import { useEffect, useState, useCallback } from "react";
import { timeAgo, formatDateTime } from "../utils/time";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4511";

interface StatsData {
  my_activity: {
    prs_reviewed: number;
    prs_approved: number;
    changes_requested: number;
    review_comments: number;
  };
  my_prs: {
    opened: number;
    merged: number;
    avg_time_to_first_review_hours: number | null;
    avg_time_to_merge_hours: number | null;
  };
  teammate_activity: Array<{
    user: string;
    reviewed: number;
    approved: number;
    changes_requested: number;
    comments: number;
    is_me: boolean;
  }>;
  overview: {
    total_prs_opened: number;
    total_prs_merged: number;
    avg_time_to_first_review_hours: number | null;
    avg_pr_size: number;
  };
  updated_at: string | null;
  window_days: number;
}

type SortKey = "user" | "reviewed" | "approved" | "changes_requested" | "comments";
type SortDir = "asc" | "desc";

function formatHours(h: number | null): string {
  if (h === null) return "\u2014";
  if (h < 1) return `${Math.round(h * 60)}m`;
  if (h < 24) return `${h.toFixed(1)}h`;
  return `${(h / 24).toFixed(1)}d`;
}

export function StatsPage() {
  const [data, setData] = useState<StatsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [changingWindow, setChangingWindow] = useState(false);
  const [sortKey, setSortKey] = useState<SortKey>("reviewed");
  const [sortDir, setSortDir] = useState<SortDir>("desc");

  const fetchData = useCallback(async () => {
    if (document.hidden) return;
    try {
      const res = await fetch(`${API_URL}/api/stats`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json: StatsData = await res.json();
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
      const res = await fetch(`${API_URL}/api/refresh/stats`, { method: "POST" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json: StatsData = await res.json();
      setData(json);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Refresh failed");
    } finally {
      setRefreshing(false);
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, data?.updated_at ? 30_000 : 3_000);
    const onVisible = () => { if (!document.hidden) fetchData(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [fetchData, data?.updated_at]);

  const changeWindow = async (days: number) => {
    setChangingWindow(true);
    try {
      const res = await fetch(`${API_URL}/api/stats_window`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ window_days: days }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json: StatsData = await res.json();
      setData(json);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to change window");
    } finally {
      setChangingWindow(false);
    }
  };

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortDir(sortDir === "desc" ? "asc" : "desc");
    } else {
      setSortKey(key);
      setSortDir(key === "user" ? "asc" : "desc");
    }
  };

  const sortedTeammates = data?.teammate_activity
    ? [...data.teammate_activity].sort((a, b) => {
        const av = a[sortKey];
        const bv = b[sortKey];
        if (typeof av === "string" && typeof bv === "string") {
          return sortDir === "asc" ? av.localeCompare(bv) : bv.localeCompare(av);
        }
        return sortDir === "asc" ? (av as number) - (bv as number) : (bv as number) - (av as number);
      })
    : [];

  const sortArrow = (key: SortKey) =>
    sortKey === key ? (sortDir === "desc" ? " \u25BC" : " \u25B2") : "";

  const updatedAtRelative = data?.updated_at ? timeAgo(data.updated_at) : "\u2014";
  const updatedAtAbsolute = data?.updated_at ? formatDateTime(data.updated_at) : "";

  return (
    <>
      <header>
        <div className="header-left">
          <h1>PR Statistics</h1>
          {data && data.updated_at && (
            <span className="subtitle" title={updatedAtAbsolute}>
              last {data.window_days}d &middot; updated {updatedAtRelative}
            </span>
          )}
        </div>
        <div className="header-actions">
          <select
            className="days-select"
            value={data?.window_days ?? 7}
            disabled={changingWindow}
            onChange={(e) => changeWindow(Number(e.target.value))}
          >
            {[7, 14, 21, 28].map((d) => (
              <option key={d} value={d}>{d} days</option>
            ))}
          </select>
          <button
            className="refresh-btn"
            onClick={triggerRefresh}
            disabled={refreshing}
          >
            {refreshing ? "Refreshing\u2026" : "Refresh"}
          </button>
        </div>
      </header>

      {loading && <div className="loading">Loading\u2026</div>}
      {error && <div className="error">Error: {error}</div>}

      {!loading && data && !data.updated_at && (
        <div className="loading">Computing statistics from GitHub data\u2026</div>
      )}

      {data && data.updated_at && (
        <div className="stats-grid">
          {/* My Review Activity */}
          <div className="stats-card">
            <h3>My Review Activity</h3>
            <div className="stats-metrics">
              <div className="stats-metric">
                <span className="stats-metric-value">{data.my_activity.prs_reviewed}</span>
                <span className="stats-metric-label">PRs Reviewed</span>
              </div>
              <div className="stats-metric">
                <span className="stats-metric-value stats-approved">{data.my_activity.prs_approved}</span>
                <span className="stats-metric-label">Approved</span>
              </div>
              <div className="stats-metric">
                <span className="stats-metric-value stats-changes">{data.my_activity.changes_requested}</span>
                <span className="stats-metric-label">Changes Requested</span>
              </div>
              <div className="stats-metric">
                <span className="stats-metric-value">{data.my_activity.review_comments}</span>
                <span className="stats-metric-label">Review Comments</span>
              </div>
            </div>
          </div>

          {/* My PRs */}
          <div className="stats-card">
            <h3>My PRs</h3>
            <div className="stats-metrics">
              <div className="stats-metric">
                <span className="stats-metric-value">{data.my_prs.opened}</span>
                <span className="stats-metric-label">Opened</span>
              </div>
              <div className="stats-metric">
                <span className="stats-metric-value stats-merged">{data.my_prs.merged}</span>
                <span className="stats-metric-label">Merged</span>
              </div>
              <div className="stats-metric">
                <span className="stats-metric-value">{formatHours(data.my_prs.avg_time_to_first_review_hours)}</span>
                <span className="stats-metric-label">Avg Time to Review</span>
              </div>
              <div className="stats-metric">
                <span className="stats-metric-value">{formatHours(data.my_prs.avg_time_to_merge_hours)}</span>
                <span className="stats-metric-label">Avg Time to Merge</span>
              </div>
            </div>
          </div>

          {/* Team Overview */}
          <div className="stats-card">
            <h3>Team Overview</h3>
            <div className="stats-metrics">
              <div className="stats-metric">
                <span className="stats-metric-value">{data.overview.total_prs_opened}</span>
                <span className="stats-metric-label">PRs Opened</span>
              </div>
              <div className="stats-metric">
                <span className="stats-metric-value stats-merged">{data.overview.total_prs_merged}</span>
                <span className="stats-metric-label">PRs Merged</span>
              </div>
              <div className="stats-metric">
                <span className="stats-metric-value">{formatHours(data.overview.avg_time_to_first_review_hours)}</span>
                <span className="stats-metric-label">Avg Time to Review</span>
              </div>
              <div className="stats-metric">
                <span className="stats-metric-value">{data.overview.avg_pr_size}</span>
                <span className="stats-metric-label">Avg PR Size (lines)</span>
              </div>
            </div>
          </div>

          {/* Teammate Activity Table */}
          <div className="stats-card stats-card-wide">
            <h3>Teammate Activity</h3>
            {data.teammate_activity.length === 0 ? (
              <div className="empty">No teammate activity in the last {data.window_days} days</div>
            ) : (
              <table className="stats-table">
                <thead>
                  <tr>
                    <th className={`sortable${sortKey === "user" ? " sort-active" : ""}`} onClick={() => toggleSort("user")}>User{sortArrow("user")}</th>
                    <th className={`sortable${sortKey === "reviewed" ? " sort-active" : ""}`} onClick={() => toggleSort("reviewed")}>Reviewed{sortArrow("reviewed")}</th>
                    <th className={`sortable${sortKey === "approved" ? " sort-active" : ""}`} onClick={() => toggleSort("approved")}>Approved{sortArrow("approved")}</th>
                    <th className={`sortable${sortKey === "changes_requested" ? " sort-active" : ""}`} onClick={() => toggleSort("changes_requested")}>Changes Req.{sortArrow("changes_requested")}</th>
                    <th className={`sortable${sortKey === "comments" ? " sort-active" : ""}`} onClick={() => toggleSort("comments")}>Comments{sortArrow("comments")}</th>
                  </tr>
                </thead>
                <tbody>
                  {sortedTeammates.map((t) => (
                    <tr key={t.user} className={t.is_me ? "stats-me-row" : ""}>
                      <td>{t.is_me ? <strong>{t.user} (me)</strong> : t.user}</td>
                      <td>{t.reviewed}</td>
                      <td className="stats-approved">{t.approved}</td>
                      <td className="stats-changes">{t.changes_requested}</td>
                      <td>{t.comments}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      )}
    </>
  );
}
