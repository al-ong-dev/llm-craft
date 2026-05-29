# Multi-Agent Workflow: Integration Guide

This document explains how to integrate the consensus workflow with your LLM backend, monitoring tools, and existing scripts.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                  Workflow Orchestrator                   │
│           (workflow-orchestrator.sh)                     │
│                                                          │
│  • Manages 9 phases                                      │
│  • Creates tmux session with 5 panes                     │
│  • Enforces unanimous consensus                          │
│  • Escalates on dissent/timeout                          │
└──────────────────┬──────────────────────────────────────┘
                   │
     ┌─────────────┼─────────────┐
     │             │             │
┌────▼────┐  ┌─────▼────┐  ┌────▼────┐
│ Agent   │  │  State   │  │ Voting  │
│ Runners │  │Mgmt (SQL)│  │ (JSON)  │
│ (tmux)  │  │          │  │         │
└────┬────┘  └────┬─────┘  └────┬────┘
     │            │             │
     └────────────┼─────────────┘
                  │
        ┌─────────▼──────────┐
        │  Consensus Engine   │
        │ (Check unanimous    │
        │  vote, escalate)    │
        └─────────┬───────────┘
                  │
     ┌────────────┼────────────┐
     │            │            │
  PROCEED    ESCALATE      BLOCKED
     │            │            │
  Execute    Postpone    Retry
             Notify
```

## Integration Points

### 1. Agent LLM Backend

**Current State**: Mock votes (agent-runner.sh hardcodes "proceed")

**Integration Point**: `agent-runner.sh` functions `run_agent_for_phase()` and `submit_vote()`

**How to integrate**:

```bash
# Option A: Claude API
run_agent_for_phase() {
  local agent=$1 phase=$2 persona_file=$3
  
  # Build prompt with persona + context
  local prompt=$(cat <<EOF
$(cat "$persona_file")

PHASE $phase INSTRUCTION: $(get_agent_instruction "$agent" "$phase")

CONTEXT: $(cat "$CONTEXT_FILE")

Please analyze and respond with JSON: {decision, confidence, rationale, findings}
EOF
)
  
  # Call Claude
  local response=$(curl -s https://api.anthropic.com/v1/messages \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "{\"model\":\"claude-opus\",\"prompt\":\"$prompt\",\"max_tokens\":2000}" \
    | jq -r '.content[0].text')
  
  # Parse response as JSON and submit vote
  echo "$response" | jq -r '@json' | while read -r vote; do
    submit_vote "$agent" "$(echo "$vote" | jq -r .decision)" \
                         "$(echo "$vote" | jq -r .confidence)" \
                         "$(echo "$vote" | jq -r .rationale)"
  done
}
```

**Option B**: Use local Ollama (from llm-craft)
```bash
# Use existing ollama-task.sh
./scripts/ollama-task.sh "Analyze this code..." ./context.txt llama3.1:8b
```

**Option C**: Use Python agent wrapper
```bash
# Create agent-python-wrapper.py
# Receives: agent_id, phase, workflow_id, context_file
# Returns: JSON vote
# Can use: Claude, GPT, local models, or custom logic
```

### 2. State Management (SQL Integration)

**Current**: JSON files in workflow-state/

**SQL Integration**: All state sync'd to database

```sql
-- Track workflows
CREATE TABLE workflows (
  id TEXT PRIMARY KEY,
  created_at TIMESTAMP,
  status TEXT,
  current_phase INTEGER,
  task_json JSON
);

-- Track votes
CREATE TABLE agent_votes (
  workflow_id TEXT,
  phase INTEGER,
  agent_id TEXT,
  decision TEXT,
  confidence TEXT,
  rationale TEXT,
  findings JSON,
  submitted_at TIMESTAMP,
  PRIMARY KEY (workflow_id, phase, agent_id)
);

