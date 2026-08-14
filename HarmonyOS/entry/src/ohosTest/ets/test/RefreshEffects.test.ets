import { describe, it, expect } from '@ohos/hypium';
import { RefreshEffects } from '../../../main/ets/services/RefreshEffects';
import { RefreshCoordinator, RefreshResult } from '../../../main/ets/services/RefreshCoordinator';
import { Account } from '../../../main/ets/storage/AccountStore';

function account(id: string): Account {
  return {
    id: id,
    displayName: id,
    provider: 'deepSeek',
    isEnabled: true,
    sortOrder: 0
  };
}

export default function refreshEffectsTest() {
  describe('RefreshRunEffectsTest', () => {
    it('appliesBatchEffectsOnceAfterAllSuccessfulAccountsComplete', 0, async () => {
      const completed: RefreshResult[] = [];
      const coordinator = new RefreshCoordinator({
        loadAccounts: async () => [account('one'), account('two')],
        refreshAccount: async (_account: Account) => {},
        onCompleted: async (result: RefreshResult) => {
          completed.push(result);
        }
      });

      await coordinator.refreshAllEnabled();

      expect(completed.length).assertEqual(1);
      expect(completed[0].succeeded.length).assertEqual(2);
    });

    it('invalidatesAndPublishesOnceForAllFailedRunWithoutEvaluatingAlerts', 0, async () => {
      let invalidations = 0;
      let publications = 0;
      let evaluations = 0;
      const effects = new RefreshEffects({
        invalidateOverview: () => invalidations++,
        publishCards: async () => {
          publications++;
        },
        evaluateAlerts: async (_ids: string[]) => {
          evaluations++;
        }
      });

      await effects.apply({ outcome: 'allFailed', succeeded: [], failed: ['one'] });

      expect(invalidations).assertEqual(1);
      expect(publications).assertEqual(1);
      expect(evaluations).assertEqual(0);
    });

    it('reportsAllFailedBatchOnceSoPersistedStaleStateCanPublish', 0, async () => {
      const completed: RefreshResult[] = [];
      const coordinator = new RefreshCoordinator({
        loadAccounts: async () => [account('one'), account('two')],
        refreshAccount: async (_account: Account) => {
          throw new Error('network:1');
        },
        onCompleted: async (result: RefreshResult) => {
          completed.push(result);
        }
      });

      const result = await coordinator.refreshAllEnabled();

      expect(result.outcome).assertEqual('allFailed');
      expect(completed.length).assertEqual(1);
      expect(completed[0].failed.length).assertEqual(2);
    });

    it('evaluatesFreshSuccessesOnceForSingleCompletedRun', 0, async () => {
      const evaluated: string[][] = [];
      const effects = new RefreshEffects({
        invalidateOverview: () => {},
        publishCards: async () => {},
        evaluateAlerts: async (ids: string[]) => {
          evaluated.push(ids);
        }
      });

      await effects.apply({ outcome: 'partial', succeeded: ['one', 'two'], failed: ['three'] });

      expect(evaluated.length).assertEqual(1);
      expect(evaluated[0].length).assertEqual(2);
      expect(evaluated[0][0]).assertEqual('one');
      expect(evaluated[0][1]).assertEqual('two');
    });
  });
}
