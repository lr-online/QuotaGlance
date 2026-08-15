// Builds the provider registry from the spec resources synced by
// scripts/sync-specs-to-harmonyos.sh into
// entry/src/main/resources/rawfile/providerspecs/<id>.json (camelCase id).
// The rawfile specs are read through the app context's resourceManager; the
// engine itself stays context-free (tests inject the spec JSON directly).
// Specs are immutable bundled resources, so providers are built once and
// cached.

import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { SpecDrivenProvider } from './SpecDrivenProvider';
import {
  ALL_PROVIDER_IDS,
  ProviderDescriptor,
  ProviderID,
  ProviderRegistry,
  UsageProvider
} from './UsageProvider';

const providerCache: Map<ProviderID, SpecDrivenProvider> = new Map();

function readSpecJson(context: common.Context, id: ProviderID): string {
  try {
    const bytes: Uint8Array =
      context.resourceManager.getRawFileContentSync(`providerspecs/${id}.json`);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  } catch (error) {
    throw new Error(`specNotFound:${id}`);
  }
}

// Returns the spec-driven provider for the id, building and caching it on
// first use. A missing or invalid spec fails fast here.
export function providerFor(context: common.Context, id: ProviderID): SpecDrivenProvider {
  let provider = providerCache.get(id);
  if (provider === undefined) {
    provider = new SpecDrivenProvider(readSpecJson(context, id));
    providerCache.set(id, provider);
  }
  return provider;
}

// Builds the registry of providers compiled into the app.
export function createProviderRegistry(context: common.Context): ProviderRegistry {
  const providers: UsageProvider[] = ALL_PROVIDER_IDS.map(
    (id: ProviderID): UsageProvider => providerFor(context, id));
  return new ProviderRegistry(providers);
}

export function providerDescriptor(context: common.Context, id: ProviderID): ProviderDescriptor {
  return providerFor(context, id).descriptor;
}

export function providerDisplayName(context: common.Context, id: ProviderID): string {
  return providerFor(context, id).descriptor.displayName;
}
