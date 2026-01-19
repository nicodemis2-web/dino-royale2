--[[
    DinoHUD - User interface and heads-up display
    Adapted from Evostrike's EvoHUD

    Components:
    - Health/Shield bars
    - Weapon hotbar (5 slots)
    - Ammo counter
    - Minimap with storm indicator
    - Kill feed
    - Player count
    - Squad teammate status
    - Damage indicators
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local DinoHUD = {}
DinoHUD.__index = DinoHUD

-- Private state
local player = Players.LocalPlayer
local components = {}
local isEnabled = true
local framework = nil
local gameConfig = nil

-- UI References
local screenGui = nil
local hudFrame = nil

--[[
    Initialize the DinoHUD
]]
function DinoHUD:Initialize()
    framework = require(script.Parent.Parent.framework)
    gameConfig = require(script.Parent.Parent.src.shared.GameConfig)

    -- Create main ScreenGui
    self:CreateScreenGui()

    -- Create all HUD components
    self:CreateHealthBar()
    self:CreateWeaponHotbar()
    self:CreateMinimap()
    self:CreateKillFeed()
    self:CreatePlayerCount()
    self:CreateSquadStatus()
    self:CreateDamageIndicator()
    self:CreateStormWarning()

    -- Connect to remote events
    self:ConnectRemotes()

    -- Start update loop
    self:StartUpdateLoop()

    framework.Log("Info", "DinoHUD initialized")
    return self
end

--[[
    Create the main ScreenGui
]]
function DinoHUD:CreateScreenGui()
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DinoHUD"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = player:WaitForChild("PlayerGui")

    -- Main HUD frame
    hudFrame = Instance.new("Frame")
    hudFrame.Name = "HUDFrame"
    hudFrame.Size = UDim2.new(1, 0, 1, 0)
    hudFrame.BackgroundTransparency = 1
    hudFrame.Parent = screenGui

    components.screenGui = screenGui
    components.hudFrame = hudFrame
end

--[[
    Create health and shield bars
]]
function DinoHUD:CreateHealthBar()
    local container = Instance.new("Frame")
    container.Name = "HealthContainer"
    container.Size = UDim2.new(0, 300, 0, 60)
    container.Position = UDim2.new(0, 20, 1, -80)
    container.AnchorPoint = Vector2.new(0, 1)
    container.BackgroundTransparency = 1
    container.Parent = hudFrame

    -- Health bar background
    local healthBg = Instance.new("Frame")
    healthBg.Name = "HealthBg"
    healthBg.Size = UDim2.new(1, 0, 0, 25)
    healthBg.Position = UDim2.new(0, 0, 1, -25)
    healthBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    healthBg.BorderSizePixel = 0
    healthBg.Parent = container

    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(0, 4)
    healthCorner.Parent = healthBg

    -- Health bar fill
    local healthFill = Instance.new("Frame")
    healthFill.Name = "HealthFill"
    healthFill.Size = UDim2.new(1, -4, 1, -4)
    healthFill.Position = UDim2.new(0, 2, 0, 2)
    healthFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    healthFill.BorderSizePixel = 0
    healthFill.Parent = healthBg

    local healthFillCorner = Instance.new("UICorner")
    healthFillCorner.CornerRadius = UDim.new(0, 3)
    healthFillCorner.Parent = healthFill

    -- Health text
    local healthText = Instance.new("TextLabel")
    healthText.Name = "HealthText"
    healthText.Size = UDim2.new(1, 0, 1, 0)
    healthText.BackgroundTransparency = 1
    healthText.Text = "100"
    healthText.TextColor3 = Color3.new(1, 1, 1)
    healthText.TextSize = 16
    healthText.Font = Enum.Font.GothamBold
    healthText.Parent = healthFill

    -- Shield bar background
    local shieldBg = Instance.new("Frame")
    shieldBg.Name = "ShieldBg"
    shieldBg.Size = UDim2.new(1, 0, 0, 20)
    shieldBg.Position = UDim2.new(0, 0, 1, -50)
    shieldBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    shieldBg.BorderSizePixel = 0
    shieldBg.Parent = container

    local shieldCorner = Instance.new("UICorner")
    shieldCorner.CornerRadius = UDim.new(0, 4)
    shieldCorner.Parent = shieldBg

    -- Shield bar fill
    local shieldFill = Instance.new("Frame")
    shieldFill.Name = "ShieldFill"
    shieldFill.Size = UDim2.new(0, 0, 1, -4)
    shieldFill.Position = UDim2.new(0, 2, 0, 2)
    shieldFill.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
    shieldFill.BorderSizePixel = 0
    shieldFill.Parent = shieldBg

    local shieldFillCorner = Instance.new("UICorner")
    shieldFillCorner.CornerRadius = UDim.new(0, 3)
    shieldFillCorner.Parent = shieldFill

    components.healthContainer = container
    components.healthFill = healthFill
    components.healthText = healthText
    components.shieldFill = shieldFill
end

--[[
    Create weapon hotbar
]]
function DinoHUD:CreateWeaponHotbar()
    local container = Instance.new("Frame")
    container.Name = "WeaponHotbar"
    container.Size = UDim2.new(0, 350, 0, 70)
    container.Position = UDim2.new(0.5, 0, 1, -20)
    container.AnchorPoint = Vector2.new(0.5, 1)
    container.BackgroundTransparency = 1
    container.Parent = hudFrame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 5)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Parent = container

    components.weaponSlots = {}

    for i = 1, 5 do
        local slot = Instance.new("Frame")
        slot.Name = "Slot" .. i
        slot.Size = UDim2.new(0, 65, 0, 65)
        slot.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        slot.BackgroundTransparency = 0.3
        slot.BorderSizePixel = 0
        slot.Parent = container

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = slot

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(80, 80, 80)
        stroke.Thickness = 2
        stroke.Parent = slot

        -- Slot number
        local slotNum = Instance.new("TextLabel")
        slotNum.Name = "SlotNumber"
        slotNum.Size = UDim2.new(0, 20, 0, 20)
        slotNum.Position = UDim2.new(0, 5, 0, 5)
        slotNum.BackgroundTransparency = 1
        slotNum.Text = tostring(i)
        slotNum.TextColor3 = Color3.new(1, 1, 1)
        slotNum.TextSize = 14
        slotNum.Font = Enum.Font.GothamBold
        slotNum.Parent = slot

        -- Weapon icon placeholder
        local icon = Instance.new("ImageLabel")
        icon.Name = "WeaponIcon"
        icon.Size = UDim2.new(0.8, 0, 0.6, 0)
        icon.Position = UDim2.new(0.5, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.BackgroundTransparency = 1
        icon.ScaleType = Enum.ScaleType.Fit
        icon.Visible = false
        icon.Parent = slot

        -- Ammo counter
        local ammoLabel = Instance.new("TextLabel")
        ammoLabel.Name = "AmmoLabel"
        ammoLabel.Size = UDim2.new(1, -10, 0, 15)
        ammoLabel.Position = UDim2.new(0, 5, 1, -20)
        ammoLabel.BackgroundTransparency = 1
        ammoLabel.Text = ""
        ammoLabel.TextColor3 = Color3.new(1, 1, 1)
        ammoLabel.TextSize = 12
        ammoLabel.Font = Enum.Font.Gotham
        ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
        ammoLabel.Parent = slot

        components.weaponSlots[i] = {
            frame = slot,
            stroke = stroke,
            icon = icon,
            ammo = ammoLabel,
        }
    end

    components.hotbarContainer = container
end

--[[
    Create minimap with storm indicator
]]
function DinoHUD:CreateMinimap()
    local size = gameConfig.UI.minimapSize

    local container = Instance.new("Frame")
    container.Name = "Minimap"
    container.Size = UDim2.new(0, size, 0, size)
    container.Position = UDim2.new(1, -20, 0, 20)
    container.AnchorPoint = Vector2.new(1, 0)
    container.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    container.BackgroundTransparency = 0.3
    container.BorderSizePixel = 0
    container.Parent = hudFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = container

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60, 60, 60)
    stroke.Thickness = 2
    stroke.Parent = container

    -- Storm circle indicator
    local stormCircle = Instance.new("Frame")
    stormCircle.Name = "StormCircle"
    stormCircle.Size = UDim2.new(0.8, 0, 0.8, 0)
    stormCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
    stormCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    stormCircle.BackgroundTransparency = 0.7
    stormCircle.BackgroundColor3 = Color3.fromRGB(75, 0, 130)
    stormCircle.Parent = container

    local stormCorner = Instance.new("UICorner")
    stormCorner.CornerRadius = UDim.new(0.5, 0)
    stormCorner.Parent = stormCircle

    -- Safe zone indicator
    local safeZone = Instance.new("Frame")
    safeZone.Name = "SafeZone"
    safeZone.Size = UDim2.new(0.6, 0, 0.6, 0)
    safeZone.Position = UDim2.new(0.5, 0, 0.5, 0)
    safeZone.AnchorPoint = Vector2.new(0.5, 0.5)
    safeZone.BackgroundTransparency = 0.8
    safeZone.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    safeZone.Parent = container

    local safeCorner = Instance.new("UICorner")
    safeCorner.CornerRadius = UDim.new(0.5, 0)
    safeCorner.Parent = safeZone

    -- Player marker
    local playerMarker = Instance.new("Frame")
    playerMarker.Name = "PlayerMarker"
    playerMarker.Size = UDim2.new(0, 8, 0, 8)
    playerMarker.Position = UDim2.new(0.5, 0, 0.5, 0)
    playerMarker.AnchorPoint = Vector2.new(0.5, 0.5)
    playerMarker.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
    playerMarker.Parent = container

    local markerCorner = Instance.new("UICorner")
    markerCorner.CornerRadius = UDim.new(0.5, 0)
    markerCorner.Parent = playerMarker

    components.minimap = container
    components.stormCircle = stormCircle
    components.safeZone = safeZone
    components.playerMarker = playerMarker
end

--[[
    Create kill feed
]]
function DinoHUD:CreateKillFeed()
    local container = Instance.new("Frame")
    container.Name = "KillFeed"
    container.Size = UDim2.new(0, 300, 0, 150)
    container.Position = UDim2.new(1, -20, 0, 240)
    container.AnchorPoint = Vector2.new(1, 0)
    container.BackgroundTransparency = 1
    container.Parent = hudFrame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 5)
    layout.VerticalAlignment = Enum.VerticalAlignment.Top
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = container

    components.killFeed = container
    components.killFeedItems = {}
