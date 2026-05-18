--!strict

-- Admin debugging panel for Studio testing.
-- Press F2 to toggle. Shows quick-action buttons for cash and boxes.
-- Only activates in Studio mode (RunService:IsStudio()).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local AdminController = {}

local isOpen: boolean = false
local adminGui: ScreenGui? = nil

-- ── Colors ─────────────────────────────────────────
local BG = Color3.fromRGB(20, 20, 30)
local FG = Color3.fromRGB(240, 240, 245)
local ACCENT = Color3.fromRGB(80, 160, 255)
local GREEN = Color3.fromRGB(80, 220, 80)
local GOLD = Color3.fromRGB(255, 210, 90)
local RED = Color3.fromRGB(200, 70, 70)

-- Resolve the AdminCommand remote
local AdminCommand: RemoteEvent? = nil

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

local function ensureRemote()
	if AdminCommand then return end
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local found = remotes:FindFirstChild("AdminCommand")
	if found then
		AdminCommand = found :: RemoteEvent
	end
end

local function fireCmd(command: string, ...: any)
	ensureRemote()
	if AdminCommand then
		AdminCommand:FireServer(command, ...)
	end
end

-- ── UI building ──────────────────────────────────

local function makeLabel(parent: Instance, name: string, text: string, sizeY: number, textSize: number, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = textSize
	l.TextColor3 = color
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, -16, 0, sizeY)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function makeBtn(parent: Instance, name: string, text: string, sizeX: number, posX: number, posY: number, color: Color3, onClick: () -> ()): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextColor3 = FG
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Size = UDim2.new(0, sizeX, 0, 28)
	btn.Position = UDim2.new(0, posX, 0, posY)
	btn.Parent = parent
	btn.MouseButton1Click:Connect(onClick)
	return btn
end

local function buildUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminGui"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = Player:WaitForChild("PlayerGui")
	adminGui = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(0, 320, 0, 280)
	panel.Position = UDim2.new(0, 16, 0, 420)
	panel.Parent = gui

	-- Title
	local title = makeLabel(panel, "Title", "ADMIN (Studio Only)", 24, 16, GOLD, true)
	title.Position = UDim2.new(0, 8, 0, 6)

	-- Cash commands row
	local cashHeader = makeLabel(panel, "CashHeader", "── Cash ──", 18, 12, ACCENT)
	cashHeader.Position = UDim2.new(0, 8, 0, 32)

	makeBtn(panel, "Cash1k", "+$1,000", 72, 8, 52, GREEN, function()
		fireCmd("cash", 1000)
	end)
	makeBtn(panel, "Cash10k", "+$10,000", 72, 86, 52, GREEN, function()
		fireCmd("cash", 10000)
	end)
	makeBtn(panel, "Cash100k", "+$100,000", 72, 164, 52, GREEN, function()
		fireCmd("cash", 100000)
	end)
	makeBtn(panel, "Cash1m", "+$1,000,000", 72, 242, 52, GREEN, function()
		fireCmd("cash", 1000000)
	end)

	-- Box commands
	local boxHeader = makeLabel(panel, "BoxHeader", "── Boxes (grants cash to buy) ──", 18, 12, ACCENT)
	boxHeader.Position = UDim2.new(0, 8, 0, 86)

	makeBtn(panel, "BoxBasic", "Basic Box", 96, 8, 106, ACCENT, function()
		fireCmd("box", "box_basic", 1)
	end)
	makeBtn(panel, "BoxPremium", "Premium Box", 96, 110, 106, ACCENT, function()
		fireCmd("box", "box_premium", 1)
	end)
	makeBtn(panel, "BoxExotic", "Exotic Box", 96, 212, 106, ACCENT, function()
		fireCmd("box", "box_exotic", 1)
	end)

	makeBtn(panel, "BoxVoid", "Void Box", 96, 8, 138, ACCENT, function()
		fireCmd("box", "box_void", 1)
	end)
	makeBtn(panel, "BoxCelestial", "Celestial Box", 96, 110, 138, ACCENT, function()
		fireCmd("box", "box_celestial", 1)
	end)
	makeBtn(panel, "AllBoxes", "One of Each", 96, 212, 138, ACCENT, function()
		fireCmd("allboxes")
	end)

	-- Utility commands
	local utilHeader = makeLabel(panel, "UtilHeader", "── Utilities ──", 18, 12, ACCENT)
	utilHeader.Position = UDim2.new(0, 8, 0, 172)

	makeBtn(panel, "Reset", "Reset Profile", 144, 8, 192, RED, function()
		fireCmd("reset")
	end)
	makeBtn(panel, "Save", "Save Now", 144, 158, 192, ACCENT, function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local reqSave = remotes:FindFirstChild("RequestSave")
		if reqSave then
			reqSave:FireServer()
		end
	end)

	-- Note
	local note = makeLabel(panel, "Note", "F2 to toggle  \u{2022}  Studio only", 16, 10, Color3.fromRGB(120, 120, 130))
	note.Position = UDim2.new(0, 8, 0, 230)
end

-- ── Toggle ───────────────────────────────────────

function AdminController.Toggle()
	if not adminGui then return end
	isOpen = not isOpen
	adminGui.Enabled = isOpen
end

function AdminController:Init()
	if not RunService:IsStudio() then
		print("[AdminController] Not in Studio — admin panel disabled")
		return
	end

	buildUI()

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.F2 then
			AdminController.Toggle()
		end
	end)

	print("[AdminController] Initialized (F2 to toggle)")
end

return AdminController
