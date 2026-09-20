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

function VFXController.Init(biome)
	-- Bloom: subtle glow on Neon tile highlights and skill effects
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local b = Instance.new("BloomEffect")
		b.Intensity = 0.7
		b.Size = 28
		b.Threshold = 0.8  -- lowered 0.9->0.8 so mid-bright neon (blue move frame) blooms
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

return VFXController