end

--[[
    Create player count display
]]
function DinoHUD:CreatePlayerCount()
    local container = Instance.new("Frame")
    container.Name = "PlayerCount"
    container.Size = UDim2.new(0, 100, 0, 50)
    container.Position = UDim2.new(0.5, 0, 0, 20)
    container.AnchorPoint = Vector2.new(0.5, 0)
    container.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    container.BackgroundTransparency = 0.3
    container.BorderSizePixel = 0
    container.Parent = hudFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = container

    -- Player icon
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 24, 0, 24)
    icon.Position = UDim2.new(0, 15, 0.5, 0)
    icon.AnchorPoint = Vector2.new(0, 0.5)
    icon.BackgroundTransparency = 1
    icon.Image = "rbxassetid://6031071053" -- Person icon
    icon.Parent = container

    -- Count text
    local countText = Instance.new("TextLabel")
    countText.Name = "CountText"
    countText.Size = UDim2.new(0, 50, 1, 0)
    countText.Position = UDim2.new(0, 45, 0, 0)
    countText.BackgroundTransparency = 1
    countText.Text = "20"
    countText.TextColor3 = Color3.new(1, 1, 1)
    countText.TextSize = 24
    countText.Font = Enum.Font.GothamBold
    countText.TextXAlignment = Enum.TextXAlignment.Left
    countText.Parent = container

    components.playerCount = countText
