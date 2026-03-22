export interface PR {
  number: number;
  title: string;
  author: string;
  status: "changes_requested" | "review_required" | "approved" | "draft";
  requested_from: string[];
  is_me_requested: boolean;
  approved_by: string[];
  changes_requested_by: string[];
  commented_by: string[];
  created_at: string;
  updated_at: string;
  my_reviewed_at: string | null;
  needs_re_review: boolean;
  url: string;
}

export type ColumnKey =
  | "pr"
  | "author"
  | "status"
  | "title"
  | "requested"
  | "approved"
  | "changes"
  | "commented"
  | "created"
  | "myReview"
  | "updated";

export interface ColumnDef {
  key: ColumnKey;
  label: string;
  className: string;
  hideable: boolean;
}

export const ALL_COLUMNS: ColumnDef[] = [
  { key: "pr", label: "PR", className: "col-pr", hideable: false },
  { key: "author", label: "Author", className: "col-author", hideable: true },
  { key: "status", label: "Status", className: "col-status", hideable: true },
  { key: "title", label: "Title", className: "col-title", hideable: false },
  { key: "requested", label: "Requested From", className: "col-requested", hideable: true },
  { key: "approved", label: "Approved By", className: "col-approved", hideable: true },
  { key: "changes", label: "Changes Req.", className: "col-changes", hideable: true },
  { key: "commented", label: "Commented", className: "col-commented", hideable: true },
  { key: "created", label: "Created", className: "col-created", hideable: true },
  { key: "myReview", label: "My Review", className: "col-my-review", hideable: true },
  { key: "updated", label: "Updated", className: "col-updated", hideable: true },
];

export interface Section {
  id: number;
  title: string;
  color: string;
  prs: PR[];
}

export interface PRData {
  sections: Section[];
  total: number;
  updated_at: string | null;
  days_window: number;
}
