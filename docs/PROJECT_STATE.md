Project State
Purpose
This document answers: where is the project right now, what works, what is broken, and what should happen next?
This is the first document to read after returning to the project from a break.
Current status
Status: Board selection and cross-platform Cancel controls verified through UAT.
CTRBLXAI has a working baseline project structure. VS Code, Git, Rojo, and Roblox Studio are connected successfully.
`BoardPrototype.server.lua` runs from the CTRBLXAI repository and generates a visible 8x8 tactical board in Roblox Studio.
Tile selection is working. Selecting a tile creates a bright yellow ground-level square outline. Selecting another tile moves the outline to the newly selected tile.
The Cancel/Back control is working across the currently tested platforms:
Desktop: right-click anywhere in the game view clears the current selection.
Mobile: a compact Cancel button appears in the upper-right top-bar safe area while a selection is active.
Gamepad foundation: Button B is connected to the same Cancel action but has not yet been tested.
The mobile Cancel button passed UAT for size, position, visibility, and function using the Roblox Studio iPhone XR device emulator.
Current workflow decision
Use:
VS Code native Chat
Gemini API models when useful
Git for source control
Rojo for Roblox Studio synchronization
Roblox Studio for runtime and device-emulator testing
AI-generated complete full-file overwrites only
Do not currently rely on:
Open WebUI for this project workflow
Continue extension
LeanCTX
local autonomous coding agents
Current focus
Continue building Chaos Tactics one small, approved, and verified interaction at a time.
Current working layer:
```text
Board generation
↓
Tile selection
↓
Cross-platform Cancel/Back action
```
Do not begin another gameplay feature until the current accepted change is committed as a stable Git checkpoint.
Current blocker
No active blocker.
Verified working
CTRBLXAI folder structure exists.
Git repository has an initial working baseline commit.
VS Code opens CTRBLXAI as the project root.
Rojo 7.6.1 is installed and serving the project through the VS Code Rojo extension.
Roblox Studio connects to the Rojo server.
Rojo automatically syncs saved source changes while connected.
`source/ServerScriptService/BoardPrototype.server.lua` syncs and runs in Roblox Studio.
`source/StarterPlayer/StarterPlayerScripts/BoardInput.client.lua` syncs as `StarterPlayerScripts/BoardInput` and runs on the client.
The board prototype creates a visible 8x8 board.
Left-click or mobile tap selects a tile.
The selected tile shows a bright yellow ground-level outline without recoloring the tile.
Selecting another tile moves the outline.
Desktop right-click anywhere clears the current selection without removing normal camera control.
The mobile Cancel button appears only while a selection is active.
The mobile Cancel button clears the selection and then disappears.
The mobile Cancel button passed UAT in the iPhone XR landscape emulator.
`CTRBLXAI client input ready` appears in Roblox Studio Output when the client script loads.
Accepted interaction rules
Selection
Left-click or tap means Select or Confirm.
Selecting another tile replaces the current tile selection.
The tile selector remains a ground-level marker.
The selector must remain separate from tile textures, terrain decoration, units, trees, and other occupants.
Cancel and Back
Right-click means Cancel, Back, or Exit when applicable on desktop.
The upper-right Cancel button performs the same action on mobile.
Gamepad Button B is intended to perform the same action.
Cancel should eventually move back one interaction layer rather than always clearing all state.
The button should appear only when the current state has something meaningful to cancel or exit.
Interface theme
The game uses a medieval-fantasy visual direction.
Buttons and menus should follow the same theme.
The current Cancel button is a replaceable placeholder using dark brown, muted gold, and parchment-colored text.
Visual design must remain separate from Cancel behavior so a future Creator Store button design can replace the appearance without rebuilding the input logic.
Roblox standard controls are the reference for practical mobile size, spacing, and safe positioning.
Known issues and notes
Old BoardClient error
Roblox Studio Output has shown this unrelated client-side error:
```text
Modules is not a valid member of ReplicatedStorage "ReplicatedStorage"
Client - BoardClient:8
```
This comes from an older `BoardClient` script under `StarterCharacterScripts/Client`. It does not currently block board generation, tile selection, or Cancel behavior.
Do not modify or remove it until its role is deliberately reviewed.
Rojo version
The current working version is Rojo 7.6.1. A newer version exists, but updating is deferred because the current baseline is stable.
Use the Rojo controls in the VS Code status bar instead of manually running `rojo serve` in a terminal. Starting both the VS Code-managed server and a terminal server causes a port conflict on `localhost:34872`.
Rojo path lesson
Local filesystem paths must match `default.project.json` exactly.
The client input file must remain at:
```text
source/StarterPlayer/StarterPlayerScripts/BoardInput.client.lua
```
Before changing code for a feature that appears not to work, first verify:
The file exists at the mapped local path.
Rojo synchronized it to the expected Roblox Studio location.
The script loaded and printed its readiness message.
Only then investigate the script behavior.
Next action
Review the accepted changes in VS Code Source Control and create a Git checkpoint for the UAT-approved board selection and cross-platform Cancel controls.
After that checkpoint is complete, discuss and approve the next actual gameplay feature before implementing it.