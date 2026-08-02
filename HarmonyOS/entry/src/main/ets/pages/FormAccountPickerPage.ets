import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AccountService } from '../services/AccountService';
import { updateFormCard } from '../services/CardUpdater';
import { Account } from '../storage/AccountStore';
import { FormBindingStore } from '../storage/FormBindingStore';
import { providerDisplayName } from '../providers/ProviderCatalog';
import { friendlyErrorText } from '../utils/ErrorMapping';

interface PickerParams {
  formId: string;
}

@Entry
@Component
struct FormAccountPickerPage {
  @State accounts: Account[] = [];
  @State selectedAccountId: string = '';
  private formId: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as PickerParams;
    if (params !== undefined && params !== null && typeof params.formId === 'string') {
      this.formId = params.formId;
    }
  }

  onPageShow(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const service = await AccountService.create(context);
      await service.ensureLegacyMigration();
      this.accounts = await service.loadAccounts();
      const bindingStore = await FormBindingStore.create(context);
      const binding = await bindingStore.bindingFor(this.formId);
      this.selectedAccountId = binding?.accountId ?? '';
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
  }

  private async select(accountId: string): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const bindingStore = await FormBindingStore.create(context);
      await bindingStore.setAccount(this.formId, accountId.length > 0 ? accountId : null);
      await updateFormCard(context, this.formId);
      promptAction.showToast({
        message: context.resourceManager.getStringSync($r('app.string.widget_updated').id)
      });
      router.back();
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
  }

  @Builder
  optionRow(title: string, subtitle: string, selected: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.textPrimary'))
          .maxLines(1)
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(11)
            .fontColor($r('app.color.textSecondary'))
            .maxLines(1)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(selected ? '✓' : '')
        .fontSize(16)
        .fontColor($r('app.color.accentTeal'))
        .width(20)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.cardBackground'))
    .borderRadius(14)
    .border({
      width: 1,
      color: selected ? $r('app.color.accentTeal') : Color.Transparent
    })
    .onClick(onTap)
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor($r('app.color.textPrimary'))
          .padding({ right: 12, top: 2, bottom: 2 })
          .onClick(() => {
            router.back();
          })
        Text($r('app.string.widget_choose_account'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.textPrimary'))
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 20 })

      Text($r('app.string.widget_select_hint'))
        .fontSize(13)
        .fontColor($r('app.color.textSecondary'))
        .width('100%')
        .padding({ left: 20, right: 20 })

      Scroll() {
        Column({ space: 12 }) {
          this.optionRow(
            getContext(this).resourceManager.getStringSync($r('app.string.widget_show_overview').id),
            getContext(this).resourceManager.getStringSync($r('app.string.widget_open_target').id),
            this.selectedAccountId.length === 0,
            () => {
              this.select('');
            }
          )

          ForEach(this.accounts, (account: Account) => {
            this.optionRow(
              account.displayName,
              providerDisplayName(getContext(this), account.provider),
              this.selectedAccountId === account.id,
              () => {
                this.select(account.id);
              }
            )
          }, (account: Account) => account.id)
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 20 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.appBackground'))
  }
}
