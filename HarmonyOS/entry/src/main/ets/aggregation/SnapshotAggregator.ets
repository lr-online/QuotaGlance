import { DailyUsage, Money, UsageSnapshot } from '../providers/UsageSnapshot';

// Cross-account aggregation engine. Mirrors
// Sources/QuotaGlanceCore/Aggregation/SnapshotAggregator.swift semantics:
// enabled-account filtering + sortOrder ordering, balances summed per
// currency, today cost/requests only when ALL ordered snapshots expose them,
// Int64 overflow detection on request sums, a 7-day daily-usage window ending
// at max(latest entry day, local day of now), mixed-currency -> empty daily
// usage, and the isPartial rule. Money amounts stay canonical decimal
// strings; summation is exact string arithmetic (result scale = widest
// operand scale, matching Swift Decimal addition) so the contract fixtures'
// amount strings round-trip exactly.

// Health as aggregation needs it: only the stale/unavailable distinction
// feeds isPartial, so the Swift SnapshotFailure payload is dropped.
export type AggregateHealth = 'healthy' | 'belowThreshold' | 'stale' | 'unavailable';

// The account fields aggregation reads — a structural subset of
// storage/AccountStore.Account (which carries provider/profile on top).
export interface AggregateAccount {
  id: string;
  displayName: string;
  isEnabled: boolean;
  sortOrder: number;
}

// Mirror of the Swift AccountSnapshot input shape.
export interface AggregateSnapshotInput {
  accountID: string;
  displayName: string;
  usage?: UsageSnapshot;
  health: AggregateHealth;
}

// Output row: the snapshot with the owning account's display name attached,
// in aggregate order (Swift also copies provider/detectedProfile/
// lowBalanceThreshold, which aggregation itself never reads — omitted here).
export interface AggregateAccountSnapshot {
  accountID: string;
  displayName: string;
  usage?: UsageSnapshot;
  health: AggregateHealth;
}

// Mirror of Swift Domain/UsageSnapshot.swift's AggregateSnapshot.
export interface AggregateSnapshot {
  balances: Money[];
  todayActualCost?: Money;
  todayRequests?: number;
  dailyUsage: DailyUsage[];
  accounts: AggregateAccountSnapshot[];
  isPartial: boolean;
}

// Time seam: the evaluation instant plus the local zone as minutes east of
// UTC (`-new Date().getTimezoneOffset()`). Contract tests pass 0 (UTC),
// mirroring the Swift suite's fixed GMT calendar.
export interface AggregationClock {
  nowMs: number;
  timeZoneOffsetMinutes: number;
}

const DAY_MS: number = 86400000;
// Int64 bounds as doubles: 2^63 is exactly representable, 2^63-1 is not, so
// the max is checked as an exclusive bound.
const INT64_EXCLUSIVE_MAX: number = 9223372036854775808; // 2^63
const INT64_MIN: number = -9223372036854775808; // -2^63

