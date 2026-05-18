--!strict

-- Handles the unboxing UI flow: opening the box screen, initiating rolls,
-- and displaying results. Fires OpenBox remote on user confirm.
-- Builds a full-screen overlay with box cards and a results log.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BoxData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BoxData"))
local RarityData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenBoxRemote = Remotes:WaitForChild("OpenBox") :: RemoteEvent
local BoxOpenedRemote = Remotes:WaitForChild("BoxOpened") :: RemoteEvent
local GetPlayerData = Remotes:WaitForChild("GetPlayerData") :: RemoteFunction

local Player = Players.LocalPlayer
local UnboxController = {}

-- ── State ──────────────────────────────────────────
local currentCash: number = 0
local unboxGui: ScreenGui? = nil
local isOpen: boolean = false

-- ── Colors ─────────────────────────────────────────
local BG = Color3.fromRGB(20, 20, 30)
local FG = Color3.fromRGB(240, 240, 245)
local ACCENT = Color3.fromRGB(80, 160, 255)
local EMPTY = Color3.fromRGB(100, 100, 110)
local GREEN = Color3.fromRGB(80, 220, 80)
local RED = Color3.fromRGB(220, 80, 80)
local GOLD = Color3.fromRGB(255, 210, 90)

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

-- ── Factory helpers ────────────────────────────────

local function makeLabel(parent: Instance, name: string, text: string, sizeY: number, textSize: number, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text
	l.Font = font or Enum.Font.Gotham
	l.TextSize = textSize
	l.TextColor3 = color
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, -20, 0, sizeY)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function makeButton(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, color: Color3, onClick: () -> ()): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.TextColor3 = FG
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Size = size
	btn.Position = position
	btn.Parent = parent

	btn.MouseButton1Click:Connect(function()
		onClick()
	end)

	-- Hover effect
	btn.MouseEnter:Connect(function()
		btn.BackgroundTransparency = 0.15
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundTransparency = 0
	end)

	return btn
end

-- ── Build results popup ────────────────────────────

-- Show a temporary popup in the center of the screen for each unbox result
local function showResultPopup(result: any)
	if not unboxGui then return end

	local popup = Instance.new("Frame")
	popup.Name = "ResultPopup"
	popup.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
	popup.BorderSizePixel = 0
	popup.Size = UDim2.new(0, 280, 0, 80)
	popup.Position = UDim2.new(0.5, -140, 0.5, -40)
	popup.BackgroundTransparency = 1
	popup.Parent = unboxGui

	-- Rarity accent bar
	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.BorderSizePixel = 0
	local rColor = result.rarity and rarityColor(result.rarity) or ACCENT
	accentBar.BackgroundColor3 = rColor
	accentBar.Size = UDim2.new(0, 4, 1, 0)
	accentBar.Parent = popup

	local itemColor = result.rarity and rarityColor(result.rarity) or EMPTY

	local itemName = Instance.new("TextLabel")
	itemName.Name = "ItemName"
	itemName.Text = result.displayName
	itemName.Font = Enum.Font.GothamBold
	itemName.TextSize = 18
	itemName.TextColor3 = itemColor
	itemName.BackgroundTransparency = 1
	itemName.Position = UDim2.new(0, 14, 0, 8)
	itemName.Size = UDim2.new(1, -24, 0, 24)
	itemName.TextXAlignment = Enum.TextXAlignment.Left
	itemName.Parent = popup

	local typeLabel = Instance.new("TextLabel")
	if result.type == "gear" then
		typeLabel.Text = string.format("Tier %d  %s  \u{2709} %s", result.tier, result.itemId:upper(), result.rarity or "?")
	elseif result.duplicate then
		typeLabel.Text = string.format("Tier %d Motor (duplicate — +$%s)", result.tier, formatNumber(result.refundAmount or 0))
		typeLabel.TextColor3 = GOLD
	else
		typeLabel.Text = string.format("Tier %d Motor \u{2728} NEW!", result.tier)
		typeLabel.TextColor3 = GREEN
	end
	typeLabel.Font = Enum.Font.Gotham
	typeLabel.TextSize = 13
	typeLabel.TextColor3 = result.rarity and rarityColor(result.rarity) or EMPTY
	typeLabel.BackgroundTransparency = 1
	typeLabel.Position = UDim2.new(0, 14, 0, 34)
	typeLabel.Size = UDim2.new(1, -24, 0, 20)
	typeLabel.TextXAlignment = Enum.TextXAlignment.Left
	typeLabel.Parent = popup

	-- Animate in
	popup.Position = UDim2.new(0.5, -140, 0.45, -40)
	local tweenIn = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenOut = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local fadeIn = TweenService:Create(popup, tweenIn, { BackgroundTransparency = 0, Position = UDim2.new(0.5, -140, 0.5, -40) })
	fadeIn:Play()

	-- Auto-dismiss after 1.5 seconds
	task.delay(1.5, function()
		if not popup.Parent then return end
		local fadeOut = TweenService:Create(popup, tweenOut, { BackgroundTransparency = 1, Position = UDim2.new(0.5, -140, 0.55, -40) })
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			popup:Destroy()
		end)
	end)
