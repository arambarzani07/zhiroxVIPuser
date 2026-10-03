import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
};

const supportedMimeTypes = new Set(["image/jpeg", "image/png", "image/webp"]);
const maxDecodedBytes = 8 * 1024 * 1024;
const maxBase64Chars = Math.ceil(maxDecodedBytes / 3) * 4 + 16;

function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed.default ?? Object.values(parsed)[0] ?? null;
  } catch (_) {
    return raw;
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function normalizeBase64(value: unknown): string {
  if (typeof value !== "string") return "";
  const trimmed = value.trim();
  const comma = trimmed.indexOf(",");
  const candidate = trimmed.startsWith("data:") && comma >= 0
    ? trimmed.slice(comma + 1)
    : trimmed;
  return candidate.replace(/\s+/g, "");
}

function isValidBase64(value: string): boolean {
  if (!value || value.length > maxBase64Chars || value.length % 4 !== 0) return false;
  return /^[A-Za-z0-9+/]*={0,2}$/.test(value);
}

function decodedSize(value: string): number {
  const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
  return Math.max(0, Math.floor((value.length * 3) / 4) - padding);
}

function normalizeDigits(value: string): string {
  const map: Record<string, string> = {
    "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
    "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
    "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
    "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
  };
  return value.replace(/[٠-٩۰-۹]/g, (char) => map[char] ?? char);
}

function unique<T>(values: T[]): T[] {
  return [...new Set(values)];
}

function extractAmounts(text: string) {
  const normalized = normalizeDigits(text).replace(/\u00a0/g, " ");
  const results: Array<{ raw: string; value: number; currency: "IQD" | "USD" | "unknown" }> = [];
  const pattern = /(?:\$\s*)?\b\d{1,3}(?:[,. ]\d{3})+(?:[.,]\d{1,2})?\b|(?:\$\s*)?\b\d{3,9}(?:[.,]\d{1,2})?\b/g;
  for (const match of normalized.matchAll(pattern)) {
    const raw = match[0].trim();
    const nearbyStart = Math.max(0, (match.index ?? 0) - 12);
    const nearbyEnd = Math.min(normalized.length, (match.index ?? 0) + raw.length + 12);
    const nearby = normalized.slice(nearbyStart, nearbyEnd).toLowerCase();
    let currency: "IQD" | "USD" | "unknown" = "unknown";
    if (/\$|usd|دۆلار|دولار/.test(nearby)) currency = "USD";
    if (/iqd|د\.ع|دینار|دينار/.test(nearby)) currency = "IQD";
    const cleaned = raw
      .replace(/\$/g, "")
      .replace(/\s/g, "")
      .replace(/,(?=\d{3}(?:\D|$))/g, "")
      .replace(/\.(?=\d{3}(?:\D|$))/g, "")
      .replace(",", ".");
    const value = Number(cleaned);
    if (!Number.isFinite(value) || value <= 0 || value > 10_000_000_000) continue;
    results.push({ raw, value, currency });
  }
  const dedup = new Map<string, { raw: string; value: number; currency: "IQD" | "USD" | "unknown" }>();
  for (const item of results) {
    dedup.set(`${item.value}:${item.currency}`, item);
  }
  return [...dedup.values()].slice(0, 20);
}

function extractDates(text: string): string[] {
  const normalized = normalizeDigits(text);
  const out: string[] = [];
  const patterns = [
    /\b(20\d{2})[\/-](0?[1-9]|1[0-2])[\/-](0?[1-9]|[12]\d|3[01])\b/g,
    /\b(0?[1-9]|[12]\d|3[01])[\/-](0?[1-9]|1[0-2])[\/-](20\d{2})\b/g,
  ];
  for (let index = 0; index < patterns.length; index++) {
    for (const match of normalized.matchAll(patterns[index])) {
      let year: string;
      let month: string;
      let day: string;
      if (index === 0) {
        year = match[1]; month = match[2]; day = match[3];
      } else {
        day = match[1]; month = match[2]; year = match[3];
      }
      out.push(`${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}`);
    }
  }
  return unique(out).slice(0, 10);
}

function extractPhones(text: string): string[] {
  const normalized = normalizeDigits(text);
  const matches = normalized.match(/(?:\+?964\s?7\d{2}|07\d{2})[\s-]?\d{3}[\s-]?\d{4}/g) ?? [];
  return unique(matches.map((value) => value.replace(/[\s-]/g, ""))).slice(0, 10);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = envJsonKey("SUPABASE_SECRET_KEYS") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) return json({ error: "server_not_configured" }, 500);

    const authorization = req.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
    if (!token) return json({ error: "unauthorized" }, 401);

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    const user = authData.user;
    if (authError || !user) return json({ error: "unauthorized" }, 401);

    const { data: profile } = await admin
      .from("profiles")
      .select("id, admin_id, role, active, approved, is_system_owner")
      .eq("id", user.id)
      .maybeSingle();
    if (!profile || profile.active !== true || profile.approved !== true) {
      return json({ error: "account_inactive" }, 403);
    }
    if (!["admin", "employee"].includes(String(profile.role)) && profile.is_system_owner !== true) {
      return json({ error: "forbidden" }, 403);
    }

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch (_) {
      return json({ error: "invalid_json" }, 400);
    }

    const mimeType = String(body.mimeType ?? body.mime_type ?? "").toLowerCase().trim();
    if (!supportedMimeTypes.has(mimeType)) {
      return json({ error: "unsupported_image_type" }, 415);
    }

    const imageBase64 = normalizeBase64(body.imageBase64 ?? body.image_base64);
    if (!isValidBase64(imageBase64)) return json({ error: "invalid_image" }, 400);
    const bytes = decodedSize(imageBase64);
    if (bytes <= 0 || bytes > maxDecodedBytes) return json({ error: "image_too_large" }, 413);

    const apiKey = envJsonKey("GOOGLE_VISION_API_KEY");
    if (!apiKey) return json({ error: "google_vision_not_configured" }, 503);

    const rawHints = Array.isArray(body.languageHints ?? body.language_hints)
      ? (body.languageHints ?? body.language_hints) as unknown[]
      : [];
    const languageHints = rawHints
      .map((value) => String(value).trim())
      .filter((value) => /^[A-Za-z-]{2,12}$/.test(value))
      .slice(0, 5);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20_000);
    let upstream: Response;
    try {
      upstream = await fetch(
        `https://vision.googleapis.com/v1/images:annotate?key=${encodeURIComponent(apiKey)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            requests: [{
              image: { content: imageBase64 },
              features: [{ type: "DOCUMENT_TEXT_DETECTION", maxResults: 1 }],
              ...(languageHints.length > 0 ? { imageContext: { languageHints } } : {}),
            }],
          }),
          signal: controller.signal,
        },
      );
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        return json({ error: "google_vision_timeout" }, 504);
      }
      return json({ error: "google_vision_unavailable" }, 502);
    } finally {
      clearTimeout(timeout);
    }

    if (!upstream.ok) {
      console.error("google_vision_error", upstream.status);
      if (upstream.status === 429) return json({ error: "google_vision_rate_limited" }, 429);
      return json({ error: "google_vision_failed" }, 502);
    }

    const payload = await upstream.json();
    const result = payload?.responses?.[0] ?? {};
    if (result?.error) {
      console.error("google_vision_response_error", result.error?.code ?? "unknown");
      return json({ error: "google_vision_failed" }, 502);
    }

    const fullText = String(
      result?.fullTextAnnotation?.text ?? result?.textAnnotations?.[0]?.description ?? "",
    ).trim();
    const pages = Array.isArray(result?.fullTextAnnotation?.pages)
      ? result.fullTextAnnotation.pages
      : [];
    const confidences: number[] = [];
    const languages: string[] = [];
    for (const page of pages) {
      if (typeof page?.confidence === "number") confidences.push(page.confidence);
      for (const language of page?.property?.detectedLanguages ?? []) {
        if (language?.languageCode) languages.push(String(language.languageCode));
      }
    }
    const confidence = confidences.length > 0
      ? confidences.reduce((sum, value) => sum + value, 0) / confidences.length
      : null;

    const amounts = extractAmounts(fullText);
    const dates = extractDates(fullText);
    const phones = extractPhones(fullText);
    const bestAmount = amounts.length > 0
      ? amounts.reduce((best, item) => item.value > best.value ? item : best, amounts[0])
      : null;

    return json({
      text: fullText,
      text_length: fullText.length,
      confidence,
      detected_languages: unique(languages),
      candidates: {
        amounts,
        dates,
        phones,
      },
      suggested: {
        amount: bestAmount,
        date: dates[0] ?? null,
      },
      requires_confirmation: true,
      persisted: false,
      provider: "google_cloud_vision",
    });
  } catch (error) {
    console.error("google_vision_ocr_unhandled", error instanceof Error ? error.message : "unknown");
    return json({ error: "ocr_failed" }, 500);
  }
});
