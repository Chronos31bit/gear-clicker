# Gear & Motor Tycoon

## Game concept
An AFK unboxing clicker on Roblox. Players have a Motor that spins Gears. Each gear earns money per tick; the motor sets the gear cap (max 5) and the maximum gear tier that can be equipped. Players buy mystery boxes to unbox better motors and gears. Gears roll a rarity prefix on unbox (Chilly, Oily, Molten, Mythical, etc.) which multiplies their earnings. Clicking the gear gives a burst earning on top of the AFK tick.

## Architecture
- ReplicatedStorage/Modules: pure data + shared logic (GameConfig, RarityData, MotorData, GearData, BoxData, RarityService, RNG)
- ReplicatedStorage/Remotes: RemoteEvents and RemoteFunctions
- ServerScriptService/Services: server-authoritative game logic (PlayerDataService, MotorService, GearService, EarningsService, UnboxService, InventoryService)
- StarterPlayerScripts/Client: client controllers (ClientMain, HUDController, UnboxController, InventoryController)
- StarterGui: ScreenGuis

The server is authoritative for: cash, inventory, equip state, rarity rolls, box rolls. Client never computes or mutates these — it only requests via remotes and reflects server state.

## Core systems and rules
- Max gear slots: 1 to 5, controlled by equipped motor's maxGearSlots
- Max gear tier per motor: motor.maxGearTier — gears above this cannot equip
- Earnings per tick: sum over equipped gears of (gear.baseEarnings * rarityMultiplier) * motor.rpm
- Click reward: earningsPerTick * CLICK_MULTIPLIER (debounced 10/sec)
- Offline earnings: capped at 8 hours, 0.5x rate

## Rarity table (do not change without explicit instruction)
Common, Chilly, Oily, Glowing, Static, Molten, Frostbitten, Radiant, Eclipsed, Mythical — with multipliers 1x, 1.35x, 1.80x, 2.50x, 4x, 7x, 12x, 22x, 50x, 150x respectively. See RarityData.lua for exact weights.

## Tier system
Motors and gears both span tier 1 to tier 7. Tier 1 = early game, tier 7 = endgame. Higher-tier boxes have stronger pools.

## Coding conventions
- Lua, strict typing where possible (--!strict)
- Services as ModuleScripts initialized from a Main.server.lua bootstrap
- One ModuleScript = one responsibility; no god modules
- All RemoteEvents validated server-side: never trust client input
- DataStore: UpdateAsync with retry, session locking, autosave every 60s + PlayerRemoving + BindToClose
- TweenService for all UI animations; no while-loop animations
- Comma format all displayed numbers; use Color3.fromRGB for all colors
- Use os.time() consistently for timestamps (not tick())

## Persistence schema
See PlayerDataService.lua for the canonical profile schema. Gears are stored as unique instances (each with its own uniqueId and rolled rarity). Motors are stored as a set of owned IDs.

## Git workflow — IMPORTANT
After completing any task or feature, ALWAYS:
1. Run `git add -A`
2. Commit with a conventional commit message (feat:, fix:, chore:, refactor:, docs:)
3. Run `git push` on the current branch
Do this without being asked. The user does not want to push manually.

## Testing
- Sanity-check every system in Studio Play Solo before considering it done
- Watch the Output window for errors and warnings
- For DataStore: test PlayerRemoving and BindToClose paths
- For unboxing: verify rolls match expected weights with a debug command (open 10,000 boxes, print rarity distribution)

## What NOT to do
- Don't sell gears or motors yet — no sell system in scope
- Don't add gamepasses, monetization, or Robux flows yet
- Don't add a leaderboard yet
- Don't add pets, eggs, or trading
- Don't auto-balance numbers; only adjust if explicitly asked

## When the user asks for a new feature
- Read this file first
- Identify which existing services it touches
- Propose the data model changes (add to schema, bump a version) before writing code
- Keep changes small and committed per logical unit
