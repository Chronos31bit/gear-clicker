--!strict

-- CSGO-style case opening reveal animation.
-- Handles the spinning "slot" effect, glow reveal, and batch sequencing.
-- All animations use TweenService + task.delay (no RenderStepped / while-loops).

local TweenService = game:GetService("TweenService")

--------------------
-- Types          --
--------------------

export type FakeItem = {
	displayName: string,
	rarity: string,
	rarityColor: Color3,
	type: "gear" | "motor",
	tier: number,
	isFinal: boolean,
}

--------------------
-- Colors         --
--------------------

local BG = Color3.fromRGB(20, 20, 30)
local FG = Color3.fromRGB(240, 240, 245)
local ACCENT = Color3.fromRGB(80, 160, 255)
local EMPTY = Color3.fromRGB(100, 100, 110)
local GREEN = Color3.fromRGB(80, 220, 80)
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

--------------------
-- State          --
--------------------

local UnboxRevealController = {}
local revealActive: boolean = false
local activeTweens: { Tween } = {}
local activeTimers: { thread } = {}

--------------------
-- Fake item generation --
--------------------

local FAKE_GEAR_NAMES = { "Plastic Cog", "Iron Gear", "Steel Pinion", "Brass Sprocket", "Titanium Hub", "Copper Ring", "Crank Shaft", "Ratchet Wheel" }
local FAKE_MOTOR_NAMES = { "Rusty Spindle", "Iron Rotor", "Coil Winder", "Flux Core", "Torque Hub", "Piston Head", "Cam Shaft", "Drive Axle" }

local function getSpinRarity(): string
	local roll = math.random()
	if roll < 0.55 then return "Common"
	elseif roll < 0.78 then return "Chilly"
	elseif roll < 0.92 then return "Oily"
	elseif roll < 0.97 then return "Glowing"
	elseif roll < 0.99 then return "Static"
	elseif roll < 0.998 then return "Molten"
	else return "Frostbitten" end
end

