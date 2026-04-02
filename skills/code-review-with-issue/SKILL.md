---
name: code-review-with-issue
description: |
  Isolated code review that posts findings as a GitHub issue (or local file as fallback) and
  optionally verifies fixes. Creates a detached git worktree for clean review, dispatches
  superpowers:code-reviewer, posts sanitized results, then reports back. Later, when the user
  says "check the fix", "verify the issues", or "check issue replies", re-inspects the fix in
  a new worktree: if fixes are satisfactory, posts END-OF-REVIEW and closes; otherwise reopens
  with comments. Use this whenever the user asks to "do a code review", "review this phase",
  "review and create issue", "check code quality", or wants to review recent commits before
  merging. Also triggers on "verify fixes", "check if issues are resolved", "reopen if needed"
  — the full review-to-verification lifecycle.
---

# Code Review with Issue

Two-phase workflow: **Review → Verify Fix**.

Results are stored as GitHub issues when possible, or local files as fallback.

## Worktree Directory

Do NOT create worktrees inside the project working directory — they pollute `git status` and interfere with the user's work.

Instead, create worktrees in the system temp directory with unique names:

```bash
# Derive a unique worktree name from project + purpose + random suffix
WT_PATH=$(mktemp -d "${TMPDIR:-/tmp}/review-XXXXXXXX")
# Result on Linux/macOS: /tmp/review-a3fK9x2m
# Result on Windows (Git Bash): /tmp/review-a3fK9x2m (mapped to %TEMP%)
```

Each review/verification gets its own unique directory. Clean up with `git worktree remove` when done.

## Phase 1: Review

### Step 1: Determine Scope

```bash
git log --oneline -30
git rev-parse HEAD
```

Identify the review range:

- **Auto-detect:** Look for boundary commits (e.g., `docs: add Phase N plan`). Plan doc commit = `BASE_SHA`, HEAD = `HEAD_SHA`.
- **User-specified:** Phase name, commit count, or explicit SHAs.
- **Full history:** Root commit as BASE_SHA for small projects.

If ambiguous, ask the user. Collect diff stats: `git diff --stat $BASE_SHA..HEAD`.

### Step 2: Detect Output Mode

Check whether GitHub issue creation is available:

```bash
git remote get-url origin   # Must be a github.com remote
which gh                     # gh CLI must be installed
gh auth status               # Must be authenticated
```

**All three pass → GitHub mode.** Results go to a GitHub issue; Phase 2 can verify via issue replies.

**Any fail → Local file fallback.** Results go to `docs/superpowers/review/{phase-name}.md`; Phase 2 verifies by reading the latest commit diff. Note which mode was selected — it affects all subsequent steps.

### Step 3: Create Isolated Worktree

```bash
REVIEW_WT=$(mktemp -d "${TMPDIR:-/tmp}/review-XXXXXXXX")
git worktree add "$REVIEW_WT" HEAD --detach
```

**All file reads must use `$REVIEW_WT` paths.** This is the isolation guarantee — the main directory's uncommitted changes must not influence the review. Multiple reviews can run concurrently without collision.

### Step 4: Dispatch Code Reviewer

Use the Agent tool with `subagent_type: superpowers:code-reviewer`. Provide:

- What was implemented (from commit messages + diff stats)
- Requirements (plan/spec doc paths in the worktree)
- Git range: BASE_SHA..HEAD_SHA
- Key files to review (worktree paths)
- Test command: `cd $REVIEW_WT && npm install && npm test`
- **Stress:** "Read ALL files from `$REVIEW_WT/`, NOT the main working directory"

### Step 5: Sanitize & Save Results

Before saving anywhere, **sanitize** the review content:

- Replace real usernames, emails, API keys, tokens with obvious placeholders: `user_id`, `api_key_placeholder`, `user@example.com`
- Replace user-specific paths: `/home/{actual_user}/` → `/home/{user}/`, `C:\Users\{name}\` → `C:\Users\{user}\`
- Keep relative project paths intact (e.g., `src/config.ts:43`)
- Remove any environment variable values from config examples

**If GitHub mode:**

```bash
gh issue create --repo {owner/repo} \
  --title "{Phase} Code Review: {N} Issues to Fix" \
  --body "$(cat <<'EOF'
## Context

{What was reviewed, commit range, scope}

---

## Issues

### I-1. {Issue title}
- **File:** `src/path.ts:line`
- **Problem:** {description}
- **Fix:** {recommendation}

{repeat for each Critical/Important issue}

### Minor

