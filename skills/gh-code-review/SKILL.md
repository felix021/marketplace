---
name: gh-code-review
description: |
  GitHub-backed code review with an iterative reviewer-fixer loop. Two subcommands:
  [review] — reviewer inspects code, posts findings as a GitHub issue, and outputs a
  fixer prompt; [fix] — fixer resolves issues, updates the GitHub issue, and outputs
  a reviewer prompt. The cycle repeats until the reviewer posts END-OF-REVIEW.
  Trigger on "gh-code-review review", "gh-code-review fix", "review code and create issue",
  "fix the review issues", "verify fixes", or any code-review lifecycle request involving
  GitHub issues.
argument-hint: "[review|fix] [issue-number|range]"
---

# gh-code-review — Reviewer/Fixer Loop

Two-role iterative workflow backed by GitHub issues:

```
[review] → Reviewer inspects code → creates/updates issue → outputs fixer prompt
    ↑                                                               ↓
    └── Reviewer satisfied → END-OF-REVIEW ← Fixer updates issue ← [fix]
```

## Roles

| Role | Subcommand | Responsibility |
|------|-----------|---------------|
| **Reviewer** | `review` | Inspect code, post findings to issue, output fixer prompt or END-OF-REVIEW |
| **Fixer** | `fix` | Resolve issues in code, update issue, output reviewer prompt |

## Worktree Directory

Do NOT create worktrees inside the project working directory. Use system temp:

```bash
WT_PATH=$(mktemp -d "${TMPDIR:-/tmp}/gh-review-XXXXXXXX")
```

Clean up with `git worktree remove` when done.

## Sanitize Before Posting

Before writing to any GitHub issue, sanitize the content:

- Replace real usernames, emails, API keys, tokens with placeholders: `user_id`, `api_key_placeholder`, `user@example.com`
- Replace user-specific paths: `/home/{actual_user}/` → `/home/{user}/`
- Keep relative project paths intact (e.g., `src/config.ts:43`)
- Remove environment variable values from config examples

---

## Subcommand: `review`

### Step 1: Determine Scope

If an issue number is given, read the issue body to understand what was previously requested and skip to Step 4 (re-verification).

If no issue number:

```bash
git log --oneline -30
git rev-parse HEAD
```

Identify the review range:

- **Auto-detect:** Look for boundary commits (e.g., `docs: add Phase N plan`). Plan doc commit = `BASE_SHA`, HEAD = `HEAD_SHA`.
- **User-specified:** Phase name, commit count, or explicit SHAs.
- **Full history:** Root commit as BASE_SHA for small projects.

Collect diff stats: `git diff --stat $BASE_SHA..HEAD`.

### Step 2: Create Isolated Worktree

```bash
REVIEW_WT=$(mktemp -d "${TMPDIR:-/tmp}/gh-review-XXXXXXXX")
git worktree add "$REVIEW_WT" HEAD --detach
```

**All file reads must use `$REVIEW_WT` paths.**

### Step 3: Dispatch Code Reviewer

Use the Agent tool with `subagent_type: superpowers:code-reviewer`. Provide:

- What was implemented (from commit messages + diff stats)
- Requirements (plan/spec doc paths in the worktree)
- Git range: BASE_SHA..HEAD_SHA
- Key files to review (worktree paths)
- Test command: `cd $REVIEW_WT && npm install && npm test`
- **Stress:** "Read ALL files from `$REVIEW_WT/`, NOT the main working directory"

### Step 4: Post or Update GitHub Issue

**If new review (no issue number):**

```bash
gh issue create --repo {owner/repo} \
  --title "Code Review: {N} Issues to Fix" \
  --body "$(cat <<'EOF'
## Context

{What was reviewed, commit range, scope}

---

## Round 1 — Review

### I-1. {Issue title}
- **File:** `src/path.ts:line`
- **Problem:** {description}
- **Fix:** {recommendation}

{repeat for each issue}

### Minor

- {Minor issue 1}

---

## Assessment

**Ready to merge:** {Yes / With fixes / No}

{reasoning}
EOF
)"
```

**If re-verification (existing issue number):**

```bash
gh issue comment {number} --repo {owner/repo} --body "$(cat <<'EOF'
## Round {N} — Review

{Verify each previously reported issue: FIXED or NOT FIXED}

### New Findings

{Any new issues discovered during re-review, or "None"}

---

## Assessment

{Verdict}
EOF
)"
```

