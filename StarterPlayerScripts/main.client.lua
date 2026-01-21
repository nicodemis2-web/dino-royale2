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

-- Initialize TouchControls for mobile devices
local TouchControls = require(ReplicatedStorage:WaitForChild("Module"):WaitForChild("TouchControls"))
local touchControls = TouchControls:Initialize()
local isTouchDevice = touchControls:IsTouchDevice()
print("[DinoRoyale Client] Touch controls initialized (Touch device: " .. tostring(isTouchDevice) .. ")")

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

    -- Update touch controls for game state (show/hide combat buttons)
    if isTouchDevice then
        touchControls:UpdateForGameState(newState)
    end

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
        -- Lock mouse for gameplay (in case tutorial didn't run or was skipped)
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    elseif newState == "Match" then
        -- Full HUD enabled, hide any overlays
        hud:SetEnabled(true)
        hud:HideLobbyUI()
        -- Ensure mouse is locked for gameplay
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
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

-- ============== STORM AUDIO SYSTEM ==============

-- Storm ambient sound (loops while player is in the storm)
local stormAmbientSound = nil
local stormWindSound = nil
local isInStorm = false

-- Track failed sound IDs to avoid repeated load attempts
local failedSoundIds = {}

--[[
    Safely create and configure a sound with fallback handling
    Prevents console spam from failed sound loads

    @param parent Instance - Parent for the sound
    @param soundId string - Roblox sound asset ID
    @param properties table - Sound properties (Volume, Looped, etc.)
    @return Sound|nil - The created sound or nil if disabled
]]
local function createSafeSound(parent, soundId, properties)
    -- Skip if this sound ID already failed
    if failedSoundIds[soundId] then
        return nil
    end

    local sound = Instance.new("Sound")
    sound.Name = properties.Name or "Sound"
    sound.Volume = properties.Volume or 0.5
    sound.Looped = properties.Looped or false
    sound.PlaybackSpeed = properties.PlaybackSpeed or 1
    sound.Parent = parent

    -- Try to set the sound ID and mark as failed if it errors
    local success = pcall(function()
        sound.SoundId = soundId
    end)

    if not success then
        failedSoundIds[soundId] = true
        sound:Destroy()
        return nil
    end

    return sound
end

--[[
    Initialize storm audio system
    Creates looping ambient sounds that play when player is in the storm
    Uses safe sound loading to prevent console errors
]]
local function initStormAudio()
    -- Storm crackle/electric ambient
    stormAmbientSound = createSafeSound(workspace.CurrentCamera, "rbxassetid://9114491437", {
        Name = "StormAmbient",
        Volume = 0,
        Looped = true,
    })

    -- Storm wind howling (same sound, different pitch for variety)
    stormWindSound = createSafeSound(workspace.CurrentCamera, "rbxassetid://9114491437", {
        Name = "StormWind",
        Volume = 0,
        Looped = true,
        PlaybackSpeed = 0.8,  -- Deeper wind sound
    })

    -- Start playing if sounds were created successfully
    if stormAmbientSound then
        stormAmbientSound:Play()
    end
    if stormWindSound then
        stormWindSound:Play()
    end
end

--[[
    Update storm audio based on player position relative to zone
    Called each frame to smoothly fade audio in/out

    @param inStorm boolean - Whether player is outside the safe zone
    @param distanceFromEdge number - How far outside the zone (0 if inside)
]]
local function updateStormAudio(inStorm, distanceFromEdge)
    -- Skip audio updates if sounds failed to load
    if not stormAmbientSound and not stormWindSound then
        return
    end

    local targetVolume = 0
    local targetWindVolume = 0

    if inStorm then
        -- Volume increases with distance from zone edge
        -- Max volume at 50+ studs outside
        local intensityFactor = math.min(1, distanceFromEdge / 50)
        targetVolume = 0.3 + (intensityFactor * 0.5)  -- 0.3 to 0.8
        targetWindVolume = 0.2 + (intensityFactor * 0.4)  -- 0.2 to 0.6
    end

    -- Smooth volume transitions (only for sounds that loaded)
    if stormAmbientSound then
        stormAmbientSound.Volume = stormAmbientSound.Volume + (targetVolume - stormAmbientSound.Volume) * 0.1
    end
    if stormWindSound then
        stormWindSound.Volume = stormWindSound.Volume + (targetWindVolume - stormWindSound.Volume) * 0.1
    end

    isInStorm = inStorm
end

--[[
    Play storm warning siren
    Alert sound when the storm is about to move
]]
local function playStormWarningSiren()
    -- Skip if this sound already failed
    -- Using a public alarm/siren sound
    if failedSoundIds["rbxassetid://9120224953"] then
        return
    end

    local sirenSound = createSafeSound(workspace.CurrentCamera, "rbxassetid://9120224953", {
        Name = "StormSiren",
        Volume = 0.6,
    })

    if sirenSound then
        sirenSound:Play()
        sirenSound.Ended:Connect(function()
            sirenSound:Destroy()
        end)
    end
end

--[[
    Play storm damage tick sound
    Audio feedback when taking storm damage
]]
local function playStormDamageSound()
    -- Skip if this sound already failed
    if failedSoundIds["rbxassetid://4812054633"] then
        return
    end

    local damageSound = createSafeSound(workspace.CurrentCamera, "rbxassetid://4812054633", {
        Name = "StormDamage",
        Volume = 0.4,
        PlaybackSpeed = 1.5,  -- Higher pitch for damage
    })

    if damageSound then
        damageSound:Play()
        damageSound.Ended:Connect(function()
            damageSound:Destroy()
        end)
    end
end

-- Initialize storm audio on load
initStormAudio()

-- ============== STORM EVENTS ==============

-- Storm phase changed (zone is shrinking)
Remotes.OnEvent("StormPhaseChanged", function(data)
    hud:UpdateStormDisplay(data)
    print(string.format("[DinoRoyale Client] Storm phase %d - radius: %d", data.phase, data.targetRadius))

    -- Play subtle phase change audio cue (skip if sound already failed)
    if not failedSoundIds["rbxassetid://9116884651"] then
        local phaseSound = createSafeSound(workspace.CurrentCamera, "rbxassetid://9116884651", {
            Name = "StormPhase",
            Volume = 0.3,
            PlaybackSpeed = 0.6,  -- Deep rumble
        })

        if phaseSound then
            phaseSound:Play()
            phaseSound.Ended:Connect(function()
                phaseSound:Destroy()
            end)
        end
    end
end)

-- Storm warning
Remotes.OnEvent("StormWarning", function(delay, phase)
    hud:ShowStormWarning(delay, phase)
    playStormWarningSiren()
end)

-- Storm damage taken
Remotes.OnEvent("StormDamage", function(damage)
    -- Flash screen red / show damage indicator
    hud:ShowDamageIndicator(nil) -- No direction for storm damage
    playStormDamageSound()
end)

-- Update storm audio based on player position (check every frame)
RunService.Heartbeat:Connect(function()
    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- Check if player is in the storm (use StormService remote state)
    -- This is tracked via the StormDamage event - if we're taking damage, we're in the storm
    -- For smoother audio, we estimate based on damage events
    -- The actual check would require server communication, so we use a simpler approach

    -- Storm audio will fade in/out based on StormDamage events
    -- When we receive damage, mark as in storm and gradually fade audio
    if isInStorm then
        updateStormAudio(true, 20)  -- Assume moderate distance when in storm
    else
        updateStormAudio(false, 0)
    end
end)

-- Track storm state based on damage events
local lastStormDamageTime = 0
Remotes.OnEvent("StormDamage", function(damage)
    lastStormDamageTime = tick()
    isInStorm = true
end)

-- Clear storm state if no damage for 2 seconds
RunService.Heartbeat:Connect(function()
    if isInStorm and (tick() - lastStormDamageTime) > 2 then
        isInStorm = false
    end
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

-- Weapon fire - play gunshot sounds and effects for other players (not local player)
Remotes.OnEvent("WeaponFire", function(data)
    -- Server sends: {shooterId, weaponType, origin, direction, weaponCategory}
    if type(data) ~= "table" then return end

    local shooterId = data.shooterId
    local origin = data.origin
    local weaponCategory = data.weaponCategory or "assault_rifle"

    -- Don't play for our own shots (we handle that locally)
    if shooterId == player.UserId then return end
    if not origin then return end

    -- Find the shooter's character to play sound at their position
    local shooter = nil
    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
        if p.UserId == shooterId then
            shooter = p
            break
        end
    end

    -- Get weapon-specific sound configuration
    local soundConfig = WEAPON_SOUNDS[weaponCategory] or DEFAULT_WEAPON_SOUND

    -- Create 3D gunshot sound at the origin position with weapon-specific audio
    local sound = Instance.new("Sound")
    sound.SoundId = soundConfig.soundId
    sound.Volume = soundConfig.volume
    sound.PlaybackSpeed = soundConfig.playbackSpeed or 1.0
    sound.RollOffMode = Enum.RollOffMode.Linear
    sound.RollOffMaxDistance = soundConfig.maxDistance or 300
    sound.RollOffMinDistance = 20

    -- If shooter exists, parent to their character for accurate 3D audio
    if shooter and shooter.Character then
        local shooterRoot = shooter.Character:FindFirstChild("HumanoidRootPart")
        if shooterRoot then
            sound.Parent = shooterRoot
        else
            -- Fallback: create at origin position
            local soundPart = Instance.new("Part")
            soundPart.Anchored = true
            soundPart.CanCollide = false
            soundPart.Transparency = 1
            soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
            soundPart.Position = origin
            soundPart.Parent = workspace
            sound.Parent = soundPart
            -- Cleanup part after sound finishes
            sound.Ended:Connect(function()
                soundPart:Destroy()
            end)
        end
    else
        -- Fallback: create temporary part at origin
        local soundPart = Instance.new("Part")
        soundPart.Anchored = true
        soundPart.CanCollide = false
        soundPart.Transparency = 1
        soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
        soundPart.Position = origin
        soundPart.Parent = workspace
        sound.Parent = soundPart
        sound.Ended:Connect(function()
            soundPart:Destroy()
        end)
    end

    sound:Play()

    -- Cleanup sound after playing (if parented to character)
    if sound.Parent and sound.Parent:IsA("BasePart") and sound.Parent.Name == "HumanoidRootPart" then
        sound.Ended:Connect(function()
            sound:Destroy()
        end)
    end

    -- Create muzzle flash effect for other players
    if shooter and shooter.Character then
        local weaponModel = shooter.Character:FindFirstChild("EquippedWeaponModel")
        local flashPosition = origin
        if weaponModel and weaponModel.PrimaryPart then
            flashPosition = weaponModel.PrimaryPart.Position
        end

        local flash = Instance.new("Part")
        flash.Name = "MuzzleFlash"
        flash.Size = Vector3.new(0.4, 0.4, 0.4)
        flash.Anchored = true
        flash.CanCollide = false
        flash.Transparency = 0.4
        flash.Material = Enum.Material.Neon
        flash.Color = Color3.fromRGB(255, 200, 50)
        flash.CastShadow = false
        flash.Position = flashPosition
        flash.Parent = workspace

        -- Add light
        local light = Instance.new("PointLight")
        light.Color = Color3.fromRGB(255, 200, 100)
        light.Brightness = 3
        light.Range = 10
        light.Parent = flash

        -- Remove quickly
        task.delay(0.04, function()
            if flash and flash.Parent then
                flash:Destroy()
            end
        end)
    end
end)

-- Damage dealt feedback - shows hit marker when our shots connect
Remotes.OnEvent("DamageDealt", function(data)
    if type(data) ~= "table" then return end

    local damage = data.damage or 0
    local isHeadshot = data.isHeadshot or false

    -- Show hit marker on crosshair
    hud:ShowHitMarker(isHeadshot)

    -- Play hit confirmation sound (different sound for headshot vs normal hit)
    local hitSound = Instance.new("Sound")
    if isHeadshot then
        -- Headshot: higher pitch "ding" sound for satisfying feedback
        hitSound.SoundId = "rbxassetid://160432334"  -- Hit marker ding (verified working)
        hitSound.Volume = 0.7
        hitSound.PlaybackSpeed = 1.3  -- Slightly higher pitch for headshot
    else
        -- Normal hit: standard hit marker sound
        hitSound.SoundId = "rbxassetid://160432334"  -- Hit marker sound (verified working)
        hitSound.Volume = 0.5
        hitSound.PlaybackSpeed = 1.0
    end
    hitSound.Parent = workspace.CurrentCamera
    hitSound:Play()
    hitSound.Ended:Connect(function()
        hitSound:Destroy()
    end)
end)

-- Bullet hit effect
Remotes.OnEvent("BulletHit", function(position, surfaceType)
    -- Spawn impact effect at position
end)

-- Explosion effect - create visual explosion and screen shake
Remotes.OnEvent("ExplosionEffect", function(data)
    if type(data) ~= "table" then return end

    local position = data.position
    local radius = data.radius or 10
    local source = data.source  -- "grenade", "rocket", "c4", etc.

    if not position then return end

    -- Calculate distance from player for screen shake intensity
    local character = player.Character
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local distance = (rootPart.Position - position).Magnitude
            local maxShakeDistance = radius * 3  -- Shake felt within 3x explosion radius

            if distance < maxShakeDistance then
                -- Intensity decreases with distance
                local distanceFactor = 1 - (distance / maxShakeDistance)
                local baseIntensity = source == "rocket" and 1.2 or (source == "c4" and 1.5 or 0.8)
                local shakeIntensity = baseIntensity * distanceFactor
                local shakeDuration = 0.3 + (0.2 * distanceFactor)  -- Longer shake when closer

                addScreenShake(shakeIntensity, shakeDuration)
            end
        end
    end

    -- Create visual explosion effect
    local explosion = Instance.new("Part")
    explosion.Name = "ExplosionVisual"
    explosion.Shape = Enum.PartType.Ball
    explosion.Size = Vector3.new(1, 1, 1)
    explosion.Position = position
    explosion.Anchored = true
    explosion.CanCollide = false
    explosion.Transparency = 0.3
    explosion.Material = Enum.Material.Neon
    explosion.Color = Color3.fromRGB(255, 150, 50)  -- Orange
    explosion.CastShadow = false
    explosion.Parent = workspace

    -- Add bright light
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 200, 100)
    light.Brightness = 10
    light.Range = radius * 2
    light.Parent = explosion

    -- Animate expansion and fade
    local tweenService = game:GetService("TweenService")
    local expandTween = tweenService:Create(explosion,
        TweenInfo.new(0.3, Enum.EasingStyle.Expo, Enum.EasingDirection.Out),
        {Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1}
    )
    local lightTween = tweenService:Create(light,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Brightness = 0}
    )

    expandTween:Play()
    lightTween:Play()

    -- Cleanup after animation
    expandTween.Completed:Connect(function()
        explosion:Destroy()
    end)

    -- Play explosion sound (3D positioned)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://5801257793"  -- Explosion sound (verified working)
    sound.Volume = 1.0
    sound.RollOffMode = Enum.RollOffMode.Linear
    sound.RollOffMaxDistance = 500
    sound.RollOffMinDistance = 30

    -- Create temporary part for 3D sound positioning
    local soundPart = Instance.new("Part")
    soundPart.Anchored = true
    soundPart.CanCollide = false
    soundPart.Transparency = 1
    soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
    soundPart.Position = position
    soundPart.Parent = workspace
    sound.Parent = soundPart
    sound:Play()
    sound.Ended:Connect(function()
        soundPart:Destroy()
    end)
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
-- INVENTORY EVENT HANDLERS
-- Handle weapon and item updates from server
--=============================================================================

-- Inventory update from server - sync weapons, ammo, etc.
Remotes.OnEvent("InventoryUpdate", function(data)
    if data then
        clientState.inventory = data
        -- Update HUD weapon slots if method exists (server sends 'slots')
        if data.slots and hud.UpdateWeaponSlots then
            hud:UpdateWeaponSlots(data.slots)
        end
        -- Server sends 'equipped' - sync to client state
        if data.equipped and data.equipped > 0 then
            clientState.selectedWeaponSlot = data.equipped
            hud:SelectWeaponSlot(data.equipped)
        end
        print(string.format("[DinoRoyale Client] Inventory updated - equipped slot: %d", data.equipped or 0))
    end
end)

-- Ammo update from server
Remotes.OnEvent("AmmoUpdate", function(ammoData)
    if ammoData then
        clientState.inventory.ammo = ammoData
        -- Update ammo display if method exists
        if hud.UpdateAmmoDisplay then
            hud:UpdateAmmoDisplay(ammoData)
        end
    end
end)

-- Weapon equip from server (another player equipped weapon - for animation sync)
Remotes.OnEvent("WeaponEquip", function(userId, slotIndex, weaponId)
    -- If this is for our player, update local state and play feedback
    if userId == player.UserId then
        clientState.selectedWeaponSlot = slotIndex
        hud:SelectWeaponSlot(slotIndex)

        -- Play weapon equip sound for feedback
        local character = player.Character
        if character then
            local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                local equipSound = Instance.new("Sound")
                equipSound.SoundId = "rbxassetid://169799883"  -- Weapon draw/equip sound
                equipSound.Volume = 0.6
                equipSound.Parent = humanoidRootPart
                equipSound:Play()
                equipSound.Ended:Connect(function()
                    equipSound:Destroy()
                end)
            end
        end

        -- Visual feedback: brief highlight on the equipped weapon slot
        hud:FlashWeaponSlot(slotIndex)
    end
    -- Could also update third-person weapon display for other players here
end)

--=============================================================================
-- SETTINGS STATE
-- Track current settings from HUD settings menu
--=============================================================================

local mouseSettings = {
    sensitivity = 1.0,
    adsMultiplier = 0.5,
    invertY = false,
    mouseLock = true,
    scrollWheelWeaponSwitch = true,
    autoFire = true,
}

-- Register for settings changes from HUD
hud:OnSettingsChanged(function(settingName, newValue)
    print(string.format("[DinoRoyale Client] Setting changed: %s = %s", settingName, tostring(newValue)))

    if settingName == "mouseSensitivity" then
        mouseSettings.sensitivity = newValue
    elseif settingName == "adsMouseMultiplier" then
        mouseSettings.adsMultiplier = newValue
    elseif settingName == "invertMouseY" then
        mouseSettings.invertY = newValue
    elseif settingName == "mouseLock" then
        mouseSettings.mouseLock = newValue
        -- Apply mouse lock setting immediately (unless settings menu is open)
        if not hud:IsSettingsMenuOpen() then
            if newValue then
                UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            else
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            end
        end
    elseif settingName == "scrollWheelWeaponSwitch" then
        mouseSettings.scrollWheelWeaponSwitch = newValue
    elseif settingName == "autoFire" then
        mouseSettings.autoFire = newValue
    end
end)

--=============================================================================
-- INPUT HANDLING
-- Process keyboard/mouse input for game controls
-- Input is validated client-side then sent to server for authorization
--=============================================================================

--[[
    Keyboard Controls:
    - 1-5: Select weapon slot
    - Tab: Toggle inventory screen
    - M: Toggle fullscreen map
    - ESC: Toggle settings menu
    - R: Reload weapon

    Note: gameProcessed=true means Roblox UI consumed the input
    (e.g., typing in chat) - we should ignore these inputs
]]
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Ignore inputs that were consumed by Roblox UI (chat, menus, etc.)
    if gameProcessed then return end

    -- ESC key - toggle settings menu
    if input.KeyCode == Enum.KeyCode.Escape then
        hud:ToggleSettingsMenu()
        return  -- Don't process other inputs when toggling settings
    end

    -- If settings menu is open, ignore gameplay inputs
    if hud:IsSettingsMenuOpen() then
        return
    end

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
local lastFireTime = 0
local FIRE_RATE_LIMIT = 0.1  -- Minimum time between shots (10 shots/sec max)

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

--=============================================================================
-- CAMERA RECOIL SYSTEM
-- Adds weapon kick/shake when firing for better game feel
--=============================================================================

-- Recoil state tracking
local recoilState = {
    current = CFrame.new(),       -- Current recoil offset
    target = CFrame.new(),        -- Target recoil to apply
    recovering = false,           -- Whether we're recovering from recoil
}

-- Recoil configuration per weapon category (matches GameConfig.Weapons)
local RECOIL_CONFIGS = {
    pistol = {vertical = 1.5, horizontal = 0.3, recovery = 8},
    smg = {vertical = 0.8, horizontal = 0.4, recovery = 12},
    assault_rifle = {vertical = 1.2, horizontal = 0.5, recovery = 10},
    shotgun = {vertical = 3.0, horizontal = 0.8, recovery = 6},
    sniper = {vertical = 4.0, horizontal = 0.2, recovery = 4},
    explosive = {vertical = 2.0, horizontal = 0.3, recovery = 5},
    melee = {vertical = 0, horizontal = 0, recovery = 0},  -- No recoil for melee
}

local DEFAULT_RECOIL = {vertical = 1.0, horizontal = 0.3, recovery = 10}

--=============================================================================
-- ADS RETICLE SYSTEM
-- Shows weapon-specific aiming reticles when aiming down sights (right-click)
-- Different weapon types show appropriate sight types:
-- - Iron sights for pistols/SMGs
-- - Red dot for assault rifles
-- - Crosshair scope for snipers
-- - Simple dot for shotguns
--=============================================================================

-- Crosshair/reticle vertical offset to avoid overlapping character in third-person view
-- 0.4 = 40% from top (10% above center), matching DinoHUD crosshair offset
local CROSSHAIR_VERTICAL_POSITION = 0.4

-- ADS reticle configuration per weapon category
-- Each entry defines the visual appearance of the sight when ADS
local ADS_RETICLE_CONFIGS = {
    pistol = {
        type = "iron_sights",
        fov = 55,                    -- Less zoom for pistols
        color = Color3.new(1, 1, 1), -- White
        size = 40,
        thickness = 2,
    },
    smg = {
        type = "red_dot",
        fov = 50,
        color = Color3.fromRGB(255, 50, 50),  -- Red dot
        size = 8,
        dotSize = 4,
    },
    assault_rifle = {
        type = "red_dot",
        fov = 50,
        color = Color3.fromRGB(255, 50, 50),  -- Red
        size = 60,
        dotSize = 6,
    },
    shotgun = {
        type = "circle_dot",
        fov = 55,                    -- Less zoom for shotgun
        color = Color3.new(1, 1, 1), -- White
        size = 80,                   -- Larger spread indicator
        dotSize = 6,
    },
    sniper = {
        type = "scope",
        fov = 30,                    -- High zoom for snipers
        color = Color3.new(0, 0, 0), -- Black crosshairs
        size = 400,                  -- Full scope overlay
        thickness = 2,
    },
    explosive = {
        type = "crosshair",
        fov = 55,
        color = Color3.fromRGB(255, 200, 50),  -- Orange/yellow
        size = 80,
        thickness = 3,
    },
    melee = {
        type = "none",               -- No ADS for melee
        fov = 70,
    },
}

local DEFAULT_ADS_CONFIG = {
    type = "red_dot",
    fov = 50,
    color = Color3.fromRGB(255, 50, 50),
    size = 60,
    dotSize = 6,
}

-- ADS reticle UI elements (created once, shown/hidden as needed)
local adsReticleGui = nil
local adsReticleFrame = nil
local currentReticleElements = {}

--[[
    Create the ADS reticle ScreenGui and container
    Called once during initialization
]]
local function createADSReticleGui()
    -- Create ScreenGui for ADS reticle (separate from HUD for layering)
    adsReticleGui = Instance.new("ScreenGui")
    adsReticleGui.Name = "ADSReticle"
    adsReticleGui.ResetOnSpawn = false
    adsReticleGui.IgnoreGuiInset = true  -- Cover entire screen
    adsReticleGui.DisplayOrder = 100     -- Above HUD
    adsReticleGui.Enabled = false        -- Hidden by default
    adsReticleGui.Parent = player:WaitForChild("PlayerGui")

    -- Container frame centered on screen
    adsReticleFrame = Instance.new("Frame")
    adsReticleFrame.Name = "ReticleContainer"
    adsReticleFrame.Size = UDim2.new(1, 0, 1, 0)
    adsReticleFrame.Position = UDim2.new(0, 0, 0, 0)
    adsReticleFrame.BackgroundTransparency = 1
    adsReticleFrame.Parent = adsReticleGui

    print("[DinoRoyale Client] ADS Reticle GUI created")
end

--[[
    Clear all current reticle elements from the GUI
]]
local function clearReticleElements()
    for _, element in ipairs(currentReticleElements) do
        if element and element.Parent then
            element:Destroy()
        end
    end
    currentReticleElements = {}
end

--[[
    Create iron sights reticle (pistol style)
    Simple front post with rear notch outline
]]
local function createIronSightsReticle(config)
    -- Front sight post (vertical line at center)
    local frontPost = Instance.new("Frame")
    frontPost.Name = "FrontPost"
    frontPost.Size = UDim2.new(0, config.thickness, 0, config.size / 2)
    frontPost.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, -config.size / 4)
    frontPost.AnchorPoint = Vector2.new(0.5, 0.5)
    frontPost.BackgroundColor3 = config.color
    frontPost.BorderSizePixel = 0
    frontPost.Parent = adsReticleFrame
    table.insert(currentReticleElements, frontPost)

    -- Rear sight notch (U-shaped opening)
    local notchLeft = Instance.new("Frame")
    notchLeft.Name = "NotchLeft"
    notchLeft.Size = UDim2.new(0, config.thickness, 0, config.size / 3)
    notchLeft.Position = UDim2.new(0.5, -config.size / 3, CROSSHAIR_VERTICAL_POSITION, 0)
    notchLeft.AnchorPoint = Vector2.new(0.5, 0.5)
    notchLeft.BackgroundColor3 = config.color
    notchLeft.BorderSizePixel = 0
    notchLeft.Parent = adsReticleFrame
    table.insert(currentReticleElements, notchLeft)

    local notchRight = Instance.new("Frame")
    notchRight.Name = "NotchRight"
    notchRight.Size = UDim2.new(0, config.thickness, 0, config.size / 3)
    notchRight.Position = UDim2.new(0.5, config.size / 3, CROSSHAIR_VERTICAL_POSITION, 0)
    notchRight.AnchorPoint = Vector2.new(0.5, 0.5)
    notchRight.BackgroundColor3 = config.color
    notchRight.BorderSizePixel = 0
    notchRight.Parent = adsReticleFrame
    table.insert(currentReticleElements, notchRight)
