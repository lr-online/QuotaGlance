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
        .maxLines(1)

      Text(this.statusText)
        .fontSize(12)
        .fontColor('#666666')
        .maxLines(1)

      Text(this.updatedAtText)
        .fontSize(10)
        .fontColor('#999999')
        .maxLines(1)

      Button('打开应用')
        .fontSize(12)
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
  }
}
