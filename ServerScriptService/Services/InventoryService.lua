--!strict

-- Manages player inventory: owned motors, owned gears, equipped gear slots,
-- and equip/unequip operations. Validates all equip requests against motor
-- constraints (slots, tier caps).

local InventoryService = {}

function InventoryService:Init()
	-- Register equip handlers
end

function InventoryService:HandleEquipMotor(player, motorId)
	-- Validate and equip motor
end

function InventoryService:HandleEquipGear(player, gearUniqueId)
	-- Validate tier cap + slot availability and equip gear
end

return InventoryService
