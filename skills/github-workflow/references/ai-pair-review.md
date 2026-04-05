# AI Pair Review — claude-glm Integration

Detailed protocols for dual-agent consensus mode using `claude-glm` (智谱GLM-powered CLI).

## Table of Contents

- [Detection](#detection)
- [Requirements Discussion Protocol](#requirements-discussion-protocol)
- [Code Review Protocol](#code-review-protocol)
- [Consensus Labels](#consensus-labels)
- [Safety Constraints](#safety-constraints)

---

## Detection

```bash
if command -v claude-glm &>/dev/null; then
  GLM_AVAILABLE=true
fi
```

---

## Requirements Discussion Protocol

When an issue is ambiguous, before escalating to human:

```bash
# Write the question to a temp file
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
- Agents disagree → post both interpretations as an issue comment, label
  `ai:needs-clarification`, and let the human decide

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
- claude-glm approves (no critical/major issues) → merge the PR, but:
  1. Add label `ai:human-confirm` to the issue
  2. Post a comment summarizing both agents' assessments
  3. Notify the human: "AI pair review passed, PR merged — please confirm or request adjustments"
  4. **Do NOT close the issue** — human removes the tag after confirmation
- claude-glm requests changes → fix the issues first, then re-run review
- After 2 rounds of disagreement → escalate to human

---

## Consensus Labels

```bash
gh label create "ai:human-confirm" --description "AI agents agreed and acted — human please confirm" --color "BF55EC" --repo $REPO 2>/dev/null || true
```

| Label | Meaning |
|-------|---------|
| `ai:human-confirm` | Both AIs agreed, action was taken (PR merged / implementation done). Human should review and either confirm (remove label + close issue) or request adjustments. |

---

## Safety Constraints

Even with dual-agent consensus, **never**:

- Delete branches or force-push
- Close issues (human closes after confirming)
- Merge PRs that touch CI/CD configs, secrets, or permissions
- Merge PRs with failing CI — even if both agents say "it's fine"
- Act on issues labeled `ai:needs-clarification` without human response
