import { useState } from "react";
import { Link } from "react-router-dom";
import type { PR, ColumnKey } from "../types";
import { timeAgo, formatDateTime } from "../utils/time";

interface Props {
  pr: PR;
  visibleColumns: Set<ColumnKey>;
}

function CopyLinkBtn({ url }: { url: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      className={`copy-link-btn${copied ? " copied" : ""}`}
      title="Copy GitHub URL"
      onClick={() => {
        navigator.clipboard.writeText(url);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }}
    >
      {copied ? "✓" : "🔗"}
    </button>
  );
}

export function PRRow({ pr, visibleColumns }: Props) {
  const show = (key: ColumnKey) => visibleColumns.has(key);

  const approvalCount = pr.approved_by.length;
  const changesCount = pr.changes_requested_by.length;
  const requestedCount = pr.requested_from.length;
  const commentTotal = pr.total_review_threads;
  const commentUnresolved = pr.unresolved_comments;
  const hasConflicts = pr.has_conflicts;
  const ci = pr.ci_status;

  return (
    <tr>
      {show("pr") && (
        <td className="pr-num">
          <Link to={`/pr/${pr.repo}/${pr.number}`}>
            #{pr.number}
          </Link>
        </td>
      )}
      {show("pr") && (
        <td className="pr-actions-cell">
          <a href={pr.url} target="_blank" rel="noopener noreferrer" className="pr-action-btn" title="Open on GitHub">
            <svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>
          </a>
          <CopyLinkBtn url={pr.url} />
          {!pr.my_approved && (
            <a
              href={`http://localhost:4512/review?pr_url=${encodeURIComponent(pr.url)}`}
              target="_blank"
              rel="noopener noreferrer"
              className="pr-action-btn"
              title="Open in review tool"
            >
              ▶
            </a>
          )}
        </td>
      )}
      {show("repo") && (
        <td className="repo">{pr.repo ? pr.repo.split("/")[1] : ""}</td>
      )}
      {show("author") && <td>{pr.author}</td>}
      {show("target") && (
        <td className="target-branch" title={pr.base_branch}>
          {pr.base_branch}
        </td>
      )}
      {show("title") && (
        <td className="title-cell">
          {pr.needs_re_review && (
            <span className="badge re-review" title="New commits since your last review">re-review</span>
          )}
          {pr.title}
        </td>
      )}
      {show("status") && (
        <td className="status-icons">
          <span className={`si-icon ${approvalCount > 0 ? "si-approved-active" : "si-dim"}`} title={approvalCount > 0 ? `Approved by: ${pr.approved_by.join(", ")}` : "No approvals"}>✓</span>
          <span className={`si-val ${approvalCount > 0 ? "si-approved-active" : "si-dim"}`}>{approvalCount >= 2 ? approvalCount : ""}</span>
          <span className={`si-icon ${changesCount > 0 ? "si-changes-active" : "si-dim"}`} title={changesCount > 0 ? `Changes requested by: ${pr.changes_requested_by.join(", ")}` : "No changes requested"}>✗</span>
          <span className={`si-val ${changesCount > 0 ? "si-changes-active" : "si-dim"}`}>{changesCount >= 2 ? changesCount : ""}</span>
          {requestedCount > 0 && (
            <><span className="si-icon si-requested-active" title={`Review requested from: ${pr.requested_from.join(", ")}`}>👁</span><span className="si-val si-requested-active">{requestedCount}</span></>
          )}
          <span className={`si-icon ${commentTotal > 0 ? (commentUnresolved > 0 ? "si-comments-unresolved" : "si-comments-resolved") : "si-dim"}`} title={commentTotal > 0 ? `${commentUnresolved} unresolved / ${commentTotal} threads` : "No review threads"}>💬</span>
          <span className={`si-val ${commentTotal > 0 ? (commentUnresolved > 0 ? "si-comments-unresolved" : "si-comments-resolved") : "si-dim"}`}>{commentTotal > 0 ? `${commentUnresolved}/${commentTotal}` : ""}</span>
          <span className={`si-icon ${hasConflicts ? "si-conflicts-active" : "si-dim"}`} title={hasConflicts ? "Has merge conflicts" : "No conflicts"}>⚡</span>
          <span className={`si-icon ${ci === "pass" ? "si-ci-pass" : ci === "failed" ? "si-ci-fail" : ci === "in_progress" ? "si-ci-running" : "si-dim"}`} title={ci === "pass" ? "CI passed" : ci === "failed" ? "CI failed" : ci === "in_progress" ? "CI running" : "No CI"}>{ci === "pass" ? "●" : ci === "failed" ? "●" : ci === "in_progress" ? "◐" : "●"}</span>
        </td>
      )}
      {show("created") && (
        <td className="created" title={formatDateTime(pr.created_at)}>
          {timeAgo(pr.created_at)}
        </td>
      )}
      {show("myReview") && (
        <td
          className="my-review"
          title={pr.my_reviewed_at ? formatDateTime(pr.my_reviewed_at) : ""}
        >
          {pr.my_reviewed_at ? timeAgo(pr.my_reviewed_at) : "—"}
        </td>
      )}
      {show("updated") && (
        <td className="updated" title={formatDateTime(pr.updated_at)}>
          {timeAgo(pr.updated_at)}
        </td>
      )}
    </tr>
  );
}
