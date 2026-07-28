import { describe, it, expect } from '@ohos/hypium';

export default function abilityTest() {
  describe('ActsAbilityTest', () => {
    it('assertContain', 0, () => {
      expect('abc').assertContain('b');
      expect('abcd').assertContain('bc');
    });
  });
}
