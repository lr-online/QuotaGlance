// A UsageProvider executing a declarative provider spec
// (Contracts/Providers/<id>/spec.json) instead of hand-written per-provider
// code. Mirrors the Swift SpecDrivenProvider / ProviderSpec in
// Sources/QuotaGlanceCore/Providers/SpecDrivenProvider.swift and
// ProviderSpec.swift; see Contracts/README.md ("Provider spec schema
// (draft v1)") for the execution semantics and error-token contract.

import { i18n } from '@kit.LocalizationKit';
import { getJsonWithStatus } from '../network/HttpClient';
import { UsageSnapshot } from './UsageSnapshot';
import {
  EvalScope,
  EvalValue,
  asArray,
  asRecord,
  assembleSnapshot,
  engineError,
  errorTokenOf,
  evaluateBuilder,
  evaluateCondition,
  hasKey,
  runChecks,
  scalarKey,
  specError,
  stringList,
  resolvePath
} from './SpecEngine';
import {
  HttpFetcher,
  ProviderCredentialKind,
  ProviderDescriptor,
  ProviderDetection,
  ProviderID,
  ProviderProfile,
  ProviderRegion,
  RawJsonResponse,
  UsageProvider
} from './UsageProvider';

const SUPPORTED_SPEC_VERSION = 1;

const KNOWN_PROVIDER_IDS: string[] = [
  'apiInfo',
  'deepSeek',
  'kimi',
  'openRouter',
  'miniMax',
  'bioMapCoding'
];

const KNOWN_REGIONS: string[] = ['global', 'china', 'international'];
const KNOWN_KINDS: string[] = ['standard', 'management', 'tokenPlan'];
const KNOWN_TRANSFORMS: string[] = ['trim', 'uppercase'];
const KNOWN_VALUE_TYPES: string[] = ['decimal', 'string', 'int', 'bool', 'date'];
const KNOWN_STRATEGIES: string[] = ['miniMaxModelRemains'];
const KNOWN_L10N_KEYS: string[] = [
  'notDetected',
  'chinaCNY',
  'internationalUSD',
  'globalCredential',
  'regionCredential'
];
const KNOWN_ERROR_TOKENS: string[] = [
  'invalidCredential',
  'rateLimited',
  'httpStatus',
  'invalidResponse',
  'providerInactive',
  'unsupportedCredential',
  'regionDetectionFailed',
  'profileMismatch'
];
const KNOWN_SNAPSHOT_FIELDS: string[] = [
  'balances',
  'spendingLimit',
  'spend',
  'quotaWindows',
  'today',
  'total',
  'dailyUsage',
  'modelUsage',
  'providerStatus',
  'metricsUnavailableReason'
];

// MARK: - Spec validation

// Load-time validation rejects every spec the engine cannot execute, per
// Contracts/README.md. Failures throw specError/unsupportedSpecVersion/
// unknownStrategy Errors (outside the runtime error-token table).
export function validateSpec(spec: Record<string, Object>): void {
  const specVersion = spec['specVersion'];
  if (typeof specVersion !== 'number' || !Number.isInteger(specVersion) || specVersion < 1) {
    throw specError('specVersion must be a positive integer');
  }
  if (specVersion > SUPPORTED_SPEC_VERSION) {
    throw new Error(`unsupportedSpecVersion:${specVersion}`);
  }
  const id = spec['id'];
  if (typeof id !== 'string' || KNOWN_PROVIDER_IDS.indexOf(id) < 0) {
    throw specError(`unknown provider id '${id}'`);
  }
  const profiles = asRecord(spec['profiles']);
  const supported = asArray(profiles?.['supported']);
  if (supported === null) {
    throw specError('profiles.supported must be an array');
  }
  const supportedRegions = new Set<string>();
  for (const profileRaw of supported) {
    const profile = asRecord(profileRaw);
    if (profile === null) {
      throw specError('profiles.supported entries must be objects');
    }
    validateRegion(profile['region']);
    validateCredentialKind(profile['credentialKind']);
    supportedRegions.add(profile['region'] as string);
  }
  validateDescriptor(spec['descriptor']);
  const credential = asRecord(spec['credential']);
  for (const ruleRaw of asArray(credential?.['reject']) ?? []) {
    const rule = asRecord(ruleRaw);
    if (rule === null || typeof rule['prefix'] !== 'string' || typeof rule['error'] !== 'string') {
      throw specError('credential.reject entries need prefix and error');
    }
    validateErrorToken(rule['error']);
  }
  const regions = validateDetect(spec['detect'], supportedRegions);
  validateFetch(spec['fetch'], regions);
}

