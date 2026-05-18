--!strict

-- Handles box opening requests. Validates player can afford the box,
-- rolls item type + tier + rarity from the box's pool, grants results
-- to inventory, and deducts cost. All randomness is server-authoritative.
--
-- Supports batched opens (quantity 1, 10, 100).
-- Rolls are atomic: on any failure the full box cost is refunded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local BoxData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BoxData"))
local RNG = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RNG"))
local MotorData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MotorData"))
local GearData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GearData"))
local RarityData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityData"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("PlayerDataService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenBoxRemote = Remotes:WaitForChild("OpenBox") :: RemoteEvent

-- Will be resolved/created in Init()
local BoxOpenedRemote: RemoteEvent? = nil

--------------------
-- Types          --
--------------------

export type RollResult = {
	type: "motor" | "gear",
	itemId: string,
	displayName: string,
	tier: number,
	-- gear-only fields
	uniqueId: string?,
	rarity: string?,
	multiplier: number?,
	-- motor-only fields
	duplicate: boolean?,
	refundAmount: number?,
}

--------------------
-- Helpers        --
--------------------

-- Generate a unique ID for a new gear instance.
-- Format: gearId_rarity_timestamp_random
-- The timestamp + random suffix makes collisions vanishingly unlikely
-- across sessions and players.
local function generateUniqueId(gearId: string, rarity: string): string
	return string.format("%s_%s_%d_%d", gearId, rarity, os.time(), math.random(10000, 99999))
end

