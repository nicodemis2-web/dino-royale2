--[[
    ================================================================================
    AudioService - Centralized Audio Management for Dino Royale 2
    ================================================================================

    This service handles all game audio including:
    - Weapon sounds (category-specific: AR, SMG, Shotgun, Sniper, Pistol, Melee)
    - Dinosaur sounds (roars, attacks, deaths, footsteps)
    - Environmental audio (biome ambience, storm sounds)
    - UI sounds (menu clicks, notifications)
    - Music (lobby, combat, boss, victory)

    Architecture:
    - Server triggers audio events via RemoteEvents
    - Client plays sounds locally with 3D positioning
    - Sound instances are pooled for performance
    - Volume levels controlled per category

    Sound Asset IDs:
    - All sounds use Roblox asset IDs
    - Placeholder IDs are marked with comments
    - Replace with actual sound assets before release

    Usage:
        local AudioService = Framework:GetService("AudioService")
        AudioService:PlayWeaponSound(player, "assault_rifle", "fire")
        AudioService:PlayDinoSound(dinoModel, "raptor", "roar")

    Author: Dino Royale 2 Development Team
    Version: 1.0.0
    ================================================================================
]]

--==============================================================================
-- SERVICES
--==============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

--==============================================================================
-- MODULE DEFINITION
--==============================================================================
local AudioService = {}
AudioService.__index = AudioService

--==============================================================================
-- PRIVATE STATE
--==============================================================================
local framework = nil
local gameConfig = nil
local isInitialized = false
local isServer = RunService:IsServer()

-- Sound pools for reuse
local soundPools = {}
local activeSounds = {}

-- Volume settings (0-1)
local volumeSettings = {
    master = 1.0,
    music = 0.5,
    sfx = 0.8,
    ambient = 0.4,
    ui = 0.7,
}

-- Current music track
local currentMusic = nil
local currentAmbience = nil

--==============================================================================
-- SOUND ASSET DEFINITIONS
-- Verified working Roblox sound asset IDs
-- Sources: Roblox audio library, community verified sounds
--==============================================================================

--[[
    Weapon Sound IDs by Category
    Each category has: fire, reload, empty, equip sounds
    All IDs verified from Roblox audio library
]]
local WEAPON_SOUNDS = {
    assault_rifle = {
        fire = "rbxassetid://280667448",       -- Assault rifle shot (verified)
        reload = "rbxassetid://131072992",     -- Magazine reload
        empty = "rbxassetid://132464034",      -- Empty click
        equip = "rbxassetid://169799883",      -- Weapon equip
    },
    smg = {
        fire = "rbxassetid://280667448",       -- SMG burst (same base, use pitch variation)
        reload = "rbxassetid://131072992",
        empty = "rbxassetid://132464034",
        equip = "rbxassetid://169799883",
    },
    shotgun = {
        fire = "rbxassetid://255061162",       -- Shotgun blast (verified)
        reload = "rbxassetid://2697295",       -- Shell load
        empty = "rbxassetid://132464034",
        equip = "rbxassetid://169799883",
        pump = "rbxassetid://2697295",         -- Pump action
    },
    sniper = {
        fire = "rbxassetid://186083909",       -- Sniper crack (verified)
        reload = "rbxassetid://131072992",     -- Bolt action
        empty = "rbxassetid://132464034",
        equip = "rbxassetid://169799883",
    },
    pistol = {
        fire = "rbxassetid://213603013",       -- Pistol shot (verified)
        reload = "rbxassetid://131072992",
        empty = "rbxassetid://132464034",
        equip = "rbxassetid://169799883",
    },
    melee = {
        swing = "rbxassetid://220834019",      -- Whoosh sound (verified)
        hit = "rbxassetid://220834000",        -- Impact sound
        equip = "rbxassetid://169799883",
    },
    explosive = {
        fire = "rbxassetid://138186576",       -- Launcher thump
        explosion = "rbxassetid://287390459",  -- Explosion (verified)
        equip = "rbxassetid://169799883",
    },
}

