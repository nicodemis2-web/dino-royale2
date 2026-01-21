--[[
    ================================================================================
    TouchControls - Mobile/Touch Input System for Dino Royale 2
    ================================================================================

    This module provides touch-based controls for mobile devices:
    - Virtual joystick for movement (left side)
    - Fire button (right side)
    - Aim/ADS button (right side)
    - Reload button
    - Weapon slot buttons
    - Jump button

    Features:
    - Auto-detection of touch devices
    - Customizable button positions/sizes
    - Transparent overlays for better visibility
    - Haptic feedback support (vibration)
    - Dynamic hiding when not on touch device

    Usage:
        local TouchControls = require(game.ReplicatedStorage.Module.TouchControls)
        TouchControls:Initialize()

        -- Check if touch device
        if TouchControls:IsTouchDevice() then
            TouchControls:SetEnabled(true)
        end

    Author: Dino Royale 2 Development Team
    Version: 1.0.0
    ================================================================================
]]

--==============================================================================
-- SERVICES
--==============================================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HapticService = game:GetService("HapticService")
local GuiService = game:GetService("GuiService")

--==============================================================================
-- MODULE DEFINITION
--==============================================================================
local TouchControls = {}
TouchControls.__index = TouchControls

--==============================================================================
-- PRIVATE STATE
--==============================================================================
local player = Players.LocalPlayer
local screenGui = nil
local isInitialized = false
local isEnabled = false
local isTouchDevice = false

-- UI References
local leftJoystickFrame = nil
local leftJoystickThumb = nil
local fireButton = nil
local aimButton = nil
local reloadButton = nil
local jumpButton = nil
local weaponSlotButtons = {}

-- Joystick state
local joystickState = {
    active = false,
    startPosition = Vector2.new(0, 0),
    currentPosition = Vector2.new(0, 0),
    direction = Vector2.new(0, 0),
    touchId = nil,
}

-- Button states
local buttonStates = {
    fire = false,
    aim = false,
    reload = false,
    jump = false,
}

-- Callbacks (set by client)
local callbacks = {
    onMove = nil,           -- function(direction: Vector2)
    onFire = nil,           -- function(isPressed: boolean)
    onAim = nil,            -- function(isPressed: boolean)
    onReload = nil,         -- function()
    onJump = nil,           -- function()
    onWeaponSlot = nil,     -- function(slot: number)
}

--==============================================================================
-- CONFIGURATION
--==============================================================================
local CONFIG = {
    -- Joystick settings
    joystickSize = 150,
    joystickThumbSize = 60,
    joystickMaxDistance = 50,
    joystickPosition = UDim2.new(0, 50, 1, -200),

    -- Button sizes
    fireButtonSize = 100,
    aimButtonSize = 80,
    smallButtonSize = 60,

    -- Colors
    backgroundColor = Color3.fromRGB(30, 30, 30),
    accentColor = Color3.fromRGB(200, 50, 50),
    aimColor = Color3.fromRGB(50, 150, 200),
    reloadColor = Color3.fromRGB(100, 200, 100),

    -- Transparency
    baseTransparency = 0.6,
    activeTransparency = 0.3,

    -- Haptic feedback
    enableHaptics = true,
    hapticIntensity = 0.5,
}

--==============================================================================
-- UTILITY FUNCTIONS
--==============================================================================

--[[
    Check if device supports touch input
    @return boolean
]]
local function detectTouchDevice()
    return UserInputService.TouchEnabled
end

--[[
    Create a circular button UI element
    @param name string - Button name
    @param size number - Button diameter
    @param position UDim2 - Button position
    @param color Color3 - Button color
    @param text string - Button text/icon
    @return Frame
]]
local function createCircularButton(name, size, position, color, text)
    local button = Instance.new("Frame")
    button.Name = name
    button.Size = UDim2.new(0, size, 0, size)
    button.Position = position
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    button.BackgroundColor3 = color
    button.BackgroundTransparency = CONFIG.baseTransparency
    button.BorderSizePixel = 0

    -- Make it circular
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = button

    -- Add stroke
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(1, 1, 1)
    stroke.Thickness = 2
    stroke.Transparency = 0.5
    stroke.Parent = button

    -- Add text label
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextSize = size * 0.35
    label.Font = Enum.Font.GothamBold
    label.Parent = button

    return button
