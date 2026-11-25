-- Nameplates: cast bars under the plates, and the cooldowns enemy players were seen
-- using, above the auras. ### UNIT_SPELLCAST_* events fire for plate tokens; a cast
-- has timing only from a start the client saw.
local _, NP = ...
local db = NP.db
local M = {}
table.insert(NP.modules, M)

local SHOWN, SIZE = 5, 22
local Direction, IMMEDIATE = Enum.StatusBarTimerDirection, Enum.StatusBarInterpolation.Immediate
local UP = Enum.NumericRuleFormatRounding.Up

-- "~": GetSpellBaseCooldown counts no talent and no item (### GetSpellBaseCooldown).
local FORMAT = C_StringUtil.CreateNumericRuleFormatter()
FORMAT:SetBreakpoints({
    { threshold = 0, step = 1, rounding = UP, format = "~%d" },
    { threshold = 60, format = "~%dm", components = { { div = 60, step = 1, rounding = UP } } },
})

local Row
local function Done(cd) Row(cd.p) end

-- A tooltip border round the bar and round the icon, in the bar's colour.
local EDGE = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local function Edged(bar)
    local f = CreateFrame("Frame", nil, bar)
    f:SetFrameLevel(bar:GetFrameLevel())
    f:SetBackdrop(EDGE)
    return f
end

local function Make(p)
    local bar = CreateFrame("StatusBar", nil, p.frame)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetTexture(0, 0, 0, 0.6)
    bar.edge = Edged(bar)
    bar.edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -3, 3)
    bar.edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 3, -3)
    bar.box = Edged(bar)
    bar.box:SetPoint("RIGHT", bar, "LEFT", 0, 0)
    bar.icon = bar.box:CreateTexture(nil, "ARTWORK")
    bar.icon:SetPoint("CENTER", bar.box, "CENTER", 0, 0)
    bar.spark = bar:CreateTexture(nil, "OVERLAY")  -- rides the fill's edge
    bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.spark:SetBlendMode("ADD")
    bar.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar:Hide()
    p.cast, p.span = bar, C_DurationUtil.CreateDuration()
    p.cds = NP.Icons(p, SHOWN, Done)
    for _, f in ipairs(p.cds.icons) do f.cd:SetCountdownFormatter(FORMAT) end
end

function M.Layout(p, k)
    if not p.cast then Make(p) end
    local bar = p.cast
    bar:ClearAllPoints()  -- the icon's box fits under the plate, left of the bar
    bar:SetPoint("TOPLEFT", p.bar, "BOTTOMLEFT", 19 * k, -3 * k)
    bar:SetPoint("TOPRIGHT", p.bar, "BOTTOMRIGHT", -3 * k, -3 * k)
    bar:SetHeight(10 * k)
    bar.box:SetWidth(18 * k); bar.box:SetHeight(18 * k)
    bar.icon:SetWidth(12 * k); bar.icon:SetHeight(12 * k)
    bar.spark:SetWidth(20 * k); bar.spark:SetHeight(20 * k)
    bar.text:SetFont(STANDARD_TEXT_FONT, math.max(7, 9 * k), "OUTLINE")
    NP.PlaceRow(p, p.cds, SIZE * k, NP.AuraY() + 20 + 8, k)  -- over the auras, 8 px between
end

