--[[
	VFXController.lua
	Central visual effects controller for CTRBLXAI.
	Handles: particle bursts, attack beams/trails, unit highlights, post-processing.
	Place: ReplicatedStorage/CTRBLXAI/Shared/
	Require from client scripts only.
]]

local VFXController = {}

local Lighting     = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

--------------------------------------------------
-- TEXTURES (built-in Roblox assets)
--------------------------------------------------
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

--------------------------------------------------
-- VFX FOLDER (workspace container for temp Parts)
--------------------------------------------------
local vfxFolder = Instance.new("Folder")
vfxFolder.Name = "VFX"
vfxFolder.Parent = workspace

--------------------------------------------------
-- PRE-MADE VFX ASSETS (ReplicatedStorage/CTRBLXAI/VFX) + REGISTRY
-- The asset LIBRARY (ParticleEmitters/Models authored in Studio) lives in
-- ReplicatedStorage so the client can clone it (NET-001: client owns visuals).
-- vfxAssetFolder is resolved lazily so require order doesn't matter.
--------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vfxAssetFolder = nil  -- resolved on first use
local VFXRegistry = nil
local SkillData = nil
local _regOk = pcall(function()
	VFXRegistry = require(
		ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
			:WaitForChild("Shared", 10):WaitForChild("VFXRegistry", 10)
	)
end)
if not _regOk then warn("[VFX] VFXRegistry require failed — pre-made VFX disabled") end
-- SkillData lives in ReplicatedStorage/Content; resolve it directly.
pcall(function()
	local content = ReplicatedStorage:FindFirstChild("Content")
	if content then
		local sd = content:FindFirstChild("SkillData")
		if sd then SkillData = require(sd) end
	end
end)

local function getAssetFolder()
	if vfxAssetFolder and vfxAssetFolder.Parent then return vfxAssetFolder end
	local ct = ReplicatedStorage:FindFirstChild("CTRBLXAI")
	if ct then vfxAssetFolder = ct:FindFirstChild("VFX") end
	if not vfxAssetFolder then
		-- Fallback: a top-level ReplicatedStorage/VFX folder.
		vfxAssetFolder = ReplicatedStorage:FindFirstChild("VFX")
	end
	return vfxAssetFolder
end

--------------------------------------------------
-- HIGHLIGHT STATE
--------------------------------------------------
local activeHL  = nil    -- { unitId, instance } (one at a time)
local persistHL = {}     -- unitId -> Highlight  (KO, guard, channel)

--------------------------------------------------
-- COLOR MAPS
--------------------------------------------------
local ELEMENT_COLOR = {
	Fire     = Color3.fromRGB(255, 120, 30),
	Ice      = Color3.fromRGB(100, 200, 255),
	Electric = Color3.fromRGB(255, 255, 100),
	Holy     = Color3.fromRGB(255, 255, 200),
	Dark     = Color3.fromRGB(100, 40, 150),
	Poison   = Color3.fromRGB(100, 200, 50),
	Physical = Color3.fromRGB(255, 220, 180),
}

local STATUS_COLOR = {
	Burn         = Color3.fromRGB(255, 100, 20),
	Poison       = Color3.fromRGB(100, 200, 50),
	Venom        = Color3.fromRGB(80, 180, 40),
	Bleed        = Color3.fromRGB(200, 30, 30),
	Wounded      = Color3.fromRGB(180, 40, 40),
	Freeze       = Color3.fromRGB(100, 200, 255),
	Frozen       = Color3.fromRGB(100, 200, 255),
	Stun         = Color3.fromRGB(255, 255, 100),
	Silence      = Color3.fromRGB(150, 100, 200),
	Mute         = Color3.fromRGB(150, 100, 200),
	Slow         = Color3.fromRGB(100, 100, 180),
	Blind        = Color3.fromRGB(60, 60, 60),
	Confuse      = Color3.fromRGB(255, 150, 255),
	Sleep        = Color3.fromRGB(100, 100, 200),
	Petrify      = Color3.fromRGB(150, 150, 130),
	Cursed       = Color3.fromRGB(80, 0, 80),
	Weakened     = Color3.fromRGB(180, 120, 80),
	Pinned       = Color3.fromRGB(150, 100, 60),
	Crippled     = Color3.fromRGB(120, 80, 60),
	Disarmed     = Color3.fromRGB(160, 140, 100),
	Haste        = Color3.fromRGB(100, 255, 200),
	Frenzy       = Color3.fromRGB(255, 50, 50),
	Regeneration = Color3.fromRGB(80, 255, 120),
	Blessed      = Color3.fromRGB(255, 255, 180),
	Guard        = Color3.fromRGB(100, 180, 255),
	Wet          = Color3.fromRGB(80, 130, 200),
	Drowning     = Color3.fromRGB(40, 80, 160),
}

