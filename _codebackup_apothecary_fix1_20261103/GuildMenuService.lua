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
local PartyService           = require(Game:WaitForChild("PartyService"))
local CurrencyService        = require(Game:WaitForChild("CurrencyService"))
local RecruitmentService     = require(Game:WaitForChild("RecruitmentService"))
local MerchantService        = require(Game:WaitForChild("MerchantService"))
local BlacksmithService      = require(Game:WaitForChild("BlacksmithService"))
local RuneforgeService       = require(Game:WaitForChild("RuneforgeService"))
local CrucibleService        = require(Game:WaitForChild("CrucibleService")) -- gear merging (2026-11-02)
local ApothecaryService      = require(Game:WaitForChild("ApothecaryService")) -- consumables (2026-11-03)
local DispatchService        = require(Game:WaitForChild("DispatchService"))
local ProgressionService     = require(Game:WaitForChild("ProgressionService"))
-- Item -> UI detail entry (same builder as Loadout/inspector) for the Merchant inspector (2026-10-31).
local ItemDisplay            = require(Game:WaitForChild("ItemDisplay"))

local RaceData     = require(Content:WaitForChild("RaceData"))
local DoctrineData = require(Content:WaitForChild("DoctrineData"))
local WeaponData   = require(Content:WaitForChild("WeaponData"))
local ArmorData    = require(Content:WaitForChild("ArmorData"))
local UnitNameData = require(Content:WaitForChild("UnitNameData"))
local TraitData    = require(Content:WaitForChild("TraitData"))
local PortraitData = require(Content:WaitForChild("PortraitData"))

local GuildMenuService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

-- TEMPORARY building levels (user decision 2026-10-07: every building = level 1
-- until Slice 8 builds real facility purchasing). ONE table, Dev-adjustable.
local DEFAULT_BUILDING_LEVEL = 1
local BUILDING_MIN_LEVEL, BUILDING_MAX_LEVEL = 1, 10 -- guild_facilities: Max Level 10
local BUILDING_NAMES = table.freeze({ "GuildHall", "Tavern", "Merchant", "Blacksmith", "Runeforge", "Crucible", "Apothecary" })
-- guild_facilities 46: the Runeforge unlocks at Guild Hall L4 and can never be above the
-- Guild Hall level. Its building level is Dev-adjustable until Slice 8 facility purchasing.
local RUNEFORGE_UNLOCK_GUILD_HALL = 4
-- Crucible (gear merging, USER DECISION 2026-11-02): unlocks at Guild Hall L5, never above it.
local CRUCIBLE_UNLOCK_GUILD_HALL = 5
-- Apothecary (USER DECISION 2026-11-03, replaces the Workshop): unlocks at Guild Hall L4, never above it.
local APOTHECARY_UNLOCK_GUILD_HALL = 4

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
	Common = 1, Uncommon = 1, Rare = 3, Epic = 5, Exalted = 6, Legendary = 7, Mythic = 9,
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
-- Dev "Refresh all shops" counter (Studio tool, 2026-10-31). Mixed into the Merchant, Tavern
-- and Dispatch seeds so a refresh gives new offers; saved so the refresh survives a restart.
local devShopNonce = 0
local DEV_NONCE_MAX = 1000000
-- Hired Tavern recruits of the CURRENT pool (2026-10-31, user decision). The pool seed no
-- longer includes the hire counter (hire + restart used to give a whole new list = a free
-- reroll); hired candidates are remembered instead and stay gone until the pool refreshes.
-- Saved as guildMenu.tavernHired = { seed, ids = { candidateId } }.
local tavernHired: { seed: number, ids: { [string]: boolean } }? = nil
local MAX_TAVERN_HIRED_SAVE = 20 -- load bound (pool size is at most 10)
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

local _dirty = false
local function save()
	if _doSave then _doSave() end
	_dirty = false
end
local function markDirty()
	-- SMARTER SAVE (2026-10-13): per-action saves caused a ~2s clunk after every guild
	-- action. Live actions mark the session dirty; the real write happens once when the
	-- menu closes (see GuildMenuService.Close).
	_dirty = true
end

-- Save-on-quit (2026-10-31, user decision): Main calls this when the player leaves or
-- the server shuts down. Writes only when there are unsaved guild-base changes.
-- Returns true if a save was made.
function GuildMenuService.SaveIfDirty(reason: string): boolean
	if not _dirty then return false end
	print(`[GuildMenuService] Saving unsaved guild changes ({reason})`)
	save()
	return true
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

-- Gold + resource counters for the client (v2 2026-11-01: mercury, crystals, sulfur).
local function balance()
	local b = CurrencyService.GetBalance(_playerId)
	return b.gold or 0, { mercury = b.mercury or 0, crystals = b.crystals or 0, sulfur = b.sulfur or 0 }
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

local function fail(msg: string): any
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

-- Effective Crucible level: 0 until Guild Hall L5, never above the Guild Hall level (2026-11-02).
function GuildMenuService.GetCrucibleLevel(): number
	local gh = buildingLevels.GuildHall or DEFAULT_BUILDING_LEVEL
	if gh < CRUCIBLE_UNLOCK_GUILD_HALL then return 0 end
	return math.min(buildingLevels.Crucible or DEFAULT_BUILDING_LEVEL, gh)
end

-- Highest level a merged item may reach: the current map level (the same level the Merchant
-- shelf and loot use; there is no separate "highest unlocked map level" yet).
function GuildMenuService.CrucibleLevelCap(): number
	return mapLevel()
end

-- Crucible inputs may not be equipped (this also covers units out on dispatch: their gear is
-- equipped), so BUG-050 / keep-a-weapon stay safe. Nil = allowed.
function GuildMenuService.CrucibleBlockedReason(item: any): string?
	local holder = item and item.instanceId and holderOf(item.instanceId) or nil
	if holder then return `Equipped by {holder.name}` end
	return nil
end

-- Effective Runeforge level: 0 until Guild Hall L4, never above the Guild Hall level (gf 46).
function GuildMenuService.GetRuneforgeLevel(): number
	local gh = buildingLevels.GuildHall or DEFAULT_BUILDING_LEVEL
	if gh < RUNEFORGE_UNLOCK_GUILD_HALL then return 0 end
	return math.min(buildingLevels.Runeforge or DEFAULT_BUILDING_LEVEL, gh)
end

-- Effective Apothecary level: 0 until Guild Hall L4, never above the Guild Hall level (gf 67).
function GuildMenuService.GetApothecaryLevel(): number
	local gh = buildingLevels.GuildHall or DEFAULT_BUILDING_LEVEL
	if gh < APOTHECARY_UNLOCK_GUILD_HALL then return 0 end
	return math.min(buildingLevels.Apothecary or DEFAULT_BUILDING_LEVEL, gh)
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

