import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AccountService } from '../services/AccountService';
import { Account } from '../storage/AccountStore';
import { SnapshotStore, StoredSnapshot } from '../storage/SnapshotStore';
import { providerDisplayName } from '../providers/UsageProvider';
import { friendlyErrorText } from '../utils/ErrorMapping';

type PrimaryKind = 'balance' | 'limit' | 'quota' | 'status' | 'empty';

interface CardModel {
  accountId: string;
  displayName: string;
  providerName: string;
  isEnabled: boolean;
  primaryKind: PrimaryKind;
  primaryText: string;
  primaryUnit: string;
  quotaUsed: number;
  quotaTotal: number;
  secondaryText: string;
  secondaryWarning: boolean;
}

function pad2(value: number): string {
  return value.toString().padStart(2, '0');
}

function formatUpdatedAt(context: common.Context, ms: number): string {
  const prefix = context.resourceManager.getStringSync($r('app.string.updated_prefix').id);
  const date = new Date(ms);
  const now = new Date();
  const hhmm = `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  const sameDay = date.getFullYear() === now.getFullYear()
    && date.getMonth() === now.getMonth()
    && date.getDate() === now.getDate();
  if (sameDay) {
    return `${prefix} ${hhmm}`;
  }
  return `${prefix} ${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${hhmm}`;
}

function buildCardModel(context: common.Context, account: Account, stored: StoredSnapshot | null): CardModel {
  const model: CardModel = {
    accountId: account.id,
    displayName: account.displayName,
    providerName: providerDisplayName(account.provider),
    isEnabled: account.isEnabled,
    primaryKind: 'empty',
    primaryText: context.resourceManager.getStringSync($r('app.string.no_data').id),
    primaryUnit: '',
    quotaUsed: 0,
    quotaTotal: 1,
    secondaryText: context.resourceManager.getStringSync($r('app.string.not_refreshed').id),
    secondaryWarning: false
  };
  if (stored === null) {
    return model;
  }
  const snapshot = stored.snapshot;
  if (snapshot.balances.length > 0) {
    const balance = snapshot.balances[0];
    model.primaryKind = 'balance';
    model.primaryText = balance.available.amount;
    model.primaryUnit = balance.available.currency;
  } else if (snapshot.spendingLimit !== undefined) {
    const limit = snapshot.spendingLimit;
    const remaining = limit.remaining;
    const used = limit.used;
    model.primaryKind = 'limit';
    model.primaryText = remaining !== undefined ? remaining.amount : (used !== undefined ? used.amount : '--');
    const currency = remaining !== undefined ? remaining.currency
      : (used !== undefined ? used.currency : (limit.limit !== undefined ? limit.limit.currency : ''));
    model.primaryUnit = limit.limit !== undefined ? `/ ${limit.limit.amount} ${currency}` : currency;
  } else if (snapshot.quotaWindows !== undefined && snapshot.quotaWindows.length > 0) {
    const window = snapshot.quotaWindows[0];
    model.primaryKind = 'quota';
    const used = window.used ?? ((window.limit !== undefined && window.remaining !== undefined)
      ? window.limit - window.remaining : 0);
    const total = window.limit ?? ((window.used ?? 0) + (window.remaining ?? 0));
    model.primaryText = window.remaining !== undefined ? `${window.remaining}` : `${used}`;
    model.primaryUnit = window.limit !== undefined ? `/ ${window.limit} ${window.unit}` : window.unit;
    model.quotaTotal = total > 0 ? total : 1;
    model.quotaUsed = Math.min(Math.max(used, 0), model.quotaTotal);
  } else {
    model.primaryKind = 'status';
    model.primaryText = snapshot.metricsUnavailableReason ?? snapshot.providerStatus ??
      context.resourceManager.getStringSync($r('app.string.no_data').id);
  }
  if (stored.isStale) {
    model.secondaryText = context.resourceManager.getStringSync($r('app.string.stale_text').id);
    model.secondaryWarning = true;
  } else if (model.primaryKind === 'status' && snapshot.metricsUnavailableReason !== undefined) {
    model.secondaryText = snapshot.providerStatus ?? '';
    model.secondaryWarning = false;
  } else {
    model.secondaryText = formatUpdatedAt(context, snapshot.receivedAtMs);
    model.secondaryWarning = false;
  }
  return model;
}

@Entry
@Component
struct Index {
  @State cards: CardModel[] = [];
  @State refreshingAll: boolean = false;

  onPageShow(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const service = await AccountService.create(context);
    await service.ensureLegacyMigration();
    const accounts = await service.loadAccounts();
    const store = await SnapshotStore.create(context);
    const models: CardModel[] = [];
    for (const account of accounts) {
      const stored = await store.load(account.id);
      models.push(buildCardModel(context, account, stored));
    }
    this.cards = models;
  }

  private async refreshAll(): Promise<void> {
    if (this.refreshingAll) {
      return;
    }
    this.refreshingAll = true;
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const service = await AccountService.create(context);
      await service.refreshAllEnabled();
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
    this.refreshingAll = false;
    await this.reload();
  }

  private openDetail(item: CardModel): void {
    router.pushUrl({ url: 'pages/AccountDetailPage', params: { accountId: item.accountId } });
  }

  @Builder
  onboardingBody() {
    Column({ space: 0 }) {
      Stack() {
        Progress({ value: 72, total: 100, type: ProgressType.Ring })
          .width(104)
          .height(104)
          .color($r('app.color.accentTeal'))
          .backgroundColor($r('app.color.slateSecondary'))
        Circle()
          .width(10)
          .height(10)
          .fill($r('app.color.highlightCyan'))
          .offset({ x: 0, y: -47 })
      }

      Text('QuotaGlance')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.textPrimary'))
        .margin({ top: 24 })

      Text($r('app.string.onboarding_tagline'))
        .fontSize(15)
        .fontColor($r('app.color.textSecondary'))
        .margin({ top: 10 })

      Text($r('app.string.onboarding_hint'))
        .fontSize(12)
        .fontColor($r('app.color.slateSecondary'))
        .margin({ top: 6 })

      Button($r('app.string.add_account'))
        .width(200)
        .height(44)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.appBackground'))
        .backgroundColor($r('app.color.accentTeal'))
        .borderRadius(22)
        .margin({ top: 36 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/AccountEditorPage' });
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  accountCard(item: CardModel) {
    Column({ space: 12 }) {
      Row() {
        Text(item.displayName)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.textPrimary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(item.providerName)
          .fontSize(11)
          .fontColor($r('app.color.accentTeal'))
          .backgroundColor($r('app.color.accentTealTint'))
          .borderRadius(6)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      }
      .width('100%')

      if (item.primaryKind === 'balance' || item.primaryKind === 'limit') {
        Row() {
          Text(item.primaryText)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.textPrimary'))
            .maxLines(1)
          if (item.primaryUnit.length > 0) {
            Text(item.primaryUnit)
              .fontSize(14)
              .fontColor($r('app.color.textSecondary'))
              .margin({ left: 4 })
          }
        }
        .alignItems(VerticalAlign.Bottom)
      } else if (item.primaryKind === 'quota') {
        Column({ space: 8 }) {
          Row() {
            Text(item.primaryText)
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.accentTeal'))
              .maxLines(1)
            if (item.primaryUnit.length > 0) {
              Text(item.primaryUnit)
                .fontSize(14)
                .fontColor($r('app.color.textSecondary'))
                .margin({ left: 4 })
            }
          }
          .alignItems(VerticalAlign.Bottom)

          Progress({ value: item.quotaUsed, total: item.quotaTotal, type: ProgressType.Linear })
            .color($r('app.color.accentTeal'))
            .backgroundColor($r('app.color.slateSecondary'))
            .height(4)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        Text(item.primaryText)
          .fontSize(15)
          .fontColor($r('app.color.textSecondary'))
          .maxLines(2)
          .width('100%')
          .textAlign(TextAlign.Start)
      }

      if (item.secondaryText.length > 0) {
        Text(item.secondaryText)
          .fontSize(12)
          .fontColor(item.secondaryWarning ? $r('app.color.warning') : $r('app.color.textSecondary'))
          .maxLines(1)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.cardBackground'))
    .borderRadius(14)
    .opacity(item.isEnabled ? 1 : 0.5)
    .onClick(() => {
      this.openDetail(item);
    })
  }

  @Builder
  dashboardBody() {
    List({ space: 12 }) {
      ForEach(this.cards, (item: CardModel) => {
        ListItem() {
          this.accountCard(item)
        }
      }, (item: CardModel) => item.accountId)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16 })
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      Row() {
        Text('QuotaGlance')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.textPrimary'))
        Blank()
        if (this.cards.length > 0) {
          if (this.refreshingAll) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('app.color.accentTeal'))
              .margin({ right: 16 })
          } else {
            Text('⟳')
              .fontSize(20)
              .fontColor($r('app.color.accentTeal'))
              .margin({ right: 16 })
              .padding(4)
              .onClick(() => {
                this.refreshAll();
              })
          }
        }
        Text($r('app.string.manage_accounts'))
          .fontSize(15)
          .fontColor($r('app.color.accentTeal'))
          .padding(4)
          .onClick(() => {
            router.pushUrl({ url: 'pages/AccountsPage' });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 20, right: 20 })

      if (this.cards.length === 0) {
        this.onboardingBody()
      } else {
        this.dashboardBody()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.appBackground'))
  }
}
