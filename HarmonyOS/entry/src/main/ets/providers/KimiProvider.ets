import { i18n } from '@kit.LocalizationKit';
import { getJsonWithStatus, throwForHttpStatus } from '../network/HttpClient';
import {
  MonetaryValue,
  Money,
  UsageSnapshot
} from './UsageSnapshot';
import {
  HttpFetcher,
  ProviderDetection,
  ProviderID,
  ProviderProfile,
  ProviderRegion,
  RawJsonResponse,
  UsageProvider
} from './UsageProvider';

interface BalanceDataPayload {
  available_balance?: string | number;
  cash_balance?: string | number;
  voucher_balance?: string | number;
}

interface BalanceResponsePayload {
  code: number;
  status: boolean;
  data?: BalanceDataPayload;
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

export class KimiProvider implements UsageProvider {
  static readonly CHINA_ENDPOINT: string = 'https://api.moonshot.cn/v1/users/me/balance';
  static readonly INTERNATIONAL_ENDPOINT: string = 'https://api.moonshot.ai/v1/users/me/balance';

  readonly id: ProviderID = 'kimi';

  private readonly preferredRegion: ProviderRegion;

  private readonly now: () => number;

  private readonly fetcher: HttpFetcher;

  constructor(preferredRegion?: ProviderRegion, now?: () => number, fetcher?: HttpFetcher) {
    this.preferredRegion = KimiProvider.supportedRegion(preferredRegion)
      ?? KimiProvider.localePreferredRegion();
    this.now = now ?? ((): number => Date.now());
    this.fetcher = fetcher ?? getJsonWithStatus;
  }

  async detect(apiKey: string): Promise<ProviderDetection> {
    try {
      const snapshot = await this.requestBalance(apiKey, this.preferredRegion);
      const detection: ProviderDetection = {
        profile: KimiProvider.profileFor(this.preferredRegion),
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
      const snapshot = await this.requestBalance(apiKey, fallbackRegion);
      const detection: ProviderDetection = {
        profile: KimiProvider.profileFor(fallbackRegion),
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
    const region = KimiProvider.supportedRegion(profile.region);
    if (profile.credentialKind !== 'standard' || region === undefined) {
      throw new Error('profileMismatch');
    }
    return this.requestBalance(apiKey, region);
  }

  // Parses a balance response body for the provider's configured region.
  parseResponse(responseBody: string, receivedAtMs: number): UsageSnapshot {
    return this.parseBalance(responseBody, this.preferredRegion, receivedAtMs);
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
    const profile: ProviderProfile = { region: region, credentialKind: 'standard' };
    return profile;
  }

  private static endpointFor(region: ProviderRegion): string {
    return region === 'china' ? KimiProvider.CHINA_ENDPOINT : KimiProvider.INTERNATIONAL_ENDPOINT;
  }

  private static currencyFor(region: ProviderRegion): string {
    return region === 'china' ? 'CNY' : 'USD';
  }

  private async requestBalance(apiKey: string, region: ProviderRegion): Promise<UsageSnapshot> {
    const response: RawJsonResponse =
      await this.fetcher(KimiProvider.endpointFor(region), apiKey);
    throwForHttpStatus(response.code);
    return this.parseBalance(response.body, region, this.now());
  }

  private parseBalance(
    responseBody: string,
    region: ProviderRegion,
    receivedAtMs: number
  ): UsageSnapshot {
    let payload: BalanceResponsePayload;
    try {
      payload = JSON.parse(responseBody) as BalanceResponsePayload;
    } catch (error) {
      throw new Error('invalidResponse');
    }

    const available = decimalString(payload.data?.available_balance);
    if (payload.code !== 0 || !payload.status || available === null) {
      throw new Error('invalidResponse');
    }

    const currency = KimiProvider.currencyFor(region);
    const breakdown: MonetaryValue[] = [];
    const cash = decimalString(payload.data?.cash_balance);
    if (cash !== null) {
      const cashValue: Money = { amount: cash, currency: currency };
      breakdown.push({ label: 'Cash', value: cashValue });
    }
    const voucher = decimalString(payload.data?.voucher_balance);
    if (voucher !== null) {
      const voucherValue: Money = { amount: voucher, currency: currency };
      breakdown.push({ label: 'Voucher', value: voucherValue });
    }

    const availableMoney: Money = { amount: available, currency: currency };
    const snapshot: UsageSnapshot = {
      provider: this.id,
      balances: [{ label: 'Balance', available: availableMoney, breakdown: breakdown }],
      providerStatus: 'active',
      receivedAtMs: receivedAtMs
    };
    return snapshot;
  }
}
