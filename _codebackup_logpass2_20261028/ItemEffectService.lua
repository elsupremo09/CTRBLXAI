--!strict
-- ItemEffectService.lua
-- CTRBLXAI | Consumable item effect resolution (server-only).
--
-- WHY THIS MODULE EXISTS (2026-10-26):
-- Consumable effects were resolved by one text-parsing function inside
-- CommandService (resolveItemEffect) that recognised only 6 English phrasings.
-- 116 of 140 items used other phrasings or effect types and silently no-op'd.
-- This module is the single, data-driven dispatcher for ALL item effects. Each
-- effect family is routed to the system that ALREADY owns that behaviour
-- (CombatResolver for damage, StatusService for statuses, ...) instead of
-- re-implementing it here -- one place per job, not a tangled parallel system.
--
-- Dependencies are INJECTED by CommandService (cycle-free: this module requires
-- nothing that requires CommandService).
--
-- BUILD STATUS (families):
--   DONE : HP/MP restore, status cure, revive, status-apply (turns + CT),
--          single-target Power-formula direct damage.
--   TODO : AOE/multi-tile damage, delayed-CT bursts, chaining, deployables,
--          environment/terrain/weather, push/pull, utility reveal/teleport,
--          stat-buff Support items (need buff statuses authored in the DB).
--   Anything not yet handled returns effectType = "Unimplemented" and is LOGGED,
--   never silently treated as success.

local ItemEffectService = {}

--------------------------------------------------
-- INJECTED DEPENDENCIES
--------------------------------------------------
local UnitSchema: any = nil
local StatusService: any = nil
local CombatResolver: any = nil
local GameConstants: any = nil
local TraitEffectService: any = nil
local ArmorPassiveService: any = nil
local TargetingService: any = nil
local ObjectData: any = nil
local ConsumableData: any = nil

function ItemEffectService.Init(deps: any)
	UnitSchema          = deps.UnitSchema
	StatusService       = deps.StatusService
	CombatResolver      = deps.CombatResolver
	GameConstants       = deps.GameConstants
	TraitEffectService  = deps.TraitEffectService
	ArmorPassiveService = deps.ArmorPassiveService
	TargetingService    = deps.TargetingService
	ObjectData          = deps.ObjectData
	ConsumableData      = deps.ConsumableData  -- item names for Charge Relay (2026-10-26)
end

-- PulseScheduler injection (2026-10-26): set by CommandService.SetPulseScheduler.
-- Lets tile-anchored pulse items (Healing Beacon, Poison Cloud, delayed-burst
-- damage) register a fixed-CT schedule. nil-safe: absent -> pulse items defer.
local _pulseScheduler: any = nil
function ItemEffectService.SetPulseScheduler(ps: any)
	_pulseScheduler = ps
end

-- DEPLOYABLE CLASSIFIER (2026-10-26). Pure/stateless: decides whether a Deployable
-- consumable can be made functional by PLACING its archetype into the existing object
-- pipeline, WITHOUT any new behaviour subsystem. CommandService performs the actual
-- placement (it owns battle state); this only classifies, so the "what does this item
-- do" decision stays here with the rest of item resolution.
--
-- Functional-by-placement = the placed archetype already produces its effect through
-- systems that exist today:
--   * solid blocker (passable == false)  -> cover / movement + LoS block (Barrier Pylon,
--     Hardlight Wall). Being on the field IS the effect.
--   * entry-triggered trap (activation == "Triggered" + a real triggerEvent string) ->
--     the existing trap-trigger pipeline fires it (Land Mine, Snare Trap).
-- NOT functional-by-placement (returns functional=false so the caller DEFERS, never fakes):
--   * placement-only foundations with no behaviour of their own
--     (activation == nil AND triggerEvent == nil). No current item lands here: the Stasis
--     Trap Emitter is now a Triggered RT-delay trap (wired 2026-10-27).
--   * interact-to-fire structures needing an unbuilt per-turn usage tracker (Ballista).
-- Summon-kind and defer-kind deploys are NOT handled here (return nil) -- they need the
-- summon-stat-injection / per-CT pulse scheduler passes.
function ItemEffectService.GetDeployPlan(def: any): any
	if not def or def.deployKind ~= "object" or not def.deployRef then
		return nil
	end
	local arch = ObjectData and ObjectData.Objects and ObjectData.Objects[def.deployRef]
	if not arch then
		return { ref = def.deployRef, functional = false, reason = "unknown archetype" }
	end
	-- PURE static blocker only: impassable AND no activation/trigger of its own. This
	-- excludes structures whose real effect is an UNBUILT behaviour (e.g. Ballista is
	-- impassable but activation == "Interact ..." -> its siege-fire needs the unbuilt
	-- per-turn usage tracker; placing it as an inert wall would be fake progress).
	local isBlocker = (arch.passable == false)
		and (arch.activation == nil) and (arch.triggerEvent == nil)
	local isTrap = (arch.activation == "Triggered" and type(arch.triggerEvent) == "string")
	-- Interactable deployable (2026-10-26, Portable Ballista): placed object that the
	-- owner's side Interacts with; its effect handler lives in ObjectEffectService.
	local isInteractable = arch.isDeployable == true and type(arch.activation) == "string"
		and string.sub(arch.activation, 1, 8) == "Interact"
	-- Self-acting deployable (2026-10-26, Rescue Beacon): placed object whose effect runs on
	-- its own ("Passive"), driven by CommandService.ProcessRescueBeacons.
	local isPassive = arch.isDeployable == true and arch.activation == "Passive"
	return {
		ref = def.deployRef,
		functional = isBlocker or isTrap or isInteractable or isPassive,
		isInteractable = isInteractable,
		isBlocker = isBlocker,
		isTrap = isTrap,
		reason = (not (isBlocker or isTrap)) and "placement-only foundation (behaviour is a later wave)" or nil,
	}
end

-- DISPLACEMENT CLASSIFIER (2026-10-26). Pure/stateless: parses a push/pull item's
-- force formula and shape so CommandService (which owns battle state + the shared
-- applyKnockback helper + DisplacementService) can perform the move. Mirrors the
-- GetDeployPlan split: classify here, mutate there.
--
-- Recognised formula shapes (floor-divisor, ASCII — no multiply sign):
--   "... Force = <base> + floor(IL/<d1>)"                      (+ optional "+ floor(<STAT>/<d2>)")
--   "Push Force = <base> + floor(IL/<d1>) + floor(<STAT>/<d2>)"
-- mode: "push" (away from user) for Push/Repulsion/Ram; "pull" (toward user) when
-- the formula says Pull. area=true for Impact/Circle/etc. patterns (push every unit
-- on the affected tiles). collisionMult carries a "collision multiplier xN" (Kinetic
-- Ram 1.25). Returns nil when the item is not a parseable push/pull.
function ItemEffectService.GetPushPlan(user: any, def: any): any
	if not def then return nil end
	local f = (def.effectFormula or ""):gsub("\195\151", "x")  -- normalise multiply sign
	-- Must mention a Force and at least one floor(.../...) term.
	local base = string.match(f, "[Ff]orce%s*=%s*(%d+)")
	if not base then return nil end
	local ilDiv = tonumber(string.match(f, "floor%(IL/(%d+)%)"))
	local statName, statDiv = string.match(f, "floor%((%u%u%u)/(%d+)%)")
	local IL = user.level or 1
	local force = tonumber(base)
	if ilDiv and ilDiv > 0 then force = force + math.floor(IL / ilDiv) end
	if statName and statDiv and tonumber(statDiv) > 0 then
		local sv = (user.effectiveStats and user.effectiveStats[statName]) or 10
		force = force + math.floor(sv / tonumber(statDiv))
	end
	local isPull = string.find(f, "Pull") ~= nil or string.find(f, "pull") ~= nil
	local pat = tostring(def.pattern or "Single")
	local isArea = pat:match("^Impact") ~= nil or pat:match("^Circle") ~= nil
		or pat:match("^Cross") ~= nil or pat:match("^Ring") ~= nil
	-- Capture the number WITHOUT a trailing period: "[%d%.]+" would swallow the
	-- sentence's full stop ("x1.25.") and tonumber that to nil. Match digits, an
	-- optional single dot, and more digits so "1.25" is captured cleanly.
	local collisionMult = tonumber(string.match(f, "collision multiplier%s*x(%d+%.?%d*)"))
	return {
		mode = isPull and "pull" or "push",
		force = math.max(0, math.round(force)),
		area = isArea,
		collisionMult = collisionMult,
	}
end

-- WEATHER CLASSIFIER (2026-10-26). Pure/stateless: maps a Battlefield/Global weather
-- beacon's formula to a WeatherService condition id. CommandService (which owns state
-- + the injected WeatherService) performs the actual set. Only the three authored
-- weather SETTERS are recognised; the condition id must be one WeatherService knows
-- (Clear / Rain / Thunderstorm here). Returns {conditionId, durationCt?} or nil.
--
-- durationCt is passed to WeatherService.ForceCondition as a hold (user ruling 2026-10-27):
-- no per-round re-roll until it ends, then re-rolls resume immediately.
function ItemEffectService.GetWeatherPlan(def: any): any
	if not def then return nil end
	local rules = tostring(def.targetRules or "")
	if rules ~= "Battlefield" and rules ~= "Global" then return nil end
	local f = def.effectFormula or ""
	local conditionId = nil
	if string.find(f, "Thunderstorm") then
		conditionId = "Thunderstorm"
	elseif string.find(f, "Rain") and not string.find(f, "end ordinary Rain") then
		conditionId = "Rain"
	elseif string.find(f, "Clear") or string.find(f, "Sunny") then
		conditionId = "Clear"
	end
	if not conditionId then return nil end
	local durCt = tonumber(string.match(f, "for (%d+) CT"))
	return { conditionId = conditionId, durationCt = durCt }
end

-- TERRAIN CLASSIFIER (2026-10-26). Pure/stateless: returns an item's authored
-- terrain-transform rules so CommandService can apply them per affected tile via
-- TileEffectService.TransformTileTerrain. Only mode "all" is handled here; "choice"
-- items need a player target-terrain picker (no such input exists) and return nil ->
-- defer. Each rule is {from = {terrainId,...}, to = terrainId}. The engine, per tile
-- in the AOE pattern, swaps the terrain when its current id is in a rule's `from`.
-- Terrain-item side clauses (2026-10-27), read from the live formula:
--   "other tiles gain +N Move Cost for M CT" (ENV-003) -> costAdd / costCt
--   "remove <Tile Effect>"                    (ENV-013) -> removeEffect (a TILE_EFFECTS id)
function ItemEffectService.GetTerrainExtras(def: any): any
	if not def then return nil end
	local f = tostring(def.effectFormula or "")
	local out = {}
	local add, ct = string.match(f, "other tiles gain %+(%d+) Move Cost for (%d+) CT")
	if add then
		out.costAdd = tonumber(add)
		out.costCt = tonumber(ct)
	end
	local rem = string.match(f, "remove ([%a ]-)%.?$")
	if rem and GameConstants and GameConstants.TILE_EFFECTS and GameConstants.TILE_EFFECTS[rem] then
		out.removeEffect = rem
	end
	if next(out) == nil then return nil end
	return out
end

function ItemEffectService.GetTerrainPlan(def: any, choice: any): any
	if not def or type(def.terrainTransforms) ~= "table" or #def.terrainTransforms == 0 then
		return nil
	end
	if def.terrainTransformMode == "choice" then
		-- Pick-list (user ruling 1, 2026-10-26): the player chose a target terrain; use
		-- only the rule that produces it. No choice -> defer (never guess).
		for _, rule in ipairs(def.terrainTransforms) do
			if rule.to == choice then
				return { rules = { rule } }
			end
		end
		return nil
	end
	return { rules = def.terrainTransforms }
end

--------------------------------------------------
-- PICK-LIST ITEMS (user ruling 1, 2026-10-26)
--------------------------------------------------
-- Damage elements a ward can cover (CTRBLXAI.db elements_statuses "Elements").
local WARD_ELEMENTS = { "Physical", "Fire", "Water", "Ice", "Poison", "Dark", "Holy", "Electric" }

