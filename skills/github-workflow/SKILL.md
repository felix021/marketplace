---
name: github-workflow
description: |
  AI-driven GitHub issue and PR automation — full lifecycle from triage to delivery.
  Subcommands: [triage] scans open issues, labels, and prioritizes; [solve] picks an issue
  and drives it through plan → implement → review → fix → confirm with a label-based state
  machine; [review] reviews incoming PRs with structured feedback; [respond] addresses PR
  review comments and pushes fixes; [status] shows a dashboard of all tracked work.
  Trigger on: "solve github issues", "triage issues", "review PRs", "handle open issues",
  "process github backlog", "respond to PR reviews", "check issue status", "work on issue #N",
  "implement #N", "fix #N", or any request involving automated GitHub issue/PR workflows.
  Also trigger when used with /loop for recurring automation.
argument-hint: "[triage|solve|review|respond|status] [issue/PR number or range]"
---

# github-workflow — AI-Driven GitHub Automation

End-to-end workflow that turns GitHub issues into tested PRs, reviews incoming PRs, and
keeps humans in the loop via notifications. Designed for recurring automation (works with
`/loop`) or one-shot execution.

```
  ┌─────────┐     ┌─────────────────────────────────────────────┐
  │ triage  │────▶│  solve (label-driven state machine)         │
  │         │     │  ai:plan → ai:impl → ai:review ────┐       │
  │         │     │                         ▲           │       │
  │         │     │                      ai:fix ◀───────┘       │
  │         │     │                         (max 3 rounds)      │
  │         │     │                                ──▶ ai:confirm│
  └────┬────┘     └─────────────────────────────────────────────┘
       │                                                    │
       │          ┌──────────┐                              │
       │          │ review   │◀─────────────────────────────┘
       │          │ respond  │
       │          └──────────┘
       └──────────▶ status dashboard
```

## Safety Principles

These constraints exist because automated actions on shared repos are hard to reverse and
visible to collaborators. The skill is designed to be a productive assistant, not an
autonomous operator.

1. **Never auto-close issues** — use labels to track state, human closes after confirming
2. **Never auto-merge PRs** unless dual-agent consensus (claude-glm approves) — otherwise
   mark as ready and notify the human
3. **Never force-push** — always create new commits for fixes
4. **Always notify** — every meaningful state change gets a notification
5. **Human gates** — architecture decisions, breaking changes, CI/CD config, and ambiguous
   requirements always pause and ask (even with dual-agent consensus)
6. **Dual-agent merge = issue stays open** — `ai:human-confirm` tag ensures human reviews

## Prerequisites

```bash
# required
gh --version    # GitHub CLI, authenticated
git --version

# optional (for AI pair review)
claude-glm --version   # GLM-powered Claude instance for cross-model review

# optional (for notifications)
# feishu-notify skill OR telegram-notify skill OR any notification channel
```

## AI Pair Review (claude-glm)

If `claude-glm` is available locally (a Claude-compatible CLI powered by 智谱GLM), the
workflow gains a **dual-agent consensus** mode. Two independent AI models review each other's
work, catching blind spots and enabling higher autonomy.

**Read `references/ai-pair-review.md` for full protocols** (discussion prompts, review
prompts, JSON schemas). Summary below:

```bash
# Detection
command -v claude-glm &>/dev/null && GLM_AVAILABLE=true
```

| Phase | Without claude-glm | With claude-glm |
|-------|-------------------|-----------------|
| **Ambiguous requirements** | Wait for human | Discuss with GLM first; consensus → proceed; disagree → escalate |
| **Code review** | Label `ai:review`, wait | GLM reviews diff; LGTM → can merge PR |
| **PR merge** | Never auto-merge | Can merge if GLM approves — tag issue `ai:human-confirm` |

**Key rule:** Even with consensus, issue stays open with `ai:human-confirm` label. Human
removes the tag after confirming. Never auto-close, never merge PRs touching CI/secrets.

## Repo Detection

```bash
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)
```

If this fails, ask the user for the repo. All `gh` commands below use `--repo $REPO`.

## Labels

All labels use the `ai:` prefix. Create them idempotently:

```bash
for label in ai:ready ai:needs-clarification ai:human-confirm \
             ai:plan ai:impl ai:review ai:fix ai:confirm; do
  gh label create "$label" --repo $REPO 2>/dev/null || true
done
```