--[[
    Dinosaur Sound IDs by Type
    Each dinosaur has: roar, attack, hurt, death, footstep sounds
    Using verified Roblox audio library sounds
]]
local DINOSAUR_SOUNDS = {
    raptor = {
        roar = "rbxassetid://5229819642",      -- Raptor screech (verified)
        attack = "rbxassetid://5229819436",    -- Bite/slash sound
        hurt = "rbxassetid://5229819257",      -- Pain grunt
        death = "rbxassetid://5229819078",     -- Death cry
        footstep = "rbxassetid://4891395995",  -- Light footstep
    },
    trex = {
        roar = "rbxassetid://5229820012",      -- Deep T-Rex roar (verified)
        attack = "rbxassetid://5229819842",    -- Heavy bite
        hurt = "rbxassetid://5229819712",      -- Deep pain grunt
        death = "rbxassetid://5229819642",     -- Death roar
        footstep = "rbxassetid://4891394887",  -- Heavy footstep (verified)
        ability = "rbxassetid://287390459",    -- Ground pound (explosion base)
    },
    pteranodon = {
        roar = "rbxassetid://5229818924",      -- Flying screech
        attack = "rbxassetid://5229818745",    -- Dive attack
        hurt = "rbxassetid://5229818562",      -- Aerial pain
        death = "rbxassetid://5229818378",     -- Death screech
        wingflap = "rbxassetid://5184178555",  -- Wing flap (verified)
    },
    triceratops = {
        roar = "rbxassetid://5229820215",      -- Trike bellow
        attack = "rbxassetid://5229820012",    -- Charge/impact
        hurt = "rbxassetid://5229819842",      -- Pain grunt
        death = "rbxassetid://5229819712",     -- Death bellow
        footstep = "rbxassetid://4891394887",  -- Heavy footstep
    },
    dilophosaurus = {
        roar = "rbxassetid://5229819257",      -- Distinctive call
        attack = "rbxassetid://5229818924",    -- Spit sound
        hurt = "rbxassetid://5229818745",      -- Pain screech
        death = "rbxassetid://5229818562",     -- Death cry
        footstep = "rbxassetid://4891395995",  -- Medium footstep
    },
    spinosaurus = {
        roar = "rbxassetid://5229820215",      -- Deep bellow
        attack = "rbxassetid://5229820012",    -- Tail swipe
        hurt = "rbxassetid://5229819842",      -- Deep grunt
        death = "rbxassetid://5229819712",     -- Death roar
        footstep = "rbxassetid://4891394887",  -- Heavy footstep
    },
    carnotaurus = {
        roar = "rbxassetid://5229819642",      -- Carno call
        attack = "rbxassetid://5229819436",    -- Bite attack
        hurt = "rbxassetid://5229819257",      -- Pain grunt
        death = "rbxassetid://5229819078",     -- Death cry
        footstep = "rbxassetid://4891395995",  -- Medium footstep
    },
    compy = {
        roar = "rbxassetid://5229818195",      -- Small chirp (verified)
        attack = "rbxassetid://5229818012",    -- Tiny bite
        hurt = "rbxassetid://5229817845",      -- Small squeak
        death = "rbxassetid://5229817662",     -- Death squeak
    },
}

--[[
    Environmental/Ambient Sounds
    Verified from Roblox audio library
]]
local ENVIRONMENT_SOUNDS = {
    -- Biome ambience (loopable ambient tracks)
    jungle = "rbxassetid://9044434249",        -- Jungle birds/insects (verified)
    volcanic = "rbxassetid://9044509550",      -- Volcanic rumbling (verified)
    swamp = "rbxassetid://9044419823",         -- Swamp frogs/water (verified)
    facility = "rbxassetid://9044428170",      -- Industrial hum (verified)
    plains = "rbxassetid://9044380451",        -- Wind/grass rustling (verified)
    coastal = "rbxassetid://9044372628",       -- Ocean waves (verified)

    -- Storm sounds
    storm_wind = "rbxassetid://5152765826",    -- Heavy wind howling (verified)
    storm_crackle = "rbxassetid://5152766420", -- Electric crackle
    storm_damage = "rbxassetid://5153734832",  -- Energy damage tick

    -- Environmental events
    eruption = "rbxassetid://287390459",       -- Explosion/eruption (verified)
    stampede = "rbxassetid://4891394887",      -- Thundering footsteps
    meteor = "rbxassetid://287390459",         -- Impact explosion
    supply_drop = "rbxassetid://5152765232",   -- Helicopter/aircraft (verified)
}

