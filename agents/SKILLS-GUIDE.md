# Agent Skills System

Each agent has a set of tools (skills) they can use during their assigned phases. Some skills are shared across agents, others are role-specific.

## Quick Overview

### Skill Types
- **Shared Skills** (7): Used by multiple agents
  - Code Search, Issue Lookup, Pattern Analysis, etc.
- **Unique Skills** (22): Role-specific tools
  - Correctness Check (Lens), Auth Check (Sentinel), Failure Mode Analysis (Anchor), etc.

### Agent Skill Distribution

| Agent | Shared Skills | Unique Skills | Total |
|-------|---------------|---------------|-------|
| Researcher | 7 | 3 | 10 |
| Implementer | 5 | 5 | 10 |
| Lens (Quality) | 5 | 5 | 10 |
| Sentinel (Security) | 5 | 6 | 11 |
| Anchor (Ops) | 5 | 6 | 11 |

---

## 🔑 Shared Skills (Used by Multiple Agents)

### 1. Code Search
**Agents**: Researcher, Implementer, Lens, Sentinel  
**Purpose**: Find relevant code snippets in codebase  
**Implementation**: `scripts/smart-search.sh`  
**Input**: Query string + top N results  
**Output**: Code blocks with line numbers and scores  
**Timeout**: 30 seconds  
**Cached**: Yes (1 hour TTL)

```bash
# Example
skill-executor code-search '{"query": "jwt middleware validation", "top": 5}'
```

### 2. Issue Lookup
**Agents**: Researcher, Sentinel, Anchor  
**Purpose**: Find related GitHub issues and PRs  
**Implementation**: GitHub API via MCP  
**Input**: Keywords or issue title  
**Output**: Related issues with context  
**Timeout**: 20 seconds  
**Cached**: Yes

```bash
# Example
skill-executor issue-lookup '{"keywords": "token refresh race condition", "top": 5}'
```

### 3. Documentation Search
**Agents**: Researcher, Implementer, Lens  
**Purpose**: Search docs, runbooks, design docs  
**Implementation**: `scripts/knowledge-search.sh` (Confluence)  
**Input**: Documentation keywords  
**Output**: Relevant doc excerpts  
**Timeout**: 20 seconds  
**Cached**: Yes

### 4. Pattern Analysis
**Agents**: Researcher, Implementer, Lens, Sentinel  
**Purpose**: Identify existing code patterns and conventions  
**Implementation**: Combined grep + code-search  
**Input**: Pattern description  
**Output**: Code examples showing pattern  
**Timeout**: 15 seconds  
**Cached**: Yes

### 5. Context Retrieval
**Agents**: Researcher, Implementer, Lens, Sentinel  
**Purpose**: Get full context for specific file/module  
**Implementation**: `github-mcp-server get_file_contents`  
**Input**: File path  
**Output**: Full file contents + metadata  
**Timeout**: 10 seconds  
**Cached**: Yes

### 6. Dependency Check
**Agents**: Implementer, Lens, Sentinel, Anchor  
**Purpose**: Analyze dependencies, versions, CVE status  
**Implementation**: npm audit, pip check, safety  
**Input**: Dependency manifest file path  
**Output**: Dependency tree + vulnerabilities  
**Timeout**: 30 seconds  
**Cached**: Yes

### 7. Token Estimate
**Agents**: All  
**Purpose**: Estimate token count for LLM context sizing  
**Implementation**: `scripts/estimate-tokens.sh`  
**Input**: Text or file path  
**Output**: Token count + heuristics  
**Timeout**: 5 seconds  
**Cached**: Yes (no re-calc needed)

---

## 🎯 Researcher-Specific Skills (Pathfinder)

### 8. Trade-off Analysis
**Purpose**: Compare implementation approaches with pros/cons  
**Phase Used**: Phase 2 (Research)  
**Input**: Problem + feasible options  
**Output**: Comparison matrix with trade-offs  
**Timeout**: 60 seconds

