import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { createProviderRegistry, providerDisplayName } from '../providers/ProviderCatalog';
import {
  ProviderID,
  ProviderRegistry
} from '../providers/UsageProvider';
import { Account, AccountStore, generateAccountId } from '../storage/AccountStore';
import { AlertStateStore } from '../storage/AlertStateStore';
import { KeyRepository } from '../storage/KeyRepository';
import { SnapshotStore } from '../storage/SnapshotStore';
import { notifyOverviewRefresh } from './LaunchRefresh';
import { evaluateAndNotifyAlerts } from './NotificationService';
import { RefreshCoordinator, RefreshResult } from './RefreshCoordinator';
import { updateAllCards } from './CardUpdater';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

export interface CreateAccountInput {
  provider: ProviderID;
  displayName: string;
  apiKey: string;
  lowBalanceThreshold?: string;
}

export interface UpdateAccountInput extends CreateAccountInput {
  isEnabled: boolean;
}

// Orchestration layer used by pages and EntryFormAbility so the UI stays thin.
// Error tokens from the provider layer propagate unchanged; the UI maps them
// to friendly text.
export class AccountService {
  private readonly context: common.Context;
  private readonly registry: ProviderRegistry;
  private readonly accountStore: AccountStore;
  private readonly snapshotStore: SnapshotStore;
  private refreshCoordinator?: RefreshCoordinator;

  private constructor(
    context: common.Context,
    registry: ProviderRegistry,
    accountStore: AccountStore,
    snapshotStore: SnapshotStore
  ) {
    this.context = context;
    this.registry = registry;
    this.accountStore = accountStore;
    this.snapshotStore = snapshotStore;
  }

  static async create(context: common.Context): Promise<AccountService> {
    const accountStore = await AccountStore.create(context);
    const snapshotStore = await SnapshotStore.create(context);
    return new AccountService(context, createProviderRegistry(context), accountStore, snapshotStore);
  }

  async loadAccounts(): Promise<Account[]> {
    return this.accountStore.load();
  }

  // Live-validates the key via provider.detect, then persists key, account
  // metadata and the detection snapshot. Any failure after the key save rolls
  // the key back so no orphan credential is left behind.
  async createAccount(input: CreateAccountInput): Promise<Account> {
    const provider = this.registry.provider(input.provider);
    const apiKey = input.apiKey.trim();
    if (apiKey.length === 0) {
      throw new Error('invalidCredential');
    }
    const displayName = input.displayName.trim();
    const detection = await provider.detect(apiKey);
    const account: Account = {
      id: generateAccountId(),
      displayName: displayName.length > 0 ? displayName : providerDisplayName(this.context, input.provider),
      provider: input.provider,
      detectedProfile: detection.profile,
      isEnabled: true,
      sortOrder: await this.accountStore.nextSortOrder()
    };
    const threshold = input.lowBalanceThreshold?.trim();
    if (threshold !== undefined && threshold.length > 0) {
      account.lowBalanceThreshold = threshold;
    }
    await KeyRepository.save(account.id, apiKey);
    try {
      await this.accountStore.add(account);
      await this.snapshotStore.save(account.id, detection.snapshot);
    } catch (error) {
      await KeyRepository.clear(account.id);
      throw error as Error;
    }
    return account;
  }

