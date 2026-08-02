import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountService } from '../services/AccountService';
import { getLaunchRefresh, notifyOverviewRefresh } from '../services/LaunchRefresh';
import { Account, AccountStore } from '../storage/AccountStore';
import { SnapshotStore, StoredSnapshot } from '../storage/SnapshotStore';
import {
  DailyUsage,
  ModelUsage,
  MonetaryBalance,
  MonetaryValue,
  QuotaWindow,
  UsageCounters,
  UsageSnapshot
} from '../providers/UsageSnapshot';
import { friendlyErrorText } from '../utils/ErrorMapping';
import { formatAmount, formatCompactCount, formatQuotaValue, formatTokenCount } from '../utils/NumberFormat';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

interface StatItem {
  label: string;
  value: string;
}

interface DayBar {
  date: string;
  dayLabel: string;
  barHeight: number;
}

interface QuotaItem {
  label: string;
  valueText: string;
  limitText: string;
  showProgress: boolean;
  fraction: number;
  resetText: string;
}

interface LimitView {
  label: string;
  remainingText: string;
  remainingCurrency: string;
  usageText: string;
  resetText: string;
}

interface StatusLine {
  text: string;
  isWarning: boolean;
}

interface DetailViewModel {
  balances: MonetaryBalance[];
  models: ModelUsage[];
  spendingLimit: LimitView | null;
  quotaItems: QuotaItem[];
  todayStats: StatItem[];
  days: DayBar[];
  daysTotalText: string;
  spendItems: StatItem[];
  totalStats: StatItem[];
  statusLines: StatusLine[];
  requestsUnit: string;
}

const MAX_BAR_HEIGHT: number = 64;
const MIN_BAR_HEIGHT: number = 4;

// Auto-refresh-once-per-launch bookkeeping, keyed by account id. Shared by
// every AccountDetailView instance (Index tabs, detail page, screensaver) so
// re-created views do not re-fire the open-refresh within one app launch.
const autoRefreshedAccounts: Set<string> = new Set();

// Pre-marks accounts as refreshed for this launch. Index uses this after
// its cold-launch refreshAllEnabled so the per-tab auto-refresh does not
// immediately duplicate the same fetches.
export function markAccountsRefreshedThisLaunch(accountIds: string[]): void {
  for (const id of accountIds) {
    autoRefreshedAccounts.add(id);
  }
}

function pad2(value: number): string {
  return value.toString().padStart(2, '0');
}

function getString(context: common.Context, resource: Resource): string {
  return context.resourceManager.getStringSync(resource.id);
}

// Strict yyyy-MM-dd parse; returns epoch ms (local) or null when invalid.
// Mirrors the en_US_POSIX non-lenient DateFormatter in mac's makeDays.
function parseDayMs(value: string): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (match === null) {
    return null;
  }
  const year = parseInt(match[1], 10);
  const month = parseInt(match[2], 10);
  const day = parseInt(match[3], 10);
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  const date = new Date(year, month - 1, day);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    return null;
  }
  return date.getTime();
}

function dayLabel(value: string): string {
  if (parseDayMs(value) !== null) {
    const parts = value.split('-');
    return `${parseInt(parts[2], 10)}`;
  }
  const fallback = value.substring(0, 3);
  return fallback.length > 0 ? fallback : '--';
}

interface IndexedDay {
  index: number;
  usage: DailyUsage;
  ms: number | null;
}

