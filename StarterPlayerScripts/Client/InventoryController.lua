--!strict

-- Manages the inventory UI: displaying owned motors and gears,
-- equip/unequip actions, and reflecting server-side inventory state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
