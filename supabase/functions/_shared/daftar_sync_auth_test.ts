import { assertEquals } from "jsr:@std/assert@1";
import {
  authorizeDaftarSyncRequest,
  sha256Hex,
} from "./daftar_sync_auth.ts";

Deno.test("ordinary user bearer cannot invoke daftar-sync internally", async () => {
  const allowed = await authorizeDaftarSyncRequest({
    authorizationHeader: "Bearer user-token",
    providedSecret: "",
    serviceCredential: "service-token",
    expectedSecretHash: await sha256Hex("trigger-secret"),
  });
  assertEquals(allowed, false);
});

Deno.test("service bearer can invoke daftar-sync without trigger secret", async () => {
  const allowed = await authorizeDaftarSyncRequest({
    authorizationHeader: "Bearer service-token",
    providedSecret: "",
    serviceCredential: "service-token",
    expectedSecretHash: await sha256Hex("trigger-secret"),
  });
  assertEquals(allowed, true);
});

Deno.test("dedicated trigger secret still authorizes cron and gateway", async () => {
  const allowed = await authorizeDaftarSyncRequest({
    authorizationHeader: null,
    providedSecret: "trigger-secret",
    serviceCredential: "service-token",
    expectedSecretHash: await sha256Hex("trigger-secret"),
  });
  assertEquals(allowed, true);
});
