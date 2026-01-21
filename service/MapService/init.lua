--[[
    ================================================================================
    MapService - Map Generation, Biomes, POIs, and Dynamic Environmental Events
    ================================================================================

    This service manages the game world including:
    - Biome system with distinct regions (Jungle, Volcanic, Swamp, Research Facility, etc.)
    - Points of Interest (POIs) with named locations and landmarks
    - Dynamic environmental events (volcanic eruptions, stampedes, meteor showers)
    - Terrain generation and decoration
    - Map boundaries and spawn point management

    Architecture:
    - Server-authoritative map state
    - Client receives map data for minimap/UI rendering
    - Events are triggered based on storm phase and random timers

    Dependencies:
    - Framework (service locator)
    - GameConfig (map configuration)
    - StormService (for event coordination)

    Usage:
        local MapService = Framework:GetService("MapService")
        MapService:GenerateMap()
        MapService:StartEnvironmentalEvents()

    Author: Dino Royale 2 Development Team
    Version: 1.0.0
    Last Updated: 2024
    ================================================================================
]]

--==============================================================================
-- SERVICES
--==============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

--==============================================================================
-- MODULE DEFINITION
--==============================================================================
local MapService = {}
MapService.__index = MapService

--==============================================================================
-- PRIVATE STATE
--==============================================================================
local isInitialized = false          -- Whether the service has been initialized
local mapData = nil                  -- Current map configuration
local activeBiomes = {}              -- Currently active biome instances
local activePOIs = {}                -- Currently active POI instances
local activeEvents = {}              -- Currently running environmental events
local spawnPoints = {                -- Player and dinosaur spawn locations
    player = {},
    dinosaur = {},
    loot = {},
}
local eventLoopRunning = false       -- Whether the event loop is active
local framework = nil                -- Framework reference
local gameConfig = nil               -- Game configuration reference

--==============================================================================
-- CONSTANTS
--==============================================================================

-- Map dimensions (studs)
local MAP_SIZE = 2000                -- Total map width/length
local MAP_CENTER = Vector3.new(0, 0, 0)

-- Biome definitions with visual and gameplay properties
local BIOME_DEFINITIONS = {
    --[[
        Dense Jungle Biome
        - Heavy vegetation, limited visibility
        - Perfect for ambush tactics
        - Higher raptor spawn rates
    ]]
    jungle = {
        name = "Dense Jungle",
        description = "Thick vegetation provides cover but limits visibility",
        color = Color3.fromRGB(34, 139, 34),           -- Forest green
        fogColor = Color3.fromRGB(50, 80, 50),         -- Greenish fog
        fogDensity = 0.02,                              -- Medium fog
        ambientColor = Color3.fromRGB(100, 120, 100),  -- Green-tinted ambient
        groundMaterial = Enum.Material.Grass,
        vegetationDensity = 0.8,                        -- 80% vegetation coverage
        dinoSpawnModifier = {                           -- Dinosaur spawn weights
            raptor = 1.5,        -- More raptors in jungle
            dilophosaurus = 1.3, -- Dilos like jungle cover
            trex = 0.5,          -- T-Rex avoids dense areas
        },
        lootModifier = 0.9,      -- Slightly less loot (harder to find)
        coverAmount = 0.7,       -- Lots of natural cover
    },

    --[[
        Volcanic Region Biome
        - Dangerous terrain with lava pools
        - Environmental hazards (eruptions)
        - High-tier loot spawns
    ]]
    volcanic = {
        name = "Volcanic Wastes",
        description = "Scorched earth with lava pools and valuable resources",
        color = Color3.fromRGB(139, 69, 19),           -- Saddle brown/burnt
        fogColor = Color3.fromRGB(100, 50, 30),        -- Smoky orange
        fogDensity = 0.03,                              -- Thick volcanic haze
        ambientColor = Color3.fromRGB(150, 100, 80),   -- Warm ambient
        groundMaterial = Enum.Material.CrackedLava,
        vegetationDensity = 0.1,                        -- Sparse vegetation
        dinoSpawnModifier = {
            trex = 1.5,          -- T-Rex thrives here
            pteranodon = 1.3,    -- Pteranodons roost on peaks
            raptor = 0.7,        -- Raptors avoid open terrain
        },
        lootModifier = 1.3,      -- Better loot (risk/reward)
        coverAmount = 0.2,       -- Little cover
        hazards = {"lava_pool", "eruption", "toxic_gas"},
    },

    --[[
        Swampland Biome
        - Water hazards slow movement
        - Foggy conditions
        - Aquatic dinosaurs prevalent
    ]]
    swamp = {
        name = "Murky Swamplands",
        description = "Treacherous marshes slow movement and hide dangers",
        color = Color3.fromRGB(85, 107, 47),           -- Dark olive green
        fogColor = Color3.fromRGB(70, 80, 60),         -- Murky fog
        fogDensity = 0.04,                              -- Heavy fog
        ambientColor = Color3.fromRGB(80, 90, 70),     -- Dim ambient
        groundMaterial = Enum.Material.Mud,
        vegetationDensity = 0.5,                        -- Moderate vegetation
        dinoSpawnModifier = {
            dilophosaurus = 1.5, -- Dilos love swamps
            raptor = 1.2,        -- Raptors hunt here
            triceratops = 0.5,   -- Trikes avoid water
        },
        lootModifier = 1.0,      -- Standard loot
        coverAmount = 0.5,       -- Medium cover
        movementPenalty = 0.7,   -- 30% slower movement
        waterLevel = 5,          -- Water height in studs
    },

    --[[
        Research Facility Biome
        - Abandoned structures
        - High loot concentration
        - Indoor/outdoor combat
    ]]
    facility = {
        name = "Abandoned Research Facility",
        description = "Ruins of InGen research labs hold powerful equipment",
        color = Color3.fromRGB(128, 128, 128),         -- Gray concrete
        fogColor = Color3.fromRGB(100, 100, 110),      -- Industrial haze
        fogDensity = 0.01,                              -- Light fog
        ambientColor = Color3.fromRGB(120, 120, 130),  -- Cool ambient
        groundMaterial = Enum.Material.Concrete,
        vegetationDensity = 0.2,                        -- Overgrown areas
        dinoSpawnModifier = {
            raptor = 1.8,        -- Raptors nest in facilities
            trex = 0.3,          -- T-Rex can't fit inside
            dilophosaurus = 1.2, -- Dilos lurk in shadows
        },
        lootModifier = 1.5,      -- Best loot density
        coverAmount = 0.8,       -- Lots of structural cover
        hasBuildings = true,
    },

    --[[
        Open Plains Biome
        - Wide open areas
        - Good visibility
        - Vehicle-friendly terrain
    ]]
    plains = {
        name = "Prehistoric Plains",
        description = "Open grasslands with scattered rock formations",
        color = Color3.fromRGB(154, 205, 50),          -- Yellow green
        fogColor = Color3.fromRGB(180, 200, 180),      -- Light haze
        fogDensity = 0.005,                             -- Minimal fog
        ambientColor = Color3.fromRGB(140, 140, 120),  -- Neutral ambient
        groundMaterial = Enum.Material.Grass,
        vegetationDensity = 0.3,                        -- Light vegetation
        dinoSpawnModifier = {
            triceratops = 1.5,   -- Trikes roam plains
            trex = 1.2,          -- T-Rex hunts here
            pteranodon = 1.4,    -- Good flying conditions
        },
        lootModifier = 0.8,      -- Less concentrated loot
        coverAmount = 0.2,       -- Exposed terrain
    },

    --[[
        Coastal Beach Biome
        - Water boundary areas
        - Pteranodon nesting grounds
        - Ship wreckage POIs
    ]]
    coastal = {
        name = "Coastal Shores",
        description = "Sandy beaches and rocky cliffs at the island's edge",
        color = Color3.fromRGB(238, 214, 175),         -- Sand color
        fogColor = Color3.fromRGB(200, 220, 240),      -- Ocean mist
        fogDensity = 0.015,                             -- Sea fog
        ambientColor = Color3.fromRGB(160, 170, 180),  -- Coastal lighting
        groundMaterial = Enum.Material.Sand,
        vegetationDensity = 0.25,                       -- Palm trees, sparse
        dinoSpawnModifier = {
            pteranodon = 2.0,    -- Pteranodon nesting grounds
            raptor = 0.8,        -- Raptors hunt the beach
            trex = 0.6,          -- T-Rex occasionally visits
        },
        lootModifier = 1.1,      -- Ship wreckage has good loot
        coverAmount = 0.3,       -- Rock formations
        waterBorder = true,
    },
}

