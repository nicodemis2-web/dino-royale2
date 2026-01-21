--[[
    ================================================================================
    ObjectPool - High-Performance Object Pooling for Dino Royale 2
    ================================================================================

    This module provides efficient object pooling to reduce garbage collection
    overhead and improve performance for frequently created/destroyed objects:
    - Projectiles (bullets, rockets, grenades)
    - Particles/Effects (muzzle flash, impacts, explosions)
    - UI Elements (damage numbers, hit markers)
    - Audio sources (3D positioned sounds)

    How it works:
    - Pre-creates a pool of reusable objects
    - Objects are "acquired" from pool instead of creating new instances
    - Objects are "released" back to pool instead of being destroyed
    - Pool auto-expands if needed (with configurable limits)
    - Periodic cleanup removes excess pooled objects

    Performance Benefits:
    - Eliminates Instance.new() overhead during gameplay
    - Reduces garbage collection pauses
    - Consistent memory usage patterns
    - Faster object "creation" via pool acquisition

    Usage:
        local ObjectPool = require(game.ReplicatedStorage.Module.ObjectPool)
        ObjectPool:Initialize()

        -- Register a pool type
        ObjectPool:RegisterPool("Projectile", {
            create = function() return Instance.new("Part") end,
            reset = function(obj) obj.CFrame = CFrame.new(0, -1000, 0) end,
            initialSize = 20,
            maxSize = 100,
        })

        -- Get object from pool
        local projectile = ObjectPool:Acquire("Projectile")

        -- Return object to pool
        ObjectPool:Release("Projectile", projectile)

    Author: Dino Royale 2 Development Team
    Version: 1.0.0
    ================================================================================
]]

--!strict

--==============================================================================
-- SERVICES
--==============================================================================
local RunService = game:GetService("RunService")

--==============================================================================
-- TYPE DEFINITIONS
--==============================================================================

-- Pool configuration type
export type PoolConfig = {
    create: () -> Instance,
    reset: ((obj: Instance) -> ())?,
    initialSize: number?,
    maxSize: number?,
    autoExpand: boolean?,
}

-- Internal pool data type
type PoolData = {
    available: {Instance},
    inUse: {[Instance]: boolean},
    config: {
        create: () -> Instance,
        reset: (obj: Instance) -> (),
        initialSize: number,
        maxSize: number,
        autoExpand: boolean,
    },
    maxUsed: number,
}

-- Pool statistics type
export type PoolStats = {
    acquires: number,
    releases: number,
    creates: number,
    destroys: number,
}

-- Pool info type
export type PoolInfo = {
    available: number,
    inUse: number,
    total: number,
    maxSize: number,
    maxUsed: number,
}

--==============================================================================
-- MODULE DEFINITION
--==============================================================================
local ObjectPool = {}
ObjectPool.__index = ObjectPool

--==============================================================================
-- PRIVATE STATE
--==============================================================================
local pools: {[string]: PoolData} = {}
local isInitialized: boolean = false
local cleanupConnection: thread? = nil
local stats: PoolStats = {
    acquires = 0,
    releases = 0,
    creates = 0,
    destroys = 0,
}

--==============================================================================
-- CONFIGURATION
--==============================================================================
local CONFIG = {
    -- Cleanup settings
    cleanupInterval = 30,       -- Seconds between cleanup cycles
    excessThreshold = 1.5,      -- Remove objects if pool > maxUsed * threshold
    minPoolSize = 5,            -- Always keep at least this many objects

    -- Default pool settings
    defaultInitialSize = 10,
    defaultMaxSize = 50,
    defaultAutoExpand = true,
}

--==============================================================================
-- UTILITY FUNCTIONS
--==============================================================================

--[[
    Create the storage folder for pooled objects
    @return Folder
]]
local function getStorageFolder()
    local storage = workspace:FindFirstChild("_ObjectPoolStorage")
    if not storage then
        storage = Instance.new("Folder")
        storage.Name = "_ObjectPoolStorage"
        storage.Parent = workspace
    end
    return storage
end

--[[
    Move object to storage (hidden from game)
    @param obj Instance
]]
local function storeObject(obj)
    if obj:IsA("BasePart") then
        obj.CFrame = CFrame.new(0, -10000, 0)
        obj.Anchored = true
        obj.CanCollide = false
        obj.Parent = getStorageFolder()
    elseif obj:IsA("Model") then
        if obj.PrimaryPart then
            obj:SetPrimaryPartCFrame(CFrame.new(0, -10000, 0))
        end
        obj.Parent = getStorageFolder()
    else
        obj.Parent = getStorageFolder()
    end
