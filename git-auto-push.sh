#!/bin/bash

# Git Auto-Push Script with GitHub Deployment
# Handles git operations and copies to -github folder for GitHub deployment

set -euo pipefail  # Basic error handling

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load environment variables from .env file
load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at $ENV_FILE"
        log_info "Please create a .env file with your credentials"
        exit 1
    fi
    
    log_info "Loading environment variables from .env"
    
    # Source the .env file (safely)
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z $key ]] && continue
        
        # Remove surrounding quotes if present
        value=$(echo "$value" | sed 's/^["'\'']//' | sed 's/["'\\'']$//')
        
        # Export the variable
        export "$key"="$value"
    done < "$ENV_FILE"
    
    log_info "Environment variables loaded successfully"
}

# Validate required environment variables
validate_env() {
    local required_vars=("DEFAULT_GITHUB_USERNAME" "DEFAULT_GITHUB_TOKEN")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_info "Please add these to your .env file"
        exit 1
    fi
}

# Get current repository name
get_repo_name() {
    local repo_name
    repo_name=$(basename "$(git rev-parse --show-toplevel)")
    echo "$repo_name"
}

# Perform git operations (add, commit, push)
perform_git_operations() {
    local commit_message="${1:-Auto-commit $(date '+%Y-%m-%d %H:%M:%S')}"
    
    log_info "Performing git operations..."
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a git repository"
        exit 1
    fi
    
    # Add all changes
    log_info "Adding all changes..."
    if ! git add .; then
        log_error "Failed to add files to git"
        exit 1
    fi
    
    # Check if there are changes to commit
    if git diff --cached --quiet; then
        log_warn "No changes to commit"
        return 0
    fi
    
    # Commit changes
    log_info "Committing changes..."
    if ! git commit -m "$commit_message"; then
        log_error "Failed to commit changes"
        exit 1
    fi
    
    # Push to current remote
    log_info "Pushing to current remote..."
    if ! git push; then
        log_error "Failed to push to current remote"
        exit 1
    fi
    
    log_info "Git operations completed successfully"
}

# Copy files to -github folder
copy_to_github_folder() {
    local repo_name
    repo_name=$(get_repo_name)
    local github_folder="${repo_name}-github"
    
    log_info "Copying files to $github_folder..."
    
    # Create target directory if it doesn't exist
    if [[ ! -d "../$github_folder" ]]; then
        mkdir -p "../$github_folder"
        log_info "Created directory: $github_folder"
    fi
    
    # Copy all files except .git and the github folder itself
    local rsync_args=(
        -av
        --exclude='.git'
        --exclude="$github_folder"
        --exclude='.env'
        --exclude='node_modules'
        --exclude='__pycache__'
        --exclude='.DS_Store'
        --exclude='*.log'
    )
    
    if ! rsync "${rsync_args[@]}" "./" "../$github_folder/"; then
        log_error "Failed to copy files to $github_folder"
        exit 1
    fi
    
    log_info "Files copied to $github_folder successfully"
}

# Push to GitHub using credentials from .env
push_to_github() {
    local repo_name
    repo_name=$(get_repo_name)
    local github_folder="${repo_name}-github"
    local github_username="${GITHUB_USERNAME:-$DEFAULT_GITHUB_USERNAME}"
    local github_token="${GITHUB_TOKEN:-$DEFAULT_GITHUB_TOKEN}"
    
    log_info "Setting up GitHub repository..."
    
    # Navigate to github folder
    cd "../$github_folder"
    
    # Initialize git if not already initialized
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_info "Initializing git repository in $github_folder..."
        git init
    fi
    
    # Configure git user if not set
    if ! git config user.name >/dev/null 2>&1; then
        git config user.name "$github_username"
        git config user.email "${github_username}@users.noreply.github.com"
    fi
    
    # Add remote if not exists
    local remote_url="https://${github_username}:${github_token}@github.com/${github_username}/${repo_name}.git"
    if ! git remote get-url origin >/dev/null 2>&1; then
        git remote add origin "$remote_url"
        log_info "Added GitHub remote: origin"
    else
        # Update remote URL to include credentials
        git remote set-url origin "$remote_url"
    fi
    
    # Add, commit, and push
    log_info "Adding files to GitHub repository..."
    git add .
    
    # Check if there are changes to commit
    if ! git diff --cached --quiet; then
        git commit -m "Deploy to GitHub $(date '+%Y-%m-%d %H:%M:%S')" || true
    fi
    
    log_info "Pushing to GitHub..."
    if ! git push -u origin main 2>/dev/null && ! git push -u origin master 2>/dev/null; then
        log_error "Failed to push to GitHub. Make sure the repository exists on GitHub."
        exit 1
    fi
    
    # Go back to original directory
    cd - >/dev/null
    
    log_info "GitHub deployment completed successfully"
}

# Main function
main() {
    local commit_message="${1:-}"
    
    log_info "Starting Git Auto-Push with GitHub Deployment..."
    
    # Load and validate environment
    load_env
    validate_env
    
    # Perform operations
    perform_git_operations "$commit_message"
    copy_to_github_folder
    push_to_github
    
    log_info "All operations completed successfully! 🎉"
}

# Help function
show_help() {
    cat << EOF
Git Auto-Push Script with GitHub Deployment

USAGE:
    $0 [OPTIONS] [COMMIT_MESSAGE]

OPTIONS:
    -h, --help     Show this help message

DESCRIPTION:
    This script performs the following operations:
    1. Loads credentials from .env file
    2. Adds, commits, and pushes current repository
    3. Copies files to repo-name-github folder
    4. Pushes the copied files to GitHub using credentials

ENVIRONMENT FILE (.env):
    REQUIRED:
        DEFAULT_GITHUB_USERNAME=your_github_username
        DEFAULT_GITHUB_TOKEN=your_github_personal_access_token
    
    OPTIONAL:
        GITHUB_USERNAME=override_username_for_this_run
        GITHUB_TOKEN=override_token_for_this_run

EXAMPLES:
    $0 "Fix bug in authentication"
    $0  # Uses default commit message

REQUIREMENTS:
    - Git must be initialized in the current directory
    - .env file must exist with required credentials
    - GitHub repository should exist (script will create if needed)
EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac