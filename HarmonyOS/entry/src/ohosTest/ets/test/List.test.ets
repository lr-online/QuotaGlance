import abilityTest from './Ability.test';
import contractTest from './Contract.test';
import specEngineTest from './SpecEngine.test';

export default function testsuite() {
  abilityTest();
  contractTest();
  specEngineTest();
}