function validateDescriptor(descriptorRaw: Object | null | undefined): void {
  const descriptor = asRecord(descriptorRaw);
  if (descriptor === null) {
    throw specError('descriptor must be an object');
  }
  const threshold = asRecord(descriptor['supportsLowBalanceThreshold']);
  if (threshold === null) {
    throw specError('descriptor.supportsLowBalanceThreshold must be an object');
  }
  const hasAlways = hasKey(threshold, 'always');
  const hasRule = hasKey(threshold, 'undetected') || hasKey(threshold, 'credentialKinds');
  if (hasAlways === hasRule) {
    throw specError('descriptor.supportsLowBalanceThreshold needs exactly one form');
  }
  for (const kind of stringList(threshold['credentialKinds'])) {
    validateCredentialKind(kind);
  }
  const description = asRecord(descriptor['profileDescription']);
  if (description === null) {
    throw specError('descriptor.profileDescription must be an object');
  }
  const undetected = asRecord(description['undetected']);
  if (undetected === null) {
    throw specError('descriptor.profileDescription.undetected must be an object');
  }
  validateL10nKey(undetected['l10nKey']);
  const detected = asRecord(description['detected']);
  if (detected === null) {
    throw specError('descriptor.profileDescription.detected must be an object');
  }
  if (hasKey(detected, 'style')) {
    const style = detected['style'];
    if (style !== 'regionCredential' && style !== 'credentialKind') {
      throw specError(`unknown profileDescription style '${style}'`);
    }
  } else if (hasKey(detected, 'byRegion')) {
    const byRegion = asRecord(detected['byRegion']);
    if (byRegion === null) {
      throw specError('descriptor.profileDescription.detected.byRegion must be an object');
    }
    for (const region of Object.keys(byRegion)) {
      validateRegion(region);
      const entry = asRecord(byRegion[region]);
      if (entry === null) {
        throw specError('profileDescription byRegion entries must be objects');
      }
      validateL10nKey(entry['l10nKey']);
      for (const arg of stringList(entry['args'])) {
        if (arg !== 'credentialKind') {
          throw specError(`unknown profileDescription arg '${arg}'`);
        }
      }
    }
  } else {
    throw specError('descriptor.profileDescription.detected needs a style or byRegion table');
  }
}

// Validates the detect block; returns the union of `supportedRegions` and the
// detect-side regions — the set every byRegion table in the spec must cover.
function validateDetect(detectRaw: Object | null | undefined, supportedRegions: Set<string>): Set<string> {
  const detect = asRecord(detectRaw);
  if (detect === null) {
    throw specError('detect must be an object');
  }
  const regions = new Set<string>(supportedRegions);
  const strategy = detect['strategy'];
  if (strategy === 'fixedProfile') {
    const profile = asRecord(detect['profile']);
    if (profile === null) {
      throw specError('fixedProfile detect needs a profile');
    }
    validateRegion(profile['region']);
    const kind = profile['credentialKind'];
    if (kind !== 'detected') {
      validateCredentialKind(kind);
    }
    regions.add(profile['region'] as string);
  } else if (strategy === 'regionFallback') {
    const candidates = asArray(detect['candidates']);
    if (candidates === null || candidates.length === 0) {
      throw specError('regionFallback detect needs candidates');
    }
    for (const candidateRaw of candidates) {
      const candidate = asRecord(candidateRaw);
      if (candidate === null) {
        throw specError('regionFallback candidates must be objects');
      }
      validateRegion(candidate['region']);
      validateCredentialKind(candidate['credentialKind']);
      regions.add(candidate['region'] as string);
    }
    const fallbackOn = asArray(detect['fallbackOn']);
    if (fallbackOn === null || fallbackOn.length === 0) {
      throw specError('regionFallback detect needs fallbackOn');
    }
    for (const token of fallbackOn) {
      validateErrorToken(token);
    }
    if (typeof detect['exhaustedError'] !== 'string') {
      throw specError('regionFallback detect needs exhaustedError');
    }
    validateErrorToken(detect['exhaustedError']);
  } else {
    throw specError(`unknown detect strategy '${strategy}'`);
  }
  return regions;
}

function validateFetch(fetchRaw: Object | null | undefined, detectRegions: Set<string>): void {
  const fetch = asRecord(fetchRaw);
  if (fetch === null) {
    throw specError('fetch must be an object');
  }
  const steps = asArray(fetch['steps']);
  if (steps === null || steps.length === 0) {
    throw specError('fetch needs at least one step');
  }
  const stepNames = new Set<string>();
  for (let index = 0; index < steps.length; index++) {
    const step = asRecord(steps[index]);
    if (step === null) {
      throw specError('fetch steps must be objects');
    }
    const name = step['name'];
    if (typeof name !== 'string') {
      throw specError('fetch steps need a name');
    }
    if (stepNames.has(name)) {
      throw specError(`duplicate step name '${name}'`);
    }
    stepNames.add(name);
    if (index === 0 && hasKey(step, 'when')) {
      throw specError('the first step must not have a when clause');
    }
  }
  for (const stepRaw of steps) {
    validateStep(asRecord(stepRaw) as Record<string, Object>, stepNames, detectRegions);
  }
}