end

-- ── Build results list ────────────────────────────

-- Show a scrolling list of all unboxed items (for batch opens)
local function showResultsList(results: { any })
	if not unboxGui then return end

	-- Close any existing results list
	local existing = unboxGui:FindFirstChild("ResultsPanel")
	if existing then existing:Destroy() end

	local panel = Instance.new("Frame")
	panel.Name = "ResultsPanel"
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(0, 600, 0, 300)
	panel.Position = UDim2.new(0.5, -300, 0.5, 60)
	panel.BackgroundTransparency = 0.15
	panel.Parent = unboxGui

	-- Header
	local header = Instance.new("TextLabel")
	header.Text = string.format("Opened %d items", #results)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 16
	header.TextColor3 = ACCENT
	header.BackgroundTransparency = 1
	header.Position = UDim2.new(0, 10, 0, 6)
	header.Size = UDim2.new(1, -20, 0, 24)
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = panel

	-- Close button for results
	local closeBtn = makeButton(panel, "CloseResults", "X", UDim2.new(0, 24, 0, 24), UDim2.new(1, -30, 0, 6), Color3.fromRGB(180, 60, 60), function()
		panel:Destroy()
	end)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16

	-- Scrolling list
	local list = Instance.new("ScrollingFrame")
	list.Name = "ItemList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 6, 0, 36)
	list.Size = UDim2.new(1, -12, 1, -42)
	list.CanvasSize = UDim2.new(0, 0, 0, #results * 28)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = ACCENT
	list.Parent = panel

	for i, result in ipairs(results) do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -8, 0, 26)
		row.Position = UDim2.new(0, 4, 0, (i - 1) * 28)
		row.Parent = list

		local itemColor = result.rarity and rarityColor(result.rarity) or EMPTY

		-- Rarity dot / accent
		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = itemColor
		dot.BorderSizePixel = 0
		dot.Size = UDim2.new(0, 3, 1, -4)
		dot.Position = UDim2.new(0, 0, 0, 2)
		dot.Parent = row

		-- Item label
		local label = Instance.new("TextLabel")
		label.Text = string.format("%s  %s", result.displayName, (result.rarity and ("(" .. result.rarity .. ")")) or "")
		if result.type == "motor" then
			if result.duplicate then
				label.Text = string.format("%s  (duplicate) +%s", result.displayName, formatMoney(result.refundAmount or 0))
			else
				label.Text = string.format("%s  \u{2728} NEW MOTOR!", result.displayName)
			end
		end
		label.Font = Enum.Font.Gotham
		label.TextSize = 14
		label.TextColor3 = itemColor
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 10, 0, 0)
		label.Size = UDim2.new(1, -80, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = row

		-- Type tag
		local tag = Instance.new("TextLabel")
		tag.Name = "Tag"
		tag.Text = result.type:upper()
		tag.Font = Enum.Font.GothamBold
		tag.TextSize = 10
		tag.TextColor3 = EMPTY
		tag.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
		tag.BorderSizePixel = 0
		tag.Size = UDim2.new(0, 48, 0, 18)
		tag.Position = UDim2.new(1, -56, 0, 4)
		tag.Parent = row

		-- Tier badge
		local tierTag = Instance.new("TextLabel")
		tierTag.Name = "Tier"
		if result.type == "gear" then
			tierTag.Text = "T" .. result.tier
		else
			tierTag.Text = "T" .. result.tier
		end
		tierTag.Font = Enum.Font.GothamBold
		tierTag.TextSize = 10
		tierTag.TextColor3 = itemColor
		tierTag.BackgroundTransparency = 1
		tierTag.Size = UDim2.new(0, 20, 1, 0)
		tierTag.Position = UDim2.new(1, -24, 0, 0)
		tierTag.Parent = row
	end
end

-- ── Box pool summary helper ───────────────────────

-- Format a one-line summary of what a box can contain
local function formatPoolSummary(boxDef: any): string
	local gearTiers: { number } = {}
	local motorTiers: { number } = {}
	for _, entry in ipairs(boxDef.contentsPool) do
		if entry.type == "gear" then
			table.insert(gearTiers, entry.tier)
		elseif entry.type == "motor" then
			table.insert(motorTiers, entry.tier)
		end
	end

	local parts: { string } = {}
	if #gearTiers > 0 then
		local tiers = {}
		for _, t in ipairs(gearTiers) do
			table.insert(tiers, "T" .. t)
		end
		table.insert(parts, "Gears: " .. table.concat(tiers, "/"))
	end
	if #motorTiers > 0 then
		local tiers = {}
		for _, t in ipairs(motorTiers) do
			table.insert(tiers, "T" .. t)
		end
		table.insert(parts, "Motors: " .. table.concat(tiers, "/"))
	end

	return table.concat(parts, "\n")
end

-- ── Build unbox screen ────────────────────────────

local function buildUnboxScreen(playerGui: PlayerGui)
	-- Destroy existing if any
	local existing = playerGui:FindFirstChild("UnboxGui")
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "UnboxGui"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = playerGui
	unboxGui = gui

	-- Fullscreen backdrop (click to close)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.Parent = gui

	backdrop.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			UnboxController.Hide()
		end
	end)

	-- Main panel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(0, 720, 0, 420)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Parent = gui

	-- Title bar
	local title = makeLabel(panel, "Title", "OPEN BOXES", 28, 22, ACCENT, Enum.Font.GothamBold)
	title.Position = UDim2.new(0, 14, 0, 10)
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- Close button (X) on panel
	local closeBtn = makeButton(panel, "CloseBtn", "\u{2715}", UDim2.new(0, 30, 0, 30), UDim2.new(1, -40, 0, 8), Color3.fromRGB(180, 60, 60), function()
		UnboxController.Hide()
	end)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18

	-- Box cards row
	local cardWidth = 128
	local cardGap = 12
	local boxes = BoxData.GetCatalogList()
	local totalWidth = #boxes * cardWidth + (#boxes - 1) * cardGap
	local startX = (720 - totalWidth) / 2

	local idx = 0
	for _, boxDef in ipairs(boxes) do
		idx += 1
		local cx = startX + (idx - 1) * (cardWidth + cardGap)

		-- Card frame
		local card = Instance.new("Frame")
		card.Name = "Card_" .. boxDef.id
		card.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
		card.BorderSizePixel = 0
		card.Size = UDim2.new(0, cardWidth, 0, 200)
		card.Position = UDim2.new(0, cx, 0, 50)
		card.Parent = panel

		-- Box name
		local nameL = makeLabel(card, "BoxName", boxDef.displayName, 22, 15, FG, Enum.Font.GothamBold)
		nameL.Position = UDim2.new(0, 6, 0, 6)
		nameL.Size = UDim2.new(1, -12, 0, 22)
		nameL.TextXAlignment = Enum.TextXAlignment.Center

		-- Cost
		local costL = makeLabel(card, "Cost", formatMoney(boxDef.cost), 18, 13, GOLD)
		costL.Position = UDim2.new(0, 6, 0, 30)
		costL.Size = UDim2.new(1, -12, 0, 18)
		costL.TextXAlignment = Enum.TextXAlignment.Center

		-- Separator
		local sep = Instance.new("Frame")
		sep.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
		sep.BorderSizePixel = 0
		sep.Size = UDim2.new(1, -16, 0, 1)
		sep.Position = UDim2.new(0, 8, 0, 54)
		sep.Parent = card

		-- Pool summary
		local pool = makeLabel(card, "Pool", formatPoolSummary(boxDef), 40, 11, EMPTY)
		pool.Position = UDim2.new(0, 6, 0, 60)
		pool.Size = UDim2.new(1, -12, 0, 40)
		pool.TextXAlignment = Enum.TextXAlignment.Center
		pool.TextWrapped = true

		-- Open buttons
		local btnY = 120
		local function makeOpenBtn(btnName: string, label: string, posX: number, width: number, qty: number)
			local canAfford = currentCash >= boxDef.cost * qty
			local btnColor = canAfford and ACCENT or Color3.fromRGB(60, 60, 70)
			local btn = makeButton(card, btnName, label,
				UDim2.new(0, width, 0, 26),
				UDim2.new(0, posX, 0, btnY),
				btnColor,
				function()
					if not canAfford then return end
					OpenBoxRemote:FireServer(boxDef.id, qty)
					UnboxController.Hide()
				end
			)
			btn.TextSize = 11
			btn.Font = Enum.Font.GothamBold
			return btn
		end

		makeOpenBtn("Open1", "\u{25B6} \u{00D7}1", 4, 38, 1)
		makeOpenBtn("Open10", "\u{25B6} \u{00D7}10", 45, 40, 10)
		makeOpenBtn("Open100", "\u{25B6} \u{00D7}100", 88, 38, 100)

		-- Refund note
		if boxDef.motorDuplicateRefund > 0 then
			local refund = makeLabel(card, "Refund", string.format("dupe refund: +%s", formatMoney(boxDef.motorDuplicateRefund)), 14, 10, EMPTY)
			refund.Position = UDim2.new(0, 4, 0, 170)
			refund.Size = UDim2.new(1, -8, 0, 14)
			refund.TextXAlignment = Enum.TextXAlignment.Center
		end
	end