export function aggregateSnapshots(
  accounts: AggregateAccount[],
  snapshots: AggregateSnapshotInput[],
  clock: AggregationClock
): AggregateSnapshot {
  const enabled = accounts.filter((account: AggregateAccount) => account.isEnabled);
  enabled.sort((a: AggregateAccount, b: AggregateAccount) => {
    if (a.sortOrder !== b.sortOrder) {
      return a.sortOrder - b.sortOrder;
    }
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
  });
  const snapshotsByID = new Map<string, AggregateSnapshotInput>();
  for (const snapshot of snapshots) {
    if (!snapshotsByID.has(snapshot.accountID)) {
      snapshotsByID.set(snapshot.accountID, snapshot);
    }
  }
  const ordered: AggregateAccountSnapshot[] = [];
  for (const account of enabled) {
    const snapshot = snapshotsByID.get(account.id);
    if (snapshot === undefined) {
      continue;
    }
    ordered.push({
      accountID: snapshot.accountID,
      displayName: account.displayName,
      usage: snapshot.usage,
      health: snapshot.health
    });
  }

  const balanceValues: Money[] = [];
  for (const snapshot of ordered) {
    const usage = snapshot.usage;
    if (usage === undefined) {
      continue;
    }
    for (const balance of usage.balances) {
      balanceValues.push(balance.available);
    }
  }
  const balances = sumMoneyByCurrency(balanceValues);

  const todayCostValues: Money[] = [];
  for (const snapshot of ordered) {
    const cost = snapshot.usage?.spend?.today ?? snapshot.usage?.today?.actualCost;
    if (cost !== undefined) {
      todayCostValues.push(cost);
    }
  }
  const todayCost = todayCostValues.length === ordered.length
    ? sumMoney(todayCostValues)
    : undefined;

  const todayRequestValues: number[] = [];
  for (const snapshot of ordered) {
    const requests = snapshot.usage?.today?.requests;
    if (requests !== undefined) {
      todayRequestValues.push(requests);
    }
  }
  const hasAllTodayRequests = todayRequestValues.length === ordered.length;
  const todayRequests = hasAllTodayRequests ? sumIntegers(todayRequestValues) : undefined;
  const todayRequestsOverflowed = hasAllTodayRequests
    && todayRequestValues.length > 0
    && todayRequests === undefined;

  const dailyUsage = makeDailyUsage(ordered, clock);

  let isPartial = ordered.length !== enabled.length || todayRequestsOverflowed;
  if (!isPartial) {
    for (const snapshot of ordered) {
      if (snapshot.health === 'stale' || snapshot.health === 'unavailable') {
        isPartial = true;
        break;
      }
    }
  }

  const result: AggregateSnapshot = {
    balances: balances,
    dailyUsage: dailyUsage,
    accounts: ordered,
    isPartial: isPartial
  };
  if (todayCost !== undefined) {
    result.todayActualCost = todayCost;
  }
  if (todayRequests !== undefined) {
    result.todayRequests = todayRequests;
  }
  return result;
}

function sumMoneyByCurrency(values: Money[]): Money[] {
  const currencies: string[] = [];
  const byCurrency = new Map<string, Money[]>();
  for (const value of values) {
    const existing = byCurrency.get(value.currency);
    if (existing === undefined) {
      byCurrency.set(value.currency, [value]);
      currencies.push(value.currency);
    } else {
      existing.push(value);
    }
  }
  currencies.sort((a: string, b: string) => a < b ? -1 : (a > b ? 1 : 0));
  const result: Money[] = [];
  for (const currency of currencies) {
    // Groups are non-empty and single-currency by construction, so sumMoney
    // cannot return undefined here.
    const sum = sumMoney(byCurrency.get(currency) as Money[]) as Money;
    result.push(sum);
  }
  return result;
}

function sumMoney(values: Money[]): Money | undefined {
  if (values.length === 0) {
    return undefined;
  }
  const currency = values[0].currency;
  const amounts: string[] = [];
  for (const value of values) {
    if (value.currency !== currency) {
      return undefined;
    }
    amounts.push(value.amount);
  }
  const sum: Money = { amount: sumDecimalStrings(amounts), currency: currency };
  return sum;
}

// Int64 mirror: ArkTS numbers are doubles, so Swift's addingReportingOverflow
// is approximated — non-integers and values outside the double-safe range are
// rejected (the contract's Int64.max input parses to 2^63 as a double and is
// rejected here), and the running total must stay a safe integer inside
// [-2^63, 2^63).
function sumIntegers(values: number[]): number | undefined {
  if (values.length === 0) {
    return undefined;
  }
  let total = 0;
  for (const value of values) {
    if (!Number.isSafeInteger(value)) {
      return undefined;
    }
    total += value;
    if (!Number.isSafeInteger(total) || total >= INT64_EXCLUSIVE_MAX || total < INT64_MIN) {
      return undefined;
    }
  }
  return total;
}

interface ParsedDayEntry {
  day: number;
  entry: DailyUsage;
}

