# Dino Royale 2 - Game Design Document

## Overview

**Title:** Dino Royale 2
**Platform:** Roblox
**Genre:** Battle Royale with Dinosaur AI
**Players:** 1-20 per match
**Target Audience:** Ages 9+, fans of battle royale and dinosaur games

### Elevator Pitch

Dino Royale 2 is a fast-paced battle royale where players compete against each other AND against AI-controlled dinosaurs in a prehistoric-themed arena. Survive the shrinking zone, battle other players, and avoid becoming dino food in matches lasting 5-10 minutes.

### Core Pillars

1. **Fast-Paced Action** - Short matches with constant engagement
2. **Dynamic PvEvP** - Players vs Players vs Dinosaurs creates unpredictable encounters
3. **Strategic Depth** - Multiple weapon types, dinosaur behaviors, and map features
4. **Accessible Fun** - Easy to learn, rewarding to master

---

## Game Modes

### Solo
- 20 players, free-for-all
- Last player standing wins
- No revives

### Duos
- 10 teams of 2 players
- Teammates can revive downed allies (5 second channel)
- 30 second bleedout timer when downed
- Last team standing wins

### Trios
- 7 teams of 3 players
- Same revive mechanics as Duos
- Last team standing wins

---

## Core Gameplay Loop

1. **Lobby** - Players wait (up to 60 seconds) for match to start
2. **Drop Phase** - Players spawn in air, choose landing location
3. **Loot Phase** - Scavenge weapons, ammo, healing items
4. **Combat Phase** - Fight players and dinosaurs as zone shrinks
5. **Endgame** - Final survivors battle in tight zone
6. **Victory/Defeat** - Match ends, return to lobby

---

## Map Design

### Map Overview

The map is a 1000x1000 stud island divided into 6 distinct biomes, each with unique environmental features and dinosaur spawns.

### Biomes

| Biome | Description | Special Features |
|-------|-------------|------------------|
| **Dense Jungle** | Thick vegetation, limited visibility | +20% dino spawns, fog |
| **Volcanic Wastes** | Lava pools, eruption hazards | Environmental damage |
| **Murky Swamp** | Water hazards, slow movement | 20% movement penalty |
| **Research Facility** | Indoor areas, high-tech | +50% loot quality |
| **Open Plains** | Wide open spaces | +50% visibility, scarce cover |
| **Coastal Cliffs** | Beach and cliffs | Pteranodon spawns +100% |

### Points of Interest (POIs)

#### Major POIs (Named Locations)

| POI | Biome | Loot Tier | Description |
|-----|-------|-----------|-------------|
| **Visitor Center** | Facility | Epic | Main building, central location |
| **Raptor Paddock** | Jungle | Rare | Fenced area, raptor spawns |
| **T-Rex Kingdom** | Plains | Legendary | T-Rex guaranteed, high risk/reward |
| **Genetics Lab** | Facility | Epic | Multi-story building, tech loot |
| **Aviary** | Coastal | Rare | Dome structure, pteranodons |
| **Cargo Docks** | Coastal | Uncommon | Shipping containers, open area |
| **Communications Tower** | Plains | Rare | Tall structure, sniper spot |
| **Power Station** | Volcanic | Uncommon | Industrial, hazards nearby |

#### Minor POIs

- **Ranger Stations** - Small outposts scattered across map
- **Bunkers** - Underground shelters with rare loot
- **Crashed Helicopters** - Supply spawns
- **Supply Caches** - Random small loot spots

### Environmental Events

Random events that occur during matches:

| Event | Duration | Effect |
|-------|----------|--------|
| **Volcanic Eruption** | 30s | Area damage in volcanic biome |
| **Dinosaur Stampede** | 20s | 8 dinos charge through area |
| **Meteor Shower** | 15s | Random explosive impacts |
| **Toxic Gas** | 25s | DoT + slow in affected area |
| **Supply Drop** | - | Legendary loot crate drops |
| **Alpha Spawn** | - | Boss dinosaur appears |

---

## Dinosaur System

### Dinosaur Behaviors

| Behavior | Description | Examples |
|----------|-------------|----------|
| **Pack Hunter** | Coordinate attacks, flank targets | Raptor |
| **Solo Predator** | High damage, direct approach | T-Rex, Spinosaurus |
| **Aerial Diver** | Attack from above | Pteranodon |
| **Defensive Charger** | Passive until provoked | Triceratops |
| **Ranged Spitter** | Projectile attacks, maintains distance | Dilophosaurus |
| **Ambush Predator** | Camouflage, surprise attacks | Carnotaurus |
| **Swarm** | Attack in large numbers | Compy |

### Dinosaur Types