end

--[[
    Create squad status display (for duos/trios)
]]
function DinoHUD:CreateSquadStatus()
    local container = Instance.new("Frame")
    container.Name = "SquadStatus"
    container.Size = UDim2.new(0, 200, 0, 100)
    container.Position = UDim2.new(0, 20, 0, 20)
    container.BackgroundTransparency = 1
    container.Parent = hudFrame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 5)
    layout.Parent = container

    components.squadStatus = container
    components.teammateCards = {}
end

--[[
    Create damage indicator
]]
function DinoHUD:CreateDamageIndicator()
    local container = Instance.new("Frame")
    container.Name = "DamageIndicator"
    container.Size = UDim2.new(0, 100, 0, 100)
    container.Position = UDim2.new(0.5, 0, 0.5, 0)
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.BackgroundTransparency = 1
    container.Parent = hudFrame

    components.damageIndicator = container
end

--[[
    Create storm warning display
]]
function DinoHUD:CreateStormWarning()
    local warning = Instance.new("TextLabel")
    warning.Name = "StormWarning"
    warning.Size = UDim2.new(0, 400, 0, 40)
    warning.Position = UDim2.new(0.5, 0, 0, 80)
    warning.AnchorPoint = Vector2.new(0.5, 0)
    warning.BackgroundTransparency = 1
    warning.Text = ""
    warning.TextColor3 = Color3.fromRGB(255, 100, 100)
    warning.TextSize = 20
    warning.Font = Enum.Font.GothamBold
    warning.Visible = false
    warning.Parent = hudFrame

    components.stormWarning = warning
end

--[[
    Connect to remote events
]]
function DinoHUD:ConnectRemotes()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotes then return end

    -- Player count updates
    local aliveRemote = remotes:FindFirstChild("UpdatePlayersAlive")
    if aliveRemote then
        aliveRemote.OnClientEvent:Connect(function(players, teams)
            self:UpdatePlayerCount(players)
        end)
    end

    -- Kill feed
    local eliminatedRemote = remotes:FindFirstChild("PlayerEliminated")
    if eliminatedRemote then
        eliminatedRemote.OnClientEvent:Connect(function(victimId, killerId)
            self:AddKillFeedItem(victimId, killerId)
        end)
    end

    -- Storm updates
    local stormRemote = remotes:FindFirstChild("StormPhaseChanged")
    if stormRemote then
        stormRemote.OnClientEvent:Connect(function(data)
            self:UpdateStormDisplay(data)
        end)
    end

    local warningRemote = remotes:FindFirstChild("StormWarning")
    if warningRemote then
        warningRemote.OnClientEvent:Connect(function(delay, phase)
            self:ShowStormWarning(delay, phase)
        end)
    end
end

--[[
    Start HUD update loop
]]
function DinoHUD:StartUpdateLoop()
    RunService.Heartbeat:Connect(function()
        if not isEnabled then return end

        self:UpdateHealthDisplay()
    end)
end

--[[
    Update health display
]]
function DinoHUD:UpdateHealthDisplay()
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end

    local health = humanoid.Health
    local maxHealth = humanoid.MaxHealth
    local healthPercent = health / maxHealth

    -- Update health bar
    if components.healthFill then
        components.healthFill.Size = UDim2.new(healthPercent, -4, 1, -4)

        -- Color based on health
        if healthPercent > 0.5 then
            components.healthFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
        elseif healthPercent > 0.25 then
            components.healthFill.BackgroundColor3 = Color3.fromRGB(241, 196, 15)
        else
            components.healthFill.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
        end
    end

    if components.healthText then
        components.healthText.Text = tostring(math.ceil(health))
    end
end

--[[
    Update player count display
]]
function DinoHUD:UpdatePlayerCount(count)
    if components.playerCount then
        components.playerCount.Text = tostring(count)
    end
end

--[[
    Add item to kill feed
]]
function DinoHUD:AddKillFeedItem(victimId, killerId)
    local victimName = "Unknown"
    local killerName = "Storm"

    local victim = Players:GetPlayerByUserId(victimId)
    if victim then
        victimName = victim.Name
    end

    if killerId then
        local killer = Players:GetPlayerByUserId(killerId)
        if killer then
            killerName = killer.Name
        end
    end

    -- Create feed item
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 25)
    item.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    item.BackgroundTransparency = 0.5
    item.Text = killerName .. " eliminated " .. victimName
    item.TextColor3 = Color3.new(1, 1, 1)
    item.TextSize = 14
    item.Font = Enum.Font.Gotham
    item.TextXAlignment = Enum.TextXAlignment.Right
    item.Parent = components.killFeed

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = item

    -- Remove after delay
    task.delay(gameConfig.UI.killFeedItemDuration, function()
        if item and item.Parent then
            item:Destroy()
        end
    end)

    -- Limit items
    local children = components.killFeed:GetChildren()
    local textLabels = {}
    for _, child in ipairs(children) do
        if child:IsA("TextLabel") then
            table.insert(textLabels, child)
        end
    end

    while #textLabels > gameConfig.UI.killFeedMaxItems do
        textLabels[1]:Destroy()
        table.remove(textLabels, 1)
    end
