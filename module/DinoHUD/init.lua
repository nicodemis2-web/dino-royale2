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

return DinoHUD