function validateStep(
  step: Record<string, Object>,
  stepNames: Set<string>,
  regions: Set<string>
): void {
  const context = `step '${step['name']}'`;
  if (hasKey(step, 'when')) {
    validateCondition(step['when'], stepNames, context);
  }
  const request = asRecord(step['request']);
  if (request === null) {
    throw specError(`${context}: request must be an object`);
  }
  const urlWrapper = asRecord(request['url']);
  if (urlWrapper !== null) {
    // url is a string or { "byRegion": { "<region>": "...", ... } }.
    const urlTable = asRecord(urlWrapper['byRegion']);
    if (urlTable === null) {
      throw specError(`${context}: request url must be a string or a byRegion table`);
    }
    for (const region of regions) {
      if (!hasKey(urlTable, region)) {
        throw specError(`${context}: request url byRegion table misses region '${region}'`);
      }
    }
  } else if (typeof request['url'] !== 'string') {
    throw specError(`${context}: request url must be a string or a byRegion table`);
  }
  const onStatus = asArray(step['onStatus']);
  if (onStatus === null || onStatus.length === 0) {
    throw specError(`${context}: onStatus must not be empty`);
  }
  for (const branchRaw of onStatus) {
    const branch = asRecord(branchRaw);
    if (branch === null) {
      throw specError(`${context}: onStatus branches must be objects`);
    }
    validateStatusMatch(branch['match'], context);
    const action = branch['action'];
    if (action === 'parse') {
      continue;
    }
    if (action === 'error') {
      if (typeof branch['error'] !== 'string') {
        throw specError(`${context}: error branch needs an error`);
      }
      validateErrorToken(branch['error']);
      continue;
    }
    if (action === 'gotoStep') {
      const target = branch['step'];
      if (typeof target !== 'string' || !stepNames.has(target)) {
        throw specError(`${context}: gotoStep targets an unknown step`);
      }
      continue;
    }
    throw specError(`${context}: unknown onStatus action '${action}'`);
  }
  const parse = asRecord(step['parse']);
  if (parse === null) {
    return;
  }
  for (const checkRaw of asArray(parse['checks']) ?? []) {
    validateCheck(checkRaw, stepNames, context);
  }
  const values = asRecord(parse['values']);
  if (values !== null) {
    for (const name of Object.keys(values)) {
      validateBuilder(values[name], regions, stepNames, `${context} value '${name}'`);
    }
  }
  const snapshot = asRecord(parse['snapshot']);
  if (snapshot !== null) {
    for (const field of Object.keys(snapshot)) {
      if (KNOWN_SNAPSHOT_FIELDS.indexOf(field) < 0) {
        throw specError(`${context}: unknown snapshot field '${field}'`);
      }
      const builder = asRecord(snapshot[field]);
      if (builder !== null && hasKey(builder, 'strategy') && field !== 'quotaWindows') {
        throw specError(`${context}: named strategies are only valid for quotaWindows`);
      }
      validateBuilder(snapshot[field], regions, stepNames, `${context} snapshot field '${field}'`);
    }
  }
  const detection = asRecord(parse['credentialKindDetection']);
  if (detection !== null) {
    if (typeof detection['path'] !== 'string') {
      throw specError(`${context}: credentialKindDetection needs a path`);
    }
    const map = asRecord(detection['map']);
    if (map === null) {
      throw specError(`${context}: credentialKindDetection needs a map`);
    }
    for (const key of Object.keys(map)) {
      validateCredentialKind(map[key]);
    }
  }
}

function validateStatusMatch(match: Object | null | undefined, context: string): void {
  if (match === '2xx' || match === 'default') {
    return;
  }
  const codes = asArray(match);
  if (codes !== null) {
    for (const code of codes) {
      if (typeof code !== 'number') {
        throw specError(`${context}: status codes must be numbers`);
      }
    }
    return;
  }
  throw specError(`${context}: unknown status match '${match}'`);
}

function validateCheck(checkRaw: Object, stepNames: Set<string>, context: string): void {
  const check = asRecord(checkRaw);
  if (check === null) {
    throw specError(`${context}: check entries must be objects`);
  }
  const eachItem = asRecord(check['eachItem']);
  if (eachItem !== null) {
    if (typeof eachItem['of'] !== 'string' || typeof eachItem['path'] !== 'string') {
      throw specError(`${context}: eachItem check needs of and path`);
    }
    for (const transform of stringList(eachItem['transforms'])) {
      validateTransform(transform, context);
    }
    if (hasKey(eachItem, 'type')) {
      validateValueType(eachItem['type'], context);
    }
  } else {
    if (!hasKey(check, 'path')) {
      throw specError(`${context}: check entry needs a path`);
    }
    for (const transform of stringList(check['transforms'])) {
      validateTransform(transform, context);
    }
    if (check['required'] !== true && !hasKey(check, 'when') && check['strict'] !== true) {
      throw specError(`${context}: check entry needs required, strict, or when`);
    }
    if (check['strict'] === true && !hasKey(check, 'type')) {
      throw specError(`${context}: strict check needs a type`);
    }
  }
  if (hasKey(check, 'when')) {
    validateCondition(check['when'], stepNames, context);
  }
  if (hasKey(check, 'type')) {
    validateValueType(check['type'], context);
  }
  if (hasKey(check, 'error')) {
    validateErrorToken(check['error']);
  }
}

