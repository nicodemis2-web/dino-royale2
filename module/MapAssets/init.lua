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

-- Track failed assets to avoid repeated load attempts
local failedAssets = {}

-- Folders for organizing spawned assets
local folders = {
    buildings = nil,
    vegetation = nil,
    dinosaurs = nil,
    props = nil,
}

-- Track spawned instances for cleanup
local spawnedInstances = {}

-- Workspace reference for raycasting
local Workspace = game:GetService("Workspace")

--=============================================================================
-- TERRAIN HEIGHT DETECTION
--=============================================================================

--[[
    Get the terrain height at a given X, Z position using raycast
    Excludes placed objects (buildings, vegetation, props) to find actual terrain

    @param x number - X coordinate
    @param z number - Z coordinate
    @return number - Terrain height (Y value) at the position
]]
local function GetTerrainHeight(x, z)
    local rayOrigin = Vector3.new(x, 1000, z)  -- Start high above
    local rayDirection = Vector3.new(0, -2000, 0)  -- Cast downward

    -- Build exclusion list - exclude all spawned asset folders
    local excludeList = {}

    -- Exclude our own folders
    if folders.buildings and folders.buildings.Parent then
        table.insert(excludeList, folders.buildings)
    end
    if folders.vegetation and folders.vegetation.Parent then
        table.insert(excludeList, folders.vegetation)
    end
    if folders.dinosaurs and folders.dinosaurs.Parent then
        table.insert(excludeList, folders.dinosaurs)
    end
    if folders.props and folders.props.Parent then
        table.insert(excludeList, folders.props)
    end

    -- Also exclude common workspace folders that might contain non-terrain objects
    local poiFolder = Workspace:FindFirstChild("POIs")
    local floraFolder = Workspace:FindFirstChild("Flora")
    local decorFolder = Workspace:FindFirstChild("Decorations")
    local lobbyPlatform = Workspace:FindFirstChild("LobbyPlatform")
    local groundLoot = Workspace:FindFirstChild("GroundLoot")

    if poiFolder then table.insert(excludeList, poiFolder) end
    if floraFolder then table.insert(excludeList, floraFolder) end
    if decorFolder then table.insert(excludeList, decorFolder) end
    if lobbyPlatform then table.insert(excludeList, lobbyPlatform) end
    if groundLoot then table.insert(excludeList, groundLoot) end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = excludeList
    raycastParams.IgnoreWater = true

    local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if result then
        return result.Position.Y
    end

    -- Fallback: try to read terrain voxels directly
    -- ReadVoxels returns: materials[x][y][z], occupancies[x][y][z]
    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        local success, materials, occupancies = pcall(function()
            local region = Region3.new(
                Vector3.new(x - 2, 0, z - 2),
                Vector3.new(x + 2, 200, z + 2)
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

    -- Final fallback to base terrain height
    return 5
end

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
    Tracks failed assets to avoid repeated HTTP requests
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

    -- Check if this asset already failed (avoid repeated HTTP requests)
    if failedAssets[assetId] then
        -- Only log once per session, not every attempt
        return nil
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
        -- Mark as failed to prevent repeated attempts
        failedAssets[assetId] = true
        framework.Log("Warn", "Failed to load asset %d: %s (will use placeholder)", assetId, tostring(result))
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
    Spawn a building from the LowPolyBuildings manifest
    @param buildingKey string - Key from AssetManifest.LowPolyBuildings (Store, House, Office, etc.)
    @param position Vector3 - World position to spawn at
    @param rotation number - Y-axis rotation in degrees (optional)
    @return Model|nil - The spawned building or nil on failure
]]
function MapAssets:SpawnLowPolyBuilding(buildingKey, position, rotation)
    local buildingConfig = AssetManifest.LowPolyBuildings and AssetManifest.LowPolyBuildings[buildingKey]
    if not buildingConfig or not buildingConfig.assetId then
        framework.Log("Warn", "Unknown or invalid LowPolyBuilding: %s", buildingKey)
        return nil
    end

    local loaded = self:LoadAsset(buildingConfig.assetId)
    if not loaded then
        framework.Log("Warn", "Failed to load LowPolyBuilding asset: %s", buildingKey)
        return nil
    end

    -- Get the actual model from the loaded container
    local building = loaded:GetChildren()[1]
    if not building then
        loaded:Destroy()
        return nil
    end
    building = building:Clone()
    loaded:Destroy()

    -- Get terrain height and position
    local groundY = GetTerrainHeight(position.X, position.Z)

    -- Position the building
    if building:IsA("Model") then
        if building.PrimaryPart then
            local cf = CFrame.new(position.X, groundY, position.Z)
            if rotation then
                cf = cf * CFrame.Angles(0, math.rad(rotation), 0)
            end
            building:SetPrimaryPartCFrame(cf)
        else
            -- Find a suitable primary part
            local basePart = building:FindFirstChildWhichIsA("BasePart", true)
            if basePart then
                building.PrimaryPart = basePart
                local cf = CFrame.new(position.X, groundY, position.Z)
                if rotation then
                    cf = cf * CFrame.Angles(0, math.rad(rotation), 0)
                end
                building:SetPrimaryPartCFrame(cf)
            end
        end
    elseif building:IsA("BasePart") then
        building.Position = Vector3.new(position.X, groundY + building.Size.Y / 2, position.Z)
        if rotation then
            building.CFrame = building.CFrame * CFrame.Angles(0, math.rad(rotation), 0)
        end
    end

    building.Parent = folders.buildings
    table.insert(spawnedInstances, building)

    framework.Log("Debug", "Spawned LowPolyBuilding '%s' at %s", buildingKey, tostring(position))
    return building
