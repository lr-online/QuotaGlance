import { i18n } from '@kit.LocalizationKit';
import { getJsonWithStatus, throwForHttpStatus } from '../network/HttpClient';
import { QuotaWindow, UsageSnapshot } from './UsageSnapshot';
import {
  HttpFetcher,
  ProviderDetection,
  ProviderID,
  ProviderProfile,
  ProviderRegion,
  RawJsonResponse,
  UsageProvider
} from './UsageProvider';

type RawDecimal = string | number;

interface BaseRespPayload {
  status_code?: RawDecimal;
}

interface ModelRemainPayload {
  model_name?: string;
  label?: string;
  unit?: string;
  remains?: RawDecimal;
  total?: RawDecimal;
  used?: RawDecimal;
  reset_time?: RawDecimal;
  start_time?: RawDecimal;
  end_time?: RawDecimal;
  current_interval_total_count?: RawDecimal;
  current_interval_usage_count?: RawDecimal;
  current_interval_status?: RawDecimal;
  current_interval_remaining_percent?: RawDecimal;
  current_weekly_total_count?: RawDecimal;
  current_weekly_usage_count?: RawDecimal;
  current_weekly_status?: RawDecimal;
  current_weekly_remaining_percent?: RawDecimal;
  weekly_end_time?: RawDecimal;
}

interface RemainsResponsePayload {
  model_remains?: ModelRemainPayload[];
  base_resp?: BaseRespPayload;
}

function decimalNumber(raw: RawDecimal | undefined): number | null {
  if (raw === undefined) {
    return null;
  }
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? raw : null;
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return null;
  }
  const value = Number(trimmed);
  return Number.isFinite(value) ? value : null;
}

