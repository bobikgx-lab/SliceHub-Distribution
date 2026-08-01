-- Slice Utility | Custom UI Toggle Key Build | 2026-08-02
-- Adds global search, favorites, quick actions, keybinds, saved position, panic reset, and finder workflow polish.

--[[
    Slice Utility
    Universal Roblox utility + developer tools hub.

    Tabs:
      1. Utility        - native movement, visual, teleport, and player helpers
      2. Developer Tools - script/tool launchers such as Dex++, SimpleSpy

    RightShift toggles the interface.
    This project is an original clean-room UI/architecture inspired by the useful
    categories found in command suites such as Infinite Yield.
]]

if getgenv and getgenv().SliceUtilityLoaded then
    return
end
if getgenv then
    getgenv().SliceUtilityLoaded = true
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Services = setmetatable({}, {
    __index = function(self, key)
        local service = game:GetService(key)
        rawset(self, key, service)
        return service
    end,
})

local Players = Services.Players
local RunService = Services.RunService
local UserInputService = Services.UserInputService
local TweenService = Services.TweenService
local TeleportService = Services.TeleportService
local HttpService = Services.HttpService
local StarterGui = Services.StarterGui
local Lighting = Services.Lighting
local CoreGui = Services.CoreGui

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local State = {
    visible = true,
    destroyed = false,
    fly = false,
    flySpeed = 60,
    noclip = false,
    infiniteJump = false,
    clickTeleport = false,
    esp = false,
    fullbright = false,
    walkSpeed = 16,
    jumpPower = 50,
    gravity = workspace.Gravity,
    fieldOfView = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70,
    antiAfk = false,
    xray = false,
    launcherVisible = true,
    sprint = false,
    sprintSpeed = 32,
    removeFog = false,
    lowGraphics = false,
    removeTextures = false,
    infiniteZoom = false,
    npcEsp = false,
    savedCFrame = nil,
    windowWidth = 760,
    windowHeight = 500,
    windowPositionX = nil,
    windowPositionY = nil,
    favorites = {},
    keybinds = {ToggleUI = "RightShift", Fly = "F", Noclip = "N", ESP = "P"},
    originalWorld = {},
    connections = {},
    espObjects = {},
    originalLighting = {},
    originalCollisions = {},
    originalTransparency = {},
}


local GUI_CONFIG_FILE = "SliceUtility/interface.json"

local function loadWindowSize()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
    local ok, data = pcall(function()
        if not isfile(GUI_CONFIG_FILE) then return nil end
        return HttpService:JSONDecode(readfile(GUI_CONFIG_FILE))
    end)
    if ok and type(data) == "table" then
        State.windowWidth = math.clamp(tonumber(data.width) or State.windowWidth, 620, 1600)
        State.windowHeight = math.clamp(tonumber(data.height) or State.windowHeight, 420, 1000)
        State.windowPositionX = tonumber(data.positionX)
        State.windowPositionY = tonumber(data.positionY)
        if type(data.favorites) == "table" then State.favorites = data.favorites end
        if type(data.keybinds) == "table" then
            for name, key in pairs(data.keybinds) do State.keybinds[name] = tostring(key) end
        end
    end
end

local function saveWindowSize()
    if type(writefile) ~= "function" then return end
    pcall(function()
        if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("SliceUtility") then
            makefolder("SliceUtility")
        end
        writefile(GUI_CONFIG_FILE, HttpService:JSONEncode({
            width = math.floor(State.windowWidth + 0.5),
            height = math.floor(State.windowHeight + 0.5),
            positionX = State.windowPositionX,
            positionY = State.windowPositionY,
            favorites = State.favorites,
            keybinds = State.keybinds,
        }))
    end)
end

loadWindowSize()

local function track(connection)
    table.insert(State.connections, connection)
    return connection
end

local function safeDisconnect(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHumanoid()
    local character = getCharacter()
    return character:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local character = getCharacter()
    return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
end

local function protectGui(gui)
    local protect = (syn and syn.protect_gui) or protectgui
    if protect then
        pcall(protect, gui)
    end
end

local function chooseParent()
    local hidden = gethui or get_hidden_gui
    if hidden then
        local ok, result = pcall(hidden)
        if ok and result then
            return result
        end
    end
    return CoreGui
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SliceUtility"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
protectGui(ScreenGui)
ScreenGui.Parent = chooseParent()

local function new(className, properties)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    return object
end

local Theme = {
    Background = Color3.fromRGB(13, 15, 20),
    Surface = Color3.fromRGB(22, 25, 33),
    Surface2 = Color3.fromRGB(31, 35, 45),
    Accent = Color3.fromRGB(46, 196, 182),
    Text = Color3.fromRGB(239, 242, 247),
    Muted = Color3.fromRGB(150, 158, 174),
    Danger = Color3.fromRGB(230, 84, 84),
    Success = Color3.fromRGB(75, 205, 122),
}

local function addCorner(parent, radius)
    new("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
        Parent = parent,
    })
end

local function addStroke(parent, transparency)
    new("UIStroke", {
        Color = Color3.fromRGB(54, 61, 77),
        Transparency = transparency or 0.35,
        Thickness = 1,
        Parent = parent,
    })
end

local function notify(title, message, duration)
    duration = duration or 3
    local holder = ScreenGui:FindFirstChild("Notifications")
    if not holder then
        holder = new("Frame", {
            Name = "Notifications",
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -330, 0, 20),
            Size = UDim2.new(0, 310, 1, -40),
            Parent = ScreenGui,
        })
        new("UIListLayout", {
            Padding = UDim.new(0, 8),
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Top,
            Parent = holder,
        })
    end

    local card = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0.03,
        Size = UDim2.new(1, 0, 0, 76),
        Parent = holder,
    })
    addCorner(card, 9)
    addStroke(card, 0.25)

    new("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 4, 1, 0),
        Parent = card,
    })
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 9),
        Size = UDim2.new(1, -28, 0, 20),
        Font = Enum.Font.GothamBold,
        Text = tostring(title),
        TextColor3 = Theme.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 31),
        Size = UDim2.new(1, -28, 0, 35),
        Font = Enum.Font.Gotham,
        Text = tostring(message),
        TextColor3 = Theme.Muted,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = card,
    })

    card.Position = UDim2.new(1, 30, 0, 0)
    TweenService:Create(card, TweenInfo.new(0.22), {Position = UDim2.new(0, 0, 0, 0)}):Play()
    task.delay(duration, function()
        if card.Parent then
            local tween = TweenService:Create(card, TweenInfo.new(0.2), {
                BackgroundTransparency = 1,
                Position = UDim2.new(1, 30, 0, 0),
            })
            tween:Play()
            tween.Completed:Wait()
            card:Destroy()
        end
    end)
end

local Main = new("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Theme.Background,
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(State.windowWidth, State.windowHeight),
    Parent = ScreenGui,
})
addCorner(Main, 12)
addStroke(Main, 0.15)

-- Small draggable launcher inspired by compact command-suite corner buttons.
-- It remains available while the main interface is hidden and can be moved anywhere.
local Launcher = new("TextButton", {
    Name = "Launcher",
    AutoButtonColor = false,
    AnchorPoint = Vector2.new(1, 1),
    BackgroundColor3 = Theme.Surface,
    Position = UDim2.new(1, -18, 1, -18),
    Size = UDim2.fromOffset(48, 48),
    Font = Enum.Font.GothamBold,
    Text = "SU",
    TextColor3 = Theme.Text,
    TextSize = 15,
    ZIndex = 50,
    Parent = ScreenGui,
})
addCorner(Launcher, 12)
addStroke(Launcher, 0.1)

local LauncherAccent = new("Frame", {
    Name = "Accent",
    AnchorPoint = Vector2.new(0.5, 1),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, 0, 1, -5),
    Size = UDim2.new(0.55, 0, 0, 3),
    ZIndex = 51,
    Parent = Launcher,
})
addCorner(LauncherAccent, 3)

local Scale = new("UIScale", {Scale = 1, Parent = Main})
local BaseScale = 1
local WindowTween

local function tweenWindow(show)
    if WindowTween then pcall(function() WindowTween:Cancel() end) end
    TweenService:Create(Launcher, TweenInfo.new(0.16), {
        BackgroundColor3 = show and Theme.Accent or Theme.Surface,
        TextColor3 = show and Color3.fromRGB(9, 21, 23) or Theme.Text,
    }):Play()
    if show then
        Main.Visible = true
        Main.BackgroundTransparency = 0.08
        Scale.Scale = BaseScale * 0.92
        WindowTween = TweenService:Create(Scale, TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Scale = BaseScale})
        TweenService:Create(Main, TweenInfo.new(0.2), {BackgroundTransparency = 0}):Play()
        WindowTween:Play()
    else
        WindowTween = TweenService:Create(Scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = BaseScale * 0.92})
        TweenService:Create(Main, TweenInfo.new(0.16), {BackgroundTransparency = 0.12}):Play()
        WindowTween:Play()
        task.delay(0.17, function()
            if not State.visible and Main.Parent then Main.Visible = false end
        end)
    end
end

local viewport = Camera.ViewportSize
if viewport.X < 850 or viewport.Y < 580 then
    Scale.Scale = math.clamp(math.min(viewport.X / 820, viewport.Y / 560), 0.68, 1)
end
BaseScale = Scale.Scale

local Header = new("Frame", {
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 54),
    Parent = Main,
})
addCorner(Header, 12)
new("Frame", {
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 1, -12),
    Size = UDim2.new(1, 0, 0, 12),
    Parent = Header,
})

new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 20, 0, 0),
    Size = UDim2.new(0, 260, 1, 0),
    Font = Enum.Font.GothamBold,
    Text = "Slice Utility",
    TextColor3 = Theme.Text,
    TextSize = 20,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = Header,
})

local HeaderSubtitle = new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(1, -220, 0, 0),
    Size = UDim2.new(0, 170, 1, 0),
    Font = Enum.Font.Gotham,
    Text = "Drag SU • " .. tostring(State.keybinds.ToggleUI or "RightShift") .. " to hide",
    TextColor3 = Theme.Muted,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = Header,
})

local CloseButton = new("TextButton", {
    AutoButtonColor = false,
    BackgroundColor3 = Theme.Surface2,
    Position = UDim2.new(1, -42, 0.5, -14),
    Size = UDim2.fromOffset(28, 28),
    Font = Enum.Font.GothamBold,
    Text = "×",
    TextColor3 = Theme.Muted,
    TextSize = 18,
    Parent = Header,
})
addCorner(CloseButton, 7)

