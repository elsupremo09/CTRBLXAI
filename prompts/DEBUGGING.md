# Debugging Prompt

Use this prompt when something breaks and the AI should investigate before changing code.

```text
Investigate this issue in the CTRBLXAI repository.

Do not modify any files yet.
Do not run destructive commands.
Do not guess missing project state.

Problem:
[Describe the issue here. Paste the exact Roblox Studio error and stack trace if available.]

Tasks:
1. Inspect the relevant files.
2. Identify the most likely root cause.
3. Provide the evidence supporting that cause.
4. List every file involved.
5. Explain whether the fix should affect one file or multiple files.
6. Recommend the smallest safe fix.
7. Explain the answer in non-coder-friendly language first.

Follow docs/AI_COLLABORATION_RULES.md.
```