local function generateFakeItem(): FakeItem
	local isGear = math.random() < 0.7
	local rar = getSpinRarity()
	local names = isGear and FAKE_GEAR_NAMES or FAKE_MOTOR_NAMES
	local name = names[math.random(#names)]

	return {
		displayName = name,
		rarity = rar,
		rarityColor = RARITY_COLORS[rar] or EMPTY,
		type = if isGear then "gear" else "motor",
		tier = math.random(1, 5),
		isFinal = false,
	}
end

--------------------
-- Tween tracking --
--------------------

local function trackTween(tween: Tween)
	table.insert(activeTweens, tween)
	tween.Completed:Connect(function()
		for i, t in ipairs(activeTweens) do
			if t == tween then
				table.remove(activeTweens, i)
				break
			end
		end
	end)
end

local function cancelAllTweens()
	for _, tween in ipairs(activeTweens) do
		tween:Cancel()
	end
	activeTweens = {}
end

--------------------
-- Slot UI         --
--------------------

-- Creates the slot machine frame and all child elements
local function createSlotOverlay(unboxGui: ScreenGui): { Frame, { [string]: Instance } }
	if revealActive then return nil, {} end

	-- Fullscreen overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "RevealOverlay"
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.ZIndex = 10
	overlay.Parent = unboxGui

	-- Click catcher (blocks interaction with unbox panel)
	local catcher = Instance.new("Frame")
	catcher.Name = "ClickCatcher"
	catcher.BackgroundTransparency = 1
	catcher.BorderSizePixel = 0
	catcher.Size = UDim2.new(1, 0, 1, 0)
	catcher.ZIndex = overlay.ZIndex
	catcher.Parent = overlay

	-- Slot container
	local slot = Instance.new("Frame")
	slot.Name = "SlotContainer"
	slot.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.Size = UDim2.new(0, 300, 0, 120)
	slot.Position = UDim2.new(0.5, -150, 0.5, -60)
	slot.ZIndex = overlay.ZIndex + 1
	slot.Parent = overlay

	-- Rarity border (accent bar at top)
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.BackgroundColor3 = ACCENT
	accentBar.BackgroundTransparency = 1
	accentBar.BorderSizePixel = 0
	accentBar.Size = UDim2.new(1, 0, 0, 3)
	accentBar.ZIndex = slot.ZIndex + 1
	accentBar.Parent = slot

	-- Item name label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Text = ""
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 24
	nameLabel.TextColor3 = FG
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, -20, 0, 34)
	nameLabel.Position = UDim2.new(0, 10, 0, 12)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.ZIndex = slot.ZIndex + 1
	nameLabel.Parent = slot

	-- Type / tier / rarity info label
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "ItemInfo"
	infoLabel.Text = ""
	infoLabel.Font = Enum.Font.Gotham
	infoLabel.TextSize = 14
	infoLabel.TextColor3 = EMPTY
	infoLabel.BackgroundTransparency = 1
	infoLabel.Size = UDim2.new(1, -20, 0, 22)
	infoLabel.Position = UDim2.new(0, 10, 0, 50)
	infoLabel.TextXAlignment = Enum.TextXAlignment.Center
	infoLabel.ZIndex = slot.ZIndex + 1
	infoLabel.Parent = slot

	-- Tier badge
	local tierBadge = Instance.new("TextLabel")
	tierBadge.Name = "TierBadge"
	tierBadge.Text = ""
	tierBadge.Font = Enum.Font.GothamBold
	tierBadge.TextSize = 12
	tierBadge.TextColor3 = EMPTY
	tierBadge.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
	tierBadge.BorderSizePixel = 0
	tierBadge.Size = UDim2.new(0, 32, 0, 20)
	tierBadge.Position = UDim2.new(0.5, -16, 0, 76)
	tierBadge.ZIndex = slot.ZIndex + 1
	tierBadge.Parent = slot

	local elements = {
		overlay = overlay,
		catcher = catcher,
		slot = slot,
		accentBar = accentBar,
		nameLabel = nameLabel,
		infoLabel = infoLabel,
		tierBadge = tierBadge,
	}

	return overlay, elements
end

--------------------
-- Glow effects    --
--------------------

-- Create pulsing rarity glow layers around the slot
local function createGlow(container: Frame, rarityColor: Color3)
	local layers: { Frame } = {}
	for i = 1, 3 do
		local layer = Instance.new("Frame")
		layer.Name = "GlowLayer" .. i
		layer.BackgroundColor3 = rarityColor
		layer.BackgroundTransparency = 0.5 + (i - 1) * 0.2
		layer.BorderSizePixel = 0
		local padding = 6 + (i - 1) * 8
		layer.Size = UDim2.new(1, padding * 2, 1, padding * 2)
		layer.Position = UDim2.new(0.5, -padding, 0.5, -padding)
		layer.AnchorPoint = Vector2.new(0.5, 0.5)
		layer.ZIndex = container.ZIndex - i
		layer.Parent = container
		table.insert(layers, layer)

		local tween = TweenService:Create(layer,
			TweenInfo.new(0.6 + i * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.1, Size = UDim2.new(1, padding * 4, 1, padding * 4) })
		tween:Play()
		trackTween(tween)
	end
	return layers
end

-- Expand-and-fade burst on final reveal
local function playRevealBurst(container: Frame, rarityColor: Color3)
	local burst = Instance.new("Frame")
	burst.Name = "RevealBurst"
	burst.BackgroundColor3 = rarityColor
	burst.BackgroundTransparency = 0.7
	burst.BorderSizePixel = 0
	burst.Size = UDim2.new(1, 0, 1, 0)
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.new(0.5, 0, 0.5, 0)
	burst.ZIndex = container.ZIndex + 2
	burst.Parent = container

	local tween = TweenService:Create(burst,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 80, 1, 80), BackgroundTransparency = 1 })
	tween:Play()
	trackTween(tween)
	tween.Completed:Connect(function() burst:Destroy() end)
end

-- Scale bounce for the item name on reveal
local function playNameBounce(nameLabel: TextLabel)
	local originalSize = nameLabel.TextSize
	local tween = TweenService:Create(nameLabel,
		TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = originalSize * 1.35 })
	tween:Play()
	trackTween(tween)
	tween.Completed:Connect(function()
		local tween2 = TweenService:Create(nameLabel,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextSize = originalSize })
		tween2:Play()
		trackTween(tween2)
	end)
end

--------------------
-- Slot display    --
--------------------

local function updateSlotDisplay(elements: { [string]: Instance }, fakeItem: FakeItem)
	elements.nameLabel.Text = fakeItem.displayName
	elements.nameLabel.TextColor3 = fakeItem.rarityColor
	elements.accentBar.BackgroundColor3 = fakeItem.rarityColor

	local typeText = fakeItem.type == "gear" and "GEAR" or "MOTOR"
	elements.infoLabel.Text = string.format("%s  \u{00B7}  T%d  \u{00B7}  %s", typeText, fakeItem.tier, fakeItem.rarity)
	elements.infoLabel.TextColor3 = fakeItem.rarityColor
	elements.tierBadge.Text = "T" .. fakeItem.tier
	elements.tierBadge.TextColor3 = fakeItem.rarityColor
