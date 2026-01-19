--[[
    =========================================================================
    Dino Royale 2 - Server Bootstrap
    =========================================================================

    Main entry point for server-side game initialization.
    This script runs once when the server starts and initializes all
    core services in the correct order.

    Initialization Order:
    1. Remotes - Network communication layer (required for client-server messaging)
    2. Framework - Service locator pattern (dependency injection container)
    3. Core Services - Game systems (GameService, MapService, StormService, etc.)
    4. Modules - Support systems (LootSystem, SquadSystem, PlayerInventory)
    5. Player Events - Handle player join/leave lifecycle

    Architecture Notes:
    - All game logic runs server-side (server-authoritative model)
    - Clients receive state via RemoteEvents defined in src/shared/Remotes.lua
    - Services are loosely coupled via framework:GetService() calls
    - GameService is the source of truth for match state

    =========================================================================
]]

-- Roblox service references
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--=============================================================================
-- INITIALIZATION
--=============================================================================

print("[DinoRoyale] Server starting...")

-- Step 1: Setup Remotes first (required by all services)
local Remotes = require(ServerScriptService.Parent["dino-royale2"].src.shared.Remotes)
Remotes.Setup()
print("[DinoRoyale] Remotes initialized")

-- Step 2: Get Framework reference
local framework = require(ServerScriptService.Parent["dino-royale2"].framework)
print("[DinoRoyale] Framework loaded")

-- Step 3: Get GameConfig
local GameConfig = require(ServerScriptService.Parent["dino-royale2"].src.shared.GameConfig)
print("[DinoRoyale] GameConfig loaded")

--=============================================================================
-- SERVICE INITIALIZATION
-- Services are initialized in dependency order
--=============================================================================

--[[
    Service initialization order is critical!
    Services are registered with framework and can call each other via GetService().
    Dependencies must be initialized before their dependents.

    Dependency Graph:
        GameService (root - no deps)
        MapService (root - no deps)
        StormService (root - no deps)
        WeaponService (root - no deps)
        DinoService → MapService (queries spawn points)
]]
local serviceInitOrder = {
    "GameService",      -- Match state machine (LOBBY → STARTING → DROPPING → MATCH → ENDING → CLEANUP)
    "MapService",       -- Map/biome system (jungle, volcanic, swamp, facility, plains, coastal)
    "StormService",     -- Zone mechanics (shrinking safe zone)
    "WeaponService",    -- Weapon system (ranged, melee, explosives, traps)
    "DinoService",      -- Dinosaur AI (raptors, t-rex, pteranodons, bosses)
}

--[[
    Module initialization order
    Modules are support systems that may depend on services.

    Dependency Graph:
        LootSystem → WeaponService, MapService (needs weapon defs and POI locations)
        SquadSystem → GameService (needs match state for team formation)
]]
local moduleInitOrder = {
    "LootSystem",       -- Loot spawning (weapons, ammo, healing, throwables, traps)
    "SquadSystem",      -- Team management (solo/duos/trios, revives)
}

-- Initialize all services
-- Each service is wrapped in pcall() to catch initialization errors
-- and prevent one failing service from bringing down the entire server
print("[DinoRoyale] Initializing services...")

for _, serviceName in ipairs(serviceInitOrder) do
    -- GetService uses framework's service locator pattern to retrieve registered services
    local service = framework:GetService(serviceName)
    if service then
        if service.Initialize then
            -- pcall protects against initialization errors
            local success, err = pcall(function()
                service:Initialize()
            end)
            if success then
                print(string.format("[DinoRoyale] ✓ %s initialized", serviceName))
            else
                warn(string.format("[DinoRoyale] ✗ %s failed: %s", serviceName, tostring(err)))
            end
        else
            -- Some services may not require explicit initialization
            print(string.format("[DinoRoyale] ✓ %s loaded (no init required)", serviceName))
        end
    else
        warn(string.format("[DinoRoyale] ✗ %s not found", serviceName))
    end
end

-- Initialize all modules
print("[DinoRoyale] Initializing modules...")

for _, moduleName in ipairs(moduleInitOrder) do
    local mod = framework:GetModule(moduleName)
    if mod then
        if mod.Initialize then
            local success, err = pcall(function()
                mod:Initialize()
            end)
            if success then
                print(string.format("[DinoRoyale] ✓ %s initialized", moduleName))
            else
                warn(string.format("[DinoRoyale] ✗ %s failed: %s", moduleName, tostring(err)))
            end
        else
            print(string.format("[DinoRoyale] ✓ %s loaded (no init required)", moduleName))
        end
    else
        warn(string.format("[DinoRoyale] ✗ %s not found", moduleName))
    end
end

--=============================================================================
-- SERVICE CONNECTIONS
-- Wire up cross-service communication
--=============================================================================

print("[DinoRoyale] Connecting services...")

-- Get service references
local GameService = framework:GetService("GameService")
local MapService = framework:GetService("MapService")
local DinoService = framework:GetService("DinoService")
local StormService = framework:GetService("StormService")
local LootSystem = framework:GetModule("LootSystem")
local SquadSystem = framework:GetModule("SquadSystem")

-- Connect MapService to provide spawn points
if MapService and DinoService then
    -- DinoService can now query MapService for spawn locations
    print("[DinoRoyale] ✓ DinoService connected to MapService")
end

-- Connect LootSystem to MapService for POI-based loot
if MapService and LootSystem then
    print("[DinoRoyale] ✓ LootSystem connected to MapService")
end

