import { FormEvent, useEffect, useState } from "react";
import { Eye, EyeOff, SearchCheck } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";

import { PageShell } from "@/components/app-shell";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { commands, type ProviderID, type ProviderProfile } from "@/lib/tauri-bindings";
import { PROVIDER_NAMES } from "@/lib/format";

const PROVIDERS: ProviderID[] = ["apiInfo", "deepSeek", "kimi", "openRouter", "miniMax", "bioMapCoding"];

export default function AddProvider() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const [provider, setProvider] = useState<ProviderID>("deepSeek");
  const [displayName, setDisplayName] = useState("");
  const [apiKey, setApiKey] = useState("");
  const [region, setRegion] = useState<ProviderProfile["region"]>("global");
  const [profile, setProfile] = useState<ProviderProfile | null>(null);
  const [showKey, setShowKey] = useState(false);
  const [detecting, setDetecting] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setProfile(null);
    if (provider === "kimi" || provider === "miniMax") setRegion("china");
    else setRegion("global");
  }, [provider]);

  const detect = async () => {
    if (!apiKey.trim()) {
      setError(t("addAccount.missingKey"));
      return;
    }
    setDetecting(true);
    setError(null);
    try {
      const detected = await commands.detectProviderProfile(provider, apiKey);
      setProfile(detected);
      setRegion(detected.region);
    } catch (cause) {
      setProfile(null);
      setError(String(cause));
    } finally {
      setDetecting(false);
    }
  };

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!displayName.trim()) {
      setError(t("addAccount.missingName"));
      return;
    }
    if (!apiKey.trim()) {
      setError(t("addAccount.missingKey"));
      return;
    }
    if (!profile) {
      setError(t("addAccount.detectRequired"));
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const id = await commands.addAccount({
        display_name: displayName.trim(),
        provider,
        api_key: apiKey,
        detected_profile: profile,
      });
      await commands.showNotification(t("addAccount.saved"), displayName.trim()).catch(() => undefined);
      navigate(`/accounts/${id}`);
    } catch (cause) {
      setError(String(cause));
    } finally {
      setSaving(false);
    }
  };

  const canChooseRegion = provider === "kimi" || provider === "miniMax";
  return (
    <PageShell title={t("addAccount.title")} subtitle={t("addAccount.subtitle")} backTo="/">
      <form className="flex flex-col gap-5" onSubmit={submit}>
        <fieldset className="qg-form-group"><legend className="qg-form-label">{t("addAccount.selectProvider")}</legend><div className="grid grid-cols-2 gap-2">{PROVIDERS.map((id) => <button key={id} type="button" aria-pressed={provider === id} onClick={() => setProvider(id)} className={provider === id ? "min-h-11 rounded-qg border border-qg-blue bg-qg-blue px-3 text-sm font-medium text-white" : "min-h-11 rounded-qg border border-qg-neutral/30 px-3 text-sm font-medium transition-colors hover:bg-qg-bg-light-2 dark:hover:bg-qg-bg-dark-2"}>{PROVIDER_NAMES[id]}</button>)}</div></fieldset>
        <div className="qg-form-group"><label className="qg-form-label" htmlFor="display-name">{t("addAccount.displayName")}</label><Input id="display-name" value={displayName} onChange={(event) => setDisplayName(event.target.value)} autoComplete="nickname" placeholder={PROVIDER_NAMES[provider]} required /><p className="qg-form-help">{t("addAccount.nameHelp")}</p></div>
        <div className="qg-form-group"><label className="qg-form-label" htmlFor="api-key">{t("addAccount.pasteKey")}</label><div className="flex gap-2"><Input id="api-key" type={showKey ? "text" : "password"} value={apiKey} onChange={(event) => { setApiKey(event.target.value); setProfile(null); }} autoComplete="off" spellCheck={false} placeholder={t("addAccount.keyPlaceholder")} required /><button className="qg-icon-button" type="button" aria-label={showKey ? t("actions.hide") : t("actions.show")} onClick={() => setShowKey((value) => !value)}>{showKey ? <EyeOff aria-hidden="true" size={20} /> : <Eye aria-hidden="true" size={20} />}</button></div><p className="qg-form-help">{t("addAccount.keyHelp")}</p></div>
        {canChooseRegion ? <fieldset className="qg-form-group"><legend className="qg-form-label">{t("addAccount.region")}</legend><div className="grid grid-cols-2 gap-2">{(["china", "international"] as const).map((value) => <button key={value} type="button" aria-pressed={region === value} onClick={() => { setRegion(value); setProfile(null); }} className={region === value ? "min-h-11 rounded-qg border border-qg-blue bg-qg-blue px-3 text-sm font-medium text-white" : "min-h-11 rounded-qg border border-qg-neutral/30 px-3 text-sm font-medium transition-colors hover:bg-qg-bg-light-2 dark:hover:bg-qg-bg-dark-2"}>{t(`region.${value}`)}</button>)}</div></fieldset> : null}
        <section className="rounded-qg border border-black/5 bg-qg-bg-light-2 p-4 dark:border-white/10 dark:bg-qg-bg-dark-2"><div className="flex items-center justify-between gap-3"><div><h2 className="qg-section-title">{t("addAccount.detect")}</h2><p className="mt-1 text-xs leading-5 text-qg-neutral">{profile ? `${t("addAccount.detected")}: ${t(`region.${profile.region}`)} · ${t(`credential.${profile.credential_kind}`)}` : t("addAccount.detectHelp")}</p></div><Button type="button" variant="secondary" size="sm" loading={detecting} onClick={detect}><SearchCheck aria-hidden="true" size={17} />{t("addAccount.detect")}</Button></div></section>
        {error ? <p className="qg-error" role="alert">{error}</p> : null}
        <Button type="submit" size="lg" loading={saving}>{t("actions.saveAccount")}</Button>
      </form>
    </PageShell>
  );
}
