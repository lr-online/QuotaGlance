import * as React from "react";
import { cn } from "@/lib/cn";

export type BadgeProps = React.HTMLAttributes<HTMLSpanElement> & {
  tone?: "neutral" | "healthy" | "warning" | "danger";
};

export function Badge({ className, tone = "neutral", children, ...rest }: BadgeProps) {
  const tones: Record<NonNullable<BadgeProps["tone"]>, string> = {
    neutral: "bg-qg-neutral/10 text-qg-neutral",
    healthy: "bg-qg-success/15 text-qg-success",
    warning: "bg-qg-warning/15 text-qg-warning",
    danger: "bg-qg-danger/15 text-qg-danger",
  };
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium",
        tones[tone],
        className,
      )}
      {...rest}
    >
      {children}
    </span>
  );
}
