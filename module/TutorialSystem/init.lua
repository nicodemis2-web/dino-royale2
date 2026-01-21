--[[
    ================================================================================
    TutorialSystem - Onboarding & Tutorial for Dino Royale 2
    ================================================================================

    This module provides a tutorial/onboarding experience for new players:
    - First-time player detection
    - Step-by-step tutorial UI
    - Interactive hints during gameplay
    - Tips for game mechanics

    Tutorial Steps:
    1. Welcome & Basic Controls (WASD, mouse look)
    2. Weapon Pickup (interact with loot)
    3. Shooting & Aiming (fire, ADS)
    4. Inventory Management (weapon slots, reload)
    5. Storm/Zone Awareness (minimap, safe zone)
    6. Dinosaur Threats (avoid/fight dinosaurs)
    7. Victory Conditions (last one standing)

    Features:
    - Persistent tutorial progress (DataStore)
    - Skippable for experienced players
    - Contextual hints during gameplay
    - Mobile-friendly UI

    Usage:
        local TutorialSystem = require(game.ReplicatedStorage.Module.TutorialSystem)
        TutorialSystem:Initialize()
        TutorialSystem:StartTutorial()

    Author: Dino Royale 2 Development Team
    Version: 1.0.0
    ================================================================================
]]

--==============================================================================
-- SERVICES
--==============================================================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

--==============================================================================
-- MODULE DEFINITION
--==============================================================================
local TutorialSystem = {}
TutorialSystem.__index = TutorialSystem

--==============================================================================
-- PRIVATE STATE
--==============================================================================
local player = Players.LocalPlayer
local screenGui = nil
local tutorialFrame = nil
local isInitialized = false
local isActive = false
local currentStep = 0
local completedSteps = {}
local hintsShown = {}

--==============================================================================
-- TUTORIAL STEPS DEFINITION
--==============================================================================
local TUTORIAL_STEPS = {
    {
        id = "welcome",
        title = "Welcome to Dino Royale!",
        description = "You've landed on an island filled with dinosaurs and other players. Your goal: be the last one standing!",
        icon = "🦖",
        buttonText = "Let's Go!",
        showDuration = 0, -- Manual dismiss
    },
    {
        id = "movement",
        title = "Basic Movement",
        description = "Use WASD to move around. Move your mouse to look around. On mobile, use the virtual joystick on the left.",
        icon = "🎮",
        buttonText = "Got It",
        showDuration = 0,
        highlightArea = "movement",
    },
    {
        id = "loot",
        title = "Pick Up Weapons",
        description = "Walk over weapons and items on the ground to pick them up. Loot chests for better gear!",
        icon = "🔫",
        buttonText = "Understood",
        showDuration = 0,
        highlightArea = "hotbar",
    },
    {
        id = "shooting",
        title = "Combat Basics",
        description = "Click/tap to fire your weapon. Hold right-click to aim down sights for better accuracy. Press R to reload.",
        icon = "🎯",
        buttonText = "Ready to Fight",
        showDuration = 0,
        highlightArea = "crosshair",
    },
    {
        id = "inventory",
        title = "Inventory Management",
        description = "You have 5 weapon slots (keys 1-5). Press TAB to see your full inventory. Manage your loadout wisely!",
        icon = "🎒",
        buttonText = "Got It",
        showDuration = 0,
        highlightArea = "hotbar",
    },
    {
        id = "storm",
        title = "The Storm",
        description = "The safe zone shrinks over time! Check your minimap - stay inside the white circle or take damage from the storm.",
        icon = "⚡",
        buttonText = "Understood",
        showDuration = 0,
        highlightArea = "minimap",
    },
    {
        id = "dinosaurs",
        title = "Dinosaur Threats",
        description = "Dinosaurs roam the island! They're dangerous but drop valuable loot. Work together or fight them alone - just don't get eaten!",
        icon = "🦕",
        buttonText = "I'll Be Careful",
        showDuration = 0,
    },
    {
        id = "victory",
        title = "Victory Condition",
        description = "Eliminate players and dinosaurs, survive the storm, and be the last one standing to win! Good luck!",
        icon = "🏆",
        buttonText = "Start Playing!",
        showDuration = 0,
        isFinal = true,
    },
}

