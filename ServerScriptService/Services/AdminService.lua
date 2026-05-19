--!strict

-- Admin command service for Studio testing.
-- Only processes commands when the server is running in Studio (RunService:IsStudio()).
-- All commands are server-authoritative: the client sends a command name + args,
-- the server validates and performs the action.
--
-- Available commands (sent via AdminCommand RemoteEvent):
--   cash <amount>          — give the player cash
--   box <boxId> [quantity] — give free boxes (default 1)
--   reset                  — reset to starter profile

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local PlayerDataService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("PlayerDataService"))
local BoxData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BoxData"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local AdminCommand: RemoteEvent? = nil
local CashUpdatedRemote: RemoteEvent? = nil

local AdminService = {}

local function ensureRemote()
	if AdminCommand then return end
	local found = Remotes:FindFirstChild("AdminCommand")
	if found then
		AdminCommand = found :: RemoteEvent
	else
		local newRemote = Instance.new("RemoteEvent")
		newRemote.Name = "AdminCommand"
		newRemote.Parent = Remotes
		AdminCommand = newRemote :: RemoteEvent
		print("[AdminService] Created AdminCommand RemoteEvent")
	end

	-- Also grab CashUpdated so we can push HUD updates to the client
	if not CashUpdatedRemote then
		CashUpdatedRemote = Remotes:FindFirstChild("CashUpdated") :: RemoteEvent?
		if CashUpdatedRemote then
			print("[AdminService] CashUpdated remote resolved")
		else
			warn("[AdminService] CashUpdated remote NOT FOUND — HUD will not update")
		end
	end
end

-- Notify the client that their cash changed, so the HUD updates immediately
local function notifyCashChanged(player: Player)
	if not CashUpdatedRemote then
		warn("[AdminService] notifyCashChanged: CashUpdatedRemote is nil, cannot notify client")
		return
	end
	local profile = PlayerDataService:GetProfile(player)
	if not profile then
		warn("[AdminService] notifyCashChanged: no profile for " .. player.Name)
		return
	end
	CashUpdatedRemote:FireClient(player, profile.cash, 0)
	print(string.format("[AdminService] Fired CashUpdated for %s: $%s", player.Name, tostring(profile.cash)))
end

-- ── Command handlers ──────────────────────────────

local function handleCash(player: Player, amountStr: string)
	local amount = tonumber(amountStr)
	if not amount or amount <= 0 then
		warn(string.format("[Admin] %s: invalid cash amount %q", player.Name, amountStr))
		return
	end
	PlayerDataService.AddCash(player, amount)
	notifyCashChanged(player)
	print(string.format("[Admin] %s: +$%s", player.Name, amountStr))
end

local function handleBox(player: Player, boxId: string, qtyStr: string?)
	local boxDef = BoxData.GetBox(boxId)
	if not boxDef then
		warn(string.format("[Admin] %s: unknown box %q", player.Name, boxId))
		return
	end
	local qty = math.clamp(tonumber(qtyStr) or 1, 1, 100)

	local cost = boxDef.cost * qty
	PlayerDataService.AddCash(player, cost)
	notifyCashChanged(player)
	print(string.format("[Admin] %s: granted $%d to buy %d x %q", player.Name, cost, qty, boxId))
end

local function handleReset(player: Player)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then return end

	profile.cash = GameConfig.STARTING_CASH or 0
	profile.equippedMotor = "motor_rusty"
	profile.equippedGears = {}
	profile.inventory.motors = { ["motor_rusty"] = true }
	profile.inventory.gears = {}
	profile.stats.totalEarned = 0
	profile.stats.boxesOpened = 0
	notifyCashChanged(player)
	print(string.format("[Admin] %s: profile reset", player.Name))
end

local function handleAllBoxes(player: Player)
	local boxes = BoxData.GetCatalogList()
	local total = 0
	for _, boxDef in ipairs(boxes) do
		total += boxDef.cost
	end
	PlayerDataService.AddCash(player, total)
	notifyCashChanged(player)
	print(string.format("[Admin] %s: granted $%d to buy one of every box", player.Name, total))
end

-- ── Remote handler ────────────────────────────────

local function onAdminCommand(player: Player, command: any, ...: any)
	if not RunService:IsStudio() then
		warn("[Admin] Admin commands only work in Studio")
		return
	end

	if typeof(command) ~= "string" then
		warn(string.format("[Admin] %s: invalid command type %s", player.Name, typeof(command)))
		return
	end

	local args = { ... }
	local cmd = command:lower()

	if cmd == "cash" then
		handleCash(player, tostring(args[1] or ""))
	elseif cmd == "box" then
		handleBox(player, tostring(args[1] or ""), tostring(args[2]))
	elseif cmd == "reset" then
		handleReset(player)
	elseif cmd == "allboxes" then
		handleAllBoxes(player)
	else
		warn(string.format("[Admin] %s: unknown command %q", player.Name, cmd))
	end
end

-- ── Init ──────────────────────────────────────────

function AdminService:Init()
	if not RunService:IsStudio() then
		print("[AdminService] Not in Studio — admin commands disabled")
		return
	end

	ensureRemote()
	if AdminCommand then
		AdminCommand.OnServerEvent:Connect(onAdminCommand)
	end

	print("[AdminService] Initialized (Studio mode — admin commands active)")
end

return AdminService
