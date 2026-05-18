--!strict

-- Handles gear equip/unequip operations. Server-authoritative.
-- Validates player owns the gear, slot is within motor's capacity,
-- gear tier does not exceed motor's max gear tier, and slot is not occupied.
-- Equipped gears are stored as a contiguous array (no gaps).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GearData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GearData"))
local MotorData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MotorData"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("PlayerDataService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EquipGearRemote = Remotes:WaitForChild("EquipGear") :: RemoteEvent
local GearEquippedRemote = Remotes:WaitForChild("GearEquipped") :: RemoteEvent
local UnequipGearRemote = Remotes:WaitForChild("UnequipGear") :: RemoteEvent

local GearService = {}

-- Scan ownedGears array for a gear instance by uniqueId. Returns the instance or nil.
local function findGearInstance(
	ownedGears: { { uniqueId: string, gearId: string, tier: number, rarity: string } },
	uniqueId: string
): { uniqueId: string, gearId: string, tier: number, rarity: string }?
	for _, gear in ipairs(ownedGears) do
		if gear.uniqueId == uniqueId then
			return gear
		end
	end
	return nil
end

-- Check if a gear uniqueId is already in the equipped gears array.
local function isGearEquipped(equippedGears: { string }, uniqueId: string): boolean
	for _, uid in ipairs(equippedGears) do
		if uid == uniqueId then
			return true
		end
	end
	return false
end

-- Equip a gear to a slot. Slots are 1-indexed and must fill consecutively
-- (contiguous array invariant). Returns (true) or (false, errorCode).
function GearService.EquipGear(player: Player, gearUniqueId: string, slotIndex: number): (boolean, string?)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then
		return false, "Profile not loaded"
	end

	-- Validate ownership
	local gearInstance = findGearInstance(profile.ownedGears, gearUniqueId)
	if not gearInstance then
		return false, "Gear not owned"
	end

	-- Check not already equipped
	if isGearEquipped(profile.equippedGears, gearUniqueId) then
		return false, "Gear already equipped"
	end

	-- Coerce to integer
	slotIndex = math.floor(slotIndex)
	if slotIndex < 1 then
		return false, "Invalid slot"
	end

	-- Validate motor is equipped
	local motorDef = MotorData.GetMotor(profile.equippedMotor)
	if not motorDef then
		return false, "No motor equipped"
	end

	-- Slot within motor's capacity
	if slotIndex > motorDef.maxGearSlots then
		return false, "SLOT_OUT_OF_RANGE"
	end

	-- Gear tier within motor's max (tier is stored on the gear instance)
	if gearInstance.tier > motorDef.maxGearTier then
		return false, "MOTOR_TIER_TOO_LOW"
	end

	-- Slot must be the next available slot (contiguous array, no gaps)
	-- If slotIndex <= #equippedGears the slot is occupied.
	-- If slotIndex > #equippedGears + 1 it would leave a gap.
	if slotIndex ~= #profile.equippedGears + 1 then
		return false, "SLOT_OCCUPIED"
	end

	-- Equip
	table.insert(profile.equippedGears, gearUniqueId)

	-- Notify client
	GearEquippedRemote:FireClient(player, gearUniqueId, slotIndex)

	return true
end

-- Unequip gear from a slot. Removes the entry from the contiguous array
-- and shifts subsequent entries left. Returns (true) or (false, errorMsg).
function GearService.UnequipGear(player: Player, slotIndex: number): (boolean, string?)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then
		return false, "Profile not loaded"
	end

	slotIndex = math.floor(slotIndex)
	if slotIndex < 1 or slotIndex > #profile.equippedGears then
		return false, "No gear in that slot"
	end

	-- Remove from array (shifts subsequent entries left, maintaining contiguity)
	local removedUid = table.remove(profile.equippedGears, slotIndex)

	-- Notify client: nil gearUniqueId signals the slot was cleared
	GearEquippedRemote:FireClient(player, nil, slotIndex)

	return true
end

-- Return readable stats for a gear definition. Returns nil if not found.
function GearService.GetGearStats(gearId: string): { [string]: any }?
	local gearDef = GearData.GetGear(gearId)
	if not gearDef then
		return nil
	end

	return {
		id = gearDef.id,
		displayName = gearDef.displayName,
		tier = gearDef.tier,
		baseEarnings = gearDef.baseEarnings,
		modelAsset = gearDef.modelAsset,
	}
end

-- Init hooks the EquipGear and UnequipGear RemoteEvents.
-- Called once from Main.server.lua.
function GearService:Init()
	EquipGearRemote.OnServerEvent:Connect(function(player: Player, gearUniqueId: any, slotIndex: any)
		-- Validate argument types server-side
		if typeof(gearUniqueId) ~= "string" or typeof(slotIndex) ~= "number" then
			warn(string.format("EquipGear: invalid arguments from %s: gearUniqueId=%s, slotIndex=%s",
				player.Name, typeof(gearUniqueId), typeof(slotIndex)))
			return
		end

		local ok, err = GearService.EquipGear(player, gearUniqueId, slotIndex)
		if not ok and err then
			warn(string.format("EquipGear failed for %s: %s", player.Name, err))
		end
	end)

	UnequipGearRemote.OnServerEvent:Connect(function(player: Player, slotIndex: any)
		if typeof(slotIndex) ~= "number" then
			warn(string.format("UnequipGear: invalid slotIndex from %s: %s",
				player.Name, typeof(slotIndex)))
			return
		end

		local ok, err = GearService.UnequipGear(player, slotIndex)
		if not ok and err then
			warn(string.format("UnequipGear failed for %s: %s", player.Name, err))
		end
	end)
end

return GearService
