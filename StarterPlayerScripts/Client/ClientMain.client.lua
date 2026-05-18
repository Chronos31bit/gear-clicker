--!strict

-- Client entry point. Initializes controllers and sets up remote proxies.
-- Runs when the player's character loads.

local PlayerScripts = script.Parent

local HUDController = require(PlayerScripts:WaitForChild("HUDController"))
local UnboxController = require(PlayerScripts:WaitForChild("UnboxController"))
local AdminController = require(PlayerScripts:WaitForChild("AdminController"))

HUDController:Init()
UnboxController:Init()
AdminController:Init()
