# Implementation Prompt

Use this prompt after the bug or feature change has already been investigated and the intended fix is approved.

```text
Apply the approved change to the CTRBLXAI repository.

Follow docs/AI_COLLABORATION_RULES.md.

Rules:
- Use complete full-file overwrites only.
- Never provide partial edits.
- Never ask me to insert, move, replace, or delete individual lines manually.
- Modify the fewest files possible.
- Do not modify unrelated files.
- Preserve existing behavior unless the approved change requires otherwise.
- Preserve public interfaces unless explicitly approved.
- Do not rename, create, move, or delete files unless explicitly requested.
- Explain changes in non-coder-friendly language.
- List every modified file.
- Identify assumptions and risks.
- Tell me what to test in Roblox Studio.

Approved change:
[Describe the approved change here.]
```
