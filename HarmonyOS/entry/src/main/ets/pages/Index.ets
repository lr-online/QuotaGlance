import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AccountService } from '../services/AccountService';
import { Account } from '../storage/AccountStore';
import { SnapshotStore, StoredSnapshot } from '../storage/SnapshotStore';
import { providerDisplayName } from '../providers/UsageProvider';
import { QuotaWindow } from '../providers/UsageSnapshot';
import { friendlyErrorText } from '../utils/ErrorMapping';
import { formatAmount, formatCompactCount, formatQuotaValue } from '../utils/NumberFormat';
import { ThemeMode, ThemeStore } from '../storage/ThemeStore';
import { applyThemeMode, reapplyWindowBackground } from '../utils/ThemeUtils';
import { AccountDetailView, markAccountsRefreshedThisLaunch } from '../components/AccountDetailView';

// Aggregate currency ordering: CNY first, then USD, then the rest
// alphabetically (mirrors the mac app's CNY/USD emphasis).
function currencyRank(currency: string): number {
  if (currency === 'CNY') {
    return 0;
  }
  if (currency === 'USD') {
    return 1;
  }
  return 2;
}

function orderedCurrencies(map: Map<string, number>): string[] {
  const keys: string[] = [];
  map.forEach((value: number, key: string) => {
    keys.push(key);
  });
  keys.sort((a: string, b: string) => {
    const rankDiff = currencyRank(a) - currencyRank(b);
    if (rankDiff !== 0) {
      return rankDiff;
    }
    return a < b ? -1 : (a > b ? 1 : 0);
  });
  return keys;
}

// Sums a decimal-string amount into the per-currency map; NaN is skipped.
function sumInto(map: Map<string, number>, currency: string, amountText: string): void {
  const value = parseFloat(amountText);
  if (isNaN(value)) {
    return;
  }
  map.set(currency, (map.get(currency) ?? 0) + value);
}

// 'CNY 123.45 · USD 67.89' (currency first), '' when empty.
function balanceLine(map: Map<string, number>): string {
  const parts: string[] = orderedCurrencies(map).map((currency: string) => {
    return `${currency} ${formatAmount(`${map.get(currency) ?? 0}`)}`;
  });
  return parts.join(' · ');
}

// '12.34 CNY · 45 次' (amount first), '' when nothing is exposed.
function todayBody(context: common.Context, costs: Map<string, number>, requests: number,
  hasRequests: boolean): string {
  const parts: string[] = orderedCurrencies(costs).map((currency: string) => {
    return `${formatAmount(`${costs.get(currency) ?? 0}`)} ${currency}`;
  });
  if (hasRequests) {
    const unit = context.resourceManager.getStringSync($r('app.string.requests_unit').id);
    parts.push(`${formatCompactCount(requests)} ${unit}`);
  }
  return parts.join(' · ');
}

// '配额 300/500 次' from the first quota window, per the MiniMax-style
// providers that expose quotas instead of balances.
function quotaSummary(context: common.Context, window: QuotaWindow): string {
  const label = context.resourceManager.getStringSync($r('app.string.overview_quota').id);
  const mainText = window.remaining !== undefined ? formatQuotaValue(window.remaining)
    : (window.used !== undefined ? formatQuotaValue(window.used) : '--');
  const limitText = window.limit !== undefined ? `/${formatQuotaValue(window.limit)}` : '';
  return `${label} ${mainText}${limitText} ${window.unit}`.trim();
}

interface ProviderOverview {
  key: string;
  name: string;
  hasEnabled: boolean;
  balanceText: string;
  todayText: string;
  quotaText: string;
  stale: boolean;
  hasData: boolean;
  // Comparison-bar fill fraction (0–1, score ÷ max score) and its rounded
  // percentage label ('' when the provider has no consumption score).
  fraction: number;
  pctText: string;
}

interface ProviderWork {
  name: string;
  hasEnabled: boolean;
  balances: Map<string, number>;
  todayCosts: Map<string, number>;
  todayRequests: number;
  hasTodayRequests: boolean;
  quotaText: string;
  quotaScore: number | null;
  stale: boolean;
}