end

--[[
    Trigger haptic feedback
    @param intensity number - 0 to 1
]]
local function triggerHaptic(intensity)
    if not CONFIG.enableHaptics then return end

    pcall(function()
        HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, intensity or CONFIG.hapticIntensity)
        task.delay(0.1, function()
            HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
        end)
    end)
end

--[[
    Animate button press
    @param button Frame
    @param pressed boolean
]]
local function animateButton(button, pressed)
    local targetTransparency = pressed and CONFIG.activeTransparency or CONFIG.baseTransparency
    local targetScale = pressed and 0.9 or 1

    local tween = TweenService:Create(button, TweenInfo.new(0.1), {
        BackgroundTransparency = targetTransparency,
    })
    tween:Play()
end

--==============================================================================
-- JOYSTICK SYSTEM
--==============================================================================

--[[
    Create the virtual joystick
]]
local function createJoystick()
    -- Joystick background/boundary
    leftJoystickFrame = Instance.new("Frame")
    leftJoystickFrame.Name = "LeftJoystick"
    leftJoystickFrame.Size = UDim2.new(0, CONFIG.joystickSize, 0, CONFIG.joystickSize)
    leftJoystickFrame.Position = CONFIG.joystickPosition
    leftJoystickFrame.AnchorPoint = Vector2.new(0, 1)
    leftJoystickFrame.BackgroundColor3 = CONFIG.backgroundColor
    leftJoystickFrame.BackgroundTransparency = CONFIG.baseTransparency
    leftJoystickFrame.BorderSizePixel = 0
    leftJoystickFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = leftJoystickFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(1, 1, 1)
    stroke.Thickness = 2
    stroke.Transparency = 0.5
    stroke.Parent = leftJoystickFrame

    -- Joystick thumb (movable center)
    leftJoystickThumb = Instance.new("Frame")
    leftJoystickThumb.Name = "Thumb"
    leftJoystickThumb.Size = UDim2.new(0, CONFIG.joystickThumbSize, 0, CONFIG.joystickThumbSize)
    leftJoystickThumb.Position = UDim2.new(0.5, 0, 0.5, 0)
    leftJoystickThumb.AnchorPoint = Vector2.new(0.5, 0.5)
    leftJoystickThumb.BackgroundColor3 = Color3.new(1, 1, 1)
    leftJoystickThumb.BackgroundTransparency = 0.3
    leftJoystickThumb.BorderSizePixel = 0
    leftJoystickThumb.Parent = leftJoystickFrame

    local thumbCorner = Instance.new("UICorner")
    thumbCorner.CornerRadius = UDim.new(1, 0)
    thumbCorner.Parent = leftJoystickThumb
end

--[[
    Handle joystick touch input
    @param touchPositions table - Touch positions
    @param gameProcessed boolean
]]
local function handleJoystickTouch(input, phase)
    local touchPos = input.Position

    -- Get joystick center in screen space
    local joystickCenter = leftJoystickFrame.AbsolutePosition +
        Vector2.new(leftJoystickFrame.AbsoluteSize.X / 2, leftJoystickFrame.AbsoluteSize.Y / 2)

    -- Check if touch is within joystick area
    local touchVec = Vector2.new(touchPos.X, touchPos.Y)
    local distanceFromCenter = (touchVec - joystickCenter).Magnitude

    if phase == "begin" then
        -- Check if touch started within joystick region (with some padding)
        local maxStartDistance = CONFIG.joystickSize * 0.75
        if distanceFromCenter <= maxStartDistance then
            joystickState.active = true
            joystickState.touchId = input
            joystickState.startPosition = joystickCenter
            triggerHaptic(0.3)
        end
    elseif phase == "changed" and joystickState.active then
        -- Calculate direction
        local offset = touchVec - joystickState.startPosition
        local distance = offset.Magnitude

        -- Clamp to max distance
        if distance > CONFIG.joystickMaxDistance then
            offset = offset.Unit * CONFIG.joystickMaxDistance
        end

        -- Update thumb position
        local normalizedOffset = offset / CONFIG.joystickMaxDistance
        leftJoystickThumb.Position = UDim2.new(
            0.5 + normalizedOffset.X * 0.35,
            0,
            0.5 + normalizedOffset.Y * 0.35,
            0
        )

        -- Store direction
        joystickState.direction = normalizedOffset

        -- Call movement callback
        if callbacks.onMove then
            callbacks.onMove(joystickState.direction)
        end
    elseif phase == "ended" then
        if joystickState.active then
            joystickState.active = false
            joystickState.direction = Vector2.new(0, 0)
            joystickState.touchId = nil

            -- Reset thumb position
            leftJoystickThumb.Position = UDim2.new(0.5, 0, 0.5, 0)

            -- Call movement callback with zero
            if callbacks.onMove then
                callbacks.onMove(Vector2.new(0, 0))
            end
        end
    end