end

local function setFinalDisplay(elements: { [string]: Instance }, result: any)
	local rarity: string = (if result.type == "gear" then result.rarity else "MOTOR") :: string
	local color: Color3 = if result.type == "gear" and result.rarity then (RARITY_COLORS[result.rarity] or EMPTY) elseif result.duplicate then GOLD else GREEN
	local displayName: string = result.displayName
	local tier: number = result.tier
	local typeStr: string = result.type:upper()
	local rarityStr: string = (if result.type == "gear" then (result.rarity or "?") else "") :: string

	elements.nameLabel.Text = displayName
	elements.nameLabel.TextColor3 = color
	elements.accentBar.BackgroundColor3 = color

	if result.type == "gear" then
		elements.infoLabel.Text = string.format("%s  \u{00B7}  T%d  \u{00B7}  %s", typeStr, tier, rarityStr)
		elements.infoLabel.TextColor3 = color
	elseif result.duplicate then
		elements.infoLabel.Text = string.format("DUPLICATE  +%s", result.refundAmount and string.format("$%d", result.refundAmount) or "")
		elements.infoLabel.TextColor3 = GOLD
	else
		elements.infoLabel.Text = string.format("%s  \u{00B7}  T%d  \u{2728} NEW!", typeStr, tier)
		elements.infoLabel.TextColor3 = GREEN
	end
	elements.tierBadge.Text = "T" .. tier
	elements.tierBadge.TextColor3 = color
end

--------------------
-- Hold duration  --
--------------------

local function getHoldDuration(result: any): number
	local rar = result.rarity
	if not rar then return 1.0 end
	local holdTimes: { [string]: number } = {
		Common = 0.6, Chilly = 0.8, Oily = 1.0,
		Glowing = 1.3, Static = 1.5, Molten = 1.8,
		Frostbitten = 2.2, Radiant = 2.8, Eclipsed = 3.5,
		Mythical = 4.5,
	}
	return holdTimes[rar] or 1.0
end

--------------------
-- Spin animation  --
--------------------

local function playSpinCycle(elements: { [string]: Instance }, result: any, onComplete: () -> ())
	-- Phase 1: Fast spin (0.6s)
	local fastEnd = os.clock() + 0.6
	local function fastTick()
		if not revealActive or os.clock() >= fastEnd then
			if revealActive then slowTick() end
			return
		end
		updateSlotDisplay(elements, generateFakeItem())
		local timer = task.delay(0.04 + math.random() * 0.02, fastTick)
		table.insert(activeTimers, timer)
	end

	-- Phase 2: Slow spin (0.5s)
	local slowStart = os.clock()
	local function slowTick()
		if not revealActive then return end
		local elapsed = os.clock() - slowStart
		if elapsed >= 0.5 then
			if revealActive then finalPass(0) end
			return
		end
		updateSlotDisplay(elements, generateFakeItem())
		local delay = 0.08 + (elapsed / 0.5) * 0.2
		local timer = task.delay(delay, slowTick)
		table.insert(activeTimers, timer)
	end

	-- Phase 3: Final pass — 3 near-miss items before reveal
	local function finalPass(step: number)
		if not revealActive then return end
		if step >= 3 then
			doReveal()
			return
		end
		updateSlotDisplay(elements, generateFakeItem())
		local delays = { 0.1, 0.2, 0.35 }
		local timer = task.delay(delays[step + 1], function() finalPass(step + 1) end)
		table.insert(activeTimers, timer)
	end

	-- Phase 4: Reveal
	local function doReveal()
		if not revealActive then return end

		setFinalDisplay(elements, result)
		playNameBounce(elements.nameLabel :: TextLabel)

		local slot = elements.slot
		-- Rarity glow
		local color = if result.type == "gear" and result.rarity then RARITY_COLORS[result.rarity] elseif result.duplicate then GOLD else GREEN
		createGlow(slot, color)
		playRevealBurst(slot, color)

		-- Hold for rarity-scaled duration, then finish
		local holdTime = getHoldDuration(result)
		local timer = task.delay(holdTime, onComplete)
		table.insert(activeTimers, timer)
	end

	fastTick()
end

--------------------
-- Batch sequencing--
--------------------