function validateBuilder(
  builderRaw: Object,
  regions: Set<string>,
  stepNames: Set<string>,
  context: string
): void {
  const builder = asRecord(builderRaw);
  if (builder === null) {
    throw specError(`${context}: builder must be an object`);
  }
  const hasForm = hasKey(builder, 'object')
    || hasKey(builder, 'money')
    || hasKey(builder, 'template')
    || hasKey(builder, 'fromArray')
    || hasKey(builder, 'fixed')
    || hasKey(builder, 'strategy')
    || hasKey(builder, 'op')
    || hasKey(builder, 'value')
    || hasKey(builder, 'byRegion')
    || hasKey(builder, 'literal')
    || hasKey(builder, 'map')
    || hasKey(builder, 'path');
  if (!hasForm) {
    throw specError(`${context}: empty builder`);
  }
  for (const transform of stringList(builder['transforms'])) {
    validateTransform(transform, context);
  }
  if (hasKey(builder, 'path')
    && !hasKey(builder, 'map')
    && !hasKey(builder, 'op')
    && !hasKey(builder, 'strategy')) {
    if (!hasKey(builder, 'type')) {
      throw specError(`${context}: path builder needs a type`);
    }
    validateValueType(builder['type'], context);
  }
  if (hasKey(builder, 'when')) {
    validateCondition(builder['when'], stepNames, context);
  }
  const object = asRecord(builder['object']);
  if (object !== null) {
    for (const name of Object.keys(object)) {
      validateBuilder(object[name], regions, stepNames, `${context}.${name}`);
    }
  }
  const money = asRecord(builder['money']);
  if (money !== null) {
    validateBuilder(money['amount'], regions, stepNames, `${context}.amount`);
    validateBuilder(money['currency'], regions, stepNames, `${context}.currency`);
  }
  if (hasKey(builder, 'fromArray')) {
    const itemValues = asRecord(builder['itemValues']);
    if (itemValues !== null) {
      for (const name of Object.keys(itemValues)) {
        validateBuilder(itemValues[name], regions, stepNames, `${context}.itemValues.${name}`);
      }
    }
    const item = asRecord(builder['item']);
    if (item === null) {
      throw specError(`${context}: fromArray needs an item builder`);
    }
    for (const name of Object.keys(item)) {
      validateBuilder(item[name], regions, stepNames, `${context}.item.${name}`);
    }
    if (hasKey(builder, 'skipItemWhen')) {
      validateCondition(builder['skipItemWhen'], stepNames, context);
    }
  }
  const fixed = asArray(builder['fixed']);
  if (fixed !== null) {
    for (const entryRaw of fixed) {
      const entry = asRecord(entryRaw);
      if (entry === null) {
        throw specError(`${context}: fixed entries must be objects`);
      }
      for (const name of Object.keys(entry)) {
        if (name === 'when') {
          validateCondition(entry['when'], stepNames, context);
        } else {
          validateBuilder(entry[name], regions, stepNames, `${context}.${name}`);
        }
      }
    }
  }
  if (hasKey(builder, 'strategy')) {
    const strategy = builder['strategy'];
    if (KNOWN_STRATEGIES.indexOf(strategy as string) < 0) {
      throw new Error(`unknownStrategy:${strategy}`);
    }
    if (!hasKey(builder, 'path')) {
      throw specError(`${context}: strategy needs a path`);
    }
  }
  if (hasKey(builder, 'op')) {
    const op = builder['op'];
    if (op === 'subtract') {
      if (!hasKey(builder, 'a') || !hasKey(builder, 'b')) {
        throw specError(`${context}: subtract needs a and b`);
      }
      validateBuilder(builder['a'], regions, stepNames, `${context}.a`);
      validateBuilder(builder['b'], regions, stepNames, `${context}.b`);
    } else if (op === 'count') {
      if (!hasKey(builder, 'path')) {
        throw specError(`${context}: count needs a path`);
      }
    } else {
      throw specError(`${context}: unknown op '${op}'`);
    }
  }
  if (hasKey(builder, 'value') && typeof builder['value'] !== 'string') {
    validateBuilder(builder['value'], regions, stepNames, context);
  }
  const byRegion = asRecord(builder['byRegion']);
  if (byRegion !== null) {
    for (const region of regions) {
      if (!hasKey(byRegion, region)) {
        throw specError(`${context}: byRegion table misses region '${region}'`);
      }
    }
    for (const key of Object.keys(byRegion)) {
      validateScalar(byRegion[key], context);
    }
  }
  if (hasKey(builder, 'literal')) {
    validateScalar(builder['literal'], context);
  }
  if (hasKey(builder, 'map') && !hasKey(builder, 'path')) {
    throw specError(`${context}: map needs a path`);
  }
}

