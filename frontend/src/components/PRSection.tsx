import type { Section } from "../types";
import { PRRow } from "./PRRow";

interface Props {
  section: Section;
}

export function PRSection({ section }: Props) {
  return (
    <div className="section">
      <h2 style={{ borderLeftColor: section.color }}>
        {section.title}
        <span className="count">({section.prs.length})</span>
      </h2>

      {section.prs.length === 0 ? (
        <p className="empty">None</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th className="col-pr">PR</th>
              <th className="col-author">Author</th>
              <th className="col-status">Status</th>
              <th className="col-title">Title</th>
              <th className="col-requested">Requested From</th>
              <th className="col-approved">Approved By</th>
              <th className="col-changes">Changes Req.</th>
              <th className="col-updated">Updated</th>
            </tr>
          </thead>
          <tbody>
            {section.prs.map((pr) => (
              <PRRow key={pr.number} pr={pr} />
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
