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

-- Cached reference to the cash display label
local cashLabel: TextLabel? = nil

-- Format a number with commas (e.g. 1234567 -> "1,234,567")
local function formatNumber(n: number): string
	local formatted = tostring(math.floor(n))
	local result = ""
	local count = 0
	for i = #formatted, 1, -1 do
		count += 1
		result = formatted:sub(i, i) .. result
		if count % 3 == 0 and i > 1 then
			result = "," .. result
		end
	end
	return result
end

-- Update the cash display with new balance and delta for pop animations.
-- delta > 0 means money was gained, delta < 0 means it was spent.
local function onCashUpdated(newBalance: number, delta: number)
	currentCash = newBalance

	if cashLabel then
		cashLabel.Text = "Cash: $" .. formatNumber(newBalance)
	end
end

-- Display a welcome-back notification with offline earnings.
local function onWelcomeBack(earnings: number)
	if earnings > 0 then
		print(string.format("Welcome back! You earned %s while away.", formatNumber(earnings)))
	end
end

-- Return the current cash balance (for other controllers to read).
function HUDController.GetCurrentCash(): number
	return currentCash
end

-- Init wires remote listeners and finds UI elements.
-- Called from ClientMain when the client starts.
function HUDController:Init()
	-- Find the cash label in the player's GUI
	local playerGui = Player:WaitForChild("PlayerGui")
	local hudGui = playerGui:WaitForChild("HUDGui")
	cashLabel = hudGui:WaitForChild("CashLabel") :: TextLabel?

	CashUpdated.OnClientEvent:Connect(onCashUpdated)
	WelcomeBack.OnClientEvent:Connect(onWelcomeBack)
end

return HUDController
