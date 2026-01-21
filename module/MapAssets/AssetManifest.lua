--[[
    =========================================================================
    AssetManifest - Registry of all external assets used in Dino Royale 2
    =========================================================================

    This module contains all Roblox asset IDs and configuration for:
    - Terrain maps
    - Dinosaur models
    - Building structures
    - Vegetation and decorations
    - Sound effects

    Asset Sources:
    - Roblox Creator Store (free community assets)
    - DevForum open-source contributions

    Usage:
        local AssetManifest = require(path.to.AssetManifest)
        local terrainId = AssetManifest.Terrain.JungleIsland

    =========================================================================
]]

local AssetManifest = {}

--=============================================================================
-- TERRAIN MAPS
-- Large-scale terrain assets for the game world
-- Source: DevForum free terrain maps
--=============================================================================

AssetManifest.Terrain = {
    -- Primary jungle island map
    -- Source: https://devforum.roblox.com/t/free-large-and-detailed-terrain-maps/825340
    -- Features: High cliffs, canyons, rolling hills - perfect for Dino Island
    JungleIsland = {
        gameId = 4564507466,
        name = "Jungle Island",
        size = 2048,  -- Approximate size in studs
        author = "VlachSlvs",
    },

    -- Alternative large island map
    -- Source: https://devforum.roblox.com/t/a-surplus-of-open-sourced-terrain-maps/837081
    LargeIsland = {
        gameId = 5983725563,
        name = "Large Island",
        size = 3000,
        author = "FxllenCode",
    },

    -- Scottish highlands (for volcanic biome reference)
    ScottishHighlands = {
        gameId = 4929930657,
        name = "Scottish Highlands",
        size = 2000,
        author = "VlachSlvs",
    },

    -- Desert terrain (for facility/plains biome)
    Desert = {
        gameId = 4878757462,
        name = "Desert",
        size = 1500,
        author = "VlachSlvs",
    },
}

--=============================================================================
-- ASSET PACKS
-- Collections of props, buildings, and decorations
--=============================================================================

AssetManifest.AssetPacks = {
    -- The Ultimate Low Poly Asset Pack
    -- Source: https://devforum.roblox.com/t/free-the-ultimate-low-poly-asset-pack/1772603
    -- Contains: 22 vegetation, 12 buildings, 13 street assets, 17 bonus items,
    -- 11 modular dungeon assets, 23 interior design assets, 2 maps
    LowPolyUltimate = {
        assetId = 9492405836,
        name = "Ultimate Low Poly Asset Pack",
        categories = {"vegetation", "buildings", "street", "interior", "dungeon"},
    },

    -- Free Low Poly Asset Pack (352 assets, 21 themes)
    -- Source: https://devforum.roblox.com/t/free-low-poly-asset-pack/1306599
    LowPolyMega = {
        assetId = 10023352552,
        name = "Low Poly Mega Pack",
        categories = {"vegetation", "rocks", "trees", "grass"},
    },

    -- Stylized Ghibli-style assets
    -- Source: https://devforum.roblox.com/t/free-stylized-assets-by-orcaenvironments/2737986
    -- Contains: Ghibli-style rocks, anime-style trees
    StylizedAssets = {
        downloadFile = "Stylized_Assets.rbxm",
        name = "Stylized Assets",
        categories = {"rocks", "trees", "terrain"},
    },

    -- Optimized Forest Pack (uses LOD for performance)
    -- Source: https://devforum.roblox.com/t/optimized-forest-pack/1228976
    OptimizedForest = {
        assetId = nil,  -- Check DevForum for latest ID
        name = "Optimized Forest Pack",
        categories = {"trees", "forest", "vegetation"},
        features = {"LOD support", "performance optimized"},
    },
}

--=============================================================================
-- LOW POLY BUILDINGS (Individual)
-- Source: https://devforum.roblox.com/t/free-low-poly-buildings-accumulative/1080972
-- Free to use, no credit required
--=============================================================================