function normalizedLabel(value: string | undefined): string | undefined {
  if (value === undefined) {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? undefined : trimmed;
}

function normalizedModelName(value: string | undefined): string {
  return normalizedLabel(value) ?? 'Token Plan';
}

// Provider timestamps arrive as epoch seconds or milliseconds; normalize to
// epoch milliseconds (Swift providerDate's 1e10 threshold).
function providerDateMs(raw: RawDecimal | undefined): number | undefined {
  const value = decimalNumber(raw);
  if (value === null) {
    return undefined;
  }
  const seconds = Math.abs(value) > 10000000000 ? value / 1000 : value;
  return seconds * 1000;
}

function providerDateSeconds(raw: RawDecimal | undefined): number | undefined {
  const value = decimalNumber(raw);
  if (value === null) {
    return undefined;
  }
  return Math.abs(value) > 10000000000 ? value / 1000 : value;
}

function isFiveHourWindow(start: RawDecimal | undefined, end: RawDecimal | undefined): boolean {
  const startSeconds = providerDateSeconds(start);
  const endSeconds = providerDateSeconds(end);
  if (startSeconds === undefined || endSeconds === undefined) {
    return false;
  }
  return Math.abs((endSeconds - startSeconds) - 18000) < 1;
}

function subtract(lhs: number | null, rhs: number | null): number | undefined {
  if (lhs === null || rhs === null) {
    return undefined;
  }
  return lhs - rhs;
}

export class MiniMaxProvider implements UsageProvider {
  static readonly CHINA_ENDPOINT: string = 'https://www.minimaxi.com/v1/token_plan/remains';
  static readonly INTERNATIONAL_ENDPOINT: string = 'https://www.minimax.io/v1/token_plan/remains';

  readonly id: ProviderID = 'miniMax';

  private readonly preferredRegion: ProviderRegion;

  private readonly now: () => number;

  private readonly fetcher: HttpFetcher;

  constructor(preferredRegion?: ProviderRegion, now?: () => number, fetcher?: HttpFetcher) {
    this.preferredRegion = MiniMaxProvider.supportedRegion(preferredRegion)
      ?? MiniMaxProvider.localePreferredRegion();
    this.now = now ?? ((): number => Date.now());
    this.fetcher = fetcher ?? getJsonWithStatus;
  }

  async detect(apiKey: string): Promise<ProviderDetection> {
    const key = apiKey.trim();
    MiniMaxProvider.validateCredential(key);
    try {
      const snapshot = await this.requestQuota(key, this.preferredRegion);
      const detection: ProviderDetection = {
        profile: MiniMaxProvider.profileFor(this.preferredRegion),
        snapshot: snapshot
      };
      return detection;
    } catch (error) {
      if ((error as Error).message !== 'invalidCredential') {
        throw error as Error;
      }
    }
    const fallbackRegion: ProviderRegion =
      this.preferredRegion === 'china' ? 'international' : 'china';
    try {
      const snapshot = await this.requestQuota(key, fallbackRegion);
      const detection: ProviderDetection = {
        profile: MiniMaxProvider.profileFor(fallbackRegion),
        snapshot: snapshot
      };
      return detection;
    } catch (error) {
      if ((error as Error).message === 'invalidCredential') {
        throw new Error('regionDetectionFailed');
      }
      throw error as Error;
    }
  }

  async fetch(apiKey: string): Promise<UsageSnapshot> {
    const detection = await this.detect(apiKey);
    return detection.snapshot;
  }

  async fetchWithProfile(apiKey: string, profile: ProviderProfile): Promise<UsageSnapshot> {
    const key = apiKey.trim();
    MiniMaxProvider.validateCredential(key);
    const region = MiniMaxProvider.supportedRegion(profile.region);
    if (profile.credentialKind !== 'tokenPlan' || region === undefined) {
      throw new Error('profileMismatch');
    }
    return this.requestQuota(key, region);
  }

  // Parses a token-plan remains response body (region-independent).
  parseResponse(responseBody: string, receivedAtMs: number): UsageSnapshot {
    return this.parseQuota(responseBody, receivedAtMs);
  }

  private static validateCredential(apiKey: string): void {
    if (apiKey.toLowerCase().startsWith('sk-api-')) {
      throw new Error('unsupportedCredential');
    }
  }

  private static supportedRegion(region: ProviderRegion | undefined): ProviderRegion | undefined {
    if (region === 'china' || region === 'international') {
      return region;
    }
    return undefined;
  }

  private static localePreferredRegion(): ProviderRegion {
    try {
      return i18n.System.getSystemRegion().toUpperCase() === 'CN' ? 'china' : 'international';
    } catch (error) {
      return 'international';
    }
  }

  private static profileFor(region: ProviderRegion): ProviderProfile {
    const profile: ProviderProfile = { region: region, credentialKind: 'tokenPlan' };
    return profile;
  }

  private static endpointFor(region: ProviderRegion): string {
    return region === 'china' ? MiniMaxProvider.CHINA_ENDPOINT : MiniMaxProvider.INTERNATIONAL_ENDPOINT;
  }

  private async requestQuota(apiKey: string, region: ProviderRegion): Promise<UsageSnapshot> {
    const response: RawJsonResponse =
      await this.fetcher(MiniMaxProvider.endpointFor(region), apiKey);
    throwForHttpStatus(response.code);
    return this.parseQuota(response.body, this.now());
  }

  private parseQuota(responseBody: string, receivedAtMs: number): UsageSnapshot {
    let payload: RemainsResponsePayload;
    try {
      payload = JSON.parse(responseBody) as RemainsResponsePayload;
    } catch (error) {
      throw new Error('invalidResponse');
    }

    // HTTP-200 responses with a nonzero embedded status_code are still errors.
    const statusCode = decimalNumber(payload.base_resp?.status_code);
    if (statusCode === null) {
      throw new Error('invalidResponse');
    }
    if (statusCode === 1004) {
      throw new Error('invalidCredential');
    }
    if (statusCode !== 0) {
      throw new Error('invalidResponse');
    }

    const windows: QuotaWindow[] = [];
    for (const entry of payload.model_remains ?? []) {
      for (const window of MiniMaxProvider.quotaWindowsFor(entry)) {
        windows.push(window);
      }
    }
    if (windows.length === 0) {
      throw new Error('invalidResponse');
    }

    const snapshot: UsageSnapshot = {
      provider: this.id,
      balances: [],
      quotaWindows: windows,
      providerStatus: 'active',
      receivedAtMs: receivedAtMs
    };
    return snapshot;
  }

  private static quotaWindowsFor(entry: ModelRemainPayload): QuotaWindow[] {
    const direct = MiniMaxProvider.directQuotaWindowFor(entry);
    if (direct !== undefined) {
      return [direct];
    }

    const windows: QuotaWindow[] = [];
    // Missing status counts as active, matching Swift's `status?.value != 0`.
    if (decimalNumber(entry.current_interval_status) !== 0) {
      const interval = MiniMaxProvider.intervalQuotaWindowFor(entry);
      if (interval !== undefined) {
        windows.push(interval);
      }
    }
    if (decimalNumber(entry.current_weekly_status) !== 0) {
      const weekly = MiniMaxProvider.weeklyQuotaWindowFor(entry);
      if (weekly !== undefined) {
        windows.push(weekly);
      }
    }
    return windows;
  }

  private static directQuotaWindowFor(entry: ModelRemainPayload): QuotaWindow | undefined {
    const limit = decimalNumber(entry.total);
    const suppliedUsed = decimalNumber(entry.used);
    const suppliedRemaining = decimalNumber(entry.remains);
    if (limit === null && suppliedUsed === null && suppliedRemaining === null) {
      return undefined;
    }

    const used = suppliedUsed ?? subtract(limit, suppliedRemaining);
    const remaining = suppliedRemaining ?? subtract(limit, suppliedUsed);
    const window: QuotaWindow = {
      label: normalizedLabel(entry.label) ?? `${normalizedModelName(entry.model_name)} quota`,
      unit: normalizedLabel(entry.unit) ?? 'requests'
    };
    if (used !== undefined) {
      window.used = used;
    }
    if (limit !== null) {
      window.limit = limit;
    }
    if (remaining !== undefined) {
      window.remaining = remaining;
    }
    const resetsAtMs = providerDateMs(entry.reset_time ?? entry.end_time);
    if (resetsAtMs !== undefined) {
      window.resetsAtMs = resetsAtMs;
    }
    return window;
  }

  private static intervalQuotaWindowFor(entry: ModelRemainPayload): QuotaWindow | undefined {
    const label = isFiveHourWindow(entry.start_time, entry.end_time)
      ? `${normalizedModelName(entry.model_name)} 5-hour quota`
      : `${normalizedModelName(entry.model_name)} quota`;
    return MiniMaxProvider.countedOrPercentWindow(
      label,
      entry.current_interval_total_count,
      entry.current_interval_usage_count,
      entry.current_interval_remaining_percent,
      entry.end_time
    );
  }

  private static weeklyQuotaWindowFor(entry: ModelRemainPayload): QuotaWindow | undefined {
    return MiniMaxProvider.countedOrPercentWindow(
      `${normalizedModelName(entry.model_name)} weekly quota`,
      entry.current_weekly_total_count,
      entry.current_weekly_usage_count,
      entry.current_weekly_remaining_percent,
      entry.weekly_end_time
    );
  }

  private static countedOrPercentWindow(
    label: string,
    total: RawDecimal | undefined,
    used: RawDecimal | undefined,
    remainingPercent: RawDecimal | undefined,
    resetsAt: RawDecimal | undefined
  ): QuotaWindow | undefined {
    const totalValue = decimalNumber(total);
    const usedValue = decimalNumber(used);
    const resetsAtMs = providerDateMs(resetsAt);

    if ((totalValue !== null && totalValue > 0) || (usedValue !== null && usedValue > 0)) {
      const window: QuotaWindow = { label: label, unit: 'requests' };
      if (usedValue !== null) {
        window.used = usedValue;
      }
      if (totalValue !== null) {
        window.limit = totalValue;
      }
      const remaining = subtract(totalValue, usedValue);
      if (remaining !== undefined) {
        window.remaining = remaining;
      }
      if (resetsAtMs !== undefined) {
        window.resetsAtMs = resetsAtMs;
      }
      return window;
    }

    const percentage = decimalNumber(remainingPercent);
    if (percentage !== null) {
      const remaining = Math.max(0, Math.min(100, percentage));
      const window: QuotaWindow = {
        label: label,
        used: 100 - remaining,
        limit: 100,
        remaining: remaining,
        unit: '%'
      };
      if (resetsAtMs !== undefined) {
        window.resetsAtMs = resetsAtMs;
      }
      return window;
    }

    return undefined;
  }
}
