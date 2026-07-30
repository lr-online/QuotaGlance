import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { UsageSnapshot } from '../providers/UsageSnapshot';

const STORE_NAME = 'quotaglance_store';
const SNAPSHOT_KEY = 'deepseek_snapshot';
const STALE_KEY = 'deepseek_snapshot_stale';

export interface StoredSnapshot {
  snapshot: UsageSnapshot | null;
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

  async save(snapshot: UsageSnapshot): Promise<void> {
    await this.store.put(SNAPSHOT_KEY, JSON.stringify(snapshot));
    await this.store.put(STALE_KEY, false);
    await this.store.flush();
  }

  async markStale(): Promise<void> {
    await this.store.put(STALE_KEY, true);
    await this.store.flush();
  }

  async load(): Promise<StoredSnapshot> {
    const raw = await this.store.get(SNAPSHOT_KEY, '') as string;
    const isStale = await this.store.get(STALE_KEY, false) as boolean;
    if (raw.length === 0) {
      return { snapshot: null, isStale: false };
    }
    try {
      return { snapshot: JSON.parse(raw) as UsageSnapshot, isStale: isStale };
    } catch (error) {
      return { snapshot: null, isStale: false };
    }
  }
}

export function formatSnapshotTexts(stored: StoredSnapshot): Record<string, string> {
  if (!stored.snapshot) {
    return {
      'balanceText': '未配置',
      'statusText': '打开应用录入 DeepSeek API Key',
      'updatedAtText': ''
    };
  }
  const snapshot = stored.snapshot;
  const primary = snapshot.balances[0];
  const texts: Record<string, string> = {
    'balanceText': `${primary.available.amount} ${primary.available.currency}`,
    'statusText': '正常',
    'updatedAtText': formatTime(snapshot.receivedAtMs)
  };
  if (stored.isStale) {
    texts['statusText'] = '更新失败 · 数据过期';
  } else if (snapshot.providerStatus !== 'active') {
    texts['statusText'] = '服务不可用';
  }
  return texts;
}

function formatTime(ms: number): string {
  const date = new Date(ms);
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');
  return `更新于 ${hours}:${minutes}`;
}
