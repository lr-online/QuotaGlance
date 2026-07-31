import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

// Per-account credentials in Asset Store Kit. Alias scheme:
//   quotaglance_key_<accountId>
// The pre-multi-account single-key installs used a fixed alias; migrateLegacyKey
// reads it so AccountService can move the key onto a new account.
const ALIAS_PREFIX = 'quotaglance_key_';
const LEGACY_ALIAS = 'quotaglance_deepseek_api_key';
const ERROR_NOT_FOUND = 24000002;

function stringToArray(str: string): Uint8Array {
  return new util.TextEncoder().encodeInto(str);
}

function arrayToString(bytes: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

function rethrowBusinessError(error: Object, action: string): never {
  const businessError = error as BusinessError;
  throw new Error(`${action}:${businessError.code}`);
}

function aliasForAccount(accountId: string): string {
  return ALIAS_PREFIX + accountId;
}

export interface LegacyKey {
  key: string;
}

async function saveWithAlias(alias: string, apiKey: string): Promise<void> {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, stringToArray(alias));
  try {
    await asset.remove(query);
  } catch (error) {
    if ((error as BusinessError).code !== ERROR_NOT_FOUND) {
      rethrowBusinessError(error as Object, 'assetRemoveFailed');
    }
  }

  const attributes: asset.AssetMap = new Map();
  attributes.set(asset.Tag.ALIAS, stringToArray(alias));
  attributes.set(asset.Tag.SECRET, stringToArray(apiKey));
  attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
  await asset.add(attributes);
}

async function loadWithAlias(alias: string): Promise<string | null> {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, stringToArray(alias));
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  try {
    const results = await asset.query(query);
    if (results.length === 0) {
      return null;
    }
    const secret = results[0].get(asset.Tag.SECRET) as Uint8Array;
    return arrayToString(secret);
  } catch (error) {
    if ((error as BusinessError).code === ERROR_NOT_FOUND) {
      return null;
    }
    rethrowBusinessError(error as Object, 'assetQueryFailed');
  }
}

async function clearWithAlias(alias: string): Promise<void> {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, stringToArray(alias));
  try {
    await asset.remove(query);
  } catch (error) {
    if ((error as BusinessError).code !== ERROR_NOT_FOUND) {
      rethrowBusinessError(error as Object, 'assetClearFailed');
    }
  }
}

export class KeyRepository {
  static async save(accountId: string, apiKey: string): Promise<void> {
    await saveWithAlias(aliasForAccount(accountId), apiKey);
  }

  static async load(accountId: string): Promise<string | null> {
    return loadWithAlias(aliasForAccount(accountId));
  }

  static async clear(accountId: string): Promise<void> {
    await clearWithAlias(aliasForAccount(accountId));
  }

  // Reads the legacy single-key alias from pre-multi-account installs without
  // touching it. AccountService.ensureLegacyMigration moves the key onto a new
  // DeepSeek account and then calls removeLegacyKey.
  static async migrateLegacyKey(): Promise<LegacyKey | null> {
    const key = await loadWithAlias(LEGACY_ALIAS);
    if (key === null) {
      return null;
    }
    const legacy: LegacyKey = { key: key };
    return legacy;
  }

  static async removeLegacyKey(): Promise<void> {
    await clearWithAlias(LEGACY_ALIAS);
  }
}
