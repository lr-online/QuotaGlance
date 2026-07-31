import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AccountService } from '../services/AccountService';
import { Account, AccountStore } from '../storage/AccountStore';
import { providerDisplayName } from '../providers/UsageProvider';
import { friendlyErrorText } from '../utils/ErrorMapping';

@Entry
@Component
struct AccountsPage {
  @State accounts: Account[] = [];

  onPageShow(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const service = await AccountService.create(context);
    this.accounts = await service.loadAccounts();
  }

  private async setEnabled(account: Account, enabled: boolean): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const store = await AccountStore.create(context);
      const updated: Account = {
        id: account.id,
        displayName: account.displayName,
        provider: account.provider,
        detectedProfile: account.detectedProfile,
        isEnabled: enabled,
        sortOrder: account.sortOrder,
        lowBalanceThreshold: account.lowBalanceThreshold
      };
      await store.update(updated);
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
    await this.reload();
  }

  private confirmDelete(account: Account): void {
    const context = getContext(this) as common.UIAbilityContext;
    AlertDialog.show({
      title: context.resourceManager.getStringSync($r('app.string.delete_confirm_title').id),
      message: context.resourceManager.getStringSync($r('app.string.delete_confirm_message').id),
      primaryButton: {
        value: context.resourceManager.getStringSync($r('app.string.cancel').id),
        action: () => {
        }
      },
      secondaryButton: {
        value: context.resourceManager.getStringSync($r('app.string.delete').id),
        fontColor: $r('app.color.danger'),
        action: () => {
          this.deleteAccount(account);
        }
      }
    });
  }

  private async deleteAccount(account: Account): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const service = await AccountService.create(context);
      await service.deleteAccount(account.id);
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
    await this.reload();
  }

  @Builder
  accountRow(account: Account) {
    Row() {
      Column({ space: 6 }) {
        Text(account.displayName)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.textPrimary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(providerDisplayName(account.provider))
          .fontSize(11)
          .fontColor($r('app.color.accentTeal'))
          .backgroundColor($r('app.color.accentTealTint'))
          .borderRadius(6)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: account.isEnabled })
        .selectedColor($r('app.color.accentTeal'))
        .onChange((isOn: boolean) => {
          this.setEnabled(account, isOn);
        })

      Text($r('app.string.delete'))
        .fontSize(13)
        .fontColor($r('app.color.danger'))
        .padding({ left: 12, top: 6, right: 4, bottom: 6 })
        .onClick(() => {
          this.confirmDelete(account);
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.cardBackground'))
    .borderRadius(14)
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor($r('app.color.textPrimary'))
          .padding({ right: 12, top: 2, bottom: 2 })
          .onClick(() => {
            router.back();
          })
        Text($r('app.string.manage_accounts'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.textPrimary'))
        Blank()
        Text($r('app.string.add_account'))
          .fontSize(15)
          .fontColor($r('app.color.accentTeal'))
          .padding(4)
          .onClick(() => {
            router.pushUrl({ url: 'pages/AccountEditorPage' });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 20 })

      if (this.accounts.length === 0) {
        Column() {
          Text($r('app.string.empty_accounts'))
            .fontSize(15)
            .fontColor($r('app.color.textSecondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.accounts, (account: Account) => {
            ListItem() {
              this.accountRow(account)
            }
          }, (account: Account) => account.id)
        }
        .width('100%')
        .constraintSize({ maxWidth: 560 })
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.appBackground'))
  }
}
