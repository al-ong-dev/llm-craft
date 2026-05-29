# 📖 User Guide - Multi-Agent Workflow System

**For**: End users running workflows  
**Status**: Production Ready  
**Phase**: 4 (LLM Backend)  

---

## 🎯 What This System Does

Submit a task (problem, bug, feature request, analysis) and the system:
1. Parses your task across 9 specialized phases
2. Routes to 6 agents (Coordinator + 5 specialists)
3. Each agent reviews with expertise (code, security, reliability, quality)
4. Agents consult each other for second opinions
5. All agents vote on the best decision
6. If unanimous: executes and reports results
7. If conflict: escalates for human review

Result: Expert-level analysis from multiple perspectives with complete audit trail.

---

## 🚀 Quick Start

### The Fastest Way (1 minute)

```bash
./scripts/start-workflow.sh --task "Fix the login bug"
```

The system will:
- Ask for clarification if needed
- Generate expert analysis
- Show results when done

### Example Tasks

```bash
# Bug fix
./scripts/start-workflow.sh --task "Fix token refresh race condition in mobile app"

# Feature request
./scripts/start-workflow.sh --task "Add OAuth 2.0 support to authentication service"

# Code review
./scripts/start-workflow.sh --task "Review PR #456 for quality and security issues"

# Analysis
./scripts/start-workflow.sh --task "Analyze performance bottleneck in database queries"
```

---

## 💻 Three Ways to Submit Tasks

### Method 1: CLI (Fastest)

```bash
./scripts/start-workflow.sh --task "Your task here"
```

Best for: Quick tasks, automation, scripts

### Method 2: File (Structured)

Create `my-task.json`:
```json
{
  "id": "my-unique-id",
  "title": "Brief summary",
  "description": "Detailed description of the task",
  "context": {
    "priority": "high",
    "impact": "5% of users affected",
    "related_issues": ["#123", "#456"]
  },
  "code_snippet": {
    "file": "src/auth/token-refresh.ts",
    "language": "typescript",
    "content": "function refreshToken() { ... }"
  },
  "success_criteria": [
    "Criterion 1",
    "Criterion 2"
  ]
}
```

Then run:
```bash
./scripts/start-workflow.sh --file my-task.json
```

Best for: Complex tasks, code reviews, formal submissions

### Method 3: Interactive (Flexible)

```bash
./scripts/start-workflow.sh
```

Then type your task description. Press Ctrl+D when done.

Best for: Exploratory work, detailed input, multi-line descriptions

---

## 📊 What Happens During Execution

### The 9 Phases

```
Phase 1: INTAKE (parsing)
  → Coordinator parses task into structured format

Phase 2: RESEARCH (context gathering)
  → Researcher gathers information about the problem
  → Parallel execution possible

Phase 3: PLANNING (solution design)
  → Implementer designs solution approach

Phase 4: QUALITY REVIEW (code correctness)
  → Lens checks implementation for quality

Phase 5: SECURITY REVIEW (vulnerability check)
  → Sentinel assesses security risks

Phase 6: OPS REVIEW (reliability check)
  → Anchor evaluates operational reliability

Phase 7: CONSENSUS DECISION (voting)
  → All 6 agents vote on decision
  → Unanimous vote required to proceed

Phase 8: EXECUTION (apply changes)
  → Implementer executes approved changes

Phase 9: DELIVERY (verification & results)
  → All agents verify output
  → Results presented to user
```

**Total Time**: 5-15 minutes for all 9 phases

---

## 👥 The 6 Agents

### Coordinator
- **Role**: Orchestrates workflow, manages phase transitions
- **Expertise**: Process flow, decision aggregation
- **Asks**: "Should we proceed to next phase?"

### Researcher
- **Role**: Gathers context, analyzes problems
- **Expertise**: Investigation, research, information synthesis
- **Asks**: "What are all the relevant factors?"

### Implementer
- **Role**: Designs and implements solutions
- **Expertise**: Coding, architecture, implementation
- **Asks**: "How should we implement this?"

### Lens (Quality Reviewer)
- **Role**: Ensures code quality and correctness
- **Expertise**: Code style, testing, maintainability
- **Asks**: "Is this well-written and correct?"

### Sentinel (Security Reviewer)
- **Role**: Evaluates security implications
- **Expertise**: Authentication, authorization, vulnerabilities
- **Asks**: "Are there security risks?"

### Anchor (Ops Reviewer)
- **Role**: Checks operational reliability
- **Expertise**: Deployment, monitoring, disaster recovery
- **Asks**: "Can we operate this in production?"

---

## 🗣️ Agent Consultations

