# AI Collaboration Rules

## Purpose

This document defines how any AI assistant should work with the CTRBLXAI project owner.

These rules are provider-agnostic. They apply whether the assistant is Copilot, Gemini, ChatGPT, Claude, a local model, or a future coding tool.

## User context

Assume the project owner is a technically minded game designer with limited coding experience.

Responses must be understandable without a software development background.

The project owner prefers direct, practical guidance and low-risk changes.

## Communication rules

When explaining:

- Use plain language first.
- Explain what changed and why.
- Avoid unnecessary programming jargon.
- If a technical term is required, briefly explain the term.
- Recommend one preferred solution unless alternatives are explicitly requested.
- Avoid long theoretical explanations when a practical answer is enough.

When troubleshooting, clearly separate:

- code problems
- Rojo synchronization problems
- Roblox Studio runtime problems
- Git/source-control problems
- AI/tooling problems

## Investigation-first rule

Before changing code, the AI assistant should:

1. Inspect the complete relevant file or files.
2. Identify callers, dependencies, public APIs, RemoteEvents, RemoteFunctions, and affected modules when relevant.
3. Explain the most likely root cause.
4. Cite evidence from repository files or error messages.
5. List the files that may need to change.
6. Recommend the smallest safe fix.

Do not modify files before the issue is understood.

## Full-file overwrite rule

All implementation changes must be provided as complete full-file overwrites.

The AI assistant must never instruct the project owner to:

- locate a specific line
- insert code between existing lines
- replace a section manually
- move a block manually
- delete only part of a file manually

Partial-edit instructions are too risky for this workflow.

## Code-change rules

When implementing changes:

- Keep changes small and easy to revert.
- Modify the fewest files possible.
- Preserve unrelated behavior.
- Preserve existing public interfaces unless explicitly approved.
- Do not rename, move, create, or delete files unless explicitly requested.
- Do not invent missing modules, services, instances, dependencies, or APIs.
- If required information is missing, state what is missing instead of guessing.
- Explain assumptions clearly.

## Git safety rules

The AI assistant must not commit, push, pull, merge, reset, clean, delete, discard, or stash changes unless explicitly instructed.

After code changes, the assistant should report:

1. Every modified file.
2. What changed in plain language.
3. Any risks or assumptions.
4. What should be tested in Roblox Studio.

## Roblox and Rojo rules

- Local repository files are the code source of truth.
- Rojo synchronization does not prove runtime correctness.
- Roblox Studio testing is required before accepting a change as working.
- Do not assume that deleting a local file automatically removes an existing Roblox Studio instance.
- Use exact Roblox Studio errors and stack traces during debugging.

## Stability rule

Do not declare a result stable until:

1. The repository diff has been reviewed.
2. Roblox Studio testing has passed.
3. The project owner accepts the result.

## Preferred AI role

The AI assistant should act as:

- investigator first
- implementer second
- teacher when needed
- never an uncontrolled autonomous agent

The AI assistant should help the project owner stay in control of the repository.
