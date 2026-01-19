--[[
    =========================================================================
    TerrainSetup - Procedural Terrain and Map Generation
    =========================================================================

    Creates a playable map environment when terrain assets aren't available.
    This service generates:
    - Base terrain (island shape with varied height)
    - Biome regions (jungle, volcanic, swamp, plains, coastal)
    - Basic POI structures (placeholder buildings)
    - Spawn platform for lobby

    This is meant for testing when actual terrain assets haven't been imported.
    In production, terrain would be loaded from saved models or InsertService.

    Usage:
        local TerrainSetup = framework:GetService("TerrainSetup")
        TerrainSetup:GenerateMap()

    =========================================================================
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local TerrainSetup = {}
TerrainSetup.__index = TerrainSetup

--=============================================================================
-- PRIVATE STATE
--=============================================================================

local framework = nil
local gameConfig = nil
local terrain = nil  -- Reference to Workspace.Terrain
local generatedParts = {}  -- Track generated parts for cleanup

--=============================================================================
-- CONFIGURATION
--=============================================================================

local MAP_CONFIG = {
    -- Island dimensions
    mapSize = 2048,           -- Total map size in studs
    islandRadius = 900,       -- Main island radius
    waterLevel = 0,           -- Sea level Y position

    -- Terrain heights
    baseHeight = 5,           -- Minimum terrain height
    maxHeight = 150,          -- Maximum terrain height (volcano peak)
    beachWidth = 50,          -- Beach transition zone

    -- Biome settings (from GameConfig)
    biomes = {
        jungle = { color = Color3.fromRGB(34, 139, 34), material = Enum.Material.Grass },
        volcanic = { color = Color3.fromRGB(50, 30, 30), material = Enum.Material.Basalt },
        swamp = { color = Color3.fromRGB(60, 80, 40), material = Enum.Material.Mud },
        plains = { color = Color3.fromRGB(124, 185, 72), material = Enum.Material.Grass },
        coastal = { color = Color3.fromRGB(194, 178, 128), material = Enum.Material.Sand },
    },

    -- POI placeholder settings
    poiHeight = 20,           -- Default building height
}

--=============================================================================
-- INITIALIZATION
--=============================================================================

function TerrainSetup:Initialize()
    -- Rojo maps to ReplicatedStorage.Framework and ReplicatedStorage.Shared
    framework = require(script.Parent.Parent.Framework)
    gameConfig = require(script.Parent.Parent.Shared.GameConfig)
    terrain = Workspace:FindFirstChild("Terrain") or Workspace.Terrain

    framework.Log("Info", "TerrainSetup initialized")
    return true
end

--=============================================================================
-- TERRAIN GENERATION
--=============================================================================

--[[
    Generate the complete game map
    Creates terrain, water, buildings, and flora
]]
function TerrainSetup:GenerateMap()
    framework.Log("Info", "Generating map...")

    -- Clear any existing generated content
    self:ClearGeneratedContent()

    -- Setup lighting for jungle atmosphere
    self:SetupLighting()

    -- Generate the island terrain
    self:GenerateIslandTerrain()

    -- Add water around the island
    self:GenerateWater()

    -- Create POI structures with interiors
    self:GeneratePOIs()

    -- Generate flora (trees, plants, rocks)
    self:GenerateFlora()

    -- Create lobby spawn platform
    self:GenerateLobbyArea()

    framework.Log("Info", "Map generation complete!")
    return true
end

--[[
    Setup atmospheric lighting
]]
function TerrainSetup:SetupLighting()
    Lighting.Ambient = Color3.fromRGB(100, 100, 100)
    Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
    Lighting.Brightness = 2
    Lighting.ClockTime = 14  -- 2 PM for good visibility
    Lighting.GeographicLatitude = 10  -- Tropical latitude
    Lighting.GlobalShadows = true

    -- Add atmosphere for hazy jungle feel
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if not atmosphere then
        atmosphere = Instance.new("Atmosphere")
        atmosphere.Parent = Lighting
    end
    atmosphere.Density = 0.3
    atmosphere.Offset = 0.1
    atmosphere.Color = Color3.fromRGB(199, 199, 199)
    atmosphere.Decay = Color3.fromRGB(92, 120, 92)
    atmosphere.Glare = 0.2
    atmosphere.Haze = 1

    framework.Log("Debug", "Lighting configured")
end

--[[
    Generate island terrain using Roblox terrain
]]
function TerrainSetup:GenerateIslandTerrain()
    local mapSize = MAP_CONFIG.mapSize
    local islandRadius = MAP_CONFIG.islandRadius
    local resolution = 64  -- Terrain cell size

    -- Clear existing terrain
    terrain:Clear()

    -- Generate terrain in chunks
    local halfSize = mapSize / 2

    for x = -halfSize, halfSize, resolution do
        for z = -halfSize, halfSize, resolution do
            local distFromCenter = math.sqrt(x*x + z*z)

            if distFromCenter < islandRadius then
                -- Calculate height based on distance from center and noise
                local normalizedDist = distFromCenter / islandRadius
                local heightFalloff = 1 - (normalizedDist ^ 2)  -- Smooth falloff

                -- Add noise for natural terrain
                local noise = math.noise(x / 200, z / 200) * 0.5 + 0.5
                local detailNoise = math.noise(x / 50, z / 50) * 0.3

                -- Calculate final height
                local baseHeight = MAP_CONFIG.baseHeight + (noise + detailNoise) * 50 * heightFalloff

                -- Add volcano peak in one corner
                local volcanoX, volcanoZ = -300, -300
                local volcanoDistSq = (x - volcanoX)^2 + (z - volcanoZ)^2
                local volcanoRadius = 200
                if volcanoDistSq < volcanoRadius^2 then
                    local volcanoFactor = 1 - math.sqrt(volcanoDistSq) / volcanoRadius
                    baseHeight = baseHeight + volcanoFactor * MAP_CONFIG.maxHeight
                end

                -- Determine material based on height and position
                local material = Enum.Material.Grass
                if baseHeight > 80 then
                    material = Enum.Material.Rock
                elseif baseHeight < MAP_CONFIG.baseHeight + 5 then
                    material = Enum.Material.Sand
                elseif distFromCenter > islandRadius - MAP_CONFIG.beachWidth then
                    material = Enum.Material.Sand
                end

                -- Fill terrain
                local region = Region3.new(
                    Vector3.new(x, 0, z),
                    Vector3.new(x + resolution, baseHeight, z + resolution)
                ):ExpandToGrid(4)

                terrain:FillRegion(region, 4, material)
            end
        end

        -- Yield periodically to prevent timeout
        if x % 256 == 0 then
            task.wait()
        end
    end

    framework.Log("Debug", "Island terrain generated")
end

--[[
    Generate water around the island
]]
function TerrainSetup:GenerateWater()
    local mapSize = MAP_CONFIG.mapSize
    local halfSize = mapSize / 2
    local waterLevel = MAP_CONFIG.waterLevel

    -- Fill water around island
    local waterRegion = Region3.new(
        Vector3.new(-halfSize, waterLevel - 50, -halfSize),
        Vector3.new(halfSize, waterLevel, halfSize)
    ):ExpandToGrid(4)

    terrain:FillRegion(waterRegion, 4, Enum.Material.Water)

    framework.Log("Debug", "Water generated")
end

--[[
    Generate POI structures with themed interiors and exteriors
    Based on best practices from Roblox developer community
]]
function TerrainSetup:GeneratePOIs()
    -- Get POI data from GameConfig
    local pois = gameConfig and gameConfig.Map and gameConfig.Map.POIs or {}

    -- Create a folder for POIs
    local poiFolder = Workspace:FindFirstChild("POIs")
    if not poiFolder then
        poiFolder = Instance.new("Folder")
        poiFolder.Name = "POIs"
        poiFolder.Parent = Workspace
    end

    -- POI-specific building configurations
    local poiConfigs = {
        visitor_center = {
            buildingType = "main_building",
            color = Color3.fromRGB(200, 190, 170),
            roofColor = Color3.fromRGB(139, 69, 19),
            floors = 2,
            hasLobby = true,
            furniture = {"reception_desk", "benches", "display_cases", "potted_plants"},
        },
        raptor_paddock = {
            buildingType = "enclosure",
            color = Color3.fromRGB(80, 80, 80),
            fenceColor = Color3.fromRGB(60, 60, 60),
            hasObservationDeck = true,
            furniture = {"control_panels", "warning_signs", "cages"},
        },
        trex_kingdom = {
            buildingType = "massive_enclosure",
            color = Color3.fromRGB(100, 90, 80),
            fenceColor = Color3.fromRGB(50, 50, 50),
            wallHeight = 30,
            furniture = {"viewing_platforms", "emergency_bunkers", "feeding_stations"},
        },
        genetics_lab = {
            buildingType = "lab",
            color = Color3.fromRGB(220, 220, 230),
            accentColor = Color3.fromRGB(100, 150, 200),
            floors = 3,
            furniture = {"lab_tables", "computers", "incubators", "storage_tanks"},
        },
        aviary = {
            buildingType = "dome",
            color = Color3.fromRGB(180, 200, 220),
            transparent = true,
            furniture = {"perches", "nests", "viewing_areas"},
        },
        docks = {
            buildingType = "warehouse",
            color = Color3.fromRGB(150, 140, 130),
            furniture = {"crates", "boats", "cranes", "storage_containers"},
        },
        communications = {
            buildingType = "tower",
            color = Color3.fromRGB(180, 180, 190),
            hasAntenna = true,
            furniture = {"radio_equipment", "servers", "desks"},
        },
        power_station = {
            buildingType = "industrial",
            color = Color3.fromRGB(120, 120, 130),
            accentColor = Color3.fromRGB(200, 180, 50),
            furniture = {"generators", "pipes", "control_room", "transformers"},
        },
    }

    -- Generate each POI
    for name, poiData in pairs(pois) do
        local position = poiData.position or Vector3.new(0, 0, 0)
        local size = poiData.size or 100
        local config = poiConfigs[name] or {buildingType = "generic", color = Color3.fromRGB(150, 150, 150)}

        -- Get terrain height at POI location
        local terrainHeight = self:GetTerrainHeight(position)

        -- Create POI ground/foundation
        local foundation = Instance.new("Part")
        foundation.Name = name .. "_Foundation"
        foundation.Size = Vector3.new(size, 1, size)
        foundation.Position = Vector3.new(position.X, terrainHeight + 0.5, position.Z)
        foundation.Anchored = true
        foundation.Material = Enum.Material.Concrete
        foundation.Color = Color3.fromRGB(100, 100, 100)
        foundation.Parent = poiFolder
        table.insert(generatedParts, foundation)

        -- Add POI label
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "Label"
        billboard.Size = UDim2.new(0, 250, 0, 60)
        billboard.StudsOffset = Vector3.new(0, 35, 0)
        billboard.MaxDistance = 500
        billboard.Parent = foundation

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 0.3
        label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.Text = string.gsub(name, "_", " "):upper()
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard

        -- Generate buildings based on type
        self:GeneratePOIBuilding(poiFolder, name, position, size, terrainHeight, config)
    end

    framework.Log("Debug", "POIs generated with detailed buildings")
end

--[[
    Generate a themed building for a POI
]]
function TerrainSetup:GeneratePOIBuilding(parent, poiName, position, size, terrainHeight, config)
    local buildingType = config.buildingType
    local baseY = terrainHeight + 1

    if buildingType == "main_building" or buildingType == "lab" then
        -- Multi-floor building with interior
        self:GenerateMultiFloorBuilding(parent, poiName, position, size, baseY, config)
    elseif buildingType == "enclosure" or buildingType == "massive_enclosure" then
        -- Fenced enclosure with observation areas
        self:GenerateEnclosure(parent, poiName, position, size, baseY, config)
    elseif buildingType == "dome" then
        -- Dome structure (aviary)
        self:GenerateDome(parent, poiName, position, size, baseY, config)
    elseif buildingType == "warehouse" then
        -- Warehouse with crates
        self:GenerateWarehouse(parent, poiName, position, size, baseY, config)
    elseif buildingType == "tower" then
        -- Communication tower
        self:GenerateTower(parent, poiName, position, size, baseY, config)
    elseif buildingType == "industrial" then
        -- Industrial building
        self:GenerateIndustrialBuilding(parent, poiName, position, size, baseY, config)
    else
        -- Generic building
        self:GenerateGenericBuilding(parent, poiName, position, size, baseY, config)
    end
end

--[[
    Generate a multi-floor building with interior rooms
]]
function TerrainSetup:GenerateMultiFloorBuilding(parent, name, position, size, baseY, config)
    local floors = config.floors or 2
    local floorHeight = 12
    local wallThickness = 2
    local buildingWidth = size * 0.6
    local buildingDepth = size * 0.5
    local color = config.color or Color3.fromRGB(200, 190, 170)
    local roofColor = config.roofColor or Color3.fromRGB(100, 80, 60)

    local buildingModel = Instance.new("Model")
    buildingModel.Name = name .. "_Building"

    -- Generate each floor
    for floor = 1, floors do
        local floorY = baseY + (floor - 1) * floorHeight

        -- Floor platform
        local floorPart = Instance.new("Part")
        floorPart.Name = "Floor" .. floor
        floorPart.Size = Vector3.new(buildingWidth, 1, buildingDepth)
        floorPart.Position = Vector3.new(position.X, floorY, position.Z)
        floorPart.Anchored = true
        floorPart.Material = Enum.Material.Concrete
        floorPart.Color = Color3.fromRGB(80, 80, 80)
        floorPart.Parent = buildingModel
        table.insert(generatedParts, floorPart)

        -- Walls with windows
        local walls = {
            {offset = Vector3.new(0, floorHeight/2, buildingDepth/2), size = Vector3.new(buildingWidth, floorHeight, wallThickness), windows = true},
            {offset = Vector3.new(0, floorHeight/2, -buildingDepth/2), size = Vector3.new(buildingWidth, floorHeight, wallThickness), windows = true},
            {offset = Vector3.new(buildingWidth/2, floorHeight/2, 0), size = Vector3.new(wallThickness, floorHeight, buildingDepth), windows = true},
            {offset = Vector3.new(-buildingWidth/2, floorHeight/2, 0), size = Vector3.new(wallThickness, floorHeight, buildingDepth), windows = true},
        }

        for i, wallData in ipairs(walls) do
            local wall = Instance.new("Part")
            wall.Name = "Wall" .. floor .. "_" .. i
            wall.Size = wallData.size
            wall.Position = Vector3.new(position.X, floorY, position.Z) + wallData.offset
            wall.Anchored = true
            wall.Material = Enum.Material.Concrete
            wall.Color = color
            wall.Parent = buildingModel
            table.insert(generatedParts, wall)

            -- Add windows
            if wallData.windows then
                self:AddWindows(wall, buildingModel)
            end
        end

        -- Add doorway on ground floor
        if floor == 1 then
            self:AddDoorway(buildingModel, Vector3.new(position.X, floorY, position.Z + buildingDepth/2), 8, floorHeight * 0.7)
        end

        -- Add interior furniture
        self:AddInteriorFurniture(buildingModel, position, floorY + 1, buildingWidth * 0.8, buildingDepth * 0.8, config.furniture or {})
    end

    -- Roof
    local roof = Instance.new("Part")
    roof.Name = "Roof"
    roof.Size = Vector3.new(buildingWidth + 4, 2, buildingDepth + 4)
    roof.Position = Vector3.new(position.X, baseY + floors * floorHeight + 1, position.Z)
    roof.Anchored = true
    roof.Material = Enum.Material.Slate
    roof.Color = roofColor
    roof.Parent = buildingModel
    table.insert(generatedParts, roof)

    buildingModel.Parent = parent
end

--[[
    Generate an enclosure with fencing
]]
function TerrainSetup:GenerateEnclosure(parent, name, position, size, baseY, config)
    local wallHeight = config.wallHeight or 15
    local fenceColor = config.fenceColor or Color3.fromRGB(60, 60, 60)

    local enclosureModel = Instance.new("Model")
    enclosureModel.Name = name .. "_Enclosure"

    -- Fence posts and walls
    local fenceSegments = 8
    for i = 1, fenceSegments do
        local angle = (i / fenceSegments) * math.pi * 2
        local nextAngle = ((i + 1) / fenceSegments) * math.pi * 2
        local radius = size * 0.45

        local x1 = position.X + math.cos(angle) * radius
        local z1 = position.Z + math.sin(angle) * radius
        local x2 = position.X + math.cos(nextAngle) * radius
        local z2 = position.Z + math.sin(nextAngle) * radius

        -- Fence post
        local post = Instance.new("Part")
        post.Name = "Post" .. i
        post.Size = Vector3.new(2, wallHeight, 2)
        post.Position = Vector3.new(x1, baseY + wallHeight/2, z1)
        post.Anchored = true
        post.Material = Enum.Material.Metal
        post.Color = fenceColor
        post.Parent = enclosureModel
        table.insert(generatedParts, post)

        -- Fence section (wire mesh look)
        local fenceLength = math.sqrt((x2-x1)^2 + (z2-z1)^2)
        local fenceAngle = math.atan2(z2-z1, x2-x1)

        local fence = Instance.new("Part")
        fence.Name = "Fence" .. i
        fence.Size = Vector3.new(fenceLength, wallHeight - 2, 0.5)
        fence.CFrame = CFrame.new((x1+x2)/2, baseY + wallHeight/2, (z1+z2)/2) * CFrame.Angles(0, -fenceAngle, 0)
        fence.Anchored = true
        fence.Material = Enum.Material.DiamondPlate
        fence.Color = fenceColor
        fence.Transparency = 0.3
        fence.Parent = enclosureModel
        table.insert(generatedParts, fence)
    end

    -- Observation deck
    if config.hasObservationDeck then
        local deckSize = 20
        local deck = Instance.new("Part")
        deck.Name = "ObservationDeck"
        deck.Size = Vector3.new(deckSize, 2, deckSize)
        deck.Position = Vector3.new(position.X + size * 0.3, baseY + wallHeight + 5, position.Z)
        deck.Anchored = true
        deck.Material = Enum.Material.Metal
        deck.Color = Color3.fromRGB(80, 80, 80)
        deck.Parent = enclosureModel
        table.insert(generatedParts, deck)

        -- Railing
        for _, offset in ipairs({{deckSize/2, 0}, {-deckSize/2, 0}, {0, deckSize/2}, {0, -deckSize/2}}) do
            local rail = Instance.new("Part")
            rail.Size = Vector3.new(offset[1] == 0 and deckSize or 1, 4, offset[2] == 0 and deckSize or 1)
            rail.Position = deck.Position + Vector3.new(offset[1], 2, offset[2])
            rail.Anchored = true
            rail.Material = Enum.Material.Metal
            rail.Color = Color3.fromRGB(60, 60, 60)
            rail.Parent = enclosureModel
            table.insert(generatedParts, rail)
        end
    end

    enclosureModel.Parent = parent
end

--[[
    Generate a dome structure (aviary)
]]
function TerrainSetup:GenerateDome(parent, name, position, size, baseY, config)
    local domeModel = Instance.new("Model")
    domeModel.Name = name .. "_Dome"

    local radius = size * 0.4
    local segments = 12

    -- Dome frame
    for i = 1, segments do
        local angle = (i / segments) * math.pi * 2

        -- Vertical arch
        local arch = Instance.new("Part")
        arch.Name = "Arch" .. i
        arch.Size = Vector3.new(2, radius * 1.5, 2)
        arch.CFrame = CFrame.new(
            position.X + math.cos(angle) * radius * 0.5,
            baseY + radius * 0.75,
            position.Z + math.sin(angle) * radius * 0.5
        ) * CFrame.Angles(0, -angle, math.rad(30))
        arch.Anchored = true
        arch.Material = Enum.Material.Metal
        arch.Color = config.color or Color3.fromRGB(180, 200, 220)
        arch.Parent = domeModel
        table.insert(generatedParts, arch)
    end

    -- Dome covering (transparent)
    local cover = Instance.new("Part")
    cover.Name = "Cover"
    cover.Shape = Enum.PartType.Ball
    cover.Size = Vector3.new(radius * 2, radius * 1.5, radius * 2)
    cover.Position = Vector3.new(position.X, baseY + radius * 0.5, position.Z)
    cover.Anchored = true
    cover.Material = Enum.Material.Glass
    cover.Color = Color3.fromRGB(200, 220, 240)
    cover.Transparency = 0.7
    cover.CanCollide = false
    cover.Parent = domeModel
    table.insert(generatedParts, cover)

    -- Entrance
    local entrance = Instance.new("Part")
    entrance.Name = "Entrance"
    entrance.Size = Vector3.new(15, 10, 10)
    entrance.Position = Vector3.new(position.X + radius * 0.6, baseY + 5, position.Z)
    entrance.Anchored = true
    entrance.Material = Enum.Material.Concrete
    entrance.Color = Color3.fromRGB(150, 150, 160)
    entrance.Parent = domeModel
    table.insert(generatedParts, entrance)

    domeModel.Parent = parent
end

--[[
    Generate a warehouse
]]
function TerrainSetup:GenerateWarehouse(parent, name, position, size, baseY, config)
    local warehouseModel = Instance.new("Model")
    warehouseModel.Name = name .. "_Warehouse"

    local width = size * 0.7
    local depth = size * 0.5
    local height = 15

    -- Main structure
    local building = Instance.new("Part")
    building.Name = "MainBuilding"
    building.Size = Vector3.new(width, height, depth)
    building.Position = Vector3.new(position.X, baseY + height/2, position.Z)
    building.Anchored = true
    building.Material = Enum.Material.Metal
    building.Color = config.color or Color3.fromRGB(150, 140, 130)
    building.Parent = warehouseModel
    table.insert(generatedParts, building)

    -- Large door
    local door = Instance.new("Part")
    door.Name = "Door"
    door.Size = Vector3.new(width * 0.4, height * 0.8, 1)
    door.Position = Vector3.new(position.X, baseY + height * 0.4, position.Z + depth/2)
    door.Anchored = true
    door.Material = Enum.Material.Metal
    door.Color = Color3.fromRGB(100, 100, 110)
    door.Parent = warehouseModel
    table.insert(generatedParts, door)

    -- Crates outside
    for i = 1, 8 do
        local crate = Instance.new("Part")
        crate.Name = "Crate" .. i
        local crateSize = math.random(3, 6)
        crate.Size = Vector3.new(crateSize, crateSize, crateSize)
        crate.Position = Vector3.new(
            position.X + math.random(-size/3, size/3),
            baseY + crateSize/2,
            position.Z + size/3 + math.random(5, 15)
        )
        crate.Anchored = true
        crate.Material = Enum.Material.Wood
        crate.Color = Color3.fromRGB(139, 90, 43)
        crate.Parent = warehouseModel
        table.insert(generatedParts, crate)
    end

    warehouseModel.Parent = parent
end

--[[
    Generate a communication tower
]]
function TerrainSetup:GenerateTower(parent, name, position, size, baseY, config)
    local towerModel = Instance.new("Model")
    towerModel.Name = name .. "_Tower"

    local towerHeight = 60

    -- Base building
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(20, 10, 20)
    base.Position = Vector3.new(position.X, baseY + 5, position.Z)
    base.Anchored = true
    base.Material = Enum.Material.Concrete
    base.Color = config.color or Color3.fromRGB(180, 180, 190)
    base.Parent = towerModel
    table.insert(generatedParts, base)

    -- Tower structure
    for i = 1, 4 do
        local section = Instance.new("Part")
        section.Name = "TowerSection" .. i
        local sectionWidth = 6 - i * 0.8
        section.Size = Vector3.new(sectionWidth, towerHeight / 4, sectionWidth)
        section.Position = Vector3.new(position.X, baseY + 10 + (i - 0.5) * towerHeight / 4, position.Z)
        section.Anchored = true
        section.Material = Enum.Material.Metal
        section.Color = Color3.fromRGB(200, 50, 50)
        section.Parent = towerModel
        table.insert(generatedParts, section)
    end

    -- Antenna
    if config.hasAntenna then
        local antenna = Instance.new("Part")
        antenna.Name = "Antenna"
        antenna.Size = Vector3.new(1, 15, 1)
        antenna.Position = Vector3.new(position.X, baseY + 10 + towerHeight + 7.5, position.Z)
        antenna.Anchored = true
        antenna.Material = Enum.Material.Metal
        antenna.Color = Color3.fromRGB(150, 150, 150)
        antenna.Parent = towerModel
        table.insert(generatedParts, antenna)

        -- Dish
        local dish = Instance.new("Part")
        dish.Name = "Dish"
        dish.Size = Vector3.new(8, 8, 2)
        dish.Position = Vector3.new(position.X + 3, baseY + towerHeight * 0.7, position.Z)
        dish.Anchored = true
        dish.Material = Enum.Material.Metal
        dish.Color = Color3.fromRGB(220, 220, 220)
        dish.Parent = towerModel
        table.insert(generatedParts, dish)
    end

    towerModel.Parent = parent
end

--[[
    Generate an industrial building
]]
function TerrainSetup:GenerateIndustrialBuilding(parent, name, position, size, baseY, config)
    local industrialModel = Instance.new("Model")
    industrialModel.Name = name .. "_Industrial"

    local width = size * 0.6
    local depth = size * 0.5
    local height = 12

    -- Main building
    local building = Instance.new("Part")
    building.Name = "MainBuilding"
    building.Size = Vector3.new(width, height, depth)
    building.Position = Vector3.new(position.X, baseY + height/2, position.Z)
    building.Anchored = true
    building.Material = Enum.Material.Metal
    building.Color = config.color or Color3.fromRGB(120, 120, 130)
    building.Parent = industrialModel
    table.insert(generatedParts, building)

    -- Smokestacks
    for i = 1, 2 do
        local stack = Instance.new("Part")
        stack.Name = "Smokestack" .. i
        stack.Shape = Enum.PartType.Cylinder
        stack.Size = Vector3.new(25, 4, 4)
        stack.CFrame = CFrame.new(
            position.X + (i == 1 and -width/4 or width/4),
            baseY + height + 12.5,
            position.Z - depth/4
        ) * CFrame.Angles(0, 0, math.rad(90))
        stack.Anchored = true
        stack.Material = Enum.Material.Metal
        stack.Color = Color3.fromRGB(80, 80, 80)
        stack.Parent = industrialModel
        table.insert(generatedParts, stack)
    end

    -- Pipes
    for i = 1, 4 do
        local pipe = Instance.new("Part")
        pipe.Name = "Pipe" .. i
        pipe.Shape = Enum.PartType.Cylinder
        pipe.Size = Vector3.new(15, 2, 2)
        pipe.CFrame = CFrame.new(
            position.X + width/2 + 5,
            baseY + i * 3,
            position.Z + math.random(-depth/4, depth/4)
        ) * CFrame.Angles(0, 0, math.rad(90))
        pipe.Anchored = true
        pipe.Material = Enum.Material.Metal
        pipe.Color = config.accentColor or Color3.fromRGB(200, 180, 50)
        pipe.Parent = industrialModel
        table.insert(generatedParts, pipe)
    end

    industrialModel.Parent = parent
end

--[[
    Generate a generic building
]]
function TerrainSetup:GenerateGenericBuilding(parent, name, position, size, baseY, config)
    local buildingModel = Instance.new("Model")
    buildingModel.Name = name .. "_Building"

    local width = math.random(15, 25)
    local depth = math.random(15, 25)
    local height = math.random(10, 20)

    local building = Instance.new("Part")
    building.Name = "MainBuilding"
    building.Size = Vector3.new(width, height, depth)
    building.Position = Vector3.new(position.X, baseY + height/2, position.Z)
    building.Anchored = true
    building.Material = Enum.Material.Concrete
    building.Color = config.color or Color3.fromRGB(150, 150, 150)
    building.Parent = buildingModel
    table.insert(generatedParts, building)

    self:AddWindows(building, buildingModel)
    self:AddDoorway(buildingModel, Vector3.new(position.X, baseY, position.Z + depth/2), 6, 8)

    buildingModel.Parent = parent
end

--[[
    Add windows to a wall
]]
function TerrainSetup:AddWindows(wall, parent)
    local wallSize = wall.Size
    local windowsX = math.floor(wallSize.X / 8)
    local windowsY = math.floor(wallSize.Y / 6)

    for wx = 1, math.max(1, windowsX) do
        for wy = 1, math.max(1, windowsY) do
            local window = Instance.new("Part")
            window.Name = "Window"
            window.Size = Vector3.new(
                wallSize.X < wallSize.Z and 0.5 or 3,
                3,
                wallSize.Z < wallSize.X and 0.5 or 3
            )
            window.Position = wall.Position + Vector3.new(
                (wx - windowsX/2 - 0.5) * 6 * (wallSize.X > wallSize.Z and 1 or 0),
                (wy - windowsY/2 - 0.5) * 5,
                (wx - windowsX/2 - 0.5) * 6 * (wallSize.Z > wallSize.X and 1 or 0)
            )
            window.Anchored = true
            window.Material = Enum.Material.Glass
            window.Color = Color3.fromRGB(150, 200, 255)
            window.Transparency = 0.5
            window.Parent = parent
            table.insert(generatedParts, window)
        end
    end
end

--[[
    Add a doorway
]]
function TerrainSetup:AddDoorway(parent, position, width, height)
    local door = Instance.new("Part")
    door.Name = "Door"
    door.Size = Vector3.new(width, height, 1)
    door.Position = Vector3.new(position.X, position.Y + height/2, position.Z)
    door.Anchored = true
    door.Material = Enum.Material.Wood
    door.Color = Color3.fromRGB(101, 67, 33)
    door.Parent = parent
    table.insert(generatedParts, door)

    -- Door frame
    local frame = Instance.new("Part")
    frame.Name = "DoorFrame"
    frame.Size = Vector3.new(width + 2, height + 1, 0.5)
    frame.Position = Vector3.new(position.X, position.Y + height/2, position.Z + 0.5)
    frame.Anchored = true
    frame.Material = Enum.Material.Metal
    frame.Color = Color3.fromRGB(60, 60, 60)
    frame.Parent = parent
    table.insert(generatedParts, frame)
end

--[[
    Add interior furniture based on room type
]]
function TerrainSetup:AddInteriorFurniture(parent, position, floorY, width, depth, furnitureTypes)
    for _, furnitureType in ipairs(furnitureTypes) do
        if furnitureType == "reception_desk" then
            local desk = Instance.new("Part")
            desk.Name = "ReceptionDesk"
            desk.Size = Vector3.new(8, 4, 3)
            desk.Position = Vector3.new(position.X, floorY + 2, position.Z)
            desk.Anchored = true
            desk.Material = Enum.Material.Wood
            desk.Color = Color3.fromRGB(139, 90, 43)
            desk.Parent = parent
            table.insert(generatedParts, desk)
        elseif furnitureType == "benches" then
            for i = 1, 3 do
                local bench = Instance.new("Part")
                bench.Name = "Bench" .. i
                bench.Size = Vector3.new(6, 2, 2)
                bench.Position = Vector3.new(position.X + (i-2) * 8, floorY + 1, position.Z - depth/3)
                bench.Anchored = true
                bench.Material = Enum.Material.Wood
                bench.Color = Color3.fromRGB(101, 67, 33)
                bench.Parent = parent
                table.insert(generatedParts, bench)
            end
        elseif furnitureType == "lab_tables" then
            for i = 1, 4 do
                local table_ = Instance.new("Part")
                table_.Name = "LabTable" .. i
                table_.Size = Vector3.new(6, 3, 3)
                table_.Position = Vector3.new(
                    position.X + (i % 2 == 0 and width/4 or -width/4),
                    floorY + 1.5,
                    position.Z + (i > 2 and depth/4 or -depth/4)
                )
                table_.Anchored = true
                table_.Material = Enum.Material.Metal
                table_.Color = Color3.fromRGB(200, 200, 210)
                table_.Parent = parent
                table.insert(generatedParts, table_)
            end
        elseif furnitureType == "computers" then
            for i = 1, 2 do
                local computer = Instance.new("Part")
                computer.Name = "Computer" .. i
                computer.Size = Vector3.new(2, 2, 1)
                computer.Position = Vector3.new(position.X + (i == 1 and -3 or 3), floorY + 4, position.Z)
                computer.Anchored = true
                computer.Material = Enum.Material.Plastic
                computer.Color = Color3.fromRGB(50, 50, 50)
                computer.Parent = parent
                table.insert(generatedParts, computer)

                -- Screen glow
                local screen = Instance.new("Part")
                screen.Name = "Screen" .. i
                screen.Size = Vector3.new(1.8, 1.5, 0.1)
                screen.Position = computer.Position + Vector3.new(0, 0, 0.5)
                screen.Anchored = true
                screen.Material = Enum.Material.Neon
                screen.Color = Color3.fromRGB(100, 200, 255)
                screen.Parent = parent
                table.insert(generatedParts, screen)
            end
        end
    end
end

--[[
    Get terrain height at position using raycast
]]
function TerrainSetup:GetTerrainHeight(position)
    local rayOrigin = Vector3.new(position.X, 500, position.Z)
    local rayDirection = Vector3.new(0, -1000, 0)

    local result = Workspace:Raycast(rayOrigin, rayDirection)

    if result then
        return result.Position.Y
    end

    return MAP_CONFIG.baseHeight
end

--[[
    Generate the lobby spawn area
]]
function TerrainSetup:GenerateLobbyArea()
    -- Create lobby platform above the island center
    local lobbyPlatform = Instance.new("Part")
    lobbyPlatform.Name = "LobbyPlatform"
    lobbyPlatform.Size = Vector3.new(100, 5, 100)
    lobbyPlatform.Position = Vector3.new(0, MAP_CONFIG.baseHeight + 50, 0)
    lobbyPlatform.Anchored = true
    lobbyPlatform.Material = Enum.Material.SmoothPlastic
    lobbyPlatform.Color = Color3.fromRGB(50, 150, 200)
    lobbyPlatform.Transparency = 0.3
    lobbyPlatform.Parent = Workspace

    -- Add spawn location
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "LobbySpawn"
    spawn.Size = Vector3.new(6, 1, 6)
    spawn.Position = lobbyPlatform.Position + Vector3.new(0, 3, 0)
    spawn.Anchored = true
    spawn.Neutral = true
    spawn.CanCollide = false
    spawn.Transparency = 1
    spawn.Parent = Workspace

    -- Add welcome sign
    local sign = Instance.new("Part")
    sign.Name = "LobbySign"
    sign.Size = Vector3.new(40, 20, 1)
    sign.Position = lobbyPlatform.Position + Vector3.new(0, 15, -45)
    sign.Anchored = true
    sign.Material = Enum.Material.Neon
    sign.Color = Color3.fromRGB(0, 200, 100)
    sign.Parent = Workspace

    local signGui = Instance.new("SurfaceGui")
    signGui.Face = Enum.NormalId.Front
    signGui.Parent = sign

    local signText = Instance.new("TextLabel")
    signText.Size = UDim2.new(1, 0, 1, 0)
    signText.BackgroundTransparency = 1
    signText.TextColor3 = Color3.fromRGB(255, 255, 255)
    signText.Text = "DINO ROYALE 2"
    signText.TextScaled = true
    signText.Font = Enum.Font.GothamBlack
    signText.Parent = signGui

    table.insert(generatedParts, lobbyPlatform)
    table.insert(generatedParts, spawn)
    table.insert(generatedParts, sign)

    framework.Log("Debug", "Lobby area generated")
end

--=============================================================================
-- FLORA GENERATION
-- Procedural trees, plants, flowers, and rocks based on biome
-- Uses techniques from open-source procedural tree generation
--=============================================================================

--[[
    Generate flora across the map based on biome types
    Uses Perlin noise for natural distribution patterns
]]
function TerrainSetup:GenerateFlora()
    framework.Log("Info", "Generating flora...")

    -- Create flora folder
    local floraFolder = Workspace:FindFirstChild("Flora")
    if not floraFolder then
        floraFolder = Instance.new("Folder")
        floraFolder.Name = "Flora"
        floraFolder.Parent = Workspace
    end

    local islandRadius = MAP_CONFIG.islandRadius
    local treesGenerated = 0
    local rocksGenerated = 0
    local plantsGenerated = 0

    -- Generate flora in a grid pattern with noise-based density
    local gridSpacing = 40  -- Check every 40 studs
    local halfSize = MAP_CONFIG.mapSize / 2

    for x = -halfSize, halfSize, gridSpacing do
        for z = -halfSize, halfSize, gridSpacing do
            local distFromCenter = math.sqrt(x*x + z*z)

            -- Only generate within island bounds (with margin)
            if distFromCenter < islandRadius - 60 then
                -- Use noise to determine flora density at this location
                local densityNoise = math.noise(x / 150, z / 150) * 0.5 + 0.5
                local biome = self:GetBiomeAt(x, z, distFromCenter)

                -- Skip if near POIs (check distance to all POI positions)
                local nearPOI = self:IsNearPOI(x, z, 80)
                if nearPOI then
                    densityNoise = densityNoise * 0.2  -- Much less flora near buildings
                end

                -- Generate trees
                if densityNoise > 0.3 and math.random() < self:GetTreeChance(biome) then
                    local terrainHeight = self:GetTerrainHeight(Vector3.new(x, 0, z))
                    if terrainHeight > 3 then  -- Above water
                        local offsetX = (math.random() - 0.5) * gridSpacing * 0.8
                        local offsetZ = (math.random() - 0.5) * gridSpacing * 0.8
                        self:GenerateTree(floraFolder, Vector3.new(x + offsetX, terrainHeight, z + offsetZ), biome)
                        treesGenerated = treesGenerated + 1
                    end
                end

                -- Generate rocks
                if densityNoise > 0.4 and math.random() < self:GetRockChance(biome) then
                    local terrainHeight = self:GetTerrainHeight(Vector3.new(x, 0, z))
                    if terrainHeight > 2 then
                        local offsetX = (math.random() - 0.5) * gridSpacing * 0.6
                        local offsetZ = (math.random() - 0.5) * gridSpacing * 0.6
                        self:GenerateRock(floraFolder, Vector3.new(x + offsetX, terrainHeight, z + offsetZ), biome)
                        rocksGenerated = rocksGenerated + 1
                    end
                end

                -- Generate ground plants/flowers
                if densityNoise > 0.25 and math.random() < self:GetPlantChance(biome) then
                    local terrainHeight = self:GetTerrainHeight(Vector3.new(x, 0, z))
                    if terrainHeight > 3 then
                        for _ = 1, math.random(2, 5) do
                            local offsetX = (math.random() - 0.5) * gridSpacing * 0.9
                            local offsetZ = (math.random() - 0.5) * gridSpacing * 0.9
                            self:GeneratePlant(floraFolder, Vector3.new(x + offsetX, terrainHeight, z + offsetZ), biome)
                            plantsGenerated = plantsGenerated + 1
                        end
                    end
                end
            end
        end

        -- Yield to prevent timeout
        if x % 200 == 0 then
            task.wait()
        end
    end

    framework.Log("Info", "Flora generated: %d trees, %d rocks, %d plants", treesGenerated, rocksGenerated, plantsGenerated)
end

--[[
    Determine biome type based on position
]]
function TerrainSetup:GetBiomeAt(x, z, distFromCenter)
    local islandRadius = MAP_CONFIG.islandRadius
    local normalizedDist = distFromCenter / islandRadius

    -- Volcanic area (corner)
    local volcanoX, volcanoZ = -300, -300
    local volcanoDistSq = (x - volcanoX)^2 + (z - volcanoZ)^2
    if volcanoDistSq < 250^2 then
        return "volcanic"
    end

    -- Coastal (outer ring)
    if normalizedDist > 0.85 then
        return "coastal"
    end

    -- Swamp (lower areas, use noise)
    local swampNoise = math.noise(x / 300, z / 300)
    if swampNoise < -0.2 and normalizedDist > 0.3 then
        return "swamp"
    end

    -- Plains (flatter areas)
    local terrainHeight = self:GetTerrainHeight(Vector3.new(x, 0, z))
    if terrainHeight < 15 and normalizedDist < 0.6 then
        return "plains"
    end

    -- Default: jungle
    return "jungle"
end

--[[
    Check if position is near a POI
]]
function TerrainSetup:IsNearPOI(x, z, minDistance)
    local pois = gameConfig and gameConfig.Map and gameConfig.Map.POIs or {}
    for _, poiData in pairs(pois) do
        local pos = poiData.position or Vector3.new(0, 0, 0)
        local dist = math.sqrt((x - pos.X)^2 + (z - pos.Z)^2)
        if dist < minDistance then
            return true
        end
    end
    return false
end

--[[
    Get tree spawn chance based on biome
]]
function TerrainSetup:GetTreeChance(biome)
    local chances = {
        jungle = 0.7,
        plains = 0.3,
        swamp = 0.5,
        volcanic = 0.1,
        coastal = 0.2,
    }
    return chances[biome] or 0.4
end

--[[
    Get rock spawn chance based on biome
]]
function TerrainSetup:GetRockChance(biome)
    local chances = {
        jungle = 0.2,
        plains = 0.15,
        swamp = 0.1,
        volcanic = 0.5,
        coastal = 0.3,
    }
    return chances[biome] or 0.2
end

--[[
    Get plant spawn chance based on biome
]]
function TerrainSetup:GetPlantChance(biome)
    local chances = {
        jungle = 0.8,
        plains = 0.6,
        swamp = 0.7,
        volcanic = 0.1,
        coastal = 0.4,
    }
    return chances[biome] or 0.5
end

--[[
    Generate a procedural tree
    Uses segmented branches for natural look (inspired by open-source techniques)
]]
function TerrainSetup:GenerateTree(parent, position, biome)
    local treeModel = Instance.new("Model")
    treeModel.Name = "Tree"

    -- Tree parameters based on biome
    local treeParams = self:GetTreeParams(biome)
    local trunkHeight = treeParams.trunkHeight + math.random(-3, 3)
    local trunkWidth = treeParams.trunkWidth * (0.8 + math.random() * 0.4)
    local canopySize = treeParams.canopySize * (0.8 + math.random() * 0.4)
    local trunkColor = treeParams.trunkColor
    local leafColor = treeParams.leafColor

    -- Create trunk (multiple segments for natural look)
    local segments = math.random(2, 4)
    local segmentHeight = trunkHeight / segments
    local prevTop = position

    for i = 1, segments do
        local segmentWidth = trunkWidth * (1 - (i - 1) * 0.15)
        local trunk = Instance.new("Part")
        trunk.Name = "Trunk" .. i
        trunk.Size = Vector3.new(segmentWidth, segmentHeight, segmentWidth)

        -- Slight random tilt for each segment
        local tiltX = (math.random() - 0.5) * 0.1
        local tiltZ = (math.random() - 0.5) * 0.1
        trunk.CFrame = CFrame.new(prevTop + Vector3.new(tiltX * i, segmentHeight / 2, tiltZ * i))

        trunk.Anchored = true
        trunk.Material = Enum.Material.Wood
        trunk.Color = trunkColor
        trunk.CanCollide = true  -- Trunk has collision
        trunk.Parent = treeModel
        table.insert(generatedParts, trunk)

        prevTop = trunk.Position + Vector3.new(0, segmentHeight / 2, 0)
    end

    -- Create canopy (leaf clusters)
    local canopyStyle = treeParams.canopyStyle or "round"

    if canopyStyle == "round" then
        -- Round canopy (jungle, plains trees)
        local canopy = Instance.new("Part")
        canopy.Name = "Canopy"
        canopy.Shape = Enum.PartType.Ball
        canopy.Size = Vector3.new(canopySize, canopySize * 0.8, canopySize)
        canopy.Position = prevTop + Vector3.new(0, canopySize * 0.3, 0)
        canopy.Anchored = true
        canopy.Material = Enum.Material.Grass
        canopy.Color = leafColor
        canopy.CanCollide = false  -- Canopy has no collision (best practice)
        canopy.CastShadow = true
        canopy.Parent = treeModel
        table.insert(generatedParts, canopy)

        -- Add secondary leaf clusters for fuller look
        for j = 1, math.random(2, 4) do
            local cluster = Instance.new("Part")
            cluster.Name = "LeafCluster" .. j
            cluster.Shape = Enum.PartType.Ball
            local clusterSize = canopySize * (0.4 + math.random() * 0.3)
            cluster.Size = Vector3.new(clusterSize, clusterSize * 0.7, clusterSize)
            local angle = (j / 4) * math.pi * 2
            cluster.Position = canopy.Position + Vector3.new(
                math.cos(angle) * canopySize * 0.4,
                (math.random() - 0.5) * canopySize * 0.3,
                math.sin(angle) * canopySize * 0.4
            )
            cluster.Anchored = true
            cluster.Material = Enum.Material.Grass
            cluster.Color = leafColor
            cluster.CanCollide = false
            cluster.CastShadow = true
            cluster.Parent = treeModel
            table.insert(generatedParts, cluster)
        end

    elseif canopyStyle == "palm" then
        -- Palm tree (coastal)
        for j = 1, 6 do
            local frond = Instance.new("Part")
            frond.Name = "Frond" .. j
            frond.Size = Vector3.new(1, 0.5, canopySize * 0.8)
            local angle = (j / 6) * math.pi * 2
            frond.CFrame = CFrame.new(prevTop) *
                CFrame.Angles(0, angle, math.rad(-45)) *
                CFrame.new(0, 0, canopySize * 0.3)
            frond.Anchored = true
            frond.Material = Enum.Material.Grass
            frond.Color = leafColor
            frond.CanCollide = false
            frond.Parent = treeModel
            table.insert(generatedParts, frond)
        end

    elseif canopyStyle == "dead" then
        -- Dead/volcanic tree (minimal branches)
        for j = 1, math.random(2, 4) do
            local branch = Instance.new("Part")
            branch.Name = "DeadBranch" .. j
            branch.Size = Vector3.new(0.5, canopySize * 0.4, 0.5)
            local angle = (j / 4) * math.pi * 2
            branch.CFrame = CFrame.new(prevTop) *
                CFrame.Angles(math.rad(-30), angle, 0) *
                CFrame.new(0, canopySize * 0.15, 0)
            branch.Anchored = true
            branch.Material = Enum.Material.Wood
            branch.Color = Color3.fromRGB(60, 50, 40)
            branch.CanCollide = false
            branch.Parent = treeModel
            table.insert(generatedParts, branch)
        end

    elseif canopyStyle == "willow" then
        -- Swamp willow tree (hanging branches)
        local mainCanopy = Instance.new("Part")
        mainCanopy.Name = "Canopy"
        mainCanopy.Shape = Enum.PartType.Ball
        mainCanopy.Size = Vector3.new(canopySize * 0.6, canopySize * 0.4, canopySize * 0.6)
        mainCanopy.Position = prevTop + Vector3.new(0, canopySize * 0.2, 0)
        mainCanopy.Anchored = true
        mainCanopy.Material = Enum.Material.Grass
        mainCanopy.Color = leafColor
        mainCanopy.CanCollide = false
        mainCanopy.Parent = treeModel
        table.insert(generatedParts, mainCanopy)

        -- Hanging vines/branches
        for j = 1, 8 do
            local vine = Instance.new("Part")
            vine.Name = "Vine" .. j
            vine.Size = Vector3.new(0.3, canopySize * 0.6, 0.3)
            local angle = (j / 8) * math.pi * 2
            vine.Position = mainCanopy.Position + Vector3.new(
                math.cos(angle) * canopySize * 0.25,
                -canopySize * 0.3,
                math.sin(angle) * canopySize * 0.25
            )
            vine.Anchored = true
            vine.Material = Enum.Material.Grass
            vine.Color = Color3.fromRGB(50, 80, 50)
            vine.CanCollide = false
            vine.Parent = treeModel
            table.insert(generatedParts, vine)
        end
    end

    treeModel.Parent = parent
end

--[[
    Get tree parameters based on biome
]]
function TerrainSetup:GetTreeParams(biome)
    local params = {
        jungle = {
            trunkHeight = 18,
            trunkWidth = 3,
            canopySize = 15,
            trunkColor = Color3.fromRGB(101, 67, 33),
            leafColor = Color3.fromRGB(34, 139, 34),
            canopyStyle = "round",
        },
        plains = {
            trunkHeight = 12,
            trunkWidth = 2,
            canopySize = 10,
            trunkColor = Color3.fromRGB(139, 90, 43),
            leafColor = Color3.fromRGB(107, 142, 35),
            canopyStyle = "round",
        },
        swamp = {
            trunkHeight = 14,
            trunkWidth = 2.5,
            canopySize = 12,
            trunkColor = Color3.fromRGB(80, 60, 40),
            leafColor = Color3.fromRGB(85, 107, 47),
            canopyStyle = "willow",
        },
        volcanic = {
            trunkHeight = 8,
            trunkWidth = 1.5,
            canopySize = 6,
            trunkColor = Color3.fromRGB(50, 40, 30),
            leafColor = Color3.fromRGB(60, 60, 50),
            canopyStyle = "dead",
        },
        coastal = {
            trunkHeight = 15,
            trunkWidth = 1.5,
            canopySize = 8,
            trunkColor = Color3.fromRGB(160, 130, 90),
            leafColor = Color3.fromRGB(60, 150, 60),
            canopyStyle = "palm",
        },
    }
    return params[biome] or params.jungle
end

--[[
    Generate a rock formation
]]
function TerrainSetup:GenerateRock(parent, position, biome)
    local rockModel = Instance.new("Model")
    rockModel.Name = "Rock"

    -- Rock parameters based on biome
    local rockColors = {
        jungle = Color3.fromRGB(100, 100, 90),
        plains = Color3.fromRGB(140, 130, 120),
        swamp = Color3.fromRGB(70, 80, 70),
        volcanic = Color3.fromRGB(40, 35, 35),
        coastal = Color3.fromRGB(180, 170, 160),
    }
    local rockColor = rockColors[biome] or Color3.fromRGB(120, 120, 110)

    -- Main rock
    local rockSize = 3 + math.random() * 5
    local mainRock = Instance.new("Part")
    mainRock.Name = "MainRock"
    mainRock.Size = Vector3.new(rockSize, rockSize * 0.7, rockSize * 0.9)
    mainRock.Position = position + Vector3.new(0, rockSize * 0.3, 0)
    mainRock.CFrame = mainRock.CFrame * CFrame.Angles(
        (math.random() - 0.5) * 0.3,
        math.random() * math.pi * 2,
        (math.random() - 0.5) * 0.3
    )
    mainRock.Anchored = true
    mainRock.Material = Enum.Material.Rock
    mainRock.Color = rockColor
    mainRock.CanCollide = true
    mainRock.Parent = rockModel
    table.insert(generatedParts, mainRock)

    -- Sometimes add smaller rocks around
    if math.random() > 0.5 then
        for i = 1, math.random(1, 3) do
            local smallRock = Instance.new("Part")
            smallRock.Name = "SmallRock" .. i
            local smallSize = rockSize * (0.2 + math.random() * 0.3)
            smallRock.Size = Vector3.new(smallSize, smallSize * 0.8, smallSize)
            smallRock.Position = position + Vector3.new(
                (math.random() - 0.5) * rockSize * 1.5,
                smallSize * 0.3,
                (math.random() - 0.5) * rockSize * 1.5
            )
            smallRock.CFrame = smallRock.CFrame * CFrame.Angles(
                math.random() * 0.5,
                math.random() * math.pi * 2,
                math.random() * 0.5
            )
            smallRock.Anchored = true
            smallRock.Material = Enum.Material.Rock
            smallRock.Color = rockColor
            smallRock.CanCollide = true
            smallRock.Parent = rockModel
            table.insert(generatedParts, smallRock)
        end
    end

    rockModel.Parent = parent
end

--[[
    Generate ground plants/flowers
]]
function TerrainSetup:GeneratePlant(parent, position, biome)
    local plantModel = Instance.new("Model")
    plantModel.Name = "Plant"

    -- Plant type based on biome
    local plantType = self:GetPlantType(biome)

    if plantType == "flower" then
        -- Flower
        local stemHeight = 0.5 + math.random() * 1
        local stem = Instance.new("Part")
        stem.Name = "Stem"
        stem.Size = Vector3.new(0.1, stemHeight, 0.1)
        stem.Position = position + Vector3.new(0, stemHeight / 2, 0)
        stem.Anchored = true
        stem.Material = Enum.Material.Grass
        stem.Color = Color3.fromRGB(50, 120, 50)
        stem.CanCollide = false
        stem.Parent = plantModel
        table.insert(generatedParts, stem)

        -- Flower head
        local flowerColors = {
            Color3.fromRGB(255, 100, 100),
            Color3.fromRGB(255, 200, 100),
            Color3.fromRGB(200, 100, 255),
            Color3.fromRGB(255, 255, 100),
            Color3.fromRGB(255, 150, 200),
        }
        local flower = Instance.new("Part")
        flower.Name = "Flower"
        flower.Shape = Enum.PartType.Ball
        flower.Size = Vector3.new(0.4, 0.4, 0.4)
        flower.Position = position + Vector3.new(0, stemHeight + 0.2, 0)
        flower.Anchored = true
        flower.Material = Enum.Material.SmoothPlastic
        flower.Color = flowerColors[math.random(#flowerColors)]
        flower.CanCollide = false
        flower.Parent = plantModel
        table.insert(generatedParts, flower)

    elseif plantType == "fern" then
        -- Fern (jungle/swamp)
        local fernSize = 1 + math.random() * 2
        for i = 1, math.random(4, 8) do
            local frond = Instance.new("Part")
            frond.Name = "Frond" .. i
            frond.Size = Vector3.new(0.2, fernSize * 0.8, 0.8)
            local angle = (i / 8) * math.pi * 2
            frond.CFrame = CFrame.new(position) *
                CFrame.Angles(0, angle, math.rad(-60)) *
                CFrame.new(0, fernSize * 0.3, 0)
            frond.Anchored = true
            frond.Material = Enum.Material.Grass
            frond.Color = Color3.fromRGB(40, 100, 40)
            frond.CanCollide = false
            frond.Parent = plantModel
            table.insert(generatedParts, frond)
        end

    elseif plantType == "grass_tuft" then
        -- Grass tuft
        local grassCount = math.random(5, 12)
        for i = 1, grassCount do
            local blade = Instance.new("Part")
            blade.Name = "Blade" .. i
            local height = 0.5 + math.random() * 1.5
            blade.Size = Vector3.new(0.1, height, 0.1)
            blade.CFrame = CFrame.new(position + Vector3.new(
                (math.random() - 0.5) * 1,
                height / 2,
                (math.random() - 0.5) * 1
            )) * CFrame.Angles((math.random() - 0.5) * 0.3, 0, (math.random() - 0.5) * 0.3)
            blade.Anchored = true
            blade.Material = Enum.Material.Grass
            blade.Color = Color3.fromRGB(80, 140, 80)
            blade.CanCollide = false
            blade.Parent = plantModel
            table.insert(generatedParts, blade)
        end

    elseif plantType == "mushroom" then
        -- Mushroom (swamp)
        local stemHeight = 0.3 + math.random() * 0.5
        local stem = Instance.new("Part")
        stem.Name = "Stem"
        stem.Shape = Enum.PartType.Cylinder
        stem.Size = Vector3.new(stemHeight, 0.3, 0.3)
        stem.CFrame = CFrame.new(position + Vector3.new(0, stemHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
        stem.Anchored = true
        stem.Material = Enum.Material.SmoothPlastic
        stem.Color = Color3.fromRGB(230, 220, 200)
        stem.CanCollide = false
        stem.Parent = plantModel
        table.insert(generatedParts, stem)

        local cap = Instance.new("Part")
        cap.Name = "Cap"
        cap.Shape = Enum.PartType.Ball
        cap.Size = Vector3.new(0.6, 0.3, 0.6)
        cap.Position = position + Vector3.new(0, stemHeight + 0.1, 0)
        cap.Anchored = true
        cap.Material = Enum.Material.SmoothPlastic
        cap.Color = Color3.fromRGB(180, 50, 50)
        cap.CanCollide = false
        cap.Parent = plantModel
        table.insert(generatedParts, cap)

    elseif plantType == "cactus" then
        -- Small cactus (volcanic/dry areas)
        local height = 1 + math.random() * 2
        local cactus = Instance.new("Part")
        cactus.Name = "Cactus"
        cactus.Size = Vector3.new(0.8, height, 0.8)
        cactus.Position = position + Vector3.new(0, height / 2, 0)
        cactus.Anchored = true
        cactus.Material = Enum.Material.SmoothPlastic
        cactus.Color = Color3.fromRGB(50, 100, 50)
        cactus.CanCollide = false
        cactus.Parent = plantModel
        table.insert(generatedParts, cactus)
    end

    plantModel.Parent = parent
end

--[[
    Get plant type based on biome
]]
function TerrainSetup:GetPlantType(biome)
    local plantTypes = {
        jungle = {"fern", "flower", "grass_tuft"},
        plains = {"flower", "grass_tuft", "grass_tuft"},
        swamp = {"fern", "mushroom", "grass_tuft"},
        volcanic = {"cactus", "grass_tuft"},
        coastal = {"grass_tuft", "flower"},
    }
    local types = plantTypes[biome] or {"grass_tuft"}
    return types[math.random(#types)]
end

--=============================================================================
-- UTILITY
--=============================================================================

--[[
    Clear all generated content
]]
function TerrainSetup:ClearGeneratedContent()
    for _, part in ipairs(generatedParts) do
        if part and part.Parent then
            part:Destroy()
        end
    end
    generatedParts = {}

    -- Clear POI folder
    local poiFolder = Workspace:FindFirstChild("POIs")
    if poiFolder then
        poiFolder:Destroy()
    end

    -- Clear Flora folder
    local floraFolder = Workspace:FindFirstChild("Flora")
    if floraFolder then
        floraFolder:Destroy()
    end

    framework.Log("Debug", "Cleared generated content")
end

--[[
    Shutdown the service
]]
function TerrainSetup:Shutdown()
    self:ClearGeneratedContent()
    framework.Log("Info", "TerrainSetup shut down")
end

return TerrainSetup