function makeDailyUsage(
  snapshots: AggregateAccountSnapshot[],
  clock: AggregationClock
): DailyUsage[] {
  const entries: DailyUsage[] = [];
  for (const snapshot of snapshots) {
    const usage = snapshot.usage;
    if (usage === undefined || usage.dailyUsage === undefined) {
      continue;
    }
    for (const entry of usage.dailyUsage) {
      entries.push(entry);
    }
  }
  if (entries.length === 0) {
    return [];
  }
  // Swift computes `entries.first?.actualCost.currency ?? fallbackCurrency`
  // with fallbackCurrency = the single summed balance currency; the non-empty
  // guard above makes the first entry always win, so the fallback is
  // provably unreachable and is not modeled here.
  const currency: string = entries[0].actualCost.currency;
  for (const entry of entries) {
    if (entry.actualCost.currency !== currency) {
      return [];
    }
  }

  const parsed: ParsedDayEntry[] = [];
  for (const entry of entries) {
    const day = dayIndexFromDateText(entry.date);
    if (day !== null) {
      parsed.push({ day: day, entry: entry });
    }
  }
  if (parsed.length === 0) {
    return [];
  }

  const localDay = Math.floor((clock.nowMs + clock.timeZoneOffsetMinutes * 60000) / DAY_MS);
  let endDay = localDay;
  for (const item of parsed) {
    endDay = Math.max(endDay, item.day);
  }
  const grouped = new Map<number, DailyUsage[]>();
  for (const item of parsed) {
    const existing = grouped.get(item.day);
    if (existing === undefined) {
      grouped.set(item.day, [item.entry]);
    } else {
      existing.push(item.entry);
    }
  }

  const result: DailyUsage[] = [];
  for (let index = 0; index < 7; index++) {
    const day = endDay + index - 6;
    const values = grouped.get(day) ?? [];
    const amounts: string[] = [];
    const requestValues: number[] = [];
    const tokenValues: number[] = [];
    for (const value of values) {
      amounts.push(value.actualCost.amount);
      if (value.requests !== undefined) {
        requestValues.push(value.requests);
      }
      if (value.totalTokens !== undefined) {
        tokenValues.push(value.totalTokens);
      }
    }
    const daily: DailyUsage = {
      date: formatDayIndex(day),
      actualCost: { amount: sumDecimalStrings(amounts), currency: currency }
    };
    const requests = sumIntegers(requestValues);
    if (requests !== undefined) {
      daily.requests = requests;
    }
    const totalTokens = sumIntegers(tokenValues);
    if (totalTokens !== undefined) {
      daily.totalTokens = totalTokens;
    }
    result.push(daily);
  }
  return result;
}

// 'yyyy-MM-dd' -> day index (days since epoch in the shifted-UTC day space).
// Roundtrip-checked so normalized overflow dates (e.g. 2026-02-30) are
// rejected the way a strict DateFormatter parse is.
function dayIndexFromDateText(text: string): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (match === null) {
    return null;
  }
  const ms = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  const day = Math.floor(ms / DAY_MS);
  return formatDayIndex(day) === text ? day : null;
}

