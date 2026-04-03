import { useState, useEffect } from "react";
import { NavLink, Outlet } from "react-router-dom";
import "./App.css";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4511";

interface RateLimit {
  limit: number;
  used: number;
  remaining: number;
  reset: number;
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

  const pct = Math.round((rl.remaining / rl.limit) * 100);
  const isLow = rl.remaining < rl.limit * 0.1;
  const isExhausted = rl.remaining === 0;

  let resetLabel = "";
  if (isExhausted || isLow) {
    const resetDate = new Date(rl.reset * 1000);
    const mins = Math.max(0, Math.round((resetDate.getTime() - Date.now()) / 60000));
    resetLabel = mins > 0 ? ` · resets in ${mins}m` : " · resets soon";
  }

  const cls = isExhausted
    ? "rate-limit exhausted"
    : isLow
      ? "rate-limit low"
      : "rate-limit ok";

  return (
    <span className={cls} title={`GitHub API: ${rl.remaining}/${rl.limit} remaining${resetLabel}`}>
      {isExhausted ? `API limit exceeded${resetLabel}` : `API: ${pct}%`}
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
