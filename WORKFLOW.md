# Multi-Agent Consensus Workflow Guide

## Overview

Five AI agents (Researcher, Implementer, Reviewer-Quality, Reviewer-Security, Ops) collaborate on tasks using a tmux-based workflow with mandatory unanimous consensus before proceeding.

**Agents & Roles**:
- **Researcher** (Pathfinder): Discovers context, trade-offs, prior work
- **Implementer** (Forge): Drafts implementation, minimal safe changes
- **Reviewer-Quality** (Lens): Checks correctness, tests, maintainability
- **Reviewer-Security** (Sentinel): Checks auth, secrets, boundaries, abuse paths
- **Ops** (Anchor): Checks reliability, recovery, automation safety

## Workflow Phases

| Phase | Agent | Purpose | Output |
|-------|-------|---------|--------|
| 1 | All | **Intake** - Parse task, create context | Problem statement, scope, constraints |
| 2 | Researcher | **Research** - Gather context and options | Code patterns, prior issues, feasible approaches |
| 3 | Implementer | **Plan** - Draft implementation | Files to change, approach, test strategy |
| 4 | Lens | **Quality Review** - Check correctness/tests | Bugs, test gaps, refactoring suggestions |
| 5 | Sentinel | **Security Review** - Check auth/secrets | Auth flaws, injection risks, data leakage |
| 6 | Anchor | **Ops Review** - Check reliability | Failure modes, recovery paths, observability |
| 7 | All | **Decision** - Unanimous vote | Proceed, Escalate, or Blocked |
| 8 | Implementer | **Execute** - Implement changes | Code changes, validation results |
| 9 | All | **Verify** - Validate output | Requirements met? All tests pass? |

## Quick Start

### 1. Create a task file

```json
{
  "title": "Fix token refresh race condition",
  "description": "Users report random 401 errors after token refresh in mobile app.",
  "context": "Affects 5% of daily users, regression from PR #456.",
  "priority": "high"
}
```

### 2. Start workflow

```bash
cd /path/to/llm-craft
./scripts/workflow-orchestrator.sh ./my-task.json
```

This creates:
- tmux session with 5 agent panes
- Workflow state file
- Vote tracking
- Phase logs

### 3. Monitor agents in tmux

```bash
tmux attach -t agent-consensus-<TIMESTAMP>
```

Navigate panes with `Ctrl+b` arrow keys:
- **Pane 0**: Researcher (left)
- **Pane 1**: Implementer (right top)
- **Pane 2**: Reviewer-Quality (right middle)
- **Pane 3**: Reviewer-Security (right bottom-top)
- **Pane 4**: Ops (right bottom)

## Consensus Rules

**Rule**: UNANIMOUS
- All 5 agents must vote **"proceed"** to continue
- If ANY agent votes differently: workflow escalates + postpones
- If ANY agent times out (>5 min): escalated as blocked
- If ANY agent votes **"needs_info"**: that phase re-runs after getting answers

### Example Consensus Scenarios

✅ **Consensus Reached**: All vote proceed → advance to next phase
❌ **Dissent**: Sentinel votes blocked (security issue), others vote proceed → escalate
⏱️ **Timeout**: Implementer doesn't respond after 5 min → escalate as blocked
❓ **Needs Info**: Lens votes needs_info (missing test details) → loop phase, implementer provides info

## Escalation & Postponement

When consensus fails:

1. **Escalation logged** to `workflow-logs/<workflow_id>-escalation.log`
2. **State preserved** - all votes and context saved
3. **Human notified** - review agent disagreements
4. **Task postponed** until human decision or agent modifications

### Escalation Log Contents

```json
{
  "workflow_id": "wf-1234567890-abc123",
  "escalated_at": "2026-05-28T15:02:43Z",
  "phase_reached": 5,
  "escalation_reason": "dissent",
  "agent_votes": [
    { "agent_id": "reviewer-security", "decision": "blocked", "rationale": "..." },
    { "agent_id": "reviewer-quality", "decision": "proceed", "rationale": "..." }
  ],
  "state_file": "workflow-state/wf-1234567890-abc123.json",
  "votes_file": "workflow-state/wf-1234567890-abc123-votes.json"
}
```

### How to Resolve Escalations

1. **Read the escalation log**:
   ```bash
   cat workflow-logs/<workflow_id>-escalation.log
   ```

2. **Examine agent votes**:
   ```bash
   cat workflow-state/<workflow_id>-votes.json | jq '.votes[] | select(.phase == 5)'
   ```

3. **Options**:
   - **Accept high-confidence dissent**: Modify task based on agent feedback
   - **Override agent**: Provide human justification (security sign-off, etc.)
   - **Request more info**: Ask agents specific questions

4. **Resume workflow**:
   ```bash
   ./scripts/workflow-orchestrator.sh --resume <workflow_id>
   ```

## File Structure

```
llm-craft/
├── workflow-protocol.json              # Consensus protocol schema
├── scripts/
│   ├── workflow-orchestrator.sh         # Main orchestrator
│   ├── agent-runner.sh                  # Agent wrapper
│   └── ...
├── agents/
│   ├── personas/
│   │   ├── researcher.md
│   │   ├── implementer.md
│   │   ├── reviewer-quality.md
│   │   ├── reviewer-security.md
│   │   └── ops.md
│   └── routing-guide.md
├── workflow-state/                      # Workflow sessions
│   ├── wf-1234567890-abc123.json       # Workflow state
│   └── wf-1234567890-abc123-votes.json # Votes
└── workflow-logs/                       # Phase logs
    ├── wf-1234567890-abc123.log        # Main log
    ├── wf-1234567890-abc123-researcher.log
    ├── wf-1234567890-abc123-escalation.log
    └── ...
```

