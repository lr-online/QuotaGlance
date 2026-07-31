import { getJsonWithStatus, throwForHttpStatus } from '../network/HttpClient';
import {
  DailyUsage,
  ModelUsage,
  Money,
  SpendingLimit,
  SpendSummary,
  UsageCounters,
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

interface QuotaPayload {
  limit?: string | number;
  remaining?: string | number;
  used?: string | number;
}

interface CountersPayload {
  actual_cost?: string | number;
  requests?: number;
  input_tokens?: number;
  output_tokens?: number;
  cache_read_tokens?: number;
  cache_creation_tokens?: number;
  total_tokens?: number;
}

interface UsagePayload {
  today?: CountersPayload;
  total?: CountersPayload;
}

interface DailyPayload {
  date: string;
  actual_cost?: string | number;
  requests?: number;
  total_tokens?: number;
}

interface ModelPayload {
  model: string;
  actual_cost?: string | number;
  requests?: number;
  total_tokens?: number;
}

interface UsageResponsePayload {
  isValid: boolean;
  status?: string;
  unit?: string;
  remaining?: string | number;
  quota?: QuotaPayload;
  usage?: UsagePayload;
  daily_usage?: DailyPayload[];
  model_stats?: ModelPayload[];
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

function buildCounters(raw: CountersPayload, currency: string): UsageCounters {
  const counters: UsageCounters = {};
  const cost = decimalString(raw.actual_cost);
  if (cost !== null) {
    const actualCost: Money = { amount: cost, currency: currency };
    counters.actualCost = actualCost;
  }
  if (raw.requests !== undefined) {
    counters.requests = raw.requests;
  }
  if (raw.input_tokens !== undefined) {
    counters.inputTokens = raw.input_tokens;
  }
  if (raw.output_tokens !== undefined) {
    counters.outputTokens = raw.output_tokens;
  }
  if (raw.cache_read_tokens !== undefined) {
    counters.cacheReadTokens = raw.cache_read_tokens;
  }
  if (raw.cache_creation_tokens !== undefined) {
    counters.cacheCreationTokens = raw.cache_creation_tokens;
  }
  if (raw.total_tokens !== undefined) {
    counters.totalTokens = raw.total_tokens;
  }
  return counters;
}

export class APIInfoProvider implements UsageProvider {
  static readonly ENDPOINT: string = 'https://www.api-info.net/v1/usage';

  readonly id: ProviderID = 'apiInfo';

  private readonly now: () => number;

  private readonly fetcher: HttpFetcher;

  constructor(now?: () => number, fetcher?: HttpFetcher) {
    this.now = now ?? ((): number => Date.now());
    this.fetcher = fetcher ?? getJsonWithStatus;
  }

  async fetch(apiKey: string): Promise<UsageSnapshot> {
    const response: RawJsonResponse = await this.fetcher(APIInfoProvider.ENDPOINT, apiKey);
    throwForHttpStatus(response.code);
    return this.parseResponse(response.body, this.now());
  }

  async detect(apiKey: string): Promise<ProviderDetection> {
    const snapshot = await this.fetch(apiKey);
    const detection: ProviderDetection = {
      profile: {},
      snapshot: snapshot
    };
    return detection;
  }

  async fetchWithProfile(apiKey: string, profile: ProviderProfile): Promise<UsageSnapshot> {
    // API Info has no regions or credential kinds; anything else is a mismatch.
    if (profile.region !== undefined || profile.credentialKind !== undefined) {
      throw new Error('profileMismatch');
    }
    return this.fetch(apiKey);
  }

  parseResponse(responseBody: string, receivedAtMs: number): UsageSnapshot {
    let payload: UsageResponsePayload;
    try {
      payload = JSON.parse(responseBody) as UsageResponsePayload;
    } catch (error) {
      throw new Error('invalidResponse');
    }

    if (!payload.isValid) {
      throw new Error('providerInactive');
    }
    const remaining = decimalString(payload.remaining);
    if (remaining === null) {
      throw new Error('invalidResponse');
    }
    const currency = payload.unit;
    if (currency === undefined || currency.length === 0) {
      throw new Error('invalidResponse');
    }

    const available: Money = { amount: remaining, currency: currency };

    const snapshot: UsageSnapshot = {
      provider: this.id,
      balances: [{ label: 'Balance', available: available, breakdown: [] }],
      receivedAtMs: receivedAtMs
    };

    if (payload.quota !== undefined) {
      const limit = decimalString(payload.quota.limit);
      const used = decimalString(payload.quota.used);
      const quotaRemaining = decimalString(payload.quota.remaining);
      if (limit !== null || used !== null || quotaRemaining !== null) {
        const spendingLimit: SpendingLimit = { label: 'Quota' };
        if (used !== null) {
          spendingLimit.used = { amount: used, currency: currency };
        }
        if (limit !== null) {
          spendingLimit.limit = { amount: limit, currency: currency };
        }
        if (quotaRemaining !== null) {
          spendingLimit.remaining = { amount: quotaRemaining, currency: currency };
        }
        snapshot.spendingLimit = spendingLimit;
      }
    }

    let today: UsageCounters | undefined = undefined;
    let total: UsageCounters | undefined = undefined;
    if (payload.usage !== undefined) {
      if (payload.usage.today !== undefined) {
        today = buildCounters(payload.usage.today, currency);
        snapshot.today = today;
      }
      if (payload.usage.total !== undefined) {
        total = buildCounters(payload.usage.total, currency);
        snapshot.total = total;
      }
    }

    const spend: SpendSummary = {};
    if (today?.actualCost !== undefined) {
      spend.today = today.actualCost;
    }
    if (total?.actualCost !== undefined) {
      spend.total = total.actualCost;
    }
    if (spend.today !== undefined || spend.total !== undefined) {
      snapshot.spend = spend;
    }

    if (payload.daily_usage !== undefined) {
      const dailyUsage: DailyUsage[] = [];
      for (const daily of payload.daily_usage) {
        // Days without a cost figure are skipped, matching the Swift compactMap.
        const dailyCost = decimalString(daily.actual_cost);
        if (dailyCost === null) {
          continue;
        }
        const entry: DailyUsage = {
          date: daily.date,
          actualCost: { amount: dailyCost, currency: currency }
        };
        if (daily.requests !== undefined) {
          entry.requests = daily.requests;
        }
        if (daily.total_tokens !== undefined) {
          entry.totalTokens = daily.total_tokens;
        }
        dailyUsage.push(entry);
      }
      snapshot.dailyUsage = dailyUsage;
    }

    if (payload.model_stats !== undefined) {
      const modelUsage: ModelUsage[] = payload.model_stats.map((model: ModelPayload): ModelUsage => {
        const entry: ModelUsage = { model: model.model };
        const modelCost = decimalString(model.actual_cost);
        if (modelCost !== null) {
          entry.actualCost = { amount: modelCost, currency: currency };
        }
        if (model.requests !== undefined) {
          entry.requests = model.requests;
        }
        if (model.total_tokens !== undefined) {
          entry.totalTokens = model.total_tokens;
        }
        return entry;
      });
      snapshot.modelUsage = modelUsage;
    }

    if (payload.status !== undefined) {
      snapshot.providerStatus = payload.status;
    }

    return snapshot;
  }
}
