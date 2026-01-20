--[[
    LootSystem - Ground loot and chest spawning

    Features:
    - Ground loot spawn points
    - Chest/crate containers
    - Rarity-based loot tables
    - Pickup system
    - Loot respawn (if enabled)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local LootSystem = {}
LootSystem.__index = LootSystem

-- Private state
local groundLoot = {}       -- Active ground items
local chests = {}           -- Chest containers
local spawnPoints = {}      -- Loot spawn locations
local isActive = false
local framework = nil
local gameConfig = nil

-- Loot tables by category
local lootTables = {}

--[[
    Initialize the LootSystem
]]
function LootSystem:Initialize()
    -- Rojo maps to ReplicatedStorage.Framework and ReplicatedStorage.Shared
    framework = require(script.Parent.Parent.Framework)
    gameConfig = require(script.Parent.Parent.Shared.GameConfig)

    -- Load spawn points
    self:LoadSpawnPoints()

    -- Initialize loot tables
    self:InitializeLootTables()

    -- Setup remotes
    self:SetupRemotes()

    framework.Log("Info", "LootSystem initialized with %d spawn points", #spawnPoints)
    return self
end

--[[
    Setup remote events
]]
function LootSystem:SetupRemotes()
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = "Remotes"
        remoteFolder.Parent = ReplicatedStorage
    end

    local lootRemotes = {
        "LootSpawned",
        "LootPickedUp",
        "ChestOpened",
    }

    for _, remoteName in ipairs(lootRemotes) do
        if not remoteFolder:FindFirstChild(remoteName) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = remoteName
            remote.Parent = remoteFolder
        end
    end
end

--[[
    Load loot spawn points from map
    First tries MapService for POI-based spawn points, then falls back to workspace folders
]]
function LootSystem:LoadSpawnPoints()
    spawnPoints = {}

    -- First try to get spawn points from MapService (POI-based loot)
    local mapService = framework:GetService("MapService")
    if mapService and mapService.GetLootSpawnPoints then
        local mapSpawns = mapService:GetLootSpawnPoints()
        if mapSpawns and #mapSpawns > 0 then
            for _, spawn in ipairs(mapSpawns) do
                table.insert(spawnPoints, {
                    position = spawn.position or spawn,
                    type = spawn.type or "any",
                    rarity = spawn.rarity or nil,
                    biome = spawn.biome or nil,
                })
            end
            framework.Log("Info", "Loaded %d spawn points from MapService", #spawnPoints)
        end
    end

    -- Also check workspace for additional ground loot points
    local groundFolder = workspace:FindFirstChild("LootSpawnPoints")
    if groundFolder then
        for _, point in ipairs(groundFolder:GetChildren()) do
            if point:IsA("BasePart") then
                table.insert(spawnPoints, {
                    position = point.Position,
                    type = point:GetAttribute("LootType") or "any",
                    rarity = point:GetAttribute("Rarity") or nil,
                })
            end
        end
    end

    -- Chest locations from workspace
    local chestFolder = workspace:FindFirstChild("ChestSpawnPoints")
    if chestFolder then
        for _, point in ipairs(chestFolder:GetChildren()) do
            if point:IsA("BasePart") then
                table.insert(chests, {
                    position = point.Position,
                    opened = false,
                    model = nil,
                })
            end
        end
    end

    -- Also get chest locations from MapService POIs
    if mapService and mapService.GetPOIChestLocations then
        local poiChests = mapService:GetPOIChestLocations()
        if poiChests then
            for _, chestPos in ipairs(poiChests) do
                table.insert(chests, {
                    position = chestPos.position or chestPos,
                    opened = false,
                    model = nil,
                    rarity = chestPos.rarity or "rare", -- POI chests have better loot
                })
            end
        end
    end

    -- Generate default spawn points if none found
    if #spawnPoints == 0 then
        self:GenerateDefaultSpawnPoints()
    end

    -- Generate default chests if none found (for test mode)
    if #chests == 0 then
        self:GenerateDefaultChests()
    end
end

--[[
    Generate default chest locations (fallback for test mode)
    Creates chests distributed across the map with higher concentration near POI areas
    Industry standard: ~30-50 chests per battle royale map
]]
function LootSystem:GenerateDefaultChests()
    -- Generate 30-40 chests distributed across the map
    local baseChestCount = 35
    local mapRadius = 800  -- Cover most of the map

    -- Create ring patterns at different distances for good distribution
    local rings = {
        {radius = 100, count = 5, baseRarity = "rare"},      -- Inner ring (near spawn)
        {radius = 300, count = 10, baseRarity = "uncommon"}, -- Mid ring
        {radius = 500, count = 10, baseRarity = "uncommon"}, -- Outer mid ring
        {radius = 700, count = 8, baseRarity = "common"},    -- Outer ring
    }

    -- Add some epic/legendary chests at random locations
    local epicCount = 3
    for i = 1, epicCount do
        local angle = math.random() * math.pi * 2
        local radius = math.random(200, 600)
        table.insert(chests, {
            position = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius),
            opened = false,
            model = nil,
            rarity = (i == 1) and "legendary" or "epic",
        })
    end

    -- Generate ring-based chests
    for _, ring in ipairs(rings) do
        for i = 1, ring.count do
            local angle = (i / ring.count) * math.pi * 2 + math.random() * 0.3  -- Slight randomization
            local radiusVariation = ring.radius + (math.random() - 0.5) * 100
            local x = math.cos(angle) * radiusVariation
            local z = math.sin(angle) * radiusVariation

            table.insert(chests, {
                position = Vector3.new(x, 0, z),
                opened = false,
                model = nil,
                rarity = ring.baseRarity,
            })
        end
    end

    framework.Log("Warn", "Generated %d default chests for testing (fallback mode)", #chests)
end

--[[
    Generate default spawn points (fallback)
    Uses industry-standard FPS loot density: ~1 spawn per 40-60 square studs
    Map size is 2000x2000 = 4M sq studs, targeting ~800-1600 loot spawns
]]
function LootSystem:GenerateDefaultSpawnPoints()
    -- Create a grid of spawn points covering the full map
    local mapHalfSize = 900  -- Slightly smaller than MAP_SIZE/2 to avoid edge
    local spacing = 50  -- Studs between potential loot spawns (standard FPS density)

    local count = 0
    for x = -mapHalfSize, mapHalfSize, spacing do
        for z = -mapHalfSize, mapHalfSize, spacing do
            -- Add some randomness to avoid grid-like appearance
            local offsetX = (math.random() - 0.5) * spacing * 0.6
            local offsetZ = (math.random() - 0.5) * spacing * 0.6

            table.insert(spawnPoints, {
                position = Vector3.new(x + offsetX, 0, z + offsetZ),
                type = "any",
                rarity = nil,
            })
            count = count + 1
        end
    end

    framework.Log("Warn", "Generated %d default loot spawn points (fallback mode)", count)
end

--[[
    Initialize loot tables
    Contains all weapon types including melee, explosives, throwables, and traps
]]
function LootSystem:InitializeLootTables()
    lootTables = {
        --==================================================================
        -- RANGED WEAPONS
        --==================================================================
        weapons = {
            -- Pistols (Common)
            {item = "glock", weight = 15, rarity = "common"},
            {item = "revolver", weight = 10, rarity = "common"},

            -- SMGs (Common/Uncommon)
            {item = "uzi", weight = 12, rarity = "common"},
            {item = "mp5", weight = 10, rarity = "uncommon"},
            {item = "p90", weight = 6, rarity = "rare"},

            -- Shotguns (Uncommon/Rare)
            {item = "pump_shotgun", weight = 8, rarity = "uncommon"},
            {item = "tactical_shotgun", weight = 5, rarity = "rare"},
            {item = "double_barrel", weight = 4, rarity = "rare"},

            -- Assault Rifles (Rare/Epic)
            {item = "ak47", weight = 6, rarity = "rare"},
            {item = "m4a1", weight = 3, rarity = "epic"},
            {item = "scar", weight = 1, rarity = "legendary"},

            -- Snipers (Rare/Epic/Legendary)
            {item = "semi_sniper", weight = 4, rarity = "rare"},
            {item = "bolt_sniper", weight = 2, rarity = "epic"},
            {item = "heavy_sniper", weight = 1, rarity = "legendary"},

            -- Pistols (Rare)
            {item = "deagle", weight = 4, rarity = "rare"},
        },

        --==================================================================
        -- MELEE WEAPONS
        --==================================================================
        melee = {
            -- Common melee
            {item = "combat_knife", weight = 15, rarity = "common"},

            -- Uncommon melee
            {item = "machete", weight = 10, rarity = "uncommon"},

            -- Rare melee
            {item = "stun_baton", weight = 6, rarity = "rare"},
            {item = "spear", weight = 5, rarity = "rare"},
        },

        --==================================================================
        -- EXPLOSIVE WEAPONS
        --==================================================================
        explosives = {
            -- Epic explosives
            {item = "grenade_launcher", weight = 2, rarity = "epic"},

            -- Legendary explosives
            {item = "rocket_launcher", weight = 1, rarity = "legendary"},
        },

        --==================================================================
        -- THROWABLES
        --==================================================================
        throwables = {
            -- Common throwables
            {item = "smoke_grenade", amount = {1, 2}, weight = 20, rarity = "common"},

            -- Uncommon throwables
            {item = "frag_grenade", amount = {1, 2}, weight = 15, rarity = "uncommon"},
            {item = "molotov", amount = {1, 2}, weight = 12, rarity = "uncommon"},

            -- Rare throwables
            {item = "flashbang", amount = {1, 2}, weight = 8, rarity = "rare"},
            {item = "c4", amount = {1, 1}, weight = 4, rarity = "rare"},
        },

        --==================================================================
        -- TRAPS
        --==================================================================
        traps = {
            -- Uncommon traps
            {item = "bear_trap", amount = {1, 2}, weight = 10, rarity = "uncommon"},
            {item = "tripwire", amount = {1, 2}, weight = 8, rarity = "uncommon"},

            -- Rare traps
            {item = "spike_trap", amount = {1, 1}, weight = 5, rarity = "rare"},
            {item = "tranq_trap", amount = {1, 1}, weight = 4, rarity = "rare"},
        },

        --==================================================================
        -- AMMUNITION
        --==================================================================
        ammo = {
            {item = "light_ammo", amount = {20, 40}, weight = 30},
            {item = "medium_ammo", amount = {15, 30}, weight = 25},
            {item = "heavy_ammo", amount = {5, 15}, weight = 15},
            {item = "shells", amount = {5, 10}, weight = 20},
            {item = "rockets", amount = {1, 3}, weight = 5},
        },

        --==================================================================
        -- HEALING & SHIELDS
        --==================================================================
        healing = {
            -- Health items
            {item = "bandage", amount = {3, 5}, weight = 35, heal = 15},
            {item = "medkit", amount = {1, 2}, weight = 20, heal = 50},
            {item = "health_kit", amount = {1, 1}, weight = 5, heal = 100},

            -- Shield items
            {item = "mini_shield", amount = {1, 3}, weight = 25, shield = 25},
            {item = "shield_potion", amount = {1, 2}, weight = 15, shield = 50},
            {item = "big_shield", amount = {1, 1}, weight = 5, shield = 100},
        },

        --==================================================================
        -- ATTACHMENTS
        --==================================================================
        attachments = {
            -- Scopes
            {item = "red_dot", weight = 15, rarity = "uncommon"},
            {item = "scope_2x", weight = 10, rarity = "uncommon"},
            {item = "scope_4x", weight = 6, rarity = "rare"},
            {item = "scope_8x", weight = 2, rarity = "epic"},
            {item = "thermal_scope", weight = 1, rarity = "legendary"},

            -- Grips
            {item = "vertical_grip", weight = 12, rarity = "uncommon"},
            {item = "angled_grip", weight = 10, rarity = "uncommon"},
            {item = "stabilizer_grip", weight = 4, rarity = "rare"},

            -- Magazines
            {item = "extended_mag", weight = 10, rarity = "uncommon"},
            {item = "quickdraw_mag", weight = 8, rarity = "rare"},

            -- Muzzles
            {item = "compensator", weight = 8, rarity = "uncommon"},
            {item = "light_suppressor", weight = 5, rarity = "rare"},
            {item = "heavy_suppressor", weight = 2, rarity = "epic"},
        },
    }
end

--[[
    Spawn all loot for match start
    Refreshes spawn points from MapService to ensure we have the latest data
]]
function LootSystem:SpawnAllLoot()
    if isActive then
        framework.Log("Warn", "LootSystem already active")
        return
    end

    isActive = true
    groundLoot = {}

    -- Refresh spawn points from MapService (may have been generated after our Initialize)
    self:LoadSpawnPoints()

    local density = gameConfig.Loot.density
    local spawnChance = 1.0

    if density == "low" then
        spawnChance = 0.5
    elseif density == "medium" then
        spawnChance = 0.75
    elseif density == "high" then
        spawnChance = 1.0
    end

    local spawnedCount = 0

    framework.Log("Info", "Spawning loot at %d spawn points with density '%s' (chance: %.0f%%)",
        #spawnPoints, density, spawnChance * 100)

    for _, spawnPoint in ipairs(spawnPoints) do
        if math.random() <= spawnChance then
            self:SpawnLootAtPoint(spawnPoint)
            spawnedCount = spawnedCount + 1
        end
    end

    -- Spawn chests
    for _, chest in ipairs(chests) do
        self:SpawnChest(chest)
    end

    framework.Log("Info", "Spawned %d loot items and %d chests", spawnedCount, #chests)
end

--[[
    Spawn loot at a specific point
]]
function LootSystem:SpawnLootAtPoint(spawnPoint)
    -- Determine what to spawn
    local lootType = self:SelectLootType()
    local item = self:SelectItem(lootType, spawnPoint.rarity)

    if not item then return nil end

    -- Create loot model
    local lootId = game:GetService("HttpService"):GenerateGUID(false)

    local lootData = {
        id = lootId,
        type = lootType,
        item = item.item,
        rarity = item.rarity,
        amount = item.amount and math.random(item.amount[1], item.amount[2]) or 1,
        position = spawnPoint.position,
        model = nil,
    }

    -- Create visual model
    lootData.model = self:CreateLootModel(lootData)

    -- Store in active loot
    groundLoot[lootId] = lootData

    -- Broadcast spawn
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.LootSpawned:FireAllClients({
            id = lootId,
            type = lootType,
            item = item.item,
            position = spawnPoint.position,
            rarity = item.rarity,
        })
    end

    return lootData
end

--[[
    Select loot type based on weighted probabilities
    Categories: weapons, melee, explosives, throwables, traps, ammo, healing, attachments
]]
function LootSystem:SelectLootType()
    local roll = math.random() * 100

    -- Loot type weights (must sum to 100)
    -- Ranged weapons: 25%
    -- Melee weapons: 5%
    -- Explosives: 2%
    -- Throwables: 8%
    -- Traps: 5%
    -- Ammo: 25%
    -- Healing: 20%
    -- Attachments: 10%

    if roll <= 25 then
        return "weapons"
    elseif roll <= 30 then
        return "melee"
    elseif roll <= 32 then
        return "explosives"
    elseif roll <= 40 then
        return "throwables"
    elseif roll <= 45 then
        return "traps"
    elseif roll <= 70 then
        return "ammo"
    elseif roll <= 90 then
        return "healing"
    else
        return "attachments"
    end
end

--[[
    Select specific item from loot table
]]
function LootSystem:SelectItem(lootType, forcedRarity)
    local lootTable = lootTables[lootType]
    if not lootTable then return nil end

    -- Filter by rarity if forced
    local validItems = {}
    local totalWeight = 0

    for _, item in ipairs(lootTable) do
        if not forcedRarity or item.rarity == forcedRarity then
            table.insert(validItems, item)
            totalWeight = totalWeight + item.weight
        end
    end

    -- If no valid items with forced rarity, use all items
    if #validItems == 0 then
        validItems = lootTable
        totalWeight = 0
        for _, item in ipairs(validItems) do
            totalWeight = totalWeight + item.weight
        end
    end

    -- Weighted random selection
    local roll = math.random() * totalWeight
    local cumulative = 0

    for _, item in ipairs(validItems) do
        cumulative = cumulative + item.weight
        if roll <= cumulative then
            return item
        end
    end

    return validItems[1]
end

--[[
    Create visual model for loot
]]
function LootSystem:CreateLootModel(lootData)
    local lootFolder = workspace:FindFirstChild("GroundLoot")
    if not lootFolder then
        lootFolder = Instance.new("Folder")
        lootFolder.Name = "GroundLoot"
        lootFolder.Parent = workspace
    end

    -- Raycast to find ground level for proper placement
    local spawnPos = lootData.position
    local rayOrigin = Vector3.new(spawnPos.X, 500, spawnPos.Z)  -- Start high
    local rayDirection = Vector3.new(0, -600, 0)  -- Ray down

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {workspace:FindFirstChild("GroundLoot") or workspace}
    raycastParams.IgnoreWater = true  -- Find solid ground, not water surface

    local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    local groundY = 5  -- Default to base terrain height if no ground found

    if result then
        groundY = result.Position.Y
    end

    -- Create simple part for now
    local model = Instance.new("Part")
    model.Name = lootData.id
    model.Size = Vector3.new(2, 1, 2)
    model.Position = Vector3.new(spawnPos.X, groundY + 0.5, spawnPos.Z)
    model.Anchored = true
    model.CanCollide = false

    -- Set color based on rarity
    local rarityColor = gameConfig.Loot.rarityColors[lootData.rarity]
    if rarityColor then
        model.Color = rarityColor
    else
        model.Color = Color3.fromRGB(180, 180, 180)
    end

    -- Add glow effect for higher rarities
    if lootData.rarity == "epic" or lootData.rarity == "legendary" then
        local light = Instance.new("PointLight")
        light.Color = rarityColor
        light.Brightness = 1
        light.Range = 10
        light.Parent = model
    end

    -- Store item data as attributes
    model:SetAttribute("LootId", lootData.id)
    model:SetAttribute("LootType", lootData.type)
    model:SetAttribute("Item", lootData.item)
    model:SetAttribute("Amount", lootData.amount)
    model:SetAttribute("Rarity", lootData.rarity)

    -- Add proximity prompt
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Pick up"
    prompt.ObjectText = self:GetItemDisplayName(lootData.item, lootData.amount)
    prompt.MaxActivationDistance = gameConfig.Player.pickupRange
    prompt.Parent = model

    -- Connect pickup
    prompt.Triggered:Connect(function(playerWhoTriggered)
        self:PickupLoot(playerWhoTriggered, lootData.id)
    end)

    model.Parent = lootFolder

    return model
end

--[[
    Get display name for item
    Includes all weapon types, consumables, and equipment
]]
function LootSystem:GetItemDisplayName(item, amount)
    local displayNames = {
        -- Pistols
        glock = "Glock",
        deagle = "Desert Eagle",
        revolver = "Revolver",

        -- SMGs
        uzi = "UZI",
        mp5 = "MP5",
        p90 = "P90",

        -- Shotguns
        pump_shotgun = "Pump Shotgun",
        tactical_shotgun = "Tactical Shotgun",
        double_barrel = "Double Barrel",

        -- Assault Rifles
        ak47 = "AK-47",
        m4a1 = "M4A1",
        scar = "SCAR",

        -- Snipers
        semi_sniper = "Semi-Auto Sniper",
        bolt_sniper = "Bolt Sniper",
        heavy_sniper = "Heavy Sniper",

        -- Melee Weapons
        combat_knife = "Combat Knife",
        machete = "Machete",
        stun_baton = "Stun Baton",
        spear = "Spear",

        -- Explosives
        rocket_launcher = "Rocket Launcher",
        grenade_launcher = "Grenade Launcher",

        -- Throwables
        frag_grenade = "Frag Grenade",
        smoke_grenade = "Smoke Grenade",
        molotov = "Molotov Cocktail",
        flashbang = "Flashbang",
        c4 = "C4 Explosive",

        -- Traps
        bear_trap = "Bear Trap",
        tripwire = "Tripwire Alarm",
        spike_trap = "Spike Trap",
        tranq_trap = "Tranquilizer Trap",

        -- Ammo
        light_ammo = "Light Ammo",
        medium_ammo = "Medium Ammo",
        heavy_ammo = "Heavy Ammo",
        shells = "Shotgun Shells",
        rockets = "Rockets",

        -- Healing
        bandage = "Bandage",
        medkit = "Med Kit",
        health_kit = "Health Kit",
        mini_shield = "Mini Shield",
        shield_potion = "Shield Potion",
        big_shield = "Big Shield",

        -- Attachments - Scopes
        red_dot = "Red Dot Sight",
        scope_2x = "2x Scope",
        scope_4x = "4x Scope",
        scope_8x = "8x Scope",
        thermal_scope = "Thermal Scope",

        -- Attachments - Grips
        vertical_grip = "Vertical Grip",
        angled_grip = "Angled Grip",
        stabilizer_grip = "Stabilizer Grip",

        -- Attachments - Magazines
        extended_mag = "Extended Magazine",
        quickdraw_mag = "Quickdraw Magazine",

        -- Attachments - Muzzles
        compensator = "Compensator",
        light_suppressor = "Light Suppressor",
        heavy_suppressor = "Heavy Suppressor",
    }

    local name = displayNames[item] or item

    if amount and amount > 1 then
        name = name .. " x" .. amount
    end

    return name
end

--[[
    Handle loot pickup
    Supports all loot types: weapons, melee, explosives, throwables, traps, ammo, healing, attachments
]]
function LootSystem:PickupLoot(player, lootId)
    local lootData = groundLoot[lootId]
    if not lootData then return false end

    local success = false
    local weaponService = framework:GetService("WeaponService")
    local playerInventory = framework:GetModule("PlayerInventory")

    -- Handle based on loot type
    if lootData.type == "weapons" or lootData.type == "melee" or lootData.type == "explosives" then
        -- All weapon types go through WeaponService
        if weaponService then
            success = weaponService:GiveWeapon(player, lootData.item)
        end

    elseif lootData.type == "throwables" then
        -- Throwables use WeaponService
        if weaponService then
            success = weaponService:GiveThrowable(player, lootData.item, lootData.amount or 1)
        end

    elseif lootData.type == "traps" then
        -- Traps go to PlayerInventory
        if playerInventory then
            success = playerInventory:GiveTrap(player, lootData.item, lootData.amount or 1)
        end

    elseif lootData.type == "ammo" then
        -- Ammo through WeaponService or PlayerInventory
        if weaponService then
            local ammoType = self:GetAmmoType(lootData.item)
            success = weaponService:GiveAmmo(player, ammoType, lootData.amount)
        end

    elseif lootData.type == "healing" then
        -- Healing items go to PlayerInventory as consumables
        if playerInventory then
            success = playerInventory:GiveConsumable(player, lootData.item, lootData.amount or 1)
        else
            -- Fallback: apply immediately
            success = self:ApplyHealing(player, lootData)
        end

    elseif lootData.type == "attachments" then
        -- Attachments - store for later equipping
        -- For now, broadcast that player has attachment
        -- Full implementation would add to player's attachment inventory
        success = true
        framework.Log("Debug", "%s picked up attachment: %s", player.Name, lootData.item)
    end

    if success then
        -- Remove from world
        if lootData.model then
            lootData.model:Destroy()
        end
        groundLoot[lootId] = nil

        -- Broadcast pickup
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
            remotes.LootPickedUp:FireAllClients({
                id = lootId,
                playerId = player.UserId,
                item = lootData.item,
                type = lootData.type,
            })
        end

        framework.Log("Debug", "%s picked up %s (%s)", player.Name, lootData.item, lootData.type)
    end

    return success
end

--[[
    Get ammo type from item name
]]
function LootSystem:GetAmmoType(item)
    local ammoTypes = {
        light_ammo = "light",
        medium_ammo = "medium",
        heavy_ammo = "heavy",
        shells = "shells",
    }
    return ammoTypes[item] or "light"
end

--[[
    Apply healing item
]]
function LootSystem:ApplyHealing(player, lootData)
    local character = player.Character
    if not character then return false end

    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return false end

    local item = lootData.item

    if item == "bandage" or item == "medkit" then
        -- Find heal amount
        for _, healItem in ipairs(lootTables.healing) do
            if healItem.item == item then
                humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healItem.heal)
                break
            end
        end
    elseif item == "small_shield" or item == "big_shield" then
        -- Shield would be handled by player data system
        -- For now just return success
    end

    return true
end

--[[
    Spawn a chest with visual and audio indicators (FPS best practices)
]]
function LootSystem:SpawnChest(chestData)
    local chestFolder = workspace:FindFirstChild("Chests")
    if not chestFolder then
        chestFolder = Instance.new("Folder")
        chestFolder.Name = "Chests"
        chestFolder.Parent = workspace
    end

    -- Raycast to find ground level for proper placement
    local spawnPos = chestData.position
    local rayOrigin = Vector3.new(spawnPos.X, 500, spawnPos.Z)  -- Start high
    local rayDirection = Vector3.new(0, -600, 0)  -- Ray down

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {workspace:FindFirstChild("Chests") or workspace}
    raycastParams.IgnoreWater = true  -- Find solid ground, not water surface

    local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    local groundY = spawnPos.Y or 5  -- Default to provided Y or base terrain height

    if result then
        groundY = result.Position.Y
    end

    local adjustedPosition = Vector3.new(spawnPos.X, groundY + 1, spawnPos.Z)  -- +1 to sit on ground

    -- Create chest model
    local chest = Instance.new("Model")
    chest.Name = "Chest"

    -- Base (chest body)
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(3, 2, 2)
    base.Position = adjustedPosition
    base.Anchored = true
    base.CanCollide = true
    base.Color = Color3.fromRGB(139, 90, 43)
    base.Material = Enum.Material.Wood
    base.Parent = chest

    -- Lid
    local lid = Instance.new("Part")
    lid.Name = "Lid"
    lid.Size = Vector3.new(3, 0.5, 2)
    lid.Position = adjustedPosition + Vector3.new(0, 1.25, 0)
    lid.Anchored = true
    lid.CanCollide = false
    lid.Color = Color3.fromRGB(160, 110, 50)
    lid.Material = Enum.Material.Wood
    lid.Parent = chest

    -- Metal trim on lid
    local trim = Instance.new("Part")
    trim.Name = "Trim"
    trim.Size = Vector3.new(3.1, 0.2, 0.2)
    trim.Position = adjustedPosition + Vector3.new(0, 1.5, 0.9)
    trim.Anchored = true
    trim.CanCollide = false
    trim.Color = Color3.fromRGB(180, 160, 60)  -- Gold trim
    trim.Material = Enum.Material.Metal
    trim.Parent = chest

    chest.PrimaryPart = base

    -- ============ VISUAL INDICATORS (FPS Best Practice) ============

    -- Golden glow effect (visible from distance)
    local glow = Instance.new("PointLight")
    glow.Name = "ChestGlow"
    glow.Color = Color3.fromRGB(255, 215, 0)  -- Gold
    glow.Brightness = 1.5
    glow.Range = 20
    glow.Parent = base

    -- Particle sparkle effect
    local sparkle = Instance.new("ParticleEmitter")
    sparkle.Name = "Sparkle"
    sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 223, 128))
    sparkle.LightEmission = 0.5
    sparkle.LightInfluence = 0
    sparkle.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 0)
    })
    sparkle.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 1)
    })
    sparkle.Lifetime = NumberRange.new(0.5, 1)
    sparkle.Rate = 10
    sparkle.Speed = NumberRange.new(2, 4)
    sparkle.SpreadAngle = Vector2.new(180, 180)
    sparkle.Parent = base

    -- ============ AUDIO INDICATOR (FPS Best Practice) ============

    -- Ambient hum sound (helps players locate chests)
    local humSound = Instance.new("Sound")
    humSound.Name = "ChestHum"
    humSound.SoundId = "rbxassetid://9125402735"  -- Ambient hum
    humSound.Volume = 0.3
    humSound.Looped = true
    humSound.RollOffMode = Enum.RollOffMode.Linear
    humSound.RollOffMinDistance = 5
    humSound.RollOffMaxDistance = 40  -- Audible from 40 studs
    humSound.Parent = base
    humSound:Play()

    -- Store sounds for later use
    chest:SetAttribute("HasAudio", true)

    -- Add proximity prompt
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Open"
    prompt.ObjectText = "Loot Chest"
    prompt.MaxActivationDistance = gameConfig.Player.pickupRange or 10
    prompt.HoldDuration = 0.3  -- Quick open
    prompt.Parent = base

    prompt.Triggered:Connect(function(playerWhoTriggered)
        if not chestData.opened then
            self:OpenChest(playerWhoTriggered, chestData, chest)
        end
    end)

    chest.Parent = chestFolder
    chestData.model = chest

    framework.Log("Debug", "Spawned chest at %s with glow and audio", tostring(chestData.position))