local Sidebar = new("Frame", {
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0, 54),
    Size = UDim2.new(0, 184, 1, -54),
    Parent = Main,
})
new("UIPadding", {
    PaddingTop = UDim.new(0, 14),
    PaddingLeft = UDim.new(0, 12),
    PaddingRight = UDim.new(0, 12),
    Parent = Sidebar,
})
local SidebarLayout = new("UIListLayout", {
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = Sidebar,
})

local Content = new("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 184, 0, 54),
    Size = UDim2.new(1, -184, 1, -54),
    Parent = Main,
})

local ResizeGrip = new("TextButton", {
    Name = "ResizeGrip",
    AutoButtonColor = false,
    AnchorPoint = Vector2.new(1, 1),
    BackgroundColor3 = Theme.Surface2,
    BackgroundTransparency = 0.15,
    Position = UDim2.new(1, -7, 1, -7),
    Size = UDim2.fromOffset(22, 22),
    Font = Enum.Font.GothamBold,
    Text = "⌟",
    TextColor3 = Theme.Accent,
    TextSize = 17,
    ZIndex = 30,
    Parent = Main,
})
addCorner(ResizeGrip, 6)
addStroke(ResizeGrip, 0.35)

local Pages = {}
local TabButtons = {}

local function createPage(name)
    local page = new("ScrollingFrame", {
        Name = name,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Theme.Accent,
        Position = UDim2.new(0, 18, 0, 16),
        Size = UDim2.new(1, -36, 1, -32),
        Visible = false,
        Parent = Content,
    })
    new("UIPadding", {
        PaddingBottom = UDim.new(0, 18),
        Parent = page,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = page,
    })
    Pages[name] = page
    return page
end

local CurrentPage
local function showPage(name)
    local nextPage = Pages[name]
    if not nextPage or CurrentPage == nextPage then return end
    if CurrentPage then
        CurrentPage.Visible = false
    end
    nextPage.Visible = true
    nextPage.Position = UDim2.new(0, 30, 0, 16)
    nextPage.ScrollBarImageTransparency = 1
    TweenService:Create(nextPage, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 18, 0, 16),
        ScrollBarImageTransparency = 0,
    }):Play()
    CurrentPage = nextPage
    for tabName, button in pairs(TabButtons) do
        local active = tabName == name
        TweenService:Create(button, TweenInfo.new(0.15), {
            BackgroundColor3 = active and Theme.Accent or Theme.Surface2,
            TextColor3 = active and Color3.fromRGB(9, 21, 23) or Theme.Text,
        }):Play()
    end
end

local function createTab(name, order)
    local button = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Surface2,
        LayoutOrder = order,
        Size = UDim2.new(1, 0, 0, 42),
        Font = Enum.Font.GothamSemibold,
        Text = name,
        TextColor3 = Theme.Text,
        TextSize = 13,
        Parent = Sidebar,
    })
    addCorner(button, 8)
    TabButtons[name] = button
    track(button.MouseButton1Click:Connect(function()
        showPage(name)
    end))
    return createPage(name)
end

local HomePage = createTab("Quick Actions", 1)
local UtilityPage = createTab("Utility", 2)
local DeveloperPage = createTab("Developer Tools", 3)
local SettingsPage = createTab("Settings", 4)

local function createSection(page, title, description)
    local section = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 0),
        Parent = page,
    })
    addCorner(section, 10)
    addStroke(section, 0.45)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 14),
        PaddingBottom = UDim.new(0, 14),
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
        Parent = section,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = section,
    })
    new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 20),
        Font = Enum.Font.GothamBold,
        Text = title,
        TextColor3 = Theme.Text,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = section,
    })
    if description then
        new("TextLabel", {
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
            Font = Enum.Font.Gotham,
            Text = description,
            TextColor3 = Theme.Muted,
            TextSize = 12,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = section,
        })
    end
    return section
end

local ActionRegistry = {}
local ActionOrder = {}
local QuickActionsSection

local function favoriteContains(name)
    return table.find(State.favorites, name) ~= nil
end

local function setFavorite(name, enabled)
    local index = table.find(State.favorites, name)
    if enabled and not index then table.insert(State.favorites, name) end
    if not enabled and index then table.remove(State.favorites, index) end
    saveWindowSize()
end

local function runAction(name)
    local action = ActionRegistry[name]
    if not action then return false end
    local ok, err = pcall(action.callback)
    if not ok then notify("Action failed", tostring(err), 5) end
    return ok
end

local function createButton(parent, text, callback, danger)
    local button = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = danger and Theme.Danger or Theme.Surface2,
        Size = UDim2.new(1, 0, 0, 38),
        Font = Enum.Font.GothamSemibold,
        Text = text,
        TextColor3 = Theme.Text,
        TextSize = 13,
        Parent = parent,
    })
    addCorner(button, 8)
    track(button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), {
            BackgroundTransparency = 0.12,
        }):Play()
    end))
    track(button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), {
            BackgroundTransparency = 0,
        }):Play()
    end))
    track(button.MouseButton1Down:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.08), {Size = UDim2.new(1, -6, 0, 36)}):Play()
    end))
    track(button.MouseButton1Up:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.1), {Size = UDim2.new(1, 0, 0, 38)}):Play()
    end))
    if not ActionRegistry[text] then table.insert(ActionOrder, text) end
    ActionRegistry[text] = {callback = callback, button = button}
    button.TextXAlignment = Enum.TextXAlignment.Left
    button.Text = "   " .. text
    local star = new("TextButton", {
        AutoButtonColor = false, BackgroundTransparency = 1,
        Position = UDim2.new(1, -38, 0, 0), Size = UDim2.fromOffset(38, 38),
        Font = Enum.Font.GothamBold, Text = favoriteContains(text) and "★" or "☆",
        TextColor3 = Theme.Accent, TextSize = 17, ZIndex = button.ZIndex + 1, Parent = button,
    })
    track(star.MouseButton1Click:Connect(function()
        local enabled = not favoriteContains(text)
        setFavorite(text, enabled)
        star.Text = enabled and "★" or "☆"
        notify("Favorites", (enabled and "Added " or "Removed ") .. text, 2)
    end))
    track(button.MouseButton1Click:Connect(function()
        runAction(text)
    end))
    return button
end

local function createToggle(parent, label, initial, callback)
    local enabled = initial
    local row = new("Frame", {
        BackgroundColor3 = Theme.Surface2,
        Size = UDim2.new(1, 0, 0, 42),
        Parent = parent,
    })
    addCorner(row, 8)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -74, 1, 0),
        Font = Enum.Font.GothamSemibold,
        Text = label,
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    local switch = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = enabled and Theme.Accent or Color3.fromRGB(70, 76, 90),
        Position = UDim2.new(1, -51, 0.5, -12),
        Size = UDim2.fromOffset(39, 24),
        Text = "",
        Parent = row,
    })
    addCorner(switch, 12)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(245, 247, 250),
        Position = enabled and UDim2.new(1, -12, 0.5, 0) or UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        Parent = switch,
    })
    addCorner(knob, 9)
    local function set(value)
        enabled = value
        TweenService:Create(switch, TweenInfo.new(0.15), {
            BackgroundColor3 = enabled and Theme.Accent or Color3.fromRGB(70, 76, 90),
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = enabled and UDim2.new(1, -12, 0.5, 0) or UDim2.new(0, 12, 0.5, 0),
        }):Play()
        callback(enabled)
    end
    track(switch.MouseButton1Click:Connect(function()
        set(not enabled)
    end))
    if not ActionRegistry[label] then table.insert(ActionOrder, label) end
    ActionRegistry[label] = {callback = function() set(not enabled) end, button = switch}
    return row, set
end

local function createNumberInput(parent, label, value, callback)
    local row = new("Frame", {
        BackgroundColor3 = Theme.Surface2,
        Size = UDim2.new(1, 0, 0, 42),
        Parent = parent,
    })
    addCorner(row, 8)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -116, 1, 0),
        Font = Enum.Font.GothamSemibold,
        Text = label,
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    local box = new("TextBox", {
        BackgroundColor3 = Theme.Background,
        Position = UDim2.new(1, -100, 0.5, -14),
        Size = UDim2.fromOffset(88, 28),
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        Text = tostring(value),
        TextColor3 = Theme.Text,
        PlaceholderColor3 = Theme.Muted,
        TextSize = 12,
        Parent = row,
    })
    addCorner(box, 7)
    track(box.FocusLost:Connect(function()
        local number = tonumber(box.Text)
        if not number then
            box.Text = tostring(value)
            notify("Invalid value", label .. " must be a number")
            return
        end
        value = number
        callback(number)
        box.Text = tostring(number)
    end))
    return row
end


local function createTextAction(parent, label, placeholder, buttonText, callback)
    local row = new("Frame", {
        BackgroundColor3 = Theme.Surface2,
        Size = UDim2.new(1, 0, 0, 46),
        Parent = parent,
    })
    addCorner(row, 8)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(0.28, 0, 1, 0),
        Font = Enum.Font.GothamSemibold,
        Text = label,
        TextColor3 = Theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    local box = new("TextBox", {
        BackgroundColor3 = Theme.Background,
        Position = UDim2.new(0.28, 5, 0.5, -14),
        Size = UDim2.new(0.49, -10, 0, 28),
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        Text = "",
        PlaceholderText = placeholder,
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    addCorner(box, 7)
    local action = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Accent,
        Position = UDim2.new(0.77, 4, 0.5, -14),
        Size = UDim2.new(0.23, -16, 0, 28),
        Font = Enum.Font.GothamBold,
        Text = buttonText,
        TextColor3 = Color3.fromRGB(9, 21, 23),
        TextSize = 11,
        Parent = row,
    })
    addCorner(action, 7)
    track(action.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback, box.Text, box)
        if not ok then notify("Action failed", tostring(err), 5) end
    end))
    return row, box
end

-- Quick actions and global search -------------------------------------------
local searchSection = createSection(HomePage, "Global Search", "Search every Utility and Developer Tools action from one place.")
local searchResults = createSection(HomePage, "Results", "Enter a feature name, then click a result to run it.")
local favoritesSection = createSection(HomePage, "Favorites", "Star any action to pin it here. Refresh after changing favorites.")

local function clearGenerated(section)
    for _, child in ipairs(section:GetChildren()) do
        if child:GetAttribute("GeneratedAction") then child:Destroy() end
    end
end

