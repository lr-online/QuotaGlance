// Display-layer number formatting. Amounts are stored/parsed as decimal
// strings everywhere; these helpers only shape how they render.

// Monetary amounts always render with exactly 2 decimals. Unparseable
// input is returned unchanged so provider quirks still surface.
export function formatAmount(amount: string): string {
  const value = parseFloat(amount);
  if (!isNaN(value) && isFinite(value)) {
    return value.toFixed(2);
  }
  return amount;
}

// Integer counters (requests/tokens): render as-is, no decimals, no
// thousands separators. Fractional input falls back to 2 decimals.
export function formatCompactCount(n: number): string {
  if (n % 1 === 0) {
    return `${n}`;
  }
  return n.toFixed(2);
}

// Quota-window numbers (remaining/limit/used, unit like 次/个): integers
// as-is; a fractional part renders with 2 decimals.
export function formatQuotaValue(n: number): string {
  if (n % 1 === 0) {
    return `${n}`;
  }
  return n.toFixed(2);
}
