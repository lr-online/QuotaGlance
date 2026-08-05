import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import PopoverApp from "./pages/Popover";
import "./styles/index.css";
import "./i18n";

const rootEl = document.getElementById("root");
if (!rootEl) {
  throw new Error("QuotaGlance popover: missing #root element");
}

createRoot(rootEl).render(
  <StrictMode>
    <PopoverApp />
  </StrictMode>,
);
