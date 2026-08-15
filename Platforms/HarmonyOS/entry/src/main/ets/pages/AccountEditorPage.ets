import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import {
  AccountService,
  CreateAccountInput,
  UpdateAccountInput
} from '../services/AccountService';
import { ALL_PROVIDER_IDS, ProviderID, ProviderProfile } from '../providers/UsageProvider';
import { Account } from '../storage/AccountStore';
import { providerDescriptor, providerDisplayName } from '../providers/ProviderCatalog';
import { friendlyErrorText } from '../utils/ErrorMapping';
import { resolveProfileDescription } from '../utils/ProfileDescriptionL10n';

// Threshold support comes from the provider spec descriptor; pre-detection
// there is no profile, matching the spec's `undetected` rule.
function keyPlaceholder(id: ProviderID): string {
  if (id === 'openRouter') {
    return 'sk-or-...';
  }
  if (id === 'miniMax') {
    return 'MiniMax Token Plan Key';
  }
  return 'sk-...';
}

function isValidThreshold(value: string): boolean {
  return /^\d+(\.\d+)?$/.test(value);
}

interface AccountEditorParams {
  accountId?: string;
}

@Entry
@Component
struct AccountEditorPage {
  @State selectedProvider: ProviderID = 'deepSeek';
  @State name: string = '';
  @State apiKey: string = '';
  @State threshold: string = '';
  @State isEnabled: boolean = true;
  @State saving: boolean = false;
  @State loading: boolean = false;
  @State errorText: string = '';
  private editingAccountId: string = '';
  private originalProvider: ProviderID = 'deepSeek';
  private existingProfile?: ProviderProfile;

  aboutToAppear(): void {
    const params = router.getParams() as AccountEditorParams;
    if (params === undefined || params === null || typeof params.accountId !== 'string'
      || params.accountId.length === 0) {
      return;
    }
    this.editingAccountId = params.accountId;
    this.loadExistingAccount();
  }

