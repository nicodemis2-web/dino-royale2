--[[
    Dino Royale 2 - Core Framework
    Service locator pattern adapted from Evostrike architecture

    Usage:
        local Framework = require(game.ReplicatedStorage.Framework)
        local GameService = Framework:GetService("GameService")
        local DinoPlayer = Framework:GetModule("DinoPlayer")
]]

local Framework = {}
Framework.__index = Framework

-- Module type definitions
Framework.Types = {
    Class = "Class",
    Function = "Function",
    Service = "Service",
    Module = "Module",
    Utility = "Utility"
}

-- Internal storage
local services = {}
local modules = {}
local utilities = {}
local initialized = false
local isServer = game:GetService("RunService"):IsServer()

-- Configuration
Framework.Config = {
    DEBUG_MODE = true,
    LOG_LEVEL = "Info", -- Debug, Info, Warn, Error
    VERSION = "1.0.0"
}

--[[
    Logging utility
]]
local function log(level, message, ...)
    if not Framework.Config.DEBUG_MODE then return end

    local levels = {Debug = 1, Info = 2, Warn = 3, Error = 4}
    local currentLevel = levels[Framework.Config.LOG_LEVEL] or 2

    if levels[level] >= currentLevel then
        local prefix = string.format("[DinoRoyale][%s]", level)
        local formatted = string.format(message, ...)

        if level == "Error" then
            error(prefix .. " " .. formatted)
        elseif level == "Warn" then
            warn(prefix .. " " .. formatted)
        else
            print(prefix .. " " .. formatted)
        end
    end
end

Framework.Log = log

--[[
    Get a service by name
    Services are singletons that handle core game systems
]]
function Framework:GetService(serviceName)
    if services[serviceName] then
        return services[serviceName]
    end

    -- Attempt to load the service
    -- Rojo maps service/ to ReplicatedStorage.Service
    local serviceContainer = script.Parent:FindFirstChild("Service")
    if serviceContainer then
        local servicePath = serviceContainer:FindFirstChild(serviceName)
        if servicePath then
            local success, service = pcall(require, servicePath)
            if success then
                services[serviceName] = service
                log("Debug", "Loaded service: %s", serviceName)
                return service
            else
                log("Error", "Failed to load service %s: %s", serviceName, service)
            end
        end
    end

    log("Warn", "Service not found: %s", serviceName)
    return nil
end

--[[
    Get a module by name
    Modules are reusable components with specific functionality
]]
function Framework:GetModule(moduleName)
    if modules[moduleName] then
        return modules[moduleName]
    end

    -- Attempt to load the module
    -- Rojo maps module/ to ReplicatedStorage.Module
    local moduleContainer = script.Parent:FindFirstChild("Module")
    if moduleContainer then
        local modulePath = moduleContainer:FindFirstChild(moduleName)
        if modulePath then
            local success, mod = pcall(require, modulePath)
            if success then
                modules[moduleName] = mod
                log("Debug", "Loaded module: %s", moduleName)
                return mod
            else
                log("Error", "Failed to load module %s: %s", moduleName, mod)
            end
        end
    end

    log("Warn", "Module not found: %s", moduleName)
    return nil
end

--[[
    Get a utility library
]]
function Framework:GetUtility(utilityName)
    if utilities[utilityName] then
        return utilities[utilityName]
    end

    -- Attempt to load from shared/lib
    -- Rojo maps src/shared to ReplicatedStorage.Shared
    local sharedContainer = script.Parent:FindFirstChild("Shared")
    if sharedContainer then
        local libContainer = sharedContainer:FindFirstChild("lib")
        if libContainer then
            local libPath = libContainer:FindFirstChild(utilityName)
            if libPath then
                local success, util = pcall(require, libPath)
                if success then
                    utilities[utilityName] = util
                    log("Debug", "Loaded utility: %s", utilityName)
                    return util
                else
                    log("Error", "Failed to load utility %s: %s", utilityName, util)
                end
            end
        end
    end

    log("Warn", "Utility not found: %s", utilityName)
    return nil
end

--[[
    Register a service manually
]]
function Framework:RegisterService(name, service)
    if services[name] then
        log("Warn", "Service %s already registered, overwriting", name)
    end
    services[name] = service
    log("Debug", "Registered service: %s", name)
end

--[[
    Register a module manually
]]
function Framework:RegisterModule(name, mod)
    if modules[name] then
        log("Warn", "Module %s already registered, overwriting", name)
    end
    modules[name] = mod
    log("Debug", "Registered module: %s", name)
end

--[[
    Check if running on server
]]
function Framework:IsServer()
    return isServer
end

--[[
    Check if running on client
]]
function Framework:IsClient()
    return not isServer
end

--[[
    Initialize the framework
    Call this once at game start
]]
function Framework:Initialize()
    if initialized then
        log("Warn", "Framework already initialized")
        return
    end

    log("Info", "Initializing Dino Royale Framework v%s", Framework.Config.VERSION)

    -- Initialize core services in order
    -- Note: AudioService removed - not yet implemented
    local coreServices = {
        "GameService",
        "WeaponService",
        "StormService",
        "DinoService",
    }

    for _, serviceName in ipairs(coreServices) do
        local service = self:GetService(serviceName)
        if service and service.Initialize then
            local success, err = pcall(service.Initialize, service)
            if not success then
                log("Error", "Failed to initialize %s: %s", serviceName, err)
            else
                log("Info", "Initialized service: %s", serviceName)
            end
        end
    end

    initialized = true
    log("Info", "Framework initialization complete")
end

--[[
    Shutdown the framework gracefully
]]
function Framework:Shutdown()
    log("Info", "Shutting down framework...")

    for name, service in pairs(services) do
        if service.Shutdown then
            pcall(service.Shutdown, service)
        end
    end

    services = {}
    modules = {}
    utilities = {}
    initialized = false

    log("Info", "Framework shutdown complete")
end

--[[
    Wait for framework to be ready
]]
function Framework:WaitForReady()
    while not initialized do
        task.wait(0.1)
    end
    return true
end

return Framework