## API Reference

### workflow-orchestrator.sh

**Start workflow:**
```bash
./workflow-orchestrator.sh <task_file> [--headless]
```

- `<task_file>`: JSON task description
- `--headless`: Auto-cleanup tmux after completion (no manual attach needed)

**Resume escalated workflow:**
```bash
./workflow-orchestrator.sh --resume <workflow_id>
```

### agent-runner.sh

**Internal use** - called by orchestrator. Shows agent prompts and collects votes.

```bash
agent-runner --agent <id> --phase <num> --workflow <id> --context <file>
```

**Example**: How Researcher phase 2 runs:
```bash
agent-runner --agent researcher --phase 2 --workflow wf-123 --context task.json
# → Shows Researcher persona + research instruction + task context
# → Reads agent response as JSON vote
# → Appends to votes file
```

## Consensus Vote Format

All agents respond in this JSON format:

```json
{
  "workflow_id": "wf-20260528-001",
  "phase": 5,
  "agent_id": "reviewer-security",
  "timestamp": "2026-05-28T15:02:43Z",
  "status": "submitted",
  "decision": "blocked",
  "confidence": "high",
  "rationale": "Token refresh endpoint lacks rate-limit check. Vulnerable to brute-force on mobile.",
  "findings": [
    "No rate-limit middleware on POST /auth/refresh",
    "Accepts unlimited requests from same device_id",
    "No exponential backoff or circuit breaker"
  ],
  "questions": [
    "Is rate-limiting handled elsewhere (WAF, CDN)?",
    "What's the intended rate limit for mobile?"
  ]
}
```

**Decision values**:
- `"proceed"`: Agent approves, ready to continue
- `"escalate"`: Agent has concerns, needs human review
- `"blocked"`: Agent found critical issue, should not proceed
- `"needs_info"`: Agent needs more context before deciding

## Extending the Workflow

### Add a new agent persona

1. Create `agents/personas/my-agent.md` with role description
2. Update `workflow-protocol.json` to add agent
3. Update `scripts/agent-runner.sh` to handle new agent in `get_agent_instruction()`
4. Update consensus voting to include new agent

### Modify consensus rules

Edit `workflow-protocol.json` consensus section. Options:
- Change from unanimous to majority (3/5)
- Add weighted voting (security = 1.5x weight)
- Create phase-specific rules (security review must be unanimous, planning can be majority)

### Custom phase instructions

Edit `scripts/agent-runner.sh` function `get_agent_instruction()`:

```bash
get_agent_instruction() {
  case $phase in
    ...
    7) echo "Custom instruction for phase 7" ;;
  esac
}
```

## Troubleshooting

### Agent hangs during a phase

**Symptom**: Workflow waits >5 min on an agent

**Resolution**:
1. Check agent pane in tmux: `Ctrl+b` arrow to pane
2. Review agent log: `cat workflow-logs/<workflow_id>-<agent_id>.log`
3. If agent is waiting for user input: provide input in tmux pane
4. If agent crashed: manually vote or kill workflow and resume with `--resume`

### Consensus keeps failing on same issue

**Symptom**: Agent X always votes "blocked" on phase Y

**Resolution**:
1. Review agent's rationale in votes file
2. Modify task to address agent's concern OR
3. Override with human decision (document in escalation log) OR
4. Request agent reconsider with new context

### Lost workflow state

**Symptom**: Can't resume workflow, files missing

**Recovery**:
- State files in `workflow-state/` are authoritative
- If deleted, escalation log still has agent votes and context
- Recreate task and start fresh workflow

## Examples

### Example 1: Successful consensus

```
Phase 1 (intake): All vote proceed ✓
Phase 2 (research): All vote proceed ✓
Phase 3 (plan): All vote proceed ✓
Phase 4 (quality review): All vote proceed ✓
Phase 5 (security review): All vote proceed ✓
Phase 6 (ops review): All vote proceed ✓
Phase 7 (decision): All vote proceed ✓
→ PROCEED TO EXECUTION
Phase 8 (execute): Implementer runs changes, all verify ✓
Phase 9 (verify): All validate ✓
→ WORKFLOW COMPLETE
```

### Example 2: Security escalation

```
Phase 1-4: All vote proceed ✓
Phase 5 (security review):
  - Sentinel: "blocked" (missing CSRF token validation)
  - Implementer: "proceed"
  - Others: "proceed"
→ CONSENSUS FAILED: Escalate + Postpone
Escalation log written to: workflow-logs/wf-abc-escalation.log
Human reviews: "Sentinel is correct, add CSRF validation"
Task modified, resume with: --resume wf-abc
Phase 5 rerun: Sentinel votes proceed ✓
→ Continue to phases 6-9
```

## Performance Notes

- **Phase time**: 5 min per agent per phase (300 sec timeout)
- **Total workflow**: ~30 min for full 9-phase run (if all agents respond quickly)
- **Consensus check**: Runs every 2 sec, completes when all 5 votes received
- **Escalation**: Immediate, no queue

## Security Considerations

- **Vote integrity**: Votes are JSON files in workflow-state/, assume filesystem is trusted
- **Secret handling**: No secrets in task JSON or agent prompts; use env vars
- **Access control**: Escalation logs contain decision rationale, may need ACLs
- **Audit trail**: All phases logged to `workflow-logs/`, immutable after phase completion
