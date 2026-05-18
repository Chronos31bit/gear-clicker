--!strict

-- Runs the AFK earnings tick loop per player. Tracks equipped gears and
-- motor stats to compute per-tick earnings. Also handles click burst rewards
-- with debounce. Distributes offline earnings on join.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local MotorData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MotorData"))
local EarningsCalc = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EarningsCalc"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("PlayerDataService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClickGearRemote = Remotes:WaitForChild("ClickGear") :: RemoteEvent
local CashUpdatedRemote = Remotes:WaitForChild("CashUpdated") :: RemoteEvent
local WelcomeBackRemote = Remotes:WaitForChild("WelcomeBack") :: RemoteEvent

local EarningsService = {}

-- Per-player tick loop control flags
local tickLoops: { [Player]: boolean } = {}
-- Per-player click debounce timestamps (os.clock, sub-second precision)
local lastClickTime: { [Player]: number } = {}

-- Resolve equipped gear uniqueIds into { gearId, rarity } pairs.
-- Looks up each uniqueId in the player's ownedGears array.
local function resolveEquippedGears(profile: PlayerDataService.Profile): { { gearId: string, rarity: string } }
	local result: { { gearId: string, rarity: string } } = {}
	for _, uid in ipairs(profile.equippedGears) do
		for _, gear in ipairs(profile.ownedGears) do
			if gear.uniqueId == uid then
				table.insert(result, { gearId = gear.gearId, rarity = gear.rarity })
				break
			end
		end
	end
	return result
end

-- Start a per-player AFK tick loop. Awards earningsPerTick every BASE_TICK_RATE
-- seconds and fires CashUpdated to the client. Silently skips if the player
-- has no motor or no gears equipped (no remote spam).
local function startTickLoop(player: Player)
	if tickLoops[player] then
		return
	end
	tickLoops[player] = true

	task.spawn(function()
		while tickLoops[player] do
			task.wait(GameConfig.BASE_TICK_RATE)

			-- Player may have disconnected during the wait
			if not tickLoops[player] then
				break
			end

			local profile = PlayerDataService:GetProfile(player)
			if not profile then
				continue
			end

			-- Must have a motor equipped
			local motorDef = MotorData.GetMotor(profile.equippedMotor)
			if not motorDef then
				continue
			end

			-- Must have at least one gear equipped
			local equippedGearData = resolveEquippedGears(profile)
			if #equippedGearData == 0 then
				continue
			end

			local earningsPerTick = EarningsCalc.ComputeTickEarnings(equippedGearData, motorDef.rpm)
			if earningsPerTick <= 0 then
				continue
			end

			profile.cash += earningsPerTick
			CashUpdatedRemote:FireClient(player, profile.cash, earningsPerTick)
		end
	end)
end

-- Stop a per-player tick loop. The flag check in the spawned thread handles the
-- actual exit; we don't need to cancel it forcefully.
local function stopTickLoop(player: Player)
	tickLoops[player] = false
end

-- Compute and grant offline earnings when a player rejoins.
-- Uses profile.lastSeen (set on last save/disconnect) to determine time away.
-- Earnings are capped at 8 hours and awarded at half the AFK rate.
-- Fires WelcomeBack to the client if any earnings were granted.
local function handleOfflineEarnings(player: Player)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then
		return
	end

	local now = os.time()
	local offlineSeconds = now - profile.lastSeen
	if offlineSeconds <= 0 then
		return
	end

	-- Need a motor to have earned anything offline
	local motorDef = MotorData.GetMotor(profile.equippedMotor)
	if not motorDef then
		profile.lastSeen = now
		return
	end

	local equippedGearData = resolveEquippedGears(profile)
	if #equippedGearData == 0 then
		profile.lastSeen = now
		return
	end

	local earningsPerTick = EarningsCalc.ComputeTickEarnings(equippedGearData, motorDef.rpm)
	profile.lastSeen = now

	if earningsPerTick <= 0 then
		return
	end

	local offlineEarnings = EarningsCalc.ComputeOfflineEarnings(offlineSeconds, earningsPerTick)
	if offlineEarnings > 0 then
		profile.cash += offlineEarnings
		WelcomeBackRemote:FireClient(player, offlineEarnings)
	end
end

-- Handle a click on a gear. Awards an instant burst of
-- earningsPerTick * CLICK_MULTIPLIER, debounced at 10 clicks/sec per player.
function EarningsService.HandleClickGear(player: Player)
	-- Debounce: at most 10 clicks per second
	local now = os.clock()
	local last = lastClickTime[player] or 0
	if now - last < 0.1 then
		return
	end
	lastClickTime[player] = now

	local profile = PlayerDataService:GetProfile(player)
	if not profile then
		return
	end

	local motorDef = MotorData.GetMotor(profile.equippedMotor)
	if not motorDef then
		return
	end

	local equippedGearData = resolveEquippedGears(profile)
	if #equippedGearData == 0 then
		return
	end

	local earningsPerTick = EarningsCalc.ComputeTickEarnings(equippedGearData, motorDef.rpm)
	if earningsPerTick <= 0 then
		return
	end

	local reward = EarningsCalc.ComputeClickReward(earningsPerTick)
	profile.cash += reward
	CashUpdatedRemote:FireClient(player, profile.cash, reward)
end

-- Init wires the ClickGear remote, connects lifecycle events for tick loops
-- and offline earnings, and starts loops for any players already in the game.
-- Called once from Main.server.lua.
function EarningsService:Init()
	-- Self-wire ClickGear remote (matching MotorService/GearService pattern)
	ClickGearRemote.OnServerEvent:Connect(function(player: Player)
		EarningsService.HandleClickGear(player)
	end)

	-- Start tick loop and grant offline earnings when a player joins
	Players.PlayerAdded:Connect(function(player: Player)
		-- Yield briefly to let PlayerDataService:LoadPlayerAsync finish setting
		-- up the profile. When DataStore is wired, a more robust handoff
		-- (signal/callback) will be needed.
		task.wait(0.1)

		handleOfflineEarnings(player)
		startTickLoop(player)
	end)

	-- Cleanup when a player leaves
	Players.PlayerRemoving:Connect(function(player: Player)
		stopTickLoop(player)
		lastClickTime[player] = nil
	end)

	-- Handle players already in the game (script reload / late join)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			task.wait(0.1)
			handleOfflineEarnings(player)
			startTickLoop(player)
		end)
	end
end

return EarningsService
