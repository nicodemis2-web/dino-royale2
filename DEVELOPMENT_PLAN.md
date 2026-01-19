# 🦖 DINO ROYALE 2 - Multi-Agent Development Plan

## Project Vision
A Roblox battle royale game combining Evostrike's FPS mechanics with Fortnite-style gameplay (up to 20 players), featuring high-definition dinosaur NPCs that actively hunt players alongside the shrinking storm circle.

---

## Architecture Overview (Based on Evostrike Analysis)

```
dino-royale2/
├── framework/              # Core framework with type system and module management
│   └── init.lua           # Service locator pattern initialization
├── module/                 # Modular game systems
│   ├── DinoPlayer/        # Player management (adapted from EvoPlayer)
│   ├── DinoHUD/           # UI/HUD system (adapted from EvoHUD)
│   ├── DinoEconomy/       # Loot/inventory economy
│   ├── SquadSystem/       # Solo/Duos/Trios team management
│   ├── StormSystem/       # Shrinking zone controller
│   ├── DinoAI/            # Dinosaur hunting AI
│   ├── LootSystem/        # Ground loot spawning
│   ├── MatchMaking/       # Player queue and match creation
│   └── NetClient/         # Rate-limited networking
├── service/               # Core game services
│   ├── GameService/       # Main game loop and state machine
│   ├── WeaponService/     # Weapon handling (from Evostrike)
│   ├── DinoService/       # Dinosaur spawning and behavior
│   ├── StormService/      # Storm progression and damage
│   └── AudioService/      # Sound management
├── src/
│   ├── client/            # Client-side scripts
│   │   ├── character/     # Movement, viewmodel, crosshair
│   │   ├── player/        # HUD, menus, UI controllers
│   │   └── effects/       # Visual effects, particles
│   ├── server/            # Server-side scripts
│   │   ├── GameScript/    # Main game orchestration
│   │   ├── LootScript/    # Loot spawning
│   │   ├── DinoScript/    # Dinosaur spawning/AI
│   │   └── StormScript/   # Storm progression
│   ├── shared/            # Shared code
│   │   ├── lib/           # Utility libraries
│   │   ├── weapon/        # Weapon configs and functions
│   │   ├── movement/      # Movement mechanics
│   │   └── Remotes/       # Network event definitions
│   └── serverstorage/     # Spawn systems, data persistence
├── assets/                # Game assets reference
│   ├── dinosaurs/         # Dinosaur models (from Creator Store)
│   ├── weapons/           # Weapon models
│   ├── map/               # Map assets
│   └── ui/                # UI elements
└── plugin/                # Studio development tools
```

---

## Multi-Agent Development Strategy

### Agent 1: Core Framework & Architecture
**Responsibility:** Set up the foundational framework
- Implement service locator pattern from Evostrike
- Create module type system (Class, Function, Service, etc.)
- Set up client/server script bootstrapping
- Establish remote event/function infrastructure
- Create utility libraries (math, tables, tweens, signals)

### Agent 2: Game Loop & Match System
**Responsibility:** Battle royale game flow
- Implement game state machine (LOBBY → LOADING → MATCH → CLEANUP)
- Create matchmaking queue system
- Build lobby with player count display
- Implement player spawning (drop from sky or teleport)
- Handle victory/elimination detection
- Manage round timing and transitions

### Agent 3: Squad System
**Responsibility:** Team management for all modes
- Solo mode (20 individual players)
- Duos mode (10 teams of 2)
- Trios mode (6-7 teams of 3)
- Team spawning proximity
- Teammate revival system
- Team UI indicators (names, health bars)
- Spectate teammates on death

### Agent 4: Storm/Zone System
**Responsibility:** Shrinking safe zone
- Configurable storm phases (fast-paced for action)
- Storm origin movement with lerp interpolation
- Visual storm wall effect (transparent cylinder or union)
- Player damage when outside zone (DOT)
- Minimap zone indicator
- Audio warning when storm approaching
- Phase timing configuration

**Storm Configuration (Fast-Paced):**
```lua
StormConfig = {
    phases = {
        {delay = 30, shrinkTime = 20, endRadius = 200, damage = 1},
        {delay = 20, shrinkTime = 15, endRadius = 120, damage = 2},
        {delay = 15, shrinkTime = 12, endRadius = 60, damage = 4},
        {delay = 10, shrinkTime = 10, endRadius = 25, damage = 8},
        {delay = 5, shrinkTime = 8, endRadius = 0, damage = 16}
    }
}
```

