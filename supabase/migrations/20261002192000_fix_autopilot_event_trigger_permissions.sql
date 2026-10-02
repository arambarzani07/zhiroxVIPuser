-- Fix Daftar sync failures caused by internal triggers attempting to write
-- to private.autopilot_events with the caller's permissions.
--
-- Keep the queue table private. Only the trigger functions execute with the
-- function owner's privileges; clients are not granted direct table access.

alter function private.enqueue_autopilot_debt_event()
  security definer;

alter function private.enqueue_autopilot_debt_event()
  set search_path = '';

alter function private.enqueue_autopilot_payment_event()
  security definer;

alter function private.enqueue_autopilot_payment_event()
  set search_path = '';
