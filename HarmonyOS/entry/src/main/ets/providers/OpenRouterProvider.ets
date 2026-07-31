import { getJsonWithStatus, throwForHttpStatus } from '../network/HttpClient';
import {
  Money,
  SpendingLimit,
  SpendSummary,
  UsageSnapshot
} from './UsageSnapshot';
import {
  HttpFetcher,
  ProviderCredentialKind,
  ProviderDetection,
  ProviderID,
  ProviderProfile,
  RawJsonResponse,
  UsageProvider
} from './UsageProvider';

interface KeyResponsePayload {
  is_management_key?: boolean;
  usage?: string | number;
  limit?: string | number;
  limit_remaining?: string | number;
  usage_daily?: string | number;
  usage_weekly?: string | number;
  usage_monthly?: string | number;
}

interface KeyEnvelopePayload {
  data?: KeyResponsePayload;
}

interface CreditsResponsePayload {
  total_credits?: string | number;
  total_usage?: string | number;
}

interface CreditsEnvelopePayload {
  data?: CreditsResponsePayload;
}

interface KeyData {
  isManagementKey: boolean;
  usage?: string;
  limit?: string;
  limitRemaining?: string;
  usageDaily?: string;
  usageWeekly?: string;
  usageMonthly?: string;
}

function decimalString(raw: string | number | undefined): string | null {
  if (raw === undefined) {
    return null;
  }
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? String(raw) : null;
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return null;
  }
  return Number.isFinite(Number(trimmed)) ? trimmed : null;
}

export class OpenRouterProvider implements UsageProvider {
  static readonly KEY_ENDPOINT: string = 'https://openrouter.ai/api/v1/key';
  static readonly CREDITS_ENDPOINT: string = 'https://openrouter.ai/api/v1/credits';

  readonly id: ProviderID = 'openRouter';

  private readonly now: () => number;

  private readonly fetcher: HttpFetcher;

  constructor(now?: () => number, fetcher?: HttpFetcher) {
    this.now = now ?? ((): number => Date.now());
    this.fetcher = fetcher ?? getJsonWithStatus;
  }

  async detect(apiKey: string): Promise<ProviderDetection> {
    const key = await this.requestKey(apiKey);
    const kind: ProviderCredentialKind = key.isManagementKey ? 'management' : 'standard';
    const snapshot = await this.buildSnapshot(apiKey, key);
    const detection: ProviderDetection = {
      profile: { region: 'global', credentialKind: kind },
      snapshot: snapshot
    };
    return detection;
  }

  async fetch(apiKey: string): Promise<UsageSnapshot> {
    const detection = await this.detect(apiKey);
    return detection.snapshot;
  }

  async fetchWithProfile(apiKey: string, profile: ProviderProfile): Promise<UsageSnapshot> {
    if (profile.region !== 'global' ||
      (profile.credentialKind !== 'standard' && profile.credentialKind !== 'management')) {
      throw new Error('profileMismatch');
    }
    const key = await this.requestKey(apiKey);
    const observedKind: ProviderCredentialKind = key.isManagementKey ? 'management' : 'standard';
    if (observedKind !== profile.credentialKind) {
      throw new Error('profileMismatch');
    }
    return this.buildSnapshot(apiKey, key);
  }

  // Parses a /key response body into the key-derived snapshot. The Management
  // Key credits balance requires the second /credits request and is only
  // merged by the fetch path, so parseResponse never includes it.
  parseResponse(responseBody: string, receivedAtMs: number): UsageSnapshot {
    const key = this.parseKeyBody(responseBody);
    return this.buildKeySnapshot(key, undefined, receivedAtMs);
  }

  private async requestKey(apiKey: string): Promise<KeyData> {
    const response: RawJsonResponse = await this.fetcher(OpenRouterProvider.KEY_ENDPOINT, apiKey);
    throwForHttpStatus(response.code);
    return this.parseKeyBody(response.body);
  }

