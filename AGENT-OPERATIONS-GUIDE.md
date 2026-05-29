# 🤖 Agent Operations Guide: Using Helper Scripts

**Purpose**: Complete reference for AI agents on how to use the workflow and skill helper scripts
**Audience**: AI agents executing in the consensus workflow
**Status**: Production-ready

---

## 🎯 Quick Reference: What Script Do I Use When?

| Situation | Script | Purpose |
|-----------|--------|---------|
| "I need to check task status" | `workflow-state-manager.sh status` | Query current workflow state |
| "I need to see what phase I'm in" | `workflow-state-manager.sh phase` | Query current phase details |
| "I need to see my vote options" | `workflow-protocol.json` | Reference consensus rules |
| "I need to run a skill" | `skill-executor.sh` | Execute a skill with context |
| "I need context about the task" | `workflow-state-manager.sh` + context file | Query state manager |
| "I need to see what skills I can use" | `agents/SKILLS.json` | Lookup available skills |
| "I need to understand consensus rules" | `workflow-protocol.json` | Reference voting protocol |

---

## 📋 Script Reference for Agents

### 1. `workflow-state-manager.sh` - Query Workflow State

**Purpose**: Read workflow state, task context, agent votes, phase status

#### Usage

```bash
# Show all active workflows
./scripts/workflow-state-manager.sh list

# Get full workflow status
./scripts/workflow-state-manager.sh status <WORKFLOW_ID>

# Get current phase details
./scripts/workflow-state-manager.sh phase <WORKFLOW_ID> <PHASE_NUM>

# Get consensus status for a phase
./scripts/workflow-state-manager.sh consensus <WORKFLOW_ID> <PHASE_NUM>

# Get specific agent's vote and rationale
./scripts/workflow-state-manager.sh agent <WORKFLOW_ID> <AGENT_ID> <PHASE_NUM>

# Export full workflow as report
./scripts/workflow-state-manager.sh export <WORKFLOW_ID> [txt|json|html]

# List all escalated workflows
./scripts/workflow-state-manager.sh escalations

# Get escalation details
./scripts/workflow-state-manager.sh escalation <WORKFLOW_ID>
```

#### Input Format

| Parameter | Type | Example | Required |
|-----------|------|---------|----------|
| WORKFLOW_ID | string | `wf-1234567890-abc123` | Yes (except for `list`) |
| PHASE_NUM | integer | `1`, `5`, `9` | For phase-specific queries |
| AGENT_ID | string | `researcher`, `sentinel`, `implementer` | For agent-specific queries |
| FORMAT | string | `txt`, `json`, `html` | Optional (default: json) |

#### Output Format - `status` Command

```json
{
  "workflow_id": "wf-1234567890-abc123",
  "status": "in_progress",
  "current_phase": 5,
  "created_at": "2026-05-29T05:00:00Z",
  "task": {
    "title": "Add auth middleware",
    "description": "Implement token refresh with rate limiting",
    "scope": ["src/auth.ts", "src/middleware.ts"],
    "constraints": ["Must not break existing API", "Rate limit: 5/min"]
  },
  "phases": {
    "1": { "status": "complete", "started_at": "...", "ended_at": "..." },
    "2": { "status": "complete", "started_at": "...", "ended_at": "..." },
    "5": { "status": "in_progress", "started_at": "...", "current_agent": "sentinel" }
  },
  "context": {
    "file": "/path/to/context.json",
    "size_bytes": 2048,
    "last_updated": "2026-05-29T05:30:00Z"
  }
}
```

#### Output Format - `phase` Command

```json
{
  "workflow_id": "wf-1234567890-abc123",
  "phase_num": 5,
  "phase_name": "Security Review",
  "description": "Review for security risks, auth, secrets, injection attacks",
  "responsible_agent": "sentinel",
  "status": "in_progress",
  "started_at": "2026-05-29T05:30:00Z",
  "findings": {
    "risks_identified": ["SQL injection risk in user input", "Missing CSRF token"],
    "severity": ["high", "medium"],
    "recommendations": ["Add parameterized queries", "Add CSRF middleware"]
  },
  "prior_phases_votes": {
    "phase_1": { "consensus": "proceed", "unanimous": true },
    "phase_2": { "consensus": "proceed", "unanimous": true },
    "phase_3": { "consensus": "proceed", "unanimous": true },
    "phase_4": { "consensus": "proceed", "unanimous": true }
  }
}
```