-- Everything about a recruit that its candidate seed decides: race, doctrine, perk + flaw,
-- name, starter weapon type + seed, portrait. Pure: no ids, items or state. The hire
-- (BuildRecruitUnit) and the Tavern preview (previewRecruit) BOTH use it, so the recruit
-- shown in the Tavern is exactly the recruit you get (user decision 2026-10-31). The rng
-- order matches the hire code it replaced.
local function rollRecruit(candidate: any): any?
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
	local perkId, flawId = TraitRoller.RollPair(rng)
	local name = buildName(rng, { perkIds = { perkId }, drawbackIds = { flawId }, doctrineId = doctrineId }, "")
	local archetypes = weaponArchetypes()
	local weaponArchetypeId: string? = nil
	local weaponSeed: number? = nil
	if #archetypes > 0 then
		weaponArchetypeId = archetypes[rng:NextInteger(1, #archetypes)]
		weaponSeed = rng:NextInteger(1, 2147483646)
	end
	return {
		level = math.clamp(math.floor(candidate.level), 1, ITEM_LEVEL_CAP),
		raceId = raceId,
		doctrineId = doctrineId,
		perkId = perkId,
		flawId = flawId,
		name = if name ~= "" then name else nil,
		weaponArchetypeId = weaponArchetypeId,
		weaponSeed = weaponSeed,
		portraitAssetId = PortraitData.PickRandom(rng, raceId),
	}
end

-- Per-unit setup shared by the hire and the preview (same as the starting units get), ending
-- with the stat rebuild. The weapon is already in the MainHand when this runs.
local function finishRecruitSetup(unit: any, r: any)
	local doc = (DoctrineData :: any)[r.doctrineId]
	unit.selectedDoctrineSkill = doc and doc.skillChoices and doc.skillChoices[1] or nil
	unit.skillLoadout = { slot2 = nil, slot3 = nil, slot4 = nil }
	unit.skillIds = unit.selectedDoctrineSkill and { unit.selectedDoctrineSkill } or {}
	unit.records = {
		battlesParticipated = 0, victoriesParticipated = 0, enemiesDefeated = 0,
		totalDamageDealt = 0, totalHealingDone = 0, timesKO = 0,
		-- ProgressionService reads level/xp/raceId from the record; seed them so the
		-- recruit's XP bar and level-up stat recompute start from its real level.
		level = r.level, xp = 0, raceId = r.raceId,
	}
	unit.consumableSlots = {}
	unit.consumableSlotCount = 3
	unit.maxConsumableSlots = 6
	if raceHasTag(r.raceId, "Flying") then
		StatusService.ApplyStatus(unit, "Flight", "RaceTag")
	end
	EquipmentService.RebuildUnitStats(unit)
end

-- Tavern inspector preview (2026-10-31): the recruit's permanent parts (race, perk, flaw),
-- its doctrine and its primary stats, computed on a throwaway unit with the same setup as
-- the hire. The starter weapon is a stand-in: Common items roll no bonus lines or passives
-- (ItemGenerator early exit), so the stats match the real weapon without creating an item.
local function previewRecruit(candidate: any): any?
	local r = rollRecruit(candidate)
	if not r then return nil end
	local unit = UnitSchema.Create({
		id         = `preview_{tostring(candidate.candidateId)}`,
		name       = r.name or "Recruit",
		level      = r.level,
		raceId     = r.raceId,
		side       = "Player",
		controller = "Player",
		tileX      = 0,
		tileY      = 0,
		doctrineId = r.doctrineId,
	})
	unit.perkIds = { r.perkId }
	unit.drawbackIds = { r.flawId }
	if r.weaponArchetypeId then
		local standIn = {
			instanceId = "preview", baseArchetypeId = r.weaponArchetypeId, itemLevel = r.level,
			rarityId = "Common", bonusLines = {}, bonusPassiveIds = {},
		}
		-- Same check Equip runs; an invalid weapon is left off, as it would be on a real hire.
		if EquipmentService.ValidateEquip(unit, standIn, "MainHand") then
			unit.equipmentSlots = unit.equipmentSlots or {}
			unit.equipmentSlots.MainHand = standIn
		end
	end
	finishRecruitSetup(unit, r)
	local race = RaceData.GetRace(r.raceId)
	local doc = (DoctrineData :: any)[r.doctrineId]
	local perk = r.perkId and TraitData.GetTrait(r.perkId) or nil
	local flaw = r.flawId and TraitData.GetTrait(r.flawId) or nil
	local es = unit.effectiveStats or {}
	return {
		name = r.name or "Recruit",
		portraitAssetId = r.portraitAssetId,
		raceName = race and race.name or r.raceId,
		racePassiveName = race and race.passiveName or nil,
		racePassiveEffect = race and race.passiveEffect or nil,
		perkName = perk and perk.name or nil,
		perkEffect = perk and perk.effect or nil,
		flawName = flaw and flaw.name or nil,
		flawEffect = flaw and flaw.effect or nil,
		doctrineName = doc and doc.name or r.doctrineId,
		doctrinePassiveName = doc and doc.passiveName or nil,
		doctrinePassiveEffect = doc and doc.passiveEffect or nil,
		stats = { STR = es.STR, AGI = es.AGI, INT = es.INT, VIT = es.VIT, DEX = es.DEX, LUK = es.LUK },
	}
end

function GuildMenuService.BuildRecruitUnit(candidate: any): any?
	local r = rollRecruit(candidate)
	if not r then return nil end
	local raceId = r.raceId
	local doctrineId = r.doctrineId
	local level = r.level
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
	unit.perkIds = { r.perkId }
	unit.drawbackIds = { r.flawId }
	unit.name = r.name or unit.name

	-- Starter weapon: Common, at the recruit's level (starting units also get one
	-- generated weapon each). Item goes into the shared inventory like theirs.
	if r.weaponArchetypeId then
		local item = ItemGenerator.Generate({
			baseArchetypeId = r.weaponArchetypeId,
			itemLevel       = level,
			rarity          = "Common",
			seed            = r.weaponSeed,
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
	finishRecruitSetup(unit, r)
	unit.currentHp = unit.maxHp
	unit.currentMp = unit.maxMp
	unit.isRecruit = true
	unit.hireQuality = candidate.quality
	-- Hired recruits get a random race-matched default portrait (same rule as the
	-- player starters). Deterministic from the candidate roll; persists via SaveService;
	-- a loadout pick overrides it later. (2026-10-15)
	unit.portraitAssetId = r.portraitAssetId
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
				-- Restore the saved portrait (hired default, battle-recruit enemy face, or a
				-- loadout pick) so it stays stable across logins. (2026-10-15)
				if savedRace.portraitAssetId then unit.portraitAssetId = savedRace.portraitAssetId end
			end
			-- Old saves (pre-portrait) or any gap: give the recruit a random race-matched
			-- face rather than letting it fall back to initials. Never overrides a restored one.
			if not unit.portraitAssetId then
				unit.portraitAssetId = PortraitData.PickRandom(Random.new(seedFromId(unitId) + 4242), unit.raceId)
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
				-- Battle recruits KEEP the face they wore as an enemy (user rule 2026-10-15):
				-- carry the enemy's portrait onto the adopted unit so it never resets to initials.
				unit.portraitAssetId = src.portraitAssetId
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
		buildings = table.clone(buildingLevels), -- facility levels carry over (2026-10-31)
		apothecary = ApothecaryService.Export(), -- auto-refill switch + bought shelf slots (2026-11-03)
		-- Bought Merchant shelf slots stay bought after a restart / rejoin (2026-10-31).
		merchantBought = MerchantService.ExportPurchases(_pid),
		devShopRefresh = devShopNonce, -- dev "Refresh all shops" survives a restart (2026-10-31)
		tavernHired = (function(): any?
			-- Hired recruits of the current pool stay gone after a restart (2026-10-31).
			if not tavernHired then return nil end
			local ids: { string } = {}
			for id in tavernHired.ids do table.insert(ids, id) end
			if #ids == 0 then return nil end
			table.sort(ids)
			return { seed = tavernHired.seed, ids = ids }
		end)(),
	}
end

function GuildMenuService.Import(_pid: string, data: any)
	if type(data) ~= "table" then return end
	battlesCompleted = math.max(0, math.floor(tonumber(data.battlesCompleted) or 0))
	hireCounter = math.max(0, math.floor(tonumber(data.hireCounter) or 0))
	devShopNonce = math.clamp(math.floor(tonumber(data.devShopRefresh) or 0), 0, DEV_NONCE_MAX)
	-- Hired recruits of the saved pool (2026-10-31). Bad data is ignored; old saves = none.
	tavernHired = nil
	local th = data.tavernHired
	if type(th) == "table" and type(th.seed) == "number" and th.seed % 1 == 0 and type(th.ids) == "table" then
		local ids: { [string]: boolean } = {}
		local count = 0
		for _, id in th.ids do
			if count >= MAX_TAVERN_HIRED_SAVE then break end
			if type(id) == "string" and #id > 0 and #id <= 64 and not ids[id] then
				ids[id] = true
				count += 1
			end
		end
		tavernHired = { seed = th.seed, ids = ids }
	end
	-- Facility levels (2026-10-31). Saves from before this keep the defaults (L1).
	-- Unknown buildings and bad values are ignored; levels clamp to 1..10.
	if type(data.buildings) == "table" then
		for _, b in BUILDING_NAMES do
			local lvl = tonumber(data.buildings[b])
			if lvl then
				buildingLevels[b] = math.clamp(math.floor(lvl), BUILDING_MIN_LEVEL, BUILDING_MAX_LEVEL)
			end
		end
	end
	tavernCache, merchantCache = nil, nil -- pool size / stock depend on building level
	MerchantService.ImportPurchases(_pid, data.merchantBought) -- nil on older saves = none bought
	ApothecaryService.Import(data.apothecary) -- nil on older saves = switch on, nothing bought
	recruitDefs, recruitOrder = {}, {}
	if type(data.recruitOrder) == "table" and type(data.recruits) == "table" then
		for _, id in data.recruitOrder do
			local d = data.recruits[id]
			if type(id) == "string" and type(d) == "table" and type(d.raceId) == "string" then
				-- Race renames (2026-10-09): a saved recruit may carry a legacy race ID.
				local raceId, converted = RaceData.Resolve(d.raceId)
				if converted then
					warn(`[GuildMenuService] converted legacy race id {d.raceId} -> {raceId} (recruit {id})`)
				end
				recruitDefs[id] = {
					name = type(d.name) == "string" and d.name or id,
					level = math.clamp(math.floor(tonumber(d.level) or 1), 1, ITEM_LEVEL_CAP),
					raceId = raceId or d.raceId,
					doctrineId = type(d.doctrineId) == "string" and d.doctrineId or nil,
					quality = type(d.quality) == "string" and d.quality or "Standard",
				}
				table.insert(recruitOrder, id)
			end
		end
	end
	print(`[GuildMenuService] Imported | battles completed {battlesCompleted} | hired units {#recruitOrder} | GuildHall L{buildingLevels.GuildHall} Tavern L{buildingLevels.Tavern} Merchant L{buildingLevels.Merchant} Blacksmith L{buildingLevels.Blacksmith}`)
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

function GuildMenuService.SyncBattleRoster(allUnitsList: { any }, deployCap: number, partyMembers: { string }?)
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

	-- 2.5) restrict to the CHOSEN PARTY (2026-10-15, game_flow id 10/27): if a party
	-- member set is supplied, drop Player units NOT in it BEFORE the deploy-cap bench, so
	-- the per-quest cap applies to the party. An empty/absent set means no restriction
	-- (full roster) -- so an empty party can never soft-lock deployment.
	if type(partyMembers) == "table" and #partyMembers > 0 then
		local inParty = {}
		for _, id in ipairs(partyMembers) do inParty[id] = true end
		for i = #allUnitsList, 1, -1 do
			local u = allUnitsList[i]
			if u.side == "Player" and not inParty[u.id] then
				table.remove(allUnitsList, i)
			end
		end
	end

	-- 3) bench beyond the cap, from the END of the list. List order is: starting units
	--     first, then the rest in id-sorted order per the Stage 2 roster snapshot (2026-10-19).
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
-- daysElapsed (2026-10-16): the number of DISPATCH DAYS this battle was worth
-- (Main computes ceil(elapsed CT / 4000), min 1). Dispatch now counts down in days, not
-- battle count; forwarded to ResolveReturns. Defaults to 1 if a caller omits it.
function GuildMenuService.OnBattleCompleted(daysElapsed: number?)
	battlesCompleted += 1
	local result = DispatchService.ResolveReturns(_playerId, daysElapsed or 1)
	-- Boards refresh per battle (dispatch/tavern); merchant per its own interval.
	tavernCache, dispatchCache = nil, nil
	print(`[GuildMenuService] Battle counted ({battlesCompleted} completed) | {#(result and result.returned or {})} unit(s) returned from dispatch`)
	return result
