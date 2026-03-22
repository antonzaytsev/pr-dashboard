import { useState, useRef, useEffect } from "react";
import type { ColumnKey } from "../types";
import { ALL_COLUMNS } from "../types";

interface Props {
  visibleColumns: Set<ColumnKey>;
  onToggle: (key: ColumnKey) => void;
}

export function ColumnToggle({ visibleColumns, onToggle }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  const hideableColumns = ALL_COLUMNS.filter((c) => c.hideable);

  return (
    <div className="col-toggle" ref={ref}>
      <button
        className="col-toggle-btn"
        onClick={() => setOpen((v) => !v)}
        title="Toggle columns"
      >
        Columns
      </button>
      {open && (
        <div className="col-toggle-dropdown">
          {hideableColumns.map((col) => (
            <label key={col.key} className="col-toggle-item">
              <input
                type="checkbox"
                checked={visibleColumns.has(col.key)}
                onChange={() => onToggle(col.key)}
              />
              {col.label}
            </label>
          ))}
        </div>
      )}
    </div>
  );
}
