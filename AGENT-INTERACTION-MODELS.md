# 🤖 Agent Interaction Models - Architecture Options

## Current Design: 5 Parallel Panes (One Agent Per Pane)

```
tmux session with 5 panes:
┌─────────────────────────────────────────────────┐
│ Pane 0: Researcher  │ Pane 1: Implementer      │
├──────────────────────────────────────────────────┤
│ Pane 2: Lens        │ Pane 3: Sentinel        │
├──────────────────────────────────────────────────┤
│ Pane 4: Anchor                                   │
└─────────────────────────────────────────────────┘

Benefits:
  ✓ Parallel execution (all agents run simultaneously)
  ✓ Independent failures (one agent fails ≠ all fail)
  ✓ Visual monitoring (see all agents at once)
  ✓ 9 phases complete in ~300-600 seconds

Tradeoff:
  ✗ Requires tmux
  ✗ More complex state management
```

---

## OPTION 1: Sequential Single Pane (No Tmux)

```
Single pane/terminal, agents run sequentially:

Phase 1: Researcher runs → votes → Phase 1 complete
Phase 2: Researcher runs → votes → Phase 2 complete
Phase 3: Implementer runs → votes → Phase 3 complete
Phase 4: Lens runs → votes → Phase 4 complete
Phase 5: Sentinel runs → votes → Phase 5 complete
Phase 6: Anchor runs → votes → Phase 6 complete
Phase 7: ALL vote → consensus check
Phase 8: Implementer executes
Phase 9: ALL verify

Pros:
  ✓ Simple (no tmux needed)
  ✓ Easy to debug (linear flow)
  ✓ Single output stream
  ✓ No process management

Cons:
  ✗ Slower (sequential vs parallel)
  ✗ All phases take ~3-5 hours per task
  ✗ One agent slow = entire task slow
  ✗ No real parallelism

Implementation:
  • Modify workflow-orchestrator.sh
  • Remove tmux spawning
  • Run agents sequentially
  • Wait for each vote before proceeding
```

---

## OPTION 2: Agents as Subagents

```
Agents can invoke other agents as subroutines:

Researcher can call:
  → code-search skill
  → issue-lookup skill
  → Ask Implementer "is this feasible?" (subagent call)
  → Get answer back
  → Continue research

Implementer can call:
  → Ask Lens "will my approach work?" (quality check subagent)
  → Ask Sentinel "is this secure?" (security check subagent)
  → Get answers back
  → Refine implementation

Sentinel can call:
  → Ask Lens "does this break anything?"
  → Get answer back
  → Make decision

Benefits:
  ✓ Collaborative (agents help each other)
  ✓ Reduces back-and-forth
  ✓ Better decisions (consulting before voting)
  ✓ More realistic (like humans)

Drawbacks:
  ✗ Complex to implement (RPC/messaging)
  ✗ Infinite loop risk (A calls B, B calls A)
  ✗ Harder to debug
  ✗ Slower (sequential + network calls)

Implementation:
  • Add agent-to-agent messaging in agent-runner.sh
  • Whitelist allowed subagent calls per role
  • Track call depth (prevent infinite loops)
  • Modify SKILLS.json: add "consult-agent" as skill
  • Return consultation result to calling agent
```

---

## OPTION 3: Hybrid - Multi-Agent Per Pane

```
Same pane, multiple agents in sequence:

Pane 0: Researcher → Implementer (sequential)
Pane 1: Lens → Sentinel (sequential)
Pane 2: Anchor (solo)

Or:

Pane 0: Researcher → Ask Implementer (subagent) → Vote
Pane 1: Implementer → Ask Lens/Sentinel (subagents) → Vote
...

Pros:
  ✓ Faster than pure sequential
  ✓ Some parallelism
  ✓ Simpler than full subagent model

Cons:
  ✗ Still complex
  ✗ Partial parallelism only
  ✗ Mixed interaction models
```

---

## SUBAGENT IMPLEMENTATION SKETCH

```bash
# In agent-runner.sh, add:

consult_agent() {
  local target_agent=$1
  local question=$2
  local context_file=$3
  
  # Call target agent as subagent
  ./scripts/agent-runner.sh \
    --agent $target_agent \
    --phase $PHASE \
    --workflow $WORKFLOW_ID \
    --context $context_file \
    --instruction "Answer this question: $question" \
    --subagent true
  
  # Return answer to calling agent
  cat /tmp/subagent_answer.json
}

# In main logic:
if [[ "$AGENT_ID" == "implementer" ]]; then
  # Consult Lens about quality
  LENS_FEEDBACK=$(consult_agent "lens" "Will my approach pass your quality checks?" $CONTEXT_FILE)
  
  # Consult Sentinel about security
  SENTINEL_FEEDBACK=$(consult_agent "sentinel" "Are there security issues?" $CONTEXT_FILE)
  
  # Now make better decision using feedback
  VOTE="proceed|escalate|blocked"
fi
```

---

## RECOMMENDATION FOR PHASE 4

**For simplicity**: Keep current design (5 parallel panes)
- Works well
- Fully tested
- Documented
- No changes needed

**If you want single pane**: 
- Use OPTION 1 (sequential)
- Easy to implement (1-2 hours)
- Trade speed for simplicity
- Good for testing/debugging

**If you want subagents**:
- Use OPTION 2 (collaborative)
- More complex (4-6 hours)
- Better decisions (agents help each other)
- Better mirrors human collaboration
- Slower execution (more LLM calls)

---

## COMPARISON TABLE

| Feature | Current (5 Panes) | Sequential (1 Pane) | Subagents |
|---------|---|---|---|
| Parallel | ✓ Yes | ✗ No | Partial |
| Speed | Fast (5-10 min) | Slow (3-5 hours) | Medium (depends) |
| Complexity | High (tmux) | Low | High (messaging) |
| Debugging | Harder | Easy | Hard |
| Collaboration | Voting only | Voting only | Rich (consultation) |
| Implementation | Done | 1-2 hours | 4-6 hours |
| LLM calls | 5 per phase | 5 per phase | 5+ per phase |
| Cost | Base | Base | +20% (more calls) |

---

## DECISION MATRIX

**Choose Current (5 panes)** if:
- You want fast execution
- You have tmux available
- Parallel is preferred
- You're OK with current complexity

**Choose Sequential (1 pane)** if:
- You want simplicity
- You're debugging/testing
- Speed is not critical
- You have hours available per task

**Choose Subagents** if:
- You want realistic collaboration
- Better decisions matter more than speed
- You're willing to pay for extra LLM calls
- You want agents to help each other

---

## QUICK ANSWER

**Will subagents work?** 
✅ Yes, but requires implementation (4-6 hours in Phase 4)

**Will they be in same pane?**
✅ Yes, if you remove tmux (OPTION 1 or 3)
✅ Or, they can be in same workflow but different processes

**Recommendation for Phase 4:**
Start with current design (5 panes). 
After Phase 4 works, consider subagents as enhancement (Phase 4.5).

This keeps Phase 4 focused on LLM integration, not architectural changes.