| Label | Purpose |
|-------|---------|
| `ai:ready` | Triaged and ready for AI to pick up |
| `ai:needs-clarification` | AI needs more info before proceeding |
| `ai:human-confirm` | AI agents agreed and acted — human please confirm |
| `ai:plan` | Solve state: needs planning |
| `ai:impl` | Solve state: plan approved, ready to build |
| `ai:review` | Solve state: implementation done, needs review |
| `ai:fix` | Solve state: review found issues, needs fixes |
| `ai:confirm` | Solve state: review passed, user should confirm |

---

## Subcommand: `triage`

Scan open issues, categorize them, apply labels, and produce a prioritized work queue.

### Step 1: Fetch Open Issues

```bash
gh issue list --repo $REPO --state open --limit 50 --json number,title,body,labels,assignees,createdAt,comments
```

### Step 2: Categorize Each Issue

For each issue, determine:

| Field | How to decide |
|-------|--------------|
| **Type** | `bug`, `feature`, `docs`, `refactor`, `question` — infer from title + body |
| **Complexity** | `trivial` (typo/config), `small` (single file), `medium` (multi-file), `large` (multi-module/architecture) |
| **AI-solvable** | Can an AI agent resolve this without human judgment? `yes` / `needs-clarification` / `no` |
| **Priority** | `P0` (crash/security), `P1` (broken feature), `P2` (enhancement), `P3` (nice-to-have) |

### Step 3: Apply Labels

For issues missing labels, apply them:

```bash
# apply triage label + initial workflow state
gh issue edit $NUMBER --repo $REPO --add-label "ai:ready" --add-label "ai:plan"
```

For issues needing clarification:

```bash
gh issue edit $NUMBER --repo $REPO --add-label "ai:needs-clarification"
```

### Step 4: Output Summary

Present a table sorted by priority:

```
## Triage Summary — $REPO

| # | Title | Type | Complexity | AI-Solvable | Priority |
|---|-------|------|-----------|-------------|----------|
| 42 | Crash on startup | bug | small | yes | P0 |
| 38 | Add dark mode | feature | medium | yes | P2 |
| 35 | Explain config format | question | trivial | no | P3 |

Ready to solve: 5 issues
Need clarification: 2 issues
Need human: 1 issue
```

### Step 5: Notify

Send a triage summary via the notification channel (see Notification section below).

---

## Subcommand: `solve`

Pick an issue (or accept a specified issue number) and drive it through a **label-based state
machine**: plan → implement → review → fix → confirm.

### Phase Detection

When given an issue number, auto-detect the current phase before doing anything:

```bash
LABELS=$(gh issue view $NUMBER --repo $REPO --json labels -q '.labels[].name' | tr '\n' ',')
```

- Has `ai:plan` or no workflow label → Phase 1 (Plan)
- Has `ai:impl` → Phase 2 (Implement)
- Has `ai:review` → Phase 3 (Review)
- Has `ai:fix` → Phase 4 (Fix)
- Has `ai:confirm` → Phase 5 (Confirm)

Jump directly to the detected phase. Never restart from Phase 1 if the issue is already
further along.

### Issue Selection

If no issue number given, pick the highest-priority `ai:ready` issue:

```bash
gh issue list --repo $REPO --state open --label "ai:ready" --limit 5 --json number,title,body,labels
```

Read the full issue:

```bash
gh issue view $NUMBER --repo $REPO --json title,body,comments,labels
```

### Workflow State

Track session-specific state so the workflow survives context compaction and can be resumed:

```bash
mkdir -p .claude/workflow
cat > .claude/workflow/issue-$NUMBER.json <<EOF
{
  "issue": $NUMBER,
  "branch": "<branch-name>",
  "worktree": "<worktree-path>",
  "base_sha": "$(git rev-parse HEAD)",
  "review_round": 0
}
EOF
```

Update `review_round` each time Phase 3 runs. Read this file at the start of any phase to
recover context. The `base_sha` is captured once when the worktree is created — this is the
commit to diff against for all reviews.

### Spec Shortcut

Before entering Phase 1, check if the issue body already contains a structured spec (look
for headings like `## Design`, `## Tasks`, `## Summary`, or a file change table). If the
issue is already well-specified, skip brainstorming and go straight to
`superpowers:writing-plans`. Not every issue needs a full brainstorm cycle.

---

### Phase 1: Plan (ai:plan)

**Entry:** Issue exists with `ai:plan` label (or no workflow label yet).

1. Read the issue: `gh issue view $NUMBER --repo $REPO`
2. If the issue lacks a plan/spec, use the `superpowers:brainstorming` skill to explore the
   design with the user
3. Once design is approved, use `superpowers:writing-plans` to create a detailed
   implementation plan
