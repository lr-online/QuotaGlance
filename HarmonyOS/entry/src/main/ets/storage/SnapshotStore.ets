import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { UsageSnapshot } from '../providers/UsageSnapshot';
import { formatAmount } from '../utils/NumberFormat';

// Per-account cached snapshots in the shared 'quotaglance_store' preferences
// file. Keys:
//   snapshot_<accountId>        - JSON-serialized UsageSnapshot
//   snapshot_stale_<accountId>  - bool, last refresh failed
const STORE_NAME = 'quotaglance_store';
const SNAPSHOT_PREFIX = 'snapshot_';
const STALE_PREFIX = 'snapshot_stale_';

export interface StoredSnapshot {
  snapshot: UsageSnapshot;
  isStale: boolean;
}

export class SnapshotStore {
  private readonly store: preferences.Preferences;

  private constructor(store: preferences.Preferences) {
    this.store = store;
  }

  static async create(context: common.Context): Promise<SnapshotStore> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    return new SnapshotStore(store);
  }

  async save(accountId: string, snapshot: UsageSnapshot): Promise<void> {
    await this.store.put(SNAPSHOT_PREFIX + accountId, JSON.stringify(snapshot));
    await this.store.put(STALE_PREFIX + accountId, false);
    await this.store.flush();
  }

  async markStale(accountId: string): Promise<void> {
    await this.store.put(STALE_PREFIX + accountId, true);
    await this.store.flush();
  }

  async load(accountId: string): Promise<StoredSnapshot | null> {
    const raw = await this.store.get(SNAPSHOT_PREFIX + accountId, '') as string;
    if (raw.length === 0) {
      return null;
    }
    try {
      const snapshot = JSON.parse(raw) as UsageSnapshot;
      const isStale = await this.store.get(STALE_PREFIX + accountId, false) as boolean;
      return { snapshot: snapshot, isStale: isStale };
    } catch (error) {
      return null;
    }
  }

  async clear(accountId: string): Promise<void> {
    await this.store.delete(SNAPSHOT_PREFIX + accountId);
    await this.store.delete(STALE_PREFIX + accountId);
    await this.store.flush();
  }
}

// Presentation helper for the current single-account UI and widget. Reads the
// primary balance (balances[0]) exactly as before; a later UI pass replaces
// presentation wholesale.
export function formatSnapshotTexts(context: common.Context, stored: StoredSnapshot | null): Record<string, string> {
  const rm = context.resourceManager;
  if (!stored || stored.snapshot.balances.length === 0) {
    return {
      'balanceText': rm.getStringSync($r('app.string.widget_balance_unconfigured').id),
      'statusText': rm.getStringSync($r('app.string.widget_status_prompt_key').id),
      'updatedAtText': ''
    };
  }
  const snapshot = stored.snapshot;
  const primary = snapshot.balances[0];
  const texts: Record<string, string> = {
    'balanceText': `${formatAmount(primary.available.amount)} ${primary.available.currency}`,
    'statusText': rm.getStringSync($r('app.string.widget_status_ok').id),
    'updatedAtText': formatTime(
      snapshot.receivedAtMs,
      rm.getStringSync($r('app.string.updated_prefix').id)
    )
  };
  if (stored.isStale) {
    texts['statusText'] = rm.getStringSync($r('app.string.stale_text').id);
  } else if (snapshot.providerStatus !== 'active') {
    texts['statusText'] = rm.getStringSync($r('app.string.widget_status_unavailable').id);
  }
  return texts;
}

function formatTime(ms: number, prefix: string): string {
  const date = new Date(ms);
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');
  return `${prefix} ${hours}:${minutes}`;
}
