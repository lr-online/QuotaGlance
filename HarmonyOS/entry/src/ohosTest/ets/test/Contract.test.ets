import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { util } from '@kit.ArkTS';
import { SpecDrivenProvider } from '../../../main/ets/providers/SpecDrivenProvider';
import {
  HttpFetcher,
  ProviderID,
  ProviderProfile,
  RawJsonResponse,
  UsageProvider
} from '../../../main/ets/providers/UsageProvider';
import {
  DailyUsage,
  ModelUsage,
  Money,
  MonetaryBalance,
  QuotaWindow,
  SpendingLimit,
  SpendSummary,
  UsageCounters,
  UsageSnapshot
} from '../../../main/ets/providers/UsageSnapshot';

// Expected-fixture schema: each file pins a subset of UsageSnapshot fields.
// Only fields present in the file are asserted. See Contracts/README.md.
interface ExpectedMoney {
  amount: string;
  currency: string;
}

interface ExpectedMonetaryValue {
  label: string;
  value: ExpectedMoney;
}

interface ExpectedBalance {
  label: string;
  available: ExpectedMoney;
  breakdown: ExpectedMonetaryValue[];
}

interface ExpectedSpendingLimit {
  label: string;
  used?: ExpectedMoney;
  limit?: ExpectedMoney;
  remaining?: ExpectedMoney;
  resetDescription?: string;
}

interface ExpectedSpendSummary {
  today?: ExpectedMoney;
  week?: ExpectedMoney;
  month?: ExpectedMoney;
  total?: ExpectedMoney;
}

interface ExpectedUsageCounters {
  actualCost?: ExpectedMoney;
  requests?: number;
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheCreationTokens?: number;
  totalTokens?: number;
}

interface ExpectedDailyUsage {
  date: string;
  actualCost?: ExpectedMoney;
  requests?: number;
  totalTokens?: number;
}

interface ExpectedModelUsage {
  model: string;
  actualCost?: ExpectedMoney;
  requests?: number;
  totalTokens?: number;
}

interface ExpectedQuotaWindow {
  label: string;
  used?: number;
  limit?: number;
  remaining?: number;
  unit: string;
  resetsAtMs?: number;
}

interface ExpectedSnapshot {
  balances?: ExpectedBalance[];
  spendingLimit?: ExpectedSpendingLimit;
  spend?: ExpectedSpendSummary;
  quotaWindows?: ExpectedQuotaWindow[];
  today?: ExpectedUsageCounters;
  total?: ExpectedUsageCounters;
  dailyUsage?: ExpectedDailyUsage[];
  modelUsage?: ExpectedModelUsage[];
  providerStatus?: string;
  metricsUnavailableReason?: string;
}

// Requests-fixture schema: pins the exact request sequence a fetch issues.
// Header values are assertion patterns ("Bearer" = scheme assertion). Both
// Swift and ArkTS harnesses assert count, order, method, URL, and header
// patterns. See Contracts/README.md.
interface ExpectedRequest {
  method: string;
  url: string;
  headers: Record<string, string>;
}

// One stubbed HTTP step: the fixture file served when the provider requests
// this URL, with this status code (default 200). Steps are looked up by URL,
// so a provider may hit its endpoints in any order.
interface StubStep {
  url: string;
  file: string;
  code?: number;
}

interface ContractCase {
  provider: ProviderID;
  name: string;
  profile: ProviderProfile;
  steps: StubStep[];
}