end

--==============================================================================
-- BUTTON CREATION
--==============================================================================

--[[
    Create all control buttons
]]
local function createButtons()
    local screenSize = screenGui.AbsoluteSize
    local bottomPadding = 50 + GuiService:GetGuiInset().Y

    -- Fire button (large, bottom right)
    fireButton = createCircularButton(
        "FireButton",
        CONFIG.fireButtonSize,
        UDim2.new(1, -80, 1, -120 - bottomPadding),
        CONFIG.accentColor,
        "FIRE"
    )
    fireButton.Parent = screenGui

    -- Aim button (above fire button)
    aimButton = createCircularButton(
        "AimButton",
        CONFIG.aimButtonSize,
        UDim2.new(1, -160, 1, -120 - bottomPadding),
        CONFIG.aimColor,
        "AIM"
    )
    aimButton.Parent = screenGui

    -- Reload button (left of aim)
    reloadButton = createCircularButton(
        "ReloadButton",
        CONFIG.smallButtonSize,
        UDim2.new(1, -80, 1, -230 - bottomPadding),
        CONFIG.reloadColor,
        "R"
    )
    reloadButton.Parent = screenGui

    -- Jump button (between joystick and fire)
    jumpButton = createCircularButton(
        "JumpButton",
        CONFIG.smallButtonSize,
        UDim2.new(0.5, 100, 1, -100 - bottomPadding),
        CONFIG.backgroundColor,
        "⬆"
    )
    jumpButton.Parent = screenGui

    -- Weapon slot buttons (top of screen, horizontal)
    local slotStartX = 100
    local slotSpacing = 70

    for i = 1, 5 do
        local slotButton = createCircularButton(
            "WeaponSlot" .. i,
            50,
            UDim2.new(0, slotStartX + (i - 1) * slotSpacing, 0, 80),
            CONFIG.backgroundColor,
            tostring(i)
        )
        slotButton.Parent = screenGui
        weaponSlotButtons[i] = slotButton
    end
end

--[[
    Setup button touch handlers
]]
local function setupButtonHandlers()
    -- Helper function to handle button touches
    local function setupButton(button, onPress, onRelease)
        local touchStarted = false

        -- Use Touch events for better mobile response
        button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then
                touchStarted = true
                animateButton(button, true)
                triggerHaptic(CONFIG.hapticIntensity)
                if onPress then onPress() end
            end
        end)

        button.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch and touchStarted then
                touchStarted = false
                animateButton(button, false)
                if onRelease then onRelease() end
            end
        end)
    end

    -- Fire button
    setupButton(fireButton,
        function()
            buttonStates.fire = true
            if callbacks.onFire then callbacks.onFire(true) end
        end,
        function()
            buttonStates.fire = false
            if callbacks.onFire then callbacks.onFire(false) end
        end
    )

    -- Aim button
    setupButton(aimButton,
        function()
            buttonStates.aim = true
            if callbacks.onAim then callbacks.onAim(true) end
        end,
        function()
            buttonStates.aim = false
            if callbacks.onAim then callbacks.onAim(false) end
        end
    )

    -- Reload button
    setupButton(reloadButton,
        function()
            if callbacks.onReload then callbacks.onReload() end
        end
    )

    -- Jump button
    setupButton(jumpButton,
        function()
            if callbacks.onJump then callbacks.onJump() end
        end
    )

    -- Weapon slot buttons
    for i, slotButton in ipairs(weaponSlotButtons) do
        setupButton(slotButton,
            function()
                if callbacks.onWeaponSlot then callbacks.onWeaponSlot(i) end
            end
        )
    end
