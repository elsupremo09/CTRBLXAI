-- CTRBLXAI | BattleTurnController  (extracted from Main.server.lua on 2026-10-12)
-- Per-turn engine: channel interrupt, turn prompt, player/AI turns, action broadcast,
-- facing/direction prompts, channeling activation, PlayerCommand handler.
-- Main injects live battle state via SetState each battle; SetPlayer/SetMapDimensions/
-- Init(tile helpers) are one-time. ForceEndTurn() backs the dev Instant-Win/Lose tools.

local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")
local Game = ServerScriptService:WaitForChild("Game")

local UnitSchema              = require(Game:WaitForChild("UnitSchema"))
local BattleCoordinator       = require(Game:WaitForChild("BattleCoordinator"))
local CommandService          = require(Game:WaitForChild("CommandService"))
local TargetingService        = require(Game:WaitForChild("TargetingService"))
local BattleVisualBroadcaster = require(Game:WaitForChild("BattleVisualBroadcaster"))
local StatusService           = require(Game:WaitForChild("StatusService"))
local TraitEffectService      = require(Game:WaitForChild("TraitEffectService"))
local CombatResolver          = require(Game:WaitForChild("CombatResolver"))
local ItemGenerator           = require(Game:WaitForChild("ItemGenerator"))
local InventoryService        = require(Game:WaitForChild("InventoryService"))
local EquipmentService        = require(Game:WaitForChild("EquipmentService"))
local PersistentStateService  = require(Game:WaitForChild("PersistentStateService"))
local SaveService             = require(Game:WaitForChild("SaveService"))
local RewardService           = require(Game:WaitForChild("RewardService"))
local DisplacementService     = require(Game:WaitForChild("DisplacementService"))
local TileEffectService       = require(Game:WaitForChild("TileEffectService"))
local TileCrossEffectService  = require(Game:WaitForChild("TileCrossEffectService"))
local RacePassiveService      = require(Game:WaitForChild("RacePassiveService"))
local ArmorPassiveService     = require(Game:WaitForChild("ArmorPassiveService"))
local _AugmentEffectService    = require(Game:WaitForChild("AugmentEffectService"))
local AIService               = require(Game:WaitForChild("AIService"))
local MapService              = require(Game:WaitForChild("MapService"))
local MapRenderer             = require(Game:WaitForChild("MapRenderer"))
local EnemyGenerator          = require(Game:WaitForChild("EnemyGenerator"))
local TraitRoller             = require(Game:WaitForChild("TraitRoller"))
local ObjectEffectService     = require(Game:WaitForChild("ObjectEffectService"))
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

local BattleTurnController = {}

local state
local player
local MAP_WIDTH
local MAP_HEIGHT
local setTileOccupant
local clearTileOccupant
local pendingCommand
local commandReceived

function BattleTurnController.SetState(s) state = s end
function BattleTurnController.SetPlayer(p) player = p end
function BattleTurnController.SetMapDimensions(w, h) MAP_WIDTH = w; MAP_HEIGHT = h end
function BattleTurnController.Init(deps)
	setTileOccupant = deps.setTileOccupant
	clearTileOccupant = deps.clearTileOccupant
end
function BattleTurnController.ForceEndTurn()
	pendingCommand = { actionType = "Wait" }
	if commandReceived then commandReceived:Fire() end
end

local function checkChannelInterrupt(unit, statusId)
	if unit.isChanneling and StatusService.IsChannelDisruptor(statusId) then
		-- Activation phase is uninterruptible (2026-10-07): InterruptChanneling
		-- returns false then, and the channel visual must keep running.
		if BattleCoordinator.InterruptChanneling(unit, statusId .. " applied") then
			BattleVisualBroadcaster.ChannelEnded(unit)
			BattleVisualBroadcaster.Log("channel", `{unit.name}\'s channel is interrupted by {statusId}.`, unit.id)
			return true
		end
	end
	return false
end

--------------------------------------------------
-- PLAYER TURN: Build prompt data
--
-- Sends the player all info needed to choose an action:
--   - Available skills (with MP check)
--   - Move candidates (tiles they can walk to)
--   - Attack candidates (enemies in melee range)
--------------------------------------------------

