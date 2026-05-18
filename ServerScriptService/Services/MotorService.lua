--!strict

-- Handles motor equip/unequip operations. Server-authoritative.
-- Validates player owns the motor, swaps equipped motor, and handles
-- unequipping gears that exceed the new motor's slot or tier caps.
-- Unequipped gears are returned to the player's inventory (not deleted).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MotorData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MotorData"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("PlayerDataService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EquipMotorRemote = Remotes:WaitForChild("EquipMotor") :: RemoteEvent
local MotorEquippedRemote = Remotes:WaitForChild("MotorEquipped") :: RemoteEvent

local MotorService = {}

-- Equip a motor for a player. Returns (true) on success or (false, errorMsg).
-- Handles:
--   - Validation (owns motor, motor exists)
--   - No-op if the motor is already equipped
--   - Unequipping gears whose tier exceeds the new motor's maxGearTier
--   - Trimming equipped gears if they exceed the new motor's maxGearSlots
--   - Firing MotorEquipped to the client with unequipped gear IDs
function MotorService.EquipMotor(player: Player, motorId: string): (boolean, string?)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then
		return false, "Profile not loaded"
	end

	local motorDef = MotorData.GetMotor(motorId)
	if not motorDef then
		return false, "Unknown motor: " .. motorId
	end

	-- Check if player owns this motor
	if not profile.inventory.motors[motorId] then
		return false, "You don't own this motor"
	end

	-- No-op if already equipped
	if profile.equippedMotor == motorId then
		return true
	end

	-- Swap the equipped motor
	profile.equippedMotor = motorId

	-- Collect IDs of gears that must be unequipped due to cap changes
	local unequippedGearIds: { string } = {}

	-- Phase 1: Unequip gears whose tier exceeds the new motor's maxGearTier
	for slot = 1, 5 do
		local uid = profile.equippedGears[slot]
		if not uid then
			continue
		end
		local gearInst = profile.inventory.gears[uid]
		if gearInst and gearInst.tier > motorDef.maxGearTier then
			profile.equippedGears[slot] = nil
			table.insert(unequippedGearIds, uid)
		end
	end

	-- Phase 2: If still over the slot count, remove extras from the highest slots
	local filledSlots = 0
	for slot = 1, 5 do
		if profile.equippedGears[slot] then
			filledSlots += 1
		end
	end

	local excess = filledSlots - motorDef.maxGearSlots
	if excess > 0 then
		for slot = 5, 1, -1 do
			if excess <= 0 then break end
			local uid = profile.equippedGears[slot]
			if uid then
				profile.equippedGears[slot] = nil
				table.insert(unequippedGearIds, uid)
				excess -= 1
			end
		end
	end

	-- Notify the client
	MotorEquippedRemote:FireClient(player, motorId, unequippedGearIds)

	return true
end

-- Return formatted stats for any motor by its ID. Returns nil if not found.
function MotorService.GetMotorStats(motorId: string): { [string]: any }?
	local motorDef = MotorData.GetMotor(motorId)
	if not motorDef then
		return nil
	end

	return {
		id = motorDef.id,
		displayName = motorDef.displayName,
		tier = motorDef.tier,
		rpm = motorDef.rpm,
		maxGearSlots = motorDef.maxGearSlots,
		maxGearTier = motorDef.maxGearTier,
		modelAsset = motorDef.modelAsset,
	}
end

-- Init hooks the EquipMotor RemoteEvent. Called once from Main.server.lua.
function MotorService:Init()
	EquipMotorRemote.OnServerEvent:Connect(function(player: Player, motorId: string)
		-- Validate argument type server-side
		if typeof(motorId) ~= "string" then
			warn(string.format("EquipMotor: invalid motorId type from %s: %s", player.Name, typeof(motorId)))
			return
		end

		local ok, err = MotorService.EquipMotor(player, motorId)
		if not ok and err then
			warn(string.format("EquipMotor failed for %s: %s", player.Name, err))
		end
	end)
end

return MotorService
