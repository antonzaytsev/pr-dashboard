# PR Dashboard

A personal PR review dashboard that tracks open pull requests on a GitHub repo. Shows which PRs need your review, which you've already reviewed, and the status of your own PRs — with CI status, merge conflicts, and smart re-review detection.

## Features

- **Need My Review** — PRs where you're requested or the author replied to your comments
- **My PRs** — your PRs grouped by status: ready to merge, changes requested, waiting for review, approved, draft
- **CI & Conflicts** — CI pass/fail/running status and merge conflict indicators per PR
- **Configurable time window** — filter PRs by how recently they were updated (1–30 days), persisted in localStorage
- **Column toggles** — show/hide columns to customize the view
- **Auto-refresh** — backend polls GitHub on an interval and caches results

## Tech Stack

- **Backend**: Ruby / Sinatra — fetches PRs via GitHub GraphQL API, serves JSON
- **Frontend**: React / TypeScript / Vite — renders the dashboard

## Setup

### Prerequisites

- Docker and Docker Compose (recommended), **or**
- Ruby 3.3+ and Node.js 22+
- A GitHub personal access token with `repo` scope

### 1. Configure environment

```sh
cp .env.example .env
```

Edit `.env` and set your values:

```
GITHUB_TOKEN=ghp_your_token_here
POLL_INTERVAL=300
BACKEND_PORT=4511
FRONTEND_PORT=4510
```

### 2. Configure the repo and user

Edit `backend/app.rb` and update these constants:

```ruby
REPO = "your-org/your-repo"
MY_ALIASES = %w[your-github-username].freeze
```

### 3a. Run with Docker Compose (recommended)

```sh
docker compose up
```

Frontend: http://localhost:4510 (or your `FRONTEND_PORT`)
Backend API: http://localhost:4511 (or your `BACKEND_PORT`)

### 3b. Run without Docker

```sh
# Backend
cd backend
bundle install
GITHUB_TOKEN=ghp_... ruby app.rb

# Frontend (in another terminal)
cd frontend
npm install
npm run dev
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/prs` | PRs to review |
| GET | `/api/my-prs` | Your own PRs |
| POST | `/api/refresh` | Force cache refresh |
| POST | `/api/days_window` | Update time window (`{"days_window": 7}`) |
| GET | `/health` | Health check |
