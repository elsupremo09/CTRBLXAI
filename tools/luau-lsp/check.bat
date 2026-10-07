@echo off
rem CTRBLXAI warning checker. Double-click to run.
rem Copies the project to C:\luaucheck (the checker can't read the D: drive),
rem runs the checker on every game file, and saves the list where the AI can read it.
set P=D:\AI\Projects\CTRBLXAI
set W=C:\luaucheck
if not exist "%W%" mkdir "%W%"
cd /d "%P%"
call rojo sourcemap default.project.json -o sourcemap.json
robocopy "%P%\source" "%W%\source" /MIR /NFL /NDL /NJH /NJS /NP >nul
copy /y "%P%\sourcemap.json" "%W%\" >nul
copy /y "%P%\tools\luau-lsp\luau-lsp.exe" "%W%\" >nul
copy /y "%P%\tools\luau-lsp\roblox.d.luau" "%W%\" >nul
cd /d "%W%"
luau-lsp.exe analyze --definitions=roblox.d.luau --sourcemap=sourcemap.json --formatter=plain source > "%P%\tools\luau-lsp\all_warnings.txt" 2>&1
echo.
echo Done. You can close this window and tell the AI "checked".
pause