| Dinosaur | Health | Damage | Speed | Special |
|----------|--------|--------|-------|---------|
| **Raptor** | 150 | 20 | 28 | Pounce, Pack Tactics |
| **T-Rex** | 800 | 60 | 18 | Roar, Charge, Tail Swipe |
| **Pteranodon** | 100 | 15 | 35 | Dive Bomb, Flight |
| **Triceratops** | 500 | 40 | 15 | Charge (30% armor) |
| **Dilophosaurus** | 120 | 25 | 22 | Venom Spit (blind + DoT) |
| **Carnotaurus** | 300 | 45 | 30 | Camouflage, Pounce |
| **Compy** | 25 | 8 | 32 | Swarm Damage Bonus |
| **Spinosaurus** | 650 | 55 | 20 | Tail Swipe, Roar |

### Pack System

- Dinosaurs spawn in packs with designated leaders
- Pack members receive +20% damage when leader is alive
- Flanking behavior for coordinated attacks
- Pack scatters when leader is killed

### Special Abilities

| Ability | Effect | Cooldown |
|---------|--------|----------|
| **Roar** | Fear effect, slows players | 15s |
| **Charge** | Dash attack + knockback | 8s |
| **Pounce** | Gap closer + stun | 5s |
| **Venom Spit** | Blind + DoT damage | 6s |
| **Tail Swipe** | AoE knockback | 4s |
| **Dive Bomb** | Aerial attack + stun | 7s |
| **Camouflage** | Become invisible, 2x ambush damage | 20s |
| **Ground Pound** | AoE stun (boss only) | 12s |

### Boss Dinosaurs (Alphas)

Rare spawns with enhanced stats and unique abilities:

| Boss | Base | HP Multiplier | Special Abilities |
|------|------|---------------|-------------------|
| **Alpha Rex** | T-Rex | 3.0x (2400 HP) | Ground Pound, Summon Raptors |
| **Alpha Raptor** | Raptor | 4.0x (600 HP) | Pack Call, Frenzy |
| **Alpha Spino** | Spinosaurus | 2.5x (1625 HP) | Tidal Wave, Submerge |

Bosses have **3 phases** based on health:
- Phase 1: 100-66% HP - Normal attacks
- Phase 2: 66-33% HP - Unlocks new abilities
- Phase 3: <33% HP - Rage mode (+50% damage, +30% speed)

---

## Weapon System

### Weapon Categories

| Category | Slot | Ammo Type | Playstyle |
|----------|------|-----------|-----------|
| **Assault Rifle** | 1 | Medium | Versatile, medium range |
| **SMG** | 2 | Light | High fire rate, close range |
| **Shotgun** | 3 | Shells | Devastating close range |
| **Sniper** | 4 | Heavy | Long range, high damage |
| **Pistol** | 5 | Light | Sidearm, backup |
| **Melee** | 6 | None | Silent, special effects |
| **Explosive** | 7 | Rockets | Area damage |
| **Throwable** | 8 | None | Utility and damage |
| **Trap** | 9 | None | Area denial |

### Ranged Weapons

#### Assault Rifles
- **AK-47** - High damage, high recoil
- **M4A1** - Balanced, versatile
- **SCAR** - Premium, low recoil

#### SMGs
- **MP5** - Balanced SMG
- **Uzi** - High fire rate
- **P90** - Large magazine

#### Shotguns
- **Pump Shotgun** - High damage, slow
- **Tactical Shotgun** - Faster fire rate
- **Double Barrel** - Two quick shots

#### Snipers
- **Bolt-Action** - High damage, slow
- **Semi-Auto Sniper** - Faster follow-up
- **Heavy Sniper** - Penetrates cover

#### Pistols
- **Glock** - Fast fire rate
- **Desert Eagle** - High damage
- **Revolver** - Precision

### Melee Weapons

| Weapon | Damage | Special Effect |
|--------|--------|----------------|
| **Machete** | 35 | Bleed (3 dmg/s for 5s) |
| **Spear** | 40 | Throwable, +50% vs dinos |
| **Stun Baton** | 25 | Electric stun (2s slow) |
| **Combat Knife** | 30 | Silent, 3x backstab |

### Explosives

| Weapon | Damage | Radius | Special |
|--------|--------|--------|---------|
| **Rocket Launcher** | 120 | 12 | Single shot |
| **Grenade Launcher** | 75 | 8 | 6-round magazine |

### Throwables

| Item | Damage | Effect |
|------|--------|--------|
| **Frag Grenade** | 100 | Explosion after 3s |
| **Smoke Grenade** | 0 | Vision block 10s |
| **Molotov** | 15/s | Fire area 8s |
| **Flashbang** | 0 | Blind + deaf 4s |
| **C4** | 150 | Remote detonation |

### Traps

| Trap | Damage | Effect |
|------|--------|--------|
| **Bear Trap** | 50 | Immobilize 3s |
| **Tripwire** | 30 | Alert owner |
| **Tranq Trap** | 10 | Sleep (5s players, 10s dinos) |
| **Spike Trap** | 40 | + Bleed damage |

