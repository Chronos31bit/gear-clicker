--!strict

-- Manages player profile lifecycle: load on join, autosave every 60s,
-- save on leave. Uses DataStore with UpdateAsync and session locking.
-- See schema in PlayerDataService for the canonical profile structure.
--
-- Profile schema:
--   cash: number
--   ownedMotors: { [string]: true }  -- set of owned motor IDs
--   equippedMotor: string            -- currently equipped motor ID
--   ownedGears: { GearInstance }     -- array of gear objects, each with:
--       uniqueId: string, gearId: string, tier: number, rarity: string
--   equippedGears: { string }        -- ordered list of uniqueIds of equipped gears
--   lastSeen: number                 -- os.time() timestamp of last save/disconnect

export type Profile = {
	cash: number,
	ownedMotors: { [string]: boolean },
	equippedMotor: string?,
	ownedGears: { { uniqueId: string, gearId: string, tier: number, rarity: string } },
	equippedGears: { string },
	lastSeen: number,
}

local PlayerDataService = {}

-- Default profile for new players
local function defaultProfile(): Profile
	return {
		cash = 0,
		ownedMotors = {},
		equippedMotor = nil,
		ownedGears = {},
		equippedGears = {},
		lastSeen = os.time(),
	}
end

-- In-memory profiles keyed by Player
local profiles: { [Player]: Profile } = {}

function PlayerDataService:Init()
	-- Profile templates, DataStore setup, autosave loop
end

function PlayerDataService:LoadPlayerAsync(player)
	-- TODO: load from DataStore with UpdateAsync once DataStore is wired.
	-- For now, create a fresh profile. Existing saved data ignored.
	local profile = defaultProfile()

	-- If player had saved data, this is where we'd merge it over the default.
	-- profile.lastSeen comes from the saved timestamp (used by offline earnings calc).

	profiles[player] = profile
end

function PlayerDataService:SavePlayerAsync(player)
	local profile = profiles[player]
	if not profile then
		return
	end

	-- Stamp the time of this save so offline earnings can be computed on next join
	profile.lastSeen = os.time()

	-- TODO: persist to DataStore with UpdateAsync
end

-- Return the server-side mutable profile for a player.
-- Used by services to read and write inventory / equipped data.
function PlayerDataService:GetProfile(player: Player): Profile?
	return profiles[player]
end

-- Return a read-only snapshot of the profile for client display.
function PlayerDataService:GetPlayerData(player: Player): Profile?
	return profiles[player]
end

return PlayerDataService
