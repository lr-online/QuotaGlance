import { router } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountService } from '../services/AccountService';
import { Account } from '../storage/AccountStore';
import { SnapshotStore, StoredSnapshot } from '../storage/SnapshotStore';
import { UsageSnapshot } from '../providers/UsageSnapshot';
import { formatAmount, formatQuotaValue } from '../utils/NumberFormat';
import { AccountDetailView } from '../components/AccountDetailView';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlanceScreensaver';
const MAX_ROWS = 5;
const CLOCK_INTERVAL_MS = 1000;
const DRIFT_INTERVAL_MS = 60 * 1000;
const REFRESH_INTERVAL_MS = 5 * 60 * 1000;
const DIM_BRIGHTNESS = 0.08;

interface SaverRow {
  accountId: string;
  displayName: string;
  metricText: string;
  isStale: boolean;
}

interface ScreensaverParams {
  accountId: string;
}

function pad2(value: number): string {
  return value.toString().padStart(2, '0');
}

// Primary-metric priority mirrors the dashboard card in Index.ets:
// first balance, else spending limit, else first quota window, else dash.
function primaryMetric(snapshot: UsageSnapshot): string {
  if (snapshot.balances.length > 0) {
    const available = snapshot.balances[0].available;
    return `${formatAmount(available.amount)} ${available.currency}`;
  }
  if (snapshot.spendingLimit !== undefined) {
    const limit = snapshot.spendingLimit;
    const main = limit.remaining ?? limit.used;
    const currency = main !== undefined ? main.currency
      : (limit.limit !== undefined ? limit.limit.currency : '');
    const mainText = main !== undefined ? formatAmount(main.amount) : '--';
    const limitText = limit.limit !== undefined ? `/${formatAmount(limit.limit.amount)}` : '';
    return `${mainText}${limitText} ${currency}`.trim();
  }
  if (snapshot.quotaWindows !== undefined && snapshot.quotaWindows.length > 0) {
    const quota = snapshot.quotaWindows[0];
    const mainText = quota.remaining !== undefined ? formatQuotaValue(quota.remaining)
      : (quota.used !== undefined ? formatQuotaValue(quota.used) : '--');
    const limitText = quota.limit !== undefined ? `/${formatQuotaValue(quota.limit)}` : '';
    return `${mainText}${limitText} ${quota.unit}`.trim();
  }
  return '—';
}

@Entry
@Component
struct ScreensaverPage {
  @State clockText: string = '';
  @State dateText: string = '';
  @State rows: SaverRow[] = [];
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State detailAccountId: string = '';
  @State syncTick: number = 0;

