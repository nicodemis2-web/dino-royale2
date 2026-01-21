--[[
    =========================================================================
    PlayerInventory - Player inventory and equipment management
    =========================================================================

    Manages player weapons, ammo, consumables, and equipment.
    This module handles the server-side storage and syncing of player items.

    Features:
    - 5 weapon slots with rarity and attachment support
    - Ammo storage by type (light, medium, heavy, shells, rockets)
    - Consumable/healing item storage (bandage, medkit, shields)
    - Throwable item storage (grenades, molotovs, C4)
    - Trap storage (bear trap, tripwire, landmine)
    - Real-time sync with client via RemoteEvents

    Architecture:
    - Server-authoritative: All inventory changes happen server-side
    - Client receives updates via InventoryUpdate and AmmoUpdate remotes
    - Integrates with WeaponService for weapon definitions
    - Integrates with LootSystem for dropped weapon spawning
    - Uses GameConfig for stack limits and item values

    Data Flow:
    1. Server modifies inventory via public methods (GiveWeapon, GiveAmmo, etc.)
    2. Module calls SyncInventory() to push changes to client
    3. Client receives InventoryUpdate event and updates UI

    =========================================================================
]]

-- Roblox service references
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerInventory = {}
PlayerInventory.__index = PlayerInventory

--=============================================================================
-- PRIVATE STATE
-- Module-level variables (not exposed externally)
--=============================================================================

-- Player inventory storage: Maps UserId to InventoryData table
-- This is the source of truth for all player inventories
local playerData = {}           -- UserId -> InventoryData

-- Module dependencies (set during Initialize)
local framework = nil           -- Service locator for GetService/GetModule
local gameConfig = nil          -- Game configuration (stack limits, etc.)

--=============================================================================
-- INVENTORY STRUCTURE
--=============================================================================

--[[
    InventoryData structure:
    {
        weapons = {
            [1] = {weaponId = "ak47", rarity = "rare", attachments = {}, currentAmmo = 30},
            [2] = nil,
            [3] = nil,
            [4] = nil,
            [5] = nil,
        },
        equippedSlot = 1,
        ammo = {
            light = 60,
            medium = 90,
            heavy = 15,
            shells = 20,
            rockets = 3,
        },
        consumables = {
            bandage = 5,
            medkit = 2,
            miniShield = 3,
            shield = 1,
        },
        throwables = {
            frag_grenade = 2,
            smoke_grenade = 1,
            molotov = 0,
        },
        traps = {
            bear_trap = 2,
            tripwire = 1,
        },
    }
]]

--=============================================================================
-- INITIALIZATION
--=============================================================================

--[[
    Initialize the PlayerInventory module
]]
function PlayerInventory:Initialize()
    -- Rojo maps to ReplicatedStorage.Framework and ReplicatedStorage.Shared
    framework = require(script.Parent.Parent.Framework)
    gameConfig = require(script.Parent.Parent.Shared.GameConfig)

    -- Setup remote event handlers
    self:SetupRemotes()

    framework.Log("Info", "PlayerInventory initialized")
    return self
end

--[[
    Setup remote event handlers for inventory actions
]]
function PlayerInventory:SetupRemotes()
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then return end

    -- Handle weapon equip requests
    local equipRemote = remoteFolder:FindFirstChild("WeaponEquip")
    if equipRemote then
        equipRemote.OnServerEvent:Connect(function(player, slotIndex)
            self:EquipWeaponSlot(player, slotIndex)
        end)
    end

    -- Handle weapon drop requests
    local dropRemote = remoteFolder:FindFirstChild("WeaponDrop")
    if dropRemote then
        dropRemote.OnServerEvent:Connect(function(player, slotIndex)
            self:DropWeapon(player, slotIndex)
        end)
    end
end

--=============================================================================
-- PLAYER DATA MANAGEMENT
--=============================================================================