end

--==============================================================================
-- POOL MANAGEMENT
--==============================================================================

--[[
    Initialize the ObjectPool system
]]
function ObjectPool:Initialize()
    if isInitialized then return self end

    -- Register built-in pool types
    self:RegisterBuiltInPools()

    -- Start cleanup cycle
    self:StartCleanupCycle()

    isInitialized = true
    print("[ObjectPool] Initialized")

    return self
end

--[[
    Register built-in pool types for common game objects
]]
function ObjectPool:RegisterBuiltInPools()
    -- Projectile pool (bullets, rockets)
    self:RegisterPool("Projectile", {
        create = function()
            local part = Instance.new("Part")
            part.Name = "PooledProjectile"
            part.Size = Vector3.new(0.5, 0.5, 1.5)
            part.Material = Enum.Material.Neon
            part.CanCollide = false
            part.Anchored = false

            -- Add BodyVelocity for movement
            local bv = Instance.new("BodyVelocity")
            bv.Name = "Velocity"
            bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bv.Velocity = Vector3.new(0, 0, 0)
            bv.Parent = part

            return part
        end,
        reset = function(obj)
            obj.CFrame = CFrame.new(0, -10000, 0)
            obj.Anchored = true
            obj.CanCollide = false
            obj.Transparency = 0
            local bv = obj:FindFirstChild("Velocity")
            if bv then bv.Velocity = Vector3.new(0, 0, 0) end
        end,
        initialSize = 30,
        maxSize = 100,
    })

    -- Throwable pool (grenades, molotovs)
    self:RegisterPool("Throwable", {
        create = function()
            local part = Instance.new("Part")
            part.Name = "PooledThrowable"
            part.Shape = Enum.PartType.Ball
            part.Size = Vector3.new(1, 1, 1)
            part.Material = Enum.Material.Metal
            part.CanCollide = true
            part.Anchored = false
            return part
        end,
        reset = function(obj)
            obj.CFrame = CFrame.new(0, -10000, 0)
            obj.Anchored = true
            obj.CanCollide = false
            obj.Transparency = 0
            obj.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            obj.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end,
        initialSize = 15,
        maxSize = 50,
    })

    -- Effect part pool (muzzle flash, impacts)
    self:RegisterPool("EffectPart", {
        create = function()
            local part = Instance.new("Part")
            part.Name = "PooledEffect"
            part.Size = Vector3.new(1, 1, 1)
            part.Material = Enum.Material.Neon
            part.Anchored = true
            part.CanCollide = false
            part.CastShadow = false
            return part
        end,
        reset = function(obj)
            obj.CFrame = CFrame.new(0, -10000, 0)
            obj.Transparency = 1
            obj.Size = Vector3.new(1, 1, 1)
            -- Remove any children (particles, lights, etc.)
            for _, child in ipairs(obj:GetChildren()) do
                if not child:IsA("Weld") then
                    child:Destroy()
                end
            end
        end,
        initialSize = 20,
        maxSize = 80,
    })

    -- Tracer beam pool (bullet trails)
    self:RegisterPool("TracerBeam", {
        create = function()
            local attachment0 = Instance.new("Attachment")
            attachment0.Name = "Start"

            local attachment1 = Instance.new("Attachment")
            attachment1.Name = "End"

            local beam = Instance.new("Beam")
            beam.Name = "PooledTracer"
            beam.Attachment0 = attachment0
            beam.Attachment1 = attachment1
            beam.Width0 = 0.1
            beam.Width1 = 0.1
            beam.FaceCamera = true
            beam.LightEmission = 1
            beam.Brightness = 2
            beam.Color = ColorSequence.new(Color3.fromRGB(255, 200, 100))
            beam.Transparency = NumberSequence.new(0)

            -- Container model
            local container = Instance.new("Model")
            container.Name = "TracerContainer"
            attachment0.Parent = container
            attachment1.Parent = container
            beam.Parent = container

            return container
        end,
        reset = function(obj)
            local start = obj:FindFirstChild("Start")
            local endAtt = obj:FindFirstChild("End")
            if start and endAtt then
                start.WorldPosition = Vector3.new(0, -10000, 0)
                endAtt.WorldPosition = Vector3.new(0, -10000, 0)
            end
        end,
        initialSize = 25,
        maxSize = 100,
    })

    -- Hit marker pool (UI feedback)
    self:RegisterPool("HitMarker", {
        create = function()
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "PooledHitMarker"
            billboard.Size = UDim2.new(0, 50, 0, 50)
            billboard.StudsOffset = Vector3.new(0, 2, 0)
            billboard.AlwaysOnTop = true

            local label = Instance.new("TextLabel")
            label.Name = "Text"
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.TextColor3 = Color3.new(1, 1, 1)
            label.TextStrokeTransparency = 0.5
            label.TextStrokeColor3 = Color3.new(0, 0, 0)
            label.Font = Enum.Font.GothamBold
            label.TextSize = 20
            label.Parent = billboard

            return billboard
        end,
        reset = function(obj)
            obj.Adornee = nil
            obj.Enabled = false
            local label = obj:FindFirstChild("Text")
            if label then
                label.Text = ""
            end
        end,
        initialSize = 15,
        maxSize = 40,
    })

    -- 3D Sound pool
    self:RegisterPool("Sound3D", {
        create = function()
            local part = Instance.new("Part")
            part.Name = "PooledSoundEmitter"
            part.Size = Vector3.new(0.1, 0.1, 0.1)
            part.Transparency = 1
            part.Anchored = true
            part.CanCollide = false

            local sound = Instance.new("Sound")
            sound.Name = "Sound"
            sound.RollOffMode = Enum.RollOffMode.InverseTapered
            sound.RollOffMinDistance = 10
            sound.RollOffMaxDistance = 200
            sound.Parent = part

            return part
        end,
        reset = function(obj)
            obj.CFrame = CFrame.new(0, -10000, 0)
            local sound = obj:FindFirstChild("Sound")
            if sound then
                sound:Stop()
                sound.SoundId = ""
                sound.Volume = 1
                sound.PlaybackSpeed = 1
            end
        end,
        initialSize = 20,
        maxSize = 60,
    })
