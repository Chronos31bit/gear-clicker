--!strict

-- Motor catalog: tier, RPM, max gear slots, max gear tier, and model per motor.
-- Every motor ID in the game is defined here.
-- Tier 1 = early game, tier 7 = endgame.
-- Higher-tier motors unlock more gear slots and accept higher-tier gears.

export type MotorDef = {
	id: string,
	displayName: string,
	tier: number,
	rpm: number,
	maxGearSlots: number,
	maxGearTier: number,
	modelAsset: string,
}

local MotorData: { [string]: MotorDef } = {
	motor_rusty = {
		id = "motor_rusty",
		displayName = "Rusty Spindle",
		tier = 1,
		rpm = 1.0,
		maxGearSlots = 1,
		maxGearTier = 1,
		modelAsset = "rbxassetid://0",
	},
	motor_iron = {
		id = "motor_iron",
		displayName = "Iron Cog",
		tier = 2,
		rpm = 1.5,
		maxGearSlots = 2,
		maxGearTier = 2,
		modelAsset = "rbxassetid://0",
	},
	motor_steel = {
		id = "motor_steel",
		displayName = "Steel Axle",
		tier = 3,
		rpm = 2.0,
		maxGearSlots = 2,
		maxGearTier = 3,
		modelAsset = "rbxassetid://0",
	},
	motor_turbo = {
		id = "motor_turbo",
		displayName = "Turbo Rotor",
		tier = 4,
		rpm = 3.0,
		maxGearSlots = 3,
		maxGearTier = 4,
		modelAsset = "rbxassetid://0",
	},
	motor_quantum = {
		id = "motor_quantum",
		displayName = "Quantum Drive",
		tier = 5,
		rpm = 5.0,
		maxGearSlots = 4,
		maxGearTier = 5,
		modelAsset = "rbxassetid://0",
	},
	motor_singularity = {
		id = "motor_singularity",
		displayName = "Singularity Core",
		tier = 6,
		rpm = 8.0,
		maxGearSlots = 4,
		maxGearTier = 6,
		modelAsset = "rbxassetid://0",
	},
	motor_mythicore = {
		id = "motor_mythicore",
		displayName = "Mythicore Engine",
		tier = 7,
		rpm = 15.0,
		maxGearSlots = 5,
		maxGearTier = 7,
		modelAsset = "rbxassetid://0",
	},
}

-- Return the full catalog (used by client catalog endpoint and server lookup).
function MotorData.GetCatalog(): { [string]: MotorDef }
	return MotorData
end

-- Look up a single motor definition by ID. Returns nil if not found.
function MotorData.GetMotor(motorId: string): MotorDef?
	return MotorData[motorId]
end

-- Look up a motor definition by tier number.
-- Returns the first motor found at that tier, or nil if none exist.
function MotorData.GetMotorByTier(tier: number): MotorDef?
	for _, def in pairs(MotorData) do
		if typeof(def) == "table" and (def :: any).tier == tier then
			return def :: MotorDef
		end
	end
	return nil
end

return MotorData
