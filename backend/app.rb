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
DAYS_WINDOW = Integer(ENV.fetch("DAYS_WINDOW", "3"))

set :bind, "0.0.0.0"
set :port, 4567

$pr_cache = { sections: [], updated_at: nil, total: 0 }
$cache_mutex = Mutex.new

# --- GitHub API helpers ---

def gh_graphql(query, variables = {})
  uri = URI("https://api.github.com/graphql")
  req = Net::HTTP::Post.new(uri)
  req["Authorization"] = "Bearer #{GH_TOKEN}"
  req["Content-Type"] = "application/json"
  req.body = { query: query, variables: variables }.to_json

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  JSON.parse(res.body)
end

def fetch_prs
  owner, name = REPO.split("/")
  all_prs = []
  cursor = nil

  loop do
    after_clause = cursor ? ", after: \"#{cursor}\"" : ""
    query = <<~GQL
      query {
        repository(owner: "#{owner}", name: "#{name}") {
          pullRequests(states: OPEN, first: 100, orderBy: {field: UPDATED_AT, direction: DESC}#{after_clause}) {
            pageInfo { hasNextPage endCursor }
            nodes {
              number
              title
              isDraft
              updatedAt
              author { login }
              reviewDecision
              reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { name } } } }
              reviews(first: 50) { nodes { author { login } state submittedAt } }
            }
          }
        }
      }
    GQL

    data = gh_graphql(query)
    pr_nodes = data.dig("data", "repository", "pullRequests", "nodes") || []
    page_info = data.dig("data", "repository", "pullRequests", "pageInfo")

    all_prs.concat(pr_nodes)

    cutoff = Time.now - (DAYS_WINDOW * 86400)
    last_updated = pr_nodes.last && Time.parse(pr_nodes.last["updatedAt"])
    break if last_updated && last_updated < cutoff
    break unless page_info&.dig("hasNextPage")

    cursor = page_info["endCursor"]
  end

  all_prs
end

def process_prs(raw_prs)
  cutoff = Time.now - (DAYS_WINDOW * 86400)

  filtered = raw_prs.select do |pr|
    next false if pr["isDraft"]

    author = pr.dig("author", "login")
    next false if MY_ALIASES.include?(author)
    next false unless %w[REVIEW_REQUIRED CHANGES_REQUESTED].include?(pr["reviewDecision"])

    Time.parse(pr["updatedAt"]) > cutoff
  end

  sections = [
    { id: 1, title: "Review requested from me", color: "#d29922", prs: [] },
    { id: 2, title: "Not reviewed by me", color: "#58a6ff", prs: [] },
    { id: 3, title: "Already reviewed by me", color: "#3fb950", prs: [] }
  ]

  filtered.each do |pr|
    requested = (pr.dig("reviewRequests", "nodes") || []).map { |r|
      r.dig("requestedReviewer", "login") || r.dig("requestedReviewer", "name")
    }.compact
    reviewed = (pr.dig("reviews", "nodes") || []).any? { |r| MY_ALIASES.include?(r.dig("author", "login")) }
    requested_from_me = MY_ALIASES.any? { |a| requested.include?(a) }

    latest_reviews = {}
    (pr.dig("reviews", "nodes") || []).each do |r|
      login = r.dig("author", "login")
      next unless login
      ts = r["submittedAt"]
      prev = latest_reviews[login]
      latest_reviews[login] = r if prev.nil? || (ts && prev["submittedAt"] && ts > prev["submittedAt"])
    end

    approved_by = latest_reviews.select { |_, r| r["state"] == "APPROVED" }.keys.sort
    changes_requested_by = latest_reviews.select { |_, r| r["state"] == "CHANGES_REQUESTED" }.keys.sort

    section = if requested_from_me then 0
              elsif !reviewed then 1
              else 2
              end

    sections[section][:prs] << {
      number: pr["number"],
      title: pr["title"],
      author: pr.dig("author", "login"),
      status: pr["reviewDecision"] == "CHANGES_REQUESTED" ? "changes_requested" : "review_required",
      requested_from: requested,
      is_me_requested: requested_from_me,
      approved_by: approved_by,
      changes_requested_by: changes_requested_by,
      updated_at: pr["updatedAt"],
      url: "https://github.com/#{REPO}/pull/#{pr["number"]}"
    }
  end

  sections.each { |s| s[:prs].sort_by! { |p| -p[:number] } }

  total = sections.sum { |s| s[:prs].size }
  { sections: sections, total: total, updated_at: Time.now.utc.iso8601, days_window: DAYS_WINDOW }
end

def refresh_cache
  raw = fetch_prs
  result = process_prs(raw)
  $cache_mutex.synchronize { $pr_cache = result }
  $stderr.puts "[#{Time.now}] Refreshed: #{result[:total]} PRs"
rescue StandardError => e
  $stderr.puts "[#{Time.now}] Refresh error: #{e.message}"
end

# --- Background poller ---

Thread.new do
  loop do
    refresh_cache
    sleep POLL_INTERVAL
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

post "/api/refresh" do
  refresh_cache
  content_type :json
  data = $cache_mutex.synchronize { $pr_cache.dup }
  data.to_json
end

get "/health" do
  content_type :json
  { status: "ok" }.to_json
end
