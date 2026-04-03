export interface PR {
  number: number;
  title: string;
  author: string;
  status: "changes_requested" | "review_required" | "approved" | "draft";
  has_conflicts: boolean;
  requested_from: string[];
  is_me_requested: boolean;
  approved_by: string[];
  changes_requested_by: string[];
  commented_by: string[];
  created_at: string;
  updated_at: string;
  my_reviewed_at: string | null;
  needs_re_review: boolean;
  ci_status: "pass" | "in_progress" | "failed" | "unknown";
  unresolved_comments: number;
  total_review_threads: number;
  my_approved: boolean;
  base_branch: string;
  repo: string;
  url: string;
}

export type ColumnKey =
  | "pr"
  | "repo"
  | "author"
  | "target"
  | "status"
  | "title"
  | "created"
  | "myReview"
  | "updated";

export interface ColumnDef {
  key: ColumnKey;
  label: string;
  tooltip: string;
  className: string;
  hideable: boolean;
}

export const ALL_COLUMNS: ColumnDef[] = [
  { key: "pr", label: "PR", tooltip: "Pull request number", className: "col-pr", hideable: false },
  { key: "repo", label: "Repo", tooltip: "Repository name", className: "col-repo", hideable: true },
  { key: "author", label: "Author", tooltip: "Who opened the PR", className: "col-author", hideable: true },
  { key: "target", label: "Target", tooltip: "Target branch", className: "col-target", hideable: true },
  { key: "title", label: "Title", tooltip: "PR title", className: "col-title", hideable: false },
  { key: "status", label: "Status", tooltip: "Approvals, changes requested, comments, conflicts, CI", className: "col-status", hideable: false },
  { key: "created", label: "Created", tooltip: "When the PR was opened", className: "col-created", hideable: true },
  { key: "myReview", label: "My Review", tooltip: "When you last submitted a review", className: "col-my-review", hideable: true },
  { key: "updated", label: "Updated", tooltip: "Last activity on the PR", className: "col-updated", hideable: true },
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