end

--[[
    Create red dot reticle (SMG/AR style)
    Circle housing with illuminated center dot
]]
local function createRedDotReticle(config)
    -- Outer circle (sight housing)
    local housing = Instance.new("Frame")
    housing.Name = "Housing"
    housing.Size = UDim2.new(0, config.size, 0, config.size)
    housing.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, 0)
    housing.AnchorPoint = Vector2.new(0.5, 0.5)
    housing.BackgroundTransparency = 1
    housing.Parent = adsReticleFrame
    table.insert(currentReticleElements, housing)

    -- Circle outline using UICorner and UIStroke
    local housingCorner = Instance.new("UICorner")
    housingCorner.CornerRadius = UDim.new(0.5, 0)
    housingCorner.Parent = housing

    local housingStroke = Instance.new("UIStroke")
    housingStroke.Color = Color3.new(0.2, 0.2, 0.2)
    housingStroke.Thickness = 2
    housingStroke.Transparency = 0.3
    housingStroke.Parent = housing

    -- Center red dot
    local dot = Instance.new("Frame")
    dot.Name = "RedDot"
    dot.Size = UDim2.new(0, config.dotSize, 0, config.dotSize)
    dot.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, 0)
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.BackgroundColor3 = config.color
    dot.BorderSizePixel = 0
    dot.Parent = adsReticleFrame
    table.insert(currentReticleElements, dot)

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(0.5, 0)
    dotCorner.Parent = dot
