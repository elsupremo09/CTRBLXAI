-- CTRBLXAI | Slice 3 — "Skills and Real Combat"
--
-- Player-controlled units wait for client input.
-- Enemy units use AI.
--
-- Player input flow:
--   1. Server sends PlayerTurnPrompt with available actions
--   2. Client shows Skill Cards + Move highlights + Attack option
--   3. Player clicks → client fires PlayerCommand
--   4. Server validates and commits
--   5. If AP remains, send another prompt. If AP=0, turn ends.

local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")
local Game = ServerScriptService:WaitForChild("Game")

local UnitSchema              = require(Game:WaitForChild("UnitSchema"))
local BattleCoordinator       = require(Game:WaitForChild("BattleCoordinator"))
local CommandService          = require(Game:WaitForChild("CommandService"))
local TargetingService        = require(Game:WaitForChild("TargetingService"))
local BattleVisualBroadcaster = require(Game:WaitForChild("BattleVisualBroadcaster"))
local StatusService           = require(Game:WaitForChild("StatusService"))
-- Connect UnitSchema to StatusService once at boot (2026-10-26). This slot existed but was
-- never filled, so shield bookkeeping (pill draw-down, Retribution Shell on break) and
-- 'healing weakens Venom' in the main heal step never ran.
UnitSchema.SetStatusService(StatusService)
local TraitEffectService      = require(Game:WaitForChild("TraitEffectService"))
local CombatResolver          = require(Game:WaitForChild("CombatResolver"))
local ItemGenerator           = require(Game:WaitForChild("ItemGenerator"))
local InventoryService        = require(Game:WaitForChild("InventoryService"))
local DoctrineInventoryService = require(Game:WaitForChild("DoctrineInventoryService"))
local EquipmentService        = require(Game:WaitForChild("EquipmentService"))
local PersistentStateService  = require(Game:WaitForChild("PersistentStateService"))
local SaveService             = require(Game:WaitForChild("SaveService"))
local RewardService           = require(Game:WaitForChild("RewardService"))
local DisplacementService     = require(Game:WaitForChild("DisplacementService"))
local TileEffectService       = require(Game:WaitForChild("TileEffectService"))
local TileCrossEffectService  = require(Game:WaitForChild("TileCrossEffectService"))
local PulseScheduler          = require(Game:WaitForChild("PulseScheduler"))
local RacePassiveService      = require(Game:WaitForChild("RacePassiveService"))
local ArmorPassiveService     = require(Game:WaitForChild("ArmorPassiveService"))
local _AugmentEffectService    = require(Game:WaitForChild("AugmentEffectService"))
local AIService               = require(Game:WaitForChild("AIService"))
local MapService              = require(Game:WaitForChild("MapService"))
local MapRenderer             = require(Game:WaitForChild("MapRenderer"))
local EnemyGenerator          = require(Game:WaitForChild("EnemyGenerator"))
local TraitRoller             = require(Game:WaitForChild("TraitRoller"))
local ObjectEffectService     = require(Game:WaitForChild("ObjectEffectService"))
local ObjectiveService        = require(Game:WaitForChild("ObjectiveService"))
local WeatherService          = require(Game:WaitForChild("WeatherService"))
local BattlefieldEventService = require(Game:WaitForChild("BattlefieldEventService"))
local ItemDisplay             = require(Game:WaitForChild("ItemDisplay")) -- item->UI entry builders (extracted 2026-10-12)

-- Slice 6 services (switched on this pass). CurrencyService provides AsProvider()
-- used by Recruitment/Blacksmith/Merchant/Dispatch; it is required FIRST so the
-- provider exists before the consumers are wired below.
local CurrencyService         = require(Game:WaitForChild("CurrencyService"))
local RecruitmentService      = require(Game:WaitForChild("RecruitmentService"))
local BlacksmithService       = require(Game:WaitForChild("BlacksmithService"))
local GuildService            = require(Game:WaitForChild("GuildService"))
local MerchantService         = require(Game:WaitForChild("MerchantService"))
local DispatchService         = require(Game:WaitForChild("DispatchService"))
local PartyService            = require(Game:WaitForChild("PartyService"))
local ExploreService          = require(Game:WaitForChild("ExploreService"))
local ProgressionService      = require(Game:WaitForChild("ProgressionService"))
-- Slice 6 temporary Guild menu (game_flow id 23): server glue for the building
-- buttons. Requires GuildEvents itself, so the Guild remotes exist from here on.
local GuildMenuService        = require(Game:WaitForChild("GuildMenuService"))
-- UGC Rental & Ownership (ugc_rules 2026-10-07). Wired below GuildMenuService.Init.
local UGCService              = require(Game:WaitForChild("UGCService"))
local UGCOutfitService        = require(Game:WaitForChild("UGCOutfitService"))
local UGCRemoteHandler        = require(Game:WaitForChild("UGCRemoteHandler"))
local UGCRatingService        = require(Game:WaitForChild("UGCRatingService")) -- split from UGCService 2026-10-08 (ARC-005)


local WeaponData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("WeaponData")
)
local RaceData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)

-- STAT BASE ESTABLISHMENT (2026-10-19): idempotent. Base Primary Stat = race growth
-- (CalcBaseStats from the unit's level) + permanent allocation (statAllocation). Set
-- ABSOLUTELY (not +=), so this is safe to call anywhere, any number of times, on a
-- reused object or a freshly-built one, with no double-apply. Called wherever a player
-- unit is established (boot roster + battle setup) and after a level-up.
-- (CTRBLXAI.db unit_progression ids 100-105; item_rarity_rules id 9.)
local STAT_KEYS = {"STR", "AGI", "INT", "VIT", "DEX", "LUK"}
local function establishBaseStats(u)
	if not (u and u.raceId and u.baseStats) then return end
	local raceBase = RaceData.CalcBaseStats(u.raceId, u.level or 1)
	if not raceBase then return end
	for _, stat in ipairs(STAT_KEYS) do
		local alloc = (u.statAllocation and u.statAllocation[stat]) or 0
		if raceBase[stat] ~= nil then
			u.baseStats[stat] = raceBase[stat] + alloc
		end
	end
	EquipmentService.RebuildUnitStats(u)
end
local TraitData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("TraitData")
)
local DoctrineData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("DoctrineData")
)
local SkillData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("SkillData")
)

local BonusData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("BonusData")
)
local ArmorData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ArmorData")
)

local AugmentData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("AugmentData")
)

--------------------------------------------------
-- SHARED BATTLE GOLD BREAKDOWN (2026-10-17)
-- One formula used by BOTH the battle-end payout AND the live Map Details
-- "accumulated so far" panel, so the live projection can never drift from the
-- real payout (no duplicated math). Pure/read-only: derives the kill list and
-- deployed-player set from the CURRENT unit list exactly as the post-battle
-- block does (a dead non-summon enemy = a kill), applies the level-gap band,
-- per-kill base gold, and the largest event gold multiplier. On victory it adds
-- completion + quest gold; on non-victory it keeps 50% of kill gold only (the
-- locked defeat rule). Returns the breakdown; does NOT credit or mutate state.
local KILL_GOLD_BASE = { Grunt = 8, Veteran = 14, Elite = 25, Boss = 50 }
local function computeBattleGold(units, playerUnitsById, quest, isVictory)
	local recLvl = (quest and quest.recommendedLvl) or 1
	local topLevel = 1
	local killCount = 0
	local kills = {}
	for _, u in ipairs(units or {}) do
		if u.side == "Enemy" and not u.isSummon and not u.isAlive then
			kills[#kills + 1] = {
				enemyType = u.enemyType,
				level = u.level or 0,
				goldMult = (type(u.rewardOnDeath) == "table" and tonumber(u.rewardOnDeath.goldMult)) or nil,
				goldHarvest = u._goldHarvested == true,  -- Gold Harvest augment: +25% this kill (2026-10-25)
			}
			killCount += 1
		elseif u.side == "Player" and not u.isSummon and playerUnitsById and playerUnitsById[u.id] then
			local pu = playerUnitsById[u.id]
			if pu and type(pu.level) == "number" and pu.level > topLevel then topLevel = pu.level end
		end
	end
	local gap = topLevel - recLvl
	local band = if gap <= 5 then 1.0 elseif gap <= 10 then 0.75 elseif gap <= 15 then 0.50
		elseif gap <= 20 then 0.25 else 0.10
	local killGold = 0
	local eventGoldMult = 1
	for _, k in ipairs(kills) do
		local base = KILL_GOLD_BASE[k.enemyType or ""] or KILL_GOLD_BASE.Grunt
		local kg = base * (1 + (k.level or 0) / 100) * band
		if k.goldHarvest then kg = kg * 1.25 end  -- Gold Harvest augment (2026-10-25)
		killGold += kg
		if k.goldMult and k.goldMult > eventGoldMult then eventGoldMult = k.goldMult end
	end
	killGold = math.floor(killGold)
	local completionGold, questGold = 0, 0
	if isVictory then
		local r = quest and quest.rewards
		local cBase = (r and r.completionGoldBase) or 30
		completionGold = math.floor(cBase * (1 + recLvl / 50))
		questGold = (r and r.questGold) or 0
	else
		killGold = math.floor(killGold * 0.5)
	end
	local total = math.floor((killGold + completionGold + questGold) * eventGoldMult)
	return {
		killGold = killGold, completionGold = completionGold, questGold = questGold,
		eventGoldMult = eventGoldMult, band = band, total = total, killCount = killCount,
	}
end

-- Moved up (was declared mid-file, after the roster builder that uses it).
local ConsumableData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ConsumableData")
)

-- Portrait pools per race (player 2D-portrait picker validation).
local PortraitData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("PortraitData")
)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local BattleEvents = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Remotes")
		:WaitForChild("BattleEvents")
)

--------------------------------------------------
-- WEAPON ACCESSORY ATTACHMENT (server-side)
--------------------------------------------------
-- Weapons are RIGID ACCESSORIES stored at ServerStorage > Gears > Weapon,
-- named by the archetype display name (e.g. "Sword", "Wand"). A rigid
-- accessory already carries its own attachment, so Humanoid:AddAccessory
-- snaps it onto the correct body part automatically -- no welds needed.
-- Done server-side so it replicates once with the unit (NET: server
-- simulates, client visualizes). A missing accessory is skipped with a
-- warn so units without a model simply spawn weaponless, never erroring.
local ServerStorage = game:GetService("ServerStorage")

-- Find a weapon accessory by archetype name. Exact match first, then a
-- case/space-insensitive fallback so minor name drift (e.g. "CrossBow" vs
-- "Crossbow", "Great Sword" vs "Greatsword") still resolves.
local function findWeaponAccessory(weaponName: string): Instance?
	if not weaponName or weaponName == "none" or weaponName == "Unarmed" then return nil end
	local gears = ServerStorage:FindFirstChild("Gears")
	local weaponFolder = gears and gears:FindFirstChild("Weapon")
	if not weaponFolder then
		warn("[WeaponAttach] ServerStorage > Gears > Weapon folder not found")
		return nil
	end
	local exact = weaponFolder:FindFirstChild(weaponName)
	if exact then return exact end
	local function norm(s: string): string return (s:lower():gsub("%s+", "")) end
	local want = norm(weaponName)
	for _, child in ipairs(weaponFolder:GetChildren()) do
		if norm(child.Name) == want then return child end
	end
	return nil
end

-- Resolve the equipped archetype display NAME for a slot ("MainHand"/"OffHand").
local function equippedArchetypeName(unit, slot: string): string?
	if not (unit.equipmentSlots and unit.equipmentSlots[slot]) then return nil end
	local item = unit.equipmentSlots[slot]
	local arch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
	return arch and arch.name or nil
end

-- Attach the equipped MainHand and OffHand weapon accessories to a spawned unit.
local function attachWeaponToUnit(charModel: Model, unit)
	if not charModel or not unit then return end
	local humanoid = charModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(string.format("[WeaponAttach] %s: no Humanoid -- cannot attach weapon", unit.name or "?"))
		return
	end
	for _, slot in ipairs({ "MainHand", "OffHand" }) do
		local weaponName = equippedArchetypeName(unit, slot)
		if weaponName then
			local tpl = findWeaponAccessory(weaponName)
			if not tpl then
				warn(string.format("[WeaponAttach] %s %s: no accessory '%s' in Gears/Weapon -- skipping",
					unit.name or "?", slot, weaponName))
			else
				local acc = tpl:Clone()
				if acc:IsA("Accessory") then
					humanoid:AddAccessory(acc)
				else
					acc.Parent = charModel
				end
				print(string.format("[WeaponAttach] %s: %s '%s' attached", unit.name or "?", slot, weaponName))
			end
		end
	end
end

--------------------------------------------------
-- TILE OCCUPANCY HELPERS
--------------------------------------------------

local mapFolder = nil  -- Set after quest map renders (L~195). No startup map.

local BATTLE_OFFSET_X = 0
local BATTLE_OFFSET_Y = 0

local function findTilePart(x, y)
	local templateX = x + BATTLE_OFFSET_X
	local templateY = y + BATTLE_OFFSET_Y
	for _, child in ipairs(mapFolder:GetChildren()) do
		if child:GetAttribute("X") == templateX and child:GetAttribute("Y") == templateY then
			return child
		end
	end
	return nil
end

local function setTileOccupant(x, y, name, category, impact)
	local tile = findTilePart(x, y)
	if not tile then return end
	tile:SetAttribute("ObjectName", name)
	tile:SetAttribute("ObjectCategory", category)
	tile:SetAttribute("ObjectPassabilityImpact", impact)
end

local function clearTileOccupant(x, y)
	setTileOccupant(x, y, "None", "None", "None")
end

--------------------------------------------------
-- QUEST BOARD > MAP SETUP
-- Quest flow replaces hardcoded Plains/T01 generation.
-- Map generation + service init deferred until after quest selection.
--------------------------------------------------

local QuestGenerator = require(Game:WaitForChild("QuestGenerator"))

-- Wait for at least one player to join
local player
if #Players:GetPlayers() > 0 then
	player = Players:GetPlayers()[1]
else
	player = Players.PlayerAdded:Wait()
end
print("[Main] Player joined: " .. player.Name)


-- AIService dependency injection
AIService.SetDependencies({
	TargetingService  = TargetingService,
	CommandService    = CommandService,
	CombatResolver    = CombatResolver,
	StatusService     = StatusService,
	UnitSchema        = UnitSchema,
	TileEffectService = TileEffectService,
	DisplacementService = DisplacementService,
})

--------------------------------------------------
-- SKILL REGISTRATION
--------------------------------------------------

for key, skillDef in pairs(GameConstants.SKILLS) do
	CommandService.RegisterSkill(skillDef)
	-- Legacy alias support: if this entry was iterated under an alias key
	-- (e.g. "skill_power_strike" → same table as "SKL-POWER-STRIKE"),
	-- RegisterSkill only stores under skillDef.id. Also store under the alias.
	if key ~= skillDef.id then
		CommandService.RegisterSkillAlias(key, skillDef)
	end
end

--------------------------------------------------
-- DOCTRINE SKILL REGISTRATION
-- Doctrine-exclusive skills (DOC-*) are not in GameConstants.SKILLS.
-- They need combat definitions so CommandService can resolve them
-- during PlayerTurnPrompt. Formulas parsed from CTRBLXAI.db.
-- NOTE: Only the 18 doctrine skills that exist in SkillData are
-- registered. When new doctrine skills are added to the DB, add
-- their combat entries here.
--------------------------------------------------

-- NOTE: level-based doctrine skills (Arcanist, Tactician, Warlord, Shadowbinder, Ascetic,
-- Trickster, Duelist, Conjurer-01/02/03) have NO rt field here on purpose — their RT
-- cost comes from GameConstants.SKILL_FIXED_RT (DB-authored). Weapon-WT doctrine skills
-- (Berserker, Ranger, Vanguard, Spellblade, Thief, Juggernaut, Twinblade) keep rtMult.
local doctrineSkillCombatDefs = {
	["DOC-BERSERKER-01"] = { id = "DOC-BERSERKER-01", name = "Reckless Charge", tags = {"Direct Damage","Physical","Utility"}, targetRules = "Enemy Unit", range = 3, pattern = "Single", mpCost = 4, rtMult = 1.50, channelTime = 0, power = 1.20, isHealing = false, isCharge = true },
	["DOC-ARCANIST-01"]  = { id = "DOC-ARCANIST-01", name = "Mana Surge", tags = {"Buff","Utility"}, targetRules = "Self", range = 0, pattern = "Self", mpCost = 0, channelTime = 150, power = 0, isHealing = false, appliesStatus = "Mana Surge", selfMpRestoreFraction = 0.20 },
	["DOC-RANGER-01"]    = { id = "DOC-RANGER-01", name = "Hunter's Mark", tags = {"Direct Damage","Debuff","Physical"}, targetRules = "Enemy Unit", range = -1, pattern = "Single", mpCost = 4, rtMult = 1.00, channelTime = 0, power = 0.75, isHealing = false },
	["DOC-VANGUARD-01"]  = { id = "DOC-VANGUARD-01", name = "Hold the Line", tags = {"Buff","Utility"}, targetRules = "Self", range = 0, pattern = "Self", mpCost = 4, rtMult = 0.75, channelTime = 0, power = 0, isHealing = false, appliesStatus = "Hold the Line" }, -- DB: Stability +2, direct dmg taken -15%, 1000 CT (2026-10-07)
	["DOC-TACTICIAN-01"] = { id = "DOC-TACTICIAN-01", name = "Coordinated Advance", tags = {"Buff","Utility"}, targetRules = "Ally Unit, Self", range = 4, pattern = "Single", mpCost = 5, channelTime = 100, power = 0, isHealing = false, appliesStatus = "Coordinated Advance" }, -- DB: Move +2, Move RT -20%, 1000 CT, channel 100 (2026-10-07)
	["DOC-WARLORD-01"]   = { id = "DOC-WARLORD-01", name = "War Cry", tags = {"Buff","Utility"}, targetRules = "Self, Allies", range = 0, pattern = "AOE", aoePattern = "Circle3", mpCost = 6, channelTime = 100, power = 0, isHealing = false, appliesStatus = "War Cry" }, -- DB: caster + allies radius 3, dmg +10%, Stability +1, 1000 CT, channel 100 (2026-10-07)
	["DOC-SHADOWBINDER-01"] = { id = "DOC-SHADOWBINDER-01", name = "Veil of Weakness", tags = {"Debuff","Dark"}, targetRules = "Enemy Unit", range = 4, pattern = "Single", mpCost = 5, channelTime = 150, power = 0, isHealing = false, appliesStatus = "Weakened", appliesStatuses = { "Debuff Res Down" }, statusDurationCt = 1500 }, -- DB: Weakened + Debuff Res -10 pts, 1500 CT (2026-10-07)
	["DOC-SPELLBLADE-01"] = { id = "DOC-SPELLBLADE-01", name = "Arcane Strike", tags = {"Direct Damage","Physical"}, targetRules = "Enemy Unit", range = 1, pattern = "Single", mpCost = 4, rtMult = 1.00, channelTime = 0, power = 1.10, isHealing = false }, -- rtMult 1.00 per DB (was 1.25)
	["DOC-ASCETIC-01"]   = { id = "DOC-ASCETIC-01", name = "Meditate", tags = {"Buff","Utility"}, targetRules = "Self, Ally Unit", range = 3, pattern = "Single", mpCost = 0, channelTime = 200, power = 0, isHealing = false, appliesStatus = "Debuff Res Up", selfMpRestoreFraction = 0.15, allyMpTransferFraction = 0.12 },
	["DOC-TRICKSTER-01"] = { id = "DOC-TRICKSTER-01", name = "Misdirection", tags = {"Buff","Utility"}, targetRules = "Self", range = 0, pattern = "Self", mpCost = 3, channelTime = 0, power = 0, isHealing = false, appliesStatus = "Misdirection" }, -- DB: 1000 CT, first enemy single-target attack redirected (CommandService applyMisdirection)
	["DOC-THIEF-01"]     = { id = "DOC-THIEF-01", name = "Mug", tags = {"Direct Damage","Physical","Utility"}, targetRules = "Enemy Unit", range = 1, pattern = "Single", mpCost = 2, rtMult = 1.00, channelTime = 0, power = 0.80, isHealing = false },
	["DOC-DUELIST-01"]   = { id = "DOC-DUELIST-01", name = "Riposte Stance", tags = {"Buff","Utility"}, targetRules = "Self", range = 0, pattern = "Self", mpCost = 3, channelTime = 0, power = 0, isHealing = false, appliesStatus = "CounterStance", counterPowerMult = 0.85, counterRtDelayMult = 0.50 },  -- DB: each Riposte deals 85% Basic Attack Power + 50% Weapon RT Delay to attacker
	["DOC-TWINBLADE-01"] = { id = "DOC-TWINBLADE-01", name = "Crossing Blades", tags = {"Direct Damage","Physical"}, targetRules = "Enemy Unit", range = 1, pattern = "Single", mpCost = 4, rtMult = 1.25, channelTime = 0, power = 1.30, isHealing = false },
	["DOC-TWINBLADE-02"] = { id = "DOC-TWINBLADE-02", name = "Feinting Flurry", tags = {"Direct Damage","Physical"}, targetRules = "Enemy Unit", range = 1, pattern = "Single", mpCost = 5, rtMult = 1.50, channelTime = 0, power = 0.60, isHealing = false },
	["DOC-JUGGERNAUT-01"] = { id = "DOC-JUGGERNAUT-01", name = "Overwhelming Blow", tags = {"Direct Damage","Physical"}, targetRules = "Enemy Unit", range = 1, pattern = "Single", mpCost = 6, rtMult = 2.00, channelTime = 200, knockbackOnHit = 1, power = 1.80, isHealing = false },
	["DOC-CONJURER-01"]  = { id = "DOC-CONJURER-01", name = "Conjure Sentinel", tags = {"Summon","Utility"}, targetRules = "Empty Tile", range = 3, pattern = "Single", mpCost = 8, channelTime = 250, power = 0, isHealing = false, isSummon = true, summonProfile = "melee" },
	["DOC-CONJURER-02"]  = { id = "DOC-CONJURER-02", name = "Conjure Wisp", tags = {"Summon","Utility"}, targetRules = "Empty Tile", range = 4, pattern = "Single", mpCost = 5, channelTime = 200, power = 0, isHealing = false, isSummon = true, summonProfile = "ranged" },
	["DOC-CONJURER-03"]  = { id = "DOC-CONJURER-03", name = "Conjure Mender", tags = {"Summon","Healing"}, targetRules = "Empty Tile", range = 3, pattern = "Single", mpCost = 7, channelTime = 250, power = 0, isHealing = false, isSummon = true, summonProfile = "healer" },
}

for docId, docDef in pairs(doctrineSkillCombatDefs) do
	if not CommandService.GetSkill(docId) then
		CommandService.RegisterSkill(docDef)
	end
end

--------------------------------------------------
-- UNIT DEFINITIONS
-- Player units have controller = "Player" (waits for input)
-- Enemy units have controller = "AI"
--
-- Slice 4A: Units now get equipment via ItemGenerator + EquipmentService.
-- Player ID for inventory ownership:
--------------------------------------------------

local PLAYER_ID = "player_1"
InventoryService.InitPlayer(PLAYER_ID)
DoctrineInventoryService.InitPlayer(PLAYER_ID)

--------------------------------------------------
-- SLICE 6 SERVICE STARTUP (additive, dependency-ordered)
-- CurrencyService first (provides AsProvider used by shops/recruit), then the
-- batch-1 (Recruitment/Blacksmith/Guild) and batch-2 (Merchant/Dispatch/Explore)
-- consumers. Balances are RESTORED from the save below (EDIT 3) via Import().
-- ProgressionService providers + unit-XP sinks are wired AFTER playerUnits is
-- defined (they capture it), see the block just below the playerUnits lookup.
--------------------------------------------------
CurrencyService.InitPlayer(PLAYER_ID)
GuildService.InitPlayer(PLAYER_ID)
local currencyProvider = CurrencyService.AsProvider()

-- Batch-1: Recruitment + Blacksmith
RecruitmentService.SetCurrencyProvider(currencyProvider)
BlacksmithService.SetCurrencyProvider(currencyProvider)
RecruitmentService.SetGuildService(GuildService)
RecruitmentService.SetPersistentStateService(PersistentStateService)
BlacksmithService.SetEquipmentService(EquipmentService)
BlacksmithService.SetWeaponData(WeaponData)
BlacksmithService.SetArmorData(ArmorData)
-- TODO when their UIs land: RecruitmentService.SetUnitFactory(...),
--   RecruitmentService.SetTavernLevelProvider(...) [Slice 8],
--   BlacksmithService.SetItemPersist(...)

-- Batch-2: Merchant + Dispatch + Explore
MerchantService.SetCurrencyProvider(currencyProvider)
MerchantService.SetInventoryService(InventoryService)
MerchantService.SetEquipmentService(EquipmentService)
MerchantService.SetItemGenerator(ItemGenerator)
DispatchService.SetCurrencyProvider(currencyProvider)
DispatchService.SetCurrencyCredit(function(pid, grant) return CurrencyService.Credit(pid, grant) end)
ExploreService.SetCurrencyProvider(currencyProvider)
ExploreService.SetRewardService(RewardService)
ExploreService.SetGuildService(GuildService)
-- Torture objective gate (2026-10-24): tell ObjectiveService how to detect a
-- deployed player unit carrying a targetable revive consumable ("KO Ally" rule)
-- with charges, so Torture only rolls when reviving an enemy is actually possible.
-- DI keeps ObjectiveService a leaf module; Main owns the ConsumableData lookup.
ObjectiveService.SetRevivePotionChecker(function(u)
	if not u then return false end
	-- (1) A targetable revive CONSUMABLE ("KO Ally" rule) with charges.
	local slots = u.consumableSlots
	if type(slots) == "table" then
		for _, slot in pairs(slots) do
			if slot and slot.consumableId and (slot.currentCharges or 0) > 0 then
				local def = ConsumableData.Items[slot.consumableId]
				if def and def.targetRules == "KO Ally" then
					return true
				end
			end
		end
	end
	-- (2) An equipped revive SKILL (isRevive). skillIds is populated at battle setup
	-- from the unit's loadout (doctrine skill + equipped skill cards). Revive skills
	-- are equippable loot (not doctrine-locked), so a skill-only party can also revive
	-- an enemy -> Torture must be able to roll for them too. (2026-10-24 follow-up.)
	for _, sid in ipairs(u.skillIds or {}) do
		local sdef = CommandService.GetSkill(sid)
		if sdef and sdef.isRevive then
			return true
		end
	end
	return false
end)
-- Power of Nature gate (2026-10-24): a deployed player unit has an element source
-- if its equipped weapon is elemental OR any of its skills carries an element tag
-- (reuses CombatResolver.ExtractSkillElement — single source for element parsing).
-- Lets Power of Nature roll only when the party can actually burn/transform terrain.
ObjectiveService.SetElementSourceChecker(function(u)
	if not u then return false end
	local we = u.weaponElement
	if we and we ~= "Physical" then return true end
	for _, sid in ipairs(u.skillIds or {}) do
		local def = CommandService.GetSkill(sid)
		if def and CombatResolver.ExtractSkillElement(def) ~= "Physical" then
			return true
		end
	end
	return false
end)
-- TODO when their UIs/roster-availability land: MerchantService.SetMerchantLevelProvider(...),
--   DispatchService.SetAvailabilitySink(...), DispatchService.SetRosterProvider(...)

