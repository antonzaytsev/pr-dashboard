import { useEffect, useState, useCallback } from "react";
import type { PRData } from "../types";
import { PRSection } from "../components/PRSection";
import { useColumnVisibility } from "../hooks/useColumnVisibility";
import { timeAgo, formatDateTime } from "../utils/time";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4511";

export function MyPRsPage() {
  const [data, setData] = useState<PRData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const { visibleColumns } = useColumnVisibility();

  const fetchData = useCallback(async () => {
    try {
      const res = await fetch(`${API_URL}/api/my-prs`);
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
      await fetchData();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Refresh failed");
    } finally {
      setRefreshing(false);
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, data?.updated_at ? 30_000 : 3_000);
    return () => clearInterval(interval);
  }, [fetchData, data?.updated_at]);

  const updatedAtRelative = data?.updated_at ? timeAgo(data.updated_at) : "—";
  const updatedAtAbsolute = data?.updated_at ? formatDateTime(data.updated_at) : "";

  return (
    <>
      <header>
        <div className="header-left">
          <h1>My PRs</h1>
          {data && data.updated_at && (
            <span className="subtitle" title={updatedAtAbsolute}>
              {data.total} open · last {data.days_window}d · updated {updatedAtRelative}
            </span>
          )}
        </div>
        <div className="header-actions">
          <button
            className="refresh-btn"
            onClick={triggerRefresh}
            disabled={refreshing}
          >
            {refreshing ? "Refreshing…" : "Refresh"}
          </button>
        </div>
      </header>

      {loading && <div className="loading">Loading…</div>}
      {error && <div className="error">Error: {error}</div>}

      {!loading && data && !data.updated_at && (
        <div className="loading">Fetching PRs from GitHub, this may take a moment…</div>
      )}

      {data?.sections.map((section) => (
        <PRSection
          key={section.id}
          section={section}
          visibleColumns={visibleColumns}
        />
      ))}
    </>
  );
}