end

--[[
    Create circle dot reticle (shotgun style)
    Shows spread pattern with center aiming point
]]
local function createCircleDotReticle(config)
    -- Outer spread indicator circle
    local spreadCircle = Instance.new("Frame")
    spreadCircle.Name = "SpreadCircle"
    spreadCircle.Size = UDim2.new(0, config.size, 0, config.size)
    spreadCircle.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, 0)
    spreadCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    spreadCircle.BackgroundTransparency = 1
    spreadCircle.Parent = adsReticleFrame
    table.insert(currentReticleElements, spreadCircle)

    local circleCorner = Instance.new("UICorner")
    circleCorner.CornerRadius = UDim.new(0.5, 0)
    circleCorner.Parent = spreadCircle

    local circleStroke = Instance.new("UIStroke")
    circleStroke.Color = config.color
    circleStroke.Thickness = 2
    circleStroke.Transparency = 0.3
    circleStroke.Parent = spreadCircle

    -- Center dot
    local dot = Instance.new("Frame")
    dot.Name = "CenterDot"
    dot.Size = UDim2.new(0, config.dotSize, 0, config.dotSize)
    dot.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, 0)
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.BackgroundColor3 = config.color
    dot.BorderSizePixel = 0
    dot.Parent = adsReticleFrame
    table.insert(currentReticleElements, dot)

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(0.5, 0)
    dotCorner.Parent = dot
