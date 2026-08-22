--// Blade Ball Trade Plaza - Underrap Scanner
--// Revised:
--// 1. Emote name menggunakan ReplicatedStorage.Misc.Emotes -> Attribute "EmoteName"
--// 2. Sword image menggunakan ReplicatedInstances:GetInstance("Swords", itemKey)
--// 3. TextureID dari MeshPart/SpecialMesh dipakai sebagai thumbnail Discord
--// 4. Semua webhook dikirim SELESAI terlebih dahulu
--// 5. Setelah webhook selesai, scanner baru server hop
--// 6. Server hop memakai Roblox Public Server API
--// 7. Menangani TeleportInitFailed


local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

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

local DEBUG = true
local DUMP_RAW_DATA = false

local WEBHOOK_DELAY_SECONDS = 1
local BOOTH_LOAD_DELAY_SECONDS = 5
local BOOTH_LOAD_TIMEOUT_SECONDS = 20

local SERVER_HOP_DELAY_SECONDS = 5
local ENABLE_SERVER_HOP = true

--==================================================
-- WEBHOOKS
--==================================================
-- MASUKKAN WEBHOOK URL LU YANG SEBELUMNYA DI SINI

local WEBHOOKS = {
    LOW = "https://discord.com/api/webhooks/1540647799954214962/JelVlhOdjg12dmfULla0O0kWJ1r43uSzG8eIkf2U71Cyh0uhOCOnMk5MFnJ5CSNhgZrT",
    MID = "https://discord.com/api/webhooks/1540647796313563190/Z0S9wJiDmS3cGdsTNL95DFMCK7_rN3Smfw20R9Vgc_lHCs5HuBdlJUsCoMjBIg-IcyEN",
    HIGH = "https://discord.com/api/webhooks/1540647989230702623/cy2z0xRydhttYIdYvMh-5b9s9hEgFbzFXJEVnBvZv5SNj-BEoUUfKscO6anbi9QKQ03X",
    ["100K+"] = "https://discord.com/api/webhooks/1540648079580078131/XOvHGOidws-4kWf52JMg95z5a2-dnv50D5PnuP905CcbUgAZRPGi75l4eaXIOjs-zKN7",
    BOOSTED = "https://discord.com/api/webhooks/1540648162815905832/cfutqmGiZh6gFY_xeiAMDhEZI4at_1A1Tu34LU9Pa1dhMHPQ4ekMXKNqW6Qzq5Tu_14Q",
    NUKE = "https://discord.com/api/webhooks/1540648254482681937/LCmXm86xKbfp7uBhzgOC8PVlXZgE5RntgQwf4SgS7XUcKol94vVykCIxcGsr02Hufcn-",
    DEEP_UNDERRAP = "https://discord.com/api/webhooks/1540648345226317855/LmytFGDSP03UZwV_HCcZ8GIo6cZky3I_x3QJIqRiIs2-eJvJwYoyZxt9nG1Qz0imWL-R",
}

--==================================================
-- MANUAL BOOSTED LIST
--==================================================

local BOOSTED_ITEMS = {
    ["Coconut Failure"] = true,
    ["Sword of Order"] = true,
    ["Chroma Fortune Cleaver"] = true,
    ["Glacial Blade"] = true,
    ["Dual Axolotl Blade"] = true,
    ["Tidewither"] = true,
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
    ["Lightning Dagger"] = true,
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
    ["Gravelight"] = true,
    ["Mythical Enchanter"] = true,
    ["Proposal"] = true,
    ["Skeleton Dance"] = true,
    ["Skeleton Juggle"] = true,
    ["Weeping Angel"] = true,
    ["Wreath Shot"] = true,
    ["Zeus' Revenge"] = true,
    ["2025"] = true,
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
    ["Aquatic Greatsword"] = true,
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
    ["Chroma DJ Emote"] = true,
    ["Chrome Dracula Blade"] = true,
    ["Clockwork Blueblade"] = true,
    ["Cloud Sword"] = true,
    ["Coconut Crusher"] = true,
    ["Coral Greatsword"] = true,
    ["Corrupted Bow"] = true,
    ["Corrupted Frostblade"] = true,
    ["Crimson Katana"] = true,
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
    ["Wintery Greatblade"] = true,
    ["Wrapped Froststaff"] = true,
    ["Yuleflame"] = true,
    ["Zephyr Scythe"] = true,
    ["Blackhole Katana"] = true,
    ["Flower Katana"] = true,
    ["Stardust Katana"] = true,
    ["Stellar Blade"] = true,
    ["Souless Katana"] = true,
    ["Shadow Dagger"] = true,
}

