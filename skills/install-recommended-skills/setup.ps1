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

$CliTools = @("rtk")

$NpmPackages = @(
  "bun"
  "claude-multi"
)

function Install-CliTool {
  param([string]$Tool)
  switch ($Tool) {
    "rtk" {
      $rtkCmd = Get-Command rtk -ErrorAction SilentlyContinue
      if ($rtkCmd) {
        # Verify it's the correct rtk (Token Killer, not Type Kit)
        try {
          rtk gain 2>&1 | Out-Null
          Write-Host "  Skipping: rtk (already installed)"
          return
        } catch {
          Write-Host "  WARNING: rtk found but 'rtk gain' failed — may be wrong package"
        }
      }
      Write-Host "  Installing: rtk (Rust Token Killer)"
      try {
        Invoke-RestMethod -Uri "https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh" | Out-Null
        # On Windows, prefer cargo install
        cargo install --git https://github.com/rtk-ai/rtk 2>&1 | Out-Null
        if (-not (rtk gain 2>&1)) {
          throw "rtk gain failed after install"
        }
        rtk init -g --auto-patch 2>&1 | Out-Null
      } catch {
        Write-Host "  WARNING: rtk install failed: $_"
      }
    }
    default { Write-Host "  Unknown CLI tool: $Tool" }
  }
}

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
  Write-Host "Installing CLI tools..."
  foreach ($tool in $CliTools) {
    Install-CliTool -Tool $tool
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
