import { useCallback, useEffect, useState } from "react";
import { ExternalLink, RefreshCw } from "lucide-react";
import { useTranslation } from "react-i18next";

import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/status-badge";
import { commands, type AccountSummary, type AggregateSnapshot } from "@/lib/tauri-bindings";
import { formatMoney, healthKind, PROVIDER_NAMES } from "@/lib/format";

export default function PopoverApp() {
  const { t } = useTranslation();
  const [accounts, setAccounts] = useState<AccountSummary[]>([]);
  const [aggregate, setAggregate] = useState<AggregateSnapshot | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    const [rows, snapshot] = await Promise.all([commands.listAccounts(), commands.getAggregateSnapshot()]);
    setAccounts(rows.filter((account) => account.is_enabled).sort((a, b) => a.sort_order - b.sort_order));
    setAggregate(snapshot);
  }, []);
  useEffect(() => { void load(); }, [load]);
  const refresh = async () => { setRefreshing(true); try { await commands.refreshAll(); await load(); } finally { setRefreshing(false); } };
  const snapshots = new Map((aggregate?.accounts ?? []).map((snapshot) => [snapshot.account_id, snapshot]));

  return <div className="flex min-h-dvh flex-col gap-3 bg-qg-bg-light p-3 dark:bg-qg-bg-dark-2"><header className="flex items-center justify-between"><div><p className="text-sm font-semibold">{t("app.name")}</p><p className="text-xs text-qg-neutral">{t("popover.title")}</p></div><button type="button" className="qg-icon-button" aria-label={t("popover.openMain")} onClick={() => void commands.openWindow("main")}><ExternalLink aria-hidden="true" size={18} /></button></header><div className="min-h-0 flex-1 space-y-2 overflow-y-auto">{accounts.length ? accounts.map((account) => { const snapshot = snapshots.get(account.id); return <div key={account.id} className="flex items-center justify-between gap-2 rounded-qg bg-qg-bg-light-2 px-3 py-2 dark:bg-black/20"><span className="min-w-0"><span className="block truncate text-sm font-medium">{account.display_name}</span><span className="block truncate text-xs text-qg-neutral">{PROVIDER_NAMES[account.provider]}</span></span><span className="flex flex-col items-end gap-1"><span className="font-mono text-xs font-semibold tabular-nums">{formatMoney(snapshot?.usage?.balances[0]?.available)}</span><StatusBadge health={snapshot ? healthKind(snapshot.health) : "unavailable"} /></span></div>; }) : <p className="qg-section-note px-2 py-5 text-center">{t("app.noAccounts")}</p>}</div><Button size="sm" loading={refreshing} onClick={refresh}><RefreshCw aria-hidden="true" size={17} />{t("popover.refreshAll")}</Button></div>;
}
