--!strict

-- Manages the inventory UI: displaying owned motors and gears,
-- equip/unequip actions, and reflecting server-side inventory state.
-- Toggle with the I key.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MotorData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MotorData"))
local GearData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GearData"))
local RarityData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EquipMotorRemote = Remotes:WaitForChild("EquipMotor") :: RemoteEvent
local EquipGearRemote = Remotes:WaitForChild("EquipGear") :: RemoteEvent
local UnequipGearRemote = Remotes:WaitForChild("UnequipGear") :: RemoteEvent
local MotorEquipped = Remotes:WaitForChild("MotorEquipped") :: RemoteEvent
local GearEquipped = Remotes:WaitForChild("GearEquipped") :: RemoteEvent
local BoxOpened = Remotes:WaitForChild("BoxOpened") :: RemoteEvent
local GetPlayerData = Remotes:WaitForChild("GetPlayerData") :: RemoteFunction

local Player = Players.LocalPlayer
local InventoryController = {}

--------------------
-- State          --
--------------------

local isOpen: boolean = false
local invGui: ScreenGui? = nil
local activeTab: string = "motors"

-- Cached server data (refreshed on Show and on events)
local currentCash: number = 0
local currentMotorId: string? = nil
local currentEquippedGears: { [number]: string } = {}
local currentOwnedMotors: { [string]: boolean } = {}
local currentOwnedGears: { [string]: any } = {}

-- UI element refs for tab switching
local motorsContainer: ScrollingFrame? = nil
local gearsContainer: ScrollingFrame? = nil
local motorsTabBtn: TextButton? = nil
local gearsTabBtn: TextButton? = nil

--------------------
-- Colors         --
--------------------

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

--------------------
-- Helpers        --
--------------------

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

	btn.MouseEnter:Connect(function()
		btn.BackgroundTransparency = 0.15
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundTransparency = 0
	end)

	return btn
end

--------------------
-- Data fetching  --
--------------------

local function refreshData()
	local ok, data = pcall(function()
		return GetPlayerData:InvokeServer()
	end)
	if not ok or not data then return end

	currentCash = data.cash or 0
	currentMotorId = data.equippedMotor
	currentEquippedGears = data.equippedGears or {}
	currentOwnedMotors = (data.inventory and data.inventory.motors) or {}
	currentOwnedGears = (data.inventory and data.inventory.gears) or {}
end

--------------------
-- Motors tab     --
--------------------

local function getSortedMotorIds(): { string }
	local ids: { string } = {}
	for id, _ in pairs(currentOwnedMotors) do
		table.insert(ids, id)
	end
	-- Sort by tier ascending (starter first)
	table.sort(ids, function(a, b)
		local defA = MotorData.GetMotor(a)
		local defB = MotorData.GetMotor(b)
		local tierA = defA and defA.tier or 99
		local tierB = defB and defB.tier or 99
		if tierA ~= tierB then return tierA < tierB end
		return a < b
	end)
	return ids
end

