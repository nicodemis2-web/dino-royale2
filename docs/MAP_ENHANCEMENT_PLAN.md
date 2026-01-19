# Dino Royale 2 - Map Enhancement Plan

## Executive Summary

This document outlines a comprehensive plan to enhance the procedural map generation system with:
1. **Buildings & Structures** - Proper POI buildings with interiors
2. **Flora & Vegetation** - Trees, bushes, grass, and natural obstacles
3. **Loot System Improvements** - FPS-standard chest mechanics
4. **Dinosaur Visibility** - Ensuring dinos spawn and behave correctly
5. **Player Accessibility** - Clear paths and navigable terrain

---

## Current State Analysis

### What Currently Exists ✓
- 6 biomes (jungle, volcanic, swamp, facility, plains, coastal)
- 8 major POIs + 4 minor POIs defined with positions
- Basic terrain generation (flat planes with materials)
- Loot system with 40+ items, rarity tiers, and chests
- Dinosaur AI with 8 types and full behavior system
- Spawn point distribution (player drops, dino spawns, loot grid)

### What's Missing/Placeholder ✗
- Buildings are invisible marker points (no geometry)
- Vegetation is simple cylinder+sphere trees only
- No natural obstacles (rocks, logs, bushes)
- No interior spaces or multi-level structures
- Chests lack proper visual/audio feedback
- Dinosaurs may not be reaching MATCH phase to spawn

---

## Phase 1: Building & Structure Generation

### 1.1 POI Building Types

Create procedural building generators for each POI type:

```lua
-- Building configurations by POI type
local BUILDING_CONFIGS = {
    visitor_center = {
        mainBuilding = {size = Vector3.new(60, 15, 40), floors = 2},
        entrances = 4,
        windows = true,
        furniture = {"desks", "chairs", "displays"}
    },
    research_lab = {
        mainBuilding = {size = Vector3.new(50, 20, 50), floors = 3},
        entrances = 2,
        windows = true,
        furniture = {"lab_tables", "computers", "containment_cells"}
    },
    military_outpost = {
        buildings = {
            {type = "barracks", size = Vector3.new(30, 8, 15)},
            {type = "watchtower", size = Vector3.new(6, 20, 6)},
            {type = "armory", size = Vector3.new(20, 10, 15)}
        },
        walls = true,
        entrances = 1
    },
    -- etc.
}
```

### 1.2 Building Generation Algorithm

```
1. For each POI:
   a. Get building config based on POI type
   b. Generate main structure (walls, roof, floor)
   c. Cut doorways and windows
   d. Add interior floors for multi-story
   e. Place furniture/props
   f. Add loot spawn points inside
   g. Create navigation mesh for AI
```

### 1.3 Accessibility Features

- **Doorways**: Minimum 4 studs wide, 8 studs tall
- **Stairs/Ramps**: 45° max incline, with railings
- **Windows**: Shootable but not walkable (1.5 stud openings)
- **Cover Objects**: Crates, desks at 3-4 stud height for crouch cover

### 1.4 Implementation Priority

| Building Type | Priority | Complexity |
|---------------|----------|------------|
| Research Lab | High | Medium |
| Military Outpost | High | Low |
| Wooden Hut | Medium | Low |
| Watchtower | Medium | Low |
| Visitor Center | Medium | High |
| Warehouse | Low | Low |

---

## Phase 2: Flora & Vegetation System

### 2.1 Vegetation Types by Biome

```lua
local VEGETATION_CONFIG = {
    jungle = {
        trees = {
            {name = "PalmTree", density = 0.3, height = {15, 25}, canopy = 8},
            {name = "JungleTree", density = 0.4, height = {20, 35}, canopy = 12},
            {name = "FernTree", density = 0.2, height = {8, 12}, canopy = 6}
        },
        bushes = {
            {name = "JungleBush", density = 0.5, size = {2, 4}},
            {name = "Fern", density = 0.6, size = {1, 2}}
        },
        groundCover = {
            {name = "TallGrass", density = 0.7, height = 1.5},
            {name = "Vines", density = 0.3}
        },
        rocks = {
            {name = "MossyRock", density = 0.1, size = {3, 8}}
        }
    },
    volcanic = {
        trees = {
            {name = "CharredTree", density = 0.05, height = {10, 15}}
        },
        rocks = {
            {name = "LavaRock", density = 0.3, size = {2, 6}},
            {name = "Obsidian", density = 0.1, size = {4, 10}}
        },
        hazards = {
            {name = "LavaPool", density = 0.05, size = {5, 15}, damage = 10}
        }
    },
    swamp = {
        trees = {
            {name = "SwampTree", density = 0.25, height = {12, 20}},
            {name = "DeadTree", density = 0.15, height = {8, 12}}
        },
        bushes = {
            {name = "SwampBush", density = 0.3, size = {2, 3}},
            {name = "Cattails", density = 0.4, size = {1, 2}}
        },
        water = {
            {name = "ShallowWater", density = 0.2, depth = 2, slowdown = 0.5}
        }
    },
    plains = {
        trees = {
            {name = "OakTree", density = 0.1, height = {15, 25}}
        },
        bushes = {
            {name = "Shrub", density = 0.2, size = {2, 3}}
        },
        groundCover = {
            {name = "Grass", density = 0.8, height = 0.5},
            {name = "Flowers", density = 0.1}
        },
        rocks = {
            {name = "Boulder", density = 0.05, size = {4, 12}}
        }
    },
    coastal = {
        trees = {
            {name = "PalmTree", density = 0.15, height = {12, 18}}
        },
        rocks = {
            {name = "BeachRock", density = 0.1, size = {2, 5}}
        },
        props = {
            {name = "Driftwood", density = 0.1},
            {name = "ShipwreckPiece", density = 0.02}
        }
    },
    facility = {
        trees = {
            {name = "DecorativeTree", density = 0.05, height = {8, 12}}
        },
        props = {
            {name = "Crate", density = 0.1, size = {2, 3}},
            {name = "Barrel", density = 0.15},
            {name = "ConcreteBarrier", density = 0.1}
        }
    }
}
```

