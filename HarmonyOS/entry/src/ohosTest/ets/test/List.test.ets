import abilityTest from './Ability.test';
import aggregationContractTest from './AggregationContract.test';
import alertsContractTest from './AlertsContract.test';
import contractTest from './Contract.test';
import refreshEffectsTest from './RefreshEffects.test';
import specEngineTest from './SpecEngine.test';

export default function testsuite() {
  abilityTest();
  aggregationContractTest();
  alertsContractTest();
  contractTest();
  refreshEffectsTest();
  specEngineTest();
}
