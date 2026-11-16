--[[
    PLATE SNIPER v9   |   By tg Torn_tuz_lua

    Вкладка «Покупка»: диапазон цены и скорость.
    Вкладка «Редкость»: выбор редкости + цена продажи и минимальная прибыль.
      - при выборе редкости скрипт сам открывает ТОРГИ, ставит «Дешёвые»
        и в списке «Редкость» выключает кружки всех лишних редкостей
      - лот покупается только если его редкость совпадает с выбранной
      - если задана цена продажи: чистыми = цена × 0.9 (комиссия -10%),
        максимум покупки = чистыми - мин. прибыль, поле «ДО» считается само

    Покупка: список -> «КУПИТЬ» -> окно лота («ПРОВЕРЯЮ...», «КУПИТЬ ЗА ...»,
    иногда два раза подряд) -> розыгрыш -> результат.
      «ПРОДАН» -> проверка кто купил, крестик окна лота, дальше
      «Ошибка» -> закрыть окно лота, пропустить лот, дальше

    Нажатия: select (выбор кнопки + Enter), запасной fire.
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local lp = Players.LocalPlayer
local pg = lp:WaitForChild("PlayerGui")

---------------------------------------------------------------- СОСТОЯНИЕ
local S = {
    min = 5000,
    max = 9000,
    interval = 0.15,
    enabled = false,
    won = 0,
    lost = 0,
    earn = 0,
    rarity = nil,   -- "rare" | "epic" | "mythic" | "legend" | nil
    sell = 0,       -- цена продажи (0 = не задана)
    profit = 0,     -- минимальная прибыль с номера
    licensed = false,
    keyExpire = nil,
}

local COMMISSION = 0.10
local function netOf(sell) return math.floor(sell * (1 - COMMISSION)) end

-- рабочие границы цены покупки
local function limits()
    local lo, hi = S.min, S.max
    if S.sell > 0 then hi = netOf(S.sell) - S.profit end
    return lo, hi
end

local setupMarket          -- определяется ниже
local setupBusy = false
local rarityTouched = false   -- уже меняли кружки редкости
local filterApplied = false   -- скрипт выставил фильтр редкости в игре
local detectOk = false        -- редкость карточек читается

---------------------------------------------------------------- РОДИТЕЛЬ GUI
local function getParent()
    if gethui then
        local ok, r = pcall(gethui)
        if ok and r then return r end
    end
    local ok = pcall(function() return game:GetService("CoreGui"):GetChildren() end)
    if ok then return game:GetService("CoreGui") end
    return pg
end

local host = getParent()
local old = host:FindFirstChild("PlateSniper")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "PlateSniper"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
gui.Parent = host

---------------------------------------------------------------- ТЕМА И ХЕЛПЕРЫ
local T = {
    bg = Color3.fromRGB(16, 20, 32),
    card = Color3.fromRGB(26, 32, 49),
    field = Color3.fromRGB(12, 15, 24),
    line = Color3.fromRGB(48, 58, 82),
    accent = Color3.fromRGB(255, 150, 50),
    gold = Color3.fromRGB(255, 205, 90),
    green = Color3.fromRGB(52, 199, 100),
    red = Color3.fromRGB(235, 84, 84),
    text = Color3.fromRGB(236, 239, 246),
    dim = Color3.fromRGB(128, 139, 163),
    idle = Color3.fromRGB(95, 105, 128),
    dark = Color3.fromRGB(20, 16, 10),
}

local RAR = {
    { key = "rare",   ru = "Редкий",      stems = { "РЕДК", "Редк" },     col = Color3.fromRGB(80, 150, 255) },
    { key = "epic",   ru = "Эпический",   stems = { "ЭПИЧ", "Эпич" },     col = Color3.fromRGB(176, 108, 255) },
    { key = "mythic", ru = "Мифический",  stems = { "МИФИЧ", "Мифич" },   col = Color3.fromRGB(235, 72, 72) },
    { key = "legend", ru = "Легендарный", stems = { "ЛЕГЕНД", "Легенд" }, col = Color3.fromRGB(255, 190, 50) },
}
local RAR_BY_KEY = {}
for _, r in ipairs(RAR) do RAR_BY_KEY[r.key] = r end

local function mk(cls, props, parent)
    local o = Instance.new(cls)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function corner(o, r) return mk("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function stroke(o, col, th) return mk("UIStroke", { Color = col, Thickness = th }, o) end

local function text(parent, props)
    local p = {
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = T.text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }
    for k, v in pairs(props) do p[k] = v end
    return mk("TextLabel", p, parent)
end

local function tw(obj, info, goal)
    local t = TweenService:Create(obj, info, goal)
    t:Play()
    return t
end

local FAST = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PAGE = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function fmt(n)
    local s = tostring(math.floor(n))
    local r = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (r:gsub("^ ", ""))
end

local function short(n)
    local a = math.abs(n)
    local s
    if a >= 1e6 then
        s = string.format("%.2fM", a / 1e6)
    elseif a >= 1e4 then
        s = string.format("%.1fk", a / 1e3)
    else
        s = tostring(math.floor(a))
    end
    return (n < 0 and "-" or "") .. s
end

local function digits(t)
    local d = (tostring(t):gsub("%D", ""))
    return tonumber(d)
end

---------------------------------------------------------------- ОКНО
local W, H = 210, 308
local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 400)

local main = mk("CanvasGroup", {
    Name = "Main",
    Size = UDim2.fromOffset(W, H),
    Position = UDim2.fromOffset(math.max(6, vp.X - W - 12), 40),
    BackgroundColor3 = T.bg,
    BorderSizePixel = 0,
    GroupTransparency = 1,
    Active = true,
}, gui)
corner(main, 12)
stroke(main, T.line, 1.5)
local mainScale = mk("UIScale", { Scale = 0.85 }, main)

local content = mk("Frame", { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, main)
mk("UIPadding", {
    PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
    PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
}, content)
mk("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, content)

-- шапка
local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, content)
local dot = mk("Frame", {
    Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 2, 0.5, -5),
    BackgroundColor3 = T.idle, BorderSizePixel = 0,
}, header)
corner(dot, 5)
text(header, {
    Text = "Plate Sniper", Font = Enum.Font.GothamBold, TextSize = 14,
    Position = UDim2.new(0, 20, 0, 0), Size = UDim2.new(1, -72, 1, 0),
})
local lblKey = text(header, {
    Text = "", TextSize = 10, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Right,
    Position = UDim2.new(0, 100, 0, 0), Size = UDim2.fromOffset(44, 22),
})

local function headBtn(txt, xoff)
    local b = mk("TextButton", {
        Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, xoff, 0.5, -11),
        BackgroundColor3 = T.card, Text = txt, Font = Enum.Font.GothamBold,
        TextSize = 14, TextColor3 = T.dim, AutoButtonColor = true,
    }, header)
    corner(b, 6)
    return b
end
local btnMin = headBtn("-", -48)
local btnClose = headBtn("x", -22)

-- переключатель вкладок
local tabs = mk("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 2 }, content)
local tabBtns = {}
for i, name in ipairs({ "Покупка", "Редкость", "Прохождение" }) do
    local b = mk("TextButton", {
        Position = UDim2.new(0, (i - 1) * 66, 0, 0), Size = UDim2.fromOffset(62, 22),
        BackgroundColor3 = T.card, Text = name, Font = Enum.Font.GothamBold, TextSize = 9,
        TextColor3 = T.dim, AutoButtonColor = false,
    }, tabs)
    corner(b, 7)
    tabBtns[i] = b
end

-- область страниц
local holder = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 132), BackgroundTransparency = 1, ClipsDescendants = true, LayoutOrder = 3,
}, content)

local function field(parent, x, capY, boxY, h, caption, default)
    local cap = text(parent, {
        Text = caption, TextSize = 10, TextColor3 = T.dim,
        Position = UDim2.new(0, x + 2, 0, capY), Size = UDim2.fromOffset(90, 12),
    })
    local box = mk("TextBox", {
        Position = UDim2.new(0, x, 0, boxY), Size = UDim2.fromOffset(87, h),
        BackgroundColor3 = T.field, Text = tostring(default), PlaceholderText = "0",
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = T.accent,
        ClearTextOnFocus = false,
    }, parent)
    corner(box, 6)
    local st = stroke(box, T.line, 1)
    box.Focused:Connect(function() tw(st, FAST, { Color = T.accent }) end)
    box.FocusLost:Connect(function() tw(st, FAST, { Color = T.line }) end)
    return box, cap
end

-- страница 1: покупка
local page1 = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.card, BorderSizePixel = 0 }, holder)
corner(page1, 8)
local boxMin = field(page1, 7, 8, 22, 28, "ОТ, ₽", S.min)
local boxMax, capMax = field(page1, 100, 8, 22, 28, "ДО, ₽", S.max)

text(page1, { Text = "Скорость", TextSize = 11, TextColor3 = T.dim, Position = UDim2.new(0, 9, 0, 60), Size = UDim2.fromOffset(54, 26) })
local SPEEDS = { { "Макс", 0.08 }, { "Норм", 0.15 }, { "Тихо", 0.35 } }
local speedBtns = {}
for i, sp in ipairs(SPEEDS) do
    local b = mk("TextButton", {
        Position = UDim2.new(0, 64 + (i - 1) * 43, 0, 60), Size = UDim2.fromOffset(40, 26),
        BackgroundColor3 = T.field, Text = sp[1], Font = Enum.Font.GothamBold,
        TextSize = 11, TextColor3 = T.dim, AutoButtonColor = false,
    }, page1)
    corner(b, 6)
    speedBtns[i] = b
end
local hint = text(page1, {
    Text = "Цена продажи задаётся на вкладке «Редкость». Тогда «ДО» считается само.",
    TextSize = 10, TextColor3 = T.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
    Position = UDim2.new(0, 9, 0, 94), Size = UDim2.new(1, -18, 0, 30),
})

-- страница 2: редкость и прибыль
local page2 = mk("Frame", { Size = UDim2.fromScale(1, 1), Position = UDim2.new(1, 6, 0, 0), BackgroundColor3 = T.card, BorderSizePixel = 0 }, holder)
corner(page2, 8)
text(page2, { Text = "РЕДКОСТЬ НОМЕРА", TextSize = 10, TextColor3 = T.dim, Position = UDim2.new(0, 9, 0, 4), Size = UDim2.fromOffset(150, 12) })