// Consumption score for the cross-provider comparison bars. Priority:
// (a) today.actualCost — CNY if present, else USD, else the first currency.
//     Cross-currency amounts are NOT converted (project rule), so picking
//     one currency per provider keeps the comparison approximate by design.
// (b) today.requests.
// (c) first quota window's used percentage (used/limit, clamped 0–100).
// (d) otherwise no score (null) → empty fill, no % label.
function providerScore(work: ProviderWork): number | null {
  if (work.todayCosts.size > 0) {
    const cny = work.todayCosts.get('CNY');
    if (cny !== undefined) {
      return cny;
    }
    const usd = work.todayCosts.get('USD');
    if (usd !== undefined) {
      return usd;
    }
    const first = orderedCurrencies(work.todayCosts)[0];
    return work.todayCosts.get(first) ?? null;
  }
  if (work.hasTodayRequests) {
    return work.todayRequests;
  }
  return work.quotaScore;
}

// Cold-launch guard (module scope): the once-per-app-open auto refreshAll
// must not re-fire on tab switches or page returns within the process.
let launchAutoRefreshDone: boolean = false;

@Entry
@Component
struct Index {  @State accounts: Account[] = [];
  @State refreshingAll: boolean = false;
  @State currentIndex: number = 0;
  @State syncTick: number = 0;
  @State themeMode: ThemeMode = 'system';
  @State overviewToday: string = '';
  @State overviewPartial: boolean = false;
  @State providerBlocks: ProviderOverview[] = [];
  private tabsController: TabsController = new TabsController();

  onPageShow(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const service = await AccountService.create(context);
    await service.ensureLegacyMigration();
    this.accounts = await service.loadAccounts();
    if (this.currentIndex >= this.accounts.length) {
      this.currentIndex = 0;
    }
    this.preloadTabs();
    const themeStore = await ThemeStore.create(context);
    this.themeMode = await themeStore.load();
    await this.loadOverview(context);
    await this.maybeLaunchRefresh(service, context);
  }

