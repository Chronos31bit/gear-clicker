--!strict

-- Manages HUD display: cash counter, equipped gear slots, motor info,
-- and tick/click earnings feedback. Updates UI in response to server state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
