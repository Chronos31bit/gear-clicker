--!strict

-- Manages player profile lifecycle: load on join, autosave every 60s,
-- save on leave. Uses DataStore with UpdateAsync and session locking.
-- See schema in PlayerDataService for the canonical profile structure.

local PlayerDataService = {}

function PlayerDataService:Init()
	-- Profile templates, DataStore setup, autosave loop
end

function PlayerDataService:LoadPlayerAsync(player)
	-- Load or create profile for player
end

function PlayerDataService:SavePlayerAsync(player)
	-- Serialize and persist player profile
end

function PlayerDataService:GetPlayerData(player)
	-- Return profile for client display (read-only snapshot)
	return nil
end

return PlayerDataService
