// Spec engine evaluation core. Mirrors the Swift SpecEngine /
// SpecSnapshotAssembly / SpecDecimal in
// Sources/QuotaGlanceCore/Providers/SpecDrivenProvider.swift and
// ProviderSpec.swift, implementing the closed semantics of
// Contracts/README.md ("Provider spec schema (draft v1)"): dot paths, value
// expressions, conditions, ordered checks, snapshot builders and decimal
// canonicalization. The spec itself is interpreted as parsed JSON (ArkTS has
// no Codable); structural validation lives in SpecDrivenProvider.ets.

import {
  DailyUsage,
  ModelUsage,
  MonetaryBalance,
  MonetaryValue,
  Money,
  QuotaWindow,
  SpendingLimit,
  SpendSummary,
  UsageCounters,
  UsageSnapshot
} from './UsageSnapshot';
import { miniMaxModelRemainsWindows } from './MiniMaxModelRemainsStrategy';

// MARK: - JSON helpers

export function asRecord(value: Object | null | undefined): Record<string, Object> | null {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, Object>;
}

export function asArray(value: Object | null | undefined): Object[] | null {
  if (value === null || value === undefined || !Array.isArray(value)) {
    return null;
  }
  return value as Object[];
}

// Key-presence test for JSON-derived records. ArkTS forbids
// Function.call/apply, and JSON never produces undefined values, so an
// undefined comparison is an exact presence check.
export function hasKey(record: Record<string, Object>, key: string): boolean {
  return record[key] !== undefined;
}

export function stringList(value: Object | null | undefined): string[] {
  const array = asArray(value);
  if (array === null) {
    return [];
  }
  const result: string[] = [];
  for (const item of array) {
    if (typeof item === 'string') {
      result.push(item);
    }
  }
  return result;
}

// Resolves a dot-separated path. A missing key, an explicit null, or a
// non-object intermediate all resolve to absent (null), per the schema.
export function resolvePath(root: Object | null, path: string): Object | null {
  let current: Object | null = root;
  const keys = path.split('.');
  for (const key of keys) {
    const record = asRecord(current);
    if (record === null || !hasKey(record, key)) {
      return null;
    }
    const next: Object = record[key];
    if (next === null) {
      return null;
    }
    current = next;
  }
  return current;
}

// MARK: - SpecDecimal

// Decimal value carrying the canonical string form mandated by
// Contracts/README.md ("Decimal and Money canonicalization"): string sources
// are preserved verbatim after trimming, number sources use the shortest
// round-trip rendering, and subtract renders the exact result canonically.
// ArkTS compares Money.amount as exact strings, so `canonical` is the form
// the fixtures pin.
export interface SpecDecimal {
  value: number;
  canonical: string;
}

const DECIMAL_PATTERN: RegExp = /^[+-]?(\d+(\.\d+)?|\.\d+)([eE][+-]?\d+)?$/;

export function decimalFromString(raw: string): SpecDecimal | null {
  const trimmed = raw.trim();
  if (trimmed.length === 0 || !DECIMAL_PATTERN.test(trimmed)) {
    return null;
  }
  const value = Number(trimmed);
  if (!Number.isFinite(value)) {
    return null;
  }
  const decimal: SpecDecimal = { value: value, canonical: trimmed };
  return decimal;
}

// JS String() is already the shortest round-trip rendering for finite
// doubles (6655.90 -> "6655.9", 10 -> "10"), matching Swift's
// NSDecimalNumber(decimal:).stringValue for the magnitudes providers send.
export function decimalFromNumber(raw: number): SpecDecimal | null {
  if (!Number.isFinite(raw)) {
    return null;
  }
  const decimal: SpecDecimal = { value: raw, canonical: String(raw) };
  return decimal;
}

export function decimalSubtract(a: SpecDecimal | null, b: SpecDecimal | null): SpecDecimal | null {
  if (a === null || b === null) {
    return null;
  }
  const canonical = subtractDecimalStrings(a.canonical, b.canonical);
  const decimal: SpecDecimal = { value: Number(canonical), canonical: canonical };
  return decimal;
}

// Exact decimal subtraction on the canonical strings: doubles would render
// float noise (e.g. 0.3 - 0.1), which the exact-string fixture comparison
// cannot tolerate. Falls back to double arithmetic only for values that have
// no plain decimal form (extreme exponents), which fixtures never contain.
interface PlainDecimal {
  negative: boolean;
  intPart: string;
  fracPart: string;
}

function toPlainDecimal(raw: string): PlainDecimal | null {
  let text = raw;
  if (/[eE]/.test(text)) {
    const rendered = String(Number(text));
    if (/[eE]/.test(rendered)) {
      return null;
    }
    text = rendered;
  }
  const match = /^([+-]?)(\d*)(?:\.(\d*))?$/.exec(text);
  if (match === null) {
    return null;
  }
  let intPart = match[2];
  const fracPart = match[3] ?? '';
  if (intPart.length === 0 && fracPart.length === 0) {
    return null;
  }
  if (intPart.length === 0) {
    intPart = '0';
  }
  const plain: PlainDecimal = { negative: match[1] === '-', intPart: intPart, fracPart: fracPart };
  return plain;
}

