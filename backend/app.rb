# frozen_string_literal: true

require "sinatra"
require "json"
require "time"
require "net/http"
require "uri"

AVAILABLE_REPOS = {
  "sdtechdev/spree-jiffyshirts" => "spree-jiffyshirts",
  "sdtechdev/assignment" => "assignment"
}.freeze
$enabled_repos = AVAILABLE_REPOS.keys.dup
MY_ALIASES = %w[zaytsev-anton antonzaytsev].freeze
GH_TOKEN = ENV.fetch("GITHUB_TOKEN")
POLL_INTERVAL = Integer(ENV.fetch("POLL_INTERVAL", "600")) # seconds
STATS_POLL_INTERVAL = Integer(ENV.fetch("STATS_POLL_INTERVAL", "1800")) # seconds — stats change slowly, poll less often
$days_window = 3
$stats_window = 7

set :bind, "0.0.0.0"
set :port, Integer(ENV.fetch("PORT", "4511"))

$pr_cache = { sections: [], updated_at: nil, total: 0 }
$my_pr_cache = { sections: [], updated_at: nil, total: 0 }
$stats_cache = { updated_at: nil }
$cache_mutex = Mutex.new
$rate_limit_reset = nil # Time when rate limit resets; skip GH calls until then
$rate_limit_info = { limit: nil, used: nil, remaining: nil, reset: nil, updated_at: nil } # Cached from GraphQL response headers + inline rateLimit field
# Rolling history of rate limit snapshots for the GitHub Statistics chart.
# Each entry: { remaining:, limit:, used:, reset:, recorded_at: ISO8601 }
# Capped at 500 entries to bound memory; one entry per gh_request call.
$rate_limit_history = []
$rate_limit_history_mutex = Mutex.new
RATE_LIMIT_HISTORY_MAX = 500

# --- GitHub API helpers ---

DETAIL_BATCH_SIZE = 15
MAX_PARALLEL = 4

# Cache of previously fetched PR details keyed by "repo/number" => { updated_at:, details: }
# Used to skip re-fetching details for PRs whose updatedAt hasn't changed since last poll.
$detail_cache = {}
$detail_cache_mutex = Mutex.new

GH_URI = URI("https://api.github.com/graphql").freeze

DETAIL_FIELDS = <<~GQL.freeze
  reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { name } } } }
  reviews(last: 100) { nodes { author { login } state submittedAt } }
  commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
  reviewThreads(first: 50) { nodes { isResolved comments(first: 30) { nodes { author { login } createdAt } } } }
  comments(first: 100) { nodes { author { login } } }
GQL

def with_gh_connection(&block)
  Net::HTTP.start(GH_URI.hostname, GH_URI.port, use_ssl: true, read_timeout: 30, open_timeout: 10, &block)
end

def rate_limited?
  $rate_limit_reset && Time.now < $rate_limit_reset
end

def gh_request(http, query)
  req = Net::HTTP::Post.new(GH_URI)
  req["Authorization"] = "Bearer #{GH_TOKEN}"
  req["Content-Type"] = "application/json"
  req.body = { query: query }.to_json
  res = http.request(req)
  remaining = res["x-ratelimit-remaining"]
  reset = res["x-ratelimit-reset"]
  if remaining && remaining.to_i <= 0 && reset
    $rate_limit_reset = Time.at(reset.to_i)
    $stderr.puts "[#{Time.now}] Rate limit exhausted, pausing until #{$rate_limit_reset}"
  elsif remaining && remaining.to_i > 0
    $rate_limit_reset = nil
  end
  # Update cached rate limit info from response headers
  $rate_limit_info[:remaining] = remaining.to_i if remaining
  $rate_limit_info[:reset] = reset.to_i if reset
  limit_header = res["x-ratelimit-limit"]
  $rate_limit_info[:limit] = limit_header.to_i if limit_header
  parsed = JSON.parse(res.body)
  # Also read inline rateLimit field if present (more accurate cost tracking)
  if (rl = parsed.dig("data", "rateLimit"))
    $rate_limit_info[:remaining] = rl["remaining"] if rl["remaining"]
    $rate_limit_info[:reset] = Time.parse(rl["resetAt"]).to_i if rl["resetAt"]
    $rate_limit_info[:used] = rl["cost"] if rl["cost"]
    $rate_limit_info[:limit] = rl["limit"] if rl["limit"]
  end
  $rate_limit_info[:updated_at] = Time.now.utc.iso8601
  # Append snapshot to history for the GitHub Statistics chart
  if $rate_limit_info[:remaining] && $rate_limit_info[:limit]
    snapshot = {
      remaining: $rate_limit_info[:remaining],
      limit: $rate_limit_info[:limit],
      used: $rate_limit_info[:limit] - $rate_limit_info[:remaining],
      reset: $rate_limit_info[:reset],
      recorded_at: Time.now.utc.iso8601
    }
    $rate_limit_history_mutex.synchronize do
      $rate_limit_history << snapshot
      $rate_limit_history.shift if $rate_limit_history.size > RATE_LIMIT_HISTORY_MAX
    end
  end
  parsed