end

--[[
    Create scope reticle (sniper style)
    Classic crosshair with scope vignette effect
]]
local function createScopeReticle(config)
    -- Scope vignette (dark edges)
    local vignette = Instance.new("Frame")
    vignette.Name = "ScopeVignette"
    vignette.Size = UDim2.new(1, 0, 1, 0)
    vignette.Position = UDim2.new(0, 0, 0, 0)
    vignette.BackgroundColor3 = Color3.new(0, 0, 0)
    vignette.BackgroundTransparency = 0
    vignette.BorderSizePixel = 0
    vignette.Parent = adsReticleFrame
    table.insert(currentReticleElements, vignette)

    -- Circular scope view (cut out from vignette)
    local scopeView = Instance.new("Frame")
    scopeView.Name = "ScopeView"
    scopeView.Size = UDim2.new(0, config.size, 0, config.size)
    scopeView.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, 0)
    scopeView.AnchorPoint = Vector2.new(0.5, 0.5)
    scopeView.BackgroundTransparency = 1
    scopeView.ClipsDescendants = true
    scopeView.Parent = adsReticleFrame
    table.insert(currentReticleElements, scopeView)

    -- Make vignette have a circular hole using separate corner pieces
    -- Adjusted for offset crosshair position (CROSSHAIR_VERTICAL_POSITION = 0.4)
    -- Top left corner block
    local tlBlock = Instance.new("Frame")
    tlBlock.Size = UDim2.new(0.5, -config.size/2, CROSSHAIR_VERTICAL_POSITION, -config.size/2)
    tlBlock.Position = UDim2.new(0, 0, 0, 0)
    tlBlock.BackgroundColor3 = Color3.new(0, 0, 0)
    tlBlock.BorderSizePixel = 0
    tlBlock.Parent = vignette

    -- Top right corner block
    local trBlock = Instance.new("Frame")
    trBlock.Size = UDim2.new(0.5, -config.size/2, CROSSHAIR_VERTICAL_POSITION, -config.size/2)
    trBlock.Position = UDim2.new(0.5, config.size/2, 0, 0)
    trBlock.BackgroundColor3 = Color3.new(0, 0, 0)
    trBlock.BorderSizePixel = 0
    trBlock.Parent = vignette

    -- Bottom left corner block
    local blBlock = Instance.new("Frame")
    blBlock.Size = UDim2.new(0.5, -config.size/2, 1 - CROSSHAIR_VERTICAL_POSITION, -config.size/2)
    blBlock.Position = UDim2.new(0, 0, CROSSHAIR_VERTICAL_POSITION, config.size/2)
    blBlock.BackgroundColor3 = Color3.new(0, 0, 0)
    blBlock.BorderSizePixel = 0
    blBlock.Parent = vignette

    -- Bottom right corner block
    local brBlock = Instance.new("Frame")
    brBlock.Size = UDim2.new(0.5, -config.size/2, 1 - CROSSHAIR_VERTICAL_POSITION, -config.size/2)
    brBlock.Position = UDim2.new(0.5, config.size/2, CROSSHAIR_VERTICAL_POSITION, config.size/2)
    brBlock.BackgroundColor3 = Color3.new(0, 0, 0)
    brBlock.BorderSizePixel = 0
    brBlock.Parent = vignette

    -- Make vignette mostly transparent except edges
    vignette.BackgroundTransparency = 1

    -- Scope ring
    local scopeRing = Instance.new("Frame")
    scopeRing.Name = "ScopeRing"
    scopeRing.Size = UDim2.new(0, config.size, 0, config.size)
    scopeRing.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, 0)
    scopeRing.AnchorPoint = Vector2.new(0.5, 0.5)
    scopeRing.BackgroundTransparency = 1
    scopeRing.Parent = adsReticleFrame
    table.insert(currentReticleElements, scopeRing)

    local ringCorner = Instance.new("UICorner")
    ringCorner.CornerRadius = UDim.new(0.5, 0)
    ringCorner.Parent = scopeRing

    local ringStroke = Instance.new("UIStroke")
    ringStroke.Color = Color3.new(0.1, 0.1, 0.1)
    ringStroke.Thickness = 4
    ringStroke.Parent = scopeRing

    -- Crosshair lines
    local lineLength = config.size / 3

    -- Vertical line (top)
    local topLine = Instance.new("Frame")
    topLine.Size = UDim2.new(0, config.thickness, 0, lineLength)
    topLine.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, -config.size/4)
    topLine.AnchorPoint = Vector2.new(0.5, 1)
    topLine.BackgroundColor3 = config.color
    topLine.BorderSizePixel = 0
    topLine.Parent = adsReticleFrame
    table.insert(currentReticleElements, topLine)

    -- Vertical line (bottom)
    local bottomLine = Instance.new("Frame")
    bottomLine.Size = UDim2.new(0, config.thickness, 0, lineLength)
    bottomLine.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, config.size/4)
    bottomLine.AnchorPoint = Vector2.new(0.5, 0)
    bottomLine.BackgroundColor3 = config.color
    bottomLine.BorderSizePixel = 0
    bottomLine.Parent = adsReticleFrame
    table.insert(currentReticleElements, bottomLine)

    -- Horizontal line (left)
    local leftLine = Instance.new("Frame")
    leftLine.Size = UDim2.new(0, lineLength, 0, config.thickness)
    leftLine.Position = UDim2.new(0.5, -config.size/4, CROSSHAIR_VERTICAL_POSITION, 0)
    leftLine.AnchorPoint = Vector2.new(1, 0.5)
    leftLine.BackgroundColor3 = config.color
    leftLine.BorderSizePixel = 0
    leftLine.Parent = adsReticleFrame
    table.insert(currentReticleElements, leftLine)

    -- Horizontal line (right)
    local rightLine = Instance.new("Frame")
    rightLine.Size = UDim2.new(0, lineLength, 0, config.thickness)
    rightLine.Position = UDim2.new(0.5, config.size/4, CROSSHAIR_VERTICAL_POSITION, 0)
    rightLine.AnchorPoint = Vector2.new(0, 0.5)
    rightLine.BackgroundColor3 = config.color
    rightLine.BorderSizePixel = 0
    rightLine.Parent = adsReticleFrame
    table.insert(currentReticleElements, rightLine)

    -- Center dot (small)
    local centerDot = Instance.new("Frame")
    centerDot.Name = "CenterDot"
    centerDot.Size = UDim2.new(0, 4, 0, 4)
    centerDot.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, 0)
    centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
    centerDot.BackgroundColor3 = Color3.fromRGB(255, 0, 0)  -- Red center dot
    centerDot.BorderSizePixel = 0
    centerDot.Parent = adsReticleFrame
    table.insert(currentReticleElements, centerDot)

    local centerCorner = Instance.new("UICorner")
    centerCorner.CornerRadius = UDim.new(0.5, 0)
    centerCorner.Parent = centerDot
end