end

--[[
    Register a new pool type
    @param poolName string - Unique identifier for this pool
    @param config table - Pool configuration
        - create: function() -> Instance (creates new pooled object)
        - reset: function(obj) (resets object to default state)
        - initialSize: number (pre-create this many objects)
        - maxSize: number (max pool size)
        - autoExpand: boolean (create new objects if pool is empty)
]]
function ObjectPool:RegisterPool(poolName, config)
    if pools[poolName] then
        warn("[ObjectPool] Pool already exists: " .. poolName)
        return
    end

    local poolConfig = {
        create = config.create,
        reset = config.reset or function() end,
        initialSize = config.initialSize or CONFIG.defaultInitialSize,
        maxSize = config.maxSize or CONFIG.defaultMaxSize,
        autoExpand = config.autoExpand ~= false,
    }

    pools[poolName] = {
        available = {},
        inUse = {},
        config = poolConfig,
        maxUsed = 0,
    }

    -- Pre-populate pool
    for i = 1, poolConfig.initialSize do
        local obj = poolConfig.create()
        storeObject(obj)
        table.insert(pools[poolName].available, obj)
        stats.creates = stats.creates + 1
    end

    print(string.format("[ObjectPool] Registered pool '%s' with %d initial objects",
        poolName, poolConfig.initialSize))
end

