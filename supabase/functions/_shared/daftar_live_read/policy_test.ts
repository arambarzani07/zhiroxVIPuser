import {
  assertEquals,
  assertFalse,
} from "jsr:@std/assert@1";
import {
  isFallbackEligible,
  isMirrorStale,
} from "./policy.ts";

Deno.test("fallbacks on timeout, 408, 425, 429 and 5xx", () => {
  assertEquals(isFallbackEligible({ kind: "timeout" }), true);
  for (const status of [408, 425, 429, 500, 503]) {
    assertEquals(isFallbackEligible({ kind: "http", status }), true);
  }
});

Deno.test("does not fallback on auth, unsupported or integrity failures", () => {
  for (
    const kind of [
      "authentication",
      "authorization",
      "unsupported",
      "integrity",
    ] as const
  ) {
    assertFalse(isFallbackEligible({ kind }));
  }
  assertFalse(isFallbackEligible({ kind: "http", status: 401 }));
  assertFalse(isFallbackEligible({ kind: "http", status: 403 }));
  assertFalse(isFallbackEligible({ kind: "http", status: 422 }));
});

Deno.test("mirror becomes stale after configured threshold", () => {
  const asOf = "2026-09-20T00:00:00.000Z";
  assertFalse(
    isMirrorStale(
      asOf,
      300,
      Date.parse("2026-09-20T00:04:59.000Z"),
    ),
  );
  assertEquals(
    isMirrorStale(
      asOf,
      300,
      Date.parse("2026-09-20T00:05:01.000Z"),
    ),
    true,
  );
});