--[[
    Create simple crosshair reticle (explosive launcher style)
]]
local function createCrosshairReticle(config)
    local halfSize = config.size / 2
    local gap = 10  -- Gap around center

    -- Top line
    local topLine = Instance.new("Frame")
    topLine.Size = UDim2.new(0, config.thickness, 0, halfSize - gap)
    topLine.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, -halfSize)
    topLine.AnchorPoint = Vector2.new(0.5, 0)
    topLine.BackgroundColor3 = config.color
    topLine.BorderSizePixel = 0
    topLine.Parent = adsReticleFrame
    table.insert(currentReticleElements, topLine)

    -- Bottom line
    local bottomLine = Instance.new("Frame")
    bottomLine.Size = UDim2.new(0, config.thickness, 0, halfSize - gap)
    bottomLine.Position = UDim2.new(0.5, 0, CROSSHAIR_VERTICAL_POSITION, gap)
    bottomLine.AnchorPoint = Vector2.new(0.5, 0)
    bottomLine.BackgroundColor3 = config.color
    bottomLine.BorderSizePixel = 0
    bottomLine.Parent = adsReticleFrame
    table.insert(currentReticleElements, bottomLine)

    -- Left line
    local leftLine = Instance.new("Frame")
    leftLine.Size = UDim2.new(0, halfSize - gap, 0, config.thickness)
    leftLine.Position = UDim2.new(0.5, -halfSize, CROSSHAIR_VERTICAL_POSITION, 0)
    leftLine.AnchorPoint = Vector2.new(0, 0.5)
    leftLine.BackgroundColor3 = config.color
    leftLine.BorderSizePixel = 0
    leftLine.Parent = adsReticleFrame
    table.insert(currentReticleElements, leftLine)

    -- Right line
    local rightLine = Instance.new("Frame")
    rightLine.Size = UDim2.new(0, halfSize - gap, 0, config.thickness)
    rightLine.Position = UDim2.new(0.5, gap, CROSSHAIR_VERTICAL_POSITION, 0)
    rightLine.AnchorPoint = Vector2.new(0, 0.5)
    rightLine.BackgroundColor3 = config.color
    rightLine.BorderSizePixel = 0
    rightLine.Parent = adsReticleFrame
    table.insert(currentReticleElements, rightLine)
end

--[[
    Show the appropriate ADS reticle for the current weapon
    @param weaponCategory string - The weapon category to show reticle for
]]
local function showADSReticle(weaponCategory)
    if not adsReticleGui then
        createADSReticleGui()
    end

    -- Clear any existing reticle
    clearReticleElements()

    -- Get config for this weapon type
    local config = ADS_RETICLE_CONFIGS[weaponCategory] or DEFAULT_ADS_CONFIG

    -- Skip if weapon has no ADS reticle (melee)
    if config.type == "none" then
        return
    end

    -- Create appropriate reticle based on type
    if config.type == "iron_sights" then
        createIronSightsReticle(config)
    elseif config.type == "red_dot" then
        createRedDotReticle(config)
    elseif config.type == "circle_dot" then
        createCircleDotReticle(config)
    elseif config.type == "scope" then
        createScopeReticle(config)
    elseif config.type == "crosshair" then
        createCrosshairReticle(config)
    end

    -- Show the reticle GUI
    adsReticleGui.Enabled = true

    -- Hide the regular crosshair when ADS
    if hud and hud.SetCrosshairVisible then
        hud:SetCrosshairVisible(false)
    end
end

--[[
    Hide the ADS reticle and restore normal crosshair
]]
local function hideADSReticle()
    if adsReticleGui then
        adsReticleGui.Enabled = false
    end

    -- Show the regular crosshair again
    if hud and hud.SetCrosshairVisible then
        hud:SetCrosshairVisible(true)
    end
end

--[[
    Get the current weapon category from inventory
    @return string - The weapon category of the currently equipped weapon
]]
local function getCurrentWeaponCategory()
    if clientState.inventory then
        local slots = clientState.inventory.slots or clientState.inventory.weapons
        if slots then
            local slot = slots[clientState.selectedWeaponSlot]
            if slot and slot.category then
                return slot.category
            end
        end
    end
    return "assault_rifle"  -- Default fallback
end

-- Initialize ADS reticle GUI when script loads
createADSReticleGui()

--[[
    Apply camera recoil when firing
    Creates a brief upward kick that recovers smoothly

    @param weaponCategory string - Weapon category for recoil lookup (optional)
]]
local function applyCameraRecoil(weaponCategory)
    local camera = workspace.CurrentCamera
    if not camera then return end

    -- Get recoil config for weapon type
    local config = RECOIL_CONFIGS[weaponCategory] or DEFAULT_RECOIL

    -- Skip if no recoil (melee weapons)
    if config.vertical == 0 and config.horizontal == 0 then
        return
    end

    -- Calculate recoil angles (in degrees)
    -- Vertical is always upward, horizontal is random left/right
    local verticalKick = math.rad(config.vertical * (0.8 + math.random() * 0.4))  -- 80-120% of base
    local horizontalKick = math.rad(config.horizontal * (math.random() * 2 - 1))   -- Random -100% to +100%

    -- Apply recoil as rotation offset
    local recoilRotation = CFrame.Angles(-verticalKick, horizontalKick, 0)

    -- Add to current recoil target
    recoilState.target = recoilState.target * recoilRotation
    recoilState.recovering = false
end

--[[
    Update camera recoil each frame
    Smoothly applies and recovers from recoil
]]
local function updateCameraRecoil(deltaTime)
    local camera = workspace.CurrentCamera
    if not camera then return end

    -- Smooth interpolation towards target recoil
    local lerpSpeed = 15 * deltaTime
    recoilState.current = recoilState.current:Lerp(recoilState.target, math.min(1, lerpSpeed))

    -- If not recovering and no recent shots, start recovering
    if not recoilState.recovering then
        -- Check if we're close to target (apply it)
        local diff = (recoilState.current.Position - recoilState.target.Position).Magnitude
        if diff < 0.001 then
            recoilState.recovering = true
        end
    end

    -- Recover towards identity (no recoil)
    if recoilState.recovering then
        local recoverySpeed = 10 * deltaTime
        recoilState.target = recoilState.target:Lerp(CFrame.new(), math.min(1, recoverySpeed))
        recoilState.current = recoilState.current:Lerp(CFrame.new(), math.min(1, recoverySpeed))
    end
end

-- Connect recoil update to render step for smooth animation
RunService.RenderStepped:Connect(function(deltaTime)
    updateCameraRecoil(deltaTime)

    -- Apply recoil offset to camera
    local camera = workspace.CurrentCamera
    if camera and recoilState.current ~= CFrame.new() then
        -- This works with Roblox's default camera by modifying CFrame
        -- The offset is applied after the camera controller runs
        camera.CFrame = camera.CFrame * recoilState.current
    end
end)

--[[
    Add screen shake effect (for explosions, large impacts)

    @param intensity number - Shake intensity (0.1 = subtle, 1.0 = strong)
    @param duration number - How long to shake (seconds)
]]
local function addScreenShake(intensity, duration)
    intensity = intensity or 0.5
    duration = duration or 0.2

    local camera = workspace.CurrentCamera
    if not camera then return end

    local startTime = tick()
    local shakeConnection

    shakeConnection = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        if elapsed >= duration then
            shakeConnection:Disconnect()
            return
        end

        -- Fade out shake over time
        local progress = elapsed / duration
        local currentIntensity = intensity * (1 - progress)

        -- Random offset
        local shakeX = (math.random() * 2 - 1) * currentIntensity
        local shakeY = (math.random() * 2 - 1) * currentIntensity

        camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(shakeX), math.rad(shakeY), 0)
    end)
end

--[[
    Create muzzle flash effect on character's weapon
    Shows a brief flash of light and particles at the weapon barrel
]]
local function createMuzzleFlash()
    local character = player.Character
    if not character then return end

    -- Find the weapon model on the character (server names it "EquippedWeaponModel")
    local weaponModel = character:FindFirstChild("EquippedWeaponModel")
    local flashPosition = nil

    if weaponModel then
        -- Get the primary part or first part of the weapon model
        local primaryPart = weaponModel.PrimaryPart or weaponModel:FindFirstChildWhichIsA("BasePart")
        if primaryPart then
            -- Position flash at the front/barrel of the weapon
            local camera = workspace.CurrentCamera
            if camera then
                local lookVector = camera.CFrame.LookVector
                flashPosition = primaryPart.Position + lookVector * 1.5
            else
                flashPosition = primaryPart.Position + primaryPart.CFrame.LookVector * 1.5
            end
        end
    end

    -- Fallback: create flash at right hand position
    if not flashPosition then
        local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
        if rightHand then
            local camera = workspace.CurrentCamera
            if camera then
                flashPosition = rightHand.Position + camera.CFrame.LookVector * 1.5
            else
                flashPosition = rightHand.Position + Vector3.new(0, 0, -1.5)
            end
        else
            return
        end
    end

    -- Create flash part
    local flash = Instance.new("Part")
    flash.Name = "MuzzleFlash"
    flash.Size = Vector3.new(0.5, 0.5, 0.5)
    flash.Anchored = true
    flash.CanCollide = false
    flash.Transparency = 0.3
    flash.Material = Enum.Material.Neon
    flash.Color = Color3.fromRGB(255, 200, 50)  -- Orange-yellow
    flash.CastShadow = false
    flash.Position = flashPosition

    -- Add point light for flash effect
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 200, 100)
    light.Brightness = 5
    light.Range = 15
    light.Parent = flash

    flash.Parent = workspace

    -- Remove after brief moment
    task.delay(0.05, function()
        if flash and flash.Parent then
            flash:Destroy()
        end
    end)