--------------------------------------------------
-- BIOME ATMOSPHERE PRESETS
--------------------------------------------------
local BIOME_ATMO = {
	Plains = {
		Density = 0.2,  Offset = 0.1,  Glare = 0.3,  Haze = 1,
		Color = Color3.fromRGB(200, 210, 220),
	},
	Forest = {
		Density = 0.35, Offset = 0.15, Glare = 0.1,  Haze = 2,
		Color = Color3.fromRGB(170, 200, 160),
	},
	Desert = {
		Density = 0.25, Offset = 0.2,  Glare = 0.8,  Haze = 3,
		Color = Color3.fromRGB(230, 210, 170),
	},
	Swamp = {
		Density = 0.5,  Offset = 0.2,  Glare = 0.05, Haze = 4,
		Color = Color3.fromRGB(140, 160, 130),
	},
	Highlands = {
		Density = 0.15, Offset = 0.05, Glare = 0.4,  Haze = 0.5,
		Color = Color3.fromRGB(210, 220, 240),
	},
	Tundra = {
		Density = 0.3,  Offset = 0.1,  Glare = 0.6,  Haze = 2,
		Color = Color3.fromRGB(220, 230, 240),
	},
	Volcano = {
		Density = 0.4,  Offset = 0.25, Glare = 0.2,  Haze = 5,
		Color = Color3.fromRGB(200, 140, 100),
	},
	Cave = {
		Density = 0.6,  Offset = 0.3,  Glare = 0,    Haze = 0,
		Color = Color3.fromRGB(80, 80, 100),
	},
	Ruins = {
		Density = 0.3,  Offset = 0.15, Glare = 0.2,  Haze = 2,
		Color = Color3.fromRGB(180, 180, 170),
	},
	Castle = {
		Density = 0.2,  Offset = 0.1,  Glare = 0.15, Haze = 1,
		Color = Color3.fromRGB(190, 190, 200),
	},
	Corrupted = {
		Density = 0.45, Offset = 0.25, Glare = 0.1,  Haze = 3,
		Color = Color3.fromRGB(140, 100, 160),
	},
}

--------------------------------------------------
-- UTILITIES
--------------------------------------------------

local function makeAnchor(pos, lifetime)
	local p = Instance.new("Part")
	p.Name = "VFX_Anchor"
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.Position = pos
	p.Anchored = true
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = vfxFolder
	Debris:AddItem(p, lifetime or 3)
	return p
end

local function elemColor(element)
	return ELEMENT_COLOR[element] or ELEMENT_COLOR.Physical
end

local function statColor(statusId)
	return STATUS_COLOR[statusId] or Color3.fromRGB(200, 200, 200)
end

local function mkHighlight(basePart, outColor, outTrans, fillColor, fillTrans)
	local hl = Instance.new("Highlight")
	hl.Name = "VFX_HL"
	hl.Adornee = basePart
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.OutlineColor = outColor
	hl.OutlineTransparency = outTrans
	hl.FillColor = fillColor
	hl.FillTransparency = fillTrans
	hl.Parent = basePart
	return hl
end

--------------------------------------------------
-- HIGHLIGHT STYLE PRESETS
--------------------------------------------------
local HL_STYLE = {
	active  = { out = Color3.fromRGB(255, 200, 80),  outT = 0,   fill = Color3.fromRGB(255, 220, 100), fillT = 0.85 },
	target  = { out = Color3.fromRGB(255, 60, 60),   outT = 0,   fill = Color3.fromRGB(255, 80, 80),   fillT = 0.80 },
	ko      = { out = Color3.fromRGB(80, 80, 80),    outT = 0.3, fill = Color3.fromRGB(40, 40, 40),    fillT = 0.60 },
	channel = { out = Color3.fromRGB(100, 150, 255),  outT = 0,   fill = Color3.fromRGB(120, 170, 255), fillT = 0.75 },
	guard   = { out = Color3.fromRGB(100, 180, 255),  outT = 0,   fill = Color3.fromRGB(100, 200, 255), fillT = 0.80 },
}

