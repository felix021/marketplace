#!/usr/bin/env bash
# Install recommended Claude Code plugins and npm packages.
# Usage:
#   setup.sh init   — add marketplaces and install all plugins
#   setup.sh update — update all plugins to latest versions
#   setup.sh list   — list installed plugins and marketplaces
set -euo pipefail

# Marketplace definitions: name=url
declare -A MARKETPLACES=(
  [claude-plugins-official]=https://github.com/anthropics/claude-plugins-official.git
  [anthropic-agent-skills]=https://github.com/anthropics/skills.git
  [pua-skills]=https://github.com/tanweai/pua.git
  [web-access]=https://github.com/eze-is/web-access.git
)

# Plugin definitions: plugin@marketplace
PLUGINS=(
  frontend-design@claude-plugins-official
  superpowers@claude-plugins-official
  skill-creator@claude-plugins-official
  document-skills@anthropic-agent-skills
  pua@pua-skills
  web-access@web-access
)

# CLI tools (installed separately from plugins)
CLI_TOOLS=(
  rtk
)

# npm global packages
NPM_PACKAGES=(
  bun
  claude-multi
)

# Install a single CLI tool
install_cli_tool() {
  local tool="$1"
  case "$tool" in
    rtk)
      # Verify not already installed (and not the wrong rtk)
      if command -v rtk &>/dev/null && rtk gain &>/dev/null 2>&1; then
        echo "  Skipping: rtk (already installed, $(rtk --version 2>/dev/null || echo 'version unknown'))"
        return 0
      fi
      echo "  Installing: rtk (Rust Token Killer)"
      curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh 2>&1 || {
        echo "  WARNING: rtk install failed"; return 1
      }
      # Verify correct rtk was installed
      if ! rtk gain &>/dev/null 2>&1; then
        echo "  WARNING: rtk installed but 'rtk gain' failed — may be wrong package (Rust Type Kit)"
        return 1
      fi
      # Set up global hook (auto-patch settings.json)
      rtk init -g --auto-patch 2>&1 || echo "  WARNING: rtk init -g failed"
      ;;
    *)
      echo "  Unknown CLI tool: $tool"
      ;;
  esac
}

cmd_init() {
  echo "Adding marketplaces..."
  for name in "${!MARKETPLACES[@]}"; do
    url="${MARKETPLACES[$name]}"
    echo "  Adding: $name ($url)"
    claude plugin marketplace add "$url" 2>&1 || echo "  (may already exist)"
  done

  echo ""
  echo "Installing plugins..."
  for plugin in "${PLUGINS[@]}"; do
    echo "  Installing: $plugin"
    claude plugin install "$plugin" 2>&1 || echo "  WARNING: Failed to install $plugin"
  done

  echo ""
  echo "Installing CLI tools..."
  for tool in "${CLI_TOOLS[@]}"; do
    install_cli_tool "$tool"
  done

  echo ""
  echo "Installing npm packages..."
  for pkg in "${NPM_PACKAGES[@]}"; do
    if command -v "$pkg" &>/dev/null || npm list -g "$pkg" &>/dev/null; then
      echo "  Skipping: $pkg (already installed)"
    else
      echo "  Installing: $pkg"
      npm install -g "$pkg" 2>&1 || echo "  WARNING: Failed to install $pkg"
    fi
  done

  echo ""
  echo "Done. Installed plugins:"
  claude plugin list
}

cmd_update() {
  echo "Updating marketplaces..."
  claude plugin marketplace update 2>&1 || true

  echo ""
  echo "Updating plugins..."
  for plugin in "${PLUGINS[@]}"; do
    name="${plugin%%@*}"
    echo "  Updating: $name"
    claude plugin update "$name" 2>&1 || echo "  ($name: already up to date or not installed)"
  done

  echo ""
  echo "Updating npm packages..."
  for pkg in "${NPM_PACKAGES[@]}"; do
    echo "  Updating: $pkg"
    npm update -g "$pkg" 2>&1 || echo "  ($pkg: already up to date or not installed)"
  done

  echo ""
  echo "Done."
}

cmd_list() {
  echo "Configured marketplaces:"
  claude plugin marketplace list
  echo ""
  echo "Installed plugins:"
  claude plugin list
}

case "${1:-help}" in
  init)   cmd_init   ;;
  update) cmd_update ;;
  list)   cmd_list   ;;
  *)
    echo "Usage: $0 {init|update|list}"
    echo "  init   — add marketplaces + install all plugins (for new machine)"
    echo "  update — update all plugins to latest versions"
    echo "  list   — show installed plugins and marketplaces"
    exit 1
    ;;
esac
