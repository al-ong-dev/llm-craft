# RPC (Remote Procedure Call) in Phase 4.5 - Use Cases

## Problem It Solves

Currently:
- Coordinator can talk to each agent (one-way)
- Agents cannot talk to each other

But per SUBAGENT-ARCHITECTURE, we need:
- **Agents consulting agents** (two-way communication)
- Example: Implementer asks Sentinel "Is this auth approach secure?"

---

## Concrete Example

### Scenario: Implement OAuth 2.0

**Phase 3 (Plan)**:
```
Coordinator → Implementer: "Draft plan for OAuth 2.0"

Implementer thinks:
  "I'll use JWT tokens with refresh tokens."
  
But wait... should I consult Sentinel about security implications?
  
Implementer → Sentinel (RPC CALL):
  "Is JWT + refresh token approach secure for OAuth 2.0?"
  
Sentinel responds (RPC RESPONSE):
  {
    "opinion": "Approach is sound",
    "concern_level": "medium",
    "recommendation": "Add rate limiting to token endpoint",
    "issues": ["Missing rate limiting", "No token blacklist"]
  }
  
Implementer adjusts plan:
  "Add rate limiting to token endpoint"
  "Add token blacklist for logout"
  
Implementer → Coordinator:
  "Plan ready. Coordinated with Sentinel on security."
  
Coordinator vote: "PROCEED" (all concerns addressed)
```

---

## RPC in Architecture

### Without RPC (Current State)
```
Phase 3: Implementer drafts plan → Coordinator
Phase 4: Lens reviews plan → Coordinator
Phase 5: Sentinel reviews plan → Coordinator

Problem: Each agent reviews independently
- Quality concerns might not be addressable
- Security issues discovered too late
- Back-and-forth impossible
```

### With RPC (Phase 4.5+)
```
Phase 3: Implementer drafts plan
         → Consults Sentinel: "Security OK?"
         → Gets feedback
         → Updates plan
         → Coordinator gets BETTER plan

Phase 4: Lens reviews updated plan
         → Consults Implementer: "Can we add tests?"
         → Gets feasibility answer
         → Determines if quality is achievable

Phase 5: Sentinel reviews AGAIN
         → All security concerns already addressed
         → No blockers
```

---

## Technical Implementation (Phase 4.5)

### RPC Message Format (JSON)

**Request** (Implementer → Sentinel):
```json
{
  "type": "consultation_request",
  "from_agent": "implementer",
  "to_agent": "sentinel",
  "workflow_id": "wf-20260529-001",
  "phase": 3,
  "question": "Is JWT + refresh token secure for OAuth 2.0?",
  "context": {
    "approach": "JWT tokens with refresh tokens",
    "endpoints": ["/auth/token", "/auth/refresh", "/auth/logout"],
    "rate_limiting": "proposed in implementation"
  },
  "depth": 0,
  "timeout": 60
}
```

**Response** (Sentinel → Implementer):
```json
{
  "type": "consultation_response",
  "from_agent": "sentinel",
  "to_agent": "implementer",
  "workflow_id": "wf-20260529-001",
  "phase": 3,
  "question": "Is JWT + refresh token secure for OAuth 2.0?",
  "opinion": "Approach is secure with recommended additions",
  "concern_level": "medium",
  "recommendation": "proceed_with_fixes",
  "issues": [
    "Missing rate limiting on token endpoint",
    "No token blacklist mechanism",
    "Refresh token stored in HTTP-only cookie?"
  ],
  "fixes": [
    "Add 10 req/min limit to /auth/token",
    "Implement token blacklist with TTL",
    "Ensure refresh token in HTTP-only cookie"
  ],
  "timestamp": "2026-05-29T14:20:00Z"
}
```

---

## RPC Protocol Details

### How RPC Works

1. **Agent A needs opinion from Agent B**
   - Agent A calls: `consult_agent B --question "..."`
   
2. **RPC Handler intercepts**
   - Logs consultation
   - Prevents circular calls (A→B→A protection)
   - Checks depth (max 2 levels)
   
3. **Agent B runs quickly**
   - Uses fast LLM model (Haiku instead of Sonnet)
   - Brief response format (not full vote)
   - Timeout after 60 seconds
   
4. **Response returned to Agent A**
   - Agent A gets opinion + concern level + recommendation
   - Agent A uses this to adjust their decision
   - Both agents report to Coordinator

### Consultation Call Graph

```
Researcher can consult:
  └─ Implementer (is this buildable?)
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
```

---

## Benefits of RPC

### ✅ Better Decisions
- Issues caught early and fixable
- Agents coordinate before voting
- No surprises in later phases

### ✅ Fewer Escalations
**Without RPC**:
```
Phase 3: Implementer votes "proceed"
Phase 5: Sentinel votes "blocked" (security critical)
Result: Escalate to human
```

**With RPC**:
```
Phase 3: Implementer consults Sentinel → addresses concern
Phase 5: Sentinel votes "proceed" (already fixed)
Result: No escalation needed
```

### ✅ Simulation of Real Teamwork
- Like an actual team consulting on concerns
- Natural, collaborative decision-making
- Audit trail of consultations

---

## When RPC Happens

### Phase 2 (Research)
- Researcher might consult Implementer: "Feasible?"
- Researcher might consult Sentinel: "Any red flags?"

### Phase 3 (Planning)
- Implementer consults Lens: "Quality acceptable?"
- Implementer consults Sentinel: "Security OK?"
- Implementer consults Anchor: "Deployable?"

### Phase 4 (Quality Review)
- Lens consults Implementer: "Can we fix this?"
- Lens consults Anchor: "Will this impact production?"

### Phase 5 (Security Review)
- Sentinel consults Implementer: "Can you mitigate this?"
- Sentinel consults Anchor: "Operational security?"

### Phase 6 (Ops Review)
- Anchor consults all others on final concerns

---

## Why This Matters

### Traditional Multi-Agent (No RPC)
```
Issues found in Phase 5 that could have been fixed in Phase 3
→ Delays
→ Rework needed
→ Escalation required
```

### Our System (With RPC)
```
Issues identified in Phase 3
→ Consulted with specialists immediately
→ Fixed before Phase 5 review
→ Proceeding to implementation with confidence
→ Better decisions faster
```

---

## Summary

**RPC = Agents asking each other for opinions during decision-making**

Not for full analysis (that's what phases are for), but for quick:
- "Is this feasible?" (30 seconds)
- "Any security concerns?" (30 seconds)
- "Can we deploy this?" (30 seconds)

Results flow back to the consulting agent, who adjusts their decision accordingly.

**Result**: Consensus-based decisions with early issue detection and mitigation.