end

--==============================================================================
-- TOUCH INPUT HANDLING
--==============================================================================

--[[
    Global touch input handler
]]
local function setupTouchInput()
    UserInputService.TouchStarted:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if not isEnabled then return end

        handleJoystickTouch(input, "begin")
    end)

    UserInputService.TouchMoved:Connect(function(input, gameProcessed)
        if not isEnabled then return end

        handleJoystickTouch(input, "changed")
    end)

    UserInputService.TouchEnded:Connect(function(input, gameProcessed)
        if not isEnabled then return end

        handleJoystickTouch(input, "ended")
    end)
end

--==============================================================================
-- PUBLIC API
--==============================================================================

--[[
    Initialize the touch controls system
]]
function TouchControls:Initialize()
    if isInitialized then return self end

    -- Detect device type
    isTouchDevice = detectTouchDevice()

    -- Create screen GUI
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TouchControls"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 100
    screenGui.Enabled = false
    screenGui.Parent = player:WaitForChild("PlayerGui")

    -- Create UI elements
    createJoystick()
    createButtons()
    setupButtonHandlers()
    setupTouchInput()

    -- Auto-enable on touch devices
    if isTouchDevice then
        self:SetEnabled(true)
    end

    isInitialized = true
    print("[TouchControls] Initialized (Touch device: " .. tostring(isTouchDevice) .. ")")

    return self
end

--[[
    Check if this is a touch device
    @return boolean
]]
function TouchControls:IsTouchDevice()
    return isTouchDevice
end

--[[
    Enable or disable touch controls
    @param enabled boolean
]]
function TouchControls:SetEnabled(enabled)
    isEnabled = enabled
    if screenGui then
        screenGui.Enabled = enabled
    end
end

--[[
    Get if touch controls are enabled
    @return boolean
]]
function TouchControls:IsEnabled()
    return isEnabled
end

--[[
    Set callback for movement input
    @param callback function(direction: Vector2)
]]
function TouchControls:SetMoveCallback(callback)
    callbacks.onMove = callback
end

--[[
    Set callback for fire input
    @param callback function(isPressed: boolean)
]]
function TouchControls:SetFireCallback(callback)
    callbacks.onFire = callback
end

--[[
    Set callback for aim input
    @param callback function(isPressed: boolean)
]]
function TouchControls:SetAimCallback(callback)
    callbacks.onAim = callback
end

--[[
    Set callback for reload input
    @param callback function()
]]
function TouchControls:SetReloadCallback(callback)
    callbacks.onReload = callback
end

--[[
    Set callback for jump input
    @param callback function()
]]
function TouchControls:SetJumpCallback(callback)
    callbacks.onJump = callback
end

--[[
    Set callback for weapon slot selection
    @param callback function(slot: number)
]]
function TouchControls:SetWeaponSlotCallback(callback)
    callbacks.onWeaponSlot = callback
end

--[[
    Get current joystick direction
    @return Vector2
]]
function TouchControls:GetMoveDirection()
    return joystickState.direction
end

--[[
    Get current button states
    @return table
]]
function TouchControls:GetButtonStates()
    return buttonStates
end

--[[
    Highlight a weapon slot
    @param slot number - Slot to highlight (1-5)
]]
function TouchControls:HighlightWeaponSlot(slot)
    for i, button in ipairs(weaponSlotButtons) do
        if i == slot then
            button.BackgroundColor3 = CONFIG.accentColor
        else
            button.BackgroundColor3 = CONFIG.backgroundColor
        end
    end
end

--[[
    Update button visibility based on game state
    @param state string - Game state (Lobby, Match, etc.)
]]
function TouchControls:UpdateForGameState(state)
    local showCombatControls = (state == "Match" or state == "Dropping")

    if fireButton then fireButton.Visible = showCombatControls end
    if aimButton then aimButton.Visible = showCombatControls end
    if reloadButton then reloadButton.Visible = showCombatControls end

    for _, button in ipairs(weaponSlotButtons) do
        button.Visible = showCombatControls
    end
end

--[[
    Cleanup touch controls
]]
function TouchControls:Cleanup()
    if screenGui then
        screenGui:Destroy()
        screenGui = nil
    end

    isInitialized = false
    isEnabled = false
end

return TouchControls
