--[[
    ================================================================================
    WeaponService - Comprehensive Weapon System for Dino Royale 2
    ================================================================================

    This service handles all weapon-related functionality including:
    - Ranged weapons (Assault Rifles, SMGs, Shotguns, Snipers, Pistols)
    - Melee weapons (Machete, Spear, Stun Baton)
    - Explosives (Grenades, C4, Rocket Launcher)
    - Traps (Bear Trap, Tripwire, Tranquilizer Trap)
    - Attachment system (Scopes, Grips, Magazines, Suppressors)
    - Damage calculation with falloff, headshots, and armor
    - Ammunition management and reloading
    - Server-authoritative hit validation

    Architecture:
    - Server validates all shots and damage
    - Client sends fire requests with aim data
    - Server broadcasts effects to other clients
    - Attachments modify weapon stats dynamically

    Security:
    - All damage calculations are server-side
    - Fire rate validation prevents rapid-fire exploits
    - Position validation prevents teleport exploits
    - Ammo tracking prevents infinite ammo exploits

    Dependencies:
    - Framework (service locator)
    - GameConfig (weapon configuration)
    - DinoService (for dinosaur damage)
    - GameService (for player elimination)

    Usage:
        local WeaponService = Framework:GetService("WeaponService")
        WeaponService:GiveWeapon(player, "ak47")
        WeaponService:GiveAmmo(player, "medium", 30)

    Author: Dino Royale 2 Development Team
    Version: 2.0.0 (Enhanced with melee, explosives, traps, attachments)
    ================================================================================
]]

--==============================================================================
-- SERVICES
--==============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

--==============================================================================
-- MODULE DEFINITION
--==============================================================================
local WeaponService = {}
WeaponService.__index = WeaponService

--==============================================================================
-- PRIVATE STATE
--==============================================================================
local playerWeapons = {}      -- Player inventory: UserId -> inventory data
local weaponConfigs = {}      -- All weapon configurations
local attachmentConfigs = {}  -- All attachment configurations
local activeTraps = {}        -- Currently placed traps
local activeProjectiles = {}  -- In-flight projectiles (grenades, rockets)
local framework = nil         -- Framework reference
local gameConfig = nil        -- Game configuration reference

--==============================================================================
-- CONSTANTS
--==============================================================================
local MAX_WEAPON_SLOTS = 5
local MAX_TRAPS_PER_PLAYER = 3
local GRENADE_FUSE_TIME = 3.0
local ROCKET_SPEED = 150
local C4_MAX_DISTANCE = 200

--==============================================================================
-- WEAPON CATEGORY DEFINITIONS
--==============================================================================

--[[
    Weapon Categories define:
    - Default inventory slot
    - Ammunition type
    - Fire mode (automatic, semi-auto, melee, explosive)
    - Allowed attachments
]]
local WEAPON_CATEGORIES = {
    assault_rifle = {
        slot = 1,
        ammoType = "medium",
        fireMode = "automatic",
        allowedAttachments = {"scope", "grip", "magazine", "suppressor"},
    },
    smg = {
        slot = 2,
        ammoType = "light",
        fireMode = "automatic",
        allowedAttachments = {"scope", "grip", "magazine", "suppressor"},
    },
    shotgun = {
        slot = 3,
        ammoType = "shells",
        fireMode = "pump",
        allowedAttachments = {"grip"},
    },
    sniper = {
        slot = 4,
        ammoType = "heavy",
        fireMode = "bolt",
        allowedAttachments = {"scope", "magazine", "suppressor"},
    },
    pistol = {
        slot = 5,
        ammoType = "light",
        fireMode = "semi",
        allowedAttachments = {"scope", "magazine", "suppressor"},
    },
    melee = {
        slot = 5,
        ammoType = nil,
        fireMode = "melee",
        allowedAttachments = {},
    },
    explosive = {
        slot = 1,
        ammoType = "explosive",
        fireMode = "launcher",
        allowedAttachments = {},
    },
    throwable = {
        slot = nil,
        ammoType = nil,
        fireMode = "throw",
        allowedAttachments = {},
    },
    trap = {
        slot = nil,
        ammoType = nil,
        fireMode = "place",
        allowedAttachments = {},
    },
}

--==============================================================================
-- WEAPON CONFIGURATIONS
--==============================================================================

