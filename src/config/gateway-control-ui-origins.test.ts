import { afterEach, describe, expect, it } from "vitest";
import {
  ensureControlUiAllowedOriginsForNonLoopbackBind,
  getRenderExternalOrigin,
} from "./gateway-control-ui-origins.js";

describe("gateway-control-ui-origins", () => {
  afterEach(() => {
    delete process.env.RENDER_EXTERNAL_URL;
  });

  it("returns undefined for missing render URL", () => {
    expect(getRenderExternalOrigin()).toBeUndefined();
  });

  it("returns origin from RENDER_EXTERNAL_URL", () => {
    process.env.RENDER_EXTERNAL_URL = "https://myapp.onrender.com/path";
    expect(getRenderExternalOrigin()).toBe("https://myapp.onrender.com");
  });

  it("seeds render endpoint into controlUi.allowedOrigins on non-loopback binds", () => {
    process.env.RENDER_EXTERNAL_URL = "https://myapp.onrender.com";
    const input = { gateway: { bind: "lan" as const } };

    const result = ensureControlUiAllowedOriginsForNonLoopbackBind(input as any);

    expect(result.seededOrigins).toContain("https://myapp.onrender.com");
    expect(result.config.gateway?.controlUi?.allowedOrigins).toContain("https://myapp.onrender.com");
  });
});