4. Save spec and plan to `docs/superpowers/specs/` and `docs/superpowers/plans/`
5. Comment on the issue with a summary of the plan
6. Update label:
   ```bash
   gh issue edit $NUMBER --repo $REPO --remove-label ai:plan --add-label ai:impl
   ```

**If the issue is ambiguous and claude-glm is available:**
Run the Requirements Discussion Protocol (see `references/ai-pair-review.md`). If both
agents reach consensus, proceed. If they disagree, post both interpretations, label
`ai:needs-clarification`, notify the human, and stop.

**Exit criteria:** Spec + plan committed, issue labeled `ai:impl`.

---

### Phase 2: Implement (ai:impl)

**Entry:** Issue has `ai:impl` label with an approved plan.

1. Capture `base_sha` with `git rev-parse HEAD` — this is the diff base for all future
   reviews
2. Create a git worktree using `superpowers:using-git-worktrees`
   ```bash
   BRANCH="ai/issue-${NUMBER}"
   ```
3. Write workflow state file (see Workflow State section above)
4. Use `superpowers:subagent-driven-development` to execute the plan:
   - Dispatch one sub-agent per task
   - Run spec compliance review after each task
   - Run code quality review after each task
   - Fix issues found in reviews before moving to next task
5. After all tasks complete, run full verification (auto-detect language):
   - Go: `go build ./... && go vet ./... && go test ./... -race`
   - Node: `npm run build && npm test`
   - Python: `python -m pytest`
   - Rust: `cargo build && cargo test`
6. Commit using conventional commit format:
   ```bash
   git add {changed files}
   git commit -m "$(cat <<'EOF'
   fix: {concise description} (#$NUMBER)

   {Brief explanation of what was changed and why}

   Closes #$NUMBER

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
7. Comment on the issue with implementation summary (files changed, test results)
8. Update label:
   ```bash
   gh issue edit $NUMBER --repo $REPO --remove-label ai:impl --add-label ai:review
   ```

**Exit criteria:** All tasks done, tests pass, issue labeled `ai:review`.

---

### Phase 3: Review (ai:review)

**Entry:** Issue has `ai:review` label.

Read workflow state to get `base_sha` and `review_round`. Increment `review_round`.

**Review loop guard:** If `review_round > 3`, stop the loop. Post a comment on the issue
listing all unresolved findings across rounds, label as `ai:confirm`, and notify the user
to make a judgment call. Infinite loops waste tokens and usually mean the reviewer is
nitpicking or the issues are subjective.

Review is a two-stage process: self-review first (cheap, catches obvious issues), then
peer review by claude-glm after push (independent model, catches blind spots).

#### Stage 1: Self-Review (always)

1. Run `superpowers:code-reviewer` yourself against the changes:
   - Use the review prompt template below with `base_sha` from workflow state
   - Auto-detect build/test commands from project files

2. **If self-review finds issues** → fix them, commit, and re-run self-review. Do not
   proceed to Stage 2 until self-review passes. This keeps the diff clean for the peer
   reviewer.

3. Post self-review results to the issue as a comment (include round number):
   ```
   ## Self-Review (Round N)
   {review results}
   ```

#### Stage 2: Push + Peer Review (claude-glm)

4. Push the branch:
   ```bash
   git push -u origin "$BRANCH"
   ```

5. **If claude-glm is available** → invoke it for peer review:
   ```bash
   claude-glm -p "<review-prompt>" --output-format json 2>/dev/null
   ```
   Post peer review results to the issue as a comment.

   See `references/ai-pair-review.md` for full protocols.

6. **If claude-glm is unavailable** → skip peer review, proceed directly to verdict
   based on self-review.

#### Verdict

7. **If APPROVE (self-review passed, and peer review passed or was skipped):**
   ```bash
   gh issue edit $NUMBER --repo $REPO --remove-label ai:review --add-label ai:confirm
   ```
   If claude-glm peer-reviewed and approved (dual-agent consensus), optionally create and
   merge PR:
   ```bash
   gh pr create --repo $REPO --title "{type}: {description} (#$NUMBER)" --body "..."
   gh pr merge $PR_NUMBER --repo $REPO --squash --body "AI pair review passed (Claude + GLM)"
   gh issue edit $NUMBER --repo $REPO --add-label "ai:human-confirm"
   ```
   **Do NOT close the issue** — human removes `ai:human-confirm` after confirming.

8. **If REQUEST_CHANGES (peer review found issues):**
   ```bash
   gh issue edit $NUMBER --repo $REPO --remove-label ai:review --add-label ai:fix
   ```

**Exit criteria:** Review posted, label updated based on verdict.

#### Review Prompt Template

Auto-detect the project language and adapt the checklist:

```
You are a strict code reviewer. Review the changes on this branch.