--[[
    Initialize inventory for a new player
    @param player Player - The player to initialize
]]
function PlayerInventory:InitializePlayer(player)
    local data = {
        weapons = {
            [1] = nil,
            [2] = nil,
            [3] = nil,
            [4] = nil,
            [5] = nil,
        },
        equippedSlot = 1,
        ammo = {
            light = 0,
            medium = 0,
            heavy = 0,
            shells = 0,
            rockets = 0,
        },
        consumables = {},
        throwables = {},
        traps = {},
    }

    playerData[player.UserId] = data
    framework.Log("Debug", "Initialized inventory for %s", player.Name)

    -- Send initial inventory to client
    self:SyncInventory(player)
end

--[[
    Cleanup inventory when player leaves
    @param player Player - The player leaving
]]
function PlayerInventory:CleanupPlayer(player)
    playerData[player.UserId] = nil
    framework.Log("Debug", "Cleaned up inventory for %s", player.Name)
end

--[[
    Get a player's inventory data
    @param player Player - The player
    @return table|nil - Inventory data or nil if not found
]]
function PlayerInventory:GetInventory(player)
    return playerData[player.UserId]
end

--[[
    Reset a player's inventory (for new match)
    @param player Player - The player to reset
]]
function PlayerInventory:ResetInventory(player)
    local data = playerData[player.UserId]
    if not data then return end

    -- Clear all weapons
    for i = 1, 5 do
        data.weapons[i] = nil
    end
    data.equippedSlot = 1

    -- Clear all ammo
    for ammoType, _ in pairs(data.ammo) do
        data.ammo[ammoType] = 0
    end

    -- Clear consumables, throwables, traps
    data.consumables = {}
    data.throwables = {}
    data.traps = {}

    self:SyncInventory(player)
    framework.Log("Debug", "Reset inventory for %s", player.Name)
end

--=============================================================================
-- WEAPON MANAGEMENT
--=============================================================================

--[[
    Give a weapon to a player
    @param player Player - The player
    @param weaponId string - The weapon identifier
    @param rarity string - Weapon rarity (optional, defaults to "common")
    @param attachments table - List of attachments (optional)
    @return boolean - Success status
]]
function PlayerInventory:GiveWeapon(player, weaponId, rarity, attachments)
    local data = playerData[player.UserId]
    if not data then
        framework.Log("Warn", "No inventory for player %s", player.Name)
        return false
    end

    -- Get weapon definition from WeaponService
    local weaponService = framework:GetService("WeaponService")
    local weaponDef = nil
    if weaponService and weaponService.GetWeaponDefinition then
        weaponDef = weaponService:GetWeaponDefinition(weaponId)
    end

    if not weaponDef then
        framework.Log("Warn", "Unknown weapon: %s", weaponId)
        return false
    end

    -- Find empty slot or matching category slot
    local targetSlot = nil
    local categorySlot = gameConfig.Weapons.categories[weaponDef.category]
    local preferredSlot = categorySlot and categorySlot.slot or 1

    -- First try preferred slot
    if preferredSlot >= 1 and preferredSlot <= 5 then
        if not data.weapons[preferredSlot] then
            targetSlot = preferredSlot
        end
    end

    -- If preferred slot is full, find any empty slot
    if not targetSlot then
        for i = 1, 5 do
            if not data.weapons[i] then
                targetSlot = i
                break
            end
        end
    end

    -- If no empty slots, replace current equipped weapon
    if not targetSlot then
        targetSlot = data.equippedSlot
        -- Drop the current weapon first
        self:DropWeapon(player, targetSlot)
    end

    -- Create weapon instance
    local weaponInstance = {
        weaponId = weaponId,
        rarity = rarity or "common",
        attachments = attachments or {},
        currentAmmo = weaponDef.magazineSize or 30,
    }

    data.weapons[targetSlot] = weaponInstance

    -- Sync with client
    self:SyncInventory(player)

    -- Notify client
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local pickupRemote = remotes:FindFirstChild("WeaponPickup")
        if pickupRemote then
            pickupRemote:FireClient(player, {
                slot = targetSlot,
                weaponId = weaponId,
                rarity = rarity,
            })
        end
    end

    framework.Log("Debug", "%s picked up %s (%s) in slot %d", player.Name, weaponId, rarity or "common", targetSlot)
    return true
