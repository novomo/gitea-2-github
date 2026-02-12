#!/bin/bash
set -e

echo "🚀 Installing g2g (Gitea → GitHub sync) system-wide..."

# Download the latest script and install as 'g2g'
sudo curl -L https://raw.githubusercontent.com/novomo/gitea-2-github/main/git-auto-push.sh \
     -o /usr/local/bin/g2g

sudo chmod +x /usr/local/bin/g2g

echo "✅ g2g installed successfully!"
echo ""
echo "How to use:"
echo "   1. cd into any of your Git repositories"
echo "   2. Run:   g2g"
echo "      or:   g2g \"Your commit message here\""
echo ""
echo "First time in a repo: it will guide you to set the GitHub SSH remote."
echo "After that, just run 'g2g' from anywhere inside the repo."