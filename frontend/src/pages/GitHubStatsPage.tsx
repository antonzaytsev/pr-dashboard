import { useEffect, useState, useCallback } from "react";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
} from "recharts";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4511";

interface RateLimitSnapshot {
  remaining: number;
  limit: number;
  used: number;
  reset: number;
  recorded_at: string;
}

interface ChartPoint {
  time: string;
  timestamp: number;
  remaining: number;
  used: number;
  limit: number;
  pct: number;
}

function formatTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function formatDateTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function GitHubStatsPage() {
  const [history, setHistory] = useState<RateLimitSnapshot[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchHistory = useCallback(async () => {
    try {
      const res = await fetch(`${API_URL}/api/rate-limit-history`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json: RateLimitSnapshot[] = await res.json();
      setHistory(json);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to fetch");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchHistory();
    const id = setInterval(fetchHistory, 30_000);
    return () => clearInterval(id);
  }, [fetchHistory]);

  const chartData: ChartPoint[] = history.map((s) => ({
    time: formatTime(s.recorded_at),
    timestamp: new Date(s.recorded_at).getTime(),
    remaining: s.remaining,
    used: s.limit - s.remaining,
    limit: s.limit,
    pct: Math.round((s.remaining / s.limit) * 100),
  }));

  const currentLimit = chartData.length > 0 ? chartData[chartData.length - 1].limit : 5000;

  return (
    <>
      <header>
        <div className="header-left">
          <h1>GitHub Statistics</h1>
          {history.length > 0 && (
            <span className="subtitle">
              {history.length} data points
              {history.length >= 2 &&
                ` · ${formatDateTime(history[0].recorded_at)} — ${formatDateTime(history[history.length - 1].recorded_at)}`}
            </span>
          )}
        </div>
      </header>

      {loading && <div className="loading">Loading…</div>}
      {error && <div className="error">Error: {error}</div>}

      {!loading && history.length === 0 && (
        <div className="loading">
          No API limit history yet. Data is recorded each time the app makes a
          GitHub API call.
        </div>
      )}

      {history.length > 0 && (
        <div className="gh-stats-grid">
          {/* Remaining / Used chart */}
          <div className="stats-card stats-card-wide">
            <h3>API Limits Over Time</h3>
            <div className="gh-stats-chart">
              <ResponsiveContainer width="100%" height={320}>
                <AreaChart data={chartData} margin={{ top: 8, right: 16, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="gradRemaining" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#3fb950" stopOpacity={0.3} />
                      <stop offset="95%" stopColor="#3fb950" stopOpacity={0.02} />
                    </linearGradient>
                    <linearGradient id="gradUsed" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#f85149" stopOpacity={0.3} />
                      <stop offset="95%" stopColor="#f85149" stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="#21262d" />
                  <XAxis
                    dataKey="time"
                    stroke="#8b949e"
                    fontSize={11}
                    tickLine={false}
                  />
                  <YAxis
                    stroke="#8b949e"
                    fontSize={11}
                    tickLine={false}
                    domain={[0, currentLimit]}
                  />
                  <Tooltip
                    contentStyle={{
                      background: "#161b22",
                      border: "1px solid #30363d",
                      borderRadius: "6px",
                      fontSize: "12px",
                      color: "#c9d1d9",
                    }}
                    labelStyle={{ color: "#8b949e" }}
                  />
                  <ReferenceLine
                    y={currentLimit * 0.1}
                    stroke="#d29922"
                    strokeDasharray="6 3"
                    label={{
                      value: "10% threshold",
                      position: "right",
                      fill: "#d29922",
                      fontSize: 11,
                    }}
                  />
                  <Area
                    type="monotone"
                    dataKey="remaining"
                    name="Remaining"
                    stroke="#3fb950"
                    fill="url(#gradRemaining)"
                    strokeWidth={2}
                    dot={false}
                    activeDot={{ r: 3, fill: "#3fb950" }}
                  />
                  <Area
                    type="monotone"
                    dataKey="used"
                    name="Used"
                    stroke="#f85149"
                    fill="url(#gradUsed)"
                    strokeWidth={2}
                    dot={false}
                    activeDot={{ r: 3, fill: "#f85149" }}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Percentage chart */}
          <div className="stats-card stats-card-wide">
            <h3>Available Capacity (%)</h3>
            <div className="gh-stats-chart">
              <ResponsiveContainer width="100%" height={200}>
                <AreaChart data={chartData} margin={{ top: 8, right: 16, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="gradPct" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#58a6ff" stopOpacity={0.3} />
                      <stop offset="95%" stopColor="#58a6ff" stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="#21262d" />
                  <XAxis
                    dataKey="time"
                    stroke="#8b949e"
                    fontSize={11}
                    tickLine={false}
                  />
                  <YAxis
                    stroke="#8b949e"
                    fontSize={11}
                    tickLine={false}
                    domain={[0, 100]}
                    tickFormatter={(v: number) => `${v}%`}
                  />
                  <Tooltip
                    contentStyle={{
                      background: "#161b22",
                      border: "1px solid #30363d",
                      borderRadius: "6px",
                      fontSize: "12px",
                      color: "#c9d1d9",
                    }}
                    labelStyle={{ color: "#8b949e" }}
                    formatter={(value: number) => [`${value}%`, "Available"]}
                  />
                  <ReferenceLine
                    y={10}
                    stroke="#d29922"
                    strokeDasharray="6 3"
                  />
                  <Area
                    type="monotone"
                    dataKey="pct"
                    name="Available %"
                    stroke="#58a6ff"
                    fill="url(#gradPct)"
                    strokeWidth={2}
                    dot={false}
                    activeDot={{ r: 3, fill: "#58a6ff" }}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
