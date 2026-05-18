--!strict

-- Weighted random selection utilities for rarity rolls and box contents.
-- Deterministic; uses math.random() which Roblox auto-seeds per session.
-- All functions return nil on empty or zero-total input (never crash).

local RNG = {}

-- Pick an index from an array of { weight: number } entries.
-- Returns 1-based index, or nil if the array is empty or all weights are 0.
function RNG.WeightedPick(entries: { { weight: number } }): number?
	local total: number = 0
	for _, entry in ipairs(entries) do
		if entry.weight > 0 then
			total += entry.weight
		end
	end

	if total <= 0 then
		return nil
	end

	local roll: number = math.random() * total
	local cumulative: number = 0

	for i, entry in ipairs(entries) do
		if entry.weight > 0 then
			cumulative += entry.weight
			if roll <= cumulative then
				return i
			end
		end
	end

	-- Floating-point safety: if we somehow fall through, return the last valid entry
	for i = #entries, 1, -1 do
		if entries[i].weight > 0 then
			return i
		end
	end

	return nil
end

-- Pick a key from a { [string]: number } weight table.
-- Returns the selected key, or nil if the table is empty or all weights are 0.
function RNG.WeightedTablePick(weights: { [string]: number }): string?
	local total: number = 0
	local keys: { string } = {}

	for key, weight in pairs(weights) do
		if weight > 0 then
			total += weight
			table.insert(keys, key)
		end
	end

	if total <= 0 or #keys == 0 then
		return nil
	end

	local roll: number = math.random() * total
	local cumulative: number = 0

	for _, key in ipairs(keys) do
		local w = weights[key]
		if w and w > 0 then
			cumulative += w
			if roll <= cumulative then
				return key
			end
		end
	end

	-- Floating-point safety: return last valid key
	for i = #keys, 1, -1 do
		local k = keys[i]
		local w = weights[k]
		if w and w > 0 then
			return k
		end
	end

	return nil
end

return RNG
