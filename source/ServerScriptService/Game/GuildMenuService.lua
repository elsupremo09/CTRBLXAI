--!strict
-- GuildMenuService.lua
-- CTRBLXAI | Slice 6 — TEMPORARY Guild menu (server side)
--
-- game_flow id 23 "Town: first version": the town is a base screen with one button
-- per building. This module is the server half of that screen. It owns NO game
-- rules of its own — it is the glue between the GuildEvents remotes and the Slice 6
-- services that already exist (Recruitment, Merchant, Blacksmith, Dispatch,
-- Progression, Currency). Every request is validated here before a service is
-- called (SEC-001): right player, menu open, rate limit, argument types, ownership,
-- and the service re-prices everything itself (the client never sends a price).
--
-- OWNS (temporary, until Slice 8 facilities exist):
--   * the ONE table of building levels (all 1 for now, Dev-adjustable 1..10)
--   * the persisted completed-battle counter (drives dispatch returns + shop reroll)
--   * the list of hired units' identity (name/level/race/doctrine) so they can be
--     rebuilt next session (the roster save deliberately stores no names)
--   * the hire/dispatch/shop board caches for the current session
--
-- MUST NOT OWN: prices, fees, XP, item levels, stock rules (the services own them).
--
-- Dependencies on Main's runtime state (playerUnits, doSave, the session player)
-- are INJECTED via Init (ARC-004 / ARC-006: nil-safe). Content + service modules
-- are required directly (none of them requires this module, so no cycle — AP-013).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Game    = ServerScriptService:WaitForChild("Game")
local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI")
local Content = ReplicatedStorage:WaitForChild("Content")

-- Remote registries build their fields at runtime, so type them as `any` for the
-- strict checker (runtime behaviour unchanged).
local GuildEvents: any  = require(CTRBLXAI:WaitForChild("Remotes"):WaitForChild("GuildEvents"))
local BattleEvents: any = require(CTRBLXAI:WaitForChild("Remotes"):WaitForChild("BattleEvents"))

local UnitSchema             = require(Game:WaitForChild("UnitSchema"))
local EquipmentService       = require(Game:WaitForChild("EquipmentService"))
local InventoryService       = require(Game:WaitForChild("InventoryService"))
local ItemGenerator          = require(Game:WaitForChild("ItemGenerator"))
local TraitRoller            = require(Game:WaitForChild("TraitRoller"))
local StatusService          = require(Game:WaitForChild("StatusService"))
local PersistentStateService = require(Game:WaitForChild("PersistentStateService"))
local CurrencyService        = require(Game:WaitForChild("CurrencyService"))
local RecruitmentService     = require(Game:WaitForChild("RecruitmentService"))
local MerchantService        = require(Game:WaitForChild("MerchantService"))
local BlacksmithService      = require(Game:WaitForChild("BlacksmithService"))
local DispatchService        = require(Game:WaitForChild("DispatchService"))
local ProgressionService     = require(Game:WaitForChild("ProgressionService"))

local RaceData     = require(Content:WaitForChild("RaceData"))
local DoctrineData = require(Content:WaitForChild("DoctrineData"))
local WeaponData   = require(Content:WaitForChild("WeaponData"))
local ArmorData    = require(Content:WaitForChild("ArmorData"))
local UnitNameData = require(Content:WaitForChild("UnitNameData"))
local TraitData    = require(Content:WaitForChild("TraitData"))

local GuildMenuService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

-- TEMPORARY building levels (user decision 2026-10-07: every building = level 1
-- until Slice 8 builds real facility purchasing). ONE table, Dev-adjustable.
local DEFAULT_BUILDING_LEVEL = 1
local BUILDING_MIN_LEVEL, BUILDING_MAX_LEVEL = 1, 10 -- guild_facilities: Max Level 10
local BUILDING_NAMES = table.freeze({ "GuildHall", "Tavern", "Merchant", "Blacksmith" })

-- game_flow id 4: a party holds up to 7 units (max deployment).
local MAX_DEPLOY = 7

-- guild_facilities id 15: Merchant stock refreshes every 5 completed battles.
-- (Used only to know when our cached view is stale; MerchantService owns the reroll.)
local MERCHANT_REFRESH_BATTLES = 5

-- guild_facilities id 12/13 (Locked): Blacksmith max upgradeable item level =
-- Level x 10 (L10 = 99), and the rarity a Blacksmith level may upgrade.
-- UAT D1 fix 2026-10-07: Broken is NOT in the id 13 unlock list, so it is absent
-- here and Broken items are refused ("cannot be upgraded").
local BLACKSMITH_RARITY_LEVEL = table.freeze({
	Common = 1, Uncommon = 1, Rare = 3, Epic = 5, Legendary = 7, Mythic = 9,
})
local ITEM_LEVEL_CAP = 99

local RATE_LIMIT_SECONDS = 0.2 -- SEC-001: per-player, per-request minimum spacing
local MAX_DISPATCH_PICK = 7

local EQUIP_SLOT_ORDER = table.freeze({ "MainHand", "OffHand", "Head", "Body", "Gloves", "Feet", "Accessory" })

--------------------------------------------------
-- INJECTED STATE (Init) — all nil-safe
--------------------------------------------------

local _playerId: string = "player_1"
local _sessionPlayer: Player? = nil
local _getPlayerUnits: (() -> { [string]: any })? = nil
local _addPlayerUnit: ((any) -> ())? = nil
local _doSave: (() -> any)? = nil
local _getMapLevel: (() -> number)? = nil
local _isSkillRegistered: ((string) -> boolean)? = nil

