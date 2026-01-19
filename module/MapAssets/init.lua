--[[
    =========================================================================
    MapAssets - Asset Loading and Management System
    =========================================================================

    Handles loading and instantiation of external Roblox assets including:
    - Terrain maps
    - Building prefabs
    - Vegetation decorations
    - Dinosaur models

    This module provides a centralized system for:
    1. Loading assets from Roblox Creator Store by ID
    2. Caching loaded assets for reuse
    3. Instantiating assets at specified positions
    4. Managing asset lifecycle (cleanup on match end)

    Usage:
        local MapAssets = framework:GetModule("MapAssets")
        MapAssets:Initialize()
        MapAssets:SpawnBuilding("ResearchLab", Vector3.new(100, 0, 200))

    =========================================================================
]]

local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapAssets = {}
MapAssets.__index = MapAssets

--=============================================================================
-- PRIVATE STATE
--=============================================================================

local framework = nil
local AssetManifest = nil

-- Cache for loaded assets (prevents re-downloading)
local assetCache = {}

-- Folders for organizing spawned assets
local folders = {
    buildings = nil,
    vegetation = nil,
    dinosaurs = nil,
    props = nil,
}

-- Track spawned instances for cleanup
local spawnedInstances = {}

--=============================================================================
-- INITIALIZATION
--=============================================================================

--[[
    Initialize the MapAssets module
    Creates workspace folders and loads the asset manifest
]]
function MapAssets:Initialize()
    -- Rojo maps to ReplicatedStorage.Framework
    framework = require(script.Parent.Parent.Framework)
    AssetManifest = require(script.AssetManifest)

    -- Create workspace folders for organization
    self:SetupFolders()

    framework.Log("Info", "MapAssets initialized")
    return true
end

--[[
    Create workspace folders for asset organization
]]
function MapAssets:SetupFolders()
    local workspace = game:GetService("Workspace")

    -- Create or get existing folders
    folders.buildings = workspace:FindFirstChild("POIBuildings") or Instance.new("Folder")
    folders.buildings.Name = "POIBuildings"
    folders.buildings.Parent = workspace

    folders.vegetation = workspace:FindFirstChild("Decorations") or Instance.new("Folder")
    folders.vegetation.Name = "Decorations"
    folders.vegetation.Parent = workspace

    folders.dinosaurs = workspace:FindFirstChild("Dinosaurs") or Instance.new("Folder")
    folders.dinosaurs.Name = "Dinosaurs"
    folders.dinosaurs.Parent = workspace

    folders.props = workspace:FindFirstChild("Props") or Instance.new("Folder")
    folders.props.Name = "Props"
    folders.props.Parent = workspace

    framework.Log("Debug", "Workspace folders created")
end

--=============================================================================
-- ASSET LOADING
--=============================================================================

--[[
    Load an asset from Roblox by asset ID
    Uses caching to prevent duplicate downloads
    @param assetId number - The Roblox asset ID
    @return Model|nil - The loaded model or nil on failure
]]
function MapAssets:LoadAsset(assetId)
    if not assetId then
        framework.Log("Warn", "LoadAsset called with nil assetId")
        return nil
    end

    -- Check cache first
    if assetCache[assetId] then
        framework.Log("Debug", "Asset %d loaded from cache", assetId)
        return assetCache[assetId]:Clone()
    end

    -- Attempt to load from Roblox
    local success, result = pcall(function()
        return InsertService:LoadAsset(assetId)
    end)

    if success and result then
        -- Cache the original for future cloning
        assetCache[assetId] = result
        framework.Log("Info", "Asset %d loaded successfully", assetId)
        return result:Clone()
    else
        framework.Log("Warn", "Failed to load asset %d: %s", assetId, tostring(result))
        return nil
    end
end