-- Grey when no interrupt you know can stop it (### C_Spell.UnitCastingInfo).
local function Color(p, locked)
    local bar, r, g, b = p.cast, 1, 0.8, 0
    if locked then r, g, b = 0.6, 0.6, 0.6 end
    bar:SetStatusBarColor(r, g, b)
    bar.edge:SetBackdropBorderColor(r, g, b)
    bar.box:SetBackdropBorderColor(r, g, b)
end

-- One timer at the earliest end among the bars up, for a STOP the client never got.
local timer, timerAt
local Watch
local function Hide(p) p.castEnd = nil; p.cast:Hide() end
local function Expire()
    timer = nil
    local now = GetTime()
    for _, p in pairs(NP.byToken) do
        if p.castEnd and p.castEnd <= now then Hide(p) end
    end
    Watch()
end
function Watch()
    local soonest
    for _, p in pairs(NP.byToken) do
        if p.castEnd and (not soonest or p.castEnd < soonest) then soonest = p.castEnd end
    end
    if timer and timerAt == soonest then return end
    if timer then timer:Cancel(); timer = nil end
    if soonest then
        timerAt = soonest
        timer = C_Timer.NewTimer(math.max(soonest - GetTime(), 0) + 0.5, Expire)
    end
end
local function Stop(p)
    if p.castEnd then Hide(p); Watch() end
end

-- The bar fills by itself (### statusBar:SetTimerDuration); a channel empties.
local function Cast(p)
    local unit, channel = p.unit, false
    local name, _, icon, from, to, _, _, locked = C_Spell.UnitCastingInfo(unit)
    if not name then
        channel = true
        name, _, icon, from, to, _, locked = C_Spell.UnitChannelInfo(unit)
    end
    if not (db.casts and name and from and to) then return Stop(p) end
    local bar = p.cast
    p.span:SetTimeSpan(from / 1000, to / 1000)
    bar:SetTimerDuration(p.span, IMMEDIATE, channel and Direction.RemainingTime or Direction.ElapsedTime)
    bar.icon:SetTexture(icon)
    bar.text:SetText(name)
    Color(p, locked)
    bar:Show()
    p.castEnd = to / 1000
    Watch()
end

-- Enemy cooldowns, kept in memory by GUID (128 units, 16 spells each), newest first.
local seen, units = {}, 0
local spells, known = {}, 0  -- spellID -> { name, icon, duration } or false, 256 at most

local function Spell(id)
    local info = spells[id]
    if info == nil then
        if known >= 256 then table.wipe(spells); known = 0 end
        local ms = GetSpellBaseCooldown(id)
        local data = ms and ms >= 5000 and ms <= 1800000 and C_Spell.GetSpellInfo(id)
        info = data and { name = data.name, icon = data.iconID, duration = ms / 1000 } or false
        spells[id], known = info, known + 1
    end
    return info
end

local function Used(p, spellID)
    local info = p.player and p.enemy and p.guid and Spell(spellID)
    if not info then return end
    local list, now, entry = seen[p.guid], GetTime()
    if not list then
        if units >= 128 then table.wipe(seen); units = 0 end
        list, units = {}, units + 1
        seen[p.guid] = list
    end
    for i, e in ipairs(list) do
        if e.info.name == info.name then  -- another rank of it too
            entry = table.remove(list, i)
            break
        end
    end
    if not entry and #list == 16 then entry = table.remove(list) end
    entry = entry or {}
    entry.info, entry.start = info, now
    table.insert(list, 1, entry)
    Row(p)
end

function Row(p)
    local row, list, n = p.cds, p.unit and db.cooldowns and seen[p.guid], 0
    if list then
        local now = GetTime()
        for i = #list, 1, -1 do
            if list[i].start + list[i].info.duration <= now then table.remove(list, i) end
        end
        n = math.min(#list, SHOWN)
        for i = 1, n do
            local e, f = list[i], row.icons[i]
            if f.start ~= e.start or f.info ~= e.info then
                f.start, f.info = e.start, e.info
                f.texture:SetTexture(e.info.icon)
                f.cd:SetCooldown(e.start, e.info.duration)
            end
            f:Show()
        end
    end
    for i = n + 1, SHOWN do
        local f = row.icons[i]
        if f:IsShown() then f.start, f.info = nil, nil; f:Hide() end
    end
    row:SetWidth(n * row.step)
end

function M.Draw(p)
    Cast(p)
    Row(p)
end
M.Clear = Stop
function M.Enter() table.wipe(seen); units = 0 end

local events = CreateFrame("Frame")
local LOCK = { "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }
function M.Setup()
    NP.Listen(events, db.casts, "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP")
    -- Every spell that goes off, channels too (after CHANNEL_START, ### UNIT_SPELLCAST_*).
    NP.Listen(events, db.cooldowns, "UNIT_SPELLCAST_SUCCEEDED")
    -- They fire for target and focus only.
    for _, e in ipairs(LOCK) do
        if db.casts then events:RegisterUnitEvent(e, "target") else events:UnregisterEvent(e) end
    end
end

events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if unit == "target" then
        local p = NP.TargetParts()
        if p and p.castEnd then Color(p, event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE") end
        return
    end
    local p = NP.byToken[unit]
    if not p then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then Used(p, spellID)
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then Cast(p)
    else Stop(p) end
end)
