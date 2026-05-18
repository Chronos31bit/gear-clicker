--!strict

-- Manages player inventory: owned gears, equipped gear slots,
-- and equip/unequip operations for gears.
-- Motor equip is handled by MotorService.

local InventoryService = {}

function InventoryService:Init()
	-- Register equip handlers
end

function InventoryService:HandleEquipGear(player, gearUniqueId)
	-- Validate tier cap + slot availability and equip gear
end

return InventoryService
