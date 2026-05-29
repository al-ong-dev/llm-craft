# 🤖 SUBAGENT ARCHITECTURE - Phase 4 Integration Plan

**Decision**: Implement Option 2 (Agent-to-Agent Consultation)
**Rationale**: Simulates real-world collaboration, better decisions
**Impact**: More complex, slower, +20% cost, but more realistic

---

## ARCHITECTURE OVERVIEW

```
Agent Communication Model:

Researcher Phase 2:
  ├─ Run code-search skill
  ├─ Ask Implementer: "Is this approach buildable?"
  ├─ Ask Sentinel: "Any obvious security concerns?"
  └─ Vote based on findings + consultation feedback

Implementer Phase 3:
  ├─ Run file-impact-analysis skill
  ├─ Ask Lens: "Will this pass quality gates?"
  ├─ Ask Sentinel: "Are there security issues?"
  └─ Vote based on findings + consultation feedback

Lens Phase 4:
  ├─ Run test-coverage-check skill
  ├─ Ask Implementer: "Can you cover these gaps?"
  └─ Vote based on findings + consultation feedback

Sentinel Phase 5:
  ├─ Run security-scan skill
  ├─ Ask Lens: "Will quality review catch this?"
  ├─ Ask Implementer: "Can you fix this?"
  └─ Vote based on findings + consultation feedback

Anchor Phase 6:
  ├─ Run deployment-readiness check
  ├─ Ask Sentinel: "Are we secure enough?"
  ├─ Ask Implementer: "Is this deployable?"
  └─ Vote based on findings + consultation feedback
```

---

## CALL GRAPH (Who Can Consult Whom)

```
Researcher can consult:
  └─ Implementer (is it feasible?)
  └─ Sentinel (security red flags?)

Implementer can consult:
  └─ Lens (quality concerns?)
  └─ Sentinel (security issues?)
  └─ Anchor (deployment concerns?)

Lens can consult:
  └─ Implementer (can you fix this?)
  └─ Anchor (operational impact?)

Sentinel can consult:
  └─ Lens (quality implication?)
  └─ Implementer (can you fix this?)
  └─ Anchor (operational security?)

Anchor can consult:
  └─ Sentinel (security posture?)
  └─ Lens (quality impact?)
  └─ Implementer (technical feasibility?)

Rules:
  ✓ No circular calls (A→B→A prevention)
  ✓ Max 2 consultation calls per agent per phase
  ✓ Consultation = synchronous (wait for answer)
  ✓ Consultation answer = brief opinion (not full vote)
```

---

## IMPLEMENTATION PLAN

### Phase 4.1: Add Consultation Skill (2 hours)

**File**: `agents/SKILLS.json`

Add new skill:
```json
{
  "name": "consult-agent",
  "description": "Ask another agent for consultation/opinion",
  "phases": [2, 3, 4, 5, 6],
  "agents": ["researcher", "implementer", "lens", "sentinel", "anchor"],
  "parameters": {
    "target_agent": "string (which agent to consult)",
    "question": "string (what to ask)",
    "context": "json (current context)"
  },
  "output": {
    "agent_opinion": "string",
    "concern_level": "low|medium|high",
    "recommendation": "proceed|escalate|blocked"
  },
  "timeout": 60,
  "cached": false
}
```

**Implementation**: Add to SKILLS.json (5 min)

### Phase 4.2: Add Subagent RPC Handler (3 hours)

**File**: `scripts/agent-runner.sh`

