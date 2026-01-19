--[[
    StormService - Shrinking zone/storm system
    Handles: Zone progression, damage dealing, visual effects

    Features:
    - Configurable multi-phase storm
    - Dynamic center movement
    - Damage-over-time outside zone
    - Visual storm wall effects
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local StormService = {}
StormService.__index = StormService

-- Private state
local isActive = false
local currentPhase = 0
local currentRadius = 1000
local targetRadius = 1000
local currentCenter = Vector3.new(0, 0, 0)
local targetCenter = Vector3.new(0, 0, 0)
local stormPart = nil
local damageConnection = nil
local shrinkTween = nil
local gameConfig = nil
local framework = nil

-- Storm visual settings
local STORM_COLOR = Color3.fromRGB(75, 0, 130)  -- Deep purple
local STORM_TRANSPARENCY = 0.7
local STORM_HEIGHT = 500

--[[
    Initialize the StormService
]]
function StormService:Initialize()
    -- Rojo maps to ReplicatedStorage.Framework and ReplicatedStorage.Shared
    framework = require(script.Parent.Parent.Framework)
    gameConfig = require(script.Parent.Parent.Shared.GameConfig)

    -- Set initial radius from config
    currentRadius = gameConfig.Storm.visualRadius
    targetRadius = currentRadius

    -- Create storm visual
    self:CreateStormVisual()

    -- Setup remotes
    self:SetupRemotes()

    framework.Log("Info", "StormService initialized")
    return true
end

--[[
    Setup remote events
]]
function StormService:SetupRemotes()
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = "Remotes"
        remoteFolder.Parent = ReplicatedStorage
    end

    local stormRemotes = {
        "StormPhaseChanged",
        "StormPositionUpdate",
        "StormWarning",
    }

    for _, remoteName in ipairs(stormRemotes) do
        if not remoteFolder:FindFirstChild(remoteName) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = remoteName
            remote.Parent = remoteFolder
        end
    end
end

--[[
    Create the visual storm barrier
]]
function StormService:CreateStormVisual()
    -- Create a hollow cylinder for the storm wall
    stormPart = Instance.new("Part")
    stormPart.Name = "StormWall"
    stormPart.Anchored = true
    stormPart.CanCollide = false
    stormPart.CastShadow = false
    stormPart.Material = Enum.Material.ForceField
    stormPart.Color = STORM_COLOR
    stormPart.Transparency = STORM_TRANSPARENCY
    stormPart.Size = Vector3.new(currentRadius * 2, STORM_HEIGHT, currentRadius * 2)
    stormPart.Position = Vector3.new(currentCenter.X, STORM_HEIGHT / 2, currentCenter.Z)
    stormPart.Shape = Enum.PartType.Cylinder
    stormPart.Orientation = Vector3.new(0, 0, 90) -- Rotate to be vertical

    -- Create inner transparent part to make it hollow
    local innerPart = Instance.new("Part")
    innerPart.Name = "StormInner"
    innerPart.Anchored = true
    innerPart.CanCollide = false
    innerPart.CastShadow = false
    innerPart.Transparency = 1
    innerPart.Size = Vector3.new((currentRadius - 5) * 2, STORM_HEIGHT + 10, (currentRadius - 5) * 2)
    innerPart.Position = stormPart.Position
    innerPart.Shape = Enum.PartType.Cylinder
    innerPart.Orientation = Vector3.new(0, 0, 90)
    innerPart.Parent = stormPart

    -- Add particle effects
    local particles = Instance.new("ParticleEmitter")
    particles.Name = "StormParticles"
    particles.Color = ColorSequence.new(STORM_COLOR)
    particles.Transparency = NumberSequence.new(0.5, 1)
    particles.Size = NumberSequence.new(2, 5)
    particles.Lifetime = NumberRange.new(1, 3)
    particles.Rate = 50
    particles.Speed = NumberRange.new(10, 30)
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.Parent = stormPart

    -- Parent to workspace (initially hidden)
    stormPart.Parent = workspace
    stormPart.Transparency = 1

    framework.Log("Debug", "Storm visual created")
end

--[[
    Start the storm progression
    In test mode, storm is much slower and has a larger initial radius
]]
function StormService:StartStorm()
    if isActive then
        framework.Log("Warn", "Storm already active")
        return
    end

    isActive = true
    currentPhase = 0

    -- Reset to initial state - use larger radius in test mode
    local baseRadius = gameConfig.Storm.visualRadius
    if gameConfig.TestMode and gameConfig.TestMode.enabled then
        baseRadius = baseRadius * 1.5  -- 50% larger in test mode
        framework.Log("Info", "Storm: Test mode - using larger radius: %d", baseRadius)
    end
    currentRadius = baseRadius

    -- Get map center from MapService (instead of hardcoded 0,0,0)
    local mapCenter = Vector3.new(0, 0, 0)  -- Fallback
    local mapService = framework:GetService("MapService")
    if mapService and mapService.GetMapCenter then
        mapCenter = mapService:GetMapCenter()
        framework.Log("Debug", "Storm using map center from MapService: %s", tostring(mapCenter))
    end
    currentCenter = mapCenter

    -- Show storm visual
    stormPart.Transparency = STORM_TRANSPARENCY
    self:UpdateStormVisual()

    -- Start phase progression
    self:StartPhaseProgression()

    -- Start damage loop
    self:StartDamageLoop()

    framework.Log("Info", "Storm started")
end

--[[
    Start phase progression coroutine
]]
function StormService:StartPhaseProgression()
    task.spawn(function()
        local phases = gameConfig.Storm.phases

        for phaseIndex, phaseConfig in ipairs(phases) do
            if not isActive then break end

            currentPhase = phaseIndex

            -- Broadcast phase warning
            self:BroadcastWarning(phaseConfig.delay)

            -- Wait for delay
            local waitTime = phaseConfig.delay
            while waitTime > 0 and isActive do
                task.wait(1)
                waitTime = waitTime - 1

                -- Broadcast countdown if less than warning time
                if waitTime <= gameConfig.Storm.warningTime then
                    self:BroadcastCountdown(waitTime)
                end
            end

            if not isActive then break end

            -- Calculate new center (with offset)
            local offset = phaseConfig.centerOffset
            local offsetX = (math.random() - 0.5) * 2 * offset * currentRadius
            local offsetZ = (math.random() - 0.5) * 2 * offset * currentRadius
            targetCenter = Vector3.new(
                currentCenter.X + offsetX,
                currentCenter.Y,
                currentCenter.Z + offsetZ
            )
            targetRadius = phaseConfig.endRadius

            -- Start shrinking
            self:ShrinkToTarget(phaseConfig.shrinkTime)

            -- Broadcast phase change
            self:BroadcastPhaseChange(phaseIndex, phaseConfig)

            framework.Log("Info", "Storm phase %d started - shrinking to radius %d", phaseIndex, targetRadius)

            -- Wait for shrink to complete
            task.wait(phaseConfig.shrinkTime)
        end

        framework.Log("Info", "Storm progression complete")
    end)
end

--[[
    Shrink storm to target using TweenService
]]
function StormService:ShrinkToTarget(duration)
    -- Cancel existing tween
    if shrinkTween then
        shrinkTween:Cancel()
    end

    local tweenInfo = TweenInfo.new(
        duration,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.InOut
    )

    -- We need to tween our values manually since they're not Instance properties
    local startRadius = currentRadius
    local startCenter = currentCenter

    task.spawn(function()
        local startTime = tick()

        while tick() - startTime < duration and isActive do
            local alpha = (tick() - startTime) / duration
            alpha = math.clamp(alpha, 0, 1)

            -- Lerp radius and center
            currentRadius = startRadius + (targetRadius - startRadius) * alpha
            currentCenter = startCenter:Lerp(targetCenter, alpha)

            -- Update visual
            self:UpdateStormVisual()

            task.wait(0.05) -- Update 20 times per second
        end

        -- Snap to final values
        currentRadius = targetRadius
        currentCenter = targetCenter
        self:UpdateStormVisual()
    end)
end

--[[
    Update storm visual to match current state
]]
function StormService:UpdateStormVisual()
    if not stormPart then return end

    -- Update size (cylinder diameter = radius * 2)
    stormPart.Size = Vector3.new(STORM_HEIGHT, currentRadius * 2, currentRadius * 2)
    stormPart.Position = Vector3.new(currentCenter.X, STORM_HEIGHT / 2, currentCenter.Z)

    -- Update inner part
    local innerPart = stormPart:FindFirstChild("StormInner")
    if innerPart then
        innerPart.Size = Vector3.new(STORM_HEIGHT + 10, (currentRadius - 5) * 2, (currentRadius - 5) * 2)
        innerPart.Position = stormPart.Position
    end
end

--[[
    Start the damage loop for players outside the zone
]]
function StormService:StartDamageLoop()
    local damageInterval = gameConfig.Storm.damageInterval

    task.spawn(function()
        while isActive do
            self:ApplyStormDamage()
            task.wait(damageInterval)
        end
    end)
end

--[[
    Apply damage to players outside the safe zone
    Damage is reduced in test mode for easier exploration
]]
function StormService:ApplyStormDamage()
    local damage = self:GetCurrentDamage()
    if damage <= 0 then return end

    -- Reduce damage in test mode
    if gameConfig.TestMode and gameConfig.TestMode.enabled then
        damage = damage * 0.25  -- 25% damage in test mode for easier exploration
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if not character then continue end

        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChild("Humanoid")

        if humanoidRootPart and humanoid and humanoid.Health > 0 then
            -- Check distance from storm center
            local playerPos = humanoidRootPart.Position
            local distance = (Vector3.new(playerPos.X, 0, playerPos.Z) - Vector3.new(currentCenter.X, 0, currentCenter.Z)).Magnitude

            if distance > currentRadius then
                -- Player is outside the safe zone
                humanoid:TakeDamage(damage)

                -- Notify player they're taking storm damage
                self:NotifyStormDamage(player, damage)
            end
        end
    end
end

--[[
    Get current storm damage based on phase
]]
function StormService:GetCurrentDamage()
    if currentPhase == 0 or currentPhase > #gameConfig.Storm.phases then
        return 0
    end

    return gameConfig.Storm.phases[currentPhase].damage
end

--[[
    Notify player of storm damage
]]
function StormService:NotifyStormDamage(player, damage)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes and remotes:FindFirstChild("StormDamage") then
        remotes.StormDamage:FireClient(player, damage)
    end
end

--[[
    Broadcast storm warning
]]
function StormService:BroadcastWarning(delay)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.StormWarning:FireAllClients(delay, currentPhase + 1)
    end
end

--[[
    Broadcast countdown
]]
function StormService:BroadcastCountdown(seconds)
    -- This would update a client-side countdown display
end

--[[
    Broadcast phase change
]]
function StormService:BroadcastPhaseChange(phase, config)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.StormPhaseChanged:FireAllClients({
            phase = phase,
            targetRadius = config.endRadius,
            targetCenter = targetCenter,
            damage = config.damage,
        })
    end

    -- Also update the main game service
    remotes.UpdateStormPhase:FireAllClients(phase)
end

--[[
    Stop the storm
]]
function StormService:StopStorm()
    isActive = false

    -- Cancel any active tweens
    if shrinkTween then
        shrinkTween:Cancel()
        shrinkTween = nil
    end

    -- Hide storm visual
    if stormPart then
        stormPart.Transparency = 1
    end

    currentPhase = 0

    framework.Log("Info", "Storm stopped")
end

--[[
    Get current storm state (for UI/minimap)
]]
function StormService:GetState()
    return {
        isActive = isActive,
        phase = currentPhase,
        currentRadius = currentRadius,
        targetRadius = targetRadius,
        currentCenter = currentCenter,
        targetCenter = targetCenter,
        damage = self:GetCurrentDamage(),
    }
end

--[[
    Check if a position is inside the safe zone
]]
function StormService:IsInsideZone(position)
    local flatPos = Vector3.new(position.X, 0, position.Z)
    local flatCenter = Vector3.new(currentCenter.X, 0, currentCenter.Z)
    local distance = (flatPos - flatCenter).Magnitude

    return distance <= currentRadius
end

--[[
    Get distance to safe zone edge
]]
function StormService:GetDistanceToZone(position)
    local flatPos = Vector3.new(position.X, 0, position.Z)
    local flatCenter = Vector3.new(currentCenter.X, 0, currentCenter.Z)
    local distance = (flatPos - flatCenter).Magnitude

    return currentRadius - distance -- Positive = inside, Negative = outside
end

--[[
    Shutdown the service
]]
function StormService:Shutdown()
    self:StopStorm()

    if stormPart then
        stormPart:Destroy()
        stormPart = nil
    end

    framework.Log("Info", "StormService shut down")
end

return StormService
