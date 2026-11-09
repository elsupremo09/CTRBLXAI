# CTRBLXAI parallel-session rules (MANDATORY for every session/agent)

Project root: D:\AI\Projects\CTRBLXAI. Sign-up sheet: _sessions\claims.json. Change log: _sessions\log.md.

1. BEFORE editing any file under source\ or docs\, read claims.json.
   - If any file you need is claimed by another session (and its claim is not expired), DO NOT edit it. Wait, or tell the user which session holds it.
   - Otherwise add your claim: {"session": "<short name, e.g. Dev-rulings>", "task": "<one line>", "files": ["source/...", ...], "started": "<now, Asia/Manila ISO>", "expires_hours": 3}. Write the file back immediately, then re-read it to confirm your claim is there (another session may have written at the same moment).
2. Studio: claim "STUDIO" the same way before starting a playtest. Only one session may use the Battle Studio at a time. Never stop another session's playtest while it holds STUDIO.
3. Before each edit, check the file's modified time against when you last read it. If it changed and you didn't change it, STOP and report.
4. When finished (or stopping), remove your claim and append one line to log.md: "<time> | <session> | <files> | <what changed>".
5. Backups go in a _codebackup_<name>_<date>\ folder at the project root, NEVER inside source\.
6. Claims older than expires_hours are stale: report them to the user before overriding.
7. Read-only work (Tester checks, reading files) needs no claim, but must note in its report if a file changed during the check.