// One entry per synced contract case. Fixture files live under
// contracts/<lowercased provider id>/<name>-expected.json plus the step files.
// Endpoint URLs are pinned by the <case>-requests.json fixtures asserted
// below; the profile is the one the fetch runs under (the same profile
// detect would produce for the case).
const CONTRACT_CASES: ContractCase[] = [
  {
    provider: 'deepSeek',
    name: 'balance',
    profile: { region: 'global', credentialKind: 'standard' },
    steps: [{ url: 'https://api.deepseek.com/user/balance', file: 'balance-response.json' }]
  },
  {
    provider: 'apiInfo',
    name: 'usage',
    profile: { region: 'global', credentialKind: 'standard' },
    steps: [{ url: 'https://www.api-info.net/v1/usage', file: 'usage-response.json' }]
  },
  {
    provider: 'kimi',
    name: 'china',
    profile: { region: 'china', credentialKind: 'standard' },
    steps: [{ url: 'https://api.moonshot.cn/v1/users/me/balance', file: 'china-response.json' }]
  },
  {
    provider: 'openRouter',
    name: 'key-standard',
    profile: { region: 'global', credentialKind: 'standard' },
    steps: [{ url: 'https://openrouter.ai/api/v1/key', file: 'key-standard-response.json' }]
  },
  {
    provider: 'openRouter',
    name: 'key-management',
    profile: { region: 'global', credentialKind: 'management' },
    steps: [
      { url: 'https://openrouter.ai/api/v1/key', file: 'key-management-response.json' },
      { url: 'https://openrouter.ai/api/v1/credits', file: 'key-management-response2.json' }
    ]
  },
  {
    provider: 'miniMax',
    name: 'remains',
    profile: { region: 'china', credentialKind: 'tokenPlan' },
    steps: [{ url: 'https://www.minimaxi.com/v1/token_plan/remains', file: 'remains-response.json' }]
  },
  {
    provider: 'bioMapCoding',
    name: 'budget',
    profile: { region: 'global', credentialKind: 'standard' },
    steps: [{ url: 'https://coding.biomap-int.com/key/info', file: 'budget-response.json' }]
  },
  {
    provider: 'bioMapCoding',
    name: 'fallback',
    profile: { region: 'global', credentialKind: 'standard' },
    steps: [
      { url: 'https://coding.biomap-int.com/key/info', file: 'fallback-response.json', code: 403 },
      { url: 'https://coding.biomap-int.com/v1/models', file: 'fallback-response2.json' }
    ]
  }
];

// Builds the provider under test: the spec synced into
// contracts/<lowercased id>/spec.json, a pinned clock (receivedAtMs = 0) and
// the stubbed transport.
function createTestProvider(contractCase: ContractCase, fetcher: HttpFetcher): UsageProvider {
  const dir = contractCase.provider.toLowerCase();
  const specJson = readRawFileString(`contracts/${dir}/spec.json`);
  const now = (): number => 0;
  return new SpecDrivenProvider(specJson, { now: now, fetcher: fetcher });
}