end

--------------------------------------------------
-- OPEN / CLOSE
--------------------------------------------------

-- Set the session player ONCE at boot so Open()/Close() can FireClient even on the
-- first guild-base landing, which runs before the per-round Init() (fixes blank-screen
-- when Open("Base") fired with _sessionPlayer still nil). 2026-10-13.
function GuildMenuService.SetSessionPlayer(player: Player)
	_sessionPlayer = player
end

function GuildMenuService.Open(phase: string, extra: { [string]: any }?)
	isOpen = true
	currentPhase = phase
	if _sessionPlayer then
		local payload: { [string]: any } = { phase = phase }
		if type(extra) == "table" then
			for k, v in extra do payload[k] = v end
		end
		GuildEvents.GuildMenuOpened:FireClient(_sessionPlayer, payload)
	end
	print(`[GuildMenuService] Guild menu OPEN ({phase})`)
end

function GuildMenuService.Close()
	if not isOpen then return end
	isOpen = false
	if _dirty then save() end  -- SMARTER SAVE: one write when the menu closes
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
		resources = mats,
		buildings = table.clone(buildingLevels),
		battlesCompleted = battlesCompleted,
		rosterCount = count,
		isStudio = RunService:IsStudio(),
	}
end

local function tavernPool()
	if not tavernCache then
		-- No hire counter in the seed (2026-10-31): hiring no longer rerolls the list on the
		-- next restart. Hired recruits of this pool are skipped instead (tavernHired).
		local seed = 7001 + battlesCompleted * 97 + devShopNonce * 7919
		local res = RecruitmentService.GenerateRecruitPool(_playerId, seed, nil)
		if not tavernHired or tavernHired.seed ~= seed then
			tavernHired = { seed = seed, ids = {} }
		end
		local hired = tavernHired.ids
		local pool = {}
		for _, c in res.pool or {} do
			if not hired[c.candidateId] then
				c.preview = previewRecruit(c) -- shown in the Tavern inspector
				table.insert(pool, c)
			end
		end
		tavernCache = { pool = pool, reason = res.reason, seed = seed }
	end
	return tavernCache
end

-- Remember a hire so the recruit stays gone after a restart or a pool rebuild.
local function markHired(candidateId: string)
	local cache = tavernCache
	if cache and tavernHired and tavernHired.seed == cache.seed then
		tavernHired.ids[candidateId] = true
	end
end

local function merchantStock()
	-- Rebuild when the 5-battle window OR the map level changes (2026-10-31, user decision):
	-- the base shelf (L1) and a quest shelf (its level) are different shelves, so switching
	-- between them must show the right one at once, not the first one opened this window.
	-- Bought slots are tracked per shelf in MerchantService, so a rebuild never restocks them.
	local lvl = mapLevel()
	local key = `{math.floor(battlesCompleted / MERCHANT_REFRESH_BATTLES)}:{lvl}:{devShopNonce}`
	if not merchantCache or merchantCache.key ~= key then
		-- No seed until the first dev refresh, so normal shelves stay exactly as before.
		local seed: number? = if devShopNonce > 0 then devShopNonce * 104729 else nil
		local res = MerchantService.GetStock(_playerId, lvl, battlesCompleted, seed)
		merchantCache = { key = key, res = res }
	end
	return merchantCache.res
end

local function dispatchBoard()
	if not dispatchCache then
		local res = DispatchService.OfferMissions(_playerId, mapLevel(), 5003 + battlesCompleted * 31 + devShopNonce * 7907)
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
	return true, nil, maxLevel
end

local function describeItem(item: any): any
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
	local g = guard(player, "tavern"); if g then return fail(g) end
	local cache = tavernPool()
	local list = {}
	for _, c in cache.pool do
		table.insert(list, {
			candidateId = c.candidateId, level = c.level, quality = c.quality, cost = c.cost,
			preview = c.preview, -- race, perk, flaw, doctrine, primary stats (display only)
		})
	end
	return { ok = true, pool = list, reason = cache.reason, tavernLevel = GuildMenuService.GetBuildingLevel("Tavern") }
end

local function onRequestHire(player: Player, candidateId: any)
	local g = guard(player, "hire"); if g then return fail(g) end
	if type(candidateId) ~= "string" or #candidateId > 64 then return fail("Invalid recruit") end
	local cache = tavernPool()
	local idx, candidate = nil, nil
	for i, c in cache.pool do
		if c.candidateId == candidateId then idx, candidate = i, c; break end
	end
	if not candidate then return fail("That recruit is no longer available") end

	local ok, result: any = RecruitmentService.CommitHire(_playerId, candidate)
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
	markHired(candidateId)
	markDirty()
	local gold = balance()
	return { ok = true, unitName = unit.name, cost = result.cost, gold = gold }
end

local function onGetMerchantStock(player: Player)
	local g = guard(player, "merchant"); if g then return fail(g) end
	local res = merchantStock()
	local stock = {}
	for i, offer in res.stock or {} do
		table.insert(stock, {
			offerIndex = i, name = itemDisplayName(offer.item), level = offer.itemLevel,
			rarity = offer.rarity, price = offer.buyPrice,
			-- Full display detail for the Merchant inspector (stats, passives, bonuses, icon).
			-- Display-only; buying still goes by offerIndex and is re-priced server-side.
			detail = ItemDisplay.buildItemEntry(offer.item),
		})
	end
	local sellable = {}
	for _, item in InventoryService.GetAllItems(_playerId) do
		if not holderOf(item.instanceId) then
			local d = describeItem(item)
			d.price = MerchantService.PriceToSell(item)
			d.detail = ItemDisplay.buildItemEntry(item)
			table.insert(sellable, d)
		end
	end
	table.sort(sellable, function(a: any, b: any) return a.name < b.name end)
	return { ok = true, stock = stock, sellable = sellable, reason = res.reason,
		merchantLevel = GuildMenuService.GetBuildingLevel("Merchant"), slots = res.slots }
end

local function onRequestBuy(player: Player, offerIndex: any)
	local g = guard(player, "buy"); if g then return fail(g) end
	if type(offerIndex) ~= "number" or offerIndex ~= offerIndex or offerIndex % 1 ~= 0 then
		return fail("Invalid offer")
	end
	local res = merchantStock()
	if offerIndex < 1 or offerIndex > #(res.stock or {}) then return fail("Invalid offer") end
	local ok, result: any = MerchantService.BuyItem(_playerId, offerIndex, mapLevel(), battlesCompleted)
	if not ok then return fail(tostring(result)) end
	markDirty()
	return { ok = true, name = itemDisplayName(result.item), price = result.price, gold = (balance()) }
end

local function onRequestSell(player: Player, instanceId: any)
	local g = guard(player, "sell"); if g then return fail(g) end
	if type(instanceId) ~= "string" or #instanceId > 80 then return fail("Invalid item") end
	if not InventoryService.OwnsItem(_playerId, instanceId) then return fail("Item not owned") end
	if holderOf(instanceId) then return fail("Unequip that item before selling it") end
	local ok, result: any = MerchantService.SellItem(_playerId, instanceId)
	if not ok then return fail(tostring(result)) end
	markDirty()
	return { ok = true, payout = result.payout, gold = (balance()) }
