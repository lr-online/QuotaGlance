import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { createProviderRegistry } from '../providers/ProviderCatalog';
import { KeyRepository } from '../storage/KeyRepository';
import { SnapshotStore, formatSnapshotTexts } from '../storage/SnapshotStore';

const TAG = 'EntryFormAbility';
const DOMAIN_NUMBER = 0xFF00;
const FORM_ID_PARAM = 'ohos.extra.param.key.form_identity';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.[FORM_ID_PARAM] as string;
    if (formId) {
      this.refreshForm(formId);
    }
    const placeholder: Record<string, string> = {
      'balanceText': '加载中…',
      'statusText': '',
      'updatedAtText': ''
    };
    return formBindingData.createFormBindingData(placeholder);
  }

  onUpdateForm(formId: string): void {
    this.refreshForm(formId);
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN_NUMBER, TAG, `onRemoveForm: ${formId}`);
  }

  private async refreshForm(formId: string): Promise<void> {
    try {
      const store = await SnapshotStore.create(this.context);
      const apiKey = await KeyRepository.load();
      if (apiKey) {
        try {
          const provider = createProviderRegistry().provider('deepSeek');
          const snapshot = await provider.fetch(apiKey);
          await store.save(snapshot);
        } catch (error) {
          await store.markStale();
        }
      }
      const texts = formatSnapshotTexts(await store.load());
      const data = formBindingData.createFormBindingData(texts);
      await formProvider.updateForm(formId, data);
    } catch (error) {
      hilog.error(DOMAIN_NUMBER, TAG, `refreshForm failed: ${(error as Error).message}`);
    }
  }
}