--==============================================================================
-- CONTEXTUAL HINTS (shown during gameplay)
--==============================================================================
local GAMEPLAY_HINTS = {
    {
        id = "first_weapon_pickup",
        trigger = "weapon_pickup",
        title = "Weapon Equipped!",
        description = "Switch weapons with number keys 1-5. Always keep a variety!",
        oneTime = true,
    },
    {
        id = "low_ammo",
        trigger = "low_ammo",
        title = "Low Ammo!",
        description = "Press R to reload. Loot ammo crates and defeated enemies.",
        oneTime = false,
    },
    {
        id = "storm_warning",
        trigger = "storm_warning",
        title = "Storm Incoming!",
        description = "The safe zone is shrinking! Check your minimap and move quickly.",
        oneTime = false,
    },
    {
        id = "first_dino_nearby",
        trigger = "dino_nearby",
        title = "Dinosaur Detected!",
        description = "A dinosaur is nearby! Engage or escape - your choice.",
        oneTime = true,
    },
    {
        id = "first_damage",
        trigger = "took_damage",
        title = "You're Hit!",
        description = "Use healing items (if you have them) by selecting them in your inventory.",
        oneTime = true,
    },
    {
        id = "teammate_down",
        trigger = "teammate_downed",
        title = "Teammate Down!",
        description = "Revive your teammate by holding E near them.",
        oneTime = true,
    },
}

--==============================================================================
-- UI CREATION
--==============================================================================

--[[
    Create the tutorial UI
]]
local function createTutorialUI()
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TutorialUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 200
    screenGui.Enabled = false
    screenGui.Parent = player:WaitForChild("PlayerGui")

    -- Dark overlay (non-interactive so buttons can be clicked through it)
    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0.5
    overlay.BorderSizePixel = 0
    overlay.ZIndex = 1
    overlay.Active = false  -- Critical: allows clicks to pass through to elements below
    overlay.Parent = screenGui

    -- Tutorial panel (higher ZIndex so it's above overlay and interactive)
    tutorialFrame = Instance.new("Frame")
    tutorialFrame.Name = "TutorialPanel"
    tutorialFrame.Size = UDim2.new(0, 450, 0, 300)
    tutorialFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    tutorialFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    tutorialFrame.BackgroundColor3 = Color3.fromRGB(30, 35, 45)
    tutorialFrame.BorderSizePixel = 0
    tutorialFrame.ZIndex = 10
    tutorialFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = tutorialFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(80, 150, 80)
    stroke.Thickness = 2
    stroke.Parent = tutorialFrame

    -- Icon
    local icon = Instance.new("TextLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 80, 0, 80)
    icon.Position = UDim2.new(0.5, 0, 0, 20)
    icon.AnchorPoint = Vector2.new(0.5, 0)
    icon.BackgroundTransparency = 1
    icon.TextSize = 50
    icon.Font = Enum.Font.GothamBold
    icon.TextColor3 = Color3.new(1, 1, 1)
    icon.Parent = tutorialFrame

    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -40, 0, 40)
    title.Position = UDim2.new(0, 20, 0, 100)
    title.BackgroundTransparency = 1
    title.TextSize = 24
    title.Font = Enum.Font.GothamBold
    title.TextColor3 = Color3.new(1, 1, 1)
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.Parent = tutorialFrame

    -- Description
    local description = Instance.new("TextLabel")
    description.Name = "Description"
    description.Size = UDim2.new(1, -40, 0, 80)
    description.Position = UDim2.new(0, 20, 0, 145)
    description.BackgroundTransparency = 1
    description.TextSize = 16
    description.Font = Enum.Font.Gotham
    description.TextColor3 = Color3.fromRGB(200, 200, 200)
    description.TextXAlignment = Enum.TextXAlignment.Center
    description.TextYAlignment = Enum.TextYAlignment.Top
    description.TextWrapped = true
    description.Parent = tutorialFrame

    -- Continue button
    local button = Instance.new("TextButton")
    button.Name = "ContinueButton"
    button.Size = UDim2.new(0, 200, 0, 45)
    button.Position = UDim2.new(0.5, 0, 1, -60)
    button.AnchorPoint = Vector2.new(0.5, 0)
    button.BackgroundColor3 = Color3.fromRGB(80, 150, 80)
    button.BorderSizePixel = 0
    button.TextSize = 18
    button.Font = Enum.Font.GothamBold
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Text = "Continue"
    button.ZIndex = 11
    button.Parent = tutorialFrame

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 8)
    buttonCorner.Parent = button

    button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(100, 180, 100)
        }):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(80, 150, 80)
        }):Play()
    end)

    button.MouseButton1Click:Connect(function()
        TutorialSystem:NextStep()
    end)

    -- Skip button
    local skipButton = Instance.new("TextButton")
    skipButton.Name = "SkipButton"
    skipButton.Size = UDim2.new(0, 100, 0, 30)
    skipButton.Position = UDim2.new(1, -10, 0, 10)
    skipButton.AnchorPoint = Vector2.new(1, 0)
    skipButton.BackgroundTransparency = 1
    skipButton.TextSize = 14
    skipButton.Font = Enum.Font.Gotham
    skipButton.TextColor3 = Color3.fromRGB(150, 150, 150)
    skipButton.Text = "Skip Tutorial"
    skipButton.ZIndex = 11
    skipButton.Parent = tutorialFrame

    skipButton.MouseButton1Click:Connect(function()
        TutorialSystem:SkipTutorial()
    end)

    -- Step indicator
    local stepIndicator = Instance.new("TextLabel")
    stepIndicator.Name = "StepIndicator"
    stepIndicator.Size = UDim2.new(0, 100, 0, 20)
    stepIndicator.Position = UDim2.new(0, 20, 1, -30)
    stepIndicator.BackgroundTransparency = 1
    stepIndicator.TextSize = 12
    stepIndicator.Font = Enum.Font.Gotham
    stepIndicator.TextColor3 = Color3.fromRGB(120, 120, 120)
    stepIndicator.TextXAlignment = Enum.TextXAlignment.Left
    stepIndicator.Parent = tutorialFrame
