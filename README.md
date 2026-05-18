# Gear & Motor Tycoon

An AFK unboxing clicker on Roblox. Players spin gears with motors to earn money, buy mystery boxes to unbox better equipment, and climb from rusty tier-1 parts to mythical endgame gear.

## Overview

- **Motor** — sets the gear cap (max 5 slots) and the max gear tier you can equip. Higher RPM means faster earnings.
- **Gears** — equipped into motor slots. Each gear has a base earning rate multiplied by its rolled rarity prefix (Chilly, Oily, Molten, Mythical, etc.).
- **Earnings** — AFK tick loop awards money every second. Clicking the gear gives a burst boost on top.
- **Progression** — unbox mystery boxes to roll for better motors and gears. Higher-tier boxes have stronger pools.

## Architecture

```
ReplicatedStorage/
├── Modules/          # Pure data + shared logic
│   ├── BoxData.lua       Box definitions (stub)
│   ├── EarningsCalc.lua  Earnings computation functions
│   ├── GameConfig.lua    Core tuning constants
│   ├── GearData.lua      Gear catalog (7 types, tiers 1-7)
│   ├── MotorData.lua     Motor catalog (7 motors, tiers 1-7)
│   ├── RarityData.lua    Rarity definitions + multipliers
│   └── RNG.lua           Weighted random utilities (stub)
└── Remotes/          # RemoteEvents + RemoteFunctions
    ├── OpenBox, EquipMotor, EquipGear, ClickGear, RequestSave
    ├── CashUpdated, GearEquipped, MotorEquipped, WelcomeBack
    └── GetPlayerData, GetCatalog (RemoteFunctions)

ServerScriptService/
├── Main.server.lua        Bootstrap — loads services, wires remotes
└── Services/
    ├── PlayerDataService  Profile lifecycle + persistence
    ├── EarningsService    AFK tick loop, click handler, offline earnings
    ├── MotorService       Motor equip/unequip with validation
    ├── GearService        Gear equip/unequip with validation
    ├── InventoryService   Inventory management (stub)
    └── UnboxService       Box opening logic (stub)

StarterPlayerScripts/
└── Client/
    ├── ClientMain.client.lua         Client entry point
    ├── HUDController.client.lua      Cash display, event listeners
    ├── InventoryController.client.lua (stub)
    └── UnboxController.client.lua    (stub)
```

## Key design principles

- **Server-authoritative** — cash, inventory, equip state, rarity rolls, and box rolls are never computed or mutated on the client. The client only requests via remotes and reflects server state.
- **Self-wired services** — each service hooks its own remote events in `Init()`, keeping Main.server.lua minimal.
- **Pure computation** — earnings math lives in ReplicatedStorage so both server and client can use it without service dependencies.
- **Contiguous gear slots** — `equippedGears` is an always-contiguous array (no gaps). Slot N = array position N.

## Getting started

1. Open the project in **Roblox Studio**.
2. Install dependencies with [Rojo](https://rojo.space) (see `aftman.toml`).
3. Run `rojo build` to build the place file, or use the Rojo plugin for live sync.
4. Press **Play** to test in Studio.

## Development conventions

See [CLAUDE.md](CLAUDE.md) for the full project guide including:

- Rarity table (do not change values without explicit instruction)
- Tier system (1-7 for motors and gears)
- Coding conventions (strict typing, service patterns, Tween animations)
- Git workflow (conventional commits, auto-push after tasks)
- Testing checklist (Studio Play Solo, Output window, edge cases)

## Current status

| System | Status |
|---|---|
| Motor catalog + equip | Done |
| Gear catalog + equip | Done |
| AFK earnings tick | Done |
| Click burst earnings | Done |
| Offline earnings | Done |
| Unboxing / RNG | Stub |
| Inventory UI | Stub |
| HUD / cash display | Stub (remote listeners wired) |
| Persistence (DataStore) | Stub |
| Sell system | Not in scope |
| Gamepasses / monetization | Not in scope |
