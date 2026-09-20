export type DaftarLiveReadOperation =
  | "customer_directory"
  | "customer_finance_snapshot"
  | "customer_timeline"
  | "customer_debts_page"
  | "debt_detail"
  | "debt_payments"
  | "customer_all_debts"
  | "admin_dashboard"
  | "admin_all_debts"
  | "employee_stats";

export type ReadSource = "live" | "mirror" | "zhirox_primary";

export type LiveFailure =
  | { kind: "timeout" }
  | { kind: "network" }
  | { kind: "http"; status: number }
  | { kind: "authentication" }
  | { kind: "authorization" }
  | { kind: "unsupported" }
  | { kind: "integrity" };

export class LiveReadError extends Error {
  constructor(
    readonly failure: LiveFailure,
    message: string,
  ) {
    super(message);
    this.name = "LiveReadError";
  }
}

export type LiveReadEnvelope<T> = {
  ok: true;
  source: ReadSource;
  as_of: string | null;
  stale: boolean;
  fallback_reason: string | null;
  data: T;
};
