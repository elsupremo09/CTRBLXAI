# Roblox / Luau Best Practices Reference
## For CTRBLXAI Dev Agent — Expert Knowledge Base

> This document is the single source of truth for the Roblox Dev Expert agent.
> Before implementing any feature or fixing any bug, consult the relevant section.
> Every decision must be traceable to a rule or pattern documented here.

---

## TABLE OF CONTENTS

### Core Reference
1. [Official Resource Index](#1-official-resource-index)
2. [Code Style & Conventions](#2-code-style--conventions)
3. [Architecture: Server Authority Model](#3-architecture-server-authority-model)
4. [Security & Anti-Cheat](#4-security--anti-cheat)
5. [Performance: Scripting](#5-performance-scripting)
6. [Performance: Memory](#6-performance-memory)
7. [Performance: Draw Calls & Rendering](#7-performance-draw-calls--rendering)
8. [Performance: Networking & Bandwidth](#8-performance-networking--bandwidth)
9. [Roblox Studio Native Tools (Use These First)](#9-roblox-studio-native-tools-use-these-first)
10. [Modern Luau Features](#10-modern-luau-features)
11. [Common Mistakes & Anti-Patterns](#11-common-mistakes--anti-patterns)
12. [Roblox-Specific Patterns & Idioms](#12-roblox-specific-patterns--idioms)
13. [UI Best Practices](#13-ui-best-practices)
14. [Data Management](#14-data-management)
15. [Community Libraries Worth Knowing](#15-community-libraries-worth-knowing)
16. [Platform Limitations & Constraints](#16-platform-limitations--constraints)

### Advanced Patterns (Learned from Real Development)
17. [Rojo Workflow & External Tooling](#17-rojo-workflow--external-tooling)
18. [Module Architecture & Dependency Management](#18-module-architecture--dependency-management)
19. [WaitForChild & Module Loading Order](#19-waitforchild--module-loading-order)
20. [Spatial Lookups & Caching](#20-spatial-lookups--caching)
21. [RemoteEvent Architecture at Scale](#21-remoteevent-architecture-at-scale)
22. [Logging & Debugging Discipline](#22-logging--debugging-discipline)
23. [Data Module Organization](#23-data-module-organization)
24. [Trial-and-Error Lessons (Things Docs Don't Teach)](#24-trial-and-error-lessons-things-docs-dont-teach)

### Appendices
---

## 1. Official Resource Index

These are the authoritative sources. When in doubt, these win over community advice.

### Core Documentation
| Resource | URL | What It Covers |
|----------|-----|----------------|
| Roblox Creator Hub — Scripting | https://create.roblox.com/docs/scripting | All scripting fundamentals, Luau reference |
| Luau Language Reference | https://create.roblox.com/docs/luau | Type system, scope, control flow, strings, tables |
| Roblox Lua Style Guide | https://roblox.github.io/lua-style-guide/ | **Official** naming, formatting, and code organization conventions |
| Luau Type Checking | https://create.roblox.com/docs/luau/type-checking | Strict mode, type annotations, inference |
| Native Code Generation | https://create.roblox.com/docs/luau/native-code-gen | `@native` attribute, when to use it |
| Parallel Luau | https://create.roblox.com/docs/scripting/luau/parallel-luau | Actor model, multithreading, task.desynchronize/synchronize |

### Performance & Optimization
| Resource | URL | What It Covers |
|----------|-----|----------------|
| Improve Performance (Memory/Compute) | https://create.roblox.com/docs/projects/performance-optimization/memory | Script computation, physics, humanoids, memory |
| Design for Performance | https://create.roblox.com/docs/performance-optimization/design | Materials, streaming, draw calls, transparency, scripting budget |
| Optimize Your Experience | https://create.roblox.com/docs/tutorials/environmental-art/optimize-your-experience | Asset optimization, GPU/rendering |
| Test on Hardware | https://create.roblox.com/docs/performance-optimization/test-on-hardware | Why emulation isn't enough |

### Security
| Resource | URL | What It Covers |
|----------|-----|----------------|
| Security & Cheat Mitigation Tactics | https://create.roblox.com/docs/scripting/security/security-tactics | Never-trust-client, server authority, threat modeling |

### Studio & Tools
| Resource | URL | What It Covers |
|----------|-----|----------------|
| Studio Overview | https://create.roblox.com/docs/studio | Full Studio feature reference |
| Studio UI Overview | https://create.roblox.com/docs/en-us/studio/ui-overview | Tabs, tools, panels |
| Studio Tools | https://create.roblox.com/docs/get-started/tools | Transform, terrain, model tools |
| Art Creation Overview | https://create.roblox.com/docs/art/overview-studio | 3D art tools built into Studio |

### Community Guides (High Quality)
| Resource | URL | What It Covers |
|----------|-----|----------------|
| DevForum: Optimization Guide | https://devforum.roblox.com/t/tutorial-roblox-optimization-guide-memory-draw-calls-and-network-tips/3881861 | Memory, draw calls, network — practical |
| DevForum: Bandwidth Art | https://devforum.roblox.com/t/the-bandwith-art-learning-how-to-optimize-and-improve-your-game-network-performance/3865361 | Network compression, buffers, bandwidth |
| DevForum: Network Optimization | https://devforum.roblox.com/t/network-optimization-best-practices-how-to-keep-your-games-ping-low/1913475 | Remote byte costs, SerDes patterns |
| DevForum: Type Annotations Guide | https://devforum.roblox.com/t/type-annotations-a-guide-to-writing-luau-code-that-is-actually-good/2843221 | Practical --!strict usage |
| DevForum: Anti-Cheat Bad Practices | https://devforum.roblox.com/t/securing-your-anticheat-common-bad-practices-and-how-powerful-are-exploiters-guide-on-handshakes/2519952 | What exploiters can do, handshakes |
| Ozzypig: Improving Coding Habits | https://ozzypig.com/2021/11/22/your-code-sucks | Practical Luau code quality |
| Kampfkarren Luau Guidelines | https://github.com/Kampfkarren/kampfkarren-luau-guidelines | Advanced Luau style & patterns |
| Quenty Luau Conventions | https://quenty.github.io/NevermoreEngine/docs/conventions/luau | OOP, metatables, type patterns |
| DevForum: Community Services Collection | https://devforum.roblox.com/t/collection-of-useful-community-services-for-roblox-developers/3173037 | Curated module list |

---

## 2. Code Style & Conventions

**Source**: [Roblox Lua Style Guide](https://roblox.github.io/lua-style-guide/)

### Naming
- **PascalCase**: Services, ModuleScripts, classes, enum-like tables, public methods
- **camelCase**: Local variables, local functions, private methods, function parameters
- **UPPER_SNAKE_CASE**: Constants (true compile-time constants only)
- **Prefix with underscore**: Private members in OOP (`self._health`)
- **Boolean variables**: Prefix with `is`, `has`, `can`, `should` (e.g., `isAlive`, `hasShield`)

### Scope
- **Always use `local`**. Luau accesses local variables faster than globals. Global scope is almost never appropriate.
- Declare variables as close to their usage as possible.
- One variable per line — never `local a, b, c = 1, 2, 3` unless destructuring a function return.

### Formatting
- Use tabs for indentation (Roblox convention).
- No trailing whitespace.
- One blank line between function definitions.
- Keep lines under 120 characters.
- Always use explicit `then`, `do`, `end` — no shorthand.

### Functions
- Prefer named local functions over anonymous ones for readability and stack traces.
- If a function is only used in one place as a callback, anonymous is acceptable.
- Put the function definition before its first use.

### Requires
- All `require()` calls at the top of the file.
- Group by: Services → Shared Modules → Local Modules.
- One require per line.

```lua
-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Shared Modules
local Utility = require(ReplicatedStorage.Shared.Utility)

-- Local Modules
local CombatResolver = require(script.Parent.CombatResolver)
```

### Comments
- Use `--` for single line, `--[[ ]]` for multi-line.
- Comment *why*, not *what*. The code already says what.
- Use `-- TODO:` for known incomplete work (searchable).
- Use `-- HACK:` for known workarounds that should be fixed later.

---

## 3. Architecture: Server Authority Model

**Source**: [Roblox Security Tactics](https://create.roblox.com/docs/scripting/security/security-tactics)

### Principle: The Server Is the Source of Truth
- The server makes ALL gameplay decisions: damage, inventory, currency, progression, win conditions.
- The client's role is to **render** the world and **send user input** to the server.
- The client is a "dumb terminal" for critical logic.

### The Server's Job
1. Receive input from the client
2. Validate the requested action is possible and permissible
3. Execute the action and update authoritative state
4. Replicate results to relevant clients

### The Client's Job
1. Display the game world
2. Handle user input (mouse, keyboard, touch)
3. Send input events to the server via RemoteEvents
4. Play visual effects, animations, and sounds
5. **Never** make authoritative decisions

### Container Discipline
| Container | What Goes Here | Who Can See It |
|-----------|---------------|----------------|
| `ServerScriptService` | All server logic, game rules | Server only |
| `ServerStorage` | Server-side assets, maps, templates | Server only |
| `ReplicatedStorage` | Shared modules, RemoteEvents, shared assets | Server + Client |
| `StarterPlayerScripts` | Client boot scripts | Client only |
| `StarterGui` | UI templates | Client only |
| `ReplicatedFirst` | Loading screen, critical client-first assets | Client (loads first) |

**CRITICAL**: Never put game logic in `ReplicatedStorage`. Exploiters can read everything there. Only put assets and modules the client legitimately needs.

---

## 4. Security & Anti-Cheat

**Source**: [Roblox Security Tactics](https://create.roblox.com/docs/scripting/security/security-tactics)

### What Exploiters Can Do
- Decompile ANY replicated LocalScript or ModuleScript (even ones that never run on client)
- Fire or invoke RemoteEvents/RemoteFunctions with arbitrary arguments at any frequency
- Take network ownership of their character and unanchored parts
- Modify their local DataModel without firing expected events
- Alter behavior of any locally running code

### Mandatory Validation Rules

**Every RemoteEvent handler MUST:**
1. Validate the `player` argument (first arg, auto-provided)
2. Type-check every argument — reject unexpected types immediately
3. Range-check numerical values (damage, currency, coordinates)
4. Verify the player can actually perform the action (distance, cooldown, alive, has item)
5. Rate-limit calls per player

```lua
-- GOOD: Server validates everything
RemoteEvent.OnServerEvent:Connect(function(player, targetId, actionType)
    -- Type validation
    if typeof(targetId) ~= "number" or typeof(actionType) ~= "string" then
        return -- silently reject
    end

    -- Range check
    if targetId < 1 or targetId > MAX_TARGETS then
        return
    end

    -- Permission check
    if not canPlayerAct(player) then
        return
    end

    -- Rate limit
    if isRateLimited(player) then
        return
    end

    -- Execute with validated data
    processAction(player, targetId, actionType)
end)
```

### Security Patterns
- **Threat model every new feature**: "What if an attacker has full control of their client?"
- **Partition responsibilities early**: Keep logic in ServerScriptService from day one.
- Never store secrets (admin flags, drop rates, economy formulas) in replicated containers.
- Use server-side cooldowns — client-side cooldowns are cosmetic only.

---

## 5. Performance: Scripting

**Source**: [Roblox Performance Optimization](https://create.roblox.com/docs/projects/performance-optimization/memory), [Design for Performance](https://create.roblox.com/docs/performance-optimization/design)

### Frame Budget
- At 60 FPS, total budget per frame = **16.67ms**.
- Every per-frame calculation eats into this. Seemingly minor code can consume significant budget.

### Event-Driven, Not Per-Frame
```lua
-- BAD: Polling every frame
RunService.Heartbeat:Connect(function()
    if part.Position.Y < 0 then -- checked 60x/sec even if rarely true
        handleFall()
    end
end)

-- GOOD: Event-driven
part:GetPropertyChangedSignal("Position"):Connect(function()
    if part.Position.Y < 0 then
        handleFall()
    end
end)
```

### Break Up Long-Running Code
If code takes 100ms and runs every frame → game runs at 10 FPS. Instead, break work into chunks across frames:
```lua
-- Process 5ms of work per frame, complete over 20 frames
local index = 1
RunService.Heartbeat:Connect(function()
    local startTime = os.clock()
    while index <= #items and (os.clock() - startTime) < 0.005 do
        processItem(items[index])
        index += 1
    end
end)
```

### Connection Cleanup
- **Always** disconnect `RBXScriptConnection` when no longer needed.
- Use a cleanup pattern (Maid, Trove, or manual table of connections).

```lua
-- Track connections for cleanup
local connections = {}

table.insert(connections, event:Connect(handler))

-- On cleanup:
for _, conn in connections do
    conn:Disconnect()
end
table.clear(connections)
```

### Table Operations
- Complex serialization/deserialization and deep cloning are expensive on large tables.
- Avoid recursive operations on very large data structures.
- Cache method call results rather than calling the same method repeatedly.
- Use `table.create(n)` to pre-allocate arrays when size is known.

### task Library (Use Instead of Legacy)
| Use This | Not This | Why |
|----------|----------|-----|
| `task.spawn(fn)` | `coroutine.wrap(fn)()` | Proper error handling, scheduler-aware |
| `task.delay(t, fn)` | `delay(t, fn)` | Non-deprecated, scheduler-aware |
| `task.wait(t)` | `wait(t)` | Returns actual elapsed time, more accurate |
| `task.defer(fn)` | N/A | Runs next resumption cycle, after current thread |
| `task.cancel(thread)` | N/A | Clean cancellation |

---

## 6. Performance: Memory

**Source**: [Roblox Performance Optimization](https://create.roblox.com/docs/projects/performance-optimization/memory), [DevForum Optimization Guide](https://devforum.roblox.com/t/tutorial-roblox-optimization-guide-memory-draw-calls-and-network-tips/3881861)

### Collision Fidelity
This is one of the biggest hidden memory sinks.
- **Box**: Lowest memory. Use for decorative objects, walls, floors.
- **Hull**: Medium. Use for round objects that need collision.
- **Default / Precise**: Highest memory. Use ONLY when exact collision shape matters.

**Rule**: Default everything to `Box` unless gameplay requires hull/precise collision.

### Instance Management
- **Destroy instances** you no longer need — `instance:Destroy()` cleans up all connections and children.
- Don't just parent to `nil` — that leaks memory.
- Create sounds on-demand, destroy after playing. Don't hoard sounds in SoundService.
- For frequently spawned objects, use **object pooling** instead of repeated Instance.new + Destroy.

```lua
-- Sound on-demand pattern
local function playSound(soundId: string, parent: Instance)
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Parent = parent
    sound:Play()
    sound.Ended:Once(function()
        sound:Destroy()
    end)
end
```

### Storage Discipline
- **Never** store everything in `ReplicatedStorage` — it ALL loads on client.
- Put server-only assets in `ServerStorage`.
- Use `ReplicatedStorage` only for what the client genuinely needs.
- Maps/large assets → `ServerStorage`, clone to `Workspace` when needed.

### Streaming
- **Enable Instance Streaming** (`Workspace.StreamingEnabled = true`) for any world larger than a single screen.
- Streaming dynamically loads/unloads 3D content → better join times, lower memory, higher frame rate.
- Set `LevelOfDetail` to `SLIM` on models for distant rendering.
- `Workspace.EnableSLIMAvatars` for social spaces with many players.

### Workspace Settings (Quick Wins)
| Setting | Value | Effect |
|---------|-------|--------|
| `PlayerCharacterDestroyBehavior` | `Enabled` | Prevents character memory leaks |
| `ClientAnimatorThrottling` | `true` | Throttles distant animations |
| `PhysicsSteppingMethod` | `Adaptive` | Reduces physics CPU for distant objects |

---

## 7. Performance: Draw Calls & Rendering

**Source**: [DevForum Optimization Guide](https://devforum.roblox.com/t/tutorial-roblox-optimization-guide-memory-draw-calls-and-network-tips/3881861), [Design for Performance](https://create.roblox.com/docs/performance-optimization/design)

### Draw Call Budget
- Target: **under 500 draw calls** (check via Ctrl+Shift+F2 → "Scene Draw Count")
- Under 1,000,000 triangles for mobile baseline.

### Reducing Draw Calls
- **Reuse MeshIds**: Identical meshes with the same `MeshId` batch into fewer draw calls. If you import the same mesh twice with different IDs, that's 2 draw calls instead of 1.
- **Particle emitters**: Each emitter = 1 draw call regardless of particle count. Disable emitters when distant from player.
- **Built-in materials** use far less memory than custom textures. Use materials first, save texture budget for hero assets.
- **MeshPart RenderFidelity**: Set to `Automatic` instead of `Precise` unless close-up detail matters.

### Transparency
- Only use transparency values of **0 (visible)** or **1 (invisible)**.
- Partial transparency (0.1–0.9) is expensive — causes transparency overdraw.
- When you must use partial transparency, minimize overlapping transparent objects.

### Asset Reuse
- Reuse meshes and textures by resizing, rotating, overlapping.
- Convert reused assets into **Packages** to avoid duplicate IDs.
- Search Explorer for duplicate MeshIds — consolidate them.

---

## 8. Performance: Networking & Bandwidth

**Source**: [DevForum: Network Optimization](https://devforum.roblox.com/t/network-optimization-best-practices-how-to-keep-your-games-ping-low/1913475), [DevForum: Bandwidth Art](https://devforum.roblox.com/t/the-bandwith-art-learning-how-to-optimize-and-improve-your-game-network-performance/3865361)

### Budget
- Incoming network: target **under 50 KB/s** (check via F9 → ServerStats → Total Data KB/s).
- Over 100 KB/s = almost certainly needs optimization.

### The Golden Rule: Server Simulates, Client Visualizes
| Server Does | Client Does |
|------------|-------------|
| Game logic, damage, state | Visual effects, particles, tweens |
| Authoritative positions | Interpolated/predicted rendering |
| Data storage | UI display |
| Hit detection | Hit feedback (sounds, animations) |

**NEVER** on the server:
- Tween parts for visual effects
- Play animations (replicate the trigger, let client animate)
- Create particle effects
- Update CFrames for visual-only movement

### Remote Event Costs
| Data Type | Size |
|-----------|------|
| Remote overhead (empty fire) | 9 bytes |
| Each value type overhead | 1 byte |
| Number (Float64) | 8 + 1 bytes |
| Vector3 (3× Float32) | 12 + 1 bytes |
| String | length + 2 + 1 bytes |
| Instance reference | 4 + 1 bytes |
| Boolean | 1 + 1 bytes |
| CFrame (axis-aligned rotation) | Position + 1 byte rotation ID |

### Optimization Patterns
1. **Send minimal data**: Only send what the recipient needs. If client only needs an item name, don't send the whole item table.
2. **Arrays over dictionaries**: Dictionary keys are strings and cost bytes. Arrays use no extra space for indices.
3. **UnreliableRemoteEvent**: For non-critical, frequent updates (particles, cosmetic effects). 1000 byte limit but server can skip them under load.
4. **Batch remotes**: Instead of firing 10 separate events, fire one event with a table of 10 actions.
5. **Buffer compression**: For high-frequency data, use `buffer` library to pack numbers into minimal bytes.
6. **BulkMoveTo**: For moving many parts, use `Workspace:BulkMoveTo()` instead of setting each CFrame individually.

```lua
-- GOOD: BulkMoveTo for mass updates
workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

-- BAD: Individual CFrame updates
for _, part in parts do
    part.CFrame = newCFrame -- each one replicates separately
end
```

---

## 9. Roblox Studio Native Tools (Use These First)

Before reaching for community modules or custom code, check if Roblox already provides it.

### Instance & Data Tools
| Tool | Use Instead Of | Why |
|------|---------------|-----|
| **Attributes** (`:SetAttribute()` / `:GetAttribute()`) | ValueObjects (StringValue, IntValue, etc.) | Less overhead, no extra instances, type-safe, observable via `GetAttributeChangedSignal` |
| **CollectionService Tags** | Manual tables tracking instances | Engine-level tracking, survives streaming, `GetTagged()` + `GetInstanceAddedSignal()` |
| **Collections** (new, 2026) | CollectionService for complex queries | Live query-based grouping — auto-adds/removes instances matching a query pattern |

### UI Layout Tools
| Tool | Use Instead Of | Why |
|------|---------------|-----|
| `UIListLayout` | Manual `Position` offsets | Auto-arranges children, responds to additions/removals |
| `UIGridLayout` | Manual grid positioning | Automatic grid with configurable cell size |
| `UIPageLayout` | Custom page-swipe logic | Built-in page navigation |
| `UITableLayout` | Custom table rendering | Row/column layout with headers |
| `AutomaticSize` | Manual `.Size` calculations | Frame auto-sizes to content |
| `UIFlexItem` | Custom flex logic | Flexbox-like layout within UIListLayout |
| `UISizeConstraint` | Clamping in scripts | Min/max size enforcement |
| `UIAspectRatioConstraint` | Manual ratio math | Maintains aspect ratio |
| `UIScale` | Manual scaling math | Scale factor for UI trees |

### Physics & Movement
| Tool | Use Instead Of | Why |
|------|---------------|-----|
| **Constraints** (SpringConstraint, HingeConstraint, etc.) | BodyPosition, BodyGyro (deprecated) | Modern, configurable, stable |
| **LinearVelocity** / **AngularVelocity** | BodyVelocity (deprecated) | Replacements for deprecated body movers |
| **AlignPosition** / **AlignOrientation** | BodyPosition / BodyGyro | Modern replacements |
| **Attachments** | CFrame math for constraint endpoints | Clean anchor points for constraints |
| **WeldConstraint** | Manual `Weld` with C0/C1 | Zero-config welding |

### Animation & Visual
| Tool | Use Instead Of | Why |
|------|---------------|-----|
| **Animation Editor** | External tools | Built into Studio, direct export |
| **TweenService** | Manual interpolation loops | Optimized, handles easing, cancellable |
| **Terrain** | Part-based ground | Optimized rendering, built-in materials, water |

### Debugging & Profiling
| Tool | How to Access | What It Shows |
|------|---------------|---------------|
| **Script Profiler** | View → Script Profiler | Per-function CPU time |
| **MicroProfiler** | Ctrl+F6 | Frame-level timing breakdown |
| **Developer Console** | F9 | Memory, network, log, errors |
| **Render Stats** | Shift+F2 | Draw calls, triangles, FPS |
| **Physics Stats** | Shift+F3 | Physics step time, contacts |
| **Network Stats** | Shift+F4 | Bandwidth in/out |
| **Device Emulator** | Test → Device | Aspect ratio, touch simulation (NOT accurate for memory) |
| **Output Window** | View → Output | Print, warn, error messages |

---

## 10. Modern Luau Features

### Type Annotations & Strict Mode
**Source**: [Roblox Type Checking Docs](https://create.roblox.com/docs/luau/type-checking), [DevForum: Type Annotations Guide](https://devforum.roblox.com/t/type-annotations-a-guide-to-writing-luau-code-that-is-actually-good/2843221)

```lua
--!strict  -- ADD THIS TO EVERY SCRIPT

-- Type-annotated function
local function calculateDamage(baseDamage: number, multiplier: number): number
    return baseDamage * multiplier
end

-- Custom types
type WeaponData = {
    name: string,
    damage: number,
    range: number,
    cooldown: number,
}

-- Generic types
type Array<T> = {T}
type Dict<K, V> = {[K]: V}

-- Optional values
local function findPlayer(name: string): Player?
    -- May return nil
end
```

**Rule**: Use `--!strict` on every new script. It catches bugs at write-time instead of runtime.

### Generalized Iteration
```lua
-- Modern (preferred)
for key, value in dictionary do
    -- works on tables, arrays, custom iterators
end

-- Legacy (avoid)
for key, value in pairs(dictionary) do end
for index, value in ipairs(array) do end
```

### String Interpolation
```lua
-- Modern (preferred)
local message = `{player.Name} dealt {damage} damage to {target.Name}`

-- Legacy (avoid)
local message = player.Name .. " dealt " .. tostring(damage) .. " damage to " .. target.Name
```

### If-Expression
```lua
-- Modern (for simple assignments)
local status = if health > 0 then "alive" else "dead"

-- Still use if-then-end for multi-line logic
```

### Native Code Generation
```lua
--!native  -- Opt-in per script
-- Best for: pure computation scripts (math, pathfinding, serialization)
-- NOT for: scripts that spend most time waiting on engine API calls
-- ALWAYS profile before and after to verify actual improvement
```

### Parallel Luau (Actor Model)
- Place scripts under `Actor` instances to run on separate threads.
- Use `task.desynchronize()` to enter parallel phase, `task.synchronize()` to re-enter serial.
- Actors cannot directly share memory — use `Actor:SendMessage()` or `SharedTable`.
- Best for: NPC AI, pathfinding, spatial queries across many entities.
- Not worth it for: simple scripts, anything that mostly calls engine APIs (those run serial anyway).

---

## 11. Common Mistakes & Anti-Patterns

### Scripting Anti-Patterns
| Mistake | Why It's Bad | Do This Instead |
|---------|-------------|-----------------|
| Using `wait()` | Deprecated, imprecise, returns old delta | `task.wait()` |
| Using `spawn()` | Deprecated, 1-frame delay, poor error handling | `task.spawn()` |
| Using `delay()` | Deprecated | `task.delay()` |
| Global variables | Slower access, pollutes namespace, hard to trace | `local` everything |
| `Instance.new("Part", parent)` | Second arg is deprecated, sets Parent before properties | Create → set properties → set Parent last |
| Polling with `while true do wait()` | Wastes frames, imprecise timing | Event-driven or `RunService` connections |
| Not disconnecting events | Memory leak, phantom callbacks | Track and `:Disconnect()` |
| `require()` inside functions | Re-requires every call (no caching concern but confusing pattern) | Require at top of file |
| Deep-nesting if/else | Unreadable | Early returns (guard clauses) |
| String concatenation in loops | Creates intermediate strings | `table.concat()` or string interpolation |
| Using `game.Workspace` | Deprecated syntax | `workspace` (global) or `game:GetService("Workspace")` |

### Architecture Anti-Patterns
| Mistake | Why It's Bad | Do This Instead |
|---------|-------------|-----------------|
| Game logic in LocalScripts | Exploitable, not authoritative | Server scripts + client rendering |
| Everything in ReplicatedStorage | Client downloads ALL of it; exposes code to exploiters | Use ServerStorage for server-only assets |
| Client-side hit detection | Exploiter auto-hits everything | Server validates all hits |
| Trusting RemoteEvent arguments | Exploiter sends anything | Validate every argument server-side |
| One giant script | Unmaintainable, hard to debug | ModuleScripts with single responsibility |
| Circular requires | Runtime error | Restructure dependency graph |

### Performance Anti-Patterns
| Mistake | Why It's Bad | Do This Instead |
|---------|-------------|-----------------|
| Tweening on server | Replicates every frame to every client | Fire remote → client tweens locally |
| Server-side animations | Bandwidth hog | Fire remote → client plays animation |
| Server-side particles | Each property change replicates | Client creates particles on signal |
| `Instance.new` in hot loops | GC pressure, slow | Object pool or pre-clone from template |
| Not using BulkMoveTo | N separate replications | `Workspace:BulkMoveTo()` |
| Precise collision on decorative parts | Memory waste | `CollisionFidelity = Box` |
| Sounds hoarded in SoundService | Memory waste | Create on demand, destroy after playback |

---

## 12. Roblox-Specific Patterns & Idioms

### The Module Pattern
```lua
-- Shared/MathUtil.lua
local MathUtil = {}

function MathUtil.clamp(value: number, min: number, max: number): number
    return math.max(min, math.min(max, value))
end

function MathUtil.lerp(a: number, b: number, t: number): number
    return a + (b - a) * t
end

return table.freeze(MathUtil)
```

### Service Locator Pattern
```lua
-- Get services once at top of file
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
-- NEVER use game.Players — always game:GetService()
```

### Instance Creation Order
```lua
-- CORRECT: Set properties BEFORE parenting
local part = Instance.new("Part")
part.Size = Vector3.new(4, 1, 4)
part.Position = Vector3.new(0, 10, 0)
part.Anchored = true
part.Material = Enum.Material.SmoothPlastic
part.Parent = workspace -- Parent LAST

-- WRONG: Parent first (causes unnecessary property-change replications)
local part = Instance.new("Part", workspace) -- deprecated second arg
part.Size = Vector3.new(4, 1, 4) -- each change replicates
```

### CollectionService Tag Pattern
```lua
local CollectionService = game:GetService("CollectionService")

-- On server or client, bind behavior to tagged instances
local function onDamageable(instance: BasePart)
    -- Setup behavior
    instance.Touched:Connect(function(hit) ... end)
end

for _, instance in CollectionService:GetTagged("Damageable") do
    onDamageable(instance)
end
CollectionService:GetInstanceAddedSignal("Damageable"):Connect(onDamageable)
```

### Attribute Pattern (Replacing ValueObjects)
```lua
-- GOOD: Attributes
part:SetAttribute("Health", 100)
part:SetAttribute("MaxHealth", 100)
part:SetAttribute("Team", "Blue")

part:GetAttributeChangedSignal("Health"):Connect(function()
    local health = part:GetAttribute("Health")
    updateHealthBar(health)
end)

-- AVOID: ValueObjects
local healthValue = Instance.new("IntValue")
healthValue.Name = "Health"
healthValue.Value = 100
healthValue.Parent = part -- extra instance, extra overhead
```

### Object Pooling
```lua
local pool: {Part} = {}

local function getFromPool(): Part
    if #pool > 0 then
        local obj = table.remove(pool)
        obj.Parent = workspace
        return obj
    end
    -- Pool empty, create new
    local obj = Instance.new("Part")
    obj.Parent = workspace
    return obj
end

local function returnToPool(obj: Part)
    obj.Parent = nil -- remove from world but keep alive
    table.insert(pool, obj)
end
```

---

## 13. UI Best Practices

### Mobile-First Design
- CTRBLXAI is primarily mobile. **All interactions must use tap (touch) events only.**
- No hover-based patterns — hover doesn't exist on mobile.
- Use `UIListLayout` / `UIGridLayout` / `AutomaticSize` for responsive layouts.
- Test with Device Emulator for aspect ratios.
- Minimum touch target: **44×44 pixels** equivalent.
- Use `UDim2` with `Scale` (0–1) for responsive sizing, not `Offset` (pixels).

### Layer Organization
- Use `ScreenGui.DisplayOrder` to manage z-ordering between different UI systems.
- Use `ZIndex` within a single ScreenGui for local ordering.
- `ScreenGui.IgnoreGuiInset` = true for fullscreen UI (ignores top bar).

### Input Handling
```lua
-- Modern input (recommended)
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end -- UI already handled it
    -- Handle game input
end)

-- For GUI buttons
button.Activated:Connect(function() -- works for click AND touch
    -- Handle button press
end)
```

---

## 14. Data Management

### DataStoreService Best Practices
- **Session locking**: Prevent data corruption from multiple servers accessing same player data.
- **Auto-save**: Save periodically (every 30–60 seconds) AND on `PlayerRemoving` AND on `game:BindToClose()`.
- **Retry with backoff**: DataStore calls can fail. Retry with exponential backoff.
- **Budget management**: DataStore has request budgets. Check `DataStoreService:GetRequestBudgetForRequestType()`.
- **Data versioning**: Store a version number in saved data to handle schema migrations.

### ProfileService / DataStore Pattern
For production games, use a data management module (ProfileService or similar) that handles:
- Session locking
- Auto-saving
- Error recovery
- Data migration

### MemoryStoreService
- For temporary, shared data between servers (lobbies, matchmaking, leaderboards).
- Data expires — set appropriate TTL.
- Not for persistent data — use DataStoreService for that.

---

## 15. Community Libraries Worth Knowing

These are well-established, widely-used libraries the agent should be aware of:

| Library | Purpose | Notes |
|---------|---------|-------|
| **ProfileService** | DataStore wrapper with session locking | De facto standard for player data |
| **Knit** | Service/controller framework | Opinionated but clean architecture |
| **Trove** / **Maid** | Cleanup/lifecycle management | Track and clean up connections, instances |
| **Promise** | Asynchronous operation management | evaera's Promise library, Lua adaptation |
| **Signal** (GoodSignal) | Custom events | Faster than BindableEvents for in-code signaling |
| **Packet** / **ByteNet** | Networking optimization | Buffer-based remote compression |
| **Weave** | Parallel Luau job scheduler | Job-based parallelism library |

**Rule**: Prefer Roblox-native solutions first. Use community libraries when Roblox doesn't provide the feature or the native approach is significantly worse.

---

## 16. Platform Limitations & Constraints

### Hard Limits
| Limit | Value |
|-------|-------|
| Max players per server | 700 (but practical limit much lower) |
| Instance count warning | ~1,000,000 instances |
| DataStore key size | 50 characters |
| DataStore value size | 4 MB (4,194,304 characters) |
| DataStore requests/min | Varies by request type and player count |
| RemoteEvent payload | No hard limit but practical limit ~1KB per call |
| UnreliableRemoteEvent payload | **1,000 bytes hard limit** |
| HttpService request size | 500 KB |
| HTTP requests/minute | 500 |
| MemoryStore sorted map items | 128 KB per item |
| Audio length (uploaded) | 7 minutes |
| Mesh triangle count | Engine handles LOD, but <10K tris per mesh recommended |

### Runtime Constraints
- Luau runs single-threaded per script (unless using Parallel Luau Actors).
- Physics simulation is shared across all scripts — heavy physics = less script budget.
- Mobile devices have ~1–2 GB usable RAM. OOM crashes are the #1 mobile stability issue.
- Client and server share the same Luau VM when testing in Studio — performance metrics are unreliable. Always test on real devices.
- The Device Emulator is useful for aspect ratio but **not** for memory or performance.

### Known Gotchas
- `Humanoid` is expensive. Every property change fires events. Minimize Humanoid usage on NPCs if possible (use simple parts + CFrame for non-player entities).
- `FindFirstChild` is O(n) on children count. For frequent lookups, cache the result.
- `GetChildren()` / `GetDescendants()` create new tables every call. Cache if called frequently.
- `:Clone()` is deep — it clones all descendants. For large hierarchies, this is expensive.
- `:WaitForChild()` yields the thread. Use with timeout to avoid infinite hangs: `:WaitForChild("Name", 5)`.
- `math.random()` seeds differently per script. Use `Random.new()` for reproducible sequences.

---

## 17. Rojo Workflow & External Tooling

**The reference doc originally ignored Rojo entirely. This is critical because AI-assisted development typically uses Rojo to sync files from an external editor into Roblox Studio.**

### What Is Rojo
Rojo is a tool that syncs a folder of Lua files on disk into Roblox Studio's DataModel in real-time. You edit `.lua` files in VS Code (or let AI write them), and Rojo mirrors the changes into Studio instantly.

### File Naming Conventions (Rojo)
Rojo uses file extensions to determine what kind of script to create:

| File Extension | Roblox Script Type | Runs On |
|---------------|-------------------|---------|
| `MyModule.lua` | ModuleScript | Wherever required |
| `Main.server.lua` | Script (server) | Server only |
| `Client.client.lua` | LocalScript | Client only |
| `init.lua` | ModuleScript (as folder's "self") | Like `__init__.py` in Python |
| `init.server.lua` | Script (as folder's "self") | Server |
| `init.client.lua` | LocalScript (as folder's "self") | Client |

**Rule**: The file extension determines execution context. A `.lua` file is a ModuleScript that does nothing on its own — it must be `require()`d. A `.server.lua` runs automatically on the server. A `.client.lua` runs automatically on the client.

### Project File (`default.project.json`)
Maps your filesystem folders to Roblox's DataModel containers:
```json
{
  "name": "MyGame",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "$path": "source/ReplicatedStorage"
    },
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "$path": "source/ServerScriptService"
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "StarterPlayerScripts": {
        "$className": "StarterPlayerScripts",
        "$path": "source/StarterPlayer/StarterPlayerScripts"
      }
    }
  }
}
```

### Critical Rojo Gotchas
1. **Rojo only reads `default.project.json` on startup**. If you edit the project file, you must restart `rojo serve`.
2. **Rojo deletes instances not in your file tree**. If Studio has instances that don't exist in your source folder, Rojo removes them on sync. This is by design — the filesystem is the source of truth.
3. **Non-script instances** (Parts, Models, UI) cannot be represented as `.lua` files. They live in `.rbxm` or `.rbxmx` files, or are created by scripts at runtime. Rojo is primarily for scripts and data modules.
4. **$properties in project.json** can set service-level properties (like `CharacterAutoLoads = false` on Players), but these only apply when Rojo builds or syncs the project.
5. **Folder structure = DataModel hierarchy**. A file at `source/ServerScriptService/Game/CombatResolver.lua` becomes `ServerScriptService.Game.CombatResolver` in Studio. The folder `Game` becomes a Folder instance.

### Rojo + AI Workflow Rules
- **Always work on `.lua` files on disk**, never edit scripts directly in Studio while Rojo is connected (Studio edits get overwritten on next file save).
- **One script per file**. Each `.lua` file = one ModuleScript/Script/LocalScript.
- **Test changes by playing in Studio** after Rojo syncs them. Watch the Output window for errors.
- When creating a new module, place the `.lua` file in the correct filesystem path — Rojo handles the rest.

---

## 18. Module Architecture & Dependency Management

### The Circular Dependency Problem
**This is the #1 architecture issue in growing Roblox codebases.** When Module A requires Module B and Module B requires Module A, you get: `Requested module was required recursively`.

### Solution: Dependency Injection
Instead of having two modules require each other, have a third party (the orchestrator) inject the dependency at runtime:

```lua
-- BattleCoordinator.lua (CANNOT require TileEffectService directly)
local BattleCoordinator = {}
local _tileEffectService = nil  -- injected at runtime

function BattleCoordinator.SetTileEffectService(tes)
    _tileEffectService = tes
end

function BattleCoordinator.SomeFunction()
    if _tileEffectService then
        _tileEffectService.DoThing()
    end
end

return BattleCoordinator
```

```lua
-- Main.server.lua (the orchestrator — wires everything together)
local BattleCoordinator = require(Game.BattleCoordinator)
local TileEffectService = require(Game.TileEffectService)

-- Inject dependencies after both are loaded
BattleCoordinator.SetTileEffectService(TileEffectService)
```

**Rules for dependency injection:**
1. The injected dependency MUST be nil-safe — always check `if _injectedModule then` before calling.
2. Document the injection requirement in a comment at the top of the file.
3. The orchestrator (usually `Main.server.lua`) is responsible for all injections.
4. Keep the injection count low — if a module needs 5+ injections, it has too many responsibilities.

### Alternative: Callback/Event Pattern
When Module A needs to notify Module B of something but can't require it:
```lua
-- StatusService.lua — returns a flag, caller handles the action
function StatusService.ApplyStatus(unit, statusId, ...)
    local disruptsChannel = CHANNEL_DISRUPTORS[statusId] == true
    return applied, disruptsChannel  -- caller checks this and acts
end
```
The caller (Main loop) checks the return value and calls BattleCoordinator itself. StatusService never needs to know BattleCoordinator exists.

### File Size Discipline
**Problem**: Files grow until they become unmaintainable. 

| Threshold | Action |
|-----------|--------|
| **< 500 lines** | Healthy. No action needed. |
| **500–1000 lines** | Watch it. Consider if responsibilities can be split. |
| **1000–2000 lines** | Split into sub-modules. Extract logical sections. |
| **> 2000 lines** | Mandatory refactor. This file is doing too much. |

**How to split**: Identify groups of functions that share a responsibility. Extract them into a new ModuleScript. The original file requires and delegates to it.

### Require Path Patterns
```lua
-- SERVER scripts requiring sibling modules (same folder):
local CombatResolver = require(script.Parent.CombatResolver)

-- SERVER scripts requiring content data from ReplicatedStorage:
local WeaponData = require(
    game:GetService("ReplicatedStorage")
        :WaitForChild("Content")
        :WaitForChild("WeaponData")
)

-- CLIENT scripts — ALWAYS use WaitForChild with timeout for replicated content:
local GameConstants = require(
    ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
        :WaitForChild("Shared", 10)
        :WaitForChild("GameConstants", 10)
)

-- Graceful require for optional modules:
local ok, VFXController = pcall(require,
    ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
        :WaitForChild("Shared", 10)
        :WaitForChild("VFXController", 10)
)
if not ok then
    warn("[Module] VFXController not available: " .. tostring(VFXController))
    VFXController = nil
end
```

---

## 19. WaitForChild & Module Loading Order

### The Core Rule
- **Server scripts**: Can use direct indexing (`script.Parent.ModuleName`) for sibling modules in `ServerScriptService` because server content is available immediately.
- **Client scripts**: MUST use `WaitForChild()` for anything in `ReplicatedStorage` because content replicates from server to client and may not be available when the script starts.

### Always Use Timeouts on Client
```lua
-- GOOD: Timeout prevents infinite yield if something is missing
local module = parent:WaitForChild("ModuleName", 10)
if not module then
    error("ModuleName failed to replicate within 10 seconds")
end

-- BAD: No timeout — if ModuleName doesn't exist, this yields FOREVER
local module = parent:WaitForChild("ModuleName")
```

**Rule**: Every `WaitForChild` on the client MUST have a numeric timeout (5–10 seconds is typical).

### Chaining WaitForChild
When you need to reach a deeply nested module, chain WaitForChild calls:
```lua
-- Each step waits for its child with a timeout
local BattleEvents = require(
    ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
        :WaitForChild("Remotes", 10)
        :WaitForChild("BattleEvents", 10)
)
```
**Warning**: If the first `WaitForChild` times out and returns nil, the next `:WaitForChild()` call will error ("attempt to index nil"). Wrap in pcall or check each step.

### Loading Order Facts
1. `ReplicatedFirst` scripts run first on the client — use for loading screens.
2. `StarterPlayerScripts` and `StarterGui` scripts run after ReplicatedFirst.
3. Server scripts in `ServerScriptService` run as soon as the server starts.
4. The order scripts RUN within the same container is NOT guaranteed.
5. Module scripts run when first `require()`d, not when they appear in the DataModel.

---

## 20. Spatial Lookups & Caching

### The O(n) Trap: Iterating Children to Find a Tile
```lua
-- BAD: O(n) per lookup — iterates ALL children every time
local function findTilePart(x, y)
    for _, child in mapFolder:GetChildren() do
        if child:GetAttribute("X") == x and child:GetAttribute("Y") == y then
            return child
        end
    end
    return nil
end
```
On a 30×20 map, that's checking up to 600 children per call. If called 50 times per turn, that's 30,000 iterations.

### Solution: Build a Lookup Dictionary
```lua
-- GOOD: O(1) per lookup — build once, query instantly
local tileLookup: {[string]: BasePart} = {}

local function buildTileLookup(mapFolder: Folder)
    table.clear(tileLookup)
    for _, child in mapFolder:GetChildren() do
        local x = child:GetAttribute("X")
        local y = child:GetAttribute("Y")
        if x and y then
            tileLookup[x .. "," .. y] = child
        end
    end
end

local function findTilePart(x: number, y: number): BasePart?
    return tileLookup[x .. "," .. y]
end
```

### General Rule: Cache Expensive Lookups
- `GetChildren()` creates a new table every call. If you need it multiple times, store the result.
- `FindFirstChild()` is O(n) on children count. Cache the result in a local variable.
- Any lookup that runs inside a loop or per-frame should use a dictionary, not iteration.
- Rebuild the cache only when the underlying data changes (e.g., after map generation).

---

## 21. RemoteEvent Architecture at Scale

### The Problem: Remote Explosion
As a game grows, you end up with dozens of RemoteEvents. Each one is an Instance in the DataModel. Managing them gets unwieldy.

### Pattern: Centralized Remote Registry Module
```lua
-- BattleEvents.lua (shared module in ReplicatedStorage)
local EVENT_NAMES = { "BattleStarted", "UnitMoved", "UnitActed", ... }

local BattleEvents = {}
for _, name in EVENT_NAMES do
    local existing = remoteFolder:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then
        BattleEvents[name] = existing
    else
        local event = Instance.new("RemoteEvent")
        event.Name = name
        event.Parent = remoteFolder
        BattleEvents[name] = event
    end
end
return BattleEvents
```

**Benefits**: Both server and client require the same module and access remotes by name (`BattleEvents.UnitMoved:FireAllClients(data)`). No string-based lookups scattered through the codebase.

### Rules
1. **One registry module per system** (BattleEvents, MenuEvents, etc.) — not one global registry for everything.
2. **Name events by what happened**, not what should happen: `UnitMoved` not `MoveUnit`. Server→Client events describe facts; Client→Server events describe intentions.
3. **Keep payloads minimal**. Don't send the entire unit table — send the unit ID and the fields that changed.
4. **RemoteFunctions** (server←→client request/response) are appropriate for inventory queries, stat lookups, etc. Use them for "give me data" patterns. Use RemoteEvents for "something happened" patterns.

---

## 22. Logging & Debugging Discipline

### Problem: `print()` Spam
Using `print()` everywhere makes Output unreadable and has performance cost in production.

### Tiered Logging Pattern
```lua
-- Use print() for normal operational messages
print("[BattleCoordinator] Turn started for: " .. unit.name)

-- Use warn() for unexpected but recoverable situations
warn("[StatusService] Unknown status: " .. tostring(statusId))

-- Use error() for unrecoverable problems that should halt execution
error("[CombatResolver] Unit has no weapon data — cannot resolve attack")
```

### Rules
1. **Prefix every log with `[ModuleName]`** so you can filter Output by system.
2. **Use `warn()` not `print()` for things that shouldn't normally happen** — they show in orange/yellow in Output, making them scannable.
3. **Never leave raw `print(variable)` debug statements in committed code**. Convert to structured messages or remove.
4. **Use string interpolation** for log messages (cleaner than `string.format` chains):
```lua
-- Preferred
print(`[Combat] {unit.name} dealt {damage} to {target.name}`)

-- Legacy (still works, just verbose)
print(string.format("[Combat] %s dealt %d to %s", unit.name, damage, target.name))
```
5. **For conditional debug logging** (only during development):
```lua
local DEBUG_COMBAT = false  -- flip to true when debugging

local function debugLog(message: string)
    if DEBUG_COMBAT then
        print("[DEBUG:Combat] " .. message)
    end
end
```

---

## 23. Data Module Organization

### Problem: Monolithic Data Files
Data modules (weapon stats, skill definitions, terrain types) grow huge because game content is constantly added. A single file with 2500+ lines becomes hard to navigate and error-prone to edit.

### Rules for Data Modules
1. **One data domain per file**: WeaponData.lua, SkillData.lua, ArmorData.lua — not AllGameData.lua.
2. **Shared constants belong in a Constants module**, not duplicated across files.
3. **Freeze data tables** with `table.freeze()` to prevent accidental mutation:
```lua
local WeaponData = {
    Longsword = { damage = 40, range = 1, speed = 5 },
    Shortbow  = { damage = 30, range = 4, speed = 3 },
}
return table.freeze(WeaponData)
```
4. **Never mix static data and runtime state** in the same module. If a module defines constants AND has mutable state that gets overwritten at runtime, split them.
5. **Constants that multiple files need** (like `TILE_SIZE`, `ELEVATION_STEP`) must live in ONE shared module, not be redefined in each file that uses them:
```lua
-- BAD: Same constant defined in 3 different files
-- MapRenderer.lua:     local TILE_SIZE = 5
-- BattleVisualClient:  local TILE_SIZE = 5
-- DeploymentUI:        local TILE_SIZE = 5
-- If you change it in one and forget the others → desync bug.

-- GOOD: Define once in GameConstants, require everywhere
-- GameConstants.lua:   GameConstants.TILE_SIZE = 5
-- MapRenderer.lua:     local TILE_SIZE = GameConstants.TILE_SIZE
-- BattleVisualClient:  local TILE_SIZE = GameConstants.TILE_SIZE
```

---

## 24. Trial-and-Error Lessons (Things Docs Don't Teach)

These are patterns and pitfalls learned from real Roblox development experience — the kind of knowledge that usually takes months of debugging to acquire.

### 1. Instance.new Parent Order REALLY Matters for Networking
When you `Instance.new("Part")` and set `.Parent = workspace` BEFORE setting properties, every subsequent property change (Size, Position, Color, Material) sends a separate network replication to all clients. On a tile-map with 600 tiles, this means thousands of unnecessary network packets during map generation. Always set ALL properties BEFORE parenting.

### 2. `GetChildren()` Returns a New Table Every Time
```lua
-- BAD: Creates 2 tables per frame
RunService.Heartbeat:Connect(function()
    for _, child in workspace.Folder:GetChildren() do ... end
    for _, child in workspace.Folder:GetChildren() do ... end
end)

-- GOOD: Cache if you need it more than once
local children = workspace.Folder:GetChildren()
for _, child in children do ... end
for _, child in children do ... end  -- reuses same table
```

### 3. Surface Properties Default to Smooth (Modern Roblox)
You do NOT need to manually set all 6 surface types to Smooth on new Parts:
```lua
-- UNNECESSARY in modern Roblox (2022+):
part.TopSurface    = Enum.SurfaceType.Smooth
part.BottomSurface = Enum.SurfaceType.Smooth
-- (4 more...)
-- Parts already default to SmoothNoOutlines. This is dead code.
```

### 4. RemoteEvent First Argument Is ALWAYS the Player (Server-Side)
On the server, `OnServerEvent` automatically prepends the firing player:
```lua
-- CLIENT fires:
RemoteEvent:FireServer("attack", targetId)

-- SERVER receives:
RemoteEvent.OnServerEvent:Connect(function(player, action, targetId)
    -- `player` is auto-injected, NOT sent by client
    -- DO NOT try to send player from client — it's forged
end)
```

### 5. Studio Play Mode ≠ Real Client
When you hit Play in Studio, both server and client run in the same process. This means:
- Memory usage is ~2x what a real client sees.
- Network "latency" is 0ms — race conditions don't manifest.
- Module loading is instant — `WaitForChild` always succeeds immediately.
- Performance profiling is unreliable. **Always test on a real device for performance and memory.**

### 6. `Destroy()` vs `Parent = nil`
- `:Destroy()` — disconnects all events, locks the instance, destroys all descendants. The instance becomes unusable. Use for permanent cleanup.
- `.Parent = nil` — removes from DataModel but keeps the instance alive in memory. Connections remain active. Use only for object pooling (where you plan to re-parent it later).
- **Common bug**: Setting `Parent = nil` thinking it's cleaned up, but event connections keep firing on a phantom instance.

### 7. `table.freeze()` Is Shallow
```lua
local data = table.freeze({
    weapons = { Sword = { damage = 10 } }  -- inner table is NOT frozen
})
data.weapons.Sword.damage = 999  -- THIS WORKS — inner table is mutable!
```
For deep freeze, you need to recursively freeze nested tables. Or accept shallow freeze and be disciplined about not mutating nested data.

### 8. The "One-Player Test" Trap
Many bugs only appear with 2+ players or with network latency. A feature that works perfectly in solo Play mode may break with:
- Race conditions between players
- Network ownership conflicts
- Replication delays for remote events
- Multiple players triggering the same event simultaneously

Test with Studio's local server (2-player mode) regularly, not just solo Play.

### 9. `string.format` with `%s` Crashes on nil
```lua
-- CRASHES if target.name is nil:
string.format("Hit %s for %d damage", target.name, damage)

-- SAFE:
string.format("Hit %s for %d damage", tostring(target.name), damage)
-- OR use string interpolation (handles nil gracefully):
`Hit {target.name} for {damage} damage`
```

### 10. Event Connection Memory Leaks Are Silent
The #1 source of server memory leaks. If you connect to a PlayerAdded event and store data per-player but never clean up on PlayerRemoving, memory grows with every player join/leave. After 24 hours with hundreds of players cycling through, the server runs out of memory. This never shows up in a 5-minute test.

### 11. `require()` Is Cached — Except Across Actors
When you `require(module)` multiple times, Luau returns the same cached table. This is good — it means all scripts share the same module state. **EXCEPTION**: In Parallel Luau, each Actor has its own require cache. A module required in Actor A returns a DIFFERENT table than the same module required in Actor B. You cannot use modules to share state between Actors.

### 12. Rojo File Rename = Delete + Create
When you rename a `.lua` file in your editor, Rojo sees it as a deletion of the old script and creation of a new one. Any runtime state stored in the old module is lost. This is usually fine (state is in the DataModel or server tables, not in the module itself), but be aware of it.

---

## APPENDIX A: Pre-Implementation Checklist

Before writing ANY code, the agent MUST verify:

- [ ] **Architecture**: Does this logic belong on server or client?
- [ ] **Security**: If this involves client input, is server validation planned?
- [ ] **Performance**: Will this run per-frame? If so, is 16ms budget maintained?
- [ ] **Memory**: Are new instances cleaned up? Is object pooling appropriate?
- [ ] **Networking**: Are visuals handled client-side? Is remote data minimal?
- [ ] **Native Tools**: Does Roblox already provide a built-in solution for this?
- [ ] **Type Safety**: Is `--!strict` enabled? Are parameters typed?
- [ ] **Cleanup**: Are connections tracked and disconnectable?
- [ ] **Mobile**: Does this work with touch-only input?
- [ ] **Container**: Are scripts and assets in the correct service container?
- [ ] **Constants**: Am I reusing existing shared constants, not redefining them?
- [ ] **Dependencies**: Does this create a circular require? If so, use injection.
- [ ] **File size**: Will this push a file over 1000 lines? If so, plan a split.

## APPENDIX B: Bug Fix Checklist

Before fixing ANY bug, the agent MUST:

- [ ] **Reproduce understanding**: Confirm the symptoms and expected behavior
- [ ] **Root cause**: Identify the actual cause, not just the symptom
- [ ] **Scope check**: Is this a server bug, client bug, or replication bug?
- [ ] **Side effects**: Will this fix break anything else? Check connections to the changed code
- [ ] **Validation**: Does the fix maintain server authority and security?
- [ ] **Performance**: Does the fix introduce per-frame work or memory allocation?
- [ ] **Test path**: How can the human test this fix in Studio?

## APPENDIX C: New File Checklist

Before creating ANY new Lua file, the agent MUST verify:

- [ ] **File extension**: Is it `.lua` (module), `.server.lua` (server script), or `.client.lua` (client script)?
- [ ] **Filesystem location**: Does the path match the correct Roblox container per the project.json?
- [ ] **WaitForChild**: If this is a client file requiring replicated content, are all requires using `WaitForChild` with timeouts?
- [ ] **Require style**: Server siblings use `script.Parent.Name`, cross-container uses `game:GetService()`.
- [ ] **No circular deps**: Does this file require anything that already requires (directly or indirectly) a module this file exports to?
- [ ] **Constants**: Are TILE_SIZE, ELEVATION_STEP, and other shared values imported from GameConstants, not redefined?

---

*Document version: 1.1*
*Last updated: 2026-09-15*
*Sources: Roblox Creator Hub Documentation, Roblox Lua Style Guide, DevForum community tutorials, CTRBLXAI development experience*
