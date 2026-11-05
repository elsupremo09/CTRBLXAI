--!strict
-- AnimationRegistry.lua
-- CTRBLXAI | Shared unit-animation catalog (2026-10-28)
--
-- Single source of truth (DAT-001) for every R15 combat animation: the asset ids,
-- which pool each animation KIND draws from, its playback priority, and the
-- weapon / skill rules that decide WHICH kind an action plays.
--   * Server (BattleTurnController / CommandService) calls the Classify* helpers and
--     sends only the resulting kind string inside the existing broadcasts. The server
--     never plays an animation (NET-001); it only names the action.
--   * Client (UnitAnimController) resolves kind -> asset and plays it.
--
-- Asset ids are the user's own published animations (creator El_Pi0818). Roblox only
-- plays an animation inside an experience owned by the same user/group that owns the
-- animation asset; under a group-owned place these must be re-published to the group.
-- Ids are kept as STRINGS on purpose: 15-digit numbers formatted through tostring can
-- lose digits.

local AnimationRegistry = {}

AnimationRegistry.Assets = table.freeze({
	-- Idle (base loop + random fidgets)
	Idle             = "rbxassetid://94748749945128",
	IdleNailsCheck   = "rbxassetid://89253009239428",
	IdleArmStretch   = "rbxassetid://75035360024267",
	IdleSass         = "rbxassetid://101920400165183",
	Laugh            = "rbxassetid://76784462714662",
	FlyingKiss       = "rbxassetid://138844885618716",
	-- Movement
	Run              = "rbxassetid://109878831528544",
	-- Reactions
	Hit              = "rbxassetid://74045336700987",
	Hit2             = "rbxassetid://126217807136737",
	Hit3             = "rbxassetid://101755393111336",
	OneHandHit       = "rbxassetid://138393819070043",
	Block            = "rbxassetid://125423094094995",
	KODramatic       = "rbxassetid://125562907687625",
	-- Turn
	Thinking         = "rbxassetid://72727961648950",
	-- Skills
	DoubleCast       = "rbxassetid://138145745171321",
	BigSpell         = "rbxassetid://105707213702026",
	TwoHandQuickCast = "rbxassetid://91595918838984",
	ShieldBash       = "rbxassetid://117093901473041",
	Taunt            = "rbxassetid://115994392487282",
	-- Basic attacks / items
	Throw            = "rbxassetid://125258306969790",
	ThrowObject      = "rbxassetid://121233630855144",
	BowAttack        = "rbxassetid://81128991720639",
	BowShoot         = "rbxassetid://115269811850414",
	PistolShot       = "rbxassetid://115686841878786",
	DualWieldAttack  = "rbxassetid://122148196337613",
	-- Commands
	Push             = "rbxassetid://87861196818557",
	Interact         = "rbxassetid://123484135442026",
	OpenTreasure     = "rbxassetid://88582823384658",
	-- Battle end
	Victory          = "rbxassetid://75059269042453",
	Victory2         = "rbxassetid://128858587877090",
	-- Roblox default R15 stand-ins, used ONLY where no custom animation exists yet
	-- (melee basic attack / non-moving melee skills, unmapped ranged weapons).
	MeleeStandIn     = "rbxassetid://507768375",
	RangedStandIn    = "rbxassetid://507767714",
})

local A = AnimationRegistry.Assets

-- Kind -> pool. A kind with several assets picks one at random per play.
-- "None" is a valid kind on the wire meaning "play nothing" (it has no pool).
AnimationRegistry.Kinds = table.freeze({
	Idle         = table.freeze({ A.Idle }),
	Fidget       = table.freeze({ A.IdleNailsCheck, A.IdleArmStretch, A.IdleSass, A.Laugh, A.FlyingKiss }),
	Run          = table.freeze({ A.Run }),
	Hit          = table.freeze({ A.Hit, A.Hit2, A.Hit3, A.OneHandHit }),
	Block        = table.freeze({ A.Block }),
	KO           = table.freeze({ A.KODramatic }),
	Thinking     = table.freeze({ A.Thinking }),
	DoubleCast   = table.freeze({ A.DoubleCast }),
	BigSpell     = table.freeze({ A.BigSpell }),
	QuickCast    = table.freeze({ A.TwoHandQuickCast }),
	ShieldBash   = table.freeze({ A.ShieldBash }),
	Taunt        = table.freeze({ A.Taunt }),
	Throw        = table.freeze({ A.Throw }),
	ThrowObject  = table.freeze({ A.ThrowObject }),
	Bow          = table.freeze({ A.BowAttack, A.BowShoot }),
	Pistol       = table.freeze({ A.PistolShot }),
	DualWield    = table.freeze({ A.DualWieldAttack }),
	Push         = table.freeze({ A.Push }),
	Interact     = table.freeze({ A.Interact }),
	OpenTreasure = table.freeze({ A.OpenTreasure }),
	Victory      = table.freeze({ A.Victory, A.Victory2 }),
	-- Stand-in / client-fallback kinds (device hits and anything the server did not name).
	Attack       = table.freeze({ A.MeleeStandIn }),
	Projectile   = table.freeze({ A.RangedStandIn }),
	Cast         = table.freeze({ A.TwoHandQuickCast }),
})

