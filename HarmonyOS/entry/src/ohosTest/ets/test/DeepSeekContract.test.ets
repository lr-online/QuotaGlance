import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { util } from '@kit.ArkTS';
import { parseBalance } from '../../../main/ets/providers/DeepSeekProvider';

interface ExpectedMoney {
  amount: string;
  currency: string;
}

interface ExpectedBreakdownItem {
  label: string;
  value: ExpectedMoney;
}

interface ExpectedBalance {
  label: string;
  available: ExpectedMoney;
  breakdown: ExpectedBreakdownItem[];
}

interface ExpectedSnapshot {
  balances: ExpectedBalance[];
  providerStatus: string;
}

function readRawFileString(path: string): string {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(path);
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

export default function deepSeekContractTest() {
  describe('DeepSeekContractTest', () => {
    it('parseBalanceMatchesContractFixture', 0, () => {
      const responseBody = readRawFileString('contracts/deepseek/balance-response.json');
      const expected = JSON.parse(
        readRawFileString('contracts/deepseek/balance-expected.json')
      ) as ExpectedSnapshot;

      const snapshot = parseBalance(responseBody, 0);

      expect(snapshot.providerStatus).assertEqual(expected.providerStatus);
      expect(snapshot.balances.length).assertEqual(expected.balances.length);
      for (let i = 0; i < expected.balances.length; i++) {
        const actualBalance = snapshot.balances[i];
        const expectedBalance = expected.balances[i];
        expect(actualBalance.label).assertEqual(expectedBalance.label);
        expect(actualBalance.available.amount).assertEqual(expectedBalance.available.amount);
        expect(actualBalance.available.currency).assertEqual(expectedBalance.available.currency);
        expect(actualBalance.breakdown.length).assertEqual(expectedBalance.breakdown.length);
        for (let j = 0; j < expectedBalance.breakdown.length; j++) {
          const actualItem = actualBalance.breakdown[j];
          const expectedItem = expectedBalance.breakdown[j];
          expect(actualItem.label).assertEqual(expectedItem.label);
          expect(actualItem.value.amount).assertEqual(expectedItem.value.amount);
          expect(actualItem.value.currency).assertEqual(expectedItem.value.currency);
        }
      }
    });

    it('rejectsEmptyBalanceInfos', 0, () => {
      let threw = false;
      try {
        parseBalance('{"is_available":true,"balance_infos":[]}', 0);
      } catch (error) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });
}