end

--[[
    Create hint popup UI
]]
local hintFrame = nil
local function createHintUI()
    hintFrame = Instance.new("Frame")
    hintFrame.Name = "HintPopup"
    hintFrame.Size = UDim2.new(0, 350, 0, 100)
    hintFrame.Position = UDim2.new(0.5, 0, 0, 80)
    hintFrame.AnchorPoint = Vector2.new(0.5, 0)
    hintFrame.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
    hintFrame.BackgroundTransparency = 0.1
    hintFrame.BorderSizePixel = 0
    hintFrame.Visible = false
    hintFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = hintFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 200, 100)
    stroke.Thickness = 2
    stroke.Parent = hintFrame

    local hintTitle = Instance.new("TextLabel")
    hintTitle.Name = "HintTitle"
    hintTitle.Size = UDim2.new(1, -20, 0, 30)
    hintTitle.Position = UDim2.new(0, 10, 0, 10)
    hintTitle.BackgroundTransparency = 1
    hintTitle.TextSize = 18
    hintTitle.Font = Enum.Font.GothamBold
    hintTitle.TextColor3 = Color3.fromRGB(255, 200, 100)
    hintTitle.TextXAlignment = Enum.TextXAlignment.Left
    hintTitle.Parent = hintFrame

    local hintDesc = Instance.new("TextLabel")
    hintDesc.Name = "HintDescription"
    hintDesc.Size = UDim2.new(1, -20, 0, 50)
    hintDesc.Position = UDim2.new(0, 10, 0, 40)
    hintDesc.BackgroundTransparency = 1
    hintDesc.TextSize = 14
    hintDesc.Font = Enum.Font.Gotham
    hintDesc.TextColor3 = Color3.new(1, 1, 1)
    hintDesc.TextXAlignment = Enum.TextXAlignment.Left
    hintDesc.TextWrapped = true
    hintDesc.Parent = hintFrame
end

--==============================================================================
-- TUTORIAL LOGIC
--==============================================================================

--[[
    Update the tutorial UI for the current step
    @param stepIndex number
]]
local function updateTutorialUI(stepIndex)
    local step = TUTORIAL_STEPS[stepIndex]
    if not step or not tutorialFrame then return end

    local icon = tutorialFrame:FindFirstChild("Icon")
    local title = tutorialFrame:FindFirstChild("Title")
    local description = tutorialFrame:FindFirstChild("Description")
    local button = tutorialFrame:FindFirstChild("ContinueButton")
    local stepIndicator = tutorialFrame:FindFirstChild("StepIndicator")

    if icon then icon.Text = step.icon or "?" end
    if title then title.Text = step.title or "" end
    if description then description.Text = step.description or "" end
    if button then button.Text = step.buttonText or "Continue" end
    if stepIndicator then
        stepIndicator.Text = string.format("Step %d of %d", stepIndex, #TUTORIAL_STEPS)
    end

    -- Animate in
    tutorialFrame.Position = UDim2.new(0.5, 0, 0.5, 50)
    tutorialFrame.BackgroundTransparency = 1

    TweenService:Create(tutorialFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
        Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundTransparency = 0,
    }):Play()
end

--==============================================================================
-- PUBLIC API
--==============================================================================

--[[
    Initialize the tutorial system
]]
function TutorialSystem:Initialize()
    if isInitialized then return self end

    createTutorialUI()
    createHintUI()

    isInitialized = true
    print("[TutorialSystem] Initialized")

    return self
