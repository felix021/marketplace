# AI Pair Review — claude-glm Integration

Detailed protocols for dual-agent autonomy mode using `claude-glm` (智谱GLM-powered CLI).
When both agents reach consensus, the workflow proceeds without human intervention.

## Table of Contents

- [Detection](#detection)
- [General Discussion Protocol](#general-discussion-protocol)
- [Requirements Discussion Protocol](#requirements-discussion-protocol)
- [Code Review Protocol](#code-review-protocol)
- [Build & Deploy Protocol](#build--deploy-protocol)
- [Consensus Labels](#consensus-labels)
- [Decision Logging](#decision-logging)
- [Safety Constraints](#safety-constraints)

---

## Detection

```bash
if command -v claude-glm &>/dev/null; then
  GLM_AVAILABLE=true
fi
```

---

## General Discussion Protocol

**For ANY question or decision** during the workflow, if claude-glm is available, discuss
with it before asking the human. This applies to:

- Requirements interpretation
- Design/architecture choices
- Scope decisions (in/out)
- Implementation approach
- Whether a test is sufficient
- Whether a change is safe to deploy
- Any ambiguity or judgment call

```bash
cat > /tmp/glm-discuss-$NUMBER.md <<'EOF'
## Context: Issue #$NUMBER — {title}

{relevant context}

## Question

{the specific question or decision to be made}

## My position

{your analysis and recommendation}

Please share your position. If you agree, confirm with reasoning.
If you disagree, explain why and propose an alternative.

Reply with structured JSON:
{
  "agree": true/false,
  "position": "...",
  "reasoning": "...",
  "concerns": [...]
}
EOF

GLM_RESPONSE=$(claude-glm -p "$(cat /tmp/glm-discuss-$NUMBER.md)" --output-format json 2>/dev/null)
```

**Decision logic:**
- Both agents agree → proceed autonomously, log the decision
- Agents disagree → one more round of discussion with counterarguments
- Still disagree after 2 rounds → escalate to human with both perspectives
- **Exception:** Hard human gates (see Safety Constraints) always escalate regardless

---

## Requirements Discussion Protocol

When an issue is ambiguous, before escalating to human:

```bash
cat > /tmp/glm-discuss-$NUMBER.md <<'EOF'
## Issue #$NUMBER: {title}

{issue body}

## My analysis

{Your understanding of the requirements}

## Open questions

1. {question 1}
2. {question 2}

Please share your interpretation and answer the open questions.
If you disagree with my analysis, explain why.
Reply with a structured JSON:
{"agree": true/false, "interpretation": "...", "answers": [...], "concerns": [...]}
EOF

claude-glm -p "$(cat /tmp/glm-discuss-$NUMBER.md)" --output-format json 2>/dev/null
```

**Decision logic:**
- Both agents agree on interpretation → proceed with implementation, post agreed
  interpretation as a comment on the issue
- Agents disagree → one more round, then escalate to human if still no consensus

---

## Code Review Protocol

After implementation, before creating the PR (or after, for external PRs):

```bash
# Generate the diff
DIFF=$(git diff origin/$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')..HEAD)

# Ask claude-glm to review
cat > /tmp/glm-review-$NUMBER.md <<'EOF'
Review this diff for issue #$NUMBER: {title}

## Requirements
{issue body / acceptance criteria}

## Diff
$DIFF

Review for: correctness, security, style, edge cases.
Reply with structured JSON:
{
  "verdict": "approve" | "request_changes",
  "issues": [{"severity": "critical|major|minor", "file": "...", "line": N, "description": "..."}],
  "summary": "..."
}
EOF

GLM_REVIEW=$(claude-glm -p "$(cat /tmp/glm-review-$NUMBER.md)" --output-format json 2>/dev/null)
```

**Decision logic:**
- claude-glm approves (no critical/major issues) → **full autonomous delivery**:
  1. Create and merge the PR
  2. Close the issue
  3. Trigger build & deploy
  4. Log the decision on the issue
  5. Notify human: "Issue #N resolved, PR merged and deployed — dual-agent consensus"
- claude-glm requests changes → fix the issues first, then re-run review
- After 2 rounds of disagreement → escalate to human

---

## Build & Deploy Protocol

After dual-agent consensus merge, automatically build and deploy:

```bash
# Discuss deploy readiness with GLM
cat > /tmp/glm-deploy-$NUMBER.md <<'EOF'
PR #$PR_NUMBER for issue #$NUMBER has been merged to main.

## Changes summary
{summary of what changed}

## Build result
{build output — pass/fail}

## Question
Should we proceed with deployment? Consider:
- Are there any risks in deploying this change?
- Does this need a staged rollout?
- Any rollback concerns?

Reply with structured JSON:
{
  "agree_to_deploy": true/false,
  "reasoning": "...",
  "concerns": [],
  "rollback_plan": "..."
}
EOF

GLM_DEPLOY=$(claude-glm -p "$(cat /tmp/glm-deploy-$NUMBER.md)" --output-format json 2>/dev/null)
```

**Decision logic:**
- Both agree to deploy → deploy, log, and notify human
- Either agent has concerns → notify human with the concerns, let human decide
- Build failed → hard escalation to human, no deploy discussion needed

---

## Consensus Labels

```bash
gh label create "ai:human-confirm" --description "AI agents agreed and acted — human please confirm" --color "BF55EC" --repo $REPO 2>/dev/null || true
gh label create "ai:autonomous" --description "Resolved autonomously by dual-agent consensus" --color "2ECC71" --repo $REPO 2>/dev/null || true
```

| Label | Meaning |
|-------|---------|
| `ai:human-confirm` | Fallback: used in single-agent mode when human must confirm |
| `ai:autonomous` | Issue was resolved end-to-end by dual-agent consensus. Human notified. |

---

## Decision Logging

Every autonomous action must be logged as an issue comment:

```markdown
## 🤖 Autonomous Decision

**Action:** {what was done}
**Consensus:** Claude ✅ + GLM ✅
**Reasoning:** {1-2 sentences}
**Reversible:** {yes/no — and how}
**Notification sent:** {channel}

<details>
<summary>Discussion transcript</summary>

**Claude:** {position}
**GLM:** {response}
**Agreement:** {final consensus}
</details>
```

This creates a full audit trail. Humans can review decisions asynchronously without being
blocked.

---

## Safety Constraints

### Hard human gates (even with dual-agent consensus, ALWAYS escalate):

- PRs that touch CI/CD configs (`.github/workflows/`, `Jenkinsfile`, etc.)
- Changes to secrets, credentials, or permissions
- Changes to authentication/authorization systems
- Database migrations that drop columns/tables
- License or legal-sensitive changes
- Merging PRs with failing CI — even if both agents say "it's fine"

### Autonomy rules:

- Both agents agree → proceed, log, notify
- Either agent has safety concerns → escalate to human
- Agents disagree after 2 rounds → escalate to human
- Build or deploy fails → hard escalation to human
- Never force-push, even with consensus
- Always log decisions — no silent actions

### Notification channels (detection order):

1. `felix021:feishu-notify` skill (feishu/lark)
2. Telegram (if env vars configured)
3. `gh issue comment` / `gh pr comment` (always, as audit trail)