local function createGeneratedAction(section, name)
    local button = new("TextButton", {AutoButtonColor = false, BackgroundColor3 = Theme.Surface2, Size = UDim2.new(1,0,0,38), Font = Enum.Font.GothamSemibold, Text = "   " .. name, TextColor3 = Theme.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = section})
    button:SetAttribute("GeneratedAction", true)
    addCorner(button, 8)
    track(button.MouseButton1Click:Connect(function() runAction(name) end))
    return button
end

local function refreshFavorites()
    clearGenerated(favoritesSection)
    if #State.favorites == 0 then
        local label = new("TextLabel", {BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1,0,0,0), Font = Enum.Font.Gotham, Text = "No favorites yet. Tap ☆ beside any action.", TextColor3 = Theme.Muted, TextSize = 12, TextWrapped = true, Parent = favoritesSection})
        label:SetAttribute("GeneratedAction", true)
        return
    end
    for _, name in ipairs(State.favorites) do
        if ActionRegistry[name] then
            createGeneratedAction(favoritesSection, name)
        end
    end
end

local _, globalSearchBox = createTextAction(searchSection, "Search", "fly, dex, fog, remote...", "Find", function(query)
    clearGenerated(searchResults)
    query = string.lower((query or ""):match("^%s*(.-)%s*$"))
    local count = 0
    for _, name in ipairs(ActionOrder) do
        if query == "" or string.find(string.lower(name), query, 1, true) then
            count += 1
            createGeneratedAction(searchResults, name)
            if count >= 18 then break end
        end
    end
    notify("Global Search", tostring(count) .. " result(s)", 2)
end)
createButton(favoritesSection, "Refresh Favorites", refreshFavorites)

-- Utility systems -----------------------------------------------------------
local Fly = {connection = nil, attachment = nil, velocity = nil, orientation = nil}
local flyKeys = {W = false, A = false, S = false, D = false, Q = false, E = false}

local function stopFly()
    State.fly = false
    safeDisconnect(Fly.connection)
    Fly.connection = nil
    for _, object in ipairs({Fly.velocity, Fly.orientation, Fly.attachment}) do
        if object then pcall(function() object:Destroy() end) end
    end
    Fly.velocity, Fly.orientation, Fly.attachment = nil, nil, nil
    local humanoid = getHumanoid()
    if humanoid then humanoid.PlatformStand = false end
end

local function startFly()
    stopFly()
    State.fly = true
    local root = getRoot()
    local humanoid = getHumanoid()
    if not root or not humanoid then
        State.fly = false
        return notify("Fly", "Character is not ready")
    end

    local attachment = new("Attachment", {Name = "SliceFlyAttachment", Parent = root})
    local velocity = new("LinearVelocity", {
        Name = "SliceFlyVelocity",
        Attachment0 = attachment,
        MaxForce = math.huge,
        VectorVelocity = Vector3.zero,
        RelativeTo = Enum.ActuatorRelativeTo.World,
        Parent = root,
    })
    local orientation = new("AlignOrientation", {
        Name = "SliceFlyOrientation",
        Attachment0 = attachment,
        MaxTorque = math.huge,
        Responsiveness = 25,
        Mode = Enum.OrientationAlignmentMode.OneAttachment,
        Parent = root,
    })
    Fly.attachment, Fly.velocity, Fly.orientation = attachment, velocity, orientation
    humanoid.PlatformStand = true

    Fly.connection = RunService.RenderStepped:Connect(function()
        if not State.fly or not root.Parent then return end
        Camera = workspace.CurrentCamera
        local direction = Vector3.zero
        if flyKeys.W then direction += Camera.CFrame.LookVector end
        if flyKeys.S then direction -= Camera.CFrame.LookVector end
        if flyKeys.D then direction += Camera.CFrame.RightVector end
        if flyKeys.A then direction -= Camera.CFrame.RightVector end
        if flyKeys.E then direction += Vector3.yAxis end
        if flyKeys.Q then direction -= Vector3.yAxis end
        velocity.VectorVelocity = direction.Magnitude > 0 and direction.Unit * State.flySpeed or Vector3.zero
        orientation.CFrame = CFrame.lookAt(root.Position, root.Position + Camera.CFrame.LookVector)
    end)
end

local function setNoclip(enabled)
    State.noclip = enabled
    if not enabled then
        for part, original in pairs(State.originalCollisions) do
            if part and part.Parent then part.CanCollide = original end
        end
        State.originalCollisions = {}
    end
end

local function setESP(enabled)
    State.esp = enabled
    for _, object in pairs(State.espObjects) do
        pcall(function() object:Destroy() end)
    end
    State.espObjects = {}
    if not enabled then return end

    local function addESP(player)
        if player == LocalPlayer then return end
        local function attach(character)
            if not State.esp then return end
            local highlight = new("Highlight", {
                Name = "SliceESP",
                Adornee = character,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                FillColor = Theme.Accent,
                FillTransparency = 0.65,
                OutlineColor = Color3.new(1, 1, 1),
                OutlineTransparency = 0.1,
                Parent = ScreenGui,
            })
            State.espObjects[player] = highlight
        end
        if player.Character then attach(player.Character) end
        track(player.CharacterAdded:Connect(attach))
    end
    for _, player in ipairs(Players:GetPlayers()) do addESP(player) end
end

local function setFullbright(enabled)
    State.fullbright = enabled
    if enabled then
        State.originalLighting = {
            Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd,
            GlobalShadows = Lighting.GlobalShadows,
            Ambient = Lighting.Ambient,
        }
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
    elseif next(State.originalLighting) then
        for key, value in pairs(State.originalLighting) do
            Lighting[key] = value
        end
    end
end

local movement = createSection(UtilityPage, "Movement", "Universal movement controls. Fly uses WASD, E to rise, and Q to descend.")
createToggle(movement, "Fly", false, function(enabled)
    if enabled then startFly() else stopFly() end
end)
createNumberInput(movement, "Fly Speed", State.flySpeed, function(value)
    State.flySpeed = math.clamp(value, 1, 500)
end)
createNumberInput(movement, "WalkSpeed", State.walkSpeed, function(value)
    State.walkSpeed = math.clamp(value, 0, 500)
    local humanoid = getHumanoid()
    if humanoid then humanoid.WalkSpeed = State.walkSpeed end
end)
createNumberInput(movement, "JumpPower", State.jumpPower, function(value)
    State.jumpPower = math.clamp(value, 0, 500)
    local humanoid = getHumanoid()
    if humanoid then
        humanoid.UseJumpPower = true
        humanoid.JumpPower = State.jumpPower
    end
end)
createNumberInput(movement, "Gravity", State.gravity, function(value)
    State.gravity = math.clamp(value, 0, 1000)
    workspace.Gravity = State.gravity
end)
createNumberInput(movement, "Sprint Speed", State.sprintSpeed, function(value)
    State.sprintSpeed = math.clamp(value, 1, 500)
end)
createToggle(movement, "Shift Sprint", false, function(enabled)
    State.sprint = enabled
    local humanoid = getHumanoid()
    if humanoid and not enabled then humanoid.WalkSpeed = State.walkSpeed end
end)
createToggle(movement, "Noclip", false, setNoclip)
createToggle(movement, "Infinite Jump", false, function(enabled)
    State.infiniteJump = enabled
end)
createToggle(movement, "Click Teleport (Ctrl + Click)", false, function(enabled)
    State.clickTeleport = enabled
end)

local world = createSection(UtilityPage, "World", "Reversible client-side world and performance controls.")
createToggle(world, "Fullbright", false, setFullbright)
createToggle(world, "Remove Fog", false, function(enabled)
    State.removeFog = enabled
    if enabled then
        State.originalWorld.FogStart = Lighting.FogStart
        State.originalWorld.FogEnd = Lighting.FogEnd
        Lighting.FogStart = 0
        Lighting.FogEnd = 1000000
    else
        Lighting.FogStart = State.originalWorld.FogStart or 0
        Lighting.FogEnd = State.originalWorld.FogEnd or 100000
    end
end)
createToggle(world, "X-Ray World", false, function(enabled)
    State.xray = enabled
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("BasePart") and not (LocalPlayer.Character and object:IsDescendantOf(LocalPlayer.Character)) then
            if enabled then
                if State.originalTransparency[object] == nil then State.originalTransparency[object] = object.LocalTransparencyModifier end
                object.LocalTransparencyModifier = math.max(object.LocalTransparencyModifier, 0.65)
            elseif State.originalTransparency[object] ~= nil then
                object.LocalTransparencyModifier = State.originalTransparency[object]
            end
        end
    end
    if not enabled then State.originalTransparency = {} end
end)
createToggle(world, "Remove Textures", false, function(enabled)
    State.removeTextures = enabled
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("Texture") or object:IsA("Decal") then
            if State.originalWorld[object] == nil then State.originalWorld[object] = object.Transparency end
            object.Transparency = enabled and 1 or State.originalWorld[object]
        end
    end
end)
createToggle(world, "Low Graphics", false, function(enabled)
    State.lowGraphics = enabled
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("BasePart") then
            if State.originalWorld[object] == nil then State.originalWorld[object] = object.Material end
            object.Material = enabled and Enum.Material.SmoothPlastic or State.originalWorld[object]
            object.CastShadow = not enabled
        elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam") then
            object.Enabled = not enabled
        end
    end
    Lighting.GlobalShadows = not enabled
end)

local visual = createSection(UtilityPage, "Visual", "Player, NPC, camera, and visibility helpers.")
createToggle(visual, "Player ESP", false, setESP)
createToggle(visual, "NPC ESP", false, function(enabled)
    State.npcEsp = enabled
    for key, object in pairs(State.espObjects) do
        if type(key) == "string" and key:sub(1, 4) == "NPC:" then pcall(function() object:Destroy() end) State.espObjects[key] = nil end
    end
    if not enabled then return end
    local count = 0
    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(model) then
            count += 1
            local highlight = new("Highlight", {
                Name = "SliceNPCEsp",
                Adornee = model,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                FillColor = Color3.fromRGB(255, 179, 71),
                FillTransparency = 0.68,
                OutlineColor = Color3.new(1, 1, 1),
                OutlineTransparency = 0.15,
                Parent = ScreenGui,
            })
            State.espObjects["NPC:" .. tostring(count)] = highlight
        end
    end
    notify("NPC ESP", string.format("Highlighted %d NPC models", count))
end)
createNumberInput(visual, "Camera FOV", State.fieldOfView, function(value)
    State.fieldOfView = math.clamp(value, 1, 120)
    Camera.FieldOfView = State.fieldOfView
end)
createToggle(visual, "Infinite Zoom", false, function(enabled)
    State.infiniteZoom = enabled
    if enabled then
        State.originalWorld.CameraMaxZoomDistance = LocalPlayer.CameraMaxZoomDistance
        LocalPlayer.CameraMaxZoomDistance = 100000
    else
        LocalPlayer.CameraMaxZoomDistance = State.originalWorld.CameraMaxZoomDistance or 128
    end
end)
createButton(visual, "Sit / Stand", function()
    local humanoid = getHumanoid()
    if humanoid then humanoid.Sit = not humanoid.Sit end
end)
createButton(visual, "Reset Character", function()
    local humanoid = getHumanoid()
    if humanoid then humanoid.Health = 0 end
end)