--==================================================
-- 1. POST-PROCESSING & ATMOSPHERE
--==================================================

--------------------------------------------------
-- DAY/NIGHT SKY CYCLE (CT-driven; client visual only, NET-001)
--------------------------------------------------
-- The battle clock (CT) drives Lighting.ClockTime so the sky tracks in-world time.
-- The server only broadcasts CT; it never touches Lighting (NET-001: client owns
-- visuals). Mapping matches the server Dawn/Day/Dusk/Night phase cycle:
--   one phase = 1000 CT = 6 hours; full day = 4000 CT = 24h; CT 0 = 03:00 (Dawn start).
--   CT 333->05:00, 666->07:00, 1000->09:00 (Day), 2000->15:00 (Dusk), 3000->21:00 (Night).
local CLOCK_CYCLE_CT   = 4000   -- CT for one full 24h sky revolution
local CLOCK_START_HOUR = 3      -- CT 0 maps to 03:00
local CLOCK_GLIDE_TIME = 1.5    -- seconds to glide the sun to a new clock reading
local CLOCK_SNAP_FWD   = 18     -- a reading >18h "forward" = clock reset (new battle) -> snap
-- Night-readability floor: this is a mobile tactics board, so even midnight must stay
-- legible. Flooring Outdoor/Ambient keeps the darkest night readable (tunable).
local DAY_OUTDOOR_AMBIENT   = Color3.fromRGB(90, 92, 110)   -- unchanged daytime floor
local DAY_AMBIENT           = Color3.fromRGB(70, 72, 85)
local NIGHT_OUTDOOR_AMBIENT = Color3.fromRGB(125, 128, 150) -- brighter night (was 90,92,110)
local NIGHT_AMBIENT         = Color3.fromRGB(104, 107, 125) -- brighter night (was 70,72,85)

local function clockHourForCt(ct: number): number
	local c = ct % CLOCK_CYCLE_CT
	return (CLOCK_START_HOUR + (c / CLOCK_CYCLE_CT) * 24) % 24
end

-- Blend ambient between the day floor (sun up) and the brighter night floor (sun down)
-- from the sun's height at `clockTime`. dayWeight reaches 1 while the sun is modestly up,
-- so the whole Day phase keeps the exact DAY_* values (daytime is never brightened), and
-- falls to 0 at/below the horizon, lifting to NIGHT_* across dusk/night/dawn.
local function updateAmbientForClock(clockTime: number)
	local sunHeight = math.sin((clockTime - 6) / 12 * math.pi) -- +1 noon, 0 at 06/18, <0 at night
	local dayWeight = math.clamp(sunHeight / 0.25, 0, 1)
	Lighting.OutdoorAmbient = NIGHT_OUTDOOR_AMBIENT:Lerp(DAY_OUTDOOR_AMBIENT, dayWeight)
	Lighting.Ambient        = NIGHT_AMBIENT:Lerp(DAY_AMBIENT, dayWeight)
end

-- We glide a NumberValue monotonically FORWARD and mirror it to Lighting.ClockTime
-- via % 24, so the sun never runs backward across the midnight wrap (23:xx -> 00:xx).
local _clockProxy: NumberValue? = nil
local _clockConn: RBXScriptConnection? = nil
local _clockTween: Tween? = nil
local _clockAbs = CLOCK_START_HOUR  -- absolute (unwrapped) hours the proxy currently holds

local function ensureClockProxy()
	if _clockProxy then return end
	local nv = Instance.new("NumberValue")
	nv.Name = "VFXClockProxy"
	nv.Value = _clockAbs
	-- Left unparented on purpose: client-only, tweenable, no DataModel pollution.
	_clockConn = nv:GetPropertyChangedSignal("Value"):Connect(function()
		local ct = nv.Value % 24
		Lighting.ClockTime = ct
		updateAmbientForClock(ct)
	end)
	_clockProxy = nv
