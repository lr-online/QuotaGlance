import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AccountService } from '../services/AccountService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'QuotaGlance', '%{public}s', 'Ability onCreate');
    AccountService.create(this.context)
      .then((service: AccountService) => service.ensureLegacyMigration())
      .catch((error: Object) => {
        hilog.error(DOMAIN, 'QuotaGlance', 'legacy migration failed: %{public}s', (error as Error).message);
      });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'QuotaGlance', 'Failed to load content: %{public}s', JSON.stringify(err));
      }
    });
  }
}
