import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  FormBinding,
  decodeFormBindings,
  encodeFormBindings
} from './StateCodecs';

// formId → card binding (selected account + grid dimension), in the shared
// 'quotaglance_store' preferences file under 'form_bindings_v1'. The map's
// keys double as the form registry: EntryFormAbility registers a form in
// onAddForm/onUpdateForm and removes it in onRemoveForm, so card-update pushes
// after refreshes know which formIds exist without formProvider.getFormsInfo.
//
// This is the HarmonyOS mirror of the macOS NCWidget per-widget account
// choice: unset accountId = 总览 (aggregate overview).
const STORE_NAME = 'quotaglance_store';
const BINDINGS_KEY = 'form_bindings_v1';

export class FormBindingStore {
  private readonly store: preferences.Preferences;

  private constructor(store: preferences.Preferences) {
    this.store = store;
  }

  static async create(context: common.Context): Promise<FormBindingStore> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    return new FormBindingStore(store);
  }

  private async loadAll(): Promise<Map<string, FormBinding>> {
    const raw = await this.store.get(BINDINGS_KEY, '') as string;
    return decodeFormBindings(raw);
  }

  private async saveAll(bindings: Map<string, FormBinding>): Promise<void> {
    await this.store.put(BINDINGS_KEY, encodeFormBindings(bindings));
    await this.store.flush();
  }

  // Registers/updates the form's dimension (called from onAddForm/onUpdateForm).
  async registerForm(formId: string, dimension: number): Promise<void> {
    const bindings = await this.loadAll();
    const existing = bindings.get(formId);
    if (existing !== undefined) {
      existing.dimension = dimension;
    } else {
      const binding: FormBinding = { dimension: dimension };
      bindings.set(formId, binding);
    }
    await this.saveAll(bindings);
  }

  async bindingFor(formId: string): Promise<FormBinding | null> {
    return (await this.loadAll()).get(formId) ?? null;
  }

  // accountId = null resets the card to the aggregate overview.
  async setAccount(formId: string, accountId: string | null): Promise<void> {
    const bindings = await this.loadAll();
    const binding = bindings.get(formId) ?? { dimension: 2 };
    if (accountId === null) {
      delete binding.accountId;
    } else {
      binding.accountId = accountId;
    }
    bindings.set(formId, binding);
    await this.saveAll(bindings);
  }

  async removeForm(formId: string): Promise<void> {
    const bindings = await this.loadAll();
    if (bindings.delete(formId)) {
      await this.saveAll(bindings);
    }
  }

  // All known formIds — the push targets for post-refresh card updates.
  async listFormIds(): Promise<string[]> {
    const ids: string[] = [];
    (await this.loadAll()).forEach((binding: FormBinding, formId: string) => {
      ids.push(formId);
    });
    return ids;
  }
}
