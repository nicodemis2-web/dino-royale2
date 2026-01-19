--[[
    Dino Royale 2 - Server Framework Bootstrap
    This is the main server entry point that initializes all services
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Wait for required folders to exist
local function ensureFolders()
    -- Create Remotes folder
    if not ReplicatedStorage:FindFirstChild("Remotes") then
        local remotes = Instance.new("Folder")
        remotes.Name = "Remotes"
        remotes.Parent = ReplicatedStorage
    end

    -- Create Dinosaurs folder in workspace
    if not workspace:FindFirstChild("Dinosaurs") then
        local dinos = Instance.new("Folder")
        dinos.Name = "Dinosaurs"
        dinos.Parent = workspace
    end

    -- Create GroundLoot folder
    if not workspace:FindFirstChild("GroundLoot") then
        local loot = Instance.new("Folder")
        loot.Name = "GroundLoot"
        loot.Parent = workspace
    end

    -- Create GroundWeapons folder
    if not workspace:FindFirstChild("GroundWeapons") then
        local weapons = Instance.new("Folder")
        weapons.Name = "GroundWeapons"
        weapons.Parent = workspace
    end

    -- Create Chests folder
    if not workspace:FindFirstChild("Chests") then
        local chests = Instance.new("Folder")
        chests.Name = "Chests"
        chests.Parent = workspace
    end

    -- Create ServerStorage folders
    if not ServerStorage:FindFirstChild("Dinosaurs") then
        local dinos = Instance.new("Folder")
        dinos.Name = "Dinosaurs"
        dinos.Parent = ServerStorage
    end

    if not ServerStorage:FindFirstChild("Weapons") then
        local weapons = Instance.new("Folder")
        weapons.Name = "Weapons"
        weapons.Parent = ServerStorage
    end
end

-- Main initialization
local function initialize()
    print("[DinoRoyale] Server starting...")

    -- Ensure all required folders exist
    ensureFolders()

    -- Load the framework
    -- Rojo maps framework/ to ReplicatedStorage.Framework
    local Framework = require(ReplicatedStorage:WaitForChild("Framework"))

    -- Initialize the framework (this will load all services)
    Framework:Initialize()

    -- Get services for manual setup if needed
    local GameService = Framework:GetService("GameService")
    local WeaponService = Framework:GetService("WeaponService")
    local StormService = Framework:GetService("StormService")
    local DinoService = Framework:GetService("DinoService")

    -- Initialize modules
    local SquadSystem = Framework:GetModule("SquadSystem")
    if SquadSystem then
        SquadSystem:Initialize()
    end

    local LootSystem = Framework:GetModule("LootSystem")
    if LootSystem then
        LootSystem:Initialize()
    end

    print("[DinoRoyale] Server initialization complete!")
    print("[DinoRoyale] Waiting for players...")
end

-- Handle critical errors
local success, errorMessage = pcall(initialize)
if not success then
    warn("[DinoRoyale] CRITICAL ERROR during server initialization:")
    warn(errorMessage)
end