end

local function onGetBlacksmithItems(player: Player)
	local g = guard(player, "smith"); if g then return fail(g) end
	local items = {}
	for _, item in InventoryService.GetAllItems(_playerId) do
		if type(item.itemLevel) == "number" then
			local d = describeItem(item)
			local allowed, why, maxLevel = blacksmithGate(item)
			local cost = BlacksmithService.ResolveUpgradeCost(item, item.itemLevel + 1)
			d.canUpgrade = allowed and cost ~= nil
			d.upgradeBlockedReason = why
			d.upgradeGold = cost and cost.gold or nil
			d.upgradeMercury = cost and cost.mercury or nil
			if allowed and maxLevel then
				d.upgradeCurve = BlacksmithService.GetUpgradeCurve(item, maxLevel)
			end
			d.canDowngrade = item.itemLevel > 1
			d.minDowngradeLevel = 1 -- free and unlimited (guild_facilities 47)
			d.detail = ItemDisplay.buildItemEntry(item) -- Blacksmith screen inspector (v2 step 3)
			-- Dismantle preview (guild_facilities 51-52, v2 step 2). Equipped items (also on
			-- units away on dispatch) cannot be dismantled.
			local yield, ywhy = BlacksmithService.ResolveDismantle(item)
			if yield then
				local gemNames = {}
				for gid, n in yield.gems do
					table.insert(gemNames, if n > 1 then `{gid} x{n}` else gid)
				end
				table.sort(gemNames)
				d.dismantle = {
					mercury = yield.mercury, crystals = yield.crystals, sulfur = yield.sulfur,
					gemCount = yield.gemCount, gems = gemNames, cappedLines = yield.cappedLines,
					lostPassives = yield.lostPassives, aboveEpic = yield.aboveEpic, unique = yield.unique,
				}
			end
			d.canDismantle = yield ~= nil and d.equippedBy == nil
			d.dismantleBlockedReason = if d.equippedBy then `Equipped by {d.equippedBy}` elseif not yield then tostring(ywhy) else nil
			table.insert(items, d)
		end
	end
	table.sort(items, function(a: any, b: any)
		if (a.equippedBy ~= nil) ~= (b.equippedBy ~= nil) then return a.equippedBy ~= nil end
		return a.name < b.name
	end)
	local gold, mats = balance()
	return { ok = true, items = items, gold = gold, resources = mats,
		blacksmithLevel = GuildMenuService.GetBuildingLevel("Blacksmith") }
end

local function ownedItem(instanceId: any): (any?, string?)
	if type(instanceId) ~= "string" or #instanceId > 80 then return nil, "Invalid item" end
	local item = InventoryService.GetItem(_playerId, instanceId)
	if not item then return nil, "Item not owned" end
	return item, nil
end

local function onRequestUpgrade(player: Player, instanceId: any)
	local g = guard(player, "upgrade"); if g then return fail(g) end
	local item, err = ownedItem(instanceId)
	if not item then return fail(err or "Invalid item") end
	local allowed, why = blacksmithGate(item)
	if not allowed then return fail(why or "Not allowed") end
	local ok, result: any = BlacksmithService.CommitUpgrade(_playerId, item, item.itemLevel + 1)
	if not ok then return fail(tostring(result)) end
	markDirty()
	return { ok = true, toLevel = result.toLevel, gold = (balance()) }
end

local function onRequestDowngrade(player: Player, instanceId: any, targetLevel: any)
	local g = guard(player, "downgrade"); if g then return fail(g) end
	local item, err = ownedItem(instanceId)
	if not item then return fail(err or "Invalid item") end
	-- Free and unlimited (guild_facilities 47): any level from 1 up to the current level.
	-- No target = one level down (the old behaviour).
	local target = item.itemLevel - 1
	if targetLevel ~= nil then
		if type(targetLevel) ~= "number" or targetLevel ~= targetLevel or targetLevel % 1 ~= 0 then
			return fail("Invalid level")
		end
		target = targetLevel
	end
	if target < 1 or target >= item.itemLevel then return fail("Invalid level") end
	local ok, result: any = BlacksmithService.CommitDowngrade(_playerId, item, target)
	if not ok then return fail(tostring(result)) end
	markDirty()
	return { ok = true, toLevel = result.toLevel }
end

