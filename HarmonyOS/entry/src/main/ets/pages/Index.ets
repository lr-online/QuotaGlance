import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AccountService } from '../services/AccountService';
import { SnapshotStore, StoredSnapshot, formatSnapshotTexts } from '../storage/SnapshotStore';

@Entry
@Component
struct Index {
  @State balanceText: string = '--';
  @State statusText: string = '';
  @State updatedAtText: string = '';
  @State isRefreshing: boolean = false;

  private async reloadFromStore(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const service = await AccountService.create(context);
    await service.ensureLegacyMigration();
    const accounts = await service.loadAccounts();
    let stored: StoredSnapshot | null = null;
    if (accounts.length > 0) {
      const store = await SnapshotStore.create(context);
      stored = await store.load(accounts[0].id);
    }
    const texts = formatSnapshotTexts(stored);
    this.balanceText = texts['balanceText'];
    this.statusText = texts['statusText'];
    this.updatedAtText = texts['updatedAtText'];
  }

  private async refresh(): Promise<void> {
    this.isRefreshing = true;
    const context = getContext(this) as common.UIAbilityContext;
    const service = await AccountService.create(context);
    const accounts = await service.loadAccounts();
    if (accounts.length === 0) {
      this.isRefreshing = false;
      this.statusText = '请先在设置中录入 API Key';
      return;
    }
    try {
      await service.refreshAccount(accounts[0]);
    } catch (error) {
      // refreshAccount already marked the snapshot stale.
    }
    this.isRefreshing = false;
    await this.reloadFromStore();
  }

  aboutToAppear(): void {
    this.reloadFromStore();
  }

  build() {
    Column({ space: 16 }) {
      Text('QuotaGlance')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Text(this.balanceText)
        .fontSize(40)
        .fontWeight(FontWeight.Bold)

      Text(this.statusText)
        .fontSize(14)
        .fontColor('#666666')

      Text(this.updatedAtText)
        .fontSize(12)
        .fontColor('#999999')

      Button(this.isRefreshing ? '刷新中…' : '手动刷新')
        .enabled(!this.isRefreshing)
        .onClick(() => {
          this.refresh();
        })

      Button('设置')
        .onClick(() => {
          router.pushUrl({ url: 'pages/SettingsPage' });
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
