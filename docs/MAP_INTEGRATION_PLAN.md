# Dino Royale 2 - Map & Terrain Integration Plan

## Overview

This document outlines the recommended 3D terrain, buildings, and visual assets for Dino Royale 2, along with the integration plan for the codebase.

## Recommended Assets

### Primary Terrain Map

**Jungle Terrain Map by VlachSlvs**
- **Source:** [Roblox DevForum - Free Large Terrain Maps](https://devforum.roblox.com/t/free-large-and-detailed-terrain-maps-different-biomes-geographical-areas/825340)
- **Game ID:** `4564507466`
- **Download:** VlachSlvs-Place-Number-53.rbxl (1.2 MB)
- **Features:** Large jungle map with high cliffs, canyons, and rolling hills
- **Size:** Approximately 2000+ studs - fits our 2048x2048 map configuration
- **License:** Free to use (credit optional)

**Why This Map:**
- Matches our "Dino Island" jungle theme perfectly
- Has varied elevation for tactical gameplay
- Large enough for 60-player battle royale
- Pre-built terrain saves significant development time

### Supplementary Island Maps

**FxllenCode's Open-Source Islands**
- **Source:** [Roblox DevForum - Surplus of Open-Sourced Terrain Maps](https://devforum.roblox.com/t/a-surplus-of-open-sourced-terrain-maps/837081)
- **Island 1 Game ID:** `5798157535`
- **Large Island Game ID:** `5983725563`
- **License:** Free (no resale, no claiming as own)

### Vegetation & Environment Assets

**The Ultimate Low Poly Asset Pack**
- **Source:** [Roblox DevForum](https://devforum.roblox.com/t/free-the-ultimate-low-poly-asset-pack-added-more-assets/1772603)
- **Asset ID:** `9492405836`
- **Includes:**
  - 22 vegetation assets (trees, rocks, plants, flowers)
  - 12 building structures
  - 13 street assets
  - 2 complete maps for reference
- **License:** Free to use (credit appreciated)

**Stylized Assets by orcaenvironments**
- **Source:** [Roblox DevForum](https://devforum.roblox.com/t/free-stylized-assets-by-orcaenvironments/2737986)
- **Download:** Stylized_Assets.rbxm (3.5 MB)
- **Includes:** Ghibli-style rocks, anime-style trees
- **Perfect for:** Jungle/tropical biome decoration

### Dinosaur Models

**Rigged Dinosaur Models**
- **Asset ID:** `102772249876319`
- **Source:** [Roblox Creator Store](https://create.roblox.com/store/asset/102772249876319/Rigged-Dinosaur-Models)
- **Features:** Pre-rigged for animation

**JPOG Dinosaur Collection**
- **Asset ID:** `17132239877`
- **Source:** [Roblox Creator Store](https://create.roblox.com/store/asset/17132239877/JPOG-Dinosaur-models)
- **Style:** Jurassic Park inspired models

**Individual Dinosaur Models:**
- Allosaurus: `163023643`
- Giganotosaurus: `287958375`
- Indominus Rex: `2158624411`

### Building Assets for POIs

**KW Studio Free Maps** (for building reference/extraction)
- **Source:** [KW Studio](https://kwstudio.org/free-roblox-maps)
- **Features:** Optimized for mobile performance, clean hierarchy
- **Good for:** Military facility, research lab POI buildings

---

## Integration Architecture

### Phase 1: Asset Loading System

Create a new module to handle asset loading and instantiation:

```
module/
  MapAssets/
    init.lua           -- Asset loading and management
    AssetManifest.lua  -- Asset IDs and configurations
```

### Phase 2: MapService Enhancement

Update MapService to support physical terrain:

```lua
-- New methods to add:
MapService:LoadTerrain(terrainId)      -- Load terrain from asset
MapService:SpawnPOIBuildings()          -- Instantiate POI structures
MapService:GetTerrainHeight(x, z)       -- Query terrain elevation
MapService:SetupBiomeDecorations()      -- Add vegetation per biome
```

### Phase 3: POI Building Placement

Map each POI from GameConfig to physical structures:

| POI Name | Building Type | Asset Source |
|----------|---------------|--------------|
| Raptor Ridge | Research Outpost | Low Poly Pack |
| Volcano Lair | Industrial Facility | KW Studio |
| Swamp Base | Wooden Structures | Stylized Assets |
| Research Lab | Modern Building | Low Poly Pack |
| Dino Graveyard | Ruins/Fossils | Custom |
| Coastal Cliffs | Lighthouse/Dock | Low Poly Pack |

---

## File Structure Changes

```
dino-royale2/
  module/
    MapAssets/
      init.lua              -- NEW: Asset loading system
      AssetManifest.lua     -- NEW: Asset ID registry
  service/
    MapService/
      init.lua              -- UPDATE: Add terrain methods
  workspace/
    Terrain/                -- Terrain data (loaded at runtime)
    POIBuildings/           -- POI structure instances
    Decorations/            -- Vegetation, props
    LootSpawnPoints/        -- Physical spawn markers
    ChestSpawnPoints/       -- Chest location markers
```

---

## Implementation Steps

### Step 1: Create AssetManifest Module

```lua
-- module/MapAssets/AssetManifest.lua
return {
    Terrain = {
        JungleIsland = 4564507466,  -- Main map
        LargeIsland = 5983725563,   -- Alternative
    },

    AssetPacks = {
        LowPolyUltimate = 9492405836,
        StylizedAssets = "rbxassetid://stylized_assets",
    },

    Dinosaurs = {
        Raptor = 102772249876319,
        TRex = 17132239877,
        Allosaurus = 163023643,
    },

    Buildings = {
        ResearchLab = "from_low_poly_pack",
        MilitaryBase = "from_kw_studio",
        WoodenHut = "from_stylized_assets",
    },
}
```

### Step 2: Create MapAssets Module

```lua
-- module/MapAssets/init.lua
local InsertService = game:GetService("InsertService")
local AssetManifest = require(script.AssetManifest)

local MapAssets = {}

function MapAssets:LoadAsset(assetId)
    return InsertService:LoadAsset(assetId)
end

function MapAssets:SpawnBuilding(buildingType, position, rotation)
    -- Instantiate building at position
end

function MapAssets:SetupTerrain()
    -- Load and configure terrain
end

return MapAssets
```

### Step 3: Update MapService

Add physical terrain support while maintaining backward compatibility with logical map data.

### Step 4: Workspace Setup Script

Create a one-time setup script to:
1. Load terrain asset
2. Place POI markers
3. Add loot spawn points
4. Configure biome boundaries

---

## Download Instructions

### Manual Asset Import (Recommended for Initial Setup)

1. **Jungle Terrain:**
   - Visit: https://www.roblox.com/games/4564507466
   - Open in Roblox Studio
   - Copy terrain to your place

2. **Low Poly Asset Pack:**
   - In Roblox Studio: Toolbox > Search "9492405836"
   - Insert into workspace
   - Organize assets into folders

3. **Dinosaur Models:**
   - Search each Asset ID in Creator Store
   - Import to ServerStorage for runtime spawning

### Programmatic Loading (Runtime)

```lua
local InsertService = game:GetService("InsertService")
local assetId = 9492405836  -- Low Poly Pack
local model = InsertService:LoadAsset(assetId)
model.Parent = workspace
```

---

## Performance Considerations

1. **Streaming Enabled:** Enable workspace streaming for large terrain
2. **LOD Groups:** Use Level of Detail for distant objects
3. **Collision Optimization:** Disable CanCollide on decorative vegetation
4. **Instance Count:** Keep under 50,000 parts for mobile compatibility

---

## Next Steps

1. [ ] Download jungle terrain map (VlachSlvs)
2. [ ] Import Low Poly Asset Pack
3. [ ] Import Stylized Assets
4. [ ] Create MapAssets module
5. [ ] Place POI buildings manually in Studio
6. [ ] Add spawn point markers
7. [ ] Test with MapService integration
8. [ ] Optimize for performance

---

## Sources

- [Free Large Terrain Maps - DevForum](https://devforum.roblox.com/t/free-large-and-detailed-terrain-maps-different-biomes-geographical-areas/825340)
- [Ultimate Low Poly Asset Pack - DevForum](https://devforum.roblox.com/t/free-the-ultimate-low-poly-asset-pack-added-more-assets/1772603)
- [Stylized Assets - DevForum](https://devforum.roblox.com/t/free-stylized-assets-by-orcaenvironments/2737986)
- [Open-Sourced Terrain Maps - DevForum](https://devforum.roblox.com/t/a-surplus-of-open-sourced-terrain-maps/837081)
- [Roblox Creator Store - Dinosaurs](https://create.roblox.com/store/models)
- [KW Studio Free Maps](https://kwstudio.org/free-roblox-maps)