- {Minor issue 1}
- {Minor issue 2}

---

## Assessment

**Ready to merge:** {Yes / With fixes / No}

{1-2 sentence reasoning}
EOF
)"
```

Include Critical, Important, and Minor issues. Number them (I-1, I-2, C-1 for critical) for cross-referencing.

**If local file fallback:**

Write the same content to `docs/superpowers/review/{phase-name}.md` with a YAML-style header:

```markdown
# Code Review: {Phase Name}

**Date:** {date}
**Base SHA:** {sha}
**Head SHA:** {sha}
**Scope:** {N} commits, {M} files, +{X} lines

{rest of the review content}
```

### Step 6: Clean Up & Report

```bash
git worktree remove "$REVIEW_WT"
```

Report to the user:

```
{GitHub mode:  Issue created: {owner/repo}#{number}}
{Local mode:   Review saved: docs/superpowers/review/{phase-name}.md}
- {N} Critical, {M} Important, {K} Minor
- Assessment: {verdict}
```

**Then stop and wait for the user.** The user may:
- Ask another agent to fix the issues (that agent will reply on the issue / commit fixes)
- Ask you to verify the fixes (→ Phase 2)
- Close the issue themselves

---

## Phase 2: Verify Fix

Triggered when the user says "check the fix", "verify issue replies", "check if #N is resolved", etc.

### Step 1: Read Prior Review

**GitHub mode:**

```bash
gh api repos/{owner/repo}/issues/{number}/comments --jq '.[].body'
gh api repos/{owner/repo}/issues/{number} --jq '.state'
```

**Local mode:** Read `docs/superpowers/review/{phase-name}.md` and check `git log` for fix commits since the review.

Understand what the fixing agent claims to have done.

### Step 2: Create Worktree at Fix Commit

```bash
git log --oneline -5  # find the fix commit
VERIFY_WT=$(mktemp -d "${TMPDIR:-/tmp}/verify-XXXXXXXX")
git worktree add "$VERIFY_WT" {fix-commit} --detach
```

### Step 3: Verify Each Issue

Read the actual code for each issue. For each one:

- Does the fix exist in the code?
- Does it correctly address the root cause?
- Is it consistent with the surrounding code style?

Also run tests: `cd "$VERIFY_WT" && npm install && npm test`

### Step 4: Post Verdict

**If all issues are satisfactorily fixed:**

**GitHub mode:**

```bash
gh issue comment {number} --repo {owner/repo} --body "$(cat <<'EOF'
## END-OF-REVIEW

All {N} issues verified and confirmed fixed in commit {sha}.

{Optionally list each issue with one-line verification}
EOF
)"

gh issue close {number} --repo {owner/repo}
```

**Local mode:** Append to the review file:

```
## Verification ({date})

All {N} issues verified and confirmed fixed in commit {sha}.
END-OF-REVIEW
```

**If some issues are NOT fixed:**

**GitHub mode:**

```bash
gh issue comment {number} --repo {owner/repo} --body "$(cat <<'EOF'
## Verification Result

**{X} of {N} issues remain unresolved:**

### I-2. {Issue title} — NOT FIXED
- **Problem:** {what's still wrong}
- **Expected:** {what the fix should look like}

{repeat for each unfixed issue}

---

Please address the remaining issues and reply here when done.
EOF
)"
```

Then reopen if the issue was closed: `gh issue edit {number} --repo {owner/repo} --state open`

**Local mode:** Append to the review file with the unfixed items and "STATUS: REOPENED".

### Step 5: Clean Up & Report

```bash
git worktree remove "$VERIFY_WT"
```

Report to the user:

```
Verification of #{number} / {review-file}: {X} fixed, {Y} remain
{If all fixed: "All clear — END-OF-REVIEW mark posted, issue closed"}
{If issues remain: "Reopened with comments on unfixed items"}
```

---

## Edge Cases

- **No issues found:** Post a "LGTM" issue / review file with just the assessment. Skip issue creation if user prefers.
- **Tests fail in worktree:** Note as a review finding. Never silently ignore.
- **No plan/spec doc:** Review against commit messages and user's stated intent.
- **Worktree collision:** Remove existing worktree first, then recreate.
- **Issue already closed by fixer:** Reopen if verification fails, leave closed if all pass.
- **Partial fix (some fixed, new bugs introduced):** Comment with both — confirmed fixes + new findings as additional issues.
- **Local mode Phase 2:** Without issue comments, verification relies on git log + code inspection. No reopen mechanic — just update the review file and report to user.