-- Compressed spin for batch opens (~0.9s per item)
local function playCompressedSpin(elements: { [string]: Instance }, result: any, onComplete: () -> ())
	local fastEnd = os.clock() + 0.3
	local function fastTick()
		if not revealActive or os.clock() >= fastEnd then
			if revealActive then slowTick() end
			return
		end
		updateSlotDisplay(elements, generateFakeItem())
		local timer = task.delay(0.05, fastTick)
		table.insert(activeTimers, timer)
	end

	local slowStart = os.clock()
	local function slowTick()
		if not revealActive then return end
		if os.clock() - slowStart >= 0.3 then
			if revealActive then doReveal() end
			return
		end
		updateSlotDisplay(elements, generateFakeItem())
		local timer = task.delay(0.08 + (os.clock() - slowStart) * 0.3, slowTick)
		table.insert(activeTimers, timer)
	end

	local function doReveal()
		if not revealActive then return end
		setFinalDisplay(elements, result)
		playNameBounce(elements.nameLabel :: TextLabel)
		local color = if result.type == "gear" and result.rarity then RARITY_COLORS[result.rarity] elseif result.duplicate then GOLD else GREEN
		playRevealBurst(elements.slot, color)
		local timer = task.delay(0.4, onComplete)
		table.insert(activeTimers, timer)
	end

	fastTick()
end

-- Fade in the overlay
local function fadeInOverlay(overlay: Frame): ()
	local tween = TweenService:Create(overlay,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.5 })
	tween:Play()
	trackTween(tween)
end

-- Fade out and destroy the overlay
local function fadeOutOverlay(overlay: Frame, onDone: () -> ())
	local tween = TweenService:Create(overlay,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 })
	tween:Play()
	trackTween(tween)
	tween.Completed:Connect(function()
		overlay:Destroy()
		if onDone then onDone() end
	end)
end

--------------------
-- Public API      --
--------------------

-- Cancel any active reveal animation and clean up
function UnboxRevealController.CancelReveal()
	revealActive = false
	cancelAllTweens()
	for _, timer in ipairs(activeTimers) do
		task.cancel(timer)
	end
	activeTimers = {}
end

-- Play the reveal animation for a batch of results
-- @param results - array of RollResult tables from the server
-- @param unboxGui - the ScreenGui to parent the overlay into
-- @param onBatchDone - callback when all individual reveals + hold completes
function UnboxRevealController.PlayReveals(results: { any }, unboxGui: ScreenGui, onBatchDone: () -> ())
	if #results == 0 then
		if onBatchDone then onBatchDone() end
		return
	end

	CancelReveal()
	revealActive = true

	-- Create the slot overlay
	local overlay, elements = createSlotOverlay(unboxGui)
	if not overlay then
		revealActive = false
		if onBatchDone then onBatchDone() end
		return
	end

	fadeInOverlay(overlay)

	if #results == 1 then
		-- Full animation, single item
		playSpinCycle(elements, results[1], function()
			if not revealActive then return end
			fadeOutOverlay(overlay, function()
				revealActive = false
				if onBatchDone then onBatchDone() end
			end)
		end)

	elseif #results <= 10 then
		-- Compressed individual reveals, then results grid
		local currentIndex = 0
		local function revealNext()
			currentIndex += 1
			if currentIndex > #results then
				if not revealActive then return end
				-- Keep overlay briefly, then fade
				local timer = task.delay(0.5, function()
					if not revealActive then return end
					fadeOutOverlay(overlay, function()
						revealActive = false
						if onBatchDone then onBatchDone() end
					end)
				end)
				table.insert(activeTimers, timer)
				return
			end
			if not revealActive then return end

			-- Don't recreate slot — reuse existing elements
			playCompressedSpin(elements, results[currentIndex], function()
				if not revealActive then return end
				-- Brief gap, then next item
				local timer = task.delay(0.2, revealNext)
				table.insert(activeTimers, timer)
			end)
		end
		revealNext()

	else
		-- 100x batch: show a brief progress-style animation, then grid
		-- Update slot to show "Opening..."
		elements.nameLabel.Text = "OPENING"
		elements.nameLabel.TextColor3 = ACCENT
		elements.accentBar.BackgroundColor3 = ACCENT
		elements.infoLabel.Text = string.format("%d items...", #results)

		local timer = task.delay(1.5, function()
			if not revealActive then return end
			fadeOutOverlay(overlay, function()
				revealActive = false
				if onBatchDone then onBatchDone() end
			end)
		end)
		table.insert(activeTimers, timer)
	end
end

return UnboxRevealController
