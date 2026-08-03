import { Money } from '../providers/UsageSnapshot';

// Low-balance alert batch evaluator. Mirrors
// Sources/QuotaGlanceCore/Alerts/AlertEvaluator.swift semantics: one batch
// pass over accounts, per-account threshold crossing with a `<=` comparison,
// episode debounce (notify once until the balance recovers), episode reset on
// recovery, stale/unavailable snapshots never change episode state, and
// disabled or threshold-less accounts never alert. The engine is I/O-free:
// episode state arrives on the accounts and is mutated in place (Swift inout
// semantics); the caller persists it and delivers the returned notifications.
// Threshold comparison is exact decimal-string comparison — no doubles.

export type AlertAction = 'none' | 'notify' | 'reset';

// Health as alerts need it: only the fresh vs stale/unavailable distinction
// gates evaluation, so the Swift SnapshotFailure payload is dropped.
export type AlertHealth = 'healthy' | 'belowThreshold' | 'stale' | 'unavailable';

// The account fields alerts read and mutate — a structural subset of
// storage/AccountStore.Account. lowBalanceThreshold is a canonical decimal
// amount string; alertEpisodeActive is the caller-persisted episode state.
export interface AlertAccount {
  id: string;
  displayName: string;
  isEnabled: boolean;
  lowBalanceThreshold?: string;
  alertEpisodeActive: boolean;
}

// Mirror of the Swift AccountSnapshot input shape, reduced to the fields the
// evaluator reads (owning account id, remaining, health).
export interface AlertSnapshotInput {
  accountID: string;
  remaining?: Money;
  health: AlertHealth;
}

// Mirror of Swift PendingLowBalanceNotification: the account after its
// episode-state mutation plus the remaining amount that crossed the
// threshold.
export interface PendingLowBalanceNotification {
  account: AlertAccount;
  remaining: Money;
}

// Mirror of Swift AlertBatchEvaluation.
export interface AlertBatchEvaluation {
  didChange: boolean;
  notifications: PendingLowBalanceNotification[];
}

// Mirrors Swift evaluate(accounts:freshSnapshots:). Accounts without a fresh
// snapshot, or whose fresh snapshot has no remaining amount, are skipped.
export function evaluateAlertBatch(
  accounts: AlertAccount[],
  freshSnapshots: AlertSnapshotInput[]
): AlertBatchEvaluation {
  const snapshotsByID = new Map<string, AlertSnapshotInput>();
  for (const snapshot of freshSnapshots) {
    if (!snapshotsByID.has(snapshot.accountID)) {
      snapshotsByID.set(snapshot.accountID, snapshot);
    }
  }

  let didChange = false;
  const notifications: PendingLowBalanceNotification[] = [];
  for (const account of accounts) {
    const snapshot = snapshotsByID.get(account.id);
    if (snapshot === undefined || snapshot.remaining === undefined) {
      continue;
    }
    const action = evaluateSnapshot(account, snapshot);
    if (action === 'none') {
      continue;
    }
    didChange = true;
    if (action === 'notify') {
      const remaining = snapshot.remaining as Money;
      notifications.push({ account: account, remaining: remaining });
    }
  }
  return { didChange: didChange, notifications: notifications };
}

// Mirrors Swift evaluate(account:freshSnapshot:): a mismatched account id or
// a stale/unavailable snapshot is inert; fresh health defers to the threshold
// check with the snapshot's remaining amount.
function evaluateSnapshot(account: AlertAccount, freshSnapshot: AlertSnapshotInput): AlertAction {
  if (freshSnapshot.accountID !== account.id) {
    return 'none';
  }
  if (freshSnapshot.health === 'stale' || freshSnapshot.health === 'unavailable') {
    return 'none';
  }
  return evaluateEpisode(account, freshSnapshot.remaining?.amount);
}

// Mirrors Swift evaluate(account:freshRemaining:): crossing at or below the
// threshold notifies once per episode; recovering above it resets the
// episode.
function evaluateEpisode(account: AlertAccount, freshRemaining?: string): AlertAction {
  if (!account.isEnabled
    || account.lowBalanceThreshold === undefined
    || freshRemaining === undefined) {
    return 'none';
  }

  if (compareDecimalStrings(freshRemaining, account.lowBalanceThreshold) <= 0) {
    if (account.alertEpisodeActive) {
      return 'none';
    }
    account.alertEpisodeActive = true;
    return 'notify';
  }

  if (!account.alertEpisodeActive) {
    return 'none';
  }
  account.alertEpisodeActive = false;
  return 'reset';
}

// MARK: - Exact decimal-string comparison

// Mirrors the aggregation engine's exact decimal-string approach: doubles
// would render float noise that the exact-string fixture comparison cannot
// tolerate. Plain decimals align by fractional scale and compare as digit
// strings; unparseable inputs (e.g. exponent-only) fall back to double
// comparison, as SpecEngine does.
interface PlainDecimalParts {
  negative: boolean;
  intPart: string;
  fracPart: string;
}

function parsePlainDecimal(raw: string): PlainDecimalParts | null {
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
  // A zero magnitude has no sign ("-0" equals "0").
  if (/^0*$/.test(intPart + fracPart)) {
    const zero: PlainDecimalParts = { negative: false, intPart: intPart, fracPart: fracPart };
    return zero;
  }
  const plain: PlainDecimalParts = {
    negative: match[1] === '-',
    intPart: intPart,
    fracPart: fracPart
  };
  return plain;
}

function compareMagnitude(a: PlainDecimalParts, b: PlainDecimalParts, fracLength: number): number {
  const aInt = a.intPart.replace(/^0+(?=\d)/, '');
  const bInt = b.intPart.replace(/^0+(?=\d)/, '');
  if (aInt.length !== bInt.length) {
    return aInt.length < bInt.length ? -1 : 1;
  }
  if (aInt !== bInt) {
    return aInt < bInt ? -1 : 1;
  }
  const aFrac = a.fracPart.padEnd(fracLength, '0');
  const bFrac = b.fracPart.padEnd(fracLength, '0');
  return aFrac === bFrac ? 0 : (aFrac < bFrac ? -1 : 1);
}

// Compares two decimal amount strings exactly (no doubles), returning
// negative/zero/positive like Swift Decimal comparison.
export function compareDecimalStrings(a: string, b: string): number {
  const pa = parsePlainDecimal(a);
  const pb = parsePlainDecimal(b);
  if (pa === null || pb === null) {
    const da = Number(a);
    const db = Number(b);
    return da === db ? 0 : (da < db ? -1 : 1);
  }
  if (pa.negative !== pb.negative) {
    return pa.negative ? -1 : 1;
  }
  const fracLength = Math.max(pa.fracPart.length, pb.fracPart.length);
  const magnitude = compareMagnitude(pa, pb, fracLength);
  return pa.negative ? -magnitude : magnitude;
}