-- Pure function: simulate a single box roll with no side effects.
-- Picks from the box's contents pool by weight, then rolls rarity if it's a gear.
-- @param boxDef - the box definition from BoxData
-- @return RollResult table or nil if the roll fails (shouldn't happen with valid data)
local function simulateSingleRoll(boxDef: BoxData.BoxDef): RollResult?
	local poolIdx = RNG.WeightedPick(boxDef.contentsPool)
	if not poolIdx then
		return nil
	end

	local entry = boxDef.contentsPool[poolIdx]

	if entry.type == "motor" then
		local motorDef = MotorData.GetMotorByTier(entry.tier)
		if not motorDef then
			return nil
		end

		return {
			type = "motor",
			itemId = motorDef.id,
			displayName = motorDef.displayName,
			tier = motorDef.tier,
		}
	elseif entry.type == "gear" then
		local gearDef = GearData.GetGearByTier(entry.tier)
		if not gearDef then
			return nil
		end

		local rarityId = RNG.WeightedTablePick(boxDef.rarityRollTable)
		if not rarityId then
			return nil
		end

		local rarityDef = RarityData.GetRarity(rarityId)
		local mult = rarityDef and rarityDef.multiplier or 1.0

		return {
			type = "gear",
			itemId = gearDef.id,
			displayName = gearDef.displayName,
			tier = gearDef.tier,
			uniqueId = generateUniqueId(gearDef.id, rarityId),
			rarity = rarityId,
			multiplier = mult,
		}
	else
		warn(string.format("UnboxService: unknown pool entry type %q", entry.type))
		return nil
	end
end

-- Apply a single roll result to the player's profile.
-- Mutates the profile in-memory (DataStore write happens on autosave/save).
-- @return true on success, false + errorMsg on failure
local function applyRollResult(player: Player, result: RollResult, boxDef: BoxData.BoxDef): (boolean, string?)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then
		return false, "Profile not loaded"
	end

	if result.type == "gear" then
		PlayerDataService.AddGear(player, {
			uniqueId = result.uniqueId :: string,
			id = result.itemId,
			tier = result.tier,
			rarity = result.rarity :: string,
			rolledAt = os.time(),
		})
		return true
	elseif result.type == "motor" then
		-- Check for duplicate motor
		if profile.inventory.motors[result.itemId] then
			-- Already owned: refund a portion of the box cost
			result.duplicate = true
			result.refundAmount = boxDef.motorDuplicateRefund
			PlayerDataService.AddCash(player, boxDef.motorDuplicateRefund)
		else
			-- New motor: add to inventory
			PlayerDataService.AddMotor(player, result.itemId)
		end
		return true
	end

	return false, "Unknown roll result type"
end

--------------------
-- Public API     --
--------------------

local UnboxService = {}

-- Process a batch of box opens for a player.
-- Steps: validate → spend cash → simulate all rolls → apply results.
-- On any failure after spending cash, the full box cost is refunded.
function UnboxService:HandleOpenBox(player: Player, boxId: string, quantity: number)
	-- 1. Validate profile loaded
	local profile = PlayerDataService:GetProfile(player)
	if not profile then
		warn(string.format("UnboxService: %s tried to open boxes without a profile", player.Name))
		return
	end

	-- 2. Validate boxId
	local boxDef = BoxData.GetBox(boxId)
	if not boxDef then
		warn(string.format("UnboxService: %s tried to open unknown box %q", player.Name, boxId))
		return
	end

	-- 3. Validate quantity
	local validQuantities = { [1] = true, [10] = true, [100] = true }
	if not validQuantities[quantity] then
		warn(string.format("UnboxService: %s tried invalid quantity %d for box %q", player.Name, quantity, boxId))
		return
	end

	-- 4. Compute and spend cost
	local totalCost = boxDef.cost * quantity
	if not PlayerDataService.SpendCash(player, totalCost) then
		warn(string.format("UnboxService: %s cannot afford %d x %q ($%d needed, has $%d)",
			player.Name, quantity, boxId, totalCost, profile.cash))
		return
	end

	-- 5. Simulate all rolls (pure computation, no side effects)
	local results: { RollResult } = {}
	local ok, err = pcall(function()
		for _ = 1, quantity do
			local result = simulateSingleRoll(boxDef)
			if not result then
				error("simulateSingleRoll returned nil — invalid pool or lookup")
			end
			table.insert(results, result)
		end
	end)

	if not ok then
		warn(string.format("UnboxService: roll simulation failed for %s: %s — refunding $%d",
			player.Name, tostring(err), totalCost))
		PlayerDataService.AddCash(player, totalCost)
		return
	end

	-- 6. Apply each result to inventory
	local applyFail = false
	for _, result in ipairs(results) do
		local ok2, err2 = applyRollResult(player, result, boxDef)
		if not ok2 then
			warn(string.format("UnboxService: apply failed for %s: %s — refunding $%d",
				player.Name, tostring(err2), totalCost))
			applyFail = true
			break
		end
	end

	if applyFail then
		PlayerDataService.AddCash(player, totalCost)
		return
	end

	-- 7. Update stats
	profile.stats.boxesOpened = (profile.stats.boxesOpened or 0) + quantity

	-- 8. Fire results to client
	if BoxOpenedRemote then
		local cashRemaining = profile.cash
		BoxOpenedRemote:FireClient(player, {
			boxId = boxId,
			quantity = quantity,
			results = results,
			totalCost = totalCost,
			cashRemaining = cashRemaining,
		})
	end
end

function UnboxService:Init()
	-- Wire the OpenBox remote (matching MotorService/GearService pattern)
	OpenBoxRemote.OnServerEvent:Connect(function(player: Player, boxId: any, quantity: any)
		-- Validate argument types server-side
		if typeof(boxId) ~= "string" then
			warn(string.format("OpenBox: invalid boxId type from %s: %s", player.Name, typeof(boxId)))
			return
		end
		if typeof(quantity) ~= "number" then
			warn(string.format("OpenBox: invalid quantity type from %s: %s", player.Name, typeof(quantity)))
			return
		end

		UnboxService:HandleOpenBox(player, boxId, quantity)
	end)

	-- Resolve or create the BoxOpened RemoteEvent for sending results to clients
	local found = Remotes:FindFirstChild("BoxOpened")
	if found then
		BoxOpenedRemote = found :: RemoteEvent
	else
		local newRemote = Instance.new("RemoteEvent")
		newRemote.Name = "BoxOpened"
		newRemote.Parent = Remotes
		BoxOpenedRemote = newRemote :: RemoteEvent
		warn("[UnboxService] BoxOpened RemoteEvent did not exist — created one in ReplicatedStorage/Remotes")
	end
end

return UnboxService