Number issues as I-1, I-2, C-1 (critical) for cross-referencing across rounds.

### Step 5: Decide — Loop or Close

**If all issues are fixed and no new findings:**

Post END-OF-REVIEW:

```bash
gh issue comment {number} --repo {owner/repo} --body "$(cat <<'EOF'
## END-OF-REVIEW

All issues verified and confirmed fixed across {N} rounds.

{One-line summary per issue confirming the fix}

Closing this review.
EOF
)"

gh issue close {number} --repo {owner/repo}
```

Clean up worktree:

```bash
git worktree remove "$REVIEW_WT"
```

Report to user: "All clear — END-OF-REVIEW posted, issue #{number} closed."

**If issues remain unfixed, output the fixer prompt (Step 6).**

### Step 6: Output Fixer Prompt

Clean up the review worktree:

```bash
git worktree remove "$REVIEW_WT"
```

Then output the following prompt for the fixer:

```
╔═══════════════════════════════════════════════════════════════╗
║ FIXER PROMPT — Round {N}                                      ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║ gh-code-review fix {issue-number}                             ║
║                                                               ║
║ Issue: {owner/repo}#{number}                                  ║
║ Unresolved issues: {X}                                        ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

**Then stop and wait.** The user runs the fixer prompt (possibly in another session or agent).

---

## Subcommand: `fix`

### Step 1: Read the GitHub Issue

```bash
gh issue view {number} --repo {owner/repo} --json title,body,comments
```

Parse the latest review round to identify all unresolved issues. Extract:

- Issue numbers (I-1, I-2, C-1, etc.)
- File paths and line numbers
- Problem descriptions and fix recommendations

### Step 2: Fix Each Issue

For each unresolved issue:

1. Read the referenced file
2. Understand the problem in context
3. Apply the fix as described in the review
4. Verify the fix is consistent with surrounding code style

Run tests after all fixes:

```bash
npm test
```

If tests fail, fix the failures before proceeding.

### Step 3: Commit Fixes

```bash
git add {fixed files}
git commit -m "fix: resolve review issues I-{N}, I-{M} from #{issue-number}

- I-{N}: {brief description of fix}
- I-{M}: {brief description of fix}

Refs: {owner/repo}#{issue-number}"
```

### Step 4: Update the GitHub Issue

```bash
gh issue comment {number} --repo {owner/repo} --body "$(cat <<'EOF'
## Round {N} — Fix

Commit: {sha}

### Fixes Applied

- **I-1:** {description of what was fixed} — `src/file.ts:{line}`
- **I-2:** {description of what was fixed} — `src/file.ts:{line}`

### Skipped / Partial

{List any issues that could not be fully fixed, with explanation, or "None"}

---

Tests: {PASS/FAIL}
EOF
)"
```

### Step 5: Output Reviewer Prompt

Output the following prompt for the reviewer:

```
╔═══════════════════════════════════════════════════════════════╗
║ REVIEWER PROMPT — Round {N+1}                                 ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║ gh-code-review review {issue-number}                          ║
║                                                               ║
║ Issue: {owner/repo}#{number}                                  ║
║ Fix commit: {sha}                                             ║
║ Fixes claimed: {X} of {Y}                                     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

**Then stop and wait.** The user runs the reviewer prompt (possibly in another session or agent).

---

## Edge Cases

- **No issues found (review):** Post a "LGTM" issue and immediately close with END-OF-REVIEW. No fixer prompt needed.
- **Tests fail in worktree:** Note as a review finding. Never silently ignore.
- **No plan/spec doc:** Review against commit messages and user's stated intent.
- **Fixer cannot fix an issue:** Mark as "Skipped / Partial" in the issue comment with explanation. Reviewer decides whether to accept or insist.
- **Issue already closed:** If reviewer closed it, fixer should not reopen — ask user instead. If closed by someone else, proceed with caution.
- **Partial fix with new bugs introduced:** Reviewer notes both confirmed fixes and new findings as additional issues.
- **Local file fallback:** If `gh` is unavailable, store review rounds in `docs/superpowers/review/{name}.md` instead of GitHub issues. The loop still works — prompts reference the file path instead of issue number.