#### Example: Researcher Querying Task Status

```bash
# Researcher gets into the workflow
WORKFLOW_ID="wf-1234567890-abc123"

# 1. Check what phase we're in and what was done before
./scripts/workflow-state-manager.sh status $WORKFLOW_ID

# 2. Review the task context
cat workflow-state/${WORKFLOW_ID}-context.json

# 3. See what other agents found
./scripts/workflow-state-manager.sh phase $WORKFLOW_ID 2

# 4. Get ready to contribute my findings
echo "I found X patterns, Y similar issues, recommending Z..."
```

---

### 2. `skill-executor.sh` - Run Skills

**Purpose**: Execute skills (research, analysis, validation) with caching

#### Usage

```bash
# Basic skill execution
./scripts/skill-executor.sh --skill <SKILL_NAME> --context <CONTEXT_FILE> [--phase <PHASE_NUM>] [--agent <AGENT_ID>]

# With timeout (default: 300s = 5 min)
./scripts/skill-executor.sh --skill <SKILL_NAME> --context <CONTEXT_FILE> --timeout 600

# Disable caching (always run fresh)
./scripts/skill-executor.sh --skill <SKILL_NAME> --context <CONTEXT_FILE> --no-cache

# With custom parameters
./scripts/skill-executor.sh --skill <SKILL_NAME> --context <CONTEXT_FILE> --params '{"key": "value"}'

# List available skills for current phase
./scripts/skill-executor.sh --list-skills --phase 2

# List skills for a specific agent
./scripts/skill-executor.sh --list-skills --agent researcher
```

#### Input Format

| Parameter | Type | Example | Required | Default |
|-----------|------|---------|----------|---------|
| SKILL_NAME | string | `code-search`, `issue-lookup` | Yes | - |
| CONTEXT_FILE | string | `task-context.json` | Yes | - |
| PHASE_NUM | integer | `2`, `5` | No | From context |
| AGENT_ID | string | `researcher` | No | Auto-detect |
| TIMEOUT | integer (seconds) | `300`, `600` | No | 300 |
| PARAMS | JSON string | `'{"query": "auth"}'` | No | `{}` |

#### Output Format - Successful Skill

```json
{
  "skill": "code-search",
  "status": "success",
  "execution_time_ms": 1234,
  "cached": false,
  "findings": {
    "query": "authentication middleware",
    "matches": 12,
    "results": [
      {
        "file": "src/auth.ts",
        "line": 45,
        "context": "export const authMiddleware = ..."
      }
    ],
    "summary": "Found 12 matches in 3 files"
  },
  "confidence": 0.92,
  "next_steps": ["Review line 45 in src/auth.ts", "Check related middleware"]
}
```

#### Output Format - Error

```json
{
  "skill": "code-search",
  "status": "error",
  "error": "query_too_broad",
  "error_message": "Query must be more specific (>3 chars, <100 chars)",
  "execution_time_ms": 45,
  "retry_suggestions": [
    "Try 'password reset' instead of 'auth'",
    "Narrow scope: 'auth in src/middleware'"
  ]
}
```

#### Available Skills by Agent

See `agents/SKILLS.json` for complete list. Quick reference:

**Shared Skills** (all agents can use):
- `code-search` - Search codebase for patterns
- `issue-lookup` - Find related GitHub issues
- `docs-search` - Search documentation
- `pattern-analysis` - Analyze code patterns
- `context-retrieval` - Get task context
- `dependency-check` - Check dependencies
- `token-estimate` - Estimate token usage

**Researcher Unique Skills**:
- `market-research` - Look for similar solutions
- `constraint-analysis` - Identify constraints
- `risk-assessment` - Early risk identification

**Implementer Unique Skills**:
- `file-impact-analysis` - What files will change
- `test-generation` - Generate test cases
- `migration-analysis` - Check for data migrations

**Lens Unique Skills**:
- `test-coverage-check` - Measure test coverage
- `code-quality-scan` - Run quality checks
- `api-contract-check` - Validate API changes

**Sentinel Unique Skills**:
- `security-scan` - Scan for vulnerabilities
- `auth-check` - Review authentication
- `dependency-audit` - Check dependencies for CVEs