-- Track escalations
CREATE TABLE escalations (
  workflow_id TEXT PRIMARY KEY,
  phase_reached INTEGER,
  reason TEXT,
  escalated_at TIMESTAMP,
  human_action_required BOOLEAN,
  resolved BOOLEAN,
  resolution_notes TEXT
);
```

**Usage**: Query workflow history, audit trails, escalation patterns

### 3. Tmux Pane Integration

**Current**: agent-runner.sh sends commands to tmux panes

**Extension Options**:

#### Option A: Health Monitoring
```bash
# Monitor pane health
monitor_pane() {
  local pane=$1
  while true; do
    if ! tmux capture-pane -t "agent-consensus:0.$pane" -p | grep -q "ERROR"; then
      echo "Pane $pane: OK"
    else
      echo "Pane $pane: FAILED"
      escalate_workflow "agent_failure"
    fi
    sleep 5
  done
}
```

#### Option B: Log Aggregation
```bash
# Capture pane output to logs
tmux capture-pane -t "agent-consensus:0.0" -p > logs/researcher-pane.log
# Useful for debugging, auditing
```

#### Option C: Remote Monitoring
```bash
# Stream tmux to WebSocket for live dashboard
tmux capture-pane -t "agent-consensus:0.0" -p | \
  jq -R -s -c 'split("\n") | .[0:100]' | \
  curl -X POST ws://dashboard/pane-update -d @-
```

### 4. Escalation Notifications

**Current**: Escalation logged to file, human reviews manually

**Integration Options**:

```bash
# Option A: Email notification
escalate_workflow() {
  local phase=$1 reason=$2
  
  # Send email
  mail -s "Workflow Escalation: $reason" ops@company.com <<EOF
Workflow $WORKFLOW_ID escalated at phase $phase.
Reason: $reason
Review: ./workflow-state-manager.sh escalation $WORKFLOW_ID
EOF
}

# Option B: Slack notification
escalate_workflow() {
  curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK \
    -H 'Content-Type: application/json' \
    -d "{\"text\":\"Workflow escalated: $reason\"}"
}

# Option C: Jira ticket creation
escalate_workflow() {
  curl -X POST https://jira.company.com/rest/api/3/issues \
    -H "Authorization: Bearer $JIRA_TOKEN" \
    -d "{\"fields\":{\"project\":\"OPS\",\"summary\":\"Workflow escalation\"}}"
}
```

### 5. Integration with Existing llm-craft Tools

**Use existing scripts in agent analysis**:

```bash
# In agent-runner.sh, when Researcher runs:
run_agent_for_phase() {
  local agent="researcher" phase=2
  
  # Use smart-search to find related code
  ./scripts/smart-search.sh "token refresh authentication" --top 5 \
    > context-search-results.json
  
  # Use knowledge-search for Jira/Confluence context
  ./scripts/knowledge-search.sh "token refresh race condition" --top 3 \
    > context-jira-confluence.json
  
  # Merge context and send to agent
  jq -s 'add' context-search-results.json context-jira-confluence.json \
    > merged-context.json
  
  # Agent analyzes merged context...
}
```

### 6. Consensus Decision Logic

**Custom consensus rules** (beyond unanimous):

```bash
# Modify workflow-orchestrator.sh check_consensus()
check_consensus() {
  local phase=$1
  local votes=$(jq ".votes[] | select(.phase == $phase)" "$VOTES_FILE")
  
  # Custom rules by phase:
  case $phase in
    5) # Security review - must be unanimous
       grep -q '"decision": "blocked"' <<< "$votes" && return 1
       ;;
    4) # Quality review - majority OK (3/5)
       local proceed=$(echo "$votes" | jq 'select(.decision == "proceed") | length')
       [[ $proceed -ge 3 ]] && return 0 || return 1
       ;;
    *) # Other phases - unanimous
       [[ $(echo "$votes" | jq -s 'map(select(.decision == "proceed")) | length') -eq 5 ]]
       ;;
  esac
}
```

### 7. Resume Workflow with Modifications

**When human overrides a blocker**:

```bash
# Store human decision
./scripts/workflow-state-manager.sh update-escalation \
  --workflow wf-123 \
  --phase 5 \
  --human-decision "Accept Sentinel's concern, added rate-limit" \
  --resolution-notes "Modified src/auth/middleware to check X-Rate-Limit header"

# Resume from phase 5 (Sentinel re-votes with context)
./scripts/workflow-orchestrator.sh --resume wf-123 --from-phase 5
```

### 8. Audit & Compliance

**All workflow decisions are auditable**:

```bash
# Generate compliance report
./scripts/workflow-state-manager.sh export wf-123 json | \
  jq '{
    workflow_id,
    phases: (.votes | group_by(.phase) | map({
      phase: .[0].phase,
      votes: map({agent_id, decision, confidence})
    })),
    escalations: (.escalations // [])
  }' > compliance-report.json