end

-- Update affordability state on all box cards
local function refreshAffordability()
	if not unboxGui then return end
	local panel = unboxGui:FindFirstChild("Panel")
	if not panel then return end

	for _, boxDef in ipairs(BoxData.GetCatalogList()) do
		local card = panel:FindFirstChild("Card_" .. boxDef.id)
		if not card then continue end

		for _, qty in ipairs({ 1, 10, 100 }) do
			local btn = card:FindFirstChild("Open" .. qty)
			if not btn then continue end
			local canAfford = currentCash >= boxDef.cost * qty
			if canAfford then
				btn.BackgroundColor3 = ACCENT
				btn.TextTransparency = 0
				btn.Active = true
			else
				btn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
				btn.TextTransparency = 0.4
				btn.Active = false
			end
		end
	end
end

-- ── Remote handlers ────────────────────────────────

local function onBoxOpened(data: any)
	-- Update local cash from the server response
	if data.cashRemaining then
		currentCash = data.cashRemaining
	end

	-- Show individual popups for each result (with delay for visual feedback)
	local results = data.results or {}
	if #results > 0 then
		if #results <= 3 then
			-- For small batches, show popups one at a time
			for i, result in ipairs(results) do
				task.delay((i - 1) * 0.6, function()
					showResultPopup(result)
				end)
			end
		else
			-- For large batches, show the scrolling results list
			task.delay(0.3, function()
				showResultsList(results)
			end)
		end
	end
