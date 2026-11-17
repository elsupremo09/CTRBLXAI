--!strict
-- FurnitureEnemy.lua
-- CTRBLXAI | Furniture v5 build STEP 2 (= v4 step 4, 2026-11-16): ENEMY LINES weaken enemies.
-- Rules: docs\CTRBLXAI.db guild_facilities 108 (APPROVED 6:48 / 7:02 PM), data FurnitureData.V4.Enemy.
--
-- How it works:
--   * At battle start Main calls ApplyBattleStart(units). The placed furniture's ENEMY totals
--     (FurnitureService.V4Totals().enemy + the -1 threshold lines) become a per-enemy stamp
--     unit._furnEnemy in the SAME key format as the player bonus table (unit.furnitureBonus),
--     but with negative / >1 values. FurnitureService.BonusFor returns that stamp for enemies, so
--     EquipmentService.RebuildUnitStats applies it on every rebuild for the rest of the battle and
--     every reader (StatCalcService Movement / Jump / Force / Stability, AI move candidates,
--     Displacement, item damage) sees the FINAL weakened values. The AI plans with them for free
--     (TargetingService.GetMoveCandidates -> StatCalcService.GetMovementRange).
--   * HP / MP loss is applied once to current HP / MP (not damage: no on-hit, no wake, no counter,
--     can't kill, floor 1 HP; MP floor 0).
--   * Floors: primary stat >= 1; Attack / Defense lose at most 25% of that enemy's own value;
--     Movement >= 2; HP loss <= 15% of Max HP (bosses 5%).
--   * Elites and bosses: 50% of every value (flat values round down), threshold lines ignored.
--   * Mid-battle arrivals (EnemyGenerator.SpawnReinforcement: reinforcements, woken Mimic,
--     battlefield-event enemies) get the same stamp on arrival. Summons and map objects never.
--   * Not a status: nothing to cleanse, ignores immunity. Never touches RT / CT / AP / channel.
--
-- OWNS: the per-battle enemy profile + the stamps. MUST NOT OWN: furniture totals (FurnitureService),
-- stat formulas (EquipmentService / StatCalcService).

local Game = script.Parent
local EquipmentService = require(Game:WaitForChild("EquipmentService"))
local StatCalcService = require(Game:WaitForChild("StatCalcService"))
local FurnitureService = require(Game:WaitForChild("FurnitureService"))
local EnemyGenerator = require(Game:WaitForChild("EnemyGenerator"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FurnitureData = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("FurnitureData"))
local V4: any = FurnitureData.V4

local FurnitureEnemy = {}

local PRIMARY = { "STR", "AGI", "DEX", "INT", "VIT", "LUK" }
-- threshold kind -> bonus-table key + the lowest final value it may leave
local THRESHOLD: { [string]: { key: string, floor: number } } = {
	movement = { key = "movementRange", floor = V4.Enemy.Floors.movementMin }, -- row 108 floor (2), read from data
	jump = { key = "jump", floor = 0 },
	force = { key = "force", floor = 0 },
	stability = { key = "stability", floor = 0 },
}

-- Active profile for THIS battle (nil = no enemy lines). Set at every battle start.
local _profile: { enemy: { [string]: number }, threshold: { [string]: number } }? = nil

local function isBig(u: any): (boolean, boolean)
	local boss = u.isBoss == true or u.enemyType == "Boss" or u.aiRole == "Boss"
	local elite = u.enemyType == "Elite" or u.aiRole == "Elite"
	return boss or elite, boss
end

local function pctOf(maxV: number, pct: number): number
	return math.floor(maxV * pct)
end

--- Builds the profile from the current furniture totals. nil when no enemy line applies.
local function buildProfile(): any
	local okT, t = pcall(FurnitureService.V4Totals)
	if not okT or type(t) ~= "table" then return nil end
	local enemy: { [string]: number } = {}
	for k, v in (t.enemy or {}) :: any do
		if type(v) == "number" and v > 0 then enemy[k] = v end
	end
	local thr: { [string]: number } = {}
	for k, v in (t.threshold or {}) :: any do
		if type(v) == "number" and v < 0 and THRESHOLD[k] then thr[k] = v end
	end
	if next(enemy) == nil and next(thr) == nil then return nil end
	return { enemy = enemy, threshold = thr }
end

--- Stamps one enemy unit. Returns the HP it lost (for the log).
local function applyUnit(u: any): number
	local p = _profile
	if not p or type(u) ~= "table" or u.side ~= "Enemy" or u.isSummon then return 0 end
	if u._furnEnemyApplied then return 0 end
	local big, boss = isBig(u)
	local mult = if big then V4.Enemy.EliteBossMult else 1
	local E = p.enemy
	local fl = V4.Enemy.Floors
	local function flat(k: string): number
		local v = E[k]
		if not v then return 0 end
		return math.floor(v * mult)
	end
	local function frac(k: string): number
		local v = E[k]
		if not v then return 0 end
		return v * mult / 100
	end
	-- Readings BEFORE the stamp (nothing stamped yet; stats as generated).
	local eff = u.effectiveStats or {}
	local fb: { [string]: number } = {}
	for _, s in PRIMARY do
		local loss = math.min(flat(s), math.max(0, (tonumber(eff[s]) or 0) - fl.primaryMin))
		if loss > 0 then fb[s] = -loss end
	end
	local atkLoss = math.min(flat("attack"), pctOf(tonumber(u.weaponDamage) or 0, fl.attackDefenseMaxLossPct))
	if atkLoss > 0 then fb.attack = -atkLoss end
	local defLoss = math.min(flat("defense"), pctOf(tonumber(u.armorDefense) or 0, fl.attackDefenseMaxLossPct))
	if defLoss > 0 then fb.defense = -defLoss end
	local function put(k: string, v: number) if math.abs(v) > 1e-9 then fb[k] = v end end
	put("precision", -frac("precision"))
	put("evasiveness", -frac("evasion"))
	put("skillPotency", -frac("skillPotency"))
	put("itemDamage", -frac("itemDamage"))
	if E.healingOutput then fb.healingOutput = 1 - frac("healingOutput") end
	if E.debuffResist then fb.debuffResist = 1 + frac("debuffResist") end -- debuffs land harder
	if E.collisionResist then fb.collision = 1 + frac("collisionResist") end -- collision taken
	if E.fallResist then fb.fallTaken = 1 + frac("fallResist") end
	if E.collisionDamage then fb.collisionDealt = 1 - frac("collisionDamage") end
	if not big then -- Elites / bosses ignore threshold lines (row 108)
		for k, v in p.threshold do
			local th = THRESHOLD[k]
			local cur = 0
			if k == "movement" then cur = StatCalcService.GetMovementRange(u, "battle")
			elseif k == "jump" then cur = StatCalcService.GetJump(u, "battle")
			elseif k == "force" then cur = StatCalcService.GetForce(u, "battle")
			elseif k == "stability" then cur = StatCalcService.GetStability(u, "battle") end
			local step = math.max(v, th.floor - cur) -- v is -1; never below the floor
			if step < 0 then fb[th.key] = step end
		end
	end
	u._furnEnemyApplied = true
	if next(fb) ~= nil then
		local hp, mp = u.currentHp, u.currentMp
		u._furnEnemy = fb
		EquipmentService.RebuildUnitStats(u)
		-- A -VIT / -INT line can lower Max HP / Max MP through the rebuild: keep current HP / MP, clamped to the new max.
		if hp then u.currentHp = math.min(hp, u.maxHp or hp) end
		if mp then u.currentMp = math.min(mp, u.maxMp or mp) end
	end
	-- HP / MP loss at battle start (not damage).
	local lost = 0
	local hpLoss = flat("hpLoss")
	if hpLoss > 0 and u.isAlive ~= false and (u.currentHp or 0) > 1 then
		local cap = pctOf(u.maxHp or 0, if boss then fl.bossHpLossMaxPctOfMax else fl.hpLossMaxPctOfMax)
		lost = math.max(0, math.min(hpLoss, cap, (u.currentHp or 0) - fl.hpMin))
		u.currentHp = (u.currentHp or 0) - lost
	end
	local mpLoss = flat("mpLoss")
	if mpLoss > 0 and u.currentMp then u.currentMp = math.max(fl.mpMin, u.currentMp - mpLoss) end
	return lost
end

-- No decimals in player text (loadout_ui_spec 129, user 2026-11-17 1:50 PM): flat values whole,
-- percent values keep one decimal only for a half step.
local function fmt(v: number, pct: boolean?): string
	if not pct then return tostring(math.round(v)) end
	local r = math.round(v * 2) / 2
	if r == math.floor(r) then return tostring(math.floor(r)) end
	return string.format("%.1f", r)
end

--- Short summary of the normal-enemy effect, for "Guild furniture: enemies {summary}".
local function summary(p: any): string
	local E, parts = p.enemy, {}
	local function add(s: string) table.insert(parts, s) end
	if E.hpLoss then add("-" .. fmt(E.hpLoss) .. " HP") end
	if E.mpLoss then add("-" .. fmt(E.mpLoss) .. " MP") end
	for _, s in PRIMARY do if E[s] then add("-" .. fmt(E[s]) .. " " .. s) end end
	if E.attack then add("-" .. fmt(E.attack) .. " Attack") end
	if E.defense then add("-" .. fmt(E.defense) .. " Defense") end
	local NAMES = { precision = "Precision", evasion = "Evasion", skillPotency = "Skill Potency",
		healingOutput = "Healing Output", debuffResist = "Debuff Resistance", collisionResist = "Collision Resistance",
		fallResist = "Fall Resistance", collisionDamage = "Collision Damage", itemDamage = "Item Damage" }
	for _, k in { "precision", "evasion", "skillPotency", "healingOutput", "debuffResist", "collisionResist",
		"fallResist", "collisionDamage", "itemDamage" } do
		if E[k] then add("-" .. fmt(E[k], true) .. "% " .. NAMES[k]) end
	end
	local TN = { movement = "Movement", jump = "Jump", force = "Force", stability = "Stability" }
	for _, k in { "movement", "jump", "force", "stability" } do
		if p.threshold[k] then add("-1 " .. TN[k]) end
	end
	return table.concat(parts, ", ")
end

--- Battle start (Main, before the dungeon relic stamps). Returns the log summary or nil.
function FurnitureEnemy.ApplyBattleStart(units: { any }): string?
	_profile = buildProfile()
	for _, u in ipairs(units or {}) do
		if type(u) == "table" then u._furnEnemy = nil; u._furnEnemyApplied = nil end
	end
	local p = _profile
	if not p then return nil end
	local n, hpTotal = 0, 0
	for _, u in ipairs(units or {}) do
		if type(u) == "table" and u.side == "Enemy" and not u.isSummon then
			local okA, lost = pcall(applyUnit, u)
			if okA then n += 1; hpTotal += (lost :: number) else warn("[FurnitureEnemy] apply failed: " .. tostring(lost)) end
		end
	end
	local s = summary(p)
	print(string.format("[FurnitureEnemy] Enemy lines applied | %d enemies | HP lost total %d | %s", n, hpTotal, s))
	return if s ~= "" then s else nil
end

--- Mid-battle arrival (EnemyGenerator.SpawnReinforcement hook).
function FurnitureEnemy.ApplyArrival(u: any)
	if not _profile then return end
	local okA, err = pcall(applyUnit, u)
	if not okA then warn("[FurnitureEnemy] arrival failed: " .. tostring(err)) end
end

--- Test / dev: the active profile (read-only copy semantics not enforced).
function FurnitureEnemy.Profile(): any
	return _profile
end

if EnemyGenerator.SetArrivalHook then EnemyGenerator.SetArrivalHook(FurnitureEnemy.ApplyArrival) end

return FurnitureEnemy
