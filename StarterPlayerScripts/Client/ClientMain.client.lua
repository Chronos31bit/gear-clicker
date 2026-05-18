--!strict

-- Client entry point. Initializes controllers and sets up remote proxies.
-- Runs when the player's character loads.

local PlayerScripts = script.Parent

local HUDController = require(PlayerScripts:WaitForChild("HUDController"))

HUDController:Init()
