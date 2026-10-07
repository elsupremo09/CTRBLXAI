--!strict
-- SoundController.lua
-- Client-side combat SFX engine. Mirrors VFXController: the server fires an
-- event, each client plays its own audio locally (NET golden rule — never
-- stream audio from the server). Reads all ids from SoundRegistry; any blank
-- slot is skipped silently, so the game is playable with zero ids filled.
--
-- Create-on-demand pattern (best-practices doc, Section 6): a Sound is created,
-- played, and Destroyed when it ends — no hoarding Sounds in SoundService.

local SoundController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local SoundRegistry = nil
local SkillData     = nil

local _regOk = pcall(function()
	SoundRegistry = require(
		ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
			:WaitForChild("Shared", 10):WaitForChild("SoundRegistry", 10)
	)
end)
if not _regOk or not SoundRegistry then
	warn("[Sound] SoundRegistry require failed — combat SFX disabled")
end

-- SkillData lives in ReplicatedStorage/Content; resolve it directly (same as VFX).
pcall(function()
	local content = ReplicatedStorage:FindFirstChild("Content")
	if content then
		local sd = content:FindFirstChild("SkillData")
		if sd then SkillData = require(sd) end
	end
end)

--------------------------------------------------
-- INTERNAL: play a sound id with throttle + concurrency cap
--------------------------------------------------
local _lastPlay = {}        -- slotKey -> os.clock() of last play
local _activeCount = {}     -- slotKey -> number of live copies

local function categoryVol(category)
	if SoundRegistry and SoundRegistry.CategoryVolume and category then
		return SoundRegistry.CategoryVolume[category] or 1.0
	end
	return 1.0
end

-- Core: play one asset id. slotKey is used for throttle/concurrency bookkeeping.
local function playId(assetId, slotKey, category, pitchRange)
	if not SoundRegistry then return nil end
	if type(assetId) ~= "string" or assetId == "" then return nil end  -- blank slot: silent

	local now = os.clock()
	local throttle = SoundRegistry.ThrottleSeconds or 0.06
	if _lastPlay[slotKey] and (now - _lastPlay[slotKey]) < throttle then
		return nil  -- too soon since the last identical sound
	end
	local maxSame = SoundRegistry.MaxConcurrentSame or 4
	if (_activeCount[slotKey] or 0) >= maxSame then
		return nil  -- already enough copies of this sound playing
	end
	_lastPlay[slotKey] = now
	_activeCount[slotKey] = (_activeCount[slotKey] or 0) + 1

	local s = Instance.new("Sound")
	s.SoundId = assetId
	s.Volume = (SoundRegistry.MasterVolume or 0.5) * categoryVol(category)
	if pitchRange then
		-- slight random pitch so repeats don't sound robotic
		local lo, hi = pitchRange[1], pitchRange[2]
		s.PlaybackSpeed = lo + math.random() * (hi - lo)
	end
	-- 2D sound: parent to SoundService so it plays globally for the local client
	-- (combat feedback shouldn't attenuate with camera distance).
	s.Parent = SoundService

	local function cleanup()
		_activeCount[slotKey] = math.max(0, (_activeCount[slotKey] or 1) - 1)
		if s and s.Parent then s:Destroy() end
	end
	s.Ended:Once(cleanup)
	-- Safety: if the id fails to load, destroy after a few seconds anyway.
	Debris:AddItem(s, 8)
	s:Play()
	return s
end

--------------------------------------------------
-- SKILL RESOLUTION (priority order, matches SoundRegistry header)
-- explosion -> element -> heal -> buff -> debuff -> physical -> default
--------------------------------------------------
local ELEMENTS = { "Fire", "Ice", "Electric", "Water", "Earth", "Holy", "Dark", "Poison" }

local function hasTag(tags, name)
	if not tags then return false end
	for _, t in ipairs(tags) do
		if t == name then return true end
	end
	return false
end

-- Returns slotName (key in SoundRegistry.Skill) for a given skillId, or nil.
function SoundController.ResolveSkillSlot(skillId)
	local def = skillId and SkillData and SkillData[skillId] or nil
	if not def then return "DefaultSkill" end
	local tags = def.tags

	-- 1) Explosion (future tag)
	if hasTag(tags, "explosion") or hasTag(tags, "Explosion") then
		return "Explosion"
	end
	-- 2) Element
	for _, el in ipairs(ELEMENTS) do
		if hasTag(tags, el) then return el end
	end
	-- 3) Heal
	if def.isHealing or hasTag(tags, "Healing") then
		return "Heal"
	end
	-- Does this skill deal direct damage?
	local isDamage = hasTag(tags, "Direct Damage") or hasTag(tags, "Physical")
	-- 4) Buff (pure buff: no damage)
	if hasTag(tags, "Buff") and not isDamage then
		return "Buff"
	end
	-- 5) Debuff (pure debuff: no damage)
	if hasTag(tags, "Debuff") and not isDamage then
		return "Debuff"
	end
	-- 6) Non-elemental damage hit (incl. Direct Damage + Debuff)
	if isDamage then
		return "PhysicalHit"
	end
	-- 7) Default
	return "DefaultSkill"