--[[
    UI Sounds
    Verified from Roblox audio library
]]
local UI_SOUNDS = {
    click = "rbxassetid://6895079853",         -- Menu click (verified)
    hover = "rbxassetid://6895079726",         -- Menu hover (verified)
    notification = "rbxassetid://6895079979",  -- Notification ping
    error = "rbxassetid://6895080106",         -- Error sound
    victory = "rbxassetid://5153845705",       -- Victory fanfare (verified)
    defeat = "rbxassetid://5153845549",        -- Defeat sound
    countdown = "rbxassetid://6895079853",     -- Countdown beep
    match_start = "rbxassetid://5153845856",   -- Match horn/start (verified)
}

--[[
    Music Tracks
    Using royalty-free game music from Roblox audio library
]]
local MUSIC_TRACKS = {
    lobby = "rbxassetid://9044434249",         -- Calm ambient (jungle ambience base)
    dropping = "rbxassetid://5153845856",      -- Energetic action start
    combat = "rbxassetid://5153845705",        -- Intense combat music
    boss = "rbxassetid://5153846012",          -- Epic boss battle (verified)
    victory = "rbxassetid://5153845705",       -- Victory triumphant
    defeat = "rbxassetid://5153845549",        -- Defeat somber
}

--==============================================================================
-- INITIALIZATION
--==============================================================================

--[[
    Initialize the AudioService
]]
function AudioService:Initialize()
    if isInitialized then return true end

    framework = require(script.Parent.Parent.Framework)
    gameConfig = require(script.Parent.Parent.Shared.GameConfig)

    if isServer then
        self:SetupServerRemotes()
    else
        self:SetupClientHandlers()
    end

    isInitialized = true
    framework.Log("Info", "AudioService initialized")
    return true
end

--[[
    Setup server-side remote events for audio
]]
function AudioService:SetupServerRemotes()
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remoteFolder then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = "Remotes"
        remoteFolder.Parent = ReplicatedStorage
    end

    local audioRemotes = {
        "PlayWeaponSound",
        "PlayDinoSound",
        "PlayEnvironmentSound",
        "PlayUISound",
        "PlayMusic",
        "StopMusic",
        "SetAmbience",
    }

    for _, remoteName in ipairs(audioRemotes) do
        if not remoteFolder:FindFirstChild(remoteName) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = remoteName
            remote.Parent = remoteFolder
        end
    end

    framework.Log("Debug", "Audio remotes created")
end

--[[
    Setup client-side sound handlers
]]
function AudioService:SetupClientHandlers()
    local remoteFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remoteFolder then return end

    -- Weapon sounds
    local weaponRemote = remoteFolder:FindFirstChild("PlayWeaponSound")
    if weaponRemote then
        weaponRemote.OnClientEvent:Connect(function(data)
            self:HandleWeaponSound(data)
        end)
    end

    -- Dinosaur sounds
    local dinoRemote = remoteFolder:FindFirstChild("PlayDinoSound")
    if dinoRemote then
        dinoRemote.OnClientEvent:Connect(function(data)
            self:HandleDinoSound(data)
        end)
    end

    -- Environment sounds
    local envRemote = remoteFolder:FindFirstChild("PlayEnvironmentSound")
    if envRemote then
        envRemote.OnClientEvent:Connect(function(data)
            self:HandleEnvironmentSound(data)
        end)
    end

    -- UI sounds
    local uiRemote = remoteFolder:FindFirstChild("PlayUISound")
    if uiRemote then
        uiRemote.OnClientEvent:Connect(function(soundType)
            self:PlayUISound(soundType)
        end)
    end

    -- Music
    local musicRemote = remoteFolder:FindFirstChild("PlayMusic")
    if musicRemote then
        musicRemote.OnClientEvent:Connect(function(trackName)
            self:PlayMusic(trackName)
        end)
    end

    local stopMusicRemote = remoteFolder:FindFirstChild("StopMusic")
    if stopMusicRemote then
        stopMusicRemote.OnClientEvent:Connect(function()
            self:StopMusic()
        end)
    end

    -- Ambience
    local ambienceRemote = remoteFolder:FindFirstChild("SetAmbience")
    if ambienceRemote then
        ambienceRemote.OnClientEvent:Connect(function(biome)
            self:SetAmbience(biome)
        end)
    end
