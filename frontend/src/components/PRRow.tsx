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

  const statusClass =
    pr.status === "draft"
      ? "badge draft"
      : pr.status === "approved"
        ? "badge approved"
        : pr.status === "changes_requested"
          ? "badge changes"
          : "badge review";
  const statusLabel =
    pr.status === "draft"
      ? "Draft"
      : pr.status === "approved"
        ? "Approved"
        : pr.status === "changes_requested"
          ? "Changes Requested"
          : "Review Required";

  return (
    <tr>
      {show("pr") && (
        <td className="pr-num">
          <a href={pr.url} target="_blank" rel="noopener noreferrer">
            #{pr.number}
          </a>
        </td>
      )}
      {show("author") && <td>{pr.author}</td>}
      {show("status") && (
        <td>
          <span className={statusClass}>{statusLabel}</span>
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
      {show("conflicts") && (
        <td>
          {pr.has_conflicts && (
            <span className="badge conflicts">Yes</span>
          )}
        </td>
      )}
      {show("requested") && (
        <td className="requested">
          {pr.requested_from.length === 0
            ? "—"
            : pr.requested_from.map((r, i) => (
                <span key={r}>
                  {i > 0 && ", "}
                  {pr.is_me_requested &&
                  (r === "antonzaytsev" || r === "zaytsev-anton") ? (
                    <strong>{r}</strong>
                  ) : (
                    r
                  )}
                </span>
              ))}
        </td>
      )}
      {show("approved") && (
        <td className="approved">
          {pr.approved_by.length === 0 ? "—" : pr.approved_by.join(", ")}
        </td>
      )}
      {show("changes") && (
        <td className="changes-req">
          {pr.changes_requested_by.length === 0
            ? "—"
            : pr.changes_requested_by.join(", ")}
        </td>
      )}
      {show("commented") && (
        <td className="commented">
          {pr.commented_by.length === 0
            ? "—"
            : pr.commented_by.join(", ")}
        </td>
      )}
      {show("ci") && (
        <td>
          <span
            className={`badge ci-${pr.ci_status}`}
            title={
              pr.ci_status === "pass"
                ? "CI passed"
                : pr.ci_status === "in_progress"
                  ? "CI running"
                  : pr.ci_status === "failed"
                    ? "CI failed"
                    : "No CI status"
            }
          >
            {pr.ci_status === "pass"
              ? "Pass"
              : pr.ci_status === "in_progress"
                ? "Running"
                : pr.ci_status === "failed"
                  ? "Failed"
                  : "—"}
          </span>
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
