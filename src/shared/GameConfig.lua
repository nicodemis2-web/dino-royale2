--[[
    =========================================================================
    Dino Royale 2 - Central Game Configuration
    =========================================================================

    This file contains all configurable game parameters for Dino Royale 2.
    Modify these values to tune gameplay without changing code logic.

    SECTIONS:
    1. Match Settings - Player limits, timing, drop mechanics
    2. Game Modes - Solo, Duos, Trios configurations
    3. Storm/Zone - Shrinking zone mechanics
    4. Dinosaurs - AI, spawning, stats
    5. Weapons - Categories, damage multipliers
    6. Map - Biomes, POIs, environmental events
    7. Loot - Spawn rates, rarity weights
    8. Player - Health, inventory, movement
    9. UI - HUD settings
    10. Audio - Volume levels
    11. Debug - Development tools

    =========================================================================
]]

local GameConfig = {}

--=============================================================================
-- MATCH SETTINGS
-- Core match parameters for lobby and game flow
--=============================================================================

GameConfig.Match = {
    -- Player limits
    maxPlayers = 20,               -- Maximum players per match
    minPlayersToStart = 4,         -- Minimum players to start match

    -- Timing (seconds)
    lobbyWaitTime = 60,            -- Max time to wait in lobby
    matchMaxDuration = 600,        -- 10 minute hard limit
    intermissionTime = 15,         -- Time between matches
    warmupTime = 10,               -- Pre-drop warmup period

    -- Drop mechanics
    dropHeight = 500,              -- Height players spawn at
    dropSpeed = 50,                -- Fall speed (studs/second)
    parachuteHeight = 50,          -- Auto-deploy parachute height
    parachuteSpeed = 20,           -- Descent speed with parachute

    -- Victory conditions
    victoryDisplayTime = 10,       -- Time to show victory screen
    xpMultiplier = 1.0,            -- XP multiplier for this mode
}

--=============================================================================
-- GAME MODES
-- Configuration for Solo, Duos, and Trios
--=============================================================================

GameConfig.Modes = {
    solo = {
        name = "Solo",
        description = "Every player for themselves",
        maxPlayers = 20,
        teamSize = 1,
        friendlyFire = false,
        reviveEnabled = false,
    },

    duos = {
        name = "Duos",
        description = "Team up with a partner",
        maxPlayers = 20,
        teamSize = 2,
        friendlyFire = false,
        reviveEnabled = true,
        reviveTime = 5,            -- Seconds to complete revive
        bleedoutTime = 30,         -- Seconds before death when downed
    },

    trios = {
        name = "Trios",
        description = "Squad up with two teammates",
        maxPlayers = 21,           -- 7 teams of 3
        teamSize = 3,
        friendlyFire = false,
        reviveEnabled = true,
        reviveTime = 5,
        bleedoutTime = 30,
    },
}

--=============================================================================
-- STORM/ZONE CONFIGURATION
-- Shrinking safe zone mechanics - Industry-standard battle royale storm
-- Based on Fortnite/PUBG best practices for 20-minute match length
-- Storm starts OUTSIDE the map and progressively shrinks inward
--=============================================================================

