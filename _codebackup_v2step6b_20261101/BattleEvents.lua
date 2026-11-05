-- BattleEvents.lua
-- CTRBLXAI | Slice 3
--
-- Creates and exposes RemoteEvents for battle communication.
--
-- Server → Client (FireAllClients / FireClient):
--   BattleStarted, TurnStarted, UnitMoved, UnitActed, UnitDefeated,
--   TurnEnded, BattleEnded, StatusApplied, StatusExpired,
--   DotDamage, SkillCardData, TargetHighlight, HealingApplied,
--   PlayerTurnPrompt (tells client it's their turn with available actions)
--
-- Client → Server (FireServer):
--   PlayerCommand (player sends their chosen action)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getOrCreateFolder()
	local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	assert(CTRBLXAI, "BattleEvents: CTRBLXAI folder not found in ReplicatedStorage.")

	local existing = CTRBLXAI:FindFirstChild("BattleRemotes")
	if existing then return existing end

	local folder = Instance.new("Folder")
	folder.Name   = "BattleRemotes"
	folder.Parent = CTRBLXAI
	return folder
end

local remoteFolder = getOrCreateFolder()

local EVENT_NAMES = {
	"BattleStarted",
	"TurnStarted",
	"UnitMoved",
	"UnitActed",
	"UnitDefeated",
	"TurnEnded",
	"BattleEnded",
	"StatusApplied",
	"StatusExpired",
	"DotDamage",
	-- Object-sourced damage feedback (2026-10-26): S->C { tileX, tileY, amount, focus }.
	-- Map objects that deal damage (Ballista, Catapult, Eye of the Magi, traps,
	-- explosions) fire this so the client shows a floating damage number + impact
	-- flash on the tile, and pans the camera to the tile when focus=true (first hit).
	"ObjectDamage",
	"SkillCardData",
	"TargetHighlight",
	"HealingApplied",
	-- Player input (Slice 3)
	"PlayerTurnPrompt",
	"PlayerCommand",
	-- Loadout save-on-trigger (2026-10-19): client fires on unit swap / tab exit /
	-- loadout screen exit; server saves once if changes were staged.
	"RequestSaveLoadout",
	"TurnOrderUpdate",
	-- Slice 4A
	"ChannelFizzled",
	"GuardActivated",
	"UnitPushed",
	-- Unit Inspector (3-tab)
	"InspectUnitRequest",
	"InspectUnitResponse",
	-- Move-target attack-range preview (on-demand, 2026-10-17). Client asks for
	-- the attack footprint of ONE prospective landing tile when the player picks
	-- it; server replies with that tile's attackable tiles. Replaces shipping the
	-- footprint for every move candidate in the turn prompt (payload reduction).
	"AttackRangeRequest",   -- C->S: { tileX, tileY }
	"AttackRangeResponse",  -- S->C: { tileX, tileY, attackTiles }
	-- Map Details panel (2026-10-17). Client asks for the current battle's quest
	-- details, optional quests, live "if you win" gold tally, and victory loot
	-- range; server replies with a read-only snapshot (nothing is rolled or
	-- committed — gold/loot still finalize only at battle end).
	"MapDetailsRequest",    -- C->S: {} (active player's open turn)
	"MapDetailsResponse",   -- S->C: { quest, optional, goldSoFar, goldOnVictory, lootMin, lootMax }
	-- Phase 2: Status expansion
	"TurnSkipped",
	"StatusImmune",
	-- Dev tools (Studio only)
	"DevCommand",
	-- Slice 4D: Management contracts
	"RewardScreen",       -- S->C: reward summaries after victory
	"RewardContinue",     -- C->S: player acknowledged rewards
	"LoadoutHubOpen",     -- S->C: tells client to show loadout hub
	"StartBattle",        -- C->S: player ready to fight
	-- Tile effects (Slice 3: TileEffectService)
	"TileEffectApplied",  -- S->C: effect placed on tile
	"TileEffectRemoved",  -- S->C: effect removed from tile
	"RoadChanged",        -- S->C: temporary road on a tile (ENV-019, 2026-10-27): { x, y, cut } (cut 0 = gone)
	"MoveCostChanged",    -- S->C: temporary move-cost penalty on a tile (ENV-003, 2026-10-27): { x, y, add } (add 0 = gone)
	"UnitStateChanged",   -- S->C: unit HP/isAlive changed (revive, etc.)
	"ObjectChanged",      -- S->C: OBS object break/HP-change/move (Phase 2c-0): { x, y, newHp? | destroyed? | moved? }
	"TrapSprung",         -- S->C: step-on trap fired (2026-10-28): { x, y, trapType, unitId, hidden }
	"TerrainChanged",     -- S->C: a tile's base terrain transformed mid-battle (BUG-002 fix 2026-10-22): { x, y, terrainId } (fire burn-out, Holy/Dark/Earth/Wind transforms, weather, explosion chain). Client re-skins the tile Part + updates its local terrain data; no reposition.
	"MapDataSync",        -- S->C: terrain/elevation/blocker grids for client
	-- Phase B: Quest Board
	"QuestBoardOpen",     -- S->C: quest board data (3 quests)
	"QuestSelected",      -- C->S: player picks a quest
	"QuestBoardCancel",   -- C->S: player backs out of the quest board, no commit (2026-10-14)
	"OpenAdventurersGuild", -- C->S: player opened the Adventurer's Guild; server shows quest board (2026-10-12)
	"AbandonQuest",      -- C->S: player cancels an accepted quest at the sortie briefing (50% penalty, 2026-10-13)
	"SelectSortieParty", -- C->S: player picks which saved party (A/B/C) to deploy at the sortie (2026-10-15)
	"MapBuildComplete",  -- S->C: battle prep (map+enemies) done; unlock the sortie button (scouting UX, 2026-10-13)
	-- Phase D: Deployment
	"DeploymentPhase",    -- S->C: deployment data (anchors, units, map size)
	"DeployUnit",         -- C->S: player places a unit on a tile
	"UnitDeployed",       -- S->C: server confirms unit placement
	"UndeployUnit",       -- C->S: player removes a deployed unit
	"UnitUndeployed",     -- S->C: server confirms unit removal
	"DeploymentReady",    -- C->S: all units placed, start battle
	-- Facing system
	"FacingPrompt",       -- S->C: asks player to choose facing direction
	"SetFacing",          -- C->S: player's chosen facing direction
	"FacingChanged",      -- S->C: unit facing direction changed
	-- Siege tile aiming (2026-10-24): object-initiated tile prompt, the tile
	-- analogue of FacingPrompt/SetFacing. Used by the Catapult (player picks a
	-- landing tile within range) and reusable by any future tile-targeted object.
	-- Self-contained prompt-and-block, does NOT touch the turn-action currentPrompt
	-- flow (stays off the inputMode state machine to avoid handler collisions).
	"TilePrompt",         -- S->C: { unitId, originX, originY, range, tiles = {{x,y}...}, aimMode } asks player to pick a tile
	"SetTile",            -- C->S: { unitId, tileX, tileY } player's chosen tile
	-- Item usage
	"ItemUsed",           -- S->C: unit used a consumable item
	-- Reinforcements (mid-battle spawn)
	"UnitSpawned",        -- S->C: a new unit entered the battle mid-fight
	-- Time cycle (Dawn/Day/Dusk/Night, one phase per 1000-CT round)
	"TimePhaseChanged",   -- S->C: the battle time-of-day phase changed
	-- Weather/crisis (one combined slot, re-rolls each round)
	"WeatherChanged",     -- S->C: the active weather/crisis condition changed
	-- Action announce (AP spend label over the acting unit)
	"ActionAnnounced",
	"BattleLogEntry",     -- S->C: { t = turn#, c = category, x = text, u = unitId? } server-authored battle log line    -- S->C: { unitId, label } e.g. "Move", "Basic Attack", skill/item name
	-- Channel VFX lifecycle (loop start/stop on the caster)
	"ChannelStarted",     -- S->C: { unitId, isHealing } start looping Charging 1/2
	"ChannelEnded",       -- S->C: { unitId } stop the channel loop (fired on execute; interrupt uses ChannelFizzled)
	"MultiTargetHit",     -- S->C: { unitId } attacker played a multi-target (Cleave) hit; client shows Multi-Slash on the attacker
	-- Shield subsystem (damage-absorption pool). S->C: a unit's shield_total
	-- changed (granted, absorbed damage, decayed, or broke). Client shows a
	-- shield bar/pill and a grant/break flourish.
	"ShieldChanged",      -- S->C: { unitId, shieldTotal, delta, reason, maxHp, currentHp }
	-- Battlefield events (35-event system). S->C: a battlefield event triggered;
	-- client shows a dramatic center-screen banner with the event's name.
	"BattlefieldEventAnnounced",  -- S->C: { eventName }
	-- Steal / Mug slot pick (2026-10-24)
	"StealPrompt",   -- S->C: { casterId, targetId, targetName, slots }
	"StealChoice",   -- C->S: { casterId, slot }
}

-- RemoteFunctions for Slice 4D management contracts
local FUNCTION_NAMES = {
	"GetRosterData",
	"GetInventoryData",
	"RequestEquip",
	"RequestUnequip",
	-- Slice 4H: Doctrine management
	"RequestDoctrineSkillSelect",
	"GetDoctrineChoices",
	-- Doctrine ownership (2026-10-20): equip an owned doctrine instance; list owned.
	"RequestEquipDoctrine",
	"GetOwnedDoctrines",
	-- Slice 4I: Skill Card and Augment Card management
	"RequestEquipSkillCard",
	"RequestUnequipSkillCard",
	"RequestAttachAugment",
	"RequestDetachAugment",
	"GetSkillLoadout",
	-- Slice 4J: Stat allocation and comparison
	"GetEquipmentComparison",
	"GetDoctrineComparison",
	"GetUnitFullStats",
	-- Stat allocation basket (2026-10-18): read-only preview + batched commit
	"PreviewStatAllocation",
	"CommitStatAllocation",

	"RequestEquipConsumable",
	"RequestUnequipConsumable",
	-- Player picks a 2D race portrait for one of their units (loadout screen).
	-- (unitId, assetId) -> { ok, error? }; server validates assetId is in the
	-- unit's race pool, then stores it on the unit (persisted on next save).
	"RequestSetPortrait",
	-- Player picks a body/skin tint for one of their units (loadout screen).
	-- (unitId, r, g, b) -> { ok, error? }; server clamps 0-255 and stores it;
	-- nil r clears the tint. Persisted on next save.
	"RequestSetBodyColor",
	"GetConsumableSlots",
	-- Dismiss a roster unit from the Loadout Info tab (2026-10-15). Two modes:
	-- (unitId) preview -> { ok, cost, canAfford, isAvatar, name }; (unitId, true)
	-- commits: unequips all gear to inventory, charges 5x recruitment severance, removes the unit.
	"RequestDismissUnit",
	-- Skill hit preview (2026-10-30): (skillId, tileX, tileY) -> { ok, entries }. Read-only list of
	-- every unit a skill would affect on that tile and the predicted amount. Battle-time only.
	"PreviewSkillHits",
}

local BattleEvents = {}

for _, name in ipairs(EVENT_NAMES) do
	local existing = remoteFolder:FindFirstChild(name)

	if existing and existing:IsA("RemoteEvent") then
		BattleEvents[name] = existing
	else
		local event   = Instance.new("RemoteEvent")
		event.Name    = name
		event.Parent  = remoteFolder
		BattleEvents[name] = event
	end
end

for _, name in ipairs(FUNCTION_NAMES) do
	local existing = remoteFolder:FindFirstChild(name)

	if existing and existing:IsA("RemoteFunction") then
		BattleEvents[name] = existing
	else
		local fn = Instance.new("RemoteFunction")
		fn.Name   = name
		fn.Parent = remoteFolder
		BattleEvents[name] = fn
	end
end

return BattleEvents