-- Point of Interest definitions
local POI_DEFINITIONS = {
    --[[
        Named Locations - Major POIs
        These appear on the map with names and are primary destinations
    ]]

    -- Visitor Center (center of map, major landmark)
    visitor_center = {
        name = "Visitor Center",
        type = "major",
        description = "The iconic entrance to the park - high loot, high risk",
        biome = "facility",
        size = Vector3.new(150, 50, 150),
        lootTier = "epic",
        lootDensity = 2.0,       -- Double normal loot
        chestCount = 8,
        dinoSpawns = 3,
        landmarks = {"main_hall", "gift_shop", "dining_area"},
        preferredPosition = "center",
    },

    -- Raptor Paddock (jungle area)
    raptor_paddock = {
        name = "Raptor Paddock",
        type = "major",
        description = "Containment facility for velociraptors - now overrun",
        biome = "jungle",
        size = Vector3.new(120, 30, 120),
        lootTier = "rare",
        lootDensity = 1.5,
        chestCount = 5,
        dinoSpawns = 6,          -- Lots of raptors here
        dinoOverride = "raptor", -- Only raptors spawn
        landmarks = {"feeding_pen", "observation_tower"},
    },

    -- T-Rex Kingdom (volcanic border)
    trex_kingdom = {
        name = "T-Rex Kingdom",
        type = "major",
        description = "Former paddock of the island's apex predator",
        biome = "plains",
        size = Vector3.new(200, 40, 200),
        lootTier = "legendary",
        lootDensity = 1.8,
        chestCount = 6,
        dinoSpawns = 2,
        dinoOverride = "trex",   -- T-Rex territory
        landmarks = {"viewing_platform", "feeding_crane"},
    },

    -- Genetics Lab (facility)
    genetics_lab = {
        name = "Genetics Laboratory",
        type = "major",
        description = "Where the dinosaurs were created - contains experimental tech",
        biome = "facility",
        size = Vector3.new(100, 40, 80),
        lootTier = "legendary",
        lootDensity = 2.5,
        chestCount = 10,
        dinoSpawns = 2,
        landmarks = {"embryo_storage", "amber_collection", "server_room"},
        hasSpecialLoot = true,   -- Can spawn legendary weapons
    },

    -- Pteranodon Aviary (coastal)
    pteranodon_aviary = {
        name = "Pteranodon Aviary",
        type = "major",
        description = "Massive dome structure for flying reptiles",
        biome = "coastal",
        size = Vector3.new(180, 100, 180),
        lootTier = "epic",
        lootDensity = 1.4,
        chestCount = 7,
        dinoSpawns = 5,
        dinoOverride = "pteranodon",
        landmarks = {"central_spire", "nesting_platforms"},
    },

    -- Dock (coastal)
    main_dock = {
        name = "Main Dock",
        type = "major",
        description = "Supply arrival point with cargo containers",
        biome = "coastal",
        size = Vector3.new(150, 20, 100),
        lootTier = "rare",
        lootDensity = 1.6,
        chestCount = 8,
        dinoSpawns = 2,
        landmarks = {"cargo_ship", "warehouse", "crane"},
    },

    -- Volcano Peak (volcanic)
    volcano_peak = {
        name = "Volcano Summit",
        type = "major",
        description = "Dangerous peak with the best loot - eruption risk!",
        biome = "volcanic",
        size = Vector3.new(100, 150, 100),
        lootTier = "legendary",
        lootDensity = 3.0,
        chestCount = 4,
        dinoSpawns = 1,
        hazardZone = true,       -- Eruptions target this area
        landmarks = {"crater", "lava_pools"},
    },

    -- Swamp Outpost (swamp)
    swamp_outpost = {
        name = "Swamp Research Outpost",
        type = "major",
        description = "Partially submerged research station",
        biome = "swamp",
        size = Vector3.new(80, 25, 80),
        lootTier = "rare",
        lootDensity = 1.3,
        chestCount = 4,
        dinoSpawns = 4,
        landmarks = {"radio_tower", "supply_depot"},
    },

    --[[
        Minor POIs - Smaller locations with some loot
    ]]

    -- Scattered around the map
    ranger_station = {
        name = "Ranger Station",
        type = "minor",
        description = "Small outpost with basic supplies",
        size = Vector3.new(30, 15, 30),
        lootTier = "uncommon",
        lootDensity = 1.0,
        chestCount = 2,
        count = 5,               -- 5 scattered around map
    },

    emergency_bunker = {
        name = "Emergency Bunker",
        type = "minor",
        description = "Underground shelter with emergency supplies",
        size = Vector3.new(20, 10, 20),
        lootTier = "rare",
        lootDensity = 1.5,
        chestCount = 3,
        count = 3,
        underground = true,
    },

    crashed_helicopter = {
        name = "Crashed Helicopter",
        type = "minor",
        description = "Downed rescue helicopter with survivor gear",
        size = Vector3.new(15, 8, 25),
        lootTier = "epic",
        lootDensity = 1.2,
        chestCount = 2,
        count = 2,
    },

    supply_cache = {
        name = "Supply Cache",
        type = "minor",
        description = "Hidden supply container",
        size = Vector3.new(10, 5, 10),
        lootTier = "uncommon",
        lootDensity = 0.8,
        chestCount = 1,
        count = 12,
    },

    --[[
        Missing GDD POIs - Added for compliance
    ]]

    -- Communications Tower (GDD: plains, rare loot, tall structure, sniper spot)
    communications_tower = {
        name = "Communications Tower",
        type = "major",
        description = "Tall radio tower with excellent sightlines - a sniper's paradise",
        biome = "plains",
        size = Vector3.new(60, 120, 60),  -- Tall structure
        lootTier = "rare",
        lootDensity = 1.4,
        chestCount = 4,
        dinoSpawns = 1,
        landmarks = {"antenna_array", "control_room", "observation_deck"},
        sniperSpot = true,  -- Flags this as good sniper location
    },

    -- Power Station (GDD: volcanic, uncommon, industrial, hazards nearby)
    power_station = {
        name = "Power Station",
        type = "major",
        description = "Geothermal power facility - danger from nearby volcanic activity",
        biome = "volcanic",
        size = Vector3.new(100, 40, 80),
        lootTier = "uncommon",
        lootDensity = 1.2,
        chestCount = 5,
        dinoSpawns = 2,
        landmarks = {"turbine_hall", "cooling_towers", "transformer_yard"},
        hazardZone = true,  -- Near volcanic hazards
    },
}

-- Environmental Event Definitions
local EVENT_DEFINITIONS = {
    --[[
        Volcanic Eruption
        - Triggers in volcanic biome
        - Creates danger zones with falling debris
        - Pushes players away from area
    ]]
    volcanic_eruption = {
        name = "Volcanic Eruption",
        type = "hazard",
        description = "The volcano erupts, raining down fiery debris!",
        duration = 30,           -- Seconds
        warningTime = 10,        -- Warning before start
        cooldown = 120,          -- Minimum time between events
        radius = 150,            -- Affected radius
        damage = 15,             -- Damage per hit
        biome = "volcanic",      -- Only triggers in volcanic areas
        visualEffect = "eruption",
        soundEffect = "rumble",
    },

    --[[
        Dinosaur Stampede
        - NPC dinosaurs rush across an area
        - Can damage/knockback players
        - Triggered by loud sounds or explosions
    ]]
    dinosaur_stampede = {
        name = "Dinosaur Stampede",
        type = "chaos",
        description = "A herd of dinosaurs stampedes through the area!",
        duration = 20,
        warningTime = 5,
        cooldown = 90,
        radius = 200,
        damage = 25,             -- Damage if trampled
        knockback = 50,          -- Studs of knockback
        dinoCount = 8,           -- Number of stampeding dinos
        dinoType = "triceratops",
    },

    --[[
        Meteor Shower
        - Random meteors fall across the map
        - Creates temporary craters/cover
        - Late-game chaos event
    ]]
    meteor_shower = {
        name = "Meteor Shower",
        type = "hazard",
        description = "Meteors rain from the sky!",
        duration = 15,           -- GDD specifies 15s (was 45s)
        warningTime = 5,         -- Short warning for urgent chaos
        cooldown = 180,
        radius = 500,            -- Map-wide
        damage = 75,             -- GDD: 75 damage per meteor
        meteorCount = 10,        -- GDD: 10 meteors
        impactRadius = 15,       -- Each meteor's damage radius
        stormPhaseMin = 3,       -- Only in late game
    },

    --[[
        Toxic Gas Release
        - Clouds of gas spread from facility
        - Damage over time in affected area
        - Forces area denial
    ]]
    toxic_gas = {
        name = "Toxic Gas Leak",
        type = "hazard",
        description = "Toxic gas is leaking from the facility!",
        duration = 25,           -- GDD specifies 25s (was 40s)
        warningTime = 8,
        cooldown = 100,
        radius = 80,
        damagePerSecond = 5,
        slowEffect = 0.5,        -- GDD: "DoT + slow" - 50% movement speed reduction
        biome = "facility",
        visualEffect = "green_fog",
    },

    --[[
        Supply Drop
        - Beneficial event
        - High-tier loot crate drops
        - Attracts attention (marked on map)
    ]]
    supply_drop = {
        name = "Supply Drop",
        type = "beneficial",
        description = "An emergency supply crate is dropping nearby!",
        duration = 60,           -- Time before despawn
        warningTime = 15,
        cooldown = 60,
        lootTier = "legendary",
        markedOnMap = true,      -- Visible to all players
        soundEffect = "helicopter",
    },

    --[[
        Alpha Dinosaur Spawn
        - Boss-level dinosaur appears
        - Drops exceptional loot when killed
        - Announced server-wide
    ]]
    alpha_spawn = {
        name = "Alpha Predator",
        type = "boss",
        description = "An alpha predator has emerged!",
        duration = 180,          -- 3 minutes before despawn
        warningTime = 10,
        cooldown = 240,          -- 4 minute cooldown
        dinoType = "trex",       -- Alpha T-Rex
        healthMultiplier = 3.0,
        damageMultiplier = 1.5,
        lootReward = "legendary",
        markedOnMap = true,
        stormPhaseMin = 2,
    },
}

