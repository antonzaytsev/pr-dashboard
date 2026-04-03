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
$days_window = 3

set :bind, "0.0.0.0"
set :port, Integer(ENV.fetch("PORT", "4511"))

$pr_cache = { sections: [], updated_at: nil, total: 0 }
$my_pr_cache = { sections: [], updated_at: nil, total: 0 }
$cache_mutex = Mutex.new
$rate_limit_reset = nil # Time when rate limit resets; skip GH calls until then

# --- GitHub API helpers ---

DETAIL_BATCH_SIZE = 15
MAX_PARALLEL = 4

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
  JSON.parse(res.body)
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

    # Pass 2: fetch review/comment details in parallel batches
    batches = relevant.map { |pr| pr["number"] }.each_slice(DETAIL_BATCH_SIZE).to_a
    details = {}
    mutex = Mutex.new

    batches.each_slice(MAX_PARALLEL) do |chunk|
      threads = chunk.map do |batch|
        Thread.new do
          with_gh_connection do |http|
            aliases = batch.map { |n|
              "pr_#{n}: pullRequest(number: #{n}) {\n#{DETAIL_FIELDS}}"
            }.join("\n")
            query = %Q(query { repository(owner: "#{owner}", name: "#{name}") {\n#{aliases}\n} })
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

    relevant.each { |pr| pr.merge!(details[pr["number"]] || {}) }
    $stderr.puts "[#{Time.now}] Pass 2 done (#{repo_full}): details fetched for #{details.size} PRs in #{batches.size} batches"
    all_prs.concat(relevant)
  end

  all_prs
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

  author_replied = false
  if reviewed && !my_approved && my_reviewed_at
    pr_author = pr.dig("author", "login")
    (pr.dig("reviewThreads", "nodes") || []).each do |thread|
      comments = thread.dig("comments", "nodes") || []
      next unless comments.any? { |c| MY_ALIASES.include?(c.dig("author", "login")) }

      if comments.any? { |c| c.dig("author", "login") == pr_author && c["createdAt"] && c["createdAt"] > my_reviewed_at }
        author_replied = true
        break
      end
    end
  end

  needs_re_review = reviewed && !my_approved && author_replied

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

  sections = [
    { id: 1, title: "Need my review", color: "#d29922", prs: [] },
    { id: 2, title: "Not reviewed by me", color: "#58a6ff", prs: [] },
    { id: 3, title: "Already reviewed by me", color: "#3fb950", prs: [] },
    { id: 4, title: "Draft", color: "#8b949e", prs: [] }
  ]

  raw_prs.each do |pr|
    next if Time.parse(pr["updatedAt"]) <= cutoff
    next if MY_ALIASES.include?(pr.dig("author", "login"))

    details = extract_pr_details(pr)

    if pr["isDraft"]
      sections[3][:prs] << build_pr_hash(pr, details)
      next
    end

    section = if details[:my_approved] then 2
              elsif details[:requested_from_me] then 0
              elsif details[:needs_re_review] then 0
              elsif !details[:reviewed] then 1
              else 2
              end

    if section != 1
      next unless %w[REVIEW_REQUIRED CHANGES_REQUESTED].include?(pr["reviewDecision"])
    end

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

# --- Background poller ---

Thread.new do
  loop do
    refresh_cache
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
  content_type :json
  data = $cache_mutex.synchronize { $pr_cache.dup }
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
  uri = URI("https://api.github.com/rate_limit")
  http = Net::HTTP.new(uri.hostname, uri.port)
  http.use_ssl = true
  http.open_timeout = 5
  http.read_timeout = 5
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Bearer #{GH_TOKEN}"
  res = JSON.parse(http.request(req).body)
  graphql = res.dig("resources", "graphql") || {}
  { limit: graphql["limit"], used: graphql["used"], remaining: graphql["remaining"], reset: graphql["reset"] }.to_json
rescue StandardError => e
  status 502
  { error: e.message }.to_json
end

get "/health" do
  content_type :json
  { status: "ok" }.to_json
end