```json
{
  "problem": "Fix token refresh race condition",
  "options": [
    "Add mutex/locking",
    "Use JWT version field",
    "Add idempotency key"
  ]
}
```

**Output**:
```json
{
  "analysis": [
    {
      "option": "Add mutex/locking",
      "pros": ["Simple", "Guaranteed atomicity"],
      "cons": ["Potential bottleneck", "Deadlock risk"]
    }
  ]
}
```

### 9. Prior Solution Finder
**Purpose**: Find similar solved problems in issue history  
**Phase Used**: Phase 2 (Research)  
**Input**: Problem description  
**Output**: Prior issues with solutions

### 10. Requirements Extraction
**Purpose**: Extract requirements and constraints from task  
**Phase Used**: Phase 1 (Intake)  
**Input**: Task description  
**Output**: Structured requirements, constraints, success criteria

---

## 🔨 Implementer-Specific Skills (Forge)

### 11. Code Generation
**Purpose**: Generate code changes aligned with patterns  
**Phase Used**: Phase 3 (Plan)  
**Input**: File + change description  
**Output**: Generated code diff  
**Timeout**: 120 seconds

### 12. Test Generation
**Purpose**: Generate unit/integration tests  
**Phase Used**: Phase 3 (Plan)  
**Input**: Code change + test framework  
**Output**: Test cases  
**Timeout**: 60 seconds

### 13. Refactor Suggestion
**Purpose**: Suggest minimal safe refactoring  
**Phase Used**: Phase 3 (Plan)  
**Input**: Code snippet  
**Output**: Refactoring options with impact analysis

### 14. Change Validation
**Purpose**: Validate change for syntax, imports, compatibility  
**Phase Used**: Phase 3 (Plan)  
**Input**: Files + changes  
**Output**: Validation report (errors, warnings)  
**Timeout**: 30 seconds

### 15. Build Test
**Purpose**: Run build/tests on proposed changes  
**Phase Used**: Phase 3 (Plan)  
**Input**: Files changed  
**Output**: Build result + test results  
**Timeout**: 180 seconds  
**Note**: Executes locally (npm test, python -m pytest, etc.)

---

## 🔍 Lens-Specific Skills (Quality Reviewer)

### 16. Correctness Check
**Purpose**: Identify logic bugs, edge cases, error handling gaps  
**Phase Used**: Phase 4 (Quality Review)  
**Input**: Code diff  
**Output**: Bug list with severity  
**Timeout**: 60 seconds

### 17. Test Coverage Check
**Purpose**: Analyze test gaps and coverage needs  
**Phase Used**: Phase 4 (Quality Review)  
**Input**: Code changes + existing tests  
**Output**: Test gap analysis

### 18. Regression Detection
**Purpose**: Identify potential regressions and impacts  
**Phase Used**: Phase 4 (Quality Review)  
**Input**: Code changes + related code  
**Output**: Regression risk assessment

### 19. Maintainability Review
**Purpose**: Check clarity, documentation, future-proofing  
**Phase Used**: Phase 4 (Quality Review)  
**Input**: Code diff  
**Output**: Maintainability issues + suggestions

### 20. Performance Analysis
**Purpose**: Identify performance issues and optimizations  
**Phase Used**: Phase 4 (Quality Review)  
**Input**: Code snippet  
**Output**: Performance risks + optimization suggestions

---

## 🛡️ Sentinel-Specific Skills (Security Reviewer)

### 21. Auth Check
**Purpose**: Identify authentication/authorization flaws  
**Phase Used**: Phase 5 (Security Review)  
**Input**: Code diff  
**Output**: Auth vulnerabilities with exploitability  
**Timeout**: 60 seconds

**Example Checks**:
- Missing token validation
- Insecure JWT algorithms
- Missing rate limiting
- Insufficient permission checks