AssetManifest.LowPolyBuildings = {
    Store = {
        assetId = 6301604080,
        name = "Low Poly Store",
        author = "TheSaltyPeanuto",
    },

    House = {
        assetId = 6268497330,
        name = "Low Poly House",
        author = "TheSaltyPeanuto",
    },

    Office = {
        assetId = 6256989379,
        name = "Low Poly Office (Empty)",
        author = "TheSaltyPeanuto",
    },

    BarberShop = {
        assetId = 6258154611,
        name = "Low Poly Barber Shop with Road",
        author = "TheSaltyPeanuto",
    },

    Factory = {
        assetId = 6247256567,
        name = "Factory Low Poly Structures",
        author = "TheSaltyPeanuto",
    },

    Houses = {
        assetId = 5823449782,
        name = "Low Poly Houses Pack",
        author = "TheSaltyPeanuto",
    },
}

--=============================================================================
-- TREE PACKS
-- NOTE: Many DevForum tree packs don't have "Allow Copying" enabled and will
-- fail to load with InsertService:LoadAsset(). Only use assets that:
-- 1. You uploaded yourself
-- 2. Are explicitly marked "Allow Copying" in Creator Store
-- 3. Are from verified free-to-use packs
--
-- The game uses procedural placeholder trees when external assets fail to load.
-- To use custom trees, import them directly in Roblox Studio (File > Import).
--=============================================================================

AssetManifest.TreePacks = {
    -- Free Low Poly Trees (verified public, allow copying)
    -- Source: https://devforum.roblox.com/t/5-free-low-poly-trees/1229193
    FreeLowPolyTrees = {
        assetId = 6531788768,
        name = "Free Low Poly Trees",
        biomes = {"jungle", "plains", "coastal", "swamp"},
        author = "Community",
        allowCopying = true,
    },

    -- Customizable Low Poly Tree (verified public)
    -- Source: https://devforum.roblox.com/t/customizable-low-poly-tree/2735506
    CustomizableLowPoly = {
        assetId = 15590758157,
        name = "Customizable Low Poly Tree",
        biomes = {"jungle", "plains", "coastal"},
        author = "Community",
        allowCopying = true,
    },

    -- Free Realistic Trees (verified public)
    -- Source: https://devforum.roblox.com/t/free-realistic-trees/1585229
    FreeRealisticTrees = {
        assetId = 8118452766,
        name = "Free Realistic Trees",
        biomes = {"jungle", "plains", "swamp"},
        author = "Community",
        allowCopying = true,
    },

    -- Placeholder entries for biome-specific trees
    -- These use nil assetId to trigger procedural placeholder generation
    -- Import actual trees in Studio if you want specific models
    SubalpineForest = {
        assetId = nil,  -- Original 4467174685 doesn't allow copying
        name = "Subalpine Forest Trees",
        biomes = {"jungle", "plains"},
        note = "Import manually in Studio from DevForum",
    },

    VolcanicTrees = {
        assetId = nil,  -- Use placeholder charred trees
        name = "Volcanic Trees",
        biomes = {"volcanic"},
        note = "Uses procedural charred placeholder",
    },

    SwampTrees = {
        assetId = nil,  -- Use placeholder swamp trees
        name = "Swamp Trees",
        biomes = {"swamp"},
        note = "Uses procedural swamp placeholder",
    },
}

--=============================================================================
-- WEAPON MODELS
-- Gun and melee weapon models for the game
-- Source: Roblox Creator Store & DevForum
--=============================================================================

