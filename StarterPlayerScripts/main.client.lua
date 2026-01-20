--[[
    =========================================================================
    Dino Royale 2 - Client Bootstrap
    =========================================================================

    Main entry point for client-side game initialization.
    This script runs when a player joins and sets up all client systems.

    Initialization Order:
    1. Wait for Remotes to be ready (server must create them first)
    2. Load shared modules (GameConfig, Remotes)
    3. Initialize HUD (DinoHUD module)
    4. Setup remote event handlers (receive server state updates)
    5. Setup input handling (weapon slots, inventory, map)
    6. Request initial state from server (game state, squad info)
    7. Disable default Roblox UI (use custom HUD)

    Architecture Notes:
    - Client is purely reactive (responds to server events)
    - All game logic happens server-side (no client prediction)
    - Client maintains local state for UI responsiveness
    - Input events are sent to server for validation

    Remote Event Categories:
    - Game State: GameStateChanged, MatchStarting, VictoryDeclared, etc.
    - Storm: StormPhaseChanged, StormWarning, StormDamage
    - Squad: SquadUpdate, TeammateStateChanged, ReviveStarted, ReviveCompleted
    - Dinosaurs: DinoSpawned, DinoDamaged, DinoDied, DinoAttack
    - Weapons: WeaponFire, DamageDealt, BulletHit
    - Loot: LootSpawned, LootPickedUp, ChestOpened

    =========================================================================
]]

-- Roblox service references
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

-- Get the local player reference (client-side only)
local player = Players.LocalPlayer

--=============================================================================
-- INITIALIZATION
--=============================================================================

print("[DinoRoyale Client] Starting...")

-- Wait for Remotes folder to exist
local remoteFolder = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remoteFolder then
    warn("[DinoRoyale Client] Failed to find Remotes folder!")
    return
end
print("[DinoRoyale Client] Remotes ready")

-- Get shared modules
-- Rojo maps src/shared to ReplicatedStorage.Shared
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage.Shared:WaitForChild("Remotes"))
print("[DinoRoyale Client] Shared modules loaded")

--=============================================================================
-- HUD INITIALIZATION
--=============================================================================

-- Initialize the DinoHUD
-- Rojo maps module to ReplicatedStorage.Module
local DinoHUD = require(ReplicatedStorage:WaitForChild("Module"):WaitForChild("DinoHUD"))
local hud = DinoHUD:Initialize()
print("[DinoRoyale Client] HUD initialized")

--=============================================================================
-- CLIENT STATE
-- Local state for UI responsiveness and tracking
-- This mirrors server state but is updated via remote events
--=============================================================================

--[[
    Client-side state tracking
    - gameState: Current match phase (Lobby, Starting, Dropping, Match, Ending)
    - selectedWeaponSlot: Currently equipped weapon slot (1-5)
    - inventory: Local copy of inventory for UI display
    - squad: Squad assignment info (squadId, members)
    - isAlive: Whether local player is alive in match
    - isDowned: Whether local player is in downed state (can be revived)
]]
local clientState = {
    gameState = "Lobby",        -- Current match state
    selectedWeaponSlot = 1,     -- Active weapon slot (1-5)
    inventory = {},             -- Cached inventory for UI
    squad = nil,                -- Squad info {squadId, members}
    isAlive = true,             -- Player alive status
    isDowned = false,           -- Downed but not eliminated (revivable)
}

--=============================================================================
-- REMOTE EVENT HANDLERS
-- Respond to server events via RemoteEvents
-- These callbacks update local state and trigger UI changes
--=============================================================================

-- ============== GAME STATE EVENTS ==============

