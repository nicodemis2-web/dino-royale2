--[[
    Remotes - Network communication definitions
    Centralizes all remote events and functions used in the game
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- List of all remote events used in the game
Remotes.Events = {
    -- Game State
    "GameStateChanged",
    "MatchStarting",
    "VictoryDeclared",
    "UpdatePlayersAlive",
    "UpdateStormPhase",
    "RequestGameMode",
    "LobbyStatusUpdate",
    "CountdownUpdate",

    -- Player/Squad
    "PlayerEliminated",
    "SquadUpdate",
    "TeammateStateChanged",
    "ReviveStarted",
    "ReviveCompleted",
    "ReviveCancelled",
    "SpectateTeammate",
    "PlayerDowned",

    -- Storm
    "StormPhaseChanged",
    "StormPositionUpdate",
    "StormWarning",
    "StormDamage",

    -- Weapons
    "WeaponFire",
    "WeaponReload",
    "WeaponEquip",
    "WeaponDrop",
    "WeaponPickup",
    "BulletHit",
    "DamageDealt",
    "MeleeAttack",
    "ThrowableThrown",
    "ExplosionEffect",

    -- Traps
    "TrapPlaced",
    "TrapTriggered",
    "TrapDestroyed",

    -- Dinosaurs
    "DinoSpawned",
    "DinoDamaged",
    "DinoDied",
    "DinoAttack",
    "DinoAbility",
    "DinoStateUpdate",
    "PackAlert",

    -- Boss Dinosaurs
    "BossSpawned",
    "BossPhaseChanged",
    "BossDied",
    "BossAbility",

    -- Dragon Events
    "DragonApproaching",     -- Dragon raid starting warning
    "DragonAttack",          -- Dragon attack notification
    "DragonDeparted",        -- Dragon has left the island

    -- Map Events
    "MapEventStarted",
    "MapEventEnded",
    "EnvironmentalDamage",
    "SupplyDropSpawned",
    "SupplyDropLanded",

    -- Inventory
    "InventoryUpdate",
    "AmmoUpdate",
    "ItemConsumed",
    "HealingChannelStarted",      -- Player started channeling a heal
    "HealingChannelInterrupted",  -- Healing was interrupted (damage, movement, etc.)

    -- Loot
    "LootSpawned",
    "LootPickedUp",
    "ChestOpened",
}

-- List of all remote functions (request-response pattern)
Remotes.Functions = {
    "GetPlayerInventory",
    "GetGameState",
    "GetSquadInfo",
}

-- Get or create the Remotes folder
function Remotes.GetFolder()
    local folder = ReplicatedStorage:FindFirstChild("Remotes")

    -- Create folder if it doesn't exist (server only)
    if not folder and RunService:IsServer() then
        folder = Instance.new("Folder")
        folder.Name = "Remotes"
        folder.Parent = ReplicatedStorage
    end

    return folder
end

-- Setup all remotes (call on server)
function Remotes.Setup()
    if not RunService:IsServer() then
        warn("[Remotes] Setup should only be called on server")
        return
    end

    local folder = Remotes.GetFolder()

    -- Create all events
    for _, eventName in ipairs(Remotes.Events) do
        if not folder:FindFirstChild(eventName) then
            local event = Instance.new("RemoteEvent")
            event.Name = eventName
            event.Parent = folder
        end
    end

    -- Create all functions
    for _, funcName in ipairs(Remotes.Functions) do
        if not folder:FindFirstChild(funcName) then
            local func = Instance.new("RemoteFunction")
            func.Name = funcName
            func.Parent = folder
        end
    end

    print("[Remotes] Setup complete - created", #Remotes.Events, "events and", #Remotes.Functions, "functions")
end

-- Get a remote event by name
function Remotes.GetEvent(eventName)
    local folder = Remotes.GetFolder()
    if not folder then
        warn("[Remotes] Folder not found")
        return nil
    end

    local event = folder:FindFirstChild(eventName)
    if not event then
        warn("[Remotes] Event not found:", eventName)
        return nil
    end

    return event
end

-- Get a remote function by name
function Remotes.GetFunction(funcName)
    local folder = Remotes.GetFolder()
    if not folder then
        warn("[Remotes] Folder not found")
        return nil
    end

    local func = folder:FindFirstChild(funcName)
    if not func then
        warn("[Remotes] Function not found:", funcName)
        return nil
    end

    return func
end

-- Fire an event to all clients
function Remotes.FireAllClients(eventName, ...)
    local event = Remotes.GetEvent(eventName)
    if event then
        event:FireAllClients(...)
    end
end

-- Fire an event to a specific client
function Remotes.FireClient(eventName, player, ...)
    local event = Remotes.GetEvent(eventName)
    if event then
        event:FireClient(player, ...)
    end
end

-- Fire an event to the server (client only)
function Remotes.FireServer(eventName, ...)
    local event = Remotes.GetEvent(eventName)
    if event then
        event:FireServer(...)
    else
        warn("[Remotes] FireServer failed - event not found:", eventName)
    end
end

-- Connect to an event
function Remotes.OnEvent(eventName, callback)
    local event = Remotes.GetEvent(eventName)
    if event then
        if RunService:IsServer() then
            return event.OnServerEvent:Connect(callback)
        else
            return event.OnClientEvent:Connect(callback)
        end
    end
    return nil
end

-- Invoke a remote function
function Remotes.Invoke(funcName, ...)
    local func = Remotes.GetFunction(funcName)
    if func then
        if RunService:IsServer() then
            -- This is for invoking client from server
            local player = ...
            return func:InvokeClient(player, select(2, ...))
        else
            return func:InvokeServer(...)
        end
    end
    return nil
end

-- Set callback for a remote function
function Remotes.OnInvoke(funcName, callback)
    local func = Remotes.GetFunction(funcName)
    if func then
        if RunService:IsServer() then
            func.OnServerInvoke = callback
        else
            func.OnClientInvoke = callback
        end
    end
end

return Remotes
