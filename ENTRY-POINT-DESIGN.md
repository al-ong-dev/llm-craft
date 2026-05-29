# 🎯 User Entry Point Architecture - Phase 4

**Decision**: Hybrid approach - CLI + Interactive  
**Primary Script**: `scripts/start-workflow.sh`  
**Date**: 2026-05-29

---

## Entry Point Design

### Mode 1: Explicit Task (Best for Scripting/Automation)

```bash
./scripts/start-workflow.sh --task "Fix token refresh race condition" --provider claude --budget 100000
```

**What happens**:
1. Validates input (task, provider, budget)
2. Creates tmux session: `llm-coordinator-wf-{workflow-id}`
3. Spawns Coordinator + 5 agent panes
4. Feeds task to Coordinator
5. Coordinator immediately starts Phase 1 (parse task)
6. Returns to user: `Workflow ID: wf-20260529-001` (can be used for monitoring)

**Use case**: Scripting, CI/CD integration, batch processing

---

### Mode 2: Interactive Input (Best for Exploration)

```bash
./scripts/start-workflow.sh
```

**What happens**:
1. Creates tmux session: `llm-coordinator-{timestamp}`
2. Spawns Coordinator + 5 agent panes
3. Coordinator pane shows prompt: `📝 Enter task description (or 'help' for examples): `
4. User types task (supports multi-line input)
5. Coordinator starts orchestration
6. User can navigate panes with Alt+N shortcuts

**User interaction**:
```
📝 Enter task description: 
> Fix token refresh race condition in mobile app that causes 401 errors.
> Priority: high
> Affects: 5% of daily users
> (Press Enter twice to submit)

✅ Task received. Starting analysis...
[Coordinator] Phase 1: Parsing task...
[Researcher] Phase 2: Beginning research...
```

**Use case**: Interactive debugging, exploration, user testing

---

### Mode 3: Hybrid (File Input - Bonus)

```bash
# Read from file
./scripts/start-workflow.sh < task.txt

# Or with explicit file
./scripts/start-workflow.sh --file ./task.json --provider claude
```

**task.json format**:
```json
{
  "title": "Fix token refresh race condition",
  "description": "Users report random 401 errors after token refresh in mobile app",
  "context": {
    "priority": "high",
    "impact": "5% of daily active users affected",
    "regression_from": "PR #456",
    "related_issues": ["#456", "#423"]
  },
  "success_criteria": [
    "All users can refresh tokens without 401",
    "Token refresh is idempotent"
  ]
}
```

**Use case**: Standardized task format, integration with GitHub issues

---

## Session Layout (After Starting)

### Tmux Window Layout
```
┌───────────────────────────────────────────────────────────────┐
│                                                               │
│  COORDINATOR PANE (Main - 60%)      │ SUBAGENT PANELS (40%)  │
│  ┌──────────────────────────────┐   │ ┌────────────────────┐ │
│  │ Phase: 2 (Research)         │   │ │ [1] Researcher     │ │
│  │ Status: In Progress          │   │ │     (Active)       │ │
│  │                              │   │ │                    │ │
│  │ Agent Status:               │   │ │ Searching patterns │
│  │ ✓ Researcher: Working       │   │ │ in codebase...     │ │
│  │ • Implementer: Waiting      │   │ │                    │ │
│  │ • Lens: Waiting             │   │ │ Press Alt+2 for    │ │
│  │ • Sentinel: Waiting         │   │ │ Implementer        │ │
│  │ • Anchor: Waiting           │   │ │                    │ │
│  │                              │   │ └────────────────────┘ │
│  │ [Type to input findings      │   │                        │
│  │  or press '?' for help]      │   │ [Alt+1 Researcher]    │
│  │                              │   │ [Alt+2 Implementer]   │
│  └──────────────────────────────┘   │ [Alt+3 Lens]          │
│                                     │ [Alt+4 Sentinel]      │
│                                     │ [Alt+5 Anchor]        │
│                                     │ [q to quit]           │
└───────────────────────────────────────────────────────────────┘
```

### Key Bindings
- **Alt+1** → Focus Researcher pane
- **Alt+2** → Focus Implementer pane
- **Alt+3** → Focus Lens (Quality) pane
- **Alt+4** → Focus Sentinel (Security) pane
- **Alt+5** → Focus Anchor (Ops) pane
- **Alt+C** → Return to Coordinator pane
- **Q** → Quit workflow (with confirmation)
- **Space** → Pause/Resume workflow
- **?** → Help menu

---

## Implementation Scripts

### `scripts/start-workflow.sh` (Main entry point)

```bash
#!/bin/bash
# Main entry point for starting a workflow
# Usage:
#   ./start-workflow.sh --task "..." [--provider claude] [--budget 100000]
#   ./start-workflow.sh [--interactive]
#   ./start-workflow.sh --file task.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Defaults
TASK=""
PROVIDER="claude"
BUDGET=100000
INTERACTIVE=false
FILE=""
MODE="auto"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --task) TASK="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --interactive) INTERACTIVE=true; shift ;;
    --file) FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Determine mode
if [[ -n "$FILE" ]]; then
  MODE="file"
  # Load task from file
  TASK=$(jq -r '.title + "\n" + .description' "$FILE")
elif [[ -n "$TASK" ]]; then
  MODE="explicit"
elif [[ "$INTERACTIVE" == true ]]; then
  MODE="interactive"
else
  MODE="interactive"  # Default
fi

# Generate workflow ID
WORKFLOW_ID="wf-$(date +%Y%m%d-%H%M%S)-$(uuidgen | cut -c1-8)"

# Create session and spawn agents
# (Implementation continues in Phase 4.4)

echo "✅ Workflow started: $WORKFLOW_ID"
echo "Provider: $PROVIDER"
echo "Budget: $BUDGET tokens"
```

