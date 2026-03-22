import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import App from "./App";
import { ReviewPage } from "./pages/ReviewPage";
import { MyPRsPage } from "./pages/MyPRsPage";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <Routes>
        <Route element={<App />}>
          <Route index element={<ReviewPage />} />
          <Route path="my-prs" element={<MyPRsPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  </StrictMode>
);
