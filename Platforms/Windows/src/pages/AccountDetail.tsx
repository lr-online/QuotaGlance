import { useCallback, useEffect, useState } from "react";
import { Edit3, RefreshCw } from "lucide-react";
import { useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";

import { PageShell } from "@/components/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/status-badge";
import { commands, type AccountSnapshot, type AccountSummary } from "@/lib/tauri-bindings";
import { formatMoney, formatNumber, healthKind, PROVIDER_NAMES, relativeTime } from "@/lib/format";

export default function AccountDetail() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { id = "" } = useParams<{ id: string }>();
  const [account, setAccount] = useState<AccountSummary | null>(null);
  const [snapshot, setSnapshot] = useState<AccountSnapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [accounts, latest] = await Promise.all([commands.listAccounts(), commands.getAccountSnapshot(id)]);
      setAccount(accounts.find((candidate) => candidate.id === id) ?? null);
      setSnapshot(latest);
    } catch (cause) {
      setError(String(cause));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => { void load(); }, [load]);

  const refresh = async () => {
    setRefreshing(true);
    setError(null);
    try {
      setSnapshot(await commands.refreshAccount(id));
    } catch (cause) {
      setError(String(cause));
      await load();
    } finally {
      setRefreshing(false);
    }
  };

  if (loading) return <div className="flex min-h-dvh items-center justify-center text-sm text-qg-neutral">{t("status.loading")}</div>;
  if (!account) return <div className="flex min-h-dvh flex-col items-center justify-center gap-3 p-6 text-center"><p className="qg-section-note">{t("detail.notFound")}</p><Button onClick={() => navigate("/")}>{t("nav.overview")}</Button></div>;

  const usage = snapshot?.usage;
  const health = snapshot ? healthKind(snapshot.health) : "unavailable";
  return (
    <PageShell
      backTo="/"
      title={account.display_name}
      subtitle={PROVIDER_NAMES[account.provider]}
      action={<div className="flex items-center gap-1"><button className="qg-icon-button" type="button" aria-label={t("actions.edit")} onClick={() => navigate(`/accounts/${id}/edit`)}><Edit3 aria-hidden="true" size={19} /></button><button className="qg-icon-button" type="button" aria-label={t("actions.refresh")} onClick={refresh} disabled={refreshing}><RefreshCw aria-hidden="true" size={19} className={refreshing ? "animate-spin" : ""} /></button></div>}
    >
      {error ? <p className="qg-error" role="alert">{error}</p> : null}
      <section className="flex items-center justify-between gap-3"><StatusBadge health={account.is_enabled ? health : "unavailable"} /><span className="text-right text-xs text-qg-neutral">{snapshot?.last_success_at ? `${t("detail.refreshed")} ${relativeTime(snapshot.last_success_at)}` : t("detail.neverRefreshed")}</span></section>
      {!account.is_enabled ? <p className="qg-error">{t("detail.disabled")}</p> : null}
      {!snapshot ? <section className="qg-empty"><p className="qg-section-note">{t("detail.noSnapshot")}</p><Button loading={refreshing} onClick={refresh}><RefreshCw aria-hidden="true" size={18} />{t("actions.refresh")}</Button></section> : null}
      {usage ? <>
        <section className="grid grid-cols-2 gap-3">
          <div className="qg-metric col-span-2"><p className="qg-metric-label">{t("metrics.balance")}</p><p className="qg-metric-value">{formatMoney(usage.balances[0]?.available)}</p><p className="mt-1 text-xs text-qg-neutral">{usage.balances[0]?.label ?? t("detail.notProvided")}</p></div>
          <div className="qg-metric"><p className="qg-metric-label">{t("metrics.spendToday")}</p><p className="qg-metric-value">{formatMoney(usage.spend.today)}</p></div>
          <div className="qg-metric"><p className="qg-metric-label">{t("metrics.todayRequests")}</p><p className="qg-metric-value">{formatNumber(usage.today?.requests)}</p></div>
        </section>
        {usage.balances.some((balance) => balance.breakdown.length > 0) ? <Card title={t("detail.balanceBreakdown")} className="p-4"><dl className="divide-y divide-black/5 dark:divide-white/10">{usage.balances.flatMap((balance) => balance.breakdown).map((item, index) => <div key={`${item.label}-${index}`} className="flex justify-between gap-3 py-3 text-sm"><dt className="text-qg-neutral">{item.label}</dt><dd className="font-mono font-medium tabular-nums">{formatMoney(item.value)}</dd></div>)}</dl></Card> : null}
        {usage.spending_limit ? <Card title={usage.spending_limit.label} className="p-4"><dl className="grid grid-cols-3 gap-3"><MetricItem label={t("metrics.quotaUsed")} value={formatMoney(usage.spending_limit.used)} /><MetricItem label={t("metrics.quotaLimit")} value={formatMoney(usage.spending_limit.limit)} /><MetricItem label={t("metrics.quotaRemaining")} value={formatMoney(usage.spending_limit.remaining)} /></dl>{usage.spending_limit.reset_description ? <p className="mt-4 text-xs text-qg-neutral">{usage.spending_limit.reset_description}</p> : null}</Card> : null}
        <Card title={t("detail.spending")} className="p-4"><dl className="grid grid-cols-2 gap-x-5 gap-y-4"><MetricItem label={t("metrics.spendToday")} value={formatMoney(usage.spend.today)} /><MetricItem label={t("metrics.spendWeek")} value={formatMoney(usage.spend.week)} /><MetricItem label={t("metrics.spendMonth")} value={formatMoney(usage.spend.month)} /><MetricItem label={t("metrics.spendTotal")} value={formatMoney(usage.spend.total)} /></dl></Card>
        <CounterCard title="Request details" counters={usage.today} />
        <CounterCard title="Total request details" counters={usage.total} />
        {usage.quota_windows.length ? <Card title={t("metrics.quotaWindow")} className="p-4"><dl className="divide-y divide-black/5 dark:divide-white/10">{usage.quota_windows.map((window, index) => <div key={`${window.label}-${index}`} className="flex items-center justify-between gap-3 py-3"><dt><p className="text-sm font-medium">{window.label}</p><p className="mt-1 text-xs text-qg-neutral">{window.unit}{window.resets_at ? ` · ${new Date(window.resets_at).toLocaleString()}` : ""}</p></dt><dd className="font-mono text-right text-sm tabular-nums"><div>Remaining {window.remaining ?? "--"}</div><div>{window.used ?? "--"} / {window.limit ?? "--"}</div></dd></div>)}</dl></Card> : null}
        {usage.daily_usage.length ? <Card title={t("detail.dailyUsage")} className="p-4"><dl className="divide-y divide-black/5 dark:divide-white/10">{usage.daily_usage.slice(-7).reverse().map((day) => <div key={day.date} className="flex justify-between gap-3 py-3 text-sm"><dt>{day.date}</dt><dd className="font-mono tabular-nums">{formatMoney(day.actual_cost)}{day.requests !== undefined ? ` · ${formatNumber(day.requests)} requests` : ""}{day.total_tokens !== undefined ? ` · ${formatNumber(day.total_tokens)} tokens` : ""}</dd></div>)}</dl></Card> : null}
        {usage.model_usage.length ? <Card title={t("detail.modelUsage")} className="p-4"><dl className="divide-y divide-black/5 dark:divide-white/10">{usage.model_usage.map((model, index) => <div key={`${model.model}-${index}`} className="flex justify-between gap-3 py-3 text-sm"><dt className="min-w-0 truncate">{model.model}</dt><dd className="shrink-0 font-mono tabular-nums">{formatMoney(model.actual_cost)}{model.requests !== undefined ? ` · ${formatNumber(model.requests)} requests` : ""}{model.total_tokens !== undefined ? ` · ${formatNumber(model.total_tokens)} tokens` : ""}</dd></div>)}</dl></Card> : null}
        {usage.api_info_details ? <Card title="API Info account" className="p-4"><dl className="grid grid-cols-2 gap-x-5 gap-y-4"><MetricItem label="Plan" value={usage.api_info_details.plan_name ?? "--"} /><MetricItem label="Mode" value={usage.api_info_details.mode ?? "--"} /><MetricItem label="Credential" value={usage.api_info_details.is_valid === undefined ? "--" : usage.api_info_details.is_valid ? "Valid" : "Invalid"} /><MetricItem label="Reported balance" value={formatMoney(usage.api_info_details.reported_balance)} /><MetricItem label="Expires" value={usage.api_info_details.expires_at ? new Date(usage.api_info_details.expires_at).toLocaleString() : "--"} /><MetricItem label="Days remaining" value={formatNumber(usage.api_info_details.days_until_expiry)} /></dl></Card> : null}
        {usage.provider_status || usage.metrics_unavailable_reason ? <Card title={t("detail.providerStatus")} className="p-4"><p className="text-sm font-medium">{usage.provider_status ?? t("detail.notProvided")}</p>{usage.metrics_unavailable_reason ? <p className="mt-2 text-sm leading-6 text-qg-neutral">{usage.metrics_unavailable_reason}</p> : null}</Card> : null}
      </> : null}
    </PageShell>
  );
}

function MetricItem({ label, value }: { label: string; value: string }) {
  return <div><dt className="text-xs text-qg-neutral">{label}</dt><dd className="mt-1 break-words font-mono text-sm font-semibold tabular-nums">{value}</dd></div>;
}

function CounterCard({ title, counters }: { title: string; counters: import("@/lib/tauri-bindings").UsageCounters | undefined }) {
  if (!counters) return null;
  const entries = [
    ["Cost", formatMoney(counters.actual_cost)],
    ["Requests", formatNumber(counters.requests)],
    ["Total tokens", formatNumber(counters.total_tokens)],
    ["Input tokens", formatNumber(counters.input_tokens)],
    ["Output tokens", formatNumber(counters.output_tokens)],
    ["Cache-read tokens", formatNumber(counters.cache_read_tokens)],
    ["Cache-creation tokens", formatNumber(counters.cache_creation_tokens)],
  ];
  if (entries.every(([, value]) => value === "--")) return null;
  return <Card title={title} className="p-4"><dl className="grid grid-cols-2 gap-x-5 gap-y-4">{entries.map(([label, value]) => <MetricItem key={label} label={label} value={value} />)}</dl></Card>;
}
