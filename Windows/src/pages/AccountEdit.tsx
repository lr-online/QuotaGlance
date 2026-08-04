import { FormEvent, useEffect, useState } from "react";
import { Trash2 } from "lucide-react";
import { useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";

import { PageShell } from "@/components/app-shell";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { commands, type AccountSummary } from "@/lib/tauri-bindings";
import { PROVIDER_NAMES } from "@/lib/format";

export default function AccountEdit() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { id = "" } = useParams<{ id: string }>();
  const [account, setAccount] = useState<AccountSummary | null>(null);
  const [displayName, setDisplayName] = useState("");
  const [threshold, setThreshold] = useState("");
  const [newKey, setNewKey] = useState("");
  const [enabled, setEnabled] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void commands.listAccounts().then((accounts) => {
      const found = accounts.find((candidate) => candidate.id === id) ?? null;
      setAccount(found);
      if (found) {
        setDisplayName(found.display_name);
        setThreshold(found.low_balance_threshold ?? "");
        setEnabled(found.is_enabled);
      }
    }).catch((cause) => setError(String(cause)));
  }, [id]);

  const save = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!account) return;
    if (!displayName.trim()) {
      setError(t("addAccount.missingName"));
      return;
    }
    if (threshold.trim() && !Number.isFinite(Number(threshold))) {
      setError(t("edit.invalidThreshold"));
      return;
    }
    setSaving(true);
    setError(null);
    try {
      let detectedProfile = account.detected_profile;
      if (newKey.trim()) {
        detectedProfile = await commands.detectProviderProfile(account.provider, newKey);
        await commands.replaceAccountCredential(account.id, newKey);
      }
      await commands.updateAccount({
        id: account.id,
        display_name: displayName.trim(),
        detected_profile: detectedProfile,
        low_balance_threshold: threshold.trim() || null,
        is_enabled: enabled,
      });
      navigate(`/accounts/${account.id}`);
    } catch (cause) {
      setError(String(cause));
    } finally {
      setSaving(false);
    }
  };

  const remove = async () => {
    if (!account || !window.confirm(t("edit.deleteConfirm"))) return;
    try {
      await commands.deleteAccount(account.id);
      navigate("/");
    } catch (cause) {
      setError(String(cause));
    }
  };

  if (!account) return <div className="flex min-h-dvh items-center justify-center p-6 text-sm text-qg-neutral">{error ?? t("status.loading")}</div>;
  return (
    <PageShell title={t("edit.title")} subtitle={PROVIDER_NAMES[account.provider]} backTo={`/accounts/${id}`}>
      <form className="flex flex-col gap-5" onSubmit={save}>
        <div className="qg-form-group"><label className="qg-form-label" htmlFor="edit-name">{t("addAccount.displayName")}</label><Input id="edit-name" value={displayName} onChange={(event) => setDisplayName(event.target.value)} required /></div>
        <div className="qg-form-group"><label className="qg-form-label" htmlFor="edit-threshold">{t("edit.threshold")}</label><Input id="edit-threshold" inputMode="decimal" value={threshold} onChange={(event) => setThreshold(event.target.value)} placeholder="0.00" /><p className="qg-form-help">{t("edit.thresholdHelp")}</p></div>
        <div className="qg-form-group"><label className="qg-form-label" htmlFor="edit-key">{t("edit.replaceKey")}</label><Input id="edit-key" type="password" autoComplete="new-password" spellCheck={false} value={newKey} onChange={(event) => setNewKey(event.target.value)} placeholder={t("edit.replaceKeyPlaceholder")} /><p className="qg-form-help">{t("edit.replaceKeyHelp")}</p></div>
        <section className="rounded-qg border border-black/5 dark:border-white/10"><Switch id="enabled" checked={enabled} onCheckedChange={setEnabled} label={t("edit.enabled")} description={enabled ? t("edit.enabledHelp") : t("edit.disabledHelp")} /></section>
        {error ? <p className="qg-error" role="alert">{error}</p> : null}
        <Button type="submit" size="lg" loading={saving}>{t("actions.save")}</Button>
        <button type="button" className="flex min-h-11 items-center justify-center gap-2 rounded-qg border border-qg-danger/30 px-4 text-sm font-medium text-qg-danger transition-colors hover:bg-qg-danger/10" onClick={remove}><Trash2 aria-hidden="true" size={18} />{t("actions.delete")}</button>
      </form>
    </PageShell>
  );
}
