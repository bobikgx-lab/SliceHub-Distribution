--[[
    SliceHub BABFT Edition
    AUTO FARM + AUTO BUILD Control Center
    Version 0.1.8.1

    Scope:
      - Creates SH/BABFT/AUTOBUILDSCEMES
      - Lists exact .Build files after Refresh Files
      - Decodes SliceHub JSON and BuilderHub BH2 .Build files
      - Normalizes and validates both blueprint schemas
      - Shows required material counts
      - Creates a removable, local-only ghost preview
      - Centers previews on the current team's building zone
      - Uses automatic performance LOD for oversized blueprints
      - Provides adjustable preview opacity
      - Provides a local-only Walkable Preview toggle
      - Keeps the runtime-confirmed 10-part placement engine
      - Runs one controlled blueprint-fidelity test through the native
        placement, scaling, and painting protocols
      - Verifies size, color, transparency, collision, and anchoring
      - Uses canonical Scaling/Painting remotes without requiring tool
        ownership or equipped state
      - Saves the latest placement protocol result as a local JSON dump

    Explicitly excluded:
      - No full-blueprint construction
      - No automatic retry
      - No more than one placement, one scale, and one paint call per test
      - No two-stage Spring, Bar, or Rope placement
      - No guessed transparency or collision mutation
      - No BindTable activation
      - No mechanical activation
]]

local SCRIPT_NAME = "SliceHub BABFT Control Center"
local SCRIPT_VERSION = "0.1.8.1"
local BUILD_FOLDER = "SH/BABFT/AUTOBUILDSCEMES"
local PROBE_FOLDER = "SH/BABFT/probes"
local MAX_FILE_BYTES = 25 * 1024 * 1024
local MAX_PARTS = 60000
local FULL_PREVIEW_PART_LIMIT = 8000
local MAX_PREVIEW_GHOSTS = 8000
local PREVIEW_CHUNK_SIZE = 120
local DEFAULT_PREVIEW_OPACITY = 0.72
local MIN_PREVIEW_OPACITY = 0.25
local MAX_PREVIEW_OPACITY = 1
local PREVIEW_SOURCE_TRANSPARENCY_ATTRIBUTE =
    "SliceHubPreviewSourceTransparency"
local PREVIEW_SOURCE_COLLISION_ATTRIBUTE =
    "SliceHubPreviewSourceCanCollide"
local TEST_BLOCK_NAME = "WoodBlock"
local TEST_VERIFY_TIMEOUT = 10
local previewOpacity = DEFAULT_PREVIEW_OPACITY
local walkablePreview = false
local BUILD_TIER = "PREMIUM"
local IS_PREMIUM = true
local USER_TIER = IS_PREMIUM and "Premium" or "Free"


if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local playerDeadline = os.clock() + 20
while not LocalPlayer and os.clock() < playerDeadline do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end
if not LocalPlayer then
    warn("[" .. SCRIPT_NAME .. "] LocalPlayer unavailable.")
    return
end

local environment = _G
pcall(function()
    if type(getgenv) == "function" then
        environment = getgenv()
    end
end)
if type(environment) ~= "table" then
    environment = _G
end
previewOpacity = math.clamp(
    tonumber(environment.__SliceHubBABFTPreviewOpacity)
        or previewOpacity,
    MIN_PREVIEW_OPACITY,
    MAX_PREVIEW_OPACITY
)
walkablePreview =
    environment.__SliceHubBABFTPreviewWalkable == true

local previousController = environment.__SliceHubBABFTAutoBuildPreviewController
if type(previousController) == "table"
    and type(previousController.Destroy) == "function" then
    pcall(previousController.Destroy)
    task.wait(0.1)
end
local previousFarmController =
    environment.__SliceHubBABFTStandaloneFarmController
if type(previousFarmController) == "table"
    and type(previousFarmController.Destroy) == "function" then
    pcall(previousFarmController.Destroy)
    task.wait(0.1)
end
environment.SliceHubBABFTAutoFarmStop = true

local function requirePremium(featureName)
    if IS_PREMIUM then return true end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "SliceHub BABFT • Premium",
            Text = tostring(featureName or "This automation") .. " is visible in Free but requires Premium.",
            Duration = 6,
        })
    end)
    return false
end

local function getGlobalFunction(name)
    local value
    pcall(function()
        value = environment[name]
    end)
    if type(value) ~= "function" and environment ~= _G then
        pcall(function()
            value = _G[name]
        end)
    end
    return type(value) == "function" and value or nil
end

local READ_FILE = getGlobalFunction("readfile")
local LIST_FILES = getGlobalFunction("listfiles")
local MAKE_FOLDER = getGlobalFunction("makefolder")
local IS_FOLDER = getGlobalFunction("isfolder")
local WRITE_FILE = getGlobalFunction("writefile")

local function ensureFolder(path)
    if IS_FOLDER then
        local ok, exists = pcall(IS_FOLDER, path)
        if ok and exists then
            return true
        end
    end
    if not MAKE_FOLDER then
        return false
    end
    local ok = pcall(MAKE_FOLDER, path)
    if ok then
        return true
    end
    if IS_FOLDER then
        local checkOk, exists = pcall(IS_FOLDER, path)
        return checkOk and exists == true
    end
    return false
end

local folderReady = ensureFolder("SH")
    and ensureFolder("SH/BABFT")
    and ensureFolder(BUILD_FOLDER)
local probeFolderReady = ensureFolder("SH")
    and ensureFolder("SH/BABFT")
    and ensureFolder(PROBE_FOLDER)

local function basename(path)
    local normalized = tostring(path):gsub("\\", "/")
    return normalized:match("([^/]+)$") or normalized
end

local function endsWithExactBuild(name)
    name = tostring(name)
    return #name >= 6 and name:sub(-6) == ".Build"
end

local function finiteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and math.abs(value) <= 10000000
end