### Attachments

Players can find and equip attachments to improve weapons:

| Slot | Options | Effect |
|------|---------|--------|
| **Scope** | Red Dot, 2x, 4x, 8x, Thermal | Zoom, ADS speed |
| **Grip** | Vertical, Angled, Stabilizer | Recoil, stability |
| **Magazine** | Extended, Quickdraw | Mag size, reload speed |
| **Muzzle** | Suppressor, Compensator | Sound, recoil |

### Rarity System

All weapons come in 5 rarities with stat multipliers:

| Rarity | Color | Stat Multiplier |
|--------|-------|-----------------|
| Common | Gray | 1.0x |
| Uncommon | Green | 1.1x |
| Rare | Blue | 1.2x |
| Epic | Purple | 1.35x |
| Legendary | Orange | 1.5x |

---

## Storm/Zone System

### Zone Mechanics

- Circular safe zone shrinks over 5 phases
- Players outside zone take increasing damage
- Zone center shifts each phase for unpredictability

### Phase Breakdown

| Phase | Delay | Shrink Time | End Radius | Damage/tick |
|-------|-------|-------------|------------|-------------|
| 1 | 30s | 20s | 200 | 1 |
| 2 | 20s | 15s | 120 | 2 |
| 3 | 15s | 12s | 60 | 4 |
| 4 | 10s | 10s | 25 | 8 |
| 5 | 5s | 8s | 0 | 16 |

---

## Player Systems

### Health & Shield
- **Max Health:** 100
- **Max Shield:** 100
- Shield absorbs damage first

### Healing Items

| Item | Heal Amount | Use Time |
|------|-------------|----------|
| Bandage | 15 HP | 2s |
| Medkit | 50 HP | 5s |
| Health Kit | 100 HP | 7s |
| Mini Shield | 25 Shield | 2s |
| Shield Potion | 50 Shield | 4s |
| Big Shield | 100 Shield | 6s |

### Inventory
- 5 weapon/item slots
- Unlimited ammo storage
- Stack sizes vary by item type

### Movement
- Walk: 16 speed
- Sprint: 24 speed
- Crouch: 8 speed
- Swim: 12 speed

---

## Loot Distribution

### Loot Sources
1. **Floor Loot** - Random spawns throughout map
2. **Chests** - Guaranteed multiple items
3. **Supply Drops** - Rare, high-quality loot
4. **Dinosaur Drops** - Kill dinos for materials
5. **Boss Drops** - Guaranteed legendary items

### Loot Tiers by Location

| Location Type | Common | Uncommon | Rare | Epic | Legendary |
|---------------|--------|----------|------|------|-----------|
| Floor Loot | 50% | 30% | 15% | 4% | 1% |
| Chests | 30% | 35% | 25% | 8% | 2% |
| Supply Drop | 0% | 10% | 30% | 40% | 20% |
| Boss Drop | 0% | 0% | 20% | 50% | 30% |

---

## Audio Design

### Music
- **Lobby** - Atmospheric, anticipation
- **Drop Phase** - Energetic, action
- **Combat** - Intense, driving
- **Boss Fight** - Epic, orchestral
- **Victory** - Triumphant

### Sound Effects
- Distinct weapon sounds by type
- Dinosaur calls and roars
- Environmental ambience per biome
- Storm crackling and warnings

---

## UI/UX

### HUD Elements
- Health/Shield bars
- Ammo counter
- Minimap with zone indicator
- Compass
- Kill feed
- Player/team count
- Storm timer/distance

### Menus
- Main menu (Play, Settings, Exit)
- Mode selection
- Inventory during match
- Victory/Defeat screen
- Spectator UI

---

## Technical Architecture

### Services
- **GameService** - Match state machine
- **WeaponService** - Weapon mechanics and damage
- **DinoService** - AI spawning and behavior
- **MapService** - Biomes, POIs, events
- **StormService** - Zone management
- **LootSystem** - Item spawning
- **SquadSystem** - Team management

### Networking
- Server-authoritative gameplay
- Remote events for client-server communication
- Anti-cheat through server validation

---

## Balance Philosophy

### Player vs Player
- Time-to-kill: 1-3 seconds with good aim
- Skill expression through movement and accuracy
- Multiple viable weapon loadouts

### Player vs Environment
- Dinosaurs are dangerous but manageable
- Environmental awareness rewarded
- High-risk areas offer better rewards

### Pacing
- Early game: Looting focus, few encounters
- Mid game: Rotations, dinosaur encounters
- Late game: Intense PvP with zone pressure

---

## Future Considerations

### Potential Features
- Ranked matchmaking
- Battle pass/seasonal content
- Additional dinosaur types
- New weapons and items
- Custom game modes
- Spectator improvements

### Monetization (if applicable)
- Cosmetic skins only
- No pay-to-win elements
- Battle pass for additional content