  private parseKeyBody(responseBody: string): KeyData {
    let envelope: KeyEnvelopePayload;
    try {
      envelope = JSON.parse(responseBody) as KeyEnvelopePayload;
    } catch (error) {
      throw new Error('invalidResponse');
    }
    const data = envelope.data;
    if (data === undefined || data.is_management_key === undefined) {
      throw new Error('invalidResponse');
    }
    const key: KeyData = { isManagementKey: data.is_management_key };
    const usage = decimalString(data.usage);
    if (usage !== null) {
      key.usage = usage;
    }
    const limit = decimalString(data.limit);
    if (limit !== null) {
      key.limit = limit;
    }
    const limitRemaining = decimalString(data.limit_remaining);
    if (limitRemaining !== null) {
      key.limitRemaining = limitRemaining;
    }
    const usageDaily = decimalString(data.usage_daily);
    if (usageDaily !== null) {
      key.usageDaily = usageDaily;
    }
    const usageWeekly = decimalString(data.usage_weekly);
    if (usageWeekly !== null) {
      key.usageWeekly = usageWeekly;
    }
    const usageMonthly = decimalString(data.usage_monthly);
    if (usageMonthly !== null) {
      key.usageMonthly = usageMonthly;
    }
    return key;
  }

  private async buildSnapshot(apiKey: string, key: KeyData): Promise<UsageSnapshot> {
    let creditsBalance: Money | undefined = undefined;
    if (key.isManagementKey) {
      const response: RawJsonResponse =
        await this.fetcher(OpenRouterProvider.CREDITS_ENDPOINT, apiKey);
      throwForHttpStatus(response.code);
      creditsBalance = this.parseCreditsBalance(response.body);
    }
    return this.buildKeySnapshot(key, creditsBalance, this.now());
  }

  private parseCreditsBalance(responseBody: string): Money {
    let envelope: CreditsEnvelopePayload;
    try {
      envelope = JSON.parse(responseBody) as CreditsEnvelopePayload;
    } catch (error) {
      throw new Error('invalidResponse');
    }
    const totalCredits = decimalString(envelope.data?.total_credits);
    const totalUsage = decimalString(envelope.data?.total_usage);
    if (totalCredits === null || totalUsage === null) {
      throw new Error('invalidResponse');
    }
    // The remainder may be negative; both sides are decimal strings.
    const remainder = Number(totalCredits) - Number(totalUsage);
    const balance: Money = { amount: String(remainder), currency: 'USD' };
    return balance;
  }

  private buildKeySnapshot(
    key: KeyData,
    creditsBalance: Money | undefined,
    receivedAtMs: number
  ): UsageSnapshot {
    const currency = 'USD';
    const snapshot: UsageSnapshot = {
      provider: this.id,
      balances: [],
      providerStatus: 'active',
      receivedAtMs: receivedAtMs
    };

    if (key.limit !== undefined) {
      const spendingLimit: SpendingLimit = {
        label: 'Key limit',
        limit: { amount: key.limit, currency: currency }
      };
      if (key.usage !== undefined) {
        spendingLimit.used = { amount: key.usage, currency: currency };
      }
      if (key.limitRemaining !== undefined) {
        spendingLimit.remaining = { amount: key.limitRemaining, currency: currency };
      }
      snapshot.spendingLimit = spendingLimit;
    }

    const spend: SpendSummary = {};
    if (key.usageDaily !== undefined) {
      spend.today = { amount: key.usageDaily, currency: currency };
    }
    if (key.usageWeekly !== undefined) {
      spend.week = { amount: key.usageWeekly, currency: currency };
    }
    if (key.usageMonthly !== undefined) {
      spend.month = { amount: key.usageMonthly, currency: currency };
    }
    if (key.usage !== undefined) {
      spend.total = { amount: key.usage, currency: currency };
    }
    if (spend.today !== undefined || spend.week !== undefined ||
      spend.month !== undefined || spend.total !== undefined) {
      snapshot.spend = spend;
    }

    if (creditsBalance !== undefined) {
      snapshot.balances = [{ label: 'Credits', available: creditsBalance, breakdown: [] }];
    }

    return snapshot;
  }
}
