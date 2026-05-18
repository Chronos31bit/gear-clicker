--!strict

-- Client entry point. Initializes controllers and sets up remote proxies.
-- Runs when the player's character loads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PlayerScripts = script.Parent

local HUDController = require(PlayerScripts:WaitForChild("HUDController"))

HUDController:Init()
