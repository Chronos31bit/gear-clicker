--!strict

-- Runs the AFK earnings tick loop per player. Tracks equipped gears and
-- motor stats to compute per-tick earnings. Also handles click burst rewards
-- with debounce. Distributes offline earnings on join.

local EarningsService = {}

function EarningsService:Init()
	-- Start tick loops, register click handler
end

function EarningsService:HandleClickGear(player, gearUniqueId)
	-- Validate and grant click burst earnings
end

return EarningsService