end

-- ── Public API ─────────────────────────────────────

function UnboxController.Show()
	if not unboxGui then return end
	isOpen = true

	-- Refresh cash state
	local data = GetPlayerData:InvokeServer()
	if data then
		currentCash = data.cash
	end

	refreshAffordability()
	unboxGui.Enabled = true
end

function UnboxController.Hide()
	if not unboxGui then return end
	isOpen = false

	-- Close any open results panel
	local resultsPanel = unboxGui:FindFirstChild("ResultsPanel")
	if resultsPanel then resultsPanel:Destroy() end

	-- Close any open popups
	for _, v in unboxGui:GetChildren() do
		if v.Name == "ResultPopup" then
			v:Destroy()
		end
	end

	unboxGui.Enabled = false
end

function UnboxController.Toggle()
	if isOpen then
		UnboxController.Hide()
	else
		UnboxController.Show()
	end
end

function UnboxController.UpdateCash(newCash: number)
	currentCash = newCash
	refreshAffordability()
end

function UnboxController:Init()
	-- Build UI
	local playerGui = Player:WaitForChild("PlayerGui")
	buildUnboxScreen(playerGui)

	-- Wire BoxOpened remote
	BoxOpenedRemote.OnClientEvent:Connect(onBoxOpened)

	-- Keyboard shortcut: B to toggle
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.B then
			UnboxController.Toggle()
		end
	end)
end

return UnboxController
