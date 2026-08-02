// Named parse strategy `miniMaxModelRemains` (Contracts/README.md, "Named
// parse strategies"): derives quota windows from MiniMax `model_remains`
// entries. Direct windows win over interval/weekly windows, counted forms win
// over percent forms, an absent status counts as active (!= 0), and
// timestamps are epoch seconds or milliseconds (magnitude > 1e10 =>
// milliseconds). Mirrors the Swift MiniMaxModelRemainsStrategy.swift and the
// deleted hand-written MiniMaxProvider.ets.

import { QuotaWindow } from './UsageSnapshot';
import { asRecord, jsonDecimal, jsonString } from './SpecEngine';

export function miniMaxModelRemainsWindows(value: Object | null): QuotaWindow[] {
  if (value === null || !Array.isArray(value)) {
    return [];
  }
  const windows: QuotaWindow[] = [];
  for (const entry of value as Object[]) {
    for (const window of quotaWindowsForEntry(entry)) {
      windows.push(window);
    }
  }
  return windows;
}

function quotaWindowsForEntry(entry: Object): QuotaWindow[] {
  const direct = directQuotaWindow(entry);
  if (direct !== null) {
    return [direct];
  }
  const windows: QuotaWindow[] = [];
  // A missing status counts as active, matching Swift's `status?.value != 0`.
  if (entryDecimal(entry, 'current_interval_status') !== 0) {
    const interval = intervalQuotaWindow(entry);
    if (interval !== null) {
      windows.push(interval);
    }
  }
  if (entryDecimal(entry, 'current_weekly_status') !== 0) {
    const weekly = weeklyQuotaWindow(entry);
    if (weekly !== null) {
      windows.push(weekly);
    }
  }
  return windows;
}

function directQuotaWindow(entry: Object): QuotaWindow | null {
  const limit = entryDecimal(entry, 'total');
  const suppliedUsed = entryDecimal(entry, 'used');
  const suppliedRemaining = entryDecimal(entry, 'remains');
  if (limit === null && suppliedUsed === null && suppliedRemaining === null) {
    return null;
  }
  const used = suppliedUsed ?? subtractNumbers(limit, suppliedRemaining);
  const remaining = suppliedRemaining ?? subtractNumbers(limit, suppliedUsed);
  const window: QuotaWindow = {
    label: normalizedLabel(entryString(entry, 'label'))
      ?? `${normalizedModelName(entryString(entry, 'model_name'))} quota`,
    unit: normalizedLabel(entryString(entry, 'unit')) ?? 'requests'
  };
  if (used !== null) {
    window.used = used;
  }
  if (limit !== null) {
    window.limit = limit;
  }
  if (remaining !== null) {
    window.remaining = remaining;
  }
  const resetsAtMs = providerDateMs(entryDecimal(entry, 'reset_time') ?? entryDecimal(entry, 'end_time'));
  if (resetsAtMs !== null) {
    window.resetsAtMs = resetsAtMs;
  }
  return window;
}

function intervalQuotaWindow(entry: Object): QuotaWindow | null {
  const label = isFiveHourWindow(entryDecimal(entry, 'start_time'), entryDecimal(entry, 'end_time'))
    ? `${normalizedModelName(entryString(entry, 'model_name'))} 5-hour quota`
    : `${normalizedModelName(entryString(entry, 'model_name'))} quota`;
  return countedOrPercentWindow(
    label,
    entryDecimal(entry, 'current_interval_total_count'),
    entryDecimal(entry, 'current_interval_usage_count'),
    entryDecimal(entry, 'current_interval_remaining_percent'),
    entryDecimal(entry, 'end_time')
  );
}

function weeklyQuotaWindow(entry: Object): QuotaWindow | null {
  return countedOrPercentWindow(
    `${normalizedModelName(entryString(entry, 'model_name'))} weekly quota`,
    entryDecimal(entry, 'current_weekly_total_count'),
    entryDecimal(entry, 'current_weekly_usage_count'),
    entryDecimal(entry, 'current_weekly_remaining_percent'),
    entryDecimal(entry, 'weekly_end_time')
  );
}

function countedOrPercentWindow(
  label: string,
  total: number | null,
  used: number | null,
  remainingPercent: number | null,
  resetsAt: number | null
): QuotaWindow | null {
  if ((total !== null && total > 0) || (used !== null && used > 0)) {
    const window: QuotaWindow = { label: label, unit: 'requests' };
    if (used !== null) {
      window.used = used;
    }
    if (total !== null) {
      window.limit = total;
    }
    const remaining = subtractNumbers(total, used);
    if (remaining !== null) {
      window.remaining = remaining;
    }
    const resetsAtMs = providerDateMs(resetsAt);
    if (resetsAtMs !== null) {
      window.resetsAtMs = resetsAtMs;
    }
    return window;
  }
  if (remainingPercent !== null) {
    const remaining = Math.max(0, Math.min(100, remainingPercent));
    const window: QuotaWindow = {
      label: label,
      used: 100 - remaining,
      limit: 100,
      remaining: remaining,
      unit: '%'
    };
    const resetsAtMs = providerDateMs(resetsAt);
    if (resetsAtMs !== null) {
      window.resetsAtMs = resetsAtMs;
    }
    return window;
  }
  return null;
}

function subtractNumbers(lhs: number | null, rhs: number | null): number | null {
  if (lhs === null || rhs === null) {
    return null;
  }
  return lhs - rhs;
}

function normalizedLabel(value: string | null): string | null {
  if (value === null) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function normalizedModelName(value: string | null): string {
  return normalizedLabel(value) ?? 'Token Plan';
}

// Provider timestamps arrive as epoch seconds or milliseconds; normalize to
// epoch milliseconds (Swift providerDate's 1e10 threshold).
function providerDateMs(value: number | null): number | null {
  if (value === null) {
    return null;
  }
  const seconds = Math.abs(value) > 10000000000 ? value / 1000 : value;
  return seconds * 1000;
}

function providerDateSeconds(value: number | null): number | null {
  if (value === null) {
    return null;
  }
  return Math.abs(value) > 10000000000 ? value / 1000 : value;
}

function isFiveHourWindow(start: number | null, end: number | null): boolean {
  const startSeconds = providerDateSeconds(start);
  const endSeconds = providerDateSeconds(end);
  if (startSeconds === null || endSeconds === null) {
    return false;
  }
  return Math.abs((endSeconds - startSeconds) - 18000) < 1;
}

function entryDecimal(entry: Object, key: string): number | null {
  const record = asRecord(entry);
  if (record === null) {
    return null;
  }
  return jsonDecimal(record[key])?.value ?? null;
}

function entryString(entry: Object, key: string): string | null {
  const record = asRecord(entry);
  if (record === null) {
    return null;
  }
  return jsonString(record[key]);
}
