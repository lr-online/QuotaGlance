import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AccountService } from '../services/AccountService';
import { LanguagePreference, LanguageStore } from '../storage/LanguageStore';
import { registerBackgroundRefresh } from '../services/BackgroundRefreshScheduler';
import { setPendingDeepLink } from '../services/DeepLink';
import { FormBindingStore } from '../storage/FormBindingStore';
import { ThemeMode, ThemeStore } from '../storage/ThemeStore';
import { applyLanguage } from '../utils/LanguageUtils';
import { applyThemeMode, reapplyWindowBackground } from '../utils/ThemeUtils';
import { updateAllCards } from '../services/CardUpdater';

const DOMAIN = 0x0000;
const FORM_ID_PARAM = 'ohos.extra.param.key.form_identity';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'QuotaGlance', '%{public}s', 'Ability onCreate');
    this.captureDeepLink(want);
    // Periodic background refresh via Work Scheduler Kit; best-effort, never
    // blocks launch (see BackgroundRefreshScheduler).
    registerBackgroundRefresh(this.context);
    AccountService.create(this.context)
      .then((service: AccountService) => service.ensureLegacyMigration())
      .catch((error: Object) => {
        hilog.error(DOMAIN, 'QuotaGlance', 'legacy migration failed: %{public}s', (error as Error).message);
      });
    // Restore the manual theme override (跟随系统/浅色/深色) before the first
    // frame so resources resolve in the chosen mode from the start.
    ThemeStore.create(this.context)
      .then((store: ThemeStore) => store.load())
      .then((mode: ThemeMode) => {
        applyThemeMode(this.context, mode);
        // Existing forms may have been created before the theme was changed;
        // republish their payload so manual light/dark overrides are visible
        // without requiring a refresh or card recreation.
        return updateAllCards(this.context);
      })
      .catch((error: Object) => {
        hilog.warn(DOMAIN, 'QuotaGlance', 'theme restore failed: %{public}s', (error as Error).message);
      });
    LanguageStore.create(this.context)
      .then((store: LanguageStore) => store.load())
      .then((preference: LanguagePreference) => {
        applyLanguage(preference);
      })
      .catch((error: Object) => {
        hilog.warn(DOMAIN, 'QuotaGlance', 'language restore failed: %{public}s', (error as Error).message);
      });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Brand background behind the first frame so launch matches the app
    // theme in whichever color mode is effective (system or manual override).
    reapplyWindowBackground(this.context);
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'QuotaGlance', 'Failed to load content: %{public}s', JSON.stringify(err));
      }
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.captureDeepLink(want);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // Fires for system dark/light flips and is expected to fire for the
    // app-level setColorMode override as well (both are configuration
    // changes); re-resolving here is idempotent with the explicit re-apply
    // the theme switcher performs right after setColorMode.
    reapplyWindowBackground(this.context);
  }

  private captureDeepLink(want: Want): void {
    const accountId = want.parameters?.['accountId'];
    if (typeof accountId === 'string' && accountId.length > 0) {
      setPendingDeepLink({ kind: 'account', targetId: accountId });
      return;
    }
    const formId = want.parameters?.[FORM_ID_PARAM];
    if (typeof formId === 'string' && formId.length > 0) {
      FormBindingStore.create(this.context)
        .then((store: FormBindingStore) => store.bindingFor(formId))
        .then((binding) => {
          if (binding?.accountId !== undefined && binding.accountId.length > 0) {
            setPendingDeepLink({ kind: 'account', targetId: binding.accountId });
          }
        })
        .catch((error: Object) => {
          hilog.warn(DOMAIN, 'QuotaGlance', 'form binding resolve failed: %{public}s', (error as Error).message);
        });
    }
  }
}
