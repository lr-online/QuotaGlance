import type { ReactNode } from "react";
import { ArrowLeft, BarChart3, CirclePlus, Settings } from "lucide-react";
import { NavLink, useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";

import { cn } from "@/lib/cn";

interface PageShellProps {
  title: string;
  subtitle?: string;
  children: ReactNode;
  action?: ReactNode;
  backTo?: string;
}

export function PageShell({ title, subtitle, children, action, backTo }: PageShellProps) {
  const navigate = useNavigate();

  return (
    <div className="qg-app-shell">
      <header className="qg-page-header">
        <div className="flex min-w-0 items-center gap-3">
          {backTo ? (
            <button
              className="qg-icon-button"
              type="button"
              aria-label="Go back"
              onClick={() => navigate(backTo)}
            >
              <ArrowLeft aria-hidden="true" size={20} />
            </button>
          ) : null}
          <div className="min-w-0">
            <h1 className="truncate text-xl font-semibold text-qg-text-light dark:text-qg-text-dark">{title}</h1>
            {subtitle ? <p className="mt-0.5 text-sm text-qg-neutral">{subtitle}</p> : null}
          </div>
        </div>
        {action ? <div className="shrink-0">{action}</div> : null}
      </header>
      <main className="qg-page-content" tabIndex={-1}>{children}</main>
      <BottomNav />
    </div>
  );
}

function BottomNav() {
  const { t } = useTranslation();
  const entries = [
    { to: "/", label: t("nav.overview"), icon: BarChart3, end: true },
    { to: "/add", label: t("nav.addProvider"), icon: CirclePlus },
    { to: "/settings", label: t("nav.settings"), icon: Settings },
  ];
  return (
    <nav className="qg-bottom-nav" aria-label="Primary navigation">
      {entries.map(({ to, label, icon: Icon, end }) => (
        <NavLink
          key={to}
          to={to}
          end={end}
          className={({ isActive }) => cn("qg-nav-item", isActive && "qg-nav-item-active")}
        >
          <Icon aria-hidden="true" size={20} strokeWidth={2} />
          <span>{label}</span>
        </NavLink>
      ))}
    </nav>
  );
}