--[[
    Handle game state transitions
    States: Lobby → Starting → Dropping → Match → Ending → Cleanup
    Each state has different UI requirements
]]
Remotes.OnEvent("GameStateChanged", function(newState, oldState)
    print(string.format("[DinoRoyale Client] Game state: %s -> %s", oldState or "none", newState))
    clientState.gameState = newState

    -- Handle state-specific UI changes
    if newState == "Lobby" then
        hud:SetEnabled(true)
        -- Show lobby UI
        hud:UpdateLobbyUI({
            currentPlayers = #game:GetService("Players"):GetPlayers(),
            requiredPlayers = 60,
            canStart = false,
        })
        hud:HideDeathScreen()
        hud:HideVictoryScreen()
        hud:HideSpectatorUI()
    elseif newState == "Starting" then
        -- Show countdown UI (lobby UI updates via CountdownUpdate)
    elseif newState == "Dropping" then
        -- Hide lobby UI, show drop UI
        hud:HideLobbyUI()
    elseif newState == "Match" then
        -- Full HUD enabled, hide any overlays
        hud:SetEnabled(true)
        hud:HideLobbyUI()
    elseif newState == "Ending" then
        -- Show results (handled by VictoryDeclared event)
    elseif newState == "Cleanup" then
        -- Reset all screens for next match
        hud:HideBossHealth()
        hud:HideDinoHealth()
    end
end)

-- Match starting countdown
Remotes.OnEvent("MatchStarting", function(countdown)
    print(string.format("[DinoRoyale Client] Match starting in %d...", countdown))
    -- Countdown is displayed via lobby UI updates from CountdownUpdate event
    -- The lobby UI shows the timer when canStart=true
end)

-- Player eliminated
Remotes.OnEvent("PlayerEliminated", function(victimId, killerId, placement, killerName)
    -- Add to kill feed
    hud:AddKillFeedItem(victimId, killerId)

    -- Check if we were eliminated
    if victimId == player.UserId then
        clientState.isAlive = false
        print("[DinoRoyale Client] You were eliminated!")
        -- Show death screen with killer info and placement
        hud:ShowDeathScreen(killerName or "Unknown", placement)
    end
end)

-- Victory declared
Remotes.OnEvent("VictoryDeclared", function(winner, stats)
    print("[DinoRoyale Client] Victory!")
    -- Show victory or defeat screen based on whether we won
    if winner == player.UserId or (winner and winner.squadId and winner.squadId == clientState.squad) then
        hud:ShowVictoryScreen(stats)
    end
end)

-- Players alive count update
Remotes.OnEvent("UpdatePlayersAlive", function(playersAlive, teamsAlive)
    hud:UpdatePlayerCount(playersAlive)
end)

-- Lobby status update (player count, timer, can start)
Remotes.OnEvent("LobbyStatusUpdate", function(data)
    hud:UpdateLobbyUI(data)
end)

-- Countdown update
Remotes.OnEvent("CountdownUpdate", function(seconds)
    -- Update lobby timer if in lobby state
    if clientState.gameState == "Lobby" or clientState.gameState == "Starting" then
        hud:UpdateLobbyUI({
            currentPlayers = #game:GetService("Players"):GetPlayers(),
            requiredPlayers = 60,
            timeRemaining = seconds,
            canStart = true,
        })
    end
end)

--=============================================================================
-- STORM EVENT HANDLERS
-- Handle shrinking zone updates and warnings
--=============================================================================

-- ============== STORM EVENTS ==============

-- Storm phase changed (zone is shrinking)
Remotes.OnEvent("StormPhaseChanged", function(data)
    hud:UpdateStormDisplay(data)
    print(string.format("[DinoRoyale Client] Storm phase %d - radius: %d", data.phase, data.targetRadius))
end)

-- Storm warning
Remotes.OnEvent("StormWarning", function(delay, phase)
    hud:ShowStormWarning(delay, phase)
end)

-- Storm damage taken
Remotes.OnEvent("StormDamage", function(damage)
    -- Flash screen red / show damage indicator
    hud:ShowDamageIndicator(nil) -- No direction for storm damage
end)

--=============================================================================
-- SQUAD EVENT HANDLERS
-- Handle team assignments, teammate status, and revive mechanics
--=============================================================================

-- ============== SQUAD EVENTS ==============

-- Squad update - received when teams are formed or changed
Remotes.OnEvent("SquadUpdate", function(data)
    clientState.squad = data
    print(string.format("[DinoRoyale Client] Squad assigned: %s", data.squadId))
    -- Squad UI is part of DinoHUD - updates teammate indicators on minimap
    -- and shows squad member health bars when in duos/trios mode
end)

-- Teammate state changed
Remotes.OnEvent("TeammateStateChanged", function(userId, state)
    print(string.format("[DinoRoyale Client] Teammate %d is now %s", userId, state))
    -- State can be: "alive", "downed", "eliminated"
    -- DinoHUD automatically updates teammate indicators based on this state
end)

