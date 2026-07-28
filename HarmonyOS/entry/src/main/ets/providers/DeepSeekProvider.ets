import { MonetaryBalance, MonetaryValue, Money, UsageSnapshot } from './UsageSnapshot';

interface BalanceInfoPayload {
  currency: string;
  total_balance?: string | number;
  granted_balance?: string | number;
  topped_up_balance?: string | number;
}

interface BalanceResponsePayload {
  is_available: boolean;
  balance_infos?: BalanceInfoPayload[];
}

function decimalString(raw: string | number | undefined): string | null {
  if (raw === undefined) {
    return null;
  }
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? String(raw) : null;
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return null;
  }
  return Number.isFinite(Number(trimmed)) ? trimmed : null;
}

export function parseBalance(responseBody: string, receivedAtMs: number): UsageSnapshot {
  let payload: BalanceResponsePayload;
  try {
    payload = JSON.parse(responseBody) as BalanceResponsePayload;
  } catch (error) {
    throw new Error('invalidResponse');
  }

  const infos = payload.balance_infos;
  if (!infos || infos.length === 0) {
    throw new Error('invalidResponse');
  }

  const balances: MonetaryBalance[] = infos.map((info: BalanceInfoPayload) => {
    const currency = info.currency.trim().toUpperCase();
    const total = decimalString(info.total_balance);
    if (currency.length === 0 || total === null) {
      throw new Error('invalidResponse');
    }

    const breakdown: MonetaryValue[] = [];
    const granted = decimalString(info.granted_balance);
    if (granted !== null) {
      breakdown.push({ label: 'Granted', value: { amount: granted, currency: currency } });
    }
    const toppedUp = decimalString(info.topped_up_balance);
    if (toppedUp !== null) {
      breakdown.push({ label: 'Topped up', value: { amount: toppedUp, currency: currency } });
    }

    const available: Money = { amount: total, currency: currency };
    return { label: 'Balance', available: available, breakdown: breakdown };
  });

  return {
    balances: balances,
    providerStatus: payload.is_available ? 'active' : 'unavailable',
    receivedAtMs: receivedAtMs
  };
}
