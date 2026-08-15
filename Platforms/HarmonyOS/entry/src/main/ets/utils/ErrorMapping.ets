import { common } from '@kit.AbilityKit';

// Maps provider-layer error tokens (see providers/UsageProvider.ets) to
// user-facing Chinese text from string resources. Shared by the dashboard
// (refresh toasts) and the account editor (inline validation errors).
export function friendlyErrorText(context: common.Context, message: string): string {
  const rm = context.resourceManager;
  if (message === 'invalidCredential' || message === 'missingCredential') {
    return rm.getStringSync($r('app.string.err_invalid_credential').id);
  }
  if (message === 'rateLimited') {
    return rm.getStringSync($r('app.string.err_rate_limited').id);
  }
  if (message === 'regionDetectionFailed') {
    return rm.getStringSync($r('app.string.err_region_detection').id);
  }
  if (message === 'unsupportedCredential') {
    return rm.getStringSync($r('app.string.err_unsupported_credential').id);
  }
  if (message === 'providerInactive') {
    return rm.getStringSync($r('app.string.err_provider_inactive').id);
  }
  if (message === 'accountLimitReached') {
    return rm.getStringSync($r('app.string.err_account_limit').id);
  }
  if (message.startsWith('network:')) {
    return rm.getStringSync($r('app.string.err_network').id);
  }
  if (message.startsWith('httpStatus:')) {
    return rm.getStringSync($r('app.string.err_http_status').id);
  }
  // invalidResponse, profileMismatch, providerUnavailable, anything else.
  return rm.getStringSync($r('app.string.err_generic').id);
}