-- Revive started
Remotes.OnEvent("ReviveStarted", function(reviverId, targetId, duration)
    print(string.format("[DinoRoyale Client] Revive started (%ds)", duration))
    -- Show revive progress indicator
    -- If we're the one being revived, show centered progress bar
    -- If we're reviving, show progress near crosshair
    if targetId == player.UserId then
        hud:ShowReviveProgress(duration, true)  -- Being revived
    elseif reviverId == player.UserId then
        hud:ShowReviveProgress(duration, false) -- Reviving teammate
    end
end)

-- Revive completed
Remotes.OnEvent("ReviveCompleted", function(reviverId, targetId)
    if targetId == player.UserId then
        clientState.isAlive = true
        clientState.isDowned = false
        print("[DinoRoyale Client] You were revived!")
    end
end)

--=============================================================================
-- DINOSAUR EVENT HANDLERS
-- Handle dinosaur spawning, damage, deaths, and attacks
-- Used for visual/audio feedback and targeting UI
--=============================================================================

-- ============== DINOSAUR EVENTS ==============

-- Dinosaur spawned nearby - create visual indicators
Remotes.OnEvent("DinoSpawned", function(data)
    -- Create client-side visual/sound effects
    print(string.format("[DinoRoyale Client] Dinosaur spawned: %s at %s", data.type, tostring(data.position)))
end)

-- Dinosaur damaged - show health bar for damaged dinos
Remotes.OnEvent("DinoDamaged", function(dinoId, damage, currentHealth, maxHealth, dinoName)
    -- Update dinosaur health bar display
    if dinoName then
        hud:UpdateDinoHealth(dinoName, currentHealth, maxHealth)
    end
end)

-- Dinosaur died
Remotes.OnEvent("DinoDied", function(dinoId, killerUserId)
    -- Play death effects
    if killerUserId == player.UserId then
        print("[DinoRoyale Client] You killed a dinosaur!")
    end
end)

-- Dinosaur attack
Remotes.OnEvent("DinoAttack", function(data)
    -- Play attack sound/visual at location
end)

-- ============== BOSS EVENTS ==============

-- Boss spawned - show boss health bar
Remotes.OnEvent("BossSpawned", function(bossId, bossName, health, maxHealth)
    print(string.format("[DinoRoyale Client] Boss spawned: %s", bossName))
    hud:ShowBossHealth(bossName, health, maxHealth, 1)
end)

-- Boss phase changed - update health bar and phase indicator
Remotes.OnEvent("BossPhaseChanged", function(bossId, phase, health, maxHealth, bossName)
    hud:ShowBossHealth(bossName or "Boss", health, maxHealth, phase)
end)

-- Boss died - hide health bar
Remotes.OnEvent("BossDied", function(bossId, killerUserId)
    print("[DinoRoyale Client] Boss defeated!")
    hud:HideBossHealth()
end)

--=============================================================================
-- WEAPON EVENT HANDLERS
-- Handle weapon effects, hit feedback, and bullet impacts
-- Provides audio/visual feedback for combat
--=============================================================================

-- ============== WEAPON EVENTS ==============

-- Weapon fire - play gunshot sounds for other players (not local player)
Remotes.OnEvent("WeaponFire", function(shooterUserId, weaponId, origin, direction)
    if shooterUserId ~= player.UserId then
        -- Play gunshot sound at location
    end
end)

-- Damage dealt feedback
Remotes.OnEvent("DamageDealt", function(targetUserId, damage, isHeadshot)
    -- Hit marker feedback
    print(string.format("[DinoRoyale Client] Hit for %d damage%s", damage, isHeadshot and " (HEADSHOT)" or ""))
    -- Show hit marker on crosshair and play sound
    hud:ShowHitMarker(isHeadshot)
    -- Damage numbers float up from target position (handled by DinoHUD)
end)

-- Bullet hit effect
Remotes.OnEvent("BulletHit", function(position, surfaceType)
    -- Spawn impact effect at position
end)

--=============================================================================
-- LOOT EVENT HANDLERS
-- Handle loot spawning, pickup feedback, and chest interactions
--=============================================================================

-- ============== LOOT EVENTS ==============

-- Loot spawned nearby - could add glow/indicator effects
Remotes.OnEvent("LootSpawned", function(data)
    -- Could add glow effect or indicator
end)

