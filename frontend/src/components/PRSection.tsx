import { useMemo, useState } from "react";
import type { PR, Section, ColumnKey } from "../types";
import { ALL_COLUMNS } from "../types";
import { PRRow } from "./PRRow";

type SortDir = "asc" | "desc";

const SORT_ACCESSORS: Partial<Record<ColumnKey, (pr: PR) => string | number>> = {
  pr: (pr) => pr.number,
  repo: (pr) => pr.repo,
  author: (pr) => pr.author.toLowerCase(),
  title: (pr) => pr.title.toLowerCase(),
  created: (pr) => pr.created_at,
  myReview: (pr) => pr.my_reviewed_at ?? "",
  updated: (pr) => pr.updated_at,
};

const DEFAULT_DIR: Partial<Record<ColumnKey, SortDir>> = {
  created: "desc",
  myReview: "desc",
  updated: "desc",
  pr: "desc",
};

interface Props {
  section: Section;
  visibleColumns: Set<ColumnKey>;
}

export function PRSection({ section, visibleColumns }: Props) {
  const columns = ALL_COLUMNS.filter((c) => visibleColumns.has(c.key));
  const [sortKey, setSortKey] = useState<ColumnKey>("created");
  const [sortDir, setSortDir] = useState<SortDir>("desc");

  const handleSort = (key: ColumnKey) => {
    if (!SORT_ACCESSORS[key]) return;
    if (sortKey === key) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortKey(key);
      setSortDir(DEFAULT_DIR[key] ?? "asc");
    }
  };

  const sortedPrs = useMemo(() => {
    const accessor = SORT_ACCESSORS[sortKey];
    if (!accessor) return section.prs;
    const sorted = [...section.prs].sort((a, b) => {
      const va = accessor(a);
      const vb = accessor(b);
      if (va < vb) return -1;
      if (va > vb) return 1;
      return 0;
    });
    return sortDir === "desc" ? sorted.reverse() : sorted;
  }, [section.prs, sortKey, sortDir]);

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
              {columns.map((col) => {
                const sortable = !!SORT_ACCESSORS[col.key];
                const active = sortKey === col.key;
                return (
                  <th
                    key={col.key}
                    className={`${col.className}${sortable ? " sortable" : ""}${active ? " sort-active" : ""}`}
                    title={col.tooltip}
                    onClick={sortable ? () => handleSort(col.key) : undefined}
                  >
                    {col.label}
                    {active && <span className="sort-arrow">{sortDir === "asc" ? " ▲" : " ▼"}</span>}
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody>
            {sortedPrs.map((pr) => (
              <PRRow key={`${pr.repo}#${pr.number}`} pr={pr} visibleColumns={visibleColumns} />
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