end

--[[
    Remove a weapon from player's inventory
    @param player Player - The player
    @param slotIndex number - The slot to clear (1-5)
    @return table|nil - The removed weapon data
]]
function PlayerInventory:RemoveWeapon(player, slotIndex)
    local data = playerData[player.UserId]
    if not data then return nil end

    local weapon = data.weapons[slotIndex]
    data.weapons[slotIndex] = nil

    self:SyncInventory(player)
    return weapon
end

--[[
    Drop a weapon at player's position (creates loot pickup)
    @param player Player - The player
    @param slotIndex number - The slot to drop
]]
function PlayerInventory:DropWeapon(player, slotIndex)
    local data = playerData[player.UserId]
    if not data then return end

    local weapon = data.weapons[slotIndex]
    if not weapon then return end

    -- Get drop position
    local character = player.Character
    local dropPosition = Vector3.new(0, 5, 0)
    if character and character:FindFirstChild("HumanoidRootPart") then
        dropPosition = character.HumanoidRootPart.Position + Vector3.new(0, 0, 3)
    end

    -- Remove from inventory
    data.weapons[slotIndex] = nil

    -- Spawn as loot pickup
    local lootSystem = framework:GetModule("LootSystem")
    if lootSystem and lootSystem.SpawnWeaponLoot then
        lootSystem:SpawnWeaponLoot(weapon.weaponId, weapon.rarity, dropPosition)
    end

    self:SyncInventory(player)

    -- Notify client
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local dropRemote = remotes:FindFirstChild("WeaponDrop")
        if dropRemote then
            dropRemote:FireClient(player, slotIndex)
        end
    end

    framework.Log("Debug", "%s dropped %s from slot %d", player.Name, weapon.weaponId, slotIndex)
end

--[[
    Equip a weapon slot
    @param player Player - The player
    @param slotIndex number - The slot to equip (1-5)
]]
function PlayerInventory:EquipWeaponSlot(player, slotIndex)
    local data = playerData[player.UserId]
    if not data then return end

    if slotIndex < 1 or slotIndex > 5 then return end

    data.equippedSlot = slotIndex

    -- Notify all clients (for third-person weapon display)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local equipRemote = remotes:FindFirstChild("WeaponEquip")
        if equipRemote then
            local weapon = data.weapons[slotIndex]
            equipRemote:FireAllClients(player.UserId, slotIndex, weapon and weapon.weaponId or nil)
        end
    end
end

--[[
    Get currently equipped weapon
    @param player Player - The player
    @return table|nil - Weapon data or nil
]]
function PlayerInventory:GetEquippedWeapon(player)
    local data = playerData[player.UserId]
    if not data then return nil end

    return data.weapons[data.equippedSlot]
end

--[[
    Get weapon in specific slot
    @param player Player - The player
    @param slotIndex number - Slot index (1-5)
    @return table|nil - Weapon data or nil
]]
function PlayerInventory:GetWeaponInSlot(player, slotIndex)
    local data = playerData[player.UserId]
    if not data then return nil end

    return data.weapons[slotIndex]
end

--=============================================================================
-- AMMO MANAGEMENT
--=============================================================================

--[[
    Give ammo to a player
    @param player Player - The player
    @param ammoType string - Type of ammo (light, medium, heavy, shells, rockets)
    @param amount number - Amount to add
    @return boolean - Success status
]]
function PlayerInventory:GiveAmmo(player, ammoType, amount)
    local data = playerData[player.UserId]
    if not data then return false end

    if not data.ammo[ammoType] then
        framework.Log("Warn", "Unknown ammo type: %s", ammoType)
        return false
    end

    local maxAmmo = gameConfig.Player.maxStackSize.ammo
    data.ammo[ammoType] = math.min(data.ammo[ammoType] + amount, maxAmmo)

    -- Sync ammo with client
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local ammoRemote = remotes:FindFirstChild("AmmoUpdate")
        if ammoRemote then
            ammoRemote:FireClient(player, data.ammo)
        end
    end

    framework.Log("Debug", "%s received %d %s ammo", player.Name, amount, ammoType)
    return true