local function parseTriple(text)
    if type(text) ~= "string" then
        return nil, "value is not a string"
    end

    local values = {}
    for token in text:gmatch("[^,]+") do
        local numberValue = tonumber(token:match("^%s*(.-)%s*$"))
        if not finiteNumber(numberValue) then
            return nil, "contains a non-finite number"
        end
        values[#values + 1] = numberValue
    end

    if #values ~= 3 then
        return nil, "must contain exactly three numbers"
    end
    return Vector3.new(values[1], values[2], values[3])
end

local function parseColor(text)
    local vector, reason = parseTriple(text)
    if not vector then
        return nil, reason
    end
    return Color3.new(
        math.clamp(vector.X, 0, 1),
        math.clamp(vector.Y, 0, 1),
        math.clamp(vector.Z, 0, 1)
    )
end

local BuildingParts = ReplicatedStorage:FindFirstChild("BuildingParts")

local function decodeBuildDocument(raw, analysis)
    local trimmed = raw:match("^%s*(.-)%s*$") or raw
    if trimmed:sub(1, 11) == "BuilderHub_" then
        local buildMarkerStart = trimmed:find("[Build]", 1, true)
        local assignmentStart = buildMarkerStart
            and trimmed:find("Build=", buildMarkerStart + 7, true)
        if not assignmentStart then
            return nil, "BuilderHub file has no [Build] payload."
        end

        local payload = trimmed:sub(assignmentStart + 6)
        payload = payload:match("^%s*(.-)%s*$") or payload
        local decodeOk, builderHub = pcall(function()
            return HttpService:JSONDecode(payload)
        end)
        if not decodeOk or type(builderHub) ~= "table" then
            return nil, "BuilderHub Build payload is not valid JSON."
        end
        if type(builderHub.b) ~= "table" then
            return nil, "BuilderHub Build payload has no block table."
        end

        local typeOrder = {}
        local groupedParts = {}
        for blockType, group in pairs(builderHub.b) do
            if type(blockType) ~= "string"
                or type(group) ~= "table" then
                return nil, "BuilderHub block table is malformed."
            end

            typeOrder[#typeOrder + 1] = blockType
            local normalizedGroup = {}
            groupedParts[blockType] = normalizedGroup
            for index, savedPart in ipairs(group) do
                if type(savedPart) ~= "table" then
                    return nil,
                        "BuilderHub "
                            .. blockType
                            .. " entry #"
                            .. tostring(index)
                            .. " is malformed."
                end
                normalizedGroup[index] = {
                    ID = savedPart.i,
                    Position = savedPart.p,
                    Rotation = savedPart.r,
                    Size = savedPart.sz,
                    Color = savedPart.cl,
                    Transparency = savedPart.tr,
                    BindTable = savedPart.bd,
                    CanCollide = savedPart.cc,
                    Anchored = savedPart.a,
                    BuilderHubRaw = savedPart,
                }
            end
        end
        table.sort(typeOrder, function(left, right)
            return left:lower() < right:lower()
        end)

        analysis.sourceFormat = "BuilderHub BH2"
        analysis.sourceVersion = builderHub.v
        analysis.sourceTeam = builderHub.t
        return {typeOrder, groupedParts}
    end

    local decodeOk, decoded = pcall(function()
        return HttpService:JSONDecode(trimmed)
    end)
    if not decodeOk or type(decoded) ~= "table" then
        return nil, "File is not valid .Build JSON."
    end
    analysis.sourceFormat = "SliceHub JSON"
    return decoded
end

local function analyzeBuildFile(path)
    local analysis = {
        path = path,
        fileName = basename(path),
        valid = false,
        errors = {},
        warnings = {},
        materials = {},
        parts = {},
        partCount = 0,
        typeCount = 0,
        bindingCount = 0,
        syntheticIds = false,
        missingTemplateTypes = {},
        boundsMin = nil,
        boundsMax = nil,
        rawBytes = 0,
        sourceFormat = "Unknown",
        sourceVersion = nil,
        sourceTeam = nil,
    }

    local function addError(message)
        analysis.errors[#analysis.errors + 1] = tostring(message)
    end

    local function addWarning(message)
        analysis.warnings[#analysis.warnings + 1] = tostring(message)
    end

    if not READ_FILE then
        addError("Executor does not provide readfile.")
        return analysis
    end

    local readOk, raw = pcall(READ_FILE, path)
    if not readOk or type(raw) ~= "string" then
        addError("Could not read the selected file.")
        return analysis
    end

    analysis.rawBytes = #raw
    if #raw == 0 then
        addError("File is empty.")
        return analysis
    end
    if #raw > MAX_FILE_BYTES then
        addError("File exceeds the 25 MB preview limit.")
        return analysis
    end

    local decoded, decodeProblem = decodeBuildDocument(raw, analysis)
    if not decoded then
        addError(decodeProblem or "Could not decode the .Build file.")
        return analysis
    end

    local typeOrder = decoded[1]
    local groupedParts = decoded[2]
    if type(typeOrder) ~= "table" or type(groupedParts) ~= "table" then
        addError("Expected [type list, grouped parts] at the top level.")
        return analysis
    end

    local declaredTypes = {}
    for index, blockType in ipairs(typeOrder) do
        if type(blockType) ~= "string" or blockType == "" then
            addError("Declared block type #" .. tostring(index) .. " is invalid.")
        elseif declaredTypes[blockType] then
            addError("Duplicate declared block type: " .. blockType)
        else
            declaredTypes[blockType] = true
        end
    end

    for blockType in pairs(groupedParts) do
        if type(blockType) ~= "string" then
            addError("Grouped block type key is not a string.")
        elseif not declaredTypes[blockType] then
            addError("Grouped type was not declared: " .. blockType)
        end
    end

    local hasExplicitIds = false
    local hasMissingIds = false
    for _, blockType in ipairs(typeOrder) do
        local group = groupedParts[blockType]
        if type(group) == "table" then
            for _, savedPart in ipairs(group) do
                if type(savedPart) == "table" then
                    if savedPart.ID == nil then
                        hasMissingIds = true
                    else
                        hasExplicitIds = true
                    end
                end
            end
        end
    end

    local usesSyntheticIds = hasMissingIds and not hasExplicitIds
    analysis.syntheticIds = usesSyntheticIds
    if hasMissingIds and hasExplicitIds then
        addError("Blueprint mixes ID-based and ID-less part entries.")
    elseif usesSyntheticIds then
        addWarning(
            "ID-less blueprint: generated preview-only part IDs."
        )
    end

    local ids = {}
    local bindingTargets = {}
    local missingTemplates = {}
    local boundsMin = Vector3.new(math.huge, math.huge, math.huge)
    local boundsMax = Vector3.new(-math.huge, -math.huge, -math.huge)

    for _, blockType in ipairs(typeOrder) do
        local group = groupedParts[blockType]
        if type(group) ~= "table" then
            addError("Missing or invalid group for " .. blockType .. ".")
            group = {}
        end

        local template = BuildingParts
            and BuildingParts:FindFirstChild(blockType)
        if not template then
            missingTemplates[blockType] = true
        end

        analysis.materials[#analysis.materials + 1] = {
            blockType = blockType,
            count = #group,
            templateFound = template ~= nil,
        }

        for groupIndex, savedPart in ipairs(group) do
            if analysis.partCount >= MAX_PARTS then
                addError("Blueprint exceeds the 60,000-part analysis limit.")
                break
            end

            if type(savedPart) ~= "table" then
                addError(
                    blockType
                        .. " entry #"
                        .. tostring(groupIndex)
                        .. " is not an object."
                )
            else
                local id = usesSyntheticIds
                    and (analysis.partCount + 1)
                    or savedPart.ID
                if usesSyntheticIds then
                    ids[id] = true
                elseif not finiteNumber(id)
                    or id % 1 ~= 0
                    or id < 1 then
                    addError(
                        blockType
                            .. " entry #"
                            .. tostring(groupIndex)
                            .. " has an invalid ID."
                    )
                elseif ids[id] then
                    addError("Duplicate part ID: " .. tostring(id))
                else
                    ids[id] = true
                end

                local position, positionReason = parseTriple(savedPart.Position)
                local rotation, rotationReason = parseTriple(savedPart.Rotation)
                local size = nil
                local color = nil

                if not position then
                    addError(
                        "ID "
                            .. tostring(id)
                            .. " Position "
                            .. tostring(positionReason)
                            .. "."
                    )
                end
                if not rotation then
                    addError(
                        "ID "
                            .. tostring(id)
                            .. " Rotation "
                            .. tostring(rotationReason)
                            .. "."
                    )
                end

                if savedPart.Size ~= nil then
                    local sizeReason
                    size, sizeReason = parseTriple(savedPart.Size)
                    if not size then
                        addError(
                            "ID "
                                .. tostring(id)
                                .. " Size "
                                .. tostring(sizeReason)
                                .. "."
                        )
                    elseif size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
                        addError("ID " .. tostring(id) .. " has a non-positive Size.")
                        size = nil
                    end
                end

                if savedPart.Color ~= nil then
                    local colorReason
                    color, colorReason = parseColor(savedPart.Color)
                    if not color then
                        addError(
                            "ID "
                                .. tostring(id)
                                .. " Color "
                                .. tostring(colorReason)
                                .. "."
                        )
                    end
                end

                if savedPart.Transparency ~= nil
                    and not finiteNumber(savedPart.Transparency) then
                    addError("ID " .. tostring(id) .. " has invalid Transparency.")
                end

                local bindTable = savedPart.BindTable
                if bindTable ~= nil then
                    if type(bindTable) ~= "table" then
                        addError("ID " .. tostring(id) .. " BindTable is invalid.")
                    elseif usesSyntheticIds and #bindTable > 0 then
                        addError(
                            "ID-less blueprint contains bindings "
                                .. "that cannot be verified."
                        )
                    else
                        for bindIndex, binding in ipairs(bindTable) do
                            local targetID = type(binding) == "table"
                                and binding[1]
                            local action = type(binding) == "table"
                                and binding[2]
                            local keyCode = type(binding) == "table"
                                and binding[3]
                            if not finiteNumber(targetID)
                                or targetID % 1 ~= 0
                                or type(action) ~= "string"
                                or not finiteNumber(keyCode) then
                                addError(
                                    "ID "
                                        .. tostring(id)
                                        .. " binding #"
                                        .. tostring(bindIndex)
                                        .. " is malformed."
                                )
                            else
                                bindingTargets[#bindingTargets + 1] = {
                                    ownerID = id,
                                    targetID = targetID,
                                }
                                analysis.bindingCount = analysis.bindingCount + 1
                            end
                        end
                    end
                end

                if position and rotation then
                    local previewSize = size or Vector3.new(2, 2, 2)
                    local halfSize = previewSize * 0.5
                    boundsMin = Vector3.new(
                        math.min(boundsMin.X, position.X - halfSize.X),
                        math.min(boundsMin.Y, position.Y - halfSize.Y),
                        math.min(boundsMin.Z, position.Z - halfSize.Z)
                    )
                    boundsMax = Vector3.new(
                        math.max(boundsMax.X, position.X + halfSize.X),
                        math.max(boundsMax.Y, position.Y + halfSize.Y),
                        math.max(boundsMax.Z, position.Z + halfSize.Z)
                    )

                    analysis.parts[#analysis.parts + 1] = {
                        blockType = blockType,
                        id = id,
                        position = position,
                        rotation = rotation,
                        size = size,
                        color = color,
                        transparency = math.clamp(
                            tonumber(savedPart.Transparency) or 0,
                            0,
                            1
                        ),
                        raw = savedPart,
                    }
                end
                analysis.partCount = analysis.partCount + 1
            end
        end

        if analysis.partCount >= MAX_PARTS and #analysis.errors > 0 then
            break
        end
    end

    analysis.typeCount = #typeOrder
    for blockType in pairs(missingTemplates) do
        analysis.missingTemplateTypes[#analysis.missingTemplateTypes + 1] =
            blockType
    end
    table.sort(analysis.missingTemplateTypes)
    if #analysis.missingTemplateTypes > 0 then
        addWarning(
            "Missing local templates: "
                .. table.concat(analysis.missingTemplateTypes, ", ")
        )
    end

    for declaredType in pairs(declaredTypes) do
        if groupedParts[declaredType] == nil then
            addError("Declared type has no group: " .. declaredType)
        end
    end

    if analysis.partCount == 0 then
        addError("Blueprint contains no parts.")
    end

    for expectedID = 1, analysis.partCount do
        if not ids[expectedID] then
            addError("Missing continuous part ID: " .. tostring(expectedID))
            if #analysis.errors >= 30 then
                addWarning("Additional ID errors were suppressed.")
                break
            end
        end
    end

    for _, binding in ipairs(bindingTargets) do
        if not ids[binding.targetID] then
            addError(
                "ID "
                    .. tostring(binding.ownerID)
                    .. " binds to missing ID "
                    .. tostring(binding.targetID)
                    .. "."
            )
        end
    end

    table.sort(analysis.parts, function(left, right)
        return left.id < right.id
    end)

    if analysis.partCount > 0 and boundsMin.X ~= math.huge then
        analysis.boundsMin = boundsMin
        analysis.boundsMax = boundsMax
    end

    analysis.valid = #analysis.errors == 0
    return analysis
end

local function getTemplateBasePart(template)
    if not template then
        return nil
    end
    if template:IsA("BasePart") then
        return template
    end
    return template:FindFirstChildWhichIsA("BasePart", true)
end

local function safePreviewTransparency(sourceTransparency)
    sourceTransparency = math.clamp(
        tonumber(sourceTransparency) or 0,
        0,
        1
    )
    if sourceTransparency >= 0.999 then
        return 1
    end
    return math.max(sourceTransparency, 1 - previewOpacity)
end

local function setPreviewPartTransparency(part, sourceTransparency)
    sourceTransparency = math.clamp(
        tonumber(sourceTransparency) or 0,
        0,
        1
    )
    part:SetAttribute(
        PREVIEW_SOURCE_TRANSPARENCY_ATTRIBUTE,
        sourceTransparency
    )
    part.Transparency = safePreviewTransparency(sourceTransparency)
end

local function setPreviewPartCollision(part, sourceCanCollide)
    local canCollide = sourceCanCollide == true
    part:SetAttribute(
        PREVIEW_SOURCE_COLLISION_ATTRIBUTE,
        canCollide
    )
    part.CanCollide = false
end

local function sanitizePreviewInstance(instance, savedPart)
    local descendants = instance:GetDescendants()
    table.insert(descendants, 1, instance)

    for _, descendant in ipairs(descendants) do
        if descendant:IsA("LuaSourceContainer")
            or descendant:IsA("RemoteEvent")
            or descendant:IsA("RemoteFunction")
            or descendant:IsA("BindableEvent")
            or descendant:IsA("BindableFunction")
            or descendant:IsA("ClickDetector")
            or descendant:IsA("ProximityPrompt")
            or descendant:IsA("Sound") then
            pcall(function()
                descendant:Destroy()
            end)
        elseif descendant:IsA("BasePart") then
            local sourceCanCollide = descendant.CanCollide
            descendant.Anchored = true
            setPreviewPartCollision(
                descendant,
                savedPart.raw.CanCollide ~= false
                    and sourceCanCollide
            )
            descendant.CanTouch = false
            descendant.CanQuery = false
            descendant.CastShadow = false
            descendant.Massless = true
            setPreviewPartTransparency(
                descendant,
                math.max(
                    descendant.Transparency,
                    savedPart.transparency
                )
            )
            if savedPart.color then
                descendant.Color = savedPart.color
            end
            pcall(function()
                descendant.Disabled = true
            end)
        elseif descendant:IsA("ParticleEmitter")
            or descendant:IsA("Beam")
            or descendant:IsA("Trail")
            or descendant:IsA("Smoke")
            or descendant:IsA("Fire")
            or descendant:IsA("Sparkles")
            or descendant:IsA("Light") then
            pcall(function()
                descendant.Enabled = false
            end)
        elseif descendant:IsA("Constraint") then
            pcall(function()
                descendant.Enabled = false
            end)
        end
    end
end

local TEAM_ZONE_NAMES = {
    black = "BlackZone",
    blue = "Really blueZone",
    ["really blue"] = "Really blueZone",
    green = "CamoZone",
    camo = "CamoZone",
    magenta = "MagentaZone",
    red = "Really redZone",
    ["really red"] = "Really redZone",
    white = "WhiteZone",
    yellow = "New YellerZone",
    ["new yeller"] = "New YellerZone",
}

local function findTeamBuildZone(root)
    local nativeZoneName
    pcall(function()
        nativeZoneName = tostring(LocalPlayer.TeamColor) .. "Zone"
    end)
    local nativeZone = nativeZoneName
        and Workspace:FindFirstChild(nativeZoneName)
    if nativeZone and nativeZone:IsA("BasePart") then
        return nativeZone
    end

    local team = LocalPlayer.Team
    local lookupNames = {}
    if team then
        lookupNames[#lookupNames + 1] = tostring(team.Name):lower()
        pcall(function()
            lookupNames[#lookupNames + 1] =
                tostring(team.TeamColor.Name):lower()
        end)
    end

    for _, lookupName in ipairs(lookupNames) do
        local zoneName = TEAM_ZONE_NAMES[lookupName]
        local candidate = zoneName
            and Workspace:FindFirstChild(zoneName)
        if candidate and candidate:IsA("BasePart") then
            return candidate
        end
    end

    if not root then
        return nil
    end

    local nearestZone = nil
    local nearestDistance = math.huge
    local checkedZoneNames = {}
    for _, zoneName in pairs(TEAM_ZONE_NAMES) do
        if not checkedZoneNames[zoneName] then
            checkedZoneNames[zoneName] = true
            local candidate = Workspace:FindFirstChild(zoneName)
            if candidate and candidate:IsA("BasePart") then
                local offset = Vector3.new(
                    candidate.Position.X - root.Position.X,
                    0,
                    candidate.Position.Z - root.Position.Z
                )
                if offset.Magnitude < nearestDistance then
                    nearestDistance = offset.Magnitude
                    nearestZone = candidate
                end
            end
        end
    end
    return nearestZone
end

local function findPreviewAnchor()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local buildZone = findTeamBuildZone(root)
    if not buildZone then
        return nil, 0, "build_zone_unavailable"
    end

    local zoneCFrame = buildZone.CFrame
    local anchorPosition = (
        zoneCFrame * CFrame.new(0, buildZone.Size.Y * 0.5, 0)
    ).Position

    local zoneLook = Vector3.new(
        zoneCFrame.LookVector.X,
        0,
        zoneCFrame.LookVector.Z
    )
    if zoneLook.Magnitude < 0.001 then
        zoneLook = Vector3.new(0, 0, -1)
    else
        zoneLook = zoneLook.Unit
    end

    return CFrame.lookAt(
        anchorPosition,
        anchorPosition + zoneLook
    ), 0, "build_zone_center"
end

local function makePreviewObject(savedPart, worldCFrame)
    local template = BuildingParts
        and BuildingParts:FindFirstChild(savedPart.blockType)

    if savedPart.size then
        local previewPart = Instance.new("Part")
        previewPart.Name = savedPart.blockType .. "_" .. tostring(savedPart.id)
        previewPart.Size = savedPart.size
        previewPart.CFrame = worldCFrame
        previewPart.Anchored = true
        setPreviewPartCollision(
            previewPart,
            savedPart.raw.CanCollide ~= false
        )
        previewPart.CanTouch = false
        previewPart.CanQuery = false
        previewPart.CastShadow = false
        previewPart.Massless = true
        setPreviewPartTransparency(
            previewPart,
            savedPart.transparency
        )

        local templatePart = getTemplateBasePart(template)
        if templatePart then
            previewPart.Color = savedPart.color or templatePart.Color
            previewPart.Material = templatePart.Material
            pcall(function()
                previewPart.MaterialVariant = templatePart.MaterialVariant
            end)
        else
            previewPart.Color = savedPart.color
                or Color3.fromRGB(70, 210, 235)
            previewPart.Material = Enum.Material.SmoothPlastic
        end
        return previewPart
    end

    if template then
        local cloneOk, clone = pcall(function()
            return template:Clone()
        end)
        if cloneOk and clone then
            clone.Name = savedPart.blockType .. "_" .. tostring(savedPart.id)
            sanitizePreviewInstance(clone, savedPart)
            if clone:IsA("BasePart") then
                clone.CFrame = worldCFrame
            elseif clone:IsA("Model") then
                clone:PivotTo(worldCFrame)
            else
                local basePart = clone:FindFirstChildWhichIsA("BasePart", true)
                if basePart then
                    local offset = worldCFrame * basePart.CFrame:Inverse()
                    for _, descendant in ipairs(clone:GetDescendants()) do
                        if descendant:IsA("BasePart") then
                            descendant.CFrame = offset * descendant.CFrame
                        end
                    end
                end
            end
            return clone
        end
    end

    local placeholder = Instance.new("Part")
    placeholder.Name = savedPart.blockType
        .. "_"
        .. tostring(savedPart.id)
        .. "_MissingTemplate"
    placeholder.Size = Vector3.new(2, 2, 2)
    placeholder.CFrame = worldCFrame
    placeholder.Anchored = true
    setPreviewPartCollision(placeholder, false)
    placeholder.CanTouch = false
    placeholder.CanQuery = false
    placeholder.CastShadow = false
    placeholder.Massless = true
    setPreviewPartTransparency(placeholder, 0)
    placeholder.Color = Color3.fromRGB(255, 91, 132)
    placeholder.Material = Enum.Material.Neon
    return placeholder
end

local function findSpatialExtremeIds(parts)
    local values = {
        minX = math.huge,
        minY = math.huge,
        minZ = math.huge,
        maxX = -math.huge,
        maxY = -math.huge,
        maxZ = -math.huge,
    }
    local ids = {}

    for _, savedPart in ipairs(parts) do
        local size = savedPart.size or Vector3.new(2, 2, 2)
        local halfSize = size * 0.5
        local position = savedPart.position
        local minX = position.X - halfSize.X
        local minY = position.Y - halfSize.Y
        local minZ = position.Z - halfSize.Z
        local maxX = position.X + halfSize.X
        local maxY = position.Y + halfSize.Y
        local maxZ = position.Z + halfSize.Z

        if minX < values.minX then
            values.minX = minX
            ids.minX = savedPart.id
        end
        if minY < values.minY then
            values.minY = minY
            ids.minY = savedPart.id
        end
        if minZ < values.minZ then
            values.minZ = minZ
            ids.minZ = savedPart.id
        end
        if maxX > values.maxX then
            values.maxX = maxX
            ids.maxX = savedPart.id
        end
        if maxY > values.maxY then
            values.maxY = maxY
            ids.maxY = savedPart.id
        end
        if maxZ > values.maxZ then
            values.maxZ = maxZ
            ids.maxZ = savedPart.id
        end
    end

    local result = {}
    for _, id in pairs(ids) do
        result[id] = true
    end
    return result
end

local function isPriorityPreviewPart(savedPart, extremeIds)
    if extremeIds[savedPart.id] or not savedPart.size then
        return true
    end
    local bindTable = savedPart.raw and savedPart.raw.BindTable
    return type(bindTable) == "table" and #bindTable > 0
end

local function buildPreviewPartList(parts)
    local sourceCount = #parts
    if sourceCount <= FULL_PREVIEW_PART_LIMIT then
        return parts, false
    end

    local extremeIds = findSpatialExtremeIds(parts)
    local priorityCount = 0
    for _, savedPart in ipairs(parts) do
        if isPriorityPreviewPart(savedPart, extremeIds) then
            priorityCount = priorityCount + 1
        end
    end

    local maximumPriorityGhosts = math.max(
        1,
        math.floor(MAX_PREVIEW_GHOSTS * 0.25)
    )
    local priorityStride = math.max(
        1,
        math.ceil(priorityCount / maximumPriorityGhosts)
    )
    local keptPriorityCount = math.ceil(priorityCount / priorityStride)
    local structuralCount = sourceCount - priorityCount
    local structuralBudget = math.max(
        1,
        MAX_PREVIEW_GHOSTS - keptPriorityCount
    )
    local structuralStride = math.max(
        1,
        math.ceil(structuralCount / structuralBudget)
    )

    local selected = {}
    local priorityIndex = 0
    local structuralIndex = 0
    for _, savedPart in ipairs(parts) do
        local include = false
        if isPriorityPreviewPart(savedPart, extremeIds) then
            priorityIndex = priorityIndex + 1
            include = (priorityIndex - 1) % priorityStride == 0
        else
            structuralIndex = structuralIndex + 1
            include = (structuralIndex - 1) % structuralStride == 0
        end

        if include and #selected < MAX_PREVIEW_GHOSTS then
            selected[#selected + 1] = savedPart
        end
    end

    if #selected == 0 and sourceCount > 0 then
        selected[1] = parts[1]
    end
    return selected, true
end

local controller = {}
local destroyRequested = false
local guiConnections = {}
local analysisGeneration = 0
local previewGeneration = 0
local previewModel = nil
local previewBuilding = false
local placementTesting = false
local placementGeneration = 0
local latestProtocolDump = nil
local selectedPath = nil
local selectedAnalysis = nil
local buildFiles = {}
local opacityApplyGeneration = 0

local function applyPreviewOpacity()
    local model = previewModel
    if not model or not model.Parent then
        return
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local sourceTransparency = descendant:GetAttribute(
                PREVIEW_SOURCE_TRANSPARENCY_ATTRIBUTE
            )
            if type(sourceTransparency) == "number" then
                descendant.Transparency = safePreviewTransparency(
                    sourceTransparency
                )
            end
        end
    end
end

local function queuePreviewOpacityApply(immediate)
    opacityApplyGeneration = opacityApplyGeneration + 1
    local generation = opacityApplyGeneration
    if immediate then
        applyPreviewOpacity()
        return
    end

    task.delay(0.08, function()
        if destroyRequested or generation ~= opacityApplyGeneration then
            return
        end
        applyPreviewOpacity()
    end)
end

local function applyWalkablePreview()
    local model = previewModel
    if not model or not model.Parent then
        return true
    end
    if walkablePreview
        and model:GetAttribute("PerformanceLOD") == true then
        walkablePreview = false
        environment.__SliceHubBABFTPreviewWalkable = false
        return false
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local sourceCanCollide = descendant:GetAttribute(
                PREVIEW_SOURCE_COLLISION_ATTRIBUTE
            )
            descendant.CanCollide = walkablePreview
                and sourceCanCollide == true
                or false
        end
    end
    return true
end

local Farm = {
    Enabled = false,
    WorkerRunning = false,
    StartedAt = os.clock(),
    StartingGold = 0,
    CompletedCycles = 0,
    TreasureFinishes = 0,
    FailedCycles = 0,
    LastStatus = "Ready",
    LastFailure = nil,
    CameraRestore = nil,
    Checkpoints = {},
    Events = {},
    Errors = {},
    UI = {},
    StatsView = "session",
    SessionFastestRun = nil,
    LastRunEarned = 0,
    SessionGoldEarned = 0,
    LastObservedGold = nil,
    LastRunReachedEnd = false,
    CurrentRunStartedAt = nil,
    RuntimeCommitted = true,
    SessionElapsedAtStop = 0,
}

Farm.StatsFolder = "SH/BABFT/state"
Farm.StatsPath = Farm.StatsFolder .. "/autofarm_stats.json"
Farm.GuiStatePath = Farm.StatsFolder .. "/gui_state.json"
Farm.GuiState = {
    schemaVersion = 2,
    xScale = 0.5,
    xOffset = 0,
    yScale = 0,
    yOffset = 60,
    scale = tonumber(environment.__SliceHubBABFTControlCenterScale) or 1,
    minimized = false,
    floatXScale = 1,
    floatXOffset = -72,
    floatYScale = 0.82,
    floatYOffset = 0,
}
Farm.Overall = {
    schemaVersion = 2,
    sessions = 0,
    runtimeSeconds = 0,
    runs = 0,
    gold = 0,
    recoveries = 0,
    finishes = 0,
    fastestRunSeconds = nil,
}

Farm.Defaults = {
    MaxCycles = 0,
    TargetGold = 0,
    StopAtCheckpoint = 10,
    VisitTreasureAtEnd = true,
    FastRestart = true,
    CameraComfortMode = true,
    StageDwellSeconds = 2.5,
    BetweenRunsSeconds = 1,
    CharacterTimeoutSeconds = 25,
    TreasureTimeoutSeconds = 30,
    TreasureAttemptWaitSeconds = 1.25,
    SaveSession = true,
    WebhookEnabled = false,
    WebhookUrl = "",
}

Farm.Config = environment.SliceHubBABFTAutoFarmConfig
if type(Farm.Config) ~= "table" then
    Farm.Config = {}
    environment.SliceHubBABFTAutoFarmConfig = Farm.Config
end
if Farm.Config.VisitTreasureAtEnd == nil
    and Farm.Config.ClaimTreasureAtEnd ~= nil then
    Farm.Config.VisitTreasureAtEnd =
        Farm.Config.ClaimTreasureAtEnd == true
end
for key, value in pairs(Farm.Defaults) do
    if Farm.Config[key] == nil then
        Farm.Config[key] = value
    end
end

function Farm:SanitizeConfig()
    self.Config.MaxCycles = math.max(
        0,
        math.floor(tonumber(self.Config.MaxCycles) or 0)
    )
    self.Config.TargetGold = math.max(
        0,
        math.floor(tonumber(self.Config.TargetGold) or 0)
    )
    self.Config.StopAtCheckpoint = math.clamp(
        math.floor(tonumber(self.Config.StopAtCheckpoint) or 10),
        1,
        10
    )
    self.Config.StageDwellSeconds = math.clamp(
        tonumber(self.Config.StageDwellSeconds) or 2.5,
        2,
        8
    )
    self.Config.BetweenRunsSeconds = math.clamp(
        tonumber(self.Config.BetweenRunsSeconds) or 6,
        1,
        60
    )
    self.Config.TreasureAttemptWaitSeconds = math.clamp(
        tonumber(self.Config.TreasureAttemptWaitSeconds) or 1.25,
        0.8,
        1.5
    )
end
Farm:SanitizeConfig()

function Farm:FormatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remaining = seconds % 60
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    end
    if minutes > 0 then
        return string.format("%dm %02ds", minutes, remaining)
    end
    return tostring(remaining) .. "s"
end

function Farm:LoadOverallStats()
    if not READ_FILE then
        return
    end
    local ok, raw = pcall(READ_FILE, self.StatsPath)
    if not ok or type(raw) ~= "string" or raw == "" then
        return
    end
    local decodedOk, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not decodedOk or type(decoded) ~= "table" then
        return
    end
    self.Overall.sessions = math.max(
        0,
        math.floor(tonumber(decoded.sessions) or 0)
    )
    self.Overall.runtimeSeconds = math.max(
        0,
        tonumber(decoded.runtimeSeconds) or 0
    )
    self.Overall.runs = math.max(
        0,
        math.floor(tonumber(decoded.runs) or 0)
    )
    self.Overall.gold = math.max(
        0,
        math.floor(tonumber(decoded.gold) or 0)
    )
    self.Overall.recoveries = math.max(
        0,
        math.floor(tonumber(decoded.recoveries) or 0)
    )
    self.Overall.finishes = math.max(
        0,
        math.floor(tonumber(decoded.finishes) or 0)
    )
    local fastest = tonumber(decoded.fastestRunSeconds)
    self.Overall.fastestRunSeconds =
        fastest and fastest > 0 and fastest or nil
end

function Farm:SaveOverallStats()
    if not WRITE_FILE then
        return false
    end
    if not (ensureFolder("SH")
        and ensureFolder("SH/BABFT")
        and ensureFolder(self.StatsFolder)) then
        return false
    end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(self.Overall)
    end)
    if not ok then
        return false
    end
    return pcall(WRITE_FILE, self.StatsPath, encoded)
end

function Farm:LoadGuiState()
    if READ_FILE then
        local ok, raw = pcall(READ_FILE, self.GuiStatePath)
        if ok and type(raw) == "string" and raw ~= "" then
            local decodedOk, decoded = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if decodedOk and type(decoded) == "table" then
                for _, key in ipairs({
                    "scale",
                    "floatXScale",
                    "floatXOffset",
                    "floatYScale",
                    "floatYOffset",
                }) do
                    if type(decoded[key]) == "number" then
                        self.GuiState[key] = decoded[key]
                    end
                end
                if tonumber(decoded.schemaVersion) == 2 then
                    for _, key in ipairs({
                        "xScale",
                        "xOffset",
                        "yScale",
                        "yOffset",
                    }) do
                        if type(decoded[key]) == "number" then
                            self.GuiState[key] = decoded[key]
                        end
                    end
                end
                self.GuiState.minimized = decoded.minimized == true
            end
        end
    end
    self.GuiState.scale = math.clamp(
        tonumber(self.GuiState.scale) or 1,
        0.62,
        1.35
    )
    environment.__SliceHubBABFTControlCenterScale = self.GuiState.scale
end

function Farm:SaveGuiState(position, scale, minimized)
    self.GuiState.schemaVersion = 2
    if position then
        self.GuiState.xScale = position.X.Scale
        self.GuiState.xOffset = position.X.Offset
        self.GuiState.yScale = position.Y.Scale
        self.GuiState.yOffset = position.Y.Offset
    end
    if type(scale) == "number" then
        self.GuiState.scale = math.clamp(scale, 0.62, 1.35)
    end
    if type(minimized) == "boolean" then
        self.GuiState.minimized = minimized
    end
    environment.__SliceHubBABFTControlCenterScale = self.GuiState.scale
    if not WRITE_FILE then
        return false
    end
    if not (ensureFolder("SH")
        and ensureFolder("SH/BABFT")
        and ensureFolder(self.StatsFolder)) then
        return false
    end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(self.GuiState)
    end)
    return ok and pcall(WRITE_FILE, self.GuiStatePath, encoded)
end

function Farm:CommitRuntime()
    if self.RuntimeCommitted then
        return
    end
    self.RuntimeCommitted = true
    self.Overall.runtimeSeconds = self.Overall.runtimeSeconds
        + self:Elapsed()
    self:SaveOverallStats()
end

function Farm:RegisterCompletedRun()
    local duration = self.CurrentRunStartedAt
            and math.max(0, os.clock() - self.CurrentRunStartedAt)
        or 0
    if duration > 0 then
        if not self.SessionFastestRun
            or duration < self.SessionFastestRun then
            self.SessionFastestRun = duration
        end
        if not self.Overall.fastestRunSeconds
            or duration < self.Overall.fastestRunSeconds then
            self.Overall.fastestRunSeconds = duration
        end
    end
    self.Overall.runs = self.Overall.runs + 1
    if self.LastRunReachedEnd then
        self.Overall.finishes = self.Overall.finishes + 1
    end
    self:SaveOverallStats()
end

function Farm:StatsSnapshot(view)
    local isOverall = view == "overall"
    local earned = self.SessionGoldEarned
    local runtime = self.Enabled
            and self:Elapsed()
        or self.SessionElapsedAtStop
    local runs = self.CompletedCycles
    local recoveries = self.FailedCycles
    local finishes = self.TreasureFinishes
    local fastest = self.SessionFastestRun
    local sessions = 1
    if isOverall then
        runtime = self.Overall.runtimeSeconds
            + (
                self.Enabled and not self.RuntimeCommitted
                    and self:Elapsed()
                or 0
            )
        runs = self.Overall.runs
        earned = self.Overall.gold
        recoveries = self.Overall.recoveries
        finishes = self.Overall.finishes
        fastest = self.Overall.fastestRunSeconds
        sessions = self.Overall.sessions
    end
    return {
        runtime = self:FormatDuration(runtime),
        runs = tostring(runs),
        gold = tostring(math.floor(earned)),
        average = tostring(runs > 0 and math.floor(earned / runs) or 0),
        fastest = fastest and self:FormatDuration(fastest) or "—",
        recoveries = tostring(recoveries),
        finishes = tostring(finishes),
        sessions = tostring(sessions),
    }
end

function Farm:UpdateStatsUI()
    if not self.UI.StatValues then
        return
    end
    local snapshot = self:StatsSnapshot(self.StatsView)
    local order = {
        "runtime",
        "runs",
        "gold",
        "average",
        "fastest",
        "recoveries",
        "finishes",
        "sessions",
    }
    for index, key in ipairs(order) do
        local valueLabel = self.UI.StatValues[index]
        if valueLabel then
            valueLabel.Text = snapshot[key]
        end
    end
end

function Farm:SetStatsView(view)
    self.StatsView = view == "overall" and "overall" or "session"
    if self.UI.SessionStatsTab then
        self.UI.SessionStatsTab.BackgroundColor3 =
            self.StatsView == "session"
                and Color3.fromRGB(35, 160, 190)
            or Color3.fromRGB(48, 61, 69)
    end
    if self.UI.OverallStatsTab then
        self.UI.OverallStatsTab.BackgroundColor3 =
            self.StatsView == "overall"
                and Color3.fromRGB(35, 160, 190)
            or Color3.fromRGB(48, 61, 69)
    end
    self:UpdateStatsUI()
end

function Farm:ResetOverallStats()
    self.Overall = {
        schemaVersion = 2,
        sessions = 0,
        runtimeSeconds = 0,
        runs = 0,
        gold = 0,
        recoveries = 0,
        finishes = 0,
        fastestRunSeconds = nil,
    }
    if self.Enabled then
        self.Overall.sessions = 1
        self.RuntimeCommitted = false
    end
    self:SaveOverallStats()
    self:UpdateStatsUI()
end

Farm:LoadOverallStats()
Farm:LoadGuiState()

function Farm:Gold()
    local data = LocalPlayer:FindFirstChild("Data")
    local object = data and data:FindFirstChild("Gold")
    if not object then
        return nil
    end
    local ok, value = pcall(function()
        return object.Value
    end)
    return ok and type(value) == "number" and value or nil
end

function Farm:TrackGold()
    local current = self:Gold()
    if type(current) ~= "number" then
        return
    end
    local previous = self.LastObservedGold
    self.LastObservedGold = current
    if type(previous) ~= "number" or not self.Enabled then
        return
    end
    local delta = current - previous
    if delta <= 0 then
        return
    end
    self.SessionGoldEarned = self.SessionGoldEarned + delta
    self.Overall.gold = self.Overall.gold + delta
    self.LastRunEarned = self.LastRunEarned + delta
    self:Record("gold_increased", {
        before = previous,
        after = current,
        earned = delta,
    })
    self:SaveOverallStats()
end

function Farm:Elapsed()
    return math.floor((os.clock() - self.StartedAt) * 10 + 0.5) / 10
end

function Farm:Stopped()
    return destroyRequested
        or self.Enabled ~= true
        or environment.SliceHubBABFTAutoFarmStop == true
end

function Farm:Record(kind, details)
    self.Events[#self.Events + 1] = {
        elapsedSeconds = self:Elapsed(),
        kind = tostring(kind),
        details = details or {},
    }
end

function Farm:SetStatus(text, tone)
    self.LastStatus = tostring(text)
    local label = self.UI.Status
    if label then
        label.Text = self.LastStatus
        label.TextColor3 = tone == "error"
                and Color3.fromRGB(255, 112, 122)
            or tone == "success"
                and Color3.fromRGB(91, 231, 150)
            or tone == "active"
                and Color3.fromRGB(65, 211, 240)
            or Color3.fromRGB(165, 184, 193)
    end
    self:RefreshUI()
end

function Farm:RefreshUI()
    local gold = self:Gold()
    if self.UI.Gold then
        self.UI.Gold.Text = tostring(gold or "—")
    end
    if self.UI.Earned then
        self.UI.Earned.Text = tostring(self.SessionGoldEarned)
    end
    if self.UI.Cycles then
        self.UI.Cycles.Text = tostring(self.CompletedCycles)
    end
    if self.UI.Mode then
        self.UI.Mode.Text = self.Enabled and "ACTIVE" or "READY"
        self.UI.Mode.TextColor3 = self.Enabled
                and Color3.fromRGB(91, 231, 150)
            or Color3.fromRGB(232, 241, 244)
    end
    if self.UI.Start then
        self.UI.Start.Text = self.Enabled and "STOP FARM"
            or (IS_PREMIUM and "START FARM" or "PREMIUM • START FARM")
        self.UI.Start.BackgroundColor3 = self.Enabled
                and Color3.fromRGB(174, 69, 83)
            or Color3.fromRGB(35, 168, 195)
    end
    self:UpdateStatsUI()
end

function Farm:Notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = tostring(title),
            Text = tostring(text),
            Duration = 8,
        })
    end)
end

function Farm:WaitUntil(predicate, timeoutSeconds)
    local deadline = os.clock() + timeoutSeconds
    repeat
        if self:Stopped() then
            return false, "stopped"
        end
        local ok, result = pcall(predicate)
        if ok and result then
            return true, result
        end
        task.wait(0.1)
    until os.clock() >= deadline
    return false, "timeout"
end

function Farm:Character()
    local character
    local humanoid
    local root
    local ok = self:WaitUntil(function()
        character = LocalPlayer.Character
        humanoid = character
            and character:FindFirstChildOfClass("Humanoid")
        root = character
            and character:FindFirstChild("HumanoidRootPart")
        return character and humanoid and root and humanoid.Health > 0
    end, self.Config.CharacterTimeoutSeconds)
    if ok then
        return character, humanoid, root
    end
    return nil, nil, nil
end

function Farm:RequestFunction()
    local direct = getGlobalFunction("request")
        or getGlobalFunction("http_request")
    if direct then
        return direct
    end
    local synObject = environment.syn
    return type(synObject) == "table"
        and type(synObject.request) == "function"
        and synObject.request
        or nil
end

function Farm:Webhook(title, description, color, fields, force)
    if self.Config.WebhookUrl == ""
        or (not force and self.Config.WebhookEnabled ~= true) then
        return false, "disabled"
    end
    local request = self:RequestFunction()
    if not request then
        return false, "request API unavailable"
    end
    if not tostring(self.Config.WebhookUrl):match(
        "^https://[^/]+/api/webhooks/"
    ) then
        return false, "invalid Discord webhook URL"
    end
    if not force
        and self.LastWebhookAt
        and os.clock() - self.LastWebhookAt < 4 then
        return false, "rate limited"
    end
    self.LastWebhookAt = os.clock()
    local payload = {
        allowed_mentions = {parse = {}},
        embeds = {{
            title = "SliceHub BABFT • " .. tostring(title),
            description = tostring(description or ""),
            color = color or 3458807,
            fields = fields or {},
            footer = {text = "v" .. SCRIPT_VERSION},
        }},
    }
    local ok, response = pcall(request, {
        Url = self.Config.WebhookUrl,
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode(payload),
    })
    if not ok then
        return false, tostring(response)
    end
    return true
end

function Farm:SummaryFields()
    local gold = self:Gold()
    return {
        {name = "Gold", value = tostring(gold or "—"), inline = true},
        {
            name = "Earned",
            value = tostring(
                self.SessionGoldEarned
            ),
            inline = true,
        },
        {
            name = "Runs",
            value = tostring(self.CompletedCycles),
            inline = true,
        },
        {
            name = "Checkpoint",
            value = tostring(self.Config.StopAtCheckpoint) .. "/10",
            inline = true,
        },
        {
            name = "Treasure",
            value = self.Config.VisitTreasureAtEnd and "ON" or "OFF",
            inline = true,
        },
        {
            name = "Runtime",
            value = tostring(self:Elapsed()) .. "s",
            inline = true,
        },
    }
end

function Farm:SaveSession()
    if self.Config.SaveSession ~= true or not WRITE_FILE then
        return false
    end
    local directory = PROBE_FOLDER
        .. "/"
        .. os.date("!%Y%m%d_%H%M%S")
        .. "_"
        .. tostring(game.PlaceId)
        .. "_autofarm"
    if not (probeFolderReady and ensureFolder(directory)) then
        return false
    end
    local data = {
        script = SCRIPT_NAME,
        version = SCRIPT_VERSION,
        placeId = game.PlaceId,
        placeVersion = game.PlaceVersion,
        elapsedSeconds = self:Elapsed(),
        status = self.LastStatus,
        currentGold = self:Gold(),
        startingGold = self.StartingGold,
        completedCycles = self.CompletedCycles,
        treasureFinishes = self.TreasureFinishes,
        failedCycles = self.FailedCycles,
        config = {
            MaxCycles = self.Config.MaxCycles,
            TargetGold = self.Config.TargetGold,
            StopAtCheckpoint = self.Config.StopAtCheckpoint,
            VisitTreasureAtEnd = self.Config.VisitTreasureAtEnd,
            StageDwellSeconds = self.Config.StageDwellSeconds,
            BetweenRunsSeconds = self.Config.BetweenRunsSeconds,
        },
        errors = self.Errors,
        events = self.Events,
    }
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if not ok then
        return false
    end
    return pcall(
        WRITE_FILE,
        directory .. "/autofarm_session.json",
        encoded
    )
end

function Farm:Preflight()
    table.clear(self.Checkpoints)
    local stages = Workspace:FindFirstChild("BoatStages")
    stages = stages and stages:FindFirstChild("NormalStages")
    if not stages then
        return false, "NormalStages was not found."
    end
    for index = 1, 10 do
        local cave = stages:FindFirstChild("CaveStage" .. tostring(index))
        local marker = cave and cave:FindFirstChild("DarknessPart")
        if not marker or not marker:IsA("BasePart") then
            return false, "CaveStage" .. tostring(index)
                .. ".DarknessPart is missing."
        end
        self.Checkpoints[index] = marker
    end
    local ending = stages:FindFirstChild("TheEnd")
    local chest = ending and ending:FindFirstChild("GoldenChest")
    self.Trigger = chest and chest:FindFirstChild("Trigger")
    if not self.Trigger or not self.Trigger:IsA("BasePart") then
        return false, "GoldenChest.Trigger is missing."
    end
    if type(self:Gold()) ~= "number" then
        return false, "LocalPlayer.Data.Gold is unavailable."
    end
    return true
end

function Farm:StableCamera()
    if self.Config.CameraComfortMode ~= true then
        return function() end
    end
    if self.CameraRestore then
        pcall(self.CameraRestore)
    end
    local camera = Workspace.CurrentCamera
    if not camera then
        return function() end
    end
    local oldType = camera.CameraType
    local oldSubject = camera.CameraSubject
    local frozen = camera.CFrame
    local connection
    local restored = false
    pcall(function()
        camera.CameraType = Enum.CameraType.Scriptable
    end)
    connection = RunService.RenderStepped:Connect(function()
        local current = Workspace.CurrentCamera
        if current then
            pcall(function()
                current.CameraType = Enum.CameraType.Scriptable
                current.CFrame = frozen
            end)
        end
    end)
    local function restore()
        if restored then
            return
        end
        restored = true
        if connection then
            connection:Disconnect()
        end
        local current = Workspace.CurrentCamera
        local character = LocalPlayer.Character
        local humanoid = character
            and character:FindFirstChildOfClass("Humanoid")
        if current then
            pcall(function()
                current.CameraSubject = humanoid or oldSubject
                current.CameraType = oldType
            end)
        end
        self.CameraRestore = nil
    end
    self.CameraRestore = restore
    return restore
end

function Farm:VisitCheckpoint(index)
    local _, _, root = self:Character()
    if not root then
        return false, "character unavailable"
    end
    local marker = self.Checkpoints[index]
    self:SetStatus("Running", "active")
    if self.UI.ActivityTitle then
        self.UI.ActivityTitle.Text = "River"
    end
    if self.UI.ActivityDetail then
        self.UI.ActivityDetail.Text = "Stage " .. tostring(index)
            .. " of " .. tostring(self.Config.StopAtCheckpoint)
    end
    if self.UI.RouteFill then
        TweenService:Create(
            self.UI.RouteFill,
            TweenInfo.new(0.28, Enum.EasingStyle.Quint),
            {
                Size = UDim2.fromScale(
                    index / math.max(self.Config.StopAtCheckpoint, 1),
                    1
                ),
            }
        ):Play()
    end
    root.CFrame = marker.CFrame * CFrame.new(0, 8, 0)
    local platform = Instance.new("Part")
    platform.Name = "SliceHubFarmSafetyPlatform"
    platform.Size = Vector3.new(12, 1, 12)
    platform.Transparency = 1
    platform.Anchored = true
    platform.CanCollide = true
    platform.CFrame = marker.CFrame * CFrame.new(0, 3, 0)
    platform.Parent = Workspace
    local deadline = os.clock() + self.Config.StageDwellSeconds
    while not self:Stopped() and os.clock() < deadline do
        task.wait(0.1)
    end
    if platform.Parent then
        platform:Destroy()
    end
    return not self:Stopped(), self:Stopped() and "stopped" or nil
end

function Farm:EnterTreasure()
    local restore = self:StableCamera()
    if self:Stopped() then
        restore()
        return false, "stopped"
    end
    local _, _, root = self:Character()
    if not root then
        restore()
        return false, "character unavailable"
    end
    self:SetStatus("Running", "active")
    if self.UI.ActivityTitle then
        self.UI.ActivityTitle.Text = "Finish"
    end
    if self.UI.ActivityDetail then
        self.UI.ActivityDetail.Text = "Endpoint"
    end
    root.CFrame = self.Trigger.CFrame
    local settleDeadline = os.clock()
        + math.max(1.25, self.Config.TreasureAttemptWaitSeconds)
    while not self:Stopped() and os.clock() < settleDeadline do
        task.wait(0.05)
    end
    restore()
    if self:Stopped() then
        return false, "stopped"
    end
    self.LastRunReachedEnd = true
    self.TreasureFinishes = self.TreasureFinishes + 1
    self:Record("treasure_endpoint_reached")
    return true, "endpoint"
end

function Farm:RunCycle(index)
    self:Record("cycle_started", {cycle = index})
    for checkpoint = 1, self.Config.StopAtCheckpoint do
        local ok, reason = self:VisitCheckpoint(checkpoint)
        if not ok then
            return false, reason
        end
    end
    if self.Config.StopAtCheckpoint < 10 then
        return true, "threshold"
    end
    if self.Config.VisitTreasureAtEnd ~= true then
        return true, "treasure disabled"
    end
    local entered, reason = self:EnterTreasure()
    if not entered then
        return false, reason
    end
    return true, "treasure reached"
end

function Farm:Recover(reason)
    self.FailedCycles = self.FailedCycles + 1
    self.LastFailure = tostring(reason)
    self.Errors[#self.Errors + 1] = {
        elapsedSeconds = self:Elapsed(),
        message = tostring(reason),
    }
    self.LastStatus = "Running"
    if self.UI.Status then
        self.UI.Status.Text = "Running"
        self.UI.Status.TextColor3 = Color3.fromRGB(65, 211, 240)
    end
    self.Overall.recoveries = self.Overall.recoveries + 1
    if self.UI.RouteFill then
        self.UI.RouteFill.Size = UDim2.fromScale(0, 1)
    end
    self:Webhook(
        "Farm recovered",
        "A run needed recovery; farming is continuing.",
        16753920,
        self:SummaryFields()
    )
    self:Record("automatic_recovery", {reason = tostring(reason)})
    self:SaveOverallStats()
    self:RefreshUI()
end

function Farm:Stop(reason)
    self.SessionElapsedAtStop = self:Elapsed()
    self.Enabled = false
    environment.SliceHubBABFTAutoFarmStop = true
    if self.CameraRestore then
        pcall(self.CameraRestore)
    end
    self:SetStatus("Stopped", nil)
    if self.UI.ActivityTitle then
        self.UI.ActivityTitle.Text = "River"
    end
    if self.UI.ActivityDetail then
        self.UI.ActivityDetail.Text = "—"
    end
    if self.UI.RouteFill then
        TweenService:Create(
            self.UI.RouteFill,
            TweenInfo.new(0.2, Enum.EasingStyle.Quint),
            {Size = UDim2.fromScale(0, 1)}
        ):Play()
    end
    self:Record("farm_stopped", {reason = reason or "user"})
    self:CommitRuntime()
    self:Webhook(
        "Farm stopped",
        "Stopped by user",
        10066329,
        self:SummaryFields()
    )
    self:SaveSession()
    self:RefreshUI()
end

function Farm:Start()
    if not requirePremium("Auto Farm") then
        self:SetStatus("Premium required", "error")
        self:RefreshUI()
        return false
    end
    if self.WorkerRunning or self.Enabled then
        self:Stop("Stopped by user")
        return
    end
    self:SanitizeConfig()
    self.Enabled = true
    self.WorkerRunning = true
    environment.SliceHubBABFTAutoFarmStop = false
    self.StartedAt = os.clock()
    self.StartingGold = self:Gold() or 0
    self.LastObservedGold = self.StartingGold
    self.SessionGoldEarned = 0
    self.CompletedCycles = 0
    self.TreasureFinishes = 0
    self.FailedCycles = 0
    self.Events = {}
    self.Errors = {}
    self.SessionFastestRun = nil
    self.SessionElapsedAtStop = 0
    self.CurrentRunStartedAt = nil
    self.LastRunEarned = 0
    self.LastRunReachedEnd = false
    self.RuntimeCommitted = false
    self.Overall.sessions = self.Overall.sessions + 1
    self:SaveOverallStats()
    self:SetStatus("Running", "active")
    self:Record("farm_started", {startingGold = self.StartingGold})
    self:Webhook(
        "Farm started",
        "Auto Farm is now running.",
        3447003,
        self:SummaryFields(),
        true
    )
    task.spawn(function()
        local cycle = 0
        while not self:Stopped() do
            local shortRetry = false
            local ready, preflightProblem = self:Preflight()
            if not ready then
                self:Recover(preflightProblem)
                shortRetry = true
            else
                if not self:Stopped() then
                    cycle = cycle + 1
                    self.CurrentRunStartedAt = os.clock()
                    self.LastRunEarned = 0
                    self.LastRunReachedEnd = false
                    local cycleOk, result = self:RunCycle(cycle)
                    if not cycleOk then
                        if not self:Stopped() then
                            self:Recover(result)
                            shortRetry = true
                        end
                    else
                        self.CompletedCycles = self.CompletedCycles + 1
                        self:RegisterCompletedRun()
                        self:SetStatus("Running", "active")
                        if self.UI.ActivityTitle then
                            self.UI.ActivityTitle.Text = "River"
                        end
                        if self.UI.ActivityDetail then
                            self.UI.ActivityDetail.Text = "Starting"
                        end
                        self:Record("cycle_completed", {
                            cycle = cycle,
                            result = result,
                            gold = self:Gold(),
                        })
                        self:Webhook(
                            "Run completed",
                            "Auto Farm completed another run.",
                            5763719,
                            self:SummaryFields()
                        )
                    end
                end
            end
            local deadline = os.clock()
                + (
                    (shortRetry or self.Config.FastRestart)
                        and 0.45
                    or self.Config.BetweenRunsSeconds
                )
            while not self:Stopped() and os.clock() < deadline do
                task.wait(0.1)
            end
        end
        self.WorkerRunning = false
        self:RefreshUI()
    end)
end

local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    or LocalPlayer:WaitForChild("PlayerGui", 10)
if not playerGui then
    warn("[" .. SCRIPT_NAME .. "] PlayerGui unavailable.")
    return
end

local previousGui = playerGui:FindFirstChild("SliceHubBABFTAutoBuildPreviewUI")
if previousGui then
    previousGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SliceHubBABFTAutoBuildPreviewUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 50020
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(
    Farm.GuiState.xScale,
    Farm.GuiState.xOffset,
    Farm.GuiState.yScale,
    Farm.GuiState.yOffset
)
panel.Size = UDim2.fromOffset(700, 790)
panel.BackgroundColor3 = Color3.fromRGB(16, 23, 29)
panel.BorderSizePixel = 0
panel.Active = true
panel.ClipsDescendants = true
panel.Parent = screenGui

local uiScale = Instance.new("UIScale")
uiScale.Scale = Farm.GuiState.scale
uiScale.Parent = panel

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(54, 201, 231)
panelStroke.Transparency = 0.25
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 46)
header.BackgroundColor3 = Color3.fromRGB(23, 34, 42)
header.BorderSizePixel = 0
header.Active = true
header.Parent = panel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 14)
headerCorner.Parent = header

local headerMask = Instance.new("Frame")
headerMask.Size = UDim2.new(1, 0, 0, 14)
headerMask.Position = UDim2.new(0, 0, 1, -14)
headerMask.BackgroundColor3 = header.BackgroundColor3
headerMask.BorderSizePixel = 0
headerMask.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.fromOffset(190, 46)
titleLabel.Position = UDim2.fromOffset(16, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Text = "SLICEHUB  •  BABFT"
titleLabel.TextColor3 = Color3.fromRGB(241, 248, 250)
titleLabel.TextSize = 16
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local versionLabel = Instance.new("TextLabel")
versionLabel.Size = UDim2.fromOffset(54, 46)
versionLabel.Position = UDim2.new(1, -146, 0, 0)
versionLabel.BackgroundTransparency = 1
versionLabel.Font = Enum.Font.GothamMedium
versionLabel.Text = "v" .. SCRIPT_VERSION
versionLabel.TextColor3 = Color3.fromRGB(105, 194, 213)
versionLabel.TextSize = 11
versionLabel.Parent = header

local tierBadge = Instance.new("TextLabel")
tierBadge.Size = UDim2.fromOffset(86, 24)
tierBadge.Position = UDim2.new(1, -170, 0, 11)
tierBadge.BackgroundColor3 = IS_PREMIUM and Color3.fromRGB(181, 131, 42) or Color3.fromRGB(63, 75, 82)
tierBadge.BorderSizePixel = 0
tierBadge.Font = Enum.Font.GothamBold
tierBadge.Text = USER_TIER
tierBadge.TextColor3 = Color3.fromRGB(244, 248, 250)
tierBadge.TextSize = 10
tierBadge.ZIndex = 20
tierBadge.Parent = header
local tierCorner = Instance.new("UICorner")
tierCorner.CornerRadius = UDim.new(0, 7)
tierCorner.Parent = tierBadge

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.Position = UDim2.new(1, -40, 0, 6)
closeButton.BackgroundColor3 = Color3.fromRGB(42, 54, 62)
closeButton.BorderSizePixel = 0
closeButton.AutoButtonColor = false
closeButton.Font = Enum.Font.GothamBold
closeButton.Text = "×"
closeButton.TextColor3 = Color3.fromRGB(230, 237, 240)
closeButton.TextSize = 20
closeButton.Parent = header

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 9)
closeCorner.Parent = closeButton

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.fromOffset(34, 34)
minimizeButton.Position = UDim2.new(1, -78, 0, 6)
minimizeButton.BackgroundColor3 = Color3.fromRGB(42, 54, 62)
minimizeButton.BorderSizePixel = 0
minimizeButton.AutoButtonColor = false
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.Text = "—"
minimizeButton.TextColor3 = Color3.fromRGB(230, 237, 240)
minimizeButton.TextSize = 18
minimizeButton.ZIndex = 20
minimizeButton.Parent = header
local minimizeCorner = Instance.new("UICorner")
minimizeCorner.CornerRadius = UDim.new(0, 9)
minimizeCorner.Parent = minimizeButton

local floatingButton = Instance.new("TextButton")
floatingButton.Name = "SliceHubReopen"
floatingButton.AnchorPoint = Vector2.new(0.5, 0.5)
floatingButton.Position = UDim2.new(
    Farm.GuiState.floatXScale,
    Farm.GuiState.floatXOffset,
    Farm.GuiState.floatYScale,
    Farm.GuiState.floatYOffset
)
floatingButton.Size = UDim2.fromOffset(52, 52)
floatingButton.BackgroundColor3 = Color3.fromRGB(24, 137, 164)
floatingButton.BorderSizePixel = 0
floatingButton.AutoButtonColor = false
floatingButton.Font = Enum.Font.GothamBold
floatingButton.Text = "SH"
floatingButton.TextColor3 = Color3.fromRGB(242, 249, 251)
floatingButton.TextSize = 14
floatingButton.Visible = false
floatingButton.ZIndex = 50
floatingButton.Parent = screenGui
local floatingCorner = Instance.new("UICorner")
floatingCorner.CornerRadius = UDim.new(0, 16)
floatingCorner.Parent = floatingButton

function Farm:Round(object, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 9)
    corner.Parent = object
    return object
end

function Farm:Label(parent, text, position, size, font, textSize, color)
    local object = Instance.new("TextLabel")
    object.BackgroundTransparency = 1
    object.Position = position
    object.Size = size
    object.Font = font or Enum.Font.Gotham
    object.Text = text
    object.TextColor3 = color or Color3.fromRGB(204, 218, 224)
    object.TextSize = textSize or 12
    object.TextXAlignment = Enum.TextXAlignment.Left
    object.TextTruncate = Enum.TextTruncate.AtEnd
    object.ZIndex = 7
    object.Parent = parent
    return object
end

function Farm:Button(parent, text, position, size, color)
    local object = Instance.new("TextButton")
    object.Position = position
    object.Size = size
    object.BackgroundColor3 = color or Color3.fromRGB(43, 57, 66)
    object.BorderSizePixel = 0
    object.AutoButtonColor = false
    object.Font = Enum.Font.GothamBold
    object.Text = text
    object.TextColor3 = Color3.fromRGB(242, 248, 250)
    object.TextSize = 12
    object.ZIndex = 7
    object.Parent = parent
    self:Round(object, 8)
    table.insert(guiConnections, object.MouseEnter:Connect(function()
        TweenService:Create(
            object,
            TweenInfo.new(0.16, Enum.EasingStyle.Quint),
            {BackgroundTransparency = 0.08}
        ):Play()
    end))
    table.insert(guiConnections, object.MouseLeave:Connect(function()
        TweenService:Create(
            object,
            TweenInfo.new(0.18, Enum.EasingStyle.Quint),
            {BackgroundTransparency = 0}
        ):Play()
    end))
    return object
end

function Farm:Card(parent, position, size)
    local object = Instance.new("Frame")
    object.Position = position
    object.Size = size
    object.BackgroundColor3 = Color3.fromRGB(22, 31, 38)
    object.BorderSizePixel = 0
    object.ZIndex = 6
    object.Parent = parent
    return self:Round(object, 10)
end

function Farm:Input(parent, key, labelText, position, width)
    self:Label(
        parent,
        labelText,
        position,
        UDim2.fromOffset(width or 184, 18),
        Enum.Font.GothamMedium,
        10,
        Color3.fromRGB(138, 160, 170)
    )
    local object = Instance.new("TextBox")
    object.Position = UDim2.fromOffset(
        position.X.Offset,
        position.Y.Offset + 21
    )
    object.Size = UDim2.fromOffset(width or 184, 34)
    object.BackgroundColor3 = Color3.fromRGB(31, 43, 51)
    object.BorderSizePixel = 0
    object.ClearTextOnFocus = false
    object.Font = Enum.Font.GothamSemibold
    object.Text = tostring(self.Config[key])
    object.TextColor3 = Color3.fromRGB(239, 246, 248)
    object.PlaceholderColor3 = Color3.fromRGB(115, 135, 144)
    object.TextSize = 12
    object.ZIndex = 7
    object.Parent = parent
    self:Round(object, 8)
    self.UI.Inputs = self.UI.Inputs or {}
    self.UI.Inputs[key] = object
    table.insert(guiConnections, object.FocusLost:Connect(function()
        self.Config[key] = tonumber(object.Text) or self.Config[key]
        self:SanitizeConfig()
        object.Text = tostring(self.Config[key])
    end))
    return object
end

function Farm:Toggle(parent, key, labelText, position, width)
    local object = self:Button(
        parent,
        "",
        position,
        UDim2.fromOffset(width or 190, 34),
        Color3.fromRGB(45, 58, 66)
    )
    local function refresh()
        object.Text = labelText .. "  •  "
            .. (self.Config[key] == true and "ON" or "OFF")
        object.BackgroundColor3 = self.Config[key] == true
                and Color3.fromRGB(31, 157, 116)
            or Color3.fromRGB(63, 75, 82)
    end
    refresh()
    table.insert(guiConnections, object.MouseButton1Click:Connect(function()
        self.Config[key] = not (self.Config[key] == true)
        refresh()
    end))
    return object
end

Farm.UI.FarmTab = Farm:Button(
    header,
    IS_PREMIUM and "AUTO FARM" or "AUTO FARM 🔒",
    UDim2.fromOffset(210, 8),
    UDim2.fromOffset(104, 30),
    Color3.fromRGB(35, 160, 190)
)
Farm.UI.FarmTab.ZIndex = 4
Farm.UI.BuildTab = Farm:Button(
    header,
    IS_PREMIUM and "AUTO BUILD" or "AUTO BUILD 🔒",
    UDim2.fromOffset(322, 8),
    UDim2.fromOffset(104, 30),
    Color3.fromRGB(48, 61, 69)
)
Farm.UI.BuildTab.ZIndex = 4
Farm.UI.SettingsTab = Farm:Button(
    header,
    "SETTINGS",
    UDim2.fromOffset(434, 8),
    UDim2.fromOffset(104, 30),
    Color3.fromRGB(48, 61, 69)
)
Farm.UI.SettingsTab.ZIndex = 4

Farm.UI.Page = Instance.new("Frame")
Farm.UI.Page.Name = "AutoFarmPage"
Farm.UI.Page.Position = UDim2.fromOffset(0, 46)
Farm.UI.Page.Size = UDim2.new(1, 0, 1, -46)
Farm.UI.Page.BackgroundColor3 = Color3.fromRGB(16, 23, 29)
Farm.UI.Page.BorderSizePixel = 0
Farm.UI.Page.ZIndex = 5
Farm.UI.Page.Parent = panel

Farm.UI.Hero = Farm:Card(
    Farm.UI.Page,
    UDim2.fromOffset(18, 18),
    UDim2.new(1, -36, 0, 122)
)
Farm:Label(
    Farm.UI.Hero,
    "AUTO GOLD FARM",
    UDim2.fromOffset(16, 12),
    UDim2.fromOffset(300, 24),
    Enum.Font.GothamBold,
    17,
    Color3.fromRGB(241, 248, 250)
)
Farm.UI.Status = Farm:Label(
    Farm.UI.Hero,
    "Stopped",
    UDim2.fromOffset(16, 38),
    UDim2.new(1, -210, 0, 22),
    Enum.Font.Gotham,
    11,
    Color3.fromRGB(165, 184, 193)
)
Farm.UI.Start = Farm:Button(
    Farm.UI.Hero,
    IS_PREMIUM and "START FARM" or "PREMIUM • START FARM",
    UDim2.new(1, -174, 0, 14),
    UDim2.fromOffset(158, 44),
    Color3.fromRGB(35, 168, 195)
)

Farm.UI.Metrics = {}
local farmMetricNames = {"GOLD", "EARNED", "RUNS", "MODE"}
for index, name in ipairs(farmMetricNames) do
    Farm:Label(
        Farm.UI.Hero,
        name,
        UDim2.new((index - 1) * 0.25, 16, 0, 70),
        UDim2.new(0.25, -20, 0, 14),
        Enum.Font.GothamMedium,
        9,
        Color3.fromRGB(119, 145, 156)
    )
    Farm.UI.Metrics[index] = Farm:Label(
        Farm.UI.Hero,
        "0",
        UDim2.new((index - 1) * 0.25, 16, 0, 86),
        UDim2.new(0.25, -20, 0, 24),
        Enum.Font.GothamBold,
        17,
        Color3.fromRGB(232, 241, 244)
    )
end
Farm.UI.Gold = Farm.UI.Metrics[1]
Farm.UI.Earned = Farm.UI.Metrics[2]
Farm.UI.Cycles = Farm.UI.Metrics[3]
Farm.UI.Mode = Farm.UI.Metrics[4]

Farm.UI.Settings = Farm:Card(
    Farm.UI.Page,
    UDim2.fromOffset(18, 152),
    UDim2.fromOffset(410, 474)
)
Farm:Label(
    Farm.UI.Settings,
    "RUN SETTINGS",
    UDim2.fromOffset(14, 12),
    UDim2.fromOffset(200, 20),
    Enum.Font.GothamBold,
    11,
    Color3.fromRGB(71, 211, 238)
)
Farm:Input(
    Farm.UI.Settings,
    "MaxCycles",
    "MAX CYCLES  •  0 = UNLIMITED",
    UDim2.fromOffset(14, 44),
    184
)
Farm:Input(
    Farm.UI.Settings,
    "TargetGold",
    "TARGET GOLD  •  0 = OFF",
    UDim2.fromOffset(212, 44),
    184
)
Farm:Input(
    Farm.UI.Settings,
    "StopAtCheckpoint",
    "STOP CHECKPOINT  •  1—10",
    UDim2.fromOffset(14, 112),
    184
)
Farm:Input(
    Farm.UI.Settings,
    "StageDwellSeconds",
    "STAGE DWELL  •  2—8 SEC",
    UDim2.fromOffset(212, 112),
    184
)
Farm:Input(
    Farm.UI.Settings,
    "BetweenRunsSeconds",
    "BETWEEN RUNS  •  1—60 SEC",
    UDim2.fromOffset(14, 180),
    184
)
Farm:Input(
    Farm.UI.Settings,
    "TreasureAttemptWaitSeconds",
    "ENDPOINT PAUSE  •  0.8—1.5 SEC",
    UDim2.fromOffset(212, 180),
    184
)
Farm:Label(
    Farm.UI.Settings,
    "BEHAVIOR",
    UDim2.fromOffset(14, 252),
    UDim2.fromOffset(200, 20),
    Enum.Font.GothamBold,
    11,
    Color3.fromRGB(71, 211, 238)
)
Farm:Toggle(
    Farm.UI.Settings,
    "VisitTreasureAtEnd",
    "VISIT TREASURE",
    UDim2.fromOffset(14, 278),
    184
)
Farm:Toggle(
    Farm.UI.Settings,
    "FastRestart",
    "FAST RESTART",
    UDim2.fromOffset(212, 278),
    184
)
Farm:Toggle(
    Farm.UI.Settings,
    "CameraComfortMode",
    "COMFORT CAMERA",
    UDim2.fromOffset(14, 322),
    184
)
Farm:Toggle(
    Farm.UI.Settings,
    "SaveSession",
    "SAVE SESSION DUMP",
    UDim2.fromOffset(212, 322),
    184
)
Farm:Label(
    Farm.UI.Settings,
    "Route: CaveStage1—10 DarknessPart → GoldenChest.Trigger\n"
        .. "Runs finish at the treasure endpoint; rewards remain manual.",
    UDim2.fromOffset(14, 374),
    UDim2.new(1, -28, 0, 54),
    Enum.Font.Gotham,
    10,
    Color3.fromRGB(143, 164, 173)
).TextWrapped = true

Farm.UI.Webhook = Farm:Card(
    Farm.UI.Page,
    UDim2.fromOffset(440, 152),
    UDim2.fromOffset(242, 474)
)
Farm:Label(
    Farm.UI.Webhook,
    "WEBHOOK",
    UDim2.fromOffset(14, 12),
    UDim2.fromOffset(150, 20),
    Enum.Font.GothamBold,
    11,
    Color3.fromRGB(71, 211, 238)
)
Farm:Label(
    Farm.UI.Webhook,
    "Discord URL stays local and is never written into session dumps.",
    UDim2.fromOffset(14, 40),
    UDim2.new(1, -28, 0, 42),
    Enum.Font.Gotham,
    10,
    Color3.fromRGB(143, 164, 173)
).TextWrapped = true

Farm.UI.WebhookInput = Instance.new("TextBox")
Farm.UI.WebhookInput.Position = UDim2.fromOffset(14, 92)
Farm.UI.WebhookInput.Size = UDim2.new(1, -28, 0, 66)
Farm.UI.WebhookInput.BackgroundColor3 = Color3.fromRGB(31, 43, 51)
Farm.UI.WebhookInput.BorderSizePixel = 0
Farm.UI.WebhookInput.ClearTextOnFocus = false
Farm.UI.WebhookInput.MultiLine = true
Farm.UI.WebhookInput.TextWrapped = true
Farm.UI.WebhookInput.Font = Enum.Font.Code
Farm.UI.WebhookInput.Text = ""
Farm.UI.WebhookInput.PlaceholderText = "Paste Discord webhook URL"
Farm.UI.WebhookInput.TextColor3 = Color3.fromRGB(229, 239, 242)
Farm.UI.WebhookInput.PlaceholderColor3 = Color3.fromRGB(105, 126, 136)
Farm.UI.WebhookInput.TextSize = 10
Farm.UI.WebhookInput.ZIndex = 7
Farm.UI.WebhookInput.Parent = Farm.UI.Webhook
Farm:Round(Farm.UI.WebhookInput, 8)

Farm.UI.WebhookToggle = Farm:Button(
    Farm.UI.Webhook,
    "WEBHOOK: OFF",
    UDim2.fromOffset(14, 170),
    UDim2.new(1, -28, 0, 36),
    Color3.fromRGB(63, 75, 82)
)
Farm.UI.WebhookTest = Farm:Button(
    Farm.UI.Webhook,
    "SEND TEST",
    UDim2.fromOffset(14, 216),
    UDim2.new(0.5, -19, 0, 36),
    Color3.fromRGB(35, 160, 190)
)
Farm.UI.WebhookClear = Farm:Button(
    Farm.UI.Webhook,
    "CLEAR",
    UDim2.new(0.5, 5, 0, 216),
    UDim2.new(0.5, -19, 0, 36),
    Color3.fromRGB(99, 63, 70)
)
Farm.UI.WebhookStatus = Farm:Label(
    Farm.UI.Webhook,
    "No webhook saved.",
    UDim2.fromOffset(14, 262),
    UDim2.new(1, -28, 0, 50),
    Enum.Font.Gotham,
    10,
    Color3.fromRGB(143, 164, 173)
)
Farm.UI.WebhookStatus.TextWrapped = true
Farm:Label(
    Farm.UI.Webhook,
    "EVENTS",
    UDim2.fromOffset(14, 326),
    UDim2.fromOffset(160, 18),
    Enum.Font.GothamBold,
    10,
    Color3.fromRGB(138, 160, 170)
)
Farm:Label(
    Farm.UI.Webhook,
    "• Farm start / stop\n• Cycle completed\n• Target reached\n"
        .. "• Failure summary\n\nRate limited: no checkpoint spam.",
    UDim2.fromOffset(14, 350),
    UDim2.new(1, -28, 0, 104),
    Enum.Font.Gotham,
    10,
    Color3.fromRGB(171, 188, 196)
).TextWrapped = true

-- Replace the prototype's crowded farm controls with a calm main page and
-- move advanced controls into their own Settings tab.
Farm.UI.Settings:Destroy()
Farm.UI.Webhook:Destroy()

Farm.UI.Activity = Farm:Card(
    Farm.UI.Page,
    UDim2.fromOffset(18, 152),
    UDim2.new(1, -36, 0, 190)
)
Farm:Label(
    Farm.UI.Activity,
    "CURRENT RUN",
    UDim2.fromOffset(18, 16),
    UDim2.fromOffset(220, 20),
    Enum.Font.GothamBold,
    10,
    Color3.fromRGB(99, 205, 227)
)
Farm.UI.ActivityTitle = Farm:Label(
    Farm.UI.Activity,
    "River",
    UDim2.fromOffset(18, 50),
    UDim2.new(1, -36, 0, 32),
    Enum.Font.GothamBold,
    21,
    Color3.fromRGB(241, 248, 250)
)
Farm.UI.ActivityDetail = Farm:Label(
    Farm.UI.Activity,
    "—",
    UDim2.fromOffset(18, 86),
    UDim2.new(1, -36, 0, 24),
    Enum.Font.Gotham,
    12,
    Color3.fromRGB(151, 173, 183)
)
Farm.UI.RouteBack = Instance.new("Frame")
Farm.UI.RouteBack.Position = UDim2.fromOffset(18, 132)
Farm.UI.RouteBack.Size = UDim2.new(1, -36, 0, 10)
Farm.UI.RouteBack.BackgroundColor3 = Color3.fromRGB(35, 47, 55)
Farm.UI.RouteBack.BorderSizePixel = 0
Farm.UI.RouteBack.ZIndex = 7
Farm.UI.RouteBack.Parent = Farm.UI.Activity
Farm:Round(Farm.UI.RouteBack, 10)
Farm.UI.RouteFill = Instance.new("Frame")
Farm.UI.RouteFill.Size = UDim2.fromScale(0, 1)
Farm.UI.RouteFill.BackgroundColor3 = Color3.fromRGB(49, 199, 228)
Farm.UI.RouteFill.BorderSizePixel = 0
Farm.UI.RouteFill.ZIndex = 8
Farm.UI.RouteFill.Parent = Farm.UI.RouteBack
Farm:Round(Farm.UI.RouteFill, 10)

Farm.UI.Session = Farm:Card(
    Farm.UI.Page,
    UDim2.fromOffset(18, 356),
    UDim2.new(1, -36, 0, 250)
)
Farm:Label(
    Farm.UI.Session,
    "STATISTICS",
    UDim2.fromOffset(18, 16),
    UDim2.fromOffset(180, 20),
    Enum.Font.GothamBold,
    10,
    Color3.fromRGB(99, 205, 227)
)
Farm.UI.SessionStatsTab = Farm:Button(
    Farm.UI.Session,
    "SESSION",
    UDim2.new(1, -220, 0, 10),
    UDim2.fromOffset(96, 30),
    Color3.fromRGB(35, 160, 190)
)
Farm.UI.OverallStatsTab = Farm:Button(
    Farm.UI.Session,
    "OVERALL",
    UDim2.new(1, -114, 0, 10),
    UDim2.fromOffset(96, 30),
    Color3.fromRGB(48, 61, 69)
)
Farm.UI.StatValues = {}
Farm.UI.StatNames = {}
local farmStatNames = {
    "RUNTIME",
    "RUNS",
    "GOLD",
    "AVG / RUN",
    "FASTEST",
    "RECOVERIES",
    "FINISHES",
    "SESSIONS",
}
for index, statName in ipairs(farmStatNames) do
    local column = (index - 1) % 4
    local row = math.floor((index - 1) / 4)
    local xScale = column * 0.25
    local yOffset = 58 + row * 86
    Farm.UI.StatNames[index] = Farm:Label(
        Farm.UI.Session,
        statName,
        UDim2.new(xScale, 18, 0, yOffset),
        UDim2.new(0.25, -24, 0, 16),
        Enum.Font.GothamMedium,
        9,
        Color3.fromRGB(119, 145, 156)
    )
    Farm.UI.StatValues[index] = Farm:Label(
        Farm.UI.Session,
        "0",
        UDim2.new(xScale, 18, 0, yOffset + 22),
        UDim2.new(0.25, -24, 0, 28),
        Enum.Font.GothamBold,
        16,
        Color3.fromRGB(232, 241, 244)
    )
end

Farm.UI.SettingsPage = Instance.new("Frame")
Farm.UI.SettingsPage.Name = "SettingsPage"
Farm.UI.SettingsPage.Position = UDim2.fromOffset(0, 46)
Farm.UI.SettingsPage.Size = UDim2.new(1, 0, 1, -46)
Farm.UI.SettingsPage.BackgroundColor3 = Color3.fromRGB(16, 23, 29)
Farm.UI.SettingsPage.BorderSizePixel = 0
Farm.UI.SettingsPage.ZIndex = 5
Farm.UI.SettingsPage.Visible = false
Farm.UI.SettingsPage.Parent = panel

Farm.UI.FarmPageScale = Instance.new("UIScale")
Farm.UI.FarmPageScale.Scale = 1
Farm.UI.FarmPageScale.Parent = Farm.UI.Page
Farm.UI.SettingsPageScale = Instance.new("UIScale")
Farm.UI.SettingsPageScale.Scale = 1
Farm.UI.SettingsPageScale.Parent = Farm.UI.SettingsPage

Farm.UI.Settings = Farm:Card(
    Farm.UI.SettingsPage,
    UDim2.fromOffset(18, 18),
    UDim2.fromOffset(410, 608)
)
Farm:Label(
    Farm.UI.Settings,
    "FARM SETTINGS",
    UDim2.fromOffset(16, 16),
    UDim2.fromOffset(220, 24),
    Enum.Font.GothamBold,
    15,
    Color3.fromRGB(241, 248, 250)
)
Farm:Label(
    Farm.UI.Settings,
    "RUN",
    UDim2.fromOffset(16, 42),
    UDim2.new(1, -32, 0, 20),
    Enum.Font.Gotham,
    10,
    Color3.fromRGB(139, 162, 172)
)
Farm:Input(
    Farm.UI.Settings,
    "StopAtCheckpoint",
    "LAST RIVER STAGE  •  1—10",
    UDim2.fromOffset(16, 86),
    182
)
Farm:Input(
    Farm.UI.Settings,
    "StageDwellSeconds",
    "STAGE PAUSE  •  2—8 SEC",
    UDim2.fromOffset(212, 86),
    182
)
Farm:Input(
    Farm.UI.Settings,
    "BetweenRunsSeconds",
    "NEXT RUN DELAY  •  1—60 SEC",
    UDim2.fromOffset(16, 158),
    182
)
Farm:Input(
    Farm.UI.Settings,
    "TreasureAttemptWaitSeconds",
    "ENDPOINT PAUSE  •  0.8—1.5 SEC",
    UDim2.fromOffset(212, 158),
    182
)
Farm:Label(
    Farm.UI.Settings,
    "BEHAVIOR",
    UDim2.fromOffset(16, 242),
    UDim2.fromOffset(180, 20),
    Enum.Font.GothamBold,
    10,
    Color3.fromRGB(99, 205, 227)
)
Farm:Toggle(
    Farm.UI.Settings,
    "VisitTreasureAtEnd",
    "VISIT TREASURE",
    UDim2.fromOffset(16, 272),
    182
)
Farm:Toggle(
    Farm.UI.Settings,
    "FastRestart",
    "FAST RESTART",
    UDim2.fromOffset(212, 272),
    182
)
Farm:Toggle(
    Farm.UI.Settings,
    "CameraComfortMode",
    "COMFORT CAMERA",
    UDim2.fromOffset(16, 318),
    182
)
Farm:Toggle(
    Farm.UI.Settings,
    "SaveSession",
    "SAVE SESSION",
    UDim2.fromOffset(212, 318),
    182
)
Farm:Label(
    Farm.UI.Settings,
    "DATA",
    UDim2.fromOffset(16, 386),
    UDim2.fromOffset(180, 20),
    Enum.Font.GothamBold,
    10,
    Color3.fromRGB(99, 205, 227)
)
Farm.UI.ResetStatsButton = Farm:Button(
    Farm.UI.Settings,
    "RESET OVERALL STATS",
    UDim2.fromOffset(16, 416),
    UDim2.fromOffset(182, 38),
    Color3.fromRGB(91, 63, 70)
)
Farm.UI.ResetStatsStatus = Farm:Label(
    Farm.UI.Settings,
    "",
    UDim2.fromOffset(212, 424),
    UDim2.fromOffset(182, 24),
    Enum.Font.GothamMedium,
    9,
    Color3.fromRGB(139, 162, 172)
)
Farm.UI.ShutdownButton = Farm:Button(
    Farm.UI.Settings,
    "SHUT DOWN",
    UDim2.fromOffset(16, 486),
    UDim2.fromOffset(182, 38),
    Color3.fromRGB(132, 62, 72)
)
Farm.UI.ShutdownStatus = Farm:Label(
    Farm.UI.Settings,
    "Stops the farm and closes SliceHub.",
    UDim2.fromOffset(212, 486),
    UDim2.fromOffset(182, 38),
    Enum.Font.GothamMedium,
    9,
    Color3.fromRGB(139, 162, 172)
)
Farm.UI.ShutdownStatus.TextWrapped = true

Farm.UI.Webhook = Farm:Card(
    Farm.UI.SettingsPage,
    UDim2.fromOffset(440, 18),
    UDim2.fromOffset(242, 608)
)
Farm:Label(
    Farm.UI.Webhook,
    "WEBHOOK",
    UDim2.fromOffset(14, 16),
    UDim2.fromOffset(180, 22),
    Enum.Font.GothamBold,
    15,
    Color3.fromRGB(241, 248, 250)
)
Farm:Label(
    Farm.UI.Webhook,
    "STATUS REPORTS",
    UDim2.fromOffset(14, 44),
    UDim2.new(1, -28, 0, 18),
    Enum.Font.Gotham,
    10,
    Color3.fromRGB(139, 162, 172)
)
Farm.UI.WebhookInput = Instance.new("TextBox")
Farm.UI.WebhookInput.Position = UDim2.fromOffset(14, 82)
Farm.UI.WebhookInput.Size = UDim2.new(1, -28, 0, 72)
Farm.UI.WebhookInput.BackgroundColor3 = Color3.fromRGB(31, 43, 51)
Farm.UI.WebhookInput.BorderSizePixel = 0
Farm.UI.WebhookInput.ClearTextOnFocus = false
Farm.UI.WebhookInput.MultiLine = true
Farm.UI.WebhookInput.TextWrapped = true
Farm.UI.WebhookInput.Font = Enum.Font.Code
Farm.UI.WebhookInput.Text = ""
Farm.UI.WebhookInput.PlaceholderText = "Paste Discord webhook URL"
Farm.UI.WebhookInput.TextColor3 = Color3.fromRGB(229, 239, 242)
Farm.UI.WebhookInput.PlaceholderColor3 = Color3.fromRGB(105, 126, 136)
Farm.UI.WebhookInput.TextSize = 10
Farm.UI.WebhookInput.ZIndex = 7
Farm.UI.WebhookInput.Parent = Farm.UI.Webhook
Farm:Round(Farm.UI.WebhookInput, 8)
Farm.UI.WebhookToggle = Farm:Button(
    Farm.UI.Webhook,
    "WEBHOOK: OFF",
    UDim2.fromOffset(14, 170),
    UDim2.new(1, -28, 0, 38),
    Color3.fromRGB(63, 75, 82)
)
Farm.UI.WebhookTest = Farm:Button(
    Farm.UI.Webhook,
    "SEND TEST",
    UDim2.fromOffset(14, 220),
    UDim2.new(0.5, -19, 0, 38),
    Color3.fromRGB(35, 160, 190)
)
Farm.UI.WebhookClear = Farm:Button(
    Farm.UI.Webhook,
    "CLEAR",
    UDim2.new(0.5, 5, 0, 220),
    UDim2.new(0.5, -19, 0, 38),
    Color3.fromRGB(91, 63, 70)
)
Farm.UI.WebhookStatus = Farm:Label(
    Farm.UI.Webhook,
    "No webhook saved.",
    UDim2.fromOffset(14, 276),
    UDim2.new(1, -28, 0, 56),
    Enum.Font.Gotham,
    10,
    Color3.fromRGB(143, 164, 173)
)
Farm.UI.WebhookStatus.TextWrapped = true
Farm:Label(
    Farm.UI.Webhook,
    "Start, run, recovery and stop events.",
    UDim2.fromOffset(14, 360),
    UDim2.new(1, -28, 0, 92),
    Enum.Font.Gotham,
    10,
    Color3.fromRGB(151, 171, 180)
).TextWrapped = true

Farm.UI.BottomStatus = Farm:Label(
    Farm.UI.Page,
    "DRAG THE CORNER TO RESIZE",
    UDim2.fromOffset(18, 642),
    UDim2.new(1, -36, 0, 22),
    Enum.Font.GothamMedium,
    10,
    Color3.fromRGB(109, 179, 195)
)

Farm.UI.ResizeHandle = Instance.new("TextButton")
Farm.UI.ResizeHandle.AnchorPoint = Vector2.new(1, 1)
Farm.UI.ResizeHandle.Position = UDim2.new(1, -5, 1, -5)
Farm.UI.ResizeHandle.Size = UDim2.fromOffset(28, 28)
Farm.UI.ResizeHandle.BackgroundTransparency = 1
Farm.UI.ResizeHandle.Font = Enum.Font.GothamBold
Farm.UI.ResizeHandle.Text = "◢"
Farm.UI.ResizeHandle.TextColor3 = Color3.fromRGB(68, 207, 235)
Farm.UI.ResizeHandle.TextSize = 18
Farm.UI.ResizeHandle.ZIndex = 30
Farm.UI.ResizeHandle.Parent = panel

local fileLabel = Instance.new("TextLabel")
fileLabel.Size = UDim2.fromOffset(120, 22)
fileLabel.Position = UDim2.fromOffset(18, 60)
fileLabel.BackgroundTransparency = 1
fileLabel.Font = Enum.Font.GothamSemibold
fileLabel.Text = "SELECTED FILE"
fileLabel.TextColor3 = Color3.fromRGB(164, 182, 190)
fileLabel.TextSize = 11
fileLabel.TextXAlignment = Enum.TextXAlignment.Left
fileLabel.Parent = panel

local fileButton = Instance.new("TextButton")
fileButton.Name = "FileDropdownButton"
fileButton.Size = UDim2.new(1, -180, 0, 38)
fileButton.Position = UDim2.fromOffset(18, 84)
fileButton.BackgroundColor3 = Color3.fromRGB(29, 40, 48)
fileButton.BorderSizePixel = 0
fileButton.AutoButtonColor = false
fileButton.Font = Enum.Font.Gotham
fileButton.Text = "No .Build files found  ▾"
fileButton.TextColor3 = Color3.fromRGB(224, 232, 235)
fileButton.TextSize = 13
fileButton.TextTruncate = Enum.TextTruncate.AtEnd
fileButton.Parent = panel

local fileButtonCorner = Instance.new("UICorner")
fileButtonCorner.CornerRadius = UDim.new(0, 9)
fileButtonCorner.Parent = fileButton

local refreshButton = Instance.new("TextButton")
refreshButton.Size = UDim2.fromOffset(132, 38)
refreshButton.Position = UDim2.new(1, -150, 0, 84)
refreshButton.BackgroundColor3 = Color3.fromRGB(37, 153, 182)
refreshButton.BorderSizePixel = 0
refreshButton.AutoButtonColor = false
refreshButton.Font = Enum.Font.GothamBold
refreshButton.Text = "Refresh Files"
refreshButton.TextColor3 = Color3.fromRGB(245, 250, 251)
refreshButton.TextSize = 12
refreshButton.Parent = panel

local refreshCorner = Instance.new("UICorner")
refreshCorner.CornerRadius = UDim.new(0, 9)
refreshCorner.Parent = refreshButton

local dropdown = Instance.new("ScrollingFrame")
dropdown.Name = "FileDropdown"
dropdown.Size = UDim2.new(1, -180, 0, 0)
dropdown.Position = UDim2.fromOffset(18, 124)
dropdown.BackgroundColor3 = Color3.fromRGB(24, 34, 42)
dropdown.BorderSizePixel = 0
dropdown.ScrollBarThickness = 4
dropdown.ScrollBarImageColor3 = Color3.fromRGB(65, 186, 211)
dropdown.CanvasSize = UDim2.fromOffset(0, 0)
dropdown.Visible = false
dropdown.ZIndex = 20
dropdown.ClipsDescendants = true
dropdown.Parent = panel

local dropdownCorner = Instance.new("UICorner")
dropdownCorner.CornerRadius = UDim.new(0, 9)
dropdownCorner.Parent = dropdown

local dropdownLayout = Instance.new("UIListLayout")
dropdownLayout.Padding = UDim.new(0, 3)
dropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
dropdownLayout.Parent = dropdown

local summaryFrame = Instance.new("Frame")
summaryFrame.Size = UDim2.new(1, -36, 0, 82)
summaryFrame.Position = UDim2.fromOffset(18, 136)
summaryFrame.BackgroundColor3 = Color3.fromRGB(22, 31, 38)
summaryFrame.BorderSizePixel = 0
summaryFrame.Parent = panel

local summaryCorner = Instance.new("UICorner")
summaryCorner.CornerRadius = UDim.new(0, 10)
summaryCorner.Parent = summaryFrame

local summaryLabels = {}
local summaryNames = {"PARTS", "TYPES", "BINDINGS", "STATUS"}
for index, name in ipairs(summaryNames) do
    local cell = Instance.new("Frame")
    cell.Size = UDim2.new(0.25, -8, 1, -16)
    cell.Position = UDim2.new((index - 1) * 0.25, 6, 0, 8)
    cell.BackgroundTransparency = 1
    cell.Parent = summaryFrame

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0, 20)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.Text = name
    nameLabel.TextColor3 = Color3.fromRGB(126, 149, 159)
    nameLabel.TextSize = 10
    nameLabel.Parent = cell

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(1, 0, 0, 34)
    valueLabel.Position = UDim2.fromOffset(0, 23)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.Text = "—"
    valueLabel.TextColor3 = Color3.fromRGB(230, 238, 241)
    valueLabel.TextSize = index == 4 and 12 or 20
    valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
    valueLabel.Parent = cell
    summaryLabels[index] = valueLabel
