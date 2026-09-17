import webpush from "npm:web-push@3.6.7";
import { randomHexToken } from "./crypto.ts";

export type CustomerPushRuntime = {
  vapidPublicKey: string;
  vapidPrivateKey: string;
  vapidSubject: string;
  workerSecret: string;
  rateLimitSalt: string;
};

function parseRuntime(data: unknown): CustomerPushRuntime | null {
  if (!data || typeof data !== "object") return null;
  const map = data as Record<string, unknown>;
  const runtime = {
    vapidPublicKey: String(map.customer_push_vapid_public ?? ""),
    vapidPrivateKey: String(map.customer_push_vapid_private ?? ""),
    vapidSubject: String(map.customer_push_vapid_subject ?? ""),
    workerSecret: String(map.customer_push_worker_secret ?? ""),
    rateLimitSalt: String(map.customer_push_rate_limit_salt ?? ""),
  };
  return Object.values(runtime).every((value) => value.length > 0) ? runtime : null;
}

// The Edge Functions intentionally use an ungenerated Supabase schema. The
// concrete rpc() return is an awaitable PostgREST builder rather than a plain
// Promise, so keep this backend-only adapter untyped instead of narrowing valid
// RPC calls to `never` during standalone Deno type-checking.
export async function loadOrInitializePushRuntime(
  admin: any,
): Promise<CustomerPushRuntime> {
  const loaded = await admin.rpc("get_customer_push_runtime_config_service");
  if (!loaded.error) {
    const parsed = parseRuntime(loaded.data);
    if (parsed) return parsed;
  }

  const keys = webpush.generateVAPIDKeys();
  const initialized = await admin.rpc(
    "initialize_customer_push_runtime_config_service",
    {
      p_vapid_public: keys.publicKey,
      p_vapid_private: keys.privateKey,
      p_vapid_subject: "mailto:notifications@zhirox.com",
      p_worker_secret: randomHexToken(32),
      p_rate_limit_salt: randomHexToken(32),
    },
  );
  if (initialized.error) throw initialized.error;
  const parsed = parseRuntime(initialized.data);
  if (!parsed) throw new Error("customer_push_runtime_not_initialized");
  return parsed;
}
