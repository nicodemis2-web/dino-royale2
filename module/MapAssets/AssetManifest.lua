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
    -- Contains: 22 vegetation, 12 buildings, 13 street assets, 17 bonus items
    LowPolyUltimate = {
        assetId = 9492405836,
        name = "Ultimate Low Poly Asset Pack",
        categories = {"vegetation", "buildings", "street", "interior"},
    },

    -- Stylized Ghibli-style assets
    -- Source: https://devforum.roblox.com/t/free-stylized-assets-by-orcaenvironments/2737986
    -- Contains: Ghibli-style rocks, anime-style trees
    StylizedAssets = {
        downloadFile = "Stylized_Assets.rbxm",
        name = "Stylized Assets",
        categories = {"rocks", "trees", "terrain"},
    },
}

--=============================================================================
-- DINOSAUR MODELS
-- Pre-made dinosaur models for the game
-- Source: Roblox Creator Store
--=============================================================================

AssetManifest.Dinosaurs = {
    -- Rigged dinosaur pack (multiple dinos, animation-ready)
    RiggedPack = {
        assetId = 102772249876319,
        name = "Rigged Dinosaur Models",
        types = {"raptor", "trex", "pteranodon"},
    },

    -- JPOG-style dinosaurs (Jurassic Park inspired)
    JPOGPack = {
        assetId = 17132239877,
        name = "JPOG Dinosaur Models",
        types = {"various"},
    },

    -- Individual dinosaur models
    Allosaurus = {
        assetId = 163023643,
        name = "Allosaurus",
        health = 500,
        damage = 35,
        speed = 28,
    },

    Giganotosaurus = {
        assetId = 287958375,
        name = "Giganotosaurus",
        health = 800,
        damage = 50,
        speed = 24,
        isBoss = true,
    },

    IndomnusRex = {
        assetId = 2158624411,
        name = "Indominus Rex",
        health = 1500,
        damage = 75,
        speed = 30,
        isBoss = true,
    },

    -- Placeholder for custom raptor model
    Raptor = {
        assetId = nil,  -- Use custom or from RiggedPack
        name = "Velociraptor",
        health = 150,
        damage = 25,
        speed = 35,
    },

    -- Placeholder for pteranodon
    Pteranodon = {
        assetId = nil,  -- Use from RiggedPack
        name = "Pteranodon",
        health = 100,
        damage = 15,
        speed = 45,
        canFly = true,
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
}

return AssetManifest