--[[
    Preload multiple assets into cache
    Call this during initialization to avoid runtime loading delays
    @param assetIds table - Array of asset IDs to preload
]]
function MapAssets:PreloadAssets(assetIds)
    framework.Log("Info", "Preloading %d assets...", #assetIds)

    for _, assetId in ipairs(assetIds) do
        self:LoadAsset(assetId)
    end

    framework.Log("Info", "Preloading complete")
end

--=============================================================================
-- BUILDING SPAWNING
--=============================================================================

--[[
    Spawn a building at the specified position
    @param buildingType string - Building type from AssetManifest.Buildings
    @param position Vector3 - World position to spawn at
    @param rotation number - Y-axis rotation in degrees (optional)
    @return Model|nil - The spawned building or nil on failure
]]
function MapAssets:SpawnBuilding(buildingType, position, rotation)
    local buildingConfig = AssetManifest.Buildings[buildingType]
    if not buildingConfig then
        framework.Log("Warn", "Unknown building type: %s", buildingType)
        return nil
    end

    -- For now, create a placeholder part
    -- In production, this would load from the asset pack
    local building = Instance.new("Model")
    building.Name = buildingConfig.name

    -- Create placeholder structure
    local footprint = buildingConfig.footprint or Vector3.new(20, 10, 20)
    local mainPart = Instance.new("Part")
    mainPart.Name = "Foundation"
    mainPart.Size = footprint
    mainPart.Position = position + Vector3.new(0, footprint.Y / 2, 0)
    mainPart.Anchored = true
    mainPart.Material = Enum.Material.Concrete
    mainPart.Color = Color3.fromRGB(180, 180, 180)
    mainPart.Parent = building

    -- Apply rotation if specified
    if rotation then
        mainPart.CFrame = mainPart.CFrame * CFrame.Angles(0, math.rad(rotation), 0)
    end

    -- Set PrimaryPart for model manipulation
    building.PrimaryPart = mainPart

    -- Parent to buildings folder
    building.Parent = folders.buildings

    -- Track for cleanup
    table.insert(spawnedInstances, building)

    framework.Log("Debug", "Spawned building '%s' at %s", buildingType, tostring(position))
    return building
end

--[[
    Spawn all buildings for a POI
    @param poiName string - Name of the POI from GameConfig
    @param centerPosition Vector3 - Center position of the POI
    @return table - Array of spawned building models
]]
function MapAssets:SpawnPOIBuildings(poiName, centerPosition)
    local mapping = AssetManifest.POIMappings[poiName]
    if not mapping then
        framework.Log("Warn", "No POI mapping found for: %s", poiName)
        return {}
    end

    local buildings = {}
    local buildingList = mapping.buildings or {}

    for i, buildingType in ipairs(buildingList) do
        -- Spread buildings around the center
        local angle = (i / #buildingList) * math.pi * 2
        local radius = 30 + (i * 10)
        local offset = Vector3.new(
            math.cos(angle) * radius,
            0,
            math.sin(angle) * radius
        )

        local building = self:SpawnBuilding(buildingType, centerPosition + offset, math.deg(angle))
        if building then
            table.insert(buildings, building)
        end
    end

    framework.Log("Info", "Spawned %d buildings for POI '%s'", #buildings, poiName)
    return buildings
end

--=============================================================================
-- VEGETATION SPAWNING
--=============================================================================

--[[
    Spawn vegetation decorations in an area
    @param vegetationType string - Vegetation type from AssetManifest.Vegetation
    @param centerPosition Vector3 - Center of the spawn area
    @param radius number - Radius of the spawn area
    @param count number - Number of vegetation items to spawn (optional)
    @return table - Array of spawned vegetation models
]]
function MapAssets:SpawnVegetation(vegetationType, centerPosition, radius, count)
    local vegConfig = AssetManifest.Vegetation[vegetationType]
    if not vegConfig then
        framework.Log("Warn", "Unknown vegetation type: %s", vegetationType)
        return {}
    end

    -- Calculate count based on density if not specified
    local area = math.pi * radius * radius
    local density = vegConfig.density or 0.2
    count = count or math.floor(area * density / 100)

    local vegetation = {}
    local scaleRange = vegConfig.scale or {min = 0.8, max = 1.2}

    for i = 1, count do
        -- Random position within radius
        local angle = math.random() * math.pi * 2
        local dist = math.random() * radius
        local position = centerPosition + Vector3.new(
            math.cos(angle) * dist,
            0,
            math.sin(angle) * dist
        )

        -- Create placeholder vegetation
        local veg = Instance.new("Part")
        veg.Name = vegetationType .. "_" .. i
        veg.Anchored = true
        veg.CanCollide = false
        veg.CastShadow = true

        -- Random scale
        local scale = scaleRange.min + math.random() * (scaleRange.max - scaleRange.min)

        -- Different shapes based on type
        if string.find(vegetationType, "Tree") then
            veg.Shape = Enum.PartType.Cylinder
            veg.Size = Vector3.new(8 * scale, 3 * scale, 3 * scale)
            veg.Material = Enum.Material.Wood
            veg.Color = Color3.fromRGB(139, 90, 43)
            veg.Orientation = Vector3.new(0, 0, 90)
        elseif string.find(vegetationType, "Rock") then
            veg.Shape = Enum.PartType.Ball
            veg.Size = Vector3.new(4 * scale, 3 * scale, 4 * scale)
            veg.Material = Enum.Material.Slate
            veg.Color = Color3.fromRGB(128, 128, 128)
        else
            veg.Shape = Enum.PartType.Block
            veg.Size = Vector3.new(2 * scale, 1 * scale, 2 * scale)
            veg.Material = Enum.Material.Grass
            veg.Color = Color3.fromRGB(76, 153, 0)
        end

        veg.Position = position + Vector3.new(0, veg.Size.Y / 2, 0)
        veg.Parent = folders.vegetation

        table.insert(vegetation, veg)
        table.insert(spawnedInstances, veg)
    end

    framework.Log("Debug", "Spawned %d %s decorations", #vegetation, vegetationType)
    return vegetation
end

--=============================================================================
-- DINOSAUR SPAWNING
--=============================================================================

--[[
    Get dinosaur model configuration
    @param dinoType string - Dinosaur type from AssetManifest.Dinosaurs
    @return table|nil - Dinosaur configuration or nil if not found
]]
function MapAssets:GetDinoConfig(dinoType)
    return AssetManifest.Dinosaurs[dinoType]
end

--[[
    Spawn a dinosaur model at position
    Note: This creates a placeholder - DinoService handles actual dino logic
    @param dinoType string - Dinosaur type
    @param position Vector3 - Spawn position
    @return Model|nil - The spawned dinosaur model
]]
function MapAssets:SpawnDinoModel(dinoType, position)
    local config = AssetManifest.Dinosaurs[dinoType]
    if not config then
        framework.Log("Warn", "Unknown dinosaur type: %s", dinoType)
        return nil
    end

    -- Try to load actual model if asset ID exists
    local dino = nil
    if config.assetId then
        local loaded = self:LoadAsset(config.assetId)
        if loaded then
            dino = loaded:GetChildren()[1] or loaded
        end
    end

    -- Create placeholder if no asset available
    if not dino then
        dino = Instance.new("Model")
        dino.Name = config.name or dinoType

        local body = Instance.new("Part")
        body.Name = "Body"
        body.Size = Vector3.new(6, 4, 10)
        body.Position = position + Vector3.new(0, 2, 0)
        body.Anchored = true
        body.Material = Enum.Material.SmoothPlastic
        body.Color = Color3.fromRGB(0, 100, 0)  -- Green for placeholder
        body.Parent = dino

        dino.PrimaryPart = body
    else
        -- Position the loaded model
        if dino.PrimaryPart then
            dino:SetPrimaryPartCFrame(CFrame.new(position))
        end
    end

    dino.Parent = folders.dinosaurs
    table.insert(spawnedInstances, dino)

    framework.Log("Debug", "Spawned dinosaur '%s' at %s", dinoType, tostring(position))
    return dino
end

--=============================================================================
-- TERRAIN MANAGEMENT
--=============================================================================

--[[
    Get terrain configuration by name
    @param terrainName string - Name of terrain from AssetManifest.Terrain
    @return table|nil - Terrain configuration
]]
function MapAssets:GetTerrainConfig(terrainName)
    return AssetManifest.Terrain[terrainName]
end

--[[
    Load terrain from a game place
    Note: This requires manual import in Studio - programmatic terrain loading
    is limited. This function documents the process.
    @param terrainName string - Name of terrain to load
]]
function MapAssets:LoadTerrain(terrainName)
    local config = AssetManifest.Terrain[terrainName]
    if not config then
        framework.Log("Warn", "Unknown terrain: %s", terrainName)
        return false
    end

    framework.Log("Info", "Terrain '%s' (Game ID: %d) should be manually imported in Studio",
        config.name, config.gameId)
    framework.Log("Info", "Visit: https://www.roblox.com/games/%d", config.gameId)

    return true
end

--=============================================================================
-- CLEANUP
--=============================================================================

--[[
    Clear all spawned assets
    Called during match cleanup to reset the map
]]
function MapAssets:ClearAll()
    framework.Log("Info", "Clearing all spawned assets...")

    for _, instance in ipairs(spawnedInstances) do
        if instance and instance.Parent then
            instance:Destroy()
        end
    end

    spawnedInstances = {}

    -- Clear folders
    for _, folder in pairs(folders) do
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                child:Destroy()
            end
        end
    end

    framework.Log("Info", "Asset cleanup complete")
end

--[[
    Clear asset cache (free memory)
]]
function MapAssets:ClearCache()
    for assetId, asset in pairs(assetCache) do
        if asset then
            asset:Destroy()
        end
    end
    assetCache = {}
    framework.Log("Debug", "Asset cache cleared")
end

--=============================================================================
-- UTILITY
--=============================================================================

--[[
    Get the asset manifest for external reference
    @return table - The AssetManifest module
]]
function MapAssets:GetManifest()
    return AssetManifest
end

--[[
    Get spawned instance count
    @return number - Number of currently spawned instances
]]
function MapAssets:GetSpawnedCount()
    return #spawnedInstances
end

--[[
    Shutdown the module
]]
function MapAssets:Shutdown()
    self:ClearAll()
    self:ClearCache()
    framework.Log("Info", "MapAssets shut down")
end

return MapAssets
