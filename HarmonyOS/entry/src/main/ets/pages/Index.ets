import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AccountService } from '../services/AccountService';
import { Account } from '../storage/AccountStore';
import { providerDisplayName } from '../providers/UsageProvider';
import { friendlyErrorText } from '../utils/ErrorMapping';
import { ThemeMode, ThemeStore } from '../storage/ThemeStore';
import { applyThemeMode, reapplyWindowBackground } from '../utils/ThemeUtils';
import { AccountDetailView } from '../components/AccountDetailView';

const THEME_MODES: ThemeMode[] = ['system', 'light', 'dark'];
const THEME_CHOOSER_LABELS: string[] = ['跟随系统', '浅色', '深色'];

@Entry
@Component
struct Index {
  @State accounts: Account[] = [];
  @State refreshingAll: boolean = false;
  @State currentIndex: number = 0;
  @State syncTick: number = 0;
  @State themeMode: ThemeMode = 'system';
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
  }

  private themeLabel(): string {
    if (this.themeMode === 'light') {
      return '浅色';
    }
    if (this.themeMode === 'dark') {
      return '深色';
    }
    return '跟随';
  }

  private openThemeChooser(): void {
    const context = getContext(this) as common.UIAbilityContext;
    promptAction.showActionMenu({
      title: '主题',
      buttons: [
        { text: THEME_CHOOSER_LABELS[0], color: $r('app.color.textPrimary') },
        { text: THEME_CHOOSER_LABELS[1], color: $r('app.color.textPrimary') },
        { text: THEME_CHOOSER_LABELS[2], color: $r('app.color.textPrimary') }
      ]
    }).then((response: promptAction.ActionMenuSuccessResponse) => {
      if (response.index < 0 || response.index >= THEME_MODES.length) {
        return;
      }
      const mode = THEME_MODES[response.index];
      if (mode === this.themeMode) {
        return;
      }
      this.themeMode = mode;
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
    }).catch((error: Object) => {
      // Dismissed without a selection; nothing to do.
    });
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
        Blank()
        if (this.accounts.length > 0) {
          if (this.refreshingAll) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('app.color.accentTeal'))
              .margin({ right: 16 })
          } else {
            Text('⟳')
              .fontSize(20)
              .fontColor($r('app.color.accentTeal'))
              .margin({ right: 16 })
              .padding(4)
              .onClick(() => {
                this.refreshAll();
              })
          }
        }
        Text(this.themeLabel())
          .fontSize(15)
          .fontColor($r('app.color.accentTeal'))
          .padding(4)
          .margin({ right: 16 })
          .onClick(() => {
            this.openThemeChooser();
          })
        Text($r('app.string.screensaver'))
          .fontSize(15)
          .fontColor($r('app.color.accentTeal'))
          .padding(4)
          .margin({ right: 16 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/ScreensaverPage' });
          })
        Text($r('app.string.manage_accounts'))
          .fontSize(15)
          .fontColor($r('app.color.accentTeal'))
          .padding(4)
          .onClick(() => {
            router.pushUrl({ url: 'pages/AccountsPage' });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 20, right: 20 })

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
