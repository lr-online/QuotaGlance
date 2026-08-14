// Pure account selection rules for widget horizontal swipes. Keeping this
// module Kit-free makes the wrapping behavior independently testable.

export interface WidgetAccount {
  id: string;
  isEnabled: boolean;
  sortOrder: number;
}

export type SwipeDirection = 'left' | 'right';

export function selectAdjacentAccount(
  accounts: WidgetAccount[],
  currentAccountId: string | undefined,
  direction: SwipeDirection
): WidgetAccount | null {
  const enabled = accounts.filter((account: WidgetAccount) => account.isEnabled);
  enabled.sort((a: WidgetAccount, b: WidgetAccount) => a.sortOrder - b.sortOrder);
  if (enabled.length === 0) {
    return null;
  }

  const currentIndex = currentAccountId === undefined
    ? -1
    : enabled.findIndex((account: WidgetAccount) => account.id === currentAccountId);
  if (currentIndex < 0) {
    return direction === 'left' ? enabled[0] : enabled[enabled.length - 1];
  }

  const step = direction === 'left' ? 1 : -1;
  const nextIndex = (currentIndex + step + enabled.length) % enabled.length;
  return enabled[nextIndex];
}
