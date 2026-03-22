import { useState, useCallback } from "react";
import type { ColumnKey } from "../types";
import { ALL_COLUMNS } from "../types";

const STORAGE_KEY = "pr-dashboard-visible-columns";

function getDefaultVisible(): Set<ColumnKey> {
  return new Set(ALL_COLUMNS.map((c) => c.key));
}

function loadFromStorage(): Set<ColumnKey> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return getDefaultVisible();
    const keys: ColumnKey[] = JSON.parse(raw);
    if (!Array.isArray(keys) || keys.length === 0) return getDefaultVisible();
    return new Set(keys);
  } catch {
    return getDefaultVisible();
  }
}

function saveToStorage(visible: Set<ColumnKey>) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify([...visible]));
}

export function useColumnVisibility() {
  const [visibleColumns, setVisibleColumns] = useState<Set<ColumnKey>>(loadFromStorage);

  const toggleColumn = useCallback((key: ColumnKey) => {
    setVisibleColumns((prev) => {
      const next = new Set(prev);
      if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      saveToStorage(next);
      return next;
    });
  }, []);

  const isVisible = useCallback(
    (key: ColumnKey) => visibleColumns.has(key),
    [visibleColumns],
  );

  return { visibleColumns, toggleColumn, isVisible };
}
