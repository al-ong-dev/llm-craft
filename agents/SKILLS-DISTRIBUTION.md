# Skills Distribution Summary

## Overview

Each of the 5 agents has been assigned a curated set of skills tailored to their role. Some skills are shared across multiple agents to reduce duplication and improve consistency.

---

## 📊 Skills Breakdown

### Total Skills: 29
- **Shared Skills**: 7 (used by multiple agents)
- **Unique Skills**: 22 (role-specific)

---

## 🔄 Shared Skills (Used by Multiple Agents)

All 5 agents can use these foundational skills:

| # | Skill | Purpose | Agents | Impl |
|---|-------|---------|--------|------|
| 1 | **Code Search** | Find relevant code snippets | All (4) | smart-search.sh |
| 2 | **Issue Lookup** | Find related issues/PRs | Researcher, Sentinel, Anchor | GitHub API |
| 3 | **Docs Search** | Search documentation | Researcher, Implementer, Lens | knowledge-search |
| 4 | **Pattern Analysis** | Identify code patterns | Researcher, Implementer, Lens, Sentinel | grep + search |
| 5 | **Context Retrieval** | Get file context | All except Researcher (4) | github-mcp |
| 6 | **Dependency Check** | CVE/version analysis | Implementer, Lens, Sentinel, Anchor | npm/pip/safety |
| 7 | **Token Estimate** | Calculate token count | All (5) | estimate-tokens |

---

## 👤 Researcher Skills (Pathfinder)

**Role**: Discover context, find options, analyze trade-offs

**Shared Skills** (7):
- Code Search
- Issue Lookup
- Docs Search
- Pattern Analysis
- Context Retrieval
- Dependency Check
- Token Estimate

**Unique Skills** (3):
- **Trade-off Analysis** - Compare implementation approaches
- **Prior Solution Finder** - Find similar solved problems
- **Requirements Extraction** - Parse requirements from task

**Total**: 10 skills
**Primary Phase**: Phase 2 (Research)

**Example Use Case**:
```
Task: "Fix token refresh race condition"

Skills Used (Sequential):
1. code-search("token refresh") → find existing code
2. issue-lookup("race condition auth") → find prior issues
3. docs-search("token security") → find docs
4. pattern-analysis("auth patterns") → see conventions
5. prior-solution-finder() → similar solved problems
6. trade-off-analysis() → pros/cons of options

Output: "Context found, 3 feasible approaches identified"
```

---

## 🔨 Implementer Skills (Forge)

**Role**: Draft minimal, safe, testable changes

**Shared Skills** (5):
- Code Search
- Pattern Analysis
- Context Retrieval
- Dependency Check
- Token Estimate

**Unique Skills** (5):
- **Code Generation** - Generate code changes
- **Test Generation** - Write tests
- **Refactor Suggestion** - Safe refactoring
- **Change Validation** - Syntax/compatibility check
- **Build Test** - Run build and tests

**Total**: 10 skills
**Primary Phase**: Phase 3 (Plan)

**Example Use Case**:
```
Task: "Implement token refresh with rate limiting"

Skills Used (Parallel):
1. code-search("rate limiting patterns")
2. pattern-analysis()
3. dependency-check() → verify available libraries
4. code-generation() → generate implementation
5. test-generation() → write tests
6. change-validation() → check for errors
7. build-test() → run locally

Output: "Changes ready, all tests pass, no errors"
```

---

## 🔍 Lens Skills (Quality Reviewer)

**Role**: Validate correctness, tests, maintainability

**Shared Skills** (5):
- Code Search
- Pattern Analysis
- Context Retrieval
- Dependency Check
- Token Estimate

**Unique Skills** (5):
- **Correctness Check** - Find logic bugs
- **Test Coverage Check** - Analyze test gaps
- **Regression Detection** - Find side effects
- **Maintainability Review** - Code clarity
- **Performance Analysis** - Perf issues

**Total**: 10 skills
**Primary Phase**: Phase 4 (Quality Review)

