import type { AccountHealth, Money, ProviderID } from "@/lib/tauri-bindings";

export const PROVIDER_NAMES: Record<ProviderID, string> = {
  apiInfo: "API Info",
  deepSeek: "DeepSeek",
  kimi: "Kimi",
  openRouter: "OpenRouter",
  miniMax: "MiniMax",
  bioMapCoding: "BioMap Coding",
};

export function formatMoney(money?: Money): string {
  if (!money) return "--";
  const amount = Number(money.amount);
  const value = Number.isFinite(amount)
    ? new Intl.NumberFormat(undefined, { maximumFractionDigits: 4 }).format(amount)
    : money.amount;
  return `${value} ${money.currency.toUpperCase()}`;
}

export function formatNumber(value?: number): string {
  return value === undefined ? "--" : new Intl.NumberFormat().format(value);
}

export function healthKind(health: AccountHealth | { kind: "stale" | "unavailable"; failure: string }): AccountHealth {
  return typeof health === "string" ? health : health.kind;
}

export function relativeTime(iso?: string): string | null {
  if (!iso) return null;
  const deltaSeconds = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
  if (deltaSeconds < 60) return "just now";
  if (deltaSeconds < 3600) return `${Math.floor(deltaSeconds / 60)}m ago`;
  if (deltaSeconds < 86_400) return `${Math.floor(deltaSeconds / 3600)}h ago`;
  return `${Math.floor(deltaSeconds / 86_400)}d ago`;
}
