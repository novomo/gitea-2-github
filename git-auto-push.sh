#!/bin/bash

# Git Auto-Push Script: Gitea → GitHub Mirror (SSH-only, no credentials)
# 1. Commit & push to Gitea (uses your existing origin remote over SSH)
# 2. rsync to ../repo-github (with --delete for perfect sync)
# 3. Commit & push to GitHub via SSH (one-time manual remote setup)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

main() {
    local commit_msg="${1:-Auto-commit $(date '+%Y-%m-%d %H:%M:%S')}"

    log_info "=== Starting Gitea → GitHub sync ==="

    # Go to repo root
    cd "$(git rev-parse --show-toplevel)"

    local repo_name
    repo_name=$(basename "$(pwd)")
    local github_folder="${repo_name}-github"
    local branch
    branch="$(git branch --show-current)"

    [[ -z "$branch" ]] && { log_error "Not on a branch (detached HEAD)"; exit 1; }

    # === 1. Push to Gitea (uses your SSH origin) ===
    log_info "1. Adding, committing and pushing to Gitea (branch: $branch)..."
    git add -A

    if git diff --cached --quiet; then
        log_warn "No changes to commit"
    else
        git commit -m "$commit_msg"
        git push || { log_error "Push to Gitea failed — check your SSH setup"; exit 1; }
        log_info "✓ Successfully pushed to Gitea"
    fi

    # === 2. rsync to -github folder (perfect mirror, including deletions) ===
    log_info "2. Syncing files to ../${github_folder} (with deletion of removed files)..."
    mkdir -p "../${github_folder}"

    rsync -av --delete \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='__pycache__' \
        --exclude='.DS_Store' \
        --exclude='*.log' \
        ./ "../${github_folder}/"

    log_info "✓ Files synced to ../${github_folder}"

    # === 3. Commit & push to GitHub (SSH) ===
    cd "../${github_folder}"

    # Initialize only if completely new
    if [[ ! -d ".git" ]] && ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_info "First-time setup: Initializing new Git repo with branch '$branch'"
        git init -b "$branch"
    fi

    git add -A

    if git diff --cached --quiet; then
        log_warn "No changes to commit for GitHub"
        cd - >/dev/null
        log_info "=== Sync complete! ==="
        exit 0
    fi

    git commit -m "Mirror from Gitea: ${commit_msg}"
    log_info "Committed changes for GitHub"

    # === Push only if remote exists ===
    if git remote get-url origin >/dev/null 2>&1; then
        log_info "Pushing to GitHub via SSH (branch: $branch)..."
        git push -u origin "$branch" || { log_error "Push to GitHub failed"; exit 1; }
        log_info "✓ Successfully pushed to GitHub"
    else
        log_warn "No 'origin' remote found in the GitHub mirror."
        echo ""
        log_info "One-time setup required (run this once):"
        echo "   cd ../${github_folder}"
        echo "   git remote add origin git@github.com:YOUR_GITHUB_USERNAME/${repo_name}.git"
        echo "   git push -u origin $branch"
        echo ""
        log_info "After that, all future runs will push automatically via SSH."
        log_info "(If your GitHub repo has a different name, adjust it in the URL above.)"
    fi

    cd - >/dev/null
    log_info "=== All done! 🎉 ==="
}

# Help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [commit message]"
    echo ""
    echo "Pushes to Gitea → syncs files → pushes to GitHub over SSH."
    echo "First run requires one manual 'git remote add origin ...' (shown in output)."
    exit 0
fi

main "$@"