AssetManifest.Weapons = {
    -- FPS Gun Pack (FREE) - Multiple weapons
    -- Source: https://create.roblox.com/store/asset/11096757605/Fps-gun-pack-FREE
    FPSGunPack = {
        assetId = 11096757605,
        name = "FPS Gun Pack",
        weapons = {"assault_rifle", "smg", "pistol", "shotgun", "sniper"},
    },

    -- Gun Models Collection
    -- Source: https://create.roblox.com/store/asset/8976938735/gun-models
    GunModels = {
        assetId = 8976938735,
        name = "Gun Models Collection",
        weapons = {"various"},
    },

    -- Individual weapon placeholder IDs (to be filled with specific models)
    AssaultRifle = {
        assetId = nil,  -- Use from FPSGunPack
        name = "Assault Rifle",
        category = "assault_rifle",
    },

    SMG = {
        assetId = nil,  -- Use from FPSGunPack
        name = "SMG",
        category = "smg",
    },

    Shotgun = {
        assetId = nil,  -- Use from FPSGunPack
        name = "Shotgun",
        category = "shotgun",
    },

    SniperRifle = {
        assetId = nil,  -- Use from FPSGunPack
        name = "Sniper Rifle",
        category = "sniper",
    },

    Pistol = {
        assetId = nil,  -- Use from FPSGunPack
        name = "Pistol",
        category = "pistol",
    },

    -- Melee weapons
    Machete = {
        assetId = nil,
        name = "Machete",
        category = "melee",
    },

    CombatKnife = {
        assetId = nil,
        name = "Combat Knife",
        category = "melee",
    },
}

--=============================================================================
-- DINOSAUR MODELS
-- Pre-made dinosaur models for the game
-- Source: Roblox Creator Store
--=============================================================================

AssetManifest.Dinosaurs = {
    -- Rigged dinosaur pack (multiple dinos, animation-ready)
    -- Source: https://create.roblox.com/store/asset/102772249876319/Rigged-Dinosaur-Models
    RiggedPack = {
        assetId = 102772249876319,
        name = "Rigged Dinosaur Models",
        types = {"raptor", "trex", "pteranodon", "triceratops", "spinosaurus"},
        hasAnimations = true,
    },

    -- JPOG-style dinosaurs (Jurassic Park: Operation Genesis inspired)
    -- Source: https://create.roblox.com/store/asset/17132239877/JPOG-Dinosaur-models
    JPOGPack = {
        assetId = 17132239877,
        name = "JPOG Dinosaur Models",
        types = {"various"},
        style = "realistic",
    },

    -- Individual dinosaur models with stats
    Allosaurus = {
        assetId = 163023643,
        name = "Allosaurus",
        health = 500,
        damage = 35,
        speed = 28,
        category = "solo_predator",
    },

    Giganotosaurus = {
        assetId = 287958375,
        name = "Giganotosaurus",
        health = 800,
        damage = 50,
        speed = 24,
        isBoss = true,
        category = "solo_predator",
    },

    IndomnusRex = {
        assetId = 2158624411,
        name = "Indominus Rex",
        health = 1500,
        damage = 75,
        speed = 30,
        isBoss = true,
        category = "apex_predator",
        abilities = {"camouflage", "roar"},
    },

    -- Core game dinosaurs (use from RiggedPack or JPOGPack)
    Raptor = {
        assetId = nil,  -- Use from RiggedPack
        packSource = "RiggedPack",
        name = "Velociraptor",
        health = 150,
        damage = 25,
        speed = 35,
        category = "pack_hunter",
    },

    TRex = {
        assetId = nil,  -- Use from RiggedPack
        packSource = "RiggedPack",
        name = "Tyrannosaurus Rex",
        health = 800,
        damage = 60,
        speed = 18,
        category = "solo_predator",
    },

    Pteranodon = {
        assetId = nil,  -- Use from RiggedPack
        packSource = "RiggedPack",
        name = "Pteranodon",
        health = 100,
        damage = 15,
        speed = 45,
        canFly = true,
        category = "aerial_diver",
    },

    Triceratops = {
        assetId = nil,  -- Use from RiggedPack
        packSource = "RiggedPack",
        name = "Triceratops",
        health = 500,
        damage = 40,
        speed = 15,
        armor = 0.3,
        category = "defensive_charger",
    },

    Spinosaurus = {
        assetId = nil,  -- Use from RiggedPack
        packSource = "RiggedPack",
        name = "Spinosaurus",
        health = 650,
        damage = 55,
        speed = 20,
        category = "solo_predator",
    },

    Dilophosaurus = {
        assetId = nil,
        packSource = "JPOGPack",
        name = "Dilophosaurus",
        health = 120,
        damage = 25,
        speed = 22,
        hasRangedAttack = true,
        category = "ranged_spitter",
    },

    Carnotaurus = {
        assetId = nil,
        packSource = "JPOGPack",
        name = "Carnotaurus",
        health = 300,
        damage = 45,
        speed = 30,
        category = "ambush_predator",
    },

    Compy = {
        assetId = nil,
        name = "Compsognathus",
        health = 25,
        damage = 8,
        speed = 32,
        category = "swarm",
        packSize = {min = 5, max = 10},
    },
}

