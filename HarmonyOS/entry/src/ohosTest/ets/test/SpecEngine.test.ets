import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { util } from '@kit.ArkTS';
import { SpecDrivenProvider, SpecDrivenProviderOptions } from '../../../main/ets/providers/SpecDrivenProvider';
import {
  decimalFromNumber,
  decimalFromString,
  decimalSubtract
} from '../../../main/ets/providers/SpecEngine';
import {
  HttpFetcher,
  ProviderProfile,
  ProviderRegion,
  RawJsonResponse
} from '../../../main/ets/providers/UsageProvider';

// Engine semantics unit tests: the closed value/condition sets, decimal
// canonicalization, status-branch ordering, gotoStep/onDemand,
// credentialKindDetection enforcement, regionFallback, profile validation,
// credential preprocessing, and spec load validation. Crafted minimal specs
// drive SpecDrivenProvider end to end; the real contract specs cover the
// provider-specific flows. Ports Tests/QuotaGlanceCoreTests/SpecEngineTests.swift.

interface StubResponse {
  body: string;
  code: number;
}

// URL-keyed stub transport recording every request (url + headers).
class StubTransport {
  readonly responses: Map<string, StubResponse> = new Map();
  readonly requests: string[] = [];
  readonly requestHeaders: Record<string, string>[] = [];

  constructor(entries: Record<string, StubResponse>) {
    for (const url of Object.keys(entries)) {
      this.responses.set(url, entries[url]);
    }
  }

  fetcher(): HttpFetcher {
    return (url: string, headers: Record<string, string>): Promise<RawJsonResponse> => {
      this.requests.push(url);
      this.requestHeaders.push(headers);
      const stub = this.responses.get(url);
      if (stub === undefined) {
        return Promise.reject(new Error(`unstubbedUrl:${url}`));
      }
      const response: RawJsonResponse = { code: stub.code, body: stub.body };
      return Promise.resolve(response);
    };
  }
}

