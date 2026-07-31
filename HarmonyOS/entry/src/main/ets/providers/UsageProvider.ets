// Provider framework. Mirrors Sources/QuotaGlanceCore/Providers/UsageProvider.swift
// and Sources/QuotaGlanceCore/Domain/Provider.swift.
//
// Error taxonomy: providers report failures as `Error` objects whose message is
// one of the following stable tokens (matching the Swift ProviderError cases):
//   invalidCredential          - HTTP 401/403, key rejected
//   rateLimited                - HTTP 429
//   httpStatus:<code>          - any other non-2xx HTTP status
//   invalidResponse            - malformed or incomplete provider payload
//   providerInactive           - provider reports the key/account as inactive
//   regionDetectionFailed      - regional endpoint detection failed
//   unsupportedCredential      - credential type not supported by the provider
//   profileMismatch            - stored profile does not fit this provider
//   providerUnavailable        - registry has no provider for the requested id
//   network:<detail>           - transport-level failure (BusinessError code)

import { UsageSnapshot } from './UsageSnapshot';

// Injectable HTTP transport: given a URL and API key, returns the raw status
// code and body. Production providers default to getJsonWithStatus from
// network/HttpClient.ets; tests inject stubs that serve fixture responses.
// Mirrors Swift's HTTPClient protocol injection.
export interface RawJsonResponse {
  code: number;
  body: string;
}

export type HttpFetcher = (url: string, apiKey: string) => Promise<RawJsonResponse>;

export type ProviderID = 'apiInfo' | 'deepSeek' | 'kimi' | 'openRouter' | 'miniMax' | 'bioMapCoding';

export type ProviderRegion = 'global' | 'china' | 'international';

export type ProviderCredentialKind = 'standard' | 'management' | 'tokenPlan';

export interface ProviderProfile {
  region?: ProviderRegion;
  credentialKind?: ProviderCredentialKind;
}

export interface ProviderDetection {
  profile: ProviderProfile;
  snapshot: UsageSnapshot;
}

export interface UsageProvider {
  readonly id: ProviderID;

  fetch(apiKey: string): Promise<UsageSnapshot>;

  detect(apiKey: string): Promise<ProviderDetection>;

  fetchWithProfile(apiKey: string, profile: ProviderProfile): Promise<UsageSnapshot>;

  // Parses a raw provider response body into a snapshot without any network
  // access. Contract fixtures on both platforms exercise this path.
  parseResponse(responseBody: string, receivedAtMs: number): UsageSnapshot;
}

export const ALL_PROVIDER_IDS: ProviderID[] = [
  'apiInfo',
  'deepSeek',
  'kimi',
  'openRouter',
  'miniMax',
  'bioMapCoding'
];

const PROVIDER_DISPLAY_NAMES: Record<ProviderID, string> = {
  'apiInfo': 'API Info',
  'deepSeek': 'DeepSeek',
  'kimi': 'Kimi',
  'openRouter': 'OpenRouter',
  'miniMax': 'MiniMax',
  'bioMapCoding': 'BioMap Coding'
};

export function providerDisplayName(id: ProviderID): string {
  return PROVIDER_DISPLAY_NAMES[id];
}

export class ProviderRegistry {
  private readonly providers: Map<ProviderID, UsageProvider> = new Map();

  constructor(providers: UsageProvider[]) {
    for (const provider of providers) {
      this.providers.set(provider.id, provider);
    }
  }

  provider(id: ProviderID): UsageProvider {
    const provider = this.providers.get(id);
    if (provider === undefined) {
      throw new Error('providerUnavailable');
    }
    return provider;
  }

  all(): UsageProvider[] {
    const result: UsageProvider[] = [];
    this.providers.forEach((provider: UsageProvider) => {
      result.push(provider);
    });
    return result;
  }
}
