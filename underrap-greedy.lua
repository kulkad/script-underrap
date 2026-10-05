do
    local realWarn = warn
    local realPrint = print
    local blocked = {
        "API HTTP error",
        "Semua server udah dikunjungi",
        "Mencari server lagi",
        "Tidak menemukan server baru",
        "Rate-limited",
    }

    local function shouldBlock(msg)
        local m = tostring(msg or "")
        for idx = 1, #blocked do
            if string.find(m, blocked[idx], 1, true) then
                return true
            end
        end
        return false
    end

    warn = function(...)
        if shouldBlock(select(1, ...)) then return end
        realWarn(...)
    end

    print = function(...)
        if shouldBlock(select(1, ...)) then return end
        realPrint(...)
    end
end
print("[Silent Filter] Aktif")

--// Blade Ball Trade Plaza - Underrap Scanner
--// Revised:
--// 1. Emote name menggunakan ReplicatedStorage.Misc.Emotes -> Attribute "EmoteName"
--// 2. Sword image menggunakan ReplicatedInstances:GetInstance("Swords", itemKey)
--// 3. TextureID dari MeshPart/SpecialMesh dipakai sebagai thumbnail Discord
--// 4. Semua webhook dikirim SELESAI terlebih dahulu
--// 5. Setelah webhook selesai, scanner baru server hop
--// 6. Server hop memakai Roblox Public Server API
--// 7. Menangani TeleportInitFailed
--// + AUTO-BUY & SALES CHART (ditambahkan)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Anti-idle supaya gak kena kick AFK
task.spawn(function()
    while task.wait(15) do
        pcall(function()
            local char = LocalPlayer.Character
            if char and char:FindFirstChildOfClass("Humanoid") then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    LocalPlayer:Move(Vector3.new(0, 0, 0), true) -- reset input
                    task.wait(0.1)
                    LocalPlayer:Move(Vector3.new(0, 0, 0), false)
                end
            end
        end)
    end
end)

--==================================================
-- CONFIG
--==================================================

local UNDERRAP_THRESHOLDS = {
    LOW = 10,
    MID = 3,
    HIGH = 3,
    ["100K+"] = 3,
}

local DEEP_UNDERRAP_PERCENT = 50
-- Rule tambahan untuk sword RAP kecil
local LOW_RAP_THRESHOLD = 750        -- RAP < 700
local LOW_RAP_MIN_DIFF = 70          -- selisih minimal 60 RAP (ubah ke 70 kalau mau)

local DEBUG = false
local DUMP_RAW_DATA = false

local SAFE_MODE = true
local SAFE_SCAN_COOLDOWN_SECONDS = 2
local SAFE_HOP_COOLDOWN_SECONDS = 3
local SAFE_MAX_WEBHOOKS_PER_SCAN = 50
local SAFE_SERVER_HOP_RETRY_LIMIT = 1

local WEBHOOK_DELAY_SECONDS = 0.3
local BOOTH_LOAD_DELAY_SECONDS = 0.2
local BOOTH_LOAD_TIMEOUT_SECONDS = 20

local SERVER_HOP_DELAY_SECONDS = 1
local SERVER_HOP_FAILURE_RETRY_DELAY_SECONDS = 1
local SERVER_HOP_COOLDOWN_SECONDS = SAFE_HOP_COOLDOWN_SECONDS
local ENABLE_SERVER_HOP = true
local MIN_PREFERRED_PLAYERS = 10
local MAX_PREFERRED_PLAYERS = 25
local MIN_FALLBACK_PLAYERS = 5
local SERVER_API_MAX_PAGES = 3
local SERVER_HOP_CYCLE = 15
local PREFERRED_HOP_COUNT = 14
local TELEPORT_SETTING_KEY = "ApayaServerHopCount"

local lastServerHopAt = 0
local lastScanAt = 0
local scanInProgress = false
local hopInProgress = false
local hopAttemptCount = 0
local blockedServerIds = {}
local lastTeleportTargetId = nil
local preparedServerId = nil
-- forward declaration biar bisa dipanggil sebelum di-assign
local serverHop

--==================================================
-- AUTO-BUY CONFIG (TAMBAHAN)
--==================================================

local AUTO_BUY_ENABLED = true   -- matikan kalau gak mau auto-buy

local AUTO_BUY_LIST = {
    ["Pulseheart Set"] = 3900,
    ["Cosmic Wrath"] = 37000,
    ["Lily Katana"] = 4200,
    ["Snowball Launcher"] = 3200,
    ["Floppy Chicken"] = 3200,
    ["Sitting"] = 2400,
    ["Shackled Celestial"] = 500,
    ["Moonflower Greatsword"] = 3200,
    ["Strawberry Cake Blade"] = 290,
    ["Star Wand"] = 2900,
    ["Queen Blade"] = 27500,
    ["Meowstruck"] = 1400,
    ["Red Moon Katana"] = 2900,
    ["Gravelight"] = 4500,
    ["Hellfire King"] = 3200,
    ["Hollow Oath Katana"] = 3200,
    ["Black Oni Katana"] = 3200,
    ["Eternal Scythe"] = 2400,
    ["Enchanted Bluerose"] = 2100,
    ["Sunset Pastelblade"] = 2000,
    ["Glacialis Requiem"] = 1400,
    ["Crystal Blade"] = 1500,
    ["Black Ninja Star"] = 1700,
    ["Riftspike Reaper"] = 1500,
    ["Oceanic Reaper"] = 1500,
    ["All-Star Striker"] = 1100,
    ["Skeleton Bride"] = 6400,
    ["Black Cat Scythe"] = 900,
    ["Y2K Blade"] = 400,
    ["Wolf Greatsword"] = 14000,
    ["North Blade"] = 1400,
    ["Dual Chroma set"] = 11200,
    ["Chroma Scythe"] = 7500,
    ["The Curse"] = 3900,
    ["Dual Yinyang Greatsword"] = 4500,
    ["Prismatic Odachi"] = 3100,
    ["Shark"] = 3000,
    ["Aetherion"] = 1900,
    ["Crimson Backblade"] = 2100,
    ["Thorned Sovereign"] = 2100,
    ["Water Slasher"] = 2100,
    ["Calamity Guardian"] = 2000,
    ["Amethyst Backblade"] = 2000,
    ["Ethereal Bombardment"] = 2400,
    ["Nebula Sniper"] = 1900,
    ["Soulrender Scythe"] = 2400,
    ["Blackhole Sword"] = 1900,
    ["Candycane Sniper"] = 1800,
    ["Draconic Greatsword"] = 1500,
    ["Venomlight Scythe"] = 1800,
    ["Santa Greatsword"] = 1700,
    ["Dual Black Cat Scythe"] = 1500,
    ["Red Ninja Star"] = 1400,
    ["Pink Ninja Star"] = 1400,
    ["Starshooter Rapier"] = 1300,
    ["Blue Oni Katana"] = 2800,
    ["Pink Oni Katana"] = 2800,
    ["Purple Oni Katana"] = 2800,
    ["Dual Wonderwisp Greatsword"] = 3000,
    ["Pearl Angel Katana"] = 3500,
    ["Dual Eternal Greatsword"] = 3100,
    ["Chroma Ninja Star"] = 3300,
    ["Proyection Sorcery Katana"] = 3400,
    ["Hellwing Set"] = 4100,
    ["Halberd"] = 3900,
    ["Gyaru Katana"] = 4300,
    ["Guardian of the underworld"] = 3700,
    ["Devil Greatsword"] = 3900,
    ["Frostbound Latern"] = 4300,
    ["Poisoned Bunny"] = 4600,
    ["Crystal Fairyblade"] = 4700,
    ["Green Ninja Katana"] = 4800,
    ["Red Ninja Katana"] = 5400,
    ["Blue Ninja katana"] = 5500,
    ["Void Blade"] = 1700,
    ["Abyssal Blade"] = 1350,
    ["Cloud"] = 23500,
    ["Crystal Greatblade"] = 1900,
    ["Kitty Katana"] = 14000,
    ["Neo-Neko Katana"] = 500,
    ["Witch's Curse"] = 2800,
    ["Wind Thorn"] = 700,
    ["Jackolantern"] = 17000,
    ["Eternal Piercer"] = 29000,
    ["Valentine Hearts"] = 9000,
    ["Tiger's Katana"] = 12000,
    ["Love For You"] = 14800,
    ["Chroma Blade"] = 14500,
    ["King Blade"] = 12000,
    ["Puppy"] = 16000,
    ["Flaming Sword"] = 3000,
    ["Pillow"] = 2500,
    ["Royal Duality"] = 50000,
    ["Holy Blade"] = 2100,
    ["Higanbana Katana"] = 4100,
    ["Moonflower Katana"] = 18000,
    ["Evil Deal"] = 3000,
    ["Kitty Rocket"] = 9200,
    ["Cat Paw"] = 10000,
    ["Brutality Affection Bat"] = 7400,
    ["Borealis"] = 28000,
    ["Celestial Whisper"] = 25000,
    ["Reindeer"] = 35000,
    ["The Conjurer"] = 1500,
    --["Siam Ember Axe"] = 98000,
    --["Zombie Slide"] = 100000,
    ["Prince Blade"] = 2550,
    ["Slime"] = 7400,
    ["Aligned Constellation"] = 4000,
    ["Dancinha"] = 3000,
    ["Riftflare Katana"] = 2900,
    ["Fox Katana"] = 5200,
    ["Milk & Cookies"] = 3000,
    ["Kraken"] = 7000,
    ["Sakura's Requiem"] = 3800,
    ["Hitman"] = 5100,
    ["Angel Greatsword"] = 3000,
    --["Bunny"] = 120000,
    --["Ranked Season 15 Top 50"] = 31000,
    ["Icebound Dominus"] = 34000,
    ["Regret Blades"] = 19000,
    ["Eternum Galepiercer"] = 9500,
    ["Phantom Chase"] = 110,
    ["Wicked Crow"] = 8700,
    ["Hug"] = 16000,
    ["Black Ninja Katana"] = 8900,
    ["Loving Backblade"] = 9000,
    --["T-Rex"] = 11500,
    ["Jolly Scythe Set"] = 1800,
    ["Kitty Launcher"] = 16500,
    ["Fallen Angel"] = 20000,
    ["Chroma Ninja Katana"] = 24500,
    ["Chroma Seal"] = 31000,
    --["Seraphim"] = 39000,
    ["Montagem Miau"] = 7200,
    ["Legs Kickin'"] = 8300,
    ["Winter Wolf"] = 20000,
    ["Night Raver"] = 8300,
    ["Dual Leviathan Set"] = 3800,
    ["Gothic Bunny Blade"] = 300,
    ["Watching The Stars"] = 3000,
    ["Rabicasada"] = 1700,
    ["Bring it Arround"] = 1700,
    ["Jackpot"] = 3700,
    ["King Throne"] = 2900,
    ["Devil Greatsword Emote"] = 3000,
    ["Popular"] = 1400,
    ["Kitty Launcher Emote"] = 2400,
    ["Crab Rave"] = 2200,
    --["Luna Bala"] = 1900,
    --["Floating Sword"] = 2300,
    ["Orbital [NEBULA YORU]"] = 1500,
    ["Coffin Explosion"] = 7000,
    ["Phantom Ops"] = 2900,
    ["Emperor Blade"] = 900,
    ["Floating Hearts Aura"] = 180,
    ["Menacing"] = 340,
    ["Lumen Petal"] = 300,
    ["Rosarium Blade"] = 380,
    ["Rose Blade"] = 530,
    ["Cursed Obsession"] = 4400,
}

--==================================================
-- SALES HISTORY CONFIG (TAMBAHAN)
--==================================================

local SALES_HISTORY_DAYS = 6
local MIN_SALES_COUNT = 20

-- Syarat auto-buy untuk under-100 dan under-50%
local AUTO_BUY_MIN_DAYS_WITH_SALES = 2          -- minimal berapa hari yang mencapai target
local AUTO_BUY_MIN_DAILY_SALES = 30             -- target penjualan per hari

--==================================================
-- WEBHOOK DELAY CONFIG
--==================================================
local SECOND_WEBHOOK_DELAY = 7  -- detik (recommended 10-15)

