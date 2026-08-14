import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";

import { PageShell } from "@/components/app-shell";
import { Switch } from "@/components/ui/switch";
import { commands, type AccountSummary, type PreferencesDTO } from "@/lib/tauri-bindings";
import { resolveLocale } from "@/i18n";
import { PROVIDER_NAMES } from "@/lib/format";
import type { Locale, WidgetTarget } from "@/storage/types";

const INTERVALS = [1, 5, 15, 30, 60] as const;

function targetToValue(target: WidgetTarget): string {
  if (target.kind === "all") return "all";
  if (target.kind === "account") return `account:${target.account_id}`;
  return "default";
}

function valueToTarget(value: string): WidgetTarget {
  if (value === "all") return { kind: "all" };
  if (value.startsWith("account:")) return { kind: "account", account_id: value.slice("account:".length) };
  return { kind: "defaultAccount" };
}

export default function SettingsPage() {
  const { t, i18n } = useTranslation();
  const [preferences, setPreferences] = useState<PreferencesDTO | null>(null);
  const [accounts, setAccounts] = useState<AccountSummary[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void Promise.all([commands.getPreferences(), commands.listAccounts()])
      .then(([prefs, rows]) => { setPreferences(prefs); setAccounts(rows); })
      .catch((cause) => setError(String(cause)));
  }, []);

  const update = async (next: PreferencesDTO) => {
    setPreferences(next);
    setSaving(true);
    setError(null);
    try {
      await commands.updatePreferences(next);
      if (next.locale !== preferences?.locale) await i18n.changeLanguage(resolveLocale(next.locale));
    } catch (cause) {
      setError(String(cause));
    } finally {
      setSaving(false);
    }
  };

  if (!preferences) return <div className="flex min-h-dvh items-center justify-center text-sm text-qg-neutral">{error ?? t("status.loading")}</div>;
  return (
    <PageShell title={t("settings.title")} subtitle={t("settings.subtitle")}>
      {error ? <p className="qg-error" role="alert">{error}</p> : null}
      <section className="qg-form-group"><h2 className="qg-section-title">{t("settings.refreshInterval")}</h2><div className="grid grid-cols-2 gap-2">{INTERVALS.map((minutes) => <button key={minutes} type="button" aria-pressed={preferences.refresh_interval_minutes === minutes} disabled={saving} onClick={() => void update({ ...preferences, refresh_interval_minutes: minutes })} className={preferences.refresh_interval_minutes === minutes ? "min-h-11 rounded-qg border border-qg-blue bg-qg-blue px-3 text-sm font-medium text-white" : "min-h-11 rounded-qg border border-qg-neutral/30 px-3 text-sm font-medium transition-colors hover:bg-qg-bg-light-2 dark:hover:bg-qg-bg-dark-2"}>{t(`settings.minute${minutes}`)}</button>)}</div></section>
      <section className="qg-form-group"><label className="qg-form-label" htmlFor="language">{t("settings.language")}</label><select id="language" className="qg-selection" value={preferences.locale} disabled={saving} onChange={(event) => void update({ ...preferences, locale: event.target.value as Locale })}><option value="system">{t("settings.languageSystem")}</option><option value="en">{t("settings.languageEn")}</option><option value="zh-CN">{t("settings.languageZhCn")}</option></select></section>
      <section className="rounded-qg border border-black/5 dark:border-white/10"><Switch id="notifications" checked={preferences.notifications_enabled} disabled={saving} onCheckedChange={(notifications_enabled) => void update({ ...preferences, notifications_enabled })} label={t("settings.notifications")} description={t("settings.notificationsHelp")} /><Switch id="launch-at-login" checked={preferences.launch_at_login} disabled={saving} onCheckedChange={(launch_at_login) => void update({ ...preferences, launch_at_login })} label={t("settings.launchAtLogin")} description={t("settings.launchAtLoginHelp")} /></section>
      <section className="qg-form-group"><label className="qg-form-label" htmlFor="widget-target">{t("settings.defaultWidget")}</label><select id="widget-target" className="qg-selection" value={targetToValue(preferences.default_widget_target)} disabled={saving} onChange={(event) => void update({ ...preferences, default_widget_target: valueToTarget(event.target.value) })}><option value="all">{t("settings.widgetAll")}</option><option value="default">{t("settings.widgetDefault")}</option>{accounts.filter((account) => account.is_enabled).map((account) => <option key={account.id} value={`account:${account.id}`}>{account.display_name} ({PROVIDER_NAMES[account.provider]})</option>)}</select><p className="qg-form-help">{t("settings.widgetHelp")}</p></section>
    </PageShell>
  );
}
