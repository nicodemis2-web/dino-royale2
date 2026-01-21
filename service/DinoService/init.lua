--[[
    DinoService - Advanced Dinosaur AI System

    A comprehensive dinosaur AI and spawning system for Dino Royale 2.
    Handles spawning, behavior trees, pack tactics, special abilities, and boss fights.

    =============================================================================
    FEATURES
    =============================================================================

    1. BEHAVIOR TYPES:
       - pack_hunter: Raptors that coordinate attacks with flanking maneuvers
       - solo_predator: T-Rex with charge attacks and ground pound
       - aerial_diver: Pteranodons that dive-bomb from above
       - defensive_charger: Triceratops that charge when threatened
       - ranged_spitter: Dilophosaurus with blinding venom attacks
       - ambush_predator: Stealth dinosaurs that hide and pounce
       - swarm: Small dinosaurs that attack in large numbers

    2. PACK TACTICS:
       - Pack leader designation and following behavior
       - Coordinated flanking attacks
       - Pack morale system (flee when leader dies)
       - Communication calls between pack members
       - Synchronized attack timing

    3. SPECIAL ABILITIES:
       - Roar (fear/stun effects)
       - Charge (knockback + bonus damage)
       - Pounce (gap closer)
       - Venom spit (blind + DoT)
       - Tail swipe (AoE knockback)
       - Ground pound (AoE stun)
       - Dive bomb (aerial attack)
       - Camouflage (stealth)

    4. BOSS SYSTEM:
       - Alpha variants with enhanced stats
       - Unique boss abilities and attack patterns
       - Multi-phase boss fights
       - Rage modes at low health
       - Guaranteed legendary loot drops

    5. ENVIRONMENTAL AWARENESS:
       - Dinosaurs react to storm damage
       - Territorial behavior near nests
       - Day/night behavior changes
       - Weather effects on aggression

    =============================================================================
    ARCHITECTURE
    =============================================================================

    State Machine States:
    - idle: Wandering or resting
    - alert: Detected threat, deciding action
    - hunting: Searching for target
    - chasing: Pursuing target
    - attacking: Executing attack
    - ability: Using special ability
    - fleeing: Running away (low health/pack scattered)
    - stunned: Temporarily disabled
    - dead: Awaiting cleanup

    =============================================================================
    USAGE
    =============================================================================

    local DinoService = framework:GetService("DinoService")
    DinoService:Initialize()
    DinoService:StartSpawning()

    -- Spawn a boss
    DinoService:SpawnBoss("alpha_rex", position)

    -- Damage a dinosaur
    DinoService:DamageDinosaur(dinoId, damage, attacker)

    =============================================================================
]]

--=============================================================================
-- SERVICES
--=============================================================================

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

--=============================================================================
-- MODULE SETUP
--=============================================================================

local DinoService = {}
DinoService.__index = DinoService

--=============================================================================
-- CONSTANTS
--=============================================================================

-- AI update rate (seconds between AI ticks)
local AI_UPDATE_RATE = 0.2

-- Pack behavior constants
local PACK_FOLLOW_DISTANCE = 15        -- Distance pack members maintain from leader
local PACK_SCATTER_DISTANCE = 50       -- Distance before pack is considered scattered
local FLANK_ANGLE = math.rad(45)       -- Angle for flanking maneuvers

-- Ability cooldowns (seconds)
local ABILITY_COOLDOWNS = {
    roar = 15,
    charge = 8,
    pounce = 5,
    venom_spit = 6,
    tail_swipe = 4,
    ground_pound = 12,
    dive_bomb = 7,
    camouflage = 20,
}

-- Boss phase thresholds (percentage of max health)
local BOSS_PHASE_THRESHOLDS = {
    phase2 = 0.66,   -- 66% health triggers phase 2
    phase3 = 0.33,   -- 33% health triggers phase 3 (rage mode)
}

--=============================================================================
-- SPATIAL HASH GRID
-- Optimizes target finding from O(n) to O(1) average case
-- Grid divides the map into cells, each cell tracks nearby players
--=============================================================================
local GRID_CELL_SIZE = 50  -- studs per cell (should be >= max aggro radius)
local spatialGrid = {}     -- [cellX][cellZ] = {[playerId] = true}
local playerCells = {}     -- [playerId] = {x = cellX, z = cellZ}

--[[
    Get grid cell coordinates for a world position
    @param position Vector3
    @return number, number - cellX, cellZ
]]
local function getGridCell(position)
    local cellX = math.floor(position.X / GRID_CELL_SIZE)
    local cellZ = math.floor(position.Z / GRID_CELL_SIZE)
    return cellX, cellZ
end

--[[
    Update a player's position in the spatial grid
    @param player Player
    @param position Vector3
]]
local function updatePlayerInGrid(player, position)
    local userId = player.UserId
    local newCellX, newCellZ = getGridCell(position)

    -- Check if player changed cells
    local oldCell = playerCells[userId]
    if oldCell and oldCell.x == newCellX and oldCell.z == newCellZ then
        return -- Same cell, no update needed
    end

    -- Remove from old cell
    if oldCell then
        local oldGrid = spatialGrid[oldCell.x]
        if oldGrid and oldGrid[oldCell.z] then
            oldGrid[oldCell.z][userId] = nil
        end
    end

    -- Add to new cell
    if not spatialGrid[newCellX] then
        spatialGrid[newCellX] = {}
    end
    if not spatialGrid[newCellX][newCellZ] then
        spatialGrid[newCellX][newCellZ] = {}
    end
    spatialGrid[newCellX][newCellZ][userId] = true

    -- Update player's cell reference
    playerCells[userId] = {x = newCellX, z = newCellZ}
end

--[[
    Remove a player from the spatial grid
    @param player Player
]]
local function removePlayerFromGrid(player)
    local userId = player.UserId
    local cell = playerCells[userId]
    if cell then
        local grid = spatialGrid[cell.x]
        if grid and grid[cell.z] then
            grid[cell.z][userId] = nil
        end
    end
    playerCells[userId] = nil
end

--[[
    Get all player IDs in nearby cells
    @param position Vector3
    @param radius number - Search radius in studs
    @return table - Array of player UserIds
]]
local function getPlayersInRadius(position, radius)
    local cellX, cellZ = getGridCell(position)
    local cellRadius = math.ceil(radius / GRID_CELL_SIZE)

    local nearbyPlayers = {}

    for dx = -cellRadius, cellRadius do
        for dz = -cellRadius, cellRadius do
            local grid = spatialGrid[cellX + dx]
            if grid then
                local cell = grid[cellZ + dz]
                if cell then
                    for userId, _ in pairs(cell) do
                        table.insert(nearbyPlayers, userId)
                    end
                end
            end
        end
    end

    return nearbyPlayers
end

--=============================================================================
-- DINOSAUR DEFINITIONS
-- Comprehensive stats and abilities for each dinosaur type
--=============================================================================

local DINOSAUR_DEFINITIONS = {
    --=========================================================================
    -- RAPTOR - Pack Hunter
    -- Fast, agile pack hunters that coordinate flanking attacks
    -- Real size: 1.5-2m long, 0.5m hip height, turkey-sized
    -- Game scale: Slightly larger for visibility (~2m tall at hip for gameplay)
    --=========================================================================
    raptor = {
        name = "Velociraptor",
        category = "pack_hunter",

        -- Base stats
        health = 150,
        speed = 28,
        damage = 20,
        attackRange = 6,
        attackCooldown = 1.5,

        -- Spawn settings
        spawnWeight = 40,
        packSize = {min = 2, max = 4},

        -- Visual settings (realistic proportions, scaled for gameplay)
        -- Body: Width x Height x Length in studs (1 stud ≈ 0.28m)
        modelSize = Vector3.new(1.5, 2, 4),  -- Sleek, low predator
        color = Color3.fromRGB(85, 95, 65),  -- Olive green-brown
        secondaryColor = Color3.fromRGB(120, 110, 85),  -- Lighter underbelly
        stripeColor = Color3.fromRGB(45, 55, 35),  -- Dark stripes
        materialType = "scales",  -- Scaly skin

        -- Behavior settings
        aggressionRadius = 80,
        fleeHealthPercent = 0.15,

        -- Abilities
        abilities = {
            pounce = {
                enabled = true,
                damage = 35,
                range = 15,
                cooldown = 5,
                stunDuration = 0.5,
            },
        },

        -- Pack behavior
        packBehavior = {
            flanking = true,
            coordinatedAttacks = true,
            leaderBonus = 1.2,  -- 20% damage bonus when leader alive
            scatterOnLeaderDeath = true,
            callRange = 40,     -- Range to alert pack members
        },

        -- Loot drops
        lootTable = {
            {item = "raptor_claw", chance = 0.3, rarity = "uncommon"},
            {item = "dino_meat", chance = 0.5, rarity = "common"},
            {item = "medium_ammo", chance = 0.4, count = {10, 20}},
        },
    },

    --=========================================================================
    -- T-REX - Solo Predator
    -- Massive apex predator with devastating attacks
    -- Real size: 12-13m long, 4m hip height, 6-8 tons
    -- Game scale: Imposing presence (scaled appropriately)
    --=========================================================================
    trex = {
        name = "Tyrannosaurus Rex",
        category = "solo_predator",

        -- Base stats
        health = 800,
        speed = 18,
        damage = 60,
        attackRange = 12,
        attackCooldown = 2.5,

        -- Spawn settings
        spawnWeight = 10,
        packSize = {min = 1, max = 1},

        -- Visual settings (massive, terrifying predator)
        modelSize = Vector3.new(6, 12, 24),  -- Tall, powerful stance
        color = Color3.fromRGB(75, 55, 40),  -- Dark brown
        secondaryColor = Color3.fromRGB(95, 75, 55),  -- Lighter underbelly
        accentColor = Color3.fromRGB(50, 35, 25),  -- Dark accent patches
        materialType = "rough_scales",  -- Thick, rough hide

        -- Behavior settings
        aggressionRadius = 100,
        fleeHealthPercent = 0,  -- Never flees

        -- Abilities
        abilities = {
            roar = {
                enabled = true,
                fearRadius = 30,
                fearDuration = 3,
                cooldown = 15,
            },
            charge = {
                enabled = true,
                damage = 80,
                range = 25,
                knockback = 50,
                cooldown = 8,
            },
            tail_swipe = {
                enabled = true,
                damage = 40,
                radius = 15,
                knockback = 30,
                cooldown = 4,
            },
        },

        -- Loot drops
        lootTable = {
            {item = "rex_tooth", chance = 0.5, rarity = "rare"},
            {item = "dino_heart", chance = 0.2, rarity = "epic"},
            {item = "heavy_ammo", chance = 0.6, count = {15, 30}},
            {item = "health_kit", chance = 0.4, rarity = "uncommon"},
        },
    },

    --=========================================================================
    -- PTERANODON - Aerial Diver
    -- Flying predator that dive-bombs targets
    -- Real size: 6m wingspan, 1.8m body length
    -- Game scale: Impressive wingspan for aerial presence
    --=========================================================================
    pteranodon = {
        name = "Pteranodon",
        category = "aerial_diver",

        -- Base stats
        health = 100,
        speed = 35,
        damage = 15,
        attackRange = 8,
        attackCooldown = 2,

        -- Spawn settings
        spawnWeight = 25,
        packSize = {min = 1, max = 3},

        -- Visual settings (wide wingspan, sleek body)
        modelSize = Vector3.new(12, 2, 4),  -- Wide wingspan
        color = Color3.fromRGB(110, 90, 70),  -- Tan/brown
        secondaryColor = Color3.fromRGB(85, 70, 55),  -- Darker wing membrane
        accentColor = Color3.fromRGB(140, 120, 95),  -- Lighter crest
        materialType = "membrane",  -- Leathery wings

        -- Flight settings
        isFlying = true,
        flightHeight = 30,
        diveSpeed = 80,

        -- Behavior settings
        aggressionRadius = 120,  -- Larger due to aerial view
        fleeHealthPercent = 0.3,

        -- Abilities
        abilities = {
            dive_bomb = {
                enabled = true,
                damage = 45,
                cooldown = 7,
                stunOnHit = 1,
            },
        },

        -- Loot drops
        lootTable = {
            {item = "pteranodon_wing", chance = 0.25, rarity = "uncommon"},
            {item = "light_ammo", chance = 0.5, count = {15, 25}},
        },
    },

    --=========================================================================
    -- TRICERATOPS - Defensive Charger
    -- Heavily armored herbivore that charges when threatened
    -- Real size: 8-9m long, 3m tall, 6-12 tons
    -- Game scale: Bulky, imposing tank-like dinosaur
    --=========================================================================
    triceratops = {
        name = "Triceratops",
        category = "defensive_charger",

        -- Base stats
        health = 500,
        speed = 15,
        damage = 40,
        attackRange = 10,
        attackCooldown = 3,
        armor = 0.3,  -- 30% damage reduction

        -- Spawn settings
        spawnWeight = 15,
        packSize = {min = 1, max = 2},

        -- Visual settings (bulky, armored herbivore)
        modelSize = Vector3.new(5, 6, 14),  -- Wide, sturdy build
        color = Color3.fromRGB(130, 115, 90),  -- Sandy brown
        secondaryColor = Color3.fromRGB(160, 145, 120),  -- Lighter underbelly
        accentColor = Color3.fromRGB(100, 85, 65),  -- Darker frill
        hornColor = Color3.fromRGB(245, 235, 210),  -- Ivory horns
        materialType = "armored",  -- Thick armored hide

        -- Behavior settings
        aggressionRadius = 40,  -- Less aggressive, needs provocation
        fleeHealthPercent = 0.1,
        isPassive = true,       -- Only attacks when attacked first

        -- Abilities
        abilities = {
            charge = {
                enabled = true,
                damage = 70,
                range = 30,
                knockback = 60,
                cooldown = 6,
                stunDuration = 1.5,
            },
        },

        -- Loot drops
        lootTable = {
            {item = "trike_horn", chance = 0.4, rarity = "rare"},
            {item = "dino_hide", chance = 0.6, rarity = "uncommon"},
            {item = "shield_potion", chance = 0.3, rarity = "uncommon"},
        },
    },

    --=========================================================================
    -- DILOPHOSAURUS - Ranged Spitter
    -- Venomous dinosaur with ranged blind attack
    -- Real size: 6m long, 2m tall
    -- Game scale: Medium-sized, distinctive crests
    --=========================================================================
    dilophosaurus = {
        name = "Dilophosaurus",
        category = "ranged_spitter",

        -- Base stats
        health = 120,
        speed = 22,
        damage = 25,
        attackRange = 20,  -- Ranged attack
        attackCooldown = 2,

        -- Spawn settings
        spawnWeight = 20,
        packSize = {min = 1, max = 2},

        -- Visual settings (distinctive crests, colorful warning colors)
        modelSize = Vector3.new(2, 4, 8),  -- Lean, agile build
        color = Color3.fromRGB(55, 95, 75),  -- Deep teal-green
        secondaryColor = Color3.fromRGB(80, 120, 95),  -- Lighter belly
        accentColor = Color3.fromRGB(180, 80, 50),  -- Orange-red frill/crest
        materialType = "smooth_scales",  -- Sleek skin

        -- Behavior settings
        aggressionRadius = 60,
        fleeHealthPercent = 0.25,
        prefersRanged = true,   -- Maintains distance

        -- Abilities
        abilities = {
            venom_spit = {
                enabled = true,
                damage = 15,
                range = 25,
                cooldown = 6,
                blindDuration = 4,
                dotDamage = 5,
                dotDuration = 5,
            },
        },

        -- Loot drops
        lootTable = {
            {item = "venom_gland", chance = 0.35, rarity = "rare"},
            {item = "dino_meat", chance = 0.4, rarity = "common"},
            {item = "smoke_grenade", chance = 0.2, rarity = "uncommon"},
        },
    },

    --=========================================================================
    -- CARNOTAURUS - Ambush Predator
    -- Camouflaged hunter that ambushes prey
    -- Real size: 8m long, 3m tall, distinctive horns above eyes
    -- Game scale: Fast, muscular predator
    --=========================================================================
    carnotaurus = {
        name = "Carnotaurus",
        category = "ambush_predator",

        -- Base stats
        health = 300,
        speed = 30,
        damage = 45,
        attackRange = 8,
        attackCooldown = 2,

        -- Spawn settings
        spawnWeight = 12,
        packSize = {min = 1, max = 1},

        -- Visual settings (muscular build, distinctive horns)
        modelSize = Vector3.new(3.5, 5, 12),  -- Streamlined for speed
        color = Color3.fromRGB(95, 60, 50),  -- Reddish-brown
        secondaryColor = Color3.fromRGB(125, 85, 70),  -- Lighter areas
        accentColor = Color3.fromRGB(65, 40, 35),  -- Dark stripes
        hornColor = Color3.fromRGB(60, 50, 45),  -- Dark horns
        materialType = "rough_scales",  -- Bumpy hide

        -- Behavior settings
        aggressionRadius = 50,
        fleeHealthPercent = 0.2,

        -- Abilities
        abilities = {
            camouflage = {
                enabled = true,
                duration = 10,
                cooldown = 20,
                ambushDamageBonus = 2.0,  -- Double damage from stealth
            },
            pounce = {
                enabled = true,
                damage = 50,
                range = 12,
                cooldown = 5,
            },
        },

        -- Loot drops
        lootTable = {
            {item = "carno_hide", chance = 0.4, rarity = "rare"},
            {item = "stealth_kit", chance = 0.15, rarity = "epic"},
        },
    },

    --=========================================================================
    -- COMPSOGNATHUS - Swarm
    -- Tiny dinosaurs that attack in overwhelming numbers
    -- Real size: 0.6-1m long, chicken-sized
    -- Game scale: Small but visible, swarming threat
    --=========================================================================
    compy = {
        name = "Compsognathus",
        category = "swarm",

        -- Base stats
        health = 25,
        speed = 32,
        damage = 8,
        attackRange = 3,
        attackCooldown = 0.8,

        -- Spawn settings
        spawnWeight = 18,
        packSize = {min = 5, max = 10},

        -- Visual settings (tiny, numerous)
        modelSize = Vector3.new(0.4, 0.6, 1.2),  -- Very small
        color = Color3.fromRGB(75, 85, 60),  -- Greenish-brown
        secondaryColor = Color3.fromRGB(95, 105, 75),  -- Lighter belly
        accentColor = Color3.fromRGB(55, 65, 45),  -- Dark markings
        materialType = "smooth_scales",  -- Fine scales

        -- Behavior settings
        aggressionRadius = 30,
        fleeHealthPercent = 0,  -- Swarm doesn't flee

        -- Swarm behavior
        swarmBehavior = {
            surround = true,
            damageBonus = 0.1,  -- +10% damage per nearby swarm member
            maxBonus = 2.0,     -- Cap at 200% damage
        },

        -- Loot drops (low individual drops, compensated by numbers)
        lootTable = {
            {item = "light_ammo", chance = 0.2, count = {5, 10}},
            {item = "bandage", chance = 0.1, rarity = "common"},
        },
    },

    --=========================================================================
    -- SPINOSAURUS - Apex Predator
    -- Large semi-aquatic predator with distinctive sail
    -- Real size: 15-18m long, largest carnivorous dinosaur
    -- Game scale: Massive, distinctive sail on back
    --=========================================================================
    spinosaurus = {
        name = "Spinosaurus",
        category = "solo_predator",

        -- Base stats
        health = 650,
        speed = 20,
        damage = 55,
        attackRange = 14,
        attackCooldown = 2.2,

        -- Spawn settings
        spawnWeight = 8,
        packSize = {min = 1, max = 1},

        -- Visual settings (massive with distinctive sail)
        modelSize = Vector3.new(5, 10, 22),  -- Long, powerful build
        color = Color3.fromRGB(90, 80, 65),  -- Earthy brown
        secondaryColor = Color3.fromRGB(115, 100, 80),  -- Lighter underbelly
        sailColor = Color3.fromRGB(140, 60, 45),  -- Reddish sail
        accentColor = Color3.fromRGB(70, 60, 50),  -- Dark stripes
        materialType = "rough_scales",  -- Semi-aquatic hide

        -- Behavior settings
        aggressionRadius = 90,
        fleeHealthPercent = 0.1,

        -- Abilities
        abilities = {
            tail_swipe = {
                enabled = true,
                damage = 35,
                radius = 12,
                knockback = 40,
                cooldown = 3,
            },
            roar = {
                enabled = true,
                fearRadius = 25,
                fearDuration = 2,
                cooldown = 12,
            },
        },

        -- Loot drops
        lootTable = {
            {item = "spino_sail", chance = 0.45, rarity = "rare"},
            {item = "dino_heart", chance = 0.15, rarity = "epic"},
            {item = "heavy_ammo", chance = 0.5, count = {10, 25}},
        },
    },
}