end

--------------------------------------------------
-- PUBLIC PLAY HELPERS (called by BattleVisualClient event handlers)
--------------------------------------------------

-- Skill hit: resolve the slot from tags, play it (category Hit, except Heal).
function SoundController.PlaySkill(skillId)
	if not SoundRegistry then return end
	local slot = SoundController.ResolveSkillSlot(skillId)
	local id = SoundRegistry.Skill[slot]
	local category = (slot == "Heal") and "Heal" or "Hit"
	playId(id, "Skill_" .. slot, category, {0.95, 1.05})
end

-- Basic attack hit: isProjectile picks Projectile vs Melee.
function SoundController.PlayAttack(isProjectile)
	if not SoundRegistry then return end
	if isProjectile then
		playId(SoundRegistry.Attack.Projectile, "Attack_Projectile", "Hit", {0.97, 1.03})
	else
		playId(SoundRegistry.Attack.Melee, "Attack_Melee", "Hit", {0.95, 1.05})
	end
end

function SoundController.PlayHeal()
	if not SoundRegistry then return end
	playId(SoundRegistry.Skill.Heal, "Skill_Heal", "Heal", {0.97, 1.03})
end

-- Status applied: kind is "Buff" or "Debuff" (from GameConstants STATUSES.kind).
function SoundController.PlayStatus(kind)
	if not SoundRegistry then return end
	if kind == "Debuff" then
		playId(SoundRegistry.Skill.Debuff, "Skill_Debuff", "Status")
	elseif kind == "Buff" then
		playId(SoundRegistry.Skill.Buff, "Skill_Buff", "Status")
	end
end

function SoundController.PlayMove()
	if not SoundRegistry then return end
	playId(SoundRegistry.Action.Move, "Action_Move", "Move")
end

function SoundController.PlayGuard()
	if not SoundRegistry then return end
	playId(SoundRegistry.Action.Guard, "Action_Guard", "Status")
end

function SoundController.PlayKO()
	if not SoundRegistry then return end
	playId(SoundRegistry.Action.KO, "Action_KO", "KO")
end

function SoundController.PlayTurnChime()
	if not SoundRegistry then return end
	playId(SoundRegistry.Action.TurnChime, "Action_TurnChime", "UI")
end

function SoundController.PlayUIClick()
	if not SoundRegistry then return end
	playId(SoundRegistry.Action.UIClick, "Action_UIClick", "UI")
end

-- Item used: category is the consumable's category field.
function SoundController.PlayItem(category)
	if not SoundRegistry then return end
	local slot = category
	if not (slot and SoundRegistry.Item[slot] and SoundRegistry.Item[slot] ~= "") then
		slot = "Default"
	end
	playId(SoundRegistry.Item[slot], "Item_" .. tostring(slot), "Hit")
end

--------------------------------------------------
-- CHANNEL LOOP (start on ChannelStarted, stop on ChannelEnded)
--------------------------------------------------
local _channelLoops = {}   -- unitId -> Sound

function SoundController.StartChannel(unitId)
	if not SoundRegistry then return end
	if not unitId then return end
	local id = SoundRegistry.Channel.Loop
	if type(id) ~= "string" or id == "" then return end   -- blank: silent
	-- Already looping for this unit? leave it.
	if _channelLoops[unitId] and _channelLoops[unitId].Parent then return end

	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = (SoundRegistry.MasterVolume or 0.5) * categoryVol("Channel")
	s.Parent = SoundService
	s:Play()
	_channelLoops[unitId] = s
end

function SoundController.StopChannel(unitId)
	if not unitId then return end
	local s = _channelLoops[unitId]
	if s then
		if s.Parent then s:Stop(); s:Destroy() end   -- MEM-002: Destroy, not nil
		_channelLoops[unitId] = nil
	end
end

-- Clear all channel loops (call on battle end / reset).
function SoundController.StopAllChannels()
	for uid, s in pairs(_channelLoops) do
		if s and s.Parent then s:Stop(); s:Destroy() end
		_channelLoops[uid] = nil
	end
end

return SoundController
