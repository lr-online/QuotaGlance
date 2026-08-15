import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

// Cold-launch refresh coordination + overview-refresh events.
//
// 1) Shared launch-refresh promise: Index sets it before building the
//    provider tabs and clears it when refreshAllEnabled settles. A tab's
//    AccountDetailView that comes up while the promise is pending awaits it
//    and reads the cache instead of firing a duplicate network fetch — so
//    each account is fetched exactly once per cold launch.
let launchRefreshPromise: Promise<void> | null = null;

export function setLaunchRefresh(promise: Promise<void>): void {
  launchRefreshPromise = promise;
}

export function clearLaunchRefresh(): void {
  launchRefreshPromise = null;
}

export function getLaunchRefresh(): Promise<void> | null {
  return launchRefreshPromise;
}

// 2) Overview-refresh listeners: any successful account refresh (tab,
//    detail page) notifies, so the Index overview panel recomputes from the
//    snapshot cache instead of waiting for the next page-level reload.
export type OverviewListener = () => void;

const overviewListeners: Set<OverviewListener> = new Set();

export function subscribeOverviewRefresh(listener: OverviewListener): void {
  overviewListeners.add(listener);
}

export function unsubscribeOverviewRefresh(listener: OverviewListener): void {
  overviewListeners.delete(listener);
}

export function notifyOverviewRefresh(): void {
  overviewListeners.forEach((listener: OverviewListener) => {
    try {
      listener();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'overview listener failed: %{public}s', (error as Error).message);
    }
  });
}