end

-- Snap the sky instantly to the clock for `ct` (no glide). Used at battle start.
local function snapClock(ct: number)
	ensureClockProxy()
	if _clockTween then _clockTween:Cancel(); _clockTween = nil end
	_clockAbs = clockHourForCt(ct)
	_clockProxy.Value = _clockAbs
	Lighting.ClockTime = _clockAbs % 24  -- force even if Value was unchanged
	updateAmbientForClock(_clockAbs % 24)
end

-- Glide the sky toward the clock for `ct` over CLOCK_GLIDE_TIME. Forward-only.
function VFXController.SetBattleClock(ct: number)
	if typeof(ct) ~= "number" then return end
	ensureClockProxy()
	local targetHour = clockHourForCt(ct)
	local forward = (targetHour - (_clockAbs % 24)) % 24  -- 0..24 forward distance
	if _clockTween then _clockTween:Cancel(); _clockTween = nil end
	if forward < 0.01 then
		return                        -- already there; skip a zero-length tween
	elseif forward > CLOCK_SNAP_FWD then
		_clockAbs = targetHour         -- clock went backward (new battle / reset) -> snap
		_clockProxy.Value = _clockAbs
		Lighting.ClockTime = _clockAbs % 24
		return
	end
	_clockAbs = _clockAbs + forward    -- keep the proxy monotonic so % 24 wraps cleanly
	_clockTween = TweenService:Create(_clockProxy,
		TweenInfo.new(CLOCK_GLIDE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Value = _clockAbs })
	_clockTween:Play()
end

function VFXController.Init(biome)
	-- Bloom: subtle glow on Neon tile highlights and skill effects
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local b = Instance.new("BloomEffect")
		b.Intensity = 0.7
		b.Size = 28
		b.Threshold = 0.9  -- raised 0.8->0.9 (Oct 4 2026) to stop bright Ice/Sand terrain textures blooming; may dim blue move-highlight glow (acceptable trade-off per user)
		b.Parent = Lighting
	end

	-- Color Correction: warm medieval palette
	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Brightness = 0.02
		cc.Contrast = 0.05
		cc.Saturation = 0.1
		cc.TintColor = Color3.fromRGB(255, 248, 240)
		cc.Parent = Lighting
	end

	-- Sun Rays: atmospheric god rays
	if not Lighting:FindFirstChildOfClass("SunRaysEffect") then
		local sr = Instance.new("SunRaysEffect")
		sr.Intensity = 0.06
		sr.Spread = 0.8
		sr.Parent = Lighting
	end

	-- Atmosphere: biome-specific fog, haze, aerial perspective
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmo then
		atmo = Instance.new("Atmosphere")
		atmo.Parent = Lighting
	end
	local preset = BIOME_ATMO[biome] or BIOME_ATMO.Plains
	atmo.Density = preset.Density
	atmo.Offset  = preset.Offset
	atmo.Glare   = preset.Glare
	atmo.Haze    = preset.Haze
	atmo.Color   = preset.Color
	atmo.Decay   = Color3.fromRGB(180, 180, 190)

	-- Day/night sky: snap the sky + ambient to the battle's starting clock (Dawn / 03:00).
	-- Ambient is clock-driven now (updateAmbientForClock), so snapClock sets it — not here.
	-- SetBattleClock then glides both the sun and the ambient as CT climbs.
	snapClock(0)

	print(string.format("[VFX] Init: biome=%s", tostring(biome)))
end

--==================================================
-- 2. PARTICLE EFFECTS
--==================================================

--- Burst of sparks at the damage target position.
function VFXController.DamageImpact(position, element)
	local color = elemColor(element)
	local anchor = makeAnchor(position, 2)

	local e = Instance.new("ParticleEmitter")
	e.Texture        = SPARK
	e.Color          = ColorSequence.new(color, Color3.fromRGB(60, 30, 10))
	e.Size           = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency   = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime       = NumberRange.new(0.2, 0.5)
	e.Speed          = NumberRange.new(8, 16)
	e.SpreadAngle    = Vector2.new(180, 180)
	e.Drag           = 6
	e.Rate           = 0
	e.LightEmission  = 0.8
	e.LightInfluence = 0.2
	e.Parent         = anchor

	e:Emit(25)