end

--[[
    Update storm display on minimap
]]
function DinoHUD:UpdateStormDisplay(data)
    -- Update storm circle visualization
    -- This would scale the minimap circles based on storm data
end

--[[
    Show storm warning
]]
function DinoHUD:ShowStormWarning(delay, phase)
    if components.stormWarning then
        components.stormWarning.Text = string.format("Storm closing in %d seconds (Phase %d)", delay, phase)
        components.stormWarning.Visible = true

        -- Hide after a few seconds
        task.delay(5, function()
            if components.stormWarning then
                components.stormWarning.Visible = false
            end
        end)
    end
end

--[[
    Select weapon slot visually
]]
function DinoHUD:SelectWeaponSlot(slotIndex)
    for i, slot in pairs(components.weaponSlots) do
        if i == slotIndex then
            slot.stroke.Color = Color3.fromRGB(255, 200, 0)
            slot.stroke.Thickness = 3
        else
            slot.stroke.Color = Color3.fromRGB(80, 80, 80)
            slot.stroke.Thickness = 2
        end
    end
end

--[[
    Update weapon slot display
]]
function DinoHUD:UpdateWeaponSlot(slotIndex, weaponData)
    local slot = components.weaponSlots[slotIndex]
    if not slot then return end

    if weaponData then
        slot.ammo.Text = string.format("%d/%d", weaponData.currentAmmo, weaponData.config.magazineSize)
        slot.frame.BackgroundColor3 = gameConfig.Loot.rarityColors[weaponData.config.rarity] or Color3.fromRGB(30, 30, 30)
        slot.frame.BackgroundTransparency = 0.5
    else
        slot.ammo.Text = ""
        slot.frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        slot.frame.BackgroundTransparency = 0.7
    end
end

--[[
    Show damage indicator
]]
function DinoHUD:ShowDamageIndicator(direction)
    -- Create directional damage indicator
    local indicator = Instance.new("ImageLabel")
    indicator.Size = UDim2.new(0, 50, 0, 50)
    indicator.Position = UDim2.new(0.5, 0, 0.5, 0)
    indicator.AnchorPoint = Vector2.new(0.5, 0.5)
    indicator.BackgroundTransparency = 1
    indicator.Image = "rbxassetid://6031090990" -- Arrow icon
    indicator.ImageColor3 = Color3.fromRGB(255, 0, 0)
    indicator.Rotation = direction or 0
    indicator.Parent = components.damageIndicator

    -- Fade out
    local tween = TweenService:Create(indicator, TweenInfo.new(gameConfig.UI.damageIndicatorDuration), {
        ImageTransparency = 1
    })
    tween:Play()
    tween.Completed:Connect(function()
        indicator:Destroy()
    end)
end

--[[
    Enable/disable HUD
]]
function DinoHUD:SetEnabled(enabled)
    isEnabled = enabled
    if screenGui then
        screenGui.Enabled = enabled
    end
end

--[[
    Destroy HUD
]]
function DinoHUD:Destroy()
    if screenGui then
        screenGui:Destroy()
    end
    components = {}
end

--=============================================================================
-- DINOSAUR HEALTH BARS (Phase 3 UX)
-- Shows health bars above targeted dinosaurs
--=============================================================================

--[[
    Create dinosaur health bar UI (for targeted dinos)
    Shows above the dinosaur model in world space
]]
function DinoHUD:CreateDinoHealthBar()
    local container = Instance.new("Frame")
    container.Name = "DinoHealthContainer"
    container.Size = UDim2.new(0, 200, 0, 40)
    container.Position = UDim2.new(0.5, 0, 0.15, 0)
    container.AnchorPoint = Vector2.new(0.5, 0)
    container.BackgroundTransparency = 1
    container.Visible = false
    container.Parent = hudFrame

    -- Dino name label
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "DinoName"
    nameLabel.Size = UDim2.new(1, 0, 0, 20)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = "Velociraptor"
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextSize = 14
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextStrokeTransparency = 0.5
    nameLabel.Parent = container

    -- Health bar background
    local healthBg = Instance.new("Frame")
    healthBg.Name = "DinoHealthBg"
    healthBg.Size = UDim2.new(1, 0, 0, 12)
    healthBg.Position = UDim2.new(0, 0, 0, 22)
    healthBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    healthBg.BorderSizePixel = 0
    healthBg.Parent = container

    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(0, 4)
    healthCorner.Parent = healthBg

    -- Health bar fill
    local healthFill = Instance.new("Frame")
    healthFill.Name = "DinoHealthFill"
    healthFill.Size = UDim2.new(1, -4, 1, -4)
    healthFill.Position = UDim2.new(0, 2, 0, 2)
    healthFill.BackgroundColor3 = Color3.fromRGB(231, 76, 60) -- Red for enemies
    healthFill.BorderSizePixel = 0
    healthFill.Parent = healthBg

    local healthFillCorner = Instance.new("UICorner")
    healthFillCorner.CornerRadius = UDim.new(0, 3)
    healthFillCorner.Parent = healthFill

    components.dinoHealthContainer = container
    components.dinoHealthFill = healthFill
    components.dinoNameLabel = nameLabel
end

