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

End-to-end workflow that turns GitHub issues into merged, deployed code. When `claude-glm`
is available, operates in full autonomy mode — dual-agent consensus replaces human gating
for most decisions (including merge, close, build, deploy). Humans are notified but not
blocked. Without `claude-glm`, falls back to human-in-the-loop mode. Designed for recurring
automation (works with `/loop`) or one-shot execution.

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

These constraints balance autonomous delivery with responsible operation.

1. **Never force-push** — always create new commits for fixes
2. **Always log decisions** — every decision and its reasoning goes to the Decision Log
3. **Always notify** — every meaningful state change gets a notification via available
   channels (feishu/lark, telegram, or gh comment as fallback)
4. **Dual-agent autonomy** — when `claude-glm` is available and both agents reach consensus,
   proceed without human approval for: merging PRs, closing issues, building, and deploying.
   Human is notified but does not gate.
5. **Hard human gates (even with dual-agent consensus):**
   - PRs touching CI/CD configs, secrets, or permissions
   - Changes to authentication/authorization systems
   - Database migrations that drop data
   - License or legal-sensitive changes
   These always pause and ask the human regardless of consensus.
6. **Single-agent mode (no claude-glm)** — behaves as before: mark as ready and wait for
   human to confirm/merge/deploy
7. **Disagreement escalation** — if the two agents cannot reach consensus after 2 rounds of
   discussion, escalate to human with both perspectives

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

## AI Pair Review (claude-glm) — Dual-Agent Autonomy

If `claude-glm` is available locally (a Claude-compatible CLI powered by 智谱GLM), the
workflow operates in **full autonomy mode**. Two independent AI models discuss and review
each other's work. When they agree, the workflow proceeds end-to-end without human
intervention — including merge, close, build, and deploy.

**Read `references/ai-pair-review.md` for full protocols** (discussion prompts, review
prompts, JSON schemas, decision logging). Summary below:

```bash
# Detection
command -v claude-glm &>/dev/null && GLM_AVAILABLE=true
```

| Phase | Without claude-glm | With claude-glm (consensus) |
|-------|-------------------|----------------------------|
| **Any question/decision** | Ask human | Discuss with GLM first; consensus → proceed; disagree → escalate |
| **Ambiguous requirements** | Wait for human | Discuss → consensus → proceed |
| **Code review** | Label `ai:review`, wait for human | GLM reviews diff; LGTM → merge PR |
| **PR merge** | Never auto-merge | Auto-merge on consensus |
| **Issue close** | Never auto-close | Auto-close after merge on consensus |
| **Build & deploy** | Notify human | Auto-build and deploy on consensus |

**Key rules:**
- All autonomous decisions are logged in the Decision Log (see below)
- Human is notified of all actions via available channels but does NOT gate them
- Hard human gates still apply (see Safety Principles)
- If agents disagree after 2 rounds, escalate to human

## Repo Detection

```bash
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)
```

If this fails, ask the user for the repo. All `gh` commands below use `--repo $REPO`.

## Labels

All labels use the `ai:` prefix. Create them idempotently:

```bash
for label in ai:ready ai:needs-clarification ai:human-confirm ai:autonomous \
             ai:plan ai:impl ai:review ai:fix ai:confirm; do
  gh label create "$label" --repo $REPO 2>/dev/null || true
done
```

| Label | Purpose |
|-------|---------|
| `ai:ready` | Triaged and ready for AI to pick up |
| `ai:needs-clarification` | AI needs more info before proceeding |
| `ai:human-confirm` | Single-agent mode: human must confirm before merge |
| `ai:autonomous` | Resolved end-to-end by dual-agent consensus (Claude + GLM) |
| `ai:plan` | Solve state: needs planning |
| `ai:impl` | Solve state: plan approved, ready to build |
| `ai:review` | Solve state: implementation done, needs review |
| `ai:fix` | Solve state: review found issues, needs fixes |
| `ai:confirm` | Solve state: review passed, user should confirm (single-agent only) |

---

## Decision Log

Every autonomous decision made by the dual-agent pair must be logged. This gives the human
a clear audit trail without requiring them to be in the loop.

### Where to log

1. **Issue comment** — post a structured decision note on the relevant issue
2. **Notification** — send a summary via available channels (feishu/lark, telegram)

### Decision note format

```markdown
## 🤖 Autonomous Decision

**Action:** {what was done — e.g., "Merged PR #42 to main", "Closed issue #38"}
**Consensus:** Claude ✅ + GLM ✅
**Reasoning:** {1-2 sentences on why both agents agreed}
**Reversible:** {yes/no — and how to reverse if yes}
**Notification sent:** {channel — e.g., "feishu", "telegram", "gh comment only"}

<details>
<summary>Discussion transcript</summary>

{Claude's position}
{GLM's response}
{Final agreement}
</details>
```

