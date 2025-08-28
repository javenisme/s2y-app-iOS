#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "[ERROR] GitHub CLI (gh) is not installed. Install via: brew install gh" >&2
  exit 1
fi

# Detect owner/repo from git remote
REMOTE_URL=$(git remote get-url origin)
if [[ -z "${REMOTE_URL:-}" ]]; then
  echo "[ERROR] No git remote 'origin' found." >&2
  exit 1
fi

if [[ "$REMOTE_URL" =~ github.com[:/](.+)/(.+)\.git$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
else
  echo "[ERROR] Unsupported remote URL: $REMOTE_URL" >&2
  exit 1
fi

echo "Using repository: $OWNER/$REPO"

echo "Ensuring authentication (requires prior: gh auth login -s repo -w)"
if ! gh auth status >/dev/null 2>&1; then
  echo "[ERROR] gh is not authenticated. Run: gh auth login -s repo -w" >&2
  exit 1
fi

PROJECT_TITLE="S2Y Roadmap"

# Find or create user-level project under OWNER
get_project_number() {
  gh project list --owner "$OWNER" --format json \
    | jq -r --arg title "$PROJECT_TITLE" '.projects[] | select(.title == $title) | .number' \
    | head -n1
}

PROJECT_NUMBER=$(get_project_number || true)
if [[ -z "${PROJECT_NUMBER:-}" ]]; then
  echo "Creating project: $PROJECT_TITLE"
  gh project create --owner "$OWNER" --title "$PROJECT_TITLE" >/dev/null
  PROJECT_NUMBER=$(get_project_number)
  echo "Created project number: $PROJECT_NUMBER"
else
  echo "Project exists: #$PROJECT_NUMBER $PROJECT_TITLE"
fi

add_issue_urls_for_milestone() {
  local milestone_title="$1"
  gh issue list --repo "$OWNER/$REPO" --state open --search "milestone:\"$milestone_title\"" --json url -L 200 | jq -r '.[].url'
}

add_item_to_project() {
  local url="$1"
  # Add issue to project; capture item id if printed
  gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$url" >/dev/null || true
}

for MS in M0 M1 M2 M3; do
  echo "Adding issues for milestone $MS"
  while read -r ISSUE_URL; do
    [[ -z "$ISSUE_URL" ]] && continue
    add_item_to_project "$ISSUE_URL"
    echo "Added: $ISSUE_URL"
  done < <(add_issue_urls_for_milestone "$MS")
done

echo "All issues added to project $PROJECT_TITLE (#$PROJECT_NUMBER)."


