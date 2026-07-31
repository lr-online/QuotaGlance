@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('balanceText') balanceText: string = '--';
  @LocalStorageProp('statusText') statusText: string = '';
  @LocalStorageProp('updatedAtText') updatedAtText: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.balanceText)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.accentTeal'))
        .maxLines(1)

      Text(this.statusText)
        .fontSize(12)
        .fontColor($r('app.color.textSecondary'))
        .maxLines(1)

      Text(this.updatedAtText)
        .fontSize(10)
        .fontColor($r('app.color.slateSecondary'))
        .maxLines(1)

      Button($r('app.string.open_app'))
        .fontSize(12)
        .fontColor($r('app.color.appBackground'))
        .backgroundColor($r('app.color.accentTeal'))
        .borderRadius(14)
        .height(28)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility'
          });
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(12)
    .backgroundColor($r('app.color.appBackground'))
    .borderRadius(16)
  }
}