local teleport = createSection(UtilityPage, "Teleport", "Save locations, return instantly, and teleport to players.")
createButton(teleport, "Save Current Position", function()
    local root = getRoot()
    if not root then return notify("Position", "Character root not found") end
    State.savedCFrame = root.CFrame
    notify("Position", "Current position saved")
end)
createButton(teleport, "Return to Saved Position", function()
    local root = getRoot()
    if not root or not State.savedCFrame then return notify("Position", "No saved position yet") end
    root.CFrame = State.savedCFrame
end)
createTextAction(teleport, "Player", "name / display name", "Teleport", function(query)
    query = string.lower(query or "")
    if query == "" then return notify("Teleport", "Enter a player name") end
    local target
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and (string.sub(string.lower(player.Name), 1, #query) == query or string.sub(string.lower(player.DisplayName), 1, #query) == query) then
            target = player break
        end
    end
    local targetRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local root = getRoot()
    if not targetRoot or not root then return notify("Teleport", "Player or character not found") end
    root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)
end)
createButton(teleport, "Copy Position Vector3", function()
    local root = getRoot()
    if not root then return notify("Position", "Character root not found") end
    local pos = root.Position
    local text = string.format("Vector3.new(%.3f, %.3f, %.3f)", pos.X, pos.Y, pos.Z)
    local clipboard = setclipboard or toclipboard or set_clipboard
    if clipboard then clipboard(text) end
    notify("Position", clipboard and "Vector3 copied" or text, 5)
end)
createButton(teleport, "Copy Full CFrame", function()
    local root = getRoot()
    if not root then return notify("CFrame", "Character root not found") end
    local components = {root.CFrame:GetComponents()}
    local formatted = {}
    for _, value in ipairs(components) do table.insert(formatted, string.format("%.6f", value)) end
    local text = "CFrame.new(" .. table.concat(formatted, ", ") .. ")"
    local clipboard = setclipboard or toclipboard or set_clipboard
    if clipboard then clipboard(text) end
    notify("CFrame", clipboard and "Full CFrame copied" or "Printed to console", 5)
    if not clipboard then print(text) end
end)

local utility = createSection(UtilityPage, "Utility", "Session, clipboard, camera, and quality-of-life actions.")
createToggle(utility, "Anti AFK", false, function(enabled)
    State.antiAfk = enabled
    notify("Anti AFK", enabled and "Enabled" or "Disabled")
end)
createButton(utility, "Reset Movement & Camera", function()
    State.walkSpeed, State.jumpPower, State.gravity, State.fieldOfView = 16, 50, 196.2, 70
    workspace.Gravity = 196.2
    Camera.FieldOfView = 70
    local humanoid = getHumanoid()
    if humanoid then humanoid.WalkSpeed = 16 humanoid.UseJumpPower = true humanoid.JumpPower = 50 end
    notify("Defaults", "Movement and camera restored")
end)
createButton(utility, "Rejoin Server", function()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end)
createButton(utility, "Server Hop", function()
    local response = game:HttpGet(string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true", game.PlaceId))
    local body = HttpService:JSONDecode(response)
    local choices = {}
    for _, server in ipairs(body.data or {}) do
        if server.id ~= game.JobId and server.playing < server.maxPlayers then table.insert(choices, server.id) end
    end
    if #choices == 0 then return notify("Server Hop", "No available server found") end
    TeleportService:TeleportToPlaceInstance(game.PlaceId, choices[math.random(1, #choices)], LocalPlayer)
end)
createButton(utility, "Join Smallest Server", function()
    local response = game:HttpGet(string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true", game.PlaceId))
    local body = HttpService:JSONDecode(response)
    local best
    for _, server in ipairs(body.data or {}) do
        if server.id ~= game.JobId and server.playing < server.maxPlayers and (not best or server.playing < best.playing) then best = server end
    end
    if not best then return notify("Small Server", "No available server found") end
    TeleportService:TeleportToPlaceInstance(game.PlaceId, best.id, LocalPlayer)
end)
createButton(utility, "Copy Game Link", function()
    local text = "https://www.roblox.com/games/" .. tostring(game.PlaceId)
    local clipboard = setclipboard or toclipboard or set_clipboard
    if clipboard then clipboard(text) end
    notify("Game Link", clipboard and "Copied" or text, 5)
end)
createButton(utility, "Copy PlaceId / JobId / UserId", function()
    local text = string.format("PlaceId: %s\nJobId: %s\nUserId: %s", tostring(game.PlaceId), tostring(game.JobId), tostring(LocalPlayer.UserId))
    local clipboard = setclipboard or toclipboard or set_clipboard
    if clipboard then clipboard(text) end
    notify("Game IDs", clipboard and "Copied all IDs" or text, 5)
end)
createButton(utility, "Open Developer Console", function()
    StarterGui:SetCore("DevConsoleVisible", true)
end)

-- Developer Tools -----------------------------------------------------------
local ToolRegistry = {
    {
        name = "DEX++",
        description = "Modern instance explorer and property inspector.",
        url = "https://github.com/AZYsGithub/DexPlusPlus/releases/latest/download/out.lua",
    },
    {
        name = "Moon Dex",
        description = "Alternative instance explorer from the IY tool set.",
        url = "https://raw.githubusercontent.com/infyiff/backup/main/dex.lua",
    },
    {
        name = "SimpleSpy",
        description = "RemoteEvent and RemoteFunction call logger.",
        url = "https://raw.githubusercontent.com/infyiff/backup/main/SimpleSpyV3/main.lua",
    },
    {
        name = "Audio Logger",
        description = "Inspect sounds and copy discovered audio identifiers.",
        url = "https://raw.githubusercontent.com/infyiff/backup/main/audiologger.lua",
    },
    {
        name = "Old Console",
        description = "Legacy output console loader.",
        url = "https://raw.githubusercontent.com/infyiff/backup/main/console.lua",
    },
    {
        name = "F3X",
        description = "Building and local workspace manipulation tools.",
        url = "https://raw.githubusercontent.com/infyiff/backup/refs/heads/main/f3x.lua",
    },
}

local function runRemoteTool(tool)
    if type(loadstring) ~= "function" then
        return notify("Unsupported", "This executor does not provide loadstring", 5)
    end
    notify(tool.name, "Loading tool…")
    local ok, source = pcall(function()
        return game:HttpGet(tool.url, true)
    end)
    if not ok or type(source) ~= "string" or source == "" then
        return notify(tool.name, "Could not download the tool", 5)
    end
    local compiled, compileError = loadstring(source)
    if type(compiled) ~= "function" then
        return notify(tool.name, "Compile failed: " .. tostring(compileError), 6)
    end
    local success, runtimeError = pcall(compiled)
    if not success then
        return notify(tool.name, "Runtime failed: " .. tostring(runtimeError), 6)
    end
    notify(tool.name, "Launched")
end

local toolsIntro = createSection(DeveloperPage, "Developer Tools", "Script launchers and inspection tools. These do not duplicate Fly, Noclip, or other Utility controls.")
for _, tool in ipairs(ToolRegistry) do
    local card = new("Frame", {
        BackgroundColor3 = Theme.Surface2,
        Size = UDim2.new(1, 0, 0, 76),
        Parent = toolsIntro,
    })
    addCorner(card, 8)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 9),
        Size = UDim2.new(1, -112, 0, 20),
        Font = Enum.Font.GothamBold,
        Text = tool.name,
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 31),
        Size = UDim2.new(1, -112, 0, 34),
        Font = Enum.Font.Gotham,
        Text = tool.description,
        TextColor3 = Theme.Muted,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = card,
    })
    local launch = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Accent,
        Position = UDim2.new(1, -91, 0.5, -16),
        Size = UDim2.fromOffset(79, 32),
        Font = Enum.Font.GothamBold,
        Text = "Launch",
        TextColor3 = Color3.fromRGB(9, 21, 23),
        TextSize = 12,
        Parent = card,
    })
    addCorner(launch, 7)
    track(launch.MouseButton1Click:Connect(function()
        task.spawn(runRemoteTool, tool)
    end))
end