local chips = {}
local function refreshChips()
    for key, b in pairs(chips) do
        local r = RAR_BY_KEY[key]
        local on = S.rarity == key
        tw(b, FAST, { BackgroundColor3 = on and r.col or T.field, TextColor3 = on and T.dark or r.col })
    end
end
for i, r in ipairs(RAR) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local b = mk("TextButton", {
        Position = UDim2.new(0, 7 + col * 93, 0, 18 + row * 25), Size = UDim2.fromOffset(87, 22),
        BackgroundColor3 = T.field, Text = r.ru, Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = r.col, AutoButtonColor = false,
    }, page2)
    corner(b, 6)
    chips[r.key] = b
    b.MouseButton1Click:Connect(function()
        if S.rarity == r.key then S.rarity = nil else S.rarity = r.key end
        refreshChips()
        filterApplied = false
        if S.rarity or rarityTouched then
            task.spawn(function() if setupMarket then setupMarket() end end)
        end
    end)
end

local boxSell = field(page2, 7, 70, 80, 24, "ЦЕНА ПРОДАЖИ, ₽", "")
local boxProfit = field(page2, 100, 70, 80, 24, "МИН. ПРИБЫЛЬ, ₽", "")
boxSell.Text = ""
boxProfit.Text = ""
local infoNet = text(page2, { Text = "", TextSize = 9, TextColor3 = T.dim, Position = UDim2.new(0, 9, 0, 107), Size = UDim2.new(1, -18, 0, 11) })
local infoMax = text(page2, { Text = "", TextSize = 9, TextColor3 = T.gold, Font = Enum.Font.GothamBold, Position = UDim2.new(0, 9, 0, 118), Size = UDim2.new(1, -18, 0, 11) })

---------------------------------------------------------------- АВТО-МИНИ-ИГРЫ
-- Если авто-поиск не находит UI, впиши точные имена из Dex Explorer в AUTO_UI.
local AUTO_UI = {
    RootNames = { "Phone", "Телефон", "MobilePhone", "PhoneGui" },
    FlappyPlayer = { "Bird", "Player", "Skibidi", "Птица", "Игрок" },
    FlappyPipe = { "Pipe", "Tube", "Труба", "Препятствие" },
    DinoPlayer = { "Dino", "Dinosaur", "Динозавр" },
    DinoObstacle = { "Cactus", "Obstacle", "Кактус" },
    MineCell = { "Cell", "Tile", "Block", "Клетка", "Ячейка", "Button" },
    JumpButton = { "Jump", "Tap", "Flap", "Прыжок", "Вверх" },
    RestartButton = { "Сначала крути", "Еще раз", "Ещё раз", "Try again", "Restart", "Play again" },
    -- Точные имена при необходимости:
    -- PhoneRootName = "PhoneFrame", FlappyPlayerName = "BirdImage",
    -- DinoPlayerName = "DinoImage", MinesGridName = "MinesweeperGrid",
}
local page3
local AUTO = {
    flappy = false, dino = false, mines = false, restart = false,
    lastFlap = 0, lastJump = 0, lastRestart = {},
    dinoLastY = nil, dinoGroundFrames = 0,
    mineFirstMove = false, mineBusy = false, mineKnownMines = {},
    status = "Ожидание мини-игры",
}
local function autoToggle(label, order, fieldName)
    local row = mk("Frame", {
        Size = UDim2.new(1, -2, 0, 27), BackgroundColor3 = T.field,
        BorderSizePixel = 0, LayoutOrder = order,
    }, page3)
    corner(row, 6)
    text(row, {
        Text = label, TextSize = 10, Font = Enum.Font.GothamBold,
        Position = UDim2.new(0, 7, 0, 0), Size = UDim2.new(1, -48, 1, 0),
    })
    local b = mk("TextButton", {
        Size = UDim2.fromOffset(36, 19), Position = UDim2.new(1, -41, 0.5, -9),
        BackgroundColor3 = T.idle, Text = "ВЫКЛ", Font = Enum.Font.GothamBold,
        TextSize = 9, TextColor3 = T.text, AutoButtonColor = false,
    }, row)
    corner(b, 6)
    b.MouseButton1Click:Connect(function()
        AUTO[fieldName] = not AUTO[fieldName]
        if fieldName == "mines" then
            AUTO.mineFirstMove = false
            AUTO.mineKnownMines = {}
        end
        b.Text = AUTO[fieldName] and "ВКЛ" or "ВЫКЛ"
        tw(b, FAST, { BackgroundColor3 = AUTO[fieldName] and T.green or T.idle })
        AUTO.status = AUTO[fieldName] and "Поиск интерфейса..." or "Переключатель выключен"
    end)
end

