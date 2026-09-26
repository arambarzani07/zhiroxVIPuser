import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

function envJsonKey(name) {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed.default ?? Object.values(parsed)[0] ?? null;
  } catch (_) {
    return raw;
  }
}

function num(value) {
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
}

function isoDay(value) {
  return value.toISOString().slice(0, 10);
}

function dayDiff(later, earlier) {
  return Math.max(0, Math.floor((later.getTime() - earlier.getTime()) / 86_400_000));
}

function normalizeText(value) {
  return String(value ?? "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\u064B-\u065F\u0670\u06D6-\u06ED]/g, "")
    .replace(/[ىي]/g, "ی")
    .replace(/ك/g, "ک")
    .replace(/[أإآ]/g, "ا")
    .replace(/ؤ/g, "و")
    .replace(/ۀ/g, "ە")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function textTokens(value) {
  return normalizeText(value)
    .split(" ")
    .filter((token) => token.length >= 3);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function redactQuestion(question, customers, matchedCustomer) {
  let safe = String(question ?? "").slice(0, 1000);

  const matchedId = matchedCustomer ? String(matchedCustomer.id ?? "") : "";
  const variants = [];
  for (const customer of customers) {
    const name = String(customer.name ?? "").trim();
    if (!name) continue;
    const replacement = String(customer.id ?? "") === matchedId ? "C_TARGET" : "[CUSTOMER]";
    variants.push({ value: name, replacement });
    for (const token of name.split(/[^\p{L}\p{N}]+/gu)) {
      if (token.length >= 3) variants.push({ value: token, replacement });
    }
  }

  variants.sort((a, b) => b.value.length - a.value.length);
  const seen = new Set();
  for (const variant of variants) {
    const key = variant.value.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    safe = safe.replace(new RegExp(escapeRegExp(variant.value), "giu"), variant.replacement);
  }

  safe = safe
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/giu, "[EMAIL]")
    .replace(/\+?\d[\d\s().-]{7,}\d/g, "[PHONE]");

  return safe.trim();
}

function findCustomerMatch(question, customers) {
  const q = normalizeText(question);
  if (!q) return { status: "none", customer: null, matches: [] };
  const qTokens = new Set(q.split(" "));

  const scored = [];
  for (const customer of customers) {
    const name = normalizeText(customer.name);
    if (!name) continue;
    let score = 0;
    if (name.length >= 3 && q.includes(name)) score = 2000 + name.length;
    for (const token of textTokens(customer.name)) {
      if (qTokens.has(token)) score = Math.max(score, 1000 + token.length);
    }
    if (score > 0) scored.push({ customer, score });
  }

  scored.sort((a, b) => b.score - a.score);
  if (!scored.length) return { status: "none", customer: null, matches: [] };

  const topScore = scored[0].score;
  const top = scored.filter((item) => item.score === topScore);
  if (top.length > 1) {
    return { status: "ambiguous", customer: null, matches: top.map((item) => item.customer) };
  }

  return { status: "matched", customer: scored[0].customer, matches: [scored[0].customer] };
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function fetchAll(admin, table, columns, configure) {
  const rows = [];
  const pageSize = 1000;
  for (let from = 0; ; from += pageSize) {
    let query = admin.from(table).select(columns);
    query = configure(query);
    const { data, error } = await query.range(from, from + pageSize - 1);
    if (error) throw error;
    const page = data ?? [];
    rows.push(...page);
    if (page.length < pageSize) break;
  }
  return rows;
}

async function fetchDebtsForCustomers(admin, customerIds) {
  const rows = [];
  const chunkSize = 80;
  const pageSize = 1000;
  for (let i = 0; i < customerIds.length; i += chunkSize) {
    const chunk = customerIds.slice(i, i + chunkSize);
    for (let from = 0; ; from += pageSize) {
      const { data, error } = await admin
        .from("debts")
        .select("id,customer_id,amount,remaining,due_date,status,currency,created_at")
        .in("customer_id", chunk)
        .eq("is_deleted", false)
        .range(from, from + pageSize - 1);
      if (error) throw error;
      const page = data ?? [];
      rows.push(...page);
      if (page.length < pageSize) break;
    }
  }
  return rows;
}

async function fetchPaymentsForCustomers(admin, customerIds) {
  const rows = [];
  const chunkSize = 80;
  const pageSize = 1000;
  for (let i = 0; i < customerIds.length; i += chunkSize) {
    const chunk = customerIds.slice(i, i + chunkSize);
    for (let from = 0; ; from += pageSize) {
      const { data, error } = await admin
        .from("payments")
        .select("id,debt_id,amount,created_at,debts!inner(customer_id,currency)")
        .in("debts.customer_id", chunk)
        .range(from, from + pageSize - 1);
      if (error) throw error;
      const page = data ?? [];
      rows.push(...page);
      if (page.length < pageSize) break;
    }
  }
  return rows;
}

function buildSnapshot(profile, customers, debts, payments) {
  const now = new Date();
  const today = isoDay(now);
  const in7 = new Date(now.getTime() + 7 * 86_400_000);
  const in30 = new Date(now.getTime() + 30 * 86_400_000);
  const ago30 = new Date(now.getTime() - 30 * 86_400_000);
  const ago60 = new Date(now.getTime() - 60 * 86_400_000);

  let openCount = 0;
  let remainingIqd = 0;
  let remainingUsd = 0;
  let overdueCount = 0;
  let overdueIqd = 0;
  let due7Count = 0;
  let due7Iqd = 0;
  let due30Count = 0;
  let due30Iqd = 0;

  const riskByCustomer = new Map();

  for (const debt of debts) {
    const remaining = Math.max(0, num(debt.remaining));
    if (remaining <= 0) continue;
    const currency = String(debt.currency ?? "IQD").toUpperCase();
    const customerId = String(debt.customer_id ?? "");
    const dueRaw = String(debt.due_date ?? "");
    const due = dueRaw ? new Date(`${dueRaw}T00:00:00Z`) : null;
    openCount += 1;

    if (currency === "USD") {
      remainingUsd += remaining;
      continue;
    }
    if (currency !== "IQD") continue;

    remainingIqd += remaining;
    const risk = riskByCustomer.get(customerId) ?? {
      remaining: 0,
      overdue: 0,
      maxOverdueDays: 0,
      openCount: 0,
    };
    risk.remaining += remaining;
    risk.openCount += 1;

    if (due && !Number.isNaN(due.getTime())) {
      const dueDay = isoDay(due);
      if (dueDay < today) {
        overdueCount += 1;
        overdueIqd += remaining;
        risk.overdue += remaining;
        risk.maxOverdueDays = Math.max(risk.maxOverdueDays, dayDiff(now, due));
      } else if (due <= in7) {
        due7Count += 1;
        due7Iqd += remaining;
      } else if (due <= in30) {
        due30Count += 1;
        due30Iqd += remaining;
      }
    }
    riskByCustomer.set(customerId, risk);
  }

  let collected30 = 0;
  let collectedPrev30 = 0;
  for (const payment of payments) {
    const relation = payment.debts;
    const debtRow = Array.isArray(relation) ? relation[0] : relation;
    const currency = String(
      debtRow && typeof debtRow === "object" ? debtRow.currency ?? "IQD" : "IQD",
    ).toUpperCase();
    if (currency !== "IQD") continue;

    const at = new Date(String(payment.created_at ?? ""));
    if (Number.isNaN(at.getTime())) continue;
    const amount = Math.max(0, num(payment.amount));
    if (at >= ago30) collected30 += amount;
    else if (at >= ago60 && at < ago30) collectedPrev30 += amount;
  }

  const customerName = new Map(
    customers.map((row) => [String(row.id ?? ""), String(row.name ?? "کڕیار")]),
  );
  const topRisks = [];
  const avgOutstanding = riskByCustomer.size > 0
    ? remainingIqd / riskByCustomer.size
    : 0;

  for (const [customerId, risk] of riskByCustomer.entries()) {
    if (!customerId) continue;
    const overdueRatio = risk.remaining > 0 ? risk.overdue / risk.remaining : 0;
    const amountFactor = avgOutstanding > 0
      ? Math.min(1, risk.remaining / (avgOutstanding * 3))
      : 0;
    const score = Math.round(Math.min(
      100,
      overdueRatio * 45 +
        Math.min(30, risk.maxOverdueDays / 3) +
        amountFactor * 20 +
        Math.min(5, risk.openCount),
    ));

    topRisks.push({
      customer_id: customerId,
      name: customerName.get(customerId) ?? "کڕیار",
      risk_score: score,
      remaining_iqd: Math.round(risk.remaining),
      overdue_iqd: Math.round(risk.overdue),
      max_overdue_days: risk.maxOverdueDays,
      open_debts: risk.openCount,
    });
  }

  topRisks.sort((a, b) =>
    b.risk_score - a.risk_score ||
    b.overdue_iqd - a.overdue_iqd ||
    b.remaining_iqd - a.remaining_iqd
  );

  const overdueRatio = remainingIqd > 0 ? overdueIqd / remainingIqd : 0;
  const highRiskCount = topRisks.filter((r) => r.risk_score >= 70).length;
  const highRiskRatio = customers.length > 0 ? highRiskCount / customers.length : 0;
  const healthScore = Math.max(
    0,
    Math.min(100, Math.round(100 - overdueRatio * 65 - highRiskRatio * 35)),
  );

  const collectionChangePercent = collectedPrev30 > 0
    ? Math.round(((collected30 - collectedPrev30) / collectedPrev30) * 1000) / 10
    : (collected30 > 0 ? 100 : 0);

  return {
    generated_at: now.toISOString(),
    market_name: String(profile.market_name ?? ""),
    health_score: healthScore,
    totals: {
      customers: customers.length,
      active_customers: customers.filter((c) => c.active === true).length,
      open_debts: openCount,
      total_remaining_iqd: Math.round(remainingIqd),
      total_remaining_usd: Math.round(remainingUsd * 100) / 100,
      overdue_count: overdueCount,
      overdue_iqd: Math.round(overdueIqd),
      due_7_count: due7Count,
      due_7_iqd: Math.round(due7Iqd),
      due_30_count: due30Count,
      due_30_iqd: Math.round(due30Iqd),
      collected_30_iqd: Math.round(collected30),
      collected_previous_30_iqd: Math.round(collectedPrev30),
      collection_change_percent: collectionChangePercent,
      high_risk_customers: highRiskCount,
    },
    top_risks: topRisks.slice(0, 12),
  };
}

function buildCustomerContext(customer, debts, payments, snapshot) {
  if (!customer) return null;
  const customerId = String(customer.id ?? "");
  const now = new Date();
  const today = isoDay(now);

  let remainingIqd = 0;
  let remainingUsd = 0;
  let overdueIqd = 0;
  let overdueUsd = 0;
  let originalIqd = 0;
  let originalUsd = 0;
  let openDebts = 0;
  let maxOverdueDays = 0;

  const debtIds = new Set();
  for (const debt of debts) {
    if (String(debt.customer_id ?? "") !== customerId) continue;
    debtIds.add(String(debt.id ?? ""));
    const currency = String(debt.currency ?? "IQD").toUpperCase();
    const amount = Math.max(0, num(debt.amount));
    const remaining = Math.max(0, num(debt.remaining));
    if (currency === "USD") originalUsd += amount;
    else if (currency === "IQD") originalIqd += amount;

    if (remaining <= 0) continue;
    openDebts += 1;
    if (currency === "USD") remainingUsd += remaining;
    else if (currency === "IQD") remainingIqd += remaining;

    const dueRaw = String(debt.due_date ?? "");
    if (!dueRaw) continue;
    const due = new Date(`${dueRaw}T00:00:00Z`);
    if (Number.isNaN(due.getTime()) || isoDay(due) >= today) continue;
    maxOverdueDays = Math.max(maxOverdueDays, dayDiff(now, due));
    if (currency === "USD") overdueUsd += remaining;
    else if (currency === "IQD") overdueIqd += remaining;
  }

  let paid30Iqd = 0;
  let paid30Usd = 0;
  const ago30 = new Date(now.getTime() - 30 * 86_400_000);
  for (const payment of payments) {
    if (!debtIds.has(String(payment.debt_id ?? ""))) continue;
    const createdAt = new Date(String(payment.created_at ?? ""));
    if (Number.isNaN(createdAt.getTime()) || createdAt < ago30) continue;
    const relation = payment.debts;
    const debtRow = Array.isArray(relation) ? relation[0] : relation;
    const currency = String(
      debtRow && typeof debtRow === "object" ? debtRow.currency ?? "IQD" : "IQD",
    ).toUpperCase();
    if (currency === "USD") paid30Usd += Math.max(0, num(payment.amount));
    else if (currency === "IQD") paid30Iqd += Math.max(0, num(payment.amount));
  }

  const riskRow = (snapshot.top_risks ?? []).find(
    (risk) => String(risk.customer_id ?? "") === customerId,
  );

  return {
    customer_id: customerId,
    name: String(customer.name ?? "کڕیار"),
    alias: "C_TARGET",
    active: customer.active === true,
    risk_score: riskRow ? num(riskRow.risk_score) : 0,
    open_debts: openDebts,
    original_iqd: Math.round(originalIqd),
    original_usd: Math.round(originalUsd * 100) / 100,
    remaining_iqd: Math.round(remainingIqd),
    remaining_usd: Math.round(remainingUsd * 100) / 100,
    overdue_iqd: Math.round(overdueIqd),
    overdue_usd: Math.round(overdueUsd * 100) / 100,
    max_overdue_days: maxOverdueDays,
    paid_30_iqd: Math.round(paid30Iqd),
    paid_30_usd: Math.round(paid30Usd * 100) / 100,
  };
}

function extractOutputText(payload) {
  if (typeof payload?.output_text === "string" && payload.output_text.trim()) {
    return payload.output_text.trim();
  }
  for (const item of payload?.output ?? []) {
    if (item?.type !== "message") continue;
    for (const content of item?.content ?? []) {
      if (content?.type === "output_text" && typeof content.text === "string") {
        return content.text.trim();
      }
    }
  }
  return "";
}

function replaceAliases(text, aliasMap) {
  let result = String(text ?? "");
  const aliases = [...aliasMap.keys()].sort((a, b) => b.length - a.length);
  for (const alias of aliases) {
    const name = String(aliasMap.get(alias)?.name ?? alias);
    result = result.replace(new RegExp(`\\b${escapeRegExp(alias)}\\b`, "g"), name);
  }
  return result;
}

async function runOpenAI(apiKey, model, adminId, snapshot, question, customers, debts, payments) {
  const match = findCustomerMatch(question, customers);
  const target = match.status === "matched"
    ? buildCustomerContext(match.customer, debts, payments, snapshot)
    : null;
  const safeQuestion = question
    ? redactQuestion(question, customers, match.customer)
    : "پوختەی دۆخ، مەترسییەکان و ٣ هەنگاوی پێشنیارکراو بۆ بەڕێوەبەر بنووسە.";

  const topRiskSource = (snapshot.top_risks ?? []).slice(0, 8);
  const aliases = topRiskSource.map((risk, index) => ({
    alias: `C${index + 1}`,
    risk_score: risk.risk_score,
    remaining_iqd: risk.remaining_iqd,
    overdue_iqd: risk.overdue_iqd,
    max_overdue_days: risk.max_overdue_days,
    open_debts: risk.open_debts,
  }));

  const aliasMap = new Map(
    topRiskSource.map((risk, index) => [`C${index + 1}`, risk]),
  );
  if (target) aliasMap.set("C_TARGET", target);

  const userPayload = {
    market: {
      health_score: snapshot.health_score,
      totals: snapshot.totals,
    },
    top_risk_customers: aliases,
    customer_match_status: match.status,
    target_customer: target
      ? {
          alias: "C_TARGET",
          active: target.active,
          risk_score: target.risk_score,
          open_debts: target.open_debts,
          original_iqd: target.original_iqd,
          original_usd: target.original_usd,
          remaining_iqd: target.remaining_iqd,
          remaining_usd: target.remaining_usd,
          overdue_iqd: target.overdue_iqd,
          overdue_usd: target.overdue_usd,
          max_overdue_days: target.max_overdue_days,
          paid_30_iqd: target.paid_30_iqd,
          paid_30_usd: target.paid_30_usd,
        }
      : null,
    ambiguous_customer_count: match.status === "ambiguous" ? match.matches.length : 0,
    question: safeQuestion,
  };

  const body = {
    model,
    store: false,
    reasoning: { effort: "low" },
    max_output_tokens: 1800,
    safety_identifier: await sha256Hex(`zhirox:${adminId}`),
    prompt_cache_key: "zhirox-intelligence-v2",
    instructions:
      "You are ZHIROX AI for a debt-management market. Answer only in Kurdish Sorani. Use only supplied figures and never invent facts. Customer aliases such as C1 or C_TARGET are privacy placeholders. If target_customer exists, answer questions about that customer from target_customer figures. If customer_match_status is ambiguous, explain that the user should enter the full customer name. Recommendations are advisory only and must not make automatic financial decisions.",
    input: JSON.stringify(userPayload),
    text: {
      verbosity: "low",
      format: {
        type: "json_schema",
        name: "zhirox_intelligence",
        strict: true,
        schema: {
          type: "object",
          additionalProperties: false,
          properties: {
            executive_summary: { type: "string" },
            health_assessment: { type: "string" },
            alerts: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  severity: { type: "string", enum: ["high", "medium", "low"] },
                  title: { type: "string" },
                  detail: { type: "string" },
                },
                required: ["severity", "title", "detail"],
              },
            },
            recommendations: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  priority: { type: "string", enum: ["high", "medium", "low"] },
                  title: { type: "string" },
                  why: { type: "string" },
                  action: { type: "string" },
                },
                required: ["priority", "title", "why", "action"],
              },
            },
            customer_insights: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  customer_alias: { type: "string" },
                  assessment: { type: "string" },
                  next_action: { type: "string" },
                },
                required: ["customer_alias", "assessment", "next_action"],
              },
            },
            confidence: { type: "number", minimum: 0, maximum: 1 },
          },
          required: [
            "executive_summary",
            "health_assessment",
            "alerts",
            "recommendations",
            "customer_insights",
            "confidence",
          ],
        },
      },
    },
  };

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error("OpenAI request failed", response.status, payload?.error?.code ?? "unknown");
    throw new Error(`openai_${response.status}`);
  }

  const outputText = extractOutputText(payload);
  if (!outputText) throw new Error("openai_empty_output");

  const parsed = JSON.parse(outputText);
  const customerInsights = Array.isArray(parsed.customer_insights)
    ? parsed.customer_insights.map((item) => {
        const risk = aliasMap.get(String(item.customer_alias ?? ""));
        return {
          customer_id: risk?.customer_id ?? null,
          customer_name: risk?.name ?? String(item.customer_alias ?? ""),
          risk_score: risk?.risk_score ?? null,
          assessment: replaceAliases(item.assessment, aliasMap),
          next_action: replaceAliases(item.next_action, aliasMap),
        };
      })
    : [];

  const alerts = Array.isArray(parsed.alerts)
    ? parsed.alerts.slice(0, 6).map((item) => ({
        ...item,
        title: replaceAliases(item.title, aliasMap),
        detail: replaceAliases(item.detail, aliasMap),
      }))
    : [];

  const recommendations = Array.isArray(parsed.recommendations)
    ? parsed.recommendations.slice(0, 6).map((item) => ({
        ...item,
        title: replaceAliases(item.title, aliasMap),
        why: replaceAliases(item.why, aliasMap),
        action: replaceAliases(item.action, aliasMap),
      }))
    : [];

  return {
    model: String(payload.model ?? model),
    generated_at: new Date().toISOString(),
    executive_summary: replaceAliases(parsed.executive_summary, aliasMap),
    health_assessment: replaceAliases(parsed.health_assessment, aliasMap),
    alerts,
    recommendations,
    customer_insights: customerInsights.slice(0, 8),
    confidence: Math.max(0, Math.min(1, num(parsed.confidence))),
    matched_customer_id: target?.customer_id ?? null,
    usage: payload.usage
      ? {
          input_tokens: num(payload.usage.input_tokens),
          output_tokens: num(payload.usage.output_tokens),
          total_tokens: num(payload.usage.total_tokens),
        }
      : null,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const secret = envJsonKey("SUPABASE_SECRET_KEYS") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) return json({ error: "server_not_configured" }, 500);

  const admin = createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "unauthorized" }, 401);

    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "unauthorized" }, 401);

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("id,role,active,approved,subscription_end,market_name,is_system_owner")
      .eq("id", authData.user.id)
      .maybeSingle();

    if (profileError || !profile) return json({ error: "profile_not_found" }, 403);
    if (profile.role !== "admin" || profile.is_system_owner === true) {
      return json({ error: "admin_required" }, 403);
    }
    if (profile.active !== true || profile.approved !== true) {
      return json({ error: "account_inactive" }, 403);
    }
    if (profile.subscription_end) {
      const end = Date.parse(String(profile.subscription_end));
      if (Number.isFinite(end) && end < Date.now()) {
        return json({ error: "subscription_expired" }, 403);
      }
    }

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "snapshot");
    const question = String(body.question ?? "").trim().slice(0, 1000);
    if (!["snapshot", "analyze"].includes(action)) {
      return json({ error: "unsupported_action" }, 400);
    }

    const adminId = String(profile.id);
    const customers = await fetchAll(
      admin,
      "profiles",
      "id,name,active",
      (q) => q.eq("admin_id", adminId).eq("role", "customer"),
    );
    const customerIds = customers.map((row) => String(row.id ?? "")).filter(Boolean);

    const [debts, payments] = await Promise.all([
      fetchDebtsForCustomers(admin, customerIds),
      fetchPaymentsForCustomers(admin, customerIds),
    ]);

    const snapshot = buildSnapshot(profile, customers, debts, payments);
    const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim() ?? "";
    const model = Deno.env.get("OPENAI_INTELLIGENCE_MODEL")?.trim() ||
      "gpt-5.6-luna";

    if (action === "snapshot") {
      return json({
        ok: true,
        ai_enabled: apiKey.length > 0,
        model: apiKey.length > 0 ? model : null,
        snapshot,
      });
    }

    if (!apiKey) {
      return json({
        ok: true,
        ai_enabled: false,
        error: "ai_not_configured",
        snapshot,
      });
    }

    try {
      const ai = await runOpenAI(
        apiKey,
        model,
        adminId,
        snapshot,
        question,
        customers,
        debts,
        payments,
      );
      return json({ ok: true, ai_enabled: true, snapshot, ai });
    } catch (error) {
      console.error(error);
      return json({
        ok: true,
        ai_enabled: true,
        error: error instanceof Error ? error.message : "ai_failed",
        snapshot,
      });
    }
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "internal_error" }, 500);
  }
});