Run: git diff <base_sha>..HEAD

## Review checklist
1. Build: <build command for detected language>
2. Tests: <test command for detected language>
3. Architecture: clean separation, no circular deps
4. Concurrency: data races, goroutine leaks, thread safety
5. Error handling: no swallowed errors
6. Resource leaks: goroutines, file descriptors, sockets
7. Test coverage: sufficient for new code

For each item: PASS, WARNING (with details), or FAIL (with details).
Overall: APPROVE or REQUEST_CHANGES with must-fix list.

Be harsh. Do not rubber-stamp.
```

For re-reviews (round > 1), prepend to the prompt:

```
This is re-review round <N> after fixes were applied.
Previous review found these issues: <list from previous review>
Verify each fix, then check for new issues introduced by the fixes.
```

---

### Phase 4: Fix (ai:fix)

**Entry:** Issue has `ai:fix` label with review feedback.

1. Read the review feedback from the latest issue comment
2. Dispatch a sub-agent to fix the issues:
   - Provide the exact review feedback (file paths, line numbers, what to fix)
   - Sub-agent fixes, runs tests, commits
3. Run full verification again
4. Comment on the issue confirming fixes applied
5. Update label back to `ai:review`:
   ```bash
   gh issue edit $NUMBER --repo $REPO --remove-label ai:fix --add-label ai:review
   ```
6. **Go back to Phase 3** (re-review by external reviewer)

**Exit criteria:** Fixes committed, tests pass, issue labeled `ai:review`.

---

### Phase 5: Confirm (ai:confirm)

**Entry:** Issue has `ai:confirm` label (review passed).

1. Push and create PR (if not already done in Phase 3 via dual-agent merge):
   ```bash
   git push -u origin "$BRANCH"
   gh pr create --repo $REPO \
     --title "{type}: {description} (#$NUMBER)" \
     --body "$(cat <<'EOF'
   ## Summary

   Resolves #$NUMBER

   {1-3 bullet points describing the changes}

   ## Changes

   {List of changed files with brief descriptions}

   ## Verification

   - [ ] Compile check passes
   - [ ] Tests pass
   - [ ] {Issue-specific verification steps}

   ## Review History

   {Number of review rounds, summary of findings and fixes}

   ---
   Generated by AI agent — human review required.
   EOF
   )"
   ```

2. Notify the user that work is ready for confirmation:
   - Use `felix021:feishu-notify` skill if available
   - Include: issue link, PR link, branch name, summary of changes, review round count

3. Present merge options to the user:
   - Merge branch to main: `cd <project-root> && git merge <branch>`
   - Merge via PR on GitHub

4. After merge, clean up:
   - Remove worktree: `git worktree remove <worktree-path>`
   - Delete workflow state: `rm .claude/workflow/issue-$NUMBER.json`
   - Close issue: `gh issue close $NUMBER --repo $REPO`

**Exit criteria:** User confirms. Branch merged, worktree cleaned, issue closed.

---

## Subcommand: `review`

Review an incoming PR (from a human or another agent).

### Step 1: Fetch PR

```bash
# If no number given, list open PRs
gh pr list --repo $REPO --state open --json number,title,author,headRefName,createdAt

# Read specific PR
gh pr view $NUMBER --repo $REPO --json title,body,files,commits,comments,reviews
gh pr diff $NUMBER --repo $REPO
```

### Step 2: Analyze Changes

For each changed file:
1. Read the full file (not just the diff) to understand context
2. Check for:
   - Correctness — does the code do what the PR claims?
   - Security — OWASP top 10, injection risks, hardcoded secrets
   - Style — consistency with surrounding code
   - Tests — are changes covered? Are new edge cases handled?
   - Performance — obvious regressions (N+1 queries, unbounded loops)

### Step 3: Post Review

```bash
gh pr review $NUMBER --repo $REPO --comment --body "$(cat <<'EOF'
## AI Review

### Summary
{One paragraph assessment}

### Findings

**Issues (must fix):**
- [ ] **I-1**: {file}:{line} — {problem and suggested fix}

**Suggestions (nice to have):**
- [ ] **S-1**: {file}:{line} — {suggestion}

