# 🧪 PHASE 4.11 - E2E TESTING PLAN & RESULTS

**Date**: 2026-05-29 15:09 UTC+8  
**Status**: IN PROGRESS  
**Objective**: Validate full workflow end-to-end with example-task.json

---

## TEST SCOPE

### What We're Testing
✓ Entry point initialization (start-workflow.sh)  
✓ Workflow state file creation  
✓ Agent initialization  
✓ LLM voting mechanism (real Claude API)  
✓ RPC protocol (inter-agent consultations)  
✓ Logging (JSONL audit trail)  
✓ Configuration loading  
✓ Error handling  

### Test Levels
1. **Unit**: Individual scripts (llm-vote.sh, consult-agent.sh)
2. **Integration**: Agent orchestration with LLM
3. **E2E**: Full workflow (all 9 phases)
4. **Scenario**: Example task through complete workflow

---

## TEST PREREQUISITES

### Environment
- ANTHROPIC_API_KEY set ✓ (required for Claude API)
- Bash 4.0+ ✓
- jq (JSON processor) ✓
- Scripts: start-workflow.sh, llm-vote.sh, consult-agent.sh, llm-client.sh ✓
- Config: copilot-config.json, copilot-prompts.json ✓
- Task: example-task.json ✓

### System Requirements
- Tmux (optional, for UI testing)
- ~100KB disk space for logs
- Network access to Claude API
- 10-60 second timeout per LLM call

---

## TEST CASES

### TC-1: Entry Point Validation

**Objective**: Verify start-workflow.sh initializes correctly

**Steps**:
```bash
cd /data/data/com.termux/files/home/lc2

# TC-1a: CLI mode with --task
./scripts/start-workflow.sh --task "Fix token bug" --provider claude

# Expected output:
# ✓ Workflow ID generated (wf-YYYYMMDD-NNN)
# ✓ State file created: workflow-state/wf-XXX.json
# ✓ Log files created: workflow-logs/wf-XXX-*.jsonl
# ✓ Coordinator initialized
```

**Expected Results**:
- [ ] Workflow ID format valid (wf-YYYYMMDD-NNN)
- [ ] State file contains: id, task, agents[], phases[]
- [ ] Log directory writable
- [ ] No permission errors
- [ ] Script exits cleanly

---

### TC-2: Configuration Loading

**Objective**: Verify copilot-config.json loads correctly

**Steps**:
```bash
# Check agent config
jq '.agent_config | keys' copilot-config.json

# Expected: ["coordinator", "researcher", "implementer", "lens", "sentinel", "anchor"]
```

**Expected Results**:
- [ ] All 6 agents configured
- [ ] Each agent has llm_provider, model, temperature, max_tokens
- [ ] Token budget defined (100K default)
- [ ] Consultation settings valid

---

### TC-3: Prompt Template Loading

**Objective**: Verify copilot-prompts.json has all prompts

**Steps**:
```bash
# Count coordinator prompts
jq '.coordinator.phases | keys | length' copilot-prompts.json

# Expected: 9 (all phases)

# Check researcher prompts
jq '.researcher.phases | keys | length' copilot-prompts.json

# Expected: 9
```

**Expected Results**:
- [ ] All 6 agents have system_prompt
- [ ] Each agent has phases.1_intake through phases.9_delivery
- [ ] Prompts contain {task_context}, {phase_findings} placeholders
- [ ] No syntax errors in JSON

---

### TC-4: LLM Vote Generation (llm-vote.sh)

**Objective**: Verify real Claude API calls work

**Steps**:
```bash
# Generate a vote for researcher in Phase 2
./scripts/llm-vote.sh \
  --agent researcher \
  --phase 2 \
  --workflow test-wf-001 \
  --task "Fix token refresh bug in mobile app" \
  --findings "Race condition suspected"

# Expected output: Valid JSON vote object
```

**Expected Results**:
- [ ] Command completes within 30 seconds
- [ ] Returns valid JSON (not error)
- [ ] Vote contains: workflow_id, agent_id, phase, decision, confidence, rationale
- [ ] Decision is one of: proceed, block, escalate
- [ ] Confidence is one of: high, medium, low
- [ ] Logged to: workflow-logs/test-wf-001-votes.jsonl

---