end

--[[
    Play gunshot sound
    Creates a 3D sound at the character's position
]]
-- Weapon-specific sound configurations
-- Each category has distinct sounds for better game feel
-- Using verified working Roblox sound IDs
local WEAPON_SOUNDS = {
    pistol = {
        soundId = "rbxassetid://280667448",  -- Pistol shot (verified working)
        volume = 0.6,
        playbackSpeed = 1.2,  -- Higher pitch for pistol
        maxDistance = 150,
    },
    smg = {
        soundId = "rbxassetid://280667448",  -- SMG shot (verified working)
        volume = 0.5,
        playbackSpeed = 1.1,
        maxDistance = 120,
    },
    assault_rifle = {
        soundId = "rbxassetid://280667448",  -- Rifle shot (verified working)
        volume = 0.7,
        playbackSpeed = 1.0,
        maxDistance = 250,
    },
    shotgun = {
        soundId = "rbxassetid://280667448",  -- Shotgun blast (verified working)
        volume = 0.9,
        playbackSpeed = 0.7,  -- Lower pitch for deep boom
        maxDistance = 180,
    },
    sniper = {
        soundId = "rbxassetid://280667448",  -- Sniper crack (verified working)
        volume = 1.0,
        playbackSpeed = 0.85,  -- Slightly lower for powerful crack
        maxDistance = 400,  -- Heard from far away
    },
    explosive = {
        soundId = "rbxassetid://280667448",  -- Launcher thump (verified working)
        volume = 0.8,
        playbackSpeed = 0.5,  -- Very deep thump
        maxDistance = 300,
    },
    melee = {
        soundId = "rbxassetid://220834019",  -- Melee swing/hit (verified working)
        volume = 0.4,
        playbackSpeed = 1.3,
        maxDistance = 30,
    },
}

local DEFAULT_WEAPON_SOUND = {
    soundId = "rbxassetid://280667448",  -- Generic gun shot (verified working)
    volume = 0.8,
    playbackSpeed = 1.0,
    maxDistance = 200,
}

--[[
    Play gunshot sound with weapon-specific audio
    @param weaponCategory string - Optional weapon category for specific sound
]]
local function playGunshotSound(weaponCategory)
    local character = player.Character
    if not character then return end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    -- Get weapon-specific sound config
    local soundConfig = WEAPON_SOUNDS[weaponCategory] or DEFAULT_WEAPON_SOUND

    -- Create sound with category-specific settings
    local sound = Instance.new("Sound")
    sound.SoundId = soundConfig.soundId
    sound.Volume = soundConfig.volume
    sound.PlaybackSpeed = soundConfig.playbackSpeed or 1.0
    sound.RollOffMode = Enum.RollOffMode.Linear
    sound.RollOffMaxDistance = soundConfig.maxDistance or 200
    sound.RollOffMinDistance = 10
    sound.Parent = humanoidRootPart
    sound:Play()

    -- Cleanup after playing
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
end

-- Store original walk speed for ADS restoration
local originalWalkSpeed = 16

--[[
    Start aiming animation - adjusts character pose and camera
    Shows weapon-specific ADS reticle and adjusts FOV based on weapon type
    Reduces movement speed for steadier aim
]]
local function startAiming()
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    -- Check if we have a weapon equipped
    local hasWeapon = false
    if clientState.inventory then
        local slots = clientState.inventory.slots or clientState.inventory.weapons
        if slots then
            local slot = slots[clientState.selectedWeaponSlot]
            hasWeapon = slot and slot.id ~= nil
        end
    end

    if not hasWeapon then
        return  -- Can't aim without a weapon
    end

    -- Get current weapon category for FOV and reticle selection
    local weaponCategory = getCurrentWeaponCategory()
    local adsConfig = ADS_RETICLE_CONFIGS[weaponCategory] or DEFAULT_ADS_CONFIG

    -- Store and reduce walk speed while aiming (steadier aim)
    originalWalkSpeed = humanoid.WalkSpeed
    local adsSpeedMultiplier = 0.6  -- 60% of normal speed while ADS
    if weaponCategory == "sniper" then
        adsSpeedMultiplier = 0.4  -- Snipers move slower while ADS
    elseif weaponCategory == "shotgun" then
        adsSpeedMultiplier = 0.75  -- Shotguns barely slow down
    end
    humanoid.WalkSpeed = originalWalkSpeed * adsSpeedMultiplier

    -- Adjust camera FOV based on weapon type (snipers zoom more, shotguns less)
    local camera = workspace.CurrentCamera
    if camera then
        local TweenService = game:GetService("TweenService")
        local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local targetFOV = adsConfig.fov or 50
        local tween = TweenService:Create(camera, tweenInfo, {FieldOfView = targetFOV})
        tween:Play()
    end

    -- Show weapon-specific ADS reticle
    showADSReticle(weaponCategory)

    -- Update crosshair spread (for weapons that still show it)
    if hud and hud.SetCrosshairSpread then
        hud:SetCrosshairSpread(0.5)  -- Tighter crosshair when aiming
    end
end

--[[
    Stop aiming animation - returns to normal pose and camera
    Hides ADS reticle and restores normal crosshair
    Restores normal movement speed
]]
local function stopAiming()
    local character = player.Character
    if not character then return end

    -- Restore walk speed
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = originalWalkSpeed
    end

    -- Reset camera FOV to default
    local camera = workspace.CurrentCamera
    if camera then
        local TweenService = game:GetService("TweenService")
        local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tween = TweenService:Create(camera, tweenInfo, {FieldOfView = 70})
        tween:Play()
    end

    -- Hide ADS reticle and restore normal crosshair
    hideADSReticle()

    -- Reset crosshair spread
    if hud and hud.SetCrosshairSpread then
        hud:SetCrosshairSpread(1.0)  -- Normal crosshair
    end
end

--[[
    Fire the equipped weapon
    Sends fire request to server with aim direction
    Server will perform raycast for hit detection
]]
local function fireWeapon()
    -- Rate limit client-side firing
    local now = tick()
    if now - lastFireTime < FIRE_RATE_LIMIT then
        return  -- Too soon to fire again
    end
    lastFireTime = now

    if not clientState.isAlive then
        return
    end
    if clientState.gameState ~= "Match" and clientState.gameState ~= "Lobby" then
        return
    end

    -- Check if we have a weapon and ammo before firing
    local weaponCategory = "assault_rifle"  -- Default
    local hasAmmo = true
    local hasWeapon = false

    -- Check inventory - server sends 'slots' not 'weapons'
    if clientState.inventory then
        local slots = clientState.inventory.slots or clientState.inventory.weapons
        if slots then
            local slot = slots[clientState.selectedWeaponSlot]
            if slot and slot.id then
                hasWeapon = true
                if slot.category then
                    weaponCategory = slot.category
                end
                -- Check ammo - melee weapons don't need ammo
                if slot.category ~= "melee" and slot.currentAmmo ~= nil and slot.currentAmmo <= 0 then
                    hasAmmo = false
                end
            end
        end
    end

    -- No weapon in slot, can't fire
    if not hasWeapon then
        return
    end

    -- Don't fire visual/audio effects if out of ammo
    if not hasAmmo then
        -- Play empty click sound instead
        local character = player.Character
        if character then
            local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                local clickSound = Instance.new("Sound")
                clickSound.SoundId = "rbxassetid://132464034"  -- Empty gun click
                clickSound.Volume = 0.4
                clickSound.Parent = humanoidRootPart
                clickSound:Play()
                clickSound.Ended:Connect(function()
                    clickSound:Destroy()
                end)
            end
        end
        return
    end

    local origin, direction = getMouseRay()

    -- Send fire request to server
    local success, err = pcall(function()
        Remotes.FireServer("WeaponFire", {
            origin = origin,
            direction = direction,
            slotIndex = clientState.selectedWeaponSlot,
        })
    end)

    if success then
        -- Create immediate visual and audio feedback
        createMuzzleFlash()
        playGunshotSound(weaponCategory)  -- Pass category for weapon-specific sound

        -- Apply camera recoil based on weapon category
        applyCameraRecoil(weaponCategory)

        -- Apply weapon recoil/firing kick animation
        if _G.triggerWeaponFiringKick then
            _G.triggerWeaponFiringKick()
        end

        -- Create bullet tracer effect
        if _G.createBulletTracer then
            local character = player.Character
            local tracerOrigin = origin

            -- Try to get muzzle position from weapon model
            if character then
                local weaponModel = character:FindFirstChild("EquippedWeaponModel")
                if weaponModel then
                    local primaryPart = weaponModel.PrimaryPart or weaponModel:FindFirstChildWhichIsA("BasePart")
                    if primaryPart then
                        tracerOrigin = primaryPart.Position
                    end
                end
            end

            -- Perform client-side raycast to find tracer endpoint
            local raycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            if character then
                raycastParams.FilterDescendantsInstances = {character}
            end

            local maxRange = 500  -- Max tracer distance
            local rayResult = workspace:Raycast(origin, direction.Unit * maxRange, raycastParams)

            local tracerEnd
            local isHit = false
            if rayResult then
                tracerEnd = rayResult.Position
                isHit = true
            else
                tracerEnd = origin + direction.Unit * maxRange
            end

            _G.createBulletTracer(tracerOrigin, tracerEnd, isHit)
        end
    end
