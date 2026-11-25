-- Nameplates: what a plate shows of its unit. The class bar and the health text,
-- the target glow, "Targeting you", combo points and the raid mark.
local _, NP = ...
local db = NP.db
local M = {}
table.insert(NP.modules, M)

local FONT, BAR = STANDARD_TEXT_FONT, "Interface\\TargetingFrame\\UI-StatusBar"
local TARGET_OF = {}  -- "nameplateN" -> "nameplateNtarget" (### Unit tokens: token chains)
for i = 1, 150 do TARGET_OF["nameplate" .. i] = "nameplate" .. i .. "target" end

-- Our parts, made once per plate frame. `top` lies one level over the class bar, so
-- the text and pips draw above it. None of them calls SetAlpha: they fade with the
-- plate (CLASSICAPI_MASTER_REFERENCE.md, "Nameplate alpha").
local function Make(p)
    local top = CreateFrame("Frame", nil, p.bar)
    top:SetAllPoints(p.bar)
    top:SetFrameLevel(p.bar:GetFrameLevel() + 2)
    p.top = top
    p.health = top:CreateFontString(nil, "OVERLAY")
    p.health:SetPoint("CENTER", p.bar, "CENTER", 0, 0)
    p.glow = top:CreateTexture(nil, "OVERLAY")
    p.glow:SetTexture("Interface\\Tooltips\\Nameplate-Glow")
    p.glow:SetBlendMode("ADD")
    p.glow:SetAllPoints(p.border)
    p.targeting = top:CreateFontString(nil, "OVERLAY")
    p.targeting:SetTextColor(1, 0.4, 0.25)
    p.combo = {}
    for i = 1, 5 do
        p.combo[i] = top:CreateTexture(nil, "OVERLAY")
        p.combo[i]:SetTexture(1, 0.75, 0.15, 1)
    end
    p.mark = top:CreateTexture(nil, "OVERLAY")
    p.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
end

function M.Layout(p, k)
    if not p.top then Make(p) end
    p.health:SetFont(FONT, 9 * k, "OUTLINE")
    p.targeting:SetFont(FONT, 9 * k, "OUTLINE")
    p.targeting:SetText("Targeting you")  -- after its font: the client refuses text before one
    p.targeting:ClearAllPoints()
    p.targeting:SetPoint("TOP", p.bar, "BOTTOM", 0, -(db.casts and 15 or 4) * k)
    for i = 1, 5 do
        local pip = p.combo[i]
        pip:SetWidth(6 * k); pip:SetHeight(6 * k)
        pip:ClearAllPoints()
        pip:SetPoint("BOTTOM", p.name, "TOP", (i - 3) * 9 * k, 2 * k)
    end
    local mark, size, place = p.mark, db.markSize * k, db.markPlace
    mark:SetWidth(size); mark:SetHeight(size)
    mark:ClearAllPoints()
    if place == "LEFT" then mark:SetPoint("RIGHT", p.bar, "LEFT", -4 * k, 0)
    elseif place == "RIGHT" then mark:SetPoint("LEFT", p.level, "RIGHT", 4 * k, 0)
    else mark:SetPoint("BOTTOM", p.name, "TOP", 0, 10 * k) end
end

-- GAP: a DLL should colour a default plate's bar by class (a cvar, as retail's
-- ShowClassColorInNameplate, or keep a colour an addon writes): the engine recolours
-- its own bar on its own updates (KNOWN_PATTERNS KP-32), so players get a bar of ours.
local function ClassBar(p)
    local _, class = UnitClass(p.unit)
    local color = db.classColors and p.player and class and RAID_CLASS_COLORS[class]
    local bar = p.classBar
    if not color then
        if bar then bar:Hide() end
        return
    end
    if not bar then
        bar = CreateFrame("StatusBar", nil, p.bar)
        bar:SetAllPoints(p.bar)
        bar:SetStatusBarTexture(BAR)
        p.classBar = bar
    end
    bar:SetStatusBarColor(color.r, color.g, color.b)
    bar:Show()
end

-- Most servers send other units' health as a percent (max 100): then it reads "72%".
local function Health(p)
    local hp, max = UnitHealth(p.unit), UnitHealthMax(p.unit)
    if hp == p.hp and max == p.max then return end
    p.hp, p.max = hp, max
    if p.classBar then
        p.classBar:SetMinMaxValues(0, max > 0 and max or 1)
        p.classBar:SetValue(hp)
    end
    if db.health and max > 0 then
        p.health:SetText(max == 100 and math.floor(hp) .. "%" or AbbreviateNumbers(hp))
        p.health:Show()
    else
        p.health:Hide()
    end
end

local function IsTarget(p) return p.unit and UnitIsUnit(p.unit, "target") end

local function Glow(p) p.glow:SetShown(db.glow and IsTarget(p)) end

local function Combo(p)
    local n = db.combo and NP.ComboClass() and IsTarget(p) and GetComboPoints("player", "target") or 0
    for i = 1, 5 do p.combo[i]:SetShown(i <= n) end
end

local function Targeting(p)
    local unit = p.unit
    p.targeting:SetShown(db.targeting and unit and p.enemy and not p.player
        and UnitIsUnit(TARGET_OF[unit], "player"))
end

-- Our mark (SetRaidTargetIconTexture, FrameXML TargetFrame.lua); the game's own is
-- hidden by alpha while ours is on. UNVERIFIED: that the engine leaves that alpha alone.
local function Mark(p)
    local index = db.marks and GetRaidTargetIndex(p.unit)
    if p.raid then
        local alpha = db.marks and 0 or 1
        if p.raid:GetAlpha() ~= alpha then p.raid:SetAlpha(alpha) end
    end
    if index then SetRaidTargetIconTexture(p.mark, index) end
    p.mark:SetShown(index)
end

local shownTarget  -- the plate that has the glow and the pips

function M.Draw(p)
    if IsTarget(p) then shownTarget = p end
    p.hp = nil
    ClassBar(p)
    Health(p)
    Glow(p)
    Combo(p)
    Targeting(p)
    Mark(p)
end

local events = CreateFrame("Frame")

local function Target()
    local p = NP.TargetParts()
    if shownTarget and shownTarget ~= p then Glow(shownTarget); Combo(shownTarget) end
    shownTarget = p
    if p then Glow(p); Combo(p) end
end

function M.Setup()
    NP.Listen(events, db.classColors or db.health, "UNIT_HEALTH", "UNIT_MAXHEALTH")
    NP.Listen(events, db.glow or db.combo, "PLAYER_TARGET_CHANGED")
    NP.Listen(events, db.targeting, "UNIT_TARGET")
    NP.Listen(events, db.combo and NP.ComboClass(), "PLAYER_COMBO_POINTS")
    NP.Listen(events, db.marks, "RAID_TARGET_UPDATE")
    shownTarget = nil
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then Target()
    elseif event == "PLAYER_COMBO_POINTS" then
        if shownTarget then Combo(shownTarget) end
    elseif event == "RAID_TARGET_UPDATE" then
        for _, p in pairs(NP.byToken) do Mark(p) end
    else
        local p = NP.byToken[unit]
        if not p then return end
        if event == "UNIT_TARGET" then Targeting(p) else Health(p) end
    end
end)