### Agent 5: Weapon System
**Responsibility:** Combat mechanics (adapted from Evostrike)
- Weapon pickup and equipping
- Shooting mechanics with recoil patterns
- Damage calculation (headshots, falloff, armor)
- Ammunition system
- Reload mechanics
- Weapon switching
- Bullet hit effects and audio

**Weapon Categories:**
- Assault Rifles (AK, M4, SCAR)
- SMGs (MP5, UZI)
- Shotguns (Pump, Tactical)
- Snipers (Bolt, Semi-auto)
- Pistols (Glock, Desert Eagle)

### Agent 6: Dinosaur AI System
**Responsibility:** NPC dinosaurs that hunt players
- Dinosaur spawning based on storm phase
- Pathfinding using Roblox's PathfindingService
- Target acquisition (nearest player detection)
- Attack patterns (bite, charge, swipe)
- Health and damage system
- Different dinosaur types with varying stats
- Pack behavior for smaller dinos
- Audio cues (roars, footsteps)

**Dinosaur Types:**
| Type | Health | Speed | Damage | Behavior |
|------|--------|-------|--------|----------|
| Raptor | 150 | 28 | 20 | Pack hunter, fast, flanks |
| T-Rex | 800 | 18 | 60 | Solo, powerful, loud |
| Pteranodon | 100 | 35 | 15 | Aerial dive attacks |
| Triceratops | 500 | 15 | 40 | Defensive, charges |
| Dilophosaurus | 120 | 22 | 25 | Ranged spit attack |

### Agent 7: Loot & Inventory System
**Responsibility:** Item management
- Ground loot spawning at designated points
- Chest/crate loot containers
- Inventory UI (Fortnite-style hotbar)
- Item pickup with E key
- Item dropping
- Ammo stacking
- Health/shield items
- Rarity tiers (Common, Uncommon, Rare, Epic, Legendary)

### Agent 8: UI/HUD System
**Responsibility:** User interface (adapted from EvoHUD)
- Health and shield bars
- Weapon hotbar (5 slots)
- Ammo counter
- Minimap with storm indicator
- Kill feed
- Player count remaining
- Squad teammate status
- Damage indicators
- Victory/elimination screens

### Agent 9: Map & Environment
**Responsibility:** Game world
- Island-style map design
- Named locations/POIs
- Loot spawn point placement
- Dinosaur spawn zones
- Terrain variation (hills, valleys, water)
- Building/structure placement
- Lobby area design
- Ambient audio and lighting

### Agent 10: Audio & Polish
**Responsibility:** Sound and effects
- Weapon sounds
- Dinosaur sounds (varied roars, footsteps)
- Storm audio (increasing intensity)
- UI sounds
- Ambient music
- Hit indicators
- Kill sounds
- Victory/defeat audio

---

## Key Technical Decisions

### 1. Networking Architecture
- Server-authoritative gameplay (prevent cheating)
- Client-side prediction for responsive feel
- Rate-limited remote events (1 request/second limit from NetClient)
- RemoteEvents for fire-and-forget actions
- RemoteFunctions for request-response patterns

### 2. Storm Implementation
```lua
-- Server-side storm progression
local function updateStorm(phase)
    local config = StormConfig.phases[phase]
    local targetPosition = calculateNewCenter()
    local targetRadius = config.endRadius

    -- Lerp storm position and radius
    TweenService:Create(stormData, TweenInfo.new(config.shrinkTime), {
        centerX = targetPosition.X,
        centerZ = targetPosition.Z,
        radius = targetRadius
    }):Play()
end

-- Damage check (runs every 0.5 seconds)
local function checkPlayerInStorm(player)
    local char = player.Character
    if not char then return end

    local pos = char.HumanoidRootPart.Position
    local distance = (pos - Vector3.new(stormCenter.X, pos.Y, stormCenter.Z)).Magnitude

    if distance > currentRadius then
        local humanoid = char:FindFirstChild("Humanoid")
        humanoid:TakeDamage(currentDamage)
    end
end
```