end

def fetch_prs
  if rate_limited?
    $stderr.puts "[#{Time.now}] Skipping fetch_prs — rate limited until #{$rate_limit_reset}"
    return nil
  end
  cutoff = Time.now - ($days_window * 86400)
  all_prs = []

  $enabled_repos.each do |repo_full|
    owner, name = repo_full.split("/")

    # Pass 1: lightweight list (sequential pagination, persistent connection)
    repo_prs = []
    with_gh_connection do |http|
      cursor = nil
      loop do
        after_clause = cursor ? %Q(, after: "#{cursor}") : ""
        query = <<~GQL
          query {
            rateLimit { cost remaining resetAt limit }
            repository(owner: "#{owner}", name: "#{name}") {
              pullRequests(states: OPEN, first: 100, orderBy: {field: UPDATED_AT, direction: DESC}#{after_clause}) {
                pageInfo { hasNextPage endCursor }
                nodes {
                  number title isDraft mergeable createdAt updatedAt baseRefName
                  author { login }
                  reviewDecision
                }
              }
            }
          }
        GQL

        data = gh_request(http, query)
        nodes = data.dig("data", "repository", "pullRequests", "nodes") || []
        page_info = data.dig("data", "repository", "pullRequests", "pageInfo")
        # Tag each PR with its repo
        nodes.each { |n| n["_repo"] = repo_full }
        repo_prs.concat(nodes)

        last_updated = nodes.last && Time.parse(nodes.last["updatedAt"])
        break if last_updated && last_updated < cutoff
        break unless page_info&.dig("hasNextPage")
        cursor = page_info["endCursor"]
      end
    end

    relevant = repo_prs.select { |pr| Time.parse(pr["updatedAt"]) > cutoff }
    $stderr.puts "[#{Time.now}] Pass 1 done (#{repo_full}): #{repo_prs.size} fetched, #{relevant.size} within window"

    # Pass 2: fetch review/comment details in parallel batches.
    # Skip re-fetching details for PRs whose updatedAt hasn't changed since last poll
    # — their review/comment data can't have changed either.
    needs_fetch = []
    cached_details = {}
    relevant.each do |pr|
      cache_key = "#{repo_full}/#{pr["number"]}"
      cached = $detail_cache_mutex.synchronize { $detail_cache[cache_key] }
      if cached && cached[:updated_at] == pr["updatedAt"]
        cached_details[pr["number"]] = cached[:details]
      else
        needs_fetch << pr["number"]
      end
    end
    $stderr.puts "[#{Time.now}] Pass 2 (#{repo_full}): #{cached_details.size} cached, #{needs_fetch.size} need fetch"

    batches = needs_fetch.each_slice(DETAIL_BATCH_SIZE).to_a
    details = {}
    mutex = Mutex.new

    batches.each_slice(MAX_PARALLEL) do |chunk|
      threads = chunk.map do |batch|
        Thread.new do
          with_gh_connection do |http|
            aliases = batch.map { |n|
              "pr_#{n}: pullRequest(number: #{n}) {\n#{DETAIL_FIELDS}}"
            }.join("\n")
            query = %Q(query { rateLimit { cost remaining resetAt limit }\nrepository(owner: "#{owner}", name: "#{name}") {\n#{aliases}\n} })
            data = gh_request(http, query)
            repo = data.dig("data", "repository") || {}
            batch.each do |n|
              d = repo["pr_#{n}"]
              mutex.synchronize { details[n] = d } if d
            end
          end
        rescue StandardError => e
          $stderr.puts "[#{Time.now}] Detail batch error (#{batch.first}..#{batch.last}): #{e.message}"
        end
      end
      threads.each(&:join)
    end

    # Merge fetched details into cache for next cycle
    details.each do |n, d|
      pr = relevant.find { |p| p["number"] == n }
      cache_key = "#{repo_full}/#{n}"
      $detail_cache_mutex.synchronize { $detail_cache[cache_key] = { updated_at: pr["updatedAt"], details: d } }
    end

    all_details = cached_details.merge(details)
    relevant.each { |pr| pr.merge!(all_details[pr["number"]] || {}) }
    $stderr.puts "[#{Time.now}] Pass 2 done (#{repo_full}): #{details.size} fetched, #{cached_details.size} from cache"
    all_prs.concat(relevant)
  end

  all_prs
end

STATS_DETAIL_FIELDS = <<~GQL.freeze
  reviews(last: 100) { nodes { author { login } state submittedAt } }
  reviewThreads(first: 50) { nodes { comments(first: 30) { nodes { author { login } createdAt } } } }
GQL

def fetch_stats_prs
  if rate_limited?
    $stderr.puts "[#{Time.now}] Skipping fetch_stats_prs — rate limited until #{$rate_limit_reset}"
    return nil
  end
  cutoff = Time.now - ($stats_window * 86400)
  all_prs = []

  $enabled_repos.each do |repo_full|
    owner, name = repo_full.split("/")

    repo_prs = []
    with_gh_connection do |http|
      cursor = nil
      loop do
        after_clause = cursor ? %Q(, after: "#{cursor}") : ""
        query = <<~GQL
          query {
            rateLimit { cost remaining resetAt limit }
            repository(owner: "#{owner}", name: "#{name}") {
              pullRequests(states: [OPEN, MERGED], first: 100, orderBy: {field: UPDATED_AT, direction: DESC}#{after_clause}) {
                pageInfo { hasNextPage endCursor }
                nodes {
                  number title isDraft createdAt updatedAt mergedAt state
                  author { login }
                  additions deletions changedFiles
                }
              }
            }
          }
        GQL

        data = gh_request(http, query)
        nodes = data.dig("data", "repository", "pullRequests", "nodes") || []
        page_info = data.dig("data", "repository", "pullRequests", "pageInfo")
        nodes.each { |n| n["_repo"] = repo_full }
        repo_prs.concat(nodes)

        last_updated = nodes.last && Time.parse(nodes.last["updatedAt"])
        break if last_updated && last_updated < cutoff
        break unless page_info&.dig("hasNextPage")
        cursor = page_info["endCursor"]
      end
    end

    relevant = repo_prs.select { |pr| Time.parse(pr["updatedAt"]) > cutoff }
    $stderr.puts "[#{Time.now}] Stats pass 1 done (#{repo_full}): #{repo_prs.size} fetched, #{relevant.size} within window"

    # Incremental: skip detail fetch for PRs whose updatedAt is unchanged since last poll
    needs_fetch = []
    cached_details = {}
    relevant.each do |pr|
      cache_key = "stats/#{repo_full}/#{pr["number"]}"
      cached = $detail_cache_mutex.synchronize { $detail_cache[cache_key] }
      if cached && cached[:updated_at] == pr["updatedAt"]
        cached_details[pr["number"]] = cached[:details]
      else
        needs_fetch << pr["number"]
      end
    end
    $stderr.puts "[#{Time.now}] Stats pass 2 (#{repo_full}): #{cached_details.size} cached, #{needs_fetch.size} need fetch"

    batches = needs_fetch.each_slice(DETAIL_BATCH_SIZE).to_a
    details = {}
    mutex = Mutex.new

    batches.each_slice(MAX_PARALLEL) do |chunk|
      threads = chunk.map do |batch|
        Thread.new do
          with_gh_connection do |http|
            aliases = batch.map { |n|
              "pr_#{n}: pullRequest(number: #{n}) {\n#{STATS_DETAIL_FIELDS}}"
            }.join("\n")
            query = %Q(query { rateLimit { cost remaining resetAt limit }\nrepository(owner: "#{owner}", name: "#{name}") {\n#{aliases}\n} })
            data = gh_request(http, query)
            repo = data.dig("data", "repository") || {}
            batch.each do |n|
              d = repo["pr_#{n}"]
              mutex.synchronize { details[n] = d } if d
            end
          end
        rescue StandardError => e
          $stderr.puts "[#{Time.now}] Stats detail batch error: #{e.message}"
        end
      end
      threads.each(&:join)
    end

    # Merge fetched details into cache for next cycle
    details.each do |n, d|
      pr = relevant.find { |p| p["number"] == n }
      cache_key = "stats/#{repo_full}/#{n}"
      $detail_cache_mutex.synchronize { $detail_cache[cache_key] = { updated_at: pr["updatedAt"], details: d } }
    end

    all_details = cached_details.merge(details)
    relevant.each { |pr| pr.merge!(all_details[pr["number"]] || {}) }
    $stderr.puts "[#{Time.now}] Stats pass 2 done (#{repo_full}): #{details.size} fetched, #{cached_details.size} from cache"
    all_prs.concat(relevant)
  end

  all_prs
end

def process_stats(raw_prs)
  cutoff = Time.now - ($stats_window * 86400)

  my_reviewed = 0
  my_approved = 0
  my_changes_requested = 0
  my_review_comments = 0
  my_opened = 0
  my_merged = 0
  times_to_first_review = []
  my_times_to_first_review = []
  times_to_merge = []
  total_opened = 0
  total_merged = 0
  pr_sizes = []
  teammate_stats = Hash.new { |h, k| h[k] = { reviewed: 0, approved: 0, changes_requested: 0, comments: 0 } }

  raw_prs.each do |pr|
    author = pr.dig("author", "login")
    created = Time.parse(pr["createdAt"])
    is_mine = MY_ALIASES.include?(author)

    # Count PRs opened in window
    if created > cutoff
      total_opened += 1
      my_opened += 1 if is_mine
      pr_sizes << (pr["additions"] || 0) + (pr["deletions"] || 0)
    end

    # Count merges in window
    if pr["mergedAt"]
      merged_at = Time.parse(pr["mergedAt"])
      if merged_at > cutoff
        total_merged += 1
        my_merged += 1 if is_mine
        times_to_merge << (merged_at - created) / 3600.0
      end
    end

    # Process reviews
    reviews = pr.dig("reviews", "nodes") || []
    reviewers_seen = {}

    reviews.sort_by { |r| r["submittedAt"] || "" }.each do |review|
      reviewer = review.dig("author", "login")
      next unless reviewer
      submitted = review["submittedAt"]
      next unless submitted

      submitted_time = Time.parse(submitted)
      next unless submitted_time > cutoff

      # Track first review per reviewer per PR
      unless reviewers_seen[reviewer]
        reviewers_seen[reviewer] = true

        if MY_ALIASES.include?(reviewer)
          my_reviewed += 1
          my_approved += 1 if review["state"] == "APPROVED"
          my_changes_requested += 1 if review["state"] == "CHANGES_REQUESTED"
        else
          teammate_stats[reviewer][:reviewed] += 1
          teammate_stats[reviewer][:approved] += 1 if review["state"] == "APPROVED"
          teammate_stats[reviewer][:changes_requested] += 1 if review["state"] == "CHANGES_REQUESTED"
        end
      end
    end

    # Time to first review (any reviewer)
    first_review = reviews.filter_map { |r| r["submittedAt"] }.min
    if first_review
      first_review_time = Time.parse(first_review)
      hours = (first_review_time - created) / 3600.0
      if hours >= 0
        times_to_first_review << hours
        my_times_to_first_review << hours if is_mine
      end
    end

    # Count review comments per user from threads
    (pr.dig("reviewThreads", "nodes") || []).each do |thread|
      (thread.dig("comments", "nodes") || []).each do |comment|
        commenter = comment.dig("author", "login")
        next unless commenter
        comment_time = comment["createdAt"] && Time.parse(comment["createdAt"])
        next unless comment_time && comment_time > cutoff

        if MY_ALIASES.include?(commenter)
          my_review_comments += 1
        else
          teammate_stats[commenter][:comments] += 1
        end
      end
    end
  end

  avg = ->(arr) { arr.empty? ? nil : (arr.sum / arr.size).round(1) }

  me_entry = { user: MY_ALIASES.first, reviewed: my_reviewed, approved: my_approved,
               changes_requested: my_changes_requested, comments: my_review_comments, is_me: true }

  teammate_list = teammate_stats.map { |user, s|
    { user: user, reviewed: s[:reviewed], approved: s[:approved],
      changes_requested: s[:changes_requested], comments: s[:comments], is_me: false }
  }
  teammate_list.push(me_entry)

  {
    my_activity: {
      prs_reviewed: my_reviewed,
      prs_approved: my_approved,
      changes_requested: my_changes_requested,
      review_comments: my_review_comments
    },
    my_prs: {
      opened: my_opened,
      merged: my_merged,
      avg_time_to_first_review_hours: avg.call(my_times_to_first_review),
      avg_time_to_merge_hours: avg.call(times_to_merge.select { |t| t > 0 })
    },
    teammate_activity: teammate_list,
    overview: {
      total_prs_opened: total_opened,
      total_prs_merged: total_merged,
      avg_time_to_first_review_hours: avg.call(times_to_first_review),
      avg_pr_size: avg.call(pr_sizes) || 0
    },
    updated_at: Time.now.utc.iso8601,
    window_days: $stats_window
  }
end

def extract_pr_details(pr)
  requested = (pr.dig("reviewRequests", "nodes") || []).map { |r|
    r.dig("requestedReviewer", "login") || r.dig("requestedReviewer", "name")
  }.compact

  requested_from_me = MY_ALIASES.any? { |a| requested.include?(a) }

  latest_reviews = {}
  (pr.dig("reviews", "nodes") || []).each do |r|
    login = r.dig("author", "login")
    next unless login
    next if r["state"] == "COMMENTED" || r["state"] == "PENDING" || r["state"] == "DISMISSED"
    ts = r["submittedAt"]
    prev = latest_reviews[login]
    latest_reviews[login] = r if prev.nil? || (ts && prev["submittedAt"] && ts > prev["submittedAt"])
  end

  commented_by = (pr.dig("comments", "nodes") || []).filter_map { |c| c.dig("author", "login") }.uniq.sort
  reviewed = (pr.dig("reviews", "nodes") || []).any? { |r| MY_ALIASES.include?(r.dig("author", "login")) }

  my_reviewed_at = (pr.dig("reviews", "nodes") || [])
    .select { |r| MY_ALIASES.include?(r.dig("author", "login")) && r["submittedAt"] }
    .map { |r| r["submittedAt"] }
    .max

  my_approved = (pr.dig("reviews", "nodes") || [])
    .any? { |r| MY_ALIASES.include?(r.dig("author", "login")) && r["state"] == "APPROVED" }

  # Detect whether the PR author has responded (comment or new code) since my last review.
  # This drives the "re-review" flag: if the author acted after I reviewed, the PR moves
  # from "Already reviewed by me" back to "Need my review".
  # We intentionally do NOT gate on !my_approved — even if I approved, new code or a reply
  # from the author means I should look again. Without this, approved PRs where the author
  # pushes follow-up commits silently stay hidden.
  author_responded = false
  if reviewed && my_reviewed_at
    pr_author = pr.dig("author", "login")

    # Check 1: author replied in a review thread I participated in.
    (pr.dig("reviewThreads", "nodes") || []).each do |thread|
      comments = thread.dig("comments", "nodes") || []
      next unless comments.any? { |c| MY_ALIASES.include?(c.dig("author", "login")) }

      if comments.any? { |c| c.dig("author", "login") == pr_author && c["createdAt"] && c["createdAt"] > my_reviewed_at }
        author_responded = true
        break
      end
    end

    # Check 2: author pushed new commits after my last review.
    # The GraphQL query fetches commits(last: 1), so committedDate is the latest commit.
    # If that commit is newer than my review, the author changed code and I should re-review.
    unless author_responded
      last_commit_date = pr.dig("commits", "nodes", 0, "commit", "committedDate")
      author_responded = true if last_commit_date && last_commit_date > my_reviewed_at
    end
  end

  needs_re_review = reviewed && author_responded

  review_threads = pr.dig("reviewThreads", "nodes") || []
  unresolved_comments = review_threads.count { |t| !t["isResolved"] }
  total_review_threads = review_threads.size

  { requested: requested, requested_from_me: requested_from_me,
    latest_reviews: latest_reviews, commented_by: commented_by, reviewed: reviewed,
    my_reviewed_at: my_reviewed_at, my_approved: my_approved, needs_re_review: needs_re_review,
    unresolved_comments: unresolved_comments, total_review_threads: total_review_threads }
end

def build_pr_hash(pr, details)
  approved_by = details[:latest_reviews].select { |_, r| r["state"] == "APPROVED" }.keys.sort
  changes_requested_by = details[:latest_reviews].select { |_, r| r["state"] == "CHANGES_REQUESTED" }.keys.sort

  status = if pr["isDraft"]
             "draft"
           elsif pr["reviewDecision"] == "APPROVED"
             "approved"
           elsif pr["reviewDecision"] == "CHANGES_REQUESTED"
             "changes_requested"
           else
             "review_required"
           end

  ci_rollup = pr.dig("commits", "nodes", 0, "commit", "statusCheckRollup", "state")
  ci_status = case ci_rollup
              when "SUCCESS" then "pass"
              when "PENDING", "EXPECTED" then "in_progress"
              when "FAILURE", "ERROR" then "failed"
              else "unknown"
              end

  {
    number: pr["number"],
    title: pr["title"],
    author: pr.dig("author", "login"),
    status: status,
    has_conflicts: pr["mergeable"] == "CONFLICTING",
    requested_from: details[:requested],
    is_me_requested: details[:requested_from_me],
    approved_by: approved_by,
    changes_requested_by: changes_requested_by,
    commented_by: details[:commented_by],
    created_at: pr["createdAt"],
    updated_at: pr["updatedAt"],
    my_reviewed_at: details[:my_reviewed_at],
    needs_re_review: !!details[:needs_re_review],
    ci_status: ci_status,
    unresolved_comments: details[:unresolved_comments],
    total_review_threads: details[:total_review_threads],
    my_approved: !!details[:my_approved],
    base_branch: pr["baseRefName"],
    repo: pr["_repo"],
    url: "https://github.com/#{pr["_repo"]}/pull/#{pr["number"]}"
  }
end

def process_prs(raw_prs)
  cutoff = Time.now - ($days_window * 86400)

  # Sections indexed 0-3. PRs are assigned to exactly one section based on
  # review state. The order here matches the display order in the frontend.
  sections = [
    { id: 1, title: "Need my review", color: "#d29922", prs: [] },     # 0: explicitly requested or needs re-review
    { id: 2, title: "Not reviewed by me", color: "#58a6ff", prs: [] },  # 1: open PRs I haven't reviewed yet
    { id: 3, title: "Already reviewed by me", color: "#3fb950", prs: [] }, # 2: I submitted a review already
    { id: 4, title: "Draft", color: "#8b949e", prs: [] }               # 3: draft PRs (always separated)
  ]

  raw_prs.each do |pr|
    next if Time.parse(pr["updatedAt"]) <= cutoff
    # Own PRs are never shown on the review page — they appear on "My PRs" page instead.
    next if MY_ALIASES.include?(pr.dig("author", "login"))

    details = extract_pr_details(pr)

    if pr["isDraft"]
      sections[3][:prs] << build_pr_hash(pr, details)
      next
    end

    # Section assignment priority (first match wins):
    #   0 "Need my review"        — my review is explicitly requested, OR
    #                                author responded (comment/code) after my non-approval review
    #   2 "Already reviewed by me" — I approved, OR I reviewed and author hasn't responded yet
    #   1 "Not reviewed by me"    — I haven't submitted any review yet
    # my_approved always wins → section 2. Once I approved a PR, it's done from my side
    # regardless of subsequent author activity. If new review is truly needed, the author
    # or a maintainer will re-request review (caught by requested_from_me).
    section = if details[:requested_from_me] then 0
              elsif details[:my_approved] then 2
              elsif details[:needs_re_review] then 0
              elsif !details[:reviewed] then 1
              else 2
              end

    # No reviewDecision filter for any section. Previously section 2 ("Already reviewed by me")
    # dropped PRs where reviewDecision was null or APPROVED, but that hid PRs in repos without
    # required-reviews branch protection (reviewDecision stays null even after reviews).
    # Instead, visibility is controlled entirely by the re-review logic above:
    #   - Author responded after my review → moves to section 0 ("Need my review")
    #   - No response yet → stays in section 2 ("Already reviewed by me")
    # Section 0 ("Need my review") must also NEVER be filtered — reviewDecision can be empty
    # even on PRs with pending review requests (e.g. when only bot COMMENTED reviews exist,
    # which GitHub doesn't count toward reviewDecision).

    sections[section][:prs] << build_pr_hash(pr, details)
  end

  sections.each { |s| s[:prs].sort_by! { |p| -p[:number] } }

  total = sections.sum { |s| s[:prs].size }
  { sections: sections, total: total, updated_at: Time.now.utc.iso8601, days_window: $days_window }
end

def process_my_prs(raw_prs)
  cutoff = Time.now - ($days_window * 86400)

  sections = [
    { id: 0, title: "Ready to merge", color: "#a371f7", prs: [] },
    { id: 1, title: "Changes requested", color: "#f85149", prs: [] },
    { id: 2, title: "Waiting for review", color: "#d29922", prs: [] },
    { id: 3, title: "Approved", color: "#3fb950", prs: [] },
    { id: 4, title: "Draft", color: "#8b949e", prs: [] }
  ]

  raw_prs.each do |pr|
    next if Time.parse(pr["updatedAt"]) <= cutoff
    next unless MY_ALIASES.include?(pr.dig("author", "login"))

    details = extract_pr_details(pr)

    if pr["isDraft"]
      sections[4][:prs] << build_pr_hash(pr, details)
      next
    end

    pr_hash = build_pr_hash(pr, details)

    if pr["reviewDecision"] == "CHANGES_REQUESTED"
      sections[1][:prs] << pr_hash
    elsif pr["reviewDecision"] == "APPROVED"
      if pr_hash[:approved_by].any? && pr_hash[:changes_requested_by].empty? && pr_hash[:ci_status] == "pass" && !pr_hash[:has_conflicts]
        sections[0][:prs] << pr_hash
      else
        sections[3][:prs] << pr_hash
      end
    else
      sections[2][:prs] << pr_hash
    end
  end

  sections.each { |s| s[:prs].sort_by! { |p| -p[:number] } }

  total = sections.sum { |s| s[:prs].size }
  { sections: sections, total: total, updated_at: Time.now.utc.iso8601, days_window: $days_window }
end

def refresh_cache
  raw = fetch_prs
  return unless raw
  result = process_prs(raw)
  my_result = process_my_prs(raw)
  $cache_mutex.synchronize do
    $pr_cache = result
    $my_pr_cache = my_result
  end
  $stderr.puts "[#{Time.now}] Refreshed: #{result[:total]} PRs, #{my_result[:total]} my PRs"
rescue StandardError => e
  $stderr.puts "[#{Time.now}] Refresh error: #{e.message}"
end

def refresh_stats_cache
  raw = fetch_stats_prs
  return unless raw
  result = process_stats(raw)
  $cache_mutex.synchronize { $stats_cache = result }
  $stderr.puts "[#{Time.now}] Stats refreshed"
rescue StandardError => e
  $stderr.puts "[#{Time.now}] Stats refresh error: #{e.message}"
end

# --- Background poller ---

Thread.new do
  $last_stats_refresh = Time.at(0)
  loop do
    refresh_cache
    # Stats cover a wider historical window and change slowly (merges, review counts),
    # so we refresh them less frequently than the live PR list.
    if Time.now - $last_stats_refresh >= STATS_POLL_INTERVAL
      refresh_stats_cache
      $last_stats_refresh = Time.now
    end
    loaded = $cache_mutex.synchronize { $pr_cache[:updated_at] }
    sleep(loaded ? POLL_INTERVAL : 10)
  end
end

# --- Routes ---

before do
  response.headers["Access-Control-Allow-Origin"] = "*"
  response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Content-Type"
end

options "*" do
  200
end

get "/api/prs" do
  content_type :json
  data = $cache_mutex.synchronize { $pr_cache.dup }
  data.to_json
end

get "/api/my-prs" do
  content_type :json
  data = $cache_mutex.synchronize { $my_pr_cache.dup }
  data.to_json
end

post "/api/refresh" do
  refresh_cache
  refresh_stats_cache
  content_type :json
  data = $cache_mutex.synchronize { $pr_cache.dup }
  data.to_json
end

post "/api/refresh/prs" do
  refresh_cache
  content_type :json
  data = $cache_mutex.synchronize { $pr_cache.dup }
  data.to_json
end

post "/api/refresh/stats" do
  refresh_stats_cache
  content_type :json
  data = $cache_mutex.synchronize { $stats_cache.dup }
  data.to_json
end

post "/api/days_window" do
  body = JSON.parse(request.body.read)
  new_window = Integer(body["days_window"])
  halt 400, { error: "days_window must be between 1 and 30" }.to_json unless (1..30).include?(new_window)

  $days_window = new_window
  refresh_cache
  content_type :json
  data = $cache_mutex.synchronize { $pr_cache.dup }
  data.to_json
end

get "/api/pr/:owner/:name/:number" do
  pr_number = Integer(params[:number])
  owner = params[:owner]
  name = params[:name]
  repo_full = "#{owner}/#{name}"

  query = <<~GQL
    query {
      repository(owner: "#{owner}", name: "#{name}") {
        pullRequest(number: #{pr_number}) {
          id number title body isDraft mergeable createdAt updatedAt
          author { login }
          reviewDecision
          additions deletions changedFiles
          baseRefName headRefName
          reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { name } } } }
          reviews(last: 100) { nodes { author { login } state submittedAt } }
          commits(last: 1) {
            nodes {
              commit {
                committedDate
                statusCheckRollup {
                  state
                  contexts(first: 100) {
                    nodes {
                      ... on CheckRun { name conclusion status detailsUrl }
                      ... on StatusContext { context state description targetUrl }
                    }
                  }
                }
              }
            }
          }
          reviewThreads(first: 100) {
            nodes {
              isResolved
              path
              line
              comments(first: 30) {
                nodes {
                  author { login }
                  body
                  createdAt
                  url
                }
              }
            }
          }
          comments(first: 100) { nodes { author { login } } }
        }
      }
    }
  GQL

  data = with_gh_connection { |http| gh_request(http, query) }
  pr = data.dig("data", "repository", "pullRequest")
  halt 404, { error: "PR not found" }.to_json unless pr

  details = extract_pr_details(pr)

  approved_by = details[:latest_reviews].select { |_, r| r["state"] == "APPROVED" }.keys.sort
  changes_requested_by = details[:latest_reviews].select { |_, r| r["state"] == "CHANGES_REQUESTED" }.keys.sort

  status = if pr["isDraft"] then "draft"
           elsif pr["reviewDecision"] == "APPROVED" then "approved"
           elsif pr["reviewDecision"] == "CHANGES_REQUESTED" then "changes_requested"
           else "review_required"
           end

  ci_rollup = pr.dig("commits", "nodes", 0, "commit", "statusCheckRollup", "state")
  ci_status = case ci_rollup
              when "SUCCESS" then "pass"
              when "PENDING", "EXPECTED" then "in_progress"
              when "FAILURE", "ERROR" then "failed"
              else "unknown"
              end

  ci_checks = (pr.dig("commits", "nodes", 0, "commit", "statusCheckRollup", "contexts", "nodes") || []).map do |node|
    if node["name"]
      { name: node["name"], status: node["status"]&.downcase, conclusion: node["conclusion"]&.downcase, url: node["detailsUrl"] }
    elsif node["context"]
      conclusion = case node["state"]
                   when "SUCCESS" then "success"
                   when "PENDING", "EXPECTED" then nil
                   when "FAILURE", "ERROR" then "failure"
                   end
      { name: node["context"], status: node["state"] == "PENDING" ? "in_progress" : "completed", conclusion: conclusion, url: node["targetUrl"] }
    end
  end.compact

  unresolved_threads = (pr.dig("reviewThreads", "nodes") || []).select { |t| !t["isResolved"] }.map do |thread|
    comments = (thread.dig("comments", "nodes") || []).map do |c|
      { author: c.dig("author", "login"), body: c["body"], created_at: c["createdAt"], url: c["url"] }
    end
    { path: thread["path"], line: thread["line"], comments: comments }
  end

  content_type :json
  {
    node_id: pr["id"],
    number: pr["number"],
    title: pr["title"],
    body: pr["body"],
    author: pr.dig("author", "login"),
    status: status,
    has_conflicts: pr["mergeable"] == "CONFLICTING",
    requested_from: details[:requested],
    is_me_requested: details[:requested_from_me],
    approved_by: approved_by,
    changes_requested_by: changes_requested_by,
    commented_by: details[:commented_by],
    created_at: pr["createdAt"],
    updated_at: pr["updatedAt"],
    my_reviewed_at: details[:my_reviewed_at],
    needs_re_review: !!details[:needs_re_review],
    ci_status: ci_status,
    ci_checks: ci_checks,
    unresolved_comments: details[:unresolved_comments],
    total_review_threads: details[:total_review_threads],
    unresolved_threads: unresolved_threads,
    url: "https://github.com/#{repo_full}/pull/#{pr["number"]}",
    additions: pr["additions"],
    deletions: pr["deletions"],
    changed_files: pr["changedFiles"],
    base_branch: pr["baseRefName"],
    head_branch: pr["headRefName"],
  }.to_json
end

post "/api/pr/:owner/:name/:number/approve" do
  pr_number = Integer(params[:number])
  owner = params[:owner]
  name = params[:name]

  # First get the PR node ID
  id_query = <<~GQL
    query {
      repository(owner: "#{owner}", name: "#{name}") {
        pullRequest(number: #{pr_number}) { id }
      }
    }
  GQL

  data = with_gh_connection { |http| gh_request(http, id_query) }
  pr_id = data.dig("data", "repository", "pullRequest", "id")
  halt 404, { error: "PR not found" }.to_json unless pr_id

  # Submit approval review
  mutation = <<~GQL
    mutation {
      addPullRequestReview(input: { pullRequestId: "#{pr_id}", event: APPROVE }) {
        pullRequestReview { state }
      }
    }
  GQL

  result = with_gh_connection { |http| gh_request(http, mutation) }
  errors = result["errors"]
  halt 422, { error: errors.map { |e| e["message"] }.join(", ") }.to_json if errors&.any?

  content_type :json
  { success: true, state: result.dig("data", "addPullRequestReview", "pullRequestReview", "state") }.to_json
end

get "/api/stats" do
  content_type :json
  data = $cache_mutex.synchronize { $stats_cache.dup }
  data.to_json
end

post "/api/stats_window" do
  body = JSON.parse(request.body.read)
  new_window = Integer(body["window_days"])
  halt 400, { error: "window_days must be 7, 14, 21, or 28" }.to_json unless [7, 14, 21, 28].include?(new_window)

  $stats_window = new_window
  refresh_stats_cache
  content_type :json
  data = $cache_mutex.synchronize { $stats_cache.dup }
  data.to_json
end

get "/api/repos" do
  content_type :json
  {
    available: AVAILABLE_REPOS.map { |full, label| { id: full, label: label } },
    enabled: $enabled_repos.dup
  }.to_json
end

post "/api/repos" do
  body = JSON.parse(request.body.read)
  repos = Array(body["repos"]).select { |r| AVAILABLE_REPOS.key?(r) }
  halt 400, { error: "At least one repo must be enabled" }.to_json if repos.empty?

  $enabled_repos = repos
  refresh_cache
  content_type :json
  { enabled: $enabled_repos.dup }.to_json
end

get "/api/rate-limit" do
  content_type :json
  # Serve from cached values gathered from GraphQL response headers and inline rateLimit fields,
  # avoiding a separate REST API call that would itself consume rate limit.
  $rate_limit_info.to_json
end

get "/api/rate-limit-history" do
  content_type :json
  $rate_limit_history_mutex.synchronize { $rate_limit_history.dup }.to_json
end

get "/health" do
  content_type :json
  { status: "ok" }.to_json
end
