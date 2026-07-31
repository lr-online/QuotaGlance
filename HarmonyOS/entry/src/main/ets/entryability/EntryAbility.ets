import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AccountService } from '../services/AccountService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindowStage: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'QuotaGlance', '%{public}s', 'Ability onCreate');
    AccountService.create(this.context)
      .then((service: AccountService) => service.ensureLegacyMigration())
      .catch((error: Object) => {
        hilog.error(DOMAIN, 'QuotaGlance', 'legacy migration failed: %{public}s', (error as Error).message);
      });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainWindowStage = windowStage;
    // Brand background behind the first frame so launch matches the app
    // theme in whichever color mode the system is in.
    this.applyWindowBackground();
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'QuotaGlance', 'Failed to load content: %{public}s', JSON.stringify(err));
      }
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // System dark/light flip while the app is alive: re-resolve the
    // mode-aware color so the window background tracks the theme.
    this.applyWindowBackground();
  }

  // Resolve appBackground through resourceManager — it follows the current
  // color mode (resources/base = light, resources/dark = dark) — instead of
  // pinning a fixed hex. setWindowBackgroundColor takes a hex string, so the
  // resolved 0xAARRGGBB number is reduced to its RGB part.
  private applyWindowBackground(): void {
    const stage = this.mainWindowStage;
    if (stage === null) {
      return;
    }
    try {
      const color = this.context.resourceManager.getColorSync($r('app.color.appBackground').id);
      const rgb = `#${(color & 0xFFFFFF).toString(16).padStart(6, '0')}`;
      stage.getMainWindowSync().setWindowBackgroundColor(rgb);
    } catch (error) {
      hilog.warn(DOMAIN, 'QuotaGlance', 'setWindowBackgroundColor failed: %{public}s', (error as Error).message);
    }
  }
}
