import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fetchBalance } from '../network/HttpClient';
import { parseBalance } from '../providers/DeepSeekProvider';
import { KeyRepository } from '../storage/KeyRepository';
import { SnapshotStore, formatSnapshotTexts } from '../storage/SnapshotStore';

@Entry
@Component
struct Index {
  @State balanceText: string = '--';
  @State statusText: string = '';
  @State updatedAtText: string = '';
  @State isRefreshing: boolean = false;

  private async reloadFromStore(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const store = await SnapshotStore.create(context);
    const texts = formatSnapshotTexts(await store.load());
    this.balanceText = texts['balanceText'];
    this.statusText = texts['statusText'];
    this.updatedAtText = texts['updatedAtText'];
  }

  private async refresh(): Promise<void> {
    this.isRefreshing = true;
    const apiKey = await KeyRepository.load();
    if (!apiKey) {
      this.isRefreshing = false;
      this.statusText = '请先在设置中录入 API Key';
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const store = await SnapshotStore.create(context);
    try {
      const body = await fetchBalance(apiKey);
      const snapshot = parseBalance(body, Date.now());
      await store.save(snapshot);
    } catch (error) {
      await store.markStale();
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