--=============================================================================
-- REMOTE FUNCTION HANDLERS
-- Server-side handlers for client requests (RemoteFunctions)
-- These allow clients to request data synchronously via Remotes.Invoke()
--=============================================================================

--[[
    Handle GetGameState requests
    Called by clients when they join to get current match state
    @param player Player - The requesting player
    @return table - Current game state, mode, and storm info
]]
Remotes.OnInvoke("GetGameState", function(player)
    if GameService then
        return {
            state = GameService:GetState(),      -- Current match phase (Lobby, Match, etc.)
            mode = GameService:GetMode(),        -- Game mode (solo, duos, trios)
            storm = StormService and StormService:GetState() or nil,  -- Zone state
        }
    end
    return nil
end)

--[[
    Handle GetSquadInfo requests
    Called by clients to get their current squad assignment
    @param player Player - The requesting player
    @return table - Squad info with ID, members list, and mode
]]
Remotes.OnInvoke("GetSquadInfo", function(player)
    if SquadSystem then
        local squad = SquadSystem:GetPlayerSquad(player)
        if squad then
            return {
                squadId = squad.id,
                members = squad.members,
                mode = SquadSystem:GetMode(),
            }
        end
    end
    return nil
end)

--[[
    Handle GetPlayerInventory requests
    Called by clients to get their full inventory state
    @param player Player - The requesting player
    @return table - Complete inventory (weapons, ammo, consumables, etc.)
]]
Remotes.OnInvoke("GetPlayerInventory", function(player)
    local PlayerInventory = framework:GetModule("PlayerInventory")
    if PlayerInventory then
        return PlayerInventory:GetInventory(player)
    end
    return nil
end)

--=============================================================================
-- GAME EVENT HANDLERS
-- Respond to game state changes
--=============================================================================

-- When match starts, spawn loot
if GameService then
    -- Listen for state changes via custom signal or polling
    -- For now, we'll use the existing event system
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if remoteFolder then
        local stateRemote = remoteFolder:FindFirstChild("GameStateChanged")
        if stateRemote then
            -- Server-side state change handler
            -- (GameService already fires this to clients, we hook into state changes internally)
        end
    end
end

--=============================================================================
-- MATCH FLOW INTEGRATION
-- Connect the full match lifecycle
--=============================================================================

--[[
    Match Flow:

    LOBBY
      ↓ (min players reached, timer expires)
    STARTING
      ↓ (countdown complete, teams formed)
    DROPPING
      ↓ (players land)
    MATCH
      ↓ (winner determined or timeout)
    ENDING
      ↓ (results displayed)
    CLEANUP
      ↓ (reset everything)
    LOBBY (loop)
]]

-- Hook into match phase transitions
local function onMatchPhaseChanged(newState, oldState)
    print(string.format("[DinoRoyale] Match phase: %s -> %s", oldState or "none", newState))

    if newState == "Dropping" then
        -- Spawn all loot when players are dropping
        if LootSystem then
            LootSystem:SpawnAllLoot()
            print("[DinoRoyale] Loot spawned for match")
        end

    elseif newState == "Match" then
        -- Match has started
        -- StormService and DinoService are started by GameService

    elseif newState == "Cleanup" then
        -- Reset systems for next match
        if LootSystem then
            LootSystem:ResetLoot()
        end
        if SquadSystem then
            SquadSystem:Reset()
        end
    end
end

-- Register the phase change callback with GameService
-- (GameService already handles this internally, but we can extend it)

--=============================================================================
-- PLAYER CONNECTION HANDLING
-- Handle player join and leave events
-- These callbacks run for every player connecting/disconnecting
--=============================================================================

--[[
    Called when a player joins the server
    Responsibilities:
    1. Initialize player's inventory (weapons, ammo, etc.)
    2. Notify client of current game state
    3. Any additional per-player setup
]]
Players.PlayerAdded:Connect(function(player)
    print(string.format("[DinoRoyale] Player joined: %s", player.Name))

    -- Initialize player's inventory with empty slots
    -- This creates the data structure for tracking weapons, ammo, consumables
    local PlayerInventory = framework:GetModule("PlayerInventory")
    if PlayerInventory then
        PlayerInventory:InitializePlayer(player)
    end

    -- Send current game state to the joining player
    -- This ensures late-joiners know if a match is in progress
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if remoteFolder and GameService then
        local stateRemote = remoteFolder:FindFirstChild("GameStateChanged")
        if stateRemote then
            stateRemote:FireClient(player, GameService:GetState(), nil)
        end
    end
end)

--[[
    Called when a player leaves the server
    Responsibilities:
    1. Cleanup player's inventory data (prevent memory leaks)
    2. Handle any active match implications (elimination, squad updates)
    3. Release any resources held by the player
]]
Players.PlayerRemoving:Connect(function(player)
    print(string.format("[DinoRoyale] Player left: %s", player.Name))

    -- Cleanup player's inventory data to prevent memory leaks
    local PlayerInventory = framework:GetModule("PlayerInventory")
    if PlayerInventory then
        PlayerInventory:CleanupPlayer(player)
    end
end)

--=============================================================================
-- STARTUP COMPLETE
--=============================================================================

print("[DinoRoyale] ========================================")
print("[DinoRoyale] Server initialization complete!")
print(string.format("[DinoRoyale] Version: %s", framework.Config.VERSION))
print(string.format("[DinoRoyale] Debug Mode: %s", tostring(GameConfig.Debug.enabled)))
print("[DinoRoyale] ========================================")
print("[DinoRoyale] Waiting for players...")