function formatDayIndex(day: number): string {
  const date = new Date(day * DAY_MS);
  const year = String(date.getUTCFullYear()).padStart(4, '0');
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const dayOfMonth = String(date.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${dayOfMonth}`;
}

// MARK: - Exact decimal-string addition

// Mirrors SpecEngine's exact decimal-string approach (subtractDecimalStrings):
// doubles would render float noise (0.1 + 0.2) that the exact-string fixture
// comparison cannot tolerate. Unlike subtraction, summation PRESERVES the
// widest fractional scale of the operands ("12.00" + "3.00" -> "15.00"),
// matching Swift Decimal addition, which the aggregation fixtures pin.
// Exponent-only inputs fall back to double arithmetic, as SpecEngine does.
interface PlainDecimal {
  negative: boolean;
  intPart: string;
  fracPart: string;
}

function toPlainDecimal(raw: string): PlainDecimal | null {
  let text = raw;
  if (/[eE]/.test(text)) {
    const rendered = String(Number(text));
    if (/[eE]/.test(rendered)) {
      return null;
    }
    text = rendered;
  }
  const match = /^([+-]?)(\d*)(?:\.(\d*))?$/.exec(text);
  if (match === null) {
    return null;
  }
  let intPart = match[2];
  const fracPart = match[3] ?? '';
  if (intPart.length === 0 && fracPart.length === 0) {
    return null;
  }
  if (intPart.length === 0) {
    intPart = '0';
  }
  const plain: PlainDecimal = { negative: match[1] === '-', intPart: intPart, fracPart: fracPart };
  return plain;
}

function addDigitStrings(a: string, b: string): string {
  let carry = 0;
  let i = a.length - 1;
  let j = b.length - 1;
  let result = '';
  while (i >= 0 || j >= 0 || carry > 0) {
    const da = i >= 0 ? a.charCodeAt(i) - 48 : 0;
    const db = j >= 0 ? b.charCodeAt(j) - 48 : 0;
    const sum = da + db + carry;
    result = String(sum % 10) + result;
    carry = Math.floor(sum / 10);
    i--;
    j--;
  }
  return result;
}

function compareDigitStrings(a: string, b: string): number {
  if (a.length !== b.length) {
    return a.length < b.length ? -1 : 1;
  }
  return a === b ? 0 : (a < b ? -1 : 1);
}

// Requires a >= b.
function subtractDigitStrings(a: string, b: string): string {
  let borrow = 0;
  let i = a.length - 1;
  let j = b.length - 1;
  let result = '';
  while (i >= 0) {
    let da = a.charCodeAt(i) - 48 - borrow;
    const db = j >= 0 ? b.charCodeAt(j) - 48 : 0;
    if (da < db) {
      da += 10;
      borrow = 1;
    } else {
      borrow = 0;
    }
    result = String(da - db) + result;
    i--;
    j--;
  }
  return result.replace(/^0+(?=\d)/, '');
}

// Sums canonical decimal amount strings exactly. The result keeps the widest
// fractional scale of the operands (Swift Decimal semantics: "544.05" +
// "100.00" -> "644.05"); an empty list yields "0" (the Decimal.zero seed), and
// a zero total collapses to "0".
function sumDecimalStrings(amounts: string[]): string {
  if (amounts.length === 0) {
    return '0';
  }
  const plains: PlainDecimal[] = [];
  for (const raw of amounts) {
    const plain = toPlainDecimal(raw);
    if (plain === null) {
      let total = 0;
      for (const value of amounts) {
        total += Number(value);
      }
      return String(total);
    }
    plains.push(plain);
  }
  let fracLength = 0;
  for (const plain of plains) {
    fracLength = Math.max(fracLength, plain.fracPart.length);
  }
  let negative = false;
  let digits = '0';
  for (const plain of plains) {
    let scaled = (plain.intPart + plain.fracPart.padEnd(fracLength, '0')).replace(/^0+/, '');
    if (scaled.length === 0) {
      scaled = '0';
    }
    if (negative === plain.negative) {
      digits = addDigitStrings(digits, scaled);
    } else {
      const order = compareDigitStrings(digits, scaled);
      if (order === 0) {
        digits = '0';
        negative = false;
      } else if (order > 0) {
        digits = subtractDigitStrings(digits, scaled);
      } else {
        digits = subtractDigitStrings(scaled, digits);
        negative = plain.negative;
      }
    }
  }
  digits = digits.padStart(fracLength + 1, '0');
  let intPart = fracLength === 0 ? digits : digits.substring(0, digits.length - fracLength);
  const fracPart = fracLength === 0 ? '' : digits.substring(digits.length - fracLength);
  intPart = intPart.replace(/^0+(?=\d)/, '');
  if (/^0*$/.test(intPart + fracPart)) {
    return '0';
  }
  const sign = negative ? '-' : '';
  return fracLength === 0 ? `${sign}${intPart}` : `${sign}${intPart}.${fracPart}`;
}
