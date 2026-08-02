import { formBindingData, FormExtensionAbility } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { updateFormCard } from '../services/CardUpdater';
import { FormBindingStore } from '../storage/FormBindingStore';

const TAG = 'EntryFormAbility';
const DOMAIN_NUMBER = 0xFF00;
const FORM_ID_PARAM = 'ohos.extra.param.key.form_identity';

function parseDimension(raw: Object | undefined): number {
  if (typeof raw === 'number' && raw >= 1) {
    return raw;
  }
  if (typeof raw === 'string') {
    if (raw === '1*2') {
      return 1;
    }
    if (raw === '2*2') {
      return 2;
    }
    if (raw === '2*4') {
      return 3;
    }
    if (raw === '4*4') {
      return 4;
    }
  }
  return 2;
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.[FORM_ID_PARAM] as string;
    const dimension = parseDimension(want.parameters?.['ohos.extra.param.key.form_dimension']);
    if (formId) {
      FormBindingStore.create(this.context)
        .then((store: FormBindingStore) => store.registerForm(formId, dimension))
        .then(() => updateFormCard(this.context, formId))
        .catch((error: Object) => {
          hilog.warn(DOMAIN_NUMBER, TAG, 'onAddForm register failed: %{public}s', (error as Error).message);
        });
    }
    const placeholder: Record<string, string> = {
      'formId': formId ?? '',
      'formDimension': '' + dimension,
      'mode': 'aggregate',
      'title': this.context.resourceManager.getStringSync($r('app.string.overview_label').id),
      'balanceText': this.context.resourceManager.getStringSync($r('app.string.widget_loading').id),
      'statusText': '',
      'updatedAtText': '',
      'todayText': '',
      'rowsText': '',
      'targetAccountId': ''
    };
    return formBindingData.createFormBindingData(placeholder);
  }

  onUpdateForm(formId: string): void {
    updateFormCard(this.context, formId).catch((error: Object) => {
      hilog.warn(DOMAIN_NUMBER, TAG, 'onUpdateForm failed: %{public}s', (error as Error).message);
    });
  }

  onRemoveForm(formId: string): void {
    FormBindingStore.create(this.context)
      .then((store: FormBindingStore) => store.removeForm(formId))
      .catch((error: Object) => {
        hilog.warn(DOMAIN_NUMBER, TAG, 'onRemoveForm failed: %{public}s', (error as Error).message);
      });
  }
}
