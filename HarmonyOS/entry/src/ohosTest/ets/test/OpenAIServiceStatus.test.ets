import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { util } from '@kit.ArkTS';
import { parseOpenAIServiceStatus } from '../../../main/ets/services/OpenAIServiceStatus';

export default function OpenAIServiceStatusTest() {
  describe('OpenAI service status fixture', () => {
    it('maps the shared degraded fixture', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const bytes = context.resourceManager.getRawFileContentSync('contracts/servicestatus/openai-degraded-response.json');
      const body = util.TextDecoder.create('utf-8').decodeToString(bytes);
      const status = parseOpenAIServiceStatus(body);
      expect(status.overall).assertEqual('degraded');
      expect(status.affectedComponents.length).assertEqual(2);
      expect(status.activeIncidents.length).assertEqual(1);
    });
  });
}