```

## Migration Path

### Phase 1: Validate Architecture (Current)
- ✅ Mock agents (all vote proceed)
- ✅ Workflow orchestration works
- ✅ Consensus detection works
- ✅ Escalation logging works

### Phase 2: Add Real Agent Decisions
- [ ] Integrate one agent (e.g., Researcher) with Claude API
- [ ] Test consensus with mixed mock/real votes
- [ ] Add retry/fallback logic

### Phase 3: Full Integration
- [ ] All 5 agents use real LLMs
- [ ] SQL state tracking enabled
- [ ] Notifications integrated (email/Slack)
- [ ] Existing llm-craft tools integrated

### Phase 4: Production Hardening
- [ ] Health monitoring for all agents
- [ ] Automatic recovery on failures
- [ ] Performance optimization (parallel agent execution)
- [ ] Cost tracking (API calls per workflow)

## Example: Researcher Agent with Claude

```bash
#!/bin/bash
# researcher-agent.sh - Example real agent implementation

AGENT_ID="researcher"
PHASE="$1"
WORKFLOW_ID="$2"
CONTEXT_FILE="$3"

get_researcher_instruction() {
  case $PHASE in
    1) echo "Parse this task and identify: problem, scope, constraints, success criteria." ;;
    2) echo "Research this problem: find existing code patterns, prior issues, feasible solutions." ;;
  esac
}

# Read task context
context=$(cat "$CONTEXT_FILE")
instruction=$(get_researcher_instruction "$PHASE")

# Read researcher persona
persona=$(cat agents/personas/researcher.md)

# Call Claude
prompt="$persona

INSTRUCTION: $instruction

CONTEXT:
$context

Please respond with JSON: {decision, confidence, rationale, findings[], questions[]}"

response=$(curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{\"model\":\"claude-opus\",\"max_tokens\":2000,\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}]}" \
  | jq -r '.content[0].text')

# Parse and submit vote
decision=$(echo "$response" | jq -r '.decision')
confidence=$(echo "$response" | jq -r '.confidence')
rationale=$(echo "$response" | jq -r '.rationale')

# Append to votes
jq --arg wf "$WORKFLOW_ID" --arg ph "$PHASE" --arg ag "$AGENT_ID" \
   --arg dec "$decision" --arg conf "$confidence" --arg rat "$rationale" \
   '.votes += [{
     workflow_id: $wf,
     phase: ($ph | tonumber),
     agent_id: $ag,
     decision: $dec,
     confidence: $conf,
     rationale: $rat,
     timestamp: (now | todate)
   }]' workflow-state/${WORKFLOW_ID}-votes.json > temp.json && \
   mv temp.json workflow-state/${WORKFLOW_ID}-votes.json
```

## Configuration Files

### `.env` for credentials

```bash
# Anthropic
ANTHROPIC_API_KEY=sk-ant-...

# OpenAI
OPENAI_API_KEY=sk-...

# Local Ollama
OLLAMA_BASE_URL=http://127.0.0.1:11434

# Atlassian (for knowledge-search integration)
ATLASSIAN_BASE_URL=https://company.atlassian.net
ATLASSIAN_EMAIL=agent@company.com
ATLASSIAN_API_TOKEN=...

# Notifications
SLACK_WEBHOOK=https://hooks.slack.com/services/...
JIRA_WEBHOOK=...
SMTP_HOST=mail.company.com
SMTP_USER=...
```

### `workflow-config.json` for behavior

```json
{
  "phases": {
    "1": { "timeout": 300, "required": true },
    "2": { "timeout": 300, "agent": "researcher", "required": true },
    "3": { "timeout": 300, "agent": "implementer", "required": true },
    "4": { "timeout": 300, "agent": "reviewer-quality", "required": true },
    "5": { "timeout": 300, "agent": "reviewer-security", "required": true },
    "6": { "timeout": 300, "agent": "ops", "required": true },
    "7": { "timeout": 120, "consensus_rule": "unanimous", "required": true },
    "8": { "timeout": 600, "agent": "implementer", "required": false },
    "9": { "timeout": 300, "consensus_rule": "majority", "required": false }
  },
  "escalation": {
    "notify_slack": true,
    "create_jira": true,
    "email_stakeholders": ["ops@company.com"]
  },
  "agents": {
    "researcher": { "backend": "claude-opus", "temperature": 0.7 },
    "implementer": { "backend": "claude-opus", "temperature": 0.3 },
    "reviewer-quality": { "backend": "claude-sonnet", "temperature": 0.5 },
    "reviewer-security": { "backend": "claude-opus", "temperature": 0.1 },
    "ops": { "backend": "claude-sonnet", "temperature": 0.5 }
  }
}
```

---

**Next**: Choose your LLM backend and start integrating agent-runner.sh with real AI decisions!