### When to notify human (even with consensus)

Use available notification channels (`felix021:feishu-notify` skill, telegram, etc.) for:

- **Always notify:** PR merged, issue closed, deploy triggered, build failure
- **Notify if notable:** architecture decisions, dependency changes, new APIs
- **Skip notification:** routine label changes, status checks, intermediate commits

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

**If claude-glm is available:**
Run the Discussion Protocol (see `references/ai-pair-review.md`) for any non-trivial
decision: requirements interpretation, design choices, scope questions. If both agents
reach consensus, proceed without human input and log the decision. If they disagree after
2 rounds, post both interpretations, label `ai:needs-clarification`, notify the human, and
stop.

**If claude-glm is NOT available:**
Ambiguous issues require human input — label `ai:needs-clarification` and wait.

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

   **With dual-agent consensus (claude-glm approved):** Full autonomous delivery —
   ```bash
   # Create and merge PR
   gh pr create --repo $REPO --title "{type}: {description} (#$NUMBER)" --body "..."
   gh pr merge $PR_NUMBER --repo $REPO --squash --body "AI pair review passed (Claude + GLM)"
   # Close the issue
   gh issue close $NUMBER --repo $REPO --comment "Resolved via dual-agent consensus. PR #$PR_NUMBER merged."
   # Log decision and notify human
   ```
   Post a Decision Log entry on the issue. Notify human via available channels.
   Then proceed to **Build & Deploy** (see below) if applicable.
   Skip Phase 5 entirely — no human confirmation needed.

   **Without claude-glm (single-agent):**
   ```bash
   gh issue edit $NUMBER --repo $REPO --remove-label ai:review --add-label ai:confirm
   ```
   Proceed to Phase 5 for human confirmation.

8. **If REQUEST_CHANGES (peer review found issues):**
   ```bash
   gh issue edit $NUMBER --repo $REPO --remove-label ai:review --add-label ai:fix
   ```

**Exit criteria:** Review posted, label updated based on verdict. With dual-agent consensus:
PR merged, issue closed, build/deploy triggered.

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

### Build & Deploy (dual-agent consensus only)

**Entry:** PR merged via dual-agent consensus in Phase 3.

When both agents agree the change is ready, trigger build and deploy automatically:

1. **Build verification** (on main after merge):
   ```bash
   git checkout main && git pull
   # Auto-detect and run build
   # Go: go build ./...
   # Node: npm run build
   # Python: python -m pytest
   # Rust: cargo build
   ```

2. **Deploy** (if the repo has a deploy mechanism):
   - Detect deploy method: `Makefile` targets, `deploy.sh`, GitHub Actions, etc.
   - Run the deploy command
   - Verify deployment succeeded (health check, smoke test)

3. **If build or deploy fails:**
   - Post failure details to the issue (reopen if closed)
   - Notify human immediately via feishu/telegram — this is a **hard escalation**
   - Do NOT retry deploy more than once

4. **Log & notify:**
   - Post Decision Log entry with build/deploy results
   - Notify human: "Issue #N resolved, PR merged, deployed successfully"

5. **Clean up:**
   - Remove worktree: `git worktree remove <worktree-path>`
   - Delete workflow state: `rm .claude/workflow/issue-$NUMBER.json`

---

### Phase 5: Confirm (ai:confirm) — Single-Agent Mode Only

**Entry:** Issue has `ai:confirm` label (review passed, but no claude-glm for consensus).

> **Note:** This phase is skipped entirely when dual-agent consensus is achieved in Phase 3.
> With claude-glm, the workflow goes directly from Phase 3 → Build & Deploy → done.

1. Push and create PR (if not already done):
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

4. After human approves and merge completes, clean up:
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

Detection order: `felix021:feishu-notify` skill → Telegram (env vars) → `gh` comment.

**Always notify on:** triage complete, PR merged, issue closed, deploy triggered,
deploy succeeded/failed, blocked/escalated, errors, any autonomous decision.
**Skip notification on:** issue picked up (too noisy), routine label changes, status checks.

In dual-agent autonomy mode, notifications serve as the human's **awareness channel** —
not a gate. The human can review decisions asynchronously and intervene if needed.

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
- **Large/architecture issues**: If claude-glm available, discuss approach with it — consensus
  → proceed; otherwise label `ai:needs-clarification` and wait for human

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
