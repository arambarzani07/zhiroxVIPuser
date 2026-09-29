import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const SOURCE_URL = "https://t.me/s/iraqborsa";
const SOURCE_KEY = "iraqborsa_public_mirror";
const SOURCE_LABEL = "بورصة العراق";
const CACHE_MS = 2 * 60 * 1000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });

function env(name: string): string {
  const raw = Deno.env.get(name) ?? "";
  try {
    const parsed = JSON.parse(raw);
    return String(parsed.default ?? Object.values(parsed)[0] ?? "");
  } catch (_) {
    return raw;
  }
}

function decodeEntities(value: string): string {
  const named: Record<string, string> = {
    amp: "&",
    lt: "<",
    gt: ">",
    quot: '"',
    apos: "'",
    nbsp: " ",
  };
  return value
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) =>
      String.fromCodePoint(Number.parseInt(hex, 16))
    )
    .replace(/&#([0-9]+);/g, (_, dec) =>
      String.fromCodePoint(Number.parseInt(dec, 10))
    )
    .replace(/&([a-z]+);/gi, (all, name) => named[name.toLowerCase()] ?? all);
}

function htmlToText(html: string): string {
  return decodeEntities(
    html
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<\/(?:div|p|article|section|time)>/gi, "\n")
      .replace(/<[^>]+>/g, " ")
  )
    .replace(/\r/g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function latinDigits(value: string): string {
  const arabic = "٠١٢٣٤٥٦٧٨٩";
  const persian = "۰۱۲۳۴۵۶۷۸۹";
  return Array.from(value)
    .map((ch) => {
      const a = arabic.indexOf(ch);
      if (a >= 0) return String(a);
      const p = persian.indexOf(ch);
      if (p >= 0) return String(p);
      return ch;
    })
    .join("");
}

function normalizeRate(raw: string): number | null {
  const digits = latinDigits(raw).replace(/[^0-9]/g, "");
  const value = Number.parseInt(digits, 10);
  if (!Number.isFinite(value) || value < 100_000 || value > 300_000) return null;
  return value;
}

function normalizeWords(value: string): string {
  return value
    .normalize("NFKC")
    .replace(/[ىي]/g, "ی")
    .replace(/ك/g, "ک")
    .replace(/[أإآ]/g, "ا")
    .replace(/ۀ/g, "ە")
    .toLowerCase();
}

function detectCity(value: string): string | null {
  const t = normalizeWords(value);
  if (/هەولێر|هولێر|اربیل|اربيل|erbil/.test(t)) return "erbil";
  if (/سلێمانی|سلێمانى|سلیمانی|سليمانی|السليمانيه|السليمانية|sulaimani|sulaymaniyah/.test(t)) {
    return "sulaimani";
  }
  if (/دهۆک|دهوک|دهوك|duhok/.test(t)) return "duhok";
  if (/بغداد|baghdad/.test(t)) return "baghdad";
  return null;
}

function detectVariant(value: string): string {
  const t = normalizeWords(value);
  if (/پێنجی|پينجی|پنجی|پێنجى|pengi/.test(t)) return "pengi";
  if (/سوور|سور|احمر|red/.test(t)) return "red";
  return "general";
}

type ParsedRate = {
  source: string;
  city: string;
  variant: string;
  rate_iqd_per_100_usd: number;
  source_url: string;
  source_published_at: string | null;
  retrieved_at: string;
  updated_at: string;
};

function latestPublishedAt(html: string): string | null {
  const values = [...html.matchAll(/datetime="([^"]+)"/g)]
    .map((m) => Date.parse(m[1]))
    .filter((v) => Number.isFinite(v));
  if (!values.length) return null;
  return new Date(Math.max(...values)).toISOString();
}

function parseRates(html: string): ParsedRate[] {
  const text = htmlToText(html);
  const now = new Date().toISOString();
  const publishedAt = latestPublishedAt(html);
  const byKey = new Map<string, ParsedRate>();

  for (const line of text.split("\n")) {
    if (!/100\s*\$/.test(latinDigits(line))) continue;
    const normalized = latinDigits(line);
    const match = normalized.match(
      /100\s*\$\s*=\s*([0-9٠-٩۰-۹]{2,3}(?:[\s,،٬.]?[0-9٠-٩۰-۹]{3})?)\s*(.*)$/u,
    );
    if (!match) continue;

    const rate = normalizeRate(match[1]);
    const context = match[2] ?? "";
    const city = detectCity(context);
    if (rate == null || city == null) continue;

    const variant = detectVariant(context);
    const key = `${city}:${variant}`;
    byKey.set(key, {
      source: SOURCE_KEY,
      city,
      variant,
      rate_iqd_per_100_usd: rate,
      source_url: SOURCE_URL,
      source_published_at: publishedAt,
      retrieved_at: now,
      updated_at: now,
    });
  }

  return [...byKey.values()];
}

function sortRows(rows: any[]): any[] {
  const cityOrder = ["erbil", "sulaimani", "duhok", "baghdad"];
  const variantOrder = ["pengi", "red", "general"];
  return [...rows].sort((a, b) => {
    const c = cityOrder.indexOf(String(a.city)) - cityOrder.indexOf(String(b.city));
    if (c !== 0) return c;
    return variantOrder.indexOf(String(a.variant)) - variantOrder.indexOf(String(b.variant));
  });
}

async function cachedRows(admin: ReturnType<typeof createClient>) {
  const { data, error } = await admin
    .from("market_exchange_rates")
    .select("source,city,variant,rate_iqd_per_100_usd,source_url,source_published_at,retrieved_at,updated_at")
    .eq("source", SOURCE_KEY);
  if (error) throw error;
  return sortRows(data ?? []);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (!["GET", "POST"].includes(request.method)) return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = env("SUPABASE_URL");
  const serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "server_not_configured" }, 500);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let cached: any[] = [];
  try {
    cached = await cachedRows(admin);
  } catch (_) {
    // A source refresh can still succeed if cache reading is temporarily unavailable.
  }

  const newest = cached
    .map((row) => Date.parse(String(row.retrieved_at ?? row.updated_at ?? "")))
    .filter((v) => Number.isFinite(v))
    .sort((a, b) => b - a)[0];

  if (newest && Date.now() - newest < CACHE_MS) {
    return json({
      source: SOURCE_LABEL,
      source_transport: "telegram_public_mirror",
      source_url: SOURCE_URL,
      stale: false,
      cached: true,
      rates: cached,
    });
  }

  try {
    const response = await fetch(SOURCE_URL, {
      headers: {
        "User-Agent": "Mozilla/5.0 ZHIROX/1.0 market-rate-fetcher",
        "Accept": "text/html,application/xhtml+xml",
      },
      redirect: "follow",
    });
    if (!response.ok) throw new Error(`source_http_${response.status}`);

    const html = await response.text();
    const parsed = parseRates(html);
    if (!parsed.length) throw new Error("source_parse_empty");

    const { error: upsertError } = await admin
      .from("market_exchange_rates")
      .upsert(parsed, { onConflict: "source,city,variant" });
    if (upsertError) throw upsertError;

    const fresh = await cachedRows(admin);
    return json({
      source: SOURCE_LABEL,
      source_transport: "telegram_public_mirror",
      source_url: SOURCE_URL,
      stale: false,
      cached: false,
      rates: fresh,
    });
  } catch (error) {
    if (cached.length) {
      return json({
        source: SOURCE_LABEL,
        source_transport: "telegram_public_mirror",
        source_url: SOURCE_URL,
        stale: true,
        cached: true,
        source_error: error instanceof Error ? error.message : "source_unavailable",
        rates: cached,
      });
    }
    return json({
      error: "market_rate_unavailable",
      detail: error instanceof Error ? error.message : String(error),
    }, 502);
  }
});
