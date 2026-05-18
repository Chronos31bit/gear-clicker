--!strict

-- Handles box opening requests. Validates player can afford the box,
-- rolls rarity + item from the box's pool, grants the result to inventory,
-- and deducts cost. All randomness is server-authoritative.

local UnboxService = {}

function UnboxService:Init()
	-- Register remote handlers, cache box/gacha data
end

function UnboxService:HandleOpenBox(player, boxId)
	-- Validate, roll, grant, deduct cost
end

return UnboxService
