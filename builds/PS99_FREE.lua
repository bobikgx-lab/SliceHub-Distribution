--!nocheck
--[[
    SliceHub PS99 MASTER
    Version: V0.1.1.4.1 Event Craft + Luck Automation

    First PS99 hub foundation:
      - Permanent core tab shell
      - Replaceable, error-isolated Event module
      - Runtime-confirmed Garden custom/event egg opener
      - Config persistence under SH/config/PS99/
      - Free/Premium gating bridge for later license integration
      - Pre-native Orbs: Create bridge for verified drop credit

    Runtime-confirmed Garden protocol:
        Network.Invoke("CustomEggs_Hatch", customEggUID, amount)

    Confirmed standalone result:
      - 12/12 successful requests
      - 40/40 confirmed pets
      - 0 rate limits
      - 0 errors
      - Stable computed cycle: 1.650 seconds

    Premium bridge for development:
        getgenv().SliceHubPS99Tier = "Premium"
    or:
        getgenv().SliceHubPS99Premium = true

    Garden Event v0.2 integrates the runtime-confirmed campaign loop:
      collect, plant, lanes, plots, upgrades, regrow, unit layouts, boss
      tracking, and custom eggs. Farm, normal Eggs, consumables, and rank
      rewards are now integrated into the permanent core.

    V0.1.1.3.2 makes Upgrade Machine automation fail-closed and selectable:
      only user-enabled Garden upgrades may be purchased.

    V0.1.1.4.1 adds scanner-confirmed Garden crafting and Event Luck:
      selected recipe auto-start/claim, and selected rarity 6-hour refill.
]]

local HUB_VERSION = "V0.1.1.4.1"
local CORE_VERSION = "0.1.6"
local EVENT_MODULE_VERSION = "Garden 0.3.1"
warn("[SliceHub PS99] BOOT START • V0.1.1.4.1 CRAFT + LUCK")
local MOTION_BUILD_MARKER = "GARDEN-CRAFT-LUCK-20260801-A"
local GAME_PLACE_ID = 8737899170

local RATE_LIMIT_TEXT = "You're doing that too quickly!"
local RATE_LIMIT_WAIT = 2.5
local MAX_RATE_LIMIT_RETRIES = 5
local MAX_HATCH_DISTANCE = 40
local EGG_REFRESH_INTERVAL = 2
local AUTOSAVE_INTERVAL = 5

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = nil -- capability-safe build: never access CoreGui directly
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

-- Every execution invalidates all older SliceHub workers immediately.
env.SliceHubPS99Generation = (tonumber(env.SliceHubPS99Generation) or 0) + 1

do
    local oldHub = env.SliceHubPS99

    -- Shut down exposed features individually first. This still works when an
    -- older build's full Unload function is partially broken.
    if type(oldHub) == "table" then
        pcall(oldHub.SetVisible, false)
        pcall(oldHub.SetAutoBestArea, false)
        pcall(oldHub.SetAutoTimedFreeGifts, false)
        pcall(oldHub.SetFarmFeature, "AutoFarm", false)
        pcall(oldHub.SetFarmFeature, "PlayerDamage", false)
        pcall(oldHub.SetFarmFeature, "CollectOrbs", false)
        pcall(oldHub.StopFarm, "re-executed")
        pcall(oldHub.StopNormalEggs, "re-executed")
        pcall(oldHub.SetAutoGoldPet, false)
        pcall(oldHub.SetAutoRainbowPet, false)
        pcall(oldHub.SetAutoInfiniteEgg, false)
        pcall(oldHub.SetAutoDisableIndexedEggs, false)
        pcall(oldHub.StopEventEggs)
        pcall(oldHub.StopGardenAutomation, false)

        -- Force engine tables dead before calling Unload, so stale task loops
        -- cannot continue even if a stop callback throws.
        local okState, state = pcall(oldHub.GetState)
        if okState and type(state) == "table" then
            for _, engineName in ipairs({
                "farm",
                "normalEggs",
                "automatic",
                "bestArea",
                "rankRewards",
                "timedFreeGifts",
            }) do
                local engine = state[engineName]
                if type(engine) == "table" then
                    engine.Alive = false
                    engine.Running = false
                    engine.Enabled = false
                    engine.AutoFarm = false
                    engine.PlayerDamage = false
                    engine.CollectOrbs = false
                    engine.AutoFruit = false
                    engine.AutoPotion = false
                    engine.AutoToys = false
                    engine.AutoUltimate = false
                    engine.AutoClaim = false
                    engine.WorkerToken = (tonumber(engine.WorkerToken) or 0) + 1
                end
            end
        end

        pcall(oldHub.Unload, "re-executed")
    end

    env.SliceHubPS99 = nil

    -- Remove every old SliceHub screen/button/card from both supported GUI
    -- roots. Harmless user preferences remain in the config file.
    pcall(function()
        if typeof(env.SliceHubPS99BootScreen) == "Instance" then
            env.SliceHubPS99BootScreen:Destroy()
        end
        env.SliceHubPS99BootScreen = nil

        local roots = {}
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            table.insert(roots, playerGui)
        end

        if type(gethui) == "function" then
            local okHui, hui = pcall(gethui)
            if okHui and typeof(hui) == "Instance" and hui ~= playerGui then
                table.insert(roots, hui)
            end
        end

        for _, root in ipairs(roots) do
            for _, child in ipairs(root:GetChildren()) do
                local name = string.lower(tostring(child.Name or ""))
                local marked = false
                pcall(function()
                    marked = child:GetAttribute("SliceHubBuild") ~= nil
                        or child:GetAttribute("SliceHubMarker") ~= nil
                end)

                if marked or string.find(name, "slicehub_ps99", 1, true) then
                    pcall(child.Destroy, child)
                end
            end
        end
    end)
end

--////////////////////////////////////////////////////////////////////
-- Utilities
--////////////////////////////////////////////////////////////////////

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function safeText(value, limit)
    local text = tostring(value == nil and "nil" or value)
    text = string.gsub(text, "[\r\n]+", " ")
    limit = limit or 500
    if #text > limit then
        text = string.sub(text, 1, limit) .. "...[truncated]"
    end
    return text
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function round(value, places)
    local multiplier = 10 ^ (places or 0)
    return math.floor(value * multiplier + 0.5) / multiplier
end

local function nowStamp()
    local ok, result = pcall(os.date, "!%Y%m%d_%H%M%S")
    if ok then
        return result
    end
    return tostring(math.floor(os.clock() * 1000))
end

local function formatCompactNumber(value)
    value = tonumber(value) or 0
    local absolute = math.abs(value)

    if absolute >= 1e12 then
        return string.format("%.2fT", value / 1e12)
    elseif absolute >= 1e9 then
        return string.format("%.2fB", value / 1e9)
    elseif absolute >= 1e6 then
        return string.format("%.2fM", value / 1e6)
    elseif absolute >= 1e3 then
        return string.format("%.2fK", value / 1e3)
    end

    return tostring(math.floor(value))
end

local function formatDistance(value)
    if value == math.huge or value == nil then
        return "unknown"
    end
    return string.format("%.1f", value)
end

local function requireModule(instance, label, optional)
    if not instance then
        if optional then
            return nil
        end
        error("[SliceHub PS99] Missing module: " .. tostring(label), 0)
    end

    local ok, result = pcall(require, instance)
    if ok then
        return result
    end

    if optional then
        warn("[SliceHub PS99] Optional module failed: " .. tostring(label) .. " | " .. tostring(result))
        return nil
    end

    error("[SliceHub PS99] Failed to require " .. tostring(label) .. ": " .. tostring(result), 0)
end

local function disconnectAll(connections)
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(connections)
end

--////////////////////////////////////////////////////////////////////
-- Tier bridge
--////////////////////////////////////////////////////////////////////

-- Build-time tier bridge. The universal bootstrap validates the key/HWID,
-- then the private runtime selected for this game supplies the correct tier.
local tierInput = "FREE"
local IS_PREMIUM = false
local USER_TIER = IS_PREMIUM and "Premium" or "Free"
local FREE_EVENT_HATCH_CAP = 3

--////////////////////////////////////////////////////////////////////
-- Files and config
--////////////////////////////////////////////////////////////////////

local ROOT = "SH"
local CONFIG_ROOT = ROOT .. "/config"
local CONFIG_FOLDER = CONFIG_ROOT .. "/PS99"
local CONFIG_PATH = CONFIG_FOLDER .. "/settings.json"

local LOG_ROOT = ROOT .. "/logs"
local LOG_FOLDER = LOG_ROOT .. "/PS99"
local SESSION = nowStamp() .. "_" .. tostring(LocalPlayer and LocalPlayer.UserId or 0)
local LOG_PATH = LOG_FOLDER .. "/SliceHubPS99_" .. SESSION .. ".txt"

local canWrite = type(writefile) == "function"
local canAppend = type(appendfile) == "function"

local function ensureFolder(path)
    if type(makefolder) ~= "function" then
        return
    end

    local exists = false
    if type(isfolder) == "function" then
        local ok, result = pcall(isfolder, path)
        exists = ok and result == true
    end

    if not exists then
        pcall(makefolder, path)
    end
end

if canWrite then
    ensureFolder(ROOT)
    ensureFolder(CONFIG_ROOT)
    ensureFolder(CONFIG_FOLDER)
    ensureFolder(LOG_ROOT)
    ensureFolder(LOG_FOLDER)
    pcall(writefile, LOG_PATH, "")
end

local DEFAULT_CONFIG = {
    selectedTab = "Home",
    farm = {
        enabled = false,
        autoTargetCount = true,
        targetCount = 3,
        petsPerTarget = 4,
        targetRadius = 2000,
        playerDamage = false,
        collectOrbs = false,
        infSpeedPets = false,
    },
    eggs = {
        mode = "Best Egg",
        selectedEggID = "",
        autoBuy = false,
        disableAnimation = false,

        goldSearch = "",
        goldSelectedPetID = "",
        autoGold = false,
        rainbowSearch = "",
        rainbowSelectedPetID = "",
        autoRainbow = false,
    },
    infiniteEggs = {
        selectedWorld = 1,
        amountMode = "Max",
        autoOpen = false,
        autoDisableIndexed = false,
    },
    automatic = {
        selectedFruitID = "",
        fruitAmount = 1,
        autoFruit = false,
        autoSqueakyToy = false,
        autoToyBall = false,
        selectedPotionID = "",
        selectedPotionTier = 1,
        autoPotion = false,

        -- Simple V0.1.0.5.5 controls.
        autoToys = false,
        autoUltimate = false,
        ultimateName = "Pet Surge",
        fruitSelection = {},
        potionSelection = {},
    },
    teleports = {
        autoBestArea = false,
    },
    main = {
        autoRankRewards = false,
        autoFreeGifts = false,
    },
    expansion = {
        autoLoginStreak = false,
        autoAreaRewards = false,
        autoForeverPack = false,
        autoDaycareClaim = false,
        autoDaycareEnroll = false,
        daycarePetSearch = "",
        daycareSelection = {},
        autoCombineKeys = false,
        autoBalloonGifts = false,
    },
    event = {
        selectedEggID = "",
        requestedAmount = 1,
        useMaximumEveryCycle = false,
        speedMode = "Stable",
        resumeAfterReconnect = false,

        crafting = {
            auto = false,
            selection = {},
        },
        luck = {
            auto = false,
            selection = {},
        },

        garden = {
            autoCollect = false,
            autoPlant = false,
            autoUnlockLanes = false,
            autoBuyPlots = false,
            autoUpgrades = false,
            upgradeSelection = {},
            autoRegrow = false,
            autoRestoreUnits = false,
            autoMerchant = false,
            autoReinforce = false,
            fullCampaign = false,
            missionDirector = false,
            autoSuperRebirth = false,

            selectedSeedUID = "",
            selectedSeedID = "",

            unitLayout = {},
            unitLayoutUserId = 0,

            lineTools = {
                selectedLine = 1,
                selectedUnitUID = "",
                selectedUnitID = "",
                quantity = 1,
                pattern = {},
                placeDelay = 0.12,
                autoFill = false,
            },
        },
    },
    settings = {
        debugLogging = false,
        rememberLastTab = true,
        compactUI = false,
        theme = "Mist Purple",
        windowWidth = 800,
        windowHeight = 520,
        windowPositionX = 0.5,
        windowPositionY = 0.5,
        togglePositionX = 0.92,
        togglePositionY = 0.5,
    },
}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local output = {}
    for key, child in pairs(value) do
        output[key] = deepCopy(child)
    end
    return output
end

local function mergeDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, defaultValue in pairs(defaults) do
        if type(defaultValue) == "table" then
            target[key] = mergeDefaults(target[key], defaultValue)
        elseif target[key] == nil then
            target[key] = defaultValue
        end
    end

    return target
end

local Config = deepCopy(DEFAULT_CONFIG)

local function loadConfig()
    if not canWrite or type(readfile) ~= "function" or type(isfile) ~= "function" then
        return
    end

    local okExists, exists = pcall(isfile, CONFIG_PATH)
    if not okExists or not exists then
        return
    end

    local okRead, raw = pcall(readfile, CONFIG_PATH)
    if not okRead or type(raw) ~= "string" then
        return
    end

    local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
    if okDecode and type(decoded) == "table" then
        Config = mergeDefaults(decoded, DEFAULT_CONFIG)
    end
end

local configDirty = false

local function markConfigDirty()
    configDirty = true
end

local function saveConfig(force)
    if not canWrite then
        return false
    end

    if not force and not configDirty then
        return true
    end

    local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, Config)
    if not okEncode then
        return false
    end

    local okWrite = pcall(writefile, CONFIG_PATH, encoded)
    if okWrite then
        configDirty = false
        return true
    end

    return false
end

loadConfig()

-- Keep old saved tab names compatible with the simple Event page.
if Config.selectedTab == "Teleports" then
    Config.selectedTab = "Farm"
elseif Config.selectedTab == "Garden"
    or Config.selectedTab == "GardenUnits"
    or Config.selectedTab == "EventEggs"
then
    Config.selectedTab = "Event"
end

-- Permanent automation toggles begin OFF on each execution.
-- Users enable each Farm feature independently from the Farm tab.
Config.farm.enabled = false
Config.farm.playerDamage = false
Config.farm.collectOrbs = false
Config.farm.infSpeedPets = false
Config.farm.autoTargetCount = true
Config.farm.targetRadius = 2000
Config.eggs.autoBuy = false
Config.eggs.disableAnimation = false
Config.eggs.autoGold = false
Config.eggs.autoRainbow = false
Config.infiniteEggs.autoOpen = false
Config.infiniteEggs.autoDisableIndexed = false
Config.teleports.autoBestArea = false
Config.main.autoRankRewards = false
Config.main.autoFreeGifts = false

Config.automatic.autoFruit = false
Config.automatic.autoSqueakyToy = false
Config.automatic.autoToyBall = false
Config.automatic.autoPotion = false
Config.automatic.autoToys = false
Config.automatic.autoUltimate = false

Config.expansion.autoLoginStreak = false
Config.expansion.autoAreaRewards = false
Config.expansion.autoForeverPack = false
Config.expansion.autoDaycareClaim = false
Config.expansion.autoDaycareEnroll = false
Config.expansion.autoCombineKeys = false
Config.expansion.autoBalloonGifts = false

Config.event.useMaximumEveryCycle = false
Config.event.resumeAfterReconnect = false
Config.event.crafting.auto = false
Config.event.luck.auto = false
Config.event.garden.autoCollect = false
Config.event.garden.autoPlant = false
Config.event.garden.autoUnlockLanes = false
Config.event.garden.autoBuyPlots = false
Config.event.garden.autoUpgrades = false
Config.event.garden.autoRegrow = false
Config.event.garden.autoRestoreUnits = false
Config.event.garden.autoMerchant = false
Config.event.garden.autoReinforce = false
Config.event.garden.fullCampaign = false
Config.event.garden.missionDirector = false
Config.event.garden.autoSuperRebirth = false
Config.event.garden.lineTools.autoFill = false
markConfigDirty()

if not IS_PREMIUM then
    Config.event.useMaximumEveryCycle = false
    Config.event.speedMode = "Stable"
    Config.event.resumeAfterReconnect = false
    Config.event.crafting.auto = false
    Config.event.luck.auto = false

    Config.event.garden.autoUnlockLanes = false
    Config.event.garden.autoBuyPlots = false
    Config.event.garden.autoUpgrades = false
    Config.event.garden.autoRegrow = false
    Config.event.garden.autoRestoreUnits = false
    Config.event.garden.fullCampaign = false
    Config.event.garden.missionDirector = false
    Config.event.garden.autoSuperRebirth = false
end

local startedAt = os.clock()

local function appendLog(kind, message)
    local line = string.format(
        "[%08.3f] %-14s %s\n",
        os.clock() - startedAt,
        tostring(kind),
        safeText(message)
    )

    if Config.settings.debugLogging then
        print("[SliceHub PS99][" .. tostring(kind) .. "] " .. safeText(message))
    end

    if canWrite then
        if canAppend then
            pcall(appendfile, LOG_PATH, line)
        else
            local old = ""
            if type(readfile) == "function" and type(isfile) == "function" then
                local okExists, exists = pcall(isfile, LOG_PATH)
                if okExists and exists then
                    pcall(function()
                        old = readfile(LOG_PATH)
                    end)
                end
            end
            pcall(writefile, LOG_PATH, old .. line)
        end
    end
end

appendLog("BOOT", "SliceHub PS99 " .. HUB_VERSION .. " | tier=" .. USER_TIER)

--////////////////////////////////////////////////////////////////////
-- Runtime and game modules
--////////////////////////////////////////////////////////////////////

local Runtime = {
    Alive = true,
    Generation = env.SliceHubPS99Generation,
    Connections = {},
    SelectedTab = Config.settings.rememberLastTab and Config.selectedTab or "Home",
    EventFault = nil,
    LastNotice = nil,
    GUIVisible = true,

    UIAnimating = false,
    UIMotionToken = 0,
    UIRestPosition = nil,
    UITargetScale = 1,
}

local Library = ReplicatedStorage:WaitForChild("Library", 30)
if not Library then
    error("[SliceHub PS99] ReplicatedStorage.Library was not found.", 0)
end

local Client = Library:WaitForChild("Client", 30)
if not Client then
    error("[SliceHub PS99] Library.Client was not found.", 0)
end

local Network = requireModule(Client:WaitForChild("Network", 30), "Client.Network")
local CustomEggsCmds = requireModule(Client:WaitForChild("CustomEggsCmds", 30), "Client.CustomEggsCmds")
local EggCmds = requireModule(Client:WaitForChild("EggCmds", 30), "Client.EggCmds")
local CurrencyCmds = requireModule(Client:FindFirstChild("CurrencyCmds"), "Client.CurrencyCmds", true)
local HatchingCmds = requireModule(Client:FindFirstChild("HatchingCmds"), "Client.HatchingCmds", true)
local TradingPlazaCmds = requireModule(
    Client:FindFirstChild("TradingPlazaCmds"),
    "Client.TradingPlazaCmds",
    true
)

local Modules = Library:FindFirstChild("Modules")
local DirectoryFolder = Library:FindFirstChild("Directory")
local PlaceFile = requireModule(
    Modules and Modules:FindFirstChild("PlaceFile"),
    "Modules.PlaceFile",
    true
)
local WorldsDirectory = requireModule(
    DirectoryFolder and DirectoryFolder:FindFirstChild("Worlds"),
    "Directory.Worlds",
    true
)

local Save = requireModule(
    Client:FindFirstChild("Save"),
    "Client.Save",
    true
)
local EventUpgradeCmds = requireModule(
    Client:FindFirstChild("EventUpgradeCmds"),
    "Client.EventUpgradeCmds",
    true
)
local ClientFFlags = requireModule(
    Client:FindFirstChild("FFlags"),
    "Client.FFlags",
    true
)

local PlotCmdsFolder = Client:FindFirstChild("PlotCmds")
local ClientPlot = requireModule(
    PlotCmdsFolder and PlotCmdsFolder:FindFirstChild("ClientPlot"),
    "Client.PlotCmds.ClientPlot",
    true
)

local PvCombatCmdsFolder = Client:FindFirstChild("PvCombatCmds")
local ClientTowerDefenseFolder = PvCombatCmdsFolder
    and PvCombatCmdsFolder:FindFirstChild("ClientTowerDefense")
local ClientTowerDefense = requireModule(
    ClientTowerDefenseFolder,
    "Client.PvCombatCmds.ClientTowerDefense",
    true
)
local EntityRegistryFolder = ClientTowerDefenseFolder
    and ClientTowerDefenseFolder:FindFirstChild("EntityRegistry")
local ClientTower = requireModule(
    EntityRegistryFolder and EntityRegistryFolder:FindFirstChild("ClientTower"),
    "ClientTowerDefense.EntityRegistry.ClientTower",
    true
)

local ItemsFolder = Library:FindFirstChild("Items")
local CropSeedItem = requireModule(
    ItemsFolder and ItemsFolder:FindFirstChild("CropSeedItem"),
    "Items.CropSeedItem",
    true
)

local UtilFolder = Library:FindFirstChild("Util")
local GardenPlots = requireModule(
    UtilFolder and UtilFolder:FindFirstChild("GardenPlots"),
    "Util.GardenPlots",
    true
)

local EventUpgradesDirectory = requireModule(
    DirectoryFolder and DirectoryFolder:FindFirstChild("EventUpgrades"),
    "Directory.EventUpgrades",
    true
)

local Balancing = Library:FindFirstChild("Balancing")
local CalcEggPricePlayer = nil
if Balancing then
    CalcEggPricePlayer = requireModule(
        Balancing:FindFirstChild("CalcEggPricePlayer"),
        "Balancing.CalcEggPricePlayer",
        true
    )
end

--////////////////////////////////////////////////////////////////////
-- UI forward declarations
--////////////////////////////////////////////////////////////////////

local UI = {
    Screen = nil,
    Main = nil,
    MainScale = nil,
    ToggleButton = nil,
    ToggleScale = nil,
    Pages = {},
    TabButtons = {},
    NoticeLabel = nil,
    TierLabel = nil,
    ResizeHandle = nil,
    Teleports = {},
    Farm = {},
    NormalEggs = {},
    Machines = {},
    InfiniteEggs = {},
    Automatic = {},
    Rank = {},
    Rewards = {},
    Utilities = {},
    Event = {},
    Settings = {},
}

local function setNotice(text, level)
    Runtime.LastNotice = tostring(text or "")

    if UI.NoticeLabel and UI.NoticeLabel.Parent then
        local targetColor
        local visibleText = Runtime.LastNotice

        visibleText = visibleText:gsub(
            "Premium Garden campaign enabled%..*",
            "Auto Everything is on."
        )

        if #visibleText > 96 then
            visibleText = string.sub(visibleText, 1, 93) .. "..."
        end

        if level == "error" then
            targetColor = Color3.fromRGB(255, 160, 160)
        elseif level == "success" then
            targetColor = Color3.fromRGB(165, 245, 190)
        elseif level == "premium" then
            targetColor = Color3.fromRGB(255, 221, 125)
        else
            targetColor = Color3.fromRGB(202, 211, 224)
        end

        UI.NoticeLabel.Text = visibleText
        UI.NoticeLabel.TextColor3 = targetColor
        UI.NoticeLabel.TextTransparency = 0.42

        pcall(function()
            TweenService:Create(
                UI.NoticeLabel,
                TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                {TextTransparency = 0}
            ):Play()
        end)
    end

    appendLog(string.upper(level or "INFO"), text)
end

local function requirePremium(featureName)
    if IS_PREMIUM then
        return true
    end

    setNotice(
        tostring(featureName or "This feature") .. " is Premium. Current build tier: Free.",
        "premium"
    )
    return false
end

--////////////////////////////////////////////////////////////////////
-- Teleport controller
--////////////////////////////////////////////////////////////////////

local TeleportRuntime = {
    Busy = false,
    LastTarget = nil,
}

local function clearTeleportBusyLater(delaySeconds)
    task.delay(delaySeconds or 8, function()
        if Runtime.Alive then
            TeleportRuntime.Busy = false
        end
    end)
end

local function stopAutomationForTeleport()
    -- The egg engine is defined later. Resolve it through the public environment
    -- only when available; this avoids a forward-local dependency.
    local hub = env.SliceHubPS99
    if type(hub) == "table" then
        if type(hub.StopEventEggs) == "function" then
            pcall(hub.StopEventEggs)
        end
        if type(hub.StopGardenAutomation) == "function" then
            pcall(hub.StopGardenAutomation, true)
        end
        if type(hub.StopFarm) == "function" then
            pcall(hub.StopFarm, "Teleporting")
        end
        if type(hub.StopNormalEggs) == "function" then
            pcall(hub.StopNormalEggs, "Teleporting")
        end
    end
end

local function beginTeleport(label)
    if TeleportRuntime.Busy then
        setNotice(
            "A teleport is already being requested. Wait a moment before trying again.",
            "error"
        )
        return false
    end

    TeleportRuntime.Busy = true
    TeleportRuntime.LastTarget = tostring(label)
    stopAutomationForTeleport()
    saveConfig(true)

    setNotice("Teleporting to " .. tostring(label) .. "...", "success")
    appendLog("TELEPORT_START", tostring(label))
    return true
end

local function failTeleport(label, reason)
    TeleportRuntime.Busy = false
    setNotice(
        "Teleport to " .. tostring(label) .. " failed: " .. safeText(reason),
        "error"
    )
    appendLog(
        "TELEPORT_FAIL",
        tostring(label) .. " | " .. safeText(reason)
    )
end

local function teleportToPlace(placeId, label)
    placeId = tonumber(placeId)
    label = tostring(label or "destination")

    if not placeId or placeId <= 0 or placeId == math.huge then
        setNotice("No valid place ID is available for " .. label .. ".", "error")
        return
    end

    if game.PlaceId == placeId then
        setNotice("You are already in " .. label .. ".", "info")
        return
    end

    if not beginTeleport(label) then
        return
    end

    task.spawn(function()
        local ok, result = pcall(
            TeleportService.Teleport,
            TeleportService,
            placeId,
            LocalPlayer
        )

        if not ok then
            failTeleport(label, result)
            return
        end

        clearTeleportBusyLater(10)
    end)
end

local function getWorldEntries()
    local entries = {}

    if type(WorldsDirectory) == "table" then
        for key, world in pairs(WorldsDirectory) do
            if type(world) == "table" then
                local number = tonumber(
                    rawget(world, "WorldNumber")
                    or string.match(tostring(key), "%d+")
                )
                local placeId = tonumber(rawget(world, "PlaceId"))

                if number and placeId and placeId > 0 and placeId ~= math.huge then
                    table.insert(entries, {
                        Name = tostring(key),
                        WorldNumber = number,
                        PlaceId = placeId,
                    })
                end
            end
        end
    end

    if #entries == 0 and type(PlaceFile) == "table"
        and type(PlaceFile.LocalPlaces) == "table"
    then
        for worldNumber = 1, 10 do
            local key = "World" .. tostring(worldNumber)
            local placeId = tonumber(PlaceFile.LocalPlaces[key])
            if placeId and placeId > 0 and placeId ~= math.huge then
                table.insert(entries, {
                    Name = "World " .. tostring(worldNumber),
                    WorldNumber = worldNumber,
                    PlaceId = placeId,
                })
            end
        end
    end

    table.sort(entries, function(left, right)
        return left.WorldNumber < right.WorldNumber
    end)

    return entries
end

function TeleportRuntime.teleportToBestWorld()
    local entries = getWorldEntries()
    local best = entries[#entries]

    if not best then
        setNotice("PS99 did not expose a best-world destination.", "error")
        return
    end

    if game.PlaceId == best.PlaceId then
        setNotice("You are already in " .. best.Name .. ".", "info")
        return
    end

    teleportToPlace(best.PlaceId, "Best World • " .. best.Name)
end

local function tradingPlaceId(pro)
    if type(PlaceFile) ~= "table" or type(PlaceFile.LocalPlaces) ~= "table" then
        return nil
    end

    return tonumber(
        PlaceFile.LocalPlaces[pro and "ProTrading" or "Trading"]
    )
end

local function canAccessTradingPlace(placeId)
    if not TradingPlazaCmds or type(TradingPlazaCmds.GetAvailable) ~= "function" then
        return true
    end

    local ok, available = pcall(TradingPlazaCmds.GetAvailable)
    if not ok or type(available) ~= "table" then
        return true
    end

    for _, option in ipairs(available) do
        if type(option) == "table" and tonumber(option.PlaceId) == tonumber(placeId) then
            return true
        end
    end

    return false
end

local function teleportToTradingPlaza(pro)
    local label = pro and "Pro Trading Plaza" or "Trading Plaza"
    local placeId = tradingPlaceId(pro)

    if not placeId then
        setNotice("PS99 did not expose a valid " .. label .. " place ID.", "error")
        return
    end

    if game.PlaceId == placeId then
        setNotice("You are already in " .. label .. ".", "info")
        return
    end

    if not canAccessTradingPlace(placeId) then
        setNotice(
            pro
                and "Pro Trading Plaza is locked on this account."
                or "Trading Plaza is locked. Unlock the Happy Castle and rebirth first.",
            "error"
        )
        return
    end

    if TradingPlazaCmds
        and type(TradingPlazaCmds.RequestTradingPlaza) == "function"
    then
        if not beginTeleport(label) then
            return
        end

        task.spawn(function()
            local ok, result = pcall(
                TradingPlazaCmds.RequestTradingPlaza,
                placeId
            )

            if not ok then
                failTeleport(label, result)
                return
            end

            clearTeleportBusyLater(10)
        end)
        return
    end

    teleportToPlace(placeId, label)
end

TeleportService.TeleportInitFailed:Connect(function(player, result, message)
    if player ~= LocalPlayer or not TeleportRuntime.Busy then
        return
    end

    failTeleport(
        TeleportRuntime.LastTarget or "destination",
        tostring(message or result or "TeleportInitFailed")
    )
end)

--////////////////////////////////////////////////////////////////////
-- Runtime-confirmed custom egg engine
--////////////////////////////////////////////////////////////////////

local EggEngine = {
    Alive = true,
    Running = false,
    Busy = false,
    WorkerToken = 0,
    Connections = {},

    Eggs = {},
    SelectedIndex = 0,
    SelectedUID = nil,
    SelectedID = Config.event.selectedEggID ~= "" and Config.event.selectedEggID or nil,

    RequestedAmount = math.max(1, math.floor(tonumber(Config.event.requestedAmount) or 1)),
    UseMaximumEveryCycle = IS_PREMIUM and Config.event.useMaximumEveryCycle == true,
    SpeedMode = IS_PREMIUM and Config.event.speedMode or "Stable",
    ResumeAfterReconnect = IS_PREMIUM and Config.event.resumeAfterReconnect == true,

    RawDebounce = 1.625,
    StableDelay = 1.650,
    CurrentDelay = 1.650,

    Requests = 0,
    SuccessfulRequests = 0,
    RequestedEggs = 0,
    ConfirmedEggs = 0,
    RateLimits = 0,
    Errors = 0,
    ConsecutiveSuccesses = 0,

    LastError = nil,
    LastServerMessage = nil,
    RecentPets = {},
    PetCounts = {},
    DisableAnimation = Config.eggs.disableAnimation == true,
    SuppressedAnimationConnections = {},
    ResultConnection = nil,
}

do
    local ok, value = pcall(function()
        return EggCmds.ComputeDebounce()
    end)

    if ok and type(value) == "number" and value > 0 then
        EggEngine.RawDebounce = clamp(value, 0.25, 8)
        EggEngine.StableDelay = clamp(value + 0.025, 0.25, 8)
    end

    if EggEngine.SpeedMode == "Fast" and IS_PREMIUM then
        EggEngine.CurrentDelay = EggEngine.RawDebounce
    else
        EggEngine.SpeedMode = "Stable"
        EggEngine.CurrentDelay = EggEngine.StableDelay
    end
end

local function getRootPart()
    local character = LocalPlayer and LocalPlayer.Character
    if not character then
        return nil
    end
    return character:FindFirstChild("HumanoidRootPart")
end

local function getEggDirectory(egg)
    local ok, result = pcall(function()
        return egg:Directory()
    end)
    if ok and type(result) == "table" then
        return result
    end

    if type(egg) == "table" then
        return rawget(egg, "_dir")
    end

    return nil
end

local function getEggPosition(egg)
    local ok, result = pcall(function()
        return egg:GetPosition()
    end)
    if ok and typeof(result) == "Vector3" then
        return result
    end

    if type(egg) == "table" then
        local position = rawget(egg, "_position")
        if typeof(position) == "Vector3" then
            return position
        end
    end

    local okModel, model = pcall(function()
        return egg:GetModel()
    end)
    if okModel and typeof(model) == "Instance" then
        local okPivot, pivot = pcall(model.GetPivot, model)
        if okPivot and pivot then
            return pivot.Position
        end
    end

    return nil
end

local function getEggDistance(egg)
    local root = getRootPart()
    local position = getEggPosition(egg)
    if not root or not position then
        return math.huge
    end
    return (root.Position - position).Magnitude
end

local function isEggHatchable(egg)
    local ok, result = pcall(function()
        return egg:IsHatchable()
    end)
    if ok then
        return result == true
    end

    if type(egg) == "table" then
        return rawget(egg, "_hatchable") == true
    end

    return false
end

local function getEggUID(egg, fallback)
    -- Preserve the exact runtime UID type. Some custom eggs use a numeric
    -- network UID, and converting it to text makes the server reject hatches.
    if type(egg) == "table" then
        local uid = rawget(egg, "_uid")
        if uid ~= nil then
            return uid
        end
    end
    return fallback
end

local function getEggID(egg, directory)
    if type(egg) == "table" then
        local id = rawget(egg, "_id")
        if type(id) == "string" and id ~= "" then
            return id
        end
    end

    if type(directory) == "table" then
        local id = rawget(directory, "_id") or rawget(directory, "id")
        if type(id) == "string" and id ~= "" then
            return id
        end
    end

    return "Unknown Custom Egg"
end

local function getEggName(egg, directory, id)
    local ok, title = pcall(function()
        return egg:GetTitle()
    end)
    if ok and type(title) == "string" and title ~= "" then
        return title
    end

    if type(egg) == "table" then
        local title = rawget(egg, "_title")
        if type(title) == "string" and title ~= "" then
            return title
        end
    end

    if type(directory) == "table" then
        local name = rawget(directory, "name")
        if type(name) == "string" and name ~= "" then
            return name
        end
    end

    return id
end

local function getEggMaximum(egg)
    local ok, result = pcall(function()
        return egg:GetMaxEggCount()
    end)

    if ok and type(result) == "number" and result >= 1 then
        return math.max(1, math.floor(result))
    end

    if type(egg) == "table" then
        local maximum = rawget(egg, "_maxEggCount")
        if type(maximum) == "number" and maximum >= 1 then
            return math.max(1, math.floor(maximum))
        end
    end

    local okGlobal, globalMaximum = pcall(function()
        return EggCmds.GetMaxHatch()
    end)

    if okGlobal and type(globalMaximum) == "number" and globalMaximum >= 1 then
        return math.max(1, math.floor(globalMaximum))
    end

    return 1
end

local function getAffordability(entry)
    if not entry or not entry.Egg or type(entry.Directory) ~= "table" then
        return nil, nil, nil
    end

    local currency = rawget(entry.Directory, "currency")
    if currency == nil or not CurrencyCmds or not CalcEggPricePlayer then
        return nil, nil, currency
    end

    local allowChargedAndGolden = false
    if type(entry.Egg) == "table" then
        allowChargedAndGolden = rawget(entry.Egg, "_allowChargedAndGolden") == true
    end

    local okPrice, price = pcall(
        CalcEggPricePlayer,
        entry.Directory,
        nil,
        not allowChargedAndGolden
    )

    if not okPrice or type(price) ~= "number" or price <= 0 then
        return nil, nil, currency
    end

    local okOwned, owned = pcall(CurrencyCmds.Get, currency)
    if not okOwned or type(owned) ~= "number" then
        return nil, price, currency
    end

    return math.max(0, math.floor(owned / price)), price, currency
end

local function buildEggEntry(uid, egg)
    local directory = getEggDirectory(egg)
    local eggUID = getEggUID(egg, uid)
    local eggID = getEggID(egg, directory)

    return {
        UID = eggUID,
        ID = eggID,
        Name = getEggName(egg, directory, eggID),
        Egg = egg,
        Directory = directory,
        Hatchable = isEggHatchable(egg),
        Distance = getEggDistance(egg),
        Maximum = getEggMaximum(egg),
    }
end

local function selectedEgg()
    if EggEngine.SelectedIndex < 1 or EggEngine.SelectedIndex > #EggEngine.Eggs then
        return nil
    end
    return EggEngine.Eggs[EggEngine.SelectedIndex]
end

local function findEggByUID(uid)
    if uid == nil then
        return nil, nil
    end

    for index, entry in ipairs(EggEngine.Eggs) do
        if entry.UID == uid then
            return entry, index
        end
    end

    return nil, nil
end

local function findEggByID(id)
    if id == nil then
        return nil, nil
    end

    local best = nil
    local bestIndex = nil

    for index, entry in ipairs(EggEngine.Eggs) do
        if entry.ID == id then
            if not best or entry.Distance < best.Distance then
                best = entry
                bestIndex = index
            end
        end
    end

    return best, bestIndex
end

local function setSelectedEntry(entry, index)
    if not entry or not index then
        EggEngine.SelectedIndex = 0
        EggEngine.SelectedUID = nil
        return
    end

    EggEngine.SelectedIndex = index
    EggEngine.SelectedUID = entry.UID
    EggEngine.SelectedID = entry.ID

    Config.event.selectedEggID = entry.ID
    Config.event.requestedAmount = EggEngine.RequestedAmount
    markConfigDirty()
end

local refreshEventUI

local function refreshEggs(reason)
    local oldUID = EggEngine.SelectedUID
    local oldID = EggEngine.SelectedID
    local entries = {}

    local ok, allEggs = pcall(CustomEggsCmds.All)
    if not ok or type(allEggs) ~= "table" then
        EggEngine.Eggs = {}
        EggEngine.SelectedIndex = 0
        EggEngine.SelectedUID = nil

        if reason then
            appendLog("EGG_REFRESH", "Failed: " .. tostring(reason))
        end

        if refreshEventUI then
            refreshEventUI()
        end
        return false
    end

    for uid, egg in pairs(allEggs) do
        if type(egg) == "table" then
            local okEntry, entry = pcall(buildEggEntry, uid, egg)
            if okEntry and entry then
                table.insert(entries, entry)
            end
        end
    end

    table.sort(entries, function(left, right)
        if left.Hatchable ~= right.Hatchable then
            return left.Hatchable
        end
        if left.Distance ~= right.Distance then
            return left.Distance < right.Distance
        end
        if left.Name ~= right.Name then
            return left.Name < right.Name
        end
        return tostring(left.UID) < tostring(right.UID)
    end)

    EggEngine.Eggs = entries

    local entry, index = findEggByUID(oldUID)
    if not entry then
        entry, index = findEggByID(oldID)
    end
    if not entry then
        entry, index = findEggByID(Config.event.selectedEggID)
    end

    if entry then
        setSelectedEntry(entry, index)
    elseif #entries > 0 then
        setSelectedEntry(entries[1], 1)
    else
        EggEngine.SelectedIndex = 0
        EggEngine.SelectedUID = nil
    end

    local current = selectedEgg()
    if current then
        EggEngine.RequestedAmount = math.floor(
            clamp(EggEngine.RequestedAmount, 1, current.Maximum)
        )
    end

    if reason then
        appendLog("EGG_REFRESH", tostring(reason) .. " | eggs=" .. tostring(#entries))
    end

    if refreshEventUI then
        refreshEventUI()
    end

    return #entries > 0
end

local function chooseNearestHatchable()
    local best = nil
    local bestIndex = nil

    for index, entry in ipairs(EggEngine.Eggs) do
        entry.Hatchable = isEggHatchable(entry.Egg)
        entry.Distance = getEggDistance(entry.Egg)

        if entry.Hatchable and (not best or entry.Distance < best.Distance) then
            best = entry
            bestIndex = index
        end
    end

    if best then
        setSelectedEntry(best, bestIndex)
        EggEngine.RequestedAmount = math.floor(
            clamp(EggEngine.RequestedAmount, 1, best.Maximum)
        )
        setNotice("Selected nearest hatchable egg: " .. best.Name, "success")
    else
        setNotice("No hatchable custom/event egg is currently loaded.", "error")
    end

    if refreshEventUI then
        refreshEventUI()
    end
end

local function cycleEggSelection(direction)
    if #EggEngine.Eggs == 0 then
        refreshEggs("selection refresh")
        return
    end

    local index = EggEngine.SelectedIndex + direction
    if index < 1 then
        index = #EggEngine.Eggs
    elseif index > #EggEngine.Eggs then
        index = 1
    end

    local entry = EggEngine.Eggs[index]
    setSelectedEntry(entry, index)
    EggEngine.RequestedAmount = math.floor(
        clamp(EggEngine.RequestedAmount, 1, entry.Maximum)
    )

    setNotice("Selected: " .. entry.Name, "info")

    if refreshEventUI then
        refreshEventUI()
    end
end

local function effectiveAmount(entry)
    local maximum = getEggMaximum(entry.Egg)
    local amount

    if EggEngine.UseMaximumEveryCycle and IS_PREMIUM then
        amount = maximum
    else
        if not IS_PREMIUM then
            maximum = math.min(maximum, FREE_EVENT_HATCH_CAP)
        end
        amount = math.floor(clamp(EggEngine.RequestedAmount, 1, maximum))
    end

    local affordable = getAffordability(entry)
    if affordable ~= nil then
        if affordable <= 0 then
            return 0, "You cannot currently afford one hatch."
        end
        amount = math.min(amount, affordable)
    end

    return amount, nil
end

local function isRateLimit(message)
    return string.find(lower(message), lower(RATE_LIMIT_TEXT), 1, true) ~= nil
end

local function isCurrencyFailure(message)
    local text = lower(message)
    local terms = {
        "cannot afford",
        "can't afford",
        "not enough",
        "need more",
        "insufficient",
    }

    for _, term in ipairs(terms) do
        if string.find(text, term, 1, true) then
            return true
        end
    end

    return false
end

local function isEggFailure(message)
    local text = lower(message)
    local terms = {
        "invalid egg",
        "egg not found",
        "not hatchable",
        "too far",
        "distance",
        "unavailable",
        "does not exist",
        "doesn't exist",
    }

    for _, term in ipairs(terms) do
        if string.find(text, term, 1, true) then
            return true
        end
    end

    return false
end

local function waitInterruptible(duration, token)
    local deadline = os.clock() + math.max(0, duration)

    while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
        and EggEngine.Alive
        and EggEngine.Running
        and EggEngine.WorkerToken == token
        and os.clock() < deadline
    do
        task.wait(math.min(0.1, math.max(0.01, deadline - os.clock())))
    end

    return Runtime.Alive
        and EggEngine.Alive
        and EggEngine.Running
        and EggEngine.WorkerToken == token
end

local function resolveSelectedEgg()
    local entry = selectedEgg()

    if entry then
        local ok, live = pcall(CustomEggsCmds.Get, entry.UID)
        if ok and live == entry.Egg then
            return entry
        end
    end

    refreshEggs("selected egg changed")

    entry = selectedEgg()
    if entry and entry.ID == EggEngine.SelectedID then
        return entry
    end

    local replacement = findEggByID(EggEngine.SelectedID)
    return replacement or entry
end

local function stopEggEngine(reason, level)
    local wasRunning = EggEngine.Running or EggEngine.Busy

    EggEngine.Running = false
    EggEngine.Busy = false
    EggEngine.WorkerToken = EggEngine.WorkerToken + 1

    -- Clear PS99's native hatching state too. The previous direct-only loop
    -- could leave the client saying it was opening while no hatch was active.
    if HatchingCmds and type(HatchingCmds.StopHatching) == "function" then
        pcall(HatchingCmds.StopHatching)
    end

    if reason then
        setNotice(reason, level or "info")
    end

    if wasRunning then
        appendLog("EGG_STOP", reason or "Stopped")
    end

    if refreshEventUI then
        refreshEventUI()
    end
end

local function invokeHatch(entry, amount, token)
    local attempts = 0

    while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
        and EggEngine.Alive
        and EggEngine.Running
        and EggEngine.WorkerToken == token
    do
        attempts = attempts + 1
        EggEngine.Requests = EggEngine.Requests + 1
        EggEngine.Busy = true

        local requestStarted = os.clock()
        local okCall, success, message = pcall(
            Network.Invoke,
            "CustomEggs_Hatch",
            entry.UID,
            amount
        )
        local latency = os.clock() - requestStarted
        EggEngine.Busy = false

        if not okCall then
            EggEngine.Errors = EggEngine.Errors + 1
            EggEngine.LastError = tostring(success)
            return false, "Event egg request failed.", requestStarted
        end

        EggEngine.LastServerMessage = message
        appendLog(
            "EGG_INVOKE",
            string.format(
                "egg=%s amount=%d success=%s latency=%.3fs",
                entry.Name,
                amount,
                tostring(success),
                latency
            )
        )

        if success == true then
            EggEngine.SuccessfulRequests = EggEngine.SuccessfulRequests + 1
            EggEngine.RequestedEggs = EggEngine.RequestedEggs + amount
            EggEngine.ConsecutiveSuccesses = EggEngine.ConsecutiveSuccesses + 1
            return true, nil, requestStarted
        end

        -- Native fallback mirrors PS99's own custom-auto-hatch path while the
        -- runtime-confirmed direct remote remains the primary request.
        if HatchingCmds
            and type(HatchingCmds.SetupCustomEgg) == "function"
            and type(HatchingCmds.AttemptHatch) == "function"
        then
            local okSetup = pcall(
                HatchingCmds.SetupCustomEgg,
                entry.UID,
                entry.Directory,
                amount
            )
            if okSetup then
                local okNative, nativeSuccess, nativeMessage = pcall(
                    HatchingCmds.AttemptHatch
                )
                if okNative and nativeSuccess == true then
                    EggEngine.SuccessfulRequests = EggEngine.SuccessfulRequests + 1
                    EggEngine.RequestedEggs = EggEngine.RequestedEggs + amount
                    EggEngine.ConsecutiveSuccesses = EggEngine.ConsecutiveSuccesses + 1
                    return true, nil, requestStarted
                end
                message = nativeMessage or nativeSuccess or message
            end
        end

        local errorText = tostring(message or success or "Request rejected")
        EggEngine.LastError = errorText

        if isRateLimit(errorText) and attempts <= MAX_RATE_LIMIT_RETRIES then
            EggEngine.RateLimits = EggEngine.RateLimits + 1
            if not waitInterruptible(RATE_LIMIT_WAIT, token) then
                return false, "Stopped.", requestStarted
            end
        else
            EggEngine.Errors = EggEngine.Errors + 1
            if isCurrencyFailure(errorText) then
                return false, "Not enough event currency.", requestStarted
            end
            return false, errorText, requestStarted
        end
    end

    return false, "Stopped.", os.clock()
end

local function startEggEngine()
    if EggEngine.Running or EggEngine.Busy then
        return
    end

    if Runtime.EventFault then
        setNotice("Garden tools hit an error. Reload SliceHub.", "error")
        return
    end

    refreshEggs("start validation")

    local entry = selectedEgg()
    if not entry then
        setNotice("No event egg found.", "error")
        return
    end


    entry.Hatchable = isEggHatchable(entry.Egg)
    entry.Distance = getEggDistance(entry.Egg)
    entry.Maximum = getEggMaximum(entry.Egg)

    if not entry.Hatchable then
        setNotice("The selected custom/event egg is not hatchable.", "error")
        return
    end

    if entry.Distance == math.huge then
        setNotice("Could not determine your distance from the selected egg.", "error")
        return
    end

    if entry.Distance > MAX_HATCH_DISTANCE then
        setNotice(
            string.format(
                "Move closer first: %.1f studs away, maximum is %d.",
                entry.Distance,
                MAX_HATCH_DISTANCE
            ),
            "error"
        )
        return
    end

    local amount, issue = effectiveAmount(entry)
    if amount <= 0 then
        setNotice(issue or "Cannot afford this egg.", "error")
        return
    end

    if EggEngine.SpeedMode == "Fast" then
        if not requirePremium("Fast computed egg speed") then
            EggEngine.SpeedMode = "Stable"
            EggEngine.CurrentDelay = EggEngine.StableDelay
        end
    end

    EggEngine.Running = true
    EggEngine.Busy = false
    EggEngine.WorkerToken = EggEngine.WorkerToken + 1
    local token = EggEngine.WorkerToken

    setNotice(
        string.format(
            "Opening %d x %s every %.3fs.",
            amount,
            entry.Name,
            EggEngine.CurrentDelay
        ),
        "success"
    )

    appendLog(
        "EGG_START",
        string.format(
            "egg=%s id=%s uid=%s amount=%d mode=%s delay=%.3f",
            entry.Name,
            entry.ID,
            entry.UID,
            amount,
            EggEngine.SpeedMode,
            EggEngine.CurrentDelay
        )
    )

    if refreshEventUI then
        refreshEventUI()
    end

    task.spawn(function()
        local okWorker, workerError = xpcall(function()
            while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
                and EggEngine.Alive
                and EggEngine.Running
                and EggEngine.WorkerToken == token
            do
                local current = resolveSelectedEgg()
                if not current then
                    stopEggEngine("Selected custom/event egg disappeared.", "error")
                    break
                end

                current.Hatchable = isEggHatchable(current.Egg)
                current.Distance = getEggDistance(current.Egg)
                current.Maximum = getEggMaximum(current.Egg)

                if not current.Hatchable then
                    stopEggEngine("Selected egg is no longer hatchable.", "error")
                    break
                end

                if current.Distance == math.huge or current.Distance > MAX_HATCH_DISTANCE then
                    stopEggEngine(
                        "Moved too far from the egg: " .. formatDistance(current.Distance) .. " studs.",
                        "error"
                    )
                    break
                end

                local cycleAmount, amountIssue = effectiveAmount(current)
                if cycleAmount <= 0 then
                    stopEggEngine(amountIssue or "Insufficient currency.", "error")
                    break
                end

                local accepted, failure, requestStarted = invokeHatch(
                    current,
                    cycleAmount,
                    token
                )

                if refreshEventUI then
                    refreshEventUI()
                end

                if not accepted then
                    if EggEngine.Running then
                        stopEggEngine(failure or "Egg request failed.", "error")
                    end
                    break
                end

                setNotice(
                    string.format(
                        "Opened %d x %s | next cycle %.3fs",
                        cycleAmount,
                        current.Name,
                        EggEngine.CurrentDelay
                    ),
                    "success"
                )

                local remaining = EggEngine.CurrentDelay - (os.clock() - requestStarted)
                if remaining > 0 and not waitInterruptible(remaining, token) then
                    break
                end
            end
        end, debug.traceback)

        EggEngine.Busy = false

        if not okWorker then
            Runtime.EventFault = tostring(workerError)
            EggEngine.Errors = EggEngine.Errors + 1
            stopEggEngine("Garden tools hit an error. Reload SliceHub.", "error")
            appendLog("EVENT_FAULT", workerError)
        end

        if refreshEventUI then
            refreshEventUI()
        end
    end)
end

local function setEggAmount(amount)
    local entry = selectedEgg()
    local maximum = entry and entry.Maximum or 999
    if not IS_PREMIUM then
        maximum = math.min(maximum, FREE_EVENT_HATCH_CAP)
    end

    EggEngine.RequestedAmount = math.floor(clamp(amount, 1, maximum))
    Config.event.requestedAmount = EggEngine.RequestedAmount
    markConfigDirty()

    if refreshEventUI then
        refreshEventUI()
    end
end

local function setSpeedMode(mode)
    mode = tostring(mode)

    if mode == "Fast" then
        if not requirePremium("Fast computed egg speed") then
            return
        end
        EggEngine.SpeedMode = "Fast"
        EggEngine.CurrentDelay = EggEngine.RawDebounce
    else
        EggEngine.SpeedMode = "Stable"
        EggEngine.CurrentDelay = EggEngine.StableDelay
    end

    Config.event.speedMode = EggEngine.SpeedMode
    markConfigDirty()

    setNotice(
        string.format(
            "%s speed selected: %.3fs request cycle.",
            EggEngine.SpeedMode,
            EggEngine.CurrentDelay
        ),
        EggEngine.SpeedMode == "Fast" and "premium" or "info"
    )

    if refreshEventUI then
        refreshEventUI()
    end
end

local function setUseMaximum(enabled)
    if enabled and not requirePremium("Maximum hatch every cycle") then
        enabled = false
    end

    EggEngine.UseMaximumEveryCycle = enabled == true
    Config.event.useMaximumEveryCycle = EggEngine.UseMaximumEveryCycle
    markConfigDirty()

    if refreshEventUI then
        refreshEventUI()
    end
end

local function setResumeAfterReconnect(enabled)
    if enabled and not requirePremium("Reconnect resume") then
        enabled = false
    end

    EggEngine.ResumeAfterReconnect = enabled == true
    Config.event.resumeAfterReconnect = EggEngine.ResumeAfterReconnect
    markConfigDirty()

    if refreshEventUI then
        refreshEventUI()
    end
end

local function registerEggResultListener()
    local okSignal, signal = pcall(Network.Fired, "Eggs_PlayOpenAnimation")
    if not okSignal or not signal then
        appendLog("EVENT_WARN", "Could not attach Eggs_PlayOpenAnimation listener.")
        return
    end

    local okConnect, connection = pcall(function()
        return signal:Connect(function(eggName, pets)
            if not Runtime.Alive or not EggEngine.Alive or type(pets) ~= "table" then
                return
            end

            local count = 0
            local names = {}

            for _, petData in pairs(pets) do
                count = count + 1

                local petName = "Unknown Pet"
                if type(petData) == "table" then
                    petName = tostring(
                        rawget(petData, "id")
                        or rawget(petData, "ID")
                        or rawget(petData, "name")
                        or petName
                    )
                end

                EggEngine.PetCounts[petName] = (EggEngine.PetCounts[petName] or 0) + 1
                table.insert(names, petName)
                table.insert(EggEngine.RecentPets, 1, petName)
            end

            while #EggEngine.RecentPets > 8 do
                table.remove(EggEngine.RecentPets)
            end

            EggEngine.ConfirmedEggs = EggEngine.ConfirmedEggs + count

            appendLog(
                "EGG_RESULT",
                string.format(
                    "egg=%s count=%d pets=%s",
                    tostring(eggName),
                    count,
                    table.concat(names, ", ")
                )
            )

            if refreshEventUI then
                refreshEventUI()
            end
        end)
    end)

    if okConnect and connection then
        EggEngine.ResultConnection = connection
        table.insert(EggEngine.Connections, connection)
    else
        appendLog("EVENT_WARN", "Result listener failed: " .. tostring(connection))
    end
end

function EggEngine:ApplyAnimationSetting()
    local okSignal, signal = pcall(Network.Fired, "Eggs_PlayOpenAnimation")
    if not okSignal or not signal then
        return false
    end

    if self.DisableAnimation then
        if type(getconnections) ~= "function" then
            return false
        end

        local okConnections, connections = pcall(getconnections, signal)
        if not okConnections or type(connections) ~= "table" then
            return false
        end

        for _, connection in ipairs(connections) do
            if connection ~= self.ResultConnection
                and not self.SuppressedAnimationConnections[connection]
            then
                local disabled = false
                if type(connection.Disable) == "function" then
                    disabled = pcall(connection.Disable, connection)
                elseif type(connection.Disconnect) == "function" then
                    -- Never disconnect permanently. Executors without Disable
                    -- simply keep the animation enabled.
                    disabled = false
                end
                if disabled then
                    self.SuppressedAnimationConnections[connection] = true
                end
            end
        end
        return true
    end

    for connection in pairs(self.SuppressedAnimationConnections) do
        if type(connection.Enable) == "function" then
            pcall(connection.Enable, connection)
        end
        self.SuppressedAnimationConnections[connection] = nil
    end
    return true
end

registerEggResultListener()

--////////////////////////////////////////////////////////////////////
-- Garden automation engine
--////////////////////////////////////////////////////////////////////

local GARDEN_UPGRADE_IDS = {
    "GardenBetterEggs",
    "GardenMoreCoins",
    "GardenMoreDamage",
    "GardenFasterAttacks",
    "GardenFasterCrops",
    "GardenBiggerHarvest",
    "GardenMoreSeeds",
    "GardenBetterLuck",
}

local PREMIUM_GARDEN_FEATURES = {
    AutoUnlockLanes = true,
    AutoBuyPlots = true,
    AutoUpgrades = true,
    AutoRegrow = true,
    AutoRestoreUnits = true,
    FullCampaign = true,
    MissionDirector = true,
    AutoSuperRebirth = true,
    AutoCraftSelected = true,
    AutoMaxLuck = true,
}

local GardenAutomation = {
    Alive = true,
    Suspended = false,
    Busy = false,
    WorkerToken = 0,

    AutoCollect = Config.event.garden.autoCollect == true,
    AutoPlant = Config.event.garden.autoPlant == true,
    AutoUnlockLanes = IS_PREMIUM and Config.event.garden.autoUnlockLanes == true,
    AutoBuyPlots = IS_PREMIUM and Config.event.garden.autoBuyPlots == true,
    AutoUpgrades = IS_PREMIUM and Config.event.garden.autoUpgrades == true,
    UpgradeSelection = type(Config.event.garden.upgradeSelection) == "table"
        and deepCopy(Config.event.garden.upgradeSelection)
        or {},
    UpgradeLabels = {
        GardenBetterEggs = "Better Eggs",
        GardenMoreCoins = "More Sunflowers",
        GardenMoreDamage = "Unit Damage",
        GardenFasterAttacks = "Attack Speed",
        GardenFasterCrops = "Crop Growth",
        GardenBiggerHarvest = "Bigger Harvest",
        GardenMoreSeeds = "More Seeds",
        GardenBetterLuck = "Event Luck",
    },
    AutoRegrow = IS_PREMIUM and Config.event.garden.autoRegrow == true,
    AutoRestoreUnits = IS_PREMIUM and Config.event.garden.autoRestoreUnits == true,

    -- Runtime-confirmed Garden seed merchant.
    -- This intentionally targets only FarmingMerchant.
    AutoMerchant = Config.event.garden.autoMerchant == true,

    -- Runtime-confirmed placed-unit reinforcement.
    -- Protocol: Network.Invoke("EK_Promote", placementID)
    AutoReinforce = Config.event.garden.autoReinforce == true,
    ReinforceCursor = 1,
    ReinforceSuccessDelay = 0.16,
    ReinforceRateLimitDelay = 2.10,
    ReinforceUnavailableDelay = 0.55,
    ReinforceNoUnitsDelay = 0.75,
    ReinforceLastTowerID = nil,
    ReinforceLastTowerName = nil,
    ReinforceLastLevel = nil,
    ReinforceLastReason = nil,
    ReinforceBlockedUntil = {},

    MerchantID = "FarmingMerchant",
    MerchantSlot = 1,
    MerchantMaxSlot = 6,
    MerchantSuccessDelay = 0.65,
    MerchantRateLimitDelay = 1.60,
    MerchantNextSlotDelay = 0.28,
    MerchantPassCooldown = 20,
    MerchantLastReason = nil,

    FullCampaign = IS_PREMIUM and Config.event.garden.fullCampaign == true,

    -- Garden Missions are the three sequential goals used to unlock a
    -- Super Rebirth: six Garden rebirths, coin defeats, then crop harvests.
    -- The director uses temporary action overrides and never rewrites the
    -- user's normal Garden toggle choices.
    MissionDirector = IS_PREMIUM
        and Config.event.garden.missionDirector == true,
    AutoSuperRebirth = IS_PREMIUM
        and Config.event.garden.autoSuperRebirth == true,

    AutoCraftSelected = IS_PREMIUM
        and Config.event.crafting.auto == true,
    CraftSelection = type(Config.event.crafting.selection) == "table"
        and deepCopy(Config.event.crafting.selection)
        or {},
    CraftLabels = {
        Huge1 = "Huge Garlic Chick",
        Huge2 = "Huge Tomato Turtle",
        Huge3 = "Huge Broccoli Dino",
        Titanic = "Titanic Blossom Kitsune",
    },
    CraftOrder = {"Huge1", "Huge2", "Huge3", "Titanic"},
    CraftPriority = {"Titanic", "Huge3", "Huge2", "Huge1"},
    CraftBoard = nil,
    CraftLastStatus = "Choose the recipes SliceHub may craft.",

    AutoMaxLuck = IS_PREMIUM
        and Config.event.luck.auto == true,
    LuckSelection = type(Config.event.luck.selection) == "table"
        and deepCopy(Config.event.luck.selection)
        or {},
    LuckRates = {
        Huge = 1.44,
        Titanic = 0.432,
        Gargantuan = 0.216,
    },
    LuckPriority = {"Huge", "Titanic", "Gargantuan"},
    LuckMaxSeconds = 21600,
    LuckRefillGap = 300,
    LuckLastStatus = "Choose the luck boosts SliceHub may refill.",

    MissionNPCID = "GardenQuests",
    MissionOverrides = {},
    MissionEnsureAt = 0,
    MissionState = {
        Available = false,
        Completed = false,
        GoalIndex = nil,
        GoalLabel = "Waiting for Garden Missions",
        Progress = 0,
        Amount = 0,
        Claimable = false,
        UpdatedAt = 0,
    },

    Seeds = {},
    SelectedSeedIndex = 0,
    SelectedSeedUID = Config.event.garden.selectedSeedUID ~= ""
        and Config.event.garden.selectedSeedUID
        or nil,
    SelectedSeedID = Config.event.garden.selectedSeedID ~= ""
        and Config.event.garden.selectedSeedID
        or nil,

    UnitLayout = type(Config.event.garden.unitLayout) == "table"
        and Config.event.garden.unitLayout
        or {},
    UnitLayoutUserId = tonumber(Config.event.garden.unitLayoutUserId) or 0,

    CollectCursor = 1,
    Next = {
        Status = 0,
        Seeds = 0,
        Collect = 0,
        Plant = 0,
        Lane = 0,
        Plot = 0,
        Upgrade = 0,
        Regrow = 0,
        Restore = 0,
        Merchant = 0,
        Reinforce = 0,
        Mission = 0,
        SuperRebirth = 0,
        Craft = 0,
        Luck = 0,
    },

    Stats = {
        CollectCalls = 0,
        CollectedSunflowers = 0,
        SeedsPlanted = 0,
        LanesUnlocked = 0,
        PlotsPurchased = 0,
        UpgradesPurchased = 0,
        Regrows = 0,
        UnitsRestored = 0,
        MerchantPasses = 0,
        MerchantAttempts = 0,
        MerchantPurchases = 0,
        MerchantRateLimits = 0,
        MerchantRejections = 0,
        ReinforceAttempts = 0,
        ReinforceUpgrades = 0,
        ReinforceRateLimits = 0,
        ReinforceMaxed = 0,
        ReinforceUnavailable = 0,
        BossesObserved = 0,
        MissionClaims = 0,
        SuperRebirths = 0,
        CraftStarts = 0,
        CraftClaims = 0,
        LuckRefills = 0,
        Errors = 0,
    },

    LastAction = "Idle",
    LastError = nil,
    LastBossScore = nil,
    LastStatus = nil,
}

function GardenAutomation:IsUpgradeSelected(upgradeID)
    return type(upgradeID) == "string"
        and self.UpgradeSelection[upgradeID] == true
end

function GardenAutomation:SelectedUpgradeCount()
    local count = 0

    for _, upgradeID in ipairs(GARDEN_UPGRADE_IDS) do
        if self:IsUpgradeSelected(upgradeID) then
            count = count + 1
        end
    end

    return count
end

function GardenAutomation:SetUpgradeSelected(upgradeID, enabled)
    if type(upgradeID) ~= "string" then
        return false
    end

    self.UpgradeSelection[upgradeID] = enabled == true
    Config.event.garden.upgradeSelection = deepCopy(self.UpgradeSelection)

    if self:SelectedUpgradeCount() <= 0 and self.AutoUpgrades then
        self.AutoUpgrades = false
        Config.event.garden.autoUpgrades = false
    end

    markConfigDirty()

    if refreshEventUI then
        refreshEventUI()
    end

    return true
end


function GardenAutomation:ClearMissionOverrides()
    self.MissionOverrides = {}
end

function GardenAutomation:RefreshMissionState()
    local state = {
        Available = false,
        Completed = false,
        GoalIndex = nil,
        GoalLabel = "Waiting for Garden Missions",
        Progress = 0,
        Amount = 0,
        Claimable = false,
        UpdatedAt = os.clock(),
    }

    local save = nil
    if Save and type(Save.Get) == "function" then
        local okSave, result = pcall(Save.Get)
        if okSave and type(result) == "table" then
            save = result
        end
    end

    local questData = save
        and type(save.NPCQuests) == "table"
        and rawget(save.NPCQuests, self.MissionNPCID)
        or nil

    if type(questData) ~= "table"
        or type(questData.Quests) ~= "table"
    then
        if os.clock() >= (tonumber(self.MissionEnsureAt) or 0) then
            self.MissionEnsureAt = os.clock() + 3
            task.spawn(function()
                pcall(Network.Invoke, "NPC Quests: Ensure", self.MissionNPCID)
            end)
        end

        state.GoalLabel = "Loading Garden Missions"
        self:ClearMissionOverrides()
        self.MissionState = state
        return state
    end

    state.Available = true

    if questData.Completed == true then
        state.Completed = true
        state.GoalLabel = "Garden Missions complete"
        self:ClearMissionOverrides()
        self.MissionState = state
        return state
    end

    local labels = {
        [1] = "Complete Garden rebirths",
        [2] = "Defeat Garden coins",
        [3] = "Harvest Garden crops",
    }

    local previousClaimed = true
    for index = 1, 3 do
        local goal = questData.Quests[index]
        if type(goal) == "table" and goal.Claimed ~= true then
            state.GoalIndex = index
            state.GoalLabel = labels[index] or ("Garden mission " .. tostring(index))
            state.Progress = math.max(0, math.floor(tonumber(goal.Progress) or 0))
            state.Amount = math.max(0, math.floor(tonumber(goal.Amount) or 0))
            state.Claimable = previousClaimed
                and state.Amount > 0
                and state.Progress >= state.Amount
            break
        end

        if type(goal) ~= "table" or goal.Claimed ~= true then
            previousClaimed = false
        end
    end

    if state.GoalIndex == nil then
        state.GoalLabel = "Finalizing Garden Missions"
        state.Progress = 3
        state.Amount = 3
        self:ClearMissionOverrides()
    elseif self.MissionDirector then
        local overrides = {}

        if state.GoalIndex == 1 then
            -- Rebirth mission: progress through the full Garden run, but do
            -- not spend on upgrades or the merchant without user permission.
            overrides.AutoCollect = true
            overrides.AutoPlant = true
            overrides.AutoUnlockLanes = true
            overrides.AutoBuyPlots = true
            overrides.AutoRegrow = true
            overrides.AutoRestoreUnits = true
            overrides.AutoReinforce = true
        elseif state.GoalIndex == 2 then
            -- Coin defeats are handled by placed Garden units.
            overrides.AutoRestoreUnits = true
            overrides.AutoReinforce = true
        elseif state.GoalIndex == 3 then
            overrides.AutoCollect = true
            overrides.AutoPlant = true
        end

        self.MissionOverrides = overrides
    else
        self:ClearMissionOverrides()
    end

    self.MissionState = state
    return state
end

function GardenAutomation:ClaimMissionStep()
    local state = self:RefreshMissionState()
    if not state.Available then
        return false, state.GoalLabel
    end
    if state.Completed then
        return false, "Garden Missions already complete"
    end
    if not state.Claimable or not state.GoalIndex then
        return false, "Mission is still in progress"
    end

    local ok, success, reason = pcall(
        Network.Invoke,
        "NPC Quests: Redeem",
        self.MissionNPCID,
        state.GoalIndex
    )

    if not ok then
        return false, tostring(success)
    end
    if not success then
        return false, tostring(reason or "Mission claim rejected")
    end

    self.Stats.MissionClaims = self.Stats.MissionClaims + 1
    self.LastAction = "Claimed " .. tostring(state.GoalLabel)
    self.LastError = nil
    self.Next.Mission = os.clock() + 0.75

    task.delay(0.25, function()
        if self.Alive then
            self:RefreshMissionState()
            if refreshEventUI then
                refreshEventUI()
            end
        end
    end)

    return true, self.LastAction
end

function GardenAutomation:TrySuperRebirth()
    local mission = self:RefreshMissionState()
    if not mission.Completed then
        return false, "Finish and claim every Garden Mission first"
    end

    if EggEngine.Running then
        stopEggEngine("Paused event eggs for Super Rebirth.", "info")
    end

    local okStatus, status, statusReason = pcall(
        Network.Invoke,
        "PvC_BiomeStatus"
    )

    if not okStatus then
        return false, tostring(status)
    end
    if type(status) ~= "table"
        or type(status.biome) ~= "number"
        or type(status.nextBiome) ~= "number"
    then
        return false, tostring(statusReason or "Super Rebirth is not ready")
    end
    if status.biome >= status.nextBiome then
        return false, "No higher Garden biome is available"
    end

    local okAdvance, success, reason = pcall(
        Network.Invoke,
        "PvC_AdvanceBiome"
    )

    if not okAdvance then
        return false, tostring(success)
    end
    if not success then
        return false, tostring(reason or "Super Rebirth rejected")
    end

    self.Stats.SuperRebirths = self.Stats.SuperRebirths + 1
    self.LastAction = string.format(
        "Super Rebirth %d → %d",
        status.biome,
        status.nextBiome
    )
    self.LastError = nil
    self:ClearMissionOverrides()
    self.MissionState = {
        Available = false,
        Completed = false,
        GoalIndex = nil,
        GoalLabel = "Loading next Garden biome",
        Progress = 0,
        Amount = 0,
        Claimable = false,
        UpdatedAt = os.clock(),
    }

    self.Next.Mission = os.clock() + 5
    self.Next.SuperRebirth = os.clock() + 8
    self.Next.Lane = os.clock() + 3
    self.Next.Plot = os.clock() + 3
    self.Next.Plant = os.clock() + 3
    self.Next.Restore = os.clock() + 3

    return true, self.LastAction
end

local function gardenFlagNumber(key, fallback)
    fallback = tonumber(fallback) or 0

    if not ClientFFlags
        or type(ClientFFlags.GetNumber) ~= "function"
        or type(ClientFFlags.Keys) ~= "table"
    then
        return fallback
    end

    local token = ClientFFlags.Keys[key]
    if token == nil then
        return fallback
    end

    local ok, value = pcall(ClientFFlags.GetNumber, token)
    if ok and type(value) == "number" then
        return value
    end

    return fallback
end

local function getGardenPlot()
    if not ClientPlot then
        return nil
    end

    local plot = nil

    if type(ClientPlot.GetByPlayer) == "function" then
        pcall(function()
            plot = ClientPlot.GetByPlayer(LocalPlayer)
        end)
    end

    if not plot and type(ClientPlot.GetLocal) == "function" then
        pcall(function()
            plot = ClientPlot.GetLocal("Garden")
        end)

        if not plot then
            pcall(function()
                plot = ClientPlot.GetLocal()
            end)
        end
    end

    if not plot then
        return nil
    end

    local ok, directory = pcall(function()
        return plot:GetDirectory()
    end)

    if not ok or type(directory) ~= "table" or directory._id ~= "Garden" then
        return nil
    end

    return plot
end

local function plotSave(plot, key, fallback)
    if not plot or type(plot.Save) ~= "function" then
        return fallback
    end

    local ok, value = pcall(plot.Save, plot, key)
    if ok and value ~= nil then
        return value
    end

    return fallback
end

local function getSaveTable()
    if not Save or type(Save.Get) ~= "function" then
        return nil
    end

    local ok, result = pcall(Save.Get)
    if ok and type(result) == "table" then
        return result
    end

    return nil
end

local function getGardenStatus()
    local plot = getGardenPlot()
    if not plot then
        return {
            Plot = nil,
            Supported = false,
            Regrows = 0,
            RegrowCap = 0,
            Lanes = 0,
            MaxLanes = 7,
            RunBossKills = 0,
            BossNeed = 0,
            RegrowReady = false,
            OwnedPlots = 0,
            MaxPlots = 0,
            OccupiedBeds = 0,
            Sunflowers = 0,
            GardenBossScore = 0,
        }
    end

    local regrows = math.max(0, math.floor(tonumber(plotSave(plot, "PvC_Regrows", 0)) or 0))
    local regrowCap = math.max(0, math.floor(gardenFlagNumber("PvC_RegrowCap", 6)))
    local effectiveRegrows = math.min(regrows, regrowCap)

    local bossBase = gardenFlagNumber("PvC_RegrowBossBase", 18)
    local bossStep = gardenFlagNumber("PvC_RegrowBossStep", 1.65)
    local bossNeed = math.max(1, math.ceil(bossBase * bossStep ^ effectiveRegrows))

    local lanes = math.max(
        1,
        math.floor(tonumber(plotSave(plot, "PvC_UnlockedLanes", 1)) or 1)
    )
    local runBossKills = math.max(
        0,
        math.floor(tonumber(plotSave(plot, "PvC_RunBossKills", 0)) or 0)
    )

    local ownedPlots = 0
    local maxPlots = 0

    if GardenPlots then
        if type(GardenPlots.GetOwnedPlots) == "function" then
            pcall(function()
                ownedPlots = GardenPlots.GetOwnedPlots(plot)
            end)
        end

        if type(GardenPlots.MaxPlots) == "function" then
            pcall(function()
                maxPlots = GardenPlots.MaxPlots()
            end)
        end
    end

    local beds = plotSave(plot, "PvC_Beds", {})
    local occupiedBeds = 0
    if type(beds) == "table" then
        for _ in pairs(beds) do
            occupiedBeds = occupiedBeds + 1
        end
    end

    local sunflowers = 0
    if CurrencyCmds and type(CurrencyCmds.Get) == "function" then
        pcall(function()
            sunflowers = tonumber(CurrencyCmds.Get("Sunflowers")) or 0
        end)
    end

    local save = getSaveTable()
    local globalBossScore = save and tonumber(save.GardenBossScore) or 0

    return {
        Plot = plot,
        Supported = true,
        Regrows = regrows,
        RegrowCap = regrowCap,
        Lanes = lanes,
        MaxLanes = 7,
        RunBossKills = runBossKills,
        BossNeed = bossNeed,
        RegrowReady =
            regrows < regrowCap
            and lanes >= 7
            and runBossKills >= bossNeed,
        OwnedPlots = math.max(0, math.floor(tonumber(ownedPlots) or 0)),
        MaxPlots = math.max(0, math.floor(tonumber(maxPlots) or 0)),
        OccupiedBeds = occupiedBeds,
        Sunflowers = math.max(0, tonumber(sunflowers) or 0),
        GardenBossScore = math.max(0, math.floor(tonumber(globalBossScore) or 0)),
    }
end



function GardenAutomation:IsCraftSelected(recipeID)
    return type(recipeID) == "string"
        and self.CraftSelection[recipeID] == true
end

function GardenAutomation:SelectedCraftCount()
    local count = 0
    for _, recipeID in ipairs(self.CraftOrder) do
        if self:IsCraftSelected(recipeID) then
            count = count + 1
        end
    end
    return count
end

function GardenAutomation:SetCraftSelected(recipeID, enabled)
    if type(recipeID) ~= "string" or self.CraftLabels[recipeID] == nil then
        return false
    end

    self.CraftSelection[recipeID] = enabled == true
    Config.event.crafting.selection = deepCopy(self.CraftSelection)

    if self:SelectedCraftCount() <= 0 and self.AutoCraftSelected then
        self.AutoCraftSelected = false
        Config.event.crafting.auto = false
    end

    markConfigDirty()
    if refreshEventUI then
        refreshEventUI()
    end
    return true
end

function GardenAutomation:SetCraftAuto(enabled)
    enabled = enabled == true
    if enabled and not requirePremium("Auto Event Crafting") then
        return false
    end
    if enabled and self:SelectedCraftCount() <= 0 then
        setNotice("Select at least one event craft first.", "error")
        return false
    end

    self.AutoCraftSelected = enabled
    Config.event.crafting.auto = enabled
    self.Next.Craft = 0
    markConfigDirty()
    setNotice(
        enabled and "Auto Event Crafting enabled." or "Auto Event Crafting disabled.",
        enabled and "success" or "info"
    )
    if refreshEventUI then
        refreshEventUI()
    end
    return true
end

function GardenAutomation:IsLuckSelected(rarity)
    return type(rarity) == "string"
        and self.LuckSelection[rarity] == true
end

function GardenAutomation:SelectedLuckCount()
    local count = 0
    for _, rarity in ipairs(self.LuckPriority) do
        if self:IsLuckSelected(rarity) then
            count = count + 1
        end
    end
    return count
end

function GardenAutomation:SetLuckSelected(rarity, enabled)
    if type(rarity) ~= "string" or self.LuckRates[rarity] == nil then
        return false
    end

    self.LuckSelection[rarity] = enabled == true
    Config.event.luck.selection = deepCopy(self.LuckSelection)

    if self:SelectedLuckCount() <= 0 and self.AutoMaxLuck then
        self.AutoMaxLuck = false
        Config.event.luck.auto = false
    end

    markConfigDirty()
    if refreshEventUI then
        refreshEventUI()
    end
    return true
end

function GardenAutomation:SetLuckAuto(enabled)
    enabled = enabled == true
    if enabled and not requirePremium("Auto Event Luck") then
        return false
    end
    if enabled and self:SelectedLuckCount() <= 0 then
        setNotice("Select at least one Event Luck rarity first.", "error")
        return false
    end

    self.AutoMaxLuck = enabled
    Config.event.luck.auto = enabled
    self.Next.Luck = 0
    markConfigDirty()
    setNotice(
        enabled and "Auto Event Luck enabled." or "Auto Event Luck disabled.",
        enabled and "success" or "info"
    )
    if refreshEventUI then
        refreshEventUI()
    end
    return true
end

function GardenAutomation:FormatClock(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%d:%02d:%02d", hours, minutes, secs)
end

function GardenAutomation:GetLuckTime(rarity)
    local save = getSaveTable()
    local tracks = save and save.GardenChanceMachineTracks
    if type(tracks) ~= "table" then
        return nil
    end

    local expiry = tonumber(tracks[rarity]) or 0
    local serverTime = 0
    pcall(function()
        serverTime = Workspace:GetServerTimeNow()
    end)
    if serverTime <= 0 then
        return nil
    end
    return math.max(0, expiry - serverTime)
end

function GardenAutomation:RefreshCraftBoard()
    local ok, board, reason = pcall(Network.Invoke, "GardenCombineMachine_GetBoard")
    if not ok then
        self.CraftLastStatus = "Craft board error: " .. tostring(board)
        return nil, self.CraftLastStatus
    end
    if type(board) ~= "table" or type(board.Recipes) ~= "table" then
        self.CraftLastStatus = tostring(reason or "Craft board is unavailable")
        return nil, self.CraftLastStatus
    end

    self.CraftBoard = board
    return board
end

function GardenAutomation:CraftSelectedStep()
    if self:SelectedCraftCount() <= 0 then
        return false, "Choose at least one event craft"
    end

    local board, boardError = self:RefreshCraftBoard()
    if not board then
        return false, boardError
    end

    local recipesByID = {}
    for _, recipe in ipairs(board.Recipes) do
        if type(recipe) == "table" and recipe.RecipeId ~= nil then
            recipesByID[tostring(recipe.RecipeId)] = recipe
        end
    end

    for _, recipeID in ipairs(self.CraftPriority) do
        local recipe = recipesByID[recipeID]
        if self:IsCraftSelected(recipeID)
            and type(recipe) == "table"
            and recipe.QueueUID ~= nil
        then
            local remaining = math.max(0, tonumber(recipe.Remaining) or 0)
            if remaining <= 0 then
                local ok, success, reason = pcall(
                    Network.Invoke,
                    "GardenCombineMachine_Claim",
                    recipe.QueueUID
                )
                if not ok then
                    self.CraftLastStatus = "Claim error: " .. tostring(success)
                    return false, self.CraftLastStatus
                end
                if success == true then
                    self.Stats.CraftClaims = self.Stats.CraftClaims + 1
                    self.CraftLastStatus = "Claimed " .. tostring(
                        recipe.Output or self.CraftLabels[recipeID]
                    )
                    self.LastAction = self.CraftLastStatus
                    return true, self.CraftLastStatus
                end
                self.CraftLastStatus = tostring(reason or "Craft claim rejected")
                return false, self.CraftLastStatus
            end
        end
    end

    local lastReason = nil
    for _, recipeID in ipairs(self.CraftPriority) do
        local recipe = recipesByID[recipeID]
        if self:IsCraftSelected(recipeID)
            and type(recipe) == "table"
            and recipe.QueueUID == nil
        then
            if recipe.Enabled == false then
                lastReason = tostring(recipe.Output or self.CraftLabels[recipeID])
                    .. " is unavailable"
            else
                local ok, success, reason = pcall(
                    Network.Invoke,
                    "GardenCombineMachine_StartCraft",
                    recipeID
                )
                if not ok then
                    lastReason = tostring(success)
                elseif success == true then
                    self.Stats.CraftStarts = self.Stats.CraftStarts + 1
                    self.CraftLastStatus = "Started " .. tostring(
                        recipe.Output or self.CraftLabels[recipeID]
                    )
                    self.LastAction = self.CraftLastStatus
                    return true, self.CraftLastStatus
                else
                    lastReason = tostring(reason or "Craft requirements not met")
                end
            end
        end
    end

    for _, recipeID in ipairs(self.CraftPriority) do
        local recipe = recipesByID[recipeID]
        if self:IsCraftSelected(recipeID)
            and type(recipe) == "table"
            and recipe.QueueUID ~= nil
            and (tonumber(recipe.Remaining) or 0) > 0
        then
            self.CraftLastStatus = tostring(
                recipe.Output or self.CraftLabels[recipeID]
            ) .. " ready in " .. self:FormatClock(recipe.Remaining)
            return false, self.CraftLastStatus
        end
    end

    self.CraftLastStatus = lastReason or "No selected craft can start yet"
    return false, self.CraftLastStatus
end

function GardenAutomation:MaxSelectedLuckStep(force)
    if self:SelectedLuckCount() <= 0 then
        return false, "Choose at least one Event Luck rarity"
    end

    local available = 0
    if CurrencyCmds and type(CurrencyCmds.Get) == "function" then
        pcall(function()
            available = math.max(0, tonumber(CurrencyCmds.Get("Sunflowers")) or 0)
        end)
    end

    local skipped = 0
    local lastReason = nil

    for _, rarity in ipairs(self.LuckPriority) do
        if self:IsLuckSelected(rarity) then
            local timeLeft = self:GetLuckTime(rarity)
            if timeLeft == nil then
                lastReason = "Event Luck state is still loading"
                continue
            end

            local shouldRefill = force == true
                and timeLeft <= self.LuckMaxSeconds - 1
                or force ~= true
                and timeLeft <= self.LuckMaxSeconds - self.LuckRefillGap

            if shouldRefill then
                local rate = tonumber(self.LuckRates[rarity]) or 0
                local needed = rate > 0
                    and math.max(0, math.ceil((self.LuckMaxSeconds - timeLeft) / rate))
                    or 0

                if needed <= 0 then
                    skipped = skipped + 1
                elseif available < needed then
                    lastReason = "Need " .. formatCompactNumber(needed)
                        .. " Sunflowers for " .. rarity .. " Luck"
                else
                    local ok, success, reason = pcall(
                        Network.Invoke,
                        "GardenChanceMachine_AddTime",
                        rarity,
                        "Slot1",
                        needed
                    )
                    if not ok then
                        self.LuckLastStatus = "Luck error: " .. tostring(success)
                        return false, self.LuckLastStatus
                    end
                    if success == true then
                        self.Stats.LuckRefills = self.Stats.LuckRefills + 1
                        self.LuckLastStatus = "Maxed " .. rarity .. " Luck for 6 hours"
                        self.LastAction = self.LuckLastStatus
                        return true, self.LuckLastStatus
                    end
                    lastReason = tostring(reason or (rarity .. " Luck refill rejected"))
                end
            else
                skipped = skipped + 1
            end
        end
    end

    self.LuckLastStatus = lastReason
        or (skipped > 0 and "Selected luck timers are already near 6 hours")
        or "No Event Luck rarity selected"
    return false, self.LuckLastStatus
end

local function itemMethod(item, methodName, fallback)
    if type(item) ~= "table" or type(item[methodName]) ~= "function" then
        return fallback
    end

    local ok, result = pcall(item[methodName], item)
    if ok and result ~= nil then
        return result
    end

    return fallback
end

local function refreshGardenSeeds()
    local previousUID = GardenAutomation.SelectedSeedUID
    local previousID = GardenAutomation.SelectedSeedID
    local entries = {}

    if CropSeedItem and type(CropSeedItem.All) == "function" then
        local ok, all = pcall(CropSeedItem.All, CropSeedItem)
        if ok and type(all) == "table" then
            for _, item in pairs(all) do
                if type(item) == "table" then
                    local uid = tostring(itemMethod(item, "GetUID", ""))
                    local id = tostring(itemMethod(item, "GetId", ""))
                    local name = tostring(itemMethod(item, "GetName", id))
                    local amount = tonumber(itemMethod(item, "GetAmount", 1)) or 1
                    local variant = itemMethod(item, "GetVariant", nil)

                    if uid ~= "" and id ~= "" and amount > 0 then
                        table.insert(entries, {
                            Item = item,
                            UID = uid,
                            ID = id,
                            Name = name,
                            Variant = variant,
                            Amount = amount,
                        })
                    end
                end
            end
        end
    end

    table.sort(entries, function(left, right)
        if left.Name ~= right.Name then
            return left.Name < right.Name
        end
        return left.UID < right.UID
    end)

    GardenAutomation.Seeds = entries
    GardenAutomation.SelectedSeedIndex = 0

    for index, entry in ipairs(entries) do
        if entry.UID == previousUID then
            GardenAutomation.SelectedSeedIndex = index
            break
        end
    end

    if GardenAutomation.SelectedSeedIndex == 0 and previousID then
        for index, entry in ipairs(entries) do
            if entry.ID == previousID then
                GardenAutomation.SelectedSeedIndex = index
                GardenAutomation.SelectedSeedUID = entry.UID
                break
            end
        end
    end

    if GardenAutomation.SelectedSeedIndex == 0 then
        GardenAutomation.SelectedSeedUID = nil
        GardenAutomation.SelectedSeedID = nil
    else
        local selected = entries[GardenAutomation.SelectedSeedIndex]
        GardenAutomation.SelectedSeedUID = selected.UID
        GardenAutomation.SelectedSeedID = selected.ID
    end

    Config.event.garden.selectedSeedUID = GardenAutomation.SelectedSeedUID or ""
    Config.event.garden.selectedSeedID = GardenAutomation.SelectedSeedID or ""
    markConfigDirty()

end

local function selectedGardenSeed()
    local index = GardenAutomation.SelectedSeedIndex
    local entry = GardenAutomation.Seeds[index]

    if entry and entry.UID == GardenAutomation.SelectedSeedUID then
        return entry
    end

    refreshGardenSeeds()
    return GardenAutomation.Seeds[GardenAutomation.SelectedSeedIndex]
end

local function cycleGardenSeed(direction)
    if #GardenAutomation.Seeds == 0 then
        refreshGardenSeeds()
    end

    if #GardenAutomation.Seeds == 0 then
        setNotice("No Garden seeds found.", "error")
        return
    end

    local index = GardenAutomation.SelectedSeedIndex + direction

    if index < 1 then
        index = #GardenAutomation.Seeds
    elseif index > #GardenAutomation.Seeds then
        index = 1
    end

    local entry = GardenAutomation.Seeds[index]
    GardenAutomation.SelectedSeedIndex = index
    GardenAutomation.SelectedSeedUID = entry.UID
    GardenAutomation.SelectedSeedID = entry.ID

    Config.event.garden.selectedSeedUID = entry.UID
    Config.event.garden.selectedSeedID = entry.ID
    markConfigDirty()

    setNotice("Selected seed: " .. entry.Name, "success")

    if refreshEventUI then
        refreshEventUI()
    end
end

local function getBedKeys(plot, occupiedOnly)
    local output = {}
    local beds = plotSave(plot, "PvC_Beds", {})

    if type(beds) ~= "table" then
        beds = {}
    end

    local maximum = 0
    if GardenPlots and type(GardenPlots.MaxPlots) == "function" then
        pcall(function()
            maximum = GardenPlots.MaxPlots()
        end)
    end

    maximum = math.max(maximum, 1)

    for index = 1, maximum do
        local unlocked = true

        if GardenPlots and type(GardenPlots.IsBedUnlocked) == "function" then
            local ok, result = pcall(GardenPlots.IsBedUnlocked, plot, index)
            unlocked = ok and result == true
        end

        if unlocked then
            local occupied = beds[index] ~= nil or beds[tostring(index)] ~= nil

            if not occupiedOnly or occupied then
                table.insert(output, tostring(index))
            end
        end
    end

    return output, beds
end

local function collectOneBed()
    local status = getGardenStatus()
    local plot = status.Plot

    if not plot then
        return false, "No Garden plot"
    end

    local keys = getBedKeys(plot, true)
    if #keys == 0 then
        return false, "No planted beds"
    end

    if GardenAutomation.CollectCursor > #keys then
        GardenAutomation.CollectCursor = 1
    end

    local bed = keys[GardenAutomation.CollectCursor]
    GardenAutomation.CollectCursor = GardenAutomation.CollectCursor + 1

    local ok, amount = pcall(plot.Invoke, plot, "SD_Collect", bed)
    if not ok then
        return false, tostring(amount)
    end

    GardenAutomation.Stats.CollectCalls =
        GardenAutomation.Stats.CollectCalls + 1

    if type(amount) == "number" and amount > 0 then
        GardenAutomation.Stats.CollectedSunflowers =
            GardenAutomation.Stats.CollectedSunflowers + amount

        GardenAutomation.LastAction =
            "Collected " .. formatCompactNumber(amount) .. " Sunflowers"
        return true, amount
    end

    return false, "Nothing ready"
end

local function plantOneSeed()
    local status = getGardenStatus()
    local plot = status.Plot

    if not plot then
        return false, "No Garden plot"
    end

    local seed = selectedGardenSeed()
    if not seed then
        return false, "Select a Garden seed first"
    end

    local _, beds = getBedKeys(plot, false)
    local maximum = status.MaxPlots

    for index = 1, maximum do
        local unlocked = true

        if GardenPlots and type(GardenPlots.IsBedUnlocked) == "function" then
            local ok, result = pcall(GardenPlots.IsBedUnlocked, plot, index)
            unlocked = ok and result == true
        end

        local occupied = beds[index] ~= nil or beds[tostring(index)] ~= nil

        if unlocked and not occupied then
            local ok, success, reason = pcall(
                plot.Invoke,
                plot,
                "SD_Insert",
                tostring(index),
                seed.UID
            )

            if not ok then
                return false, tostring(success)
            end

            if success == true then
                GardenAutomation.Stats.SeedsPlanted =
                    GardenAutomation.Stats.SeedsPlanted + 1
                GardenAutomation.LastAction =
                    "Planted " .. seed.Name .. " in bed " .. tostring(index)

                task.delay(0.25, refreshGardenSeeds)
                return true
            end

            return false, tostring(reason or "Plant rejected")
        end
    end

    return false, "No empty unlocked bed"
end

local function unlockLaneOnce()
    local status = getGardenStatus()

    if not status.Plot then
        return false, "No Garden plot"
    end

    if status.Lanes >= status.MaxLanes then
        return false, "All lanes unlocked"
    end

    local ok, success, reason, newLane = pcall(Network.Invoke, "PG_Widen")
    if not ok then
        return false, tostring(success)
    end

    if success == true then
        GardenAutomation.Stats.LanesUnlocked =
            GardenAutomation.Stats.LanesUnlocked + 1
        GardenAutomation.LastAction =
            "Unlocked lane " .. tostring(newLane or status.Lanes + 1)
        return true
    end

    return false, tostring(reason or "Lane purchase rejected")
end

local function buyPlotOnce()
    local status = getGardenStatus()
    local plot = status.Plot

    if not plot then
        return false, "No Garden plot"
    end

    if not GardenPlots
        or type(GardenPlots.IsBedUnlocked) ~= "function"
        or type(GardenPlots.PlotCost) ~= "function"
    then
        return false, "GardenPlots API unavailable"
    end

    for index = 1, status.MaxPlots do
        local okUnlocked, unlocked = pcall(
            GardenPlots.IsBedUnlocked,
            plot,
            index
        )

        if okUnlocked and not unlocked then
            local okCost, cost = pcall(GardenPlots.PlotCost, index)
            cost = okCost and tonumber(cost) or nil

            if cost and status.Sunflowers < cost then
                return false, "Need " .. formatCompactNumber(cost) .. " Sunflowers"
            end

            local ok, success, reason = pcall(
                plot.Invoke,
                plot,
                "BD_Acquire",
                index
            )

            if not ok then
                return false, tostring(success)
            end

            if success == true then
                GardenAutomation.Stats.PlotsPurchased =
                    GardenAutomation.Stats.PlotsPurchased + 1
                GardenAutomation.LastAction =
                    "Purchased Garden plot " .. tostring(index)
                return true
            end

            return false, tostring(reason or "Plot purchase rejected")
        end
    end

    return false, "All plots unlocked"
end

local function nextAffordableUpgrade()
    if not EventUpgradeCmds or type(EventUpgradesDirectory) ~= "table" then
        return nil
    end

    local best = nil

    for _, id in ipairs(GARDEN_UPGRADE_IDS) do
        local directory = EventUpgradesDirectory[id]

        if GardenAutomation:IsUpgradeSelected(id)
            and type(directory) == "table"
        then
            local tier = 0
            pcall(function()
                tier = EventUpgradeCmds.GetTier(directory)
            end)

            local maximum = type(directory.TierPowers) == "table"
                and #directory.TierPowers
                or 0

            if tier < maximum then
                local nextCost = type(directory.TierCosts) == "table"
                    and directory.TierCosts[tier + 1]
                    or nil
                local amount = math.huge
                local affordable = true

                if type(nextCost) == "table" then
                    pcall(function()
                        amount = tonumber(nextCost:GetAmount()) or math.huge
                    end)

                    pcall(function()
                        affordable = nextCost:CountAny() >= nextCost:GetAmount()
                    end)
                end

                if affordable and (not best or amount < best.Cost) then
                    best = {
                        ID = id,
                        Directory = directory,
                        Tier = tier,
                        Maximum = maximum,
                        Cost = amount,
                    }
                end
            end
        end
    end

    return best
end

-- EventUpgradeCmds.Purchase uses the confirmed
-- Network.Invoke("EventUpgrades: Purchase", upgradeID) protocol.
local function buyUpgradeOnce()
    if GardenAutomation:SelectedUpgradeCount() <= 0 then
        return false, "Choose at least one Garden upgrade"
    end

    local upgrade = nextAffordableUpgrade()

    if not upgrade then
        return false, "No selected Garden upgrade is affordable"
    end

    local ok, success, reason = pcall(
        EventUpgradeCmds.Purchase,
        upgrade.Directory
    )

    if not ok then
        return false, tostring(success)
    end

    if success == true then
        GardenAutomation.Stats.UpgradesPurchased =
            GardenAutomation.Stats.UpgradesPurchased + 1
        GardenAutomation.LastAction =
            "Upgraded " .. tostring(upgrade.Directory.Name or upgrade.ID)
        return true
    end

    return false, tostring(reason or "Upgrade rejected")
end

local function regrowOnce()
    local status = getGardenStatus()

    if not status.Plot then
        return false, "No Garden plot"
    end

    if not status.RegrowReady then
        return false, string.format(
            "Rebirth locked: lanes %d/%d, bosses %d/%d",
            status.Lanes,
            status.MaxLanes,
            status.RunBossKills,
            status.BossNeed
        )
    end

    if EggEngine.Running then
        stopEggEngine("Paused event eggs for Garden rebirth.", "info")
    end

    local ok, success, reason, newRegrow = pcall(Network.Invoke, "WK_Reclaim")
    if not ok then
        return false, tostring(success)
    end

    if success == true then
        GardenAutomation.Stats.Regrows =
            GardenAutomation.Stats.Regrows + 1
        GardenAutomation.LastAction =
            "Completed Garden rebirth " .. tostring(newRegrow or status.Regrows + 1)

        GardenAutomation.Next.Lane = os.clock() + 2
        GardenAutomation.Next.Plot = os.clock() + 2
        GardenAutomation.Next.Plant = os.clock() + 2
        GardenAutomation.Next.Restore = os.clock() + 2

        return true
    end

    return false, tostring(reason or "Rebirth rejected")
end

local function getLocalTowerWorld()
    if not ClientTowerDefense or type(ClientTowerDefense.GetLocal) ~= "function" then
        return nil
    end

    local ok, world = pcall(ClientTowerDefense.GetLocal)
    if ok then
        return world
    end

    return nil
end

local GardenLineTools = (function()
    local fallback = {
        Available = false,
        Error = "Line tools did not initialize",
    }

    local compiler = loadstring
    if type(compiler) ~= "function" then
        fallback.Error = "Executor loadstring is unavailable"
        return fallback
    end

    local moduleSource = [====[
return function(C)
    local M = {
        Available = false,
        Error = nil,
        Units = {},
        SelectedUnitIndex = 0,
        CleanArmedUntil = 0,
        Busy = false,
        LastAction = "Idle",
        LastError = nil,
        PatternCursor = 1,
        AutoFill = false,
        AutoFillToken = 0,
        FillCursor = 1,
        Cleaning = false,
        CleanToken = 0,
    }

    local function clamp(value, minimum, maximum)
        value = tonumber(value) or minimum
        if value < minimum then
            return minimum
        elseif value > maximum then
            return maximum
        end
        return value
    end

    local function itemCall(item, methodName, fallback)
        if type(item) ~= "table" or type(item[methodName]) ~= "function" then
            return fallback
        end

        local ok, result = pcall(item[methodName], item)
        if ok and result ~= nil then
            return result
        end

        return fallback
    end

    local function ensureConfig()
        local garden = C.Config.event.garden

        if type(garden.lineTools) ~= "table" then
            garden.lineTools = {
                selectedLine = 1,
                selectedUnitUID = "",
                selectedUnitID = "",
                quantity = 1,
                pattern = {},
                placeDelay = 0.12,
                autoFill = false,
            }
        end

        local config = garden.lineTools

        config.selectedLine = math.floor(
            clamp(config.selectedLine or 1, 1, 7)
        )
        config.quantity = math.floor(
            clamp(config.quantity or 1, 1, 25)
        )
        config.placeDelay = 0.12

        if type(config.pattern) ~= "table" then
            config.pattern = {}
        end

        config.autoFill = config.autoFill == true

        return config
    end

    local Config = ensureConfig()
    M.AutoFill = Config.autoFill == true

    local TowerItem = C.RequireModule(
        C.ItemsFolder and C.ItemsFolder:FindFirstChild("TowerItem"),
        "Items.TowerItem",
        true
    )

    local EntityPlacement = C.RequireModule(
        C.PvCombatCmdsFolder
            and C.PvCombatCmdsFolder:FindFirstChild("EntityPlacement"),
        "Client.PvCombatCmds.EntityPlacement",
        true
    )

    local function markDirty()
        C.MarkDirty()
    end

    local function getWorld()
        return C.GetLocalTowerWorld()
    end

    local function getStatus()
        return C.GetGardenStatus()
    end

    local function getPlaced()
        local output = {}
        local world = getWorld()

        if not world
            or not C.ClientTower
            or type(C.ClientTower.All) ~= "function"
        then
            return output, world
        end

        local ok, towers = pcall(C.ClientTower.All, world)
        if not ok or type(towers) ~= "table" then
            return output, world
        end

        for _, tower in ipairs(towers) do
            local okItem, item = pcall(tower.GetItem, tower)
            local okCFrame, worldCFrame = pcall(tower.GetCFrame, tower)
            local okID, placementID = pcall(tower.GetId, tower)

            if okItem
                and okCFrame
                and type(item) == "table"
                and typeof(worldCFrame) == "CFrame"
            then
                table.insert(output, {
                    Tower = tower,
                    Item = item,
                    UID = tostring(itemCall(item, "GetUID", "")),
                    ID = okID and placementID or nil,
                    CFrame = worldCFrame,
                    Radius = tonumber(
                        itemCall(item, "GetPlacementRadius", 2)
                    ) or 2,
                })
            end
        end

        return output, world
    end

    local function totalPlacedCount()
        local placed = getPlaced()
        return #placed
    end

    local function waitForPlacedIncrease(previousCount, timeout)
        local deadline = os.clock() + math.max(
            0.5,
            tonumber(timeout) or 3.5
        )

        while C.IsAlive() and os.clock() < deadline do
            if totalPlacedCount() > previousCount then
                return true
            end
            task.wait(0.04)
        end

        return totalPlacedCount() > previousCount
    end

    local function getLaneGeometry(lineNumber)
        local plot = C.GetGardenPlot()
        if not plot then
            return nil, nil, nil, "Garden is not loaded"
        end

        local okModel, model = pcall(plot.GetModel, plot)
        if not okModel or not model then
            return nil, nil, nil, "Garden plot model is not streamed yet"
        end

        local lanes = model:FindFirstChild("Lanes", true)
        if not lanes then
            return nil, nil, nil, "Garden Lanes folder was not found"
        end

        local lane =
            lanes:FindFirstChild(tostring(lineNumber))
            or lanes:FindFirstChild("Lane" .. tostring(lineNumber))

        if not lane then
            for _, child in ipairs(lanes:GetChildren()) do
                if tostring(child.Name):match("%d+") == tostring(lineNumber) then
                    lane = child
                    break
                end
            end
        end

        if not lane then
            return nil, nil, nil, "Selected line geometry was not found"
        end

        local slotsRoot = lane:FindFirstChild("Slots", true) or lane
        local parts = {}

        for _, child in ipairs(slotsRoot:GetDescendants()) do
            if child:IsA("BasePart") then
                table.insert(parts, child)
            end
        end

        if slotsRoot:IsA("BasePart") then
            table.insert(parts, slotsRoot)
        end

        if #parts == 0 then
            return nil, nil, nil, "Selected line has no placement parts"
        end

        table.sort(parts, function(left, right)
            if left.Position.Z ~= right.Position.Z then
                return left.Position.Z < right.Position.Z
            end
            return left.Position.X < right.Position.X
        end)

        local row = lane:FindFirstChild("Row", true)

        if not row or not row:IsA("BasePart") then
            for _, child in ipairs(lane:GetDescendants()) do
                if child:IsA("BasePart")
                    and child:FindFirstChild("Begin")
                    and child:FindFirstChild("End")
                then
                    row = child
                    break
                end
            end
        end

        return lane, parts, row, nil
    end

    local function facingAt(position, row)
        if row and row:IsA("BasePart") then
            local beginAttachment = row:FindFirstChild("Begin")
            local endAttachment = row:FindFirstChild("End")

            if beginAttachment
                and beginAttachment:IsA("Attachment")
                and endAttachment
                and endAttachment:IsA("Attachment")
            then
                local direction =
                    (beginAttachment.WorldPosition - endAttachment.WorldPosition)
                    * Vector3.new(1, 0, 1)

                if direction.Magnitude > 0.001 then
                    return CFrame.lookAlong(position, direction)
                end
            end
        end

        return CFrame.new(position)
    end

    local function pointInsidePartXZ(part, worldPosition, margin)
        local localPoint = part.CFrame:PointToObjectSpace(worldPosition)
        margin = tonumber(margin) or 0

        return math.abs(localPoint.X)
                <= math.max(0, part.Size.X / 2 - margin)
            and math.abs(localPoint.Z)
                <= math.max(0, part.Size.Z / 2 - margin)
    end

    local function generateCandidates(item, lineNumber)
        local _, parts, row, errorMessage =
            getLaneGeometry(lineNumber)

        if errorMessage then
            return {}, errorMessage
        end

        local radius = tonumber(
            itemCall(item, "GetPlacementRadius", 2)
        ) or 2

        -- The old radius * 2 spacing was much stricter than PS99's server.
        -- Scan a denser set of positions and let WD_Attach be authoritative.
        local spacing = math.max(1.1, radius * 0.72)
        local candidates = {}

        for _, part in ipairs(parts) do
            local useX = part.Size.X >= part.Size.Z
            local length = useX and part.Size.X or part.Size.Z
            local direction = useX
                and part.CFrame.RightVector
                or part.CFrame.LookVector

            local edgePadding = math.min(
                math.max(radius * 0.2, 0.25),
                1.25
            )
            local usable = math.max(
                0,
                length - edgePadding * 2
            )

            local count = math.max(
                1,
                math.floor(usable / spacing) + 1
            )
            count = math.min(count, 80)

            for index = 1, count do
                local offset = 0

                if count > 1 then
                    offset = -usable / 2
                        + usable * ((index - 1) / (count - 1))
                end

                local position =
                    part.Position
                    + direction * offset
                    + Vector3.new(0, part.Size.Y / 2, 0)

                if pointInsidePartXZ(
                    part,
                    position,
                    edgePadding
                ) then
                    table.insert(candidates, {
                        Part = part,
                        CFrame = facingAt(position, row),
                    })
                end
            end
        end

        table.sort(candidates, function(left, right)
            if left.CFrame.Z ~= right.CFrame.Z then
                return left.CFrame.Z < right.CFrame.Z
            end
            return left.CFrame.X < right.CFrame.X
        end)

        return candidates, nil
    end

    local function candidateIsFree(item, candidate, placed)
        local radius = tonumber(
            itemCall(item, "GetPlacementRadius", 2)
        ) or 2

        local point = Vector2.new(
            candidate.CFrame.X,
            candidate.CFrame.Z
        )

        -- Only block near-identical centers. The previous sum-of-radii check
        -- rejected positions the real PS99 server accepts.
        for _, entry in ipairs(placed) do
            local other = Vector2.new(
                entry.CFrame.X,
                entry.CFrame.Z
            )
            local minimumDistance = math.max(
                1.0,
                math.min(radius, entry.Radius) * 0.4
            )

            if (point - other).Magnitude < minimumDistance then
                return false
            end
        end

        -- Do not use EntityPlacement.Validate here. Its client state can be
        -- stale and caused the false "no valid positions" warning.
        return true
    end

    local function belongsToLine(entry, lineNumber)
        local _, parts, _, errorMessage =
            getLaneGeometry(lineNumber)

        if errorMessage then
            return false
        end

        for _, part in ipairs(parts) do
            if pointInsidePartXZ(
                part,
                entry.CFrame.Position,
                0
            ) then
                return true
            end
        end

        return false
    end

    local function getLineEntries(lineNumber)
        local output = {}
        local placed = getPlaced()

        for _, entry in ipairs(placed) do
            if belongsToLine(entry, lineNumber) then
                table.insert(output, entry)
            end
        end

        return output
    end

    local function unitByUID(uid)
        for _, entry in ipairs(M.Units) do
            if entry.UID == uid then
                return entry
            end
        end
        return nil
    end

    local function countPlacedUID(uid, placed)
        local count = 0

        for _, entry in ipairs(placed) do
            if entry.UID == uid then
                count = count + 1
            end
        end

        return count
    end

    function M:RefreshUnits()
        local previousUID = Config.selectedUnitUID
        local previousID = Config.selectedUnitID
        local entries = {}

        if TowerItem and type(TowerItem.All) == "function" then
            local ok, all = pcall(TowerItem.All, TowerItem)

            if ok and type(all) == "table" then
                for _, item in pairs(all) do
                    if type(item) == "table" then
                        local uid = tostring(
                            itemCall(item, "GetUID", "")
                        )
                        local id = tostring(
                            itemCall(item, "GetId", "")
                        )
                        local name = tostring(
                            itemCall(item, "GetName", id)
                        )
                        local amount = tonumber(
                            itemCall(item, "GetAmount", 1)
                        ) or 1

                        if uid ~= "" and id ~= "" and amount > 0 then
                            table.insert(entries, {
                                Item = item,
                                UID = uid,
                                ID = id,
                                Name = name,
                                Amount = math.max(1, math.floor(amount)),
                            })
                        end
                    end
                end
            end
        end

        table.sort(entries, function(left, right)
            if left.Name ~= right.Name then
                return left.Name < right.Name
            end
            return left.UID < right.UID
        end)

        M.Units = entries
        M.SelectedUnitIndex = 0

        for index, entry in ipairs(entries) do
            if entry.UID == previousUID then
                M.SelectedUnitIndex = index
                break
            end
        end

        if M.SelectedUnitIndex == 0 and previousID ~= "" then
            for index, entry in ipairs(entries) do
                if entry.ID == previousID then
                    M.SelectedUnitIndex = index
                    break
                end
            end
        end

        if M.SelectedUnitIndex == 0 and #entries > 0 then
            M.SelectedUnitIndex = 1
        end

        local selected = entries[M.SelectedUnitIndex]

        Config.selectedUnitUID = selected and selected.UID or ""
        Config.selectedUnitID = selected and selected.ID or ""
        markDirty()

        return #entries
    end

    function M:GetSelectedUnit()
        local entry = M.Units[M.SelectedUnitIndex]

        if entry and entry.UID == Config.selectedUnitUID then
            return entry
        end

        self:RefreshUnits()
        return M.Units[M.SelectedUnitIndex]
    end

    function M:CycleUnit(direction)
        if #M.Units == 0 then
            self:RefreshUnits()
        end

        if #M.Units == 0 then
            return false, "No units found"
        end

        local index = M.SelectedUnitIndex + direction

        if index < 1 then
            index = #M.Units
        elseif index > #M.Units then
            index = 1
        end

        M.SelectedUnitIndex = index

        local selected = M.Units[index]
        Config.selectedUnitUID = selected.UID
        Config.selectedUnitID = selected.ID
        markDirty()

        return true, selected.Name
    end

    function M:CycleLine(direction)
        local status = getStatus()
        local maximum = math.max(
            1,
            math.min(7, tonumber(status.Lanes) or 1)
        )

        local nextLine = Config.selectedLine + direction

        if nextLine < 1 then
            nextLine = maximum
        elseif nextLine > maximum then
            nextLine = 1
        end

        Config.selectedLine = nextLine
        markDirty()

        return nextLine
    end

    function M:SetLine(lineNumber)
        local status = getStatus()
        local maximum = math.max(
            1,
            math.min(7, tonumber(status.Lanes) or 1)
        )

        Config.selectedLine = math.floor(
            clamp(lineNumber or 1, 1, maximum)
        )
        markDirty()
        return Config.selectedLine
    end

    function M:SetAutoFill(enabled)
        enabled = enabled == true

        M.AutoFillToken = M.AutoFillToken + 1
        M.AutoFill = enabled
        Config.autoFill = enabled
        markDirty()

        if not enabled then
            M.LastAction = "Auto fill stopped"
            return true, M.LastAction
        end

        self:RefreshUnits()

        if not self:GetSelectedUnit() then
            M.AutoFill = false
            Config.autoFill = false
            markDirty()
            M.LastError = "Choose a filler pet first"
            return false, M.LastError
        end

        local token = M.AutoFillToken
        M.LastError = nil
        M.LastAction = "Auto fill started"

        task.spawn(function()
            while C.IsAlive()
                and M.AutoFill
                and M.AutoFillToken == token
            do
                if not M.Busy then
                    local status = getStatus()
                    local maximum = math.max(
                        1,
                        math.min(7, tonumber(status.Lanes) or 1)
                    )

                    if M.FillCursor < 1 or M.FillCursor > maximum then
                        M.FillCursor = 1
                    end

                    Config.selectedLine = M.FillCursor
                    markDirty()

                    local success, detail = M:FillLine(true, token)

                    if not M.AutoFill or M.AutoFillToken ~= token then
                        break
                    end

                    M.FillCursor = M.FillCursor + 1
                    if M.FillCursor > maximum then
                        M.FillCursor = 1
                    end

                    if success then
                        task.wait(0.10)
                    else
                        M.LastError = tostring(detail or "Could not fill line")
                        task.wait(0.40)
                    end
                else
                    task.wait(0.15)
                end
            end
        end)

        return true, M.LastAction
    end

    function M:ChangeQuantity(direction)
        Config.quantity = math.floor(
            clamp(Config.quantity + direction, 1, 25)
        )
        markDirty()
        return Config.quantity
    end

    function M:AddSelectedToPattern()
        local selected = self:GetSelectedUnit()

        if not selected then
            return false, "Choose a tower/pet first"
        end

        table.insert(Config.pattern, {
            uid = selected.UID,
            id = selected.ID,
            name = selected.Name,
            count = Config.quantity,
        })

        markDirty()
        M.PatternCursor = 1
        M.LastAction = string.format(
            "Added %s x%d to pattern",
            selected.Name,
            Config.quantity
        )

        return true, M.LastAction
    end

    function M:ClearPattern()
        Config.pattern = {}
        M.PatternCursor = 1
        markDirty()
        M.LastAction = "Placement pattern cleared"
        return true, M.LastAction
    end

    function M:GetPatternText()
        if #Config.pattern == 0 then
            return "Pattern: none — add one or more tower/pet entries"
        end

        local pieces = {}

        for _, entry in ipairs(Config.pattern) do
            table.insert(
                pieces,
                tostring(entry.name or entry.id or "Unit")
                    .. " x"
                    .. tostring(entry.count or 1)
            )
        end

        return "Pattern: " .. table.concat(pieces, "  →  ")
    end

    local function buildPatternSequence()
        local sequence = {}

        for _, patternEntry in ipairs(Config.pattern) do
            local count = math.floor(
                clamp(patternEntry.count or 1, 1, 25)
            )

            for _ = 1, count do
                table.insert(sequence, patternEntry)
            end
        end

        if #sequence == 0 then
            local selected = M:GetSelectedUnit()

            if selected then
                table.insert(sequence, {
                    uid = selected.UID,
                    id = selected.ID,
                    name = selected.Name,
                    count = 1,
                })
            end
        end

        return sequence
    end

    local function nextUsablePatternUnit(sequence, placed)
        if #sequence == 0 then
            return nil
        end

        for _ = 1, #sequence do
            if M.PatternCursor > #sequence then
                M.PatternCursor = 1
            end

            local patternEntry = sequence[M.PatternCursor]
            M.PatternCursor = M.PatternCursor + 1

            local unit = unitByUID(patternEntry.uid)

            if unit then
                local placedCount = countPlacedUID(
                    unit.UID,
                    placed
                )

                if placedCount < unit.Amount then
                    return unit
                end
            end
        end

        return nil
    end

    local function placeAtCandidate(unit, candidate, world, placedCount)
        local localCFrame =
            world.CFrame:ToObjectSpace(candidate.CFrame)

        local ok, success, reason = pcall(
            C.Network.Invoke,
            "WD_Attach",
            unit.UID,
            localCFrame
        )

        if not ok then
            return false, tostring(success)
        end

        if success ~= true then
            return false, tostring(
                reason or "Unit placement rejected"
            )
        end

        if not waitForPlacedIncrease(placedCount, 1.15) then
            return false,
                "Placement was accepted but did not confirm"
        end

        return true
    end

    function M:PlaceOne()
        if M.Busy then
            return false, "Line tools are already running"
        end

        M.Busy = true
        M.LastError = nil

        local ok, success, detail = xpcall(function()
            self:RefreshUnits()

            local sequence = buildPatternSequence()
            if #sequence == 0 then
                return false, "No placement pattern or selected unit"
            end

            local placed, world = getPlaced()
            if not world then
                return false, "Garden combat world is not active"
            end

            local unit = nextUsablePatternUnit(
                sequence,
                placed
            )

            if not unit then
                return false,
                    "No available copies remain for the pattern"
            end

            local candidates, errorMessage =
                generateCandidates(
                    unit.Item,
                    Config.selectedLine
                )

            if errorMessage then
                return false, errorMessage
            end

            local lastReason = nil
            local attempts = 0

            for _, candidate in ipairs(candidates) do
                if candidateIsFree(
                    unit.Item,
                    candidate,
                    placed
                ) then
                    attempts = attempts + 1

                    local placedCount = #placed
                    local placedOK, placedDetail =
                        placeAtCandidate(
                            unit,
                            candidate,
                            world,
                            placedCount
                        )

                    if placedOK then
                        M.LastError = nil
                        M.LastAction = string.format(
                            "Placed %s on line %d",
                            unit.Name,
                            Config.selectedLine
                        )
                        return true, M.LastAction
                    end

                    lastReason = placedDetail
                    task.wait(0.04)

                    if attempts >= 60 then
                        break
                    end
                end
            end

            return false,
                lastReason
                or "Server found no usable position on this line"
        end, debug.traceback)

        M.Busy = false

        if not ok then
            M.LastError = tostring(success)
            return false, tostring(success)
        end

        if success ~= true then
            M.LastError = tostring(detail)
        end

        return success, detail
    end

    function M:FillLine(selectedOnly, autoToken)
        if M.Busy then
            return false, "Line tools are already running"
        end

        M.Busy = true
        M.LastError = nil

        local ok, success, detail = xpcall(function()
            self:RefreshUnits()

            local sequence

            if selectedOnly then
                local selected = self:GetSelectedUnit()
                sequence = selected and {
                    {
                        uid = selected.UID,
                        id = selected.ID,
                        name = selected.Name,
                        count = 1,
                    },
                } or {}
            else
                sequence = buildPatternSequence()
            end

            if #sequence == 0 then
                return false,
                    selectedOnly
                    and "Choose a filler pet first"
                    or "Choose a pet first"
            end

            local placed, world = getPlaced()
            if not world then
                return false, "Garden combat world is not active"
            end

            local placedTotal = 0
            local lastReason = nil

            for _ = 1, 100 do
                if autoToken
                    and (
                        not M.AutoFill
                        or M.AutoFillToken ~= autoToken
                    )
                then
                    lastReason = "Auto fill stopped"
                    break
                end

                local unit = nextUsablePatternUnit(
                    sequence,
                    placed
                )

                if not unit then
                    lastReason =
                        "No available copies remain for the pattern"
                    break
                end

                local candidates, errorMessage =
                    generateCandidates(
                        unit.Item,
                        Config.selectedLine
                    )

                if errorMessage then
                    lastReason = errorMessage
                    break
                end

                local placedThisCycle = false
                local attempted = 0

                for _, candidate in ipairs(candidates) do
                    if autoToken
                        and (
                            not M.AutoFill
                            or M.AutoFillToken ~= autoToken
                        )
                    then
                        lastReason = "Auto fill stopped"
                        break
                    end

                    if candidateIsFree(
                        unit.Item,
                        candidate,
                        placed
                    ) then
                        attempted = attempted + 1

                        local beforeCount = #placed
                        local placedOK, placedDetail =
                            placeAtCandidate(
                                unit,
                                candidate,
                                world,
                                beforeCount
                            )

                        if placedOK then
                            placedThisCycle = true
                            placedTotal = placedTotal + 1
                            M.LastError = nil

                            task.wait(0.12)
                            placed = getPlaced()
                            break
                        end

                        lastReason = placedDetail
                        task.wait(0.01)

                        if attempted >= 60 then
                            break
                        end
                    end
                end

                if not placedThisCycle then
                    lastReason =
                        lastReason
                        or "Server found no remaining usable position"
                    break
                end
            end

            if placedTotal > 0 then
                -- Reaching the server's real limit after placing units is a
                -- successful fill, not a red warning.
                M.LastError = nil
                M.LastAction = string.format(
                    "Filled line %d with %d units",
                    Config.selectedLine,
                    placedTotal
                )
                return true, M.LastAction
            end

            return false, lastReason or "No units were placed"
        end, debug.traceback)

        M.Busy = false

        if not ok then
            M.LastError = tostring(success)
            return false, tostring(success)
        end

        if success ~= true then
            M.LastError = tostring(detail)
        end

        return success, detail
    end

    function M:StopCleaning()
        if not M.Cleaning then
            return false, "Nothing is being cleaned"
        end

        M.CleanToken = M.CleanToken + 1
        M.Cleaning = false
        M.LastError = nil
        M.LastAction = "Cleaning stopped"
        return true, M.LastAction
    end

    function M:CleanLine(lineNumber)
        if M.Busy then
            return false, "Line tools are already running"
        end

        if lineNumber ~= nil then
            self:SetLine(lineNumber)
        end

        M.Busy = true
        M.Cleaning = true
        M.CleanToken = M.CleanToken + 1
        local cleanToken = M.CleanToken
        M.LastError = nil

        local ok, success, detail = xpcall(function()
            local entries = getLineEntries(Config.selectedLine)

            if #entries == 0 then
                return false, "Selected line is already empty"
            end

            local removed = 0
            local lastReason = nil

            for _, entry in ipairs(entries) do
                if not M.Cleaning or M.CleanToken ~= cleanToken then
                    return removed > 0, "Cleaning stopped"
                end

                if entry.ID ~= nil then
                    local callOK, callSuccess, reason = pcall(
                        C.Network.Invoke,
                        "OR_Detach",
                        entry.ID
                    )

                    if not callOK then
                        lastReason = tostring(callSuccess)
                        break
                    end

                    if callSuccess == true then
                        removed = removed + 1
                    else
                        lastReason = tostring(reason or "Remove rejected")
                    end

                    task.wait(0.07)
                end
            end

            if removed > 0 then
                M.LastAction = string.format(
                    "Cleaned line %d — removed %d units",
                    Config.selectedLine,
                    removed
                )
                return true, M.LastAction
            end

            return false, lastReason or "No units were removed"
        end, debug.traceback)

        if M.CleanToken == cleanToken then
            M.Cleaning = false
        end
        M.Busy = false

        if not ok then
            M.LastError = tostring(success)
            return false, tostring(success)
        end

        if success ~= true and detail ~= "Cleaning stopped" then
            M.LastError = tostring(detail)
        end

        return success, detail
    end

    function M:CleanAllLines()
        if M.Busy then
            return false, "Line tools are already running"
        end

        self:SetAutoFill(false)
        M.Busy = true
        M.Cleaning = true
        M.CleanToken = M.CleanToken + 1
        local cleanToken = M.CleanToken
        M.LastError = nil

        local ok, success, detail = xpcall(function()
            local status = getStatus()
            local maximum = math.max(
                1,
                math.min(7, tonumber(status.Lanes) or 1)
            )
            local byID = {}

            for lineNumber = 1, maximum do
                for _, entry in ipairs(getLineEntries(lineNumber)) do
                    if entry.ID ~= nil then
                        byID[tostring(entry.ID)] = entry
                    end
                end
            end

            local total = 0
            for _ in pairs(byID) do
                total = total + 1
            end

            if total == 0 then
                return false, "All lines are already empty"
            end

            local removed = 0
            local lastReason = nil

            for _, entry in pairs(byID) do
                if not M.Cleaning or M.CleanToken ~= cleanToken then
                    return removed > 0, "Cleaning stopped"
                end

                local callOK, callSuccess, reason = pcall(
                    C.Network.Invoke,
                    "OR_Detach",
                    entry.ID
                )

                if not callOK then
                    lastReason = tostring(callSuccess)
                    break
                end

                if callSuccess == true then
                    removed = removed + 1
                else
                    lastReason = tostring(reason or "Remove rejected")
                end

                task.wait(0.07)
            end

            if removed > 0 then
                M.LastAction = string.format(
                    "Cleaned all lines — removed %d units",
                    removed
                )
                return true, M.LastAction
            end

            return false, lastReason or "No units were removed"
        end, debug.traceback)

        if M.CleanToken == cleanToken then
            M.Cleaning = false
        end
        M.Busy = false

        if not ok then
            M.LastError = tostring(success)
            return false, tostring(success)
        end

        if success ~= true and detail ~= "Cleaning stopped" then
            M.LastError = tostring(detail)
        end

        return success, detail
    end

    function M:GetView()
        local status = getStatus()
        local selected = self:GetSelectedUnit()
        local lineEntries = getLineEntries(
            Config.selectedLine
        )

        return {
            available = M.Available,
            error = M.Error,
            line = Config.selectedLine,
            maxLine = math.max(
                1,
                math.min(7, tonumber(status.Lanes) or 1)
            ),
            selectedIndex = M.SelectedUnitIndex,
            unitCount = #M.Units,
            unitName = selected and selected.Name or "Choose a filler pet",
            unitAmount = selected and selected.Amount or 0,
            quantity = Config.quantity,
            pattern = self:GetPatternText(),
            unitsOnLine = #lineEntries,
            busy = M.Busy,
            cleaning = M.Cleaning,
            autoFill = M.AutoFill,
            lastAction = M.LastAction,
            lastError = M.LastError,
        }
    end

    M.Available = TowerItem ~= nil
    if not M.Available then
        M.Error = "Line tools are unavailable"
    end

    M:RefreshUnits()
    return M
end
]====]

    local compiled, compileError = compiler(
        moduleSource,
        "@SliceHub_PS99_GardenLineTools"
    )

    if not compiled then
        fallback.Error = "Line tools error: " .. tostring(compileError)
        return fallback
    end

    local okFactory, factory = pcall(compiled)
    if not okFactory or type(factory) ~= "function" then
        fallback.Error = "Line tools error: " .. tostring(factory)
        return fallback
    end

    local okModule, module = pcall(factory, {
        Network = Network,
        ClientTower = ClientTower,
        ItemsFolder = ItemsFolder,
        PvCombatCmdsFolder = PvCombatCmdsFolder,
        Config = Config,
        RequireModule = requireModule,
        MarkDirty = markConfigDirty,
        GetGardenPlot = getGardenPlot,
        GetGardenStatus = getGardenStatus,
        GetLocalTowerWorld = getLocalTowerWorld,
        IsAlive = function()
            return Runtime.Alive == true
        end,
    })

    if not okModule or type(module) ~= "table" then
        fallback.Error = "Line tools error: " .. tostring(module)
        return fallback
    end

    return module
end)()

function GardenAutomation:GetPlacedTowerEntries()
    local entries = {}
    local world = getLocalTowerWorld()

    if not world or not ClientTower or type(ClientTower.All) ~= "function" then
        return entries, world
    end

    local ok, towers = pcall(ClientTower.All, world)
    if not ok or type(towers) ~= "table" then
        return entries, world
    end

    for _, tower in ipairs(towers) do
        local okID, placementID = pcall(tower.GetId, tower)
        local okItem, item = pcall(tower.GetItem, tower)

        if okID and placementID ~= nil then
            local numericID = tonumber(placementID)
            local itemName = "Garden Unit"
            local itemUID = ""

            if okItem and type(item) == "table" then
                itemName = tostring(itemMethod(item, "GetName", itemName))
                itemUID = tostring(itemMethod(item, "GetUID", ""))
            end

            table.insert(entries, {
                Tower = tower,
                PlacementID = numericID or placementID,
                SortID = numericID or math.huge,
                Name = itemName,
                UID = itemUID,
            })
        end
    end

    table.sort(entries, function(left, right)
        if left.SortID ~= right.SortID then
            return left.SortID < right.SortID
        end

        if left.Name ~= right.Name then
            return left.Name < right.Name
        end

        return tostring(left.PlacementID) < tostring(right.PlacementID)
    end)

    return entries, world
end

function GardenAutomation:IsReinforceRateLimit(reason)
    local text = lower(reason)
    return string.find(text, "too fast", 1, true) ~= nil
        or string.find(text, "too quickly", 1, true) ~= nil
        or string.find(text, "rate limit", 1, true) ~= nil
end

function GardenAutomation:IsReinforceMaxed(reason)
    local text = lower(reason)
    return string.find(text, "max", 1, true) ~= nil
        or string.find(text, "fully", 1, true) ~= nil
        or string.find(text, "highest level", 1, true) ~= nil
end

function GardenAutomation:IsReinforceUnavailable(reason)
    local text = lower(reason)
    local terms = {
        "not enough",
        "cannot afford",
        "can't afford",
        "insufficient",
        "unavailable",
        "does not exist",
        "doesn't exist",
        "not found",
        "invalid",
    }

    for _, term in ipairs(terms) do
        if string.find(text, term, 1, true) then
            return true
        end
    end

    return false
end

function GardenAutomation:AdvanceReinforceCursor(total)
    total = math.max(0, math.floor(tonumber(total) or 0))

    if total <= 0 then
        self.ReinforceCursor = 1
        return
    end

    self.ReinforceCursor = self.ReinforceCursor + 1
    if self.ReinforceCursor > total then
        self.ReinforceCursor = 1
    end
end

function GardenAutomation:ReinforceOneUnit()
    local entries, world = self:GetPlacedTowerEntries()

    if not world then
        self.ReinforceLastReason = "Garden combat world is not active"
        self.LastAction = "Waiting for Garden combat world"
        return false, self.ReinforceLastReason, self.ReinforceNoUnitsDelay
    end

    if #entries == 0 then
        self.ReinforceCursor = 1
        self.ReinforceLastReason = "No placed Garden units"
        self.LastAction = "Waiting for placed Garden units"
        return false, self.ReinforceLastReason, self.ReinforceNoUnitsDelay
    end

    if self.ReinforceCursor < 1 or self.ReinforceCursor > #entries then
        self.ReinforceCursor = 1
    end

    local now = os.clock()
    local selected = nil
    local selectedIndex = nil

    for offset = 0, #entries - 1 do
        local index = ((self.ReinforceCursor - 1 + offset) % #entries) + 1
        local entry = entries[index]
        local blockedUntil = tonumber(
            self.ReinforceBlockedUntil[tostring(entry.PlacementID)]
        ) or 0

        if blockedUntil <= now then
            selected = entry
            selectedIndex = index
            break
        end
    end

    if not selected then
        self.ReinforceLastReason = "All placed units are cooling down"
        self.LastAction = "Placed units are cooling down"
        return false, self.ReinforceLastReason, self.ReinforceUnavailableDelay
    end

    self.ReinforceCursor = selectedIndex
    self.ReinforceLastTowerID = selected.PlacementID
    self.ReinforceLastTowerName = selected.Name
    self.Stats.ReinforceAttempts = self.Stats.ReinforceAttempts + 1

    local ok, success, reason, newLevel = pcall(
        Network.Invoke,
        "EK_Promote",
        selected.PlacementID
    )

    self:AdvanceReinforceCursor(#entries)

    if not ok then
        self.Stats.Errors = self.Stats.Errors + 1
        self.ReinforceLastReason = tostring(success)
        self.LastError = self.ReinforceLastReason
        self.LastAction = "Reinforce request failed"

        return false,
            self.ReinforceLastReason,
            self.ReinforceUnavailableDelay
    end

    if success == true then
        local level = tonumber(newLevel)

        self.Stats.ReinforceUpgrades = self.Stats.ReinforceUpgrades + 1
        self.ReinforceLastLevel = level or newLevel
        self.ReinforceLastReason = nil
        self.LastError = nil
        self.LastAction = string.format(
            "Reinforced %s%s",
            tostring(selected.Name),
            level and (" to level " .. tostring(level)) or ""
        )

        self.ReinforceBlockedUntil[tostring(selected.PlacementID)] = nil

        return true,
            self.LastAction,
            self.ReinforceSuccessDelay
    end

    local reasonText = tostring(
        reason
        or success
        or "Reinforcement rejected"
    )

    self.ReinforceLastReason = reasonText
    self.LastError = reasonText

    if self:IsReinforceRateLimit(reasonText) then
        self.Stats.ReinforceRateLimits =
            self.Stats.ReinforceRateLimits + 1
        self.LastAction = "Reinforce rate limited; backing off"

        return false,
            reasonText,
            self.ReinforceRateLimitDelay
    end

    if self:IsReinforceMaxed(reasonText) then
        self.Stats.ReinforceMaxed = self.Stats.ReinforceMaxed + 1
        self.ReinforceBlockedUntil[tostring(selected.PlacementID)] = now + 30
        self.LastAction = tostring(selected.Name) .. " appears fully reinforced"

        return false,
            reasonText,
            self.ReinforceUnavailableDelay
    end

    if self:IsReinforceUnavailable(reasonText) then
        self.Stats.ReinforceUnavailable =
            self.Stats.ReinforceUnavailable + 1
        self.ReinforceBlockedUntil[tostring(selected.PlacementID)] = now + 4
        self.LastAction = "Reinforce unavailable: " .. tostring(selected.Name)

        return false,
            reasonText,
            self.ReinforceUnavailableDelay
    end

    self.Stats.ReinforceUnavailable =
        self.Stats.ReinforceUnavailable + 1
    self.ReinforceBlockedUntil[tostring(selected.PlacementID)] = now + 2
    self.LastAction = "Reinforce rejected: " .. tostring(selected.Name)

    return false,
        reasonText,
        self.ReinforceUnavailableDelay
end

local function getPlacedTowerUIDs()
    local output = {}
    local world = getLocalTowerWorld()

    if not world or not ClientTower or type(ClientTower.All) ~= "function" then
        return output, world
    end

    local ok, towers = pcall(ClientTower.All, world)
    if not ok or type(towers) ~= "table" then
        return output, world
    end

    for _, tower in ipairs(towers) do
        local okItem, item = pcall(tower.GetItem, tower)
        if okItem and type(item) == "table" then
            local uid = tostring(itemMethod(item, "GetUID", ""))
            if uid ~= "" then
                output[uid] = true
            end
        end
    end

    return output, world
end

local function recordCurrentUnitLayout()
    local placed, world = getPlacedTowerUIDs()

    if not world or not ClientTower or type(ClientTower.All) ~= "function" then
        setNotice("No local Garden tower-defense world is active.", "error")
        return false
    end

    local ok, towers = pcall(ClientTower.All, world)
    if not ok or type(towers) ~= "table" then
        setNotice("Could not read placed Garden units.", "error")
        return false
    end

    local layout = {}

    for _, tower in ipairs(towers) do
        local okItem, item = pcall(tower.GetItem, tower)
        local okCFrame, worldCFrame = pcall(tower.GetCFrame, tower)

        if okItem and okCFrame and type(item) == "table" then
            local uid = tostring(itemMethod(item, "GetUID", ""))
            local name = tostring(itemMethod(item, "GetName", "Garden Unit"))

            if uid ~= "" and typeof(worldCFrame) == "CFrame" then
                local localCFrame = world.CFrame:ToObjectSpace(worldCFrame)

                table.insert(layout, {
                    uid = uid,
                    name = name,
                    cframe = {localCFrame:GetComponents()},
                })
            end
        end
    end

    table.sort(layout, function(left, right)
        local leftCF = left.cframe or {}
        local rightCF = right.cframe or {}

        if (leftCF[3] or 0) ~= (rightCF[3] or 0) then
            return (leftCF[3] or 0) < (rightCF[3] or 0)
        end

        return (leftCF[1] or 0) < (rightCF[1] or 0)
    end)

    GardenAutomation.UnitLayout = layout
    GardenAutomation.UnitLayoutUserId = LocalPlayer.UserId

    Config.event.garden.unitLayout = deepCopy(layout)
    Config.event.garden.unitLayoutUserId = LocalPlayer.UserId
    markConfigDirty()
    saveConfig(true)

    setNotice(
        "Recorded " .. tostring(#layout) .. " Garden unit placements.",
        #layout > 0 and "success" or "info"
    )

    if refreshEventUI then
        refreshEventUI()
    end

    return true
end

local function clearUnitLayout()
    GardenAutomation.UnitLayout = {}
    GardenAutomation.UnitLayoutUserId = 0

    Config.event.garden.unitLayout = {}
    Config.event.garden.unitLayoutUserId = 0
    markConfigDirty()
    saveConfig(true)

    setNotice("Saved Garden unit layout cleared.", "info")

    if refreshEventUI then
        refreshEventUI()
    end
end

local function restoreOneUnit()
    if GardenAutomation.UnitLayoutUserId ~= LocalPlayer.UserId then
        return false, "Saved layout belongs to another account"
    end

    if #GardenAutomation.UnitLayout == 0 then
        return false, "No saved unit layout"
    end

    local placed, world = getPlacedTowerUIDs()
    if not world then
        return false, "Garden combat world is not active"
    end

    for _, entry in ipairs(GardenAutomation.UnitLayout) do
        if not placed[entry.uid] and type(entry.cframe) == "table" then
            local okCFrame, localCFrame = pcall(
                CFrame.new,
                table.unpack(entry.cframe, 1, 12)
            )

            if not okCFrame then
                return false, "Saved unit CFrame is invalid"
            end

            local ok, success, reason = pcall(
                Network.Invoke,
                "WD_Attach",
                entry.uid,
                localCFrame
            )

            if not ok then
                return false, tostring(success)
            end

            if success == true then
                GardenAutomation.Stats.UnitsRestored =
                    GardenAutomation.Stats.UnitsRestored + 1
                GardenAutomation.LastAction =
                    "Restored " .. tostring(entry.name or "Garden unit")
                return true
            end

            return false, tostring(reason or "Unit placement rejected")
        end
    end

    return false, "Layout already restored"
end

local function gardenFeatureEnabled(name)
    if name == "AutoUpgrades"
        and GardenAutomation:SelectedUpgradeCount() <= 0
    then
        return false
    end

    if GardenAutomation.MissionDirector
        and GardenAutomation.MissionOverrides[name] == true
    then
        return true
    end

    if GardenAutomation.FullCampaign then
        return true
    end

    return GardenAutomation[name] == true
end

local GARDEN_CONFIG_KEYS = {
    AutoCollect = "autoCollect",
    AutoPlant = "autoPlant",
    AutoUnlockLanes = "autoUnlockLanes",
    AutoBuyPlots = "autoBuyPlots",
    AutoUpgrades = "autoUpgrades",
    AutoRegrow = "autoRegrow",
    AutoRestoreUnits = "autoRestoreUnits",
    AutoMerchant = "autoMerchant",
    AutoReinforce = "autoReinforce",
    FullCampaign = "fullCampaign",
    MissionDirector = "missionDirector",
    AutoSuperRebirth = "autoSuperRebirth",
}

local function setGardenFeature(name, enabled)
    enabled = enabled == true

    if enabled and PREMIUM_GARDEN_FEATURES[name] then
        if not requirePremium(
            name == "AutoRegrow"
                and "Auto Rebirth"
                or name:gsub("(%u)", " %1"):gsub("^ ", "")
        ) then
            return false
        end
    end

    GardenAutomation[name] = enabled

    if name == "AutoSuperRebirth" and enabled then
        GardenAutomation.MissionDirector = true
        Config.event.garden.missionDirector = true
        GardenAutomation.Next.Mission = 0
        GardenAutomation.Next.SuperRebirth = 0
    elseif name == "MissionDirector" and not enabled
        and GardenAutomation.AutoSuperRebirth
    then
        GardenAutomation.AutoSuperRebirth = false
        Config.event.garden.autoSuperRebirth = false
        GardenAutomation:ClearMissionOverrides()
    elseif name == "MissionDirector" then
        GardenAutomation.Next.Mission = 0
        if not enabled then
            GardenAutomation:ClearMissionOverrides()
        end
    end

    local configKey = GARDEN_CONFIG_KEYS[name]
    if configKey then
        Config.event.garden[configKey] = enabled
        markConfigDirty()
    end

    if name == "FullCampaign" and enabled then
        GardenAutomation.Suspended = false
        setNotice(
            "Auto Everything is on.",
            "success"
        )
    else
        setNotice(
            (
                name == "AutoRegrow"
                    and "Auto Rebirth"
                    or name:gsub("(%u)", " %1"):gsub("^ ", "")
            )
                .. (enabled and " enabled." or " disabled."),
            enabled and "success" or "info"
        )
    end

    if refreshEventUI then
        refreshEventUI()
    end

    return true
end

local function syncGardenAutomationFromConfig()
    GardenAutomation.AutoCollect = Config.event.garden.autoCollect == true
    GardenAutomation.AutoPlant = Config.event.garden.autoPlant == true
    GardenAutomation.AutoUnlockLanes =
        IS_PREMIUM and Config.event.garden.autoUnlockLanes == true
    GardenAutomation.AutoBuyPlots =
        IS_PREMIUM and Config.event.garden.autoBuyPlots == true
    GardenAutomation.AutoUpgrades =
        IS_PREMIUM and Config.event.garden.autoUpgrades == true
    GardenAutomation.UpgradeSelection =
        type(Config.event.garden.upgradeSelection) == "table"
        and deepCopy(Config.event.garden.upgradeSelection)
        or {}
    GardenAutomation.AutoRegrow =
        IS_PREMIUM and Config.event.garden.autoRegrow == true
    GardenAutomation.AutoRestoreUnits =
        IS_PREMIUM and Config.event.garden.autoRestoreUnits == true
    GardenAutomation.AutoMerchant =
        Config.event.garden.autoMerchant == true
    GardenAutomation.AutoReinforce =
        Config.event.garden.autoReinforce == true
    GardenAutomation.FullCampaign =
        IS_PREMIUM and Config.event.garden.fullCampaign == true
    GardenAutomation.MissionDirector =
        IS_PREMIUM and Config.event.garden.missionDirector == true
    GardenAutomation.AutoSuperRebirth =
        IS_PREMIUM and Config.event.garden.autoSuperRebirth == true
    GardenAutomation.AutoCraftSelected =
        IS_PREMIUM and Config.event.crafting.auto == true
    GardenAutomation.CraftSelection =
        type(Config.event.crafting.selection) == "table"
        and deepCopy(Config.event.crafting.selection)
        or {}
    GardenAutomation.AutoMaxLuck =
        IS_PREMIUM and Config.event.luck.auto == true
    GardenAutomation.LuckSelection =
        type(Config.event.luck.selection) == "table"
        and deepCopy(Config.event.luck.selection)
        or {}

    if GardenAutomation.AutoSuperRebirth then
        GardenAutomation.MissionDirector = true
    end
    GardenAutomation.Next.Mission = 0
    GardenAutomation.Next.SuperRebirth = 0
    GardenAutomation.Next.Craft = 0
    GardenAutomation.Next.Luck = 0
    GardenAutomation:ClearMissionOverrides()

    GardenAutomation.UnitLayout =
        type(Config.event.garden.unitLayout) == "table"
        and Config.event.garden.unitLayout
        or {}
    GardenAutomation.UnitLayoutUserId =
        tonumber(Config.event.garden.unitLayoutUserId) or 0

    GardenAutomation.SelectedSeedUID =
        Config.event.garden.selectedSeedUID ~= ""
        and Config.event.garden.selectedSeedUID
        or nil
    GardenAutomation.SelectedSeedID =
        Config.event.garden.selectedSeedID ~= ""
        and Config.event.garden.selectedSeedID
        or nil

    refreshGardenSeeds()

    if refreshEventUI then
        refreshEventUI()
    end
end

local function runGardenAction(label, callback)
    if GardenAutomation.Busy or GardenAutomation.Suspended then
        return false, "Busy"
    end

    GardenAutomation.Busy = true

    local ok, success, detail = xpcall(callback, debug.traceback)

    GardenAutomation.Busy = false

    if not ok then
        GardenAutomation.Stats.Errors = GardenAutomation.Stats.Errors + 1
        GardenAutomation.LastError = tostring(success)
        GardenAutomation.LastAction = label .. " failed"
        appendLog("GARDEN_ERROR", label .. " | " .. tostring(success))

        if refreshEventUI then
            refreshEventUI()
        end

        return false, tostring(success)
    end

    if success == true then
        appendLog("GARDEN_ACTION", label .. " | success")
    elseif detail and detail ~= "Nothing ready" then
        GardenAutomation.LastError = tostring(detail)
    end

    if refreshEventUI then
        refreshEventUI()
    end

    return success, detail
end

function GardenAutomation:AdvanceMerchantSlot()
    self.MerchantSlot =
        math.floor(
            clamp(
                tonumber(self.MerchantSlot) or 1,
                1,
                self.MerchantMaxSlot
            )
        ) + 1

    if self.MerchantSlot > self.MerchantMaxSlot then
        self.MerchantSlot = 1
        self.Stats.MerchantPasses =
            self.Stats.MerchantPasses + 1
        return true
    end

    return false
end

function GardenAutomation:BuyMerchantStep()
    local slot =
        math.floor(
            clamp(
                tonumber(self.MerchantSlot) or 1,
                1,
                self.MerchantMaxSlot
            )
        )

    self.Stats.MerchantAttempts =
        self.Stats.MerchantAttempts + 1

    local ok, success, reason = pcall(
        Network.Invoke,
        "Merchant_RequestPurchase",
        self.MerchantID,
        slot
    )

    if not ok then
        self.Stats.Errors =
            self.Stats.Errors + 1
        self.LastError = tostring(success)
        self.MerchantLastReason =
            tostring(success)

        local wrapped =
            self:AdvanceMerchantSlot()

        return false,
            "Merchant request error: "
                .. tostring(success),
            wrapped
                and self.MerchantPassCooldown
                or 2
    end

    if success == true then
        self.Stats.MerchantPurchases =
            self.Stats.MerchantPurchases + 1

        self.MerchantLastReason = nil
        self.LastError = nil
        self.LastAction =
            "Bought Farming Merchant slot "
            .. tostring(slot)

        -- Stay on the same slot after a successful purchase.
        -- The next request rechecks authoritative stock and continues
        -- until that slot is sold out, locked, or unaffordable.
        return true,
            self.LastAction,
            self.MerchantSuccessDelay
    end

    local reasonText =
        tostring(
            reason
            or success
            or "Purchase rejected"
        )

    self.MerchantLastReason = reasonText

    if string.find(
        lower(reasonText),
        "too quickly",
        1,
        true
    ) then
        self.Stats.MerchantRateLimits =
            self.Stats.MerchantRateLimits + 1

        self.LastAction =
            "Garden Merchant rate limited; waiting"

        return false,
            reasonText,
            self.MerchantRateLimitDelay
    end

    self.Stats.MerchantRejections =
        self.Stats.MerchantRejections + 1

    local wrapped =
        self:AdvanceMerchantSlot()

    self.LastAction =
        wrapped
        and "Garden Merchant pass complete"
        or (
            "Garden Merchant slot "
            .. tostring(slot)
            .. " unavailable; checking next"
        )

    return false,
        reasonText,
        wrapped
            and self.MerchantPassCooldown
            or self.MerchantNextSlotDelay
end

local function observeGardenStatus()
    local status = getGardenStatus()
    GardenAutomation.LastStatus = status

    if status.Supported then
        if GardenAutomation.LastBossScore == nil then
            GardenAutomation.LastBossScore = status.GardenBossScore
        elseif status.GardenBossScore > GardenAutomation.LastBossScore then
            local difference =
                status.GardenBossScore - GardenAutomation.LastBossScore

            GardenAutomation.Stats.BossesObserved =
                GardenAutomation.Stats.BossesObserved + difference
            GardenAutomation.LastAction =
                "Observed " .. tostring(difference) .. " Garden boss completion"

            appendLog(
                "GARDEN_BOSS",
                string.format(
                    "score %d -> %d",
                    GardenAutomation.LastBossScore,
                    status.GardenBossScore
                )
            )

            GardenAutomation.LastBossScore = status.GardenBossScore
        elseif status.GardenBossScore < GardenAutomation.LastBossScore then
            GardenAutomation.LastBossScore = status.GardenBossScore
        end
    end

    return status
end

local function startGardenWorker()
    GardenAutomation.WorkerToken = GardenAutomation.WorkerToken + 1
    local token = GardenAutomation.WorkerToken

    task.spawn(function()
        while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
            and GardenAutomation.Alive
            and GardenAutomation.WorkerToken == token
        do
            task.wait(0.1)

            local now = os.clock()

            if now >= GardenAutomation.Next.Status then
                GardenAutomation.Next.Status = now + 0.75
                observeGardenStatus()

                if refreshEventUI then
                    refreshEventUI()
                end
            end

            if now >= GardenAutomation.Next.Seeds then
                GardenAutomation.Next.Seeds = now + 3
                refreshGardenSeeds()
            end

            if GardenAutomation.Suspended or GardenAutomation.Busy then
                continue
            end


            if GardenAutomation.AutoCraftSelected
                and now >= GardenAutomation.Next.Craft
            then
                local success, detail = runGardenAction(
                    "Event craft",
                    function()
                        return GardenAutomation:CraftSelectedStep()
                    end
                )
                GardenAutomation.Next.Craft = now + (success and 1.0 or 4.0)
                if success then
                    continue
                end
            end

            if GardenAutomation.AutoMaxLuck
                and now >= GardenAutomation.Next.Luck
            then
                local success, detail = runGardenAction(
                    "Event Luck",
                    function()
                        return GardenAutomation:MaxSelectedLuckStep(false)
                    end
                )
                GardenAutomation.Next.Luck = now + (success and 2.0 or 15.0)
                if success then
                    continue
                end
            end

            local status = GardenAutomation.LastStatus or getGardenStatus()
            if not status.Supported then
                continue
            end

            if (GardenAutomation.MissionDirector
                or GardenAutomation.AutoSuperRebirth)
                and now >= GardenAutomation.Next.Mission
            then
                local mission = GardenAutomation:RefreshMissionState()
                GardenAutomation.Next.Mission = now + 0.75

                if mission.Claimable then
                    local claimed = runGardenAction(
                        "Claim Garden mission",
                        function()
                            return GardenAutomation:ClaimMissionStep()
                        end
                    )
                    GardenAutomation.Next.Mission = now + (claimed and 0.9 or 1.5)
                    if claimed then
                        continue
                    end
                end

                if GardenAutomation.AutoSuperRebirth
                    and mission.Completed
                    and now >= GardenAutomation.Next.SuperRebirth
                then
                    local advanced = runGardenAction(
                        "Super Rebirth",
                        function()
                            return GardenAutomation:TrySuperRebirth()
                        end
                    )
                    GardenAutomation.Next.SuperRebirth =
                        now + (advanced and 8 or 3)
                    if advanced then
                        continue
                    end
                end
            end


            if gardenFeatureEnabled("AutoRegrow")
                and now >= GardenAutomation.Next.Regrow
                and status.RegrowReady
            then
                local success = runGardenAction("Rebirth", regrowOnce)
                GardenAutomation.Next.Regrow =
                    now + (success and 4 or 2)
                continue
            end

            if gardenFeatureEnabled("AutoUnlockLanes")
                and now >= GardenAutomation.Next.Lane
                and status.Lanes < status.MaxLanes
            then
                local success = runGardenAction("Unlock lane", unlockLaneOnce)
                GardenAutomation.Next.Lane =
                    now + (success and 0.8 or 3)
                continue
            end

            if gardenFeatureEnabled("AutoBuyPlots")
                and now >= GardenAutomation.Next.Plot
                and status.OwnedPlots < status.MaxPlots
            then
                local success = runGardenAction("Buy plot", buyPlotOnce)
                GardenAutomation.Next.Plot =
                    now + (success and 0.8 or 3)
                continue
            end

            if gardenFeatureEnabled("AutoRestoreUnits")
                and now >= GardenAutomation.Next.Restore
            then
                local success, detail = runGardenAction(
                    "Restore unit",
                    restoreOneUnit
                )
                GardenAutomation.Next.Restore =
                    now + (success and 0.55 or 2.5)

                if success then
                    continue
                end
            end

            if (GardenAutomation.AutoReinforce
                or (GardenAutomation.MissionDirector
                    and GardenAutomation.MissionOverrides.AutoReinforce == true))
                and now >= GardenAutomation.Next.Reinforce
            then
                GardenAutomation.Busy = true

                local ok,
                    success,
                    detail,
                    nextDelay = xpcall(
                        function()
                            return GardenAutomation:ReinforceOneUnit()
                        end,
                        debug.traceback
                    )

                GardenAutomation.Busy = false

                if not ok then
                    GardenAutomation.Stats.Errors =
                        GardenAutomation.Stats.Errors + 1
                    GardenAutomation.LastError = tostring(success)
                    GardenAutomation.LastAction =
                        "Auto Reinforce step failed"
                    nextDelay = GardenAutomation.ReinforceUnavailableDelay

                    appendLog(
                        "GARDEN_REINFORCE_ERROR",
                        tostring(success)
                    )
                elseif success == true then
                    appendLog(
                        "GARDEN_REINFORCE",
                        tostring(detail)
                    )
                elseif detail and GardenAutomation:IsReinforceRateLimit(detail) then
                    appendLog(
                        "GARDEN_REINFORCE_LIMIT",
                        tostring(detail)
                    )
                end

                GardenAutomation.Next.Reinforce =
                    os.clock()
                    + math.max(
                        0.12,
                        tonumber(nextDelay)
                            or GardenAutomation.ReinforceUnavailableDelay
                    )

                if refreshEventUI then
                    refreshEventUI()
                end

                if success == true then
                    continue
                end
            end

            if gardenFeatureEnabled("AutoPlant")
                and now >= GardenAutomation.Next.Plant
            then
                local success = runGardenAction("Plant seed", plantOneSeed)
                GardenAutomation.Next.Plant =
                    now + (success and 0.65 or 2)
                if success then
                    continue
                end
            end

            if gardenFeatureEnabled("AutoUpgrades")
                and now >= GardenAutomation.Next.Upgrade
            then
                local success = runGardenAction(
                    "Buy Garden upgrade",
                    buyUpgradeOnce
                )
                GardenAutomation.Next.Upgrade =
                    now + (success and 0.85 or 3)
                if success then
                    continue
                end
            end

            if gardenFeatureEnabled("AutoCollect")
                and now >= GardenAutomation.Next.Collect
            then
                runGardenAction("Collect crop", collectOneBed)
                GardenAutomation.Next.Collect = now + 0.4
            end

            if gardenFeatureEnabled("AutoMerchant")
                and now >= GardenAutomation.Next.Merchant
            then
                GardenAutomation.Busy = true

                local ok,
                    success,
                    detail,
                    nextDelay = xpcall(
                        function()
                            return GardenAutomation:BuyMerchantStep()
                        end,
                        debug.traceback
                    )

                GardenAutomation.Busy = false

                if not ok then
                    GardenAutomation.Stats.Errors =
                        GardenAutomation.Stats.Errors + 1
                    GardenAutomation.LastError =
                        tostring(success)
                    GardenAutomation.LastAction =
                        "Garden Merchant step failed"
                    nextDelay = 2

                    appendLog(
                        "GARDEN_MERCHANT_ERROR",
                        tostring(success)
                    )
                elseif success == true then
                    appendLog(
                        "GARDEN_MERCHANT_BUY",
                        tostring(detail)
                    )
                elseif detail
                    and string.find(
                        lower(detail),
                        "too quickly",
                        1,
                        true
                    )
                then
                    appendLog(
                        "GARDEN_MERCHANT_LIMIT",
                        tostring(detail)
                    )
                end

                GardenAutomation.Next.Merchant =
                    os.clock()
                    + math.max(
                        0.2,
                        tonumber(nextDelay) or 1
                    )

                if refreshEventUI then
                    refreshEventUI()
                end
            end
        end
    end)
end

startGardenWorker()

local CoreAutomation = {}

--////////////////////////////////////////////////////////////////////
-- Permanent core automation: Farm, normal Eggs, consumables, rank rewards
--////////////////////////////////////////////////////////////////////

CoreAutomation.PetNetworking = requireModule(
    Client:FindFirstChild("PetNetworking"),
    "Client.PetNetworking",
    true
)
CoreAutomation.PlayerPet = requireModule(
    Client:FindFirstChild("PlayerPet"),
    "Client.PlayerPet",
    true
)
CoreAutomation.BreakableFrontend = requireModule(
    Client:FindFirstChild("BreakableFrontend"),
    "Client.BreakableFrontend",
    true
)
CoreAutomation.MapCmds = requireModule(
    Client:FindFirstChild("MapCmds"),
    "Client.MapCmds",
    true
)
CoreAutomation.ZoneCmds = requireModule(
    Client:FindFirstChild("ZoneCmds"),
    "Client.ZoneCmds",
    true
)
CoreAutomation.TeleportMapCmds = requireModule(
    Client:FindFirstChild("TeleportMapCmds"),
    "Client.TeleportMapCmds",
    true
)
CoreAutomation.FruitCmds = requireModule(
    Client:FindFirstChild("FruitCmds"),
    "Client.FruitCmds",
    true
)
CoreAutomation.PotionCmds = requireModule(
    Client:FindFirstChild("PotionCmds"),
    "Client.PotionCmds",
    true
)
CoreAutomation.UltimateCmds = requireModule(
    Client:FindFirstChild("UltimateCmds"),
    "Client.UltimateCmds",
    true
)
CoreAutomation.MasteryCmds = requireModule(
    Client:FindFirstChild("MasteryCmds"),
    "Client.MasteryCmds",
    true
)
CoreAutomation.FruitItem = requireModule(
    ItemsFolder and ItemsFolder:FindFirstChild("FruitItem"),
    "Items.FruitItem",
    true
)
CoreAutomation.PotionItem = requireModule(
    ItemsFolder and ItemsFolder:FindFirstChild("PotionItem"),
    "Items.PotionItem",
    true
)
CoreAutomation.NormalEggsDirectory = requireModule(
    DirectoryFolder and DirectoryFolder:FindFirstChild("Eggs"),
    "Directory.Eggs",
    true
)
CoreAutomation.RanksDirectory = requireModule(
    DirectoryFolder and DirectoryFolder:FindFirstChild("Ranks"),
    "Directory.Ranks",
    true
)
CoreAutomation.FreeGiftsDirectory = requireModule(
    DirectoryFolder and DirectoryFolder:FindFirstChild("FreeGifts"),
    "Directory.FreeGifts",
    true
)
CoreAutomation.LoginStreakCmds = requireModule(
    Client:FindFirstChild("LoginStreakCmds"),
    "Client.LoginStreakCmds",
    true
)
CoreAutomation.DaycareCmds = requireModule(
    Client:FindFirstChild("DaycareCmds"),
    "Client.DaycareCmds",
    true
)
CoreAutomation.OrbCmds = requireModule(
    Client:FindFirstChild("OrbCmds"),
    "Client.OrbCmds",
    true
)
CoreAutomation.InfinityEggCmds = requireModule(
    Client:FindFirstChild("InfinityEggCmds"),
    "Client.InfinityEggCmds",
    true
)
CoreAutomation.PetItem = requireModule(
    ItemsFolder and ItemsFolder:FindFirstChild("PetItem"),
    "Items.PetItem",
    true
)
CoreAutomation.PetsDirectory = requireModule(
    DirectoryFolder and DirectoryFolder:FindFirstChild("Pets"),
    "Directory.Pets",
    true
)
CoreAutomation.DaycareLoot = requireModule(
    Modules and Modules:FindFirstChild("DaycareLoot"),
    "Modules.DaycareLoot",
    true
)
CoreAutomation.EggsUtil = requireModule(
    UtilFolder and UtilFolder:FindFirstChild("EggsUtil"),
    "Util.EggsUtil",
    true
)
CoreAutomation.ForeverPackCmds = requireModule(
    Client:FindFirstChild("ForeverPackCmds"),
    "Client.ForeverPackCmds",
    true
)
CoreAutomation.TimedRewardsDirectory = requireModule(
    DirectoryFolder and DirectoryFolder:FindFirstChild("TimedRewards"),
    "Directory.TimedRewards",
    true
)

CoreAutomation.ThingsFolder = Workspace:FindFirstChild("__THINGS")
CoreAutomation.BreakablesFolder = CoreAutomation.ThingsFolder and CoreAutomation.ThingsFolder:FindFirstChild("Breakables")
CoreAutomation.OrbsFolder = CoreAutomation.ThingsFolder and CoreAutomation.ThingsFolder:FindFirstChild("Orbs")

CoreAutomation.refreshFarmUI = nil
CoreAutomation.refreshNormalEggUI = nil
CoreAutomation.refreshAutomaticUI = nil
CoreAutomation.refreshRankUI = nil
--//////////////////////////////////////////////////////////////////
-- Farm controller
--//////////////////////////////////////////////////////////////////

CoreAutomation.FarmEngine = {
    Alive = true,
    Running = false,
    Paused = false,
    PauseReason = nil,
    WorkerToken = 0,
    Connections = {},

    AutoFarm = Config.farm.enabled == true,
    AutoTargetCount = true,
    ManualTargetCount = math.floor(clamp(Config.farm.targetCount, 1, 15)),
    PetsPerTarget = math.floor(clamp(Config.farm.petsPerTarget, 1, 12)),
    TargetRadius = 2000,
    PlayerDamage = Config.farm.playerDamage == true,
    CollectOrbs = Config.farm.collectOrbs == true,
    InfSpeedPets = Config.farm.infSpeedPets == true,

    CurrentPets = {},
    CurrentTargets = {},
    KnownOrbs = {},
    PendingOrbIDs = {},
    PendingOrbSet = {},
    DropFolders = {},
    LastDropRescanAt = 0,
    LastAssignmentSignature = nil,
    LastAssignmentAt = 0,
    LastAction = "Stopped",
    LastError = nil,

    AssignmentInterval = 0.85,
    AssignmentKeepAlive = 4.5,
    DamageInterval = 0.085,
    OrbInterval = 0.08,
    UIRefreshInterval = 0.45,
    LastUIRefreshAt = 0,
    OrbRegistry = nil,
    OrbRegistryCheckedAt = 0,
    CurrentJoinMap = {},
    OrbCreateSignal = nil,
    OrbListenerConnection = nil,
    OrbNativeConnection = nil,
    OrbNativeCallback = nil,
    OrbBridgeInstalled = false,
    OrbVisualConnections = {},
    OrbVisualSuppressed = false,
    OrbCleanupScheduled = false,
    HiddenOrbVisuals = setmetatable({}, { __mode = "k" }),

    Stats = {
        AssignmentCalls = 0,
        DamageCalls = 0,
        OrbCalls = 0,
        OrbIDs = 0,
        TargetChanges = 0,
        Errors = 0,
    },
}

function CoreAutomation.permanentRootPart()
    local character = LocalPlayer and LocalPlayer.Character
    if not character then
        return nil
    end
    return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

function CoreAutomation.farmCurrentZone()
    if CoreAutomation.MapCmds and type(CoreAutomation.MapCmds.GetCurrentZone) == "function" then
        local ok, zone = pcall(CoreAutomation.MapCmds.GetCurrentZone)
        if ok then
            return zone
        end
    end
    return nil
end

function CoreAutomation.farmModelPosition(instance)
    if not instance then
        return nil
    end
    if instance:IsA("BasePart") then
        return instance.Position
    end
    if instance:IsA("Model") then
        local ok, pivot = pcall(instance.GetPivot, instance)
        if ok then
            return pivot.Position
        end
    end
    local part = instance:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

function CoreAutomation.farmBreakableUID(instance)
    if not instance then
        return nil
    end
    local values = {
        instance:GetAttribute("BreakableUID"),
        instance:GetAttribute("UID"),
        instance:GetAttribute("BreakableId"),
        instance:GetAttribute("BreakableID"),
        instance.Name,
    }
    for _, value in ipairs(values) do
        if value ~= nil and tonumber(tostring(value)) ~= nil then
            return tostring(value)
        end
    end
    return nil
end

function CoreAutomation.farmEquippedPets()
    local pets = {}
    local seen = {}

    if CoreAutomation.PetNetworking and type(CoreAutomation.PetNetworking.EquippedPets) == "function" then
        local ok, equipped = pcall(CoreAutomation.PetNetworking.EquippedPets)
        if ok and type(equipped) == "table" then
            for euid in pairs(equipped) do
                local value = tostring(euid)
                if not seen[value] then
                    seen[value] = true
                    table.insert(pets, value)
                end
            end
        end
    end

    if #pets == 0 and CoreAutomation.PlayerPet and type(CoreAutomation.PlayerPet.GetByPlayer) == "function" then
        local ok, rendered = pcall(CoreAutomation.PlayerPet.GetByPlayer, LocalPlayer)
        if ok and type(rendered) == "table" then
            for euid in pairs(rendered) do
                local value = tostring(euid)
                if not seen[value] then
                    seen[value] = true
                    table.insert(pets, value)
                end
            end
        end
    end

    table.sort(pets, function(left, right)
        local a, b = tonumber(left), tonumber(right)
        if a and b then
            return a < b
        end
        return left < right
    end)
    return pets
end

function CoreAutomation.farmDesiredTargets(petCount)
    if not CoreAutomation.FarmEngine.AutoTargetCount then
        return math.floor(clamp(CoreAutomation.FarmEngine.ManualTargetCount, 1, 15))
    end
    if petCount <= 0 then
        return 3
    end
    return math.floor(clamp(math.ceil(petCount / CoreAutomation.FarmEngine.PetsPerTarget), 3, 15))
end

function CoreAutomation.farmBreakableInstances()
    local output = {}
    local seen = {}
    CoreAutomation.BreakablesFolder = CoreAutomation.BreakablesFolder or (Workspace:FindFirstChild("__THINGS") and Workspace.__THINGS:FindFirstChild("Breakables"))
    if not CoreAutomation.BreakablesFolder then
        return output
    end

    for _, child in ipairs(CoreAutomation.BreakablesFolder:GetChildren()) do
        local uid = CoreAutomation.farmBreakableUID(child)
        if uid and not seen[uid] then
            seen[uid] = true
            table.insert(output, child)
        else
            for _, nested in ipairs(child:GetChildren()) do
                local nestedUID = CoreAutomation.farmBreakableUID(nested)
                if nestedUID and not seen[nestedUID] then
                    seen[nestedUID] = true
                    table.insert(output, nested)
                end
            end
        end
    end
    return output
end

function CoreAutomation.farmCandidates()
    local root = CoreAutomation.permanentRootPart()
    if not root then
        return {}, "Character root unavailable"
    end

    local zone = CoreAutomation.farmCurrentZone()
    local all = {}
    local inZone = {}

    for _, instance in ipairs(CoreAutomation.farmBreakableInstances()) do
        local uid = CoreAutomation.farmBreakableUID(instance)
        if uid then
            local data = nil
            if CoreAutomation.BreakableFrontend and type(CoreAutomation.BreakableFrontend.Get) == "function" then
                local ok, result = pcall(CoreAutomation.BreakableFrontend.Get, uid)
                if ok then
                    data = result
                end
            end

            local model = type(data) == "table" and rawget(data, "model") or instance
            local position = type(data) == "table" and rawget(data, "position") or CoreAutomation.farmModelPosition(model)
            local health = type(data) == "table" and tonumber(rawget(data, "health")) or nil
            local parentID = type(data) == "table" and rawget(data, "parentID") or nil

            if typeof(position) == "Vector3" and (health == nil or health > 0) then
                local distance = (position - root.Position).Magnitude
                if distance <= CoreAutomation.FarmEngine.TargetRadius then
                    local entry = {
                        UID = uid,
                        Instance = model,
                        Position = position,
                        Distance = distance,
                        ParentID = parentID,
                    }
                    table.insert(all, entry)
                    if zone ~= nil and parentID == zone then
                        table.insert(inZone, entry)
                    end
                end
            end
        end
    end

    local candidates = #inZone > 0 and inZone or all
    table.sort(candidates, function(left, right)
        return left.Distance < right.Distance
    end)

    if #candidates == 0 then
        return {}, "No breakables within " .. tostring(CoreAutomation.FarmEngine.TargetRadius) .. " studs"
    end
    return candidates, nil
end

function CoreAutomation.farmRefreshStableTargets()
    local desired = CoreAutomation.farmDesiredTargets(#CoreAutomation.FarmEngine.CurrentPets)
    local candidates, reason = CoreAutomation.farmCandidates()

    if #candidates == 0 then
        local changed = #CoreAutomation.FarmEngine.CurrentTargets > 0
        CoreAutomation.FarmEngine.CurrentTargets = {}
        return {}, changed, reason
    end

    local byUID = {}
    for _, candidate in ipairs(candidates) do
        byUID[candidate.UID] = candidate
    end

    local slots = {}
    local used = {}
    for slot = 1, desired do
        local previous = CoreAutomation.FarmEngine.CurrentTargets[slot]
        local fresh = previous and byUID[previous.UID] or nil
        if fresh and not used[fresh.UID] then
            slots[slot] = fresh
            used[fresh.UID] = true
        end
    end

    local cursor = 1
    for slot = 1, desired do
        if not slots[slot] then
            while candidates[cursor] and used[candidates[cursor].UID] do
                cursor = cursor + 1
            end
            if candidates[cursor] then
                slots[slot] = candidates[cursor]
                used[candidates[cursor].UID] = true
                cursor = cursor + 1
            end
        end
    end

    local stable = {}
    for slot = 1, desired do
        if slots[slot] then
            table.insert(stable, slots[slot])
        end
    end

    local changed = #stable ~= #CoreAutomation.FarmEngine.CurrentTargets
    if not changed then
        for index, target in ipairs(stable) do
            if not CoreAutomation.FarmEngine.CurrentTargets[index]
                or CoreAutomation.FarmEngine.CurrentTargets[index].UID ~= target.UID
            then
                changed = true
                break
            end
        end
    end

    CoreAutomation.FarmEngine.CurrentTargets = stable
    return stable, changed, nil
end

function CoreAutomation.farmRestorePets()
    if not CoreAutomation.PlayerPet or type(CoreAutomation.PlayerPet.GetByPlayer) ~= "function" then
        return 0
    end
    local character = LocalPlayer.Character
    if not character then
        return 0
    end
    local ok, pets = pcall(CoreAutomation.PlayerPet.GetByPlayer, LocalPlayer)
    if not ok or type(pets) ~= "table" then
        return 0
    end
    local restored = 0
    for _, pet in pairs(pets) do
        if type(pet) == "table" and type(pet.SetTarget) == "function" then
            if pcall(pet.SetTarget, pet, character) then
                restored = restored + 1
            end
        end
    end
    return restored
end

function CoreAutomation.farmSetPaused(paused, reason)
    if CoreAutomation.FarmEngine.Paused == paused then
        CoreAutomation.FarmEngine.PauseReason = paused and reason or nil
        return
    end
    CoreAutomation.FarmEngine.Paused = paused
    CoreAutomation.FarmEngine.PauseReason = paused and reason or nil
    CoreAutomation.FarmEngine.LastAssignmentSignature = nil
    if paused then
        local restored = CoreAutomation.farmRestorePets()
        CoreAutomation.FarmEngine.LastAction = "Paused • restored " .. tostring(restored) .. " pets"
    else
        CoreAutomation.FarmEngine.LastAction = "Resumed"
    end
    if CoreAutomation.refreshFarmUI then
        CoreAutomation.refreshFarmUI()
    end
end

function CoreAutomation.farmAssignmentSignature(pets, targets)
    local values = {table.concat(pets, ",")}
    for _, target in ipairs(targets) do
        table.insert(values, target.UID)
    end
    return table.concat(values, "|")
end

function CoreAutomation.farmTargetByUID(uid)
    uid = tostring(uid or "")
    for _, target in ipairs(CoreAutomation.FarmEngine.CurrentTargets) do
        if tostring(target.UID) == uid then
            return target
        end
    end
    return nil
end

function CoreAutomation.farmSnapRenderedPets()
    if not CoreAutomation.FarmEngine.InfSpeedPets
        or not CoreAutomation.FarmEngine.AutoFarm
        or CoreAutomation.FarmEngine.Paused
        or not CoreAutomation.PlayerPet
        or type(CoreAutomation.PlayerPet.GetByPlayer) ~= "function"
    then
        return 0
    end

    local okPets, rendered = pcall(
        CoreAutomation.PlayerPet.GetByPlayer,
        LocalPlayer
    )

    if not okPets or type(rendered) ~= "table" then
        return 0
    end

    local moved = 0

    for key, pet in pairs(rendered) do
        if type(pet) == "table" then
            local euid = tostring(
                rawget(pet, "_euid")
                or rawget(pet, "euid")
                or rawget(pet, "EUID")
                or key
            )
            local targetUID = CoreAutomation.FarmEngine.CurrentJoinMap[euid]
            local target = targetUID and CoreAutomation.farmTargetByUID(targetUID) or nil

            if target then
                local targetInstance = target.Instance
                local targetPosition = target.Position

                if type(pet.SetTarget) == "function" and targetInstance then
                    pcall(pet.SetTarget, pet, targetInstance)
                end

                if typeof(targetPosition) == "Vector3" then
                    local targetCFrame = CFrame.new(targetPosition + Vector3.new(0, 2.5, 0))
                    local movedThisPet = false

                    for _, methodName in ipairs({
                        "Teleport",
                        "SetPosition",
                        "SetCFrame",
                        "PivotTo",
                    }) do
                        local method = pet[methodName]
                        if type(method) == "function" then
                            local argument = methodName == "SetPosition"
                                and targetPosition
                                or targetCFrame
                            if pcall(method, pet, argument) then
                                movedThisPet = true
                                break
                            end
                        end
                    end

                    if not movedThisPet then
                        local model = rawget(pet, "_model")
                            or rawget(pet, "model")
                            or rawget(pet, "Model")
                        if typeof(model) == "Instance" then
                            if model:IsA("Model") then
                                movedThisPet = pcall(model.PivotTo, model, targetCFrame)
                            elseif model:IsA("BasePart") then
                                movedThisPet = pcall(function()
                                    model.CFrame = targetCFrame
                                end)
                            end
                        end
                    end

                    if movedThisPet then
                        moved = moved + 1
                    end
                end
            end
        end
    end

    return moved
end

function CoreAutomation.farmSetOrbVisualSuppressed(enabled)
    -- V0.1.1.2.6.2 keeps the runtime-confirmed exact-ID collection bridge
    -- and only suppresses client visuals after the server collection call.
    -- It never disables additional Orbs: Create handlers or fakes credit.
    CoreAutomation.FarmEngine.OrbVisualSuppressed = enabled == true
    CoreAutomation.FarmEngine.OrbVisualConnections = {}

    if enabled then
        CoreAutomation.farmScheduleOrbVisualCleanup()
    end

    return true
end

function CoreAutomation.farmHideOrbVisual(instance)
    if not instance or not instance.Parent then
        return false
    end

    if CoreAutomation.FarmEngine.HiddenOrbVisuals[instance] then
        return false
    end
    CoreAutomation.FarmEngine.HiddenOrbVisuals[instance] = true

    local function hideObject(object)
        if object:IsA("BasePart") then
            pcall(function()
                object.LocalTransparencyModifier = 1
                object.Transparency = 1
                object.CanCollide = false
                object.CanTouch = false
                object.CanQuery = false
            end)
        elseif object:IsA("ParticleEmitter")
            or object:IsA("Trail")
            or object:IsA("Beam")
            or object:IsA("BillboardGui")
            or object:IsA("SurfaceGui")
        then
            pcall(function()
                object.Enabled = false
            end)
        elseif object:IsA("Sound") then
            pcall(function()
                object:Stop()
            end)
        end
    end

    hideObject(instance)
    for _, object in ipairs(instance:GetDescendants()) do
        hideObject(object)
    end

    task.delay(0.20, function()
        if instance and instance.Parent then
            pcall(function()
                instance:Destroy()
            end)
        end
    end)

    return true
end

function CoreAutomation.farmHideVisibleOrbs()
    if not CoreAutomation.FarmEngine.CollectOrbs
        or not CoreAutomation.FarmEngine.OrbVisualSuppressed
    then
        return 0
    end

    CoreAutomation.ThingsFolder = Workspace:FindFirstChild("__THINGS")
        or CoreAutomation.ThingsFolder
    CoreAutomation.OrbsFolder = CoreAutomation.ThingsFolder
        and CoreAutomation.ThingsFolder:FindFirstChild("Orbs")
        or CoreAutomation.OrbsFolder

    if not CoreAutomation.OrbsFolder
        or not CoreAutomation.OrbsFolder.Parent
    then
        return 0
    end

    local hidden = 0
    local now = os.clock()

    for _, orb in ipairs(CoreAutomation.OrbsFolder:GetChildren()) do
        local id = tonumber(CoreAutomation.farmOrbID(orb))

        if id then
            id = math.floor(id)
        end

        if id and CoreAutomation.FarmEngine.KnownOrbs[id] ~= nil then
            if CoreAutomation.farmHideOrbVisual(orb) then
                hidden = hidden + 1
            end
        end
    end

    -- Exact IDs only need to stay hot long enough for OrbCmds to render the
    -- matching client part. Pruning prevents an endless KnownOrbs table.
    for id, collectedAt in pairs(CoreAutomation.FarmEngine.KnownOrbs) do
        if type(collectedAt) == "number"
            and now - collectedAt > 15
        then
            CoreAutomation.FarmEngine.KnownOrbs[id] = nil
        end
    end

    return hidden
end

function CoreAutomation.farmScheduleOrbVisualCleanup()
    if CoreAutomation.FarmEngine.OrbCleanupScheduled
        or not CoreAutomation.FarmEngine.CollectOrbs
    then
        return
    end

    CoreAutomation.FarmEngine.OrbCleanupScheduled = true

    task.spawn(function()
        for _, delaySeconds in ipairs({
            0,
            0.025,
            0.065,
            0.14,
            0.30,
        }) do
            if delaySeconds > 0 then
                task.wait(delaySeconds)
            end

            if not Runtime.Alive
                or not CoreAutomation.FarmEngine.Alive
                or not CoreAutomation.FarmEngine.CollectOrbs
            then
                break
            end

            CoreAutomation.farmHideVisibleOrbs()
        end

        CoreAutomation.FarmEngine.OrbCleanupScheduled = false
    end)
end

function CoreAutomation.farmSendAssignments()
    local needsTargets =
        CoreAutomation.FarmEngine.AutoFarm
        or CoreAutomation.FarmEngine.PlayerDamage

    if not needsTargets then
        CoreAutomation.FarmEngine.CurrentPets = {}
        CoreAutomation.FarmEngine.CurrentTargets = {}
        CoreAutomation.FarmEngine.LastAssignmentSignature = nil
        CoreAutomation.farmSetPaused(false)
        CoreAutomation.FarmEngine.LastAction = "Collecting drops"
        return true
    end

    local targets, changed, reason =
        CoreAutomation.farmRefreshStableTargets()

    if #targets == 0 then
        CoreAutomation.farmSetPaused(true, reason)
        return true, "Waiting for breakables"
    end

    CoreAutomation.farmSetPaused(false)

    if not CoreAutomation.FarmEngine.AutoFarm then
        CoreAutomation.FarmEngine.CurrentPets = {}
        CoreAutomation.FarmEngine.LastAssignmentSignature = nil
        CoreAutomation.FarmEngine.LastAction = "Auto Tap ready"
        return true
    end

    local pets = CoreAutomation.farmEquippedPets()
    CoreAutomation.FarmEngine.CurrentPets = pets

    if #pets == 0 then
        return false, "No equipped pets found"
    end

    local signature = CoreAutomation.farmAssignmentSignature(pets, targets)
    local now = os.clock()
    local shouldSend = changed
        or signature ~= CoreAutomation.FarmEngine.LastAssignmentSignature
        or now - CoreAutomation.FarmEngine.LastAssignmentAt
            >= CoreAutomation.FarmEngine.AssignmentKeepAlive

    if not shouldSend then
        CoreAutomation.FarmEngine.LastAction = "Farming"
        return true
    end

    local targetMap = {}
    local joinMap = {}

    for index, euid in ipairs(pets) do
        local target = targets[((index - 1) % #targets) + 1]
        joinMap[euid] = target.UID
        targetMap[euid] = {
            v = target.UID,
            t = 2,
        }
    end

    -- Exact scanner-confirmed pairing. Do not send CQ_Route here: the game
    -- accepts Pets_SetTargetBulk followed by Breakables_JoinPetBulk.
    local okTarget, targetError = pcall(
        Network.Fire,
        "Pets_SetTargetBulk",
        targetMap
    )

    if not okTarget then
        return false, tostring(targetError)
    end

    local okJoin, joinError = pcall(
        Network.Fire,
        "Breakables_JoinPetBulk",
        joinMap
    )

    if not okJoin then
        return false, tostring(joinError)
    end

    CoreAutomation.FarmEngine.CurrentJoinMap = joinMap
    if CoreAutomation.FarmEngine.InfSpeedPets then
        CoreAutomation.farmSnapRenderedPets()
    end

    CoreAutomation.FarmEngine.LastAssignmentSignature = signature
    CoreAutomation.FarmEngine.LastAssignmentAt = now
    CoreAutomation.FarmEngine.Stats.AssignmentCalls =
        CoreAutomation.FarmEngine.Stats.AssignmentCalls + 1

    if changed then
        CoreAutomation.FarmEngine.Stats.TargetChanges =
            CoreAutomation.FarmEngine.Stats.TargetChanges + 1
    end

    CoreAutomation.FarmEngine.LastAction = "Farming"
    return true
end

function CoreAutomation.farmTargetUsable(target)
    if not target then
        return false
    end
    if target.Instance and target.Instance.Parent then
        return true
    end
    if CoreAutomation.BreakableFrontend and type(CoreAutomation.BreakableFrontend.Get) == "function" then
        local ok, data = pcall(CoreAutomation.BreakableFrontend.Get, target.UID)
        if ok and data then
            target.Instance = type(data) == "table" and rawget(data, "model") or nil
            local health = type(data) == "table" and tonumber(rawget(data, "health")) or nil
            return health == nil or health > 0
        end
    end
    return false
end

function CoreAutomation.farmQueueDropID(value)
    local id = tonumber(value)

    if not id then
        return false
    end

    id = math.floor(id)

    if CoreAutomation.FarmEngine.KnownOrbs[id] ~= nil
        or CoreAutomation.FarmEngine.PendingOrbSet[id]
    then
        return false
    end

    CoreAutomation.FarmEngine.PendingOrbSet[id] = true
    table.insert(
        CoreAutomation.FarmEngine.PendingOrbIDs,
        id
    )

    return true
end

function CoreAutomation.farmExtractCreatedOrbIDs(createdOrbs)
    local ids = {}
    local seen = {}

    if type(createdOrbs) ~= "table" then
        return ids
    end

    local function addOrb(orbData)
        if type(orbData) ~= "table" then
            return
        end

        local id = tonumber(
            rawget(orbData, "id")
            or rawget(orbData, "ID")
        )

        if id then
            id = math.floor(id)

            if not seen[id] then
                seen[id] = true
                table.insert(ids, id)
            end
        end
    end

    for _, orbData in ipairs(createdOrbs) do
        addOrb(orbData)
    end

    -- Defensive fallback for a non-array batch. Scanner-confirmed batches are
    -- arrays, but this keeps future protocol reshuffles fail-safe.
    if #ids == 0 then
        for _, orbData in pairs(createdOrbs) do
            addOrb(orbData)
        end
    end

    return ids
end

function CoreAutomation.farmSendOrbIDs(ids)
    if type(ids) ~= "table" then
        return false, "No orb ID batch"
    end

    local payload = {}
    local seen = {}

    for _, value in ipairs(ids) do
        local id = tonumber(value)

        if id then
            id = math.floor(id)

            if not seen[id]
                and CoreAutomation.FarmEngine.KnownOrbs[id] == nil
            then
                seen[id] = true
                table.insert(payload, id)
            end
        end
    end

    if #payload == 0 then
        return true, 0
    end

    -- Runtime-captured exact protocol. This must run before the native
    -- OrbCmds Orbs: Create callback for the same batch.
    local ok, err = pcall(
        Network.Fire,
        "Orbs: Collect",
        payload
    )

    if not ok then
        CoreAutomation.FarmEngine.LastError = tostring(err)
        CoreAutomation.FarmEngine.Stats.Errors =
            CoreAutomation.FarmEngine.Stats.Errors + 1
        return false, tostring(err)
    end

    for _, id in ipairs(payload) do
        CoreAutomation.FarmEngine.KnownOrbs[id] = os.clock()
        CoreAutomation.FarmEngine.PendingOrbSet[id] = nil
    end

    CoreAutomation.FarmEngine.Stats.OrbCalls =
        CoreAutomation.FarmEngine.Stats.OrbCalls + 1
    CoreAutomation.FarmEngine.Stats.OrbIDs =
        CoreAutomation.FarmEngine.Stats.OrbIDs + #payload
    CoreAutomation.FarmEngine.LastError = nil
    CoreAutomation.FarmEngine.LastAction =
        "Collected " .. tostring(#payload) .. " drops"

    CoreAutomation.farmScheduleOrbVisualCleanup()

    return true, #payload
end

function CoreAutomation.farmOrbID(instance)
    if not instance then
        return nil
    end

    local values = {
        instance:GetAttribute("OrbID"),
        instance:GetAttribute("DropID"),
        instance:GetAttribute("LootID"),
        instance:GetAttribute("PickupID"),
        instance:GetAttribute("ID"),
        instance:GetAttribute("UID"),
        instance:GetAttribute("id"),
        instance:GetAttribute("uid"),
    }

    -- PS99's OrbCmds creates each pickup as a BasePart whose Name is the
    -- authoritative orb ID. The parts normally have no ID attributes.
    if instance:IsA("BasePart") then
        local numericName = tonumber(instance.Name)
        table.insert(values, numericName or instance.Name)
    end

    for _, value in ipairs(values) do
        if value ~= nil and tostring(value) ~= "" then
            return value
        end
    end

    return nil
end

function CoreAutomation.farmIsDropFolder(instance)
    if not instance then
        return false
    end

    local name = lower(instance.Name)

    local terms = {
        "orb",
        "loot",
        "bag",
        "drop",
        "pickup",
        "collectible",
    }

    for _, term in ipairs(terms) do
        if string.find(name, term, 1, true) then
            return true
        end
    end

    return false
end

function CoreAutomation.farmTrackDropInstance(instance)
    if not instance then
        return
    end

    local id =
        CoreAutomation.farmOrbID(instance)

    if id then
        CoreAutomation.farmQueueDropID(id)
    end

    for _, nested in ipairs(
        instance:GetDescendants()
    ) do
        local nestedID =
            CoreAutomation.farmOrbID(nested)

        if nestedID then
            CoreAutomation.farmQueueDropID(
                nestedID
            )
        end
    end
end

function CoreAutomation.farmBindDropFolder(folder)
    if not folder
        or CoreAutomation.FarmEngine.DropFolders[folder]
    then
        return
    end

    CoreAutomation.FarmEngine.DropFolders[folder] =
        true

    CoreAutomation.farmTrackDropInstance(folder)

    table.insert(
        CoreAutomation.FarmEngine.Connections,
        folder.DescendantAdded:Connect(
            function(instance)
                if not Runtime.Alive
                    or not CoreAutomation.FarmEngine.Alive
                then
                    return
                end

                local id =
                    CoreAutomation.farmOrbID(instance)

                if id then
                    CoreAutomation.farmQueueDropID(
                        id
                    )
                end
            end
        )
    )
end

function CoreAutomation.farmRefreshDropFolders()
    CoreAutomation.ThingsFolder =
        CoreAutomation.ThingsFolder
        or Workspace:FindFirstChild("__THINGS")

    if not CoreAutomation.ThingsFolder then
        return
    end

    for _, child in ipairs(
        CoreAutomation.ThingsFolder:GetChildren()
    ) do
        if CoreAutomation.farmIsDropFolder(child) then
            CoreAutomation.farmBindDropFolder(
                child
            )
        end
    end
end

function CoreAutomation.farmRescanOrbs()
    if os.clock()
        - CoreAutomation.FarmEngine.LastDropRescanAt
        < 0.20
    then
        return
    end

    CoreAutomation.FarmEngine.LastDropRescanAt =
        os.clock()

    CoreAutomation.farmRefreshDropFolders()

    -- Always refresh the live Orbs folder reference. OrbCmds can recreate the
    -- folder during world transitions and the old reference then goes stale.
    CoreAutomation.ThingsFolder =
        Workspace:FindFirstChild("__THINGS")
        or CoreAutomation.ThingsFolder
    CoreAutomation.OrbsFolder =
        CoreAutomation.ThingsFolder
        and CoreAutomation.ThingsFolder:FindFirstChild("Orbs")
        or CoreAutomation.OrbsFolder

    if CoreAutomation.OrbsFolder
        and CoreAutomation.OrbsFolder.Parent
    then
        CoreAutomation.farmBindDropFolder(
            CoreAutomation.OrbsFolder
        )

        for _, orb in ipairs(
            CoreAutomation.OrbsFolder:GetChildren()
        ) do
            local id = CoreAutomation.farmOrbID(orb)
            if id then
                CoreAutomation.farmQueueDropID(id)
            end
        end
    end

    for folder in pairs(
        CoreAutomation.FarmEngine.DropFolders
    ) do
        if folder and folder.Parent then
            CoreAutomation.farmTrackDropInstance(
                folder
            )
        else
            CoreAutomation.FarmEngine.DropFolders[folder] =
                nil
        end
    end
end

function CoreAutomation.farmFindOrbRegistry()
    local cached = CoreAutomation.FarmEngine.OrbRegistry
    if type(cached) == "table" then
        for _, orb in pairs(cached) do
            if type(orb) == "table"
                and rawget(orb, "_id") ~= nil
                and rawget(orb, "_part") ~= nil
                and not rawget(orb, "_destroyed")
                and not rawget(orb, "_collected")
            then
                return cached
            end
        end
    end

    if os.clock() - (CoreAutomation.FarmEngine.OrbRegistryCheckedAt or 0) < 0.65 then
        return nil
    end
    CoreAutomation.FarmEngine.OrbRegistryCheckedAt = os.clock()

    if type(getgc) ~= "function" then
        return nil
    end

    local okGC, objects = pcall(getgc, true)
    if not okGC or type(objects) ~= "table" then
        return nil
    end

    -- Fast path: many executors expose the live orb objects themselves in
    -- getgc(true). Build a lightweight registry from those exact objects.
    local direct = {}
    for _, object in ipairs(objects) do
        if type(object) == "table"
            and rawget(object, "_id") ~= nil
            and rawget(object, "_part") ~= nil
            and rawget(object, "_cframePhysics") ~= nil
            and rawget(object, "_combinedIds") ~= nil
            and not rawget(object, "_destroyed")
            and not rawget(object, "_collected")
        then
            direct[rawget(object, "_id")] = object
        end
    end
    if next(direct) ~= nil then
        CoreAutomation.FarmEngine.OrbRegistry = direct
        return direct
    end

    -- Fallback: locate OrbCmds' private registry through function upvalues.
    local readAll = type(getupvalues) == "function" and getupvalues
        or (debug and type(debug.getupvalues) == "function" and debug.getupvalues)
    local readOne = type(getupvalue) == "function" and getupvalue
        or (debug and type(debug.getupvalue) == "function" and debug.getupvalue)

    for _, object in ipairs(objects) do
        if type(object) == "function" then
            local candidates = {}
            if type(readAll) == "function" then
                local ok, values = pcall(readAll, object)
                if ok and type(values) == "table" then
                    for _, value in pairs(values) do
                        table.insert(candidates, value)
                    end
                end
            elseif type(readOne) == "function" then
                for index = 1, 32 do
                    local ok, name, value = pcall(readOne, object, index)
                    if not ok or name == nil then break end
                    table.insert(candidates, value)
                end
            end

            for _, candidate in ipairs(candidates) do
                if type(candidate) == "table" then
                    local found = 0
                    local checked = 0
                    for _, orb in pairs(candidate) do
                        checked = checked + 1
                        if type(orb) == "table"
                            and rawget(orb, "_id") ~= nil
                            and rawget(orb, "_part") ~= nil
                            and rawget(orb, "_cframePhysics") ~= nil
                            and rawget(orb, "_combinedIds") ~= nil
                        then
                            found = found + 1
                        end
                        if checked >= 8 then break end
                    end
                    if found > 0 and found == checked then
                        CoreAutomation.FarmEngine.OrbRegistry = candidate
                        return candidate
                    end
                end
            end
        end
    end

    return nil
end

function CoreAutomation.farmCollectOrbs()
    CoreAutomation.farmRescanOrbs()

    local pending = CoreAutomation.FarmEngine.PendingOrbIDs
    CoreAutomation.FarmEngine.PendingOrbIDs = {}

    local ids = {}

    for _, id in ipairs(pending) do
        CoreAutomation.FarmEngine.PendingOrbSet[id] = nil

        if CoreAutomation.FarmEngine.KnownOrbs[id] == nil then
            table.insert(ids, id)
        end
    end

    if #ids == 0 then
        return true, 0
    end

    return CoreAutomation.farmSendOrbIDs(ids)
end

function CoreAutomation.farmAnyFeatureEnabled()
    return CoreAutomation.FarmEngine.AutoFarm
        or CoreAutomation.FarmEngine.PlayerDamage
        or CoreAutomation.FarmEngine.CollectOrbs
end

function CoreAutomation.startFarmEngine()
    if CoreAutomation.FarmEngine.Running then
        return
    end

    if not CoreAutomation.farmAnyFeatureEnabled() then
        return
    end

    if not Network
        or type(Network.Fire) ~= "function"
        or type(Network.UnreliableFire) ~= "function"
    then
        setNotice(
            "PS99 Network API is unavailable for Farm automation.",
            "error"
        )
        return
    end

    CoreAutomation.FarmEngine.Running = true
    CoreAutomation.FarmEngine.Paused = false
    CoreAutomation.FarmEngine.WorkerToken =
        CoreAutomation.FarmEngine.WorkerToken + 1
    CoreAutomation.FarmEngine.LastError = nil
    CoreAutomation.FarmEngine.LastAction =
        "Farm feature workers started"

    local token =
        CoreAutomation.FarmEngine.WorkerToken

    task.spawn(function()
        while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
            and CoreAutomation.FarmEngine.Alive
            and CoreAutomation.FarmEngine.Running
            and CoreAutomation.FarmEngine.WorkerToken == token
        do
            local ok, reason =
                CoreAutomation.farmSendAssignments()

            if not ok then
                CoreAutomation.FarmEngine.LastError = reason
                CoreAutomation.FarmEngine.Stats.Errors =
                    CoreAutomation.FarmEngine.Stats.Errors + 1
            else
                CoreAutomation.FarmEngine.LastError = nil
            end

            if CoreAutomation.refreshFarmUI
                and os.clock() - CoreAutomation.FarmEngine.LastUIRefreshAt
                    >= CoreAutomation.FarmEngine.UIRefreshInterval
            then
                CoreAutomation.FarmEngine.LastUIRefreshAt = os.clock()
                CoreAutomation.refreshFarmUI()
            end

            task.wait(CoreAutomation.FarmEngine.AssignmentInterval)
        end
    end)

    task.spawn(function()
        while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
            and CoreAutomation.FarmEngine.Alive
            and CoreAutomation.FarmEngine.Running
            and CoreAutomation.FarmEngine.WorkerToken == token
        do
            if CoreAutomation.FarmEngine.InfSpeedPets then
                CoreAutomation.farmSnapRenderedPets()
            end
            task.wait(0.035)
        end
    end)

    task.spawn(function()
        local index = 1

        while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
            and CoreAutomation.FarmEngine.Alive
            and CoreAutomation.FarmEngine.Running
            and CoreAutomation.FarmEngine.WorkerToken == token
        do
            if CoreAutomation.FarmEngine.PlayerDamage
                and not CoreAutomation.FarmEngine.Paused
                and #CoreAutomation.FarmEngine.CurrentTargets > 0
            then
                local count =
                    #CoreAutomation.FarmEngine.CurrentTargets
                local target = nil

                for offset = 0, count - 1 do
                    local candidateIndex =
                        ((index - 1 + offset) % count) + 1
                    local candidate =
                        CoreAutomation.FarmEngine
                            .CurrentTargets[candidateIndex]

                    if CoreAutomation.farmTargetUsable(candidate) then
                        target = candidate
                        index =
                            (candidateIndex % count) + 1
                        break
                    end
                end

                if target then
                    local ok, err = pcall(
                        Network.UnreliableFire,
                        "Breakables_PlayerDealDamage",
                        target.UID
                    )

                    if ok then
                        CoreAutomation.FarmEngine
                            .Stats.DamageCalls =
                            CoreAutomation.FarmEngine
                                .Stats.DamageCalls + 1
                    else
                        CoreAutomation.FarmEngine.LastError =
                            tostring(err)
                        CoreAutomation.FarmEngine.Stats.Errors =
                            CoreAutomation.FarmEngine
                                .Stats.Errors + 1
                    end
                end
            end

            task.wait(
                CoreAutomation.FarmEngine.DamageInterval
            )
        end
    end)

    task.spawn(function()
        while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
            and CoreAutomation.FarmEngine.Alive
            and CoreAutomation.FarmEngine.Running
            and CoreAutomation.FarmEngine.WorkerToken == token
        do
            if CoreAutomation.FarmEngine.CollectOrbs
                and (
                    not CoreAutomation.FarmEngine.Paused
                    or (
                        not CoreAutomation.FarmEngine.AutoFarm
                        and not CoreAutomation.FarmEngine.PlayerDamage
                    )
                )
            then
                CoreAutomation.farmCollectOrbs()
            end

            task.wait(
                CoreAutomation.FarmEngine.OrbInterval
            )
        end
    end)

    if CoreAutomation.refreshFarmUI then
        CoreAutomation.refreshFarmUI()
    end
end

function CoreAutomation.stopFarmEngine(
    reason,
    disableFeatures
)
    local wasRunning =
        CoreAutomation.FarmEngine.Running

    CoreAutomation.FarmEngine.Running = false
    CoreAutomation.FarmEngine.Paused = false
    CoreAutomation.FarmEngine.PauseReason = nil
    CoreAutomation.FarmEngine.WorkerToken =
        CoreAutomation.FarmEngine.WorkerToken + 1
    CoreAutomation.FarmEngine.CurrentTargets = {}
    CoreAutomation.FarmEngine.CurrentPets = {}
    CoreAutomation.FarmEngine.CurrentJoinMap = {}
    CoreAutomation.FarmEngine.PendingOrbIDs = {}
    CoreAutomation.FarmEngine.PendingOrbSet = {}
    CoreAutomation.FarmEngine.LastAssignmentSignature = nil

    if disableFeatures == true then
        CoreAutomation.FarmEngine.AutoFarm = false
        CoreAutomation.FarmEngine.PlayerDamage = false
        CoreAutomation.FarmEngine.CollectOrbs = false
        CoreAutomation.FarmEngine.InfSpeedPets = false
        CoreAutomation.farmSetOrbVisualSuppressed(false)

        Config.farm.enabled = false
        Config.farm.playerDamage = false
        Config.farm.collectOrbs = false
        Config.farm.infSpeedPets = false
        markConfigDirty()
    end

    local restored =
        CoreAutomation.farmRestorePets()

    CoreAutomation.FarmEngine.LastAction =
        tostring(reason or "Farm workers stopped")
        .. " • restored "
        .. tostring(restored)
        .. " pets"

    if wasRunning and disableFeatures == true then
        setNotice(
            "All Farm features disabled. Restored "
                .. tostring(restored)
                .. " pets.",
            "info"
        )
    end

    if CoreAutomation.refreshFarmUI then
        CoreAutomation.refreshFarmUI()
    end
end

function CoreAutomation.syncFarmEngine(reason)
    if CoreAutomation.farmAnyFeatureEnabled() then
        CoreAutomation.startFarmEngine()
    elseif CoreAutomation.FarmEngine.Running then
        CoreAutomation.stopFarmEngine(
            reason or "All Farm features disabled",
            false
        )
    elseif CoreAutomation.refreshFarmUI then
        CoreAutomation.refreshFarmUI()
    end
end

function CoreAutomation.setFarmFeature(
    featureName,
    enabled
)
    enabled = enabled == true

    if featureName == "AutoFarm" then
        CoreAutomation.FarmEngine.AutoFarm = enabled
        Config.farm.enabled = enabled
        CoreAutomation.FarmEngine.LastAssignmentSignature = nil

        if not enabled then
            local restored =
                CoreAutomation.farmRestorePets()

            CoreAutomation.FarmEngine.LastAction =
                "Auto Farm Pets disabled • restored "
                .. tostring(restored)
                .. " pets"
        else
            CoreAutomation.FarmEngine.LastAction =
                "Auto Farm Pets enabled"
        end
    elseif featureName == "PlayerDamage"
        or featureName == "AutoTap"
    then
        CoreAutomation.FarmEngine.PlayerDamage = enabled
        Config.farm.playerDamage = enabled
        CoreAutomation.FarmEngine.LastAction =
            enabled
            and "Auto Tap enabled"
            or "Auto Tap disabled"
    elseif featureName == "CollectOrbs"
        or featureName == "CollectDrops"
    then
        if enabled
            and not CoreAutomation.FarmEngine.OrbBridgeInstalled
        then
            CoreAutomation.registerFarmOrbListeners()
        end

        if enabled
            and not CoreAutomation.FarmEngine.OrbBridgeInstalled
        then
            enabled = false
        end

        CoreAutomation.FarmEngine.CollectOrbs = enabled
        Config.farm.collectOrbs = enabled
        CoreAutomation.farmSetOrbVisualSuppressed(enabled)

        if not enabled then
            CoreAutomation.FarmEngine.PendingOrbIDs = {}
            CoreAutomation.FarmEngine.PendingOrbSet = {}
            CoreAutomation.FarmEngine.OrbCleanupScheduled = false
        end

        if enabled then
            CoreAutomation.FarmEngine.LastAction =
                "Collect Drops enabled"
        elseif CoreAutomation.FarmEngine.LastError then
            CoreAutomation.FarmEngine.LastAction =
                CoreAutomation.FarmEngine.LastError
        else
            CoreAutomation.FarmEngine.LastAction =
                "Collect Drops disabled"
        end
    elseif featureName == "InfSpeedPets"
        or featureName == "FastPets"
    then
        if enabled and not requirePremium("Inf Speed Pets") then
            return false
        end
        CoreAutomation.FarmEngine.InfSpeedPets = enabled
        Config.farm.infSpeedPets = enabled
        CoreAutomation.FarmEngine.LastAssignmentSignature = nil
        if not enabled then
            CoreAutomation.farmRestorePets()
        end
        CoreAutomation.FarmEngine.LastAction = enabled
            and "Inf Speed Pets enabled"
            or "Inf Speed Pets disabled"
    else
        return false
    end

    markConfigDirty()
    CoreAutomation.syncFarmEngine(
        "All Farm features disabled"
    )

    if CoreAutomation.refreshFarmUI then
        CoreAutomation.refreshFarmUI()
    end

    return true
end

function CoreAutomation.farmRestoreOrbBridge()
    local wrapper = CoreAutomation.FarmEngine.OrbListenerConnection
    if wrapper then
        pcall(function()
            wrapper:Disconnect()
        end)
    end

    local nativeConnection =
        CoreAutomation.FarmEngine.OrbNativeConnection

    if nativeConnection then
        if type(nativeConnection.Enable) == "function" then
            pcall(nativeConnection.Enable, nativeConnection)
        elseif type(nativeConnection.enable) == "function" then
            pcall(nativeConnection.enable, nativeConnection)
        end
    end

    CoreAutomation.FarmEngine.OrbListenerConnection = nil
    CoreAutomation.FarmEngine.OrbNativeConnection = nil
    CoreAutomation.FarmEngine.OrbNativeCallback = nil
    CoreAutomation.FarmEngine.OrbBridgeInstalled = false
end

function CoreAutomation.registerFarmOrbListeners()
    if CoreAutomation.FarmEngine.OrbBridgeInstalled then
        return true
    end

    if not Network or type(Network.Fired) ~= "function" then
        CoreAutomation.FarmEngine.LastError =
            "Orb bridge unavailable: Network.Fired missing"
        return false
    end

    local okCreate, createSignal = pcall(
        Network.Fired,
        "Orbs: Create"
    )

    if not okCreate
        or not createSignal
        or type(createSignal.Connect) ~= "function"
    then
        CoreAutomation.FarmEngine.LastError =
            "Orb bridge unavailable: Orbs: Create missing"
        return false
    end

    CoreAutomation.FarmEngine.OrbCreateSignal = createSignal

    if type(getconnections) ~= "function" then
        CoreAutomation.FarmEngine.LastError =
            "Orb bridge unavailable: getconnections missing"
        return false
    end

    local okConnections, connections = pcall(
        getconnections,
        createSignal
    )

    if not okConnections or type(connections) ~= "table" then
        CoreAutomation.FarmEngine.LastError =
            "Orb bridge unavailable: native connection scan failed"
        return false
    end

    local nativeConnection = nil
    local nativeCallback = nil

    local function callbackSource(callback)
        local source = ""

        if debug and type(debug.info) == "function" then
            local okInfo, result = pcall(
                debug.info,
                callback,
                "s"
            )
            if okInfo and result ~= nil then
                source = tostring(result)
            end
        end

        if source == "" then
            local getter = type(getinfo) == "function"
                and getinfo
                or (debug and debug.getinfo)

            if type(getter) == "function" then
                local okInfo, info = pcall(getter, callback)
                if okInfo and type(info) == "table" then
                    source = tostring(
                        info.source
                        or info.short_src
                        or ""
                    )
                end
            end
        end

        return string.lower(source)
    end

    for _, connection in ipairs(connections) do
        local callback = connection.Function
            or connection["function"]

        if type(callback) == "function" then
            local source = callbackSource(callback)

            if string.find(source, "orbcmds", 1, true) then
                nativeConnection = connection
                nativeCallback = callback
                break
            end
        end
    end

    if not nativeConnection or type(nativeCallback) ~= "function" then
        CoreAutomation.FarmEngine.LastError =
            "Orb bridge unavailable: native OrbCmds handler not found"
        return false
    end

    local disabled = false
    if type(nativeConnection.Disable) == "function" then
        disabled = pcall(
            nativeConnection.Disable,
            nativeConnection
        )
    elseif type(nativeConnection.disable) == "function" then
        disabled = pcall(
            nativeConnection.disable,
            nativeConnection
        )
    end

    if not disabled then
        CoreAutomation.FarmEngine.LastError =
            "Orb bridge unavailable: native handler could not be paused"
        return false
    end

    CoreAutomation.FarmEngine.OrbNativeConnection =
        nativeConnection
    CoreAutomation.FarmEngine.OrbNativeCallback =
        nativeCallback

    local function bridgedCreateHandler(createdOrbs, ...)
        if Runtime.Alive
            and CoreAutomation.FarmEngine.Alive
            and CoreAutomation.FarmEngine.CollectOrbs
        then
            local ids =
                CoreAutomation.farmExtractCreatedOrbIDs(
                    createdOrbs
                )

            if #ids > 0 then
                -- The successful trace showed Orbs: Collect first, followed
                -- immediately by NativeOrbCmds.Connection1 for the same batch.
                CoreAutomation.farmSendOrbIDs(ids)
            end
        end

        local callback =
            CoreAutomation.FarmEngine.OrbNativeCallback

        if type(callback) ~= "function" then
            return
        end

        local returned = table.pack(
            pcall(callback, createdOrbs, ...)
        )

        if not returned[1] then
            CoreAutomation.FarmEngine.LastError =
                "Native OrbCmds error: "
                .. tostring(returned[2])
            CoreAutomation.FarmEngine.Stats.Errors =
                CoreAutomation.FarmEngine.Stats.Errors + 1
            return
        end

        -- The native callback has now registered/rendered this exact batch.
        -- Sweep only IDs already submitted to the server, then remove their
        -- local parts after a short grace period.
        CoreAutomation.farmScheduleOrbVisualCleanup()

        return table.unpack(returned, 2, returned.n)
    end

    local okWrapper, wrapperConnection = pcall(
        createSignal.Connect,
        createSignal,
        bridgedCreateHandler
    )

    if not okWrapper or not wrapperConnection then
        if type(nativeConnection.Enable) == "function" then
            pcall(nativeConnection.Enable, nativeConnection)
        elseif type(nativeConnection.enable) == "function" then
            pcall(nativeConnection.enable, nativeConnection)
        end

        CoreAutomation.FarmEngine.OrbNativeConnection = nil
        CoreAutomation.FarmEngine.OrbNativeCallback = nil
        CoreAutomation.FarmEngine.LastError =
            "Orb bridge unavailable: wrapper connection failed"
        return false
    end

    CoreAutomation.FarmEngine.OrbListenerConnection =
        wrapperConnection
    CoreAutomation.FarmEngine.OrbBridgeInstalled = true
    CoreAutomation.FarmEngine.LastError = nil

    table.insert(
        CoreAutomation.FarmEngine.Connections,
        wrapperConnection
    )

    return true
end

CoreAutomation.registerFarmOrbListeners()

--//////////////////////////////////////////////////////////////////
-- Normal egg controller
--//////////////////////////////////////////////////////////////////

CoreAutomation.NormalEggEngine = {
    Alive = true,
    Running = false,
    WorkerToken = 0,
    Eggs = {},
    Mode = tostring(Config.eggs.mode or "Best Egg"),
    SelectedID = Config.eggs.selectedEggID ~= "" and Config.eggs.selectedEggID or nil,
    SelectedIndex = 0,
    Delay = 1.65,
    LastRefreshAt = 0,
    LastAction = "Stopped",
    LastError = nil,
    Stats = {
        Requests = 0,
        Successes = 0,
        RequestedEggs = 0,
        Errors = 0,
    },
}

function CoreAutomation.normalEggMethod(object, methodName, fallback)
    if type(object) ~= "table" or type(object[methodName]) ~= "function" then
        return fallback
    end
    local ok, value = pcall(object[methodName], object)
    if ok and value ~= nil then
        return value
    end
    return fallback
end

function CoreAutomation.normalEggScore(id, directory, index)
    directory = type(directory) == "table" and directory or {}
    local fields = {
        rawget(directory, "order"),
        rawget(directory, "Order"),
        rawget(directory, "index"),
        rawget(directory, "Index"),
        rawget(directory, "eggNumber"),
        rawget(directory, "EggNumber"),
        rawget(directory, "area"),
        rawget(directory, "Area"),
        rawget(directory, "zone"),
        rawget(directory, "Zone"),
    }
    for _, value in ipairs(fields) do
        if tonumber(value) then
            return tonumber(value)
        end
        if type(value) == "string" then
            local number = tonumber(string.match(value, "%d+"))
            if number then
                return number
            end
        end
    end
    return tonumber(string.match(tostring(id), "%d+")) or index or 0
end

function CoreAutomation.addNormalEgg(entries, seen, key, object, index)
    local id = nil
    local directory = nil
    local hatchable = nil

    if type(object) == "table" then
        id = rawget(object, "_id") or rawget(object, "id") or rawget(object, "ID")
        id = CoreAutomation.normalEggMethod(object, "GetId", id)
        id = CoreAutomation.normalEggMethod(object, "GetID", id)
        directory = CoreAutomation.normalEggMethod(object, "Directory", nil)
        hatchable = CoreAutomation.normalEggMethod(object, "IsHatchable", nil)
        if hatchable == nil then
            hatchable = CoreAutomation.normalEggMethod(object, "CanHatch", nil)
        end
    end

    id = tostring(id or key or "")
    if id == "" or seen[id] then
        return
    end

    if type(directory) ~= "table" and type(CoreAutomation.NormalEggsDirectory) == "table" then
        directory = CoreAutomation.NormalEggsDirectory[id]
    end
    directory = type(directory) == "table" and directory or {}

    local name = CoreAutomation.normalEggMethod(object, "GetTitle", nil)
        or CoreAutomation.normalEggMethod(object, "GetName", nil)
        or rawget(directory, "name")
        or rawget(directory, "Name")
        or id

    local position = CoreAutomation.normalEggMethod(object, "GetPosition", nil)
    local distance = math.huge
    local root = CoreAutomation.permanentRootPart()
    if root and typeof(position) == "Vector3" then
        distance = (root.Position - position).Magnitude
    end

    if hatchable == false then
        return
    end

    local available = true
    if type(EggCmds.IsEggAvailable) == "function" then
        local okAvailable, result = pcall(
            EggCmds.IsEggAvailable,
            id
        )
        available = okAvailable and result == true
    end

    local unlocked = true
    if type(EggCmds.IsUnlocked) == "function" then
        local okUnlocked, result = pcall(
            EggCmds.IsUnlocked,
            id
        )
        unlocked = okUnlocked and result == true
    end

    -- Exclude future, locked, special, and non-normal eggs. Previously the
    -- Best Egg selector could choose the final directory entry even though the
    -- account could not buy it, so every purchase was rejected.
    if not available or not unlocked then
        return
    end

    seen[id] = true
    table.insert(entries, {
        ID = id,
        Name = tostring(name),
        Object = object,
        Directory = directory,
        Score = CoreAutomation.normalEggScore(id, directory, index),
        Distance = distance,
        Hatchable = hatchable ~= false,
    })
end

function CoreAutomation.refreshNormalEggs(force)
    if not force and os.clock() - CoreAutomation.NormalEggEngine.LastRefreshAt < 1.5 then
        return #CoreAutomation.NormalEggEngine.Eggs > 0
    end
    CoreAutomation.NormalEggEngine.LastRefreshAt = os.clock()

    local entries = {}
    local seen = {}
    local things = Workspace:FindFirstChild("__THINGS")
    local physicalEggs = things and things:FindFirstChild("Eggs")

    -- Prefer eggs physically rendered in the current world. The old directory
    -- fallback could select a later-world egg (for example Blossom Egg) while
    -- the player was standing beside a different live egg, so every purchase
    -- was rejected or appeared to do nothing.
    if physicalEggs and CoreAutomation.EggsUtil
        and type(CoreAutomation.EggsUtil.GetIdByNumber) == "function"
    then
        for _, stand in ipairs(physicalEggs:GetDescendants()) do
            if stand:IsA("Model") then
                local number = tonumber(stand.Name:match("%d+"))
                local center = stand:FindFirstChild("Center")
                local eggPart = stand:FindFirstChild("Egg") or stand:FindFirstChild("Display Egg")
                if number and (center or eggPart) then
                    local okID, id = pcall(CoreAutomation.EggsUtil.GetIdByNumber, number)
                    if okID and type(id) == "string" and id ~= "" and not seen[id] then
                        local directory = type(CoreAutomation.NormalEggsDirectory) == "table"
                            and CoreAutomation.NormalEggsDirectory[id] or nil
                        local available, unlocked = true, true
                        if type(EggCmds.IsEggAvailable) == "function" then
                            local ok, value = pcall(EggCmds.IsEggAvailable, id)
                            available = ok and value == true
                        end
                        if type(EggCmds.IsUnlocked) == "function" then
                            local ok, value = pcall(EggCmds.IsUnlocked, id)
                            unlocked = ok and value == true
                        end
                        if available and unlocked then
                            local position = nil
                            if center and center:IsA("BasePart") then
                                position = center.Position
                            elseif stand.PrimaryPart then
                                position = stand.PrimaryPart.Position
                            elseif eggPart and eggPart:IsA("BasePart") then
                                position = eggPart.Position
                            end
                            local root = CoreAutomation.permanentRootPart()
                            local distance = root and position
                                and (root.Position - position).Magnitude or math.huge
                            seen[id] = true
                            table.insert(entries, {
                                ID = id,
                                Name = tostring(type(directory) == "table"
                                    and (rawget(directory, "name") or rawget(directory, "Name")) or id),
                                Object = stand,
                                Directory = type(directory) == "table" and directory or {},
                                Score = number,
                                Distance = distance,
                                Position = position,
                                Hatchable = true,
                            })
                        end
                    end
                end
            end
        end
    end

    -- Compatibility fallback when the physical egg frontend is not loaded yet.
    if #entries == 0 and type(CoreAutomation.NormalEggsDirectory) == "table" then
        local index = 0
        for key, directory in pairs(CoreAutomation.NormalEggsDirectory) do
            if type(directory) == "table" then
                index = index + 1
                CoreAutomation.addNormalEgg(entries, seen, key, {_id = key, _directory = directory}, index)
                local entry = entries[#entries]
                if entry and entry.ID == tostring(key) then
                    entry.Directory = directory
                    entry.Name = tostring(rawget(directory, "name") or rawget(directory, "Name") or key)
                    entry.Score = CoreAutomation.normalEggScore(key, directory, index)
                end
            end
        end
    end

    table.sort(entries, function(left, right)
        if left.Score ~= right.Score then return left.Score < right.Score end
        if left.Distance ~= right.Distance then return left.Distance < right.Distance end
        return left.Name < right.Name
    end)

    CoreAutomation.NormalEggEngine.Eggs = entries
    CoreAutomation.NormalEggEngine.SelectedIndex = 0
    if CoreAutomation.NormalEggEngine.SelectedID then
        for index, entry in ipairs(entries) do
            if entry.ID == CoreAutomation.NormalEggEngine.SelectedID then
                CoreAutomation.NormalEggEngine.SelectedIndex = index
                break
            end
        end
    end
    if CoreAutomation.NormalEggEngine.SelectedIndex == 0 and #entries > 0 then
        CoreAutomation.NormalEggEngine.SelectedIndex = 1
        CoreAutomation.NormalEggEngine.SelectedID = entries[1].ID
    end

    local okDelay, delay = pcall(EggCmds.ComputeDebounce)
    if okDelay and tonumber(delay) then
        CoreAutomation.NormalEggEngine.Delay = clamp(tonumber(delay) + 0.025, 0.3, 8)
    end

    if CoreAutomation.refreshNormalEggUI then CoreAutomation.refreshNormalEggUI() end
    return #entries > 0
end

function CoreAutomation.normalEggSelectedSpecific()
    local entry = CoreAutomation.NormalEggEngine.Eggs[CoreAutomation.NormalEggEngine.SelectedIndex]
    if entry and entry.ID == CoreAutomation.NormalEggEngine.SelectedID then
        return entry
    end
    for index, candidate in ipairs(CoreAutomation.NormalEggEngine.Eggs) do
        if candidate.ID == CoreAutomation.NormalEggEngine.SelectedID then
            CoreAutomation.NormalEggEngine.SelectedIndex = index
            return candidate
        end
    end
    return CoreAutomation.NormalEggEngine.Eggs[1]
end

function CoreAutomation.resolvedNormalEgg()
    CoreAutomation.refreshNormalEggs(false)
    if #CoreAutomation.NormalEggEngine.Eggs == 0 then
        return nil
    end
    if CoreAutomation.NormalEggEngine.Mode == "Worst Egg" then
        return CoreAutomation.NormalEggEngine.Eggs[1]
    elseif CoreAutomation.NormalEggEngine.Mode == "Best Egg" then
        return CoreAutomation.NormalEggEngine.Eggs[#CoreAutomation.NormalEggEngine.Eggs]
    end
    return CoreAutomation.normalEggSelectedSpecific()
end

function CoreAutomation.cycleNormalEggMode()
    local modes = {"Best Egg", "Worst Egg", "Specific Egg"}
    local index = table.find(modes, CoreAutomation.NormalEggEngine.Mode) or 1
    index = (index % #modes) + 1
    CoreAutomation.NormalEggEngine.Mode = modes[index]
    Config.eggs.mode = CoreAutomation.NormalEggEngine.Mode
    markConfigDirty()
    if CoreAutomation.refreshNormalEggUI then
        CoreAutomation.refreshNormalEggUI()
    end
end

function CoreAutomation.cycleNormalEggSelection(direction)
    CoreAutomation.refreshNormalEggs(true)
    if #CoreAutomation.NormalEggEngine.Eggs == 0 then
        setNotice("No eggs found.", "error")
        return
    end
    local index = CoreAutomation.NormalEggEngine.SelectedIndex + direction
    if index < 1 then
        index = #CoreAutomation.NormalEggEngine.Eggs
    elseif index > #CoreAutomation.NormalEggEngine.Eggs then
        index = 1
    end
    CoreAutomation.NormalEggEngine.Mode = "Specific Egg"
    CoreAutomation.NormalEggEngine.SelectedIndex = index
    CoreAutomation.NormalEggEngine.SelectedID = CoreAutomation.NormalEggEngine.Eggs[index].ID
    Config.eggs.mode = CoreAutomation.NormalEggEngine.Mode
    Config.eggs.selectedEggID = CoreAutomation.NormalEggEngine.SelectedID
    markConfigDirty()
    if CoreAutomation.refreshNormalEggUI then
        CoreAutomation.refreshNormalEggUI()
    end
end

function CoreAutomation.normalEggMaxHatch()
    local ok, amount = pcall(EggCmds.GetMaxHatch)
    if ok and tonumber(amount) then
        return math.max(1, math.floor(tonumber(amount)))
    end
    return 1
end

function CoreAutomation.normalEggAffordableAmount(entry)
    local amount = CoreAutomation.normalEggMaxHatch()
    local directory = entry and entry.Directory
    if type(directory) == "table" and CalcEggPricePlayer and CurrencyCmds then
        local currency = rawget(directory, "currency")
        if currency and type(CurrencyCmds.Get) == "function" then
            local okPrice, price = pcall(CalcEggPricePlayer, directory)
            local okOwned, owned = pcall(CurrencyCmds.Get, currency)
            if okPrice and okOwned and tonumber(price) and tonumber(price) > 0
                and tonumber(owned)
            then
                amount = math.min(amount, math.floor(tonumber(owned) / tonumber(price)))
            end
        end
    end
    return math.max(0, math.floor(tonumber(amount) or 0))
end

function CoreAutomation.startNormalEggs()
    if CoreAutomation.NormalEggEngine.Running then
        return
    end

    if not CoreAutomation.refreshNormalEggs(true) then
        setNotice("No eggs found here.", "error")
        return
    end

    local selected = CoreAutomation.resolvedNormalEgg()
    if not selected then
        setNotice("Choose an egg first.", "error")
        return
    end

    local eggID = tostring(selected.ID)
    local eggName = tostring(selected.Name or selected.ID)
    local amount = CoreAutomation.normalEggMaxHatch()
    local delay = 1.65

    if EggCmds and type(EggCmds.ComputeDebounce) == "function" then
        local okDelay, value = pcall(EggCmds.ComputeDebounce)
        if okDelay and tonumber(value) then
            delay = math.max(0.35, tonumber(value) + 0.025)
        end
    end

    CoreAutomation.NormalEggEngine.Running = true
    CoreAutomation.NormalEggEngine.WorkerToken =
        CoreAutomation.NormalEggEngine.WorkerToken + 1
    CoreAutomation.NormalEggEngine.SelectedID = eggID
    CoreAutomation.NormalEggEngine.Delay = delay
    CoreAutomation.NormalEggEngine.LastError = nil
    CoreAutomation.NormalEggEngine.LastAction = "Waiting for first hatch"
    Config.eggs.autoBuy = true
    Config.eggs.selectedEggID = eggID
    markConfigDirty()

    EggEngine:ApplyAnimationSetting()

    local token = CoreAutomation.NormalEggEngine.WorkerToken
    task.spawn(function()
        local announced = false

        while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
            and CoreAutomation.NormalEggEngine.Alive
            and CoreAutomation.NormalEggEngine.Running
            and CoreAutomation.NormalEggEngine.WorkerToken == token
        do
            CoreAutomation.NormalEggEngine.Stats.Requests =
                CoreAutomation.NormalEggEngine.Stats.Requests + 1

            -- Exact payload captured from ZapHub:
            -- Network.Invoke("Eggs_RequestPurchase", "Hollow Egg", 63)
            local ok, success, message = pcall(
                Network.Invoke,
                "Eggs_RequestPurchase",
                eggID,
                amount
            )

            appendLog(
                "NORMAL_EGG",
                string.format(
                    "id=%s amount=%d ok=%s success=%s message=%s",
                    eggID,
                    amount,
                    tostring(ok),
                    tostring(success),
                    tostring(message)
                )
            )

            if ok and success == true then
                CoreAutomation.NormalEggEngine.Stats.Successes =
                    CoreAutomation.NormalEggEngine.Stats.Successes + 1
                CoreAutomation.NormalEggEngine.Stats.RequestedEggs =
                    CoreAutomation.NormalEggEngine.Stats.RequestedEggs + amount
                CoreAutomation.NormalEggEngine.LastError = nil
                CoreAutomation.NormalEggEngine.LastAction =
                    "Opening " .. eggName

                if not announced then
                    announced = true
                    setNotice("Auto Open active.", "success")
                end
            else
                local reason = tostring(ok and (message or success) or success)
                CoreAutomation.NormalEggEngine.Stats.Errors =
                    CoreAutomation.NormalEggEngine.Stats.Errors + 1
                CoreAutomation.NormalEggEngine.LastError = reason
                CoreAutomation.NormalEggEngine.LastAction = "Waiting to retry"

                if isCurrencyFailure(reason) then
                    CoreAutomation.stopNormalEggs("Not enough currency")
                    break
                elseif isRateLimit(reason) then
                    task.wait(2.5)
                end
            end

            if CoreAutomation.refreshNormalEggUI then
                CoreAutomation.refreshNormalEggUI()
            end
            task.wait(CoreAutomation.NormalEggEngine.Delay)
        end
    end)

    if CoreAutomation.refreshNormalEggUI then
        CoreAutomation.refreshNormalEggUI()
    end
end

function CoreAutomation.stopNormalEggs(reason)
    local wasRunning = CoreAutomation.NormalEggEngine.Running
    CoreAutomation.NormalEggEngine.Running = false
    CoreAutomation.NormalEggEngine.WorkerToken =
        CoreAutomation.NormalEggEngine.WorkerToken + 1
    CoreAutomation.NormalEggEngine.LastAction =
        tostring(reason or "Stopped")
    Config.eggs.autoBuy = false

    if HatchingCmds and type(HatchingCmds.StopHatching) == "function" then
        pcall(HatchingCmds.StopHatching)
    end

    markConfigDirty()

    if wasRunning then
        setNotice(reason or "Normal egg automation stopped.", "info")
    end

    if CoreAutomation.refreshNormalEggUI then
        CoreAutomation.refreshNormalEggUI()
    end
end

--//////////////////////////////////////////////////////////////////
-- Consumables
--//////////////////////////////////////////////////////////////////

CoreAutomation.AutomaticEngine = {
    Alive = true,
    Fruits = {},
    Potions = {},

    AutoFruit = Config.automatic.autoFruit == true,
    AutoPotion = Config.automatic.autoPotion == true,
    AutoToys = Config.automatic.autoToys == true
        or Config.automatic.autoSqueakyToy == true
        or Config.automatic.autoToyBall == true,
    AutoUltimate = Config.automatic.autoUltimate == true,

    UltimateName =
        tostring(
            Config.automatic.ultimateName
            or "Pet Surge"
        ),

    FruitSelection =
        type(Config.automatic.fruitSelection) == "table"
        and Config.automatic.fruitSelection
        or {},

    PotionSelection =
        type(Config.automatic.potionSelection) == "table"
        and Config.automatic.potionSelection
        or {},

    FruitConfigExpanded = false,
    PotionConfigExpanded = false,

    LastRefreshAt = 0,
    LastAction = "Idle",
    LastError = nil,

    NextFruitAt = 0,
    NextPotionAt = 0,
    NextToyAt = 0,
    NextUltimateAt = 0,

    FruitInterval = 30,
    PotionInterval = 3,
    ToyInterval = 12,
    UltimateInterval = 2.5,

    Stats = {
        FruitCalls = 0,
        ToyCalls = 0,
        PotionCalls = 0,
        UltimateCalls = 0,
        Errors = 0,
    },
}

function CoreAutomation.inventoryBucket(save, names)
    if type(save) ~= "table" then
        return nil
    end

    local roots = {
        rawget(save, "Inventory"),
        rawget(save, "Items"),
        save,
    }

    for _, root in ipairs(roots) do
        if type(root) == "table" then
            for _, name in ipairs(names) do
                local bucket = rawget(root, name)

                if type(bucket) == "table" then
                    return bucket
                end
            end
        end
    end

    return nil
end

function CoreAutomation.inventoryEntries(
    bucket,
    kindName
)
    local output = {}

    if type(bucket) ~= "table" then
        return output
    end

    for key, value in pairs(bucket) do
        local uid = tostring(key)
        local data = value
        local amount = 1

        if type(value) == "number" then
            amount = value
            data = {}
        elseif type(value) ~= "table" then
            data = {}
        else
            amount = tonumber(
                rawget(value, "_am")
                or rawget(value, "am")
                or rawget(value, "amount")
                or rawget(value, "Amount")
                or 1
            ) or 1

            uid = tostring(
                rawget(value, "_uid")
                or rawget(value, "uid")
                or rawget(value, "UID")
                or key
            )
        end

        local id = tostring(
            rawget(data, "id")
            or rawget(data, "ID")
            or rawget(data, "_id")
            or rawget(data, "name")
            or rawget(data, "Name")
            or key
        )

        local tier = math.max(
            1,
            math.floor(
                tonumber(
                    rawget(data, "tier")
                    or rawget(data, "Tier")
                    or rawget(data, "_tier")
                    or 1
                ) or 1
            )
        )

        if uid ~= ""
            and id ~= ""
            and amount > 0
        then
            table.insert(
                output,
                {
                    UID = uid,
                    ID = id,
                    Name = id,
                    Tier = tier,
                    Amount =
                        math.max(
                            1,
                            math.floor(amount)
                        ),
                    Kind = kindName,
                }
            )
        end
    end

    table.sort(output, function(left, right)
        if left.Name ~= right.Name then
            return left.Name < right.Name
        end

        if left.Tier ~= right.Tier then
            return left.Tier < right.Tier
        end

        return left.UID < right.UID
    end)

    return output
end

function CoreAutomation.refreshConsumables(force)
    if not force
        and os.clock() - CoreAutomation.AutomaticEngine.LastRefreshAt < 1.5
    then
        return
    end

    CoreAutomation.AutomaticEngine.LastRefreshAt = os.clock()

    local function readItems(itemClass, kindName)
        local output = {}

        if not itemClass or type(itemClass.All) ~= "function" then
            return output
        end

        local okAll, all = pcall(itemClass.All, itemClass)
        if not okAll or type(all) ~= "table" then
            return output
        end

        for _, item in pairs(all) do
            if type(item) == "table" then
                local uid = tostring(itemMethod(item, "GetUID", ""))
                local id = tostring(itemMethod(item, "GetId", ""))
                local name = tostring(itemMethod(item, "GetName", id))
                local amount = math.max(
                    0,
                    math.floor(tonumber(itemMethod(item, "GetAmount", 0)) or 0)
                )
                local tier = math.max(
                    1,
                    math.floor(tonumber(itemMethod(item, "GetTier", 1)) or 1)
                )
                local shiny = itemMethod(item, "IsShiny", false) == true

                local allowed =
                    kindName ~= "Potion"
                    or tier >= 7

                if allowed
                    and uid ~= ""
                    and id ~= ""
                    and amount > 0
                then
                    table.insert(output, {
                        Item = item,
                        UID = uid,
                        ID = id,
                        Name = name,
                        DisplayName = shiny and ("Shiny " .. name) or name,
                        Tier = tier,
                        Amount = amount,
                        Shiny = shiny,
                        Variant = shiny and "Shiny" or "Normal",
                        Kind = kindName,
                    })
                end
            end
        end

        table.sort(output, function(left, right)
            if left.Name ~= right.Name then
                return left.Name < right.Name
            end
            if left.Shiny ~= right.Shiny then
                return left.Shiny == false
            end
            if left.Tier ~= right.Tier then
                return left.Tier > right.Tier
            end
            return left.UID < right.UID
        end)

        return output
    end

    CoreAutomation.AutomaticEngine.Fruits =
        readItems(CoreAutomation.FruitItem, "Fruit")
    CoreAutomation.AutomaticEngine.Potions =
        readItems(CoreAutomation.PotionItem, "Potion")
end

function CoreAutomation.fruitSelectionKey(entry)
    if not entry then
        return ""
    end

    return tostring(entry.ID)
        .. "|"
        .. tostring(entry.Variant or "Normal")
end

function CoreAutomation.potionSelectionKey(entry)
    if not entry then
        return ""
    end

    return tostring(entry.ID)
        .. "|"
        .. tostring(entry.Tier)
end

function CoreAutomation.fruitIsSelected(entry)
    local key = CoreAutomation.fruitSelectionKey(entry)

    if key == "" then
        return false
    end

    local selected =
        CoreAutomation.AutomaticEngine.FruitSelection[key]

    if selected == nil and entry then
        selected =
            CoreAutomation.AutomaticEngine
                .FruitSelection[tostring(entry.ID)]
    end

    return selected ~= false
end

function CoreAutomation.potionCategoryName(entry)
    if not entry then
        return "Potion"
    end

    local name = tostring(entry.Name or entry.ID or "Potion")

    -- Potion names are normally like "Coins Potion VII". Keep only the
    -- useful category name so the UI shows Coins, Diamonds, Treasure Hunter,
    -- Walkspeed, etc. instead of one row for every Roman-numeral tier.
    name = string.gsub(name, "%s+[Pp]otion%s+[%u]+$", "")
    name = string.gsub(name, "%s+[Pp]otion%s+%d+$", "")
    name = string.gsub(name, "%s+[Pp]otion$", "")
    name = string.gsub(name, "_", " ")

    if name == "" or name == "Potion" then
        name = tostring(entry.ID or "Potion")
    end

    return name
end

function CoreAutomation.potionCategorySelected(categoryID)
    local found = false

    for _, entry in ipairs(
        CoreAutomation.AutomaticEngine.Potions
    ) do
        if entry.ID == categoryID then
            found = true
            if not CoreAutomation.potionIsSelected(entry) then
                return false
            end
        end
    end

    return found
end

function CoreAutomation.setPotionCategorySelected(
    categoryID,
    enabled
)
    for _, entry in ipairs(
        CoreAutomation.AutomaticEngine.Potions
    ) do
        if entry.ID == categoryID then
            CoreAutomation.setPotionSelected(
                entry,
                enabled
            )
        end
    end
end

function CoreAutomation.potionIsSelected(entry)
    local key =
        CoreAutomation.potionSelectionKey(entry)

    return key ~= ""
        and CoreAutomation.AutomaticEngine
            .PotionSelection[key] ~= false
end

function CoreAutomation.setFruitSelected(
    entry,
    enabled
)
    local key =
        CoreAutomation.fruitSelectionKey(entry)

    if key == "" then
        return
    end

    CoreAutomation.AutomaticEngine
        .FruitSelection[key] =
        enabled == true

    Config.automatic.fruitSelection =
        CoreAutomation.AutomaticEngine
            .FruitSelection

    markConfigDirty()
end

function CoreAutomation.setPotionSelected(
    entry,
    enabled
)
    local key =
        CoreAutomation.potionSelectionKey(entry)

    if key == "" then
        return
    end

    CoreAutomation.AutomaticEngine
        .PotionSelection[key] =
        enabled == true

    Config.automatic.potionSelection =
        CoreAutomation.AutomaticEngine
            .PotionSelection

    markConfigDirty()
end

function CoreAutomation.potionIsActive(entry)
    if not entry
        or not CoreAutomation.PotionCmds
        or type(CoreAutomation.PotionCmds.GetPotionData) ~= "function"
    then
        return false
    end

    local ok, activeTier, remaining = pcall(
        CoreAutomation.PotionCmds.GetPotionData,
        entry.ID
    )

    if not ok or not activeTier then
        return false
    end

    return tonumber(activeTier) >= tonumber(entry.Tier)
        and tonumber(remaining or 0) > 5
end

function CoreAutomation.consumeSelectedFruits()
    CoreAutomation.refreshConsumables(true)

    if not CoreAutomation.FruitCmds
        or type(CoreAutomation.FruitCmds.GetMaxConsume) ~= "function"
        or type(CoreAutomation.FruitCmds.Consume) ~= "function"
    then
        CoreAutomation.AutomaticEngine.LastError =
            "Fruit controls unavailable"
        return
    end

    local calls = 0

    -- Shiny is stronger, so consume selected Shiny stacks before regular
    -- stacks when both variants of the same fruit are enabled.
    local entries = table.clone(CoreAutomation.AutomaticEngine.Fruits)
    table.sort(entries, function(left, right)
        if left.ID ~= right.ID then
            return left.ID < right.ID
        end
        if left.Shiny ~= right.Shiny then
            return left.Shiny == true
        end
        return left.UID < right.UID
    end)

    for _, entry in ipairs(entries) do
        if CoreAutomation.fruitIsSelected(entry) then
            local okMax, maximum = pcall(
                CoreAutomation.FruitCmds.GetMaxConsume,
                entry.UID
            )
            maximum = okMax and math.max(0, math.floor(tonumber(maximum) or 0)) or 0

            local amount = math.min(entry.Amount, maximum)

            if amount > 0 then
                local ok, err = pcall(
                    CoreAutomation.FruitCmds.Consume,
                    entry.UID,
                    amount
                )

                if ok then
                    calls = calls + 1
                    CoreAutomation.AutomaticEngine.Stats.FruitCalls =
                        CoreAutomation.AutomaticEngine.Stats.FruitCalls + 1
                    CoreAutomation.AutomaticEngine.LastAction =
                        "Ate " .. tostring(amount) .. " " .. entry.DisplayName
                else
                    CoreAutomation.AutomaticEngine.LastError = tostring(err)
                    CoreAutomation.AutomaticEngine.Stats.Errors =
                        CoreAutomation.AutomaticEngine.Stats.Errors + 1
                end

                task.wait(0.16)
            end
        end
    end

    if calls == 0 then
        CoreAutomation.AutomaticEngine.LastAction =
            "Fruit boosts are full or unavailable"
    end

    task.delay(0.35, function()
        CoreAutomation.refreshConsumables(true)
        if CoreAutomation.rebuildFruitConfigRows
            and CoreAutomation.AutomaticEngine.FruitConfigExpanded
        then
            CoreAutomation.rebuildFruitConfigRows()
        end
    end)
end

function CoreAutomation.consumeSelectedPotions()
    CoreAutomation.refreshConsumables(true)

    if not CoreAutomation.PotionCmds
        or type(CoreAutomation.PotionCmds.Consume) ~= "function"
    then
        CoreAutomation.AutomaticEngine.LastError =
            "Potion controls unavailable"
        return
    end

    local bestByID = {}

    for _, entry in ipairs(CoreAutomation.AutomaticEngine.Potions) do
        if CoreAutomation.potionIsSelected(entry) then
            local usable = true

            if CoreAutomation.MasteryCmds
                and type(CoreAutomation.MasteryCmds.CanUsePotion) == "function"
            then
                local okUse, canUse = pcall(
                    CoreAutomation.MasteryCmds.CanUsePotion,
                    entry.Tier
                )
                usable = okUse and canUse == true
            end

            if usable then
                local current = bestByID[entry.ID]
                if not current or entry.Tier > current.Tier then
                    bestByID[entry.ID] = entry
                end
            end
        end
    end

    local calls = 0

    for _, entry in pairs(bestByID) do
        if not CoreAutomation.potionIsActive(entry) then
            local ok, err = pcall(
                CoreAutomation.PotionCmds.Consume,
                entry.UID,
                1
            )

            if ok then
                calls = calls + 1
                CoreAutomation.AutomaticEngine.Stats.PotionCalls =
                    CoreAutomation.AutomaticEngine.Stats.PotionCalls + 1
                CoreAutomation.AutomaticEngine.LastAction =
                    "Used " .. entry.Name .. " Tier " .. tostring(entry.Tier)
            else
                CoreAutomation.AutomaticEngine.LastError = tostring(err)
                CoreAutomation.AutomaticEngine.Stats.Errors =
                    CoreAutomation.AutomaticEngine.Stats.Errors + 1
            end

            task.wait(0.16)
        end
    end

    if calls == 0 then
        CoreAutomation.AutomaticEngine.LastAction =
            next(bestByID)
            and "Selected potions are active"
            or "No usable selected potions"
    end

    task.delay(0.35, function()
        CoreAutomation.refreshConsumables(true)
    end)
end

function CoreAutomation.invokeToy(remoteName)
    local ok, success, message = pcall(
        Network.Invoke,
        remoteName
    )

    if not ok then
        return false, tostring(success)
    end

    -- A false return normally means cooldown/not ready.
    if success == true then
        CoreAutomation.AutomaticEngine
            .Stats.ToyCalls =
            CoreAutomation.AutomaticEngine
                .Stats.ToyCalls + 1

        return true
    end

    return true,
        tostring(
            message
            or success
            or "not ready"
        )
end

function CoreAutomation.useToys()
    local used = 0

    local okSqueaky, errSqueaky =
        CoreAutomation.invokeToy(
            "SqueakyToy_Consume"
        )

    if okSqueaky then
        used = used + 1
    else
        CoreAutomation.AutomaticEngine.LastError =
            errSqueaky
    end

    task.wait(0.12)

    local okBall, errBall =
        CoreAutomation.invokeToy(
            "ToyBall_Consume"
        )

    if okBall then
        used = used + 1
    else
        CoreAutomation.AutomaticEngine.LastError =
            errBall
    end

    if used > 0 then
        CoreAutomation.AutomaticEngine.LastAction =
            "Checked both toys"
    end
end

function CoreAutomation.useUltimate()
    if not CoreAutomation.UltimateCmds
        or type(CoreAutomation.UltimateCmds.GetEquippedItem) ~= "function"
    then
        CoreAutomation.AutomaticEngine.LastError =
            "Ultimate controls unavailable"
        return false
    end

    local okItem, item = pcall(
        CoreAutomation.UltimateCmds.GetEquippedItem
    )

    if not okItem or not item then
        CoreAutomation.AutomaticEngine.LastAction =
            "No ultimate equipped"
        return false
    end

    local ultimateID = tostring(itemMethod(item, "GetId", ""))

    if ultimateID == "" then
        CoreAutomation.AutomaticEngine.LastAction =
            "No ultimate equipped"
        return false
    end

    CoreAutomation.AutomaticEngine.UltimateName = ultimateID
    Config.automatic.ultimateName = ultimateID

    if type(CoreAutomation.UltimateCmds.IsCharged) == "function" then
        local okCharged, charged = pcall(
            CoreAutomation.UltimateCmds.IsCharged,
            ultimateID
        )

        if okCharged and charged ~= true then
            CoreAutomation.AutomaticEngine.LastAction =
                ultimateID .. " charging"
            return true
        end
    end

    local ok, success = pcall(
        CoreAutomation.UltimateCmds.Activate,
        ultimateID
    )

    if not ok then
        CoreAutomation.AutomaticEngine.LastError = tostring(success)
        CoreAutomation.AutomaticEngine.Stats.Errors =
            CoreAutomation.AutomaticEngine.Stats.Errors + 1
        return false
    end

    if success == true then
        CoreAutomation.AutomaticEngine.Stats.UltimateCalls =
            CoreAutomation.AutomaticEngine.Stats.UltimateCalls + 1
        CoreAutomation.AutomaticEngine.LastAction =
            "Activated " .. ultimateID
        return true
    end

    CoreAutomation.AutomaticEngine.LastAction =
        ultimateID .. " charging"
    return true
end

function CoreAutomation.setAutomaticFeature(
    name,
    enabled
)
    enabled = enabled == true

    if name == "Fruit" then
        CoreAutomation.AutomaticEngine.AutoFruit =
            enabled
        Config.automatic.autoFruit = enabled
        CoreAutomation.AutomaticEngine.NextFruitAt = 0
    elseif name == "Potion" then
        CoreAutomation.AutomaticEngine.AutoPotion =
            enabled
        Config.automatic.autoPotion = enabled
        CoreAutomation.AutomaticEngine.NextPotionAt = 0
    elseif name == "Toys" then
        CoreAutomation.AutomaticEngine.AutoToys =
            enabled
        Config.automatic.autoToys = enabled

        -- Retire old split-toy toggles.
        Config.automatic.autoSqueakyToy = false
        Config.automatic.autoToyBall = false

        CoreAutomation.AutomaticEngine.NextToyAt = 0
    elseif name == "Ultimate" then
        CoreAutomation.AutomaticEngine.AutoUltimate =
            enabled
        Config.automatic.autoUltimate = enabled
        CoreAutomation.AutomaticEngine.NextUltimateAt = 0
    end

    markConfigDirty()

    if CoreAutomation.refreshAutomaticUI then
        CoreAutomation.refreshAutomaticUI()
    end
end

task.spawn(function()
    while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
        and CoreAutomation.AutomaticEngine.Alive
    do
        task.wait(0.25)

        local now = os.clock()

        if CoreAutomation.AutomaticEngine.AutoFruit
            and now
                >= CoreAutomation.AutomaticEngine
                    .NextFruitAt
        then
            CoreAutomation.AutomaticEngine.NextFruitAt =
                now
                + CoreAutomation.AutomaticEngine
                    .FruitInterval

            CoreAutomation.consumeSelectedFruits()
        end

        if CoreAutomation.AutomaticEngine.AutoPotion
            and now
                >= CoreAutomation.AutomaticEngine
                    .NextPotionAt
        then
            CoreAutomation.AutomaticEngine.NextPotionAt =
                now
                + CoreAutomation.AutomaticEngine
                    .PotionInterval

            CoreAutomation.consumeSelectedPotions()
        end

        if CoreAutomation.AutomaticEngine.AutoToys
            and now
                >= CoreAutomation.AutomaticEngine
                    .NextToyAt
        then
            CoreAutomation.AutomaticEngine.NextToyAt =
                now
                + CoreAutomation.AutomaticEngine
                    .ToyInterval

            CoreAutomation.useToys()
        end

        if CoreAutomation.AutomaticEngine.AutoUltimate
            and now
                >= CoreAutomation.AutomaticEngine
                    .NextUltimateAt
        then
            CoreAutomation.AutomaticEngine.NextUltimateAt =
                now
                + CoreAutomation.AutomaticEngine
                    .UltimateInterval

            CoreAutomation.useUltimate()
        end

        if CoreAutomation.refreshAutomaticUI then
            CoreAutomation.refreshAutomaticUI()
        end
    end
end)

--//////////////////////////////////////////////////////////////////
-- Best-area travel
--//////////////////////////////////////////////////////////////////

CoreAutomation.BestAreaEngine = {
    Alive = true,
    Auto = Config.teleports.autoBestArea == true,
    Busy = false,
    Interval = 2.5,
    LastCheckAt = 0,
    LastBestID = nil,
    LastPosition = nil,
    LastAction = "Idle",
    LastError = nil,
    Stats = {
        Checks = 0,
        Teleports = 0,
        Errors = 0,
    },
}

function CoreAutomation.areaNumber(value)
    if type(value) == "number" then
        return math.floor(value)
    end

    if type(value) == "string" then
        local number =
            tonumber(
                string.match(value, "%d+")
            )

        if number then
            return math.floor(number)
        end
    elseif type(value) == "table" then
        local fields = {
            "id",
            "ID",
            "zone",
            "Zone",
            "zoneId",
            "ZoneId",
            "area",
            "Area",
            "areaId",
            "AreaId",
            "_id",
            "ZoneName",
            "ZoneNumber",
            "number",
            "Number",
        }

        for _, field in ipairs(fields) do
            local number =
                CoreAutomation.areaNumber(
                    rawget(value, field)
                )

            if number then
                return number
            end
        end
    end

    return nil
end

function CoreAutomation.bestAreaFromTable(
    value,
    currentBest,
    depth,
    seen
)
    currentBest = tonumber(currentBest) or 0
    depth = depth or 0
    seen = seen or {}

    if type(value) ~= "table"
        or depth > 3
        or seen[value]
    then
        return currentBest
    end

    seen[value] = true

    for key, child in pairs(value) do
        local keyNumber =
            CoreAutomation.areaNumber(key)

        local childNumber =
            CoreAutomation.areaNumber(child)

        if keyNumber
            and (
                child == true
                or child == 1
                or type(child) == "table"
            )
        then
            currentBest =
                math.max(currentBest, keyNumber)
        end

        if childNumber then
            currentBest =
                math.max(currentBest, childNumber)
        end

        if type(child) == "table" then
            currentBest =
                CoreAutomation.bestAreaFromTable(
                    child,
                    currentBest,
                    depth + 1,
                    seen
                )
        end
    end

    seen[value] = nil
    return currentBest
end

function CoreAutomation.resolveBestAreaID()
    local best = 0

    if CoreAutomation.MapCmds then
        local methodNames = {
            "GetBestZone",
            "GetBestArea",
            "GetMaxZone",
            "GetMaxArea",
            "GetHighestZone",
            "GetHighestArea",
            "GetLastZone",
        }

        for _, methodName in ipairs(methodNames) do
            local method =
                CoreAutomation.MapCmds[methodName]

            if type(method) == "function" then
                local ok, result = pcall(method)

                if ok then
                    local number =
                        CoreAutomation.areaNumber(result)

                    if number then
                        best = math.max(best, number)
                    end
                end
            end
        end
    end

    local save = getSaveTable()

    if type(save) == "table" then
        local directFields = {
            "BestArea",
            "BestZone",
            "CurrentArea",
            "CurrentZone",
            "LastArea",
            "LastZone",
            "MaxArea",
            "MaxZone",
        }

        for _, field in ipairs(directFields) do
            local number =
                CoreAutomation.areaNumber(
                    rawget(save, field)
                )

            if number then
                best = math.max(best, number)
            end
        end

        local tableFields = {
            "AreasUnlocked",
            "ZonesUnlocked",
            "Areas",
            "Zones",
            "Map",
        }

        for _, field in ipairs(tableFields) do
            best =
                CoreAutomation.bestAreaFromTable(
                    rawget(save, field),
                    best
                )
        end
    end

    -- Final fallback: use the highest loaded breakable parent ID.
    for _, instance in ipairs(
        CoreAutomation.farmBreakableInstances()
    ) do
        local uid =
            CoreAutomation.farmBreakableUID(instance)

        if uid
            and CoreAutomation.BreakableFrontend
            and type(
                CoreAutomation.BreakableFrontend.Get
            ) == "function"
        then
            local ok, data = pcall(
                CoreAutomation.BreakableFrontend.Get,
                uid
            )

            if ok and type(data) == "table" then
                local number =
                    CoreAutomation.areaNumber(
                        rawget(data, "parentID")
                    )

                if number then
                    best = math.max(best, number)
                end
            end
        end
    end

    if best > 0 then
        return math.floor(best)
    end

    return nil
end

function CoreAutomation.areaInstanceMatches(
    instance,
    areaID
)
    if not instance or not areaID then
        return false
    end

    local values = {
        instance:GetAttribute("ZoneID"),
        instance:GetAttribute("ZoneId"),
        instance:GetAttribute("AreaID"),
        instance:GetAttribute("AreaId"),
        instance:GetAttribute("ID"),
        instance.Name,
    }

    for _, value in ipairs(values) do
        if CoreAutomation.areaNumber(value)
            == areaID
        then
            return true
        end
    end

    return false
end

function CoreAutomation.bestAreaBreakablePosition(
    areaID
)
    local positions = {}

    for _, instance in ipairs(
        CoreAutomation.farmBreakableInstances()
    ) do
        local uid =
            CoreAutomation.farmBreakableUID(instance)

        if uid
            and CoreAutomation.BreakableFrontend
            and type(
                CoreAutomation.BreakableFrontend.Get
            ) == "function"
        then
            local ok, data = pcall(
                CoreAutomation.BreakableFrontend.Get,
                uid
            )

            if ok and type(data) == "table" then
                local parentID =
                    CoreAutomation.areaNumber(
                        rawget(data, "parentID")
                    )

                local position =
                    rawget(data, "position")

                if parentID == areaID
                    and typeof(position) == "Vector3"
                then
                    table.insert(
                        positions,
                        position
                    )

                    if #positions >= 24 then
                        break
                    end
                end
            end
        end
    end

    if #positions == 0 then
        return nil
    end

    local total = Vector3.zero

    for _, position in ipairs(positions) do
        total = total + position
    end

    return total / #positions
end

function CoreAutomation.bestAreaModelPosition(
    areaID
)
    local things =
        Workspace:FindFirstChild("__THINGS")

    local roots = {
        things
            and things:FindFirstChild("Zones"),
        things
            and things:FindFirstChild("Areas"),
        Workspace:FindFirstChild("__MAP"),
        Workspace:FindFirstChild("Map"),
    }

    for _, root in ipairs(roots) do
        if root then
            for _, instance in ipairs(
                root:GetDescendants()
            ) do
                if CoreAutomation.areaInstanceMatches(
                    instance,
                    areaID
                ) then
                    if instance:IsA("BasePart") then
                        return instance.Position
                    elseif instance:IsA("Model") then
                        local preferredNames = {
                            "Teleport",
                            "Spawn",
                            "Center",
                            "Floor",
                            "Main",
                        }

                        for _, name in ipairs(
                            preferredNames
                        ) do
                            local part =
                                instance:FindFirstChild(
                                    name,
                                    true
                                )

                            if part
                                and part:IsA("BasePart")
                            then
                                return part.Position
                            end
                        end

                        local ok, pivot = pcall(
                            instance.GetPivot,
                            instance
                        )

                        if ok then
                            return pivot.Position
                        end
                    end
                end
            end
        end
    end

    return nil
end

function CoreAutomation.bestAreaGroundPosition(zoneName, areaID)
    local things = Workspace:FindFirstChild("__THINGS")
    local roots = {
        things and things:FindFirstChild("__FAKE_GROUND"),
        things and things:FindFirstChild("__FAKE_INSTANCE_GROUND"),
        things and things:FindFirstChild("__FAKE_INSTANCE_BREAK_ZONES"),
        Workspace:FindFirstChild("__MAP"),
        Workspace:FindFirstChild("Map"),
    }

    local wantedName = tostring(zoneName or "")
    local wantedNumber = tonumber(areaID)

    for _, root in ipairs(roots) do
        if root then
            local direct = wantedName ~= "" and root:FindFirstChild(wantedName, true)
            if direct then
                if direct:IsA("BasePart") then
                    return direct.Position
                elseif direct:IsA("Model") then
                    local ok, pivot = pcall(direct.GetPivot, direct)
                    if ok then return pivot.Position end
                end
            end

            for _, instance in ipairs(root:GetDescendants()) do
                local number = CoreAutomation.areaNumber(instance.Name)
                if (wantedNumber and number == wantedNumber)
                    or (wantedName ~= "" and instance.Name == wantedName)
                then
                    if instance:IsA("BasePart") then
                        return instance.Position
                    elseif instance:IsA("Model") then
                        local ok, pivot = pcall(instance.GetPivot, instance)
                        if ok then return pivot.Position end
                    end
                end
            end
        end
    end

    return nil
end

function CoreAutomation.resolveBestAreaPosition(areaID, zoneName)
    return CoreAutomation.bestAreaGroundPosition(zoneName, areaID)
        or CoreAutomation.bestAreaBreakablePosition(areaID)
        or CoreAutomation.bestAreaModelPosition(areaID)
end

function CoreAutomation.teleportToBestArea(silent)
    if CoreAutomation.BestAreaEngine.Busy then
        return false, "Busy"
    end

    CoreAutomation.BestAreaEngine.Busy = true
    CoreAutomation.BestAreaEngine.Stats.Checks =
        CoreAutomation.BestAreaEngine.Stats.Checks + 1

    local zoneName = nil
    local zoneDirectory = nil
    if CoreAutomation.ZoneCmds
        and type(CoreAutomation.ZoneCmds.GetMaxOwnedZone) == "function"
    then
        local okZone, first, second = pcall(
            CoreAutomation.ZoneCmds.GetMaxOwnedZone
        )
        if okZone then
            zoneName = first
            zoneDirectory = second
        end
    end

    local areaID = CoreAutomation.areaNumber(zoneDirectory)
        or CoreAutomation.areaNumber(zoneName)
        or CoreAutomation.resolveBestAreaID()
    local position = CoreAutomation.resolveBestAreaPosition(areaID, zoneName)
    local character = LocalPlayer and LocalPlayer.Character

    if position and character then
        local root = character:FindFirstChild("HumanoidRootPart")
        local rotation = root and (root.CFrame - root.Position) or CFrame.new()
        local okMove, moveError = pcall(
            character.PivotTo,
            character,
            CFrame.new(position + Vector3.new(0, 5, 0)) * rotation
        )

        CoreAutomation.BestAreaEngine.Busy = false
        if okMove then
            CoreAutomation.BestAreaEngine.Stats.Teleports =
                CoreAutomation.BestAreaEngine.Stats.Teleports + 1
            CoreAutomation.BestAreaEngine.LastBestID = tostring(zoneName or areaID)
            CoreAutomation.BestAreaEngine.LastError = nil
            CoreAutomation.BestAreaEngine.LastAction = "At Best Area"
            if not silent then setNotice("Moved to Best Area.", "success") end
            return true, zoneName or areaID
        end
        CoreAutomation.BestAreaEngine.LastError = tostring(moveError)
    else
        CoreAutomation.BestAreaEngine.Busy = false
        CoreAutomation.BestAreaEngine.LastError = "Best Area is not loaded"
    end

    CoreAutomation.BestAreaEngine.Stats.Errors =
        CoreAutomation.BestAreaEngine.Stats.Errors + 1
    if not silent then setNotice("Best Area is not loaded yet.", "error") end
    return false, CoreAutomation.BestAreaEngine.LastError
end

function CoreAutomation.setAutoBestArea(enabled)
    CoreAutomation.BestAreaEngine.Auto =
        enabled == true

    Config.teleports.autoBestArea =
        CoreAutomation.BestAreaEngine.Auto

    CoreAutomation.BestAreaEngine.LastCheckAt = 0

    markConfigDirty()

    if CoreAutomation.refreshBestAreaUI then
        CoreAutomation.refreshBestAreaUI()
    end
end

task.spawn(function()
    while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation and CoreAutomation.BestAreaEngine.Alive do
        task.wait(1)

        if CoreAutomation.BestAreaEngine.Auto
            and not CoreAutomation.BestAreaEngine.Busy
            and os.clock() - CoreAutomation.BestAreaEngine.LastCheckAt
                >= math.max(3, CoreAutomation.BestAreaEngine.Interval)
        then
            CoreAutomation.BestAreaEngine.LastCheckAt = os.clock()

            local zoneName = nil
            if CoreAutomation.ZoneCmds
                and type(CoreAutomation.ZoneCmds.GetMaxOwnedZone) == "function"
            then
                local ok, value = pcall(CoreAutomation.ZoneCmds.GetMaxOwnedZone)
                if ok then zoneName = value end
            end

            local root = CoreAutomation.permanentRootPart()
            local areaID = CoreAutomation.areaNumber(zoneName)
            local center = CoreAutomation.resolveBestAreaPosition(areaID, zoneName)
            local far = center and root and (root.Position - center).Magnitude > 35

            if zoneName ~= CoreAutomation.BestAreaEngine.LastBestID or far then
                CoreAutomation.teleportToBestArea(true)
            end
        end

        if CoreAutomation.refreshBestAreaUI then
            CoreAutomation.refreshBestAreaUI()
        end
    end
end)

--//////////////////////////////////////////////////////////////////
-- Rank rewards
--//////////////////////////////////////////////////////////////////

CoreAutomation.RankEngine = {
    Alive = true,
    AutoClaim = Config.main.autoRankRewards == true,
    LastAction = "Idle",
    LastError = nil,
    LastDetected = {},
    LastAttempt = {},
    Stats = {Detected = 0, Claims = 0, Errors = 0},
}

function CoreAutomation.rankCandidateFromInstance(instance)
    local attributes = {
        instance:GetAttribute("RewardIndex"),
        instance:GetAttribute("Index"),
        instance:GetAttribute("Tier"),
        instance:GetAttribute("ID"),
    }
    for _, value in ipairs(attributes) do
        if tonumber(value) then
            return math.floor(tonumber(value))
        end
    end
    local current = instance
    for _ = 1, 4 do
        if not current then break end
        local number = tonumber(string.match(current.Name, "%d+"))
        if number then
            return math.floor(number)
        end
        current = current.Parent
    end
    return nil
end

function CoreAutomation.detectRankRewardIndexes()
    local indexes = {}
    local seen = {}
    local save = getSaveTable()

    if save
        and type(CoreAutomation.RanksDirectory) == "table"
    then
        local rankNumber = tonumber(rawget(save, "Rank"))
        local rankStars = tonumber(rawget(save, "RankStars")) or 0
        local redeemed = rawget(save, "RedeemedRankRewards")
        redeemed = type(redeemed) == "table" and redeemed or {}
        local rankDirectory = nil

        for _, directory in pairs(
            CoreAutomation.RanksDirectory
        ) do
            if type(directory) == "table"
                and tonumber(rawget(directory, "RankNumber")) == rankNumber
            then
                rankDirectory = directory
                break
            end
        end

        local rewards = rankDirectory
            and rawget(rankDirectory, "Rewards")
            or nil

        if type(rewards) == "table" then
            local ordered = {}

            for key, reward in pairs(rewards) do
                local index = tonumber(key)
                if index and type(reward) == "table" then
                    table.insert(ordered, {
                        Index = math.floor(index),
                        Reward = reward,
                    })
                end
            end

            table.sort(ordered, function(left, right)
                return left.Index < right.Index
            end)

            local starsNeeded = 0

            for _, data in ipairs(ordered) do
                starsNeeded = starsNeeded
                    + (tonumber(
                        rawget(data.Reward, "StarsRequired")
                    ) or 0)

                local claimed =
                    redeemed[tostring(data.Index)] ~= nil
                    or redeemed[data.Index] ~= nil

                if rankStars >= starsNeeded
                    and not claimed
                    and not seen[data.Index]
                then
                    seen[data.Index] = true
                    table.insert(indexes, data.Index)
                end
            end
        end
    end

    -- Fallback only when save/directory data has not loaded yet.
    if #indexes == 0 and not save then
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")

        for _, instance in ipairs(
            playerGui and playerGui:GetDescendants() or {}
        ) do
            if instance:IsA("GuiButton")
                and instance.Visible
                and instance.Active
            then
                local text = lower(
                    instance:IsA("TextButton")
                    and instance.Text
                    or instance.Name
                )
                local parentText = lower(
                    instance.Parent
                    and instance.Parent.Name
                    or ""
                )

                if string.find(text, "claim", 1, true)
                    or string.find(parentText, "rankreward", 1, true)
                    or string.find(parentText, "rank reward", 1, true)
                then
                    local index =
                        CoreAutomation.rankCandidateFromInstance(instance)

                    if index
                        and index >= 1
                        and index <= 500
                        and not seen[index]
                    then
                        seen[index] = true
                        table.insert(indexes, index)
                    end
                end
            end
        end
    end

    table.sort(indexes)
    CoreAutomation.RankEngine.LastDetected = indexes
    CoreAutomation.RankEngine.Stats.Detected = #indexes
    return indexes
end

function CoreAutomation.claimDetectedRankRewards()
    local indexes =
        CoreAutomation.detectRankRewardIndexes()

    if #indexes == 0 then
        CoreAutomation.RankEngine.LastAction =
            "No rank rewards ready"
        if CoreAutomation.refreshRankUI then
            CoreAutomation.refreshRankUI()
        end
        return 0
    end

    local attempted = 0

    for _, index in ipairs(indexes) do
        if os.clock()
            - (CoreAutomation.RankEngine.LastAttempt[index] or 0)
            >= 1.5
        then
            CoreAutomation.RankEngine.LastAttempt[index] = os.clock()

            local ok, err = pcall(
                Network.Fire,
                "Ranks_ClaimReward",
                index
            )

            if ok then
                attempted = attempted + 1
            else
                CoreAutomation.RankEngine.LastError = tostring(err)
                CoreAutomation.RankEngine.Stats.Errors =
                    CoreAutomation.RankEngine.Stats.Errors + 1
            end

            task.wait(0.20)
        end
    end

    task.wait(0.35)

    local remaining =
        CoreAutomation.detectRankRewardIndexes()
    local claimed = math.max(0, #indexes - #remaining)

    CoreAutomation.RankEngine.Stats.Claims =
        CoreAutomation.RankEngine.Stats.Claims + claimed
    CoreAutomation.RankEngine.LastAction =
        claimed > 0
        and ("Claimed " .. tostring(claimed) .. " rank reward(s)")
        or ("Sent " .. tostring(attempted) .. " rank claim(s)")

    if CoreAutomation.refreshRankUI then
        CoreAutomation.refreshRankUI()
    end

    return claimed
end

task.spawn(function()
    while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation and CoreAutomation.RankEngine.Alive do
        task.wait(1.5)
        if CoreAutomation.RankEngine.AutoClaim then
            CoreAutomation.claimDetectedRankRewards()
        else
            CoreAutomation.detectRankRewardIndexes()
            if CoreAutomation.refreshRankUI then CoreAutomation.refreshRankUI() end
        end
    end
end)

--//////////////////////////////////////////////////////////////////
-- Timed Free Gifts
--//////////////////////////////////////////////////////////////////

CoreAutomation.FreeGiftEngine = {
    Alive = true,
    AutoClaim = Config.main.autoFreeGifts == true,
    Busy = false,
    MaxIndex = 12,
    ScanCooldown = 5,
    NextScanAt = 0,
    LastAction = "Idle",
    LastError = nil,
    LastDetected = {},
    LastResults = {},
    Stats = {
        Passes = 0,
        Attempts = 0,
        Claims = 0,
        Rejections = 0,
        Errors = 0,
    },
}

function CoreAutomation.freeGiftCandidateFromInstance(instance)
    local attributes = {
        instance:GetAttribute("GiftIndex"),
        instance:GetAttribute("RewardIndex"),
        instance:GetAttribute("Index"),
        instance:GetAttribute("ID"),
    }

    for _, value in ipairs(attributes) do
        local number = tonumber(value)

        if number then
            number = math.floor(number)

            if number >= 1
                and number <= CoreAutomation.FreeGiftEngine.MaxIndex
            then
                return number
            end
        end
    end

    local current = instance

    for _ = 1, 5 do
        if not current then
            break
        end

        local number =
            tonumber(
                string.match(
                    tostring(current.Name),
                    "%d+"
                )
            )

        if number
            and number >= 1
            and number <= CoreAutomation.FreeGiftEngine.MaxIndex
        then
            return math.floor(number)
        end

        current = current.Parent
    end

    return nil
end

function CoreAutomation.detectTimedFreeGiftIndexes()
    local indexes = {}
    local seen = {}
    local save = getSaveTable()

    if save
        and type(CoreAutomation.FreeGiftsDirectory) == "table"
    then
        local elapsed = tonumber(
            rawget(save, "FreeGiftsTime")
        ) or 0
        local redeemed = rawget(save, "FreeGiftsRedeemed")
        redeemed = type(redeemed) == "table" and redeemed or {}

        local function wasRedeemed(index)
            if redeemed[index] == true
                or redeemed[tostring(index)] == true
            then
                return true
            end

            for _, value in pairs(redeemed) do
                if tonumber(value) == index then
                    return true
                end
            end

            return false
        end

        for key, gift in pairs(
            CoreAutomation.FreeGiftsDirectory
        ) do
            if type(gift) == "table" then
                local index = tonumber(
                    rawget(gift, "Id")
                    or rawget(gift, "ID")
                    or key
                )
                local waitTime = tonumber(
                    rawget(gift, "WaitTime")
                )

                if index and waitTime then
                    index = math.floor(index)
                    CoreAutomation.FreeGiftEngine.MaxIndex =
                        math.max(
                            CoreAutomation.FreeGiftEngine.MaxIndex,
                            index
                        )

                    if elapsed >= waitTime
                        and not wasRedeemed(index)
                        and not seen[index]
                    then
                        seen[index] = true
                        table.insert(indexes, index)
                    end
                end
            end
        end
    end

    table.sort(indexes)
    CoreAutomation.FreeGiftEngine.LastDetected = indexes
    return indexes
end

function CoreAutomation.claimTimedFreeGifts(
    forceFullScan
)
    if CoreAutomation.FreeGiftEngine.Busy then
        return 0
    end

    CoreAutomation.FreeGiftEngine.Busy = true
    CoreAutomation.FreeGiftEngine.LastError = nil

    local indexes =
        CoreAutomation.detectTimedFreeGiftIndexes()

    -- Claim only gifts proven ready by FreeGiftsTime and the directory.
    -- Blindly invoking every slot creates rejections and can rate-limit later
    -- ready gifts.
    if #indexes == 0 then
        CoreAutomation.FreeGiftEngine.LastAction =
            "No timed gifts ready"
        CoreAutomation.FreeGiftEngine.NextScanAt =
            os.clock() + 5
        CoreAutomation.FreeGiftEngine.Busy = false

        if CoreAutomation.refreshFreeGiftUI then
            CoreAutomation.refreshFreeGiftUI()
        end

        return 0
    end

    local claimed = 0
    local attempts = 0
    local results = {}

    for _, index in ipairs(indexes) do
        if not Runtime.Alive
            or not CoreAutomation.FreeGiftEngine.Alive
        then
            break
        end

        attempts = attempts + 1

        local ok,
            success,
            message = pcall(
                Network.Invoke,
                "Redeem Free Gift",
                index
            )

        CoreAutomation.FreeGiftEngine
            .Stats.Attempts =
            CoreAutomation.FreeGiftEngine
                .Stats.Attempts + 1

        if ok and success == true then
            claimed = claimed + 1

            CoreAutomation.FreeGiftEngine
                .Stats.Claims =
                CoreAutomation.FreeGiftEngine
                    .Stats.Claims + 1

            results[index] = "claimed"
        elseif ok then
            CoreAutomation.FreeGiftEngine
                .Stats.Rejections =
                CoreAutomation.FreeGiftEngine
                    .Stats.Rejections + 1

            results[index] =
                tostring(
                    message
                    or success
                    or "not ready"
                )
        else
            CoreAutomation.FreeGiftEngine
                .Stats.Errors =
                CoreAutomation.FreeGiftEngine
                    .Stats.Errors + 1

            CoreAutomation.FreeGiftEngine
                .LastError =
                tostring(success)

            results[index] =
                "error: "
                .. tostring(success)
        end

        task.wait(0.12)
    end

    CoreAutomation.FreeGiftEngine
        .Stats.Passes =
        CoreAutomation.FreeGiftEngine
            .Stats.Passes + 1

    CoreAutomation.FreeGiftEngine.LastResults =
        results

    CoreAutomation.FreeGiftEngine.LastAction =
        string.format(
            "Checked %d timed gifts • claimed %d",
            attempts,
            claimed
        )

    CoreAutomation.FreeGiftEngine.NextScanAt =
        os.clock()
        + CoreAutomation.FreeGiftEngine.ScanCooldown

    CoreAutomation.FreeGiftEngine.Busy = false

    if CoreAutomation.refreshFreeGiftUI then
        CoreAutomation.refreshFreeGiftUI()
    end

    return claimed
end

task.spawn(function()
    while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation
        and CoreAutomation.FreeGiftEngine.Alive
    do
        task.wait(1)

        if CoreAutomation.FreeGiftEngine.AutoClaim
            and not CoreAutomation.FreeGiftEngine.Busy
            and os.clock()
                >= CoreAutomation.FreeGiftEngine.NextScanAt
        then
            CoreAutomation.claimTimedFreeGifts(false)
        elseif CoreAutomation.refreshFreeGiftUI then
            CoreAutomation.refreshFreeGiftUI()
        end
    end
end)

--////////////////////////////////////////////////////////////////////
-- Replaceable Event module interface
--////////////////////////////////////////////////////////////////////

local GardenEventModule = {
    Name = "Garden Event",
    Version = EVENT_MODULE_VERSION,
    Supported = false,
    LastDetection = nil,
}

function GardenEventModule:Detect()
    local eggOK = refreshEggs("event detection")
    local foundGardenEgg = false

    for _, entry in ipairs(EggEngine.Eggs) do
        if string.find(lower(entry.ID), "garden", 1, true)
            or string.find(lower(entry.Name), "garden", 1, true)
        then
            foundGardenEgg = true
            break
        end
    end

    local foundGardenPlot = getGardenPlot() ~= nil

    self.Supported = foundGardenPlot or (eggOK and foundGardenEgg)
    self.LastDetection = os.clock()

    return self.Supported
end

function GardenEventModule:StartFeature(name)
    if name == "CustomEggs" then
        startEggEngine()
        return true
    elseif name == "Campaign" then
        return setGardenFeature("FullCampaign", true)
    end

    return false, "Unknown Garden feature: " .. tostring(name)
end

function GardenEventModule:StopFeature(name)
    if name == "CustomEggs" then
        stopEggEngine("Stopped manually.", "info")
        return true
    elseif name == "Campaign" then
        return setGardenFeature("FullCampaign", false)
    elseif name == "Automation" then
        GardenAutomation.Suspended = true
        return true
    end

    return false, "Unknown Garden feature: " .. tostring(name)
end

function GardenEventModule:GetProgress()
    local status = getGardenStatus()

    return {
        eggs = {
            requests = EggEngine.Requests,
            successfulRequests = EggEngine.SuccessfulRequests,
            requestedEggs = EggEngine.RequestedEggs,
            confirmedEggs = EggEngine.ConfirmedEggs,
            rateLimits = EggEngine.RateLimits,
            errors = EggEngine.Errors,
            running = EggEngine.Running,
        },
        garden = {
            status = status,
            fullCampaign = GardenAutomation.FullCampaign,
            suspended = GardenAutomation.Suspended,
            stats = GardenAutomation.Stats,
            lastAction = GardenAutomation.LastAction,
            lastError = GardenAutomation.LastError,
            layoutCount = #GardenAutomation.UnitLayout,
            missionDirector = GardenAutomation.MissionDirector,
            autoSuperRebirth = GardenAutomation.AutoSuperRebirth,
            mission = GardenAutomation.MissionState,
            autoCraftSelected = GardenAutomation.AutoCraftSelected,
            craftSelection = deepCopy(GardenAutomation.CraftSelection),
            craftStatus = GardenAutomation.CraftLastStatus,
            autoMaxLuck = GardenAutomation.AutoMaxLuck,
            luckSelection = deepCopy(GardenAutomation.LuckSelection),
            luckStatus = GardenAutomation.LuckLastStatus,
        },
    }
end

function GardenEventModule:Unload()
    stopEggEngine("Garden stopped.", "info")

    GardenAutomation.Alive = false
    GardenAutomation.Suspended = true
    GardenAutomation.AutoCraftSelected = false
    GardenAutomation.AutoMaxLuck = false
    GardenAutomation.WorkerToken = GardenAutomation.WorkerToken + 1

    disconnectAll(EggEngine.Connections)
end

local CurrentEventModule = GardenEventModule

local function safeEventCall(methodName, ...)
    if Runtime.EventFault then
        return false, Runtime.EventFault
    end

    local method = CurrentEventModule and CurrentEventModule[methodName]
    if type(method) ~= "function" then
        return false, "Missing event method: " .. tostring(methodName)
    end

    local packed = table.pack(...)
    local ok, resultA, resultB = xpcall(function()
        return method(CurrentEventModule, table.unpack(packed, 1, packed.n))
    end, debug.traceback)

    if not ok then
        Runtime.EventFault = tostring(resultA)
        appendLog("EVENT_FAULT", Runtime.EventFault)
        setNotice("Garden tools hit an error. Reload SliceHub.", "error")
        return false, Runtime.EventFault
    end

    return true, resultA, resultB
end

--////////////////////////////////////////////////////////////////////
-- UI primitives
--////////////////////////////////////////////////////////////////////

local Theme = {
    Palettes = {
    ["Mist Purple"] = {
        Background = Color3.fromRGB(20, 16, 31),
        Sidebar = Color3.fromRGB(28, 21, 43),
        Panel = Color3.fromRGB(37, 28, 57),
        Panel2 = Color3.fromRGB(48, 37, 72),
        Input = Color3.fromRGB(58, 45, 85),
        Border = Color3.fromRGB(111, 86, 151),
        Text = Color3.fromRGB(249, 244, 255),
        Muted = Color3.fromRGB(190, 174, 211),
        Accent = Color3.fromRGB(190, 130, 255),
        AccentDark = Color3.fromRGB(132, 78, 205),
        Success = Color3.fromRGB(83, 177, 132),
        Error = Color3.fromRGB(191, 77, 111),
        Premium = Color3.fromRGB(205, 151, 58),
        CandyA = Color3.fromRGB(227, 164, 255),
        CandyB = Color3.fromRGB(122, 213, 255),
        Glow = Color3.fromRGB(210, 171, 255),
    },
    ["Cotton Candy"] = {
        Background = Color3.fromRGB(29, 20, 35),
        Sidebar = Color3.fromRGB(43, 27, 50),
        Panel = Color3.fromRGB(57, 36, 64),
        Panel2 = Color3.fromRGB(73, 46, 82),
        Input = Color3.fromRGB(87, 55, 96),
        Border = Color3.fromRGB(154, 103, 166),
        Text = Color3.fromRGB(255, 246, 251),
        Muted = Color3.fromRGB(218, 179, 203),
        Accent = Color3.fromRGB(255, 128, 190),
        AccentDark = Color3.fromRGB(197, 76, 143),
        Success = Color3.fromRGB(74, 170, 127),
        Error = Color3.fromRGB(204, 72, 105),
        Premium = Color3.fromRGB(209, 151, 57),
        CandyA = Color3.fromRGB(255, 138, 199),
        CandyB = Color3.fromRGB(136, 215, 255),
        Glow = Color3.fromRGB(255, 183, 222),
    },
    ["Blueberry Pop"] = {
        Background = Color3.fromRGB(14, 20, 34),
        Sidebar = Color3.fromRGB(19, 28, 48),
        Panel = Color3.fromRGB(25, 37, 63),
        Panel2 = Color3.fromRGB(31, 48, 79),
        Input = Color3.fromRGB(39, 59, 94),
        Border = Color3.fromRGB(80, 113, 166),
        Text = Color3.fromRGB(241, 248, 255),
        Muted = Color3.fromRGB(161, 187, 218),
        Accent = Color3.fromRGB(88, 158, 255),
        AccentDark = Color3.fromRGB(53, 102, 190),
        Success = Color3.fromRGB(55, 154, 112),
        Error = Color3.fromRGB(184, 68, 93),
        Premium = Color3.fromRGB(198, 144, 49),
        CandyA = Color3.fromRGB(91, 166, 255),
        CandyB = Color3.fromRGB(129, 105, 255),
        Glow = Color3.fromRGB(121, 174, 255),
    },
    ["Mint Frost"] = {
        Background = Color3.fromRGB(14, 27, 28),
        Sidebar = Color3.fromRGB(18, 39, 40),
        Panel = Color3.fromRGB(24, 51, 52),
        Panel2 = Color3.fromRGB(31, 65, 66),
        Input = Color3.fromRGB(38, 78, 78),
        Border = Color3.fromRGB(78, 138, 133),
        Text = Color3.fromRGB(241, 255, 252),
        Muted = Color3.fromRGB(166, 211, 202),
        Accent = Color3.fromRGB(91, 230, 197),
        AccentDark = Color3.fromRGB(47, 169, 143),
        Success = Color3.fromRGB(58, 173, 119),
        Error = Color3.fromRGB(181, 69, 89),
        Premium = Color3.fromRGB(199, 147, 48),
        CandyA = Color3.fromRGB(107, 244, 210),
        CandyB = Color3.fromRGB(126, 209, 255),
        Glow = Color3.fromRGB(155, 255, 230),
    },
    ["Strawberry Milk"] = {
        Background = Color3.fromRGB(34, 18, 23),
        Sidebar = Color3.fromRGB(49, 24, 31),
        Panel = Color3.fromRGB(64, 31, 40),
        Panel2 = Color3.fromRGB(82, 40, 51),
        Input = Color3.fromRGB(96, 49, 60),
        Border = Color3.fromRGB(164, 91, 107),
        Text = Color3.fromRGB(255, 246, 247),
        Muted = Color3.fromRGB(222, 177, 184),
        Accent = Color3.fromRGB(255, 116, 143),
        AccentDark = Color3.fromRGB(200, 66, 98),
        Success = Color3.fromRGB(70, 164, 111),
        Error = Color3.fromRGB(197, 62, 86),
        Premium = Color3.fromRGB(210, 146, 50),
        CandyA = Color3.fromRGB(255, 127, 157),
        CandyB = Color3.fromRGB(255, 190, 212),
        Glow = Color3.fromRGB(255, 163, 186),
    },
},
    Order = {
    "Mist Purple",
    "Cotton Candy",
    "Blueberry Pop",
    "Mint Frost",
    "Strawberry Milk",
},
    Gradients = {},
    RefreshUI = nil,
}

Theme.CurrentName = Theme.Palettes[Config.settings.theme]
    and Config.settings.theme
    or "Mist Purple"

Config.settings.theme = Theme.CurrentName

local COLORS = deepCopy(Theme.Palettes[Theme.CurrentName])

function Theme.ColorsEqual(left, right)
    return typeof(left) == "Color3"
        and typeof(right) == "Color3"
        and left.R == right.R
        and left.G == right.G
        and left.B == right.B
end

function Theme.MakeGradient(parent, firstRole, secondRole, rotation)
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = rotation or 0
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, COLORS[firstRole]),
        ColorSequenceKeypoint.new(1, COLORS[secondRole]),
    })
    gradient.Parent = parent

    table.insert(Theme.Gradients, {
        Gradient = gradient,
        First = firstRole,
        Second = secondRole,
    })

    return gradient
end

function Theme.RemapColorProperty(instance, property, previousPalette, newPalette)
    local ok, value = pcall(function()
        return instance[property]
    end)

    if not ok or typeof(value) ~= "Color3" then
        return
    end

    for role, previousColor in pairs(previousPalette) do
        if Theme.ColorsEqual(value, previousColor) and newPalette[role] then
            pcall(function()
                instance[property] = newPalette[role]
            end)
            return
        end
    end
end

function Theme.Apply(themeName, quiet)
    local palette = Theme.Palettes[themeName]
    if not palette then
        themeName = "Mist Purple"
        palette = Theme.Palettes[themeName]
    end

    local previousPalette = deepCopy(COLORS)

    for role, color in pairs(palette) do
        COLORS[role] = color
    end

    Theme.CurrentName = themeName
    Config.settings.theme = themeName
    markConfigDirty()

    if UI.Screen and UI.Screen.Parent then
        local objects = {UI.Screen}
        for _, descendant in ipairs(UI.Screen:GetDescendants()) do
            table.insert(objects, descendant)
        end

        for _, object in ipairs(objects) do
            if object:IsA("GuiObject") then
                Theme.RemapColorProperty(
                    object,
                    "BackgroundColor3",
                    previousPalette,
                    COLORS
                )
                Theme.RemapColorProperty(
                    object,
                    "BorderColor3",
                    previousPalette,
                    COLORS
                )
            end

            if object:IsA("TextLabel")
                or object:IsA("TextButton")
                or object:IsA("TextBox")
            then
                Theme.RemapColorProperty(
                    object,
                    "TextColor3",
                    previousPalette,
                    COLORS
                )

                if object:IsA("TextBox") then
                    Theme.RemapColorProperty(
                        object,
                        "PlaceholderColor3",
                        previousPalette,
                        COLORS
                    )
                end
            end

            if object:IsA("ImageLabel") or object:IsA("ImageButton") then
                Theme.RemapColorProperty(
                    object,
                    "ImageColor3",
                    previousPalette,
                    COLORS
                )
            end

            if object:IsA("ScrollingFrame") then
                Theme.RemapColorProperty(
                    object,
                    "ScrollBarImageColor3",
                    previousPalette,
                    COLORS
                )
            end

            if object:IsA("UIStroke") then
                Theme.RemapColorProperty(
                    object,
                    "Color",
                    previousPalette,
                    COLORS
                )
            end
        end

        for _, entry in ipairs(Theme.Gradients) do
            if entry.Gradient and entry.Gradient.Parent then
                entry.Gradient.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, COLORS[entry.First]),
                    ColorSequenceKeypoint.new(1, COLORS[entry.Second]),
                })
            end
        end

        for tabName, button in pairs(UI.TabButtons) do
            local active = tabName == Runtime.SelectedTab
            button.BackgroundColor3 =
                active and COLORS.AccentDark or COLORS.Sidebar
            button.TextColor3 =
                active and COLORS.Text or COLORS.Muted
        end

        if refreshEventUI then
            refreshEventUI()
        end
    end

    if type(Theme.RefreshUI) == "function" then
        Theme.RefreshUI()
    end

    if not quiet then
        setNotice("Theme switched to " .. themeName .. ".", "success")
    end
end

local function makeCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = parent
    return corner
end

local function makeStroke(parent, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.Border
    stroke.Transparency = transparency or 0.2
    stroke.Thickness = 1
    stroke.Parent = parent
    return stroke
end

local function tween(instance, duration, style, direction, properties)
    if not instance or not instance.Parent then
        return nil
    end

    local ok, animation = pcall(function()
        return TweenService:Create(
            instance,
            TweenInfo.new(
                duration or 0.18,
                style or Enum.EasingStyle.Quint,
                direction or Enum.EasingDirection.Out
            ),
            properties
        )
    end)

    if not ok or not animation then
        return nil
    end

    animation:Play()
    return animation
end

local function attachButtonMotion(button)
    local motionScale = Instance.new("UIScale")
    motionScale.Name = "MotionScale"
    motionScale.Scale = 1
    motionScale.Parent = button

    local hovering = false
    local pressed = false

    local function animateTo(value, duration, style)
        tween(
            motionScale,
            duration or 0.14,
            style or Enum.EasingStyle.Quint,
            Enum.EasingDirection.Out,
            {Scale = value}
        )
    end

    button.MouseEnter:Connect(function()
        hovering = true
        if not pressed then
            animateTo(1.025, 0.16)
        end
    end)

    button.MouseLeave:Connect(function()
        hovering = false
        pressed = false
        animateTo(1, 0.16)
    end)

    button.MouseButton1Down:Connect(function()
        pressed = true
        animateTo(0.965, 0.08, Enum.EasingStyle.Quad)
    end)

    button.MouseButton1Up:Connect(function()
        pressed = false
        animateTo(hovering and 1.025 or 1, 0.14)
    end)

    button.Activated:Connect(function()
        animateTo(0.965, 0.06, Enum.EasingStyle.Quad)
        task.delay(0.065, function()
            if motionScale.Parent then
                animateTo(hovering and 1.025 or 1, 0.16)
            end
        end)
    end)

    return motionScale
end

local function makeLabel(parent, text, position, size, options)
    options = options or {}

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = options.backgroundTransparency == nil and 1 or options.backgroundTransparency
    label.BackgroundColor3 = options.backgroundColor or COLORS.Panel
    label.BorderSizePixel = 0
    label.Position = position
    label.Size = size
    label.Text = text or ""
    label.TextColor3 = options.textColor or COLORS.Text
    label.TextXAlignment = options.xAlignment or Enum.TextXAlignment.Left
    label.TextYAlignment = options.yAlignment or Enum.TextYAlignment.Center
    label.TextWrapped = options.wrapped == true
    label.Font = options.font or Enum.Font.Gotham
    label.TextSize = options.textSize or 12
    label.Visible = options.visible ~= false
    label.Parent = parent

    if options.corner then
        makeCorner(label, options.corner)
    end
    if options.stroke then
        makeStroke(label, options.strokeTransparency)
    end

    return label
end

local function makeButton(parent, text, position, size, options)
    options = options or {}

    local button = Instance.new("TextButton")
    button.BackgroundColor3 = options.backgroundColor or COLORS.Input
    button.BorderSizePixel = 0
    button.Position = position
    button.Size = size
    button.AutoButtonColor = options.autoButtonColor ~= false
    button.Text = text or ""
    button.TextColor3 = options.textColor or COLORS.Text
    button.TextWrapped = options.wrapped == true
    button.Font = options.font or Enum.Font.GothamMedium
    button.TextSize = options.textSize or 12
    button.Visible = options.visible ~= false
    button.Parent = parent

    makeCorner(button, options.corner or 7)

    if options.stroke then
        makeStroke(button, options.strokeTransparency)
    end

    attachButtonMotion(button)
    return button
end

local function makeTextBox(parent, text, position, size, options)
    options = options or {}

    local box = Instance.new("TextBox")
    box.BackgroundColor3 = options.backgroundColor or COLORS.Input
    box.BorderSizePixel = 0
    box.Position = position
    box.Size = size
    box.ClearTextOnFocus = options.clearTextOnFocus == true
    box.PlaceholderText = options.placeholder or ""
    box.PlaceholderColor3 = COLORS.Muted
    box.Text = text or ""
    box.TextColor3 = COLORS.Text
    box.Font = options.font or Enum.Font.Code
    box.TextSize = options.textSize or 12
    box.TextXAlignment = options.xAlignment or Enum.TextXAlignment.Center
    box.Parent = parent

    makeCorner(box, options.corner or 7)
    return box
end

local function makeSwitch(parent, labelText, position, lockedPremium)
    local holder = Instance.new("Frame")
    holder.BackgroundTransparency = 1
    holder.Position = position
    holder.Size = UDim2.new(1, -24, 0, 36)
    holder.Parent = parent

    local visibleLabelText = lockedPremium and ("🔒 " .. tostring(labelText) .. "  •  PREMIUM") or labelText
    local label = makeLabel(
        holder,
        visibleLabelText,
        UDim2.fromOffset(0, 0),
        UDim2.new(1, -76, 1, 0),
        {
            textSize = 12,
            textColor = lockedPremium and COLORS.Muted or COLORS.Text,
        }
    )

    local button = makeButton(
        holder,
        "",
        UDim2.new(1, -62, 0, 4),
        UDim2.fromOffset(62, 28),
        {
            backgroundColor = COLORS.Input,
            corner = 14,
            autoButtonColor = false,
        }
    )
    button.ClipsDescendants = true
    if lockedPremium then
        button.BackgroundColor3 = COLORS.Panel2
    end

    local knob = Instance.new("Frame")
    knob.Name = "CandyKnob"
    knob.Position = UDim2.fromOffset(3, 3)
    knob.Size = UDim2.fromOffset(22, 22)
    knob.BackgroundColor3 = COLORS.Text
    knob.BorderSizePixel = 0
    knob.Parent = button
    makeCorner(knob, 11)

    local shine = Instance.new("Frame")
    shine.Name = "Shine"
    shine.Position = UDim2.fromOffset(5, 4)
    shine.Size = UDim2.fromOffset(7, 5)
    shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    shine.BackgroundTransparency = 0.38
    shine.BorderSizePixel = 0
    shine.Parent = knob
    makeCorner(shine, 5)

    return {
        Holder = holder,
        Label = label,
        Button = button,
        Knob = knob,
        LockedPremium = lockedPremium,
    }
end

local function applySwitchVisual(switch, enabled)
    if not switch or not switch.Button then
        return
    end

    tween(
        switch.Button,
        0.20,
        Enum.EasingStyle.Quint,
        Enum.EasingDirection.Out,
        {
            BackgroundColor3 = enabled and COLORS.Success or COLORS.Input,
        }
    )

    if switch.Knob and switch.Knob.Parent then
        tween(
            switch.Knob,
            0.22,
            Enum.EasingStyle.Back,
            Enum.EasingDirection.Out,
            {
                Position = enabled
                    and UDim2.new(1, -25, 0, 3)
                    or UDim2.fromOffset(3, 3),
            }
        )
    end
end

local function makePage(parent, name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.Position = UDim2.fromOffset(0, 0)
    page.Size = UDim2.fromScale(1, 1)
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = COLORS.Accent
    page.Visible = false
    page.Parent = parent

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 14)
    padding.PaddingRight = UDim.new(0, 14)
    padding.PaddingTop = UDim.new(0, 14)
    padding.PaddingBottom = UDim.new(0, 14)
    padding.Parent = page

    return page
end

local function makeSection(parent, titleText, height)
    local section = Instance.new("Frame")
    section.Name = tostring(titleText or "Section")
    section.BackgroundColor3 = COLORS.Panel
    section.BorderSizePixel = 0
    section.Size = UDim2.new(1, 0, 0, height)
    section.Parent = parent
    makeCorner(section, 12)
    makeStroke(section, 0.28)
    Theme.MakeGradient(section, "Panel", "Panel2", 10)

    local revealScale = Instance.new("UIScale")
    revealScale.Name = "RevealScale"
    revealScale.Scale = 1
    revealScale.Parent = section

    local accentBar = Instance.new("Frame")
    accentBar.Name = "CandyAccent"
    accentBar.Position = UDim2.fromOffset(0, 11)
    accentBar.Size = UDim2.fromOffset(4, 23)
    accentBar.BackgroundColor3 = COLORS.Accent
    accentBar.BorderSizePixel = 0
    accentBar.Parent = section
    makeCorner(accentBar, 4)
    Theme.MakeGradient(accentBar, "CandyA", "CandyB", 90)

    makeLabel(
        section,
        titleText,
        UDim2.fromOffset(14, 7),
        UDim2.new(1, -28, 0, 26),
        {
            font = Enum.Font.GothamBold,
            textSize = 13,
        }
    )

    return section
end

local function makeVerticalLayout(parent, padding)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, padding or 10)
    layout.Parent = parent
    return layout
end

--//////////////////////////////////////////////////////////////////
-- Smart automation expansion
--//////////////////////////////////////////////////////////////////

CoreAutomation.Major = {
    Alive = true,
    AutoLoginStreak = Config.expansion.autoLoginStreak == true,
    AutoAreaRewards = Config.expansion.autoAreaRewards == true,
    AutoForeverPack = Config.expansion.autoForeverPack == true,
    AutoDaycareClaim = Config.expansion.autoDaycareClaim == true,
    AutoDaycareEnroll = Config.expansion.autoDaycareEnroll == true,
    DaycareSearch = tostring(Config.expansion.daycarePetSearch or ""),
    DaycareSelection = type(Config.expansion.daycareSelection) == "table"
        and Config.expansion.daycareSelection or {},
    DaycareMatches = {},
    ForeverBlocked = false,
    AutoCombineKeys = Config.expansion.autoCombineKeys == true,
    AutoBalloonGifts = Config.expansion.autoBalloonGifts == true,
    Next = {},
    LastAction = "Ready",
    LastError = nil,
    Stats = {
        Login = 0,
        AreaRewards = 0,
        Forever = 0,
        Daycare = 0,
        DaycareEnroll = 0,
        Keys = 0,
        Balloons = 0,
    },
}

function CoreAutomation.majorSet(feature, enabled)
    local field = "Auto" .. tostring(feature)
    if CoreAutomation.Major[field] == nil then return end

    if feature == "ForeverPack" and enabled then
        local free = CoreAutomation.majorForeverIsFree and CoreAutomation.majorForeverIsFree()
        if free ~= true then
            CoreAutomation.Major.AutoForeverPack = false
            Config.expansion.autoForeverPack = false
            CoreAutomation.Major.ForeverBlocked = true
            markConfigDirty()
            setNotice("Free pack finished.", "info")
            if CoreAutomation.refreshMajorUI then CoreAutomation.refreshMajorUI() end
            return
        end
    end

    CoreAutomation.Major[field] = enabled == true
    Config.expansion["auto" .. tostring(feature):sub(1, 1):lower() .. tostring(feature):sub(2)] = enabled == true
    CoreAutomation.Major.Next[feature] = 0
    markConfigDirty()
    if CoreAutomation.refreshMajorUI then CoreAutomation.refreshMajorUI() end
end

function CoreAutomation.majorClaimLogin()
    if not CoreAutomation.LoginStreakCmds
        or type(CoreAutomation.LoginStreakCmds.CanClaim) ~= "function"
    then return false end
    local okReady, ready = pcall(CoreAutomation.LoginStreakCmds.CanClaim)
    if not okReady or not ready then return false end
    local ok, success = pcall(Network.Invoke, "Login Streaks: Claim")
    if ok and success == true then
        CoreAutomation.Major.Stats.Login = CoreAutomation.Major.Stats.Login + 1
        CoreAutomation.Major.LastAction = "Login reward claimed"
        return true
    end
    return false
end

function CoreAutomation.majorClaimAreaRewards()
    local save = getSaveTable()
    local directory = CoreAutomation.TimedRewardsDirectory
    if type(save) ~= "table" or type(directory) ~= "table" then return false end
    local timestamps = rawget(save, "TimedRewardTimestamps")
    if type(timestamps) ~= "table" then timestamps = {} end
    local now = Workspace:GetServerTimeNow()

    for rewardID, info in pairs(directory) do
        if type(info) == "table" then
            local last = tonumber(timestamps[rewardID])
            local cooldown = tonumber(rawget(info, "Cooldown")) or math.huge
            if not last or now - last > cooldown then
                local ok, success = pcall(Network.Invoke, "DailyRewards_Redeem", rewardID)
                if ok and success == true then
                    CoreAutomation.Major.Stats.AreaRewards =
                        CoreAutomation.Major.Stats.AreaRewards + 1
                    CoreAutomation.Major.LastAction = "Area reward claimed"
                    return true
                end
            end
        end
    end
    return false
end

function CoreAutomation.majorForeverNextSlot()
    if not CoreAutomation.ForeverPackCmds
        or type(CoreAutomation.ForeverPackCmds.GetState) ~= "function"
    then return nil, "Unavailable" end

    local okState, state = pcall(CoreAutomation.ForeverPackCmds.GetState, "Default")
    if not okState or type(state) ~= "table" then
        return nil, tostring(state or "No state")
    end
    local index = (tonumber(rawget(state, "Slot")) or 0) + 1
    local slots = rawget(state, "Slots")
    local slot = type(slots) == "table" and slots[index] or nil
    if not slot and type(CoreAutomation.ForeverPackCmds.GetSlot) == "function" then
        local ok, value = pcall(CoreAutomation.ForeverPackCmds.GetSlot, "Default", index)
        if ok then slot = value end
    end
    return slot, index
end

function CoreAutomation.majorForeverIsFree()
    local slot = CoreAutomation.majorForeverNextSlot()
    if type(slot) ~= "table" then return false end
    return rawget(slot, "Free") == true or rawget(slot, "Price") == nil
end

function CoreAutomation.majorClaimForever()
    if not CoreAutomation.majorForeverIsFree() then
        CoreAutomation.Major.AutoForeverPack = false
        CoreAutomation.Major.ForeverBlocked = true
        Config.expansion.autoForeverPack = false
        markConfigDirty()
        if CoreAutomation.refreshMajorUI then CoreAutomation.refreshMajorUI() end
        return false
    end

    -- Never call ForeverPackCmds.Claim here: that helper intentionally opens a
    -- Robux purchase prompt for paid slots. Only the confirmed free remote is
    -- allowed in SliceHub.
    local ok, success, message = pcall(
        Network.Invoke,
        "ForeverPacks: Claim Free",
        "Default"
    )
    if ok and success == true then
        CoreAutomation.Major.Stats.Forever = CoreAutomation.Major.Stats.Forever + 1
        CoreAutomation.Major.LastAction = "Free pack claimed"
        task.delay(0.2, function()
            if not CoreAutomation.majorForeverIsFree() then
                CoreAutomation.Major.AutoForeverPack = false
                CoreAutomation.Major.ForeverBlocked = true
                Config.expansion.autoForeverPack = false
                markConfigDirty()
                if CoreAutomation.refreshMajorUI then CoreAutomation.refreshMajorUI() end
            end
        end)
        return true
    end

    if tostring(message or success):lower():find("price", 1, true) then
        CoreAutomation.Major.AutoForeverPack = false
        CoreAutomation.Major.ForeverBlocked = true
        Config.expansion.autoForeverPack = false
        markConfigDirty()
    end
    return false
end

function CoreAutomation.majorClaimDaycare()
    if not CoreAutomation.DaycareCmds
        or type(CoreAutomation.DaycareCmds.GetActive) ~= "function"
        or type(CoreAutomation.DaycareCmds.ComputeRemainingTime) ~= "function"
        or type(CoreAutomation.DaycareCmds.Claim) ~= "function"
    then return false end

    local okActive, active = pcall(CoreAutomation.DaycareCmds.GetActive)
    if not okActive or type(active) ~= "table" then return false end
    for uid in pairs(active) do
        local okTime, remaining = pcall(CoreAutomation.DaycareCmds.ComputeRemainingTime, uid)
        if okTime and tonumber(remaining) and tonumber(remaining) <= 0 then
            local ok, success = pcall(CoreAutomation.DaycareCmds.Claim, uid)
            if ok and success == true then
                CoreAutomation.Major.Stats.Daycare = CoreAutomation.Major.Stats.Daycare + 1
                CoreAutomation.Major.LastAction = "Daycare claimed"
                return true
            end
        end
    end
    return false
end

function CoreAutomation.majorPetIconAsset(value)
    if type(value) == "number" then
        return "rbxassetid://" .. tostring(math.floor(value))
    end
    if type(value) ~= "string" or value == "" then
        return nil
    end
    if string.find(value, "rbxasset", 1, true)
        or string.find(value, "rbxthumb", 1, true)
        or string.find(value, "http", 1, true)
    then
        return value
    end
    if tonumber(value) then
        return "rbxassetid://" .. tostring(math.floor(tonumber(value)))
    end
    return nil
end

function CoreAutomation.majorNormalizePetName(value)
    return lower(value):gsub("[^%w]", "")
end

function CoreAutomation.majorPetEditDistance(left, right)
    left = CoreAutomation.majorNormalizePetName(left)
    right = CoreAutomation.majorNormalizePetName(right)
    if left == right then return 0 end
    if left == "" then return #right end
    if right == "" then return #left end

    local previous = {}
    local current = {}
    for column = 0, #right do previous[column] = column end

    for row = 1, #left do
        current[0] = row
        local leftByte = string.byte(left, row)
        for column = 1, #right do
            local cost = leftByte == string.byte(right, column) and 0 or 1
            current[column] = math.min(
                current[column - 1] + 1,
                previous[column] + 1,
                previous[column - 1] + cost
            )
        end
        previous, current = current, previous
    end
    return previous[#right]
end

function CoreAutomation.majorPetSearchScore(name, id, search)
    local query = CoreAutomation.majorNormalizePetName(search)
    if query == "" then return 1 end

    local display = CoreAutomation.majorNormalizePetName(name)
    local internal = CoreAutomation.majorNormalizePetName(id)
    local position = string.find(display, query, 1, true)
        or string.find(internal, query, 1, true)
    if position then return 1000 - position end

    local distance = math.min(
        CoreAutomation.majorPetEditDistance(display, query),
        CoreAutomation.majorPetEditDistance(internal, query)
    )
    local tolerance = math.max(2, math.floor(#query * 0.34))
    if distance <= tolerance then
        return 500 - distance
    end
    return nil
end

function CoreAutomation.majorDaycarePetInfo(item)
    if type(item) ~= "table" then return nil end

    local uid = itemMethod(
        item,
        "GetUID",
        rawget(item, "_uid") or rawget(item, "uid")
    )
    local id = itemMethod(
        item,
        "GetId",
        rawget(item, "_id") or rawget(item, "id")
    )
    if uid == nil or tostring(uid) == "" or id == nil then return nil end

    local directory = itemMethod(item, "Directory", nil)
    if type(directory) ~= "table" and type(CoreAutomation.PetsDirectory) == "table" then
        directory = CoreAutomation.PetsDirectory[tostring(id)]
            or CoreAutomation.PetsDirectory[id]
    end
    directory = type(directory) == "table" and directory or {}

    local name = itemMethod(item, "GetName", nil)
        or rawget(directory, "name")
        or rawget(directory, "Name")
        or id
    local variant = itemMethod(item, "GetVariant", rawget(item, "_variant"))
    local amount = math.max(1, math.floor(tonumber(
        itemMethod(item, "GetAmount", rawget(item, "_am") or rawget(item, "amount") or 1)
    ) or 1))

    -- Daycare selector intentionally excludes every oversized pet class.
    local classification = lower(tostring(
        rawget(directory, "petType")
        or rawget(directory, "PetType")
        or rawget(directory, "category")
        or rawget(directory, "Category")
        or ""
    ))
    local identity = lower(tostring(name) .. " " .. tostring(id) .. " " .. classification)
    local excluded = false

    for _, methodName in ipairs({"IsHuge", "IsTitanic", "IsGargantuan"}) do
        if type(item[methodName]) == "function" then
            local ok, value = pcall(item[methodName], item)
            if ok and value == true then excluded = true break end
        end
    end

    if not excluded then
        for _, key in ipairs({
            "huge", "Huge", "isHuge", "IsHuge",
            "titanic", "Titanic", "isTitanic", "IsTitanic",
            "gargantuan", "Gargantuan", "isGargantuan", "IsGargantuan"
        }) do
            if rawget(directory, key) == true then excluded = true break end
        end
    end

    if not excluded then
        excluded = string.find(identity, "huge", 1, true) ~= nil
            or string.find(identity, "titanic", 1, true) ~= nil
            or string.find(identity, "gargantuan", 1, true) ~= nil
    end

    if excluded then return nil end

    local icon = CoreAutomation.majorPetIconAsset(
        rawget(directory, "thumbnail")
        or rawget(directory, "Thumbnail")
        or rawget(directory, "icon")
        or rawget(directory, "Icon")
        or rawget(directory, "image")
        or rawget(directory, "Image")
    )

    local eligible = true
    if CoreAutomation.DaycareLoot
        and type(CoreAutomation.DaycareLoot.CanEnroll) == "function"
    then
        local okCan, can = pcall(CoreAutomation.DaycareLoot.CanEnroll, item)
        eligible = okCan and can == true
    end

    return {
        Item = item,
        UID = tostring(uid),
        ID = tostring(id),
        Name = tostring(name),
        Variant = tostring(variant or "Normal"),
        Icon = icon,
        Amount = amount,
        Eligible = eligible,
    }
end

function CoreAutomation.majorRefreshDaycareMatches(search)
    search = tostring(search or CoreAutomation.Major.DaycareSearch or "")
    CoreAutomation.Major.DaycareMatches = {}
    if not CoreAutomation.PetItem or type(CoreAutomation.PetItem.All) ~= "function" then
        return CoreAutomation.Major.DaycareMatches
    end

    local ok, all = pcall(CoreAutomation.PetItem.All, CoreAutomation.PetItem)
    if not ok then ok, all = pcall(CoreAutomation.PetItem.All) end
    if not ok or type(all) ~= "table" then
        return CoreAutomation.Major.DaycareMatches
    end

    local groups = {}
    for _, item in pairs(all) do
        local info = CoreAutomation.majorDaycarePetInfo(item)
        if info then
            local key = lower(info.Name) .. "|" .. lower(info.Variant)
            local group = groups[key]
            if not group then
                group = {
                    Name = info.Name,
                    ID = info.ID,
                    Variant = info.Variant,
                    Icon = info.Icon,
                    Amount = 0,
                    EligibleAmount = 0,
                    Stacks = {},
                }
                groups[key] = group
            end

            group.Amount = group.Amount + info.Amount
            table.insert(group.Stacks, {
                UID = info.UID,
                Amount = info.Amount,
                Eligible = info.Eligible,
            })
            if info.Eligible then
                group.EligibleAmount = group.EligibleAmount + info.Amount
            end
        end
    end

    for _, group in pairs(groups) do
        local score = CoreAutomation.majorPetSearchScore(
            group.Name,
            group.ID,
            search
        )
        if score then
            group.Score = score
            table.insert(CoreAutomation.Major.DaycareMatches, group)
        end
    end

    table.sort(CoreAutomation.Major.DaycareMatches, function(left, right)
        if left.Score ~= right.Score then return left.Score > right.Score end
        if left.EligibleAmount ~= right.EligibleAmount then
            return left.EligibleAmount > right.EligibleAmount
        end
        if left.Amount ~= right.Amount then return left.Amount > right.Amount end
        return lower(left.Name) < lower(right.Name)
    end)

    return CoreAutomation.Major.DaycareMatches
end

function CoreAutomation.majorDaycareSelectedCount()
    local count = 0
    for _, selected in pairs(CoreAutomation.Major.DaycareSelection) do
        if selected == true then
            count = count + 1
        elseif tonumber(selected) and tonumber(selected) > 0 then
            count = count + math.floor(tonumber(selected))
        end
    end
    return count
end

function CoreAutomation.majorDaycareAddGroup(group)
    if type(group) ~= "table" then return false end

    local free = math.huge
    if CoreAutomation.DaycareCmds
        and type(CoreAutomation.DaycareCmds.GetMaxSlots) == "function"
        and type(CoreAutomation.DaycareCmds.GetUsedSlots) == "function"
    then
        local okMax, maximum = pcall(CoreAutomation.DaycareCmds.GetMaxSlots)
        local okUsed, used = pcall(CoreAutomation.DaycareCmds.GetUsedSlots)
        if okMax and okUsed then
            free = math.max(0, (tonumber(maximum) or 0) - (tonumber(used) or 0))
        end
    end

    if CoreAutomation.majorDaycareSelectedCount() >= free then
        setNotice("Daycare selection is full.", "info")
        return false
    end

    for _, stack in ipairs(group.Stacks or {}) do
        if stack.Eligible == true then
            local selected = tonumber(CoreAutomation.Major.DaycareSelection[stack.UID]) or 0
            if selected < (tonumber(stack.Amount) or 1) then
                CoreAutomation.Major.DaycareSelection[stack.UID] = selected + 1
                Config.expansion.daycareSelection = CoreAutomation.Major.DaycareSelection
                markConfigDirty()
                setNotice("Added " .. group.Name .. ".", "success")
                if CoreAutomation.refreshMajorUI then CoreAutomation.refreshMajorUI() end
                return true
            end
        end
    end

    setNotice(
        group.EligibleAmount > 0
            and "All available copies are selected."
            or "No daycare-ready copies of this pet.",
        "info"
    )
    return false
end

function CoreAutomation.majorDaycareAddSearchPet()
    local matches = CoreAutomation.majorRefreshDaycareMatches(
        CoreAutomation.Major.DaycareSearch
    )
    if #matches == 0 then
        setNotice("No matching pet found.", "error")
        return false
    end
    return CoreAutomation.majorDaycareAddGroup(matches[1])
end

function CoreAutomation.majorDaycareClearSelection()
    table.clear(CoreAutomation.Major.DaycareSelection)
    Config.expansion.daycareSelection = CoreAutomation.Major.DaycareSelection
    markConfigDirty()
    if CoreAutomation.refreshMajorUI then CoreAutomation.refreshMajorUI() end
end

function CoreAutomation.majorEnrollDaycare()
    if not Network or type(Network.Invoke) ~= "function" then
        setNotice("Daycare is unavailable.", "error")
        return false
    end

    -- Runtime-confirmed PS99 payload:
    -- Daycare: Enroll({ [stackUID] = quantity })
    -- A stack must appear once with its requested amount; repeating the same
    -- UID in an array makes AbstractItem assert and rejects the enrollment.
    local payload = {}
    local total = 0
    local stackCount = 0

    for uid, selected in pairs(CoreAutomation.Major.DaycareSelection) do
        local count = selected == true
            and 1
            or math.max(0, math.floor(tonumber(selected) or 0))

        if count > 0 then
            payload[tostring(uid)] = count
            total = total + count
            stackCount = stackCount + 1
        end
    end

    if total <= 0 then
        setNotice("Select at least one pet.", "info")
        return false
    end

    local beforeUsed = nil
    if CoreAutomation.DaycareCmds
        and type(CoreAutomation.DaycareCmds.GetUsedSlots) == "function"
    then
        local okBefore, value = pcall(CoreAutomation.DaycareCmds.GetUsedSlots)
        if okBefore then beforeUsed = tonumber(value) end
    end

    local ok, success, message = pcall(
        Network.Invoke,
        "Daycare: Enroll",
        payload
    )

    appendLog("DAYCARE_ENROLL", string.format(
        "pets=%d stacks=%d ok=%s success=%s message=%s",
        total,
        stackCount,
        tostring(ok),
        tostring(success),
        tostring(message)
    ))

    if ok and success == true then
        CoreAutomation.Major.Stats.DaycareEnroll =
            CoreAutomation.Major.Stats.DaycareEnroll + 1
        CoreAutomation.Major.LastAction =
            "Enrolled " .. tostring(total) .. " pets"

        task.delay(0.35, function()
            if not Runtime.Alive then return end

            local confirmed = true
            if beforeUsed ~= nil
                and CoreAutomation.DaycareCmds
                and type(CoreAutomation.DaycareCmds.GetUsedSlots) == "function"
            then
                local okAfter, afterUsed =
                    pcall(CoreAutomation.DaycareCmds.GetUsedSlots)
                confirmed = okAfter
                    and (tonumber(afterUsed) or 0) > beforeUsed
            end

            if confirmed then
                setNotice(
                    "Enrolled " .. tostring(total) .. " pets.",
                    "success"
                )
            else
                setNotice(
                    "Daycare accepted the request; refreshing.",
                    "info"
                )
            end
        end)

        CoreAutomation.majorDaycareClearSelection()
        return true
    end

    local reason = tostring(message or success or "Enrollment rejected.")
    if string.find(string.lower(reason), "assertion", 1, true) then
        reason = "The selected pet stack changed. Refresh and select it again."
    end
    setNotice(reason, "error")
    return false
end

function CoreAutomation.majorCombineKey()
    CoreAutomation.Major.KeyCursor = ((CoreAutomation.Major.KeyCursor or 0) % 3) + 1
    local remote = ({"CrystalKey_Combine", "MVPKey_Combine", "FantasyKey_Unlock"})[
        CoreAutomation.Major.KeyCursor
    ]
    local ok, success = pcall(Network.Invoke, remote, 1)
    if ok and success == true then
        CoreAutomation.Major.Stats.Keys = CoreAutomation.Major.Stats.Keys + 1
        CoreAutomation.Major.LastAction = "Key combined"
        return true
    end
    return false
end


function CoreAutomation.majorPopBalloon()
    local things = Workspace:FindFirstChild("__THINGS")
    local folder = things and things:FindFirstChild("BalloonGifts")
    if not folder then return false end

    local root = CoreAutomation.permanentRootPart()
    local best = nil
    local bestDistance = math.huge
    for _, instance in ipairs(folder:GetDescendants()) do
        if instance:IsA("BasePart") then
            local balloonID = instance:GetAttribute("BalloonId")
                or instance:GetAttribute("BalloonID")
                or instance:GetAttribute("ID")
            if balloonID then
                local distance = root and (root.Position - instance.Position).Magnitude or 0
                if distance < bestDistance then
                    best = {Part = instance, ID = balloonID}
                    bestDistance = distance
                end
            end
        end
    end
    if not best then return false end

    local okEquip, equipped = pcall(Network.Invoke, "Slingshot_Equip")
    if not okEquip or equipped == false then return false end
    task.wait(0.12)
    local okShot, shot = pcall(
        Network.Invoke,
        "Slingshot_FireProjectile",
        best.Part.Position,
        1,
        0,
        200
    )
    if okShot and shot ~= false then
        pcall(Network.Fire, "BalloonGifts_BalloonHit", best.ID)
        CoreAutomation.Major.Stats.Balloons = CoreAutomation.Major.Stats.Balloons + 1
        CoreAutomation.Major.LastAction = "Balloon popped"
    end
    task.wait(0.08)
    pcall(Network.Invoke, "Slingshot_Unequip")
    return okShot and shot ~= false
end

function CoreAutomation.majorRunNow(feature)
    local handlers = {
        LoginStreak = CoreAutomation.majorClaimLogin,
        AreaRewards = CoreAutomation.majorClaimAreaRewards,
        ForeverPack = CoreAutomation.majorClaimForever,
        DaycareClaim = CoreAutomation.majorClaimDaycare,
        DaycareEnroll = CoreAutomation.majorEnrollDaycare,
        CombineKeys = CoreAutomation.majorCombineKey,
        BalloonGifts = CoreAutomation.majorPopBalloon,
    }
    local handler = handlers[feature]
    if handler then
        task.spawn(function()
            local ok, result = pcall(handler)
            if not ok then CoreAutomation.Major.LastError = tostring(result) end
            if CoreAutomation.refreshMajorUI then CoreAutomation.refreshMajorUI() end
        end)
    end
end

task.spawn(function()
    while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation and CoreAutomation.Major.Alive do
        task.wait(0.35)
        local now = os.clock()
        local schedule = {
            {"LoginStreak", 12, CoreAutomation.majorClaimLogin},
            {"AreaRewards", 8, CoreAutomation.majorClaimAreaRewards},
            {"ForeverPack", 15, CoreAutomation.majorClaimForever},
            {"DaycareClaim", 12, CoreAutomation.majorClaimDaycare},
            {"DaycareEnroll", 15, CoreAutomation.majorEnrollDaycare},
            {"CombineKeys", 1.25, CoreAutomation.majorCombineKey},
            {"BalloonGifts", 2.5, CoreAutomation.majorPopBalloon},
        }

        for _, item in ipairs(schedule) do
            local feature, interval, handler = item[1], item[2], item[3]
            if CoreAutomation.Major["Auto" .. feature]
                and now >= (CoreAutomation.Major.Next[feature] or 0)
            then
                CoreAutomation.Major.Next[feature] = now + interval
                local ok, result = pcall(handler)
                if not ok then CoreAutomation.Major.LastError = tostring(result) end
                break
            end
        end
    end
end)

--////////////////////////////////////////////////////////////////////
-- Pages
--////////////////////////////////////////////////////////////////////

local TAB_NAMES = {
    "Home",
    "Farm",
    "Eggs",
    "InfiniteEggs",
    "Automatic",
    "Rewards",
    "Utilities",
    "Event",
    "Settings",
}

UI.TabLabels = {
    Farm = "Auto Farm",
    InfiniteEggs = "Infinite Eggs",
    Automatic = "Boosts",
    Rewards = "Rewards",
    Utilities = "Utilities",
    Event = "Event",
}

local function showTab(name)
    if not UI.Pages[name] then
        name = "Home"
    end

    Runtime.SelectedTab = name

    if Config.settings.rememberLastTab then
        Config.selectedTab = name
        markConfigDirty()
    end

    local selectedPage = UI.Pages[name]

    for tabName, page in pairs(UI.Pages) do
        page.Visible = tabName == name
    end

    if selectedPage then
        selectedPage.Position = UDim2.fromOffset(26, 0)
        selectedPage.ScrollBarImageTransparency = 1

        tween(
            selectedPage,
            0.24,
            Enum.EasingStyle.Quint,
            Enum.EasingDirection.Out,
            {
                Position = UDim2.fromOffset(0, 0),
                ScrollBarImageTransparency = 0,
            }
        )

        local revealOrder = 0
        for _, child in ipairs(selectedPage:GetChildren()) do
            if child:IsA("Frame") then
                local revealScale = child:FindFirstChild("RevealScale")
                if revealScale then
                    revealScale.Scale = 0.965
                    revealOrder = revealOrder + 1
                    task.delay((revealOrder - 1) * 0.035, function()
                        if revealScale.Parent and selectedPage.Visible then
                            tween(
                                revealScale,
                                0.28,
                                Enum.EasingStyle.Back,
                                Enum.EasingDirection.Out,
                                {Scale = 1}
                            )
                        end
                    end)
                end
            end
        end
    end

    for tabName, button in pairs(UI.TabButtons) do
        local active = tabName == name

        tween(
            button,
            0.18,
            Enum.EasingStyle.Quint,
            Enum.EasingDirection.Out,
            {
                BackgroundColor3 = active and COLORS.AccentDark or COLORS.Sidebar,
                TextColor3 = active and COLORS.Text or COLORS.Muted,
            }
        )
    end
end

local function buildHomePage(page)
    makeVerticalLayout(page, 10)

    local welcome = makeSection(page, "SliceHub", 128)
    makeLabel(
        welcome,
        "Sweet automation. Zero clutter.",
        UDim2.fromOffset(14, 40),
        UDim2.new(1, -28, 0, 28),
        {font = Enum.Font.GothamBold, textSize = 15}
    )
    makeLabel(
        welcome,
        "Pick a tab and turn on what you need.",
        UDim2.fromOffset(14, 72),
        UDim2.new(1, -28, 0, 34),
        {wrapped = true, textColor = COLORS.Muted, textSize = 11}
    )

    local quick = makeSection(page, "Quick Start", 164)
    local farmButton = makeButton(
        quick,
        "Auto Farm",
        UDim2.fromOffset(14, 42),
        UDim2.new(0.5, -21, 0, 42),
        {backgroundColor = COLORS.AccentDark}
    )
    local rewardsButton = makeButton(
        quick,
        "Rewards",
        UDim2.new(0.5, 7, 0, 42),
        UDim2.new(0.5, -21, 0, 42),
        {backgroundColor = COLORS.Panel2}
    )
    local eggsButton = makeButton(
        quick,
        "Eggs",
        UDim2.fromOffset(14, 94),
        UDim2.new(0.5, -21, 0, 42),
        {backgroundColor = COLORS.Panel2}
    )
    local eventButton = makeButton(
        quick,
        "Event",
        UDim2.new(0.5, 7, 0, 94),
        UDim2.new(0.5, -21, 0, 42),
        {backgroundColor = COLORS.Panel2}
    )
    farmButton.Activated:Connect(function() showTab("Farm") end)
    rewardsButton.Activated:Connect(function() showTab("Rewards") end)
    eggsButton.Activated:Connect(function() showTab("Eggs") end)
    eventButton.Activated:Connect(function() showTab("Event") end)
end

function CoreAutomation.buildRewardsPage(page)
    makeVerticalLayout(page, 10)

    local rank = makeSection(page, "Rank Rewards", 128)
    local rankSwitch = makeSwitch(rank, "Auto Claim", UDim2.fromOffset(14, 42), false)
    local claimRank = makeButton(rank, "Claim Now", UDim2.fromOffset(14, 84), UDim2.new(1, -28, 0, 32), {backgroundColor = COLORS.AccentDark})
    UI.Rank = {Status = makeLabel(rank, "", UDim2.fromOffset(150, 42), UDim2.new(1, -164, 0, 32), {textColor = COLORS.Muted, xAlignment = Enum.TextXAlignment.Right, textSize = 10}), Switch = rankSwitch}
    rankSwitch.Button.Activated:Connect(function()
        CoreAutomation.RankEngine.AutoClaim = not CoreAutomation.RankEngine.AutoClaim
        Config.main.autoRankRewards = CoreAutomation.RankEngine.AutoClaim
        markConfigDirty()
        CoreAutomation.refreshRankUI()
    end)
    claimRank.Activated:Connect(CoreAutomation.claimDetectedRankRewards)
    CoreAutomation.refreshRankUI = function()
        if not UI.Rank.Status or not UI.Rank.Status.Parent then return end
        applySwitchVisual(UI.Rank.Switch, CoreAutomation.RankEngine.AutoClaim)
        UI.Rank.Status.Text = #CoreAutomation.RankEngine.LastDetected > 0 and "Ready" or "Up to date"
    end

    local gifts = makeSection(page, "Free Gifts", 128)
    local giftSwitch = makeSwitch(gifts, "Auto Claim", UDim2.fromOffset(14, 42), false)
    local claimGifts = makeButton(gifts, "Claim Now", UDim2.fromOffset(14, 84), UDim2.new(1, -28, 0, 32), {backgroundColor = COLORS.AccentDark})
    UI.FreeGifts = {Status = makeLabel(gifts, "", UDim2.fromOffset(150, 42), UDim2.new(1, -164, 0, 32), {textColor = COLORS.Muted, xAlignment = Enum.TextXAlignment.Right, textSize = 10}), Switch = giftSwitch, Button = claimGifts}
    giftSwitch.Button.Activated:Connect(function()
        CoreAutomation.FreeGiftEngine.AutoClaim = not CoreAutomation.FreeGiftEngine.AutoClaim
        Config.main.autoFreeGifts = CoreAutomation.FreeGiftEngine.AutoClaim
        CoreAutomation.FreeGiftEngine.NextScanAt = 0
        markConfigDirty()
        CoreAutomation.refreshFreeGiftUI()
    end)
    claimGifts.Activated:Connect(function() task.spawn(function() CoreAutomation.claimTimedFreeGifts(true) end) end)
    CoreAutomation.refreshFreeGiftUI = function()
        if not UI.FreeGifts.Status or not UI.FreeGifts.Status.Parent then return end
        applySwitchVisual(UI.FreeGifts.Switch, CoreAutomation.FreeGiftEngine.AutoClaim)
        UI.FreeGifts.Status.Text = #CoreAutomation.FreeGiftEngine.LastDetected > 0 and "Ready" or "Up to date"
    end

    local daily = makeSection(page, "Daily Rewards", 202)
    UI.Rewards = {}
    local rows = {
        {"LoginStreak", "Login Streak"},
        {"AreaRewards", "Area Rewards"},
        {"ForeverPack", "Free Forever Pack"},
        {"DaycareClaim", "Daycare Claim"},
    }
    for index, row in ipairs(rows) do
        local feature, label = row[1], row[2]
        local switch = makeSwitch(daily, label, UDim2.fromOffset(14, 34 + (index - 1) * 40), false)
        UI.Rewards[feature] = switch
        switch.Button.Activated:Connect(function()
            CoreAutomation.majorSet(feature, not CoreAutomation.Major["Auto" .. feature])
        end)
    end

    local daycare = makeSection(page, "Daycare Enroll", 386)
    UI.DaycareEnroll = {}
    UI.DaycareEnroll.Search = makeTextBox(
        daycare,
        "",
        UDim2.fromOffset(14, 42),
        UDim2.new(1, -108, 0, 34),
        {placeholder = "Search owned pets"}
    )
    UI.DaycareEnroll.Search.Text = CoreAutomation.Major.DaycareSearch
    local clearPets = makeButton(
        daycare,
        "Clear",
        UDim2.new(1, -88, 0, 42),
        UDim2.fromOffset(74, 34),
        {backgroundColor = COLORS.Panel2}
    )

    UI.DaycareEnroll.Suggestions = Instance.new("ScrollingFrame")
    UI.DaycareEnroll.Suggestions.Name = "PetSuggestions"
    UI.DaycareEnroll.Suggestions.BackgroundColor3 = COLORS.Input
    UI.DaycareEnroll.Suggestions.BorderSizePixel = 0
    UI.DaycareEnroll.Suggestions.Position = UDim2.fromOffset(14, 84)
    UI.DaycareEnroll.Suggestions.Size = UDim2.new(1, -28, 0, 150)
    UI.DaycareEnroll.Suggestions.ScrollBarThickness = 3
    UI.DaycareEnroll.Suggestions.AutomaticCanvasSize = Enum.AutomaticSize.Y
    UI.DaycareEnroll.Suggestions.CanvasSize = UDim2.new()
    UI.DaycareEnroll.Suggestions.Parent = daycare
    makeCorner(UI.DaycareEnroll.Suggestions, 8)

    UI.DaycareEnroll.Status = makeLabel(
        daycare,
        "No pets selected",
        UDim2.fromOffset(14, 242),
        UDim2.new(1, -28, 0, 34),
        {backgroundTransparency = 0, backgroundColor = COLORS.Panel2, corner = 7, xAlignment = Enum.TextXAlignment.Center, textColor = COLORS.Muted, textSize = 10}
    )
    UI.DaycareEnroll.Switch = makeSwitch(daycare, "Auto Enroll Selected", UDim2.fromOffset(14, 284), false)
    local enrollNow = makeButton(daycare, "Enroll Selected Now", UDim2.fromOffset(14, 328), UDim2.new(1, -28, 0, 36), {backgroundColor = COLORS.AccentDark})

    local function rebuildDaycareSuggestions()
        local holder = UI.DaycareEnroll.Suggestions
        if not holder or not holder.Parent then return end

        for _, child in ipairs(holder:GetChildren()) do
            if child.Name == "SuggestionRow" then child:Destroy() end
        end

        local matches = CoreAutomation.majorRefreshDaycareMatches(
            UI.DaycareEnroll.Search.Text
        )
        local shown = math.min(8, #matches)
        holder.CanvasSize = UDim2.fromOffset(0, shown * 40 + 6)

        if shown == 0 then
            local empty = makeLabel(
                holder,
                "No owned pets match.",
                UDim2.fromOffset(10, 8),
                UDim2.new(1, -20, 0, 30),
                {textColor = COLORS.Muted, textSize = 10, xAlignment = Enum.TextXAlignment.Center}
            )
            empty.Name = "SuggestionRow"
            return
        end

        for index = 1, shown do
            local group = matches[index]
            local row = makeButton(
                holder,
                "",
                UDim2.fromOffset(6, 6 + (index - 1) * 40),
                UDim2.new(1, -12, 0, 34),
                {backgroundColor = COLORS.Panel2, textSize = 10}
            )
            row.Name = "SuggestionRow"

            if group.Icon then
                local icon = Instance.new("ImageLabel")
                icon.BackgroundTransparency = 1
                icon.Position = UDim2.fromOffset(5, 3)
                icon.Size = UDim2.fromOffset(28, 28)
                icon.Image = group.Icon
                icon.Parent = row
            end

            local availableText = group.EligibleAmount > 0
                and (" • " .. tostring(group.EligibleAmount) .. " available")
                or " • unavailable"
            local label = makeLabel(
                row,
                group.Name .. "  x" .. tostring(group.Amount) .. availableText,
                UDim2.fromOffset(group.Icon and 38 or 10, 0),
                UDim2.new(1, group.Icon and -44 or -16, 1, 0),
                {textSize = 10, textColor = group.EligibleAmount > 0 and COLORS.Text or COLORS.Muted}
            )
            label.Active = false

            row.Activated:Connect(function()
                CoreAutomation.majorDaycareAddGroup(group)
                rebuildDaycareSuggestions()
            end)
        end
    end

    UI.DaycareEnroll.Search:GetPropertyChangedSignal("Text"):Connect(function()
        CoreAutomation.Major.DaycareSearch = UI.DaycareEnroll.Search.Text
        Config.expansion.daycarePetSearch = CoreAutomation.Major.DaycareSearch
        markConfigDirty()
        CoreAutomation.Major.DaycareSearchToken =
            (CoreAutomation.Major.DaycareSearchToken or 0) + 1
        local token = CoreAutomation.Major.DaycareSearchToken
        task.delay(0.12, function()
            if token == CoreAutomation.Major.DaycareSearchToken then
                rebuildDaycareSuggestions()
            end
        end)
    end)
    clearPets.Activated:Connect(function()
        CoreAutomation.majorDaycareClearSelection()
        rebuildDaycareSuggestions()
    end)
    UI.DaycareEnroll.Switch.Button.Activated:Connect(function()
        CoreAutomation.majorSet("DaycareEnroll", not CoreAutomation.Major.AutoDaycareEnroll)
    end)
    enrollNow.Activated:Connect(function() CoreAutomation.majorRunNow("DaycareEnroll") end)

    CoreAutomation.refreshMajorUI = function()
        for feature, switch in pairs(UI.Rewards or {}) do
            applySwitchVisual(switch, CoreAutomation.Major["Auto" .. feature] == true)
        end
        for feature, switch in pairs(UI.Utilities or {}) do
            applySwitchVisual(switch, CoreAutomation.Major["Auto" .. feature] == true)
        end
        if UI.DaycareEnroll and UI.DaycareEnroll.Switch then
            applySwitchVisual(UI.DaycareEnroll.Switch, CoreAutomation.Major.AutoDaycareEnroll == true)
            UI.DaycareEnroll.Status.Text = string.format(
                "%d pet%s selected",
                CoreAutomation.majorDaycareSelectedCount(),
                CoreAutomation.majorDaycareSelectedCount() == 1 and "" or "s"
            )
        end
    end

    rebuildDaycareSuggestions()

    CoreAutomation.refreshRankUI()
    CoreAutomation.refreshFreeGiftUI()
    CoreAutomation.refreshMajorUI()
end

function CoreAutomation.buildUtilitiesPage(page)
    makeVerticalLayout(page, 10)
    local tools = makeSection(page, "Smart Utilities", 244)
    UI.Utilities = {}
    local rows = {
        {"CombineKeys", "Combine Keys"},
        {"BalloonGifts", "Balloon Gifts"},
    }
    for index, row in ipairs(rows) do
        local feature, label = row[1], row[2]
        local switch = makeSwitch(tools, label, UDim2.fromOffset(14, 38 + (index - 1) * 48), false)
        UI.Utilities[feature] = switch
        switch.Button.Activated:Connect(function()
            CoreAutomation.majorSet(feature, not CoreAutomation.Major["Auto" .. feature])
        end)
    end

    local run = makeButton(
        tools,
        "Run Selected Now",
        UDim2.fromOffset(14, 188),
        UDim2.new(1, -28, 0, 36),
        {backgroundColor = COLORS.AccentDark}
    )
    run.Activated:Connect(function()
        for feature in pairs(UI.Utilities) do
            if CoreAutomation.Major["Auto" .. feature] then
                CoreAutomation.majorRunNow(feature)
            end
        end
    end)

    if CoreAutomation.refreshMajorUI then CoreAutomation.refreshMajorUI() end
end

local function buildPlaceholderPage(page, titleText, bodyText, nextStep)
    makeVerticalLayout(page, 10)

    local section = makeSection(page, titleText, 180)
    makeLabel(
        section,
        bodyText,
        UDim2.fromOffset(14, 42),
        UDim2.new(1, -28, 0, 70),
        {
            wrapped = true,
            textColor = COLORS.Muted,
            textSize = 12,
            yAlignment = Enum.TextYAlignment.Top,
        }
    )
    makeLabel(
        section,
        "Next: " .. nextStep,
        UDim2.fromOffset(14, 120),
        UDim2.new(1, -28, 0, 36),
        {
            wrapped = true,
            textColor = COLORS.Text,
            textSize = 11,
            yAlignment = Enum.TextYAlignment.Top,
        }
    )

    local safety = makeSection(page, "Alpha status", 90)
    makeLabel(
        safety,
        "This page is part of the permanent shell but does not run unfinished automation.",
        UDim2.fromOffset(14, 38),
        UDim2.new(1, -28, 0, 38),
        {
            wrapped = true,
            textColor = COLORS.Muted,
            textSize = 11,
        }
    )
end

function CoreAutomation.buildFarmPage(page)
    makeVerticalLayout(page, 10)

    local statusSection =
        makeSection(page, "Farm", 84)

    local status = makeLabel(
        statusSection,
        "",
        UDim2.fromOffset(14, 38),
        UDim2.new(1, -28, 0, 38),
        {
            wrapped = true,
            textColor = COLORS.Muted,
            textSize = 11,
            yAlignment = Enum.TextYAlignment.Top,
        }
    )

    local automation =
        makeSection(page, "Farm Toggles", 190)

    local autoFarmSwitch = makeSwitch(
        automation,
        "Auto Farm",
        UDim2.fromOffset(14, 36),
        false
    )

    local damageSwitch = makeSwitch(
        automation,
        "Auto Tap",
        UDim2.fromOffset(14, 72),
        false
    )

    local orbSwitch = makeSwitch(
        automation,
        "Collect Drops",
        UDim2.fromOffset(14, 108),
        false
    )

    local infSpeedSwitch = makeSwitch(
        automation,
        "Inf Speed Pets",
        UDim2.fromOffset(14, 144),
        false
    )

    local targeting =
        makeSection(page, "Range", 154)

    local autoTargets = makeSwitch(
        targeting,
        "Automatic Target Count",
        UDim2.fromOffset(14, 36),
        false
    )

    local targetLabel = makeLabel(
        targeting,
        "",
        UDim2.fromOffset(58, 78),
        UDim2.new(1, -116, 0, 30),
        {
            backgroundTransparency = 0,
            backgroundColor = COLORS.Input,
            xAlignment =
                Enum.TextXAlignment.Center,
            textSize = 11,
            corner = 7,
        }
    )

    local targetMinus = makeButton(
        targeting,
        "−",
        UDim2.fromOffset(14, 78),
        UDim2.fromOffset(36, 30),
        {
            backgroundColor = COLORS.Input,
        }
    )

    local targetPlus = makeButton(
        targeting,
        "+",
        UDim2.new(1, -50, 0, 78),
        UDim2.fromOffset(36, 30),
        {
            backgroundColor = COLORS.Input,
        }
    )

    local radiusLabel = makeLabel(
        targeting,
        "",
        UDim2.fromOffset(58, 116),
        UDim2.new(1, -116, 0, 30),
        {
            backgroundTransparency = 0,
            backgroundColor = COLORS.Input,
            xAlignment =
                Enum.TextXAlignment.Center,
            textSize = 11,
            corner = 7,
        }
    )

    local radiusMinus = makeButton(
        targeting,
        "−",
        UDim2.fromOffset(14, 116),
        UDim2.fromOffset(36, 30),
        {
            backgroundColor = COLORS.Input,
        }
    )

    local radiusPlus = makeButton(
        targeting,
        "+",
        UDim2.new(1, -50, 0, 116),
        UDim2.fromOffset(36, 30),
        {
            backgroundColor = COLORS.Input,
        }
    )

    targeting.Visible = false
    CoreAutomation.FarmEngine.AutoTargetCount = true
    CoreAutomation.FarmEngine.TargetRadius = 2000
    Config.farm.autoTargetCount = true
    Config.farm.targetRadius = 2000

    local travel =
        makeSection(page, "Travel", 174)

    local travelStatus = makeLabel(
        travel,
        "",
        UDim2.fromOffset(14, 38),
        UDim2.new(1, -28, 0, 42),
        {
            wrapped = true,
            textColor = COLORS.Muted,
            textSize = 10,
            yAlignment = Enum.TextYAlignment.Top,
        }
    )

    local bestAreaButton = makeButton(
        travel,
        "Teleport to Best Area",
        UDim2.fromOffset(14, 88),
        UDim2.new(0.5, -21, 0, 36),
        {
            backgroundColor = COLORS.AccentDark,
            textSize = 11,
        }
    )

    local bestWorldButton = makeButton(
        travel,
        "Teleport to Best World",
        UDim2.new(0.5, 7, 0, 88),
        UDim2.new(0.5, -21, 0, 36),
        {
            backgroundColor = COLORS.Panel2,
            textSize = 11,
        }
    )

    local bestAreaSwitch = makeSwitch(
        travel,
        "Auto Teleport to Best Area",
        UDim2.fromOffset(14, 128),
        false
    )

    UI.Teleports.BestStatus = travelStatus
    UI.Teleports.BestButton = bestAreaButton
    UI.Teleports.BestWorldButton = bestWorldButton
    UI.Teleports.BestSwitch = bestAreaSwitch

    bestAreaButton.Activated:Connect(function()
        task.spawn(function()
            CoreAutomation.teleportToBestArea(false)
        end)
    end)

    bestWorldButton.Activated:Connect(function()
        task.spawn(TeleportRuntime.teleportToBestWorld)
    end)

    bestAreaSwitch.Button.Activated:Connect(function()
        CoreAutomation.setAutoBestArea(
            not CoreAutomation.BestAreaEngine.Auto
        )
    end)

    CoreAutomation.refreshBestAreaUI = function()
        if not UI.Teleports.BestStatus
            or not UI.Teleports.BestStatus.Parent
        then
            return
        end

        applySwitchVisual(
            UI.Teleports.BestSwitch,
            CoreAutomation.BestAreaEngine.Auto
        )

        local detected = CoreAutomation.resolveBestAreaID()
        local worlds = getWorldEntries()
        local bestWorld = worlds[#worlds]

        UI.Teleports.BestStatus.Text = string.format(
            "Best area: %s  •  Best world: %s",
            detected and tostring(detected) or "—",
            bestWorld and bestWorld.Name or "—"
        )
    end

    CoreAutomation.refreshBestAreaUI()

    local safety =
        makeSection(page, "Pet Controls", 90)

    local restore = makeButton(
        safety,
        "Restore Pets Now",
        UDim2.fromOffset(14, 38),
        UDim2.new(0.5, -21, 0, 36),
        {
            backgroundColor = COLORS.Panel2,
            textSize = 11,
        }
    )

    local disableAll = makeButton(
        safety,
        "Stop All",
        UDim2.new(0.5, 7, 0, 38),
        UDim2.new(0.5, -21, 0, 36),
        {
            backgroundColor = COLORS.Error,
            textSize = 11,
        }
    )

    UI.Farm = {
        Status = status,
        AutoFarm = autoFarmSwitch,
        AutoTargets = autoTargets,
        TargetLabel = targetLabel,
        RadiusLabel = radiusLabel,
        Damage = damageSwitch,
        Orbs = orbSwitch,
        InfSpeed = infSpeedSwitch,
        TravelStatus = travelStatus,
        BestAreaButton = bestAreaButton,
        BestWorldButton = bestWorldButton,
        BestAreaSwitch = bestAreaSwitch,
        Restore = restore,
        DisableAll = disableAll,
    }

    autoFarmSwitch.Button.Activated:Connect(function()
        CoreAutomation.setFarmFeature(
            "AutoFarm",
            not CoreAutomation.FarmEngine.AutoFarm
        )
    end)

    damageSwitch.Button.Activated:Connect(function()
        CoreAutomation.setFarmFeature(
            "AutoTap",
            not CoreAutomation.FarmEngine.PlayerDamage
        )
    end)

    orbSwitch.Button.Activated:Connect(function()
        CoreAutomation.setFarmFeature(
            "CollectDrops",
            not CoreAutomation.FarmEngine.CollectOrbs
        )
    end)

    infSpeedSwitch.Button.Activated:Connect(function()
        CoreAutomation.setFarmFeature(
            "InfSpeedPets",
            not CoreAutomation.FarmEngine.InfSpeedPets
        )
    end)

    autoTargets.Button.Activated:Connect(function()
        CoreAutomation.FarmEngine.AutoTargetCount =
            not CoreAutomation.FarmEngine.AutoTargetCount
        Config.farm.autoTargetCount =
            CoreAutomation.FarmEngine.AutoTargetCount
        CoreAutomation.FarmEngine.LastAssignmentSignature = nil
        markConfigDirty()
        CoreAutomation.refreshFarmUI()
    end)

    targetMinus.Activated:Connect(function()
        CoreAutomation.FarmEngine.ManualTargetCount =
            math.floor(
                clamp(
                    CoreAutomation.FarmEngine.ManualTargetCount - 1,
                    1,
                    15
                )
            )

        Config.farm.targetCount =
            CoreAutomation.FarmEngine.ManualTargetCount
        CoreAutomation.FarmEngine.LastAssignmentSignature = nil
        markConfigDirty()
        CoreAutomation.refreshFarmUI()
    end)

    targetPlus.Activated:Connect(function()
        CoreAutomation.FarmEngine.ManualTargetCount =
            math.floor(
                clamp(
                    CoreAutomation.FarmEngine.ManualTargetCount + 1,
                    1,
                    15
                )
            )

        Config.farm.targetCount =
            CoreAutomation.FarmEngine.ManualTargetCount
        CoreAutomation.FarmEngine.LastAssignmentSignature = nil
        markConfigDirty()
        CoreAutomation.refreshFarmUI()
    end)

    radiusMinus.Activated:Connect(function()
        CoreAutomation.FarmEngine.TargetRadius =
            clamp(
                CoreAutomation.FarmEngine.TargetRadius - 20,
                100,
                600
            )

        Config.farm.targetRadius =
            CoreAutomation.FarmEngine.TargetRadius
        CoreAutomation.FarmEngine.LastAssignmentSignature = nil
        markConfigDirty()
        CoreAutomation.refreshFarmUI()
    end)

    radiusPlus.Activated:Connect(function()
        CoreAutomation.FarmEngine.TargetRadius =
            clamp(
                CoreAutomation.FarmEngine.TargetRadius + 20,
                100,
                600
            )

        Config.farm.targetRadius =
            CoreAutomation.FarmEngine.TargetRadius
        CoreAutomation.FarmEngine.LastAssignmentSignature = nil
        markConfigDirty()
        CoreAutomation.refreshFarmUI()
    end)

    restore.Activated:Connect(function()
        local restored =
            CoreAutomation.farmRestorePets()

        CoreAutomation.FarmEngine.LastAssignmentSignature = nil
        CoreAutomation.FarmEngine.LastAction =
            "Restored "
            .. tostring(restored)
            .. " pets"

        setNotice(
            "Restored "
                .. tostring(restored)
                .. " rendered pets.",
            "success"
        )

        CoreAutomation.refreshFarmUI()
    end)

    disableAll.Activated:Connect(function()
        CoreAutomation.stopFarmEngine(
            "Disabled by user",
            true
        )
    end)

    CoreAutomation.refreshFarmUI = function()
        if not UI.Farm.Status or not UI.Farm.Status.Parent then return end
        applySwitchVisual(UI.Farm.AutoFarm, CoreAutomation.FarmEngine.AutoFarm)
        applySwitchVisual(UI.Farm.Damage, CoreAutomation.FarmEngine.PlayerDamage)
        applySwitchVisual(UI.Farm.Orbs, CoreAutomation.FarmEngine.CollectOrbs)
        applySwitchVisual(UI.Farm.InfSpeed, CoreAutomation.FarmEngine.InfSpeedPets)
        applySwitchVisual(UI.Farm.AutoTargets, CoreAutomation.FarmEngine.AutoTargetCount)
        UI.Farm.Status.Text = CoreAutomation.FarmEngine.Running and "Running" or "Ready"
        UI.Farm.TargetLabel.Text = "Targets: Auto"
        UI.Farm.RadiusLabel.Text = "Range: Max"
        if CoreAutomation.refreshBestAreaUI then CoreAutomation.refreshBestAreaUI() end
    end

    CoreAutomation.refreshFarmUI()
end


--//////////////////////////////////////////////////////////////////
-- Gold / Rainbow machines + Infinite Eggs
--//////////////////////////////////////////////////////////////////

CoreAutomation.Machines = {
    Alive = true,
    Gold = {
        Search = tostring(Config.eggs.goldSearch or ""),
        SelectedID = tostring(Config.eggs.goldSelectedPetID or ""),
        Auto = false,
        Busy = false,
        Matches = {},
        LastAction = "Ready",
        LastError = nil,
        NextAt = 0,
        Stats = 0,
    },
    Rainbow = {
        Search = tostring(Config.eggs.rainbowSearch or ""),
        SelectedID = tostring(Config.eggs.rainbowSelectedPetID or ""),
        Auto = false,
        Busy = false,
        Matches = {},
        LastAction = "Ready",
        LastError = nil,
        NextAt = 0,
        Stats = 0,
    },
}

CoreAutomation.InfiniteEggEngine = {
    Alive = true,
    AutoOpen = false,
    AutoDisableIndexed = false,
    AmountMode = tostring(Config.infiniteEggs.amountMode or "Max"),
    SelectedWorld = math.max(1, math.floor(tonumber(Config.infiniteEggs.selectedWorld) or 1)),
    Busy = false,
    IndexBusy = false,
    IndexCounts = {},
    IndexVersion = 0,
    LastIndexRefreshAt = 0,
    NextIndexRefreshAt = 0,
    LastAction = "Ready",
    LastError = nil,
    NextHatchAt = 0,
    NextIndexAt = 0,
    Stats = {Hatches = 0, EggsDisabled = 0, WorldsDisabled = 0},
}

function CoreAutomation.machineState(kind)
    return CoreAutomation.Machines[tostring(kind)]
end

function CoreAutomation.machineRequired(kind)
    local perkName = tostring(kind) == "Rainbow" and "RainbowReduction" or "GoldReduction"
    local reduction = 0
    if CoreAutomation.MasteryCmds
        and type(CoreAutomation.MasteryCmds.HasPerk) == "function"
        and type(CoreAutomation.MasteryCmds.GetPerkPower) == "function"
    then
        local okHas, has = pcall(CoreAutomation.MasteryCmds.HasPerk, "Pets", perkName)
        if okHas and has == true then
            local okPower, power = pcall(CoreAutomation.MasteryCmds.GetPerkPower, "Pets", perkName)
            if okPower then reduction = math.max(0, math.floor(tonumber(power) or 0)) end
        end
    end
    return math.max(1, 10 - reduction)
end

function CoreAutomation.machinePetInfo(item, kind)
    local info = CoreAutomation.majorDaycarePetInfo(item)
    if not info then return nil end

    local wantedMethod = tostring(kind) == "Rainbow" and "IsGolden" or "IsNormal"
    local canMethod = tostring(kind) == "Rainbow" and "CanRainbowMachine" or "CanGoldMachine"
    local variantOK = itemMethod(item, wantedMethod, false) == true
    local canUse = itemMethod(item, canMethod, false) == true
    local exclusive = tonumber(itemMethod(item, "GetExclusiveLevel", 0)) or 0
    local locked = itemMethod(item, "IsLocked", false) == true

    if not variantOK or not canUse or exclusive ~= 0 or locked then
        return nil
    end

    info.Icon = CoreAutomation.majorPetIconAsset(itemMethod(item, "GetIcon", nil)) or info.Icon
    info.Required = CoreAutomation.machineRequired(kind)
    info.Crafts = math.floor(info.Amount / info.Required)
    return info
end

function CoreAutomation.refreshMachineMatches(kind, search)
    local state = CoreAutomation.machineState(kind)
    if not state then return {} end
    search = tostring(search or state.Search or "")
    state.Matches = {}

    if not CoreAutomation.PetItem or type(CoreAutomation.PetItem.All) ~= "function" then
        return state.Matches
    end

    local ok, all = pcall(CoreAutomation.PetItem.All, CoreAutomation.PetItem)
    if not ok then ok, all = pcall(CoreAutomation.PetItem.All) end
    if not ok or type(all) ~= "table" then return state.Matches end

    local groups = {}
    for _, item in pairs(all) do
        local info = CoreAutomation.machinePetInfo(item, kind)
        if info then
            local key = tostring(info.ID)
            local group = groups[key]
            if not group then
                group = {
                    ID = info.ID,
                    Name = info.Name,
                    Icon = info.Icon,
                    Amount = 0,
                    Crafts = 0,
                    Required = info.Required,
                    Stacks = {},
                }
                groups[key] = group
            end
            group.Amount = group.Amount + info.Amount
            group.Crafts = group.Crafts + info.Crafts
            table.insert(group.Stacks, {
                UID = info.UID,
                Amount = info.Amount,
                Crafts = info.Crafts,
                Item = item,
            })
        end
    end

    for _, group in pairs(groups) do
        local score = CoreAutomation.majorPetSearchScore(group.Name, group.ID, search)
        if score then
            group.Score = score
            table.sort(group.Stacks, function(left, right)
                if left.Crafts ~= right.Crafts then return left.Crafts > right.Crafts end
                return left.Amount > right.Amount
            end)
            table.insert(state.Matches, group)
        end
    end

    table.sort(state.Matches, function(left, right)
        if left.Score ~= right.Score then return left.Score > right.Score end
        if left.Crafts ~= right.Crafts then return left.Crafts > right.Crafts end
        if left.Amount ~= right.Amount then return left.Amount > right.Amount end
        return lower(left.Name) < lower(right.Name)
    end)

    return state.Matches
end

function CoreAutomation.selectMachinePet(kind, group)
    local state = CoreAutomation.machineState(kind)
    if not state or type(group) ~= "table" then return false end
    state.SelectedID = tostring(group.ID or "")
    if kind == "Rainbow" then
        Config.eggs.rainbowSelectedPetID = state.SelectedID
    else
        Config.eggs.goldSelectedPetID = state.SelectedID
    end
    markConfigDirty()
    state.LastError = nil
    state.LastAction = "Selected " .. tostring(group.Name or group.ID)
    if CoreAutomation.refreshMachineUI then CoreAutomation.refreshMachineUI(kind, true) end
    return true
end

function CoreAutomation.resolveMachineStack(kind)
    local state = CoreAutomation.machineState(kind)
    if not state or state.SelectedID == "" then return nil, nil, "Choose a pet first." end

    local matches = CoreAutomation.refreshMachineMatches(kind, "")
    for _, group in ipairs(matches) do
        if tostring(group.ID) == tostring(state.SelectedID) then
            for _, stack in ipairs(group.Stacks or {}) do
                if (tonumber(stack.Crafts) or 0) > 0 then
                    return stack, group
                end
            end
            return nil, group, "Not enough copies yet."
        end
    end
    return nil, nil, "Selected pet is no longer available."
end

function CoreAutomation.runPetMachine(kind, manual)
    local state = CoreAutomation.machineState(kind)
    if not state or state.Busy or not Runtime.Alive then return false end
    if not Network or type(Network.Invoke) ~= "function" then
        state.LastError = "Machine network is unavailable."
        return false
    end

    local stack, group, reason = CoreAutomation.resolveMachineStack(kind)
    if not stack then
        state.LastError = reason
        state.LastAction = reason or "Waiting"
        if manual then setNotice(state.LastAction, "info") end
        if CoreAutomation.refreshMachineUI then CoreAutomation.refreshMachineUI(kind, true) end
        return false
    end

    local outputs = math.max(0, math.floor(tonumber(stack.Crafts) or 0))
    if outputs <= 0 then
        state.LastAction = "Not enough copies yet."
        if manual then setNotice(state.LastAction, "info") end
        return false
    end

    state.Busy = true
    state.LastError = nil
    local remote = kind == "Rainbow" and "RainbowMachine_Activate" or "GoldMachine_Activate"
    local ok, success, _, shinyCount = pcall(Network.Invoke, remote, tostring(stack.UID), outputs)
    state.Busy = false

    appendLog("PET_MACHINE", string.format(
        "kind=%s pet=%s uid=%s outputs=%d ok=%s success=%s shiny=%s",
        tostring(kind), tostring(group and group.Name or state.SelectedID), tostring(stack.UID),
        outputs, tostring(ok), tostring(success), tostring(shinyCount)
    ))

    if ok and success == true then
        state.Stats = (tonumber(state.Stats) or 0) + outputs
        state.LastAction = string.format("Made %d %s pet%s", outputs, kind, outputs == 1 and "" or "s")
        if manual then setNotice(state.LastAction .. ".", "success") end
        task.delay(0.35, function()
            if Runtime.Alive and CoreAutomation.refreshMachineUI then
                CoreAutomation.refreshMachineUI(kind, true)
            end
        end)
        return true
    end

    state.LastError = tostring(success or "Machine rejected the request.")
    state.LastAction = state.LastError
    state.Auto = false
    if kind == "Rainbow" then Config.eggs.autoRainbow = false else Config.eggs.autoGold = false end
    markConfigDirty()
    if manual then setNotice(state.LastError, "error") end
    if CoreAutomation.refreshMachineUI then CoreAutomation.refreshMachineUI(kind, true) end
    return false
end

function CoreAutomation.setPetMachineAuto(kind, enabled)
    local state = CoreAutomation.machineState(kind)
    if not state then return false end
    if enabled and not requirePremium(tostring(kind) .. " Pet Machine Automation") then
        return false
    end
    state.Auto = enabled == true
    state.NextAt = 0
    state.LastError = nil
    state.LastAction = state.Auto and "Watching selected pet" or "Stopped"
    if kind == "Rainbow" then Config.eggs.autoRainbow = state.Auto else Config.eggs.autoGold = state.Auto end
    markConfigDirty()
    if CoreAutomation.refreshMachineUI then CoreAutomation.refreshMachineUI(kind, false) end
    return true
end

function CoreAutomation.rebuildMachineSuggestions(kind)
    local state = CoreAutomation.machineState(kind)
    local ui = UI.Machines and UI.Machines[kind]
    if not state or not ui or not ui.Suggestions or not ui.Suggestions.Parent then return end

    for _, child in ipairs(ui.Suggestions:GetChildren()) do
        if child.Name == "SuggestionRow" then child:Destroy() end
    end

    local matches = CoreAutomation.refreshMachineMatches(kind, ui.Search.Text)
    local shown = math.min(8, #matches)
    ui.Suggestions.CanvasSize = UDim2.fromOffset(0, shown * 40 + 6)

    if shown == 0 then
        local empty = makeLabel(
            ui.Suggestions,
            kind == "Rainbow" and "No eligible Golden pets." or "No eligible Normal pets.",
            UDim2.fromOffset(10, 8), UDim2.new(1, -20, 0, 30),
            {textColor = COLORS.Muted, textSize = 10, xAlignment = Enum.TextXAlignment.Center}
        )
        empty.Name = "SuggestionRow"
        return
    end

    for index = 1, shown do
        local group = matches[index]
        local row = makeButton(
            ui.Suggestions, "", UDim2.fromOffset(6, 6 + (index - 1) * 40),
            UDim2.new(1, -12, 0, 34),
            {backgroundColor = COLORS.Panel2, textSize = 10}
        )
        row.Name = "SuggestionRow"

        if group.Icon then
            local icon = Instance.new("ImageLabel")
            icon.BackgroundTransparency = 1
            icon.Position = UDim2.fromOffset(5, 3)
            icon.Size = UDim2.fromOffset(28, 28)
            icon.Image = group.Icon
            icon.Parent = row
        end

        local text = string.format(
            "%s  x%d  •  %d craft%s",
            tostring(group.Name), tonumber(group.Amount) or 0,
            tonumber(group.Crafts) or 0, tonumber(group.Crafts) == 1 and "" or "s"
        )
        local label = makeLabel(
            row, text, UDim2.fromOffset(group.Icon and 38 or 10, 0),
            UDim2.new(1, group.Icon and -44 or -16, 1, 0),
            {textSize = 10, textColor = group.Crafts > 0 and COLORS.Text or COLORS.Muted}
        )
        label.Active = false
        row.Activated:Connect(function()
            CoreAutomation.selectMachinePet(kind, group)
        end)
    end
end

function CoreAutomation.refreshMachineUI(kind, rebuild)
    local state = CoreAutomation.machineState(kind)
    local ui = UI.Machines and UI.Machines[kind]
    if not state or not ui then return end

    local selectedName = "Choose a pet"
    local selectedCrafts = 0
    local selectedAmount = 0
    local matches = CoreAutomation.refreshMachineMatches(kind, "")
    for _, group in ipairs(matches) do
        if tostring(group.ID) == tostring(state.SelectedID) then
            selectedName = group.Name
            selectedCrafts = group.Crafts
            selectedAmount = group.Amount
            break
        end
    end

    ui.Selected.Text = string.format("%s  •  x%d  •  %d ready", selectedName, selectedAmount, selectedCrafts)
    ui.Status.Text = state.Busy and "Working..." or (state.LastError or state.LastAction or "Ready")
    ui.Required.Text = string.format("%d pets per craft", CoreAutomation.machineRequired(kind))
    applySwitchVisual(ui.Auto, state.Auto == true)
    if rebuild == true then CoreAutomation.rebuildMachineSuggestions(kind) end
end

function CoreAutomation.buildPetMachineSection(page, kind)
    UI.Machines[kind] = {}
    local title = kind .. " Machine"
    local section = makeSection(page, title, 382)
    local ui = UI.Machines[kind]
    local state = CoreAutomation.machineState(kind)

    ui.Search = makeTextBox(
        section, "", UDim2.fromOffset(14, 42), UDim2.new(1, -108, 0, 34),
        {placeholder = kind == "Rainbow" and "Search Golden pets" or "Search Normal pets"}
    )
    ui.Search.Text = state.Search
    local clear = makeButton(section, "Clear", UDim2.new(1, -88, 0, 42), UDim2.fromOffset(74, 34), {backgroundColor = COLORS.Panel2})

    ui.Suggestions = Instance.new("ScrollingFrame")
    ui.Suggestions.Name = kind .. "PetSuggestions"
    ui.Suggestions.BackgroundColor3 = COLORS.Input
    ui.Suggestions.BorderSizePixel = 0
    ui.Suggestions.Position = UDim2.fromOffset(14, 84)
    ui.Suggestions.Size = UDim2.new(1, -28, 0, 144)
    ui.Suggestions.ScrollBarThickness = 3
    ui.Suggestions.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ui.Suggestions.CanvasSize = UDim2.new()
    ui.Suggestions.Parent = section
    makeCorner(ui.Suggestions, 8)

    ui.Selected = makeLabel(
        section, "Choose a pet", UDim2.fromOffset(14, 236), UDim2.new(1, -28, 0, 32),
        {backgroundTransparency = 0, backgroundColor = COLORS.Panel2, corner = 7, xAlignment = Enum.TextXAlignment.Center, textColor = COLORS.Muted, textSize = 10}
    )
    ui.Required = makeLabel(section, "", UDim2.fromOffset(14, 270), UDim2.new(1, -28, 0, 20), {textColor = COLORS.Muted, textSize = 9, xAlignment = Enum.TextXAlignment.Center})
    ui.Auto = makeSwitch(section, "Always Make " .. kind .. " Pet", UDim2.fromOffset(14, 294), false)
    local now = makeButton(section, "Make Now", UDim2.fromOffset(14, 334), UDim2.new(0.38, -7, 0, 32), {backgroundColor = COLORS.AccentDark})
    ui.Status = makeLabel(section, "Ready", UDim2.new(0.38, 7, 0, 334), UDim2.new(0.62, -21, 0, 32), {wrapped = true, textColor = COLORS.Muted, textSize = 10, yAlignment = Enum.TextYAlignment.Center})

    ui.Search:GetPropertyChangedSignal("Text"):Connect(function()
        state.Search = ui.Search.Text
        if kind == "Rainbow" then Config.eggs.rainbowSearch = state.Search else Config.eggs.goldSearch = state.Search end
        markConfigDirty()
        state.SearchToken = (tonumber(state.SearchToken) or 0) + 1
        local token = state.SearchToken
        task.delay(0.12, function()
            if Runtime.Alive and token == state.SearchToken then CoreAutomation.rebuildMachineSuggestions(kind) end
        end)
    end)
    clear.Activated:Connect(function()
        state.Search = ""
        state.SelectedID = ""
        ui.Search.Text = ""
        if kind == "Rainbow" then
            Config.eggs.rainbowSearch = ""
            Config.eggs.rainbowSelectedPetID = ""
        else
            Config.eggs.goldSearch = ""
            Config.eggs.goldSelectedPetID = ""
        end
        markConfigDirty()
        CoreAutomation.refreshMachineUI(kind, true)
    end)
    ui.Auto.Button.Activated:Connect(function()
        CoreAutomation.setPetMachineAuto(kind, not state.Auto)
    end)
    now.Activated:Connect(function() CoreAutomation.runPetMachine(kind, true) end)

    CoreAutomation.refreshMachineUI(kind, true)
end

function CoreAutomation.infiniteWorlds()
    if CoreAutomation.InfinityEggCmds and type(CoreAutomation.InfinityEggCmds.GetWorldNumbers) == "function" then
        local ok, worlds = pcall(CoreAutomation.InfinityEggCmds.GetWorldNumbers)
        if ok and type(worlds) == "table" and #worlds > 0 then
            table.sort(worlds)
            return worlds
        end
    end
    return {1, 2, 3, 4}
end

function CoreAutomation.infiniteEnsureWorld()
    local engine = CoreAutomation.InfiniteEggEngine
    local worlds = CoreAutomation.infiniteWorlds()
    if not table.find(worlds, engine.SelectedWorld) then engine.SelectedWorld = worlds[1] or 1 end
    Config.infiniteEggs.selectedWorld = engine.SelectedWorld
    return worlds
end

function CoreAutomation.infiniteEligibleEggs(world)
    if CoreAutomation.InfinityEggCmds and type(CoreAutomation.InfinityEggCmds.GetEligibleEggs) == "function" then
        local ok, eggs = pcall(CoreAutomation.InfinityEggCmds.GetEligibleEggs, world)
        if ok and type(eggs) == "table" then return eggs end
    end
    return {}
end

function CoreAutomation.refreshInfiniteIndexCounts(force)
    local engine = CoreAutomation.InfiniteEggEngine
    local now = os.clock()
    if engine.IndexBusy then return false, engine.IndexCounts end
    if force ~= true and type(engine.IndexCounts) == "table" and next(engine.IndexCounts) ~= nil and now < (engine.NextIndexRefreshAt or 0) then
        return true, engine.IndexCounts
    end
    if not Network or type(Network.Invoke) ~= "function" then return false, engine.IndexCounts end

    engine.IndexBusy = true
    local ok, counts = pcall(Network.Invoke, "Index: Request Hatch Count")
    engine.IndexBusy = false
    if ok and type(counts) == "table" then
        engine.IndexCounts = counts
        engine.IndexVersion = (engine.IndexVersion or 0) + 1
        engine.LastIndexRefreshAt = now
        engine.NextIndexRefreshAt = now + 0.55
        return true, counts
    end
    engine.NextIndexRefreshAt = now + 1.25
    appendLog("INFINITE_INDEX", "refresh failed: " .. tostring(counts))
    return false, engine.IndexCounts
end

function CoreAutomation.infiniteEntryPetNames(entry)
    local names = {}
    local seen = {}
    if type(entry) ~= "table" or type(entry.pets) ~= "table" then return names end
    for _, petEntry in ipairs(entry.pets) do
        local petID = nil
        if type(petEntry) == "table" then
            petID = petEntry[1] or petEntry.id or petEntry._id or petEntry.name
        elseif type(petEntry) == "string" then
            petID = petEntry
        end
        petID = petID and tostring(petID) or nil
        if petID and petID ~= "" and not seen[petID] then
            seen[petID] = true
            names[#names + 1] = petID
        end
    end
    return names
end

function CoreAutomation.infiniteProgress(entry)
    local engine = CoreAutomation.InfiniteEggEngine
    local petNames = CoreAutomation.infiniteEntryPetNames(entry)
    if #petNames > 0 and type(engine.IndexCounts) == "table" and next(engine.IndexCounts) ~= nil then
        local owned = 0
        for _, petName in ipairs(petNames) do
            if (tonumber(engine.IndexCounts[petName]) or 0) > 0 then owned = owned + 1 end
        end
        return owned, #petNames, owned >= #petNames
    end
    if CoreAutomation.InfinityEggCmds and type(CoreAutomation.InfinityEggCmds.GetHatchProgress) == "function" then
        local ok, owned, total, indexed = pcall(CoreAutomation.InfinityEggCmds.GetHatchProgress, entry)
        if ok then return tonumber(owned) or 0, tonumber(total) or 0, indexed == true end
    end
    return 0, 0, false
end

function CoreAutomation.infiniteIsEnabled(eggID)
    if CoreAutomation.InfinityEggCmds and type(CoreAutomation.InfinityEggCmds.IsEnabled) == "function" then
        local ok, enabled = pcall(CoreAutomation.InfinityEggCmds.IsEnabled, eggID)
        return ok and enabled == true
    end
    return false
end

function CoreAutomation.infiniteSetEgg(eggID, enabled)
    if not CoreAutomation.InfinityEggCmds or type(CoreAutomation.InfinityEggCmds.SetDisabled) ~= "function" then
        setNotice("Infinite Eggs are unavailable.", "error")
        return false
    end
    local ok, success = pcall(CoreAutomation.InfinityEggCmds.SetDisabled, tostring(eggID), enabled ~= true)
    if ok and success == true then
        CoreAutomation.InfiniteEggEngine.LastAction = (enabled and "Enabled " or "Disabled ") .. tostring(eggID)
        task.delay(0.12, function() if Runtime.Alive and CoreAutomation.refreshInfiniteEggUI then CoreAutomation.refreshInfiniteEggUI(true) end end)
        return true
    end
    CoreAutomation.InfiniteEggEngine.LastError = tostring(success or "Egg toggle failed.")
    setNotice(CoreAutomation.InfiniteEggEngine.LastError, "error")
    return false
end

function CoreAutomation.infiniteSetWorld(world, enabled)
    if not CoreAutomation.InfinityEggCmds or type(CoreAutomation.InfinityEggCmds.SetWorldDisabled) ~= "function" then
        setNotice("Infinite Eggs are unavailable.", "error")
        return false
    end
    local ok, success = pcall(CoreAutomation.InfinityEggCmds.SetWorldDisabled, tonumber(world) or 1, enabled ~= true)
    if ok and success == true then
        CoreAutomation.InfiniteEggEngine.LastAction = string.format("World %d %s", tonumber(world) or 1, enabled and "enabled" or "disabled")
        task.delay(0.12, function() if Runtime.Alive and CoreAutomation.refreshInfiniteEggUI then CoreAutomation.refreshInfiniteEggUI(true) end end)
        return true
    end
    CoreAutomation.InfiniteEggEngine.LastError = tostring(success or "World toggle failed.")
    setNotice(CoreAutomation.InfiniteEggEngine.LastError, "error")
    return false
end

function CoreAutomation.infiniteHatchAmount()
    if CoreAutomation.InfiniteEggEngine.AmountMode == "1" then return 1 end
    if EggCmds and type(EggCmds.GetMaxHatch) == "function" then
        local ok, amount = pcall(EggCmds.GetMaxHatch)
        if ok then return math.max(1, math.floor(tonumber(amount) or 1)) end
    end
    return 1
end

function CoreAutomation.runInfiniteHatch(manual)
    if not requirePremium("Infinite Egg Automation") then
        return false
    end
    local engine = CoreAutomation.InfiniteEggEngine
    if engine.Busy or not Runtime.Alive then return false end
    if not Network or type(Network.Invoke) ~= "function" then
        engine.LastError = "Infinite Egg network is unavailable."
        return false
    end

    if CoreAutomation.InfinityEggCmds and type(CoreAutomation.InfinityEggCmds.GetGlobalCount) == "function" then
        local okCount, enabled = pcall(CoreAutomation.InfinityEggCmds.GetGlobalCount)
        if okCount and (tonumber(enabled) or 0) <= 0 then
            engine.LastError = "Enable at least one egg first."
            engine.LastAction = engine.LastError
            engine.AutoOpen = false
            Config.infiniteEggs.autoOpen = false
            markConfigDirty()
            if manual then setNotice(engine.LastError, "info") end
            if CoreAutomation.refreshInfiniteEggUI then CoreAutomation.refreshInfiniteEggUI(false) end
            return false
        end
    end

    local amount = CoreAutomation.infiniteHatchAmount()
    engine.Busy = true
    local ok, success, message = pcall(Network.Invoke, "Eggs_RequestPurchase", "Infinity Egg", amount)
    engine.Busy = false

    appendLog("INFINITE_EGG", string.format("amount=%d ok=%s success=%s message=%s", amount, tostring(ok), tostring(success), tostring(message)))

    if ok and success == true then
        engine.Stats.Hatches = engine.Stats.Hatches + amount
        engine.LastError = nil
        engine.LastAction = string.format("Opened %d Infinite Egg%s", amount, amount == 1 and "" or "s")
        if engine.AutoDisableIndexed then
            task.delay(0.30, function()
                if Runtime.Alive and engine.Alive and engine.AutoDisableIndexed then
                    CoreAutomation.refreshInfiniteIndexCounts(true)
                    CoreAutomation.disableIndexedInfiniteEggs(false, true)
                    engine.NextIndexAt = 0
                end
            end)
        end
        if manual then setNotice(engine.LastAction .. ".", "success") end
        if CoreAutomation.refreshInfiniteEggUI then CoreAutomation.refreshInfiniteEggUI(false) end
        return true
    end

    engine.LastError = tostring(message or success or "Hatch rejected.")
    engine.LastAction = engine.LastError
    engine.AutoOpen = false
    Config.infiniteEggs.autoOpen = false
    markConfigDirty()
    if manual then setNotice(engine.LastError, "error") end
    if CoreAutomation.refreshInfiniteEggUI then CoreAutomation.refreshInfiniteEggUI(false) end
    return false
end

function CoreAutomation.disableIndexedInfiniteEggs(manual, skipRefresh)
    local engine = CoreAutomation.InfiniteEggEngine
    if not CoreAutomation.InfinityEggCmds then return false end
    if skipRefresh ~= true then CoreAutomation.refreshInfiniteIndexCounts(manual == true) end
    local disabledEggs = 0
    local disabledWorlds = 0

    for _, world in ipairs(CoreAutomation.infiniteWorlds()) do
        local eggs = CoreAutomation.infiniteEligibleEggs(world)
        local allIndexed = #eggs > 0
        local worldEnabled = 0
        if type(CoreAutomation.InfinityEggCmds.GetWorldCount) == "function" then
            local okCount, enabled = pcall(CoreAutomation.InfinityEggCmds.GetWorldCount, world)
            if okCount then worldEnabled = tonumber(enabled) or 0 end
        end
        for _, entry in ipairs(eggs) do
            local _, _, indexed = CoreAutomation.infiniteProgress(entry)
            if not indexed then allIndexed = false end
            if indexed and CoreAutomation.infiniteIsEnabled(entry._id) then
                local ok, success = pcall(CoreAutomation.InfinityEggCmds.SetDisabled, entry._id, true)
                if ok and success == true then disabledEggs = disabledEggs + 1 end
            end
        end
        if allIndexed and worldEnabled > 0 then
            local ok, success = pcall(CoreAutomation.InfinityEggCmds.SetWorldDisabled, world, true)
            if ok and success == true then disabledWorlds = disabledWorlds + 1 end
        end
    end

    engine.Stats.EggsDisabled = engine.Stats.EggsDisabled + disabledEggs
    engine.Stats.WorldsDisabled = engine.Stats.WorldsDisabled + disabledWorlds
    engine.LastError = nil
    engine.LastAction = disabledEggs > 0 or disabledWorlds > 0
        and string.format("Disabled %d indexed egg%s", disabledEggs, disabledEggs == 1 and "" or "s")
        or "Watching for newly indexed pets"
    if manual then setNotice(engine.LastAction .. ".", disabledEggs > 0 and "success" or "info") end
    if CoreAutomation.refreshInfiniteEggUI then
        CoreAutomation.refreshInfiniteEggUI(Runtime.SelectedTab == "InfiniteEggs" and (disabledEggs > 0 or disabledWorlds > 0))
    end
    return disabledEggs > 0 or disabledWorlds > 0
end

function CoreAutomation.rebuildInfiniteEggRows()
    local ui = UI.InfiniteEggs
    if not ui or not ui.Eggs or not ui.Eggs.Parent then return end
    for _, child in ipairs(ui.Eggs:GetChildren()) do
        if child.Name == "InfiniteEggRow" then child:Destroy() end
    end

    local engine = CoreAutomation.InfiniteEggEngine
    local eggs = CoreAutomation.infiniteEligibleEggs(engine.SelectedWorld)
    ui.Eggs.CanvasSize = UDim2.fromOffset(0, #eggs * 42 + 6)

    if #eggs == 0 then
        local empty = makeLabel(ui.Eggs, "No unlocked eggs in this world.", UDim2.fromOffset(10, 8), UDim2.new(1, -20, 0, 30), {textColor = COLORS.Muted, textSize = 10, xAlignment = Enum.TextXAlignment.Center})
        empty.Name = "InfiniteEggRow"
        return
    end

    for index, entry in ipairs(eggs) do
        local enabled = CoreAutomation.infiniteIsEnabled(entry._id)
        local owned, total, indexed = CoreAutomation.infiniteProgress(entry)
        local row = makeButton(ui.Eggs, "", UDim2.fromOffset(6, 6 + (index - 1) * 42), UDim2.new(1, -12, 0, 36), {backgroundColor = enabled and COLORS.Panel2 or COLORS.Input, textSize = 10})
        row.Name = "InfiniteEggRow"

        local iconAsset = nil
        if type(entry.pets) == "table" and type(entry.pets[1]) == "table" then
            local petID = entry.pets[1][1]
            if petID and CoreAutomation.PetItem then
                local okPet, pet = pcall(CoreAutomation.PetItem, petID)
                if okPet and type(pet) == "table" then iconAsset = CoreAutomation.majorPetIconAsset(itemMethod(pet, "GetIcon", nil)) end
            end
        end
        if iconAsset then
            local icon = Instance.new("ImageLabel")
            icon.BackgroundTransparency = 1
            icon.Position = UDim2.fromOffset(5, 4)
            icon.Size = UDim2.fromOffset(28, 28)
            icon.Image = iconAsset
            icon.Parent = row
        end

        local progress = indexed and "Indexed!" or string.format("%d/%d", owned, total)
        local text = string.format("%s  •  %s  •  %s", tostring(entry.name or entry._id), progress, enabled and "ON" or "OFF")
        local label = makeLabel(row, text, UDim2.fromOffset(iconAsset and 38 or 10, 0), UDim2.new(1, iconAsset and -44 or -16, 1, 0), {textSize = 10, textColor = indexed and COLORS.Success or (enabled and COLORS.Text or COLORS.Muted)})
        label.Active = false
        row.Activated:Connect(function()
            CoreAutomation.infiniteSetEgg(entry._id, not enabled)
        end)
    end
end

function CoreAutomation.refreshInfiniteEggUI(rebuild)
    local ui = UI.InfiniteEggs
    local engine = CoreAutomation.InfiniteEggEngine
    if not ui or not ui.World then return end

    if rebuild == true then CoreAutomation.refreshInfiniteIndexCounts(false) end
    CoreAutomation.infiniteEnsureWorld()
    local enabled, total = 0, 0
    if CoreAutomation.InfinityEggCmds and type(CoreAutomation.InfinityEggCmds.GetWorldCount) == "function" then
        local ok, a, b = pcall(CoreAutomation.InfinityEggCmds.GetWorldCount, engine.SelectedWorld)
        if ok then enabled, total = tonumber(a) or 0, tonumber(b) or 0 end
    end

    ui.World.Text = string.format("World %d", engine.SelectedWorld)
    ui.WorldStatus.Text = string.format("%d/%d eggs enabled", enabled, total)
    ui.Amount.Text = "Amount: " .. engine.AmountMode
    ui.Status.Text = engine.Busy and "Opening..." or (engine.LastError or engine.LastAction or "Ready")
    applySwitchVisual(ui.AutoOpen, engine.AutoOpen == true)
    applySwitchVisual(ui.AutoIndexed, engine.AutoDisableIndexed == true)
    if rebuild == true then CoreAutomation.rebuildInfiniteEggRows() end
end

function CoreAutomation.cycleInfiniteWorld(direction)
    local worlds = CoreAutomation.infiniteEnsureWorld()
    local index = table.find(worlds, CoreAutomation.InfiniteEggEngine.SelectedWorld) or 1
    index = index + (tonumber(direction) or 1)
    if index < 1 then index = #worlds elseif index > #worlds then index = 1 end
    CoreAutomation.InfiniteEggEngine.SelectedWorld = worlds[index] or 1
    Config.infiniteEggs.selectedWorld = CoreAutomation.InfiniteEggEngine.SelectedWorld
    markConfigDirty()
    CoreAutomation.refreshInfiniteEggUI(true)
end

function CoreAutomation.buildInfiniteEggsPage(page)
    makeVerticalLayout(page, 10)
    local engine = CoreAutomation.InfiniteEggEngine

    local world = makeSection(page, "Infinite Eggs", 158)
    local previous = makeButton(world, "Previous", UDim2.fromOffset(14, 42), UDim2.new(0.25, -10, 0, 34), {backgroundColor = COLORS.Input})
    local worldLabel = makeLabel(world, "World 1", UDim2.new(0.25, 2, 0, 42), UDim2.new(0.5, -4, 0, 34), {backgroundTransparency = 0, backgroundColor = COLORS.Input, xAlignment = Enum.TextXAlignment.Center, textSize = 11, corner = 7})
    local nextButton = makeButton(world, "Next", UDim2.new(0.75, 8, 0, 42), UDim2.new(0.25, -22, 0, 34), {backgroundColor = COLORS.Input})
    local worldStatus = makeLabel(world, "", UDim2.fromOffset(14, 78), UDim2.new(1, -28, 0, 26), {textColor = COLORS.Muted, textSize = 10, xAlignment = Enum.TextXAlignment.Center})
    local enableWorld = makeButton(world, "Enable World", UDim2.fromOffset(14, 112), UDim2.new(0.5, -21, 0, 32), {backgroundColor = COLORS.AccentDark})
    local disableWorld = makeButton(world, "Disable World", UDim2.new(0.5, 7, 0, 112), UDim2.new(0.5, -21, 0, 32), {backgroundColor = COLORS.Panel2})

    local eggs = makeSection(page, "Egg Selection", 302)
    local eggList = Instance.new("ScrollingFrame")
    eggList.BackgroundColor3 = COLORS.Input
    eggList.BorderSizePixel = 0
    eggList.Position = UDim2.fromOffset(14, 42)
    eggList.Size = UDim2.new(1, -28, 1, -56)
    eggList.ScrollBarThickness = 3
    eggList.CanvasSize = UDim2.new()
    eggList.Parent = eggs
    makeCorner(eggList, 8)

    local automation = makeSection(page, "Automation", 218)
    local amount = makeButton(automation, "Amount: Max", UDim2.fromOffset(14, 42), UDim2.new(1, -28, 0, 34), {backgroundColor = COLORS.Input})
    local autoOpen = makeSwitch(automation, "Auto Open Infinite Egg", UDim2.fromOffset(14, 84), not IS_PREMIUM)
    local autoIndexed = makeSwitch(automation, "Auto Turn Off Indexed Eggs", UDim2.fromOffset(14, 124), not IS_PREMIUM)
    local hatchNow = makeButton(automation, "Hatch Now", UDim2.fromOffset(14, 166), UDim2.new(0.38, -7, 0, 34), {backgroundColor = COLORS.AccentDark})
    local indexedNow = makeButton(automation, "Check Indexed", UDim2.new(0.38, 7, 0, 166), UDim2.new(0.34, -7, 0, 34), {backgroundColor = COLORS.Panel2})
    local status = makeLabel(automation, "Ready", UDim2.new(0.72, 7, 0, 166), UDim2.new(0.28, -21, 0, 34), {wrapped = true, textColor = COLORS.Muted, textSize = 9, yAlignment = Enum.TextYAlignment.Center})

    UI.InfiniteEggs = {
        World = worldLabel, WorldStatus = worldStatus, Eggs = eggList,
        Amount = amount, AutoOpen = autoOpen, AutoIndexed = autoIndexed, Status = status,
    }

    previous.Activated:Connect(function() CoreAutomation.cycleInfiniteWorld(-1) end)
    nextButton.Activated:Connect(function() CoreAutomation.cycleInfiniteWorld(1) end)
    enableWorld.Activated:Connect(function() CoreAutomation.infiniteSetWorld(engine.SelectedWorld, true) end)
    disableWorld.Activated:Connect(function() CoreAutomation.infiniteSetWorld(engine.SelectedWorld, false) end)
    amount.Activated:Connect(function()
        engine.AmountMode = engine.AmountMode == "Max" and "1" or "Max"
        Config.infiniteEggs.amountMode = engine.AmountMode
        markConfigDirty()
        CoreAutomation.refreshInfiniteEggUI(false)
    end)
    autoOpen.Button.Activated:Connect(function()
        if not engine.AutoOpen and not requirePremium("Auto Open Infinite Egg") then return end
        engine.AutoOpen = not engine.AutoOpen
        engine.NextHatchAt = 0
        engine.LastError = nil
        engine.LastAction = engine.AutoOpen and "Auto Open running" or "Auto Open stopped"
        Config.infiniteEggs.autoOpen = engine.AutoOpen
        markConfigDirty()
        CoreAutomation.refreshInfiniteEggUI(false)
    end)
    autoIndexed.Button.Activated:Connect(function()
        if not engine.AutoDisableIndexed and not requirePremium("Auto Turn Off Indexed Eggs") then return end
        engine.AutoDisableIndexed = not engine.AutoDisableIndexed
        engine.NextIndexAt = 0
        engine.NextIndexRefreshAt = 0
        engine.LastError = nil
        engine.LastAction = engine.AutoDisableIndexed and "Watching every new indexed pet" or "Index watcher stopped"
        Config.infiniteEggs.autoDisableIndexed = engine.AutoDisableIndexed
        markConfigDirty()
        if engine.AutoDisableIndexed then
            task.spawn(function()
                CoreAutomation.refreshInfiniteIndexCounts(true)
                CoreAutomation.disableIndexedInfiniteEggs(false, true)
            end)
        end
        CoreAutomation.refreshInfiniteEggUI(false)
    end)
    hatchNow.Activated:Connect(function() CoreAutomation.runInfiniteHatch(true) end)
    indexedNow.Activated:Connect(function() CoreAutomation.disableIndexedInfiniteEggs(true) end)

    CoreAutomation.refreshInfiniteEggUI(true)
end

task.spawn(function()
    while Runtime.Alive and CoreAutomation.Machines.Alive do
        local now = os.clock()
        for _, kind in ipairs({"Gold", "Rainbow"}) do
            local state = CoreAutomation.machineState(kind)
            if state and state.Auto and not state.Busy and now >= (state.NextAt or 0) then
                state.NextAt = now + 1.15
                CoreAutomation.runPetMachine(kind, false)
                break
            end
        end
        task.wait(0.20)
    end
end)

task.spawn(function()
    local engine = CoreAutomation.InfiniteEggEngine
    while Runtime.Alive and engine.Alive do
        local now = os.clock()
        if engine.AutoDisableIndexed and now >= (engine.NextIndexAt or 0) then
            engine.NextIndexAt = now + 0.75
            CoreAutomation.refreshInfiniteIndexCounts(false)
            CoreAutomation.disableIndexedInfiniteEggs(false, true)
        end
        if engine.AutoOpen and not engine.Busy and now >= (engine.NextHatchAt or 0) then
            engine.NextHatchAt = now + 1.65
            CoreAutomation.runInfiniteHatch(false)
        end
        if Runtime.SelectedTab == "InfiniteEggs" and now >= (engine.NextUIAt or 0) then
            engine.NextUIAt = now + 2.5
            if CoreAutomation.refreshInfiniteEggUI then CoreAutomation.refreshInfiniteEggUI(true) end
        end
        task.wait(0.20)
    end
end)

function CoreAutomation.buildNormalEggsPage(page)
    makeVerticalLayout(page, 10)

    local buy = makeSection(page, "Normal Eggs", 232)
    local modeButton = makeButton(
        buy,
        "Best Egg",
        UDim2.fromOffset(14, 38),
        UDim2.new(1, -28, 0, 36),
        {backgroundColor = COLORS.Input, textSize = 12}
    )
    local previous = makeButton(buy, "Previous", UDim2.fromOffset(14, 82), UDim2.new(0.25, -10, 0, 34), {backgroundColor = COLORS.Input})
    local selected = makeLabel(
        buy,
        "Detecting eggs...",
        UDim2.new(0.25, 2, 0, 82),
        UDim2.new(0.5, -4, 0, 34),
        {backgroundTransparency = 0, backgroundColor = COLORS.Input, xAlignment = Enum.TextXAlignment.Center, textSize = 11, corner = 7}
    )
    local nextButton = makeButton(buy, "Next", UDim2.new(0.75, 8, 0, 82), UDim2.new(0.25, -22, 0, 34), {backgroundColor = COLORS.Input})
    local details = makeLabel(
        buy,
        "",
        UDim2.fromOffset(14, 122),
        UDim2.new(1, -28, 0, 28),
        {textColor = COLORS.Muted, textSize = 10, xAlignment = Enum.TextXAlignment.Center}
    )
    local autoBuy = makeSwitch(buy, "Auto Buy Selected Egg", UDim2.fromOffset(14, 152), false)
    local disableAnimation = makeSwitch(buy, "Disable Egg Animation", UDim2.fromOffset(14, 190), false)

    local statusSection = makeSection(page, "Auto Open", 82)
    local status = makeLabel(
        statusSection,
        "",
        UDim2.fromOffset(14, 38),
        UDim2.new(1, -28, 0, 34),
        {wrapped = true, textColor = COLORS.Muted, textSize = 11, yAlignment = Enum.TextYAlignment.Center}
    )

    UI.NormalEggs = {
        Mode = modeButton,
        Selected = selected,
        Details = details,
        AutoBuy = autoBuy,
        DisableAnimation = disableAnimation,
        Status = status,
    }

    modeButton.Activated:Connect(CoreAutomation.cycleNormalEggMode)
    previous.Activated:Connect(function() CoreAutomation.cycleNormalEggSelection(-1) end)
    nextButton.Activated:Connect(function() CoreAutomation.cycleNormalEggSelection(1) end)
    autoBuy.Button.Activated:Connect(function()
        if CoreAutomation.NormalEggEngine.Running then
            CoreAutomation.stopNormalEggs("Stopped by user")
        else
            CoreAutomation.startNormalEggs()
        end
    end)
    disableAnimation.Button.Activated:Connect(function()
        EggEngine.DisableAnimation = not EggEngine.DisableAnimation
        Config.eggs.disableAnimation = EggEngine.DisableAnimation
        markConfigDirty()
        local supported = EggEngine:ApplyAnimationSetting()
        if EggEngine.DisableAnimation and not supported then
            setNotice("Animation blocking is not supported by this executor.", "info")
        end
        if CoreAutomation.refreshNormalEggUI then
            CoreAutomation.refreshNormalEggUI()
        end
    end)

    CoreAutomation.refreshNormalEggUI = function()
        if not UI.NormalEggs.Mode or not UI.NormalEggs.Mode.Parent then
            return
        end

        local entry = CoreAutomation.resolvedNormalEgg()
        UI.NormalEggs.Mode.Text = CoreAutomation.NormalEggEngine.Mode
        UI.NormalEggs.Selected.Text = entry and entry.Name or "Choose an egg"
        UI.NormalEggs.Details.Text = entry
            and ("Hatch up to " .. tostring(CoreAutomation.normalEggMaxHatch()) .. " at once")
            or "Event eggs are inside Event."

        applySwitchVisual(UI.NormalEggs.AutoBuy, CoreAutomation.NormalEggEngine.Running)
        applySwitchVisual(UI.NormalEggs.DisableAnimation, EggEngine.DisableAnimation)

        if CoreAutomation.NormalEggEngine.Running then
            UI.NormalEggs.Status.Text = CoreAutomation.NormalEggEngine.LastAction
        elseif CoreAutomation.NormalEggEngine.LastError then
            UI.NormalEggs.Status.Text = CoreAutomation.NormalEggEngine.LastError
        else
            UI.NormalEggs.Status.Text = "Ready"
        end
    end

    CoreAutomation.buildPetMachineSection(page, "Gold")
    CoreAutomation.buildPetMachineSection(page, "Rainbow")

    CoreAutomation.refreshNormalEggs(true)
    EggEngine:ApplyAnimationSetting()
    CoreAutomation.refreshNormalEggUI()
end

function CoreAutomation.clearAutomaticRows(
    section
)
    if not section then
        return
    end

    for _, child in ipairs(
        section:GetChildren()
    ) do
        if child.Name == "DynamicAutomaticRow" then
            child:Destroy()
        end
    end
end

function CoreAutomation.rebuildFruitConfigRows()
    local section =
        UI.Automatic.FruitConfigSection

    if not section then
        return
    end

    CoreAutomation.clearAutomaticRows(section)
    CoreAutomation.refreshConsumables(true)

    local expanded =
        CoreAutomation.AutomaticEngine
            .FruitConfigExpanded

    section.Size =
        UDim2.new(
            1,
            0,
            0,
            expanded
                and (
                    60
                    + math.max(
                        1,
                        #CoreAutomation.AutomaticEngine
                            .Fruits
                    ) * 34
                )
                or 58
        )

    UI.Automatic.FruitConfigButton.Text =
        expanded
        and "Fruits  v"
        or "Fruits  >"

    if not expanded then
        return
    end

    if #CoreAutomation.AutomaticEngine.Fruits == 0 then
        local empty = makeLabel(
            section,
            "No fruits found.",
            UDim2.fromOffset(14, 42),
            UDim2.new(1, -28, 0, 28),
            {
                textColor = COLORS.Muted,
                textSize = 11,
            }
        )

        empty.Name = "DynamicAutomaticRow"
        return
    end

    for index, entry in ipairs(
        CoreAutomation.AutomaticEngine.Fruits
    ) do
        local row = Instance.new("Frame")
        row.Name = "DynamicAutomaticRow"
        row.BackgroundTransparency = 1
        row.Position =
            UDim2.fromOffset(
                14,
                42 + (index - 1) * 34
            )
        row.Size =
            UDim2.new(1, -28, 0, 30)
        row.Parent = section

        makeLabel(
            row,
            (entry.DisplayName or entry.Name)
                .. " • x"
                .. formatCompactNumber(entry.Amount),
            UDim2.fromOffset(0, 0),
            UDim2.new(1, -76, 1, 0),
            {
                textSize = 11,
            }
        )

        local toggle = makeButton(
            row,
            CoreAutomation.fruitIsSelected(entry)
                and "ON"
                or "OFF",
            UDim2.new(1, -68, 0, 1),
            UDim2.fromOffset(68, 28),
            {
                backgroundColor =
                    CoreAutomation.fruitIsSelected(entry)
                    and COLORS.Success
                    or COLORS.Input,
                textSize = 10,
            }
        )

        toggle.Activated:Connect(function()
            local enabled =
                not CoreAutomation
                    .fruitIsSelected(entry)

            CoreAutomation.setFruitSelected(
                entry,
                enabled
            )

            toggle.Text =
                enabled and "ON" or "OFF"

            toggle.BackgroundColor3 =
                enabled
                and COLORS.Success
                or COLORS.Input
        end)
    end
end

function CoreAutomation.rebuildPotionConfigRows()
    local section =
        UI.Automatic.PotionConfigSection

    if not section then
        return
    end

    CoreAutomation.clearAutomaticRows(section)
    CoreAutomation.refreshConsumables(true)

    local expanded =
        CoreAutomation.AutomaticEngine
            .PotionConfigExpanded

    local groups = {}

    for _, entry in ipairs(
        CoreAutomation.AutomaticEngine.Potions
    ) do
        if entry.Tier >= 7 then
            local group = groups[entry.ID]

            if not group then
                group = {
                    ID = entry.ID,
                    Name = CoreAutomation
                        .potionCategoryName(entry),
                    Highest = entry,
                    LowestTier = entry.Tier,
                    HighestTier = entry.Tier,
                    Amount = 0,
                }
                groups[entry.ID] = group
            end

            group.Amount = group.Amount + entry.Amount
            group.LowestTier = math.min(
                group.LowestTier,
                entry.Tier
            )
            group.HighestTier = math.max(
                group.HighestTier,
                entry.Tier
            )

            if entry.Tier > group.Highest.Tier then
                group.Highest = entry
            end
        end
    end

    local ordered = {}
    for _, group in pairs(groups) do
        table.insert(ordered, group)
    end

    table.sort(ordered, function(left, right)
        return left.Name < right.Name
    end)

    section.Size =
        UDim2.new(
            1,
            0,
            0,
            expanded
                and (
                    60
                    + math.max(1, #ordered) * 34
                )
                or 58
        )

    UI.Automatic.PotionConfigButton.Text =
        expanded
        and "Potions  v"
        or "Potions  >"

    if not expanded then
        return
    end

    if #ordered == 0 then
        local empty = makeLabel(
            section,
            "No Tier 7+ potions found.",
            UDim2.fromOffset(14, 42),
            UDim2.new(1, -28, 0, 28),
            {
                textColor = COLORS.Muted,
                textSize = 11,
            }
        )

        empty.Name = "DynamicAutomaticRow"
        return
    end

    for index, group in ipairs(ordered) do
        local row = Instance.new("Frame")
        row.Name = "DynamicAutomaticRow"
        row.BackgroundTransparency = 1
        row.Position =
            UDim2.fromOffset(
                14,
                42 + (index - 1) * 34
            )
        row.Size =
            UDim2.new(1, -28, 0, 30)
        row.Parent = section

        local tierText =
            group.LowestTier == group.HighestTier
            and ("Tier " .. tostring(group.HighestTier))
            or (
                "Tiers "
                .. tostring(group.LowestTier)
                .. "-"
                .. tostring(group.HighestTier)
            )

        makeLabel(
            row,
            group.Name
                .. " • "
                .. tierText
                .. " • x"
                .. formatCompactNumber(group.Amount),
            UDim2.fromOffset(0, 0),
            UDim2.new(1, -76, 1, 0),
            {
                textSize = 11,
            }
        )

        local selected =
            CoreAutomation.potionCategorySelected(
                group.ID
            )

        local toggle = makeButton(
            row,
            selected and "ON" or "OFF",
            UDim2.new(1, -68, 0, 1),
            UDim2.fromOffset(68, 28),
            {
                backgroundColor =
                    selected
                    and COLORS.Success
                    or COLORS.Input,
                textSize = 10,
            }
        )

        toggle.Activated:Connect(function()
            local enabled =
                not CoreAutomation
                    .potionCategorySelected(group.ID)

            CoreAutomation.setPotionCategorySelected(
                group.ID,
                enabled
            )

            toggle.Text =
                enabled and "ON" or "OFF"

            toggle.BackgroundColor3 =
                enabled
                and COLORS.Success
                or COLORS.Input
        end)
    end
end

function CoreAutomation.buildAutomaticPage(page)
    makeVerticalLayout(page, 10)

    local quick =
        makeSection(
            page,
            "Automatic",
            190
        )

    local fruitSwitch = makeSwitch(
        quick,
        "Auto Eat Fruits",
        UDim2.fromOffset(14, 36),
        false
    )

    local potionSwitch = makeSwitch(
        quick,
        "Auto Use Potions",
        UDim2.fromOffset(14, 72),
        false
    )

    local toysSwitch = makeSwitch(
        quick,
        "Auto Use Toys",
        UDim2.fromOffset(14, 108),
        false
    )

    local ultimateSwitch = makeSwitch(
        quick,
        "Auto Ultimate",
        UDim2.fromOffset(14, 144),
        false
    )

    local fruitConfig =
        makeSection(
            page,
            "",
            58
        )

    local fruitConfigButton = makeButton(
        fruitConfig,
        "Fruit Config  >",
        UDim2.fromOffset(14, 12),
        UDim2.new(1, -28, 0, 34),
        {
            backgroundColor = COLORS.Panel2,
            textSize = 11,
        }
    )

    local potionConfig =
        makeSection(
            page,
            "",
            58
        )

    local potionConfigButton = makeButton(
        potionConfig,
        "Potion Config  >",
        UDim2.fromOffset(14, 12),
        UDim2.new(1, -28, 0, 34),
        {
            backgroundColor = COLORS.Panel2,
            textSize = 11,
        }
    )

    local statusSection =
        makeSection(
            page,
            "Status",
            96
        )

    local status = makeLabel(
        statusSection,
        "",
        UDim2.fromOffset(14, 38),
        UDim2.new(1, -28, 0, 48),
        {
            wrapped = true,
            textColor = COLORS.Muted,
            textSize = 10,
            yAlignment =
                Enum.TextYAlignment.Top,
        }
    )

    UI.Automatic = {
        FruitSwitch = fruitSwitch,
        PotionSwitch = potionSwitch,
        ToysSwitch = toysSwitch,
        UltimateSwitch = ultimateSwitch,

        FruitConfigSection = fruitConfig,
        FruitConfigButton = fruitConfigButton,
        PotionConfigSection = potionConfig,
        PotionConfigButton = potionConfigButton,

        Status = status,
    }

    fruitSwitch.Button.Activated:Connect(function()
        CoreAutomation.setAutomaticFeature(
            "Fruit",
            not CoreAutomation.AutomaticEngine.AutoFruit
        )
    end)

    potionSwitch.Button.Activated:Connect(function()
        CoreAutomation.setAutomaticFeature(
            "Potion",
            not CoreAutomation.AutomaticEngine.AutoPotion
        )
    end)

    toysSwitch.Button.Activated:Connect(function()
        CoreAutomation.setAutomaticFeature(
            "Toys",
            not CoreAutomation.AutomaticEngine.AutoToys
        )
    end)

    ultimateSwitch.Button.Activated:Connect(function()
        CoreAutomation.setAutomaticFeature(
            "Ultimate",
            not CoreAutomation.AutomaticEngine
                .AutoUltimate
        )
    end)

    fruitConfigButton.Activated:Connect(function()
        CoreAutomation.AutomaticEngine
            .FruitConfigExpanded =
            not CoreAutomation.AutomaticEngine
                .FruitConfigExpanded

        CoreAutomation.rebuildFruitConfigRows()
    end)

    potionConfigButton.Activated:Connect(function()
        CoreAutomation.AutomaticEngine
            .PotionConfigExpanded =
            not CoreAutomation.AutomaticEngine
                .PotionConfigExpanded

        CoreAutomation.rebuildPotionConfigRows()
    end)

    CoreAutomation.refreshAutomaticUI = function()
        if not UI.Automatic.Status
            or not UI.Automatic.Status.Parent
        then
            return
        end

        applySwitchVisual(UI.Automatic.FruitSwitch, CoreAutomation.AutomaticEngine.AutoFruit)
        applySwitchVisual(UI.Automatic.PotionSwitch, CoreAutomation.AutomaticEngine.AutoPotion)
        applySwitchVisual(UI.Automatic.ToysSwitch, CoreAutomation.AutomaticEngine.AutoToys)
        applySwitchVisual(UI.Automatic.UltimateSwitch, CoreAutomation.AutomaticEngine.AutoUltimate)

        local active = {}
        if CoreAutomation.AutomaticEngine.AutoFruit then table.insert(active, "Fruits") end
        if CoreAutomation.AutomaticEngine.AutoPotion then table.insert(active, "Potions") end
        if CoreAutomation.AutomaticEngine.AutoToys then table.insert(active, "Toys") end
        if CoreAutomation.AutomaticEngine.AutoUltimate then table.insert(active, "Ultimate") end

        UI.Automatic.Status.Text = #active > 0
            and ("Running: " .. table.concat(active, " + "))
            or (CoreAutomation.AutomaticEngine.LastError and "Paused  •  Check your choices" or "Ready")
    end

    CoreAutomation.refreshConsumables(true)
    CoreAutomation.rebuildFruitConfigRows()
    CoreAutomation.rebuildPotionConfigRows()
    CoreAutomation.refreshAutomaticUI()
end

-- Teleport-only page removed in V0.1.0.5.7.
-- Best-area and best-world travel now live inside Auto Farm.

local function buildEventPage(page)
    makeVerticalLayout(page, 12)

    local hidden = Instance.new("Frame")
    hidden.Name = "HiddenEventControls"
    hidden.BackgroundTransparency = 1
    hidden.Size = UDim2.fromOffset(1, 1)
    hidden.Visible = false
    hidden.Parent = page

    local header = makeSection(page, "Garden Event", 82)

    UI.Event.ModuleTitle = makeLabel(
        hidden,
        "Garden Event",
        UDim2.fromOffset(0, 0),
        UDim2.fromOffset(1, 1)
    )

    UI.Event.ModuleBadge = makeLabel(
        header,
        "WAITING",
        UDim2.new(1, -108, 0, 39),
        UDim2.fromOffset(94, 26),
        {
            backgroundTransparency = 0,
            backgroundColor = COLORS.Input,
            textColor = COLORS.Text,
            textSize = 10,
            xAlignment = Enum.TextXAlignment.Center,
            corner = 13,
        }
    )

    UI.Event.ModuleInfo = makeLabel(
        header,
        "Enter the Garden to start.",
        UDim2.fromOffset(14, 38),
        UDim2.new(1, -132, 0, 28),
        {
            textColor = COLORS.Muted,
            textSize = 11,
        }
    )

    UI.Event.GardenMetrics = makeLabel(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))
    UI.Event.GardenLastAction = makeLabel(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))

    local automation = makeSection(page, "Garden", 260)

    UI.Event.FullCampaignSwitch = makeSwitch(
        automation,
        "Auto Everything",
        UDim2.fromOffset(14, 36),
        not IS_PREMIUM
    )

    UI.Event.AutoCollectSwitch = makeSwitch(
        automation,
        "Auto Collect",
        UDim2.fromOffset(14, 72),
        false
    )

    UI.Event.AutoPlantSwitch = makeSwitch(
        automation,
        "Auto Plant",
        UDim2.fromOffset(14, 108),
        false
    )

    UI.Event.SeedPrevious = makeButton(
        automation,
        "‹",
        UDim2.fromOffset(14, 148),
        UDim2.fromOffset(40, 34),
        {textSize = 18}
    )

    UI.Event.SeedSelector = makeButton(
        automation,
        "Choose Seed",
        UDim2.fromOffset(60, 148),
        UDim2.new(1, -120, 0, 34),
        {
            backgroundColor = COLORS.Panel2,
            wrapped = true,
            textSize = 10,
        }
    )

    UI.Event.SeedNext = makeButton(
        automation,
        "›",
        UDim2.new(1, -54, 0, 148),
        UDim2.fromOffset(40, 34),
        {textSize = 18}
    )

    UI.Event.AutoReinforceSwitch = makeSwitch(
        automation,
        "Auto Reinforce",
        UDim2.fromOffset(14, 188),
        false
    )

    UI.Event.AutomationStats = makeLabel(
        automation,
        "Ready",
        UDim2.fromOffset(14, 226),
        UDim2.new(1, -28, 0, 24),
        {
            textColor = COLORS.Muted,
            textSize = 10,
            xAlignment = Enum.TextXAlignment.Center,
        }
    )

    UI.Event.AutoLaneSwitch = makeSwitch(hidden, "", UDim2.new(), false)
    UI.Event.AutoPlotSwitch = makeSwitch(hidden, "", UDim2.new(), false)
    UI.Event.AutoRegrowSwitch = makeSwitch(hidden, "", UDim2.new(), false)
    UI.Event.AutoMerchantSwitch = makeSwitch(hidden, "", UDim2.new(), false)

    local collectNow = makeButton(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))
    local plantNow = makeButton(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))
    local laneNow = makeButton(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))
    local plotNow = makeButton(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))
    local regrowNow = makeButton(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))

    local missions = makeSection(page, "Garden Missions", 164)

    UI.Event.MissionDirectorSwitch = makeSwitch(
        missions,
        "Mission Director",
        UDim2.fromOffset(14, 36),
        not IS_PREMIUM
    )

    UI.Event.AutoSuperRebirthSwitch = makeSwitch(
        missions,
        "Auto Super Rebirth",
        UDim2.fromOffset(14, 72),
        not IS_PREMIUM
    )

    UI.Event.MissionStatus = makeLabel(
        missions,
        "Waiting for Garden Missions",
        UDim2.fromOffset(14, 112),
        UDim2.new(1, -28, 0, 38),
        {
            backgroundTransparency = 0,
            backgroundColor = COLORS.Panel2,
            wrapped = true,
            textColor = COLORS.Muted,
            textSize = 10,
            xAlignment = Enum.TextXAlignment.Center,
            corner = 9,
        }
    )

    local upgrades = makeSection(page, "Upgrade Machine", 314)

    UI.Event.AutoUpgradeSwitch = makeSwitch(
        upgrades,
        "Auto Upgrade Selected",
        UDim2.fromOffset(14, 36),
        not IS_PREMIUM
    )

    UI.Event.UpgradeSwitches = {}

    for index, upgradeID in ipairs(GARDEN_UPGRADE_IDS) do
        local selectedUpgradeID = upgradeID
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local switch = makeSwitch(
            upgrades,
            GardenAutomation.UpgradeLabels[selectedUpgradeID]
                or selectedUpgradeID,
            UDim2.new(
                column * 0.5,
                column == 0 and 14 or 7,
                0,
                76 + row * 38
            ),
            false
        )

        switch.Holder.Size = UDim2.new(0.5, -21, 0, 36)
        switch.Label.TextSize = 10
        UI.Event.UpgradeSwitches[selectedUpgradeID] = switch

        switch.Button.Activated:Connect(function()
            GardenAutomation:SetUpgradeSelected(
                selectedUpgradeID,
                not GardenAutomation:IsUpgradeSelected(selectedUpgradeID)
            )
        end)
    end

    local upgradeNow = makeButton(
        upgrades,
        "Upgrade Selected Now",
        UDim2.fromOffset(14, 232),
        UDim2.new(1, -28, 0, 36),
        {backgroundColor = COLORS.AccentDark}
    )

    UI.Event.UpgradeStatus = makeLabel(
        upgrades,
        "Select the upgrades SliceHub may buy.",
        UDim2.fromOffset(14, 274),
        UDim2.new(1, -28, 0, 24),
        {
            textColor = COLORS.Muted,
            textSize = 10,
            xAlignment = Enum.TextXAlignment.Center,
        }
    )



    local craftSection = makeSection(page, "Craft Pets", 260)

    UI.Event.AutoCraftSwitch = makeSwitch(
        craftSection,
        "Auto Craft Selected",
        UDim2.fromOffset(14, 36),
        not IS_PREMIUM
    )

    UI.Event.CraftSwitches = {}
    for index, recipeID in ipairs(GardenAutomation.CraftOrder) do
        local selectedRecipeID = recipeID
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local switch = makeSwitch(
            craftSection,
            GardenAutomation.CraftLabels[selectedRecipeID],
            UDim2.new(
                column * 0.5,
                column == 0 and 14 or 7,
                0,
                76 + row * 38
            ),
            false
        )
        switch.Holder.Size = UDim2.new(0.5, -21, 0, 36)
        switch.Label.TextSize = 9
        UI.Event.CraftSwitches[selectedRecipeID] = switch

        switch.Button.Activated:Connect(function()
            GardenAutomation:SetCraftSelected(
                selectedRecipeID,
                not GardenAutomation:IsCraftSelected(selectedRecipeID)
            )
        end)
    end

    UI.Event.CraftNow = makeButton(
        craftSection,
        "Craft / Claim Selected Now",
        UDim2.fromOffset(14, 160),
        UDim2.new(1, -28, 0, 36),
        {backgroundColor = COLORS.AccentDark}
    )

    UI.Event.CraftStatus = makeLabel(
        craftSection,
        "Choose the recipes SliceHub may craft.",
        UDim2.fromOffset(14, 204),
        UDim2.new(1, -28, 0, 42),
        {
            backgroundTransparency = 0,
            backgroundColor = COLORS.Panel2,
            wrapped = true,
            textColor = COLORS.Muted,
            textSize = 10,
            xAlignment = Enum.TextXAlignment.Center,
            corner = 9,
        }
    )

    local luckSection = makeSection(page, "Event Luck", 244)

    UI.Event.AutoLuckSwitch = makeSwitch(
        luckSection,
        "Auto Keep Selected Near 6 Hours",
        UDim2.fromOffset(14, 36),
        not IS_PREMIUM
    )

    UI.Event.LuckSwitches = {}
    for index, rarity in ipairs(GardenAutomation.LuckPriority) do
        local selectedRarity = rarity
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local switch = makeSwitch(
            luckSection,
            selectedRarity .. " Luck",
            UDim2.new(
                column * 0.5,
                column == 0 and 14 or 7,
                0,
                78 + row * 38
            ),
            false
        )
        switch.Holder.Size = UDim2.new(0.5, -21, 0, 36)
        switch.Label.TextSize = 10
        UI.Event.LuckSwitches[selectedRarity] = switch

        switch.Button.Activated:Connect(function()
            GardenAutomation:SetLuckSelected(
                selectedRarity,
                not GardenAutomation:IsLuckSelected(selectedRarity)
            )
        end)
    end

    UI.Event.LuckNow = makeButton(
        luckSection,
        "Max Selected Now",
        UDim2.fromOffset(14, 154),
        UDim2.new(1, -28, 0, 36),
        {backgroundColor = COLORS.AccentDark}
    )

    UI.Event.LuckStatus = makeLabel(
        luckSection,
        "Choose the luck boosts SliceHub may refill.",
        UDim2.fromOffset(14, 198),
        UDim2.new(1, -28, 0, 32),
        {
            backgroundTransparency = 0,
            backgroundColor = COLORS.Panel2,
            wrapped = true,
            textColor = COLORS.Muted,
            textSize = 9,
            xAlignment = Enum.TextXAlignment.Center,
            corner = 9,
        }
    )

    local lineTools = makeSection(page, "Line Filler", 294)

    UI.Event.LineUnitPrevious = makeButton(
        lineTools,
        "‹",
        UDim2.fromOffset(14, 42),
        UDim2.fromOffset(40, 34),
        {textSize = 18}
    )

    UI.Event.LineUnitSelector = makeButton(
        lineTools,
        "Choose Filler Pet",
        UDim2.fromOffset(60, 42),
        UDim2.new(1, -120, 0, 34),
        {
            backgroundColor = COLORS.Panel2,
            wrapped = true,
            textSize = 10,
        }
    )

    UI.Event.LineUnitNext = makeButton(
        lineTools,
        "›",
        UDim2.new(1, -54, 0, 42),
        UDim2.fromOffset(40, 34),
        {textSize = 18}
    )

    UI.Event.AutoFillLinesSwitch = makeSwitch(
        lineTools,
        "Auto Fill Lines",
        UDim2.fromOffset(14, 84),
        false
    )

    UI.Event.CleanAllLines = makeButton(
        lineTools,
        "Clean All Lines",
        UDim2.fromOffset(14, 124),
        UDim2.new(1, -112, 0, 36),
        {
            backgroundColor = COLORS.Error,
            textSize = 11,
        }
    )

    UI.Event.StopCleaning = makeButton(
        lineTools,
        "Stop",
        UDim2.new(1, -94, 0, 124),
        UDim2.fromOffset(80, 36),
        {
            backgroundColor = COLORS.Panel2,
            textSize = 10,
        }
    )
    UI.Event.StopCleaning.Visible = false

    UI.Event.CleanLineButtons = {}

    for lineNumber = 1, 7 do
        local row = math.floor((lineNumber - 1) / 4)
        local column = (lineNumber - 1) % 4
        local button = makeButton(
            lineTools,
            "Line " .. tostring(lineNumber),
            UDim2.new(
                column / 4,
                column == 0 and 14 or 5,
                0,
                168 + row * 40
            ),
            UDim2.new(0.25, -12, 0, 32),
            {
                backgroundColor = COLORS.Panel2,
                textSize = 10,
            }
        )

        button.Visible = false
        UI.Event.CleanLineButtons[lineNumber] = button
    end

    UI.Event.LineStatus = makeLabel(
        lineTools,
        "Enter the Garden first.",
        UDim2.fromOffset(14, 250),
        UDim2.new(1, -28, 0, 30),
        {
            backgroundTransparency = 0,
            backgroundColor = COLORS.Panel2,
            textColor = COLORS.Muted,
            xAlignment = Enum.TextXAlignment.Center,
            textSize = 10,
            wrapped = true,
            corner = 10,
        }
    )

    local eggSection = makeSection(page, "Event Eggs", 250)

    UI.Event.EggPrevious = makeButton(
        eggSection,
        "‹",
        UDim2.fromOffset(14, 42),
        UDim2.fromOffset(40, 34),
        {textSize = 18}
    )

    UI.Event.EggSelector = makeButton(
        eggSection,
        "Choose Event Egg",
        UDim2.fromOffset(60, 42),
        UDim2.new(1, -120, 0, 34),
        {
            backgroundColor = COLORS.Panel2,
            wrapped = true,
            textSize = 10,
        }
    )

    UI.Event.EggNext = makeButton(
        eggSection,
        "›",
        UDim2.new(1, -54, 0, 42),
        UDim2.fromOffset(40, 34),
        {textSize = 18}
    )

    makeLabel(
        eggSection,
        "Amount",
        UDim2.fromOffset(14, 86),
        UDim2.fromOffset(68, 30),
        {font = Enum.Font.GothamMedium, textSize = 11}
    )

    UI.Event.AmountMinus = makeButton(eggSection, "−", UDim2.fromOffset(84, 84), UDim2.fromOffset(36, 30))
    UI.Event.AmountBox = makeTextBox(eggSection, tostring(EggEngine.RequestedAmount), UDim2.fromOffset(126, 84), UDim2.fromOffset(72, 30))
    UI.Event.AmountPlus = makeButton(eggSection, "+", UDim2.fromOffset(204, 84), UDim2.fromOffset(36, 30))
    UI.Event.AmountMax = makeButton(eggSection, "MAX", UDim2.fromOffset(246, 84), UDim2.fromOffset(62, 30), {backgroundColor = COLORS.AccentDark})

    UI.Event.MaxSwitch = makeSwitch(
        eggSection,
        "Always Hatch Max",
        UDim2.fromOffset(14, 122),
        not IS_PREMIUM
    )

    UI.Event.StartButton = makeButton(
        eggSection,
        "Start Auto Open",
        UDim2.fromOffset(14, 164),
        UDim2.new(0.5, -21, 0, 36),
        {backgroundColor = COLORS.Success}
    )

    UI.Event.StopButton = makeButton(
        eggSection,
        "Stop",
        UDim2.new(0.5, 7, 0, 164),
        UDim2.new(0.5, -21, 0, 36),
        {backgroundColor = COLORS.Error}
    )

    UI.Event.Metrics = makeLabel(
        eggSection,
        "Ready",
        UDim2.fromOffset(14, 208),
        UDim2.new(1, -28, 0, 28),
        {
            backgroundTransparency = 0,
            backgroundColor = COLORS.Panel2,
            xAlignment = Enum.TextXAlignment.Center,
            textSize = 10,
            corner = 9,
        }
    )

    local eggPremium = makeSection(page, "Egg Enhancements", 132)
    UI.Event.SpeedButton = makeButton(
        eggPremium,
        IS_PREMIUM and ("Speed: " .. tostring(EggEngine.SpeedMode)) or "🔒 Fast Egg Speed  •  PREMIUM",
        UDim2.fromOffset(14, 38),
        UDim2.new(1, -28, 0, 34),
        {backgroundColor = IS_PREMIUM and COLORS.AccentDark or COLORS.Panel2, textSize = 11}
    )
    UI.Event.ResumeSwitch = makeSwitch(
        eggPremium,
        "Resume After Reconnect",
        UDim2.fromOffset(14, 78),
        not IS_PREMIUM
    )
    UI.Event.DelayLabel = makeLabel(
        eggPremium,
        IS_PREMIUM and "Premium removes the Free 3-hatch event cap." or "Free event eggs are capped at 3 per cycle.",
        UDim2.fromOffset(14, 110),
        UDim2.new(1, -28, 0, 18),
        {textColor = COLORS.Muted, textSize = 9, xAlignment = Enum.TextXAlignment.Center}
    )
    UI.Event.RefreshButton = makeButton(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))
    UI.Event.NearestButton = makeButton(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))
    UI.Event.EggDetails = makeLabel(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))
    UI.Event.RecentPets = makeLabel(hidden, "", UDim2.new(), UDim2.fromOffset(1, 1))

    UI.Event.AutoCollectSwitch.Button.Activated:Connect(function()
        setGardenFeature("AutoCollect", not GardenAutomation.AutoCollect)
    end)

    UI.Event.AutoPlantSwitch.Button.Activated:Connect(function()
        if not GardenAutomation.AutoPlant and not selectedGardenSeed() then
            setNotice("Choose a Garden seed before enabling Auto Plant.", "error")
            return
        end
        setGardenFeature("AutoPlant", not GardenAutomation.AutoPlant)
    end)

    UI.Event.SeedPrevious.Activated:Connect(function()
        cycleGardenSeed(-1)
    end)

    UI.Event.SeedSelector.Activated:Connect(function()
        cycleGardenSeed(1)
    end)

    UI.Event.SeedNext.Activated:Connect(function()
        cycleGardenSeed(1)
    end)

    UI.Event.AutoLaneSwitch.Button.Activated:Connect(function()
        setGardenFeature("AutoUnlockLanes", not GardenAutomation.AutoUnlockLanes)
    end)

    UI.Event.AutoPlotSwitch.Button.Activated:Connect(function()
        setGardenFeature("AutoBuyPlots", not GardenAutomation.AutoBuyPlots)
    end)

    UI.Event.AutoUpgradeSwitch.Button.Activated:Connect(function()
        if not GardenAutomation.AutoUpgrades
            and GardenAutomation:SelectedUpgradeCount() <= 0
        then
            setNotice(
                "Select at least one Upgrade Machine option first.",
                "error"
            )
            return
        end

        setGardenFeature("AutoUpgrades", not GardenAutomation.AutoUpgrades)
    end)

    UI.Event.AutoRegrowSwitch.Button.Activated:Connect(function()
        setGardenFeature("AutoRegrow", not GardenAutomation.AutoRegrow)
    end)

    UI.Event.FullCampaignSwitch.Button.Activated:Connect(function()
        setGardenFeature("FullCampaign", not GardenAutomation.FullCampaign)
    end)

    UI.Event.MissionDirectorSwitch.Button.Activated:Connect(function()
        GardenAutomation.Next.Mission = 0
        setGardenFeature(
            "MissionDirector",
            not GardenAutomation.MissionDirector
        )
    end)

    UI.Event.AutoSuperRebirthSwitch.Button.Activated:Connect(function()
        GardenAutomation.Next.Mission = 0
        GardenAutomation.Next.SuperRebirth = 0
        setGardenFeature(
            "AutoSuperRebirth",
            not GardenAutomation.AutoSuperRebirth
        )
    end)

    UI.Event.AutoMerchantSwitch.Button.Activated:Connect(function()
        GardenAutomation.Next.Merchant = 0
        setGardenFeature("AutoMerchant", not GardenAutomation.AutoMerchant)
    end)

    UI.Event.AutoReinforceSwitch.Button.Activated:Connect(function()
        GardenAutomation.Next.Reinforce = 0
        setGardenFeature("AutoReinforce", not GardenAutomation.AutoReinforce)
    end)

    collectNow.Activated:Connect(function()
        local success, detail = runGardenAction("Collect crop", collectOneBed)
        setNotice(
            success and "Collected."
                or tostring(detail or "Nothing ready."),
            success and "success" or "info"
        )
    end)

    plantNow.Activated:Connect(function()
        local success, detail = runGardenAction("Plant seed", plantOneSeed)
        setNotice(
            success and GardenAutomation.LastAction
                or tostring(detail or "Could not plant."),
            success and "success" or "error"
        )
    end)

    laneNow.Activated:Connect(function()
        local success, detail = runGardenAction("Unlock lane", unlockLaneOnce)
        setNotice(
            success and GardenAutomation.LastAction
                or tostring(detail or "Could not buy lane."),
            success and "success" or "error"
        )
    end)

    plotNow.Activated:Connect(function()
        local success, detail = runGardenAction("Buy plot", buyPlotOnce)
        setNotice(
            success and GardenAutomation.LastAction
                or tostring(detail or "Could not buy plot."),
            success and "success" or "error"
        )
    end)

    upgradeNow.Activated:Connect(function()
        if not requirePremium("Selective Garden Upgrades") then
            return
        end

        local success, detail = runGardenAction(
            "Buy Garden upgrade",
            buyUpgradeOnce
        )
        setNotice(
            success and GardenAutomation.LastAction
                or tostring(detail or "No selected upgrade bought."),
            success and "success" or "error"
        )
    end)

    regrowNow.Activated:Connect(function()
        local success, detail = runGardenAction("Rebirth", regrowOnce)
        setNotice(
            success and GardenAutomation.LastAction
                or tostring(detail or "Not ready."),
            success and "success" or "error"
        )
    end)



    UI.Event.AutoCraftSwitch.Button.Activated:Connect(function()
        GardenAutomation:SetCraftAuto(
            not GardenAutomation.AutoCraftSelected
        )
    end)

    UI.Event.CraftNow.Activated:Connect(function()
        task.spawn(function()
            if not requirePremium("Event Pet Crafting") then
                return
            end
            local success, detail = runGardenAction(
                "Event craft",
                function()
                    return GardenAutomation:CraftSelectedStep()
                end
            )
            setNotice(
                tostring(detail or (success and "Craft request accepted." or "Nothing crafted.")),
                success and "success" or "info"
            )
        end)
    end)

    UI.Event.AutoLuckSwitch.Button.Activated:Connect(function()
        GardenAutomation:SetLuckAuto(
            not GardenAutomation.AutoMaxLuck
        )
    end)

    UI.Event.LuckNow.Activated:Connect(function()
        task.spawn(function()
            if not requirePremium("Event Luck") then
                return
            end
            if GardenAutomation:SelectedLuckCount() <= 0 then
                setNotice("Select at least one Event Luck rarity first.", "error")
                return
            end

            local anySuccess = false
            local lastDetail = nil
            for _ = 1, 3 do
                local success, detail = runGardenAction(
                    "Event Luck",
                    function()
                        return GardenAutomation:MaxSelectedLuckStep(true)
                    end
                )
                anySuccess = anySuccess or success == true
                lastDetail = detail or lastDetail
                task.wait(0.18)
            end

            setNotice(
                tostring(lastDetail or (anySuccess and "Selected Event Luck maxed." or "No refill needed.")),
                anySuccess and "success" or "info"
            )
        end)
    end)

    UI.Event.LineUnitPrevious.Activated:Connect(function()
        if GardenLineTools.Available then
            local success, detail = GardenLineTools:CycleUnit(-1)
            setNotice(tostring(detail), success and "success" or "error")
            refreshEventUI()
        end
    end)

    UI.Event.LineUnitSelector.Activated:Connect(function()
        if GardenLineTools.Available then
            local success, detail = GardenLineTools:CycleUnit(1)
            setNotice(tostring(detail), success and "success" or "error")
            refreshEventUI()
        end
    end)

    UI.Event.LineUnitNext.Activated:Connect(function()
        if GardenLineTools.Available then
            local success, detail = GardenLineTools:CycleUnit(1)
            setNotice(tostring(detail), success and "success" or "error")
            refreshEventUI()
        end
    end)

    UI.Event.AutoFillLinesSwitch.Button.Activated:Connect(function()
        if not GardenLineTools.Available then
            setNotice("Line tools are unavailable.", "error")
            return
        end

        local success, detail = GardenLineTools:SetAutoFill(
            not GardenLineTools.AutoFill
        )

        setNotice(
            tostring(detail),
            success and "success" or "error"
        )
        refreshEventUI()
    end)

    UI.Event.StopCleaning.Activated:Connect(function()
        if GardenLineTools.Available
            and type(GardenLineTools.StopCleaning) == "function"
        then
            local success, detail = GardenLineTools:StopCleaning()
            setNotice(tostring(detail), success and "info" or "info")
            refreshEventUI()
        end
    end)

    UI.Event.CleanAllLines.Activated:Connect(function()
        task.spawn(function()
            if not GardenLineTools.Available then
                setNotice("Line tools are unavailable.", "error")
                return
            end

            local success, detail = GardenLineTools:CleanAllLines()
            setNotice(
                tostring(detail),
                success and "success" or "info"
            )
            refreshEventUI()
        end)
    end)

    for lineNumber, button in pairs(UI.Event.CleanLineButtons) do
        button.Activated:Connect(function()
            task.spawn(function()
                if not GardenLineTools.Available then
                    setNotice("Line tools are unavailable.", "error")
                    return
                end

                GardenLineTools:SetAutoFill(false)
                local success, detail =
                    GardenLineTools:CleanLine(lineNumber)

                setNotice(
                    tostring(detail),
                    success and "success" or "info"
                )
                refreshEventUI()
            end)
        end)
    end

    UI.Event.EggPrevious.Activated:Connect(function()
        cycleEggSelection(-1)
    end)

    UI.Event.EggNext.Activated:Connect(function()
        cycleEggSelection(1)
    end)

    UI.Event.EggSelector.Activated:Connect(chooseNearestHatchable)

    UI.Event.RefreshButton.Activated:Connect(function()
        refreshEggs("manual refresh")
        refreshGardenSeeds()
        setNotice("Garden event data refreshed.", "info")
    end)

    UI.Event.NearestButton.Activated:Connect(chooseNearestHatchable)

    UI.Event.AmountBox.FocusLost:Connect(function()
        setEggAmount(tonumber(UI.Event.AmountBox.Text) or 1)
    end)

    UI.Event.AmountMinus.Activated:Connect(function()
        setEggAmount(EggEngine.RequestedAmount - 1)
    end)

    UI.Event.AmountPlus.Activated:Connect(function()
        setEggAmount(EggEngine.RequestedAmount + 1)
    end)

    UI.Event.AmountMax.Activated:Connect(function()
        local entry = selectedEgg()
        if entry then
            entry.Maximum = getEggMaximum(entry.Egg)
            setEggAmount(entry.Maximum)
        end
    end)

    UI.Event.SpeedButton.Activated:Connect(function()
        if EggEngine.SpeedMode == "Stable" then
            setSpeedMode("Fast")
        else
            setSpeedMode("Stable")
        end
    end)

    UI.Event.MaxSwitch.Button.Activated:Connect(function()
        setUseMaximum(not EggEngine.UseMaximumEveryCycle)
    end)

    UI.Event.ResumeSwitch.Button.Activated:Connect(function()
        setResumeAfterReconnect(not EggEngine.ResumeAfterReconnect)
    end)

    UI.Event.StartButton.Activated:Connect(function()
        safeEventCall("StartFeature", "CustomEggs")
    end)

    UI.Event.StopButton.Activated:Connect(function()
        safeEventCall("StopFeature", "CustomEggs")
    end)
end

local function buildSettingsPage(page)
    makeVerticalLayout(page, 10)

    local themeSection = makeSection(page, "Candy Theme", 202)

    UI.Settings.ThemeName = makeLabel(
        themeSection,
        "",
        UDim2.fromOffset(14, 38),
        UDim2.new(1, -28, 0, 30),
        {
            backgroundTransparency = 0,
            backgroundColor = COLORS.Input,
            xAlignment = Enum.TextXAlignment.Center,
            font = Enum.Font.GothamBold,
            textSize = 12,
            corner = 9,
        }
    )

    makeLabel(
        themeSection,
        "Choose a theme.",
        UDim2.fromOffset(14, 70),
        UDim2.new(1, -28, 0, 22),
        {
            textColor = COLORS.Muted,
            textSize = 10,
            xAlignment = Enum.TextXAlignment.Center,
        }
    )

    local themeButtons = {}

    for index, themeName in ipairs(Theme.Order) do
        local row = math.floor((index - 1) / 3)
        local column = (index - 1) % 3
        local button = makeButton(
            themeSection,
            themeName,
            UDim2.new(
                column / 3,
                column == 0 and 14 or 7,
                0,
                102 + row * 44
            ),
            UDim2.new(1 / 3, -14, 0, 34),
            {
                backgroundColor = COLORS.Panel2,
                textSize = 10,
            }
        )

        themeButtons[themeName] = button

        button.Activated:Connect(function()
            Theme.Apply(themeName, false)
        end)
    end

    UI.Settings.ThemeButtons = themeButtons

    Theme.RefreshUI = function()
        if UI.Settings.ThemeName and UI.Settings.ThemeName.Parent then
            UI.Settings.ThemeName.Text =
                "Current theme: " .. tostring(Theme.CurrentName)
        end

        for themeName, button in pairs(UI.Settings.ThemeButtons or {}) do
            if button and button.Parent then
                button.BackgroundColor3 =
                    themeName == Theme.CurrentName
                    and COLORS.AccentDark
                    or COLORS.Panel2
                button.TextColor3 =
                    themeName == Theme.CurrentName
                    and COLORS.Text
                    or COLORS.Muted
            end
        end
    end

    Theme.RefreshUI()

    local storage = makeSection(page, "Saved Settings", 140)

    makeLabel(
        storage,
        "Save or reset your setup.",
        UDim2.fromOffset(14, 38),
        UDim2.new(1, -28, 0, 22),
        {
            textColor = COLORS.Muted,
            textSize = 11,
        }
    )

    makeLabel(
        storage,
        "Saved automatically",
        UDim2.fromOffset(14, 62),
        UDim2.new(1, -28, 0, 30),
        {
            backgroundTransparency = 0,
            backgroundColor = COLORS.Input,
            textSize = 11,
            xAlignment = Enum.TextXAlignment.Center,
            corner = 7,
        }
    )

    local saveButton = makeButton(
        storage,
        "Save Now",
        UDim2.fromOffset(14, 98),
        UDim2.new(0.5, -21, 0, 34),
        {
            backgroundColor = COLORS.AccentDark,
        }
    )

    local resetButton = makeButton(
        storage,
        "Reset Settings",
        UDim2.new(0.5, 7, 0, 98),
        UDim2.new(0.5, -21, 0, 34),
        {
            backgroundColor = COLORS.Error,
        }
    )

    local debugSwitch = makeSwitch(
        storage,
        "Diagnostics",
        UDim2.fromOffset(286, 104),
        false
    )
    debugSwitch.Holder.Visible = false

    applySwitchVisual(debugSwitch, Config.settings.debugLogging)

    saveButton.Activated:Connect(function()
        if saveConfig(true) then
            setNotice("PS99 settings saved.", "success")
        else
            setNotice("Could not save settings with this executor.", "error")
        end
    end)

    resetButton.Activated:Connect(function()
        Config = deepCopy(DEFAULT_CONFIG)
        if not IS_PREMIUM then
            Config.event.useMaximumEveryCycle = false
            Config.event.speedMode = "Stable"
            Config.event.resumeAfterReconnect = false
        end

        EggEngine.RequestedAmount = Config.event.requestedAmount
        EggEngine.UseMaximumEveryCycle = Config.event.useMaximumEveryCycle
        EggEngine.ResumeAfterReconnect = Config.event.resumeAfterReconnect
        setSpeedMode(Config.event.speedMode)
        syncGardenAutomationFromConfig()
        Theme.Apply(Config.settings.theme, true)

        configDirty = true
        saveConfig(true)
        setNotice("PS99 settings reset.", "success")

        applySwitchVisual(debugSwitch, Config.settings.debugLogging)
        if refreshEventUI then
            refreshEventUI()
        end
    end)

    debugSwitch.Button.Activated:Connect(function()
        Config.settings.debugLogging = not Config.settings.debugLogging
        markConfigDirty()
        applySwitchVisual(debugSwitch, Config.settings.debugLogging)
        setNotice(
            "Debug console logging " .. (Config.settings.debugLogging and "enabled." or "disabled."),
            "info"
        )
    end)

    local tier = makeSection(page, "About", 112)

    makeLabel(
        tier,
        USER_TIER,
        UDim2.fromOffset(14, 38),
        UDim2.fromOffset(120, 28),
        {
            backgroundTransparency = 0,
            backgroundColor = IS_PREMIUM and COLORS.Premium or COLORS.Input,
            xAlignment = Enum.TextXAlignment.Center,
            font = Enum.Font.GothamBold,
            textSize = 12,
            corner = 7,
        }
    )

    makeLabel(
        tier,
        "SliceHub PS99  •  " .. HUB_VERSION,
        UDim2.fromOffset(14, 75),
        UDim2.new(1, -28, 0, 24),
        {
            wrapped = true,
            textColor = COLORS.Muted,
            textSize = 11,
            yAlignment = Enum.TextYAlignment.Top,
        }
    )
end

refreshEventUI = function()
    if not UI.Event.ModuleBadge or not UI.Event.ModuleBadge.Parent then
        return
    end

    local status = getGardenStatus()
    GardenAutomation.LastStatus = status

    applySwitchVisual(UI.Event.AutoCollectSwitch, GardenAutomation.AutoCollect)
    applySwitchVisual(UI.Event.AutoPlantSwitch, GardenAutomation.AutoPlant)
    applySwitchVisual(UI.Event.AutoLaneSwitch, GardenAutomation.AutoUnlockLanes)
    applySwitchVisual(UI.Event.AutoPlotSwitch, GardenAutomation.AutoBuyPlots)
    applySwitchVisual(UI.Event.AutoUpgradeSwitch, GardenAutomation.AutoUpgrades)

    for upgradeID, switch in pairs(UI.Event.UpgradeSwitches or {}) do
        applySwitchVisual(
            switch,
            GardenAutomation:IsUpgradeSelected(upgradeID)
        )
    end

    if UI.Event.UpgradeStatus and UI.Event.UpgradeStatus.Parent then
        local selectedCount = GardenAutomation:SelectedUpgradeCount()
        UI.Event.UpgradeStatus.Text = selectedCount > 0
            and (
                tostring(selectedCount)
                    .. " selected  •  only these upgrades may be purchased"
            )
            or "Select the upgrades SliceHub may buy."
    end



    if UI.Event.AutoCraftSwitch and UI.Event.AutoCraftSwitch.Holder.Parent then
        applySwitchVisual(UI.Event.AutoCraftSwitch, GardenAutomation.AutoCraftSelected)
        for recipeID, switch in pairs(UI.Event.CraftSwitches or {}) do
            applySwitchVisual(
                switch,
                GardenAutomation:IsCraftSelected(recipeID)
            )
        end
        UI.Event.CraftStatus.Text = tostring(
            GardenAutomation.CraftLastStatus
                or "Choose the recipes SliceHub may craft."
        )
    end

    if UI.Event.AutoLuckSwitch and UI.Event.AutoLuckSwitch.Holder.Parent then
        applySwitchVisual(UI.Event.AutoLuckSwitch, GardenAutomation.AutoMaxLuck)
        for rarity, switch in pairs(UI.Event.LuckSwitches or {}) do
            applySwitchVisual(
                switch,
                GardenAutomation:IsLuckSelected(rarity)
            )
        end

        local parts = {}
        for _, rarity in ipairs(GardenAutomation.LuckPriority) do
            if GardenAutomation:IsLuckSelected(rarity) then
                local timeLeft = GardenAutomation:GetLuckTime(rarity)
                table.insert(
                    parts,
                    rarity .. " " .. (
                        timeLeft ~= nil
                        and GardenAutomation:FormatClock(timeLeft)
                        or "--"
                    )
                )
            end
        end
        UI.Event.LuckStatus.Text = #parts > 0
            and table.concat(parts, "  •  ")
            or tostring(
                GardenAutomation.LuckLastStatus
                    or "Choose the luck boosts SliceHub may refill."
            )
    end

    applySwitchVisual(UI.Event.AutoRegrowSwitch, GardenAutomation.AutoRegrow)
    applySwitchVisual(UI.Event.FullCampaignSwitch, GardenAutomation.FullCampaign)
    applySwitchVisual(
        UI.Event.MissionDirectorSwitch,
        GardenAutomation.MissionDirector
    )
    applySwitchVisual(
        UI.Event.AutoSuperRebirthSwitch,
        GardenAutomation.AutoSuperRebirth
    )
    applySwitchVisual(UI.Event.AutoMerchantSwitch, GardenAutomation.AutoMerchant)
    applySwitchVisual(UI.Event.AutoReinforceSwitch, GardenAutomation.AutoReinforce)

    if UI.Event.MissionStatus and UI.Event.MissionStatus.Parent then
        local mission = GardenAutomation.MissionState
        if type(mission) ~= "table"
            or os.clock() - (tonumber(mission.UpdatedAt) or 0) > 1.5
        then
            mission = GardenAutomation:RefreshMissionState()
        end

        if mission.Completed then
            UI.Event.MissionStatus.Text = GardenAutomation.AutoSuperRebirth
                and "All missions claimed  •  advancing when the biome is ready"
                or "All missions claimed  •  Super Rebirth ready"
        elseif not mission.Available then
            UI.Event.MissionStatus.Text = tostring(mission.GoalLabel)
        else
            UI.Event.MissionStatus.Text = string.format(
                "%s  •  %s/%s%s",
                tostring(mission.GoalLabel),
                formatCompactNumber(mission.Progress or 0),
                formatCompactNumber(mission.Amount or 0),
                mission.Claimable and "  •  claiming" or ""
            )
        end
    end

    local seed = selectedGardenSeed()
    if UI.Event.SeedSelector and UI.Event.SeedSelector.Parent then
        UI.Event.SeedSelector.Text = seed
            and (seed.Name .. "  ×" .. formatCompactNumber(seed.Amount))
            or (#GardenAutomation.Seeds > 0 and "Choose Seed" or "No Seeds")
    end

    if UI.Event.AutomationStats and UI.Event.AutomationStats.Parent then
        if not status.Supported then
            UI.Event.AutomationStats.Text = "Enter the Garden first."
        elseif GardenAutomation.FullCampaign then
            UI.Event.AutomationStats.Text = "Auto Everything is running."
        elseif GardenAutomation.MissionDirector then
            UI.Event.AutomationStats.Text = tostring(
                (GardenAutomation.MissionState or {}).GoalLabel
                or "Garden Mission Director is running."
            )
        elseif GardenAutomation.LastError then
            UI.Event.AutomationStats.Text = "Paused  •  Try again"
        else
            UI.Event.AutomationStats.Text = tostring(GardenAutomation.LastAction or "Ready")
        end
    end

    if UI.Event.LineUnitSelector and UI.Event.LineUnitSelector.Parent then
        if GardenLineTools.Available
            and type(GardenLineTools.GetView) == "function"
        then
            local lineView = GardenLineTools:GetView()

            applySwitchVisual(UI.Event.AutoFillLinesSwitch, lineView.autoFill == true)
            UI.Event.LineUnitSelector.Text = lineView.unitName == "None"
                and "Choose Filler Pet"
                or (lineView.unitName .. "  ×" .. tostring(lineView.unitAmount))

            for lineNumber, button in pairs(UI.Event.CleanLineButtons or {}) do
                button.Visible = lineNumber <= lineView.maxLine
            end
            if UI.Event.StopCleaning then
                UI.Event.StopCleaning.Visible = lineView.cleaning == true
            end

            if lineView.cleaning then
                UI.Event.LineStatus.Text = "Cleaning..."
            elseif lineView.lastError then
                UI.Event.LineStatus.Text = "Paused  •  Check the Garden"
            elseif lineView.autoFill then
                UI.Event.LineStatus.Text = "Filling " .. tostring(lineView.maxLine) .. " line"
                    .. (lineView.maxLine == 1 and "" or "s")
            else
                UI.Event.LineStatus.Text = tostring(lineView.maxLine) .. " line"
                    .. (lineView.maxLine == 1 and "" or "s") .. " ready"
            end
        else
            applySwitchVisual(UI.Event.AutoFillLinesSwitch, false)
            UI.Event.LineUnitSelector.Text = "Choose Filler Pet"

            for _, button in pairs(UI.Event.CleanLineButtons or {}) do
                button.Visible = false
            end
            if UI.Event.StopCleaning then
                UI.Event.StopCleaning.Visible = false
            end

            UI.Event.LineStatus.Text = "Enter the Garden first."
        end
    end

    local entry = selectedEgg()

    if UI.Event.EggSelector and UI.Event.EggSelector.Parent then
        if entry then
            entry.Distance = getEggDistance(entry.Egg)
            entry.Hatchable = isEggHatchable(entry.Egg)
            entry.Maximum = getEggMaximum(entry.Egg)
            UI.Event.EggSelector.Text = entry.Name
                .. (entry.Hatchable and "" or "  •  Locked")
        else
            UI.Event.EggSelector.Text = "No Event Egg"
        end

        UI.Event.AmountBox.Text = tostring(EggEngine.RequestedAmount)
        applySwitchVisual(UI.Event.MaxSwitch, EggEngine.UseMaximumEveryCycle)
        applySwitchVisual(UI.Event.ResumeSwitch, EggEngine.ResumeAfterReconnect)

        UI.Event.Metrics.Text = EggEngine.Running
            and ("Opening  •  " .. tostring(EggEngine.ConfirmedEggs) .. " pets found")
            or (EggEngine.LastError and "Stopped  •  Try again" or "Ready")

        UI.Event.StartButton.Text = EggEngine.Running and "Opening..." or "Start Auto Open"
    end

    local supported = CurrentEventModule.Supported

    if Runtime.EventFault then
        UI.Event.ModuleBadge.Text = "ERROR"
        UI.Event.ModuleBadge.BackgroundColor3 = COLORS.Error
        UI.Event.ModuleInfo.Text = "Reload SliceHub."
    elseif supported then
        UI.Event.ModuleBadge.Text = "READY"
        UI.Event.ModuleBadge.BackgroundColor3 = COLORS.Success
        UI.Event.ModuleInfo.Text = status.Supported and "Ready to grow." or "Enter the Garden to start."
    else
        UI.Event.ModuleBadge.Text = "WAITING"
        UI.Event.ModuleBadge.BackgroundColor3 = COLORS.Input
        UI.Event.ModuleInfo.Text = "Enter the Garden to start."
    end
end

--////////////////////////////////////////////////////////////////////
-- Main UI
--////////////////////////////////////////////////////////////////////

local function offsetPosition(position, yOffset)
    return UDim2.new(
        position.X.Scale,
        position.X.Offset,
        position.Y.Scale,
        position.Y.Offset + yOffset
    )
end

local function pulseMobileToggle()
    if not UI.ToggleButton
        or not UI.ToggleButton.Parent
        or not UI.ToggleButton.Visible
        or not UI.ToggleScale
    then
        return
    end

    UI.ToggleScale.Scale = 0.72

    tween(
        UI.ToggleScale,
        0.34,
        Enum.EasingStyle.Back,
        Enum.EasingDirection.Out,
        {Scale = 1.14}
    )

    task.delay(0.35, function()
        if UI.ToggleScale and UI.ToggleScale.Parent and UI.ToggleButton.Visible then
            tween(
                UI.ToggleScale,
                0.22,
                Enum.EasingStyle.Quint,
                Enum.EasingDirection.Out,
                {Scale = 1}
            )
        end
    end)
end

local function setHubVisible(visible, source)
    visible = visible == true
    Runtime.GUIVisible = visible
    Runtime.UIMotionToken = Runtime.UIMotionToken + 1

    local token = Runtime.UIMotionToken
    local main = UI.Main
    local scale = UI.MainScale
    local toggleButton = UI.ToggleButton

    if not main or not main.Parent then
        return
    end

    Runtime.UIAnimating = true

    if visible then
        if toggleButton and toggleButton.Parent then
            toggleButton.Visible = false
        end

        local restPosition = Runtime.UIRestPosition or main.Position
        Runtime.UIRestPosition = restPosition

        main.Visible = true
        main.Position = offsetPosition(restPosition, 34)

        if scale then
            scale.Scale = math.max(0.01, Runtime.UITargetScale * 0.88)
        end

        tween(
            main,
            0.30,
            Enum.EasingStyle.Quint,
            Enum.EasingDirection.Out,
            {Position = restPosition}
        )

        if scale then
            local scaleTween = tween(
                scale,
                0.34,
                Enum.EasingStyle.Back,
                Enum.EasingDirection.Out,
                {Scale = Runtime.UITargetScale}
            )

            if scaleTween then
                scaleTween.Completed:Connect(function()
                    if Runtime.UIMotionToken == token then
                        Runtime.UIAnimating = false
                    end
                end)
            else
                Runtime.UIAnimating = false
            end
        else
            task.delay(0.31, function()
                if Runtime.UIMotionToken == token then
                    Runtime.UIAnimating = false
                end
            end)
        end
    else
        Runtime.UIRestPosition = main.Position

        local restPosition = Runtime.UIRestPosition
        local moveTween = tween(
            main,
            0.20,
            Enum.EasingStyle.Quint,
            Enum.EasingDirection.In,
            {Position = offsetPosition(restPosition, 34)}
        )

        if scale then
            tween(
                scale,
                0.20,
                Enum.EasingStyle.Quint,
                Enum.EasingDirection.In,
                {Scale = math.max(0.01, Runtime.UITargetScale * 0.88)}
            )
        end

        local function finishHide()
            if Runtime.UIMotionToken ~= token or Runtime.GUIVisible then
                return
            end

            main.Visible = false
            main.Position = restPosition

            if scale then
                scale.Scale = Runtime.UITargetScale
            end

            Runtime.UIAnimating = false

            if toggleButton and toggleButton.Parent then
                toggleButton.Visible = true
                pulseMobileToggle()
            end
        end

        if moveTween then
            moveTween.Completed:Connect(finishHide)
        else
            task.delay(0.21, finishHide)
        end
    end

    if source then
        appendLog(
            "UI_TOGGLE",
            string.format(
                "visible=%s source=%s",
                tostring(Runtime.GUIVisible),
                tostring(source)
            )
        )
    end
end

local function toggleHubVisibility(source)
    setHubVisible(not Runtime.GUIVisible, source or "toggle")
end

local function createUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local cleanupRoots = {playerGui}
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and typeof(hui) == "Instance" and hui ~= playerGui then
            table.insert(cleanupRoots, hui)
        end
    end

    for _, root in ipairs(cleanupRoots) do
        pcall(function()
            for _, child in ipairs(root:GetChildren()) do
                if child.Name == "SliceHub_PS99" then
                    child:Destroy()
                end
            end
        end)
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = "SliceHub_PS99"
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 999999
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen:SetAttribute("SliceHubBuild", HUB_VERSION)
    screen:SetAttribute("SliceHubMarker", MOTION_BUILD_MARKER)

    local parent = playerGui
    if type(gethui) == "function" then
        local okHui, hui = pcall(gethui)
        if okHui and typeof(hui) == "Instance" then
            parent = hui
        end
    end

    local okParent = pcall(function()
        screen.Parent = parent
    end)
    if not okParent and parent ~= playerGui then
        screen.Parent = playerGui
    end

    local defaultWidth = UserInputService.TouchEnabled and 700 or 800
    local defaultHeight = 520
    local baseWidth = math.floor(
        clamp(
            tonumber(Config.settings.windowWidth) or defaultWidth,
            610,
            1180
        )
    )
    local baseHeight = math.floor(
        clamp(
            tonumber(Config.settings.windowHeight) or defaultHeight,
            400,
            800
        )
    )

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.fromScale(
        clamp(tonumber(Config.settings.windowPositionX) or 0.5, 0.05, 0.95),
        clamp(tonumber(Config.settings.windowPositionY) or 0.5, 0.05, 0.95)
    )
    main.Size = UDim2.fromOffset(baseWidth, baseHeight)
    main.BackgroundColor3 = COLORS.Background
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = screen
    makeCorner(main, 14)
    makeStroke(main, 0.05)
    Theme.MakeGradient(main, "Background", "Panel", 35)

    local candyGlow = Instance.new("UIStroke")
    candyGlow.Name = "CandyGlow"
    candyGlow.Color = COLORS.Glow
    candyGlow.Transparency = 0.58
    candyGlow.Thickness = 2
    candyGlow.Parent = main

    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = main

    local function updateScale()
        local camera = Workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
        local horizontalMargin = UserInputService.TouchEnabled and 18 or 30
        local verticalMargin = UserInputService.TouchEnabled and 28 or 42
        local widthScale = math.max(0.1, (viewport.X - horizontalMargin) / baseWidth)
        local heightScale = math.max(0.1, (viewport.Y - verticalMargin) / baseHeight)
        local target = clamp(math.min(widthScale, heightScale), 0.35, 1)

        if Config.settings.compactUI then
            target = math.min(target, 0.9)
        end

        Runtime.UITargetScale = target

        if not Runtime.UIAnimating then
            scale.Scale = target

            local halfWidth = (baseWidth * target) / 2
            local halfHeight = (baseHeight * target) / 2
            local centerX = clamp(
                main.Position.X.Scale * viewport.X + main.Position.X.Offset,
                halfWidth + 8,
                math.max(halfWidth + 8, viewport.X - halfWidth - 8)
            )
            local centerY = clamp(
                main.Position.Y.Scale * viewport.Y + main.Position.Y.Offset,
                halfHeight + 8,
                math.max(halfHeight + 8, viewport.Y - halfHeight - 8)
            )

            main.Position = UDim2.fromScale(
                viewport.X > 0 and centerX / viewport.X or 0.5,
                viewport.Y > 0 and centerY / viewport.Y or 0.5
            )
            Runtime.UIRestPosition = main.Position
        end
    end

    UI.MainScale = scale
    updateScale()

    if Workspace.CurrentCamera then
        table.insert(
            Runtime.Connections,
            Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
        )
    end

    local top = Instance.new("Frame")
    top.Size = UDim2.new(1, 0, 0, 48)
    top.BackgroundColor3 = COLORS.Sidebar
    top.BorderSizePixel = 0
    top.Parent = main
    makeCorner(top, 14)
    Theme.MakeGradient(top, "CandyA", "CandyB", 8)

    local resolvedSliceLogoAsset = nil
    local resolvedSliceLogoFrames = nil
    local sliceLogoAttempted = false

    local function resolveSliceLogoAsset()
        if sliceLogoAttempted then
            return resolvedSliceLogoAsset
        end
        sliceLogoAttempted = true

        local assetLoader = rawget(env, "getcustomasset")
            or rawget(env, "getsynasset")
            or getcustomasset
            or getsynasset

        if type(assetLoader) ~= "function" or not canWrite then
            appendLog("LOGO", "Custom assets unavailable; using built-in fallback.")
            return nil
        end

        ensureFolder(ROOT .. "/cache")
        ensureFolder(ROOT .. "/cache/PS99")

        local encodedFrames = {
            [[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]],
            [[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]],
            [[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]],
            [[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]],
            [[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]],
            [[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]],
            [[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]],
            [[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]],
        }

        local function decodeBase64(encoded)
            local cryptTable = rawget(env, "crypt")
            local synTable = rawget(env, "syn")
            local decoders = {
                type(cryptTable) == "table" and cryptTable.base64decode,
                type(cryptTable) == "table"
                    and type(cryptTable.base64) == "table"
                    and cryptTable.base64.decode,
                type(synTable) == "table"
                    and type(synTable.crypt) == "table"
                    and type(synTable.crypt.base64) == "table"
                    and synTable.crypt.base64.decode,
                rawget(env, "base64_decode"),
            }

            for _, decoder in pairs(decoders) do
                if type(decoder) == "function" then
                    local okDecode, decoded = pcall(decoder, encoded)
                    if okDecode and type(decoded) == "string" and #decoded > 32 then
                        return decoded
                    end
                end
            end

            local alphabet =
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            encoded = string.gsub(encoded, "[^" .. alphabet .. "=]", "")

            local bits = encoded:gsub(".", function(character)
                if character == "=" then
                    return ""
                end

                local index = string.find(alphabet, character, 1, true)
                if not index then
                    return ""
                end

                local value = index - 1
                local output = ""

                for bit = 6, 1, -1 do
                    output = output
                        .. (
                            value % 2 ^ bit
                            - value % 2 ^ (bit - 1)
                            > 0
                            and "1"
                            or "0"
                        )
                end

                return output
            end)

            return bits:gsub("%d%d%d?%d?%d?%d?%d?%d?", function(byte)
                if #byte ~= 8 then
                    return ""
                end

                local value = 0
                for bit = 1, 8 do
                    if string.sub(byte, bit, bit) == "1" then
                        value = value + 2 ^ (8 - bit)
                    end
                end
                return string.char(value)
            end)
        end

        local assets = {}

        for index, encoded in ipairs(encodedFrames) do
            local path = string.format(
                "%s/cache/PS99/slicehub_logo_frame_%02d.png",
                ROOT,
                index
            )
            local exists = false

            if type(isfile) == "function" then
                local okExists, result = pcall(isfile, path)
                exists = okExists and result == true
            end

            if not exists then
                local decoded = decodeBase64(encoded)
                if type(decoded) == "string" and #decoded > 32 then
                    pcall(writefile, path, decoded)
                end
            end

            local okAsset, asset = pcall(assetLoader, path)
            if okAsset and type(asset) == "string" and asset ~= "" then
                table.insert(assets, asset)
            end
        end

        if #assets > 0 then
            resolvedSliceLogoFrames = assets
            resolvedSliceLogoAsset = assets[1]
            appendLog(
                "LOGO",
                "Loaded "
                    .. tostring(#assets)
                    .. " exact MP4 logo frames."
            )
            return resolvedSliceLogoAsset
        end

        appendLog("LOGO", "Embedded logo unavailable; using built-in fallback.")
        return nil
    end

    local function addCandyGem(parentObject, pixelSize)
        local holder = Instance.new("Frame")
        holder.Name = "SliceHubLogo"
        holder.AnchorPoint = Vector2.new(0.5, 0.5)
        holder.Position = UDim2.fromScale(0.5, 0.5)
        holder.Size = UDim2.fromOffset(pixelSize, pixelSize)
        holder.BackgroundTransparency = 1
        holder.ClipsDescendants = true
        holder.Parent = parentObject
        makeCorner(holder, math.max(8, math.floor(pixelSize * 0.26)))

        local logoAsset = resolveSliceLogoAsset()
        if logoAsset then
            local image = Instance.new("ImageLabel")
            image.Name = "ServerLogo"
            image.AnchorPoint = Vector2.new(0.5, 0.5)
            image.Position = UDim2.fromScale(0.5, 0.5)
            image.Size = UDim2.fromScale(0.94, 0.94)
            image.BackgroundTransparency = 1
            image.Image = logoAsset
            image.ScaleType = Enum.ScaleType.Fit
            image.ZIndex = parentObject.ZIndex + 2
            image.Parent = holder

            if resolvedSliceLogoFrames
                and #resolvedSliceLogoFrames > 1
            then
                task.spawn(function()
                    local frameIndex = 1

                    while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation and image.Parent do
                        frameIndex =
                            (frameIndex % #resolvedSliceLogoFrames) + 1
                        image.Image =
                            resolvedSliceLogoFrames[frameIndex]
                        task.wait(0.095)
                    end
                end)
            end

            local logoScale = Instance.new("UIScale")
            logoScale.Scale = 1
            logoScale.Parent = image

            task.spawn(function()
                while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation and image.Parent do
                    local grow = tween(
                        logoScale,
                        1.15,
                        Enum.EasingStyle.Sine,
                        Enum.EasingDirection.InOut,
                        {Scale = 1.055}
                    )
                    if grow then grow.Completed:Wait() else task.wait(1.15) end
                    if not Runtime.Alive or not image.Parent then break end
                    local shrink = tween(
                        logoScale,
                        1.15,
                        Enum.EasingStyle.Sine,
                        Enum.EasingDirection.InOut,
                        {Scale = 1}
                    )
                    if shrink then shrink.Completed:Wait() else task.wait(1.15) end
                end
            end)

            return holder
        end

        local gem = Instance.new("Frame")
        gem.AnchorPoint = Vector2.new(0.5, 0.5)
        gem.Position = UDim2.fromScale(0.5, 0.5)
        gem.Size = UDim2.fromScale(0.62, 0.62)
        gem.Rotation = 45
        gem.BackgroundColor3 = COLORS.CandyA
        gem.BorderSizePixel = 0
        gem.Parent = holder
        makeCorner(gem, math.max(4, math.floor(pixelSize * 0.12)))
        makeStroke(gem, 0.18)
        Theme.MakeGradient(gem, "CandyA", "CandyB", 45)

        local center = Instance.new("Frame")
        center.AnchorPoint = Vector2.new(0.5, 0.5)
        center.Position = UDim2.fromScale(0.5, 0.5)
        center.Size = UDim2.fromScale(0.38, 0.38)
        center.BackgroundColor3 = COLORS.Glow
        center.BackgroundTransparency = 0.16
        center.BorderSizePixel = 0
        center.Parent = holder
        makeCorner(center, math.max(4, math.floor(pixelSize * 0.18)))

        local shine = Instance.new("Frame")
        shine.AnchorPoint = Vector2.new(0.5, 0.5)
        shine.Position = UDim2.fromScale(0.38, 0.34)
        shine.Size = UDim2.fromScale(0.18, 0.10)
        shine.Rotation = -18
        shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        shine.BackgroundTransparency = 0.16
        shine.BorderSizePixel = 0
        shine.Parent = holder
        makeCorner(shine, 8)

        return holder
    end

    local topLogo = Instance.new("Frame")
    topLogo.BackgroundTransparency = 1
    topLogo.Position = UDim2.fromOffset(10, 6)
    topLogo.Size = UDim2.fromOffset(36, 36)
    topLogo.Parent = top
    addCandyGem(topLogo, 34)


    makeLabel(
        top,
        "SliceHub PS99",
        UDim2.fromOffset(50, 0),
        UDim2.fromOffset(160, 48),
        {
            font = Enum.Font.GothamBold,
            textSize = 16,
        }
    )


    local tierLabel = makeLabel(
        top,
        USER_TIER,
        UDim2.new(1, -160, 0, 10),
        UDim2.fromOffset(92, 28),
        {
            backgroundTransparency = 0,
            backgroundColor = IS_PREMIUM and COLORS.Premium or COLORS.Input,
            xAlignment = Enum.TextXAlignment.Center,
            font = Enum.Font.GothamBold,
            textSize = 11,
            corner = 7,
        }
    )

    local closeButton = makeButton(
        top,
        "X",
        UDim2.new(1, -46, 0, 9),
        UDim2.fromOffset(34, 30),
        {
            backgroundColor = COLORS.Error,
        }
    )

    local mobileToggleButton = makeButton(
        screen,
        "",
        UDim2.fromScale(
            clamp(tonumber(Config.settings.togglePositionX) or 0.92, 0.05, 0.95),
            clamp(tonumber(Config.settings.togglePositionY) or 0.5, 0.05, 0.95)
        ),
        UDim2.fromOffset(58, 58),
        {
            backgroundColor = COLORS.AccentDark,
            corner = 29,
            stroke = true,
            strokeTransparency = 0.02,
            autoButtonColor = false,
        }
    )
    mobileToggleButton.Name = "MobileToggle"
    mobileToggleButton.AnchorPoint = Vector2.new(0.5, 0.5)
    Theme.MakeGradient(mobileToggleButton, "CandyA", "CandyB", 35)
    addCandyGem(mobileToggleButton, 42)
    mobileToggleButton.ZIndex = 100
    mobileToggleButton.Visible = false

    local mobileToggleScale = mobileToggleButton:FindFirstChild("MotionScale")
    if not mobileToggleScale then
        mobileToggleScale = Instance.new("UIScale")
        mobileToggleScale.Name = "MotionScale"
        mobileToggleScale.Parent = mobileToggleButton
    end
    mobileToggleScale.Scale = 1

    local sidebar = Instance.new("Frame")
    sidebar.Position = UDim2.fromOffset(0, 48)
    sidebar.Size = UDim2.new(0, 138, 1, -48)
    sidebar.BackgroundColor3 = COLORS.Sidebar
    sidebar.BorderSizePixel = 0
    sidebar.Parent = main
    Theme.MakeGradient(sidebar, "Sidebar", "Background", 90)

    local tabHolder = Instance.new("ScrollingFrame")
    tabHolder.Name = "TabScroller"
    tabHolder.BackgroundTransparency = 1
    tabHolder.BorderSizePixel = 0
    tabHolder.Position = UDim2.fromOffset(8, 8)
    tabHolder.Size = UDim2.new(1, -16, 1, -72)
    tabHolder.CanvasSize = UDim2.new()
    tabHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
    tabHolder.ScrollBarThickness = 0
    tabHolder.ScrollingDirection = Enum.ScrollingDirection.Y
    tabHolder.Parent = sidebar

    local tabLayout = makeVerticalLayout(tabHolder, 5)

    local sidebarFooter = makeLabel(
        sidebar,
        "",
        UDim2.new(0, 8, 1, -58),
        UDim2.new(1, -16, 0, 48),
        {
            textColor = COLORS.Muted,
            textSize = 10,
            wrapped = true,
            yAlignment = Enum.TextYAlignment.Bottom,
        }
    )

    local content = Instance.new("Frame")
    content.Position = UDim2.fromOffset(138, 48)
    content.Size = UDim2.new(1, -138, 1, -92)
    content.BackgroundTransparency = 1
    content.ClipsDescendants = true
    content.Parent = main

    local bottom = Instance.new("Frame")
    bottom.Position = UDim2.new(0, 138, 1, -44)
    bottom.Size = UDim2.new(1, -138, 0, 44)
    bottom.BackgroundColor3 = COLORS.Sidebar
    bottom.BorderSizePixel = 0
    bottom.Parent = main
    Theme.MakeGradient(bottom, "Sidebar", "Panel", 0)

    local noticeLabel = makeLabel(
        bottom,
        "Ready.",
        UDim2.fromOffset(14, 0),
        UDim2.new(1, -40, 1, 0),
        {
            textColor = COLORS.Muted,
            textSize = 11,
            wrapped = true,
        }
    )

    local resizeHandle = Instance.new("TextButton")
    resizeHandle.Name = "ResizeHandle"
    resizeHandle.AnchorPoint = Vector2.new(1, 1)
    resizeHandle.Position = UDim2.new(1, -4, 1, -4)
    resizeHandle.Size = UDim2.fromOffset(26, 26)
    resizeHandle.BackgroundColor3 = COLORS.Panel2
    resizeHandle.BackgroundTransparency = 0.08
    resizeHandle.BorderSizePixel = 0
    resizeHandle.AutoButtonColor = false
    resizeHandle.Text = "↘"
    resizeHandle.TextColor3 = COLORS.Muted
    resizeHandle.TextSize = 16
    resizeHandle.Font = Enum.Font.GothamBold
    resizeHandle.ZIndex = 90
    resizeHandle.Parent = main
    makeCorner(resizeHandle, 7)
    makeStroke(resizeHandle, 0.35)

    UI.Screen = screen
    UI.Main = main
    UI.MainScale = scale
    UI.ToggleButton = mobileToggleButton
    UI.ToggleScale = mobileToggleScale
    UI.NoticeLabel = noticeLabel
    UI.TierLabel = tierLabel
    UI.ResizeHandle = resizeHandle

    for _, name in ipairs(TAB_NAMES) do
        local button = makeButton(
            tabHolder,
            UI.TabLabels[name] or name,
            UDim2.new(),
            UDim2.new(1, 0, 0, 35),
            {
                backgroundColor = COLORS.Sidebar,
                textColor = COLORS.Muted,
                textSize = 11,
            }
        )
        button.LayoutOrder = table.find(TAB_NAMES, name) or 0

        UI.TabButtons[name] = button
        button.Activated:Connect(function()
            showTab(name)
        end)

        local page = makePage(content, name)
        UI.Pages[name] = page
    end

    buildHomePage(UI.Pages.Home)

    CoreAutomation.buildFarmPage(UI.Pages.Farm)

    CoreAutomation.buildNormalEggsPage(UI.Pages.Eggs)
    CoreAutomation.buildInfiniteEggsPage(UI.Pages.InfiniteEggs)

    CoreAutomation.buildAutomaticPage(UI.Pages.Automatic)

    CoreAutomation.buildRewardsPage(UI.Pages.Rewards)
    CoreAutomation.buildUtilitiesPage(UI.Pages.Utilities)

    if UI.Pages.Pets then
        buildPlaceholderPage(UI.Pages.Pets, "Pets", "Coming later.", "")
    end

    if UI.Pages.Upgrades then
        buildPlaceholderPage(UI.Pages.Upgrades, "Upgrades", "Coming later.", "")
    end

    buildEventPage(UI.Pages.Event)

    if UI.Pages.Webhooks then
        buildPlaceholderPage(UI.Pages.Webhooks, "Webhooks", "Coming later.", "")
    end

    buildSettingsPage(UI.Pages.Settings)

    closeButton.Activated:Connect(function()
        setHubVisible(false, "close button")
    end)

    local toggleDragging = false
    local toggleDragInput = nil
    local toggleDragStart = nil
    local toggleStartPosition = nil
    local toggleMoved = false

    mobileToggleButton.Activated:Connect(function()
        if toggleMoved then
            toggleMoved = false
            return
        end
        setHubVisible(true, "candy logo")
    end)

    mobileToggleButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            toggleDragging = true
            toggleMoved = false
            toggleDragStart = input.Position
            toggleStartPosition = mobileToggleButton.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    toggleDragging = false
                    toggleDragInput = nil

                    Config.settings.togglePositionX = mobileToggleButton.Position.X.Scale
                    Config.settings.togglePositionY = mobileToggleButton.Position.Y.Scale
                    markConfigDirty()
                end
            end)
        end
    end)

    mobileToggleButton.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            toggleDragInput = input
        end
    end)

    table.insert(
        Runtime.Connections,
        UserInputService.InputChanged:Connect(function(input)
            if not toggleDragging
                or input ~= toggleDragInput
                or not toggleDragStart
                or not toggleStartPosition
            then
                return
            end

            local camera = Workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
            local delta = input.Position - toggleDragStart
            local startX = toggleStartPosition.X.Scale * viewport.X + toggleStartPosition.X.Offset
            local startY = toggleStartPosition.Y.Scale * viewport.Y + toggleStartPosition.Y.Offset
            local x = clamp(startX + delta.X, 36, math.max(36, viewport.X - 36))
            local y = clamp(startY + delta.Y, 36, math.max(36, viewport.Y - 36))

            if delta.Magnitude > 5 then
                toggleMoved = true
            end

            mobileToggleButton.Position = UDim2.fromScale(
                viewport.X > 0 and x / viewport.X or 0.92,
                viewport.Y > 0 and y / viewport.Y or 0.5
            )
        end)
    )

    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil

    top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart = input.Position
            startPosition = main.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    dragInput = nil

                    Config.settings.windowPositionX = main.Position.X.Scale
                    Config.settings.windowPositionY = main.Position.Y.Scale
                    markConfigDirty()
                    Runtime.UIRestPosition = main.Position
                end
            end)
        end
    end)

    top.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragInput = input
        end
    end)

    table.insert(
        Runtime.Connections,
        UserInputService.InputChanged:Connect(function(input)
            if dragging and input == dragInput and dragStart and startPosition then
                local camera = Workspace.CurrentCamera
                local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
                local delta = input.Position - dragStart
                local halfWidth = (baseWidth * math.max(0.05, scale.Scale)) / 2
                local halfHeight = (baseHeight * math.max(0.05, scale.Scale)) / 2
                local startX = startPosition.X.Scale * viewport.X + startPosition.X.Offset
                local startY = startPosition.Y.Scale * viewport.Y + startPosition.Y.Offset
                local centerX = clamp(
                    startX + delta.X,
                    halfWidth + 8,
                    math.max(halfWidth + 8, viewport.X - halfWidth - 8)
                )
                local centerY = clamp(
                    startY + delta.Y,
                    halfHeight + 8,
                    math.max(halfHeight + 8, viewport.Y - halfHeight - 8)
                )

                main.Position = UDim2.fromScale(
                    viewport.X > 0 and centerX / viewport.X or 0.5,
                    viewport.Y > 0 and centerY / viewport.Y or 0.5
                )
                Runtime.UIRestPosition = main.Position
            end
        end)
    )

    local resizing = false
    local resizeInput = nil
    local resizeStart = nil
    local resizeStartWidth = nil
    local resizeStartHeight = nil

    resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            resizing = true
            resizeInput = input
            resizeStart = input.Position
            resizeStartWidth = baseWidth
            resizeStartHeight = baseHeight

            tween(
                resizeHandle,
                0.12,
                Enum.EasingStyle.Quint,
                Enum.EasingDirection.Out,
                {
                    BackgroundColor3 = COLORS.AccentDark,
                    TextColor3 = COLORS.Text,
                }
            )

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    resizing = false
                    resizeInput = nil

                    Config.settings.windowWidth = math.floor(baseWidth)
                    Config.settings.windowHeight = math.floor(baseHeight)
                    markConfigDirty()

                    tween(
                        resizeHandle,
                        0.16,
                        Enum.EasingStyle.Quint,
                        Enum.EasingDirection.Out,
                        {
                            BackgroundColor3 = COLORS.Panel2,
                            TextColor3 = COLORS.Muted,
                        }
                    )

                    setNotice(
                        string.format(
                            "Window size saved: %d × %d",
                            baseWidth,
                            baseHeight
                        ),
                        "info"
                    )
                end
            end)
        end
    end)

    resizeHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            resizeInput = input
        end
    end)

    table.insert(
        Runtime.Connections,
        UserInputService.InputChanged:Connect(function(input)
            if not resizing
                or input ~= resizeInput
                or not resizeStart
                or not resizeStartWidth
                or not resizeStartHeight
            then
                return
            end

            local effectiveScale = math.max(0.05, scale.Scale)
            local delta = (input.Position - resizeStart) / effectiveScale

            baseWidth = math.floor(
                clamp(resizeStartWidth + delta.X, 610, 1180)
            )
            baseHeight = math.floor(
                clamp(resizeStartHeight + delta.Y, 400, 800)
            )

            main.Size = UDim2.fromOffset(baseWidth, baseHeight)
            Runtime.UIRestPosition = main.Position
            updateScale()
        end)
    )

    table.insert(
        Runtime.Connections,
        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed or UserInputService:GetFocusedTextBox() then
                return
            end

            if input.KeyCode == Enum.KeyCode.RightShift then
                toggleHubVisibility("RightShift")
            end
        end)
    )

    if not UI.Pages[Runtime.SelectedTab] then
        Runtime.SelectedTab = "Home"
    end

    showTab(Runtime.SelectedTab)

    Runtime.UIRestPosition = main.Position
    main.Visible = false
    setHubVisible(true, "initial open")

    refreshEventUI()
end

Runtime.UIBootOK, Runtime.UIBootError = xpcall(
    createUI,
    function(errorMessage)
        return debug.traceback(tostring(errorMessage), 2)
    end
)

if not Runtime.UIBootOK then
    warn("[SliceHub PS99] UI BOOT FAILED\n" .. tostring(Runtime.UIBootError))
    appendLog("UI_BOOT_FAIL", tostring(Runtime.UIBootError))

    if canWrite then
        pcall(
            writefile,
            LOG_FOLDER .. "/BOOT_ERROR.txt",
            tostring(Runtime.UIBootError)
        )
    end

    return
end

pcall(function()
    if typeof(env.SliceHubPS99BootScreen) == "Instance" then
        env.SliceHubPS99BootScreen:Destroy()
    end
    env.SliceHubPS99BootScreen = nil
end)

--////////////////////////////////////////////////////////////////////
-- Event detection and refresh workers
--////////////////////////////////////////////////////////////////////

local function connectEggEvent(eventObject, label)
    if not eventObject or type(eventObject.Connect) ~= "function" then
        return
    end

    local ok, connection = pcall(function()
        return eventObject:Connect(function()
            task.delay(0.15, function()
                if Runtime.Alive and EggEngine.Alive then
                    refreshEggs(label)
                    safeEventCall("Detect")
                    refreshEventUI()
                end
            end)
        end)
    end)

    if ok and connection then
        table.insert(EggEngine.Connections, connection)
    end
end

connectEggEvent(CustomEggsCmds.Created, "egg created")
connectEggEvent(CustomEggsCmds.Updated, "egg updated")
connectEggEvent(CustomEggsCmds.Destroyed, "egg destroyed")

safeEventCall("Detect")
refreshEventUI()
CoreAutomation.refreshConsumables(true)
CoreAutomation.detectRankRewardIndexes()
CoreAutomation.detectTimedFreeGiftIndexes()
if CoreAutomation.refreshFarmUI then CoreAutomation.refreshFarmUI() end
if CoreAutomation.refreshNormalEggUI then CoreAutomation.refreshNormalEggUI() end
if CoreAutomation.refreshAutomaticUI then CoreAutomation.refreshAutomaticUI() end
if CoreAutomation.refreshRankUI then CoreAutomation.refreshRankUI() end

task.spawn(function()
    while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation and EggEngine.Alive do
        task.wait(EGG_REFRESH_INTERVAL)

        local ok, fault = pcall(function()
            refreshEggs(nil)
            safeEventCall("Detect")
            refreshEventUI()
        end)

        if not ok then
            Runtime.EventFault = tostring(fault)
            appendLog("EVENT_REFRESH_FAULT", fault)
            refreshEventUI()
        end
    end
end)

task.spawn(function()
    while Runtime.Alive and Runtime.Generation == env.SliceHubPS99Generation do
        task.wait(AUTOSAVE_INTERVAL)
        saveConfig(false)
    end
end)

--////////////////////////////////////////////////////////////////////
-- Public API and unload
--////////////////////////////////////////////////////////////////////

local API = {}

function API.GetState()
    return {
        version = HUB_VERSION,
        tier = USER_TIER,
        selectedTab = Runtime.SelectedTab,
        eventFault = Runtime.EventFault,
        event = CurrentEventModule:GetProgress(),
        selectedEgg = selectedEgg(),
        gardenStatus = getGardenStatus(),
        gardenMerchant = {
            enabled = GardenAutomation.AutoMerchant,
            slot = GardenAutomation.MerchantSlot,
            lastReason = GardenAutomation.MerchantLastReason,
            stats = GardenAutomation.Stats,
        },
        gardenReinforce = {
            enabled = GardenAutomation.AutoReinforce,
            lastTowerID = GardenAutomation.ReinforceLastTowerID,
            lastTowerName = GardenAutomation.ReinforceLastTowerName,
            lastLevel = GardenAutomation.ReinforceLastLevel,
            lastReason = GardenAutomation.ReinforceLastReason,
            stats = GardenAutomation.Stats,
        },
        farm = CoreAutomation.FarmEngine,
        normalEggs = CoreAutomation.NormalEggEngine,
        machines = CoreAutomation.Machines,
        infiniteEggs = CoreAutomation.InfiniteEggEngine,
        automatic = CoreAutomation.AutomaticEngine,
        bestArea = CoreAutomation.BestAreaEngine,
        rankRewards = CoreAutomation.RankEngine,
        timedFreeGifts =
            CoreAutomation.FreeGiftEngine,
    }
end

function API.ShowTab(name)
    showTab(name)
end

function API.SetVisible(visible)
    setHubVisible(visible == true, "API")
end

function API.ToggleUI()
    toggleHubVisibility("API")
end

function API.IsVisible()
    return Runtime.GUIVisible
end

function API.TeleportToWorld(worldNumber)
    worldNumber = tonumber(worldNumber)

    for _, world in ipairs(getWorldEntries()) do
        if world.WorldNumber == worldNumber then
            teleportToPlace(world.PlaceId, world.Name)
            return true
        end
    end

    setNotice("World " .. tostring(worldNumber) .. " is unavailable.", "error")
    return false
end

function API.TeleportToTradingPlaza(pro)
    teleportToTradingPlaza(pro == true)
end

function API.SetWindowSize(width, height)
    if not UI.Main or not UI.Main.Parent then
        return false
    end

    local newWidth = math.floor(clamp(tonumber(width) or 800, 610, 1180))
    local newHeight = math.floor(clamp(tonumber(height) or 520, 400, 800))

    UI.Main.Size = UDim2.fromOffset(newWidth, newHeight)
    Config.settings.windowWidth = newWidth
    Config.settings.windowHeight = newHeight
    markConfigDirty()

    setNotice(
        string.format("Window resized to %d × %d.", newWidth, newHeight),
        "info"
    )
    return true
end

function API.StartFarm()
    CoreAutomation.setFarmFeature("AutoFarm", true)
end

function API.StopFarm(reason)
    CoreAutomation.stopFarmEngine(
        reason or "Stopped through API",
        true
    )
end

function API.SetFarmFeature(featureName, enabled)
    return CoreAutomation.setFarmFeature(
        featureName,
        enabled == true
    )
end

function API.TeleportToBestArea()
    return CoreAutomation.teleportToBestArea(false)
end

function API.SetAutoBestArea(enabled)
    CoreAutomation.setAutoBestArea(
        enabled == true
    )
end

function API.StartNormalEggs()
    CoreAutomation.startNormalEggs()
end

function API.StopNormalEggs(reason)
    CoreAutomation.stopNormalEggs(reason or "Stopped through API")
end

function API.MakeGoldPet()
    return CoreAutomation.runPetMachine("Gold", true)
end

function API.MakeRainbowPet()
    return CoreAutomation.runPetMachine("Rainbow", true)
end

function API.SetAutoGoldPet(enabled)
    return CoreAutomation.setPetMachineAuto("Gold", enabled == true)
end

function API.SetAutoRainbowPet(enabled)
    return CoreAutomation.setPetMachineAuto("Rainbow", enabled == true)
end

function API.HatchInfiniteEgg()
    return CoreAutomation.runInfiniteHatch(true)
end

function API.SetAutoInfiniteEgg(enabled)
    if enabled and not requirePremium("Auto Open Infinite Egg") then return false end
    CoreAutomation.InfiniteEggEngine.AutoOpen = enabled == true
    CoreAutomation.InfiniteEggEngine.NextHatchAt = 0
    Config.infiniteEggs.autoOpen = CoreAutomation.InfiniteEggEngine.AutoOpen
    markConfigDirty()
    if CoreAutomation.refreshInfiniteEggUI then CoreAutomation.refreshInfiniteEggUI(false) end
end

function API.SetAutoDisableIndexedEggs(enabled)
    if enabled and not requirePremium("Auto Turn Off Indexed Eggs") then return false end
    local engine = CoreAutomation.InfiniteEggEngine
    engine.AutoDisableIndexed = enabled == true
    engine.NextIndexAt = 0
    engine.NextIndexRefreshAt = 0
    Config.infiniteEggs.autoDisableIndexed = engine.AutoDisableIndexed
    markConfigDirty()
    if engine.AutoDisableIndexed then
        task.spawn(function()
            CoreAutomation.refreshInfiniteIndexCounts(true)
            CoreAutomation.disableIndexedInfiniteEggs(false, true)
        end)
    end
    if CoreAutomation.refreshInfiniteEggUI then CoreAutomation.refreshInfiniteEggUI(false) end
end

function API.ClaimRankRewards()
    return CoreAutomation.claimDetectedRankRewards()
end

function API.ClaimTimedFreeGifts()
    return CoreAutomation.claimTimedFreeGifts(true)
end

function API.SetAutoTimedFreeGifts(enabled)
    CoreAutomation.FreeGiftEngine.AutoClaim =
        enabled == true
    Config.main.autoFreeGifts =
        CoreAutomation.FreeGiftEngine.AutoClaim
    CoreAutomation.FreeGiftEngine.NextScanAt = 0
    markConfigDirty()

    if CoreAutomation.refreshFreeGiftUI then
        CoreAutomation.refreshFreeGiftUI()
    end
end

function API.RefreshNormalEggs()
    return CoreAutomation.refreshNormalEggs(true)
end

function API.StopGardenAutomation(preserveSettings)
    GardenAutomation.Suspended = true

    if GardenLineTools.Available then
        if type(GardenLineTools.SetAutoFill) == "function" then
            pcall(GardenLineTools.SetAutoFill, GardenLineTools, false)
        end
        if type(GardenLineTools.StopCleaning) == "function" then
            pcall(GardenLineTools.StopCleaning, GardenLineTools)
        end
    end

    if preserveSettings ~= true then
        GardenAutomation.AutoCollect = false
        GardenAutomation.AutoPlant = false
        GardenAutomation.AutoUnlockLanes = false
        GardenAutomation.AutoBuyPlots = false
        GardenAutomation.AutoUpgrades = false
        GardenAutomation.AutoRegrow = false
        GardenAutomation.AutoRestoreUnits = false
        GardenAutomation.AutoMerchant = false
        GardenAutomation.AutoReinforce = false
        GardenAutomation.FullCampaign = false
        GardenAutomation.MissionDirector = false
        GardenAutomation.AutoSuperRebirth = false
        GardenAutomation.AutoCraftSelected = false
        GardenAutomation.AutoMaxLuck = false
        GardenAutomation:ClearMissionOverrides()
    end

    if refreshEventUI then
        refreshEventUI()
    end
end

function API.ResumeGardenAutomation()
    GardenAutomation.Suspended = false
    if refreshEventUI then
        refreshEventUI()
    end
end

function API.GetGardenLineTools()
    return GardenLineTools
end

function API.FillGardenLine()
    if not GardenLineTools.Available then
        return false, GardenLineTools.Error
    end
    return GardenLineTools:FillLine()
end

function API.CleanGardenLine(lineNumber)
    if not GardenLineTools.Available then
        return false, GardenLineTools.Error
    end
    return GardenLineTools:CleanLine(lineNumber)
end

function API.SetAutoFillGardenLines(enabled)
    if not GardenLineTools.Available then
        return false, GardenLineTools.Error
    end
    return GardenLineTools:SetAutoFill(enabled == true)
end

function API.CleanAllGardenLines()
    if not GardenLineTools.Available then
        return false, GardenLineTools.Error
    end
    return GardenLineTools:CleanAllLines()
end

function API.StopCleaningGardenLines()
    if not GardenLineTools.Available
        or type(GardenLineTools.StopCleaning) ~= "function"
    then
        return false, GardenLineTools.Error or "Line tools unavailable"
    end
    return GardenLineTools:StopCleaning()
end

function API.RecordGardenUnitLayout()
    return recordCurrentUnitLayout()
end

function API.RestoreGardenUnit()
    return runGardenAction("Restore unit", restoreOneUnit)
end

function API.SetGardenFeature(name, enabled)
    return setGardenFeature(name, enabled)
end

function API.SetAutoGardenReinforce(enabled)
    GardenAutomation.Next.Reinforce = 0
    return setGardenFeature(
        "AutoReinforce",
        enabled == true
    )
end

function API.ReinforceGardenUnitStep()
    if GardenAutomation.Busy or GardenAutomation.Suspended then
        return false, "Garden automation is busy"
    end

    GardenAutomation.Busy = true

    local ok,
        success,
        detail,
        nextDelay = xpcall(
            function()
                return GardenAutomation:ReinforceOneUnit()
            end,
            debug.traceback
        )

    GardenAutomation.Busy = false
    GardenAutomation.Next.Reinforce =
        os.clock()
        + math.max(
            0.3,
            tonumber(nextDelay)
                or GardenAutomation.ReinforceUnavailableDelay
        )

    if not ok then
        return false, tostring(success)
    end

    if refreshEventUI then
        refreshEventUI()
    end

    return success, detail
end

function API.SetAutoGardenMerchant(enabled)
    GardenAutomation.Next.Merchant = 0
    return setGardenFeature(
        "AutoMerchant",
        enabled == true
    )
end

function API.BuyGardenMerchantStep()
    if GardenAutomation.Busy
        or GardenAutomation.Suspended
    then
        return false, "Garden automation is busy"
    end

    GardenAutomation.Busy = true

    local ok,
        success,
        detail,
        nextDelay = xpcall(
            function()
                return GardenAutomation:BuyMerchantStep()
            end,
            debug.traceback
        )

    GardenAutomation.Busy = false
    GardenAutomation.Next.Merchant =
        os.clock()
        + math.max(
            0.2,
            tonumber(nextDelay) or 1
        )

    if not ok then
        return false, tostring(success)
    end

    if refreshEventUI then
        refreshEventUI()
    end

    return success, detail
end



function API.SetAutoEventCraft(enabled)
    return GardenAutomation:SetCraftAuto(enabled == true)
end

function API.CraftSelectedEventPet()
    return runGardenAction(
        "Event craft",
        function()
            return GardenAutomation:CraftSelectedStep()
        end
    )
end

function API.SetAutoEventLuck(enabled)
    return GardenAutomation:SetLuckAuto(enabled == true)
end

function API.MaxSelectedEventLuck()
    return runGardenAction(
        "Event Luck",
        function()
            return GardenAutomation:MaxSelectedLuckStep(true)
        end
    )
end

function API.StartEventEggs()
    return safeEventCall("StartFeature", "CustomEggs")
end

function API.StopEventEggs()
    return safeEventCall("StopFeature", "CustomEggs")
end

function API.RefreshEvent()
    return safeEventCall("Detect")
end

function API.SaveConfig()
    return saveConfig(true)
end

function API.Unload(reason)
    -- Idempotent cleanup: even a second call removes any surviving UI/state.
    Runtime.Alive = false
    CoreAutomation.FarmEngine.Alive = false
    CoreAutomation.NormalEggEngine.Alive = false
    CoreAutomation.Machines.Alive = false
    CoreAutomation.Machines.Gold.Auto = false
    CoreAutomation.Machines.Rainbow.Auto = false
    CoreAutomation.InfiniteEggEngine.Alive = false
    CoreAutomation.InfiniteEggEngine.AutoOpen = false
    CoreAutomation.InfiniteEggEngine.AutoDisableIndexed = false
    CoreAutomation.AutomaticEngine.Alive = false
    CoreAutomation.BestAreaEngine.Alive = false
    CoreAutomation.RankEngine.Alive = false
    CoreAutomation.FreeGiftEngine.Alive = false
    if CoreAutomation.Major then
        CoreAutomation.Major.Alive = false
        CoreAutomation.Major.AutoLoginStreak = false
        CoreAutomation.Major.AutoAreaRewards = false
        CoreAutomation.Major.AutoForeverPack = false
        CoreAutomation.Major.AutoDaycareClaim = false
        CoreAutomation.Major.AutoDaycareEnroll = false
        CoreAutomation.Major.AutoCombineKeys = false
        CoreAutomation.Major.AutoBalloonGifts = false
    end

    CoreAutomation.AutomaticEngine.AutoFruit = false
    CoreAutomation.AutomaticEngine.AutoPotion = false
    CoreAutomation.AutomaticEngine.AutoToys = false
    CoreAutomation.AutomaticEngine.AutoUltimate = false
    CoreAutomation.BestAreaEngine.AutoTeleport = false
    CoreAutomation.RankEngine.AutoClaim = false
    CoreAutomation.FreeGiftEngine.AutoClaim = false

    CoreAutomation.farmSetOrbVisualSuppressed(false)
    CoreAutomation.stopFarmEngine(reason or "Hub unloaded", true)
    CoreAutomation.stopNormalEggs(reason or "Hub unloaded")
    EggEngine.Alive = false
    GardenAutomation.Alive = false
    GardenAutomation.Suspended = true
    GardenAutomation.AutoCraftSelected = false
    GardenAutomation.AutoMaxLuck = false
    GardenAutomation.WorkerToken = GardenAutomation.WorkerToken + 1

    if GardenLineTools.Available then
        if type(GardenLineTools.SetAutoFill) == "function" then
            pcall(GardenLineTools.SetAutoFill, GardenLineTools, false)
        end
        if type(GardenLineTools.StopCleaning) == "function" then
            pcall(GardenLineTools.StopCleaning, GardenLineTools)
        end
    end

    stopEggEngine(reason or "Hub unloaded.", "info")
    EggEngine.DisableAnimation = false
    EggEngine:ApplyAnimationSetting()

    Config.farm.enabled = false
    Config.farm.playerDamage = false
    Config.farm.collectOrbs = false
    Config.farm.infSpeedPets = false
    Config.eggs.autoBuy = false
    Config.eggs.disableAnimation = false
    Config.eggs.autoGold = false
    Config.eggs.autoRainbow = false
    Config.infiniteEggs.autoOpen = false
    Config.infiniteEggs.autoDisableIndexed = false
    Config.teleports.autoBestArea = false
    Config.main.autoRankRewards = false
    Config.main.autoFreeGifts = false
    Config.automatic.autoFruit = false
    Config.automatic.autoSqueakyToy = false
    Config.automatic.autoToyBall = false
    Config.automatic.autoPotion = false
    Config.automatic.autoToys = false
    Config.automatic.autoUltimate = false
    Config.expansion.autoLoginStreak = false
    Config.expansion.autoAreaRewards = false
    Config.expansion.autoForeverPack = false
    Config.expansion.autoDaycareClaim = false
    Config.expansion.autoDaycareEnroll = false
    Config.expansion.autoCombineKeys = false
        Config.expansion.autoBalloonGifts = false
    Config.event.garden.autoCollect = false
    Config.event.garden.autoPlant = false
    Config.event.garden.autoUnlockLanes = false
    Config.event.garden.autoBuyPlots = false
    Config.event.garden.autoUpgrades = false
    Config.event.garden.autoRegrow = false
    Config.event.garden.autoRestoreUnits = false
    Config.event.garden.autoMerchant = false
    Config.event.garden.autoReinforce = false
    Config.event.garden.fullCampaign = false
    Config.event.garden.missionDirector = false
    Config.event.garden.autoSuperRebirth = false
    Config.event.crafting.auto = false
    Config.event.luck.auto = false
    Config.event.garden.lineTools.autoFill = false
    markConfigDirty()
    saveConfig(true)

    pcall(function()
        CurrentEventModule:Unload()
    end)

    CoreAutomation.farmRestoreOrbBridge()
    disconnectAll(CoreAutomation.FarmEngine.Connections)
    disconnectAll(EggEngine.Connections)
    disconnectAll(Runtime.Connections)

    if UI.Screen then
        pcall(function()
            UI.Screen:Destroy()
        end)
    end

    pcall(function()
        local roots = {}
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then table.insert(roots, playerGui) end
        if type(gethui) == "function" then
            local okHui, hui = pcall(gethui)
            if okHui and typeof(hui) == "Instance" and hui ~= playerGui then
                table.insert(roots, hui)
            end
        end
        for _, root in ipairs(roots) do
            for _, child in ipairs(root:GetChildren()) do
                local name = string.lower(tostring(child.Name or ""))
                if string.find(name, "slicehub_ps99", 1, true) then
                    pcall(child.Destroy, child)
                end
            end
        end
    end)

    if env.SliceHubPS99 == API then
        env.SliceHubPS99 = nil
    end

    appendLog("UNLOAD", reason or "Hub unloaded")
end

API.Version = HUB_VERSION
API.Generation = Runtime.Generation
API.Tier = USER_TIER
API.EventModule = CurrentEventModule
API.ConfigPath = CONFIG_PATH
API.LogPath = LOG_PATH

env.SliceHubPS99 = API

setNotice(
    CurrentEventModule.Supported
        and "Ready."
        or "Loaded. Waiting for Garden.",
    CurrentEventModule.Supported and "success" or "info"
)

appendLog(
    "READY",
    string.format(
        "Core=%s tier=%s eventSupported=%s eggs=%d rawDelay=%.3f stableDelay=%.3f",
        CORE_VERSION,
        USER_TIER,
        tostring(CurrentEventModule.Supported),
        #EggEngine.Eggs,
        EggEngine.RawDebounce,
        EggEngine.StableDelay
    )
)
appendLog("MOTION_BUILD", MOTION_BUILD_MARKER)