During analysis, agents may consult each other:

```
Implementer → "Sentinel, is this secure?"
Sentinel   ← "Yes, you handle credentials properly. +1 vote."

Implementer → "Anchor, can we deploy this?"
Anchor     ← "Yes, with monitoring in place. +1 vote."
```

All consultations are logged and tracked. This is the **RPC (Remote Procedure Call)** protocol in action.

---

## 📋 Understanding Results

### Vote Decision

Each agent votes on: **proceed**, **block**, or **escalate**

```json
{
  "agent_id": "sentinel",
  "phase": "5",
  "decision": "proceed",
  "confidence": "high",
  "rationale": "No security vulnerabilities detected. Code uses bcrypt for password hashing and JWT tokens with proper expiration."
}
```

**Decision Types**:
- **proceed**: Agent approves the decision
- **block**: Agent has concerns, recommends stopping
- **escalate**: Uncertain, escalate for human review

### Unanimous Voting

**Phase 7 (Consensus)** requires **all 6 agents must vote "proceed"** to continue.

If any agent votes "block" or "escalate":
- Workflow pauses
- Issue is logged for human review
- Recommendation provided
- User can address concerns and retry

### Confidence Levels

Each vote includes confidence:
- **high**: Agent is very confident (>80% certainty)
- **medium**: Agent is reasonably confident (50-80%)
- **low**: Agent is uncertain (<50%)

Low confidence votes trigger human escalation.

---

## 📂 Output Files

After running a workflow, check these directories:

### Workflow Logs (`workflow-logs/`)

```bash
# Human-readable log
wf-20260529-1234.log

# Vote decisions (JSON, one per line)
wf-20260529-1234-votes.jsonl

# Agent consultations
wf-20260529-1234-consultations.jsonl

# LLM requests and responses
wf-20260529-1234-llm-requests.jsonl

# Token usage tracking
wf-20260529-1234-tokens.jsonl
```

### Workflow State (`workflow-state/`)

```bash
# Complete workflow state (JSON)
wf-20260529-1234.json
```

### Example: Viewing Results

```bash
# See all votes
jq '.[] | {agent: .agent_id, decision: .decision, confidence: .confidence}' \
  workflow-logs/wf-*-votes.jsonl

# See consultations
jq '.[] | select(.type=="consultation_request") | {from: .from, to: .to, question: .question}' \
  workflow-logs/wf-*-consultations.jsonl

# See final status
jq '.status' workflow-state/wf-*.json
```

---

## 🔍 Viewing Live Progress

### Watch Main Log (Recommended)

```bash
# In one terminal, start workflow
./scripts/start-workflow.sh --task "Your task"

# In another terminal, watch logs
tail -f workflow-logs/wf-*.log
```

### Watch Decisions

```bash
# See votes as they happen
tail -f workflow-logs/wf-*-votes.jsonl | jq '.decision'
```

### See Consultations

```bash
# Watch agents ask each other
tail -f workflow-logs/wf-*-consultations.jsonl | jq '.question'
```

### Monitor Token Usage

```bash
# See token consumption per phase
tail -f workflow-logs/wf-*-tokens.jsonl
```

---

## 💡 Tips & Best Practices

### Get Better Results

1. **Be Specific**
   - ❌ "Fix the app"
   - ✅ "Fix token refresh timeout on mobile app causing 401 errors"

2. **Provide Context**
   - Include priority, impact, related issues
   - Mention constraints or requirements
   - Provide code snippets if relevant

3. **Clear Success Criteria**
   - Define what "done" means
   - Include test coverage requirements
   - List performance expectations

### Task Structure (File Mode)

```json
{
  "title": "One-line summary",
  "description": "2-3 paragraph detailed description",
  "context": {
    "priority": "high|medium|low",
    "impact": "How many users/systems affected?",
    "deadline": "When is it needed?",
    "related_issues": ["#123", "#456"]
  },
  "code_snippet": {
    "file": "path/to/file",
    "language": "typescript|python|go|java",
    "content": "Relevant code excerpt"
  },
  "success_criteria": [
    "Measurable criterion 1",
    "Measurable criterion 2",
    "Measurable criterion 3"
  ]
}
```

### Monitor Results

- Check for unanimous votes (all "proceed")
- Review any "block" or "escalate" votes
- Read agent rationales for recommendations
- View consultation logs for reasoning
- Monitor token usage to stay in budget

---

## ⚠️ Common Scenarios

### Workflow Takes Too Long

**Normal behavior**: 5-15 minutes is expected

