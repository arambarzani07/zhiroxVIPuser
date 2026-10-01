import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { PDFDocument, rgb } from "npm:pdf-lib@1.17.1";
import fontkit from "npm:@pdf-lib/fontkit@1.1.1";

const A4: [number, number] = [595.28, 841.89];
const MARGIN = 42;
const MAX_STATEMENT_ROWS = 200;
let fontPromise: Promise<Uint8Array> | null = null;

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function serviceKey(): string {
  const modern = env("SUPABASE_SECRET_KEYS");
  if (modern) {
    try {
      const parsed = JSON.parse(modern) as Record<string, string>;
      const value = parsed.default ?? Object.values(parsed)[0];
      if (value) return String(value).trim();
    } catch (_) {}
  }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return Array.from(hash).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function secureEqual(left: string, right: string): Promise<boolean> {
  const [a, b] = await Promise.all([sha256Hex(left), sha256Hex(right)]);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function loadBotToken(admin: any): Promise<string> {
  const direct = env("TELEGRAM_BOT_TOKEN");
  if (direct) return direct;
  const { data, error } = await admin.rpc("get_telegram_runtime_config_service");
  if (error) return "";
  const row = Array.isArray(data) ? data[0] : data;
  return String(row?.bot_token ?? "").trim();
}

async function loadFont(): Promise<Uint8Array> {
  if (!fontPromise) {
    fontPromise = (async () => {
      const response = await fetch(
        "https://raw.githubusercontent.com/google/fonts/main/ofl/notosansarabic/NotoSansArabic%5Bwdth%2Cwght%5D.ttf",
        { signal: AbortSignal.timeout(10000) },
      );
      if (!response.ok) throw new Error(`font_${response.status}`);
      return new Uint8Array(await response.arrayBuffer());
    })();
  }
  return await fontPromise;
}

function clean(value: unknown): string {
  return String(value ?? "").replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim();
}

function fmtDate(value: unknown): string {
  const d = new Date(String(value ?? ""));
  if (!Number.isFinite(d.getTime())) return "—";
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Baghdad",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(d);
}

function fmtAmount(value: unknown, currency: unknown = "IQD"): string {
  const n = Number(value ?? 0);
  const v = Number.isFinite(n) ? n : 0;
  return String(currency ?? "IQD").toUpperCase() === "USD"
    ? `$${v.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
    : `${Math.round(v).toLocaleString("en-US")} د.ع`;
}

async function readAll(
  admin: any,
  table: string,
  select: string,
  customerId: string,
): Promise<any[]> {
  const out: any[] = [];
  for (let offset = 0; offset < 5000; offset += 1000) {
    const { data, error } = await admin
      .from(table)
      .select(select)
      .eq("customer_id", customerId)
      .range(offset, offset + 999);
    if (error) throw error;
    out.push(...(data ?? []));
    if (!data || data.length < 1000) break;
  }
  return out;
}

async function loadLedger(admin: any, customerId: string): Promise<any[]> {
  const debts = await readAll(
    admin,
    "debts",
    "id,customer_id,amount,remaining,currency,custom_date,created_at,description,is_deleted",
    customerId,
  );
  const activeDebts = debts.filter((d) => d.is_deleted !== true);
  const debtMap = new Map(activeDebts.map((d) => [String(d.id), d]));
  const debtIds = [...debtMap.keys()];
  const payments: any[] = [];

  if (debtIds.length) {
    for (let start = 0; start < debtIds.length; start += 100) {
      const chunk = debtIds.slice(start, start + 100);
      for (let offset = 0; offset < 5000; offset += 1000) {
        const { data, error } = await admin
          .from("payments")
          .select("id,debt_id,amount,created_at,note")
          .in("debt_id", chunk)
          .range(offset, offset + 999);
        if (error) throw error;
        payments.push(...(data ?? []));
        if (!data || data.length < 1000) break;
      }
    }
  }

  const general = await readAll(
    admin,
    "customer_general_payments",
    "id,customer_id,amount,created_at,note",
    customerId,
  );

  const rows: any[] = [];
  for (const d of activeDebts) {
    rows.push({
      id: d.id,
      kind: "debt",
      amount: d.amount,
      currency: d.currency || "IQD",
      occurred_at: d.custom_date || d.created_at,
      note: d.description || "",
    });
  }
  for (const p of payments) {
    const d = debtMap.get(String(p.debt_id));
    if (!d) continue;
    rows.push({
      id: p.id,
      kind: "payment",
      payment_scope: "debt",
      amount: p.amount,
      currency: d.currency || "IQD",
      occurred_at: p.created_at,
      note: p.note || "",
    });
  }
  for (const g of general) {
    rows.push({
      id: g.id,
      kind: "payment",
      payment_scope: "general",
      amount: g.amount,
      currency: "IQD",
      occurred_at: g.created_at,
      note: g.note || "",
    });
  }

  rows.sort((a, b) =>
    Date.parse(String(b.occurred_at)) - Date.parse(String(a.occurred_at)) ||
    String(a.id).localeCompare(String(b.id))
  );
  return rows.slice(0, 5000);
}

async function newPdf() {
  const bytes = await loadFont();
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const font = await pdf.embedFont(bytes, { subset: true });
  return { pdf, font };
}

function pdfHelpers(pdf: any, font: any) {
  const W = A4[0];
  const H = A4[1];
  const usable = W - MARGIN * 2;
  let page = pdf.addPage(A4);
  let y = H - 54;

  const addPage = () => {
    page = pdf.addPage(A4);
    y = H - 52;
  };
  const ensure = (height: number) => {
    if (y - height < 42) addPage();
  };
  const right = (text: string, size = 9, color = rgb(.07, .07, .07)) => {
    const t = clean(text);
    const w = font.widthOfTextAtSize(t, size);
    page.drawText(t, {
      x: Math.max(MARGIN, W - MARGIN - w),
      y,
      size,
      font,
      color,
    });
  };
  const left = (text: string, size = 8.2) => {
    page.drawText(clean(text), {
      x: MARGIN,
      y,
      size,
      font,
      color: rgb(.07, .07, .07),
    });
  };
  const wrap = (text: string, size = 8.2, max = usable) => {
    const words = clean(text).split(" ").filter(Boolean);
    const lines: string[] = [];
    let current = "";
    for (const word of words) {
      const next = current ? `${current} ${word}` : word;
      if (font.widthOfTextAtSize(next, size) <= max) current = next;
      else {
        if (current) lines.push(current);
        current = word;
      }
    }
    if (current) lines.push(current);
    return lines;
  };
  const wrapRight = (text: string, size = 8.2, max = usable) => {
    for (const lineText of wrap(text, size, max)) {
      ensure(13);
      right(lineText, size);
      y -= 13;
    }
  };
  const line = () => {
    page.drawLine({
      start: { x: MARGIN, y },
      end: { x: W - MARGIN, y },
      thickness: .45,
      color: rgb(.78, .78, .78),
    });
  };
  const down = (n: number) => {
    y -= n;
  };
  const pages = () => pdf.getPages();

  return { usable, ensure, right, left, wrapRight, line, down, pages };
}

async function statementPdf(
  current: any,
  rows: any[],
  totalRows: number,
): Promise<Uint8Array> {
  const { pdf, font } = await newPdf();
  const h = pdfHelpers(pdf, font);

  h.right("کەشف حسابی ZHIROX", 18);
  h.down(28);
  h.right(`مارکێت: ${clean(current.market_name)}`, 10);
  h.down(16);
  h.right(`کڕیار: ${clean(current.customer_name)}`, 10);
  h.down(16);
  h.right(`قەرزی ماوە: ${fmtAmount(current.remaining_iqd, "IQD")}`, 11);
  h.down(16);
  h.right(`مامەڵە پیشاندراوەکان: ${rows.length} / ${totalRows}`, 8.5);
  h.down(15);
  h.right(`بەرواری دروستکردن: ${fmtDate(new Date().toISOString())}`, 8.5);
  h.down(18);
  h.line();
  h.down(15);

  if (!rows.length) {
    h.right("هیچ مامەڵەیەک تۆمار نەکراوە.", 10);
    h.down(18);
  }

  let no = 0;
  for (const row of rows) {
    no++;
    h.ensure(42);
    const kind = row.kind === "payment" ? "پارەدان" : "قەرز";
    h.left(
      `${no}. ${fmtDate(row.occurred_at)} | ${kind} | ${fmtAmount(row.amount, row.currency)}`,
      8.2,
    );
    h.down(13);
    if (clean(row.note)) {
      h.wrapRight(`تێبینی: ${clean(row.note).slice(0, 220)}`, 7.8, h.usable - 8);
    }
    h.line();
    h.down(8);
  }

  const pages = h.pages();
  pages.forEach((pg: any, i: number) => {
    const s = `${i + 1} / ${pages.length}`;
    const w = font.widthOfTextAtSize(s, 7);
    pg.drawText(s, {
      x: (A4[0] - w) / 2,
      y: 17,
      size: 7,
      font,
      color: rgb(.45, .45, .45),
    });
  });

  return await pdf.save({ useObjectStreams: true, addDefaultPage: false, objectsPerTick: 100 });
}

async function receiptPdf(admin: any, current: any, row: any): Promise<Uint8Array> {
  const { pdf, font } = await newPdf();
  const h = pdfHelpers(pdf, font);
  let receiptNumber = "";

  if (row.payment_scope !== "general") {
    const sourceType = row.kind === "payment" ? "payment" : "debt";
    const { data } = await admin
      .from("receipt_documents")
      .select("receipt_number")
      .eq("admin_id", current.market_id)
      .eq("source_type", sourceType)
      .eq("source_id", row.id)
      .order("created_at", { ascending: false })
      .limit(1);
    receiptNumber = String(data?.[0]?.receipt_number ?? "");
  }

  h.right("پسووڵەی مامەڵە - ZHIROX", 18);
  h.down(30);
  h.right(`مارکێت: ${clean(current.market_name)}`, 10);
  h.down(18);
  h.right(`کڕیار: ${clean(current.customer_name)}`, 10);
  h.down(18);
  h.line();
  h.down(20);
  h.right(`جۆر: ${row.kind === "payment" ? "پارەدان" : "قەرز"}`, 11);
  h.down(18);
  h.right(`بڕ: ${fmtAmount(row.amount, row.currency)}`, 12);
  h.down(18);
  h.right(`کات: ${fmtDate(row.occurred_at)}`, 9);
  h.down(18);
  h.right(`قەرزی ماوەی ئێستا: ${fmtAmount(current.remaining_iqd, "IQD")}`, 10);
  h.down(18);
  if (receiptNumber) {
    h.right(`ژمارەی پسووڵە: ${receiptNumber}`, 9);
    h.down(18);
  }
  h.right(`ناسنامەی مامەڵە: ${String(row.id).slice(0, 18)}…`, 8);
  h.down(18);
  if (clean(row.note)) {
    h.wrapRight(`تێبینی: ${clean(row.note).slice(0, 500)}`, 9);
  }
  h.down(8);
  h.line();
  h.down(18);
  h.right("ئەم پسووڵەیە لە سیستەمی ZHIROX دەرکراوە.", 8.5);

  return await pdf.save({ useObjectStreams: true, addDefaultPage: false, objectsPerTick: 100 });
}

async function sendDocument(
  botToken: string,
  chatId: string,
  bytes: Uint8Array,
  filename: string,
  caption: string,
) {
  const form = new FormData();
  form.append("chat_id", chatId);
  form.append("caption", caption);
  form.append("document", new Blob([bytes], { type: "application/pdf" }), filename);
  const response = await fetch(`https://api.telegram.org/bot${botToken}/sendDocument`, {
    method: "POST",
    body: form,
    signal: AbortSignal.timeout(20000),
  });
  let body: any = {};
  try {
    body = await response.json();
  } catch (_) {}
  if (!response.ok || body?.ok !== true) {
    throw new Error(`telegram_sendDocument_${response.status}`);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { "content-type": "application/json" },
    });
  }

  const url = env("SUPABASE_URL");
  const secret = serviceKey();
  if (!url || !secret) {
    return new Response(JSON.stringify({ error: "server_not_configured" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  const admin = createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const botToken = await loadBotToken(admin);
  if (!botToken) {
    return new Response(JSON.stringify({ error: "telegram_not_configured" }), {
      status: 503,
      headers: { "content-type": "application/json" },
    });
  }

  const expected = await sha256Hex(`${botToken}:customer-pdf`);
  const provided = req.headers.get("x-zhirox-telegram-internal") ?? "";
  if (!provided || !(await secureEqual(provided, expected))) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  let body: any;
  try {
    body = await req.json();
  } catch (_) {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const chatId = String(body?.chat_id ?? "").trim();
  const action = String(body?.action ?? "").trim();
  if (!chatId || !["statement", "receipt"].includes(action)) {
    return new Response(JSON.stringify({ error: "invalid_input" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  try {
    const snap = await admin.rpc("get_telegram_customer_snapshot_service", {
      p_chat_id: chatId,
    });
    if (snap.error || !snap.data) {
      return new Response(JSON.stringify({ error: "telegram_not_linked" }), {
        status: 404,
        headers: { "content-type": "application/json" },
      });
    }

    const current = snap.data as any;
    const customerId = String(current.customer_id ?? "");
    const marketId = String(current.market_id ?? "");
    if (!customerId || !marketId) throw new Error("identity_missing");

    const { data: customer, error: customerError } = await admin
      .from("profiles")
      .select("id,admin_id,role,active,approved")
      .eq("id", customerId)
      .eq("admin_id", marketId)
      .eq("role", "customer")
      .eq("active", true)
      .eq("approved", true)
      .maybeSingle();
    if (customerError || !customer) throw new Error("tenant_identity_invalid");

    const rows = await loadLedger(admin, customerId);

    if (action === "statement") {
      const statementRows = rows.slice(0, MAX_STATEMENT_ROWS);
      const bytes = await statementPdf(current, statementRows, rows.length);
      const day = new Date().toISOString().slice(0, 10);
      await sendDocument(
        botToken,
        chatId,
        bytes,
        `ZHIROX-statement-${day}.pdf`,
        `📄 کەشف حساب • ${clean(current.market_name)}\n${statementRows.length} مامەڵەی کۆتایی لە کۆی ${rows.length}\nقەرزی ماوە: ${fmtAmount(current.remaining_iqd, "IQD")}`,
      );
    } else {
      const latest = rows[0];
      if (!latest) {
        return new Response(JSON.stringify({ ok: true, sent: false, reason: "no_transactions" }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }
      const bytes = await receiptPdf(admin, current, latest);
      await sendDocument(
        botToken,
        chatId,
        bytes,
        `ZHIROX-receipt-${String(latest.id).slice(0, 8)}.pdf`,
        `🧾 پسووڵەی کۆتا مامەڵە • ${fmtAmount(latest.amount, latest.currency)}`,
      );
    }

    return new Response(JSON.stringify({
      ok: true,
      sent: true,
      action,
      transactions: rows.length,
      statement_rows: action === "statement" ? Math.min(rows.length, MAX_STATEMENT_ROWS) : null,
    }), {
      status: 200,
      headers: { "content-type": "application/json", "cache-control": "no-store" },
    });
  } catch (error) {
    console.error(
      "telegram-customer-pdf",
      String(error instanceof Error ? error.message : error),
    );
    return new Response(JSON.stringify({ error: "document_failed" }), {
      status: 500,
      headers: { "content-type": "application/json", "cache-control": "no-store" },
    });
  }
});
