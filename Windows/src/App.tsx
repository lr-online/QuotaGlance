import { useEffect } from "react";
import { HashRouter, Navigate, Route, Routes, useNavigate } from "react-router-dom";

import AccountDetail from "@/pages/AccountDetail";
import AccountEdit from "@/pages/AccountEdit";
import AddProvider from "@/pages/AddProvider";
import Overview from "@/pages/Overview";
import SettingsPage from "@/pages/Settings";
import { commands, events } from "@/lib/tauri-bindings";
import "@/i18n";

function IntentBridge() {
  const navigate = useNavigate();
  useEffect(() => {
    const route = (raw: string) => {
      try {
        const url = new URL(raw);
        if (url.protocol !== "quotaglance:") return;
        if (url.hostname === "all") navigate("/");
        if (url.hostname === "settings") navigate("/settings");
        if (url.hostname === "account" && url.pathname.length > 1) {
          navigate(`/accounts/${url.pathname.slice(1)}`);
        }
      } catch {
        // Ignore malformed external links rather than interrupting the current view.
      }
    };
    void commands.getIntentPayload().then((payload) => payload && route(payload));
    let unlisten: (() => void) | undefined;
    void events.onDeepLink(route).then((release) => { unlisten = release; });
    return () => unlisten?.();
  }, [navigate]);
  return null;
}

function TrayRefreshBridge() {
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    void events.onMenuRefreshAll(() => { void commands.refreshAll(); }).then((release) => { unlisten = release; });
    return () => unlisten?.();
  }, []);
  return null;
}

export default function App() {
  return (
    <HashRouter>
      <IntentBridge />
      <TrayRefreshBridge />
      <Routes>
        <Route path="/" element={<Overview />} />
        <Route path="/accounts/:id" element={<AccountDetail />} />
        <Route path="/accounts/:id/edit" element={<AccountEdit />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="/add" element={<AddProvider />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </HashRouter>
  );
}