**Positive:**
- {What's done well — reinforce good patterns}

### Verdict
{LGTM / Approve with suggestions / Request changes}

---
Automated review — human reviewer should verify these findings.
EOF
)"
```

For specific line comments:

```bash
gh api repos/$REPO/pulls/$NUMBER/comments -f body="{comment}" -f path="{file}" -f line={line} -f side="RIGHT" -f commit_id="$(gh pr view $NUMBER --json headRefOid -q '.headRefOid' --repo $REPO)"
```

### Step 4: Notify

Notify the PR author about the review findings.

---

## Subcommand: `respond`

Address review feedback on a PR the agent created.

### Step 1: Read Review Comments

```bash
gh pr view $NUMBER --repo $REPO --json reviews,comments
gh api repos/$REPO/pulls/$NUMBER/comments --jq '.[] | {id, body, path, line, created_at, user: .user.login}'
```

### Step 2: Categorize Feedback

For each comment:
- **Actionable fix**: Code change needed → implement it
- **Question**: Needs a reply → answer in the PR thread
- **Disagreement**: Agent thinks the reviewer is wrong → explain reasoning in the thread,
  but ultimately defer to the human
- **Out of scope**: Related but not part of this PR → note it, suggest a follow-up issue

### Step 3: Implement Fixes

For each actionable fix:
1. Make the code change
2. Commit with reference to the review comment

```bash
git commit -m "fix: address review feedback on #$NUMBER

- {description of fix 1}
- {description of fix 2}
"
git push
```

### Step 4: Reply to Comments

Reply to each review comment:

```bash
gh api repos/$REPO/pulls/$NUMBER/comments/$COMMENT_ID/replies -f body="{reply}"
```

### Step 5: Request Re-review

```bash
gh pr comment $NUMBER --repo $REPO --body "$(cat <<'EOF'
Review feedback addressed in {commit SHA}.

**Changes made:**
- {list of changes}

**Questions answered:**
- {list of replies}

Ready for re-review.
EOF
)"
```

Notify the reviewer.

---

## Subcommand: `status`

Dashboard of all AI-tracked work in the repo.

```bash
# Gather data
gh issue list --repo $REPO --label "ai:plan" --state open --json number,title
gh issue list --repo $REPO --label "ai:impl" --state open --json number,title
gh issue list --repo $REPO --label "ai:review" --state open --json number,title
gh issue list --repo $REPO --label "ai:fix" --state open --json number,title
gh issue list --repo $REPO --label "ai:confirm" --state open --json number,title
gh issue list --repo $REPO --label "ai:needs-clarification" --state open --json number,title
gh pr list --repo $REPO --state open --json number,title,headRefName,reviews
```

Output a grouped table: Plan → Implement → Review → Fix → Confirm → Needs Clarification,
with issue numbers, titles, linked PRs, and review status.

---

## Issue Comment Convention

Every phase transition should be documented with an issue comment:
- **Plan phase:** Summary of the plan, link to spec/plan files
- **Impl phase:** Files changed, test results, verification output
- **Review phase:** Full review results with round number (per-item verdicts + overall)
- **Fix phase:** What was fixed, re-verification results
- **Confirm phase:** Final status, ready to merge

---

## Notification

Detection order: feishu-notify skill → lark-im skill → Telegram (env vars) → gh comment.

Notify on: triage complete, PR created, review posted, feedback addressed, blocked, errors.
Do NOT notify on: issue picked up (too noisy), routine status checks.

---

## Recurring Mode (with /loop)

When invoked via `/loop`, the skill runs a smart cycle:

```
/loop 30m github-workflow triage
/loop 1h github-workflow solve
```

In recurring mode:
- `triage` only processes issues created/updated since last run
- `solve` picks one issue per cycle (to avoid overwhelming reviewers)
- Skips if no actionable work found (no noisy "nothing to do" notifications)
- Deduplicates: won't re-triage already-labeled issues or re-solve in-progress ones

---

## Edge Cases

- **Issue already has a PR**: Skip in `solve`, mention in `status`
- **PR has merge conflicts**: Attempt rebase; if it fails, notify human
- **CI fails after PR creation**: Read CI logs, attempt fix, push new commit; if 2 attempts
  fail, notify human with error details
- **Rate limiting**: If `gh` returns 403/429, back off and notify human
- **Repo has no issues**: Report clean state, skip
- **Issue references other issues**: Note dependencies in PR body, don't auto-resolve deps
- **Large/architecture issues**: Label as `ai:needs-clarification`, post a proposed approach
  as a comment, and wait for human approval before implementing

---

## Quick Start

```bash
# Triage all open issues
github-workflow triage

# Work on a specific issue (auto-detects phase)
github-workflow solve 9

# Work on the highest-priority ready issue
github-workflow solve

# Review an incoming PR
github-workflow review 15

# Respond to review feedback on a PR
github-workflow respond 15

# Show status dashboard
github-workflow status

# Recurring automation
/loop 30m github-workflow triage
/loop 1h github-workflow solve
```