### 2.2 Tree Generation Algorithm

```lua
function GenerateTree(treeType, position)
    local tree = Instance.new("Model")

    -- Trunk (cylinder)
    local trunk = Instance.new("Part")
    trunk.Shape = Enum.PartType.Cylinder
    trunk.Size = Vector3.new(height, trunkRadius * 2, trunkRadius * 2)
    trunk.Material = Enum.Material.Wood
    trunk.Anchored = true
    trunk.CanCollide = true  -- Players can hide behind trees

    -- Canopy (union of spheres or mesh)
    local canopy = Instance.new("Part")
    canopy.Shape = Enum.PartType.Ball
    canopy.Size = Vector3.new(canopySize, canopySize, canopySize)
    canopy.Material = Enum.Material.Grass
    canopy.CanCollide = false  -- Bullets pass through leaves
    canopy.Transparency = 0.1

    -- Add collision box for trunk only
    return tree
end
```

### 2.3 Vegetation Placement Rules

1. **Minimum Spacing**: Trees 8+ studs apart, bushes 3+ studs
2. **Path Clearance**: No vegetation within 5 studs of paths
3. **Building Buffer**: No trees within 10 studs of buildings
4. **Spawn Point Buffer**: No vegetation within 8 studs of loot/player spawns
5. **Cluster Grouping**: 60% chance to spawn near existing vegetation

### 2.4 Performance Optimization

- **LOD System**: Reduce detail at distance (>200 studs)
- **Culling**: Don't render vegetation behind player
- **Instancing**: Use same mesh for identical trees
- **Max Per Chunk**: Limit to 50 vegetation items per 100x100 area

---

## Phase 3: Enhanced Loot System

### 3.1 Chest Visual Improvements

```lua
local CHEST_CONFIG = {
    standard = {
        model = "WoodenChest",
        size = Vector3.new(4, 3, 3),
        glowColor = Color3.fromRGB(255, 215, 0),  -- Gold glow
        glowRange = 15,
        soundId = "rbxassetid://CHEST_HUM_ID",
        soundRange = 30,
        openTime = 0.5,
        items = {min = 2, max = 4},
        rarityWeights = {common = 40, uncommon = 30, rare = 20, epic = 8, legendary = 2}
    },
    rare = {
        model = "MetalChest",
        size = Vector3.new(4, 3, 3),
        glowColor = Color3.fromRGB(138, 43, 226),  -- Purple glow
        glowRange = 25,
        soundId = "rbxassetid://RARE_CHEST_HUM_ID",
        soundRange = 50,
        openTime = 1.0,
        items = {min = 3, max = 5},
        rarityWeights = {uncommon = 20, rare = 40, epic = 30, legendary = 10}
    },
    supply_drop = {
        model = "SupplyCrate",
        glowColor = Color3.fromRGB(255, 0, 0),  -- Red glow
        beaconHeight = 100,
        items = {min = 4, max = 6},
        rarityWeights = {rare = 20, epic = 50, legendary = 30},
        exclusiveItems = {"rocket_launcher", "heavy_sniper"}
    }
}
```

### 3.2 Chest Audio System

```lua
-- Ambient chest hum (detectable from distance)
function CreateChestAudio(chest, config)
    local sound = Instance.new("Sound")
    sound.SoundId = config.soundId
    sound.Looped = true
    sound.Volume = 0.5
    sound.RollOffMode = Enum.RollOffMode.Linear
    sound.RollOffMaxDistance = config.soundRange
    sound.Parent = chest
    sound:Play()
end

-- Opening sound effect
function PlayChestOpenSound(chest)
    -- Satisfying click + creak sound
    local openSound = Instance.new("Sound")
    openSound.SoundId = "rbxassetid://CHEST_OPEN_ID"
    openSound:Play()
end
```

