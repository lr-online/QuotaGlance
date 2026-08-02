import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent, Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Account, AccountStore } from '../storage/AccountStore';
import { AlertStateStore } from '../storage/AlertStateStore';
import { SnapshotStore } from '../storage/SnapshotStore';
import { notificationIdForAccount } from '../storage/StateCodecs';
import {
  AlertAccount,
  AlertSnapshotInput,
  evaluateAlertBatch
} from '../alerts/AlertEvaluator';
import { Money } from '../providers/UsageSnapshot';
import { formatAmount } from '../utils/NumberFormat';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

// Notification Kit adapter + low-balance alert orchestration. The adapter
// part (ensurePermissionOnce / publishLowBalance) carries no business rules;
// evaluateAndNotifyAlerts is the post-refresh glue that feeds the I/O-free
// AlertEvaluator: load accounts + persisted episode flags, evaluate against
// the freshly persisted snapshots, persist mutated flags, publish one
// notification per crossing. Called from AccountService's post-refresh hooks,
// so BOTH foreground batches and the WorkSchedulerAbility background batch
// run the same evaluation (the engine itself stays I/O-free).

// One-shot permission prompt guard in the shared preferences file.
const STORE_NAME = 'quotaglance_store';
const PERMISSION_ASKED_FLAG = 'notification_permission_prompted_v1';
const LEGACY_PERMISSION_ASKED_FLAG = 'notification_permission_asked_v1';

// First-use moment for the notification permission prompt: app launch, but
// only once at least one account exists (no accounts = nothing to notify
// about), and only once per install — re-prompting a user who already
// declined on every launch is spam. The system dialog is shown by
// requestEnableNotification; the result is not tracked here, publishing
// re-checks isNotificationEnabled() every time.
export async function requestNotificationPermissionOnce(context: common.UIAbilityContext,
  hasAccounts: boolean): Promise<void> {
  if (!hasAccounts) {
    return;
  }
  try {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    const asked = await store.get(PERMISSION_ASKED_FLAG,
      await store.get(LEGACY_PERMISSION_ASKED_FLAG, false)) as boolean;
    if (asked) {
      return;
    }
    await store.put(PERMISSION_ASKED_FLAG, true);
    await store.flush();
    await notificationManager.requestEnableNotification(context);
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'notification permission request failed: %{public}s', (error as Error).message);
  }
}

// Publishes one low-balance notification whose tap deep-links into the
// account's detail page: the wantAgent want carries parameters.accountId,
// which EntryAbility turns into a pending deep link (see services/DeepLink).
async function publishLowBalance(context: common.Context, account: AlertAccount,
  remaining: Money): Promise<void> {
  const enabled = await notificationManager.isNotificationEnabled();
  if (!enabled) {
    hilog.info(DOMAIN, TAG, 'notifications disabled, skip publish: %{public}s', account.id);
    return;
  }
  const bundleName = context.applicationInfo.name;
  const want: Want = {
    bundleName: bundleName,
    abilityName: 'EntryAbility',
    parameters: { 'accountId': account.id }
  };
  const agent = await wantAgent.getWantAgent({
    wants: [want],
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: 0,
    actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
  });
  const title = context.resourceManager.getStringSync($r('app.string.low_balance_title').id);
  const body = context.resourceManager.getStringSync($r('app.string.low_balance_body').id,
    account.displayName, `${formatAmount(remaining.amount)} ${remaining.currency}`,
    account.lowBalanceThreshold ?? '');
  const request: notificationManager.NotificationRequest = {
    id: notificationIdForAccount(account.id),
    content: {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: title,
        text: body
      }
    },
    wantAgent: agent
  };
  await notificationManager.publish(request);
  hilog.info(DOMAIN, TAG, 'low-balance notification published: %{public}s', account.id);
}

// Post-refresh alert evaluation. freshlyRefreshedIds are the accounts whose
// snapshots were just persisted as fresh; everything else (failed/stale) is
// inert in the engine, mirroring Swift AppModel.evaluateAlerts.
//
// Invocations are serialized on a module-level queue: a batch fans this out
// once per refreshed account (refreshAccount) plus once at batch completion
// (RefreshCoordinator.afterBatch), and concurrent runs could otherwise read
// the same pre-mutation episode flags and publish duplicate notifications.
// Queued runs re-read the persisted flags, so the episode debounce makes
// repeated evaluation idempotent.
let evaluationQueue: Promise<void> = Promise.resolve();

export async function evaluateAndNotifyAlerts(context: common.Context,
  freshlyRefreshedIds: string[]): Promise<void> {
  if (freshlyRefreshedIds.length === 0) {
    return;
  }
  evaluationQueue = evaluationQueue
    .then(() => runAlertEvaluation(context, freshlyRefreshedIds))
    .catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'alert evaluation failed: %{public}s', (error as Error).message);
    });
  return evaluationQueue;
}

async function runAlertEvaluation(context: common.Context,
  freshlyRefreshedIds: string[]): Promise<void> {
  try {
    const accountStore = await AccountStore.create(context);
    const alertStateStore = await AlertStateStore.create(context);
    const snapshotStore = await SnapshotStore.create(context);
    const accounts = await accountStore.load();
    const episodes = await alertStateStore.load();

    const freshSnapshots: AlertSnapshotInput[] = [];
    for (const accountId of freshlyRefreshedIds) {
      const stored = await snapshotStore.load(accountId);
      if (stored === null || stored.isStale) {
        continue;
      }
      const input: AlertSnapshotInput = {
        accountID: accountId,
        health: 'healthy'
      };
      const remaining = stored.snapshot.balances.length > 0
        ? stored.snapshot.balances[0].available
        : undefined;
      if (remaining !== undefined) {
        input.remaining = remaining;
      }
      freshSnapshots.push(input);
    }

    const alertAccounts: AlertAccount[] = accounts.map((account: Account): AlertAccount => {
      const alertAccount: AlertAccount = {
        id: account.id,
        displayName: account.displayName,
        isEnabled: account.isEnabled,
        alertEpisodeActive: episodes.get(account.id) ?? false
      };
      if (account.lowBalanceThreshold !== undefined) {
        alertAccount.lowBalanceThreshold = account.lowBalanceThreshold;
      }
      return alertAccount;
    });

    const evaluation = evaluateAlertBatch(alertAccounts, freshSnapshots);

    // Episode flags are persisted regardless of notification permission —
    // Swift persists on didChange before checking authorization, so a user
    // who grants permission later is not re-notified for an old crossing.
    if (evaluation.didChange) {
      const flags = new Map<string, boolean>();
      for (const account of alertAccounts) {
        if (account.alertEpisodeActive) {
          flags.set(account.id, true);
        }
      }
      await alertStateStore.save(flags);
    }
    for (const notification of evaluation.notifications) {
      await publishLowBalance(context, notification.account, notification.remaining);
    }
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'alert evaluation failed: %{public}s', (error as Error).message);
  }
}