--==================================================
-- WEBHOOKS (2 SERVER)
--==================================================
local WEBHOOKS = {
    -- SERVER 1 (kode kirim langsung)
    SERVER1 = {
        LOW = "https://discord.com/api/webhooks/1556249938407464963/zr5Z8SPJY1tFABQKMcbY0vteotNb6mhxjcwsroIHL1dPJp68FWhyyL5mILbZU1j0RLWy",
        MID = "https://discord.com/api/webhooks/1556250029205749860/ScUkJ3cH4IpFMHMgc2ihJ7wGKayC3T47krgcWKz6zWifc8tgJbxAoTrVRiJCCHw1aZm4",
        HIGH = "https://discord.com/api/webhooks/1556250100731224104/Rc91SXAbnTedssiATPaSkiMzW1avSmsRBtg93l_-l-aaAZH5ehlQi17t9WG0fsVooMOg",
        ["100K+"] = "https://discord.com/api/webhooks/1556250154380820551/4OvR-52MskIR7PFc1WxKbgJhQk359klE2iSFVa5xMtR9oDukCW-G5UcRVnibuRdF60_T",
        BOOSTED = "https://discord.com/api/webhooks/1556250203961561088/er_A0xeXlsR3kcZ6yU94w9CkSwd-mQRSqqqjY1elr6ltQBZ2YI47M_NN413PPgjtpj8y",
        NUKE = "https://discord.com/api/webhooks/1556250250014883923/2qUm0VbDB8pWF0XHMZnwYjtKfqj9PlS4GlpglLe8woiAzlnMvf995Q2Wsg6uQ8Olbbld",
        DEEP_UNDERRAP = "https://discord.com/api/webhooks/1556250301286322211/w9z4F5MuyxamX9uHtYDFqhckowf37uhJI0nqiyex-UghxMnN9y48vFzjRW0fV7VzHRo7",
        AUTO_BUY = "https://discord.com/api/webhooks/1556250385511882853/egiraUPm5EvO8GrPVUbgD3hvRRpW7_xPxu2vatqDVgyg8MvDSrQoZvi5n9yLLPXb_8Qf",
    },
    -- SERVER 2 (kode kirim setelah delay)
    SERVER2 = {
        LOW = "https://discord.com/api/webhooks/1551501843773784134/B_TyApwNmK70RXS3_hUtjqjPYwWU2y9ZzogQ5Hhen-mvg0OI0tFqgp6C-vKxv3FwWjjA",
        MID = "https://discord.com/api/webhooks/1551501902498500702/sbF6owgb1-i-cRYUhOajnKjlb-etcTUDBoI_MmrAGzTaLYp2dESb5BZGNRhgWtkErGkD",
        HIGH = "https://discord.com/api/webhooks/1551501956130799716/C5VIlFFjBf01AjnsVtspKfckDPfRO5uqJshw7uQ32YHMkNpb-iHn0L2ygB4WxDYXaWnd",
        ["100K+"] = "https://discord.com/api/webhooks/1551502081050017865/gWokJ-KdVhkBLt0uP3G8_34jaw3-ylCzJ_zQ6OxJnbNqkV_S-IlGz16YegPcLkJ7X48n",
        BOOSTED = "https://discord.com/api/webhooks/1551502193482399764/3ZkOX2PhlrsYFztaGW-U6kjFKrXEybRXBTwPwUqbUzQ1MTPgIW4nYW54AWZkSRD2--Ws",
        NUKE = "https://discord.com/api/webhooks/1551502133738741761/vM_TPC3osHpvVg3wU5QEBCPtYo6LMrAkPdB4g_BTfRyX9Zx1srPih6B3Ew1_vSAUwh-R",
        DEEP_UNDERRAP = "https://discord.com/api/webhooks/1551502008153014272/w8HH1oUVcd5YcChmyFGsIZDmaoYyqILPTviecTniw4YWkrCoFCxBGBtmM7IehwCvEwr4",
        AUTO_BUY = "https://discord.com/api/webhooks/1553920710508945551/O4RirCUjuiBN5bVTyOwGnguwEuBzNmItLd9_sWvGKlymT7USpcRyOQaf5uWclRFxYEJU",
    },
}

-- Alias biar kode lama yang pakai `AUTO_BUY_LIST[itemName]` tetep jalan
-- (gak perlu diubah kalau kamu udah fix dari sebelumnya)

print("[Scanner] ✅ Loaded - Auto Buy " .. (AUTO_BUY_ENABLED and "ON" or "OFF"))

--==================================================
-- MANUAL BOOSTED LIST
--==================================================

