# Dino Royale 2

A fast-paced battle royale game for Roblox featuring AI-controlled dinosaurs, diverse biomes, and intense PvPvE combat.

## Overview

Dino Royale 2 drops up to 20 players onto a prehistoric island where they must scavenge for weapons, battle other players, and survive against intelligent dinosaur AI. The shrinking safe zone forces encounters while environmental events and boss dinosaurs create chaos and opportunity.

## Features

### Battle Royale Gameplay
- Solo, Duos, and Trios modes
- 5-phase shrinking zone system
- Server-authoritative anti-cheat architecture
- Fast-paced 5-10 minute matches

### Dinosaur AI System
- 8 unique dinosaur species with distinct behaviors
- Pack tactics with coordinated flanking attacks
- 3 Alpha boss variants with multi-phase fights
- Special abilities: Roar, Charge, Pounce, Venom Spit, Camouflage, and more

### Comprehensive Weapon System
- 25+ weapons across 9 categories
- Melee weapons with special effects (bleed, stun, backstab)
- Explosives and throwables (grenades, C4, molotovs)
- Deployable traps (bear trap, tripwire, tranquilizer)
- Attachment system (scopes, grips, magazines, suppressors)

### Dynamic Map
- 6 distinct biomes (Jungle, Volcanic, Swamp, Facility, Plains, Coastal)
- 8+ named POIs with tiered loot
- Environmental events (eruptions, stampedes, meteor showers)
- Supply drops and boss spawn events

## Project Structure

```
dino-royale2/
├── framework/
│   └── init.lua           # Service locator framework
├── service/
│   ├── GameService/       # Match state machine
│   ├── WeaponService/     # Weapon mechanics & damage
│   ├── DinoService/       # Dinosaur AI & spawning
│   ├── MapService/        # Biomes, POIs, events
│   └── StormService/      # Zone management
├── module/
│   ├── DinoHUD/           # Client-side HUD
│   ├── LootSystem/        # Loot spawning
│   └── SquadSystem/       # Team management
├── src/
│   └── shared/
│       ├── GameConfig.lua # Central configuration
│       ├── Remotes.lua    # Network events
│       └── lib/
│           └── Signal.lua # Event system
├── GDD.md                 # Game Design Document
├── CLAUDE.md              # AI assistant guide
└── README.md              # This file
```

## Architecture

### Framework Pattern

The game uses a **Service Locator** pattern for clean dependency management:

```lua
local framework = require(game.ServerScriptService.framework)

-- Register services
framework:RegisterService("GameService", GameService)
framework:RegisterService("WeaponService", WeaponService)

-- Access services from anywhere
local dinoService = framework:GetService("DinoService")
```

### Service Overview

| Service | Responsibility |
|---------|---------------|
| **GameService** | Match lifecycle (lobby → drop → combat → victory) |
| **WeaponService** | Weapon data, damage calculation, attachments |
| **DinoService** | Dinosaur spawning, AI behavior, boss fights |
| **MapService** | Biome generation, POI management, events |
| **StormService** | Zone phases, damage ticking, notifications |
| **LootSystem** | Item spawning, rarity rolls, distribution |
| **SquadSystem** | Team formation, revives, spectating |

### Server-Client Communication

All gameplay-critical logic runs on the server. Clients receive updates via RemoteEvents:

```lua
-- Server fires event
Remotes.DinoSpawned:FireAllClients({
    id = dinoId,
    type = "raptor",
    position = spawnPos
})

-- Client listens
Remotes.DinoSpawned.OnClientEvent:Connect(function(data)
    -- Handle spawn visualization
end)
```

## Configuration

All game parameters are centralized in `src/shared/GameConfig.lua`:

```lua
-- Adjust dinosaur spawning
GameConfig.Dinosaurs.maxActive = 15
GameConfig.Dinosaurs.spawnInterval = 30

-- Tune weapon damage
GameConfig.Weapons.damageMultipliers.headshot = 2.0

-- Configure storm phases
GameConfig.Storm.phases[1].damage = 1
```

## Quick Start

### Running Locally

1. Open project in Roblox Studio
2. Configure place settings for 1-20 players
3. Start test server with desired player count
4. Players spawn in lobby, match begins when minimum players join

### Testing Services

```lua
-- In command bar or script
local framework = require(game.ServerScriptService.framework)

-- Test dinosaur spawning
local dinoService = framework:GetService("DinoService")
dinoService:SpawnBoss("alpha_rex", Vector3.new(0, 10, 0))

-- Test weapon creation
local weaponService = framework:GetService("WeaponService")
local weapon = weaponService:CreateWeapon("ak47", "epic")

-- Trigger environmental event
local mapService = framework:GetService("MapService")
mapService:TriggerEvent("volcanic_eruption")
```

## Key Systems

### Dinosaur Behaviors

| Behavior | AI Pattern |
|----------|------------|
| `pack_hunter` | Flanking, coordinated attacks, follow leader |
| `solo_predator` | Direct aggression, powerful attacks |
| `aerial_diver` | Circle target, dive bomb attacks |
| `defensive_charger` | Passive until provoked, charge attacks |
| `ranged_spitter` | Maintain distance, projectile attacks |
| `ambush_predator` | Camouflage, surprise pounce |
| `swarm` | Surround target, stacking damage bonus |

### Weapon Categories

- **Ranged**: Assault Rifles, SMGs, Shotguns, Snipers, Pistols
- **Melee**: Machete (bleed), Spear (throwable), Stun Baton, Combat Knife (backstab)
- **Explosives**: Rocket Launcher, Grenade Launcher
- **Throwables**: Frag, Smoke, Molotov, Flashbang, C4
- **Traps**: Bear Trap, Tripwire, Tranq Trap, Spike Trap

### Loot Rarities

| Rarity | Color | Stat Multiplier |
|--------|-------|-----------------|
| Common | Gray | 1.0x |
| Uncommon | Green | 1.1x |
| Rare | Blue | 1.2x |
| Epic | Purple | 1.35x |
| Legendary | Orange | 1.5x |

## Development

### Adding a New Dinosaur

1. Add definition to `DinoService.DINOSAUR_DEFINITIONS`:
```lua
newdino = {
    name = "New Dinosaur",
    category = "solo_predator",
    health = 200,
    speed = 25,
    damage = 30,
    attackRange = 8,
    attackCooldown = 2,
    spawnWeight = 10,
    packSize = {min = 1, max = 1},
    abilities = { ... },
    lootTable = { ... },
}
```

2. Update `GameConfig.Dinosaurs.types` with base stats

### Adding a New Weapon

1. Add definition to `WeaponService.WEAPON_DEFINITIONS`:
```lua
newweapon = {
    name = "New Weapon",
    category = "assault_rifle",
    damage = 25,
    fireRate = 10,
    magazineSize = 30,
    reloadTime = 2,
    range = 100,
    recoil = 0.5,
}
```

2. Configure attachment slots and rarity scaling

### Adding an Environmental Event

1. Add definition to `MapService.EVENT_DEFINITIONS`:
```lua
new_event = {
    name = "New Event",
    type = "hazard",
    duration = 30,
    cooldown = 120,
    damage = 10,
    radius = 50,
}
```

2. Implement execution logic in `MapService:ExecuteEvent()`

## Documentation

- **[GDD.md](./GDD.md)** - Complete game design document
- **[CLAUDE.md](./CLAUDE.md)** - AI assistant guide for development
- **[DEVELOPMENT_PLAN.md](./DEVELOPMENT_PLAN.md)** - Original development roadmap

## Credits

Built with Roblox Studio using Luau.