function readRawFileString(path: string): string {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(path);
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

function assertMoney(actual: Money | undefined, expected: ExpectedMoney): void {
  expect(actual !== undefined).assertTrue();
  const money = actual as Money;
  expect(money.amount).assertEqual(expected.amount);
  expect(money.currency).assertEqual(expected.currency);
}

function assertOptionalMoney(actual: Money | undefined, expected: ExpectedMoney | undefined): void {
  if (expected === undefined) {
    return;
  }
  assertMoney(actual, expected);
}

function assertBalances(actual: MonetaryBalance[] | undefined, expected: ExpectedBalance[]): void {
  expect(actual !== undefined).assertTrue();
  const balances = actual as MonetaryBalance[];
  expect(balances.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    const actualBalance = balances[i];
    const expectedBalance = expected[i];
    expect(actualBalance.label).assertEqual(expectedBalance.label);
    assertMoney(actualBalance.available, expectedBalance.available);
    expect(actualBalance.breakdown.length).assertEqual(expectedBalance.breakdown.length);
    for (let j = 0; j < expectedBalance.breakdown.length; j++) {
      const actualItem = actualBalance.breakdown[j];
      const expectedItem = expectedBalance.breakdown[j];
      expect(actualItem.label).assertEqual(expectedItem.label);
      assertMoney(actualItem.value, expectedItem.value);
    }
  }
}

function assertSpendingLimit(actual: SpendingLimit | undefined, expected: ExpectedSpendingLimit): void {
  expect(actual !== undefined).assertTrue();
  const limit = actual as SpendingLimit;
  expect(limit.label).assertEqual(expected.label);
  assertOptionalMoney(limit.used, expected.used);
  assertOptionalMoney(limit.limit, expected.limit);
  assertOptionalMoney(limit.remaining, expected.remaining);
  if (expected.resetDescription !== undefined) {
    expect(limit.resetDescription).assertEqual(expected.resetDescription);
  }
}

function assertSpendSummary(actual: SpendSummary | undefined, expected: ExpectedSpendSummary): void {
  expect(actual !== undefined).assertTrue();
  const spend = actual as SpendSummary;
  assertOptionalMoney(spend.today, expected.today);
  assertOptionalMoney(spend.week, expected.week);
  assertOptionalMoney(spend.month, expected.month);
  assertOptionalMoney(spend.total, expected.total);
}

function assertCounters(actual: UsageCounters | undefined, expected: ExpectedUsageCounters): void {
  expect(actual !== undefined).assertTrue();
  const counters = actual as UsageCounters;
  assertOptionalMoney(counters.actualCost, expected.actualCost);
  if (expected.requests !== undefined) {
    expect(counters.requests).assertEqual(expected.requests);
  }
  if (expected.inputTokens !== undefined) {
    expect(counters.inputTokens).assertEqual(expected.inputTokens);
  }
  if (expected.outputTokens !== undefined) {
    expect(counters.outputTokens).assertEqual(expected.outputTokens);
  }
  if (expected.cacheReadTokens !== undefined) {
    expect(counters.cacheReadTokens).assertEqual(expected.cacheReadTokens);
  }
  if (expected.cacheCreationTokens !== undefined) {
    expect(counters.cacheCreationTokens).assertEqual(expected.cacheCreationTokens);
  }
  if (expected.totalTokens !== undefined) {
    expect(counters.totalTokens).assertEqual(expected.totalTokens);
  }
}

function assertQuotaWindows(actual: QuotaWindow[] | undefined, expected: ExpectedQuotaWindow[]): void {
  expect(actual !== undefined).assertTrue();
  const windows = actual as QuotaWindow[];
  expect(windows.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    const actualWindow = windows[i];
    const expectedWindow = expected[i];
    expect(actualWindow.label).assertEqual(expectedWindow.label);
    expect(actualWindow.unit).assertEqual(expectedWindow.unit);
    if (expectedWindow.used !== undefined) {
      expect(actualWindow.used).assertEqual(expectedWindow.used);
    }
    if (expectedWindow.limit !== undefined) {
      expect(actualWindow.limit).assertEqual(expectedWindow.limit);
    }
    if (expectedWindow.remaining !== undefined) {
      expect(actualWindow.remaining).assertEqual(expectedWindow.remaining);
    }
    if (expectedWindow.resetsAtMs !== undefined) {
      expect(actualWindow.resetsAtMs).assertEqual(expectedWindow.resetsAtMs);
    }
  }
}

function assertDailyUsage(actual: DailyUsage[] | undefined, expected: ExpectedDailyUsage[]): void {
  expect(actual !== undefined).assertTrue();
  const daily = actual as DailyUsage[];
  expect(daily.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    const actualEntry = daily[i];
    const expectedEntry = expected[i];
    expect(actualEntry.date).assertEqual(expectedEntry.date);
    assertOptionalMoney(actualEntry.actualCost, expectedEntry.actualCost);
    if (expectedEntry.requests !== undefined) {
      expect(actualEntry.requests).assertEqual(expectedEntry.requests);
    }
    if (expectedEntry.totalTokens !== undefined) {
      expect(actualEntry.totalTokens).assertEqual(expectedEntry.totalTokens);
    }
  }
}

function assertModelUsage(actual: ModelUsage[] | undefined, expected: ExpectedModelUsage[]): void {
  expect(actual !== undefined).assertTrue();
  const models = actual as ModelUsage[];
  expect(models.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    const actualEntry = models[i];
    const expectedEntry = expected[i];
    expect(actualEntry.model).assertEqual(expectedEntry.model);
    assertOptionalMoney(actualEntry.actualCost, expectedEntry.actualCost);
    if (expectedEntry.requests !== undefined) {
      expect(actualEntry.requests).assertEqual(expectedEntry.requests);
    }
    if (expectedEntry.totalTokens !== undefined) {
      expect(actualEntry.totalTokens).assertEqual(expectedEntry.totalTokens);
    }
  }
}

function assertSnapshot(snapshot: UsageSnapshot, expected: ExpectedSnapshot): void {
  if (expected.balances !== undefined) {
    assertBalances(snapshot.balances, expected.balances);
  }
  if (expected.spendingLimit !== undefined) {
    assertSpendingLimit(snapshot.spendingLimit, expected.spendingLimit);
  }
  if (expected.spend !== undefined) {
    assertSpendSummary(snapshot.spend, expected.spend);
  }
  if (expected.quotaWindows !== undefined) {
    assertQuotaWindows(snapshot.quotaWindows, expected.quotaWindows);
  }
  if (expected.today !== undefined) {
    assertCounters(snapshot.today, expected.today);
  }
  if (expected.total !== undefined) {
    assertCounters(snapshot.total, expected.total);
  }
  if (expected.dailyUsage !== undefined) {
    assertDailyUsage(snapshot.dailyUsage, expected.dailyUsage);
  }
  if (expected.modelUsage !== undefined) {
    assertModelUsage(snapshot.modelUsage, expected.modelUsage);
  }
  if (expected.providerStatus !== undefined) {
    expect(snapshot.providerStatus).assertEqual(expected.providerStatus);
  }
  if (expected.metricsUnavailableReason !== undefined) {
    expect(snapshot.metricsUnavailableReason).assertEqual(expected.metricsUnavailableReason);
  }
}

// Returns undefined when the case has no <case>-requests.json fixture yet.
function loadExpectedRequests(dir: string, name: string): ExpectedRequest[] | undefined {
  try {
    return JSON.parse(
      readRawFileString(`contracts/${dir}/${name}-requests.json`)
    ) as ExpectedRequest[];
  } catch (error) {
    return undefined;
  }
}

interface RecordedRequest {
  method: string;
  url: string;
  headers: Record<string, string>;
}

// Asserts the recorded request sequence against a requests fixture.
// Semantics match Swift expectRequests in ContractTests.swift:
// count/order/method/url exact; header values are patterns ("Bearer" =
// scheme prefix; any other string = exact match). Headers absent from
// the fixture are unchecked. Missing fixture => no-op.
function assertRequests(
  actual: RecordedRequest[],
  expected: ExpectedRequest[] | undefined
): void {
  if (expected === undefined) {
    return;
  }
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(actual[i].method).assertEqual(expected[i].method);
    expect(actual[i].url).assertEqual(expected[i].url);
    const patterns = expected[i].headers;
    const keys = Object.keys(patterns);
    for (let k = 0; k < keys.length; k++) {
      const field = keys[k];
      const pattern = patterns[field];
      const value = actual[i].headers[field];
      if (pattern === 'Bearer') {
        expect(value !== undefined && value.indexOf('Bearer ') === 0).assertTrue();
      } else {
        expect(value).assertEqual(pattern);
      }
    }
  }
}