--[[
    Update dinosaur health bar display
    @param dinoName string - Name of the dinosaur
    @param currentHealth number - Current health
    @param maxHealth number - Maximum health
]]
function DinoHUD:UpdateDinoHealth(dinoName, currentHealth, maxHealth)
    if not components.dinoHealthContainer then
        self:CreateDinoHealthBar()
    end

    local healthPercent = math.clamp(currentHealth / maxHealth, 0, 1)
    components.dinoHealthFill.Size = UDim2.new(healthPercent, -4, 1, -4)
    components.dinoNameLabel.Text = dinoName
    components.dinoHealthContainer.Visible = true

    -- Hide after 3 seconds of no updates
    if components.dinoHealthHideTimer then
        task.cancel(components.dinoHealthHideTimer)
    end
    components.dinoHealthHideTimer = task.delay(3, function()
        if components.dinoHealthContainer then
            components.dinoHealthContainer.Visible = false
        end
    end)
end

--[[
    Hide dinosaur health bar
]]
function DinoHUD:HideDinoHealth()
    if components.dinoHealthContainer then
        components.dinoHealthContainer.Visible = false
    end
end

--=============================================================================
-- BOSS HEALTH BAR (Phase 3 UX)
-- Large health bar at top of screen for boss fights
--=============================================================================

--[[
    Create boss health bar UI
    Large bar at top of screen with boss name and phase indicator
]]
function DinoHUD:CreateBossHealthBar()
    local container = Instance.new("Frame")
    container.Name = "BossHealthContainer"
    container.Size = UDim2.new(0, 600, 0, 80)
    container.Position = UDim2.new(0.5, 0, 0, 20)
    container.AnchorPoint = Vector2.new(0.5, 0)
    container.BackgroundTransparency = 1
    container.Visible = false
    container.Parent = hudFrame

    -- Boss name label
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "BossName"
    nameLabel.Size = UDim2.new(1, 0, 0, 30)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = "ALPHA T-REX"
    nameLabel.TextColor3 = Color3.fromRGB(255, 215, 0) -- Gold for boss
    nameLabel.TextSize = 24
    nameLabel.Font = Enum.Font.GothamBlack
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.Parent = container

    -- Phase indicator
    local phaseLabel = Instance.new("TextLabel")
    phaseLabel.Name = "PhaseLabel"
    phaseLabel.Size = UDim2.new(1, 0, 0, 16)
    phaseLabel.Position = UDim2.new(0, 0, 0, 28)
    phaseLabel.BackgroundTransparency = 1
    phaseLabel.Text = "Phase 1"
    phaseLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    phaseLabel.TextSize = 12
    phaseLabel.Font = Enum.Font.Gotham
    phaseLabel.Parent = container

    -- Health bar background
    local healthBg = Instance.new("Frame")
    healthBg.Name = "BossHealthBg"
    healthBg.Size = UDim2.new(1, 0, 0, 25)
    healthBg.Position = UDim2.new(0, 0, 0, 50)
    healthBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    healthBg.BorderSizePixel = 0
    healthBg.Parent = container

    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(0, 6)
    healthCorner.Parent = healthBg

    local healthStroke = Instance.new("UIStroke")
    healthStroke.Color = Color3.fromRGB(255, 215, 0)
    healthStroke.Thickness = 2
    healthStroke.Parent = healthBg

    -- Health bar fill
    local healthFill = Instance.new("Frame")
    healthFill.Name = "BossHealthFill"
    healthFill.Size = UDim2.new(1, -6, 1, -6)
    healthFill.Position = UDim2.new(0, 3, 0, 3)
    healthFill.BackgroundColor3 = Color3.fromRGB(192, 57, 43) -- Dark red
    healthFill.BorderSizePixel = 0
    healthFill.Parent = healthBg

    local healthFillCorner = Instance.new("UICorner")
    healthFillCorner.CornerRadius = UDim.new(0, 4)
    healthFillCorner.Parent = healthFill

    -- Gradient for boss health
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(231, 76, 60)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(192, 57, 43))
    })
    gradient.Rotation = 90
    gradient.Parent = healthFill

    components.bossHealthContainer = container
    components.bossHealthFill = healthFill
    components.bossNameLabel = nameLabel
    components.bossPhaseLabel = phaseLabel
end

--[[
    Show boss health bar
    @param bossName string - Name of the boss
    @param currentHealth number - Current health
    @param maxHealth number - Maximum health
    @param phase number - Current phase (1, 2, or 3)
]]
function DinoHUD:ShowBossHealth(bossName, currentHealth, maxHealth, phase)
    if not components.bossHealthContainer then
        self:CreateBossHealthBar()
    end

    local healthPercent = math.clamp(currentHealth / maxHealth, 0, 1)
    components.bossHealthFill.Size = UDim2.new(healthPercent, -6, 1, -6)
    components.bossNameLabel.Text = string.upper(bossName)
    components.bossPhaseLabel.Text = "Phase " .. (phase or 1)
    components.bossHealthContainer.Visible = true

    -- Change color based on phase
    local phaseColors = {
        [1] = Color3.fromRGB(231, 76, 60),   -- Red
        [2] = Color3.fromRGB(230, 126, 34),  -- Orange
        [3] = Color3.fromRGB(142, 68, 173),  -- Purple (rage)
    }
    components.bossHealthFill.BackgroundColor3 = phaseColors[phase] or phaseColors[1]
end

--[[
    Hide boss health bar
]]
function DinoHUD:HideBossHealth()
    if components.bossHealthContainer then
        components.bossHealthContainer.Visible = false
    end
end

--=============================================================================
-- LOBBY UI (Phase 3 UX)
-- Shows player count, timer, and game mode in lobby
--=============================================================================