end

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

    -- Get actual terrain height at this position
    local groundY = GetTerrainHeight(position.X, position.Z)

    -- Check if building should load from an asset pack
    local building = nil
    local source = buildingConfig.source

    -- Try to load from LowPolyUltimate pack
    if source == "LowPolyUltimate" and AssetManifest.AssetPacks.LowPolyUltimate then
        local packId = AssetManifest.AssetPacks.LowPolyUltimate.assetId
        local loaded = self:LoadAsset(packId)
        if loaded then
            -- Search for matching building in pack
            local searchName = buildingConfig.name or buildingType
            local foundBuilding = loaded:FindFirstChild(searchName, true)
            if foundBuilding then
                building = foundBuilding:Clone()
            end
            loaded:Destroy()
        end
    end

    -- Fallback to placeholder if no asset loaded
    if not building then
        building = Instance.new("Model")
        building.Name = buildingConfig.name

        -- Create placeholder structure
        local footprint = buildingConfig.footprint or Vector3.new(20, 10, 20)
        local mainPart = Instance.new("Part")
        mainPart.Name = "Foundation"
        mainPart.Size = footprint
        mainPart.Position = Vector3.new(position.X, groundY + footprint.Y / 2, position.Z)
        mainPart.Anchored = true
        mainPart.Material = Enum.Material.Concrete
        mainPart.Color = Color3.fromRGB(180, 180, 180)
        mainPart.Parent = building

        if rotation then
            mainPart.CFrame = mainPart.CFrame * CFrame.Angles(0, math.rad(rotation), 0)
        end

        building.PrimaryPart = mainPart
    else
        -- Position loaded building
        if building:IsA("Model") and building.PrimaryPart then
            local cf = CFrame.new(position.X, groundY, position.Z)
            if rotation then
                cf = cf * CFrame.Angles(0, math.rad(rotation), 0)
            end
            building:SetPrimaryPartCFrame(cf)
        end
    end

    -- Parent to buildings folder
    building.Parent = folders.buildings

    -- Track for cleanup
    table.insert(spawnedInstances, building)

    framework.Log("Debug", "Spawned building '%s' at %s (ground Y: %.1f)", buildingType, tostring(position), groundY)
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
    Get the appropriate tree pack for a biome
    @param biome string - Biome name (jungle, swamp, plains, coastal, volcanic, facility)
    @return table - Tree pack config with assetId
]]
function MapAssets:GetTreePackForBiome(biome)
    local treePacks = AssetManifest.TreePacks
    if not treePacks then return nil end

    -- Find packs that match this biome
    local matchingPacks = {}
    for packName, packConfig in pairs(treePacks) do
        if packConfig.biomes then
            for _, b in ipairs(packConfig.biomes) do
                if b == biome then
                    table.insert(matchingPacks, packConfig)
                    break
                end
            end
        end
    end

    -- Return random matching pack or nil
    if #matchingPacks > 0 then
        return matchingPacks[math.random(1, #matchingPacks)]
    end

    return nil
end

--[[
    Spawn trees from a tree pack at position
    @param biome string - Biome name to select appropriate trees
    @param position Vector3 - Position to spawn at
    @param scale number - Scale multiplier (optional, default 1)
    @return Model|nil - Spawned tree model
]]
function MapAssets:SpawnTreeFromPack(biome, position, scale)
    local treePack = self:GetTreePackForBiome(biome)
    if not treePack or not treePack.assetId then
        -- Fallback to placeholder
        return self:SpawnPlaceholderTree(position, scale)
    end

    local loaded = self:LoadAsset(treePack.assetId)
    if not loaded then
        return self:SpawnPlaceholderTree(position, scale)
    end

    -- Tree packs contain multiple tree models - pick one randomly
    local children = loaded:GetChildren()
    if #children == 0 then
        loaded:Destroy()
        return self:SpawnPlaceholderTree(position, scale)
    end

    local treeModel = children[math.random(1, #children)]:Clone()
    loaded:Destroy()

    -- Get terrain height and position tree
    local groundY = GetTerrainHeight(position.X, position.Z)

    if treeModel:IsA("Model") and treeModel.PrimaryPart then
        local scaleFactor = scale or 1
        -- Scale the model
        if scaleFactor ~= 1 then
            for _, part in ipairs(treeModel:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Size = part.Size * scaleFactor
                end
            end
        end
        treeModel:SetPrimaryPartCFrame(CFrame.new(position.X, groundY, position.Z))
    elseif treeModel:IsA("BasePart") then
        treeModel.Position = Vector3.new(position.X, groundY + treeModel.Size.Y / 2, position.Z)
    end

    treeModel.Parent = folders.vegetation
    table.insert(spawnedInstances, treeModel)

    return treeModel
end

--[[
    Spawn a placeholder tree (used when no asset pack available)
]]
function MapAssets:SpawnPlaceholderTree(position, scale)
    local groundY = GetTerrainHeight(position.X, position.Z)
    scale = scale or 1

    local tree = Instance.new("Model")
    tree.Name = "PlaceholderTree"

    -- Trunk
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Shape = Enum.PartType.Cylinder
    trunk.Size = Vector3.new(8 * scale, 1.5 * scale, 1.5 * scale)
    trunk.CFrame = CFrame.new(position.X, groundY + 4 * scale, position.Z) * CFrame.Angles(0, 0, math.rad(90))
    trunk.Anchored = true
    trunk.Material = Enum.Material.Wood
    trunk.Color = Color3.fromRGB(101, 67, 33)
    trunk.Parent = tree

    -- Canopy
    local canopy = Instance.new("Part")
    canopy.Name = "Canopy"
    canopy.Shape = Enum.PartType.Ball
    canopy.Size = Vector3.new(6 * scale, 5 * scale, 6 * scale)
    canopy.Position = Vector3.new(position.X, groundY + 9 * scale, position.Z)
    canopy.Anchored = true
    canopy.Material = Enum.Material.Grass
    canopy.Color = Color3.fromRGB(34, 139, 34)
    canopy.Parent = tree

    tree.PrimaryPart = trunk
    tree.Parent = folders.vegetation
    table.insert(spawnedInstances, tree)

    return tree
end

--[[
    Spawn vegetation decorations in an area
    @param vegetationType string - Vegetation type from AssetManifest.Vegetation
    @param centerPosition Vector3 - Center of the spawn area
    @param radius number - Radius of the spawn area
    @param count number - Number of vegetation items to spawn (optional)
    @param biome string - Biome name for tree pack selection (optional)
    @return table - Array of spawned vegetation models
]]
function MapAssets:SpawnVegetation(vegetationType, centerPosition, radius, count, biome)
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
        local worldX = centerPosition.X + math.cos(angle) * dist
        local worldZ = centerPosition.Z + math.sin(angle) * dist
        local pos = Vector3.new(worldX, 0, worldZ)

        -- Random scale
        local scale = scaleRange.min + math.random() * (scaleRange.max - scaleRange.min)

        local veg = nil

        -- Use tree packs for tree types if biome specified
        if string.find(vegetationType, "Tree") and biome then
            veg = self:SpawnTreeFromPack(biome, pos, scale)
        else
            -- Get actual terrain height at this position
            local groundY = GetTerrainHeight(worldX, worldZ)

            -- Create placeholder vegetation
            veg = Instance.new("Part")
            veg.Name = vegetationType .. "_" .. i
            veg.Anchored = true
            veg.CanCollide = false
            veg.CastShadow = true

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

            -- Position vegetation on terrain
            veg.Position = Vector3.new(worldX, groundY + veg.Size.Y / 2, worldZ)
            veg.Parent = folders.vegetation

            table.insert(spawnedInstances, veg)
        end

        if veg then
            table.insert(vegetation, veg)
        end
    end

    framework.Log("Debug", "Spawned %d %s decorations (grounded)", #vegetation, vegetationType)
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

    -- Get actual terrain height at this position
    local groundY = GetTerrainHeight(position.X, position.Z)

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
        -- Position dinosaur on terrain
        body.Position = Vector3.new(position.X, groundY + 2, position.Z)
        body.Anchored = true
        body.Material = Enum.Material.SmoothPlastic
        body.Color = Color3.fromRGB(0, 100, 0)  -- Green for placeholder
        body.Parent = dino

        dino.PrimaryPart = body
    else
        -- Position the loaded model on terrain
        if dino.PrimaryPart then
            dino:SetPrimaryPartCFrame(CFrame.new(position.X, groundY, position.Z))
        end
    end

    dino.Parent = folders.dinosaurs
    table.insert(spawnedInstances, dino)

    framework.Log("Debug", "Spawned dinosaur '%s' at %s (ground Y: %.1f)", dinoType, tostring(position), groundY)
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
-- VFX AND PARTICLE EFFECTS
--=============================================================================

--[[
    Get VFX configuration by name
    @param effectName string - Name of effect from AssetManifest.VFX
    @return table|nil - VFX configuration
]]
function MapAssets:GetVFXConfig(effectName)
    return AssetManifest.VFX and AssetManifest.VFX[effectName]
end

--[[
    Create a muzzle flash effect
    @param attachment Attachment - The attachment to emit from
    @return ParticleEmitter - The created emitter
]]
function MapAssets:CreateMuzzleFlash(attachment)
    local config = AssetManifest.VFX and AssetManifest.VFX.MuzzleFlash
    if not config then
        config = {
            color = Color3.fromRGB(255, 200, 50),
            lifetime = 0.05,
        }
    end

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "MuzzleFlash"
    emitter.Color = ColorSequence.new(config.color)
    emitter.LightEmission = 1
    emitter.LightInfluence = 0
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(config.lifetime or 0.05)
    emitter.Rate = 0
    emitter.Speed = NumberRange.new(0)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Parent = attachment

    return emitter
end

--[[
    Create a bullet impact effect
    @param position Vector3 - Position of impact
    @param normal Vector3 - Surface normal at impact
    @return Part - Container part with particle effects
]]
function MapAssets:CreateBulletImpact(position, normal)
    local config = AssetManifest.VFX and AssetManifest.VFX.BulletImpact
    if not config then
        config = {
            color = Color3.fromRGB(255, 200, 100),
            sparkCount = 8,
            spread = 180,
        }
    end

    local impactPart = Instance.new("Part")
    impactPart.Name = "BulletImpact"
    impactPart.Size = Vector3.new(0.1, 0.1, 0.1)
    impactPart.Transparency = 1
    impactPart.Anchored = true
    impactPart.CanCollide = false
    impactPart.Position = position
    impactPart.CFrame = CFrame.lookAt(position, position + normal)

    local attachment = Instance.new("Attachment")
    attachment.Parent = impactPart

    local sparks = Instance.new("ParticleEmitter")
    sparks.Name = "Sparks"
    sparks.Color = ColorSequence.new(config.color)
    sparks.LightEmission = 0.8
    sparks.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(1, 0),
    })
    sparks.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    sparks.Lifetime = NumberRange.new(0.1, 0.2)
    sparks.Rate = 0
    sparks.Speed = NumberRange.new(5, 15)
    sparks.SpreadAngle = Vector2.new(config.spread or 180, config.spread or 180)
    sparks.Parent = attachment

    impactPart.Parent = Workspace
    sparks:Emit(config.sparkCount or 8)

    -- Auto cleanup
    game:GetService("Debris"):AddItem(impactPart, 0.5)

    return impactPart
end

--[[
    Create an explosion effect using the realistic flipbook explosions if available
    @param position Vector3 - Position of explosion
    @param scale number - Scale of explosion (optional, default 1)
    @return Part|nil - Explosion container or nil
]]
function MapAssets:CreateExplosion(position, scale)
    scale = scale or 1

    -- Try to load realistic explosion from VFX manifest
    local explosionConfig = AssetManifest.VFX and AssetManifest.VFX.RealisticExplosions
    if explosionConfig and explosionConfig.assetId then
        local loaded = self:LoadAsset(explosionConfig.assetId)
        if loaded then
            local explosion = loaded:GetChildren()[1]
            if explosion then
                explosion = explosion:Clone()
                loaded:Destroy()

                if explosion:IsA("Model") and explosion.PrimaryPart then
                    explosion:SetPrimaryPartCFrame(CFrame.new(position))
                elseif explosion:IsA("BasePart") then
                    explosion.Position = position
                end

                explosion.Parent = Workspace
                game:GetService("Debris"):AddItem(explosion, 3)

                framework.Log("Debug", "Created realistic explosion at %s", tostring(position))
                return explosion
            end
            loaded:Destroy()
        end
    end

    -- Fallback to basic explosion
    local explosionPart = Instance.new("Part")
    explosionPart.Name = "Explosion"
    explosionPart.Size = Vector3.new(0.1, 0.1, 0.1)
    explosionPart.Transparency = 1
    explosionPart.Anchored = true
    explosionPart.CanCollide = false
    explosionPart.Position = position

    local attachment = Instance.new("Attachment")
    attachment.Parent = explosionPart

    -- Fire/smoke effect
    local fire = Instance.new("ParticleEmitter")
    fire.Name = "FireBall"
    fire.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 50, 0)),
    })
    fire.LightEmission = 1
    fire.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 2 * scale),
        NumberSequenceKeypoint.new(0.3, 5 * scale),
        NumberSequenceKeypoint.new(1, 8 * scale),
    })
    fire.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    fire.Lifetime = NumberRange.new(0.5, 1)
    fire.Rate = 0
    fire.Speed = NumberRange.new(10 * scale, 20 * scale)
    fire.SpreadAngle = Vector2.new(360, 360)
    fire.Parent = attachment

    explosionPart.Parent = Workspace
    fire:Emit(20)

    game:GetService("Debris"):AddItem(explosionPart, 2)

    return explosionPart
