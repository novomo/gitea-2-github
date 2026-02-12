#!/bin/bash

# Git Auto-Push Script: Gitea → GitHub Mirror
# 1. Commit & push to Gitea
# 2. Copy to ../repo-github folder
# 3. Commit & push to GitHub

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at $ENV_FILE"
        log_info "Copy env-template.txt to .env and fill in your credentials."
        exit 1
    fi

    log_info "Loading .env file..."
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
    log_info "Environment loaded successfully"
}

validate_env() {
    local missing=()
    [[ -z "${DEFAULT_GITHUB_USERNAME:-}" ]] && missing+=("DEFAULT_GITHUB_USERNAME")
    [[ -z "${DEFAULT_GITHUB_TOKEN:-}" ]] && missing+=("DEFAULT_GITHUB_TOKEN")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required variables: ${missing[*]}"
        exit 1
    fi
}

main() {
    local commit_msg="${1:-Auto-commit $(date '+%Y-%m-%d %H:%M:%S')}"

    log_info "=== Starting Gitea → GitHub sync ==="

    # Go to repo root
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "Not inside a git repository"
        exit 1
    fi
    cd "$(git rev-parse --show-toplevel)"

    local repo_name
    repo_name=$(basename "$(pwd)")
    local github_folder="${repo_name}-github"
    local branch
    branch="$(git branch --show-current)"

    if [[ -z "$branch" ]]; then
        log_error "Not on a branch (detached HEAD). Please checkout a branch."
        exit 1
    fi

    load_env
    validate_env

    # === 1. Push to Gitea ===
    log_info "1. Adding, committing and pushing to Gitea..."
    git add -A

    if git diff --cached --quiet; then
        log_warn "No changes to commit"
    else
        git commit -m "$commit_msg"
        log_info "Pushing to Gitea (branch: $branch)..."
        git push
        log_info "✓ Successfully pushed to Gitea"
    fi

    # === 2. Copy to -github folder ===
    log_info "2. Copying files to ../${github_folder}..."
    mkdir -p "../${github_folder}"

    rsync -av \
        --exclude='.git' \
        --exclude='.env' \
        --exclude='node_modules' \
        --exclude='__pycache__' \
        --exclude='.DS_Store' \
        --exclude='*.log' \
        --exclude="${github_folder}" \
        ./ "../${github_folder}/"

    log_info "✓ Files copied to ../${github_folder}"

    # === 3. Push to GitHub ===
    local github_username="${GITHUB_USERNAME:-$DEFAULT_GITHUB_USERNAME}"
    local github_token="${GITHUB_TOKEN:-$DEFAULT_GITHUB_TOKEN}"
    local github_repo_name="${GITHUB_REPO_NAME:-$repo_name}"   # Allow override

    log_info "3. Pushing to GitHub (${github_username}/${github_repo_name}) on branch ${branch}..."

    cd "../${github_folder}"

    # Initialize git if needed
    if [[ -d ".git" ]] || git rev-parse --git-dir >/dev/null 2>&1; then
        log_info "GitHub folder already exists and is a Git repo → skipping init"
    else
        log_info "First time setup: Initializing new Git repo in ${github_folder}"
        git init -b "$branch"
    fi

    # Set identity
    git config user.name "${github_username}"
    git config user.email "${github_username}@users.noreply.github.com"

    # Set remote (with token)
    local remote_url="https://${github_username}:${github_token}@github.com/${github_username}/${github_repo_name}.git"
    if ! git remote get-url origin >/dev/null 2>&1; then
        git remote add origin "$remote_url"
    else
        git remote set-url origin "$remote_url"
    fi

    git add -A

    if ! git diff --cached --quiet; then
        git commit -m "Mirror from Gitea: ${commit_msg}"
        log_info "Committing changes for GitHub..."
    else
        log_warn "No new changes to push to GitHub"
        cd - >/dev/null
        log_info "=== All done! ==="
        exit 0
    fi

    log_info "Pushing to GitHub..."
    if git push -u origin "$branch"; then
        log_info "✓ Successfully pushed to GitHub"
    else
        log_error "Push to GitHub failed."
        log_info "Make sure the repository ${github_repo_name} exists on GitHub and is empty (no initial README/commit)."
        exit 1
    fi

    cd - >/dev/null
    log_info "=== All operations completed successfully! 🎉 ==="
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [commit message]

This script:
  1. Commits and pushes to your Gitea remote
  2. Copies the repo to a sibling folder named <repo>-github
  3. Pushes that copy to GitHub

Put your credentials in .env (copy from env-template.txt).
EOF
}

case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac