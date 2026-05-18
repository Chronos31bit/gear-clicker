--!strict

-- Manages HUD display: cash counter (with tween animation), equipped gear slots,
-- motor info, and tick/click earnings feedback. Updates UI in response to server state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CashUpdated = Remotes:WaitForChild("CashUpdated") :: RemoteEvent
local WelcomeBack = Remotes:WaitForChild("WelcomeBack") :: RemoteEvent
local MotorEquipped = Remotes:WaitForChild("MotorEquipped") :: RemoteEvent
local GearEquipped = Remotes:WaitForChild("GearEquipped") :: RemoteEvent
local GetPlayerData = Remotes:WaitForChild("GetPlayerData") :: RemoteFunction

-- Shared data modules — client can read these for display
local MotorData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MotorData"))
local GearData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GearData"))
local RarityData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityData"))

local Player = Players.LocalPlayer
local HUDController = {}

-- ── State ──────────────────────────────────────────
local currentCash: number = 0
local currentMotorId: string? = nil
local currentEquippedGears: { [number]: string } = {}
-- Map of uniqueId -> gear instance (matches server inventory.gears schema)
local currentOwnedGears: { [string]: { id: string, tier: number, rarity: string, rolledAt: number } } = {}

-- ── Colors ─────────────────────────────────────────
local BG = Color3.fromRGB(20, 20, 30)
local FG = Color3.fromRGB(240, 240, 245)
local ACCENT = Color3.fromRGB(80, 160, 255)
local EMPTY = Color3.fromRGB(100, 100, 110)

local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(180, 180, 180),
	Chilly = Color3.fromRGB(100, 200, 255),
	Oily = Color3.fromRGB(180, 200, 80),
	Glowing = Color3.fromRGB(80, 240, 80),
	Static = Color3.fromRGB(220, 220, 50),
	Molten = Color3.fromRGB(255, 110, 50),
	Frostbitten = Color3.fromRGB(140, 200, 255),
	Radiant = Color3.fromRGB(255, 210, 90),
	Eclipsed = Color3.fromRGB(180, 100, 255),
	Mythical = Color3.fromRGB(255, 140, 200),
}

local function rarityColor(rarity: string): Color3
	return RARITY_COLORS[rarity] or EMPTY
end

-- ── Helpers ────────────────────────────────────────
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

local function formatMoney(n: number): string
	if n >= 1_000_000 then
		return string.format("$%.2fM", n / 1_000_000)
	elseif n >= 1_000 then
		return string.format("$%.2fK", n / 1_000)
	else
		return "$" .. formatNumber(n)
	end
end

-- Look up a gear instance by uniqueId from the owned-gears map
local function findGearByUid(uid: string): { id: string, tier: number, rarity: string }?
	return currentOwnedGears[uid]
end

-- Compute per-tick earnings for display purposes only
local function computeGearEarningsPerTick(gearId: string, rarity: string, rpm: number): number
	local gearDef = GearData.GetGear(gearId)
	if not gearDef then return 0 end
	local mult = RarityData.GetMultiplier(rarity)
	return gearDef.baseEarnings * mult * rpm
end

-- ── UI building ────────────────────────────────────

