# Marketplace — Agent Instructions

This repo is a personal Claude Code skills marketplace for `felix021`.

Install via: `claude plugin install felix021@felix021-skills`

## Structure

```
.claude-plugin/
  marketplace.json      # marketplace manifest — list of all plugins/skills
skills/
  <skill-name>/
    SKILL.md            # skill definition (frontmatter + instructions)
```

## How to add a skill

1. Create `skills/<skill-name>/SKILL.md` with this frontmatter:
   ```markdown
   ---
   name: skill-name
   description: When/why Claude should use this skill (this is the trigger)
   ---

   # Skill Title

   Instructions for Claude...
   ```

2. Register it in `.claude-plugin/marketplace.json` — add the path to the `skills` array:
   ```json
   "./skills/<skill-name>"
   ```

3. Commit both files.

## SKILL.md frontmatter fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Skill identifier, matches directory name |
| `description` | yes | Trigger description — when Claude invokes this skill |
| `version` | no | Semantic version |
| `license` | no | License type |
| `argument-hint` | no | Hint shown to user, e.g. `<query>` |
| `allowed-tools` | no | Restrict which tools the skill can use |