function alignMagnitudes(a: PlainDecimal, b: PlainDecimal): string[] {
  const fracLength = Math.max(a.fracPart.length, b.fracPart.length);
  const aDigits = (a.intPart + a.fracPart.padEnd(fracLength, '0')).replace(/^0+/, '');
  const bDigits = (b.intPart + b.fracPart.padEnd(fracLength, '0')).replace(/^0+/, '');
  return [aDigits.length === 0 ? '0' : aDigits, bDigits.length === 0 ? '0' : bDigits, String(fracLength)];
}

function compareMagnitudes(aDigits: string, bDigits: string): number {
  if (aDigits.length !== bDigits.length) {
    return aDigits.length < bDigits.length ? -1 : 1;
  }
  return aDigits === bDigits ? 0 : (aDigits < bDigits ? -1 : 1);
}

function addDigitStrings(a: string, b: string): string {
  let carry = 0;
  let i = a.length - 1;
  let j = b.length - 1;
  let result = '';
  while (i >= 0 || j >= 0 || carry > 0) {
    const da = i >= 0 ? a.charCodeAt(i) - 48 : 0;
    const db = j >= 0 ? b.charCodeAt(j) - 48 : 0;
    const sum = da + db + carry;
    result = String(sum % 10) + result;
    carry = Math.floor(sum / 10);
    i--;
    j--;
  }
  return result;
}

// Requires aDigits >= bDigits.
function subtractDigitStrings(a: string, b: string): string {
  let borrow = 0;
  let i = a.length - 1;
  let j = b.length - 1;
  let result = '';
  while (i >= 0) {
    let da = a.charCodeAt(i) - 48 - borrow;
    const db = j >= 0 ? b.charCodeAt(j) - 48 : 0;
    if (da < db) {
      da += 10;
      borrow = 1;
    } else {
      borrow = 0;
    }
    result = String(da - db) + result;
    i--;
    j--;
  }
  return result.replace(/^0+(?=\d)/, '');
}

function subtractDecimalStrings(aRaw: string, bRaw: string): string {
  const a = toPlainDecimal(aRaw);
  const b = toPlainDecimal(bRaw);
  if (a === null || b === null) {
    return String(Number(aRaw) - Number(bRaw));
  }
  const aligned = alignMagnitudes(a, b);
  const aDigits = aligned[0];
  const bDigits = aligned[1];
  const fracLength = Number(aligned[2]);
  // a - b, computed as signed-magnitude addition of a and -b.
  const bNegative = !b.negative;
  let negative: boolean;
  let digits: string;
  if (a.negative === bNegative) {
    digits = addDigitStrings(aDigits, bDigits);
    negative = a.negative;
  } else {
    const order = compareMagnitudes(aDigits, bDigits);
    if (order === 0) {
      return '0';
    }
    if (order > 0) {
      digits = subtractDigitStrings(aDigits, bDigits);
      negative = a.negative;
    } else {
      digits = subtractDigitStrings(bDigits, aDigits);
      negative = bNegative;
    }
  }
  digits = digits.padStart(fracLength + 1, '0');
  let intPart = fracLength === 0 ? digits : digits.substring(0, digits.length - fracLength);
  let fracPart = fracLength === 0 ? '' : digits.substring(digits.length - fracLength);
  intPart = intPart.replace(/^0+(?=\d)/, '');
  fracPart = fracPart.replace(/0+$/, '');
  if (/^0*$/.test(intPart) && fracPart.length === 0) {
    return '0';
  }
  const sign = negative ? '-' : '';
  return fracPart.length === 0 ? `${sign}${intPart}` : `${sign}${intPart}.${fracPart}`;
}

// MARK: - Typed extraction

export function jsonDecimal(value: Object | null): SpecDecimal | null {
  if (typeof value === 'number') {
    return decimalFromNumber(value);
  }
  if (typeof value === 'string') {
    return decimalFromString(value);
  }
  return null;
}

export function jsonInt(value: Object | null): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return null;
  }
  const rounded = Math.round(value);
  if (rounded !== value) {
    return null;
  }
  if (Math.abs(value) > 9223372036854775807) {
    return null;
  }
  return rounded;
}

export function jsonString(value: Object | null): string | null {
  return typeof value === 'string' ? value : null;
}

export function jsonBool(value: Object | null): boolean | null {
  return typeof value === 'boolean' ? value : null;
}

