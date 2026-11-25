-- Nameplates: auras on enemies. The first crowd control from anyone, then up to three
-- of your own debuffs (your pet's and totems' too), with the game's countdown numbers.
local _, NP = ...
local db = NP.db
local M = {}
table.insert(NP.modules, M)

local MOST = 4
local slots = {}  -- one fill table for the whole addon (### C_UnitAuras.GetAuraSlots)

local function Done(cd) M.Draw(cd.p) end

function M.Layout(p, k)
    if not p.auras then
        p.auras = NP.Icons(p, MOST, Done)
        for _, f in ipairs(p.auras.icons) do
            f.cd:SetDrawSwipe(false)  -- only the numbers
            f.cd:SetCountdownAbbrevThreshold(60)
            f.count = f:CreateFontString(nil, "OVERLAY")
            f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 1)
        end
    end
    NP.PlaceRow(p, p.auras, 20 * k, NP.AuraY(), k)
    for _, f in ipairs(p.auras.icons) do f.count:SetFont(STANDARD_TEXT_FONT, 9 * k, "OUTLINE") end
end

-- One icon, written only when its aura or its timing changed.
local function Put(f, id, icon, count, duration, expires)
    if f.id ~= id or f.expires ~= expires or f.icon ~= icon then
        f.id, f.expires, f.icon = id, expires, icon
        f.texture:SetTexture(icon)
        if duration > 0 and expires > 0 then f.cd:SetCooldown(expires - duration, duration) else f.cd:Clear() end
    end
    count = (count or 0) > 1 and count or ""
    if f.n ~= count then f.n = count; f.count:SetText(count) end
    f:Show()
end

-- Not without an icon (tracking), not when it ran out; 0 is "until cancelled".
local function Live(icon, expires, now) return icon and (expires == 0 or expires > now) end

-- On ADDED and each UNIT_AURA_DELTA (one per unit per frame): one CC lookup and one
-- slot walk, no table made. Only an aura we show writes, so another player's does not.
function M.Draw(p)
    local icons, unit, n = p.auras.icons, p.unit, 0
    if db.auras and unit and p.enemy then
        local now, A = GetTime(), C_UnitAuras
        local _, icon, count, _, duration, expires, _, _, _, _, _, _, _, _, _, cc = A.UnitAura(unit, 1, "HARMFUL|CROWD_CONTROL")
        if Live(icon, expires, now) then
            n = 1
            Put(icons[1], cc, icon, count, duration, expires)
        end
        local _, found = A.GetAuraSlots(unit, "HARMFUL|PLAYER", nil, nil, slots)
        local last = n + 3
        for i = 1, found do
            if n == last then break end
            local _, icon, count, _, duration, expires, _, _, _, _, _, _, _, _, _, id = A.UnitAuraBySlot(unit, slots[i])
            if not (cc and id == cc) and Live(icon, expires, now) then
                n = n + 1
                Put(icons[n], id, icon, count, duration, expires)
            end
        end
    end
    for i = n + 1, MOST do
        local f = icons[i]
        if f:IsShown() then f.id, f.icon = nil, nil; f.cd:Clear(); f:Hide() end
    end
    p.auras:SetWidth(n * p.auras.step)
end

local events = CreateFrame("Frame")
function M.Setup() NP.Listen(events, db.auras, "UNIT_AURA_DELTA") end
events:SetScript("OnEvent", function(_, _, unit)
    local p = NP.byToken[unit]
    if p then M.Draw(p) end
end)