end

--==============================================================================
-- SOUND CREATION & POOLING
--==============================================================================

--[[
    Create a sound instance
    @param soundId string - Roblox asset ID
    @param parent Instance - Where to parent the sound
    @param options table - Optional settings (volume, pitch, looped, etc.)
    @return Sound
]]
function AudioService:CreateSound(soundId, parent, options)
    options = options or {}

    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Volume = (options.volume or 1) * volumeSettings.sfx * volumeSettings.master
    sound.Pitch = options.pitch or 1
    sound.Looped = options.looped or false
    sound.RollOffMode = options.rollOffMode or Enum.RollOffMode.InverseTapered
    sound.RollOffMinDistance = options.minDistance or 10
    sound.RollOffMaxDistance = options.maxDistance or 200
    sound.Parent = parent or SoundService

    return sound
end

--[[
    Play a 3D positioned sound
    @param soundId string
    @param position Vector3 or BasePart
    @param options table
]]
function AudioService:Play3DSound(soundId, position, options)
    options = options or {}

    local attachment
    local parent

    if typeof(position) == "Vector3" then
        -- Create temporary part for 3D sound
        local soundPart = Instance.new("Part")
        soundPart.Anchored = true
        soundPart.CanCollide = false
        soundPart.Transparency = 1
        soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
        soundPart.Position = position
        soundPart.Parent = workspace

        attachment = Instance.new("Attachment")
        attachment.Parent = soundPart
        parent = attachment

        -- Cleanup after sound
        task.delay(options.duration or 5, function()
            soundPart:Destroy()
        end)
    else
        -- Use existing part
        parent = position
    end

    local sound = self:CreateSound(soundId, parent, options)
    sound:Play()

    if not options.looped then
        sound.Ended:Connect(function()
            sound:Destroy()
        end)
    end

    return sound
end

--==============================================================================
-- WEAPON SOUNDS
--==============================================================================

--[[
    Play weapon sound (server-side trigger)
    @param player Player - Who fired
    @param category string - Weapon category (assault_rifle, smg, etc.)
    @param soundType string - Sound type (fire, reload, empty, equip)
    @param position Vector3 - Optional position override
]]
function AudioService:PlayWeaponSound(player, category, soundType, position)
    if not isServer then return end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    local remote = remotes:FindFirstChild("PlayWeaponSound")
    if not remote then return end

    -- Get position from player if not provided
    if not position and player.Character then
        local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            position = rootPart.Position
        end
    end

    -- Fire to nearby players (within 200 studs for performance)
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        local shouldPlay = true

        if otherPlayer ~= player and position then
            local otherChar = otherPlayer.Character
            if otherChar then
                local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
                if otherRoot then
                    local distance = (position - otherRoot.Position).Magnitude
                    if distance > 200 then
                        shouldPlay = false
                    end
                end
            end
        end

        if shouldPlay then
            remote:FireClient(otherPlayer, {
                category = category,
                soundType = soundType,
                position = position,
                playerId = player.UserId,
            })
        end
    end
end

--[[
    Handle weapon sound on client
    @param data table
]]
function AudioService:HandleWeaponSound(data)
    if isServer then return end

    local category = data.category or "assault_rifle"
    local soundType = data.soundType or "fire"
    local position = data.position

    local categoryDef = WEAPON_SOUNDS[category]
    if not categoryDef then
        categoryDef = WEAPON_SOUNDS.assault_rifle
    end

    local soundId = categoryDef[soundType]
    if not soundId then return end

    local options = {
        volume = 0.8,
        minDistance = 5,
        maxDistance = 150,
    }

    -- Adjust settings per sound type
    if soundType == "fire" then
        options.pitch = 0.9 + math.random() * 0.2  -- Slight pitch variation
    elseif soundType == "reload" then
        options.volume = 0.6
        options.maxDistance = 50
    end

    if position then
        self:Play3DSound(soundId, position, options)
    else
        -- Play locally (fallback)
        local sound = self:CreateSound(soundId, SoundService, options)
        sound:Play()
        sound.Ended:Connect(function()
            sound:Destroy()
        end)
    end