end

-- Handle mouse button down (start firing)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Ignore inputs consumed by Roblox UI (chat, menus, etc.)
    if gameProcessed then return end

    -- Don't process mouse input if settings menu is open
    if hud:IsSettingsMenuOpen() then return end

    -- Left mouse button - Fire weapon
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isMouseDown = true
        fireWeapon()

        -- Start continuous firing for automatic weapons (if auto-fire is enabled)
        if mouseSettings.autoFire and not fireConnection then
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
        startAiming()
        -- Notify server of aim state
        pcall(function()
            Remotes.FireServer("WeaponAim", true)
        end)
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
        stopAiming()
        -- Notify server of aim state
        pcall(function()
            Remotes.FireServer("WeaponAim", false)
        end)
    end
end)

-- NOTE: Mouse lock is now handled by TutorialSystem
-- Mouse starts UNLOCKED so tutorial buttons can be clicked
-- After tutorial completes, TutorialSystem will lock the mouse for gameplay
-- If no tutorial shown, the game state change will handle mouse lock
UserInputService.MouseBehavior = Enum.MouseBehavior.Default

-- Handle mouse scroll for weapon switching
UserInputService.InputChanged:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    -- Don't process if settings menu is open
    if hud:IsSettingsMenuOpen() then return end

    -- Only process scroll wheel if the setting is enabled
    if input.UserInputType == Enum.UserInputType.MouseWheel and mouseSettings.scrollWheelWeaponSwitch then
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
-- TOUCH CONTROLS INTEGRATION
-- Setup callbacks for mobile/touch input
--=============================================================================

if isTouchDevice then
    print("[DinoRoyale Client] Setting up touch control callbacks...")

    -- Movement callback - apply to character via Humanoid
    touchControls:SetMoveCallback(function(direction)
        local character = player.Character
        if not character then return end

        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid then return end

        -- Convert 2D touch direction to 3D movement
        -- direction.X = left/right, direction.Y = forward/back
        if direction.Magnitude > 0.1 then
            local camera = workspace.CurrentCamera
            if camera then
                local camCFrame = camera.CFrame
                -- Get camera-relative movement direction
                local moveDirection = camCFrame:VectorToWorldSpace(
                    Vector3.new(direction.X, 0, -direction.Y)
                )
                moveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit
                humanoid:Move(moveDirection)
            end
        else
            humanoid:Move(Vector3.new(0, 0, 0))
        end
    end)

    -- Fire callback - trigger weapon firing
    touchControls:SetFireCallback(function(isPressed)
        if isPressed then
            isMouseDown = true
            fireWeapon()

            -- Start continuous firing for automatic weapons
            if mouseSettings.autoFire and not fireConnection then
                fireConnection = RunService.Heartbeat:Connect(function()
                    if isMouseDown and clientState.isAlive then
                        fireWeapon()
                    end
                end)
            end
        else
            isMouseDown = false
            if fireConnection then
                fireConnection:Disconnect()
                fireConnection = nil
            end
        end
    end)

    -- Aim callback - toggle ADS
    touchControls:SetAimCallback(function(isPressed)
        if isPressed then
            isAiming = true
            startAiming()
            Remotes.FireServer("WeaponAim", true)
        else
            isAiming = false
            stopAiming()
            Remotes.FireServer("WeaponAim", false)
        end
    end)

    -- Reload callback
    touchControls:SetReloadCallback(function()
        Remotes.FireServer("WeaponReload")
    end)

    -- Jump callback
    touchControls:SetJumpCallback(function()
        local character = player.Character
        if not character then return end

        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.Jump = true
        end
    end)

    -- Weapon slot callback
    touchControls:SetWeaponSlotCallback(function(slot)
        clientState.selectedWeaponSlot = slot
        hud:SelectWeaponSlot(slot)
        touchControls:HighlightWeaponSlot(slot)
        Remotes.FireServer("WeaponEquip", slot)
    end)

    -- Disable mouse lock on touch devices (use touch aiming instead)
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default

    print("[DinoRoyale Client] Touch control callbacks configured")
end

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
-- WEAPON POSE SYSTEM
-- Adjusts weapon position based on movement state by modifying the weapon weld.
-- This approach works because Roblox's Animator doesn't control welds.
-- - Ready pose: Weapon raised, pointed forward (when stationary)
-- - Lowered pose: Weapon angled down (when running)
-- - Aiming pose: Weapon closer to camera (when ADS)
--=============================================================================

-- Weapon pose state
local weaponPoseState = {
    currentPose = "ready",
    targetPose = "ready",
    transitionAlpha = 1.0,
    baseWeldC0 = nil,           -- Original weld C0 from server
    firingKick = 0,             -- Recoil amount 0-1
}

-- Pose transition settings
local POSE_LERP_SPEED = 8
local FIRING_KICK_RECOVERY = 12
local RUN_SPEED_THRESHOLD = 10

-- Weapon position offsets relative to hand (applied to weld C0)
-- Base position is set by server, these are additional offsets
local WEAPON_POSES = {
    -- Ready: Weapon forward, slightly raised
    ready = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(0), 0, 0),
    -- Lowered: Weapon angled down while running
    lowered = CFrame.new(0, 0.2, 0.3) * CFrame.Angles(math.rad(35), math.rad(15), 0),
    -- Aiming: Weapon pulled in tighter
    aiming = CFrame.new(0, -0.1, -0.2) * CFrame.Angles(math.rad(-5), 0, 0),
}

-- Firing kick offset
local FIRING_KICK_OFFSET = CFrame.Angles(math.rad(-15), 0, 0)