### 22. Injection Detection
**Purpose**: Find SQL, XSS, command injection risks  
**Phase Used**: Phase 5 (Security Review)  
**Input**: Code snippet  
**Output**: Injection risks with context  
**Timeout**: 45 seconds

### 23. Secret Scan
**Purpose**: Detect hardcoded secrets, API keys, credentials  
**Phase Used**: Phase 5 (Security Review)  
**Input**: Code files  
**Output**: Secret findings with location  
**Timeout**: 30 seconds

### 24. Privilege Boundary Check
**Purpose**: Verify authorization boundaries and role checks  
**Phase Used**: Phase 5 (Security Review)  
**Input**: Code diff + role definitions  
**Output**: Privilege escalation risks

### 25. CVE Check
**Purpose**: Check dependencies for known CVEs  
**Phase Used**: Phase 5 (Security Review)  
**Input**: Dependency manifest  
**Output**: CVE list with severity  
**Timeout**: 60 seconds

### 26. Data Exposure Check
**Purpose**: Find data leakage in logs, errors, storage  
**Phase Used**: Phase 5 (Security Review)  
**Input**: Code snippet  
**Output**: Data exposure risks

---

## ⚓ Anchor-Specific Skills (Ops)

### 27. Failure Mode Analysis
**Purpose**: Identify failure scenarios and recovery paths  
**Phase Used**: Phase 6 (Ops Review)  
**Input**: Code change + system context  
**Output**: Failure modes with mitigation  
**Timeout**: 60 seconds

**Example Failure Modes**:
- Network timeout during token refresh
- Duplicate requests hitting race condition
- Load spike causing resource exhaustion
- Cascading failures if token endpoint down

### 28. Idempotency Check
**Purpose**: Verify operations are idempotent (safe retries)  
**Phase Used**: Phase 6 (Ops Review)  
**Input**: Code snippet  
**Output**: Idempotency analysis

### 29. Observability Check
**Purpose**: Ensure adequate logging and monitoring hooks  
**Phase Used**: Phase 6 (Ops Review)  
**Input**: Code diff  
**Output**: Logging/monitoring gaps

### 30. Scaling Analysis
**Purpose**: Analyze resource usage and scaling implications  
**Phase Used**: Phase 6 (Ops Review)  
**Input**: Code change + deployment context  
**Output**: Scaling risks and limits

### 31. Automation Safety Check
**Purpose**: Verify automation has guardrails and safeguards  
**Phase Used**: Phase 6 (Ops Review)  
**Input**: Automation script  
**Output**: Safety gaps and recommendations

### 32. Deployment Plan
**Purpose**: Create deployment strategy with rollback  
**Phase Used**: Phase 6 (Ops Review)  
**Input**: Code change + environment info  
**Output**: Deployment steps + rollback plan

---

## 🔄 Skill Execution Flow

### Parallel Execution During Phase

Each phase executes skills in parallel where possible:

```
Phase 2 (Research):
├─ code-search           (parallel)
├─ issue-lookup          (parallel)
├─ docs-search           (parallel)
├─ prior-solution-finder (parallel)
└─ trade-off-analysis    (depends on above, sequential)

Phase 4 (Quality Review):
├─ correctness-check       (sequential)
├─ test-coverage-check     (parallel)
├─ regression-detection    (parallel)
├─ maintainability-review  (parallel)
└─ performance-analysis    (parallel)

Phase 5 (Security Review):
├─ auth-check                (sequential)
├─ injection-detection       (parallel)
├─ secret-scan              (parallel)
├─ privilege-boundary-check  (parallel)
├─ cve-check                (parallel)
└─ data-exposure-check      (parallel)

Phase 6 (Ops Review):
├─ failure-mode-analysis      (sequential)
├─ idempotency-check         (parallel)
├─ observability-check       (parallel)
├─ scaling-analysis          (parallel)
├─ automation-safety-check   (parallel)
└─ deployment-plan           (parallel)
```

---

## 📚 Using Skills in Agent Code

### Invoke a Shared Skill

