import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import App from "./App";
import { ReviewPage } from "./pages/ReviewPage";
import { MyPRsPage } from "./pages/MyPRsPage";
import { SettingsPage } from "./pages/SettingsPage";
import { PRViewPage } from "./pages/PRViewPage";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <Routes>
        <Route element={<App />}>
          <Route index element={<ReviewPage />} />
          <Route path="my-prs" element={<MyPRsPage />} />
          <Route path="pr/:owner/:repo/:number" element={<PRViewPage />} />
          <Route path="settings" element={<SettingsPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  </StrictMode>
);