local function onFinalizeCart(player: Player, payload: any)
	-- SMARTER SAVE / CART (2026-10-13): buy+sell are batched client-side and committed
	-- here in ONE call. Sells run first (free gold for the buys); buys run high-index
	-- first because buying removes an offer and reindexes the rest. One save at the end.
	local g = guard(player, "cart"); if g then return fail(g) end
	if type(payload) ~= "table" then return fail("Invalid cart") end
	local buys = (type(payload.buys) == "table") and payload.buys or {}
	local sells = (type(payload.sells) == "table") and payload.sells or {}
	-- Blacksmith staged (2026-10-14): optional { [instanceId] = targetLevel } maps, applied
	-- here on Save, dropped on Discard. Keeps blacksmith consistent with the buy/sell cart.
	local upgrades = (type(payload.upgrades) == "table") and payload.upgrades or {}
	local downgrades = (type(payload.downgrades) == "table") and payload.downgrades or {}
	local upCount, downCount = 0, 0
	for _ in upgrades do upCount += 1 end
	for _ in downgrades do downCount += 1 end
	-- Dispatch staged (2026-10-14): optional list of { missionId, unitIds }, sent on Save,
	-- dropped on Discard. Applied sequentially below with the same checks as the live Send.
	local dispatches = (type(payload.dispatches) == "table") and payload.dispatches or {}
	-- Tavern staged (2026-10-14): optional list of candidateId strings, hired on Save, dropped
	-- on Discard. Mirrors the live onRequestHire per candidate; failures go to problems.
	local hires = (type(payload.hires) == "table") and payload.hires or {}
	-- Blacksmith dismantle staged (v2 step 2): optional list of instanceIds, destroyed on Save.
	local dismantles = (type(payload.dismantles) == "table") and payload.dismantles or {}
	if #buys > 50 or #sells > 50 or upCount > 50 or downCount > 50 or #dispatches > 50 or #hires > 50
		or #dismantles > 50 then return fail("Cart too large") end

	local soldCount, boughtCount = 0, 0
	local soldGold, boughtGold = 0, 0
	local sellFailed, buyFailed = 0, 0 -- shown to the player (2026-10-31: failures were silent)
	local upgradedCount, downgradedCount = 0, 0
	local dispatchedCount = 0
	local hiredCount = 0
	local dismantledCount = 0
	local dismantleGain = { mercury = 0, crystals = 0, sulfur = 0, gems = 0 }
	local problems: { string } = {}

	-- guild_facilities 52: an item staged to be sold, upgraded or downgraded in this cart
	-- cannot also be dismantled. Collected BEFORE anything runs.
	local stagedElsewhere: { [string]: boolean } = {}
	for _, iid in sells do if type(iid) == "string" then stagedElsewhere[iid] = true end end
	for iid in upgrades do if type(iid) == "string" then stagedElsewhere[iid] = true end end
	for iid in downgrades do if type(iid) == "string" then stagedElsewhere[iid] = true end end

	for _, instanceId in sells do
		if type(instanceId) == "string" and #instanceId <= 80
			and InventoryService.OwnsItem(_playerId, instanceId) and not holderOf(instanceId) then
			local ok, result: any = MerchantService.SellItem(_playerId, instanceId)
			if ok then
				soldCount += 1
				soldGold += (result.payout or 0)
			else
				sellFailed += 1
				table.insert(problems, tostring(result))
			end
		else
			sellFailed += 1
			table.insert(problems, "an item could not be sold (equipped or no longer owned)")
		end
	end

	local buyIdx: { number } = {}
	for _, idx in buys do
		if type(idx) == "number" and idx == idx and idx % 1 == 0 then table.insert(buyIdx, idx) end
	end
	table.sort(buyIdx, function(a, b) return a > b end)
	for _, idx in buyIdx do
		local ok, result: any = MerchantService.BuyItem(_playerId, idx, mapLevel(), battlesCompleted)
		if ok then
			boughtCount += 1
			boughtGold += (result.price or 0)
		else
			buyFailed += 1
			table.insert(problems, tostring(result))
		end
	end

	-- Blacksmith: apply each staged item as +1 steps, re-checking the blacksmith gate AND
	-- affordability per step (exactly like the live handler) so staging cannot bypass the
	-- level cap. CommitUpgrade is atomic (gold+materials or nothing); nothing was charged
	-- before this point, so a Discard upstream simply never calls this handler.
	for instanceId, targetLevel in upgrades do
		if type(instanceId) == "string" and #instanceId <= 80 and type(targetLevel) == "number" then
			local item = InventoryService.GetItem(_playerId, instanceId)
			if not item then
				table.insert(problems, "an item to upgrade is no longer owned")
			else
				while item.itemLevel < targetLevel do
					local allowed, why = blacksmithGate(item)
					if not allowed then table.insert(problems, why or "upgrade blocked"); break end
					local ok, result: any = BlacksmithService.CommitUpgrade(_playerId, item, item.itemLevel + 1)
					if not ok then table.insert(problems, tostring(result)); break end
					upgradedCount += 1
				end
			end
		end
	end
	for instanceId, targetLevel in downgrades do
		if type(instanceId) == "string" and #instanceId <= 80 and type(targetLevel) == "number" then
			local item = InventoryService.GetItem(_playerId, instanceId)
			if not item then
				table.insert(problems, "an item to downgrade is no longer owned")
			else
				while item.itemLevel > targetLevel and item.itemLevel > 1 do
					local ok, result: any = BlacksmithService.CommitDowngrade(_playerId, item, item.itemLevel - 1)
					if not ok then table.insert(problems, tostring(result)); break end
					downgradedCount += 1
				end
			end
		end
	end
	-- Blacksmith dismantle (guild_facilities 51-52): owned, not equipped (holderOf covers units
	-- away on dispatch, so the keep-a-weapon rule / BUG-050 stays safe), not staged for
	-- anything else in this cart. CommitDismantle removes the item before crediting.
	local seenDismantle: { [string]: boolean } = {}
	for _, instanceId in dismantles do
		if type(instanceId) ~= "string" or #instanceId > 80 or seenDismantle[instanceId] then
			table.insert(problems, "an invalid dismantle entry was ignored")
		else
			seenDismantle[instanceId] = true
			local item = InventoryService.GetItem(_playerId, instanceId)
			if not item then
				table.insert(problems, "an item to dismantle is no longer owned")
			elseif holderOf(instanceId) then
				table.insert(problems, `{itemDisplayName(item)} is equipped and was not dismantled`)
			elseif stagedElsewhere[instanceId] then
				table.insert(problems, `{itemDisplayName(item)} is also staged to sell or level and was not dismantled`)
			else
				local ok, result: any = BlacksmithService.CommitDismantle(_playerId, item)
				if ok then
					dismantledCount += 1
					dismantleGain.mercury += result.yield.mercury
					dismantleGain.crystals += result.yield.crystals
					dismantleGain.sulfur += result.yield.sulfur
					dismantleGain.gems += result.yield.gemCount
				else
					table.insert(problems, tostring(result))
				end
			end
		end
	end
	-- Dispatch: apply each staged mission one at a time, re-validating against the updated
	-- roster each time (roster membership, not-already-away, keep-one-home, mission still
	-- offered) exactly like the live onRequestDispatch. SendUnits marks units away, so the
	-- next staged entry sees the reduced home count. Overflow is refused into problems.
	for _, d in dispatches do
		if type(d) == "table" and type(d.missionId) == "string" and #d.missionId <= 64
			and type(d.unitIds) == "table" and #d.unitIds >= 1 and #d.unitIds <= MAX_DISPATCH_PICK then
			local live = playerUnits()
			local seen: { [string]: boolean } = {}
			local clean: { string } = {}
			local okPick = true
			for _, id in d.unitIds do
				if type(id) ~= "string" or seen[id] then okPick = false; break end
				if not live[id] then okPick = false; break end
				if DispatchService.IsUnitDispatched(_playerId, id) then okPick = false; break end
				seen[id] = true
				table.insert(clean, id)
			end
			if not okPick then
				table.insert(problems, "a dispatch had an invalid or unavailable unit")
			elseif homeUnitCount() - #clean < 1 then
				table.insert(problems, "a dispatch would leave no unit at home")
			else
				local board = dispatchBoard()
				local mIdx = nil
				for i, m in board.missions do if m.missionId == d.missionId then mIdx = i; break end end
				if not mIdx then
					table.insert(problems, "a dispatch mission is no longer offered")
				else
					local ok, result: any = DispatchService.SendUnits(_playerId, d.missionId, clean, battlesCompleted)
					if ok then
						table.remove(board.missions, mIdx)
						dispatchedCount += 1
					else
						table.insert(problems, tostring(result))
					end
				end
			end
		else
			table.insert(problems, "an invalid dispatch entry was ignored")
		end
	end
	for _, candidateId in hires do
		if type(candidateId) == "string" and #candidateId <= 64 then
			local cache = tavernPool()
			local idx, candidate = nil, nil
			for i, c in cache.pool do
				if c.candidateId == candidateId then idx, candidate = i, c; break end
			end
			if not candidate then
				table.insert(problems, "a recruit is no longer available")
			else
				local ok, result: any = RecruitmentService.CommitHire(_playerId, candidate)
				if not ok then
					table.insert(problems, tostring(result))
				else
					local unitId = result.unitId
					local unit = builtUnits[unitId]
					builtUnits[unitId] = nil
					if not unit then
						table.insert(problems, "a hire recorded but its unit was missing")
					else
						if _addPlayerUnit then _addPlayerUnit(unit) end
						recruitDefs[unitId] = {
							name = unit.name, level = unit.level, raceId = unit.raceId,
							doctrineId = unit.doctrineId, quality = candidate.quality,
						}
						table.insert(recruitOrder, unitId)
						if currentPhase == "PreBattle" then table.insert(pendingBattleUnits, unit) end
						table.remove(cache.pool, idx)
						markHired(candidateId)
						hiredCount += 1
					end
				end
			end
		end
	end
	if soldCount > 0 or boughtCount > 0 or upgradedCount > 0 or downgradedCount > 0 or dispatchedCount > 0 or hiredCount > 0
		or dismantledCount > 0 then
		markDirty()
		save()  -- commit = persist now (matches the confirm-then-save model)
	end
	local gold = balance()
	return { ok = true, boughtCount = boughtCount, soldCount = soldCount,
		upgradedCount = upgradedCount, downgradedCount = downgradedCount,
		dispatchedCount = dispatchedCount,
		hiredCount = hiredCount,
		dismantledCount = dismantledCount, dismantleGain = dismantleGain,
		boughtGold = boughtGold, soldGold = soldGold, gold = gold, problems = problems,
		buyFailed = buyFailed, sellFailed = sellFailed }
end

local function onGetDispatchBoard(player: Player)
	local g = guard(player, "dispatch"); if g then return fail(g) end
	local board = dispatchBoard()
	local missions = {}
	for _, m in board.missions do
		table.insert(missions, {
			missionId = m.missionId, tier = m.tier, duration = m.duration, xp = m.xp,
			rewardMercury = m.rewardMercury,
		})
	end
	local units = {}
	local live = playerUnits()
	for _, id in sortedKeys(live) do
		local away = DispatchService.IsUnitDispatched(_playerId, id)
		table.insert(units, { id = id, name = live[id].name, level = live[id].level,
			away = away, returnBattle = awayUntil[id] })
	end
	return { ok = true, missions = missions, units = units, battlesCompleted = battlesCompleted,
		slotsUsed = DispatchService.GetSlotsUsed(_playerId),
		slotCap = DispatchService.GetSlotCap(_playerId),
		feeGold = DispatchService.GetFeeGold() }
end

local function onRequestDispatch(player: Player, missionId: any, unitIds: any)
	local g = guard(player, "send"); if g then return fail(g) end
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
	for i, m in board.missions do if m.missionId == missionId then mIdx = i; break end end
	if not mIdx then return fail("That mission is no longer offered") end

	local ok, result: any = DispatchService.SendUnits(_playerId, missionId, clean, battlesCompleted)
	if not ok then return fail(tostring(result)) end
	table.remove(board.missions, mIdx)
	markDirty()
	return { ok = true, returnBattle = result.returnBattle, xpEach = result.xpEach }
end

local function onGetGuildUnits(player: Player)
	local g = guard(player, "units"); if g then return fail(g) end
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

-- PARTY MANAGEMENT (game_flow id 4/10/27; activity-agnostic design, user 2026-10-14).
-- PartyService owns the stored data; these thin handlers validate against the LIVE
-- roster (SEC-001/ARC-001): the client sends slot + unit ids only. A unit MAY belong
-- to multiple parties (locked design). Dispatched units are flagged (away) so the
-- client can grey them out; membership stays permissive (being away is a deploy-time
-- filter, not a save-time one). Edits markDirty() -> one save when the menu closes.
local function partyMemberInfo(unitId: string): any
	local live = playerUnits()
	local u = live[unitId]
	if not u then return nil end
	local race = u.raceId and RaceData.GetRace(u.raceId) or nil
	return {
		id = unitId,
		name = u.name,
		unitLevel = u.level,
		race = race and race.name or "?",
		away = DispatchService.IsUnitDispatched(_playerId, unitId),
	}
end