end

local materialsTitle = Instance.new("TextLabel")
materialsTitle.Size = UDim2.new(1, -36, 0, 24)
materialsTitle.Position = UDim2.fromOffset(18, 230)
materialsTitle.BackgroundTransparency = 1
materialsTitle.Font = Enum.Font.GothamSemibold
materialsTitle.Text = "REQUIRED MATERIALS"
materialsTitle.TextColor3 = Color3.fromRGB(164, 182, 190)
materialsTitle.TextSize = 11
materialsTitle.TextXAlignment = Enum.TextXAlignment.Left
materialsTitle.Parent = panel

local materialsList = Instance.new("ScrollingFrame")
materialsList.Size = UDim2.new(1, -36, 0, 166)
materialsList.Position = UDim2.fromOffset(18, 256)
materialsList.BackgroundColor3 = Color3.fromRGB(21, 29, 36)
materialsList.BorderSizePixel = 0
materialsList.ScrollBarThickness = 4
materialsList.ScrollBarImageColor3 = Color3.fromRGB(65, 186, 211)
materialsList.CanvasSize = UDim2.fromOffset(0, 0)
materialsList.Parent = panel

local materialsCorner = Instance.new("UICorner")
materialsCorner.CornerRadius = UDim.new(0, 10)
materialsCorner.Parent = materialsList

local materialsLayout = Instance.new("UIListLayout")
materialsLayout.Padding = UDim.new(0, 3)
materialsLayout.SortOrder = Enum.SortOrder.LayoutOrder
materialsLayout.Parent = materialsList

local opacityTitle = Instance.new("TextLabel")
opacityTitle.Size = UDim2.new(1, -110, 0, 20)
opacityTitle.Position = UDim2.fromOffset(18, 432)
opacityTitle.BackgroundTransparency = 1
opacityTitle.Font = Enum.Font.GothamSemibold
opacityTitle.Text = "PREVIEW OPACITY"
opacityTitle.TextColor3 = Color3.fromRGB(164, 182, 190)
opacityTitle.TextSize = 11
opacityTitle.TextXAlignment = Enum.TextXAlignment.Left
opacityTitle.Parent = panel

local opacityValue = Instance.new("TextLabel")
opacityValue.Size = UDim2.fromOffset(74, 20)
opacityValue.Position = UDim2.new(1, -92, 0, 432)
opacityValue.BackgroundTransparency = 1
opacityValue.Font = Enum.Font.GothamBold
opacityValue.TextColor3 = Color3.fromRGB(75, 213, 240)
opacityValue.TextSize = 11
opacityValue.TextXAlignment = Enum.TextXAlignment.Right
opacityValue.Parent = panel