end

--- Rising green particles for healing.
function VFXController.HealEffect(position)
	local anchor = makeAnchor(position, 3)

	local e = Instance.new("ParticleEmitter")
	e.Texture            = SPARK
	e.Color              = ColorSequence.new(Color3.fromRGB(80, 255, 130), Color3.fromRGB(200, 255, 200))
	e.Size               = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency       = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime           = NumberRange.new(0.6, 1.0)
	e.Speed              = NumberRange.new(2, 5)
	e.EmissionDirection  = Enum.NormalId.Top
	e.SpreadAngle        = Vector2.new(25, 25)
	e.Drag               = 1
	e.Rate               = 0
	e.LightEmission      = 0.6
	e.LightInfluence     = 0.3
	e.Parent             = anchor

	e:Emit(18)
end

--- Brief colored burst for status application.
function VFXController.StatusBurst(position, statusId)
	local color = statColor(statusId)
	local anchor = makeAnchor(position, 2)

	local e = Instance.new("ParticleEmitter")
	e.Texture        = SPARK
	e.Color          = ColorSequence.new(color)
	e.Size           = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency   = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime       = NumberRange.new(0.3, 0.6)
	e.Speed          = NumberRange.new(4, 8)
	e.SpreadAngle    = Vector2.new(120, 120)
	e.Drag           = 4
	e.Rate           = 0
	e.LightEmission  = 0.5
	e.LightInfluence = 0.3
	e.Parent         = anchor

	e:Emit(12)
end

--- Dark smoke puff for unit defeat.
function VFXController.KOEffect(position)
	local anchor = makeAnchor(position, 3)

	local e = Instance.new("ParticleEmitter")
	e.Texture            = SMOKE
	e.Color              = ColorSequence.new(Color3.fromRGB(40, 40, 50), Color3.fromRGB(80, 80, 90))
	e.Size               = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 1.2),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	e.Transparency       = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime           = NumberRange.new(0.5, 1.0)
	e.Speed              = NumberRange.new(2, 5)
	e.EmissionDirection  = Enum.NormalId.Top
	e.SpreadAngle        = Vector2.new(60, 60)
	e.Drag               = 2
	e.Rate               = 0
	e.RotSpeed           = NumberRange.new(-60, 60)
	e.Rotation           = NumberRange.new(0, 360)
	e.LightEmission      = 0
	e.LightInfluence     = 1
	e.Parent             = anchor

	e:Emit(10)
end

--- DOT tick damage (smaller, subtler burst).
function VFXController.DotTick(position, statusId)
	local color = statColor(statusId)
	local anchor = makeAnchor(position, 2)

	local e = Instance.new("ParticleEmitter")
	e.Texture        = SPARK
	e.Color          = ColorSequence.new(color)
	e.Size           = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency   = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime       = NumberRange.new(0.2, 0.4)
	e.Speed          = NumberRange.new(3, 6)
	e.SpreadAngle    = Vector2.new(90, 90)
	e.Drag           = 5
	e.Rate           = 0
	e.LightEmission  = 0.4
	e.LightInfluence = 0.4
	e.Parent         = anchor

	e:Emit(8)
end

--==================================================
-- 3. UNIT HIGHLIGHTS
--==================================================

--- Gold outline on the active (current-turn) unit.
function VFXController.SetActiveUnit(unitId, basePart)
	-- Clear previous active highlight
	if activeHL then
		pcall(function() activeHL.instance:Destroy() end)
		activeHL = nil
	end
	if not basePart then return end
	local s = HL_STYLE.active
	local hl = mkHighlight(basePart, s.out, s.outT, s.fill, s.fillT)
	activeHL = { unitId = unitId, instance = hl }
end

--- Persistent highlight (target flash, KO, guard, channel).
function VFXController.SetPersistHighlight(unitId, basePart, style)
	local s = HL_STYLE[style]
	if not s or not basePart then return end
	if persistHL[unitId] then
		pcall(function() persistHL[unitId]:Destroy() end)
		persistHL[unitId] = nil
	end
	persistHL[unitId] = mkHighlight(basePart, s.out, s.outT, s.fill, s.fillT)
