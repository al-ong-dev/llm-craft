# Ollama Task Catalog (Safe Local Usage)

This catalog defines what local Ollama should and should not handle to reduce errors, overload, and low-quality outputs.

## Core operating limits

- Target total budget per run: `<= 4000` tokens
- Recommended context size: `<= 200 lines of code` or equivalent text
- Reserve for output: `800-1500` tokens
- Preferred style: single-step instruction/response (avoid long multi-turn chains)

If a task exceeds these limits, split it or route to a larger/cloud model.

## Allowed task classes

### 1) Snippet Summary

- **Use when:** You need quick understanding of a small function/file section.
- **Input:** 20-200 LOC
- **Output target:** 5-15 bullets
- **Example instruction:** `Summarize this snippet's purpose, dependencies, and failure paths.`

### 2) Risk and Bug Scan (Heuristic)

- **Use when:** You want likely bug hotspots before deeper review.
- **Input:** 30-200 LOC
- **Output target:** top 3-10 risks with rationale
- **Example instruction:** `List likely bugs, edge cases, and null/error handling gaps.`

### 3) Test Case Drafting

- **Use when:** You need candidate tests for a narrow module.
- **Input:** function/module snippet + brief expected behavior
- **Output target:** unit/integration test checklist
- **Example instruction:** `Generate test cases including edge and failure conditions.`

### 4) Prompt Compression / Rewrite

- **Use when:** You want a shorter, clearer prompt for downstream models.
- **Input:** long prompt text
- **Output target:** compact instruction with constraints
- **Example instruction:** `Rewrite this prompt to be concise while preserving constraints.`

### 5) Keyword Extraction for Index Search

- **Use when:** You need better query terms for `smart-search` / `knowledge-search`.
- **Input:** user question or ticket text
- **Output target:** 5-12 high-signal keywords
- **Example instruction:** `Extract the most discriminative technical keywords for codebase search.`

### 6) Structured Classification

- **Use when:** You need quick labels (severity/type/component) from short text.
- **Input:** issue/comment/log excerpt
- **Output target:** fixed JSON schema
- **Example instruction:** `Classify severity, subsystem, and probable owner from this issue text.`

## Conditionally allowed tasks (split first)

These are allowed only after chunking/splitting into bounded inputs:

- Multi-file review
- Long incident timeline synthesis
- Policy/doc comparison across large pages
- Refactor planning for large modules

Pattern: run multiple bounded local tasks, then merge results with a stronger model or deterministic script.

## Disallowed local tasks (route elsewhere)

- Whole-repo architecture decisions from raw repo dump
- High-stakes security/compliance sign-off
- Large-scale code rewrite generation
- Tasks requiring exact tokenizer/billing accuracy
- Any run that consistently exceeds budget even after truncation

## Error-prone patterns to avoid

- Vague instruction (`analyze this`) without expected format
- Oversized context with no prioritization
- Asking for final truth from heuristic-only scan
- Mixing many objectives in one prompt
- Repeated retries with same overloaded prompt

## Recommended instruction template

Use this structure for consistency:

```text
Task: <one allowed task class>
Goal: <specific outcome>
Constraints:
- Max output length: <N bullets or lines>
- Output format: <bullets/json/checklist>
- Focus: <error handling | test gaps | keyword extraction ...>
Context:
<bounded snippet/text>
```

## Overload guardrails

- If estimated input > budget:
  1. shorten context to most relevant section,
  2. reduce objective scope,
  3. retry once,
  4. escalate to larger model.
- Max retry count for same task: `2`
- If two retries fail, mark task `escalate_required`.

## Output quality checklist

Before accepting local output:

- Is it specific to provided context (not generic)?
- Are claims tied to visible code/text?
- Does format match requested schema?
- Are obvious hallucinations absent?
- Is confidence/uncertainty stated where needed?

## Quick routing guide

- **Small, bounded, operational task** -> local Ollama (`ollama-task.ps1/.sh`)
- **Cross-system or high-context task** -> indexed retrieval + stronger model
- **High-risk decision** -> human review + stronger model

## Preferred implementation pattern

When possible, use retrieval-grounded local inference:

1. run index search (`smart-search` / `knowledge-search`),
2. take top 3-5 blocks,
3. trim per block,
4. call local Ollama.

Use wrappers:
- `local-analyze.ps1`
- `local-analyze.sh`

This reduces overload risk versus direct large-context prompts.
