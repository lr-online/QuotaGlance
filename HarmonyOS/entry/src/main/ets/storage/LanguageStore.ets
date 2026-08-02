import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// Manual language override: 跟随系统 (default) / English / 简体中文.
// Same preferences file as ThemeStore under 'app_language_v1'.
export type LanguagePreference = 'system' | 'english' | 'chinese';

const STORE_NAME = 'quotaglance_store';
const LANGUAGE_KEY = 'app_language_v1';
const DEFAULT_PREF: LanguagePreference = 'system';

export class LanguageStore {
  private readonly store: preferences.Preferences;

  private constructor(store: preferences.Preferences) {
    this.store = store;
  }

  static async create(context: common.Context): Promise<LanguageStore> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    return new LanguageStore(store);
  }

  async load(): Promise<LanguagePreference> {
    const raw = await this.store.get(LANGUAGE_KEY, DEFAULT_PREF) as string;
    if (raw === 'english' || raw === 'chinese') {
      return raw;
    }
    return DEFAULT_PREF;
  }

  async save(preference: LanguagePreference): Promise<void> {
    await this.store.put(LANGUAGE_KEY, preference);
    await this.store.flush();
  }
}