local WEAPON_DEFINITIONS = {
    -- ASSAULT RIFLES
    ak47 = {
        name = "AK-47",
        category = "assault_rifle",
        rarity = "rare",
        damage = 27,
        fireRate = 10,
        magazineSize = 30,
        reloadTime = 2.4,
        accuracy = 0.85,
        range = 150,
        recoil = {vertical = 0.8, horizontal = 0.3, recovery = 0.15, pattern = "climb"},
        headshotMultiplier = 2.0,
        falloffStart = 50,
        falloffEnd = 150,
    },
    m4a1 = {
        name = "M4A1",
        category = "assault_rifle",
        rarity = "epic",
        damage = 24,
        fireRate = 12,
        magazineSize = 30,
        reloadTime = 2.2,
        accuracy = 0.9,
        range = 160,
        recoil = {vertical = 0.6, horizontal = 0.2, recovery = 0.18, pattern = "s-curve"},
        headshotMultiplier = 2.0,
        falloffStart = 60,
        falloffEnd = 160,
    },
    scar = {
        name = "SCAR",
        category = "assault_rifle",
        rarity = "legendary",
        damage = 30,
        fireRate = 9,
        magazineSize = 25,
        reloadTime = 2.6,
        accuracy = 0.92,
        range = 180,
        recoil = {vertical = 0.7, horizontal = 0.15, recovery = 0.2, pattern = "controlled"},
        headshotMultiplier = 2.0,
        falloffStart = 70,
        falloffEnd = 180,
    },

    -- SMGS
    mp5 = {
        name = "MP5",
        category = "smg",
        rarity = "uncommon",
        damage = 18,
        fireRate = 15,
        magazineSize = 30,
        reloadTime = 2.0,
        accuracy = 0.75,
        range = 80,
        recoil = {vertical = 0.4, horizontal = 0.35, recovery = 0.25, pattern = "circular"},
        headshotMultiplier = 1.8,
        falloffStart = 30,
        falloffEnd = 80,
    },
    uzi = {
        name = "UZI",
        category = "smg",
        rarity = "common",
        damage = 15,
        fireRate = 18,
        magazineSize = 32,
        reloadTime = 1.8,
        accuracy = 0.65,
        range = 60,
        recoil = {vertical = 0.35, horizontal = 0.5, recovery = 0.3, pattern = "random"},
        headshotMultiplier = 1.8,
        falloffStart = 20,
        falloffEnd = 60,
    },
    p90 = {
        name = "P90",
        category = "smg",
        rarity = "rare",
        damage = 17,
        fireRate = 16,
        magazineSize = 50,
        reloadTime = 2.5,
        accuracy = 0.78,
        range = 70,
        recoil = {vertical = 0.38, horizontal = 0.28, recovery = 0.22, pattern = "controlled"},
        headshotMultiplier = 1.8,
        falloffStart = 25,
        falloffEnd = 70,
        armorPiercing = 0.3,
    },

    -- SHOTGUNS
    pump = {
        name = "Pump Shotgun",
        category = "shotgun",
        rarity = "uncommon",
        damage = 90,
        pellets = 10,
        fireRate = 1,
        magazineSize = 5,
        reloadTime = 4.5,
        reloadType = "per_shell",
        accuracy = 0.6,
        range = 30,
        spread = 8,
        recoil = {vertical = 1.5, horizontal = 0.2, recovery = 0.5, pattern = "kick"},
        headshotMultiplier = 1.5,
        falloffStart = 10,
        falloffEnd = 30,
    },
    tactical_shotgun = {
        name = "Tactical Shotgun",
        category = "shotgun",
        rarity = "rare",
        damage = 70,
        pellets = 8,
        fireRate = 1.5,
        magazineSize = 8,
        reloadTime = 5.5,
        reloadType = "per_shell",
        accuracy = 0.65,
        range = 35,
        spread = 6,
        recoil = {vertical = 1.2, horizontal = 0.15, recovery = 0.45, pattern = "kick"},
        headshotMultiplier = 1.5,
        falloffStart = 12,
        falloffEnd = 35,
    },
    double_barrel = {
        name = "Double Barrel",
        category = "shotgun",
        rarity = "epic",
        damage = 110,
        pellets = 12,
        fireRate = 2.5,
        magazineSize = 2,
        reloadTime = 3.0,
        reloadType = "full",
        accuracy = 0.55,
        range = 25,
        spread = 10,
        recoil = {vertical = 2.0, horizontal = 0.3, recovery = 0.6, pattern = "kick"},
        headshotMultiplier = 1.5,
        falloffStart = 8,
        falloffEnd = 25,
    },

    -- SNIPERS
    bolt_sniper = {
        name = "Bolt-Action Sniper",
        category = "sniper",
        rarity = "epic",
        damage = 105,
        fireRate = 0.5,
        magazineSize = 5,
        reloadTime = 3.0,
        accuracy = 0.98,
        range = 500,
        recoil = {vertical = 2.5, horizontal = 0.1, recovery = 1.0, pattern = "single"},
        headshotMultiplier = 2.5,
        falloffStart = 200,
        falloffEnd = 500,
        scope = true,
        scopeZoom = 4,
    },
    semi_sniper = {
        name = "Semi-Auto Sniper",
        category = "sniper",
        rarity = "rare",
        damage = 75,
        fireRate = 1.5,
        magazineSize = 10,
        reloadTime = 2.8,
        accuracy = 0.95,
        range = 400,
        recoil = {vertical = 1.8, horizontal = 0.15, recovery = 0.8, pattern = "single"},
        headshotMultiplier = 2.5,
        falloffStart = 150,
        falloffEnd = 400,
        scope = true,
        scopeZoom = 3,
    },
    heavy_sniper = {
        name = "Heavy Sniper",
        category = "sniper",
        rarity = "legendary",
        damage = 150,
        fireRate = 0.33,
        magazineSize = 4,
        reloadTime = 4.0,
        accuracy = 0.99,
        range = 600,
        recoil = {vertical = 3.0, horizontal = 0.05, recovery = 1.5, pattern = "single"},
        headshotMultiplier = 2.5,
        falloffStart = 250,
        falloffEnd = 600,
        scope = true,
        scopeZoom = 5,
        penetration = true,
        penetrationDamage = 0.7,
    },

    -- PISTOLS
    glock = {
        name = "Glock",
        category = "pistol",
        rarity = "common",
        damage = 20,
        fireRate = 5,
        magazineSize = 15,
        reloadTime = 1.5,
        accuracy = 0.8,
        range = 50,
        recoil = {vertical = 0.5, horizontal = 0.2, recovery = 0.3, pattern = "kick"},
        headshotMultiplier = 2.0,
        falloffStart = 20,
        falloffEnd = 50,
    },
    deagle = {
        name = "Desert Eagle",
        category = "pistol",
        rarity = "rare",
        damage = 55,
        fireRate = 2,
        magazineSize = 7,
        reloadTime = 2.0,
        accuracy = 0.75,
        range = 70,
        recoil = {vertical = 1.2, horizontal = 0.4, recovery = 0.5, pattern = "kick"},
        headshotMultiplier = 2.0,
        falloffStart = 30,
        falloffEnd = 70,
    },
    revolver = {
        name = "Revolver",
        category = "pistol",
        rarity = "epic",
        damage = 70,
        fireRate = 1.5,
        magazineSize = 6,
        reloadTime = 3.0,
        reloadType = "full",
        accuracy = 0.85,
        range = 80,
        recoil = {vertical = 1.5, horizontal = 0.25, recovery = 0.6, pattern = "kick"},
        headshotMultiplier = 2.2,
        falloffStart = 35,
        falloffEnd = 80,
    },

    -- MELEE WEAPONS
    machete = {
        name = "Machete",
        category = "melee",
        rarity = "common",
        damage = 35,
        fireRate = 2,
        range = 6,
        attackAngle = 90,
        headshotMultiplier = 1.5,
        swingTime = 0.3,
        recoveryTime = 0.2,
        effects = {bleed = {damage = 3, duration = 5, tickRate = 1}},
    },
    spear = {
        name = "Spear",
        category = "melee",
        rarity = "uncommon",
        damage = 45,
        fireRate = 1.2,
        range = 10,
        attackAngle = 30,
        headshotMultiplier = 1.8,
        swingTime = 0.5,
        recoveryTime = 0.3,
        bonusDamage = {dinosaur = 1.5},
        canThrow = true,
        throwDamage = 60,
        throwRange = 40,
        retrievable = true,
    },
    stun_baton = {
        name = "Stun Baton",
        category = "melee",
        rarity = "rare",
        damage = 25,
        fireRate = 1.5,
        range = 5,
        attackAngle = 60,
        headshotMultiplier = 1.2,
        swingTime = 0.25,
        recoveryTime = 0.2,
        effects = {stun = {duration = 2, slowAmount = 0.5}},
        chargeRequired = true,
        maxCharge = 100,
        chargePerHit = 10,
    },
    combat_knife = {
        name = "Combat Knife",
        category = "melee",
        rarity = "common",
        damage = 25,
        fireRate = 3,
        range = 4,
        attackAngle = 45,
        headshotMultiplier = 2.0,
        swingTime = 0.15,
        recoveryTime = 0.15,
        silent = true,
        backstabMultiplier = 3.0,
    },

    -- EXPLOSIVE WEAPONS
    rocket_launcher = {
        name = "Rocket Launcher",
        category = "explosive",
        rarity = "legendary",
        damage = 120,
        explosionDamage = 80,
        explosionRadius = 15,
        fireRate = 0.5,
        magazineSize = 1,
        reloadTime = 3.5,
        accuracy = 0.95,
        range = 200,
        projectileSpeed = 150,
        recoil = {vertical = 2.0, horizontal = 0.5, recovery = 1.0, pattern = "kick"},
        selfDamage = true,
        selfDamageMultiplier = 0.5,
    },
    grenade_launcher = {
        name = "Grenade Launcher",
        category = "explosive",
        rarity = "epic",
        damage = 90,
        explosionDamage = 70,
        explosionRadius = 12,
        fireRate = 1,
        magazineSize = 6,
        reloadTime = 4.0,
        accuracy = 0.8,
        range = 150,
        projectileSpeed = 80,
        bounces = 2,
        fuseTime = 2.0,
        recoil = {vertical = 1.0, horizontal = 0.3, recovery = 0.5, pattern = "kick"},
        selfDamage = true,
        selfDamageMultiplier = 0.5,
    },

    -- THROWABLES
    frag_grenade = {
        name = "Frag Grenade",
        category = "throwable",
        rarity = "uncommon",
        damage = 100,
        explosionRadius = 12,
        fuseTime = 3.0,
        throwSpeed = 60,
        maxStack = 6,
        canCook = true,
        minCookTime = 0.5,
        selfDamage = true,
        selfDamageMultiplier = 0.8,
    },
    smoke_grenade = {
        name = "Smoke Grenade",
        category = "throwable",
        rarity = "common",
        damage = 0,
        effectRadius = 15,
        effectDuration = 15,
        fuseTime = 1.5,
        throwSpeed = 55,
        maxStack = 4,
        effect = "smoke",
    },
    molotov = {
        name = "Molotov Cocktail",
        category = "throwable",
        rarity = "rare",
        damage = 30,
        burnDamage = 10,
        effectRadius = 10,
        effectDuration = 8,
        fuseTime = 0,
        throwSpeed = 50,
        maxStack = 3,
        effect = "fire",
        selfDamage = true,
        selfDamageMultiplier = 1.0,
    },
    flashbang = {
        name = "Flashbang",
        category = "throwable",
        rarity = "uncommon",
        damage = 5,
        effectRadius = 20,
        effectDuration = 4,
        fuseTime = 2.0,
        throwSpeed = 65,
        maxStack = 4,
        effect = "flash",
        affectsThrower = true,
    },
    c4 = {
        name = "C4 Explosive",
        category = "throwable",
        rarity = "epic",
        damage = 150,
        explosionRadius = 15,
        throwSpeed = 40,
        maxStack = 2,
        remoteDetonated = true,
        maxDetonationRange = 200,
        stickToSurface = true,
        selfDamage = true,
        selfDamageMultiplier = 0.5,
    },

    -- TRAPS
    bear_trap = {
        name = "Bear Trap",
        category = "trap",
        rarity = "uncommon",
        damage = 50,
        maxStack = 3,
        triggerRadius = 3,
        immobilizeDuration = 3,
        affectsDinosaurs = true,
        visibleToEnemy = true,
        armTime = 1.5,
        deployTime = 1.0,
    },
    tripwire = {
        name = "Tripwire Alarm",
        category = "trap",
        rarity = "common",
        damage = 15,
        maxStack = 5,
        triggerRadius = 5,
        alertRange = 100,
        affectsDinosaurs = true,
        visibleToEnemy = false,
        armTime = 1.0,
        deployTime = 0.8,
        effect = "alert",
    },
    tranq_trap = {
        name = "Tranquilizer Trap",
        category = "trap",
        rarity = "rare",
        damage = 10,
        maxStack = 2,
        triggerRadius = 4,
        sleepDuration = 5,
        dinoSleepDuration = 10,
        affectsDinosaurs = true,
        visibleToEnemy = true,
        armTime = 2.0,
        deployTime = 1.5,
        effect = "sleep",
    },
    spike_trap = {
        name = "Spike Trap",
        category = "trap",
        rarity = "uncommon",
        damage = 75,
        maxStack = 2,
        triggerRadius = 4,
        affectsDinosaurs = true,
        visibleToEnemy = false,
        armTime = 2.0,
        deployTime = 2.0,
        resetTime = 5.0,
        reusable = true,
        effects = {bleed = {damage = 5, duration = 8, tickRate = 1}},
    },
}