```bash
# From agent-runner.sh or any agent script
skill_result=$(
  ${SCRIPT_DIR}/scripts/skill-executor.sh \
    code-search \
    '{"query": "jwt middleware validate", "top": 5}'
)

# Parse result
findings=$(echo "$skill_result" | jq -r '.output')
cached=$(echo "$skill_result" | jq -r '.cached')
execution_time=$(echo "$skill_result" | jq -r '.execution_time_ms')
```

### Invoke a Role-Specific Skill

```bash
# From implementer agent
skill_result=$(
  ${SCRIPT_DIR}/scripts/skill-executor.sh \
    code-generation \
    '{"file": "src/auth.ts", "change": "Add rate limiting to token refresh"}'
)

generated_code=$(echo "$skill_result" | jq -r '.output.generated_code')
```

### Skill with Dependencies

```bash
# Run phase 2 skills with proper ordering
code_results=$(skill-executor code-search '{"query": "token refresh", "top": 5}')
issue_results=$(skill-executor issue-lookup '{"keywords": "race condition"}')
docs_results=$(skill-executor docs-search '{"keywords": "authentication"}')

# After all above complete, run dependent skill
trade_off=$(skill-executor trade-off-analysis "{
  \"problem\": \"Fix token refresh race\",
  \"context\": \"$code_results\",
  \"prior_issues\": \"$issue_results\"
}")
```

---

## 🎯 Skill Performance Characteristics

| Skill | Timeout | Cached | Typical Time | Parallel? |
|-------|---------|--------|--------------|-----------|
| code-search | 30s | Yes | 5-15s | Yes |
| issue-lookup | 20s | Yes | 5-10s | Yes |
| token-estimate | 5s | Yes | <1s | Yes |
| correctness-check | 60s | No | 10-30s | No |
| auth-check | 60s | No | 10-30s | No |
| test-generation | 60s | No | 20-40s | No |
| cve-check | 60s | Yes | 10-20s | Yes |
| failure-mode-analysis | 60s | No | 15-30s | No |

---

## 🚀 Extending Skills

### Add a New Shared Skill

1. **Define in `agents/SKILLS.json`**:
   ```json
   {
     "id": "new-skill",
     "category": "search",
     "description": "...",
     "implementation": "...",
     "used_by": ["agent1", "agent2"]
   }
   ```

2. **Implement in `scripts/skill-executor.sh`**:
   ```bash
   skill_new_skill() {
     log "Running new-skill"
     # implementation
     echo "{ \"skill_id\": \"new-skill\", \"output\": ... }"
   }
   ```

3. **Add to dispatcher**:
   ```bash
   case "$SKILL_ID" in
     new-skill) result=$(skill_new_skill) ;;
   esac
   ```

### Add Role-Specific Skill

1. **Define in `agents/SKILLS.json`** under agent's `unique_skills`
2. **Implement in skill-executor.sh**
3. **Reference in workflow execution order** (`execution_order` section)

---

## 📊 Skill Usage Statistics

To track which skills are used most:

```bash
# Query skill logs
./scripts/workflow-state-manager.sh query-skill-usage \
  --workflow-id <wf-id> \
  --group-by skill

# Output:
# code-search: 15 uses (cached: 12)
# correctness-check: 5 uses
# auth-check: 5 uses
# ...
```

---

## 🔐 Security Considerations

- **Shared Skills** run in isolated executor process
- **Secret Scan** redacts findings in logs
- **Code Generation** output reviewed before execution
- **Skill Cache** namespaced by agent + phase (no cross-contamination)

---

## Next Steps

1. ✅ Define skill registry (SKILLS.json)
2. ✅ Implement skill executor
3. 📝 Integrate skills into agent-runner.sh
4. 📝 Create skill performance dashboard
5. 📝 Add skill usage tracking
6. 📝 Implement skill result caching layer

---

**Status**: Skills defined and executor ready. Integration into workflow happening next.
