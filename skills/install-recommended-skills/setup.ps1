# Install recommended Claude Code plugins and npm packages (Windows PowerShell).
# Usage:
#   setup.ps1 init   — add marketplaces and install all plugins
#   setup.ps1 update — update all plugins to latest versions
#   setup.ps1 list   — list installed plugins and marketplaces

$ErrorActionPreference = "Stop"

$Marketplaces = @{
  "claude-plugins-official" = "https://github.com/anthropics/claude-plugins-official.git"
  "anthropic-agent-skills"  = "https://github.com/anthropics/skills.git"
  "pua-skills"              = "https://github.com/tanweai/pua.git"
  "web-access"              = "https://github.com/eze-is/web-access.git"
}

$Plugins = @(
  "frontend-design@claude-plugins-official"
  "superpowers@claude-plugins-official"
  "skill-creator@claude-plugins-official"
  "document-skills@anthropic-agent-skills"
  "pua@pua-skills"
  "web-access@web-access"
)

$NpmPackages = @(
  "bun"
  "claude-multi"
)

function Cmd-Init {
  Write-Host "Adding marketplaces..."
  foreach ($name in $Marketplaces.Keys) {
    $url = $Marketplaces[$name]
    Write-Host "  Adding: $name ($url)"
    try {
      claude plugin marketplace add $url 2>&1 | Out-Null
    } catch {
      Write-Host "  (may already exist)"
    }
  }

  Write-Host ""
  Write-Host "Installing plugins..."
  foreach ($plugin in $Plugins) {
    Write-Host "  Installing: $plugin"
    try {
      claude plugin install $plugin 2>&1 | Out-Null
    } catch {
      Write-Host "  WARNING: Failed to install $plugin"
    }
  }

  Write-Host ""
  Write-Host "Installing npm packages..."
  foreach ($pkg in $NpmPackages) {
    $already = Get-Command $pkg -ErrorAction SilentlyContinue
    if ($already) {
      Write-Host "  Skipping: $pkg (already installed)"
    } else {
      Write-Host "  Installing: $pkg"
      try {
        npm install -g $pkg 2>&1 | Out-Null
      } catch {
        Write-Host "  WARNING: Failed to install $pkg"
      }
    }
  }

  Write-Host ""
  Write-Host "Done. Installed plugins:"
  claude plugin list
}

function Cmd-Update {
  Write-Host "Updating marketplaces..."
  try { claude plugin marketplace update 2>&1 | Out-Null } catch {}

  Write-Host ""
  Write-Host "Updating plugins..."
  foreach ($plugin in $Plugins) {
    $name = $plugin.Split("@")[0]
    Write-Host "  Updating: $name"
    try {
      claude plugin update $name 2>&1 | Out-Null
    } catch {
      Write-Host "  ($name`: already up to date or not installed)"
    }
  }

  Write-Host ""
  Write-Host "Updating npm packages..."
  foreach ($pkg in $NpmPackages) {
    Write-Host "  Updating: $pkg"
    try {
      npm update -g $pkg 2>&1 | Out-Null
    } catch {
      Write-Host "  ($pkg`: already up to date or not installed)"
    }
  }

  Write-Host ""
  Write-Host "Done."
}

function Cmd-List {
  Write-Host "Configured marketplaces:"
  claude plugin marketplace list
  Write-Host ""
  Write-Host "Installed plugins:"
  claude plugin list
}

$cmd = if ($args.Count -gt 0) { $args[0] } else { "help" }

switch ($cmd) {
  "init"   { Cmd-Init   }
  "update" { Cmd-Update }
  "list"   { Cmd-List   }
  default {
    Write-Host "Usage: setup.ps1 {init|update|list}"
    Write-Host "  init   — add marketplaces + install all plugins (for new machine)"
    Write-Host "  update — update all plugins to latest versions"
    Write-Host "  list   — show installed plugins and marketplaces"
    exit 1
  }
}