end

--[[
    Consume ammo from player
    @param player Player - The player
    @param ammoType string - Type of ammo
    @param amount number - Amount to consume
    @return boolean - True if had enough ammo
]]
function PlayerInventory:ConsumeAmmo(player, ammoType, amount)
    local data = playerData[player.UserId]
    if not data then return false end

    if not data.ammo[ammoType] or data.ammo[ammoType] < amount then
        return false
    end

    data.ammo[ammoType] = data.ammo[ammoType] - amount
    return true
end

--[[
    Get player's ammo count for a type
    @param player Player - The player
    @param ammoType string - Type of ammo
    @return number - Current ammo count
]]
function PlayerInventory:GetAmmo(player, ammoType)
    local data = playerData[player.UserId]
    if not data or not data.ammo[ammoType] then return 0 end

    return data.ammo[ammoType]
end

--[[
    Reload the equipped weapon from ammo reserves
    @param player Player - The player
    @return boolean - Success status
]]
function PlayerInventory:ReloadEquipped(player)
    local data = playerData[player.UserId]
    if not data then return false end

    local weapon = data.weapons[data.equippedSlot]
    if not weapon then return false end

    -- Get weapon definition
    local weaponService = framework:GetService("WeaponService")
    local weaponDef = nil
    if weaponService and weaponService.GetWeaponDefinition then
        weaponDef = weaponService:GetWeaponDefinition(weapon.weaponId)
    end

    if not weaponDef then return false end

    -- Get ammo type for this weapon
    local categoryConfig = gameConfig.Weapons.categories[weaponDef.category]
    if not categoryConfig or categoryConfig.ammoType == "none" then
        return false -- Melee or no ammo weapon
    end

    local ammoType = categoryConfig.ammoType
    local magSize = weaponDef.magazineSize
    local neededAmmo = magSize - weapon.currentAmmo

    if neededAmmo <= 0 then return false end -- Already full

    local availableAmmo = data.ammo[ammoType] or 0
    local ammoToLoad = math.min(neededAmmo, availableAmmo)

    if ammoToLoad <= 0 then return false end -- No ammo available

    -- Transfer ammo
    data.ammo[ammoType] = data.ammo[ammoType] - ammoToLoad
    weapon.currentAmmo = weapon.currentAmmo + ammoToLoad

    self:SyncInventory(player)
    return true
end

--=============================================================================
-- CONSUMABLES MANAGEMENT
--=============================================================================

--[[
    Give a consumable item to player
    @param player Player - The player
    @param itemId string - Item identifier
    @param amount number - Amount to add
    @return boolean - Success status
]]
function PlayerInventory:GiveConsumable(player, itemId, amount)
    local data = playerData[player.UserId]
    if not data then return false end

    local maxStack = gameConfig.Player.maxStackSize.consumable
    local current = data.consumables[itemId] or 0

    data.consumables[itemId] = math.min(current + amount, maxStack)

    self:SyncInventory(player)
    return true
end

-- Active healing channels (UserId -> {itemId, startTime, duration, thread})
local activeHealingChannels = {}

