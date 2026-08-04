import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { createProviderRegistry } from '../../../main/ets/providers/ProviderCatalog';
import { ALL_PROVIDER_IDS, ProviderID, UsageProvider } from '../../../main/ets/providers/UsageProvider';
import { resolveProfileDescription } from '../../../main/ets/utils/ProfileDescriptionL10n';
import { Account } from '../../../main/ets/storage/AccountStore';
import { StoredSnapshot } from '../../../main/ets/storage/SnapshotStore';
import { UsageSnapshot } from '../../../main/ets/providers/UsageSnapshot';
import { buildScreensaverMessages, ScreensaverMessageSource } from '../../../main/ets/utils/ScreensaverMessages';
import {
  selectAdjacentAccount,
  WidgetAccount
} from '../../../main/ets/widget/FormAccountNavigation';

function widgetAccount(id: string, sortOrder: number, isEnabled: boolean = true): WidgetAccount {
  return { id: id, sortOrder: sortOrder, isEnabled: isEnabled };
}

function account(id: string, enabled: boolean = true, threshold?: string): Account {
  const value: Account = {
    id: id,
    displayName: id,
    provider: 'deepSeek',
    isEnabled: enabled,
    sortOrder: 0
  };
  if (threshold !== undefined) {
    value.lowBalanceThreshold = threshold;
  }
  return value;
}

function stored(amount: string, stale: boolean = false, providerStatus?: string): StoredSnapshot {
  const usage: UsageSnapshot = {
    provider: 'deepSeek',
    balances: [{
      label: 'balance',
      available: { amount: amount, currency: 'CNY' },
      breakdown: []
    }],
    receivedAtMs: 100
  };
  if (providerStatus !== undefined) {
    usage.providerStatus = providerStatus;
  }
  return { snapshot: usage, isStale: stale };
}

export default function abilityTest() {
  describe('WidgetAccountNavigationTest', () => {
    it('filtersDisabledAccountsAndSortsByOrder', 0, () => {
      const accounts: WidgetAccount[] = [
        widgetAccount('later', 2),
        widgetAccount('disabled', 0, false),
        widgetAccount('first', 1)
      ];
      const selected = selectAdjacentAccount(accounts, 'first', 'left');
      expect(selected?.id).assertEqual('later');
    });

    it('wrapsInBothDirections', 0, () => {
      const accounts: WidgetAccount[] = [widgetAccount('first', 0), widgetAccount('last', 1)];
      const left = selectAdjacentAccount(accounts, 'last', 'left');
      const right = selectAdjacentAccount(accounts, 'first', 'right');
      expect(left?.id).assertEqual('first');
      expect(right?.id).assertEqual('last');
    });

    it('entersFromAggregateAtTheCorrectEnd', 0, () => {
      const accounts: WidgetAccount[] = [widgetAccount('first', 0), widgetAccount('last', 1)];
      const left = selectAdjacentAccount(accounts, undefined, 'left');
      const right = selectAdjacentAccount(accounts, undefined, 'right');
      expect(left?.id).assertEqual('first');
      expect(right?.id).assertEqual('last');
    });

    it('returnsNullWhenThereAreNoEnabledAccounts', 0, () => {
      const selected = selectAdjacentAccount([widgetAccount('disabled', 0, false)], undefined, 'left');
      expect(selected).assertEqual(null);
    });
  });

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

    it('resolvesEveryProfileDescriptionTokenShape', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.Context;
      expect(resolveProfileDescription(context, 'notDetected')).assertEqual(
        context.resourceManager.getStringSync($r('app.string.l10n_not_detected').id)
      );
      expect(resolveProfileDescription(context, 'standard')).assertEqual(
        context.resourceManager.getStringSync($r('app.string.l10n_standard_key').id)
      );
      expect(resolveProfileDescription(context, 'globalCredential:management')).assertEqual(
        context.resourceManager.getStringSync($r('app.string.l10n_global_credential').id)
          .replace('%s', context.resourceManager.getStringSync($r('app.string.l10n_management_key').id))
      );
      expect(resolveProfileDescription(context, 'regionCredential:china:tokenPlan')).assertEqual(
        context.resourceManager.getStringSync($r('app.string.l10n_region_credential').id)
          .replace('%s', context.resourceManager.getStringSync($r('app.string.l10n_china').id))
          .replace('%s', context.resourceManager.getStringSync($r('app.string.l10n_token_plan').id))
      );
      expect(resolveProfileDescription(context, 'chinaCNY')).assertEqual(
        context.resourceManager.getStringSync($r('app.string.l10n_china_cny').id)
      );
      expect(resolveProfileDescription(context, 'internationalUSD')).assertEqual(
        context.resourceManager.getStringSync($r('app.string.l10n_international_usd').id)
      );
      expect(resolveProfileDescription(context, 'chinaCNY:management')).assertEqual(
        `${context.resourceManager.getStringSync($r('app.string.l10n_china_cny').id)} · `
          + context.resourceManager.getStringSync($r('app.string.l10n_management_key').id)
      );
      expect(resolveProfileDescription(context, 'futureToken')).assertEqual('futureToken');
    });
  });

  describe('ScreensaverMessagesTest', () => {
    it('prioritizesErrorsAndCapsMessages', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.Context;
      const sources: ScreensaverMessageSource[] = [
        { account: account('low', true, '10'), stored: stored('5') },
        { account: account('stale'), stored: stored('20', true) },
        { account: account('unavailable'), stored: stored('20', false, 'inactive') },
        { account: account('waiting'), stored: null }
      ];
      const messages = buildScreensaverMessages(context, sources);
      expect(messages.length).assertEqual(3);
      expect(messages[0].severity).assertEqual('error');
      expect(messages[1].severity).assertEqual('error');
      expect(messages[2].severity).assertEqual('warning');
    });

    it('excludesDisabledAccounts', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.Context;
      const messages = buildScreensaverMessages(context, [
        { account: account('disabled', false), stored: null }
      ]);
      expect(messages.length).assertEqual(0);
    });

    it('acceptsLegacySnapshotsWithoutRefreshMetadata', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.Context;
      const messages = buildScreensaverMessages(context, [
        { account: account('legacy'), stored: stored('20', true) }
      ]);
      expect(messages.length).assertEqual(1);
      expect(messages[0].severity).assertEqual('error');
      expect(messages[0].createdAtMs).assertEqual(100);
    });

    it('comparesLowBalanceThresholdsAsExactDecimals', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.Context;
      const messages = buildScreensaverMessages(context, [
        {
          account: account('precise', true, '9007199254740992.0'),
          stored: stored('9007199254740992.1')
        }
      ]);
      expect(messages.length).assertEqual(0);
    });
  });
}
