import { useState, useEffect } from "react";
import { NavLink, Outlet } from "react-router-dom";
import "./App.css";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4511";

interface RateLimit {
  limit: number;
  used: number;
  remaining: number;
  reset: number;
  updated_at: string | null;
}

function RateLimitIndicator() {
  const [rl, setRl] = useState<RateLimit | null>(null);

  useEffect(() => {
    const fetchRL = () => {
      fetch(`${API_URL}/api/rate-limit`)
        .then((r) => (r.ok ? r.json() : null))
        .then(setRl)
        .catch(() => setRl(null));
    };
    fetchRL();
    const id = setInterval(fetchRL, 60_000);
    return () => clearInterval(id);
  }, []);

  if (!rl) return null;

  const usedPct = Math.round(((rl.limit - rl.remaining) / rl.limit) * 100);
  const isExhausted = rl.remaining === 0;

  let resetLabel = "";
  if (rl.reset) {
    const resetDate = new Date(rl.reset * 1000);
    const mins = Math.max(0, Math.round((resetDate.getTime() - Date.now()) / 60000));
    resetLabel = mins > 0 ? ` · resets in ${mins}m` : " · resets soon";
  }

  let updatedLabel = "";
  if (rl.updated_at) {
    const updatedDate = new Date(rl.updated_at);
    const secsAgo = Math.round((Date.now() - updatedDate.getTime()) / 1000);
    if (secsAgo < 60) updatedLabel = ` · updated ${secsAgo}s ago`;
    else if (secsAgo < 3600) updatedLabel = ` · updated ${Math.round(secsAgo / 60)}m ago`;
    else updatedLabel = ` · updated ${Math.round(secsAgo / 3600)}h ago`;
  }

  // green < 50%, yellow 50-80%, red > 80% used
  const cls = isExhausted
    ? "rate-limit exhausted"
    : usedPct >= 80
      ? "rate-limit high"
      : usedPct >= 50
        ? "rate-limit medium"
        : "rate-limit low-usage";

  return (
    <span className={cls} title={`GitHub API: ${rl.limit - rl.remaining}/${rl.limit} used${resetLabel}${updatedLabel}`}>
      {isExhausted ? `API limit exceeded${resetLabel}` : `API: ${usedPct}% used`}
    </span>
  );
}

function App() {
  return (
    <div className="app">
      <nav className="top-nav">
        <NavLink to="/" end>
          PRs to Review
        </NavLink>
        <NavLink to="/my-prs">My PRs</NavLink>
        <NavLink to="/stats">PR Statistics</NavLink>
        <NavLink to="/gh-stats">GitHub Statistics</NavLink>
        <RateLimitIndicator />
        <NavLink to="/settings" className="nav-settings">
          Settings
        </NavLink>
      </nav>
      <Outlet />
    </div>
  );
}

export default App;