--[[
    Use a consumable item (with GDD-compliant use times)
    Items now require channeling before taking effect.
    Taking damage or moving interrupts the channel.

    @param player Player - The player
    @param itemId string - Item identifier
    @return boolean - Success status (started channeling)
]]
function PlayerInventory:UseConsumable(player, itemId)
    local data = playerData[player.UserId]
    if not data then return false end

    local current = data.consumables[itemId] or 0
    if current <= 0 then return false end

    -- Check if already channeling
    if activeHealingChannels[player.UserId] then
        framework.Log("Debug", "%s already channeling a heal", player.Name)
        return false
    end

    -- Get use time from config (GDD compliant)
    local useTimes = gameConfig.Loot.healingUseTimes
    local useTime = useTimes and useTimes[itemId] or 0

    -- If no use time configured, apply instantly (legacy behavior)
    if useTime <= 0 then
        return self:ApplyConsumableEffect(player, itemId)
    end

    -- Reserve the item (remove from inventory now, refund if cancelled)
    data.consumables[itemId] = current - 1
    self:SyncInventory(player)

    -- Notify client that channeling started
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local channelRemote = remotes:FindFirstChild("HealingChannelStarted")
        if channelRemote then
            channelRemote:FireClient(player, {
                itemId = itemId,
                duration = useTime,
            })
        end
    end

    -- Store channel state
    local channelData = {
        itemId = itemId,
        startTime = tick(),
        duration = useTime,
        startHealth = nil,
    }

    -- Track starting health for interrupt detection
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    if humanoid then
        channelData.startHealth = humanoid.Health
    end

    activeHealingChannels[player.UserId] = channelData

    -- Start channel thread
    channelData.thread = task.spawn(function()
        local interrupted = false
        local elapsed = 0

        -- Check for interrupts during channel
        while elapsed < useTime do
            task.wait(0.1)
            elapsed = tick() - channelData.startTime

            -- Check if channel was cancelled externally
            if not activeHealingChannels[player.UserId] then
                interrupted = true
                break
            end

            -- Check if player took damage (interrupt condition)
            if humanoid and channelData.startHealth then
                if humanoid.Health < channelData.startHealth then
                    interrupted = true
                    framework.Log("Debug", "%s healing interrupted by damage", player.Name)
                    break
                end
            end

            -- Check if player is still alive
            if not humanoid or humanoid.Health <= 0 then
                interrupted = true
                break
            end
        end

        -- Clear channel state
        activeHealingChannels[player.UserId] = nil

        if interrupted then
            -- Refund the item
            local currentData = playerData[player.UserId]
            if currentData then
                currentData.consumables[itemId] = (currentData.consumables[itemId] or 0) + 1
                self:SyncInventory(player)
            end

            -- Notify client of interruption
            if remotes then
                local interruptRemote = remotes:FindFirstChild("HealingChannelInterrupted")
                if interruptRemote then
                    interruptRemote:FireClient(player, itemId)
                end
            end
        else
            -- Channel completed, apply the effect
            self:ApplyConsumableEffect(player, itemId)

            -- Notify client of completion
            if remotes then
                local completeRemote = remotes:FindFirstChild("ItemConsumed")
                if completeRemote then
                    completeRemote:FireClient(player, itemId)
                end
            end
        end
    end)

    return true
end

--[[
    Cancel active healing channel
    @param player Player - The player
]]
function PlayerInventory:CancelHealingChannel(player)
    local channel = activeHealingChannels[player.UserId]
    if channel then
        -- Thread will detect cancellation and handle refund
        activeHealingChannels[player.UserId] = nil
        framework.Log("Debug", "%s cancelled healing channel", player.Name)
    end
end

--[[
    Apply the effect of a consumable item
    @param player Player - The player
    @param itemId string - Item identifier
    @return boolean - Success status
]]
function PlayerInventory:ApplyConsumableEffect(player, itemId)
    local healValues = gameConfig.Loot.healingValues
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")

    if humanoid and healValues[itemId] then
        -- Health items
        if itemId == "bandage" or itemId == "medkit" or itemId == "healthKit" then
            humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healValues[itemId])
            framework.Log("Debug", "%s healed for %d HP using %s", player.Name, healValues[itemId], itemId)
        end
        -- Shield items - check for shield attribute or separate system
        if itemId == "miniShield" or itemId == "shield" or itemId == "bigShield" then
            local currentShield = humanoid:GetAttribute("Shield") or 0
            local maxShield = gameConfig.Player.maxShield or 100
            local newShield = math.min(maxShield, currentShield + healValues[itemId])
            humanoid:SetAttribute("Shield", newShield)
            framework.Log("Debug", "%s gained %d shield using %s", player.Name, healValues[itemId], itemId)
        end
    end

    return true
