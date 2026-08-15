import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/cn";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 rounded-qg text-sm font-medium transition-all " +
    "focus:outline-none focus:ring-2 focus:ring-qg-blue/40 focus:ring-offset-1 " +
    "disabled:pointer-events-none disabled:opacity-50 " +
    "active:scale-[0.98] motion-safe:transition-transform",
  {
    variants: {
      variant: {
        primary: "bg-qg-blue text-white hover:bg-qg-blue-dark",
        secondary:
          "border border-qg-neutral/30 bg-transparent text-qg-text-light dark:text-qg-text-dark hover:bg-qg-bg-light-2 dark:hover:bg-qg-bg-dark-2",
        ghost:
          "bg-transparent text-qg-text-light dark:text-qg-text-dark hover:bg-qg-bg-light-2 dark:hover:bg-qg-bg-dark-2",
        danger: "bg-qg-danger text-white hover:bg-qg-danger/90",
      },
      size: {
        sm: "h-10 px-3",
        md: "h-11 px-4",
        lg: "h-12 px-5",
        icon: "size-11",
      },
    },
    defaultVariants: { variant: "primary", size: "md" },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  loading?: boolean;
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  function Button({ className, variant, size, loading, children, disabled, ...rest }, ref) {
    return (
      <button
        ref={ref}
        className={cn(buttonVariants({ variant, size }), className)}
        disabled={disabled || loading}
        {...rest}
      >
        {loading ? (
          <span className="inline-block size-3 animate-spin rounded-full border-2 border-current border-t-transparent" />
        ) : null}
        {children}
      </button>
    );
  },
);

export { buttonVariants };
