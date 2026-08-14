// Mirrors `Sources/QuotaGlanceCore/Storage/Preferences.swift`'s
// JSON shape. Kept tiny: the actual persistence lives in Rust; the
// front-end only reasons in DTO form before invoking a command.

export type Locale = "system" | "en" | "zh-CN";

export type WidgetTarget =
  | { kind: "all" }
  | { kind: "account"; account_id: string }
  | { kind: "defaultAccount" };
