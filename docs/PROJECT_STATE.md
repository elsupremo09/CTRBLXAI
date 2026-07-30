# Project State

## Purpose

This document answers: where is the project right now, what works, what is broken, and what should happen next?

This is the first document to read after returning to the project from a break.

## Current status

Status: Baseline verified.

CTRBLXAI has a working baseline project structure. VS Code, Rojo, and Roblox Studio are connected successfully.

`BoardPrototype.server.lua` runs from the CTRBLXAI repository and generates a visible 8x8 tactical board in Roblox Studio.

## Current workflow decision

Use:

- VS Code native Chat
- Gemini API models when useful
- Git for source control when ready
- Rojo for Roblox Studio synchronization
- Roblox Studio for runtime testing
- AI-generated full-file overwrites only

Do not currently rely on:

- Open WebUI for this project workflow
- Continue extension
- LeanCTX
- local autonomous coding agents

## Current focus

Begin actual game development on top of the verified board prototype.

The next gameplay step should be small and testable.

Recommended next feature:

- Tile selection
- Tile highlight
- Tile deselection

## Current blocker

No active blocker.

## Verified working

- CTRBLXAI folder structure exists.
- VS Code opens CTRBLXAI as the project root.
- Rojo 7.6.1 is installed and serving the project.
- Roblox Studio connects to the Rojo server.
- `source/ServerScriptService/BoardPrototype.server.lua` syncs into Roblox Studio.
- The board prototype creates a visible 8x8 board.
- Roblox Studio Output confirms: `Rblx CT board prototype created: 8x8`.

## Known issue

Roblox Studio Output showed this unrelated client-side error:

```text
Modules is not a valid member of ReplicatedStorage "ReplicatedStorage"
Client - BoardClient:8