--=============================================================================
-- VFX AND PARTICLE EFFECTS
-- Visual effects for combat, environment, and dinosaurs
-- Source: DevForum open-source VFX
--=============================================================================

AssetManifest.VFX = {
    -- CIX Library Plugin (600+ free particles)
    -- Source: https://devforum.roblox.com/t/over-600-free-particle-with-cix-library/2864815
    -- Plugin that provides easy access to 600+ particle effects
    CIXLibrary = {
        pluginId = nil,  -- Install via Plugin marketplace
        name = "CIX Particle Library",
        particleCount = 600,
    },

    -- Yuruzuu's Open Source VFX
    -- Source: https://devforum.roblox.com/t/yuruzuus-open-source-vfx/1840021
    YuruzuuVFX = {
        assetId = nil,  -- Check DevForum for model ID
        name = "Yuruzuu VFX Pack",
        effects = {"explosions", "impacts", "trails"},
    },

    -- Free Realistic Flipbook Explosions
    -- Source: https://devforum.roblox.com/t/2-free-realistic-flipbook-particle-explosions/3035597
    -- High quality explosion effects, no credit required
    RealisticExplosions = {
        assetId = 17040521870,
        name = "Flipbook Particle Explosions",
        effects = {"explosion_fx1", "explosion_fx2"},
        author = "DevForum",
    },

    -- Muzzle flash particles
    MuzzleFlash = {
        -- Custom or from VFX packs
        color = Color3.fromRGB(255, 200, 50),
        size = NumberSequence.new(0.5, 0),
        lifetime = 0.05,
    },

    -- Bullet impact sparks
    BulletImpact = {
        color = Color3.fromRGB(255, 200, 100),
        sparkCount = 8,
        spread = 180,
    },

    -- Dinosaur breath/roar effect
    DinoBreath = {
        color = Color3.fromRGB(100, 200, 100),
        size = NumberSequence.new(1, 3),
        lifetime = 0.5,
    },

    -- Blood/damage effect (stylized, not realistic)
    DamageEffect = {
        color = Color3.fromRGB(200, 50, 50),
        particleCount = 5,
        spread = 45,
    },

    -- Storm/zone edge effect
    StormEdge = {
        color = Color3.fromRGB(100, 50, 150),
        transparency = 0.3,
        particleDensity = 0.1,
    },

    -- Loot glow effects by rarity
    LootGlow = {
        common = Color3.fromRGB(180, 180, 180),
        uncommon = Color3.fromRGB(50, 200, 50),
        rare = Color3.fromRGB(50, 100, 255),
        epic = Color3.fromRGB(150, 50, 200),
        legendary = Color3.fromRGB(255, 180, 0),
    },
}

--=============================================================================
-- BUILDING PREFABS
-- Structures for POI locations
--=============================================================================

