# syntax=docker/dockerfile:1.7

# Opt-in extension dependencies at build time (space-separated directory names).
ARG OPENCLAW_EXTENSIONS=""
ARG OPENCLAW_VARIANT=default
ARG OPENCLAW_DOCKER_APT_UPGRADE=1
ARG OPENCLAW_NODE_BOOKWORM_IMAGE="node:24-bookworm@sha256:3a09aa6354567619221ef6c45a5051b671f953f0a1924d1f819ffb236e520e6b"
ARG OPENCLAW_NODE_BOOKWORM_DIGEST="sha256:3a09aa6354567619221ef6c45a5051b671f953f0a1924d1f819ffb236e520e6b"
ARG OPENCLAW_NODE_BOOKWORM_SLIM_IMAGE="node:24-bookworm-slim@sha256:e8e2e91b1378f83c5b2dd15f0247f34110e2fe895f6ca7719dbb780f929368eb"
ARG OPENCLAW_NODE_BOOKWORM_SLIM_DIGEST="sha256:e8e2e91b1378f83c5b2dd15f0247f34110e2fe895f6ca7719dbb780f929368eb"

FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS ext-deps
ARG OPENCLAW_EXTENSIONS
COPY extensions /tmp/extensions
RUN mkdir -p /out && \
    for ext in $OPENCLAW_EXTENSIONS; do \
      if [ -f "/tmp/extensions/$ext/package.json" ]; then \
        mkdir -p "/out/$ext" && \
        cp "/tmp/extensions/$ext/package.json" "/out/$ext/package.json"; \
      fi; \
    done

# ── Stage 2: Build ──────────────────────────────────────────────
FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS build
RUN set -eux; \
    for attempt in 1 2 3 4 5; do \
      if curl --retry 5 --retry-all-errors --retry-delay 2 -fsSL https://bun.sh/install | bash; then \
        break; \
      fi; \
      if [ "$attempt" -eq 5 ]; then exit 1; fi; \
      sleep $((attempt * 2)); \
    done
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY --from=ext-deps /out/ ./extensions/
RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    NODE_OPTIONS=--max-old-space-size=2048 pnpm install --frozen-lockfile
COPY . .
RUN for dir in /app/extensions /app/.agent /app/.agents; do \
      if [ -d "$dir" ]; then \
        find "$dir" -type d -exec chmod 755 {} +; \
        find "$dir" -type f -exec chmod 644 {} +; \
      fi; \
    done
RUN pnpm canvas:a2ui:bundle || (mkdir -p src/canvas-host/a2ui && echo "/* stub */" > src/canvas-host/a2ui/a2ui.bundle.js)
RUN pnpm build:docker
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

FROM build AS runtime-assets
RUN CI=true pnpm prune --prod && \
    find dist -type f \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.map' \) -delete

# ── Runtime base images ─────────────────────────────────────────
FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS base-default
FROM ${OPENCLAW_NODE_BOOKWORM_SLIM_IMAGE} AS base-slim

# ── Stage 3: Runtime ────────────────────────────────────────────
FROM base-${OPENCLAW_VARIANT}
WORKDIR /app
RUN --mount=type=cache,id=openclaw-bookworm-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=openclaw-bookworm-apt-lists,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      procps hostname curl git lsof openssl
RUN chown node:node /app
COPY --from=runtime-assets --chown=node:node /app/dist ./dist
COPY --from=runtime-assets --chown=node:node /app/node_modules ./node_modules
COPY --from=runtime-assets --chown=node:node /app/package.json .
COPY --from=runtime-assets --chown=node:node /app/openclaw.mjs .
COPY --from=runtime-assets --chown=node:node /app/extensions ./extensions
COPY --from=runtime-assets --chown=node:node /app/skills ./skills
COPY --from=runtime-assets --chown=node:node /app/docs ./docs
COPY --chmod=755 scripts/docker/render-entrypoint.sh /app/render-entrypoint.sh

ENV OPENCLAW_BUNDLED_PLUGINS_DIR=/app/extensions
ENV COREPACK_HOME=/usr/local/share/corepack
RUN install -d -m 0755 "$COREPACK_HOME" && corepack enable && \
    corepack prepare "$(node -p "require('./package.json').packageManager")" --activate
RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw && chmod 755 /app/openclaw.mjs

ENV NODE_ENV=production
ENV NODE_OPTIONS=--max-old-space-size=384
ENV PORT=8080
ENV OPENCLAW_GATEWAY_PORT=8080
USER node

HEALTHCHECK --interval=3m --timeout=10s --start-period=15s --retries=3 \
  CMD curl -f http://localhost:${PORT:-8080}/health || exit 1

CMD ["/app/render-entrypoint.sh"]