local opacitySlider = Instance.new("Frame")
opacitySlider.Name = "PreviewOpacitySlider"
opacitySlider.Size = UDim2.new(1, -36, 0, 26)
opacitySlider.Position = UDim2.fromOffset(18, 452)
opacitySlider.BackgroundTransparency = 1
opacitySlider.Active = true
opacitySlider.Parent = panel

local opacityTrack = Instance.new("Frame")
opacityTrack.Size = UDim2.new(1, 0, 0, 8)
opacityTrack.Position = UDim2.fromOffset(0, 9)
opacityTrack.BackgroundColor3 = Color3.fromRGB(35, 47, 55)
opacityTrack.BorderSizePixel = 0
opacityTrack.Parent = opacitySlider

local opacityTrackCorner = Instance.new("UICorner")
opacityTrackCorner.CornerRadius = UDim.new(1, 0)
opacityTrackCorner.Parent = opacityTrack

local opacityFill = Instance.new("Frame")
opacityFill.Size = UDim2.fromScale(0, 1)
opacityFill.BackgroundColor3 = Color3.fromRGB(51, 203, 232)
opacityFill.BorderSizePixel = 0
opacityFill.Parent = opacityTrack

local opacityFillCorner = Instance.new("UICorner")
opacityFillCorner.CornerRadius = UDim.new(1, 0)
opacityFillCorner.Parent = opacityFill

local opacityKnob = Instance.new("Frame")
opacityKnob.AnchorPoint = Vector2.new(0.5, 0.5)
opacityKnob.Size = UDim2.fromOffset(16, 16)
opacityKnob.Position = UDim2.fromScale(0, 0.5)
opacityKnob.BackgroundColor3 = Color3.fromRGB(237, 249, 252)
opacityKnob.BorderSizePixel = 0
opacityKnob.Parent = opacityTrack

local opacityKnobCorner = Instance.new("UICorner")
opacityKnobCorner.CornerRadius = UDim.new(1, 0)
opacityKnobCorner.Parent = opacityKnob

local opacityKnobStroke = Instance.new("UIStroke")
opacityKnobStroke.Color = Color3.fromRGB(35, 160, 190)
opacityKnobStroke.Thickness = 2
opacityKnobStroke.Parent = opacityKnob

local function updateOpacityUi()
    local ratio = (previewOpacity - MIN_PREVIEW_OPACITY)
        / (MAX_PREVIEW_OPACITY - MIN_PREVIEW_OPACITY)
    ratio = math.clamp(ratio, 0, 1)
    opacityFill.Size = UDim2.fromScale(ratio, 1)
    opacityKnob.Position = UDim2.fromScale(ratio, 0.5)
    opacityValue.Text = tostring(
        math.floor(previewOpacity * 100 + 0.5)
    ) .. "%"
end

local function setPreviewOpacityFromX(screenX, immediate)
    local width = math.max(opacitySlider.AbsoluteSize.X, 1)
    local ratio = math.clamp(
        (screenX - opacitySlider.AbsolutePosition.X) / width,
        0,
        1
    )
    previewOpacity = MIN_PREVIEW_OPACITY
        + ratio * (MAX_PREVIEW_OPACITY - MIN_PREVIEW_OPACITY)
    previewOpacity = math.floor(previewOpacity * 100 + 0.5) / 100
    environment.__SliceHubBABFTPreviewOpacity = previewOpacity
    updateOpacityUi()
    queuePreviewOpacityApply(immediate)
end

updateOpacityUi()

local walkableLabel = Instance.new("TextLabel")
walkableLabel.Size = UDim2.new(1, -180, 0, 34)
walkableLabel.Position = UDim2.fromOffset(18, 482)
walkableLabel.BackgroundTransparency = 1
walkableLabel.Font = Enum.Font.GothamSemibold
walkableLabel.Text = "WALKABLE PREVIEW  •  FULL PREVIEWS ONLY"
walkableLabel.TextColor3 = Color3.fromRGB(164, 182, 190)
walkableLabel.TextSize = 11
walkableLabel.TextXAlignment = Enum.TextXAlignment.Left
walkableLabel.Parent = panel

local walkableButton = Instance.new("TextButton")
walkableButton.Size = UDim2.fromOffset(144, 30)
walkableButton.Position = UDim2.new(1, -162, 0, 484)
walkableButton.BorderSizePixel = 0
walkableButton.AutoButtonColor = false
walkableButton.Font = Enum.Font.GothamBold
walkableButton.TextColor3 = Color3.fromRGB(240, 247, 249)
walkableButton.TextSize = 11
walkableButton.Parent = panel

local walkableCorner = Instance.new("UICorner")
walkableCorner.CornerRadius = UDim.new(0, 8)
walkableCorner.Parent = walkableButton

local function updateWalkableUi()
    walkableButton.Text = walkablePreview and "WALKABLE: ON" or "WALKABLE: OFF"
    walkableButton.BackgroundColor3 = walkablePreview
            and Color3.fromRGB(39, 157, 109)
        or Color3.fromRGB(61, 72, 79)
end

updateWalkableUi()

local previewButton = Instance.new("TextButton")
previewButton.Size = UDim2.new(0.5, -27, 0, 40)
previewButton.Position = UDim2.fromOffset(18, 524)
previewButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
previewButton.BorderSizePixel = 0
previewButton.AutoButtonColor = false
previewButton.Font = Enum.Font.GothamBold
previewButton.Text = "Preview Build"
previewButton.TextColor3 = Color3.fromRGB(244, 250, 251)
previewButton.TextSize = 13
previewButton.Parent = panel

local previewCorner = Instance.new("UICorner")
previewCorner.CornerRadius = UDim.new(0, 9)
previewCorner.Parent = previewButton

local removeButton = Instance.new("TextButton")
removeButton.Size = UDim2.new(0.5, -27, 0, 40)
removeButton.Position = UDim2.new(0.5, 9, 0, 524)
removeButton.BackgroundColor3 = Color3.fromRGB(61, 72, 79)
removeButton.BorderSizePixel = 0
removeButton.AutoButtonColor = false
removeButton.Font = Enum.Font.GothamBold
removeButton.Text = "Remove Preview"
removeButton.TextColor3 = Color3.fromRGB(230, 236, 239)
removeButton.TextSize = 13
removeButton.Parent = panel

local removeCorner = Instance.new("UICorner")
removeCorner.CornerRadius = UDim.new(0, 9)
removeCorner.Parent = removeButton

local protocolFrame = Instance.new("Frame")
protocolFrame.Size = UDim2.new(1, -36, 0, 106)
protocolFrame.Position = UDim2.fromOffset(18, 574)
protocolFrame.BackgroundColor3 = Color3.fromRGB(21, 29, 36)
protocolFrame.BorderSizePixel = 0
protocolFrame.Parent = panel

local protocolCorner = Instance.new("UICorner")
protocolCorner.CornerRadius = UDim.new(0, 10)
protocolCorner.Parent = protocolFrame

local protocolTitle = Instance.new("TextLabel")
protocolTitle.Size = UDim2.new(1, -20, 0, 24)
protocolTitle.Position = UDim2.fromOffset(10, 5)
protocolTitle.BackgroundTransparency = 1
protocolTitle.Font = Enum.Font.GothamBold
protocolTitle.Text = "CONTROLLED BLUEPRINT FIDELITY TEST"
protocolTitle.TextColor3 = Color3.fromRGB(75, 213, 240)
protocolTitle.TextSize = 11
protocolTitle.TextXAlignment = Enum.TextXAlignment.Left
protocolTitle.Parent = protocolFrame

local testBlockLabel = Instance.new("TextLabel")
testBlockLabel.Size = UDim2.new(0.5, -15, 0, 22)
testBlockLabel.Position = UDim2.fromOffset(10, 30)
testBlockLabel.BackgroundTransparency = 1
testBlockLabel.Font = Enum.Font.Gotham
testBlockLabel.Text = "TEST MODE  •  ONE FIDELITY-RICH PART"
testBlockLabel.TextColor3 = Color3.fromRGB(215, 227, 232)
testBlockLabel.TextSize = 11
testBlockLabel.TextXAlignment = Enum.TextXAlignment.Left
testBlockLabel.Parent = protocolFrame

local targetLabel = Instance.new("TextLabel")
targetLabel.Size = UDim2.new(0.5, -15, 0, 22)
targetLabel.Position = UDim2.new(0.5, 5, 0, 30)
targetLabel.BackgroundTransparency = 1
targetLabel.Font = Enum.Font.Gotham
targetLabel.Text = "TARGET  •  TEAM ZONE CENTER"
targetLabel.TextColor3 = Color3.fromRGB(215, 227, 232)
targetLabel.TextSize = 11
targetLabel.TextXAlignment = Enum.TextXAlignment.Left
targetLabel.Parent = protocolFrame

local verificationLabel = Instance.new("TextLabel")
verificationLabel.Size = UDim2.new(1, -20, 0, 22)
verificationLabel.Position = UDim2.fromOffset(10, 54)
verificationLabel.BackgroundTransparency = 1
verificationLabel.Font = Enum.Font.Gotham
verificationLabel.Text = "VERIFICATION  •  IDLE"
verificationLabel.TextColor3 = Color3.fromRGB(164, 182, 190)
verificationLabel.TextSize = 11
verificationLabel.TextTruncate = Enum.TextTruncate.AtEnd
verificationLabel.TextXAlignment = Enum.TextXAlignment.Left
verificationLabel.Parent = protocolFrame

local protocolWarning = Instance.new("TextLabel")
protocolWarning.Size = UDim2.new(1, -20, 0, 20)
protocolWarning.Position = UDim2.fromOffset(10, 78)
protocolWarning.BackgroundTransparency = 1
protocolWarning.Font = Enum.Font.GothamMedium
protocolWarning.Text =
    "CANONICAL REMOTES • NO TOOL EQUIP • VERIFY • NO RETRY"
protocolWarning.TextColor3 = Color3.fromRGB(255, 186, 98)
protocolWarning.TextSize = 10
protocolWarning.TextXAlignment = Enum.TextXAlignment.Left
protocolWarning.Parent = protocolFrame

local placeTestButton = Instance.new("TextButton")
placeTestButton.Size = UDim2.new(0.5, -27, 0, 40)
placeTestButton.Position = UDim2.fromOffset(18, 690)
placeTestButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
placeTestButton.BorderSizePixel = 0
placeTestButton.AutoButtonColor = false
placeTestButton.Font = Enum.Font.GothamBold
placeTestButton.Text = IS_PREMIUM and "Test Blueprint Fidelity" or "Premium • Build Test Locked"
placeTestButton.TextColor3 = Color3.fromRGB(244, 250, 251)
placeTestButton.TextSize = 13
placeTestButton.Parent = panel

local placeTestCorner = Instance.new("UICorner")
placeTestCorner.CornerRadius = UDim.new(0, 9)
placeTestCorner.Parent = placeTestButton

local stopTestButton = Instance.new("TextButton")
stopTestButton.Size = UDim2.new(0.25, -23, 0, 40)
stopTestButton.Position = UDim2.new(0.5, 9, 0, 690)
stopTestButton.BackgroundColor3 = Color3.fromRGB(61, 72, 79)
stopTestButton.BorderSizePixel = 0
stopTestButton.AutoButtonColor = false
stopTestButton.Font = Enum.Font.GothamBold
stopTestButton.Text = "Stop Test"
stopTestButton.TextColor3 = Color3.fromRGB(230, 236, 239)
stopTestButton.TextSize = 12
stopTestButton.Parent = panel

local stopTestCorner = Instance.new("UICorner")
stopTestCorner.CornerRadius = UDim.new(0, 9)
stopTestCorner.Parent = stopTestButton

local saveDumpButton = Instance.new("TextButton")
saveDumpButton.Size = UDim2.new(0.25, -23, 0, 40)
saveDumpButton.Position = UDim2.new(0.75, 5, 0, 690)
saveDumpButton.BackgroundColor3 = Color3.fromRGB(61, 72, 79)
saveDumpButton.BorderSizePixel = 0
saveDumpButton.AutoButtonColor = false
saveDumpButton.Font = Enum.Font.GothamBold
saveDumpButton.Text = "Save Dump"
saveDumpButton.TextColor3 = Color3.fromRGB(230, 236, 239)
saveDumpButton.TextSize = 12
saveDumpButton.Parent = panel

local saveDumpCorner = Instance.new("UICorner")
saveDumpCorner.CornerRadius = UDim.new(0, 9)
saveDumpCorner.Parent = saveDumpButton

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -36, 0, 20)
statusLabel.Position = UDim2.fromOffset(18, 738)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = "READY • CONTROLLED FIDELITY TEST"
statusLabel.TextColor3 = Color3.fromRGB(116, 185, 200)
statusLabel.TextSize = 11
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = panel

local progressBack = Instance.new("Frame")
progressBack.Size = UDim2.new(1, -36, 0, 6)
progressBack.Position = UDim2.fromOffset(18, 764)
progressBack.BackgroundColor3 = Color3.fromRGB(35, 47, 55)
progressBack.BorderSizePixel = 0
progressBack.Parent = panel

local progressBackCorner = Instance.new("UICorner")
progressBackCorner.CornerRadius = UDim.new(1, 0)
progressBackCorner.Parent = progressBack

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.BackgroundColor3 = Color3.fromRGB(51, 203, 232)
progressFill.BorderSizePixel = 0
progressFill.Parent = progressBack

local progressCorner = Instance.new("UICorner")
progressCorner.CornerRadius = UDim.new(1, 0)
progressCorner.Parent = progressFill

local function setStatus(text, tone)
    statusLabel.Text = tostring(text)
    if tone == "error" then
        statusLabel.TextColor3 = Color3.fromRGB(255, 114, 114)
    elseif tone == "success" then
        statusLabel.TextColor3 = Color3.fromRGB(96, 231, 148)
    elseif tone == "active" then
        statusLabel.TextColor3 = Color3.fromRGB(75, 213, 240)
    else
        statusLabel.TextColor3 = Color3.fromRGB(116, 185, 200)
    end
end

local function setProgress(value)
    progressFill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
end

local function setPlacementTesting(active)
    placementTesting = active == true
    placeTestButton.BackgroundColor3 = placementTesting
            and Color3.fromRGB(61, 72, 79)
        or Color3.fromRGB(35, 160, 190)
    stopTestButton.BackgroundColor3 = placementTesting
            and Color3.fromRGB(153, 71, 82)
        or Color3.fromRGB(61, 72, 79)
end

local function getPlacedBlockCount(blockName)
    local blocks = Workspace:FindFirstChild("Blocks")
    local playerFolder = blocks
        and blocks:FindFirstChild(LocalPlayer.Name)
    if not playerFolder then
        return 0
    end

    local count = 0
    for _, child in ipairs(playerFolder:GetChildren()) do
        if child.Name == blockName then
            count = count + 1
        end
    end
    return count
end

local function getInventorySnapshot(blockName)
    local dataRoot = LocalPlayer:FindFirstChild("Data")
    local dataObject = dataRoot and dataRoot:FindFirstChild(blockName)
    local usedObject = dataObject and dataObject:FindFirstChild("Used")
    if not dataObject or not dataObject:IsA("ValueBase") then
        return nil, "Data." .. blockName .. " is unavailable."
    end
    if not usedObject or not usedObject:IsA("ValueBase") then
        return nil, "Data." .. blockName .. ".Used is unavailable."
    end

    local total = tonumber(dataObject.Value)
    local used = tonumber(usedObject.Value)
    if not total or not used then
        return nil, "Inventory values are not numeric."
    end

    return {
        total = total,
        used = used,
        available = total - used,
        placedCount = getPlacedBlockCount(blockName),
    }
end

local function findBuildingToolRemote()
    local containers = {
        LocalPlayer.Character,
        LocalPlayer:FindFirstChildOfClass("Backpack"),
        game:GetService("StarterPack"),
    }
    for _, container in ipairs(containers) do
        local tool = container and container:FindFirstChild("BuildingTool")
        local remote = tool and tool:FindFirstChild("RF")
        if remote and remote:IsA("RemoteFunction") then
            return remote
        end
    end
    return nil
end

local function snapshotText(snapshot)
    if not snapshot then
        return "unavailable"
    end
    return "available "
        .. tostring(snapshot.available)
        .. " • used "
        .. tostring(snapshot.used)
        .. " • placed "
        .. tostring(snapshot.placedCount)
end

local function safeResultValue(value)
    local valueType = typeof(value)
    if valueType == "nil" then
        return nil
    end
    if valueType == "boolean"
        or valueType == "number"
        or valueType == "string" then
        return value
    end
    return "<" .. valueType .. ">"
end

