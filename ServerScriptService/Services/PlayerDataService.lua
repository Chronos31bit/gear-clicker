--!strict

-- Player profile lifecycle: DataStore persistence, session locking, schema validation.
-- Server-authoritative: client never reads or writes DataStore directly.
-- Autosave every GameConfig.AUTOSAVE_INTERVAL, on PlayerRemoving, and on BindToClose.
--
-- Profile schema (canonical):
--   version: number                -- schema version for migration support
--   cash: number                   -- current spendable cash
--   equippedMotor: string          -- motor ID (default "motor_rusty")
--   equippedGears: { [slot]: uid } -- fixed 5-slot indexed table (1-5), nils = empty
--   inventory.motors: { [id]: true }   -- set of owned motor IDs
--   inventory.gears: { [uid]: GearInstance }  -- map of owned gear instances
--   stats.totalEarned: number      -- lifetime earnings
--   stats.boxesOpened: number      -- boxes opened (future use)
--   stats.lastSeen: number         -- os.time() of last save/disconnect

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

--------------------
-- Types          --
--------------------

export type GearInstance = {
	uniqueId: string,
	id: string,
	tier: number,
	rarity: string,
	rolledAt: number,
}

export type Profile = {
	version: number,
	cash: number,
	equippedMotor: string,
	equippedGears: { [number]: string },
	inventory: {
		motors: { [string]: boolean },
		gears: { [string]: GearInstance },
	},
	stats: {
		totalEarned: number,
		boxesOpened: number,
		lastSeen: number,
	},
}

--------------------
-- Constants      --
--------------------

local SAVE_VERSION = 1
local SESSION_TTL = 30
local MAX_RETRIES = 3
local BACKOFF_BASE = 0.5

--------------------
-- State          --
--------------------

local playerDataService: { [string]: any } = {}
local profiles: { [Player]: Profile } = {}
local dataStore: DataStore? = nil
local autosaveThread: thread? = nil
local jobId: string = game.JobId

--------------------
-- Helpers        --
--------------------

local function generateToken(): string
	return string.format("%x-%x-%x", math.random(1, 2^31), math.random(1, 2^31), math.random(1, 2^31))
end

local function makeDataKey(userId: number): string
	return "PlayerData_" .. userId
end

-- Deep copy the player-visibile parts of a profile (strips internal fields).
local function copyProfileForClient(profile: Profile): { [string]: any }
	local gearsCopy: { [string]: GearInstance } = {}
	for k, v in pairs(profile.inventory.gears) do
		gearsCopy[k] = { id = v.id, tier = v.tier, rarity = v.rarity, rolledAt = v.rolledAt }
	end

	local motorsCopy: { [string]: boolean } = {}
	for k, v in pairs(profile.inventory.motors) do
		motorsCopy[k] = v
	end

	local equippedCopy: { [number]: string } = {}
	for k, v in pairs(profile.equippedGears) do
		equippedCopy[k] = v
	end

	return {
		version = profile.version,
		cash = profile.cash,
		equippedMotor = profile.equippedMotor,
		equippedGears = equippedCopy,
		inventory = {
			motors = motorsCopy,
			gears = gearsCopy,
		},
		stats = {
			totalEarned = profile.stats.totalEarned,
			boxesOpened = profile.stats.boxesOpened,
			lastSeen = profile.stats.lastSeen,
		},
	}
end

-- Retry a DataStore call with exponential backoff.
-- Returns (true, result) or (false, errorMessage).
local function withRetry(action: () -> any): (boolean, any)
	local lastErr: any
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(action)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < MAX_RETRIES then
			task.wait(BACKOFF_BASE * (2 ^ (attempt - 1))) -- 0.5s, 1s, 2s
		end
	end
	return false, lastErr
end

--------------------
-- Default profile --
--------------------

local function newDefaultProfile(): Profile
	return {
		version = SAVE_VERSION,
		cash = 0,
		equippedMotor = "motor_rusty",
		equippedGears = {},
		inventory = {
			motors = { ["motor_rusty"] = true },
			gears = {},
		},
		stats = {
			totalEarned = 0,
			boxesOpened = 0,
			lastSeen = os.time(),
		},
	}
end

--------------------
-- Migration      --
--------------------

-- Ensure a loaded table has all required fields. Handles partial/corrupt data.
local function ensureValidProfile(data: { [string]: any }): Profile
	if typeof(data) ~= "table" then
		return newDefaultProfile()
	end

	if typeof(data.version) ~= "number" then data.version = SAVE_VERSION end

	if typeof(data.cash) ~= "number" then data.cash = 0 end
	if typeof(data.equippedMotor) ~= "string" then
		data.equippedMotor = "motor_rusty"
	end
	if typeof(data.equippedGears) ~= "table" then
		data.equippedGears = {}
	end

	if typeof(data.inventory) ~= "table" then data.inventory = {} end
	if typeof(data.inventory.motors) ~= "table" then
		data.inventory.motors = {}
	end
	if typeof(data.inventory.gears) ~= "table" then
		data.inventory.gears = {}
	end

	if typeof(data.stats) ~= "table" then data.stats = {} end
	if typeof(data.stats.totalEarned) ~= "number" then
		data.stats.totalEarned = 0
	end
	if typeof(data.stats.boxesOpened) ~= "number" then
		data.stats.boxesOpened = 0
	end
	if typeof(data.stats.lastSeen) ~= "number" then
		data.stats.lastSeen = os.time()
	end

	-- Ensure starter motor is always owned
	if not data.inventory.motors["motor_rusty"] then
		data.inventory.motors["motor_rusty"] = true
	end

	return data :: any