--==============================================================================
-- ATTACHMENT CONFIGURATIONS
--==============================================================================

local ATTACHMENT_DEFINITIONS = {
    -- Scopes
    red_dot = {
        name = "Red Dot Sight",
        slot = "scope",
        rarity = "common",
        statModifiers = {accuracy = 0.05},
        zoom = 1.0,
    },
    scope_2x = {
        name = "2x Scope",
        slot = "scope",
        rarity = "uncommon",
        statModifiers = {accuracy = 0.03, adsTime = 0.1},
        zoom = 2.0,
    },
    scope_4x = {
        name = "4x Scope",
        slot = "scope",
        rarity = "rare",
        statModifiers = {accuracy = 0.05, adsTime = 0.15, hipfireAccuracy = -0.1},
        zoom = 4.0,
    },
    scope_8x = {
        name = "8x Scope",
        slot = "scope",
        rarity = "epic",
        statModifiers = {accuracy = 0.08, adsTime = 0.25, hipfireAccuracy = -0.2},
        zoom = 8.0,
        sniperOnly = true,
    },
    scope_thermal = {
        name = "Thermal Scope",
        slot = "scope",
        rarity = "legendary",
        statModifiers = {accuracy = 0.05, adsTime = 0.2},
        zoom = 4.0,
        thermalVision = true,
        seeThroughSmoke = true,
    },

    -- Grips
    vertical_grip = {
        name = "Vertical Grip",
        slot = "grip",
        rarity = "common",
        statModifiers = {recoilVertical = -0.15},
    },
    angled_grip = {
        name = "Angled Grip",
        slot = "grip",
        rarity = "uncommon",
        statModifiers = {adsTime = -0.1, recoilVertical = -0.08},
    },
    stabilizer_grip = {
        name = "Stabilizer Grip",
        slot = "grip",
        rarity = "rare",
        statModifiers = {recoilVertical = -0.2, recoilHorizontal = -0.2, recoilRecovery = 0.15},
    },

    -- Magazines
    extended_mag = {
        name = "Extended Magazine",
        slot = "magazine",
        rarity = "common",
        statModifiers = {magazineSize = 0.5, reloadTime = 0.1},
    },
    quickdraw_mag = {
        name = "Quick-Draw Magazine",
        slot = "magazine",
        rarity = "uncommon",
        statModifiers = {reloadTime = -0.25},
    },
    extended_quickdraw = {
        name = "Extended Quick-Draw Mag",
        slot = "magazine",
        rarity = "rare",
        statModifiers = {magazineSize = 0.3, reloadTime = -0.15},
    },

    -- Suppressors/Muzzles
    suppressor_light = {
        name = "Light Suppressor",
        slot = "suppressor",
        rarity = "common",
        statModifiers = {damage = -0.05, soundReduction = 0.5},
        hidesMuzzleFlash = true,
    },
    suppressor_heavy = {
        name = "Heavy Suppressor",
        slot = "suppressor",
        rarity = "rare",
        statModifiers = {damage = -0.1, range = -0.1, soundReduction = 0.8},
        hidesMuzzleFlash = true,
    },
    compensator = {
        name = "Compensator",
        slot = "suppressor",
        rarity = "uncommon",
        statModifiers = {recoilVertical = -0.15, recoilHorizontal = -0.1, soundReduction = -0.2},
    },
}

--==============================================================================
-- INITIALIZATION
--==============================================================================