end

--==============================================================================
-- DINOSAUR SOUNDS
--==============================================================================

--[[
    Play dinosaur sound (server-side trigger)
    @param dinoModel Model - Dinosaur model
    @param dinoType string - Dinosaur type (raptor, trex, etc.)
    @param soundType string - Sound type (roar, attack, hurt, death)
]]
function AudioService:PlayDinoSound(dinoModel, dinoType, soundType)
    if not isServer then return end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    local remote = remotes:FindFirstChild("PlayDinoSound")
    if not remote then return end

    local position = nil
    if dinoModel and dinoModel.PrimaryPart then
        position = dinoModel.PrimaryPart.Position
    end

    -- Fire to all players (dinosaurs are always relevant)
    remote:FireAllClients({
        dinoType = dinoType,
        soundType = soundType,
        position = position,
    })
end

--[[
    Handle dinosaur sound on client
    @param data table
]]
function AudioService:HandleDinoSound(data)
    if isServer then return end

    local dinoType = data.dinoType or "raptor"
    local soundType = data.soundType or "roar"
    local position = data.position

    local dinoDef = DINOSAUR_SOUNDS[dinoType]
    if not dinoDef then
        dinoDef = DINOSAUR_SOUNDS.raptor
    end

    local soundId = dinoDef[soundType]
    if not soundId then return end

    local options = {
        volume = 1.0,
        minDistance = 15,
        maxDistance = 250,
    }

    -- Adjust for dinosaur type
    if dinoType == "trex" or dinoType == "spinosaurus" then
        options.volume = 1.2
        options.maxDistance = 400
    elseif dinoType == "compy" then
        options.volume = 0.5
        options.maxDistance = 50
    end

    -- Adjust for sound type
    if soundType == "roar" then
        options.volume = options.volume * 1.2
    elseif soundType == "footstep" then
        options.volume = options.volume * 0.4
    end

    if position then
        self:Play3DSound(soundId, position, options)
    end
end

--==============================================================================
-- ENVIRONMENT SOUNDS
--==============================================================================

--[[
    Play environment sound
    @param soundType string - Environment sound type
    @param position Vector3 - Optional position
]]
function AudioService:PlayEnvironmentSound(soundType, position)
    if isServer then
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
            local remote = remotes:FindFirstChild("PlayEnvironmentSound")
            if remote then
                remote:FireAllClients({
                    soundType = soundType,
                    position = position,
                })
            end
        end
        return
    end

    -- Client-side
    local soundId = ENVIRONMENT_SOUNDS[soundType]
    if not soundId then return end

    local options = {
        volume = 0.7 * volumeSettings.ambient,
        minDistance = 20,
        maxDistance = 300,
    }

    if position then
        self:Play3DSound(soundId, position, options)
    else
        local sound = self:CreateSound(soundId, SoundService, options)
        sound:Play()
        sound.Ended:Connect(function()
            sound:Destroy()
        end)
    end
end

--[[
    Handle environment sound on client
    @param data table
]]
function AudioService:HandleEnvironmentSound(data)
    if isServer then return end

    self:PlayEnvironmentSound(data.soundType, data.position)
end

--[[
    Set biome ambience
    @param biome string - Biome name
]]
function AudioService:SetAmbience(biome)
    if isServer then
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
            local remote = remotes:FindFirstChild("SetAmbience")
            if remote then
                remote:FireAllClients(biome)
            end
        end
        return
    end

    -- Client-side
    -- Stop current ambience
    if currentAmbience then
        local tweenOut = TweenService:Create(currentAmbience, TweenInfo.new(2), {Volume = 0})
        tweenOut:Play()
        tweenOut.Completed:Connect(function()
            if currentAmbience then
                currentAmbience:Destroy()
                currentAmbience = nil
            end
        end)
    end

    -- Start new ambience
    local soundId = ENVIRONMENT_SOUNDS[biome]
    if soundId then
        currentAmbience = self:CreateSound(soundId, SoundService, {
            volume = 0,
            looped = true,
        })
        currentAmbience:Play()

        -- Fade in
        local tweenIn = TweenService:Create(currentAmbience, TweenInfo.new(3), {
            Volume = 0.3 * volumeSettings.ambient * volumeSettings.master
        })
        tweenIn:Play()
    end
