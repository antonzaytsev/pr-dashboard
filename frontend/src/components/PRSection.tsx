import type { Section, ColumnKey } from "../types";
import { ALL_COLUMNS } from "../types";
import { PRRow } from "./PRRow";

interface Props {
  section: Section;
  visibleColumns: Set<ColumnKey>;
}

export function PRSection({ section, visibleColumns }: Props) {
  const columns = ALL_COLUMNS.filter((c) => visibleColumns.has(c.key));

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
              {columns.map((col) => (
                <th key={col.key} className={col.className} title={col.tooltip}>
                  {col.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {section.prs.map((pr) => (
              <PRRow key={`${pr.repo}#${pr.number}`} pr={pr} visibleColumns={visibleColumns} />
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