### 3.3 Visual Loot Indicators

```lua
-- Rarity color coding (industry standard)
local RARITY_COLORS = {
    common = Color3.fromRGB(180, 180, 180),     -- Gray
    uncommon = Color3.fromRGB(30, 255, 30),     -- Green
    rare = Color3.fromRGB(30, 144, 255),        -- Blue
    epic = Color3.fromRGB(163, 53, 238),        -- Purple
    legendary = Color3.fromRGB(255, 165, 0),    -- Orange/Gold
    mythic = Color3.fromRGB(255, 0, 128)        -- Pink/Magenta
}

-- Glow effect for epic+ items
function AddLootGlow(item, rarity)
    if rarity == "epic" or rarity == "legendary" or rarity == "mythic" then
        local light = Instance.new("PointLight")
        light.Color = RARITY_COLORS[rarity]
        light.Brightness = 2
        light.Range = 10
        light.Parent = item

        -- Particle effect
        local particles = Instance.new("ParticleEmitter")
        particles.Color = ColorSequence.new(RARITY_COLORS[rarity])
        particles.Rate = 20
        particles.Parent = item
    end
end
```

### 3.4 Loot Distribution Zones

```lua
-- Map divided into loot tiers
local LOOT_ZONES = {
    high_tier = {
        pois = {"GeneticsLab", "VisitorCenter", "TRexKingdom"},
        legendaryChance = 0.1,
        epicChance = 0.25
    },
    mid_tier = {
        pois = {"RaptorPaddock", "MainDock", "SwampOutpost"},
        legendaryChance = 0.05,
        epicChance = 0.15
    },
    low_tier = {
        areas = "default",
        legendaryChance = 0.02,
        epicChance = 0.08
    }
}
```

---

## Phase 4: Dinosaur Visibility Fix

### 4.1 Current Issue Diagnosis

The dinosaur system is fully implemented but may not be running because:

1. **StartSpawning() timing**: Called in MatchPhase, but game may not reach MATCH state
2. **Spawn points**: Falls back to ring around origin if MapService doesn't provide points
3. **Placeholder models**: Only green cubes appear if no actual models loaded

### 4.2 Immediate Fixes

```lua
-- In GameService:Initialize(), add early dino test spawn
if gameConfig.TestMode and gameConfig.TestMode.enabled then
    task.defer(function()
        task.wait(5)  -- Wait for initialization
        local dinoService = framework:GetService("DinoService")
        if dinoService then
            -- Force spawn a test dinosaur
            dinoService:SpawnDinosaur("raptor", Vector3.new(50, 10, 50))
            print("[DinoRoyale] TEST MODE: Spawned test raptor")
        end
    end)
end
```

### 4.3 Better Dinosaur Models

```lua
-- Enhanced placeholder with visible features
function CreateVisibleDinoPlaceholder(dinoType, config)
    local model = Instance.new("Model")

    -- Body (elongated for dino shape)
    local body = Instance.new("Part")
    body.Size = Vector3.new(config.length, config.height, config.width)
    body.Color = config.color  -- Green for herbivores, red for carnivores
    body.Material = Enum.Material.SmoothPlastic

    -- Head (sphere at front)
    local head = Instance.new("Part")
    head.Shape = Enum.PartType.Ball
    head.Size = Vector3.new(config.height * 0.6, config.height * 0.6, config.height * 0.6)

    -- Tail (wedge at back)
    local tail = Instance.new("WedgePart")
    tail.Size = Vector3.new(config.width * 0.5, config.height * 0.3, config.length * 0.5)

    -- Name billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 100, 0, 30)
    billboard.StudsOffset = Vector3.new(0, config.height + 2, 0)

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Text = dinoType:upper()
    nameLabel.TextColor3 = Color3.new(1, 0, 0)
    nameLabel.Parent = billboard

    return model
end
```

### 4.4 Dinosaur Size Reference

| Dinosaur | Length | Height | Width | Color |
|----------|--------|--------|-------|-------|
| Raptor | 6 | 4 | 2 | Green |
| T-Rex | 20 | 12 | 6 | Dark Red |
| Pteranodon | 8 | 3 | 12 | Gray |
| Triceratops | 12 | 6 | 5 | Brown |
| Dilophosaurus | 8 | 5 | 3 | Yellow-Green |
| Carnotaurus | 10 | 6 | 4 | Red |
| Compy | 1.5 | 1 | 0.5 | Light Green |
| Spinosaurus | 18 | 10 | 5 | Dark Green |

---

## Phase 5: Player Accessibility

### 5.1 Path Generation Between POIs