end

--[[
    Open a chest and spawn loot with satisfying feedback
]]
function LootSystem:OpenChest(player, chestData, chestModel)
    chestData.opened = true

    local base = chestModel.PrimaryPart

    -- ============ STOP AMBIENT EFFECTS ============

    -- Stop the hum sound
    local humSound = base:FindFirstChild("ChestHum")
    if humSound then
        humSound:Stop()
    end

    -- Stop sparkle particles
    local sparkle = base:FindFirstChild("Sparkle")
    if sparkle then
        sparkle.Enabled = false
    end

    -- Dim the glow
    local glow = base:FindFirstChild("ChestGlow")
    if glow then
        glow.Brightness = 0.3
    end

    -- ============ PLAY OPEN SOUND ============

    local openSound = Instance.new("Sound")
    openSound.SoundId = "rbxassetid://9125402735"  -- Chest open sound
    openSound.Volume = 0.8
    openSound.Parent = base
    openSound:Play()

    -- ============ ANIMATE LID OPENING ============

    local lid = chestModel:FindFirstChild("Lid")
    local trim = chestModel:FindFirstChild("Trim")
    if lid then
        local originalLidCFrame = lid.CFrame
        local originalTrimCFrame = trim and trim.CFrame

        -- Smooth lid opening animation
        for i = 1, 15 do
            local angle = math.rad(-6 * i)  -- Open to 90 degrees
            lid.CFrame = originalLidCFrame * CFrame.new(0, 0, -1) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 0, 1)
            if trim then
                trim.CFrame = originalTrimCFrame * CFrame.new(0, 0, -1) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 0, 1)
            end
            task.wait(0.02)
        end
    end

    -- ============ BURST PARTICLE EFFECT ============

    local burst = Instance.new("ParticleEmitter")
    burst.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
    burst.LightEmission = 1
    burst.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0)
    })
    burst.Transparency = NumberSequence.new(0, 1)
    burst.Lifetime = NumberRange.new(0.5, 1)
    burst.Speed = NumberRange.new(10, 20)
    burst.SpreadAngle = Vector2.new(180, 180)
    burst.Parent = base
    burst:Emit(30)  -- Burst of 30 particles

    -- Clean up burst emitter after particles fade
    task.delay(1.5, function()
        if burst then burst:Destroy() end
    end)

    -- ============ SPAWN LOOT ============

    -- Spawn 2-4 items around chest
    local numItems = math.random(2, 4)
    local basePos = chestData.position

    for i = 1, numItems do
        local angle = (i / numItems) * math.pi * 2
        local offset = Vector3.new(math.cos(angle) * 3, 1, math.sin(angle) * 3)  -- Raised slightly

        local spawnPoint = {
            position = basePos + offset,
            type = "any",
            rarity = nil,
        }

        -- Higher chance of better loot from chests
        if math.random() < 0.3 then
            spawnPoint.rarity = "rare"
        elseif math.random() < 0.1 then
            spawnPoint.rarity = "epic"
        end

        self:SpawnLootAtPoint(spawnPoint)
    end

    -- Remove prompt
    local prompt = chestModel.PrimaryPart:FindFirstChild("ProximityPrompt")
    if prompt then
        prompt:Destroy()
    end

    -- Broadcast chest opened
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.ChestOpened:FireAllClients({
            position = chestData.position,
            playerId = player.UserId,
        })
    end

    framework.Log("Debug", "%s opened a chest", player.Name)
