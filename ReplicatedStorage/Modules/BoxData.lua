--!strict

-- Box definitions: cost, pool contents (motors + gears), and rarity roll table per box type.
-- Five progressive boxes: basic → premium → exotic → void → celestial.
-- Higher-cost boxes have higher-tier pools and better rarity distributions.
-- Used by UnboxService to determine what a player receives.

export type BoxPoolEntry = {
	type: "motor" | "gear",
	tier: number,
	weight: number,
}

export type BoxDef = {
	id: string,
	displayName: string,
	cost: number,
	contentsPool: { BoxPoolEntry },
	rarityRollTable: { [string]: number },
	motorDuplicateRefund: number,
}

local BoxData: { [string]: BoxDef } = {
	box_basic = {
		id = "box_basic",
		displayName = "Basic Box",
		cost = 100,
		contentsPool = {
			{ type = "gear", tier = 1, weight = 55 },
			{ type = "gear", tier = 2, weight = 20 },
			{ type = "motor", tier = 1, weight = 25 },
		},
		rarityRollTable = {
			Common = 50,
			Chilly = 30,
			Oily = 15,
			Glowing = 5,
		},
		motorDuplicateRefund = 10,
	},

	box_premium = {
		id = "box_premium",
		displayName = "Premium Box",
		cost = 500,
		contentsPool = {
			{ type = "gear", tier = 1, weight = 25 },
			{ type = "gear", tier = 2, weight = 30 },
			{ type = "gear", tier = 3, weight = 15 },
			{ type = "motor", tier = 1, weight = 15 },
			{ type = "motor", tier = 2, weight = 10 },
			{ type = "motor", tier = 3, weight = 5 },
		},
		rarityRollTable = {
			Common = 35,
			Chilly = 25,
			Oily = 20,
			Glowing = 12,
			Static = 8,
		},
		motorDuplicateRefund = 50,
	},

	box_exotic = {
		id = "box_exotic",
		displayName = "Exotic Box",
		cost = 2500,
		contentsPool = {
			{ type = "gear", tier = 2, weight = 20 },
			{ type = "gear", tier = 3, weight = 25 },
			{ type = "gear", tier = 4, weight = 15 },
			{ type = "gear", tier = 5, weight = 8 },
			{ type = "motor", tier = 2, weight = 15 },
			{ type = "motor", tier = 3, weight = 10 },
			{ type = "motor", tier = 4, weight = 7 },
		},
		rarityRollTable = {
			Chilly = 25,
			Oily = 22,
			Glowing = 20,
			Static = 18,
			Molten = 15,
		},
		motorDuplicateRefund = 250,
	},

	box_void = {
		id = "box_void",
		displayName = "Void Box",
		cost = 10000,
		contentsPool = {
			{ type = "gear", tier = 3, weight = 15 },
			{ type = "gear", tier = 4, weight = 25 },
			{ type = "gear", tier = 5, weight = 20 },
			{ type = "gear", tier = 6, weight = 8 },
			{ type = "motor", tier = 3, weight = 12 },
			{ type = "motor", tier = 4, weight = 12 },
			{ type = "motor", tier = 5, weight = 8 },
		},
		rarityRollTable = {
			Glowing = 22,
			Static = 20,
			Molten = 18,
			Frostbitten = 18,
			Radiant = 15,
			Eclipsed = 7,
		},
		motorDuplicateRefund = 1000,
	},

	box_celestial = {
		id = "box_celestial",
		displayName = "Celestial Box",
		cost = 50000,
		contentsPool = {
			{ type = "gear", tier = 4, weight = 10 },
			{ type = "gear", tier = 5, weight = 20 },
			{ type = "gear", tier = 6, weight = 15 },
			{ type = "gear", tier = 7, weight = 10 },
			{ type = "motor", tier = 4, weight = 15 },
			{ type = "motor", tier = 5, weight = 15 },
			{ type = "motor", tier = 6, weight = 10 },
			{ type = "motor", tier = 7, weight = 5 },
		},
		rarityRollTable = {
			Static = 5,
			Molten = 15,
			Frostbitten = 20,
			Radiant = 22,
			Eclipsed = 20,
			Mythical = 18,
		},
		motorDuplicateRefund = 5000,
	},
}

-- Return the full box catalog (only box definitions, not utility functions).
function BoxData.GetCatalog(): { [string]: BoxDef }
	local catalog: { [string]: BoxDef } = {}
	for id, def in pairs(BoxData) do
		if typeof(def) == "table" and (def :: any).id then
			catalog[id] = def :: BoxDef
		end
	end
	return catalog
end

-- Look up a single box definition by ID. Returns nil if not found.
function BoxData.GetBox(boxId: string): BoxDef?
	return BoxData[boxId]
end

return BoxData