export function jsonDateMs(value: Object | null): number | null {
  if (typeof value !== 'string' || value.length === 0) {
    return null;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

// Renders a scalar for map lookups and credentialKindDetection keys: bools as
// "true"/"false", numbers in canonical decimal form, strings verbatim.
export function scalarKey(value: Object | null): string | null {
  if (typeof value === 'boolean') {
    return value ? 'true' : 'false';
  }
  if (typeof value === 'number') {
    return decimalFromNumber(value)?.canonical ?? null;
  }
  if (typeof value === 'string') {
    return value;
  }
  return null;
}

// MARK: - Errors

// Engine errors keep the stable Error-token string convention documented in
// UsageProvider.ets; httpStatus carries the code as `httpStatus:<code>`.
export function engineError(token: string | null | undefined, statusCode?: number): Error {
  switch (token) {
    case 'invalidCredential':
    case 'rateLimited':
    case 'providerInactive':
    case 'unsupportedCredential':
    case 'regionDetectionFailed':
    case 'profileMismatch':
      return new Error(token);
    case 'httpStatus':
      return new Error(`httpStatus:${statusCode ?? 0}`);
    default:
      return new Error('invalidResponse');
  }
}

// Maps an engine Error message back to its bare token (httpStatus:<code> ->
// httpStatus); used by regionFallback's fallbackOn matching.
export function errorTokenOf(message: string): string {
  return message.startsWith('httpStatus:') ? 'httpStatus' : message;
}

// Spec-load failures are not provider errors; they use an explicit
// `invalidSpec:<detail>` / `unsupportedSpecVersion:<n>` / `unknownStrategy:<name>`
// message outside the runtime error-token table (mirrors Swift's
// ProviderSpecError cases).
export function specError(message: string): Error {
  return new Error(`invalidSpec:${message}`);
}

// MARK: - Conditions

export function evaluateCondition(
  conditionRaw: Object,
  root: Object | null,
  steps: Map<string, Object>
): boolean {
  const condition = asRecord(conditionRaw);
  if (condition === null) {
    return false;
  }
  const any = asArray(condition['any']);
  if (any !== null) {
    return any.some((nested: Object): boolean => evaluateCondition(nested, root, steps));
  }
  const all = asArray(condition['all']);
  if (all !== null) {
    return all.every((nested: Object): boolean => evaluateCondition(nested, root, steps));
  }
  let base = root;
  if (hasKey(condition, 'step')) {
    base = steps.get(condition['step'] as string) ?? null;
  }
  let actual: Object | null;
  if (hasKey(condition, 'path')) {
    actual = resolvePath(base, condition['path'] as string);
  } else {
    actual = base;
  }
  if (hasKey(condition, 'exists')) {
    return (actual !== null) === (condition['exists'] as boolean);
  }
  if (hasKey(condition, 'equals')) {
    return scalarEquals(actual, condition['equals']);
  }
  if (hasKey(condition, 'notEquals')) {
    return actual !== null && !scalarEquals(actual, condition['notEquals']);
  }
  if (hasKey(condition, 'lt')) {
    const bound = condition['lt'];
    const value = jsonDecimal(actual);
    return typeof bound === 'number' && value !== null && value.value < bound;
  }
  if (hasKey(condition, 'gt')) {
    const bound = condition['gt'];
    const value = jsonDecimal(actual);
    return typeof bound === 'number' && value !== null && value.value > bound;
  }
  return false;
}

// equals semantics: a numeric expectation parses the actual value as a
// decimal (number-or-string) and compares numerically; anything else is an
// exact scalar comparison. Absent actual is never equal.
export function scalarEquals(actual: Object | null, expected: Object): boolean {
  if (expected === null) {
    return actual === null;
  }
  if (typeof expected === 'boolean') {
    return jsonBool(actual) === expected;
  }
  if (typeof expected === 'number') {
    const value = jsonDecimal(actual);
    return value !== null && value.value === expected;
  }
  if (typeof expected === 'string') {
    return typeof actual === 'string' && actual === expected;
  }
  return false;
}

// MARK: - Checks

// Evaluates a parse block's ordered checks; the first failing entry throws
// its named error (default invalidResponse).
export function runChecks(checks: Object[], body: Object): void {
  const emptySteps: Map<string, Object> = new Map();
  for (const checkRaw of checks) {
    const check = asRecord(checkRaw);
    if (check === null) {
      throw specError('check entry is not an object');
    }
    const errorToken = hasKey(check, 'error') ? check['error'] as string : null;
    const eachItem = asRecord(check['eachItem']);
    if (eachItem !== null) {
      const resolved = resolvePath(body, eachItem['of'] as string);
      if (resolved === null) {
        continue;
      }
      const elements = asArray(resolved);
      if (elements === null) {
        throw engineError(errorToken);
      }
      for (const element of elements) {
        requireValue(
          resolvePath(element, eachItem['path'] as string),
          stringList(eachItem['transforms']),
          eachItem['required'] === true,
          eachItem['nonEmpty'] === true,
          errorToken,
          hasKey(eachItem, 'type') ? eachItem['type'] as string : null
        );
      }
      continue;
    }
    if (!hasKey(check, 'path')) {
      throw specError('check entry without a path');
    }
    const raw = resolvePath(body, check['path'] as string);
    if (check['required'] === true) {
      requireValue(
        raw,
        stringList(check['transforms']),
        true,
        check['nonEmpty'] === true,
        errorToken,
        hasKey(check, 'type') ? check['type'] as string : null
      );
    }
    if (check['strict'] === true) {
      // Optional but validated when present: absent is fine, a present value
      // that fails the type/nonEmpty rules throws (Swift optional Decodable
      // field semantics).
      requireValue(
        raw,
        stringList(check['transforms']),
        false,
        check['nonEmpty'] === true,
        errorToken,
        hasKey(check, 'type') ? check['type'] as string : null
      );
    }
    if (hasKey(check, 'when') && evaluateCondition(check['when'], raw, emptySteps)) {
      throw engineError(errorToken);
    }
  }
}

function requireValue(
  raw: Object | null,
  transforms: string[],
  required: boolean,
  nonEmpty: boolean,
  errorToken: string | null,
  type: string | null
): void {
  const failure = engineError(errorToken);
  if (raw === null) {
    if (required) {
      throw failure;
    }
    return;
  }
  if (type !== null) {
    let parseable: boolean;
    switch (type) {
      case 'decimal':
        parseable = jsonDecimal(raw) !== null;
        break;
      case 'string':
        parseable = jsonString(raw) !== null;
        break;
      case 'int':
        parseable = jsonInt(raw) !== null;
        break;
      case 'bool':
        parseable = jsonBool(raw) !== null;
        break;
      case 'date':
        parseable = jsonDateMs(raw) !== null;
        break;
      default:
        throw specError(`unknown value type '${type}'`);
    }
    if (!parseable) {
      throw failure;
    }
  }
  if (nonEmpty) {
    if (typeof raw === 'string') {
      const transformed = transformedString(raw, transforms);
      if (transformed === null || transformed.length === 0) {
        throw failure;
      }
    } else if (Array.isArray(raw)) {
      if ((raw as Object[]).length === 0) {
        throw failure;
      }
    }
  }
}

function transformedString(raw: Object | null, transforms: string[]): string | null {
  let value = jsonString(raw);
  if (value === null) {
    return null;
  }
  for (const transform of transforms) {
    if (transform === 'trim') {
      value = value.trim();
    } else if (transform === 'uppercase') {
      value = value.toUpperCase();
    }
  }
  return value;
}

// MARK: - Evaluated values

export interface EvalValue {
  kind: string;
  decimal?: SpecDecimal;
  text?: string;
  intValue?: number;
  boolValue?: boolean;
  dateMs?: number;
  currency?: string;
  fields?: Record<string, EvalValue>;
  items?: EvalValue[];
}

function evDecimal(decimal: SpecDecimal): EvalValue {
  const value: EvalValue = { kind: 'decimal', decimal: decimal };
  return value;
}

function evString(text: string): EvalValue {
  const value: EvalValue = { kind: 'string', text: text };
  return value;
}

function evInt(intValue: number): EvalValue {
  const value: EvalValue = { kind: 'int', intValue: intValue };
  return value;
}

function evBool(boolValue: boolean): EvalValue {
  const value: EvalValue = { kind: 'bool', boolValue: boolValue };
  return value;
}

function evDateMs(dateMs: number): EvalValue {
  const value: EvalValue = { kind: 'dateMs', dateMs: dateMs };
  return value;
}

function evMoney(amount: SpecDecimal, currency: string): EvalValue {
  const value: EvalValue = { kind: 'money', decimal: amount, currency: currency };
  return value;
}

function evObject(fields: Record<string, EvalValue>): EvalValue {
  const value: EvalValue = { kind: 'object', fields: fields };
  return value;
}

function evArray(items: EvalValue[]): EvalValue {
  const value: EvalValue = { kind: 'array', items: items };
  return value;
}

// Evaluation scope of one parse block (or one array item). Named values
// (values / itemValues) are resolved lazily and memoized; item scopes fall
// through to the enclosing step scope.
export class EvalScope {
  readonly root: Object | null;
  readonly region: string;
  readonly steps: Map<string, Object>;
  private readonly namedBuilders: Record<string, Object>;
  private readonly parent: EvalScope | null;
  private readonly cache: Map<string, EvalValue | null> = new Map();
  private readonly resolving: Set<string> = new Set();

  constructor(
    root: Object | null,
    region: string,
    steps: Map<string, Object>,
    namedBuilders: Record<string, Object>,
    parent: EvalScope | null
  ) {
    this.root = root;
    this.region = region;
    this.steps = steps;
    this.namedBuilders = namedBuilders;
    this.parent = parent;
  }

  namedValue(name: string): EvalValue | null {
    if (this.cache.has(name)) {
      return this.cache.get(name) ?? null;
    }
    if (!hasKey(this.namedBuilders, name)) {
      return this.parent !== null ? this.parent.namedValue(name) : null;
    }
    if (this.resolving.has(name)) {
      throw engineError('invalidResponse');
    }
    this.resolving.add(name);
    const value = evaluateBuilder(this.namedBuilders[name], this);
    this.resolving.delete(name);
    this.cache.set(name, value);
    return value;
  }
}

// MARK: - Field builders

export function evaluateBuilder(builderRaw: Object, scope: EvalScope): EvalValue | null {
  const builder = asRecord(builderRaw);
  if (builder === null) {
    throw engineError('invalidResponse');
  }
  if (hasKey(builder, 'when') && !evaluateCondition(builder['when'], scope.root, scope.steps)) {
    return null;
  }
  const object = asRecord(builder['object']);
  if (object !== null) {
    const fields: Record<string, EvalValue> = {};
    for (const key of Object.keys(object)) {
      const nested = evaluateBuilder(object[key], scope);
      if (nested !== null) {
        fields[key] = nested;
      }
    }
    return evObject(fields);
  }
  const money = asRecord(builder['money']);
  if (money !== null) {
    const amountValue = evaluateBuilder(money['amount'], scope);
    const currencyValue = evaluateBuilder(money['currency'], scope);
    if (amountValue === null || currencyValue === null) {
      return null;
    }
    if (amountValue.kind !== 'decimal' || currencyValue.kind !== 'string') {
      throw engineError('invalidResponse');
    }
    return evMoney(amountValue.decimal as SpecDecimal, currencyValue.text as string);
  }
  if (hasKey(builder, 'template')) {
    const rendered = renderTemplate(builder['template'] as string, scope);
    return rendered === null ? null : evString(rendered);
  }
  if (hasKey(builder, 'fromArray')) {
    return evaluateFromArray(builder, scope);
  }
  const fixed = asArray(builder['fixed']);
  if (fixed !== null) {
    return evaluateFixed(fixed, scope);
  }
  if (hasKey(builder, 'strategy')) {
    return evaluateStrategy(builder, scope);
  }
  if (hasKey(builder, 'op')) {
    const op = builder['op'] as string;
    if (op === 'subtract') {
      const a = evaluateBuilder(builder['a'], scope);
      const b = evaluateBuilder(builder['b'], scope);
      const aDecimal = a !== null && a.kind === 'decimal' ? a.decimal as SpecDecimal : null;
      const bDecimal = b !== null && b.kind === 'decimal' ? b.decimal as SpecDecimal : null;
      const difference = decimalSubtract(aDecimal, bDecimal);
      return difference === null ? null : evDecimal(difference);
    }
    if (op === 'count') {
      const resolved = resolvePath(scope.root, builder['path'] as string);
      const elements = asArray(resolved);
      if (elements === null) {
        return null;
      }
      return evInt(elements.length);
    }
    throw specError(`unknown op '${op}'`);
  }
  if (hasKey(builder, 'value')) {
    const reference = builder['value'];
    if (typeof reference === 'string') {
      return scope.namedValue(reference);
    }
    return evaluateBuilder(reference, scope);
  }
  const byRegion = asRecord(builder['byRegion']);
  if (byRegion !== null) {
    if (!hasKey(byRegion, scope.region)) {
      throw specError(`byRegion table misses region '${scope.region}'`);
    }
    return scalarValue(byRegion[scope.region]);
  }
  if (hasKey(builder, 'literal')) {
    return scalarValue(builder['literal']);
  }
  const map = asRecord(builder['map']);
  if (map !== null) {
    const key = scalarKey(resolvePath(scope.root, builder['path'] as string));
    if (key === null || !hasKey(map, key)) {
      return null;
    }
    return evString(map[key] as string);
  }
  if (hasKey(builder, 'path')) {
    return evaluatePathBuilder(builder, scope);
  }
  throw engineError('invalidResponse');
}

function evaluatePathBuilder(builder: Record<string, Object>, scope: EvalScope): EvalValue | null {
  const raw = resolvePath(scope.root, builder['path'] as string);
  const required = builder['required'] === true;
  const type = builder['type'] as string;
  switch (type) {
    case 'decimal': {
      const value = jsonDecimal(raw);
      if (value === null) {
        if (required) {
          throw engineError('invalidResponse');
        }
        return null;
      }
      return evDecimal(value);
    }
    case 'string': {
      const transforms = stringList(builder['transforms']);
      const value = transformedString(raw, transforms);
      if (value === null) {
        if (required) {
          throw engineError('invalidResponse');
        }
        return null;
      }
      if (value.length === 0) {
        if (required && builder['nonEmpty'] === true) {
          throw engineError('invalidResponse');
        }
        if (builder['nullIfEmpty'] === true) {
          return null;
        }
      }
      return evString(value);
    }
    case 'int': {
      const value = jsonInt(raw);
      if (value === null) {
        if (required) {
          throw engineError('invalidResponse');
        }
        return null;
      }
      return evInt(value);
    }
    case 'bool': {
      const value = jsonBool(raw);
      if (value === null) {
        if (required) {
          throw engineError('invalidResponse');
        }
        return null;
      }
      return evBool(value);
    }
    case 'date': {
      const value = jsonDateMs(raw);
      if (value === null) {
        if (required) {
          throw engineError('invalidResponse');
        }
        return null;
      }
      return evDateMs(value);
    }
    default:
      throw specError(`unknown value type '${type}'`);
  }
}

function evaluateFromArray(builder: Record<string, Object>, scope: EvalScope): EvalValue {
  const resolved = resolvePath(scope.root, builder['fromArray'] as string);
  if (resolved === null) {
    return evArray([]);
  }
  const elements = asArray(resolved);
  if (elements === null) {
    throw engineError('invalidResponse');
  }
  const itemValues = asRecord(builder['itemValues']);
  const namedBuilders: Record<string, Object> = itemValues ?? {};
  const itemBuilders = asRecord(builder['item']);
  const results: EvalValue[] = [];
  for (const element of elements) {
    if (asRecord(element) === null) {
      throw engineError('invalidResponse');
    }
    const itemScope = new EvalScope(element, scope.region, scope.steps, namedBuilders, scope);
    if (hasKey(builder, 'skipItemWhen')
      && evaluateCondition(builder['skipItemWhen'], element, scope.steps)) {
      continue;
    }
    const fields: Record<string, EvalValue> = {};
    if (itemBuilders !== null) {
      for (const key of Object.keys(itemBuilders)) {
        const value = evaluateBuilder(itemBuilders[key], itemScope);
        if (value !== null) {
          fields[key] = value;
        }
      }
    }
    results.push(evObject(fields));
  }
  return evArray(results);
}

function evaluateFixed(entries: Object[], scope: EvalScope): EvalValue {
  const results: EvalValue[] = [];
  for (const entryRaw of entries) {
    const entry = asRecord(entryRaw);
    if (entry === null) {
      throw engineError('invalidResponse');
    }
    if (hasKey(entry, 'when') && !evaluateCondition(entry['when'], scope.root, scope.steps)) {
      continue;
    }
    const fields: Record<string, EvalValue> = {};
    for (const key of Object.keys(entry)) {
      if (key === 'when') {
        continue;
      }
      const value = evaluateBuilder(entry[key], scope);
      if (value !== null) {
        fields[key] = value;
      }
    }
    results.push(evObject(fields));
  }
  return evArray(results);
}

function evaluateStrategy(builder: Record<string, Object>, scope: EvalScope): EvalValue {
  const strategy = builder['strategy'] as string;
  if (strategy !== 'miniMaxModelRemains') {
    throw new Error(`unknownStrategy:${strategy}`);
  }
  const source = hasKey(builder, 'path') ? resolvePath(scope.root, builder['path'] as string) : null;
  const windows = miniMaxModelRemainsWindows(source);
  if (builder['requireNonEmpty'] === true && windows.length === 0) {
    throw engineError('invalidResponse');
  }
  return quotaWindowsValue(windows);
}

function scalarValue(json: Object): EvalValue | null {
  if (json === null) {
    return null;
  }
  if (typeof json === 'boolean') {
    return evBool(json);
  }
  if (typeof json === 'number') {
    const decimal = decimalFromNumber(json);
    return decimal === null ? null : evDecimal(decimal);
  }
  if (typeof json === 'string') {
    return evString(json);
  }
  throw engineError('invalidResponse');
}

// Interpolates ${name} references against named values only; any unresolved
// or null reference nulls the whole template.
function renderTemplate(template: string, scope: EvalScope): string | null {
  const pattern = /\$\{([^}]*)\}/g;
  let result = '';
  let lastIndex = 0;
  let match = pattern.exec(template);
  while (match !== null) {
    result += template.substring(lastIndex, match.index);
    const value = scope.namedValue(match[1]);
    if (value === null) {
      return null;
    }
    const rendered = renderScalar(value);
    if (rendered === null) {
      return null;
    }
    result += rendered;
    lastIndex = match.index + match[0].length;
    match = pattern.exec(template);
  }
  result += template.substring(lastIndex);
  return result;
}

function renderScalar(value: EvalValue): string | null {
  switch (value.kind) {
    case 'string':
      return value.text as string;
    case 'int':
      return String(value.intValue);
    case 'decimal':
      return (value.decimal as SpecDecimal).canonical;
    case 'bool':
      return value.boolValue === true ? 'true' : 'false';
    default:
      return null;
  }
}

function quotaWindowsValue(windows: QuotaWindow[]): EvalValue {
  const items: EvalValue[] = [];
  for (const window of windows) {
    const fields: Record<string, EvalValue> = {
      'label': evString(window.label),
      'unit': evString(window.unit)
    };
    if (window.used !== undefined) {
      const decimal = decimalFromNumber(window.used);
      if (decimal !== null) {
        fields['used'] = evDecimal(decimal);
      }
    }
    if (window.limit !== undefined) {
      const decimal = decimalFromNumber(window.limit);
      if (decimal !== null) {
        fields['limit'] = evDecimal(decimal);
      }
    }
    if (window.remaining !== undefined) {
      const decimal = decimalFromNumber(window.remaining);
      if (decimal !== null) {
        fields['remaining'] = evDecimal(decimal);
      }
    }
    if (window.resetsAtMs !== undefined) {
      fields['resetsAt'] = evDateMs(window.resetsAtMs);
    }
    items.push(evObject(fields));
  }
  return evArray(items);
}

// MARK: - Snapshot assembly

// Assembles evaluated field values into the typed snapshot model. Structural
// mismatches are invalidResponse, matching the hand-written providers'
// catch-all for parse failures.
export function assembleSnapshot(
  merged: Record<string, EvalValue>,
  providerId: string,
  receivedAtMs: number
): UsageSnapshot {
  const snapshot: UsageSnapshot = {
    provider: providerId,
    balances: [],
    receivedAtMs: receivedAtMs
  };
  for (const field of Object.keys(merged)) {
    const value = merged[field];
    switch (field) {
      case 'balances':
        snapshot.balances = assembleBalances(value);
        break;
      case 'spendingLimit':
        snapshot.spendingLimit = assembleSpendingLimit(value);
        break;
      case 'spend':
        snapshot.spend = assembleSpend(value);
        break;
      case 'quotaWindows':
        snapshot.quotaWindows = assembleQuotaWindows(value);
        break;
      case 'today':
        snapshot.today = assembleCounters(value);
        break;
      case 'total':
        snapshot.total = assembleCounters(value);
        break;
      case 'dailyUsage':
        snapshot.dailyUsage = assembleDailyUsage(value);
        break;
      case 'modelUsage':
        snapshot.modelUsage = assembleModelUsage(value);
        break;
      case 'providerStatus': {
        const status = assembleString(value);
        if (status !== null) {
          snapshot.providerStatus = status;
        }
        break;
      }
      case 'metricsUnavailableReason': {
        const reason = assembleString(value);
        if (reason !== null) {
          snapshot.metricsUnavailableReason = reason;
        }
        break;
      }
      default:
        throw specError(`unknown snapshot field '${field}'`);
    }
  }
  return snapshot;
}

function assembleString(value: EvalValue | undefined): string | null {
  if (value === undefined) {
    return null;
  }
  if (value.kind !== 'string') {
    throw engineError('invalidResponse');
  }
  return value.text as string;
}

function assembleNumber(value: EvalValue | undefined): number | null {
  if (value === undefined) {
    return null;
  }
  if (value.kind === 'decimal') {
    return (value.decimal as SpecDecimal).value;
  }
  if (value.kind === 'int') {
    return value.intValue as number;
  }
  throw engineError('invalidResponse');
}

function assembleMoney(value: EvalValue | undefined): Money | null {
  if (value === undefined) {
    return null;
  }
  if (value.kind !== 'money') {
    throw engineError('invalidResponse');
  }
  const money: Money = {
    amount: (value.decimal as SpecDecimal).canonical,
    currency: value.currency as string
  };
  return money;
}

function assembleObjectFields(value: EvalValue): Record<string, EvalValue> {
  if (value.kind !== 'object') {
    throw engineError('invalidResponse');
  }
  return value.fields as Record<string, EvalValue>;
}

function assembleItems(value: EvalValue): EvalValue[] {
  if (value.kind !== 'array') {
    throw engineError('invalidResponse');
  }
  return value.items as EvalValue[];
}

function assembleBalances(value: EvalValue): MonetaryBalance[] {
  const balances: MonetaryBalance[] = [];
  for (const item of assembleItems(value)) {
    const fields = assembleObjectFields(item);
    const label = assembleString(fields['label']);
    const available = assembleMoney(fields['available']);
    if (label === null || available === null) {
      throw engineError('invalidResponse');
    }
    const balance: MonetaryBalance = {
      label: label,
      available: available,
      breakdown: fields['breakdown'] !== undefined ? assembleMonetaryValues(fields['breakdown']) : []
    };
    balances.push(balance);
  }
  return balances;
}

function assembleMonetaryValues(value: EvalValue): MonetaryValue[] {
  const values: MonetaryValue[] = [];
  for (const item of assembleItems(value)) {
    const fields = assembleObjectFields(item);
    const label = assembleString(fields['label']);
    const itemValue = assembleMoney(fields['value']);
    if (label === null || itemValue === null) {
      throw engineError('invalidResponse');
    }
    const monetaryValue: MonetaryValue = { label: label, value: itemValue };
    values.push(monetaryValue);
  }
  return values;
}

function assembleSpendingLimit(value: EvalValue): SpendingLimit {
  const fields = assembleObjectFields(value);
  const label = assembleString(fields['label']);
  if (label === null) {
    throw engineError('invalidResponse');
  }
  const limit: SpendingLimit = { label: label };
  const used = assembleMoney(fields['used']);
  if (used !== null) {
    limit.used = used;
  }
  const limitValue = assembleMoney(fields['limit']);
  if (limitValue !== null) {
    limit.limit = limitValue;
  }
  const remaining = assembleMoney(fields['remaining']);
  if (remaining !== null) {
    limit.remaining = remaining;
  }
  const resetDescription = assembleString(fields['resetDescription']);
  if (resetDescription !== null) {
    limit.resetDescription = resetDescription;
  }
  return limit;
}

function assembleSpend(value: EvalValue): SpendSummary {
  const fields = assembleObjectFields(value);
  const spend: SpendSummary = {};
  const today = assembleMoney(fields['today']);
  if (today !== null) {
    spend.today = today;
  }
  const week = assembleMoney(fields['week']);
  if (week !== null) {
    spend.week = week;
  }
  const month = assembleMoney(fields['month']);
  if (month !== null) {
    spend.month = month;
  }
  const total = assembleMoney(fields['total']);
  if (total !== null) {
    spend.total = total;
  }
  return spend;
}

function assembleCounters(value: EvalValue): UsageCounters {
  const fields = assembleObjectFields(value);
  const counters: UsageCounters = {};
  const actualCost = assembleMoney(fields['actualCost']);
  if (actualCost !== null) {
    counters.actualCost = actualCost;
  }
  const requests = assembleNumber(fields['requests']);
  if (requests !== null) {
    counters.requests = requests;
  }
  const inputTokens = assembleNumber(fields['inputTokens']);
  if (inputTokens !== null) {
    counters.inputTokens = inputTokens;
  }
  const outputTokens = assembleNumber(fields['outputTokens']);
  if (outputTokens !== null) {
    counters.outputTokens = outputTokens;
  }
  const cacheReadTokens = assembleNumber(fields['cacheReadTokens']);
  if (cacheReadTokens !== null) {
    counters.cacheReadTokens = cacheReadTokens;
  }
  const cacheCreationTokens = assembleNumber(fields['cacheCreationTokens']);
  if (cacheCreationTokens !== null) {
    counters.cacheCreationTokens = cacheCreationTokens;
  }
  const totalTokens = assembleNumber(fields['totalTokens']);
  if (totalTokens !== null) {
    counters.totalTokens = totalTokens;
  }
  return counters;
}

function assembleDailyUsage(value: EvalValue): DailyUsage[] {
  const entries: DailyUsage[] = [];
  for (const item of assembleItems(value)) {
    const fields = assembleObjectFields(item);
    const date = assembleString(fields['date']);
    if (date === null) {
      throw engineError('invalidResponse');
    }
    // DailyUsage.actualCost is non-optional; entries the spec did not already
    // filter out but that still lack a cost are dropped, like the old
    // hand-written providers.
    const actualCost = assembleMoney(fields['actualCost']);
    if (actualCost === null) {
      continue;
    }
    const entry: DailyUsage = { date: date, actualCost: actualCost };
    const requests = assembleNumber(fields['requests']);
    if (requests !== null) {
      entry.requests = requests;
    }
    const totalTokens = assembleNumber(fields['totalTokens']);
    if (totalTokens !== null) {
      entry.totalTokens = totalTokens;
    }
    entries.push(entry);
  }
  return entries;
}

function assembleModelUsage(value: EvalValue): ModelUsage[] {
  const entries: ModelUsage[] = [];
  for (const item of assembleItems(value)) {
    const fields = assembleObjectFields(item);
    const model = assembleString(fields['model']);
    if (model === null) {
      throw engineError('invalidResponse');
    }
    const entry: ModelUsage = { model: model };
    const actualCost = assembleMoney(fields['actualCost']);
    if (actualCost !== null) {
      entry.actualCost = actualCost;
    }
    const requests = assembleNumber(fields['requests']);
    if (requests !== null) {
      entry.requests = requests;
    }
    const totalTokens = assembleNumber(fields['totalTokens']);
    if (totalTokens !== null) {
      entry.totalTokens = totalTokens;
    }
    entries.push(entry);
  }
  return entries;
}

function assembleQuotaWindows(value: EvalValue): QuotaWindow[] {
  const windows: QuotaWindow[] = [];
  for (const item of assembleItems(value)) {
    const fields = assembleObjectFields(item);
    const label = assembleString(fields['label']);
    const unit = assembleString(fields['unit']);
    if (label === null || unit === null) {
      throw engineError('invalidResponse');
    }
    const window: QuotaWindow = { label: label, unit: unit };
    const used = assembleNumber(fields['used']);
    if (used !== null) {
      window.used = used;
    }
    const limit = assembleNumber(fields['limit']);
    if (limit !== null) {
      window.limit = limit;
    }
    const remaining = assembleNumber(fields['remaining']);
    if (remaining !== null) {
      window.remaining = remaining;
    }
    const resetsAt = fields['resetsAt'];
    if (resetsAt !== undefined) {
      if (resetsAt.kind !== 'dateMs') {
        throw engineError('invalidResponse');
      }
      window.resetsAtMs = resetsAt.dateMs as number;
    }
    windows.push(window);
  }
  return windows;
}