local BOOSTED_TYPE_EXCLUSIONS = {
    Gravelight = {
        Sword = true,
    },
}

--==================================================
-- MANUAL NUKE LIST
--==================================================

local NUKE_ITEMS = {
    ["Cloud"] = 19500,
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

--==================================================
-- GET CONTROLLERS
--==================================================

local Controllers =
    ReplicatedStorage:WaitForChild("Controllers")

local Trading =
    Controllers:WaitForChild("Trading")

local BoothController =
    require(Controllers.Booth.BoothController)

local RAPController =
    require(Trading.RAPController)

--==================================================
-- REPLICATED INSTANCES
--==================================================

local ReplicatedInstances =
    require(
        ReplicatedStorage.Shared.ReplicatedInstances
    )

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

    local offset = spawn.CFrame:PointToObjectSpace(position)
    local horizontal = math.abs(offset.X) > 10
    local vertical = math.abs(offset.Z) > 10

    if not horizontal and not vertical then
        return string.format(
            "dekat spawn • %.0f studs",
            (position - spawn.Position).Magnitude
        )
    end

    local horizontalName = offset.X < 0 and "kiri" or "kanan"
    local verticalName = offset.Z < 0 and "depan" or "belakang"
    local direction

    if horizontal and vertical then
        direction = horizontalName .. "-" .. verticalName
    else
        direction = horizontal and horizontalName or verticalName
    end

    return string.format(
        "%s dari spawn • %.0f studs",
        direction,
        (position - spawn.Position).Magnitude
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

local function isBoosted(itemType, itemName)
    if not itemType or not itemName then
        return false
    end

    local excludedTypes =
        BOOSTED_TYPE_EXCLUSIONS[itemName]

    if excludedTypes
        and excludedTypes[itemType] then

        return false
    end

    return BOOSTED_ITEMS[itemName] == true
end

local function getNukeLimit(itemName)
    if not itemName then
        return nil
    end

    local limit =
        NUKE_ITEMS[itemName]

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
-- WEBHOOK
--==================================================

local function sendWebhook(
    webhookType,
    ownerId,
    listing
)

    local webhookUrl =
        WEBHOOKS[webhookType]

    if not webhookUrl
        or webhookUrl == ""
        or string.find(
            webhookUrl,
            "PASTE_"
        ) then

        warn(
            "[WEBHOOK] URL belum diisi:",
            webhookType
        )

        return false
    end

    if not REQUEST then

        warn(
            "[WEBHOOK] Request function tidak tersedia."
        )

        return false
    end

    local ownerInfo =
        getOwnerInfo(ownerId)

    local ownerAvatarUrl =
        getOwnerAvatarUrl(ownerId)

    local ownerProfileUrl =
        getOwnerProfileUrl(ownerId)

    local title =
        "🚨 UNDER VALUE ITEM DETECTED"

    if webhookType == "BOOSTED" then

        title =
            "⚡ BOOSTED ITEM DETECTED"

    elseif webhookType == "NUKE" then

        title =
            "☢️ NUKE ITEM DETECTED"

    elseif webhookType == "DEEP_UNDERRAP" then

        title =
            "🔥 50%+ UNDERRAP DETECTED"
    end

    local fields = {

        {
            name = "Seller",
            value =
                tostring(
                    ownerInfo.displayName
                ),
            inline = true,
        },

        {
            name = "Item",
            value = string.format(
                "`%s`",
                tostring(listing.itemName)
            ),
            inline = true,
        },

        {
            name = "Type",
            value = string.format(
                "`%s`",
                tostring(listing.itemType)
            ),
            inline = true,
        },

        {
            name = "RAP",
            value = string.format(
                "`%s`",
                tostring(listing.rap)
            ),
            inline = true,
        },

        {
            name = "Price",
            value = string.format(
                "`%s`",
                tostring(listing.price)
            ),
            inline = true,
        },
    }

    --==================================================
    -- NUKE
    --==================================================

    if webhookType == "NUKE" then

        table.insert(fields, {
            name = "Nuke Limit",
            value = string.format(
                "`%s`",
                tostring(
                    listing.nukeLimit or "N/A"
                )
            ),
            inline = true,
        })

        table.insert(fields, {
            name = "Profit",
            value = string.format(
                "`%s`",
                tostring(listing.profit)
            ),
            inline = true,
        })

    --==================================================
    -- BOOSTED
    --==================================================

    elseif webhookType == "BOOSTED" then

        table.insert(fields, {
            name = "Profit",
            value = string.format(
                "`%s`",
                tostring(listing.profit)
            ),
            inline = true,
        })

    --==================================================
    -- NORMAL / DEEP
    --==================================================

    else

        table.insert(fields, {
            name = "Profit",
            value = string.format(
                "`%s (%.0f%%)`",
                tostring(listing.profit),
                listing.discount
            ),
            inline = true,
        })
    end

    table.insert(fields, {
        name = "Booth Claimed",
        value = listing.boothClaimed
            and "✅ Sudah claim — listing masih aktif"
            or "❌ Belum claim",
        inline = false,
    })

    table.insert(fields, {
        name = "Booth Location",
        value = listing.boothLocation
            or "Lokasi tidak tersedia",
        inline = false,
    })

    --==================================================
    -- SERVER
    --==================================================

    table.insert(fields, {
        name = "Server Link",
        value = getServerLink(),
        inline = false,
    })

    --==================================================
    -- PROFILE
    --==================================================

    if ownerProfileUrl then

        table.insert(fields, {
            name = "Profile",
            value = ownerProfileUrl,
            inline = false,
        })
    end

    --==================================================
    -- IMAGE
    --==================================================

    local itemImageUrl =
        getItemImageUrl(
            listing.itemType,
            listing.itemKey
        )

    --==================================================
    -- PAYLOAD
    --==================================================

    local embed = {
        title = title,

        timestamp = DateTime.now():ToIsoDate(),

        color =
            getTierColor(
                webhookType
            ),

        fields = fields,

        footer = {
            text =
                "Type: "
                .. tostring(webhookType)
                .. " | Seller ID: "
                .. tostring(ownerId),
        },
    }

    --==================================================
    -- ADD SWORD IMAGE
    --==================================================

    if itemImageUrl then

        embed.thumbnail = {
            url = itemImageUrl,
        }

        if DEBUG then
            print(
                "[WEBHOOK IMAGE]",
                listing.itemName,
                itemImageUrl
            )
        end
    end

    local payload = {
        username =
            ownerInfo.displayName,

        avatar_url =
            ownerAvatarUrl,

        embeds = {
            embed
        },
    }

    local success, response =
        pcall(function()

            return REQUEST({
                Url = webhookUrl,

                Method = "POST",

                Headers = {
                    ["Content-Type"] =
                        "application/json",
                },

                Body =
                    HttpService:JSONEncode(
                        payload
                    ),
            })

        end)

    if not success then

        warn(
            "[WEBHOOK ERROR]",
            response
        )

        return false
    end

    if DEBUG then

        print(
            "[WEBHOOK SENT]",
            webhookType,
            ownerInfo.displayName,
            listing.itemName,
            itemImageUrl
                and "[IMAGE]"
                or "[NO IMAGE]"
        )
    end

    return true
end

--==================================================
-- LISTING PARSER
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

    local boosted =
        isBoosted(
            itemType,
            itemName
        )

    local nukeLimit =
        getNukeLimit(
            itemName
        )

    local isNuke =
        nukeLimit ~= nil
        and price <= nukeLimit

    local isUnderrap =
        price < rap
        and discount >=
            getUnderrapThreshold(
                tierName
            )

    local isDeepUnderrap =
        isUnderrap
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
        }
    end
end

--==================================================
-- SERVER API
--==================================================

local function getNewServer()

    if not REQUEST then
        warn("[SERVER HOP] Request function tidak tersedia.")
        return nil
    end

    local url = string.format(
        "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100",
        tostring(game.PlaceId)
    )

    local success, response = pcall(function()
        return REQUEST({
            Url = url,
            Method = "GET",
        })
    end)

    if not success then
        warn("[SERVER HOP ERROR]", response)
        return nil
    end

    if not response or not response.Body then
        warn("[SERVER HOP] Response kosong.")
        return nil
    end

    local decodeSuccess, data = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)

    if not decodeSuccess or not data then
        warn("[SERVER HOP] JSON decode gagal.")
        return nil
    end

    if not data.data then
        warn("[SERVER HOP] Server data tidak ditemukan.")
        return nil
    end

    local availableServers = {}

    for _, server in ipairs(data.data) do
        if server.id
            and server.id ~= game.JobId
            and server.playing
            and server.maxPlayers
            and server.playing < server.maxPlayers
        then
            table.insert(
                availableServers,
                server
            )
        end
    end

    if #availableServers == 0 then
        warn("[SERVER HOP] Tidak ada server lain tersedia.")
        return nil
    end

    -- Random server biasa
    local selected = availableServers[
        math.random(1, #availableServers)
    ]

    print(
        "[SERVER HOP] Target:",
        tostring(selected.id),
        "| Players:",
        tostring(selected.playing),
        "/",
        tostring(selected.maxPlayers)
    )

    return selected.id
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
    end
)

