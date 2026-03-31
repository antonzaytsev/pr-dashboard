import { useState, useEffect, useCallback } from "react";
import type { ColumnKey } from "../types";
import { ALL_COLUMNS } from "../types";
import { useColumnVisibility } from "../hooks/useColumnVisibility";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4511";

interface RepoOption {
  id: string;
  label: string;
}

export function SettingsPage() {
  const { visibleColumns, toggleColumn } = useColumnVisibility();
  const [daysWindow, setDaysWindow] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedMsg, setSavedMsg] = useState<string | null>(null);
  const [availableRepos, setAvailableRepos] = useState<RepoOption[]>([]);
  const [enabledRepos, setEnabledRepos] = useState<string[]>([]);
  const [repoSaving, setRepoSaving] = useState(false);
  const [repoMsg, setRepoMsg] = useState<string | null>(null);

  const syncToBackend = useCallback(async (days: number) => {
    await fetch(`${API_URL}/api/days_window`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ days_window: days }),
    });
  }, []);

  useEffect(() => {
    fetch(`${API_URL}/api/repos`)
      .then((res) => (res.ok ? res.json() : null))
      .then((json) => {
        if (json) {
          setAvailableRepos(json.available);
          setEnabledRepos(json.enabled);
        }
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    const stored = localStorage.getItem("days_window");
    if (stored) {
      const days = Number(stored);
      setDaysWindow(days);
      syncToBackend(days).catch(() => {});
    } else {
      fetch(`${API_URL}/api/prs`)
        .then((res) => res.ok ? res.json() : null)
        .then((json) => { if (json) setDaysWindow(json.days_window); })
        .catch(() => {});
    }
  }, [syncToBackend]);

  const saveDaysWindow = async (days: number) => {
    setSaving(true);
    setSavedMsg(null);
    try {
      const res = await fetch(`${API_URL}/api/days_window`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ days_window: days }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setDaysWindow(days);
      localStorage.setItem("days_window", String(days));
      setSavedMsg("Saved");
      setTimeout(() => setSavedMsg(null), 2000);
    } catch {
      setSavedMsg("Failed to save");
    } finally {
      setSaving(false);
    }
  };

  const toggleRepo = async (repoId: string) => {
    const updated = enabledRepos.includes(repoId)
      ? enabledRepos.filter((r) => r !== repoId)
      : [...enabledRepos, repoId];
    if (updated.length === 0) return;
    setRepoSaving(true);
    setRepoMsg(null);
    try {
      const res = await fetch(`${API_URL}/api/repos`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repos: updated }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setEnabledRepos(updated);
      setRepoMsg("Saved");
      setTimeout(() => setRepoMsg(null), 2000);
    } catch {
      setRepoMsg("Failed to save");
    } finally {
      setRepoSaving(false);
    }
  };

  const hideableColumns = ALL_COLUMNS.filter((c) => c.hideable);

  return (
    <>
      <header>
        <div className="header-left">
          <h1>Settings</h1>
        </div>
      </header>

      <div className="settings-sections">
        <div className="settings-card">
          <h3>Repositories</h3>
          <p className="settings-desc">
            Choose which GitHub repositories to show PRs from.
          </p>
          <div className="settings-columns-grid">
            {availableRepos.map((repo) => (
              <label key={repo.id} className="settings-column-item">
                <input
                  type="checkbox"
                  checked={enabledRepos.includes(repo.id)}
                  disabled={repoSaving || (enabledRepos.includes(repo.id) && enabledRepos.length === 1)}
                  onChange={() => toggleRepo(repo.id)}
                />
                {repo.label}
              </label>
            ))}
          </div>
          {repoMsg && (
            <span className={`settings-msg ${repoMsg === "Saved" ? "ok" : "err"}`}>
              {repoMsg}
            </span>
          )}
        </div>

        <div className="settings-card">
          <h3>Timeframe</h3>
          <p className="settings-desc">
            Show PRs updated within the last N days.
          </p>
          <div className="settings-row">
            <select
              className="days-select"
              value={daysWindow ?? ""}
              disabled={saving || daysWindow === null}
              onChange={(e) => saveDaysWindow(Number(e.target.value))}
            >
              {[1, 2, 3, 5, 7, 14, 21, 30].map((d) => (
                <option key={d} value={d}>
                  {d} {d === 1 ? "day" : "days"}
                </option>
              ))}
            </select>
            {savedMsg && (
              <span className={`settings-msg ${savedMsg === "Saved" ? "ok" : "err"}`}>
                {savedMsg}
              </span>
            )}
          </div>
        </div>

        <div className="settings-card">
          <h3>Visible Columns</h3>
          <p className="settings-desc">
            Choose which columns appear in the PR tables. PR and Title are
            always shown.
          </p>
          <div className="settings-columns-grid">
            {hideableColumns.map((col) => (
              <label key={col.key} className="settings-column-item">
                <input
                  type="checkbox"
                  checked={visibleColumns.has(col.key as ColumnKey)}
                  onChange={() => toggleColumn(col.key as ColumnKey)}
                />
                {col.label}
              </label>
            ))}
          </div>
        </div>
      </div>
    </>
  );
}
