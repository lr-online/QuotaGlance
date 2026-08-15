import { invoke } from "@tauri-apps/api/core";

import type { Locale, WidgetTarget } from "@/storage/types";

const hasTauriRuntime = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

function invokeOrPreview<T>(command: string, args: Record<string, unknown>, preview: T): Promise<T> {
  return hasTauriRuntime ? invoke<T>(command, args) : Promise.resolve(preview);
}

export type ProviderID = "apiInfo" | "deepSeek" | "kimi" | "openRouter" | "miniMax" | "bioMapCoding";
export type AccountHealth = "healthy" | "belowThreshold" | "stale" | "unavailable";

export interface ProviderProfile {
  region: "global" | "china" | "international";
  credential_kind: "standard" | "management" | "tokenPlan";
}

export interface Money {
  amount: string;
  currency: string;
}

export interface UsageCounters {
  actual_cost?: Money;
  requests?: number;
  input_tokens?: number;
  output_tokens?: number;
  cache_read_tokens?: number;
  cache_creation_tokens?: number;
  total_tokens?: number;
}

export interface ProviderUsageSnapshot {
  balances: Array<{ label: string; available: Money; breakdown: Array<{ label: string; value: Money }> }>;
  spending_limit?: { label: string; used?: Money; limit?: Money; remaining?: Money; reset_description?: string };
  spend: { today?: Money; week?: Money; month?: Money; total?: Money };
  quota_windows: Array<{ label: string; used?: string; limit?: string; remaining?: string; unit: string; resets_at?: string }>;
  today?: UsageCounters;
  total?: UsageCounters;
  daily_usage: Array<{ date: string; actual_cost: Money; requests?: number; total_tokens?: number }>;
  model_usage: Array<{ model: string; actual_cost?: Money; requests?: number; total_tokens?: number }>;
  provider_status?: string;
  metrics_unavailable_reason?: string;
  received_at: string;
}

export interface AccountSummary {
  id: string;
  display_name: string;
  provider: ProviderID;
  detected_profile?: ProviderProfile;
  is_enabled: boolean;
  sort_order: number;
  low_balance_threshold?: string;
  alert_episode_active: boolean;
}

export interface AccountSnapshot {
  account_id: string;
  display_name: string;
  provider: ProviderID;
  detected_profile?: ProviderProfile;
  low_balance_threshold?: string;
  usage?: ProviderUsageSnapshot;
  health: AccountHealth | { kind: "stale" | "unavailable"; failure: string };
  last_success_at?: string;
}

export interface AggregateSnapshot {
  balances: Money[];
  today_actual_cost?: Money;
  today_requests?: number;
  daily_usage: Array<{ date: string; actual_cost: Money; requests?: number; total_tokens?: number }>;
  accounts: AccountSnapshot[];
  is_partial: boolean;
}

export interface RefreshReport {
  total: number;
  failures: number;
  last_failure_reason: string | null;
}

export interface PreferencesDTO {
  refresh_interval_minutes: number;
  locale: Locale;
  notifications_enabled: boolean;
  launch_at_login: boolean;
  default_widget_target: WidgetTarget;
}

const PREVIEW_PREFERENCES: PreferencesDTO = {
  refresh_interval_minutes: 15,
  locale: "system",
  notifications_enabled: false,
  launch_at_login: false,
  default_widget_target: { kind: "defaultAccount" },
};

const EMPTY_AGGREGATE: AggregateSnapshot = {
  balances: [],
  daily_usage: [],
  accounts: [],
  is_partial: false,
};

export const commands = {
  listAccounts: () => invokeOrPreview<AccountSummary[]>("list_accounts", {}, []),
  getAccountSnapshot: (id: string) => invokeOrPreview<AccountSnapshot | null>("get_account_snapshot", { id }, null),
  getAggregateSnapshot: () => invokeOrPreview<AggregateSnapshot>("get_aggregate_snapshot", {}, EMPTY_AGGREGATE),
  addAccount: (request: {
    display_name: string;
    provider: ProviderID;
    api_key: string;
    detected_profile: ProviderProfile;
    low_balance_threshold?: string;
  }) => invokeOrPreview<string>("add_account", { request }, "browser-preview"),
  detectProviderProfile: (provider: ProviderID, apiKey: string) =>
    invokeOrPreview<ProviderProfile>("detect_provider_profile", { provider, apiKey }, { region: "global", credential_kind: "standard" }),
  updateAccount: (request: {
    id: string;
    display_name?: string;
    detected_profile?: ProviderProfile;
    low_balance_threshold?: string | null;
    is_enabled?: boolean;
  }) => invokeOrPreview<void>("update_account", { request }, undefined),
  deleteAccount: (id: string) => invokeOrPreview<boolean>("delete_account", { id }, true),
  replaceAccountCredential: (id: string, apiKey: string) =>
    invokeOrPreview<void>("replace_account_credential", { id, apiKey }, undefined),
  refreshAll: () => invokeOrPreview<RefreshReport>("refresh_all", {}, { total: 0, failures: 0, last_failure_reason: null }),
  refreshAccount: (id: string) => invokeOrPreview<AccountSnapshot>("refresh_account", { id }, null as unknown as AccountSnapshot),
  getPreferences: () => invokeOrPreview<PreferencesDTO>("get_preferences", {}, PREVIEW_PREFERENCES),
  updatePreferences: (preferences: PreferencesDTO) =>
    invokeOrPreview<void>("update_preferences", { preferences }, undefined),
  openWindow: (label: string) => invokeOrPreview<void>("open_window_by_label", { label }, undefined),
  showNotification: (title: string, body: string) =>
    invokeOrPreview<void>("show_notification", { title, body }, undefined),
  quit: () => invokeOrPreview<void>("quit_app", {}, undefined),
  getIntentPayload: () => invokeOrPreview<string | null>("get_intent_payload", {}, null),
};

export const events = {
  onDeepLink: async (callback: (url: string) => void) => {
    if (!hasTauriRuntime) return () => undefined;
    const { listen } = await import("@tauri-apps/api/event");
    return listen<string>("deep-link", (event) => callback(event.payload));
  },
  onSnapshotsUpdated: async (callback: () => void) => {
    if (!hasTauriRuntime) return () => undefined;
    const { listen } = await import("@tauri-apps/api/event");
    return listen("snapshots-updated", () => callback());
  },
  onMenuRefreshAll: async (callback: () => void) => {
    if (!hasTauriRuntime) return () => undefined;
    const { listen } = await import("@tauri-apps/api/event");
    return listen("menu-refresh-all", () => callback());
  },
};
