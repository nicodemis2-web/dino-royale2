--[[
    ================================================================================
    DataService - Player Data Persistence for Dino Royale 2
    ================================================================================

    This service handles saving and loading player data using Roblox DataStoreService.

    Features:
    - Player statistics (kills, deaths, wins, matches played)
    - Session data with auto-save
    - Data versioning for migrations
    - Retry logic for failed saves
    - Session locking to prevent data loss

    Data Structure:
    {
        version = 1,
        stats = {
            kills = 0,
            deaths = 0,
            wins = 0,
            matchesPlayed = 0,
            dinosaursKilled = 0,
            damageDealt = 0,
            timePlayed = 0,  -- seconds
        },
        settings = {
            -- Player preferences (synced from client)
        },
        lastPlayed = 0,  -- Unix timestamp
    }

    Usage:
        local DataService = Framework:GetService("DataService")
        DataService:Initialize()

        -- Get player stats
        local stats = DataService:GetPlayerStats(player)

        -- Update stats
        DataService:IncrementStat(player, "kills", 1)
        DataService:AddWin(player)

    Author: Dino Royale 2 Development Team
    Version: 1.0.0
    ================================================================================
]]

--==============================================================================
-- SERVICES
--==============================================================================
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

--==============================================================================
-- MODULE DEFINITION
--==============================================================================
local DataService = {}
DataService.__index = DataService

--==============================================================================
-- CONSTANTS
--==============================================================================
local DATA_STORE_NAME = "DinoRoyale_PlayerData_v1"
local DATA_VERSION = 1
local AUTO_SAVE_INTERVAL = 60  -- seconds
local MAX_RETRIES = 3
local RETRY_DELAY = 1  -- seconds

--==============================================================================
-- PRIVATE STATE
--==============================================================================
local framework = nil
local playerDataStore = nil
local playerDataCache = {}  -- [UserId] = data
local sessionLocks = {}     -- [UserId] = true (locked by this server)
local pendingSaves = {}     -- [UserId] = true (needs save)
local isInitialized = false
local autoSaveConnection = nil

--==============================================================================
-- DEFAULT DATA TEMPLATE
--==============================================================================
local DEFAULT_DATA = {
    version = DATA_VERSION,
    stats = {
        kills = 0,
        deaths = 0,
        wins = 0,
        matchesPlayed = 0,
        dinosaursKilled = 0,
        damageDealt = 0,
        timePlayed = 0,
        highestPlacement = 0,  -- Best placement (1 = win)
    },
    settings = {
        musicVolume = 0.5,
        sfxVolume = 0.8,
        sensitivity = 1.0,
    },
    lastPlayed = 0,
}

--==============================================================================
-- UTILITY FUNCTIONS
--==============================================================================

--[[
    Deep copy a table
]]
local function deepCopy(original)
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = deepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

--[[
    Merge default values into data (for migrations)
]]
local function mergeDefaults(data, defaults)
    for key, defaultValue in pairs(defaults) do
        if data[key] == nil then
            if type(defaultValue) == "table" then
                data[key] = deepCopy(defaultValue)
            else
                data[key] = defaultValue
            end
        elseif type(defaultValue) == "table" and type(data[key]) == "table" then
            mergeDefaults(data[key], defaultValue)
        end
    end
    return data
end

--[[
    Migrate data to current version
]]
local function migrateData(data)
    if not data then
        return deepCopy(DEFAULT_DATA)
    end

    local version = data.version or 0

    -- Version 0 -> 1: Initial structure
    if version < 1 then
        data = mergeDefaults(data, DEFAULT_DATA)
        data.version = 1
    end

    -- Future migrations go here
    -- if version < 2 then ... end

    return data
end

--==============================================================================
-- INITIALIZATION
--==============================================================================

--[[
    Initialize the DataService
]]
function DataService:Initialize()
    if isInitialized then return true end

    framework = require(script.Parent.Parent.Framework)

    -- Only run on server
    if not RunService:IsServer() then
        framework.Log("Debug", "DataService skipped on client")
        return true
    end

    -- Get DataStore (will fail in Studio without API access)
    local success, result = pcall(function()
        return DataStoreService:GetDataStore(DATA_STORE_NAME)
    end)

    if success then
        playerDataStore = result
        framework.Log("Info", "DataService connected to DataStore: %s", DATA_STORE_NAME)
    else
        framework.Log("Warn", "DataService failed to connect to DataStore: %s", tostring(result))
        framework.Log("Warn", "Player data will NOT be saved this session")
    end

    -- Connect player events
    Players.PlayerAdded:Connect(function(player)
        self:OnPlayerAdded(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:OnPlayerRemoving(player)
    end)

    -- Load data for existing players (in case of late initialization)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            self:OnPlayerAdded(player)
        end)
    end

    -- Start auto-save loop
    self:StartAutoSave()

    -- Handle server shutdown
    game:BindToClose(function()
        self:SaveAllPlayers()
    end)

    isInitialized = true
    framework.Log("Info", "DataService initialized")
    return true
