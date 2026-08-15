import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { workScheduler } from '@kit.BackgroundTasksKit';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

// Registers the periodic background refresh work with Work Scheduler Kit.
// The work triggers WorkSchedulerAbility (see module.json5), whose onWorkStart
// runs RefreshCoordinator.refreshAllEnabled.
//
// The system — not the app — decides when the work actually fires: the repeat
// cycle is clamped to a system-enforced minimum and the trigger additionally
// requires the declared network condition. This is a registered platform
// difference from Swift RefreshCoordinator's timer semantics (see
// HarmonyOS/AGENTS.md 平台差异白名单). Re-registering on every launch keeps
// the work info current (bundle/ability name can't drift stale).
const WORK_ID = 1;
// 30 minutes; the system may round this up to its enforced minimum.
const REPEAT_CYCLE_MS = 30 * 60 * 1000;

function buildWorkInfo(bundleName: string): workScheduler.WorkInfo {
  const work: workScheduler.WorkInfo = {
    workId: WORK_ID,
    bundleName: bundleName,
    abilityName: 'WorkSchedulerAbility',
    // Only run with network connectivity; any type will do.
    networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
    isPersisted: true,
    isRepeat: true,
    repeatCycleTime: REPEAT_CYCLE_MS
  };
  return work;
}

// Best-effort: scheduling failures (e.g. system restrictions) must never
// block app launch, so every error is logged and swallowed.
export function registerBackgroundRefresh(context: common.UIAbilityContext): void {
  try {
    const work = buildWorkInfo(context.abilityInfo.bundleName);
    // Replace any stale registration for this work id before re-adding.
    try {
      workScheduler.stopWork(work, true);
    } catch (error) {
      // Not registered yet — nothing to stop.
    }
    workScheduler.startWork(work);
    hilog.info(DOMAIN, TAG, 'background refresh work registered');
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'background refresh registration failed: %{public}s', (error as Error).message);
  }
}
