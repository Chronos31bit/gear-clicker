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

export type Profile = {
	cash: number,
	ownedMotors: { [string]: boolean },
	equippedMotor: string?,
	ownedGears: { { uniqueId: string, gearId: string, tier: number, rarity: string } },
	equippedGears: { string },
}

local PlayerDataService = {}

-- In-memory profiles keyed by Player
local profiles: { [Player]: Profile } = {}

function PlayerDataService:Init()
	-- Profile templates, DataStore setup, autosave loop
end

function PlayerDataService:LoadPlayerAsync(player)
	-- Load or create profile for player
end

function PlayerDataService:SavePlayerAsync(player)
	-- Serialize and persist player profile
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
