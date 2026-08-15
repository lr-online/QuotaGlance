import { hilog } from '@kit.PerformanceAnalysisKit';
import { RefreshResult } from './RefreshCoordinator';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

// Host-level completion effects for one refresh run. Provider fetches and
// snapshot persistence remain behind AccountService's refresh seam; this
// module owns the effects that must happen once after that seam completes.
export interface RefreshEffectsDeps {
  invalidateOverview: () => void;
  publishCards: () => Promise<void>;
  evaluateAlerts: (freshlyRefreshedIds: string[]) => Promise<void>;
}

export class RefreshEffects {
  private readonly deps: RefreshEffectsDeps;

  constructor(deps: RefreshEffectsDeps) {
    this.deps = deps;
  }

  // A completed run always invalidates quick-view state, including all-failed
  // runs whose stale snapshot state changed. Alert evaluation is limited to
  // newly fresh snapshots, so failed accounts cannot alter an alert episode.
  async apply(result: RefreshResult): Promise<void> {
    if (result.succeeded.length > 0) {
      try {
        // This persists alert episode transitions before notification delivery.
        await this.deps.evaluateAlerts(result.succeeded);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'alert evaluation failed: %{public}s', (error as Error).message);
      }
    }
    this.deps.invalidateOverview();
    try {
      await this.deps.publishCards();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'card update failed: %{public}s', (error as Error).message);
    }
  }
}