end

--=============================================================================
-- THROWABLES MANAGEMENT
--=============================================================================

--[[
    Give a throwable item to player
    @param player Player - The player
    @param itemId string - Throwable identifier
    @param amount number - Amount to add
    @return boolean - Success status
]]
function PlayerInventory:GiveThrowable(player, itemId, amount)
    local data = playerData[player.UserId]
    if not data then return false end

    local maxStack = gameConfig.Player.maxStackSize.throwable
    local current = data.throwables[itemId] or 0

    data.throwables[itemId] = math.min(current + amount, maxStack)

    self:SyncInventory(player)
    return true
end

--[[
    Consume a throwable (when thrown)
    @param player Player - The player
    @param itemId string - Throwable identifier
    @return boolean - Success status
]]
function PlayerInventory:ConsumeThrowable(player, itemId)
    local data = playerData[player.UserId]
    if not data then return false end

    local current = data.throwables[itemId] or 0
    if current <= 0 then return false end

    data.throwables[itemId] = current - 1
    self:SyncInventory(player)
    return true
end

--=============================================================================
-- TRAPS MANAGEMENT
--=============================================================================

--[[
    Give a trap to player
    @param player Player - The player
    @param trapId string - Trap identifier
    @param amount number - Amount to add
    @return boolean - Success status
]]
function PlayerInventory:GiveTrap(player, trapId, amount)
    local data = playerData[player.UserId]
    if not data then return false end

    local maxStack = gameConfig.Player.maxStackSize.trap
    local current = data.traps[trapId] or 0

    data.traps[trapId] = math.min(current + amount, maxStack)

    self:SyncInventory(player)
    return true
end

--[[
    Consume a trap (when placed)
    @param player Player - The player
    @param trapId string - Trap identifier
    @return boolean - Success status
]]
function PlayerInventory:ConsumeTrap(player, trapId)
    local data = playerData[player.UserId]
    if not data then return false end

    local current = data.traps[trapId] or 0
    if current <= 0 then return false end

    data.traps[trapId] = current - 1
    self:SyncInventory(player)
    return true
end

--[[
    Get count of placed traps by player
    @param player Player - The player
    @return number - Count of active traps
]]
function PlayerInventory:GetPlacedTrapCount(player)
    -- This would query WeaponService for active traps owned by player
    local weaponService = framework:GetService("WeaponService")
    if weaponService and weaponService.GetPlayerTrapCount then
        return weaponService:GetPlayerTrapCount(player)
    end
    return 0
end

--=============================================================================
-- SYNC & SERIALIZATION
--=============================================================================

--[[
    Sync full inventory state to client
    @param player Player - The player to sync
]]
function PlayerInventory:SyncInventory(player)
    local data = playerData[player.UserId]
    if not data then return end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    local inventoryRemote = remotes:FindFirstChild("InventoryUpdate")
    if inventoryRemote then
        inventoryRemote:FireClient(player, {
            weapons = data.weapons,
            equippedSlot = data.equippedSlot,
            ammo = data.ammo,
            consumables = data.consumables,
            throwables = data.throwables,
            traps = data.traps,
        })
    end
end

--[[
    Get serialized inventory for saving/debugging
    @param player Player - The player
    @return table - Serialized inventory data
]]
function PlayerInventory:SerializeInventory(player)
    local data = playerData[player.UserId]
    if not data then return {} end

    return {
        weapons = data.weapons,
        equippedSlot = data.equippedSlot,
        ammo = data.ammo,
        consumables = data.consumables,
        throwables = data.throwables,
        traps = data.traps,
    }
end

return PlayerInventory
