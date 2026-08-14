import * as React from "react";
import { cn } from "@/lib/cn";

export interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  title?: React.ReactNode;
  description?: React.ReactNode;
  action?: React.ReactNode;
}

export function Card({ className, title, description, action, children, ...rest }: CardProps) {
  return (
    <section
      className={cn(
        "rounded-qg-lg border border-black/5 bg-qg-bg-light p-6 shadow-qg-sm dark:border-white/5 dark:bg-qg-bg-dark-2",
        className,
      )}
      {...rest}
    >
      {(title || description || action) && (
        <header className="flex items-start justify-between gap-4">
          <div>
            {title ? <h3 className="text-sm font-semibold tracking-tight">{title}</h3> : null}
            {description ? (
              <p className="mt-1 text-xs text-qg-neutral">{description}</p>
            ) : null}
          </div>
          {action ? <div className="shrink-0">{action}</div> : null}
        </header>
      )}
      <div className={cn(title || description || action ? "mt-4" : "")}>{children}</div>
    </section>
  );
}

export function CardGrid({ children, className, ...rest }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "grid gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4",
        className,
      )}
      {...rest}
    >
      {children}
    </div>
  );
}
