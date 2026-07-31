import { describe, it, expect } from '@ohos/hypium';
import { createProviderRegistry } from '../../../main/ets/providers/ProviderCatalog';
import { ProviderID, UsageProvider } from '../../../main/ets/providers/UsageProvider';

export default function abilityTest() {
  describe('ProviderCatalogTest', () => {
    it('registryContainsPortedProviders', 0, () => {
      const registry = createProviderRegistry();
      const ids: ProviderID[] = registry.all().map((provider: UsageProvider): ProviderID => provider.id);
      expect(ids.indexOf('apiInfo') >= 0).assertTrue();
      expect(ids.indexOf('deepSeek') >= 0).assertTrue();
    });
  });
}
