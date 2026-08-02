import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { util } from '@kit.ArkTS';
import {
  AggregateAccount,
  AggregateHealth,
  AggregateSnapshot,
  AggregateSnapshotInput,
  aggregateSnapshots
} from '../../../main/ets/aggregation/SnapshotAggregator';
import { DailyUsage, MonetaryBalance, Money, UsageCounters, UsageSnapshot } from '../../../main/ets/providers/UsageSnapshot';

// Aggregation contract-fixture decode interfaces, mirroring
// Tests/QuotaGlanceCoreTests/AggregationContractTests.swift. An input file
// pins accounts, snapshots, and the evaluation instant; an expected file pins
// a subset of AggregateSnapshot — only fields present in the file are
// asserted, and a field present with JSON null asserts the value is absent.
// See Contracts/README.md ("Aggregation contract fixtures").
interface MoneyInput {
  amount: string;
  currency: string;
}

interface BalanceInput {
  label: string;
  available: MoneyInput;
}

interface TodayInput {
  actualCost?: MoneyInput;
  requests?: number;
}

interface DailyUsageInput {
  date: string;
  actualCost: MoneyInput;
  requests?: number;
  totalTokens?: number;
}

interface UsageInput {
  balances?: BalanceInput[];
  today?: TodayInput;
  dailyUsage?: DailyUsageInput[];
}

interface SnapshotInput {
  accountID: string;
  health: Object;
  usage?: UsageInput;
}

interface AccountInput {
  id: string;
  displayName: string;
  isEnabled?: boolean;
  sortOrder?: number;
}

interface AggregationInput {
  now: string;
  accounts: AccountInput[];
  snapshots: SnapshotInput[];
}

interface ExpectedMoney {
  amount: string;
  currency: string;
}

interface ExpectedAccountRow {
  accountID: string;
  displayName?: string;
}

interface ExpectedDailyRow {
  date: string;
  actualCost?: ExpectedMoney;
}

// One entry per synced contract case. Fixture files live under
// contracts/aggregation/<name>-{input,expected}.json.
const AGGREGATION_CASES: string[] = [
  'healthy-sum',
  'stale-partial',
  'disabled-excluded',
  'mixed-currency',
  'missing-metrics',
  'request-overflow'
];

