import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountService } from '../services/AccountService';
import { RefreshResult } from '../services/RefreshCoordinator';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

// Periodic background refresh entry point. The system starts this extension
// when the registered work's conditions (network + repeat cycle) are met;
// onWorkStart refreshes all enabled accounts through the RefreshCoordinator,
// persisting fresh snapshots (or stale markings) for the next UI/widget read.
export default class WorkSchedulerAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, TAG, 'background refresh work start: %{public}d', work.workId);
    AccountService.create(this.context)
      .then((service: AccountService) => service.getRefreshCoordinator().refreshAllEnabled())
      .then((result: RefreshResult) => {
        hilog.info(DOMAIN, TAG, 'background refresh done: %{public}s %{public}d ok',
          result.outcome, result.succeeded.length);
      })
      .catch((error: Object) => {
        hilog.warn(DOMAIN, TAG, 'background refresh failed: %{public}s', (error as Error).message);
      });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, TAG, 'background refresh work stop: %{public}d', work.workId);
  }
}
