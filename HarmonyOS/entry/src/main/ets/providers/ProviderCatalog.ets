import { APIInfoProvider } from './APIInfoProvider';
import { BioMapCodingProvider } from './BioMapCodingProvider';
import { DeepSeekProvider } from './DeepSeekProvider';
import { KimiProvider } from './KimiProvider';
import { MiniMaxProvider } from './MiniMaxProvider';
import { OpenRouterProvider } from './OpenRouterProvider';
import { ProviderRegistry, UsageProvider } from './UsageProvider';

// Builds the registry of providers compiled into the app.
export function createProviderRegistry(): ProviderRegistry {
  const providers: UsageProvider[] = [
    new APIInfoProvider(),
    new DeepSeekProvider(),
    new KimiProvider(),
    new OpenRouterProvider(),
    new MiniMaxProvider(),
    new BioMapCodingProvider()
  ];
  return new ProviderRegistry(providers);
}