local function buildMotorsList(container: ScrollingFrame)
	-- Clear existing children
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local motorIds = getSortedMotorIds()

	if #motorIds == 0 then
		container.CanvasSize = UDim2.new(0, 0, 0, 60)
		local emptyL = makeLabel(container, "EmptyLabel", "No motors owned", 60, 18, EMPTY)
		emptyL.TextXAlignment = Enum.TextXAlignment.Center
		emptyL.Position = UDim2.new(0, 0, 0, 0)
		return
	end

	local CARD_W = 190
	local CARD_H = 110
	local GAP = 10
	local COLS = 3
	local rows = math.ceil(#motorIds / COLS)

	container.CanvasSize = UDim2.new(0, 0, 0, rows * (CARD_H + GAP) + GAP)

	for idx, motorId in ipairs(motorIds) do
		local def = MotorData.GetMotor(motorId)
		if not def then continue end

		local col = (idx - 1) % COLS
		local row = math.floor((idx - 1) / COLS)
		local x = GAP + col * (CARD_W + GAP)
		local y = GAP + row * (CARD_H + GAP)

		local card = Instance.new("Frame")
		card.Name = "MotorCard_" .. motorId
		card.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
		card.BorderSizePixel = 0
		card.Size = UDim2.new(0, CARD_W, 0, CARD_H)
		card.Position = UDim2.new(0, x, 0, y)
		card.Parent = container

		local nameL = makeLabel(card, "Name", def.displayName, 22, 15, FG, Enum.Font.GothamBold)
		nameL.Position = UDim2.new(0, 8, 0, 6)

		local isEquipped = currentMotorId == motorId
		local maxSlots = def.maxGearSlots or 1
		local statsText = string.format("T%d  \u{2022}  %.1f RPM  \u{2022}  %d slots (T%d max)", def.tier or 1, def.rpm or 1, maxSlots, def.maxGearTier or 1)
		local statsL = makeLabel(card, "Stats", statsText, 18, 11, EMPTY)
		statsL.Position = UDim2.new(0, 8, 0, 30)

		if isEquipped then
			local badge = makeLabel(card, "Status", "\u{2713} Equipped", 20, 13, GREEN, Enum.Font.GothamBold)
			badge.Position = UDim2.new(0, 8, 0, 80)
		else
			local btn = makeButton(card, "EquipBtn", "Equip",
				UDim2.new(0, 80, 0, 26),
				UDim2.new(0, CARD_W - 88, 0, 78),
				ACCENT,
				function()
					EquipMotorRemote:FireServer(motorId)
				end)
			btn.TextSize = 12
		end
	end
end

--------------------
-- Gears tab      --
--------------------

local function getSortedGearEntries(): { any }
	local entries: { any } = {}
	for uid, gear in pairs(currentOwnedGears) do
		local def = GearData.GetGear(gear.id)
		table.insert(entries, {
			uniqueId = uid,
			id = gear.id,
			tier = gear.tier,
			rarity = gear.rarity,
			rolledAt = gear.rolledAt,
			displayName = if def then def.displayName else gear.id,
		})
	end
	-- Sort by tier descending (best first)
	table.sort(entries, function(a, b)
		if a.tier ~= b.tier then return a.tier > b.tier end
		return a.uniqueId < b.uniqueId
	end)
	return entries
end

-- Find which slot a gear is equipped in, or nil
local function findEquippedSlot(uid: string): number?
	for slot, equippedUid in pairs(currentEquippedGears) do
		if equippedUid == uid then
			return slot
		end
	end
	return nil
end

-- Get the first free slot within the motor's maxGearSlots
local function getFirstFreeSlot(): number?
	local motorDef = currentMotorId and MotorData.GetMotor(currentMotorId)
	local maxSlots = motorDef and motorDef.maxGearSlots or 0
	if maxSlots == 0 then return nil end
	for slot = 1, maxSlots do
		if not currentEquippedGears[slot] then
			return slot
		end
	end
	return nil
end

local function buildGearsList(container: ScrollingFrame)
	-- Clear existing children
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local entries = getSortedGearEntries()

	if #entries == 0 then
		container.CanvasSize = UDim2.new(0, 0, 0, 60)
		local emptyL = makeLabel(container, "EmptyLabel", "No gears owned. Open boxes to find some!", 60, 18, EMPTY)
		emptyL.TextXAlignment = Enum.TextXAlignment.Center
		emptyL.Position = UDim2.new(0, 0, 0, 0)
		return
	end

	local ROW_H = 30
	container.CanvasSize = UDim2.new(0, 0, 0, #entries * ROW_H)

	local hasMotor = currentMotorId ~= nil and currentMotorId ~= ""
	local freeSlot = getFirstFreeSlot()

	for idx, entry in ipairs(entries) do
		local y = (idx - 1) * ROW_H

		local row = Instance.new("Frame")
		row.Name = "GearRow_" .. entry.uniqueId
		row.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -8, 0, ROW_H - 2)
		row.Position = UDim2.new(0, 4, 0, y)
		row.Parent = container

		local color = rarityColor(entry.rarity)

		-- Rarity accent dot
		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = color
		dot.BorderSizePixel = 0
		dot.Size = UDim2.new(0, 3, 1, -6)
		dot.Position = UDim2.new(0, 0, 0, 3)
		dot.Parent = row

		-- Gear name
		local nameL = makeLabel(row, "Name", entry.displayName, ROW_H, 14, FG)
		nameL.Position = UDim2.new(0, 10, 0, 0)
		nameL.Size = UDim2.new(0, 180, 1, 0)

		-- Rarity name
		local rarityName = "?"
		local rarityDef = RarityData.GetRarity(entry.rarity)
		if rarityDef then rarityName = rarityDef.displayName end
		local rarityL = makeLabel(row, "Rarity", rarityName, ROW_H, 12, color, Enum.Font.GothamBold)
		rarityL.Position = UDim2.new(0, 200, 0, 0)
		rarityL.Size = UDim2.new(0, 100, 1, 0)

		-- Tier badge
		local tierL = makeLabel(row, "Tier", "T" .. entry.tier, ROW_H, 12, EMPTY)
		tierL.Position = UDim2.new(0, 310, 0, 0)
		tierL.Size = UDim2.new(0, 30, 1, 0)

		-- State-dependent action area (right side)
		local equippedSlot = findEquippedSlot(entry.uniqueId)
		local actionX = 560
		local actionW = container.AbsoluteSize.X and math.max(0, container.AbsoluteSize.X - actionX - 16) or 140

		if equippedSlot then
			-- Show slot badge + Unequip button
			local slotL = makeLabel(row, "SlotBadge", "Slot " .. equippedSlot, ROW_H, 13, GREEN, Enum.Font.GothamBold)
			slotL.Position = UDim2.new(0, actionX, 0, 0)
			slotL.Size = UDim2.new(0, 50, 1, 0)

			local unequipBtn = makeButton(row, "UnequipBtn", "Unequip",
				UDim2.new(0, 72, 0, 22),
				UDim2.new(0, actionX + 56, 0, 4),
				Color3.fromRGB(180, 60, 60),
				function()
					UnequipGearRemote:FireServer(equippedSlot)
				end)
			unequipBtn.TextSize = 11

		elseif not hasMotor then
			-- No motor equipped — disable
			local noMotorL = makeLabel(row, "NoMotor", "No motor", ROW_H, 12, EMPTY)
			noMotorL.Position = UDim2.new(0, actionX, 0, 0)
			noMotorL.Size = UDim2.new(0, 80, 1, 0)

		elseif freeSlot then
			-- Equip button
			local slotForClosure = freeSlot
			local equipBtn = makeButton(row, "EquipBtn", "Equip",
				UDim2.new(0, 72, 0, 22),
				UDim2.new(0, actionX, 0, 4),
				ACCENT,
				function()
					EquipGearRemote:FireServer(entry.uniqueId, slotForClosure)
				end)
			equipBtn.TextSize = 11

		else
			-- All slots full
			local fullL = makeLabel(row, "FullLabel", "Full", ROW_H, 12, RED)
			fullL.Position = UDim2.new(0, actionX, 0, 0)
			fullL.Size = UDim2.new(0, 50, 1, 0)
		end
	end
end

--------------------
-- Tab switching  --
--------------------

local function switchTab(tab: string)
	activeTab = tab

	if motorsTabBtn then
		motorsTabBtn.TextColor3 = (tab == "motors") and ACCENT or EMPTY
	end
	if gearsTabBtn then
		gearsTabBtn.TextColor3 = (tab == "gears") and ACCENT or EMPTY
	end
	if motorsContainer then
		motorsContainer.Visible = (tab == "motors")
		if tab == "motors" then buildMotorsList(motorsContainer) end
	end
	if gearsContainer then
		gearsContainer.Visible = (tab == "gears")
		if tab == "gears" then buildGearsList(gearsContainer) end
	end
end

--------------------
-- Refresh UI     --
--------------------

local function refreshUI()
	-- Rebuild the active tab
	if activeTab == "motors" and motorsContainer then
		buildMotorsList(motorsContainer)
	elseif activeTab == "gears" and gearsContainer then
		buildGearsList(gearsContainer)
	end
end

--------------------
-- Build UI       --
--------------------

local function buildInventoryScreen(playerGui: PlayerGui)
	-- Destroy existing GUI if any
	local existing = playerGui:FindFirstChild("InventoryGui")
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryGui"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = playerGui
	invGui = gui

	-- Fullscreen backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.Parent = gui

	backdrop.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			InventoryController.Hide()
		end
	end)

	-- Main panel
	local PANEL_W = 660
	local PANEL_H = 460
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Parent = gui

	-- Title
	local title = makeLabel(panel, "Title", "INVENTORY", 28, 22, ACCENT, Enum.Font.GothamBold)
	title.Position = UDim2.new(0, 14, 0, 10)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Text = "\u{2715}"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = FG
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeBtn.BorderSizePixel = 0
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -40, 0, 8)
	closeBtn.Parent = panel
	closeBtn.MouseButton1Click:Connect(function()
		InventoryController.Hide()
	end)
	closeBtn.MouseEnter:Connect(function()
		closeBtn.BackgroundTransparency = 0.15
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.BackgroundTransparency = 0
	end)

	-- Tab bar
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
	tabBar.BorderSizePixel = 0
	tabBar.Size = UDim2.new(1, -20, 0, 32)
	tabBar.Position = UDim2.new(0, 10, 0, 44)
	tabBar.Parent = panel

	-- Motors tab button
	local motorsTab = Instance.new("TextButton")
	motorsTab.Name = "MotorsTab"
	motorsTab.Text = "MOTORS"
	motorsTab.Font = Enum.Font.GothamBold
	motorsTab.TextSize = 14
	motorsTab.TextColor3 = ACCENT
	motorsTab.BackgroundTransparency = 1
	motorsTab.BorderSizePixel = 0
	motorsTab.Size = UDim2.new(0, 120, 1, 0)
	motorsTab.Position = UDim2.new(0, 0, 0, 0)
	motorsTab.Parent = tabBar
	motorsTab.MouseButton1Click:Connect(function()
		switchTab("motors")
	end)
	motorsTabBtn = motorsTab

	-- Gears tab button
	local gearsTab = Instance.new("TextButton")
	gearsTab.Name = "GearsTab"
	gearsTab.Text = "GEARS"
	gearsTab.Font = Enum.Font.GothamBold
	gearsTab.TextSize = 14
	gearsTab.TextColor3 = EMPTY
	gearsTab.BackgroundTransparency = 1
	gearsTab.BorderSizePixel = 0
	gearsTab.Size = UDim2.new(0, 120, 1, 0)
	gearsTab.Position = UDim2.new(0, 120, 0, 0)
	gearsTab.Parent = tabBar
	gearsTab.MouseButton1Click:Connect(function()
		switchTab("gears")
	end)
	gearsTabBtn = gearsTab

	-- Content area dimensions
	local contentY = 86
	local contentH = PANEL_H - contentY - 14

	-- Motors container (visible by default)
	local motorsScroll = Instance.new("ScrollingFrame")
	motorsScroll.Name = "MotorsContainer"
	motorsScroll.BackgroundTransparency = 1
	motorsScroll.BorderSizePixel = 0
	motorsScroll.Position = UDim2.new(0, 10, 0, contentY)
	motorsScroll.Size = UDim2.new(1, -20, 0, contentH)
	motorsScroll.CanvasSize = UDim2.new(0, 0, 0, 100)
	motorsScroll.ScrollBarThickness = 6
	motorsScroll.ScrollBarImageColor3 = ACCENT
	motorsScroll.Parent = panel
	motorsContainer = motorsScroll

	-- Gears container (hidden by default)
	local gearsScroll = Instance.new("ScrollingFrame")
	gearsScroll.Name = "GearsContainer"
	gearsScroll.BackgroundTransparency = 1
	gearsScroll.BorderSizePixel = 0
	gearsScroll.Position = UDim2.new(0, 10, 0, contentY)
	gearsScroll.Size = UDim2.new(1, -20, 0, contentH)
	gearsScroll.CanvasSize = UDim2.new(0, 0, 0, 100)
	gearsScroll.ScrollBarThickness = 6
	gearsScroll.ScrollBarImageColor3 = ACCENT
	gearsScroll.Visible = false
	gearsScroll.Parent = panel
	gearsContainer = gearsScroll
