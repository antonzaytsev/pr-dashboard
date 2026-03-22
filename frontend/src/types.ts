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
  updated_at: string;
  url: string;
}

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