Add function:
```bash
consult_agent() {
  local target_agent=$1
  local question=$2
  local context_file=$3
  local depth=$4
  
  # Prevent infinite loops
  if [[ $depth -gt 2 ]]; then
    echo '{"error": "max_depth_reached"}' > /tmp/consultation_response.json
    return
  fi
  
  # Prevent circular calls (A→B→A)
  if grep -q "$target_agent" /tmp/consultation_chain_${WORKFLOW_ID}.log 2>/dev/null; then
    echo '{"error": "circular_call_prevented"}' > /tmp/consultation_response.json
    return
  fi
  
  # Call target agent as subagent
  echo "$target_agent" >> /tmp/consultation_chain_${WORKFLOW_ID}.log
  
  ./scripts/agent-runner.sh \
    --agent $target_agent \
    --phase $PHASE \
    --workflow $WORKFLOW_ID \
    --context $context_file \
    --instruction "CONSULTATION REQUEST from $AGENT_ID: $question. Respond briefly (opinion, concern level, recommendation). Do NOT submit a vote." \
    --subagent true \
    --depth $((depth + 1)) 2>/dev/null
  
  # Return consultation result
  cat /tmp/subagent_response_${target_agent}.json 2>/dev/null || \
    echo '{"error": "no_response"}'
}
```

**Implementation**: Add to agent-runner.sh (3 hours)
- Add consultation handler
- Add depth tracking
- Add circular call prevention
- Add timeout per consultation
- Parse consultation response

### Phase 4.3: Update Agent Decision Logic (3 hours)

**File**: `scripts/agent-runner.sh` main()

For each agent, add consultation step:

```bash
# Researcher Phase 2 with consultation
if [[ "$AGENT_ID" == "researcher" ]] && [[ "$PHASE" == "2" ]]; then
  # Step 1: Run skills
  run_skill code-search
  run_skill issue-lookup
  
  # Step 2: Consult (optional)
  IMPLEMENTER_OPINION=$(consult_agent implementer \
    "Is this approach buildable with these findings?" $CONTEXT_FILE 0)
  
  # Step 3: Synthesize
  if [[ $(echo $IMPLEMENTER_OPINION | jq -r '.recommendation') == "blocked" ]]; then
    VOTE="escalate"
    FINDINGS="$FINDINGS. Implementer flags: $(echo $IMPLEMENTER_OPINION | jq -r '.concern')"
  else
    VOTE="proceed"
  fi
fi
```

**Implementation**: 3 hours
- Researcher consultations (Implementer, Sentinel)
- Implementer consultations (Lens, Sentinel, Anchor)
- Lens consultations (Implementer, Anchor)
- Sentinel consultations (Lens, Implementer, Anchor)
- Anchor consultations (Sentinel, Lens, Implementer)

### Phase 4.4: Add Consultation State Tracking (1 hour)

**File**: `workflow-state/*.json`

Add to phase state:
```json
{
  "phase": 2,
  "agent": "researcher",
  "consultations": [
    {
      "target": "implementer",
      "question": "Is this buildable?",
      "response": {
        "opinion": "Yes, approach is sound",
        "concern": "Missing error handling",
        "level": "medium"
      }
    }
  ]
}
```

**Implementation**: 1 hour
- Log consultations to state file
- Track consultation metadata
- Add to audit trail

### Phase 4.5: Update Tests & Examples (2 hours)

**Files**: 
- `example-task.json` (add consultation example)
- New test cases for consultation flow

**Implementation**: 2 hours
- Test Researcher → Implementer consultation
- Test circular call prevention
- Test depth limiting
- Test timeout handling

### Phase 4.6: Performance & Optimization (2 hours)

**Optimizations**:
- Parallel consultation (ask multiple agents at once)
- Consultation caching (same question = same answer)
- Consultation timeout tuning
- Consultation cost tracking (count LLM calls)

**Implementation**: 2 hours

---

## TOTAL TIME ESTIMATE

```
Current Phase 4:          20-30 hours
Add Subagent Feature:     +13-15 hours
──────────────────────────────────────
Total Phase 4 (Enhanced): 33-45 hours

Breakdown:
  4.1 Add skill:          2 hours
  4.2 RPC handler:        3 hours
  4.3 Agent logic:        3 hours
  4.4 State tracking:     1 hour
  4.5 Tests:              2 hours
  4.6 Optimization:       2 hours
  ────────────────────────────────
  Subtotal:              13 hours

  + Original Phase 4:    20-30 hours
  ────────────────────────────────
  TOTAL:                 33-43 hours
```

