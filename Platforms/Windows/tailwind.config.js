/**
 * Tailwind configuration for the QuotaGlance Windows front end.
 *
 * The colour tokens below mirror the macOS design language declared in
 * `App/` (see Sources/QuotaGlanceCore/Presentation/StyleTokens.swift) and
 * feed into `src/styles/tokens.css`. Visual fidelity to macOS is the goal;
 * the system-tray, right-click menu, flyout and other platform-native
 * interactions are owned by the front-end components themselves.
 *
 * Typography falls back through Helvetica Neue (macOS echo) -> Segoe UI
 * Variable (Windows 11 modern control text) -> Microsoft YaHei UI (zh-CN).
 *
 * Do not introduce fresh colours here without parallel updates to the L10n /
 * design-token tables and to Windows/AGENTS.md.
 */
/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ["class"],
  content: ["./index.html", "./popover.html", "./widget.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // macOS-mirrored palette (see design_guidelines.colors).
        "qg-blue": {
          DEFAULT: "#007AFF",
          dark: "#0A84FF",
          violet: "#5E5CE6",
        },
        "qg-bg": {
          light: "#FFFFFF",
          "light-2": "#F2F2F7",
          dark: "#1E1E1E",
          "dark-2": "#2C2C2E",
        },
        "qg-text": {
          light: "#000000",
          "light-2": "#3C3C43",
          dark: "#FFFFFF",
          "dark-2": "#EBEBF5",
        },
        "qg-success": "#34C759",
        "qg-warning": "#FF9500",
        "qg-danger": "#FF3B30",
        "qg-neutral": "#8E8E93",
      },
      fontFamily: {
        sans: [
          '"Helvetica Neue"',
          '"Segoe UI Variable"',
          '"Microsoft YaHei UI"',
          "system-ui",
          "sans-serif",
        ],
        mono: ["ui-monospace", "SFMono-Regular", "Consolas", "monospace"],
      },
      borderRadius: {
        qg: "8px",
        "qg-lg": "8px",
        "qg-xl": "8px",
      },
      boxShadow: {
        qg: "0 6px 24px rgba(0,0,0,0.18)",
        "qg-sm": "0 2px 8px rgba(0,0,0,0.12)",
      },
      transitionTimingFunction: {
        "qg-ease": "cubic-bezier(0.4, 0, 0.2, 1)",
      },
      animation: {
        "qg-fade-in": "qg-fade-in 0.18s cubic-bezier(0.4, 0, 0.2, 1)",
      },
      keyframes: {
        "qg-fade-in": {
          "0%": { opacity: "0", transform: "translateY(-4px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
};
