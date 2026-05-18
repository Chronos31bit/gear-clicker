--!strict

-- Server bootstrap. Requires all services and wires them to remotes.

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

PlayerDataService:Init()
UnboxService:Init()
EarningsService:Init()
InventoryService:Init()

OpenBox.OnServerEvent:Connect(function(player, ...)
	UnboxService:HandleOpenBox(player, ...)
end)

EquipMotor.OnServerEvent:Connect(function(player, ...)
	InventoryService:HandleEquipMotor(player, ...)
end)

EquipGear.OnServerEvent:Connect(function(player, ...)
	InventoryService:HandleEquipGear(player, ...)
end)

ClickGear.OnServerEvent:Connect(function(player, ...)
	EarningsService:HandleClickGear(player, ...)
end)

RequestSave.OnServerEvent:Connect(function(player)
	PlayerDataService:SavePlayerAsync(player)
end)

GetPlayerData.OnServerInvoke = function(player)
	return PlayerDataService:GetPlayerData(player)
end

GetCatalog.OnServerInvoke = function()
	local BoxData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BoxData"))
	return BoxData
end

Players.PlayerAdded:Connect(function(player)
	PlayerDataService:LoadPlayerAsync(player)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerDataService:SavePlayerAsync(player)
end)
