// Tauri 2 React entry that mounts the main window. Mirrors the macOS /
// Android top-level shell: a sidebar of accounts on the left, a detail
// pane on the right, a status footer. The App component handles routing
// via HashRouter (works under tauri:// and https://tauri.localhost
// without server-side fallback).

import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import App from "./App";
import "./styles/index.css";
import "./i18n";

const rootEl = document.getElementById("root");
if (!rootEl) {
  throw new Error("QuotaGlance Windows front end: missing #root element");
}

createRoot(rootEl).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
