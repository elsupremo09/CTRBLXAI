# CTRBLXAI

Chaos Tactics Roblox AI is a solo Roblox tactical game project developed with AI assistance.

The goal is to keep the workflow simple enough that the project can keep moving even if development pauses for a long time.

## Project purpose

CTRBLXAI is focused on building a playable Roblox tactical game prototype using:

- VS Code as the main editor
- Git as the safety net
- Rojo for syncing local source files into Roblox Studio
- Roblox Studio for runtime testing
- AI tools for investigation, debugging, and controlled full-file overwrites

The project is not currently optimized for collaborators, publishing, modding, or automation-heavy workflows.

## Minimal project structure

```text
CTRBLXAI/
├── README.md
├── .github/
│   └── copilot-instructions.md
├── docs/
│   ├── AI_COLLABORATION_RULES.md
│   ├── PROJECT_STATE.md
│   └── DECISION_LOG.md
├── prompts/
│   ├── DEBUGGING.md
│   └── IMPLEMENTATION.md
├── source/
└── default.project.json
```

## Architecture direction

The project should favor a simple Roblox architecture that is easy to understand, test, and safely modify with AI assistance.

Preferred direction:

- One file should have one clear main responsibility.
- Game rules should be separated from visual Roblox objects where practical.
- Server scripts should own game state and validation.
- Client scripts should handle display and player input.
- Config data should be separated from logic when practical.
- Runtime-generated objects should be kept separate from source-controlled objects.

Avoid large rewrites, complex frameworks, or architecture changes unless the existing structure clearly blocks progress.

## Source of truth

The source of truth is:

1. The committed repository files.
2. The current contents of `docs/PROJECT_STATE.md`.
3. The latest accepted Roblox Studio test result.

Chat history is helpful, but it should not override the repository.

## How to resume work

If returning to the project after a break:

1. Read `docs/PROJECT_STATE.md` first.
2. Read `docs/DECISION_LOG.md` if a tool or workflow decision seems unclear.
3. Use `prompts/DEBUGGING.md` when investigating a problem.
4. Use `prompts/IMPLEMENTATION.md` when requesting a controlled code change.
5. Test in Roblox Studio before accepting any change as stable.