--[[
    Acquire an object from a pool
    @param poolName string - Pool to acquire from
    @return Instance|nil - The acquired object, or nil if pool is full
]]
function ObjectPool:Acquire(poolName)
    local pool = pools[poolName]
    if not pool then
        warn("[ObjectPool] Unknown pool: " .. poolName)
        return nil
    end

    local obj

    if #pool.available > 0 then
        -- Get from pool
        obj = table.remove(pool.available)
    elseif pool.config.autoExpand and #pool.inUse < pool.config.maxSize then
        -- Create new object
        obj = pool.config.create()
        stats.creates = stats.creates + 1
    else
        -- Pool exhausted
        warn(string.format("[ObjectPool] Pool '%s' exhausted (%d/%d in use)",
            poolName, #pool.inUse, pool.config.maxSize))
        return nil
    end

    -- Track in-use
    pool.inUse[obj] = true
    pool.maxUsed = math.max(pool.maxUsed, #pool.inUse + #pool.available)

    stats.acquires = stats.acquires + 1

    return obj
end

--[[
    Release an object back to its pool
    @param poolName string - Pool to release to
    @param obj Instance - Object to release
]]
function ObjectPool:Release(poolName, obj)
    local pool = pools[poolName]
    if not pool then
        warn("[ObjectPool] Unknown pool: " .. poolName)
        return
    end

    if not pool.inUse[obj] then
        -- Object wasn't from this pool, just destroy it
        obj:Destroy()
        return
    end

    -- Remove from in-use tracking
    pool.inUse[obj] = nil

    -- Reset object state
    pool.config.reset(obj)
    storeObject(obj)

    -- Add back to available pool
    table.insert(pool.available, obj)

    stats.releases = stats.releases + 1
end

--[[
    Release an object after a delay (auto-release)
    @param poolName string
    @param obj Instance
    @param delay number - Seconds before release
]]
function ObjectPool:ReleaseAfter(poolName, obj, delay)
    task.delay(delay, function()
        if obj and obj.Parent then
            self:Release(poolName, obj)
        end
    end)
end

--==============================================================================
-- CLEANUP & STATS
--==============================================================================

--[[
    Start the periodic cleanup cycle
]]
function ObjectPool:StartCleanupCycle()
    if cleanupConnection then return end

    cleanupConnection = task.spawn(function()
        while true do
            task.wait(CONFIG.cleanupInterval)
            self:Cleanup()
        end
    end)
end

--[[
    Cleanup excess pooled objects
]]
function ObjectPool:Cleanup()
    for poolName, pool in pairs(pools) do
        local targetSize = math.max(
            CONFIG.minPoolSize,
            math.floor(pool.maxUsed * CONFIG.excessThreshold)
        )

        while #pool.available > targetSize do
            local obj = table.remove(pool.available)
            if obj then
                obj:Destroy()
                stats.destroys = stats.destroys + 1
            end
        end

        -- Reset max used tracking
        pool.maxUsed = #pool.inUse
    end
end

--[[
    Get pool statistics
    @return table
]]
function ObjectPool:GetStats()
    local poolStats = {}

    for poolName, pool in pairs(pools) do
        poolStats[poolName] = {
            available = #pool.available,
            inUse = 0,
            maxUsed = pool.maxUsed,
            maxSize = pool.config.maxSize,
        }
        -- Count in-use
        for _ in pairs(pool.inUse) do
            poolStats[poolName].inUse = poolStats[poolName].inUse + 1
        end
    end

    return {
        pools = poolStats,
        totals = stats,
    }
end

--[[
    Get info about a specific pool
    @param poolName string
    @return table|nil
]]
function ObjectPool:GetPoolInfo(poolName)
    local pool = pools[poolName]
    if not pool then return nil end

    local inUseCount = 0
    for _ in pairs(pool.inUse) do
        inUseCount = inUseCount + 1
    end

    return {
        available = #pool.available,
        inUse = inUseCount,
        total = #pool.available + inUseCount,
        maxSize = pool.config.maxSize,
        maxUsed = pool.maxUsed,
    }
end

--[[
    Clear all pools (used during match reset)
]]
function ObjectPool:ClearAll()
    for poolName, pool in pairs(pools) do
        -- Destroy all available objects
        for _, obj in ipairs(pool.available) do
            obj:Destroy()
            stats.destroys = stats.destroys + 1
        end
        pool.available = {}

        -- Destroy all in-use objects
        for obj, _ in pairs(pool.inUse) do
            obj:Destroy()
            stats.destroys = stats.destroys + 1
        end
        pool.inUse = {}

        pool.maxUsed = 0
    end

    print("[ObjectPool] All pools cleared")
end

--[[
    Pre-warm a specific pool (useful before match start)
    @param poolName string
    @param count number - Number of objects to pre-create
]]
function ObjectPool:PreWarm(poolName, count)
    local pool = pools[poolName]
    if not pool then return end

    local toCreate = math.min(count, pool.config.maxSize - #pool.available)

    for i = 1, toCreate do
        local obj = pool.config.create()
        storeObject(obj)
        table.insert(pool.available, obj)
        stats.creates = stats.creates + 1
    end

    print(string.format("[ObjectPool] Pre-warmed '%s' with %d objects", poolName, toCreate))
end

return ObjectPool