function validateCondition(conditionRaw: Object, stepNames: Set<string>, context: string): void {
  const condition = asRecord(conditionRaw);
  if (condition === null) {
    throw specError(`${context}: condition must be an object`);
  }
  const any = asArray(condition['any']);
  if (any !== null) {
    if (any.length === 0) {
      throw specError(`${context}: any needs at least one condition`);
    }
    for (const nested of any) {
      validateCondition(nested, stepNames, context);
    }
    return;
  }
  const all = asArray(condition['all']);
  if (all !== null) {
    if (all.length === 0) {
      throw specError(`${context}: all needs at least one condition`);
    }
    for (const nested of all) {
      validateCondition(nested, stepNames, context);
    }
    return;
  }
  if (hasKey(condition, 'step')) {
    const step = condition['step'];
    if (typeof step !== 'string' || !stepNames.has(step)) {
      throw specError(`${context}: condition references unknown step '${step}'`);
    }
  }
  let operators = 0;
  if (hasKey(condition, 'exists')) {
    operators += 1;
  }
  if (hasKey(condition, 'equals')) {
    operators += 1;
  }
  if (hasKey(condition, 'notEquals')) {
    operators += 1;
  }
  if (hasKey(condition, 'lt')) {
    operators += 1;
  }
  if (hasKey(condition, 'gt')) {
    operators += 1;
  }
  if (operators !== 1) {
    throw specError(`${context}: condition needs exactly one operator`);
  }
  if (hasKey(condition, 'lt') && typeof condition['lt'] !== 'number') {
    throw specError(`${context}: lt expects a JSON number`);
  }
  if (hasKey(condition, 'gt') && typeof condition['gt'] !== 'number') {
    throw specError(`${context}: gt expects a JSON number`);
  }
}

function validateScalar(value: Object, context: string): void {
  if (value === null || typeof value === 'boolean' || typeof value === 'number'
    || typeof value === 'string') {
    return;
  }
  throw specError(`${context}: expected a JSON scalar`);
}

function validateRegion(region: Object | null | undefined): void {
  if (typeof region !== 'string' || KNOWN_REGIONS.indexOf(region) < 0) {
    throw specError(`unknown region '${region}'`);
  }
}

function validateCredentialKind(kind: Object | null | undefined): void {
  if (typeof kind !== 'string' || KNOWN_KINDS.indexOf(kind) < 0) {
    throw specError(`unknown credential kind '${kind}'`);
  }
}

function validateErrorToken(token: Object | null | undefined): void {
  if (typeof token !== 'string' || KNOWN_ERROR_TOKENS.indexOf(token) < 0) {
    throw specError(`unknown error token '${token}'`);
  }
}

function validateL10nKey(key: Object | null | undefined): void {
  if (typeof key !== 'string' || KNOWN_L10N_KEYS.indexOf(key) < 0) {
    throw specError(`unknown L10n key '${key}'`);
  }
}

function validateTransform(transform: string, context: string): void {
  if (KNOWN_TRANSFORMS.indexOf(transform) < 0) {
    throw specError(`${context}: unknown transform '${transform}'`);
  }
}

function validateValueType(type: Object | null | undefined, context: string): void {
  if (typeof type !== 'string' || KNOWN_VALUE_TYPES.indexOf(type) < 0) {
    throw specError(`${context}: unknown value type '${type}'`);
  }
}

// MARK: - Descriptor