end

--[[
    Get loot glow color by rarity
    @param rarity string - Rarity level (common, uncommon, rare, epic, legendary)
    @return Color3 - The glow color
]]
function MapAssets:GetLootGlowColor(rarity)
    local glowConfig = AssetManifest.VFX and AssetManifest.VFX.LootGlow
    if glowConfig and glowConfig[rarity] then
        return glowConfig[rarity]
    end

    -- Fallback colors
    local fallbackColors = {
        common = Color3.fromRGB(180, 180, 180),
        uncommon = Color3.fromRGB(50, 200, 50),
        rare = Color3.fromRGB(50, 100, 255),
        epic = Color3.fromRGB(150, 50, 200),
        legendary = Color3.fromRGB(255, 180, 0),
    }

    return fallbackColors[rarity] or fallbackColors.common
end

--=============================================================================
-- ASSET PRELOADING
--=============================================================================

--[[
    Preload all critical assets for the game
    Call this during initialization to reduce runtime loading
]]
function MapAssets:PreloadCriticalAssets()
    framework.Log("Info", "Preloading critical game assets...")

    local assetsToPreload = {}

    -- Weapon packs
    if AssetManifest.Weapons then
        if AssetManifest.Weapons.FPSGunPack and AssetManifest.Weapons.FPSGunPack.assetId then
            table.insert(assetsToPreload, AssetManifest.Weapons.FPSGunPack.assetId)
        end
    end

    -- Dinosaur packs
    if AssetManifest.Dinosaurs then
        if AssetManifest.Dinosaurs.RiggedPack and AssetManifest.Dinosaurs.RiggedPack.assetId then
            table.insert(assetsToPreload, AssetManifest.Dinosaurs.RiggedPack.assetId)
        end
        if AssetManifest.Dinosaurs.JPOGPack and AssetManifest.Dinosaurs.JPOGPack.assetId then
            table.insert(assetsToPreload, AssetManifest.Dinosaurs.JPOGPack.assetId)
        end
    end

    -- Asset packs
    if AssetManifest.AssetPacks then
        if AssetManifest.AssetPacks.LowPolyUltimate and AssetManifest.AssetPacks.LowPolyUltimate.assetId then
            table.insert(assetsToPreload, AssetManifest.AssetPacks.LowPolyUltimate.assetId)
        end
    end

    -- VFX
    if AssetManifest.VFX then
        if AssetManifest.VFX.RealisticExplosions and AssetManifest.VFX.RealisticExplosions.assetId then
            table.insert(assetsToPreload, AssetManifest.VFX.RealisticExplosions.assetId)
        end
    end

    -- Preload all gathered assets
    self:PreloadAssets(assetsToPreload)

    framework.Log("Info", "Critical asset preloading complete (%d assets)", #assetsToPreload)
end

--[[
    Preload tree packs for a specific biome
    @param biome string - Biome name
]]
function MapAssets:PreloadBiomeAssets(biome)
    if not AssetManifest.TreePacks then return end

    local toPreload = {}

    for packName, packConfig in pairs(AssetManifest.TreePacks) do
        if packConfig.biomes and packConfig.assetId then
            for _, b in ipairs(packConfig.biomes) do
                if b == biome then
                    table.insert(toPreload, packConfig.assetId)
                    break
                end
            end
        end
    end

    if #toPreload > 0 then
        framework.Log("Info", "Preloading %d tree packs for biome '%s'", #toPreload, biome)
        self:PreloadAssets(toPreload)
    end
end

--[[
    Preload LowPoly building assets
]]
function MapAssets:PreloadBuildings()
    if not AssetManifest.LowPolyBuildings then return end

    local toPreload = {}
    for buildingKey, config in pairs(AssetManifest.LowPolyBuildings) do
        if config.assetId then
            table.insert(toPreload, config.assetId)
        end
    end

    if #toPreload > 0 then
        framework.Log("Info", "Preloading %d building assets", #toPreload)
        self:PreloadAssets(toPreload)
    end
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