-- Create a labelled info row
local function makeLabel(parent: Instance, name: string, text: string, sizeY: number, textSize: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text
	l.Font = Enum.Font.Gotham
	l.TextSize = textSize
	l.TextColor3 = color
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, -20, 0, sizeY)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- Build the full HUD layout
local function buildHUD(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HUDGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	-- Background panel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Position = UDim2.new(0, 16, 0, 16)
	panel.Size = UDim2.new(0, 340, 0, 340)
	panel.Parent = gui

	-- Cash
	local cashL = makeLabel(panel, "CashLabel", "Cash: $0", 36, 28, FG)
	cashL.Font = Enum.Font.GothamBold
	cashL.Position = UDim2.new(0, 10, 0, 6)

	-- Motor section header
	local motorHeader = makeLabel(panel, "MotorHeader", "─── Motor ───", 20, 14, ACCENT)
	motorHeader.Position = UDim2.new(0, 10, 0, 44)

	-- Motor name
	local motorName = makeLabel(panel, "MotorName", "None equipped", 22, 18, FG)
	motorName.Position = UDim2.new(0, 20, 0, 64)

	-- Motor stats (tier, rpm)
	local motorStats = makeLabel(panel, "MotorStats", "", 18, 13, EMPTY)
	motorStats.Position = UDim2.new(0, 20, 0, 86)

	-- Gears section header
	local gearsHeader = makeLabel(panel, "GearsHeader", "─── Gears ───", 20, 14, ACCENT)
	gearsHeader.Position = UDim2.new(0, 10, 0, 110)

	-- Slot frames (max 5)
	for i = 1, 5 do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
		slot.BorderSizePixel = 0
		slot.Position = UDim2.new(0, 12, 0, 134 + (i - 1) * 34)
		slot.Size = UDim2.new(1, -24, 0, 30)
		slot.Parent = panel

		-- Slot number badge
		local badge = Instance.new("TextLabel")
		badge.Name = "Badge"
		badge.Text = tostring(i)
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = 13
		badge.TextColor3 = EMPTY
		badge.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
		badge.BorderSizePixel = 0
		badge.Size = UDim2.new(0, 24, 1, 0)
		badge.Parent = slot

		-- Gear name (or Empty placeholder)
		local nameL = Instance.new("TextLabel")
		nameL.Name = "Name"
		nameL.Text = "[ Empty ]"
		nameL.Font = Enum.Font.Gotham
		nameL.TextSize = 14
		nameL.TextColor3 = EMPTY
		nameL.BackgroundTransparency = 1
		nameL.Position = UDim2.new(0, 30, 0, 0)
		nameL.Size = UDim2.new(0.5, -10, 1, 0)
		nameL.TextXAlignment = Enum.TextXAlignment.Left
		nameL.Parent = slot

		-- Rarity label
		local rarityL = Instance.new("TextLabel")
		rarityL.Name = "Rarity"
		rarityL.Text = ""
		rarityL.Font = Enum.Font.GothamBold
		rarityL.TextSize = 12
		rarityL.TextColor3 = EMPTY
		rarityL.BackgroundTransparency = 1
		rarityL.Position = UDim2.new(0.5, -10, 0, 0)
		rarityL.Size = UDim2.new(0.25, 0, 1, 0)
		rarityL.TextXAlignment = Enum.TextXAlignment.Left
		rarityL.Parent = slot

		-- Earnings per tick
		local earnL = Instance.new("TextLabel")
		earnL.Name = "Earnings"
		earnL.Text = ""
		earnL.Font = Enum.Font.Gotham
		earnL.TextSize = 12
		earnL.TextColor3 = EMPTY
		earnL.BackgroundTransparency = 1
		earnL.Position = UDim2.new(0.75, 0, 0, 0)
		earnL.Size = UDim2.new(0.25, -4, 1, 0)
		earnL.TextXAlignment = Enum.TextXAlignment.Right
		earnL.Parent = slot
	end

	-- Total / click footer
	local footer = makeLabel(panel, "Footer", "", 18, 13, EMPTY)
	footer.Position = UDim2.new(0, 14, 0, 310)
end

-- ── UI update helpers ──────────────────────────────

local function getPanel(): Frame?
	local sg = Player:FindFirstChild("PlayerGui")
	if not sg then return nil end
	local gui = sg:FindFirstChild("HUDGui")
	if not gui then return nil end
	return gui:FindFirstChild("Panel") :: Frame?
end

local function getCashLabel(): TextLabel?
	local panel = getPanel()
	if not panel then return nil end
	return panel:FindFirstChild("CashLabel") :: TextLabel?
end

local function updateMotorDisplay()
	local panel = getPanel()
	if not panel then return end

	local nameL = panel:FindFirstChild("MotorName") :: TextLabel?
	local statsL = panel:FindFirstChild("MotorStats") :: TextLabel?
	if not nameL or not statsL then return end

	if currentMotorId then
		local def = MotorData.GetMotor(currentMotorId)
		if def then
			nameL.Text = def.displayName
			nameL.TextColor3 = FG

			-- Count filled slots
			local filledCount = 0
			for _ in pairs(currentEquippedGears) do
				filledCount += 1
			end

			statsL.Text = string.format("Tier %d  \u{2022}  %.1f RPM  \u{2022}  %d/%d slots",
				def.tier, def.rpm, filledCount, def.maxGearSlots)
			statsL.TextColor3 = EMPTY
		else
			nameL.Text = "Unknown motor"
			nameL.TextColor3 = EMPTY
		end
	else
		nameL.Text = "None equipped"
		nameL.TextColor3 = EMPTY
		statsL.Text = ""
	end
end

local function updateGearSlots()
	local panel = getPanel()
	if not panel then return end

	local motorDef = currentMotorId and MotorData.GetMotor(currentMotorId)
	local rpm = motorDef and motorDef.rpm or 1

	local totalPerTick = 0

	for i = 1, 5 do
		local slot = panel:FindFirstChild("Slot" .. i) :: Frame?
		if not slot then continue end

		local nameL = slot:FindFirstChild("Name") :: TextLabel?
		local rarityL = slot:FindFirstChild("Rarity") :: TextLabel?
		local earnL = slot:FindFirstChild("Earnings") :: TextLabel?
		if not nameL or not rarityL or not earnL then continue end

		local uid = currentEquippedGears[i]
		if uid then
			local gearInst = findGearByUid(uid)
			if gearInst then
				local gearDef = GearData.GetGear(gearInst.id)
				local rarityDef = RarityData.GetRarity(gearInst.rarity)
				local displayName = gearDef and gearDef.displayName or gearInst.id
				local rarityName = rarityDef and rarityDef.displayName or gearInst.rarity
				local rColor = rarityColor(gearInst.rarity)

				nameL.Text = displayName
				nameL.TextColor3 = FG
				rarityL.Text = "\9993 " .. rarityName
				rarityL.TextColor3 = rColor

				local gearEarn = computeGearEarningsPerTick(gearInst.id, gearInst.rarity, rpm)
				earnL.Text = formatMoney(gearEarn) .. "/t"
				earnL.TextColor3 = rColor
				totalPerTick += gearEarn
			else
				nameL.Text = "[ Missing ]"
				nameL.TextColor3 = Color3.fromRGB(200, 80, 80)
				rarityL.Text = ""
				earnL.Text = ""
			end
		else
			nameL.Text = "[ Empty ]"
			nameL.TextColor3 = EMPTY
			rarityL.Text = ""
			earnL.Text = ""
		end
	end

	-- Update footer with totals
	local footer = panel:FindFirstChild("Footer") :: TextLabel?
	if footer then
		local clickAmount = totalPerTick * 2 -- CLICK_MULTIPLIER
		footer.Text = string.format("Total: %s/tick  \u{2022}  Click: +%s",
			formatMoney(totalPerTick), formatMoney(clickAmount))
		footer.TextColor3 = EMPTY
	end
end

-- ── Cash tween animation ──────────────────────────

-- Hidden NumberValue used as a tween target for smooth cash counting
local cashTweenValue = Instance.new("NumberValue")
cashTweenValue.Value = 0

local function updateCashLabelText(value: number)
	local label = getCashLabel()
	if label then
		label.Text = "Cash: $" .. formatNumber(math.floor(value))
	end
end

cashTweenValue.Changed:Connect(updateCashLabelText)

local function animateCash(fromValue: number, toValue: number)
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(cashTweenValue, tweenInfo, { Value = toValue })
	tween:Play()
end

-- ── Remote handlers ────────────────────────────────

local function onCashUpdated(newBalance: number, delta: number)
	local oldCash = currentCash
	currentCash = newBalance
	animateCash(oldCash, newBalance)
end

local function onMotorEquipped(motorId: string, unequippedGearIds: { string })
	currentMotorId = motorId
	-- Re-fetch full profile to stay in sync with server
	task.spawn(function()
		local data = GetPlayerData:InvokeServer()
		if data then
			currentEquippedGears = data.equippedGears
			currentOwnedGears = data.inventory.gears
			currentCash = data.cash
			updateMotorDisplay()
			updateGearSlots()
			onCashUpdated(currentCash, 0)
		end
	end)
end

local function onGearEquipped(gearUniqueId: string?, slotIndex: number)
	task.spawn(function()
		local data = GetPlayerData:InvokeServer()
		if data then
			currentEquippedGears = data.equippedGears
			currentOwnedGears = data.inventory.gears
			currentCash = data.cash
			updateMotorDisplay()
			updateGearSlots()
			onCashUpdated(currentCash, 0)
		end
	end)
end

local function onWelcomeBack(earnings: number)
	if earnings > 0 then
		print(string.format("Welcome back! You earned %s while away.", formatMoney(earnings)))
	end
end

-- ── Public API ─────────────────────────────────────

function HUDController.GetCurrentCash(): number
	return currentCash
end

function HUDController:Init()
	-- Build the HUD
	local playerGui = Player:WaitForChild("PlayerGui")
	buildHUD(playerGui)

	-- Wire remotes
	CashUpdated.OnClientEvent:Connect(onCashUpdated)
	WelcomeBack.OnClientEvent:Connect(onWelcomeBack)
	MotorEquipped.OnClientEvent:Connect(onMotorEquipped)
	GearEquipped.OnClientEvent:Connect(onGearEquipped)

	-- Fetch initial data
	task.spawn(function()
		local data = GetPlayerData:InvokeServer()
		if data then
			currentCash = data.cash
			currentMotorId = data.equippedMotor
			currentEquippedGears = data.equippedGears
			currentOwnedGears = data.inventory.gears
			updateMotorDisplay()
			updateGearSlots()
			onCashUpdated(currentCash, 0)
		end
	end)
end

return HUDController
