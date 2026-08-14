import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { decodeAlertEpisodes, encodeAlertEpisodes } from './StateCodecs';

// Durable per-account low-balance episode flags across launches, in the
// shared 'quotaglance_store' preferences file under 'alert_episodes_v1'.
// Swift persists alertEpisodeActive on the account record; ArkTS keeps the
// flags in a side store so AccountStore's schema stays untouched (the
// alertEpisodeActive field is merged onto accounts at evaluation time in
// NotificationService.evaluateAndNotifyAlerts).
const STORE_NAME = 'quotaglance_store';
const EPISODES_KEY = 'alert_episodes_v1';

export class AlertStateStore {
  private readonly store: preferences.Preferences;

  private constructor(store: preferences.Preferences) {
    this.store = store;
  }

  static async create(context: common.Context): Promise<AlertStateStore> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    return new AlertStateStore(store);
  }

  // accountId -> episodeActive. Missing id = false (never alerted / recovered).
  async load(): Promise<Map<string, boolean>> {
    const raw = await this.store.get(EPISODES_KEY, '') as string;
    return decodeAlertEpisodes(raw);
  }

  async save(flags: Map<string, boolean>): Promise<void> {
    await this.store.put(EPISODES_KEY, encodeAlertEpisodes(flags));
    await this.store.flush();
  }

  async isEpisodeActive(accountId: string): Promise<boolean> {
    return (await this.load()).get(accountId) ?? false;
  }

  // Account deletion hygiene: drop the orphan flag (AccountService.deleteAccount).
  async clear(accountId: string): Promise<void> {
    const flags = await this.load();
    if (flags.delete(accountId)) {
      await this.save(flags);
    }
  }
}
