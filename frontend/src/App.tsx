import { useEffect, useState, useCallback } from "react";
import type { PRData } from "./types";
import { PRSection } from "./components/PRSection";
import "./App.css";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4567";

function App() {
  const [data, setData] = useState<PRData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const fetchData = useCallback(async () => {
    try {
      const res = await fetch(`${API_URL}/api/prs`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json: PRData = await res.json();
      setData(json);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to fetch");
    } finally {
      setLoading(false);
    }
  }, []);

  const triggerRefresh = async () => {
    setRefreshing(true);
    try {
      const res = await fetch(`${API_URL}/api/refresh`, { method: "POST" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json: PRData = await res.json();
      setData(json);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Refresh failed");
    } finally {
      setRefreshing(false);
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 30_000);
    return () => clearInterval(interval);
  }, [fetchData]);

  const updatedAt = data?.updated_at
    ? new Date(data.updated_at).toLocaleTimeString()
    : "—";

  return (
    <div className="app">
      <header>
        <div className="header-left">
          <h1>PRs to Review</h1>
          {data && (
            <span className="subtitle">
              {data.total} open · last {data.days_window}d · updated {updatedAt}
            </span>
          )}
        </div>
        <button
          className="refresh-btn"
          onClick={triggerRefresh}
          disabled={refreshing}
        >
          {refreshing ? "Refreshing…" : "Refresh"}
        </button>
      </header>

      {loading && <div className="loading">Loading…</div>}
      {error && <div className="error">Error: {error}</div>}

      {data?.sections.map((section) => (
        <PRSection key={section.id} section={section} />
      ))}
    </div>
  );
}

export default App;