local function beginPlacementTest()
    if not requirePremium("Auto Build / Placement Test") then
        setStatus("PREMIUM LOCK • analysis and ghost preview remain available.", "error")
        return false
    end
    if placementTesting then
        setStatus("One-block test is already running.", "active")
        return
    end

    local baseline, snapshotProblem =
        getInventorySnapshot(TEST_BLOCK_NAME)
    if not baseline then
        setStatus(snapshotProblem, "error")
        return
    end
    if baseline.available < 1 then
        setStatus("You need at least 1 WoodBlock for this test.", "error")
        return
    end

    local buildZone = findTeamBuildZone(
        LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    )
    if not buildZone then
        setStatus("Could not locate your team's buildable zone.", "error")
        return
    end

    local template = BuildingParts
        and BuildingParts:FindFirstChild(TEST_BLOCK_NAME)
    local primaryPart = getTemplateBasePart(template)
    if not template or not primaryPart then
        setStatus("WoodBlock template is unavailable.", "error")
        return
    end

    local remote = findBuildingToolRemote()
    if not remote then
        setStatus(
            "BuildingTool.RF is unavailable • equip/rejoin and retry.",
            "error"
        )
        return
    end

    local dataRoot = LocalPlayer:FindFirstChild("Data")
    local dataObject = dataRoot and dataRoot:FindFirstChild(TEST_BLOCK_NAME)
    if not dataObject then
        setStatus("WoodBlock inventory data disappeared.", "error")
        return
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local buildGui = playerGui and playerGui:FindFirstChild("BuildGui")
    local inventoryFrame = buildGui
        and buildGui:FindFirstChild("InventoryFrame")
    local moreFrame = inventoryFrame
        and inventoryFrame:FindFirstChild("MoreFrame")
    local anchorBlock = moreFrame
        and moreFrame:FindFirstChild("AnchorBlock")
    local anchorValue = anchorBlock
        and anchorBlock:FindFirstChild("Anchor")
    if not anchorValue
        or not anchorValue:IsA("ValueBase")
        or type(anchorValue.Value) ~= "boolean" then
        setStatus("BuildGui Anchor Block setting is unavailable.", "error")
        return
    end
    local anchorSetting = anchorValue.Value

    local anchorCFrame = CFrame.lookAt(
        (
            buildZone.CFrame
                * CFrame.new(0, buildZone.Size.Y * 0.5, 0)
        ).Position,
        (
            buildZone.CFrame
                * CFrame.new(0, buildZone.Size.Y * 0.5, -1)
        ).Position
    )
    local templateRotation =
        primaryPart.CFrame - primaryPart.CFrame.Position
    local testCFrame = anchorCFrame
        * CFrame.new(0, primaryPart.Size.Y * 0.5 + 0.05, 0)
        * templateRotation
    local relativeCFrame = buildZone.CFrame:ToObjectSpace(testCFrame)

    placementGeneration = placementGeneration + 1
    local generation = placementGeneration
    setPlacementTesting(true)
    setProgress(0.1)
    verificationLabel.Text = "VERIFICATION  •  BASELINE  "
        .. snapshotText(baseline)
    verificationLabel.TextColor3 = Color3.fromRGB(75, 213, 240)
    setStatus(
        "Calling native BuildingTool protocol once • "
            .. TEST_BLOCK_NAME,
        "active"
    )

    latestProtocolDump = {
        schemaVersion = 1,
        probeVersion = SCRIPT_VERSION,
        placeId = game.PlaceId,
        placeVersion = game.PlaceVersion,
        selectedBlueprint = selectedAnalysis
                and selectedAnalysis.fileName
            or nil,
        blockName = TEST_BLOCK_NAME,
        target = {
            zoneName = buildZone.Name,
            mode = "team-zone-center",
            position = string.format(
                "%.4f, %.4f, %.4f",
                testCFrame.Position.X,
                testCFrame.Position.Y,
                testCFrame.Position.Z
            ),
        },
        protocol = {
            remote = "BuildingTool.RF",
            callCount = 1,
            automaticRetries = 0,
            anchorSetting = anchorSetting,
            secondaryArgument = false,
            arguments = {
                "blockName",
                "inventoryTotal",
                "targetPart",
                "targetRelativeCFrame",
                "anchorSetting",
                "primaryPartCFrame",
                "secondaryPartCFrameOrFalse",
            },
        },
        baseline = baseline,
        outcome = "running",
    }
    saveDumpButton.BackgroundColor3 = Color3.fromRGB(61, 72, 79)

    task.spawn(function()
        -- This is the only real placement call in v0.1.6.2.
        local callOk, callResult = pcall(function()
            return remote:InvokeServer(
                TEST_BLOCK_NAME,
                dataObject.Value,
                buildZone,
                relativeCFrame,
                anchorSetting,
                testCFrame,
                false
            )
        end)

        if destroyRequested or generation ~= placementGeneration then
            return
        end

        latestProtocolDump.remoteCall = {
            completed = callOk,
            returnType = callOk and typeof(callResult) or "error",
            returnValue = callOk
                    and safeResultValue(callResult)
                or tostring(callResult),
        }

        if not callOk then
            latestProtocolDump.outcome = "remote-error"
            latestProtocolDump.error = tostring(callResult)
            latestProtocolDump.after = getInventorySnapshot(TEST_BLOCK_NAME)
            setPlacementTesting(false)
            setProgress(0)
            saveDumpButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
            verificationLabel.Text = "VERIFICATION  •  REMOTE ERROR"
            verificationLabel.TextColor3 = Color3.fromRGB(255, 114, 114)
            setStatus(
                "BuildingTool.RF failed: " .. tostring(callResult),
                "error"
            )
            return
        end

        setProgress(0.45)
        setStatus(
            "Protocol returned • verifying inventory + spawned block…",
            "active"
        )

        local deadline = os.clock() + TEST_VERIFY_TIMEOUT
        local after = nil
        local signals = nil
        repeat
            after = getInventorySnapshot(TEST_BLOCK_NAME)
            if after then
                signals = {
                    usedIncreased = after.used > baseline.used,
                    availableDecreased =
                        after.available < baseline.available,
                    placedModelIncreased =
                        after.placedCount > baseline.placedCount,
                }
                verificationLabel.Text = "VERIFICATION  •  "
                    .. snapshotText(after)
                if signals.usedIncreased
                    and signals.availableDecreased
                    and signals.placedModelIncreased then
                    break
                end
            end
            task.wait(0.1)
        until destroyRequested
            or generation ~= placementGeneration
            or os.clock() >= deadline

        if destroyRequested or generation ~= placementGeneration then
            return
        end

        local verified = signals
            and signals.usedIncreased
            and signals.availableDecreased
            and signals.placedModelIncreased
            or false
        latestProtocolDump.after = after
        latestProtocolDump.signals = signals or {}
        latestProtocolDump.verified = verified
        latestProtocolDump.outcome =
            verified and "verified" or "verification-timeout"

        setPlacementTesting(false)
        saveDumpButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
        if verified then
            setProgress(1)
            verificationLabel.Text = "VERIFICATION  •  PASS  •  "
                .. snapshotText(after)
            verificationLabel.TextColor3 = Color3.fromRGB(96, 231, 148)
            setStatus(
                "PASS • exactly one call • inventory + block confirmed.",
                "success"
            )
        else
            setProgress(0)
            verificationLabel.Text = "VERIFICATION  •  TIMEOUT  •  "
                .. snapshotText(after)
            verificationLabel.TextColor3 = Color3.fromRGB(255, 114, 114)
            setStatus(
                "Protocol returned, but all 3 placement signals did not confirm.",
                "error"
            )
        end
    end)
end

