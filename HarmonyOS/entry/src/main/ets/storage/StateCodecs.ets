// Pure (no-Kit) serialization helpers for the small preferences-backed stores
// (FormBindingStore / AlertStateStore) plus the notification-id derivation.
// Kept Kit-free so the round-trips are verifiable in a plain tsx harness the
// same way the engines are.

// Per-form binding: which account a desktop card shows (unset = 总览/aggregate
// overview) plus the form's grid dimension as reported by the form host
// (FormDimension enum values: 1=1*2, 2=2*2, 3=2*4, 4=4*4), so every
// formProvider.updateForm push can carry the dimension for layout selection.
export interface FormBinding {
  accountId?: string;
  dimension: number;
}

export function encodeFormBindings(bindings: Map<string, FormBinding>): string {
  const obj: Record<string, FormBinding> = {};
  bindings.forEach((binding: FormBinding, formId: string) => {
    obj[formId] = binding;
  });
  return JSON.stringify(obj);
}

// Self-healing decode: malformed payloads and non-object entries drop out
// instead of throwing; a missing/invalid dimension falls back to 2 (2*2).
export function decodeFormBindings(raw: string): Map<string, FormBinding> {
  const result = new Map<string, FormBinding>();
  if (raw.length === 0) {
    return result;
  }
  let parsed: Record<string, FormBinding>;
  try {
    parsed = JSON.parse(raw) as Record<string, FormBinding>;
  } catch (error) {
    return result;
  }
  if (parsed === undefined || parsed === null || typeof parsed !== 'object') {
    return result;
  }
  const keys = Object.keys(parsed);
  for (const formId of keys) {
    const value = parsed[formId];
    if (value === undefined || value === null || typeof value !== 'object') {
      continue;
    }
    const binding: FormBinding = {
      dimension: typeof value.dimension === 'number' && value.dimension >= 1 ? value.dimension : 2
    };
    if (typeof value.accountId === 'string' && value.accountId.length > 0) {
      binding.accountId = value.accountId;
    }
    result.set(formId, binding);
  }
  return result;
}

// Per-account low-balance episode flags (Swift persists alertEpisodeActive on
// the account record; ArkTS keeps them in a separate preferences key so the
// AccountStore schema stays untouched). Only `true` flags are stored; a
// missing key means false, and deleting an account simply clears its key.
export function encodeAlertEpisodes(flags: Map<string, boolean>): string {
  const obj: Record<string, boolean> = {};
  flags.forEach((active: boolean, accountId: string) => {
    if (active) {
      obj[accountId] = true;
    }
  });
  return JSON.stringify(obj);
}

export function decodeAlertEpisodes(raw: string): Map<string, boolean> {
  const result = new Map<string, boolean>();
  if (raw.length === 0) {
    return result;
  }
  let parsed: Record<string, boolean>;
  try {
    parsed = JSON.parse(raw) as Record<string, boolean>;
  } catch (error) {
    return result;
  }
  if (parsed === undefined || parsed === null || typeof parsed !== 'object') {
    return result;
  }
  const keys = Object.keys(parsed);
  for (const accountId of keys) {
    if (parsed[accountId] === true) {
      result.set(accountId, true);
    }
  }
  return result;
}

// Stable notification id per account (FNV-1a 32-bit, masked positive): the
// same account's low-balance notification replaces itself instead of
// stacking; distinct accounts collide ~never for ≤20 accounts.
export function notificationIdForAccount(accountId: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < accountId.length; i++) {
    hash ^= accountId.charCodeAt(i);
    hash = (hash * 0x01000193) % 0x100000000;
  }
  // Keep it a positive int32 away from 0 (the "update notification 0" slot).
  return (hash & 0x7ffffffe) + 1;
}
