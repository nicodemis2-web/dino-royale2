--[[
    ================================================================================
    NetworkUtils - Distance-Based Network Broadcast Utilities for Dino Royale 2
    ================================================================================

    This module provides utilities for efficient network communication:
    - Distance-based filtering for RemoteEvent broadcasts
    - Only sends events to players who can perceive them
    - Reduces network traffic and improves performance

    Why Distance Filtering:
    - Players don't need events from across the map
    - Reduces client-side processing of irrelevant events
    - Improves network bandwidth usage
    - Better scaling with large player counts

    Usage:
        local NetworkUtils = require(game.ReplicatedStorage.Shared.lib.NetworkUtils)

        -- Fire to nearby players only
        NetworkUtils.FireNearby("EventName", position, 200, data)

        -- Fire to players in a radius, with falloff data
        NetworkUtils.FireWithinRadius("EventName", position, 300, data, function(player, distance)
            return { ...data, volume = 1 - (distance / 300) }
        end)

    Author: Dino Royale 2 Development Team
    Version: 1.0.0
    ================================================================================
]]

--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--==============================================================================
-- TYPE DEFINITIONS
--==============================================================================

-- Nearby player info
export type NearbyPlayerInfo = {
    player: Player,
    distance: number,
}

-- Falloff modifier function type
export type FalloffModifierFunc = (player: Player, distance: number) -> any

--==============================================================================
-- MODULE
--==============================================================================

local NetworkUtils = {}

--==============================================================================
-- CONSTANTS
--==============================================================================
local DEFAULT_BROADCAST_RADIUS: number = 300   -- Studs for most events
local MAX_BROADCAST_RADIUS: number = 1000      -- Never broadcast beyond this
local GLOBAL_EVENTS: {string} = {              -- Events that should always be global
    "GameStateChanged",
    "MatchStarting",
    "VictoryDeclared",
    "UpdatePlayersAlive",
    "LobbyStatusUpdate",
    "CountdownUpdate",
    "StormPhaseChanged",
    "StormWarning",
    "BossSpawned",
    "BossDied",
    "BossPhaseChanged",
}

-- Check if an event should be global
local function isGlobalEvent(eventName: string): boolean
    for _, name in ipairs(GLOBAL_EVENTS) do
        if name == eventName then
            return true
        end
    end
    return false
end

--==============================================================================
-- UTILITY FUNCTIONS
--==============================================================================

--[[
    Get a player's position
    @param player Player
    @return Vector3|nil
]]
local function getPlayerPosition(player: Player): Vector3?
    local character = player.Character
    if not character then return nil end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end

    return rootPart.Position
end

--[[
    Get the Remotes folder
    @return Folder|nil
]]
local function getRemotesFolder()
    return ReplicatedStorage:FindFirstChild("Remotes")
end

--==============================================================================
-- PUBLIC API
--==============================================================================

--[[
    Fire a remote event to all players within a radius
    @param eventName string - Name of the RemoteEvent
    @param position Vector3 - Center position for distance check
    @param radius number - Maximum distance in studs
    @param data any - Data to send
    @param excludePlayer Player|nil - Optional player to exclude
]]
function NetworkUtils.FireNearby(eventName, position, radius, data, excludePlayer)
    -- Global events bypass filtering
    if isGlobalEvent(eventName) then
        NetworkUtils.FireAll(eventName, data)
        return
    end

    local remotes = getRemotesFolder()
    if not remotes then return end

    local remote = remotes:FindFirstChild(eventName)
    if not remote then return end

    radius = math.min(radius or DEFAULT_BROADCAST_RADIUS, MAX_BROADCAST_RADIUS)

    for _, player in ipairs(Players:GetPlayers()) do
        if player == excludePlayer then continue end

        local playerPos = getPlayerPosition(player)
        if playerPos then
            local distance = (playerPos - position).Magnitude
            if distance <= radius then
                remote:FireClient(player, data)
            end
        else
            -- No position = player is likely loading, send anyway
            remote:FireClient(player, data)
        end
    end
