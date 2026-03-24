# frozen_string_literal: true

require "sinatra"
require "json"
require "time"
require "net/http"
require "uri"

REPO = "sdtechdev/spree-jiffyshirts"
MY_ALIASES = %w[zaytsev-anton antonzaytsev].freeze
GH_TOKEN = ENV.fetch("GITHUB_TOKEN")
POLL_INTERVAL = Integer(ENV.fetch("POLL_INTERVAL", "300")) # seconds
$days_window = Integer(ENV.fetch("DAYS_WINDOW", "3"))

set :bind, "0.0.0.0"
set :port, Integer(ENV.fetch("PORT", "4567"))

$pr_cache = { sections: [], updated_at: nil, total: 0 }
$my_pr_cache = { sections: [], updated_at: nil, total: 0 }
$cache_mutex = Mutex.new

# --- GitHub API helpers ---

DETAIL_BATCH_SIZE = 15
MAX_PARALLEL = 4

GH_URI = URI("https://api.github.com/graphql").freeze

DETAIL_FIELDS = <<~GQL.freeze
  reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { name } } } }
  reviews(first: 50) { nodes { author { login } state submittedAt } }
  commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
  reviewThreads(first: 50) { nodes { comments(first: 30) { nodes { author { login } createdAt } } } }
  comments(first: 100) { nodes { author { login } } }
GQL

def with_gh_connection(&block)
  Net::HTTP.start(GH_URI.hostname, GH_URI.port, use_ssl: true, read_timeout: 30, open_timeout: 10, &block)
end

def gh_request(http, query)
  req = Net::HTTP::Post.new(GH_URI)
  req["Authorization"] = "Bearer #{GH_TOKEN}"
  req["Content-Type"] = "application/json"
  req.body = { query: query }.to_json
  JSON.parse(http.request(req).body)
end

def fetch_prs
  owner, name = REPO.split("/")
  cutoff = Time.now - ($days_window * 86400)

  # Pass 1: lightweight list (sequential pagination, persistent connection)
  all_prs = []
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
                number title isDraft mergeable createdAt updatedAt
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
      all_prs.concat(nodes)

      last_updated = nodes.last && Time.parse(nodes.last["updatedAt"])
      break if last_updated && last_updated < cutoff
      break unless page_info&.dig("hasNextPage")
      cursor = page_info["endCursor"]
    end
  end

  relevant = all_prs.select { |pr| Time.parse(pr["updatedAt"]) > cutoff }
  $stderr.puts "[#{Time.now}] Pass 1 done: #{all_prs.size} fetched, #{relevant.size} within window"

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
  $stderr.puts "[#{Time.now}] Pass 2 done: details fetched for #{details.size} PRs in #{batches.size} batches"
  relevant
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

  my_latest_review_state = latest_reviews.select { |k, _| MY_ALIASES.include?(k) }.values.first&.dig("state")
  my_approved = my_latest_review_state == "APPROVED"

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

  { requested: requested, requested_from_me: requested_from_me,
    latest_reviews: latest_reviews, commented_by: commented_by, reviewed: reviewed,
    my_reviewed_at: my_reviewed_at, my_approved: my_approved, needs_re_review: needs_re_review }
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
    url: "https://github.com/#{REPO}/pull/#{pr["number"]}"
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

    next unless %w[REVIEW_REQUIRED CHANGES_REQUESTED].include?(pr["reviewDecision"])

    section = if details[:my_approved] then 2
              elsif details[:requested_from_me] then 0
              elsif details[:needs_re_review] then 0
              elsif !details[:reviewed] then 1
              else 2
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

get "/health" do
  content_type :json
  { status: "ok" }.to_json
end
