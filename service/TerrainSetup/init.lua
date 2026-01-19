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
    Creates terrain, water, and basic structures
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

    -- Create POI placeholder structures
    self:GeneratePOIs()

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
    Generate POI placeholder structures
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

    -- Generate each POI
    for name, poiData in pairs(pois) do
        local position = poiData.position or Vector3.new(0, 0, 0)
        local size = poiData.size or 100

        -- Create POI marker/platform
        local poiPart = Instance.new("Part")
        poiPart.Name = name
        poiPart.Size = Vector3.new(size, 2, size)
        poiPart.Position = Vector3.new(position.X, MAP_CONFIG.baseHeight + 10, position.Z)
        poiPart.Anchored = true
        poiPart.Material = Enum.Material.Concrete
        poiPart.Color = Color3.fromRGB(100, 100, 100)
        poiPart.Transparency = 0.5
        poiPart.Parent = poiFolder

        -- Add label
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "Label"
        billboard.Size = UDim2.new(0, 200, 0, 50)
        billboard.StudsOffset = Vector3.new(0, 20, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = poiPart

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 0.5
        label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.Text = name
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard

        -- Create placeholder buildings
        self:GeneratePOIBuildings(poiPart, name)

        table.insert(generatedParts, poiPart)
    end

    framework.Log("Debug", "POIs generated: %d locations", #generatedParts)
end

--[[
    Generate placeholder buildings for a POI
]]
function TerrainSetup:GeneratePOIBuildings(poiPart, poiName)
    local buildingCount = math.random(2, 5)
    local poiPosition = poiPart.Position
    local poiSize = poiPart.Size.X

    for i = 1, buildingCount do
        local building = Instance.new("Part")
        building.Name = poiName .. "_Building_" .. i

        -- Random building dimensions
        local width = math.random(10, 30)
        local height = math.random(8, 25)
        local depth = math.random(10, 30)
        building.Size = Vector3.new(width, height, depth)

        -- Position around POI center
        local angle = (i / buildingCount) * math.pi * 2
        local radius = poiSize * 0.3
        local offsetX = math.cos(angle) * radius + math.random(-10, 10)
        local offsetZ = math.sin(angle) * radius + math.random(-10, 10)

        building.Position = Vector3.new(
            poiPosition.X + offsetX,
            poiPosition.Y + height / 2 + 1,
            poiPosition.Z + offsetZ
        )

        building.Anchored = true
        building.Material = Enum.Material.Concrete
        building.Color = Color3.fromRGB(
            math.random(80, 150),
            math.random(80, 150),
            math.random(80, 150)
        )
        building.Parent = poiPart.Parent

        table.insert(generatedParts, building)
    end
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