**Anchor Unique Skills**:
- `deployment-readiness` - Check deployment prep
- `monitoring-check` - Verify observability
- `disaster-recovery-check` - Verify backup/recovery

#### Example: Sentinel Running Security Scan

```bash
# Sentinel is running phase 5 (Security Review)
WORKFLOW_ID="wf-1234567890-abc123"
CONTEXT_FILE="workflow-state/${WORKFLOW_ID}-context.json"

# Run the security-scan skill
./scripts/skill-executor.sh \
  --skill security-scan \
  --context $CONTEXT_FILE \
  --phase 5 \
  --agent sentinel

# Parse the findings
# Output shows vulnerabilities, recommendations, confidence score
# Use findings to decide vote: "proceed", "escalate", or "blocked"
```

---

### 3. `agent-runner.sh` - Your Execution Wrapper

**Purpose**: You are invoked BY this script. Understand your contract.

#### How You're Invoked

```bash
./scripts/agent-runner.sh \
  --agent <YOUR_AGENT_ID> \
  --phase <PHASE_NUM> \
  --workflow <WORKFLOW_ID> \
  --context <CONTEXT_FILE> \
  --instruction "<CUSTOM_INSTRUCTION>"
```

#### What You Get

When agent-runner.sh invokes you, these files/env vars are available:

```bash
# Environment variables set by agent-runner.sh:
AGENT_ID="researcher"              # Your agent ID
PHASE="2"                           # Current phase (1-9)
WORKFLOW_ID="wf-1234567890-abc123" # Workflow identifier
AGENT_LOG="workflow-logs/..."       # Where your logs go
SKILLS_REGISTRY="agents/SKILLS.json" # All available skills
```

#### What You Must Return

At end of your execution, submit a vote:

```json
{
  "agent_id": "researcher",
  "phase": 2,
  "workflow_id": "wf-1234567890-abc123",
  "vote": "proceed",
  "findings": "Found 12 code patterns, 3 similar issues, no blockers identified",
  "confidence": 0.88,
  "escalation_reason": null,
  "timestamp": "2026-05-29T05:35:00Z",
  "details": {
    "patterns_found": 12,
    "similar_issues": 3,
    "risk_assessment": "low"
  }
}
```

**Valid votes**:
- `"proceed"` - Confident to move forward
- `"escalate"` - Concerns exist, needs human review
- `"blocked"` - Cannot proceed; must fix before continuing
- `"needs_info"` - Need clarification or more data

---

### 4. `workflow-protocol.json` - Consensus Rules Reference

**Purpose**: Understand voting rules, escalation, decision logic

#### Key Sections

```json
{
  "consensus_rules": {
    "unanimous_required": true,
    "dissent_action": "escalate",
    "dissent_handling": "postpone_and_notify"
  },
  "vote_options": [
    "proceed",
    "escalate",
    "blocked",
    "needs_info"
  ],
  "escalation_conditions": {
    "any_vote_blocked": true,
    "dissent_pattern": "any_agent_disagrees"
  },
  "phase_decisions": {
    "phase_1_9": "consensus required",
    "phase_7": "final_decision - any dissent blocks execution"
  }
}
```

#### When to Escalate

```
BLOCKED ← Should be rare. Only when:
  - Security vulnerability must be fixed
  - Architectural conflict with requirements
  - Dependency unavailable
  - Resource constraints violated

ESCALATE ← More common. When:
  - Multiple reasonable approaches exist
  - Tradeoffs need human input
  - Risk assessment suggests caution
  - Quality/performance concerns exist

NEEDS_INFO ← When:
  - Missing requirements clarification
  - Can't find relevant context
  - Configuration unclear
  - External dependency status unknown

PROCEED ← When:
  - Comfortable with risk level
  - Concerns addressed or acceptable
  - Ready to move forward
```

#### Example: Decision Tree for Sentinel

```
Am I reviewing Phase 5 (Security)?
  ↓ YES
  
Did I find critical vulnerabilities (CVE-level)?
  ├─ YES → BLOCKED (fix required)
  ├─ MEDIUM (auth design issue) → ESCALATE
  ├─ LOW (missing type hints) → PROCEED
  └─ NONE → PROCEED
```

---

## 🔄 Workflow: How It Works For You

