import { common } from '@kit.AbilityKit';
import { compareDecimalStrings } from '../alerts/AlertEvaluator';
import { Account } from '../storage/AccountStore';
import { StoredSnapshot } from '../storage/SnapshotStore';
import { formatAmount } from './NumberFormat';

export type ScreensaverMessageSeverity = 'info' | 'warning' | 'error';

export interface ScreensaverMessage {
  id: string;
  accountId?: string;
  severity: ScreensaverMessageSeverity;
  title: string;
  detail: string;
  createdAtMs: number;
}

export interface ScreensaverMessageSource {
  account: Account;
  stored: StoredSnapshot | null;
}

function severityRank(severity: ScreensaverMessageSeverity): number {
  if (severity === 'error') {
    return 3;
  }
  if (severity === 'warning') {
    return 2;
  }
  return 1;
}

function messageTime(source: ScreensaverMessageSource): number {
  return source.stored?.lastAttemptAtMs
    ?? source.stored?.lastSuccessAtMs
    ?? source.stored?.snapshot.receivedAtMs
    ?? 0;
}

function message(source: ScreensaverMessageSource, severity: ScreensaverMessageSeverity,
  title: string, detail: string): ScreensaverMessage {
  return {
    id: `${source.account.id}:${severity}:${source.stored?.lastErrorToken ?? 'state'}`,
    accountId: source.account.id,
    severity: severity,
    title: title,
    detail: detail,
    createdAtMs: messageTime(source)
  };
}

function lowBalanceMessage(context: common.Context, source: ScreensaverMessageSource): ScreensaverMessage | null {
  const thresholdText = source.account.lowBalanceThreshold;
  const stored = source.stored;
  if (thresholdText === undefined || stored === null || stored.isStale
    || stored.snapshot.balances.length === 0) {
    return null;
  }
  const balance = stored.snapshot.balances[0].available;
  if (compareDecimalStrings(balance.amount, thresholdText) > 0) {
    return null;
  }
  const rm = context.resourceManager;
  return message(source, 'warning',
    rm.getStringSync($r('app.string.screensaver_message_low_balance_title').id),
    rm.getStringSync($r('app.string.low_balance_body').id, source.account.displayName,
      `${formatAmount(balance.amount)} ${balance.currency}`, thresholdText));
}

export function buildScreensaverMessages(context: common.Context,
  sources: ScreensaverMessageSource[]): ScreensaverMessage[] {
  const rm = context.resourceManager;
  const messages: ScreensaverMessage[] = [];
  for (const source of sources) {
    if (!source.account.isEnabled) {
      continue;
    }
    const stored = source.stored;
    if (stored === null) {
      messages.push(message(source, 'info',
        rm.getStringSync($r('app.string.screensaver_message_not_refreshed_title').id),
        rm.getStringSync($r('app.string.not_refreshed').id)));
      continue;
    }
    if (stored.isStale) {
      messages.push(message(source, 'error',
        rm.getStringSync($r('app.string.screensaver_message_stale_title').id),
        rm.getStringSync($r('app.string.stale_text').id)));
      continue;
    }
    if (stored.snapshot.providerStatus !== undefined && stored.snapshot.providerStatus !== 'active') {
      messages.push(message(source, 'error',
        rm.getStringSync($r('app.string.screensaver_message_unavailable_title').id),
        rm.getStringSync($r('app.string.widget_status_unavailable').id)));
      continue;
    }
    if (stored.snapshot.metricsUnavailableReason !== undefined) {
      messages.push(message(source, 'warning',
        rm.getStringSync($r('app.string.screensaver_message_metrics_title').id),
        rm.getStringSync($r('app.string.screensaver_message_metrics_detail').id)));
    }
    const lowBalance = lowBalanceMessage(context, source);
    if (lowBalance !== null) {
      messages.push(lowBalance);
    }
  }
  messages.sort((left: ScreensaverMessage, right: ScreensaverMessage): number => {
    const rank = severityRank(right.severity) - severityRank(left.severity);
    if (rank !== 0) {
      return rank;
    }
    if (right.createdAtMs !== left.createdAtMs) {
      return right.createdAtMs - left.createdAtMs;
    }
    return left.id < right.id ? -1 : (left.id > right.id ? 1 : 0);
  });
  return messages.slice(0, 3);
}

export function messageColor(severity: ScreensaverMessageSeverity): string {
  if (severity === 'error') {
    return '#FF6B6B';
  }
  if (severity === 'warning') {
    return '#F5C15D';
  }
  return '#8FE8DF';
}