function readRawFileString(path: string): string {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(path);
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

const GLOBAL_STANDARD: ProviderProfile = { region: 'global', credentialKind: 'standard' };

function makeEngineSpecData(
  steps: string,
  specVersion: number = 1,
  credential: string = '{"trimWhitespace": false}',
  supported: string = '[{"region":"global","credentialKind":"standard"}]',
  detect: string = '{"strategy":"fixedProfile","profile":{"region":"global","credentialKind":"standard"}}'
): string {
  return `{
    "specVersion": ${specVersion},
    "id": "deepSeek",
    "displayName": "Engine Test",
    "descriptor": {
      "supportsLowBalanceThreshold": { "always": true },
      "profileDescription": {
        "undetected": { "l10nKey": "notDetected" },
        "detected": { "style": "regionCredential" }
      }
    },
    "credential": ${credential},
    "profiles": { "supported": ${supported} },
    "detect": ${detect},
    "fetch": { "steps": ${steps} }
  }`;
}

function makeStep(
  name: string = 'main',
  onDemand: boolean = false,
  url: string = '"https://engine.test/endpoint"',
  onStatus: string = '{"match":"2xx","action":"parse"},{"match":"default","action":"error","error":"httpStatus"}',
  parse: string = '{"checks":[],"snapshot":{}}'
): string {
  return `{
    "name": "${name}",
    "onDemand": ${onDemand},
    "request": {
      "method": "GET",
      "url": ${url},
      "headers": [
        { "name": "Authorization", "value": "Bearer \${apiKey}" },
        { "name": "Accept", "value": "application/json" }
      ]
    },
    "onStatus": [${onStatus}],
    "parse": ${parse}
  }`;
}

function makeEngine(specJson: string, transport: StubTransport, preferredRegion?: ProviderRegion): SpecDrivenProvider {
  const options: SpecDrivenProviderOptions = { now: (): number => 123000, fetcher: transport.fetcher() };
  if (preferredRegion !== undefined) {
    options.preferredRegion = preferredRegion;
  }
  return new SpecDrivenProvider(specJson, options);
}

function contractSpecEngine(provider: string, transport: StubTransport, preferredRegion?: ProviderRegion): SpecDrivenProvider {
  return makeEngine(readRawFileString(`contracts/${provider}/spec.json`), transport, preferredRegion);
}

const BALANCE_SNAPSHOT_PARSE: string =
  '{"checks":[],"snapshot":{"balances":{"fixed":[' +
  '{"label":{"literal":"Balance"},"available":{"money":{' +
  '"amount":{"path":"amount","type":"decimal"},"currency":{"literal":"USD"}}}}]}}}';

export default function specEngineTest() {
  describe('SpecEngineTest', () => {
    // MARK: Value semantics

    it('decimalAcceptsNumbersAndNumericStrings', 0, async () => {
      const specJson = makeEngineSpecData(`[${makeStep('main', false, '"https://engine.test/endpoint"', undefined, BALANCE_SNAPSHOT_PARSE)}]`);
      const stringTransport = new StubTransport({
        'https://engine.test/endpoint': { body: '{"amount": " 10.00 "}', code: 200 }
      });
      const stringSnapshot = await makeEngine(specJson, stringTransport).fetch('key', GLOBAL_STANDARD);
      // String source: preserved verbatim after trimming.
      expect(stringSnapshot.balances[0].available.amount).assertEqual('10.00');

      const numberTransport = new StubTransport({
        'https://engine.test/endpoint': { body: '{"amount": 6655.90}', code: 200 }
      });
      const numberSnapshot = await makeEngine(specJson, numberTransport).fetch('key', GLOBAL_STANDARD);
      // Number source: shortest round-trip rendering.
      expect(numberSnapshot.balances[0].available.amount).assertEqual('6655.9');
    });

    it('unparseableDecimalResolvesAbsent', 0, async () => {
      const specJson = makeEngineSpecData(`[${makeStep('main', false, '"https://engine.test/endpoint"', undefined, BALANCE_SNAPSHOT_PARSE)}]`);
      const transport = new StubTransport({
        'https://engine.test/endpoint': { body: '{"amount": "not-a-number"}', code: 200 }
      });
      let message = '';
      try {
        await makeEngine(specJson, transport).fetch('key', GLOBAL_STANDARD);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('invalidResponse');
    });

    it('decimalCanonicalForms', 0, () => {
      // Rule 1: string source preserved verbatim after trimming.
      expect(decimalFromString('  10.00  ')?.canonical).assertEqual('10.00');
      // Rule 2: number source shortest round-trip rendering.
      expect(decimalFromNumber(6655.90)?.canonical).assertEqual('6655.9');
      expect(decimalFromNumber(10)?.canonical).assertEqual('10');
      // Rule 3: subtract renders the exact result canonically.
      expect(decimalSubtract(decimalFromNumber(25), decimalFromString('3.25'))?.canonical)
        .assertEqual('21.75');
      expect(decimalSubtract(decimalFromString('20.5'), decimalFromString('8.25'))?.canonical)
        .assertEqual('12.25');
      // Float-noise cases must still render exactly.
      expect(decimalSubtract(decimalFromString('0.3'), decimalFromString('0.1'))?.canonical)
        .assertEqual('0.2');
      expect(decimalSubtract(decimalFromNumber(1), null)).assertEqual(null);
    });

    it('subtractPropagatesNull', 0, async () => {
      const parse = '{"checks":[],"values":{"currency":{"literal":"USD"}},"snapshot":{"spend":{"object":{' +
        '"total":{"money":{"amount":{"op":"subtract","a":{"path":"total","type":"decimal"},' +
        '"b":{"path":"used","type":"decimal"}},"currency":{"value":"currency"}}}}}}}';
      const specJson = makeEngineSpecData(`[${makeStep('main', false, '"https://engine.test/endpoint"', undefined, parse)}]`);
      const completeTransport = new StubTransport({
        'https://engine.test/endpoint': { body: '{"total": 25, "used": "3.25"}', code: 200 }
      });
      const complete = await makeEngine(specJson, completeTransport).fetch('key', GLOBAL_STANDARD);
      expect(complete.spend?.total?.amount).assertEqual('21.75');

      const missingTransport = new StubTransport({
        'https://engine.test/endpoint': { body: '{"total": 25}', code: 200 }
      });
      const missing = await makeEngine(specJson, missingTransport).fetch('key', GLOBAL_STANDARD);
      expect(missing.spend?.total === undefined).assertTrue();
    });

    it('missingKeyAndExplicitNullResolveAbsent', 0, async () => {
      const parse = '{"checks":[],"snapshot":{"metricsUnavailableReason":{' +
        '"when":{"path":"spend","exists":false},"value":{"literal":"none"}}}}';
      const specJson = makeEngineSpecData(`[${makeStep('main', false, '"https://engine.test/endpoint"', undefined, parse)}]`);
      for (const body of ['{}', '{"spend": null}']) {
        const transport = new StubTransport({
          'https://engine.test/endpoint': { body: body, code: 200 }
        });
        const snapshot = await makeEngine(specJson, transport).fetch('key', GLOBAL_STANDARD);
        expect(snapshot.metricsUnavailableReason).assertEqual('none');
      }
      const transport = new StubTransport({
        'https://engine.test/endpoint': { body: '{"spend": 1}', code: 200 }
      });
      const snapshot = await makeEngine(specJson, transport).fetch('key', GLOBAL_STANDARD);
      expect(snapshot.metricsUnavailableReason === undefined).assertTrue();
    });

    it('strictCheckRejectsPresentUnparseableButAllowsAbsent', 0, async () => {
      // strict: the value may be absent, but when present it must parse as
      // the declared type (Contracts/README.md checks; BioMap Coding's
      // info.spend).
      const parse = '{"checks":[{"path":"spend","type":"decimal","strict":true}],' +
        '"snapshot":{"providerStatus":{"literal":"ok"}}}';
      const specJson = makeEngineSpecData(`[${makeStep('main', false, '"https://engine.test/endpoint"', undefined, parse)}]`);
      const badTransport = new StubTransport({
        'https://engine.test/endpoint': { body: '{"spend":"abc"}', code: 200 }
      });
      let message = '';
      try {
        await makeEngine(specJson, badTransport).fetch('key', GLOBAL_STANDARD);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('invalidResponse');

      const absentTransport = new StubTransport({
        'https://engine.test/endpoint': { body: '{}', code: 200 }
      });
      const snapshot = await makeEngine(specJson, absentTransport).fetch('key', GLOBAL_STANDARD);
      expect(snapshot.providerStatus).assertEqual('ok');
    });

    // MARK: Step orchestration

    it('onStatusIsFirstMatch', 0, async () => {
      const onStatus = '{"match":"2xx","action":"parse"},' +
        '{"match":[403],"action":"gotoStep","step":"fallback"},' +
        '{"match":[401,403],"action":"error","error":"invalidCredential"},' +
        '{"match":"default","action":"error","error":"httpStatus"}';
      const specJson = makeEngineSpecData('[' +
        makeStep('primary', false, '"https://engine.test/primary"', onStatus,
          '{"checks":[],"snapshot":{"providerStatus":{"literal":"primary"}}}') + ',' +
        makeStep('fallback', true, '"https://engine.test/fallback"', undefined,
          '{"checks":[],"snapshot":{"providerStatus":{"literal":"fallback"}}}') +
        ']');
      const gotoTransport = new StubTransport({
        'https://engine.test/primary': { body: '{}', code: 403 },
        'https://engine.test/fallback': { body: '{}', code: 200 }
      });
      // A 403 rule ahead of 401 wins the branch.
      const snapshot = await makeEngine(specJson, gotoTransport).fetch('key', GLOBAL_STANDARD);
      expect(snapshot.providerStatus).assertEqual('fallback');
      expect(gotoTransport.requests.length).assertEqual(2);

      const errorTransport = new StubTransport({
        'https://engine.test/primary': { body: '{}', code: 401 }
      });
      let message = '';
      try {
        await makeEngine(specJson, errorTransport).fetch('key', GLOBAL_STANDARD);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('invalidCredential');
      expect(errorTransport.requests.length).assertEqual(1);
    });

    it('onDemandStepNeverRunsInListedOrder', 0, async () => {
      const specJson = makeEngineSpecData('[' +
        makeStep('primary', false, '"https://engine.test/primary"', undefined,
          '{"checks":[],"snapshot":{"providerStatus":{"literal":"primary"}}}') + ',' +
        makeStep('fallback', true, '"https://engine.test/fallback"', undefined,
          '{"checks":[],"snapshot":{"providerStatus":{"literal":"fallback"}}}') +
        ']');
      const transport = new StubTransport({
        'https://engine.test/primary': { body: '{}', code: 200 }
      });
      const snapshot = await makeEngine(specJson, transport).fetch('key', GLOBAL_STANDARD);
      expect(snapshot.providerStatus).assertEqual('primary');
      expect(transport.requests.length).assertEqual(1);
    });

    // MARK: credentialKindDetection

    it('fetchEnforcesDetectedKindBeforeLaterSteps', 0, async () => {
      const transport = new StubTransport({
        'https://openrouter.ai/api/v1/key': {
          body: readRawFileString('contracts/openrouter/key-management-response.json'),
          code: 200
        }
      });
      const provider = contractSpecEngine('openrouter', transport);
      let message = '';
      try {
        // A standard-profile fetch of a management key fails right after
        // /key, without calling /credits.
        await provider.fetch('redacted-test-key', GLOBAL_STANDARD);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('profileMismatch');
      expect(transport.requests.length).assertEqual(1);
    });

    it('detectAdoptsDetectedKind', 0, async () => {
      const transport = new StubTransport({
        'https://openrouter.ai/api/v1/key': {
          body: readRawFileString('contracts/openrouter/key-management-response.json'),
          code: 200
        },
        'https://openrouter.ai/api/v1/credits': {
          body: readRawFileString('contracts/openrouter/key-management-response2.json'),
          code: 200
        }
      });
      const provider = contractSpecEngine('openrouter', transport);
      const detection = await provider.detect('redacted-test-key');
      expect(detection.profile.region).assertEqual('global');
      expect(detection.profile.credentialKind).assertEqual('management');
      expect(detection.snapshot.balances.length).assertEqual(1);
      expect(transport.requests.length).assertEqual(2);
    });

    // MARK: regionFallback

    const QUOTA_PAYLOAD: string =
      '{"model_remains":[{"model_name":"general","remains":90,"total":100}],"base_resp":{"status_code":0}}';

    it('authenticationRejectionFallsBack', 0, async () => {
      const transport = new StubTransport({
        'https://www.minimaxi.com/v1/token_plan/remains': { body: '{}', code: 401 },
        'https://www.minimax.io/v1/token_plan/remains': { body: QUOTA_PAYLOAD, code: 200 }
      });
      const provider = contractSpecEngine('minimax', transport, 'china');
      const detection = await provider.detect('redacted-plan-key');
      expect(detection.profile.region).assertEqual('international');
      expect(detection.profile.credentialKind).assertEqual('tokenPlan');
      expect(transport.requests.length).assertEqual(2);
    });

    it('embeddedAuthenticationRejectionFallsBack', 0, async () => {
      const transport = new StubTransport({
        'https://www.minimaxi.com/v1/token_plan/remains': {
          body: '{"base_resp":{"status_code":1004,"status_msg":"invalid api key"}}',
          code: 200
        },
        'https://www.minimax.io/v1/token_plan/remains': { body: QUOTA_PAYLOAD, code: 200 }
      });
      const provider = contractSpecEngine('minimax', transport, 'china');
      const detection = await provider.detect('redacted-plan-key');
      expect(detection.profile.region).assertEqual('international');
      expect(transport.requests.length).assertEqual(2);
    });

    it('exhaustedCandidatesThrowExhaustedError', 0, async () => {
      const transport = new StubTransport({
        'https://www.minimaxi.com/v1/token_plan/remains': { body: '{}', code: 401 },
        'https://www.minimax.io/v1/token_plan/remains': {
          body: '{"base_resp":{"status_code":"1004"}}',
          code: 200
        }
      });
      const provider = contractSpecEngine('minimax', transport, 'china');
      let message = '';
      try {
        await provider.detect('redacted-plan-key');
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('regionDetectionFailed');
      expect(transport.requests.length).assertEqual(2);
    });

    it('nonFallbackErrorsPropagateImmediately', 0, async () => {
      const transport = new StubTransport({
        'https://www.minimaxi.com/v1/token_plan/remains': { body: '{}', code: 429 }
      });
      const provider = contractSpecEngine('minimax', transport, 'china');
      let message = '';
      try {
        await provider.detect('redacted-plan-key');
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('rateLimited');
      expect(transport.requests.length).assertEqual(1);
    });

    // MARK: Profile and credential rules

    it('unsupportedProfilesAreRejected', 0, async () => {
      const deepSeekTransport = new StubTransport({});
      const deepSeek = contractSpecEngine('deepseek', deepSeekTransport);
      let message = '';
      try {
        await deepSeek.fetch('key', { region: 'china', credentialKind: 'standard' });
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('profileMismatch');
      expect(deepSeekTransport.requests.length).assertEqual(0);

      const openRouterTransport = new StubTransport({});
      const openRouter = contractSpecEngine('openrouter', openRouterTransport);
      message = '';
      try {
        await openRouter.fetch('key', { region: 'global', credentialKind: 'tokenPlan' });
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('profileMismatch');
      expect(openRouterTransport.requests.length).assertEqual(0);
    });

    it('rejectedCredentialPrefixesFailEarly', 0, async () => {
      const transport = new StubTransport({});
      const provider = contractSpecEngine('minimax', transport, 'china');
      let message = '';
      try {
        await provider.detect('  sk-api-redacted  ');
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('unsupportedCredential');
      expect(transport.requests.length).assertEqual(0);
    });

    it('whitespaceTrimmingAppliesFirst', 0, async () => {
      const transport = new StubTransport({
        'https://www.minimaxi.com/v1/token_plan/remains': { body: QUOTA_PAYLOAD, code: 200 }
      });
      const provider = contractSpecEngine('minimax', transport, 'china');
      await provider.detect('  redacted-plan-key  ');
      expect(transport.requestHeaders[0]['Authorization']).assertEqual('Bearer redacted-plan-key');
    });

    it('fixedProfileDetectReturnsDeclaredProfile', 0, async () => {
      const transport = new StubTransport({
        'https://api.deepseek.com/user/balance': {
          body: readRawFileString('contracts/deepseek/balance-response.json'),
          code: 200
        }
      });
      const provider = contractSpecEngine('deepseek', transport);
      const detection = await provider.detect('redacted-test-key');
      expect(detection.profile.region).assertEqual('global');
      expect(detection.profile.credentialKind).assertEqual('standard');
      expect(detection.snapshot.balances.length).assertEqual(2);
    });

    it('regionFallbackDetectStartsFromPreferredRegion', 0, async () => {
      const transport = new StubTransport({
        'https://api.moonshot.cn/v1/users/me/balance': {
          body: readRawFileString('contracts/kimi/china-response.json'),
          code: 200
        }
      });
      const provider = contractSpecEngine('kimi', transport, 'china');
      const detection = await provider.detect('redacted-test-key');
      expect(detection.profile.region).assertEqual('china');
      expect(detection.profile.credentialKind).assertEqual('standard');
      expect(transport.requests.length).assertEqual(1);
    });

    // MARK: Spec loading

    it('newerSpecVersionIsRejected', 0, () => {
      const specJson = makeEngineSpecData('[]', 2);
      let message = '';
      try {
        new SpecDrivenProvider(specJson);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('unsupportedSpecVersion:2');
    });

    it('unknownStrategyIsRejected', 0, () => {
      const parse = '{"checks":[],"snapshot":{"quotaWindows":{"strategy":"bogus","path":"items"}}}';
      const specJson = makeEngineSpecData(`[${makeStep('main', false, '"https://engine.test/endpoint"', undefined, parse)}]`);
      let message = '';
      try {
        new SpecDrivenProvider(specJson);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('unknownStrategy:bogus');
    });

    it('incompleteByRegionTableIsRejected', 0, () => {
      const specJson = makeEngineSpecData(
        `[${makeStep('main', false, '{"byRegion":{"china":"https://engine.test/cn"}}')}]`,
        1,
        '{"trimWhitespace": false}',
        '[{"region":"china","credentialKind":"standard"},{"region":"international","credentialKind":"standard"}]',
        '{"strategy":"fixedProfile","profile":{"region":"china","credentialKind":"standard"}}'
      );
      let message = '';
      try {
        new SpecDrivenProvider(specJson);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message.startsWith('invalidSpec:')).assertTrue();
      expect(message.indexOf('international') >= 0).assertTrue();
    });
  });
}