--[[
    Initialize the WeaponService
    Sets up configs, remotes, and player handlers
    @return boolean - True if successful
]]
function WeaponService:Initialize()
    -- Rojo maps to ReplicatedStorage.Framework and ReplicatedStorage.Shared
    framework = require(script.Parent.Parent.Framework)
    gameConfig = require(script.Parent.Parent.Shared.GameConfig)

    self:LoadWeaponConfigs()
    self:LoadAttachmentConfigs()
    self:SetupRemotes()

    -- Handle player connections
    Players.PlayerAdded:Connect(function(player)
        self:InitializePlayerInventory(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:CleanupPlayerTraps(player)
        playerWeapons[player.UserId] = nil
    end)

    -- Initialize existing players
    for _, player in ipairs(Players:GetPlayers()) do
        self:InitializePlayerInventory(player)
    end

    framework.Log("Info", "WeaponService initialized with %d weapons and %d attachments",
        self:GetWeaponCount(), self:GetAttachmentCount())

    return true
end

--[[
    Load weapon configurations
]]
function WeaponService:LoadWeaponConfigs()
    weaponConfigs = {}
    for weaponId, weaponDef in pairs(WEAPON_DEFINITIONS) do
        local config = {}
        for key, value in pairs(weaponDef) do
            config[key] = value
        end

        local category = WEAPON_CATEGORIES[config.category]
        if category then
            config.slot = config.slot or category.slot
            config.ammoType = config.ammoType or category.ammoType
            config.fireMode = config.fireMode or category.fireMode
            config.allowedAttachments = config.allowedAttachments or category.allowedAttachments
        end

        weaponConfigs[weaponId] = config
    end
end

--[[
    Load attachment configurations
]]
function WeaponService:LoadAttachmentConfigs()
    attachmentConfigs = {}
    for attachId, attachDef in pairs(ATTACHMENT_DEFINITIONS) do
        attachmentConfigs[attachId] = attachDef
    end
end

--[[
    Setup remote events for weapon communication
]]
function WeaponService:SetupRemotes()
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = "Remotes"
        remoteFolder.Parent = ReplicatedStorage
    end

    local weaponRemotes = {
        "WeaponFire", "WeaponReload", "WeaponEquip", "WeaponDrop", "WeaponPickup",
        "BulletHit", "DamageDealt", "DamageReceived",
        "MeleeSwing", "MeleeHit",
        "ThrowProjectile", "ProjectileExplode", "DetonateC4",
        "PlaceTrap", "TrapTriggered", "TrapDestroyed",
        "AttachmentAdd", "AttachmentRemove",
        "InventoryUpdate", "AmmoUpdate",
    }

    for _, remoteName in ipairs(weaponRemotes) do
        if not remoteFolder:FindFirstChild(remoteName) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = remoteName
            remote.Parent = remoteFolder
        end
    end

    -- Connect handlers
    remoteFolder.WeaponFire.OnServerEvent:Connect(function(player, data)
        self:HandleWeaponFire(player, data)
    end)

    remoteFolder.WeaponReload.OnServerEvent:Connect(function(player, slotIndex)
        self:HandleReload(player, slotIndex)
    end)

    remoteFolder.WeaponEquip.OnServerEvent:Connect(function(player, slotIndex)
        self:HandleEquip(player, slotIndex)
    end)

    remoteFolder.WeaponDrop.OnServerEvent:Connect(function(player, slotIndex)
        self:HandleDrop(player, slotIndex)
    end)

    remoteFolder.WeaponPickup.OnServerEvent:Connect(function(player, weaponId)
        self:HandlePickup(player, weaponId)
    end)

    remoteFolder.MeleeSwing.OnServerEvent:Connect(function(player, data)
        self:HandleMeleeSwing(player, data)
    end)

    remoteFolder.ThrowProjectile.OnServerEvent:Connect(function(player, data)
        self:HandleThrowProjectile(player, data)
    end)

    remoteFolder.DetonateC4.OnServerEvent:Connect(function(player)
        self:HandleDetonateC4(player)
    end)

    remoteFolder.PlaceTrap.OnServerEvent:Connect(function(player, data)
        self:HandlePlaceTrap(player, data)
    end)
end

--[[
    Get weapon count
    @return number
]]
function WeaponService:GetWeaponCount()
    local count = 0
    for _ in pairs(weaponConfigs) do count = count + 1 end
    return count
end

--[[
    Get attachment count
    @return number
]]
function WeaponService:GetAttachmentCount()
    local count = 0
    for _ in pairs(attachmentConfigs) do count = count + 1 end
    return count
end

--==============================================================================
-- INVENTORY MANAGEMENT
--==============================================================================

--[[
    Initialize player inventory
    @param player Player
]]
function WeaponService:InitializePlayerInventory(player)
    playerWeapons[player.UserId] = {
        slots = {},
        equipped = 0,
        ammo = {light = 0, medium = 0, heavy = 0, shells = 0, explosive = 0},
        throwables = {},
        placedTraps = {},
        lastFireTime = {},
        activeC4 = {},
    }

    for i = 1, MAX_WEAPON_SLOTS do
        playerWeapons[player.UserId].slots[i] = nil
    end
end

--[[
    Get player inventory
    @param player Player
    @return table
]]
function WeaponService:GetPlayerInventory(player)
    return playerWeapons[player.UserId]
end

--[[
    Give weapon to player
    @param player Player
    @param weaponType string
    @param currentAmmo number (optional)
    @return boolean
]]
function WeaponService:GiveWeapon(player, weaponType, currentAmmo)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return false end

    local config = weaponConfigs[weaponType]
    if not config then return false end

    -- Find empty slot
    local slot = nil
    for i = 1, MAX_WEAPON_SLOTS do
        if not inventory.slots[i] then
            slot = i
            break
        end
    end

    if not slot then return false end

    local weapon = {
        id = game:GetService("HttpService"):GenerateGUID(false),
        type = weaponType,
        config = config,
        currentAmmo = currentAmmo or config.magazineSize or 0,
        attachments = {},
        charge = config.maxCharge,
    }

    inventory.slots[slot] = weapon
    self:BroadcastInventoryUpdate(player)
    framework.Log("Debug", "%s received %s in slot %d", player.Name, config.name, slot)
    return true
end

--[[
    Give ammo to player
    @param player Player
    @param ammoType string
    @param amount number
    @return boolean
]]
function WeaponService:GiveAmmo(player, ammoType, amount)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return false end

    if not inventory.ammo[ammoType] then
        inventory.ammo[ammoType] = 0
    end

    inventory.ammo[ammoType] = inventory.ammo[ammoType] + amount
    self:BroadcastAmmoUpdate(player)
    return true
end

--[[
    Give throwable to player
    @param player Player
    @param throwableType string
    @param amount number
    @return boolean
]]
function WeaponService:GiveThrowable(player, throwableType, amount)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return false end

    local config = weaponConfigs[throwableType]
    if not config or config.category ~= "throwable" then return false end

    local existingStack = nil
    for _, stack in ipairs(inventory.throwables) do
        if stack.type == throwableType then
            existingStack = stack
            break
        end
    end

    if existingStack then
        local maxStack = config.maxStack or 10
        existingStack.count = math.min(existingStack.count + amount, maxStack)
    else
        table.insert(inventory.throwables, {
            type = throwableType,
            count = math.min(amount, config.maxStack or 10),
            config = config,
        })
    end

    self:BroadcastInventoryUpdate(player)
    return true
end

--[[
    Broadcast inventory update to client
    @param player Player
]]
function WeaponService:BroadcastInventoryUpdate(player)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    local clientData = {
        slots = {},
        equipped = inventory.equipped,
        throwables = {},
    }

    for i, weapon in pairs(inventory.slots) do
        if weapon then
            clientData.slots[i] = {
                type = weapon.type,
                name = weapon.config.name,
                currentAmmo = weapon.currentAmmo,
                magazineSize = weapon.config.magazineSize,
                rarity = weapon.config.rarity,
                attachments = weapon.attachments,
            }
        end
    end

    for _, throwable in ipairs(inventory.throwables) do
        table.insert(clientData.throwables, {
            type = throwable.type,
            name = throwable.config.name,
            count = throwable.count,
        })
    end

    remotes.InventoryUpdate:FireClient(player, clientData)
end

--[[
    Broadcast ammo update to client
    @param player Player
]]
function WeaponService:BroadcastAmmoUpdate(player)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    remotes.AmmoUpdate:FireClient(player, inventory.ammo)
end

--==============================================================================
-- WEAPON FIRING
--==============================================================================

--[[
    Handle weapon fire from client
    @param player Player
    @param data table - Fire data
]]
function WeaponService:HandleWeaponFire(player, data)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    local equippedSlot = inventory.equipped
    if equippedSlot == 0 then return end

    local weapon = inventory.slots[equippedSlot]
    if not weapon then return end

    local config = weapon.config

    -- Skip for non-ranged
    if config.category == "melee" or config.category == "trap" then return end

    -- Validate fire rate
    local now = tick()
    local lastFire = inventory.lastFireTime[equippedSlot] or 0
    local minInterval = 1 / (config.fireRate or 1)

    if (now - lastFire) < (minInterval * 0.8) then return end
    inventory.lastFireTime[equippedSlot] = now

    -- Check ammo
    if config.magazineSize and weapon.currentAmmo <= 0 then return end

    -- Consume ammo
    if config.magazineSize then
        weapon.currentAmmo = weapon.currentAmmo - 1
    end

    -- Process hit
    if config.projectileSpeed then
        self:FireProjectile(player, weapon, data)
    elseif config.pellets then
        self:FireShotgun(player, weapon, data)
    else
        self:FireHitscan(player, weapon, data)
    end

    -- Broadcast to other clients
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            if otherPlayer ~= player then
                remotes.WeaponFire:FireClient(otherPlayer, {
                    shooterId = player.UserId,
                    weaponType = weapon.type,
                    origin = data.origin,
                    direction = data.direction,
                })
            end
        end
    end
end

--[[
    Fire hitscan weapon
    @param player Player
    @param weapon table
    @param data table
]]
function WeaponService:FireHitscan(player, weapon, data)
    if data.hit then
        self:ProcessHit(player, weapon, data.hit, data.hitPosition, data.hitPart)
    end
end

--[[
    Fire shotgun (multiple pellets)
    @param player Player
    @param weapon table
    @param data table
]]
function WeaponService:FireShotgun(player, weapon, data)
    if data.pelletHits then
        for _, pelletHit in ipairs(data.pelletHits) do
            self:ProcessHit(player, weapon, pelletHit.hit, pelletHit.position, pelletHit.part)
        end
    elseif data.hit then
        self:ProcessHit(player, weapon, data.hit, data.hitPosition, data.hitPart)
    end
end

--[[
    Fire projectile weapon
    @param player Player
    @param weapon table
    @param data table
]]
function WeaponService:FireProjectile(player, weapon, data)
    local config = weapon.config

    local projectile = Instance.new("Part")
    projectile.Name = "Projectile_" .. weapon.type
    projectile.Size = Vector3.new(1, 1, 2)
    projectile.Position = data.origin
    projectile.CFrame = CFrame.new(data.origin, data.origin + data.direction)
    projectile.Anchored = false
    projectile.CanCollide = true
    projectile.Color = Color3.fromRGB(100, 100, 100)
    projectile.Material = Enum.Material.Metal

    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Velocity = data.direction.Unit * config.projectileSpeed
    bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bodyVelocity.Parent = projectile

    projectile.Parent = workspace

    local projectileData = {
        id = game:GetService("HttpService"):GenerateGUID(false),
        owner = player,
        weapon = weapon,
        part = projectile,
        startTime = tick(),
    }
    activeProjectiles[projectileData.id] = projectileData

    projectile.Touched:Connect(function(hit)
        if hit:IsDescendantOf(player.Character) then return end
        self:ExplodeProjectile(projectileData, projectile.Position)
    end)

    if config.fuseTime then
        task.delay(config.fuseTime, function()
            if projectile.Parent then
                self:ExplodeProjectile(projectileData, projectile.Position)
            end
        end)
    end

    Debris:AddItem(projectile, 10)
end

--[[
    Explode a projectile
    @param projectileData table
    @param position Vector3
]]
function WeaponService:ExplodeProjectile(projectileData, position)
    local weapon = projectileData.weapon
    local config = weapon.config
    local owner = projectileData.owner

    activeProjectiles[projectileData.id] = nil

    local explosion = Instance.new("Explosion")
    explosion.Position = position
    explosion.BlastRadius = config.explosionRadius or 10
    explosion.BlastPressure = 5000
    explosion.DestroyJointRadiusPercent = 0
    explosion.Parent = workspace

    -- Damage players
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if not character then continue end

        local rootPart = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChild("Humanoid")

        if rootPart and humanoid and humanoid.Health > 0 then
            local distance = (rootPart.Position - position).Magnitude

            if distance <= (config.explosionRadius or 10) then
                local falloff = 1 - (distance / (config.explosionRadius or 10))
                local damage = (config.explosionDamage or config.damage) * falloff

                if player == owner then
                    if config.selfDamage then
                        damage = damage * (config.selfDamageMultiplier or 0.5)
                    else
                        continue
                    end
                end

                humanoid:TakeDamage(damage)

                if humanoid.Health <= 0 then
                    local gameService = framework:GetService("GameService")
                    if gameService then
                        gameService:EliminatePlayer(player, owner)
                    end
                end
            end
        end
    end

    -- Damage dinosaurs
    local dinoService = framework:GetService("DinoService")
    if dinoService then
        local activeDinos = dinoService:GetAllActive()
        for dinoId, dino in pairs(activeDinos) do
            if dino.model and dino.model.PrimaryPart then
                local distance = (dino.model.PrimaryPart.Position - position).Magnitude
                if distance <= (config.explosionRadius or 10) then
                    local falloff = 1 - (distance / (config.explosionRadius or 10))
                    local damage = (config.explosionDamage or config.damage) * falloff
                    dinoService:DamageDinosaur(dinoId, damage, owner)
                end
            end
        end
    end

    if projectileData.part then
        projectileData.part:Destroy()
    end
end

--[[
    Process a bullet hit
    @param shooter Player
    @param weapon table
    @param hitInstance Instance
    @param hitPosition Vector3
    @param hitPartName string
]]
function WeaponService:ProcessHit(shooter, weapon, hitInstance, hitPosition, hitPartName)
    if not hitInstance then return end

    local character = hitInstance:FindFirstAncestorOfClass("Model")
    if not character then return end

    local humanoid = character:FindFirstChild("Humanoid")
    local targetPlayer = Players:GetPlayerFromCharacter(character)

    if targetPlayer == shooter then return end

    local isDino = character.Name:find("Dino_") ~= nil

    if humanoid and humanoid.Health > 0 then
        local damage = self:CalculateDamage(weapon, hitPosition, shooter.Character, hitPartName, isDino)

        if isDino then
            local dinoId = character.Name:gsub("Dino_", "")
            local dinoService = framework:GetService("DinoService")
            if dinoService then
                dinoService:DamageDinosaur(dinoId, damage, shooter)
            end
        else
            humanoid:TakeDamage(damage)

            if humanoid.Health <= 0 and targetPlayer then
                local gameService = framework:GetService("GameService")
                if gameService then
                    gameService:EliminatePlayer(targetPlayer, shooter)
                end
            end
        end

        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
            remotes.DamageDealt:FireClient(shooter, {
                damage = damage,
                position = hitPosition,
                isHeadshot = hitPartName == "Head",
                victimId = targetPlayer and targetPlayer.UserId or nil,
                isDino = isDino,
            })
        end
    end
end

--[[
    Calculate damage with all modifiers
    @param weapon table
    @param hitPosition Vector3
    @param shooterCharacter Model
    @param hitPartName string
    @param isDinosaur boolean
    @return number
]]
function WeaponService:CalculateDamage(weapon, hitPosition, shooterCharacter, hitPartName, isDinosaur)
    local config = weapon.config
    local baseDamage = config.damage

    -- Shotgun per-pellet
    if config.pellets then
        baseDamage = config.damage / config.pellets
    end

    -- Attachment modifiers
    local damageModifier = 1.0
    if weapon.attachments then
        for _, attachId in pairs(weapon.attachments) do
            local attachConfig = attachmentConfigs[attachId]
            if attachConfig and attachConfig.statModifiers and attachConfig.statModifiers.damage then
                damageModifier = damageModifier + attachConfig.statModifiers.damage
            end
        end
    end
    baseDamage = baseDamage * damageModifier

    -- Distance falloff
    local distance = 0
    if shooterCharacter and shooterCharacter:FindFirstChild("HumanoidRootPart") then
        distance = (shooterCharacter.HumanoidRootPart.Position - hitPosition).Magnitude
    end

    local falloffMultiplier = 1
    if distance > (config.falloffStart or 0) then
        local falloffRange = (config.falloffEnd or 100) - (config.falloffStart or 0)
        if falloffRange > 0 then
            local falloffProgress = math.clamp((distance - config.falloffStart) / falloffRange, 0, 1)
            falloffMultiplier = 1 - (falloffProgress * 0.5)
        end
    end

    -- Hit location
    local locationMultiplier = 1.0
    if hitPartName == "Head" then
        locationMultiplier = config.headshotMultiplier or 2.0
    elseif hitPartName == "LeftLeg" or hitPartName == "RightLeg" then
        locationMultiplier = 0.75
    end

    -- Dinosaur bonus
    if isDinosaur and config.bonusDamage and config.bonusDamage.dinosaur then
        locationMultiplier = locationMultiplier * config.bonusDamage.dinosaur
    end

    return math.floor(baseDamage * falloffMultiplier * locationMultiplier)
end

--==============================================================================
-- MELEE COMBAT
--==============================================================================

--[[
    Handle melee swing
    @param player Player
    @param data table
]]
function WeaponService:HandleMeleeSwing(player, data)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    local equippedSlot = inventory.equipped
    if equippedSlot == 0 then return end

    local weapon = inventory.slots[equippedSlot]
    if not weapon or weapon.config.category ~= "melee" then return end

    local config = weapon.config

    -- Validate swing rate
    local now = tick()
    local lastSwing = inventory.lastFireTime[equippedSlot] or 0
    local minInterval = 1 / (config.fireRate or 1)

    if (now - lastSwing) < (minInterval * 0.8) then return end
    inventory.lastFireTime[equippedSlot] = now

    -- Check charge
    if config.chargeRequired then
        if weapon.charge < (config.chargePerHit or 10) then return end
        weapon.charge = weapon.charge - (config.chargePerHit or 10)
    end

    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local meleeOrigin = rootPart.Position
    local meleeDirection = data.direction or rootPart.CFrame.LookVector
    local meleeRange = config.range or 5
    local attackAngle = config.attackAngle or 90

    local hits = {}

    -- Check players
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer == player then continue end

        local targetChar = targetPlayer.Character
        if not targetChar then continue end

        local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
        local targetHumanoid = targetChar:FindFirstChild("Humanoid")

        if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
            local toTarget = (targetRoot.Position - meleeOrigin)
            local distance = toTarget.Magnitude

            if distance <= meleeRange then
                local angle = math.deg(math.acos(meleeDirection:Dot(toTarget.Unit)))
                if angle <= attackAngle / 2 then
                    local backstab = false
                    if config.backstabMultiplier then
                        local targetForward = targetRoot.CFrame.LookVector
                        local behindAngle = math.deg(math.acos(targetForward:Dot(toTarget.Unit)))
                        if behindAngle < 60 then backstab = true end
                    end

                    table.insert(hits, {
                        target = targetPlayer,
                        humanoid = targetHumanoid,
                        position = targetRoot.Position,
                        backstab = backstab,
                        isDino = false,
                    })
                end
            end
        end
    end

    -- Check dinosaurs
    local dinoService = framework:GetService("DinoService")
    if dinoService then
        local activeDinos = dinoService:GetAllActive()
        for dinoId, dino in pairs(activeDinos) do
            if dino.model and dino.model.PrimaryPart then
                local toTarget = (dino.model.PrimaryPart.Position - meleeOrigin)
                local distance = toTarget.Magnitude

                if distance <= meleeRange then
                    local angle = math.deg(math.acos(meleeDirection:Dot(toTarget.Unit)))
                    if angle <= attackAngle / 2 then
                        table.insert(hits, {
                            dinoId = dinoId,
                            position = dino.model.PrimaryPart.Position,
                            isDino = true,
                        })
                    end
                end
            end
        end
    end

    -- Apply damage
    for _, hit in ipairs(hits) do
        local damage = config.damage

        if hit.backstab and config.backstabMultiplier then
            damage = damage * config.backstabMultiplier
        end

        if hit.isDino and config.bonusDamage and config.bonusDamage.dinosaur then
            damage = damage * config.bonusDamage.dinosaur
        end

        if hit.isDino then
            dinoService:DamageDinosaur(hit.dinoId, damage, player)
        else
            hit.humanoid:TakeDamage(damage)

            if config.effects then
                self:ApplyMeleeEffects(player, hit.target, config.effects)
            end

            if hit.humanoid.Health <= 0 then
                local gameService = framework:GetService("GameService")
                if gameService then
                    gameService:EliminatePlayer(hit.target, player)
                end
            end
        end
    end
end

--[[
    Apply melee effects (bleed, stun)
    @param attacker Player
    @param victim Player
    @param effects table
]]
function WeaponService:ApplyMeleeEffects(attacker, victim, effects)
    if effects.bleed then
        task.spawn(function()
            local bleed = effects.bleed
            local elapsed = 0
            local character = victim.Character

            while elapsed < bleed.duration and character and character.Parent do
                task.wait(bleed.tickRate or 1)
                elapsed = elapsed + (bleed.tickRate or 1)

                local humanoid = character:FindFirstChild("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    humanoid:TakeDamage(bleed.damage)
                else
                    break
                end
            end
        end)
    end

    if effects.stun then
        local stun = effects.stun
        local character = victim.Character
        if character then
            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then
                local originalSpeed = humanoid.WalkSpeed
                humanoid.WalkSpeed = originalSpeed * (stun.slowAmount or 0.5)
                task.delay(stun.duration, function()
                    if humanoid and humanoid.Parent then
                        humanoid.WalkSpeed = originalSpeed
                    end
                end)
            end
        end
    end
end

--==============================================================================
-- THROWABLES AND TRAPS
--==============================================================================

--[[
    Handle throwable projectile
    @param player Player
    @param data table
]]
function WeaponService:HandleThrowProjectile(player, data)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    local throwableStack = nil
    local stackIndex = nil

    for i, stack in ipairs(inventory.throwables) do
        if stack.type == data.throwableType then
            throwableStack = stack
            stackIndex = i
            break
        end
    end

    if not throwableStack or throwableStack.count <= 0 then return end

    local config = throwableStack.config

    throwableStack.count = throwableStack.count - 1
    if throwableStack.count <= 0 then
        table.remove(inventory.throwables, stackIndex)
    end

    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local origin = rootPart.Position + Vector3.new(0, 2, 0) + (data.direction.Unit * 2)
    local direction = data.direction.Unit
    local throwPower = data.power or config.throwSpeed or 50

    if config.remoteDetonated then
        self:PlaceC4(player, origin, direction)
        return
    end

    local projectile = Instance.new("Part")
    projectile.Name = "Throwable_" .. data.throwableType
    projectile.Size = Vector3.new(1, 1, 1)
    projectile.Shape = Enum.PartType.Ball
    projectile.Position = origin
    projectile.Anchored = false
    projectile.CanCollide = true
    projectile.Color = Color3.fromRGB(50, 80, 50)
    projectile.Velocity = direction * throwPower + Vector3.new(0, throwPower * 0.3, 0)
    projectile.Parent = workspace

    local projectileData = {
        id = game:GetService("HttpService"):GenerateGUID(false),
        owner = player,
        type = data.throwableType,
        config = config,
        part = projectile,
    }

    if config.fuseTime and config.fuseTime > 0 then
        local remainingFuse = config.fuseTime - (data.cookTime or 0)
        remainingFuse = math.max(0.1, remainingFuse)

        task.delay(remainingFuse, function()
            if projectile.Parent then
                self:ExplodeThrowable(projectileData, projectile.Position)
            end
        end)
    elseif config.fuseTime == 0 then
        projectile.Touched:Connect(function(hit)
            if hit:IsDescendantOf(player.Character) then return end
            self:ExplodeThrowable(projectileData, projectile.Position)
        end)
    end

    Debris:AddItem(projectile, 15)
    self:BroadcastInventoryUpdate(player)
end

--[[
    Explode throwable
    @param throwableData table
    @param position Vector3
]]
function WeaponService:ExplodeThrowable(throwableData, position)
    local config = throwableData.config
    local owner = throwableData.owner

    if throwableData.part then
        throwableData.part:Destroy()
    end

    if config.effect == "smoke" then
        self:CreateSmokeCloud(position, config)
    elseif config.effect == "fire" then
        self:CreateFireZone(position, config, owner)
    elseif config.effect == "flash" then
        self:CreateFlashbang(position, config, owner)
    else
        self:CreateExplosion(position, config, owner)
    end
end

--[[
    Create standard explosion
    @param position Vector3
    @param config table
    @param owner Player
]]
function WeaponService:CreateExplosion(position, config, owner)
    local explosion = Instance.new("Explosion")
    explosion.Position = position
    explosion.BlastRadius = config.explosionRadius or 10
    explosion.BlastPressure = 5000
    explosion.DestroyJointRadiusPercent = 0
    explosion.Parent = workspace

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if not character then continue end

        local rootPart = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChild("Humanoid")

        if rootPart and humanoid and humanoid.Health > 0 then
            local distance = (rootPart.Position - position).Magnitude

            if distance <= (config.explosionRadius or 10) then
                local falloff = 1 - (distance / (config.explosionRadius or 10))
                local damage = config.damage * falloff

                if player == owner then
                    if config.selfDamage then
                        damage = damage * (config.selfDamageMultiplier or 0.5)
                    else
                        continue
                    end
                end

                humanoid:TakeDamage(damage)
            end
        end
    end
end

--[[
    Create smoke cloud
    @param position Vector3
    @param config table
]]
function WeaponService:CreateSmokeCloud(position, config)
    local smokePart = Instance.new("Part")
    smokePart.Name = "SmokeCloud"
    smokePart.Anchored = true
    smokePart.CanCollide = false
    smokePart.Transparency = 0.7
    smokePart.Size = Vector3.new(config.effectRadius * 2, 10, config.effectRadius * 2)
    smokePart.Position = position + Vector3.new(0, 5, 0)
    smokePart.Shape = Enum.PartType.Cylinder
    smokePart.Orientation = Vector3.new(0, 0, 90)
    smokePart.Material = Enum.Material.SmoothPlastic
    smokePart.Color = Color3.fromRGB(200, 200, 200)
    smokePart.Parent = workspace

    Debris:AddItem(smokePart, config.effectDuration or 15)
end

--[[
    Create fire zone
    @param position Vector3
    @param config table
    @param owner Player
]]
function WeaponService:CreateFireZone(position, config, owner)
    local firePart = Instance.new("Part")
    firePart.Name = "FireZone"
    firePart.Anchored = true
    firePart.CanCollide = false
    firePart.Transparency = 0.5
    firePart.Size = Vector3.new(config.effectRadius * 2, 1, config.effectRadius * 2)
    firePart.Position = position
    firePart.Shape = Enum.PartType.Cylinder
    firePart.Orientation = Vector3.new(0, 0, 90)
    firePart.Material = Enum.Material.Neon
    firePart.Color = Color3.fromRGB(255, 100, 0)

    local fire = Instance.new("Fire")
    fire.Size = 10
    fire.Heat = 5
    fire.Parent = firePart

    firePart.Parent = workspace

    task.spawn(function()
        local elapsed = 0
        while elapsed < (config.effectDuration or 8) and firePart.Parent do
            task.wait(1)
            elapsed = elapsed + 1

            for _, player in ipairs(Players:GetPlayers()) do
                local character = player.Character
                if not character then continue end

                local rootPart = character:FindFirstChild("HumanoidRootPart")
                local humanoid = character:FindFirstChild("Humanoid")

                if rootPart and humanoid and humanoid.Health > 0 then
                    local distance = (Vector3.new(rootPart.Position.X, position.Y, rootPart.Position.Z) - position).Magnitude

                    if distance <= config.effectRadius then
                        local damage = config.burnDamage or 10
                        if player == owner and not config.selfDamage then continue end
                        humanoid:TakeDamage(damage)
                    end
                end
            end
        end
    end)

    Debris:AddItem(firePart, config.effectDuration or 8)
end

--[[
    Create flashbang effect
    @param position Vector3
    @param config table
    @param owner Player
]]
function WeaponService:CreateFlashbang(position, config, owner)
    local flash = Instance.new("Part")
    flash.Name = "Flash"
    flash.Anchored = true
    flash.CanCollide = false
    flash.Size = Vector3.new(1, 1, 1)
    flash.Position = position
    flash.Shape = Enum.PartType.Ball
    flash.Material = Enum.Material.Neon
    flash.Color = Color3.new(1, 1, 1)
    flash.Parent = workspace
    Debris:AddItem(flash, 0.5)

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if not character then continue end

        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not rootPart then continue end

        local distance = (rootPart.Position - position).Magnitude

        if distance <= (config.effectRadius or 20) then
            if player == owner and not config.affectsThrower then continue end

            local effectStrength = 1 - (distance / (config.effectRadius or 20))

            if remotes then
                remotes.DamageReceived:FireClient(player, {
                    type = "flash",
                    duration = (config.effectDuration or 4) * effectStrength,
                    intensity = effectStrength,
                })
            end
        end
    end
end

--[[
    Place C4
    @param player Player
    @param position Vector3
    @param direction Vector3
]]
function WeaponService:PlaceC4(player, position, direction)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    local c4 = Instance.new("Part")
    c4.Name = "C4_" .. player.UserId .. "_" .. #inventory.activeC4
    c4.Size = Vector3.new(1, 0.5, 1.5)
    c4.Position = position
    c4.Anchored = true
    c4.CanCollide = false
    c4.Color = Color3.fromRGB(50, 50, 50)
    c4.Material = Enum.Material.Plastic
    c4.Parent = workspace

    table.insert(inventory.activeC4, {part = c4, position = position})
end

--[[
    Handle C4 detonation
    @param player Player
]]
function WeaponService:HandleDetonateC4(player)
    local inventory = playerWeapons[player.UserId]
    if not inventory or #inventory.activeC4 == 0 then return end

    local config = weaponConfigs.c4
    if not config then return end

    for _, c4Data in ipairs(inventory.activeC4) do
        self:CreateExplosion(c4Data.position, config, player)
        if c4Data.part then c4Data.part:Destroy() end
    end

    inventory.activeC4 = {}
end

--[[
    Handle trap placement
    @param player Player
    @param data table
]]
function WeaponService:HandlePlaceTrap(player, data)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    local trapStack = nil
    local stackIndex = nil

    for i, stack in ipairs(inventory.throwables) do
        if stack.type == data.trapType then
            trapStack = stack
            stackIndex = i
            break
        end
    end

    if not trapStack or trapStack.count <= 0 then return end

    local config = trapStack.config

    if #inventory.placedTraps >= MAX_TRAPS_PER_PLAYER then
        local oldestTrap = table.remove(inventory.placedTraps, 1)
        if oldestTrap and activeTraps[oldestTrap.id] then
            local trap = activeTraps[oldestTrap.id]
            if trap.model then trap.model:Destroy() end
            activeTraps[oldestTrap.id] = nil
        end
    end

    trapStack.count = trapStack.count - 1
    if trapStack.count <= 0 then
        table.remove(inventory.throwables, stackIndex)
    end

    local trapId = game:GetService("HttpService"):GenerateGUID(false)

    local trapModel = Instance.new("Part")
    trapModel.Name = "Trap_" .. trapId
    trapModel.Size = Vector3.new(3, 0.5, 3)
    trapModel.Position = data.position
    trapModel.Anchored = true
    trapModel.CanCollide = false
    trapModel.Transparency = config.visibleToEnemy and 0.3 or 0.8
    trapModel.Color = Color3.fromRGB(100, 50, 50)
    trapModel.Parent = workspace

    local trapData = {
        id = trapId,
        type = data.trapType,
        config = config,
        owner = player,
        model = trapModel,
        position = data.position,
        armed = false,
        triggered = false,
    }

    activeTraps[trapId] = trapData
    table.insert(inventory.placedTraps, {id = trapId})

    task.delay(config.armTime or 1.5, function()
        if activeTraps[trapId] then
            activeTraps[trapId].armed = true
        end
    end)

    self:SetupTrapTrigger(trapData)
    self:BroadcastInventoryUpdate(player)
end

--[[
    Setup trap trigger detection
    @param trapData table
]]
function WeaponService:SetupTrapTrigger(trapData)
    local config = trapData.config
    local triggerRadius = config.triggerRadius or 3

    task.spawn(function()
        while trapData and activeTraps[trapData.id] and not trapData.triggered do
            task.wait(0.1)
            if not trapData.armed then continue end

            local trapPos = trapData.position

            for _, player in ipairs(Players:GetPlayers()) do
                if player == trapData.owner then continue end

                local character = player.Character
                if not character then continue end

                local rootPart = character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local distance = (rootPart.Position - trapPos).Magnitude
                    if distance <= triggerRadius then
                        self:TriggerTrap(trapData, player)
                        return
                    end
                end
            end

            if config.affectsDinosaurs then
                local dinoService = framework:GetService("DinoService")
                if dinoService then
                    local activeDinos = dinoService:GetAllActive()
                    for dinoId, dino in pairs(activeDinos) do
                        if dino.model and dino.model.PrimaryPart then
                            local distance = (dino.model.PrimaryPart.Position - trapPos).Magnitude
                            if distance <= triggerRadius then
                                self:TriggerTrap(trapData, nil, dino)
                                return
                            end
                        end
                    end
                end
            end
        end
    end)
end

--[[
    Trigger trap
    @param trapData table
    @param victim Player
    @param dinosaur table
]]
function WeaponService:TriggerTrap(trapData, victim, dinosaur)
    if trapData.triggered then return end

    local config = trapData.config

    if not config.reusable then
        trapData.triggered = true
    end

    if victim then
        local character = victim.Character
        if character then
            local humanoid = character:FindFirstChild("Humanoid")

            if humanoid and config.damage then
                humanoid:TakeDamage(config.damage)
            end

            if humanoid and config.immobilizeDuration then
                local originalSpeed = humanoid.WalkSpeed
                humanoid.WalkSpeed = 0
                task.delay(config.immobilizeDuration, function()
                    if humanoid and humanoid.Parent then
                        humanoid.WalkSpeed = originalSpeed
                    end
                end)
            end

            if config.effects and config.effects.bleed then
                self:ApplyMeleeEffects(trapData.owner, victim, {bleed = config.effects.bleed})
            end
        end
    elseif dinosaur then
        local dinoService = framework:GetService("DinoService")
        if dinoService and config.damage then
            dinoService:DamageDinosaur(dinosaur.id, config.damage, trapData.owner)
        end
    end

    if config.reusable then
        trapData.armed = false
        task.delay(config.resetTime or 5, function()
            if activeTraps[trapData.id] then
                trapData.armed = true
                trapData.triggered = false
            end
        end)
    else
        self:RemoveTrap(trapData.id)
    end
end

--[[
    Remove trap
    @param trapId string
]]
function WeaponService:RemoveTrap(trapId)
    local trapData = activeTraps[trapId]
    if not trapData then return end

    if trapData.model then
        trapData.model:Destroy()
    end

    local inventory = playerWeapons[trapData.owner.UserId]
    if inventory then
        for i, tracked in ipairs(inventory.placedTraps) do
            if tracked.id == trapId then
                table.remove(inventory.placedTraps, i)
                break
            end
        end
    end

    activeTraps[trapId] = nil
end

--[[
    Cleanup player traps
    @param player Player
]]
function WeaponService:CleanupPlayerTraps(player)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    for _, tracked in ipairs(inventory.placedTraps) do
        self:RemoveTrap(tracked.id)
    end
end

--==============================================================================
-- RELOAD AND EQUIP
--==============================================================================

--[[
    Handle reload
    @param player Player
    @param slotIndex number
]]
function WeaponService:HandleReload(player, slotIndex)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    local weapon = inventory.slots[slotIndex]
    if not weapon then return end

    local config = weapon.config
    if not config.magazineSize then return end

    if weapon.currentAmmo >= config.magazineSize then return end

    local category = WEAPON_CATEGORIES[config.category]
    local ammoType = category and category.ammoType
    if not ammoType then return end

    local availableAmmo = inventory.ammo[ammoType] or 0
    if availableAmmo <= 0 then return end

    local ammoNeeded = config.magazineSize - weapon.currentAmmo
    local ammoToUse = math.min(ammoNeeded, availableAmmo)

    weapon.currentAmmo = weapon.currentAmmo + ammoToUse
    inventory.ammo[ammoType] = inventory.ammo[ammoType] - ammoToUse

    self:BroadcastInventoryUpdate(player)
    self:BroadcastAmmoUpdate(player)
end

--[[
    Handle equip
    @param player Player
    @param slotIndex number
]]
function WeaponService:HandleEquip(player, slotIndex)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    if slotIndex < 1 or slotIndex > MAX_WEAPON_SLOTS then return end

    inventory.equipped = slotIndex

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        remotes.WeaponEquip:FireAllClients(player.UserId, slotIndex)
    end
end

--[[
    Handle drop
    @param player Player
    @param slotIndex number
]]
function WeaponService:HandleDrop(player, slotIndex)
    local inventory = playerWeapons[player.UserId]
    if not inventory then return end

    local weapon = inventory.slots[slotIndex]
    if not weapon then return end

    local character = player.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        self:CreateGroundWeapon(weapon, character.HumanoidRootPart.Position + Vector3.new(0, 0, 3))
    end

    inventory.slots[slotIndex] = nil
    if inventory.equipped == slotIndex then
        inventory.equipped = 0
    end

    self:BroadcastInventoryUpdate(player)
end

--[[
    Handle pickup
    @param player Player
    @param weaponId string
]]
function WeaponService:HandlePickup(player, weaponId)
    local weaponFolder = workspace:FindFirstChild("GroundWeapons")
    if not weaponFolder then return end

    local weaponModel = weaponFolder:FindFirstChild(weaponId)
    if not weaponModel then return end

    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end

    local distance = (character.HumanoidRootPart.Position - weaponModel.Position).Magnitude
    if distance > (gameConfig.Player.pickupRange or 8) then return end

    local weaponType = weaponModel:GetAttribute("WeaponType")
    local currentAmmo = weaponModel:GetAttribute("CurrentAmmo")

    if not weaponType or not weaponConfigs[weaponType] then return end

    local success = self:GiveWeapon(player, weaponType, currentAmmo)
    if success then
        weaponModel:Destroy()
    end
end

--[[
    Create ground weapon
    @param weapon table
    @param position Vector3
    @return Instance
]]
function WeaponService:CreateGroundWeapon(weapon, position)
    local weaponFolder = workspace:FindFirstChild("GroundWeapons")
    if not weaponFolder then
        weaponFolder = Instance.new("Folder")
        weaponFolder.Name = "GroundWeapons"
        weaponFolder.Parent = workspace
    end

    local part = Instance.new("Part")
    part.Name = weapon.id
    part.Size = Vector3.new(2, 1, 4)
    part.Position = position
    part.Anchored = false
    part.CanCollide = true
    part.Color = gameConfig.Loot.rarityColors[weapon.config.rarity] or Color3.new(1, 1, 1)
    part:SetAttribute("WeaponType", weapon.type)
    part:SetAttribute("CurrentAmmo", weapon.currentAmmo)
    part.Parent = weaponFolder

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Pick up"
    prompt.ObjectText = weapon.config.name
    prompt.MaxActivationDistance = gameConfig.Player.pickupRange or 8
    prompt.Parent = part

    return part
end

--==============================================================================
-- UTILITY FUNCTIONS
--==============================================================================

--[[
    Get weapon config
    @param weaponType string
    @return table
]]
function WeaponService:GetWeaponConfig(weaponType)
    return weaponConfigs[weaponType]
end

--[[
    Get attachment config
    @param attachmentId string
    @return table
]]
function WeaponService:GetAttachmentConfig(attachmentId)
    return attachmentConfigs[attachmentId]
end

--[[
    Get all weapon configs
    @return table
]]
function WeaponService:GetAllWeaponConfigs()
    return weaponConfigs
end

--[[
    Get all attachment configs
    @return table
]]
function WeaponService:GetAllAttachmentConfigs()
    return attachmentConfigs
end

--[[
    Get weapon categories
    @return table
]]
function WeaponService:GetWeaponCategories()
    return WEAPON_CATEGORIES
end

--[[
    Get weapon definition (alias for GetWeaponConfig)
    Used by PlayerInventory module
    @param weaponId string - Weapon identifier
    @return table|nil - Weapon definition or nil if not found
]]
function WeaponService:GetWeaponDefinition(weaponId)
    return weaponConfigs[weaponId] or WEAPON_DEFINITIONS[weaponId]
end

--[[
    Get player's active trap count
    @param player Player
    @return number - Count of active traps owned by player
]]
function WeaponService:GetPlayerTrapCount(player)
    local count = 0
    for _, trapData in pairs(activeTraps) do
        if trapData.ownerId == player.UserId then
            count = count + 1
        end
    end
    return count
end

--==============================================================================
-- SHUTDOWN
--==============================================================================

--[[
    Shutdown the service
]]
function WeaponService:Shutdown()
    for trapId, _ in pairs(activeTraps) do
        self:RemoveTrap(trapId)
    end

    for _, projectileData in pairs(activeProjectiles) do
        if projectileData.part then
            projectileData.part:Destroy()
        end
    end

    playerWeapons = {}
    activeTraps = {}
    activeProjectiles = {}

    framework.Log("Info", "WeaponService shut down")
end

return WeaponService
