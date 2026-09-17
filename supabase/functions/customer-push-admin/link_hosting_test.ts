import { assertEquals } from "jsr:@std/assert@1";
import {
  CUSTOMER_PUSH_STATIC_URL,
  routeCustomerPushLink,
} from "../customer-push-link/index.ts";

const token = "a".repeat(64);
const publicBase = "https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push-link";
const runtimeBase = "https://hsoyfbtpvwfmjokudznx.supabase.co/customer-push-link";
const staticPortal =
  "https://raw.githack.com/arambarzani07/zhiroxVIPuser/user-source/customer-push-web/index.html";

function expectRedirect(url: string, expected: string) {
  const response = routeCustomerPushLink(new Request(url));
  assertEquals(response.status, 307);
  assertEquals(response.headers.get("location"), expected);
}

Deno.test("stable customer push gateway keeps bearer token out of the static host request", () => {
  assertEquals(new URL(CUSTOMER_PUSH_STATIC_URL).search, "");
  for (const base of [publicBase, runtimeBase]) {
    expectRedirect(
      `${base}?token=${token}`,
      `${CUSTOMER_PUSH_STATIC_URL}#token=${token}`,
    );
  }
});

Deno.test("stable customer push gateway preserves a token-free portal entry", () => {
  expectRedirect(publicBase, staticPortal);
});

Deno.test("gateway no longer serves HTML directly from Supabase Edge", async () => {
  const response = routeCustomerPushLink(new Request(`${publicBase}?token=${token}`));
  assertEquals(response.headers.get("content-type")?.includes("text/html") ?? false, false);
  assertEquals(await response.text(), "");
});
