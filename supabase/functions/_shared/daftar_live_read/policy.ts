import type {
  LiveFailure,
  LiveReadEnvelope,
  ReadSource,
} from "./types.ts";

export type {
  DaftarLiveReadOperation,
  LiveFailure,
  LiveReadEnvelope,
  ReadSource,
} from "./types.ts";
export { LiveReadError } from "./types.ts";

export function successEnvelope<T>(input: {
  source: ReadSource;
  asOf: string | null;
  stale: boolean;
  fallbackReason: string | null;
  data: T;
}): LiveReadEnvelope<T> {
  return {
    ok: true,
    source: input.source,
    as_of: input.asOf,
    stale: input.stale,
    fallback_reason: input.fallbackReason,
    data: input.data,
  };
}

export function isFallbackEligible(failure: LiveFailure): boolean {
  if (failure.kind === "timeout" || failure.kind === "network") return true;
  if (failure.kind !== "http") return false;
  return failure.status === 408 ||
    failure.status === 425 ||
    failure.status === 429 ||
    failure.status >= 500;
}

export function isMirrorStale(
  asOf: string | null,
  staleAfterSeconds: number,
  nowMs = Date.now(),
): boolean {
  if (!asOf) return true;
  const parsed = Date.parse(asOf);
  if (!Number.isFinite(parsed)) return true;
  return nowMs - parsed > staleAfterSeconds * 1000;
}