local remoteFinder = createSection(DeveloperPage, "Remote Finder", "Search RemoteEvent and RemoteFunction names and copy matching paths.")
createTextAction(remoteFinder, "Search", "damage, claim, reward...", "Find", function(query)
    query = string.lower(query or "")
    if query == "" then return notify("Remote Finder", "Enter a search term") end
    local matches = {}
    for _, object in ipairs(game:GetDescendants()) do
        if (object:IsA("RemoteEvent") or object:IsA("RemoteFunction")) and string.find(string.lower(object.Name), query, 1, true) then
            table.insert(matches, object:GetFullName())
        end
    end
    table.sort(matches)
    local output = table.concat(matches, "\n")
    print("[Slice Utility][Remote Finder]", query, #matches)
    for _, path in ipairs(matches) do print(path) end
    local clipboard = setclipboard or toclipboard or set_clipboard
    if clipboard and #matches > 0 then clipboard(output) end
    notify("Remote Finder", string.format("Found %d match(es)%s", #matches, clipboard and "; paths copied" or "; check console"), 5)
end)
createButton(remoteFinder, "List Every Remote", function()
    local matches = {}
    for _, object in ipairs(game:GetDescendants()) do
        if object:IsA("RemoteEvent") or object:IsA("RemoteFunction") then table.insert(matches, object:GetFullName()) end
    end
    table.sort(matches)
    for _, path in ipairs(matches) do print("[Slice Utility][Remote]", path) end
    notify("Remote Finder", string.format("Printed %d remotes", #matches))
end)

local instanceFinder = createSection(DeveloperPage, "Instance Finder", "Search loaded instance names across the game hierarchy.")
createTextAction(instanceFinder, "Search", "part, gui, module...", "Find", function(query)
    query = string.lower(query or "")
    if query == "" then return notify("Instance Finder", "Enter a search term") end
    local matches = {}
    for _, object in ipairs(game:GetDescendants()) do
        if string.find(string.lower(object.Name), query, 1, true) then
            table.insert(matches, string.format("[%s] %s", object.ClassName, object:GetFullName()))
            if #matches >= 300 then break end
        end
    end
    table.sort(matches)
    for _, path in ipairs(matches) do print("[Slice Utility][Instance]", path) end
    local clipboard = setclipboard or toclipboard or set_clipboard
    if clipboard and #matches > 0 then clipboard(table.concat(matches, "\n")) end
    notify("Instance Finder", string.format("Found %d match(es)%s", #matches, #matches >= 300 and " (limited)" or ""), 5)
end)


-- Area Finder ---------------------------------------------------------------
local AreaFinder = {
    active = false,
    dragging = false,
    start = nil,
    colorIndex = 1,
    colors = {
        Color3.fromRGB(255, 75, 75),
        Color3.fromRGB(46, 196, 182),
        Color3.fromRGB(255, 210, 70),
        Color3.fromRGB(105, 145, 255),
        Color3.fromRGB(220, 105, 255),
    },
    selected = {},
}

local SelectorOverlay = new("Frame", {
    Name = "AreaFinderOverlay",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    Visible = false,
    ZIndex = 500,
    Parent = ScreenGui,
})

local SelectorRect = new("Frame", {
    Name = "SelectionRectangle",
    BackgroundColor3 = AreaFinder.colors[1],
    BackgroundTransparency = 0.84,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 502,
    Parent = SelectorOverlay,
})
local SelectorStroke = new("UIStroke", {
    Color = AreaFinder.colors[1],
    Thickness = 2,
    Transparency = 0,
    Parent = SelectorRect,
})

local FinderHint = new("TextLabel", {
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.08,
    Position = UDim2.new(0.5, -210, 0, 22),
    Size = UDim2.fromOffset(420, 38),
    Font = Enum.Font.GothamBold,
    Text = "Drag a rectangle over the object/building • Esc to cancel",
    TextColor3 = Theme.Text,
    TextSize = 12,
    ZIndex = 503,
    Parent = SelectorOverlay,
})
addCorner(FinderHint, 9)
addStroke(FinderHint, 0.25)

local ResultPanel = new("Frame", {
    Name = "AreaFinderResults",
    BackgroundColor3 = Theme.Background,
    Position = UDim2.new(0.5, -240, 0.5, -180),
    Size = UDim2.fromOffset(480, 360),
    Visible = false,
    ZIndex = 510,
    Parent = ScreenGui,
})
addCorner(ResultPanel, 10)
addStroke(ResultPanel, 0.2)

new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(16, 12),
    Size = UDim2.new(1, -60, 0, 24),
    Font = Enum.Font.GothamBold,
    Text = "Area Finder Preview",
    TextColor3 = Theme.Text,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 511,
    Parent = ResultPanel,
})
local ResultClose = new("TextButton", {
    AutoButtonColor = false,
    BackgroundColor3 = Theme.Surface2,
    Position = UDim2.new(1, -42, 0, 10),
    Size = UDim2.fromOffset(30, 28),
    Font = Enum.Font.GothamBold,
    Text = "×",
    TextColor3 = Theme.Text,
    TextSize = 17,
    ZIndex = 511,
    Parent = ResultPanel,
})
addCorner(ResultClose, 7)

local ResultSummary = new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(16, 43),
    Size = UDim2.new(1, -32, 0, 35),
    Font = Enum.Font.Gotham,
    Text = "No selection yet.",
    TextColor3 = Theme.Muted,
    TextSize = 11,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    ZIndex = 511,
    Parent = ResultPanel,
})

local ResultList = new("ScrollingFrame", {
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(14, 82),
    Size = UDim2.new(1, -28, 1, -142),
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 5,
    ZIndex = 511,
    Parent = ResultPanel,
})
addCorner(ResultList, 8)
local ResultLayout = new("UIListLayout", {
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = ResultList,
})
new("UIPadding", {
    PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7),
    PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7),
    Parent = ResultList,
})

local SearchSelected = new("TextButton", {
    AutoButtonColor = false,
    BackgroundColor3 = Theme.Accent,
    Position = UDim2.new(0, 14, 1, -48),
    Size = UDim2.new(0.5, -20, 0, 34),
    Font = Enum.Font.GothamBold,
    Text = "Search Matching Items",
    TextColor3 = Color3.fromRGB(9, 21, 23),
    TextSize = 11,
    ZIndex = 511,
    Parent = ResultPanel,
})
addCorner(SearchSelected, 7)
local CopySelected = new("TextButton", {
    AutoButtonColor = false,
    BackgroundColor3 = Theme.Surface2,
    Position = UDim2.new(0.5, 6, 1, -48),
    Size = UDim2.new(0.5, -20, 0, 34),
    Font = Enum.Font.GothamBold,
    Text = "Copy Selected Paths",
    TextColor3 = Theme.Text,
    TextSize = 11,
    ZIndex = 511,
    Parent = ResultPanel,
})
addCorner(CopySelected, 7)

local function clearResultRows()
    for _, child in ipairs(ResultList:GetChildren()) do
        if child:IsA("TextLabel") then child:Destroy() end
    end
end

local function addResultRow(text)
    local row = new("TextLabel", {
        BackgroundColor3 = Theme.Surface2,
        Size = UDim2.new(1, 0, 0, 30),
        Font = Enum.Font.Code,
        Text = text,
        TextColor3 = Theme.Text,
        TextSize = 10,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 512,
        Parent = ResultList,
    })
    addCorner(row, 6)
    new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = row})
end

local function pointInside(point, minX, minY, maxX, maxY)
    return point.X >= minX and point.X <= maxX and point.Y >= minY and point.Y <= maxY
end

local function projectedBounds(part)
    local cf, size = part.CFrame, part.Size * 0.5
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local seen = false
    for sx = -1, 1, 2 do
        for sy = -1, 1, 2 do
            for sz = -1, 1, 2 do
                local worldPoint = cf:PointToWorldSpace(Vector3.new(size.X * sx, size.Y * sy, size.Z * sz))
                local viewport, visible = Camera:WorldToViewportPoint(worldPoint)
                if viewport.Z > 0 then
                    seen = true
                    minX, minY = math.min(minX, viewport.X), math.min(minY, viewport.Y)
                    maxX, maxY = math.max(maxX, viewport.X), math.max(maxY, viewport.Y)
                end
            end
        end
    end
    if not seen then return nil end
    return minX, minY, maxX, maxY
end

local function overlaps(aMinX, aMinY, aMaxX, aMaxY, bMinX, bMinY, bMaxX, bMaxY)
    return aMinX <= bMaxX and aMaxX >= bMinX and aMinY <= bMaxY and aMaxY >= bMinY
end

local function scanArea(minX, minY, maxX, maxY)
    local selected, seenModels = {}, {}
    local fitMinX, fitMinY, fitMaxX, fitMaxY = math.huge, math.huge, -math.huge, -math.huge
    local checked = 0
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("BasePart") then
            checked += 1
            if checked > 12000 then break end
            local pMinX, pMinY, pMaxX, pMaxY = projectedBounds(object)
            if pMinX and overlaps(minX, minY, maxX, maxY, pMinX, pMinY, pMaxX, pMaxY) then
                local candidate = object:FindFirstAncestorOfClass("Model") or object
                if not seenModels[candidate] then
                    seenModels[candidate] = true
                    table.insert(selected, candidate)
                    fitMinX, fitMinY = math.min(fitMinX, pMinX), math.min(fitMinY, pMinY)
                    fitMaxX, fitMaxY = math.max(fitMaxX, pMaxX), math.max(fitMaxY, pMaxY)
                    if #selected >= 120 then break end
                end
            end
        end
    end
    return selected, fitMinX, fitMinY, fitMaxX, fitMaxY
end

