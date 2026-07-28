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

export interface UsageSnapshot {
  balances: MonetaryBalance[];
  providerStatus: string;
  receivedAtMs: number;
}