// Mirrors MenuBarPresenter.makeDays: when every date parses, sort ascending by
// date (stable on original index), otherwise keep the provider's order; then
// take the last 7 entries and normalize bar heights to the max cost.
function makeDays(daily: DailyUsage[]): DayBar[] {
  const indexed: IndexedDay[] = daily.map((usage: DailyUsage, index: number): IndexedDay => {
    return { index: index, usage: usage, ms: parseDayMs(usage.date) };
  });
  let ordered: DailyUsage[];
  if (indexed.every((item: IndexedDay) => item.ms !== null)) {
    const sorted = indexed.slice().sort((a: IndexedDay, b: IndexedDay) => {
      const aMs = a.ms as number;
      const bMs = b.ms as number;
      if (aMs !== bMs) {
        return aMs - bMs;
      }
      return a.index - b.index;
    });
    ordered = sorted.map((item: IndexedDay) => item.usage);
  } else {
    ordered = daily;
  }
  const start = ordered.length > 7 ? ordered.length - 7 : 0;
  const last7 = ordered.slice(start);
  const costs: number[] = last7.map((usage: DailyUsage) => parseFloat(usage.actualCost.amount));
  let max = 0;
  for (const cost of costs) {
    if (!isNaN(cost) && cost > max) {
      max = cost;
    }
  }
  return last7.map((usage: DailyUsage, index: number): DayBar => {
    const cost = costs[index];
    let height = MIN_BAR_HEIGHT;
    if (max > 0 && !isNaN(cost)) {
      height = Math.max(MIN_BAR_HEIGHT, (cost / max) * MAX_BAR_HEIGHT);
    }
    return {
      date: usage.date,
      dayLabel: dayLabel(usage.date),
      barHeight: height
    };
  });
}

function daysTotalText(daily: DailyUsage[]): string {
  const start = daily.length > 7 ? daily.length - 7 : 0;
  const last7 = daily.slice(start);
  let sum = 0;
  for (const usage of last7) {
    const cost = parseFloat(usage.actualCost.amount);
    if (!isNaN(cost)) {
      sum += cost;
    }
  }
  return `${sum.toFixed(2)} ${last7[0].actualCost.currency}`;
}

function counterStats(context: common.Context, counters: UsageCounters): StatItem[] {
  const items: StatItem[] = [];
  if (counters.actualCost !== undefined) {
    items.push({
      label: getString(context, $r('app.string.stat_cost')),
      value: `${formatAmount(counters.actualCost.amount)} ${counters.actualCost.currency}`
    });
  }
  if (counters.requests !== undefined) {
    items.push({
      label: getString(context, $r('app.string.stat_requests')),
      value: formatCompactCount(counters.requests)
    });
  }
  if (counters.totalTokens !== undefined) {
    items.push({
      label: getString(context, $r('app.string.stat_tokens')),
      value: formatTokenCount(counters.totalTokens)
    });
  } else {
    const parts: string[] = [];
    if (counters.inputTokens !== undefined) {
      parts.push(`${getString(context, $r('app.string.stat_input_short'))} ${formatTokenCount(counters.inputTokens)}`);
    }
    if (counters.outputTokens !== undefined) {
      parts.push(`${getString(context, $r('app.string.stat_output_short'))} ${formatTokenCount(counters.outputTokens)}`);
    }
    if (parts.length > 0) {
      items.push({
        label: getString(context, $r('app.string.stat_tokens')),
        value: parts.join(' · ')
      });
    }
  }
  return items;
}

function limitView(context: common.Context, snapshot: UsageSnapshot): LimitView | null {
  const limit = snapshot.spendingLimit;
  if (limit === undefined) {
    return null;
  }
  const parts: string[] = [];
  if (limit.used !== undefined) {
    parts.push(`${getString(context, $r('app.string.used_label'))} ${formatAmount(limit.used.amount)}`);
  }
  if (limit.limit !== undefined) {
    parts.push(`${getString(context, $r('app.string.limit_label'))} ${formatAmount(limit.limit.amount)}`);
  }
  let currency = '';
  if (limit.remaining !== undefined) {
    currency = limit.remaining.currency;
  } else if (limit.used !== undefined) {
    currency = limit.used.currency;
  } else if (limit.limit !== undefined) {
    currency = limit.limit.currency;
  }
  let usageText = parts.join(' / ');
  if (usageText.length > 0 && currency.length > 0) {
    usageText = `${usageText} ${currency}`;
  }
  return {
    label: limit.label,
    remainingText: limit.remaining !== undefined ? formatAmount(limit.remaining.amount)
      : (limit.used !== undefined ? formatAmount(limit.used.amount) : '--'),
    remainingCurrency: currency,
    usageText: usageText,
    resetText: limit.resetDescription !== undefined ? limit.resetDescription : ''
  };
}