--=============================================================================
-- BOSS DEFINITIONS
-- Alpha variants with unique abilities and enhanced stats
--=============================================================================

local BOSS_DEFINITIONS = {
    --=========================================================================
    -- ALPHA REX - The Tyrant King
    -- Massive T-Rex with ground pound and enrage abilities
    --=========================================================================
    alpha_rex = {
        name = "Alpha Rex - The Tyrant King",
        baseDino = "trex",

        -- Stat multipliers
        healthMultiplier = 3.0,     -- 2400 HP
        damageMultiplier = 1.5,     -- 90 base damage
        speedMultiplier = 1.1,
        sizeMultiplier = 1.5,

        -- Visual
        color = Color3.fromRGB(100, 20, 20),  -- Darker red
        glowEnabled = true,
        glowColor = Color3.fromRGB(255, 50, 50),

        -- Boss-specific abilities
        abilities = {
            ground_pound = {
                enabled = true,
                damage = 100,
                radius = 25,
                stunDuration = 2,
                cooldown = 12,
            },
            summon_minions = {
                enabled = true,
                minionType = "raptor",
                count = 3,
                cooldown = 30,
            },
        },

        -- Phase behaviors
        phases = {
            [1] = {
                attackPattern = {"bite", "tail_swipe", "roar"},
                aggressionBonus = 0,
            },
            [2] = {
                attackPattern = {"charge", "ground_pound", "bite", "tail_swipe"},
                aggressionBonus = 0.2,
                abilityUnlock = "ground_pound",
            },
            [3] = {  -- Rage mode
                attackPattern = {"charge", "ground_pound", "summon_minions", "bite"},
                aggressionBonus = 0.5,
                speedBonus = 0.3,
                damageBonus = 0.5,
                abilityUnlock = "summon_minions",
            },
        },

        -- Guaranteed drops
        lootTable = {
            {item = "alpha_rex_trophy", chance = 1.0, rarity = "legendary"},
            {item = "rex_heart", chance = 1.0, rarity = "epic"},
            {item = "legendary_weapon_crate", chance = 0.5, rarity = "legendary"},
            {item = "heavy_ammo", chance = 1.0, count = {50, 100}},
        },
    },

    --=========================================================================
    -- ALPHA RAPTOR - The Pack Matriarch
    -- Supreme pack leader with enhanced pack bonuses
    --=========================================================================
    alpha_raptor = {
        name = "Alpha Raptor - Pack Matriarch",
        baseDino = "raptor",

        -- Stat multipliers
        healthMultiplier = 4.0,     -- 600 HP
        damageMultiplier = 2.0,     -- 40 base damage
        speedMultiplier = 1.2,
        sizeMultiplier = 1.3,

        -- Visual
        color = Color3.fromRGB(80, 20, 80),  -- Purple
        glowEnabled = true,
        glowColor = Color3.fromRGB(200, 50, 200),

        -- Always spawns with pack
        packOnSpawn = {type = "raptor", count = 4},

        -- Boss-specific abilities
        abilities = {
            pack_call = {
                enabled = true,
                summonType = "raptor",
                count = 2,
                cooldown = 20,
                buffDuration = 10,
                packDamageBonus = 0.5,
            },
            frenzy = {
                enabled = true,
                duration = 8,
                attackSpeedBonus = 2.0,
                cooldown = 25,
            },
        },

        -- Phase behaviors
        phases = {
            [1] = {
                attackPattern = {"pounce", "bite", "bite"},
                packCoordination = true,
            },
            [2] = {
                attackPattern = {"pack_call", "pounce", "bite", "frenzy"},
                packFlanking = true,
            },
            [3] = {  -- Rage mode
                attackPattern = {"pack_call", "frenzy", "pounce", "pounce"},
                permanentFrenzy = true,
            },
        },

        -- Guaranteed drops
        lootTable = {
            {item = "alpha_raptor_claw", chance = 1.0, rarity = "legendary"},
            {item = "pack_leader_helm", chance = 0.3, rarity = "legendary"},
            {item = "epic_weapon_crate", chance = 0.7, rarity = "epic"},
        },
    },

    --=========================================================================
    -- ALPHA SPINO - The River Terror
    -- Aquatic boss with water-based abilities
    --=========================================================================
    alpha_spino = {
        name = "Alpha Spinosaurus - River Terror",
        baseDino = "spinosaurus",

        -- Stat multipliers
        healthMultiplier = 2.5,
        damageMultiplier = 1.4,
        speedMultiplier = 1.15,
        sizeMultiplier = 1.4,

        -- Visual
        color = Color3.fromRGB(30, 60, 80),  -- Deep blue
        glowEnabled = true,
        glowColor = Color3.fromRGB(50, 150, 255),

        -- Boss-specific abilities
        abilities = {
            tidal_wave = {
                enabled = true,
                damage = 60,
                range = 35,
                knockback = 70,
                slowDuration = 3,
                cooldown = 15,
            },
            submerge = {
                enabled = true,
                duration = 5,
                healPercent = 0.1,
                cooldown = 30,
            },
        },

        -- Phase behaviors
        phases = {
            [1] = {
                attackPattern = {"bite", "tail_swipe", "roar"},
            },
            [2] = {
                attackPattern = {"tidal_wave", "bite", "tail_swipe"},
                abilityUnlock = "tidal_wave",
            },
            [3] = {
                attackPattern = {"submerge", "tidal_wave", "tail_swipe", "bite"},
                permanentAggression = true,
            },
        },

        -- Guaranteed drops
        lootTable = {
            {item = "spino_alpha_sail", chance = 1.0, rarity = "legendary"},
            {item = "aquatic_gear", chance = 0.4, rarity = "epic"},
            {item = "legendary_weapon_crate", chance = 0.35, rarity = "legendary"},
        },
    },

    --=========================================================================
    -- DRAGON - The Sky Terror
    -- Flying dragon that periodically raids the island
    -- Flies across the map attacking players, then leaves
    --=========================================================================
    dragon = {
        name = "Dragon - The Sky Terror",
        baseDino = "pteranodon",  -- Uses pteranodon as base for flying logic

        -- Stat multipliers (very powerful)
        healthMultiplier = 5.0,     -- 500 HP
        damageMultiplier = 3.0,     -- 45 base damage
        speedMultiplier = 2.0,      -- Very fast
        sizeMultiplier = 3.0,       -- Large and terrifying

        -- Visual
        color = Color3.fromRGB(20, 20, 20),    -- Dark black/gray
        glowEnabled = true,
        glowColor = Color3.fromRGB(255, 100, 0),  -- Fiery orange glow

        -- Dragon-specific behavior
        isDragon = true,
        flyHeight = 80,             -- Height above terrain
        flySpeed = 100,             -- Studs per second
        attackDiveSpeed = 150,      -- Speed during attack dive
        raidDuration = 60,          -- Seconds before dragon leaves
        attackInterval = 8,         -- Seconds between attacks

        -- Boss-specific abilities
        abilities = {
            fire_breath = {
                enabled = true,
                damage = 50,
                radius = 20,
                duration = 2,
                cooldown = 10,
            },
            dive_attack = {
                enabled = true,
                damage = 80,
                knockback = 50,
                cooldown = 15,
            },
            terrifying_roar = {
                enabled = true,
                fearDuration = 3,
                radius = 60,
                cooldown = 20,
            },
        },

        -- Phase behaviors (dragon doesn't have traditional phases, uses raid pattern)
        phases = {
            [1] = {
                attackPattern = {"dive_attack", "fire_breath"},
            },
            [2] = {
                attackPattern = {"terrifying_roar", "dive_attack", "fire_breath"},
                aggressionBonus = 0.3,
            },
            [3] = {
                attackPattern = {"terrifying_roar", "fire_breath", "dive_attack", "fire_breath"},
                aggressionBonus = 0.5,
            },
        },

        -- Sound IDs for dragon (scary sounds)
        sounds = {
            approach = "rbxassetid://9120916792",      -- Deep rumbling roar
            roar = "rbxassetid://9120916792",          -- Terrifying roar
            attack = "rbxassetid://9118895116",        -- Attack screech
            wingFlap = "rbxassetid://9112854745",      -- Wing flapping
            fireBreath = "rbxassetid://9114256606",    -- Fire sound
        },

        -- Guaranteed drops (only if killed)
        lootTable = {
            {item = "dragon_heart", chance = 1.0, rarity = "legendary"},
            {item = "dragon_scale", chance = 1.0, rarity = "legendary"},
            {item = "legendary_weapon_crate", chance = 1.0, rarity = "legendary"},
            {item = "heavy_ammo", chance = 1.0, count = {100, 200}},
        },
    },
}

--=============================================================================
-- DRAGON RAID SYSTEM
-- Handles periodic dragon flyovers that attack players
--=============================================================================

local DRAGON_RAID_INTERVAL = 300   -- 5 minutes between dragon raids
local activeDragon = nil           -- Currently active dragon
local dragonRaidTimer = nil        -- Timer for next raid
local isDragonRaidActive = false   -- Is a raid in progress

--=============================================================================
-- PRIVATE STATE
--=============================================================================

local isSpawning = false           -- Is spawn loop active
local activeDinosaurs = {}         -- All active dinosaurs {[dinoId] = dinoData}
local activePacks = {}             -- Pack groupings {[packId] = {leader, members}}
local activeBosses = {}            -- Boss fights in progress
local spawnPoints = {}             -- Available spawn positions
local framework = nil              -- Framework reference
local gameConfig = nil             -- Game configuration
local mapService = nil             -- MapService reference
local networkUtils = nil           -- Network utilities for distance filtering

--[[
    Safe logging helper - handles cases where framework may not be initialized yet
    @param level string - Log level (Debug, Info, Warn, Error)
    @param message string - Format string
    @param ... any - Format arguments
]]
local function safeLog(level, message, ...)
    if framework and framework.Log then
        framework.Log(level, message, ...)
    else
        -- Fallback to print when framework not available (e.g., during tests)
        local formatted = string.format(message, ...)
        print(string.format("[DinoService][%s] %s", level, formatted))
    end
end

--=============================================================================
-- INITIALIZATION
--=============================================================================

--[[
    Initialize the DinoService
    Sets up remotes, loads spawn points, and prepares the system

    @return boolean - Success status
]]
function DinoService:Initialize()
    -- Get framework and config references
    -- Rojo maps to ReplicatedStorage.Framework and ReplicatedStorage.Shared
    framework = require(script.Parent.Parent.Framework)
    gameConfig = require(script.Parent.Parent.Shared.GameConfig)

    -- Load network utilities for distance-based broadcasting
    networkUtils = require(script.Parent.Parent.Shared.lib.NetworkUtils)

    -- Try to get MapService for spawn points
    mapService = framework:GetService("MapService")

    -- Load spawn points from map or MapService
    self:LoadSpawnPoints()

    -- Setup network remotes
    self:SetupRemotes()

    safeLog("Info", "DinoService initialized with %d spawn points", #spawnPoints)
    return true
end

--[[
    Setup remote events for client-server communication
    Creates all necessary RemoteEvents for dinosaur-related networking
]]
function DinoService:SetupRemotes()
    -- Find or create Remotes folder
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = "Remotes"
        remoteFolder.Parent = ReplicatedStorage
    end

    -- Define all dinosaur-related remotes
    local dinoRemotes = {
        "DinoSpawned",          -- Notify clients of new dinosaur
        "DinoDamaged",          -- Dinosaur took damage
        "DinoDied",             -- Dinosaur was killed
        "DinoAttack",           -- Dinosaur performed attack
        "DinoAbility",          -- Dinosaur used special ability
        "DinoStateChanged",     -- Dinosaur state change (for animations)
        "BossSpawned",          -- Boss dinosaur appeared
        "BossPhaseChanged",     -- Boss entered new phase
        "BossDied",             -- Boss was defeated
        "PackAlert",            -- Pack communication event
    }

    -- Create any missing remotes
    for _, remoteName in ipairs(dinoRemotes) do
        if not remoteFolder:FindFirstChild(remoteName) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = remoteName
            remote.Parent = remoteFolder
        end
    end
end

--[[
    Load spawn points from map geometry or MapService
    Falls back to generated points if none found
]]
function DinoService:LoadSpawnPoints()
    spawnPoints = {}

    -- First try to get spawn points from MapService
    if mapService and mapService.GetDinoSpawnPoints then
        local mapSpawns = mapService:GetDinoSpawnPoints()
        if mapSpawns and #mapSpawns > 0 then
            spawnPoints = mapSpawns
            safeLog("Info", "Loaded %d spawn points from MapService", #spawnPoints)
            return
        end
    end

    -- Look for spawn point folder in workspace
    local spawnFolder = workspace:FindFirstChild("DinoSpawnPoints")
    if spawnFolder then
        for _, point in ipairs(spawnFolder:GetChildren()) do
            if point:IsA("BasePart") then
                table.insert(spawnPoints, point.Position)
            end
        end
    end

    -- If still no spawn points, generate defaults in a ring
    if #spawnPoints == 0 then
        local radius = 300
        for i = 1, 16 do
            local angle = (i / 16) * math.pi * 2
            local x = math.cos(angle) * radius
            local z = math.sin(angle) * radius
            -- Get terrain height for fallback spawn point
            local terrainY = self:GetTerrainHeight(Vector3.new(x, 0, z))
            table.insert(spawnPoints, Vector3.new(x, terrainY, z))
        end
        safeLog("Warn", "No spawn points found, generated %d defaults", #spawnPoints)
    end
end

--=============================================================================
-- SPAWNING SYSTEM
--=============================================================================

--[[
    Start the dinosaur spawning system
    Begins spawn waves and AI update loops
]]
function DinoService:StartSpawning()
    if isSpawning then
        safeLog("Warn", "DinoService already spawning")
        return
    end

    isSpawning = true
    safeLog("Info", "Starting dinosaur spawning")

    -- Setup player tracking for spatial grid
    self:SetupPlayerTracking()

    -- Initial spawn wave
    self:SpawnWave()

    -- Start spawn loop (periodic waves)
    task.spawn(function()
        while isSpawning do
            task.wait(gameConfig.Dinosaurs.spawnInterval)
            if isSpawning then
                self:SpawnWave()
            end
        end
    end)

    -- Start AI update loop
    task.spawn(function()
        while isSpawning do
            -- Update player positions in spatial grid
            self:UpdatePlayerGrid()
            -- Then update AI
            self:UpdateAllAI()
            task.wait(AI_UPDATE_RATE)
        end
    end)

    -- Start dragon raid system (dragon appears every 5 minutes)
    self:StartDragonRaids()
end

--[[
    Setup player tracking for spatial grid optimization
]]
function DinoService:SetupPlayerTracking()
    -- Clear existing grid
    spatialGrid = {}
    playerCells = {}

    -- Add existing players
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                updatePlayerInGrid(player, rootPart.Position)
            end
        end
    end

    -- Track when players leave
    Players.PlayerRemoving:Connect(function(player)
        removePlayerFromGrid(player)
    end)

    safeLog("Debug", "Spatial grid initialized with %d players", #Players:GetPlayers())
end

--[[
    Update all player positions in the spatial grid
    Called each AI tick for efficient target finding
]]
function DinoService:UpdatePlayerGrid()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                updatePlayerInGrid(player, rootPart.Position)
            end
        end
    end
end

--[[
    Stop the dinosaur spawning system
]]
function DinoService:StopSpawning()
    isSpawning = false
    self:StopDragonRaids()
    safeLog("Info", "Stopped dinosaur spawning")
end

--=============================================================================
-- DRAGON RAID SYSTEM FUNCTIONS
--=============================================================================

--[[
    Start the dragon raid timer
    Dragon will appear every 5 minutes and fly across the map
]]
function DinoService:StartDragonRaids()
    if dragonRaidTimer then return end  -- Already running

    safeLog("Info", "Dragon raid system started - raids every %d seconds", DRAGON_RAID_INTERVAL)

    -- Start the raid timer loop
    task.spawn(function()
        while isSpawning do
            task.wait(DRAGON_RAID_INTERVAL)
            if isSpawning and not isDragonRaidActive then
                self:StartDragonRaid()
            end
        end
    end)

    dragonRaidTimer = true
end

--[[
    Stop the dragon raid timer
]]
function DinoService:StopDragonRaids()
    dragonRaidTimer = nil
    if activeDragon then
        self:EndDragonRaid()
    end
end

--[[
    Start a dragon raid
    Spawns a dragon that flies across the map attacking players
]]
function DinoService:StartDragonRaid()
    if isDragonRaidActive then return end

    isDragonRaidActive = true
    safeLog("Info", "DRAGON RAID STARTING!")

    -- Get map bounds for flight path
    local mapCenter = Vector3.new(0, 0, 0)
    local mapRadius = 500

    if mapService then
        local center = mapService:GetMapCenter()
        local size = mapService:GetMapSize()
        if center then mapCenter = center end
        if size then mapRadius = math.max(size.X, size.Z) / 2 end
    end

    -- Calculate entry and exit points (random direction across map)
    local entryAngle = math.random() * math.pi * 2
    local exitAngle = entryAngle + math.pi  -- Opposite side

    local dragonDef = BOSS_DEFINITIONS.dragon
    local flyHeight = dragonDef.flyHeight or 80

    local entryPoint = mapCenter + Vector3.new(
        math.cos(entryAngle) * (mapRadius + 100),
        flyHeight,
        math.sin(entryAngle) * (mapRadius + 100)
    )

    local exitPoint = mapCenter + Vector3.new(
        math.cos(exitAngle) * (mapRadius + 100),
        flyHeight,
        math.sin(exitAngle) * (mapRadius + 100)
    )

    -- Spawn the dragon
    activeDragon = self:SpawnDragon(entryPoint)

    if not activeDragon then
        isDragonRaidActive = false
        return
    end

    -- Play approach warning sound to all players
    self:PlayDragonSound("approach", mapCenter, 1000)

    -- Broadcast dragon warning to all clients
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes and remotes:FindFirstChild("BossSpawned") then
        remotes.BossSpawned:FireAllClients({
            id = activeDragon.id,
            type = "dragon",
            name = dragonDef.name,
            position = entryPoint,
            health = activeDragon.health,
            maxHealth = activeDragon.maxHealth,
            phase = 1,
            isDragon = true,
        })
    end

    -- Start the dragon's flight path
    self:DragonFlyPath(activeDragon, entryPoint, exitPoint, dragonDef)
end

--[[
    Spawn a dragon entity

    @param position Vector3 - Spawn position
    @return table - Dragon data
]]
function DinoService:SpawnDragon(position)
    local dragonDef = BOSS_DEFINITIONS.dragon
    local baseDef = DINOSAUR_DEFINITIONS.pteranodon

    -- Generate unique ID
    local dragonId = game:GetService("HttpService"):GenerateGUID(false)

    -- Calculate stats
    local health = (baseDef.health or 100) * (dragonDef.healthMultiplier or 5)
    local damage = (baseDef.damage or 15) * (dragonDef.damageMultiplier or 3)
    local speed = dragonDef.flySpeed or 100

    -- Create dragon data
    local dragon = {
        id = dragonId,
        type = "dragon",
        name = dragonDef.name,
        isBoss = true,
        isDragon = true,

        health = health,
        maxHealth = health,
        damage = damage,
        speed = speed,

        position = position,
        state = "flying",
        stateTime = 0,  -- Required for AI update loop

        target = nil,
        threatTable = {},
        lastAttackTime = 0,
        abilityCooldowns = {},

        config = baseDef,
        bossConfig = dragonDef,
        model = nil,
    }

    -- Create dragon model
    dragon.model = self:CreateDragonModel(dragon, position)

    -- Store in active lists
    activeDinosaurs[dragonId] = dragon
    activeBosses[dragonId] = {
        id = dragonId,
        type = "dragon",
        phase = 1,
        spawnTime = tick(),
    }

    safeLog("Info", "Dragon spawned at %s", tostring(position))
    return dragon
end

--[[
    Create a visual model for the dragon

    @param dragon table - Dragon data
    @param position Vector3 - Spawn position
    @return Model - Dragon model
]]
function DinoService:CreateDragonModel(dragon, position)
    local dragonDef = BOSS_DEFINITIONS.dragon

    -- Create a large, scary dragon model
    local model = Instance.new("Model")
    model.Name = "Dragon_SkyTerror"

    -- Dragon body (large, elongated)
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(20, 8, 40)  -- Large body
    body.Color = dragonDef.color or Color3.fromRGB(20, 20, 20)
    body.Material = Enum.Material.SmoothPlastic
    body.CanCollide = false  -- Flying, no collision needed
    body.Anchored = true
    body.CFrame = CFrame.new(position)
    body.Parent = model

    -- Dragon head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(8, 6, 12)
    head.Color = dragonDef.color or Color3.fromRGB(20, 20, 20)
    head.Material = Enum.Material.SmoothPlastic
    head.CanCollide = false
    head.Anchored = true
    head.CFrame = CFrame.new(position + Vector3.new(0, 2, 22))
    head.Parent = model

    -- Dragon wings (large)
    local leftWing = Instance.new("Part")
    leftWing.Name = "LeftWing"
    leftWing.Size = Vector3.new(30, 2, 20)
    leftWing.Color = Color3.fromRGB(40, 40, 40)
    leftWing.Material = Enum.Material.SmoothPlastic
    leftWing.CanCollide = false
    leftWing.Anchored = true
    leftWing.CFrame = CFrame.new(position + Vector3.new(-20, 2, 0)) * CFrame.Angles(0, 0, math.rad(-15))
    leftWing.Parent = model

    local rightWing = Instance.new("Part")
    rightWing.Name = "RightWing"
    rightWing.Size = Vector3.new(30, 2, 20)
    rightWing.Color = Color3.fromRGB(40, 40, 40)
    rightWing.Material = Enum.Material.SmoothPlastic
    rightWing.CanCollide = false
    rightWing.Anchored = true
    rightWing.CFrame = CFrame.new(position + Vector3.new(20, 2, 0)) * CFrame.Angles(0, 0, math.rad(15))
    rightWing.Parent = model

    -- Dragon tail
    local tail = Instance.new("Part")
    tail.Name = "Tail"
    tail.Size = Vector3.new(4, 4, 25)
    tail.Color = dragonDef.color or Color3.fromRGB(20, 20, 20)
    tail.Material = Enum.Material.SmoothPlastic
    tail.CanCollide = false
    tail.Anchored = true
    tail.CFrame = CFrame.new(position + Vector3.new(0, 0, -30))
    tail.Parent = model

    -- Add fiery glow effect
    if dragonDef.glowEnabled then
        local glow = Instance.new("PointLight")
        glow.Name = "DragonGlow"
        glow.Color = dragonDef.glowColor or Color3.fromRGB(255, 100, 0)
        glow.Brightness = 3
        glow.Range = 40
        glow.Parent = body

        -- Fire particles on body
        local fire = Instance.new("Fire")
        fire.Name = "DragonFire"
        fire.Heat = 5
        fire.Size = 10
        fire.Color = Color3.fromRGB(255, 100, 0)
        fire.SecondaryColor = Color3.fromRGB(255, 50, 0)
        fire.Parent = body
    end

    -- Humanoid for health tracking
    local humanoid = Instance.new("Humanoid")
    humanoid.MaxHealth = dragon.maxHealth
    humanoid.Health = dragon.health
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
    humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
    humanoid.Parent = model

    model.PrimaryPart = body

    -- Place in Dinosaurs folder
    local dinoFolder = workspace:FindFirstChild("Dinosaurs")
    if not dinoFolder then
        dinoFolder = Instance.new("Folder")
        dinoFolder.Name = "Dinosaurs"
        dinoFolder.Parent = workspace
    end
    model.Parent = dinoFolder

    return model
end

--[[
    Control the dragon's flight path across the map
    Dragon flies from entry to exit, attacking players along the way

    @param dragon table - Dragon data
    @param startPos Vector3 - Starting position
    @param endPos Vector3 - Target exit position
    @param dragonDef table - Dragon definition
]]
function DinoService:DragonFlyPath(dragon, startPos, endPos, dragonDef)
    if not dragon or not dragon.model then return end

    local flySpeed = dragonDef.flySpeed or 100
    local attackInterval = dragonDef.attackInterval or 8
    local raidDuration = dragonDef.raidDuration or 60

    local raidStartTime = tick()
    local lastAttackTime = tick()
    local flightDirection = (endPos - startPos).Unit
    local currentPos = startPos

    -- Wing flap sound loop
    task.spawn(function()
        while isDragonRaidActive and dragon.model and dragon.model.Parent do
            self:PlayDragonSound("wingFlap", dragon.position, 200)
            task.wait(1.5)
        end
    end)

    -- Main flight loop
    task.spawn(function()
        while isDragonRaidActive and dragon.model and dragon.model.Parent do
            local now = tick()
            local elapsed = now - raidStartTime

            -- Check if raid should end
            if elapsed > raidDuration or dragon.health <= 0 then
                self:EndDragonRaid()
                return
            end

            -- Move dragon forward
            local moveDistance = flySpeed * AI_UPDATE_RATE
            currentPos = currentPos + flightDirection * moveDistance
            dragon.position = currentPos

            -- Update model position with smooth flight
            if dragon.model and dragon.model.PrimaryPart then
                -- Add slight up/down bobbing for natural flight
                local bobOffset = math.sin(elapsed * 2) * 3
                local targetCFrame = CFrame.new(currentPos + Vector3.new(0, bobOffset, 0))
                    * CFrame.Angles(0, math.atan2(-flightDirection.X, -flightDirection.Z), 0)

                -- Move all parts together
                pcall(function()
                    dragon.model:SetPrimaryPartCFrame(targetCFrame)
                end)
            end

            -- Attack players periodically
            if now - lastAttackTime > attackInterval then
                lastAttackTime = now
                self:DragonAttackNearestPlayer(dragon)
            end

            -- Check if dragon has exited the map
            local distanceFromStart = (currentPos - startPos).Magnitude
            local totalDistance = (endPos - startPos).Magnitude
            if distanceFromStart > totalDistance then
                safeLog("Info", "Dragon has crossed the map")
                self:EndDragonRaid()
                return
            end

            task.wait(AI_UPDATE_RATE)
        end
    end)
end

--[[
    Make the dragon attack the nearest player

    @param dragon table - Dragon data
]]
function DinoService:DragonAttackNearestPlayer(dragon)
    if not dragon or not dragon.model then return end

    -- Find nearest player
    local nearestPlayer = nil
    local nearestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                local distance = (rootPart.Position - dragon.position).Magnitude
                if distance < nearestDistance and distance < 150 then  -- Attack range
                    nearestDistance = distance
                    nearestPlayer = player
                end
            end
        end
    end

    if not nearestPlayer then return end

    local character = nearestPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- Play attack roar
    self:PlayDragonSound("roar", dragon.position, 500)

    -- Determine attack type based on distance
    local dragonDef = BOSS_DEFINITIONS.dragon
    if nearestDistance < 50 then
        -- Close range - fire breath
        self:DragonFireBreath(dragon, rootPart.Position)
    else
        -- Medium range - dive attack
        self:DragonDiveAttack(dragon, nearestPlayer, rootPart.Position)
    end
end

--[[
    Dragon fire breath attack
    Creates a cone of fire damage

    @param dragon table - Dragon data
    @param targetPos Vector3 - Target position
]]
function DinoService:DragonFireBreath(dragon, targetPos)
    if not dragon or not dragon.model then return end

    local dragonDef = BOSS_DEFINITIONS.dragon
    local fireAbility = dragonDef.abilities.fire_breath

    -- Play fire sound
    self:PlayDragonSound("fireBreath", dragon.position, 300)

    -- Create visual fire effect
    local fireStart = dragon.position
    local direction = (targetPos - fireStart).Unit

    -- Spawn fire particles along the breath path
    for i = 1, 5 do
        local firePos = fireStart + direction * (i * 10)

        local firePart = Instance.new("Part")
        firePart.Name = "DragonFire"
        firePart.Size = Vector3.new(8, 8, 8)
        firePart.Position = firePos
        firePart.Anchored = true
        firePart.CanCollide = false
        firePart.Transparency = 0.5
        firePart.Color = Color3.fromRGB(255, 100, 0)
        firePart.Material = Enum.Material.Neon

        local fire = Instance.new("Fire")
        fire.Heat = 10
        fire.Size = 15
        fire.Parent = firePart

        firePart.Parent = workspace
        Debris:AddItem(firePart, fireAbility.duration or 2)
    end

    -- Damage players in the fire area
    local damage = fireAbility.damage or 50
    local radius = fireAbility.radius or 20

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChild("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if humanoid and rootPart then
                -- Check if player is in fire cone
                local playerDir = (rootPart.Position - fireStart).Unit
                local dotProduct = direction:Dot(playerDir)
                local distanceToFire = (rootPart.Position - fireStart).Magnitude

                if dotProduct > 0.5 and distanceToFire < 60 then
                    humanoid:TakeDamage(damage)

                    -- Notify client of damage
                    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                    if remotes and remotes:FindFirstChild("DamageDealt") then
                        remotes.DamageDealt:FireClient(player, {
                            damage = damage,
                            source = "Dragon Fire",
                        })
                    end
                end
            end
        end
    end

    safeLog("Debug", "Dragon used fire breath")
end

--[[
    Dragon dive attack
    Dragon swoops down to attack a player

    @param dragon table - Dragon data
    @param targetPlayer Player - Target player
    @param targetPos Vector3 - Target position
]]
function DinoService:DragonDiveAttack(dragon, targetPlayer, targetPos)
    if not dragon or not dragon.model then return end

    local dragonDef = BOSS_DEFINITIONS.dragon
    local diveAbility = dragonDef.abilities.dive_attack

    -- Play attack screech
    self:PlayDragonSound("attack", dragon.position, 400)

    -- Animate the dive (quick swoop down)
    local originalHeight = dragon.position.Y
    local diveTarget = Vector3.new(targetPos.X, targetPos.Y + 10, targetPos.Z)

    task.spawn(function()
        -- Dive down
        local diveSteps = 10
        for i = 1, diveSteps do
            if not dragon.model or not dragon.model.Parent then return end

            local progress = i / diveSteps
            local divePos = dragon.position:Lerp(diveTarget, progress)

            pcall(function()
                dragon.model:SetPrimaryPartCFrame(CFrame.new(divePos))
            end)

            task.wait(0.05)
        end

        -- Deal damage at dive target
        local damage = diveAbility.damage or 80
        local knockback = diveAbility.knockback or 50

        local character = targetPlayer.Character
        if character then
            local humanoid = character:FindFirstChild("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")

            if humanoid and rootPart then
                local distance = (rootPart.Position - diveTarget).Magnitude
                if distance < 25 then  -- Hit radius
                    humanoid:TakeDamage(damage)

                    -- Apply knockback
                    local knockbackDir = (rootPart.Position - diveTarget).Unit
                    local bodyVelocity = Instance.new("BodyVelocity")
                    bodyVelocity.Velocity = knockbackDir * knockback + Vector3.new(0, 20, 0)
                    bodyVelocity.MaxForce = Vector3.new(50000, 50000, 50000)
                    bodyVelocity.Parent = rootPart
                    Debris:AddItem(bodyVelocity, 0.3)

                    safeLog("Debug", "Dragon dive hit %s for %d damage", targetPlayer.Name, damage)
                end
            end
        end

        -- Return to flight height
        task.wait(0.5)
        for i = 1, diveSteps do
            if not dragon.model or not dragon.model.Parent then return end

            local progress = i / diveSteps
            local returnPos = diveTarget:Lerp(Vector3.new(diveTarget.X, originalHeight, diveTarget.Z), progress)

            pcall(function()
                dragon.model:SetPrimaryPartCFrame(CFrame.new(returnPos))
            end)

            task.wait(0.05)
        end

        dragon.position = Vector3.new(diveTarget.X, originalHeight, diveTarget.Z)
    end)
end

--[[
    Play a dragon sound effect

    @param soundType string - Type of sound (approach, roar, attack, wingFlap, fireBreath)
    @param position Vector3 - Position to play sound
    @param maxDistance number - Maximum hearing distance
]]
function DinoService:PlayDragonSound(soundType, position, maxDistance)
    local dragonDef = BOSS_DEFINITIONS.dragon
    local soundId = dragonDef.sounds and dragonDef.sounds[soundType]

    if not soundId then return end

    -- Create 3D sound at position
    local soundPart = Instance.new("Part")
    soundPart.Name = "DragonSound_" .. soundType
    soundPart.Size = Vector3.new(1, 1, 1)
    soundPart.Position = position
    soundPart.Anchored = true
    soundPart.CanCollide = false
    soundPart.Transparency = 1
    soundPart.Parent = workspace

    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Volume = 1.0
    sound.RollOffMode = Enum.RollOffMode.Linear
    sound.RollOffMaxDistance = maxDistance or 300
    sound.RollOffMinDistance = 20
    sound.Parent = soundPart
    sound:Play()

    -- Cleanup after sound ends
    sound.Ended:Connect(function()
        soundPart:Destroy()
    end)

    -- Backup cleanup in case sound doesn't fire Ended
    Debris:AddItem(soundPart, 10)
end

--[[
    End the current dragon raid
    Removes the dragon and resets raid state
]]
function DinoService:EndDragonRaid()
    if not isDragonRaidActive then return end

    safeLog("Info", "Dragon raid ending")

    if activeDragon then
        -- Check if dragon was killed or just left
        if activeDragon.health <= 0 then
            -- Dragon was killed - spawn loot
            safeLog("Info", "Dragon was slain!")
            local lootSystem = framework:GetModule("LootSystem")
            if lootSystem and activeDragon.position then
                lootSystem:SpawnBossDropLoot(activeDragon.position, "dragon")
            end
        else
            -- Dragon left - just remove it
            safeLog("Info", "Dragon has departed")
        end

        -- Remove dragon model
        if activeDragon.model and activeDragon.model.Parent then
            activeDragon.model:Destroy()
        end

        -- Clean up from active lists
        if activeDragon.id then
            activeDinosaurs[activeDragon.id] = nil
            activeBosses[activeDragon.id] = nil
        end

        activeDragon = nil
    end

    isDragonRaidActive = false
end

--[[
    Spawn a wave of dinosaurs based on current game state
    Scales spawning based on storm phase and player count
]]
function DinoService:SpawnWave()
    -- Get storm state for spawn scaling
    local stormService = framework:GetService("StormService")
    local stormState = stormService and stormService:GetState() or {phase = 1}
    local scaling = gameConfig.Dinosaurs.spawnScaling[stormState.phase] or 1

    -- Calculate spawn limits
    local currentCount = self:GetActiveCount()
    local maxAllowed = math.floor(gameConfig.Dinosaurs.maxActive * scaling)
    local toSpawn = math.max(0, maxAllowed - currentCount)

    if toSpawn <= 0 then
        return
    end

    safeLog("Debug", "Spawning wave: %d dinosaurs (current: %d, max: %d)",
        toSpawn, currentCount, maxAllowed)

    -- Spawn dinosaurs with pack grouping
    local spawned = 0
    while spawned < toSpawn do
        local dinoType = self:SelectDinoType()
        local def = DINOSAUR_DEFINITIONS[dinoType]

        if def then
            -- Determine pack size
            local packMin = def.packSize.min
            local packMax = math.min(def.packSize.max, toSpawn - spawned)
            local packCount = math.random(packMin, packMax)

            -- Select spawn position
            local spawnPos = self:SelectSpawnPosition(stormState)

            if spawnPos then
                -- Spawn pack
                local pack = self:SpawnPack(dinoType, spawnPos, packCount)
                spawned = spawned + #pack
            else
                break  -- No valid spawn positions
            end
        end
    end
end

--[[
    Select a dinosaur type based on weighted spawn chances

    @return string - Selected dinosaur type name
]]
function DinoService:SelectDinoType()
    -- Calculate total weight
    local totalWeight = 0
    for typeName, def in pairs(DINOSAUR_DEFINITIONS) do
        totalWeight = totalWeight + def.spawnWeight
    end

    -- Roll and select
    local roll = math.random() * totalWeight
    local cumulative = 0

    for typeName, def in pairs(DINOSAUR_DEFINITIONS) do
        cumulative = cumulative + def.spawnWeight
        if roll <= cumulative then
            return typeName
        end
    end

    return "raptor"  -- Fallback
end

--[[
    Select a valid spawn position inside the safe zone

    @param stormState table - Current storm state
    @return Vector3|nil - Spawn position or nil if none valid
]]
function DinoService:SelectSpawnPosition(stormState)
    local validPoints = {}
    local stormService = framework:GetService("StormService")

    -- Filter to points inside safe zone
    for _, point in ipairs(spawnPoints) do
        if stormService and stormService:IsInsideZone(point) then
            table.insert(validPoints, point)
        end
    end

    -- Fall back to all points if none inside zone
    if #validPoints == 0 then
        validPoints = spawnPoints
    end

    if #validPoints == 0 then
        return nil
    end

    -- Return random valid point
    return validPoints[math.random(#validPoints)]
end

--[[
    Spawn a pack of dinosaurs at a location

    @param dinoType string - Type of dinosaur to spawn
    @param position Vector3 - Base spawn position
    @param count number - Number of dinosaurs in pack
    @return table - Array of spawned dinosaur data
]]
function DinoService:SpawnPack(dinoType, position, count)
    local pack = {}
    local packId = game:GetService("HttpService"):GenerateGUID(false)

    -- Create pack data structure
    activePacks[packId] = {
        id = packId,
        type = dinoType,
        leader = nil,
        members = {},
        state = "idle",
    }

    -- Spawn each pack member
    for i = 1, count do
        -- Offset position for pack spread
        local offset = Vector3.new(
            math.random(-10, 10),
            0,
            math.random(-10, 10)
        )
        local spawnPos = position + offset

        -- Spawn the dinosaur
        local dino = self:SpawnDinosaur(dinoType, spawnPos, packId)

        if dino then
            table.insert(pack, dino)
            table.insert(activePacks[packId].members, dino.id)

            -- First spawned is pack leader
            if i == 1 then
                activePacks[packId].leader = dino.id
                dino.isPackLeader = true
            end
        end
    end

    -- Clean up empty packs
    if #pack == 0 then
        activePacks[packId] = nil
    end

    return pack
end

--[[
    Spawn a single dinosaur

    @param dinoType string - Type of dinosaur
    @param position Vector3 - Spawn position
    @param packId string|nil - Optional pack ID
    @return table|nil - Dinosaur data or nil on failure
]]
function DinoService:SpawnDinosaur(dinoType, position, packId)
    local def = DINOSAUR_DEFINITIONS[dinoType]
    if not def then
        safeLog("Error", "Unknown dinosaur type: %s", dinoType)
        return nil
    end

    -- Generate unique ID
    local dinoId = game:GetService("HttpService"):GenerateGUID(false)

    -- Create dinosaur data structure
    local dinosaur = {
        -- Identity
        id = dinoId,
        type = dinoType,
        name = def.name,

        -- Stats
        health = def.health,
        maxHealth = def.health,
        damage = def.damage,
        speed = def.speed,
        armor = def.armor or 0,

        -- Position/Movement
        position = position,
        targetPosition = nil,

        -- State machine
        state = "idle",
        previousState = nil,
        stateTime = 0,

        -- Targeting
        target = nil,
        threatTable = {},  -- {[playerId] = threatLevel}

        -- Combat
        lastAttackTime = 0,
        abilityCooldowns = {},
        isStunned = false,
        stunEndTime = 0,

        -- Pack behavior
        packId = packId,
        isPackLeader = false,

        -- Special states
        isCamouflaged = false,
        isEnraged = false,

        -- References
        model = nil,
        config = def,
    }

    -- Initialize ability cooldowns
    if def.abilities then
        for abilityName, _ in pairs(def.abilities) do
            dinosaur.abilityCooldowns[abilityName] = 0
        end
    end

    -- Create visual model
    dinosaur.model = self:CreateDinosaurModel(dinoType, def, position)

    -- Store in active list
    activeDinosaurs[dinoId] = dinosaur

    -- Play spawn roar sound (for predators)
    if def.behavior ~= "swarm" then
        local audioService = framework:GetService("AudioService")
        if audioService and audioService.PlayDinoSound then
            audioService:PlayDinoSound(dinosaur.model, dinoType, "roar")
        end
    end

    -- Broadcast spawn event to clients
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.DinoSpawned:FireAllClients({
            id = dinoId,
            type = dinoType,
            name = def.name,
            position = position,
            health = def.health,
            maxHealth = def.health,
            packId = packId,
        })
    end

    safeLog("Debug", "Spawned %s at %s", def.name, tostring(position))

    return dinosaur
end

--[[
    Create the visual model for a dinosaur

    @param dinoType string - Type of dinosaur
    @param def table - Dinosaur definition
    @param position Vector3 - Spawn position
    @return Model - The created model
]]
function DinoService:CreateDinosaurModel(dinoType, def, position)
    -- Try to get model from ServerStorage
    local dinoModels = ServerStorage:FindFirstChild("Dinosaurs")
    local modelTemplate = dinoModels and dinoModels:FindFirstChild(dinoType)

    local model
    if modelTemplate then
        model = modelTemplate:Clone()
    else
        -- Create placeholder model
        model = self:CreatePlaceholderModel(dinoType, def)
    end

    -- Setup model
    model.Name = "Dino_" .. dinoType .. "_" .. string.sub(tostring(os.clock()), -4)

    -- Raycast to find proper terrain height
    local terrainHeight = self:GetTerrainHeight(position)
    local bodySize = def.modelSize or Vector3.new(4, 3, 8)
    local spawnHeight = terrainHeight + bodySize.Y * 0.5 + 2  -- Half body height + small offset

    local spawnPosition = Vector3.new(position.X, spawnHeight, position.Z)
    model:SetPrimaryPartCFrame(CFrame.new(spawnPosition))

    safeLog("Debug", "Spawning %s at terrain height %.1f (spawn Y: %.1f)",
        dinoType, terrainHeight, spawnHeight)

    -- Ensure Dinosaurs folder exists
    local dinoFolder = workspace:FindFirstChild("Dinosaurs")
    if not dinoFolder then
        dinoFolder = Instance.new("Folder")
        dinoFolder.Name = "Dinosaurs"
        dinoFolder.Parent = workspace
    end

    model.Parent = dinoFolder

    return model
end

--[[
    Create a placeholder dinosaur model when no asset exists
    Creates a visible, detailed dinosaur shape with proper materials

    @param dinoType string - Type of dinosaur
    @param def table - Dinosaur definition
    @return Model - The placeholder model
]]
function DinoService:CreatePlaceholderModel(dinoType, def)
    local model = Instance.new("Model")
    model.Name = dinoType

    -- Get dimensions and colors from definition
    local bodySize = def.modelSize or Vector3.new(4, 3, 8)
    local primaryColor = def.color or Color3.fromRGB(100, 100, 100)
    local secondaryColor = def.secondaryColor or Color3.fromRGB(
        math.min(255, math.floor(primaryColor.R * 255 * 1.15)),
        math.min(255, math.floor(primaryColor.G * 255 * 1.15)),
        math.min(255, math.floor(primaryColor.B * 255 * 1.15))
    )
    local accentColor = def.accentColor or Color3.fromRGB(
        math.floor(primaryColor.R * 255 * 0.7),
        math.floor(primaryColor.G * 255 * 0.7),
        math.floor(primaryColor.B * 255 * 0.7)
    )

    -- Select material based on dinosaur type for realistic appearance
    local baseMaterial = Enum.Material.SmoothPlastic
    local scaleMaterial = Enum.Material.Slate  -- Rough, scaly look
    local softMaterial = Enum.Material.Fabric

    if def.materialType == "scales" then
        baseMaterial = Enum.Material.Slate
    elseif def.materialType == "rough_scales" then
        baseMaterial = Enum.Material.Cobblestone  -- More textured
    elseif def.materialType == "armored" then
        baseMaterial = Enum.Material.Concrete  -- Heavy armor plates
    elseif def.materialType == "smooth_scales" then
        baseMaterial = Enum.Material.SmoothPlastic
    elseif def.materialType == "membrane" then
        baseMaterial = Enum.Material.Fabric  -- Leathery wings
    end

    --==========================================================================
    -- BODY - Main torso with proper proportions
    --==========================================================================
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Anchored = true
    body.CanCollide = true
    body.Size = bodySize
    body.Color = primaryColor
    body.Material = baseMaterial
    body.Transparency = 0
    body.CastShadow = true
    body.Parent = model
    model.PrimaryPart = body

    -- Add underbelly (lighter colored bottom)
    local belly = Instance.new("Part")
    belly.Name = "Belly"
    belly.Anchored = false
    belly.CanCollide = false
    belly.Size = Vector3.new(bodySize.X * 0.9, bodySize.Y * 0.35, bodySize.Z * 0.85)
    belly.Color = secondaryColor
    belly.Material = softMaterial
    belly.CFrame = body.CFrame * CFrame.new(0, -bodySize.Y * 0.28, 0)
    belly.Parent = model

    local bellyWeld = Instance.new("WeldConstraint")
    bellyWeld.Part0 = body
    bellyWeld.Part1 = belly
    bellyWeld.Parent = model

    -- Add dorsal ridge/spine row on back for texture
    local ridgeCount = math.floor(bodySize.Z / 2)
    for i = 1, ridgeCount do
        local ridge = Instance.new("Part")
        ridge.Name = "Ridge" .. i
        local ridgeHeight = bodySize.Y * 0.08 * (1 + math.sin(i * 0.5) * 0.3)
        ridge.Size = Vector3.new(bodySize.X * 0.15, ridgeHeight, bodySize.Z / ridgeCount * 0.4)
        ridge.Color = accentColor
        ridge.Material = scaleMaterial
        ridge.Anchored = false
        ridge.CanCollide = false
        ridge.CastShadow = true
        local zPos = bodySize.Z * 0.4 - (i - 1) * (bodySize.Z * 0.8 / ridgeCount)
        ridge.CFrame = body.CFrame * CFrame.new(0, bodySize.Y * 0.5, zPos)
        ridge.Parent = model

        local ridgeWeld = Instance.new("WeldConstraint")
        ridgeWeld.Part0 = body
        ridgeWeld.Part1 = ridge
        ridgeWeld.Parent = model
    end

    --==========================================================================
    -- HEAD - Detailed skull with proper features
    --==========================================================================
    local isBipedal = dinoType == "raptor" or dinoType == "trex" or dinoType == "dilophosaurus"
        or dinoType == "carnotaurus" or dinoType == "compy" or dinoType == "spinosaurus"

    -- Head size varies by dinosaur type
    local headScale = 0.6
    if dinoType == "trex" then headScale = 0.8 end  -- T-Rex has massive head
    if dinoType == "raptor" or dinoType == "compy" then headScale = 0.5 end
    if dinoType == "triceratops" then headScale = 0.9 end  -- Large frilled head

    local headSize = bodySize.Y * headScale
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(headSize * 0.8, headSize * 0.7, headSize * 1.1)
    head.Color = primaryColor
    head.Material = baseMaterial
    head.Anchored = false
    head.CanCollide = false
    head.CastShadow = true
    head.Parent = model

    -- Neck connection (raised for bipedal, lower for quadrupedal)
    local neckHeight = isBipedal and bodySize.Y * 0.3 or bodySize.Y * 0.1
    local headOffset = CFrame.new(0, neckHeight, bodySize.Z * 0.5 + headSize * 0.4)
    head.CFrame = body.CFrame * headOffset

    local headWeld = Instance.new("WeldConstraint")
    headWeld.Part0 = body
    headWeld.Part1 = head
    headWeld.Parent = model

    -- Add neck
    local neck = Instance.new("Part")
    neck.Name = "Neck"
    neck.Size = Vector3.new(headSize * 0.5, bodySize.Y * 0.4, headSize * 0.6)
    neck.Color = primaryColor
    neck.Material = baseMaterial
    neck.Anchored = false
    neck.CanCollide = false
    neck.CastShadow = true
    neck.CFrame = body.CFrame * CFrame.new(0, neckHeight * 0.5, bodySize.Z * 0.35)
        * CFrame.Angles(math.rad(-15), 0, 0)
    neck.Parent = model

    local neckWeld = Instance.new("WeldConstraint")
    neckWeld.Part0 = body
    neckWeld.Part1 = neck
    neckWeld.Parent = model

    -- Snout/Jaw with proper dinosaur shape
    local snoutLength = headSize * (dinoType == "trex" and 1.0 or 0.7)
    local snout = Instance.new("Part")
    snout.Name = "Snout"
    snout.Size = Vector3.new(headSize * 0.6, headSize * 0.4, snoutLength)
    snout.Color = primaryColor
    snout.Material = baseMaterial
    snout.Anchored = false
    snout.CanCollide = false
    snout.CastShadow = true
    snout.CFrame = head.CFrame * CFrame.new(0, -headSize * 0.1, headSize * 0.5 + snoutLength * 0.3)
    snout.Parent = model

    local snoutWeld = Instance.new("WeldConstraint")
    snoutWeld.Part0 = head
    snoutWeld.Part1 = snout
    snoutWeld.Parent = model

    -- Lower jaw
    local jaw = Instance.new("Part")
    jaw.Name = "Jaw"
    jaw.Size = Vector3.new(headSize * 0.5, headSize * 0.2, snoutLength * 0.8)
    jaw.Color = accentColor
    jaw.Material = baseMaterial
    jaw.Anchored = false
    jaw.CanCollide = false
    jaw.CastShadow = true
    jaw.CFrame = snout.CFrame * CFrame.new(0, -headSize * 0.25, snoutLength * 0.05)
    jaw.Parent = model

    local jawWeld = Instance.new("WeldConstraint")
    jawWeld.Part0 = snout
    jawWeld.Part1 = jaw
    jawWeld.Parent = model

    -- Eyes (menacing, predator look)
    local eyeSize = headSize * 0.12
    for _, side in ipairs({-1, 1}) do
        -- Eye socket (dark recess)
        local eyeSocket = Instance.new("Part")
        eyeSocket.Name = "EyeSocket" .. (side == -1 and "L" or "R")
        eyeSocket.Size = Vector3.new(eyeSize * 1.3, eyeSize * 1.5, eyeSize * 0.5)
        eyeSocket.Color = Color3.fromRGB(30, 25, 20)
        eyeSocket.Material = Enum.Material.SmoothPlastic
        eyeSocket.Anchored = false
        eyeSocket.CanCollide = false
        eyeSocket.CFrame = head.CFrame * CFrame.new(side * headSize * 0.38, headSize * 0.15, headSize * 0.35)
        eyeSocket.Parent = model

        local socketWeld = Instance.new("WeldConstraint")
        socketWeld.Part0 = head
        socketWeld.Part1 = eyeSocket
        socketWeld.Parent = model

        -- Eyeball
        local eye = Instance.new("Part")
        eye.Name = "Eye" .. (side == -1 and "L" or "R")
        eye.Shape = Enum.PartType.Ball
        eye.Size = Vector3.new(eyeSize, eyeSize, eyeSize)
        eye.Color = Color3.fromRGB(255, 200, 50)  -- Amber/yellow predator eyes
        eye.Material = Enum.Material.Glass
        eye.Reflectance = 0.2
        eye.Anchored = false
        eye.CanCollide = false
        eye.CFrame = eyeSocket.CFrame * CFrame.new(0, 0, eyeSize * 0.3)
        eye.Parent = model

        local eyeWeld = Instance.new("WeldConstraint")
        eyeWeld.Part0 = eyeSocket
        eyeWeld.Part1 = eye
        eyeWeld.Parent = model

        -- Pupil (slit for reptile look)
        local pupil = Instance.new("Part")
        pupil.Name = "Pupil" .. (side == -1 and "L" or "R")
        pupil.Size = Vector3.new(eyeSize * 0.15, eyeSize * 0.7, eyeSize * 0.1)
        pupil.Color = Color3.fromRGB(10, 10, 10)
        pupil.Material = Enum.Material.SmoothPlastic
        pupil.Anchored = false
        pupil.CanCollide = false
        pupil.CFrame = eye.CFrame * CFrame.new(0, 0, eyeSize * 0.4)
        pupil.Parent = model

        local pupilWeld = Instance.new("WeldConstraint")
        pupilWeld.Part0 = eye
        pupilWeld.Part1 = pupil
        pupilWeld.Parent = model
    end

    -- Nostrils
    for _, side in ipairs({-1, 1}) do
        local nostril = Instance.new("Part")
        nostril.Name = "Nostril" .. (side == -1 and "L" or "R")
        nostril.Shape = Enum.PartType.Ball
        nostril.Size = Vector3.new(eyeSize * 0.4, eyeSize * 0.3, eyeSize * 0.3)
        nostril.Color = Color3.fromRGB(20, 15, 10)
        nostril.Material = Enum.Material.SmoothPlastic
        nostril.Anchored = false
        nostril.CanCollide = false
        nostril.CFrame = snout.CFrame * CFrame.new(side * snout.Size.X * 0.25, snout.Size.Y * 0.3, snout.Size.Z * 0.4)
        nostril.Parent = model

        local nostrilWeld = Instance.new("WeldConstraint")
        nostrilWeld.Part0 = snout
        nostrilWeld.Part1 = nostril
        nostrilWeld.Parent = model
    end

    --==========================================================================
    -- TAIL - Multi-segmented for realistic appearance
    --==========================================================================
    local tailSegments = 5
    local prevPart = body
    for i = 1, tailSegments do
        local taperFactor = 1 - (i / (tailSegments + 1))
        local segmentSize = Vector3.new(
            bodySize.X * taperFactor * 0.7,
            bodySize.Y * taperFactor * 0.5,
            bodySize.Z * 0.2
        )
        local tail = Instance.new("Part")
        tail.Name = "Tail" .. i
        tail.Size = segmentSize
        -- Alternate colors slightly for texture
        tail.Color = i % 2 == 0 and accentColor or primaryColor
        tail.Material = baseMaterial
        tail.Anchored = false
        tail.CanCollide = false
        tail.CastShadow = true

        local tailOffset = CFrame.new(0, -bodySize.Y * 0.05 * i, -bodySize.Z * 0.45 - (i - 1) * segmentSize.Z * 1.1)
            * CFrame.Angles(math.rad(-5 * i), 0, 0)  -- Slight upward curve
        tail.CFrame = body.CFrame * tailOffset
        tail.Parent = model

        local tailWeld = Instance.new("WeldConstraint")
        tailWeld.Part0 = prevPart
        tailWeld.Part1 = tail
        tailWeld.Parent = model
        prevPart = tail
    end

    --==========================================================================
    -- LEGS - Proper dinosaur leg anatomy
    --==========================================================================
    local legPositions
    if isBipedal then
        -- Two strong back legs for bipedal dinosaurs
        legPositions = {{-0.35, -0.45, -0.1}, {0.35, -0.45, -0.1}}
    else
        -- Four legs for quadrupeds
        legPositions = {
            {-0.4, -0.45, 0.35}, {0.4, -0.45, 0.35},   -- Front legs
            {-0.4, -0.45, -0.25}, {0.4, -0.45, -0.25}  -- Back legs
        }
    end

    for i, pos in ipairs(legPositions) do
        -- Upper leg (thigh)
        local thighHeight = bodySize.Y * (isBipedal and 0.7 or 0.5)
        local thigh = Instance.new("Part")
        thigh.Name = "Thigh" .. i
        thigh.Size = Vector3.new(bodySize.X * 0.25, thighHeight, bodySize.Z * 0.12)
        thigh.Color = primaryColor
        thigh.Material = baseMaterial
        thigh.Anchored = false
        thigh.CanCollide = false
        thigh.CastShadow = true
        thigh.CFrame = body.CFrame * CFrame.new(
            pos[1] * bodySize.X,
            pos[2] * bodySize.Y - thighHeight * 0.3,
            pos[3] * bodySize.Z
        ) * CFrame.Angles(math.rad(15), 0, 0)  -- Angled for natural stance
        thigh.Parent = model

        local thighWeld = Instance.new("WeldConstraint")
        thighWeld.Part0 = body
        thighWeld.Part1 = thigh
        thighWeld.Parent = model

        -- Lower leg (shin)
        local shinHeight = thighHeight * 0.85
        local shin = Instance.new("Part")
        shin.Name = "Shin" .. i
        shin.Size = Vector3.new(bodySize.X * 0.18, shinHeight, bodySize.Z * 0.1)
        shin.Color = accentColor
        shin.Material = baseMaterial
        shin.Anchored = false
        shin.CanCollide = false
        shin.CastShadow = true
        shin.CFrame = thigh.CFrame * CFrame.new(0, -thighHeight * 0.7, 0)
            * CFrame.Angles(math.rad(-30), 0, 0)  -- Bent at knee
        shin.Parent = model

        local shinWeld = Instance.new("WeldConstraint")
        shinWeld.Part0 = thigh
        shinWeld.Part1 = shin
        shinWeld.Parent = model

        -- Foot with claws
        local foot = Instance.new("Part")
        foot.Name = "Foot" .. i
        foot.Size = Vector3.new(bodySize.X * 0.3, bodySize.Y * 0.1, bodySize.Z * 0.18)
        foot.Color = accentColor
        foot.Material = baseMaterial
        foot.Anchored = false
        foot.CanCollide = false
        foot.CastShadow = true
        foot.CFrame = shin.CFrame * CFrame.new(0, -shinHeight * 0.5, bodySize.Z * 0.08)
        foot.Parent = model

        local footWeld = Instance.new("WeldConstraint")
        footWeld.Part0 = shin
        footWeld.Part1 = foot
        footWeld.Parent = model

        -- Add claws (3 per foot)
        for c = 1, 3 do
            local claw = Instance.new("Part")
            claw.Name = "Claw" .. i .. "_" .. c
            claw.Size = Vector3.new(foot.Size.X * 0.15, foot.Size.Y * 0.8, foot.Size.Z * 0.5)
            claw.Color = Color3.fromRGB(50, 45, 40)  -- Dark claw color
            claw.Material = Enum.Material.SmoothPlastic
            claw.Anchored = false
            claw.CanCollide = false
            claw.CastShadow = true
            local clawOffset = (c - 2) * foot.Size.X * 0.35
            claw.CFrame = foot.CFrame * CFrame.new(clawOffset, -foot.Size.Y * 0.3, foot.Size.Z * 0.4)
                * CFrame.Angles(math.rad(30), 0, 0)
            claw.Parent = model

            local clawWeld = Instance.new("WeldConstraint")
            clawWeld.Part0 = foot
            clawWeld.Part1 = claw
            clawWeld.Parent = model
        end
    end

    -- Small arms for bipedal dinosaurs (T-Rex style)
    if isBipedal and (dinoType == "trex" or dinoType == "carnotaurus") then
        for _, side in ipairs({-1, 1}) do
            local arm = Instance.new("Part")
            arm.Name = "Arm" .. (side == -1 and "L" or "R")
            arm.Size = Vector3.new(bodySize.X * 0.12, bodySize.Y * 0.25, bodySize.Z * 0.08)
            arm.Color = primaryColor
            arm.Material = baseMaterial
            arm.Anchored = false
            arm.CanCollide = false
            arm.CastShadow = true
            arm.CFrame = body.CFrame * CFrame.new(
                side * bodySize.X * 0.45,
                bodySize.Y * 0.1,
                bodySize.Z * 0.3
            ) * CFrame.Angles(math.rad(45), 0, side * math.rad(20))
            arm.Parent = model

            local armWeld = Instance.new("WeldConstraint")
            armWeld.Part0 = body
            armWeld.Part1 = arm
            armWeld.Parent = model
        end
    end

    --==========================================================================
    -- DINOSAUR-SPECIFIC FEATURES
    --==========================================================================

    -- Spinosaurus sail
    if dinoType == "spinosaurus" then
        local sailColor = def.sailColor or Color3.fromRGB(140, 60, 45)
        local sailSegments = 8
        for i = 1, sailSegments do
            local sailHeight = bodySize.Y * 0.9 * math.sin(math.pi * i / (sailSegments + 1))
            local sail = Instance.new("Part")
            sail.Name = "Sail" .. i
            sail.Size = Vector3.new(bodySize.X * 0.08, sailHeight, bodySize.Z * 0.08)
            sail.Color = sailColor
            sail.Material = Enum.Material.Fabric  -- Thin membrane
            sail.Transparency = 0.1
            sail.Anchored = false
            sail.CanCollide = false
            sail.CastShadow = true
            local zPos = bodySize.Z * 0.35 - (i - 1) * (bodySize.Z * 0.7 / sailSegments)
            sail.CFrame = body.CFrame * CFrame.new(0, bodySize.Y * 0.5 + sailHeight * 0.5, zPos)
            sail.Parent = model

            local sailWeld = Instance.new("WeldConstraint")
            sailWeld.Part0 = body
            sailWeld.Part1 = sail
            sailWeld.Parent = model
        end
    end

    -- Triceratops frill and horns
    if dinoType == "triceratops" then
        local hornColor = def.hornColor or Color3.fromRGB(245, 235, 210)
        local frillColor = def.accentColor or accentColor

        -- Frill (shield behind head)
        local frill = Instance.new("Part")
        frill.Name = "Frill"
        frill.Size = Vector3.new(headSize * 1.8, headSize * 1.4, headSize * 0.15)
        frill.Color = frillColor
        frill.Material = Enum.Material.Concrete
        frill.Anchored = false
        frill.CanCollide = false
        frill.CastShadow = true
        frill.CFrame = head.CFrame * CFrame.new(0, headSize * 0.5, -headSize * 0.3)
            * CFrame.Angles(math.rad(-20), 0, 0)
        frill.Parent = model

        local frillWeld = Instance.new("WeldConstraint")
        frillWeld.Part0 = head
        frillWeld.Part1 = frill
        frillWeld.Parent = model

        -- Brow horns (two long horns)
        for _, side in ipairs({-1, 1}) do
            local horn = Instance.new("Part")
            horn.Name = "BrowHorn" .. (side == -1 and "L" or "R")
            horn.Size = Vector3.new(headSize * 0.12, headSize * 0.9, headSize * 0.12)
            horn.Color = hornColor
            horn.Material = Enum.Material.SmoothPlastic
            horn.Anchored = false
            horn.CanCollide = false
            horn.CastShadow = true
            horn.CFrame = head.CFrame * CFrame.new(side * headSize * 0.35, headSize * 0.4, headSize * 0.3)
                * CFrame.Angles(math.rad(-45), 0, side * math.rad(10))
            horn.Parent = model

            local hornWeld = Instance.new("WeldConstraint")
            hornWeld.Part0 = head
            hornWeld.Part1 = horn
            hornWeld.Parent = model
        end

        -- Nose horn (shorter)
        local noseHorn = Instance.new("Part")
        noseHorn.Name = "NoseHorn"
        noseHorn.Size = Vector3.new(headSize * 0.15, headSize * 0.4, headSize * 0.15)
        noseHorn.Color = hornColor
        noseHorn.Material = Enum.Material.SmoothPlastic
        noseHorn.Anchored = false
        noseHorn.CanCollide = false
        noseHorn.CastShadow = true
        noseHorn.CFrame = snout.CFrame * CFrame.new(0, snout.Size.Y * 0.4, snout.Size.Z * 0.2)
            * CFrame.Angles(math.rad(-30), 0, 0)
        noseHorn.Parent = model

        local noseHornWeld = Instance.new("WeldConstraint")
        noseHornWeld.Part0 = snout
        noseHornWeld.Part1 = noseHorn
        noseHornWeld.Parent = model
    end

    -- Dilophosaurus crests
    if dinoType == "dilophosaurus" then
        local crestColor = def.accentColor or Color3.fromRGB(180, 80, 50)
        for _, side in ipairs({-1, 1}) do
            local crest = Instance.new("Part")
            crest.Name = "Crest" .. (side == -1 and "L" or "R")
            crest.Size = Vector3.new(headSize * 0.1, headSize * 0.5, headSize * 0.6)
            crest.Color = crestColor
            crest.Material = Enum.Material.Fabric
            crest.Anchored = false
            crest.CanCollide = false
            crest.CastShadow = true
            crest.CFrame = head.CFrame * CFrame.new(side * headSize * 0.25, headSize * 0.5, headSize * 0.1)
            crest.Parent = model

            local crestWeld = Instance.new("WeldConstraint")
            crestWeld.Part0 = head
            crestWeld.Part1 = crest
            crestWeld.Parent = model
        end
    end

    -- Carnotaurus horns
    if dinoType == "carnotaurus" then
        local hornColor = def.hornColor or Color3.fromRGB(60, 50, 45)
        for _, side in ipairs({-1, 1}) do
            local horn = Instance.new("Part")
            horn.Name = "EyeHorn" .. (side == -1 and "L" or "R")
            horn.Size = Vector3.new(headSize * 0.15, headSize * 0.35, headSize * 0.15)
            horn.Color = hornColor
            horn.Material = Enum.Material.SmoothPlastic
            horn.Anchored = false
            horn.CanCollide = false
            horn.CastShadow = true
            horn.CFrame = head.CFrame * CFrame.new(side * headSize * 0.35, headSize * 0.35, headSize * 0.15)
                * CFrame.Angles(0, 0, side * math.rad(20))
            horn.Parent = model

            local hornWeld = Instance.new("WeldConstraint")
            hornWeld.Part0 = head
            hornWeld.Part1 = horn
            hornWeld.Parent = model
        end
    end

    -- Pteranodon wings
    if dinoType == "pteranodon" then
        local wingColor = def.secondaryColor or secondaryColor
        for _, side in ipairs({-1, 1}) do
            local wing = Instance.new("Part")
            wing.Name = "Wing" .. (side == -1 and "L" or "R")
            wing.Size = Vector3.new(bodySize.X * 2.5, bodySize.Y * 0.15, bodySize.Z * 1.2)
            wing.Color = wingColor
            wing.Material = Enum.Material.Fabric
            wing.Transparency = 0.1
            wing.Anchored = false
            wing.CanCollide = false
            wing.CastShadow = true
            wing.CFrame = body.CFrame * CFrame.new(side * bodySize.X * 1.5, bodySize.Y * 0.2, 0)
                * CFrame.Angles(0, 0, side * math.rad(-10))
            wing.Parent = model

            local wingWeld = Instance.new("WeldConstraint")
            wingWeld.Part0 = body
            wingWeld.Part1 = wing
            wingWeld.Parent = model
        end

        -- Head crest
        local crest = Instance.new("Part")
        crest.Name = "HeadCrest"
        crest.Size = Vector3.new(headSize * 0.1, headSize * 0.4, headSize * 0.8)
        crest.Color = def.accentColor or accentColor
        crest.Material = Enum.Material.SmoothPlastic
        crest.Anchored = false
        crest.CanCollide = false
        crest.CastShadow = true
        crest.CFrame = head.CFrame * CFrame.new(0, headSize * 0.4, -headSize * 0.2)
            * CFrame.Angles(math.rad(-20), 0, 0)
        crest.Parent = model

        local crestWeld = Instance.new("WeldConstraint")
        crestWeld.Part0 = head
        crestWeld.Part1 = crest
        crestWeld.Parent = model
    end

    --==========================================================================
    -- UI ELEMENTS - Name and health display
    --==========================================================================

    -- Name billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "NameBillboard"
    billboard.Size = UDim2.new(0, 150, 0, 35)
    billboard.StudsOffset = Vector3.new(0, bodySize.Y + 6, 0)
    billboard.Adornee = body
    billboard.AlwaysOnTop = false
    billboard.MaxDistance = 120
    billboard.Parent = body

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 1, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = def.name or dinoType:upper()
    nameLabel.TextColor3 = Color3.new(1, 0.4, 0.3)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextScaled = true
    nameLabel.Parent = billboard

    -- Health bar billboard
    local healthBillboard = Instance.new("BillboardGui")
    healthBillboard.Name = "HealthBillboard"
    healthBillboard.Size = UDim2.new(0, 120, 0, 14)
    healthBillboard.StudsOffset = Vector3.new(0, bodySize.Y + 4, 0)
    healthBillboard.Adornee = body
    healthBillboard.AlwaysOnTop = false
    healthBillboard.MaxDistance = 120
    healthBillboard.Parent = body

    local healthBg = Instance.new("Frame")
    healthBg.Size = UDim2.new(1, 0, 1, 0)
    healthBg.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    healthBg.BorderSizePixel = 0
    healthBg.Parent = healthBillboard

    local healthBgCorner = Instance.new("UICorner")
    healthBgCorner.CornerRadius = UDim.new(0, 4)
    healthBgCorner.Parent = healthBg

    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthBar"
    healthBar.Size = UDim2.new(1, -4, 1, -4)
    healthBar.Position = UDim2.new(0, 2, 0, 2)
    healthBar.BackgroundColor3 = Color3.new(0.3, 0.9, 0.3)
    healthBar.BorderSizePixel = 0
    healthBar.Parent = healthBg

    local healthBarCorner = Instance.new("UICorner")
    healthBarCorner.CornerRadius = UDim.new(0, 3)
    healthBarCorner.Parent = healthBar

    --==========================================================================
    -- HUMANOID - For pathfinding and health tracking
    --==========================================================================

    local humanoid = Instance.new("Humanoid")
    humanoid.MaxHealth = def.health
    humanoid.Health = def.health
    humanoid.WalkSpeed = def.speed
    humanoid.HipHeight = bodySize.Y * 0.4
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    humanoid.Parent = model

    -- Root part for humanoid
    local rootPart = Instance.new("Part")
    rootPart.Name = "HumanoidRootPart"
    rootPart.Transparency = 1
    rootPart.CanCollide = false
    rootPart.Size = Vector3.new(2, 2, 1)
    rootPart.CFrame = body.CFrame
    rootPart.Anchored = false
    rootPart.Parent = model

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = rootPart
    weld.Part1 = body
    weld.Parent = model

    safeLog("Debug", "Created detailed %s model (size: %s, material: %s)",
        dinoType, tostring(bodySize), def.materialType or "default")

    return model
end

--[[
    Get terrain height at a position using raycast
    @param position Vector3 - XZ position to check
    @return number - Y height of terrain at position
]]
function DinoService:GetTerrainHeight(position)
    local rayOrigin = Vector3.new(position.X, 500, position.Z)
    local rayDirection = Vector3.new(0, -1000, 0)

    -- Build comprehensive exclusion list to find actual terrain, not placed objects
    local excludeList = {}
    local folderNames = {
        "Dinosaurs", "POIs", "Flora", "Decorations", "POIBuildings",
        "GroundLoot", "LobbyPlatform", "Map", "Biomes", "Vegetation",
        "Props", "Hazards", "Events", "ChestSpawnPoints", "DinoSpawnPoints",
        "Chests", "SpawnedLoot", "SupplyDrops"
    }

    for _, name in ipairs(folderNames) do
        local folder = workspace:FindFirstChild(name)
        if folder then
            table.insert(excludeList, folder)
        end
    end

    -- Also exclude all players
    for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
        if player.Character then
            table.insert(excludeList, player.Character)
        end
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = excludeList
    raycastParams.IgnoreWater = true  -- Find solid ground, not water surface

    local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    -- Only accept if we hit actual terrain
    if result and result.Instance:IsA("Terrain") then
        return result.Position.Y
    end

    -- Fallback: Try voxel reading
    -- ReadVoxels returns: materials[x][y][z], occupancies[x][y][z]
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        local success, materials, occupancies = pcall(function()
            local region = Region3.new(
                Vector3.new(position.X - 2, 0, position.Z - 2),
                Vector3.new(position.X + 2, 200, position.Z + 2)
            ):ExpandToGrid(4)
            return terrain:ReadVoxels(region, 4)
        end)

        if success and materials and #materials > 0 then
            local xSize = #materials
            local ySize = #materials[1]
            local zSize = #materials[1][1]
            local midX = math.ceil(xSize / 2)
            local midZ = math.ceil(zSize / 2)

            -- Find highest non-air voxel at center of sample
            for y = ySize, 1, -1 do
                local mat = materials[midX][y][midZ]
                if mat ~= Enum.Material.Air and mat ~= Enum.Material.Water then
                    return (y - 1) * 4  -- Convert voxel index to world Y
                end
            end
        end
    end

    -- Fallback: Calculate terrain height based on noise formula (matches TerrainSetup)
    local MAP_SIZE = 2048
    local x, z = position.X, position.Z
    local distFromCenter = math.sqrt(x * x + z * z)
    local maxDist = MAP_SIZE / 2
    local normalizedDist = math.min(1, distFromCenter / maxDist)
    local edgeFalloff = 1 - (normalizedDist ^ 3)

    local baseNoise = math.noise(x / 200, z / 200, 0)
    local detailNoise = math.noise(x / 50, z / 50, 0) * 0.5
    local combinedNoise = (baseNoise + detailNoise) / 1.5

    local baseHeight = 10
    local heightVariation = 40
    local calculatedHeight = baseHeight + combinedNoise * heightVariation * edgeFalloff

    return math.max(5, calculatedHeight)
end

--=============================================================================
-- AI SYSTEM
-- Core AI logic including state machine, targeting, and behavior execution
--=============================================================================

--[[
    Update AI for all active dinosaurs
    Called on a fixed interval from the main loop
]]
function DinoService:UpdateAllAI()
    local now = tick()

    for dinoId, dino in pairs(activeDinosaurs) do
        if dino.health > 0 then
            -- Update state time
            dino.stateTime = dino.stateTime + AI_UPDATE_RATE

            -- Check for stun expiration
            if dino.isStunned and now >= dino.stunEndTime then
                dino.isStunned = false
                self:SetState(dino, dino.previousState or "idle")
            end

            -- Skip AI if stunned
            if not dino.isStunned then
                self:UpdateDinoAI(dino)
            end
        end
    end

    -- Update pack behaviors
    self:UpdatePackBehaviors()
end

--[[
    Update AI for a single dinosaur

    @param dino table - Dinosaur data
]]
function DinoService:UpdateDinoAI(dino)
    local def = dino.config

    -- State machine execution
    if dino.state == "idle" then
        self:DoIdleBehavior(dino)
    elseif dino.state == "alert" then
        self:DoAlertBehavior(dino)
    elseif dino.state == "hunting" then
        self:DoHuntingBehavior(dino)
    elseif dino.state == "chasing" then
        self:DoChaseBehavior(dino)
    elseif dino.state == "attacking" then
        self:DoAttackBehavior(dino)
    elseif dino.state == "ability" then
        self:DoAbilityBehavior(dino)
    elseif dino.state == "fleeing" then
        self:DoFleeBehavior(dino)
    end

    -- Check for flee conditions
    if def.fleeHealthPercent and def.fleeHealthPercent > 0 then
        local healthPercent = dino.health / dino.maxHealth
        if healthPercent <= def.fleeHealthPercent and dino.state ~= "fleeing" then
            self:SetState(dino, "fleeing")
        end
    end
end

--[[
    Set dinosaur state with proper transition handling

    @param dino table - Dinosaur data
    @param newState string - New state to enter
]]
function DinoService:SetState(dino, newState)
    if dino.state == newState then
        return
    end

    dino.previousState = dino.state
    dino.state = newState
    dino.stateTime = 0

    -- Broadcast state change with distance filtering (animations only matter nearby)
    local dinoPos = self:GetDinoPosition(dino)
    if dinoPos and networkUtils then
        networkUtils.FireNearby("DinoStateChanged", dinoPos, 200, {
            dinoId = dino.id,
            state = newState,
            previousState = dino.previousState,
        })
    else
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes and remotes:FindFirstChild("DinoStateChanged") then
            remotes.DinoStateChanged:FireAllClients({
                dinoId = dino.id,
                state = newState,
                previousState = dino.previousState,
            })
        end
    end
end

--[[
    Idle behavior - wander or rest
    Passive dinosaurs stay in idle, others look for targets

    @param dino table - Dinosaur data
]]
function DinoService:DoIdleBehavior(dino)
    local def = dino.config

    -- Passive dinosaurs only attack when provoked
    if def.isPassive then
        -- Check if we've been attacked recently (threat table not empty)
        local hasThreats = false
        for _ in pairs(dino.threatTable) do
            hasThreats = true
            break
        end

        if hasThreats then
            self:SetState(dino, "alert")
        end
        return
    end

    -- Look for targets periodically
    if dino.stateTime >= 2 then
        local target = self:FindBestTarget(dino)
        if target then
            dino.target = target
            self:SetState(dino, "alert")
        end
        dino.stateTime = 0
    end

    -- Random wandering (simplified)
    if math.random() < 0.02 then
        local humanoid = dino.model and dino.model:FindFirstChild("Humanoid")
        if humanoid then
            local wanderPos = dino.position + Vector3.new(
                math.random(-20, 20),
                0,
                math.random(-20, 20)
            )
            humanoid:MoveTo(wanderPos)
        end
    end
end

--[[
    Alert behavior - detected threat, deciding response

    @param dino table - Dinosaur data
]]
function DinoService:DoAlertBehavior(dino)
    local def = dino.config

    -- Validate target
    if not dino.target or not self:IsValidTarget(dino.target) then
        dino.target = self:FindBestTarget(dino)
        if not dino.target then
            self:SetState(dino, "idle")
            return
        end
    end

    -- Alert pack members
    if dino.packId and dino.isPackLeader then
        self:AlertPack(dino)
    end

    -- Choose approach based on category
    local category = def.category

    if category == "ambush_predator" then
        -- Try to camouflage and wait
        if self:TryAbility(dino, "camouflage") then
            return
        end
    elseif category == "ranged_spitter" then
        -- Check if in range for ranged attack
        local distance = self:GetDistanceToTarget(dino)
        if distance and distance <= def.attackRange then
            self:SetState(dino, "attacking")
            return
        end
    end

    -- Transition to hunting/chasing
    self:SetState(dino, "chasing")
end

--[[
    Hunting behavior - searching for lost target

    @param dino table - Dinosaur data
]]
function DinoService:DoHuntingBehavior(dino)
    -- Try to find a new target
    local target = self:FindBestTarget(dino)
    if target then
        dino.target = target
        self:SetState(dino, "chasing")
        return
    end

    -- No target found after timeout, return to idle
    if dino.stateTime >= 5 then
        self:SetState(dino, "idle")
    end
end

--[[
    Chase behavior - pursuing target

    @param dino table - Dinosaur data
]]
function DinoService:DoChaseBehavior(dino)
    local def = dino.config

    -- Validate target
    if not dino.target or not self:IsValidTarget(dino.target) then
        dino.target = nil
        self:SetState(dino, "hunting")
        return
    end

    local distance = self:GetDistanceToTarget(dino)
    if not distance then
        dino.target = nil
        self:SetState(dino, "hunting")
        return
    end

    -- Check deaggro range
    local deaggroRadius = gameConfig.Dinosaurs.deaggroRadius or 120
    if distance > deaggroRadius then
        dino.target = nil
        self:SetState(dino, "idle")
        return
    end

    -- Check for ability usage
    if self:ShouldUseAbility(dino, distance) then
        return
    end

    -- Check attack range
    if distance <= def.attackRange then
        self:SetState(dino, "attacking")
        return
    end

    -- Move towards target
    self:MoveTowardsTarget(dino)
end

--[[
    Attack behavior - executing attacks

    @param dino table - Dinosaur data
]]
function DinoService:DoAttackBehavior(dino)
    local def = dino.config
    local now = tick()

    -- Validate target
    if not dino.target or not self:IsValidTarget(dino.target) then
        dino.target = nil
        self:SetState(dino, "hunting")
        return
    end

    local distance = self:GetDistanceToTarget(dino)
    if not distance then
        dino.target = nil
        self:SetState(dino, "hunting")
        return
    end

    -- Check if still in range
    if distance > def.attackRange * 1.2 then
        self:SetState(dino, "chasing")
        return
    end

    -- Check attack cooldown
    if now - dino.lastAttackTime < def.attackCooldown then
        return
    end

    -- Execute attack
    self:ExecuteAttack(dino)
end

--[[
    Ability behavior - using special ability

    @param dino table - Dinosaur data
]]
function DinoService:DoAbilityBehavior(dino)
    -- Abilities handle their own completion and state transition
    -- This is just a placeholder for the state machine
    if dino.stateTime >= 1 then
        self:SetState(dino, "chasing")
    end
end

--[[
    Flee behavior - running away from threats

    @param dino table - Dinosaur data
]]
function DinoService:DoFleeBehavior(dino)
    -- Find direction away from threats
    local fleeDirection = Vector3.new(0, 0, 0)
    local dinoPos = self:GetDinoPosition(dino)

    if not dinoPos then
        return
    end

    -- Run away from all threats
    for playerId, _ in pairs(dino.threatTable) do
        local player = Players:GetPlayerByUserId(playerId)
        if player and player.Character then
            local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                local awayDir = (dinoPos - rootPart.Position).Unit
                fleeDirection = fleeDirection + awayDir
            end
        end
    end

    -- Move in flee direction
    if fleeDirection.Magnitude > 0 then
        local humanoid = dino.model and dino.model:FindFirstChild("Humanoid")
        if humanoid then
            local fleePos = dinoPos + fleeDirection.Unit * 50
            humanoid:MoveTo(fleePos)
        end
    end

    -- Stop fleeing after recovery
    if dino.stateTime >= 10 then
        self:SetState(dino, "idle")
        dino.threatTable = {}
    end
end

--=============================================================================
-- TARGETING SYSTEM
--=============================================================================

--[[
    Find the best target for a dinosaur based on threat and distance

    @param dino table - Dinosaur data
    @return Player|nil - Best target or nil
]]
function DinoService:FindBestTarget(dino)
    local def = dino.config
    local aggroRadius = def.aggressionRadius or gameConfig.Dinosaurs.aggressionRadius
    local dinoPos = self:GetDinoPosition(dino)

    if not dinoPos then
        return nil
    end

    local bestTarget = nil
    local bestScore = 0

    -- Use spatial grid for O(1) nearby player lookup instead of O(n) all players
    local nearbyPlayerIds = getPlayersInRadius(dinoPos, aggroRadius)

    for _, userId in ipairs(nearbyPlayerIds) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            local character = player.Character
            if character then
                local rootPart = character:FindFirstChild("HumanoidRootPart")
                local humanoid = character:FindFirstChild("Humanoid")

                if rootPart and humanoid and humanoid.Health > 0 then
                    local distance = (rootPart.Position - dinoPos).Magnitude

                    -- Double-check distance (grid cells are approximate)
                    if distance <= aggroRadius then
                        -- Calculate target score (threat + proximity)
                        local threatLevel = dino.threatTable[player.UserId] or 0
                        local proximityScore = 1 - (distance / aggroRadius)
                        local score = threatLevel + proximityScore

                        if score > bestScore then
                            bestScore = score
                            bestTarget = player
                        end
                    end
                end
            end
        end
    end

    return bestTarget
end

--[[
    Check if a target is still valid

    @param target Player - Target to validate
    @return boolean - Is target valid
]]
function DinoService:IsValidTarget(target)
    if not target or not target.Parent then
        return false
    end

    local character = target.Character
    if not character then
        return false
    end

    local humanoid = character:FindFirstChild("Humanoid")
    return humanoid and humanoid.Health > 0
end

--[[
    Get distance to current target

    @param dino table - Dinosaur data
    @return number|nil - Distance or nil if invalid
]]
function DinoService:GetDistanceToTarget(dino)
    if not dino.target then
        return nil
    end

    local character = dino.target.Character
    if not character then
        return nil
    end

    local targetRoot = character:FindFirstChild("HumanoidRootPart")
    local dinoPos = self:GetDinoPosition(dino)

    if not targetRoot or not dinoPos then
        return nil
    end

    return (targetRoot.Position - dinoPos).Magnitude
end

--[[
    Get dinosaur's current position

    @param dino table - Dinosaur data
    @return Vector3|nil - Position or nil
]]
function DinoService:GetDinoPosition(dino)
    if dino.model and dino.model.PrimaryPart then
        return dino.model.PrimaryPart.Position
    end
    return dino.position
end

--[[
    Move dinosaur towards its target

    @param dino table - Dinosaur data
]]
function DinoService:MoveTowardsTarget(dino)
    if not dino.target then
        return
    end

    local character = dino.target.Character
    if not character then
        return
    end

    local targetRoot = character:FindFirstChild("HumanoidRootPart")
    local humanoid = dino.model and dino.model:FindFirstChild("Humanoid")

    if targetRoot and humanoid then
        humanoid:MoveTo(targetRoot.Position)
    end
end

--=============================================================================
-- COMBAT SYSTEM
--=============================================================================

--[[
    Execute a basic attack

    @param dino table - Dinosaur data
]]
function DinoService:ExecuteAttack(dino)
    local def = dino.config
    local now = tick()

    if not dino.target then
        return
    end

    local character = dino.target.Character
    if not character then
        return
    end

    local targetHumanoid = character:FindFirstChild("Humanoid")
    if not targetHumanoid then
        return
    end

    -- Play attack sound via AudioService
    local audioService = framework:GetService("AudioService")
    if audioService and audioService.PlayDinoSound then
        audioService:PlayDinoSound(dino.model, dino.type, "attack")
    end

    -- Calculate damage
    local damage = dino.damage

    -- Pack leader bonus
    if dino.packId then
        local pack = activePacks[dino.packId]
        if pack and pack.leader and activeDinosaurs[pack.leader] then
            local leaderAlive = activeDinosaurs[pack.leader].health > 0
            if leaderAlive and def.packBehavior and def.packBehavior.leaderBonus then
                damage = damage * def.packBehavior.leaderBonus
            end
        end
    end

    -- Swarm damage bonus
    if def.swarmBehavior then
        local nearbyCount = self:CountNearbyPackMembers(dino, 10)
        local bonus = 1 + (nearbyCount * def.swarmBehavior.damageBonus)
        bonus = math.min(bonus, def.swarmBehavior.maxBonus)
        damage = damage * bonus
    end

    -- Ambush bonus
    if dino.isCamouflaged and def.abilities and def.abilities.camouflage then
        damage = damage * (def.abilities.camouflage.ambushDamageBonus or 2.0)
        dino.isCamouflaged = false

        -- Make visible again
        if dino.model then
            for _, part in ipairs(dino.model:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Transparency = 0
                end
            end
        end
    end

    -- Apply damage
    targetHumanoid:TakeDamage(damage)
    dino.lastAttackTime = now

    -- Add threat
    self:AddThreat(dino, dino.target.UserId, damage * 0.5)

    -- Broadcast attack with distance filtering (only nearby players need this)
    local dinoPos = self:GetDinoPosition(dino)
    if dinoPos and networkUtils then
        networkUtils.FireNearby("DinoAttack", dinoPos, 250, {
            dinoId = dino.id,
            targetId = dino.target.UserId,
            damage = damage,
            attackType = "melee",
        })
    else
        -- Fallback to FireAllClients
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes and remotes:FindFirstChild("DinoAttack") then
            remotes.DinoAttack:FireAllClients({
                dinoId = dino.id,
                targetId = dino.target.UserId,
                damage = damage,
                attackType = "melee",
            })
        end
    end

    safeLog("Debug", "%s attacked %s for %d damage",
        dino.name, dino.target.Name, math.floor(damage))
end

--[[
    Damage a dinosaur

    @param dinoId string - Dinosaur ID
    @param damage number - Damage amount
    @param attacker Player|nil - Player who dealt damage
    @return boolean - Success
]]
function DinoService:DamageDinosaur(dinoId, damage, attacker)
    local dino = activeDinosaurs[dinoId]
    if not dino then
        return false
    end

    -- Apply armor reduction
    if dino.armor and dino.armor > 0 then
        damage = damage * (1 - dino.armor)
    end

    -- Apply damage
    dino.health = math.max(0, dino.health - damage)

    -- Play hurt sound via AudioService
    local audioService = framework:GetService("AudioService")
    if audioService and audioService.PlayDinoSound then
        audioService:PlayDinoSound(dino.model, dino.type, "hurt")
    end

    -- Update model humanoid
    local humanoid = dino.model and dino.model:FindFirstChild("Humanoid")
    if humanoid then
        humanoid.Health = dino.health
    end

    -- Add attacker to threat table
    if attacker then
        self:AddThreat(dino, attacker.UserId, damage)

        -- Passive dinosaurs become aggressive when attacked
        if dino.config.isPassive and dino.state == "idle" then
            dino.target = attacker
            self:SetState(dino, "alert")
        end
    end

    -- Broadcast damage with distance filtering
    local dinoPos = self:GetDinoPosition(dino)
    if dinoPos and networkUtils then
        networkUtils.FireNearby("DinoDamaged", dinoPos, 200, {
            dinoId = dinoId,
            damage = damage,
            health = dino.health,
            maxHealth = dino.maxHealth,
            attackerId = attacker and attacker.UserId or nil,
        })
    else
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes and remotes:FindFirstChild("DinoDamaged") then
            remotes.DinoDamaged:FireAllClients({
                dinoId = dinoId,
                damage = damage,
                health = dino.health,
                maxHealth = dino.maxHealth,
                attackerId = attacker and attacker.UserId or nil,
            })
        end
    end

    -- Check for boss phase transition
    if activeBosses[dinoId] then
        self:CheckBossPhaseTransition(dino)
    end

    -- Check death
    if dino.health <= 0 then
        self:KillDinosaur(dinoId, attacker)
    end

    return true
end

--[[
    Add threat to a dinosaur's threat table

    @param dino table - Dinosaur data
    @param playerId number - Player's UserId
    @param amount number - Threat amount to add
]]
function DinoService:AddThreat(dino, playerId, amount)
    dino.threatTable[playerId] = (dino.threatTable[playerId] or 0) + amount
end

--[[
    Kill a dinosaur

    @param dinoId string - Dinosaur ID
    @param killer Player|nil - Player who killed the dinosaur
]]
function DinoService:KillDinosaur(dinoId, killer)
    local dino = activeDinosaurs[dinoId]
    if not dino then
        return
    end

    dino.state = "dead"

    -- Play death sound via AudioService
    local audioService = framework:GetService("AudioService")
    if audioService and audioService.PlayDinoSound then
        audioService:PlayDinoSound(dino.model, dino.type, "death")
    end

    safeLog("Info", "%s killed by %s", dino.name, killer and killer.Name or "unknown")

    -- Handle pack leader death
    if dino.packId and dino.isPackLeader then
        self:OnPackLeaderDeath(dino)
    end

    -- Remove from pack
    if dino.packId and activePacks[dino.packId] then
        local pack = activePacks[dino.packId]
        for i, memberId in ipairs(pack.members) do
            if memberId == dinoId then
                table.remove(pack.members, i)
                break
            end
        end

        -- Clean up empty packs
        if #pack.members == 0 then
            activePacks[dino.packId] = nil
        end
    end

    -- Spawn loot
    self:SpawnDinoLoot(dino, killer)

    -- Broadcast death
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local remote = activeBosses[dinoId] and remotes:FindFirstChild("BossDied")
            or remotes:FindFirstChild("DinoDied")

        if remote then
            remote:FireAllClients({
                dinoId = dinoId,
                killerUserId = killer and killer.UserId or nil,
                position = self:GetDinoPosition(dino),
            })
        end
    end

    -- Clean up boss data
    if activeBosses[dinoId] then
        activeBosses[dinoId] = nil
    end

    -- Play death animation (fall over) then fade out and despawn
    if dino.model then
        self:PlayDeathAnimation(dino)
    end

    -- Remove from active list
    activeDinosaurs[dinoId] = nil
end

--[[
    Play death animation for a dinosaur
    Makes the dinosaur fall over, fade out, then despawn

    @param dino table - Dinosaur data
]]
function DinoService:PlayDeathAnimation(dino)
    local model = dino.model
    if not model then return end

    local primaryPart = model.PrimaryPart
    if not primaryPart then return end

    -- Disable physics control by removing humanoid walkspeed
    local humanoid = model:FindFirstChild("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        humanoid.PlatformStand = true  -- Ragdoll-like state
    end

    -- Calculate fall direction (sideways)
    local fallDirection = primaryPart.CFrame.RightVector
    local startCFrame = primaryPart.CFrame
    local fallAngle = math.rad(90)  -- Fall 90 degrees to the side

    -- Animate the fall over 0.5 seconds
    local fallDuration = 0.5
    local startTime = tick()

    local fallConnection
    fallConnection = RunService.Heartbeat:Connect(function()
        if not model or not model.Parent then
            fallConnection:Disconnect()
            return
        end

        local elapsed = tick() - startTime
        local progress = math.min(elapsed / fallDuration, 1)

        -- Ease out for natural fall
        local easedProgress = 1 - (1 - progress) ^ 2

        -- Rotate around the length axis (fall to the side)
        local currentAngle = fallAngle * easedProgress
        local fallCFrame = startCFrame * CFrame.Angles(0, 0, currentAngle)

        -- Also drop slightly as it falls
        local dropAmount = easedProgress * 1.5
        fallCFrame = fallCFrame - Vector3.new(0, dropAmount, 0)

        pcall(function()
            model:SetPrimaryPartCFrame(fallCFrame)
        end)

        if progress >= 1 then
            fallConnection:Disconnect()

            -- Start fade out after lying on ground for 2 seconds
            task.delay(2, function()
                if model and model.Parent then
                    self:FadeOutAndDestroy(model, 1.5)  -- 1.5 second fade
                end
            end)
        end
    end)
end

--[[
    Fade out a model and then destroy it

    @param model Model - The model to fade
    @param duration number - Fade duration in seconds
]]
function DinoService:FadeOutAndDestroy(model, duration)
    if not model or not model.Parent then return end

    local startTime = tick()
    local parts = {}

    -- Collect all parts and their original transparency
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(parts, {
                part = descendant,
                originalTransparency = descendant.Transparency
            })
        end
    end

    local fadeConnection
    fadeConnection = RunService.Heartbeat:Connect(function()
        if not model or not model.Parent then
            fadeConnection:Disconnect()
            return
        end

        local elapsed = tick() - startTime
        local progress = math.min(elapsed / duration, 1)

        -- Fade all parts
        for _, partData in ipairs(parts) do
            if partData.part and partData.part.Parent then
                -- Lerp from original transparency to 1 (fully transparent)
                partData.part.Transparency = partData.originalTransparency +
                    (1 - partData.originalTransparency) * progress
            end
        end

        if progress >= 1 then
            fadeConnection:Disconnect()
            -- Destroy the model
            if model and model.Parent then
                model:Destroy()
            end
        end
    end)
end

--[[
    Spawn loot from a killed dinosaur

    @param dino table - Dinosaur data
    @param killer Player|nil - Player who killed the dinosaur
]]
function DinoService:SpawnDinoLoot(dino, killer)
    local def = dino.config
    local position = self:GetDinoPosition(dino)
    if not position then
        return
    end

    -- Get LootSystem (use GetModule since it's registered as a module)
    local lootSystem = framework:GetModule("LootSystem")

    -- Check if this is a boss dinosaur
    local isBoss = dino.isBoss or (def.behavior == "boss") or activeBosses[dino.id]

    if isBoss and lootSystem and lootSystem.SpawnBossDropLoot then
        -- Use GDD-compliant boss drop rarity distribution
        -- Boss Drop: 0% Common, 0% Uncommon, 20% Rare, 50% Epic, 30% Legendary
        local bossType = def.id or dino.type
        lootSystem:SpawnBossDropLoot(position, bossType)
        safeLog("Info", "Spawned boss loot for %s", bossType)
        return
    end

    -- Regular dinosaur loot (use loot table from config)
    local lootTable = def.lootTable
    if not lootTable then
        return
    end

    for _, lootEntry in ipairs(lootTable) do
        if math.random() <= lootEntry.chance then
            if lootSystem and lootSystem.SpawnLootItem then
                -- Use LootSystem for proper loot spawning
                local count = 1
                if lootEntry.count then
                    count = math.random(lootEntry.count[1], lootEntry.count[2])
                end

                lootSystem:SpawnLootItem(lootEntry.item, lootEntry.type or "ammo", position, lootEntry.rarity, count)
            else
                -- Fallback: Log what would be spawned
                safeLog("Debug", "Loot drop: %s at %s", lootEntry.item, tostring(position))
            end
        end
    end
end

--=============================================================================
-- ABILITY SYSTEM
--=============================================================================

--[[
    Check if dinosaur should use an ability

    @param dino table - Dinosaur data
    @param distance number - Distance to target
    @return boolean - True if ability was used
]]
function DinoService:ShouldUseAbility(dino, distance)
    local def = dino.config
    local abilities = def.abilities

    if not abilities then
        return false
    end

    -- Check each ability
    for abilityName, abilityDef in pairs(abilities) do
        if abilityDef.enabled and self:CanUseAbility(dino, abilityName) then
            -- Check range-based abilities
            if abilityName == "charge" and distance >= 15 and distance <= (abilityDef.range or 25) then
                return self:TryAbility(dino, "charge")
            elseif abilityName == "pounce" and distance >= 8 and distance <= (abilityDef.range or 15) then
                return self:TryAbility(dino, "pounce")
            elseif abilityName == "venom_spit" and distance <= (abilityDef.range or 25) then
                return self:TryAbility(dino, "venom_spit")
            elseif abilityName == "roar" and distance <= (abilityDef.fearRadius or 30) then
                -- Use roar randomly or when multiple targets nearby
                if math.random() < 0.1 then
                    return self:TryAbility(dino, "roar")
                end
            elseif abilityName == "tail_swipe" then
                -- Use when surrounded or close range
                local nearbyPlayers = self:CountNearbyPlayers(dino, abilityDef.radius or 15)
                if nearbyPlayers >= 2 or distance <= 8 then
                    return self:TryAbility(dino, "tail_swipe")
                end
            elseif abilityName == "dive_bomb" and def.isFlying then
                return self:TryAbility(dino, "dive_bomb")
            end
        end
    end

    return false
end

--[[
    Check if an ability can be used (off cooldown)

    @param dino table - Dinosaur data
    @param abilityName string - Ability name
    @return boolean - Can use ability
]]
function DinoService:CanUseAbility(dino, abilityName)
    local now = tick()
    local lastUsed = dino.abilityCooldowns[abilityName] or 0
    local def = dino.config.abilities[abilityName]

    if not def then
        return false
    end

    local cooldown = def.cooldown or ABILITY_COOLDOWNS[abilityName] or 10
    return (now - lastUsed) >= cooldown
end

--[[
    Try to use an ability

    @param dino table - Dinosaur data
    @param abilityName string - Ability name
    @return boolean - Success
]]
function DinoService:TryAbility(dino, abilityName)
    if not self:CanUseAbility(dino, abilityName) then
        return false
    end

    local def = dino.config.abilities[abilityName]
    if not def then
        return false
    end

    -- Execute ability
    local success = false

    if abilityName == "roar" then
        success = self:ExecuteRoar(dino, def)
    elseif abilityName == "charge" then
        success = self:ExecuteCharge(dino, def)
    elseif abilityName == "pounce" then
        success = self:ExecutePounce(dino, def)
    elseif abilityName == "venom_spit" then
        success = self:ExecuteVenomSpit(dino, def)
    elseif abilityName == "tail_swipe" then
        success = self:ExecuteTailSwipe(dino, def)
    elseif abilityName == "dive_bomb" then
        success = self:ExecuteDiveBomb(dino, def)
    elseif abilityName == "camouflage" then
        success = self:ExecuteCamouflage(dino, def)
    elseif abilityName == "ground_pound" then
        success = self:ExecuteGroundPound(dino, def)
    end

    if success then
        dino.abilityCooldowns[abilityName] = tick()
        self:SetState(dino, "ability")

        -- Broadcast ability use
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes and remotes:FindFirstChild("DinoAbility") then
            remotes.DinoAbility:FireAllClients({
                dinoId = dino.id,
                ability = abilityName,
                position = self:GetDinoPosition(dino),
            })
        end
    end

    return success
end

--[[
    Execute Roar ability - fear effect on nearby players

    @param dino table - Dinosaur data
    @param def table - Ability definition
    @return boolean - Success
]]
function DinoService:ExecuteRoar(dino, def)
    local dinoPos = self:GetDinoPosition(dino)
    if not dinoPos then
        return false
    end

    local radius = def.fearRadius or 30
    local duration = def.fearDuration or 3

    -- Apply fear to nearby players
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                local distance = (rootPart.Position - dinoPos).Magnitude
                if distance <= radius then
                    -- Fear effect: slow movement (handled client-side via remote)
                    safeLog("Debug", "%s feared %s with roar", dino.name, player.Name)
                end
            end
        end
    end

    return true
end

--[[
    Execute Charge ability - dash at target with knockback

    @param dino table - Dinosaur data
    @param def table - Ability definition
    @return boolean - Success
]]
function DinoService:ExecuteCharge(dino, def)
    if not dino.target then
        return false
    end

    local character = dino.target.Character
    if not character then
        return false
    end

    local targetRoot = character:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = character:FindFirstChild("Humanoid")
    local dinoPos = self:GetDinoPosition(dino)

    if not targetRoot or not targetHumanoid or not dinoPos then
        return false
    end

    -- Calculate charge
    local damage = def.damage or 50
    local knockback = def.knockback or 40

    -- Apply damage
    targetHumanoid:TakeDamage(damage)

    -- Apply knockback
    local knockbackDir = (targetRoot.Position - dinoPos).Unit
    local knockbackForce = Instance.new("BodyVelocity")
    knockbackForce.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    knockbackForce.Velocity = knockbackDir * knockback + Vector3.new(0, 20, 0)
    knockbackForce.Parent = targetRoot
    Debris:AddItem(knockbackForce, 0.3)

    -- Apply stun if defined
    if def.stunDuration then
        -- Stun effect handled client-side
    end

    safeLog("Debug", "%s charged %s for %d damage", dino.name, dino.target.Name, damage)

    return true
end

--[[
    Execute Pounce ability - leap at target

    @param dino table - Dinosaur data
    @param def table - Ability definition
    @return boolean - Success
]]
function DinoService:ExecutePounce(dino, def)
    if not dino.target then
        return false
    end

    local character = dino.target.Character
    if not character then
        return false
    end

    local targetRoot = character:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = character:FindFirstChild("Humanoid")

    if not targetRoot or not targetHumanoid then
        return false
    end

    local damage = def.damage or 35

    -- Deal damage
    targetHumanoid:TakeDamage(damage)

    -- Stun effect
    if def.stunDuration then
        -- Handled client-side
    end

    safeLog("Debug", "%s pounced on %s for %d damage", dino.name, dino.target.Name, damage)

    return true
end

--[[
    Execute Venom Spit ability - ranged blind attack

    @param dino table - Dinosaur data
    @param def table - Ability definition
    @return boolean - Success
]]
function DinoService:ExecuteVenomSpit(dino, def)
    if not dino.target then
        return false
    end

    local character = dino.target.Character
    if not character then
        return false
    end

    local targetHumanoid = character:FindFirstChild("Humanoid")
    if not targetHumanoid then
        return false
    end

    local damage = def.damage or 15

    -- Initial damage
    targetHumanoid:TakeDamage(damage)

    -- Damage over time
    if def.dotDamage and def.dotDuration then
        task.spawn(function()
            local ticks = def.dotDuration
            for i = 1, ticks do
                task.wait(1)
                if targetHumanoid and targetHumanoid.Health > 0 then
                    targetHumanoid:TakeDamage(def.dotDamage)
                end
            end
        end)
    end

    -- Blind effect handled client-side via remote

    safeLog("Debug", "%s spit venom at %s", dino.name, dino.target.Name)

    return true
end

--[[
    Execute Tail Swipe ability - AoE knockback

    @param dino table - Dinosaur data
    @param def table - Ability definition
    @return boolean - Success
]]
function DinoService:ExecuteTailSwipe(dino, def)
    local dinoPos = self:GetDinoPosition(dino)
    if not dinoPos then
        return false
    end

    local radius = def.radius or 15
    local damage = def.damage or 30
    local knockback = def.knockback or 30

    local hitCount = 0

    -- Hit all players in radius
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChild("Humanoid")

            if rootPart and humanoid and humanoid.Health > 0 then
                local distance = (rootPart.Position - dinoPos).Magnitude

                if distance <= radius then
                    -- Deal damage
                    humanoid:TakeDamage(damage)

                    -- Apply knockback
                    local knockbackDir = (rootPart.Position - dinoPos).Unit
                    local knockbackForce = Instance.new("BodyVelocity")
                    knockbackForce.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                    knockbackForce.Velocity = knockbackDir * knockback + Vector3.new(0, 15, 0)
                    knockbackForce.Parent = rootPart
                    Debris:AddItem(knockbackForce, 0.3)

                    hitCount = hitCount + 1
                end
            end
        end
    end

    safeLog("Debug", "%s tail swipe hit %d players", dino.name, hitCount)

    return hitCount > 0
end

--[[
    Execute Dive Bomb ability - aerial attack

    @param dino table - Dinosaur data
    @param def table - Ability definition
    @return boolean - Success
]]
function DinoService:ExecuteDiveBomb(dino, def)
    if not dino.target then
        return false
    end

    local character = dino.target.Character
    if not character then
        return false
    end

    local targetHumanoid = character:FindFirstChild("Humanoid")
    if not targetHumanoid then
        return false
    end

    local damage = def.damage or 45

    -- Deal damage
    targetHumanoid:TakeDamage(damage)

    -- Stun
    if def.stunOnHit then
        -- Handled client-side
    end

    safeLog("Debug", "%s dive bombed %s for %d damage", dino.name, dino.target.Name, damage)

    return true
end

--[[
    Execute Camouflage ability - become invisible

    @param dino table - Dinosaur data
    @param def table - Ability definition
    @return boolean - Success
]]
function DinoService:ExecuteCamouflage(dino, def)
    dino.isCamouflaged = true

    -- Make model transparent
    if dino.model then
        for _, part in ipairs(dino.model:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Transparency = 0.8
            end
        end
    end

    -- Auto-uncloak after duration
    local duration = def.duration or 10
    task.delay(duration, function()
        if activeDinosaurs[dino.id] and dino.isCamouflaged then
            dino.isCamouflaged = false
            if dino.model then
                for _, part in ipairs(dino.model:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.Transparency = 0
                    end
                end
            end
        end
    end)

    safeLog("Debug", "%s activated camouflage", dino.name)

    return true
end

--[[
    Execute Ground Pound ability - AoE stun (boss ability)

    @param dino table - Dinosaur data
    @param def table - Ability definition
    @return boolean - Success
]]
function DinoService:ExecuteGroundPound(dino, def)
    local dinoPos = self:GetDinoPosition(dino)
    if not dinoPos then
        return false
    end

    local radius = def.radius or 25
    local damage = def.damage or 80
    local stunDuration = def.stunDuration or 2

    local hitCount = 0

    -- Hit all players in radius
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChild("Humanoid")

            if rootPart and humanoid and humanoid.Health > 0 then
                local distance = (rootPart.Position - dinoPos).Magnitude

                if distance <= radius then
                    -- Deal damage (falloff with distance)
                    local falloff = 1 - (distance / radius) * 0.5
                    local actualDamage = damage * falloff
                    humanoid:TakeDamage(actualDamage)

                    hitCount = hitCount + 1
                end
            end
        end
    end

    safeLog("Debug", "%s ground pound hit %d players", dino.name, hitCount)

    return true
end

--=============================================================================
-- PACK BEHAVIOR SYSTEM
--=============================================================================

--[[
    Update all pack behaviors
]]
function DinoService:UpdatePackBehaviors()
    for packId, pack in pairs(activePacks) do
        if pack.leader and activeDinosaurs[pack.leader] then
            local leader = activeDinosaurs[pack.leader]

            -- Make pack members follow leader
            for _, memberId in ipairs(pack.members) do
                if memberId ~= pack.leader then
                    local member = activeDinosaurs[memberId]
                    if member and member.health > 0 then
                        self:UpdatePackMemberBehavior(member, leader)
                    end
                end
            end
        end
    end
end

--[[
    Update behavior for a pack member

    @param member table - Pack member dinosaur
    @param leader table - Pack leader dinosaur
]]
function DinoService:UpdatePackMemberBehavior(member, leader)
    local def = member.config

    -- If leader has a target, member should too
    if leader.target and not member.target then
        member.target = leader.target
        if member.state == "idle" then
            self:SetState(member, "alert")
        end
    end

    -- Flanking behavior
    if def.packBehavior and def.packBehavior.flanking and member.target then
        self:UpdateFlankingPosition(member, leader)
    end
end

--[[
    Update flanking position for pack member

    @param member table - Pack member
    @param leader table - Pack leader
]]
function DinoService:UpdateFlankingPosition(member, leader)
    if not member.target then
        return
    end

    local character = member.target.Character
    if not character then
        return
    end

    local targetRoot = character:FindFirstChild("HumanoidRootPart")
    local leaderPos = self:GetDinoPosition(leader)

    if not targetRoot or not leaderPos then
        return
    end

    -- Calculate flank position (opposite side from leader)
    local targetPos = targetRoot.Position
    local leaderToTarget = (targetPos - leaderPos).Unit

    -- Rotate to create flanking angle
    local flankAngle = FLANK_ANGLE * (member.id:byte(1) % 2 == 0 and 1 or -1)
    local flankDir = CFrame.Angles(0, flankAngle, 0) * CFrame.new(leaderToTarget)
    local flankPos = targetPos + flankDir.Position.Unit * 10

    -- Move towards flank position
    local humanoid = member.model and member.model:FindFirstChild("Humanoid")
    if humanoid and member.state == "chasing" then
        humanoid:MoveTo(flankPos)
    end
end

--[[
    Alert pack members when leader detects threat

    @param leader table - Pack leader dinosaur
]]
function DinoService:AlertPack(leader)
    if not leader.packId then
        return
    end

    local pack = activePacks[leader.packId]
    if not pack then
        return
    end

    local def = leader.config
    local callRange = def.packBehavior and def.packBehavior.callRange or 40
    local leaderPos = self:GetDinoPosition(leader)

    if not leaderPos then
        return
    end

    -- Alert nearby pack members
    for _, memberId in ipairs(pack.members) do
        if memberId ~= leader.id then
            local member = activeDinosaurs[memberId]
            if member and member.health > 0 then
                local memberPos = self:GetDinoPosition(member)
                if memberPos and (memberPos - leaderPos).Magnitude <= callRange then
                    member.target = leader.target
                    if member.state == "idle" then
                        self:SetState(member, "alert")
                    end
                end
            end
        end
    end

    -- Broadcast pack alert
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes and remotes:FindFirstChild("PackAlert") then
        remotes.PackAlert:FireAllClients({
            packId = leader.packId,
            position = leaderPos,
        })
    end
end

--[[
    Handle pack leader death

    @param leader table - Dead pack leader
]]
function DinoService:OnPackLeaderDeath(leader)
    if not leader.packId then
        return
    end

    local pack = activePacks[leader.packId]
    if not pack then
        return
    end

    local def = leader.config

    -- Check if pack should scatter
    if def.packBehavior and def.packBehavior.scatterOnLeaderDeath then
        for _, memberId in ipairs(pack.members) do
            local member = activeDinosaurs[memberId]
            if member and member.health > 0 and memberId ~= leader.id then
                -- Chance to flee or become enraged
                if math.random() < 0.7 then
                    self:SetState(member, "fleeing")
                else
                    member.isEnraged = true
                    member.damage = member.damage * 1.5
                end
            end
        end
    end

    -- Assign new leader if pack survives
    for _, memberId in ipairs(pack.members) do
        local member = activeDinosaurs[memberId]
        if member and member.health > 0 and memberId ~= leader.id then
            pack.leader = memberId
            member.isPackLeader = true
            break
        end
    end
end

--[[
    Count nearby pack members

    @param dino table - Dinosaur to check around
    @param radius number - Search radius
    @return number - Count of nearby pack members
]]
function DinoService:CountNearbyPackMembers(dino, radius)
    if not dino.packId then
        return 0
    end

    local pack = activePacks[dino.packId]
    if not pack then
        return 0
    end

    local dinoPos = self:GetDinoPosition(dino)
    if not dinoPos then
        return 0
    end

    local count = 0
    for _, memberId in ipairs(pack.members) do
        if memberId ~= dino.id then
            local member = activeDinosaurs[memberId]
            if member and member.health > 0 then
                local memberPos = self:GetDinoPosition(member)
                if memberPos and (memberPos - dinoPos).Magnitude <= radius then
                    count = count + 1
                end
            end
        end
    end

    return count
end

--[[
    Count nearby players

    @param dino table - Dinosaur to check around
    @param radius number - Search radius
    @return number - Count of nearby players
]]
function DinoService:CountNearbyPlayers(dino, radius)
    local dinoPos = self:GetDinoPosition(dino)
    if not dinoPos then
        return 0
    end

    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                local distance = (rootPart.Position - dinoPos).Magnitude
                if distance <= radius then
                    count = count + 1
                end
            end
        end
    end

    return count
end

--=============================================================================
-- BOSS SYSTEM
--=============================================================================

--[[
    Spawn a boss dinosaur

    @param bossType string - Boss type name
    @param position Vector3 - Spawn position
    @return table|nil - Boss dinosaur data
]]
function DinoService:SpawnBoss(bossType, position)
    local bossDef = BOSS_DEFINITIONS[bossType]
    if not bossDef then
        safeLog("Error", "Unknown boss type: %s", bossType)
        return nil
    end

    local baseDef = DINOSAUR_DEFINITIONS[bossDef.baseDino]
    if not baseDef then
        safeLog("Error", "Unknown base dinosaur for boss: %s", bossDef.baseDino)
        return nil
    end

    -- Generate unique ID
    local bossId = game:GetService("HttpService"):GenerateGUID(false)

    -- Calculate enhanced stats
    local health = baseDef.health * (bossDef.healthMultiplier or 2)
    local damage = baseDef.damage * (bossDef.damageMultiplier or 1.5)
    local speed = baseDef.speed * (bossDef.speedMultiplier or 1)

    -- Create boss data
    local boss = {
        -- Identity
        id = bossId,
        type = bossType,
        baseDino = bossDef.baseDino,
        name = bossDef.name,
        isBoss = true,

        -- Stats
        health = health,
        maxHealth = health,
        damage = damage,
        speed = speed,
        armor = baseDef.armor or 0,

        -- Position
        position = position,

        -- State
        state = "idle",
        previousState = nil,
        stateTime = 0,

        -- Targeting
        target = nil,
        threatTable = {},

        -- Combat
        lastAttackTime = 0,
        abilityCooldowns = {},
        isStunned = false,
        stunEndTime = 0,

        -- Boss-specific
        phase = 1,
        isEnraged = false,

        -- Config
        config = baseDef,
        bossConfig = bossDef,

        -- Model
        model = nil,
    }

    -- Initialize ability cooldowns (base + boss abilities)
    if baseDef.abilities then
        for abilityName, _ in pairs(baseDef.abilities) do
            boss.abilityCooldowns[abilityName] = 0
        end
    end
    if bossDef.abilities then
        for abilityName, _ in pairs(bossDef.abilities) do
            boss.abilityCooldowns[abilityName] = 0
        end
    end

    -- Create boss model
    boss.model = self:CreateBossModel(boss, baseDef, bossDef, position)

    -- Store in active lists
    activeDinosaurs[bossId] = boss
    activeBosses[bossId] = {
        id = bossId,
        type = bossType,
        phase = 1,
        spawnTime = tick(),
    }

    -- Spawn escort pack if defined
    if bossDef.packOnSpawn then
        for i = 1, bossDef.packOnSpawn.count do
            local offset = Vector3.new(
                math.random(-15, 15),
                0,
                math.random(-15, 15)
            )
            self:SpawnDinosaur(bossDef.packOnSpawn.type, position + offset, nil)
        end
    end

    -- Broadcast boss spawn
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes and remotes:FindFirstChild("BossSpawned") then
        remotes.BossSpawned:FireAllClients({
            id = bossId,
            type = bossType,
            name = bossDef.name,
            position = position,
            health = health,
            maxHealth = health,
            phase = 1,
        })
    end

    safeLog("Info", "Boss spawned: %s at %s", bossDef.name, tostring(position))

    return boss
end

--[[
    Create boss model with enhanced visuals

    @param boss table - Boss data
    @param baseDef table - Base dinosaur definition
    @param bossDef table - Boss definition
    @param position Vector3 - Spawn position
    @return Model - Boss model
]]
function DinoService:CreateBossModel(boss, baseDef, bossDef, position)
    local model = self:CreateDinosaurModel(bossDef.baseDino, baseDef, position)

    -- Scale up
    local scale = bossDef.sizeMultiplier or 1.5
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Size = part.Size * scale

            -- Apply boss color
            if bossDef.color then
                part.Color = bossDef.color
            end
        end
    end

    -- Add glow effect if enabled
    if bossDef.glowEnabled then
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                local light = Instance.new("PointLight")
                light.Color = bossDef.glowColor or Color3.new(1, 0, 0)
                light.Range = 15
                light.Brightness = 2
                light.Parent = part
                break  -- Only one light
            end
        end
    end

    -- Update model name
    model.Name = "Boss_" .. boss.type

    return model
end

--[[
    Check and handle boss phase transitions

    @param boss table - Boss dinosaur data
]]
function DinoService:CheckBossPhaseTransition(boss)
    if not boss.isBoss then
        return
    end

    local healthPercent = boss.health / boss.maxHealth
    local currentPhase = boss.phase
    local newPhase = currentPhase

    -- Determine new phase based on health
    if healthPercent <= BOSS_PHASE_THRESHOLDS.phase3 and currentPhase < 3 then
        newPhase = 3
    elseif healthPercent <= BOSS_PHASE_THRESHOLDS.phase2 and currentPhase < 2 then
        newPhase = 2
    end

    if newPhase ~= currentPhase then
        self:TransitionBossPhase(boss, newPhase)
    end
end

--[[
    Transition boss to a new phase

    @param boss table - Boss data
    @param newPhase number - New phase number
]]
function DinoService:TransitionBossPhase(boss, newPhase)
    local bossDef = boss.bossConfig
    local phaseConfig = bossDef.phases[newPhase]

    boss.phase = newPhase

    -- Apply phase bonuses
    if phaseConfig.speedBonus then
        boss.speed = boss.speed * (1 + phaseConfig.speedBonus)
        local humanoid = boss.model and boss.model:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = boss.speed
        end
    end

    if phaseConfig.damageBonus then
        boss.damage = boss.damage * (1 + phaseConfig.damageBonus)
    end

    -- Rage mode visual effects
    if newPhase == 3 then
        boss.isEnraged = true

        -- Visual feedback
        if boss.model then
            for _, part in ipairs(boss.model:GetDescendants()) do
                if part:IsA("BasePart") then
                    local fire = Instance.new("Fire")
                    fire.Color = Color3.new(1, 0.3, 0)
                    fire.SecondaryColor = Color3.new(1, 0, 0)
                    fire.Size = 5
                    fire.Parent = part
                    break
                end
            end
        end
    end

    -- Update boss record
    if activeBosses[boss.id] then
        activeBosses[boss.id].phase = newPhase
    end

    -- Broadcast phase change
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes and remotes:FindFirstChild("BossPhaseChanged") then
        remotes.BossPhaseChanged:FireAllClients({
            id = boss.id,
            phase = newPhase,
            isEnraged = boss.isEnraged,
        })
    end

    safeLog("Info", "Boss %s entered phase %d", boss.name, newPhase)
end

--=============================================================================
-- UTILITY FUNCTIONS
--=============================================================================

--[[
    Get count of active dinosaurs

    @return number - Active dinosaur count
]]
function DinoService:GetActiveCount()
    local count = 0
    for _ in pairs(activeDinosaurs) do
        count = count + 1
    end
    return count
end

--[[
    Get all active dinosaurs

    @return table - All active dinosaurs
]]
function DinoService:GetAllActive()
    return activeDinosaurs
end

--[[
    Get all active bosses

    @return table - All active bosses
]]
function DinoService:GetActiveBosses()
    return activeBosses
end

--[[
    Despawn all dinosaurs
]]
function DinoService:DespawnAll()
    safeLog("Info", "Despawning all dinosaurs")

    for dinoId, dino in pairs(activeDinosaurs) do
        if dino.model then
            dino.model:Destroy()
        end
    end

    activeDinosaurs = {}
    activePacks = {}
    activeBosses = {}
end

--[[
    Shutdown the service
]]
function DinoService:Shutdown()
    self:StopSpawning()
    self:DespawnAll()
    safeLog("Info", "DinoService shut down")
end

--=============================================================================
-- EXTERNAL ACCESS
--=============================================================================

-- Store definitions for external access
DinoService.DINOSAUR_DEFINITIONS = DINOSAUR_DEFINITIONS
DinoService.BOSS_DEFINITIONS = BOSS_DEFINITIONS

return DinoService
