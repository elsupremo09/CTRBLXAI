-- Registry.lua
-- Content Registry facade for CTRBLXAI
-- Provides GetSkill, GetAugment, GetDoctrine lookups.
-- All data is frozen and immutable at runtime.

local SkillData = require(script.Parent.SkillData)
local AugmentData = require(script.Parent.AugmentData)
local DoctrineData = require(script.Parent.DoctrineData)

local Registry = {}

function Registry.GetSkill(id: string)
	return SkillData[id]
end

function Registry.GetAugment(id: string)
	return AugmentData[id]
end

function Registry.GetDoctrine(id: string)
	return DoctrineData[id]
end

return table.freeze(Registry)
