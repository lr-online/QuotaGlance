import { formBindingData, FormExtensionAbility } from '@kit.FormKit';
import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountService } from '../services/AccountService';
import { switchFormAccount, updateFormCard } from '../services/CardUpdater';
import { Account } from '../storage/AccountStore';
import { FormBindingStore } from '../storage/FormBindingStore';
import { SwipeDirection } from '../widget/FormAccountNavigation';

const TAG = 'EntryFormAbility';
const DOMAIN_NUMBER = 0xFF00;
const FORM_ID_PARAM = 'ohos.extra.param.key.form_identity';
const REFRESH_MESSAGE = 'refresh';
const refreshingFormIds: Set<string> = new Set();

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

// Service-card updateDuration is limited to 30-minute units by HarmonyOS.
// A card tap is therefore the reliable way to request a refresh sooner. An
// account card refreshes only its selected account; an overview card refreshes
// all enabled accounts, matching the app's refresh-all action.
async function refreshCard(context: common.Context, formId: string): Promise<void> {
  try {
    const bindingStore = await FormBindingStore.create(context);
    const binding = await bindingStore.bindingFor(formId);
    const service = await AccountService.create(context);
    const accounts = await service.loadAccounts();
    let target: Account | undefined;
    if (binding?.accountId !== undefined) {
      target = accounts.find((account: Account) => account.id === binding.accountId);
    }
    if (target !== undefined && target.isEnabled) {
      await service.refreshAccount(target);
    } else {
      await service.refreshAllEnabled();
    }
  }
}

function requestCardRefresh(context: common.Context, formId: string): void {
  if (refreshingFormIds.has(formId)) {
    return;
  }
  refreshingFormIds.add(formId);
  refreshCard(context, formId).catch((error: Object) => {
    hilog.warn(DOMAIN_NUMBER, TAG, 'card refresh failed: %{public}s', (error as Error).message);
  }).finally(() => {
    refreshingFormIds.delete(formId);
  });
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
    // The host invokes this callback according to form_config.json's
    // updateDuration. Fetch before publishing so a scheduled card update is
    // not limited to re-rendering an old snapshot.
    requestCardRefresh(this.context, formId);
  }

  onFormEvent(formId: string, message: string): void {
    if (message === REFRESH_MESSAGE) {
      requestCardRefresh(this.context, formId);
      return;
    }
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
