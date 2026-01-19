# CLAUDE.md - AI Assistant Guide for Dino Royale 2

This document helps AI assistants understand and work with the Dino Royale 2 codebase effectively.

## Project Overview

Dino Royale 2 is a Roblox battle royale game where players fight each other and AI dinosaurs. The codebase is written in Luau (Roblox's Lua variant) and follows a service-oriented architecture.

## Quick Reference

### Key Files

| File | Purpose |
|------|---------|
| `ServerScriptService/main.server.lua` | Server bootstrap - initializes all services |
| `StarterPlayerScripts/main.client.lua` | Client bootstrap - initializes HUD and remotes |
| `framework/init.lua` | Service locator pattern, dependency injection |
| `src/shared/GameConfig.lua` | All game configuration values |
| `src/shared/Remotes.lua` | Network event definitions |
| `service/GameService/init.lua` | Match state machine (lobby, drop, combat, victory) |
| `service/WeaponService/init.lua` | Weapons, damage, attachments, traps |
| `service/DinoService/init.lua` | Dinosaur AI, spawning, abilities, bosses |
| `service/MapService/init.lua` | Biomes, POIs, environmental events |
| `service/StormService/init.lua` | Shrinking zone mechanics |
| `module/LootSystem/init.lua` | Loot spawning and distribution |
| `module/SquadSystem/init.lua` | Teams, revives, spectating |
| `module/PlayerInventory/init.lua` | Player weapons, ammo, consumables |
| `module/DinoHUD/init.lua` | Client-side HUD |

### Architecture Pattern

The project uses a **Service Locator** pattern:

```lua
-- framework/init.lua provides:
framework:RegisterService(name, service)  -- Register a service
framework:GetService(name)                -- Retrieve a service
framework:GetModule(name)                 -- Retrieve a module
framework.Log(level, message, ...)        -- Centralized logging
```

### Bootstrap Flow

**Server (main.server.lua):**
1. Setup Remotes
2. Initialize Framework
3. Initialize Services: GameService → MapService → StormService → WeaponService → DinoService
4. Initialize Modules: LootSystem → SquadSystem → PlayerInventory
5. Connect player events

**Client (main.client.lua):**
1. Wait for Remotes
2. Load shared modules
3. Initialize DinoHUD
4. Connect to remote events
5. Setup input handling

### Common Patterns

**Initializing a service:**
```lua
function MyService:Initialize()
    framework = require(script.Parent.Parent.framework)
    gameConfig = require(script.Parent.Parent.src.shared.GameConfig)
    self:SetupRemotes()
    return true
end
```

**Using Remotes (centralized):**
```lua
local Remotes = require(game.ReplicatedStorage.Remotes)

-- Server: Fire to clients
Remotes.FireAllClients("EventName", data)
Remotes.FireClient("EventName", player, data)

-- Server: Listen for client events
Remotes.OnEvent("EventName", function(player, data) end)

-- Client: Fire to server
Remotes.FireServer("EventName", data)

-- Client: Listen for server events
Remotes.OnEvent("EventName", function(data) end)
```

**Creating RemoteEvents manually:**
```lua
local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remoteFolder then
    remoteFolder = Instance.new("Folder")
    remoteFolder.Name = "Remotes"
    remoteFolder.Parent = ReplicatedStorage
end

local remote = Instance.new("RemoteEvent")
remote.Name = "MyEventName"
remote.Parent = remoteFolder
```

## Service Details

### GameService

Manages match lifecycle with state machine:
- `LOBBY` → `STARTING` → `DROPPING` → `MATCH` → `ENDING` → `CLEANUP` → `LOBBY`

Key methods:
- `GameService:GetState()` - Current match state
- `GameService:GetMode()` - Current game mode (solo/duos/trios)
- `GameService:EliminatePlayer(player, killer)` - Handle player elimination
- `GameService:BroadcastLobbyStatus(current, required, timer)` - Lobby UI updates
- `GameService:BroadcastCountdown(seconds)` - Match countdown

### WeaponService

Handles all weapon mechanics including ranged, melee, explosives, and traps.

**Weapon Categories:**
- `assault_rifle`, `smg`, `shotgun`, `sniper`, `pistol`
- `melee`, `explosive`, `throwable`, `trap`

Key methods:
- `WeaponService:GiveWeapon(player, weaponId)` - Give weapon to player
- `WeaponService:GiveAmmo(player, ammoType, amount)` - Give ammo
- `WeaponService:GiveThrowable(player, throwableType, amount)` - Give throwables
- `WeaponService:GetWeaponDefinition(weaponId)` - Get weapon config
- `WeaponService:CalculateDamage(weapon, hitPosition, shooter, hitPart, isDino)` - Damage calc
- `WeaponService:PlaceTrap(player, trapId, position)` - Deploy trap

**Adding a new weapon:**
```lua
-- In WEAPON_DEFINITIONS table:
new_weapon = {
    name = "Display Name",
    category = "assault_rifle",
    damage = 25,
    fireRate = 10,        -- rounds per second
    magazineSize = 30,
    reloadTime = 2.0,     -- seconds
    range = 100,          -- studs
    recoil = {vertical = 0.5, horizontal = 0.2, recovery = 0.1},
    accuracy = 0.9,       -- 0-1 scale
    rarity = "rare",      -- default rarity
}
```

### DinoService

Controls dinosaur AI, spawning, and boss fights.

**Dinosaur Types:**
- `raptor` (pack_hunter) - Flanking attacks
- `trex` (solo_predator) - High damage, abilities
- `pteranodon` (aerial_diver) - Flying, dive bombs
- `triceratops` (defensive_charger) - Armored, charge
- `dilophosaurus` (ranged_spitter) - Venom projectiles
- `carnotaurus` (ambush_predator) - Camouflage
- `compy` (swarm) - Large numbers
- `spinosaurus` (solo_predator) - Tail swipe

**Boss Types:**
- `alpha_rex` - Ground pound, summon minions
- `alpha_raptor` - Pack call, frenzy
- `alpha_spino` - Tidal wave, submerge

Key methods:
- `DinoService:StartSpawning()` - Begin spawn loop
- `DinoService:StopSpawning()` - Stop spawning
- `DinoService:SpawnDinosaur(type, position, packId)` - Spawn single dino
- `DinoService:SpawnBoss(bossType, position)` - Spawn boss
- `DinoService:DamageDinosaur(dinoId, damage, attacker)` - Apply damage
- `DinoService:DespawnAll()` - Clear all dinosaurs

### MapService

Manages biomes, POIs, and events.

**Biomes:** `jungle`, `volcanic`, `swamp`, `facility`, `plains`, `coastal`

Key methods:
- `MapService:GetBiomeAt(position)` - Get biome for position
- `MapService:GetNearestPOI(position)` - Find closest POI
- `MapService:TriggerEvent(eventType)` - Start environmental event
- `MapService:GetPlayerSpawnPoints()` - Get drop locations
- `MapService:GetDinoSpawnPoints()` - Get dino spawn locations
- `MapService:GetLootSpawnPoints()` - Get ground loot locations
- `MapService:GetPOIChestLocations()` - Get chest locations from POIs
- `MapService:GetMapCenter()` - Get map center position
- `MapService:GetMapSize()` - Get map dimensions

**Environmental Events:**
- `volcanic_eruption` - Area damage
- `dinosaur_stampede` - Dinos charge through
- `meteor_shower` - Random impacts
- `toxic_gas` - DoT + slow
- `supply_drop` - Legendary loot
- `alpha_spawn` - Boss appears

### StormService

Controls the shrinking safe zone.

Key methods:
- `StormService:StartStorm()` - Begin zone phases
- `StormService:StopStorm()` - Stop the storm
- `StormService:GetState()` - Current phase, radius, center
- `StormService:IsInsideZone(position)` - Check if position is safe
- `StormService:GetDistanceToZone(position)` - Distance to safe zone edge

### LootSystem

Handles item spawning and pickup.

**Loot Categories:**
- `weapons` - Ranged weapons
- `melee` - Melee weapons
- `explosives` - Rocket/grenade launchers
- `throwables` - Grenades, molotovs, C4
- `traps` - Bear trap, tripwire, etc.
- `ammo` - All ammunition types
- `healing` - Health and shield items
- `attachments` - Weapon attachments

Key methods:
- `LootSystem:SpawnAllLoot()` - Spawn all loot for match
- `LootSystem:SpawnLootAtPoint(spawnPoint)` - Spawn at location
- `LootSystem:SpawnLootItem(itemId, type, position, rarity, amount)` - Spawn specific item
- `LootSystem:SpawnWeaponLoot(weaponId, rarity, position)` - Spawn dropped weapon
- `LootSystem:PickupLoot(player, lootId)` - Handle pickup
- `LootSystem:ResetLoot()` - Clear all loot

### SquadSystem

Manages teams and revives.

Key methods:
- `SquadSystem:SetMode(mode)` - Set game mode
- `SquadSystem:FormSquads()` - Create teams from players
- `SquadSystem:GetPlayerSquad(player)` - Get player's squad
- `SquadSystem:AreTeammates(player1, player2)` - Check same team
- `SquadSystem:StartRevive(reviver, targetUserId)` - Begin revive
- `SquadSystem:OnPlayerEliminated(player, killer)` - Handle death/down

### PlayerInventory

Manages player equipment and consumables.

Key methods:
- `PlayerInventory:InitializePlayer(player)` - Setup new player
- `PlayerInventory:GiveWeapon(player, weaponId, rarity, attachments)` - Add weapon
- `PlayerInventory:GiveAmmo(player, ammoType, amount)` - Add ammo
- `PlayerInventory:GiveConsumable(player, itemId, amount)` - Add consumable
- `PlayerInventory:GiveThrowable(player, itemId, amount)` - Add throwable
- `PlayerInventory:GiveTrap(player, trapId, amount)` - Add trap
- `PlayerInventory:GetEquippedWeapon(player)` - Current weapon
- `PlayerInventory:EquipWeaponSlot(player, slot)` - Switch weapons
- `PlayerInventory:DropWeapon(player, slot)` - Drop weapon
- `PlayerInventory:ResetInventory(player)` - Clear inventory
- `PlayerInventory:SyncInventory(player)` - Send to client

### DinoHUD

Client-side HUD components.

**Components:**
- Health/Shield bars
- Weapon hotbar (5 slots)
- Minimap with storm indicator
- Kill feed
- Player count
- Squad teammate status
- Damage indicators
- Storm warning
- Dinosaur health bars (targeted dinos)
- Boss health bar with phase indicator
- Lobby UI (player count, timer, mode)
- Death screen (placement, killer, spectate button)
- Victory screen (stats display)
- Spectator UI (prev/next player controls)

Key methods:
- `DinoHUD:Initialize()` - Create HUD
- `DinoHUD:SetEnabled(enabled)` - Show/hide HUD
- `DinoHUD:UpdatePlayerCount(count)` - Update alive count
- `DinoHUD:AddKillFeedItem(victimId, killerId)` - Add kill to feed
- `DinoHUD:SelectWeaponSlot(slot)` - Highlight selected slot
- `DinoHUD:ShowStormWarning(delay, phase)` - Show warning
- `DinoHUD:ShowDamageIndicator(direction)` - Show damage direction
- `DinoHUD:UpdateDinoHealth(name, current, max)` - Show dino health bar
- `DinoHUD:ShowBossHealth(name, current, max, phase)` - Show boss health bar
- `DinoHUD:HideBossHealth()` - Hide boss health bar
- `DinoHUD:UpdateLobbyUI(data)` - Update lobby screen
- `DinoHUD:HideLobbyUI()` - Hide lobby screen
- `DinoHUD:ShowDeathScreen(killerName, placement)` - Show death overlay
- `DinoHUD:HideDeathScreen()` - Hide death overlay
- `DinoHUD:ShowVictoryScreen(stats)` - Show victory overlay
- `DinoHUD:HideVictoryScreen()` - Hide victory overlay
- `DinoHUD:ShowSpectatorUI(playerName)` - Show spectator controls
- `DinoHUD:UpdateSpectatorTarget(playerName)` - Update spectated player
- `DinoHUD:HideSpectatorUI()` - Hide spectator controls

## Network Events (Remotes.lua)

All remote events are defined in `src/shared/Remotes.lua`:

**Game State:**
- `GameStateChanged`, `MatchStarting`, `VictoryDeclared`
- `UpdatePlayersAlive`, `LobbyStatusUpdate`, `CountdownUpdate`

**Player/Squad:**
- `PlayerEliminated`, `PlayerDowned`, `SquadUpdate`
- `ReviveStarted`, `ReviveCompleted`, `SpectateTeammate`

**Storm:**
- `StormPhaseChanged`, `StormWarning`, `StormDamage`

**Weapons:**
- `WeaponFire`, `WeaponReload`, `WeaponEquip`, `WeaponDrop`
- `MeleeAttack`, `ThrowableThrown`, `ExplosionEffect`

**Traps:**
- `TrapPlaced`, `TrapTriggered`, `TrapDestroyed`

**Dinosaurs:**
- `DinoSpawned`, `DinoDamaged`, `DinoDied`, `DinoAttack`
- `DinoAbility`, `DinoStateUpdate`, `PackAlert`

**Boss:**
- `BossSpawned`, `BossPhaseChanged`, `BossDied`, `BossAbility`

**Map Events:**
- `MapEventStarted`, `MapEventEnded`, `EnvironmentalDamage`
- `SupplyDropSpawned`, `SupplyDropLanded`

**Inventory:**
- `InventoryUpdate`, `AmmoUpdate`, `ItemConsumed`

**Loot:**
- `LootSpawned`, `LootPickedUp`, `ChestOpened`

## Configuration

All tunable values are in `GameConfig.lua`. When making balance changes, modify values there rather than in service code.

**Common Configuration Areas:**
- `GameConfig.Match` - Player counts, timing
- `GameConfig.Modes` - Solo/Duos/Trios settings
- `GameConfig.Dinosaurs` - Spawn rates, AI settings
- `GameConfig.Weapons` - Damage multipliers, categories
- `GameConfig.Map` - Biomes, POIs, events
- `GameConfig.Loot` - Rarity weights, spawn rates
- `GameConfig.Storm` - Phase timing, damage
- `GameConfig.Player` - Health, inventory, movement
- `GameConfig.UI` - HUD settings
- `GameConfig.Debug` - Debug toggles

## Common Tasks

### Adding a new feature

1. Identify which service(s) need modification
2. Add configuration to `GameConfig.lua` if needed
3. Add RemoteEvents to `Remotes.lua` if needed
4. Implement server-side logic in appropriate service
5. Implement client-side handling in `main.client.lua` or DinoHUD
6. Update documentation

### Debugging

```lua
-- Enable debug logging
GameConfig.Debug.enabled = true
GameConfig.Debug.logAIDecisions = true

-- Use framework logging
framework.Log("Debug", "Message: %s", value)
framework.Log("Info", "Match started")
framework.Log("Warn", "Low player count")
framework.Log("Error", "Failed to spawn")
```

### Testing specific systems

```lua
-- Test dinosaur spawning
local dinoService = framework:GetService("DinoService")
dinoService:SpawnBoss("alpha_rex", Vector3.new(0, 10, 0))

-- Test weapon damage
local weaponService = framework:GetService("WeaponService")
local damage = weaponService:CalculateDamage(weapon, 50, "Head")

-- Test zone
local stormService = framework:GetService("StormService")
local isInside = stormService:IsInsideZone(player.Character.HumanoidRootPart.Position)

-- Test inventory
local playerInventory = framework:GetModule("PlayerInventory")
playerInventory:GiveWeapon(player, "scar", "legendary")
```

## Code Style

- Use `--[[` block comments `]]` for documentation
- Use `--` inline comments for explanations
- CamelCase for services and classes
- camelCase for functions and variables
- SCREAMING_SNAKE_CASE for constants
- Prefix private variables with underscore or use `local`

## Important Notes

1. **Server Authority**: All gameplay logic runs on server. Never trust client input.

2. **Remote Security**: Validate all RemoteEvent data on server before processing.

3. **Performance**: DinoService and StormService use update loops - be mindful of per-frame costs.

4. **State Management**: GameService is the source of truth for match state.

5. **Modularity**: Services should be loosely coupled. Use framework:GetService() for dependencies.

6. **Inventory**: WeaponService manages equipped weapons, PlayerInventory manages storage.

## File Locations Summary

```
dino-royale2/
├── ServerScriptService/
│   └── main.server.lua             # Server bootstrap
├── StarterPlayerScripts/
│   └── main.client.lua             # Client bootstrap
├── framework/init.lua              # Core framework
├── service/
│   ├── GameService/init.lua        # Match lifecycle (~640 lines)
│   ├── WeaponService/init.lua      # Weapons (~2380 lines)
│   ├── DinoService/init.lua        # Dinosaurs (~3000+ lines)
│   ├── MapService/init.lua         # Map (~2150 lines)
│   └── StormService/init.lua       # Zone (~460 lines)
├── module/
│   ├── DinoHUD/init.lua            # Client HUD (~700 lines)
│   ├── LootSystem/init.lua         # Loot (~965 lines)
│   ├── SquadSystem/init.lua        # Teams (~570 lines)
│   └── PlayerInventory/init.lua    # Inventory (~580 lines)
├── src/shared/
│   ├── GameConfig.lua              # All configuration (~660 lines)
│   ├── Remotes.lua                 # Network events (~240 lines)
│   └── lib/Signal.lua              # Event utility
├── GDD.md                          # Game design doc
├── README.md                       # Project readme
└── CLAUDE.md                       # This file
```