  private mainWindow: window.Window | null = null;
  private windowStateApplied: boolean = false;
  private clockTimer: number = -1;
  private driftTimer: number = -1;
  private refreshTimer: number = -1;
  private driftCounter: number = 0;
  private exiting: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as ScreensaverParams;
    if (params !== undefined && params !== null && typeof params.accountId === 'string'
      && params.accountId.length > 0) {
      this.detailAccountId = params.accountId;
    }
    this.updateClock();
    this.applyWindowState();
    this.clockTimer = setInterval(() => {
      this.updateClock();
    }, CLOCK_INTERVAL_MS);
    this.driftTimer = setInterval(() => {
      this.drift();
    }, DRIFT_INTERVAL_MS);
    this.refreshTimer = setInterval(() => {
      this.pollRefresh();
    }, REFRESH_INTERVAL_MS);
    if (this.detailAccountId.length > 0) {
      // AccountDetailView self-refreshes once per launch; ensure the 5-minute
      // poll also refreshes this single account going forward.
      this.pollRefresh();
    } else {
      this.loadCached().then((hasEnabled: boolean) => {
        if (hasEnabled) {
          this.refreshSnapshots();
        }
      }).catch((error: Object) => {
        hilog.warn(DOMAIN, TAG, 'initial load failed: %{public}s', (error as Error).message);
      });
    }
  }

  aboutToDisappear(): void {
    this.clearTimers();
    this.restoreWindowState();
  }

  private obtainMainWindow(): window.Window | null {
    if (this.mainWindow !== null) {
      return this.mainWindow;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.mainWindow = context.windowStage.getMainWindowSync();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'getMainWindowSync failed: %{public}s', (error as Error).message);
      this.mainWindow = null;
    }
    return this.mainWindow;
  }

  private applyWindowState(): void {
    const win = this.obtainMainWindow();
    if (win === null) {
      return;
    }
    this.windowStateApplied = true;
    // Foreground-only keep-screen-on; the system may still override it for
    // non-interactive surfaces, which this mode tolerates by design.
    win.setWindowKeepScreenOn(true).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'setWindowKeepScreenOn failed: %{public}s', (error as Error).message);
    });
    win.setWindowLayoutFullScreen(true).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', (error as Error).message);
    });
    win.setWindowSystemBarEnable([]).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'hide system bars failed: %{public}s', (error as Error).message);
    });
    win.setWindowBrightness(DIM_BRIGHTNESS).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'setWindowBrightness failed: %{public}s', (error as Error).message);
    });
  }

  // Idempotent: safe to call from both the tap-to-exit path and
  // aboutToDisappear (system back gesture / window teardown).
  private restoreWindowState(): void {
    if (!this.windowStateApplied) {
      return;
    }
    this.windowStateApplied = false;
    const win = this.obtainMainWindow();
    if (win === null) {
      return;
    }
    win.setWindowKeepScreenOn(false).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'restore keepScreenOn failed: %{public}s', (error as Error).message);
    });
    win.setWindowLayoutFullScreen(false).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'restore layout fullscreen failed: %{public}s', (error as Error).message);
    });
    win.setWindowSystemBarEnable(['status', 'navigation']).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'restore system bars failed: %{public}s', (error as Error).message);
    });
    // Per the window API docs, setWindowBrightness(-1) hands brightness back
    // to the system setting (valid values are [0.0, 1.0] or -1.0 for "follow
    // system"); the override also drops automatically when the app exits.
    win.setWindowBrightness(-1).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'restore brightness failed: %{public}s', (error as Error).message);
    });
  }

  private clearTimers(): void {
    if (this.clockTimer >= 0) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
    if (this.driftTimer >= 0) {
      clearInterval(this.driftTimer);
      this.driftTimer = -1;
    }
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private updateClock(): void {
    const now = new Date();
    this.clockText = `${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
    const weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    this.dateText = `${now.getMonth() + 1}月${now.getDate()}日 周${weekdays[now.getDay()]}`;
  }

  // Burn-in mitigation: glide the whole content block a few vp every minute
  // so no pixel cluster holds the same content for long.
  private drift(): void {
    this.driftCounter = (this.driftCounter + 1) % 997;
    const x = ((this.driftCounter * 37) % 49) - 24;
    const y = ((this.driftCounter * 53) % 33) - 16;
    animateTo({
      duration: 800,
      curve: Curve.EaseInOut
    }, () => {
      this.offsetX = x;
      this.offsetY = y;
    });
  }

  private async loadCached(): Promise<boolean> {
    const context = getContext(this) as common.UIAbilityContext;
    const service = await AccountService.create(context);
    const accounts = await service.loadAccounts();
    const enabled = accounts.filter((account: Account) => account.isEnabled).slice(0, MAX_ROWS);
    const store = await SnapshotStore.create(context);
    const rows: SaverRow[] = [];
    for (const account of enabled) {
      const stored: StoredSnapshot | null = await store.load(account.id);
      rows.push({
        accountId: account.id,
        displayName: account.displayName,
        metricText: stored !== null ? primaryMetric(stored.snapshot) : '—',
        isStale: stored !== null && stored.isStale
      });
    }
    this.rows = rows;
    return enabled.length > 0;
  }

  // Fire-and-forget refresh: per-account failures only mark the snapshot
  // stale inside AccountService, then we reload the cached view.
  private refreshSnapshots(): void {
    const context = getContext(this) as common.UIAbilityContext;
    AccountService.create(context)
      .then((service: AccountService) => service.refreshAllEnabled())
      .then(() => this.loadCached())
      .catch((error: Object) => {
        hilog.warn(DOMAIN, TAG, 'refresh failed: %{public}s', (error as Error).message);
      });
  }

  // Detail mode: poll only the source account, then tell the embedded view
  // to re-read its snapshot via syncTick.
  private pollRefresh(): void {
    if (this.detailAccountId.length === 0) {
      this.refreshSnapshots();
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    AccountService.create(context)
      .then((service: AccountService) => {
        return service.loadAccounts().then((accounts: Account[]) => {
          for (const account of accounts) {
            if (account.id === this.detailAccountId) {
              if (account.isEnabled) {
                return service.refreshAccount(account);
              }
              return Promise.resolve();
            }
          }
          return Promise.resolve();
        });
      })
      .then(() => {
        this.syncTick += 1;
      })
      .catch((error: Object) => {
        hilog.warn(DOMAIN, TAG, 'detail refresh failed: %{public}s', (error as Error).message);
      });
  }

  private exitScreensaver(): void {
    if (this.exiting) {
      return;
    }
    this.exiting = true;
    this.clearTimers();
    this.restoreWindowState();
    router.back();
  }

  @Builder
  clockBody() {
    // Content stays one bounded block (~60% width, content height) so the
    // burn-in drift has black room to move into; tap target is the outer
    // full-screen Stack, unaffected by the inner drift offset.
    Column({ space: 0 }) {
      Text(this.clockText)
        .fontSize(96)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.screensaverClock'))
        .opacity(0.9)

      Text(this.dateText)
        .fontSize(16)
        .fontColor($r('app.color.textSecondary'))
        .opacity(0.6)
        .margin({ top: 8 })

      Column({ space: 14 }) {
        ForEach(this.rows, (row: SaverRow) => {
          Row() {
            Text(row.displayName)
              .fontSize(13)
              .fontColor($r('app.color.textSecondary'))
              .opacity(0.7)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(row.metricText)
              .fontSize(16)
              .fontColor($r('app.color.accentTeal'))
              .opacity(0.8)
              .maxLines(1)
            if (row.isStale) {
              Text($r('app.string.stale_hint_short'))
                .fontSize(10)
                .fontColor($r('app.color.textSecondary'))
                .opacity(0.5)
                .margin({ left: 6 })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }, (row: SaverRow) => row.accountId)
      }
      .width('100%')
      .margin({ top: 48 })

      Text($r('app.string.screensaver_exit_hint'))
        .fontSize(11)
        .fontColor($r('app.color.textSecondary'))
        .opacity(0.25)
        .margin({ top: 64 })
    }
    .width('60%')
    .offset({ x: this.offsetX, y: this.offsetY })
  }

  @Builder
  detailBody() {
    // Full account detail in the dim screensaver palette; stays scrollable
    // for long details, bounded so the drift keeps black room around it.
    Column() {
      AccountDetailView({ accountId: this.detailAccountId, dim: true, syncTick: this.syncTick })
    }
    .width('70%')
    .height('85%')
    .offset({ x: this.offsetX, y: this.offsetY })
  }

  build() {
    Stack() {
      if (this.detailAccountId.length > 0) {
        this.detailBody()
      } else {
        this.clockBody()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .backgroundColor('#000000')
    .onClick(() => {
      this.exitScreensaver();
    })
  }
}
