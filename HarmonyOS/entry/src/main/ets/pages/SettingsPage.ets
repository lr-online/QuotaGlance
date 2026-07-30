import { router } from '@kit.ArkUI';
import { KeyRepository } from '../storage/KeyRepository';

@Entry
@Component
struct SettingsPage {
  @State apiKey: string = '';
  @State message: string = '';

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
          await KeyRepository.save(this.apiKey.trim());
          router.back();
        })

      Button('清除已保存的 Key')
        .onClick(async () => {
          await KeyRepository.clear();
          this.message = '已清除';
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