export default function contractTest() {
  describe('ContractTest', () => {
    for (const contractCase of CONTRACT_CASES) {
      it(`matches_${contractCase.provider}_${contractCase.name}`, 0, async () => {
        const dir = contractCase.provider.toLowerCase();
        const expected = JSON.parse(
          readRawFileString(`contracts/${dir}/${contractCase.name}-expected.json`)
        ) as ExpectedSnapshot;

        const stepsByUrl: Map<string, StubStep> = new Map();
        for (const step of contractCase.steps) {
          stepsByUrl.set(step.url, step);
        }
        const recorded: RecordedRequest[] = [];
        const fetcher: HttpFetcher =
          (url: string, headers: Record<string, string>): Promise<RawJsonResponse> => {
            recorded.push({ method: 'GET', url: url, headers: headers });
            const step = stepsByUrl.get(url);
            if (step === undefined) {
              return Promise.reject(new Error(`unstubbedUrl:${url}`));
            }
            const response: RawJsonResponse = {
              code: step.code ?? 200,
              body: readRawFileString(`contracts/${dir}/${step.file}`)
            };
            return Promise.resolve(response);
          };

        const provider = createTestProvider(contractCase, fetcher);
        const snapshot = await provider.fetch('redacted-test-key', contractCase.profile);

        assertSnapshot(snapshot, expected);
        assertRequests(recorded, loadExpectedRequests(dir, contractCase.name));
      });
    }

    it('deepSeekRejectsEmptyBalanceInfos', 0, async () => {
      const specJson = readRawFileString('contracts/deepseek/spec.json');
      const fetcher: HttpFetcher =
        (url: string, headers: Record<string, string>): Promise<RawJsonResponse> => {
          const response: RawJsonResponse = {
            code: 200,
            body: '{"is_available":true,"balance_infos":[]}'
          };
          return Promise.resolve(response);
        };
      const provider: UsageProvider =
        new SpecDrivenProvider(specJson, { now: (): number => 0, fetcher: fetcher });
      let message = '';
      try {
        await provider.fetch('redacted-test-key', { region: 'global', credentialKind: 'standard' });
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('invalidResponse');
    });
  });
}