// Builds the ProviderDescriptor from spec.descriptor. profileDescription
// returns the stable L10n key tokens (with region/credential-kind args
// appended, colon-separated). ProfileDescriptionL10n resolves them at the UI
// seam, so the provider keeps returning tokens and remains independent of
// ArkUI resources. See Contracts/README.md ("Why L10n keys, not copy").
function makeDescriptor(id: ProviderID, spec: Record<string, Object>): ProviderDescriptor {
  const descriptorSpec = asRecord(spec['descriptor']) as Record<string, Object>;
  const threshold = asRecord(descriptorSpec['supportsLowBalanceThreshold']) as Record<string, Object>;
  let supportsThreshold: (profile?: ProviderProfile) => boolean;
  if (hasKey(threshold, 'always')) {
    const always = threshold['always'] === true;
    supportsThreshold = (_profile?: ProviderProfile): boolean => always;
  } else {
    const undetected = threshold['undetected'] === true;
    const kinds = new Set<string>(stringList(threshold['credentialKinds']));
    supportsThreshold = (profile?: ProviderProfile): boolean => {
      if (profile === undefined || profile.credentialKind === undefined) {
        return undetected;
      }
      return kinds.has(profile.credentialKind);
    };
  }

  const description = asRecord(descriptorSpec['profileDescription']) as Record<string, Object>;
  const undetectedKey = (asRecord(description['undetected']) as Record<string, Object>)['l10nKey'] as string;
  const detected = asRecord(description['detected']) as Record<string, Object>;
  const profileDescription = (profile?: ProviderProfile): string => {
    if (profile === undefined) {
      return undetectedKey;
    }
    const region = profile.region ?? 'global';
    const kind = profile.credentialKind ?? 'standard';
    if (hasKey(detected, 'style')) {
      const style = detected['style'] as string;
      if (style === 'regionCredential') {
        return `regionCredential:${region}:${kind}`;
      }
      if (style === 'credentialKind') {
        return kind;
      }
    }
    const byRegion = asRecord(detected['byRegion']);
    if (byRegion !== null && hasKey(byRegion, region)) {
      const entry = asRecord(byRegion[region]) as Record<string, Object>;
      const key = entry['l10nKey'] as string;
      if (stringList(entry['args']).indexOf('credentialKind') >= 0) {
        return `${key}:${kind}`;
      }
      return key;
    }
    return undetectedKey;
  };

  const descriptor: ProviderDescriptor = {
    id: id,
    displayName: spec['displayName'] as string,
    supportsLowBalanceThreshold: supportsThreshold,
    profileDescription: profileDescription
  };
  return descriptor;
}

// MARK: - SpecDrivenProvider

export interface SpecDrivenProviderOptions {
  now?: () => number;
  fetcher?: HttpFetcher;
  preferredRegion?: ProviderRegion;
}

interface StepResult {
  body: Object;
  fields: Record<string, EvalValue>;
  detectedKind?: ProviderCredentialKind;
  // Set by a gotoStep branch: the pipeline stops and this step's result
  // becomes the fetch result.
  replacesPipeline: boolean;
}

interface PipelineResult {
  snapshot: UsageSnapshot;
  detectedKind?: ProviderCredentialKind;
}

export class SpecDrivenProvider implements UsageProvider {
  readonly id: ProviderID;
  readonly descriptor: ProviderDescriptor;

  private readonly spec: Record<string, Object>;
  private readonly now: () => number;
  private readonly fetcher: HttpFetcher;
  private readonly preferredRegion: ProviderRegion | undefined;

  constructor(specJson: string, options?: SpecDrivenProviderOptions) {
    let parsed: Object;
    try {
      parsed = JSON.parse(specJson) as Object;
    } catch (error) {
      throw specError(`spec decode failed: ${(error as Error).message}`);
    }
    const spec = asRecord(parsed);
    if (spec === null) {
      throw specError('spec is not a JSON object');
    }
    validateSpec(spec);
    this.spec = spec;
    this.id = spec['id'] as ProviderID;
    this.now = options?.now ?? ((): number => Date.now());
    this.fetcher = options?.fetcher
      ?? ((url: string, headers: Record<string, string>): Promise<RawJsonResponse> =>
        getJsonWithStatus(url, headers));
    this.preferredRegion = options?.preferredRegion;
    this.descriptor = makeDescriptor(this.id, spec);
  }

  async detect(apiKey: string): Promise<ProviderDetection> {
    const key = this.preprocess(apiKey);
    const detect = asRecord(this.spec['detect']) as Record<string, Object>;
    const strategy = detect['strategy'] as string;
    if (strategy === 'fixedProfile') {
      const profileSpec = asRecord(detect['profile']) as Record<string, Object>;
      const region = profileSpec['region'] as ProviderRegion;
      const kindRaw = profileSpec['credentialKind'] as string;
      const concreteKind: ProviderCredentialKind | undefined =
        kindRaw === 'detected' ? undefined : kindRaw as ProviderCredentialKind;
      const pipelineProfile: ProviderProfile = {
        region: region,
        credentialKind: concreteKind ?? 'standard'
      };
      const result = await this.runPipeline(key, pipelineProfile, false);
      let kind: ProviderCredentialKind;
      if (concreteKind !== undefined) {
        kind = concreteKind;
      } else if (result.detectedKind !== undefined) {
        kind = result.detectedKind;
      } else {
        throw engineError('invalidResponse');
      }
      const detection: ProviderDetection = {
        profile: { region: region, credentialKind: kind },
        snapshot: result.snapshot
      };
      return detection;
    }
    if (strategy === 'regionFallback') {
      const fallbackOn = new Set<string>(stringList(detect['fallbackOn']));
      for (const candidate of this.orderedCandidates()) {
        try {
          const result = await this.runPipeline(key, candidate, false);
          const detection: ProviderDetection = { profile: candidate, snapshot: result.snapshot };
          return detection;
        } catch (error) {
          // Only failures whose token is in fallbackOn advance to the next
          // candidate; anything else propagates immediately.
          if (!fallbackOn.has(errorTokenOf((error as Error).message))) {
            throw error as Error;
          }
        }
      }
      throw engineError(detect['exhaustedError'] as string);
    }
    throw specError(`unknown detect strategy '${strategy}'`);
  }

