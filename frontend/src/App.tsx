import { NavLink, Outlet } from "react-router-dom";
import "./App.css";

function App() {
  return (
    <div className="app">
      <nav className="top-nav">
        <NavLink to="/" end>
          PRs to Review
        </NavLink>
        <NavLink to="/my-prs">My PRs</NavLink>
        <NavLink to="/settings" className="nav-settings">
          Settings
        </NavLink>
      </nav>
      <Outlet />
    </div>
  );
}

export default App;