--==================================================
-- SERVER HOP
--==================================================

local function serverHop()

    if not ENABLE_SERVER_HOP then

        print(
            "[Server Hop] Disabled."
        )

        return
    end

    print(
        "======================================"
    )

    print(
        "[Server Hop] Semua webhook sudah dikirim."
    )

    print(
        "[Server Hop] Menunggu "
        .. tostring(
            SERVER_HOP_DELAY_SECONDS
        )
        .. " detik..."
    )

    print(
        "======================================"
    )

    task.wait(
        SERVER_HOP_DELAY_SECONDS
    )

    local serverId =
        getNewServer()

    if not serverId then

        warn(
            "[Server Hop] Tidak menemukan server baru."
        )

        return
    end

    print(
        "[Server Hop] Target:",
        serverId
    )

    local success, result =
        pcall(function()

            TeleportService:
                TeleportToPlaceInstance(
                    game.PlaceId,
                    serverId,
                    LocalPlayer
                )

        end)

    if not success then

        warn(
            "[Server Hop] Teleport gagal:",
            result
        )

    else

        print(
            "[Server Hop] Teleport request berhasil."
        )
    end
end

--==================================================
-- SCAN BOOTH LISTINGS
--==================================================

local function scan()

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
        return
    end

    local loadedListingCount =
        countListings(data)

    local boothsByOwnerId = buildBoothIndex()
    print("======================================")
