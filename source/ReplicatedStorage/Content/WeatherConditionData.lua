--!strict
-- WeatherConditionData.lua
-- CTRBLXAI | Client-facing descriptions of the 15 battle conditions (weather/crisis).
-- Source: CTRBLXAI.db objects_encounters BATTLE CONDITIONS block. Display-only; the
-- live mechanics run server-side in WeatherService. Keyed by condition name.

local WeatherConditionData = {}

WeatherConditionData.Conditions = {
	["Clear"] = { name = "Clear", description = "Calm battlefield.", passive = "None.", periodic = "None." },
	["Rain"] = { name = "Rain", description = "Rain drenches the battlefield.", passive = "Fire Damage -25%; Water Damage +25%.", periodic = "Every 300 CT, apply Wet to all units and traversable tiles (undispellable this round)." },
	["Strong Wind"] = { name = "Strong Wind", description = "Powerful winds sweep the battlefield.", passive = "Wind Damage +25%.", periodic = "Every 300 CT, trigger Wind reactions: Steam and Static Cloud clear; Burning spreads an extra pass; Poison Cloud drifts one tile." },
	["Heatwave"] = { name = "Heatwave", description = "Intense heat dries the battlefield.", passive = "Fire Damage +20%; Water Damage -20%.", periodic = "Every 300 CT, water dries up, Ice melts, grass ignites, Swamp/Mud harden to Rock, Wet becomes Steam." },
	["Dark Eclipse"] = { name = "Dark Eclipse", description = "Darkness engulfs the battlefield.", passive = "Light Damage -25%; Dark Damage +25%; Recruitment -20%.", periodic = "Undead, Werewolf and Demon units gain undispellable Haste this round." },
	["Holy Aurora"] = { name = "Holy Aurora", description = "Holy light shines over the battlefield.", passive = "Light Damage +25%; Dark Damage -25%.", periodic = "Every 300 CT, Undead units take 5% Max HP Light damage; Undead/Werewolf/Demon gain undispellable Slow this round." },
	["Wild Growth"] = { name = "Wild Growth", description = "Nature rapidly overtakes the battlefield.", passive = "None.", periodic = "Every 300 CT, Vines spread to 15-25% of vine-free terrain." },
	["Mana Storm"] = { name = "Mana Storm", description = "Magical energy floods the battlefield.", passive = "None.", periodic = "Every 300 CT, all units restore 10% Max MP, then take HP damage equal to 50% of current MP." },
	["Thunderstorm"] = { name = "Thunderstorm", description = "Lightning repeatedly strikes elevated targets.", passive = "None.", periodic = "Every 300 CT, the highest-elevation unit takes 20% Max HP Light damage and its tile drops 1 elevation." },
	["Meteor Storm"] = { name = "Meteor Storm", description = "Meteors periodically bombard marked locations.", passive = "None.", periodic = "Every 300 CT, mark 1-3 tiles; 300 CT later deal 30% Max HP Fire damage (15% to neighbors) and lower the tile." },
	["Volcanic Eruptions"] = { name = "Volcanic Eruptions", description = "Magma erupts throughout the battlefield.", passive = "None.", periodic = "Every 300 CT, mark 3-5 cross areas; 300 CT later deal 15% Max HP Fire damage, turn tiles Molten, raise elevation." },
	["Earthquake"] = { name = "Earthquake", description = "Violent tremors reshape the battlefield.", passive = "None.", periodic = "Every 300 CT, 20-40% of tiles shift -2 to +2 elevation; units on them take +150 RT Delay." },
	["Severe Hail"] = { name = "Severe Hail", description = "Freezing hail blankets the battlefield.", passive = "None.", periodic = "Every 300 CT, half of all units take 10% Max HP damage." },
	["Hunger Virus"] = { name = "Hunger Virus", description = "A magical plague spreads across the battlefield.", passive = "Every 300 CT, living units lose 5% Max HP; Basic Attacks heal the attacker for 20% of damage dealt.", periodic = "None." },
	["Snow Storm"] = { name = "Snow Storm", description = "A freezing blizzard entombs the battlefield.", passive = "None.", periodic = "All units are undispellable Frozen this round; all water terrain freezes to Ice." },
}

function WeatherConditionData.Get(name: string?)
	if not name then return nil end
	return WeatherConditionData.Conditions[name]
end

return table.freeze(WeatherConditionData)