end

--- Clear a specific unit's persistent highlight.
function VFXController.ClearHighlight(unitId)
	if persistHL[unitId] then
		pcall(function() persistHL[unitId]:Destroy() end)
		persistHL[unitId] = nil
	end
end

--- Clear everything (battle start / battle end reset).
function VFXController.ClearAllHighlights()
	if activeHL then
		pcall(function() activeHL.instance:Destroy() end)
		activeHL = nil
	end
	for uid, hl in pairs(persistHL) do
		pcall(function() hl:Destroy() end)
	end
	persistHL = {}
end

--==================================================
-- 4. BEAM & TRAIL ATTACKS
--==================================================

--- Flash beam for ranged attacks (crossbow bolt, spell, etc.).
--- Appears instantly between caster and target, then fades.
function VFXController.RangedBeam(fromPos, toPos, element)
	local color = elemColor(element)

	local src = makeAnchor(fromPos + Vector3.new(0, 1.5, 0), 2)
	local srcAtt = Instance.new("Attachment"); srcAtt.Parent = src

	local tgt = makeAnchor(toPos + Vector3.new(0, 1.5, 0), 2)
	local tgtAtt = Instance.new("Attachment"); tgtAtt.Parent = tgt

	local beam = Instance.new("Beam")
	beam.Attachment0    = srcAtt
	beam.Attachment1    = tgtAtt
	beam.Color          = ColorSequence.new(color)
	beam.Transparency   = NumberSequence.new(0.1)
	beam.Width0         = 0.6
	beam.Width1         = 0.3
	beam.LightEmission  = 1
	beam.LightInfluence = 0
	beam.FaceCamera     = true
	beam.Segments       = 1
	beam.Parent         = src

	-- Fade out: thin the beam to zero width
	task.delay(0.15, function()
		local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(beam, info, { Width0 = 0, Width1 = 0 }):Play()
	end)
end

--- Melee slash: small glowing Part with Trail flies from attacker to target.
function VFXController.MeleeSlash(fromPos, toPos, element)
	local color = elemColor(element)

	local proj = Instance.new("Part")
	proj.Name         = "VFX_Slash"
	proj.Size         = Vector3.new(0.3, 0.3, 0.3)
	proj.Shape        = Enum.PartType.Ball
	proj.Material     = Enum.Material.Neon
	proj.Color        = color
	proj.Anchored     = true
	proj.CanCollide   = false
	proj.CanQuery     = false
	proj.CanTouch     = false
	proj.CastShadow   = false
	proj.Transparency = 0.2
	proj.Position     = fromPos + Vector3.new(0, 1.5, 0)
	proj.Parent       = vfxFolder

	-- Attachments for Trail (vertical offset = trail width)
	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0.4, 0)
	att0.Parent = proj

	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, -0.4, 0)
	att1.Parent = proj

	local trail = Instance.new("Trail")
	trail.Attachment0    = att0
	trail.Attachment1    = att1
	trail.Color          = ColorSequence.new(color, Color3.new(1, 1, 1))
	trail.Transparency   = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime       = 0.2
	trail.MinLength      = 0.05
	trail.LightEmission  = 0.8
	trail.LightInfluence = 0.2
	trail.FaceCamera     = true
	trail.WidthScale     = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	trail.Parent = proj

	-- Tween from source to target
	local targetPos = toPos + Vector3.new(0, 1.5, 0)
	local dist = (targetPos - proj.Position).Magnitude
	local dur = math.clamp(dist / 30, 0.1, 0.3)

	local tweenInfo = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(proj, tweenInfo, { Position = targetPos }):Play()

	Debris:AddItem(proj, 2)
end

--------------------------------------------------
-- PRE-MADE ASSET PLAYBACK
-- PlayAsset clones a named asset from the VFX library, positions it at a world
-- point, plays it (enabling any ParticleEmitters), and auto-cleans up. Handles
-- both ParticleEmitter-bearing assets and Model assets. NET-004 (props before
-- parent), MEM-002 (Destroy), AP-016 (client-side particles).
--------------------------------------------------