### `scripts/tmux-coordinator-session.sh` (Spawns tmux layout)

```bash
#!/bin/bash
# Spawn tmux session with Coordinator + 5 agent panes

SESSION_NAME=$1
WORKFLOW_ID=$2
TASK=$3

# Create new session with Coordinator main pane
tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50

# Split into main (60%) + side (40%)
tmux split-window -h -p 40

# Main pane: Coordinator
tmux select-pane -t 0
tmux send-keys -t 0 "bash $SCRIPT_DIR/coordinator-runner.sh --workflow $WORKFLOW_ID --task '$TASK'" Enter

# Side pane: Spawn agent panes
for i in 1 2 3 4 5; do
  if [[ $i -gt 1 ]]; then
    tmux split-window -v -p 50 -t 1
  fi
  
  AGENT_NAME=$(["researcher", "implementer", "lens", "sentinel", "anchor"][$((i-1))])
  tmux send-keys -t 1.$((i-1)) "bash $SCRIPT_DIR/agent-runner.sh --agent $AGENT_NAME --workflow $WORKFLOW_ID" Enter
done

# Set key bindings
tmux bind-key -T prefix '1' select-pane -t 1.0
tmux bind-key -T prefix '2' select-pane -t 1.1
tmux bind-key -T prefix '3' select-pane -t 1.2
tmux bind-key -T prefix '4' select-pane -t 1.3
tmux bind-key -T prefix '5' select-pane -t 1.4
tmux bind-key -T prefix 'c' select-pane -t 0

# Attach to session
tmux attach-session -t "$SESSION_NAME"
```

---

## User Experience Flow

### Scenario 1: New Issue (Explicit Task)

```bash
$ ./scripts/start-workflow.sh --task "Implement OAuth 2.0 for API" --provider claude --budget 150000

✅ Workflow started: wf-20260529-001
Opening tmux session...

[TMUX SESSION OPENS with Coordinator pane active]

Coordinator: Phase 1 - Task Intake
  Problem: Implement OAuth 2.0 for API
  Scope: API authentication system
  Priority: High
  Estimated effort: Medium
  
  ✓ Parsing complete. Starting Phase 2...

Researcher: Phase 2 - Research
  Searching for OAuth 2.0 patterns in codebase...
  Found 3 related implementations
  Checking GitHub issues...

[User presses Alt+1 to inspect Researcher pane]
[Sees detailed research findings in Researcher pane]

[User presses Alt+C to return to Coordinator]

Coordinator: Phase 3 - Implementer Dispatch
  Asking Implementer to draft implementation plan...

[Workflow continues, user can navigate between panes anytime]
```

### Scenario 2: Interactive Exploration

```bash
$ ./scripts/start-workflow.sh

[TMUX SESSION OPENS]

📝 Enter task description (or 'help' for examples):
> 

[User types task]
> Fix token refresh race condition

✅ Task received.

[Coordinator immediately starts orchestration]
[User can navigate panes during execution]
```

### Scenario 3: Batch Processing (Script Integration)

```bash
#!/bin/bash
# Batch process multiple tasks

TASKS=(
  "Fix auth middleware"
  "Add rate limiting"
  "Implement caching"
)

for task in "${TASKS[@]}"; do
  ./scripts/start-workflow.sh --task "$task" --provider claude --budget 80000
  # System starts workflow, script continues
done
```

---

## Configuration

### Environment Variables
```bash
ANTHROPIC_API_KEY=sk-ant-...
GITHUB_TOKEN=ghp_...
LLM_PROVIDER=claude  # or github-copilot
LLM_TIMEOUT=300      # seconds
LLM_BUDGET=100000    # tokens per task
```

### Default Config from `copilot-config.json`
- Provider defaults to Claude
- Budget defaults to 100K tokens
- Timeout defaults to 300 seconds

---

## Error Handling

### If Tmux Not Available
```bash
Error: tmux not found. Install: brew install tmux
```

### If LLM API Unavailable
```bash
Error: Cannot reach Claude API (ANTHROPIC_API_KEY not set)
Set: export ANTHROPIC_API_KEY=sk-ant-...
```

### If Budget Exceeded
```bash
⚠️ Token budget exceeded (110K / 100K)
Workflow pausing. Options:
  [1] Escalate to human
  [2] Increase budget and continue
  [3] Stop and review findings so far
```

---

## Next: Implementation in Phase 4.4

Once Phase 4.4 (Tmux Layout) is complete, `start-workflow.sh` will fully functional:

- ✅ Parse arguments
- ✅ Generate workflow ID
- ✅ Create tmux session
- ✅ Spawn Coordinator + agents
- ✅ Manage key bindings
- ✅ Handle user interaction
- ✅ Return workflow ID for monitoring

---

## Documentation for Users

Quick reference card will be created showing:
- How to start workflow
- Key bindings
- How to read agent panes
- How to pause/resume
- How to view results after completion
