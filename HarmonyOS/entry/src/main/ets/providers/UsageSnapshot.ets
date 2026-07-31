// Shared usage snapshot model. Mirrors the Swift domain model in
// Sources/QuotaGlanceCore/Domain/UsageSnapshot.swift field-for-field, with
// monetary amounts carried as decimal strings and timestamps as epoch
// milliseconds (ArkTS has no Decimal/Date value semantics we want here).

export interface Money {
  amount: string;
  currency: string;
}

export interface MonetaryValue {
  label: string;
  value: Money;
}

export interface MonetaryBalance {
  label: string;
  available: Money;
  breakdown: MonetaryValue[];
}

export interface SpendingLimit {
  label: string;
  used?: Money;
  limit?: Money;
  remaining?: Money;
  resetDescription?: string;
}

export interface SpendSummary {
  today?: Money;
  week?: Money;
  month?: Money;
  total?: Money;
}

export interface QuotaWindow {
  label: string;
  used?: number;
  limit?: number;
  remaining?: number;
  unit: string;
  resetsAtMs?: number;
}

export interface UsageCounters {
  actualCost?: Money;
  requests?: number;
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheCreationTokens?: number;
  totalTokens?: number;
}

export interface DailyUsage {
  date: string;
  actualCost: Money;
  requests?: number;
  totalTokens?: number;
}

export interface ModelUsage {
  model: string;
  actualCost?: Money;
  requests?: number;
  totalTokens?: number;
}

export interface UsageSnapshot {
  provider: string;
  balances: MonetaryBalance[];
  spendingLimit?: SpendingLimit;
  spend?: SpendSummary;
  quotaWindows?: QuotaWindow[];
  today?: UsageCounters;
  total?: UsageCounters;
  dailyUsage?: DailyUsage[];
  modelUsage?: ModelUsage[];
  providerStatus?: string;
  metricsUnavailableReason?: string;
  receivedAtMs: number;
}
