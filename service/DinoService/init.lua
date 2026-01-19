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
-- DINOSAUR DEFINITIONS
-- Comprehensive stats and abilities for each dinosaur type
--=============================================================================

local DINOSAUR_DEFINITIONS = {
    --=========================================================================
    -- RAPTOR - Pack Hunter
    -- Fast, agile pack hunters that coordinate flanking attacks
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

        -- Visual settings
        modelSize = Vector3.new(2, 3, 5),
        color = Color3.fromRGB(50, 80, 50),

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

        -- Visual settings
        modelSize = Vector3.new(8, 10, 20),
        color = Color3.fromRGB(60, 40, 30),

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

        -- Visual settings
        modelSize = Vector3.new(6, 1, 3),
        color = Color3.fromRGB(80, 60, 40),

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

        -- Visual settings
        modelSize = Vector3.new(6, 5, 12),
        color = Color3.fromRGB(100, 90, 70),

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

        -- Visual settings
        modelSize = Vector3.new(2, 4, 6),
        color = Color3.fromRGB(40, 80, 60),

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
    -- CARNOTAURUS - Ambush Predator (NEW)
    -- Camouflaged hunter that ambushes prey
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

        -- Visual settings
        modelSize = Vector3.new(4, 5, 10),
        color = Color3.fromRGB(80, 50, 40),

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
    -- COMPSOGNATHUS - Swarm (NEW)
    -- Tiny dinosaurs that attack in overwhelming numbers
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

        -- Visual settings
        modelSize = Vector3.new(0.5, 0.8, 1.5),
        color = Color3.fromRGB(60, 70, 50),

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
    -- SPINOSAURUS - Apex Predator (NEW)
    -- Large semi-aquatic predator with tail attacks
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

        -- Visual settings
        modelSize = Vector3.new(6, 8, 18),
        color = Color3.fromRGB(70, 60, 50),

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
}

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
    framework = require(script.Parent.Parent.framework)
    gameConfig = require(script.Parent.Parent.src.shared.GameConfig)

    -- Try to get MapService for spawn points
    mapService = framework:GetService("MapService")

    -- Load spawn points from map or MapService
    self:LoadSpawnPoints()

    -- Setup network remotes
    self:SetupRemotes()

    framework.Log("Info", "DinoService initialized with %d spawn points", #spawnPoints)
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
            framework.Log("Info", "Loaded %d spawn points from MapService", #spawnPoints)
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
            table.insert(spawnPoints, Vector3.new(x, 5, z))
        end
        framework.Log("Warn", "No spawn points found, generated %d defaults", #spawnPoints)
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
        framework.Log("Warn", "DinoService already spawning")
        return
    end

    isSpawning = true
    framework.Log("Info", "Starting dinosaur spawning")

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
            self:UpdateAllAI()
            task.wait(AI_UPDATE_RATE)
        end
    end)
end

--[[
    Stop the dinosaur spawning system
]]
function DinoService:StopSpawning()
    isSpawning = false
    framework.Log("Info", "Stopped dinosaur spawning")
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

    framework.Log("Debug", "Spawning wave: %d dinosaurs (current: %d, max: %d)",
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
        framework.Log("Error", "Unknown dinosaur type: %s", dinoType)
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

    framework.Log("Debug", "Spawned %s at %s", def.name, tostring(position))

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
    model:SetPrimaryPartCFrame(CFrame.new(position))

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

    @param dinoType string - Type of dinosaur
    @param def table - Dinosaur definition
    @return Model - The placeholder model
]]
function DinoService:CreatePlaceholderModel(dinoType, def)
    local model = Instance.new("Model")
    model.Name = dinoType

    -- Create body part
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Anchored = false
    body.CanCollide = true
    body.Size = def.modelSize or Vector3.new(4, 3, 8)
    body.Color = def.color or Color3.fromRGB(100, 100, 100)
    body.Parent = model
    model.PrimaryPart = body

    -- Add humanoid for pathfinding
    local humanoid = Instance.new("Humanoid")
    humanoid.MaxHealth = def.health
    humanoid.Health = def.health
    humanoid.WalkSpeed = def.speed
    humanoid.Parent = model

    -- Create root part
    local rootPart = Instance.new("Part")
    rootPart.Name = "HumanoidRootPart"
    rootPart.Transparency = 1
    rootPart.CanCollide = false
    rootPart.Size = Vector3.new(2, 2, 1)
    rootPart.Parent = model

    -- Weld body to root
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = rootPart
    weld.Part1 = body
    weld.Parent = model

    return model
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

    -- Broadcast state change for animations
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes and remotes:FindFirstChild("DinoStateChanged") then
        remotes.DinoStateChanged:FireAllClients({
            dinoId = dino.id,
            state = newState,
            previousState = dino.previousState,
        })
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

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChild("Humanoid")

            if rootPart and humanoid and humanoid.Health > 0 then
                local distance = (rootPart.Position - dinoPos).Magnitude

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

    -- Broadcast attack
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes and remotes:FindFirstChild("DinoAttack") then
        remotes.DinoAttack:FireAllClients({
            dinoId = dino.id,
            targetId = dino.target.UserId,
            damage = damage,
            attackType = "melee",
        })
    end

    framework.Log("Debug", "%s attacked %s for %d damage",
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

    -- Broadcast damage
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

    framework.Log("Info", "%s killed by %s", dino.name, killer and killer.Name or "unknown")

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

    -- Remove model after delay
    if dino.model then
        task.delay(5, function()
            if dino.model then
                dino.model:Destroy()
            end
        end)
    end

    -- Remove from active list
    activeDinosaurs[dinoId] = nil
end

--[[
    Spawn loot from a killed dinosaur

    @param dino table - Dinosaur data
    @param killer Player|nil - Player who killed the dinosaur
]]
function DinoService:SpawnDinoLoot(dino, killer)
    local def = dino.config
    local lootTable = def.lootTable

    if not lootTable then
        return
    end

    local position = self:GetDinoPosition(dino)
    if not position then
        return
    end

    -- Get LootSystem if available
    local lootSystem = framework:GetService("LootSystem")

    for _, lootEntry in ipairs(lootTable) do
        if math.random() <= lootEntry.chance then
            if lootSystem and lootSystem.SpawnLootItem then
                -- Use LootSystem for proper loot spawning
                local count = 1
                if lootEntry.count then
                    count = math.random(lootEntry.count[1], lootEntry.count[2])
                end

                lootSystem:SpawnLootItem(lootEntry.item, position, {
                    rarity = lootEntry.rarity,
                    count = count,
                })
            else
                -- Fallback: Log what would be spawned
                framework.Log("Debug", "Loot drop: %s at %s", lootEntry.item, tostring(position))
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
                    framework.Log("Debug", "%s feared %s with roar", dino.name, player.Name)
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

    framework.Log("Debug", "%s charged %s for %d damage", dino.name, dino.target.Name, damage)

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

    framework.Log("Debug", "%s pounced on %s for %d damage", dino.name, dino.target.Name, damage)

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

    framework.Log("Debug", "%s spit venom at %s", dino.name, dino.target.Name)

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

    framework.Log("Debug", "%s tail swipe hit %d players", dino.name, hitCount)

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

    framework.Log("Debug", "%s dive bombed %s for %d damage", dino.name, dino.target.Name, damage)

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

    framework.Log("Debug", "%s activated camouflage", dino.name)

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

    framework.Log("Debug", "%s ground pound hit %d players", dino.name, hitCount)

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
        framework.Log("Error", "Unknown boss type: %s", bossType)
        return nil
    end

    local baseDef = DINOSAUR_DEFINITIONS[bossDef.baseDino]
    if not baseDef then
        framework.Log("Error", "Unknown base dinosaur for boss: %s", bossDef.baseDino)
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

    framework.Log("Info", "Boss spawned: %s at %s", bossDef.name, tostring(position))

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

    framework.Log("Info", "Boss %s entered phase %d", boss.name, newPhase)
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
    framework.Log("Info", "Despawning all dinosaurs")

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
    framework.Log("Info", "DinoService shut down")
end

--=============================================================================
-- EXTERNAL ACCESS
--=============================================================================

-- Store definitions for external access
DinoService.DINOSAUR_DEFINITIONS = DINOSAUR_DEFINITIONS
DinoService.BOSS_DEFINITIONS = BOSS_DEFINITIONS

return DinoService