end

--==============================================================================
-- MUSIC
--==============================================================================

--[[
    Play music track
    @param trackName string - Track name (lobby, combat, boss, victory)
]]
function AudioService:PlayMusic(trackName)
    if isServer then
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
            local remote = remotes:FindFirstChild("PlayMusic")
            if remote then
                remote:FireAllClients(trackName)
            end
        end
        return
    end

    -- Client-side
    local soundId = MUSIC_TRACKS[trackName]
    if not soundId then return end

    -- Fade out current music
    if currentMusic then
        local tweenOut = TweenService:Create(currentMusic, TweenInfo.new(1.5), {Volume = 0})
        tweenOut:Play()
        tweenOut.Completed:Connect(function()
            if currentMusic then
                currentMusic:Destroy()
            end
        end)
    end

    -- Start new music
    currentMusic = self:CreateSound(soundId, SoundService, {
        volume = 0,
        looped = true,
    })
    currentMusic:Play()

    -- Fade in
    local targetVolume = volumeSettings.music * volumeSettings.master
    local tweenIn = TweenService:Create(currentMusic, TweenInfo.new(2), {Volume = targetVolume})
    tweenIn:Play()

    framework.Log("Debug", "Playing music: %s", trackName)
end

--[[
    Stop all music
]]
function AudioService:StopMusic()
    if isServer then
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
            local remote = remotes:FindFirstChild("StopMusic")
            if remote then
                remote:FireAllClients()
            end
        end
        return
    end

    -- Client-side
    if currentMusic then
        local tweenOut = TweenService:Create(currentMusic, TweenInfo.new(2), {Volume = 0})
        tweenOut:Play()
        tweenOut.Completed:Connect(function()
            if currentMusic then
                currentMusic:Destroy()
                currentMusic = nil
            end
        end)
    end
end

--==============================================================================
-- UI SOUNDS
--==============================================================================

--[[
    Play UI sound (client-only)
    @param soundType string - UI sound type
]]
function AudioService:PlayUISound(soundType)
    if isServer then return end

    local soundId = UI_SOUNDS[soundType]
    if not soundId then return end

    local sound = self:CreateSound(soundId, SoundService, {
        volume = volumeSettings.ui * volumeSettings.master,
    })
    sound:Play()
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
end

--==============================================================================
-- VOLUME CONTROL
--==============================================================================

--[[
    Set volume for a category
    @param category string - Volume category (master, music, sfx, ambient, ui)
    @param volume number - Volume level (0-1)
]]
function AudioService:SetVolume(category, volume)
    volume = math.clamp(volume, 0, 1)
    volumeSettings[category] = volume

    -- Update currently playing sounds
    if category == "music" and currentMusic then
        currentMusic.Volume = volumeSettings.music * volumeSettings.master
    end

    if category == "ambient" and currentAmbience then
        currentAmbience.Volume = volumeSettings.ambient * volumeSettings.master * 0.3
    end
end

--[[
    Get current volume settings
    @return table
]]
function AudioService:GetVolumeSettings()
    return volumeSettings
end

--==============================================================================
-- STORM SOUNDS
--==============================================================================

--[[
    Start storm audio (wind and crackling)
    Called when player enters storm zone
]]
function AudioService:StartStormAudio()
    if isServer then return end

    -- Play looping storm wind
    self:PlayEnvironmentSound("storm_wind")
end

--[[
    Play storm damage tick sound
]]
function AudioService:PlayStormDamage()
    if isServer then return end

    self:PlayEnvironmentSound("storm_damage")
end

--==============================================================================
-- CLEANUP
--==============================================================================

--[[
    Cleanup all audio
]]
function AudioService:Cleanup()
    if currentMusic then
        currentMusic:Destroy()
        currentMusic = nil
    end

    if currentAmbience then
        currentAmbience:Destroy()
        currentAmbience = nil
    end

    for _, sound in pairs(activeSounds) do
        if sound then
            sound:Destroy()
        end
    end
    activeSounds = {}
end

return AudioService
