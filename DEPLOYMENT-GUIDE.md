# 🚀 Deployment Guide - Phase 4 LLM Backend

**Status**: Production Ready  
**Phase**: 4 (LLM Backend)  
**Date**: 2026-05-29  

---

## 📋 Overview

This guide explains how to deploy and run the multi-agent LLM workflow system with real Claude API integration.

The system is fully functional and tested. Once deployed, it can:
- Accept workflow tasks via CLI, file, or interactive input
- Route to 6 specialized agents (Coordinator + 5 specialists)
- Generate LLM-based decisions using Claude API
- Support agent-to-agent consultations
- Enforce unanimous voting
- Track token usage and budget
- Log complete audit trail

---

## 🔐 Prerequisites

### Required Software
- **Bash**: 4.0 or higher
  ```bash
  bash --version  # Verify version
  ```

- **jq**: JSON command-line processor
  ```bash
  # Install jq
  apt-get install jq          # Linux/Termux
  brew install jq             # macOS
  ```

- **curl**: HTTP client (usually pre-installed)
  ```bash
  curl --version  # Verify
  ```

### Optional Software
- **tmux**: For visual agent pane layout (recommended)
  ```bash
  apt-get install tmux        # Linux/Termux
  brew install tmux           # macOS
  ```

### Required Credentials
- **ANTHROPIC_API_KEY**: Your Anthropic API key for Claude access
  - Get key from: https://console.anthropic.com/
  - Required quota: At least 100K tokens available
  - See "Configuration" section below for setup

### System Requirements
- **Disk Space**: 100 KB minimum (for logs and state)
- **Network**: Internet access to `api.anthropic.com`
- **Memory**: 50 MB minimum

---

## ⚙️ Configuration

### 1. Set Environment Variables

Required:
```bash
export ANTHROPIC_API_KEY="sk-ant-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Optional (defaults shown):
```bash
export LLM_PROVIDER="claude"              # Or: github_copilot
export LLM_BUDGET="100000"                # Tokens per task
```

### 2. Verify Configuration Files

The system comes with default configs. Verify they exist:

```bash
# Check main config
cat copilot-config.json | jq . | head -20

# Check prompts
cat copilot-prompts.json | jq '.coordinator' | head -10
```

### 3. Customize Configuration (Optional)

Edit `copilot-config.json` to adjust:

```json
{
  "llm_providers": {
    "claude": {
      "models": {
        "default": "claude-3-5-sonnet-20241022",
        "fast": "claude-3-5-haiku-20241022"
      },
      "timeouts": {
        "request_timeout_sec": 60,
        "read_timeout_sec": 120
      }
    }
  },
  
  "token_budget": {
    "total_tokens_per_task": 100000,
    "total_tokens_per_phase": 20000,
    "warn_at_percent": 80
  }
}
```

**Common Customizations**:
- Increase timeout if API calls are slow: `request_timeout_sec`
- Adjust token budget if running longer workflows: `total_tokens_per_task`
- Switch models (Haiku for speed, Sonnet for quality)

---

## 🎯 First-Time Setup

### Step 1: Verify Installation

```bash
# Navigate to project
cd /path/to/llm-craft

# Verify bash
bash --version

# Verify jq
jq --version

# Verify config files
ls -la copilot-config.json copilot-prompts.json
```

### Step 2: Set API Key

```bash
# Set your API key (one-time or add to .bashrc)
export ANTHROPIC_API_KEY="sk-ant-your-key-here"

# Verify it's set
echo $ANTHROPIC_API_KEY
```

### Step 3: Test Entry Point

```bash
# Show help
./scripts/start-workflow.sh --help

# Verify script is executable
ls -la ./scripts/start-workflow.sh
```

### Step 4: Run Example Task

```bash
# Load and process example task
./scripts/start-workflow.sh --file example-task.json

# Watch logs appear
tail -f workflow-logs/wf-*.jsonl
```

**Expected Output**:
```
✅ Workflow started: wf-20260529-1234
📍 Provider: claude
💰 Budget: 100000 tokens
📂 Logs: workflow-logs/wf-20260529-1234.log
📊 State: workflow-state/wf-20260529-1234.json
```

---

## 🚀 Running Workflows

### CLI Mode (Simplest)

```bash
./scripts/start-workflow.sh --task "Fix authentication bug in mobile app"
```

### File Mode (Structured)

Create a task file `my-task.json`:
```json
{
  "id": "my-auth-bug",
  "title": "Fix authentication race condition",
  "description": "Users report 401 errors after login",
  "context": {
    "priority": "high",
    "impact": "5% of users affected"
  },
  "success_criteria": [
    "All users can login without 401",
    "Auth tokens are idempotent"
  ]
}
```

Then run:
```bash
./scripts/start-workflow.sh --file my-task.json
```

### Interactive Mode (Flexible)

```bash
./scripts/start-workflow.sh --interactive