local function showAreaResults(selected)
    AreaFinder.selected = selected
    clearResultRows()
    for index, object in ipairs(selected) do
        if index > 80 then break end
        addResultRow(string.format("[%s] %s", object.ClassName, object:GetFullName()))
    end
    ResultSummary.Text = string.format("Detected %d candidate object/model(s). Preview is capped at 80 rows.", #selected)
    ResultPanel.Visible = true
end

local function cancelAreaFinder()
    AreaFinder.active = false
    AreaFinder.dragging = false
    SelectorRect.Visible = false
    SelectorOverlay.Visible = false
end

local function beginAreaFinder()
    AreaFinder.active = true
    AreaFinder.dragging = false
    SelectorRect.Visible = false
    SelectorOverlay.Visible = true
    ResultPanel.Visible = false
    State.visible = false
    tweenWindow(false)
end

track(ResultClose.MouseButton1Click:Connect(function() ResultPanel.Visible = false end))
track(CopySelected.MouseButton1Click:Connect(function()
    local paths = {}
    for _, object in ipairs(AreaFinder.selected) do table.insert(paths, object:GetFullName()) end
    local clipboard = setclipboard or toclipboard or set_clipboard
    if clipboard and #paths > 0 then clipboard(table.concat(paths, "\n")) end
    notify("Area Finder", #paths > 0 and "Selected paths copied" or "Nothing selected")
end))
track(SearchSelected.MouseButton1Click:Connect(function()
    if #AreaFinder.selected == 0 then return notify("Area Finder", "Nothing selected") end
    local wanted = {}
    for _, object in ipairs(AreaFinder.selected) do wanted[string.lower(object.Name)] = true end
    local found = {}
    for _, root in ipairs({workspace, game:GetService("ReplicatedStorage"), LocalPlayer:FindFirstChildOfClass("PlayerGui")}) do
        if root then
            for _, object in ipairs(root:GetDescendants()) do
                if wanted[string.lower(object.Name)] then
                    table.insert(found, string.format("[%s] %s", object.ClassName, object:GetFullName()))
                    if #found >= 500 then break end
                end
            end
        end
        if #found >= 500 then break end
    end
    table.sort(found)
    for _, path in ipairs(found) do print("[Slice Utility][Area Match]", path) end
    local clipboard = setclipboard or toclipboard or set_clipboard
    if clipboard and #found > 0 then clipboard(table.concat(found, "\n")) end
    notify("Area Finder", string.format("Found %d name match(es)%s", #found, clipboard and "; copied" or "; check console"), 5)
end))

track(UserInputService.InputBegan:Connect(function(input, processed)
    if not AreaFinder.active then return end
    if input.KeyCode == Enum.KeyCode.Escape then
        cancelAreaFinder()
        State.visible = true
        tweenWindow(true)
        return
    end
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        AreaFinder.dragging = true
        AreaFinder.start = UserInputService:GetMouseLocation()
        SelectorRect.Position = UDim2.fromOffset(AreaFinder.start.X, AreaFinder.start.Y)
        SelectorRect.Size = UDim2.fromOffset(1, 1)
        SelectorRect.Visible = true
    end
end))

track(UserInputService.InputChanged:Connect(function(input)
    if not AreaFinder.active or not AreaFinder.dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local current = UserInputService:GetMouseLocation()
    local start = AreaFinder.start
    local minX, minY = math.min(start.X, current.X), math.min(start.Y, current.Y)
    local maxX, maxY = math.max(start.X, current.X), math.max(start.Y, current.Y)
    SelectorRect.Position = UDim2.fromOffset(minX, minY)
    SelectorRect.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
end))

track(UserInputService.InputEnded:Connect(function(input)
    if not AreaFinder.active or not AreaFinder.dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    AreaFinder.dragging = false
    local current = UserInputService:GetMouseLocation()
    local start = AreaFinder.start
    local minX, minY = math.min(start.X, current.X), math.min(start.Y, current.Y)
    local maxX, maxY = math.max(start.X, current.X), math.max(start.Y, current.Y)
    if maxX - minX < 12 or maxY - minY < 12 then return cancelAreaFinder() end
    local selected, fitMinX, fitMinY, fitMaxX, fitMaxY = scanArea(minX, minY, maxX, maxY)
    if #selected > 0 and fitMinX < math.huge then
        SelectorRect.Position = UDim2.fromOffset(math.max(0, fitMinX), math.max(0, fitMinY))
        SelectorRect.Size = UDim2.fromOffset(math.max(2, fitMaxX - fitMinX), math.max(2, fitMaxY - fitMinY))
        task.wait(0.18)
    end
    cancelAreaFinder()
    showAreaResults(selected)
end))

local areaFinderSection = createSection(DeveloperPage, "Area Finder", "Drag a screen rectangle over a building or object, preview detected Workspace candidates, then search matching names across loaded containers.")
createButton(areaFinderSection, "Drag Select Area", beginAreaFinder)
createButton(areaFinderSection, "Change Rectangle Color", function()
    AreaFinder.colorIndex = (AreaFinder.colorIndex % #AreaFinder.colors) + 1
    local color = AreaFinder.colors[AreaFinder.colorIndex]
    SelectorRect.BackgroundColor3 = color
    SelectorStroke.Color = color
    notify("Area Finder", "Rectangle color changed")
end)


-- Expanded Live Inspection Tools --------------------------------------------
local CollectionService = Services.CollectionService
local SelectionHighlights = {}
local MeasureState = {active = false, points = {}, connection = nil}

local function clipboardWrite(value)
    local clipboard = setclipboard or toclipboard or set_clipboard
    if clipboard then
        local ok = pcall(clipboard, tostring(value))
        return ok
    end
    return false
end

local function clearSelectionHighlights()
    for _, highlight in ipairs(SelectionHighlights) do
        pcall(function() highlight:Destroy() end)
    end
    table.clear(SelectionHighlights)
end

local function highlightInstance(instance, color)
    if not instance or not instance.Parent then return end
    local target = instance
    if not (target:IsA("Model") or target:IsA("BasePart")) then
        target = target:FindFirstAncestorOfClass("Model") or target:FindFirstAncestorWhichIsA("BasePart")
    end
    if not target then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "SliceUtilityHighlight"
    highlight.Adornee = target
    highlight.FillColor = color or Theme.Accent
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.72
    highlight.OutlineTransparency = 0.05
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = ScreenGui
    table.insert(SelectionHighlights, highlight)
end

local function printAndCopy(title, lines)
    table.sort(lines)
    print(string.format("[Slice Utility][%s] %d result(s)", title, #lines))
    for _, line in ipairs(lines) do print(line) end
    local copied = #lines > 0 and clipboardWrite(table.concat(lines, "\n"))
    notify(title, string.format("%d result(s)%s", #lines, copied and "; copied" or "; check console"), 5)
end

local guiExplorer = createSection(DeveloperPage, "GUI Explorer", "Search PlayerGui, CoreGui, BillboardGui, SurfaceGui, and other loaded GUI objects.")
createTextAction(guiExplorer, "Search GUI", "shop, inventory, quest...", "Find", function(query)
    query = string.lower(query or "")
    if query == "" then return notify("GUI Explorer", "Enter a search term") end
    local results = {}
    local roots = {LocalPlayer:FindFirstChildOfClass("PlayerGui"), CoreGui}
    for _, root in ipairs(roots) do
        if root then
            for _, object in ipairs(root:GetDescendants()) do
                if object:IsA("GuiObject") or object:IsA("LayerCollector") then
                    if string.find(string.lower(object.Name), query, 1, true) then
                        table.insert(results, string.format("[%s] %s", object.ClassName, object:GetFullName()))
                        if #results >= 350 then break end
                    end
                end
            end
        end
    end
    printAndCopy("GUI Explorer", results)
end)
createButton(guiExplorer, "List Visible Screen GUIs", function()
    local results = {}
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, object in ipairs(playerGui:GetDescendants()) do
            if object:IsA("ScreenGui") and object.Enabled then
                table.insert(results, string.format("[ScreenGui] %s", object:GetFullName()))
            end
        end
    end
    printAndCopy("Visible GUIs", results)
end)

local soundExplorer = createSection(DeveloperPage, "Sound Explorer", "Inspect loaded sounds, playing state, volume, looping, and SoundId.")
createTextAction(soundExplorer, "Search Sound", "music, click, ambient...", "Find", function(query)
    query = string.lower(query or "")
    if query == "" then return notify("Sound Explorer", "Enter a search term") end
    local results = {}
    for _, object in ipairs(game:GetDescendants()) do
        if object:IsA("Sound") and string.find(string.lower(object.Name), query, 1, true) then
            table.insert(results, string.format("[%s | playing=%s | volume=%.2f | looped=%s] %s | %s", object.Name, tostring(object.IsPlaying), object.Volume, tostring(object.Looped), object.SoundId, object:GetFullName()))
            if #results >= 300 then break end
        end
    end
    printAndCopy("Sound Explorer", results)
end)
createButton(soundExplorer, "List Playing Sounds", function()
    local results = {}
    for _, object in ipairs(game:GetDescendants()) do
        if object:IsA("Sound") and object.IsPlaying then
            table.insert(results, string.format("[%s | %.2f] %s | %s", object.Name, object.Volume, object.SoundId, object:GetFullName()))
        end
    end
    printAndCopy("Playing Sounds", results)
end)
createButton(soundExplorer, "Stop All Playing Sounds", function()
    local count = 0
    for _, object in ipairs(game:GetDescendants()) do
        if object:IsA("Sound") and object.IsPlaying then
            pcall(function() object:Stop() end)
            count += 1
        end
    end
    notify("Sound Explorer", string.format("Stopped %d sound(s)", count))
end)

local animationExplorer = createSection(DeveloperPage, "Animation Viewer", "List currently playing animation tracks from Humanoids and AnimationControllers.")
createButton(animationExplorer, "List Playing Animations", function()
    local results = {}
    for _, object in ipairs(workspace:GetDescendants()) do
        local animator
        if object:IsA("Humanoid") or object:IsA("AnimationController") then
            animator = object:FindFirstChildOfClass("Animator")
        end
        if animator then
            local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
            if ok then
                for _, track in ipairs(tracks) do
                    local animation = track.Animation
                    table.insert(results, string.format("[%s | speed=%.2f | time=%.2f] %s | owner=%s", track.Name, track.Speed, track.TimePosition, animation and animation.AnimationId or "unknown", object:GetFullName()))
                end
            end
        end
    end
    printAndCopy("Animation Viewer", results)
end)
createButton(animationExplorer, "Stop Local Character Animations", function()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    local count = 0
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            pcall(function() track:Stop(0.15) end)
            count += 1
        end
    end
    notify("Animation Viewer", string.format("Stopped %d local track(s)", count))
end)

local tagViewer = createSection(DeveloperPage, "Collection Tags", "List CollectionService tags and highlight every loaded object using a selected tag.")
createButton(tagViewer, "List Every Tag", function()
    local results = {}
    for _, tag in ipairs(CollectionService:GetAllTags()) do
        local count = #CollectionService:GetTagged(tag)
        table.insert(results, string.format("%s (%d)", tag, count))
    end
    printAndCopy("Collection Tags", results)
end)
createTextAction(tagViewer, "Highlight Tag", "enemy, chest, interactable...", "Highlight", function(query)
    clearSelectionHighlights()
    query = string.lower(query or "")
    if query == "" then return notify("Collection Tags", "Enter a tag name") end
    local selectedTag
    for _, tag in ipairs(CollectionService:GetAllTags()) do
        if string.lower(tag) == query or string.find(string.lower(tag), query, 1, true) then selectedTag = tag break end
    end
    if not selectedTag then return notify("Collection Tags", "No matching tag found") end
    local objects = CollectionService:GetTagged(selectedTag)
    for index, object in ipairs(objects) do
        if index > 250 then break end
        highlightInstance(object)
    end
    notify("Collection Tags", string.format("Highlighted %d object(s) tagged %s", math.min(#objects, 250), selectedTag), 5)
end)

local interactionExplorer = createSection(DeveloperPage, "Interaction Explorer", "Find ProximityPrompts, ClickDetectors, and TouchTransmitters without opening Dex.")
createTextAction(interactionExplorer, "Search Interaction", "open, talk, chest...", "Find", function(query)
    query = string.lower(query or "")
    if query == "" then return notify("Interaction Explorer", "Enter a search term") end
    local results = {}
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") or object:IsA("TouchTransmitter") then
            local label = object.Name
            if object:IsA("ProximityPrompt") then label ..= " " .. object.ActionText .. " " .. object.ObjectText end
            if string.find(string.lower(label), query, 1, true) then
                table.insert(results, string.format("[%s] %s", object.ClassName, object:GetFullName()))
                if #results >= 300 then break end
            end
        end
    end
    printAndCopy("Interaction Explorer", results)
end)
createButton(interactionExplorer, "List Every Interaction", function()
    local results = {}
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") or object:IsA("TouchTransmitter") then
            table.insert(results, string.format("[%s] %s", object.ClassName, object:GetFullName()))
        end
    end
    printAndCopy("Interactions", results)
end)

local spawnExplorer = createSection(DeveloperPage, "Spawn Explorer", "Locate SpawnLocations and likely checkpoint/spawn objects by class or name.")
createButton(spawnExplorer, "List Spawn & Checkpoint Objects", function()
    local results = {}
    for _, object in ipairs(workspace:GetDescendants()) do
        local lower = string.lower(object.Name)
        if object:IsA("SpawnLocation") or string.find(lower, "spawn", 1, true) or string.find(lower, "checkpoint", 1, true) then
            table.insert(results, string.format("[%s] %s", object.ClassName, object:GetFullName()))
            if #results >= 400 then break end
        end
    end
    printAndCopy("Spawn Explorer", results)
end)

local statistics = createSection(DeveloperPage, "Model & Map Statistics", "Inspect model composition or generate a high-level Workspace report.")
createTextAction(statistics, "Model Name", "gate, house, tree...", "Analyze", function(query)
    query = string.lower(query or "")
    if query == "" then return notify("Model Statistics", "Enter a model name") end
    local model
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("Model") and string.find(string.lower(object.Name), query, 1, true) then model = object break end
    end
    if not model then return notify("Model Statistics", "No matching model found") end
    local counts = {Parts=0, MeshParts=0, Scripts=0, Sounds=0, Decals=0, Attachments=0, Constraints=0}
    local mass = 0
    for _, object in ipairs(model:GetDescendants()) do
        if object:IsA("BasePart") then counts.Parts += 1 mass += object.AssemblyMass end
        if object:IsA("MeshPart") then counts.MeshParts += 1 end
        if object:IsA("LuaSourceContainer") then counts.Scripts += 1 end
        if object:IsA("Sound") then counts.Sounds += 1 end
        if object:IsA("Decal") or object:IsA("Texture") then counts.Decals += 1 end
        if object:IsA("Attachment") then counts.Attachments += 1 end
        if object:IsA("Constraint") then counts.Constraints += 1 end
    end
    local size = model:GetExtentsSize()
    local lines = {
        "Name: " .. model.Name,
        "Path: " .. model:GetFullName(),
        string.format("Parts: %d", counts.Parts),
        string.format("MeshParts: %d", counts.MeshParts),
        string.format("Scripts: %d", counts.Scripts),
        string.format("Sounds: %d", counts.Sounds),
        string.format("Decals/Textures: %d", counts.Decals),
        string.format("Attachments: %d", counts.Attachments),
        string.format("Constraints: %d", counts.Constraints),
        string.format("Bounding Size: %.1f, %.1f, %.1f", size.X, size.Y, size.Z),
        string.format("Approx Mass: %.1f", mass),
        "PrimaryPart: " .. (model.PrimaryPart and model.PrimaryPart.Name or "None"),
    }
    for _, line in ipairs(lines) do print("[Slice Utility][Model Statistics]", line) end
    clipboardWrite(table.concat(lines, "\n"))
    clearSelectionHighlights()
    highlightInstance(model)
    notify("Model Statistics", string.format("%s: %d parts, %d meshes; report copied", model.Name, counts.Parts, counts.MeshParts), 6)
end)
createButton(statistics, "Generate Workspace Statistics", function()
    local counts = {Models=0, Parts=0, MeshParts=0, Scripts=0, NPCs=0, Animations=0, Sounds=0, Remotes=0, Prompts=0, ClickDetectors=0}
    for _, object in ipairs(game:GetDescendants()) do
        if object:IsA("Model") and object:IsDescendantOf(workspace) then counts.Models += 1 end
        if object:IsA("BasePart") and object:IsDescendantOf(workspace) then counts.Parts += 1 end
        if object:IsA("MeshPart") and object:IsDescendantOf(workspace) then counts.MeshParts += 1 end
        if object:IsA("LuaSourceContainer") then counts.Scripts += 1 end
        if object:IsA("Humanoid") and object.Parent ~= LocalPlayer.Character then counts.NPCs += 1 end
        if object:IsA("Animation") then counts.Animations += 1 end
        if object:IsA("Sound") then counts.Sounds += 1 end
        if object:IsA("RemoteEvent") or object:IsA("RemoteFunction") then counts.Remotes += 1 end
        if object:IsA("ProximityPrompt") then counts.Prompts += 1 end
        if object:IsA("ClickDetector") then counts.ClickDetectors += 1 end
    end
    local lines = {}
    for name, count in pairs(counts) do table.insert(lines, string.format("%s: %d", name, count)) end
    printAndCopy("Workspace Statistics", lines)
end)

local visualSearch = createSection(DeveloperPage, "Highlight & Material Search", "Highlight matching names or every visible part using a selected material.")
createTextAction(visualSearch, "Highlight Name", "quest, door, merchant...", "Highlight", function(query)
    clearSelectionHighlights()
    query = string.lower(query or "")
    if query == "" then return notify("Highlight Search", "Enter a search term") end
    local count = 0
    for _, object in ipairs(workspace:GetDescendants()) do
        if (object:IsA("Model") or object:IsA("BasePart")) and string.find(string.lower(object.Name), query, 1, true) then
            highlightInstance(object)
            count += 1
            if count >= 250 then break end
        end
    end
    notify("Highlight Search", string.format("Highlighted %d result(s)", count))
end)
createTextAction(visualSearch, "Material", "Neon, Glass, Wood...", "Highlight", function(query)
    clearSelectionHighlights()
    query = string.lower(query or "")
    if query == "" then return notify("Material Finder", "Enter a material") end
    local count = 0
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("BasePart") and string.find(string.lower(object.Material.Name), query, 1, true) then
            highlightInstance(object)
            count += 1
            if count >= 300 then break end
        end
    end
    notify("Material Finder", string.format("Highlighted %d part(s)", count))
end)
createButton(visualSearch, "Clear Highlights", clearSelectionHighlights)

local partInspector = createSection(DeveloperPage, "Part Inspector", "Search one BasePart and copy its physical, visual, and movement properties.")
createTextAction(partInspector, "Part Name", "door, floor, hitbox...", "Inspect", function(query)
    query = string.lower(query or "")
    if query == "" then return notify("Part Inspector", "Enter a part name") end
    local part
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("BasePart") and string.find(string.lower(object.Name), query, 1, true) then part = object break end
    end
    if not part then return notify("Part Inspector", "No matching part found") end
    local lines = {
        "Name: " .. part.Name,
        "Class: " .. part.ClassName,
        "Path: " .. part:GetFullName(),
        "Material: " .. part.Material.Name,
        string.format("Color: %.0f, %.0f, %.0f", part.Color.R*255, part.Color.G*255, part.Color.B*255),
        string.format("Transparency: %.3f", part.Transparency),
        "CanCollide: " .. tostring(part.CanCollide),
        "Anchored: " .. tostring(part.Anchored),
        string.format("Size: %.3f, %.3f, %.3f", part.Size.X, part.Size.Y, part.Size.Z),
        string.format("Position: %.3f, %.3f, %.3f", part.Position.X, part.Position.Y, part.Position.Z),
        string.format("AssemblyMass: %.3f", part.AssemblyMass),
        string.format("Velocity: %.3f, %.3f, %.3f", part.AssemblyLinearVelocity.X, part.AssemblyLinearVelocity.Y, part.AssemblyLinearVelocity.Z),
    }
    for _, line in ipairs(lines) do print("[Slice Utility][Part Inspector]", line) end
    clipboardWrite(table.concat(lines, "\n"))
    clearSelectionHighlights()
    highlightInstance(part)
    notify("Part Inspector", part.Name .. " report copied", 5)
end)

local measureTool = createSection(DeveloperPage, "Measure Tool", "Click two world points to measure 3D distance, horizontal distance, and height difference.")
local function stopMeasure()
    MeasureState.active = false
    table.clear(MeasureState.points)
    if MeasureState.connection then safeDisconnect(MeasureState.connection) MeasureState.connection = nil end
end
createButton(measureTool, "Start Two-Point Measurement", function()
    stopMeasure()
    MeasureState.active = true
    State.visible = false
    tweenWindow(false)
    notify("Measure Tool", "Click point A, then point B. Press Escape to cancel.", 5)
    local mouse = LocalPlayer:GetMouse()
    MeasureState.connection = mouse.Button1Down:Connect(function()
        if not MeasureState.active or not mouse.Hit then return end
        table.insert(MeasureState.points, mouse.Hit.Position)
        if #MeasureState.points == 1 then
            notify("Measure Tool", "Point A saved. Click point B.")
        elseif #MeasureState.points >= 2 then
            local a, b = MeasureState.points[1], MeasureState.points[2]
            local distance = (b-a).Magnitude
            local horizontal = Vector3.new(b.X-a.X, 0, b.Z-a.Z).Magnitude
            local height = b.Y-a.Y
            local output = string.format("Distance: %.3f studs\nHorizontal: %.3f studs\nHeight difference: %.3f studs\nA: %s\nB: %s", distance, horizontal, height, tostring(a), tostring(b))
            clipboardWrite(output)
            print("[Slice Utility][Measure Tool]\n" .. output)
            notify("Measure Tool", string.format("%.2f studs; details copied", distance), 6)
            stopMeasure()
            State.visible = true
            tweenWindow(true)
        end
    end)
end)
createButton(measureTool, "Cancel Measurement", function()
    stopMeasure()
    notify("Measure Tool", "Cancelled")
end)

local inspection = createSection(DeveloperPage, "Inspection Helpers", "Fast built-in helpers that do not launch another script.")
createButton(inspection, "List Loaded Modules", function()
    local count = 0
    for _, object in ipairs(game:GetDescendants()) do
        if object:IsA("ModuleScript") then count += 1 print("[Slice Utility][Module]", object:GetFullName()) end
    end
    notify("Modules", string.format("Printed %d ModuleScript paths", count))
end)
createButton(inspection, "Executor Capability Check", function()
    local checks = {
        loadstring = type(loadstring) == "function",
        getgc = type(getgc) == "function",
        hookmetamethod = type(hookmetamethod) == "function",
        getconnections = type(getconnections) == "function",
        writefile = type(writefile) == "function",
        gethui = type(gethui) == "function",
    }
    local supported = 0
    for name, ok in pairs(checks) do print(string.format("[Slice Utility][Capability] %s = %s", name, tostring(ok))) if ok then supported += 1 end end
    notify("Capabilities", string.format("%d/6 common capabilities available", supported), 5)
end)

-- Settings -----------------------------------------------------------------
local interface = createSection(SettingsPage, "Interface", "Use the draggable SU button to open or close Slice Utility from anywhere on the screen.")
createButton(interface, "Hide Interface", function()
    State.visible = false
    tweenWindow(false)
end)
createButton(interface, "Reset Launcher Position", function()
    Launcher.AnchorPoint = Vector2.new(1, 1)
    TweenService:Create(Launcher, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = UDim2.new(1, -18, 1, -18),
    }):Play()
end)
createToggle(interface, "Show Launcher Button", true, function(enabled)
    State.launcherVisible = enabled
    Launcher.Visible = enabled == true
    Launcher.Active = enabled == true
    Launcher.Selectable = enabled == true
    if not enabled then
        Launcher.Position = Launcher.Position
    end
end)
createButton(interface, "Reset Window Size", function()
    State.windowWidth = 760
    State.windowHeight = 500
    TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = UDim2.fromOffset(State.windowWidth, State.windowHeight),
    }):Play()
    saveWindowSize()
    notify("Interface", "Window size reset to default")
end)

local keybindSection = createSection(SettingsPage, "Keybinds", "Change the key used to show or hide Slice Utility. The default UI key is RightShift.")
local function bindInput(label, actionName)
    createTextAction(keybindSection, label, State.keybinds[actionName], "Save", function(value, box)
        value = (value or ""):gsub("%s+", "")
        if not Enum.KeyCode[value] then notify("Keybind", "Unknown key: " .. value, 4) return end
        State.keybinds[actionName] = value
        box.PlaceholderText = value
        if actionName == "ToggleUI" then
            HeaderSubtitle.Text = "Drag SU • " .. value .. " to hide"
        end
        saveWindowSize()
        notify("Keybind", label .. " set to " .. value, 2)
    end)
end
bindInput("UI Toggle Key", "ToggleUI")
createButton(keybindSection, "Reset UI Key to RightShift", function()
    State.keybinds.ToggleUI = "RightShift"
    saveWindowSize()
    HeaderSubtitle.Text = "Drag SU • RightShift to hide"
    notify("Keybind", "UI toggle key reset to RightShift", 2)
end)
bindInput("Fly", "Fly")
bindInput("Noclip", "Noclip")
bindInput("Player ESP", "ESP")

local cleanup = createSection(SettingsPage, "Cleanup", "Restore modified state and remove Slice Utility.")
createButton(cleanup, "Panic Reset", function()
    pcall(stopFly)
    pcall(function() setNoclip(false) end)
    pcall(function() setESP(false) end)
    pcall(function() setFullbright(false) end)
    State.infiniteJump = false
    State.clickTeleport = false
    State.sprint = false
    State.xray = false
    State.npcEsp = false
    workspace.Gravity = 196.2
    if Camera then Camera.FieldOfView = 70 end
    local humanoid = getHumanoid()
    if humanoid then humanoid.WalkSpeed = 16 humanoid.UseJumpPower = true humanoid.JumpPower = 50 end
    for object, value in pairs(State.originalTransparency) do if object and object.Parent then pcall(function() object.LocalTransparencyModifier = value end) end end
    State.originalTransparency = {}
    notify("Panic Reset", "Active movement, visual, and world changes were disabled", 4)
end, true)
local function unload()
    if State.destroyed then return end
    pcall(cancelAreaFinder)
    pcall(clearSelectionHighlights)
    pcall(stopMeasure)
    State.destroyed = true
    stopFly()
    setNoclip(false)
    setESP(false)
    setFullbright(false)
    State.xray = false
    for object, value in pairs(State.originalTransparency) do
        if object and object.Parent then pcall(function() object.LocalTransparencyModifier = value end) end
    end
    State.originalTransparency = {}
    for object, value in pairs(State.originalWorld) do
        if typeof(object) == "Instance" and object.Parent then
            pcall(function()
                if object:IsA("Texture") or object:IsA("Decal") then object.Transparency = value
                elseif object:IsA("BasePart") and typeof(value) == "EnumItem" then object.Material = value object.CastShadow = true end
            end)
        end
    end
    if State.originalWorld.FogStart ~= nil then Lighting.FogStart = State.originalWorld.FogStart end
    if State.originalWorld.FogEnd ~= nil then Lighting.FogEnd = State.originalWorld.FogEnd end
    if State.originalWorld.CameraMaxZoomDistance ~= nil then LocalPlayer.CameraMaxZoomDistance = State.originalWorld.CameraMaxZoomDistance end
    workspace.Gravity = 196.2
    if Camera then Camera.FieldOfView = 70 end
    for _, connection in ipairs(State.connections) do safeDisconnect(connection) end
    State.connections = {}
    if getgenv then getgenv().SliceUtilityLoaded = nil end
    ScreenGui:Destroy()
end
createButton(cleanup, "Unload Slice Utility", unload, true)

-- Input and persistent loops ------------------------------------------------
track(UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local keyName = input.KeyCode.Name
    if keyName == State.keybinds.ToggleUI then
        State.visible = not State.visible
        tweenWindow(State.visible)
        return
    elseif keyName == State.keybinds.Fly then
        runAction("Fly")
    elseif keyName == State.keybinds.Noclip then
        runAction("Noclip")
    elseif keyName == State.keybinds.ESP then
        runAction("Player ESP")
    end
    if input.KeyCode == Enum.KeyCode.Escape and MeasureState.active then
        stopMeasure()
        State.visible = true
        tweenWindow(true)
        notify("Measure Tool", "Cancelled")
        return
    end
    if flyKeys[input.KeyCode.Name] ~= nil then
        flyKeys[input.KeyCode.Name] = true
    end
    if State.infiniteJump and input.KeyCode == Enum.KeyCode.Space then
        local humanoid = getHumanoid()
        if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
    if State.sprint and input.KeyCode == Enum.KeyCode.LeftShift then
        local humanoid = getHumanoid()
        if humanoid then humanoid.WalkSpeed = State.sprintSpeed end
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if flyKeys[input.KeyCode.Name] ~= nil then
        flyKeys[input.KeyCode.Name] = false
    end
    if State.sprint and input.KeyCode == Enum.KeyCode.LeftShift then
        local humanoid = getHumanoid()
        if humanoid then humanoid.WalkSpeed = State.walkSpeed end
    end
end))

track(LocalPlayer.Idled:Connect(function()
    if not State.antiAfk then return end
    local VirtualUser = Services.VirtualUser
    pcall(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), Camera.CFrame)
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0, 0), Camera.CFrame)
    end)
end))

local mouse = LocalPlayer:GetMouse()
track(mouse.Button1Down:Connect(function()
    if not State.clickTeleport or not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then return end
    local root = getRoot()
    if root and mouse.Hit then
        root.CFrame = mouse.Hit + Vector3.new(0, 3, 0)
    end
end))

track(RunService.Stepped:Connect(function()
    if State.noclip then
        local character = LocalPlayer.Character
        if character then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    if State.originalCollisions[part] == nil then
                        State.originalCollisions[part] = part.CanCollide
                    end
                    part.CanCollide = false
                end
            end
        end
    end
end))

track(Players.PlayerAdded:Connect(function(player)
    if State.esp then
        local function attach(character)
            local highlight = new("Highlight", {
                Name = "SliceESP",
                Adornee = character,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                FillColor = Theme.Accent,
                FillTransparency = 0.65,
                OutlineColor = Color3.new(1, 1, 1),
                Parent = ScreenGui,
            })
            State.espObjects[player] = highlight
        end
        track(player.CharacterAdded:Connect(attach))
        if player.Character then attach(player.Character) end
    end
end))

track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    local humanoid = getHumanoid()
    if humanoid then
        humanoid.WalkSpeed = State.walkSpeed
        humanoid.UseJumpPower = true
        humanoid.JumpPower = State.jumpPower
    end
    if State.fly then startFly() end
end))

-- Draggable launcher --------------------------------------------------------
do
    local dragging = false
    local moved = false
    local dragStart
    local startPosition
    local dragInput

    track(Launcher.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = input.Position
            startPosition = Launcher.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end))

    track(Launcher.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then moved = true end
            Launcher.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end))

    track(Launcher.MouseButton1Click:Connect(function()
        if moved then
            moved = false
            return
        end
        State.visible = not State.visible
        tweenWindow(State.visible)
        TweenService:Create(Launcher, TweenInfo.new(0.12), {Size = UDim2.fromOffset(44, 44)}):Play()
        task.delay(0.12, function()
            if Launcher.Parent then
                TweenService:Create(Launcher, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(48, 48)}):Play()
            end
        end)
    end))