-- Collect every ParticleEmitter in an instance tree.
local function collectEmitters(root)
	local out = {}
	if root:IsA("ParticleEmitter") then table.insert(out, root) end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ParticleEmitter") then table.insert(out, d) end
	end
	return out
end

-- Anchor a template at a world position. Returns the parented clone (or nil).
local function spawnAsset(assetName, position, lifetime)
	if type(assetName) ~= "string" or assetName == "" then return nil end
	local folder = getAssetFolder()
	if not folder then return nil end
	local template = folder:FindFirstChild(assetName)
	if not template then
		-- Graceful miss: caller keeps its programmatic fallback.
		return nil
	end
	lifetime = lifetime or 2.0

	local clone = template:Clone()

	-- Position: Model via PivotTo; single BasePart via CFrame; ParticleEmitter
	-- needs a holder Part (emitters can't live bare in workspace usefully).
	if clone:IsA("Model") then
		clone.Parent = vfxFolder
		pcall(function() clone:PivotTo(CFrame.new(position)) end)
	elseif clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.CFrame = CFrame.new(position)
		clone.Parent = vfxFolder
	elseif clone:IsA("ParticleEmitter") or clone:IsA("Attachment") then
		local holder = Instance.new("Part")
		holder.Name = "VFX_" .. assetName
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(1, 1, 1)
		holder.CFrame = CFrame.new(position)
		clone.Parent = holder  -- before holder is parented (NET-004)
		holder.Parent = vfxFolder
		clone = holder
	else
		clone.Parent = vfxFolder
	end

	-- Emit: enable emitters; one-shot a burst so short effects actually show.
	local emitters = collectEmitters(clone)
	for _, em in ipairs(emitters) do
		em.Enabled = true
	end
	-- Stop steady emission partway so it fades before cleanup (avoids a hard cut).
	task.delay(math.max(0.1, lifetime * 0.5), function()
		for _, em in ipairs(emitters) do
			if em and em.Parent then em.Enabled = false end
		end
	end)

	Debris:AddItem(clone, lifetime)  -- MEM-002 equivalent: scheduled Destroy
	return clone
end

-- Public: play a named asset at a position (returns clone or nil on miss).
function VFXController.PlayAsset(assetName, position, lifetime)
	return spawnAsset(assetName, position, lifetime)
end

-- Resolve the VFX asset name for a skill, using the registry + SkillData tags.
-- Order: BySkillId → ByElement(tag) → ByProperty(properties) → DefaultSkill.
function VFXController.ResolveSkill(skillId)
	if not VFXRegistry then return nil end
	if skillId and VFXRegistry.BySkillId[skillId] then
		return VFXRegistry.BySkillId[skillId]
	end
	local def = skillId and SkillData and SkillData[skillId] or nil
	if def then
		if def.tags then
			for _, tag in ipairs(def.tags) do
				if VFXRegistry.ByElement[tag] then return VFXRegistry.ByElement[tag] end
			end
		end
		if def.properties then
			local props = string.lower(tostring(def.properties))
			for key, asset in pairs(VFXRegistry.ByProperty) do
				if string.find(props, key, 1, true) then return asset end
			end
		end
	end
	return VFXRegistry.DefaultSkill
end

-- Resolve the VFX asset name for a status id.
function VFXController.ResolveStatus(statusId)
	if not VFXRegistry or not statusId then return nil end
	return VFXRegistry.ByStatus[statusId]
end

-- Expose the registry so callers can read Melee/Ranged/KO/etc. fallbacks.
function VFXController.GetRegistry()
	return VFXRegistry
end

--------------------------------------------------
-- PERSISTENT WATERFALL SPLASH VFX
-- Unlike PlayAsset (one-shot, auto-destroys), waterfall splashes must run
-- continuously at each waterfall base for the whole battle. We clone the named
-- asset, enable its emitters, and LEAVE it parented until the map changes.
-- Keyed by "tx,ty" so a tile is never double-spawned; cleared on map regen.
--------------------------------------------------
local waterfallSplashes = {}  -- "tx,ty" -> Instance

-- Spawn (or reuse) a persistent splash at a world position for tile (tx,ty).
function VFXController.AddWaterfallSplash(tx, ty, assetName, position)
	if type(assetName) ~= "string" or assetName == "" then return nil end
	local key = tostring(tx) .. "," .. tostring(ty)
	if waterfallSplashes[key] and waterfallSplashes[key].Parent then
		return waterfallSplashes[key]  -- already present
	end
	local folder = getAssetFolder()
	if not folder then return nil end
	local template = folder:FindFirstChild(assetName)
	if not template then return nil end  -- graceful miss (no art) — no error

	local clone = template:Clone()
	if clone:IsA("Model") then
		clone.Parent = vfxFolder
		pcall(function() clone:PivotTo(CFrame.new(position)) end)
	elseif clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.CFrame = CFrame.new(position)
		clone.Parent = vfxFolder
	elseif clone:IsA("ParticleEmitter") or clone:IsA("Attachment") then
		local holder = Instance.new("Part")
		holder.Name = "WaterfallSplash_" .. key
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(1, 1, 1)
		holder.CFrame = CFrame.new(position)
		clone.Parent = holder  -- props before parent (NET-004)
		holder.Parent = vfxFolder
		clone = holder
	else
		clone.Parent = vfxFolder
	end

	-- Enable emitters and LEAVE them running (persistent — no stop/Debris).
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("ParticleEmitter") then d.Enabled = true end
	end
	if clone:IsA("ParticleEmitter") then clone.Enabled = true end

	waterfallSplashes[key] = clone
	return clone
end

-- Remove every persistent waterfall splash (call on map regenerate before
-- re-adding, so stale splashes from the old map don't linger). MEM-002: Destroy.
function VFXController.ClearWaterfallSplashes()
	for key, inst in pairs(waterfallSplashes) do
		if inst and inst.Parent then inst:Destroy() end
		waterfallSplashes[key] = nil
	end
end

--------------------------------------------------
-- PERSISTENT TILE-EFFECT VFX (Burning, Poison Cloud, ...). One instance per tile,
-- emitters left running until the effect is removed or the battle resets.
--------------------------------------------------
local tileEffectVfx = {}  -- "tx,ty" -> { id = effectId, inst = Instance }

function VFXController.SetTileEffect(tx, ty, effectId, position)
	local key = tostring(tx) .. "," .. tostring(ty)
	local cur = tileEffectVfx[key]
	if cur then
		if cur.id == effectId and cur.inst and cur.inst.Parent then return cur.inst end
		if cur.inst then cur.inst:Destroy() end
		tileEffectVfx[key] = nil
	end
	local reg = VFXController.GetRegistry and VFXController.GetRegistry()
	local map = reg and reg.ByTileEffect
	local assetName = map and map[effectId]
	if type(assetName) ~= "string" or assetName == "" then return nil end
	local folder = getAssetFolder()
	local template = folder and folder:FindFirstChild(assetName)
	if not template then
		warn(`[VFXController] Tile effect VFX asset not found: {assetName} ({effectId})`)
		return nil
	end
	local clone = template:Clone()
	local holder: Instance = clone
	if clone:IsA("Model") then
		clone.Parent = vfxFolder
		pcall(function() clone:PivotTo(CFrame.new(position)) end)
	elseif clone:IsA("BasePart") then
		clone.Anchored = true; clone.CanCollide = false; clone.CanQuery = false; clone.CanTouch = false
		clone.CFrame = CFrame.new(position)
		clone.Parent = vfxFolder
	else
		local p = Instance.new("Part")
		p.Name = "TileEffectVFX_" .. key
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(4, 0.2, 4)
		p.CFrame = CFrame.new(position)
		clone.Parent = p
		p.Parent = vfxFolder
		holder = p
	end
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("ParticleEmitter") then d.Enabled = true end
	end
	tileEffectVfx[key] = { id = effectId, inst = holder }
	return holder
end

function VFXController.ClearTileEffect(tx, ty)
	local key = tostring(tx) .. "," .. tostring(ty)
	local cur = tileEffectVfx[key]
	if cur and cur.inst then cur.inst:Destroy() end
	tileEffectVfx[key] = nil
end

function VFXController.ClearAllTileEffects()
	for key, cur in pairs(tileEffectVfx) do
		if cur.inst then cur.inst:Destroy() end
		tileEffectVfx[key] = nil
	end
end

return VFXController
