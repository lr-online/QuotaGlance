import { formBindingData, FormExtensionAbility } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { switchFormAccount, updateFormCard } from '../services/CardUpdater';
import { FormBindingStore } from '../storage/FormBindingStore';
import { SwipeDirection } from '../widget/FormAccountNavigation';

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

function parseSwipeDirection(message: string): SwipeDirection | null {
  if (message === 'left' || message === 'right') {
    return message;
  }
  return null;
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
      'themeMode': 'system',
      'mode': 'aggregate',
      'title': this.context.resourceManager.getStringSync($r('app.string.overview_label').id),
      'balanceText': this.context.resourceManager.getStringSync($r('app.string.widget_loading').id),
      'statusText': '',
      'updatedAtText': '',
      'todayText': '',
      'messageText': '',
      'messageSeverity': '',
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

  onFormEvent(formId: string, message: string): void {
    const direction = parseSwipeDirection(message);
    if (direction === null) {
      return;
    }
    switchFormAccount(this.context, formId, direction).catch((error: Object) => {
      hilog.warn(DOMAIN_NUMBER, TAG, 'onFormEvent failed: %{public}s', (error as Error).message);
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