end


-- Resizable main window -----------------------------------------------------
do
    local resizing = false
    local resizeInput
    local dragStart
    local startSize

    local function resizeTo(inputPosition)
        if not resizing then return end
        local delta = inputPosition - dragStart
        local viewportSize = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
        local maxWidth = math.max(620, viewportSize.X - 30)
        local maxHeight = math.max(420, viewportSize.Y - 30)
        local width = math.clamp(startSize.X + delta.X, 620, maxWidth)
        local height = math.clamp(startSize.Y + delta.Y, 420, maxHeight)
        State.windowWidth = width
        State.windowHeight = height
        Main.Size = UDim2.fromOffset(width, height)
    end

    track(ResizeGrip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing = true
            resizeInput = input
            dragStart = input.Position
            startSize = Vector2.new(Main.AbsoluteSize.X, Main.AbsoluteSize.Y)
            TweenService:Create(ResizeGrip, TweenInfo.new(0.1), {BackgroundTransparency = 0}):Play()
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    resizing = false
                    saveWindowSize()
                    if ResizeGrip.Parent then
                        TweenService:Create(ResizeGrip, TweenInfo.new(0.15), {BackgroundTransparency = 0.15}):Play()
                    end
                end
            end)
        end
    end))

    track(ResizeGrip.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            resizeInput = input
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if resizing and (input == resizeInput or input.UserInputType == Enum.UserInputType.Touch) then
            resizeTo(input.Position)
        end
    end))
end

-- Main window dragging ------------------------------------------------------
do
    local dragging = false
    local dragStart
    local startPosition
    local dragInput

    track(Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    State.windowPositionX = Main.AbsolutePosition.X
                    State.windowPositionY = Main.AbsolutePosition.Y
                    saveWindowSize()
                end
            end)
        end
    end))

    track(Header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end))
end

track(CloseButton.MouseButton1Click:Connect(function()
    State.visible = false
    tweenWindow(false)
    notify("Slice Utility", "Hidden. Click the SU button or press " .. tostring(State.keybinds.ToggleUI or "RightShift") .. " to reopen.")
end))

if State.windowPositionX and State.windowPositionY then
    Main.AnchorPoint = Vector2.new(0, 0)
    Main.Position = UDim2.fromOffset(State.windowPositionX, State.windowPositionY)
end
refreshFavorites()
showPage("Quick Actions")
Main.Visible = true
Scale.Scale = BaseScale * 0.9
TweenService:Create(Scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = BaseScale}):Play()
notify("Slice Utility", "Polished build loaded. Search, star, bind, resize, and drag freely.", 5)
