@Entry
@Component
struct Index {
  build() {
    Row() {
      Column() {
        Text('Hello World')
          .fontSize($r('app.float.page_text_font_size'))
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
    }
    .height('100%')
  }
}