-- Playback priority per kind. Anything not listed is an actor action (Action2).
-- Order: Idle < Movement < Action (idle filler) < Action2 (actions) < Action3 (hit
-- reactions) < Action4 (KO / victory, which must override everything).
AnimationRegistry.DEFAULT_PRIORITY = Enum.AnimationPriority.Action2
AnimationRegistry.Priority = table.freeze({
	Idle     = Enum.AnimationPriority.Idle,
	Run      = Enum.AnimationPriority.Movement,
	Fidget   = Enum.AnimationPriority.Action,
	Thinking = Enum.AnimationPriority.Action,
	Hit      = Enum.AnimationPriority.Action3,
	Block    = Enum.AnimationPriority.Action3,
	KO       = Enum.AnimationPriority.Action4,
	Victory  = Enum.AnimationPriority.Action4,
})

-- Weapon archetype sets for basic attacks (WeaponData archetype ids).
local THROWN_WEAPONS = table.freeze({
	["WPN-THROWINGKNIFE"] = true,
	["WPN-JAVELIN"]       = true,
	["WPN-BOOMERANG"]     = true,
})
local BOW_WEAPONS = table.freeze({
	["WPN-LONGBOW"]  = true,
	["WPN-GREATBOW"] = true,
})
local PISTOL_WEAPONS = table.freeze({
	["WPN-PISTOL"]   = true,
	["WPN-CROSSBOW"] = true,
	["WPN-BLOWGUN"]  = true,
})

-- Basic-attack kind from the attacker's equipped weapons. nil = no custom animation
-- for this weapon (the client falls back to the melee / ranged stand-in).
-- offHandIsWeapon: dual wield (a Twinblade holding a 1H weapon in the OffHand slot).
function AnimationRegistry.ClassifyBasicAttack(mainArchetypeId: string?, offHandIsWeapon: boolean?): string?
	if offHandIsWeapon then
		return "DualWield"
	end
	if mainArchetypeId == nil then
		return nil
	end
	if THROWN_WEAPONS[mainArchetypeId] then
		return "Throw"
	elseif BOW_WEAPONS[mainArchetypeId] then
		return "Bow"
	elseif PISTOL_WEAPONS[mainArchetypeId] then
		return "Pistol"
	end
	return nil
end

-- Caster kind for an INSTANT (non-channeled) skill resolution.
--   def          runtime skill def (CommandService.GetSkill) — flags + channelTime
--   contentTags  Content.SkillData tags (Melee / Ranged), may be nil
--   isSelfTarget the skill landed on its own caster
--   dealtDamage  the resolution removed HP from the target
--   weaponMaxRange caster's weapon reach, used for weapon-reach skills (range -1)
-- A damage skill that can only hit adjacent tiles counts as melee (2026-10-28 ruling):
-- authored range 1, a weapon-reach skill on a reach-1 weapon, or a caster-centred
-- Adjacent pattern. Heals, buffs and shields never count as melee.
-- Channeled skills return "None": their caster animation is double-cast on channel
-- start and Big Spell on release (both sent by CommandService), not here.
local function hasTag(list: { string }?, wanted: string): boolean
	if list then
		for _, tag in list do
			if tag == wanted then
				return true
			end
		end
	end
	return false
end

local function isAdjacentOnly(def: any, weaponMaxRange: number?): boolean
	if def.range == 1 then
		return true
	elseif def.range == -1 then
		return (weaponMaxRange or 1) <= 1
	elseif def.range == 0 then
		return def.aoePattern == "Adjacent"
	end
	return false
end

function AnimationRegistry.ClassifySkill(def: any, contentTags: { string }?, isSelfTarget: boolean, dealtDamage: boolean, weaponMaxRange: number?): string?
	if type(def) ~= "table" then
		return nil
	end
	if (def.channelTime or 0) > 0 then
		return "None"
	end
	-- Damage skills that move the caster (charge / leap).
	if def.isCharge or def.leapsAdjacent or def.isLeapStrike then
		return "ShieldBash"
	end
	-- Any buff / shield / stance that lands on the caster = self-buff.
	if isSelfTarget and not dealtDamage and not def.isHealing then
		return "Taunt"
	end
	if hasTag(contentTags, "Melee") then
		return "Attack"  -- non-moving melee skill: stand-in until a custom one exists
	end
	local isDamage = hasTag(def.tags, "Direct Damage") or hasTag(contentTags, "Direct Damage")
	if isDamage and not def.isHealing and not def.isShield and isAdjacentOnly(def, weaponMaxRange) then
		return "Attack"  -- adjacent-only damage skill = melee, by reach
	end
	return "QuickCast"
end

return table.freeze(AnimationRegistry)
