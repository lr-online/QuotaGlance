import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { createProviderRegistry } from '../../../main/ets/providers/ProviderCatalog';
import { ALL_PROVIDER_IDS, ProviderID, UsageProvider } from '../../../main/ets/providers/UsageProvider';

export default function abilityTest() {
  describe('ProviderCatalogTest', () => {
    it('registryContainsAllSpecDrivenProviders', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.Context;
      const registry = createProviderRegistry(context);
      const providers = registry.all();
      expect(providers.length).assertEqual(ALL_PROVIDER_IDS.length);
      const ids: ProviderID[] = providers.map((provider: UsageProvider): ProviderID => provider.id);
      for (const id of ALL_PROVIDER_IDS) {
        expect(ids.indexOf(id) >= 0).assertTrue();
      }
    });

    it('descriptorsComeFromSpecs', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.Context;
      const registry = createProviderRegistry(context);
      const deepSeek = registry.provider('deepSeek');
      expect(deepSeek.descriptor.displayName).assertEqual('DeepSeek');
      expect(deepSeek.descriptor.supportsLowBalanceThreshold(undefined)).assertTrue();
      const miniMax = registry.provider('miniMax');
      expect(miniMax.descriptor.displayName).assertEqual('MiniMax');
      expect(miniMax.descriptor.supportsLowBalanceThreshold(undefined)).assertFalse();
      // OpenRouter: undetected or management only.
      const openRouter = registry.provider('openRouter');
      expect(openRouter.descriptor.supportsLowBalanceThreshold(undefined)).assertTrue();
      expect(
        openRouter.descriptor.supportsLowBalanceThreshold({ region: 'global', credentialKind: 'management' })
      ).assertTrue();
      expect(
        openRouter.descriptor.supportsLowBalanceThreshold({ region: 'global', credentialKind: 'standard' })
      ).assertFalse();
    });
  });
}