local BOOSTED_ITEMS = {
    ["Coconut Failure"] = true,
    ["Sword of Order"] = true,
    ["Chroma Fortune Cleaver"] = true,
    ["Glacial Blade"] = true,
    ["Dual Axolotl Blade"] = true,
    ["Yin Yang Katana"] = true,
    ["Radiant Duckling Explosion"] = true,
    ["Tidewither"] = true,
    Gothic Heartpiercer Bow"] = true,
    ["Zephyr Blade"] = true,
    ["Super Bow"] = true,
    ["Wavelight Greatblade"] = true,
    ["Dual Gothic Heartpiercer Blade"] = true,
    ["Wisteria Blade"] = true,
    ["Runic Scythe"] = true,
    ["Black Ninja Star"] = true,
    ["Shadow Dragger"] = true,
    ["Titanbreaker"] = true,
    ["Block Buster"] = true,
    ["Twilight Bite"] = true,
    ["Thronebreaker"] = true,
    ["Lover's Scythe"] = true,
    ["Why???"] = true,
    ["Twilight Twinkle"] = true,
    ["Quantum Leap"] = true,
    ["Sunkissed Scythe"] = true,
    ["Crystal Scissors"] = true,
    ["Skull King"] = true,
    ["Falling Down"] = true,
    ["Dual Stellar Blade"] = true,
    ["Blackhole Sword"] = true,
    ["Glacial Dominance"] = true,
    ["Sakura Scythe"] = true,
    ["Prismatic Harvester"] = true,
    ["Infinite Blade"] = true,
    ["Witch's Broom"] = true,
    ["Spring Slicer"] = true,
    ["Dual Shadow Kunai"] = true,
    ["Masked Horror Blade"] = true,
    ["Mothyx Blade"] = true,
    ["Radiant Duckling Lance"] = true,
    ["Ghostfish Blade"] = true,
    ["Astral Sword"] = true,
    ["Singularity Scythe"] = true,
    ["Nightclaw Blade"] = true,
    ["Lumina Bow"] = true,
    ["Awakened Subversion"] = true,
    ["Gleaming Katana"] = true,
    ["Cyber Scythe"] = true,
    ["Awakened Megatooth Relic"] = true,
    ["Dual Frog Blasters"] = true,
    ["Primordial Lance"] = true,
    ["Ranked Season 6 Top 50"] = true,
    ["Dawnpiercer"] = true,
    ["Aetherial Azure Reckoner"] = true,
    ["Nightshade Saber"] = true,
    ["Voltfire Blade"] = true,
    ["Starfish Blade"] = true,
    ["Ocean Surfer"] = true,
    ["Knighthood"] = true,
    ["Prismatic Gem Blade"] = true,
    ["Royal Throne"] = true,
    ["Gravebone Scythe"] = true,
    ["Loving Backblade"] = true,
    ["Blackhole Gauntlets"] = true,
    ["Onyx Katana"] = true,
    ["Pastel Spear"] = true,
    ["Solar Saber"] = true,
    ["Remastered Linked Sword"] = true,
    ["Prince Legacy Scythe"] = true,
    ["Prince Legacy Blade"] = true,
    ["Nature Cards"] = true,
    ["Proyection Sorcery Katana"] = true,
    ["Nebula Katana"] = true,
    ["Crystal Ribbon Blade"] = true,
    ["Dual Stellar Revolver"] = true,
    ["FROSTWALL"] = true,
    ["Dual Aetherial Kunai"] = true,
    ["Clans Warrior"] = true,
    ["Lover's Axe"] = true,
    ["Chilling Breath"] = true,
    ["Necrotic Burst"] = true,
    ["Berry Edge"] = true,
    ["Dual Sea Sovereign"] = true,
    ["Love Blade"] = true,
    ["Serpentbane"] = true,
    ["Plasma Gauntlets"] = true,
    ["Crystal Hammer"] = true,
    ["Void Scythe"] = true,
    ["Inferno Lance"] = true,
    ["Inferno Katana"] = true,
    ["Water Slasher"] = true,
    ["Reborn Wings Blade"] = true,
    ["Lumenshell Scythe"] = true,
    ["Frostbite Annihilator"] = true,
    ["Primordial Loop Explosion"] = true,
    ["Dual Primordial Blade"] = true,
    ["Primordial Dust Explosion"] = true,
    ["Dark Lotus Scythe"] = true,
    ["Harmonic Staff"] = true,
    ["Primordial Blade"] = true,
    ["Festive Bow"] = true,
    ["Heart of Winter"] = true,
    ["Dragon Scythe"] = true,
    ["Rosefire Scythe"] = true,
    ["Aurora Spirit"] = true,
    ["Sunknight's Sword"] = true,
    ["Awakened Architect"] = true,
    ["Bloom Katana"] = true,
    ["Golden Crescent Bow"] = true,
    ["Raven Scythe"] = true,
    ["Ranked Season 4 Top 25 Sword"] = true,
    ["Twilight Blade"] = true,
    ["Ranked Season 13 Champion"] = true,
    ["Dual Jolly Fan"] = true,
    ["Empyrean Greatblade"] = true,
    ["Infinite Scythe"] = true,
    ["Elemental Masterblade"] = true,
    ["Kurogin Scythe"] = true,
    ["Heart Blade"] = true,
    ["Serpent's Coreplosion"] = true,
    ["Blizzard Slayer"] = true,
    ["Zeus' Lightning"] = true,
    ["Dual Lucky Fan"] = true,
    ["Neo-Neko Katana"] = true,
    ["Neo-Neko Needle"] = true,
    ["Samurai's Set"] = true,
    ["Wispwind Reaper"] = true,
    ["Hero of Hope Saber"] = true,
    ["Rose Wand"] = true,
    ["Frostblade"] = true,
    ["Emerald Greatsword"] = true,
    ["Hidden Beast Blade"] = true,
    ["Dual Pumpkin Fan"] = true,
    ["Dual Luminara"] = true,
    ["Supernova Beam"] = true,
    ["Headless Horror"] = true,
    ["Venomsanct"] = true,
    ["Blossom Dragon"] = true,
    ["Spooky Sightblade"] = true,
    ["Cyborg Blade"] = true,
    ["Divine Ruin Blade"] = true,
    ["Phoenix's Rise"] = true,
    ["Solaredge Longsword"] = true,
    ["Dual Frost Saber"] = true,
    ["Plasma Blasters"] = true,
    ["Dunestrike Scimitar"] = true,
    ["Aurora Edge"] = true,
    ["Dual Widowbloom Blades"] = true,
    ["Velvet Blade"] = true,
    ["Obsidian Blade"] = true,
    ["Phoenix Rebirth Emote"] = true,
    ["Malice Parasol"] = true,
    ["Ranked Season 5 Top 200"] = true,
    ["Widow's Garden"] = true,
    ["Jade Blade"] = true,
    ["Widowbloom Blade"] = true,
    ["Burnt Relic"] = true,
    ["Empyrean Fortress"] = true,
    ["Clan Ascendancy"] = true,
    ["New Years Slicer"] = true,
    ["Dual Frosted Gleam"] = true,
    ["Ranked Season 20 Champion"] = true,
    ["Dual Sakura Fan"] = true,
    ["Frog"] = true,
    ["Y2K Blade"] = true,
    ["Dual Aurum Etherius"] = true,
    ["Inferno Greatscythe"] = true,
    ["Awakened Winter's Touch"] = true,
    ["Fire Dragon"] = true,
    ["Peachborne Blade"] = true,
    ["Lumina Spear"] = true,
    ["Frozen Doomblade"] = true,
    ["Runic Blade"] = true,
    ["Lunar Bloom"] = true,
    ["Sandstorm Slasher"] = true,
    ["Ranked Season 13 Top 200"] = true,
    ["Princess Katana"] = true,
    ["Festive Blade"] = true,
    ["Floral Slicer"] = true,
    ["Ranked Season 19 Champion"] = true,
    ["Keyblade"] = true,
    ["Curse of the Nile"] = true,
    ["Tropical Thunder"] = true,
    ["Casual Failure"] = true,
    ["Lightning Dagger"] = true,
    ["Dual Devil Katana"] = true,
    ["Blade of Eras"] = true,
    ["Crystal Reaver"] = true,
    ["Galactic Annihilation"] = true,
    ["Widowbloom Bow"] = true,
    ["Masked Horror Scythe"] = true,
    ["Duet of Destruction"] = true,
    ["Chaos Dagger"] = true,
    ["Turkey Slayer"] = true,
    ["Axolotl Scythe"] = true,
    ["Oni Claws"] = true,
    ["Cloud Summon"] = true,
    ["Avis Scythe"] = true,
    ["Mummy's Curse"] = true,
    ["Resolution Blade"] = true,
    ["Off with your Head"] = true,
    ["New Years Greatsword"] = true,
    ["Valkyrien Blade"] = true,
    ["Skeleton Phantom"] = true,
    ["Rose Railgun"] = true,
    ["Rosefire Blade"] = true,
    ["Inferno Sword"] = true,
    ["Tsunami Blade"] = true,
    ["Winter's Wrath"] = true,
    ["Thankful Cheer"] = true,
    ["Ethereal Collapse"] = true,
    ["New Year's Lance Emote"] = true,
    ["Winged Warrior"] = true,
    ["Long-nosed Scythe"] = true,
    ["Lantern Shuffle"] = true,
    ["Sunbeam Flash"] = true,
    ["Ice King Staff"] = true,
    ["Soulreaper's Scythe"] = true,
    ["Drone Flight"] = true,
    ["Butterfly Wingsword"] = true,
    ["Dual Frost Blasters"] = true,
    ["Dual Divine Ruin Blades"] = true,
    ["Dual Summer Fans"] = true,
    ["Frost Monarch Saber"] = true,
    ["Eternal Clockwork"] = true,
    ["Gilded Harvest"] = true,
    ["Frosted Trails"] = true,
    ["Frying Windmill"] = true,
    ["Mythical Enchanter"] = true,
    ["Proposal"] = true,
    ["Skeleton Dance"] = true,
    ["Skeleton Juggle"] = true,
    ["Weeping Angel"] = true,
    ["Wreath Shot"] = true,
    ["Zeus' Revenge"] = true,
    ["2025"] = true,
    ["Eternal Autumn"] = true,
    ["Sunshine Saber"] = true,
    ["Black Oni Katana"] = true,
    ["Evil Cyborg Blade"] = true,
    ["Strawberry Cake Lance"] = true,
    ["Umbra Spear"] = true,
    ["Event Horizon"] = true,
    ["Awakened Venomweaver"] = true,
    ["Fortune Cleaver"] = true,
    ["Blizzard Smash"] = true,
    ["Blue Hexplosion"] = true,
    ["Brazil Explosion"] = true,
    ["Celestial Energy"] = true,
    ["Celestial Dawn Blade"] = true,
    ["Champion's Triumph"] = true,
    ["Divine Ruin Lore"] = true,
    ["Dragon Explosion"] = true,
    ["Dragon Slayer"] = true,
    ["Fate's Fracture"] = true,
    ["France Explosion"] = true,
    ["Frosted Burst"] = true,
    ["Germany Explosion"] = true,
    ["Hex Impact"] = true,
    ["Dual Hacker Scythe"] = true,
    ["Golden Scatter"] = true,
    ["Masked Horror Explosion"] = true,
    ["Kyoi Pond"] = true,
    ["Tropical Splash"] = true,
    ["Waterplosion"] = true,
    ["Aetherwatch Scythe"] = true,
    ["Alienated Backblade"] = true,
    ["Allseeing Seer"] = true,
    ["Allseeing Spear"] = true,
    ["Amethyst Greatsword"] = true,
    ["Ancient Iceblade"] = true,
    ["Angelic Cleaver"] = true,
    ["Astral Axe"] = true,
    ["Astraea Blade"] = true,
    ["Aurora Carver"] = true,
    ["Aurora's Ice Staff"] = true,
    ["Autumn Sovereign"] = true,
    ["Awakened Ashblade"] = true,
    ["Awakened Eclipse Desire"] = true,
    ["Awakened Ethereal Scythe"] = true,
    ["Awakened Kraken's Wraith"] = true,
    ["Azure Thunderbolt"] = true,
    ["Lumenwing Bow"] = true,
    ["Arctic King's Blade"] = true,
    ["Ranked Season 14 Champion"] = true,
    ["Blackhole Scythe"] = true,
    ["Blade of the Damned"] = true,
    ["Blade of the Fallen King"] = true,
    ["Bloodline Blade"] = true,
    ["Blossom Scythe"] = true,
    ["Blossom Blade"] = true,
    ["Bloomlight Greatscythe"] = true,
    ["Blue Bunny Katana"] = true,
    ["Brazil Football"] = true,
    ["Bunny Staff"] = true,
    ["Celestial Spear"] = true,
    ["Celestial Staff"] = true,
    ["Champion's Excalibur"] = true,
    ["Chroma DJ"] = true,
    ["Nebula Scythe"] = true,
    ["Chroma DJ Emote"] = true,
    ["Chrome Dracula Blade"] = true,
    ["Clockwork Blueblade"] = true,
    ["Cloud Sword"] = true,
    ["Coconut Crusher"] = true,
    ["Coral Greatsword"] = true,
    ["Corrupted Bow"] = true,
    ["Corrupted Frostblade"] = true,
    ["Crimson Katana"] = true,
    ["Nightclaw Scythe"] = true,
    ["Crimson Kagune"] = true,
    ["Cyber Cleaveblade"] = true,
    ["Cyber King's Sword"] = true,
    ["Cyber Slasher"] = true,
    ["Cybotic Greatsword"] = true,
    ["Divine Ruin Bow"] = true,
    ["Divine Sword"] = true,
    ["Double Sided Prismatic"] = true,
    ["Draconic Blade"] = true,
    ["Dream Scythe"] = true,
    ["Dual Astral Vanguard"] = true,
    ["Dual Bloom Katana"] = true,
    ["Dual Chroma Energy Sword"] = true,
    ["Dual Cyber Sickle"] = true,
    ["Dual Cyborg Blade"] = true,
    ["Dual Demonic Greatsword"] = true,
    ["Dual Elemental Masterblade"] = true,
    ["Dual Emperor's Lance"] = true,
    ["Dual Fire Katana"] = true,
    ["Dual Fire Blasters"] = true,
    ["Dual Golden Fang"] = true,
    ["Dual Holo Fan"] = true,
    ["Dual Hacker Scythe (Finisher)"] = true,
    ["Dual Kitsune Blade"] = true,
    ["Dual Nature Kunai"] = true,
    ["Dual Nebula Blasters"] = true,
    ["Dual Neon Vipers"] = true,
    ["Dual New Years Fan"] = true,
    ["Dual Star Staffs"] = true,
    ["Dual Summer Scythe"] = true,
    ["Dual Wispwind Reaper"] = true,
    ["Eclipse Warblade"] = true,
    ["Electro Katana"] = true,
    ["Emberfang Blade"] = true,
    ["Enchanted Greatsword"] = true,
    ["England Football"] = true,
    ["Evil Runics Blade"] = true,
    ["Eternal Shield"] = true,
    ["Fallen Cherub's Blade"] = true,
    ["Festive Chakram"] = true,
    ["Festive Scythe"] = true,
    ["Firebloom Scythe"] = true,
    ["Flood Serpent"] = true,
    ["Flowering Sword"] = true,
    ["Forsaken Riftide"] = true,
    ["France Football"] = true,
    ["Frostbloom Lance"] = true,
    ["Germany Football"] = true,
    ["Gleaming Sakura"] = true,
    ["Ghostly Vengeance"] = true,
    ["Gold Vanity Blade"] = true,
    ["Golden Aeroblades"] = true,
    ["Golden Katana"] = true,
    ["Golden Nunchucks"] = true,
    ["Golden Slicer"] = true,
    ["Heavenly Sword"] = true,
    ["Hydrocore Detonation"] = true,
    ["Hibiscus Blade"] = true,
    ["Ice King's Bow"] = true,
    ["Ice Warrior"] = true,
    ["Ironrose Lance"] = true,
    ["Lumenwing Blade"] = true,
    ["Bloomveil Kunai"] = true,
    ["Play Sword"] = true,
    ["Amber Edge"] = true,
    ["Amber Edge Emote"] = true,
    ["Bloodmoon Blade"] = true,
    ["Inferno Reaver"] = true,
    ["Iridescent Stormblade"] = true,
    ["Kraken Scythe"] = true,
    ["Radiant Duckling Kunai"] = true,
    ["Kurogin Katana"] = true,
    ["Laser Twinblade"] = true,
    ["Lemonade Slicer"] = true,
    ["Lightning Cards"] = true,
    ["Monarch Shield"] = true,
    ["Moonlight Blade"] = true,
    ["Mortal's Demise"] = true,
    ["New Year's Lance"] = true,
    ["New Year's Spear"] = true,
    ["Northstar Reaper"] = true,
    ["Ogre's Axe"] = true,
    ["Periastron's Glory"] = true,
    ["Permafrost Flowerblade"] = true,
    ["Permafrost Staff"] = true,
    ["Phantom Blade"] = true,
    ["NO BATIDÃO"] = true,
    ["Phantom Warrior"] = true,
    ["Plasma Beam Blade"] = true,
    ["Plasma Blasters (Finisher)"] = true,
    ["Poison Ivy"] = true,
    ["Ranked NA Season 2 Top 100 Sword"] = true,
    ["Ranked NA Season 2 Top 25 Sword"] = true,
    ["Ranked Season 10 Top 50"] = true,
    ["Ranked Season 10 Champion"] = true,
    ["Ranked Season 10 Top 200"] = true,
    ["Ranked Season 11 Top 200"] = true,
    ["Ranked Season 11 Top 50"] = true,
    ["Ranked Season 12 Champion"] = true,
    ["Ranked Season 12 Top 200"] = true,
    ["Ranked Season 12 Top 50"] = true,
    ["Ranked Season 14 Top 50"] = true,
    ["Ranked Season 16 Champion"] = true,
    ["Ranked Season 16 Top 50"] = true,
    ["Ranked Season 17 Champion"] = true,
    ["Ranked Season 17 Top 50"] = true,
    ["Ranked Season 18 Champion"] = true,
    ["Ranked Season 2 Top 200 Sword"] = true,
    ["Ranked Season 2 Top 50 Sword"] = true,
    ["Ranked Season 3 Top 50 Sword"] = true,
    ["Ranked Season 5 Champion"] = true,
    ["Ranked Season 6 Champion"] = true,
    ["Ranked Season 6 Top 200"] = true,
    ["Ranked Season 7 Champion"] = true,
    ["Ranked Season 7 Top 200"] = true,
    ["Ranked Season 7 Top 50"] = true,
    ["Ranked Season 8 Top 50"] = true,
    ["Ranked Season 8 Top 1"] = true,
    ["Ranked Season 8 Top 200"] = true,
    ["Ranked Season 8 Champion"] = true,
    ["Ranked Season 9 Champion"] = true,
    ["Ranked Season 9 Top 200"] = true,
    ["Ranked Season 9 Top 50"] = true,
    ["Raven Greatsword"] = true,
    ["Resolution Rumble Warrior"] = true,
    ["Riftflare Blade"] = true,
    ["Santa's Wrecker"] = true,
    ["Savior Greatsword"] = true,
    ["Sci Fi Blade"] = true,
    ["Shadow Cards"] = true,
    ["Skullsplitter"] = true,
    ["Silk Divinity Blade"] = true,
    ["Snowstorm Sabre"] = true,
    ["Snowveil Blade"] = true,
    ["Solarflare Glaive"] = true,
    ["Spectral Crescent"] = true,
    ["Sundue Slash"] = true,
    ["Sunspike"] = true,
    ["Super Quantum"] = true,
    ["Sword of the Sun"] = true,
    ["Sylvan Blade"] = true,
    ["Twisted Rosemary Blade"] = true,
    ["USA Football"] = true,
    ["Valkyrien Scythe"] = true,
    ["Valor's Rage"] = true,
    ["Vampire Saw"] = true,
    ["Vampire Sickle"] = true,
    ["Voidstrike Blade"] = true,
    ["Water Bow"] = true,
    ["Wildheart"] = true,
    ["Haidilao Dance"] = true,
    ["Wintery Greatblade"] = true,
    ["Wrapped Froststaff"] = true,
    ["Yuleflame"] = true,
    ["Singularity Katana"] = true,
    ["Zephyr Scythe"] = true,
    ["Blackhole Katana"] = true,
    ["Flower Katana"] = true,
    ["Stardust Katana"] = true,
    ["Stellar Blade"] = true,
    ["Souless Katana"] = true,
    ["Shadow Dagger"] = true,
    ["Firebloom Blade"] = true,
    ["Pumpkin Blade"] = true,
    ["Serene Scythe"] = true,
    ["Blazing Azure Talon"] = true,
}

--==================================================
-- MANUAL NUKE LIST
--==================================================

local NUKE_ITEMS = {
    ["Eternal Piercer"] = 27000,
    ["Love For You"] = 12000,
    ["Winter Wolf"] = 18000,
    ["Kitty Katana"] = 12600,
    ["Moonflower Katana"] = 17000,
    ["Bunny"] = 120000,
    ["Ranked Season 15 Top 50"] = 31000,
    ["Icebound Dominus"] = 30000,
    ["Regret Blades"] = 19000,
    ["Celestial Whisper"] = 21000,
    ["Royal Duality"] = 40000,
    ["Queen Blade"] = 27500,
    ["Eternum Galepiercer"] = 9400,
    ["Zombie Slide"] = 100000,
}

--==================================================
-- RAP TIERS
--==================================================

local RAP_TIERS = {
    { Name = "LOW", Min = 100, Max = 3000 },
    { Name = "MID", Min = 3001, Max = 9999 },
    { Name = "HIGH", Min = 10000, Max = 99999 },
    { Name = "100K+", Min = 100000, Max = math.huge },
}

--==================================================
-- REQUEST
--==================================================

local REQUEST =
    request
    or http_request
    or (syn and syn.request)

local function safeRequest(options, retries)
    if type(options) ~= "table" or not REQUEST then
        return nil
    end

    local success, response = pcall(function()
        return REQUEST({
            Url = options.Url,
            Method = options.Method or "GET",
            Headers = options.Headers,
            Body = options.Body,
        })
    end)

    if success then
        return response
    end

    return nil
end

local function getResponseBody(response)
    if type(response) ~= "table" then
        return nil
    end

    return response.Body or response.body
end

local function canDoServerHop()
    return os.clock() - lastServerHopAt >= SERVER_HOP_COOLDOWN_SECONDS