  async fetch(apiKey: string, profile: ProviderProfile): Promise<UsageSnapshot> {
    const key = this.preprocess(apiKey);
    const supported = this.supportedProfiles().some((entry: ProviderProfile): boolean =>
      entry.region === profile.region && entry.credentialKind === profile.credentialKind);
    if (!supported) {
      throw engineError('profileMismatch');
    }
    const result = await this.runPipeline(key, profile, true);
    return result.snapshot;
  }

  private supportedProfiles(): ProviderProfile[] {
    const profiles = asRecord(this.spec['profiles']) as Record<string, Object>;
    const supported = asArray(profiles['supported']) as Object[];
    const result: ProviderProfile[] = [];
    for (const entryRaw of supported) {
      const entry = asRecord(entryRaw) as Record<string, Object>;
      const profile: ProviderProfile = {
        region: entry['region'] as ProviderRegion,
        credentialKind: entry['credentialKind'] as ProviderCredentialKind
      };
      result.push(profile);
    }
    return result;
  }

  // Engine steps 3-6 of the fetch semantics: ordered steps with first-match
  // status branches, per-step checks/values/snapshot merge, and
  // credential-kind enforcement immediately after a step parses.
  private async runPipeline(
    apiKey: string,
    profile: ProviderProfile,
    isFetch: boolean
  ): Promise<PipelineResult> {
    const fetchSpec = asRecord(this.spec['fetch']) as Record<string, Object>;
    const steps = asArray(fetchSpec['steps']) as Object[];
    const stepBodies: Map<string, Object> = new Map();
    const merged: Record<string, EvalValue> = {};
    let detectedKind: ProviderCredentialKind | undefined;

    for (const stepRaw of steps) {
      const step = asRecord(stepRaw) as Record<string, Object>;
      if (step['onDemand'] === true) {
        continue;
      }
      if (hasKey(step, 'when') && !evaluateCondition(step['when'], null, stepBodies)) {
        continue;
      }
      const result = await this.executeStep(step, apiKey, profile, stepBodies);
      stepBodies.set(step['name'] as string, result.body);
      for (const field of Object.keys(result.fields)) {
        merged[field] = result.fields[field];
      }
      if (result.detectedKind !== undefined) {
        if (!isFetch) {
          detectedKind = result.detectedKind;
        } else if (result.detectedKind !== profile.credentialKind) {
          throw engineError('profileMismatch');
        }
      }
      if (result.replacesPipeline) {
        break;
      }
    }
    const pipelineResult: PipelineResult = {
      snapshot: assembleSnapshot(merged, this.id, this.now())
    };
    if (detectedKind !== undefined) {
      pipelineResult.detectedKind = detectedKind;
    }
    return pipelineResult;
  }

  // Executes one step: request, first-match status branch, then parse. A
  // gotoStep branch abandons the step and recursively executes the target,
  // whose result becomes the fetch result (replacesPipeline).
  private async executeStep(
    step: Record<string, Object>,
    apiKey: string,
    profile: ProviderProfile,
    steps: Map<string, Object>
  ): Promise<StepResult> {
    const url = this.requestUrl(step, profile);
    const headers = this.requestHeaders(step, apiKey);
    const response = await this.fetcher(url, headers);

    const onStatus = asArray(step['onStatus']) as Object[];
    let branch: Record<string, Object> | null = null;
    for (const branchRaw of onStatus) {
      const candidate = asRecord(branchRaw) as Record<string, Object>;
      if (statusMatches(candidate['match'], response.code)) {
        branch = candidate;
        break;
      }
    }
    if (branch === null) {
      throw engineError('httpStatus', response.code);
    }
    const action = branch['action'] as string;
    if (action === 'error') {
      throw engineError(branch['error'] as string, response.code);
    }
    if (action === 'gotoStep') {
      const target = this.stepNamed(branch['step'] as string);
      const result = await this.executeStep(target, apiKey, profile, steps);
      result.replacesPipeline = true;
      return result;
    }

    let body: Object;
    try {
      body = JSON.parse(response.body) as Object;
    } catch (error) {
      throw engineError('invalidResponse');
    }
    const parse = asRecord(step['parse']);
    runChecks(asArray(parse?.['checks']) ?? [], body);
    const values = asRecord(parse?.['values']);
    const scope = new EvalScope(body, profile.region ?? 'global', steps, values ?? {}, null);
    const fields: Record<string, EvalValue> = {};
    const snapshotBuilders = asRecord(parse?.['snapshot']);
    if (snapshotBuilders !== null) {
      for (const field of Object.keys(snapshotBuilders)) {
        const value = evaluateBuilder(snapshotBuilders[field], scope);
        if (value !== null) {
          fields[field] = value;
        }
      }
    }
    const result: StepResult = { body: body, fields: fields, replacesPipeline: false };
    const detection = asRecord(parse?.['credentialKindDetection']);
    if (detection !== null) {
      const key = scalarKey(resolvePath(body, detection['path'] as string));
      const map = asRecord(detection['map']) as Record<string, Object>;
      if (key === null || !hasKey(map, key)) {
        throw engineError('invalidResponse');
      }
      result.detectedKind = map[key] as ProviderCredentialKind;
    }
    return result;
  }