--------------------------------------------------
-- RUNTIME STATE
--------------------------------------------------

local isOpen = false
local currentPhase: string? = nil
local buildingLevels: { [string]: number } = {}
for _, b in BUILDING_NAMES do buildingLevels[b] = DEFAULT_BUILDING_LEVEL end

-- Persisted (Export/Import)
local battlesCompleted = 0
local hireCounter = 0
local recruitDefs: { [string]: any } = {} -- unitId -> { name, level, raceId, doctrineId, quality }
local recruitOrder: { string } = {}

-- Session only
local pendingBattleUnits: { any } = {} -- hired before battle; joins this battle's roster
local builtUnits: { [string]: any } = {} -- factory output keyed by unitId (hire handoff)
local awayUntil: { [string]: number } = {} -- availability sink mirror (UI only)
local tavernCache: any = nil
local merchantCache: any = nil
local dispatchCache: any = nil
local lastCallAt: { [string]: number } = {}

--------------------------------------------------
-- SMALL HELPERS
--------------------------------------------------

local function playerUnits(): { [string]: any }
	return (_getPlayerUnits and _getPlayerUnits()) or {}
end

local function mapLevel(): number
	local lvl = _getMapLevel and _getMapLevel() or 1
	return math.max(1, math.floor(tonumber(lvl) or 1))
end

local function save()
	if _doSave then _doSave() end
end

local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for k in t do table.insert(keys, k) end
	table.sort(keys)
	return keys
end

local function seedFromId(id: string): number
	local seed = 0
	for i = 1, #id do seed += string.byte(id, i) * i end
	return seed
end

local function raceHasTag(raceId: string?, tag: string): boolean
	local race = raceId and RaceData.GetRace(raceId) or nil
	if race and race.tags then
		for _, t in race.tags do
			if t == tag then return true end
		end
	end
	return false
end

local function itemDisplayName(item: any): string
	if item.displayName then return item.displayName end
	local def = WeaponData.GetByArchetypeId(item.baseArchetypeId) or ArmorData.GetByArchetypeId(item.baseArchetypeId)
	return (def and def.name) or tostring(item.baseArchetypeId)
end

-- instanceId -> unit holding it (nil if loose). InventoryService has no equipped
-- flag, so ownership-by-slot is read from the live units (MerchantService's own
-- equipped check relies on a flag that is never set — we guard here instead).
local function holderOf(instanceId: string): any?
	for _, u in playerUnits() do
		if u.equipmentSlots then
			for _, it in u.equipmentSlots do
				if it and it.instanceId == instanceId then return u end
			end
		end
	end
	return nil
end

local function balance()
	local b = CurrencyService.GetBalance(_playerId)
	local mats = {}
	for t = 1, 5 do mats[t] = (b.materials and b.materials[t]) or 0 end
	return b.gold or 0, mats
end

-- Common gate for every remote (SEC-001): right player, menu open, rate limit.
local function guard(player: Player, key: string): string?
	if _sessionPlayer and player ~= _sessionPlayer then return "Not your guild" end
	if not isOpen then return "The Guild menu is closed" end
	local now = os.clock()
	local rk = `{player.UserId}:{key}`
	if lastCallAt[rk] and now - lastCallAt[rk] < RATE_LIMIT_SECONDS then
		return "Too fast — try again"
	end
	lastCallAt[rk] = now
	return nil
end

local function fail(msg: string)
	return { ok = false, error = msg }
end

local function homeUnitCount(): number
	local n = 0
	for id in playerUnits() do
		if not DispatchService.IsUnitDispatched(_playerId, id) then n += 1 end
	end
	return n
end

--------------------------------------------------
-- PROVIDERS WIRED INTO THE SLICE 6 SERVICES (Main calls these Setters)
--------------------------------------------------

function GuildMenuService.GetBuildingLevel(name: string): number
	return buildingLevels[name] or DEFAULT_BUILDING_LEVEL
end

function GuildMenuService.TavernLevelProvider(_pid: string): number
	return GuildMenuService.GetBuildingLevel("Tavern")
end

function GuildMenuService.MerchantLevelProvider(_pid: string): number
	return GuildMenuService.GetBuildingLevel("Merchant")
end

function GuildMenuService.RosterProvider(_pid: string): { string }?
	if not _getPlayerUnits then return nil end -- nil = DispatchService skips its own check
	return sortedKeys(playerUnits())
end

-- DispatchService availability sink contract (DispatchService L121-124).
GuildMenuService.AvailabilitySink = {
	MarkUnavailable = function(_pid: string, unitId: string, untilBattle: number)
		awayUntil[unitId] = untilBattle
	end,
	MarkAvailable = function(_pid: string, unitId: string)
		awayUntil[unitId] = nil
	end,
	IsAvailable = function(pid: string, unitId: string): boolean
		return not DispatchService.IsUnitDispatched(pid, unitId)
	end,
}

-- BlacksmithService.SetItemPersist: an upgraded/downgraded item is the SAME
-- inventory instance, so the save already carries it; the holder's stats must be
-- rebuilt so the new level applies now (not next session).
function GuildMenuService.PersistItem(_pid: string, item: any)
	local holder = item and item.instanceId and holderOf(item.instanceId) or nil
	if holder then
		EquipmentService.RebuildUnitStats(holder)
	end
end

