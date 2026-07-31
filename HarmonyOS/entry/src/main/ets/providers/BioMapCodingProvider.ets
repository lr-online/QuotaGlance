import { getJsonWithStatus, throwForHttpStatus } from '../network/HttpClient';
import {
  Money,
  SpendingLimit,
  SpendSummary,
  UsageSnapshot
} from './UsageSnapshot';
import {
  HttpFetcher,
  ProviderDetection,
  ProviderID,
  ProviderProfile,
  RawJsonResponse,
  UsageProvider
} from './UsageProvider';

interface KeyInfoPayload {
  spend?: string | number;
  max_budget?: string | number;
  budget_duration?: string;
  blocked?: boolean;
}

interface KeyInfoResponsePayload {
  info: KeyInfoPayload;
}

interface ModelPayload {
  id: string;
}

interface ModelListPayload {
  object: string;
  data: ModelPayload[];
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

export class BioMapCodingProvider implements UsageProvider {
  static readonly KEY_INFO_ENDPOINT: string = 'https://coding.biomap-int.com/key/info';
  static readonly MODELS_ENDPOINT: string = 'https://coding.biomap-int.com/v1/models';

  readonly id: ProviderID = 'bioMapCoding';

  private readonly now: () => number;

  private readonly fetcher: HttpFetcher;

  constructor(now?: () => number, fetcher?: HttpFetcher) {
    this.now = now ?? ((): number => Date.now());
    this.fetcher = fetcher ?? getJsonWithStatus;
  }

  async detect(apiKey: string): Promise<ProviderDetection> {
    const snapshot = await this.requestKeyInfo(apiKey);
    const detection: ProviderDetection = {
      profile: {},
      snapshot: snapshot
    };
    return detection;
  }

  async fetch(apiKey: string): Promise<UsageSnapshot> {
    return this.requestKeyInfo(apiKey);
  }

  async fetchWithProfile(apiKey: string, profile: ProviderProfile): Promise<UsageSnapshot> {
    // Fixed LiteLLM deployment: no regions or credential kinds.
    if (profile.region !== undefined || profile.credentialKind !== undefined) {
      throw new Error('profileMismatch');
    }
    return this.requestKeyInfo(apiKey);
  }

  // Parses a /key/info response body. The /v1/models fallback only exists in
  // the fetch path because it is triggered by the HTTP status.
  parseResponse(responseBody: string, receivedAtMs: number): UsageSnapshot {
    return this.parseKeyInfo(responseBody, receivedAtMs);
  }

  private async requestKeyInfo(apiKey: string): Promise<UsageSnapshot> {
    const response: RawJsonResponse =
      await this.fetcher(BioMapCodingProvider.KEY_INFO_ENDPOINT, apiKey);
    // Only an explicit 403/404/405 falls back to the model list; every other
    // failure stays a typed error.
    if (response.code === 403 || response.code === 404 || response.code === 405) {
      return this.requestModels(apiKey);
    }
    throwForHttpStatus(response.code);
    return this.parseKeyInfo(response.body, this.now());
  }

  private parseKeyInfo(responseBody: string, receivedAtMs: number): UsageSnapshot {
    let payload: KeyInfoResponsePayload;
    try {
      payload = JSON.parse(responseBody) as KeyInfoResponsePayload;
    } catch (error) {
      throw new Error('invalidResponse');
    }

    const info = payload.info;
    if (info === undefined) {
      throw new Error('invalidResponse');
    }
    if (info.blocked === true) {
      throw new Error('providerInactive');
    }

    const spend = decimalString(info.spend);
    const maximum = decimalString(info.max_budget);
    if (maximum !== null && Number(maximum) < 0) {
      throw new Error('invalidResponse');
    }
    const currency = 'USD';

    const snapshot: UsageSnapshot = {
      provider: this.id,
      balances: [],
      providerStatus: 'active',
      receivedAtMs: receivedAtMs
    };

    let spendMoney: Money | undefined = undefined;
    if (spend !== null) {
      spendMoney = { amount: spend, currency: currency };
    }

    if (maximum !== null) {
      const spendingLimit: SpendingLimit = {
        label: 'Key budget',
        limit: { amount: maximum, currency: currency }
      };
      if (spendMoney !== undefined) {
        spendingLimit.used = spendMoney;
        const remainder = Number(maximum) - Number(spend as string);
        spendingLimit.remaining = { amount: String(remainder), currency: currency };
      }
      const duration = info.budget_duration?.trim();
      if (duration !== undefined && duration.length > 0) {
        spendingLimit.resetDescription = `Budget period: ${duration}`;
      }
      snapshot.spendingLimit = spendingLimit;
    }

    if (spendMoney !== undefined) {
      const spend: SpendSummary = { total: spendMoney };
      snapshot.spend = spend;
    }

    if (spend === null && maximum === null) {
      snapshot.metricsUnavailableReason = 'Budget metrics unavailable for this key.';
    }

    return snapshot;
  }

  private async requestModels(apiKey: string): Promise<UsageSnapshot> {
    const response: RawJsonResponse =
      await this.fetcher(BioMapCodingProvider.MODELS_ENDPOINT, apiKey);
    throwForHttpStatus(response.code);

    let payload: ModelListPayload;
    let identifiers: string[];
    try {
      payload = JSON.parse(response.body) as ModelListPayload;
      if (payload.object !== 'list' || payload.data === undefined) {
        throw new Error('invalidResponse');
      }
      identifiers = payload.data.map((model: ModelPayload): string => model.id.trim());
    } catch (error) {
      throw new Error('invalidResponse');
    }
    if (identifiers.length === 0 ||
      identifiers.some((id: string): boolean => id.length === 0)) {
      throw new Error('invalidResponse');
    }

    const snapshot: UsageSnapshot = {
      provider: this.id,
      balances: [],
      providerStatus: 'connected',
      metricsUnavailableReason:
        `${identifiers.length} models available. Budget metrics unavailable for this key.`,
      receivedAtMs: this.now()
    };
    return snapshot;
  }
}