### Phase Roles & Responsibilities

| Phase | Name | Your Role | Key Questions |
|-------|------|-----------|---|
| 1 | Intake | All agents | Is the task clear? Do we have scope? |
| 2 | Research | Researcher | What patterns exist? What's been done before? |
| 3 | Plan | Implementer | How do we build it? What files change? |
| 4 | Quality | Lens | Is it testable? Are tests sufficient? |
| 5 | Security | Sentinel | Are there vulnerabilities? Auth risks? |
| 6 | Ops | Anchor | Is it deployable? Observable? Recoverable? |
| 7 | Decision | All agents | **UNANIMOUS VOTE** - Proceed or escalate? |
| 8 | Execute | Implementer | Make the changes. Run tests. |
| 9 | Verify | All agents | Does output match requirements? |

### Your Agent Profile & Skills

**RESEARCHER** (Pathfinder)
- Skills: code-search, issue-lookup, docs-search, pattern-analysis
- Phase 2 lead
- Goal: Find patterns, reduce uncertainty
- Decision: Proceed if findings complete, escalate if gaps

**IMPLEMENTER** (Craftsperson)
- Skills: file-impact-analysis, test-generation, migration-analysis
- Phase 3 lead, Phase 8 executor
- Goal: Design buildable solution
- Decision: Proceed if approach is sound, escalate if blockers

**LENS** (Guardian of Quality)
- Skills: test-coverage-check, code-quality-scan, api-contract-check
- Phase 4 lead
- Goal: Ensure quality, tests, maintainability
- Decision: Proceed if tests sufficient, escalate if gaps

**SENTINEL** (Security Guardian)
- Skills: security-scan, auth-check, dependency-audit
- Phase 5 lead
- Goal: Identify security risks, prevent vulnerabilities
- Decision: BLOCKED if critical risk, escalate if medium risk, proceed if low/none

**ANCHOR** (Ops Champion)
- Skills: deployment-readiness, monitoring-check, disaster-recovery-check
- Phase 6 lead
- Goal: Ensure deployability, observability, reliability
- Decision: Proceed if deployment-ready, escalate if concerns

---

## 📝 Example: Full Agent Execution

### Scenario: Researcher Phase 2

```bash
# 1. I'm invoked by agent-runner.sh
# Environment:
AGENT_ID="researcher"
PHASE="2"
WORKFLOW_ID="wf-1234567890-abc123"
CONTEXT_FILE="workflow-state/wf-1234567890-abc123-context.json"

# 2. I check the current state
./scripts/workflow-state-manager.sh status $WORKFLOW_ID
# Returns: Phase 2 active, task is "Add auth middleware with rate limiting"

# 3. I read the context
cat $CONTEXT_FILE
# Shows: Need to implement token refresh with rate limit (max 5/min)

# 4. I run my skills
./scripts/skill-executor.sh --skill code-search --context $CONTEXT_FILE \
  --params '{"query": "authentication middleware"}'
# Finds: 12 matches in src/auth.ts and src/middleware.ts

./scripts/skill-executor.sh --skill issue-lookup --context $CONTEXT_FILE \
  --params '{"query": "rate limiting"}'
# Finds: 3 related issues with solutions

./scripts/skill-executor.sh --skill pattern-analysis --context $CONTEXT_FILE \
  --params '{"pattern": "jwt refresh"}'
# Finds: Existing pattern in lib/auth/jwt.ts

# 5. I synthesize findings
FINDINGS="Found 12 code patterns, 3 similar issues, 1 existing JWT pattern. \
Rate limit middleware exists in lib/middleware. \
No blockers identified. Ready to proceed."

# 6. I vote
cat > /tmp/my_vote.json << EOF
{
  "agent_id": "researcher",
  "phase": 2,
  "workflow_id": "$WORKFLOW_ID",
  "vote": "proceed",
  "findings": "$FINDINGS",
  "confidence": 0.92,
  "escalation_reason": null,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "details": {
    "patterns_found": 12,
    "similar_issues": 3,
    "existing_solutions": 1
  }
}
EOF

# 7. Submit vote (agent-runner.sh handles this)
cat /tmp/my_vote.json >> $AGENT_LOG
```

### Scenario: Sentinel Phase 5 With Security Escalation