--------------------------------------------------
-- UNIT FACTORY (RecruitmentService.SetUnitFactory)
--
-- Builds a hired unit with the SAME building blocks Main uses for the starting
-- units: UnitSchema.Create -> generated MainHand weapon -> TraitRoller -> doctrine
-- skill -> RebuildUnitStats -> (RecruitmentService then calls RegisterNewUnit).
-- Race / doctrine / weapon are picked deterministically from the candidate seed.
--------------------------------------------------

local function buildName(rng: Random, unit: any, fallback: string): string
	-- Same naming scheme the enemy generator uses (UnitNameData).
	local perkId = unit.perkIds and unit.perkIds[1]
	local flawId = unit.drawbackIds and unit.drawbackIds[1]
	local function rank(id: string?): number
		if not id then return 0 end
		local def = (TraitData :: any)[id] or ((TraitData :: any).Traits and (TraitData :: any).Traits[id])
		local tier = def and def.tier
		return (tier and UnitNameData.TierRank[tier]) or 0
	end
	local chosen = flawId
	if rank(perkId) > rank(flawId) then chosen = perkId end
	local first = chosen and UnitNameData.FirstWords[chosen]
	local second = UnitNameData.DoctrineWords[unit.doctrineId]
	if not first or not second then return fallback end
	return `{first[rng:NextInteger(1, #first)]} {second[rng:NextInteger(1, #second)]}`
end

local function playableDoctrines(): { string }
	local list = {}
	for _, id in sortedKeys(DoctrineData :: any) do
		local d = (DoctrineData :: any)[id]
		local first = d and d.skillChoices and d.skillChoices[1]
		-- Only doctrines whose first skill the combat layer can actually resolve.
		if first and (not _isSkillRegistered or _isSkillRegistered(first)) then
			table.insert(list, id)
		end
	end
	return list
end

local function weaponArchetypes(): { string }
	local list = {}
	for id, def in WeaponData.Archetypes do
		if def.category == "Weapon" then table.insert(list, id) end
	end
	table.sort(list)
	return list
end

local function nextRecruitId(): string
	local units = playerUnits()
	repeat
		hireCounter += 1
	until not units[`unit_recruit_{hireCounter}`] and not recruitDefs[`unit_recruit_{hireCounter}`]
	return `unit_recruit_{hireCounter}`
end