If longer:
1. Check network (API latency)
2. Monitor token usage (may hit budget limit)
3. Check logs for errors: `tail -f workflow-logs/wf-*.log`

### All Votes Say "Escalate"

This is the safe fallback. Likely causes:
1. API key issue - verify `echo $ANTHROPIC_API_KEY`
2. Network problem - test `curl https://api.anthropic.com`
3. Invalid config - check `copilot-config.json`

See [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) troubleshooting section.

### Vote Split (Not Unanimous)

If agents disagree:
1. Read the rationales for each vote
2. Consult the consultation logs to see reasoning
3. Modify task to address concerns
4. Re-submit workflow

This is working as designed - agents catch issues humans might miss.

### Token Budget Exceeded

If you see "escalate" due to budget:
1. Simplify task (shorter description)
2. Remove code snippets (unless critical)
3. Increase budget in config: `token_budget.total_tokens_per_task`
4. Retry workflow

---

## 📈 Advanced Usage

### Batch Processing

```bash
# Process multiple tasks
for task in tasks/*.json; do
  ./scripts/start-workflow.sh --file "$task"
  sleep 60  # Wait between tasks
done
```

### Custom Token Budget

```bash
./scripts/start-workflow.sh --file my-task.json --budget 200000
```

### With Verbose Debugging

```bash
./scripts/start-workflow.sh --task "..." --verbose
```

Outputs debug information for troubleshooting.

### Analyze Results in Batch

```bash
# Extract all decisions
jq -s '.[].decision | group_by(.) | map({decision: .[0], count: length})' \
  workflow-logs/*-votes.jsonl

# Find all escalations
jq '.[] | select(.decision == "escalate")' workflow-logs/*-votes.jsonl

# Summary statistics
jq -s '{
  total_phases: (.[].phase | max),
  total_agents: (.[].agent_id | unique | length),
  escalations: ([.[] | select(.decision == "escalate")] | length)
}' workflow-logs/*-votes.jsonl
```

---

## 🎓 Example Workflows

### Example 1: Bug Fix

```bash
./scripts/start-workflow.sh --task "Fix race condition in token refresh endpoint causing 401 errors for 5% of mobile users. Symptoms occur after login succeeds but token refresh is called concurrently."
```

**Expected Result**:
- Researcher provides context on race conditions
- Implementer proposes locking or retry mechanism
- Lens reviews test coverage
- Sentinel checks auth flow security
- Anchor evaluates deployment impact

### Example 2: Security Review

```bash
./scripts/start-workflow.sh --file security-review.json
```

**security-review.json**:
```json
{
  "title": "Review authentication service for vulnerabilities",
  "description": "Recently refactored auth service. Need security assessment before production.",
  "context": {
    "priority": "high",
    "impact": "Affects all user logins"
  },
  "code_snippet": {
    "file": "src/auth/service.ts",
    "language": "typescript",
    "content": "export class AuthService { ... }"
  },
  "success_criteria": [
    "No OWASP Top 10 vulnerabilities",
    "Passwords encrypted with bcrypt",
    "API tokens have expiration",
    "Rate limiting in place"
  ]
}
```

**Expected Result**:
- Sentinel leads security assessment
- Implementer explains design decisions
- Lens checks code correctness
- Anchor reviews logging and monitoring
- Unanimous vote required for approval

---

## ✅ Success Indicators

A successful workflow has:
- ✅ All 9 phases complete
- ✅ All 6 agents voted "proceed"
- ✅ Unanimous consensus reached
- ✅ Phase 9 shows verified results
- ✅ Token usage within budget
- ✅ Complete audit trail in logs

---

## 🆘 Getting Help

### View Documentation

- [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) - Setup and configuration
- [PHASE4.11-FINAL-REPORT.md](PHASE4.11-FINAL-REPORT.md) - Technical details
- [RPC-EXPLANATION.md](RPC-EXPLANATION.md) - How consultations work

### Check Logs

```bash
# Last 50 lines of main log
tail -50 workflow-logs/wf-*.log

# Find errors
grep -i error workflow-logs/wf-*.log

# See all escalations
grep escalate workflow-logs/wf-*-votes.jsonl
```

### Troubleshooting Checklist

- [ ] API key is set: `echo $ANTHROPIC_API_KEY`
- [ ] Network is working: `curl https://api.anthropic.com`
- [ ] Config files exist: `ls copilot-*.json`
- [ ] Logs directory is writable: `ls -ld workflow-logs/`
- [ ] Tested with example: `./scripts/start-workflow.sh --file example-task.json`

---

**Status**: ✅ Production Ready  
**Last Updated**: 2026-05-29  
**Support**: See [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) for troubleshooting

