--!strict
-- SoundRegistry.lua
-- The ONE file you edit to wire combat sound effects.
--
-- HOW TO USE:
--   Paste a Roblox audio asset id into any slot below, e.g.
--       Fire = "rbxassetid://1234567890",
--   Any slot left as "" is simply skipped (silent) — the game stays fully
--   playable with zero ids filled, and gets louder as you fill them in.
--   Pick ids from Studio's Toolbox > Audio (Creator Store) — no uploads needed.
--
-- Pre-filled slots use Roblox's BUILT-IN engine sounds (rbxasset://sounds/...),
-- which ship with every client. Replace with Toolbox ids for better ones.
--
-- RESOLUTION ORDER for skills (first match wins), played ON HIT (not on cast):
--   1. Explosion tag  (future tag — slot is live but dormant until Designer adds it)
--   2. Element tag    (Fire/Ice/Electric/Water/Earth/Holy/Dark/Poison)
--   3. Heal           (isHealing or Healing tag)
--   4. Buff           (pure buff: no damage, no element)
--   5. Debuff         (pure debuff: no damage, no element)
--   6. PhysicalHit    (non-elemental damage skill, incl. Direct Damage + Debuff)
--   7. DefaultSkill   (final safety net)
--
-- Basic attacks are weapon-based (not tags): Melee vs Projectile.
-- Items resolve by their category field (not the free-form item tag vocab).

local SoundRegistry = {}

--------------------------------------------------
-- MIX / BEHAVIOR (tune these numbers freely)
--------------------------------------------------
SoundRegistry.MasterVolume = 0.5          -- multiplies every sound's volume
SoundRegistry.ThrottleSeconds = 0.06      -- min gap between two plays of the SAME slot
SoundRegistry.MaxConcurrentSame = 4       -- cap on simultaneous copies of one slot

-- Per-category volume multipliers (applied on top of MasterVolume)
SoundRegistry.CategoryVolume = {
	Hit     = 1.0,   -- attacks, elemental/physical skill hits, explosion
	Heal    = 0.9,
	Status  = 0.8,   -- buff / debuff applies
	Channel = 0.7,   -- looped channel sound
	Move    = 0.6,
	UI      = 0.5,   -- clicks, turn chime
	KO      = 1.0,
}

--------------------------------------------------
-- SKILL SOUNDS (keyed by element/type tag) — fire on HIT
-- Fill the asset id strings. Leave "" to stay silent.
--------------------------------------------------
SoundRegistry.Skill = {
	-- 1) Explosion (future tag; dormant until a skill carries the "explosion" tag)
	Explosion    = "rbxasset://sounds/collide.wav",

	-- 2) Elements
	Fire         = "rbxasset://sounds/Rocket shot.wav",
	Ice          = "",
	Electric     = "",
	Water        = "",
	Earth        = "",
	Holy         = "",
	Dark         = "",
	Poison       = "rbxasset://sounds/splat.wav",

	-- 3) Heal (heal lands)
	Heal         = "",

	-- 4) Buff (pure buff applies — no damage, no element)
	Buff         = "",

	-- 5) Debuff (pure debuff applies — no damage, no element)
	Debuff       = "",

	-- 6) Non-elemental damage skill hit (Direct Damage with no element,
	--    including Direct Damage + Debuff). A spell-ish "thwack".
	PhysicalHit  = "rbxasset://sounds/swordslash.wav",

	-- 7) Final safety net for any skill with no better match
	DefaultSkill = "rbxasset://sounds/electronicpingshort.wav",
}

--------------------------------------------------
-- BASIC ATTACKS (weapon-based) — fire on HIT
--------------------------------------------------
SoundRegistry.Attack = {
	Melee        = "rbxasset://sounds/swordslash.wav",   -- sword / axe / mace / unarmed
	Projectile   = "rbxasset://sounds/swordlunge.wav",   -- bow / crossbow / gun / thrown
}

--------------------------------------------------
-- OTHER TRPG ACTIONS
--------------------------------------------------
SoundRegistry.Action = {
	Move         = "rbxasset://sounds/action_footsteps_plastic.mp3",   -- unit moves to a tile
	Guard        = "rbxasset://sounds/unsheath.wav",   -- guard activates
	KO           = "rbxasset://sounds/uuhhh.mp3",   -- unit defeated
	TurnChime    = "rbxasset://sounds/electronicpingshort.wav",   -- YOUR turn begins (local player only)
	UIClick      = "rbxasset://sounds/snap.wav",   -- button press
}

--------------------------------------------------
-- CHANNELING (looped while a channel is in progress)
--------------------------------------------------
SoundRegistry.Channel = {
	Loop         = "",   -- plays looped from ChannelStarted until ChannelEnded
}

--------------------------------------------------
-- ITEMS (keyed by consumable category, NOT item tags)
--------------------------------------------------
SoundRegistry.Item = {
	Recovery     = "",   -- Recovery / Support category -> heal-ish
	Support      = "",
	Damage       = "rbxasset://sounds/collide.wav",   -- Damage category -> hit
	Control      = "",   -- Control category -> debuff-ish
	Environment  = "",
	Deployable   = "",
	Utility      = "",
	Default      = "",
}

return SoundRegistry