--[[
    Create lobby UI
]]
function DinoHUD:CreateLobbyUI()
    local container = Instance.new("Frame")
    container.Name = "LobbyContainer"
    container.Size = UDim2.new(0, 400, 0, 200)
    container.Position = UDim2.new(0.5, 0, 0.3, 0)
    container.AnchorPoint = Vector2.new(0.5, 0)
    container.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    container.BackgroundTransparency = 0.3
    container.Visible = false
    container.Parent = hudFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = container

    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "LobbyTitle"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = "DINO ROYALE 2"
    title.TextColor3 = Color3.fromRGB(255, 215, 0)
    title.TextSize = 28
    title.Font = Enum.Font.GothamBlack
    title.Parent = container

    -- Player count
    local playerCount = Instance.new("TextLabel")
    playerCount.Name = "PlayerCount"
    playerCount.Size = UDim2.new(1, 0, 0, 30)
    playerCount.Position = UDim2.new(0, 0, 0, 60)
    playerCount.BackgroundTransparency = 1
    playerCount.Text = "Players: 0 / 60"
    playerCount.TextColor3 = Color3.new(1, 1, 1)
    playerCount.TextSize = 18
    playerCount.Font = Enum.Font.GothamBold
    playerCount.Parent = container

    -- Timer
    local timer = Instance.new("TextLabel")
    timer.Name = "LobbyTimer"
    timer.Size = UDim2.new(1, 0, 0, 40)
    timer.Position = UDim2.new(0, 0, 0, 100)
    timer.BackgroundTransparency = 1
    timer.Text = "Waiting for players..."
    timer.TextColor3 = Color3.fromRGB(200, 200, 200)
    timer.TextSize = 20
    timer.Font = Enum.Font.Gotham
    timer.Parent = container

    -- Game mode
    local modeLabel = Instance.new("TextLabel")
    modeLabel.Name = "GameMode"
    modeLabel.Size = UDim2.new(1, 0, 0, 25)
    modeLabel.Position = UDim2.new(0, 0, 0, 150)
    modeLabel.BackgroundTransparency = 1
    modeLabel.Text = "Mode: Solo"
    modeLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    modeLabel.TextSize = 14
    modeLabel.Font = Enum.Font.Gotham
    modeLabel.Parent = container

    components.lobbyContainer = container
    components.lobbyPlayerCount = playerCount
    components.lobbyTimer = timer
    components.lobbyGameMode = modeLabel
end

--[[
    Update lobby UI
    @param data table - Lobby status data {currentPlayers, requiredPlayers, timeRemaining, canStart}
]]
function DinoHUD:UpdateLobbyUI(data)
    if not components.lobbyContainer then
        self:CreateLobbyUI()
    end

    components.lobbyPlayerCount.Text = string.format("Players: %d / %d",
        data.currentPlayers or 0, data.requiredPlayers or 60)

    if data.canStart and data.timeRemaining then
        components.lobbyTimer.Text = string.format("Starting in %d...", math.ceil(data.timeRemaining))
        components.lobbyTimer.TextColor3 = Color3.fromRGB(46, 204, 113)
    else
        local needed = (data.requiredPlayers or 2) - (data.currentPlayers or 0)
        components.lobbyTimer.Text = string.format("Need %d more players", math.max(0, needed))
        components.lobbyTimer.TextColor3 = Color3.fromRGB(200, 200, 200)
    end

    components.lobbyContainer.Visible = true
end

--[[
    Hide lobby UI
]]
function DinoHUD:HideLobbyUI()
    if components.lobbyContainer then
        components.lobbyContainer.Visible = false
    end
end

--=============================================================================
-- DEATH SCREEN (Phase 4 Polish)
-- Shows when player is eliminated
--=============================================================================

--[[
    Create death screen UI
]]
function DinoHUD:CreateDeathScreen()
    local container = Instance.new("Frame")
    container.Name = "DeathScreen"
    container.Size = UDim2.new(1, 0, 1, 0)
    container.Position = UDim2.new(0, 0, 0, 0)
    container.BackgroundColor3 = Color3.new(0, 0, 0)
    container.BackgroundTransparency = 0.5
    container.Visible = false
    container.ZIndex = 100
    container.Parent = hudFrame

    -- "YOU DIED" text
    local deathText = Instance.new("TextLabel")
    deathText.Name = "DeathText"
    deathText.Size = UDim2.new(1, 0, 0, 80)
    deathText.Position = UDim2.new(0, 0, 0.3, 0)
    deathText.BackgroundTransparency = 1
    deathText.Text = "ELIMINATED"
    deathText.TextColor3 = Color3.fromRGB(231, 76, 60)
    deathText.TextSize = 64
    deathText.Font = Enum.Font.GothamBlack
    deathText.TextStrokeTransparency = 0
    deathText.Parent = container

    -- Killed by label
    local killedBy = Instance.new("TextLabel")
    killedBy.Name = "KilledBy"
    killedBy.Size = UDim2.new(1, 0, 0, 30)
    killedBy.Position = UDim2.new(0, 0, 0.3, 90)
    killedBy.BackgroundTransparency = 1
    killedBy.Text = "Killed by: Player123"
    killedBy.TextColor3 = Color3.new(1, 1, 1)
    killedBy.TextSize = 20
    killedBy.Font = Enum.Font.Gotham
    killedBy.Parent = container

    -- Placement label
    local placement = Instance.new("TextLabel")
    placement.Name = "Placement"
    placement.Size = UDim2.new(1, 0, 0, 50)
    placement.Position = UDim2.new(0, 0, 0.3, 130)
    placement.BackgroundTransparency = 1
    placement.Text = "#25"
    placement.TextColor3 = Color3.fromRGB(255, 215, 0)
    placement.TextSize = 36
    placement.Font = Enum.Font.GothamBold
    placement.Parent = container

    -- Spectate button
    local spectateBtn = Instance.new("TextButton")
    spectateBtn.Name = "SpectateButton"
    spectateBtn.Size = UDim2.new(0, 200, 0, 50)
    spectateBtn.Position = UDim2.new(0.5, -105, 0.6, 0)
    spectateBtn.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
    spectateBtn.Text = "SPECTATE"
    spectateBtn.TextColor3 = Color3.new(1, 1, 1)
    spectateBtn.TextSize = 18
    spectateBtn.Font = Enum.Font.GothamBold
    spectateBtn.Parent = container

    local specCorner = Instance.new("UICorner")
    specCorner.CornerRadius = UDim.new(0, 8)
    specCorner.Parent = spectateBtn

    -- Return to lobby button
    local lobbyBtn = Instance.new("TextButton")
    lobbyBtn.Name = "ReturnButton"
    lobbyBtn.Size = UDim2.new(0, 200, 0, 50)
    lobbyBtn.Position = UDim2.new(0.5, 105, 0.6, 0)
    lobbyBtn.AnchorPoint = Vector2.new(1, 0)
    lobbyBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    lobbyBtn.Text = "RETURN TO LOBBY"
    lobbyBtn.TextColor3 = Color3.new(1, 1, 1)
    lobbyBtn.TextSize = 16
    lobbyBtn.Font = Enum.Font.GothamBold
    lobbyBtn.Parent = container

    local lobbyCorner = Instance.new("UICorner")
    lobbyCorner.CornerRadius = UDim.new(0, 8)
    lobbyCorner.Parent = lobbyBtn

    components.deathScreen = container
    components.deathKilledBy = killedBy
    components.deathPlacement = placement
    components.spectateButton = spectateBtn
    components.returnButton = lobbyBtn
