--!strict

-- Pure-function utilities for computing earnings per tick, click rewards,
-- and offline earnings. No state — operates on passed-in data only.
-- Lives in ReplicatedStorage so both server and client can use it.

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local GearData = require(script.Parent:WaitForChild("GearData"))
local RarityData = require(script.Parent:WaitForChild("RarityData"))

local EarningsCalc = {}

-- Compute earnings per AFK tick for a set of equipped gears on a motor.
-- equippedGearData is an array of { gearId: string, rarity: string } resolved
-- from the player's ownedGears by the caller.
-- Returns the total earnings for one tick cycle (baseEarnings × rarity × rpm).
function EarningsCalc.ComputeTickEarnings(
	equippedGearData: { { gearId: string, rarity: string } },
	motorRpm: number
): number
	local total = 0

	for _, entry in ipairs(equippedGearData) do
		local gearDef = GearData.GetGear(entry.gearId)
		if not gearDef then
			warn(string.format("EarningsCalc: unknown gearId %q", entry.gearId))
			continue
		end

		local rarityMult = RarityData.GetMultiplier(entry.rarity)
		total += gearDef.baseEarnings * rarityMult
	end

	return total * motorRpm
end

-- Compute the instant reward for clicking a gear.
-- Awarded on top of the AFK tick.
function EarningsCalc.ComputeClickReward(earningsPerTick: number): number
	return earningsPerTick * GameConfig.CLICK_MULTIPLIER
end

-- Compute offline earnings for a player who was away for offlineSeconds.
-- Earnings are capped at OFFLINE_CAP_HOURS and awarded at half the AFK rate.
function EarningsCalc.ComputeOfflineEarnings(offlineSeconds: number, earningsPerTick: number): number
	local OFFLINE_CAP_SECONDS = 8 * 3600 -- 8 hours
	local OFFLINE_MULTIPLIER = 0.5

	local cappedSeconds = math.min(offlineSeconds, OFFLINE_CAP_SECONDS)
	if cappedSeconds <= 0 then
		return 0
	end

	-- offlineSeconds * (earningsPerTick / BASE_TICK_RATE) * 0.5
	local ticksElapsed = cappedSeconds / GameConfig.BASE_TICK_RATE
	return math.floor(ticksElapsed * earningsPerTick * OFFLINE_MULTIPLIER)
end

return EarningsCalc