# Then type or paste your task description
# Press Ctrl+D when done
```

### With Custom Options

```bash
# Increase token budget
./scripts/start-workflow.sh --task "..." --budget 150000

# Use different provider
./scripts/start-workflow.sh --task "..." --provider github-copilot

# Verbose debugging
./scripts/start-workflow.sh --task "..." --verbose
```

---

## 📊 Monitoring Workflows

### View Live Logs

```bash
# Watch main workflow log
tail -f workflow-logs/wf-*.log

# Watch vote decisions
tail -f workflow-logs/wf-*-votes.jsonl

# Watch consultations
tail -f workflow-logs/wf-*-consultations.jsonl

# Watch token usage
tail -f workflow-logs/wf-*-tokens.jsonl
```

### Check Workflow State

```bash
# View latest workflow state
jq . workflow-state/wf-*.json | tail -50

# Check phases completed
jq '.phases | keys' workflow-state/wf-*.json

# See all votes so far
jq '.votes[] | {agent: .agent_id, decision: .decision}' workflow-state/wf-*.json
```

### List All Workflows

```bash
# List all workflows
ls -lh workflow-logs/ | grep "^-"

# Count workflows
ls -1 workflow-logs/wf-*.log | wc -l

# Latest workflow
ls -t workflow-logs/wf-*.log | head -1
```

---

## 🔍 Understanding Output

### Workflow Log (.log)

Human-readable progress:
```
═══════════════════════════════════════════════════════════════
Workflow: wf-20260529-1234
Started: 2026-05-29T15:35:41Z
Provider: claude
Budget: 100000 tokens
═══════════════════════════════════════════════════════════════

TASK:
Fix token refresh race condition in mobile app
```

### Vote Log (.jsonl)

Machine-readable decisions (one JSON per line):
```json
{"workflow_id":"wf-20260529-1234","phase":"1","agent_id":"researcher","decision":"proceed","confidence":"high","rationale":"..."}
{"workflow_id":"wf-20260529-1234","phase":"2","agent_id":"implementer","decision":"proceed","confidence":"high","rationale":"..."}
```

### Consultation Log (.jsonl)

Inter-agent discussions:
```json
{"workflow_id":"wf-20260529-1234","type":"consultation_request","from":"implementer","to":"sentinel","question":"Is this secure?"}
{"workflow_id":"wf-20260529-1234","type":"consultation_response","from":"sentinel","opinion":"Yes, passes security checks"}
```

### State File (.json)

Complete workflow state:
```json
{
  "workflow_id": "wf-20260529-1234",
  "status": "in_progress",
  "task": "Fix token refresh race condition",
  "phases": {
    "1_intake": {"status": "completed", "decision": "proceed"},
    "2_research": {"status": "in_progress"}
  },
  "votes": [...],
  "token_usage": {"phase_1": 450, "phase_2": 1200}
}
```

---

## ⚠️ Troubleshooting

### "API key missing" or 401 Error

```bash
# Verify API key is set
echo $ANTHROPIC_API_KEY

# It should show your key (starting with sk-ant-)
# If empty, set it:
export ANTHROPIC_API_KEY="sk-ant-your-key"

# Test API connection
curl -X POST https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "content-type: application/json" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"Hi"}]}' 2>/dev/null | jq '.error'

# If error shows, key is invalid. Get a new one from:
# https://console.anthropic.com/
```

### "jq: command not found"

```bash
# Install jq
apt-get install jq          # Linux/Termux
brew install jq             # macOS

# Verify
jq --version
```

### Workflow Hangs / Timeout

```bash
# Check if process is running
ps aux | grep start-workflow.sh

# Look at logs
tail -20 workflow-logs/wf-*.log

# Common causes:
# 1. API is slow (wait 60+ seconds)
# 2. Network connectivity issue
# 3. API quota exceeded (check console.anthropic.com)
# 4. Very long task description

# If API is rate-limited, wait 1 minute and retry
```

### "Config file not found"

```bash
# Verify files exist
ls -la copilot-config.json copilot-prompts.json

# Both files MUST be in project root directory
# If missing, restore from git or download

# Check they're valid JSON
jq . copilot-config.json > /dev/null && echo "Valid"
jq . copilot-prompts.json > /dev/null && echo "Valid"
```

### Logs Won't Write / Permission Error

```bash
# Check directory permissions
ls -ld workflow-logs/
ls -ld workflow-state/

# Create directories if missing
mkdir -p workflow-logs workflow-state