end

--[[
    Show death screen
    @param killerName string - Name of the player/dino that killed you
    @param placement number - Your final placement
]]
function DinoHUD:ShowDeathScreen(killerName, placement)
    if not components.deathScreen then
        self:CreateDeathScreen()
    end

    components.deathKilledBy.Text = "Killed by: " .. (killerName or "Unknown")
    components.deathPlacement.Text = "#" .. (placement or "?")
    components.deathScreen.Visible = true

    -- Animate fade in
    components.deathScreen.BackgroundTransparency = 1
    TweenService:Create(components.deathScreen,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad),
        {BackgroundTransparency = 0.5}
    ):Play()
end

--[[
    Hide death screen
]]
function DinoHUD:HideDeathScreen()
    if components.deathScreen then
        components.deathScreen.Visible = false
    end
end

--=============================================================================
-- VICTORY SCREEN (Phase 4 Polish)
-- Shows when player/team wins
--=============================================================================

--[[
    Create victory screen UI
]]
function DinoHUD:CreateVictoryScreen()
    local container = Instance.new("Frame")
    container.Name = "VictoryScreen"
    container.Size = UDim2.new(1, 0, 1, 0)
    container.Position = UDim2.new(0, 0, 0, 0)
    container.BackgroundColor3 = Color3.new(0, 0, 0)
    container.BackgroundTransparency = 0.4
    container.Visible = false
    container.ZIndex = 100
    container.Parent = hudFrame

    -- Victory text
    local victoryText = Instance.new("TextLabel")
    victoryText.Name = "VictoryText"
    victoryText.Size = UDim2.new(1, 0, 0, 100)
    victoryText.Position = UDim2.new(0, 0, 0.25, 0)
    victoryText.BackgroundTransparency = 1
    victoryText.Text = "VICTORY ROYALE!"
    victoryText.TextColor3 = Color3.fromRGB(255, 215, 0)
    victoryText.TextSize = 72
    victoryText.Font = Enum.Font.GothamBlack
    victoryText.TextStrokeTransparency = 0
    victoryText.Parent = container

    -- Stats container
    local statsFrame = Instance.new("Frame")
    statsFrame.Name = "StatsFrame"
    statsFrame.Size = UDim2.new(0, 300, 0, 150)
    statsFrame.Position = UDim2.new(0.5, 0, 0.45, 0)
    statsFrame.AnchorPoint = Vector2.new(0.5, 0)
    statsFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    statsFrame.BackgroundTransparency = 0.5
    statsFrame.Parent = container

    local statsCorner = Instance.new("UICorner")
    statsCorner.CornerRadius = UDim.new(0, 10)
    statsCorner.Parent = statsFrame

    -- Kills stat
    local killsLabel = Instance.new("TextLabel")
    killsLabel.Name = "Kills"
    killsLabel.Size = UDim2.new(1, 0, 0, 40)
    killsLabel.Position = UDim2.new(0, 0, 0, 20)
    killsLabel.BackgroundTransparency = 1
    killsLabel.Text = "Eliminations: 0"
    killsLabel.TextColor3 = Color3.new(1, 1, 1)
    killsLabel.TextSize = 20
    killsLabel.Font = Enum.Font.GothamBold
    killsLabel.Parent = statsFrame

    -- Damage stat
    local damageLabel = Instance.new("TextLabel")
    damageLabel.Name = "Damage"
    damageLabel.Size = UDim2.new(1, 0, 0, 40)
    damageLabel.Position = UDim2.new(0, 0, 0, 60)
    damageLabel.BackgroundTransparency = 1
    damageLabel.Text = "Damage Dealt: 0"
    damageLabel.TextColor3 = Color3.new(1, 1, 1)
    damageLabel.TextSize = 20
    damageLabel.Font = Enum.Font.GothamBold
    damageLabel.Parent = statsFrame

    -- Dinos killed stat
    local dinosLabel = Instance.new("TextLabel")
    dinosLabel.Name = "Dinos"
    dinosLabel.Size = UDim2.new(1, 0, 0, 40)
    dinosLabel.Position = UDim2.new(0, 0, 0, 100)
    dinosLabel.BackgroundTransparency = 1
    dinosLabel.Text = "Dinosaurs Killed: 0"
    dinosLabel.TextColor3 = Color3.new(1, 1, 1)
    dinosLabel.TextSize = 20
    dinosLabel.Font = Enum.Font.GothamBold
    dinosLabel.Parent = statsFrame

    components.victoryScreen = container
    components.victoryKills = killsLabel
    components.victoryDamage = damageLabel
    components.victoryDinos = dinosLabel
