import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AccountService } from '../services/AccountService';
import { Account, AccountStore } from '../storage/AccountStore';
import { providerDisplayName } from '../providers/ProviderCatalog';
import { friendlyErrorText } from '../utils/ErrorMapping';
import { AccountDetailView } from '../components/AccountDetailView';

interface DetailParams {
  accountId: string;
}

@Entry
@Component
struct AccountDetailPage {
  @State title: string = '';
  @State providerName: string = '';
  @State canRefresh: boolean = false;
  @State refreshing: boolean = false;
  @State syncTick: number = 0;
  private accountId: string = '';
  private currentAccount: Account | null = null;

  aboutToAppear(): void {
    const params = router.getParams() as DetailParams;
    if (params !== undefined && params !== null && typeof params.accountId === 'string') {
      this.accountId = params.accountId;
    }
  }

  onPageShow(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    if (this.accountId.length === 0) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const accountStore = await AccountStore.create(context);
    const accounts = await accountStore.load();
    let found: Account | null = null;
    for (const account of accounts) {
      if (account.id === this.accountId) {
        found = account;
        break;
      }
    }
    this.currentAccount = found;
    if (found === null) {
      this.title = '';
      this.providerName = '';
      this.canRefresh = false;
      return;
    }
    this.title = found.displayName;
    this.providerName = providerDisplayName(getContext(this), found.provider);
    this.canRefresh = found.isEnabled;
  }

  private async refresh(): Promise<void> {
    const account = this.currentAccount;
    if (this.refreshing || account === null || !account.isEnabled) {
      return;
    }
    this.refreshing = true;
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const service = await AccountService.create(context);
      await service.refreshAccount(account);
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
    this.refreshing = false;
    this.syncTick += 1;
  }

  private openScreensaver(): void {
    router.pushUrl({ url: 'pages/ScreensaverPage', params: { accountId: this.accountId } });
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
        Text(this.title.length > 0 ? this.title : '…')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.textPrimary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.providerName.length > 0) {
          Text(this.providerName)
            .fontSize(11)
            .fontColor($r('app.color.accentTeal'))
            .backgroundColor($r('app.color.accentTealTint'))
            .borderRadius(6)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .margin({ left: 8 })
        }
        Text($r('app.string.screensaver'))
          .fontSize(15)
          .fontColor($r('app.color.accentTeal'))
          .padding(4)
          .margin({ left: 12 })
          .onClick(() => {
            this.openScreensaver();
          })
        if (this.canRefresh) {
          if (this.refreshing) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color($r('app.color.accentTeal'))
              .margin({ left: 12 })
          } else {
            Text('⟳')
              .fontSize(20)
              .fontColor($r('app.color.accentTeal'))
              .padding(4)
              .margin({ left: 8 })
              .onClick(() => {
                this.refresh();
              })
          }
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 20 })

      AccountDetailView({ accountId: this.accountId, dim: false, syncTick: this.syncTick })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.appBackground'))
  }
}
