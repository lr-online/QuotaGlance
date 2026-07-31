import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountService } from '../services/AccountService';
import { Account } from '../storage/AccountStore';
import { SnapshotStore, StoredSnapshot, formatSnapshotTexts } from '../storage/SnapshotStore';

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
      const service = await AccountService.create(this.context);
      await service.ensureLegacyMigration();
      const accounts = await service.loadAccounts();
      let firstEnabled: Account | null = null;
      for (const account of accounts) {
        if (account.isEnabled) {
          firstEnabled = account;
          break;
        }
      }
      let stored: StoredSnapshot | null = null;
      if (firstEnabled) {
        try {
          await service.refreshAccount(firstEnabled);
        } catch (error) {
          // refreshAccount already marked the snapshot stale.
        }
        const store = await SnapshotStore.create(this.context);
        stored = await store.load(firstEnabled.id);
      }
      const texts = formatSnapshotTexts(stored);
      const data = formBindingData.createFormBindingData(texts);
      await formProvider.updateForm(formId, data);
    } catch (error) {
      hilog.error(DOMAIN_NUMBER, TAG, `refreshForm failed: ${(error as Error).message}`);
    }
  }
}
