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
  repo: string;
  url: string;
}

export type ColumnKey =
  | "pr"
  | "repo"
  | "author"
  | "status"
  | "title"
  | "conflicts"
  | "requested"
  | "approved"
  | "changes"
  | "commented"
  | "created"
  | "ci"
  | "unresolvedComments"
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
  { key: "status", label: "Status", tooltip: "Review decision: approved, changes requested, or pending", className: "col-status", hideable: true },
  { key: "title", label: "Title", tooltip: "PR title", className: "col-title", hideable: false },
  { key: "conflicts", label: "Conflicts", tooltip: "Has merge conflicts with the base branch", className: "col-conflicts", hideable: true },
  { key: "requested", label: "Requested From", tooltip: "Reviewers explicitly requested on the PR", className: "col-requested", hideable: true },
  { key: "approved", label: "Approved By", tooltip: "Reviewers who approved", className: "col-approved", hideable: true },
  { key: "changes", label: "Changes Req.", tooltip: "Reviewers who requested changes", className: "col-changes", hideable: true },
  { key: "commented", label: "Commented", tooltip: "Users who left top-level comments", className: "col-commented", hideable: true },
  { key: "ci", label: "CI", tooltip: "Status of CI checks on the latest commit", className: "col-ci", hideable: true },
  { key: "unresolvedComments", label: "Unresolved", tooltip: "Number of unresolved review threads", className: "col-unresolved", hideable: true },
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
