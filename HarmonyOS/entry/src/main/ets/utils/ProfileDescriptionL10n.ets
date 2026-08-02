import { common } from '@kit.AbilityKit';

function stringResource(context: common.Context, resource: Resource): string {
  return context.resourceManager.getStringSync(resource.id);
}

function regionLabel(context: common.Context, region: string): string {
  if (region === 'china') {
    return stringResource(context, $r('app.string.l10n_china'));
  }
  if (region === 'international') {
    return stringResource(context, $r('app.string.l10n_international'));
  }
  return stringResource(context, $r('app.string.l10n_global'));
}

function kindLabel(context: common.Context, kind: string): string {
  if (kind === 'management') {
    return stringResource(context, $r('app.string.l10n_management_key'));
  }
  if (kind === 'tokenPlan') {
    return stringResource(context, $r('app.string.l10n_token_plan'));
  }
  return stringResource(context, $r('app.string.l10n_standard_key'));
}

function baseLabel(context: common.Context, key: string): string | null {
  if (key === 'notDetected') {
    return stringResource(context, $r('app.string.l10n_not_detected'));
  }
  if (key === 'chinaCNY') {
    return stringResource(context, $r('app.string.l10n_china_cny'));
  }
  if (key === 'internationalUSD') {
    return stringResource(context, $r('app.string.l10n_international_usd'));
  }
  return null;
}

// Resolves only the token grammar emitted by makeDescriptor:
// bare L10n keys or credential kinds, key:kind for byRegion entries, and
// regionCredential:region:kind for the corresponding descriptor style.
export function resolveProfileDescription(context: common.Context, token: string): string {
  const direct = baseLabel(context, token);
  if (direct !== null) {
    return direct;
  }
  if (token === 'standard' || token === 'management' || token === 'tokenPlan') {
    return kindLabel(context, token);
  }

  const parts = token.split(':');
  if (parts.length === 2 && parts[0] === 'globalCredential') {
    const template = stringResource(context, $r('app.string.l10n_global_credential'));
    return template.replace('%s', kindLabel(context, parts[1]));
  }
  if (parts.length === 3 && parts[0] === 'regionCredential') {
    const template = stringResource(context, $r('app.string.l10n_region_credential'));
    return template
      .replace('%s', regionLabel(context, parts[1]))
      .replace('%s', kindLabel(context, parts[2]));
  }
  if (parts.length === 2) {
    const head = baseLabel(context, parts[0]);
    if (head !== null) {
      return `${head} · ${kindLabel(context, parts[1])}`;
    }
  }
  return token;
}
