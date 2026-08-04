@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('formId') formId: string = '';
  @LocalStorageProp('formDimension') formDimension: string = '2';
  @LocalStorageProp('themeMode') themeMode: string = 'system';
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

  private messageColor(): ResourceColor {
    if (this.messageSeverity === 'error') {
      return $r('app.color.danger');
    }
    if (this.messageSeverity === 'warning') {
      return $r('app.color.warning');
    }
    return this.accentColor();
  }

  // Form cards render outside the main UIAbility, so the app-level color mode
  // override is not guaranteed to reach this component. The selected mode is
  // persisted into the binding payload; system mode deliberately uses dynamic
  // resources so it still follows the host device's color mode.
  private cardBackground(): ResourceColor {
    if (this.themeMode === 'light') {
      return '#FFFFFF';
    }
    if (this.themeMode === 'dark') {
      return '#1B2233';
    }
    return $r('app.color.cardBackground');
  }

  private textPrimaryColor(): ResourceColor {
    if (this.themeMode === 'light') {
      return '#1A2333';
    }
    if (this.themeMode === 'dark') {
      return '#FFFFFF';
    }
    return $r('app.color.textPrimary');
  }

  private textSecondaryColor(): ResourceColor {
    if (this.themeMode === 'light') {
      return '#5A6478';
    }
    if (this.themeMode === 'dark') {
      return '#99A1B3';
    }
    return $r('app.color.textSecondary');
  }

  private slateColor(): ResourceColor {
    if (this.themeMode === 'light') {
      return '#C3CAD8';
    }
    if (this.themeMode === 'dark') {
      return '#54607A';
    }
    return $r('app.color.slateSecondary');
  }

  private accentColor(): ResourceColor {
    if (this.themeMode === 'light') {
      return '#0E9C93';
    }
    if (this.themeMode === 'dark') {
      return '#57E0D6';
    }
    return $r('app.color.accentTeal');
  }

  private requestAccountSwitch(direction: string): void {
    postCardAction(this, {
      action: 'message',
      params: {
        message: direction
      }
    });
  }

  private requestRefresh(): void {
    postCardAction(this, {
      action: 'message',
      params: {
        message: 'refresh'
      }
    });
  }

  @Builder
  refreshButton() {
    Button($r('app.string.widget_refresh'))
      .fontSize(this.dimension() >= 3 ? 11 : 10)
      .fontColor(this.accentColor())
      .width(64)
      .height(this.dimension() >= 3 ? 30 : 26)
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.cardBackground())
      .border({ width: 1, color: this.accentColor() })
      .borderRadius(8)
      .stateEffect(true)
      .onClick(() => {
        this.requestRefresh();
      })
  }

  @Builder
  compactBody() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(11)
        .fontColor(this.textSecondaryColor())
        .maxLines(1)
      Text(this.balanceText)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor())
        .maxLines(1)
      if (this.todayText.length > 0) {
        Text(this.todayText)
          .fontSize(11)
          .fontColor(this.textPrimaryColor())
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
          .fontColor(this.textSecondaryColor())
          .maxLines(1)
      }
      Row() {
        if (this.updatedAtText.length > 0) {
          Text(this.updatedAtText)
            .fontSize(10)
            .fontColor(this.slateColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        Blank()
          .layoutWeight(1)
        this.refreshButton()
      }
      .width('100%')
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
          .fontColor(this.textSecondaryColor())
          .layoutWeight(1)
          .maxLines(1)
        if (this.statusText.length > 0) {
          Text(this.statusText)
            .fontSize(10)
            .fontColor(this.textSecondaryColor())
            .maxLines(1)
        }
      }
      .width('100%')

      Text(this.balanceText)
        .fontSize(this.dimension() === 4 ? 24 : 20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor())
        .maxLines(2)

      if (this.todayText.length > 0) {
        Text(this.todayText)
          .fontSize(11)
          .fontColor(this.textPrimaryColor())
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
              .fontColor(this.textPrimaryColor())
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

      Row() {
        if (this.updatedAtText.length > 0) {
          Text(this.updatedAtText)
            .fontSize(10)
            .fontColor(this.slateColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        Blank()
          .layoutWeight(1)
        this.refreshButton()
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  cardPage() {
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
    .backgroundColor(this.cardBackground())
    .borderRadius(16)
    .onClick(() => {
      this.openApp();
    })
  }

  build() {
    Swiper() {
      this.cardPage()
      this.cardPage()
      this.cardPage()
    }
    .index(1)
    .loop(false)
    .indicator(false)
    .width('100%')
    .height('100%')
    .onChange((index: number) => {
      if (index === 0) {
        this.requestAccountSwitch('right');
      } else if (index === 2) {
        this.requestAccountSwitch('left');
      }
    })
  }
}
