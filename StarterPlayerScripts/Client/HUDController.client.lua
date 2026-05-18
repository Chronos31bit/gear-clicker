--!strict

-- Manages HUD display: cash counter, equipped gear slots, motor info,
-- and tick/click earnings feedback. Updates UI in response to server state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CashUpdated = Remotes:WaitForChild("CashUpdated") :: RemoteEvent
local WelcomeBack = Remotes:WaitForChild("WelcomeBack") :: RemoteEvent

local Player = Players.LocalPlayer
local HUDController = {}

-- Current cash balance, updated by server events
local currentCash: number = 0

-- Update the cash display with new balance and delta for pop animations.
-- delta > 0 means money was gained, delta < 0 means it was spent.
local function onCashUpdated(newBalance: number, delta: number)
	currentCash = newBalance

	-- TODO: update cash counter UI element when ScreenGuis are created
	-- TODO: trigger +money pop animation for positive delta
	print(string.format("Cash: %d (%+d)", newBalance, delta))
end

-- Display a welcome-back notification with offline earnings.
local function onWelcomeBack(earnings: number)
	if earnings > 0 then
		-- TODO: show welcome-back popup UI element
		print(string.format("Welcome back! You earned %d while away.", earnings))
	end
end

-- Return the current cash balance (for other controllers to read).
function HUDController.GetCurrentCash(): number
	return currentCash
end

-- Init wires remote listeners. Called from ClientMain when the client starts.
function HUDController:Init()
	CashUpdated.OnClientEvent:Connect(onCashUpdated)
	WelcomeBack.OnClientEvent:Connect(onWelcomeBack)
end

return HUDController