**Example Use Case**:
```
Task: Review token refresh implementation

Skills Used (Parallel):
1. correctness-check() → find bugs
2. test-coverage-check() → test gaps
3. regression-detection() → side effects
4. maintainability-review() → clarity issues
5. performance-analysis() → perf risks

Output: "3 bugs found, test coverage insufficient"
```

---

## 🛡️ Sentinel Skills (Security Reviewer)

**Role**: Validate auth, secrets, boundaries, abuse paths

**Shared Skills** (5):
- Code Search
- Issue Lookup
- Context Retrieval
- Dependency Check
- Token Estimate

**Unique Skills** (6):
- **Auth Check** - Auth/authz flaws
- **Injection Detection** - SQL/XSS/command injection
- **Secret Scan** - Hardcoded secrets
- **Privilege Boundary Check** - Escalation risks
- **CVE Check** - Vulnerability scanning
- **Data Exposure Check** - Data leakage risks

**Total**: 11 skills
**Primary Phase**: Phase 5 (Security Review)

**Example Use Case**:
```
Task: Security review of token refresh

Skills Used (Parallel):
1. auth-check() → auth flaws
2. injection-detection() → injection risks
3. secret-scan() → hardcoded secrets
4. privilege-boundary-check() → privilege risks
5. cve-check() → CVE vulnerabilities
6. data-exposure-check() → data leakage

Output: "Missing rate-limit check (high), no secrets found"
```

---

## ⚓ Anchor Skills (Ops)

**Role**: Validate reliability, recovery, automation safety

**Shared Skills** (5):
- Code Search
- Issue Lookup
- Docs Search
- Dependency Check
- Token Estimate

**Unique Skills** (6):
- **Failure Mode Analysis** - Failure scenarios
- **Idempotency Check** - Safe retries
- **Observability Check** - Logging/monitoring gaps
- **Scaling Analysis** - Resource/scaling risks
- **Automation Safety Check** - Safeguards in automation
- **Deployment Plan** - Deploy strategy + rollback

**Total**: 11 skills
**Primary Phase**: Phase 6 (Ops Review)

**Example Use Case**:
```
Task: Ops review of token refresh deployment

Skills Used (Parallel):
1. failure-mode-analysis() → failure scenarios
2. idempotency-check() → retry safety
3. observability-check() → monitoring gaps
4. scaling-analysis() → load implications
5. automation-safety-check() → automation guards
6. deployment-plan() → deployment strategy

Output: "Deployment plan ready, 2 observability gaps"
```

---

## 🔄 Skill Usage by Phase

### Phase 1: Intake (All Agents)
```
Requirements Extraction (role-agnostic LLM call)
└─ All agents parse task
```

### Phase 2: Research (Researcher)
```
Researcher:
├─ code-search (parallel)
├─ issue-lookup (parallel)
├─ docs-search (parallel)
├─ pattern-analysis (parallel)
├─ prior-solution-finder (parallel)
└─ trade-off-analysis (depends on above)
```

### Phase 3: Plan (Implementer)
```
Implementer:
├─ code-search (parallel)
├─ pattern-analysis (parallel)
├─ code-generation (sequential)
├─ test-generation (parallel)
├─ refactor-suggestion (optional)
├─ change-validation (sequential)
└─ build-test (sequential)
```

### Phase 4: Quality Review (Lens)
```
Lens:
├─ correctness-check (sequential)
├─ test-coverage-check (parallel)
├─ regression-detection (parallel)
├─ maintainability-review (parallel)
└─ performance-analysis (parallel)
```

### Phase 5: Security Review (Sentinel)
```
Sentinel:
├─ auth-check (sequential)
├─ injection-detection (parallel)
├─ secret-scan (parallel)
├─ privilege-boundary-check (parallel)
├─ cve-check (parallel)
└─ data-exposure-check (parallel)
```