end

--[[
    Reset all loot (for new match)
]]
function LootSystem:ResetLoot()
    -- Destroy all ground loot
    for _, lootData in pairs(groundLoot) do
        if lootData.model then
            lootData.model:Destroy()
        end
    end
    groundLoot = {}

    -- Reset chests
    for _, chest in ipairs(chests) do
        chest.opened = false
        if chest.model then
            chest.model:Destroy()
        end
        chest.model = nil
    end

    isActive = false

    framework.Log("Info", "Loot system reset")
end

--[[
    Get all active loot (for debugging)
]]
function LootSystem:GetAllLoot()
    return groundLoot
end

--[[
    Spawn a dropped weapon as loot pickup
    Called by PlayerInventory when player drops a weapon
    @param weaponId string - Weapon identifier
    @param rarity string - Weapon rarity
    @param position Vector3 - World position to spawn at
    @return table|nil - Loot data or nil on failure
]]
function LootSystem:SpawnWeaponLoot(weaponId, rarity, position)
    local lootId = game:GetService("HttpService"):GenerateGUID(false)

    local lootData = {
        id = lootId,
        type = "weapons",
        item = weaponId,
        rarity = rarity or "common",
        amount = 1,
        position = position,
        model = nil,
    }

    -- Create visual model
    lootData.model = self:CreateLootModel(lootData)

    -- Store in active loot
    groundLoot[lootId] = lootData

    -- Broadcast spawn
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.LootSpawned:FireAllClients({
            id = lootId,
            type = "weapons",
            item = weaponId,
            position = position,
            rarity = rarity,
        })
    end

    framework.Log("Debug", "Spawned dropped weapon: %s at %s", weaponId, tostring(position))
    return lootData
end

--[[
    Spawn a specific item at position
    @param itemId string - Item identifier
    @param itemType string - Loot type (weapons, ammo, healing, etc.)
    @param position Vector3 - World position
    @param rarity string - Item rarity (optional)
    @param amount number - Stack amount (optional)
    @return table|nil - Loot data or nil on failure
]]
function LootSystem:SpawnLootItem(itemId, itemType, position, rarity, amount)
    local lootId = game:GetService("HttpService"):GenerateGUID(false)

    local lootData = {
        id = lootId,
        type = itemType,
        item = itemId,
        rarity = rarity or "common",
        amount = amount or 1,
        position = position,
        model = nil,
    }

    -- Create visual model
    lootData.model = self:CreateLootModel(lootData)

    -- Store in active loot
    groundLoot[lootId] = lootData

    -- Broadcast spawn
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.LootSpawned:FireAllClients({
            id = lootId,
            type = itemType,
            item = itemId,
            position = position,
            rarity = rarity,
            amount = amount,
        })
    end

    return lootData
end

return LootSystem
