import { formBindingData, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Account, AccountStore } from '../storage/AccountStore';
import { FormBinding, FormBindingStore } from '../storage/FormBindingStore';
import { SnapshotStore, StoredSnapshot, formatSnapshotTexts } from '../storage/SnapshotStore';
import {
  AggregateAccount,
  AggregateHealth,
  AggregateSnapshotInput,
  AggregationClock,
  aggregateSnapshots
} from '../aggregation/SnapshotAggregator';
import { formatAmount, formatCompactCount } from '../utils/NumberFormat';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

// Card data builder + formProvider.updateForm pusher. Single source of truth
// for the formBindingData payload every card consumes (WidgetCard.ets reads
// these keys via @LocalStorageProp):
//   formId / formDimension - identity + grid dimension (1=1*2, 2=2*2, 3=2*4, 4=4*4)
//   mode                   - 'aggregate' (总览) or 'account'
//   title                  - '总览' or the account display name
//   balanceText            - primary balance line ('12.34 CNY' / per-currency join)
//   statusText / updatedAtText - health + freshness line (see SnapshotStore)
//   todayText              - today cost/requests summary ('' when unavailable)
//   rowsText               - newline-joined per-account rows for 2*4 / 4*4
//   targetAccountId        - '' (open Index) or the account id (open detail)
//
// Callers: EntryFormAbility (onAddForm/onUpdateForm), FormAccountPickerPage
// (after the user changes the per-card account), and AccountService's
// post-refresh hook (updateAllCards).

export interface CardDataParams {
  formId: string;
  dimension: number;
  mode: string;
  title: string;
  balanceText: string;
  statusText: string;
  updatedAtText: string;
  todayText: string;
  rowsText: string;
  targetAccountId: string;
}

function toBindingData(params: CardDataParams): formBindingData.FormBindingData {
  const data: Record<string, string> = {
    'formId': params.formId,
    'formDimension': `${params.dimension}`,
    'mode': params.mode,
    'title': params.title,
    'balanceText': params.balanceText,
    'statusText': params.statusText,
    'updatedAtText': params.updatedAtText,
    'todayText': params.todayText,
    'rowsText': params.rowsText,
    'targetAccountId': params.targetAccountId
  };
  return formBindingData.createFormBindingData(data);
}

// Aggregate currency ordering mirrors Index.ets: CNY first, then USD, then
// the rest alphabetically.
function currencyRank(currency: string): number {
  if (currency === 'CNY') {
    return 0;
  }
  if (currency === 'USD') {
    return 1;
  }
  return 2;
}

function formatClock(ms: number): string {
  const date = new Date(ms);
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');
  return `更新于 ${hours}:${minutes}`;
}

// One newline-separated card row per account: '名称  12.34 CNY' with a stale
// marker, '--' when the account has no cached snapshot yet.
function accountRow(account: Account, stored: StoredSnapshot | null): string {
  let value = '--';
  if (stored !== null && stored.snapshot.balances.length > 0) {
    const primary = stored.snapshot.balances[0];
    value = `${formatAmount(primary.available.amount)} ${primary.available.currency}`;
  }
  const stale = stored !== null && stored.isStale ? ' · 过期' : '';
  return `${account.displayName}  ${value}${stale}`;
}