  private stepNamed(name: string): Record<string, Object> {
    const fetchSpec = asRecord(this.spec['fetch']) as Record<string, Object>;
    const steps = asArray(fetchSpec['steps']) as Object[];
    for (const stepRaw of steps) {
      const step = asRecord(stepRaw) as Record<string, Object>;
      if (step['name'] === name) {
        return step;
      }
    }
    throw specError('unknown gotoStep target');
  }

  private requestUrl(step: Record<string, Object>, profile: ProviderProfile): string {
    const request = asRecord(step['request']) as Record<string, Object>;
    const url = request['url'];
    if (typeof url === 'string') {
      return url;
    }
    const table = asRecord(asRecord(url)?.['byRegion']);
    const region = profile.region ?? 'global';
    if (table === null || !hasKey(table, region)) {
      throw specError(`request url byRegion table misses region '${region}'`);
    }
    return table[region] as string;
  }

  // The engine sends exactly the spec's headers, in order, with ${apiKey}
  // interpolated — no implicit platform headers.
  private requestHeaders(step: Record<string, Object>, apiKey: string): Record<string, string> {
    const request = asRecord(step['request']) as Record<string, Object>;
    const headers: Record<string, string> = {};
    for (const headerRaw of asArray(request['headers']) ?? []) {
      const header = asRecord(headerRaw) as Record<string, Object>;
      const name = header['name'] as string;
      const value = (header['value'] as string).split('${apiKey}').join(apiKey);
      headers[name] = value;
    }
    return headers;
  }

  // credential.trimWhitespace, then the reject rules in order; applied at the
  // top of both detect and fetch, before anything else.
  private preprocess(apiKey: string): string {
    const credential = asRecord(this.spec['credential']);
    let key = apiKey;
    if (credential !== null && credential['trimWhitespace'] === true) {
      key = key.trim();
    }
    for (const ruleRaw of asArray(credential?.['reject']) ?? []) {
      const rule = asRecord(ruleRaw) as Record<string, Object>;
      const prefix = rule['prefix'] as string;
      const matches = rule['caseInsensitive'] === true
        ? key.toLowerCase().startsWith(prefix.toLowerCase())
        : key.startsWith(prefix);
      if (matches) {
        throw engineError(rule['error'] as string);
      }
    }
    return key;
  }

  // regionFallback candidates with the runtime-preferred region moved to the
  // front. The injected preference is clamped to the candidate set; an
  // unsupported (or absent) injection falls back to the locale default
  // (CN -> china, else international), mirroring the deleted hand-written
  // Kimi/MiniMax providers.
  private orderedCandidates(): ProviderProfile[] {
    const detect = asRecord(this.spec['detect']) as Record<string, Object>;
    const candidates: ProviderProfile[] = [];
    for (const candidateRaw of asArray(detect['candidates']) ?? []) {
      const candidate = asRecord(candidateRaw) as Record<string, Object>;
      const profile: ProviderProfile = {
        region: candidate['region'] as ProviderRegion,
        credentialKind: candidate['credentialKind'] as ProviderCredentialKind
      };
      candidates.push(profile);
    }
    const candidateRegions = new Set<string>();
    for (const candidate of candidates) {
      if (candidate.region !== undefined) {
        candidateRegions.add(candidate.region);
      }
    }
    let preferred: ProviderRegion;
    if (this.preferredRegion !== undefined && candidateRegions.has(this.preferredRegion)) {
      preferred = this.preferredRegion;
    } else {
      preferred = localePreferredRegion();
    }
    const ordered = candidates.slice();
    const index = ordered.findIndex((candidate: ProviderProfile): boolean =>
      candidate.region === preferred);
    if (index > 0) {
      const candidate = ordered.splice(index, 1)[0];
      ordered.unshift(candidate);
    }
    return ordered;
  }
}

function statusMatches(match: Object, statusCode: number): boolean {
  if (match === '2xx') {
    return statusCode >= 200 && statusCode < 300;
  }
  if (match === 'default') {
    return true;
  }
  const codes = asArray(match);
  if (codes !== null) {
    return codes.indexOf(statusCode) >= 0;
  }
  return false;
}

function localePreferredRegion(): ProviderRegion {
  try {
    return i18n.System.getSystemRegion().toUpperCase() === 'CN' ? 'china' : 'international';
  } catch (error) {
    return 'international';
  }
}
