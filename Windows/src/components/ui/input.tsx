import * as React from "react";
import { cn } from "@/lib/cn";

export type InputProps = React.InputHTMLAttributes<HTMLInputElement>;

export const Input = React.forwardRef<HTMLInputElement, InputProps>(function Input(
  { className, type = "text", ...rest },
  ref,
) {
  return (
    <input
      ref={ref}
      type={type}
      className={cn(
        "flex h-11 w-full rounded-qg border border-qg-neutral/30 bg-transparent px-3 py-1 text-base shadow-qg-sm",
        "placeholder:text-qg-neutral",
        "focus:outline-none focus:ring-2 focus:ring-qg-blue/40 focus:ring-offset-1",
        "disabled:cursor-not-allowed disabled:opacity-50",
        className,
      )}
      {...rest}
    />
  );
});

export type TextareaProps = React.TextareaHTMLAttributes<HTMLTextAreaElement>;

export const Textarea = React.forwardRef<HTMLTextAreaElement, TextareaProps>(function Textarea(
  { className, ...rest },
  ref,
) {
  return (
    <textarea
      ref={ref}
      className={cn(
        "flex min-h-28 w-full rounded-qg border border-qg-neutral/30 bg-transparent px-3 py-2 text-base shadow-qg-sm",
        "placeholder:text-qg-neutral focus:outline-none focus:ring-2 focus:ring-qg-blue/40 focus:ring-offset-1",
        className,
      )}
      {...rest}
    />
  );
});
