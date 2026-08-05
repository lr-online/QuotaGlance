// i18n bootstrap. Detects `system` locale by reading `navigator.language`
// and falls through to `en` for any unknown BCP-47 tag. The two active
// resource sets mirror `Sources/QuotaGlanceCore/Presentation/L10n.swift`
// `L10n.Localized`. New keys must land in en.json and zh-CN.json
// together; the cross-platform parity script verifies key presence when
// it gets wired in.

import i18n from "i18next";
import { initReactI18next } from "react-i18next";

import en from "./en.json";
import zhCN from "./zh-CN.json";

type ResourceBundle = "en" | "zh-CN";

function detectSystemLanguage(): ResourceBundle {
  const raw = (navigator?.language ?? "en").toLowerCase();
  if (raw.startsWith("zh")) return "zh-CN";
  if (raw.startsWith("en")) return "en";
  return "en";
}

export type { ResourceBundle };

export const SUPPORTED_LOCALES: ResourceBundle[] = ["en", "zh-CN"];

export function resolveLocale(preference: "system" | ResourceBundle): ResourceBundle {
  if (preference === "system") return detectSystemLanguage();
  return preference;
}

void i18n.use(initReactI18next).init({
  resources: {
    en: { translation: en },
    "zh-CN": { translation: zhCN },
  },
  lng: detectSystemLanguage(),
  fallbackLng: "en",
  interpolation: {
    escapeValue: false,
  },
});

export default i18n;