```bash
AGENT_ID="sentinel"
PHASE="5"
WORKFLOW_ID="wf-1234567890-abc123"

# Run security scan
./scripts/skill-executor.sh --skill security-scan --context $CONTEXT_FILE
# Output:
#   {
#     "findings": {
#       "vulnerabilities": [
#         {"type": "SQL_INJECTION", "severity": "critical", "location": "src/user.ts:23"}
#       ]
#     }
#   }

# I found a CRITICAL vulnerability. Must BLOCK or ESCALATE.
# Since this is security, I BLOCK.

VOTE="blocked"
FINDINGS="CRITICAL: SQL injection in user lookup (line 23). \
Must add parameterized queries before proceeding."

# Submit escalation
cat > /tmp/my_vote.json << EOF
{
  "agent_id": "sentinel",
  "phase": 5,
  "workflow_id": "$WORKFLOW_ID",
  "vote": "$VOTE",
  "findings": "$FINDINGS",
  "confidence": 0.99,
  "escalation_reason": "CRITICAL security vulnerability found",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "details": {
    "vulnerabilities_critical": 1,
    "vulnerabilities_high": 0,
    "action": "Fix before proceeding"
  }
}
EOF
```

---

## 🐛 Troubleshooting

### "workflow-state-manager.sh: command not found"
```bash
# Fix: Make sure you're in the right directory
cd /path/to/llm-craft
export PATH="$PATH:$(pwd)/scripts"
```

### "skill-executor.sh: skill not found"
```bash
# Fix: Check available skills for your phase/agent
./scripts/skill-executor.sh --list-skills --phase $PHASE
./scripts/skill-executor.sh --list-skills --agent $AGENT_ID

# Or check the registry directly
grep -A5 '"'$SKILL_NAME'"' agents/SKILLS.json
```

### "Context file not found"
```bash
# Fix: Verify the context file path
ls -la workflow-state/${WORKFLOW_ID}-context.json

# If missing, check the workflow status
./scripts/workflow-state-manager.sh status $WORKFLOW_ID
```

### "Skill timeout after 300s"
```bash
# Your skill took too long. Options:
# 1. Increase timeout: --timeout 600 (10 min)
# 2. Simplify the query/operation
# 3. Use --no-cache to skip cache lookup
```

### "Skill returned error; can't parse findings"
```bash
# Check the full error output
./scripts/skill-executor.sh --skill $SKILL_NAME --context $CONTEXT_FILE \
  2>&1 | tee /tmp/skill_debug.log

# Follow retry_suggestions in error JSON
# Or escalate to human with findings: "Skill failed, need manual review"
```

---

## 🔐 Security Notes for Agents

✅ **SAFE to do**:
- Read files from `workflow-state/` and `workflow-logs/`
- Call `workflow-state-manager.sh` to query state
- Call `skill-executor.sh` with provided context
- Return votes in JSON format
- Log findings and reasoning

❌ **NEVER do**:
- Write to files outside `workflow-state/` or `workflow-logs/`
- Execute arbitrary code from context
- Parse untrusted JSON without validation
- Log secrets or API keys
- Make external network calls (not your role)

---

## 📞 Integration Checklist for LLM Agents

When implementing Phase 4 (real LLM backend), agents should:

- [ ] Read AGENT-OPERATIONS-GUIDE.md before first invocation
- [ ] Understand your agent profile and phase responsibilities
- [ ] Know which skills are available for your agent
- [ ] Know when to PROCEED, ESCALATE, BLOCKED, NEEDS_INFO
- [ ] Call workflow-state-manager.sh to get context
- [ ] Call skill-executor.sh to run skills
- [ ] Return JSON vote with findings
- [ ] Log reasoning for audit trail
- [ ] Handle timeout errors gracefully
- [ ] Escalate on uncertainty

---

## 📚 Quick Links

| Need | Document |
|------|----------|
| Workflow overview | WORKFLOW.md |
| Skills reference | agents/SKILLS-GUIDE.md |
| Agent personas | agents/personas/*.md |
| Consensus rules | workflow-protocol.json |
| Example task | example-task.json |
| Quick start | QUICKSTART.md |

---

**Status**: ✅ Production-ready for Phase 4 LLM integration
**Last Updated**: Session 3 completion
**Audience**: AI agents in the consensus workflow