GameConfig.Storm = {
    enabled = true,
    damageInterval = 1.0,          -- Seconds between damage ticks
    warningTime = 10,              -- Seconds warning before zone moves
    initialRadius = 500,           -- Starting radius (covers full map)
    mapRadius = 500,               -- Actual playable map radius

    -- Grace period - no storm damage at match start
    gracePeriod = 30,              -- 30 seconds before storm activates

    -- Storm visuals
    stormColor = Color3.fromRGB(100, 50, 150),
    stormTransparency = 0.3,
    safeZoneColor = Color3.fromRGB(50, 200, 255),

    --[[
        Storm Phases - GDD Compliant (5 phases, 5-10 minute matches)

        Total time breakdown (~7 minutes):
        - Grace period: 30s
        - Phase 1: 30s delay + 20s shrink = 50s
        - Phase 2: 20s delay + 15s shrink = 35s
        - Phase 3: 15s delay + 12s shrink = 27s
        - Phase 4: 10s delay + 10s shrink = 20s
        - Phase 5: 5s delay + 8s shrink = 13s
        Total: ~6-7 minutes (within GDD's 5-10 minute target)
    ]]
    phases = {
        -- Phase 1: First shrink - exploration/looting phase
        {
            delay = 30,            -- 30 second wait (GDD: 30s)
            shrinkTime = 20,       -- 20 second shrink (GDD: 20s)
            endRadius = 200,       -- End at 200 radius (GDD: 200)
            damage = 1,            -- 1 damage per tick (GDD: 1)
            centerOffset = 0.1,    -- Slight center shift
        },
        -- Phase 2: Second shrink - mid-game begins
        {
            delay = 20,            -- 20 second wait (GDD: 20s)
            shrinkTime = 15,       -- 15 second shrink (GDD: 15s)
            endRadius = 120,       -- End at 120 radius (GDD: 120)
            damage = 2,            -- 2 damage per tick (GDD: 2)
            centerOffset = 0.15,
        },
        -- Phase 3: Mid-game - action intensifies
        {
            delay = 15,            -- 15 second wait (GDD: 15s)
            shrinkTime = 12,       -- 12 second shrink (GDD: 12s)
            endRadius = 60,        -- End at 60 radius (GDD: 60)
            damage = 4,            -- 4 damage per tick (GDD: 4)
            centerOffset = 0.2,
        },
        -- Phase 4: Endgame - high pressure
        {
            delay = 10,            -- 10 second wait (GDD: 10s)
            shrinkTime = 10,       -- 10 second shrink (GDD: 10s)
            endRadius = 25,        -- End at 25 radius (GDD: 25)
            damage = 8,            -- 8 damage per tick (GDD: 8)
            centerOffset = 0.15,
        },
        -- Phase 5: Final close - lethal zone
        {
            delay = 5,             -- 5 second wait (GDD: 5s)
            shrinkTime = 8,        -- 8 second shrink (GDD: 8s)
            endRadius = 0,         -- Complete close (GDD: 0)
            damage = 16,           -- 16 damage per tick (GDD: 16)
            centerOffset = 0,
        },
    },
}

--=============================================================================
-- DINOSAUR CONFIGURATION
-- AI behavior, spawning, and base stats
-- Note: Detailed definitions are in DinoService
--=============================================================================

GameConfig.Dinosaurs = {
    enabled = true,
    maxActive = 50,                -- Max dinosaurs at once (increased for more action)
    spawnInterval = 15,            -- Seconds between spawn waves (faster spawning)
    aggressionRadius = 30,         -- Distance to detect players (reduced for tighter engagement)
    deaggroRadius = 50,            -- Distance to lose aggro (reduced to match aggro)
    pathfindingTimeout = 5,        -- Max seconds for pathfinding

    -- AI update rate
    aiUpdateRate = 0.2,            -- Seconds between AI ticks

    -- Base dinosaur types (full definitions in DinoService)
    types = {
        raptor = {
            name = "Raptor",
            health = 150,
            speed = 28,
            damage = 20,
            attackRange = 6,
            attackCooldown = 1.5,
            spawnWeight = 40,
            packSize = {min = 2, max = 4},
            behavior = "pack_hunter",
        },
        trex = {
            name = "T-Rex",
            health = 800,
            speed = 18,
            damage = 60,
            attackRange = 12,
            attackCooldown = 2.5,
            spawnWeight = 10,
            packSize = {min = 1, max = 1},
            behavior = "solo_predator",
        },
        pteranodon = {
            name = "Pteranodon",
            health = 100,
            speed = 35,
            damage = 15,
            attackRange = 8,
            attackCooldown = 2,
            spawnWeight = 25,
            packSize = {min = 1, max = 3},
            behavior = "aerial_diver",
            isFlying = true,
        },
        triceratops = {
            name = "Triceratops",
            health = 500,
            speed = 15,
            damage = 40,
            attackRange = 10,
            attackCooldown = 3,
            spawnWeight = 15,
            packSize = {min = 1, max = 2},
            behavior = "defensive_charger",
        },
        dilophosaurus = {
            name = "Dilophosaurus",
            health = 120,
            speed = 22,
            damage = 25,
            attackRange = 20,
            attackCooldown = 2,
            spawnWeight = 20,
            packSize = {min = 1, max = 2},
            behavior = "ranged_spitter",
            hasRangedAttack = true,
        },
        carnotaurus = {
            name = "Carnotaurus",
            health = 300,
            speed = 30,
            damage = 45,
            attackRange = 8,
            attackCooldown = 2,
            spawnWeight = 12,
            packSize = {min = 1, max = 1},
            behavior = "ambush_predator",
        },
        compy = {
            name = "Compsognathus",
            health = 25,
            speed = 32,
            damage = 8,
            attackRange = 3,
            attackCooldown = 0.8,
            spawnWeight = 18,
            packSize = {min = 5, max = 10},
            behavior = "swarm",
        },
        spinosaurus = {
            name = "Spinosaurus",
            health = 650,
            speed = 20,
            damage = 55,
            attackRange = 14,
            attackCooldown = 2.2,
            spawnWeight = 8,
            packSize = {min = 1, max = 1},
            behavior = "solo_predator",
        },
    },

    -- Boss spawn settings
    bossSpawnChance = 0.05,        -- 5% chance per wave in late game
    bossMinPhase = 3,              -- Minimum storm phase for boss spawns

    -- Spawn scaling based on storm phase
    spawnScaling = {
        [1] = 0.5,                 -- Phase 1: 50% spawn rate
        [2] = 0.75,                -- Phase 2: 75% spawn rate
        [3] = 1.0,                 -- Phase 3: 100% spawn rate
        [4] = 1.25,                -- Phase 4: 125% spawn rate
        [5] = 1.5,                 -- Phase 5: 150% spawn rate (chaos!)
    },
}

--=============================================================================
-- WEAPON CONFIGURATION
-- Categories, slots, and damage mechanics
-- Note: Full weapon definitions are in WeaponService
--=============================================================================

GameConfig.Weapons = {
    -- Weapon category assignments
    categories = {
        assault_rifle = {slot = 1, ammoType = "medium"},
        smg = {slot = 2, ammoType = "light"},
        shotgun = {slot = 3, ammoType = "shells"},
        sniper = {slot = 4, ammoType = "heavy"},
        pistol = {slot = 5, ammoType = "light"},
        melee = {slot = 6, ammoType = "none"},
        explosive = {slot = 7, ammoType = "rockets"},
        throwable = {slot = 8, ammoType = "none"},
        trap = {slot = 9, ammoType = "none"},
    },

    -- Damage multipliers for hit locations
    damageMultipliers = {
        headshot = 2.0,
        bodyshot = 1.0,
        legshot = 0.75,
        armorReduction = 0.5,
    },

    -- Melee combat settings
    melee = {
        backstabAngle = 90,        -- Degrees behind target for backstab
        backstabMultiplier = 2.0,  -- Base backstab damage bonus
    },

    -- Explosive settings
    explosives = {
        friendlyFireEnabled = false,
        selfDamageMultiplier = 0.5,
        environmentalDamage = true,
    },

    -- Trap settings
    traps = {
        maxPerPlayer = 5,
        showIndicatorToOwner = true,
        despawnOnOwnerDeath = false,
    },

    -- Attachment bonuses (multiplied with base stats)
    attachments = {
        scopes = {
            redDot = {adsSpeed = 1.1},
            scope2x = {adsSpeed = 0.95, zoomLevel = 2},
            scope4x = {adsSpeed = 0.85, zoomLevel = 4},
            scope8x = {adsSpeed = 0.75, zoomLevel = 8},
            thermal = {adsSpeed = 0.7, zoomLevel = 4, thermalVision = true},
        },
        grips = {
            vertical = {recoil = 0.85, stability = 1.15},
            angled = {adsSpeed = 1.1, recoil = 0.95},
            stabilizer = {stability = 1.25, moveSpeed = 0.95},
        },
        magazines = {
            extended = {magSize = 1.5, reloadSpeed = 0.9},
            quickdraw = {reloadSpeed = 1.3, adsSpeed = 1.1},
        },
        muzzles = {
            lightSuppressor = {sound = 0.5, range = 0.95},
            heavySuppressor = {sound = 0.2, range = 0.85, damage = 0.95},
            compensator = {recoil = 0.8},
        },
    },
}

--=============================================================================
-- MAP CONFIGURATION
-- Biomes, POIs, and environmental systems
-- Note: Full definitions are in MapService
--=============================================================================

GameConfig.Map = {
    -- Map dimensions
    size = 1000,                   -- Total map size (studs)
    gridSize = 100,                -- Grid cell size for chunking

    -- Biome settings
    biomes = {
        jungle = {
            name = "Dense Jungle",
            spawnWeight = 25,
            fogDensity = 0.3,
            dinoMultiplier = 1.2,
        },
        volcanic = {
            name = "Volcanic Wastes",
            spawnWeight = 15,
            hazards = {"lava_pool", "eruption"},
            dinoMultiplier = 0.8,
        },
        swamp = {
            name = "Murky Swamp",
            spawnWeight = 20,
            movementPenalty = 0.8,
            fogDensity = 0.5,
        },
        facility = {
            name = "Research Facility",
            spawnWeight = 15,
            lootMultiplier = 1.5,
            indoors = true,
        },
        plains = {
            name = "Open Plains",
            spawnWeight = 15,
            visibilityBonus = 1.5,
            coverScarce = true,
        },
        coastal = {
            name = "Coastal Cliffs",
            spawnWeight = 10,
            hasWater = true,
            pteranodonSpawnBonus = 2.0,
        },
    },

    -- Major POI loot tiers
    poiLootTiers = {
        visitor_center = "epic",
        raptor_paddock = "rare",
        trex_kingdom = "legendary",
        genetics_lab = "epic",
        aviary = "rare",
        docks = "uncommon",
        communications = "rare",
        power_station = "uncommon",
    },

    -- POI definitions for map generation
    POIs = {
        visitor_center = {
            position = Vector3.new(0, 0, 200),
            size = 120,
            lootTier = "epic",
        },
        raptor_paddock = {
            position = Vector3.new(-300, 0, 100),
            size = 80,
            lootTier = "rare",
        },
        trex_kingdom = {
            position = Vector3.new(300, 0, -100),
            size = 100,
            lootTier = "legendary",
        },
        genetics_lab = {
            position = Vector3.new(-200, 0, -250),
            size = 90,
            lootTier = "epic",
        },
        aviary = {
            position = Vector3.new(200, 0, 250),
            size = 70,
            lootTier = "rare",
        },
        docks = {
            position = Vector3.new(-400, 0, -50),
            size = 60,
            lootTier = "uncommon",
        },
        communications = {
            position = Vector3.new(400, 0, 50),
            size = 50,
            lootTier = "rare",
        },
        power_station = {
            position = Vector3.new(0, 0, -350),
            size = 70,
            lootTier = "uncommon",
        },
    },

    -- Environmental events
    events = {
        volcanic_eruption = {
            duration = 30,
            damage = 15,
            warningTime = 5,
            cooldown = 120,
        },
        stampede = {
            duration = 20,
            dinoCount = 8,
            damage = 50,
            cooldown = 90,
        },
        meteor_shower = {
            duration = 15,
            meteorCount = 10,
            damage = 75,
            cooldown = 180,
        },
        toxic_gas = {
            duration = 25,
            damagePerSecond = 5,
            slowAmount = 0.6,
            cooldown = 100,
        },
        supply_drop = {
            lootTier = "legendary",
            dropTime = 15,
            cooldown = 60,
        },
        alpha_spawn = {
            bossTypes = {"alpha_rex", "alpha_raptor", "alpha_spino"},
            cooldown = 300,
        },
    },
}

--=============================================================================
-- LOOT CONFIGURATION
-- Spawn rates, rarity weights, and distribution
--=============================================================================

GameConfig.Loot = {
    -- Density presets
    density = "high",              -- low, medium, high
    densityMultipliers = {
        low = 0.5,
        medium = 1.0,
        high = 1.5,
    },

    -- Chest behavior
    chestRespawn = false,          -- Chests don't respawn
    groundLootDespawn = 120,       -- Seconds before ground loot despawns

    -- Rarity weights (higher = more common)
    rarityWeights = {
        common = 45,
        uncommon = 30,
        rare = 15,
        epic = 7,
        legendary = 3,
    },

    -- Rarity stat multipliers
    rarityMultipliers = {
        common = 1.0,
        uncommon = 1.1,
        rare = 1.2,
        epic = 1.35,
        legendary = 1.5,
    },

    -- Rarity colors for UI
    rarityColors = {
        common = Color3.fromRGB(180, 180, 180),
        uncommon = Color3.fromRGB(30, 255, 30),
        rare = Color3.fromRGB(30, 144, 255),
        epic = Color3.fromRGB(163, 53, 238),
        legendary = Color3.fromRGB(255, 165, 0),
    },

    -- Ammo spawn amounts per pickup
    ammoSpawnAmounts = {
        light = {min = 15, max = 30},
        medium = {min = 20, max = 40},
        heavy = {min = 5, max = 15},
        shells = {min = 6, max = 12},
        rockets = {min = 1, max = 3},
    },

    -- Healing item values
    healingValues = {
        bandage = 15,
        medkit = 50,
        healthKit = 100,
        miniShield = 25,
        shield = 50,
        bigShield = 100,
    },

    -- Healing item use times (GDD compliant)
    -- Time in seconds to channel/use the item before it takes effect
    healingUseTimes = {
        bandage = 2,        -- 2s
        medkit = 5,         -- 5s
        healthKit = 7,      -- 7s (called "Health Kit" in GDD)
        miniShield = 2,     -- 2s (called "Mini Shield" in GDD)
        shield = 4,         -- 4s (called "Shield Potion" in GDD)
        bigShield = 6,      -- 6s (called "Big Shield" in GDD)
    },
}

--=============================================================================
-- PLAYER CONFIGURATION
-- Health, inventory, movement, and interaction
--=============================================================================

GameConfig.Player = {
    -- Health & Shield
    maxHealth = 100,
    maxShield = 100,
    startingHealth = 100,
    startingShield = 0,
    shieldRegenDelay = 5,          -- Seconds before shield regen
    shieldRegenRate = 5,           -- Shield per second

    -- Inventory
    inventorySlots = 5,
    maxStackSize = {
        ammo = 999,
        consumable = 10,
        throwable = 6,
        trap = 5,
    },

    -- Interaction
    pickupRange = 8,
    interactKey = Enum.KeyCode.E,
    autoPickup = false,

    -- Movement
    walkSpeed = 16,
    sprintSpeed = 24,
    crouchSpeed = 8,
    swimSpeed = 12,

    -- Combat
    respawnTime = 0,               -- No respawns in BR
    invincibilityTime = 3,         -- After spawn/revive
}

--=============================================================================
-- UI CONFIGURATION
-- HUD elements and display settings
--=============================================================================

GameConfig.UI = {
    -- HUD toggles
    hudEnabled = true,
    minimapEnabled = true,
    compassEnabled = true,

    -- Minimap settings
    minimapSize = 200,
    minimapZoom = 1.5,
    minimapRotates = true,

    -- Damage indicators
    damageIndicatorDuration = 1,
    showDamageNumbers = true,
    damageNumberFont = Enum.Font.GothamBold,

    -- Kill feed
    killFeedMaxItems = 5,
    killFeedItemDuration = 5,
    killFeedPosition = "TopRight",

    -- Inventory
    inventoryHotbarSize = 5,
    showAmmoCount = true,
    showWeaponRarity = true,

    -- Storm
    showStormTimer = true,
    showStormDistance = true,
    stormWarningFlash = true,

    -- Dinosaur indicators
    showDinoHealthBars = true,
    showDinoNames = true,
    bossHealthBarSize = "Large",
}

--=============================================================================
-- AUDIO CONFIGURATION
-- Volume levels and sound settings
--=============================================================================

GameConfig.Audio = {
    -- Volume levels (0-1)
    masterVolume = 1.0,
    musicVolume = 0.5,
    sfxVolume = 0.8,
    voiceVolume = 1.0,
    stormVolume = 0.6,
    dinoVolume = 0.9,
    ambientVolume = 0.4,

    -- 3D audio settings
    maxAudioDistance = 200,
    rolloffScale = 1.0,

    -- Music settings
    lobbyMusic = true,
    battleMusic = true,
    victoryMusic = true,
    bossMusic = true,
}

--=============================================================================
-- DEBUG CONFIGURATION
-- Development and testing tools
--=============================================================================

GameConfig.Debug = {
    enabled = true,                -- Master debug toggle

    -- Visual debugging
    showHitboxes = false,
    showPathfinding = false,
    showStormRadius = true,
    showSpawnPoints = false,
    showBiomeBoundaries = false,
    showDamageZones = false,

    -- Logging
    logNetworkEvents = false,
    logAIDecisions = false,
    logLootSpawns = false,
    logDamageCalcs = false,

    -- Cheats (dev only)
    godMode = false,
    infiniteAmmo = false,
    noDinosaurs = false,
    noStorm = false,
    instantKill = false,
    spawnAllWeapons = false,
}

--=============================================================================
-- TEST MODE CONFIGURATION
-- Single-player testing settings
--=============================================================================

GameConfig.TestMode = {
    enabled = true,                -- Enable test mode (set to false for production)

    -- Match overrides
    minPlayersToStart = 1,         -- Allow single-player start
    autoStartDelay = 3,            -- Seconds before auto-starting match
    skipLobbyCountdown = true,     -- Skip the normal lobby countdown

    -- Gameplay overrides
    reducedStormSpeed = true,      -- Slower storm for exploration
    stormSpeedMultiplier = 0.25,   -- 25% of normal storm speed
    startingWeapons = true,        -- Give player weapons on spawn
    startingHealth = 100,          -- Starting health (can increase for testing)
    startingShield = 50,           -- Starting shield

    -- Dinosaur testing
    spawnDinosImmediately = false, -- Spawn dinos right away (not waiting for match phase)
    reducedDinoCount = true,       -- Fewer dinosaurs for performance
    dinoCountMultiplier = 0.25,    -- 25% of normal dino count

    -- Debug helpers
    teleportCommands = true,       -- Allow /tp commands in chat
    spawnCommands = true,          -- Allow /spawn commands in chat
    showTestHUD = true,            -- Show extra debug info on HUD
}

return GameConfig
