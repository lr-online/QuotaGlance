import { useCallback, useEffect, useMemo, useState } from "react";
import { Area, AreaChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { CirclePlus, RefreshCw } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";

import { PageShell } from "@/components/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/status-badge";
import { commands, events, type AccountSummary, type AggregateSnapshot } from "@/lib/tauri-bindings";
import { formatMoney, formatNumber, healthKind, PROVIDER_NAMES, relativeTime } from "@/lib/format";

export default function Overview() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const [accounts, setAccounts] = useState<AccountSummary[]>([]);
  const [aggregate, setAggregate] = useState<AggregateSnapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const [accountRows, snapshot] = await Promise.all([
        commands.listAccounts(),
        commands.getAggregateSnapshot(),
      ]);
      setAccounts(accountRows.sort((a, b) => a.sort_order - b.sort_order));
      setAggregate(snapshot);
    } catch (cause) {
      setError(String(cause));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    void events.onSnapshotsUpdated(() => void load()).then((release) => { unlisten = release; });
    return () => unlisten?.();
  }, [load]);

  const refresh = async () => {
    setRefreshing(true);
    setError(null);
    try {
      const report = await commands.refreshAll();
      if (report.failures > 0) setError(report.last_failure_reason ?? t("app.refreshPartial"));
      await load();
    } catch (cause) {
      setError(String(cause));
    } finally {
      setRefreshing(false);
    }
  };

  const chartData = useMemo(() => (aggregate?.daily_usage ?? []).map((entry) => ({
    date: entry.date.slice(5),
    amount: Number(entry.actual_cost.amount) || 0,
  })), [aggregate]);
  const snapshots = new Map((aggregate?.accounts ?? []).map((snapshot) => [snapshot.account_id, snapshot]));
  const balanceSummary = aggregate?.balances.length ? aggregate.balances.map(formatMoney).join(" / ") : "--";

  return (
    <PageShell
      title={t("app.name")}
      subtitle={t("overview.subtitle")}
      action={
        <button className="qg-icon-button" type="button" aria-label={t("actions.refresh")} onClick={refresh} disabled={refreshing}>
          <RefreshCw aria-hidden="true" size={20} className={refreshing ? "animate-spin" : ""} />
        </button>
      }
    >
      {error ? <p className="qg-error" role="alert">{error}</p> : null}
      {loading ? <p className="qg-section-note">{t("status.loading")}</p> : null}
      {!loading && accounts.length === 0 ? (
        <section className="qg-empty">
          <CirclePlus aria-hidden="true" size={32} className="text-qg-blue" />
          <h2 className="qg-section-title">{t("overview.emptyTitle")}</h2>
          <p className="qg-section-note">{t("app.noAccounts")}</p>
          <Button onClick={() => navigate("/add")}><CirclePlus aria-hidden="true" size={18} />{t("nav.addProvider")}</Button>
        </section>
      ) : null}
      {accounts.length > 0 ? <>
        <section className="grid grid-cols-2 gap-3" aria-label={t("overview.summary")}>
          <div className="qg-metric col-span-2">
            <p className="qg-metric-label">{t("metrics.balance")}</p>
            <p className="qg-metric-value">{balanceSummary}</p>
            <p className="mt-1 text-xs text-qg-neutral">{aggregate?.is_partial ? t("status.partial") : t("overview.allAccounts")}</p>
          </div>
          <div className="qg-metric"><p className="qg-metric-label">{t("metrics.todayCost")}</p><p className="qg-metric-value">{formatMoney(aggregate?.today_actual_cost)}</p></div>
          <div className="qg-metric"><p className="qg-metric-label">{t("metrics.todayRequests")}</p><p className="qg-metric-value">{formatNumber(aggregate?.today_requests)}</p></div>
        </section>
        <section>
          <div className="mb-3 flex items-baseline justify-between"><h2 className="qg-section-title">{t("overview.weeklyUsage")}</h2><span className="text-xs text-qg-neutral">{t("overview.lastSevenDays")}</span></div>
          <Card className="p-3" aria-label={t("overview.weeklyUsage")}>
            {chartData.length ? <div className="h-40"><ResponsiveContainer><AreaChart data={chartData} margin={{ top: 8, right: 4, bottom: 0, left: -24 }}><XAxis dataKey="date" tickLine={false} axisLine={false} tick={{ fill: "#8E8E93", fontSize: 11 }} /><YAxis tickLine={false} axisLine={false} tick={{ fill: "#8E8E93", fontSize: 11 }} /><Tooltip formatter={(value: number) => new Intl.NumberFormat(undefined, { maximumFractionDigits: 4 }).format(value)} /><Area type="monotone" dataKey="amount" stroke="#007AFF" strokeWidth={2} fill="#007AFF" fillOpacity={0.16} /></AreaChart></ResponsiveContainer></div> : <p className="qg-section-note py-10 text-center">{t("overview.noUsage")}</p>}
          </Card>
        </section>
        <section className="flex flex-col gap-2">
          <div className="flex items-center justify-between"><h2 className="qg-section-title">{t("overview.accounts")}</h2><Button variant="ghost" size="sm" onClick={() => navigate("/add")}>{t("actions.add")}</Button></div>
          {accounts.map((account) => {
            const snapshot = snapshots.get(account.id);
            const health = snapshot ? healthKind(snapshot.health) : "unavailable";
            return <button key={account.id} type="button" className="qg-account-row" onClick={() => navigate(`/accounts/${account.id}`)}>
              <span className="min-w-0"><span className="block truncate text-sm font-semibold">{account.display_name}</span><span className="mt-1 block truncate text-xs text-qg-neutral">{PROVIDER_NAMES[account.provider]}{snapshot?.last_success_at ? ` · ${relativeTime(snapshot.last_success_at)}` : ""}</span></span>
              <span className="flex flex-col items-end gap-1"><span className="font-mono text-sm font-semibold tabular-nums">{formatMoney(snapshot?.usage?.balances[0]?.available)}</span><StatusBadge health={account.is_enabled ? health : "unavailable"} /></span>
            </button>;
          })}
        </section>
      </> : null}
    </PageShell>
  );
}
