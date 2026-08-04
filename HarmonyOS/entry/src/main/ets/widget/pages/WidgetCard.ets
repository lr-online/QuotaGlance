import { common } from '@kit.AbilityKit';
import { switchFormAccount } from '../../services/CardUpdater';
import { SwipeDirection } from '../FormAccountNavigation';

@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('formId') formId: string = '';
  @LocalStorageProp('formDimension') formDimension: string = '2';
  @LocalStorageProp('mode') mode: string = 'aggregate';
  @LocalStorageProp('title') title: string = '总览';
  @LocalStorageProp('balanceText') balanceText: string = '--';
  @LocalStorageProp('statusText') statusText: string = '';
  @LocalStorageProp('updatedAtText') updatedAtText: string = '';
  @LocalStorageProp('todayText') todayText: string = '';
  @LocalStorageProp('messageText') messageText: string = '';
  @LocalStorageProp('messageSeverity') messageSeverity: string = '';
  @LocalStorageProp('rowsText') rowsText: string = '';
  @LocalStorageProp('targetAccountId') targetAccountId: string = '';
  @State private swipeOffsetX: number = 0;
  @State private swipeOffsetY: number = 0;
  private switchingAccount: boolean = false;

  private dimension(): number {
    const parsed = Number(this.formDimension);
    if (parsed >= 1 && parsed <= 4) {
      return parsed;
    }
    return 2;
  }

  private rows(): string[] {
    if (this.rowsText.length === 0) {
      return [];
    }
    return this.rowsText.split('\n').filter((row: string) => row.length > 0);
  }

  private openApp(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility'
    });
  }

  private messageColor(): string {
    if (this.messageSeverity === 'error') {
      return '#FF6B6B';
    }
    if (this.messageSeverity === 'warning') {
      return '#F5C15D';
    }
    return '#8FE8DF';
  }

  private resetSwipe(): void {
    this.swipeOffsetX = 0;
    this.swipeOffsetY = 0;
  }

  private finishSwipe(): void {
    const offsetX = this.swipeOffsetX;
    const offsetY = this.swipeOffsetY;
    this.resetSwipe();
    if (this.switchingAccount || Math.abs(offsetX) < 48 || Math.abs(offsetX) <= Math.abs(offsetY)) {
      return;
    }

    const direction: SwipeDirection = offsetX < 0 ? 'left' : 'right';
    this.switchingAccount = true;
    const context = getContext(this) as common.Context;
    switchFormAccount(context, this.formId, direction)
      .finally(() => {
        this.switchingAccount = false;
      });
  }

  @Builder
  compactBody() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(11)
        .fontColor('#99A1B3')
        .maxLines(1)
      Text(this.balanceText)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#57E0D6')
        .maxLines(1)
      if (this.todayText.length > 0) {
        Text(this.todayText)
          .fontSize(11)
          .fontColor('#CFD6E6')
          .maxLines(1)
      }
      if (this.messageText.length > 0) {
        Text(this.messageText)
          .fontSize(10)
          .fontColor(this.messageColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(10)
          .fontColor('#99A1B3')
          .maxLines(1)
      }
      if (this.updatedAtText.length > 0) {
        Text(this.updatedAtText)
          .fontSize(10)
          .fontColor('#54607A')
          .maxLines(1)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  listBody() {
    Column({ space: 8 }) {
      Row() {
        Text(this.title)
          .fontSize(12)
          .fontColor('#99A1B3')
          .layoutWeight(1)
          .maxLines(1)
        if (this.statusText.length > 0) {
          Text(this.statusText)
            .fontSize(10)
            .fontColor('#99A1B3')
            .maxLines(1)
        }
      }
      .width('100%')

      Text(this.balanceText)
        .fontSize(this.dimension() === 4 ? 24 : 20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#57E0D6')
        .maxLines(2)

      if (this.todayText.length > 0) {
        Text(this.todayText)
          .fontSize(11)
          .fontColor('#CFD6E6')
          .maxLines(2)
      }

      if (this.messageText.length > 0) {
        Text(this.messageText)
          .fontSize(11)
          .fontColor(this.messageColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (this.rows().length > 0) {
        Column({ space: 4 }) {
          ForEach(this.rows(), (row: string) => {
            Text(row)
              .fontSize(10)
              .fontColor('#CFD6E6')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }, (row: string) => row)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      } else {
        Blank()
          .layoutWeight(1)
      }

      if (this.updatedAtText.length > 0) {
        Text(this.updatedAtText)
          .fontSize(10)
          .fontColor('#54607A')
          .maxLines(1)
          .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 8 }) {
      if (this.dimension() >= 3) {
        this.listBody()
      } else {
        this.compactBody()
      }

    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding(12)
    .backgroundColor('#12161F')
    .borderRadius(16)
    .onClick(() => {
      this.openApp();
    })
    .gesture(
      PanGesture()
        .onActionUpdate((event?: GestureEvent) => {
          if (event !== undefined) {
            this.swipeOffsetX = event.offsetX;
            this.swipeOffsetY = event.offsetY;
          }
        })
        .onActionEnd(() => {
          this.finishSwipe();
        })
        .onActionCancel(() => {
          this.resetSwipe();
        })
    )
  }
}
