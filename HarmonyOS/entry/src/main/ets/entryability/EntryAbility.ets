import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AccountService } from '../services/AccountService';
import { LanguagePreference, LanguageStore } from '../storage/LanguageStore';
import { ThemeMode, ThemeStore } from '../storage/ThemeStore';
import { applyLanguage } from '../utils/LanguageUtils';
import { applyThemeMode, reapplyWindowBackground } from '../utils/ThemeUtils';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'QuotaGlance', '%{public}s', 'Ability onCreate');
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

  onConfigurationUpdate(newConfig: Configuration): void {
    // Fires for system dark/light flips and is expected to fire for the
    // app-level setColorMode override as well (both are configuration
    // changes); re-resolving here is idempotent with the explicit re-apply
    // the theme switcher performs right after setColorMode.
    reapplyWindowBackground(this.context);
  }
}
