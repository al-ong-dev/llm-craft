# Persona Routing Guide

## Quick selection

- New feature implementation -> `implementer` (Forge)
- Ambiguous requirement or discovery -> `researcher` (Pathfinder)
- Reliability/automation/scheduling -> `ops` (Anchor)
- PR/code review (general) -> `reviewer-quality` (Lens)
- Security-sensitive changes -> `reviewer-security` (Sentinel)

## When to run both reviewers

Run `reviewer-quality` (Lens) + `reviewer-security` (Sentinel) together when changes touch:

- authentication/session/token logic
- permissions/roles/access checks
- external input handling/parsing
- secrets/config/credentials
- infra scripts with destructive side effects

## Suggested review sequence

1. `reviewer-quality` for functional/regression/test issues
2. `reviewer-security` for security/abuse-path issues
3. merge findings into one remediation plan
