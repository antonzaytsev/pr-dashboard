import { Link } from "react-router-dom";
import type { PR, ColumnKey } from "../types";

interface Props {
  pr: PR;
  visibleColumns: Set<ColumnKey>;
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

function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString();
}

export function PRRow({ pr, visibleColumns }: Props) {
  const show = (key: ColumnKey) => visibleColumns.has(key);

  const approvalCount = pr.approved_by.length;
  const changesCount = pr.changes_requested_by.length;
  const commentTotal = pr.total_review_threads;
  const commentUnresolved = pr.unresolved_comments;
  const hasConflicts = pr.has_conflicts;
  const ci = pr.ci_status;

  return (
    <tr>
      {show("pr") && (
        <td className="pr-num">
          <Link to={`/pr/${pr.number}?repo=${encodeURIComponent(pr.repo)}`}>
            #{pr.number}
          </Link>
        </td>
      )}
      {show("repo") && (
        <td className="repo">{pr.repo ? pr.repo.split("/")[1] : ""}</td>
      )}
      {show("author") && <td>{pr.author}</td>}
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