end

--[[
    Check if player is new (first time playing)
    @return boolean
]]
function TutorialSystem:IsNewPlayer()
    -- For now, always show tutorial if never completed
    -- In production, check DataStore
    return #completedSteps == 0
end

--[[
    Start the tutorial from beginning
]]
function TutorialSystem:StartTutorial()
    if not isInitialized then return end

    isActive = true
    currentStep = 1
    screenGui.Enabled = true

    -- CRITICAL: Unlock mouse so buttons can be clicked
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled = true

    updateTutorialUI(currentStep)
end

--[[
    Move to next tutorial step
]]
function TutorialSystem:NextStep()
    if not isActive then return end

    local step = TUTORIAL_STEPS[currentStep]
    if step then
        completedSteps[step.id] = true
    end

    if currentStep >= #TUTORIAL_STEPS then
        self:CompleteTutorial()
        return
    end

    currentStep = currentStep + 1
    updateTutorialUI(currentStep)
end

--[[
    Skip the entire tutorial
]]
function TutorialSystem:SkipTutorial()
    -- Mark all steps as complete
    for _, step in ipairs(TUTORIAL_STEPS) do
        completedSteps[step.id] = true
    end

    self:CompleteTutorial()
end

--[[
    Complete the tutorial
]]
function TutorialSystem:CompleteTutorial()
    isActive = false
    currentStep = 0

    -- Fade out
    local overlay = screenGui:FindFirstChild("Overlay")
    if overlay then
        TweenService:Create(overlay, TweenInfo.new(0.5), {
            BackgroundTransparency = 1
        }):Play()
    end

    TweenService:Create(tutorialFrame, TweenInfo.new(0.3), {
        Position = UDim2.new(0.5, 0, 0.5, -50),
        BackgroundTransparency = 1,
    }):Play()

    task.delay(0.5, function()
        screenGui.Enabled = false
        -- CRITICAL: Re-lock mouse for gameplay after tutorial closes
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    end)

    print("[TutorialSystem] Tutorial completed!")
end

--[[
    Show a contextual hint during gameplay
    @param hintId string - Hint identifier
]]
function TutorialSystem:ShowHint(hintId)
    if not isInitialized then return end
    if isActive then return end -- Don't show hints during main tutorial

    -- Find the hint
    local hint = nil
    for _, h in ipairs(GAMEPLAY_HINTS) do
        if h.id == hintId then
            hint = h
            break
        end
    end

    if not hint then return end

    -- Check if one-time hint already shown
    if hint.oneTime and hintsShown[hintId] then
        return
    end

    hintsShown[hintId] = true

    -- Update hint UI
    if hintFrame then
        local title = hintFrame:FindFirstChild("HintTitle")
        local desc = hintFrame:FindFirstChild("HintDescription")

        if title then title.Text = hint.title or "" end
        if desc then desc.Text = hint.description or "" end

        -- Show with animation
        hintFrame.Visible = true
        hintFrame.Position = UDim2.new(0.5, 0, 0, 20)
        hintFrame.BackgroundTransparency = 1

        TweenService:Create(hintFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
            Position = UDim2.new(0.5, 0, 0, 80),
            BackgroundTransparency = 0.1,
        }):Play()

        -- Auto-hide after 5 seconds
        task.delay(5, function()
            TweenService:Create(hintFrame, TweenInfo.new(0.3), {
                Position = UDim2.new(0.5, 0, 0, 20),
                BackgroundTransparency = 1,
            }):Play()

            task.delay(0.3, function()
                hintFrame.Visible = false
            end)
        end)
    end
end

--[[
    Trigger a hint based on game event
    @param trigger string - Event trigger name
]]
function TutorialSystem:OnGameEvent(trigger)
    for _, hint in ipairs(GAMEPLAY_HINTS) do
        if hint.trigger == trigger then
            self:ShowHint(hint.id)
            return
        end
    end
end

--[[
    Check if tutorial is currently active
    @return boolean
]]
function TutorialSystem:IsActive()
    return isActive
end

--[[
    Get tutorial completion status
    @return table
]]
function TutorialSystem:GetProgress()
    return {
        currentStep = currentStep,
        totalSteps = #TUTORIAL_STEPS,
        completedSteps = completedSteps,
        isActive = isActive,
    }
end

--[[
    Reset tutorial progress (for testing)
]]
function TutorialSystem:Reset()
    completedSteps = {}
    hintsShown = {}
    currentStep = 0
    isActive = false
    if screenGui then
        screenGui.Enabled = false
    end
end

return TutorialSystem
