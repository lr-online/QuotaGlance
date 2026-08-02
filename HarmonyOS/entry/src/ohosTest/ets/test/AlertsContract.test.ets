import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { util } from '@kit.ArkTS';
import {
  AlertAccount,
  AlertBatchEvaluation,
  AlertHealth,
  AlertSnapshotInput,
  evaluateAlertBatch
} from '../../../main/ets/alerts/AlertEvaluator';
import { Money } from '../../../main/ets/providers/UsageSnapshot';

// Alert contract-fixture decode interfaces, mirroring
// Tests/QuotaGlanceCoreTests/AlertContractTests.swift. An input file pins
// accounts (with threshold / episode state) and the fresh snapshots of one
// batch; an expected file pins a subset of AlertBatchEvaluation plus the
// resulting per-account episode state — only fields present in the file are
// asserted. See Contracts/README.md ("Alert contract fixtures").
interface MoneyInput {
  amount: string;
  currency: string;
}

interface AccountInput {
  id: string;
  displayName: string;
  isEnabled?: boolean;
  lowBalanceThreshold?: string;
  alertEpisodeActive?: boolean;
}

interface SnapshotInput {
  accountID: string;
  health: Object;
  remaining?: MoneyInput;
}

interface AlertInput {
  accounts: AccountInput[];
  freshSnapshots: SnapshotInput[];
}

interface ExpectedMoney {
  amount: string;
  currency: string;
}

interface ExpectedNotificationRow {
  accountID: string;
  remaining?: ExpectedMoney;
}

interface ExpectedAccountRow {
  accountID: string;
  alertEpisodeActive?: boolean;
}

// One entry per synced contract case, in the Swift suite's argument order.
// Fixture files live under contracts/alerts/<name>-{input,expected}.json.
const ALERT_CASES: string[] = [
  'notify-on-low',
  'episode-debounce',
  'episode-reset',
  'stale-no-change',
  'batch-notify-and-reset',
  'no-alert-without-threshold'
];

function readRawFileString(path: string): string {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(path);
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

// Key-presence test for the expected fixture: absent = unchecked, value =
// assert equal (same pattern as SpecEngine's hasKey).
function hasField(record: Record<string, Object>, key: string): boolean {
  return record[key] !== undefined;
}

// Health as fixtures write it: "healthy" / "belowThreshold", or
// {"stale": "<failure>"} / {"unavailable": "<failure>"}.
function decodeHealth(raw: Object): AlertHealth {
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

function buildAccounts(input: AlertInput): AlertAccount[] {
  return input.accounts.map((account: AccountInput): AlertAccount => {
    const built: AlertAccount = {
      id: account.id,
      displayName: account.displayName,
      isEnabled: account.isEnabled ?? true,
      alertEpisodeActive: account.alertEpisodeActive ?? false
    };
    if (account.lowBalanceThreshold !== undefined) {
      built.lowBalanceThreshold = account.lowBalanceThreshold;
    }
    return built;
  });
}

function buildSnapshots(input: AlertInput): AlertSnapshotInput[] {
  return input.freshSnapshots.map((snapshot: SnapshotInput): AlertSnapshotInput => {
    const built: AlertSnapshotInput = {
      accountID: snapshot.accountID,
      health: decodeHealth(snapshot.health)
    };
    if (snapshot.remaining !== undefined) {
      built.remaining = toMoney(snapshot.remaining);
    }
    return built;
  });
}

function findAccount(accounts: AlertAccount[], id: string): AlertAccount | undefined {
  for (const account of accounts) {
    if (account.id === id) {
      return account;
    }
  }
  return undefined;
}

export default function alertsContractTest() {
  describe('AlertsContractTest', () => {
    for (const caseName of ALERT_CASES) {
      it(`matches_${caseName}`, 0, () => {
        const input = JSON.parse(
          readRawFileString(`contracts/alerts/${caseName}-input.json`)
        ) as AlertInput;
        const expected = JSON.parse(
          readRawFileString(`contracts/alerts/${caseName}-expected.json`)
        ) as Record<string, Object>;

        const accounts = buildAccounts(input);
        const result: AlertBatchEvaluation = evaluateAlertBatch(
          accounts,
          buildSnapshots(input)
        );

        if (hasField(expected, 'didChange')) {
          expect(result.didChange).assertEqual(expected['didChange'] as boolean);
        }
        if (hasField(expected, 'notifications')) {
          const rows = expected['notifications'] as ExpectedNotificationRow[];
          expect(result.notifications.length).assertEqual(rows.length);
          for (let i = 0; i < rows.length; i++) {
            expect(result.notifications[i].account.id).assertEqual(rows[i].accountID);
            const rowRemaining = rows[i].remaining as ExpectedMoney | undefined;
            if (rowRemaining !== undefined) {
              expect(result.notifications[i].remaining.amount).assertEqual(rowRemaining.amount);
              expect(result.notifications[i].remaining.currency).assertEqual(rowRemaining.currency);
            }
          }
        }
        if (hasField(expected, 'accounts')) {
          const rows = expected['accounts'] as ExpectedAccountRow[];
          for (const row of rows) {
            const account = findAccount(accounts, row.accountID);
            expect(account !== undefined).assertTrue();
            if (row.alertEpisodeActive !== undefined) {
              expect((account as AlertAccount).alertEpisodeActive)
                .assertEqual(row.alertEpisodeActive);
            }
          }
        }
      });
    }
  });
}
