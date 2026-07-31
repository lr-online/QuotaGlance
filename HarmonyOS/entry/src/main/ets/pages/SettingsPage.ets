import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AccountService } from '../services/AccountService';
import { Account } from '../storage/AccountStore';

@Entry
@Component
struct SettingsPage {
  @State apiKey: string = '';
  @State message: string = '';

  private async findDeepSeekAccount(service: AccountService): Promise<Account | null> {
    const accounts = await service.loadAccounts();
    for (const account of accounts) {
      if (account.provider === 'deepSeek') {
        return account;
      }
    }
    return null;
  }

  build() {
    Column({ space: 16 }) {
      Text('DeepSeek API Key')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      TextInput({ placeholder: 'sk-...' })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.apiKey = value;
        })
        .width('100%')

      Button('保存')
        .enabled(this.apiKey.trim().length > 0)
        .onClick(async () => {
          const context = getContext(this) as common.UIAbilityContext;
          const service = await AccountService.create(context);
          const existing = await this.findDeepSeekAccount(service);
          if (existing) {
            await service.saveAccountKey(existing.id, this.apiKey);
            router.back();
            return;
          }
          try {
            await service.createAccount({ provider: 'deepSeek', displayName: '', apiKey: this.apiKey });
            router.back();
          } catch (error) {
            this.message = `保存失败:${(error as Error).message}`;
          }
        })

      Button('清除已保存的 Key')
        .onClick(async () => {
          const context = getContext(this) as common.UIAbilityContext;
          const service = await AccountService.create(context);
          const existing = await this.findDeepSeekAccount(service);
          if (existing) {
            await service.deleteAccount(existing.id);
            this.message = '已清除';
          } else {
            this.message = '无已保存的 Key';
          }
        })

      Text(this.message)
        .fontSize(12)
        .fontColor('#999999')
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
  }
}
