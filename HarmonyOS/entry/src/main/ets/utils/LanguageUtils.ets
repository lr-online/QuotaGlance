import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LanguagePreference } from '../storage/LanguageStore';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlanceLanguage';

// Maps persisted preference onto app preferred language (API 11+).
// english → en-US, chinese → zh-Hans.
// system → clear override when possible; otherwise set to the device
// system language so UI still tracks the device until next relaunch.
export function applyLanguage(preference: LanguagePreference): void {
  try {
    if (preference === 'english') {
      i18n.System.setAppPreferredLanguage('en-US');
      return;
    }
    if (preference === 'chinese') {
      i18n.System.setAppPreferredLanguage('zh-Hans');
      return;
    }
    // Follow system: prefer empty / clear if SDK accepts it; fallback to
    // current system language tag so resources stop forcing en/zh override.
    const systemTag = i18n.System.getSystemLanguage();
    i18n.System.setAppPreferredLanguage(systemTag);
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'setAppPreferredLanguage failed: %{public}s', (error as Error).message);
  }
}