end

local function canDoScan()
    return os.clock() - lastScanAt >= SAFE_SCAN_COOLDOWN_SECONDS
end

--==================================================
-- SAFE REQUIRE (retry kalau module belum siap)
--==================================================

local function safeRequire(module, label, maxAttempts)
    maxAttempts = maxAttempts or 10

    for attempt = 1, maxAttempts do
        local success, result = pcall(function()
            return require(module)
        end)

        if success and result then
            print("[Scanner] ✅ Module loaded:", label or "unknown")
            return result
        end

        warn(
            "[Scanner] ⚠️ Gagal require " .. tostring(label)
            .. " (attempt " .. attempt .. "/" .. maxAttempts .. "): "
            .. tostring(result)
        )

        if attempt < maxAttempts then
            task.wait(2)  -- tunggu 2 detik sebelum retry
        end
    end

    warn("[Scanner] ❌ Gagal load module:", label)
    return nil
end

--==================================================
-- GET CONTROLLERS
--==================================================

--==================================================
-- WAIT GAME FULLY LOADED
--==================================================
do
    local startTime = os.time()
    local loadTimeout = 180  -- 3 menit, lebih aman

    while not game:IsLoaded() do
        task.wait(0.5)

        if os.time() - startTime > loadTimeout then
            warn("[Scanner] Game gak kelar load " .. loadTimeout .. " detik, stop.")
            blockedServerIds[tostring(game.JobId)] = true
            return
        end
    end
    task.wait(3)  -- buffer buat replication
end

--==================================================
-- ROBUST WaitForChild (gak crash kalau nil)
--==================================================
local function waitChildSafe(parent, name, timeout)
    if not parent then return nil end
    local deadline = os.clock() + (timeout or 30)
    repeat
        local c = parent:FindFirstChild(name)
        if c then return c end
        task.wait(0.5)
    until os.clock() >= deadline
    return nil
end

--==================================================
-- GET CONTROLLERS (RETRY 2X)
--==================================================
local Controllers = waitChildSafe(ReplicatedStorage, "Controllers", 30)

if not Controllers then
    warn("[Scanner] Controllers timeout. Tunggu 15 detik, retry...")
    task.wait(15)
    Controllers = waitChildSafe(ReplicatedStorage, "Controllers", 60)
end

if not Controllers then
    warn("[Scanner] ❌ Controllers gagal 2x. Stop script (server gak ready).")
    return  -- guard lu bakal restart via queue berikutnya
end

local Trading = waitChildSafe(Controllers, "Trading", 30)
local Booth = waitChildSafe(Controllers, "Booth", 30)

if not Trading or not Booth then
    warn("[Scanner] ❌ Trading/Booth gak ditemukan. Stop.")
    return
end

local BoothControllerModule = waitChildSafe(Booth, "BoothController", 30)
local RAPControllerModule = waitChildSafe(Trading, "RAPController", 30)

if not BoothControllerModule or not RAPControllerModule then
    warn("[Scanner] ❌ Controller modules gak ditemukan. Stop.")
    return
end

-- REQUIRED MODULES (INI YANG HILANG!)
local BoothController = safeRequire(BoothControllerModule, "BoothController")
local RAPController = safeRequire(RAPControllerModule, "RAPController")

if not BoothController or not RAPController then
    warn("[Scanner] ❌ Gagal require controller modules. Stop.")
    return
end

--==================================================
-- REPLICATED INSTANCES
--==================================================

--==================================================
-- REPLICATED INSTANCES
--==================================================

local ReplicatedInstancesModule =
    ReplicatedStorage.Shared:WaitForChild("ReplicatedInstances", 30)

local ReplicatedInstances =
    safeRequire(ReplicatedInstancesModule, "ReplicatedInstances")

if not ReplicatedInstances then
    warn("[Scanner] ❌ Gagal load ReplicatedInstances. Stop script.")
    return
end

--==================================================
-- EMOTE DATABASE
--==================================================

local Misc =
    ReplicatedStorage:WaitForChild("Misc")

local EmotesFolder =
    Misc:WaitForChild("Emotes")

--==================================================
-- BOOTH REPLION
--==================================================

local BoothListings =
    BoothController.BoothListings

if not BoothListings then
    warn("[Scanner] BoothListings tidak tersedia.")
    return
end

print("[Scanner] BoothListings ditemukan:", BoothListings)

--==================================================
-- SALES HISTORY & AUTO-BUY (TAMBAHAN)
--==================================================

local NetModule =
    ReplicatedStorage.Packages:WaitForChild("Net", 30)

local Net =
    safeRequire(NetModule, "Net")

if not Net then
    warn("[Scanner] ❌ Gagal load Net. Stop script.")
    return
end

local RAPHistoryRequest =
    Net:RemoteFunction("RequestRAPHistory")

--==================================================
-- PURCHASE REMOTE
--==================================================
local PurchaseRemote
do
    local ok, remote = pcall(function()
        return Net:RemoteFunction("PurchaseBoothListing")
    end)
    if ok and remote then
        PurchaseRemote = remote
        print("[AUTO-BUY] ✅ PurchaseRemote via Net:RemoteFunction")
    else
        local rawNet = ReplicatedStorage.Packages._Index["sleitnick_net@0.1.0"].net
        PurchaseRemote = rawNet:FindFirstChild("RF/PurchaseBoothListing")
        if PurchaseRemote then
            print("[AUTO-BUY] ✅ PurchaseRemote via raw module")
        end
    end
end

if not PurchaseRemote then
    warn("[AUTO-BUY] ❌ PurchaseRemote nil! Auto-buy tidak akan jalan.")
else
    print("[AUTO-BUY] ✅ PurchaseRemote ready")
end

local SalesHistoryCache = {}

local function getSalesHistory(itemType, itemKey)
    if not itemType or not itemKey then
        return nil
    end

    local cacheKey = tostring(itemType) .. ":" .. tostring(itemKey)

    if SalesHistoryCache[cacheKey] ~= nil then
        return SalesHistoryCache[cacheKey] or nil
    end

    local endDate = DateTime.now()
    local startDate = DateTime.fromUnixTimestamp(endDate.UnixTimestamp - SALES_HISTORY_DAYS * 86400)

    local success, requestSuccess, points = pcall(function()
        local invokeSuccess, history = RAPHistoryRequest:InvokeServer(itemType, itemKey, startDate, endDate)
        return invokeSuccess, history
    end)

    if not success or not requestSuccess or typeof(points) ~= "table" then
        SalesHistoryCache[cacheKey] = false
        if DEBUG then
            warn("[SALES HISTORY] Request failed:", itemType, itemKey)
        end
        return nil
    end

    local totalSales = 0
    local rapTotal = 0
    local rapPointCount = 0
    local daily = {}

    for _, point in ipairs(points) do
        if typeof(point) == "table"
            and typeof(point.Date) == "DateTime"
            and tonumber(point.RAP)
            and tonumber(point.Count)
        then
            local utcDate = point.Date:ToUniversalTime()
            local day = DateTime.fromUniversalTime(utcDate.Year, utcDate.Month, utcDate.Day)
            local dayKey = day.UnixTimestamp
            local dayData = daily[dayKey]

            if not dayData then
                dayData = {
                    date = day,
                    rapTotal = 0,
                    pointCount = 0,
                    sales = 0,
                }
                daily[dayKey] = dayData
            end

            local rapValue = tonumber(point.RAP)
            local sales = tonumber(point.Count)

            dayData.rapTotal = dayData.rapTotal + rapValue
            dayData.pointCount = dayData.pointCount + 1
            dayData.sales = dayData.sales + sales
            totalSales = totalSales + sales
            rapTotal = rapTotal + rapValue
            rapPointCount = rapPointCount + 1
        end
    end

    if rapPointCount == 0 then
        SalesHistoryCache[cacheKey] = false
        return nil
    end

    local chartLabels = {}
    local chartValues = {}
    local chartSales = {}
    local dailyRows = {}

    for _, dayData in pairs(daily) do
        table.insert(dailyRows, dayData)
    end

    table.sort(dailyRows, function(left, right)
        return left.date.UnixTimestamp < right.date.UnixTimestamp
    end)

    local hasSalesDayOverThreshold = false

    for _, dayData in ipairs(dailyRows) do
        if dayData.sales > MIN_SALES_COUNT then
            hasSalesDayOverThreshold = true
        end

        table.insert(chartLabels, dayData.date:FormatUniversalTime("MMM D", "en-us"))
        table.insert(chartValues, math.round(dayData.rapTotal / dayData.pointCount))
        table.insert(chartSales, dayData.sales)
    end

    -- ============ PERBAIKAN DI SINI ============
    -- Hitung jumlah hari yang mencapai target sales
    local daysAboveThreshold = 0
    for _, dayData in pairs(daily) do
        if dayData.sales >= AUTO_BUY_MIN_DAILY_SALES then
            daysAboveThreshold = daysAboveThreshold + 1
        end
    end

    local chartConfig = {
        type = "line",
        data = {
            labels = chartLabels,
            datasets = {
                {
                    label = "Rata-rata RAP",
                    data = chartValues,
                    borderColor = "#2dd4a3",
                    backgroundColor = "rgba(45,212,163,0.12)",
                    fill = true,
                    tension = 0.25,
                    pointRadius = 3,
                    pointHoverRadius = 6,
                },
            },
        },
        options = {
            responsive = true,
            maintainAspectRatio = false,
            plugins = {
                title = {
                    display = true,
                    text = "Rata-rata RAP per Hari",
                },
                tooltip = {
                    callbacks = {
                        label = "function(context) { return 'RAP: ' + context.parsed.y + ' | Sales: ' + "
                            .. HttpService:JSONEncode(chartSales)
                            .. "[context.dataIndex]; }",
                    },
                },
            },
            scales = {
                y = {
                    beginAtZero = false,
                },
            },
        },
    }

    local chartUrl = "https://quickchart.io/chart?width=500&height=300&format=png&c="
        .. HttpService:UrlEncode(HttpService:JSONEncode(chartConfig))

    local result = {
        totalSales = totalSales,
        averageRap = math.round(rapTotal / rapPointCount),
        hasSalesDayOverThreshold = hasSalesDayOverThreshold,
        chartUrl = chartUrl,
        daysAboveThreshold = daysAboveThreshold,   -- <-- sekarang sudah terdefinisi
    }

    SalesHistoryCache[cacheKey] = result
    return result
end

--==================================================
-- AUTO-BUY (pakai method lama: BoothController:PurchaseListing)
--==================================================

local function attemptPurchase(ownerId, listingId, itemName, price, maxPrice)
    if not AUTO_BUY_ENABLED then return false end

    if price > maxPrice then
        print("[AUTO-BUY] ⏭️ Harga terlalu tinggi:", itemName, price, ">", maxPrice)
        return false
    end

    -- WAJIB pakai Player object. Kalau seller offline, skip.
    local numericOwnerId = tonumber(ownerId)
    local player = numericOwnerId and Players:GetPlayerByUserId(numericOwnerId) or nil

    if not player then
        warn("[AUTO-BUY] ⏭️ Skip — seller offline (ownerId:", tostring(ownerId), ")")
        return false
    end

    print(string.format("[AUTO-BUY] 🎯 BELI: %s | price: %d | max: %d | seller: %s",
        itemName, price, maxPrice, player.Name))

    local success, result = pcall(function()
        return BoothController:PurchaseListing(player, listingId)
    end)

    -- PENTING: cek `result == true`, bukan cuma `success`
    if success and result == true then
        print("[AUTO-BUY] ✅ BERHASIL membeli", itemName, "seharga", price)
        return true
    end

    warn("[AUTO-BUY] ❌ GAGAL:", itemName,
        "| success:", tostring(success),
        "| result:", tostring(result))
    return false
end

--==================================================
-- HELPERS
--==================================================

local function dump(value, depth, visited)
    depth = depth or 0
    visited = visited or {}

    if depth > 4 then
        return "<max depth>"
    end

    if typeof(value) ~= "table" then
        return tostring(value)
    end

    if visited[value] then
        return "<circular>"
    end

    visited[value] = true

    local result = "{\n"

    for k, v in pairs(value) do
        result ..= string.rep("    ", depth + 1)
        result ..= "[" .. tostring(k) .. "] = "

        if typeof(v) == "table" then
            result ..= dump(v, depth + 1, visited)
        else
            result ..= tostring(v)
        end

        result ..= ",\n"
    end

    result ..= string.rep("    ", depth) .. "}"

    return result
end

local unresolvedListingLogged = false

local function getListingItemKey(listing)
    if typeof(listing) ~= "table" then
        return nil
    end

    local directKey =
        listing.ItemKey
        or listing.itemKey
        or listing.Key
        or listing.key
        or listing.ItemName
        or listing.itemName

    if directKey then
        return directKey
    end

    local nestedItem = listing.Item

    if nestedItem then
        local success, nestedKey =
            pcall(function()
                return nestedItem.Name
                    or nestedItem.name
                    or nestedItem.ItemName
                    or nestedItem.itemName
                    or nestedItem.ItemKey
                    or nestedItem.itemKey
            end)

        if success and nestedKey then
            return nestedKey
        end
    end

    if not unresolvedListingLogged and DEBUG then
        unresolvedListingLogged = true

        warn("[NO ITEM KEY] Listing shape:")
        print(dump(listing, 3))
    end

    return nil
