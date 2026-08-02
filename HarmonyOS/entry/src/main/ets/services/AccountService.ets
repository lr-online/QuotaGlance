import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { createProviderRegistry, providerDisplayName } from '../providers/ProviderCatalog';
import {
  ProviderID,
  ProviderRegistry
} from '../providers/UsageProvider';
import { Account, AccountStore, generateAccountId } from '../storage/AccountStore';
import { KeyRepository } from '../storage/KeyRepository';
import { SnapshotStore } from '../storage/SnapshotStore';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlance';

export interface CreateAccountInput {
  provider: ProviderID;
  displayName: string;
  apiKey: string;
  lowBalanceThreshold?: string;
}

// Orchestration layer used by pages and EntryFormAbility so the UI stays thin.
// Error tokens from the provider layer propagate unchanged; the UI maps them
// to friendly text.
export class AccountService {
  private readonly context: common.Context;
  private readonly registry: ProviderRegistry;
  private readonly accountStore: AccountStore;
  private readonly snapshotStore: SnapshotStore;

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

  async refreshAccount(account: Account): Promise<void> {
    if (!account.isEnabled) {
      return;
    }
    const apiKey = await KeyRepository.load(account.id);
    if (apiKey === null) {
      throw new Error('missingCredential');
    }
    const provider = this.registry.provider(account.provider);
    try {
      const profile = account.detectedProfile;
      // No stored profile cannot be refreshed through the narrowed provider
      // interface (Swift's RefreshCoordinator fails the same way).
      if (profile === undefined || (profile.region === undefined && profile.credentialKind === undefined)) {
        throw new Error('profileMismatch');
      }
      await this.snapshotStore.save(account.id, await provider.fetch(apiKey, profile));
      hilog.info(DOMAIN, TAG, 'refreshAccount ok: %{public}s', account.id);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'refreshAccount failed: %{public}s %{public}s', account.id, (error as Error).message);
      await this.snapshotStore.markStale(account.id);
      throw error as Error;
    }
  }

  // Sequential on purpose (widget context). Per-account failures mark that
  // account stale without aborting the rest.
  async refreshAllEnabled(): Promise<void> {
    const accounts = await this.accountStore.load();
    for (const account of accounts) {
      if (!account.isEnabled) {
        continue;
      }
      try {
        await this.refreshAccount(account);
      } catch (error) {
        await this.snapshotStore.markStale(account.id);
      }
    }
  }

  async saveAccountKey(accountId: string, apiKey: string): Promise<void> {
    await KeyRepository.save(accountId, apiKey.trim());
  }

  async deleteAccount(accountId: string): Promise<void> {
    await KeyRepository.clear(accountId);
    await this.snapshotStore.clear(accountId);
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