--[[
    Get the weapon weld from the equipped weapon model
    @return Weld|nil
]]
local function getWeaponWeld()
    local character = player.Character
    if not character then return nil end

    local weaponModel = character:FindFirstChild("EquippedWeaponModel")
    if not weaponModel then return nil end

    -- Find the weld (it's parented to the primary part)
    for _, child in ipairs(weaponModel:GetDescendants()) do
        if child:IsA("Weld") or child:IsA("Motor6D") then
            return child
        end
    end
    return nil
end

--[[
    Determine target pose based on state
]]
local function determineWeaponPose()
    if isAiming then
        return "aiming"
    end

    local character = player.Character
    if not character then return "ready" end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return "ready" end

    local velocity = rootPart.AssemblyLinearVelocity
    local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

    if speed > RUN_SPEED_THRESHOLD then
        return "lowered"
    end
    return "ready"
end

--[[
    Trigger weapon firing kick/recoil
]]
local function triggerFiringKick()
    weaponPoseState.firingKick = 1.0
end

_G.triggerWeaponFiringKick = triggerFiringKick

--[[
    Update weapon pose each frame
]]
local function updateWeaponPose(deltaTime)
    local weld = getWeaponWeld()
    if not weld then
        weaponPoseState.baseWeldC0 = nil
        return
    end

    -- Store base C0 if we haven't yet
    if not weaponPoseState.baseWeldC0 then
        weaponPoseState.baseWeldC0 = weld.C0
    end

    -- Determine target pose
    local newTarget = determineWeaponPose()
    if newTarget ~= weaponPoseState.targetPose then
        weaponPoseState.targetPose = newTarget
        weaponPoseState.transitionAlpha = 0
    end

    -- Lerp transition
    weaponPoseState.transitionAlpha = math.min(1,
        weaponPoseState.transitionAlpha + deltaTime * POSE_LERP_SPEED)

    -- Recover firing kick
    if weaponPoseState.firingKick > 0 then
        weaponPoseState.firingKick = math.max(0,
            weaponPoseState.firingKick - deltaTime * FIRING_KICK_RECOVERY)
    end

    -- Calculate final pose
    local poseOffset = WEAPON_POSES[weaponPoseState.targetPose] or WEAPON_POSES.ready

    -- Interpolate from current to target (smooth transition)
    local currentOffset = WEAPON_POSES[weaponPoseState.currentPose] or WEAPON_POSES.ready
    local lerpedOffset = currentOffset:Lerp(poseOffset, weaponPoseState.transitionAlpha)

    -- Add firing kick
    local kickOffset = CFrame.new():Lerp(FIRING_KICK_OFFSET, weaponPoseState.firingKick)

    -- Apply to weld
    weld.C0 = weaponPoseState.baseWeldC0 * lerpedOffset * kickOffset

    -- Update current pose when transition complete
    if weaponPoseState.transitionAlpha >= 1 then
        weaponPoseState.currentPose = weaponPoseState.targetPose
    end
end

--=============================================================================
-- UPPER BODY AIM SYSTEM
-- Rotates the character's upper body (torso, arms) to aim where the camera looks.
-- This makes the character visually aim at the target while moving independently.
--=============================================================================

local upperBodyAimState = {
    enabled = true,
    currentAimAngle = 0,     -- Current vertical aim angle (pitch)
    targetAimAngle = 0,      -- Target vertical aim angle
    waistMotor = nil,        -- Reference to waist Motor6D
    originalWaistC0 = nil,   -- Original waist C0 for reset
}

local AIM_LERP_SPEED = 15           -- How fast to follow aim direction
local AIM_PITCH_LIMIT = 60          -- Max degrees up/down
local AIM_MOVEMENT_REDUCTION = 0.3  -- Reduce aim when running (0-1)

--[[
    Setup upper body aiming for a character
    Stores reference to the waist motor for manipulation
]]
local function setupUpperBodyAim(character)
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    -- For R15 rigs, find the waist motor (connects LowerTorso to UpperTorso)
    local upperTorso = character:FindFirstChild("UpperTorso")
    local lowerTorso = character:FindFirstChild("LowerTorso")

    if upperTorso and lowerTorso then
        -- R15 rig - use Waist motor
        local waist = lowerTorso:FindFirstChild("Waist")
        if waist and waist:IsA("Motor6D") then
            upperBodyAimState.waistMotor = waist
            upperBodyAimState.originalWaistC0 = waist.C0
            return
        end
    end

    -- For R6 rigs, find the Torso
    local torso = character:FindFirstChild("Torso")
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    if torso and rootPart then
        -- R6 rig - check for RootJoint
        local rootJoint = rootPart:FindFirstChild("RootJoint")
        if rootJoint and rootJoint:IsA("Motor6D") then
            upperBodyAimState.waistMotor = rootJoint
            upperBodyAimState.originalWaistC0 = rootJoint.C0
        end
    end
end

--[[
    Update upper body aim each frame
    Rotates torso to follow camera pitch for aiming
]]
local function updateUpperBodyAim(deltaTime)
    if not upperBodyAimState.enabled then return end

    local character = player.Character
    if not character then return end

    local motor = upperBodyAimState.waistMotor
    if not motor or not upperBodyAimState.originalWaistC0 then
        -- Try to setup if not done yet
        setupUpperBodyAim(character)
        return
    end

    -- Check if we have a weapon equipped
    local hasWeapon = false
    if clientState.inventory then
        local slots = clientState.inventory.slots or clientState.inventory.weapons
        if slots then
            local slot = slots[clientState.selectedWeaponSlot]
            hasWeapon = slot and slot.id ~= nil
        end
    end

    -- Only aim if we have a weapon
    if not hasWeapon then
        -- Reset to original pose
        motor.C0 = upperBodyAimState.originalWaistC0
        upperBodyAimState.currentAimAngle = 0
        return
    end

    -- Get camera pitch angle
    local camera = workspace.CurrentCamera
    if not camera then return end

    local camLookVector = camera.CFrame.LookVector
    local pitch = math.asin(camLookVector.Y)  -- Vertical angle in radians
    local pitchDegrees = math.deg(pitch)

    -- Clamp pitch to limits
    pitchDegrees = math.clamp(pitchDegrees, -AIM_PITCH_LIMIT, AIM_PITCH_LIMIT)

    -- Reduce aim rotation when running (looks more natural)
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        local velocity = rootPart.AssemblyLinearVelocity
        local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        local runFactor = math.clamp(speed / 20, 0, 1)
        pitchDegrees = pitchDegrees * (1 - runFactor * AIM_MOVEMENT_REDUCTION)
    end

    upperBodyAimState.targetAimAngle = pitchDegrees

    -- Smooth interpolation
    local lerpSpeed = AIM_LERP_SPEED * deltaTime
    upperBodyAimState.currentAimAngle = upperBodyAimState.currentAimAngle +
        (upperBodyAimState.targetAimAngle - upperBodyAimState.currentAimAngle) * math.min(1, lerpSpeed)

    -- Apply rotation to waist motor
    -- Rotate around X axis (pitch) to tilt upper body
    local aimRotation = CFrame.Angles(math.rad(-upperBodyAimState.currentAimAngle), 0, 0)
    motor.C0 = upperBodyAimState.originalWaistC0 * aimRotation
end

-- Reset upper body aim when character respawns
local function resetUpperBodyAim()
    upperBodyAimState.waistMotor = nil
    upperBodyAimState.originalWaistC0 = nil
    upperBodyAimState.currentAimAngle = 0
    upperBodyAimState.targetAimAngle = 0
end

-- Start weapon pose update loop (combined with upper body aim)
RunService.RenderStepped:Connect(function(deltaTime)
    updateWeaponPose(deltaTime)
    updateUpperBodyAim(deltaTime)
end)

-- Setup upper body aim when character spawns
player.CharacterAdded:Connect(function(character)
    -- Wait for character to fully load
    character:WaitForChild("Humanoid")
    task.wait(0.1)
    setupUpperBodyAim(character)
end)

-- Setup for existing character
if player.Character then
    task.spawn(function()
        task.wait(0.1)
        setupUpperBodyAim(player.Character)
    end)
end

--=============================================================================
-- BULLET TRACER SYSTEM
-- Creates visual bullet trails from muzzle to impact point
-- Uses Beam objects for smooth, performant tracers
--=============================================================================

local TRACER_LIFETIME = 0.1      -- How long tracer is visible (seconds)
local TRACER_WIDTH = 0.08        -- Tracer beam width (studs)
local TRACER_COLOR = Color3.fromRGB(255, 220, 150)  -- Warm bullet color

--[[
    Create a bullet tracer from origin to target position
    @param origin Vector3 - Start position (muzzle)
    @param target Vector3 - End position (hit point or max range)
    @param isHit boolean - Whether the shot hit something (affects visual)
]]
local function createBulletTracer(origin, target, isHit)
    -- Create attachment points
    local attachment0 = Instance.new("Attachment")
    attachment0.WorldPosition = origin
    attachment0.Parent = workspace.Terrain

    local attachment1 = Instance.new("Attachment")
    attachment1.WorldPosition = target
    attachment1.Parent = workspace.Terrain

    -- Create the beam (tracer line)
    local beam = Instance.new("Beam")
    beam.Attachment0 = attachment0
    beam.Attachment1 = attachment1
    beam.Width0 = TRACER_WIDTH
    beam.Width1 = TRACER_WIDTH * 0.5  -- Taper at end
    beam.Color = ColorSequence.new(TRACER_COLOR)
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.8, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    beam.LightEmission = 0.8
    beam.LightInfluence = 0.2
    beam.FaceCamera = true
    beam.Segments = 1
    beam.Parent = workspace.Terrain

    -- Create impact effect if hit something
    if isHit then
        local impactPart = Instance.new("Part")
        impactPart.Name = "BulletImpact"
        impactPart.Size = Vector3.new(0.3, 0.3, 0.3)
        impactPart.Position = target
        impactPart.Anchored = true
        impactPart.CanCollide = false
        impactPart.Transparency = 0.5
        impactPart.Material = Enum.Material.Neon
        impactPart.Color = Color3.fromRGB(255, 200, 100)
        impactPart.CastShadow = false
        impactPart.Parent = workspace

        -- Spark particles
        local sparks = Instance.new("ParticleEmitter")
        sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 100))
        sparks.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.15),
            NumberSequenceKeypoint.new(1, 0),
        })
        sparks.Lifetime = NumberRange.new(0.1, 0.2)
        sparks.Rate = 0
        sparks.Speed = NumberRange.new(5, 15)
        sparks.SpreadAngle = Vector2.new(180, 180)
        sparks.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        })
        sparks.LightEmission = 1
        sparks.Parent = impactPart
        sparks:Emit(8)  -- Burst of sparks

        -- Cleanup impact
        task.delay(0.3, function()
            if impactPart and impactPart.Parent then
                impactPart:Destroy()
            end
        end)
    end

    -- Cleanup tracer
    task.delay(TRACER_LIFETIME, function()
        if beam and beam.Parent then beam:Destroy() end
        if attachment0 and attachment0.Parent then attachment0:Destroy() end
        if attachment1 and attachment1.Parent then attachment1:Destroy() end
    end)
end

-- Expose tracer function globally for fireWeapon to use
_G.createBulletTracer = createBulletTracer

-- Character respawn handler for weapon pose reset
player.CharacterAdded:Connect(function(character)
    weaponPoseState.baseWeldC0 = nil
    weaponPoseState.currentPose = "ready"
    weaponPoseState.targetPose = "ready"
    weaponPoseState.firingKick = 0
    resetUpperBodyAim()
end)

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
-- TUTORIAL SYSTEM
-- Onboarding for new players
--=============================================================================

local TutorialSystem = require(ReplicatedStorage:WaitForChild("Module"):WaitForChild("TutorialSystem"))
local tutorial = TutorialSystem:Initialize()

-- Show tutorial for new players when in lobby
-- The tutorial will check if player is new and display accordingly
task.spawn(function()
    -- Wait for game to stabilize
    task.wait(2)

    -- Only start tutorial if in lobby state
    if clientState.gameState == "Lobby" and TutorialSystem:IsNewPlayer() then
        TutorialSystem:StartTutorial()
    end
end)

-- Hook up tutorial hints to game events
Remotes.OnEvent("StormWarning", function(delay, phase)
    TutorialSystem:OnGameEvent("storm_warning")
end)

print("[DinoRoyale Client] Tutorial system initialized")

--=============================================================================
-- STARTUP COMPLETE
--=============================================================================

print("[DinoRoyale Client] ========================================")
print("[DinoRoyale Client] Client initialization complete!")
print(string.format("[DinoRoyale Client] Player: %s", player.Name))
print("[DinoRoyale Client] ========================================")

-- Client is now ready and listening for server events
-- All game logic is server-authoritative; client just displays state
