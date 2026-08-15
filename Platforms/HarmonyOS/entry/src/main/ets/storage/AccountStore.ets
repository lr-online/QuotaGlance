import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { ALL_PROVIDER_IDS, ProviderID, ProviderProfile } from '../providers/UsageProvider';

// Mirrors Sources/QuotaGlanceCore/Storage/AccountPreferencesStore.swift
// (StoredAccountPreferences, schemaVersion 2). Shares the 'quotaglance_store'
// preferences file with SnapshotStore.
const STORE_NAME = 'quotaglance_store';
const ACCOUNTS_KEY = 'accounts_preferences_v2';
const SCHEMA_VERSION = 2;

export const MAX_ACCOUNTS: number = 20;

export interface Account {
  id: string;
  displayName: string;
  provider: ProviderID;
  detectedProfile?: ProviderProfile;
  isEnabled: boolean;
  sortOrder: number;
  lowBalanceThreshold?: string;
}

interface AccountPreferencesPayload {
  schemaVersion: number;
  accounts: Account[];
}

export function generateAccountId(): string {
  try {
    return util.generateRandomUUID(true);
  } catch (error) {
    return `${Date.now().toString(36)}-${Math.floor(Math.random() * Number.MAX_SAFE_INTEGER).toString(36)}`;
  }
}

function isValidProvider(value: string): boolean {
  return (ALL_PROVIDER_IDS as string[]).indexOf(value) >= 0;
}

export class AccountStore {
  private readonly store: preferences.Preferences;

  private constructor(store: preferences.Preferences) {
    this.store = store;
  }

  static async create(context: common.Context): Promise<AccountStore> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    return new AccountStore(store);
  }

  // Self-healing load: drops entries whose provider is no longer a valid
  // ProviderID, re-sorts by sortOrder and normalizes sortOrder to consecutive
  // indexes, persisting the sanitized list when anything changed.
  async load(): Promise<Account[]> {
    const raw = await this.store.get(ACCOUNTS_KEY, '') as string;
    if (raw.length === 0) {
      return [];
    }
    let payload: AccountPreferencesPayload;
    try {
      payload = JSON.parse(raw) as AccountPreferencesPayload;
    } catch (error) {
      return [];
    }
    if (payload === undefined || payload === null || !Array.isArray(payload.accounts)) {
      return [];
    }
    const valid: Account[] = [];
    let dirty = false;
    for (const account of payload.accounts) {
      if (account === undefined || account === null || !isValidProvider(account.provider)) {
        dirty = true;
        continue;
      }
      valid.push(account);
    }
    valid.sort((a: Account, b: Account) => a.sortOrder - b.sortOrder);
    for (let i = 0; i < valid.length; i++) {
      if (valid[i].sortOrder !== i) {
        valid[i].sortOrder = i;
        dirty = true;
      }
    }
    if (dirty) {
      await this.saveAll(valid);
    }
    return valid;
  }

  async saveAll(accounts: Account[]): Promise<void> {
    accounts.sort((a: Account, b: Account) => a.sortOrder - b.sortOrder);
    for (let i = 0; i < accounts.length; i++) {
      accounts[i].sortOrder = i;
    }
    const payload: AccountPreferencesPayload = {
      schemaVersion: SCHEMA_VERSION,
      accounts: accounts
    };
    await this.store.put(ACCOUNTS_KEY, JSON.stringify(payload));
    await this.store.flush();
  }

  async add(account: Account): Promise<void> {
    const accounts = await this.load();
    if (accounts.length >= MAX_ACCOUNTS) {
      throw new Error('accountLimitReached');
    }
    account.sortOrder = accounts.length;
    accounts.push(account);
    await this.saveAll(accounts);
  }

  async update(account: Account): Promise<void> {
    const accounts = await this.load();
    for (let i = 0; i < accounts.length; i++) {
      if (accounts[i].id === account.id) {
        accounts[i] = account;
        await this.saveAll(accounts);
        return;
      }
    }
    throw new Error('accountNotFound');
  }

  // Removes metadata only. Key and snapshot cascade lives in
  // AccountService.deleteAccount, which owns the cross-store orchestration.
  async remove(accountId: string): Promise<void> {
    const accounts = await this.load();
    const remaining = accounts.filter((account: Account) => account.id !== accountId);
    if (remaining.length !== accounts.length) {
      await this.saveAll(remaining);
    }
  }

  async nextSortOrder(): Promise<number> {
    return (await this.load()).length;
  }
}
