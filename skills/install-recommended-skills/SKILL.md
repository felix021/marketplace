---
name: install-recommended-skills
description: Install recommended third-party Claude Code plugins and skills. Use when setting up a new machine, installing/updating plugins (anthropics/skills, eze-is/web-access, tanweai/pua, anthropics/claude-plugins-official, obra/superpowers), or troubleshooting plugin issues.
user-invocable: true
argument-hint: "[init|update|list]"
---

# Install Recommended Skills

Third-party skills are installed via the Claude CLI plugin marketplace — no git submodules or symlinks needed.

## Registered Marketplaces & Plugins

| Marketplace | Source | Plugins |
|---|---|---|
| `claude-plugins-official` | anthropics/claude-plugins-official | `frontend-design`, `superpowers`, `skill-creator` |
| `anthropic-agent-skills` | anthropics/skills | `document-skills` |
| `pua-skills` | tanweai/pua | `pua` |
| `web-access` | eze-is/web-access | `web-access` |

## npm Global Packages

| Package | Description |
|---|---|
| `bun` | JavaScript runtime (dependency of claude-multi) |
| `claude-multi` | Manage multiple Claude Code instances with different configs |

## Usage

When invoked, determine the action from `$ARGUMENTS` (default: `init`):

- **init** — Add all marketplaces and install all plugins (for new machines)
- **update** — Update all plugins to latest versions
- **list** — List installed plugins and marketplaces

Run the appropriate setup script based on the OS:

**Linux/macOS:**
```bash
bash skills/install-recommended-skills/setup.sh <action>
```

**Windows (PowerShell):**
```powershell
.\skills\install-recommended-skills\setup.ps1 <action>
```

## Post-Install

After installing or updating plugins, run `/skill-vetter` on newly added skills to check for suspicious code or permission issues.