-- Slice 6 temporary Guild menu (2026-10-07): the connections the TODOs above were
-- waiting for. Building levels come from ONE temporary table in GuildMenuService
-- (all L1 until Slice 8 facilities exist). Wired BEFORE the save load below so
-- DispatchService.Import re-marks away units through the availability sink.
RecruitmentService.SetUnitFactory(GuildMenuService.BuildRecruitUnit)
RecruitmentService.SetTavernLevelProvider(GuildMenuService.TavernLevelProvider)
MerchantService.SetMerchantLevelProvider(GuildMenuService.MerchantLevelProvider)
BlacksmithService.SetItemPersist(GuildMenuService.PersistItem)
DispatchService.SetAvailabilitySink(GuildMenuService.AvailabilitySink)
DispatchService.SetRosterProvider(GuildMenuService.RosterProvider)
-- Blacksmith has no level provider in BlacksmithService; its locked level gates
-- (guild_facilities id 12/13) are enforced in GuildMenuService before a commit.


-- Attempt to load saved state (Slice 4C)
local loadedSave, loadErr = SaveService.Load(PLAYER_ID)
local hasSave = false
local savedEquipMap = {} -- unitId -> { MainHand = instanceId, OffHand = instanceId }
local savedRaceMap = {}  -- unitId -> { raceId, perkIds, drawbackIds }
local savedDoctrineMap = {}  -- unitId -> doctrineId
local savedDoctrineSkillMap = {} -- unitId -> selectedDoctrineSkill
local savedDoctrineInstanceMap = {} -- unitId -> doctrineInstanceId (owned-instance link, 2026-10-20)
local savedSkillLoadoutMap = {} -- unitId -> skillLoadout table
local savedCardInventory: any = {} -- { skillCards = {id=qty}, augmentCards = {id=qty} }
local savedStatAllocation = {} -- unitId -> { STR = N, AGI = N, ... }
local savedRecords = {} -- unitId -> { battlesParticipated = N, ... }
local savedConsumableSlots = {} -- unitId -> consumableSlots table
if loadedSave then
	hasSave = true
	print("[Main] Save loaded — restoring state")
	-- Restore persisted card inventory (Bug fix: was never saved -> starter cards
	-- re-granted every launch, multiplying with equipped-card restores).
	local prog = loadedSave.progression or {}
	if type(prog.cardInventory) == "table" then
		savedCardInventory = prog.cardInventory
	end
	-- Restore owned doctrine instances (2026-10-20). Absent on pre-instance saves;
	-- establishment then mints instances from each unit.doctrineId (migration).
	if type(prog.doctrineInventory) == "table" then
		DoctrineInventoryService.ImportInventory(PLAYER_ID, prog.doctrineInventory)
	end
	-- Restore roster persistent state
	PersistentStateService.ImportState(PLAYER_ID, loadedSave.roster or {})
	-- Restore inventory
	InventoryService.ImportInventory(PLAYER_ID, loadedSave.inventory or {})
	-- Extract saved equipment assignments
	for unitId, unitData in pairs(loadedSave.roster or {}) do
		if unitData.equipSlots then
			savedEquipMap[unitId] = unitData.equipSlots
		end
		-- Extract saved race/trait data (Slice 4F)
		if unitData.raceId then
			savedRaceMap[unitId] = {
				raceId = unitData.raceId,
				perkIds = unitData.perkIds or {},
				drawbackIds = unitData.drawbackIds or {},
				-- Player-chosen 2D portrait (option B), restored onto the live unit below.
				portraitAssetId = unitData.portraitAssetId or nil,
				-- Player-chosen body/skin tint {r,g,b}, restored onto the live unit below.
				bodyColor = unitData.bodyColor or nil,
			}
		end
		-- Extract saved doctrine
		if unitData.doctrineId and unitData.doctrineId ~= "none" then
			savedDoctrineMap[unitId] = unitData.doctrineId
		end
		if unitData.doctrineInstanceId then
			savedDoctrineInstanceMap[unitId] = unitData.doctrineInstanceId
		end
		if unitData.selectedDoctrineSkill then
			savedDoctrineSkillMap[unitId] = unitData.selectedDoctrineSkill
		end
		if unitData.skillLoadout then
			savedSkillLoadoutMap[unitId] = unitData.skillLoadout
		end
		if unitData.statAllocation then
			savedStatAllocation[unitId] = unitData.statAllocation
		end
		if unitData.records then
			savedRecords[unitId] = unitData.records
		end
		if unitData.consumableSlots then
			savedConsumableSlots[unitId] = unitData.consumableSlots
		end
	end
	-- Slice 6: restore saved currency balance (Key 2) and guild/dispatch/explore
	-- progression (Key 3). All ride the EXISTING save payload; no second store.
	if loadedSave.currencies then
		CurrencyService.Import(PLAYER_ID, loadedSave.currencies)
	end
	if loadedSave.progression and loadedSave.progression.guild then
		GuildService.Import(PLAYER_ID, loadedSave.progression.guild)
	end
	if loadedSave.progression and loadedSave.progression.dispatch then
		DispatchService.Import(PLAYER_ID, loadedSave.progression.dispatch)
	end
	if loadedSave.progression and loadedSave.progression.party then
		PartyService.Import(PLAYER_ID, loadedSave.progression.party)
	end
	if loadedSave.progression and loadedSave.progression.explore then
		ExploreService.Import(PLAYER_ID, loadedSave.progression.explore)
	end
elseif loadErr then
	-- SaveService now refuses every Save for this player this session, so the fresh
	-- runtime state below can never overwrite the real save (save_data_contract).
	warn("[Main] Load failed: " .. loadErr .. " — playing on fresh runtime state; saving is DISABLED this session")
else
	print("[Main] No save found — new session")
end
-- Slice 6 Guild menu: restore the completed-battle counter and the identity of
-- units hired in earlier sessions (rides the existing progression payload, Key 3).
GuildMenuService.Import(PLAYER_ID, loadedSave and loadedSave.progression
	and loadedSave.progression.guildMenu or nil)

-- Helper: generate a weapon, add to inventory, equip on unit
local function equipGeneratedWeapon(unit, archetypeId, itemLevel, rarity, seed)
	-- If save was loaded, items are already in inventory — equip from there
	-- Priority: use saved slot assignment (instanceId), fall back to archetype match
	if hasSave then
		local slotMap = savedEquipMap[unit.id]
		if slotMap and slotMap.MainHand then
			local item = InventoryService.GetItem(PLAYER_ID, slotMap.MainHand)
			if item then
				EquipmentService.Equip(unit, item, "MainHand")
				print(string.format("[Main] Restored %s MainHand from save: %s", unit.name, slotMap.MainHand))
				-- Restore OffHand from save (if present)
				if slotMap and slotMap.OffHand then
					local offItem = InventoryService.GetItem(PLAYER_ID, slotMap.OffHand)
					if offItem then
						EquipmentService.Equip(unit, offItem, "OffHand")
						print("[Main] Restored " .. unit.name .. " OffHand from save: " .. slotMap.OffHand)
					end
				end
				return
			end
			warn(string.format("[Main] Saved MainHand item %s not found in inventory for %s — falling back to archetype", slotMap.MainHand, unit.name))
		end
		-- Fallback: match by archetype (legacy saves without equipSlots)
		local allItems = InventoryService.GetAllItems(PLAYER_ID)
		for _, item in ipairs(allItems) do
			if item.baseArchetypeId == archetypeId then
				EquipmentService.Equip(unit, item, "MainHand")
				return
			end
		end
		warn("[Main] No saved item found for archetype: " .. archetypeId)
	end
	local item = ItemGenerator.Generate({
		baseArchetypeId = archetypeId,
		itemLevel = itemLevel,
		rarity = rarity,
		seed = seed,
		sourceType = "Debug",
	})
	if not item then
		warn("[Main] Failed to generate weapon: " .. archetypeId)
		return
	end
	InventoryService.AddItem(PLAYER_ID, item)
	EquipmentService.Equip(unit, item, "MainHand")
end

local hero = UnitSchema.Create({
	id           = "unit_hero",
	name         = "Hero",
	level        = 25,
	raceId       = "RACE-HUMAN",
	side         = "Player",
	controller   = "Player",
	tileX        = 0,  -- set during deployment phase
	tileY        = 0,  -- set during deployment phase
	doctrineId   = "DOC-BERSERKER",
	skillIds     = { "skill_power_strike", "skill_sweeping_cut" },
})
-- The Hero is the player avatar (project_rules 114 / unit_schema is_avatar, DB 2026-10-16):
-- unique, cannot be dismissed or lost. Flagging the real unit makes is_avatar the source of
-- truth for dismissal protection; the unit_hero id check in GuildMenuService is now a redundant
-- safety net rather than the only guard.
hero.is_avatar = true
equipGeneratedWeapon(hero, "WPN-SWORD", 5, "Uncommon", 1001)

-- Starter off-hand shield (inventory only, not equipped)
if not hasSave then
	local starterShield = ItemGenerator.Generate({
		baseArchetypeId = "OFF-SHIELD",
		itemLevel = 5,
		rarity = "Common",
		seed = 1004,
		sourceType = "Debug",
	})
	if starterShield then
		InventoryService.AddItem(PLAYER_ID, starterShield)
		print("[Main] Added starter Shield to inventory: " .. starterShield.instanceId)
	else
		warn("[Main] Failed to generate starter Shield (OFF-SHIELD)")
	end
end

-- Starter armor items (inventory only, not equipped) — Slice 4G
-- ItemGenerator doesn't handle armor yet (4G.5), so create catalog instances directly.
if not hasSave then
	local STARTER_ARMOR = {
		{ id = "HD-001", slot = "Head",      seed = 3001 },
		{ id = "BD-001", slot = "Body",      seed = 3002 },
		{ id = "GL-001", slot = "Gloves",    seed = 3003 },
		{ id = "FT-001", slot = "Feet",      seed = 3004 },
		{ id = "AC-001", slot = "Accessory", seed = 3005 },
	}
	for _, def in ipairs(STARTER_ARMOR) do
		local aArch = ArmorData.GetByArchetypeId(def.id)
		if aArch then
			local armorInstance = {
				instanceId = "armor_" .. def.seed .. "_1",
				baseArchetypeId = def.id,
				itemLevel = 5,
				rarityId = "Common",
				bonusLines = {},
				bonusPassiveIds = {},
				generatorVersion = 1,
				sourceType = "Starter",
			}
			InventoryService.AddItem(PLAYER_ID, armorInstance)
			print(string.format("[Main] Added starter %s (%s) to inventory: %s", aArch.name, def.slot, armorInstance.instanceId))
		else
			warn("[Main] Starter armor archetype not found: " .. def.id)
		end
	end
end

-- Starter cards moved after cardInventory declaration (see block near line 1060)

local mage = UnitSchema.Create({
	id           = "unit_mage",
	name         = "Mage",
	level        = 25,
	raceId       = "RACE-ELF",
	side         = "Player",
	controller   = "Player",
	tileX        = 0,  -- set during deployment phase
	tileY        = 0,  -- set during deployment phase
	doctrineId   = "DOC-ARCANIST",
	skillIds     = { "skill_fire_bolt", "skill_healing_light" },
})
equipGeneratedWeapon(mage, "WPN-WAND", 5, "Uncommon", 1002)

local ranger = UnitSchema.Create({
	id           = "unit_ranger",
	name         = "Ranger",
	level        = 25,
	raceId       = "RACE-AVIAN",
	side         = "Player",
	controller   = "Player",
	tileX        = 0,  -- set during deployment phase
	tileY        = 0,  -- set during deployment phase
	doctrineId   = "DOC-RANGER",
	skillIds     = { "skill_crippling_shot", "skill_venom_strike" },
})
equipGeneratedWeapon(ranger, "WPN-CROSSBOW", 5, "Uncommon", 1003)

-- Perks & Flaws Phase 1: player roster units roll 1 perk + 1 flaw at first
-- appearance (data only, no gameplay effect yet). AssignIfEmpty never re-rolls a
-- unit that already has traits, so a loaded save (perkIds restored via savedRaceMap)
-- is preserved. Deterministic per-unit seed from the unit id.
for _, u in ipairs({ hero, mage, ranger }) do
	-- Restore saved traits FIRST so a loaded save wins; AssignIfEmpty then skips the
	-- re-roll for any unit that already has its saved perk+flaw.
	local saved = savedRaceMap[u.id]
	if saved then
		if saved.perkIds and #saved.perkIds > 0 then u.perkIds = saved.perkIds end
		if saved.drawbackIds and #saved.drawbackIds > 0 then u.drawbackIds = saved.drawbackIds end
		-- Restore the player's chosen 2D portrait so it shows in battle and on load.
		if saved.portraitAssetId then u.portraitAssetId = saved.portraitAssetId end
		-- Restore the player's chosen body/skin tint.
		if saved.bodyColor then u.bodyColor = saved.bodyColor end
	end
	local seed = 0
	for ci = 1, #u.id do seed = seed + string.byte(u.id, ci) end
	TraitRoller.AssignIfEmpty(u, Random.new(seed))
	-- Default 2D portrait (2026-10-15): give each starter a random race-matched face
	-- when it has none yet. The saved portrait (a loadout pick, or a previously-rolled
	-- default) is restored just above, so this assign-if-empty never overrides it.
	if not u.portraitAssetId then
		u.portraitAssetId = PortraitData.PickRandom(Random.new(seed + 4242), u.raceId)
	end
	-- Perks & Flaws Phase 2 (TRAIT-MAIN-REBUILD): traits now carry static stat effects
	-- (folded in EquipmentService.RebuildUnitStats) and were assigned AFTER this unit's
	-- weapon equip/rebuild -- rebuild once so effectiveStats / max HP / MP include them.
	-- A unit that was at full HP/MP stays full (Hardy / Deep Well raise the max).
	-- Idempotent: a unit with no Phase-2 trait effect rebuilds to identical values.
	local wasFullHp = u.currentHp ~= nil and u.maxHp ~= nil and u.currentHp >= u.maxHp
	local wasFullMp = u.currentMp ~= nil and u.maxMp ~= nil and u.currentMp >= u.maxMp
	EquipmentService.RebuildUnitStats(u)
	if wasFullHp then u.currentHp = u.maxHp end
	if wasFullMp then u.currentMp = u.maxMp end
end

-- TEST OVERRIDE: Ranger's Venom Strike uses weapon range instead of fixed 1
do
	local baseVenom = GameConstants.SKILLS["skill_venom_strike"]
	local rangerVenom = {}
	for k, v in pairs(baseVenom) do rangerVenom[k] = v end
	rangerVenom.id    = "skill_venom_strike_ranged"
	rangerVenom.range = ranger.weaponMaxRange or 1
	CommandService.RegisterSkill(rangerVenom)
	-- Swap in ranger's skill list
	for i, sid in ipairs(ranger.skillIds) do
		if sid == "skill_venom_strike" then ranger.skillIds[i] = "skill_venom_strike_ranged" end
	end
end

--------------------------------------------------
-- RESTORE ARMOR SLOTS FROM SAVE (Slice 4G)
-- After all weapons are equipped, restore armor slots
-- from savedEquipMap for each player unit.
--------------------------------------------------
if hasSave then
	local ARMOR_SLOT_NAMES = { "Head", "Body", "Gloves", "Feet", "Accessory" }
	for _, pUnit in ipairs({ hero, mage, ranger }) do
		local slotMap = savedEquipMap[pUnit.id]
		if slotMap then
			for _, armorSlot in ipairs(ARMOR_SLOT_NAMES) do
				local savedId = slotMap[armorSlot]
				if savedId then
					local armorItem = InventoryService.GetItem(PLAYER_ID, savedId)
					if armorItem then
						EquipmentService.Equip(pUnit, armorItem, armorSlot)
						print(string.format("[Main] Restored %s %s from save: %s", pUnit.name, armorSlot, savedId))
					else
						warn(string.format("[Main] Saved %s item %s not found for %s", armorSlot, savedId, pUnit.name))
					end
				end
			end
		end
	end
end

-- Procedurally generate the enemy squad from the selected quest's enemyTypes.
-- Deterministic: RNG derived from the generated map's seed (project rule:
-- same seed + content version = same result). Replaces the old hardcoded
-- Grunt/Pyro/Shaman trio (dev-locked 2026-09-26).

--------------------------------------------------
-- PER-ROUND STATE (loop vars; declared once, updated each round 2026-10-12)
--------------------------------------------------
local selectedQuestId
local selectedQuest
local quests
local generatedMap
local MAP_WIDTH
local MAP_HEIGHT
local playerSpawns
local enemySpawns
local questMapFolder
local activeQuest
local playerLevel
local oldMapFolder
local streamFocus


--------------------------------------------------
-- GAMEPLAY LOOP (2026-10-12): each iteration = one quest round.
-- One-time boot (requires, skills, units, save, roster) ran ABOVE, once.
-- Per round: quest board -> map -> enemies -> deploy -> battle -> return.
--------------------------------------------------

--------------------------------------------------
-- HUB / REWARD SIGNALS + PERSISTENT HANDLERS (one-time, 2026-10-12)
-- Moved out of the per-round loop so they connect ONCE (no per-round leak).
-- They read the current round's state/allUnitsList via the forward-declared
-- file-scope upvalues below, which the loop updates each iteration.
--------------------------------------------------
local hubContinueSignal = Instance.new("BindableEvent")
local rewardContinueSignal = Instance.new("BindableEvent")
-- Map-ready gate (2026-10-16 crash fix): the sortie opens with the Embark button locked
-- while the map generates. If an early StartBattle still reaches the server (client lock
-- race / stray trigger), committing into a half-built battle crashes. This authoritative
-- flag is false while a sortie's map is building and set true when MapBuildComplete fires;
-- StartBattle is IGNORED until then. Reset false at each sortie open.
local mapReadyForStart = false

-- forward-declared battle state (updated each round inside the loop)
local state
local BattleTurnController
local allUnitsList
local undeployConn
-- Initialized at BOOT (2026-10-13) as persistent tables so base actions (hire/loadout)
-- that fire before the loop reaches the per-round refill never hit a nil table. Each
-- round the loop CLEARS and refills these in place (table.clear) instead of replacing
-- the table, so the base's reference stays valid across rounds.
local playerUnits = {}
local cardInventory = { skillCards = {}, augmentCards = {} }
local doSave               -- fwd-declared; assigned inside the loop so dev actions at boot can call it

BattleEvents.StartBattle.OnServerEvent:Connect(function(player)
	if not mapReadyForStart then
		print("[Hub] StartBattle ignored — map not ready yet (early tap)")
		return
	end
	print("[Hub] Player ready to start battle")
	hubContinueSignal:Fire()
end)

BattleEvents.RewardContinue.OnServerEvent:Connect(function(player)
	print("[Hub] Player acknowledged rewards")
	rewardContinueSignal:Fire()
end)

