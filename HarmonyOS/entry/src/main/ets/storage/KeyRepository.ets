import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

const ALIAS = 'quotaglance_deepseek_api_key';
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

export class KeyRepository {
  static async save(apiKey: string): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, stringToArray(ALIAS));
    try {
      await asset.remove(query);
    } catch (error) {
      if ((error as BusinessError).code !== ERROR_NOT_FOUND) {
        rethrowBusinessError(error as Object, 'assetRemoveFailed');
      }
    }

    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, stringToArray(ALIAS));
    attributes.set(asset.Tag.SECRET, stringToArray(apiKey));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    await asset.add(attributes);
  }

  static async load(): Promise<string | null> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, stringToArray(ALIAS));
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

  static async clear(): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, stringToArray(ALIAS));
    try {
      await asset.remove(query);
    } catch (error) {
      if ((error as BusinessError).code !== ERROR_NOT_FOUND) {
        rethrowBusinessError(error as Object, 'assetClearFailed');
      }
    }
  }
}
