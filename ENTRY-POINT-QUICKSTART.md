# 🚀 User Entry Point - Quick Reference

## How Users Start a Workflow

### Option 1: Explicit Task (Best for Automation)
```bash
./scripts/start-workflow.sh --task "Fix token refresh race condition" --provider claude --budget 100000
```

### Option 2: Interactive Input (Best for Exploration)
```bash
./scripts/start-workflow.sh
# → Prompts: "Enter task description: _"
# User types task → Coordinator starts
```

### Option 3: From File (Best for Integration)
```bash
./scripts/start-workflow.sh --file task.json
```

---

## What Happens Inside

```
1. Script validates inputs
2. Generates workflow ID: wf-20260529-001
3. Creates tmux session: llm-coordinator-wf-20260529-001
4. Spawns Coordinator + 5 agent panes
5. Feeds task to Coordinator
6. Coordinator starts Phase 1 (Parse Task)
7. User can switch between panes:
   - Alt+C: Coordinator (primary, status view)
   - Alt+1: Researcher (findings)
   - Alt+2: Implementer (plan)
   - Alt+3: Lens (quality review)
   - Alt+4: Sentinel (security review)
   - Alt+5: Anchor (ops review)
   - Q: Quit workflow
```

---

## Tmux Session Layout

```
┌─────────────────────────────────────────────┐
│ COORDINATOR (Main - 60%)  │ AGENTS (40%)    │
├──────────────────────────┼─────────────────┤
│ Phase: 2 (Research)      │ [1] Researcher  │
│ Status: In Progress      │ ✓ Working       │
│                          │                 │
│ Agent Status:            │ [2] Implementer │
│ ✓ Researcher: Working    │ • Waiting       │
│ • Implementer: Waiting   │                 │
│ • Lens: Waiting          │ [3] Lens        │
│ • Sentinel: Waiting      │ • Waiting       │
│ • Anchor: Waiting        │                 │
│                          │ [4] Sentinel    │
│ Task: Fix token refresh  │ • Waiting       │
│ Phase progress: [===]    │                 │
│                          │ [5] Anchor      │
│                          │ • Waiting       │
└──────────────────────────┴─────────────────┘
```

---

## Configuration

Set environment before running:
```bash
# Set LLM provider
export ANTHROPIC_API_KEY=sk-ant-...  # For Claude
# OR
export GITHUB_TOKEN=ghp_...           # For GitHub Copilot

# Optional: Set defaults
export LLM_PROVIDER=claude            # claude or github-copilot
export LLM_BUDGET=100000              # tokens per task
export LLM_TIMEOUT=300                # seconds
```

---

## Examples

### Example 1: Fix a Bug
```bash
./scripts/start-workflow.sh --task "Fix 401 error in token refresh endpoint" --provider claude
```

### Example 2: Implement a Feature
```bash
./scripts/start-workflow.sh --task "Add OAuth 2.0 authentication to API" --provider claude --budget 150000
```

### Example 3: Code Review
```bash
./scripts/start-workflow.sh --task "Review PR #456 for security and quality issues" --provider claude
```

### Example 4: Interactive Mode
```bash
./scripts/start-workflow.sh
# → "Enter task description: "
# → User types: "Optimize database queries in user service"
# → Coordinator starts orchestration
```

---

## What Coordinator Does (9-Phase Workflow)

1. **Phase 1 (Intake)**: Parse task → scope, constraints, priority
2. **Phase 2 (Research)**: Researcher gathers context
3. **Phase 3 (Plan)**: Implementer drafts implementation
4. **Phase 4 (Quality)**: Lens reviews for quality issues
5. **Phase 5 (Security)**: Sentinel reviews for security issues
6. **Phase 6 (Ops)**: Anchor reviews for operational concerns
7. **Phase 7 (Decision)**: Aggregate votes → proceed/escalate/block
8. **Phase 8 (Execute)**: Implement changes (if consensus)
9. **Phase 9 (Verify)**: Verify success criteria met

---

## Key Features

✅ **Single entry point** - One command to start
✅ **Real-time visibility** - Watch agents reason in parallel
✅ **Interactive navigation** - Switch between agent panes
✅ **Consensus-based** - All agents must agree
✅ **Token budgeted** - Cost control built-in
✅ **Audit trail** - Full history logged
✅ **Scalable** - Can handle large tasks

---

## Status

**Current**: Entry point architecture designed  
**Next**: Implement `start-workflow.sh` and tmux layout (Phase 4.4)  
**When ready**: Users will run `./scripts/start-workflow.sh --task "..."` and see full orchestration
