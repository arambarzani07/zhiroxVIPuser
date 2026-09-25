#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f"missing patch anchor: {label}")
    return text.replace(old, new, 1)


# ---- outbound worker -------------------------------------------------------
path = ROOT / "supabase/functions/daftar-outbound-sync/index.ts"
text = path.read_text()

text = replace_once(
    text,
    '  entity_kind: "customer" | "debt" | "payment";',
    '  entity_kind: "customer" | "debt" | "payment" | "general_payment";',
    "outbound event kind",
)

text = replace_once(
    text,
    '''  const { data: existingSeen, error: seenReadError } = await admin
    .from("daftar_sync_seen")
    .select("target_id")
    .eq("sync_source_id", source.id)
    .eq("entity_kind", event.entity_kind)
    .eq("source_id", remoteId)
    .maybeSingle();''',
    '''  const seenKind = event.entity_kind === "general_payment"
    ? "payment"
    : event.entity_kind;
  const { data: existingSeen, error: seenReadError } = await admin
    .from("daftar_sync_seen")
    .select("target_id")
    .eq("sync_source_id", source.id)
    .eq("entity_kind", seenKind)
    .eq("source_id", remoteId)
    .maybeSingle();''',
    "outbound delete seen read",
)

text = replace_once(
    text,
    '''    entity_kind: event.entity_kind,
    source_id: remoteId,
    target_id: existingSeen?.target_id ?? null,''',
    '''    entity_kind: seenKind,
    source_id: remoteId,
    target_id: existingSeen?.target_id ?? null,''',
    "outbound delete seen write",
)

text = replace_once(
    text,
    '''    (event.entity_kind !== "debt" && event.entity_kind !== "payment")''',
    '''    (event.entity_kind !== "debt" &&
      event.entity_kind !== "payment" &&
      event.entity_kind !== "general_payment")''',
    "outbound ambiguous delete",
)

mapping_anchor = '  if (event.entity_kind === "payment") {'
mapping = '''  if (event.entity_kind === "general_payment") {
    await assertRemoteIdAvailable(
      admin,
      source,
      "general_payment",
      remoteId,
      event.entity_id,
    );

    const { error: linkError } = await admin.from("legacy_import_links").upsert(
      {
        admin_id: source.admin_id,
        source_fingerprint: source.source_fingerprint,
        entity_kind: "general_payment",
        source_id: remoteId,
        target_id: event.entity_id,
      },
      {
        onConflict: "admin_id,source_fingerprint,entity_kind,source_id",
        ignoreDuplicates: true,
      },
    );
    if (linkError) throw linkError;

    // The remote row is a PAYMENT. A null hash means the next inbound full
    // snapshot must confirm it before official totals treat it as reflected.
    const { error: seenError } = await admin.from("daftar_sync_seen").upsert({
      sync_source_id: source.id,
      entity_kind: "payment",
      source_id: remoteId,
      target_id: event.entity_id,
      payload_hash: null,
    }, {
      onConflict: "sync_source_id,entity_kind,source_id",
      ignoreDuplicates: true,
    });
    if (seenError) throw seenError;
    return;
  }

'''
text = replace_once(text, mapping_anchor, mapping + mapping_anchor, "general mapping")

payment_anchor = '  const { data: payment, error: paymentError } = await admin.from("payments")'
general_build = '''  if (event.entity_kind === "general_payment") {
    const { data: generalPayment, error: generalError } = await admin
      .from("customer_general_payments")
      .select("id, admin_id, customer_id, amount, note, created_at")
      .eq("id", event.entity_id)
      .maybeSingle();
    if (generalError) throw generalError;
    if (!generalPayment || generalPayment.admin_id !== source.admin_id) {
      return { skip: "entity_missing" };
    }

    const effective = Object.keys(snapshot).length > 0
      ? snapshot
      : generalPayment;
    const customerId = String(
      effective.customer_id ?? generalPayment.customer_id ?? "",
    );
    const contactId = await remoteLink(admin, source, "customer", customerId);
    if (!contactId) {
      await ensureCustomerOutbox(admin, source, customerId);
      return { defer: "customer_mapping_pending" };
    }

    return {
      request: event.operation === "update"
        ? buildTransactionUpdate({
          remoteId: Number(existingRemoteId),
          userId: Number(source.legacy_user_id),
          contactId: Number(contactId),
          transactionType: "PAYMENT",
          amount: Number(effective.amount ?? generalPayment.amount ?? 0),
          currency: "IQD",
          transactionDate: String(
            effective.transaction_date ?? generalPayment.created_at ??
              new Date().toISOString(),
          ),
          note: String(effective.note ?? generalPayment.note ?? ""),
        })
        : buildTransactionCreate({
          userId: Number(source.legacy_user_id),
          contactId: Number(contactId),
          transactionType: "PAYMENT",
          amount: Number(effective.amount ?? generalPayment.amount ?? 0),
          currency: "IQD",
          transactionDate: String(
            effective.transaction_date ?? generalPayment.created_at ??
              new Date().toISOString(),
          ),
          note: String(effective.note ?? generalPayment.note ?? ""),
        }),
    };
  }

'''
text = replace_once(text, payment_anchor, general_build + payment_anchor, "general payment write")

text = text.replace(
    '(event.entity_kind === "debt" || event.entity_kind === "payment")',
    '''(event.entity_kind === "debt" ||
          event.entity_kind === "payment" ||
          event.entity_kind === "general_payment")''',
)

path.write_text(text)


