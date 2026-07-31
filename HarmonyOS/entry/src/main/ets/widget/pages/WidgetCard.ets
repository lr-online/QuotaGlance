// The card is intentionally dark-styled in BOTH system color modes (form
// cards on dark desktops read fine), so it pins the dark palette as literal
// hex instead of $r('app.color.*'), which now follows the system mode.
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
        .fontColor('#57E0D6')
        .maxLines(1)

      Text(this.statusText)
        .fontSize(12)
        .fontColor('#99A1B3')
        .maxLines(1)

      Text(this.updatedAtText)
        .fontSize(10)
        .fontColor('#54607A')
        .maxLines(1)

      Button($r('app.string.open_app'))
        .fontSize(12)
        .fontColor('#12161F')
        .backgroundColor('#57E0D6')
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
    .backgroundColor('#12161F')
    .borderRadius(16)
  }
}
