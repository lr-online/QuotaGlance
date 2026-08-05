import { useCallback, useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";
import { useTranslation } from "react-i18next";

import { commands, events, type AccountSummary, type AggregateSnapshot, type PreferencesDTO } from "@/lib/tauri-bindings";
import { formatMoney, PROVIDER_NAMES } from "@/lib/format";

export default function WidgetApp() {
  const { t } = useTranslation();
  const [accounts, setAccounts] = useState<AccountSummary[]>([]);
  const [aggregate, setAggregate] = useState<AggregateSnapshot | null>(null);
  const [preferences, setPreferences] = useState<PreferencesDTO | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const load = useCallback(async () => {
    const [rows, snapshot, prefs] = await Promise.all([commands.listAccounts(), commands.getAggregateSnapshot(), commands.getPreferences()]);
    setAccounts(rows.filter((account) => account.is_enabled));
    setAggregate(snapshot);
    setPreferences(prefs);
  }, []);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    void events.onSnapshotsUpdated(() => void load()).then((release) => { unlisten = release; });
    return () => unlisten?.();
  }, [load]);
  const refresh = async () => { setRefreshing(true); try { await commands.refreshAll(); await load(); } finally { setRefreshing(false); } };
  const target = preferences?.default_widget_target;
  const selectedId = target?.kind === "account" ? target.account_id : accounts[0]?.id;
  const selected = aggregate?.accounts.find((snapshot) => snapshot.account_id === selectedId);
  const showAggregate = target?.kind === "all";
  const value = showAggregate ? aggregate?.balances.map(formatMoney).join(" / ") : formatMoney(selected?.usage?.balances[0]?.available);
  const label = showAggregate ? t("settings.widgetAll") : selected ? `${selected.display_name} · ${PROVIDER_NAMES[selected.provider]}` : t("widget.noData");
  return <div className="flex min-h-dvh flex-col justify-between gap-3 rounded-qg bg-qg-bg-light p-4 shadow-qg dark:bg-qg-bg-dark-2"><div><p className="text-xs font-semibold text-qg-blue">{t("app.name")}</p><p className="mt-2 truncate text-xs text-qg-neutral">{label}</p><p className="mt-1 break-words font-mono text-xl font-semibold tabular-nums">{value}</p></div><button type="button" className="flex min-h-10 items-center justify-center gap-2 rounded-qg bg-qg-blue text-xs font-semibold text-white transition-colors hover:bg-qg-blue-dark disabled:opacity-50" disabled={refreshing} onClick={refresh}><RefreshCw aria-hidden="true" size={16} className={refreshing ? "animate-spin" : ""} />{t("widget.refresh")}</button></div>;
}
