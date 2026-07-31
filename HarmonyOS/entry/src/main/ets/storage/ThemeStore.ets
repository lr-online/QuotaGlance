import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// Manual theme override: 跟随系统 (default) / 浅色 / 深色. Lives in the
// shared 'quotaglance_store' preferences file under 'app_theme_mode_v1'.
export type ThemeMode = 'system' | 'light' | 'dark';

const STORE_NAME = 'quotaglance_store';
const THEME_KEY = 'app_theme_mode_v1';
const DEFAULT_MODE: ThemeMode = 'system';

export class ThemeStore {
  private readonly store: preferences.Preferences;

  private constructor(store: preferences.Preferences) {
    this.store = store;
  }

  static async create(context: common.Context): Promise<ThemeStore> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    return new ThemeStore(store);
  }

  async load(): Promise<ThemeMode> {
    const raw = await this.store.get(THEME_KEY, DEFAULT_MODE) as string;
    // Self-healing: anything unrecognized falls back to following the system.
    if (raw === 'light' || raw === 'dark') {
      return raw;
    }
    return DEFAULT_MODE;
  }

  async save(mode: ThemeMode): Promise<void> {
    await this.store.put(THEME_KEY, mode);
    await this.store.flush();
  }
}