end

--------------------
-- Remote handlers--
--------------------

local function onBoxOpened(data: any)
	refreshData()
	if isOpen then refreshUI() end
end

local function onMotorEquipped(motorId: string, unequippedGearIds: { string })
	refreshData()
	if isOpen then refreshUI() end
end

local function onGearEquipped(gearUniqueId: string?, slotIndex: number)
	refreshData()
	if isOpen then refreshUI() end
end

--------------------
-- Public API     --
--------------------

function InventoryController.Show()
	if not invGui then return end
	isOpen = true
	refreshData()
	switchTab(activeTab)
	invGui.Enabled = true
end

function InventoryController.Hide()
	if not invGui then return end
	isOpen = false
	invGui.Enabled = false
end

function InventoryController.Toggle()
	if isOpen then
		InventoryController.Hide()
	else
		InventoryController.Show()
	end
end

function InventoryController:Init()
	local playerGui = Player:WaitForChild("PlayerGui")
	buildInventoryScreen(playerGui)

	-- Wire remotes
	BoxOpened.OnClientEvent:Connect(onBoxOpened)
	MotorEquipped.OnClientEvent:Connect(onMotorEquipped)
	GearEquipped.OnClientEvent:Connect(onGearEquipped)

	-- Keyboard shortcut: I to toggle
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.I then
			InventoryController.Toggle()
		end
	end)

	-- Preload data
	refreshData()
end

return InventoryController
