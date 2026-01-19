--[[
    GameService - Core game loop and state machine
    Handles: Lobby, Match Start, Match End, Victory Conditions

    States:
        LOBBY -> STARTING -> DROPPING -> MATCH -> ENDING -> CLEANUP -> LOBBY
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameService = {}
GameService.__index = GameService

-- Game States
GameService.States = {
    LOBBY = "Lobby",
    STARTING = "Starting",
    DROPPING = "Dropping",
    MATCH = "Match",
    ENDING = "Ending",
    CLEANUP = "Cleanup",
}

-- Private state
local currentState = GameService.States.LOBBY
local currentMode = "solo"
local matchStartTime = 0
local playersAlive = {}
local teams = {}
local stormPhase = 0
local gameConfig = nil
local framework = nil

-- Events (will be set up on init)
local events = {
    StateChanged = nil,      -- Fires when game state changes
    PlayerEliminated = nil,  -- Fires when player is eliminated
    TeamEliminated = nil,    -- Fires when a team is eliminated
    MatchEnded = nil,        -- Fires when match ends
    VictoryDeclared = nil,   -- Fires when winner is determined
}

--[[
    Initialize the GameService
]]
function GameService:Initialize()
    -- Get framework reference
    framework = require(script.Parent.Parent.framework)
    gameConfig = require(script.Parent.Parent.src.shared.GameConfig)

    -- Create remote events
    self:SetupRemotes()

    -- Connect player events
    Players.PlayerAdded:Connect(function(player)
        self:OnPlayerJoined(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:OnPlayerLeft(player)
    end)

    -- Start the game loop
    self:StartGameLoop()

    framework.Log("Info", "GameService initialized")
    return true
end

--[[
    Setup remote events for client-server communication
]]
function GameService:SetupRemotes()
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = "Remotes"
        remoteFolder.Parent = ReplicatedStorage
    end

    -- Create game-related remotes
    local gameRemotes = {
        "GameStateChanged",
        "MatchStarting",
        "PlayerEliminated",
        "VictoryDeclared",
        "UpdatePlayersAlive",
        "UpdateStormPhase",
        "RequestGameMode",
    }

    for _, remoteName in ipairs(gameRemotes) do
        if not remoteFolder:FindFirstChild(remoteName) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = remoteName
            remote.Parent = remoteFolder
        end
    end

    -- Handle mode selection
    remoteFolder.RequestGameMode.OnServerEvent:Connect(function(player, mode)
        if gameConfig.Modes[mode] then
            -- Only allow mode change in lobby
            if currentState == GameService.States.LOBBY then
                currentMode = mode
                framework.Log("Info", "Game mode changed to: %s", mode)
            end
        end
    end)
end

--[[
    Main game loop
]]
function GameService:StartGameLoop()
    task.spawn(function()
        while true do
            if currentState == GameService.States.LOBBY then
                self:LobbyPhase()
            elseif currentState == GameService.States.STARTING then
                self:StartingPhase()
            elseif currentState == GameService.States.DROPPING then
                self:DroppingPhase()
            elseif currentState == GameService.States.MATCH then
                self:MatchPhase()
            elseif currentState == GameService.States.ENDING then
                self:EndingPhase()
            elseif currentState == GameService.States.CLEANUP then
                self:CleanupPhase()
            end

            task.wait(0.1)
        end
    end)
end

--[[
    Lobby Phase - Wait for players
]]
function GameService:LobbyPhase()
    local playerCount = #Players:GetPlayers()
    local minPlayers = gameConfig.Match.minPlayersToStart
    local waitTime = gameConfig.Match.lobbyWaitTime
    local timer = waitTime

    framework.Log("Info", "Lobby phase started, waiting for %d players", minPlayers)

    while currentState == GameService.States.LOBBY do
        playerCount = #Players:GetPlayers()

        if playerCount >= minPlayers then
            timer = timer - 0.1
            if timer <= 0 then
                self:SetState(GameService.States.STARTING)
                return
            end
        else
            timer = waitTime -- Reset timer if not enough players
        end

        -- Broadcast lobby status to clients
        self:BroadcastLobbyStatus(playerCount, minPlayers, timer)

        task.wait(0.1)
    end
end

--[[
    Starting Phase - Countdown and team formation
]]
function GameService:StartingPhase()
    framework.Log("Info", "Match starting in 5 seconds...")

    -- Form teams based on mode
    self:FormTeams()

    -- Countdown
    for i = 5, 1, -1 do
        self:BroadcastCountdown(i)
        task.wait(1)
    end

    -- Initialize alive players
    playersAlive = {}
    for _, player in ipairs(Players:GetPlayers()) do
        playersAlive[player.UserId] = true
    end

    self:SetState(GameService.States.DROPPING)
end

--[[
    Dropping Phase - Players spawn/drop into map
]]
function GameService:DroppingPhase()
    framework.Log("Info", "Dropping players into map...")

    -- Teleport players to drop positions
    local spawnPositions = self:GetDropPositions()

    for i, player in ipairs(Players:GetPlayers()) do
        local spawnPos = spawnPositions[((i - 1) % #spawnPositions) + 1]
        self:SpawnPlayer(player, spawnPos)
    end

    -- Wait for all players to land
    task.wait(3)

    matchStartTime = tick()
    self:SetState(GameService.States.MATCH)
end

--[[
    Match Phase - Main gameplay
]]
function GameService:MatchPhase()
    framework.Log("Info", "Match started!")

    -- Start storm service
    local stormService = framework:GetService("StormService")
    if stormService then
        stormService:StartStorm()
    end

    -- Start dinosaur service
    local dinoService = framework:GetService("DinoService")
    if dinoService then
        dinoService:StartSpawning()
    end

    -- Monitor match progress
    while currentState == GameService.States.MATCH do
        local aliveCounts = self:GetAliveCount()

        -- Check victory conditions
        local winner = self:CheckVictoryConditions(aliveCounts)
        if winner then
            self:DeclareVictory(winner)
            self:SetState(GameService.States.ENDING)
            return
        end

        -- Check match timeout
        local matchDuration = tick() - matchStartTime
        if matchDuration >= gameConfig.Match.matchMaxDuration then
            framework.Log("Info", "Match timed out!")
            self:SetState(GameService.States.ENDING)
            return
        end

        -- Broadcast alive count
        self:BroadcastAliveCount(aliveCounts)

        task.wait(0.5)
    end
end

--[[
    Ending Phase - Show results
]]
function GameService:EndingPhase()
    framework.Log("Info", "Match ending...")

    -- Stop storm
    local stormService = framework:GetService("StormService")
    if stormService then
        stormService:StopStorm()
    end

    -- Stop dinosaurs
    local dinoService = framework:GetService("DinoService")
    if dinoService then
        dinoService:StopSpawning()
    end

    -- Show results for a few seconds
    task.wait(10)

    self:SetState(GameService.States.CLEANUP)
end

--[[
    Cleanup Phase - Reset for next match
]]
function GameService:CleanupPhase()
    framework.Log("Info", "Cleaning up match...")

    -- Clear dinosaurs
    local dinoService = framework:GetService("DinoService")
    if dinoService then
        dinoService:DespawnAll()
    end

    -- Reset loot
    local lootSystem = framework:GetModule("LootSystem")
    if lootSystem then
        lootSystem:ResetLoot()
    end

    -- Teleport all players to lobby
    for _, player in ipairs(Players:GetPlayers()) do
        self:TeleportToLobby(player)
    end

    -- Reset state
    playersAlive = {}
    teams = {}
    stormPhase = 0
    matchStartTime = 0

    task.wait(gameConfig.Match.intermissionTime)

    self:SetState(GameService.States.LOBBY)
end

--[[
    Set game state
]]
function GameService:SetState(newState)
    local oldState = currentState
    currentState = newState

    framework.Log("Info", "State changed: %s -> %s", oldState, newState)

    -- Notify clients
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.GameStateChanged:FireAllClients(newState, oldState)
    end
end

--[[
    Get current state
]]
function GameService:GetState()
    return currentState
end

--[[
    Get current game mode
]]
function GameService:GetMode()
    return currentMode
end

--[[
    Form teams based on current mode
]]
function GameService:FormTeams()
    teams = {}
    local modeConfig = gameConfig.Modes[currentMode]
    local players = Players:GetPlayers()

    if modeConfig.teamSize == 1 then
        -- Solo - each player is their own team
        for _, player in ipairs(players) do
            teams[player.UserId] = {player.UserId}
        end
    else
        -- Duos/Trios - group players
        local teamSize = modeConfig.teamSize
        local teamIndex = 1

        for i, player in ipairs(players) do
            local teamKey = "team_" .. teamIndex

            if not teams[teamKey] then
                teams[teamKey] = {}
            end

            table.insert(teams[teamKey], player.UserId)

            if #teams[teamKey] >= teamSize then
                teamIndex = teamIndex + 1
            end
        end
    end

    framework.Log("Info", "Formed %d teams for mode: %s", self:CountTeams(), currentMode)
end

--[[
    Count active teams
]]
function GameService:CountTeams()
    local count = 0
    for _ in pairs(teams) do
        count = count + 1
    end
    return count
end

--[[
    Handle player elimination
]]
function GameService:EliminatePlayer(player, killer)
    if not playersAlive[player.UserId] then
        return -- Already eliminated
    end

    playersAlive[player.UserId] = false

    framework.Log("Info", "Player eliminated: %s", player.Name)

    -- Notify clients
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.PlayerEliminated:FireAllClients(player.UserId, killer and killer.UserId or nil)
    end

    -- Check if team is eliminated (for duos/trios)
    if currentMode ~= "solo" then
        self:CheckTeamElimination(player.UserId)
    end
end

--[[
    Check if a player's team is eliminated
]]
function GameService:CheckTeamElimination(userId)
    for teamKey, members in pairs(teams) do
        for _, memberId in ipairs(members) do
            if memberId == userId then
                -- Check if any team members are still alive
                local teamAlive = false
                for _, member in ipairs(members) do
                    if playersAlive[member] then
                        teamAlive = true
                        break
                    end
                end

                if not teamAlive then
                    framework.Log("Info", "Team eliminated: %s", teamKey)
                end
                return
            end
        end
    end
end

--[[
    Get alive counts
]]
function GameService:GetAliveCount()
    local players = 0
    local teamsAlive = 0

    for userId, alive in pairs(playersAlive) do
        if alive then
            players = players + 1
        end
    end

    -- Count teams with alive members
    local teamsChecked = {}
    for teamKey, members in pairs(teams) do
        for _, memberId in ipairs(members) do
            if playersAlive[memberId] and not teamsChecked[teamKey] then
                teamsAlive = teamsAlive + 1
                teamsChecked[teamKey] = true
                break
            end
        end
    end

    return {
        players = players,
        teams = teamsAlive,
    }
end

--[[
    Check victory conditions
]]
function GameService:CheckVictoryConditions(aliveCounts)
    local modeConfig = gameConfig.Modes[currentMode]

    if modeConfig.teamSize == 1 then
        -- Solo - last player wins
        if aliveCounts.players <= 1 then
            for userId, alive in pairs(playersAlive) do
                if alive then
                    return Players:GetPlayerByUserId(userId)
                end
            end
        end
    else
        -- Team modes - last team wins
        if aliveCounts.teams <= 1 then
            for teamKey, members in pairs(teams) do
                for _, memberId in ipairs(members) do
                    if playersAlive[memberId] then
                        return teamKey
                    end
                end
            end
        end
    end

    return nil
end

--[[
    Declare victory
]]
function GameService:DeclareVictory(winner)
    framework.Log("Info", "Victory declared!")

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.VictoryDeclared:FireAllClients(winner)
    end
end

--[[
    Get drop positions for spawning
    Uses MapService:GetPlayerSpawnPoints() for dynamic spawn locations
]]
function GameService:GetDropPositions()
    -- Try to get spawn points from MapService
    local mapService = framework:GetService("MapService")
    if mapService and mapService.GetPlayerSpawnPoints then
        local spawnPoints = mapService:GetPlayerSpawnPoints()
        if spawnPoints and #spawnPoints > 0 then
            -- Adjust Y position for drop height
            local positions = {}
            for _, pos in ipairs(spawnPoints) do
                table.insert(positions, Vector3.new(pos.X, gameConfig.Match.dropHeight, pos.Z))
            end
            return positions
        end
    end

    -- Fallback: Generate positions around map center
    local positions = {}
    local mapCenter = Vector3.new(0, 0, 0)
    local mapSize = 2048

    -- Try to get map center and size from MapService
    if mapService then
        if mapService.GetMapCenter then
            mapCenter = mapService:GetMapCenter()
        end
        if mapService.GetMapSize then
            mapSize = mapService:GetMapSize()
        end
    end

    local radius = mapSize * 0.15  -- 15% of map size for drop spread
    for i = 1, 20 do
        local angle = (i / 20) * math.pi * 2
        local x = math.cos(angle) * radius
        local z = math.sin(angle) * radius
        table.insert(positions, Vector3.new(mapCenter.X + x, gameConfig.Match.dropHeight, mapCenter.Z + z))
    end

    return positions
end

--[[
    Spawn a player at position
]]
function GameService:SpawnPlayer(player, position)
    local character = player.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        character.HumanoidRootPart.CFrame = CFrame.new(position)
    end
end

--[[
    Teleport player to lobby
    Uses MapService for lobby spawn location
]]
function GameService:TeleportToLobby(player)
    local lobbySpawn = Vector3.new(0, 10, 0)  -- Default fallback

    -- Try to get lobby spawn from MapService
    local mapService = framework:GetService("MapService")
    if mapService then
        -- First try GetLobbySpawn if available
        if mapService.GetLobbySpawn then
            local spawn = mapService:GetLobbySpawn()
            if spawn then
                lobbySpawn = spawn
            end
        -- Otherwise use map center with a small Y offset
        elseif mapService.GetMapCenter then
            local center = mapService:GetMapCenter()
            lobbySpawn = Vector3.new(center.X, 10, center.Z)
        end
    end

    self:SpawnPlayer(player, lobbySpawn)
end

--[[
    Broadcast lobby status to all clients
    @param current number - Current player count
    @param required number - Required player count to start
    @param timer number - Seconds until match starts
]]
function GameService:BroadcastLobbyStatus(current, required, timer)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local lobbyRemote = remotes:FindFirstChild("LobbyStatusUpdate")
        if lobbyRemote then
            lobbyRemote:FireAllClients({
                currentPlayers = current,
                requiredPlayers = required,
                timeRemaining = math.ceil(timer),
                canStart = current >= required,
            })
        end
    end
end

--[[
    Broadcast countdown to all clients
    @param seconds number - Seconds remaining in countdown
]]
function GameService:BroadcastCountdown(seconds)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local countdownRemote = remotes:FindFirstChild("CountdownUpdate")
        if countdownRemote then
            countdownRemote:FireAllClients(seconds)
        end

        -- Also fire match starting for final countdown
        local matchRemote = remotes:FindFirstChild("MatchStarting")
        if matchRemote then
            matchRemote:FireAllClients(seconds)
        end
    end
end

--[[
    Broadcast alive count
]]
function GameService:BroadcastAliveCount(counts)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.UpdatePlayersAlive:FireAllClients(counts.players, counts.teams)
    end
end

--[[
    Player joined handler
]]
function GameService:OnPlayerJoined(player)
    framework.Log("Info", "Player joined: %s", player.Name)

    -- If match in progress, make them spectator
    if currentState == GameService.States.MATCH then
        -- TODO: Enable spectator mode
    end
end

--[[
    Player left handler
]]
function GameService:OnPlayerLeft(player)
    framework.Log("Info", "Player left: %s", player.Name)

    -- Remove from alive list
    if playersAlive[player.UserId] then
        self:EliminatePlayer(player, nil)
    end
end

--[[
    Shutdown the service
]]
function GameService:Shutdown()
    framework.Log("Info", "GameService shutting down")
end

return GameService
