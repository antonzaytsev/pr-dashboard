import type { PR } from "../types";

interface Props {
  pr: PR;
}

function timeAgo(iso: string): string {
  const seconds = (Date.now() - new Date(iso).getTime()) / 1000;
  const hours = Math.floor(seconds / 3600);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

export function PRRow({ pr }: Props) {
  const statusClass =
    pr.status === "changes_requested" ? "badge changes" : "badge review";
  const statusLabel =
    pr.status === "changes_requested" ? "Changes Requested" : "Review Required";

  return (
    <tr>
      <td className="pr-num">
        <a href={pr.url} target="_blank" rel="noopener noreferrer">
          #{pr.number}
        </a>
      </td>
      <td>{pr.author}</td>
      <td>
        <span className={statusClass}>{statusLabel}</span>
      </td>
      <td className="title-cell">{pr.title}</td>
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
      <td className="approved">
        {pr.approved_by.length === 0 ? "—" : pr.approved_by.join(", ")}
      </td>
      <td className="changes-req">
        {pr.changes_requested_by.length === 0
          ? "—"
          : pr.changes_requested_by.join(", ")}
      </td>
      <td className="updated">{timeAgo(pr.updated_at)}</td>
    </tr>
  );
}
