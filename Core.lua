-- Nameplates: the game's own nameplates, made readable. Core: the saved table,
-- the page in ClassicAPI's Settings window (AddOn Options, or /fnp), the plate
-- size, and which plate frame shows which unit. Plate.lua, Auras.lua and
-- Casts.lua draw their parts on a plate. Doc headings are ClassicAPI's docs/API.md.
if not CLASSIC_API_VERSION then error("Nameplates needs ClassicAPI.", 0) end

local _, NP = ...
NameplatesDB = NameplatesDB or {} -- restored first: LoadSavedVariablesFirst
local db = NameplatesDB
NP.db = db

local function Percent(value) return string.format("%d%%", value) end

-- The page in play order: a section header, or { key, label, tip, default, kind, ... }.
-- kind: nil is a switch; "slider" takes min, max, step and a label formatter.
local PAGE = {
    "Plates",
    { "size", "Plate size", "Every plate: its bar, its level and the area that takes clicks.", 90, "slider", 50, 200, 5, Percent },
    { "followUI", "Follow UI scale", "Plates grow and shrink with the interface scale.", true },
    { "classColors", "Class colours", "A player's plate has a bar in the class colour.", true },
    { "health", "Health text", "The health value in the bar, on every plate.", true },
    "Target",
    { "glow", "Target glow", "Your target's plate glows around its border.", true },
    { "targeting", "Targeting you", "A hostile NPC whose target is you says so under its bar.", true },
    { "combo", "Combo points", "Five pips above your target's name.", true, "combo" },
    "Raid marks",
    { "marks", "Move raid marks", "The mark at the size and place below. Off: the game's own mark.", true },
    { "markSize", "Mark size", "At plate size 100%.", 30, "slider", 12, 40, 1 },
    { "markPlace", "Mark place", "Where the mark sits on the plate.", "ABOVE", "place" },
    "Auras and casts",
    { "auras", "Auras", "On enemies: up to three of your debuffs and the first crowd control, with the time left.", true },
    { "casts", "Cast bars", "Under the plate; grey when you cannot interrupt the cast.", true },
    { "cooldowns", "Enemy cooldowns", "Abilities an enemy player was seen using. The ~ countdown is the base cooldown: talents and items are not counted.", true },
}

-- Fill the defaults now (the plates start before the window registers the page), and
-- clear every saved key no row owns (KNOWN_PATTERNS KP-64); BaseSize's two are kept.
local owned = { baseWidth = true, baseHeight = true }
for _, row in ipairs(PAGE) do
    if type(row) == "table" then
        owned[row[1]] = true
        if db[row[1]] == nil then db[row[1]] = row[4] end
    end
end
for key in pairs(db) do if not owned[key] then db[key] = nil end end

function NP.ComboClass()
    local _, class = UnitClass("player")
    return class == "ROGUE" or class == "DRUID"
end

local function Places()
    local places = Settings.CreateControlTextContainer()
    places:Add("LEFT", "Left of the bar")
    places:Add("ABOVE", "Above the name")
    places:Add("RIGHT", "Right of the level")
    return places:GetData()
end
local function Marking() return db.marks end

local category
SettingsRegistrar:AddRegistrant(function()
    local layout, marksRow
    category, layout = Settings.RegisterVerticalLayoutCategory("Nameplates")
    for _, row in ipairs(PAGE) do
        if type(row) == "string" then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(row))
        elseif row[5] ~= "combo" or NP.ComboClass() then
            local key, kind = row[1], row[5]
            local varType = kind == "slider" and Settings.VarType.Number
                or kind == "place" and Settings.VarType.String or Settings.VarType.Boolean
            local setting = Settings.RegisterAddOnSetting(category, "Nameplates_" .. key, key, db, varType, row[2], row[4])
            setting:SetValueChangedCallback(NP.Refresh)
            local made
            if kind == "slider" then
                local options = Settings.CreateSliderOptions(row[6], row[7], row[8])
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, row[9])
                made = Settings.CreateSlider(category, setting, options, row[3])
            elseif kind == "place" then
                made = Settings.CreateDropdown(category, setting, Places, row[3])
            else
                made = Settings.CreateCheckbox(category, setting, row[3])
            end
            if key == "marks" then marksRow = made end
            if key == "markSize" or key == "markPlace" then made:SetParentInitializer(marksRow, Marking) end
        end
    end
    Settings.RegisterAddOnCategory(category)
end)

SLASH_NAMEPLATES1 = "/fnp"
SlashCmdList.NAMEPLATES = function()
    if category then Settings.OpenToCategory(category:GetID()) end
end

-- The plates. ### frame:RegisterUnitEvent: nameplate1 to nameplate150 in one call.
local TOKENS = {}
for i = 1, 150 do TOKENS[i] = "nameplate" .. i end
NP.byToken = {}   -- "nameplateN" -> the parts of the plate that shows it
local parts = {}  -- plate frame -> its parts; the game reuses its frames, so each is read once
NP.modules = {}   -- each: Setup(), Layout(p, k), Draw(p), and Clear(p) if it keeps state
NP.gen = 0        -- bumped by every Refresh, so a plate that comes back is laid out again

-- Plate-token events for UNIT_*, plain ones for the rest; `on` false unregisters.
function NP.Listen(frame, on, ...)
    for i = 1, select("#", ...) do
        local e = select(i, ...)
        if not on then frame:UnregisterEvent(e)
        elseif string.find(e, "^UNIT_") then frame:RegisterUnitEvent(e, unpack(TOKENS))
        else frame:RegisterEvent(e) end
    end