### 3. Dinosaur AI Behavior Tree
```
Root (Selector)
├── Attack Sequence
│   ├── Is target in attack range?
│   ├── Face target
│   └── Execute attack
├── Chase Sequence
│   ├── Has valid target?
│   ├── Calculate path to target
│   └── Move along path
├── Hunt Sequence
│   ├── Find nearest player
│   ├── Set as target
│   └── Begin chase
└── Idle/Wander
    └── Random patrol behavior
```

### 4. Squad System
```lua
SquadConfig = {
    solo = {maxPlayers = 20, teamSize = 1},
    duos = {maxPlayers = 20, teamSize = 2},
    trios = {maxPlayers = 21, teamSize = 3} -- 7 teams of 3
}
```

---

## Dinosaur Model Sources

1. **Roblox Creator Store:** [Rigged Dinosaur Models](https://create.roblox.com/store/asset/102772249876319/Rigged-Dinosaur-Models)
2. **Sketchfab:** [Roblox Indominus Rex](https://sketchfab.com/3d-models/roblox-indominus-rex-7b8277a25ead4e0abf9b0059c49568f5)
3. **BuiltByBit Marketplace:** Custom high-quality models
4. **Clearly Development:** Community-made assets

---

## Development Phases

### Phase 1: Foundation (Agents 1-2)
- [ ] Set up framework architecture
- [ ] Implement game state machine
- [ ] Create lobby system
- [ ] Basic player spawning

### Phase 2: Core Mechanics (Agents 3-5)
- [ ] Squad system implementation
- [ ] Storm/zone system
- [ ] Weapon system adaptation

### Phase 3: Dinosaurs & Loot (Agents 6-7)
- [ ] Dinosaur AI system
- [ ] Loot spawning system
- [ ] Inventory management

### Phase 4: Polish (Agents 8-10)
- [ ] Complete UI/HUD
- [ ] Map finalization
- [ ] Audio implementation
- [ ] Playtesting and balance

---

## Configuration Files

### GameConfig.lua
```lua
return {
    -- Match Settings
    maxPlayers = 20,
    minPlayersToStart = 4,
    lobbyWaitTime = 60,
    matchMaxDuration = 600, -- 10 minutes max

    -- Storm Settings (fast-paced)
    stormEnabled = true,
    stormDamageInterval = 0.5,

    -- Dinosaur Settings
    dinosaursEnabled = true,
    maxDinosaurs = 15,
    dinoSpawnInterval = 30,
    dinoAggressionRadius = 80,

    -- Loot Settings
    lootDensity = "high",
    chestRespawn = false,

    -- Squad Settings
    defaultMode = "solo",
    allowFriendlyFire = false,
    reviveTime = 5,
    bleedoutTime = 30
}
```

---

## File Structure for Roblox Studio

When imported to Roblox Studio, the hierarchy will be:
```
game
├── ReplicatedStorage
│   ├── Framework
│   ├── Shared
│   │   ├── Lib
│   │   ├── Weapon
│   │   └── Movement
│   └── Remotes
├── ServerScriptService
│   ├── Services
│   └── Scripts
├── ServerStorage
│   ├── Dinosaurs
│   ├── Weapons
│   ├── LootItems
│   └── SpawnPoints
├── StarterGui
│   └── DinoHUD
├── StarterPlayer
│   ├── StarterCharacterScripts
│   └── StarterPlayerScripts
└── Workspace
    ├── Map
    ├── Lobby
    └── Effects
```

---

## Sources & References

- [Roblox Battle Royale Template](https://github.com/Ericthestein/Roblox-Battle-Royale-Template)
- [Official Roblox Battle Royale Tutorial](https://create.roblox.com/docs/education/battle-royale-series/project-setup)
- [Storm System Implementation](https://devforum.roblox.com/t/battle-royale-storm-system/2997474)
- [Shrinking Zone Discussion](https://devforum.roblox.com/t/help-creating-a-shrinking-zonestorm-barrier/2007791)
- [Rigged Dinosaur Models](https://create.roblox.com/store/asset/102772249876319/Rigged-Dinosaur-Models)
- [BuiltByBit Roblox Assets](https://builtbybit.com/resources/roblox/models/)

---

## Next Steps

1. **Decision Point:** Confirm project structure and agent assignments
2. **Decision Point:** Choose dinosaur models from available sources
3. **Decision Point:** Confirm storm speed configuration
4. Begin Phase 1 implementation with Core Framework