# ---- inbound worker --------------------------------------------------------
path = ROOT / "supabase/functions/daftar-sync/index.ts"
text = path.read_text()

marker_anchor = '''      const { data: paymentMarker } = await admin.from("daftar_sync_seen")
        .select("source_id, payload_hash").eq("sync_source_id", source.id)
        .eq("entity_kind", "payment").eq("source_id", sourceTransactionId)
        .maybeSingle();
      if (paymentMarker) {'''

marker_replacement = '''      const generalPaymentId = await findLegacyTarget(
        admin,
        source,
        "general_payment",
        sourceTransactionId,
      );
      const { data: paymentMarker } = await admin.from("daftar_sync_seen")
        .select("source_id, payload_hash").eq("sync_source_id", source.id)
        .eq("entity_kind", "payment").eq("source_id", sourceTransactionId)
        .maybeSingle();

      if (generalPaymentId && !paymentMarker) {
        await upsertSeen(
          admin,
          source.id,
          "payment",
          sourceTransactionId,
          generalPaymentId,
          payloadHash,
        );
        counters.reused_records++;
        continue;
      }

      if (paymentMarker) {'''
text = replace_once(text, marker_anchor, marker_replacement, "inbound general lookup")

null_hash_old = '''        if (paymentMarker.payload_hash == null) {
          await upsertSeen(
            admin,
            source.id,
            "payment",
            sourceTransactionId,
            null,
            payloadHash,
          );
          counters.reused_records++;
          continue;
        }
        const { error: removeError } = await admin.rpc(
          "remove_daftar_inbound_payment",
          {
            p_admin_id: source.admin_id,
            p_source_id: source.id,
            p_remote_transaction_id: sourceTransactionId,
          },
        );'''

null_hash_new = '''        if (paymentMarker.payload_hash == null) {
          await upsertSeen(
            admin,
            source.id,
            "payment",
            sourceTransactionId,
            generalPaymentId ?? null,
            payloadHash,
          );
          counters.reused_records++;
          continue;
        }

        if (generalPaymentId) {
          const { data: localGeneral, error: localGeneralError } = await admin
            .from("customer_general_payments")
            .select("customer_id")
            .eq("id", generalPaymentId)
            .maybeSingle();
          if (localGeneralError) throw localGeneralError;
          if (!localGeneral ||
              String(localGeneral.customer_id) !== String(customerId)) {
            throw new Error(
              `general_payment_customer_mismatch:${sourceTransactionId}`,
            );
          }

          const { data: applied, error: generalUpdateError } = await admin.rpc(
            "apply_daftar_inbound_general_payment_update",
            {
              p_admin_id: source.admin_id,
              p_source_id: source.id,
              p_remote_transaction_id: sourceTransactionId,
              p_amount: transactionAmount,
              p_note: String(transaction.note ?? ""),
              p_occurred_at: occurredAt,
            },
          );
          if (generalUpdateError || applied !== true) {
            throw new Error(
              `general_payment_update_failed:${sourceTransactionId}:${
                generalUpdateError?.message ?? "not_found"
              }`,
            );
          }
          await upsertSeen(
            admin,
            source.id,
            "payment",
            sourceTransactionId,
            generalPaymentId,
            payloadHash,
          );
          counters.updated_payments++;
          continue;
        }

        const { error: removeError } = await admin.rpc(
          "remove_daftar_inbound_payment",
          {
            p_admin_id: source.admin_id,
            p_source_id: source.id,
            p_remote_transaction_id: sourceTransactionId,
          },
        );'''
text = replace_once(text, null_hash_old, null_hash_new, "inbound general update")

delete_old = '''      for (const sourceId of confirmedPayments) {
        const { error: removeError } = await admin.rpc(
          "remove_daftar_inbound_payment",
          {
            p_admin_id: source.admin_id,
            p_source_id: source.id,
            p_remote_transaction_id: sourceId,
          },
        );
        if (removeError) {
          throw new Error(
            `payment_delete_failed:${sourceId}:${removeError.message}`,
          );
        }
        await upsertSeen(
          admin,
          source.id,
          "payment",
          sourceId,
          null,
          "__deleted__",
        );'''

delete_new = '''      for (const sourceId of confirmedPayments) {
        const generalPaymentId = await findLegacyTarget(
          admin,
          source,
          "general_payment",
          sourceId,
        );
        if (generalPaymentId) {
          const { data: removed, error: generalDeleteError } = await admin.rpc(
            "remove_daftar_inbound_general_payment",
            {
              p_admin_id: source.admin_id,
              p_source_id: source.id,
              p_remote_transaction_id: sourceId,
            },
          );
          if (generalDeleteError || removed !== true) {
            throw new Error(
              `general_payment_delete_failed:${sourceId}:${
                generalDeleteError?.message ?? "not_found"
              }`,
            );
          }
        } else {
          const { error: removeError } = await admin.rpc(
            "remove_daftar_inbound_payment",
            {
              p_admin_id: source.admin_id,
              p_source_id: source.id,
              p_remote_transaction_id: sourceId,
            },
          );
          if (removeError) {
            throw new Error(
              `payment_delete_failed:${sourceId}:${removeError.message}`,
            );
          }
        }
        await upsertSeen(
          admin,
          source.id,
          "payment",
          sourceId,
          generalPaymentId ?? null,
          "__deleted__",
        );'''
text = replace_once(text, delete_old, delete_new, "inbound general delete")

path.write_text(text)

print("general payment sync patch applied")