end

--==================================================
-- RAP HELPERS
--==================================================

local function getFilteredItemKey(itemType, item)
    local success, result =
        pcall(function()
            return RAPController:GetFilteredItemKey(
                itemType,
                item
            )
        end)

    if not success then
        if DEBUG then
            warn("[ITEM KEY ERROR]", result)
        end

        return nil
    end

    return result
end

local function getRAP(itemType, itemKey)
    local success, result =
        pcall(function()
            return RAPController:GetRAPAsync(
                itemType,
                itemKey,
                true
            )
        end)

    if not success then
        if DEBUG then
            warn("[RAP ERROR]", result)
        end

        return nil
    end

    return result
end

local function getRAPTier(rap)
    for _, tier in ipairs(RAP_TIERS) do
        if rap >= tier.Min
            and rap < tier.Max then

            return tier.Name
        end
    end

    return nil
end

local function getUnderrapThreshold(tierName)
    return UNDERRAP_THRESHOLDS[tierName]
        or math.huge
end

--==================================================
-- OWNER
--==================================================

local function getOwnerInfo(ownerId)
    local numericOwnerId =
        tonumber(ownerId)

    if not numericOwnerId then
        return {
            username = tostring(ownerId),
            displayName = tostring(ownerId),
        }
    end

    local player =
        Players:GetPlayerByUserId(
            numericOwnerId
        )

    if player then
        return {
            username = player.Name,
            displayName = player.DisplayName,
        }
    end

    local success, result =
        pcall(function()
            return Players:GetNameFromUserIdAsync(
                numericOwnerId
            )
        end)

    if success then
        return {
            username = result,
            displayName = result,
        }
    end

    return {
        username = tostring(ownerId),
        displayName = tostring(ownerId),
    }
end

--==================================================
-- OWNER AVATAR
--==================================================

local function getOwnerAvatarUrl(ownerId)
    local numericOwnerId =
        tonumber(ownerId)

    if not numericOwnerId then
        return nil
    end

    local thumbnailApiUrl = string.format(
        "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=%d&size=420x420&format=Png&isCircular=false",
        numericOwnerId
    )

    if REQUEST then
        local success, response =
            pcall(function()
                return REQUEST({
                    Url = thumbnailApiUrl,
                    Method = "GET",
                })
            end)

        if success
            and response
            and response.Body then

            local decodedSuccess, decoded =
                pcall(function()
                    return HttpService:JSONDecode(
                        response.Body
                    )
                end)

            if decodedSuccess
                and decoded
                and decoded.data
                and decoded.data[1]
                and decoded.data[1].imageUrl then

                return decoded.data[1].imageUrl
            end
        end
    end

    return string.format(
        "https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=420&height=420&format=png",
        numericOwnerId
    )
end

--==================================================
-- OWNER PROFILE
--==================================================

local function getOwnerProfileUrl(ownerId)
    local numericOwnerId =
        tonumber(ownerId)

    if not numericOwnerId then
        return nil
    end

    return string.format(
        "https://www.roblox.com/users/%d/profile",
        numericOwnerId
    )
end

--==================================================
-- SERVER LINK
--==================================================

local function getServerLink()
    return string.format(
        "roblox://placeId=%s&gameInstanceId=%s",
        tostring(game.PlaceId),
        tostring(game.JobId)
    )
end

-- BoothListings has changed shape between game updates, so accept common
-- field names and keep the webhook useful when optional metadata is absent.
local function normalizeId(value)
    local numericValue = tonumber(value)
    return numericValue and tostring(numericValue) or tostring(value)
end

local function getBoothPosition(instance)
    if instance:IsA("Model") and instance.PrimaryPart then
        return instance.PrimaryPart.Position
    end

    return nil
end

local function getSpawnPart()
    local spawn = Workspace:FindFirstChild("SpawnLocation", true)

    if spawn and spawn:IsA("BasePart") then
        return spawn
    end

    for _, instance in ipairs(Workspace:GetDescendants()) do
        if instance:IsA("BasePart")
            and string.find(string.lower(instance.Name), "spawn") then
            return instance
        end
    end

    return nil
end

local function getRelativeBoothLocation(spawn, position)
    if not spawn or not position then
        return nil
    end

    -- Posisi booth relatif terhadap spawn
    local offset = spawn.CFrame:PointToObjectSpace(position)

    -- Jarak booth dari spawn
    local distance = (position - spawn.Position).Magnitude

    --==================================================
    -- RING / AREA
    --==================================================

    -- Ring Dalam = area tengah saja
    -- Ring Luar  = area setelah ring tengah,
    -- termasuk area belakang karpet merah.
    --
    -- Kalau ternyata batasnya sedikit terlalu besar/kecil,
    -- cukup ubah angka ini.
    local INNER_RADIUS = 65

    local ring

    if distance <= INNER_RADIUS then
        ring = "Dalam"
    else
        ring = "Luar"
    end

    --==================================================
    -- DIRECTION
    --==================================================

    -- Berdasarkan posisi map:
    --
    --          ATAS
    --     ATAS KIRI | ATAS KANAN
    --          SPAWN
    --       KIRI | KANAN
    --     BAWAH KIRI | BAWAH KANAN
    --          BAWAH
    --
    -- X:
    -- + = kanan
    -- - = kiri
    --
    -- Z:
    -- - = atas / depan
    -- + = bawah / belakang

    local x = offset.X
    local z = offset.Z

    -- 0°  = kanan
    -- 90° = atas
    -- 180° = kiri
    -- 270° = bawah
    local angle = math.deg(math.atan2(-z, x))

    if angle < 0 then
        angle += 360
    end

    local direction

    --==================================================
    -- 8 DIRECTIONS
    --==================================================

    if angle >= 337.5 or angle < 22.5 then

        direction = "Kanan"

    elseif angle >= 22.5 and angle < 67.5 then

        direction = "Atas Kanan"

    elseif angle >= 67.5 and angle < 112.5 then

        direction = "Atas"

    elseif angle >= 112.5 and angle < 157.5 then

        direction = "Atas Kiri"

    elseif angle >= 157.5 and angle < 202.5 then

        direction = "Kiri"

    elseif angle >= 202.5 and angle < 247.5 then

        direction = "Bawah Kiri"

    elseif angle >= 247.5 and angle < 292.5 then

        direction = "Bawah"

    else

        direction = "Bawah Kanan"
    end

    --==================================================
    -- FINAL LOCATION
    --==================================================

    return string.format(
        "%s • %s • %.0f studs",
        ring,
        direction,
        distance
    )
end

local function buildBoothIndex()

    local boothsByOwnerId = {}
    local spawn = getSpawnPart()

    for _, booth in ipairs(
        CollectionService:GetTagged("TradeBoothStand")
    ) do

        local ownerId =
            booth:GetAttribute("Owner")

        local position =
            getBoothPosition(booth)

        local location =
            getRelativeBoothLocation(
                spawn,
                position
            )

        if location then
            location =
                booth.Name
                .. " • "
                .. location
        else
            location =
                booth.Name
        end

        if DEBUG then

            print(
                "================================"
            )

            print(
                "[BOOTH DEBUG]",
                booth:GetFullName()
            )

            print(
                "Owner:",
                tostring(ownerId)
            )

            print(
                "Attributes:"
            )

            for attributeName, attributeValue
                in pairs(booth:GetAttributes()) do

                print(
                    "   ",
                    attributeName,
                    "=",
                    tostring(attributeValue)
                )
            end

            print(
                "================================"
            )
        end

        if ownerId ~= nil then

            boothsByOwnerId[normalizeId(ownerId)] = {
    location = location,
    position = position,
    booth = booth,
    ownerId = ownerId,
}

        end
    end

    return boothsByOwnerId
end

local function getBoothMetadata(
    ownerId,
    listing,
    boothsByOwnerId
)
    local indexedBooth =
        boothsByOwnerId
        and boothsByOwnerId[
            normalizeId(ownerId)
        ]

    local location =
        indexedBooth
        and indexedBooth.location

    if not location
        and typeof(listing) == "table" then

        location =
            listing.BoothLocation
            or listing.Location
    end

    if not location
        or tostring(location) == "" then

        location = "Lokasi tidak tersedia"
    end

    return {
        claimed = indexedBooth ~= nil,
        location = tostring(location),
    }
end

--==================================================
-- COUNT LISTINGS
--==================================================

local function countListings(data)
    local count = 0

    if typeof(data) ~= "table" then
        return count
    end

    for _, listings in pairs(data) do
        if typeof(listings) == "table" then
            for _ in pairs(listings) do
                count += 1
            end
        end
    end

    return count
end

--==================================================
-- LOAD BOOTH DATA
--==================================================

local function getLoadedBoothData()
    task.wait(BOOTH_LOAD_DELAY_SECONDS)

    local deadline =
        os.clock()
        + BOOTH_LOAD_TIMEOUT_SECONDS

    local lastData

    repeat
        local success, data =
            pcall(function()
                return BoothListings:Get({})
            end)

        if success
            and typeof(data) == "table" then

            lastData = data

            if countListings(data) > 0 then
                return data
            end

        elseif not success
            and DEBUG then

            warn(
                "[Scanner] Booth data belum siap:",
                data
            )
        end

        task.wait(1)

    until os.clock() >= deadline

    return lastData
end

--==================================================
-- EMOTE DISPLAY NAME
--==================================================

local function getEmoteDisplayName(itemName)
    if not itemName then
        return nil
    end

    local emote =
        EmotesFolder:FindFirstChild(
            tostring(itemName)
        )

    if not emote then
        if DEBUG then
            warn(
                "[EMOTE NOT FOUND]",
                tostring(itemName)
            )
        end

        return nil
    end

    local emoteName =
        emote:GetAttribute("EmoteName")

    if typeof(emoteName) == "string"
        and emoteName ~= "" then

        return emoteName
    end

    return emote.Name
end

--==================================================
-- SWORD IMAGE
--==================================================
-- Contoh hasil model:
--
-- Dual Astral Vanguard.1 | MeshPart
-- MeshId:
-- rbxassetid://443853663
--
-- TextureID:
-- rbxassetid://443853675
--
-- TextureID akan dipakai sebagai gambar.
--==================================================

local SwordImageCache = {}

local function assetIdFromString(value)
    if typeof(value) ~= "string" then
        return nil
    end

    local id =
        string.match(
            value,
            "rbxassetid://(%d+)"
        )

    if id then
        return id
    end

    id =
        string.match(
            value,
            "[?&]id=(%d+)"
        )

    if id then
        return id
    end

    id =
        string.match(
            value,
            "(%d+)"
        )

    return id
end

local function getAssetThumbnailUrl(assetId)
    if not assetId or not REQUEST then
        return nil
    end

    local url = string.format(
        "https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png&isCircular=false",
        tostring(assetId)
    )

    local success, response =
        pcall(function()
            return REQUEST({
                Url = url,
                Method = "GET",
            })
        end)

    if not success
        or not response
        or not response.Body then

        if DEBUG then
            warn(
                "[ITEM IMAGE] Thumbnail request failed:",
                tostring(assetId),
                response
            )
        end

        return nil
    end

    local decodeSuccess, data =
        pcall(function()
            return HttpService:JSONDecode(
                response.Body
            )
        end)

    if decodeSuccess
        and data
        and data.data
        and data.data[1]
        and typeof(data.data[1].imageUrl) == "string"
        and data.data[1].imageUrl ~= "" then

        return data.data[1].imageUrl
    end

    if DEBUG then
        warn(
            "[ITEM IMAGE] Thumbnail URL missing:",
            tostring(assetId),
            tostring(response.StatusCode),
            tostring(response.Body)
        )
    end

    return nil
end

local function getItemImageUrl(itemType, itemKey)

    if not itemType or not itemKey then
        return nil
    end

    local cacheKey =
        tostring(itemType)
        .. ":"
        .. tostring(itemKey)

    if SwordImageCache[cacheKey] ~= nil then
        return SwordImageCache[cacheKey]
    end

    local collections = {
        Sword = {"Swords"},
        Emote = {"Emotes", "Emote"},
        Explosion = {
            "Explosions",
            "Explosion",
            "Effects",
            "Effect",
            "Particles",
        },
    }

    local imageInstance
    local collectionNames = collections[itemType] or {}

    for _, collectionName in ipairs(collectionNames) do
        local success, instance =
            pcall(function()
                return ReplicatedInstances:GetInstance(
                    collectionName,
                    tostring(itemKey)
                )
            end)

        if success and instance then
            imageInstance = instance
            break
        elseif DEBUG and not success then
            warn(
                "[ITEM IMAGE] GetInstance failed:",
                itemType,
                collectionName,
                tostring(itemKey),
                instance
            )
        end
    end

    if not imageInstance and itemType == "Emote" then
        imageInstance = EmotesFolder:FindFirstChild(
            tostring(itemKey)
        )
    end

    if not imageInstance then
        if DEBUG then
            warn(
                "[ITEM IMAGE] Instance not found:",
                itemType,
                tostring(itemKey)
            )
        end

        SwordImageCache[cacheKey] = false
        return nil
    end

    local iconId = nil