---

## IMPACT ANALYSIS

### Benefits
✅ **Realistic collaboration** (agents help each other)
✅ **Better decisions** (consulting before voting)
✅ **Reduced escalations** (catch issues early)
✅ **Audit trail** (track consultation reasoning)
✅ **Knowledge transfer** (agents learn from each other)

### Costs
❌ **+50% execution time** (more LLM calls)
❌ **+20% API costs** (more consultations)
❌ **Complexity** (circular call prevention, timeouts)
❌ **Debugging harder** (more state to track)

### Examples

**Without Subagents**:
```
Implementer plans change
→ Sentinel votes "blocked" (security issue discovered)
→ Escalate to human
→ Human fixes, resumes
```

**With Subagents**:
```
Implementer plans change
→ Implementer asks Sentinel: "Security OK?"
→ Sentinel says: "Auth missing, you can fix it?"
→ Implementer adjusts plan
→ Both vote "proceed"
→ No escalation needed
```

---

## DECISION FRAMEWORK

### Implement Subagents If:
✅ You want realistic collaboration
✅ Quality > Speed
✅ Better decisions matter
✅ You can afford +50% execution time
✅ Cost increase acceptable (+20%)

### Don't Implement If:
❌ Speed is critical (need <5 min per task)
❌ Cost is critical (API budget tight)
❌ Simplicity preferred
❌ Deterministic behavior required

---

## RECOMMENDATION

✅ **YES - Implement in Phase 4**

**Rationale**:
- Simulates reality (humans consult each other)
- Better decision quality
- +13 hours is acceptable tradeoff
- Audit trail valuable for debugging
- One-time implementation cost

**Approach**:
1. Start with basic subagents (Phase 4.1-4.3: 8 hours)
2. Test with example-task.json
3. Add optimization (Phase 4.6: 2 hours)
4. Deploy with consultation logs

**Timeline**: Phase 4 = 33-45 hours (vs original 20-30)

---

## PHASE 4 REVISED ROADMAP

```
Phase 4.1: LLM Provider Setup              1-2 hours
Phase 4.2: Prompt Engineering              4-6 hours
Phase 4.3: Add Consultation Skill          2 hours ← NEW
Phase 4.4: LLM Integration                 3-5 hours
Phase 4.5: RPC/Subagent Handler            3 hours ← NEW
Phase 4.6: Agent Decision + Consultation   3 hours ← NEW
Phase 4.7: Token Counting & Budget         2-3 hours
Phase 4.8: Error Recovery                  2-3 hours
Phase 4.9: Cost Tracking                   1-2 hours
Phase 4.10: State & Audit Logging          1 hour  ← NEW
Phase 4.11: E2E Testing                    4-6 hours
Phase 4.12: Performance Tuning             2-4 hours
────────────────────────────────────────────────────
TOTAL:                                    33-45 hours

Key Changes:
  • +3 new subphases (4.3, 4.5, 4.6, 4.10)
  • +13 hours for subagent feature
  • Same documentation approach
  • Same testing methodology
```

---

## FILES TO MODIFY

```
agents/SKILLS.json
  └─ Add "consult-agent" skill definition

scripts/agent-runner.sh
  ├─ Add consult_agent() function
  ├─ Add depth tracking
  ├─ Add circular call prevention
  ├─ Update main() for each agent with consultations
  └─ Add subagent response handling

workflow-state/*.json
  └─ Add consultation tracking to phase state

scripts/workflow-state-manager.sh
  └─ Add consultation query commands

example-task.json
  └─ Example showing consultation flow (optional)

INTEGRATION.md
  └─ Document subagent architecture
```

---

## SUMMARY

**Decision**: Implement Subagent Architecture (Option 2)
**Time**: +13 hours to Phase 4 (33-45 hours total)
**Quality**: Much better (realistic collaboration)
**Cost**: +20% API usage
**Status**: Ready to implement in Phase 4

This is the right choice for a production system that simulates reality.