-- Loot picked up
Remotes.OnEvent("LootPickedUp", function(data)
    if data.playerId == player.UserId then
        -- Update inventory display
        -- Play pickup sound
    end
end)

-- Chest opened
Remotes.OnEvent("ChestOpened", function(data)
    -- Play chest open sound at location
end)

--=============================================================================
-- INPUT HANDLING
-- Process keyboard/mouse input for game controls
-- Input is validated client-side then sent to server for authorization
--=============================================================================

--[[
    Keyboard Controls:
    - 1-5: Select weapon slot
    - Tab: Toggle inventory screen (not implemented)
    - M: Toggle fullscreen map (not implemented)

    Note: gameProcessed=true means Roblox UI consumed the input
    (e.g., typing in chat) - we should ignore these inputs
]]
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Ignore inputs that were consumed by Roblox UI (chat, menus, etc.)
    if gameProcessed then return end

    -- Number keys 1-5 map to weapon slots
    local slotKeys = {
        [Enum.KeyCode.One] = 1,
        [Enum.KeyCode.Two] = 2,
        [Enum.KeyCode.Three] = 3,
        [Enum.KeyCode.Four] = 4,
        [Enum.KeyCode.Five] = 5,
    }

    -- Handle weapon slot selection
    if slotKeys[input.KeyCode] then
        local slot = slotKeys[input.KeyCode]
        clientState.selectedWeaponSlot = slot
        hud:SelectWeaponSlot(slot)  -- Update HUD highlight
        -- Send equip request to server for validation
        Remotes.FireServer("WeaponEquip", slot)
    end

    -- Tab key - toggle inventory screen
    if input.KeyCode == Enum.KeyCode.Tab then
        -- Toggle full inventory overlay showing all items, ammo, and equipment
        hud:ToggleInventoryScreen()
    end

    -- M key - toggle fullscreen map
    if input.KeyCode == Enum.KeyCode.M then
        -- Toggle fullscreen map showing terrain, storm circle, and teammate positions
        hud:ToggleFullscreenMap()
    end

    -- R key - reload weapon
    if input.KeyCode == Enum.KeyCode.R then
        Remotes.FireServer("WeaponReload")
    end
end)

--=============================================================================
-- MOUSE INPUT HANDLING
-- Handle mouse buttons for weapon firing, aiming, and interaction
--=============================================================================

-- Track mouse button states for automatic weapons
local isMouseDown = false
local isAiming = false
local fireConnection = nil

--[[
    Get the mouse position and direction for aiming/shooting
    @return Vector3 origin, Vector3 direction
]]
local function getMouseRay()
    local mouse = player:GetMouse()
    local camera = workspace.CurrentCamera

    if camera then
        local mousePos = UserInputService:GetMouseLocation()
        local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
        return ray.Origin, ray.Direction * 1000
    end

    return Vector3.new(0, 0, 0), Vector3.new(0, 0, -1)
end

--[[
    Fire the equipped weapon
    Sends fire request to server with aim direction
]]
local function fireWeapon()
    if not clientState.isAlive then return end
    if clientState.gameState ~= "Match" and clientState.gameState ~= "Lobby" then return end

    local origin, direction = getMouseRay()
    Remotes.FireServer("WeaponFire", origin, direction)
end

-- Handle mouse button down (start firing)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    -- Left mouse button - Fire weapon
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isMouseDown = true
        fireWeapon()

        -- Start continuous firing for automatic weapons
        if not fireConnection then
            fireConnection = RunService.Heartbeat:Connect(function()
                if isMouseDown and clientState.isAlive then
                    fireWeapon()
                end
            end)
        end
    end

    -- Right mouse button - Aim down sights (ADS)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isAiming = true
        Remotes.FireServer("WeaponAim", true)
        -- Could also adjust camera FOV here for zoom effect
    end
end)

-- Handle mouse button up (stop firing/aiming)
UserInputService.InputEnded:Connect(function(input, gameProcessed)
    -- Left mouse button released - Stop firing
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isMouseDown = false
        if fireConnection then
            fireConnection:Disconnect()
            fireConnection = nil
        end
    end

    -- Right mouse button released - Stop aiming
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isAiming = false
        Remotes.FireServer("WeaponAim", false)
    end
end)