### Phase 6: Ops Review (Anchor)
```
Anchor:
├─ failure-mode-analysis (sequential)
├─ idempotency-check (parallel)
├─ observability-check (parallel)
├─ scaling-analysis (parallel)
├─ automation-safety-check (parallel)
└─ deployment-plan (parallel)
```

---

## 📈 Skill Reusability

### Most Shared Skills:
1. **Token Estimate** - Used by ALL 5 agents
2. **Code Search** - Used by 4 agents (Researcher, Implementer, Lens, Sentinel)
3. **Pattern Analysis** - Used by 4 agents
4. **Context Retrieval** - Used by 4 agents
5. **Dependency Check** - Used by 4 agents

### Unique Skills (Not Shared):
- Trade-off Analysis (Researcher only)
- Code Generation (Implementer only)
- Correctness Check (Lens only)
- Auth Check (Sentinel only)
- Failure Mode Analysis (Anchor only)

---

## 🔧 Skill Invocation

### Simple Invocation
```bash
skill-executor <skill_id> <input_json>
```

### Example: Researcher uses code-search
```bash
skill-executor code-search '{
  "query": "token refresh authentication",
  "top": 5
}'
```

### Example: Sentinel uses auth-check
```bash
skill-executor auth-check '{
  "code": "export function refreshToken(req, res) { ... }",
  "context": "authentication endpoint"
}'
```

### With Caching
```bash
# First call: executes skill
skill-executor code-search '{"query": "jwt", "top": 5}'

# Second call (same input): returns cached result
# Marked with "cached": true in response
```

---

## 💾 Skill Files

| File | Purpose |
|------|---------|
| `agents/SKILLS.json` | Complete skill registry |
| `agents/SKILLS-GUIDE.md` | Detailed skill documentation |
| `scripts/skill-executor.sh` | Skill execution engine |
| `agents/SKILLS-DISTRIBUTION.md` | This file |

---

## 🎯 Design Rationale

### Shared Skills (Why?)
- **Consistency**: All agents use same code-search implementation
- **Performance**: Shared caching reduces redundant queries
- **Maintainability**: Single source of truth per skill
- **Reusability**: Agents collaborate using same data sources

### Unique Skills (Why?)
- **Role-Specific**: Each agent has domain-specific analysis capabilities
- **Focused Output**: Skills produce role-aligned insights
- **Specialization**: Deep expertise in their domain (security, ops, quality)
- **Non-Overlapping**: Avoids duplication of effort

### Execution Strategy (Why Sequential + Parallel?)
- **Sequential**: When skill depends on previous output
- **Parallel**: When skills are independent (faster phase execution)
- **Mixed**: Most phases use both (parallel where possible)

---

## 🚀 Performance Impact

### Estimated Phase Execution Times
(Assuming all skills complete, no escalations)

| Phase | Agents | Duration | Parallelism |
|-------|--------|----------|-------------|
| 1 | All (5) | 5-10s | Sequential |
| 2 | Researcher | 30-60s | Mostly parallel |
| 3 | Implementer | 60-120s | Mixed |
| 4 | Lens | 45-90s | Mostly parallel |
| 5 | Sentinel | 60-120s | Mostly parallel |
| 6 | Anchor | 60-120s | Mostly parallel |
| 7 | All (5) | 2-5s | Sequential (voting) |
| 8 | Implementer | 10-30s | Sequential |
| 9 | All (5) | 20-40s | Mostly parallel |

**Total Workflow**: ~30-45 minutes (if all skills complete successfully)

---

## 🔐 Security & Isolation

✅ **Skill Isolation**:
- Each skill runs in subprocess
- Separate cache namespace
- No cross-skill state sharing

✅ **Secret Handling**:
- Secret Scan redacts findings
- Secrets not logged
- Cache excludes sensitive data

✅ **Access Control**:
- Skills respect filesystem permissions
- GitHub API tokens scoped to read-only
- No write operations in shared skills

---

## 🎓 Example: Full Workflow with Skills

