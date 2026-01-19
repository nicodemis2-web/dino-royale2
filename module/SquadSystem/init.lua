--[[
    SquadSystem - Team management for Solo, Duos, and Trios

    Features:
    - Team formation and management
    - Teammate tracking and UI
    - Revival system (for Duos/Trios)
    - Spectating teammates on death
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SquadSystem = {}
SquadSystem.__index = SquadSystem

-- Private state
local squads = {}           -- All squads
local playerSquadMap = {}   -- UserId -> squadId mapping
local currentMode = "solo"
local framework = nil
local gameConfig = nil

-- Squad states
SquadSystem.PlayerStates = {
    ALIVE = "Alive",
    DOWNED = "Downed",
    DEAD = "Dead",
    SPECTATING = "Spectating",
}

--[[
    Initialize the SquadSystem
]]
function SquadSystem:Initialize()
    framework = require(script.Parent.Parent.framework)
    gameConfig = require(script.Parent.Parent.src.shared.GameConfig)

    self:SetupRemotes()

    framework.Log("Info", "SquadSystem initialized")
    return self
end

--[[
    Setup remote events
]]
function SquadSystem:SetupRemotes()
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = "Remotes"
        remoteFolder.Parent = ReplicatedStorage
    end

    local squadRemotes = {
        "SquadUpdate",
        "TeammateStateChanged",
        "ReviveStarted",
        "ReviveCompleted",
        "ReviveCancelled",
        "SpectateTeammate",
    }

    for _, remoteName in ipairs(squadRemotes) do
        if not remoteFolder:FindFirstChild(remoteName) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = remoteName
            remote.Parent = remoteFolder
        end
    end

    -- Handle revive requests
    local reviveRemote = remoteFolder:FindFirstChild("ReviveStarted")
    if reviveRemote then
        reviveRemote.OnServerEvent:Connect(function(player, targetUserId)
            self:StartRevive(player, targetUserId)
        end)
    end

    -- Handle spectate requests
    local spectateRemote = remoteFolder:FindFirstChild("SpectateTeammate")
    if spectateRemote then
        spectateRemote.OnServerEvent:Connect(function(player, targetUserId)
            self:SpectateTeammate(player, targetUserId)
        end)
    end
end

--[[
    Set the current game mode
]]
function SquadSystem:SetMode(mode)
    if not gameConfig.Modes[mode] then
        framework.Log("Error", "Invalid mode: %s", mode)
        return false
    end

    currentMode = mode
    framework.Log("Info", "Squad mode set to: %s", mode)
    return true
end

--[[
    Get current mode
]]
function SquadSystem:GetMode()
    return currentMode
end

--[[
    Get mode configuration
]]
function SquadSystem:GetModeConfig()
    return gameConfig.Modes[currentMode]
end

--[[
    Form squads from current players
]]
function SquadSystem:FormSquads()
    -- Clear existing squads
    squads = {}
    playerSquadMap = {}

    local modeConfig = self:GetModeConfig()
    local players = Players:GetPlayers()
    local teamSize = modeConfig.teamSize

    if teamSize == 1 then
        -- Solo mode: each player is their own squad
        for _, player in ipairs(players) do
            local squadId = "squad_" .. player.UserId
            squads[squadId] = {
                id = squadId,
                members = {
                    [player.UserId] = {
                        userId = player.UserId,
                        name = player.Name,
                        state = SquadSystem.PlayerStates.ALIVE,
                        health = 100,
                        shield = 0,
                    }
                },
                alive = true,
            }
            playerSquadMap[player.UserId] = squadId
        end
    else
        -- Team modes: group players
        local squadIndex = 1

        for i, player in ipairs(players) do
            local squadId = "squad_" .. squadIndex

            if not squads[squadId] then
                squads[squadId] = {
                    id = squadId,
                    members = {},
                    alive = true,
                }
            end

            squads[squadId].members[player.UserId] = {
                userId = player.UserId,
                name = player.Name,
                state = SquadSystem.PlayerStates.ALIVE,
                health = 100,
                shield = 0,
            }

            playerSquadMap[player.UserId] = squadId

            -- Move to next squad if this one is full
            local memberCount = 0
            for _ in pairs(squads[squadId].members) do
                memberCount = memberCount + 1
            end

            if memberCount >= teamSize then
                squadIndex = squadIndex + 1
            end
        end
    end

    -- Broadcast squad assignments
    self:BroadcastSquadUpdate()

    framework.Log("Info", "Formed %d squads for mode: %s", self:CountSquads(), currentMode)
    return true
end

--[[
    Count active squads
]]
function SquadSystem:CountSquads()
    local count = 0
    for _ in pairs(squads) do
        count = count + 1
    end
    return count
end

--[[
    Count alive squads
]]
function SquadSystem:CountAliveSquads()
    local count = 0
    for _, squad in pairs(squads) do
        if squad.alive then
            count = count + 1
        end
    end
    return count
end

--[[
    Get a player's squad
]]
function SquadSystem:GetPlayerSquad(player)
    local squadId = playerSquadMap[player.UserId]
    if squadId then
        return squads[squadId]
    end
    return nil
end

--[[
    Get teammates for a player (excluding self)
]]
function SquadSystem:GetTeammates(player)
    local squad = self:GetPlayerSquad(player)
    if not squad then
        return {}
    end

    local teammates = {}
    for userId, memberData in pairs(squad.members) do
        if userId ~= player.UserId then
            table.insert(teammates, memberData)
        end
    end

    return teammates
end

--[[
    Update player state (alive, downed, dead)
]]
function SquadSystem:SetPlayerState(player, state)
    local squad = self:GetPlayerSquad(player)
    if not squad then
        return false
    end

    local member = squad.members[player.UserId]
    if not member then
        return false
    end

    local oldState = member.state
    member.state = state

    framework.Log("Debug", "%s state changed: %s -> %s", player.Name, oldState, state)

    -- Check if player is eliminated
    if state == SquadSystem.PlayerStates.DEAD then
        self:CheckSquadElimination(squad)
    end

    -- Broadcast state change
    self:BroadcastTeammateState(squad, player.UserId, state)

    return true
end

--[[
    Handle player taking damage
]]
function SquadSystem:OnPlayerDamaged(player, damage, attacker)
    local squad = self:GetPlayerSquad(player)
    if not squad then return end

    local member = squad.members[player.UserId]
    if not member then return end

    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end

    member.health = humanoid.Health
end

--[[
    Handle player eliminated (health reaches 0)
]]
function SquadSystem:OnPlayerEliminated(player, killer)
    local modeConfig = self:GetModeConfig()

    if modeConfig.teamSize == 1 or not modeConfig.reviveEnabled then
        -- Solo or no revive: instant death
        self:SetPlayerState(player, SquadSystem.PlayerStates.DEAD)
    else
        -- Team mode with revive: go to downed state
        local squad = self:GetPlayerSquad(player)
        if squad then
            -- Check if any teammates are alive (not downed or dead)
            local hasAliveTeammate = false
            for userId, member in pairs(squad.members) do
                if userId ~= player.UserId and member.state == SquadSystem.PlayerStates.ALIVE then
                    hasAliveTeammate = true
                    break
                end
            end

            if hasAliveTeammate then
                self:SetPlayerState(player, SquadSystem.PlayerStates.DOWNED)
                self:StartBleedout(player)
            else
                -- No one to revive, instant death
                self:SetPlayerState(player, SquadSystem.PlayerStates.DEAD)
            end
        end
    end
end

--[[
    Start bleedout timer for downed player
]]
function SquadSystem:StartBleedout(player)
    local modeConfig = self:GetModeConfig()
    local bleedoutTime = modeConfig.bleedoutTime or 30

    task.spawn(function()
        local elapsed = 0

        while elapsed < bleedoutTime do
            task.wait(1)
            elapsed = elapsed + 1

            local squad = self:GetPlayerSquad(player)
            if not squad then break end

            local member = squad.members[player.UserId]
            if not member then break end

            -- Check if revived
            if member.state ~= SquadSystem.PlayerStates.DOWNED then
                return
            end
        end

        -- Bleedout complete - player dies
        self:SetPlayerState(player, SquadSystem.PlayerStates.DEAD)
    end)
end

--[[
    Start reviving a teammate
]]
function SquadSystem:StartRevive(reviver, targetUserId)
    local reviverSquad = self:GetPlayerSquad(reviver)
    if not reviverSquad then return false end

    -- Check if target is a teammate
    local targetMember = reviverSquad.members[targetUserId]
    if not targetMember then
        return false -- Not on same team
    end

    -- Check if target is downed
    if targetMember.state ~= SquadSystem.PlayerStates.DOWNED then
        return false
    end

    local modeConfig = self:GetModeConfig()
    local reviveTime = modeConfig.reviveTime or 5

    framework.Log("Debug", "%s started reviving %s", reviver.Name, targetMember.name)

    -- Broadcast revive started
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.ReviveStarted:FireAllClients(reviver.UserId, targetUserId, reviveTime)
    end

    -- Start revive process
    task.spawn(function()
        task.wait(reviveTime)

        -- Verify still valid
        local squad = self:GetPlayerSquad(reviver)
        if not squad then return end

        local member = squad.members[targetUserId]
        if not member or member.state ~= SquadSystem.PlayerStates.DOWNED then
            return
        end

        -- Complete revive
        self:CompleteRevive(reviver, targetUserId)
    end)

    return true
end

--[[
    Complete a revive
]]
function SquadSystem:CompleteRevive(reviver, targetUserId)
    local squad = self:GetPlayerSquad(reviver)
    if not squad then return end

    local member = squad.members[targetUserId]
    if not member then return end

    -- Set state back to alive
    member.state = SquadSystem.PlayerStates.ALIVE
    member.health = 30 -- Revive with low health

    -- Restore player health
    local targetPlayer = Players:GetPlayerByUserId(targetUserId)
    if targetPlayer and targetPlayer.Character then
        local humanoid = targetPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.Health = 30
        end
    end

    framework.Log("Info", "%s revived %s", reviver.Name, member.name)

    -- Broadcast revive completed
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.ReviveCompleted:FireAllClients(reviver.UserId, targetUserId)
    end
end

--[[
    Check if a squad is eliminated
]]
function SquadSystem:CheckSquadElimination(squad)
    local hasAlive = false

    for _, member in pairs(squad.members) do
        if member.state == SquadSystem.PlayerStates.ALIVE or member.state == SquadSystem.PlayerStates.DOWNED then
            hasAlive = true
            break
        end
    end

    if not hasAlive then
        squad.alive = false
        framework.Log("Info", "Squad %s eliminated", squad.id)

        -- All remaining members go to spectating
        for userId, member in pairs(squad.members) do
            if member.state == SquadSystem.PlayerStates.DEAD then
                member.state = SquadSystem.PlayerStates.SPECTATING
            end
        end
    end
end

--[[
    Check if on same team (for friendly fire prevention)
]]
function SquadSystem:AreTeammates(player1, player2)
    local squad1 = playerSquadMap[player1.UserId]
    local squad2 = playerSquadMap[player2.UserId]

    return squad1 and squad2 and squad1 == squad2
end

--[[
    Spectate a teammate
]]
function SquadSystem:SpectateTeammate(player, targetUserId)
    local squad = self:GetPlayerSquad(player)
    if not squad then return false end

    -- Check if target is on same team
    if not squad.members[targetUserId] then
        return false
    end

    -- Check if target is alive
    local targetMember = squad.members[targetUserId]
    if targetMember.state ~= SquadSystem.PlayerStates.ALIVE then
        return false
    end

    framework.Log("Debug", "%s spectating %s", player.Name, targetMember.name)

    -- Client handles the actual spectate camera
    return true
end

--[[
    Get winning squad
]]
function SquadSystem:GetWinningSquad()
    local aliveSquads = {}

    for squadId, squad in pairs(squads) do
        if squad.alive then
            table.insert(aliveSquads, squad)
        end
    end

    if #aliveSquads == 1 then
        return aliveSquads[1]
    end

    return nil
end

--[[
    Broadcast squad update to all members
]]
function SquadSystem:BroadcastSquadUpdate()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    for squadId, squad in pairs(squads) do
        for userId, _ in pairs(squad.members) do
            local player = Players:GetPlayerByUserId(userId)
            if player then
                remotes.SquadUpdate:FireClient(player, {
                    squadId = squadId,
                    members = squad.members,
                })
            end
        end
    end
end

--[[
    Broadcast teammate state change
]]
function SquadSystem:BroadcastTeammateState(squad, userId, state)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    for memberId, _ in pairs(squad.members) do
        local player = Players:GetPlayerByUserId(memberId)
        if player then
            remotes.TeammateStateChanged:FireClient(player, userId, state)
        end
    end
end

--[[
    Reset all squads
]]
function SquadSystem:Reset()
    squads = {}
    playerSquadMap = {}
    framework.Log("Info", "SquadSystem reset")
end

--[[
    Get all squads (for debugging)
]]
function SquadSystem:GetAllSquads()
    return squads
end

return SquadSystem