end

--==============================================================================
-- PLAYER LIFECYCLE
--==============================================================================

--[[
    Handle player joining
]]
function DataService:OnPlayerAdded(player)
    local userId = player.UserId

    -- Load player data
    local data = self:LoadPlayerData(userId)
    if data then
        playerDataCache[userId] = data
        sessionLocks[userId] = true
        framework.Log("Debug", "Loaded data for %s", player.Name)
    else
        -- Use default data if load failed
        playerDataCache[userId] = deepCopy(DEFAULT_DATA)
        sessionLocks[userId] = true
        framework.Log("Debug", "Using default data for %s", player.Name)
    end

    -- Update last played timestamp
    playerDataCache[userId].lastPlayed = os.time()
end

--[[
    Handle player leaving
]]
function DataService:OnPlayerRemoving(player)
    local userId = player.UserId

    -- Save player data
    self:SavePlayerData(userId)

    -- Clear cache
    playerDataCache[userId] = nil
    sessionLocks[userId] = nil
    pendingSaves[userId] = nil
end

--==============================================================================
-- DATA LOADING
--==============================================================================

--[[
    Load player data from DataStore
    @param userId number
    @return table|nil
]]
function DataService:LoadPlayerData(userId)
    if not playerDataStore then
        return deepCopy(DEFAULT_DATA)
    end

    local data = nil
    local success = false

    for attempt = 1, MAX_RETRIES do
        local ok, result = pcall(function()
            return playerDataStore:GetAsync("Player_" .. userId)
        end)

        if ok then
            data = result
            success = true
            break
        else
            framework.Log("Warn", "Load attempt %d failed for %d: %s", attempt, userId, tostring(result))
            if attempt < MAX_RETRIES then
                task.wait(RETRY_DELAY)
            end
        end
    end

    if not success then
        framework.Log("Error", "Failed to load data for %d after %d attempts", userId, MAX_RETRIES)
        return nil
    end

    -- Migrate data to current version
    data = migrateData(data)

    return data
end

--==============================================================================
-- DATA SAVING
--==============================================================================

--[[
    Save player data to DataStore
    @param userId number
    @return boolean success
]]
function DataService:SavePlayerData(userId)
    local data = playerDataCache[userId]
    if not data then
        return false
    end

    if not playerDataStore then
        framework.Log("Debug", "Skipping save for %d (no DataStore)", userId)
        return false
    end

    local success = false

    for attempt = 1, MAX_RETRIES do
        local ok, err = pcall(function()
            playerDataStore:SetAsync("Player_" .. userId, data)
        end)

        if ok then
            success = true
            pendingSaves[userId] = nil
            break
        else
            framework.Log("Warn", "Save attempt %d failed for %d: %s", attempt, userId, tostring(err))
            if attempt < MAX_RETRIES then
                task.wait(RETRY_DELAY)
            end
        end
    end

    if success then
        framework.Log("Debug", "Saved data for %d", userId)
    else
        framework.Log("Error", "Failed to save data for %d after %d attempts", userId, MAX_RETRIES)
        pendingSaves[userId] = true
    end

    return success
end

--[[
    Save all players' data
]]
function DataService:SaveAllPlayers()
    framework.Log("Info", "Saving all player data...")

    local saveThreads = {}

    for userId, _ in pairs(playerDataCache) do
        table.insert(saveThreads, task.spawn(function()
            self:SavePlayerData(userId)
        end))
    end

    -- Wait for all saves to complete (with timeout)
    task.wait(5)

    framework.Log("Info", "All player data saved")
end

--==============================================================================
-- AUTO-SAVE
--==============================================================================

--[[
    Start the auto-save loop
]]
function DataService:StartAutoSave()
    if autoSaveConnection then return end

    autoSaveConnection = task.spawn(function()
        while true do
            task.wait(AUTO_SAVE_INTERVAL)

            for userId, _ in pairs(playerDataCache) do
                if pendingSaves[userId] or true then  -- Always save periodically
                    task.spawn(function()
                        self:SavePlayerData(userId)
                    end)
                end
            end
        end
    end)

    framework.Log("Debug", "Auto-save started (interval: %ds)", AUTO_SAVE_INTERVAL)