### TC-5: RPC Consultation (consult-agent.sh)

**Objective**: Verify inter-agent consultation works

**Steps**:
```bash
# Ask Sentinel (security) what Implementer thinks about approach
./scripts/consult-agent.sh \
  --from implementer \
  --to sentinel \
  --question "Is JWT + refresh token secure for mobile?" \
  --workflow test-wf-002 \
  --phase 3

# Expected: Security opinion from Sentinel
```

**Expected Results**:
- [ ] Command completes within 30 seconds
- [ ] Returns valid JSON response
- [ ] Response contains: type, from_agent, to_agent, opinion, recommendation
- [ ] No circular call error
- [ ] Logged to: workflow-logs/test-wf-002-consultations.jsonl
- [ ] Circular prevention works (test max depth)

---

### TC-6: Workflow State File

**Objective**: Verify state file tracks workflow correctly

**Steps**:
```bash
# Check state file exists and is valid
jq . workflow-state/wf-*.json

# Should contain:
# {
#   "workflow_id": "wf-20260529-001",
#   "task": {...},
#   "phases": {},
#   "agents": {},
#   "votes": [],
#   "consultations": []
# }
```

**Expected Results**:
- [ ] State file valid JSON
- [ ] Contains all required fields
- [ ] Updated as workflow progresses
- [ ] Readable by other processes

---

### TC-7: Logging & Audit Trail

**Objective**: Verify all decisions logged to JSONL

**Steps**:
```bash
# Check vote logs
cat workflow-logs/wf-*-votes.jsonl | jq -r '.agent_id' | sort | uniq

# Expected: coordinator, researcher, implementer, lens, sentinel, anchor

# Check consultation logs
cat workflow-logs/wf-*-consultations.jsonl | head -1

# Should be valid JSONL (one JSON object per line)
```

**Expected Results**:
- [ ] Each vote logged as separate JSON line
- [ ] Each consultation logged as separate JSON line
- [ ] Logs include: timestamp, workflow_id, agent_id, decision
- [ ] No log corruption
- [ ] Logs readable and parseable

---

### TC-8: Full E2E Workflow (example-task.json)

**Objective**: Run complete workflow through all 9 phases

**Steps**:
```bash
# Load and run example task
./scripts/start-workflow.sh --file example-task.json --provider claude

# Monitor logs
tail -f workflow-logs/wf-*.jsonl

# Expected phases to complete:
# 1. Intake (parse task)
# 2. Research (gather context)
# 3. Plan (design solution)
# 4. Quality (code review)
# 5. Security (risk review)
# 6. Ops (reliability review)
# 7. Consensus (aggregate votes)
# 8. Execute (apply changes)
# 9. Delivery (present results)
```

**Expected Results**:
- [ ] All 9 phases initiate
- [ ] Coordinator orchestrates each phase
- [ ] Each agent votes
- [ ] Consultations occur (if needed)
- [ ] Logs show decision progression
- [ ] No stuck phases or timeouts
- [ ] Final decision logged
- [ ] State file updated with results

---

### TC-9: Error Handling

**Objective**: Verify graceful error handling

**Test Cases**:

**TC-9a: Missing API Key**
```bash
unset ANTHROPIC_API_KEY
./scripts/llm-vote.sh --agent researcher --phase 2 --workflow test-wf-003 --task "Test"

# Expected: Clear error message, JSON error response
```
- [ ] Error message clear (API key missing)
- [ ] Fallback vote returned (e.g., "escalate")
- [ ] No crash or hang

**TC-9b: Invalid Agent**
```bash
./scripts/llm-vote.sh --agent invalid_agent --phase 2 --workflow test-wf-004 --task "Test"

# Expected: Validation error
```
- [ ] Agent validation fails
- [ ] Error returned
- [ ] No LLM call made

**TC-9c: Timeout Handling**
```bash
# Set very short timeout and LLM slow response
timeout 2 ./scripts/llm-vote.sh --agent researcher --phase 2 --workflow test-wf-005 --task "Long task that times out"

# Expected: Timeout handled gracefully
```
- [ ] Timeout detected
- [ ] Fallback vote (escalate)
- [ ] No orphaned processes