function readRawFileString(path: string): string {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(path);
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

// Key-presence test for the expected fixture: absent = unchecked, JSON null
// = assert absent, value = assert equal (the Swift suite's OptionalField
// tri-state). ArkTS forbids Function.call/apply, and JSON.parse never
// produces undefined values, so an undefined comparison on the Record is an
// exact presence check (same pattern as SpecEngine's hasKey).
function hasField(record: Record<string, Object>, key: string): boolean {
  return record[key] !== undefined;
}

// Health as fixtures write it: "healthy" / "belowThreshold", or
// {"stale": "<failure>"} / {"unavailable": "<failure>"}.
function decodeHealth(raw: Object): AggregateHealth {
  if (typeof raw === 'string') {
    return raw === 'belowThreshold' ? 'belowThreshold' : 'healthy';
  }
  const table = raw as Record<string, string>;
  const kind = Object.keys(table)[0];
  return kind === 'unavailable' ? 'unavailable' : 'stale';
}

// String sources stay verbatim (fixture canonical form); a numeric source
// renders via String(), matching decimalFromNumber.
function toMoney(input: MoneyInput): Money {
  const money: Money = { amount: String(input.amount), currency: input.currency };
  return money;
}

function buildAccounts(input: AggregationInput): AggregateAccount[] {
  return input.accounts.map((account: AccountInput): AggregateAccount => {
    return {
      id: account.id,
      displayName: account.displayName,
      isEnabled: account.isEnabled ?? true,
      sortOrder: account.sortOrder ?? 0
    };
  });
}

function buildSnapshots(input: AggregationInput): AggregateSnapshotInput[] {
  return input.snapshots.map((snapshot: SnapshotInput): AggregateSnapshotInput => {
    let usage: UsageSnapshot | undefined = undefined;
    if (snapshot.usage !== undefined) {
      const usageInput = snapshot.usage;
      usage = {
        provider: '',
        balances: (usageInput.balances ?? []).map((balance: BalanceInput): MonetaryBalance => {
          return { label: balance.label, available: toMoney(balance.available), breakdown: [] };
        }),
        dailyUsage: (usageInput.dailyUsage ?? []).map((entry: DailyUsageInput): DailyUsage => {
          const daily: DailyUsage = { date: entry.date, actualCost: toMoney(entry.actualCost) };
          if (entry.requests !== undefined) {
            daily.requests = entry.requests;
          }
          if (entry.totalTokens !== undefined) {
            daily.totalTokens = entry.totalTokens;
          }
          return daily;
        }),
        receivedAtMs: 100000
      };
      if (usageInput.today !== undefined) {
        const counters: UsageCounters = {};
        if (usageInput.today.actualCost !== undefined) {
          counters.actualCost = toMoney(usageInput.today.actualCost);
        }
        if (usageInput.today.requests !== undefined) {
          counters.requests = usageInput.today.requests;
        }
        usage.today = counters;
      }
    }
    return {
      accountID: snapshot.accountID,
      displayName: '',
      usage: usage,
      health: decodeHealth(snapshot.health)
    };
  });
}

function assertMoney(actual: Money | undefined, expected: ExpectedMoney): void {
  expect(actual !== undefined).assertTrue();
  const money = actual as Money;
  expect(money.amount).assertEqual(expected.amount);
  expect(money.currency).assertEqual(expected.currency);
}

export default function aggregationContractTest() {
  describe('AggregationContractTest', () => {
    for (const caseName of AGGREGATION_CASES) {
      it(`matches_${caseName}`, 0, () => {
        const input = JSON.parse(
          readRawFileString(`contracts/aggregation/${caseName}-input.json`)
        ) as AggregationInput;
        const expected = JSON.parse(
          readRawFileString(`contracts/aggregation/${caseName}-expected.json`)
        ) as Record<string, Object>;

        // The Swift suite injects a fixed GMT calendar; here the clock seam
        // pins the same instant with a zero (UTC) offset.
        const aggregate: AggregateSnapshot = aggregateSnapshots(
          buildAccounts(input),
          buildSnapshots(input),
          { nowMs: Date.parse(input.now), timeZoneOffsetMinutes: 0 }
        );

        if (hasField(expected, 'balances')) {
          const expectedBalances = expected['balances'] as ExpectedMoney[];
          expect(aggregate.balances.length).assertEqual(expectedBalances.length);
          for (let i = 0; i < expectedBalances.length; i++) {
            assertMoney(aggregate.balances[i], expectedBalances[i]);
          }
        }
        if (hasField(expected, 'todayActualCost')) {
          const value = expected['todayActualCost'] as ExpectedMoney | null;
          if (value === null) {
            expect(aggregate.todayActualCost === undefined).assertTrue();
          } else {
            assertMoney(aggregate.todayActualCost, value);
          }
        }
        if (hasField(expected, 'todayRequests')) {
          const value = expected['todayRequests'] as number | null;
          if (value === null) {
            expect(aggregate.todayRequests === undefined).assertTrue();
          } else {
            expect(aggregate.todayRequests).assertEqual(value);
          }
        }
        if (hasField(expected, 'dailyUsage')) {
          const rows = expected['dailyUsage'] as ExpectedDailyRow[];
          expect(aggregate.dailyUsage.length).assertEqual(rows.length);
          for (let i = 0; i < rows.length; i++) {
            expect(aggregate.dailyUsage[i].date).assertEqual(rows[i].date);
            const rowCost = rows[i].actualCost as ExpectedMoney | null | undefined;
            if (rowCost !== undefined && rowCost !== null) {
              assertMoney(aggregate.dailyUsage[i].actualCost, rowCost);
            }
          }
        }
        if (hasField(expected, 'accounts')) {
          const rows = expected['accounts'] as ExpectedAccountRow[];
          expect(aggregate.accounts.length).assertEqual(rows.length);
          for (let i = 0; i < rows.length; i++) {
            expect(aggregate.accounts[i].accountID).assertEqual(rows[i].accountID);
            if (rows[i].displayName !== undefined) {
              expect(aggregate.accounts[i].displayName).assertEqual(rows[i].displayName as string);
            }
          }
        }
        if (hasField(expected, 'isPartial')) {
          expect(aggregate.isPartial).assertEqual(expected['isPartial'] as boolean);
        }
      });
    }
  });
}
