import { LiveReadError } from "./policy.ts";

export type DaftarFreshnessSource = {
  id: string;
  legacy_user_id: number;
  api_base_url: string;
  contacts_etag?: string | null;
  transactions_etag?: string | null;
};

export type LiveFreshnessResult = {
  liveStatus: number;
  liveLatencyMs: number;
  changed: boolean;
  validatedAt: string;
};

export type FreshnessDeps = {
  fetcher: (input: string | URL, init?: RequestInit) => Promise<Response>;
  invokeWorker: () => Promise<{ ok: boolean }>;
  now: () => number;
  sleep: (milliseconds: number) => Promise<void>;
};

const RETRYABLE = new Set([408, 425, 429]);

function retryableStatus(status: number): boolean {
  return RETRYABLE.has(status) || status >= 500;
}

function endpointUrl(source: DaftarFreshnessSource, resource: string): URL {
  const url = new URL(`${source.api_base_url.replace(/\/$/, "")}/${resource}`);
  url.searchParams.set("user_id", String(source.legacy_user_id));
  return url;
}

function failureForFetch(error: unknown): LiveReadError {
  if (
    error instanceof DOMException &&
    (error.name === "TimeoutError" || error.name === "AbortError")
  ) {
    return new LiveReadError({ kind: "timeout" }, "source_timeout");
  }
  return new LiveReadError({ kind: "network" }, "source_unreachable");
}

async function probe(
  source: DaftarFreshnessSource,
  resource: "contacts" | "transactions",
  etag: string | null | undefined,
  deps: FreshnessDeps,
): Promise<{ status: number; changed: boolean }> {
  const url = endpointUrl(source, resource);
  let lastFailure: LiveReadError | null = null;

  for (let attempt = 0; attempt < 2; attempt++) {
    let response: Response;
    try {
      response = await deps.fetcher(url, {
        method: "GET",
        headers: {
          Accept: "application/json",
          ...(etag ? { "If-None-Match": etag } : {}),
        },
        signal: AbortSignal.timeout(4_000),
      });
    } catch (error) {
      lastFailure = failureForFetch(error);
      if (attempt === 0) {
        await deps.sleep(50);
        continue;
      }
      throw lastFailure;
    }

    if (response.status === 304) {
      return { status: 304, changed: false };
    }
    if (response.ok) {
      return { status: response.status, changed: true };
    }

    const failure = new LiveReadError(
      { kind: "http", status: response.status },
      `source_http_${response.status}`,
    );
    if (!retryableStatus(response.status) || attempt === 1) throw failure;
    lastFailure = failure;
    await deps.sleep(50);
  }

  throw lastFailure ??
    new LiveReadError({ kind: "network" }, "source_unreachable");
}

export async function ensureDaftarFresh(
  source: DaftarFreshnessSource,
  deps: FreshnessDeps,
): Promise<LiveFreshnessResult> {
  const startedAt = deps.now();
  const [contacts, transactions] = await Promise.all([
    probe(source, "contacts", source.contacts_etag, deps),
    probe(source, "transactions", source.transactions_etag, deps),
  ]);

  const changed = contacts.changed || transactions.changed;
  if (changed) {
    const worker = await deps.invokeWorker();
    if (!worker.ok) {
      throw new LiveReadError({ kind: "integrity" }, "normalization_failed");
    }
  }

  const finishedAt = deps.now();
  return {
    liveStatus: Math.max(contacts.status, transactions.status),
    liveLatencyMs: Math.max(0, finishedAt - startedAt),
    changed,
    validatedAt: new Date(finishedAt).toISOString(),
  };
}