  // Editing keeps the existing credential when apiKey is blank. Changing the
  // provider requires a replacement key because the stored credential/profile
  // cannot be assumed to work with a different provider. A supplied key is
  // detected before any persisted state changes, matching the create path.
  async updateAccount(accountId: string, input: UpdateAccountInput): Promise<Account> {
    const accounts = await this.accountStore.load();
    const existing = accounts.find((account: Account) => account.id === accountId);
    if (existing === undefined) {
      throw new Error('accountNotFound');
    }

    const provider = this.registry.provider(input.provider);
    const apiKey = input.apiKey.trim();
    if (apiKey.length === 0 && input.provider !== existing.provider) {
      throw new Error('replacementKeyRequired');
    }
    const detection = apiKey.length > 0 ? await provider.detect(apiKey) : undefined;
    const effectiveProfile = detection?.profile ?? existing.detectedProfile;
    const displayName = input.displayName.trim();
    const updated: Account = {
      id: existing.id,
      displayName: displayName.length > 0 ? displayName : providerDisplayName(this.context, input.provider),
      provider: input.provider,
      detectedProfile: effectiveProfile,
      isEnabled: input.isEnabled,
      sortOrder: existing.sortOrder
    };
    const threshold = input.lowBalanceThreshold?.trim();
    if (threshold !== undefined && threshold.length > 0
      && provider.descriptor.supportsLowBalanceThreshold(effectiveProfile)) {
      updated.lowBalanceThreshold = threshold;
    }

    if (detection !== undefined) {
      const previousKey = await KeyRepository.load(accountId);
      try {
        await KeyRepository.save(accountId, apiKey);
        await this.accountStore.update(updated);
        await this.snapshotStore.save(accountId, detection.snapshot);
      } catch (error) {
        try {
          await this.accountStore.update(existing);
        } catch (rollbackError) {
          hilog.error(DOMAIN, TAG, 'account-edit metadata rollback failed: %{public}s',
            (rollbackError as Error).message);
        }
        if (previousKey === null) {
          await KeyRepository.clear(accountId);
        } else {
          await KeyRepository.save(accountId, previousKey);
        }
        throw error as Error;
      }
    } else {
      await this.accountStore.update(updated);
    }

    if (!updated.isEnabled || updated.lowBalanceThreshold === undefined) {
      const alertStateStore = await AlertStateStore.create(this.context);
      await alertStateStore.clear(accountId);
    }
    notifyOverviewRefresh();
    updateAllCards(this.context).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'account-edit card update failed: %{public}s', (error as Error).message);
    });
    return updated;
  }

  async refreshAccount(account: Account): Promise<void> {
    if (!account.isEnabled) {
      return;
    }
    try {
      const apiKey = await KeyRepository.load(account.id);
      if (apiKey === null) {
        throw new Error('missingCredential');
      }
      const provider = this.registry.provider(account.provider);
      const profile = account.detectedProfile;
      // No stored profile cannot be refreshed through the narrowed provider
      // interface (Swift's RefreshCoordinator fails the same way).
      if (profile === undefined || (profile.region === undefined && profile.credentialKind === undefined)) {
        throw new Error('profileMismatch');
      }
      await this.snapshotStore.save(account.id, await provider.fetch(apiKey, profile));
      hilog.info(DOMAIN, TAG, 'refreshAccount ok: %{public}s', account.id);
      this.afterSuccessfulRefresh([account.id]);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'refreshAccount failed: %{public}s %{public}s', account.id, (error as Error).message);
      await this.snapshotStore.markStale(account.id, (error as Error).message);
      this.afterFailedRefresh();
      throw error as Error;
    }
  }

  // Post-refresh fan-out: snapshot-linked card updates (push fresh data to
  // every registered form) + low-balance alert evaluation/notification. Both
  // are fire-and-forget — a card push or notification failure must never fail
  // the refresh itself. Wired here at the service seam so EVERY refresh path
  // is covered: foreground batches, the WorkScheduler background batch (via
  // getRefreshCoordinator's afterBatch dep) and single-account refreshes
  // (refreshAccount above). The alert engine stays I/O-free; all
  // persistence/notification happens in NotificationService.
  private afterSuccessfulRefresh(refreshedIds: string[]): void {
    updateAllCards(this.context).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'card update failed: %{public}s', (error as Error).message);
    });
    evaluateAndNotifyAlerts(this.context, refreshedIds).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'alert evaluation failed: %{public}s', (error as Error).message);
    });
  }

  private afterFailedRefresh(): void {
    notifyOverviewRefresh();
    updateAllCards(this.context).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'failed-refresh card update failed: %{public}s', (error as Error).message);
    });
  }

  // THE batch-refresh path. Lazily built so the coordinator's per-account
  // dedup window is shared by every batch caller (cold launch, manual
  // refresh-all, background scheduler) on this service instance. The
  // coordinator delegates each account's fetch+persist back to
  // refreshAccount above; it owns batching, isolation and outcome.
  getRefreshCoordinator(): RefreshCoordinator {
    if (this.refreshCoordinator === undefined) {
      this.refreshCoordinator = new RefreshCoordinator({
        loadAccounts: () => this.loadAccounts(),
        refreshAccount: (account: Account) => this.refreshAccount(account),
        notifyRefreshed: notifyOverviewRefresh,
        // Batch post-refresh hook (foreground + background alike). Note the
        // per-account path already fans out via refreshAccount's own
        // afterSuccessfulRefresh; this hook adds nothing extra for the batch
        // members — it exists so the coordinator's completion seam triggers
        // the same fan-out even if a future caller bypasses refreshAccount.
        afterBatch: (result: RefreshResult) => {
          this.afterSuccessfulRefresh(result.succeeded);
        }
      });
    }
    return this.refreshCoordinator;
  }

  // Thin delegate kept for fire-and-forget callers (ScreensaverPage);
  // UI callers that need the outcome should use getRefreshCoordinator().
  async refreshAllEnabled(): Promise<RefreshResult> {
    return this.getRefreshCoordinator().refreshAllEnabled();
  }

  async saveAccountKey(accountId: string, apiKey: string): Promise<void> {
    await KeyRepository.save(accountId, apiKey.trim());
  }

  async deleteAccount(accountId: string): Promise<void> {
    const alertStateStore = await AlertStateStore.create(this.context);
    await KeyRepository.clear(accountId);
    await this.snapshotStore.clear(accountId);
    await alertStateStore.clear(accountId);
    await this.accountStore.remove(accountId);
  }

  // One-shot migration for pre-multi-account installs: if there are no
  // accounts and the legacy DeepSeek alias exists, create a DeepSeek account,
  // move the key onto the per-account alias, then drop the legacy alias.
  // Idempotent: with any account present it does nothing.
  async ensureLegacyMigration(): Promise<void> {
    const accounts = await this.accountStore.load();
    if (accounts.length > 0) {
      return;
    }
    const legacy = await KeyRepository.migrateLegacyKey();
    if (legacy === null) {
      return;
    }
    const account: Account = {
      id: generateAccountId(),
      displayName: providerDisplayName(this.context, 'deepSeek'),
      provider: 'deepSeek',
      isEnabled: true,
      sortOrder: 0
    };
    await KeyRepository.save(account.id, legacy.key);
    try {
      await this.accountStore.add(account);
    } catch (error) {
      await KeyRepository.clear(account.id);
      throw error as Error;
    }
    await KeyRepository.removeLegacyKey();
  }
}
