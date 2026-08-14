import * as React from "react";
import { cn } from "@/lib/cn";

export interface SwitchProps {
  checked: boolean;
  onCheckedChange: (next: boolean) => void;
  disabled?: boolean;
  id?: string;
  label?: React.ReactNode;
  description?: React.ReactNode;
  className?: string;
}

export function Switch({ checked, onCheckedChange, disabled, id, label, description, className }: SwitchProps) {
  return (
    <label
      htmlFor={id}
      className={cn(
        "flex items-center justify-between gap-4 rounded-qg px-3 py-2",
        disabled ? "opacity-50" : "cursor-pointer hover:bg-qg-bg-light-2 dark:hover:bg-qg-bg-dark-2",
        className,
      )}
    >
      <div className="flex flex-col">
        {label ? <span className="text-sm font-medium">{label}</span> : null}
        {description ? <span className="text-xs text-qg-neutral">{description}</span> : null}
      </div>
      <span
        role="switch"
        aria-checked={checked}
        tabIndex={0}
        onClick={() => !disabled && onCheckedChange(!checked)}
        onKeyDown={(event) => {
          if (event.key === " " || event.key === "Enter") {
            event.preventDefault();
            if (!disabled) onCheckedChange(!checked);
          }
        }}
        className={cn(
          "relative inline-flex h-5 w-9 items-center rounded-full transition",
          checked ? "bg-qg-blue" : "bg-qg-neutral/40",
        )}
      >
        <span
          className={cn(
            "absolute top-0.5 size-4 rounded-full bg-white shadow-qg-sm transition",
            checked ? "left-4" : "left-0.5",
          )}
        />
      </span>
    </label>
  );
}