-- Enable mouse lock (first-person style aiming)
-- This keeps the mouse centered for better FPS-style controls
UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

-- Handle mouse scroll for weapon switching
UserInputService.InputChanged:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.UserInputType == Enum.UserInputType.MouseWheel then
        local scroll = input.Position.Z  -- Positive = up, Negative = down

        if scroll > 0 then
            -- Scroll up - previous weapon
            local newSlot = clientState.selectedWeaponSlot - 1
            if newSlot < 1 then newSlot = 5 end
            clientState.selectedWeaponSlot = newSlot
            hud:SelectWeaponSlot(newSlot)
            Remotes.FireServer("WeaponEquip", newSlot)
        elseif scroll < 0 then
            -- Scroll down - next weapon
            local newSlot = clientState.selectedWeaponSlot + 1
            if newSlot > 5 then newSlot = 1 end
            clientState.selectedWeaponSlot = newSlot
            hud:SelectWeaponSlot(newSlot)
            Remotes.FireServer("WeaponEquip", newSlot)
        end
    end
end)

--=============================================================================
-- CHARACTER HANDLING
-- Track character spawn, health, and death events
--=============================================================================

--[[
    Called when player's character is spawned/respawned
    Sets up event listeners for health and death tracking
    @param character Model - The player's character model
]]
local function onCharacterAdded(character)
    print("[DinoRoyale Client] Character spawned")

    -- Wait for Humanoid component (required for health/death tracking)
    local humanoid = character:WaitForChild("Humanoid")

    -- Track health changes for HUD updates
    -- Note: DinoHUD has its own update loop that reads health directly,
    -- but this event can be used for additional feedback (hit sounds, etc.)
    humanoid.HealthChanged:Connect(function(health)
        -- HUD updates automatically in its update loop
    end)

    -- Track character death
    -- Server handles the actual elimination logic; this is for client feedback
    humanoid.Died:Connect(function()
        print("[DinoRoyale Client] Character died")
        -- Server will send PlayerEliminated event with full context
    end)

    -- Reset local alive state when character spawns
    clientState.isAlive = true
    clientState.isDowned = false
end

-- Connect to character spawns
-- Handle both existing character (if script runs after spawn) and future spawns
if player.Character then
    onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

--=============================================================================
-- REQUEST INITIAL STATE FROM SERVER
-- Fetch current state when joining (late-join support)
-- Uses RemoteFunctions for synchronous request/response
--=============================================================================

-- Request current game state from server
-- This handles late-joiners who need to know if a match is in progress
task.spawn(function()
    local gameState = Remotes.Invoke("GetGameState")
    if gameState then
        clientState.gameState = gameState.state
        print(string.format("[DinoRoyale Client] Current game state: %s", gameState.state))
        -- gameState also contains: mode (solo/duos/trios), storm (zone info)
    end
end)

-- Request squad info from server
-- Gets current team assignment if in duos/trios mode
task.spawn(function()
    local squadInfo = Remotes.Invoke("GetSquadInfo")
    if squadInfo then
        clientState.squad = squadInfo
        print(string.format("[DinoRoyale Client] Current squad: %s", squadInfo.squadId or "none"))
        -- squadInfo contains: squadId, members, mode
    end
end)

--=============================================================================
-- DISABLE DEFAULT ROBLOX UI
-- Hide default Roblox UI elements that conflict with custom HUD
--=============================================================================

-- Disable default health bar (DinoHUD provides custom health/shield bars)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)

-- Disable default backpack/inventory (DinoHUD provides custom weapon hotbar)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

-- Note: Other CoreGuiTypes that could be disabled:
-- Enum.CoreGuiType.PlayerList - Disable if using custom scoreboard
-- Enum.CoreGuiType.EmotesMenu - Disable if not supporting emotes
-- Enum.CoreGuiType.Chat - Keep enabled for player communication

--=============================================================================
-- STARTUP COMPLETE
--=============================================================================

print("[DinoRoyale Client] ========================================")
print("[DinoRoyale Client] Client initialization complete!")
print(string.format("[DinoRoyale Client] Player: %s", player.Name))
print("[DinoRoyale Client] ========================================")

-- Client is now ready and listening for server events
-- All game logic is server-authoritative; client just displays state
