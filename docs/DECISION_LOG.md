# Decision Log

## Purpose

This document records important accepted, rejected, deferred, and replaced decisions.

It exists so future work does not repeat old experiments or forget why the current workflow exists.

## Decision format

```text
Date: YYYY-MM-DD
Decision: Short statement.
Status: Accepted / Rejected / Deferred / Replaced
Reason:
- Why this decision was made.
Implications:
- What this means for future work.
```

## Decisions

### 2026-07-30 - CTRBLXAI is a single focused project

Status: Accepted

Reason:

- The immediate goal is to get Chaos Tactics Roblox AI running.
- A higher-level reusable workflow project would be premature.
- All project docs should live inside the CTRBLXAI folder for now.

Implications:

- Keep documentation focused on this game project.
- Reconsider a general workflow repository only after the game has meaningful progress.

### 2026-07-30 - Minimal documentation structure

Status: Accepted

Reason:

- Too many documents become hard to maintain in a solo project.
- Future project recovery should require reading only a few files.

Implications:

Use this documentation set:

```text
README.md
docs/AI_COLLABORATION_RULES.md
docs/PROJECT_STATE.md
docs/DECISION_LOG.md
prompts/DEBUGGING.md
prompts/IMPLEMENTATION.md
```

### 2026-07-30 - README includes architecture overview

Status: Accepted

Reason:

- A separate architecture document would change infrequently.
- Keeping overview and architecture together reduces file count.

Implications:

- Update `README.md` when the project structure or architecture direction changes.
- Do not create `ARCHITECTURE.md` unless the game becomes complex enough to justify it.

### 2026-07-30 - AI collaboration rules are provider-agnostic

Status: Accepted

Reason:

- The project may switch between Gemini, Copilot, ChatGPT, Claude, or future tools.
- The core collaboration behavior should not be tied to one provider.

Implications:

- `docs/AI_COLLABORATION_RULES.md` is the master AI instruction document.
- `.github/copilot-instructions.md` is only a VS Code pointer to the master rules.

### 2026-07-30 - Full-file overwrites are mandatory

Status: Accepted

Reason:

- Partial-edit instructions are too risky for the project owner.
- Full-file overwrites are easier to review, test, compare, and revert.

Implications:

- AI assistants must not ask the project owner to manually insert or move individual lines.
- Implementation prompts must request complete file replacements.

### 2026-07-30 - VS Code native Chat is the main AI interface

Status: Accepted

Reason:

- VS Code native Chat already provides the needed AI workflow.
- Continue was uninstalled after confirming it was not the actual chat interface being used.

Implications:

- Do not reinstall Continue unless a specific missing capability is proven.
- Use native VS Code Chat with available Gemini models for investigation and debugging.

### 2026-07-30 - Open WebUI is not part of this project workflow

Status: Accepted

Reason:

- Open WebUI adds another layer that is not needed for this project workflow.
- The goal is to reduce tooling complexity.

Implications:

- Open WebUI may be used separately for experiments.
- It should not be required to continue CTRBLXAI.

### 2026-07-30 - LeanCTX is deferred

Status: Deferred

Reason:

- LeanCTX could help with context management, token savings, memory, and repository maps.
- The project does not yet prove the need for that extra layer.

Implications:

- Reconsider LeanCTX only if context selection, token limits, repeated file reads, or long-session memory become real blockers.