AssetManifest.Buildings = {
    -- Research/Lab buildings
    ResearchLab = {
        source = "LowPolyUltimate",
        category = "buildings",
        name = "Research Laboratory",
        footprint = Vector3.new(30, 15, 40),
    },

    MilitaryOutpost = {
        source = "LowPolyUltimate",
        category = "buildings",
        name = "Military Outpost",
        footprint = Vector3.new(25, 10, 25),
    },

    -- Natural structures
    WoodenHut = {
        source = "StylizedAssets",
        category = "buildings",
        name = "Wooden Hut",
        footprint = Vector3.new(10, 8, 10),
    },

    Watchtower = {
        source = "LowPolyUltimate",
        category = "buildings",
        name = "Watchtower",
        footprint = Vector3.new(8, 20, 8),
    },

    -- Industrial
    WarehouseSmall = {
        source = "LowPolyUltimate",
        category = "buildings",
        name = "Small Warehouse",
        footprint = Vector3.new(20, 12, 30),
    },

    WarehouseLarge = {
        source = "LowPolyUltimate",
        category = "buildings",
        name = "Large Warehouse",
        footprint = Vector3.new(40, 15, 50),
    },
}

--=============================================================================
-- VEGETATION
-- Trees, rocks, plants for biome decoration
--=============================================================================

AssetManifest.Vegetation = {
    -- Jungle biome
    JungleTrees = {
        source = "StylizedAssets",
        density = 0.3,  -- Trees per 100 studs squared
        scale = {min = 0.8, max = 1.5},
    },

    JungleRocks = {
        source = "StylizedAssets",
        density = 0.15,
        scale = {min = 0.5, max = 2.0},
    },

    -- Plains biome
    GrassTufts = {
        source = "LowPolyUltimate",
        density = 0.5,
        scale = {min = 0.8, max = 1.2},
    },

    SmallRocks = {
        source = "LowPolyUltimate",
        density = 0.1,
        scale = {min = 0.3, max = 1.0},
    },

    -- Volcanic biome
    CharredTrees = {
        source = "custom",
        density = 0.1,
        scale = {min = 0.6, max = 1.0},
    },

    LavaRocks = {
        source = "custom",
        density = 0.2,
        scale = {min = 0.5, max = 2.5},
    },

    -- Swamp biome
    SwampTrees = {
        source = "StylizedAssets",
        density = 0.25,
        scale = {min = 1.0, max = 1.8},
    },

    SwampVines = {
        source = "LowPolyUltimate",
        density = 0.4,
        scale = {min = 0.8, max = 1.5},
    },
}

--=============================================================================
-- SOUND EFFECTS
-- Audio assets for dinosaurs and environment
--=============================================================================

AssetManifest.Sounds = {
    -- Dinosaur sounds
    DinoFootsteps = {
        assetId = 9125404774,  -- "Boomy Footsteps Giant Thumpy Dinosaur"
        name = "Dinosaur Footsteps",
        volume = 0.8,
    },

    RaptorRoar = {
        assetId = nil,  -- Placeholder
        name = "Raptor Roar",
        volume = 1.0,
    },

    TRexRoar = {
        assetId = nil,  -- Placeholder
        name = "T-Rex Roar",
        volume = 1.0,
    },

    -- Ambient sounds
    JungleAmbient = {
        assetId = nil,  -- Placeholder
        name = "Jungle Ambience",
        volume = 0.5,
        looped = true,
    },

    VolcanicAmbient = {
        assetId = nil,  -- Placeholder
        name = "Volcanic Rumble",
        volume = 0.6,
        looped = true,
    },
}

--=============================================================================
-- POI ASSET MAPPING
-- Maps POI names from GameConfig to specific building configurations
--=============================================================================

