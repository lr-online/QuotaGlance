import { getJsonWithStatus, throwForHttpStatus } from '../network/HttpClient';
import {
  MonetaryBalance,
  MonetaryValue,
  Money,
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

interface BalanceInfoPayload {
  currency: string;
  total_balance?: string | number;
  granted_balance?: string | number;
  topped_up_balance?: string | number;
}

interface BalanceResponsePayload {
  is_available: boolean;
  balance_infos?: BalanceInfoPayload[];
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

export class DeepSeekProvider implements UsageProvider {
  static readonly ENDPOINT: string = 'https://api.deepseek.com/user/balance';

  readonly id: ProviderID = 'deepSeek';

  private readonly now: () => number;

  private readonly fetcher: HttpFetcher;

  constructor(now?: () => number, fetcher?: HttpFetcher) {
    this.now = now ?? ((): number => Date.now());
    this.fetcher = fetcher ?? getJsonWithStatus;
  }

  async fetch(apiKey: string): Promise<UsageSnapshot> {
    const response: RawJsonResponse = await this.fetcher(DeepSeekProvider.ENDPOINT, apiKey);
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
    // DeepSeek has no regions or credential kinds; anything else is a mismatch.
    if (profile.region !== undefined || profile.credentialKind !== undefined) {
      throw new Error('profileMismatch');
    }
    return this.fetch(apiKey);
  }

  parseResponse(responseBody: string, receivedAtMs: number): UsageSnapshot {
    let payload: BalanceResponsePayload;
    try {
      payload = JSON.parse(responseBody) as BalanceResponsePayload;
    } catch (error) {
      throw new Error('invalidResponse');
    }

    const infos = payload.balance_infos;
    if (!infos || infos.length === 0) {
      throw new Error('invalidResponse');
    }

    const balances: MonetaryBalance[] = infos.map((info: BalanceInfoPayload): MonetaryBalance => {
      const currency = info.currency.trim().toUpperCase();
      const total = decimalString(info.total_balance);
      if (currency.length === 0 || total === null) {
        throw new Error('invalidResponse');
      }

      const breakdown: MonetaryValue[] = [];
      const granted = decimalString(info.granted_balance);
      if (granted !== null) {
        const grantedValue: Money = { amount: granted, currency: currency };
        const grantedItem: MonetaryValue = { label: 'Granted', value: grantedValue };
        breakdown.push(grantedItem);
      }
      const toppedUp = decimalString(info.topped_up_balance);
      if (toppedUp !== null) {
        const toppedUpValue: Money = { amount: toppedUp, currency: currency };
        const toppedUpItem: MonetaryValue = { label: 'Topped up', value: toppedUpValue };
        breakdown.push(toppedUpItem);
      }

      const available: Money = { amount: total, currency: currency };
      const balance: MonetaryBalance = {
        label: 'Balance',
        available: available,
        breakdown: breakdown
      };
      return balance;
    });

    const snapshot: UsageSnapshot = {
      provider: this.id,
      balances: balances,
      providerStatus: payload.is_available ? 'active' : 'unavailable',
      receivedAtMs: receivedAtMs
    };
    return snapshot;
  }
}
