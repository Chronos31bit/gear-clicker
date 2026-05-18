--!strict

-- Server bootstrap. Requires all services and wires them to remotes.
-- Player lifecycle (join/leave) is handled inside PlayerDataService:Init().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenBox = Remotes:WaitForChild("OpenBox") :: RemoteEvent
local EquipMotor = Remotes:WaitForChild("EquipMotor") :: RemoteEvent
local EquipGear = Remotes:WaitForChild("EquipGear") :: RemoteEvent
local ClickGear = Remotes:WaitForChild("ClickGear") :: RemoteEvent
local RequestSave = Remotes:WaitForChild("RequestSave") :: RemoteEvent
local GetPlayerData = Remotes:WaitForChild("GetPlayerData") :: RemoteFunction
local GetCatalog = Remotes:WaitForChild("GetCatalog") :: RemoteFunction

local Services = ServerScriptService:WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local UnboxService = require(Services:WaitForChild("UnboxService"))
local EarningsService = require(Services:WaitForChild("EarningsService"))
local InventoryService = require(Services:WaitForChild("InventoryService"))
local MotorService = require(Services:WaitForChild("MotorService"))
local GearService = require(Services:WaitForChild("GearService"))

PlayerDataService:Init()
UnboxService:Init()
EarningsService:Init()
InventoryService:Init()
MotorService:Init()
GearService:Init()

OpenBox.OnServerEvent:Connect(function(player, ...)
	UnboxService:HandleOpenBox(player, ...)
end)

RequestSave.OnServerEvent:Connect(function(player)
	PlayerDataService:SavePlayerAsync(player, false)
end)

GetPlayerData.OnServerInvoke = function(player)
	return PlayerDataService:GetPlayerData(player)
end

GetCatalog.OnServerInvoke = function()
	local BoxData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BoxData"))
	return BoxData
end

-- Player lifecycle (PlayerAdded → LoadPlayerAsync, PlayerRemoving → SavePlayerAsync)
-- is handled inside PlayerDataService:Init() alongside session locking, autosave,
-- and BindToClose.