AssetManifest.POIMappings = {
    ["Raptor Ridge"] = {
        buildings = {"Watchtower", "WoodenHut", "WoodenHut"},
        vegetation = "JungleTrees",
        chestCount = 4,
    },

    ["Volcano Lair"] = {
        buildings = {"WarehouseLarge", "MilitaryOutpost"},
        vegetation = "LavaRocks",
        chestCount = 6,
    },

    ["Swamp Base"] = {
        buildings = {"WoodenHut", "WoodenHut", "Watchtower"},
        vegetation = "SwampTrees",
        chestCount = 4,
    },

    ["Research Lab"] = {
        buildings = {"ResearchLab", "WarehouseSmall"},
        vegetation = "GrassTufts",
        chestCount = 5,
    },

    ["Dino Graveyard"] = {
        buildings = {},  -- Open area with fossils
        vegetation = "SmallRocks",
        chestCount = 3,
    },

    ["Coastal Cliffs"] = {
        buildings = {"Watchtower", "WarehouseSmall"},
        vegetation = "GrassTufts",
        chestCount = 4,
    },

    ["Ptero Peak"] = {
        buildings = {"Watchtower"},
        vegetation = "JungleRocks",
        chestCount = 3,
    },

    ["Rex Domain"] = {
        buildings = {"MilitaryOutpost", "WarehouseLarge"},
        vegetation = "JungleTrees",
        chestCount = 6,
    },

    ["Jungle Temple"] = {
        buildings = {},  -- Custom temple structure
        vegetation = "JungleTrees",
        chestCount = 5,
    },

    ["Hot Springs"] = {
        buildings = {"WoodenHut"},
        vegetation = "SwampTrees",
        chestCount = 3,
    },

    -- Additional POIs from GameConfig
    ["Power Station"] = {
        buildings = {"WarehouseLarge", "WarehouseSmall"},
        vegetation = "GrassTufts",
        chestCount = 5,
    },

    ["Pteranodon Aviary"] = {
        buildings = {"Watchtower", "Watchtower"},
        vegetation = "JungleTrees",
        chestCount = 4,
    },

    ["Communications Tower"] = {
        buildings = {"Watchtower", "WarehouseSmall"},
        vegetation = "GrassTufts",
        chestCount = 4,
    },

    ["Visitor Center"] = {
        buildings = {"ResearchLab", "WarehouseSmall", "WoodenHut"},
        vegetation = "GrassTufts",
        chestCount = 6,
    },

    ["Swamp Research Outpost"] = {
        buildings = {"WoodenHut", "WoodenHut", "Watchtower"},
        vegetation = "SwampTrees",
        chestCount = 4,
    },

    ["T-Rex Kingdom"] = {
        buildings = {"MilitaryOutpost", "WarehouseLarge", "Watchtower"},
        vegetation = "JungleTrees",
        chestCount = 7,
    },

    ["Volcano Summit"] = {
        buildings = {"MilitaryOutpost"},
        vegetation = "LavaRocks",
        chestCount = 5,
    },

    ["Genetics Laboratory"] = {
        buildings = {"ResearchLab", "ResearchLab", "WarehouseSmall"},
        vegetation = "GrassTufts",
        chestCount = 6,
    },

    ["Main Dock"] = {
        buildings = {"WarehouseSmall", "WarehouseSmall", "WoodenHut"},
        vegetation = "GrassTufts",
        chestCount = 5,
    },

    ["Raptor Paddock"] = {
        buildings = {"MilitaryOutpost", "Watchtower", "Watchtower"},
        vegetation = "JungleTrees",
        chestCount = 5,
    },

    -- Minor POIs (smaller locations)
    ["Supply Cache"] = {
        buildings = {"WoodenHut"},
        vegetation = "SmallRocks",
        chestCount = 2,
    },

    ["Emergency Bunker"] = {
        buildings = {"WarehouseSmall"},
        vegetation = "SmallRocks",
        chestCount = 3,
    },

    ["Ranger Station"] = {
        buildings = {"WoodenHut", "Watchtower"},
        vegetation = "JungleTrees",
        chestCount = 3,
    },

    ["Crashed Helicopter"] = {
        buildings = {},  -- Wreckage only, no buildings
        vegetation = "SmallRocks",
        chestCount = 2,
    },
}

return AssetManifest