local function onGetParties(player: Player): any
	local g = guard(player, "parties"); if g then return fail(g) end
	local live = playerUnits()
	local ownedSet = {}
	for id in live do ownedSet[id] = true end
	PartyService.PruneToOwned(_playerId, ownedSet)
	local partyList = PartyService.GetParties(_playerId)
	for _, party in ipairs(partyList) do
		local info = {}
		for _, uid in ipairs(party.members) do
			local mi = partyMemberInfo(uid)
			if mi then table.insert(info, mi) end
		end
		party.memberInfo = info
	end
	local roster = {}
	for _, id in sortedKeys(live) do
		local mi = partyMemberInfo(id)
		if mi then table.insert(roster, mi) end
	end
	return { ok = true, parties = partyList, roster = roster, maxSize = PartyService.MAX_PARTY_SIZE }
end

local function onSetPartyName(player: Player, slot: any, name: any): any
	local g = guard(player, "partyname"); if g then return fail(g) end
	if type(slot) ~= "string" then return fail("Invalid party slot") end
	local ok, err = PartyService.SetName(_playerId, slot, name)
	if not ok then return fail(err or "Could not rename party") end
	markDirty()
	return { ok = true }
end

local function onSetPartyMembers(player: Player, slot: any, unitIds: any): any
	local g = guard(player, "partymembers"); if g then return fail(g) end
	if type(slot) ~= "string" then return fail("Invalid party slot") end
	if type(unitIds) ~= "table" then return fail("Invalid member list") end
	local live = playerUnits()
	local clean = {}
	local seen = {}
	for _, uid in ipairs(unitIds) do
		if type(uid) == "string" and live[uid] and not seen[uid] then
			seen[uid] = true
			table.insert(clean, uid)
		end
	end
	local ok, err = PartyService.SetMembers(_playerId, slot, clean)
	if not ok then return fail(err or "Could not save party") end
	markDirty()
	return { ok = true }
end

--------------------------------------------------
-- INIT (Main calls once, after playerUnits and doSave exist)
--------------------------------------------------

-- UNIT DISMISSAL (Loadout Info tab, user decision 2026-10-15). Two modes on one remote:
-- preview (confirm nil) returns the exact severance fee + flags, changing nothing; commit
-- (confirm == true) unequips every slot (gear stays owned in inventory), charges the fee,
-- and removes the unit from the roster + recruit save records. Severance = 5x the
-- recruitment cost = 5 x ResolveHireCost(level, quality) (economy_framework id 22; starters
-- and quality-less units default to Standard). The player avatar (Hero) can NEVER be
-- dismissed (project_rules 114; is_avatar not yet flagged in code, so the Hero id is the
-- stand-in until the Designer adds the flag). Not gated by the guild menu being open -- the
-- Loadout screen is its own surface -- but the firing player must be the session player.
local AVATAR_UNIT_ID = "unit_hero"
local DISMISS_SEVERANCE_MULT = 5

local function dismissFeeFor(unitId: string): (number, string, number)
	local units = playerUnits()
	local u = units[unitId]
	local level = (u and tonumber(u.level)) or 1
	local quality = (recruitDefs[unitId] and recruitDefs[unitId].quality) or "Standard"
	local base = RecruitmentService.ResolveHireCost(level, quality)
	return base * DISMISS_SEVERANCE_MULT, quality, level
end

-- Consumable return on dismissal (2026-11-03 ownership). Injected by Main (owns cardInventory).
local _returnConsumable: ((id: string) -> ())? = nil
function GuildMenuService.SetConsumableReturn(fn: (id: string) -> ())
	_returnConsumable = fn
end

-- Owned loose consumable copies (Main's cardInventory.consumables), for the Apothecary.
local _getOwnedConsumables: (() -> { [string]: number })? = nil
function GuildMenuService.SetOwnedConsumables(fn: () -> { [string]: number })
	_getOwnedConsumables = fn
end

--------------------------------------------------
-- APOTHECARY (2026-11-03)
--------------------------------------------------

local function apothecaryPayload(): any
	local lvl = ApothecaryService.GetLevel()
	local gh = buildingLevels.GuildHall or DEFAULT_BUILDING_LEVEL
	local owned = (_getOwnedConsumables and _getOwnedConsumables()) or {}
	local ownedList = {}
	for id, n in owned do
		table.insert(ownedList, { id = id, count = n, sellPrice = ApothecaryService.SellPrice(id) })
	end
	table.sort(ownedList, function(a: any, b: any) return a.id < b.id end)
	local gold, res = balance()
	return {
		ok = true,
		level = lvl,
		buildingLevel = buildingLevels.Apothecary or DEFAULT_BUILDING_LEVEL,
		guildHallLevel = gh,
		lockedReason = if lvl < 1 then `The Apothecary unlocks at Guild Hall L{APOTHECARY_UNLOCK_GUILD_HALL} (yours is L{gh})` else nil,
		refillRate = ApothecaryService.RefillRate(),
		discountPct = ApothecaryService.BuyDiscountPct(),
		autoRefill = ApothecaryService.GetAutoRefill(),
		refillPreview = ApothecaryService.Refill(_playerId, false),
		shelf = ApothecaryService.GetShelf(),
		owned = ownedList,
		gold = gold,
		resources = res,
	}
end

local function onGetApothecary(player: Player): any
	local g = guard(player, "apothecary"); if g then return fail(g) end
	return apothecaryPayload()
end

local function onCommitApothecary(player: Player, cart: any): any
	local g = guard(player, "apothecaryCommit"); if g then return fail(g) end
	if ApothecaryService.GetLevel() < 1 then return fail("The Apothecary is not built yet") end
	if type(cart) ~= "table" then return fail("Invalid cart") end
	local buys: { number } = {}
	if type(cart.buys) == "table" then
		for _, s in cart.buys do
			if type(s) ~= "number" or s % 1 ~= 0 or s < 1 or s > 8 or #buys >= 8 then return fail("Invalid shelf slot") end
			table.insert(buys, s)
		end
	end
	local sells: { [string]: number } = {}
	if type(cart.sells) == "table" then
		local n = 0
		for id, q in cart.sells do
			n += 1
			if n > 200 or type(id) ~= "string" or #id > 16 or type(q) ~= "number" or q % 1 ~= 0 or q < 1 or q > 999 then
				return fail("Invalid sell list")
			end
			sells[id] = q
		end
	end
	local res = ApothecaryService.Commit(_playerId, buys, sells)
	if not res.ok then return fail(res.error or "Refused") end
	markDirty()
	local p = apothecaryPayload()
	p.result = res
	return p
end

local function onApothecaryRefill(player: Player, cmd: any): any
	local g = guard(player, "apothecaryRefill"); if g then return fail(g) end
	if type(cmd) ~= "table" or type(cmd.action) ~= "string" then return fail("Invalid request") end
	if cmd.action == "SetAuto" then
		if ApothecaryService.GetLevel() < 1 then return fail("The Apothecary is not built yet") end
		ApothecaryService.SetAutoRefill(cmd.on == true)
	elseif cmd.action == "RefillNow" then
		local res = ApothecaryService.Refill(_playerId, true)
		print(`[Apothecary] Refill now: {res.refilled} charge(s) for {res.cost}g`)
	else
		return fail("Unknown action")
	end
	markDirty()
	return apothecaryPayload()
end

local function onDismissUnit(player: Player, unitId: any, confirm: any): any
	if _sessionPlayer and player ~= _sessionPlayer then return fail("Not your roster") end
	if type(unitId) ~= "string" then return fail("Invalid unit") end
	local units = playerUnits()
	local unit = units[unitId]
	if not unit then return fail("That unit is no longer on your roster") end

	local isAvatar = (unitId == AVATAR_UNIT_ID) or (unit.is_avatar == true)
	local fee = dismissFeeFor(unitId)
	local gold = (CurrencyService.GetBalance(_playerId) or {}).gold or 0
	local canAfford = gold >= fee

	-- PREVIEW: no mutation. The client shows the exact cost in its confirm dialog.
	if confirm ~= true then
		return { ok = true, preview = true, cost = fee, canAfford = canAfford,
			isAvatar = isAvatar, name = unit.name }
	end

	-- COMMIT.
	if isAvatar then return fail("The Hero cannot be dismissed") end
	if not canAfford then return fail(string.format("Not enough gold for separation pay (need %d)", fee)) end
	-- Items are never destroyed (consumable_framework 1, 2026-11-03): a unit holding a partly
	-- used consumable can't leave until it is refilled (DEV DEFAULT, replaces discarding).
	for _, slotData in pairs(unit.consumableSlots or {}) do
		if type(slotData) == "table" and slotData.consumableId and not ApothecaryService.IsFull(slotData) then
			return fail(`{unit.name} has a partly used item. Refill it at the Apothecary first.`)
		end
	end

	-- 1) Unequip every slot. Items stay owned in the shared inventory (equipping is only an
	-- assignment), so this returns all the unit's gear to inventory by clearing its slots.
	for _, slot in ipairs({ "MainHand", "OffHand", "Head", "Body", "Gloves", "Feet", "Accessory" }) do
		if unit.equipmentSlots and unit.equipmentSlots[slot] then
			-- allowWeaponless: this unit is being dismissed (leaving the roster), so
			-- emptying its weapon is legitimate teardown, exempt from the retention guard.
			EquipmentService.Unequip(unit, slot, { allowWeaponless = true })
		end
	end

	-- 1b) Consumables (2026-11-03): every equipped item is full here (checked above) and goes
	-- back to the owned list.
	for idx, slotData in pairs(unit.consumableSlots or {}) do
		if type(slotData) == "table" and slotData.consumableId then
			if _returnConsumable then _returnConsumable(slotData.consumableId) end
			unit.consumableSlots[idx] = nil
		end
	end

	-- 2) Charge the severance fee.
	CurrencyService.Debit(_playerId, { gold = fee })

	-- 3) Remove from the live roster (same table Main owns via the injected provider).
	units[unitId] = nil

	-- 4) Remove from the recruit save records so the unit does not return next session.
	recruitDefs[unitId] = nil
	builtUnits[unitId] = nil
	for i = #recruitOrder, 1, -1 do
		if recruitOrder[i] == unitId then table.remove(recruitOrder, i) end
	end

	-- 5) Drop the dismissed unit from every saved party (owned-set prune).
	local ownedSet = {}
	for id in units do ownedSet[id] = true end
	PartyService.PruneToOwned(_playerId, ownedSet)

	markDirty()
	print(string.format("[GuildMenuService] Dismissed %s (%s) | severance %dg", unit.name, unitId, fee))
	local balGold = (CurrencyService.GetBalance(_playerId) or {}).gold or 0
	return { ok = true, done = true, cost = fee, gold = balGold }