  private async loadExistingAccount(): Promise<void> {
    this.loading = true;
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const service = await AccountService.create(context);
      const accounts = await service.loadAccounts();
      const account = accounts.find((candidate: Account) => candidate.id === this.editingAccountId);
      if (account === undefined) {
        throw new Error('accountNotFound');
      }
      this.selectedProvider = account.provider;
      this.originalProvider = account.provider;
      this.existingProfile = account.detectedProfile;
      this.name = account.displayName;
      this.threshold = account.lowBalanceThreshold ?? '';
      this.isEnabled = account.isEnabled;
    } catch (error) {
      this.errorText = friendlyErrorText(context, (error as Error).message);
    } finally {
      this.loading = false;
    }
  }

  private thresholdInvalid(): boolean {
    return this.threshold.trim().length > 0 && !isValidThreshold(this.threshold.trim());
  }

  private canSave(): boolean {
    const keyRequired = this.editingAccountId.length === 0
      || this.selectedProvider !== this.originalProvider;
    return !this.loading && !this.saving
      && (!keyRequired || this.apiKey.trim().length > 0)
      && !this.thresholdInvalid();
  }

  private supportsLowBalanceThreshold(): boolean {
    const profile = this.selectedProvider === this.originalProvider ? this.existingProfile : undefined;
    return providerDescriptor(getContext(this), this.selectedProvider).supportsLowBalanceThreshold(profile);
  }

  private async save(): Promise<void> {
    if (!this.canSave()) {
      return;
    }
    this.saving = true;
    this.errorText = '';
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const service = await AccountService.create(context);
      if (this.editingAccountId.length > 0) {
        const input: UpdateAccountInput = {
          provider: this.selectedProvider,
          displayName: this.name.trim(),
          apiKey: this.apiKey.trim(),
          lowBalanceThreshold: this.threshold.trim(),
          isEnabled: this.isEnabled
        };
        await service.updateAccount(this.editingAccountId, input);
      } else {
        const input: CreateAccountInput = {
          provider: this.selectedProvider,
          displayName: this.name.trim(),
          apiKey: this.apiKey.trim(),
          lowBalanceThreshold: this.threshold.trim()
        };
        await service.createAccount(input);
      }
      const messageId = this.editingAccountId.length > 0
        ? $r('app.string.account_updated').id : $r('app.string.account_added').id;
      promptAction.showToast({ message: context.resourceManager.getStringSync(messageId) });
      router.back();
    } catch (error) {
      this.errorText = friendlyErrorText(context, (error as Error).message);
      this.saving = false;
    }
  }

  @Builder
  providerChip(id: ProviderID) {
    Text(providerDisplayName(getContext(this), id))
      .fontSize(14)
      .fontColor(this.selectedProvider === id ? $r('app.color.accentTeal') : $r('app.color.textSecondary'))
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.selectedProvider === id ? $r('app.color.accentTealTint') : $r('app.color.cardBackground'))
      .borderRadius(18)
      .border({
        width: 1,
        color: this.selectedProvider === id ? $r('app.color.accentTeal') : $r('app.color.slateSecondary')
      })
      .onClick(() => {
        if (this.loading || this.saving) {
          return;
        }
        this.selectedProvider = id;
        if (!this.supportsLowBalanceThreshold()) {
          this.threshold = '';
        }
        this.errorText = '';
      })
  }

  @Builder
  fieldLabel(text: Resource) {
    Text(text)
      .fontSize(13)
      .fontColor($r('app.color.textSecondary'))
      .margin({ bottom: 8 })
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
        Text(this.editingAccountId.length > 0
          ? $r('app.string.edit_account') : $r('app.string.add_account'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.textPrimary'))
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 20 })

      Scroll() {
        Column({ space: 20 }) {
          Column() {
            this.fieldLabel($r('app.string.provider_label'))
            Scroll() {
              Row({ space: 8 }) {
                ForEach(ALL_PROVIDER_IDS, (id: ProviderID) => {
                  this.providerChip(id)
                }, (id: ProviderID) => id)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            Text(resolveProfileDescription(
              getContext(this) as common.Context,
              providerDescriptor(getContext(this), this.selectedProvider).profileDescription(
                this.selectedProvider === this.originalProvider ? this.existingProfile : undefined)
            ))
              .fontSize(12)
              .fontColor($r('app.color.textSecondary'))
              .margin({ top: 8 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column() {
            this.fieldLabel($r('app.string.name_label'))
            TextInput({ placeholder: providerDisplayName(getContext(this), this.selectedProvider), text: this.name })
              .placeholderColor($r('app.color.slateSecondary'))
              .fontColor($r('app.color.textPrimary'))
              .backgroundColor($r('app.color.cardBackground'))
              .borderRadius(10)
              .height(44)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.name = value;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column() {
            this.fieldLabel(this.editingAccountId.length > 0
              ? $r('app.string.replacement_api_key_label') : $r('app.string.api_key_label'))
            TextInput({
              placeholder: this.editingAccountId.length > 0
                && this.selectedProvider === this.originalProvider
                ? $r('app.string.replacement_api_key_placeholder') : keyPlaceholder(this.selectedProvider),
              text: this.apiKey
            })
              .type(InputType.Password)
              .placeholderColor($r('app.color.slateSecondary'))
              .fontColor($r('app.color.textPrimary'))
              .backgroundColor($r('app.color.cardBackground'))
              .borderRadius(10)
              .height(44)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.apiKey = value;
                this.errorText = '';
              })
            if (this.errorText.length > 0) {
              Text(this.errorText)
                .fontSize(12)
                .fontColor($r('app.color.danger'))
                .margin({ top: 6 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          if (this.supportsLowBalanceThreshold()) {
            Column() {
              this.fieldLabel($r('app.string.threshold_label'))
              TextInput({ placeholder: $r('app.string.threshold_placeholder'), text: this.threshold })
                .type(InputType.NUMBER_DECIMAL)
                .placeholderColor($r('app.color.slateSecondary'))
                .fontColor($r('app.color.textPrimary'))
                .backgroundColor($r('app.color.cardBackground'))
                .borderRadius(10)
                .height(44)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.threshold = value;
                })
              if (this.thresholdInvalid()) {
                Text($r('app.string.threshold_invalid'))
                  .fontSize(12)
                  .fontColor($r('app.color.danger'))
                  .margin({ top: 6 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }

          if (this.editingAccountId.length > 0) {
            Row() {
              Text($r('app.string.enabled_label'))
                .fontSize(14)
                .fontColor($r('app.color.textPrimary'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.isEnabled })
                .selectedColor($r('app.color.accentTeal'))
                .onChange((value: boolean) => {
                  this.isEnabled = value;
                })
            }
            .width('100%')
          }

          if (this.saving) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.accentTeal'))
              Text($r('app.string.verifying_key'))
                .fontSize(13)
                .fontColor($r('app.color.textSecondary'))
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
          }

          Button($r('app.string.save'))
            .width('100%')
            .height(46)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.appBackground'))
            .backgroundColor($r('app.color.accentTeal'))
            .borderRadius(23)
            .opacity(this.canSave() ? 1 : 0.4)
            .enabled(this.canSave())
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .width('100%')
      .constraintSize({ maxWidth: 560 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.appBackground'))
  }
}
