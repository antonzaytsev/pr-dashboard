# Project Rules

## Running the app

Always run the app using Docker Compose. Do not run the backend or frontend directly on the host.

```sh
docker compose up        # start both services
docker compose up -d     # start in background
docker compose down      # stop
docker compose restart   # restart
docker compose logs -f   # tail logs
```

- Backend: http://localhost:4511
- Frontend: http://localhost:4510

## Code comments

When making non-obvious decisions in code — especially around filtering logic, edge cases, or anything where a future reader might ask "why?" — add a comment explaining the reasoning. Focus on the *why*, not the *what*. This is critical for this codebase because filtering and section-assignment logic has subtle interactions (e.g. GitHub API fields like `reviewDecision` can be empty in non-obvious situations), and incorrect changes can silently hide PRs from the dashboard.
