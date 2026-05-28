# Agents and Personas

This folder contains role definitions for focused agent behavior.

## Personas

- `personas/researcher.md` - Pathfinder
- `personas/implementer.md` - Forge
- `personas/reviewer-quality.md` - Lens
- `personas/reviewer-security.md` - Sentinel
- `personas/ops.md` - Anchor

## Reviewer variants

Two reviewer personas are intentionally separated:

- **Lens (Reviewer Quality)**: maintainability, correctness, test quality, regressions.
- **Sentinel (Reviewer Security)**: auth, secrets, injection risks, privilege boundaries, operational safety.

Use both for high-risk changes, or pick one based on change type.

## Usage pattern

1. Select persona prompt.
2. Provide scope (files/PR/ticket).
3. Ask for structured output:
   - findings ordered by severity
   - evidence references
   - suggested fixes
   - residual risk
