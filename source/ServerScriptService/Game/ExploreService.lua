--!strict
-- ExploreService.lua
-- CTRBLXAI | Slice 6 — Base Management (Batch 2 of 3)
--
-- OWNS (per service_boundaries 'Explore Service'):
--   Exploration EXPEDITION state. An expedition is a SERIES of linked battles
--   with rewards along the way — distinct from a single battle and from dispatch
--   (which has no battle). ExploreService is an ORCHESTRATOR: it sequences the
--   series and advances expedition state, but it does NOT contain combat or
--   reward logic — each battle in the series is resolved through the EXISTING
--   battle + reward pipeline.
--
-- READS:
--   quest/activity structure (quest activity types: Exploration = series of
--   battles), reward eligibility, the current Map Level. It READS results from
--   the existing battle pipeline; it does not simulate combat.
--
-- WRITES:
--   Expedition progress (which battle in the series, accumulated earned XP/gold,
--   loot held pending). It commits per-battle rewards through the EXISTING
--   RewardService path on each battle VICTORY, and Guild XP through the EXISTING
--   GuildService on completion. It opens no new store.
--
-- MUST NOT OWN:
--   The battle loop (BattleCoordinator / Main), reward GENERATION
--   (RewardService), loot tables, currency, the roster.
--
-- PRIMARY INTERFACE:
--   StartExpedition(playerId, mapLevel, seriesLength?, seed?, squad?) -> ok, state|reason
--   GetState(playerId)                                        -> state|nil
--   ReportBattleResult(playerId, outcome, battleContext)      -> ok, resolution
--       outcome = "victory" | "wipeout" | "escape"
--   AbortExpedition(playerId)                                 -> ok
--
-- FAILURE BOUNDARY (LOCKED):
--   Expedition state advances ONLY on battle completion. A wipeout OR escape
--   ends the expedition following the locked defeat rules:
--     keep earned (kill) XP, keep 50% of gold earned, lose ALL other loot,
--     no quest progress. (Only VICTORY commits that battle's loot.)
--
-- ──────────────────────────────────────────────────────────────────────────────
-- LOCKED DATA — copied verbatim from CTRBLXAI.db. Do NOT invent or tune here.
-- ──────────────────────────────────────────────────────────────────────────────
--
--   loot_progression / quest activity types (Exploration, Locked direction):
--     "Series of battles. Each battle awards XP separately. Total = sum of
--      individual battles."
--   loot_progression (Victory summary, Locked):
--     "Victory: 100% kill XP + 100% gold + all loot committed + quest progress
--      + quest rewards + full Guild XP + post-battle 35% recovery."
--   loot_progression (Defeat Rewards, Locked):
--     Gold on wipeout: player keeps 50% of gold earned from enemy kills during
--       the battle; other 50% is lost.
--     Loot on wipeout: ALL loot drops are LOST. Only victory commits loot.
--     Kill XP: XP from enemies defeated is retained even on wipeout; per-kill
--       XP accumulates during battle and is awarded regardless of outcome.
--     Escape follows the same reward rules as wipeout: keep kill XP, keep 50%
--       gold, lose all loot, no quest progress, Guild XP penalty.
--   economy_framework (Battle Completion Gold, Locked):
--     Base × (1 + Map Level / 50). Exploration base = 25.
--
-- ──────────────────────────────────────────────────────────────────────────────
-- FLAGS — structure locked, exact value NOT in CTRBLXAI.db as of 2026-10-05.
-- Implemented as structure and surfaced for a Designer ruling (NOT invented).
--   FLAG-E1  (RESOLVED 2026-10-06) SERIES LENGTH. unit_progression 'Expedition
--            Length' now LOCKS the default: "Explore expeditions default to 3
--            linked battles. Rewards granted per battle (gold, loot, Guild XP)
--            via the normal battle+reward pipeline; completion after battle 3."
--            DEFAULT_SERIES_LENGTH is therefore 3 (read verbatim from the DB),
--            and rewards are paid per battle with completion on the last battle
--            — which is exactly how ReportBattleResult already behaves. The
--            StartExpedition seriesLength parameter still OVERRIDES the default
--            when supplied (per-quest overrides are allowed). No value invented.
--   FLAG-E2  GUILD XP PENALTY ON DEFEAT. The defeat rule locks "Guild XP
--            penalty" but the exact penalty formula is marked pending in the DB
--            ("Exact penalty formula pending design"). On wipeout/escape we
--            apply NO Guild XP (zero), which is the DB's stated direction
--            ("reduced or zero"), and flag that the exact penalty (possibly a
--            negative modifier) is a Designer ruling. We never invent a number.
--   FLAG-E3  PER-BATTLE GOLD/XP ACCOUNTING INPUT. The locked defeat math needs
--            "gold earned from enemy kills during the battle" and "kill XP
--            accumulated". Those totals are produced by the battle pipeline, not
--            by ExploreService. We READ them from the battleContext the caller
--            passes (goldEarned, killXp). ExploreService applies the LOCKED
--            50%/100% rules to those inputs; it does not compute kill gold/XP
--            itself (that is CombatResolver/Reward territory).
--   FLAG-E4  EXPEDITION SQUAD CALLER. StartExpedition now accepts and stores the
--            SENT squad (the unitIds the player committed to the outing). Per the
--            Designer ruling (unit_progression id 53, grounded in "participation
--            earns full"), that sent squad — NOT whoever is currently deployed —
--            is the participant set earning full XP for every battle in the
--            series. The plumbing is complete and works the moment a squad is
--            passed. BUT: as of this build NOTHING calls StartExpedition yet
--            (no live caller exists in source). The caller that initiates an
--            expedition MUST pass the sent-squad list (array of unitIds). We do
--            NOT invent a squad; absent one, the stored squad is empty and the
--            XP sink no-ops (no XP goes to the wrong units).

local ExploreService = {}

--------------------------------------------------
-- LOCKED CONSTANTS (mirror of DB — see header)
--------------------------------------------------

local WIPEOUT_GOLD_KEEP = 0.50     -- keep 50% of gold earned on wipeout/escape
local VICTORY_GOLD_KEEP = 1.00     -- keep 100% on victory
local EXPLORATION_GOLD_BASE = 25   -- economy_framework Battle Completion Gold (Exploration)
local GOLD_MAP_LEVEL_DIVISOR = 50  -- Base × (1 + Map Level / 50)

local DEFAULT_SERIES_LENGTH = 3    -- LOCKED (unit_progression 'Expedition Length', 2026-10-06): expeditions default to 3 linked battles

--------------------------------------------------
-- INJECTED DEPENDENCIES (dependency injection — no circular require)
--------------------------------------------------

local _rewardService: any = nil     -- GenerateRewards(playerId, mapLevel, opportunityId) — EXISTING pipeline
local _guildService: any = nil      -- AwardGuildXp(playerId, contentType, contentLevel, bonus?)
local _currency: any = nil          -- CurrencyService.AsProvider(): AddGold (gold is credited here)
local _unitXpSink: any = nil        -- how a battle's kill XP reaches the EXPEDITION SQUAD (see header + ReportBattleResult)

function ExploreService.SetRewardService(svc: any) _rewardService = svc end
function ExploreService.SetGuildService(svc: any) _guildService = svc end
function ExploreService.SetCurrencyProvider(svc: any) _currency = svc end
function ExploreService.SetUnitXpSink(fn: any) _unitXpSink = fn end

--------------------------------------------------
-- STATE
--   state[playerId] = {
--     active, mapLevel, seriesLength, battleIndex (1-based, next battle),
--     earnedXp, earnedGold, committedLoot (count), seed, opportunityCounter,
--     squad (array of unitIds the player SENT — the participant set for the
--       whole expedition; survives rejoin via Export/Import; Designer id 53)
--   }
-- Serialized through the EXISTING SaveService path via Export/Import (same
-- pattern as the batch-1 services). No second store.
--------------------------------------------------

local state: { [string]: any } = {}

local function stateOf(playerId: string)
	return state[playerId]
end

--------------------------------------------------
-- GOLD: Battle Completion Gold (Exploration) — LOCKED
--   Base × (1 + Map Level / 50), Exploration base = 25.
-- This is the per-battle COMPLETION gold the expedition pays on a victory. The
-- separate "gold earned from enemy kills" (for the 50%-on-wipeout rule) is an
-- INPUT from the battle pipeline (FLAG-E3), not computed here.
--------------------------------------------------

local function explorationCompletionGold(mapLevel: number): number
	local lvl = math.max(1, math.floor(mapLevel or 1))
	return math.floor(EXPLORATION_GOLD_BASE * (1 + lvl / GOLD_MAP_LEVEL_DIVISOR))
end

--------------------------------------------------
-- PRIMARY INTERFACE: StartExpedition
--
-- Begins a new expedition (series of battles). Only one expedition may be
-- active per player at a time; starting while one is active is rejected.
--
-- seriesLength (FLAG-E1): number of battles in the series; defaults to 1.
--
-- squad: the list of unitIds the player SENT on this expedition. Per the
--   Designer ruling (unit_progression id 53, grounded in "participation earns
--   full"), the SENT squad is the participant set for EVERY battle in the
--   series — every sent unit earns FULL battle XP (Humans ×1.10), exactly like
--   deployed units in a normal battle. There is NO bench rate inside an
--   expedition. The squad is stored at start and survives a rejoin (Export/
--   Import) so XP always goes to the squad that was sent, NOT to whoever is
--   currently deployed. If the caller does not supply a squad, it stores an
--   empty list and the XP sink no-ops (FLAG-E4: the StartExpedition CALLER
--   must pass the sent-squad list — see Main.server.lua wiring).
--
-- Returns: ok(boolean), state(table)|reason(string)
--------------------------------------------------

function ExploreService.StartExpedition(playerId: string, mapLevel: number, seriesLength: number?, seed: number?, squad: { string }?)
	assert(type(playerId) == "string", "ExploreService.StartExpedition: playerId required")

	local existing = stateOf(playerId)
	if existing and existing.active then
		return false, "An expedition is already in progress"
	end

	local length = DEFAULT_SERIES_LENGTH
	if type(seriesLength) == "number" and seriesLength >= 1 then
		length = math.floor(seriesLength)
	end

	-- Sanitize the sent squad into a clean array of unitId strings. This is the
	-- participant set for the WHOLE expedition (Designer ruling, unit_progression
	-- id 53). Unknown/absent squad → empty list (FLAG-E4: caller must supply it).
	local cleanSquad: { string } = {}
	if type(squad) == "table" then
		for _, uid in ipairs(squad) do
			if uid ~= nil then
				cleanSquad[#cleanSquad + 1] = tostring(uid)
			end
		end
	end

	state[playerId] = {
		active = true,
		mapLevel = math.max(1, math.floor(mapLevel or 1)),
		seriesLength = length,
		battleIndex = 1,          -- next battle to resolve (1-based)
		earnedXp = 0,             -- accumulated kill XP (retained on any outcome)
		earnedGold = 0,           -- accumulated gold actually kept
		committedLoot = 0,        -- count of loot items committed on victories
		seed = seed or 0,
		opportunityCounter = 0,   -- for unique RewardService opportunity ids
		squad = cleanSquad,       -- the SENT squad: participant set for EVERY battle (Designer id 53)
	}

	print(string.format("[ExploreService] START expedition for %s | mapLevel %d | %d battle(s) (FLAG-E1 if default) | squad %d unit(s)%s",
		playerId, state[playerId].mapLevel, length, #cleanSquad,
		(#cleanSquad == 0) and " [FLAG-E4: caller passed no squad — XP sink will no-op]" or ""))

	return true, ExploreService.GetState(playerId)
end

--------------------------------------------------
-- PRIMARY INTERFACE: ReportBattleResult
--
-- Called by Main/BattleCoordinator AFTER a battle in the series completes. This
-- is the ONLY place expedition state advances (locked: advances only on battle
-- completion). ExploreService does NOT run the battle — it reacts to the result.
--
-- outcome: "victory" | "wipeout" | "escape"
-- battleContext (from the battle pipeline — FLAG-E3 inputs):
--   { killXp = number, goldEarned = number, contentType = string?, opportunityId = string? }
--     killXp     = kill XP accumulated this battle (retained on ANY outcome)
--     goldEarned = gold earned from enemy kills this battle (100% on victory,
--                  50% on wipeout/escape)
--     contentType= Guild XP content type for a victory ("Normal"/"Elite"/"Boss");
--                  defaults to "Normal"
--     opportunityId = unique id for RewardService dedupe; auto-generated if nil
--
-- VICTORY: commit this battle's loot via RewardService (EXISTING pipeline),
--   keep 100% gold (kill gold + the Exploration completion gold), full Guild XP,
--   accumulate kill XP, advance the series. When the last battle is won the
--   expedition completes.
-- WIPEOUT or ESCAPE: keep accumulated kill XP + 50% of THIS battle's kill gold,
--   lose ALL loot (none generated), no quest progress, Guild XP penalty
--   (zero — FLAG-E2). The expedition ENDS immediately.
--
-- Returns: ok(boolean), resolution(table)
--------------------------------------------------

function ExploreService.ReportBattleResult(playerId: string, outcome: string, battleContext: any)
	assert(type(playerId) == "string", "ExploreService.ReportBattleResult: playerId required")

	local s = stateOf(playerId)
	if not s or not s.active then
		return false, { reason = "No active expedition" }
	end

	local ctx = type(battleContext) == "table" and battleContext or {}
	local killXp = math.max(0, math.floor(tonumber(ctx.killXp) or 0))
	local goldEarned = math.max(0, math.floor(tonumber(ctx.goldEarned) or 0))

	-- Kill XP is retained regardless of outcome (LOCKED).
	s.earnedXp += killXp

	-- Route this battle's kill XP to the EXPEDITION SQUAD (the units the player
	-- SENT), not to whoever is currently deployed. Per the Designer ruling
	-- (unit_progression id 53), the sent squad is the participant set for every
	-- battle in the series — all earn FULL battle XP (Humans ×1.10). We hand the
	-- sink the stored squad plus a STABLE per-expedition-battle battleId so the
	-- Progression idempotency guard treats each series battle as its own grant.
	-- battleId is stable per (seed, battleIndex): a rejoin that replays the same
	-- series battle will not double-grant.
	if killXp > 0 and _unitXpSink then
		local squad = (type(s.squad) == "table") and s.squad or {}
		local battleId = string.format("explore_%s_%d_b%d", playerId, s.seed, s.battleIndex)
		_unitXpSink(playerId, killXp, {
			squad = squad,
			battleId = battleId,
			won = (outcome == "victory"),
			mapLevel = s.mapLevel,
		})
	end

	if outcome == "victory" then
		-- Gold: 100% of kill gold + the Exploration battle-completion gold.
		local completionGold = explorationCompletionGold(s.mapLevel)
		local goldThisBattle = math.floor(goldEarned * VICTORY_GOLD_KEEP) + completionGold
		s.earnedGold += goldThisBattle
		if _currency and _currency.AddGold and goldThisBattle > 0 then
			_currency.AddGold(playerId, goldThisBattle)
		end

		-- Loot: commit this battle's rewards through the EXISTING RewardService
		-- pipeline. ExploreService does NOT generate loot — it orchestrates.
		local committedThisBattle = 0
		if _rewardService and _rewardService.GenerateRewards then
			s.opportunityCounter += 1
			local oppId = tostring(ctx.opportunityId)
			if type(ctx.opportunityId) ~= "string" then
				oppId = string.format("explore_%s_%d_%d", playerId, s.seed, s.opportunityCounter)
			end
			local results, equipCommitted = _rewardService.GenerateRewards(playerId, s.mapLevel, oppId)
			committedThisBattle = equipCommitted or 0
			s.committedLoot += committedThisBattle
			-- Non-equipment rewards are committed by Main (same contract as the
			-- normal battle path); ExploreService does not duplicate that commit.
			if type(results) == "table" then
				-- expose the raw results so Main can commit cards exactly as it
				-- does for a normal battle victory.
				ctx._rewardResults = results
			end
		end

		-- Guild XP: full, on victory (LOCKED). Content type defaults to Normal.
		local guildResult = nil
		if _guildService and _guildService.AwardGuildXp then
			local contentType = type(ctx.contentType) == "string" and ctx.contentType or "Normal"
			guildResult = _guildService.AwardGuildXp(playerId, contentType, s.mapLevel)
		end

		-- Advance the series.
		local finished = (s.battleIndex >= s.seriesLength)
		s.battleIndex += 1

		if finished then
			s.active = false
			print(string.format(
				"[ExploreService] VICTORY — expedition COMPLETE for %s | battles %d | earned XP %d | gold %d | loot %d",
				playerId, s.seriesLength, s.earnedXp, s.earnedGold, s.committedLoot))
			return true, {
				outcome = "victory",
				expeditionComplete = true,
				battleIndexNext = nil,
				goldThisBattle = goldThisBattle,
				killXp = killXp,
				committedLoot = committedThisBattle,
				totals = { earnedXp = s.earnedXp, earnedGold = s.earnedGold, committedLoot = s.committedLoot },
				guild = guildResult,
				rewardResults = ctx._rewardResults,
			}
		end

		print(string.format(
			"[ExploreService] VICTORY — battle %d/%d for %s | +%d XP | +%d gold | +%d loot | next battle %d",
			s.battleIndex - 1, s.seriesLength, playerId, killXp, goldThisBattle, committedThisBattle, s.battleIndex))
		return true, {
			outcome = "victory",
			expeditionComplete = false,
			battleIndexNext = s.battleIndex,
			goldThisBattle = goldThisBattle,
			killXp = killXp,
			committedLoot = committedThisBattle,
			totals = { earnedXp = s.earnedXp, earnedGold = s.earnedGold, committedLoot = s.committedLoot },
			guild = guildResult,
			rewardResults = ctx._rewardResults,
		}

	elseif outcome == "wipeout" or outcome == "escape" then
		-- Defeat rule (LOCKED): keep kill XP (already added above), keep 50% of
		-- THIS battle's kill gold, lose ALL loot (none generated), no quest
		-- progress, Guild XP penalty = zero (FLAG-E2). Expedition ends.
		local keptGold = math.floor(goldEarned * WIPEOUT_GOLD_KEEP)
		s.earnedGold += keptGold
		if _currency and _currency.AddGold and keptGold > 0 then
			_currency.AddGold(playerId, keptGold)
		end

		-- NO loot generated/committed (only victory commits loot — LOCKED).
		-- NO Guild XP awarded (penalty direction = reduced or zero; FLAG-E2).

		s.active = false
		print(string.format(
			"[ExploreService] %s — expedition ENDED for %s | kept %d XP | kept 50%% gold (+%d) | loot LOST | no quest progress | Guild XP 0 (FLAG-E2)",
			string.upper(outcome), playerId, s.earnedXp, keptGold))

		return true, {
			outcome = outcome,
			expeditionComplete = true,  -- the expedition is over (as a failure)
			expeditionFailed = true,
			goldThisBattle = keptGold,
			killXp = killXp,
			committedLoot = 0,
			lootLost = true,
			guildXpPenaltyApplied = true,  -- zero awarded (FLAG-E2)
			totals = { earnedXp = s.earnedXp, earnedGold = s.earnedGold, committedLoot = s.committedLoot },
		}

	else
		return false, { reason = "Unknown outcome: " .. tostring(outcome) }
	end
end

--------------------------------------------------
-- PRIMARY INTERFACE: AbortExpedition
--
-- Player-initiated abandon with no battle result. Per persistent_hp_mp_rules /
-- loot_progression, an abandoned run grants nothing beyond what was already
-- banked on prior victories (which were committed per-battle). We simply end the
-- expedition; already-committed XP/gold/loot stay (they were committed on their
-- own victories). No new reward, no penalty computed here.
--------------------------------------------------

function ExploreService.AbortExpedition(playerId: string)
	local s = stateOf(playerId)
	if not s or not s.active then
		return false
	end
	s.active = false
	print(string.format("[ExploreService] ABORTED expedition for %s | banked XP %d gold %d loot %d",
		playerId, s.earnedXp, s.earnedGold, s.committedLoot))
	return true
end

--------------------------------------------------
-- QUERY
--------------------------------------------------

function ExploreService.GetState(playerId: string)
	local s = stateOf(playerId)
	if not s then return nil end
	return {
		active = s.active,
		mapLevel = s.mapLevel,
		seriesLength = s.seriesLength,
		battleIndex = s.battleIndex,
		earnedXp = s.earnedXp,
		earnedGold = s.earnedGold,
		committedLoot = s.committedLoot,
		squad = s.squad,          -- the SENT squad (participant set for the whole trip)
	}
end

function ExploreService.IsActive(playerId: string): boolean
	local s = stateOf(playerId)
	return s ~= nil and s.active == true
end

--------------------------------------------------
-- SAVE INTEGRATION (via the EXISTING SaveService path — Key 3 Progression)
--
-- An in-progress expedition must survive a rejoin so banked XP/gold/loot and the
-- current battle index are not lost or re-granted. ExploreService does NOT touch
-- DataStore: Main.server.lua folds Export() into the Slice 4 Save payload and
-- feeds it back via Import() on load — same pattern as the batch-1 services.
--------------------------------------------------

function ExploreService.Export(playerId: string)
	local s = stateOf(playerId)
	if not s then return nil end
	return {
		active = s.active,
		mapLevel = s.mapLevel,
		seriesLength = s.seriesLength,
		battleIndex = s.battleIndex,
		earnedXp = s.earnedXp,
		earnedGold = s.earnedGold,
		committedLoot = s.committedLoot,
		seed = s.seed,
		opportunityCounter = s.opportunityCounter,
		squad = s.squad,          -- persist the SENT squad so it survives a rejoin (not re-granted)
	}
end

function ExploreService.Import(playerId: string, data: any)
	if type(data) ~= "table" then
		state[playerId] = nil
		return
	end
	state[playerId] = {
		active = data.active == true,
		mapLevel = math.max(1, math.floor(tonumber(data.mapLevel) or 1)),
		seriesLength = math.max(1, math.floor(tonumber(data.seriesLength) or DEFAULT_SERIES_LENGTH)),
		battleIndex = math.max(1, math.floor(tonumber(data.battleIndex) or 1)),
		earnedXp = math.max(0, math.floor(tonumber(data.earnedXp) or 0)),
		earnedGold = math.max(0, math.floor(tonumber(data.earnedGold) or 0)),
		committedLoot = math.max(0, math.floor(tonumber(data.committedLoot) or 0)),
		seed = tonumber(data.seed) or 0,
		opportunityCounter = math.max(0, math.floor(tonumber(data.opportunityCounter) or 0)),
		squad = (function()
			-- Restore the SENT squad as a clean array of unitId strings so the XP
			-- participant set survives a mid-expedition rejoin (not lost, not re-granted).
			local out: { string } = {}
			if type(data.squad) == "table" then
				for _, uid in ipairs(data.squad) do
					if uid ~= nil then out[#out + 1] = tostring(uid) end
				end
			end
			return out
		end)(),
	}
end

function ExploreService.ClearPlayer(playerId: string)
	state[playerId] = nil
end

return ExploreService
