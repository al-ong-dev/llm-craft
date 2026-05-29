# Quick Start: Multi-Agent Consensus Workflow

## 60-Second Setup

### 1. Try it (no setup required)

```bash
cd /path/to/llm-craft

# Start a workflow with example task
./scripts/workflow-orchestrator.sh ./example-task.json
```

**Expected output:**
```
[2026-05-28T15:02:43Z] [INFO] Starting workflow orchestrator
[2026-05-28T15:02:43Z] [INFO] Workflow state initialized: wf-1234567890-abc123
[2026-05-28T15:02:44Z] [INFO] tmux session created with 5 panes
[2026-05-28T15:02:45Z] [INFO] ========== PHASE 1: intake ==========
tmux session 'agent-consensus-1234567890' created
Attach with: tmux attach -t agent-consensus-1234567890
```

### 2. Monitor in tmux

```bash
# In another terminal:
tmux attach -t agent-consensus-1234567890

# Navigate panes: Ctrl+b + arrow keys
# Each pane shows one agent's analysis
```

### 3. Check results

```bash
# In another terminal:
./scripts/workflow-state-manager.sh list
./scripts/workflow-state-manager.sh status wf-1234567890-abc123
./scripts/workflow-state-manager.sh phase wf-1234567890-abc123 7
```

## What's Happening?

The workflow runs 9 phases with 5 agents:

| Phase | What Happens | Who Votes |
|-------|--------------|-----------|
| 1 | Parse task, create context | All |
| 2 | Research context & approaches | Researcher |
| 3 | Draft implementation | Implementer |
| 4 | Review quality/tests | Lens |
| 5 | Review security | Sentinel |
| 6 | Review ops/reliability | Anchor |
| 7 | **VOTE**: Proceed or escalate? | All (unanimous) |
| 8 | Execute changes | Implementer |
| 9 | Validate output | All |

**Key**: Phase 7 requires **unanimous consensus**. If any agent disagrees, the workflow:
- 📋 Documents the issue
- ⏸️ Pauses the task
- 👤 Notifies human for review/decision
- ▶️ Can be resumed after addressing concerns

## Real Example: Security Dissent

Imagine this happens at Phase 5 (Security Review):

```
Sentinel votes: "blocked" 
  Reason: Token refresh endpoint lacks rate-limit check

Implementer votes: "proceed"
  Reason: Fix is correct, tests pass

→ CONSENSUS FAILS (4 vote proceed, 1 votes blocked)

Escalation logged:
  workflow-logs/wf-1234567890-abc123-escalation.log
  
Human review options:
  1. Add rate-limit middleware (accept Sentinel's concern)
  2. Override with security sign-off (document why rate-limit not needed)
  3. Request more context from Sentinel

Resume:
  ./scripts/workflow-orchestrator.sh --resume wf-1234567890-abc123
```

## Files & Directories

```
llm-craft/
├── WORKFLOW.md                      ← Full documentation
├── WORKFLOW-SUMMARY.md              ← What was built
├── workflow-protocol.json           ← Consensus schema
├── example-task.json                ← Try this first
├── scripts/
│   ├── workflow-orchestrator.sh     ← Main orchestrator
│   ├── agent-runner.sh              ← Agent wrapper
│   ├── workflow-state-manager.sh    ← Query tool
│   └── ... (30+ existing scripts)
├── agents/
│   ├── personas/
│   │   ├── researcher.md
│   │   ├── implementer.md
│   │   ├── reviewer-quality.md
│   │   ├── reviewer-security.md
│   │   └── ops.md
│   └── routing-guide.md
└── workflow-state/                  ← Auto-created
    └── wf-*.json, wf-*-votes.json
```

## Common Commands

```bash
# List active workflows
./scripts/workflow-state-manager.sh list

# Show full workflow status
./scripts/workflow-state-manager.sh status wf-1234567890-abc123

# Show votes for a specific phase
./scripts/workflow-state-manager.sh phase wf-1234567890-abc123 5

# Check consensus for phase
./scripts/workflow-state-manager.sh consensus wf-1234567890-abc123 7

# Show agent's opinion/rationale
./scripts/workflow-state-manager.sh agent wf-1234567890-abc123 reviewer-security 5

# Export workflow as readable report
./scripts/workflow-state-manager.sh export wf-1234567890-abc123 txt

# List escalated workflows
./scripts/workflow-state-manager.sh escalations

# Show escalation details
./scripts/workflow-state-manager.sh escalation wf-1234567890-abc123
```

## Important Notes

### Currently: Mock Agents
The agents automatically vote "proceed" for testing. This lets you validate the workflow engine.

**To integrate real agents**, modify `agent-runner.sh`:
- Replace mock vote logic with actual LLM calls (Claude, GPT, Ollama)
- Pass prompt + context to LLM
- Parse LLM response as structured JSON vote

### Tmux Sessions
- Sessions persist until you kill them: `tmux kill-session -t agent-consensus-1234567890`
- Use `--headless` flag to auto-cleanup: `./workflow-orchestrator.sh ./task.json --headless`
- Each pane is independent; one agent failure doesn't crash others

### State Recovery
- All state is in `workflow-state/` (JSON files)
- Logs in `workflow-logs/` (immutable after phase completion)
- Can manually resume with `--resume <workflow_id>`
- Can query state at any time with `workflow-state-manager.sh`

## Next: Deep Dive

Read `WORKFLOW.md` for:
- Detailed consensus rules
- How to resolve escalations
- Extending with new agent personas
- Troubleshooting guide
- Security & audit considerations

---

**Status**: ✅ Ready to use. Agents vote unanimously by default. Modify `agent-runner.sh` to integrate real LLMs.