print("[BOOTH INDEX] Claimed booths:")
print("======================================")

for ownerId, boothData in pairs(boothsByOwnerId) do
    print(
        "[CLAIMED]",
        "Owner:",
        tostring(ownerId),
        "| Booth:",
        boothData.booth
            and boothData.booth:GetFullName()
            or "nil"
    )
end

print("======================================")

    print(
        "[Scanner] Booth listings loaded:",
        loadedListingCount
    )
    print("======================================")
print("[LISTING -> BOOTH MATCH TEST]")
print("======================================")

for ownerId, listings in pairs(data) do

    local boothData =
        boothsByOwnerId[
            normalizeId(ownerId)
        ]

    print(
        "[OWNER]",
        tostring(ownerId),
        "| Booth:",
        boothData
            and boothData.booth
            and boothData.booth:GetFullName()
            or "NOT FOUND"
    )
end

print("======================================")

    if loadedListingCount == 0 then

        warn("[Scanner] Tidak ada booth yang termuat; memulai server hop.")

        serverHop()
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

    local groupedListings = {}

    --==================================================
    -- SCAN ALL BOOTHS
    --==================================================

    for ownerId, listings in pairs(data) do

        if typeof(listings) == "table" then

            for listingId, listing
                in pairs(listings) do

                count += 1

                local result =
                    inspectListing(
                        ownerId,
                        listingId,
                        listing,
                        boothsByOwnerId
                    )

                if result then

                    detectedCount += 1

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

    local webhookCount = 0

    for ownerId, listings
        in pairs(groupedListings) do

        for _, listing
            in ipairs(listings) do

            --==========================================
            -- NUKE
            --==========================================

            if listing.nuke then

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
            -- BOOSTED
            --==========================================

            if listing.boosted then

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

            --==========================================
            -- NORMAL UNDERRAP
            --==========================================

            if listing.price < listing.rap
                and listing.discount >=
                    getUnderrapThreshold(
                        listing.tierName
                    )
                and not listing.boosted
                and not listing.nuke then

                local webhookType

                if listing.deepUnderrap then

                    webhookType =
                        "DEEP_UNDERRAP"

                else

                    webhookType =
                        listing.tierName
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

        print(
            "[Scanner] Starting server hop..."
        )

        serverHop()

    else

        print(
            "[Server Hop] Disabled."
        )
    end
end

--==================================================
-- RUN
--==================================================


scan()