```
Task: "Fix token refresh race condition in mobile app"

Phase 1: Intake (All agents)
└─ Requirements Extraction
   → "Priority: high, Impact: 5% users, Regression: PR #456"

Phase 2: Research (Researcher)
├─ code-search("token refresh")
│  → Found: src/auth/token-refresh.ts (40-90 lines)
├─ issue-lookup("race condition token")
│  → Found: Issue #432 (similar problem, solved with mutex)
├─ docs-search("token security best practices")
│  → Found: Auth runbook with rate-limiting recommendation
├─ pattern-analysis("token refresh patterns")
│  → Found: 2 other endpoints using similar pattern
└─ trade-off-analysis()
   → Option A: Mutex locking
   → Option B: JWT version field
   → Option C: Idempotency key
   → Recommended: Option C (simplest, safest)

Phase 3: Plan (Implementer)
├─ code-search("idempotency key pattern")
│  → Found: Examples in database transactions
├─ code-generation()
│  → Generated: Modified token-refresh.ts with idempotency
├─ test-generation()
│  → Generated: Concurrent request test case
├─ change-validation()
│  → ✓ No syntax errors, imports OK, TypeScript OK
└─ build-test()
   → ✓ Build passes, 5 tests pass, coverage 95%

Phase 4: Quality Review (Lens)
├─ correctness-check()
│  → ✓ Logic correct, edge cases handled
├─ test-coverage-check()
│  → ⚠️ Missing: idempotency key collision test
├─ regression-detection()
│  → ✓ No breaking changes to token schema
├─ maintainability-review()
│  → ✓ Code clear, well-documented
└─ performance-analysis()
   → ✓ No performance regressions

Phase 5: Security Review (Sentinel)
├─ auth-check()
│  → ✓ Token validation in place
├─ injection-detection()
│  → ✓ No injection risks
├─ secret-scan()
│  → ✓ No secrets found
├─ privilege-boundary-check()
│  → ✓ No privilege escalation
├─ cve-check()
│  → ✓ No CVEs in dependencies
└─ data-exposure-check()
   → ✓ No sensitive data exposed in logs

Phase 6: Ops Review (Anchor)
├─ failure-mode-analysis()
│  → Failure: Race condition still possible if idempotency key reused
│  → Mitigation: Key expires after 1 hour
├─ idempotency-check()
│  → ✓ Retry-safe with expiring idempotency key
├─ observability-check()
│  → Add metrics: token_refresh_duplicate_detected
├─ scaling-analysis()
│  → ✓ In-memory key store OK up to 10K RPS
├─ automation-safety-check()
│  → ✓ Rollback safe (just remove key check)
└─ deployment-plan()
   → Strategy: Canary 10% users → 50% → 100%
   → Rollback: Disable idempotency check in config

Phase 7: Decision (All agents vote)
├─ Researcher: proceed (context clear)
├─ Implementer: proceed (implementation sound)
├─ Lens: proceed (with noted test addition)
├─ Sentinel: proceed (no security issues)
└─ Anchor: proceed (deployment plan ready)
   → ✓ CONSENSUS REACHED

Phase 8: Execute (Implementer)
├─ Merge PR with idempotency key check
├─ Deploy to staging
└─ All tests pass

Phase 9: Verify (All agents)
├─ Researcher: ✓ Context matches implementation
├─ Implementer: ✓ All tests pass, no regressions
├─ Lens: ✓ Code quality verified
├─ Sentinel: ✓ No security issues
└─ Anchor: ✓ Deployed successfully
   → ✓ WORKFLOW COMPLETE

Result: Token refresh race condition fixed!
```

---

## 📚 Next Steps

1. ✅ Skills defined (SKILLS.json)
2. ✅ Executor created (skill-executor.sh)
3. ✅ Documentation complete
4. 📝 Integrate into agent-runner.sh
5. 📝 Add skill caching layer
6. 📝 Create skill performance dashboard
7. 📝 Add real LLM backend for unique skills

---

**Status**: Skills system fully designed and documented. Ready for integration into workflow.
