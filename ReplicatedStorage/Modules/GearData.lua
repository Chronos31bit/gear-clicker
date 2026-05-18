--!strict

-- Gear catalog: base earnings and tier for each gear type.
-- Individual gear instances also carry a rolled rarity (applied at unbox time).
-- Tier 1 = early game, tier 7 = endgame.
-- Base earnings scale exponentially across tiers.

export type GearDef = {
	id: string,
	displayName: string,
	tier: number,
	baseEarnings: number,
	modelAsset: string,
}

local GearData: { [string]: GearDef } = {
	gear_plastic = {
		id = "gear_plastic",
		displayName = "Plastic Cog",
		tier = 1,
		baseEarnings = 1,
		modelAsset = "rbxassetid://0",
	},
	gear_iron = {
		id = "gear_iron",
		displayName = "Iron Gear",
		tier = 2,
		baseEarnings = 3,
		modelAsset = "rbxassetid://0",
	},
	gear_steel = {
		id = "gear_steel",
		displayName = "Steel Pinion",
		tier = 3,
		baseEarnings = 10,
		modelAsset = "rbxassetid://0",
	},
	gear_tungsten = {
		id = "gear_tungsten",
		displayName = "Tungsten Sprocket",
		tier = 4,
		baseEarnings = 35,
		modelAsset = "rbxassetid://0",
	},
	gear_plasma = {
		id = "gear_plasma",
		displayName = "Plasma Ring",
		tier = 5,
		baseEarnings = 120,
		modelAsset = "rbxassetid://0",
	},
	gear_void = {
		id = "gear_void",
		displayName = "Void Cogwheel",
		tier = 6,
		baseEarnings = 500,
		modelAsset = "rbxassetid://0",
	},
	gear_celestial = {
		id = "gear_celestial",
		displayName = "Celestial Orbiter",
		tier = 7,
		baseEarnings = 2500,
		modelAsset = "rbxassetid://0",
	},
}

-- Return the full catalog (used by client catalog endpoint and server lookup).
function GearData.GetCatalog(): { [string]: GearDef }
	return GearData
end

-- Look up a single gear definition by ID. Returns nil if not found.
function GearData.GetGear(gearId: string): GearDef?
	return GearData[gearId]
end

-- Look up a gear definition by tier number.
-- Returns the first gear found at that tier, or nil if none exist.
function GearData.GetGearByTier(tier: number): GearDef?
	for _, def in pairs(GearData) do
		if typeof(def) == "table" and (def :: any).tier == tier then
			return def :: GearDef
		end
	end
	return nil
end

return GearData