end

--[[
    Show victory screen
    @param stats table - Player stats {kills, damage, dinosKilled}
]]
function DinoHUD:ShowVictoryScreen(stats)
    if not components.victoryScreen then
        self:CreateVictoryScreen()
    end

    stats = stats or {}
    components.victoryKills.Text = "Eliminations: " .. (stats.kills or 0)
    components.victoryDamage.Text = "Damage Dealt: " .. (stats.damage or 0)
    components.victoryDinos.Text = "Dinosaurs Killed: " .. (stats.dinosKilled or 0)
    components.victoryScreen.Visible = true

    -- Animate
    components.victoryScreen.BackgroundTransparency = 1
    TweenService:Create(components.victoryScreen,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad),
        {BackgroundTransparency = 0.4}
    ):Play()
end

--[[
    Hide victory screen
]]
function DinoHUD:HideVictoryScreen()
    if components.victoryScreen then
        components.victoryScreen.Visible = false
    end
end

--=============================================================================
-- SPECTATOR MODE (Phase 4 Polish)
-- UI for spectating other players
--=============================================================================

--[[
    Create spectator UI
]]
function DinoHUD:CreateSpectatorUI()
    local container = Instance.new("Frame")
    container.Name = "SpectatorContainer"
    container.Size = UDim2.new(0, 400, 0, 60)
    container.Position = UDim2.new(0.5, 0, 0, 20)
    container.AnchorPoint = Vector2.new(0.5, 0)
    container.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    container.BackgroundTransparency = 0.5
    container.Visible = false
    container.Parent = hudFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = container

    -- "SPECTATING" label
    local spectatingLabel = Instance.new("TextLabel")
    spectatingLabel.Name = "SpectatingLabel"
    spectatingLabel.Size = UDim2.new(1, 0, 0, 20)
    spectatingLabel.Position = UDim2.new(0, 0, 0, 5)
    spectatingLabel.BackgroundTransparency = 1
    spectatingLabel.Text = "SPECTATING"
    spectatingLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    spectatingLabel.TextSize = 12
    spectatingLabel.Font = Enum.Font.Gotham
    spectatingLabel.Parent = container

    -- Player name
    local playerName = Instance.new("TextLabel")
    playerName.Name = "SpectatingPlayer"
    playerName.Size = UDim2.new(1, 0, 0, 30)
    playerName.Position = UDim2.new(0, 0, 0, 25)
    playerName.BackgroundTransparency = 1
    playerName.Text = "Player123"
    playerName.TextColor3 = Color3.new(1, 1, 1)
    playerName.TextSize = 20
    playerName.Font = Enum.Font.GothamBold
    playerName.Parent = container

    -- Previous/Next buttons
    local prevBtn = Instance.new("TextButton")
    prevBtn.Name = "PrevPlayer"
    prevBtn.Size = UDim2.new(0, 40, 0, 40)
    prevBtn.Position = UDim2.new(0, 10, 0.5, 0)
    prevBtn.AnchorPoint = Vector2.new(0, 0.5)
    prevBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    prevBtn.Text = "<"
    prevBtn.TextColor3 = Color3.new(1, 1, 1)
    prevBtn.TextSize = 24
    prevBtn.Font = Enum.Font.GothamBold
    prevBtn.Parent = container

    local prevCorner = Instance.new("UICorner")
    prevCorner.CornerRadius = UDim.new(0, 6)
    prevCorner.Parent = prevBtn

    local nextBtn = Instance.new("TextButton")
    nextBtn.Name = "NextPlayer"
    nextBtn.Size = UDim2.new(0, 40, 0, 40)
    nextBtn.Position = UDim2.new(1, -10, 0.5, 0)
    nextBtn.AnchorPoint = Vector2.new(1, 0.5)
    nextBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    nextBtn.Text = ">"
    nextBtn.TextColor3 = Color3.new(1, 1, 1)
    nextBtn.TextSize = 24
    nextBtn.Font = Enum.Font.GothamBold
    nextBtn.Parent = container

    local nextCorner = Instance.new("UICorner")
    nextCorner.CornerRadius = UDim.new(0, 6)
    nextCorner.Parent = nextBtn

    components.spectatorContainer = container
    components.spectatorPlayerName = playerName
    components.spectatorPrevBtn = prevBtn
    components.spectatorNextBtn = nextBtn
end

--[[
    Show spectator UI
    @param playerName string - Name of player being spectated
]]
function DinoHUD:ShowSpectatorUI(playerName)
    if not components.spectatorContainer then
        self:CreateSpectatorUI()
    end

    components.spectatorPlayerName.Text = playerName or "Unknown"
    components.spectatorContainer.Visible = true
end

--[[
    Update spectator target
    @param playerName string - New target name
]]
function DinoHUD:UpdateSpectatorTarget(playerName)
    if components.spectatorPlayerName then
        components.spectatorPlayerName.Text = playerName or "Unknown"
    end
end

--[[
    Hide spectator UI
]]
function DinoHUD:HideSpectatorUI()
    if components.spectatorContainer then
        components.spectatorContainer.Visible = false
    end
end

return DinoHUD