local textureId = nil

--==================================================
-- SEARCH ATTRIBUTES
--==================================================

for attributeName, attributeValue in pairs(
    imageInstance:GetAttributes()
) do
    local normalizedName = string.lower(
        tostring(attributeName)
    )

    if string.find(normalizedName, "icon")
        or string.find(normalizedName, "image")
        or string.find(normalizedName, "thumbnail") then

        iconId =
            iconId
            or assetIdFromString(attributeValue)
    end
end

--==================================================
-- SEARCH IMAGE VALUES
--==================================================

for _, obj in ipairs(
    imageInstance:GetDescendants()
) do

    -- IMPORTANT:
    -- Jangan membaca SurfaceAppearance.ColorMap.
    -- Property tersebut membutuhkan Plugin capability.

    if obj:IsA("StringValue") then

        local normalizedName =
            string.lower(obj.Name)

        if string.find(normalizedName, "icon")
            or string.find(normalizedName, "image")
            or string.find(normalizedName, "thumbnail") then

            iconId =
                iconId
                or assetIdFromString(obj.Value)
        end

    elseif obj:IsA("ImageLabel")
        or obj:IsA("ImageButton") then

        iconId =
            iconId
            or assetIdFromString(obj.Image)
    end
end

if DEBUG and iconId then
    print(
        "[ITEM IMAGE] Appearance assets:",
        cacheKey,
        "Icon:",
        tostring(iconId)
    )
end

    --==================================================
    -- SEARCH MESH PARTS
    --==================================================

    for _, obj in ipairs(
        imageInstance:GetDescendants()
    ) do

        if obj:IsA("MeshPart") then

            local meshValue = obj.MeshId
            local textureValue = obj.TextureID

            textureId =
                textureId
                or assetIdFromString(textureValue)

            if textureId then

                if DEBUG then
                    print(
                        "[ITEM IMAGE]",
                        cacheKey,
                        "MeshPart:",
                        obj.Name,
                        "MeshId:",
                        meshValue,
                        "TextureID:",
                        textureValue
                    )
                end

                break
            end
        end
    end

    if not textureId then
        for _, obj in ipairs(imageInstance:GetDescendants()) do
            if obj:IsA("SpecialMesh") then
                textureId = assetIdFromString(obj.TextureId)

                if textureId then
                    break
                end
            end
        end
    end

    --==================================================
    -- SEARCH SPECIAL MESH
    --==================================================

    --==================================================
    -- FALLBACK: DECAL / TEXTURE
    --==================================================

    if not textureId then

        for _, obj in ipairs(
            imageInstance:GetDescendants()
        ) do

            if obj:IsA("Decal")
                or obj:IsA("Texture") then

                local value =
                    obj.Texture

                local id =
                    assetIdFromString(value)

                if id then

                    textureId = id

                    if DEBUG then
                        print(
                            "[ITEM IMAGE]",
                            cacheKey,
                            "Texture:",
                            obj.Name,
                            "Asset:",
                            value
                        )
                    end

                    break
                end
            end
        end
    end

    local imageAssetId =
    iconId
    or textureId

    if not imageAssetId then

        if DEBUG then
            warn(
                "[ITEM IMAGE] No image asset found:",
                itemType,
                tostring(itemKey)
            )
        end

        SwordImageCache[cacheKey] = false
        return nil
    end

    --==================================================
    -- ROBLOX THUMBNAILS API
    --==================================================

    local imageUrl =
        getAssetThumbnailUrl(imageAssetId)

    if not imageUrl then
        SwordImageCache[cacheKey] = false
        return nil
    end

    SwordImageCache[cacheKey] = imageUrl

    if DEBUG then
        print(
            "[ITEM IMAGE URL]",
            itemType,
            tostring(itemKey),
            "=>",
            imageUrl
        )
    end

    return imageUrl
end

--==================================================
-- CUSTOM ITEM CHECK
--==================================================

local function normalizeItemName(itemName)
    return string.lower(
        string.gsub(
            tostring(itemName),
            "%s+",
            " "
        )
    )
end

local function isBoosted(itemType, itemName)
    if not itemType or not itemName then
        return false
    end

    local normalizedItemName = normalizeItemName(itemName)

    for boostedItemName in pairs(BOOSTED_ITEMS) do
        if normalizeItemName(boostedItemName) == normalizedItemName then
            return true
        end
    end

    return false
end

local function getNukeLimit(itemType, itemName)
    if not itemType or not itemName then
        return nil
    end

    -- Semua item di NUKE_ITEMS hanya berlaku untuk Sword
    if itemType ~= "Sword" then
        return nil
    end

    local limit = NUKE_ITEMS[itemName]

    if typeof(limit) == "number" then
        return limit
    end

    return nil
end

--==================================================
-- COLORS
--==================================================

local function getTierColor(tierName)
    local colors = {
        LOW = 16776960,
        MID = 16744448,
        HIGH = 16711935,
        ["100K+"] = 16711680,

        BOOSTED = 65535,
        NUKE = 16711680,
        DEEP_UNDERRAP = 16753920,
    }

    return colors[tierName]
        or 65280
end

--==================================================
-- ITEM DETAILS (Finisher / Mount / Dual)
--==================================================

local ItemDetailsCache = {}

local function getItemDetails(itemType, itemKey)
    if not itemType or not itemKey then
        return { isFinisher = false, hasMount = false }
    end

    local cacheKey = tostring(itemType) .. ":" .. tostring(itemKey)
    if ItemDetailsCache[cacheKey] then
        return ItemDetailsCache[cacheKey]
    end

    local details = { isFinisher = false, hasMount = false, isDual = false }

    -- Deteksi Dual dari nama key
    if string.find(string.lower(tostring(itemKey)), "dual") then
        details.isDual = true
    end

    -- Inspect instance
    local instance
    pcall(function()
        if itemType == "Sword" then
            instance = ReplicatedInstances:GetInstance("Swords", tostring(itemKey))
        elseif itemType == "Emote" then
            instance = EmotesFolder:FindFirstChild(tostring(itemKey))
        end
    end)

    if instance then
        -- Cek attributes
        pcall(function()
            for attrName, attrValue in pairs(instance:GetAttributes()) do
                local n = string.lower(tostring(attrName))
                if string.find(n, "finisher") and attrValue then
                    details.isFinisher = true
                end
                if string.find(n, "mount") and attrValue then
                    details.hasMount = true
                end
                if string.find(n, "dual") and attrValue then
                    details.isDual = true
                end
            end
        end)

        -- Cek children/descendants
        pcall(function()
            for _, child in ipairs(instance:GetDescendants()) do
                local n = string.lower(tostring(child.Name))
                if string.find(n, "finisher") then
                    details.isFinisher = true
                end
                if string.find(n, "mount") then
                    details.hasMount = true
                end
            end
        end)
    end

    ItemDetailsCache[cacheKey] = details
    return details
end

-- Helper: format angka pakai koma
local function formatNumber(n)
    local num = tonumber(n)
    if not num then return tostring(n) end
    local str = tostring(math.floor(num))
    local result = ""
    local count = 0
    for i = #str, 1, -1 do
        result = string.sub(str, i, i) .. result
        count = count + 1
        if count % 3 == 0 and i > 1 then
            result = "," .. result
        end
    end
    return result
end

--==================================================
-- WEBHOOK (versi compact dengan emoji token)
--==================================================

--==================================================
-- KIRIM KE SATU URL
--==================================================
local function sendOneWebhook(webhookUrl, payload, label, itemName)
    if not webhookUrl or webhookUrl == "" then
        warn("[WEBHOOK] URL kosong untuk", label, "|", tostring(itemName))
        return false
    end

    local response = safeRequest({
        Url = webhookUrl,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode(payload),
    }, 3)

    if not response then
        warn("[WEBHOOK] No response", label, "|", tostring(itemName))
        return false
    end

    local status = tonumber(response.StatusCode)
    if status and status >= 400 then
        warn("[WEBHOOK] Discord error", status, label, "|", tostring(itemName),
            ":", tostring(response.Body))
        return false
    end

    return true
end

local function sendWebhook(webhookType, ownerId, listing)
    local server1Url = WEBHOOKS.SERVER1 and WEBHOOKS.SERVER1[webhookType]
    local server2Url = WEBHOOKS.SERVER2 and WEBHOOKS.SERVER2[webhookType]

    if not server1Url or server1Url == "" or string.find(server1Url, "PASTE_") then
        warn("[WEBHOOK] URL Server 1 belum diisi:", webhookType)
        return false
    end

    if not REQUEST then
        warn("[WEBHOOK] Request function tidak tersedia.")
        return false
    end

    -- ====== BUILD PAYLOAD (sama untuk kedua server) ======
    local ownerInfo = getOwnerInfo(ownerId)
    local ownerAvatarUrl = getOwnerAvatarUrl(ownerId)
    local ownerProfileUrl = getOwnerProfileUrl(ownerId)
    local itemImageUrl = getItemImageUrl(listing.itemType, listing.itemKey)

    local details = getItemDetails(listing.itemType, listing.itemKey)

    local tags = {}
    if details.isFinisher then table.insert(tags, "Finisher") end
    if details.hasMount then table.insert(tags, "Mount") end

    local itemDisplay = "**" .. tostring(listing.itemName) .. "**"
    if #tags > 0 then
        itemDisplay = itemDisplay .. " **(" .. table.concat(tags, ", ") .. ")**"
    end
    if listing.itemType then
        itemDisplay = itemDisplay .. "\n**(" .. tostring(listing.itemType) .. ")**"
    end

    local boothText
    if listing.boothClaimed then
        local loc = tostring(listing.boothLocation or "")
        local ring = "Luar"
        if string.find(loc, "Dalam") then
            ring = "Dalam"
        end
        boothText = "✅ Yes • " .. ring
    else
        boothText = "❌ Belum claim"
    end

    local diffText = string.format("%s (%.0f%%)",
        formatNumber(listing.profit), listing.discount)

        -- URL web Roblox — Discord auto-detect sebagai clickable link
     local serverShort = string.format(
        "roblox://placeId=%s&gameInstanceId=%s",
        tostring(game.PlaceId), tostring(game.JobId)
    )

    local fields = {
        { name = "Seller", value = tostring(ownerInfo.displayName) .. "\n( " .. tostring(ownerId) .. " )", inline = true },
        { name = "Item Name", value = itemDisplay, inline = true },
        { name = "Price", value = "<:token:1551478922242162708> " .. formatNumber(listing.price), inline = true },
        { name = "Current RAP", value = "📊 " .. formatNumber(listing.rap), inline = true },
        { name = "Profit", value = "🔻 " .. diffText, inline = true },
        { name = "Booth Claimed", value = boothText, inline = true },
        { name = "Link Server", value = serverShort, inline = false },
    }

    if listing.salesHistory then
        table.insert(fields, {
            name = "📈 Sales Trend (last " .. SALES_HISTORY_DAYS .. " days)",
            value = string.format("Avg RAP: **%s** | Total Sales: **%s**",
                formatNumber(listing.salesHistory.averageRap),
                formatNumber(listing.salesHistory.totalSales)),
            inline = false,
        })
    end

    if ownerProfileUrl then
        table.insert(fields, { name = "Seller Profile", value = ownerProfileUrl, inline = false })
    end

    local embed = {
        title = "🚨 Under RAP Scanner",
        color = getTierColor(webhookType),
        fields = fields,
        timestamp = DateTime.now():ToIsoDate(),
        footer = {
            text = "Type: " .. tostring(webhookType) ..
                   " | Seller ID: " .. tostring(ownerId),
        },
    }

    if itemImageUrl then
        embed.thumbnail = { url = itemImageUrl }
    elseif ownerAvatarUrl then
        embed.thumbnail = { url = ownerAvatarUrl }
    end

    local SCANNER_AVATAR = "https://cdn.discordapp.com/attachments/1457719933348876399/1551496854670282813/1785800458495.jpg?ex=6ab22f8b&is=6ab0de0b&hm=dce44efe43a59bd268d55fec80fc9a3d9d02a9386f43c8a40b24d485dd1e9a9d"

    local payload = {
        username = tostring(ownerInfo.displayName or ownerInfo.username or "Under RAP Scanner"),
        avatar_url = ownerAvatarUrl or SCANNER_AVATAR,
        embeds = { embed },
    }

    -- ====== KIRIM KE SERVER 1 (LANGSUNG) ======
    local ok1 = sendOneWebhook(server1Url, payload, "SERVER1/" .. tostring(webhookType), listing.itemName)

    -- ====== KIRIM KE SERVER 2 (DELAY) ======
    if server2Url and server2Url ~= "" and not string.find(server2Url, "PASTE_") then
        local itemLabel = listing.itemName
        local wt = webhookType

        task.delay(SECOND_WEBHOOK_DELAY, function()
            pcall(function()
                sendOneWebhook(server2Url, payload, "SERVER2/" .. tostring(wt), itemLabel)
            end)
        end)
    end

    return ok1
