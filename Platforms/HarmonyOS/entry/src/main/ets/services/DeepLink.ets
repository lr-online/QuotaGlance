import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

// Pending deep-link holder, mirroring the LaunchRefresh listener pattern.
// EntryAbility receives wants from three sources — card router actions
// (postCardAction), notification wantAgent taps, and plain icon launches —
// and hands the interesting ones here. Index consumes the pending link on
// page show / listener notification and performs the actual router.pushUrl
// (router only works from a UI component, not from the ability).
//
// Routes:
//   account → pages/AccountDetailPage (params.accountId)
//   picker  → pages/FormAccountPickerPage (params.formId, per-card account choice)
export type DeepLinkRouteKind = 'account' | 'picker';

export interface DeepLinkRoute {
  kind: DeepLinkRouteKind;
  // accountId for 'account', formId for 'picker'.
  targetId: string;
}

export type DeepLinkListener = () => void;

let pendingDeepLink: DeepLinkRoute | null = null;
const listeners: Set<DeepLinkListener> = new Set();

export function setPendingDeepLink(route: DeepLinkRoute): void {
  pendingDeepLink = route;
  listeners.forEach((listener: DeepLinkListener) => {
    try {
      listener();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'deep-link listener failed: %{public}s', (error as Error).message);
    }
  });
}

// Single-slot consume: the link is cleared so a later unrelated page show
// does not re-navigate.
export function consumePendingDeepLink(): DeepLinkRoute | null {
  const route = pendingDeepLink;
  pendingDeepLink = null;
  return route;
}

export function subscribeDeepLink(listener: DeepLinkListener): void {
  listeners.add(listener);
}

export function unsubscribeDeepLink(listener: DeepLinkListener): void {
  listeners.delete(listener);
}