```lua
-- Generate walking paths connecting major POIs
function GeneratePaths()
    local pois = MapService:GetPOIs()

    -- Create minimum spanning tree of POI connections
    local connections = CalculateMST(pois)

    for _, connection in ipairs(connections) do
        local path = CreatePath(connection.from, connection.to)

        -- Clear vegetation along path
        ClearVegetationInRadius(path, 5)

        -- Flatten terrain slightly
        SmoothTerrainAlongPath(path)

        -- Add path visual (dirt/gravel material)
        CreatePathVisual(path, 4)  -- 4 stud wide
    end
end
```

### 5.2 Terrain Smoothing

```lua
-- Ensure no steep cliffs or impassable terrain
function ValidateTerrainAccessibility()
    local gridSize = 10

    for x = -MAP_SIZE/2, MAP_SIZE/2, gridSize do
        for z = -MAP_SIZE/2, MAP_SIZE/2, gridSize do
            local height = GetTerrainHeight(x, z)
            local neighbors = GetNeighborHeights(x, z, gridSize)

            -- Max slope: 45 degrees (1:1 ratio)
            for _, neighborHeight in ipairs(neighbors) do
                local slope = math.abs(height - neighborHeight) / gridSize
                if slope > 1 then
                    -- Smooth the terrain
                    SmoothTerrain(x, z, neighborHeight)
                end
            end
        end
    end
end
```

### 5.3 Spawn Point Validation

```lua
-- Ensure all spawn points are accessible
function ValidateSpawnPoints()
    local spawnPoints = MapService:GetPlayerSpawnPoints()

    for i, point in ipairs(spawnPoints) do
        -- Raycast down to find ground
        local groundPos = FindGroundPosition(point)

        -- Check for obstructions
        local obstructed = CheckForObstructions(groundPos, 3)  -- 3 stud radius

        if obstructed then
            -- Move spawn point to nearest clear location
            spawnPoints[i] = FindNearestClearPosition(point)
        end

        -- Ensure minimum distance from hazards
        local nearHazard = CheckNearHazard(spawnPoints[i], 10)
        if nearHazard then
            spawnPoints[i] = MoveAwayFromHazard(spawnPoints[i], 15)
        end
    end
end
```

---

## Implementation Timeline

### Week 1: Core Fixes
- [ ] Fix dinosaur spawning (ensure StartSpawning is called)
- [ ] Add visible dinosaur placeholder models with proper sizes
- [ ] Add chest glow and ambient sound effects
- [ ] Validate all spawn points are accessible

### Week 2: Buildings
- [ ] Implement procedural building generator
- [ ] Create 3 basic building types (hut, watchtower, warehouse)
- [ ] Add interior spaces with loot points
- [ ] Place buildings at POI locations

### Week 3: Vegetation
- [ ] Implement tree generation with collision
- [ ] Add bushes and ground cover
- [ ] Implement rock/obstacle placement
- [ ] Add biome-specific vegetation variety

### Week 4: Polish
- [ ] Generate paths between POIs
- [ ] Smooth terrain accessibility
- [ ] Add loot zone tiering
- [ ] Performance optimization pass

---

## Testing Checklist

### Dinosaurs
- [ ] Dinosaurs spawn during match phase
- [ ] Dinosaurs are visible (not underground or invisible)
- [ ] Dinosaurs chase players within aggro range
- [ ] Dinosaurs deal damage on attack
- [ ] Pack behavior works (raptors coordinate)

### Buildings
- [ ] All POIs have visible structures
- [ ] Players can enter buildings
- [ ] Loot spawns inside buildings
- [ ] Cover objects provide protection

### Vegetation
- [ ] Trees have collision (can hide behind)
- [ ] Density varies by biome
- [ ] No vegetation blocking spawn points
- [ ] Performance stays above 30 FPS

### Loot
- [ ] Chests glow and make sound
- [ ] Opening chests spawns items
- [ ] Rarity colors are correct
- [ ] Epic+ items have particle effects

### Accessibility
- [ ] All POIs reachable on foot
- [ ] No stuck spots in terrain
- [ ] Spawn points are in clear areas
- [ ] Paths visible between POIs

---

## Technical Notes

### Asset Integration
The MapAssets module is ready to load external assets. To add real models:

1. Upload model to Roblox Creator Store
2. Add asset ID to `module/MapAssets/AssetManifest.lua`
3. MapAssets will automatically cache and spawn them

### Performance Targets
- Max 500 vegetation objects visible at once
- Max 15 dinosaurs active at once
- Max 100 loot items on ground
- Target: 60 FPS on mid-range hardware

### Collision Layers
- Trees: Collision ON (trunk), OFF (canopy)
- Bushes: Collision OFF (visual only)
- Rocks: Collision ON
- Buildings: Collision ON
- Loot: Collision OFF (use ProximityPrompt)