--==============================================================================
-- HELPER FUNCTIONS
--==============================================================================

--[[
    Get terrain height at a position using raycasting

    Casts a ray from above downward to find the ground level at the given X, Z position.
    This ensures assets are properly grounded on the terrain.

    @param x number - X coordinate
    @param z number - Z coordinate
    @return number - Y coordinate of ground level
]]
local function GetTerrainHeight(x, z)
    local terrain = workspace:FindFirstChildOfClass("Terrain")

    -- METHOD 1: Direct raycast against terrain only
    if terrain then
        local rayOrigin = Vector3.new(x, 500, z)
        local rayDirection = Vector3.new(0, -600, 0)

        -- Exclude ALL workspace children except Terrain
        local excludeList = {}
        for _, child in ipairs(workspace:GetChildren()) do
            if child ~= terrain then
                table.insert(excludeList, child)
            end
        end

        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = excludeList
        raycastParams.IgnoreWater = true

        local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
        if result and result.Position then
            return result.Position.Y
        end
    end

    -- METHOD 2: Read terrain voxels directly
    if terrain then
        local success, height = pcall(function()
            -- Sample a column of voxels at this X,Z position
            local minY = -20
            local maxY = 200
            local resolution = 4

            local region = Region3.new(
                Vector3.new(x - resolution, minY, z - resolution),
                Vector3.new(x + resolution, maxY, z + resolution)
            ):ExpandToGrid(resolution)

            local materials = terrain:ReadVoxels(region, resolution)

            if materials and #materials > 0 and #materials[1] > 0 and #materials[1][1] > 0 then
                local midX = math.ceil(#materials / 2)
                local midZ = math.ceil(#materials[1][1] / 2)

                -- Search from top to bottom for first solid voxel
                for y = #materials[1], 1, -1 do
                    local mat = materials[midX][y][midZ]
                    if mat ~= Enum.Material.Air and mat ~= Enum.Material.Water then
                        -- Convert voxel Y index to world Y
                        -- Region starts at minY, each voxel is resolution studs
                        local worldY = minY + (y - 0.5) * resolution
                        return worldY
                    end
                end
            end
            return nil
        end)

        if success and height then
            return height
        end
    end

    -- METHOD 3: Calculate using terrain generation formula
    -- This matches TerrainSetup:GenerateIslandTerrain() exactly
    local islandRadius = 900
    local baseHeight = 5
    local maxTerrainHeight = 50
    local distFromCenter = math.sqrt(x * x + z * z)

    if distFromCenter < islandRadius then
        local normalizedDist = distFromCenter / islandRadius
        local heightFalloff = 1 - (normalizedDist ^ 2)

        -- Same noise parameters as TerrainSetup
        local noise = math.noise(x / 200, z / 200) * 0.5 + 0.5
        local detailNoise = math.noise(x / 50, z / 50) * 0.3

        local calculatedHeight = baseHeight + (noise + detailNoise) * maxTerrainHeight * heightFalloff
        return math.max(baseHeight, calculatedHeight)
    end

    return baseHeight
end

--==============================================================================
-- INITIALIZATION
--==============================================================================

--[[
    Initialize the MapService

    Sets up the service, loads configuration, creates remote events,
    and prepares the map for generation.

    @return boolean - True if initialization successful
]]
function MapService:Initialize()
    -- Get framework reference for logging and service access
    -- Rojo maps to ReplicatedStorage.Framework and ReplicatedStorage.Shared
    framework = require(script.Parent.Parent.Framework)
    gameConfig = require(script.Parent.Parent.Shared.GameConfig)

    -- Initialize map data structure
    mapData = {
        size = MAP_SIZE,
        center = MAP_CENTER,
        biomes = {},
        pois = {},
        spawnPoints = {
            player = {},
            dinosaur = {},
            loot = {},
        },
        hazardZones = {},
    }

    -- Create remote events for client communication
    self:SetupRemotes()

    -- Mark as initialized
    isInitialized = true

    framework.Log("Info", "MapService initialized - Map size: %d studs", MAP_SIZE)
    return true
end

--[[
    Setup remote events for client-server communication

    Creates all necessary RemoteEvents and RemoteFunctions for:
    - Map data synchronization
    - Environmental event notifications
    - POI discovery
]]
function MapService:SetupRemotes()
    -- Get or create Remotes folder
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = "Remotes"
        remoteFolder.Parent = ReplicatedStorage
    end

    -- Define all map-related remote events
    local mapRemotes = {
        "MapDataSync",           -- Send full map data to client
        "BiomeEntered",          -- Player entered a new biome
        "POIDiscovered",         -- Player discovered a POI
        "EnvironmentalEvent",    -- Environmental event started/ended
        "HazardWarning",         -- Hazard zone warning
        "SupplyDropIncoming",    -- Supply drop notification
    }

    -- Create each remote event if it doesn't exist
    for _, remoteName in ipairs(mapRemotes) do
        if not remoteFolder:FindFirstChild(remoteName) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = remoteName
            remote.Parent = remoteFolder
        end
    end

    framework.Log("Debug", "MapService remotes setup complete")
end

--==============================================================================
-- MAP GENERATION
--==============================================================================

--[[
    Generate the game map

    Creates the full map including:
    - Biome placement and terrain
    - POI spawning and configuration
    - Spawn point distribution
    - Hazard zone marking

    @param config table - Optional configuration overrides
    @return boolean - True if generation successful
]]
function MapService:GenerateMap(config)
    if not isInitialized then
        framework.Log("Error", "MapService not initialized")
        return false
    end

    config = config or {}

    framework.Log("Info", "Generating map...")

    -- Step 1: Generate biome layout
    self:GenerateBiomeLayout()

    -- Step 2: Place major POIs
    self:PlacePOIs()

    -- Step 3: Generate spawn points
    self:GenerateSpawnPoints()

    -- Step 4: Create visual terrain
    self:CreateTerrainVisuals()

    -- Step 5: Setup hazard zones
    self:SetupHazardZones()

    -- Sync map data to all clients
    self:SyncMapToClients()

    framework.Log("Info", "Map generation complete - %d biomes, %d POIs",
        #activeBiomes, #activePOIs)

    return true
end

--[[
    Generate the biome layout for the map

    Divides the map into distinct biome regions using a sector-based approach.
    Each sector is assigned a biome type based on position and rules.
]]
function MapService:GenerateBiomeLayout()
    framework.Log("Debug", "Generating biome layout...")

    activeBiomes = {}

    -- Define biome placement using polar coordinates from center
    -- This creates a natural-feeling island layout
    local biomeLayout = {
        -- Center: Facility (Visitor Center area)
        {biome = "facility", angle = 0, distance = 0, radius = 200},

        -- North: Jungle
        {biome = "jungle", angle = 0, distance = 400, radius = 300},

        -- Northeast: Plains
        {biome = "plains", angle = 45, distance = 500, radius = 250},

        -- East: Coastal
        {biome = "coastal", angle = 90, distance = 600, radius = 200},

        -- Southeast: Swamp
        {biome = "swamp", angle = 135, distance = 450, radius = 280},

        -- South: Volcanic
        {biome = "volcanic", angle = 180, distance = 400, radius = 350},

        -- Southwest: Plains
        {biome = "plains", angle = 225, distance = 500, radius = 250},

        -- West: Coastal
        {biome = "coastal", angle = 270, distance = 600, radius = 200},

        -- Northwest: Jungle
        {biome = "jungle", angle = 315, distance = 400, radius = 280},
    }

    -- Create biome instances
    for i, layout in ipairs(biomeLayout) do
        local biomeType = layout.biome
        local definition = BIOME_DEFINITIONS[biomeType]

        if definition then
            -- Calculate position from polar coordinates
            local angleRad = math.rad(layout.angle)
            local x = math.cos(angleRad) * layout.distance
            local z = math.sin(angleRad) * layout.distance

            local biomeInstance = {
                id = biomeType .. "_" .. i,
                type = biomeType,
                definition = definition,
                position = Vector3.new(x, 0, z),
                radius = layout.radius,
                bounds = {
                    min = Vector3.new(x - layout.radius, -50, z - layout.radius),
                    max = Vector3.new(x + layout.radius, 200, z + layout.radius),
                },
            }

            table.insert(activeBiomes, biomeInstance)
            mapData.biomes[biomeInstance.id] = biomeInstance

            framework.Log("Debug", "Created biome: %s at (%.0f, %.0f) radius %.0f",
                definition.name, x, z, layout.radius)
        end
    end

    framework.Log("Info", "Generated %d biome regions", #activeBiomes)
end

--[[
    Place Points of Interest on the map

    Positions major and minor POIs according to their definitions,
    respecting biome preferences and spacing rules.
]]
function MapService:PlacePOIs()
    framework.Log("Debug", "Placing Points of Interest...")

    activePOIs = {}

    -- Place major POIs first (they have preferred positions)
    for poiId, poiDef in pairs(POI_DEFINITIONS) do
        if poiDef.type == "major" then
            local position = self:FindPOIPosition(poiDef)

            if position then
                local poiInstance = {
                    id = poiId,
                    name = poiDef.name,
                    definition = poiDef,
                    position = position,
                    bounds = {
                        min = position - (poiDef.size / 2),
                        max = position + (poiDef.size / 2),
                    },
                    chests = {},
                    discovered = {},  -- Players who have discovered this POI
                }

                table.insert(activePOIs, poiInstance)
                mapData.pois[poiId] = poiInstance

                framework.Log("Debug", "Placed POI: %s at (%.0f, %.0f, %.0f)",
                    poiDef.name, position.X, position.Y, position.Z)
            end
        end
    end

    -- Place minor POIs (scattered based on count)
    for poiId, poiDef in pairs(POI_DEFINITIONS) do
        if poiDef.type == "minor" and poiDef.count then
            for i = 1, poiDef.count do
                local position = self:FindMinorPOIPosition(poiDef)

                if position then
                    local instanceId = poiId .. "_" .. i
                    local poiInstance = {
                        id = instanceId,
                        name = poiDef.name,
                        definition = poiDef,
                        position = position,
                        bounds = {
                            min = position - (poiDef.size / 2),
                            max = position + (poiDef.size / 2),
                        },
                        chests = {},
                        discovered = {},
                    }

                    table.insert(activePOIs, poiInstance)
                    mapData.pois[instanceId] = poiInstance
                end
            end
        end
    end

    framework.Log("Info", "Placed %d Points of Interest", #activePOIs)
end

--[[
    Find an appropriate position for a major POI

    @param poiDef table - POI definition
    @return Vector3 - Position for the POI, or nil if not found
]]
function MapService:FindPOIPosition(poiDef)
    -- Check for preferred position
    if poiDef.preferredPosition == "center" then
        return Vector3.new(0, 0, 0)
    end

    -- Find a biome that matches the POI's preferred biome
    if poiDef.biome then
        for _, biome in ipairs(activeBiomes) do
            if biome.type == poiDef.biome then
                -- Place near the biome center with some randomness
                local offset = Vector3.new(
                    (math.random() - 0.5) * biome.radius * 0.5,
                    0,
                    (math.random() - 0.5) * biome.radius * 0.5
                )
                return biome.position + offset
            end
        end
    end

    -- Fallback: random position within map bounds
    local halfSize = MAP_SIZE / 2
    return Vector3.new(
        (math.random() - 0.5) * halfSize,
        0,
        (math.random() - 0.5) * halfSize
    )
end

--[[
    Find an appropriate position for a minor POI

    @param poiDef table - POI definition
    @return Vector3 - Position for the POI, or nil if not found
]]
function MapService:FindMinorPOIPosition(poiDef)
    local attempts = 0
    local maxAttempts = 20

    while attempts < maxAttempts do
        attempts = attempts + 1

        -- Generate random position
        local halfSize = MAP_SIZE / 2 * 0.8  -- Stay away from edges
        local position = Vector3.new(
            (math.random() - 0.5) * halfSize * 2,
            0,
            (math.random() - 0.5) * halfSize * 2
        )

        -- Check minimum distance from other POIs
        local tooClose = false
        for _, existingPOI in ipairs(activePOIs) do
            local distance = (position - existingPOI.position).Magnitude
            local minDistance = 50  -- Minimum 50 studs between POIs

            if distance < minDistance then
                tooClose = true
                break
            end
        end

        if not tooClose then
            return position
        end
    end

    return nil  -- Could not find suitable position
end

--[[
    Generate spawn points for players, dinosaurs, and loot

    Distributes spawn points across the map respecting biome properties
    and ensuring fair player distribution.
]]
function MapService:GenerateSpawnPoints()
    framework.Log("Debug", "Generating spawn points...")

    spawnPoints = {
        player = {},
        dinosaur = {},
        loot = {},
    }

    -- Generate player spawn points (ring around map edge for drops)
    local numPlayerSpawns = 30  -- More than max players for variety
    local spawnRadius = MAP_SIZE / 2 * 0.7

    for i = 1, numPlayerSpawns do
        local angle = (i / numPlayerSpawns) * math.pi * 2
        local x = math.cos(angle) * spawnRadius
        local z = math.sin(angle) * spawnRadius

        -- Get terrain height for player spawn point
        local terrainY = GetTerrainHeight(x, z)
        table.insert(spawnPoints.player, {
            position = Vector3.new(x, terrainY, z),
            type = "player_drop",
        })
    end

    -- Generate dinosaur spawn points based on biomes
    for _, biome in ipairs(activeBiomes) do
        local spawnDensity = 0.001  -- Spawns per square stud
        local area = math.pi * biome.radius * biome.radius
        local numSpawns = math.floor(area * spawnDensity)

        for i = 1, numSpawns do
            -- Random position within biome radius
            local angle = math.random() * math.pi * 2
            local distance = math.random() * biome.radius
            local x = biome.position.X + math.cos(angle) * distance
            local z = biome.position.Z + math.sin(angle) * distance

            -- Get terrain height for this spawn point
            local terrainY = GetTerrainHeight(x, z)
            table.insert(spawnPoints.dinosaur, {
                position = Vector3.new(x, terrainY, z),
                biome = biome.type,
                spawnModifier = biome.definition.dinoSpawnModifier,
            })
        end
    end

    -- Generate loot spawn points
    local lootGridSize = 50  -- Studs between potential loot spawns
    local halfMap = MAP_SIZE / 2

    for x = -halfMap, halfMap, lootGridSize do
        for z = -halfMap, halfMap, lootGridSize do
            -- Add some randomness
            local offsetX = (math.random() - 0.5) * lootGridSize * 0.5
            local offsetZ = (math.random() - 0.5) * lootGridSize * 0.5

            -- Determine biome for loot modifier
            local biome = self:GetBiomeAtPosition(Vector3.new(x, 0, z))
            local lootMod = biome and biome.definition.lootModifier or 1.0

            -- Get terrain height for loot spawn
            local terrainY = GetTerrainHeight(x + offsetX, z + offsetZ)
            table.insert(spawnPoints.loot, {
                position = Vector3.new(x + offsetX, terrainY, z + offsetZ),
                lootModifier = lootMod,
            })
        end
    end

    -- Store in map data
    mapData.spawnPoints = spawnPoints

    framework.Log("Info", "Generated spawn points - Players: %d, Dinos: %d, Loot: %d",
        #spawnPoints.player, #spawnPoints.dinosaur, #spawnPoints.loot)
end

--[[
    Create visual terrain for all biomes

    Generates terrain parts, decorations, and environmental props
    based on biome definitions.
]]
function MapService:CreateTerrainVisuals()
    framework.Log("Debug", "Creating terrain visuals...")

    -- Get or create map folder in workspace
    local mapFolder = workspace:FindFirstChild("Map")
    if not mapFolder then
        mapFolder = Instance.new("Folder")
        mapFolder.Name = "Map"
        mapFolder.Parent = workspace
    end

    -- Create biomes folder
    local biomesFolder = mapFolder:FindFirstChild("Biomes")
    if not biomesFolder then
        biomesFolder = Instance.new("Folder")
        biomesFolder.Name = "Biomes"
        biomesFolder.Parent = mapFolder
    end

    -- Create terrain for each biome
    for _, biome in ipairs(activeBiomes) do
        self:CreateBiomeTerrain(biome, biomesFolder)
    end

    -- Create POI structures
    local poisFolder = mapFolder:FindFirstChild("POIs")
    if not poisFolder then
        poisFolder = Instance.new("Folder")
        poisFolder.Name = "POIs"
        poisFolder.Parent = mapFolder
    end

    for _, poi in ipairs(activePOIs) do
        self:CreatePOIStructure(poi, poisFolder)
    end

    framework.Log("Info", "Terrain visuals created")
end

--[[
    Create terrain and decorations for a single biome

    @param biome table - Biome instance data
    @param parent Instance - Parent folder for terrain
]]
function MapService:CreateBiomeTerrain(biome, parent)
    local definition = biome.definition

    -- Create biome container
    local biomeFolder = Instance.new("Folder")
    biomeFolder.Name = biome.id
    biomeFolder.Parent = parent

    -- Create ground plane for the biome
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Anchored = true
    ground.CanCollide = true
    ground.Size = Vector3.new(biome.radius * 2, 5, biome.radius * 2)
    ground.Position = Vector3.new(biome.position.X, -2.5, biome.position.Z)
    ground.Material = definition.groundMaterial or Enum.Material.Grass
    ground.Color = definition.color
    ground.TopSurface = Enum.SurfaceType.Smooth
    ground.BottomSurface = Enum.SurfaceType.Smooth
    ground.Parent = biomeFolder

    -- Add biome indicator (for debugging/minimap)
    ground:SetAttribute("BiomeType", biome.type)
    ground:SetAttribute("BiomeName", definition.name)

    -- Create vegetation if applicable
    if definition.vegetationDensity > 0 then
        self:CreateVegetation(biome, biomeFolder)
    end

    -- Create water if swamp biome
    if definition.waterLevel then
        self:CreateWater(biome, biomeFolder)
    end

    -- Create hazard features if applicable
    if definition.hazards then
        self:CreateHazardFeatures(biome, biomeFolder)
    end
end

--[[
    Create vegetation (trees, bushes, etc.) for a biome
    Uses MapAssets module to spawn actual asset pack trees and vegetation

    @param biome table - Biome instance data
    @param parent Instance - Parent folder
]]
function MapService:CreateVegetation(biome, parent)
    local definition = biome.definition
    local vegetationFolder = Instance.new("Folder")
    vegetationFolder.Name = "Vegetation"
    vegetationFolder.Parent = parent

    -- Calculate number of vegetation pieces based on density
    local area = math.pi * biome.radius * biome.radius
    local vegDensity = definition.vegetationDensity * 0.001  -- Pieces per square stud
    local numPieces = math.floor(area * vegDensity)

    -- Cap at reasonable number
    numPieces = math.min(numPieces, 100)

    -- Try to use MapAssets for real asset loading
    local MapAssets = framework:GetModule("MapAssets")
    if MapAssets then
        -- Get vegetation type based on biome
        local vegetationType = self:GetVegetationTypeForBiome(biome.type)

        -- Spawn vegetation using MapAssets
        local spawnedVegetation = MapAssets:SpawnVegetation(
            vegetationType,
            biome.position,
            biome.radius * 0.9,
            numPieces,
            biome.type  -- Pass biome for tree pack selection
        )

        -- Reparent spawned vegetation to our folder for organization
        for _, veg in ipairs(spawnedVegetation) do
            if veg and veg.Parent then
                veg.Parent = vegetationFolder
            end
        end

        framework.Log("Debug", "Spawned %d vegetation items for biome %s using MapAssets", #spawnedVegetation, biome.type)
        return
    end

    -- Fallback to placeholder vegetation if MapAssets not available
    framework.Log("Warn", "MapAssets not available, using placeholder vegetation")
    for i = 1, numPieces do
        -- Random position within biome
        local angle = math.random() * math.pi * 2
        local distance = math.random() * biome.radius * 0.9
        local x = biome.position.X + math.cos(angle) * distance
        local z = biome.position.Z + math.sin(angle) * distance

        -- Get terrain height at this position
        local groundY = GetTerrainHeight(x, z)

        -- Create simple tree placeholder
        local tree = Instance.new("Part")
        tree.Name = "Tree_" .. i
        tree.Anchored = true
        tree.CanCollide = true
        tree.Size = Vector3.new(3, math.random(8, 15), 3)
        tree.Position = Vector3.new(x, groundY + tree.Size.Y / 2, z)
        tree.Material = Enum.Material.Wood
        tree.Color = Color3.fromRGB(101, 67, 33)  -- Brown
        tree.Parent = vegetationFolder

        -- Add foliage on top
        local foliage = Instance.new("Part")
        foliage.Name = "Foliage"
        foliage.Anchored = true
        foliage.CanCollide = false
        foliage.Size = Vector3.new(8, 6, 8)
        foliage.Position = Vector3.new(x, groundY + tree.Size.Y + 2, z)
        foliage.Material = Enum.Material.Grass
        foliage.Color = definition.color
        foliage.Shape = Enum.PartType.Ball
        foliage.Parent = vegetationFolder
    end
end

--[[
    Get the vegetation type from AssetManifest for a given biome type

    @param biomeType string - The biome type (jungle, swamp, volcanic, etc.)
    @return string - The vegetation type key for AssetManifest.Vegetation
]]
function MapService:GetVegetationTypeForBiome(biomeType)
    local biomeToVegetation = {
        jungle = "JungleTrees",
        swamp = "SwampTrees",
        volcanic = "CharredTrees",
        facility = "GrassTufts",
        plains = "GrassTufts",
        coastal = "GrassTufts",
    }
    return biomeToVegetation[biomeType] or "JungleTrees"
end

--[[
    Create water features for swamp biomes

    @param biome table - Biome instance data
    @param parent Instance - Parent folder
]]
function MapService:CreateWater(biome, parent)
    local definition = biome.definition

    local water = Instance.new("Part")
    water.Name = "Water"
    water.Anchored = true
    water.CanCollide = false
    water.Size = Vector3.new(biome.radius * 2, definition.waterLevel, biome.radius * 2)
    water.Position = Vector3.new(biome.position.X, definition.waterLevel / 2, biome.position.Z)
    water.Material = Enum.Material.Water
    water.Color = Color3.fromRGB(50, 80, 70)  -- Murky water
    water.Transparency = 0.3
    water.Parent = parent
end

--[[
    Create hazard features (lava pools, vents, etc.) for a biome

    @param biome table - Biome instance data
    @param parent Instance - Parent folder
]]
function MapService:CreateHazardFeatures(biome, parent)
    local definition = biome.definition
    local hazardFolder = Instance.new("Folder")
    hazardFolder.Name = "Hazards"
    hazardFolder.Parent = parent

    -- Create lava pools for volcanic biome
    if table.find(definition.hazards, "lava_pool") then
        local numPools = math.random(5, 10)

        for i = 1, numPools do
            local angle = math.random() * math.pi * 2
            local distance = math.random() * biome.radius * 0.7
            local x = biome.position.X + math.cos(angle) * distance
            local z = biome.position.Z + math.sin(angle) * distance

            -- Get terrain height at this position
            local groundY = GetTerrainHeight(x, z)

            local lava = Instance.new("Part")
            lava.Name = "LavaPool_" .. i
            lava.Anchored = true
            lava.CanCollide = false
            lava.Size = Vector3.new(math.random(10, 25), 1, math.random(10, 25))
            lava.Position = Vector3.new(x, groundY + 0.5, z)
            lava.Material = Enum.Material.CrackedLava
            lava.Color = Color3.fromRGB(255, 100, 0)
            lava.Parent = hazardFolder

            -- Mark as hazard
            lava:SetAttribute("Hazard", true)
            lava:SetAttribute("DamagePerSecond", 20)

            -- Add glow effect
            local light = Instance.new("PointLight")
            light.Color = Color3.fromRGB(255, 150, 50)
            light.Brightness = 2
            light.Range = lava.Size.X
            light.Parent = lava
        end
    end
end

--[[
    Create a POI structure using MapAssets for real building models

    @param poi table - POI instance data
    @param parent Instance - Parent folder
]]
function MapService:CreatePOIStructure(poi, parent)
    local definition = poi.definition

    -- Create POI container
    local poiFolder = Instance.new("Model")
    poiFolder.Name = poi.id
    poiFolder.Parent = parent

    -- Get terrain height at POI position
    local groundY = GetTerrainHeight(poi.position.X, poi.position.Z)

    -- Try to use MapAssets for real building spawning
    local MapAssets = framework:GetModule("MapAssets")
    local buildingsSpawned = false

    if MapAssets then
        -- Use POI name to look up building configuration in AssetManifest
        local spawnedBuildings = MapAssets:SpawnPOIBuildings(definition.name, poi.position)

        if spawnedBuildings and #spawnedBuildings > 0 then
            buildingsSpawned = true
            -- Reparent buildings to POI folder
            for _, building in ipairs(spawnedBuildings) do
                if building and building.Parent then
                    building.Parent = poiFolder
                end
            end
            framework.Log("Info", "Spawned %d buildings for POI '%s' using MapAssets", #spawnedBuildings, definition.name)

            -- Set the first building as primary part if available
            local firstBuilding = spawnedBuildings[1]
            if firstBuilding and firstBuilding:IsA("Model") and firstBuilding.PrimaryPart then
                poiFolder.PrimaryPart = firstBuilding.PrimaryPart
            elseif firstBuilding and firstBuilding:IsA("BasePart") then
                poiFolder.PrimaryPart = firstBuilding
            end
        end
    end

    -- Fallback to placeholder if MapAssets unavailable or no buildings configured
    if not buildingsSpawned then
        framework.Log("Debug", "Using placeholder structure for POI '%s'", definition.name)

        -- Create base platform/structure
        local base = Instance.new("Part")
        base.Name = "Base"
        base.Anchored = true
        base.CanCollide = true
        base.Size = definition.size
        base.Position = Vector3.new(poi.position.X, groundY + definition.size.Y / 2, poi.position.Z)

        -- Set material based on POI type
        if definition.biome == "facility" then
            base.Material = Enum.Material.Concrete
            base.Color = Color3.fromRGB(128, 128, 128)
        elseif definition.biome == "coastal" then
            base.Material = Enum.Material.Wood
            base.Color = Color3.fromRGB(139, 90, 43)
        else
            base.Material = Enum.Material.Slate
            base.Color = Color3.fromRGB(100, 100, 100)
        end

        base.Parent = poiFolder
        poiFolder.PrimaryPart = base
    end

    -- Create name label (BillboardGui) - attach to primary part or first child
    local labelTarget = poiFolder.PrimaryPart or poiFolder:FindFirstChildWhichIsA("BasePart", true)
    if labelTarget then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "NameLabel"
        billboard.Size = UDim2.new(0, 200, 0, 50)
        billboard.StudsOffset = Vector3.new(0, definition.size.Y / 2 + 10, 0)
        billboard.Adornee = labelTarget
        billboard.Parent = labelTarget

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 1, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = definition.name
        nameLabel.TextColor3 = Color3.new(1, 1, 1)
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        nameLabel.TextStrokeTransparency = 0.5
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Parent = billboard
    end

    -- Store reference in POI data
    poi.model = poiFolder

    -- Add POI markers for spawn points
    self:AddPOISpawnMarkers(poi, poiFolder)
end

--[[
    Add spawn point markers within a POI

    @param poi table - POI instance data
    @param parent Instance - Parent model
]]
function MapService:AddPOISpawnMarkers(poi, parent)
    local definition = poi.definition

    -- Create chest spawn points
    local chestsFolder = Instance.new("Folder")
    chestsFolder.Name = "ChestSpawnPoints"
    chestsFolder.Parent = parent

    for i = 1, definition.chestCount or 0 do
        local offset = Vector3.new(
            (math.random() - 0.5) * definition.size.X * 0.8,
            0,
            (math.random() - 0.5) * definition.size.Z * 0.8
        )

        local marker = Instance.new("Part")
        marker.Name = "ChestSpawn_" .. i
        marker.Anchored = true
        marker.CanCollide = false
        marker.Transparency = 1
        marker.Size = Vector3.new(2, 0.5, 2)
        marker.Position = poi.position + offset
        marker:SetAttribute("LootTier", definition.lootTier)
        marker.Parent = chestsFolder

        -- Store spawn point
        table.insert(poi.chests, marker.Position)
    end

    -- Create dino spawn points
    local dinoFolder = Instance.new("Folder")
    dinoFolder.Name = "DinoSpawnPoints"
    dinoFolder.Parent = parent

    for i = 1, definition.dinoSpawns or 0 do
        local offset = Vector3.new(
            (math.random() - 0.5) * definition.size.X,
            0,
            (math.random() - 0.5) * definition.size.Z
        )

        local marker = Instance.new("Part")
        marker.Name = "DinoSpawn_" .. i
        marker.Anchored = true
        marker.CanCollide = false
        marker.Transparency = 1
        marker.Size = Vector3.new(3, 0.5, 3)
        marker.Position = poi.position + offset
        marker:SetAttribute("DinoOverride", definition.dinoOverride)
        marker.Parent = dinoFolder
    end
end

--[[
    Setup hazard zones that will trigger environmental events
]]
function MapService:SetupHazardZones()
    framework.Log("Debug", "Setting up hazard zones...")

    mapData.hazardZones = {}

    -- Add volcanic hazard zone
    for _, biome in ipairs(activeBiomes) do
        if biome.type == "volcanic" then
            table.insert(mapData.hazardZones, {
                type = "volcanic",
                position = biome.position,
                radius = biome.radius,
                events = {"volcanic_eruption", "toxic_gas"},
            })
        end
    end

    -- Add POI hazard zones
    for _, poi in ipairs(activePOIs) do
        if poi.definition.hazardZone then
            table.insert(mapData.hazardZones, {
                type = "poi",
                poiId = poi.id,
                position = poi.position,
                radius = poi.definition.size.X / 2,
                events = {"alpha_spawn"},
            })
        end
    end

    framework.Log("Info", "Setup %d hazard zones", #mapData.hazardZones)
end

--==============================================================================
-- ENVIRONMENTAL EVENTS
--==============================================================================

--[[
    Start the environmental event system

    Begins monitoring for event triggers and running the event loop.
]]
function MapService:StartEnvironmentalEvents()
    if eventLoopRunning then
        framework.Log("Warn", "Environmental events already running")
        return
    end

    eventLoopRunning = true
    activeEvents = {}

    framework.Log("Info", "Starting environmental event system")

    -- Start event loop
    task.spawn(function()
        while eventLoopRunning do
            self:UpdateEnvironmentalEvents()
            task.wait(5)  -- Check every 5 seconds
        end
    end)
end

--[[
    Stop the environmental event system
]]
function MapService:StopEnvironmentalEvents()
    eventLoopRunning = false

    -- Clean up active events
    for eventId, event in pairs(activeEvents) do
        self:EndEvent(eventId)
    end

    activeEvents = {}
    framework.Log("Info", "Environmental event system stopped")
end

--[[
    Update environmental events - check for triggers and update active events
]]
function MapService:UpdateEnvironmentalEvents()
    -- Get current storm phase for event scaling
    local stormService = framework:GetService("StormService")
    local stormState = stormService and stormService:GetState() or {phase = 1}
    local currentPhase = stormState.phase

    -- Check each event type for trigger conditions
    for eventType, eventDef in pairs(EVENT_DEFINITIONS) do
        -- Skip if event is on cooldown
        if self:IsEventOnCooldown(eventType) then
            continue
        end

        -- Check phase requirement
        if eventDef.stormPhaseMin and currentPhase < eventDef.stormPhaseMin then
            continue
        end

        -- Random chance to trigger (scales with storm phase)
        local triggerChance = 0.05 * currentPhase  -- 5% per phase per check

        if math.random() < triggerChance then
            self:TriggerEvent(eventType)
        end
    end

    -- Update active events
    for eventId, event in pairs(activeEvents) do
        self:UpdateEvent(event)
    end
end

--[[
    Check if an event type is on cooldown

    @param eventType string - Event type identifier
    @return boolean - True if on cooldown
]]
function MapService:IsEventOnCooldown(eventType)
    for _, event in pairs(activeEvents) do
        if event.type == eventType then
            return true  -- Already active
        end
    end

    -- Check last trigger time
    local lastTrigger = mapData["lastEvent_" .. eventType] or 0
    local cooldown = EVENT_DEFINITIONS[eventType].cooldown or 60

    return (tick() - lastTrigger) < cooldown
end

--[[
    Trigger an environmental event

    @param eventType string - Event type identifier
    @return string - Event instance ID, or nil if failed
]]
function MapService:TriggerEvent(eventType)
    local eventDef = EVENT_DEFINITIONS[eventType]
    if not eventDef then
        framework.Log("Error", "Unknown event type: %s", eventType)
        return nil
    end

    -- Generate event instance
    local eventId = eventType .. "_" .. tick()
    local position = self:SelectEventPosition(eventType, eventDef)

    local event = {
        id = eventId,
        type = eventType,
        definition = eventDef,
        position = position,
        startTime = tick() + eventDef.warningTime,
        endTime = tick() + eventDef.warningTime + eventDef.duration,
        state = "warning",  -- warning, active, ending
        affectedPlayers = {},
    }

    activeEvents[eventId] = event
    mapData["lastEvent_" .. eventType] = tick()

    framework.Log("Info", "Environmental event triggered: %s", eventDef.name)

    -- Broadcast warning to players
    self:BroadcastEventWarning(event)

    return eventId
end

--[[
    Select a position for an environmental event

    @param eventType string - Event type
    @param eventDef table - Event definition
    @return Vector3 - Event center position
]]
function MapService:SelectEventPosition(eventType, eventDef)
    -- Biome-specific events
    if eventDef.biome then
        for _, biome in ipairs(activeBiomes) do
            if biome.type == eventDef.biome then
                -- Random position within biome
                local angle = math.random() * math.pi * 2
                local distance = math.random() * biome.radius * 0.5
                return biome.position + Vector3.new(
                    math.cos(angle) * distance,
                    0,
                    math.sin(angle) * distance
                )
            end
        end
    end

    -- Supply drops target areas with players
    if eventType == "supply_drop" then
        local players = Players:GetPlayers()
        if #players > 0 then
            local randomPlayer = players[math.random(#players)]
            if randomPlayer.Character and randomPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local playerPos = randomPlayer.Character.HumanoidRootPart.Position
                -- Drop near but not on player
                local offset = Vector3.new(
                    (math.random() - 0.5) * 100,
                    0,
                    (math.random() - 0.5) * 100
                )
                return playerPos + offset
            end
        end
    end

    -- Default: random position within storm zone
    local stormService = framework:GetService("StormService")
    if stormService then
        local stormState = stormService:GetState()
        local angle = math.random() * math.pi * 2
        local distance = math.random() * stormState.currentRadius * 0.7
        return stormState.currentCenter + Vector3.new(
            math.cos(angle) * distance,
            0,
            math.sin(angle) * distance
        )
    end

    return Vector3.new(0, 0, 0)
end

--[[
    Update a running environmental event

    @param event table - Event instance
]]
function MapService:UpdateEvent(event)
    local now = tick()
    local eventDef = event.definition

    -- State transitions
    if event.state == "warning" and now >= event.startTime then
        event.state = "active"
        self:StartEventEffects(event)
        framework.Log("Debug", "Event started: %s", eventDef.name)
    end

    if event.state == "active" then
        -- Apply event effects
        self:ApplyEventEffects(event)

        -- Check for end
        if now >= event.endTime then
            event.state = "ending"
            self:EndEvent(event.id)
        end
    end
end

--[[
    Start visual/audio effects for an event

    @param event table - Event instance
]]
function MapService:StartEventEffects(event)
    local eventDef = event.definition

    -- Create visual indicator at event location
    local mapFolder = workspace:FindFirstChild("Map")
    local eventsFolder = mapFolder and mapFolder:FindFirstChild("Events")
    if not eventsFolder and mapFolder then
        eventsFolder = Instance.new("Folder")
        eventsFolder.Name = "Events"
        eventsFolder.Parent = mapFolder
    end

    -- Create effect based on event type
    if event.type == "volcanic_eruption" then
        self:CreateEruptionEffect(event, eventsFolder)
    elseif event.type == "supply_drop" then
        self:CreateSupplyDropEffect(event, eventsFolder)
    elseif event.type == "meteor_shower" then
        self:CreateMeteorShowerEffect(event, eventsFolder)
    end
end

--[[
    Create volcanic eruption visual effect

    @param event table - Event instance
    @param parent Instance - Parent folder
]]
function MapService:CreateEruptionEffect(event, parent)
    local eventDef = event.definition

    -- Create eruption zone indicator
    local zone = Instance.new("Part")
    zone.Name = "EruptionZone_" .. event.id
    zone.Anchored = true
    zone.CanCollide = false
    zone.Transparency = 0.7
    zone.Size = Vector3.new(eventDef.radius * 2, 5, eventDef.radius * 2)
    zone.Position = event.position
    zone.Shape = Enum.PartType.Cylinder
    zone.Orientation = Vector3.new(0, 0, 90)
    zone.Material = Enum.Material.Neon
    zone.Color = Color3.fromRGB(255, 100, 0)
    zone.Parent = parent

    event.zoneIndicator = zone

    -- Spawn falling debris periodically
    task.spawn(function()
        while event.state == "active" do
            self:SpawnEruptionDebris(event)
            task.wait(0.5)
        end
    end)
end

--[[
    Spawn falling debris during eruption

    @param event table - Event instance
]]
function MapService:SpawnEruptionDebris(event)
    local eventDef = event.definition

    -- Random position within radius
    local angle = math.random() * math.pi * 2
    local distance = math.random() * eventDef.radius
    local targetPos = event.position + Vector3.new(
        math.cos(angle) * distance,
        0,
        math.sin(angle) * distance
    )

    -- Create debris
    local debris = Instance.new("Part")
    debris.Name = "Debris"
    debris.Size = Vector3.new(3, 3, 3)
    debris.Position = targetPos + Vector3.new(0, 200, 0)  -- Start high
    debris.Color = Color3.fromRGB(100, 50, 0)
    debris.Material = Enum.Material.Rock
    debris.Anchored = false
    debris.CanCollide = true

    -- Add fire effect
    local fire = Instance.new("Fire")
    fire.Size = 5
    fire.Heat = 10
    fire.Parent = debris

    debris.Parent = workspace

    -- Clean up and damage on impact
    debris.Touched:Connect(function(hit)
        -- Check if hit player
        local character = hit:FindFirstAncestorOfClass("Model")
        if character then
            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then
                humanoid:TakeDamage(eventDef.damage)
            end
        end

        -- Destroy debris
        debris:Destroy()
    end)

    -- Auto cleanup after 5 seconds
    Debris:AddItem(debris, 5)
end

--[[
    Create supply drop visual effect

    @param event table - Event instance
    @param parent Instance - Parent folder
]]
function MapService:CreateSupplyDropEffect(event, parent)
    local eventDef = event.definition

    -- Create supply crate
    local crate = Instance.new("Part")
    crate.Name = "SupplyCrate_" .. event.id
    crate.Anchored = true
    crate.CanCollide = true
    crate.Size = Vector3.new(6, 4, 4)
    crate.Position = event.position + Vector3.new(0, 100, 0)  -- Start high
    crate.Color = Color3.fromRGB(255, 200, 0)
    crate.Material = Enum.Material.Metal
    crate.Parent = parent

    -- Add smoke trail
    local smoke = Instance.new("Smoke")
    smoke.Color = Color3.fromRGB(200, 200, 200)
    smoke.Size = 3
    smoke.RiseVelocity = -5
    smoke.Parent = crate

    -- Add light beacon
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 255, 0)
    light.Brightness = 3
    light.Range = 30
    light.Parent = crate

    -- Animate descent
    local tweenInfo = TweenInfo.new(5, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(crate, tweenInfo, {
        Position = event.position + Vector3.new(0, 2, 0)
    })
    tween:Play()

    event.supplyModel = crate

    -- Add proximity prompt for opening
    tween.Completed:Connect(function()
        smoke:Destroy()

        local prompt = Instance.new("ProximityPrompt")
        prompt.ActionText = "Open"
        prompt.ObjectText = "Supply Drop"
        prompt.MaxActivationDistance = 10
        prompt.Parent = crate

        prompt.Triggered:Connect(function(player)
            self:OpenSupplyDrop(event, player)
        end)
    end)
end

--[[
    Create meteor shower visual effect

    @param event table - Event instance
    @param parent Instance - Parent folder
]]
function MapService:CreateMeteorShowerEffect(event, parent)
    local eventDef = event.definition

    -- Spawn meteors periodically
    task.spawn(function()
        local meteorsSpawned = 0
        while event.state == "active" and meteorsSpawned < eventDef.meteorCount do
            self:SpawnMeteor(event, parent)
            meteorsSpawned = meteorsSpawned + 1
            task.wait(eventDef.duration / eventDef.meteorCount)
        end
    end)
end

--[[
    Spawn a single meteor

    @param event table - Event instance
    @param parent Instance - Parent folder
]]
function MapService:SpawnMeteor(event, parent)
    local eventDef = event.definition

    -- Random target position
    local stormService = framework:GetService("StormService")
    local stormState = stormService and stormService:GetState() or {currentRadius = 500, currentCenter = Vector3.new(0,0,0)}

    local angle = math.random() * math.pi * 2
    local distance = math.random() * stormState.currentRadius
    local targetPos = stormState.currentCenter + Vector3.new(
        math.cos(angle) * distance,
        0,
        math.sin(angle) * distance
    )

    -- Create meteor
    local meteor = Instance.new("Part")
    meteor.Name = "Meteor"
    meteor.Size = Vector3.new(5, 5, 5)
    meteor.Shape = Enum.PartType.Ball
    meteor.Position = targetPos + Vector3.new(
        (math.random() - 0.5) * 100,
        300,
        (math.random() - 0.5) * 100
    )
    meteor.Color = Color3.fromRGB(150, 75, 0)
    meteor.Material = Enum.Material.Rock
    meteor.Anchored = false
    meteor.CanCollide = true
    meteor.Parent = parent

    -- Add fire trail
    local fire = Instance.new("Fire")
    fire.Size = 10
    fire.Heat = 20
    fire.Parent = meteor

    -- Add light
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 150, 0)
    light.Brightness = 5
    light.Range = 30
    light.Parent = meteor

    -- Damage on impact
    meteor.Touched:Connect(function(hit)
        if hit.Name ~= "Meteor" then
            -- Create explosion effect
            local explosion = Instance.new("Explosion")
            explosion.Position = meteor.Position
            explosion.BlastRadius = eventDef.impactRadius
            explosion.BlastPressure = 10000
            explosion.DestroyJointRadiusPercent = 0
            explosion.Parent = workspace

            meteor:Destroy()
        end
    end)

    -- Auto cleanup
    Debris:AddItem(meteor, 10)
end

--[[
    Open a supply drop and give loot to player

    @param event table - Event instance
    @param player Player - Player who opened the crate
]]
function MapService:OpenSupplyDrop(event, player)
    framework.Log("Info", "%s opened supply drop", player.Name)

    -- Use LootSystem for GDD-compliant supply drop rarity distribution
    -- Supply Drop: 0% Common, 10% Uncommon, 30% Rare, 40% Epic, 20% Legendary
    local lootSystem = framework:GetModule("LootSystem")
    if lootSystem and lootSystem.SpawnSupplyDropLoot then
        local dropPosition = event.position or (event.supplyModel and event.supplyModel.Position)
        if dropPosition then
            lootSystem:SpawnSupplyDropLoot(dropPosition, math.random(3, 4))
        end
    else
        -- Fallback: Give legendary weapon directly (legacy behavior)
        local weaponService = framework:GetService("WeaponService")
        if weaponService then
            local legendaryWeapons = {"scar", "bolt_sniper"}
            local weapon = legendaryWeapons[math.random(#legendaryWeapons)]
            weaponService:GiveWeapon(player, weapon)
        end
    end

    -- Destroy the crate
    if event.supplyModel then
        event.supplyModel:Destroy()
    end

    -- End the event
    self:EndEvent(event.id)
end

--[[
    Apply ongoing effects of an active event

    @param event table - Event instance
]]
function MapService:ApplyEventEffects(event)
    local eventDef = event.definition

    -- Track players affected by slow effects for cleanup
    if not event.affectedPlayers then
        event.affectedPlayers = {}
    end

    -- Damage-over-time events (like toxic gas)
    if eventDef.damagePerSecond or eventDef.slowEffect then
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            if not character then continue end

            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChild("Humanoid")

            if rootPart and humanoid and humanoid.Health > 0 then
                local distance = (rootPart.Position - event.position).Magnitude
                local inRadius = distance <= eventDef.radius

                if inRadius then
                    -- Apply damage over time
                    if eventDef.damagePerSecond then
                        humanoid:TakeDamage(eventDef.damagePerSecond * 0.2)  -- Apply per update tick
                    end

                    -- Apply slow effect (GDD: toxic gas has DoT + slow)
                    if eventDef.slowEffect then
                        local defaultWalkSpeed = 16  -- Roblox default
                        local slowedSpeed = defaultWalkSpeed * (1 - eventDef.slowEffect)

                        if humanoid.WalkSpeed > slowedSpeed then
                            -- Store original speed if not already stored
                            if not event.affectedPlayers[player.UserId] then
                                event.affectedPlayers[player.UserId] = {
                                    originalWalkSpeed = humanoid.WalkSpeed,
                                }
                            end
                            humanoid.WalkSpeed = slowedSpeed
                        end
                    end
                else
                    -- Player left the effect radius - restore normal speed
                    if eventDef.slowEffect and event.affectedPlayers[player.UserId] then
                        local original = event.affectedPlayers[player.UserId].originalWalkSpeed
                        if original then
                            humanoid.WalkSpeed = original
                        end
                        event.affectedPlayers[player.UserId] = nil
                    end
                end
            end
        end
    end
end

--[[
    Clean up effects when event ends (restore player speeds, etc.)

    @param event table - Event instance
]]
function MapService:CleanupEventEffects(event)
    local eventDef = event.definition

    -- Restore walk speeds for any players still affected
    if eventDef.slowEffect and event.affectedPlayers then
        for userId, data in pairs(event.affectedPlayers) do
            local player = Players:GetPlayerByUserId(userId)
            if player and player.Character then
                local humanoid = player.Character:FindFirstChild("Humanoid")
                if humanoid and data.originalWalkSpeed then
                    humanoid.WalkSpeed = data.originalWalkSpeed
                end
            end
        end
        event.affectedPlayers = {}
    end
end

--[[
    End an environmental event

    @param eventId string - Event instance ID
]]
function MapService:EndEvent(eventId)
    local event = activeEvents[eventId]
    if not event then return end

    framework.Log("Info", "Environmental event ended: %s", event.definition.name)

    -- Clean up event effects (restore player speeds, etc.)
    self:CleanupEventEffects(event)

    -- Clean up visual effects
    if event.zoneIndicator then
        event.zoneIndicator:Destroy()
    end
    if event.supplyModel then
        event.supplyModel:Destroy()
    end

    -- Remove from active events
    activeEvents[eventId] = nil

    -- Broadcast end to clients
    self:BroadcastEventEnd(event)
end

--[[
    Broadcast event warning to all players

    @param event table - Event instance
]]
function MapService:BroadcastEventWarning(event)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    local eventRemote = remotes:FindFirstChild("EnvironmentalEvent")
    if eventRemote then
        eventRemote:FireAllClients({
            type = "warning",
            eventType = event.type,
            eventName = event.definition.name,
            description = event.definition.description,
            position = event.position,
            radius = event.definition.radius,
            warningTime = event.definition.warningTime,
            markedOnMap = event.definition.markedOnMap,
        })
    end
end

--[[
    Broadcast event end to all players

    @param event table - Event instance
]]
function MapService:BroadcastEventEnd(event)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    local eventRemote = remotes:FindFirstChild("EnvironmentalEvent")
    if eventRemote then
        eventRemote:FireAllClients({
            type = "ended",
            eventType = event.type,
            eventName = event.definition.name,
        })
    end
end

--==============================================================================
-- UTILITY FUNCTIONS
--==============================================================================

--[[
    Get the biome at a specific world position

    @param position Vector3 - World position
    @return table - Biome instance, or nil if not in any biome
]]
function MapService:GetBiomeAtPosition(position)
    for _, biome in ipairs(activeBiomes) do
        local flatPos = Vector3.new(position.X, 0, position.Z)
        local flatBiomePos = Vector3.new(biome.position.X, 0, biome.position.Z)
        local distance = (flatPos - flatBiomePos).Magnitude

        if distance <= biome.radius then
            return biome
        end
    end

    return nil
end

--[[
    Get the POI at a specific world position

    @param position Vector3 - World position
    @return table - POI instance, or nil if not in any POI
]]
function MapService:GetPOIAtPosition(position)
    for _, poi in ipairs(activePOIs) do
        if position.X >= poi.bounds.min.X and position.X <= poi.bounds.max.X and
           position.Z >= poi.bounds.min.Z and position.Z <= poi.bounds.max.Z then
            return poi
        end
    end

    return nil
end

--[[
    Get player spawn points

    @return table - Array of spawn point positions
]]
function MapService:GetPlayerSpawnPoints()
    local positions = {}
    -- Handle case where spawnPoints.player may not be initialized
    if spawnPoints and spawnPoints.player then
        for _, spawn in ipairs(spawnPoints.player) do
            table.insert(positions, spawn.position)
        end
    end
    return positions
end

--[[
    Get dinosaur spawn points

    @param biomeFilter string - Optional biome type filter
    @return table - Array of spawn point data
]]
function MapService:GetDinoSpawnPoints(biomeFilter)
    -- Handle case where spawnPoints may not be initialized
    if not spawnPoints or not spawnPoints.dinosaur then
        return {}
    end

    if not biomeFilter then
        return spawnPoints.dinosaur
    end

    local filtered = {}
    for _, spawn in ipairs(spawnPoints.dinosaur) do
        if spawn.biome == biomeFilter then
            table.insert(filtered, spawn)
        end
    end
    return filtered
end

--[[
    Get loot spawn points

    @return table - Array of spawn point data
]]
function MapService:GetLootSpawnPoints()
    -- Handle case where spawnPoints may not be initialized
    if not spawnPoints or not spawnPoints.loot then
        return {}
    end
    return spawnPoints.loot
end

--[[
    Get chest spawn locations from POIs
    Each POI can have designated chest locations for higher-tier loot

    @return table - Array of chest location data {position, rarity, poiId}
]]
function MapService:GetPOIChestLocations()
    local chestLocations = {}

    -- Iterate through all active POIs to find chest spawn points
    for _, poi in ipairs(activePOIs) do
        if poi.definition and poi.definition.chestLocations then
            -- POI has defined chest locations
            for _, chestOffset in ipairs(poi.definition.chestLocations) do
                table.insert(chestLocations, {
                    position = poi.position + chestOffset,
                    rarity = poi.definition.lootTier or "rare",
                    poiId = poi.id,
                    poiName = poi.name,
                })
            end
        else
            -- Generate default chest location at POI center if no explicit locations
            -- Higher-tier POIs get more chests
            local lootTier = poi.definition and poi.definition.lootTier or "uncommon"
            local chestCount = (lootTier == "legendary" and 3) or (lootTier == "epic" and 2) or 1

            for i = 1, chestCount do
                local angle = (i / chestCount) * math.pi * 2
                local offset = Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
                table.insert(chestLocations, {
                    position = poi.position + offset,
                    rarity = lootTier,
                    poiId = poi.id,
                    poiName = poi.name,
                })
            end
        end
    end

    framework.Log("Debug", "Generated %d chest locations from %d POIs", #chestLocations, #activePOIs)
    return chestLocations
end

--[[
    Get map center position

    @return Vector3 - Center of the map
]]
function MapService:GetMapCenter()
    if mapData and mapData.center then
        return mapData.center
    end
    return MAP_CENTER -- Fallback to constant
end

--[[
    Get map bounds

    @return number - Map size (width/length in studs)
]]
function MapService:GetMapSize()
    if mapData and mapData.size then
        return mapData.size
    end
    return MAP_SIZE -- Fallback to constant
end

--[[
    Sync map data to all connected clients
]]
function MapService:SyncMapToClients()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    local mapSync = remotes:FindFirstChild("MapDataSync")
    if mapSync then
        -- Prepare simplified map data for clients
        local clientMapData = {
            size = mapData.size,
            center = mapData.center,
            biomes = {},
            pois = {},
        }

        -- Add biome info (simplified)
        for _, biome in ipairs(activeBiomes) do
            table.insert(clientMapData.biomes, {
                id = biome.id,
                type = biome.type,
                name = biome.definition.name,
                position = biome.position,
                radius = biome.radius,
                color = biome.definition.color,
            })
        end

        -- Add POI info (simplified)
        for _, poi in ipairs(activePOIs) do
            table.insert(clientMapData.pois, {
                id = poi.id,
                name = poi.name,
                position = poi.position,
                type = poi.definition.type,
            })
        end

        mapSync:FireAllClients(clientMapData)
    end
end

--[[
    Get current map data

    @return table - Map data structure
]]
function MapService:GetMapData()
    return mapData
end

--[[
    Get all active biomes

    @return table - Array of biome instances
]]
function MapService:GetBiomes()
    return activeBiomes
end

--[[
    Get all active POIs

    @return table - Array of POI instances
]]
function MapService:GetPOIs()
    return activePOIs
end

--[[
    Get biome definitions

    @return table - Biome definition table
]]
function MapService:GetBiomeDefinitions()
    return BIOME_DEFINITIONS
end

--[[
    Get POI definitions

    @return table - POI definition table
]]
function MapService:GetPOIDefinitions()
    return POI_DEFINITIONS
end

--[[
    Get event definitions

    @return table - Event definition table
]]
function MapService:GetEventDefinitions()
    return EVENT_DEFINITIONS
end

--==============================================================================
-- SHUTDOWN
--==============================================================================

--[[
    Shutdown the MapService

    Cleans up all map resources and stops event processing.
]]
function MapService:Shutdown()
    framework.Log("Info", "Shutting down MapService...")

    -- Stop environmental events
    self:StopEnvironmentalEvents()

    -- Clean up map visuals
    local mapFolder = workspace:FindFirstChild("Map")
    if mapFolder then
        mapFolder:Destroy()
    end

    -- Reset state
    activeBiomes = {}
    activePOIs = {}
    activeEvents = {}
    spawnPoints = {
        player = {},
        dinosaur = {},
        loot = {},
    }
    mapData = nil
    isInitialized = false

    framework.Log("Info", "MapService shutdown complete")
end

--==============================================================================
-- RETURN MODULE
--==============================================================================
return MapService