page3 = mk("ScrollingFrame", {
    Name = "AutoGamesPage", Size = UDim2.fromScale(1, 1),
    Position = UDim2.new(1, 6, 0, 0), BackgroundColor3 = T.card,
    BorderSizePixel = 0, ClipsDescendants = true,
    CanvasSize = UDim2.new(0, 0, 0, 205), ScrollBarThickness = 3,
    ScrollBarImageColor3 = T.accent,
}, holder)
corner(page3, 8)
mk("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, page3)
mk("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, page3)
autoToggle("Авто-Скибиди (Flappy)", 1, "flappy")
autoToggle("Авто-Динозаврик (Dino)", 2, "dino")
autoToggle("Авто-Сапёр", 3, "mines")
autoToggle("Авто-перезапуск / бонус", 4, "restart")
local autoStatus = text(page3, {
    Text = AUTO.status, TextSize = 9, TextColor3 = T.gold,
    TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
    Size = UDim2.new(1, -2, 0, 25), LayoutOrder = 5,
})
text(page3, {
    Text = "При несовпадении имён UI укажи точные названия объектов в AUTO_UI (Dex Explorer).",
    TextSize = 8, TextColor3 = T.dim, TextWrapped = true,
    TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -2, 0, 25), LayoutOrder = 6,
})

local function hasName(value, names)
    value = string.lower(tostring(value or ""))
    for _, n in ipairs(names or {}) do
        if value:find(string.lower(n), 1, true) then return true end
    end
    return false
end
local function findUI(root, names, className)
    if not root then return nil end
    for _, o in ipairs(root:GetDescendants()) do
        if o:IsA("GuiObject") and hasName(o.Name, names) and (not className or o:IsA(className)) then
            return o
        end
    end
end
local function getPhoneRoot()
    if AUTO_UI.PhoneRootName then
        local o = pg:FindFirstChild(AUTO_UI.PhoneRootName, true)
        if o then return o end
    end
    return findUI(pg, AUTO_UI.RootNames) or pg
end
local function uiCenter(o)
    return o.AbsolutePosition.X + o.AbsoluteSize.X/2, o.AbsolutePosition.Y + o.AbsoluteSize.Y/2
end
local function visibleUI(o)
    local ok, v = pcall(function() return o.Visible end)
    return ok and v
end
local function allUI(root, names)
    local t = {}
    for _, o in ipairs(root:GetDescendants()) do
        if o:IsA("GuiObject") and visibleUI(o) and hasName(o.Name, names) then t[#t+1] = o end
    end
    return t
end
local function clickUI(o)
    if not o then return false end
    local ok = pcall(function()
        if type(firesignal) == "function" and o:IsA("GuiButton") then
            firesignal(o.Activated)
            firesignal(o.MouseButton1Click)
        elseif VIM and o:IsA("GuiButton") then
            local x, y = uiCenter(o)
            VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
            VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end
    end)
    return ok
end
local function gameTap(root)
    local b = findUI(root, AUTO_UI.JumpButton, "GuiButton")
    if b then return clickUI(b) end
    if VIM then
        pcall(function()
            VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
        return true
    end
    return false
end

-- Flappy: ближайшая пара труб справа, центр просвета между их краями.
local function tickFlappy(root, now)
    local birdNames = AUTO_UI.FlappyPlayerName and { AUTO_UI.FlappyPlayerName } or AUTO_UI.FlappyPlayer
    local pipeNames = AUTO_UI.FlappyPipeName and { AUTO_UI.FlappyPipeName } or AUTO_UI.FlappyPipe
    local bird, pipes = findUI(root, birdNames), allUI(root, pipeNames)
    if not bird or #pipes == 0 then return false end
    local bx, by = uiCenter(bird)
    local right = {}
    for _, p in ipairs(pipes) do
        if p.AbsolutePosition.X > bx then right[#right+1] = p end
    end
    table.sort(right, function(a,b) return a.AbsolutePosition.X < b.AbsolutePosition.X end)
    if #right == 0 then return false end
    local x0, upper, lower = right[1].AbsolutePosition.X
    for _, p in ipairs(right) do
        if math.abs(p.AbsolutePosition.X - x0) <= 14 then
            local _, cy = uiCenter(p)
            if cy < by then upper = p elseif not lower or p.AbsolutePosition.Y < lower.AbsolutePosition.Y then lower = p end
        end
    end
    local gapY
    if upper and lower then
        gapY = (upper.AbsolutePosition.Y + upper.AbsoluteSize.Y + lower.AbsolutePosition.Y)/2
    else
        local _, cy = uiCenter(right[1]); gapY = cy
    end
    if by > gapY + math.max(2, bird.AbsoluteSize.Y * 0.15) and now - AUTO.lastFlap > 0.085 then
        if gameTap(root) then AUTO.lastFlap = now end
    end
    return true
end

-- Dino: прыжок при приближении к препятствию.
local function tickDino(root, now)
    local dn = AUTO_UI.DinoPlayerName and { AUTO_UI.DinoPlayerName } or AUTO_UI.DinoPlayer
    local on = AUTO_UI.DinoObstacleName and { AUTO_UI.DinoObstacleName } or AUTO_UI.DinoObstacle
    local dino, obstacles = findUI(root, dn), allUI(root, on)
    if not dino or #obstacles == 0 then return false end
    local dx = dino.AbsolutePosition.X + dino.AbsoluteSize.X
    local currentY = dino.AbsolutePosition.Y
    if AUTO.dinoLastY and math.abs(currentY - AUTO.dinoLastY) <= 1 then
        AUTO.dinoGroundFrames = math.min(AUTO.dinoGroundFrames + 1, 5)
    else
        AUTO.dinoGroundFrames = 0
    end
    AUTO.dinoLastY = currentY
    local obstacle
    for _, o in ipairs(obstacles) do
        if o.AbsolutePosition.X >= dx and (not obstacle or o.AbsolutePosition.X < obstacle.AbsolutePosition.X) then obstacle = o end
    end
    if not obstacle then return false end
    local dist = obstacle.AbsolutePosition.X - dx
    local threshold = math.max(34, dino.AbsoluteSize.X * 1.35)
    if dist <= threshold and dist >= -4 and AUTO.dinoGroundFrames >= 2 and now - AUTO.lastJump > 0.42 then
        if gameTap(root) then AUTO.lastJump = now end
    end
    return true
end

-- Сапёр: автоматическое распознавание клеток и логические гарантированные ходы.
-- Для пустых открытых клеток интерфейс должен задавать Attribute Opened=true
-- либо имя клетки должно содержать Open/Opened/Открыта.
local function mineGrid(root)
    if AUTO_UI.MinesGridName then return root:FindFirstChild(AUTO_UI.MinesGridName, true) end
    return findUI(root, { "Minesweeper", "Mines", "Сапер", "Сапёр", "MineField", "MineGrid" })
end
local function cellState(o)
    local raw = o:IsA("TextButton") and tostring(o.Text or "") or ""
    if o:GetAttribute("Mine") == true or hasName(o.Name, {"Flag","Mine","Флаг","Мина"}) then return "mine", 0 end
    local n = tonumber(raw:match("[1-8]"))
    if n then return "open", n end
    if o:GetAttribute("Opened") == true or o:GetAttribute("Revealed") == true
        or hasName(o.Name, {"Opened","Revealed","Открыта","Открытая"}) then return "open", 0 end
    return "closed", 0
end
local function tickMines(root)
    if AUTO.mineBusy then return false end
    local grid = mineGrid(root)
    if not grid then return false end
    local cells = {}
    for _, o in ipairs(grid:GetDescendants()) do
        if o:IsA("GuiButton") and visibleUI(o)
            and (hasName(o.Name, AUTO_UI.MineCell) or o:GetAttribute("MineCell") == true) then
            cells[#cells+1] = o
        end
    end
    if #cells < 9 then return false end
    table.sort(cells, function(a,b)
        if math.abs(a.AbsolutePosition.Y-b.AbsolutePosition.Y)>7 then return a.AbsolutePosition.Y<b.AbsolutePosition.Y end
        return a.AbsolutePosition.X<b.AbsolutePosition.X
    end)
    local rows = {}
    for _, o in ipairs(cells) do
        local row
        for _, r in ipairs(rows) do if math.abs(r.y-o.AbsolutePosition.Y)<=7 then row=r break end end
        if not row then row={y=o.AbsolutePosition.Y,cells={}}; rows[#rows+1]=row end
        row.cells[#row.cells+1]=o
    end
    table.sort(rows,function(a,b)return a.y<b.y end)
    local board, cols = {}, 0
    for _,r in ipairs(rows) do
        table.sort(r.cells,function(a,b)return a.AbsolutePosition.X<b.AbsolutePosition.X end)
        board[#board+1]=r.cells; cols=math.max(cols,#r.cells)
    end
    local nr=#board
    if nr<2 or cols<2 then return false end
    if not AUTO.mineFirstMove then
        local target=board[math.ceil(nr/2)] and board[math.ceil(nr/2)][math.ceil(cols/2)]
        if target then AUTO.mineFirstMove=clickUI(target); return true end
    end
    local st, nums, safe, closed = {}, {}, {}, {}
    for r=1,nr do
        st[r],nums[r]={},{}
        for c=1,#board[r] do
            st[r][c],nums[r][c]=cellState(board[r][c])
            if st[r][c]=="closed" then closed[#closed+1]={r=r,c=c,obj=board[r][c]} end
        end
    end
    local function around(r,c)
        local a={}
        for rr=math.max(1,r-1),math.min(nr,r+1) do
            for cc=math.max(1,c-1),math.min(#board[rr],c+1) do
                if rr~=r or cc~=c then a[#a+1]={r=rr,c=cc} end
            end
        end
        return a
    end
    for r=1,nr do for c=1,#board[r] do
        if st[r][c]=="open" and nums[r][c]>0 then
            local unknown,mines={},0
            for _,p in ipairs(around(r,c)) do
                local obj=board[p.r][p.c]
                if st[p.r][p.c]=="mine" or AUTO.mineKnownMines[obj] then mines=mines+1
                elseif st[p.r][p.c]=="closed" then unknown[#unknown+1]=obj end
            end
            local left=nums[r][c]-mines
            if left==0 then for _,o in ipairs(unknown) do safe[#safe+1]=o end
            elseif #unknown>0 and left==#unknown then for _,o in ipairs(unknown) do AUTO.mineKnownMines[o]=true end end
        end
    end end
    if #safe>0 then
        AUTO.mineBusy=true
        for _,o in ipairs(safe) do clickUI(o) end
        AUTO.mineBusy=false
        return true
    end
    -- Выбор клетки с минимальной оценкой риска по соседним открытым цифрам.
    local best,bestRisk=nil,math.huge
    for _,p in ipairs(closed) do
        local sum,count=0,0
        for _,q in ipairs(around(p.r,p.c)) do
            if st[q.r][q.c]=="open" and nums[q.r][q.c]>0 then
                local unknown,mines=0,0
                for _,z in ipairs(around(q.r,q.c)) do
                    local obj=board[z.r][z.c]
                    if st[z.r][z.c]=="mine" or AUTO.mineKnownMines[obj] then mines=mines+1
                    elseif st[z.r][z.c]=="closed" then unknown=unknown+1 end
                end
                if unknown>0 then sum=sum+math.clamp((nums[q.r][q.c]-mines)/unknown,0,1); count=count+1 end
            end
        end
        local risk=count>0 and sum/count or 0.5
        if risk<bestRisk then best,bestRisk=board[p.r][p.c],risk end
    end
    if best then return clickUI(best) end
    return true
end

local function tickRestart(root, now)
    for _, b in ipairs(allUI(root, AUTO_UI.RestartButton)) do
        if b:IsA("GuiButton") and now-(AUTO.lastRestart[b] or 0)>0.8 then
            if clickUI(b) then AUTO.lastRestart[b]=now end
        end
    end
end
local autoHeartbeat
autoHeartbeat = RunService.Heartbeat:Connect(function()
    if not gui.Parent then autoHeartbeat:Disconnect(); return end
    if not (AUTO.flappy or AUTO.dino or AUTO.mines or AUTO.restart) then return end
    local root, now = getPhoneRoot(), os.clock()
    local ok, found = pcall(function()
        local any=false
        if AUTO.flappy then any=tickFlappy(root,now) or any end
        if AUTO.dino then any=tickDino(root,now) or any end
        if AUTO.mines then any=tickMines(root) or any end
        if AUTO.restart then tickRestart(root,now) end
        return any
    end)
    AUTO.status = ok and (found and "Авто-прохождение активно" or "Ожидание / UI не найден")
        or ("Ошибка UI: "..tostring(found):sub(1,45))
    autoStatus.Text = AUTO.status
end)

local function refreshSpeed()
    for i, b in ipairs(speedBtns) do
        local on = SPEEDS[i][2] == S.interval
        tw(b, FAST, { BackgroundColor3 = on and T.accent or T.field, TextColor3 = on and T.dark or T.dim })
    end
end
for i, b in ipairs(speedBtns) do
    b.MouseButton1Click:Connect(function()
        S.interval = SPEEDS[i][2]
        refreshSpeed()
    end)
end

-- пересчёт границ покупки и подписей
local function refreshLimits()
    local lo, hi = limits()
    if S.sell > 0 then
        boxMax.Text = tostring(math.max(hi, 0))
        boxMax.TextEditable = false
        boxMax.TextColor3 = T.dim
        capMax.Text = "ДО, ₽ (авто)"
        infoNet.Text = "Чистыми: " .. fmt(netOf(S.sell)) .. " ₽ (комиссия -10%)"
        infoMax.Text = "Покупать не дороже " .. fmt(math.max(hi, 0)) .. " ₽"
    else
        boxMax.Text = tostring(S.max)
        boxMax.TextEditable = true
        boxMax.TextColor3 = T.accent
        capMax.Text = "ДО, ₽"
        infoNet.Text = "Цена продажи не задана"
        infoMax.Text = "Укажи цену и прибыль, остальное посчитаю"
    end
    boxMin.Text = tostring(S.min)
end

boxMin.FocusLost:Connect(function()
    local v = digits(boxMin.Text)
    if v then S.min = v end
    refreshLimits()
end)
boxMax.FocusLost:Connect(function()
    if S.sell == 0 then
        local v = digits(boxMax.Text)
        if v then S.max = v end
        if S.min > S.max then S.min, S.max = S.max, S.min end
    end
    refreshLimits()
end)
boxSell.FocusLost:Connect(function()
    S.sell = digits(boxSell.Text) or 0
    boxSell.Text = S.sell > 0 and tostring(S.sell) or ""
    refreshLimits()
end)
boxProfit.FocusLost:Connect(function()
    S.profit = digits(boxProfit.Text) or 0
    boxProfit.Text = S.profit > 0 and tostring(S.profit) or ""
    refreshLimits()
end)

-- переключение вкладок
local pageIdx = 1
local function refreshTabs()
    for i, b in ipairs(tabBtns) do
        local on = i == pageIdx
        tw(b, FAST, { BackgroundColor3 = on and T.accent or T.card, TextColor3 = on and T.dark or T.dim })
    end
end
local PAGES = { page1, page2, page3 }
local function showPage(i)
    if i == pageIdx or not PAGES[i] then return end
    local right = i > pageIdx
    local oldP = PAGES[pageIdx]
    local newP = PAGES[i]
    newP.Position = UDim2.new(right and 1 or -1, right and 6 or -6, 0, 0)
    tw(oldP, PAGE, { Position = UDim2.new(right and -1 or 1, right and -6 or 6, 0, 0) })
    tw(newP, PAGE, { Position = UDim2.new(0, 0, 0, 0) })
    pageIdx = i
    refreshTabs()
end
for i, b in ipairs(tabBtns) do
    b.MouseButton1Click:Connect(function() showPage(i) end)
end

-- старт / стоп
local startBtn = mk("TextButton", {
    Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.green, Text = "СТАРТ",
    Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = T.text, LayoutOrder = 4,
}, content)
corner(startBtn, 8)

-- статистика: куплено | заработок | упущено
local stats = mk("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 5 }, content)
mk("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, stats)

local function tile(order, caption, col)
    local f = mk("Frame", { Size = UDim2.new(1 / 3, -4, 1, 0), BackgroundColor3 = T.card, BorderSizePixel = 0, LayoutOrder = order }, stats)
    corner(f, 8)
    local n = text(f, {
        Text = "0", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = col,
        TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.new(0, 2, 0, 2), Size = UDim2.new(1, -4, 0, 16),
    })
    text(f, {
        Text = caption, TextSize = 9, TextColor3 = T.dim,
        TextXAlignment = Enum.TextXAlignment.Center,
        Position = UDim2.new(0, 0, 0, 19), Size = UDim2.new(1, 0, 0, 11),
    })
    return n
end
local nWon = tile(1, "КУПЛЕНО", T.green)
local nEarn = tile(2, "ЗАРАБОТОК", T.gold)
local nLost = tile(3, "УПУЩЕНО", T.accent)

local function updStats()
    nWon.Text = tostring(S.won)
    nEarn.Text = short(S.earn)
    nLost.Text = tostring(S.lost)
end

-- статус
local statusCard = mk("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = T.card, BorderSizePixel = 0, LayoutOrder = 6 }, content)
corner(statusCard, 8)
local lblStatus = text(statusCard, {
    Text = "", TextSize = 11, Font = Enum.Font.GothamBold, TextTruncate = Enum.TextTruncate.AtEnd,
    Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -60, 1, 0),
})
local lblLot = text(statusCard, {
    Text = "-", TextSize = 10, TextColor3 = T.dim, TextXAlignment = Enum.TextXAlignment.Right,
    Position = UDim2.new(1, -50, 0, 0), Size = UDim2.new(0, 42, 1, 0),
})

-- дождь из букв P / h (виден, пока меню открыто)
local rain = mk("Frame", { Name = "Rain", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, main)
local drops = {}
local function resetDrop(d, initial)
    d.x = math.random(4, W - 20)
    d.y = initial and math.random(-20, H) or -18
    d.v = math.random(28, 70)
    d.rv = math.random(-35, 35)
    d.rot = math.random(-20, 20)
    d.ph = math.random() * 6
    local isP = math.random() < 0.5
    d.l.Text = isP and "P" or "h"
    d.l.TextColor3 = isP and T.accent or T.text
    d.l.TextSize = math.random(11, 17)
end
for i = 1, 14 do
    local l = text(rain, {
        Text = "P", Font = Enum.Font.GothamBlack, TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1,
        Size = UDim2.fromOffset(16, 16), ZIndex = 6,
    })
    drops[i] = { l = l }
    resetDrop(drops[i], true)
end

-- плавающий знак защиты
local wm = mk("TextLabel", {
    Name = "Mark", Size = UDim2.fromOffset(200, 22), BackgroundTransparency = 1,
    Text = 'By tg Torn_tuz_lua', Font = Enum.Font.GothamBold, TextSize = 15,
    TextColor3 = T.text, TextTransparency = 0.5, ZIndex = 50, Active = false,
}, gui)
mk("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.2, Transparency = 0.5 }, wm)
pcall(function() wm.Interactable = false end)

-- свёрнутый значок "Ph"
local bubble = mk("TextButton", {
    Visible = false, Size = UDim2.fromOffset(48, 48), Position = main.Position,
    BackgroundColor3 = T.accent, Text = "Ph", Font = Enum.Font.GothamBlack, TextSize = 21,
    TextColor3 = T.dark, AutoButtonColor = false,
}, gui)
corner(bubble, 24)
stroke(bubble, Color3.fromRGB(255, 255, 255), 2)
local bubbleScale = mk("UIScale", { Scale = 1 }, bubble)
local bubbleDot = mk("Frame", {
    Size = UDim2.fromOffset(13, 13), Position = UDim2.new(1, -11, 0, -2),
    BackgroundColor3 = T.idle, BorderSizePixel = 0,
}, bubble)
corner(bubbleDot, 7)
stroke(bubbleDot, T.bg, 2)

-- кнопки и поля самого меню нельзя выбрать клавиатурой/геймпадом:
-- иначе Enter, который шлёт скрипт, мог нажать «-» или другие кнопки меню
local function lockSelect(d)
    if d:IsA("GuiButton") or d:IsA("TextBox") then
        pcall(function() d.Selectable = false end)
    end
end
for _, d in ipairs(gui:GetDescendants()) do lockSelect(d) end
gui.DescendantAdded:Connect(lockSelect)

-- заставка на весь экран при запуске
local function showSplash()
    local ov = mk("Frame", {
        Name = "Splash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 100, Active = true,
    }, gui)
    local txt = mk("TextLabel", {
        Size = UDim2.fromScale(0.92, 0.34), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.46), BackgroundTransparency = 1,
        Text = 'By tg Torn_tuz_lua', Font = Enum.Font.GothamBlack, TextScaled = true,
        TextColor3 = Color3.new(1, 1, 1), TextTransparency = 1, ZIndex = 101,
    }, ov)
    mk("UITextSizeConstraint", { MaxTextSize = 90 }, txt)
    local sc = mk("UIScale", { Scale = 0.7 }, txt)
    local grad = mk("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, T.accent),
            ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(1, T.accent),
        }),
        Offset = Vector2.new(-1, 0),
    }, txt)
    local sub = mk("TextLabel", {
        Size = UDim2.fromScale(0.8, 0.07), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.66), BackgroundTransparency = 1,
        Text = "Plate Sniper", Font = Enum.Font.GothamBold, TextScaled = true,
        TextColor3 = T.dim, TextTransparency = 1, ZIndex = 101,
    }, ov)
    mk("UITextSizeConstraint", { MaxTextSize = 26 }, sub)

    tw(ov, TweenInfo.new(0.35), { BackgroundTransparency = 0.12 })
    tw(txt, TweenInfo.new(0.5), { TextTransparency = 0 })
    tw(sc, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
    tw(sub, TweenInfo.new(0.5), { TextTransparency = 0.2 })
    tw(grad, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Offset = Vector2.new(1, 0) })
    task.wait(2.3)
    tw(ov, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
    tw(txt, TweenInfo.new(0.5), { TextTransparency = 1 })
    tw(sub, TweenInfo.new(0.5), { TextTransparency = 1 })
    local t = tw(sc, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1.15 })
    t.Completed:Wait()
    ov:Destroy()
end

---------------------------------------------------------------- КЛЮЧ
local KEYS = { ["ko01-28-1DAYS-82dn"] = true }
local KEY_FILE = "PlateSniper_key.txt"
local canFile = type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"

-- Бессрочный режим: разрешённый ключ больше не истекает.
local function keyDays(k) return math.huge end

local function readSaved()
    if not canFile then return nil end
    local ok, data = pcall(function()
        if isfile(KEY_FILE) then return readfile(KEY_FILE) end
        return nil
    end)
    if not ok or type(data) ~= "string" then return nil end
    local k, t = data:match("^(.-)|(%d+)%s*$")
    if k and t then return k, tonumber(t) end
    return nil
end

local function saveKey(k, t)
    if canFile then pcall(function() writefile(KEY_FILE, k .. "|" .. tostring(t)) end) end
end

-- проверка ключа: возвращает время окончания или nil, причину
local function checkKey(k)
    if not KEYS[k] then return nil, "неверный ключ" end
    local sk, st = readSaved()
    local start
    if sk == k and st then
        start = st
    else
        start = os.time()
        saveKey(k, start)
    end
    local expire = start + keyDays(k) * 86400
    if os.time() >= expire then return nil, "срок ключа истёк" end
    return expire
end

local function fmtLeft(sec)
    if sec == math.huge then return "∞" end
    if sec <= 0 then return "0м" end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return h .. "ч " .. m .. "м" end
    return m .. "м"
end

-- окно ввода ключа; true - ключ принят, false - окно закрыли
local function showKeyScreen()
    local result = nil
    local ov = mk("Frame", {
        Name = "KeyScreen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg,
        BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 90, Active = true,
    }, gui)
    local card = mk("CanvasGroup", {
        Size = UDim2.fromOffset(250, 164), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = T.card, BorderSizePixel = 0,
        GroupTransparency = 1, ZIndex = 91,
    }, ov)
    corner(card, 12)
    stroke(card, T.accent, 1.5)
    local sc = mk("UIScale", { Scale = 0.85 }, card)

    text(card, {
        Text = "Plate Sniper", Font = Enum.Font.GothamBold, TextSize = 16,
        Position = UDim2.new(0, 14, 0, 10), Size = UDim2.new(1, -50, 0, 20), ZIndex = 92,
    })
    text(card, {
        Text = "Введи ключ активации", TextSize = 11, TextColor3 = T.dim,
        Position = UDim2.new(0, 14, 0, 31), Size = UDim2.new(1, -28, 0, 14), ZIndex = 92,
    })
    local closeB = mk("TextButton", {
        Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -30, 0, 8),
        BackgroundColor3 = T.field, Text = "x", Font = Enum.Font.GothamBold, TextSize = 14,
        TextColor3 = T.dim, AutoButtonColor = true, ZIndex = 92,
    }, card)
    corner(closeB, 6)

    local box = mk("TextBox", {
        Position = UDim2.new(0, 14, 0, 54), Size = UDim2.new(1, -28, 0, 32),
        BackgroundColor3 = T.field, Text = "", PlaceholderText = "xxxx-xx-xDAYS-xxxx",
        PlaceholderColor3 = T.idle, Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = T.accent, ClearTextOnFocus = false, ZIndex = 92,
    }, card)
    corner(box, 8)
    local bst = stroke(box, T.line, 1)
    box.Focused:Connect(function() tw(bst, FAST, { Color = T.accent }) end)
    box.FocusLost:Connect(function() tw(bst, FAST, { Color = T.line }) end)

    local go = mk("TextButton", {
        Position = UDim2.new(0, 14, 0, 96), Size = UDim2.new(1, -28, 0, 32),
        BackgroundColor3 = T.accent, Text = "Активировать", Font = Enum.Font.GothamBold,
        TextSize = 14, TextColor3 = T.dark, AutoButtonColor = true, ZIndex = 92,
    }, card)
    corner(go, 8)

    local msg = text(card, {
        Text = "", TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center,
        Position = UDim2.new(0, 14, 0, 136), Size = UDim2.new(1, -28, 0, 16), ZIndex = 92,
    })

    local busyK = false
    local function submit()
        if busyK or result ~= nil then return end
        busyK = true
        local typed = (box.Text:gsub("^%s+", ""):gsub("%s+$", ""))
        local expire, why = checkKey(typed)
        if expire then
            S.licensed = true
            S.keyExpire = expire
            msg.TextColor3 = T.green
            msg.Text = "ключ принят"
            task.wait(0.6)
            result = true
        else
            msg.TextColor3 = T.red
            msg.Text = why
            for _ = 1, 3 do
                tw(card, TweenInfo.new(0.05), { Position = UDim2.new(0.5, -6, 0.5, 0) })
                task.wait(0.05)
                tw(card, TweenInfo.new(0.05), { Position = UDim2.new(0.5, 6, 0.5, 0) })
                task.wait(0.05)
            end
            tw(card, TweenInfo.new(0.05), { Position = UDim2.fromScale(0.5, 0.5) })
        end
        busyK = false
    end
    go.MouseButton1Click:Connect(submit)
    box.FocusLost:Connect(function(enter) if enter then submit() end end)
    closeB.MouseButton1Click:Connect(function() result = false end)

    tw(card, TweenInfo.new(0.3), { GroupTransparency = 0 })
    tw(sc, OPEN, { Scale = 1 })
    while result == nil and gui.Parent do task.wait(0.1) end
    if not gui.Parent then return false end
    tw(card, CLOSE, { GroupTransparency = 1 })
    tw(ov, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
    local t = tw(sc, CLOSE, { Scale = 0.8 })
    t.Completed:Wait()
    ov:Destroy()
    return result == true
end

local KIND = { idle = T.idle, run = T.green, ok = T.green, warn = T.accent, err = T.red }

local function setState(kind, msg)
    lblStatus.Text = msg
    lblStatus.TextColor3 = (kind == "idle") and T.dim or KIND[kind]
    local c = S.enabled and KIND[kind] or T.idle
    tw(dot, FAST, { BackgroundColor3 = c })
    tw(bubbleDot, FAST, { BackgroundColor3 = c })
end

local function refreshToggle()
    if S.enabled then
        startBtn.Text = "СТОП"
        tw(startBtn, FAST, { BackgroundColor3 = T.red })
        setState("run", "запущен")
    else
        startBtn.Text = "СТАРТ"
        tw(startBtn, FAST, { BackgroundColor3 = T.green })
        setState("idle", "выключен")
    end
end

-- анимации фона: дождь + знак
local t0 = os.clock()
local hb
hb = RunService.Heartbeat:Connect(function(dt)
    if not gui.Parent then
        hb:Disconnect()
        return
    end
    local t = os.clock() - t0

    local v = workspace.CurrentCamera.ViewportSize
    wm.Position = UDim2.fromOffset(
        (v.X - 200) * (0.5 + 0.5 * math.sin(t * 0.31 + 0.8)),
        (v.Y - 24) * (0.5 + 0.5 * math.sin(t * 0.19))
    )
    wm.Rotation = 5 * math.sin(t * 0.45)
    wm.TextTransparency = 0.5 + 0.18 * math.sin(t * 1.2)
    wm.TextColor3 = T.text:Lerp(T.accent, 0.5 + 0.5 * math.sin(t * 0.6))

    if main.Visible then
        for _, d in ipairs(drops) do
            d.y += d.v * dt
            d.rot += d.rv * dt
            if d.y > H then resetDrop(d, false) end
            local a = math.clamp(d.y / H, 0, 1)
            d.l.Position = UDim2.fromOffset(d.x + math.sin(t * 1.5 + d.ph) * 4, d.y)
            d.l.Rotation = d.rot
            d.l.TextTransparency = 0.66 + 0.34 * (1 - math.sin(math.pi * a))
        end
    end
end)

-- перетаскивание
local function clampXY(x, y, sz)
    local v = workspace.CurrentCamera.ViewportSize
    return math.clamp(x, 0, math.max(0, v.X - sz.X)), math.clamp(y, 0, math.max(0, v.Y - sz.Y))
end

local function makeDraggable(handle, target, onTap)
    local dragging, moved, dragStart, startPos = false, false, nil, nil
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart = i.Position
            startPos = target.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if onTap and not moved then onTap() end
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if not dragging or not gui.Parent then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
            local d = i.Position - dragStart
            if d.Magnitude > 6 then moved = true end
            if moved then
                local x, y = clampXY(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y, target.AbsoluteSize)
                target.Position = UDim2.fromOffset(x, y)
            end
        end
    end)
end

-- плавное сворачивание / разворачивание
local busy = false
local function setMin(on)
    if busy then return end
    busy = true
    if on then
        local x, y = clampXY(main.AbsolutePosition.X, main.AbsolutePosition.Y, Vector2.new(48, 48))
        tw(main, CLOSE, { GroupTransparency = 1 })
        local t = tw(mainScale, CLOSE, { Scale = 0.2 })
        t.Completed:Wait()
        main.Visible = false
        bubble.Position = UDim2.fromOffset(x, y)
        bubbleScale.Scale = 0.2
        bubble.Visible = true
        tw(bubbleScale, OPEN, { Scale = 1 })
    else
        local x, y = clampXY(bubble.AbsolutePosition.X, bubble.AbsolutePosition.Y, Vector2.new(W, H))
        local t = tw(bubbleScale, CLOSE, { Scale = 0.2 })
        t.Completed:Wait()
        bubble.Visible = false
        main.Position = UDim2.fromOffset(x, y)
        mainScale.Scale = 0.8
        main.GroupTransparency = 1
        main.Visible = true
        tw(mainScale, OPEN, { Scale = 1 })
        tw(main, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { GroupTransparency = 0 })
    end
    task.wait(0.05)
    busy = false
end

makeDraggable(header, main)
makeDraggable(bubble, bubble, function() setMin(false) end)
btnMin.MouseButton1Click:Connect(function() setMin(true) end)

local alive = true
btnClose.MouseButton1Click:Connect(function()
    alive = false
    S.enabled = false
    tw(wm, CLOSE, { TextTransparency = 1 })
    tw(main, CLOSE, { GroupTransparency = 1 })
    local t = tw(mainScale, CLOSE, { Scale = 0.6 })
    t.Completed:Wait()
    gui:Destroy()
end)

---------------------------------------------------------------- ТЕКСТЫ
local function norm(t)
    t = (t or "")
    t = t:gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("\226\128\137", " "):gsub("<[^>]*>", "")
    return t
end
local function trim(s) return ((s:gsub("^%s+", ""):gsub("%s+$", ""))) end

local function hasAny(t, list)
    for _, p in ipairs(list) do
        if t:find(p, 1, true) then return true end
    end
    return false
end
local function startsAny(t, list)
    for _, p in ipairs(list) do
        if t:sub(1, #p) == p then return true end
    end
    return false
end
local function eqAny(t, list)
    for _, p in ipairs(list) do
        if t == p then return true end
    end
    return false
end

local BUY = { "КУПИТЬ", "Купить", "купить" }
local CONFIRM = { "КУПИТЬ ЗА", "Купить за", "купить за" }
local SOLD = { "ПРОДАН", "Продан" }
local MARKET = { "НА РЫНКЕ", "На рынке" }
local CANCEL = { "ОТМЕНА", "Отмена" }
local ERR = { "Ошибка", "ОШИБКА" }
local SLOW = { "Не так быстро", "НЕ ТАК БЫСТРО" }
local CLOSE_TEXT = { "✕", "✖", "×", "X", "x", "╳", "✗", "⨯", "Х", "х", "❌" }
local CHECKING = { "ПРОВЕРЯЮ", "Проверяю" }
local RAFFLE = { "ПОКУПКА", "Покупка" }
local SORT_TEXT = { "Новые", "Скоро конец", "Дешёвые", "Дешевые", "Дорогие", "Удача", "Мои" }
local CHEAP = { "Дешёвые", "Дешевые" }

local function isConfirmText(t) return hasAny(t, CONFIRM) end
local function isBuyText(t) return hasAny(t, BUY) and not isConfirmText(t) end
local function isCloseText(t) return eqAny(trim(norm(t)), CLOSE_TEXT) end

local function parsePrice(t)
    if not t then return nil end
    if t:find("ГОС", 1, true) or t:find("Гос", 1, true) or t:find("гос", 1, true) then return nil end
    local rest = (t:gsub("[%d%s%.,]", ""))
    if t:find("₽", 1, true) or rest == "Р" or rest == "P" or rest == "руб" then
        return tonumber((t:gsub("%D", "")))
    end
    return nil
end

-- реально ли элемент виден на экране
local function isVisible(obj)
    local cur = obj
    while cur and cur ~= game do
        if cur:IsA("GuiObject") then
            if not cur.Visible then return false end
            if cur:IsA("CanvasGroup") and cur.GroupTransparency >= 0.95 then return false end
        end
        if cur:IsA("ScreenGui") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    if obj:IsA("GuiObject") then
        local s, p = obj.AbsoluteSize, obj.AbsolutePosition
        if s.X < 2 or s.Y < 2 then return false end
        local v = workspace.CurrentCamera.ViewportSize
        local cx, cy = p.X + s.X / 2, p.Y + s.Y / 2
        if cx < 0 or cy < 0 or cx > v.X or cy > v.Y + 100 then return false end
    end
    if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.TextTransparency >= 0.95 then return false end
    return true
end

local function realButton(obj)
    if obj:IsA("GuiButton") then return obj end
    local cur = obj.Parent
    for _ = 1, 3 do
        if cur and cur:IsA("GuiButton") then return cur end
        cur = cur and cur.Parent
    end
    return obj
end

local function center(o) return o.AbsolutePosition + o.AbsoluteSize / 2 end

---------------------------------------------------------------- КЛИКИ
local SIGS = { "Activated", "MouseButton1Click", "MouseButton1Up", "MouseButton1Down" }

local function fireOne(btn)
    if getconnections then
        for _, sig in ipairs(SIGS) do
            local ok, conns = pcall(function() return getconnections(btn[sig]) end)
            if ok and conns and #conns > 0 then
                for _, c in ipairs(conns) do pcall(function() c:Fire() end) end
                return true
            end
        end
    end
    if firesignal then
        local ok = pcall(function() firesignal(btn.Activated) end)
        if ok then return true end
    end
    return false
end

-- select: выбрать кнопку и нажать Enter. Перед Enter проверяем, что выбрана нужная кнопка.
local function selectPress(btn)
    if not VIM or not btn:IsA("GuiButton") then return false end
    local ok = pcall(function()
        btn.Selectable = true
        GuiService.SelectedObject = btn
    end)
    if not ok then return false end
    task.wait(0.05)
    if GuiService.SelectedObject ~= btn then
        pcall(function() GuiService.SelectedObject = nil end)
        return false
    end
    pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.04)
        VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    end)
    task.wait(0.03)
    pcall(function() GuiService.SelectedObject = nil end)
    return true
end

local METHODS = { "select", "fire" }
local LETTER = { select = "S", fire = "F" }
local mIdx = 1
local trace = {}

local function doMethod(m, btn)
    if m == "select" then return selectPress(btn) end
    return fireOne(btn)
end

local function mtag() return " [" .. METHODS[mIdx] .. "]" end

local function traceStr()
    local out = {}
    for _, m in ipairs(METHODS) do
        out[#out + 1] = LETTER[m] .. (trace[m] and "+" or "-")
    end
    return table.concat(out, " ")
end

-- нажать и проверить результат; если не сработало - пробуем следующий способ
local function clickVerified(btn, verify, waitT)
    waitT = waitT or 0.5
    for k in pairs(trace) do trace[k] = nil end
    for k = 0, #METHODS - 1 do
        local idx = ((mIdx - 1 + k) % #METHODS) + 1
        local m = METHODS[idx]
        local ran = doMethod(m, btn)
        trace[m] = ran and true or false
        if ran then
            local t0c = os.clock()
            repeat
                task.wait(0.05)
                if verify() then
                    mIdx = idx
                    return true
                end
            until os.clock() - t0c >= waitT
        end
    end
    return false
end

-- просто нажать (без проверки), первым доступным способом
local function pressRaw(btn)
    for k = 0, #METHODS - 1 do
        local idx = ((mIdx - 1 + k) % #METHODS) + 1
        if doMethod(METHODS[idx], btn) then return true end
    end
    return false
end

---------------------------------------------------------------- ПОИСК
local function findCard(btn)
    local cur = btn.Parent
    for _ = 1, 8 do
        if not cur or not cur:IsA("GuiObject") then break end
        local buys, price = 0, nil
        for _, d in ipairs(cur:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                local t = norm(d.Text)
                if isBuyText(t) then buys += 1 end
                if not price and d:IsA("TextLabel") then price = parsePrice(t) end
            end
        end
        if buys > 1 then return nil end
        if price then return cur, price end
        cur = cur.Parent
    end
    return nil
end

-- редкость лота по надписи в карточке («РЕДКИЙ · СТАРОЕ · +0.3»)
local function rarityOfText(t)
    for _, r in ipairs(RAR) do
        if startsAny(t, r.stems) then return r.key end
    end
    return nil
end

-- текст надписи без разметки (RichText: цветные части в одной строке)
local function labelText(d)
    local t = d.Text
    if d.RichText then
        local ok, ct = pcall(function() return d.ContentText end)
        if ok and type(ct) == "string" and ct ~= "" then t = ct end
    end
    return trim(norm(t))
end

local function cardRarity(card)
    for _, d in ipairs(card:GetDescendants()) do
        if d:IsA("TextLabel") then
            local t = labelText(d)
            if t:find(" ", 1, true) and #t < 60 then
                local k = rarityOfText(t)
                if k then return k end
            end
        end
    end
    return nil
end

local function isCloseBtn(o)
    if o:IsA("TextButton") and isCloseText(o.Text) then return true end
    local n = o.Name:lower()
    if n:find("close", 1, true) or n == "x" or n == "exit" then return true end
    for _, c in ipairs(o:GetChildren()) do
        if c:IsA("TextLabel") and isCloseText(c.Text) then return true end
        if c:IsA("ImageLabel") and c.Name:lower():find("close", 1, true) then return true end
    end
    return false
end

-- рамка ОКНА ЛОТА: самый верхний предок, который ещё "размером с окно лота"
-- (уже 40% экрана и строго по центру). Рамка всей торговой площадки шире.
local function modalFrame(ref)
    local v = workspace.CurrentCamera.ViewportSize
    local best
    local cur = ref
    while cur and cur:IsA("GuiObject") do
        local s = cur.AbsoluteSize
        if s.X > v.X * 0.40 then break end
        if s.Y >= v.Y * 0.25 then best = cur end
        cur = cur.Parent
    end
    if not best then return nil end
    local c = center(best)
    if math.abs(c.X - v.X / 2) > v.X * 0.07 then return nil end
    return best
end

-- крестик окна лота: ищем только внутри рамки окна, ближе к её правому верхнему углу
local function findClose(ref)
    local mf = modalFrame(ref)
    if not mf then return nil end
    local v = workspace.CurrentCamera.ViewportSize
    local p, s = mf.AbsolutePosition, mf.AbsoluteSize
    local corner = Vector2.new(p.X + s.X, p.Y)
    local scope = (mf.Parent and mf.Parent:IsA("GuiObject")) and mf.Parent or mf

    local function inside(o)
        local c = center(o)
        return c.X >= p.X - 6 and c.X <= p.X + s.X + 6 and c.Y >= p.Y - 6 and c.Y <= p.Y + s.Y + 6
    end

    local best, bd, sq, sd
    for _, d in ipairs(scope:GetDescendants()) do
        local cand
        if d:IsA("GuiButton") then
            if isCloseBtn(d) then cand = d end
        elseif d:IsA("TextLabel") and isCloseText(d.Text) then
            cand = realButton(d)
        end
        if cand then
            if inside(cand) and isVisible(cand) then
                local dist = (center(cand) - corner).Magnitude
                if not bd or dist < bd then best, bd = cand, dist end
            end
        elseif d:IsA("GuiButton") and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 then
            local sz = d.AbsoluteSize
            if sz.X >= v.X * 0.015 and sz.X <= v.X * 0.07 and sz.Y <= v.X * 0.07 and math.abs(sz.X / sz.Y - 1) < 0.5 then
                local cc = center(d)
                if inside(d) and cc.Y < p.Y + s.Y * 0.25 and cc.X > p.X + s.X * 0.5 and isVisible(d) then
                    local dist = (cc - corner).Magnitude
                    if not sd or dist < sd then sq, sd = d, dist end
                end
            end
        end
    end
    return best or sq
end

local function collect()
    local c = { buys = {} }
    for _, sg in ipairs(pg:GetChildren()) do
        if sg:IsA("ScreenGui") and sg.Enabled and sg ~= gui then
            for _, d in ipairs(sg:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    local raw = d.Text
                    if raw ~= "" and #raw < 90 then
                        local t = trim(norm(raw))
                        if startsAny(t, SOLD) then
                            if isVisible(d) and modalFrame(d) then
                                if not c.soldTitle or #t < c.soldTitleLen then
                                    c.soldTitle, c.soldTitleLen = d, #t
                                end
                                if not c.soldInfo or #t > #c.soldInfo then c.soldInfo = t end
                            end
                        elseif eqAny(t, MARKET) then
                            if isVisible(d) then c.market = d end
                        elseif startsAny(t, ERR) then
                            if isVisible(d) then c.err = d end
                        elseif hasAny(t, SLOW) then
                            if isVisible(d) then c.slow = d end
                        elseif eqAny(t, CANCEL) then
                            if isVisible(d) then c.cancel = realButton(d) end
                        elseif isConfirmText(t) then
                            if isVisible(d) then c.confirm = d end
                        elseif startsAny(t, CHECKING) then
                            if isVisible(d) then c.checking = d end
                        elseif startsAny(t, RAFFLE) then
                            if isVisible(d) and modalFrame(d) then c.raffle = d end
                        elseif isBuyText(t) then
                            if isVisible(d) then c.buys[#c.buys + 1] = d end
                        end
                    end
                end
            end
        end
    end
    return c
end

---------------------------------------------------------------- АВТОНАСТРОЙКА РЫНКА
-- все видимые надписи, для которых pred(текст, объект) вернул true
local function labelsWhere(pred)
    local out = {}
    for _, sg in ipairs(pg:GetChildren()) do
        if sg:IsA("ScreenGui") and sg.Enabled and sg ~= gui then
            for _, d in ipairs(sg:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    local raw = d.Text
                    if raw ~= "" and #raw < 60 then
                        local t = trim(norm(raw))
                        if pred(t, d) and isVisible(d) then out[#out + 1] = d end
                    end
                end
            end
        end
    end
    return out
end

local function marketOpen()
    return #labelsWhere(function(t) return t == "АУКЦИОН" or t == "Аукцион" end) > 0
end

local function openMarket()
    if marketOpen() then return true end
    local btn
    for _, d in ipairs(labelsWhere(function(t) return t == "ТОРГИ" or t == "Торги" end)) do
        local b = realButton(d)
        if b:IsA("GuiButton") then btn = b break end
    end
    if not btn then return false end
    clickVerified(btn, marketOpen, 1.2)
    for _ = 1, 20 do
        if marketOpen() then return true end
        task.wait(0.1)
    end
    return marketOpen()
end

-- строка панели фильтров: надпись «ЛОТЫ»
local function rowRef()
    local r = labelsWhere(function(t) return t == "ЛОТЫ" or t == "Лоты" end)
    return r[1]
end

local function sortHeader(ref)
    if not ref then return nil end
    local rc = center(ref)
    local v = workspace.CurrentCamera.ViewportSize
    local best
    for _, d in ipairs(labelsWhere(function(t) return eqAny(t, SORT_TEXT) end)) do
        local c = center(d)
        if math.abs(c.Y - rc.Y) < v.Y * 0.04 and c.X > rc.X then best = d end
    end
    return best
end

local function sortIsCheap()
    local h = sortHeader(rowRef())
    return h and eqAny(trim(norm(h.Text)), CHEAP) or false
end

local function sortOption(ref)
    local rc = center(ref)
    local v = workspace.CurrentCamera.ViewportSize
    for _, d in ipairs(labelsWhere(function(t) return eqAny(t, CHEAP) end)) do
        if center(d).Y > rc.Y + v.Y * 0.05 then return d end
    end
    return nil
end

local function setSort()
    if sortIsCheap() then return true end
    local ref = rowRef()
    local h = sortHeader(ref)
    if not h then return false end
    clickVerified(realButton(h), function()
        local r = rowRef()
        return r and sortOption(r) ~= nil
    end, 0.8)
    local r = rowRef()
    local opt = r and sortOption(r)
    if not opt then return false end
    clickVerified(realButton(opt), sortIsCheap, 0.8)
    task.wait(0.3)
    return sortIsCheap()
end

-- заголовок списка «Редкость»: ближайшая надпись справа от сортировки в той же строке
local function rarityHeader(ref)
    if not ref then return nil end
    local rc = center(ref)
    local v = workspace.CurrentCamera.ViewportSize
    local sh = sortHeader(ref)
    local sx = sh and center(sh).X or rc.X
    local best, bx
    for _, d in ipairs(labelsWhere(function(t, o)
        if not o:IsA("TextLabel") and not o:IsA("TextButton") then return false end
        if eqAny(t, SORT_TEXT) or t == "ЛОТЫ" or t == "ИСТОРИЯ" then return false end
        local c = center(o)
        return math.abs(c.Y - rc.Y) < v.Y * 0.04 and c.X > sx + 10
    end)) do
        local x = center(d).X
        if not bx or x < bx then best, bx = d, x end
    end
    return best
end

local function dropRow(ref, name)
    local rc = center(ref)
    local v = workspace.CurrentCamera.ViewportSize
    for _, d in ipairs(labelsWhere(function(t) return t == name end)) do
        if center(d).Y > rc.Y + v.Y * 0.05 then return d end
    end
    return nil
end

-- что можно нажать в строке списка: сама строка и кружок справа
local function rowClickables(lbl)
    local list = {}
    local v = workspace.CurrentCamera.ViewportSize
    local b = realButton(lbl)
    if b:IsA("GuiButton") then list[#list + 1] = b end
    local row = lbl.Parent
    for _ = 1, 3 do
        if row and row:IsA("GuiObject") then
            local best
            for _, d in ipairs(row:GetDescendants()) do
                if d:IsA("GuiButton") and d ~= b and isVisible(d)
                    and math.abs(center(d).Y - center(lbl).Y) < v.Y * 0.03 then
                    best = d
                end
            end
            if best then
                list[#list + 1] = best
                break
            end
            row = row.Parent
        end
    end
    return list
end

-- какие редкости сейчас в списке лотов
local function listRarities()
    local c = collect()
    local counts, total = {}, 0
    for _, d in ipairs(c.buys) do
        local card = findCard(d)
        if card then
            local k = cardRarity(card)
            if k then
                counts[k] = (counts[k] or 0) + 1
                total += 1
            end
        end
    end
    return counts, total
end

local function onlyRarity(key)
    local counts, total = listRarities()
    if total == 0 then return false, counts end
    for k in pairs(counts) do
        if k ~= key then return false, counts end
    end
    return true, counts
end

-- список «Редкость» открыт? (видна строка «Редкий» ниже панели фильтров)
local function dropdownOpen()
    local r = rowRef()
    return (r and dropRow(r, "Редкий")) ~= nil
end

local function openDrop()
    if dropdownOpen() then return true end
    local h = rarityHeader(rowRef())
    if not h then return false end
    clickVerified(realButton(h), dropdownOpen, 0.8)
    return dropdownOpen()
end

local function closeDrop()
    if not dropdownOpen() then return end
    local h = rarityHeader(rowRef())
    if h then clickVerified(realButton(h), function() return not dropdownOpen() end, 0.8) end
end

-- кружок-переключатель справа в строке редкости (виден на скрине: кружки справа)
local function findRing(lbl)
    local v = workspace.CurrentCamera.ViewportSize
    local lc = center(lbl)
    local tolY = math.max(lbl.AbsoluteSize.Y * 0.6, v.Y * 0.02)
    local row = lbl.Parent
    for _ = 1, 3 do
        if row and row:IsA("GuiObject") then
            local best, bestW
            for _, d in ipairs(row:GetDescendants()) do
                if d:IsA("GuiObject") and d ~= lbl and isVisible(d) then
                    local s = d.AbsoluteSize
                    local c = center(d)
                    if s.X >= 6 and s.Y >= 6 and s.Y <= v.Y * 0.12
                        and math.abs(s.X / s.Y - 1) < 0.3
                        and math.abs(c.Y - lc.Y) < tolY
                        and c.X > lbl.AbsolutePosition.X + lbl.AbsoluteSize.X * 0.5 then
                        if not bestW or s.X > bestW then best, bestW = d, s.X end
                    end
                end
            end
            if best then return best end
            row = row.Parent
        end
    end
    return nil
end

-- "отпечаток" вида кружка без учёта цвета: включён/выключен отличаются точкой внутри
local function ringSig(ring)
    local parts = {}
    local function add(o)
        local s = o.ClassName
        if o:IsA("GuiObject") then
            s = s .. ":" .. tostring(o.Visible) .. ":" .. math.floor(o.BackgroundTransparency * 10 + 0.5)
                .. ":" .. math.floor(o.AbsoluteSize.X / 2)
        end
        if o:IsA("ImageLabel") or o:IsA("ImageButton") then
            s = s .. ":" .. o.Image .. ":" .. math.floor(o.ImageTransparency * 10 + 0.5)
        end
        if o:IsA("UIStroke") then
            s = s .. ":" .. math.floor(o.Transparency * 10 + 0.5) .. ":" .. o.Thickness
        end
        parts[#parts + 1] = s
    end
    add(ring)
    for _, d in ipairs(ring:GetDescendants()) do
        if d:IsA("GuiObject") or d:IsA("UIStroke") then add(d) end
    end
    return table.concat(parts, ";")
end

-- состояние кружков: «Оригинал» по умолчанию выключен, с ним сравниваем остальные
local function ringStates()
    local ref = rowRef()
    if not ref then return nil end
    local rows, rings, sigs = {}, {}, {}
    for _, r in ipairs(RAR) do
        local lbl = dropRow(ref, r.ru)
        if not lbl then return nil end
        local ring = findRing(lbl)
        if not ring then return nil end
        rows[r.key], rings[r.key], sigs[r.key] = lbl, ring, ringSig(ring)
    end
    local orig = dropRow(ref, "Оригинал")
    local ro = orig and findRing(orig)
    if not ro then return nil end
    local offSig = ringSig(ro)
    local on = {}
    for key, sg in pairs(sigs) do on[key] = (sg ~= offSig) end
    return on, rows, rings, sigs
end

-- выключить кружки лишних редкостей (key = nil: включить все четыре)
-- true - готово, false - не удалось нажать, nil - не смогли прочитать кружки
local function setRarityRings(key)
    for _ = 1, 7 do
        if not openDrop() then return false end
        task.wait(0.2)
        local on, rows, rings, sigs = ringStates()
        if not on then return nil end

        local target
        for _, r in ipairs(RAR) do
            local want = (key == nil) or (r.key == key)
            if on[r.key] ~= want then
                target = r.key
                break
            end
        end
        if not target then return true end

        local cands = {}
        local ring = rings[target]
        if ring:IsA("GuiButton") then cands[#cands + 1] = ring end
        local rb = realButton(rows[target])
        if rb:IsA("GuiButton") and rb ~= ring then cands[#cands + 1] = rb end
        if #cands == 0 then return nil end

        local before = sigs[target]
        local done = false
        for _, b in ipairs(cands) do
            pressRaw(b)
            local t1 = os.clock()
            repeat
                task.wait(0.1)
                if not dropdownOpen() then
                    done = true     -- список закрылся после нажатия: действие прошло
                    break
                end
                local r2 = findRing(rows[target])
                if r2 and ringSig(r2) ~= before then
                    done = true
                    break
                end
            until os.clock() - t1 > 0.7
            if done then break end
        end
        if not done then return false end
        task.wait(0.15)
    end
    return false
end

-- запасной способ: смотрим на редкости в списке лотов и нажимаем строки
local function setRarityByList(key)
    local rar = RAR_BY_KEY[key]
    local function pickRow(name)
        if not openDrop() then return false end
        local r = rowRef()
        local lbl = r and dropRow(r, name)
        if not lbl then return false end
        for _, b in ipairs(rowClickables(lbl)) do
            pressRaw(b)
            local t1 = os.clock()
            repeat
                task.wait(0.15)
                if onlyRarity(key) then return true end
            until os.clock() - t1 > 1.2
            if not openDrop() then return false end
        end
        return false
    end

    if pickRow(rar.ru) then
        closeDrop()
        return true
    end
    for _ = 1, 4 do
        local counts = listRarities()
        local other
        for k in pairs(counts) do
            if k ~= key then other = k break end
        end
        if not other then break end
        if pickRow(RAR_BY_KEY[other].ru) then
            closeDrop()
            return true
        end
    end
    closeDrop()
    return (onlyRarity(key))
end

local function setRarity(key)
    local res = setRarityRings(key)
    if res == true then
        closeDrop()
        return true
    end
    if res == false then
        closeDrop()
        return false
    end
    -- кружки прочитать не вышло
    if key == nil then
        closeDrop()
        return false
    end
    return setRarityByList(key)
end

setupMarket = function()
    if setupBusy or not S.licensed then return end
    setupBusy = true
    filterApplied = false
    local ok = pcall(function()
        setState("run", "открываю ТОРГИ...")
        if not openMarket() then
            setState("err", "ТОРГИ не открылись")
            return
        end
        task.wait(0.4)
        setState("run", "сортировка: дешёвые...")
        local sortOk = setSort()
        if S.rarity or rarityTouched then
            if S.rarity then
                setState("run", "кружки: только " .. RAR_BY_KEY[S.rarity].ru .. "...")
            else
                setState("run", "кружки: включаю все...")
            end
            local done = setRarity(S.rarity)
            if S.rarity then rarityTouched = true elseif done then rarityTouched = false end
            if done and S.rarity then filterApplied = true end
            if done then
                setState("ok", S.rarity and "фильтр готов" or "все редкости включены")
            else
                setState("warn", "кружки: проверь вручную")
            end
        else
            setState(sortOk and "ok" or "warn", sortOk and "рынок готов" or "выбери сортировку сам")
        end
    end)
    setupBusy = false
    if not ok then setState("err", "настройка рынка: сбой") end
end

---------------------------------------------------------------- ГЛАВНЫЙ ЦИКЛ
local dead = {}
local lastTry = setmetatable({}, { __mode = "k" })
local lastListClick, lastConfirm, lastClose, errAt, backoffUntil = 0, 0, 0, 0, 0
local confirmFails = 0
local modalSince
local soldCounted = false
local lastPrice
local lastErrObj

local function isDead(price, now)
    return dead[price] and dead[price] > now
end

local function anyModal()
    local c = collect()
    return c.market or c.confirm or c.soldTitle
end

local function modalGone()
    return not anyModal()
end

-- "подпись" состояния окна лота: если после нажатия она изменилась, значит нажатие сработало
local function modalSig(c)
    return table.concat({
        c.market and "m" or "-", c.confirm and "c" or "-", c.cancel and "x" or "-",
        c.checking and "p" or "-", c.raffle and "r" or "-", c.soldTitle and "s" or "-",
        c.err and "e" or "-", c.confirm and c.confirm.Text or "",
    })
end

-- закрыть окно лота (ОТМЕНА или крестик окна лота)
local function closeModal(c)
    if os.clock() - lastClose < 0.5 then return false end
    local btn = c.cancel
    if not btn then
        local ref = c.soldTitle or c.market or c.confirm
        if ref then btn = findClose(ref) end
    end
    if not btn then
        lastClose = os.clock()
        setState("err", "не нашёл крестик окна")
        return false
    end
    local ok = clickVerified(btn, modalGone, 0.6)
    lastClose = os.clock()
    return ok
end

local function tick()
    local c = collect()
    local now = os.clock()
    local lo, hi = limits()

    if c.slow then backoffUntil = now + 1.2 end

    -- РЕЗУЛЬТАТ: «ПРОДАН» -> кто купил, закрыть окно лота, идти дальше
    if c.soldTitle then
        modalSince = nil
        confirmFails = 0
        if not soldCounted then
            soldCounted = true
            if now - lastConfirm < 30 or now - lastListClick < 30 then
                local info = c.soldInfo or ""
                local mine = info:find(lp.Name, 1, true)
                if not mine and lp.DisplayName ~= "" then mine = info:find(lp.DisplayName, 1, true) end
                if lastPrice then dead[lastPrice] = now + 25 end
                if mine then
                    S.won += 1
                    if S.sell > 0 and lastPrice then
                        S.earn += netOf(S.sell) - lastPrice
                    end
                    setState("ok", "куплено тобой!")
                else
                    S.lost += 1
                    setState("warn", "купили другие")
                end
                updStats()
            end
        end
        if now - lastClose > 0.4 then
            local cb = findClose(c.soldTitle)
            if cb then
                local ok = clickVerified(cb, function() return not collect().soldTitle end, 0.6)
                lastClose = os.clock()
                if not ok then setState("err", "крестик не жмётся " .. traceStr()) end
            else
                lastClose = os.clock()
                setState("err", "не нашёл крестик окна")
            end
        end
        return
    end
    soldCounted = false

    -- ОКНО ЛОТА
    if c.market or c.confirm then
        modalSince = modalSince or now

        -- ошибка: закрыть окно лота, пропустить лот
        if c.err and (c.err ~= lastErrObj or now - errAt > 4) and now - errAt > 1.5 and now - lastConfirm < 8 then
            errAt = now
            lastErrObj = c.err
            if lastPrice then dead[lastPrice] = now + 15 end
            confirmFails = 0
            setState("warn", "ошибка, закрываю")
            closeModal(c)
            return
        end

        if c.confirm then
            local price = digits(norm(c.confirm.Text))
            if price then lblLot.Text = short(price) end
            if price and isDead(price, now) then
                closeModal(c)
                return
            end
            if price and price >= lo and price <= hi then
                if now >= backoffUntil and now - lastConfirm > 0.5 then
                    if confirmFails >= 3 then
                        dead[price] = now + 15
                        confirmFails = 0
                        setState("warn", "не вышло, закрываю")
                        closeModal(c)
                        return
                    end
                    lastPrice = price
                    local before = modalSig(c)
                    local label = c.cancel and "подтверждение" or "2-е подтверждение"
                    local ok = clickVerified(realButton(c.confirm), function()
                        return modalSig(collect()) ~= before
                    end, 0.7)
                    lastConfirm = os.clock()
                    if ok then
                        confirmFails = 0
                        setState("run", label .. mtag())
                    else
                        confirmFails += 1
                        setState("warn", "не жмётся " .. traceStr())
                    end
                end
            else
                setState("warn", "цена вне диапазона")
            end
        else
            if c.checking then
                setState("run", "проверка...")
            elseif c.raffle then
                setState("run", "розыгрыш...")
            else
                setState("run", "жду окно...")
            end
        end

        -- окно зависло после нашей покупки
        if c.market and now - lastListClick < 40 and now - modalSince > 18 then
            if closeModal(c) then
                modalSince = nil
                setState("warn", "окно зависло, закрыл")
            end
        end
        return
    end
    modalSince = nil
    confirmFails = 0

    -- СПИСОК ЛОТОВ
    if c.err and now - errAt > 1.5 and now - lastListClick < 4 then
        errAt = now
        lastErrObj = c.err
        if lastPrice then dead[lastPrice] = now + 12 end
    end
    if #c.buys == 0 then
        setState("warn", "открой ЛОТЫ")
        return
    end
    if now - lastListClick < 1.0 or now < backoffUntil then return end

    local seen, inRange, unk, minSeen = 0, 0, 0, nil
    for _, d in ipairs(c.buys) do
        local card, price = findCard(d)
        if card and price then
            seen += 1
            if not minSeen or price < minSeen then minSeen = price end
            if price >= lo and price <= hi and not isDead(price, now) then
                local okRar = true
                if S.rarity then
                    local k = cardRarity(card)
                    if k then detectOk = true else unk += 1 end
                    okRar = (k == S.rarity) or (k == nil and (filterApplied or not detectOk))
                end
                if okRar then
                    inRange += 1
                    if not lastTry[card] or now - lastTry[card] > 1.5 then
                        lastTry[card] = now
                        local ok = clickVerified(realButton(d), anyModal, 0.6)
                        lastListClick = os.clock()
                        lastPrice = price
                        if ok then
                            setState("run", "открыл " .. short(price) .. mtag())
                        else
                            dead[price] = os.clock() + 4
                            setState("warn", "клик " .. traceStr())
                        end
                        return
                    end
                end
            end
        end
    end
    lblLot.Text = minSeen and short(minSeen) or "-"
    if seen == 0 then
        setState("warn", "кнопок " .. #c.buys .. ", цен нет")
    else
        setState("run", "лотов " .. seen .. ", цель " .. inRange .. (unk > 0 and not filterApplied and " ?" or ""))
    end
end

---------------------------------------------------------------- ЗАПУСК
startBtn.MouseButton1Click:Connect(function()
    if not S.licensed then return end
    S.enabled = not S.enabled
    if S.enabled then
        dead = {}
        confirmFails = 0
        modalSince = nil
        if S.rarity and not setupBusy then
            task.spawn(function() if setupMarket then setupMarket() end end)
        end
    end
    refreshToggle()
end)

refreshSpeed()
refreshChips()
refreshTabs()
refreshLimits()
updStats()
refreshToggle()

-- заставка на весь экран -> проверка ключа -> меню
main.Visible = false
task.spawn(function()
    showSplash()
    if not gui.Parent then return end
    -- сохранённый ключ ещё действует?
    local sk, st = readSaved()
    if sk and st and KEYS[sk] then
        S.licensed = true
        S.keyExpire = math.huge
    end
    if not S.licensed then
        if not showKeyScreen() then
            alive = false
            if gui.Parent then gui:Destroy() end
            return
        end
    end
    lblKey.Text = S.keyExpire == math.huge and "∞" or fmtLeft(S.keyExpire - os.time())
    main.Visible = true
    tw(mainScale, OPEN, { Scale = 1 })
    tw(main, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { GroupTransparency = 0 })
end)

-- срок ключа: обновляем остаток, по окончании просим новый ключ
task.spawn(function()
    while alive do
        task.wait(5)
        if S.licensed and S.keyExpire and S.keyExpire ~= math.huge then
            local left = S.keyExpire - os.time()
            if left <= 0 then
                S.licensed = false
                S.enabled = false
                refreshToggle()
                main.Visible = false
                bubble.Visible = false
                if showKeyScreen() then
                    lblKey.Text = fmtLeft(S.keyExpire - os.time())
                    main.Visible = true
                else
                    alive = false
                    if gui.Parent then gui:Destroy() end
                    return
                end
            else
                lblKey.Text = fmtLeft(left)
            end
        end
    end
end)

task.spawn(function()
    while alive do
        if S.licensed and S.enabled and not setupBusy then
            pcall(tick)
            task.wait(S.interval)
        else
            task.wait(0.25)
        end
    end
end)