end


--------------------------------------------------
-- RUNEFORGE (v2 build step 4, 2026-11-01). Server rules live in RuneforgeService; these
-- handlers validate the request shape (SEC-001) and describe results for the screen.
--------------------------------------------------

local function describeLines(lineIds: { string }): { any }
	local out = {}
	for _, id in lineIds do
		local d = RuneforgeService.DescribeGem(id)
		table.insert(out, d or { id = id, kind = "unknown", name = id })
	end
	return out
end

local function linesOf(item: any): { string }
	local ids = {}
	for _, l in item.bonusLines or {} do
		if type(l) == "table" and type(l.id) == "string" then table.insert(ids, l.id) end
	end
	for _, pid in item.bonusPassiveIds or {} do
		if type(pid) == "string" then table.insert(ids, pid) end
	end
	return ids
end

local function validInstalls(installs: any): boolean
	if type(installs) ~= "table" or #installs == 0 or #installs > 8 then return false end
	for _, ins in installs do
		if type(ins) ~= "table" or type(ins.gem) ~= "string" or #ins.gem > 64 then return false end
		if ins.replace ~= nil and (type(ins.replace) ~= "string" or #ins.replace > 64) then return false end
	end
	return true
end

local function onGetRuneforge(player: Player)
	local g = guard(player, "runeforge"); if g then return fail(g) end
	local state = RuneforgeService.GetState()
	local gh = buildingLevels.GuildHall or DEFAULT_BUILDING_LEVEL
	local bal = CurrencyService.GetBalance(_playerId)
	local owned = bal.gems or {}
	local gems = {}
	for id, count in owned do
		local d = RuneforgeService.DescribeGem(id)
		if d and count > 0 then
			d.count = count
			table.insert(gems, d)
		end
	end
	table.sort(gems, function(a: any, b: any)
		if a.kind ~= b.kind then return a.kind == "stat" end
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	local items = {}
	for _, item in InventoryService.GetAllItems(_playerId) do
		if type(item.itemLevel) == "number" then
			local d = describeItem(item)
			d.detail = ItemDisplay.buildItemEntry(item)
			d.lines = describeLines(linesOf(item))
			local arch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			d.passiveSlots = if arch and arch.handClass == "2H" then 2 else 1
			d.runeForged = item.runeForged == true
			local forgeable, why = RuneforgeService.IsForgeable(item)
			d.forgeable = forgeable
			d.forgeBlockedReason = why
			if forgeable then
				local compat = RuneforgeService.CompatibleGems(item)
				local usable = {}
				for id in owned do
					if compat[id] then table.insert(usable, id) end
				end
				table.sort(usable)
				d.compatibleGems = usable
			end
			d.reroll = RuneforgeService.RerollInfo(item)
			table.insert(items, d)
		end
	end
	table.sort(items, function(a: any, b: any) return a.name < b.name end)
	local gold, res = balance()
	return {
		ok = true,
		level = state.level,
		buildingLevel = buildingLevels.Runeforge or DEFAULT_BUILDING_LEVEL,
		guildHallLevel = gh,
		capacity = state.capacity,
		discountPct = state.discountPct,
		lockedReason = if state.level < 1 then `The Runeforge unlocks at Guild Hall L{RUNEFORGE_UNLOCK_GUILD_HALL} (yours is L{gh})` else nil,
		gems = gems,
		items = items,
		gold = gold,
		resources = res,
	}
end

local function onPreviewForge(player: Player, instanceId: any, installs: any)
	local g = guard(player, "forgePreview"); if g then return fail(g) end
	local item, err = ownedItem(instanceId)
	if not item then return fail(err or "Invalid item") end
	if not validInstalls(installs) then return fail("Invalid rune gem selection") end
	local plan, why = RuneforgeService.PlanForge(item, installs)
	if not plan then return fail(tostring(why)) end
	local newIds = {}
	for _, l in plan.lines do table.insert(newIds, l.id) end
	for _, pid in plan.passives do table.insert(newIds, pid) end
	local canAfford = CurrencyService.CanAfford(_playerId, { gold = plan.gold, crystals = plan.crystals, gems = plan.gems })
	return {
		ok = true,
		fromRarity = item.rarityId,
		newRarity = plan.newRarity,
		raised = plan.raised,
		crystals = plan.crystals,
		gold = plan.gold,
		forgeFee = plan.forgeFee,
		swapFee = plan.swapFee,
		catchUp = plan.catchUp,
		totalBp = plan.totalBp,
		replaced = describeLines(plan.replaced),
		newLines = describeLines(newIds),
		newName = ItemGenerator.ComposeName(item.baseArchetypeId, plan.lines, plan.passives),
		canAfford = canAfford,
	}
end

local function onCommitForge(player: Player, instanceId: any, installs: any)
	local g = guard(player, "forge"); if g then return fail(g) end
	local item, err = ownedItem(instanceId)
	if not item then return fail(err or "Invalid item") end
	if not validInstalls(installs) then return fail("Invalid rune gem selection") end
	local ok, result: any = RuneforgeService.CommitForge(_playerId, item, installs)
	if not ok then return fail(tostring(result)) end
	markDirty()
	local gold, res = balance()
	return { ok = true, newRarity = result.plan.newRarity, name = itemDisplayName(item), gold = gold, resources = res }
end

local function onGetRerollSets(player: Player, instanceId: any)
	local g = guard(player, "rerollSets"); if g then return fail(g) end
	local item, err = ownedItem(instanceId)
	if not item then return fail(err or "Invalid item") end
	local offer, why = RuneforgeService.GetRerollOffer(item)
	if not offer then return fail(tostring(why)) end
	local sets = {}
	for i, set in offer.sets do
		local ids = {}
		for _, l in set.bonusLines or {} do table.insert(ids, l.id) end
		for _, pid in set.bonusPassiveIds or {} do table.insert(ids, pid) end
		table.insert(sets, { choice = i, name = set.name, lines = describeLines(ids) })
	end
	return {
		ok = true,
		sulfur = offer.sulfur,
		haveSulfur = CurrencyService.GetBalance(_playerId).sulfur or 0,
		current = { name = itemDisplayName(item), lines = describeLines(linesOf(item)) },
		sets = sets,
	}
end

local function onCommitReroll(player: Player, instanceId: any, choice: any)
	local g = guard(player, "reroll"); if g then return fail(g) end
	local item, err = ownedItem(instanceId)
	if not item then return fail(err or "Invalid item") end
	local ok, result: any = RuneforgeService.CommitReroll(_playerId, item, choice)
	if not ok then return fail(tostring(result)) end
	markDirty()
	local gold, res = balance()
	return { ok = true, choice = result.choice, name = itemDisplayName(item), gold = gold, resources = res }
end

-- DEV TOOLS (Studio only, 2026-10-31): the always-on dev panel (DevToolsPanel) uses this
-- RemoteFunction so it gets an answer back (the building levels after a change). Live servers
-- refuse every request. Replaces the old DevCommand "SetBuildingLevel" listener.
local DEV_ACTIONS = table.freeze({ GetLevels = true, SetBuildingLevel = true, RefreshShops = true })

--------------------------------------------------
-- CRUCIBLE (gear merging, 2026-11-02). Rules live in CrucibleService; these handlers check the
-- request shape (SEC-001) and describe items for the screen. The client sends instance IDs only;
-- the server prices everything. Merges commit straight away (no basket).
--------------------------------------------------

local function validIdList(ids: any): boolean
	if type(ids) ~= "table" or #ids == 0 or #ids > 5 then return false end
	for _, id in ids do
		if type(id) ~= "string" or #id > 80 then return false end
	end
	return true
end

local function onGetCrucible(player: Player)
	local g = guard(player, "crucible"); if g then return fail(g) end
	local state = CrucibleService.GetState()
	local gh = buildingLevels.GuildHall or DEFAULT_BUILDING_LEVEL
	local items = {}
	for _, item in InventoryService.GetAllItems(_playerId) do
		if type(item.itemLevel) == "number" then
			local d = describeItem(item)
			d.detail = ItemDisplay.buildItemEntry(item)
			d.archetypeId = item.baseArchetypeId
			d.blockedReason = CrucibleService.ItemBlockedReason(item)
			table.insert(items, d)
		end
	end
	table.sort(items, function(a: any, b: any)
		if a.name ~= b.name then return a.name < b.name end
		return a.instanceId < b.instanceId
	end)
	local gold, res = balance()
	return {
		ok = true,
		level = state.level,
		buildingLevel = buildingLevels.Crucible or DEFAULT_BUILDING_LEVEL,
		guildHallLevel = gh,
		needed = state.needed,
		boost = state.boost,
		capacity = state.capacity,
		discountPct = state.discountPct,
		lockedReason = if state.level < 1 then `The Crucible unlocks at Guild Hall L{CRUCIBLE_UNLOCK_GUILD_HALL} (yours is L{gh})` else nil,
		items = items,
		gold = gold,
		resources = res,
	}
end

local function onPreviewMerge(player: Player, ids: any)
	local g = guard(player, "mergePreview"); if g then return fail(g) end
	if not validIdList(ids) then return fail("Invalid item selection") end
	local plan, why = CrucibleService.PlanMerge(_playerId, ids)
	if not plan then return fail(tostring(why)) end
	local first = plan.items[1]
	-- D-1 fix (2026-11-02): the plain base-item name (e.g. "Great Bow"), never an input's affix
	-- name -- the merged item's own lines (and so its name) are rolled only when it is made.
	local baseDef = WeaponData.GetByArchetypeId(first.baseArchetypeId) or ArmorData.GetByArchetypeId(first.baseArchetypeId)
	return {
		ok = true,
		name = (baseDef and baseDef.name) or tostring(first.baseArchetypeId),
		fromRarity = plan.fromRarity,
		toRarity = plan.toRarity,
		toLevel = plan.toLevel,
		averageLevel = plan.averageLevel,
		gold = plan.gold,
		crystals = plan.crystals,
		sulfur = plan.sulfur,
		canAfford = CurrencyService.CanAfford(_playerId, { gold = plan.gold, crystals = plan.crystals, sulfur = plan.sulfur }),
	}
end

local function onCommitMerge(player: Player, ids: any)
	local g = guard(player, "merge"); if g then return fail(g) end
	if not validIdList(ids) then return fail("Invalid item selection") end
	local ok, result: any = CrucibleService.CommitMerge(_playerId, ids)
	if not ok then return fail(tostring(result)) end
	markDirty()
	local gold, res = balance()
	local item = result.item
	return { ok = true, instanceId = item.instanceId, name = itemDisplayName(item), rarity = item.rarityId,
		level = item.itemLevel, gold = gold, resources = res }
end

local function onDevGuild(player: Player, cmd: any): any
	if not RunService:IsStudio() then return fail("Dev tools are Studio only") end
	if _sessionPlayer and player ~= _sessionPlayer then return fail("Not your guild") end
	if type(cmd) ~= "table" or type(cmd.action) ~= "string" or not DEV_ACTIONS[cmd.action] then
		return fail("Unknown dev action")
	end
	if cmd.action == "SetBuildingLevel" then
		local name, level = cmd.building, cmd.level
		if type(name) ~= "string" or buildingLevels[name] == nil then return fail("Unknown building") end
		if type(level) ~= "number" or level ~= level or level % 1 ~= 0 then return fail("Invalid level") end
		buildingLevels[name] = math.clamp(level, BUILDING_MIN_LEVEL, BUILDING_MAX_LEVEL)
		tavernCache, merchantCache = nil, nil -- pool size / stock depend on level
		markDirty() -- saved when the menu closes or on quit (facility levels carry over)
		print(`[Dev] Building {name} set to L{buildingLevels[name]} (saved when the menu closes)`)
	elseif cmd.action == "RefreshShops" then
		devShopNonce = math.min(devShopNonce + 1, DEV_NONCE_MAX)
		tavernCache, merchantCache, dispatchCache = nil, nil, nil
		markDirty()
		print(`[Dev] All shops refreshed (Merchant, Tavern, Dispatch) | refresh #{devShopNonce} (saved when the menu closes)`)
	end
	return { ok = true, buildings = table.clone(buildingLevels), shopRefresh = devShopNonce }
end

function GuildMenuService.Init(deps: any)
	_playerId = deps.playerId or _playerId
	_sessionPlayer = deps.sessionPlayer
	_getPlayerUnits = deps.getPlayerUnits
	_addPlayerUnit = deps.addPlayerUnit
	_doSave = deps.doSave
	_getMapLevel = deps.getMapLevel
	_isSkillRegistered = deps.isSkillRegistered
	ApothecaryService.Init({
		getLevel = GuildMenuService.GetApothecaryLevel,
		getOwned = function() return (_getOwnedConsumables and _getOwnedConsumables()) or nil end,
		getUnits = playerUnits,
		getBattles = function() return battlesCompleted end,
		getNonce = function() return devShopNonce end,
	})

	-- Dispatch slots follow the temporary Guild Hall level (Dev-adjustable).
	DispatchService.SetGuildHallLevelProvider(function(_pid: any)
		return buildingLevels.GuildHall or DEFAULT_BUILDING_LEVEL
	end)

	GuildEvents.GetGuildOverview.OnServerInvoke = onGetOverview
	GuildEvents.GetTavernPool.OnServerInvoke = onGetTavernPool
	GuildEvents.RequestHire.OnServerInvoke = onRequestHire
	GuildEvents.GetMerchantStock.OnServerInvoke = onGetMerchantStock
	GuildEvents.RequestBuy.OnServerInvoke = onRequestBuy
	GuildEvents.RequestSell.OnServerInvoke = onRequestSell
	GuildEvents.GetBlacksmithItems.OnServerInvoke = onGetBlacksmithItems
	GuildEvents.RequestUpgrade.OnServerInvoke = onRequestUpgrade
	GuildEvents.RequestDowngrade.OnServerInvoke = onRequestDowngrade
	GuildEvents.FinalizeCart.OnServerInvoke = onFinalizeCart
	GuildEvents.GetDispatchBoard.OnServerInvoke = onGetDispatchBoard
	GuildEvents.RequestDispatch.OnServerInvoke = onRequestDispatch
	GuildEvents.GetGuildUnits.OnServerInvoke = onGetGuildUnits
	GuildEvents.GetParties.OnServerInvoke = onGetParties
	GuildEvents.SetPartyName.OnServerInvoke = onSetPartyName
	GuildEvents.SetPartyMembers.OnServerInvoke = onSetPartyMembers
	BattleEvents.RequestDismissUnit.OnServerInvoke = onDismissUnit

	-- Runeforge (v2 build step 4).
	GuildEvents.GetRuneforge.OnServerInvoke = onGetRuneforge
	GuildEvents.PreviewForge.OnServerInvoke = onPreviewForge
	GuildEvents.CommitForge.OnServerInvoke = onCommitForge
	GuildEvents.GetRerollSets.OnServerInvoke = onGetRerollSets
	GuildEvents.CommitReroll.OnServerInvoke = onCommitReroll
	-- Crucible (gear merging, 2026-11-02).
	GuildEvents.GetCrucible.OnServerInvoke = onGetCrucible
	GuildEvents.PreviewMerge.OnServerInvoke = onPreviewMerge
	GuildEvents.CommitMerge.OnServerInvoke = onCommitMerge
	GuildEvents.GetApothecary.OnServerInvoke = onGetApothecary
	GuildEvents.CommitApothecary.OnServerInvoke = onCommitApothecary
	GuildEvents.ApothecaryRefill.OnServerInvoke = onApothecaryRefill

	-- Studio-only dev panel requests (the handler refuses outside Studio).
	GuildEvents.DevGuild.OnServerInvoke = onDevGuild
	print(`[GuildMenuService] Initialized | Merchant L{buildingLevels.Merchant} | battles completed {battlesCompleted}`)
end

return GuildMenuService