# Fix permissions (if needed)
chmod 755 workflow-logs workflow-state
chmod 644 workflow-logs/* workflow-state/*
```

### All Votes Say "escalate"

This is the safe fallback when something goes wrong. Check:

```bash
# 1. API key is valid
echo $ANTHROPIC_API_KEY

# 2. Network can reach API
curl -I https://api.anthropic.com/v1

# 3. Prompts file is valid
jq '.coordinator.system_prompt' copilot-prompts.json | head -5

# 4. Check actual error in logs
tail -50 workflow-logs/wf-*-llm-requests.jsonl | jq '.error'
```

---

## 🔧 Advanced Configuration

### Change Token Budget

Edit `copilot-config.json`:
```json
"token_budget": {
  "total_tokens_per_task": 200000,    # Increase for long tasks
  "total_tokens_per_phase": 40000
}
```

### Adjust Timeouts

```json
"timeouts": {
  "request_timeout_sec": 120,         # Increase if API is slow
  "read_timeout_sec": 180,
  "connect_timeout_sec": 10
}
```

### Enable Parallel Execution

```json
"execution_settings": {
  "parallel_phases": [2],             # Phase 2 (research) can run in parallel
  "sequential_phases": [1, 3, 4, 5, 6, 7, 8, 9]
}
```

### Change LLM Models

```json
"llm_providers": {
  "claude": {
    "models": {
      "default": "claude-3-opus-20250219",    # More powerful
      "fast": "claude-3-5-haiku-20241022"    # Faster
    }
  }
}
```

---

## 📋 Pre-Production Checklist

Before running critical workflows:

- [ ] ANTHROPIC_API_KEY is set and valid
- [ ] Network can reach api.anthropic.com
- [ ] Bash 4.0+ is installed
- [ ] jq is installed and working
- [ ] copilot-config.json is present
- [ ] copilot-prompts.json is present
- [ ] workflow-logs/ directory is writable
- [ ] workflow-state/ directory is writable
- [ ] Tested with example-task.json successfully
- [ ] Reviewed logs to understand output format
- [ ] Adjusted token budget if needed
- [ ] Set up log monitoring/archiving

---

## 🎯 Production Usage

### Daily Operations

```bash
# Monitor system health
tail -f workflow-logs/*.log &

# Submit workflow
./scripts/start-workflow.sh --file urgent-task.json

# Review decisions
jq '.[] | {agent: .agent_id, decision: .decision}' workflow-logs/*-votes.jsonl
```

### Log Archiving

```bash
# Archive old logs (older than 7 days)
find workflow-logs/ -mtime +7 -exec gzip {} \;

# Clean up very old logs (older than 30 days)
find workflow-logs/ -mtime +30 -delete
```

### Monitoring

```bash
# Alert if too many "escalate" votes (API issues)
grep -c '"escalate"' workflow-logs/*-votes.jsonl

# Track token usage
jq '.token_usage | to_entries | map(.key, .value)' workflow-state/*.json

# Monitor error rate
grep -c 'error' workflow-logs/*-llm-requests.jsonl
```

---

## 🎓 Getting Help

### Common Questions

**Q: How long does a workflow take?**  
A: 5-15 minutes for all 9 phases (30s-120s per phase + API latency)

**Q: Can I run multiple workflows at once?**  
A: Yes, each workflow gets a unique ID and logs separately

**Q: What if a workflow fails?**  
A: Logs are preserved in workflow-logs/ for debugging. Safe to retry.

**Q: Can I modify the prompts?**  
A: Yes, edit copilot-prompts.json to customize agent behavior

**Q: What's the maximum task budget?**  
A: Default 100K tokens/task (adjustable in config)

### Documentation

- [USER-GUIDE.md](USER-GUIDE.md) - How to run workflows
- [PHASE4.11-FINAL-REPORT.md](PHASE4.11-FINAL-REPORT.md) - Technical validation
- [RPC-EXPLANATION.md](RPC-EXPLANATION.md) - How consultations work
- [agents/RPC-PROTOCOL.json](agents/RPC-PROTOCOL.json) - Protocol specification

---

## ✅ Verification Checklist

After deployment, verify everything works:

```bash
# 1. Check environment
export ANTHROPIC_API_KEY="..." && echo "API key set"

# 2. Check files
ls -la copilot-config.json copilot-prompts.json && echo "Configs present"

# 3. Check dependencies
bash --version && jq --version && curl --version && echo "Dependencies OK"

# 4. Test with example
./scripts/start-workflow.sh --file example-task.json && echo "Test passed"

# 5. Check logs
ls -la workflow-logs/ && echo "Logs created"
```

If all steps pass: ✅ **System is ready for production**

---

**Status**: ✅ Production Ready  
**Last Updated**: 2026-05-29  
**Maintainer**: Copilot CLI Agent

