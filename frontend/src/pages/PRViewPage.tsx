import { useEffect, useState } from "react";
import { useParams, useSearchParams, Link } from "react-router-dom";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeRaw from "rehype-raw";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4511";

interface CICheck {
  name: string;
  status: string;
  conclusion: string | null;
  url: string | null;
}

interface ThreadComment {
  author: string;
  body: string;
  created_at: string;
  url: string;
}

interface UnresolvedThread {
  path: string;
  line: number | null;
  comments: ThreadComment[];
}

interface PRDetail {
  number: number;
  title: string;
  body: string;
  author: string;
  status: "changes_requested" | "review_required" | "approved" | "draft";
  has_conflicts: boolean;
  requested_from: string[];
  approved_by: string[];
  changes_requested_by: string[];
  commented_by: string[];
  created_at: string;
  updated_at: string;
  ci_status: "pass" | "in_progress" | "failed" | "unknown";
  ci_checks: CICheck[];
  unresolved_comments: number;
  unresolved_threads: UnresolvedThread[];
  url: string;
  additions: number;
  deletions: number;
  changed_files: number;
  base_branch: string;
  head_branch: string;
}

function timeAgo(iso: string): string {
  const seconds = (Date.now() - new Date(iso).getTime()) / 1000;
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(seconds / 3600);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

function statusLabel(status: PRDetail["status"]): string {
  switch (status) {
    case "draft": return "Draft";
    case "approved": return "Approved";
    case "changes_requested": return "Changes Requested";
    default: return "Review Required";
  }
}

function statusClass(status: PRDetail["status"]): string {
  switch (status) {
    case "draft": return "badge draft";
    case "approved": return "badge approved";
    case "changes_requested": return "badge changes";
    default: return "badge review";
  }
}

export function PRViewPage() {
  const { number } = useParams<{ number: string }>();
  const [searchParams] = useSearchParams();
  const repo = searchParams.get("repo") || "";
  const [pr, setPr] = useState<PRDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function fetchPR() {
      try {
        const repoParam = repo ? `?repo=${encodeURIComponent(repo)}` : "";
        const res = await fetch(`${API_URL}/api/pr/${number}${repoParam}`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        setPr(await res.json());
        setError(null);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Failed to fetch");
      } finally {
        setLoading(false);
      }
    }
    fetchPR();
  }, [number, repo]);

  if (loading) return <div className="loading">Loading...</div>;
  if (error) return <div className="error">Error: {error}</div>;
  if (!pr) return <div className="error">PR not found</div>;

  const ciGroup = (check: CICheck): "failed" | "running" | "passed" | "other" => {
    if (check.conclusion === "failure") return "failed";
    if (check.conclusion === "success") return "passed";
    if (check.status === "in_progress" || check.status === "queued" || (!check.conclusion && check.status !== "completed")) return "running";
    return "other";
  };
  const groupOrder = { failed: 0, running: 1, passed: 2, other: 3 };
  const sortedChecks = [...pr.ci_checks].sort((a, b) => groupOrder[ciGroup(a)] - groupOrder[ciGroup(b)]);
  const ciFailed = pr.ci_checks.filter((c) => ciGroup(c) === "failed").length;
  const ciRunning = pr.ci_checks.filter((c) => ciGroup(c) === "running").length;
  const ciPassed = pr.ci_checks.filter((c) => ciGroup(c) === "passed").length;
  const ciOther = pr.ci_checks.filter((c) => ciGroup(c) === "other").length;

  return (
    <div className="pr-view">
      <div className="pr-view-back">
        <Link to="/">&larr; Back to list</Link>
      </div>

      <div className="pr-view-header">
        <div className="pr-view-title-row">
          <h1>
            {pr.title} <span className="pr-view-number">#{pr.number}</span>
          </h1>
        </div>
        <div className="pr-view-meta">
          <span className={statusClass(pr.status)}>{statusLabel(pr.status)}</span>
          <span className="pr-view-author">
            <strong>{pr.author}</strong> wants to merge into{" "}
            <code>{pr.base_branch}</code> from <code>{pr.head_branch}</code>
          </span>
        </div>
        <div className="pr-view-gh-link">
          <a href={pr.url} target="_blank" rel="noopener noreferrer">
            View on GitHub &rarr;
          </a>
        </div>
      </div>

      <div className="pr-view-grid">
        <div className="pr-view-main">
          {pr.body ? (
            <div className="pr-view-card">
              <h3>Description</h3>
              <div className="pr-view-body markdown-body">
                <ReactMarkdown remarkPlugins={[remarkGfm]} rehypePlugins={[rehypeRaw]}>
                  {pr.body}
                </ReactMarkdown>
              </div>
            </div>
          ) : (
            <div className="pr-view-card">
              <h3>Description</h3>
              <p className="pr-view-empty">No description provided.</p>
            </div>
          )}

          {pr.unresolved_threads.length > 0 && (
            <div className="pr-view-card">
              <h3>
                Unresolved Comments{" "}
                <span className="count">({pr.unresolved_threads.length})</span>
              </h3>
              <div className="pr-view-threads">
                {pr.unresolved_threads.map((thread, i) => (
                  <div key={i} className="pr-view-thread">
                    <div className="pr-view-thread-file">
                      {thread.path}
                      {thread.line != null && `:${thread.line}`}
                    </div>
                    {thread.comments.map((comment, j) => (
                      <div key={j} className="pr-view-comment">
                        <div className="pr-view-comment-header">
                          <strong>{comment.author}</strong>
                          <span className="pr-view-comment-time">
                            {timeAgo(comment.created_at)}
                          </span>
                          {comment.url && (
                            <a
                              href={comment.url}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="pr-view-comment-link"
                            >
                              link
                            </a>
                          )}
                        </div>
                        <div className="pr-view-comment-body markdown-body">
                          <ReactMarkdown remarkPlugins={[remarkGfm]} rehypePlugins={[rehypeRaw]}>
                            {comment.body}
                          </ReactMarkdown>
                        </div>
                      </div>
                    ))}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        <div className="pr-view-sidebar">
          <div className="pr-view-card">
            <h3>Reviewers</h3>
            <div className="pr-view-reviewer-section">
              {pr.approved_by.length > 0 && (
                <div className="pr-view-reviewer-group">
                  <span className="pr-view-reviewer-label approved">Approved</span>
                  <span>{pr.approved_by.join(", ")}</span>
                </div>
              )}
              {pr.changes_requested_by.length > 0 && (
                <div className="pr-view-reviewer-group">
                  <span className="pr-view-reviewer-label changes-req">Changes requested</span>
                  <span>{pr.changes_requested_by.join(", ")}</span>
                </div>
              )}
              {pr.requested_from.length > 0 && (
                <div className="pr-view-reviewer-group">
                  <span className="pr-view-reviewer-label requested">Pending</span>
                  <span>{pr.requested_from.join(", ")}</span>
                </div>
              )}
              {pr.approved_by.length === 0 &&
                pr.changes_requested_by.length === 0 &&
                pr.requested_from.length === 0 && (
                  <span className="pr-view-empty">No reviewers</span>
                )}
            </div>
          </div>

          <div className="pr-view-card">
            <h3>Stats</h3>
            <div className="pr-view-stats">
              <div className="pr-view-stat">
                <span className="pr-view-stat-label">Files changed</span>
                <span className="pr-view-stat-value">{pr.changed_files}</span>
              </div>
              <div className="pr-view-stat">
                <span className="pr-view-stat-label">Additions</span>
                <span className="pr-view-stat-value pr-view-additions">+{pr.additions}</span>
              </div>
              <div className="pr-view-stat">
                <span className="pr-view-stat-label">Deletions</span>
                <span className="pr-view-stat-value pr-view-deletions">-{pr.deletions}</span>
              </div>
              <div className="pr-view-stat">
                <span className="pr-view-stat-label">Conflicts</span>
                <span className="pr-view-stat-value">
                  {pr.has_conflicts ? (
                    <span className="badge conflicts">Yes</span>
                  ) : (
                    "None"
                  )}
                </span>
              </div>
              <div className="pr-view-stat">
                <span className="pr-view-stat-label">Unresolved</span>
                <span className="pr-view-stat-value">
                  {pr.unresolved_comments > 0 ? pr.unresolved_comments : "0"}
                </span>
              </div>
              <div className="pr-view-stat">
                <span className="pr-view-stat-label">Created</span>
                <span className="pr-view-stat-value">{timeAgo(pr.created_at)}</span>
              </div>
              <div className="pr-view-stat">
                <span className="pr-view-stat-label">Updated</span>
                <span className="pr-view-stat-value">{timeAgo(pr.updated_at)}</span>
              </div>
            </div>
          </div>

          <div className="pr-view-card">
            <h3>
              CI Checks{" "}
              <span className="count">
                ({[
                  ciFailed > 0 && `${ciFailed} failed`,
                  ciRunning > 0 && `${ciRunning} in progress`,
                  ciPassed > 0 && `${ciPassed} passed`,
                  ciOther > 0 && `${ciOther} skipped`,
                ].filter(Boolean).join(", ")})
              </span>
            </h3>
            {pr.ci_checks.length === 0 ? (
              <span className="pr-view-empty">No CI checks</span>
            ) : (
              <div className="pr-view-checks">
                {sortedChecks.map((check, i) => (
                  <div key={i} className="pr-view-check">
                    <span
                      className={`pr-view-check-icon ${
                        { failed: "check-fail", running: "check-running", passed: "check-pass", other: "check-pending" }[ciGroup(check)]
                      }`}
                    >
                      {{ failed: "x", running: "~", passed: "+", other: "-" }[ciGroup(check)]}
                    </span>
                    {check.url ? (
                      <a
                        href={check.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="pr-view-check-name"
                      >
                        {check.name}
                      </a>
                    ) : (
                      <span className="pr-view-check-name">{check.name}</span>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