end

-- ### Reading region content from a default nameplate. The order held in play since
-- 2026-10: border, glow, name, level, skull, raid icon. Read, never moved or re-fonted
-- (moving them crashed the client, 2026-10-22).
local function Parts(frame)
    local p = parts[frame]
    if p then return p end
    local bar = frame:GetChildren()
    if not bar then return end
    local border, _, name, level, _, raid = frame:GetRegions()
    p = { frame = frame, bar = bar, border = border, name = name, level = level, raid = raid }
    parts[frame] = p
    return p
end

-- Above the name, bottom up: combo pips, the mark when it sits above, the auras, then
-- the enemy cooldowns. The aura row's height over the name, before the size factor.
function NP.AuraY()
    return (db.marks and db.markPlace == "ABOVE" and db.markSize + 4 or 0) + 10
end

function NP.TargetParts()
    local frame = C_NamePlate.GetNamePlateForUnit("target")
    local p = frame and parts[frame]
    if p and p.unit then return p end
end

-- A row of icons over the name, made once per plate frame; each icon's Cooldown calls
-- `done` at its end (CLASSICAPI_MASTER_REFERENCE.md "Cooldown API").
function NP.Icons(p, n, done)
    local row = CreateFrame("Frame", nil, p.frame)
    row.icons = {}
    for i = 1, n do
        local f = CreateFrame("Frame", nil, row)
        f.texture = f:CreateTexture(nil, "ARTWORK")
        f.texture:SetAllPoints(f)
        f.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.cd = CreateFrame("Cooldown", nil, f)
        f.cd:SetAllPoints(f)
        f.cd:SetDrawBling(false)
        f.cd:SetScript("OnCooldownDone", done)
        f.cd.p = p
        f:Hide()
        row.icons[i] = f
    end
    return row
end

-- The row `y` over the name, its icons `size` wide; y and the gap scale with k.
function NP.PlaceRow(p, row, size, y, k)
    row.step = size + 2 * k
    row:SetHeight(size)
    row:ClearAllPoints()
    row:SetPoint("BOTTOM", p.name, "TOP", 0, y * k)
    for i, f in ipairs(row.icons) do
        f:SetWidth(size); f:SetHeight(size)
        f:ClearAllPoints()
        f:SetPoint("LEFT", row, "LEFT", (i - 1) * row.step, 0)
    end
end

function NP.Draw(p)
    local unit = p.unit
    p.enemy = UnitCanAttack("player", unit)
    p.player = UnitIsPlayer(unit)
    if p.gen ~= NP.gen then
        p.gen = NP.gen
        for _, m in ipairs(NP.modules) do m.Layout(p, NP.k) end
    end
    for _, m in ipairs(NP.modules) do m.Draw(p) end
end

local function Added(token)
    local frame = C_NamePlate.GetNamePlateForUnit(token)
    local p = NP.k and frame and Parts(frame)  -- before the first loading screen: drawn there
    if not p then return end
    p.unit, p.guid = token, UnitGUID(token)
    NP.byToken[token] = p
    NP.Draw(p)
end

local function Removed(token)
    local p = NP.byToken[token]
    NP.byToken[token] = nil
    if not p or p.unit ~= token then return end
    p.unit = nil
    for _, m in ipairs(NP.modules) do if m.Clear then m.Clear(p) end end
end

-- GAP: a DLL should give the default plate size (GetNamePlateSize returns ours after
-- the first SetNamePlateSize of a game session). Read once, while none is saved.
local function BaseSize()
    if not db.baseWidth then db.baseWidth, db.baseHeight = C_NamePlate.GetNamePlateSize() end
    return db.baseWidth, db.baseHeight
end

-- ### C_NamePlate.SetNamePlateSize: one call sizes every plate, its bar, its level and
-- its click area. UNVERIFIED: whether "UI units" already hold the UI scale (then Follow
-- counts it twice), and whether the border and skull follow; the first play shows it.
local function Resize()
    NP.k = db.size / 100 * (db.followUI and UIParent:GetScale() or 1)
    local w, h = BaseSize()
    C_NamePlate.SetNamePlateSize(w * NP.k, h * NP.k)
end

local events = CreateFrame("Frame")
local started

-- At the first loading screen and on every setting change: size, events, every plate.
function NP.Refresh()
    if not started then return end
    Resize()
    NP.gen = NP.gen + 1
    NP.Listen(events, db.followUI, "UI_SCALE_CHANGED")
    for _, m in ipairs(NP.modules) do m.Setup() end
    for _, p in pairs(NP.byToken) do NP.Draw(p) end
end

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
NP.Listen(events, true, "UNIT_FACTION")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then Added(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then Removed(unit)
    elseif event == "UNIT_FACTION" then
        local p = NP.byToken[unit]
        if p then NP.Draw(p) end
    elseif event == "UI_SCALE_CHANGED" then NP.Refresh()
    else
        -- A loading screen: every plate is new. The plates up now (a /reload) are drawn.
        for _, m in ipairs(NP.modules) do if m.Enter then m.Enter() end end
        for token in pairs(NP.byToken) do Removed(token) end
        if not started then started = true; NP.Refresh() end
        for i = 1, 150 do
            if UnitExists(TOKENS[i]) then Added(TOKENS[i]) end
        end
    end
end)