-- Pick-list items are identified from authored DATA, never from description wording
-- (DEFECT-1, UAT 2026-10-26: SUP-018's text was reworded and text matching broke it).
-- An explicit def.choiceKind ("element" / "cleanse" / "extendBuff") wins when present;
-- otherwise the item's Secondary_Tags decide:
--   "Element Defense" -> element ward (SUP-016)
--   "Buff Duration"   -> buff extend (SUP-018)
--   "Cleanse" + Ground target -> area cleanse with a picked debuff (REC-016). The
--     single-target "Cleanse" potions (REC-013/014/015) name their statuses and keep
--     the normal cure path.
local function hasTag(def: any, tag: string): boolean
	for _, t in ipairs((def and def.tags) or {}) do
		if t == tag then return true end
	end
	return false
end
local function isElementWardItem(def: any): boolean
	if not def then return false end
	if def.choiceKind ~= nil then return def.choiceKind == "element" end
	return hasTag(def, "Element Defense")
end
-- Elemental Ward Totem (DEP-013): a placed device whose aura cuts one PICKED element's
-- direct damage to allies. Identified by its authored aura multiplier (data), not text.
local function isDeviceWardItem(def: any): boolean
	return def ~= nil and def.deviceAuraWardMult ~= nil
end
local function isCleanseChoiceItem(def: any): boolean
	if not def then return false end
	if def.choiceKind ~= nil then return def.choiceKind == "cleanse" end
	return hasTag(def, "Cleanse") and tostring(def.targetRules or "") == "Ground"
end
local function isBuffExtendItem(def: any): boolean
	if not def then return false end
	if def.choiceKind ~= nil then return def.choiceKind == "extendBuff" end
	return hasTag(def, "Buff Duration")
end
-- Object Recall Device (UTI-018, tag "Object Reposition"): "Relocate owned deployable to
-- legal empty tile; remaining duration unchanged." The user PICKS which of their placed
-- things to move and taps the tile. User ruling 2026-10-27: ALL of the user's own placed
-- things -- item devices AND placed objects (barricades, Hardlight Wall segments, item / skill
-- traps, Portable Ballista, Supply Station, Rescue Beacon...). It is a teleport, so Stability
-- is ignored. Labels carry the tile ("Barricade (5,7)") so two of a kind can be told apart.
local function isRecallItem(def: any): boolean
	if not def then return false end
	if def.choiceKind ~= nil then return def.choiceKind == "recall" end
	return hasTag(def, "Object Reposition")
end
function ItemEffectService.IsRecallItem(def: any): boolean
	return isRecallItem(def)
end
-- Everything this user may recall: { label, kind = "device"|"object", unit | inst }.
local function recallTargets(user: any, state: any): { any }
	local out = {}
	if not (user and state) then return out end
	for _, u in ipairs(state.units or {}) do
		if u.isAlive and u.isItemDevice and u.summonOwnerId == user.id and u.tileX then
			table.insert(out, { label = `{u.name} ({u.tileX},{u.tileY})`, kind = "device", unit = u })
		end
	end
	for _, o in ipairs(state.objects or {}) do
		local od = o.type and ObjectData and ObjectData.Objects and ObjectData.Objects[o.type]
		local isTrap = false
		for _, t in ipairs((od and od.tags) or {}) do
			if t == "Trap" then isTrap = true break end
		end
		if o.casterId == user.id and o.x and o.y and od and (od.isDeployable == true or isTrap) then
			table.insert(out, { label = `{o.type} ({o.x},{o.y})`, kind = "object", inst = o })
		end
	end
	return out
end
function ItemEffectService.GetRecallTargets(user: any, state: any): { any }
	return recallTargets(user, state)
end
-- Resolve a recall pick. Also accepts a bare device name (older clients / saved selections).
function ItemEffectService.FindRecallTarget(user: any, state: any, choice: any): any
	if type(choice) ~= "string" then return nil end
	for _, e in ipairs(recallTargets(user, state)) do
		if e.label == choice then return e end
	end
	for _, e in ipairs(recallTargets(user, state)) do
		if e.kind == "device" and e.unit.name == choice then return e end
	end
	return nil
end
function ItemEffectService.FindOwnedDevice(user: any, allUnits: any, name: any): any
	if not user or type(name) ~= "string" then return nil end
	for _, u in ipairs(allUnits or {}) do
		if u.isAlive and u.isItemDevice and u.summonOwnerId == user.id and u.name == name then
			return u
		end
	end
	return nil
end

-- Charge Relay (UTI-009, tag "Charge Transfer"): "Transfer 1 charge from user's Item to
-- the same Item equipped by target." The user PICKS which of their items gives the charge.
local function isChargeRelayItem(def: any): boolean
	if not def then return false end
	if def.choiceKind ~= nil then return def.choiceKind == "chargeRelay" end
	return hasTag(def, "Charge Transfer")
end
-- UTI-020 Loadout Replicator (user ruling 2026-10-27): becomes a copy of an ally's item.
local function isReplicatorItem(def: any): boolean
	if not def then return false end
	if def.choiceKind ~= nil then return def.choiceKind == "replicate" end
	return hasTag(def, "Item Flexibility")
end
local function slotItemName(slot: any): any
	if not (slot and slot.consumableId and ConsumableData and ConsumableData.GetById) then return nil end
	local d = ConsumableData.GetById(slot.consumableId)
	return d and d.name or nil
end
-- Source slot (user's, by item name, >= 1 charge, never the relay itself) and the
-- target's slot holding the same item with room for one more charge. nil when illegal.
function ItemEffectService.FindRelaySlots(def: any, user: any, target: any, itemName: any): (any, any)
	if type(itemName) ~= "string" or itemName == def.name then return nil, nil end
	local from = nil
	for _, s in ipairs((user and user.consumableSlots) or {}) do
		if slotItemName(s) == itemName and (s.currentCharges or 0) >= 1 then from = s break end
	end
	if not from then return nil, nil end
	for _, s in ipairs((target and target.consumableSlots) or {}) do
		if s.consumableId == from.consumableId and (s.currentCharges or 0) < (s.maxCharges or 0) then
			return from, s
		end
	end
	return from, nil
end
-- Replicator sources: "Ally: Item" for every living ally's item with >= 1 charge (never the
-- user's own items, never another Replicator). Entries { label, ally, slot }.
local function replicateSources(user: any, allUnits: any): { any }
	local out, seen = {}, {}
	for _, u in ipairs(allUnits or {}) do
		if user and u ~= user and u.isAlive and not u.isItemDevice and u.side == user.side then
			for _, s in pairs(u.consumableSlots or {}) do
				local d = (type(s) == "table" and s.consumableId and ConsumableData and ConsumableData.GetById)
					and ConsumableData.GetById(s.consumableId) or nil
				if d and not isReplicatorItem(d) and (s.currentCharges or 0) >= 1 then
					local label = `{u.name or u.id}: {d.name}`
					if not seen[label] then
						seen[label] = true
						table.insert(out, { label = label, ally = u, slot = s })
					end
				end
			end
		end
	end
	return out
end
function ItemEffectService.FindReplicateSource(user: any, allUnits: any, choice: any): any
	if type(choice) ~= "string" then return nil end
	for _, e in ipairs(replicateSources(user, allUnits)) do
		if e.label == choice then return e end
	end
	return nil
end
function ItemEffectService.IsReplicatorItem(def: any): boolean
	return isReplicatorItem(def)
end
ItemEffectService.IsElementWardItem = isElementWardItem
ItemEffectService.IsCleanseChoiceItem = isCleanseChoiceItem
ItemEffectService.IsBuffExtendItem = isBuffExtendItem

-- A debuff the player may pick for a cleanse: a real Debuff that is not flagged
-- undispellable.
local function isPickableDebuff(statusId: any): boolean
	local d = GameConstants and GameConstants.STATUSES and GameConstants.STATUSES[statusId]
	return d ~= nil and d.kind == "Debuff" and d.dispellable ~= false
end

-- Fixed choices for the prompt (nil when the item has none). Purification lists the
-- debuffs currently on the user's living allies (including the user).
function ItemEffectService.GetItemChoices(def: any, unit: any, state: any): any
	if not def then return nil end
	if def.terrainTransformMode == "choice" and type(def.terrainTransforms) == "table" then
		local out = {}
		for _, rule in ipairs(def.terrainTransforms) do table.insert(out, rule.to) end
		return out
	end
	if (isElementWardItem(def) and tostring(def.targetRules or "") ~= "Empty Tile") or isDeviceWardItem(def) then
		return table.clone(WARD_ELEMENTS)
	end
	if isCleanseChoiceItem(def) then
		local out, seen = {}, {}
		for _, u in ipairs((state and state.units) or {}) do
			if u.isAlive and unit and u.side == unit.side then
				for _, inst in ipairs(u.statusInstances or {}) do
					if not seen[inst.id] and isPickableDebuff(inst.id) then
						seen[inst.id] = true
						table.insert(out, inst.id)
					end
				end
			end
		end
		table.sort(out)
		return out
	end
	if isRecallItem(def) then
		local out = {}
		for _, e in ipairs(recallTargets(unit, state)) do table.insert(out, e.label) end
		table.sort(out)
		return out
	end
	if isChargeRelayItem(def) then
		-- The user's OTHER items that still have a charge to give.
		local out, seen = {}, {}
		for _, s in ipairs((unit and unit.consumableSlots) or {}) do
			local n = slotItemName(s)
			if n and n ~= def.name and not seen[n] and (s.currentCharges or 0) >= 1 then
				seen[n] = true
				table.insert(out, n)
			end
		end
		table.sort(out)
		return out
	end
	if isReplicatorItem(def) then
		local out = {}
		for _, e in ipairs(replicateSources(unit, state and state.units)) do table.insert(out, e.label) end
		table.sort(out)
		return out
	end
	return nil
end

-- Target-dependent choices are built by the client after the target is picked.
function ItemEffectService.GetItemChoiceKind(def: any): any
	if isBuffExtendItem(def) then return "targetBuff" end
	return nil
end

-- Server-side check of the picked value BEFORE any cost is paid. Returns an error
-- string, or nil when the choice is valid / the item needs none.
function ItemEffectService.ValidateItemChoice(def: any, choice: any, target: any, actor: any, allUnits: any): any
	if not def then return nil end
	if def.terrainTransformMode == "choice" then
		if ItemEffectService.GetTerrainPlan(def, choice) == nil then return "Choose a terrain." end
		return nil
	end
	if (isElementWardItem(def) and tostring(def.targetRules or "") ~= "Empty Tile") or isDeviceWardItem(def) then
		for _, e in ipairs(WARD_ELEMENTS) do
			if e == choice then return nil end
		end
		return "Choose an element."
	end
	if isCleanseChoiceItem(def) then
		if not isPickableDebuff(choice) then return "Choose a debuff to remove." end
		-- W1 fix: the picked debuff must actually be on one of the user's living allies,
		-- so a charge is never spent removing nothing.
		-- Audit P-2 fix (2026-10-27): the debuff must be on an ally INSIDE the item's area around
		-- the tapped tile (same tiles the cleanse uses), so a charge is never spent removing nothing.
		local inArea = nil
		if type(target) == "table" and target.tileX and TargetingService and actor then
			local pat = (tostring(def.pattern or "Single"):gsub("%s+", ""))
			local tiles = TargetingService.GetAOETargetTiles(pat, actor, target.tileX, target.tileY, 9999, 9999)
			if not tiles or #tiles == 0 then tiles = { { tileX = target.tileX, tileY = target.tileY } } end
			inArea = {}
			for _, t in ipairs(tiles) do inArea[t.tileX .. "," .. t.tileY] = true end
		end
		local present = false
		for _, u in ipairs(allUnits or {}) do
			if u.isAlive and actor and u.side == actor.side and StatusService and StatusService.HasStatus(u, choice)
				and (inArea == nil or (u.tileX and inArea[u.tileX .. "," .. u.tileY])) then
				present = true
				break
			end
		end
		if not present then return "No ally in the area has that debuff." end
		return nil
	end
	if isBuffExtendItem(def) then
		local inst = (type(target) == "table" and StatusService and StatusService.HasStatus(target, choice)) or nil
		local d = GameConstants and GameConstants.STATUSES and GameConstants.STATUSES[choice]
		if not inst or not d or d.kind ~= "Buff" or d.dispellable ~= true then
			return "Choose one of the target's dispellable buffs."
		end
		if inst.blessExtended then
			return "That buff has already been extended."
		end
		return nil
	end
	if isRecallItem(def) then
		-- Objects live in state.objects (not passed here): CommandService checks the pick
		-- against FindRecallTarget(state) right after this, still before any cost.
		if type(choice) ~= "string" or choice == "" then
			return "Choose one of your placed things."
		end
		return nil
	end
	if isChargeRelayItem(def) then
		local from, to = ItemEffectService.FindRelaySlots(def, actor, target, choice)
		if not from then return "Choose one of your items that has a charge." end
		if not to then return "The target does not carry that item, or it is already full." end
		return nil
	end
	if isReplicatorItem(def) then
		if not ItemEffectService.FindReplicateSource(actor, allUnits, choice) then
			return "Choose an ally's item that still has charges."
		end
		return nil
	end
	return nil
end

-- TILE-EFFECT CLASSIFIER (2026-10-26): items that place an existing ground effect
-- (Fog Machine / Smoke Generator -> Steam, Oil Sprayer -> Oily) or hit tiles with an
-- element through the normal element-reaction engine (Hydraulic Sprayer -> Water).
-- Data-driven: def.tileEffect (effect id) or def.tileElement, optional def.tileEffectCt.
-- An unknown effect id defers (never guessed).
function ItemEffectService.GetTileEffectPlan(def: any): any
	if not def or (def.tileEffect == nil and def.tileElement == nil) then
		return nil
	end
	if def.tileEffect and not (GameConstants.TILE_EFFECTS and GameConstants.TILE_EFFECTS[def.tileEffect]) then
		return nil
	end
	return { effect = def.tileEffect, element = def.tileElement, ct = def.tileEffectCt }
end

-- AIM RANGE (2026-10-26, user ruling 2: aim by tapping a tile). Extra selection
-- range for items whose authored range is 0 but which still need a tile picked:
--   * Self-origin Line N / Cone N (Flame Projector, Corrosion Sprayer, Gale Engine):
--     any tile within N picks the direction.
--   * Self to Empty Tile teleport: pattern "Range B + floor(AGI/D)".
-- Returns a number or nil. Shared by the prompt builder and the server validator.
function ItemEffectService.GetItemAimRange(actor: any, def: any): any
	if not def then return nil end
	local tr = tostring(def.targetRules or "")
	local pat = tostring(def.pattern or "")
	if tr == "Self-origin" then
		local n = tonumber(pat:match("^Line%s*(%d+)") or pat:match("^Cone%s*(%d+)"))
		return n
	end
	if tr == "Self to Empty Tile" then
		local b, d = pat:match("Range%s*(%d+)%s*%+%s*floor%(AGI/(%d+)%)")
		if b then
			local agi = (actor and actor.effectiveStats and actor.effectiveStats.AGI) or 10
			return tonumber(b) + math.floor(agi / tonumber(d))
		end
		return tonumber(pat:match("Range%s*(%d+)"))
	end
	return nil
end

-- TELEPORT CLASSIFIER (2026-10-26, UTI-004 Phase Translocator): move the user to a
-- picked legal empty tile.
function ItemEffectService.GetTeleportPlan(def: any): any
	if def and tostring(def.targetRules or "") == "Self to Empty Tile" then
		return {}
	end
	return nil
end

-- SWAP CLASSIFIER (2026-10-26, UTI-005 Exchange Device): "Swap positions" on a unit.
function ItemEffectService.GetSwapPlan(def: any): any
	if not def then return nil end
	local f = def.effectFormula or ""
	if string.find(f, "Swap positions", 1, true) and not string.find(tostring(def.targetRules or ""), "Ground", 1, true) then
		return {}
	end
	return nil
end

-- REVEAL CLASSIFIER (user ruling 2026-10-27): a Ground-targeted area item whose formula
-- starts "Reveal hidden" (UTI-003 Scanner Lens). Enemies of the user in the area lose Hide
-- and hidden enemy traps there are shown; "for N CT" keeps the area revealed that long.
function ItemEffectService.GetRevealPlan(def: any): any
	if not def then return nil end
	if tostring(def.targetRules or "") ~= "Ground" then return nil end
	local f = def.effectFormula or ""
	if string.find(f, "Reveal hidden", 1, true) then
		return { durationCt = tonumber(string.match(f, "for (%d+) CT")) }
	end
	return nil
end

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------
-- Real combat elements (must match CombatResolver.extractElement + DB
-- elements_statuses). A parsed "element" outside this set means the formula
-- was a different shape (e.g. "First target Power=" on a chaining item) and the
-- item is deferred rather than mis-resolved as Physical.
local ELEMENT_SET: { [string]: boolean } = {
	Fire = true, Ice = true, Electric = true, Poison = true,
	Holy = true, Dark = true, Physical = true, Water = true,
}

--------------------------------------------------
-- HELPERS
--------------------------------------------------
-- A unit-targeted item acts on a Self/Ally/Enemy unit. A Ground/Empty Tile item
-- is a deployable/terrain effect and is handled by the deploy/environment pass,
-- NOT by the unit-status/damage handlers below.
local function isUnitTargeted(def: any): boolean
	local t = tostring(def.targetRules or "")
	if string.find(t, "Ground") or string.find(t, "Tile") then
		return false
	end
	return string.find(t, "Enemy") ~= nil
		or string.find(t, "Ally") ~= nil
		or string.find(t, "Self") ~= nil
		or string.find(t, "Unit") ~= nil
end

-- Compute an item's self-contained flat Power from its parsed formula spec.
-- (base + ilCoeff*IL + statCoeff*STAT), then the user's item trait + accessory
-- multipliers, consistent with the single-target path.
local function computeItemPower(user: any, spec: any): number
	local IL = user.level or 1
	local statVal = (user.effectiveStats and user.effectiveStats[spec.stat]) or 10
	local power = spec.base + spec.ilCoeff * IL + spec.statCoeff * statVal
	power = power * TraitEffectService.GetItemEffectMultiplier(user)
	power = power * (1 + ArmorPassiveService.GetItemDamageBonus(user))
	return math.max(1, math.round(power))
end

-- Generic non-element rider. Element items (Fire/Ice/Poison/Water) get their
-- rider automatically from ApplyOutcome's element->status triggers, so a rider is
-- only derived for Physical items that name a status (avoids double-apply).
local function deriveRider(element: string, formula: string): any
	if element ~= "Physical" then return nil end
	if string.find(formula, "Bleed") then return "Bleed" end
	if string.find(formula, "Poison") then return "Poison" end
	return nil
end

-- Resolve ONE damaging hit on ONE unit through the full skill pipeline (Defense,
-- element resistance, weather, terrain, element->status triggers). The rider is
-- applied only when applyRider is true (the primary/first unit), honouring
-- "first target gains X" without over-applying to a whole area. Accumulates into
-- result so multi-hit / AOE report a combined amount.
local function resolveItemHitOnUnit(user: any, unit: any, element: string, power: number, rider: any, applyRider: boolean, def: any, result: any, isAOE: any): number
	local pseudoSkill = {
		id = "ITEM-" .. tostring(def.name or "?"),
		tags = { element },
		flatPower = power,
		appliesStatus = (applyRider and rider) or nil,
		-- DAM-017 Venom Repeater "2+ HP hits apply Poison" (2026-10-27): element status
		-- riders only on hits that deal at least this much.
		minRiderDamage = tonumber(string.match(def.effectFormula or "", "(%d+)%+ HP hits apply")),
	}
	-- Units this item use hit (read by the damage riders after the hits resolve).
	result._hitUnits = result._hitUnits or {}
	table.insert(result._hitUnits, unit)
	local outcome = CombatResolver.ResolveSkill(user, unit, pseudoSkill)
	if isAOE then outcome.isAOE = true end  -- same flag area skills set (race / augment AOE rules)
	local actual, statusApplied = CombatResolver.ApplyOutcome(outcome, unit, user)
	result.amount = (result.amount or 0) + (actual or 0)
	result.element = element
	if statusApplied then result.statusId = statusApplied end
	return actual or 0
end

-- Parse a self-contained item Power formula:
--   "<Element> Power = <base> + <ilCoeff>xIL + <statCoeff>x<STAT>"
-- Accepts the unicode multiply sign and ASCII x. Returns a spec or nil.
-- TIMED HITS (user ruling 2026-10-26): delayed / repeating item damage (Thermite, Tesla
-- Pylon, Meteor Marker, Sentry Turret shots) follows the normal damage rules -- Defense,
-- element rules, wards -- exactly like an instant item hit. `power` was fixed when the item
-- was used (the user's stats at that moment). PulseScheduler calls this through an injected
-- reference (SetHitResolver), so it needs no require. Returns the damage actually dealt.
-- asItem (user ruling 2026-10-27, timed hits): the ITEM owns the hit, not the user. The hit
-- is resolved from a stat-carrying "item source" that is not a living combatant (isAlive
-- false) and stands on the target's tile: Defense, element rules and wards still apply, but
-- none of the user's gear / traits / race / doctrine / statuses trigger, nobody can
-- retaliate against it (retaliation paths require a living attacker), and there is no
-- height, facing or terrain bonus. Kill credit stays with the user (id = owner.id).
-- Without asItem (Portable Ballista, Breaching Drill: used on the user's own turn) the user
-- is the attacker as before.
local function makeItemSource(owner: any, unit: any, itemName: any): any
	return {
		id = owner.id,
		name = itemName or "Item",
		side = owner.side,
		level = owner.level,
		isAlive = false,
		isItemSource = true,
		statusInstances = {},
		effectiveStats = table.clone(owner.effectiveStats or {}),
		derivedStats = {},
		gearDerived = {},
		tileX = unit.tileX,
		tileY = unit.tileY,
		maxHp = 1,
		currentHp = 1,
		weaponDamage = 0,
		consumableSlots = {},
		skillIds = {},
	}
end

function ItemEffectService.ResolveTimedHit(owner: any, unit: any, element: any, power: number, itemName: any, asItem: any): number
	if not (owner and unit and unit.isAlive) or (power or 0) <= 0 then return 0 end
	local result: any = { amount = 0 }
	local source = if asItem then makeItemSource(owner, unit, itemName) else owner
	resolveItemHitOnUnit(source, unit, element or "Physical", math.max(1, math.round(power)), nil, false,
		{ name = itemName or "Timed" }, result)
	return result.amount or 0
end

local function parsePowerFormula(formula: string): any
	-- Normalise the UTF-8 multiply sign "×" (bytes 0xC3 0x97) to ASCII "x" BEFORE matching.
	-- A Lua character class matches ONE byte, so the old [..x] class could never consume the
	-- two-byte multiply sign (it matched 0xC3, then "IL" had to match the stranded 0x97 -> no
	-- match), silently sending every "<Element> Power = base + c1*IL + c2*STAT" item to
	-- Unimplemented at runtime. gsub on the literal two-byte sequence is exact (no specials).
	formula = (formula:gsub("\195\151", "x"))
	local el, base, ilc, sc, stat = string.match(
		formula,
		"(%a+)%s*Power%s*=%s*([%d%.]+)%s*%+%s*([%d%.]+)x%s*IL%s*%+%s*([%d%.]+)x%s*(%u%u%u)"
	)
	if not base then
		return nil
	end
	return {
		element = el,
		base = tonumber(base),
		ilCoeff = tonumber(ilc),
		statCoeff = tonumber(sc),
		stat = stat,
	}
end

--------------------------------------------------
-- HANDLER A/A2: HP / MP RESTORE  (migrated verbatim from CommandService)
--------------------------------------------------
local function tryRestore(user: any, target: any, formula: string, result: any): boolean
	local hpPct = string.match(formula, "Restore (%d+)%%.-Max HP")
		or string.match(formula, "^Remove .- and restore (%d+)%% Max HP")  -- REC-015 Cooling Gel
	if hpPct then
		local pct = tonumber(hpPct)
		local heal = math.ceil((target.maxHp or 1) * pct / 100)
		-- REC-015 Cooling Gel (user ruling 2026-10-27): also heals the Burn damage the unit would
		-- still have taken (its real Burn tick x turns left), read before the rider removes Burn.
		if string.find(formula, "plus stored Burn damage removed", 1, true) and StatusService then
			local burn = StatusService.HasStatus(target, "Burn")
			if type(burn) == "table" then
				heal += StatusService.GetBurnTickDamage(target, burn) * math.max(1, burn.remainingTurns or 1)
			end
		end
		-- Item Specialist / Fumbler: scale healing-item output by the USER's trait.
		heal = math.max(0, math.round(heal * TraitEffectService.GetItemEffectMultiplier(user)))
		-- AC Accessory: healing-item output +50% (0 without the accessory).
		heal = math.max(0, math.round(heal * (1 + ArmorPassiveService.GetItemHealBonus(user))))
		UnitSchema.ApplyHealing(target, heal)
		result.effectType = "HpRestore"
		result.amount = heal
		return true
	end

	local mpPct = string.match(formula, "Restore (%d+)%%.-Max MP")
	if mpPct then
		local pct = tonumber(mpPct)
		local restore = math.max(1, math.ceil((target.maxMp or 1) * pct / 100))
		local before = target.currentMp or 0
		target.currentMp = math.min((target.maxMp or 1), before + restore)
		result.effectType = "MpRestore"
		result.amount = target.currentMp - before
		return true
	end
	return false
end

--------------------------------------------------
-- HANDLER C: STATUS CURE  (migrated verbatim)
--------------------------------------------------
local function tryCure(target: any, formula: string, result: any): boolean
	if not string.match(formula, "^Remove ") then
		return false
	end
	local statusPart = string.gsub(string.gsub(formula, "^Remove ", ""), "%.$", "")
	statusPart = string.gsub(string.gsub(statusPart, ", and ", ", "), " and ", ", ")
	local statuses = {}
	for s in string.gmatch(statusPart, "[^,]+") do
		local trimmed = string.match(s, "^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			table.insert(statuses, trimmed)
		end
	end
	for _, statusName in ipairs(statuses) do
		StatusService.RemoveStatus(target, statusName)
	end
	result.effectType = "StatusCure"
	result.statusId = table.concat(statuses, ", ")
	return true
end

--------------------------------------------------
-- HANDLER E2: REVIVE  (migrated verbatim)
--------------------------------------------------
local function tryRevive(target: any, formula: string, result: any, allUnits: any, ctx: any): boolean
	local revPct, revRt = string.match(formula, "Revive at (%d+)%% Max HP with (%d+) remaining RT")
	if not revPct then
		return false
	end
	-- Revive only ever acts on a KO'd unit (2026-10-26). The normal item path already
	-- rejects living targets (CommandService validateItemTarget "KO Ally"), but the Mirror
	-- Charm self-copy re-runs the item on the LIVING user and skipped that check -- it reset
	-- the user's HP to the revive amount, its RT, its kill credit and weakened its Venom.
	-- Handled-but-nothing-happens so it cannot fall through to other handlers.
	if target.isAlive then
		result.effectType = "NoEffect"
		result.amount = 0
		return true
	end
	-- Rises on the nearest free tile if a living unit now stands on the body (2026-10-28). The
	-- command is refused earlier when there is none; this is the safety net.
	if UnitSchema and UnitSchema.FindReviveTile then
		local rx, ry, moved = UnitSchema.FindReviveTile(target, allUnits,
			ctx and ctx.mapWidth or nil, ctx and ctx.mapHeight or nil)
		if not rx then
			result.effectType = "NoEffect"
			result.amount = 0
			return true
		end
		target.tileX, target.tileY = rx, ry
		result.reviveMoved = moved
	end
	local frac = tonumber(revPct) / 100
	local maxHp = target.maxHp or 1
	local reviveHp
	if TraitEffectService.HasReviveAtOneHp(target) then
		reviveHp = 1
	else
		local effFrac = frac * TraitEffectService.GetReviveHpMultiplier(target)
			+ TraitEffectService.GetReviveHpBonusFraction(target)
		reviveHp = math.max(1, math.ceil(maxHp * effFrac))
		reviveHp = math.min(reviveHp, maxHp)
	end
	target.isAlive = true
	if UnitSchema and UnitSchema.ClearChannelState then
		UnitSchema.ClearChannelState(target)  -- never return holding a pre-death channel
	end
	target._revivedThisBattle = true  -- kill-credit rule (2026-10-26): revived units never trigger kill augments
	target.currentHp = reviveHp
	StatusService.WeakenVenomOnHeal(target)  -- a revive weakens Venom like a heal (user ruling 2026-10-26)
	target.remainingRt = tonumber(revRt) or target.startingRt or 400
	if string.find(formula, "wound%-family") then
		for _, s in ipairs({ "Wounded", "Raptured", "Bleed" }) do
			if StatusService.HasStatus(target, s) then
				StatusService.RemoveStatus(target, s)
				break
			end
		end
	end
	result.effectType = "Revive"
	result.amount = reviveHp
	return true
end

--------------------------------------------------
-- HANDLER E: STATUS APPLY  (turns + CT; unit-targeted only)
--------------------------------------------------
-- Apply one status to one unit, honouring the item duration-bonus accessory and
-- preserving the exact single-target semantics: a CT value from the formula is an
-- explicit override; a turns value relies on the status's own authored duration
-- (the item "turns" number is informational only, as in the original handler).
local function applyItemStatus(user: any, unit: any, statusName: string, durCt: any, turns: any)
	local _durBonus = ArmorPassiveService.GetItemDurationBonus(user)
	if durCt then
		StatusService.ApplyStatus(unit, statusName, user.id, nil, durCt + _durBonus)
	else
		local _sdef = _durBonus > 0 and GameConstants.STATUSES and GameConstants.STATUSES[statusName] or nil
		if _sdef and _sdef.durationCt then
			StatusService.ApplyStatus(unit, statusName, user.id, nil, _sdef.durationCt + _durBonus)
		else
			StatusService.ApplyStatus(unit, statusName, user.id)
		end
	end
	-- Item-authored TURN count ("Apply Confuse for 2 turns", 2026-10-27): ApplyStatus has no
	-- turn override, so set it on the instance afterwards. Debuff Resistance already scaled
	-- the default turns; the same ratio is kept (minimum 1).
	if turns and unit.statusInstances then
		local sdef = GameConstants.STATUSES and GameConstants.STATUSES[statusName]
		for _, inst in ipairs(unit.statusInstances) do
			if inst.id == statusName and inst.remainingTurns and sdef and (sdef.duration or 0) > 0 then
				inst.remainingTurns = math.max(1, math.round(turns * inst.remainingTurns / sdef.duration))
				break
			end
		end
	end
end

-- Area-pattern detection shared by the status handler (same pattern vocabulary the
-- damage handler feeds to TargetingService.GetAOETargetTiles).
local function isAreaPattern(norm: string): boolean
	return norm:match("^Impact%d*$") ~= nil or norm:match("^Circle%d*$") ~= nil
		or norm:match("^Ring%d*$") ~= nil or norm:match("^Cross%d*$") ~= nil
		or norm:match("^Cone%d*$") ~= nil or norm:match("^Line%d*$") ~= nil
		or norm:match("^Aura%d*$") ~= nil or norm == "Spread"
end

-- STATUS APPLICATION: single-target (unchanged) + AREA (new). Area reuses the exact
-- enumerator the damage path uses. Recipient side is derived from targetRules: an
-- Ally/Self rule buffs allies, otherwise it debuffs enemies. CON-006-style
-- "Center X N CT; adjacent units X M CT" is parsed as a center/ring split.
local function tryStatusApply(user: any, target: any, def: any, formula: string, result: any, allUnits: any, ctx: any): boolean
	-- Parse the status + duration shapes we understand.
	local turnsStatus, turns = string.match(formula, "Apply (.+) for (%d+) turns")
	local ctStatus, ct = string.match(formula, "Apply (.+) for (%d+) CT")
	-- Center/adjacent split (e.g. "Center Pinned 1000 CT; adjacent units Pinned 500 CT").
	local centerStatus, centerCt, adjCt = string.match(formula, "Center (%a+) (%d+) CT; adjacent units %a+ (%d+) CT")

	-- Support buff/debuff items word the effect as "STR +15% for 1500 CT" with no
	-- "Apply <name>" text -- the status name is carried in data (def.appliesStatus,
	-- populated from CTRBLXAI.db). Fall back to it so those items resolve generically
	-- without hardcoding any item->status map in source.
	local sName: any = turnsStatus or ctStatus or centerStatus or def.appliesStatus
	if not sName then
		return false
	end
	local durCt: any = ct and tonumber(ct) or nil

	-- DEFER re-pulse / deployable status items (e.g. CON-002 Dazzle Beacon:
	-- "Apply Blind for 800 CT at creation and again after 600 CT"). The status name
	-- is valid, but the re-pulse / persistent-emitter mechanic is a deployable effect
	-- that this unit-status branch would silently drop. Belongs to the deployable pass.
	if string.find(formula, "again") or string.find(formula, "at creation")
		or string.match(formula, "After%s+%d+") then
		return false
	end

	-- Formula names something that is not a real status (e.g. "authored Fear movement
	-- restriction"), but the item's data names a real one -> use the data name.
	if not (GameConstants.STATUSES and GameConstants.STATUSES[sName]) and def.appliesStatus
		and GameConstants.STATUSES and GameConstants.STATUSES[def.appliesStatus] then
		sName = def.appliesStatus
	end

	-- VALIDATE against the authored status registry (the SAME table StatusService.ApplyStatus
	-- checks: GameConstants.STATUSES). A captured name that is not a real status would
	-- otherwise be reported as a resolved use while ApplyStatus no-ops it (warn "Unknown
	-- status"). This defers CON-017 ("authored Fear movement restriction" -> no "Fear"
	-- status) and ENV-001 ("Oil-coated state" -> a terrain effect, not a unit status), and
	-- will also correctly defer the new Support buffs until their statuses are ported from
	-- the DB into GameConstants.STATUSES. Known statuses (Blind/Silence/Mute/Break/Disarmed/
	-- Confuse/Pinned/...) pass unchanged.
	if not (GameConstants.STATUSES and GameConstants.STATUSES[sName]) then
		return false
	end

	local pattern = tostring(def.pattern or "Single")
	local norm = (pattern:gsub("%s+", ""))

	-- ===== SINGLE TARGET (unchanged semantics) =====
	if not isAreaPattern(norm) then
		if not isUnitTargeted(def) or type(target) ~= "table" then
			return false
		end
		applyItemStatus(user, target, sName, durCt, turns and tonumber(turns))
		result.effectType = "StatusApply"
		result.statusId = sName
		result.amount = (turns and tonumber(turns)) or durCt or 0
		return true
	end

	-- ===== AREA =====
	if not TargetingService then return false end
	local centerX = (type(target) == "table" and target.tileX) or user.tileX
	local centerY = (type(target) == "table" and target.tileY) or user.tileY
	local mapW = (ctx and ctx.mapWidth) or 8
	local mapH = (ctx and ctx.mapHeight) or 8

	-- Line/Cone need a direction (target tile distinct from the user); defer if absent.
	if (norm:match("^Line%d*$") or norm:match("^Cone%d*$")) and centerX == user.tileX and centerY == user.tileY then
		return false
	end

	local tiles = TargetingService.GetAOETargetTiles(norm, user, centerX, centerY, mapW, mapH)
	if not tiles or #tiles == 0 then
		return false
	end
	local key = {}
	for _, t in ipairs(tiles) do key[t.tileX .. "," .. t.tileY] = true end

	-- Recipient side: prefer the applied status's own kind (Buff -> allies, Debuff ->
	-- enemies), since an ally-buff AOE can be Ground-targeted ("Allies gain VIT +12%")
	-- and its targetRules would not say "Ally". Fall back to targetRules when kind is
	-- absent. (centerStatus split items are enemy debuffs, handled by the fallback.)
	local rules = tostring(def.targetRules or "")
	local sDef = GameConstants.STATUSES and GameConstants.STATUSES[sName]
	local wantAlly
	if sDef and sDef.kind == "Buff" then
		wantAlly = true
	elseif sDef and sDef.kind == "Debuff" then
		wantAlly = false
	else
		wantAlly = (string.find(rules, "Ally") ~= nil or string.find(rules, "Self") ~= nil)
			and string.find(rules, "Enemy") == nil
	end
	-- "all" recipient mode (2026-10-26): a neutral ZONE status affects EVERY unit in the
	-- area regardless of side (e.g. Gravity Anchor: "Units gain Stability +2 and Movement
	-- Range -1"). Driven by the authored item field def.statusRecipients == "all" so it is
	-- data-explicit, never guessed from wording. nil/"ally"/"enemy" keep the side logic above.
	local recipientsAll = (def.statusRecipients == "all")

	local count = 0
	for _, u in ipairs(allUnits or {}) do
		if u.isAlive and u.tileX and key[u.tileX .. "," .. u.tileY] then
			local sideOk = recipientsAll
				or (wantAlly and (u.side == user.side))
				or ((not wantAlly) and (u.side ~= user.side))
			if sideOk then
				if centerStatus then
					-- center tile gets centerCt, everything else (ring) gets adjCt
					local atCenter = (u.tileX == centerX and u.tileY == centerY)
					applyItemStatus(user, u, centerStatus, atCenter and tonumber(centerCt) or tonumber(adjCt))
				else
					applyItemStatus(user, u, sName, durCt, turns and tonumber(turns))
				end
				count += 1
			end
		end
	end

	result.effectType = "StatusApply"
	result.statusId = sName
	result.amount = count
	return true
end

--------------------------------------------------
-- HANDLER D: DIRECT DAMAGE  (single-target Power formula)
--
-- Reuses the FULL skill resolution pipeline (Defense, element resistance,
-- weather, terrain, element->status triggers) via CombatResolver.ResolveSkill +
-- ApplyOutcome. The item supplies a self-contained flat Power (CombatResolver
-- was taught to accept skillDef.flatPower), so nothing is re-implemented here.
--
-- BALANCE NOTE (flagged for Simulator/Designer, not a code bug): item damage
-- currently flows through ResolveSkill, so it inherits the caster's Skill
-- Potency race/doctrine/trait mods. The framework says item values are working
-- baselines needing simulation; whether items should ignore skill-potency is a
-- balance decision, deliberately NOT made here.
--------------------------------------------------
-- DIRECT DAMAGE: single-target, multi-hit ("N Hits"), chain ("Chain N"), and
-- area patterns (Impact/Circle/Ring/Cross/Spread/Line/Cone/Aura) via the shared
-- TargetingService enumerator. Each affected enemy is resolved through the full
-- skill pipeline (resolveItemHitOnUnit). Per-item SECONDARY clauses (lifesteal,
-- self HP cost, defense-debuff riders, Wet->Frozen conversion, mixed heal+damage)
-- and DELAYED/scheduled CT bursts, push-force, and object-primary damage are NOT
-- handled here -- they defer to their own passes (logged, never faked).
local function tryDamage(user: any, target: any, def: any, formula: string, result: any, allUnits: any, ctx: any): boolean
	local spec = parsePowerFormula(formula)
	if not spec then
		return false
	end
	-- Element resolution: the "<Element> Power =" prefix is authoritative when it names
	-- a real element. Chain / multi-hit items word the formula differently ("First target
	-- Power =", "Each hit Power ="), so the captured prefix ("target"/"hit") is not an
	-- element -- fall back to the item's Secondary_Tags, which carry it (e.g. {"Electric",
	-- "Chain"}, {"Poison","Multi-hit"}). If neither yields a real element, defer.
	if not ELEMENT_SET[spec.element] then
		local el = nil
		for _, t in ipairs(def.tags or {}) do
			if ELEMENT_SET[t] then el = t break end
		end
		if not el then
			return false
		end
		spec.element = el
	end

	-- Defer bespoke damage families (each handled by a later pass, never faked):
	--  * delayed / scheduled CT bursts   ("At 0, 400, ... CT", "After 300 CT")
	--  * push / collision force items     ("Push Force ...")
	--  * object-primary damage            ("Object Power ...")
	--  * mixed heal + damage split        ("non-Undead allies recover ...")
	if string.find(formula, "After%s+%d") or string.match(formula, "At%s+%d+[%d,%s]*CT") then
		return false
	end
	if string.find(formula, "Push Force") or string.find(formula, "Object Power") then
		return false
	end
	if string.find(formula, "non%-Undead allies recover") then
		-- HOLY WATER (DAM-009, 2026-10-26): "Undead take Holy Power = ...; non-Undead allies
		-- recover 10% Max HP." An Undead target (either side) takes the Holy hit through the
		-- normal skill pipeline (Defense, element rules incl. Holy vs Undead). A living
		-- non-Undead ALLY is healed by the authored % with the usual item heal multipliers.
		-- A non-Undead enemy is refused by target validation before any cost is paid.
		if type(target) ~= "table" or not target.isAlive or target.isGroundTarget then return false end
		if CombatResolver.IsUndead and CombatResolver.IsUndead(target) then
			resolveItemHitOnUnit(user, target, spec.element, computeItemPower(user, spec), nil, true, def, result)
			result.effectType = "Damage"
			return true
		end
		if target.side == user.side then
			local pct = tonumber(string.match(formula, "recover (%d+)%% Max HP")) or 0
			local heal = math.ceil((target.maxHp or 0) * pct / 100)
			heal = math.max(0, math.round(heal * TraitEffectService.GetItemEffectMultiplier(user)))
			heal = math.max(0, math.round(heal * (1 + ArmorPassiveService.GetItemHealBonus(user))))
			result.amount = UnitSchema.ApplyHealing(target, heal) or 0
			result.effectType = "HpRestore"
			return true
		end
		return false
	end

	local pattern = tostring(def.pattern or "Single")
	local normPattern = (pattern:gsub("%s+", ""))  -- "Impact 1" -> "Impact1"
	local power = computeItemPower(user, spec)
	local rider = deriveRider(spec.element, formula)

	-- ===== SINGLE TARGET =====
	if normPattern == "Single" or normPattern == "AuthoredSingle" or normPattern == "Direct" then
		local victim = target
		if type(target) == "table" and target.isGroundTarget and string.find(tostring(def.targetRules or ""), "Ground") then
			-- DAM-003 Frost Vial ("Enemy or Ground", 2026-10-27): the player taps a tile; the hit
			-- goes to the unit standing there. An empty tile still uses the item (no target).
			victim = nil
			for _, u in ipairs(allUnits or {}) do
				if u.isAlive and u ~= user and u.tileX == target.tileX and u.tileY == target.tileY then
					victim = u
					break
				end
			end
			if not victim then
				result.effectType = "Damage"
				result.amount = 0
				result.element = spec.element
				return true
			end
		elseif not isUnitTargeted(def) or type(target) ~= "table" or not target.isAlive then
			return false
		end
		resolveItemHitOnUnit(user, victim, spec.element, power, rider, true, def, result)
		result.effectType = "Damage"
		return true
	end

	-- ===== MULTI-HIT ("N Hits") -- repeat on the single unit target =====
	local hits = tonumber(pattern:match("^(%d+)%s*[Hh]its?$"))
	if hits then
		if type(target) ~= "table" or not target.isAlive then return false end
		for i = 1, hits do
			if not target.isAlive then break end
			resolveItemHitOnUnit(user, target, spec.element, power, rider, i == 1, def, result)
		end
		result.effectType = "Damage"
		return true
	end

	-- ===== CHAIN ("Chain N") =====
	local chainN = tonumber(pattern:match("^[Cc]hain%s*(%d+)$"))
	if chainN then
		if type(target) ~= "table" or not target.isAlive or not TargetingService then return false end
		local chain = TargetingService.GetChainTargets(target, allUnits or {}, user.side, chainN, 2)
		-- Per-hop damage falloff: "jumps at 70% and 50%" -> hop 1 = 100%, hop 2 = 70%,
		-- hop 3 = 50%. Parsed from the formula so it is data-driven, not hard-coded; with
		-- no "jump" clause every hop lands at full power.
		local falloff = { 1.0 }
		if string.find(formula, "jump") then
			for pct in string.gmatch(formula, "(%d+)%%") do
				table.insert(falloff, tonumber(pct) / 100)
			end
		end
		for i, u in ipairs(chain) do
			local mult = falloff[i] or falloff[#falloff] or 1.0
			local hopPower = math.max(1, math.round(power * mult))
			resolveItemHitOnUnit(user, u, spec.element, hopPower, rider, i == 1, def, result)
		end
		result.effectType = "Damage"
		return true
	end

	-- ===== AREA PATTERNS via the shared enumerator =====
	if not TargetingService then return false end
	local centerX = (type(target) == "table" and target.tileX) or user.tileX
	local centerY = (type(target) == "table" and target.tileY) or user.tileY
	local mapW = (ctx and ctx.mapWidth) or 8
	local mapH = (ctx and ctx.mapHeight) or 8

	-- Line/Cone need a direction (a target tile distinct from the user). Without one
	-- (self-origin, no selected tile) we cannot aim, so defer rather than guess a facing.
	local isLineCone = normPattern:match("^Line%d*$") or normPattern:match("^Cone%d*$")
	if isLineCone and centerX == user.tileX and centerY == user.tileY then
		return false
	end

	local tiles = TargetingService.GetAOETargetTiles(normPattern, user, centerX, centerY, mapW, mapH)
	if not tiles or #tiles == 0 then
		return false  -- unknown pattern (enumerator logged it) -> Unimplemented
	end

	-- AREA DAMAGE ITEMS hit like area skills (user ruling 2026-10-27; mirrors the skill AOE
	-- loop in CommandService): every living unit on the affected tiles except the user, allies
	-- included (friendly fire); a tile counts only within +-2 elevation of the aimed tile and
	-- when no BlocksAOE object stands between; "Impact N": the aimed tile takes 100% and every
	-- other tile 50% (rule 30 Impact Splash). Timed pulses are unchanged (rule 160).
	local isImpact = normPattern:match("^Impact%d*$") ~= nil
	local centerElev = GameConstants.GetElevation(centerX, centerY)
	local tileMult = {}
	for _, t in ipairs(tiles) do
		if math.abs(GameConstants.GetElevation(t.tileX, t.tileY) - centerElev) <= 2
			and not (TargetingService.IsAOEBlocked and TargetingService.IsAOEBlocked(centerX, centerY, t.tileX, t.tileY)) then
			tileMult[t.tileX .. "," .. t.tileY] = (isImpact and not (t.tileX == centerX and t.tileY == centerY)) and 0.5 or 1.0
		end
	end
	-- WIND CLEARS CLOUDS (user ruling 2026-10-27): a Wind area item blows clouds off every
	-- affected tile, occupied or not. Deferred require: no load-time dependency.
	if spec.element == "Wind" then
		local _tes = (require :: any)(script.Parent.TileEffectService)
		if _tes and _tes.WindClearsCloud then
			for _, t in ipairs(tiles) do
				if tileMult[t.tileX .. "," .. t.tileY] then _tes.WindClearsCloud(t.tileX, t.tileY, user.id) end
			end
		end
	end
	local victims = {}
	for _, u in ipairs(allUnits or {}) do
		if u.isAlive and u ~= user and u.id ~= user.id and u.tileX and tileMult[u.tileX .. "," .. u.tileY] then
			table.insert(victims, u)
		end
	end

	if #victims == 0 then
		-- A valid area item that caught no unit this use still "went off" (charge spent,
		-- deterministic), so it is a resolved use, not an Unimplemented miss.
		result.effectType = "Damage"
		result.amount = 0
		result.element = spec.element
		return true
	end

	-- Primary (gets the rider). Line / Cone: the FIRST unit hit = nearest the user (DAM-018
	-- "first target gains Bleed", audit fix 2026-10-27). Other areas: the explicitly-targeted
	-- unit if present, else the unit nearest the center. Deterministic (distance, then id).
	local ox, oy = centerX, centerY
	if isLineCone then ox, oy = user.tileX, user.tileY end
	table.sort(victims, function(a, b)
		local da = math.max(math.abs(a.tileX - ox), math.abs(a.tileY - oy))
		local db = math.max(math.abs(b.tileX - ox), math.abs(b.tileY - oy))
		if da ~= db then return da < db end
		return tostring(a.id) < tostring(b.id)
	end)
	local primaryIdx = 1
	local primaryId = (not isLineCone and type(target) == "table" and target.id) or nil
	if primaryId then
		for i, u in ipairs(victims) do
			if u.id == primaryId then primaryIdx = i break end
		end
	end
	for i, u in ipairs(victims) do
		local mult = tileMult[u.tileX .. "," .. u.tileY] or 1.0
		local hitPower = (mult < 1) and math.max(1, math.round(power * mult)) or power
		resolveItemHitOnUnit(user, u, spec.element, hitPower, rider, i == primaryIdx, def, result, true)
	end
	result.effectType = "Damage"
	return true
end

--------------------------------------------------
-- ITEM DEVICES + FORMULA AMOUNTS (2026-10-26)
-- Authored ASCII formulas like "14+0.32*IL+0.25*DEX" (Designer columns
-- Device_Hp_Formula / Pulse_Amount_Formula). Terms: a constant, c*IL (IL = user
-- level, same as every other item formula here), c*STAT (the user's effective stat).
-- Returns nil when the text has any term it cannot read (never guesses).
--------------------------------------------------
local function evalItemFormula(user: any, text: any): number?
	if type(text) ~= "string" or text == "" then return nil end
	local s = (text:gsub("\195\151", "*")):gsub("%s+", "")
	local IL = user.level or 1
	local total = 0
	for term in string.gmatch(s, "[^+]+") do
		local c, var = string.match(term, "^([%d%.]+)%*(%u+)$")
		if c then
			local v
			if var == "IL" then
				v = IL
			else
				v = user.effectiveStats and user.effectiveStats[var]
			end
			if v == nil then return nil end
			total += tonumber(c) * v
		elseif string.match(term, "^[%d%.]+$") then
			total += tonumber(term) :: number
		else
			return nil
		end
	end
	return total
end

-- Per-kind amount for a pulse with an authored amount formula: damage gets the same
-- Item Specialist / Fumbler multiplier and AC item-damage bonus as computeItemPower;
-- heals get the item-effect multiplier and AC item-heal bonus like tryRestore.
-- Public: item DAMAGE from an authored ASCII formula with the user's item multipliers
-- (Item Specialist / Fumbler, AC item-damage bonus). Used by placed objects whose power is
-- fixed when placed (Portable Ballista). nil when the formula cannot be read.
function ItemEffectService.ItemDamageFromFormula(user: any, text: any): number?
	local raw = evalItemFormula(user, text)
	if raw == nil then return nil end
	local amount = raw * TraitEffectService.GetItemEffectMultiplier(user)
	amount = amount * (1 + ArmorPassiveService.GetItemDamageBonus(user))
	return math.max(1, math.round(amount))
end

local function pulseAmountFromFormula(user: any, def: any): number?
	local raw = evalItemFormula(user, def.pulseAmountFormula)
	if raw == nil then return nil end
	local amount = raw * TraitEffectService.GetItemEffectMultiplier(user)
	if def.pulseKind == "heal" then
		amount = amount * (1 + ArmorPassiveService.GetItemHealBonus(user))
	else
		amount = amount * (1 + ArmorPassiveService.GetItemDamageBonus(user))
	end
	return math.max(1, math.round(amount))
end

local ELEMENT_TAGS = { Physical = true, Fire = true, Ice = true, Water = true, Poison = true,
	Electric = true, Lightning = true, Earth = true, Wind = true, Dark = true, Light = true, Holy = true }
local function elementFromTags(def: any): any
	for _, t in ipairs((def and def.tags) or {}) do
		if ELEMENT_TAGS[t] then return t end
	end
	return nil
end

-- Summon-kind deployables that are built as item devices. The device is a real,
-- targetable, non-acting unit; its HP / lifespan / aura / pulses are authored data.
local DEVICE_TYPES = { Turret = true, Mender = true, Decoy = true, WardTotem = true, Drone = true,
	Hologram = true, Countermeasure = true, WeatherTotem = true, TauntBeacon = true,  -- 2026-10-27
	HealingBeacon = true, PoisonVent = true }  -- DEP-002 / DEP-017 real 3-hit devices (audit fix 2026-10-27)

-- Returns a device plan for a summon-kind deployable, or nil (not a device item).
-- maxHp nil -> caller uses the summon profile's default HP (Mender / Ward Totem).
function ItemEffectService.GetDevicePlan(def: any, user: any): any
	if not def or def.deployKind ~= "summon" or not DEVICE_TYPES[def.deployRef or ""] then
		return nil
	end
	local maxHp = nil
	local fixedHits = false
	if def.deviceHpFormula then
		local hp = evalItemFormula(user, def.deviceHpFormula)
		if hp == nil then return nil end  -- unreadable authored HP: defer, never invent
		maxHp = math.max(1, math.round(hp))
	else
		-- LIGHT GADGET (DB objects_encounters "Deployed Gadget" SPLIT ruling, 2026-10-20): a
		-- device with no HP formula of its own breaks after hitsToDestroy hits from any source
		-- (ObjectData row of the same name, e.g. Mender Drone / Gravity Pylon = 3).
		local od = ObjectData and ObjectData.Objects and ObjectData.Objects[def.name]
		if od and od.hitsToDestroy then
			maxHp = od.hitsToDestroy
			fixedHits = true
		end
	end
	local aura = nil
	if def.deviceAuraRadius then
		aura = {
			radius = def.deviceAuraRadius,
			stabilityBonus = def.deviceAuraStability,
			teleportLock = def.deviceAuraTeleportLock == true,
			-- Element ward aura (DEP-013): multiplier here; the element is the player's pick,
			-- stamped by CommandService at placement (wardElement).
			wardMult = def.deviceAuraWardMult,
			-- DEP-014 Weather Stabilizer Totem: units in the aura ignore the weather.
			weatherShield = def.deviceAuraWeatherShield == true,
			-- SUP-011 Guardian Standard: +Guard percentage points for allies while Guarding.
			guardBonus = def.deviceAuraGuardBonus,
			-- DEP-018 Countermeasure Turret: hostile ranged hits it can still block.
			interceptLeft = def.deviceInterceptCount,
			-- CON-018 Taunt Beacon: enemies in the aura are Taunted by the device (StatusService.GetTaunter).
			taunt = def.deviceAuraTaunt == true,
		}
	end
	local pulse = nil
	if def.pulseKind and def.pulseAnchor == "device" then
		-- Only heal / damage pulses carry an amount; a reveal pulse (drones) has none.
		local amount = 0
		local amountKind = "flat"
		if def.pulseAmount ~= nil then
			-- Authored amount (Healing Beacon 5 = 5% of each ally's own Max HP).
			amount = def.pulseAmount
			amountKind = def.pulseAmountKind or "flat"
		elseif def.pulseKind == "heal" or def.pulseKind == "damage" then
			amount = pulseAmountFromFormula(user, def)
			if amount == nil then return nil end
		end
		pulse = {
			kind = def.pulseKind,
			recipients = def.pulseRecipients,
			radius = def.pulseRadius or 0,
			amount = amount,
			amountKind = amountKind,
			element = def.pulseElement or elementFromTags(def),
			intervalCt = def.pulseInterval,
			pulses = def.pulsePulses,
			offsetCt = def.pulseOffsetCt,
			statusId = def.pulseStatus,
			statusCt = def.pulseStatusCt,
			tileEffect = def.pulseTileEffect,      -- Poison Cloud Vent
			tileEffectCt = def.pulseTileEffectCt,
			targetMode = def.pulseTargetMode,
			requiresLoS = def.pulseRequiresLoS == true,
			fireImmediate = def.pulseFireImmediate == true,  -- drones: reveal on placement
		}
	end
	return {
		summonType = def.deployRef,
		displayName = def.name,
		maxHp = maxHp,
		lifespanCt = def.deviceLifespanCt,
		fixedHits = fixedHits,
		auraSpec = aura,
		pulse = pulse,
	}
end

--------------------------------------------------
-- HANDLER: PULSE (tile-anchored, fixed-CT repeating effect)
--
-- Data-driven: reads an authored pulse spec off the item def (populated in
-- CTRBLXAI.db / ConsumableData). Required fields: pulseKind ("heal"|"damage"|
-- "status"), pulseInterval (CT > 0), pulsePulses (>=1). Optional: pulseAmount +
-- pulseAmountKind ("flat"|"pctMaxHp"), pulseElement, pulseStatus + pulseStatusCt,
-- pulseRadius (default 0), pulseRecipients ("allies"|"enemies"; defaults by kind),
-- pulseOffsetCt (CT before the first pulse; 0 = fire at the first interval).
-- A "damage" pulse with a Power formula uses the parsed flat Power as pulseAmount
-- when pulseAmount is absent. Registers with the injected scheduler; the battle
-- clock fires it. Returns false (defer) when scheduler/spec/tile-target is missing.
--------------------------------------------------
local function tryPulse(user: any, target: any, def: any, result: any, ctx: any): boolean
	if not def or not def.pulseKind then return false end
	-- Device-anchored pulses are registered by the device spawn (CommandService), not here.
	if def.pulseAnchor == "device" then return false end
	-- Unit-anchored heal-over-time (REC-007 / REC-008, 2026-10-27) needs a unit target.
	local anchorTarget = def.pulseAnchor == "target"
	if anchorTarget and not (type(target) == "table" and target.isAlive and not target.isGroundTarget) then
		return false
	end
	if not _pulseScheduler or not (ctx and ctx.state) then return false end
	if (def.pulseInterval or 0) <= 0 or (def.pulsePulses or 0) < 1 then return false end

	-- Anchor tile: the selected tile for a Ground/Empty-Tile item, else the user's tile.
	local tx = (type(target) == "table" and target.tileX) or user.tileX
	local ty = (type(target) == "table" and target.tileY) or user.tileY
	if not (tx and ty) then return false end

	-- Amount: authored flat/pct, or the item's parsed Power formula for damage pulses.
	local amount = def.pulseAmount
	local amountKind = def.pulseAmountKind or "flat"
	-- Authored amount formula (Tesla Pylon "20+0.45*IL+0.35*INT", 2026-10-26).
	if amount == nil and def.pulseAmountFormula then
		amount = pulseAmountFromFormula(user, def)
		if amount == nil then return false end
		amountKind = "flat"
		if not result.element then result.element = elementFromTags(def) end
	end
	if amount == nil and def.pulseKind == "damage" then
		local spec = parsePowerFormula(def.effectFormula or "")
		if spec then
			-- Use the SHARED item-power helper so pulse damage gets the same Item
			-- Specialist/Fumbler trait multiplier and AC item-damage accessory bonus as
			-- the single-hit / AOE damage paths (consistency WARN fix). Pulse damage is
			-- still applied directly in PulseScheduler (no ResolveSkill), so it does not
			-- double-count skill-potency; this only aligns the item-% multipliers.
			amount = computeItemPower(user, spec)
			amountKind = "flat"
			if not result.element then result.element = spec.element end
		end
	end

	-- One-per-type limit (user ruling 2026-10-26): a DEPLOYABLE that acts on its own
	-- (Healing Beacon, Poison Cloud Vent) replaces the same user's previous one.
	if def.category == "Deployable" and _pulseScheduler.CancelByOwnerItem then
		_pulseScheduler.CancelByOwnerItem(ctx.state, user.id, def.name)
	end

	local entry = _pulseScheduler.Register(ctx.state, {
		ownerId = user.id,
		sourceName = def.name,  -- battle log names the item that hit (Tesla Pylon, Meteor Marker, ...)
		side = user.side,
		tileX = tx, tileY = ty,
		kind = def.pulseKind,
		recipients = def.pulseRecipients,
		radius = def.pulseRadius or 0,
		amount = amount or 0,
		amountKind = amountKind,
		element = def.pulseElement or result.element,
		statusId = def.pulseStatus,
		statusCt = def.pulseStatusCt,
		intervalCt = def.pulseInterval,
		pulses = def.pulsePulses,
		offsetCt = def.pulseOffsetCt,
		tileEffect = def.pulseTileEffect,     -- kind "tileEffect" (Poison Cloud Vent)
		tileEffectCt = def.pulseTileEffectCt,
		itemId = def.name,
		ringFalloff = def.pulseRingFalloff,  -- Meteor Marker 100%/65%/35% by ring
		-- "Impact N" pattern (user ruling 2026-10-27, Meteor Marker): the cross shape a skill
		-- with that pattern hits, not the full square.
		shape = (tostring(def.pattern or ""):gsub("%s+", "")):match("^Impact%d*$") and "cross" or nil,
		targetMode = def.pulseTargetMode,
		requiresLoS = def.pulseRequiresLoS == true,
		anchorUnitId = if anchorTarget then target.id else nil,  -- follows the target, stops if it dies
		-- fireImmediate: items that burst AT USE (CT 0) as well as on the interval
		-- carry "At 0" in their formula (only Thermite among current pulse items:
		-- "At 0, 400, 800, 1200 CT"). Healing Beacon ("every 400 CT") and Poison
		-- Cloud ("at 400, 800, 1200 CT") do NOT, so they correctly start at the
		-- first interval. Derived from the item's own formula (no local `formula`
		-- in this function -> read def.effectFormula) so no extra data field is needed.
		fireImmediate = def.pulseFireImmediate == true or string.match(def.effectFormula or "", "At%s+0[,%s]") ~= nil,
	})
	if not entry then return false end
	-- REC-007 Mending Salve: the pulses are the LATER heals; the "now" heal still runs
	-- through the normal restore handler (Resolve continues).
	if anchorTarget and def.pulseFireImmediate ~= true then return false end

	result.effectType = "Pulse"
	result.amount = def.pulsePulses
	result.statusId = def.pulseStatus
	return true
end

--------------------------------------------------
-- PUBLIC: Resolve
-- Mirrors the old resolveItemEffect signature/return so CommandService can
-- delegate with no other change. Returns a result table for broadcasting.
--------------------------------------------------
-- HANDLER: RT REDUCE (Utility tempo items)
-- "Reduce remaining RT by round(<base> + <ilCoeff>xIL), minimum 0." Pure state
-- change on a unit target's remainingRt (reuses no other system). Lowering
-- remaining RT moves the target up the timeline (acts sooner). Unit-targeted only.
local function tryRtReduce(user: any, target: any, def: any, formula: string, result: any): boolean
	-- Normalise the UTF-8 multiply sign (bytes C3 97) to ASCII "x" first (same reason as
	-- parsePowerFormula: a Lua class/literal cannot span the two-byte sign).
	formula = (formula:gsub("\195\151", "x"))
	local base, ilc = string.match(formula, "Reduce remaining RT by round%((%d+)%s*%+%s*([%d%.]+)xIL%)")
	if not base then
		-- also accept a plain flat "Reduce remaining RT by round(N)".
		base = string.match(formula, "Reduce remaining RT by round%((%d+)%)")
		ilc = nil
		if not base then return false end
	end
	if not isUnitTargeted(def) or type(target) ~= "table" then
		return false
	end
	local IL = user.level or 1
	local amount = math.round(tonumber(base) + (ilc and tonumber(ilc) or 0) * IL)
	local before = target.remainingRt or 0
	target.remainingRt = math.max(0, before - amount)
	result.effectType = "RtReduce"
	result.amount = before - target.remainingRt
	return true
end

-- HANDLER: RT DELAY (Control tempo debuffs, inverse of RtReduce)
-- "RT Delay = round(<base> + <ilCoeff>xIL) before resistance." Adds remaining RT to a
-- unit target (pushes it DOWN the timeline / acts later). "before resistance" means the
-- raw delay is reduced by the target's RT Delay Resistance (VIT + gear) via the SAME
-- GameConstants.CalcRtDelayResistance the Push / skill RT-delay paths use. Unit-targeted,
-- single-target only (area RT-delay, e.g. the DEP-007 trap, is a separate pass).
local function tryRtDelay(user: any, target: any, def: any, formula: string, result: any): boolean
	-- Normalise the UTF-8 multiply sign (bytes C3 97) to ASCII "x" before matching.
	formula = (formula:gsub("\195\151", "x"))
	local base, ilc = string.match(formula, "RT Delay%s*=%s*round%((%d+)%s*%+%s*([%d%.]+)xIL%)")
	if not base then
		base = string.match(formula, "RT Delay%s*=%s*round%((%d+)%)")
		ilc = nil
		if not base then return false end
	end
	if not isUnitTargeted(def) or type(target) ~= "table" or not target.isAlive then
		return false
	end
	local IL = user.level or 1
	local rawDelay = math.round(tonumber(base) + (ilc and tonumber(ilc) or 0) * IL)
	local targetVit = (target.effectiveStats and target.effectiveStats.VIT) or 10
	local gearResist = (target.gearDerived and target.gearDerived.rtDelayResist) or 1
	local actualDelay = GameConstants.CalcRtDelayResistance(rawDelay, targetVit, gearResist)
	actualDelay = math.max(0, actualDelay)
	target.remainingRt = (target.remainingRt or 0) + actualDelay
	result.effectType = "RtDelay"
	result.amount = actualDelay
	return true
end

-- HANDLER: SHIELD (Support barrier items)
-- "Shield = <base> + <il>xIL + <pct>% Max HP for <dur> CT." Grants a shield pool via
-- the existing StatusService.ApplyShield (the same one-pool, replace-on-recast system
-- skills use). Per-target amount (the % Max HP term scales to each recipient). Area
-- patterns shield every ALLY on the affected tiles; single-target shields the unit.
-- Reuses isAreaPattern + the AOE enumerator; no new shield mechanic.
local function tryShield(user: any, target: any, def: any, formula: string, result: any, allUnits: any, ctx: any): boolean
	formula = (formula:gsub("\195\151", "x"))
	local base, il, pct = string.match(formula, "Shield%s*=%s*([%d%.]+)%s*%+%s*([%d%.]+)xIL%s*%+%s*([%d%.]+)%%%s*Max HP")
	if not base then
		return false
	end
	if not StatusService or not StatusService.ApplyShield then
		return false
	end
	local dur = tonumber(string.match(formula, "for (%d+) CT")) or 800
	local IL = user.level or 1
	local function grantShield(u: any)
		local hp = math.round(tonumber(base) + tonumber(il) * IL + (tonumber(pct) / 100) * (u.maxHp or 0))
		StatusService.ApplyShield(u, hp, dur, user.id)
	end

	local norm = (tostring(def.pattern or "Single"):gsub("%s+", ""))
	if isAreaPattern(norm) and TargetingService then
		local cx = (type(target) == "table" and target.tileX) or user.tileX
		local cy = (type(target) == "table" and target.tileY) or user.tileY
		local mapW = (ctx and ctx.mapWidth) or 8
		local mapH = (ctx and ctx.mapHeight) or 8
		local tiles = TargetingService.GetAOETargetTiles(norm, user, cx, cy, mapW, mapH)
		if not tiles or #tiles == 0 then return false end
		local key = {}
		for _, t in ipairs(tiles) do key[t.tileX .. "," .. t.tileY] = true end
		local count = 0
		for _, u in ipairs(allUnits or {}) do
			if u.isAlive and u.side == user.side and u.tileX and key[u.tileX .. "," .. u.tileY] then
				grantShield(u)
				count += 1
			end
		end
		result.effectType = "Shield"
		result.amount = count
		return true
	end

	if type(target) ~= "table" or not target.isAlive then return false end
	grantShield(target)
	result.effectType = "Shield"
	result.amount = 1
	return true
end

-- HANDLER: AREA RESTORE (2026-10-26, REC-020 Field Restorative Array, "Self and Allies").
-- "Restore N% Max HP and M% Max MP to each ally in area." Centred on the USER (the
-- target is the user, not a tile). Same trait / accessory healing multipliers as the
-- single-target restore. Affected units are returned in result.affectedUnits so the
-- caller can refresh their bars. Previously this item healed a ground marker and errored.
local function tryAreaRestore(user: any, def: any, formula: string, result: any, allUnits: any): boolean
	if tostring(def.targetRules or "") ~= "Self and Allies" then return false end
	local hpPct = tonumber(string.match(formula, "Restore (%d+)%% Max HP"))
	local mpPct = tonumber(string.match(formula, "(%d+)%% Max MP"))
	if not hpPct and not mpPct then return false end
	local norm = (tostring(def.pattern or "Single"):gsub("%s+", ""))
	local radius = tonumber(norm:match("^Circle(%d+)$")) or tonumber(norm:match("^Aura(%d+)$")) or 0
	local total = 0
	result.affectedUnits = {}
	for _, u in ipairs(allUnits or {}) do
		if u.isAlive and u.side == user.side and u.tileX and user.tileX
			and math.max(math.abs(u.tileX - user.tileX), math.abs(u.tileY - user.tileY)) <= radius then
			if hpPct then
				local heal = math.ceil((u.maxHp or 0) * hpPct / 100)
				heal = math.max(0, math.round(heal * TraitEffectService.GetItemEffectMultiplier(user)))
				heal = math.max(0, math.round(heal * (1 + ArmorPassiveService.GetItemHealBonus(user))))
				total += (UnitSchema.ApplyHealing(u, heal) or 0)
			end
			if mpPct and (u.maxMp or 0) > 0 then
				local restore = math.max(1, math.ceil(u.maxMp * mpPct / 100))
				u.currentMp = math.min(u.maxMp, (u.currentMp or 0) + restore)
			end
			table.insert(result.affectedUnits, u)
		end
	end
	result.effectType = "HpRestore"
	result.amount = total
	return true
end

-- RESCUE MOVES (2026-10-26). Pure classifiers; CommandService performs the move.
-- UTI-012 Recovery Winch (tags Rescue + Pull): "Move target one legal tile toward user
--   without collision or fall damage."
-- UTI-013 Climbing Line (tag Elevation Rescue): "Relocate upward by up to 2 elevation to
--   nearest legal tile."
function ItemEffectService.GetWinchPlan(def: any): any
	-- CON-008 Grapple Cable shares the tags but pulls with a Force formula: it is a real pull
	-- (GetPushPlan), not a one-tile rescue (2026-10-27 audit fix).
	if def and string.find(def.effectFormula or "", "Force%s*=") then return nil end
	if def and hasTag(def, "Rescue") and hasTag(def, "Pull") then
		return { steps = 1 }
	end
	return nil
end
-- CON-016 Magnetic Snare (tags Mechanical + Pull): "Treat Stability as 2 lower and pull
-- 2 tiles if legal." Force = the pull distance; the target's Stability counts 2 lower.
function ItemEffectService.GetSnarePlan(def: any): any
	if not (def and hasTag(def, "Mechanical") and hasTag(def, "Pull")) then return nil end
	local f = def.effectFormula or ""
	local dist = tonumber(string.match(f, "pull (%d+) tiles"))
	if not dist then return nil end
	return { distance = dist, stabilityIgnore = tonumber(string.match(f, "Stability as (%d+) lower")) or 0 }
end
-- ENV-009 Gale Engine (tags Wind + Push), user ruling 2026-10-26: every unit in the cone
-- (both sides) is pushed away from the user with the authored Force; airborne zones in the
-- cone (Steam, Static Cloud, other "Airborne"-tagged tile effects) are blown away.
function ItemEffectService.GetGalePlan(def: any): any
	if not (def and hasTag(def, "Wind") and hasTag(def, "Push")) then return nil end
	local force = tonumber(string.match(def.effectFormula or "", "[Ff]orce (%d+)"))
	if not force then return nil end
	return { force = force }
end
-- UTI-008 Maintenance Tool (tag "Object Repair"), user ruling 2026-10-26: fully restores
-- an item device (HP / hit counter, lifespan, timed effects) or a placed deployable object.
function ItemEffectService.IsRepairItem(def: any): boolean
	return def ~= nil and hasTag(def, "Object Repair")
end
-- ENV-019 Road Fabricator (tags Path + Terrain, no terrain transform): "Create temporary
-- road state reducing positive movement penalties by 1 for 2000 CT." (Icebreaker carries the
-- same tags but has terrainTransforms, so it is excluded.)
function ItemEffectService.GetRoadPlan(def: any): any
	if not (def and hasTag(def, "Path") and hasTag(def, "Terrain")) then return nil end
	if type(def.terrainTransforms) == "table" and #def.terrainTransforms > 0 then return nil end
	local f = def.effectFormula or ""
	local ct = tonumber(string.match(f, "for (%d+) CT"))
	if not ct then return nil end
	return { durationCt = ct, cut = tonumber(string.match(f, "penalties by (%d+)")) or 1 }
end
-- ENV-012 Excavation Drill (tags Terrain + Elevation): lower each legal tile in its pattern
-- by N ("by 1"). Illegal: water / lava / deep tiles, chasm floors, blocked tiles, deployment
-- zones; protected spans and elevation-immune tiles are refused by LowerElevation itself.
function ItemEffectService.GetExcavatePlan(def: any): any
	if not (def and hasTag(def, "Terrain") and hasTag(def, "Elevation")) then return nil end
	return { amount = tonumber(string.match(def.effectFormula or "", "elevation by (%d+)")) or 1 }
end
-- DAM-014 Breaching Drill (tag Object, rule "Object or Unit"), user ruling 2026-10-27:
-- on an OBJECT it removes 1 hit (normal 3-hit rule); on a UNIT it deals Physical damage =
-- "unit Power = N%" of the Object Power formula (the user's stats, item multipliers).
function ItemEffectService.GetBreachPlan(def: any, user: any): any
	if not (def and hasTag(def, "Object") and tostring(def.targetRules or "") == "Object or Unit") then return nil end
	local f = def.effectFormula or ""
	local objText = string.match(f, "Object Power%s*=%s*([^;]+)")
	if not objText then return nil end
	local pow = ItemEffectService.ItemDamageFromFormula(user, objText)
	if not pow then return nil end
	local pct = tonumber(string.match(f, "unit Power%s*=%s*(%d+)%%")) or 100
	return { unitPower = math.max(1, math.round(pow * pct / 100)) }
end
-- ENV-010 Bridge Projector (rule "Gap Endpoints"): bridges a gap for N CT.
function ItemEffectService.GetBridgePlan(def: any): any
	if not (def and tostring(def.targetRules or "") == "Gap Endpoints") then return nil end
	local f = def.effectFormula or ""
	return {
		durationCt = tonumber(string.match(f, "for (%d+) CT")) or 2000,
		maxLen = tonumber(string.match(tostring(def.pattern or ""), "(%d+)%s*$")) or 4,
	}
end
-- ENV-020 Weather Stabilizer (tag "Weather Suppression"): a bodiless weather-shield zone.
function ItemEffectService.GetWeatherZonePlan(def: any): any
	if not (def and hasTag(def, "Weather Suppression")) then return nil end
	return {
		radius = tonumber(string.match(tostring(def.pattern or ""), "Aura%s*(%d+)")) or 3,
		durationCt = tonumber(string.match(def.effectFormula or "", "for (%d+) CT")) or 0,
	}
end
-- UTI-017 Recruitment Beacon (tags Recruitment + Area), user ruling 2026-10-27: recruitable
-- enemies in the area can be recruited at a higher HP threshold (+N percentage points).
function ItemEffectService.GetRecruitBeaconPlan(def: any): any
	if not (def and hasTag(def, "Recruitment") and hasTag(def, "Area")) then return nil end
	local pts = tonumber(string.match(def.effectFormula or "", "%+(%d+) percentage points")) or 10
	return { bonus = pts / 100 }
end
-- CON-020 Suppression Field (tag "RT Cost Increase", 2026-10-27): a bodiless zone; enemies
-- of the user who act inside it pay extra RT (project_rules 189).
function ItemEffectService.GetSuppressionPlan(def: any): any
	if not (def and hasTag(def, "RT Cost Increase")) then return nil end
	local add, ct = string.match(def.effectFormula or "", "add (%d+) RT for (%d+) CT")
	if not add then return nil end
	return {
		add = tonumber(add),
		durationCt = tonumber(ct),
		radius = tonumber(string.match(tostring(def.pattern or ""), "Circle%s*(%d+)")) or 0,
	}
end
function ItemEffectService.GetClimbPlan(def: any): any
	if def and hasTag(def, "Elevation Rescue") then
		local gain = tonumber(string.match(def.effectFormula or "", "up to (%d+) elevation")) or 2
		-- User ruling 2026-10-26: the higher tile must lie within N tiles ("within 3 tiles").
		return { maxGain = gain, radius = tonumber(string.match(def.effectFormula or "", "within (%d+) tiles")) }
	end
	return nil
end
function ItemEffectService.IsChargeRelayItem(def: any): boolean
	return isChargeRelayItem(def)
end
-- Firebreak Projector (ENV-015, tag "Anti-Fire"): "Remove Flammable state and extinguish
-- Burn zones along line for 1200 CT." Returns the guard duration, or nil.
function ItemEffectService.GetFirebreakPlan(def: any): any
	if def and hasTag(def, "Anti-Fire") then
		return { durationCt = tonumber(string.match(def.effectFormula or "", "for (%d+) CT")) or 0 }
	end
	return nil
end

-- INTERACTION AMPLIFIER (UTI-016, tags Interact + Range, Self): "Next Interact before end
-- of turn gains Maximum Range +1 and RT x0.80." Stamps the user; TargetingService adds the
-- range, CommandService applies the RT multiplier and clears it on the next Interact.
-- BattleCoordinator clears it when the unit's next turn opens.
local function tryInteractAmp(user: any, def: any, result: any): boolean
	if not (hasTag(def, "Interact") and hasTag(def, "Range")) then return false end
	local f = ((def.effectFormula or ""):gsub("\195\151", "x"))
	user._interactAmp = {
		range = tonumber(string.match(f, "Maximum Range %+(%d+)")) or 0,
		rtMult = tonumber(string.match(f, "RT%s*x(%d+%.?%d*)")) or 1,
	}
	result.effectType = "Buff"
	result.description = def.name .. ": next Interact this turn gains range and costs less RT"
	return true
end

-- RIDERS (2026-10-27 audit fixes): the extra clauses of items whose main effect is
-- resolved by tryRestore / tryDamage / tryStatusApply.
local function rtDelayOn(unit: any, raw: number)
	local vit = (unit.effectiveStats and unit.effectiveStats.VIT) or 10
	local gear = (unit.gearDerived and unit.gearDerived.rtDelayResist) or 1
	local d = math.max(0, GameConstants.CalcRtDelayResistance(raw, vit, gear))
	unit.remainingRt = (unit.remainingRt or 0) + d
	return d
end

local function splitNames(text: string): { string }
	local out = {}
	local t = (text:gsub(", and ", ", "))
	t = (t:gsub(" and ", ", "))
	for s in string.gmatch(t, "[^,]+") do
		local n = string.match(s, "^%s*(.-)%s*$")
		if n and n ~= "" then table.insert(out, n) end
	end
	return out
end

-- REC-014 Trauma Kit (heal + remove listed statuses), REC-015 Cooling Gel (remove Burn +
-- heal), REC-019 Triage Pack (heal + Shield when the target was low).
local function applyRestoreRiders(user: any, target: any, formula: string, result: any, preHpFrac: number)
	if type(target) ~= "table" or not target.isAlive then return end
	local list = string.match(formula, "^Remove (.-) and restore") or string.match(formula, " and remove (.-)%.?$")
	if list then
		local removed = {}
		for _, n in ipairs(splitNames(list)) do
			if StatusService.RemoveStatus(target, n) then table.insert(removed, n) end
		end
		if #removed > 0 then result.statusId = table.concat(removed, ", ") end
	end
	local th, sp, sct = string.match(formula, "if target was below (%d+)%%, grant Shield = (%d+)%% Max HP for (%d+) CT")
	if th and preHpFrac < tonumber(th) / 100 and StatusService.ApplyShield then
		StatusService.ApplyShield(target, math.max(1, math.round((target.maxHp or 0) * tonumber(sp) / 100)), tonumber(sct), user.id)
	end
end

-- DAM-007 / DAM-008 Defense debuff, DAM-004 centre RT Delay, DAM-011 HP payment, DAM-012 drain.
local function applyDamageRiders(user: any, target: any, def: any, formula: string, result: any)
	local hit = result._hitUnits or {}
	result._hitUnits = nil
	local sDef = def.appliesStatus and GameConstants.STATUSES and GameConstants.STATUSES[def.appliesStatus]
	if sDef and sDef.kind == "Debuff" then
		for _, u in ipairs(hit) do
			if u.isAlive then applyItemStatus(user, u, def.appliesStatus, nil) end
		end
	end
	local cRt = tonumber(string.match(formula, "center receives (%d+) RT Delay"))
	if cRt and type(target) == "table" and target.tileX then
		for _, u in ipairs(hit) do
			if u.isAlive and u.tileX == target.tileX and u.tileY == target.tileY then
				rtDelayOn(u, cRt)
				break
			end
		end
	end
	result.affectedUnits = result.affectedUnits or {}
	local pay = tonumber(string.match(formula, "user pays (%d+)%% Max HP"))
	if pay and user.isAlive then
		-- An item cost, not damage: never lethal (same floor-1 rule as other self costs).
		local loss = math.ceil((user.maxHp or 0) * pay / 100)
		user.currentHp = math.max(1, (user.currentHp or 0) - loss)
		table.insert(result.affectedUnits, user)
	end
	local dp, cap = string.match(formula, "restore (%d+)%% of final HP damage, capped at (%d+)%% Max HP")
	if dp and user.isAlive and (result.amount or 0) > 0 then
		local heal = math.min(math.floor(result.amount * tonumber(dp) / 100), math.floor((user.maxHp or 0) * tonumber(cap) / 100))
		if heal > 0 then
			UnitSchema.ApplyHealing(user, heal)
			table.insert(result.affectedUnits, user)
		end
	end
end

-- CON-005 Weapon Jammer: Mechanical targets also get an RT Delay.
local function applyStatusRiders(user: any, target: any, formula: string, result: any)
	local mrt = tonumber(string.match(formula, "Mechanical target also receives (%d+) RT Delay"))
	if mrt and type(target) == "table" and target.isAlive and not target.isGroundTarget
		and CombatResolver.HasRaceTag and CombatResolver.HasRaceTag(target, "Mechanical") then
		rtDelayOn(target, mrt)
	end
end

function ItemEffectService.Resolve(user: any, target: any, consumableDef: any, allUnits: any, ctx: any): any
	local formula = (consumableDef and consumableDef.effectFormula) or ""
	local result: any = {
		effectType = "Unknown",
		amount = 0,
		statusId = nil,
		element = nil,
		description = formula,
	}

	-- PULSE items (2026-10-26): tile-anchored, fixed-CT repeating effects whose spec is
	-- authored as data (pulseKind/pulseInterval/pulsePulses/pulseAmount/...). Registered
	-- with the injected PulseScheduler; the battle clock fires them. Runs FIRST because
	-- pulse items are tile-targeted (never unit handlers). Defers (returns false) when the
	-- scheduler is absent, the spec is incomplete, or no tile target -> logged, never faked.
	if tryPulse(user, target, consumableDef, result, ctx) then return result end
	if tryAreaRestore(user, consumableDef, formula, result, allUnits) then return result end
	if tryInteractAmp(user, consumableDef, result) then return result end

	-- Target-type gate (DEFECT-1 fix, 2026-10-26): heal / cure / revive act on a UNIT
	-- and read unit tables (statusInstances, maxHp, ...). A Ground/Tile/Object item is
	-- validated with a coordinate {tileX,tileY}, not a unit, so routing one into these
	-- handlers crashed (ipairs(nil) in StatusService.RemoveStatus). These handlers do
	-- NOT receive consumableDef, so they cannot self-gate — gate them HERE, once, before
	-- dispatch. Non-unit items (ENV-015 Ground, REC-016 Ground, UTI-008 Object) now fall
	-- through to the deploy/environment pass (currently -> Unimplemented), as required.
	-- tryDamage / tryStatusApply already gate internally (isUnitTargeted + pattern), so
	-- they stay outside this block and keep their own, stricter gates.
	if isUnitTargeted(consumableDef) then
		local _preHpFrac = 1
		if type(target) == "table" and (target.maxHp or 0) > 0 then
			_preHpFrac = (target.currentHp or 0) / target.maxHp
		end
		if tryRestore(user, target, formula, result) then
			applyRestoreRiders(user, target, formula, result, _preHpFrac)
			return result
		end
		if tryCure(target, formula, result) then return result end
		if tryRevive(target, formula, result, allUnits, ctx) then return result end
	end
	if tryDamage(user, target, consumableDef, formula, result, allUnits, ctx) then
		applyDamageRiders(user, target, consumableDef, formula, result)
		return result
	end
	if tryStatusApply(user, target, consumableDef, formula, result, allUnits, ctx) then
		applyStatusRiders(user, target, formula, result)
		return result
	end
	if tryRtReduce(user, target, consumableDef, formula, result) then return result end
	if tryRtDelay(user, target, consumableDef, formula, result) then return result end
	if tryShield(user, target, consumableDef, formula, result, allUnits, ctx) then return result end

	-- Not yet handled (AOE/deploy/environment/bespoke). Logged, never faked.
	print("[ItemEffectService] Effect not yet implemented: " .. formula)
	result.effectType = "Unimplemented"
	return result
end

return ItemEffectService