function quotaItems(context: common.Context, windows: QuotaWindow[]): QuotaItem[] {
  const resetPrefix = getString(context, $r('app.string.reset_prefix'));
  const items: QuotaItem[] = [];
  for (const window of windows) {
    let valueText = '--';
    if (window.remaining !== undefined) {
      valueText = formatQuotaValue(window.remaining);
    } else if (window.used !== undefined) {
      valueText = formatQuotaValue(window.used);
    }
    const limitText = window.limit !== undefined ? `/ ${formatQuotaValue(window.limit)} ${window.unit}` : window.unit;
    let showProgress = false;
    let fraction = 0;
    if (window.limit !== undefined && window.limit > 0) {
      let used: number | null = null;
      if (window.used !== undefined) {
        used = window.used;
      } else if (window.remaining !== undefined) {
        used = window.limit - window.remaining;
      }
      if (used !== null) {
        showProgress = true;
        fraction = Math.min(Math.max(used / window.limit, 0), 1);
      }
    }
    let resetText = '';
    if (window.resetsAtMs !== undefined) {
      const date = new Date(window.resetsAtMs);
      resetText = `${resetPrefix} ${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} `
        + `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
    }
    items.push({
      label: window.label,
      valueText: valueText,
      limitText: limitText,
      showProgress: showProgress,
      fraction: fraction,
      resetText: resetText
    });
  }
  return items;
}

function spendItems(context: common.Context, snapshot: UsageSnapshot): StatItem[] {
  const items: StatItem[] = [];
  const spend = snapshot.spend;
  if (spend === undefined) {
    return items;
  }
  if (spend.today !== undefined) {
    items.push({
      label: getString(context, $r('app.string.spend_today')),
      value: `${formatAmount(spend.today.amount)} ${spend.today.currency}`
    });
  }
  if (spend.week !== undefined) {
    items.push({
      label: getString(context, $r('app.string.spend_week')),
      value: `${formatAmount(spend.week.amount)} ${spend.week.currency}`
    });
  }
  if (spend.month !== undefined) {
    items.push({
      label: getString(context, $r('app.string.spend_month')),
      value: `${formatAmount(spend.month.amount)} ${spend.month.currency}`
    });
  }
  if (spend.total !== undefined) {
    items.push({
      label: getString(context, $r('app.string.spend_total')),
      value: `${formatAmount(spend.total.amount)} ${spend.total.currency}`
    });
  }
  return items;
}

function formatUpdatedAt(context: common.Context, ms: number): string {
  const prefix = getString(context, $r('app.string.updated_prefix'));
  const date = new Date(ms);
  const now = new Date();
  const hhmm = `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  const sameDay = date.getFullYear() === now.getFullYear()
    && date.getMonth() === now.getMonth()
    && date.getDate() === now.getDate();
  if (sameDay) {
    return `${prefix} ${hhmm}`;
  }
  return `${prefix} ${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${hhmm}`;
}

function emptyViewModel(): DetailViewModel {
  return {
    balances: [],
    models: [],
    spendingLimit: null,
    quotaItems: [],
    todayStats: [],
    days: [],
    daysTotalText: '',
    spendItems: [],
    totalStats: [],
    statusLines: [],
    requestsUnit: ''
  };
}

function buildViewModel(context: common.Context, account: Account, stored: StoredSnapshot | null): DetailViewModel {
  const vm = emptyViewModel();
  vm.requestsUnit = getString(context, $r('app.string.requests_unit'));
  if (stored === null) {
    vm.statusLines.push({ text: getString(context, $r('app.string.not_refreshed')), isWarning: false });
    return vm;
  }
  const snapshot = stored.snapshot;
  vm.balances = snapshot.balances;
  vm.models = snapshot.modelUsage !== undefined ? snapshot.modelUsage : [];
  vm.spendingLimit = limitView(context, snapshot);
  vm.quotaItems = quotaItems(context, snapshot.quotaWindows !== undefined ? snapshot.quotaWindows : []);
  if (snapshot.today !== undefined) {
    vm.todayStats = counterStats(context, snapshot.today);
  }
  const daily = snapshot.dailyUsage !== undefined ? snapshot.dailyUsage : [];
  if (daily.length > 0) {
    vm.days = makeDays(daily);
    vm.daysTotalText = daysTotalText(daily);
  }
  vm.spendItems = spendItems(context, snapshot);
  if (snapshot.total !== undefined) {
    vm.totalStats = counterStats(context, snapshot.total);
  }
  if (stored.isStale) {
    vm.statusLines.push({ text: getString(context, $r('app.string.stale_text')), isWarning: true });
  }
  if (snapshot.metricsUnavailableReason !== undefined) {
    vm.statusLines.push({ text: snapshot.metricsUnavailableReason, isWarning: false });
  }
  if (snapshot.providerStatus !== undefined && snapshot.providerStatus !== 'active') {
    vm.statusLines.push({ text: snapshot.providerStatus, isWarning: false });
  }
  vm.statusLines.push({ text: formatUpdatedAt(context, snapshot.receivedAtMs), isWarning: false });
  const thresholdText = account.lowBalanceThreshold;
  if (thresholdText !== undefined) {
    const threshold = parseFloat(thresholdText);
    if (!isNaN(threshold)) {
      for (const balance of snapshot.balances) {
        const amount = parseFloat(balance.available.amount);
        if (!isNaN(amount) && amount < threshold) {
          vm.statusLines.push({ text: getString(context, $r('app.string.below_threshold')), isWarning: true });
          break;
        }
      }
    }
  }
  return vm;
}

// Full per-account detail body, shared by AccountDetailPage, the Index
// provider tabs, and the account-sourced screensaver. Renders no top bar —
// hosts own their navigation chrome and drive snapshot reloads by bumping
// `syncTick`. The once-per-launch auto-refresh of enabled accounts lives
// here so every host behaves like the original detail page.
@Component
export struct AccountDetailView {
  accountId: string = '';
  // Dim palette for the burn-in-aware screensaver (near-black cards, muted
  // text/teal) instead of the normal bright theme.
  dim: boolean = false;
  // Bump (from the host) to reload the snapshot from the store. Network
  // refresh stays with the host; this view only re-reads the cache.
  @Prop @Watch('onSyncTick') syncTick: number = 0;
  @State private vm: DetailViewModel = emptyViewModel();
  @State private hasAccount: boolean = false;
  private currentAccount: Account | null = null;

  aboutToAppear(): void {
    this.loadAndMaybeRefresh();
  }

  onSyncTick(): void {
    this.reload();
  }

  private async loadAndMaybeRefresh(): Promise<void> {
    await this.reload();
    const account = this.currentAccount;
    if (account === null || !account.isEnabled) {
      hilog.info(DOMAIN, TAG, 'detail auto-refresh skip: %{public}s', this.accountId);
      return;
    }
    if (autoRefreshedAccounts.has(account.id)) {
      hilog.info(DOMAIN, TAG, 'detail auto-refresh already done: %{public}s', account.id);
      return;
    }
    // A cold-launch refresh may already be fetching this account; wait for it
    // instead of issuing a duplicate request. Fall back to our own refresh if
    // the launch pass finished without covering this account.
    const launchRefresh = getLaunchRefresh();
    if (launchRefresh !== null) {
      hilog.info(DOMAIN, TAG, 'detail awaiting launch refresh: %{public}s', account.id);
      try {
        await launchRefresh;
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'detail launch refresh await failed: %{public}s', (error as Error).message);
      }
      await this.reload();
      if (autoRefreshedAccounts.has(account.id)) {
        return;
      }
      hilog.info(DOMAIN, TAG, 'detail launch refresh missed, fallback: %{public}s', account.id);
    }
    autoRefreshedAccounts.add(account.id);
    hilog.info(DOMAIN, TAG, 'detail auto-refresh fetch: %{public}s', account.id);
    await this.refresh();
  }

  private async reload(): Promise<void> {
    if (this.accountId.length === 0) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const accountStore = await AccountStore.create(context);
    const accounts = await accountStore.load();
    let found: Account | null = null;
    for (const account of accounts) {
      if (account.id === this.accountId) {
        found = account;
        break;
      }
    }
    this.currentAccount = found;
    if (found === null) {
      this.hasAccount = false;
      this.vm = emptyViewModel();
      return;
    }
    this.hasAccount = true;
    const snapshotStore = await SnapshotStore.create(context);
    const stored = await snapshotStore.load(found.id);
    this.vm = buildViewModel(context, found, stored);
  }

  private async refresh(): Promise<void> {
    const account = this.currentAccount;
    if (account === null || !account.isEnabled) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const service = await AccountService.create(context);
      await service.refreshAccount(account);
      notifyOverviewRefresh();
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
    await this.reload();
  }

  // Two small internal palettes selected by `dim`. The dim palette is the
  // screensaver's: deliberately dark in BOTH system color modes (burn-in
  // safety on a pure-black window), tuned to stay legible at the
  // screensaver's charging-aware brightness (0.18–0.30 window override).
  private textPrimaryColor(): ResourceColor {
    return this.dim ? '#C9D1DC' : $r('app.color.textPrimary');
  }

  private accentColor(): ResourceColor {
    // Teal at ~0.9 opacity in screensaver mode.
    return this.dim ? '#E657E0D6' : $r('app.color.accentTeal');
  }

  private accentTintColor(): ResourceColor {
    return this.dim ? '#1F57E0D6' : $r('app.color.accentTealTint');
  }

  private cardColor(): ResourceColor {
    return this.dim ? '#0D1119' : $r('app.color.cardBackground');
  }

  @Styles
  cardStyle() {
    .width('100%')
    .padding(16)
    .borderRadius(14)
  }

  @Builder
  sectionHeader(title: Resource) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.textSecondary'))
  }

  @Builder
  statItem(item: StatItem) {
    Column({ space: 4 }) {
      Text(item.label)
        .fontSize(11)
        .fontColor($r('app.color.textSecondary'))
      Text(item.value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textPrimaryColor())
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  balanceSection() {
    Column({ space: 16 }) {
      this.sectionHeader($r('app.string.detail_balance'))
      ForEach(this.vm.balances, (balance: MonetaryBalance, index: number) => {
        Column({ space: 6 }) {
          Row() {
            Text(balance.label)
              .fontSize(13)
              .fontColor($r('app.color.textSecondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(formatAmount(balance.available.amount))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimaryColor())
              .maxLines(1)
            Text(balance.available.currency)
              .fontSize(13)
              .fontColor($r('app.color.textSecondary'))
              .margin({ left: 4 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)

          ForEach(balance.breakdown, (item: MonetaryValue, sub: number) => {
            Text(`${item.label} — ${formatAmount(item.value.amount)} ${item.value.currency}`)
              .fontSize(12)
              .fontColor($r('app.color.textSecondary'))
              .padding({ left: 12 })
              .maxLines(1)
          }, (item: MonetaryValue, sub: number) => `${item.label}-${sub}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (balance: MonetaryBalance, index: number) => `${balance.label}-${index}`)
    }
    .cardStyle()
    .backgroundColor(this.cardColor())
    .borderWidth(this.dim ? 1 : 0)
    .borderColor('#22303F')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  limitSection(limit: LimitView) {
    Column({ space: 10 }) {
      this.sectionHeader($r('app.string.detail_spending_limit'))
      Row() {
        Text(limit.label)
          .fontSize(13)
          .fontColor($r('app.color.textSecondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(limit.remainingText)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accentColor())
          .maxLines(1)
        if (limit.remainingCurrency.length > 0) {
          Text(limit.remainingCurrency)
            .fontSize(13)
            .fontColor($r('app.color.textSecondary'))
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      if (limit.usageText.length > 0) {
        Text(limit.usageText)
          .fontSize(12)
          .fontColor($r('app.color.textSecondary'))
      }
      if (limit.resetText.length > 0) {
        Text(limit.resetText)
          .fontSize(12)
          .fontColor($r('app.color.textSecondary'))
      }
    }
    .cardStyle()
    .backgroundColor(this.cardColor())
    .borderWidth(this.dim ? 1 : 0)
    .borderColor('#22303F')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  quotaSection() {
    Column({ space: 16 }) {
      this.sectionHeader($r('app.string.detail_quota'))
      ForEach(this.vm.quotaItems, (item: QuotaItem, index: number) => {
        Column({ space: 8 }) {
          Row() {
            Text(item.label)
              .fontSize(13)
              .fontColor($r('app.color.textSecondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(item.valueText)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.textPrimaryColor())
              .maxLines(1)
            Text(` ${item.limitText}`)
              .fontSize(13)
              .fontColor($r('app.color.textSecondary'))
              .maxLines(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)

          if (item.showProgress) {
            Progress({ value: item.fraction * 100, total: 100, type: ProgressType.Linear })
              .color(this.accentColor())
              .backgroundColor($r('app.color.slateSecondary'))
              .height(4)
              .width('100%')
          }
          if (item.resetText.length > 0) {
            Text(item.resetText)
              .fontSize(11)
              .fontColor($r('app.color.textSecondary'))
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (item: QuotaItem, index: number) => `${item.label}-${index}`)
    }
    .cardStyle()
    .backgroundColor(this.cardColor())
    .borderWidth(this.dim ? 1 : 0)
    .borderColor('#22303F')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  countersSection(title: Resource, stats: StatItem[]) {
    Column({ space: 14 }) {
      this.sectionHeader(title)
      Row({ space: 28 }) {
        ForEach(stats, (item: StatItem, index: number) => {
          this.statItem(item)
        }, (item: StatItem, index: number) => `${item.label}-${index}`)
      }
      .width('100%')
    }
    .cardStyle()
    .backgroundColor(this.cardColor())
    .borderWidth(this.dim ? 1 : 0)
    .borderColor('#22303F')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  daysSection() {
    Column({ space: 14 }) {
      Row() {
        this.sectionHeader($r('app.string.detail_recent_7d'))
        Blank()
        Text(this.vm.daysTotalText)
          .fontSize(13)
          .fontColor($r('app.color.textSecondary'))
          .maxLines(1)
      }
      .width('100%')

      Row({ space: 6 }) {
        ForEach(this.vm.days, (day: DayBar, index: number) => {
          Column({ space: 4 }) {
            Column()
              .width('60%')
              .height(day.barHeight)
              .backgroundColor(this.accentColor())
              .borderRadius({ topLeft: 3, topRight: 3 })
            Text(day.dayLabel)
              .fontSize(10)
              .fontColor($r('app.color.textSecondary'))
              .maxLines(1)
          }
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .height(88)
          .layoutWeight(1)
        }, (day: DayBar, index: number) => `${day.date}-${index}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .cardStyle()
    .backgroundColor(this.cardColor())
    .borderWidth(this.dim ? 1 : 0)
    .borderColor('#22303F')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  modelsSection() {
    Column({ space: 14 }) {
      this.sectionHeader($r('app.string.detail_models'))
      ForEach(this.vm.models, (model: ModelUsage, index: number) => {
        Row() {
          Text(model.model)
            .fontSize(13)
            .fontColor(this.textPrimaryColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (model.actualCost !== undefined) {
            Text(`${formatAmount(model.actualCost.amount)} ${model.actualCost.currency}`)
              .fontSize(13)
              .fontColor(this.textPrimaryColor())
              .maxLines(1)
          }
          if (model.requests !== undefined) {
            Text(`${formatCompactCount(model.requests)} ${this.vm.requestsUnit}`)
              .fontSize(12)
              .fontColor($r('app.color.textSecondary'))
              .margin({ left: 8 })
              .maxLines(1)
          }
        }
        .width('100%')
      }, (model: ModelUsage, index: number) => `${model.model}-${index}`)
    }
    .cardStyle()
    .backgroundColor(this.cardColor())
    .borderWidth(this.dim ? 1 : 0)
    .borderColor('#22303F')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  spendSection() {
    Column({ space: 14 }) {
      this.sectionHeader($r('app.string.detail_spend'))
      Row({ space: 8 }) {
        ForEach(this.vm.spendItems, (item: StatItem, index: number) => {
          Column({ space: 4 }) {
            Text(item.label)
              .fontSize(11)
              .fontColor($r('app.color.textSecondary'))
            Text(item.value)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.textPrimaryColor())
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.accentTintColor())
          .borderRadius(10)
        }, (item: StatItem, index: number) => `${item.label}-${index}`)
      }
      .width('100%')
    }
    .cardStyle()
    .backgroundColor(this.cardColor())
    .borderWidth(this.dim ? 1 : 0)
    .borderColor('#22303F')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statusSection() {
    Column({ space: 8 }) {
      this.sectionHeader($r('app.string.detail_status'))
      ForEach(this.vm.statusLines, (line: StatusLine, index: number) => {
        Text(line.text)
          .fontSize(12)
          .fontColor(line.isWarning ? $r('app.color.warning') : $r('app.color.textSecondary'))
          .maxLines(2)
          .width('100%')
          .textAlign(TextAlign.Start)
      }, (line: StatusLine, index: number) => `${index}`)
    }
    .cardStyle()
    .backgroundColor(this.cardColor())
    .borderWidth(this.dim ? 1 : 0)
    .borderColor('#22303F')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  sectionGrid() {
    // Component-width breakpoints: <600vp single column, ≥600vp two columns,
    // ≥1000vp three columns; the 最近7天 chart always spans the full row.
    GridRow({
      gutter: { x: 12, y: 12 },
      breakpoints: { value: ['600vp', '1000vp'], reference: BreakpointsReference.ComponentSize }
    }) {
      if (this.vm.balances.length > 0) {
        GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4, xl: 4, xxl: 4 } }) {
          this.balanceSection()
        }
      }
      if (this.vm.spendingLimit !== null) {
        GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4, xl: 4, xxl: 4 } }) {
          this.limitSection(this.vm.spendingLimit as LimitView)
        }
      }
      if (this.vm.quotaItems.length > 0) {
        GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4, xl: 4, xxl: 4 } }) {
          this.quotaSection()
        }
      }
      if (this.vm.todayStats.length > 0) {
        GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4, xl: 4, xxl: 4 } }) {
          this.countersSection($r('app.string.detail_today'), this.vm.todayStats)
        }
      }
      if (this.vm.days.length > 0) {
        GridCol({ span: 12 }) {
          this.daysSection()
        }
      }
      if (this.vm.models.length > 0) {
        GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4, xl: 4, xxl: 4 } }) {
          this.modelsSection()
        }
      }
      if (this.vm.spendItems.length > 0) {
        GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4, xl: 4, xxl: 4 } }) {
          this.spendSection()
        }
      }
      if (this.vm.totalStats.length > 0) {
        GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4, xl: 4, xxl: 4 } }) {
          this.countersSection($r('app.string.detail_total'), this.vm.totalStats)
        }
      }
      GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4, xl: 4, xxl: 4 } }) {
        this.statusSection()
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 32 })
  }

  build() {
    if (!this.hasAccount) {
      Column() {
        Text($r('app.string.no_data'))
          .fontSize(15)
          .fontColor($r('app.color.textSecondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        this.sectionGrid()
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
  }
}
