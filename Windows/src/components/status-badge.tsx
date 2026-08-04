import { AlertTriangle, CheckCircle2, CircleDashed, WifiOff } from "lucide-react";
import { useTranslation } from "react-i18next";

import type { AccountHealth } from "@/lib/tauri-bindings";
import { cn } from "@/lib/cn";

export function StatusBadge({ health }: { health: AccountHealth }) {
  const { t } = useTranslation();
  const details = {
    healthy: { icon: CheckCircle2, className: "qg-status-healthy" },
    belowThreshold: { icon: AlertTriangle, className: "qg-status-warning" },
    stale: { icon: CircleDashed, className: "qg-status-stale" },
    unavailable: { icon: WifiOff, className: "qg-status-unavailable" },
  } as const;
  const detail = details[health];
  const Icon = detail.icon;
  return (
    <span className={cn("qg-status-badge", detail.className)}>
      <Icon aria-hidden="true" size={14} />
      {t(`status.${health}`)}
    </span>
  );
}
