--[[
    Dino Royale 2 - Client Framework Bootstrap
    This is the main client entry point that initializes UI and client systems
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

-- Wait for character
local function waitForCharacter()
    if player.Character then
        return player.Character
    end
    return player.CharacterAdded:Wait()
end

-- Main initialization
local function initialize()
    print("[DinoRoyale] Client starting...")

    -- Wait for Remotes folder to be created by server
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
    if not remotes then
        warn("[DinoRoyale] Remotes folder not found after 30 seconds")
        return
    end

    -- Load the framework
    -- Rojo maps framework/ to ReplicatedStorage.Framework
    local Framework = require(ReplicatedStorage:WaitForChild("Framework"))

    -- Wait for framework to be ready
    Framework:WaitForReady()

    -- Initialize HUD
    local DinoHUD = Framework:GetModule("DinoHUD")
    if DinoHUD then
        DinoHUD:Initialize()
    end

    -- Setup input handling
    setupInputHandling(Framework)

    -- Setup character events
    setupCharacterEvents(Framework)

    print("[DinoRoyale] Client initialization complete!")
end

-- Setup keyboard/mouse input handling
function setupInputHandling(Framework)
    local weaponService = Framework:GetService("WeaponService")
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")

    -- Weapon slot selection (1-5)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        -- Number keys for weapon slots
        if input.KeyCode == Enum.KeyCode.One then
            remotes.WeaponEquip:FireServer(1)
        elseif input.KeyCode == Enum.KeyCode.Two then
            remotes.WeaponEquip:FireServer(2)
        elseif input.KeyCode == Enum.KeyCode.Three then
            remotes.WeaponEquip:FireServer(3)
        elseif input.KeyCode == Enum.KeyCode.Four then
            remotes.WeaponEquip:FireServer(4)
        elseif input.KeyCode == Enum.KeyCode.Five then
            remotes.WeaponEquip:FireServer(5)
        elseif input.KeyCode == Enum.KeyCode.R then
            -- Reload current weapon
            -- Get current slot from inventory and reload
            local inventory = weaponService and weaponService:GetPlayerInventory(player)
            if inventory and inventory.equipped > 0 then
                remotes.WeaponReload:FireServer(inventory.equipped)
            end
        elseif input.KeyCode == Enum.KeyCode.G then
            -- Drop current weapon
            local inventory = weaponService and weaponService:GetPlayerInventory(player)
            if inventory and inventory.equipped > 0 then
                remotes.WeaponDrop:FireServer(inventory.equipped)
            end
        end
    end)

    -- Mouse handling for shooting
    local mouse = player:GetMouse()

    mouse.Button1Down:Connect(function()
        -- Fire weapon
        local character = player.Character
        if not character then return end

        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then return end

        -- Raycast to find hit
        local camera = workspace.CurrentCamera
        local mousePos = UserInputService:GetMouseLocation()
        local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = {character}

        local result = workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)

        local fireData = {
            origin = humanoidRootPart.Position,
            direction = ray.Direction,
            hit = result and result.Instance or nil,
            hitPosition = result and result.Position or nil,
            hitPart = result and result.Instance and result.Instance.Name or nil,
        }

        if remotes and remotes:FindFirstChild("WeaponFire") then
            remotes.WeaponFire:FireServer(fireData)
        end
    end)
end

-- Setup character-related events
function setupCharacterEvents(Framework)
    local function onCharacterAdded(character)
        -- Wait for humanoid
        local humanoid = character:WaitForChild("Humanoid")

        -- Handle death
        humanoid.Died:Connect(function()
            print("[DinoRoyale] Player died")
            -- Could trigger death screen, spectate mode, etc.
        end)

        -- Handle damage for damage indicators
        local currentHealth = humanoid.Health
        humanoid.HealthChanged:Connect(function(newHealth)
            if newHealth < currentHealth then
                -- Took damage
                local DinoHUD = Framework:GetModule("DinoHUD")
                if DinoHUD and DinoHUD.ShowDamageIndicator then
                    DinoHUD:ShowDamageIndicator(0) -- Direction would be calculated from attacker
                end
            end
            currentHealth = newHealth
        end)
    end

    -- Connect for current and future characters
    player.CharacterAdded:Connect(onCharacterAdded)

    if player.Character then
        onCharacterAdded(player.Character)
    end
end

-- Handle critical errors
local success, errorMessage = pcall(initialize)
if not success then
    warn("[DinoRoyale] CRITICAL ERROR during client initialization:")
    warn(errorMessage)
end