end

--------------------
-- Session locking --
--------------------

local function sessionIsForeign(data: Profile): boolean
	local s = (data :: any)._session
	if typeof(s) ~= "table" then
		return false
	end
	if typeof(s.expiresAt) ~= "number" then
		return false
	end
	-- Lock is live if not expired AND belongs to another server
	if os.time() < s.expiresAt and s.serverId ~= jobId then
		return true
	end
	return false
end

local function stampSession(data: Profile): Profile
	(data :: any)._session = {
		token = generateToken(),
		expiresAt = os.time() + SESSION_TTL,
		serverId = jobId,
	}
	return data
end

--------------------
-- Load / Save    --
--------------------

function playerDataService:LoadPlayerAsync(player: Player): Profile?
	local userId = player.UserId
	local key = makeDataKey(userId)
	local tag = string.format("Load(u=%d)", userId)

	-- If DataStore is unavailable (Studio without API service), use in-memory
	if not dataStore then
		local profile = newDefaultProfile()
		profiles[player] = profile
		return profile
	end

	local ok, result = withRetry(function()
		return dataStore:UpdateAsync(key, function(old: any): any
			if old then
				local profile = ensureValidProfile(old)
				if sessionIsForeign(profile) then
					return nil -- lock contested
				end
				return stampSession(profile)
			else
				return stampSession(newDefaultProfile())
			end
		end)
	end)

	if not ok then
		warn(string.format("[PDS] %s DataStore error: %s", tag, tostring(result)))
		local profile = newDefaultProfile()
		profiles[player] = profile
		return profile
	end

	if result == nil then
		local msg = "Your data is being loaded on another server. Wait a moment and rejoin."
		warn(string.format("[PDS] %s session lock contested, kicking", tag))
		pcall(function() player:Kick(msg) end)
		return nil
	end

	-- Strip session from in-memory cache (re-added on each save)
	(result :: any)._session = nil
	profiles[player] = result
	return result
end

function playerDataService:SavePlayerAsync(player: Player, clearSession: boolean?): boolean
	local profile = profiles[player]
	if not profile then
		return true
	end

	profile.stats.lastSeen = os.time()

	if not dataStore then
		return true
	end

	local key = makeDataKey(player.UserId)
	local tag = string.format("Save(u=%d)", player.UserId)

	local ok, err = withRetry(function()
		return dataStore:UpdateAsync(key, function(_: any): any
			if clearSession then
				(profile :: any)._session = nil
			else
				stampSession(profile)
			end
			return profile
		end)
	end)

	if not ok then
		warn(string.format("[PDS] %s save failed: %s", tag, tostring(err)))
		return false
	end

	-- Strip session from cache after save
	(profile :: any)._session = nil
	return true
end

--------------------
-- Public API     --
--------------------

function playerDataService.GetProfile(player: Player): Profile?
	return profiles[player]
end

function playerDataService.GetPlayerData(player: Player): { [string]: any }?
	local profile = profiles[player]
	if not profile then return nil end
	return copyProfileForClient(profile)
end

function playerDataService.AddCash(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then return end
	profile.cash += amount
	if amount > 0 then
		profile.stats.totalEarned += amount
	end
end

function playerDataService.SpendCash(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile then return false end
	if profile.cash < amount then return false end
	profile.cash -= amount
	return true
end

function playerDataService.AddGear(player: Player, gearInstance: GearInstance)
	local profile = profiles[player]
	if not profile or not gearInstance then return end
	if not gearInstance.uniqueId or not gearInstance.id then return end
	profile.inventory.gears[gearInstance.uniqueId] = {
		id = gearInstance.id,
		tier = gearInstance.tier,
		rarity = gearInstance.rarity,
		rolledAt = gearInstance.rolledAt or os.time(),
	}
end

function playerDataService.RemoveGear(player: Player, uniqueId: string): boolean
	local profile = profiles[player]
	if not profile then return false end
	if not profile.inventory.gears[uniqueId] then return false end
	profile.inventory.gears[uniqueId] = nil
	return true
end

function playerDataService.AddMotor(player: Player, motorId: string)
	local profile = profiles[player]
	if not profile then return end
	profile.inventory.motors[motorId] = true
end

--------------------
-- Autosave        --
--------------------

local function saveAllPlayers(clearSessions: boolean?)
	for p, _ in pairs(profiles) do
		if p and Players:FindFirstChild(p.Name) then
			playerDataService:SavePlayerAsync(p, clearSessions)
		end
	end
end

local function startAutosaveLoop()
	if autosaveThread then return end
	autosaveThread = task.spawn(function()
		while true do
			task.wait(GameConfig.AUTOSAVE_INTERVAL)
			saveAllPlayers(false)
		end
	end)
end

--------------------
-- Init            --
--------------------

function playerDataService:Init()
	-- Resolve DataStore
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore("PlayerData")
	end)
	if ok then
		dataStore = ds
		print("[PlayerDataService] DataStore ready")
	else
		warn("[PlayerDataService] No DataStore — running in memory-only mode")
		dataStore = nil
	end

	-- Player join
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			playerDataService:LoadPlayerAsync(player)
		end)
	end)

	-- Player leave
	Players.PlayerRemoving:Connect(function(player: Player)
		playerDataService:SavePlayerAsync(player, true)
		profiles[player] = nil
	end)

	-- Autosave loop
	startAutosaveLoop()

	-- BindToClose
	game:BindToClose(function()
		saveAllPlayers(true)
		task.wait(2)
	end)

	print("[PlayerDataService] Initialized (version " .. SAVE_VERSION .. ")")
end

return playerDataService