end

--[[
    Fire a remote event with distance-based data modification
    Useful for volume falloff, visual intensity, etc.
    @param eventName string - Name of the RemoteEvent
    @param position Vector3 - Center position
    @param radius number - Maximum distance
    @param baseData any - Base data to send
    @param modifyFunc function(player, distance) -> modifiedData
]]
function NetworkUtils.FireWithFalloff(eventName, position, radius, baseData, modifyFunc)
    local remotes = getRemotesFolder()
    if not remotes then return end

    local remote = remotes:FindFirstChild(eventName)
    if not remote then return end

    radius = math.min(radius or DEFAULT_BROADCAST_RADIUS, MAX_BROADCAST_RADIUS)

    for _, player in ipairs(Players:GetPlayers()) do
        local playerPos = getPlayerPosition(player)
        if playerPos then
            local distance = (playerPos - position).Magnitude
            if distance <= radius then
                local modifiedData = modifyFunc(player, distance)
                remote:FireClient(player, modifiedData)
            end
        end
    end
end

--[[
    Fire a remote event to all players (no filtering)
    @param eventName string - Name of the RemoteEvent
    @param data any - Data to send
]]
function NetworkUtils.FireAll(eventName, data)
    local remotes = getRemotesFolder()
    if not remotes then return end

    local remote = remotes:FindFirstChild(eventName)
    if not remote then return end

    remote:FireAllClients(data)
end

--[[
    Fire a remote event to a specific player
    @param eventName string - Name of the RemoteEvent
    @param player Player - Target player
    @param data any - Data to send
]]
function NetworkUtils.FireClient(eventName, player, data)
    local remotes = getRemotesFolder()
    if not remotes then return end

    local remote = remotes:FindFirstChild(eventName)
    if not remote then return end

    remote:FireClient(player, data)
end

--[[
    Fire a remote event to all players in a list
    @param eventName string - Name of the RemoteEvent
    @param players table - Array of players
    @param data any - Data to send
]]
function NetworkUtils.FirePlayers(eventName, players, data)
    local remotes = getRemotesFolder()
    if not remotes then return end

    local remote = remotes:FindFirstChild(eventName)
    if not remote then return end

    for _, player in ipairs(players) do
        remote:FireClient(player, data)
    end
end

--[[
    Get players within a radius of a position
    @param position Vector3 - Center position
    @param radius number - Maximum distance
    @return table - Array of players within radius
]]
function NetworkUtils.GetPlayersInRadius(position, radius)
    local nearbyPlayers = {}

    for _, player in ipairs(Players:GetPlayers()) do
        local playerPos = getPlayerPosition(player)
        if playerPos then
            local distance = (playerPos - position).Magnitude
            if distance <= radius then
                table.insert(nearbyPlayers, {
                    player = player,
                    distance = distance,
                })
            end
        end
    end

    return nearbyPlayers
end

--[[
    Broadcast configuration - recommended radii for different event types
]]
NetworkUtils.RecommendedRadii = {
    -- Combat events (need quick response, medium range)
    WeaponFire = 200,
    BulletHit = 150,
    MeleeAttack = 100,
    Explosion = 300,

    -- Dinosaur events (can be heard from far)
    DinoSpawned = 400,
    DinoAttack = 250,
    DinoDamaged = 200,
    DinoDied = 300,
    DinoAbility = 350,
    PackAlert = 400,

    -- Loot events (local interest only)
    LootSpawned = 150,
    LootPickedUp = 100,
    ChestOpened = 100,

    -- Environment events (depends on intensity)
    Eruption = 500,
    MeteorImpact = 400,
    SupplyDrop = 600,

    -- Trap events (local)
    TrapPlaced = 100,
    TrapTriggered = 150,
}

return NetworkUtils