local function buildTurnPrompt(unit)
	-- Timeline data: all alive units sorted by remainingRt (who acts soonest)
	local timeline = {}
	for _, u in ipairs(state.units) do
		if u.isAlive then
			table.insert(timeline, {
				id          = u.id,
				name        = u.name,
				side        = u.side,
				remainingRt = u.remainingRt,
				currentHp   = u.currentHp,
				maxHp       = u.maxHp,
				isActive    = (u.id == unit.id), -- mark the actual active unit
				isChanneling = u.isChanneling or false,
				channelRt   = u.channelRt or 0,
				-- TWO-TIMER: remaining channel time = fixed deadline minus current CT, so the
				-- client places the channel event at the correct timeline position (independent
				-- of the caster's own RT entry).
				channelRemaining = math.max(0, (u.channelResolveCt or 0) - state.ct),
				channelPhase = u.channelPhase, -- "Channel" | "Activation" (2026-10-07)
				channeledSkillName = u.channelingData and u.channelingData.skillDef and u.channelingData.skillDef.name or nil,
				channeledSkillIcon = u.channelingData and u.channelingData.skillDef and u.channelingData.skillDef.icon or nil,
			})
		end
	end
	table.sort(timeline, function(a, b) return a.remainingRt < b.remainingRt end)

	local skills = {}
	for _, sid in ipairs(unit.skillIds or {}) do
		local def = CommandService.GetSkill(sid)
		if def then
			-- Level-based MP (2026-10-07): same pricing the server charges (CommandService.GetSkillMpCost).
			local promptMpCost = CommandService.GetSkillMpCost(unit, def, def.id)
			local canUse = UnitSchema.HasEnoughMp(unit, promptMpCost)
			local candidates, computedRange = TargetingService.GetSkillCandidates(unit, state.units, def)
			local isGroundTarget = false
			local isSelfTarget = false
			local tr = def.targetRules or "Enemy Unit"
			if tr == "Self" or tr == "Self (Aura)" or tr == "Ally Tile (centered on caster)"
				or (tr == "Self, Allies" and (def.range or 0) == 0)
			then
				isSelfTarget = true
			end
			local targetIds = {}
			for _, c in ipairs(candidates) do
				if c.isGroundTarget then
					isGroundTarget = true
					-- Ground target: no predicted damage, just a marker
					table.insert(targetIds, {
						id = "_ground_target", name = "Ground",
						tileX = c.tileX, tileY = c.tileY,
						predicted = 0, predType = "damage",
						isGroundTarget = true,
					})
				else
					local predicted = 0
					local predType = "damage"
					if def.isHealing then
						local healResult = CombatResolver.ResolveHealing(unit, c, def)
						predicted = healResult.finalHealing or 0
						predType = "healing"
					else
						local dmgResult = CombatResolver.ResolveSkill(unit, c, def)
						predicted = dmgResult.finalDamage or 0
					end
					local tEntry = {
						id        = c.id,
						name      = c.name,
						tileX     = c.tileX,
						tileY     = c.tileY,
						predicted = predicted,
						predType  = predType,
					}
					-- CHARGE preview: server computes the landing tile + straight path
					-- (shared with the actual commit logic) so the client can highlight
					-- the caster's landing (yellow) and the path (white) at confirmation.
					if def.isCharge then
						local landing = CommandService.ComputeChargeLanding(unit, c, state)
						if landing then
							tEntry.landingTileX = landing.x
							tEntry.landingTileY = landing.y
							tEntry.chargePath = CommandService.ComputeChargePath(unit.tileX, unit.tileY, landing.x, landing.y)
						end
					end
					table.insert(targetIds, tEntry)
				end
			end

			table.insert(skills, {
				id          = def.id,
				name        = def.name,
				willEndTurn = (def.channelTime or 0) > 0, -- warn player: channeling ends turn
				mpCost      = promptMpCost,
				range       = def.range or 1,
				pattern     = def.pattern or "Single",
				targetRules = def.targetRules or "Enemy Unit",
				isHealing   = def.isHealing or false,
				isCharge    = def.isCharge or false,
				channelTime = def.channelTime or 0,
				canUse      = canUse,
				targets     = targetIds,
				tags        = def.tags or {},
				groundTarget = isGroundTarget,
				selfTarget   = isSelfTarget,
				computedRange = computedRange or (def.range or 1),
				-- rtCost shown MUST match the charge path (CommandService): fixed/level skills
				-- use their authored cost; weapon-WT skills use (base component + weapon WT) × N.
				rtCost      = (function()
					local lvl = (unit.equipmentSlots and unit.equipmentSlots.MainHand and unit.equipmentSlots.MainHand.itemLevel) or 1
					local fx = GameConstants.CalcFixedSkillRt(def.id, lvl)
					if fx then return fx end
					if def.rtMult then
						local baseComp = StatusService.GetModifiedBaseRt(unit) * GameConstants.BASIC_ATTACK_RT_FACTOR
						local wWt = GameConstants.CalcEffectiveWt(unit.weaponWt or 10, (unit.effectiveStats or {}).STR or 10)
						return math.round((baseComp + wWt) * def.rtMult)
					end
					return def.rtCost or 60
				end)(),
				power       = def.power or 0,
				appliesStatus = def.appliesStatus or nil,
				description = def.isHealing and "Heals ally" or (def.appliesStatus and ("Applies " .. def.appliesStatus) or "Damages target"),
			})
		end
	end

	local moveTiles = TargetingService.GetMoveCandidates(unit, state.units, MAP_WIDTH, MAP_HEIGHT)
	if unit.isSummon and unit.canMove == false then moveTiles = {} end  -- immobile summon (Turret/Totem/Decoy)
	local moveCandidates = {}
	for _, tile in ipairs(moveTiles) do
		table.insert(moveCandidates, {
			tileX    = tile.tileX,
			tileY    = tile.tileY,
			pathCost = tile.pathCost,
			terrain  = tile.terrain,
			path     = tile.path,
		})
	end

	local attackCandidates = TargetingService.GetAttackCandidates(unit, state.units, unit.weaponMaxRange or 1)
	local attackTargets = {}
	for _, c in ipairs(attackCandidates) do
		-- Pre-calculate predicted basic attack damage for aim phase
		local atkResult = CombatResolver.ResolveBasicAttack(unit, c, unit.weaponDamage or 10)
		table.insert(attackTargets, {
			id        = c.id,
			name      = c.name,
			tileX     = c.tileX,
			tileY     = c.tileY,
			predicted = atkResult.finalDamage or 0,
		})
	end

	-- Push targets: adjacent enemies (range 1, Chebyshev)
	-- Android: extended range (up to 4), cannot target adjacent (minDistance 2)
	local pushOverride = RacePassiveService.GetPushOverride(unit)
	local pushMaxDist = pushOverride and pushOverride.maxDistance or 1
	local pushMinDist = pushOverride and pushOverride.minDistance or 1
	local pushTargets = {}
	-- Push targets ALL alive units in range (allies/enemies/neutrals/objects), not enemies only.
	-- Original design intent: anything can be pushed. GL-006 makes ally push safe (no collision).
	local pusherForce = 1
	if unit.derivedStats and unit.derivedStats.force then
		pusherForce = unit.derivedStats.force
	end
	for _, c in ipairs(state.units) do
		if c.isAlive and c.id ~= unit.id then
			local dist = math.max(math.abs(c.tileX - unit.tileX), math.abs(c.tileY - unit.tileY))
			if dist >= pushMinDist and dist <= pushMaxDist then
				-- maxPushDistance = max(0, Force - target Stability); client offers 1..max stop tiles.
				local tgtStability = 0
				if c.derivedStats and c.derivedStats.stability then
					tgtStability = c.derivedStats.stability
				elseif c.effectiveStats and c.effectiveStats.VIT then
					tgtStability = math.floor(c.effectiveStats.VIT / 60)
				end
				-- Status Stability buffs (mirrors DisplacementService.ResolvePush).
				tgtStability = math.max(0, tgtStability + StatusService.GetStabilityModifier(c))
				local maxPushDistance = math.max(0, pusherForce - tgtStability)
				table.insert(pushTargets, {
					id = c.id, name = c.name, tileX = c.tileX, tileY = c.tileY,
					maxPushDistance = maxPushDistance, side = c.side,
				})
			end
		end
	end

	-- Consumable items: usable slots only (has item + charges > 0), with
	-- targeting metadata so the client can mirror the Skill flow.
	local consumableItems = {}
	for idx = 1, (unit.consumableSlotCount or 3) do
		local slotData = unit.consumableSlots and unit.consumableSlots[idx]
		if slotData and slotData.consumableId and (slotData.currentCharges or 0) > 0 then
			local consDef = ConsumableData.GetById(slotData.consumableId)
			if consDef then
				local tr = consDef.targetRules or "Self"
				local formula = consDef.effectFormula or ""
				local itemRange = consDef.range or 0

				-- Classify targeting mode from targetRules
				local isSelf   = (tr == "Self")
				local isGround = (tr == "Ground" or tr == "Tile" or tr == "Enemy or Ground"
					or tr == "Self-origin" or tr == "Self and Allies")
				local isAllyTarget  = (tr == "Self or Ally" or tr == "Ally")
				local isEnemyTarget = (tr == "Enemy" or tr == "Enemy Unit")
				local isAnyTarget   = (tr == "Any Unit")

				local isHealing = formula:match("Restore%s+%d+%%.-Max HP") ~= nil

				-- Build unit-target candidates by side + Chebyshev range
				local itemTargets = {}
				if isAllyTarget or isEnemyTarget or isAnyTarget then
					for _, c in ipairs(state.units) do
						if c.isAlive then
							local sameSide = (c.side == unit.side)
							local includeAlly  = isAllyTarget and sameSide
							local includeEnemy = isEnemyTarget and (not sameSide)
							local includeAny   = isAnyTarget
							-- "Ally" excludes self; "Self or Ally"/"Any" include self
							if isAllyTarget and tr == "Ally" and c.id == unit.id then
								includeAlly = false
							end
							if includeAlly or includeEnemy or includeAny then
								local dist = math.max(
									math.abs(c.tileX - unit.tileX),
									math.abs(c.tileY - unit.tileY)
								)
								if dist <= itemRange then
									table.insert(itemTargets, {
										id = c.id, name = c.name,
										tileX = c.tileX, tileY = c.tileY,
									})
								end
							end
						end
					end
				end

				table.insert(consumableItems, {
					slotIndex     = idx,
					consumableId  = slotData.consumableId,
					name          = consDef.name or "Unknown",
					currentCharges = slotData.currentCharges,
					maxCharges    = slotData.maxCharges or consDef.maxCharges or 0,
					rtCost        = consDef.rtCost or 80,
					range         = itemRange,
					targetRules   = tr,
					pattern       = consDef.pattern or "Single",
					effectFormula = formula,
					category      = consDef.category or "",
					isHealing     = isHealing,
					selfTarget    = isSelf,
					groundTarget  = isGround,
					targets       = itemTargets,
				})
			end
		end
	end

	-- INTERACT candidates (Slice 4 — Interact Command framework). Classified
	-- server-side by native kind; the client labels each and only ungrays the
	-- Interact button when at least one candidate exists (Button Availability
	-- Policy). RT previews are a percentage of Modified Base RT per native kind.
	local interactCands = TargetingService.GetInteractCandidates(unit, state.units, state)
	local ObjectDataForInteract = require(game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("ObjectData"))
	local modBaseRtForInteract = StatusService.GetModifiedBaseRt(unit)
	local interactTargets = {}
	for _, c in ipairs(interactCands) do
		-- Per-kind RT preview (native percentages; headgear may reduce later).
		local rtPct = 0.10
		local label = "Interact"
		if c.interactKind == "allyRtHelp" then
			rtPct = 0.50; label = "Aid (−35% RT)"
		elseif c.interactKind == "reviveAlly" then
			rtPct = 0.30; label = "Resuscitate (channel)"
		elseif c.interactKind == "recruitEnemy" then
			rtPct = 0.10; label = "Recruit"
		elseif c.interactKind == "mapObject" then
			rtPct = 0.10; label = "Activate"
		end
		local rtPreview = math.round(modBaseRtForInteract * rtPct)
		if c.interactKind == "mapObject" then
			local od = ObjectDataForInteract.Objects and ObjectDataForInteract.Objects[c.archetypeId]
			if od and od.activation == "Interact (Free)" then
				rtPreview = 0
			elseif od and od.interactRT then
				rtPreview = od.interactRT
			end
		end
		table.insert(interactTargets, {
			interactKind = c.interactKind,
			id           = c.id,            -- unit targets
			objectId     = c.objectId,      -- map-object targets
			name         = c.name,
			tileX        = c.tileX,
			tileY        = c.tileY,
			label        = label,
			rtPreview    = rtPreview,
		})
	end

	return {
		unitId         = unit.id,
		unitName       = unit.name,
		unitSide       = unit.side,
		currentAp      = unit.currentAp,
		currentMp      = unit.currentMp,
		maxMp          = unit.maxMp,
		currentHp      = unit.currentHp,
		maxHp          = unit.maxHp,
		guardUsed      = unit.guardUsedThisTurn or false,
		tileX          = unit.tileX,
		tileY          = unit.tileY,
		skills         = skills,
		moveCandidates = moveCandidates,
		attackTargets  = attackTargets,
		pushTargets    = pushTargets,
		consumableSlots = consumableItems,
		interactTargets = interactTargets,
		interactAvailable = (#interactTargets > 0),
		pushRt         = math.round(StatusService.GetModifiedBaseRt(unit) * GameConstants.GUARD_RT_BASE_FACTOR),
		timeline       = timeline,
		currentCt      = state.ct,
		-- RT cost data so client can preview turn order shifts
		unitBaseRt = StatusService.GetModifiedBaseRt(unit),
		turnRtAccrued = state.turnRtAccrued or 0,
		attackRt   = math.round(
			StatusService.GetModifiedBaseRt(unit) * GameConstants.BASIC_ATTACK_RT_FACTOR
		) + math.round(GameConstants.CalcEffectiveWt(
			unit.weaponWt or 40, unit.effectiveStats and unit.effectiveStats.STR or 10
		)),
		waitRt     = math.round(
			StatusService.GetModifiedBaseRt(unit) * GameConstants.REST_RT_MULTIPLIER
		),
		weaponRtDelay = unit.weaponRtDelay or 0,
		weaponDamage  = unit.weaponDamage or 10,
		-- Unit identity (for active unit panel display)
		level    = unit.level or 1,
		race     = unit.raceId and RaceData.GetRace(unit.raceId)
			and RaceData.GetRace(unit.raceId).name or nil,
		doctrine = unit.doctrineId and DoctrineData[unit.doctrineId]
			and DoctrineData[unit.doctrineId].name or "",
		maxAp    = 2,
	}
end

--------------------------------------------------
-- PLAYER TURN: Wait for player command
--
-- Sends prompt, then yields until the client fires PlayerCommand.
-- Returns the command payload or nil on timeout.
--------------------------------------------------

local PLAYER_TURN_TIMEOUT = 120 -- seconds

pendingCommand = nil
commandReceived = Instance.new("BindableEvent")

BattleEvents.PlayerCommand.OnServerEvent:Connect(function(player, command)
	-- Accept commands from any connected player (single-player for now)
	pendingCommand = command
	commandReceived:Fire()
end)

local function waitForPlayerCommand(unit, playerObj)
	-- Send prompt to client
	local prompt = buildTurnPrompt(unit)
	print(string.format(
		"[Main] Sending PlayerTurnPrompt to %s for %s (AP:%d, Skills:%d, Moves:%d)",
		playerObj.Name, unit.name, unit.currentAp, #prompt.skills, #prompt.moveCandidates
	))
	BattleEvents.PlayerTurnPrompt:FireClient(playerObj, prompt)

	-- Wait for response
	pendingCommand = nil
	local startTime = tick()

	while not pendingCommand do
		local elapsed = tick() - startTime
		if elapsed > PLAYER_TURN_TIMEOUT then
			print("[Main] Player turn TIMEOUT — auto-waiting.")
			return { actionType = "Wait" }
		end
		commandReceived.Event:Wait()
	end

	local cmd = pendingCommand
	pendingCommand = nil
	return cmd
end

--------------------------------------------------
-- PLAYER TURN: Execute one player command
-- Returns: action table for broadcasting, or nil
--------------------------------------------------

--------------------------------------------------
-- FACING PROMPT: Ask player to choose facing direction
-- Called when player Guards or manually ends turn (Wait).
-- Skipped when all AP is spent naturally.
--------------------------------------------------
local function promptPlayerFacing(unit, playerObj)
	if not playerObj then return end
	BattleEvents.FacingPrompt:FireClient(playerObj, {
		unitId       = unit.id,
		currentFacing = unit.facing,
		tileX        = unit.tileX,
		tileY        = unit.tileY,
	})

	-- Wait for response with 5-second timeout
	local responded = false
	local conn
	conn = BattleEvents.SetFacing.OnServerEvent:Connect(function(player, data)
		if player == playerObj and data and data.unitId == unit.id then
			if GameConstants.IsValidFacing(data.facing) then
				unit.facing = data.facing
				BattleVisualBroadcaster.FacingChanged(unit)
				print(string.format("[Main] %s facing set to %s (player choice)", unit.name, unit.facing))
			end
			responded = true
		end
	end)
	-- Turn-based: wait until the player actually chooses (no timeout).
	while not responded do
		task.wait(0.1)
	end
	if conn then conn:Disconnect() end
end

--------------------------------------------------
-- CARDINAL DIRECTION PROMPT: reuse the facing ring to let the player AIM a
-- siege weapon (Ballista) in one of the 4 cardinal directions. Unlike
-- promptPlayerFacing this does NOT change the unit's facing — it just returns
-- the chosen direction. Diagonal picks snap to the nearest cardinal (the bolt
-- travels cardinally per DB). Single-player: uses Players:GetPlayers()[1].
-- Blocking prompt-and-wait, same pattern as promptPlayerFacing.
--------------------------------------------------
local DIAG_TO_CARDINAL = { NE = "N", SE = "S", SW = "S", NW = "N" }
local function promptCardinalDirection(unit)
	local playerObj = Players:GetPlayers()[1]
	if not playerObj then return nil end
	BattleEvents.FacingPrompt:FireClient(playerObj, {
		unitId        = unit.id,
		currentFacing = unit.facing,
		tileX         = unit.tileX,
		tileY         = unit.tileY,
		aimMode       = "siege",   -- client may style the ring differently; optional
	})
	local chosen, responded = nil, false
	local conn
	conn = BattleEvents.SetFacing.OnServerEvent:Connect(function(player, data)
		if player == playerObj and data and data.unitId == unit.id then
			local dir = data.facing
			if dir and DIAG_TO_CARDINAL[dir] then dir = DIAG_TO_CARDINAL[dir] end
			if dir == "N" or dir == "E" or dir == "S" or dir == "W" then
				chosen = dir
				responded = true
			end
		end
	end)
	while not responded do
		task.wait(0.1)
	end
	if conn then conn:Disconnect() end
	return chosen
end

-- Inject the cardinal direction prompter into ObjectEffectService now that it is
-- defined (the main OES injection block near the top runs before this function
-- exists, so wiring it here avoids a nil-prompter forward-reference).
if ObjectEffectService.SetDirectionPrompter then
	ObjectEffectService.SetDirectionPrompter(promptCardinalDirection)
end

--------------------------------------------------

local function executePlayerCommand(unit, command)
	local actionType = command.actionType

	if actionType == "Wait" then
		-- Player forfeits remaining AP — offer facing choice
		promptPlayerFacing(unit, Players:GetPlayers()[1])
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
		return { actionType = "Wait", unit = unit }
	end

	if actionType == "Guard" then
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Guard", nil)
		if ok then
			-- Guard forfeits remaining AP — offer facing choice
			promptPlayerFacing(unit, Players:GetPlayers()[1])
			return { actionType = "Guard", unit = unit }
		else
			warn("[Main] Guard rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Push" then
		-- Find the target unit by ID
		local target = nil
		for _, u in ipairs(state.units) do
			if u.id == command.targetId then target = u; break end
		end
		if not target then
			warn("[Main] Push: target not found")
			return nil
		end
		local oldTargetX, oldTargetY = target.tileX, target.tileY
		-- Distance control: player may request a stop distance (1..max). nil = full (legacy).
		local pushSelection = { target = target, pushDistance = command.pushDistance }
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Push", pushSelection)
		if ok then
			return { actionType = "Push", unit = unit, target = target,
				oldTargetX = oldTargetX, oldTargetY = oldTargetY }
		else
			warn("[Main] Push rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Interact" then
		-- INTERACT (Slice 4 framework). Client sends { actionType="Interact",
		-- interactKind, targetId (unit) | objectId (map object) }. The command
		-- service re-validates the candidate and dispatches the native effect.
		local selection = {
			interactKind = command.interactKind,
			targetId     = command.targetId,
			objectId     = command.objectId,
		}
		-- Capture pre-state for the apply side (recruit flips side → occupancy
		-- label must refresh, like Push updates occupancy after displacement).
		local tgt = nil
		if command.targetId then
			for _, u in ipairs(state.units) do
				if u.id == command.targetId then tgt = u; break end
			end
		end
		local oldSide = tgt and tgt.side or nil
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Interact", selection)
		if ok then
			return {
				actionType   = "Interact",
				unit         = unit,
				target       = tgt,
				interactKind = command.interactKind,
				oldSide      = oldSide,
			}
		else
			warn("[Main] Interact rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Move" then
		local selection = { tileX = command.tileX, tileY = command.tileY, pathCost = command.pathCost }
		local oldX, oldY = unit.tileX, unit.tileY
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Move", selection)
		if ok then
			return { actionType = "Move", unit = unit, oldTileX = oldX, oldTileY = oldY }
		else
			warn("[Main] Player move rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Attack" then
		-- Find the target unit by ID
		local target = nil
		for _, u in ipairs(state.units) do
			if u.id == command.targetId then
				target = u
				break
			end
		end
		if not target then
			warn("[Main] Player attack: target not found")
			return nil
		end

		local hpBefore = target.currentHp
		local rtBefore = target.remainingRt
		local statusesBefore = #target.statusInstances
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Attack", target)
		if ok then
			local newStatus = nil
			if #target.statusInstances > statusesBefore then
				newStatus = target.statusInstances[#target.statusInstances].id
			end
			local rtAdded = target.remainingRt - rtBefore
			return {
				actionType    = "Attack",
				unit          = unit,
				target        = target,
				damage        = hpBefore - target.currentHp,
				statusApplied = newStatus,
				rtDelay       = rtAdded > 0 and rtAdded or nil,
			}
		else
			warn("[Main] Player attack rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Skill" then
		local target = nil
		local skillDef = CommandService.GetSkill(command.skillId)
		if not skillDef then
			warn("[Main] Player skill: unknown skill " .. tostring(command.skillId))
			return nil
		end
		local _tr = skillDef.targetRules or "Enemy Unit"

		if command.tileX and command.tileY and not command.targetId then
			-- Ground targeting: create a virtual target with tile coords
			target = {
				tileX = command.tileX,
				tileY = command.tileY,
				isGroundTarget = true,
				isAlive = true,
				name = string.format("Ground(%d,%d)", command.tileX, command.tileY),
				id = "_ground_" .. command.tileX .. "_" .. command.tileY,
			}
			print(string.format("[Main] Skill ground target: (%d,%d)", command.tileX, command.tileY))
		else
			-- Unit targeting: find by ID
			for _, u in ipairs(state.units) do
				if u.id == command.targetId then
					target = u
					break
				end
			end
		end
		if not target then
			warn("[Main] Player skill: target not found (targetId=" .. tostring(command.targetId) .. ")")
			return nil
		end

		-- Snapshot ALL units' HP/RT before commit (for AOE detection)
		local hpSnapshot = {}
		local rtSnapshot = {}
		local statusSnapshot = {}
		local burnSnapshot = {}
		for _, u in ipairs(state.units) do
			hpSnapshot[u.id] = u.currentHp
			rtSnapshot[u.id] = u.remainingRt
			statusSnapshot[u.id] = #u.statusInstances
			-- Snapshot burn stored value for accumulation detection
			local burnInst = StatusService.HasStatus(u, "Burn")
			burnSnapshot[u.id] = burnInst and burnInst.storedBurn or 0
		end

		local selection = { target = target, skillId = command.skillId }

		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Skill", selection)
		if ok then
			-- Detect ALL units that were affected (for AOE skills)
			local results = {}
			for _, u in ipairs(state.units) do
				local prevHp = hpSnapshot[u.id] or u.currentHp
				local hpDiff = prevHp - u.currentHp
				local prevStatuses = statusSnapshot[u.id] or 0
				local newStatus = nil
				if #u.statusInstances > prevStatuses then
					newStatus = u.statusInstances[#u.statusInstances].id
				else
					-- Detect refreshed/accumulated statuses (instance count didn't change)
					if skillDef.appliesStatus and hpDiff > 0 then
						local inst = StatusService.HasStatus(u, skillDef.appliesStatus)
						if inst then
							newStatus = skillDef.appliesStatus
						end
					end
				end
				if hpDiff ~= 0 or newStatus then
					local rtAdded = u.remainingRt - (rtSnapshot[u.id] or 0)
					table.insert(results, {
						actionType    = "Skill",
						unit          = unit,
						target        = u,
						skillName     = skillDef.name,
						damage        = math.max(0, hpDiff),
						healing       = math.max(0, -hpDiff),
						statusApplied = newStatus,
						isChanneling  = unit.isChanneling,
						rtDelay       = rtAdded > 0 and rtAdded or nil,
					})
				end
			end

			-- Return first result (broadcastActions handles one at a time)
			-- But we need to return ALL results for AOE
			if #results == 1 then
				return results[1]
			elseif #results > 1 then
				-- Return a special multi-hit result
				return { actionType = "MultiHit", actions = results }
			else
				-- No visible change (e.g. channel commit)
				return {
					actionType   = "Skill",
					unit         = unit,
					target       = target,
					skillName    = skillDef.name,
					damage       = 0,
					healing      = 0,
					isChanneling = unit.isChanneling,
				}
			end
		else
			warn("[Main] Player skill rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Item" then
		local slotIndex = command.itemSlotIndex
		if not slotIndex then
			warn("[Main] Player item: no itemSlotIndex")
			return nil
		end
		local slot = unit.consumableSlots and unit.consumableSlots[slotIndex]
		if not slot or not slot.consumableId then
			warn("[Main] Player item: empty slot " .. tostring(slotIndex))
			return nil
		end
		local consDef = ConsumableData.GetById(slot.consumableId)
		local itemName = consDef and consDef.name or "Item"

		-- Resolve target: ground tile (virtual) or unit by id
		local target = nil
		if command.tileX and command.tileY and not command.targetId then
			target = {
				tileX = command.tileX,
				tileY = command.tileY,
				isGroundTarget = true,
				isAlive = true,
				name = string.format("Ground(%d,%d)", command.tileX, command.tileY),
				id = "_ground_" .. command.tileX .. "_" .. command.tileY,
			}
		else
			for _, u in ipairs(state.units) do
				if u.id == command.targetId then
					target = u
					break
				end
			end
		end
		if not target then
			warn("[Main] Player item: target not found (targetId=" .. tostring(command.targetId) .. ")")
			return nil
		end

		-- Snapshot target state for result reporting
		local hpBefore = target.currentHp or 0
		local mpBefore = target.currentMp or 0
		local statusesBefore = target.statusInstances and #target.statusInstances or 0

		local selection = { itemSlotIndex = slotIndex, target = target }
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Item", selection)
		if ok then
			local hpDelta = (target.currentHp or 0) - hpBefore
			local mpDelta = (target.currentMp or 0) - mpBefore
			local newStatus = nil
			if target.statusInstances and #target.statusInstances > statusesBefore then
				newStatus = target.statusInstances[#target.statusInstances].id
			end
			local amount = 0
			if hpDelta ~= 0 then
				amount = math.abs(hpDelta)
			elseif mpDelta ~= 0 then
				amount = math.abs(mpDelta)
			end
			return {
				actionType    = "Item",
				unit          = unit,
				target        = target,
				itemName      = itemName,
				amount        = amount,
				statusApplied = newStatus,
			}
		else
			warn("[Main] Player item rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	warn("[Main] Unknown player command: " .. tostring(actionType))
	return nil
end

--------------------------------------------------
-- PLAYER TURN: Full loop (keeps prompting until AP=0 or Wait)
--------------------------------------------------

local function broadcastActions(actions, activeUnit)
	for _, action in ipairs(actions) do
		if action.actionType == "Move" then
			clearTileOccupant(action.oldTileX, action.oldTileY)
			local u = action.unit
			setTileOccupant(u.tileX, u.tileY, u.name, "Unit (" .. u.side .. ")", "Blocking")
			BattleVisualBroadcaster.UnitMoved(action.unit)

		elseif action.actionType == "Attack" or action.actionType == "Skill" then
			local target = action.target
			if target then
				if action.healing and action.healing > 0 then
					BattleVisualBroadcaster.HealingApplied(
						action.unit, target, action.healing, action.skillName, action.skillId
					)
				elseif action.isChanneling then
					-- Channel commit visual — no damage yet
				else
					local outcome = {
						finalDamage   = action.damage or 0,
						type          = "Damage",
						statusApplied = action.statusApplied,
						rtDelay       = action.rtDelay,
					}
					BattleVisualBroadcaster.UnitActed(
						action.unit, target, outcome, action.skillName, action.skillId
					)

					if not target.isAlive then
						clearTileOccupant(target.tileX, target.tileY)
					end

					if action.statusApplied then
						local statusInst = StatusService.HasStatus(target, action.statusApplied)
						if statusInst then
							-- Fallback icon: the applying skill's own icon (for statuses that
							-- have no dedicated status icon, e.g. Crippled).
							local _srcIcon = nil
							if action.skillId then
								local _sk = SkillData[action.skillId]
								if not _sk then
									local _key = string.upper(action.skillId):gsub("SKILL_", "SKL-"):gsub("_", "-")
									_sk = SkillData[_key]
								end
								_srcIcon = _sk and _sk.icon or nil
							end
							BattleVisualBroadcaster.StatusApplied(
								target, action.statusApplied, statusInst.remainingTurns, _srcIcon
							)
						end
						checkChannelInterrupt(target, action.statusApplied)
					end
				end
			end

		elseif action.actionType == "Guard" then
			-- Guard visual already broadcast by CommandService; nothing extra needed here

		elseif action.actionType == "Push" then
			-- Update tile occupancy for push displacement
			if action.target and action.oldTargetX then
				clearTileOccupant(action.oldTargetX, action.oldTargetY)
				local t = action.target
				if t.isAlive then
					setTileOccupant(t.tileX, t.tileY, t.name, "Unit (" .. t.side .. ")", "Blocking")
				end
			end
			-- Push visual already broadcast by CommandService

		elseif action.actionType == "Interact" then
			-- Recruit flips the target's side to Neutral — refresh its tile
			-- occupant label so highlighting/targeting treats it correctly.
			-- Ally-RT-help and channeled revive need no occupancy change here
			-- (revive resolves later at its channel deadline). Map-object is parked.
			if action.interactKind == "recruitEnemy" and action.target then
				local t = action.target
				if t.isAlive then
					setTileOccupant(t.tileX, t.tileY, t.name, "Unit (" .. t.side .. ")", "Blocking")
				end
			end
			-- Interact visuals already broadcast by CommandService
		end
	end

	-- After each broadcast batch, send updated timeline so client sees
	-- real-time turn order changes (especially during AI turns)
	local timelineUpdate = {}
	for _, u in ipairs(state.units) do
		if u.isAlive then
			table.insert(timelineUpdate, {
				id = u.id, name = u.name, side = u.side,
				remainingRt = u.remainingRt, isChanneling = u.isChanneling or false,
				channelRt = u.channelRt or 0,
				channelRemaining = math.max(0, (u.channelResolveCt or 0) - state.ct),
				channelPhase = u.channelPhase, -- "Channel" | "Activation" (2026-10-07)
				channeledSkillName = u.channelingData and u.channelingData.skillDef and u.channelingData.skillDef.name or nil,
				channeledSkillIcon = u.channelingData and u.channelingData.skillDef and u.channelingData.skillDef.icon or nil,
			})
		end
	end
	BattleEvents.TurnOrderUpdate:FireAllClients({ units = timelineUpdate, currentCt = state.ct })
end


local function runPlayerTurn(unit)
	local actions = {}

	-- Find the first connected player (single-player game)
	local playerObj = Players:GetPlayers()[1]
	if not playerObj then
		warn("[Main] No player connected — AI fallback")
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
		return {}
	end

	while BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 and unit.isAlive do
		local command = waitForPlayerCommand(unit, playerObj)
		local action = executePlayerCommand(unit, command)

		if action then
			-- Handle MultiHit (AOE) results
			if action.actionType == "MultiHit" then
				for _, subAction in ipairs(action.actions) do
					table.insert(actions, subAction)
				end
				broadcastActions(action.actions, unit)
				-- Multi-target (Cleave) flourish: count damage sub-hits; if 2+, play
				-- Multi-Slash ONCE on the attacker (each target already showed Hit).
				local _dmgHits = 0
				for _, sub in ipairs(action.actions) do
					if (sub.actionType == "Attack" or sub.actionType == "Skill") and (sub.damage or 0) > 0 then
						_dmgHits = _dmgHits + 1
					end
				end
				if _dmgHits >= 2 then
					BattleVisualBroadcaster.MultiTargetHit(unit)
				end
			else
				table.insert(actions, action)
				broadcastActions({ action }, unit)
			end

			-- If it was Wait, turn ended inside CommandService
			if action.actionType == "Wait" then
				break
			end
		else
			-- Command rejected — send prompt again
		end
	end

	-- Close turn if still open
	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
	end

	return actions
end

--------------------------------------------------
-- AI LOGIC (same as before)
--------------------------------------------------

local function _findLowestAlly(unit, allUnits)
	local lowest = nil
	local lowestPct = 1.0
	for _, other in ipairs(allUnits) do
		if other.isAlive and other.side == unit.side then
			local pct = other.currentHp / other.maxHp
			if pct < lowestPct then
				lowestPct = pct
				lowest = other
			end
		end
	end
	return lowest, lowestPct
end

local function runAiTurn(unit)
	local allUnits = state.units
	local actions  = {}

	local function tryCommit(actionType, selection, skillName)
		if BattleCoordinator.GetPhase(state) ~= "TurnOpen" then
			return false
		end

		local targetUnit = nil
		if actionType == "Attack" then
			targetUnit = selection
		elseif actionType == "Skill" then
			targetUnit = selection and selection.target
		end
		-- Ground/tile-targeted skills (e.g. Poison Trap) pass a stat-less marker
		-- { tileX, tileY, isGroundTarget = true } as the target. It is truthy but
		-- has no currentHp / statusInstances, so the unit-tracking reads below
		-- crashed (#nil at the old L3159, aborting the whole AI turn). The real
		-- work is done by ValidateAndCommit(selection); this block only tracks
		-- HP/status deltas for a real unit, so treat a ground marker as no unit.
		if targetUnit and targetUnit.isGroundTarget then
			targetUnit = nil
		end
		local hpBefore = targetUnit and targetUnit.currentHp or 0
		local statusesBefore = (targetUnit and targetUnit.statusInstances) and #targetUnit.statusInstances or 0

		local oldTileX = unit.tileX
		local oldTileY = unit.tileY

		local ok, _ = CommandService.ValidateAndCommit(
			state, unit.id, actionType, selection
		)

		if ok and actionType ~= "Wait" then
			local damage = 0
			local healing = 0
			if targetUnit then
				local hpDiff = hpBefore - targetUnit.currentHp
				if hpDiff > 0 then
					damage = hpDiff
				elseif hpDiff < 0 then
					healing = -hpDiff
				end
			end

			local newStatus = nil
			if targetUnit and #targetUnit.statusInstances > statusesBefore then
				newStatus = targetUnit.statusInstances[#targetUnit.statusInstances].id
			else
				-- Detect refreshed/accumulated statuses (e.g. Burn accumulation)
				if targetUnit and actionType == "Skill" and selection and selection.skillId then
					local def = CommandService.GetSkill(selection.skillId)
					if def and def.appliesStatus and damage > 0 then
						local inst = StatusService.HasStatus(targetUnit, def.appliesStatus)
						if inst then newStatus = def.appliesStatus end
					end
				end
			end

			table.insert(actions, {
				actionType     = actionType,
				unit           = unit,
				oldTileX       = oldTileX,
				oldTileY       = oldTileY,
				target         = targetUnit,
				skillName      = skillName,
				skillId        = (selection and selection.skillId) or nil,  -- for client VFX lookup
				damage         = damage,
				healing        = healing,
				statusApplied  = newStatus,
				isChanneling   = unit.isChanneling,
			})

			if newStatus and targetUnit then
				checkChannelInterrupt(targetUnit, newStatus)
			end
		end

		return ok
	end

	-- Per-AP decision loop (one smart brain + personality scoring).
	-- The brain returns ONE best action; we commit it, then re-evaluate with
	-- remaining AP. This replaces the old multi-step plan executor AND the old
	-- bolt-on consumable block (item use is now a scored option inside the brain).
	local MAX_AI_ACTIONS = 8  -- safety cap against any pathological loop
	local actionsThisTurn = 0
	while BattleCoordinator.GetPhase(state) == "TurnOpen"
		and (unit.currentAp or 0) > 0
		and actionsThisTurn < MAX_AI_ACTIONS do

		-- Neutral battlefield-event NPCs use their own lightweight behaviour (move
		-- across map / seek treasure / hunt monster / stay passive), NOT the enemy
		-- AI brain which has no neutral concept.
		local action
		if unit.side == "Neutral" then
			action = BattlefieldEventService.NeutralAction(unit, state)
		else
			action = AIService.DecideAction(unit, allUnits, MAP_WIDTH, MAP_HEIGHT)
		end
		if not action or action.actionType == "Wait" then
			break  -- brain chose to stop; fall through to end-of-turn Wait
		end

		local committed = false
		local a = action.actionType
		if a == "Attack" then
			committed = tryCommit("Attack", action.selection, nil)
		elseif a == "Skill" then
			committed = tryCommit("Skill", action.selection, action.skillName)
		elseif a == "Move" then
			committed = tryCommit("Move", action.selection, nil)
		elseif a == "Guard" then
			committed = tryCommit("Guard", nil, nil)
		elseif a == "Item" then
			committed = tryCommit("Item", action.selection, nil)
		else
			-- Unknown action type: stop rather than spin.
			break
		end

		actionsThisTurn = actionsThisTurn + 1

		-- If a commit failed (state changed / illegal now), stop and end turn
		-- rather than retrying the same rejected action forever.
		if not committed then
			break
		end
	end

	-- AI facing: face toward nearest alive enemy at turn end
	do
		local nearestDist = math.huge
		local nearestEnemy = nil
		for _, other in ipairs(allUnits) do
			if other.isAlive and other.side ~= unit.side then
				local dist = math.max(math.abs(other.tileX - unit.tileX), math.abs(other.tileY - unit.tileY))
				if dist < nearestDist then
					nearestDist = dist
					nearestEnemy = other
				end
			end
		end
		if nearestEnemy then
			local aiFacing = GameConstants.CalcFacingFrom(unit.tileX, unit.tileY, nearestEnemy.tileX, nearestEnemy.tileY)
			if aiFacing then
				unit.facing = aiFacing
				BattleVisualBroadcaster.FacingChanged(unit)
			end
		end
	end

	-- Always end turn
	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
	end

	return actions
end

--------------------------------------------------
-- HANDLE CHANNELING ACTIVATION
--------------------------------------------------

local function handleChannelingActivation(activeUnit)
	-- Grab skill name before activation clears channeling data
	local channeledSkillName = activeUnit.channelingData
		and activeUnit.channelingData.skillDef
		and (activeUnit.channelingData.skillDef.name or activeUnit.channelingData.skillDef.id)
		or "Unknown"

	local success, result = CommandService.ActivateChanneledSkill(state, activeUnit)
	local actions = {}

	if not success then
		-- Fizzle: target died, MP insufficient, etc.
		BattleVisualBroadcaster.ChannelFizzled(activeUnit, channeledSkillName, result or "fizzled")
	elseif result then
		BattleVisualBroadcaster.ChannelEnded(activeUnit)
		-- Resuscitate logs its own detailed line in CommandService (no duplicate).
		if result.type ~= "Resuscitate" then
			BattleVisualBroadcaster.Log("channel", `{activeUnit.name}\'s {channeledSkillName or "skill"} lands.`, activeUnit.id)
		end
		if result.type == "Healing" then
			table.insert(actions, {
				actionType = "Skill", unit = activeUnit, target = result.target,
				skillName = result.skillName, healing = result.healing, damage = 0,
			})
		elseif result.type == "AOE" then
			for _, entry in ipairs(result.targets or {}) do
				table.insert(actions, {
					actionType = "Skill", unit = activeUnit, target = entry.target,
					skillName = result.skillName, damage = entry.outcome.finalDamage,
					healing = 0, statusApplied = entry.outcome.appliesStatus,
				})
			end
		elseif result.type == "Damage" then
			table.insert(actions, {
				actionType = "Skill", unit = activeUnit, target = result.target,
				skillName = result.skillName, damage = result.damage,
				healing = 0, statusApplied = result.statusApplied,
			})
		end
	end

	-- TWO-TIMER MODEL: do NOT end a turn here. Channel resolution is driven by the
	-- channel deadline (ChannelResolve phase), not by the caster's turn. Phase is
	-- managed by BattleCoordinator.ResolveChannelDeadline in the main loop.

	return actions
end

BattleTurnController.broadcastActions = broadcastActions
BattleTurnController.handleChannelingActivation = handleChannelingActivation
BattleTurnController.runPlayerTurn = runPlayerTurn
BattleTurnController.runAiTurn = runAiTurn

return BattleTurnController