if game:GetService("RunService"):IsStudio() then
	BattleEvents.DevCommand.OnServerEvent:Connect(function(player, cmd)
		if not cmd or type(cmd) ~= "table" then return end

		if cmd.action == "InstantWin" then
			print("[Dev] Instant Win triggered")
			for _, u in ipairs(allUnitsList) do
				if u.side == "Enemy" and u.isAlive then
					UnitSchema.Kill(u)
					clearTileOccupant(u.tileX, u.tileY)
					BattleEvents.UnitDefeated:FireAllClients({ unitId = u.id })
					print(string.format("[Dev] Killed %s", u.name))
				end
			end
			state.phase = "BattleOver"
			state.winner = "Player"
			BattleTurnController.ForceEndTurn()

		elseif cmd.action == "InstantLose" then
			print("[Dev] Instant Lose triggered")
			for _, u in ipairs(allUnitsList) do
				if u.side == "Player" and u.isAlive then
					UnitSchema.Kill(u)
					clearTileOccupant(u.tileX, u.tileY)
					BattleEvents.UnitDefeated:FireAllClients({ unitId = u.id })
					print(string.format("[Dev] Killed %s", u.name))
				end
			end
			state.phase = "BattleOver"
			state.winner = "Enemy"
			BattleTurnController.ForceEndTurn()

		elseif cmd.action == "KillAtTile" then
			local tx, ty = cmd.tileX, cmd.tileY
			if not tx or not ty then return end
			for _, u in ipairs(allUnitsList) do
				if u.tileX == tx and u.tileY == ty and u.isAlive then
					print(string.format("[Dev] Kill unit at (%d,%d): %s HP:%d->0", tx, ty, u.name, u.currentHp))
					UnitSchema.Kill(u)
					clearTileOccupant(u.tileX, u.tileY)
					BattleEvents.UnitDefeated:FireAllClients({ unitId = u.id })
				end
			end
		elseif cmd.action == "DeleteSave" then
			local ok, err = SaveService.Delete(PLAYER_ID)
			if ok then
				print("[Dev] Save deleted for " .. PLAYER_ID .. " -- restart to begin fresh")
			else
				warn("[Dev] Delete failed: " .. (err or "unknown"))
			end

		elseif cmd.action == "DevAddGold" then
			-- Dev: +10,000 gold, then save so it survives a restart.
			local bal = CurrencyService.Credit(PLAYER_ID, { gold = 10000 })
			print(string.format("[Dev] +10000 gold -> balance %d", bal and bal.gold or -1))
			doSave()

		elseif cmd.action == "DevGrantAllCards" then
			-- Dev (Studio only): grant 1 copy of every skill card (SKL-) + every augment (AUG-)
			-- to the card inventory, and 1 loose copy of every doctrine to the doctrine inventory
			-- (NOT as a skill card). Enumerated LIVE from the content modules so any new content
			-- (e.g. the trap-deploy skills) is covered automatically. Idempotent: skill/augment
			-- cards are set to at least 1 (never stacked on repeat press); a doctrine is minted
			-- only when no loose copy is already owned. Doctrine-exclusive DOC- SKILLS in SkillData
			-- are intentionally skipped (they arrive bundled with their doctrine, not as cards).
			local nSk, nAug, nDoc = 0, 0, 0
			for id, def in pairs(SkillData) do
				if type(def) == "table" and def.name and string.sub(id, 1, 4) == "SKL-" then
					if not cardInventory.skillCards[id] then
						cardInventory.skillCards[id] = 1
						nSk += 1
					end
				end
			end
			for id, def in pairs(AugmentData) do
				if type(def) == "table" and def.name then
					if not cardInventory.augmentCards[id] then
						cardInventory.augmentCards[id] = 1
						nAug += 1
					end
				end
			end
			local looseStacks = DoctrineInventoryService.GetLooseStacks(PLAYER_ID)
			for id, def in pairs(DoctrineData) do
				if type(def) == "table" and def.name and not looseStacks[id] then
					DoctrineInventoryService.Mint(PLAYER_ID, id)
					nDoc += 1
				end
			end
			print(string.format("[Dev] Grant-all: +%d skill cards, +%d augments, +%d doctrines", nSk, nAug, nDoc))
			doSave()

		elseif cmd.action == "DevResetUGCRecords" then
			-- Dev: free trials usable again + rent price back to base. Then save.
			local t, r = UGCService.DevResetTrialRentRecords(PLAYER_ID)
			print(string.format("[Dev] UGC records reset (%d trials, %d rent prices)", t, r))
			doSave()

		elseif cmd.action == "SaveNow" then
			local ok, err = doSave()
			if ok then
				print("[Dev] Manual save successful")
			else
				warn("[Dev] Manual save failed: " .. (err or "unknown"))
			end

		elseif cmd.action == "ViewMode" then
			local mode = cmd.mode
			if mode ~= "TERRAIN" and mode ~= "REGION" and mode ~= "TEMPLATE" then
				warn("[Dev] ViewMode: invalid mode '" .. tostring(mode) .. "'. Use TERRAIN, REGION, or TEMPLATE.")
				return
			end
			local folder = workspace:FindFirstChild("TemplateViewerMap")
			if not folder then
				warn("[Dev] ViewMode: no TemplateViewerMap in workspace")
				return
			end
			MapRenderer.SetViewMode(folder, mode)
			print("[Dev] View mode: " .. mode)

		elseif cmd.action == "TerrainRender" then
			-- Terrain-render switcher (hybrid): the client swaps Per-tile/Mesh visuals
			-- instantly on its own. Only VOXEL needs the server, because voxel writes
			-- (workspace.Terrain) are server-authoritative. Re-running SetViewMode in
			-- TERRAIN mode clears + refills the voxel terrain and resets natural tile
			-- Parts to hidden — which replicates back to all clients.
			local folder = workspace:FindFirstChild("TemplateViewerMap")
			if not folder then
				warn("[Dev] TerrainRender: no TemplateViewerMap in workspace")
				return
			end
			if cmd.mode == "Voxel" then
				-- Rebuild voxel terrain (clears + refills; hides natural tile Parts).
				MapRenderer.SetViewMode(folder, "TERRAIN")
				print("[Dev] Terrain render: Voxel (server rebuilt voxel terrain)")
			elseif cmd.mode == "PerTile" then
				-- Clear voxels and SHOW the tile Parts as the visible ground.
				MapRenderer.ClearVoxelsForPerTile(folder)
				print("[Dev] Terrain render: PerTile (server cleared voxels, tile Parts shown)")
			elseif cmd.mode == "Mesh" then
				-- Clear voxels and HIDE the tile Parts — the client mesh is the surface.
				-- (Showing tile Parts here caused studs/shine/floating clutter under the mesh.)
				MapRenderer.ClearVoxelsHideTiles(folder)
				print("[Dev] Terrain render: Mesh (server cleared voxels, tile Parts hidden)")
			end

		elseif cmd.action == "Regenerate" then
			-- Get current biome/template from existing map or from command.
			local currentFolder = workspace:FindFirstChild("TemplateViewerMap")
			local currentBiome = currentFolder and currentFolder:GetAttribute("BiomeId") or "Plains"
			local currentTemplate = currentFolder and currentFolder:GetAttribute("TemplateId") or "T01"

			local biome    = (cmd.biome and cmd.biome ~= "") and cmd.biome or currentBiome
			local template = (cmd.template and cmd.template ~= "") and cmd.template or currentTemplate

			print(string.format("[Dev] Regenerating: biome=%s template=%s", biome, template))

			-- Clear cache and generate new map.
			MapService.ClearCache()
			local ok, newMap = pcall(MapService.Generate, biome, template, nil)
			if not ok then
				warn("[Dev] Regenerate failed: " .. tostring(newMap))
				return
			end

			GameConstants.SetGeneratedMap(newMap)

			-- Destroy old map and render new one.
			if currentFolder then
				currentFolder:Destroy()
			end

			local newFolder = MapRenderer.Render(newMap, "TERRAIN")
			newFolder.Parent = workspace
			mapFolder = newFolder

			-- AD BILLBOARD image cycle (2026-10-15): (re)start the seeded ad-image cycle for
			-- the regenerated map. StartAdImageCycle cancels any prior cycle first, so the old
			-- map's loop (whose folder was Destroyed above) is replaced cleanly. Seeded start
			-- from newMap.seed via a dedicated derived stream (no map-gen RNG perturbation);
			-- empty/missing "Billboard Ad Images" folder -> blank faces, no crash, no thread.
			MapRenderer.StartAdImageCycle(newFolder, newMap.seed)

			-- Update module-level map state so services use the new map.
			generatedMap  = newMap
			MAP_WIDTH     = newMap.width
			MAP_HEIGHT    = newMap.height
			playerSpawns  = newMap.deploymentZones.player
			enemySpawns   = newMap.deploymentZones.enemy

			CommandService.SetMapDimensions(MAP_WIDTH, MAP_HEIGHT)
			DisplacementService.SetMapDimensions(MAP_WIDTH, MAP_HEIGHT)
			-- Tile effects belong to the old map: reset (also resizes bounds) and, if a
			-- battle is already running, re-seed the new map's chasm-floor effects.
			-- Tell clients the old map's tile effects are gone (Init wipes them silently).
			for _, eff in pairs(TileEffectService.GetAllEffects()) do
				if eff.tileX and eff.tileY then BattleVisualBroadcaster.TileEffectRemoved(eff.tileX, eff.tileY, eff.id) end
			end
			TileEffectService.Init(MAP_WIDTH, MAP_HEIGHT)
			if state then
				TileEffectService.SeedFloorEffects(GameConstants.FLOOR_EFFECTS)
				-- Slice 5 map objects: the new map has its own placed objects —
				-- refresh state.objects and recompute auras against the new layout
				-- (old banners/stands are gone; new ones may cover deployed units).
				state.objects = newMap.objects or {}
				-- OBS Phase 2a: re-seed object HP for the regenerated map's objects.
				ObjectEffectService.InitObjectHp(state)
				ObjectEffectService.ReconcileAuras(state.units, state)
			end

			-- Battlefield events on regenerate: re-pick for the new map.
			-- GUARD (2026-10-20): only when a battle is actually running. Regenerate can be
			-- used during the DEPLOYMENT phase, before BattleCoordinator.CreateBattleState
			-- assigns `state` at battle start — so `state` is nil then. The old unguarded
			-- `do` block did `state.units` here and CRASHED (Main:1037 "attempt to index
			-- nil with 'units'"), which aborted the rest of this handler — the MapDataSync
			-- below AND the unit reposition — leaving units stranded on their OLD tiles over
			-- the NEW terrain (they looked buried/stuck). No battle yet = no events to
			-- re-pick, so skipping this block during deployment is correct. Mirrors the
			-- `if state then` guard on the tile-effects block just above.
			if state then
				local ec = 0
				for _, u in ipairs(state.units) do if u.side == "Enemy" and u.isAlive then ec = ec + 1 end end
				state.enemyCountAtStart = ec
				state.playerDeployTiles = (generatedMap and generatedMap.deploymentZones and generatedMap.deploymentZones.player) or {}
				state.enemyDeployTiles = (generatedMap and generatedMap.deploymentZones and generatedMap.deploymentZones.enemy) or {}  -- Fear destination + terrain protection (2026-10-26)
				-- Seed from the map seed (varies per battle). Was state.ct + 70007, and ct is 0 at
				-- battle start, so every battle rolled the SAME events (always Fog Spirit).
				-- Per-battle seed, stored on state so the round/turn/weather rolls vary per battle too.
				state.battleSeed = (generatedMap and generatedMap.seed) or os.time()
				local bfRng = Random.new(state.battleSeed + 70007)
				BattlefieldEventService.SelectEventsForBattle(state, activeQuest and activeQuest.biome or nil, bfRng)
			end

			-- Sync terrain, elevation, blockers, AND dimensions to client.
			BattleEvents.MapDataSync:FireAllClients({
				terrainGrid   = newMap.terrainGrid,
				elevationGrid = newMap.elevationGrid,
				objectGrid    = newMap.objectGrid,
				blockers      = newMap.blockers,
				mapWidth      = MAP_WIDTH,
				mapHeight     = MAP_HEIGHT,
			})

			-- DEV-TOOL: Reposition units to new deployment anchors.
			local newPlayerAnchors = newMap.deploymentZones.player
			local newEnemyAnchors  = newMap.deploymentZones.enemy
			local pi, ei = 1, 1
			for _, u in ipairs(allUnitsList) do
				clearTileOccupant(u.tileX, u.tileY)
				if u.side == "Player" then
					local a = newPlayerAnchors[pi] or newPlayerAnchors[1]
					u.tileX = a.x
					u.tileY = a.y
					pi = pi + 1
				else
					local a = newEnemyAnchors[ei] or newEnemyAnchors[1]
					u.tileX = a.x
					u.tileY = a.y
					ei = ei + 1
				end
				setTileOccupant(u.tileX, u.tileY, u.name, "Unit (" .. u.side .. ")", "Blocking")
				-- Notify client to move the token.
				BattleEvents.UnitMoved:FireAllClients({
					unitId = u.id,
					tileX  = u.tileX,
					tileY  = u.tileY,
				})
			end

			print(string.format("[Dev] Regenerated: biome=%s template=%s seed=%d (%dx%d, %d units repositioned)",
				biome, template, newMap.seed, MAP_WIDTH, MAP_HEIGHT, #allUnitsList))

		elseif cmd.action == "GrantStatus" then
			-- Apply a buff/debuff to the selected unit (by tile). Repeatable.
			local tx, ty, sid = cmd.tileX, cmd.tileY, cmd.statusId
			if not tx or not ty or type(sid) ~= "string" then
				warn("[Dev] GrantStatus: need tileX, tileY, statusId")
				return
			end
			local hit = false
			for _, u in ipairs(allUnitsList) do
				if u.tileX == tx and u.tileY == ty and u.isAlive then
					StatusService.ApplyStatus(u, sid, u.id)
					-- D4 fix 2026-10-04: immediate feedback — rebuild stats (so stat-
					-- changing statuses apply now, not next turn) + refresh the client.
					if EquipmentService.RebuildUnitStats then EquipmentService.RebuildUnitStats(u) end
					local inst
					for _, si in ipairs(u.statusInstances or {}) do
						if si.id == sid then inst = si; break end
					end
					if inst and BattleVisualBroadcaster.StatusApplied then
						BattleVisualBroadcaster.StatusApplied(u, sid, inst.remainingTurns, nil)
					end
					if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(u) end
					print(string.format("[Dev] GrantStatus %s -> %s", sid, u.name))
					hit = true
				end
			end
			if not hit then warn("[Dev] GrantStatus: no living unit at tile") end

		elseif cmd.action == "RemoveStatus" then
			-- Remove one status (or all) from the selected unit.
			local tx, ty, sid = cmd.tileX, cmd.tileY, cmd.statusId
			if not tx or not ty then return end
			for _, u in ipairs(allUnitsList) do
				if u.tileX == tx and u.tileY == ty and u.isAlive then
					if sid == "ALL" or not sid then
						-- Snapshot ids first: RemoveStatus mutates statusInstances, so
						-- iterating it live would skip every other entry (D2 fix).
						local ids = {}
						for _, inst in ipairs(u.statusInstances or {}) do
							ids[#ids + 1] = inst.id
						end
						-- A1 fix (2026-10-04): only broadcast + count a removal that actually
						-- happened. RemoveStatus returns false for hard-locked statuses (e.g.
						-- Snow Storm Frozen), so the client no longer shows a false "-Frozen".
						local removed = 0
						for _, id in ipairs(ids) do
							if StatusService.RemoveStatus(u, id) then
								removed = removed + 1
								if BattleVisualBroadcaster.StatusExpired then BattleVisualBroadcaster.StatusExpired(u, id) end
							end
						end
						print(string.format("[Dev] RemoveStatus ALL (%d removed) -> %s", removed, u.name))
					else
						if StatusService.RemoveStatus(u, sid) then
							if BattleVisualBroadcaster.StatusExpired then BattleVisualBroadcaster.StatusExpired(u, sid) end
							print(string.format("[Dev] RemoveStatus %s -> %s", sid, u.name))
						else
							print(string.format("[Dev] RemoveStatus %s FAILED (locked?) -> %s", sid, u.name))
						end
					end
					-- D4 fix: rebuild stats + refresh client immediately after removal.
					if EquipmentService.RebuildUnitStats then EquipmentService.RebuildUnitStats(u) end
					if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(u) end
				end
			end

		elseif cmd.action == "EventFire" then
			-- Dev: add an event now, or change the current one (ends it first).
			if not state then warn("[Dev] EventFire: no battle running"); return end
			local name = cmd.eventName
			if type(name) ~= "string" or name == "" then warn("[Dev] EventFire: need eventName"); return end
			BattlefieldEventService.DevFireEvent(state, name, Random.new(os.clock() * 1000))

		elseif cmd.action == "EventEnd" then
			-- Dev: end the current event (its units leave the map).
			if not state then warn("[Dev] EventEnd: no battle running"); return end
			local ended = BattlefieldEventService.DevEndActiveEvent(state)
			if ended then
				if BattleVisualBroadcaster.BattlefieldEventAnnounced then
					BattleVisualBroadcaster.BattlefieldEventAnnounced(nil, true)
				end
			else
				print("[Dev] EventEnd: no active event")
			end

		elseif cmd.action == "SetWeather" then
			-- Force a weather/crisis condition immediately (dev only).
			local cond = cmd.condition
			if type(cond) ~= "string" or cond == "" then
				warn("[Dev] SetWeather: need condition")
				return
			end
			local ok = WeatherService.ForceCondition(cond, state)
			if ok then print("[Dev] SetWeather -> " .. cond) end

		elseif cmd.action == "SpawnUnit" or cmd.action == "SpawnGroup" then
			-- Spawn one or more units (Player ally / Enemy / Neutral) near the selected
			-- tile. D3 fix 2026-10-04: never stack on an occupied / off-map / impassable
			-- tile — a spiral search finds the nearest free, in-bounds, walkable tile.
			local tx, ty = cmd.tileX, cmd.tileY
			local tier = cmd.tier or "Grunt"
			local side = cmd.side or "Enemy"
			if not tx or not ty then
				warn("[Dev] Spawn: need tileX, tileY (select a tile/unit first)")
				return
			end
			if side ~= "Enemy" and side ~= "Neutral" and side ~= "Player" then side = "Enemy" end
			local lvl = cmd.level or 1
			local spawnSide = (side == "Player") and "Neutral" or side
			local count = (cmd.action == "SpawnGroup") and math.clamp(tonumber(cmd.count) or 3, 1, 6) or 1
			local devRng = Random.new(os.clock() * 1000)

			-- Build an occupancy set of living units (by tile key) so we never stack.
			local occupied = {}
			for _, u in ipairs(allUnitsList) do
				if u.isAlive then occupied[u.tileX .. "," .. u.tileY] = true end
			end
			local function tileFree(x, y)
				if x < 1 or y < 1 or x > MAP_WIDTH or y > MAP_HEIGHT then return false end
				if GameConstants.IsImpassableTerrain and GameConstants.IsImpassableTerrain(x, y) then return false end
				if GameConstants.IsBlocked and GameConstants.IsBlocked(x, y) then return false end
				return not occupied[x .. "," .. y]
			end
			-- Spiral outward from the anchor to find the next free tile (radius 0..6).
			local function findFreeSpawnTile(ax, ay)
				for r = 0, 6 do
					for dx = -r, r do
						for dy = -r, r do
							if math.max(math.abs(dx), math.abs(dy)) == r then
								local x, y = ax + dx, ay + dy
								if tileFree(x, y) then return x, y end
							end
						end
					end
				end
				return nil
			end

			local spawned = 0
			for _ = 1, count do
				local sx, sy = findFreeSpawnTile(tx, ty)
				if not sx then
					warn("[Dev] Spawn: no free tile near anchor")
					break
				end
				local unit = EnemyGenerator.SpawnReinforcement(
					{ type = tier, level = lvl }, { x = sx, y = sy }, state, devRng, spawnSide, cmd.raceOverride)
				if unit then
					if side == "Player" then unit.side = "Player"; unit.controller = "AI" end
					occupied[unit.tileX .. "," .. unit.tileY] = true
					setTileOccupant(unit.tileX, unit.tileY, unit.name, "Unit (" .. unit.side .. ")", "Blocking")
					if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitSpawned then
						BattleVisualBroadcaster.UnitSpawned(unit)
					end
					spawned = spawned + 1
				end
			end
			print(string.format("[Dev] Spawn %s x%d (%s) near (%d,%d) -> %d spawned", side, count, tier, tx, ty, spawned))

		elseif cmd.action == "SpawnObject" then
			-- Place a map object (blocker or interactable) on the selected tile.
			-- Uses the live PlaceObjectInstance path (renders + guards against stacking).
			local tx, ty, objType = cmd.tileX, cmd.tileY, cmd.objectType
			if not tx or not ty or type(objType) ~= "string" then
				warn("[Dev] SpawnObject: need tileX, tileY, objectType")
				return
			end
			if tx < 1 or ty < 1 or tx > MAP_WIDTH or ty > MAP_HEIGHT then
				warn("[Dev] SpawnObject: tile off-map")
				return
			end
			local inst = ObjectEffectService.PlaceObjectInstance(state, objType, tx, ty)
			if inst then
				print(string.format("[Dev] SpawnObject %s at (%d,%d) -> %s", objType, tx, ty, inst.id))
			else
				warn(string.format("[Dev] SpawnObject failed (tile occupied by another object?) %s (%d,%d)", objType, tx, ty))
			end
		end
	end)
	print("[Dev] DevCommand handler active (Studio only)")
end

BattleEvents.InspectUnitRequest.OnServerEvent:Connect(function(playerObj, unitId)
	-- Find the unit. During a live battle it is in state.units; during the DEPLOYMENT
	-- phase the battle state does not exist yet (CreateBattleState runs at battle start),
	-- so fall back to allUnitsList -- the same fully-built unit objects (stats, equipment,
	-- skills) that later become state.units. This lets the detailed inspector window work
	-- during deployment with no second data path. (2026-10-15)
	local unit = nil
	local searchList = (state and state.units) or allUnitsList or {}
	for _, u in ipairs(searchList) do
		if u.id == unitId then unit = u; break end
	end
	if not unit then return end

	-- Build equipment data
	local equipData = {}
	local slots = unit.equipmentSlots or {}
	for slotName, itemInst in pairs(slots) do
		if itemInst then
			local profile = EquipmentService.GetEffectiveWeaponProfile(itemInst)
			local _wArch = WeaponData.GetByArchetypeId(itemInst.baseArchetypeId)
			local _aArch = not _wArch and ArmorData.GetByArchetypeId(itemInst.baseArchetypeId) or nil
			local _icon = (_wArch and _wArch.icon) or (_aArch and _aArch.icon) or nil
			equipData[slotName] = {
				name      = (_wArch and _wArch.name) or (_aArch and _aArch.name) or "Unknown",
				-- Item instances store rarity as `rarityId` (ItemGenerator) — reading
				-- `.rarity` always fell back to "Common". Same field GetInventoryData uses.
				rarity    = itemInst.rarityId or itemInst.rarity or "Common",
				isWeapon  = _wArch and (_wArch.category == "Weapon") or false,
				isArmor   = _aArch ~= nil,
				category  = (_wArch and _wArch.category) or (_aArch and "Armor") or nil,
				slot      = (_aArch and _aArch.slot) or nil,
				hp        = (_aArch and ArmorData.GetScaledProfile(itemInst.baseArchetypeId, itemInst.itemLevel) or {}).hp or 0,
				mp        = (_aArch and ArmorData.GetScaledProfile(itemInst.baseArchetypeId, itemInst.itemLevel) or {}).mp or 0,
				projectileType = (_wArch and _wArch.projectileType) or nil,
				element   = _wArch and WeaponData.GetInstanceElement(itemInst) or nil,
				archPassiveName = (_aArch and _aArch.passiveName) or nil,
				archPassiveDesc = (_aArch and _aArch.passiveDesc) or nil,
				itemLevel = itemInst.itemLevel or 1,
				archetype = itemInst.archetype or "Unknown",
				handClass = itemInst.handClass or "1H",
				damage    = profile and profile.damage or 0,
				wt        = profile and profile.wt or 0,
				rtDelay   = profile and profile.rtDelay or 0,
				defense   = profile and profile.defense or 0,
				minRange  = profile and profile.minRange or 1,
				maxRange  = profile and profile.maxRange or 1,
				pattern   = profile and profile.pattern or "Single",
				bonusLines = itemInst.bonusLines or {},
				resolvedBonus = (function() local s, p = ItemDisplay.resolveItemBonuses(itemInst); return {stats = s, passives = p} end)(),
				passiveName   = itemInst.nativePassiveId or nil,
				passiveDesc   = itemInst.nativePassiveId and WeaponData.GetPassiveDesc(itemInst.nativePassiveId) or nil,
				bonusPassive  = itemInst.bonusPassive or nil,
				flavor        = (_wArch and _wArch.flavor) or (_aArch and _aArch.flavor) or nil,
				icon          = _icon,
				displayName   = itemInst.displayName or nil,
				-- Same entry GetInventoryData sends -> client maps it with the loadout's mapper.
				invEntry      = ItemDisplay.buildItemEntry(itemInst),
			}
		end
	end

	-- Build skill data
	local skillsData = {}
	-- Build a slot-index-to-augments map from the skill loadout
	local slotAugments = {}
	local loadout = unit.skillLoadout or {}
	-- Slot 1: doctrine augments
	slotAugments[1] = unit.doctrineAugments or {}
	-- Slots 2-4: skill card augments
	for i = 2, 4 do
		local key = "slot" .. i
		local slotData = loadout[key]
		slotAugments[i] = slotData and slotData.augments or {}
	end
	slotAugments[5] = {} -- locked slot

	local skillSlotIdx = 0
	for _, sid in ipairs(unit.skillIds or {}) do
		skillSlotIdx = skillSlotIdx + 1
		local skillKey = string.upper(sid):gsub("SKILL_", "SKL-"):gsub("_", "-")
		local fullData = SkillData[skillKey]
		local regDef = CommandService.GetSkill(sid)
		local skillPower = regDef and regDef.power or 0
		table.insert(skillsData, {
			id           = sid,
			name         = regDef and regDef.name or (fullData and fullData.name or sid),
			tags         = fullData and fullData.tags or (regDef and regDef.tags or {}),
			targetRules  = fullData and fullData.targetRules or (regDef and regDef.targetRules or ""),
			range        = regDef and regDef.range or 1,
			pattern      = fullData and fullData.pattern or (regDef and regDef.pattern or "Single"),
			mpCost       = regDef and CommandService.GetSkillMpCost(unit, regDef, regDef.id or sid) or 0, -- level-based (2026-10-07)
			-- rtCost shown MUST match the charge path (CommandService): fixed/level skills
			-- use their authored cost; weapon-WT skills use (base component + weapon WT) × N.
			rtCost       = (function()
				if not regDef then return 0 end
				local lvl = (unit.equipmentSlots and unit.equipmentSlots.MainHand and unit.equipmentSlots.MainHand.itemLevel) or 1
				local augRt = CommandService.GetAugmentRtMultiplier(unit, regDef.id or sid)  -- e.g. Shared Resolve x2
				local fx = GameConstants.CalcFixedSkillRt(regDef.id or sid, lvl)
				if fx then return math.round(fx * augRt) end
				if regDef.rtMult then
					local baseComp = StatusService.GetModifiedBaseRt(unit) * GameConstants.BASIC_ATTACK_RT_FACTOR
					local wWt = GameConstants.CalcEffectiveWt(unit.weaponWt or 10, (unit.effectiveStats or {}).STR or 10)
					-- Same rounding order as the charge (CommandService): skill RT first, then the augment x.
					return math.round(math.round((baseComp + wWt) * regDef.rtMult) * augRt)
				end
				return math.round((regDef.rtCost or 0) * augRt)
			end)(),
			channelTime  = regDef and regDef.channelTime or 0,
			power        = skillPower,
			isHealing    = regDef and regDef.isHealing or false,
			powerFormula = fullData and fullData.powerFormula or "",
			mpCostFormula = fullData and fullData.mpCostFormula or "",
			rtCostFormula = fullData and fullData.rtCostFormula or "",
			effects      = fullData and fullData.effects or "",
			specialRules = fullData and fullData.specialRules or "",
			icon         = fullData and fullData.icon or nil,
			description  = fullData and fullData.description or nil,
		})
		-- Attach augments for this skill slot
		local augIds = slotAugments[skillSlotIdx] or {}
		local augList = {}
		-- Use numeric loop (not ipairs) — augment arrays may be sparse (slot 2 filled, slot 1 empty)
		for ai = 1, 2 do
			local augId = augIds[ai]
			if not augId then continue end
			local augDef = AugmentData[augId]
			if augDef then
				table.insert(augList, { id = augId, name = augDef.name or augId, icon = augDef.icon or nil, description = augDef.description or "" })
			else
				table.insert(augList, { id = augId, name = augId, icon = nil, description = "" })
			end
		end
		skillsData[#skillsData].augments = augList
		-- Raw power (presentation-only, BEFORE target defense/hit quality/facing).
		-- Uses the SAME shared helpers as CombatResolver, so it can't drift from combat.
		-- (Old code read derivedStats.attackPower, which is never populated -> always 0.)
		if regDef then
			local isHeal = regDef.isHealing
			skillsData[#skillsData].estimatedDamage = (not isHeal) and math.round(CombatResolver.EstimateSkillPower(unit, regDef)) or nil
			skillsData[#skillsData].estimatedHeal   = isHeal and math.round(CombatResolver.EstimateHealPower(unit, regDef)) or nil
		end
	end

	-- Build full response
	-- Build status summary
	local rawSummary = StatusService.GetStatusSummary(unit)
	local statusSummary = {}
	for _, entry in ipairs(rawSummary) do
		local sid = entry.id
		local sDef = sid and GameConstants.STATUSES[sid] or nil
		local inst = nil
		for _, si in ipairs(unit.statusInstances or {}) do
			if si.id == sid then inst = si; break end
		end
		table.insert(statusSummary, {
			id = sid,
			remainingTurns = entry.remainingTurns or (sDef and sDef.duration),
			remainingCt = inst and inst.remainingCt or nil,
			kind = sDef and sDef.kind or "Debuff",
			stacks = inst and inst.stacks and inst.stacks > 1 and inst.stacks or nil,
			nextDamage = entry.nextDamage,
			storedBurn = entry.storedBurn,
		})
	end

	local response = {
		unitId       = unit.id,
		name         = unit.name,
		side         = unit.side,
		isAlive      = unit.isAlive ~= false,
		level        = unit.level or 1,
		raceId       = unit.raceId or nil,  -- placeholder: race system not yet implemented
		-- Portrait face image for the detailed inspector (enemy/neutral/NPC only;
		-- nil for player units and summons → inspector shows the initials box).
		portraitAssetId = unit.portraitAssetId,
		racePassiveName   = nil,  -- populated below if race assigned
		racePassiveEffect = nil,
		tileX        = unit.tileX,
		tileY        = unit.tileY,
		currentHp    = unit.currentHp,
		maxHp        = unit.maxHp,
		currentMp    = unit.currentMp,
		maxMp        = unit.maxMp,
		currentAp    = unit.currentAp or 0,
		remainingRt  = unit.remainingRt or 0,
		primaryStats = unit.primaryStats,
		derivedStats = unit.derivedStats,
		equipment    = equipData,
		skills       = skillsData,
		consumables  = (function()
			-- Equipped consumable slots (same data source as the turn prompt).
			local list = {}
			local unlocked = unit.consumableSlotCount or 3
			local maxSlots = unit.maxConsumableSlots or 6
			for idx = 1, maxSlots do
				local sd = unit.consumableSlots and unit.consumableSlots[idx]
				if sd and sd.consumableId then
					local cd = ConsumableData.GetById(sd.consumableId)
					table.insert(list, {
						slotIndex = idx,
						consumableId = sd.consumableId,
						name = cd and cd.name or sd.consumableId,
						category = cd and cd.category or "",
						icon = cd and cd.icon or nil,
						currentCharges = sd.currentCharges or 0,
						maxCharges = sd.maxCharges or (cd and cd.maxCharges) or 0,
						rtCost = cd and cd.rtCost or 0,
						range = cd and cd.range or 0,
						targetRules = cd and cd.targetRules or "",
						locked = false,
					})
				elseif idx <= unlocked then
					table.insert(list, { slotIndex = idx, empty = true })
				end
			end
			return list
		end)(),
		statuses     = statusSummary,
		doctrineId   = unit.doctrineId,
		doctrine     = unit.doctrineId and DoctrineData[unit.doctrineId] or nil,
	}

	-- Populate race passive if race is assigned
	local raceEntry = unit.raceId and RaceData and RaceData.GetRace(unit.raceId) or nil
	if raceEntry then
		response.raceName = raceEntry.name
		response.racePassiveName = raceEntry.passiveName
		response.racePassiveEffect = raceEntry.passiveEffect
	end

	-- Perks & Flaws Phase 1: resolve the unit's perk + flaw ids to display objects
	-- (name/tier/effect) via TraitData. Lookup is by trait_id (names can duplicate).
	if TraitData then
		local pid = unit.perkIds and unit.perkIds[1]
		local fid = unit.drawbackIds and unit.drawbackIds[1]
		if pid then response.perk = TraitData.GetTrait(pid) end
		if fid then response.flaw = TraitData.GetTrait(fid) end
	end

	BattleEvents.InspectUnitResponse:FireClient(playerObj, response)
end)

-- Move-target attack-range preview (on-demand, 2026-10-17). The client fires
-- this when the player selects a prospective move-destination tile; we reply
-- with the attack footprint FROM that tile only. This replaces precomputing
-- attackTiles for every move candidate in the turn prompt (payload reduction
-- per Tester NET note). Server stays the reach authority (ARC-001/SEC-002):
-- the client sends only the tile it is considering and renders what we return.
BattleEvents.AttackRangeRequest.OnServerEvent:Connect(function(playerObj, data)
	-- Only answer for the active unit's own open turn; ignore anything else.
	if not state or state.phase ~= "TurnOpen" or not state.activeUnit then return end
	if type(data) ~= "table" then return end
	local tx, ty = data.tileX, data.tileY
	if type(tx) ~= "number" or type(ty) ~= "number" then return end
	if tx < 1 or ty < 1 or tx > MAP_WIDTH or ty > MAP_HEIGHT then return end

	local tiles = TargetingService.GetAttackTilesFromOrigin(
		state.activeUnit, state.units, tx, ty, MAP_WIDTH, MAP_HEIGHT
	)
	BattleEvents.AttackRangeResponse:FireClient(playerObj, {
		tileX = tx, tileY = ty, attackTiles = tiles,
	})
end)

-- Map Details panel (2026-10-17). Read-only snapshot of the current battle for
-- the player's Map Details button: quest info, optional quests, a LIVE "if you
-- win" gold tally, and the victory loot range. Rolls/commits NOTHING — gold and
-- loot still finalize only at battle end (user's determinism + freeze-tally +
-- revoke-on-defeat rulings). The gold tally reuses computeBattleGold so it can
-- never drift from the real payout; it is computed at the VICTORY rate and
-- labeled "if you win" on the client, since a defeat keeps only 50% kill gold.
BattleEvents.MapDetailsRequest.OnServerEvent:Connect(function(playerObj)
	if not state or state.phase ~= "TurnOpen" or not state.activeUnit then return end

	-- Live gold at the victory rate (kill gold accrues as enemies fall; quest +
	-- completion gold are the fixed "on victory" portion).
	local gb = computeBattleGold(allUnitsList, playerUnits, activeQuest, true)
	local lootMin, lootMax = 1, 2
	if RewardService.GetRewardCountRange then
		lootMin, lootMax = RewardService.GetRewardCountRange()
	end

	-- Quest details (exist today). Minimal fields; client formats them.
	local quest = nil
	if activeQuest then
		quest = {
			name = activeQuest.name,
			biome = activeQuest.biome,
			recommendedLvl = activeQuest.recommendedLvl,
			enemyCount = activeQuest.enemyCount,
			questType = activeQuest.questType,
			condition = activeQuest.condition,
		}
	end

	-- Optional quests surfaced mid-battle (may be empty; generated by events).
	local optional = {}
	for _, oq in ipairs((state.pendingOptionalQuests) or {}) do
		optional[#optional + 1] = { name = oq.name, biome = oq.biome, recommendedLvl = oq.recommendedLvl }
	end

	BattleEvents.MapDetailsResponse:FireClient(playerObj, {
		quest         = quest,
		optional      = optional,
		-- "goldSoFar" = kill gold banked so far (victory rate); "goldOnVictory" =
		-- the fixed quest + completion gold added only on a win. Client shows the
		-- sum as "if you win" and notes defeat keeps 50% kill gold only.
		goldSoFar     = gb.killGold,
		goldOnVictory = gb.completionGold + gb.questGold,
		killCount     = gb.killCount,
		lootMin       = lootMin,
		lootMax       = lootMax,
	})
end)

-- One-time: give GuildMenuService the session player BEFORE the loop so the
-- round-1 guild-base landing (Open("Base")) can reach the client. 2026-10-13.
GuildMenuService.SetSessionPlayer(player)
-- One-time: wire the Guild base services (hire/shop/blacksmith/dispatch handlers)
-- at BOOT so the base is interactive on round 1. Getters read per-round values
-- (playerUnits/activeQuest/doSave are forward-declared file-scope). Running Init
-- once also avoids a per-round DevCommand:Connect leak inside Init. 2026-10-13.
GuildMenuService.Init({
	playerId       = PLAYER_ID,
	sessionPlayer  = player,
	getPlayerUnits = function() return playerUnits end,
	addPlayerUnit  = function(u)
		playerUnits[u.id] = u
		-- Every added unit (mid-session hire, battle recruit) gets a bound Doctrine
		-- instance immediately so "always equipped" holds without waiting for relaunch.
		DoctrineInventoryService.EnsureUnitBound(PLAYER_ID, u)
	end,
	-- Lazy wrapper (2026-10-13): Init runs at boot, before doSave is assigned inside
	-- the loop, so pass a closure that calls the live doSave at call time (same pattern
	-- as getPlayerUnits/getMapLevel). A by-value `doSave = doSave` would capture nil here.
	doSave         = function(...) return doSave(...) end,
	getMapLevel    = function() return activeQuest and activeQuest.recommendedLvl or 1 end,
	isSkillRegistered = function(skillId)
		return CommandService.GetSkill(skillId) ~= nil
	end,
})

-- LOADOUT REQUEST HANDLERS (moved to BOOT 2026-10-13): registers GetRosterData /
-- GetInventoryData / equip / doctrine / skill-card / stat handlers that the loadout
-- screen calls. MUST be at boot so unit management works the moment the player is at
-- the base, NOT only after a quest launches (previously this Init sat inside the loop
-- below the quest flow, so the loadout screen's fetch went unanswered until a quest
-- was picked). doSave uses the same lazy wrapper (assigned inside the loop).
local LoadoutRequestHandlers = require(Game:WaitForChild("LoadoutRequestHandlers"))
LoadoutRequestHandlers.Init({
	playerUnits = playerUnits,
	cardInventory = cardInventory,
	doSave = function(...) return doSave(...) end,
	PLAYER_ID = PLAYER_ID,
})

-- POPULATE THE PLAYER ROSTER AT BOOT (2026-10-13) so the base (loadout screen, dispatch
-- unit picker, guild roster) sees units BEFORE any quest is launched. hero/mage/ranger
-- are the boot-created starting units; recruits are restored once from the save here.
-- The in-loop battle setup still refreshes playerUnits each round from allUnitsList, which
-- picks up any unit hired mid-session, so this boot fill does not fight the per-round refill.
playerUnits[hero.id] = hero
playerUnits[mage.id] = mage
playerUnits[ranger.id] = ranger
for _, recruitUnit in ipairs(GuildMenuService.RestoreRecruits(PLAYER_ID, savedEquipMap, savedRaceMap)) do
	playerUnits[recruitUnit.id] = recruitUnit
end
print(string.format("[Main] Boot roster ready: %d player unit(s) available at the base.",
	(function() local n = 0 for _ in pairs(playerUnits) do n += 1 end return n end)()))

-- Full per-unit establishment from SAVE (Stage 3, 2026-10-19): doctrine + default, doctrine
-- skill, skill loadout, stat allocation (absolute base stats), records + level reconciliation,
-- consumable slots, and skillIds. IDEMPOTENT. As of Stage 4 (2026-10-19) this runs ONLY at
-- boot — the base owns a unit's data; battle no longer re-establishes (it just refreshes
-- effectiveStats). Mid-session hires are established by their hire path, not here.
local function establishPlayerUnitFromSave(u)
	local savedDoc = savedDoctrineMap[u.id]
	if savedDoc then
		u.doctrineId = savedDoc
	end
	-- Assign default doctrine if none set
	if not u.doctrineId then
		u.doctrineId = "DOC-BERSERKER"  -- placeholder default
	end
	-- Restore selected doctrine skill from save (Slice 4H)
	local savedSkill = savedDoctrineSkillMap[u.id]
	if savedSkill then
		u.selectedDoctrineSkill = savedSkill
	end
	-- Auto-select first skill choice if none set
	if not u.selectedDoctrineSkill then
		local doc = DoctrineData[u.doctrineId]
		if doc and doc.skillChoices and #doc.skillChoices > 0 then
			u.selectedDoctrineSkill = doc.skillChoices[1]
		end
	end
	-- Doctrine ownership (2026-10-20): restore the saved bound-instance link, then
	-- guarantee exactly one bound DoctrineInstance (mints from the content doctrineId
	-- if missing — covers starters, restored recruits, and pre-instance save migration).
	local savedDocInst = savedDoctrineInstanceMap[u.id]
	if savedDocInst then
		u.doctrineInstanceId = savedDocInst
	end
	DoctrineInventoryService.EnsureUnitBound(PLAYER_ID, u)
	print(string.format("[Main] %s doctrine: %s (skill: %s)",
		u.name, u.doctrineId, tostring(u.selectedDoctrineSkill)))

	-- Restore skill loadout from save (Slice 4I)
	local savedLoadout = savedSkillLoadoutMap[u.id]
	if savedLoadout then
		u.skillLoadout = savedLoadout
	end
	-- Initialize empty loadout if none exists
	if not u.skillLoadout then
		u.skillLoadout = { slot2 = nil, slot3 = nil, slot4 = nil }
	end

	-- Establish stats from save (Slice 4J). establishBaseStats sets Base Primary Stat =
	-- race growth(level) + allocation ABSOLUTELY, so running it at boot (and on level-up)
	-- never double-applies. (Stage 4: battle no longer calls this — it only refreshes
	-- effectiveStats after clearing the prior battle's statuses.)
	local savedAlloc = savedStatAllocation[u.id]
	if savedAlloc then
		u.statAllocation = savedAlloc
	end
	establishBaseStats(u)

	-- Restore or initialize unit records (Slice 4K)
	local savedRec = savedRecords[u.id]
	if savedRec then
		u.records = savedRec
	else
		u.records = {
			battlesParticipated = 0,
			victoriesParticipated = 0,
			enemiesDefeated = 0,
			totalDamageDealt = 0,
			totalHealingDone = 0,
			timesKO = 0,
		}
	end

	-- SLICE 6 LEVEL FIX (2026-10-07): ProgressionService reads level/xp/raceId
	-- from this record and defaults a missing level to 1, so level-25 starting
	-- units levelled up to 2. Reconcile record level with the unit's level:
	--   * record level missing or LOWER than the unit -> raise the record to the
	--     unit's level (seeds new records; one-time correction for old saves that
	--     stored the bogus 1). XP toward next level is kept as-is.
	--   * record level HIGHER than the unit -> the unit levelled up in an earlier
	--     session (starting units are always rebuilt at 25), so restore that level
	--     and recompute base stats from race growth + saved allocation.
	-- Never lowers a level. (ARC-006: nil-safe on every read.)
	do
		local rec = u.records
		local unitLevel = math.max(1, math.floor(tonumber(u.level) or 1))
		local recLevel = tonumber(rec.level)
		if recLevel == nil or math.floor(recLevel) < unitLevel then
			if recLevel ~= nil then
				print(string.format("[Main] Level fix: %s record level %d -> %d (save correction)",
					u.name, math.floor(recLevel), unitLevel))
			end
			rec.level = unitLevel
		elseif math.floor(recLevel) > unitLevel and u.raceId then
			local newLevel = math.floor(recLevel)
			local ok, stats = pcall(RaceData.CalcBaseStats, u.raceId, newLevel)
			if ok and type(stats) == "table" then
				u.level = newLevel
				for stat, value in pairs(stats) do
					local pts = (u.statAllocation and u.statAllocation[stat]) or 0
					u.baseStats[stat] = value + pts
				end
				EquipmentService.RebuildUnitStats(u)
				PersistentStateService.UpdateMaxResources(PLAYER_ID, u.id, u.maxHp, u.maxMp)
				-- Keep the runtime HP/MP in step with the persistent state read below.
				-- KO units stay at 0 HP. (ps may be nil at boot for an unregistered unit;
				-- the 'if ps' guard makes that a safe no-op.)
				local ps = PersistentStateService.GetUnitState(PLAYER_ID, u.id)
				if ps and u.isAlive then
					u.currentHp = math.min(ps.currentHp, u.maxHp)
					u.currentMp = math.min(ps.currentMp, u.maxMp)
				end
				print(string.format("[Main] Level fix: %s restored to saved level %d", u.name, newLevel))
			end
		end
		if tonumber(rec.xp) == nil then rec.xp = 0 end
		if rec.raceId == nil then rec.raceId = u.raceId end
	end

	-- Initialize consumable slots (Slice 4G.4)
	-- 6 slots: 1-3 open, 4-6 locked (unlock via progression)
	local savedCons = savedConsumableSlots[u.id]
	if savedCons then
		-- Parked items (DB Status PARKED, user 2026-10-27) and items that no longer exist (deleted
		-- CON-016 Magnetic Snare / UTI-012 Recovery Winch, user 2026-10-27) leave the slot empty.
		for idx, s in pairs(savedCons) do
			local cid = type(s) == "table" and s.consumableId or nil
			local d = cid and ConsumableData.GetById(cid) or nil
			if cid and (not d or d.parked) then
				print(`[Main] {u.name or u.id}: {d and ("parked item " .. d.name) or ("removed item " .. tostring(cid))} cleared from consumable slot {idx}`)
				savedCons[idx] = nil
			end
		end
		u.consumableSlots = savedCons
	end
	if not u.consumableSlots then
		u.consumableSlots = {}
	end
	u.consumableSlotCount = 3  -- open slots (4-6 locked)
	u.maxConsumableSlots = 6

	-- Build skillIds from loadout (doctrine skill + equipped skill cards)
	u.skillIds = {}
	if u.selectedDoctrineSkill then
		table.insert(u.skillIds, u.selectedDoctrineSkill)
	end
	for _, slotKey in ipairs({"slot2", "slot3", "slot4"}) do
		local slotData = u.skillLoadout[slotKey]
		if slotData and slotData.skillId then
			table.insert(u.skillIds, slotData.skillId)
		end
	end
	print(string.format("[Main] %s skills: %s", u.name, table.concat(u.skillIds, ", ")))
end

-- Establish EVERY player unit fully from save at BOOT so the base/loadout screen shows
-- correct, fully-set-up units immediately (doctrine, skills, stats, records, consumables).
for _, u in pairs(playerUnits) do
	if u.side == "Player" then
		establishPlayerUnitFromSave(u)
	end
end

-- DEV-ONLY doctrine stash seed (2026-10-20, TEMPORARY SCAFFOLDING): mint a few spare
-- doctrine copies into the loose stash so doctrine SWAPPING is testable before real
-- loot drops and the merchant exist. Fixed instance ids make this idempotent — once
-- these ids are in the saved doctrine inventory, re-boot skips them (no multiplication).
-- REMOVE this block when doctrine drops / the merchant land.
do
	local DEV_DOCTRINE_SEED = { "DOC-VANGUARD", "DOC-DUELIST", "DOC-CLERIC", "DOC-ASSASSIN", "DOC-ELEMENTALIST", "DOC-GEOMANCER", "DOC-CHEMIST", "DOC-ARTIFICER" }
	for i, docId in ipairs(DEV_DOCTRINE_SEED) do
		if DoctrineData[docId] then
			local fixedId = "doc_devseed_" .. i
			if not DoctrineInventoryService.GetInstance(PLAYER_ID, fixedId) then
				DoctrineInventoryService.AddInstance(PLAYER_ID, {
					instanceId = fixedId, doctrineId = docId, selectedSkillId = nil, boundUnitId = nil,
				})
			end
		end
	end
	print("[Main] Dev doctrine stash seeded (temporary) — spares available for swap testing.")
end

-- First-run party seed (2026-10-15): if the player has never built a party (all saved
-- parties empty), fill Party A with the current boot roster so there is always one
-- pickable party at the sortie Choose-Party step (empty parties are greyed/unpickable).
-- Runs AFTER PartyService.Import (saved parties already loaded above) so a returning
-- player with real parties is never overwritten.
do
	local bootIds = {}
	for id in pairs(playerUnits) do table.insert(bootIds, id) end
	local seeded = PartyService.AutoSeedIfEmpty(PLAYER_ID, bootIds)
	if seeded then
		print(string.format("[Party] First-run seed: Party A filled with %d unit(s).", #bootIds))
	end
end

--------------------------------------------------
-- UGC RENTAL & OWNERSHIP (moved to BOOT 2026-10-13): previously sat INSIDE the per-
-- round loop, so the UGC system (providers, player init, save import, remote wiring,
-- availability loop) only came online AFTER a quest launched. The Outfit tab opened at
-- the base then fetched from a server that was not listening yet and drew BLANK. It
-- needs playerUnits (boot roster, just above), loadedSave and player -- all boot-level.
-- Running once at boot also removes the per-round remote re-wire + duplicate
-- availability-loop leak. Remotes validated in UGCRemoteHandler (SEC-001); state rides
-- progression Key 3 (doSave: progression.ugc); old saves load as fresh UGC state.
--------------------------------------------------
UGCService.SetCurrencyService(CurrencyService)
UGCService.SetAvailabilityProvider(UGCOutfitService.IsAvailable)
UGCService.SetOffSaleProvider(UGCOutfitService.IsOffSale) -- "Off sale" marker (ugc_rules 41/47)
UGCService.SetRatingService(UGCRatingService) -- private vote aggregate
UGCService.SetSaveModeProvider(SaveService.GetMode)
UGCOutfitService.SetSaveModeProvider(SaveService.GetMode) -- availability cache persistence (own DataStore)
UGCService.SetUnitRaceProvider(function(_pid, unitId)
	local u = playerUnits[unitId]
	if not u then return false, nil end
	local race = u.raceId and RaceData.GetRace(u.raceId) or nil
	return true, race and race.name or nil
end)
-- Rental price level = highest owned roster unit level ("player current level").
UGCService.SetPlayerLevelProvider(function(_pid)
	local best = 1
	for _, u in pairs(playerUnits) do
		if type(u.level) == "number" and u.level > best then best = u.level end
	end
	return best
end)
UGCOutfitService.SetStateProvider(UGCService)
-- Body-color provider: UGCOutfitService asks for a unit's chosen tint when it
-- dresses the battle model / builds the loadout preview. We return a Color3 from
-- the live unit's stored {r,g,b} (nil → no tint). playerId is the project's fixed
-- PLAYER_ID; we look the unit up directly in playerUnits.
UGCOutfitService.SetBodyColorProvider(function(_playerId, unitId)
	local unit = playerUnits[unitId]
	local c = unit and unit.bodyColor
	if type(c) == "table" and #c == 3 then
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	return nil
end)
UGCService.InitPlayer(PLAYER_ID, player)
UGCService.Import(PLAYER_ID, loadedSave and loadedSave.progression
	and loadedSave.progression.ugc or nil)
UGCRemoteHandler.Init({
	playerId      = PLAYER_ID,
	sessionPlayer = player,
	ugc           = UGCService,
	outfit        = UGCOutfitService,
})
UGCService.StartRatingFlush()
task.spawn(function()
	-- First on-sale pass (fail closed until done), then a background re-check loop
	-- (ugc_rules 49); battles only read the cached pool (ugc_rules 50).
	UGCOutfitService.StartAvailabilityLoop()
	UGCService.RefreshOwnership(PLAYER_ID) -- ownership is never saved; verify live
end)

-- SAVE HELPER (moved to BOOT 2026-10-13): doSave closes over only boot-owned state
-- (playerUnits, cardInventory, PLAYER_ID, and the boot-required services), so it is
-- defined ONCE here, before the loop. This lets base write-actions (hire/buy/sell/
-- upgrade/dispatch) on round 1 — before any quest launches — persist without hitting
-- a nil doSave. The GuildMenu/Loadout Init lazy wrappers resolve to this definition.
function doSave()
	local rosterState = PersistentStateService.ExportState(PLAYER_ID)
	local inventoryItems = InventoryService.ExportInventory(PLAYER_ID)
	-- Enrich roster with equipment slot assignments (instanceIds only)
	for unitId, unit in pairs(playerUnits) do
		if rosterState[unitId] and unit.equipmentSlots then
			local slots = {}
			for slot, item in pairs(unit.equipmentSlots) do
				slots[slot] = item.instanceId
			end
			rosterState[unitId].equipSlots = slots
		end
		-- Enrich with race and trait data (Slice 4F)
		if rosterState[unitId] and unit.raceId then
			rosterState[unitId].raceId = unit.raceId
			rosterState[unitId].perkIds = unit.perkIds or {}
			rosterState[unitId].drawbackIds = unit.drawbackIds or {}
		end
		-- Enrich with doctrine data (Slice 4H)
		if rosterState[unitId] then
			rosterState[unitId].doctrineId = unit.doctrineId or nil
			rosterState[unitId].doctrineInstanceId = unit.doctrineInstanceId or nil
			rosterState[unitId].selectedDoctrineSkill = unit.selectedDoctrineSkill or nil
			rosterState[unitId].skillLoadout = unit.skillLoadout or nil
			rosterState[unitId].statAllocation = unit.statAllocation or nil
			rosterState[unitId].records = unit.records or nil
			rosterState[unitId].consumableSlots = CommandService.SaveableConsumableSlots(unit.consumableSlots) or nil
			-- Player-chosen 2D portrait (option B); nil clears it.
			rosterState[unitId].portraitAssetId = unit.portraitAssetId or nil
			-- Player-chosen body/skin tint {r,g,b}; nil clears it.
			rosterState[unitId].bodyColor = unit.bodyColor or nil
		end
	end
	-- Diagnostic: log equipment slot assignments being saved
	for unitId, unitState in pairs(rosterState) do
		if unitState.equipSlots then
			local parts = {}
			for slot, iid in pairs(unitState.equipSlots) do
				table.insert(parts, slot .. ":" .. tostring(iid))
			end
			print(string.format("[Save] Equipment: %s=%s", unitId, table.concat(parts, ",")))
		end
	end
	-- Persist the loose card inventory so skill/augment card counts survive relaunch
	-- (previously never saved -> starter cards re-granted every launch = multiplication).
	-- Slice 6: fold guild/dispatch/explore progression into Key 3 and currency
	-- balances into Key 2 (via the optional 5th Save arg). No second store.
	local progression = {
		cardInventory = cardInventory,
		doctrineInventory = DoctrineInventoryService.ExportInventory(PLAYER_ID), -- owned doctrine instances (2026-10-20)
		guild    = GuildService.Export(PLAYER_ID),
		dispatch = DispatchService.Export(PLAYER_ID),
		party    = PartyService.Export(PLAYER_ID),
		explore  = ExploreService.Export(PLAYER_ID),
		guildMenu = GuildMenuService.Export(PLAYER_ID), -- Slice 6 Guild menu (battle counter + hired units)
		ugc      = UGCService.Export(PLAYER_ID), -- UGC rentals/trials/cart/votes (ownership never saved)
	}
	local currencies = CurrencyService.Export(PLAYER_ID)
	local ok, err = SaveService.Save(PLAYER_ID, rosterState, inventoryItems, progression, currencies)
	if ok then
		print("[Save] Successful")
	else
		warn("[Save] FAILED: " .. (err or "unknown"))
	end
	return ok, err
end

-- CLEAN-SLATE BATTLE RESET (2026-10-14): the permanent player units (hero/mage/ranger)
-- are the SAME objects every round, so battle-scoped state would otherwise carry into the
-- next battle. The instant-loss-after-defeat bug was a dead 'isAlive' flag surviving a loss;
-- this resets ALL per-battle fields to their fresh-start defaults so battle N starts identical
-- to battle 1. It deliberately does NOT touch saved progression: currentHp/currentMp are
-- applied by the save-load right after this, and equipment/level/XP/doctrine/skills/stat
-- allocation/portrait are untouched. Statuses are cleared by emptying statusInstances
-- directly -- safe because EquipmentService.RebuildUnitStats recomputes effectiveStats
-- from scratch on each call (base + doctrine + equipment + a fold of the CURRENT statuses
-- via StatusService.GetStatusStatModifiers), so once statusInstances is empty the status
-- contribution is zero and no stale stat delta can survive the wipe.
local function resetUnitForNewBattle(u)
	u.isAlive = true
	u._revivedThisBattle = nil  -- kill-credit revive stamp is battle-scoped
	u.currentAp = 0
	u.statusInstances = {}
	u.shield_total = 0
	u.mpRegenAccumulator = 0
	u.isChanneling = false
	u.channelingData = nil
	u.channelPhase = nil
	u.channelResolveCt = nil
	u.channelRt = nil
	u.pendingActivationCt = nil  -- same fields as UnitSchema.ClearChannelState
	u.combatStackPct = 0
	u.combatStackAge = 0
	u.zombieReviveUsed = nil
	u.undyingWillUsed = nil   -- Undying Will perk (TRAIT-P-179): reset once-per-battle revive
	u.undyingWillKoCt = nil
	u.tileX = 0
	u.tileY = 0
	-- Facing tokens are ABBREVIATIONS everywhere (GameConstants.FACING_VECTORS keys:
	-- N/NE/E/SE/S/SW/W/NW). "South" (full word) has no key, so the client facing
	-- lookup silently fails and the unit shows no facing. Use "S". (Pre-existing bug
	-- from the 2026-10-14 reset; corrected 2026-10-21.)
	u.facing = "S"
end

while true do

	-- GUILD BASE (hub, 2026-10-13 restructure): the base is HOME, not a step between
	-- quests. It stays open with all services live (shop/blacksmith/tavern/loadout work
	-- any time, handled by their own boot-registered handlers). The base waits for the
	-- player to LAUNCH AN ACTIVITY, then dispatches by activity type. Quest is the first
	-- activity; dungeon/raid/PvP slot in later as new branches of the dispatch below —
	-- no change to the wait itself. OpenAdventurersGuild is the quest launch signal
	-- (its payload may carry { activity = "..." }; absent/"quest" = the quest board).
	GuildMenuService.Open("Base")
	local launchedActivity = "quest"
	do
		local activitySignal = Instance.new("BindableEvent")
		local activityConn = BattleEvents.OpenAdventurersGuild.OnServerEvent:Connect(function(plr, data)
			-- Default to the quest activity; a future client may send { activity = "dungeon" } etc.
			if type(data) == "table" and type(data.activity) == "string" then
				launchedActivity = data.activity
			end
			activitySignal:Fire()
		end)
		print("[Loop] At guild base (hub) — services live; waiting for the player to launch an activity.")
		activitySignal.Event:Wait()
		activityConn:Disconnect()
		activitySignal:Destroy()
	end
	-- 2026-10-16: do NOT close the base menu here. The quest board is now an in-menu page
	-- (Adventurer's Guild) that stays open; closing would hide it. The menu is closed once,
	-- just before deployment (and on abandon). The client already switched to the
	-- Adventurer's Guild page when the player opened it.
	print(`[Loop] Activity launched: {launchedActivity}`)

	-- ACTIVITY -> BATTLE ORDER -> BATTLE -> OUTCOME SEAM (2026-10-16). A battle is NOT owned
	-- by quests. An ACTIVITY (quest today; boss raid / exploration later) sets up the battle
	-- -- where the map comes from, where the enemies come from, the deploy cap -- and chooses
	-- the BETWEEN-BATTLE RULE (betweenBattleMode) that the post-battle outcome below keys on.
	-- The battle engine (map render -> enemy gen -> deploy -> turn loop) between here and the
	-- outcome never knows which activity launched it. Adding a new activity = a new branch
	-- here + (if needed) a new betweenBattleMode; the engine and this loop body stay put.
	--   quest       -> procedural map + procedural enemies, mode "standalone"
	--   (future) raid        -> fixed map + fixed enemies + daily attempt cap, mode "standalone"
	--   (future) exploration -> per-node battle, mode "run" (carry HP/MP/charges; recover only at rest nodes)
	-- betweenBattleMode "standalone" = the current rule: clean-slate reset each battle, full
	-- post-battle recovery, auto-save, return to base. (The only mode today; exploration adds "run".)
	local betweenBattleMode = "standalone"

	-- Generate 3 quests
	playerLevel = 1  -- prototype: hardcoded level 1. Future: read from save.
	quests = QuestGenerator.Generate(playerLevel, os.time())

	-- Show Quest Board to all clients
	BattleEvents.QuestBoardOpen:FireAllClients({ quests = quests })

	-- Wait for quest selection
	selectedQuestId = nil
	local questSelectedSignal = Instance.new("BindableEvent")

	local questSelectedConn = BattleEvents.QuestSelected.OnServerEvent:Connect(function(plr, data)
		if data and data.questId then
			selectedQuestId = data.questId
			questSelectedSignal:Fire()
		end
	end)

	local questCancelled = false
	local questCancelConn = BattleEvents.QuestBoardCancel.OnServerEvent:Connect(function(plr)
		questCancelled = true
		questSelectedSignal:Fire()
	end)

	questSelectedSignal.Event:Wait()
	questSelectedConn:Disconnect()
	questCancelConn:Disconnect()
	questSelectedSignal:Destroy()

	-- Back from the quest board: nothing committed or spent -- just return to the base.
	if questCancelled then
		print("[Loop] Quest board cancelled -- returning to guild base.")
		continue
	end

	-- Find selected quest
	selectedQuest = nil
	for _, q in ipairs(quests) do
		if q.id == selectedQuestId then
			selectedQuest = q
			break
		end
	end
	if not selectedQuest then selectedQuest = quests[1] end -- fallback

	print(string.format("[Main] Quest selected: %s (%s/%s)", selectedQuest.name, selectedQuest.biome, selectedQuest.template))

	-- SCOUTING WAIT UX (2026-10-13): show the sortie briefing IMMEDIATELY, with its
	-- "Continue to Deployment" button LOCKED and flavoured "Scouting the battle map...",
	-- so the player never stares at an empty world while the map builds. The button
	-- unlocks when battle prep finishes (MapBuildComplete, below). The go/abandon gate
	-- further down already waits on that same button, so locking it IS the gate.
	-- Pass the selected quest in the PreBattle payload (2026-10-16 fix): the client sortie page
	-- must show the quest even when chosenQuest was never set client-side (fallback pick / the
	-- quest reached PreBattle without a "Choose" tap). Compact copy of the display fields.
	mapReadyForStart = false  -- close the gate: this round's map starts building now
	GuildMenuService.Open("PreBattle", { scouting = true, quest = {
		id = selectedQuest.id, name = selectedQuest.name, biome = selectedQuest.biome,
		recommendedLvl = selectedQuest.recommendedLvl, enemyCount = selectedQuest.enemyCount,
		difficulty = selectedQuest.difficulty, playerSlots = selectedQuest.playerSlots,
		condition = selectedQuest.condition, rewards = selectedQuest.rewards,
	} })

	-- Generate map from quest parameters
	generatedMap = MapService.Generate(selectedQuest.biome, selectedQuest.template)
	MAP_WIDTH    = generatedMap.width
	MAP_HEIGHT   = generatedMap.height
	GameConstants.SetGeneratedMap(generatedMap)
	playerSpawns = generatedMap.deploymentZones.player
	enemySpawns  = generatedMap.deploymentZones.enemy

	-- Render the quest-selected map (replaces the initial TemplateViewer render).
	oldMapFolder = workspace:FindFirstChild("TemplateViewerMap")
	if oldMapFolder then
		print(string.format("[Main] Destroying old map folder: %s (%s)",
			oldMapFolder.Name, oldMapFolder:GetAttribute("BiomeId") or "unknown"))
		oldMapFolder:Destroy()
	else
		print("[Main] No old TemplateViewerMap found to destroy")
	end

	questMapFolder = MapRenderer.Render(generatedMap, "TERRAIN")
	questMapFolder.Parent = workspace
	mapFolder = questMapFolder

	-- AD BILLBOARD image cycle (2026-10-15 USER DECISION; map_gen_rules 79/85,
	-- objects_encounters 84). Start the seeded, 20-second ad-image cycle now that the
	-- quest map is live in workspace. Server-owned: it reads the Decal pool from
	-- ServerStorage > "Billboard Ad Images" (client can't see ServerStorage) and paints
	-- the image onto every AdFace1..N via ColorMapContent (legacy Texture fallback). The
	-- starting image is seeded from generatedMap.seed through a DEDICATED derived stream,
	-- so map layout/forms for a given seed stay byte-identical. Empty/missing folder ->
	-- blank faces, no crash, no cycle thread. The loop self-terminates when this folder
	-- is Destroyed (next quest / Regenerate). Never clickable (no ClickDetector/GUI).
	MapRenderer.StartAdImageCycle(questMapFolder, generatedMap.seed)

	-- Slice 5 blocker #2: give ObjectEffectService a way to render runtime-spawned
	-- objects (Forge, Mimic reveal) into the live mapFolder. The closure reads the
	-- `mapFolder` upvalue at CALL time, so it stays correct across Regenerate
	-- (which reassigns mapFolder). The new Part is a server instance in mapFolder
	-- and replicates to clients automatically.
	ObjectEffectService.SetObjectRenderer(function(inst)
		if mapFolder then
			MapRenderer.RenderOneObject(mapFolder, inst)
		end
	end)

	-- Object-visual remover (Mimic reveal replaces its chest). Same mapFolder-upvalue
	-- pattern as the renderer above.
	ObjectEffectService.SetObjectVisualRemover(function(inst)
		if mapFolder then
			MapRenderer.RemoveOneObject(mapFolder, inst)
		end
	end)

	-- Slice 5 blocker #3: tile reshaper for Stone Pillar's fallen span. Reads the
	-- `mapFolder` upvalue at call time (correct across Regenerate). Server Part
	-- change replicates to clients.
	ObjectEffectService.SetTileReshaper(function(x, y, terrain, elev)
		if mapFolder then
			MapRenderer.ReshapeTile(mapFolder, x, y, terrain, elev)
		end
	end)
	-- Excavation Drill (2026-10-26, UAT D1): a LOWERED tile must also drop its voxel column.
	-- Clear the old column (at the old height), reshape the Part, then rebuild the column at
	-- the new height. Single-tile FillBlocks only (never a whole-map clear).
	ObjectEffectService.SetTileLowerer(function(x, y, terrain, elev)
		if mapFolder then
			MapRenderer.ClearTileVoxelColumn(mapFolder, x, y)
			MapRenderer.ReshapeTile(mapFolder, x, y, terrain, elev)
			MapRenderer.RebuildTileVoxelColumn(mapFolder, x, y, terrain)
		end
	end)

	MapService.ClearCache()  -- clear so Regenerate dev tool can generate fresh

	-- FIX: StreamingEnabled is on (Roblox default) but CharacterAutoLoads is false,
	-- so there is no character and Player.ReplicationFocus defaults to nil.
	-- Without a focus the server never streams most map Parts to the client.
	-- Create an invisible anchor at map center and point the player's focus there.
	streamFocus = Instance.new("Part")
	streamFocus.Name       = "StreamFocus"
	streamFocus.Anchored   = true
	streamFocus.CanCollide = false
	streamFocus.Transparency = 1
	streamFocus.Position   = Vector3.new(0, 0, 0)  -- map is centered at origin
	streamFocus.Parent     = workspace
	player.ReplicationFocus = streamFocus

	print(string.format("[Main] Map generated: %dx%d, %d player spawns, %d enemy spawns",
		MAP_WIDTH, MAP_HEIGHT, #playerSpawns, #enemySpawns))

	-- Store active quest for later use (rewards, objectives)
	activeQuest = selectedQuest

	CommandService.SetMapDimensions(MAP_WIDTH, MAP_HEIGHT)
	DisplacementService.SetMapDimensions(MAP_WIDTH, MAP_HEIGHT)

	-- TileEffectService init
	TileEffectService.Init(MAP_WIDTH, MAP_HEIGHT)
	TileEffectService.SetStatusService(StatusService)
	TileEffectService.SetBroadcaster(BattleVisualBroadcaster)
	-- BUG-002 GAP 2 (2026-10-22): single-tile server voxel-clear. When a VOXEL_KEEP
	-- origin (Grassland / Shallow / Deep Water, rendered as a Roblox-Terrain voxel
	-- column) transforms mid-battle to a non-voxel terrain, the client re-skins the
	-- tile Part but cannot clear the server voxel column (workspace.Terrain is
	-- server-only). This closure reads the `mapFolder` upvalue at CALL time (correct
	-- across Regenerate) and clears ONLY that one tile's column via a localized
	-- FillBlock(Air) in MapRenderer.ClearTileVoxelColumn (never a whole-map Clear()).
	-- Same injection pattern as SetObjectRenderer / SetTileReshaper above.
	TileEffectService.SetVoxelClearer(function(x, y)
		if mapFolder then
			MapRenderer.ClearTileVoxelColumn(mapFolder, x, y)
		end
	end)
	-- OBS Phase 2c-D: route explosion/elevation object hits to the breakable OBS
	-- blocker at (x,y). Closure over the battle `state` upvalue (lazy; nil-safe
	-- before a battle exists). Billboard/unbreakable tiles are a no-op in ApplyObjectHit.
	TileEffectService.SetObjectHitCallback(function(x, y)
		-- fromExplosion=true: an EXPLOSIVE object (Bomb Barrel / Land Mine) in the
		-- blast is NOT detonated here — the explosion queue chains it via the
		-- explosive callback below so the 128-event cap spans the whole chain.
		if state then return ObjectEffectService.ApplyObjectHit(state, x, y, 1, nil, true) end
		return nil
	end)
	-- Trap-trigger feature (2026-10-20): when an explosion reaches a Bomb Barrel /
	-- Land Mine tile, remove it and chain a new explosion event in the SAME queue
	-- (TRG-011 cap). Closure over the battle `state`; nil-safe before a battle.
	TileEffectService.SetExplosiveObjectCallback(function(x, y)
		if state then return ObjectEffectService.ConsumeExplosiveObjectAt(state, x, y) end
		return false
	end)
	-- Terrain Shaper / Terra Former objectives (2026-10-24): count player-caused
	-- elevation changes (explosion terrain) + terrain transforms (element on tile).
	-- Closure over the battle `state` upvalue, like the callbacks above; nil-safe.
	TileEffectService.SetObjectiveCounter(function(key, amount)
		if state then ObjectiveService.RecordEvent(state, key, amount) end
	end)
	BattleCoordinator.SetTileEffectService(TileEffectService)
	CommandService.SetTileEffectService(TileEffectService)
	-- Pulse scheduler wiring (2026-10-26): fixed-CT deployable/delayed pulses. Init with
	-- the effect services it routes to, then inject into the clock (BattleCoordinator) and
	-- the deploy path (CommandService) so item use can register pulses. Cycle-free injection.
	PulseScheduler.Init({ UnitSchema = UnitSchema, StatusService = StatusService, TileEffectService = TileEffectService, GameConstants = GameConstants, TargetingService = TargetingService, ObjectEffectService = ObjectEffectService })
	BattleCoordinator.SetPulseScheduler(PulseScheduler)
	-- Firebreak zones (user ruling 2026-10-27): StatusService asks TileEffectService.
	StatusService.SetFireGuardQuery(function(x, y) return TileEffectService.IsFirebreak(x, y) end)
	-- Scanner Lens zones (user ruling 2026-10-27): enemies of the zone's owner cannot Hide there.
	StatusService.SetHideBlockQuery(function(u) return ObjectEffectService.IsHideBlocked(u) end)
	-- Rescue Beacon (2026-10-26): before every battle-end check, revive the first allied KO
	-- near a beacon, then re-label the tiles here (tile labels live in Main).
	BattleCoordinator.SetKoHook(function(st)
		local revived = CommandService.ProcessRescueBeacons(st)
		for _, r in ipairs(revived or {}) do
			-- Clear the tile the unit fell on (UAT advisory 2026-10-26), then label the new one.
			if r.oldX and r.oldY then clearTileOccupant(r.oldX, r.oldY) end
			setTileOccupant(r.unit.tileX, r.unit.tileY, r.unit.name, "Unit (" .. r.unit.side .. ")", "Blocking")
		end
	end)
	CommandService.SetPulseScheduler(PulseScheduler)
	-- Summon spawner injection (2026-10-06): lets CommandService route the six summon
	-- skills to EnemyGenerator.SpawnSummon without a hard require (cycle-free, mirrors
	-- the TileEffectService injection above). EnemyGenerator is required at the top.
	CommandService.SetEnemyGenerator(EnemyGenerator)
	-- Weather beacon items (Rain/Sun/Storm) run through WeatherService from the Item branch.
	CommandService.SetWeatherService(WeatherService)
	-- Augment decoy/turret spawn needs the summon spawner (2026-10-24): inject the public
	-- CommandService wrapper into AugmentEffectService. After SetEnemyGenerator so the
	-- underlying spawnSummonFor has its generator dependency.
	_AugmentEffectService.SetSummonHandler(CommandService.SpawnAugmentSummon)
	_AugmentEffectService.SetInterruptHandler(BattleCoordinator.InterruptChanneling)
	if _AugmentEffectService.SetKnockbackHandler then
		_AugmentEffectService.SetKnockbackHandler(CommandService.ApplyAugmentKnockback)
	end
	-- Round 2 terrain pass (2026-09-29): pathfinding/hit-quality/slide services also
	-- need the TileEffectService reference (Tar Pit move cost, Steam evasion, Oily slide).
	TargetingService.SetTileEffectService(TileEffectService)
	CombatResolver.SetTileEffectService(TileEffectService)
	TileCrossEffectService.SetTileEffectService(TileEffectService)

	-- Weather engine wiring: inject the service refs it needs + the back-references
	-- so weather drives per-round re-roll (BattleCoordinator), passive element
	-- damage (CombatResolver), Burn-suppression (StatusService), tile reshape, and
	-- client broadcast. The tile reshaper closure reads the mapFolder upvalue.
	WeatherService.SetTileEffectService(TileEffectService)
	WeatherService.SetBroadcaster(BattleVisualBroadcaster)
	WeatherService.SetStatusService(StatusService)
	-- OBS Phase 2c-D: Earthquake downward reshape also hits breakable OBS blockers.
	WeatherService.SetObjectHitCallback(function(x, y)
		if state then return ObjectEffectService.ApplyObjectHit(state, x, y, 1) end
		return nil
	end)
	WeatherService.SetTileReshaper(function(x, y, terrain, elev)
		if mapFolder then MapRenderer.ReshapeTile(mapFolder, x, y, terrain, elev) end
	end)
	-- BUG-002 voxel-clear follow-up (2026-10-22): wire the single-tile voxel-clear onto
	-- the WeatherService terrain-change path (reshapeTile), identical to the
	-- TileEffectService.SetVoxelClearer injection above. Same live mapFolder upvalue
	-- (reassigned on Regenerate) + localized MapRenderer.ClearTileVoxelColumn FillBlock(Air)
	-- (never a whole-map Clear). So Heatwave drying Shallow/Deep Water -> Clear now removes
	-- that one tile's stale water voxel column.
	WeatherService.SetVoxelClearer(function(x, y)
		if mapFolder then MapRenderer.ClearTileVoxelColumn(mapFolder, x, y) end
	end)
	BattleCoordinator.SetWeatherService(WeatherService)
	CombatResolver.SetWeatherService(WeatherService)

	-- Battlefield events: inject the same proven deps (all nil-safe inside the service).
	BattlefieldEventService.SetBroadcaster(BattleVisualBroadcaster)
	-- Unit remover for event units that leave the map (Merchant Caravan etc.): frees
	-- the tile and tells clients to remove the token, same as a defeat removal.
	BattlefieldEventService.SetUnitRemover(function(u)
		clearTileOccupant(u.tileX, u.tileY)
		BattleEvents.UnitDefeated:FireAllClients({ unitId = u.id, removeUnit = true })
		BattleVisualBroadcaster.Log("ko", `{u.name} leaves the battlefield.`, u.id)
	end)
	BattlefieldEventService.SetTileEffectService(TileEffectService)
	BattlefieldEventService.SetEnemyGenerator(EnemyGenerator)
	BattlefieldEventService.SetRewardService(RewardService)
	BattlefieldEventService.SetWeatherService(WeatherService)
	BattlefieldEventService.SetTargetingService(TargetingService)
	BattlefieldEventService.SetStatusService(StatusService)
	BattlefieldEventService.SetCommandService(CommandService)
	BattlefieldEventService.SetTileReshaper(function(x, y, terrain, elev)
		if mapFolder then MapRenderer.ReshapeTile(mapFolder, x, y, terrain, elev) end
	end)
	BattleCoordinator.SetBattlefieldEventService(BattlefieldEventService)
	local enemyRng = Random.new((generatedMap.seed or os.time()) + 90001)
	local generatedEnemies = EnemyGenerator.GenerateEnemies(
		activeQuest.enemyTypes or {},
		enemySpawns,
		enemyRng
	)

	-- STAGE 2 (2026-10-19): battle BORROWS the base roster instead of rebuilding it.
	-- Previously this rebuilt hero/mage/ranger and re-ran RestoreRecruits (creating NEW
	-- recruit objects) every battle -- the root of "battle is the main loop". Now battle
	-- snapshots the already-established persistent playerUnits (hero/mage/ranger + boot-
	-- restored recruits + any mid-session hires). allUnitsList is a fresh COPY so battle-
	-- only mutations (SyncBattleRoster bench/dispatch, undeployed pruning, enemy inserts)
	-- never touch the base roster. Deterministic order: starting units first, then the
	-- rest by id. The establishment block below still re-finalizes these units idempotently.
	allUnitsList = {}
	local _seenStarter = {}
	for _, starter in ipairs({ hero, mage, ranger }) do
		if starter and playerUnits[starter.id] then
			table.insert(allUnitsList, playerUnits[starter.id])
			_seenStarter[starter.id] = true
		end
	end
	do
		local _restIds = {}
		for id, u in pairs(playerUnits) do
			if u.side == "Player" and not _seenStarter[id] then
				table.insert(_restIds, id)
			end
		end
		table.sort(_restIds)
		for _, id in ipairs(_restIds) do
			table.insert(allUnitsList, playerUnits[id])
		end
	end
	for _, enemyUnit in ipairs(generatedEnemies) do
		table.insert(allUnitsList, enemyUnit)
	end
	for _, u in ipairs(allUnitsList) do
		if u.side == "Enemy" then
			setTileOccupant(u.tileX, u.tileY, u.name, "Unit (" .. u.side .. ")", "Blocking")
		end
	end
	-- CLEAN-SLATE (2026-10-14): wipe battle-scoped state on every player unit BEFORE Flight
	-- re-application and the saved HP/MP load below, so flying units get a fresh Flight (no
	-- double-stack) and isAlive is true before the save load (which only re-KOs a saved-KO unit).
	for _, u in ipairs(allUnitsList) do
		if u.side == "Player" then
			resetUnitForNewBattle(u)
		end
	end


	-- Apply permanent Flight status to units with the Flying race tag
	-- DB: "Flying: Grants permanent Flight using complete Manual Flight benefits and drawbacks"
	do
		local RaceData = require(game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("RaceData"))
		for _, u in ipairs(allUnitsList) do
			if u.raceId then
				local raceEntry = RaceData.GetRace(u.raceId)
				if raceEntry and raceEntry.tags then
					for _, tag in ipairs(raceEntry.tags) do
						if tag == "Flying" then
							StatusService.ApplyStatus(u, "Flight", "RaceTag")
							print(string.format("[Main] %s has Flying tag — Flight status applied", u.name))
							break
						end
					end
				end
			end
		end
	end

	-- Register persistent state for player units (Slice 4B)
	PersistentStateService.InitPlayer(PLAYER_ID)
	for _, u in ipairs(allUnitsList) do
		if u.side == "Player" then
			local ps = PersistentStateService.GetUnitState(PLAYER_ID, u.id)
			if not ps then
				-- Brand new unit — register at full
				PersistentStateService.RegisterNewUnit(PLAYER_ID, u.id, u.maxHp, u.maxMp)
			else
				-- Loaded from save — apply persistent HP/MP to runtime unit
				u.currentHp = math.min(ps.currentHp, u.maxHp)
				u.currentMp = math.min(ps.currentMp, u.maxMp)
				if ps.isKO then
					u.isAlive = false
					u.currentHp = 0
				end
				print(string.format("[Main] Loaded persistent state for %s: HP:%d/%d MP:%d/%d KO:%s",
					u.name, u.currentHp, u.maxHp, u.currentMp, u.maxMp, tostring(ps.isKO)))
			end
		end
	end

	-- STAGE 4 (2026-10-19): battle no longer re-establishes unit identity. Units are fully
	-- established by the base at boot and at hire time, and every base edit (equip / doctrine /
	-- skill / stat allocation) keeps the LIVE unit current, so battle purely CONSUMES them.
	-- The only battle-scoped stat work left is recomputing effectiveStats AFTER
	-- resetUnitForNewBattle cleared the previous battle's statuses, so each fight starts from a
	-- clean (no-status) stat line. The old stale-snapshot re-establish (which reverted
	-- mid-session base edits) is gone.
	for _, u in ipairs(allUnitsList) do
		if u.side == "Player" then
			EquipmentService.RebuildUnitStats(u)
		end
	end
	-- Expedition Fortune for mid-battle rewards (chests / treasure / Interact): reset each
	-- battle from the deployed team so ObjectEffectService reward hooks use THIS team's
	-- Fortune. The post-battle block re-sets it from who actually fought. (2026-10-23)
	RewardService.SetExpeditionFortune(RewardService.ComputeExpeditionFortune(allUnitsList))

	print("====================================")
	print("CTRBLXAI — Slice 3: Skills and Real Combat")
	print("====================================")
	for _, u in ipairs(allUnitsList) do
		print(string.format("  %s", UnitSchema.Describe(u)))
	end
	print("====================================")

	--------------------------------------------------
	-- BATTLE STATE
	--------------------------------------------------

	--------------------------------------------------
	-- PLAYER UNIT LOOKUP (needed by doSave and management handlers)
	--------------------------------------------------
	table.clear(playerUnits)  -- clear in place; the base holds a persistent reference (boot-init 2026-10-13)
	for _, u in ipairs(allUnitsList) do
		if u.side == "Player" then
			playerUnits[u.id] = u
			DoctrineInventoryService.EnsureUnitBound(PLAYER_ID, u)
		end
	end

	--------------------------------------------------
	-- SLICE 6: ProgressionService providers + unit-XP sinks
	-- Wired HERE (after playerUnits exists) because these closures capture it.
	--------------------------------------------------
	ProgressionService.SetUnitRecordProvider(function(pid, unitId)
		local u = playerUnits[unitId]
		return u and u.records or nil
	end)
	ProgressionService.SetOnLevelUp(function(pid, unitId, newLevel, newBaseStats)
		local u = playerUnits[unitId]
		if u then
			-- Slice 6 item 2 (2026-10-07): mirror the load-time level fix (~L888-907).
			-- Old code replaced baseStats with race-only stats (dropping saved stat
			-- points) and never rebuilt, so max HP/MP stayed stale until rejoin.
			local oldMaxHp, oldMaxMp = u.maxHp, u.maxMp
			u.level = newLevel
			if type(newBaseStats) == "table" and u.baseStats then
				for stat, value in pairs(newBaseStats) do
					local pts = (u.statAllocation and u.statAllocation[stat]) or 0
					u.baseStats[stat] = value + pts
				end
				EquipmentService.RebuildUnitStats(u)
			end
			-- Runtime HP/MP follow the same rule as PersistentStateService: a max
			-- increase is added to current (missing amount kept); KO units stay at 0.
			-- Battle level-ups run before PersistBattleEnd, which copies these runtime
			-- values into the persistent state, so this keeps the two in step.
			if oldMaxHp and u.maxHp and u.maxHp > oldMaxHp and u.isAlive and (u.currentHp or 0) > 0 then
				u.currentHp = math.min(u.maxHp, u.currentHp + (u.maxHp - oldMaxHp))
			end
			if oldMaxMp and u.maxMp and u.maxMp > oldMaxMp and u.currentMp then
				u.currentMp = math.min(u.maxMp, u.currentMp + (u.maxMp - oldMaxMp))
			end
			if u.maxHp and u.maxMp then
				PersistentStateService.UpdateMaxResources(pid, unitId, u.maxHp, u.maxMp)
			end
			if BattleVisualBroadcaster.UnitStateChanged then
				BattleVisualBroadcaster.UnitStateChanged(u)
			end
		end
	end)
	-- Dispatch sink: (playerId, unitId, xp) -> direct per-unit grant.
	DispatchService.SetUnitXpSink(function(pid, unitId, xp)
		ProgressionService.GrantUnitXp(pid, unitId, xp)
	end)
	-- Explore sink (2026-10-06): ExploreService now calls this with the full context
	-- (playerId, killXp, { squad, battleId, won, mapLevel }). Per the Designer ruling
	-- (unit_progression — the SENT expedition squad are full participants for EVERY
	-- expedition battle), route this battle's kill XP to each unitId in the SENT squad
	-- via ProgressionService.GrantExpeditionUnitXp, which applies the level-up curve
	-- and the Human ×1.10 bonus (see note below; BUG-017 fix).
	-- This replaces the old interim that granted to whoever was CURRENTLY deployed; the
	-- expedition's sent squad is the correct, stable participant set and survives rejoin.
	--
	-- FLAG-E4 (expected): nothing calls ExploreService.StartExpedition with a squad yet
	-- (no expedition-start UI), so ctx.squad is empty for now. In that case this sink
	-- NO-OPS cleanly (no fallback to deployed units — we never invent a participant set).
	-- The start-expedition CALLER must pass the sent-squad list (array of unitIds) once
	-- the UI exists; the plumbing below is ready and needs no further change.
	--
	-- Human ×1.10 on expeditions (RESOLVED, BUG-017): this sink calls
	-- ProgressionService.GrantExpeditionUnitXp, which applies the locked Human ×1.10
	-- itself (expedition-only path). Plain GrantUnitXp (used by Dispatch) still does
	-- NOT apply ×1.10 — dispatch XP is a flat formula (unit_progression 78).
	-- Updated 2026-10-07 (Slice 6 item 3): the old FLAG-EXPLORE-HUMAN note here
	-- predated the BUG-017 fix and was stale.
	ExploreService.SetUnitXpSink(function(pid, killXp, ctx)
		-- ctx = { squad = {unitId,...}, battleId, won, mapLevel }. Third arg is required
		-- for the sent-squad grant; guard it so an old 2-arg caller can never crash here.
		-- Human units get their locked x1.10 inside GrantExpeditionUnitXp (expedition-only path).
		local squad = (type(ctx) == "table" and type(ctx.squad) == "table") and ctx.squad or {}
		if #squad == 0 then
			-- FLAG-E4: no sent squad supplied — no-op (do NOT fall back to deployed units).
			print(string.format(
				"[Main] Explore XP sink: no sent squad (FLAG-E4) — %d XP not granted (awaiting start-expedition caller)",
				killXp))
			return
		end
		for _, unitId in ipairs(squad) do
			if type(unitId) == "string" then
				ProgressionService.GrantExpeditionUnitXp(pid, unitId, killXp, ctx and ctx.battleId)
			end
		end
	end)

	--------------------------------------------------
	-- REUSABLE SAVE HELPER
	--------------------------------------------------

	-- Card inventory (loose, un-equipped skill/augment cards): { skillCards = {[id]=qty},
	-- augmentCards = {[id]=qty} }. Declared BEFORE doSave so doSave captures it as an
	-- upvalue and can persist it. Populated/restored further below (starter + save load).
	-- Clear in place (boot-init 2026-10-13): base holds a persistent reference.
	table.clear(cardInventory.skillCards); table.clear(cardInventory.augmentCards)

	-- (save helper moved to boot — see SAVE HELPER block above the loop, 2026-10-13)

	--------------------------------------------------
	-- SLICE 6: temporary Guild menu wiring (needs playerUnits + doSave, so it lives
	-- here). Every Guild request is validated inside GuildMenuService (SEC-001).
	--------------------------------------------------

	-- UGC setup MOVED TO BOOT (2026-10-13): see the "UGC RENTAL & OWNERSHIP" block above
	-- the loop. It must run once at startup so the Outfit tab works at the base before any
	-- quest launches, and so the availability loop + remote wiring do not re-stack each round.

	--------------------------------------------------
	-- MANAGEMENT REMOTEFUNCTIONS (Slice 4D)
	-- Active throughout the session (pre-battle, post-battle, hub)
	--------------------------------------------------



	-- LOADOUT REQUEST HANDLERS: now registered ONCE at boot (above the loop, 2026-10-13)
	-- so unit management works at the base before any quest is launched. Previously this
	-- Init sat here inside the loop, which is why the loadout screen's data fetch went
	-- unanswered until a quest was picked.

	--------------------------------------------------
	-- BONUS DISPLAY RESOLVER
	-- Converts raw bonusLines/bonusPassiveIds into UI-friendly format.
	-- bonusStats: { STR = 1, VIT = 2 }  (scaled flat at item level)
	-- bonusPassives: { { name = "Brutal", icon = "✦", desc = "" } }
	--------------------------------------------------

	-- [ItemDisplay] BONUS_DISPLAY_KEY / resolveItemBonuses / buildItemEntry moved to Game/ItemDisplay.lua (2026-10-12)




	--------------------------------------------------
	-- DOCTRINE MANAGEMENT (Slice 4H)
	--------------------------------------------------

	-- GetDoctrineChoices: returns available doctrines and their skill choices

	-- RequestDoctrineSkillSelect: pick one of the 3 skill choices

	--------------------------------------------------
	-- SKILL CARD & AUGMENT CARD MANAGEMENT (Slice 4I)
	--------------------------------------------------

	-- Card inventory: declared earlier (before doSave) so it can be persisted.
	-- Clear in place (boot-init 2026-10-13) before restore/starter population;
	-- base holds a persistent reference, so don't replace the table.
	table.clear(cardInventory.skillCards); table.clear(cardInventory.augmentCards)

	-- Restore persisted card inventory from the save (progression.cardInventory).
	-- savedCardInventory is populated in the load block above when the save carried it.
	-- COPY values in (2026-10-13), never alias: cardInventory is cleared in place each
	-- round, so sharing savedCardInventory's subtables by reference would let that clear
	-- wipe the durable save snapshot (returning players lost their saved cards). Copy keeps
	-- the snapshot untouched while filling the base's persistent cardInventory tables.
	if savedCardInventory and type(savedCardInventory) == "table" then
		if type(savedCardInventory.skillCards) == "table" then
			for id, qty in pairs(savedCardInventory.skillCards) do cardInventory.skillCards[id] = qty end
		end
		if type(savedCardInventory.augmentCards) == "table" then
			for id, qty in pairs(savedCardInventory.augmentCards) do cardInventory.augmentCards[id] = qty end
		end
	end

	-- Populate starter cards ONLY when the inventory is genuinely empty (fresh player,
	-- or an old save that predates card persistence -> granted once, then persists).
	-- After the first save, cardInventory is restored above and this block is skipped,
	-- so starter cards are never re-granted (fixes the relaunch multiplication bug).
	do
		local hasAny = false
		for _ in pairs(cardInventory.skillCards) do hasAny = true; break end
		if not hasAny then
			for _ in pairs(cardInventory.augmentCards) do hasAny = true; break end
		end
		if not hasAny then
			-- Fill in place (2026-10-13), don't replace the subtables, so cardInventory's
			-- subtable identity stays stable across rounds (clear-in-place + copy-restore).
			local starterSkills = {
				["SKL-POWER-STRIKE"] = 1, ["SKL-SWEEPING-CUT"] = 1,
				["SKL-FIRE-BOLT"] = 1, ["SKL-HEALING-LIGHT"] = 1,
				["SKL-CRIPPLING-SHOT"] = 1, ["SKL-VENOM-BURST"] = 1,
			}
			local starterAugments = { ["AUG-BLEEDING-EDGE-SUPPORT"] = 2, ["AUG-VENOMOUS-SUPPORT"] = 2 }
			for id, qty in pairs(starterSkills) do cardInventory.skillCards[id] = qty end
			for id, qty in pairs(starterAugments) do cardInventory.augmentCards[id] = qty end
			print("[Main] Starter cards loaded (6 skill, 4 augment)")
		end
	end

	-- Tags-only augment cleanup on save load (user ruling 2026-10-26): equipped augments that no
	-- longer fit their skill are unequipped and returned to the card inventory restored above.
	-- Idempotent. A player-facing notice listing the removed augments is pending the user's
	-- approval of its wording (no new helper text without approval); Output logs each removal.
	do
		local removedAugs = LoadoutRequestHandlers.UnequipIncompatibleAugments(allUnitsList)
		if #removedAugs > 0 then
			print(string.format("[Main] Save-load augment cleanup: %d augment(s) returned to inventory", #removedAugs))
		end
	end

	-- Starter consumables: equip a healing potion on Hero if no consumables saved
	do
		local heroUnit = nil
		for _, u in ipairs(allUnitsList) do
			if u.id == "unit_hero" then heroUnit = u; break end
		end
		if heroUnit and (not heroUnit.consumableSlots or not heroUnit.consumableSlots[1]) then
			heroUnit.consumableSlots = heroUnit.consumableSlots or {}
			heroUnit.consumableSlots[1] = {
				consumableId = "REC-001",  -- Emergency Small Healing Potion
				currentCharges = 1,
				maxCharges = 1,
			}
			print("[Main] Starter consumable equipped: REC-001 on Hero slot 1")
		end
	end


	-- GetSkillLoadout: returns unit's skill slots + card inventories

	-- RequestEquipSkillCard: equip a skill card into slot 2/3/4

	-- RequestUnequipSkillCard: remove a skill card from slot 2/3/4

	-- RequestAttachAugment: attach an augment card to a skill's augment slot

	-- RequestDetachAugment: remove an augment from a skill's augment slot

	--------------------------------------------------
	-- CONSUMABLE SLOT MANAGEMENT (Slice 4G.4)
	--------------------------------------------------


	-- RequestEquipConsumable: assign a consumable to a slot (1-6)

	-- RequestUnequipConsumable: remove consumable from slot

	-- RequestSetPortrait: player picks a 2D race portrait for one of their units.
	-- Server-authoritative validation (SEC-001, never trust the client): the unit
	-- must be the player's, assetId must be a number, and it MUST belong to the
	-- unit's own race portrait pool. A nil assetId clears the choice (back to the
	-- colored-box fallback). The choice is stored on the live unit and persists via
	-- the normal save path (encodeUnit 'por'). Headshot mode (option A) is deferred.

	-- RequestSetBodyColor: player picks a body/skin tint for one of their units.
	-- Server-authoritative: unit must be the player's; r/g/b must be numbers, clamped
	-- to 0-255 integers. A nil r clears the tint. Stored on the live unit as a {r,g,b}
	-- table and persisted via the save path (encodeUnit 'bcl'). The tint is applied to
	-- the model by UGCOutfitService (battle + loadout preview) via the body-color
	-- provider wired below.

	-- GetConsumableSlots: return all consumable slot data for all player units

	--------------------------------------------------
	-- STAT ALLOCATION & COMPARISON (Slice 4J)
	--------------------------------------------------

	-- Allocable stat points (USER RULING 2026-10-07): 3 per level-up for every unit;
	-- Humans (Adaptability) get 4 on every 3rd level-up. Points are DERIVED from the
	-- unit's current level minus points spent, never stored as a running total, so
	-- rejoins / level restores cannot double-grant. Race growth (unit_progression 49)
	-- still applies on top.

	-- GetUnitFullStats: returns complete stat breakdown for Info tab

	-- GetEquipmentComparison: authoritative before/after deltas for equipping an item

	-- GetDoctrineComparison: authoritative before/after for swapping doctrine

	--------------------------------------------------
	-- HUB + REWARD SCREEN HELPERS
	--------------------------------------------------









	--------------------------------------------------
	-- DEV COMMANDS (Studio only -- instant win/lose/kill)
	--------------------------------------------------

	local _devForceResult = nil -- "PlayerWin" or "PlayerLose"


	-- PRE-BATTLE GUILD MENU (Slice 6 temporary Guild menu, 2026-10-07). Replaces the
	-- pre-battle Loadout Hub; its Units button opens that same loadout screen, and
	-- leaving fires the same BattleEvents.StartBattle -> hubContinueSignal as before.
	-- Battle prep finished — unlock the sortie button that has shown "Scouting the battle
	-- map..." since quest selection. The sortie menu is ALREADY open (scouting state); we do
	-- NOT re-open it (that teardown/relabel was the old flow). Just flip the button live.
	print("[Hub] Battle prep complete — unlocking sortie")
	mapReadyForStart = true  -- map is genuinely built now; StartBattle is accepted from here
	BattleEvents.MapBuildComplete:FireAllClients()

	-- Sync map data (terrain/elevation/blockers) to client for tile inspector
	BattleEvents.MapDataSync:FireAllClients({
		terrainGrid  = generatedMap.terrainGrid,
		elevationGrid = generatedMap.elevationGrid,
		objectGrid   = generatedMap.objectGrid,
		blockers     = generatedMap.blockers,
		mapWidth     = MAP_WIDTH,
		mapHeight    = MAP_HEIGHT,
	})

	-- SORTIE BRIEFING (bug 2, 2026-10-13): the player either confirms (Start Battle ->
	-- deployment) OR abandons the accepted quest. Abandoning forfeits 50% of the quest's
	-- posted gold (game_flow id 28), clamped to what the player can pay so backing out is
	-- never hard-blocked, then returns to the base WITHOUT a battle (loop restarts).
	local departDecision = nil  -- "go" | "abandon"
	-- Chosen party for this sortie (game_flow id 10/27 Choose Party). Default to the first
	-- non-empty saved party (Party A is auto-seeded first-run) so a plain Continue always
	-- deploys a valid party; the Party tab lets the player pick A/B/C (SelectSortieParty).
	local chosenPartySlot = nil
	for _, s in ipairs({ "A", "B", "C" }) do
		if #PartyService.GetMembers(PLAYER_ID, s) > 0 then chosenPartySlot = s break end
	end
	do
		local decided = Instance.new("BindableEvent")
		local goConn = hubContinueSignal.Event:Connect(function()
			if not departDecision then departDecision = "go"; decided:Fire() end
		end)
		local abandonConn = BattleEvents.AbandonQuest.OnServerEvent:Connect(function(plr)
			if not departDecision then departDecision = "abandon"; decided:Fire() end
		end)
		local partyConn = BattleEvents.SelectSortieParty.OnServerEvent:Connect(function(plr, slot)
			if departDecision then return end
			-- SELECT-ONLY (2026-10-15): picking a party updates the pending selection but does
			-- NOT start the battle; the player commits with Continue to Deployment (goConn path).
			if type(slot) == "string" and #PartyService.GetMembers(PLAYER_ID, slot) > 0 then
				chosenPartySlot = slot
			end
		end)
		decided.Event:Wait()
		goConn:Disconnect()
		abandonConn:Disconnect()
		partyConn:Disconnect()
		decided:Destroy()
	end

	if departDecision == "abandon" then
		-- 50% of the quest's posted gold, clamped to the player's balance.
		local posted = (selectedQuest and selectedQuest.rewards and selectedQuest.rewards.questGold) or 0
		local penalty = math.floor(posted * 0.5)
		local haveGold = (CurrencyService.GetBalance(PLAYER_ID) or {}).gold or 0
		local charged = math.min(penalty, haveGold)
		if charged > 0 then
			CurrencyService.Debit(PLAYER_ID, { gold = charged })
		end
		print(string.format("[Hub] Quest abandoned — penalty %d gold (posted %d, charged %d).",
			penalty, posted, charged))
		GuildMenuService.Close()
		doSave()  -- persist the gold change before returning to base
		continue  -- back to the top of the loop (guild base), no battle this round
	end

	print("[Hub] Player ready — entering deployment phase")
	GuildMenuService.Close()
	-- Guild menu effects on THIS battle's roster (in place; closures hold allUnitsList):
	-- add units hired just now, drop units away on dispatch, bench only beyond the
	-- PARTY CEILING (MAX_DEPLOY = 7), NOT the per-quest deploy limit (2026-10-18).
	-- The full party attends; the quest's unit limit is enforced later as a
	-- placement cap during deployment, not by benching here. Passing MAX_DEPLOY
	-- (SyncBattleRoster clamps to min(MAX_DEPLOY, cap)) keeps the whole party.
	GuildMenuService.SyncBattleRoster(allUnitsList, PartyService.MAX_PARTY_SIZE, PartyService.GetMembers(PLAYER_ID, chosenPartySlot or ""))

	-- === DEPLOYMENT PHASE ===
	-- Player manually places each unit on PD (Player Deployment) tiles.
	-- Enemy units are already positioned at ED (Enemy Deployment) anchors.

	local function serializeForDeployment(unitList, side)
		local result = {}
		for _, u in ipairs(unitList) do
			if u.side == side then
				-- UNIFIED PACKAGING (2026-10-22): deployment now uses the SAME serializer
				-- battle uses (BattleVisualBroadcaster.SerializeUnit), so both phases describe
				-- every unit identically -- a field can never again be present in battle's
				-- packet and missing from deployment's (the root cause behind facing / HP-MP /
				-- stats drift). Only the weapon LABEL stays phase-specific: deployment shows the
				-- archetype name ("Sword") while battle shows the item name, so override it here.
				local packet = BattleVisualBroadcaster.SerializeUnit(u)
				local wpnName = "Unarmed"
				if u.equipmentSlots and u.equipmentSlots.MainHand then
					local wArch = WeaponData.GetByArchetypeId(u.equipmentSlots.MainHand.baseArchetypeId)
					if wArch then wpnName = wArch.name end
				end
				packet.weaponName = wpnName
				table.insert(result, packet)
			end
		end
		return result
	end

	local deployPlayerUnits = {}
	local deployEnemyUnits  = {}
	for _, u in ipairs(allUnitsList) do
		if u.side == "Player" then
			table.insert(deployPlayerUnits, u)
		else
			table.insert(deployEnemyUnits, u)
		end
	end

	-- VISUAL CLEANUP (2026-10-15): destroy leftover unit models from the PREVIOUS battle
	-- before this battle's models spawn. Enemy units get fresh ids each battle, so last
	-- battle's enemy R15 clones (Unit_<oldId>) were orphaned in the UnitModels folder and
	-- lingered -- floating over the new map during deployment. Nothing for THIS battle has
	-- spawned yet here (enemies spawn just below; player units spawn as they deploy), so
	-- clearing the whole folder is safe -- every current model is (re)created afterward.
	do
		local _staleModels = workspace:FindFirstChild("UnitModels")
		if _staleModels then
			_staleModels:ClearAllChildren()
			print("[Main] Cleared leftover unit models from the previous battle.")
		end
	end

	-- Deployment cap + tile count (2026-10-18 user ruling).
	-- The quest's unit limit (playerSlots) is the MAX number of units the
	-- player may actually place. The player may still bring a full party; the
	-- extra units simply cannot be deployed. The number of placement tiles
	-- shown is ceil(limit * 1.5), so there are always MORE tiles than the cap
	-- and at least a few tiles stay empty when the battle starts (tactical
	-- choice of WHERE to place, not just whether).
	local questDeployLimit = math.max(1, math.floor((selectedQuest and selectedQuest.playerSlots) or 7))
	local desiredTiles     = math.ceil(questDeployLimit * 1.5)
	local deployAnchorsToShow = {}
	local maxPDAnchors = math.min(#playerSpawns, desiredTiles)
	for i = 1, maxPDAnchors do
		table.insert(deployAnchorsToShow, playerSpawns[i])
	end
	if maxPDAnchors < desiredTiles then
		warn(string.format(
			"[Deploy] Map provided only %d player tile(s); quest limit %d wanted %d (ceil 1.5x). Showing %d.",
			#playerSpawns, questDeployLimit, desiredTiles, maxPDAnchors))
	end
	print(string.format(
		"[Deploy] Quest unit limit %d -> %d placement tile(s) (ceil 1.5x); full party may attend, max %d deployable.",
		questDeployLimit, maxPDAnchors, questDeployLimit))

	-- UGC (ugc_rules Enemy Outfits / enemy_outfit_apply_point): plan this battle's
	-- enemy outfits from a seeded RNG (own offset, so enemyRng is not consumed),
	-- lock UGC looks until battle end, and dress every Unit_ model as it is parented
	-- (covers the enemy, deploy and fallback spawn paths below).
	-- PLAYER-WORN EXCLUSION (ugc_rules 26, Locked 2026-10-22): collect the UGC item ids
	-- currently equipped by ANY unit in the WHOLE active (chosen saved) party — up to 7
	-- units, INCLUDING benched units not deployed this battle (PartyService.GetMembers
	-- returns the full party, bench happens at placement, not here). Reuse the existing
	-- read-only UGCService.GetUnitLookIds accessor (same path that dresses player units);
	-- no new accessor, no RNG consumed. PlanEnemyOutfits removes these ids from the
	-- enemy candidate pool FIRST so zero enemies advertise an item the party already
	-- wears. Determinism holds: the set is derived from the party's current equips, a
	-- reproducible battle input (ugc_rules 27).
	local partyWornLookIds: { number } = {}
	do
		local seen: { [number]: boolean } = {}
		for _, partyUnitId in PartyService.GetMembers(PLAYER_ID, chosenPartySlot or "") do
			for _, wornId in UGCService.GetUnitLookIds(PLAYER_ID, partyUnitId) do
				if not seen[wornId] then
					seen[wornId] = true
					table.insert(partyWornLookIds, wornId)
				end
			end
		end
	end
	UGCOutfitService.PlanEnemyOutfits(PLAYER_ID, deployEnemyUnits, Random.new((generatedMap.seed or os.time()) + 90002), partyWornLookIds)
	UGCService.SetBattleActive(PLAYER_ID, true)
	UGCOutfitService.WatchUnitModels(PLAYER_ID)

	-- Center-facing helper (2026-10-17): during deployment and at battle start, every
	-- unit model should face the geometric CENTER of the map. We reuse the game's own
	-- facing convention (GameConstants.FACING_VECTORS: worldDir = Vector3(dx,0,dy)) so a
	-- model placed here looks the same way the client's orientUnitToFacing would turn it.
	-- Returns a CFrame that stands the model's feet at (wx,wy,wz) looking toward center.
	local function centerFacingCFrame(wx, wy, wz, tileX, tileY)
		local pos = Vector3.new(wx, wy, wz)
		-- Face the single center tile stamped at map generation (walkable tile nearest the
		-- middle); fall back to the raw midpoint only if the map lacks it.
		local _ct = generatedMap and generatedMap.centerTile
		local cx = (_ct and _ct.x) or (MAP_WIDTH / 2)
		local cy = (_ct and _ct.y) or (MAP_HEIGHT / 2)
		local f = GameConstants.CalcFacingFrom(tileX, tileY, cx, cy)
		local vec = f and GameConstants.FACING_VECTORS[f]
		if not vec or (vec.dx == 0 and vec.dy == 0) then
			return CFrame.new(pos)  -- unit already at center: keep default orientation
		end
		return CFrame.lookAt(pos, pos + Vector3.new(vec.dx, 0, vec.dy))
	end

	-- Spawn R15 models for enemy units (they're already positioned)
	local _raceModelsFolder = game:GetService("ServerStorage"):FindFirstChild("RaceModels")
	if _raceModelsFolder then
		local _umf = workspace:FindFirstChild("UnitModels")
		if not _umf then _umf = Instance.new("Folder"); _umf.Name = "UnitModels"; _umf.Parent = workspace end
		for _, eu in ipairs(deployEnemyUnits) do
			local _rn = eu.raceId and RaceData.GetRace(eu.raceId) and RaceData.GetRace(eu.raceId).name or nil
			local _tpl = _rn and _raceModelsFolder:FindFirstChild(_rn)
			if _tpl and _tpl:IsA("Model") then
				local c = _tpl:Clone()
				c.Name = "Unit_" .. eu.id
				-- STREAMING FIX (2026-10-21): make the battle unit always-present on the
				-- client. StreamingEnabled is on, so a server-spawned model can arrive late,
				-- partially, or not at all for far tiles -- the documented cause of deployment
				-- cylinders (model nil on client) and T-pose (rig parented before descendants
				-- replicate). Persistent loads after join and never streams out. Set before
				-- parenting so it applies on first replication.
				c.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
				-- Kill the R15 built-in overhead name/health tag (client HP-bar shows the name).
				local _h1 = c:FindFirstChildOfClass("Humanoid")
				if _h1 then _h1.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None; _h1.NameDisplayDistance = 0; _h1.HealthDisplayDistance = 0 end
				local hrp = c.PrimaryPart or c:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.Anchored = true
					local _ox = -(MAP_WIDTH * 5) / 2
					local _oz = -(MAP_HEIGHT * 5) / 2
					local _elev = generatedMap.elevationGrid and generatedMap.elevationGrid[eu.tileY]
						and generatedMap.elevationGrid[eu.tileY][eu.tileX] or 1
					local _tileTopY = GameConstants.TileSurfaceY(_elev)  -- shared single-source tile height
					-- Stand TRUE FEET on the surface via the shared bbox-bottom helper
					-- (race rigs with pivot-above-feet otherwise bury). Facing preserved.
					local _wx = _ox + (eu.tileX - 0.5) * 5
					local _wz = _oz + (eu.tileY - 0.5) * 5
					local _face = centerFacingCFrame(_wx, _tileTopY, _wz, eu.tileX, eu.tileY)
					c:PivotTo(GameConstants.GroundModelPivotCFrame(c, _wx, _tileTopY, _wz, _face))
				end
				c.Parent = _umf
				attachWeaponToUnit(c, eu)
				print(string.format("[Deploy] Enemy %s → R15 model '%s' at (%d,%d)", eu.name, _rn, eu.tileX, eu.tileY))
			end
		end
	end

	-- PRE-BUILD PLAYER MODELS (2026-10-21): build every deployable player unit's model
	-- up front and park it hidden below the map, exactly as enemies are built up front.
	-- Parenting to UnitModels immediately triggers UGC dressing, so each unit's outfit
	-- downloads during the player's orientation window. Deploying a unit then just slides
	-- the finished, already-dressed model onto the tile (no ~3s per-unit load). Returns
	-- the model (building it if somehow not yet built), or nil if the race has no model.
	local PLAYER_PARK_Y = -200  -- hidden well below the battlefield; camera never looks here
	local function ensurePlayerModelBuilt(u, idx)
		local umf = workspace:FindFirstChild("UnitModels")
		if not umf then umf = Instance.new("Folder"); umf.Name = "UnitModels"; umf.Parent = workspace end
		local existing = umf:FindFirstChild("Unit_" .. u.id)
		if existing then return existing end
		local raceModels = game:GetService("ServerStorage"):FindFirstChild("RaceModels")
		local raceName = u.raceId and RaceData.GetRace(u.raceId) and RaceData.GetRace(u.raceId).name or nil
		local template = raceName and raceModels and raceModels:FindFirstChild(raceName)
		if not (template and template:IsA("Model")) then return nil end
		local clone = template:Clone()
		clone.Name = "Unit_" .. u.id
		clone.ModelStreamingMode = Enum.ModelStreamingMode.Persistent  -- always-present (see enemy note)
		local _h = clone:FindFirstChildOfClass("Humanoid")
		if _h then _h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None; _h.NameDisplayDistance = 0; _h.HealthDisplayDistance = 0 end
		local hrp = clone.PrimaryPart or clone:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.Anchored = true end
		clone:PivotTo(CFrame.new((idx or 0) * 6, PLAYER_PARK_Y, 0))  -- parked hidden until deployed
		clone.Parent = umf  -- parenting here starts UGC dressing (WatchUnitModels)
		attachWeaponToUnit(clone, u)
		return clone
	end
	for idx, u in ipairs(deployPlayerUnits) do
		ensurePlayerModelBuilt(u, idx)
	end

	BattleEvents.DeploymentPhase:FireAllClients({
		playerAnchors = deployAnchorsToShow,
		enemyUnits    = serializeForDeployment(allUnitsList, "Enemy"),
		playerUnits   = serializeForDeployment(allUnitsList, "Player"),
		awayUnits     = GuildMenuService.GetAwayUnitsForDeployment(), -- greyed out, not placeable
		mapWidth      = MAP_WIDTH,
		mapHeight     = MAP_HEIGHT,
		-- Max units the player may actually DEPLOY this battle (quest playerSlots),
		-- NOT the tile count (tiles = ceil(limit*1.5), always more than the cap).
		-- Drives the deployment "deployed / max" counter in the HUD. (2026-10-18)
		playerDeployLimit = questDeployLimit,
	})

	print(string.format("[Deploy] Phase started — %d PD anchors, %d player units to place, %d enemies pre-placed",
		#playerSpawns, #deployPlayerUnits, #deployEnemyUnits))

	for i, a in ipairs(deployAnchorsToShow) do
		print(string.format("[Deploy]   PD anchor %d: (%d, %d)", i, a.x, a.y))
	end

	local deployedCount = 0
	local occupiedTiles = {}
	local deploymentCompleteSignal = Instance.new("BindableEvent")

	for _, u in ipairs(deployEnemyUnits) do
		occupiedTiles[u.tileY * 100000 + u.tileX] = true
	end

	local deployConn = BattleEvents.DeployUnit.OnServerEvent:Connect(function(plr, data)
		if not data or not data.unitId or not data.tileX or not data.tileY then return end

		local validTile = false
		-- Validate against the trimmed anchor list (2× player count), not all PD tiles.
		for _, anchor in ipairs(deployAnchorsToShow) do
			if anchor.x == data.tileX and anchor.y == data.tileY then validTile = true; break end
		end
		if not validTile then
			warn(string.format("[Deploy] REJECTED: tile (%d,%d) is not a valid PD anchor", data.tileX, data.tileY))
			return
		end

		local tileKey = data.tileY * 100000 + data.tileX
		if occupiedTiles[tileKey] then
			warn(string.format("[Deploy] REJECTED: tile (%d,%d) already occupied", data.tileX, data.tileY))
			return
		end

		-- Per-quest deploy cap (2026-10-18): at most questDeployLimit units may be
		-- placed, even though more tiles exist and a larger party may be present.
		-- Re-deploying an already-placed unit (handled below) does not hit this
		-- because that path is rejected as "already deployed"; this guards NEW
		-- placements only.
		if deployedCount >= questDeployLimit then
			warn(string.format(
				"[Deploy] REJECTED: deploy cap reached (%d/%d). Undeploy a unit to move it.",
				deployedCount, questDeployLimit))
			return
		end

		local unit = nil
		for _, u in ipairs(deployPlayerUnits) do
			if u.id == data.unitId then unit = u; break end
		end
		if not unit then
			warn(string.format("[Deploy] REJECTED: unit %s not found", tostring(data.unitId)))
			return
		end
		if unit.tileX ~= 0 or unit.tileY ~= 0 then
			warn(string.format("[Deploy] REJECTED: unit %s already deployed at (%d,%d)", unit.name, unit.tileX, unit.tileY))
			return
		end

		unit.tileX = data.tileX
		unit.tileY = data.tileY
		occupiedTiles[tileKey] = true
		deployedCount = deployedCount + 1

		setTileOccupant(unit.tileX, unit.tileY, unit.name, "Unit (" .. unit.side .. ")", "Blocking")

		BattleEvents.UnitDeployed:FireAllClients({
			unitId = unit.id,
			tileX  = data.tileX,
			tileY  = data.tileY,
		})

		-- Place the PRE-BUILT (already-dressed) model onto the tile -- no clone/dress here,
		-- so deploying feels instant. ensurePlayerModelBuilt returns the model parked at
		-- deployment start (or builds it now as a safety fallback if somehow missing).
		local model = ensurePlayerModelBuilt(unit)
		if model then
			local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.Anchored = true
				local _ox = -(MAP_WIDTH * 5) / 2
				local _oz = -(MAP_HEIGHT * 5) / 2
				local _elev = generatedMap.elevationGrid and generatedMap.elevationGrid[data.tileY]
					and generatedMap.elevationGrid[data.tileY][data.tileX] or 1
				local _feetY = GameConstants.TileSurfaceY(_elev)  -- shared single-source tile height
				-- Stand TRUE FEET on the surface via the shared bbox-bottom helper; face center.
				local _wx = _ox + (data.tileX - 0.5) * 5
				local _wz = _oz + (data.tileY - 0.5) * 5
				local _face = centerFacingCFrame(_wx, _feetY, _wz, data.tileX, data.tileY)
				model:PivotTo(GameConstants.GroundModelPivotCFrame(model, _wx, _feetY, _wz, _face))
			end
		end

		print(string.format("[Deploy] %s placed at (%d,%d) — %d/%d deployed",
			unit.name, data.tileX, data.tileY, deployedCount, #deployPlayerUnits))
	end)

	-- UNDEPLOY: Player removes a previously deployed unit
	undeployConn = BattleEvents.UndeployUnit.OnServerEvent:Connect(function(plr, data)
		if not data or not data.unitId then return end

		local unit = nil
		for _, u in ipairs(deployPlayerUnits) do
			if u.id == data.unitId then unit = u; break end
		end
		if not unit then
			warn(string.format("[Deploy] UNDEPLOY REJECTED: unit %s not found", tostring(data.unitId)))
			return
		end
		if unit.tileX == 0 and unit.tileY == 0 then
			warn(string.format("[Deploy] UNDEPLOY REJECTED: unit %s is not deployed", unit.name))
			return
		end

		local oldX, oldY = unit.tileX, unit.tileY
		local tileKey = oldY * 100000 + oldX
		occupiedTiles[tileKey] = nil
		unit.tileX = 0
		unit.tileY = 0
		deployedCount = deployedCount - 1

		BattleEvents.UnitUndeployed:FireAllClients({
			unitId = unit.id,
			tileX  = oldX,
			tileY  = oldY,
		})

		-- Park the model hidden again instead of destroying it, so re-deploying is
		-- instant (it stays built and dressed). Benched models are cleaned up when the
		-- battle actually starts (below).
		local _umf = workspace:FindFirstChild("UnitModels")
		if _umf then
			local existing = _umf:FindFirstChild("Unit_" .. unit.id)
			if existing then existing:PivotTo(CFrame.new(0, -200, 0)) end
		end

		print(string.format("[Deploy] %s UNDEPLOYED from (%d,%d) — %d/%d deployed",
			unit.name, oldX, oldY, deployedCount, #deployPlayerUnits))
	end)

	local readyConn = BattleEvents.DeploymentReady.OnServerEvent:Connect(function(plr)
		-- At least ONE unit must be deployed (user ruling 2026-10-07; was: all units).
		if deployedCount >= 1 then
			deploymentCompleteSignal:Fire()
		else
			warn("[Deploy] Ready signal but no unit deployed — waiting")
		end
	end)

	deploymentCompleteSignal.Event:Wait()
	deployConn:Disconnect()
	readyConn:Disconnect()
	if undeployConn then undeployConn:Disconnect() end
	deploymentCompleteSignal:Destroy()

	-- Units the player left undeployed sit out this battle: remove them from the battle
	-- roster so they never enter play at tile (0,0). They stay owned (playerUnits), so the
	-- post-battle XP step counts them as benched.
	for i = #allUnitsList, 1, -1 do
		local u = allUnitsList[i]
		if u.side == "Player" and u.tileX == 0 and u.tileY == 0 then
			table.remove(allUnitsList, i)
			print(string.format("[Deploy] %s not deployed — sits out this battle", u.name))
		end
	end
	for i = #deployPlayerUnits, 1, -1 do
		local u = deployPlayerUnits[i]
		if u.tileX == 0 and u.tileY == 0 then
			-- Benched (not fielded): remove its pre-built parked model so it doesn't
			-- linger hidden below the map during the battle.
			local _umf = workspace:FindFirstChild("UnitModels")
			local m = _umf and _umf:FindFirstChild("Unit_" .. u.id)
			if m then m:Destroy() end
			table.remove(deployPlayerUnits, i)
		end
	end
	print(string.format("[Deploy] %d player unit(s) deployed — starting battle", #deployPlayerUnits))

	-- === INITIATIVE (DB core_stats id 54, user ruling 2026-10-02) ===
	-- STEP 1 (every unit, once, at initial deployment): LUK Starting RT =
	--   round(Base RT x (1 - 0.30 x LUK / (100 + LUK))). Player units use standard
	--   Base RT 400 and their FINAL effective LUK (doctrine/gear included — same basis
	--   EnemyGenerator uses for enemies, which already received STEP 1 on their tier RT).
	-- STEP 2 (PLAYER-ROSTER units only): Player Initiative Edge = -10 RT (min 1), applied
	--   LAST, after any % Starting-RT modifiers (none implemented yet). Never applied to
	--   enemies, neutrals, allied NPCs, summons or mid-battle reinforcements (those are
	--   not in deployPlayerUnits / not controller "Player").
	for _, u in ipairs(deployPlayerUnits) do
		if u.side == "Player" and u.controller == "Player" then
			local luk = (u.effectiveStats and u.effectiveStats.LUK) or 10
			-- Starting RT (one-time) from Modified Base RT × LUK reduction, then the trait
			-- Starting-RT % (Timeline Sovereign −12% / Temporal Drag +15%) layers on BEFORE
			-- the flat Player Initiative Edge, which stays last (DB core_stats id 54, trait
			-- Starting-RT % approved 2026-10-04).
			-- Single rounding (DB core_stats 54): raw Modified Base RT × LUK factor × trait %,
			-- rounded ONCE, then the flat Player Initiative Edge last.
			local modBaseRt = StatusService.GetModifiedBaseRt(u)
			local lukFactor = 1 - 0.30 * luk / (100 + luk)
			local lukRt = math.round(modBaseRt * lukFactor * TraitEffectService.GetStartingRtMultiplier(u))
			u.remainingRt = GameConstants.ApplyPlayerInitiativeEdge(lukRt)
			print(string.format("[Initiative] %s LUK %d: %d -> %d (player edge -%d)",
				u.name, luk, lukRt, u.remainingRt, GameConstants.PLAYER_INITIATIVE_EDGE_RT))
		end
	end

	-- === BATTLE START ===
	state = BattleCoordinator.CreateBattleState(allUnitsList)
	-- Treasure/reward context (fix 2026-10-24): stamp the owning player id and the
	-- map level onto the battle state so object handlers that generate rewards
	-- (Treasure Chest, Cursed Chest via _grantChestReward, Black Market) can reach
	-- them. These were ALWAYS the fields those handlers read (state.ownerPlayerId /
	-- state.mapLevel); they were simply never populated, so the chest reward hit its
	-- honest DEFERRED path and granted nothing. PLAYER_ID and the quest level are the
	-- same sources the post-battle reward grant (RewardService.GenerateRewards) and
	-- AwardBattleXp already use, so chest loot now matches end-of-battle loot exactly.
	state.ownerPlayerId = PLAYER_ID
	state.mapLevel      = (activeQuest and activeQuest.recommendedLvl) or 1
	StatusService.SetAuraUnitsProvider(function() return state and state.units end)  -- Ward Tot
	CombatResolver.SetUnitsProvider(function() return state and state.units end)  -- BD-014 Guardian Mantle (adjacent-ally guard share)em aura
	-- Status conflict rules (2026-10-07): notify clients when a conflict removes a status.
	StatusService.SetConflictRemovedHandler(function(unit, statusId)
		if BattleVisualBroadcaster.StatusExpired then BattleVisualBroadcaster.StatusExpired(unit, statusId) end
		if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(unit) end
	end)

	-- Slice 5 map objects: seed the battle state with the generated map's placed
	-- objects so Interact candidacy, aura reconcile, and the death-sweep can see
	-- them. The generator (MapService.placeObjects) emits { id, type, x, y } onto
	-- generatedMap.objects; the battle state carries the SAME shape (no remap).
	-- Without this, state.objects is nil and every map-object effect is inert.
	state.objects = generatedMap.objects or {}
	-- OBS Phase 2a: seed runtime HP (3) on breakable blocker-prop OBS objects so the
	-- map-object inspector shows N/3 and Phase 2c's 3-hit break can decrement it.
	-- Billboards / unbreakable objects get no hp. Dormant otherwise (nothing reads hp yet).
	ObjectEffectService.InitObjectHp(state)

	-- Time cycle: battle starts at Dawn (ct 0). Prime RacePassiveService + resync any
	-- day/night-dependent units (Vampire/Werewolf) and tell the client, so turn-1
	-- stats and UI are correct before the clock first advances.
	RacePassiveService.SetTimePhase(state.timePhase or "Dawn")
	for _, u in ipairs(state.units) do
		if u.isAlive then RacePassiveService.RefreshConditionalStats(u) end
	end
	BattleVisualBroadcaster.TimePhaseChanged(state.timePhase or "Dawn")

	-- Weather engine: initialize the combined weather/crisis slot from the quest's
	-- biome pool + the starting condition the map generator selected, then apply the
	-- starting condition's onset statuses (e.g. Rain Wet, Snow Storm Frozen) so turn-1
	-- is correct before the first clock tick. Re-rolls each round thereafter.
	WeatherService.InitFromBiome(selectedQuest.biome, generatedMap.battleCondition, state.ct)
	WeatherService.ApplyStartingOnset(state)

	-- Slice 5 map objects: reset the per-battle object usage ledger, then apply any
	-- passive auras (War Banner / Cursed Statue) to units already standing in range
	-- at deployment. Subsequent entries/exits are reconciled on each Move.
	ObjectEffectService.ResetBattle()
	ObjectEffectService.ReconcileAuras(state.units, state)

	-- Battlefield events: pick this battle's events (0-3 random + conditional) and
	-- spawn the start ones. Separate from weather; layers on top. Seed the enemy
	-- count the Champion conditional compares against.
	do
		local ec = 0
		for _, u in ipairs(state.units) do if u.side == "Enemy" and u.isAlive then ec = ec + 1 end end
		state.enemyCountAtStart = ec
		state.playerDeployTiles = (generatedMap and generatedMap.deploymentZones and generatedMap.deploymentZones.player) or {}
		state.enemyDeployTiles = (generatedMap and generatedMap.deploymentZones and generatedMap.deploymentZones.enemy) or {}  -- Fear destination + terrain protection (2026-10-26)
		-- Seed from the map seed (varies per battle). Was state.ct + 70007, and ct is 0 at
		-- battle start, so every battle rolled the SAME events (always Fog Spirit).
		-- Per-battle seed, stored on state so the round/turn/weather rolls vary per battle too.
		state.battleSeed = (generatedMap and generatedMap.seed) or os.time()
		local bfRng = Random.new(state.battleSeed + 70007)
		BattlefieldEventService.SelectEventsForBattle(state, activeQuest and activeQuest.biome or nil, bfRng)
	end

	-- Optional in-battle objectives (Phase 1): roll this battle's optional
	-- objectives from the encounter facts, so they can be counted as the fight
	-- happens and checked at battle end (ObjectiveService — fail-and-erase,
	-- victory-only reward). Deterministic: seeded from the map seed, like every
	-- other per-battle roll. Only objectives whose counters are fully wired are
	-- eligible to roll (ObjectiveService IMPLEMENTED allowlist).
	do
		local objCtx = ObjectiveService.BuildContext(allUnitsList, state.objects)
		local objRng = Random.new((state.battleSeed or os.time()) + 13337)
		ObjectiveService.BeginBattle(state, objCtx, objRng, 2)
		if state.activeObjectives and #state.activeObjectives > 0 then
			local names = {}
			for _, a in ipairs(state.activeObjectives) do
				names[#names + 1] = a.id .. "(" .. a.mode .. ")"
			end
			print("[ObjectiveService] Rolled optional objective(s): " .. table.concat(names, ", "))
		else
			print("[ObjectiveService] No optional objectives rolled this battle.")
		end
	end

	-- Seed permanent chasm-floor tile effects (Vines / Tar Pit) int
	-- slot (map_gen_rules rows 59/65/67). Source = GameConstants.FLOOR_EFFECTS, set by
	-- SetGeneratedMap() from the generated map (also covers the dev Regenerate tool).
	TileEffectService.SeedFloorEffects(GameConstants.FLOOR_EFFECTS)

	-- Spawn R15 race models for all units
	local raceModelsFolder = game:GetService("ServerStorage"):FindFirstChild("RaceModels")
	-- DIAGNOSTIC: enumerate what's actually in ServerStorage and RaceModels
	for _, child in ipairs(game:GetService("ServerStorage"):GetChildren()) do
	end
	if raceModelsFolder then
		for _, child in ipairs(raceModelsFolder:GetChildren()) do
		end
	end
	local TILE_SZ = 5
	local offsetX, offsetZ = -(MAP_WIDTH * TILE_SZ) / 2, -(MAP_HEIGHT * TILE_SZ) / 2
	local unitModelsFolder = workspace:FindFirstChild("UnitModels")
	if not unitModelsFolder then
		unitModelsFolder = Instance.new("Folder")
		unitModelsFolder.Name = "UnitModels"
		unitModelsFolder.Parent = workspace
	end

	for _, unit in ipairs(allUnitsList) do
		if not unit.isAlive then continue end
		local raceName = unit.raceId and RaceData.GetRace(unit.raceId)
			and RaceData.GetRace(unit.raceId).name or nil
		local template = raceName and raceModelsFolder and raceModelsFolder:FindFirstChild(raceName)
		if template and template:IsA("Model") then
			-- Skip if model already exists (spawned during deployment)
			if unitModelsFolder:FindFirstChild("Unit_" .. unit.id) then
				print(string.format("[Spawn] %s → model already exists (from deployment)", unit.name))
				continue
			end
			local clone = template:Clone()
			clone.Name = "Unit_" .. unit.id
			-- STREAMING FIX (2026-10-21): always-present battle unit (see enemy spawn note).
			clone.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			local _h3 = clone:FindFirstChildOfClass("Humanoid")
			if _h3 then _h3.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None; _h3.NameDisplayDistance = 0; _h3.HealthDisplayDistance = 0 end
			local hrp = clone.PrimaryPart or clone:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.Anchored = true
				-- Position at the unit's tile
				local elev = generatedMap.elevationGrid and generatedMap.elevationGrid[unit.tileY]
					and generatedMap.elevationGrid[unit.tileY][unit.tileX] or 1
				local tileTopY = GameConstants.TileSurfaceY(elev)  -- shared single-source tile height
				-- Stand TRUE FEET on the surface via the shared bbox-bottom helper.
				local _wx = offsetX + (unit.tileX - 0.5) * TILE_SZ
				local _wz = offsetZ + (unit.tileY - 0.5) * TILE_SZ
				local _face = centerFacingCFrame(_wx, tileTopY, _wz, unit.tileX, unit.tileY)
				clone:PivotTo(GameConstants.GroundModelPivotCFrame(clone, _wx, tileTopY, _wz, _face))
			end
			clone.Parent = unitModelsFolder
			attachWeaponToUnit(clone, unit)
			print(string.format("[Spawn] %s → R15 model '%s' at (%d,%d)", unit.name, raceName, unit.tileX, unit.tileY))
		else
			print(string.format("[Spawn] %s → no model for race '%s' (cylinder fallback)", unit.name, tostring(raceName)))
		end
	end

	task.wait(2)

	--------------------------------------------------
	-- INITIAL FACING
	-- Every unit (players and enemies) faces the geometric CENTER of the map, so
	-- both sides are oriented inward toward the battlefield at battle start
	-- (user decision 2026-10-17). Supersedes the old "face the opposing side's
	-- average position" behaviour.
	--------------------------------------------------
	do
		-- Single center tile stamped at map generation (walkable tile nearest the middle).
		-- Fall back to the raw midpoint only if a map somehow lacks it.
		local _ct = generatedMap and generatedMap.centerTile
		local centerX = (_ct and _ct.x) or (MAP_WIDTH / 2)
		local centerY = (_ct and _ct.y) or (MAP_HEIGHT / 2)
		local facingLog = {}
		for _, u in ipairs(allUnitsList) do
			local f = GameConstants.CalcFacingFrom(u.tileX, u.tileY, centerX, centerY)
			if f then u.facing = f end
			table.insert(facingLog, u.name .. "→" .. (u.facing or "?"))
		end
		print("[Main] Initial facing (toward map center): " .. table.concat(facingLog, ", "))
	end

	BattleVisualBroadcaster.BattleStarted(state.units)
	-- Re-announce battlefield events selected BEFORE BattleStarted: the client resets
	-- its Event panel on BattleStarted, so start-of-battle events (e.g. Fog Spirit) showed "None".
	for _, rec in ipairs(state.battlefieldEvents or {}) do
		if rec.name then BattleVisualBroadcaster.BattlefieldEventAnnounced(rec.name, true) end
	end
	-- Resync tile effects seeded BEFORE BattleStarted (chasm-floor Vines/Tar Pit): the
	-- client clears tile VFX on BattleStarted, so re-announce every live effect now.
	for _, eff in pairs(TileEffectService.GetAllEffects()) do
		if eff.tileX and eff.tileY and eff.id then
			BattleVisualBroadcaster.TileEffectApplied(eff.tileX, eff.tileY, eff.id, eff.remainingCt)
		end
	end

	--------------------------------------------------
	-- CHANNEL INTERRUPT HOOK
	--------------------------------------------------

	--------------------------------------------------
	-- TURN ENGINE  (extracted to Game/BattleTurnController.lua 2026-10-12)
	--------------------------------------------------
	BattleTurnController = require(Game:WaitForChild("BattleTurnController"))
	BattleTurnController.Init({ setTileOccupant = setTileOccupant, clearTileOccupant = clearTileOccupant })
	BattleTurnController.SetPlayer(player)
	BattleTurnController.SetMapDimensions(MAP_WIDTH, MAP_HEIGHT)
	BattleTurnController.SetState(state)  -- re-call each battle once the loop exists

	--------------------------------------------------
	-- BROADCAST ACTIONS HELPER
	--------------------------------------------------


	--------------------------------------------------
	-- UNIT INSPECT REQUEST (3-tab panel data)
	--------------------------------------------------


	--------------------------------------------------
	-- BATTLE LOOP
	--------------------------------------------------

	local turnCount = 0

	-- Initialize armor passives for all units at battle start (Slice 4G.9)
	for _, unit in ipairs(state.units) do
		ArmorPassiveService.OnBattleStart(unit)
	end

	while BattleCoordinator.GetPhase(state) ~= "BattleOver" do
		local activeUnit = BattleCoordinator.AdvanceClock(state)
		if not activeUnit then break end
		-- TAUNT (user ruling 2026-10-27): drop / apply aura taunts before the turn plays.
		for _, _tu in ipairs(StatusService.ReconcileTaunts(state.units)) do
			BattleVisualBroadcaster.UnitStateChanged(_tu)
		end

		-- Time-phase change: BattleCoordinator stashes it on state (it has no
		-- broadcaster handle); broadcast it here, before any early continue below.
		if state.pendingTimePhase then
			BattleVisualBroadcaster.TimePhaseChanged(state.pendingTimePhase)
			state.pendingTimePhase = nil
		end

		-- Slice 5 map objects: at each turn boundary, (1) sweep for deaths so a
		-- Necro Tome Stand fires on units killed during the prior turn, and (2) clear
		-- the active unit's per-turn object-usage ledger (Ballista/Catapult/Eye are
		-- "Once per turn"). activeUnit may be a channel-resolve signal table without
		-- an .id — guard before using it as a unit.
		ObjectEffectService.ProcessDeaths(state.units, state)
		if activeUnit.id then
			ObjectEffectService.ClearTurnUsage(activeUnit.id)
		end

		-- TWO-TIMER MODEL: channel-deadline resolution. AdvanceClock returns a signal
		-- table { channelResolve = caster } when the clock reached a fixed channel
		-- deadline. Fire the skill now (independent of whose RT is up), broadcast it,
		-- then let ResolveChannelDeadline apply the resolve-timing rule: the caster
		-- takes an immediate turn ONLY if its own RT already hit 0 (frozen); otherwise
		-- it keeps its remaining RT. If immediate, fall through as that unit's turn.
		if type(activeUnit) == "table" and activeUnit.channelResolve then
			local caster = activeUnit.channelResolve
			-- ACTIVATION TIME (2026-10-07): if the channel just completed but the skill
			-- still owes Activation Time, schedule it (uninterruptible) instead of firing.
			-- BeginActivationPhase returns the clock to Waiting; refresh the timeline.
			if BattleCoordinator.BeginActivationPhase(state, caster) then
				BattleTurnController.broadcastActions({}, caster)
				continue
			end
			BattleVisualBroadcaster.TurnStarted(caster, state.ct, state.units)
			local chActions = BattleTurnController.handleChannelingActivation(caster)
			BattleTurnController.broadcastActions(chActions, caster)
			local immediate = BattleCoordinator.ResolveChannelDeadline(state)
			if not immediate then
				-- No immediate turn — caster keeps its RT; continue the main loop.
				continue
			end
			-- Immediate turn: process 'caster' as the active unit for this iteration.
			activeUnit = immediate
		end

		turnCount = turnCount + 1

		-- Regeneration/Recharge CT-tick effects: BattleCoordinator applied the HP/MP
		-- (mutating the units) and stashed the affected units here. Refresh their bars.
		local ctStatusUnits = state.ctStatusUnits or {}
		state.ctStatusUnits = nil
		for _, u in ipairs(ctStatusUnits) do
			BattleVisualBroadcaster.UnitStateChanged(u)
			-- Shield visual (2026-10-23): keep the client shield indicator in sync as the
			-- pool decays/expires on CT ticks (absolute shield_total, read by the broadcaster).
			-- Harmless no-op for units with no shield (shieldTotal = 0 just hides the pill).
			BattleVisualBroadcaster.ShieldChanged(u, 0, "decay")
			-- Sinking (and any CT-tick effect) can KO a unit mid-tick: ProcessCtTick set
			-- isAlive=false and HP=0. Broadcast the defeat the same way every other death
			-- does (clear the tile, remove the token) so the unit doesn't linger on the board.
			if u.isAlive == false then
				clearTileOccupant(u.tileX, u.tileY)
				BattleEvents.UnitDefeated:FireAllClients({ unitId = u.id, removeUnit = true })
				print(string.format("[Main] %s removed (KO via CT-tick status)", u.name))
			end
		end

		-- Deployable / delayed PULSE effects (2026-10-26): PulseScheduler.ProcessCtTick
		-- (run inside AdvanceClock) applied heal/damage/status to units on the clock and
		-- stashed one event per affected unit here. Drain the list (so it never grows across
		-- the battle) and refresh each unit: bar + heal/damage floater, and a death broadcast
		-- if a damage pulse KO'd it — same handling as the CT-status block above.
		local pulseEvents = state.pulseEvents or {}
		state.pulseEvents = nil
		local _pulseSeen = {}
		local _pulseKoSeen = {}
		for _, ev in ipairs(pulseEvents) do
			local u = ev.unit
			if u then
				if ev.kind == "damage" and (ev.amount or 0) > 0 then
					if ev.sourceUnit then
						-- Device hit (Sentry Turret, ...): shown exactly like a normal attack -- damage
						-- number, hit flinch, shot effect, "X attacks Y" log (user ruling 2026-10-27).
						-- UnitActed also announces the KO, so the removal broadcast below is skipped.
						BattleVisualBroadcaster.UnitActed(ev.sourceUnit, u, { finalDamage = ev.amount }, nil, nil)
						if u.isAlive == false and not _pulseKoSeen[u] then
							_pulseKoSeen[u] = true
							clearTileOccupant(u.tileX, u.tileY)
						end
					else
						BattleVisualBroadcaster.DotDamage(u, ev.element or "Pulse", ev.amount, ev.source)
					end
				elseif ev.kind == "heal" and ev.sourceUnit and (ev.amount or 0) > 0 then
					-- Device heal (Mender Drone, Healing Beacon): green number like a normal heal.
					BattleVisualBroadcaster.HealingApplied(ev.sourceUnit, u, ev.amount)
				end
				-- Drone reveal: the unit's Hide status ended (client drops the pill).
				if ev.kind == "reveal" then
					BattleVisualBroadcaster.StatusExpired(u, "Hide")
				end
				-- Extraction Beacon relocation: move the token + tile-occupancy labels.
				if ev.kind == "relocate" then
					clearTileOccupant(ev.oldX, ev.oldY)
					setTileOccupant(u.tileX, u.tileY, u.name, "Unit (" .. u.side .. ")", "Blocking")
					BattleVisualBroadcaster.UnitMoved(u)
				end
				-- Refresh each affected unit's bars once (a unit may appear in several events
				-- across a multi-pulse tick; collapse to one state refresh).
				if not _pulseSeen[u] then
					_pulseSeen[u] = true
					BattleVisualBroadcaster.UnitStateChanged(u)
				end
				-- W-1 fix: a unit can appear in several pulse events in one pass; broadcast its
				-- defeat only ONCE (a second UnitDefeated for the same unit is a client-side
				-- double-removal). Keyed separately from the bar-refresh dedup above.
				if u.isAlive == false and not _pulseKoSeen[u] then
					_pulseKoSeen[u] = true
					clearTileOccupant(u.tileX, u.tileY)
					BattleEvents.UnitDefeated:FireAllClients({ unitId = u.id, removeUnit = true })
					print(string.format("[Main] %s removed (KO via pulse)", u.name))
				end
			end
		end

		-- A side wiped by clock effects (statuses, tile effects, pulses) ends the battle now. They tick
		-- after AdvanceClock's own battle-end check, so without this the next unit would still get a turn
		-- on an empty field (UAT 2026-10-28 W-1). The kills above have already been shown.
		if BattleCoordinator.CheckBattleEnd(state) then
			break
		end

		-- Process DoT
		local dotEvents = state.dotEvents or {}
		state.dotEvents = nil

		for _, dot in ipairs(dotEvents) do
			if activeUnit.isAlive then
				local actual = UnitSchema.ApplyDamage(activeUnit, dot.damage)
				print(string.format(
					"[DoT] %s takes %d %s damage | HP: %d/%d%s",
					activeUnit.name, actual, dot.statusId,
					activeUnit.currentHp, activeUnit.maxHp,
					activeUnit.isAlive and "" or " | DEFEATED"
				))
				BattleVisualBroadcaster.DotDamage(activeUnit, dot.statusId, actual)
			end
		end

		-- Venom end-of-turn damage (user ruling 2026-10-26): BattleCoordinator.EndTurn applies
		-- it (so a KO still ends the battle); here it is shown on screen and a KO'd unit's tile
		-- is freed. Called right before TurnEnded on both the normal and skipped-turn paths.
		local function broadcastEndTurnDots()
			local evs = state.endTurnDotEvents
			state.endTurnDotEvents = nil
			if not evs then return end
			for _, ev in ipairs(evs) do
				local u = ev.unit
				if u then
					BattleVisualBroadcaster.DotDamage(u, ev.statusId, ev.actual)
					if not u.isAlive then
						clearTileOccupant(u.tileX, u.tileY)
						if u.isChanneling then
							BattleCoordinator.InterruptChanneling(u, "death")
							BattleVisualBroadcaster.ChannelEnded(u)
						end
					end
				end
			end
		end

		-- If unit died to DoT
		if not activeUnit.isAlive then
			clearTileOccupant(activeUnit.tileX, activeUnit.tileY)
			if activeUnit.isChanneling then
				BattleCoordinator.InterruptChanneling(activeUnit, "death")
				BattleVisualBroadcaster.ChannelEnded(activeUnit)
			end
			BattleCoordinator.EndTurn(state)
			BattleVisualBroadcaster.TurnEnded(activeUnit, 0)
		elseif StatusService.ShouldSkipTurn(activeUnit) then
			-- Turn skip: Sleep / Petrify / Stun / Knock-out
			local _, skipReason = StatusService.ShouldSkipTurn(activeUnit)
			print(string.format(
				"[TurnSkip] %s skipped (%s) | HP: %d/%d",
				activeUnit.name, skipReason,
				activeUnit.currentHp, activeUnit.maxHp
			))
			BattleVisualBroadcaster.TurnStarted(activeUnit, state.ct, state.units)
			-- Statuses count down ONCE, inside BattleCoordinator.EndTurn (2026-10-26). The extra
			-- TickStatuses call that used to sit here made skipped-turn statuses wear off twice as fast.
			BattleCoordinator.EndTurn(state)
			broadcastEndTurnDots()
			BattleVisualBroadcaster.TurnSkipped(activeUnit, skipReason)
			BattleVisualBroadcaster.TurnEnded(activeUnit, activeUnit.remainingRt)
		else
			-- Normal turn
			BattleVisualBroadcaster.TurnStarted(activeUnit, state.ct, state.units)

			-- Tile occupy effect: a unit that BEGINS its turn standing on a hazard tile
			-- receives that tile's occupy status (DB: Burning/Poison Cloud/Vines "Inflict X").
			-- Cross effects are handled separately on move (OnUnitEntersTile); this is the
			-- start-of-turn occupy path. Only fires on a normal turn (not skip/death).
			TileEffectService.OnUnitStartTurn(activeUnit)

			-- Battlefield-event per-turn behaviour (Thief Hide, hazard trails, Monster
			-- Hunter trap, Lightning strike, Lich ripple, Water flood, Bard aura, Traitor
			-- flip). Fires for any unit carrying event flags; nil-safe/no-op otherwise.
			do
				local bfRng = Random.new((state.ct or 0) + (activeUnit.stableOrderKey or 0) + (state.battleSeed or 0) + 70007)
				local okB, errB = pcall(BattlefieldEventService.OnEventUnitTurn, activeUnit, state, bfRng)
				if not okB then
					warn("[Main] BattlefieldEventService.OnEventUnitTurn error: " .. tostring(errB))
				end
				-- Single-active-event slot: if the active event ended, fire the next one.
				local okT, errT = pcall(BattlefieldEventService.OnTurnTick, state, bfRng,
					math.floor((state.ct or 0) / 1000))
				if not okT then
					warn("[Main] BattlefieldEventService.OnTurnTick error: " .. tostring(errT))
				end
			end

			-- FEAR (CON-017, user ruling 2026-10-26): a Feared unit's FIRST AP is spent fleeing
			-- toward its own deployment area before the player / AI gets the rest of the turn.
			if StatusService.HasStatus(activeUnit, "Fear") and not BattleCoordinator.IsChanneling(activeUnit) then
				local fOldX, fOldY = activeUnit.tileX, activeUnit.tileY
				local okF, resF = pcall(CommandService.ApplyFearMove, state, activeUnit)
				if not okF then
					warn("[Main] Fear move error: " .. tostring(resF))
				elseif resF and resF.moved then
					clearTileOccupant(fOldX, fOldY)
					setTileOccupant(activeUnit.tileX, activeUnit.tileY, activeUnit.name, "Unit (" .. activeUnit.side .. ")", "Blocking")
					BattleVisualBroadcaster.UnitMoved(activeUnit)
				end
			end
			local fearEndedTurn = BattleCoordinator.GetPhase(state) ~= "TurnOpen"

			-- Determine turn handler
			local actions
			local wasChanneling = BattleCoordinator.IsChanneling(activeUnit)
			if fearEndedTurn then
				-- Fear spent the unit's only AP: nothing left to play this turn.
				actions = {}
			elseif BattleCoordinator.IsChanneling(activeUnit) then
				actions = BattleTurnController.handleChannelingActivation(activeUnit)
			elseif activeUnit.isSummon and activeUnit.summonType == "SoulEcho" then
				-- Soul Echo (AUG-SOUL-ECHO) detonates on its own turn: Dark AOE within 1 tile to the
				-- owner's enemies for the damage snapshotted at the kill (30% of the original kill
				-- damage), then the echo retires. Raw UnitSchema.ApplyDamage -> no augment/counter/
				-- death retrigger (authored recursion guard). FIDELITY NOTES (flagged for Designer):
				-- damage is FLAT ("Dark" is nominal — no Dark resist/weakness math, since we bypass
				-- CombatResolver by design); enemy shields absorb it normally; the blast lands on the
				-- echo's FIRST turn (~1 turn-length after the kill). An echo is created on EVERY kill
				-- (single-target AND each AOE loop) and multiple echoes coexist (no cap / add, user
				-- decision 2026-10-26); each detonates independently on its own turn (see CommandService
				-- trySpawnSoulEcho spawn site).
				if not activeUnit._soulEchoDetonated then
					activeUnit._soulEchoDetonated = true
					local dmg = activeUnit._soulEchoDamage or 0
					local ex, ey = activeUnit.tileX, activeUnit.tileY
					local hits, total = 0, 0
					if dmg > 0 and ex and ey then
						for _, u in ipairs(state.units) do
							if u.isAlive and u.side ~= activeUnit.side and not u.isGroundTarget and u.tileX
								and math.max(math.abs(u.tileX - ex), math.abs((u.tileY or 0) - ey)) <= 1 then
								local actual = UnitSchema.ApplyDamage(u, dmg)
								BattleVisualBroadcaster.DotDamage(u, "Dark", actual)
								hits += 1
								total += (actual or 0)
								if not u.isAlive then
									clearTileOccupant(u.tileX, u.tileY)
								end
							end
						end
					end
					print(string.format("[Main] Soul Echo detonates at (%s,%s): %d enemy(ies) for %d Dark",
						tostring(ex), tostring(ey), hits, total))
				end
				-- End the echo's turn cleanly (same as Decoy), then retire it so it never acts again.
				CommandService.ValidateAndCommit(state, activeUnit.id, "Wait", nil)
				activeUnit.isAlive = false
				activeUnit.currentHp = 0
				clearTileOccupant(activeUnit.tileX, activeUnit.tileY)
				BattleEvents.UnitDefeated:FireAllClients({ unitId = activeUnit.id, removeUnit = true })
				actions = {}
			elseif activeUnit.isItemDevice
				or (activeUnit.isSummon and (activeUnit.summonType == "Decoy" or activeUnit.summonType == "WardTotem")) then
				-- Decoy / Ward Totem never act (authored): skip their turn automatically.
				-- Item devices (2026-10-26) never act either: their pulses run on the CT clock.
				CommandService.ValidateAndCommit(state, activeUnit.id, "Wait", nil)
				actions = {}
			elseif activeUnit.controller == "Player" then
				actions = BattleTurnController.runPlayerTurn(activeUnit)
			else
				actions = BattleTurnController.runAiTurn(activeUnit)
			end

			-- Broadcast
			if activeUnit.controller ~= "Player" or wasChanneling then
				BattleTurnController.broadcastActions(actions, activeUnit)
			end

			-- Safety close
			if BattleCoordinator.GetPhase(state) == "TurnOpen" then
				CommandService.ValidateAndCommit(state, activeUnit.id, "Wait", nil)
			end

			-- Tile end-of-turn hook: Tar Pit consecutive-turn Petrify counter
			-- (increments if ending on Tar Pit, resets otherwise).
			TileEffectService.OnUnitEndTurn(activeUnit)

			-- Phase 3 Battle Focus / Mana-Starved (TRAIT-P/F-006/053): at end of turn, gain/
			-- lose MP = fraction of max MP per remaining AP. Uses the AP left unspent this turn.
			do
				local mpPerApFrac = TraitEffectService.GetEndTurnMpPerApFraction(activeUnit)
				local remainingAp = activeUnit.currentAp or 0
				if mpPerApFrac ~= 0 and remainingAp > 0 and activeUnit.maxMp and activeUnit.maxMp > 0 then
					local delta = math.round(activeUnit.maxMp * mpPerApFrac * remainingAp)
					activeUnit.currentMp = math.clamp((activeUnit.currentMp or 0) + delta, 0, activeUnit.maxMp)
					print(string.format("[Main] End-turn MP trait: %s %+d MP (%d AP left) -> %d", activeUnit.name, delta, remainingAp, activeUnit.currentMp))
				end
			end

			-- Phase 3 Wrathful / Meek stack decay (TRAIT-P/F-152/167): DB rule "remove at end
			-- of next turn" = 1-turn window (user ruling 2026-10-04, Option A). Hits land during
			-- an ENEMY turn, so the stack is gained before this unit's turn, boosts THIS turn's
			-- damage, and clears at the end of THIS turn. So: clear any stack at the unit's own
			-- turn end. (No multi-turn age-tracking — that produced the 2-turn window.)
			if activeUnit.combatStackPct and activeUnit.combatStackPct ~= 0 then
				activeUnit.combatStackPct = 0
				activeUnit.combatStackAge = 0
				print(string.format("[Main] Wrathful/Meek stack expired (end of turn): %s", activeUnit.name))
			end

			broadcastEndTurnDots()
			BattleVisualBroadcaster.TurnEnded(activeUnit, activeUnit.remainingRt)
		end
	end

	--------------------------------------------------
	-- RESULT
	--------------------------------------------------

	print("====================================")
	local phase  = BattleCoordinator.GetPhase(state)
	local winner = BattleCoordinator.GetWinner(state)

	if phase == "BattleOver" then
		print(string.format("BATTLE OVER — %s wins! (%d turns)", winner, turnCount))
	else
		warn(string.format("[Main] Battle loop exited without a resolution after %d turns (engine stall — no side eliminated and the clock produced no next event). This should not happen.", turnCount))
	end
	print("====================================")
	for _, u in ipairs(allUnitsList) do
		print(string.format("  %s", UnitSchema.Describe(u)))
	end
	print("====================================")

	--------------------------------------------------
	-- POST-BATTLE: PERSIST STATE + RECOVERY (Slice 4B)
	--------------------------------------------------

	local isQualifyingVictory = (winner == "Player")
	local battleGoldEarned = 0 -- set by the BATTLE GOLD block below; shown on the reward screen
	-- Expedition Fortune (loot_progression, 2026-10-23): the deployed team's post-gear
	-- Fortune drives loot rarity quality AND the Fortune gold multiplier for THIS battle's
	-- rewards. Computed from who actually fought (allUnitsList); neutral when LUK+gear low.
	RewardService.SetExpeditionFortune(RewardService.ComputeExpeditionFortune(allUnitsList))

	--------------------------------------------------
	-- POST-BATTLE: UPDATE UNIT RECORDS (Slice 4K)
	--------------------------------------------------
	for _, u in ipairs(allUnitsList) do
		if u.side == "Player" and u.records then
			u.records.battlesParticipated = (u.records.battlesParticipated or 0) + 1
			if isQualifyingVictory then
				u.records.victoriesParticipated = (u.records.victoriesParticipated or 0) + 1
			end
			if not u.isAlive then
				u.records.timesKO = (u.records.timesKO or 0) + 1
			end
		end
	end
	-- Enemy defeat tracking: count how many enemies each player unit killed
	for _, u in ipairs(allUnitsList) do
		if u.side == "Enemy" and not u.isAlive and u._killedBy then
			local killer = playerUnits[u._killedBy]
			if killer and killer.records then
				killer.records.enemiesDefeated = (killer.records.enemiesDefeated or 0) + 1
			end
		end
	end

	--------------------------------------------------
	-- POST-BATTLE: AWARD UNIT XP (Slice 6 ProgressionService)
	-- Build the battle result from live state and hand it to AwardBattleXp, which
	-- applies the LOCKED deployed/benched/KO distribution, the overleveled penalty,
	-- the Human bonus, levels up and clamps at 99. Done BEFORE HP/MP persist + save
	-- so the new levels ride the EXISTING save payload (unit records -> Key 1/3).
	--------------------------------------------------
	-- Declared at loop-body scope so BOTH the battle-end evaluation (inside the XP
	-- do-block below) and the objective-reward grant (inside the victory reward
	-- block further down) can see the same result. (Scope fix 2026-10-24.)
	local objResult = nil
	do
		-- kills[]: one entry per defeated ENEMY. enemyType is stamped by EnemyGenerator
		-- (unit.enemyType = spec.type, EnemyGenerator L453) so Grunt/Veteran/Elite is
		-- preserved (FLAG-P3 input present; no duplicate stamp added). level is the
		-- enemy's own level. aiRole kept as a safe fallback only (retired field).
		local kills = {}
		local deployed = {}
		local koList = {}
		-- Slice 6 item 2: objective checks the battle loop can evaluate today.
		local anyPlayerKO = false
		local anyEnemyStanding = false
		for _, u in ipairs(allUnitsList) do
			if u.side == "Enemy" and not u.isSummon then
				-- Summons are not Grunt/Veteran/Elite/Boss and are rewardEligible=false
				-- (EnemyGenerator SpawnSummon): no kill XP (FLAG-P3 — they used to fall
				-- back to Grunt XP).
				if not u.isAlive then
					table.insert(kills, {
						enemyType = u.enemyType,          -- Grunt/Veteran/Elite/Boss (BUG-009 field)
						aiRole    = u.aiRole,             -- fallback only
						level     = u.level or 0,
						goldMult  = (type(u.rewardOnDeath) == "table" and tonumber(u.rewardOnDeath.goldMult)) or nil,
					})
				else
					anyEnemyStanding = true
				end
			elseif u.side == "Player" and not u.isSummon and playerUnits[u.id] then
				-- Summons are temporary battle entities: no unit XP (not roster units).
				-- Dev-spawned Player units are not roster units (no record) — skipped.
				table.insert(deployed, u.id)
				if not u.isAlive then
					table.insert(koList, u.id)
					anyPlayerKO = true
				end
			end
		end

		-- UGC usage (ugc_rules usage_decrement_rule): -1 per item worn by ANY deployed
		-- roster unit, at battle END (any outcome), before the save below (BUG-013
		-- commit -> save -> BattleEnded order unchanged). Expired items unequip everywhere.
		-- Loadout Replicator (UTI-020): copied items turn back into the Replicator at battle end.
		CommandService.RevertReplicatedItems(state.units)
		CommandService.RevertReplicatedItems(playerUnits)
		UGCService.OnBattleCompleted(PLAYER_ID, deployed)

		-- benched[] = owned roster MINUS deployed MINUS away on dispatch (FLAG-P2,
		-- resolved 2026-10-07). Owned units the Guild menu benched above the
		-- deployment cap (GuildMenuService.SyncBattleRoster removes them from
		-- allUnitsList but they stay in playerUnits) land here and get the locked 65%.
		local deployedSet = {}
		for _, id in ipairs(deployed) do deployedSet[id] = true end
		local benched = {}
		for unitId in pairs(playerUnits) do
			-- UAT D2 fix 2026-10-07: units away on dispatch are unavailable and earn
			-- dispatch XP only (unit_progression 52/77/78) — never benched XP.
			local isAway = DispatchService.IsUnitDispatched(PLAYER_ID, unitId)
			if not deployedSet[unitId] and not isAway then
				table.insert(benched, unitId)
			end
		end

		-- Procedural objectives met (unit_progression 68/69; victory only — the
		-- percentages live in ProgressionService). Known gap: a unit KO'd and then
		-- revived mid-battle is alive at the end, so it does not break Flawless.
		local objectivesMet = {}
		if isQualifyingVictory then
			if not anyPlayerKO then table.insert(objectivesMet, "Flawless") end
			-- 'All defeated' removed (user ruling 2026-10-07). More optional objectives
			-- need to be authored later.
		end

		-- Optional in-battle objectives (Phase 1): feed the end-state counter the
		-- loop already computed (player KOs = #koList), then evaluate. Victory-only
		-- grant; fail-and-erase happens inside Evaluate. This runs INSIDE the
		-- protected battle-end order (before BattleEnded — BUG-013). Reward
		-- granting (gear/skill/augment now; gold/materials Phase 3) is wired next;
		-- this increment surfaces the result to the Output log so the roll ->
		-- count -> check -> erase pipe can be verified in Studio.
		if state and state.objectiveCounters then
			state.objectiveCounters.playerKOs = #koList
		end
		objResult = ObjectiveService.Evaluate(state, isQualifyingVictory)
		if objResult and #objResult.completed > 0 then
			local onames = {}
			for _, c in ipairs(objResult.completed) do
				onames[#onames + 1] = c.name .. " (" .. c.mode .. ")"
			end
			print(string.format("[ObjectiveService] Completed %d optional objective(s): %s  -> %d reward roll(s) pending",
				#objResult.completed, table.concat(onames, ", "), objResult.rewardCount))
		else
			print("[ObjectiveService] No optional objectives completed this battle.")
		end

		local battleResult = {
			battleId         = string.format("battle_%s_%d", PLAYER_ID, turnCount),
			won              = isQualifyingVictory,
			recommendedLevel = activeQuest and activeQuest.recommendedLvl or nil,  -- FLAG-P1 (QuestGenerator L300)
			kills            = kills,
			deployed         = deployed,
			benched          = benched,
			ko               = koList,
			objectivesMet    = objectivesMet,  -- FLAG-P4 (Flawless only; AllDefeated removed 2026-10-07)
			-- Glow Crystal (Slice 6 item 3): set by ObjectEffectService on a player activation.
			glowCrystal      = (state ~= nil and state.glowCrystalActive == true),
		}
		local xpSummary = ProgressionService.AwardBattleXp(PLAYER_ID, battleResult)

		-- BATTLE GOLD (economy_framework ids 2-9, LOCKED; defeat rule 2026-09-14).
		--   Kill Gold = Base × (1 + Enemy Level / 100) × overleveled band
		--     Base: Grunt 8 / Veteran 14 / Elite 25 / Boss 50. Band uses the gap between
		--     the party's highest level and the quest's recommended level (same bands as
		--     XP, no underleveled bonus — id 7).
		--   Victory: 100% kill gold + Battle Completion Gold + Quest Reward Gold.
		--   Defeat / wipeout: 50% of kill gold only.
		-- RewardService.ApplyGold applies battlefield-event gold multipliers (Leprechaun etc.).
		do
			-- Gold now computed via the shared computeBattleGold helper so the live
			-- Map Details projection and this real payout use ONE formula. Behavior
			-- is identical to the former inline block (same band, per-kill base, 50%
			-- defeat rule, largest event mult); RewardService.ApplyGold still layers
			-- battlefield-event gold multipliers on the final total. (2026-10-17)
			local gb = computeBattleGold(allUnitsList, playerUnits, activeQuest, isQualifyingVictory)
			local killGold, completionGold, questGold = gb.killGold, gb.completionGold, gb.questGold
			local band, eventGoldMult = gb.band, gb.eventGoldMult
			local total = RewardService.ApplyGold(gb.total)
			if total > 0 then CurrencyService.Credit(PLAYER_ID, { gold = total }) end
			battleGoldEarned = total
			print(string.format("[PostBattle] Gold +%d (kills %d, completion %d, quest %d, band x%.2f, event x%.1f, %s)",
				total, killGold, completionGold, questGold, band, eventGoldMult, if isQualifyingVictory then "victory" else "defeat"))
		end
		if xpSummary and xpSummary.flags and #xpSummary.flags > 0 then
			for _, f in ipairs(xpSummary.flags) do
				print("[PostBattle][XP-FLAG] " .. tostring(f))
			end
		end
	end

	-- Step 1: Persist final HP/MP for all player units
	for _, u in ipairs(allUnitsList) do
		if u.side == "Player" then
			PersistentStateService.PersistBattleEnd(
				PLAYER_ID, u.id,
				u.currentHp, u.currentMp,
				u.maxHp, u.maxMp,
				not u.isAlive -- isKO
			)
		end
	end

	-- Step 2a: Clear KO on all player units (session rule — base not implemented)
	PersistentStateService.ClearAllKO(PLAYER_ID)

	-- Step 2b: Apply 35% recovery to all survivors (regardless of outcome)
	print("[PostBattle] Applying 35% recovery to survivors")
	-- Perks & Flaws (2026-10-23): build per-unit recovery-fraction overrides from the LIVE
	-- units (which carry trait ids; the persistent-state layer does not). Resilient adds to
	-- the 0.35 baseline, Slow to Recover replaces it. Units with neither are left out (default).
	local recoveryOverrides = {}
	for _, u in ipairs(allUnitsList) do
		if u.side == "Player" then
			local frac = TraitEffectService.GetPostBattleRecoveryFraction(u, 0.35)
			if frac ~= 0.35 then recoveryOverrides[u.id] = frac end
		end
	end
	local recovery = PersistentStateService.ApplyPostBattleRecovery(PLAYER_ID, recoveryOverrides)
	for unitId, result in pairs(recovery) do
		print(string.format("  %s: HP+%d MP+%d", unitId, result.hpRecovered, result.mpRecovered))
	end

	--------------------------------------------------
	-- POST-BATTLE: GENERATE REWARDS (Slice 4D)
	--------------------------------------------------

	local rewardSummaries = {}

	if isQualifyingVictory then
		-- Reward Item Level source (DB loot_progression, LOCKED): "Quest rewards:
		-- Item Level = Quest Level." Quest Level = activeQuest.recommendedLvl (set at
		-- quest selection). Fallback to 1 only if no quest is active (defensive).
		local MAP_LEVEL = (activeQuest and activeQuest.recommendedLvl) or 1
		local opportunityId = string.format("battle_%s_%d", PLAYER_ID, os.clock())

		-- Treasure Hunter augment (2026-10-25): if any enemy was killed with a Treasure-Hunter
		-- skill this battle (stamped _treasureHunted on the slain unit by AugmentEffectService),
		-- bump the victory loot's rarity by 1 tier. Battle loot is a single pool (not per-kill),
		-- so this applies the bonus once to the whole drop — the faithful mapping of "better loot
		-- from enemies killed with this skill" onto a pooled-loot system (flagged to the user).
		local _thBonus = 0
		if state and state.units then
			for _, u in ipairs(state.units) do
				if u._treasureHunted and not u.isAlive then _thBonus = 1 break end
			end
		end
		local results, equipCommitted = RewardService.GenerateRewards(PLAYER_ID, MAP_LEVEL, opportunityId,
			_thBonus > 0 and { bonusRarityTiers = _thBonus } or nil)

		-- Stolen gear (Steal / Mug, 2026-10-24): items taken in-battle are kept ONLY on a
		-- qualifying victory. Commit each to the player's inventory and append it to the loot
		-- results flagged stolen=true so the victory screen badges it. state.stolenItems was
		-- filled by CommandService during the fight (nil/empty when nothing was stolen).
		if state.stolenItems and #state.stolenItems > 0 then
			for _, it in ipairs(state.stolenItems) do
				local okAdd = InventoryService.AddItem(PLAYER_ID, it)
				table.insert(results, {
					category = "Equipment", item = it, committed = okAdd ~= false, stolen = true,
				})
				if okAdd ~= false then equipCommitted = equipCommitted + 1 end
			end
			print(string.format("[PostBattle] %d stolen item(s) added to victory loot", #state.stolenItems))
		end

		-- Commit non-equipment rewards to card inventories
		local cardCommitted = 0
		for _, result in ipairs(results) do
			if not result.committed and result.cardData then
				local cat = result.category
				local id = result.cardData.id
				if cat == "SkillCard" then
					cardInventory.skillCards[id] = (cardInventory.skillCards[id] or 0) + 1
					result.committed = true
					cardCommitted = cardCommitted + 1
				elseif cat == "AugmentCard" then
					cardInventory.augmentCards[id] = (cardInventory.augmentCards[id] or 0) + 1
					result.committed = true
					cardCommitted = cardCommitted + 1
				elseif cat == "Doctrine" or cat == "Consumable" then
					-- Tracked for display; ownership gating deferred
					result.committed = true
					cardCommitted = cardCommitted + 1
				end
			end
		end

		local totalCommitted = equipCommitted + cardCommitted
		if totalCommitted > 0 then
			rewardSummaries = RewardService.BuildRewardSummaries(results)
			print(string.format("[PostBattle] %d reward(s) committed (%d equip, %d cards)", totalCommitted, equipCommitted, cardCommitted))
		end

		-- Log any failures explicitly
		for i, result in ipairs(results) do
			if not result.committed then
				warn(string.format("[PostBattle] Reward %d failed: %s", i, result.error or "unknown"))
			end
		end

		-- OPTIONAL OBJECTIVE REWARDS (Phase 1): one reward roll per completed
		-- optional objective (Hard counts double, via objResult.rewardCount),
		-- restricted to gear/skill/augment — consumables + doctrines are excluded
		-- (user-locked 2026-10-24). Gold + materials are Phase 3 (grant paths not
		-- built yet). Committed the SAME way as battle loot and appended to the
		-- reward screen. objResult was computed above, inside the protected
		-- battle-end order (before BattleEnded — BUG-013).
		if objResult and objResult.rewardCount and objResult.rewardCount > 0 then
			local objOppId = string.format("objrw_%s_%d", PLAYER_ID, os.clock())
			local objResults = RewardService.GenerateRewards(PLAYER_ID, MAP_LEVEL, objOppId, {
				count = objResult.rewardCount,
				allowedCategories = ObjectiveService.REWARD_CATEGORIES,
			})
			local objCommitted = 0
			for _, result in ipairs(objResults) do
				if result.committed then
					objCommitted = objCommitted + 1  -- equipment auto-commits in GenerateRewards
				elseif result.cardData then
					local cat, id = result.category, result.cardData.id
					if cat == "SkillCard" then
						cardInventory.skillCards[id] = (cardInventory.skillCards[id] or 0) + 1
						result.committed = true
						objCommitted = objCommitted + 1
					elseif cat == "AugmentCard" then
						cardInventory.augmentCards[id] = (cardInventory.augmentCards[id] or 0) + 1
						result.committed = true
						objCommitted = objCommitted + 1
					end
				end
			end
			if objCommitted > 0 then
				local objSummaries = RewardService.BuildRewardSummaries(objResults)
				for _, s in ipairs(objSummaries) do
					rewardSummaries[#rewardSummaries + 1] = s
				end
				print(string.format("[ObjectiveService] Granted %d objective reward(s) from %d completed objective(s).",
					objCommitted, #objResult.completed))
			end
		end
	end

	-- Step 3: Save to DataStore (now includes committed rewards)
	doSave()

	-- END BATTLE LAST (persistent_hp_mp_rules authored order: victory -> finish action +
	-- triggered resolutions -> commit rewards -> persist/recovery -> save -> END). The
	-- BattleEnded end-signal must fire only AFTER rewards are committed and state is saved.
	BattleVisualBroadcaster.BattleEnded(winner or "None", state.units)

	-- Slice 6 Guild menu "return to base" bookkeeping (game_flow id 20), AFTER the
	-- protected commit -> save -> BattleEnded order above (BUG-013 order unchanged):
	-- count this battle (win or loss) and bring home dispatches that are due (their
	-- XP goes through the wired Dispatch sink, materials through CurrencyService).
	-- Dispatch now counts down in DAYS, where 1 day = 4000 CT (unit_progression 77/78/99,
	-- DB 2026-10-16). This battle was worth ceil(elapsed CT / 4000) days, minimum 1.
	local daysElapsed = math.max(1, math.ceil((state.ct or 0) / 4000))
	local dispatchReturns = GuildMenuService.OnBattleCompleted(daysElapsed)
	-- Battle recruits (project_rules id 133): alive recruited Neutrals are purified and
	-- join the roster on ANY battle end. Runs after the protected BUG-013 order above.
	GuildMenuService.AdoptBattleRecruits(state.units)
	doSave()

	-- Step 4: Reward screen (if rewards earned)
	-- Build recovery summary for client display
	local recoverySummary = {}
	for unitId, result in pairs(recovery) do
		local unitName = unitId
		for _, u in ipairs(state.units) do
			if u.id == unitId then unitName = u.name; break end
		end
		if result.hpRecovered > 0 or result.mpRecovered > 0 then
			table.insert(recoverySummary, {
				name = unitName, hpGain = result.hpRecovered, mpGain = result.mpRecovered,
			})
		end
	end

	-- Returned-dispatch summary (2026-10-14): dispatch resolves just above in
	-- OnBattleCompleted; surface each returned unit's XP + reward materials on the
	-- reward screen (the data was computed server-side then discarded). The unit was
	-- away (not in state.units), so resolve its name via the roster table playerUnits.
	local dispatchSummary = {}
	if dispatchReturns and type(dispatchReturns.returned) == "table" then
		for _, r in ipairs(dispatchReturns.returned) do
			local nm = r.unitId
			local pu = playerUnits[r.unitId]
			if pu and pu.name then nm = pu.name end
			table.insert(dispatchSummary, {
				name = nm, xp = r.xp, matTier = r.matTier, matCount = r.matCount,
			})
		end
	end

	-- Active (still-away) dispatches with their day countdown, grouped by mission, so the
	-- victory/defeat screen shows WHEN each order ends and WHO is on it. Read AFTER
	-- OnBattleCompleted above, so remainingDays already reflects this battle's day burn and
	-- any returned units are gone. Away units aren't in state.units -> names via playerUnits. (2026-10-23)
	local activeDispatch = {}
	do
		local byMission = {}
		for _, rec in ipairs(DispatchService.GetActiveDispatches(PLAYER_ID)) do
			local g = byMission[rec.missionId]
			if not g then
				g = { missionId = rec.missionId, tier = rec.tier, remainingDays = rec.remainingDays, units = {} }
				byMission[rec.missionId] = g
				table.insert(activeDispatch, g)
			end
			local nm = rec.unitId
			local pu = playerUnits[rec.unitId]
			if pu and pu.name then nm = pu.name end
			table.insert(g.units, nm)
		end
	end

	-- Always show the result screen on a DEFEAT too (2026-10-16): previously a defeat with no
	-- rewards/gold/dispatch skipped this entirely, leaving only the bare 5s "DEFEAT" banner.
	-- Firing it on defeat gives the same framed screen (DEFEAT title + a no-spoils line) with a
	-- Continue button, and the rewardContinueSignal wait keeps the loop paced like a victory.
	if #rewardSummaries > 0 or battleGoldEarned > 0 or #dispatchSummary > 0 or #activeDispatch > 0 or not isQualifyingVictory then
		print(string.format("[PostBattle] Sending %d reward(s) + %d gold + %d dispatch + %d active-dispatch to client", #rewardSummaries, battleGoldEarned, #dispatchSummary, #activeDispatch))
		BattleEvents.RewardScreen:FireAllClients({ rewards = rewardSummaries, recovery = recoverySummary, gold = battleGoldEarned,
			dispatch = dispatchSummary, activeDispatch = activeDispatch, daysElapsed = daysElapsed, defeat = not isQualifyingVictory })
		rewardContinueSignal.Event:Wait()
		print("[PostBattle] Player acknowledged rewards")
	end

	-- Step 5: Auto-save and return straight to the base (2026-10-13 user decision).
	-- No separate post-battle "Save & Finish" menu: in the real flow the player is
	-- teleported battle -> hub, so results are already persisted (the battle-end save
	-- above wrote rewards/XP/recovery/roster). This extra save is a safety net; then the
	-- loop returns to the top, which opens the base ("Base" phase). Post-battle loadout
	-- changes now happen at the base, which is fully interactive.
	doSave()
	print(`[Hub] Battle complete (mode: {betweenBattleMode}) — auto-saved; returning to base.`)

	print("[Loop] Round complete — returning to quest board for next quest.")
end