end

--==================================================
-- AUTO-BUY WEBHOOK NOTIFICATION
--==================================================

local function sendAutoBuyWebhook(itemName, itemType, itemKey, price, rap, profit, discount, ownerId)
    local server1Url = WEBHOOKS.SERVER1 and WEBHOOKS.SERVER1.AUTO_BUY
    local server2Url = WEBHOOKS.SERVER2 and WEBHOOKS.SERVER2.AUTO_BUY

    if not server1Url or server1Url == "" or string.find(server1Url, "PASTE_") then
        warn("[AUTO-BUY WEBHOOK] URL Server 1 belum diisi.")
        return false
    end

    if not REQUEST then
        warn("[AUTO-BUY WEBHOOK] Request function tidak tersedia.")
        return false
    end

    -- Dapatkan info akun pembeli (player yang menjalankan script)
    local buyerName = LocalPlayer.Name
    local buyerDisplayName = LocalPlayer.DisplayName
    local buyerAvatarUrl = getOwnerAvatarUrl(LocalPlayer.UserId)  -- FIX: pakai fungsi yang sudah ada

    -- Dapatkan info penjual (ownerId)
    local ownerInfo = getOwnerInfo(ownerId)
    local ownerProfileUrl = getOwnerProfileUrl(ownerId)
    local itemImageUrl = getItemImageUrl(itemType, itemKey)

    local embed = {
        title = "🛒 AUTO-BUY SUCCESS",
        color = 0x00ff00,  -- hijau
        fields = {
            {
                name = "Buyer",
                value = string.format("`%s` (%s)", buyerDisplayName, buyerName),
                inline = true,
            },
            {
                name = "Item",
                value = string.format("`%s`", itemName),
                inline = true,
            },
            {
                name = "Type",
                value = string.format("`%s`", itemType or "Unknown"),
                inline = true,
            },
            {
                name = "Price",
                value = string.format("`%s`", price),
                inline = true,
            },
            {
                name = "RAP",
                value = string.format("`%s`", rap),
                inline = true,
            },
            {
                name = "Profit",
                value = string.format("`%s` (%.0f%%)", profit, discount or 0),
                inline = true,
            },
            {
                name = "Seller",
                value = string.format("`%s`", ownerInfo.displayName or ownerInfo.username),
                inline = true,
            },
        },
        footer = {
            text = "Seller ID: " .. tostring(ownerId),
        },
        timestamp = DateTime.now():ToIsoDate(),
    }

        -- Server Link (tempat auto-buy terjadi)
    table.insert(embed.fields, {
        name = "Server Link",
        value = getServerLink(),
        inline = false,
    })

    if ownerProfileUrl then
        table.insert(embed.fields, {
            name = "Seller Profile",
            value = ownerProfileUrl,
            inline = false,
        })
    end

    -- Thumbnail item
    if itemImageUrl then
        embed.thumbnail = {
            url = itemImageUrl,
        }
    end

    -- Jika buyerAvatarUrl valid, pakai sebagai avatar webhook
    local payload = {
        username = buyerDisplayName .. " ",
        avatar_url = buyerAvatarUrl,  -- sudah dipastikan HTTP/HTTPS
        embeds = { embed },
    }

        -- ====== KIRIM KE SERVER 1 (LANGSUNG) ======
    local ok1 = sendOneWebhook(server1Url, payload, "SERVER1/AUTO_BUY", itemName)

    -- ====== KIRIM KE SERVER 2 (DELAY) ======
    if server2Url and server2Url ~= "" and not string.find(server2Url, "PASTE_") then
        local itemLabel = itemName
        task.delay(SECOND_WEBHOOK_DELAY, function()
            pcall(function()
                sendOneWebhook(server2Url, payload, "SERVER2/AUTO_BUY", itemLabel)
            end)
        end)
    end

    if ok1 and DEBUG then
        print("[AUTO-BUY WEBHOOK] Sent S1:", itemName)
    end

    return ok1
end

--==================================================
-- LISTING PARSER (dimodifikasi untuk SALES HISTORY)
--==================================================

local function inspectListing(
    ownerId,
    listingId,
    listing,
    boothsByOwnerId
)

    if typeof(listing) ~= "table" then
        return
    end

    -- Skip harga rendah
    local price = listing.Price or listing.price
    if price and price < 50 then return end

    --==================================================
    -- RAW ITEM KEY
    --==================================================

    local itemKey =
        getListingItemKey(listing)

    --==================================================
    -- ITEM TYPE
    --==================================================

    local itemType =
        listing.ItemType
        or listing.itemType
        or listing.Type
        or listing.type
        or listing.Category
        or listing.category

    --==================================================
    -- PRICE
    --==================================================

    local price =
        listing.Price
        or listing.price

    if DEBUG then

        print(
            "[LISTING]",
            "Owner =",
            ownerId,
            "Listing =",
            listingId,
            "ItemType =",
            itemType,
            "ItemKey =",
            itemKey,
            "Price =",
            price
        )
    end

    if not itemKey or not price then
        return
    end

    if not itemType then

        if DEBUG then
            warn(
                "[NO ITEM TYPE]",
                itemKey
            )
        end

        return
    end

    --==================================================
    -- DISPLAY NAME
    --==================================================

    local displayName

    if itemType == "Emote" then

        displayName =
            getEmoteDisplayName(
                itemKey
            )

        if displayName
            and DEBUG then

            print(
                "[EMOTE NAME]",
                tostring(itemKey),
                "=>",
                tostring(displayName)
            )
        end

    else

        if typeof(listing.DisplayName)
            == "string" then

            displayName =
                listing.DisplayName

        elseif typeof(
            listing.ItemDisplayName
        ) == "string" then

            displayName =
                listing.ItemDisplayName

        elseif typeof(
            listing.ItemName
        ) == "string" then

            displayName =
                listing.ItemName

        elseif typeof(
            listing.itemName
        ) == "string" then

            displayName =
                listing.itemName

        elseif typeof(
            listing.Item
        ) == "table" then

            if typeof(
                listing.Item.DisplayName
            ) == "string" then

                displayName =
                    listing.Item.DisplayName

            elseif typeof(
                listing.Item.Display
            ) == "string" then

                displayName =
                    listing.Item.Display
            end
        end
    end

    local itemName =
        displayName
        or itemKey

    local boothMetadata = getBoothMetadata(
        ownerId,
        listing,
        boothsByOwnerId
    )

    --==================================================
    -- RAP KEY
    --==================================================

    local rapKey = itemKey

    if typeof(listing.Item) == "table" then

        local filteredKey =
            getFilteredItemKey(
                itemType,
                listing.Item
            )

        if filteredKey then
            rapKey = filteredKey
        end
    end

    if DEBUG then

        print(
            "[RAP KEY]",
            tostring(itemName),
            "=>",
            tostring(rapKey)
        )
    end

    if not rapKey then

        warn(
            "[NO RAP KEY]",
            itemName
        )

        return
    end

    --==================================================
    -- GET RAP
    --==================================================

    local rap =
        getRAP(
            itemType,
            rapKey
        )

    if not rap then

        if DEBUG then

            warn(
                "[NO RAP]",
                itemName,
                "|",
                itemType,
                "|",
                rapKey
            )
        end

        return
    end

    --==================================================
    -- DISCOUNT
    --==================================================

    local discount =
        ((rap - price) / rap)
        * 100

    local tierName =
        getRAPTier(rap)

    if not tierName then

        if DEBUG then

            print(
                "[SKIP] RAP tidak masuk tier:",
                rap,
                itemName
            )
        end

        return
    end

    --==================================================
    -- SPECIAL CHECK
    --==================================================

    local boostedCandidate =
        isBoosted(
            itemType,
            itemName
        )

    local nukeLimit = getNukeLimit(itemType, itemName)

    local isNuke =
        nukeLimit ~= nil
        and price <= nukeLimit

    local isUnderrap =
        price < rap
        and discount >=
            getUnderrapThreshold(
                tierName
            )

       local boosted = boostedCandidate and isUnderrap

    -- Cek AUTO_BUY_LIST lebih awal biar bisa skip sales history
    local inAutoBuyList = AUTO_BUY_LIST[itemName] ~= nil
        or AUTO_BUY_LIST[rapKey] ~= nil

    --==================================================
    -- SALES HISTORY — SKIP kalau item ada di AUTO_BUY_LIST
    -- (biar auto-buy gak delay 1-3 detik)
    --==================================================

    local salesHistory
    if (isUnderrap or isNuke) and not boosted and not inAutoBuyList then
        salesHistory = getSalesHistory(
            itemType,
            rapKey
        )

        if tierName == "LOW"
            and (not salesHistory
                or not salesHistory.hasSalesDayOverThreshold) then
            if DEBUG then
                warn(
                    "[LOW SALES FILTER] Skipped:",
                    itemName,
                    "no day with sales >",
                    MIN_SALES_COUNT
                )
            end
            return
        end
    end

    local isDeepUnderrap =
    isUnderrap
    and rap < 1000000
    and discount >
        DEEP_UNDERRAP_PERCENT
    and not boosted

    --==================================================
    -- DEBUG
    --==================================================

    print(
        string.format(
            "[ITEM] %s | Price: %s | RAP: %s | Tier: %s | %.2f%% below RAP",
            tostring(itemName),
            tostring(price),
            tostring(rap),
            tostring(tierName),
            discount
        )
    )

    if boosted then

        print(
            "⚡ BOOSTED:",
            itemName,
            "| Price:",
            price,
            "| RAP:",
            rap
        )
    end

    if isNuke then

        print(
            "☢️ NUKE:",
            itemName,
            "| Price:",
            price,
            "| Limit:",
            nukeLimit,
            "| RAP:",
            rap
        )
    end

    if isUnderrap then

        print(
            "🔥 UNDERRAP:",
            itemName,
            "| Price:",
            price,
            "| RAP:",
            rap,
            "| Tier:",
            tierName,
            "| Discount:",
            string.format(
                "%.2f%%",
                discount
            )
        )
    end

    --==================================================
    -- RETURN
    --==================================================

    if isUnderrap
        or boosted
        or isNuke then

        return {
            itemName = itemName,

            -- PENTING:
            -- itemKey tetap internal key.
            itemKey = itemKey,

            rapKey = rapKey,

            itemType = itemType,

            price = price,
            rap = rap,

            discount = discount,
            profit = rap - price,

            tierName = tierName,

            boosted = boosted,
            nuke = isNuke,

            nukeLimit = nukeLimit,

            deepUnderrap =
                isDeepUnderrap,

            boothClaimed = boothMetadata.claimed,
            boothLocation = boothMetadata.location,
            salesHistory = salesHistory,   -- <-- TAMBAHAN
        }
    end
end

--==================================================
-- SERVER API
--==================================================

--==================================================
-- SERVER API (versi lama)
--==================================================