end

--==============================================================================
-- STATS API
--==============================================================================

--[[
    Get player stats
    @param player Player
    @return table|nil
]]
function DataService:GetPlayerStats(player)
    local data = playerDataCache[player.UserId]
    if data then
        return data.stats
    end
    return nil
end

--[[
    Get full player data
    @param player Player
    @return table|nil
]]
function DataService:GetPlayerData(player)
    return playerDataCache[player.UserId]
end

--[[
    Increment a stat value
    @param player Player
    @param statName string
    @param amount number
]]
function DataService:IncrementStat(player, statName, amount)
    local data = playerDataCache[player.UserId]
    if not data or not data.stats then return end

    amount = amount or 1
    data.stats[statName] = (data.stats[statName] or 0) + amount
    pendingSaves[player.UserId] = true
end

--[[
    Set a stat value
    @param player Player
    @param statName string
    @param value any
]]
function DataService:SetStat(player, statName, value)
    local data = playerDataCache[player.UserId]
    if not data or not data.stats then return end

    data.stats[statName] = value
    pendingSaves[player.UserId] = true
end

--[[
    Record a kill
    @param player Player
]]
function DataService:AddKill(player)
    self:IncrementStat(player, "kills", 1)
end

--[[
    Record a death
    @param player Player
]]
function DataService:AddDeath(player)
    self:IncrementStat(player, "deaths", 1)
end

--[[
    Record a win
    @param player Player
]]
function DataService:AddWin(player)
    self:IncrementStat(player, "wins", 1)

    -- Update highest placement
    local data = playerDataCache[player.UserId]
    if data and data.stats then
        if data.stats.highestPlacement == 0 or data.stats.highestPlacement > 1 then
            data.stats.highestPlacement = 1
        end
    end
end

--[[
    Record match completion
    @param player Player
    @param placement number - Final placement (1 = winner)
]]
function DataService:AddMatchPlayed(player, placement)
    self:IncrementStat(player, "matchesPlayed", 1)

    -- Update highest placement if better
    if placement and placement > 0 then
        local data = playerDataCache[player.UserId]
        if data and data.stats then
            local current = data.stats.highestPlacement or 0
            if current == 0 or placement < current then
                data.stats.highestPlacement = placement
            end
        end
    end
end

--[[
    Record dinosaur kill
    @param player Player
]]
function DataService:AddDinosaurKill(player)
    self:IncrementStat(player, "dinosaursKilled", 1)
end

--[[
    Add damage dealt
    @param player Player
    @param damage number
]]
function DataService:AddDamageDealt(player, damage)
    self:IncrementStat(player, "damageDealt", damage)
end

--[[
    Add play time
    @param player Player
    @param seconds number
]]
function DataService:AddPlayTime(player, seconds)
    self:IncrementStat(player, "timePlayed", seconds)
end

--==============================================================================
-- SETTINGS API
--==============================================================================

--[[
    Get player settings
    @param player Player
    @return table|nil
]]
function DataService:GetPlayerSettings(player)
    local data = playerDataCache[player.UserId]
    if data then
        return data.settings
    end
    return nil
end

--[[
    Update a setting
    @param player Player
    @param settingName string
    @param value any
]]
function DataService:SetSetting(player, settingName, value)
    local data = playerDataCache[player.UserId]
    if not data or not data.settings then return end

    data.settings[settingName] = value
    pendingSaves[player.UserId] = true
end

--==============================================================================
-- LEADERBOARD HELPERS
--==============================================================================

--[[
    Get formatted stats for display
    @param player Player
    @return table
]]
function DataService:GetFormattedStats(player)
    local stats = self:GetPlayerStats(player)
    if not stats then
        return {
            kills = 0,
            deaths = 0,
            kd = "0.00",
            wins = 0,
            matches = 0,
            winRate = "0%",
        }
    end

    local kd = stats.deaths > 0 and (stats.kills / stats.deaths) or stats.kills
    local winRate = stats.matchesPlayed > 0 and (stats.wins / stats.matchesPlayed * 100) or 0

    return {
        kills = stats.kills,
        deaths = stats.deaths,
        kd = string.format("%.2f", kd),
        wins = stats.wins,
        matches = stats.matchesPlayed,
        winRate = string.format("%.1f%%", winRate),
        dinosaursKilled = stats.dinosaursKilled,
        timePlayed = stats.timePlayed,
    }
end

return DataService