controller.BeginTenPartBuildTest = function()
    if placementTesting then
        setStatus("A controlled build test is already running.", "active")
        return
    end
    if not selectedAnalysis or not selectedAnalysis.valid then
        setStatus("Select a valid .Build file first.", "error")
        return
    end
    if not selectedAnalysis.boundsMin or not selectedAnalysis.boundsMax then
        setStatus("Blueprint bounds are unavailable.", "error")
        return
    end

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local buildZone = findTeamBuildZone(root)
    if not buildZone then
        setStatus("Could not locate your team's buildable zone.", "error")
        return
    end

    local anchorCFrame, baseTopOffset = findPreviewAnchor()
    if not anchorCFrame then
        setStatus("Could not resolve the build-zone center.", "error")
        return
    end

    local remote = findBuildingToolRemote()
    if not remote then
        setStatus(
            "BuildingTool.RF is unavailable • equip/rejoin and retry.",
            "error"
        )
        return
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local buildGui = playerGui and playerGui:FindFirstChild("BuildGui")
    local inventoryFrame = buildGui
        and buildGui:FindFirstChild("InventoryFrame")
    local moreFrame = inventoryFrame
        and inventoryFrame:FindFirstChild("MoreFrame")
    local anchorBlock = moreFrame
        and moreFrame:FindFirstChild("AnchorBlock")
    local anchorValue = anchorBlock
        and anchorBlock:FindFirstChild("Anchor")
    if not anchorValue
        or not anchorValue:IsA("ValueBase")
        or type(anchorValue.Value) ~= "boolean" then
        setStatus("BuildGui Anchor Block setting is unavailable.", "error")
        return
    end
    if anchorValue.Value ~= true then
        setStatus(
            "Turn Anchor Block ON before the controlled 10-part test.",
            "error"
        )
        return
    end
    local anchorSetting = anchorValue.Value

    local candidates = {}
    local skipped = {}
    local requiredByType = {}
    local twoStageTypes = {
        Spring = true,
        Bar = true,
        Rope = true,
    }
    for _, savedPart in ipairs(selectedAnalysis.parts) do
        if #candidates >= 10 then
            break
        end

        local template = BuildingParts
            and BuildingParts:FindFirstChild(savedPart.blockType)
        local primaryPart = getTemplateBasePart(template)
        local reason = nil
        if not template or not primaryPart then
            reason = "template-unavailable"
        elseif twoStageTypes[savedPart.blockType]
            or template:FindFirstChild("SecondaryPart", true) then
            reason = "two-stage-protocol"
        end

        if reason then
            skipped[#skipped + 1] = {
                id = savedPart.id,
                blockType = savedPart.blockType,
                reason = reason,
            }
        else
            candidates[#candidates + 1] = savedPart
            requiredByType[savedPart.blockType] =
                (requiredByType[savedPart.blockType] or 0) + 1
        end
    end

    if #candidates < 10 then
        setStatus(
            "Blueprint has only "
                .. tostring(#candidates)
                .. " supported parts in this controlled scope.",
            "error"
        )
        return
    end

    local startingInventory = {}
    for blockType, required in pairs(requiredByType) do
        local snapshot, problem = getInventorySnapshot(blockType)
        if not snapshot then
            setStatus(problem, "error")
            return
        end
        if snapshot.available < required then
            setStatus(
                "Need "
                    .. tostring(required)
                    .. " "
                    .. blockType
                    .. " • available "
                    .. tostring(snapshot.available),
                "error"
            )
            return
        end
        startingInventory[blockType] = snapshot
    end

    local boundsMin = selectedAnalysis.boundsMin
    local boundsMax = selectedAnalysis.boundsMax
    local sourceCenterX = (boundsMin.X + boundsMax.X) * 0.5
    local sourceCenterZ = (boundsMin.Z + boundsMax.Z) * 0.5
    local sourceBottomY = boundsMin.Y
    local targetLift = baseTopOffset + 0.35

    placementGeneration = placementGeneration + 1
    local generation = placementGeneration
    setPlacementTesting(true)
    setProgress(0)
    verificationLabel.Text = "VERIFICATION  •  PRE-FLIGHT PASS"
    verificationLabel.TextColor3 = Color3.fromRGB(75, 213, 240)
    setStatus("Controlled build 0 / 10 • preparing first part…", "active")

    latestProtocolDump = {
        schemaVersion = 2,
        probeVersion = SCRIPT_VERSION,
        mode = "controlled-10-part-blueprint-build",
        placeId = game.PlaceId,
        placeVersion = game.PlaceVersion,
        selectedBlueprint = selectedAnalysis.fileName,
        requestedParts = 10,
        supportedParts = #candidates,
        attemptedParts = 0,
        verifiedParts = 0,
        skippedBeforeSelection = skipped,
        scope = {
            placementOnly = true,
            defaultTemplateDimensions = true,
            sizingDeferred = true,
            bindingsDeferred = true,
            twoStagePartsDeferred = true,
            stopOnFirstRejection = true,
        },
        target = {
            zoneName = buildZone.Name,
            mode = "team-zone-center",
        },
        protocol = {
            remote = "BuildingTool.RF",
            maximumCallCount = 10,
            callCount = 0,
            automaticRetries = 0,
            anchorSetting = anchorSetting,
            secondaryArgument = false,
            arguments = {
                "blockName",
                "inventoryTotal",
                "targetPart",
                "targetRelativeCFrame",
                "anchorSetting",
                "primaryPartCFrame",
                "secondaryPartCFrameOrFalse",
            },
        },
        startingInventory = startingInventory,
        parts = {},
        outcome = "running",
    }
    saveDumpButton.BackgroundColor3 = Color3.fromRGB(61, 72, 79)

    task.spawn(function()
        local failure = nil
        for index, savedPart in ipairs(candidates) do
            if destroyRequested or generation ~= placementGeneration then
                return
            end

            local baseline, snapshotProblem =
                getInventorySnapshot(savedPart.blockType)
            local resultEntry = {
                sequence = index,
                blueprintId = savedPart.id,
                blockType = savedPart.blockType,
                baseline = baseline,
                verified = false,
            }

            if not baseline then
                resultEntry.outcome = "inventory-unavailable"
                resultEntry.error = snapshotProblem
                latestProtocolDump.parts[#latestProtocolDump.parts + 1] =
                    resultEntry
                failure = snapshotProblem
                break
            end

            local dataRoot = LocalPlayer:FindFirstChild("Data")
            local dataObject = dataRoot
                and dataRoot:FindFirstChild(savedPart.blockType)
            if not dataObject or not dataObject:IsA("ValueBase") then
                resultEntry.outcome = "inventory-data-disappeared"
                latestProtocolDump.parts[#latestProtocolDump.parts + 1] =
                    resultEntry
                failure = "Inventory data disappeared for "
                    .. savedPart.blockType
                    .. "."
                break
            end

            local relativePosition = Vector3.new(
                savedPart.position.X - sourceCenterX,
                savedPart.position.Y - sourceBottomY + targetLift,
                savedPart.position.Z - sourceCenterZ
            )
            local rotation = savedPart.rotation
            local worldCFrame = anchorCFrame
                * CFrame.new(relativePosition)
                * CFrame.fromOrientation(
                    math.rad(rotation.X),
                    math.rad(rotation.Y),
                    math.rad(rotation.Z)
                )
            local relativeCFrame =
                buildZone.CFrame:ToObjectSpace(worldCFrame)

            resultEntry.target = {
                position = string.format(
                    "%.4f, %.4f, %.4f",
                    worldCFrame.Position.X,
                    worldCFrame.Position.Y,
                    worldCFrame.Position.Z
                ),
            }
            verificationLabel.Text = "VERIFICATION  •  PART "
                .. tostring(index)
                .. " / 10  •  "
                .. savedPart.blockType
            verificationLabel.TextColor3 = Color3.fromRGB(75, 213, 240)
            setStatus(
                "Controlled build "
                    .. tostring(index - 1)
                    .. " / 10 • placing "
                    .. savedPart.blockType,
                "active"
            )
            setProgress((index - 1) / 10)

            latestProtocolDump.attemptedParts = index
            latestProtocolDump.protocol.callCount =
                latestProtocolDump.protocol.callCount + 1
            local startedAt = os.clock()
            local callOk, callResult = pcall(function()
                return remote:InvokeServer(
                    savedPart.blockType,
                    dataObject.Value,
                    buildZone,
                    relativeCFrame,
                    anchorSetting,
                    worldCFrame,
                    false
                )
            end)
            resultEntry.remoteCall = {
                completed = callOk,
                returnType = callOk and typeof(callResult) or "error",
                returnValue = callOk
                        and safeResultValue(callResult)
                    or tostring(callResult),
            }

            if not callOk then
                resultEntry.outcome = "remote-error"
                resultEntry.error = tostring(callResult)
                resultEntry.elapsedSeconds = os.clock() - startedAt
                latestProtocolDump.parts[#latestProtocolDump.parts + 1] =
                    resultEntry
                failure = "Part "
                    .. tostring(index)
                    .. " remote error: "
                    .. tostring(callResult)
                break
            end

            local deadline = os.clock() + TEST_VERIFY_TIMEOUT
            local after = nil
            local signals = nil
            repeat
                after = getInventorySnapshot(savedPart.blockType)
                if after then
                    signals = {
                        usedIncreased = after.used > baseline.used,
                        availableDecreased =
                            after.available < baseline.available,
                        placedModelIncreased =
                            after.placedCount > baseline.placedCount,
                    }
                    if signals.usedIncreased
                        and signals.availableDecreased
                        and signals.placedModelIncreased then
                        break
                    end
                end
                task.wait(0.1)
            until destroyRequested
                or generation ~= placementGeneration
                or os.clock() >= deadline

            if destroyRequested or generation ~= placementGeneration then
                return
            end

            local verified = signals
                and signals.usedIncreased
                and signals.availableDecreased
                and signals.placedModelIncreased
                or false
            resultEntry.after = after
            resultEntry.signals = signals or {}
            resultEntry.verified = verified
            resultEntry.outcome =
                verified and "verified" or "verification-timeout"
            resultEntry.elapsedSeconds = os.clock() - startedAt
            latestProtocolDump.parts[#latestProtocolDump.parts + 1] =
                resultEntry

            if not verified then
                failure = "Part "
                    .. tostring(index)
                    .. " did not confirm all 3 placement signals."
                break
            end

            latestProtocolDump.verifiedParts = index
            setProgress(index / 10)
            verificationLabel.Text = "VERIFICATION  •  PASS "
                .. tostring(index)
                .. " / 10  •  "
                .. snapshotText(after)
            verificationLabel.TextColor3 = Color3.fromRGB(96, 231, 148)
            task.wait(0.15)
        end

        if destroyRequested or generation ~= placementGeneration then
            return
        end

        local finalInventory = {}
        for blockType in pairs(requiredByType) do
            finalInventory[blockType] =
                getInventorySnapshot(blockType)
        end
        latestProtocolDump.finalInventory = finalInventory
        latestProtocolDump.stoppedAt =
            failure and (#latestProtocolDump.parts) or nil
        latestProtocolDump.error = failure
        latestProtocolDump.outcome =
            failure and "stopped-on-first-failure" or "verified"

        setPlacementTesting(false)
        saveDumpButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
        if failure then
            setProgress(latestProtocolDump.verifiedParts / 10)
            verificationLabel.Text = "VERIFICATION  •  STOPPED  •  "
                .. tostring(latestProtocolDump.verifiedParts)
                .. " / 10 PASS"
            verificationLabel.TextColor3 = Color3.fromRGB(255, 114, 114)
            setStatus(failure, "error")
        else
            setProgress(1)
            verificationLabel.Text =
                "VERIFICATION  •  PASS 10 / 10"
            verificationLabel.TextColor3 = Color3.fromRGB(96, 231, 148)
            setStatus(
                "PASS • 10 native calls • all 10 parts confirmed.",
                "success"
            )
        end
    end)
end

controller.BeginFidelityTest = function()
    if not requirePremium("Auto Build / Blueprint Placement") then
        setStatus("PREMIUM LOCK • analysis and ghost preview remain available.", "error")
        return false
    end
    if placementTesting then
        setStatus("A controlled test is already running.", "active")
        return
    end
    if not selectedAnalysis or not selectedAnalysis.valid then
        setStatus("Select a valid .Build file first.", "error")
        return
    end
    if not selectedAnalysis.boundsMin or not selectedAnalysis.boundsMax then
        setStatus("Blueprint bounds are unavailable.", "error")
        return
    end

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local buildZone = findTeamBuildZone(root)
    if not buildZone then
        setStatus("Could not locate your team's buildable zone.", "error")
        return
    end

    local anchorCFrame, baseTopOffset = findPreviewAnchor()
    if not anchorCFrame then
        setStatus("Could not resolve the build-zone center.", "error")
        return
    end

    local placementRemote = findBuildingToolRemote()
    if not placementRemote then
        setStatus("BuildingTool.RF is unavailable.", "error")
        return
    end

    local scalingTool = BuildingParts
        and BuildingParts:FindFirstChild("ScalingTool")
    local paintingTool = BuildingParts
        and BuildingParts:FindFirstChild("PaintingTool")
    local scaleRemote = scalingTool
        and scalingTool:FindFirstChild("RF")
    local paintRemote = paintingTool
        and paintingTool:FindFirstChild("RF")
    if not scaleRemote or not paintRemote then
        setStatus(
            "Canonical Scaling/Painting remotes are unavailable.",
            "error"
        )
        return
    end
    if not scaleRemote:IsA("RemoteFunction")
        or not paintRemote:IsA("RemoteFunction") then
        setStatus(
            "Canonical fidelity remotes have unexpected classes.",
            "error"
        )
        return
    end

    local excludedTypes = {
        Spring = true,
        Bar = true,
        Rope = true,
    }
    local candidate = nil
    local candidateTemplatePart = nil
    local candidateUnits = nil
    local candidateScore = -math.huge
    for index, savedPart in ipairs(selectedAnalysis.parts) do
        if index > 500 then
            break
        end

        local template = BuildingParts
            and BuildingParts:FindFirstChild(savedPart.blockType)
        local templatePart = getTemplateBasePart(template)
        if template
            and templatePart
            and savedPart.size
            and savedPart.color
            and not excludedTypes[savedPart.blockType]
            and not template:FindFirstChild("SecondaryPart", true) then
            local inventory = getInventorySnapshot(savedPart.blockType)
            if inventory then
                local templateVolume = math.max(
                    templatePart.Size.X
                        * templatePart.Size.Y
                        * templatePart.Size.Z,
                    0.000001
                )
                local desiredVolume = savedPart.size.X
                    * savedPart.size.Y
                    * savedPart.size.Z
                local requiredUnits = math.max(
                    desiredVolume / templateVolume,
                    1
                )
                if inventory.available
                    >= math.ceil(requiredUnits - 0.000001) then
                    local sizeDelta =
                        (savedPart.size - templatePart.Size).Magnitude
                    local colorDelta = math.abs(
                        savedPart.color.R - templatePart.Color.R
                    ) + math.abs(
                        savedPart.color.G - templatePart.Color.G
                    ) + math.abs(
                        savedPart.color.B - templatePart.Color.B
                    )
                    local score = 10
                        + math.min(sizeDelta, 10) * 4
                        + math.min(colorDelta, 3) * 8
                        + (savedPart.raw.Transparency ~= nil and 3 or 0)
                        + (savedPart.raw.CanCollide ~= nil and 3 or 0)
                        + (savedPart.raw.Anchored == true and 4 or 0)
                    if score > candidateScore then
                        candidate = savedPart
                        candidateTemplatePart = templatePart
                        candidateUnits = requiredUnits
                        candidateScore = score
                    end
                end
            end
        end
    end

    if not candidate or not candidateTemplatePart then
        setStatus(
            "No affordable fidelity-rich part was found in the first 500.",
            "error"
        )
        return
    end

    local baseline, snapshotProblem =
        getInventorySnapshot(candidate.blockType)
    if not baseline then
        setStatus(snapshotProblem, "error")
        return
    end

    local dataRoot = LocalPlayer:FindFirstChild("Data")
    local dataObject = dataRoot
        and dataRoot:FindFirstChild(candidate.blockType)
    if not dataObject or not dataObject:IsA("ValueBase") then
        setStatus("Selected block inventory data is unavailable.", "error")
        return
    end

    local blocks = Workspace:FindFirstChild("Blocks")
    local playerFolder = blocks
        and blocks:FindFirstChild(LocalPlayer.Name)
    local existingObjects = {}
    if playerFolder then
        for _, child in ipairs(playerFolder:GetChildren()) do
            existingObjects[child] = true
        end
    end

    local boundsMin = selectedAnalysis.boundsMin
    local boundsMax = selectedAnalysis.boundsMax
    local sourceCenterX = (boundsMin.X + boundsMax.X) * 0.5
    local sourceCenterZ = (boundsMin.Z + boundsMax.Z) * 0.5
    local sourceBottomY = boundsMin.Y
    local relativePosition = Vector3.new(
        candidate.position.X - sourceCenterX,
        candidate.position.Y - sourceBottomY + baseTopOffset + 0.35,
        candidate.position.Z - sourceCenterZ
    )
    local rotation = candidate.rotation
    local worldCFrame = anchorCFrame
        * CFrame.new(relativePosition)
        * CFrame.fromOrientation(
            math.rad(rotation.X),
            math.rad(rotation.Y),
            math.rad(rotation.Z)
        )
    local relativeCFrame =
        buildZone.CFrame:ToObjectSpace(worldCFrame)

    local desiredSize = candidate.size
    local desiredColor = candidate.color
    local desiredTransparency =
        tonumber(candidate.raw.Transparency)
    if desiredTransparency == nil then
        desiredTransparency = candidateTemplatePart.Transparency
    end
    desiredTransparency = math.clamp(desiredTransparency, 0, 1)
    local desiredCanCollide = candidateTemplatePart.CanCollide
    if type(candidate.raw.CanCollide) == "boolean" then
        desiredCanCollide = candidate.raw.CanCollide
    end
    local desiredAnchored = true
    if type(candidate.raw.Anchored) == "boolean" then
        desiredAnchored = candidate.raw.Anchored
    end

    local function vectorText(value)
        return string.format(
            "%.4f, %.4f, %.4f",
            value.X,
            value.Y,
            value.Z
        )
    end

    local function colorText(value)
        return string.format(
            "%.6f, %.6f, %.6f",
            value.R,
            value.G,
            value.B
        )
    end

    local function getPrimaryPart(instance)
        if not instance then
            return nil
        end
        if instance:IsA("BasePart") then
            return instance
        end
        if instance:IsA("Model") and instance.PrimaryPart then
            return instance.PrimaryPart
        end
        return instance:FindFirstChildWhichIsA("BasePart", true)
    end

    local function propertySnapshot(instance)
        local primary = getPrimaryPart(instance)
        if not primary then
            return nil
        end
        return {
            size = vectorText(primary.Size),
            color = colorText(primary.Color),
            transparency = primary.Transparency,
            canCollide = primary.CanCollide,
            anchored = primary.Anchored,
            position = vectorText(primary.Position),
        }, primary
    end

    placementGeneration = placementGeneration + 1
    local generation = placementGeneration
    setPlacementTesting(true)
    setProgress(0.05)
    verificationLabel.Text = "VERIFICATION  •  SELECTED ID "
        .. tostring(candidate.id)
        .. "  •  "
        .. candidate.blockType
    verificationLabel.TextColor3 = Color3.fromRGB(75, 213, 240)
    setStatus("Fidelity test • placing blueprint part…", "active")

    latestProtocolDump = {
        schemaVersion = 3,
        probeVersion = SCRIPT_VERSION,
        mode = "controlled-blueprint-fidelity",
        placeId = game.PlaceId,
        placeVersion = game.PlaceVersion,
        selectedBlueprint = selectedAnalysis.fileName,
        blueprintPart = {
            id = candidate.id,
            blockType = candidate.blockType,
            estimatedInventoryUnits = candidateUnits,
        },
        target = {
            zoneName = buildZone.Name,
            mode = "team-zone-center",
            position = vectorText(worldCFrame.Position),
        },
        desired = {
            size = vectorText(desiredSize),
            color = colorText(desiredColor),
            transparency = desiredTransparency,
            canCollide = desiredCanCollide,
            anchored = desiredAnchored,
        },
        protocol = {
            placement = {
                remote = "BuildingTool.RF",
                maximumCallCount = 1,
                automaticRetries = 0,
                anchorSetting = desiredAnchored,
                secondaryArgument = false,
            },
            scaling = {
                remote = "ScalingTool.RF",
                access = "ReplicatedStorage.BuildingParts",
                toolOwnershipRequiredByClient = false,
                toolEquippedRequiredByClient = false,
                maximumCallCount = 1,
                automaticRetries = 0,
                arguments = {
                    "placedModel",
                    "desiredSize",
                    "desiredCFrame",
                },
            },
            painting = {
                remote = "PaintingTool.RF",
                access = "ReplicatedStorage.BuildingParts",
                toolOwnershipRequiredByClient = false,
                toolEquippedRequiredByClient = false,
                maximumCallCount = 1,
                automaticRetries = 0,
                packet = "{{placedModel, desiredColor}}",
            },
            propertyMutation = {
                transparency =
                    "verification-only-no-confirmed-generic-remote",
                canCollide = "verification-only",
                anchored = "placement-argument",
            },
        },
        calls = {},
        baseline = baseline,
        outcome = "running",
    }
    saveDumpButton.BackgroundColor3 = Color3.fromRGB(61, 72, 79)

    task.spawn(function()
        local placeStarted = os.clock()
        local placeOk, placeResult = pcall(function()
            return placementRemote:InvokeServer(
                candidate.blockType,
                dataObject.Value,
                buildZone,
                relativeCFrame,
                desiredAnchored,
                worldCFrame,
                false
            )
        end)
        latestProtocolDump.calls.placement = {
            completed = placeOk,
            returnType = placeOk and typeof(placeResult) or "error",
            returnValue = placeOk
                    and safeResultValue(placeResult)
                or tostring(placeResult),
            elapsedSeconds = os.clock() - placeStarted,
        }

        if destroyRequested or generation ~= placementGeneration then
            return
        end
        if not placeOk then
            latestProtocolDump.outcome = "placement-remote-error"
            latestProtocolDump.error = tostring(placeResult)
            setPlacementTesting(false)
            saveDumpButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
            setProgress(0)
            verificationLabel.Text = "VERIFICATION  •  PLACE ERROR"
            verificationLabel.TextColor3 = Color3.fromRGB(255, 114, 114)
            setStatus("Placement failed: " .. tostring(placeResult), "error")
            return
        end

        local placedObject = nil
        local afterPlacement = nil
        local placementSignals = nil
        local placementDeadline = os.clock() + TEST_VERIFY_TIMEOUT
        repeat
            blocks = Workspace:FindFirstChild("Blocks")
            playerFolder = blocks
                and blocks:FindFirstChild(LocalPlayer.Name)
            if playerFolder then
                for _, child in ipairs(playerFolder:GetChildren()) do
                    if child.Name == candidate.blockType
                        and not existingObjects[child] then
                        placedObject = child
                        break
                    end
                end
            end
            afterPlacement = getInventorySnapshot(candidate.blockType)
            if afterPlacement then
                placementSignals = {
                    usedIncreased =
                        afterPlacement.used > baseline.used,
                    availableDecreased =
                        afterPlacement.available < baseline.available,
                    placedModelIncreased =
                        afterPlacement.placedCount > baseline.placedCount,
                    placedObjectCaptured = placedObject ~= nil,
                }
                if placementSignals.usedIncreased
                    and placementSignals.availableDecreased
                    and placementSignals.placedModelIncreased
                    and placementSignals.placedObjectCaptured then
                    break
                end
            end
            task.wait(0.1)
        until destroyRequested
            or generation ~= placementGeneration
            or os.clock() >= placementDeadline

        if destroyRequested or generation ~= placementGeneration then
            return
        end

        latestProtocolDump.afterPlacement = afterPlacement
        latestProtocolDump.placementSignals = placementSignals or {}
        if not placedObject
            or not placementSignals
            or not placementSignals.usedIncreased
            or not placementSignals.availableDecreased
            or not placementSignals.placedModelIncreased then
            latestProtocolDump.outcome = "placement-verification-timeout"
            setPlacementTesting(false)
            saveDumpButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
            setProgress(0.2)
            verificationLabel.Text =
                "VERIFICATION  •  PLACE NOT CONFIRMED"
            verificationLabel.TextColor3 = Color3.fromRGB(255, 114, 114)
            setStatus(
                "Placed part did not confirm all capture signals.",
                "error"
            )
            return
        end

        setProgress(0.35)
        verificationLabel.Text = "VERIFICATION  •  PLACED  •  SCALING"
        setStatus("Fidelity test • applying blueprint size…", "active")
        local scaleStarted = os.clock()
        local scaleOk, scaleResultSize, scaleResultCFrame =
            pcall(function()
                return scaleRemote:InvokeServer(
                    placedObject,
                    desiredSize,
                    worldCFrame
                )
            end)
        latestProtocolDump.calls.scaling = {
            completed = scaleOk,
            returnType = scaleOk
                    and typeof(scaleResultSize)
                or "error",
            returnSize = scaleOk
                    and safeResultValue(scaleResultSize)
                or tostring(scaleResultSize),
            returnCFrame = scaleOk
                    and safeResultValue(scaleResultCFrame)
                or nil,
            elapsedSeconds = os.clock() - scaleStarted,
        }
        if not scaleOk then
            latestProtocolDump.outcome = "scaling-remote-error"
            latestProtocolDump.error = tostring(scaleResultSize)
            setPlacementTesting(false)
            saveDumpButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
            verificationLabel.Text = "VERIFICATION  •  SCALE ERROR"
            verificationLabel.TextColor3 = Color3.fromRGB(255, 114, 114)
            setStatus("Scaling failed: " .. tostring(scaleResultSize), "error")
            return
        end

        task.wait(0.35)
        if destroyRequested or generation ~= placementGeneration then
            return
        end

        setProgress(0.62)
        verificationLabel.Text = "VERIFICATION  •  SCALED  •  PAINTING"
        setStatus("Fidelity test • applying blueprint color…", "active")
        local paintStarted = os.clock()
        local paintOk, paintResult = pcall(function()
            return paintRemote:InvokeServer({
                {placedObject, desiredColor},
            })
        end)
        latestProtocolDump.calls.painting = {
            completed = paintOk,
            returnType = paintOk and typeof(paintResult) or "error",
            returnValue = paintOk
                    and safeResultValue(paintResult)
                or tostring(paintResult),
            elapsedSeconds = os.clock() - paintStarted,
        }
        if not paintOk then
            latestProtocolDump.outcome = "painting-remote-error"
            latestProtocolDump.error = tostring(paintResult)
            setPlacementTesting(false)
            saveDumpButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
            verificationLabel.Text = "VERIFICATION  •  PAINT ERROR"
            verificationLabel.TextColor3 = Color3.fromRGB(255, 114, 114)
            setStatus("Painting failed: " .. tostring(paintResult), "error")
            return
        end

        setProgress(0.82)
        verificationLabel.Text =
            "VERIFICATION  •  CHECKING FIVE FIELDS"
        setStatus("Fidelity test • verifying final properties…", "active")
        local actual, actualPart = nil, nil
        local verification = nil
        local verifyDeadline = os.clock() + math.min(
            TEST_VERIFY_TIMEOUT,
            3
        )
        repeat
            actual, actualPart = propertySnapshot(placedObject)
            if actual and actualPart then
                local sizeMatched =
                    (actualPart.Size - desiredSize).Magnitude <= 0.015
                local colorMatched =
                    math.abs(actualPart.Color.R - desiredColor.R) <= 0.01
                    and math.abs(
                        actualPart.Color.G - desiredColor.G
                    ) <= 0.01
                    and math.abs(
                        actualPart.Color.B - desiredColor.B
                    ) <= 0.01
                verification = {
                    size = sizeMatched,
                    color = colorMatched,
                    transparency = math.abs(
                        actualPart.Transparency - desiredTransparency
                    ) <= 0.01,
                    canCollide =
                        actualPart.CanCollide == desiredCanCollide,
                    anchored = actualPart.Anchored == desiredAnchored,
                }
                if verification.size
                    and verification.color
                    and verification.transparency
                    and verification.canCollide
                    and verification.anchored then
                    break
                end
            end
            task.wait(0.1)
        until destroyRequested
            or generation ~= placementGeneration
            or os.clock() >= verifyDeadline

        if destroyRequested or generation ~= placementGeneration then
            return
        end

        local authoritativeMatched = verification
            and verification.size
            and verification.color
            and verification.canCollide
            and verification.anchored
            or false
        local allMatched = authoritativeMatched
            and verification.transparency
            or false
        latestProtocolDump.actual = actual
        latestProtocolDump.verification = verification or {}
        latestProtocolDump.authoritativeMatched =
            authoritativeMatched
        latestProtocolDump.allMatched = allMatched
        if allMatched then
            latestProtocolDump.outcome = "verified"
        elseif authoritativeMatched then
            latestProtocolDump.outcome =
                "verified-with-transparency-deferred"
        else
            latestProtocolDump.outcome = "fidelity-mismatch"
        end

        setPlacementTesting(false)
        saveDumpButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
        if allMatched then
            setProgress(1)
            verificationLabel.Text =
                "VERIFICATION  •  PASS  •  5 / 5 MATCH"
            verificationLabel.TextColor3 = Color3.fromRGB(96, 231, 148)
            setStatus(
                "PASS • size, color, transparency, collision, anchor.",
                "success"
            )
        elseif authoritativeMatched then
            setProgress(1)
            verificationLabel.Text =
                "VERIFICATION  •  PASS 4 / 4  •  TRANSPARENCY DEFERRED"
            verificationLabel.TextColor3 = Color3.fromRGB(96, 231, 148)
            setStatus(
                "PASS • confirmed fields match • transparency deferred.",
                "success"
            )
        else
            setProgress(0.9)
            local matched = 0
            if verification and verification.size then
                matched = matched + 1
            end
            if verification and verification.color then
                matched = matched + 1
            end
            if verification and verification.canCollide then
                matched = matched + 1
            end
            if verification and verification.anchored then
                matched = matched + 1
            end
            verificationLabel.Text = "VERIFICATION  •  "
                .. tostring(matched)
                .. " / 4 CONFIRMED  •  SAVE DUMP"
            verificationLabel.TextColor3 = Color3.fromRGB(255, 186, 98)
            setStatus(
                "Fidelity mismatch found • save and send the dump.",
                "error"
            )
        end
    end)
end

local function stopPlacementTest()
    if not placementTesting then
        setStatus("No placement verification is running.")
        return
    end
    placementGeneration = placementGeneration + 1
    setPlacementTesting(false)
    setProgress(0)
    if latestProtocolDump and latestProtocolDump.outcome == "running" then
        latestProtocolDump.outcome = "cancelled"
        latestProtocolDump.cancelledAt =
            latestProtocolDump.attemptedParts
    end
    saveDumpButton.BackgroundColor3 = latestProtocolDump
            and Color3.fromRGB(35, 160, 190)
        or Color3.fromRGB(61, 72, 79)
    verificationLabel.Text = "VERIFICATION  •  STOPPED"
    verificationLabel.TextColor3 = Color3.fromRGB(255, 186, 98)
    setStatus(
        "Build test stopped • already-placed blocks were not removed.",
        "error"
    )
end

local function saveProtocolDump()
    if not latestProtocolDump then
        setStatus("Run a controlled build test before saving a dump.", "error")
        return
    end
    if not WRITE_FILE or not probeFolderReady then
        setStatus(
            "Executor cannot save " .. PROBE_FOLDER .. " dumps.",
            "error"
        )
        return
    end

    latestProtocolDump.savedAtUtc = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local encodeOk, encoded = pcall(function()
        return HttpService:JSONEncode(latestProtocolDump)
    end)
    if not encodeOk then
        setStatus("Could not encode the protocol dump.", "error")
        return
    end

    local fileName = os.date("%Y%m%d_%H%M%S")
        .. "_"
        .. tostring(game.PlaceId)
        .. "_autobuild_protocol.json"
    local path = PROBE_FOLDER .. "/" .. fileName
    local writeOk, writeProblem = pcall(WRITE_FILE, path, encoded)
    if not writeOk then
        setStatus("Dump save failed: " .. tostring(writeProblem), "error")
        return
    end
    setStatus("Saved protocol dump to " .. path, "success")
end

local function clearContainer(container, preserved)
    for _, child in ipairs(container:GetChildren()) do
        if child ~= preserved
            and not child:IsA("UICorner")
            and not child:IsA("UIStroke") then
            child:Destroy()
        end
    end
end

local function updateMaterialList(analysis)
    clearContainer(materialsList, materialsLayout)
    if not analysis then
        materialsList.CanvasSize = UDim2.fromOffset(0, 0)
        return
    end

    for index, material in ipairs(analysis.materials) do
        local row = Instance.new("Frame")
        row.LayoutOrder = index
        row.Size = UDim2.new(1, -8, 0, 30)
        row.BackgroundColor3 = index % 2 == 0
                and Color3.fromRGB(26, 36, 43)
            or Color3.fromRGB(23, 32, 39)
        row.BorderSizePixel = 0
        row.Parent = materialsList

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 6)
        rowCorner.Parent = row

        local typeLabel = Instance.new("TextLabel")
        typeLabel.Size = UDim2.new(1, -100, 1, 0)
        typeLabel.Position = UDim2.fromOffset(10, 0)
        typeLabel.BackgroundTransparency = 1
        typeLabel.Font = Enum.Font.Gotham
        typeLabel.Text = material.blockType
            .. (material.templateFound and "" or "  ⚠")
        typeLabel.TextColor3 = material.templateFound
                and Color3.fromRGB(219, 229, 233)
            or Color3.fromRGB(255, 160, 101)
        typeLabel.TextSize = 12
        typeLabel.TextXAlignment = Enum.TextXAlignment.Left
        typeLabel.Parent = row

        local countLabel = Instance.new("TextLabel")
        countLabel.Size = UDim2.fromOffset(78, 30)
        countLabel.Position = UDim2.new(1, -88, 0, 0)
        countLabel.BackgroundTransparency = 1
        countLabel.Font = Enum.Font.GothamBold
        countLabel.Text = "× " .. tostring(material.count)
        countLabel.TextColor3 = Color3.fromRGB(78, 208, 234)
        countLabel.TextSize = 12
        countLabel.TextXAlignment = Enum.TextXAlignment.Right
        countLabel.Parent = row
    end

    materialsList.CanvasSize = UDim2.fromOffset(
        0,
        #analysis.materials * 33
    )
end

local function updateSummary(analysis)
    selectedAnalysis = analysis
    setProgress(0)
    if not analysis then
        for _, label in ipairs(summaryLabels) do
            label.Text = "—"
            label.TextColor3 = Color3.fromRGB(230, 238, 241)
        end
        updateMaterialList(nil)
        previewButton.BackgroundColor3 = Color3.fromRGB(61, 72, 79)
        return
    end

    summaryLabels[1].Text = tostring(analysis.partCount)
    summaryLabels[2].Text = tostring(analysis.typeCount)
    summaryLabels[3].Text = tostring(analysis.bindingCount)
    if analysis.valid then
        local usesPerformanceLod =
            analysis.partCount > FULL_PREVIEW_PART_LIMIT
        if usesPerformanceLod then
            summaryLabels[4].Text = "READY • LOD"
            summaryLabels[4].TextColor3 = Color3.fromRGB(96, 231, 148)
        elseif #analysis.warnings > 0 then
            summaryLabels[4].Text = "READY • "
                .. tostring(#analysis.warnings)
                .. " WARN"
            summaryLabels[4].TextColor3 = Color3.fromRGB(255, 186, 98)
        else
            summaryLabels[4].Text = "READY"
            summaryLabels[4].TextColor3 = Color3.fromRGB(96, 231, 148)
        end
        previewButton.BackgroundColor3 = Color3.fromRGB(35, 160, 190)
        setStatus(
            "Analyzed "
                .. analysis.fileName
                .. " • "
                .. analysis.sourceFormat
                .. (usesPerformanceLod
                    and " • performance LOD"
                    or " • full preview"),
            "success"
        )
    else
        summaryLabels[4].Text = "INVALID"
        summaryLabels[4].TextColor3 = Color3.fromRGB(255, 114, 114)
        previewButton.BackgroundColor3 = Color3.fromRGB(61, 72, 79)
        setStatus(
            analysis.errors[1] or "Blueprint validation failed.",
            "error"
        )
    end
    updateMaterialList(analysis)
end

local function removePreview(message)
    previewGeneration = previewGeneration + 1
    previewBuilding = false
    if previewModel then
        pcall(function()
            previewModel:Destroy()
        end)
        previewModel = nil
    end
    setProgress(0)
    removeButton.BackgroundColor3 = Color3.fromRGB(61, 72, 79)
    if message then
        setStatus(message)
    end
end

local function selectFile(path)
    if selectedPath ~= path then
        removePreview("Previous preview removed.")
    end
    analysisGeneration = analysisGeneration + 1
    local generation = analysisGeneration
    selectedPath = path
    dropdown.Visible = false
    dropdown.Size = UDim2.new(1, -180, 0, 0)

    if not path then
        fileButton.Text = "No .Build files found  ▾"
        updateSummary(nil)
        setStatus(
            "Add exact .Build files to " .. BUILD_FOLDER .. " and refresh.",
            "error"
        )
        return
    end

    fileButton.Text = basename(path) .. "  ▾"
    updateSummary(nil)
    setStatus("Analyzing " .. basename(path) .. "…", "active")
    setProgress(0.03)

    task.spawn(function()
        RunService.Heartbeat:Wait()
        if destroyRequested
            or generation ~= analysisGeneration
            or selectedPath ~= path then
            return
        end

        local analysis = analyzeBuildFile(path)
        if destroyRequested
            or generation ~= analysisGeneration
            or selectedPath ~= path then
            return
        end
        updateSummary(analysis)
    end)
end

local function rebuildDropdown()
    clearContainer(dropdown, dropdownLayout)
    for index, path in ipairs(buildFiles) do
        local option = Instance.new("TextButton")
        option.LayoutOrder = index
        option.Size = UDim2.new(1, -8, 0, 32)
        option.BackgroundColor3 = path == selectedPath
                and Color3.fromRGB(39, 130, 153)
            or Color3.fromRGB(30, 42, 50)
        option.BorderSizePixel = 0
        option.AutoButtonColor = false
        option.Font = Enum.Font.Gotham
        option.Text = basename(path)
        option.TextColor3 = Color3.fromRGB(230, 238, 241)
        option.TextSize = 12
        option.TextTruncate = Enum.TextTruncate.AtEnd
        option.ZIndex = 21
        option.Parent = dropdown

        local optionCorner = Instance.new("UICorner")
        optionCorner.CornerRadius = UDim.new(0, 6)
        optionCorner.Parent = option

        table.insert(guiConnections, option.MouseButton1Click:Connect(function()
            selectFile(path)
            rebuildDropdown()
        end))
    end

    local contentHeight = #buildFiles * 35
    dropdown.CanvasSize = UDim2.fromOffset(0, contentHeight)
end

local function refreshFiles()
    setStatus("Refreshing .Build files…", "active")
    removePreview()
    dropdown.Visible = false
    dropdown.Size = UDim2.new(1, -180, 0, 0)

    if not folderReady then
        selectFile(nil)
        setStatus(
            "Could not create " .. BUILD_FOLDER .. ".",
            "error"
        )
        return
    end
    if not LIST_FILES then
        selectFile(nil)
        setStatus("Executor does not provide listfiles.", "error")
        return
    end

    local listOk, paths = pcall(LIST_FILES, BUILD_FOLDER)
    if not listOk or type(paths) ~= "table" then
        selectFile(nil)
        setStatus("Could not scan the Auto Build folder.", "error")
        return
    end

    local refreshed = {}
    for _, path in ipairs(paths) do
        local name = basename(path)
        if endsWithExactBuild(name) then
            refreshed[#refreshed + 1] = path
        end
    end
    table.sort(refreshed, function(left, right)
        return basename(left):lower() < basename(right):lower()
    end)
    buildFiles = refreshed

    local preserved = nil
    for _, path in ipairs(buildFiles) do
        if path == selectedPath then
            preserved = path
            break
        end
    end

    rebuildDropdown()
    if preserved then
        selectFile(preserved)
    elseif #buildFiles > 0 then
        selectFile(buildFiles[1])
    else
        selectFile(nil)
    end
    rebuildDropdown()
end

local function beginPreview()
    if previewBuilding then
        setStatus("Preview is already loading.", "active")
        return
    end
    if not selectedAnalysis or not selectedAnalysis.valid then
        setStatus("Select a valid .Build file first.", "error")
        return
    end
    if not selectedAnalysis.boundsMin or not selectedAnalysis.boundsMax then
        setStatus("Blueprint bounds are unavailable.", "error")
        return
    end

    local analysis = selectedAnalysis
    removePreview()
    previewBuilding = true
    previewGeneration = previewGeneration + 1
    local generation = previewGeneration

    local anchorCFrame, baseTopOffset, anchorSource = findPreviewAnchor()
    if not anchorCFrame then
        previewBuilding = false
        setStatus(
            "Could not locate your team's buildable zone.",
            "error"
        )
        return
    end

    local model = Instance.new("Model")
    model.Name = "__SliceHubBABFTBuildPreview"
    model:SetAttribute("SliceHubPreviewOnly", true)
    model:SetAttribute("SourceFile", analysis.fileName)
    model.Parent = Workspace.CurrentCamera or Workspace
    previewModel = model
    removeButton.BackgroundColor3 = Color3.fromRGB(153, 71, 82)

    local boundsMin = analysis.boundsMin
    local boundsMax = analysis.boundsMax
    local sourceCenterX = (boundsMin.X + boundsMax.X) * 0.5
    local sourceCenterZ = (boundsMin.Z + boundsMax.Z) * 0.5
    local sourceBottomY = boundsMin.Y
    local targetLift = baseTopOffset + 0.35
    local sourceTotal = #analysis.parts
    local previewParts, usesPerformanceLod = buildPreviewPartList(
        analysis.parts
    )
    local ghostTotal = #previewParts
    local progressName = usesPerformanceLod and "LOD preview" or "Preview"

    model:SetAttribute("SourcePartCount", sourceTotal)
    model:SetAttribute("GhostPartCount", ghostTotal)
    model:SetAttribute("PerformanceLOD", usesPerformanceLod)
    if usesPerformanceLod and walkablePreview then
        walkablePreview = false
        environment.__SliceHubBABFTPreviewWalkable = false
        updateWalkableUi()
    end

    setStatus(
        progressName
            .. " 0 / "
            .. tostring(ghostTotal)
            .. " • "
            .. anchorSource,
        "active"
    )
    setProgress(0)

    task.spawn(function()
        local ok, problem = xpcall(function()
            for index, savedPart in ipairs(previewParts) do
                if destroyRequested
                    or generation ~= previewGeneration
                    or model ~= previewModel
                    or not model.Parent then
                    return
                end

                local relative = Vector3.new(
                    savedPart.position.X - sourceCenterX,
                    savedPart.position.Y - sourceBottomY + targetLift,
                    savedPart.position.Z - sourceCenterZ
                )
                local rotation = savedPart.rotation
                local worldCFrame = anchorCFrame
                    * CFrame.new(relative)
                    * CFrame.fromOrientation(
                        math.rad(rotation.X),
                        math.rad(rotation.Y),
                        math.rad(rotation.Z)
                    )

                local previewObject = makePreviewObject(
                    savedPart,
                    worldCFrame
                )
                if previewObject then
                    previewObject.Parent = model
                end

                if index % PREVIEW_CHUNK_SIZE == 0
                    or index == ghostTotal then
                    setProgress(index / math.max(ghostTotal, 1))
                    setStatus(
                        progressName
                            .. " "
                            .. tostring(index)
                            .. " / "
                            .. tostring(ghostTotal)
                            .. (usesPerformanceLod
                                and " • "
                                    .. tostring(sourceTotal)
                                    .. " source parts"
                                or ""),
                        "active"
                    )
                    RunService.Heartbeat:Wait()
                end
            end
        end, function(errorMessage)
            return tostring(errorMessage)
        end)

        if generation ~= previewGeneration or destroyRequested then
            return
        end

        previewBuilding = false
        if not ok then
            removePreview()
            setStatus("Preview failed: " .. tostring(problem), "error")
            return
        end

        applyWalkablePreview()
        setProgress(1)
        if usesPerformanceLod then
            setStatus(
                "LOD preview ready • "
                    .. tostring(ghostTotal)
                    .. " ghosts / "
                    .. tostring(sourceTotal)
                    .. " source parts",
                "success"
            )
        else
            setStatus(
                "Preview ready • "
                    .. tostring(ghostTotal)
                    .. " local ghost parts",
                "success"
            )
        end
    end)
end

local function updateScale()
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize
    if not viewport then
        return
    end
    local viewportScale = math.clamp(
        math.min(viewport.X / 740, viewport.Y / 830),
        0.55,
        1
    )
    local userScale = math.clamp(
        tonumber(environment.__SliceHubBABFTControlCenterScale) or 1,
        0.65,
        1.35
    )
    uiScale.Scale = math.clamp(viewportScale * userScale, 0.42, 1.35)
end

local dragging = false
local dragStart = nil
local panelStart = nil
local opacityDragging = false
local resizing = false
local resizeStart = nil
local resizeScaleStart = 1

local function showControlPage(pageName)
    Farm.ActivePage = pageName
    local showFarm = pageName == "farm"
    local showSettings = pageName == "settings"
    Farm.UI.Page.Visible = showFarm
    Farm.UI.SettingsPage.Visible = showSettings
    Farm.UI.FarmTab.BackgroundColor3 = showFarm
            and Color3.fromRGB(35, 160, 190)
        or Color3.fromRGB(48, 61, 69)
    Farm.UI.BuildTab.BackgroundColor3 =
        (not showFarm and not showSettings)
            and Color3.fromRGB(35, 160, 190)
        or Color3.fromRGB(48, 61, 69)
    Farm.UI.SettingsTab.BackgroundColor3 = showSettings
            and Color3.fromRGB(35, 160, 190)
        or Color3.fromRGB(48, 61, 69)
    if showFarm then
        Farm.UI.FarmPageScale.Scale = 0.985
        TweenService:Create(
            Farm.UI.FarmPageScale,
            TweenInfo.new(0.22, Enum.EasingStyle.Quint),
            {Scale = 1}
        ):Play()
    elseif showSettings then
        Farm.UI.SettingsPageScale.Scale = 0.985
        TweenService:Create(
            Farm.UI.SettingsPageScale,
            TweenInfo.new(0.22, Enum.EasingStyle.Quint),
            {Scale = 1}
        ):Play()
    end
end

function controller.ClampToViewport()
    local camera = Workspace.CurrentCamera
    if not camera or not panel or not panel.Parent then
        return false
    end
    local viewport = camera.ViewportSize
    local absolutePosition = panel.AbsolutePosition
    local absoluteSize = panel.AbsoluteSize
    local headerHeight = math.max(32, header.AbsoluteSize.Y)
    local margin = 8
    local minimumX
    local maximumX
    if absoluteSize.X <= viewport.X - margin * 2 then
        minimumX = margin
        maximumX = viewport.X - absoluteSize.X - margin
    else
        minimumX = viewport.X - absoluteSize.X - 120
        maximumX = 120
    end
    local desiredX = math.clamp(
        absolutePosition.X,
        minimumX,
        math.max(minimumX, maximumX)
    )
    local desiredY = math.clamp(
        absolutePosition.Y,
        margin,
        math.max(margin, viewport.Y - headerHeight - margin)
    )
    local deltaX = desiredX - absolutePosition.X
    local deltaY = desiredY - absolutePosition.Y
    if math.abs(deltaX) < 0.5 and math.abs(deltaY) < 0.5 then
        return false
    end
    panel.Position = UDim2.new(
        panel.Position.X.Scale,
        panel.Position.X.Offset + deltaX,
        panel.Position.Y.Scale,
        panel.Position.Y.Offset + deltaY
    )
    return true
end

function controller.BindViewport()
    if Farm.ViewportConnection then
        pcall(function()
            Farm.ViewportConnection:Disconnect()
        end)
        Farm.ViewportConnection = nil
    end
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    Farm.ViewportConnection = camera
        :GetPropertyChangedSignal("ViewportSize")
        :Connect(function()
            updateScale()
            task.defer(controller.ClampToViewport)
        end)
    table.insert(guiConnections, Farm.ViewportConnection)
end

function controller.SetMinimized(minimized)
    Farm.GuiState.minimized = minimized == true
    minimizeButton.Text = Farm.GuiState.minimized and "□" or "—"
    Farm.UI.ResizeHandle.Visible = not Farm.GuiState.minimized
    local targetSize = Farm.GuiState.minimized
            and UDim2.fromOffset(700, 46)
        or UDim2.fromOffset(700, 790)
    TweenService:Create(
        panel,
        TweenInfo.new(0.2, Enum.EasingStyle.Quint),
        {Size = targetSize}
    ):Play()
    task.delay(0.22, function()
        if destroyRequested or not panel.Parent then
            return
        end
        controller.ClampToViewport()
        Farm:SaveGuiState(
            panel.Position,
            tonumber(environment.__SliceHubBABFTControlCenterScale) or 1,
            Farm.GuiState.minimized
        )
    end)
end

function controller.Hide()
    controller.ClampToViewport()
    Farm:SaveGuiState(
        panel.Position,
        tonumber(environment.__SliceHubBABFTControlCenterScale) or 1,
        Farm.GuiState.minimized
    )
    panel.Visible = false
    floatingButton.Visible = true
end

function controller.Show()
    floatingButton.Visible = false
    panel.Visible = true
    task.defer(function()
        if destroyRequested or not panel.Parent then
            return
        end
        controller.ClampToViewport()
        Farm:SaveGuiState(
            panel.Position,
            tonumber(environment.__SliceHubBABFTControlCenterScale) or 1,
            Farm.GuiState.minimized
        )
    end)
end

function controller.ToggleVisible()
    if panel.Visible then
        controller.Hide()
    else
        controller.Show()
    end
end

local function showFarmPage(showFarm)
    showControlPage(showFarm and "farm" or "build")
end

local function showSettingsPage()
    showControlPage("settings")
end

local function refreshWebhookUi(message, tone)
    local configured = type(Farm.Config.WebhookUrl) == "string"
        and Farm.Config.WebhookUrl ~= ""
    Farm.UI.WebhookToggle.Text = Farm.Config.WebhookEnabled == true
            and "WEBHOOK: ON"
        or "WEBHOOK: OFF"
    Farm.UI.WebhookToggle.BackgroundColor3 =
        Farm.Config.WebhookEnabled == true
            and Color3.fromRGB(31, 157, 116)
        or Color3.fromRGB(63, 75, 82)
    if configured and not Farm.UI.WebhookInput:IsFocused() then
        local ending = Farm.Config.WebhookUrl:sub(-6)
        Farm.UI.WebhookInput.Text = "••••••••••" .. ending
    elseif not configured and not Farm.UI.WebhookInput:IsFocused() then
        Farm.UI.WebhookInput.Text = ""
    end
    Farm.UI.WebhookStatus.Text = message
        or (configured
            and "SAVED"
            or "NOT SET")
    Farm.UI.WebhookStatus.TextColor3 = tone == "error"
            and Color3.fromRGB(255, 112, 122)
        or tone == "success"
            and Color3.fromRGB(91, 231, 150)
        or Color3.fromRGB(143, 164, 173)
end

table.insert(guiConnections, Farm.UI.FarmTab.MouseButton1Click:Connect(
    function()
        showFarmPage(true)
    end
))
table.insert(guiConnections, Farm.UI.BuildTab.MouseButton1Click:Connect(
    function()
        showFarmPage(false)
    end
))
table.insert(guiConnections, Farm.UI.SettingsTab.MouseButton1Click:Connect(
    showSettingsPage
))
table.insert(guiConnections, Farm.UI.SessionStatsTab.MouseButton1Click:Connect(
    function()
        Farm:SetStatsView("session")
    end
))
table.insert(guiConnections, Farm.UI.OverallStatsTab.MouseButton1Click:Connect(
    function()
        Farm:SetStatsView("overall")
    end
))
table.insert(guiConnections, Farm.UI.ResetStatsButton.MouseButton1Click:Connect(
    function()
        if Farm.Enabled or Farm.WorkerRunning then
            Farm.UI.ResetStatsStatus.Text = "STOP FARM FIRST"
            Farm.UI.ResetStatsStatus.TextColor3 =
                Color3.fromRGB(255, 176, 96)
            return
        end
        local now = os.clock()
        if not Farm.ResetStatsArmedAt
            or now - Farm.ResetStatsArmedAt > 4 then
            Farm.ResetStatsArmedAt = now
            Farm.UI.ResetStatsButton.Text = "CONFIRM RESET"
            Farm.UI.ResetStatsStatus.Text = "CLICK AGAIN"
            Farm.UI.ResetStatsStatus.TextColor3 =
                Color3.fromRGB(255, 176, 96)
            return
        end
        Farm.ResetStatsArmedAt = nil
        Farm:ResetOverallStats()
        Farm.UI.ResetStatsButton.Text = "RESET OVERALL STATS"
        Farm.UI.ResetStatsStatus.Text = "RESET"
        Farm.UI.ResetStatsStatus.TextColor3 =
            Color3.fromRGB(91, 231, 150)
    end
))

table.insert(guiConnections, Farm.UI.ShutdownButton.MouseButton1Click:Connect(
    function()
        local now = os.clock()
        if not Farm.ShutdownArmedAt
            or now - Farm.ShutdownArmedAt > 4 then
            Farm.ShutdownArmedAt = now
            Farm.UI.ShutdownButton.Text = "CONFIRM SHUTDOWN"
            Farm.UI.ShutdownStatus.Text = "Click again within 4 seconds."
            Farm.UI.ShutdownStatus.TextColor3 =
                Color3.fromRGB(255, 176, 96)
            return
        end
        controller.Destroy()
    end
))

table.insert(guiConnections, Farm.UI.Start.MouseButton1Click:Connect(
    function()
        if Farm.Enabled then
            Farm:Stop("Stopped by user")
        else
            Farm:Start()
        end
    end
))

table.insert(guiConnections, Farm.UI.WebhookInput.Focused:Connect(function()
    if Farm.Config.WebhookUrl ~= "" then
        Farm.UI.WebhookInput.Text = ""
        Farm.UI.WebhookInput.PlaceholderText =
            "Paste replacement URL, or leave blank to keep saved URL"
    end
end))

table.insert(guiConnections, Farm.UI.WebhookInput.FocusLost:Connect(function()
    local entered = Farm.UI.WebhookInput.Text:match("^%s*(.-)%s*$")
    if entered ~= ""
        and not entered:find("••••••", 1, true) then
        if entered:match("^https://[^/]+/api/webhooks/") then
            Farm.Config.WebhookUrl = entered
            refreshWebhookUi("SAVED", "success")
        else
            refreshWebhookUi("INVALID URL", "error")
        end
    else
        refreshWebhookUi()
    end
end))

table.insert(guiConnections, Farm.UI.WebhookToggle.MouseButton1Click:Connect(
    function()
        if Farm.Config.WebhookUrl == "" then
            refreshWebhookUi("URL REQUIRED", "error")
            return
        end
        Farm.Config.WebhookEnabled =
            not (Farm.Config.WebhookEnabled == true)
        refreshWebhookUi(
            Farm.Config.WebhookEnabled
                    and "ON"
                or "OFF",
            Farm.Config.WebhookEnabled and "success" or nil
        )
    end
))

table.insert(guiConnections, Farm.UI.WebhookTest.MouseButton1Click:Connect(
    function()
        local ok, reason = Farm:Webhook(
            "Connection test",
            "Your BABFT control center webhook is connected.",
            3447003,
            Farm:SummaryFields(),
            true
        )
        refreshWebhookUi(
            ok and "TEST SENT" or "TEST FAILED: " .. tostring(reason),
            ok and "success" or "error"
        )
    end
))

table.insert(guiConnections, Farm.UI.WebhookClear.MouseButton1Click:Connect(
    function()
        Farm.Config.WebhookUrl = ""
        Farm.Config.WebhookEnabled = false
        Farm.UI.WebhookInput.Text = ""
        refreshWebhookUi("CLEARED")
    end
))

table.insert(guiConnections, Farm.UI.ResizeHandle.InputBegan:Connect(
    function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            resizing = true
            resizeStart = input.Position
            resizeScaleStart = math.clamp(
                tonumber(environment.__SliceHubBABFTControlCenterScale)
                    or 1,
                0.65,
                1.35
            )
        end
    end
))

table.insert(guiConnections, opacitySlider.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        opacityDragging = true
        setPreviewOpacityFromX(input.Position.X, false)
    end
end))

table.insert(guiConnections, UserInputService.InputChanged:Connect(function(input)
    if resizing and resizeStart
        and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - resizeStart
        local nextScale = math.clamp(
            resizeScaleStart + (delta.X + delta.Y) / 1100,
            0.65,
            1.35
        )
        environment.__SliceHubBABFTControlCenterScale = nextScale
        updateScale()
        return
    end
    if not opacityDragging then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        setPreviewOpacityFromX(input.Position.X, false)
    end
end))

table.insert(guiConnections, UserInputService.InputEnded:Connect(function(input)
    if resizing
        and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
        resizing = false
        resizeStart = nil
        controller.ClampToViewport()
        Farm:SaveGuiState(
            panel.Position,
            tonumber(environment.__SliceHubBABFTControlCenterScale) or 1,
            Farm.GuiState.minimized
        )
    end
    if Farm.FloatDragging
        and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
        Farm.FloatDragging = false
        Farm.GuiState.floatXScale = floatingButton.Position.X.Scale
        Farm.GuiState.floatXOffset = floatingButton.Position.X.Offset
        Farm.GuiState.floatYScale = floatingButton.Position.Y.Scale
        Farm.GuiState.floatYOffset = floatingButton.Position.Y.Offset
        Farm:SaveGuiState()
    end
    if not opacityDragging then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        opacityDragging = false
        setPreviewOpacityFromX(input.Position.X, true)
    end
end))

table.insert(guiConnections, header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        panelStart = panel.Position
    end
end))

table.insert(guiConnections, UserInputService.InputChanged:Connect(function(input)
    if not dragging or not dragStart or not panelStart then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local delta = input.Position - dragStart
    panel.Position = UDim2.new(
        panelStart.X.Scale,
        panelStart.X.Offset + delta.X,
        panelStart.Y.Scale,
        panelStart.Y.Offset + delta.Y
    )
end))

table.insert(guiConnections, UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        dragStart = nil
        panelStart = nil
        controller.ClampToViewport()
        Farm:SaveGuiState(
            panel.Position,
            tonumber(environment.__SliceHubBABFTControlCenterScale) or 1,
            Farm.GuiState.minimized
        )
    end
end))

table.insert(guiConnections, floatingButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        Farm.FloatDragging = true
        Farm.FloatMoved = false
        Farm.FloatDragStart = input.Position
        Farm.FloatPositionStart = floatingButton.Position
    end
end))

table.insert(guiConnections, UserInputService.InputChanged:Connect(function(input)
    if not Farm.FloatDragging
        or not Farm.FloatDragStart
        or not Farm.FloatPositionStart then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local delta = input.Position - Farm.FloatDragStart
    if math.abs(delta.X) + math.abs(delta.Y) > 6 then
        Farm.FloatMoved = true
    end
    floatingButton.Position = UDim2.new(
        Farm.FloatPositionStart.X.Scale,
        Farm.FloatPositionStart.X.Offset + delta.X,
        Farm.FloatPositionStart.Y.Scale,
        Farm.FloatPositionStart.Y.Offset + delta.Y
    )
end))

table.insert(guiConnections, floatingButton.MouseButton1Click:Connect(function()
    if not Farm.FloatMoved then
        controller.Show()
    end
end))

table.insert(guiConnections, UserInputService.InputBegan:Connect(
    function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.RightShift then
            controller.ToggleVisible()
        end
    end
))

table.insert(guiConnections, fileButton.MouseButton1Click:Connect(function()
    if #buildFiles == 0 then
        setStatus(
            "No exact .Build files found • press Refresh Files.",
            "error"
        )
        return
    end
    dropdown.Visible = not dropdown.Visible
    dropdown.Size = dropdown.Visible
            and UDim2.new(1, -180, 0, math.min(#buildFiles * 35, 180))
        or UDim2.new(1, -180, 0, 0)
end))

table.insert(guiConnections, refreshButton.MouseButton1Click:Connect(refreshFiles))
table.insert(guiConnections, previewButton.MouseButton1Click:Connect(beginPreview))
table.insert(guiConnections, walkableButton.MouseButton1Click:Connect(function()
    local nextState = not walkablePreview
    if nextState
        and previewModel
        and previewModel:GetAttribute("PerformanceLOD") == true then
        walkablePreview = false
        environment.__SliceHubBABFTPreviewWalkable = false
        updateWalkableUi()
        setStatus(
            "Walkable Preview is disabled for LOD previews with sampled gaps.",
            "error"
        )
        return
    end
    walkablePreview = nextState
    environment.__SliceHubBABFTPreviewWalkable = walkablePreview
    updateWalkableUi()
    applyWalkablePreview()
    setStatus(
        walkablePreview
                and "Walkable Preview ON • local collision only."
            or "Walkable Preview OFF • ghost collision disabled.",
        walkablePreview and "success" or nil
    )
end))
table.insert(guiConnections, removeButton.MouseButton1Click:Connect(function()
    removePreview("Preview removed • no real blocks were changed.")
end))
table.insert(guiConnections, placeTestButton.MouseButton1Click:Connect(
    controller.BeginFidelityTest
))
table.insert(guiConnections, stopTestButton.MouseButton1Click:Connect(
    stopPlacementTest
))
table.insert(guiConnections, saveDumpButton.MouseButton1Click:Connect(
    saveProtocolDump
))
table.insert(guiConnections, closeButton.MouseButton1Click:Connect(function()
    controller.Hide()
end))
table.insert(guiConnections, minimizeButton.MouseButton1Click:Connect(function()
    controller.SetMinimized(not Farm.GuiState.minimized)
end))

local cameraConnection = Workspace:GetPropertyChangedSignal(
    "CurrentCamera"
):Connect(function()
    updateScale()
    controller.BindViewport()
    task.defer(controller.ClampToViewport)
    if previewModel and Workspace.CurrentCamera then
        previewModel.Parent = Workspace.CurrentCamera
    end
end)
table.insert(guiConnections, cameraConnection)
controller.BindViewport()

function controller.RemovePreview()
    removePreview("Preview removed.")
end

function controller.RefreshFiles()
    refreshFiles()
end

function controller.Destroy()
    if destroyRequested then
        return
    end
    destroyRequested = true
    if Farm.Enabled or Farm.WorkerRunning then
        Farm:Stop("Control center closed")
    else
        environment.SliceHubBABFTAutoFarmStop = true
    end
    analysisGeneration = analysisGeneration + 1
    placementGeneration = placementGeneration + 1
    removePreview()
    for _, connection in ipairs(guiConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(guiConnections)
    if screenGui and screenGui.Parent then
        screenGui:Destroy()
    end
    if environment.__SliceHubBABFTAutoBuildPreviewController == controller then
        environment.__SliceHubBABFTAutoBuildPreviewController = nil
    end
    if environment.__SliceHubBABFTStandaloneFarmController == controller then
        environment.__SliceHubBABFTStandaloneFarmController = nil
    end
end

environment.__SliceHubBABFTAutoBuildPreviewController = controller
environment.__SliceHubBABFTStandaloneFarmController = controller
environment.__SliceHubBABFTControlCenter = controller
updateScale()
showFarmPage(true)
controller.SetMinimized(Farm.GuiState.minimized)
task.defer(controller.ClampToViewport)
refreshWebhookUi()
Farm.StartingGold = Farm:Gold() or 0
Farm.LastObservedGold = Farm.StartingGold
Farm:SetStatsView("session")
Farm:RefreshUI()
refreshFiles()
Farm.GoldObject = LocalPlayer:FindFirstChild("Data")
Farm.GoldObject = Farm.GoldObject
    and Farm.GoldObject:FindFirstChild("Gold")
if Farm.GoldObject then
    table.insert(
        guiConnections,
        Farm.GoldObject:GetPropertyChangedSignal("Value"):Connect(function()
            Farm:TrackGold()
            Farm:RefreshUI()
        end)
    )
end
task.spawn(function()
    while not destroyRequested do
        Farm:TrackGold()
        Farm:RefreshUI()
        task.wait(1)
    end
end)
