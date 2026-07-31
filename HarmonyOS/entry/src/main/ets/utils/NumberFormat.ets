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

const TOKEN_SUFFIXES: string[] = ['K', 'M', 'G', 'T', 'P'];

// Token quantities: below 1000 render as the plain integer; at or above
// 1000, scale by powers of 1000 with a K/M/G/T/P suffix and exactly 2
// decimals (1234 → "1.23K", 6655443322 → "6.66G").
export function formatTokenCount(n: number): string {
  if (Math.abs(n) < 1000) {
    return n % 1 === 0 ? `${n}` : n.toFixed(2);
  }
  let scaled = n;
  let tier = -1;
  while (Math.abs(scaled) >= 1000 && tier < TOKEN_SUFFIXES.length - 1) {
    scaled /= 1000;
    tier += 1;
  }
  return `${scaled.toFixed(2)}${TOKEN_SUFFIXES[tier]}`;
}
