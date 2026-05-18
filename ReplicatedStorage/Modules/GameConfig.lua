--!strict

-- Core game tuning constants.
-- All numeric values that affect gameplay are centralized here.

local GameConfig = {}

GameConfig.MAX_GEAR_SLOTS_BASE = 1
GameConfig.MAX_GEAR_SLOTS_CAP = 5
GameConfig.BASE_TICK_RATE = 1 -- seconds per AFK earnings tick
GameConfig.CLICK_MULTIPLIER = 2 -- click burst = tick earnings * this
GameConfig.STARTING_CASH = 0
GameConfig.AUTOSAVE_INTERVAL = 60 -- seconds between profile autosaves

return GameConfig
