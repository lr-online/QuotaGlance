import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeMode } from '../storage/ThemeStore';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlanceTheme';

// Maps the persisted theme mode onto the app-level color-mode override
// (ApplicationContext.setColorMode, API 18+): NOT_SET hands the decision
// back to the system, so 跟随系统 keeps following the device setting.
export function applyThemeMode(context: common.Context, mode: ThemeMode): void {
  const colorMode = mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    : (mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  try {
    context.getApplicationContext().setColorMode(colorMode);
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}s', (error as Error).message);
  }
}

// Re-resolves appBackground (base = light, dark/ = dark) onto the main
// window background. setColorMode is expected to raise a configuration
// update (UIAbility.onConfigurationUpdate re-applies this too), but callers
// invoke this right after switching as well — it is idempotent, so the
// background is correct whether or not the callback fires.
export function reapplyWindowBackground(context: common.UIAbilityContext): void {
  try {
    const color = context.resourceManager.getColorSync($r('app.color.appBackground').id);
    const rgb = `#${(color & 0xFFFFFF).toString(16).padStart(6, '0')}`;
    context.windowStage.getMainWindowSync().setWindowBackgroundColor(rgb);
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor failed: %{public}s', (error as Error).message);
  }
}