  // Once per cold app launch: refresh every enabled account (busy chip
  // while running), then recompute the overview and bump the tabs' syncTick.
  // The enabled ids are pre-marked in AccountDetailView's launch set so its
  // per-tab once-per-launch auto-refresh does not duplicate these fetches.
  private async maybeLaunchRefresh(service: AccountService, context: common.UIAbilityContext): Promise<void> {
    if (launchAutoRefreshDone) {
      return;
    }
    launchAutoRefreshDone = true;
    const enabledIds: string[] = this.accounts
      .filter((account: Account) => account.isEnabled)
      .map((account: Account) => account.id);
    if (enabledIds.length === 0) {
      return;
    }
    this.refreshingAll = true;
    try {
      await service.refreshAllEnabled();
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
    this.refreshingAll = false;
    markAccountsRefreshedThisLaunch(enabledIds);
    this.syncTick += 1;
    await this.loadOverview(context);
  }

  // Selecting the already-active mode is a no-op (the menu closes on tap).
  private selectTheme(mode: ThemeMode): void {
    if (mode === this.themeMode) {
      return;
    }
    this.themeMode = mode;
    const context = getContext(this) as common.UIAbilityContext;
    ThemeStore.create(context)
      .then((store: ThemeStore) => store.save(mode))
      .then(() => {
        applyThemeMode(context, mode);
        // Idempotent with EntryAbility.onConfigurationUpdate (see
        // ThemeUtils): correct whether or not that callback fires for an
        // app-level setColorMode.
        reapplyWindowBackground(context);
      })
      .catch((error: Object) => {
        promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
      });
  }

  // Aggregates the CACHED snapshots for the overview panel — no network.
  // Header keeps only today's totals (per-provider balances live in the
  // provider blocks; per the macOS contract, spendingLimit/quotaWindow
  // values never enter balance sums). Every provider with ≥1 account gets a
  // block, even with no cached data or only disabled accounts (常驻).
  private async loadOverview(context: common.UIAbilityContext): Promise<void> {
    const store = await SnapshotStore.create(context);
    const todayCosts = new Map<string, number>();
    let todayRequests = 0;
    let hasTodayRequests = false;
    let snapshotsFound = 0;
    let enabledCount = 0;
    let partial = false;
    const workByProvider = new Map<string, ProviderWork>();
    const providerOrder: string[] = [];

    for (const account of this.accounts) {
      const key = account.provider as string;
      let work = workByProvider.get(key);
      if (work === undefined) {
        work = {
          name: providerDisplayName(account.provider),
          hasEnabled: false,
          balances: new Map<string, number>(),
          todayCosts: new Map<string, number>(),
          todayRequests: 0,
          hasTodayRequests: false,
          quotaText: '',
          quotaScore: null,
          stale: false
        };
        workByProvider.set(key, work);
        providerOrder.push(key);
      }
      if (!account.isEnabled) {
        continue;
      }
      work.hasEnabled = true;
      enabledCount += 1;
      const stored: StoredSnapshot | null = await store.load(account.id);
      if (stored === null) {
        continue;
      }
      snapshotsFound += 1;
      if (stored.isStale) {
        partial = true;
        work.stale = true;
      }
      const snapshot = stored.snapshot;
      for (const balance of snapshot.balances) {
        sumInto(work.balances, balance.available.currency, balance.available.amount);
      }
      if (snapshot.today !== undefined) {
        if (snapshot.today.actualCost !== undefined) {
          sumInto(todayCosts, snapshot.today.actualCost.currency, snapshot.today.actualCost.amount);
          sumInto(work.todayCosts, snapshot.today.actualCost.currency, snapshot.today.actualCost.amount);
        }
        if (snapshot.today.requests !== undefined) {
          todayRequests += snapshot.today.requests;
          hasTodayRequests = true;
          work.todayRequests += snapshot.today.requests;
          work.hasTodayRequests = true;
        }
      }
      if (work.quotaText.length === 0
        && snapshot.quotaWindows !== undefined && snapshot.quotaWindows.length > 0) {
        const window = snapshot.quotaWindows[0];
        work.quotaText = quotaSummary(context, window);
        if (window.limit !== undefined && window.limit > 0) {
          const used = window.used ?? ((window.remaining !== undefined) ? window.limit - window.remaining : 0);
          work.quotaScore = Math.min(Math.max((used / window.limit) * 100, 0), 100);
        }
      }
    }
    if (snapshotsFound > 0 && snapshotsFound < enabledCount) {
      partial = true;
    }

    this.overviewToday = todayBody(context, todayCosts, todayRequests, hasTodayRequests);
    this.overviewPartial = partial;

    const todayLabel = context.resourceManager.getStringSync($r('app.string.overview_today').id);
    const blocks: ProviderOverview[] = providerOrder.map((key: string): ProviderOverview => {
      const work = workByProvider.get(key) as ProviderWork;
      const balanceText = balanceLine(work.balances);
      const body = todayBody(context, work.todayCosts, work.todayRequests, work.hasTodayRequests);
      const todayText = body.length > 0 ? `${todayLabel} ${body}` : '';
      return {
        key: key,
        name: work.name,
        hasEnabled: work.hasEnabled,
        balanceText: balanceText,
        todayText: todayText,
        quotaText: work.quotaText,
        stale: work.stale,
        hasData: balanceText.length > 0 || todayText.length > 0 || work.quotaText.length > 0,
        fraction: 0,
        pctText: ''
      };
    });
    // Normalize comparison-bar fractions against the max score; a zero/absent
    // max leaves every fill at 0 with no % labels.
    let maxScore = 0;
    const scores: Array<number | null> = blocks.map((block: ProviderOverview): number | null => {
      const work = workByProvider.get(block.key) as ProviderWork;
      const score = providerScore(work);
      if (score !== null && score > maxScore) {
        maxScore = score;
      }
      return score;
    });
    this.providerBlocks = blocks.map((block: ProviderOverview, index: number): ProviderOverview => {
      const score = scores[index];
      if (score === null || maxScore <= 0 || !block.hasEnabled) {
        return block;
      }
      const fraction = Math.min(Math.max(score / maxScore, 0), 1);
      block.fraction = fraction;
      block.pctText = `${Math.round(fraction * 100)}%`;
      return block;
    });
  }

  @Builder
  themeMenuItem(mode: ThemeMode, label: Resource) {
    Row({ space: 6 }) {
      Text(this.themeMode === mode ? '✓' : '')
        .fontSize(13)
        .fontColor($r('app.color.accentTeal'))
        .width(16)
      Text(label)
        .fontSize(14)
        .fontWeight(this.themeMode === mode ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.themeMode === mode ? $r('app.color.accentTeal') : $r('app.color.textPrimary'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.selectTheme(mode);
    })
  }

  @Builder
  themeMenu() {
    Column() {
      this.themeMenuItem('system', $r('app.string.theme_system'))
      this.themeMenuItem('light', $r('app.string.theme_light'))
      this.themeMenuItem('dark', $r('app.string.theme_dark'))
    }
    .width(168)
  }

  // Pre-warm every TabContent so first switches don't pay the lazy-build
  // cost. Each view's once-per-launch auto-refresh still fires exactly once
  // (guarded inside AccountDetailView) — preloading only moves it earlier.
  private preloadTabs(): void {
    const count = this.accounts.length;
    if (count < 2) {
      return;
    }
    const indices: number[] = [];
    for (let i = 0; i < count; i++) {
      indices.push(i);
    }
    this.tabsController.preloadItems(indices).catch((error: Object) => {
      // Preload is a best-effort latency mitigation; failures are harmless.
    });
  }

  private async refreshAll(): Promise<void> {
    if (this.refreshingAll) {
      return;
    }
    this.refreshingAll = true;
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const service = await AccountService.create(context);
      await service.refreshAllEnabled();
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
    this.refreshingAll = false;
    await this.reload();
    // Tell every embedded detail view to re-read its cached snapshot.
    this.syncTick += 1;
  }

  // Compact pill chip for the top-bar actions: brand tint fill (accentTealTint
  // is 16%-alpha of the mode's teal in both palettes) + accentTeal label —
  // legible in light (#0E9C93 on its tint) and dark (#57E0D6 on its tint).
  @Styles
  chipStyle() {
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.accentTealTint'))
    .borderRadius(18)
  }

  @Builder
  providerBlock(block: ProviderOverview) {
    Stack({ alignContent: Alignment.Start }) {
      // Comparison-fill track behind the content: width = score ÷ max score.
      // accentTealTint (16%-alpha of the mode's teal) stays legible under
      // textPrimary/accentTeal text in both palettes.
      Row() {
        Column()
          .width(`${Math.round(block.fraction * 100)}%`)
          .height('100%')
          .backgroundColor($r('app.color.accentTealTint'))
      }
      .width('100%')
      .height('100%')

      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Column()
            .width(3)
            .height(12)
            .borderRadius(2)
            .backgroundColor($r('app.color.accentTeal'))
          Text(block.name)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.textPrimary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (block.stale) {
            Text($r('app.string.stale_hint_short'))
              .fontSize(10)
              .fontColor($r('app.color.warning'))
              .maxLines(1)
          }
          if (block.pctText.length > 0) {
            Text(block.pctText)
              .fontSize(10)
              .fontColor($r('app.color.textSecondary'))
              .maxLines(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (!block.hasEnabled) {
          Text($r('app.string.overview_disabled'))
            .fontSize(12)
            .fontColor($r('app.color.textSecondary'))
        } else if (!block.hasData) {
          Text($r('app.string.no_data'))
            .fontSize(12)
            .fontColor($r('app.color.textSecondary'))
        } else {
          if (block.balanceText.length > 0) {
            Text(block.balanceText)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.accentTeal'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (block.todayText.length > 0) {
            Text(block.todayText)
              .fontSize(11)
              .fontColor($r('app.color.textSecondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (block.quotaText.length > 0) {
            Text(block.quotaText)
              .fontSize(11)
              .fontColor($r('app.color.textSecondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor($r('app.color.appBackground'))
    .borderRadius(10)
    .clip(true)
    .opacity(block.hasEnabled ? 1 : 0.5)
  }

  // 常驻 overview panel: always rendered when ≥1 account exists, even with
  // zero cached snapshots — missing data shows '--' / 暂无数据 placeholders
  // inside the panel instead of hiding it. Header keeps only today's totals
  // (prominent); providers are a vertical multi-row list of full-width
  // consumption-comparison rows at every screen width.
  @Builder
  overviewPanel() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text($r('app.string.overview_label'))
          .fontSize(11)
          .fontColor($r('app.color.textSecondary'))
          .margin({ top: 6 })
        Row({ space: 8 }) {
          Text($r('app.string.overview_today'))
            .fontSize(12)
            .fontColor($r('app.color.textSecondary'))
          Text(this.overviewToday.length > 0 ? this.overviewToday : '--')
            .fontSize(21)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accentTeal'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.overviewPartial) {
            Text($r('app.string.overview_partial'))
              .fontSize(11)
              .fontColor($r('app.color.warning'))
              .maxLines(1)
          }
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.providerBlocks.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.providerBlocks, (block: ProviderOverview) => {
            this.providerBlock(block)
          }, (block: ProviderOverview) => block.key)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.cardBackground'))
    .borderRadius(14)
    .margin({ left: 16, right: 16, bottom: 10 })
  }

  @Builder
  tabBuilder(account: Account, index: number) {
    Column({ space: 6 }) {
      Text(account.displayName.length > 0 ? account.displayName : providerDisplayName(account.provider))
        .fontSize(15)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? $r('app.color.accentTeal') : $r('app.color.textSecondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .opacity(account.isEnabled ? 1 : 0.5)
      Column()
        .width('100%')
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.currentIndex === index ? $r('app.color.accentTeal') : Color.Transparent)
    }
    .padding({ left: 8, right: 8, top: 10, bottom: 8 })
  }

  @Builder
  onboardingBody() {
    Column({ space: 0 }) {
      Stack() {
        Progress({ value: 72, total: 100, type: ProgressType.Ring })
          .width(104)
          .height(104)
          .color($r('app.color.accentTeal'))
          .backgroundColor($r('app.color.slateSecondary'))
        Circle()
          .width(10)
          .height(10)
          .fill($r('app.color.highlightCyan'))
          .offset({ x: 0, y: -47 })
      }

      Text('QuotaGlance')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.textPrimary'))
        .margin({ top: 24 })

      Text($r('app.string.onboarding_tagline'))
        .fontSize(15)
        .fontColor($r('app.color.textSecondary'))
        .margin({ top: 10 })

      Text($r('app.string.onboarding_hint'))
        .fontSize(12)
        .fontColor($r('app.color.slateSecondary'))
        .margin({ top: 6 })

      Button($r('app.string.add_account'))
        .width(200)
        .height(44)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.appBackground'))
        .backgroundColor($r('app.color.accentTeal'))
        .borderRadius(22)
        .margin({ top: 36 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/AccountEditorPage' });
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 480 })
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  tabsBody() {
    Tabs({ barPosition: BarPosition.Start, index: this.currentIndex, controller: this.tabsController }) {
      ForEach(this.accounts, (account: Account, index: number) => {
        TabContent() {
          AccountDetailView({ accountId: account.id, dim: false, syncTick: this.syncTick })
        }
        .tabBar(this.tabBuilder(account, index))
      }, (account: Account) => account.id)
    }
    .barMode(BarMode.Fixed)
    .animationDuration(0)
    .barBackgroundColor($r('app.color.appBackground'))
    .width('100%')
    .layoutWeight(1)
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }

  build() {
    Column() {
      Row() {
        Text('QuotaGlance')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.textPrimary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.accounts.length > 0) {
          Row() {
            if (this.refreshingAll) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color($r('app.color.accentTeal'))
            } else {
              Text('⟳')
                .fontSize(15)
                .fontColor($r('app.color.accentTeal'))
            }
          }
          .justifyContent(FlexAlign.Center)
          .width(42)
          .chipStyle()
          .margin({ right: 8 })
          .onClick(() => {
            this.refreshAll();
          })
        }
        Text($r('app.string.theme'))
          .fontSize(14)
          .fontColor($r('app.color.accentTeal'))
          .chipStyle()
          .margin({ right: 8 })
          .bindMenu(this.themeMenu(), {
            backgroundColor: $r('app.color.cardBackground'),
            borderRadius: 12,
            placement: Placement.Bottom,
            enableArrow: false
          })
        Text($r('app.string.screensaver'))
          .fontSize(14)
          .fontColor($r('app.color.accentTeal'))
          .chipStyle()
          .margin({ right: 8 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/ScreensaverPage' });
          })
        Text($r('app.string.manage_accounts'))
          .fontSize(14)
          .fontColor($r('app.color.accentTeal'))
          .chipStyle()
          .onClick(() => {
            router.pushUrl({ url: 'pages/AccountsPage' });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 20, right: 20 })

      if (this.accounts.length > 0) {
        this.overviewPanel()
      }

      if (this.accounts.length === 0) {
        this.onboardingBody()
      } else {
        this.tabsBody()
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.appBackground'))
  }
}