// Builds the full payload for one form. A binding whose accountId no longer
// resolves to an existing account degrades to the aggregate overview (the
// macOS NCWidget deleted-account fallback).
export async function buildCardData(context: common.Context, formId: string): Promise<CardDataParams> {
  const bindingStore = await FormBindingStore.create(context);
  const accountStore = await AccountStore.create(context);
  const snapshotStore = await SnapshotStore.create(context);
  const binding: FormBinding = (await bindingStore.bindingFor(formId)) ?? { dimension: 2 };
  const accounts = await accountStore.load();

  let target: Account | null = null;
  if (binding.accountId !== undefined) {
    for (const account of accounts) {
      if (account.id === binding.accountId) {
        target = account;
        break;
      }
    }
  }

  const base: CardDataParams = {
    formId: formId,
    dimension: binding.dimension,
    mode: target === null ? 'aggregate' : 'account',
    title: '',
    balanceText: '',
    statusText: '',
    updatedAtText: '',
    todayText: '',
    rowsText: '',
    targetAccountId: target?.id ?? ''
  };

  if (target !== null) {
    base.title = target.displayName;
    const stored = await snapshotStore.load(target.id);
    const texts = formatSnapshotTexts(stored);
    base.balanceText = texts['balanceText'] ?? '--';
    base.statusText = texts['statusText'] ?? '';
    base.updatedAtText = texts['updatedAtText'] ?? '';
    const today = stored?.snapshot.today;
    if (today !== undefined && today.actualCost !== undefined) {
      const requests = today.requests !== undefined ? ` · ${formatCompactCount(today.requests)} 次` : '';
      base.todayText = `今日 ${formatAmount(today.actualCost.amount)} ${today.actualCost.currency}${requests}`;
    }
    return base;
  }

  // Aggregate overview: totals from the shared aggregation engine (same
  // contract as the Index overview panel) + one row per account.
  base.title = '总览';
  const snapshotInputs: AggregateSnapshotInput[] = [];
  const rows: string[] = [];
  let latestMs = 0;
  for (const account of accounts) {
    if (!account.isEnabled) {
      continue;
    }
    const stored = await snapshotStore.load(account.id);
    rows.push(accountRow(account, stored));
    if (stored === null) {
      continue;
    }
    const health: AggregateHealth = stored.isStale ? 'stale' : 'healthy';
    const input: AggregateSnapshotInput = {
      accountID: account.id,
      displayName: account.displayName,
      usage: stored.snapshot,
      health: health
    };
    snapshotInputs.push(input);
    latestMs = Math.max(latestMs, stored.snapshot.receivedAtMs);
  }
  const clock: AggregationClock = {
    nowMs: Date.now(),
    timeZoneOffsetMinutes: -new Date().getTimezoneOffset()
  };
  const accountInputs: AggregateAccount[] = accounts.map((account: Account): AggregateAccount => {
    return {
      id: account.id,
      displayName: account.displayName,
      isEnabled: account.isEnabled,
      sortOrder: account.sortOrder
    };
  });
  const aggregate = aggregateSnapshots(accountInputs, snapshotInputs, clock);

  if (aggregate.balances.length > 0) {
    const sorted = [...aggregate.balances];
    sorted.sort((a, b) => {
      const rankDiff = currencyRank(a.currency) - currencyRank(b.currency);
      if (rankDiff !== 0) {
        return rankDiff;
      }
      return a.currency < b.currency ? -1 : (a.currency > b.currency ? 1 : 0);
    });
    base.balanceText = sorted
      .map((money) => `${formatAmount(money.amount)} ${money.currency}`)
      .join(' · ');
  } else {
    base.balanceText = accounts.length === 0 ? '未配置' : '--';
  }
  const todayParts: string[] = [];
  if (aggregate.todayActualCost !== undefined) {
    todayParts.push(`${formatAmount(aggregate.todayActualCost.amount)} ${aggregate.todayActualCost.currency}`);
  }
  if (aggregate.todayRequests !== undefined) {
    todayParts.push(`${formatCompactCount(aggregate.todayRequests)} 次`);
  }
  if (todayParts.length > 0) {
    base.todayText = `今日 ${todayParts.join(' · ')}`;
  }
  if (aggregate.isPartial && snapshotInputs.length > 0) {
    base.statusText = '部分数据过期';
  }
  if (latestMs > 0) {
    base.updatedAtText = formatClock(latestMs);
  }
  base.rowsText = rows.join('\n');
  return base;
}

// Pushes fresh data to one card. Best-effort: a dead formId (removed between
// registry update and push) is logged, never thrown.
export async function updateFormCard(context: common.Context, formId: string): Promise<void> {
  try {
    const params = await buildCardData(context, formId);
    await formProvider.updateForm(formId, toBindingData(params));
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'updateFormCard failed: %{public}s %{public}s', formId, (error as Error).message);
  }
}

// Post-refresh fan-out: every registered card re-reads the persisted
// snapshots. Called from AccountService's post-batch / single-refresh hooks.
export async function updateAllCards(context: common.Context): Promise<void> {
  try {
    const bindingStore = await FormBindingStore.create(context);
    const formIds = await bindingStore.listFormIds();
    for (const formId of formIds) {
      await updateFormCard(context, formId);
    }
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'updateAllCards failed: %{public}s', (error as Error).message);
  }
}
