--!strict

-- Rarity definitions: display names, multipliers, and roll weights per tier.
-- Used server-side for unboxing rolls and client-side for display.
-- Table order is from most common (lowest multiplier) to rarest (highest).
-- See CLAUDE.md for the canonical rarity table.

export type RarityDef = {
	id: string,
	displayName: string,
	multiplier: number,
}

local RarityData: { [string]: RarityDef } = {
	Common = {
		id = "Common",
		displayName = "Common",
		multiplier = 1.0,
	},
	Chilly = {
		id = "Chilly",
		displayName = "Chilly",
		multiplier = 1.35,
	},
	Oily = {
		id = "Oily",
		displayName = "Oily",
		multiplier = 1.80,
	},
	Glowing = {
		id = "Glowing",
		displayName = "Glowing",
		multiplier = 2.50,
	},
	Static = {
		id = "Static",
		displayName = "Static",
		multiplier = 4.0,
	},
	Molten = {
		id = "Molten",
		displayName = "Molten",
		multiplier = 7.0,
	},
	Frostbitten = {
		id = "Frostbitten",
		displayName = "Frostbitten",
		multiplier = 12.0,
	},
	Radiant = {
		id = "Radiant",
		displayName = "Radiant",
		multiplier = 22.0,
	},
	Eclipsed = {
		id = "Eclipsed",
		displayName = "Eclipsed",
		multiplier = 50.0,
	},
	Mythical = {
		id = "Mythical",
		displayName = "Mythical",
		multiplier = 150.0,
	},
}

-- Return a single rarity definition by ID, or nil if not found.
function RarityData.GetRarity(rarityId: string): RarityDef?
	return RarityData[rarityId]
end

-- Return the multiplier for a rarity ID. Falls back to 1.0 for unknown rarities
-- so the game never breaks on missing data.
function RarityData.GetMultiplier(rarityId: string): number
	local def = RarityData[rarityId]
	if def then
		return def.multiplier
	end
	return 1.0
end

return RarityData