function GuildMenuService.BuildRecruitUnit(candidate: any): any?
	if type(candidate) ~= "table" or type(candidate.level) ~= "number" then return nil end
	local rng = Random.new(math.floor(tonumber(candidate.seed) or 0) + 7919)
	local raceIds = RaceData.GetAllIds()
	local doctrines = playableDoctrines()
	if #raceIds == 0 or #doctrines == 0 then
		warn("[GuildMenuService] No race/doctrine available for a recruit")
		return nil
	end
	local raceId = raceIds[rng:NextInteger(1, #raceIds)]
	local doctrineId = doctrines[rng:NextInteger(1, #doctrines)]
	local level = math.clamp(math.floor(candidate.level), 1, ITEM_LEVEL_CAP)
	local unitId = nextRecruitId()

	local unit = UnitSchema.Create({
		id         = unitId,
		name       = `Recruit {hireCounter}`,
		level      = level,
		raceId     = raceId,
		side       = "Player",
		controller = "Player",
		tileX      = 0, -- set during deployment
		tileY      = 0,
		doctrineId = doctrineId,
	})
	TraitRoller.AssignIfEmpty(unit, rng)
	unit.name = buildName(rng, unit, unit.name)

	-- Starter weapon: Common, at the recruit's level (starting units also get one
	-- generated weapon each). Item goes into the shared inventory like theirs.
	local archetypes = weaponArchetypes()
	if #archetypes > 0 then
		local item = ItemGenerator.Generate({
			baseArchetypeId = archetypes[rng:NextInteger(1, #archetypes)],
			itemLevel       = level,
			rarity          = "Common",
			seed            = rng:NextInteger(1, 2147483646),
			sourceType      = "Recruit",
		})
		if item then
			InventoryService.AddItem(_playerId, item)
			EquipmentService.Equip(unit, item, "MainHand")
		else
			warn(`[GuildMenuService] Starter weapon generation failed for {unitId}`)
		end
	end

	-- Same per-unit setup Main.server.lua applies to the roster at session start.
	local doc = (DoctrineData :: any)[doctrineId]
	unit.selectedDoctrineSkill = doc and doc.skillChoices and doc.skillChoices[1] or nil
	unit.skillLoadout = { slot2 = nil, slot3 = nil, slot4 = nil }
	unit.skillIds = unit.selectedDoctrineSkill and { unit.selectedDoctrineSkill } or {}
	unit.records = {
		battlesParticipated = 0, victoriesParticipated = 0, enemiesDefeated = 0,
		totalDamageDealt = 0, totalHealingDone = 0, timesKO = 0,
		-- ProgressionService reads level/xp/raceId from the record; seed them so the
		-- recruit's XP bar and level-up stat recompute start from its real level.
		level = level, xp = 0, raceId = raceId,
	}
	unit.consumableSlots = {}
	unit.consumableSlotCount = 3
	unit.maxConsumableSlots = 6
	if raceHasTag(raceId, "Flying") then
		StatusService.ApplyStatus(unit, "Flight", "RaceTag")
	end
	EquipmentService.RebuildUnitStats(unit)
	unit.currentHp = unit.maxHp
	unit.currentMp = unit.maxMp
	unit.isRecruit = true
	unit.hireQuality = candidate.quality

	builtUnits[unitId] = unit
	print(`[GuildMenuService] Built recruit {unit.name} ({unitId}) L{level} {raceId} {doctrineId}`)
	return unit
end

--------------------------------------------------
-- NEXT-SESSION RESTORE of hired units
-- Called by Main right after the starting units are built, BEFORE the generic
-- roster loops (Flight, persistent HP/MP, doctrine, loadout, records), so those
-- loops treat recruits exactly like the starting units.
--------------------------------------------------

function GuildMenuService.RestoreRecruits(pid: string, savedEquipMap: any, savedRaceMap: any): { any }
	local restored = {}
	for _, unitId in recruitOrder do
		local def = recruitDefs[unitId]
		if def and PersistentStateService.GetUnitState(pid, unitId) then
			local unit = UnitSchema.Create({
				id = unitId, name = def.name, level = def.level, raceId = def.raceId,
				side = "Player", controller = "Player", tileX = 0, tileY = 0,
				doctrineId = def.doctrineId,
			})
			local savedRace = type(savedRaceMap) == "table" and savedRaceMap[unitId] or nil
			if savedRace then
				if savedRace.perkIds and #savedRace.perkIds > 0 then unit.perkIds = savedRace.perkIds end
				if savedRace.drawbackIds and #savedRace.drawbackIds > 0 then unit.drawbackIds = savedRace.drawbackIds end
			end
			-- Battle recruits keep exactly the traits they had (rule 133), even none:
			-- never re-roll them on load. Tavern hires keep the old roll-if-empty.
			if def.quality ~= "BattleRecruit" then
				TraitRoller.AssignIfEmpty(unit, Random.new(seedFromId(unitId)))
			end
			local slots = type(savedEquipMap) == "table" and savedEquipMap[unitId] or nil
			if type(slots) == "table" then
				for _, slot in EQUIP_SLOT_ORDER do
					local iid = slots[slot]
					local item = iid and InventoryService.GetItem(pid, iid) or nil
					if item then
						EquipmentService.Equip(unit, item, slot)
					elseif iid then
						warn(`[GuildMenuService] Saved {slot} item {iid} missing for {unitId}`)
					end
				end
			end
			EquipmentService.RebuildUnitStats(unit)
			unit.isRecruit = true
			unit.hireQuality = def.quality
			table.insert(restored, unit)
		elseif def then
			warn(`[GuildMenuService] Hired unit {unitId} has no saved roster state — skipped`)
		end
	end
	if #restored > 0 then
		print(`[GuildMenuService] Restored {#restored} hired unit(s) from save`)
	end
	return restored
end

--------------------------------------------------
-- BATTLE RECRUITS -> ROSTER (project_rules id 133, Locked; built 2026-10-07)
-- An enemy recruited in battle (CommandService sets target.recruited = true and
-- flips it to Neutral) that is STILL ALIVE at battle end is PURIFIED and joins
-- the roster: race, perks, drawbacks, doctrine (+ doctrine skill), level and base
-- stats are kept; equipped items and equipped skill cards are stripped (items are
-- destroyed, never added to inventory -- "recruiting does not grant free loot").
-- Base stats: UnitSchema.Create derives them from race + level, the same inputs
-- the enemy was built from, so rebuilding keeps them. The rule only says "still
-- alive at battle end", so this runs on win AND loss. Resources start full: the
-- roster path (PersistentStateService.RegisterNewUnit) registers new members at
-- full HP/MP, same as a Tavern hire. Recruits use the Tavern-hire save path
-- (recruitDefs/recruitOrder + RestoreRecruits) so they come back next session.
-- No roster capacity is wired today (RecruitmentService has no capacity provider
-- set), so none is enforced here.
--------------------------------------------------

function GuildMenuService.AdoptBattleRecruits(battleUnits: { any }): { any }
	local adopted = {}
	if type(battleUnits) ~= "table" then return adopted end
	for _, src in battleUnits do
		if type(src) == "table" and src.recruited == true and not src.adoptedToRoster then
			local alive = src.isAlive ~= false and (src.currentHp or 0) > 0
			if not alive then
				print(`[GuildMenuService] Recruit {tostring(src.name)} was KO'd at battle end — not added (rule 133)`)
			elseif type(src.raceId) ~= "string" then
				warn(`[GuildMenuService] Recruit {tostring(src.name)} has no race — not added`)
			else
				src.adoptedToRoster = true -- guard: never adopt the same unit twice
				local level = math.clamp(math.floor(src.level or 1), 1, ITEM_LEVEL_CAP)
				local unitId = nextRecruitId()
				local unit = UnitSchema.Create({
					id = unitId, name = src.name or unitId, level = level, raceId = src.raceId,
					side = "Player", controller = "Player", tileX = 0, tileY = 0,
					doctrineId = src.doctrineId,
					perkIds = src.perkIds and table.clone(src.perkIds) or nil,
					drawbackIds = src.drawbackIds and table.clone(src.drawbackIds) or nil,
				})
				-- Doctrine skill kept; equipped skill cards (slots 2-4) stripped.
				local docSkill = src.selectedDoctrineSkill
				if docSkill and _isSkillRegistered and not _isSkillRegistered(docSkill) then
					local doc = (DoctrineData :: any)[src.doctrineId]
					docSkill = doc and doc.skillChoices and doc.skillChoices[1] or nil
				end
				unit.selectedDoctrineSkill = docSkill
				unit.skillLoadout = { slot2 = nil, slot3 = nil, slot4 = nil }
				unit.skillIds = docSkill and { docSkill } or {}
				unit.records = {
					battlesParticipated = 0, victoriesParticipated = 0, enemiesDefeated = 0,
					totalDamageDealt = 0, totalHealingDone = 0, timesKO = 0,
					level = level, xp = 0, raceId = src.raceId,
				}
				unit.consumableSlots = {}
				unit.consumableSlotCount = 3
				unit.maxConsumableSlots = 6
				if raceHasTag(src.raceId, "Flying") then
					StatusService.ApplyStatus(unit, "Flight", "RaceTag")
				end
				EquipmentService.RebuildUnitStats(unit) -- no equipment: purified
				unit.currentHp = unit.maxHp
				unit.currentMp = unit.maxMp
				unit.isRecruit = true
				unit.hireQuality = "BattleRecruit"
				PersistentStateService.RegisterNewUnit(_playerId, unitId, unit.maxHp, unit.maxMp)
				if _addPlayerUnit then _addPlayerUnit(unit) end
				recruitDefs[unitId] = {
					name = unit.name, level = level, raceId = unit.raceId,
					doctrineId = unit.doctrineId, quality = "BattleRecruit",
				}
				table.insert(recruitOrder, unitId)
				table.insert(adopted, unit)
				print(`[GuildMenuService] Battle recruit {unit.name} joined the roster as {unitId} | L{level} {unit.raceId} {tostring(unit.doctrineId)} | purified (no items, no skill cards)`)
			end
		end
	end
	return adopted
end

--------------------------------------------------
-- SAVE (rides the existing progression payload — Key 3; no second store)
--------------------------------------------------

function GuildMenuService.Export(_pid: string)
	local units = playerUnits()
	local defs = {}
	for _, id in recruitOrder do
		local d = recruitDefs[id]
		local live = units[id]
		if d then
			defs[id] = {
				name = live and live.name or d.name,
				level = live and live.level or d.level,
				raceId = d.raceId,
				doctrineId = (live and live.doctrineId) or d.doctrineId,
				quality = d.quality,
			}
		end
	end
	return {
		battlesCompleted = battlesCompleted,
		hireCounter = hireCounter,
		recruitOrder = table.clone(recruitOrder),
		recruits = defs,
	}
end

function GuildMenuService.Import(_pid: string, data: any)
	if type(data) ~= "table" then return end
	battlesCompleted = math.max(0, math.floor(tonumber(data.battlesCompleted) or 0))
	hireCounter = math.max(0, math.floor(tonumber(data.hireCounter) or 0))
	recruitDefs, recruitOrder = {}, {}
	if type(data.recruitOrder) == "table" and type(data.recruits) == "table" then
		for _, id in data.recruitOrder do
			local d = data.recruits[id]
			if type(id) == "string" and type(d) == "table" and type(d.raceId) == "string" then
				recruitDefs[id] = {
					name = type(d.name) == "string" and d.name or id,
					level = math.clamp(math.floor(tonumber(d.level) or 1), 1, ITEM_LEVEL_CAP),
					raceId = d.raceId,
					doctrineId = type(d.doctrineId) == "string" and d.doctrineId or nil,
					quality = type(d.quality) == "string" and d.quality or "Standard",
				}
				table.insert(recruitOrder, id)
			end
		end
	end
	print(`[GuildMenuService] Imported | battles completed {battlesCompleted} | hired units {#recruitOrder}`)
end

function GuildMenuService.GetBattlesCompleted(): number
	return battlesCompleted
end

--------------------------------------------------
-- BATTLE ROSTER SYNC (Main calls once, right before deployment)
-- * adds units hired in the pre-battle menu
-- * removes units that are away on dispatch
-- * benches units beyond the deployment cap (deployment requires every listed
--   unit to be placed, so an over-cap roster would otherwise soft-lock)
-- Mutates allUnitsList IN PLACE (Main's closures hold that table).
--------------------------------------------------

local benchedThisBattle: { any } = {}

function GuildMenuService.SyncBattleRoster(allUnitsList: { any }, deployCap: number)
	-- 1) add pending hires after the last Player-side entry
	for _, unit in pendingBattleUnits do
		local present = false
		local lastPlayerIdx = 0
		for i, u in allUnitsList do
			if u == unit then present = true end
			if u.side == "Player" then lastPlayerIdx = i end
		end
		if not present then table.insert(allUnitsList, lastPlayerIdx + 1, unit) end
	end
	pendingBattleUnits = {}

	-- 2) remove dispatched units (iterate backwards)
	for i = #allUnitsList, 1, -1 do
		local u = allUnitsList[i]
		if u.side == "Player" and DispatchService.IsUnitDispatched(_playerId, u.id) then
			table.remove(allUnitsList, i)
			print(`[GuildMenuService] {u.name} is away on dispatch — not in this battle`)
		end
	end

	-- 3) bench beyond the cap (starting units first, then hires in hire order)
	benchedThisBattle = {}
	local cap = math.max(1, math.min(MAX_DEPLOY, math.floor(deployCap or MAX_DEPLOY)))
	local count = 0
	for i = 1, #allUnitsList do
		if allUnitsList[i].side == "Player" then count += 1 end
	end
	local i = #allUnitsList
	while count > cap and i >= 1 do
		local u = allUnitsList[i]
		if u.side == "Player" then
			table.remove(allUnitsList, i)
			table.insert(benchedThisBattle, u)
			count -= 1
			print(`[GuildMenuService] {u.name} benched (deployment cap {cap})`)
		end
		i -= 1
	end
end

-- Extra payload for the deployment screen: units shown greyed out ("Away"/"Bench").
function GuildMenuService.GetAwayUnitsForDeployment(): { any }
	local out = {}
	local units = playerUnits()
	for _, id in sortedKeys(units) do
		local u = units[id]
		if DispatchService.IsUnitDispatched(_playerId, id) then
			table.insert(out, { id = id, name = u.name, level = u.level, reason = "AWAY" })
		end
	end
	for _, u in benchedThisBattle do
		table.insert(out, { id = u.id, name = u.name, level = u.level, reason = "BENCH" })
	end
	return out
end

-- Post-battle "return to base" bookkeeping (game_flow id 20): count the battle
-- and resolve returning dispatches (XP via the wired sink, materials via Credit).
function GuildMenuService.OnBattleCompleted()
	battlesCompleted += 1
	local result = DispatchService.ResolveReturns(_playerId, battlesCompleted)
	-- Boards refresh per battle (dispatch/tavern); merchant per its own interval.
	tavernCache, dispatchCache = nil, nil
	print(`[GuildMenuService] Battle counted ({battlesCompleted} completed) | {#(result and result.returned or {})} unit(s) returned from dispatch`)
	return result
end

--------------------------------------------------
-- OPEN / CLOSE
--------------------------------------------------

function GuildMenuService.Open(phase: string)
	isOpen = true
	currentPhase = phase
	if _sessionPlayer then
		GuildEvents.GuildMenuOpened:FireClient(_sessionPlayer, { phase = phase })
	end
	print(`[GuildMenuService] Guild menu OPEN ({phase})`)
end

function GuildMenuService.Close()
	if not isOpen then return end
	isOpen = false
	if _sessionPlayer then
		GuildEvents.GuildMenuClosed:FireClient(_sessionPlayer, {})
	end
	print(`[GuildMenuService] Guild menu CLOSED ({tostring(currentPhase)})`)
end

--------------------------------------------------
-- QUERY BUILDERS
--------------------------------------------------

local function overview()
	local gold, mats = balance()
	local count = 0
	for _ in playerUnits() do count += 1 end
	return {
		ok = true,
		phase = currentPhase,
		gold = gold,
		materials = mats,
		buildings = table.clone(buildingLevels),
		battlesCompleted = battlesCompleted,
		rosterCount = count,
		isStudio = RunService:IsStudio(),
	}
end

local function tavernPool()
	if not tavernCache then
		local seed = 7001 + battlesCompleted * 97 + hireCounter * 13
		local res = RecruitmentService.GenerateRecruitPool(_playerId, seed, nil)
		tavernCache = { pool = res.pool or {}, reason = res.reason }
	end
	return tavernCache
end

local function merchantStock()
	local key = math.floor(battlesCompleted / MERCHANT_REFRESH_BATTLES)
	if not merchantCache or merchantCache.key ~= key then
		local res = MerchantService.GetStock(_playerId, mapLevel(), battlesCompleted)
		merchantCache = { key = key, res = res }
	end
	return merchantCache.res
end

local function dispatchBoard()
	if not dispatchCache then
		local res = DispatchService.OfferMissions(_playerId, mapLevel(), 5003 + battlesCompleted * 31)
		dispatchCache = { missions = res.missions or {} }
	end
	return dispatchCache
end

local function blacksmithGate(item: any): (boolean, string?)
	local bLevel = GuildMenuService.GetBuildingLevel("Blacksmith")
	local maxLevel = math.min(ITEM_LEVEL_CAP, bLevel * 10)
	if bLevel >= BUILDING_MAX_LEVEL then maxLevel = ITEM_LEVEL_CAP end
	if item.itemLevel + 1 > maxLevel then
		return false, `Blacksmith L{bLevel} upgrades items up to L{maxLevel}`
	end
	local need = BLACKSMITH_RARITY_LEVEL[item.rarityId]
	if not need then return false, `{tostring(item.rarityId)} items cannot be upgraded` end
	if bLevel < need then return false, `{item.rarityId} upgrades need Blacksmith L{need}` end
	return true, nil
end

local function describeItem(item: any)
	local holder = holderOf(item.instanceId)
	return {
		instanceId = item.instanceId,
		name = itemDisplayName(item),
		level = item.itemLevel,
		rarity = item.rarityId,
		equippedBy = holder and holder.name or nil,
	}
end

--------------------------------------------------
-- REMOTE HANDLERS
--------------------------------------------------

local function onGetOverview(player: Player)
	if _sessionPlayer and player ~= _sessionPlayer then return fail("Not your guild") end
	return overview()
end

local function onGetTavernPool(player: Player)
	local g = guard(player, "tavern") if g then return fail(g) end
	local cache = tavernPool()
	local list = {}
	for _, c in cache.pool do
		table.insert(list, { candidateId = c.candidateId, level = c.level, quality = c.quality, cost = c.cost })
	end
	return { ok = true, pool = list, reason = cache.reason, tavernLevel = GuildMenuService.GetBuildingLevel("Tavern") }
end

local function onRequestHire(player: Player, candidateId: any)
	local g = guard(player, "hire") if g then return fail(g) end
	if type(candidateId) ~= "string" or #candidateId > 64 then return fail("Invalid recruit") end
	local cache = tavernPool()
	local idx, candidate = nil, nil
	for i, c in cache.pool do
		if c.candidateId == candidateId then idx, candidate = i, c break end
	end
	if not candidate then return fail("That recruit is no longer available") end

	local ok, result = RecruitmentService.CommitHire(_playerId, candidate)
	if not ok then return fail(tostring(result)) end
	local unitId = result.unitId
	local unit = builtUnits[unitId]
	builtUnits[unitId] = nil
	if not unit then return fail("Hire recorded but unit missing — check Output") end

	if _addPlayerUnit then _addPlayerUnit(unit) end
	recruitDefs[unitId] = {
		name = unit.name, level = unit.level, raceId = unit.raceId,
		doctrineId = unit.doctrineId, quality = candidate.quality,
	}
	table.insert(recruitOrder, unitId)
	if currentPhase == "PreBattle" then table.insert(pendingBattleUnits, unit) end
	table.remove(cache.pool, idx)
	save()
	local gold = balance()
	return { ok = true, unitName = unit.name, cost = result.cost, gold = gold }
end

local function onGetMerchantStock(player: Player)
	local g = guard(player, "merchant") if g then return fail(g) end
	local res = merchantStock()
	local stock = {}
	for i, offer in res.stock or {} do
		table.insert(stock, {
			offerIndex = i, name = itemDisplayName(offer.item), level = offer.itemLevel,
			rarity = offer.rarity, price = offer.buyPrice,
		})
	end
	local sellable = {}
	for _, item in InventoryService.GetAllItems(_playerId) do
		if not holderOf(item.instanceId) then
			local d = describeItem(item)
			d.price = MerchantService.PriceToSell(item)
			table.insert(sellable, d)
		end
	end
	table.sort(sellable, function(a, b) return a.name < b.name end)
	return { ok = true, stock = stock, sellable = sellable, reason = res.reason,
		merchantLevel = GuildMenuService.GetBuildingLevel("Merchant") }
end

local function onRequestBuy(player: Player, offerIndex: any)
	local g = guard(player, "buy") if g then return fail(g) end
	if type(offerIndex) ~= "number" or offerIndex ~= offerIndex or offerIndex % 1 ~= 0 then
		return fail("Invalid offer")
	end
	local res = merchantStock()
	if offerIndex < 1 or offerIndex > #(res.stock or {}) then return fail("Invalid offer") end
	local ok, result = MerchantService.BuyItem(_playerId, offerIndex, mapLevel(), battlesCompleted)
	if not ok then return fail(tostring(result)) end
	save()
	return { ok = true, name = itemDisplayName(result.item), price = result.price, gold = (balance()) }
end

local function onRequestSell(player: Player, instanceId: any)
	local g = guard(player, "sell") if g then return fail(g) end
	if type(instanceId) ~= "string" or #instanceId > 80 then return fail("Invalid item") end
	if not InventoryService.OwnsItem(_playerId, instanceId) then return fail("Item not owned") end
	if holderOf(instanceId) then return fail("Unequip that item before selling it") end
	local ok, result = MerchantService.SellItem(_playerId, instanceId)
	if not ok then return fail(tostring(result)) end
	save()
	return { ok = true, payout = result.payout, gold = (balance()) }
end

local function onGetBlacksmithItems(player: Player)
	local g = guard(player, "smith") if g then return fail(g) end
	local items = {}
	for _, item in InventoryService.GetAllItems(_playerId) do
		if type(item.itemLevel) == "number" then
			local d = describeItem(item)
			local allowed, why = blacksmithGate(item)
			local cost = BlacksmithService.ResolveUpgradeCost(item, item.itemLevel + 1)
			d.canUpgrade = allowed and cost ~= nil
			d.upgradeBlockedReason = why
			d.upgradeGold = cost and cost.gold or nil
			if cost then
				local mats = {}
				for tier, qty in cost.materials do table.insert(mats, { tier = tier, qty = qty }) end
				d.upgradeMaterials = mats
			end
			d.canDowngrade = item.itemLevel > 1
			table.insert(items, d)
		end
	end
	table.sort(items, function(a, b)
		if (a.equippedBy ~= nil) ~= (b.equippedBy ~= nil) then return a.equippedBy ~= nil end
		return a.name < b.name
	end)
	local gold, mats = balance()
	return { ok = true, items = items, gold = gold, materials = mats,
		blacksmithLevel = GuildMenuService.GetBuildingLevel("Blacksmith") }
end

local function ownedItem(instanceId: any): (any?, string?)
	if type(instanceId) ~= "string" or #instanceId > 80 then return nil, "Invalid item" end
	local item = InventoryService.GetItem(_playerId, instanceId)
	if not item then return nil, "Item not owned" end
	return item, nil
end

local function onRequestUpgrade(player: Player, instanceId: any)
	local g = guard(player, "upgrade") if g then return fail(g) end
	local item, err = ownedItem(instanceId)
	if not item then return fail(err or "Invalid item") end
	local allowed, why = blacksmithGate(item)
	if not allowed then return fail(why or "Not allowed") end
	local ok, result = BlacksmithService.CommitUpgrade(_playerId, item, item.itemLevel + 1)
	if not ok then return fail(tostring(result)) end
	save()
	return { ok = true, toLevel = result.toLevel, gold = (balance()) }
end

local function onRequestDowngrade(player: Player, instanceId: any)
	local g = guard(player, "downgrade") if g then return fail(g) end
	local item, err = ownedItem(instanceId)
	if not item then return fail(err or "Invalid item") end
	local ok, result = BlacksmithService.CommitDowngrade(_playerId, item, item.itemLevel - 1)
	if not ok then return fail(tostring(result)) end
	save()
	return { ok = true, toLevel = result.toLevel }
end

local function onGetDispatchBoard(player: Player)
	local g = guard(player, "dispatch") if g then return fail(g) end
	local board = dispatchBoard()
	local missions = {}
	for _, m in board.missions do
		table.insert(missions, {
			missionId = m.missionId, tier = m.tier, duration = m.duration, xp = m.xp,
			rewardTier = m.rewardTier, rewardCount = m.rewardCount,
		})
	end
	local units = {}
	local live = playerUnits()
	for _, id in sortedKeys(live) do
		local away = DispatchService.IsUnitDispatched(_playerId, id)
		table.insert(units, { id = id, name = live[id].name, level = live[id].level,
			away = away, returnBattle = awayUntil[id] })
	end
	return { ok = true, missions = missions, units = units, battlesCompleted = battlesCompleted }
end

local function onRequestDispatch(player: Player, missionId: any, unitIds: any)
	local g = guard(player, "send") if g then return fail(g) end
	if type(missionId) ~= "string" or #missionId > 64 then return fail("Invalid mission") end
	if type(unitIds) ~= "table" or #unitIds < 1 or #unitIds > MAX_DISPATCH_PICK then
		return fail("Pick 1 to 7 units")
	end
	local live = playerUnits()
	local seen = {}
	local clean = {}
	for _, id in unitIds do
		if type(id) ~= "string" or seen[id] then return fail("Invalid unit selection") end
		if not live[id] then return fail("That unit is not on your roster") end
		if DispatchService.IsUnitDispatched(_playerId, id) then return fail(`{live[id].name} is already away`) end
		seen[id] = true
		table.insert(clean, id)
	end
	-- Keep at least one unit home so the next battle can be fought.
	if homeUnitCount() - #clean < 1 then return fail("Keep at least one unit at home") end
	local board = dispatchBoard()
	local mIdx = nil
	for i, m in board.missions do if m.missionId == missionId then mIdx = i break end end
	if not mIdx then return fail("That mission is no longer offered") end

	local ok, result = DispatchService.SendUnits(_playerId, missionId, clean, battlesCompleted)
	if not ok then return fail(tostring(result)) end
	table.remove(board.missions, mIdx)
	save()
	return { ok = true, returnBattle = result.returnBattle, xpEach = result.xpEach }
end

local function onGetGuildUnits(player: Player)
	local g = guard(player, "units") if g then return fail(g) end
	local live = playerUnits()
	local list = {}
	for _, id in sortedKeys(live) do
		local u = live[id]
		local prog = ProgressionService.GetUnitLevelProgress(_playerId, id)
		local race = u.raceId and RaceData.GetRace(u.raceId) or nil
		local doc = u.doctrineId and (DoctrineData :: any)[u.doctrineId] or nil
		table.insert(list, {
			id = id,
			name = u.name,
			unitLevel = u.level,
			xpLevel = prog.level,
			xp = prog.xp,
			xpToNext = prog.xpToNext,
			atCap = prog.atCap,
			race = race and race.name or "?",
			doctrine = doc and doc.name or "?",
			hp = u.currentHp, maxHp = u.maxHp,
			away = DispatchService.IsUnitDispatched(_playerId, id),
			returnBattle = awayUntil[id],
			isRecruit = u.isRecruit == true,
		})
	end
	return { ok = true, units = list, battlesCompleted = battlesCompleted }
end

--------------------------------------------------
-- INIT (Main calls once, after playerUnits and doSave exist)
--------------------------------------------------

function GuildMenuService.Init(deps: any)
	_playerId = deps.playerId or _playerId
	_sessionPlayer = deps.sessionPlayer
	_getPlayerUnits = deps.getPlayerUnits
	_addPlayerUnit = deps.addPlayerUnit
	_doSave = deps.doSave
	_getMapLevel = deps.getMapLevel
	_isSkillRegistered = deps.isSkillRegistered

	GuildEvents.GetGuildOverview.OnServerInvoke = onGetOverview
	GuildEvents.GetTavernPool.OnServerInvoke = onGetTavernPool
	GuildEvents.RequestHire.OnServerInvoke = onRequestHire
	GuildEvents.GetMerchantStock.OnServerInvoke = onGetMerchantStock
	GuildEvents.RequestBuy.OnServerInvoke = onRequestBuy
	GuildEvents.RequestSell.OnServerInvoke = onRequestSell
	GuildEvents.GetBlacksmithItems.OnServerInvoke = onGetBlacksmithItems
	GuildEvents.RequestUpgrade.OnServerInvoke = onRequestUpgrade
	GuildEvents.RequestDowngrade.OnServerInvoke = onRequestDowngrade
	GuildEvents.GetDispatchBoard.OnServerInvoke = onGetDispatchBoard
	GuildEvents.RequestDispatch.OnServerInvoke = onRequestDispatch
	GuildEvents.GetGuildUnits.OnServerInvoke = onGetGuildUnits

	-- Dev "set building level" (Studio only) on the EXISTING DevCommand remote.
	if RunService:IsStudio() then
		BattleEvents.DevCommand.OnServerEvent:Connect(function(player: Player, cmd: any)
			if type(cmd) ~= "table" or cmd.action ~= "SetBuildingLevel" then return end
			if _sessionPlayer and player ~= _sessionPlayer then return end
			local name, level = cmd.building, cmd.level
			if type(name) ~= "string" or buildingLevels[name] == nil then return end
			if type(level) ~= "number" or level % 1 ~= 0 then return end
			buildingLevels[name] = math.clamp(level, BUILDING_MIN_LEVEL, BUILDING_MAX_LEVEL)
			tavernCache, merchantCache = nil, nil -- pool size / stock depend on level
			print(`[Dev] Building {name} set to L{buildingLevels[name]} (temporary, not saved)`)
		end)
	end
	print(`[GuildMenuService] Initialized | buildings at L{DEFAULT_BUILDING_LEVEL} | battles completed {battlesCompleted}`)
end

return GuildMenuService