local function getNewServerOnce()

    if not REQUEST then
        warn("[SERVER HOP] Request function tidak tersedia.")
        return nil
    end

    local preferredServers = {}
    local fallbackServers = {}
    local cursor = nil
    local pagesRead = 0

    repeat
        local url = string.format(
            "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100",
            tostring(game.PlaceId)
        )

        if cursor then
            url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
        end

        local response = safeRequest({
            Url = url,
            Method = "GET",
            Headers = {
                ["Accept"] = "application/json",
            },
        }, 2)

        local responseBody = getResponseBody(response)

        if not responseBody then
            warn("[SERVER HOP] Response kosong.")
            return nil
        end

        local statusCode = tonumber(response.StatusCode)

        if statusCode and (statusCode < 200 or statusCode >= 300) then
            warn(
                "[SERVER HOP] API HTTP error:",
                tostring(statusCode),
                tostring(responseBody):sub(1, 300)
            )
            return nil
        end

        local decodeSuccess, data = pcall(function()
            return HttpService:JSONDecode(responseBody)
        end)

        if not decodeSuccess
            or not data
            or typeof(data.data) ~= "table"
        then
            warn(
                "[SERVER HOP] Data server tidak valid:",
                tostring(responseBody):sub(1, 300)
            )
            return nil
        end

        pagesRead += 1

        for _, server in ipairs(data.data) do
            if typeof(server) == "table"
                and server.id
                and server.id ~= game.JobId
                and not blockedServerIds[tostring(server.id)]
                and tonumber(server.playing) ~= nil
                and tonumber(server.maxPlayers) ~= nil
                and tonumber(server.playing) < tonumber(server.maxPlayers)
            then
                local playing = tonumber(server.playing)

                if playing >= MIN_PREFERRED_PLAYERS
                    and playing <= MAX_PREFERRED_PLAYERS then
                    table.insert(preferredServers, server)
                elseif playing >= MIN_FALLBACK_PLAYERS
                    and playing < MIN_PREFERRED_PLAYERS then
                    table.insert(fallbackServers, server)
                end
            end
        end

        -- NOTE: pakai data.nextPageCursor (top-level), bukan data.data.nextPageCursor
        cursor = data.nextPageCursor
    until not cursor or pagesRead >= SERVER_API_MAX_PAGES

    local pool = nil

    if #preferredServers > 0 then
        pool = preferredServers
        print("[SERVER HOP] Prioritas: random server 10-25 player")
    elseif #fallbackServers > 0 then
        pool = fallbackServers
        print("[SERVER HOP] Pool 10-25 kosong; fallback random server 5-9 player")
    end

    if not pool or #pool == 0 then
        warn("[SERVER HOP] Tidak ada server yang tersedia.")
        return nil
    end

    local selected = pool[math.random(1, #pool)]

    local currentHopCount = 0
    pcall(function()
        currentHopCount = tonumber(
            TeleportService:GetTeleportSetting(TELEPORT_SETTING_KEY)
        ) or 0
    end)

    pcall(function()
        TeleportService:SetTeleportSetting(
            TELEPORT_SETTING_KEY,
            tostring(currentHopCount + 1)
        )
    end)

    print("======================================")
    print("[SERVER HOP] Target:", tostring(selected.id))
    print("[SERVER HOP] Players:", tostring(selected.playing), "/", tostring(selected.maxPlayers))
    print("[SERVER HOP] Pool size:", tostring(#pool))
    print("[SERVER HOP] Pool target:", #preferredServers > 0 and "10+ player" or "fallback")
    print("======================================")

    lastTeleportTargetId = tostring(selected.id)
    return selected.id
end

local function getNewServer()
    for attempt = 1, SAFE_SERVER_HOP_RETRY_LIMIT + 1 do
        local serverId = getNewServerOnce()

        if serverId then
            return serverId
        end

        if attempt <= SAFE_SERVER_HOP_RETRY_LIMIT then
            warn(
                "[SERVER HOP] Mencari server lagi (percobaan "
                .. tostring(attempt + 1)
                .. "/"
                .. tostring(SAFE_SERVER_HOP_RETRY_LIMIT + 1)
                .. ")."
            )

            task.wait(
                SERVER_HOP_FAILURE_RETRY_DELAY_SECONDS
            )
        end
    end

    return nil
end


--==================================================
-- TELEPORT FAILED HANDLER
--==================================================

TeleportService.TeleportInitFailed:Connect(
    function(
        player,
        teleportResult,
        errorMessage
    )

        if player ~= LocalPlayer then
            return
        end

        warn(
            "[SERVER HOP] TeleportInitFailed:",
            tostring(teleportResult),
            tostring(errorMessage)
        )

        if lastTeleportTargetId then
            blockedServerIds[lastTeleportTargetId] = true
            lastTeleportTargetId = nil
        end

        hopAttemptCount += 1
        hopInProgress = false
        lastServerHopAt = 0

        if hopAttemptCount > SAFE_SERVER_HOP_RETRY_LIMIT then
            hopAttemptCount = 0
            warn(
                "[SERVER HOP] Batas retry teleport tercapai; menunggu siklus berikutnya."
            )
            return
        end

        task.delay(2, function()
            pcall(function()
                serverHop()
            end)
        end)
    end
)

--==================================================
-- SERVER HOP
--==================================================

serverHop = function(serverId)

    if not ENABLE_SERVER_HOP then
        print("[Server Hop] Disabled.")
        return
    end

    if hopInProgress then
        print("[Server Hop] Hop sedang berjalan, skip.")
        return
    end

    if not serverId and not canDoServerHop() then
        print("[Server Hop] Cooldown aktif; menunggu server hop berikutnya.")
        return
    end

    hopInProgress = true

    print("======================================")
    print("[Server Hop] Semua webhook sudah dikirim.")
    -- Tunggu pending S2 task.delay biar sempat jalan sebelum teleport
    print(string.format("[Server Hop] Tunggu %d detik biar S2 webhook kelar dulu...", SECOND_WEBHOOK_DELAY + 2))
    task.wait(SECOND_WEBHOOK_DELAY + 2)
    if not serverId then
        print("[Server Hop] Menunggu " .. tostring(SERVER_HOP_DELAY_SECONDS) .. " detik...")
    end
    print("======================================")

    if not serverId then
        task.wait(SERVER_HOP_DELAY_SECONDS)
        serverId = getNewServer()
    else
        print("[Server Hop] Target sudah disiapkan saat webhook phase.")
    end

    if not serverId then
        hopInProgress = false
        warn("[Server Hop] Tidak menemukan server baru.")
        task.delay(SERVER_HOP_FAILURE_RETRY_DELAY_SECONDS, function()
            if not hopInProgress then serverHop() end
        end)
        return
    end

    lastServerHopAt = os.clock()

    print("[Server Hop] Teleport ke:", tostring(serverId))

    local success, result = pcall(function()
        TeleportService:TeleportToPlaceInstance(
            game.PlaceId,
            serverId,
            LocalPlayer
        )
    end)

    if not success then
        hopInProgress = false
        lastServerHopAt = 0
        preparedServerId = nil
        if lastTeleportTargetId then
            blockedServerIds[lastTeleportTargetId] = true
            lastTeleportTargetId = nil
        end

        hopAttemptCount += 1
        if hopAttemptCount > SAFE_SERVER_HOP_RETRY_LIMIT then
            hopAttemptCount = 0
            warn("[SERVER HOP] Batas retry teleport tercapai; menunggu siklus berikutnya.")
            return
        end

        warn("[Server Hop] Teleport gagal:", tostring(result))

        task.delay(SERVER_HOP_FAILURE_RETRY_DELAY_SECONDS, function()
            if not hopInProgress then serverHop() end
        end)
    else
        print("[Server Hop] Teleport request berhasil.")
    end
end

--==================================================
-- SCAN BOOTH LISTINGS
--==================================================

local function scan()

    if scanInProgress then
        print("[Scanner] Scan masih berjalan, skip.")
        return
    end

    if SAFE_MODE and not canDoScan() then
        print("[Scanner] Anti-kick cooldown aktif, skip scan.")
        return
    end

    scanInProgress = true
    lastScanAt = os.clock()

    print(
        "======================================"
    )

    print(
        "[Scanner] Starting booth scan..."
    )

    print(
        "======================================"
    )

    --==================================================
    -- GET BOOTH DATA
    --==================================================

    local data =
        getLoadedBoothData()

    if not data then

        warn(
            "[Scanner] BoothListings returned nil."
        )

        serverHop()
        scanInProgress = false
        return
    end

    local loadedListingCount =
        countListings(data)

    local boothsByOwnerId = buildBoothIndex()

    if loadedListingCount == 0 then

        warn("[Scanner] Tidak ada booth yang termuat; memulai server hop.")

        serverHop()
        scanInProgress = false
        return
    end

    --==================================================
    -- RAW DUMP
    --==================================================

    if DEBUG
        and DUMP_RAW_DATA then

        print(
            "[Scanner] RAW BoothListings:"
        )

        print(
            dump(data)
        )
    end

    local count = 0
    local detectedCount = 0
    local seenListings = {}
    local groupedListings = {}

    --==================================================
    -- SCAN ALL BOOTHS
    --==================================================

    for ownerId, listings in pairs(data) do

        if typeof(listings) == "table" then

            for listingId, listing
                in pairs(listings) do

                count += 1

                local itemKey = listing and listing.ItemKey or listing and listing.itemKey or listing and listing.Key or listing and listing.key
                local itemType = listing and (listing.ItemType or listing.itemType or listing.Type or listing.type or listing.Category or listing.category)
                local price = listing and (listing.Price or listing.price)
                local listingSignature = tostring(ownerId) .. ":" .. tostring(listingId) .. ":" .. tostring(itemKey) .. ":" .. tostring(itemType) .. ":" .. tostring(price)

                if seenListings[listingSignature] then
                    continue
                end

                seenListings[listingSignature] = true

                local result =
                    inspectListing(
                        ownerId,
                        listingId,
                        listing,
                        boothsByOwnerId
                    )

                if result then

                    detectedCount += 1

--==================================================
-- AUTO-BUY (TAMBAHAN)
--==================================================

--==================================================
-- AUTO-BUY (verbose logging)
--==================================================
if AUTO_BUY_ENABLED then
    -- Lookup case-insensitive: coba itemName dulu, fallback ke rapKey
    local maxPrice
    if result.itemName then
        for listName, listPrice in pairs(AUTO_BUY_LIST) do
            if string.lower(listName) == string.lower(result.itemName) then
                maxPrice = listPrice
                break
            end
        end
    end
    if not maxPrice and result.rapKey then
        for listName, listPrice in pairs(AUTO_BUY_LIST) do
            if string.lower(listName) == string.lower(result.rapKey) then
                maxPrice = listPrice
                break
            end
        end
    end

    if maxPrice then
        print(string.format("[AUTO-BUY] 🎯 MATCH LIST: %s | price: %d | max: %d",
            result.itemName, result.price, maxPrice))
        local success = attemptPurchase(
            ownerId, listingId,
            result.itemName, result.price, maxPrice
        )
        if success then
            pcall(function()
                sendAutoBuyWebhook(
                    result.itemName, result.itemType, result.itemKey,
                    result.price, result.rap, result.profit, result.discount, ownerId
                )
            end)
        end
    end
end

                    groupedListings[ownerId] =
                        groupedListings[ownerId]
                        or {}

                    table.insert(
                        groupedListings[ownerId],
                        result
                    )
                end
            end
        end
    end

    --==================================================
    -- WEBHOOK PHASE
    --==================================================

    print(
        "======================================"
    )

    print(
        "[Webhook] Starting webhook phase..."
    )

    print(
        "[Webhook] Detected:",
        detectedCount
    )

    print(
        "======================================"
    )

    if ENABLE_SERVER_HOP then
        task.spawn(function()
            serverHop()
        end)
    end

        local webhookCount = 0

    for ownerId, listings
        in pairs(groupedListings) do

        for _, listing
            in ipairs(listings) do

            if SAFE_MODE and webhookCount >= SAFE_MAX_WEBHOOKS_PER_SCAN then
                break
            end

            --==========================================
            -- 1. NUKE (paling prioritas)
            --==========================================

            if listing.nuke then

                if SAFE_MODE and webhookCount >= SAFE_MAX_WEBHOOKS_PER_SCAN then
                    break
                end

                local sent =
                    sendWebhook(
                        "NUKE",
                        ownerId,
                        listing
                    )

                if sent then
                    webhookCount += 1
                end

                task.wait(
                    WEBHOOK_DELAY_SECONDS
                )
            end

            --==========================================
            -- 2. DEEP UNDERRAP (>= 50%)
            --==========================================

            if listing.deepUnderrap
                and not listing.nuke
                and not listing.boosted then

                if SAFE_MODE and webhookCount >= SAFE_MAX_WEBHOOKS_PER_SCAN then
                    break
                end

                local sent =
                    sendWebhook(
                        "DEEP_UNDERRAP",
                        ownerId,
                        listing
                    )

                if sent then
                    webhookCount += 1
                end

                task.wait(
                    WEBHOOK_DELAY_SECONDS
                )
            end

            --==========================================
            -- 3. NORMAL UNDERRAP (LOW / MID / HIGH / 100K+)
            --==========================================

            if listing.price < listing.rap
                and listing.discount >=
                    getUnderrapThreshold(
                        listing.tierName
                    )
                and not listing.boosted
                and not listing.nuke
                and not listing.deepUnderrap then

                local webhookType =
                    listing.tierName

                if SAFE_MODE and webhookCount >= SAFE_MAX_WEBHOOKS_PER_SCAN then
                    break
                end

                local sent =
                    sendWebhook(
                        webhookType,
                        ownerId,
                        listing
                    )

                if sent then
                    webhookCount += 1
                end

                task.wait(
                    WEBHOOK_DELAY_SECONDS
                )
            end

            --==========================================
            -- 4. BOOSTED (terakhir)
            --==========================================

            if listing.boosted then

                if SAFE_MODE and webhookCount >= SAFE_MAX_WEBHOOKS_PER_SCAN then
                    break
                end

                local sent =
                    sendWebhook(
                        "BOOSTED",
                        ownerId,
                        listing
                    )

                if sent then
                    webhookCount += 1
                end

                task.wait(
                    WEBHOOK_DELAY_SECONDS
                )
            end
        end
    end

    --==================================================
    -- SCAN SUMMARY
    --==================================================

    print(
        "======================================"
    )

    print(
        "[Scanner] Listings scanned:",
        count
    )

    print(
        "[Scanner] Underrap/special detected:",
        detectedCount
    )

    print(
        "[Webhook] Webhooks processed:",
        webhookCount
    )

    print(
        "======================================"
    )

    --==================================================
    -- SERVER HOP ONLY AFTER WEBHOOK
    --==================================================

    if ENABLE_SERVER_HOP then

        print(
            "[Scanner] Webhook phase selesai."
        )

        if SAFE_MODE then
            print(
                "[Scanner] Anti-kick mode aktif: hop dibatasi dan tidak spam."
            )
        end

        print(
            "[Scanner] Starting server hop..."
        )

        preparedServerId = nil
        serverHop()

    else

        print(
            "[Server Hop] Disabled."
        )
    end

    hopAttemptCount = 0
    scanInProgress = false
end

--==================================================
-- RUN
--==================================================

scan()