**TC-9d: Circular Call Prevention**
```bash
# Try to create circular consultation: A→B→A
./scripts/consult-agent.sh --from researcher --to implementer --question "Test" --workflow test-wf-006 --depth 2

# Expected: Depth limit enforced
```
- [ ] Max depth enforced (max 2)
- [ ] Circular call blocked
- [ ] Error logged

---

### TC-10: Performance Metrics

**Objective**: Measure system performance

**Metrics to Collect**:
- [ ] Time per phase (expected: 30-120 sec each)
- [ ] LLM response time (expected: 10-30 sec per call)
- [ ] Total workflow time (expected: 5-15 min for all 9 phases)
- [ ] Tokens used per agent
- [ ] Log file size
- [ ] Memory usage

**Test**:
```bash
# Time the full workflow
time ./scripts/start-workflow.sh --file example-task.json

# Expected output:
# real 5m30s
# user 0m45s
# sys  0m30s
```

---

## TESTING EXECUTION PLAN

### Phase 1: Local Unit Tests (30 min)
1. ✓ TC-2: Configuration Loading
2. ✓ TC-3: Prompt Templates
3. ✓ TC-4: LLM Vote (single call)
4. ✓ TC-5: RPC Consultation (single call)

### Phase 2: Integration Tests (45 min)
1. ✓ TC-1: Entry Point
2. ✓ TC-6: State File
3. ✓ TC-7: Logging
4. ✓ TC-9: Error Handling

### Phase 3: Full E2E Test (10-15 min)
1. ✓ TC-8: Complete Workflow
2. ✓ TC-10: Performance Metrics

### Phase 4: Documentation (15 min)
- Record results
- Identify failures/issues
- Recommend fixes

**Total Estimated Time**: 1.5-2 hours

---

## KNOWN ISSUES & RISKS

### Critical Path Blockers
- **API Key**: ANTHROPIC_API_KEY must be set
- **Network**: Must have internet access to Claude API
- **Tmux**: Optional but recommended for UI visibility
- **jq**: Required for JSON parsing

### Potential Failures
- LLM timeout (slow response from Claude)
- Rate limiting (too many requests)
- Circular consultations (needs depth enforcement)
- State file corruption (file I/O issues)
- Log rotation (logs not archived)

### Mitigation
- Test with short timeouts first
- Monitor API rate limits
- Test circular prevention explicitly
- Add file locking if needed
- Implement log rotation

---

## SUCCESS CRITERIA

**Pass Criteria** (System Ready):
- ✓ All 10 test cases pass
- ✓ No critical errors
- ✓ Workflow completes without user intervention
- ✓ All decisions logged
- ✓ Performance acceptable (<15 min total)

**Fail Criteria** (Needs Fixes):
- ✗ Any test case fails
- ✗ Workflow hangs or crashes
- ✗ Missing logs or corruption
- ✗ Performance <100% unacceptable (>30 min)

---

## RESULTS LOG

### Test Run #1: [PENDING]

**Date**: 2026-05-29 15:09 UTC+8  
**Provider**: Claude (with API key)  
**Task**: example-task.json (token refresh bug)  

| TC# | Test | Result | Duration | Notes |
|-----|------|--------|----------|-------|
| 1 | Entry Point | ⏳ PENDING | - | - |
| 2 | Config Load | ⏳ PENDING | - | - |
| 3 | Prompts Load | ⏳ PENDING | - | - |
| 4 | LLM Vote | ⏳ PENDING | - | - |
| 5 | RPC Consult | ⏳ PENDING | - | - |
| 6 | State File | ⏳ PENDING | - | - |
| 7 | Logging | ⏳ PENDING | - | - |
| 8 | E2E Workflow | ⏳ PENDING | - | - |
| 9 | Error Handling | ⏳ PENDING | - | - |
| 10 | Performance | ⏳ PENDING | - | - |

**Overall**: ⏳ IN PROGRESS

---

## NEXT STEPS

1. [ ] Execute all test cases
2. [ ] Document results (pass/fail/duration)
3. [ ] Identify any issues
4. [ ] Fix critical issues (if any)
5. [ ] Re-test
6. [ ] Mark Phase 4.11 complete
7. [ ] Proceed to Phase 4.13 (Documentation)

---

**Status**: Phase 4.11 E2E Testing - IN PROGRESS  
**Next**: Execute test cases (Phase 1: Unit Tests)
