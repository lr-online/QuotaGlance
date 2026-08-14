import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import WidgetApp from "./pages/Widget";
import "./styles/index.css";
import "./i18n";

const rootEl = document.getElementById("root");
if (!rootEl) {
  throw new Error("QuotaGlance widget: missing #root element");
}

createRoot(rootEl).render(
  <StrictMode>
    <WidgetApp />
  </StrictMode>,
);
