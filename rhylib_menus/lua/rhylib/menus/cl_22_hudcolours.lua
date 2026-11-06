--[[
    Settings > HUD colours (client): players recolour the HUD by meaning
    (colour blindness). Only with the HUD colours API in core
    (Rhylib.UI.HUD_KEYS, cl_11_theme.lua).

    The group (right after HUD; Menus.SettingGroupTop with ownRows, so the
    group draws this page instead of plain rows):
      - a live preview: a small HUD in the current colours over a sky and
        ground backdrop inside a black visor frame (armour and health
        ladders, the visor rim and compass, stamina lines, radar with
        squad / friendly / enemy / objective marks, radio squares, an enemy
        mark, an objective, rounds and ammo, the weapon line, 4 hotbar
        tiles). Toggles: Low health, Low ammo, Training. "Peek at your real
        HUD" fades the whole pause menu to ~8% so the real HUD shows, with
        a small floating picker card and a PEEK chip; Esc, a click outside
        the card or Peek again goes back (Menus.HudPeek / EndHudPeek).
      - Preset: Default / Red-green / Blue-yellow / High contrast
        (UI.SetHudPreset), the current one lit, a note on the right.
      - the 12 keys as rows (swatch, name, what it colours, a CHANGED chip)
        in two columns, and a picker card for the clicked key: 24 squares,
        a colour box and hue strip (drags send at most ten a second), a
        hex box and Reset. Narrow page: the picker goes under the rows (and
        the rows to one column when very narrow).
    Search finds a row per key (a few squares and a mixer, Reset) and a
    preset dropdown. The group's count is the number of picked keys (the
    key rows are bound to the rhylib_hudcol_<key> convars).
    Picking calls UI.SetHudColour(key, col) (a colour equal to the
    preset's clears the pick); the HUD changes a frame later.
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C
local UI = Rhylib.UI
if not (UI and UI.HUD_KEYS and UI.SetHudColour and Menus.AddSetting) then return end

local KEYS = UI.HUD_KEYS
local WHITE_MAT = Material("vgui/white")

-- The preview's scenery (theme tokens; the HUD in it uses the HUD colours).
local COL_SKY_TOP = UI.Col("menus.hudPrevSkyTop", 38, 49, 60)
local COL_SKY_MID = UI.Col("menus.hudPrevSkyMid", 93, 109, 124)
local COL_SKY_LOW = UI.Col("menus.hudPrevSkyLow", 125, 127, 119)
local COL_HILLS = UI.Col("menus.hudPrevHills", 59, 59, 57)
local COL_GROUND = UI.Col("menus.hudPrevGround", 42, 38, 32)
local COL_BUILDING = UI.Col("menus.hudPrevBuilding", 42, 37, 34)
local COL_VISOR = UI.Col("menus.hudPrevVisor", 6, 7, 10, 245)
local COL_EMPTY = UI.Col("menus.hudPrevEmpty", 255, 255, 255, 31)
local COL_RADAR = UI.Col("menus.hudPrevRadar", 0, 0, 0, 128)
local COL_TILE = UI.Col("menus.hudPrevTile", 0, 0, 0, 90)
local COL_TILE_EDGE = UI.Col("menus.hudPrevTileEdge", 255, 255, 255, 77)
local COL_CHANNEL = UI.Col("menus.hudPrevChannel", 79, 175, 254, 153)

-- The picker's 24 squares (colour data, not theme).
local SWATCHES = {}
for _, h in ipairs({ "FFFFFF", "E8F1F7", "FF4040", "D6584C", "FF7A1A", "EF9F27", "FFD000", "F0E442",
    "A3E635", "5CD67D", "00FF66", "2EC4B6", "00FFFF", "56B4E9", "5A96FF", "C2CCFF",
    "9F8CFF", "CC79A7", "FF00AA", "E69F00", "D55E00", "8A8C84", "4FAFFF", "FFB3C1" }) do
    SWATCHES[#SWATCHES + 1] = Color(tonumber(string.sub(h, 1, 2), 16), tonumber(string.sub(h, 3, 4), 16), tonumber(string.sub(h, 5, 6), 16))
end
-- The hue strip's colours.
local HUES = {}
for i = 0, 36 do HUES[i] = HSVToColor(i * 10 % 360, 1, 1) end

Menus.hudColKey = Menus.hudColKey or "health"   -- the key the picker shows
Menus.hudColView = Menus.hudColView or {}        -- preview toggles: low, lowAmmo, sim

local function keyInfo(id) return KEYS[UI.hudKeyIndex[id] or 1] end

-- The colour the current preset gives a key (its default for Default).
local function presetCol(id)
    local cur = UI.HudPreset()
    for _, p in ipairs(UI.HUD_PRESETS) do
        if p[1] == cur and p[3] and p[3][id] then return p[3][id] end
    end
    return keyInfo(id)[4]
end

local function same(a, b) return a and b and a.r == b.r and a.g == b.g and a.b == b.b end

-- Pick a colour for a key (the preset's own colour clears the pick).
local function pick(id, col)
    if col and same(col, presetCol(id)) then col = nil end
    if not col and not UI.HudPicked(id) then return end
    UI.SetHudColour(id, col and Color(col.r, col.g, col.b) or nil)
end

-- Which keys are picked, and the preset note (rebuilt on a change, not per frame).
local picked, pickedN, note = {}, 0, ""
local function presetLabel(id)
    for _, p in ipairs(UI.HUD_PRESETS) do if p[1] == id then return p[2] end end
    return id
end
local function refreshPicked()
    pickedN = 0
    for _, k in ipairs(KEYS) do
        local on = UI.HudPicked(k[1])
        picked[k[1]] = on
        if on then pickedN = pickedN + 1 end
    end
    local p = UI.HudPreset()
    if pickedN > 0 then
        note = "Custom: " .. pickedN .. " changed from " .. presetLabel(p)
    elseif p == "default" then
        note = "The colours the HUD has today"
    elseif p == "hc" then
        note = "Strong colours that are easy to tell apart"
    else
        note = "Picked for " .. string.lower(presetLabel(p)) .. " colour blindness"
    end
end
refreshPicked()
Rhylib.Hook.Add("Rhylib.HudColoursChanged", "menus.hudcolours", refreshPicked)

--------------------------------------------------------------------------
-- Drawing helpers (mockup units: the preview is 1004 x 290)
--------------------------------------------------------------------------

local ox, oy, u = 0, 0, 1
local V3 = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local V4 = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local CIRC = {}
for i = 1, 24 do CIRC[i] = { x = 0, y = 0 } end
local scratch = Color(0, 0, 0)

local function X(x) return ox + x * u end
local function Y(y) return oy + y * u end

-- (DrawPoly wants clockwise on screen; flip the order when it isn't)
local function drawPoly(t, n)
    local a = 0
    for i = 1, n do
        local p, q = t[i], t[i % n + 1]
        a = a + (p.x * q.y - q.x * p.y)
    end
    if a == 0 then return end
    if a < 0 then
        for i = 1, math.floor(n / 2) do
            local p, q = t[i], t[n + 1 - i]
            p.x, q.x = q.x, p.x
            p.y, q.y = q.y, p.y
        end
    end
    -- (text drawn before leaves the font's texture set)
    draw.NoTexture()
    surface.SetMaterial(WHITE_MAT)
    surface.DrawPoly(t)
end
local function quad(x1, y1, x2, y2, x3, y3, x4, y4)
    V4[1].x, V4[1].y = X(x1), Y(y1)
    V4[2].x, V4[2].y = X(x2), Y(y2)
    V4[3].x, V4[3].y = X(x3), Y(y3)
    V4[4].x, V4[4].y = X(x4), Y(y4)
    drawPoly(V4, 4)
end
local function tri(x1, y1, x2, y2, x3, y3)
    V3[1].x, V3[1].y = X(x1), Y(y1)
    V3[2].x, V3[2].y = X(x2), Y(y2)
    V3[3].x, V3[3].y = X(x3), Y(y3)
    drawPoly(V3, 3)
end
local function rect(x, y, w, h)
    surface.DrawRect(math.floor(X(x)), math.floor(Y(y)), math.max(1, math.floor(w * u + 0.5)), math.max(1, math.floor(h * u + 0.5)))
end
local function line(x1, y1, x2, y2, t)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0 then return end
    local nx, ny = -dy / len * t * 0.5, dx / len * t * 0.5
    quad(x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny)
end
local function circle(cx, cy, r)
    for i = 1, 24 do
        local a = (i - 1) / 24 * math.pi * 2
        CIRC[i].x, CIRC[i].y = X(cx + math.cos(a) * r), Y(cy + math.sin(a) * r)
    end
    drawPoly(CIRC, 24)
end
local function ring(cx, cy, r, t)
    for i = 0, 23 do
        local a0, a1 = i / 24 * math.pi * 2, (i + 1) / 24 * math.pi * 2
        line(cx + math.cos(a0) * r, cy + math.sin(a0) * r, cx + math.cos(a1) * r, cy + math.sin(a1) * r, t)
    end
end
local function col(c, a)
    surface.SetDrawColor(c.r, c.g, c.b, a or c.a or 255)
end
local function tcol(c, a)
    scratch.r, scratch.g, scratch.b, scratch.a = c.r, c.g, c.b, a or 255
    return scratch
end
-- A font about n mockup pixels tall.
local function pfont(n, weight)
    return K.Font(math.max(6, math.floor(n * u / K.Scale() + 0.5)), weight)
end
local function text(s, n, weight, x, y, c, align)
    draw.SimpleText(s, pfont(n, weight), X(x), Y(y + n * 0.22), c, align or TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
end

-- The visor rim's curve (a quadratic from 0,34 through 502,6 to 1004,34).
local function rimY(x)
    local t = x / 1004
    return (1 - t) * (1 - t) * 34 + 2 * t * (1 - t) * 6 + t * t * 34
end
local DASH = { 140, 10, 40, 10, 240, 10, 30, 20 }   -- on, off, ... (500 in all)
local function dashOn(x)
    local p = x % 500
    for i = 1, #DASH do
        if p < DASH[i] then return i % 2 == 1 end
        p = p - DASH[i]
    end
    return false
end

-- One health or armour ladder (9 bars).
local function ladder(val, c, left)
    local lit = math.Round(val / 100 * 9)
    for i = 0, 8 do
        local len = (i == 0 or i == 8) and 30 or (i % 2 == 0 and 22 or 14)
        local x = left and (150 - len - i * 1.2) or (854 + i * 1.2)
        if (8 - i) < lit then col(c, 255) else col(COL_EMPTY) end
        rect(x, 68 + i * 14, len, 7)
    end
end

-- The preview HUD, drawn into w x h (mockup units scaled to fit).
local function drawPreview(w, h)
    u = math.min(w / 1004, h / 290)
    ox, oy = math.floor((w - 1004 * u) * 0.5), math.floor((h - 290 * u) * 0.5)
    local V = Menus.hudColView
    local S = UI.HudShown
    local cText, cHealth, cCrit, cArm = S("text"), S("health"), S("critical"), S("armour")
    local cWarn, cSel, cSquad, cFriend = S("warn"), S("selected"), S("squad"), S("friend")
    local cEnemy, cObj, cSim = S("enemy"), S("objective"), S("sim")

    surface.SetMaterial(WHITE_MAT)
    col(COL_VISOR, 255)
    surface.DrawRect(0, 0, w, h)
    -- Sky (two blends), hills, ground and two posts.
    for i = 0, 15 do
        local f = i / 15
        local a, b, g
        if f < 0.6 then a, b, g = COL_SKY_TOP, COL_SKY_MID, f / 0.6 else a, b, g = COL_SKY_MID, COL_SKY_LOW, (f - 0.6) / 0.4 end
        surface.SetDrawColor(Lerp(g, a.r, b.r), Lerp(g, a.g, b.g), Lerp(g, a.b, b.b), 255)
        surface.DrawRect(ox, math.floor(Y(290 * i / 16)), math.ceil(1004 * u), math.ceil(290 * u / 16) + 1)
    end
    col(COL_HILLS, 255)
    local HX = { 0, 120, 210, 300, 420, 520, 640, 760, 880, 1004 }
    local HY = { 170, 140, 150, 120, 124, 150, 138, 150, 120, 132 }
    for i = 1, #HX - 1 do quad(HX[i], HY[i], HX[i + 1], HY[i + 1], HX[i + 1], 290, HX[i], 290) end
    col(COL_GROUND, 255)
    local px, py
    for i = 0, 12 do
        local t = i / 12
        local gx = 2 * t * (1 - t) * 500 + t * t * 1004
        local gy = (1 - t) * (1 - t) * 190 + 2 * t * (1 - t) * 170 + t * t * 186
        if px then quad(px, py, gx, gy, gx, 290, px, 290) end
        px, py = gx, gy
    end
    col(COL_BUILDING, 255)
    rect(612, 132, 9, 24)
    rect(628, 135, 8, 21)

    -- The visor frame: above the rim, and below the window's lower edge.
    col(COL_VISOR)
    for i = 0, 19 do
        local x1, x2 = 1004 * i / 20, 1004 * (i + 1) / 20
        quad(x1, 0, x2, 0, x2, rimY(x2), x1, rimY(x1))
    end
    quad(0, 200, 344, 250, 344, 290, 0, 290)
    tri(344, 250, 374, 290, 344, 290)
    quad(660, 250, 1004, 200, 1004, 290, 660, 290)
    tri(630, 290, 660, 250, 660, 290)

    -- Rim (dashed) and compass.
    col(cText, 217)
    for x = 0, 990, 10 do
        if dashOn(x + 5) then line(x, rimY(x), x + 10, rimY(x + 10), 2) end
    end
    local ct = tcol(cText, 204)
    text("NW", 11, 500, 442, 36, ct, TEXT_ALIGN_CENTER)
    text("N", 11, 500, 502, 30, ct, TEXT_ALIGN_CENTER)
    text("NE", 11, 500, 562, 36, ct, TEXT_ALIGN_CENTER)

    -- Armour (left) and health (right).
    local hp = V.low and 22 or 82
    local hpCol = V.sim and cSim or (V.low and cCrit or cHealth)
    ladder(60, cArm, true)
    ladder(hp, hpCol, false)
    text("60", 15, 500, 66, 58, cArm)
    text(tostring(hp), 15, 500, 938, 58, hpCol, TEXT_ALIGN_RIGHT)

    -- Stamina lines along the lower edge.
    local stam = V.lowAmmo and 0.15 or 0.7
    col(stam < 0.2 and cWarn or cText, 255)
    line(344, 250, 344 - 300 * stam, 250 - 46 * stam, 3)
    line(660, 250, 660 + 300 * stam, 250 - 46 * stam, 3)

    -- Radar.
    col(COL_RADAR)
    circle(270, 252, 34)
    col(cText, 153)
    ring(270, 252, 34, 1.5)
    col(cSquad, 255)
    circle(258, 240, 4)
    circle(284, 236, 4)
    col(cFriend, 255)
    quad(276, 262, 281, 267, 276, 272, 271, 267)
    col(cEnemy, 255)
    rect(290, 250, 7, 7)
    col(cObj, 255)
    tri(262, 262, 266, 255, 270, 262)
    col(cText, 255)
    tri(270, 246, 275, 258, 270, 255)
    tri(270, 246, 270, 255, 265, 258)

    -- Radio squares (the last one is a channel colour).
    col(cText, 115)
    rect(314, 226, 22, 16)
    col(cSquad, 242)
    rect(314, 246, 22, 16)
    col(COL_CHANNEL)
    rect(314, 266, 22, 16)

    -- An enemy mark and an objective.
    col(cEnemy, 255)
    line(640, 130, 650, 120, 2.5)
    line(650, 120, 660, 130, 2.5)
    line(660, 130, 650, 140, 2.5)
    line(650, 140, 640, 130, 2.5)
    text("B1 · 42 m", 11, 500, 650, 114, cEnemy, TEXT_ALIGN_CENTER)
    col(cObj, 255)
    quad(190, 122, 197, 115, 204, 122, 197, 129)
    text("OBJ ALPHA · 120 m", 13, 700, 197, 106, cObj, TEXT_ALIGN_CENTER)

    -- Crosshair ticks.
    col(cText, 230)
    line(502, 140, 502, 146, 2)
    line(502, 154, 502, 160, 2)
    line(492, 150, 498, 150, 2)
    line(506, 150, 512, 150, 2)

    -- Rounds, ammo, weapon line, hotbar.
    local ammo = V.lowAmmo and 6 or 38
    local ammoCol = ammo <= 10 and cWarn or cText
    for i = 0, 29 do
        if i < ammo / 2 then col(ammoCol, 255) else surface.SetDrawColor(COL_EMPTY.r, COL_EMPTY.g, COL_EMPTY.b, 33) end
        rect(800 + i * 6, 236, 3, 11)
    end
    text(tostring(ammo), 32, 500, 980, 226, ammoCol, TEXT_ALIGN_RIGHT)
    text("DC-15A · AUTO", 12, 700, 980, 200, cText, TEXT_ALIGN_RIGHT)
    for i = 0, 3 do
        local x = 790 + i * 50
        local on = i == 0
        if on then col(cSel, 255) else col(COL_TILE) end
        rect(x, 256, 44, 26)
        if on then col(cSel, 255) else col(COL_TILE_EDGE) end
        surface.DrawOutlinedRect(math.floor(X(x)), math.floor(Y(256)), math.floor(44 * u + 0.5), math.floor(26 * u + 0.5))
        text(tostring(i + 1), 12, 500, x + 22, 273, on and tcol(COL_VISOR, 255) or cText, TEXT_ALIGN_CENTER)
    end
end

--------------------------------------------------------------------------
-- Peek: the pause menu fades (cl_10_pause.lua reads Menus.hudPeek) and a
-- small picker card floats over your real HUD.
--------------------------------------------------------------------------

local buildPicker

-- Menus.HudPeek(on): start or stop peeking. Menus.EndHudPeek(): stop.
function Menus.HudPeek(on)
    if IsValid(Menus.hudPeekPanel) then Menus.hudPeekPanel:Remove() end
    Menus.hudPeekPanel = nil
    Menus.hudPeek = nil
    if not on or not IsValid(Menus.pause) then return end
    local S = K.S
    local holder = vgui.Create("EditablePanel", Menus.pause)
    Menus.hudPeekPanel = holder
    Menus.hudPeek = true
    holder:SetPos(0, 0)
    holder:SetSize(Menus.pause:GetWide(), Menus.pause:GetTall())
    holder.Paint = nil
    -- (a click outside the card goes back, Peek's own spot included)
    function holder:OnMousePressed() Menus.HudPeek(false) end
    function holder:OnRemove()
        if Menus.hudPeekPanel == self then
            Menus.hudPeekPanel = nil
            Menus.hudPeek = nil
        end
    end

    local chip = vgui.Create("DPanel", holder)
    local chipText = "Your real HUD, live · click Peek again or press Esc to go back"
    surface.SetFont(K.Font(13, 700))
    local w1 = surface.GetTextSize("PEEK")
    surface.SetFont(K.Font(13))
    local w2 = surface.GetTextSize(chipText)
    chip:SetSize(S(14) + S(8) + S(10) + w1 + S(10) + w2 + S(14), S(32))
    chip:SetPos(math.floor((holder:GetWide() - chip:GetWide()) * 0.5), math.floor(ScrH() * 150 / 900))
    function chip:Paint(w, h)
        K.SetCol(C.bg, 230)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeLight)
        surface.DrawOutlinedRect(0, 0, w, h)
        K.SetCol(C.accent)
        surface.DrawRect(S(14), math.floor(h * 0.5) - S(4), S(8), S(8))
        local x = S(14) + S(8) + S(10)
        draw.SimpleText("PEEK", K.Font(13, 700), x, h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(chipText, K.Font(13), x + w1 + S(10), h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    function chip:OnMousePressed() Menus.HudPeek(false) end

    local card = buildPicker(holder, "peek")
    local cw = S(420)
    local ch = card:Arrange(cw)
    card:SetSize(cw, ch)
    card:SetPos(math.floor((holder:GetWide() - cw) * 0.5), math.floor(ScrH() * 360 / 900))
end
function Menus.EndHudPeek() Menus.HudPeek(false) end

--------------------------------------------------------------------------
-- The picker card: the key's swatch and name, 24 squares, a colour box
-- and hue strip, a hex box and Reset. mode: "side" (narrow, stacked),
-- "wide" (squares left, colour box right) or "peek" (squares only).
-- card:Arrange(w) places everything and returns the height it needs.
--------------------------------------------------------------------------

local function wrapLines(s, font, maxW, out)
    for i = #out, 1, -1 do out[i] = nil end
    surface.SetFont(font)
    local cur = ""
    for word in string.gmatch(s, "%S+") do
        local try = cur == "" and word or (cur .. " " .. word)
        if cur ~= "" and surface.GetTextSize(try) > maxW then
            out[#out + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    if cur ~= "" then out[#out + 1] = cur end
    return out
end

local HINT = "Click a square, drag in the box, or type a hex colour. The preview and your real HUD change as you pick; Peek shows it over the game."
local HINT_PEEK = "Pick here and watch your real HUD change."

function buildPicker(parent, mode)
    local S = K.S
    local card = vgui.Create("DPanel", parent)
    card.mode = mode
    card.lines = {}
    local peek = mode == "peek"
    -- (a click on the floating card doesn't count as a click outside it)
    if peek then function card:OnMousePressed() end end

    function card:Paint(w, h)
        if peek then
            K.Plate(0, 0, w, h, { ticks = "all" })
        else
            K.SetCol(C.button)
            surface.DrawRect(0, 0, w, h)
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            K.SetCol(C.edgeLight)
            surface.DrawLine(1, 1, w - 1, 1)
        end
        local id = Menus.hudColKey
        local k = keyInfo(id)
        local P, sw = S(14), S(22)
        local c = UI.HudShown(id)
        surface.SetDrawColor(c.r, c.g, c.b, 255)
        surface.DrawRect(P, P, sw, sw)
        K.SetCol(C.edgeLight)
        surface.DrawOutlinedRect(P, P, sw, sw)
        local nameW = (self.headW or w) - sw - S(10) - ((picked[id] and not peek) and S(70) or 0)
        local nf = K.Font(16, 700)
        local name = k[2]
        if peek then
            surface.SetFont(nf)
            local tw = surface.GetTextSize(name)
            draw.SimpleText(K.Fit(string.lower(k[3]), K.Font(12), w - P * 2 - sw - S(10) - tw - S(12)), K.Font(12),
                w - P, P + sw * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText(K.Fit(name, nf, nameW), nf, P + sw + S(10), P + sw * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if picked[id] and not peek then
            K.Caps("Changed", (self.headW or (w - P * 2)) + P, P + sw * 0.5, C.accent, TEXT_ALIGN_RIGHT)
        end
        local f = K.Font(12)
        for i, l in ipairs(self.lines) do
            draw.SimpleText(l, f, self.hintX or P, (self.hintY or 0) + (i - 1) * S(16), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end

    -- The squares.
    card.swatches = {}
    for i, sc in ipairs(SWATCHES) do
        local b = vgui.Create("DButton", card)
        b:SetText("")
        b:SetTooltip(string.format("#%02X%02X%02X", sc.r, sc.g, sc.b))
        function b:Paint(w, h)
            surface.SetDrawColor(sc.r, sc.g, sc.b, 255)
            surface.DrawRect(0, 0, w, h)
            local on = same(UI.HudShown(Menus.hudColKey), sc)
            K.SetCol(on and C.text or C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h, on and 2 or 1)
            return true
        end
        function b:DoClick()
            surface.PlaySound("ui/buttonclick.wav")
            pick(Menus.hudColKey, sc)
        end
        card.swatches[i] = b
    end

    -- The colour box (saturation across, brightness down) and hue strip.
    -- Drags send at most ten colours a second, the last one always.
    local hue, sat, val = 0, 0, 1
    local syncKey, syncR, syncG, syncB
    local dragging, pending, nextSend = false, nil, 0
    local hueCol = Color(255, 0, 0)
    local function setHue(hh)
        hue = hh
        local c = HSVToColor(hue, 1, 1)
        hueCol.r, hueCol.g, hueCol.b = c.r, c.g, c.b
    end
    local function send(force)
        if not pending then return end
        if not force and RealTime() < nextSend then return end
        nextSend = RealTime() + 0.1
        local c = pending
        pending = nil
        pick(Menus.hudColKey, c)
    end
    local function want()
        local c = HSVToColor(hue, sat, val)
        pending = Color(c.r, c.g, c.b)
        send(false)
    end
    setHue(0)

    if not peek then
        local box = vgui.Create("DPanel", card)
        card.box = box
        box:SetCursor("crosshair")
        local function at(self)
            local x, y = self:CursorPos()
            sat = math.Clamp(x / math.max(1, self:GetWide()), 0, 1)
            val = 1 - math.Clamp(y / math.max(1, self:GetTall()), 0, 1)
            want()
        end
        function box:OnMousePressed() dragging = true self.drag = true self:MouseCapture(true) at(self) end
        function box:OnMouseReleased() self.drag = false dragging = false self:MouseCapture(false) send(true) end
        function box:Think() if self.drag then at(self) end end
        function box:Paint(w, h)
            local n = 32
            for i = 0, n - 1 do
                local f = i / (n - 1)
                surface.SetDrawColor(Lerp(f, 255, hueCol.r), Lerp(f, 255, hueCol.g), Lerp(f, 255, hueCol.b), 255)
                local x0 = math.floor(w * i / n)
                surface.DrawRect(x0, 0, math.floor(w * (i + 1) / n) - x0, h)
            end
            local m = 24
            for j = 0, m - 1 do
                local y0 = math.floor(h * j / m)
                surface.SetDrawColor(0, 0, 0, 255 * (j + 0.5) / m)
                surface.DrawRect(0, y0, w, math.floor(h * (j + 1) / m) - y0)
            end
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            local kx, ky, r = math.floor(sat * w), math.floor((1 - val) * h), S(5)
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawOutlinedRect(kx - r - 1, ky - r - 1, r * 2 + 2, r * 2 + 2)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawOutlinedRect(kx - r, ky - r, r * 2, r * 2, 2)
        end

        local bar = vgui.Create("DPanel", card)
        card.hue = bar
        bar:SetCursor("hand")
        local function hat(self)
            local x = self:CursorPos()
            setHue(math.Clamp(x / math.max(1, self:GetWide()), 0, 1) * 360)
            want()
        end
        function bar:OnMousePressed() dragging = true self.drag = true self:MouseCapture(true) hat(self) end
        function bar:OnMouseReleased() self.drag = false dragging = false self:MouseCapture(false) send(true) end
        function bar:Think() if self.drag then hat(self) end end
        function bar:Paint(w, h)
            for i = 0, 35 do
                local c = HUES[i]
                surface.SetDrawColor(c.r, c.g, c.b, 255)
                local x0 = math.floor(w * i / 36)
                surface.DrawRect(x0, 0, math.floor(w * (i + 1) / 36) - x0, h)
            end
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            local kx = math.floor(hue / 360 * w)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawRect(math.Clamp(kx - 2, 0, w - 4), 0, 4, h)
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawOutlinedRect(math.Clamp(kx - 3, 0, w - 6), 0, 6, h)
        end

        local hexLabel = vgui.Create("DPanel", card)
        card.hexLabel = hexLabel
        function hexLabel:Paint(w, h) K.Caps("Hex", 0, h * 0.5, C.label) end

        local hex = K.TextEntry(card, "#rrggbb")
        card.hex = hex
        hex:SetUpdateOnType(true)
        local function parse(s)
            s = string.gsub(tostring(s or ""), "[^%x]", "")
            if #s ~= 6 then return nil end
            return Color(tonumber(string.sub(s, 1, 2), 16), tonumber(string.sub(s, 3, 4), 16), tonumber(string.sub(s, 5, 6), 16))
        end
        function hex:OnValueChange(v)
            local c = parse(v)
            if c and not same(c, UI.HudShown(Menus.hudColKey)) then pick(Menus.hudColKey, c) end
        end
        function hex:OnEnter() self:OnValueChange(self:GetValue()) self:KillFocus() end
        card.reset = K.Button(card, "Reset", function() pick(Menus.hudColKey, nil) end,
            { small = true, enabled = function() return picked[Menus.hudColKey] end, tooltip = "Back to the preset's colour" })
    else
        card.back = K.Button(card, "Back to the menu", function() Menus.HudPeek(false) end, { small = true })
    end

    -- Follow the shown colour (another key picked, a preset, a square)
    -- unless a drag is going on.
    function card:Think()
        if pending and not dragging then send(true) end
        if dragging or pending then return end
        local id = Menus.hudColKey
        local c = UI.HudShown(id)
        if id == syncKey and c.r == syncR and c.g == syncG and c.b == syncB then return end
        syncKey, syncR, syncG, syncB = id, c.r, c.g, c.b
        local hh, ss, vv = ColorToHSV(c)
        if ss > 0.001 and vv > 0.001 then setHue(hh) end
        sat, val = ss, vv
        if IsValid(self.hex) and not self.hex:HasFocus() then
            self.hex:SetText(string.format("#%02X%02X%02X", c.r, c.g, c.b))
        end
    end

    local function placeSwatches(x, y, w, cols)
        local gap, sh = S(5), S(26)
        local cw = (w - gap * (cols - 1)) / cols
        for i, b in ipairs(card.swatches) do
            local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
            local bx = math.floor(x + c * (cw + gap))
            b:SetPos(bx, y + r * (sh + gap))
            b:SetSize(math.floor(x + c * (cw + gap) + cw) - bx, sh)
        end
        return y + math.ceil(#card.swatches / cols) * (sh + gap) - gap
    end

    function card:Arrange(w)
        local P = S(14)
        local f = K.Font(12)
        local y = P + S(22) + S(10)
        if self.mode == "wide" then
            local rightW = math.floor((w - P * 3) * 0.4)
            local leftW = w - P * 3 - rightW
            self.headW = leftW
            y = placeSwatches(P, y, leftW, 12) + S(10)
            self.hexLabel:SetPos(P, y) self.hexLabel:SetSize(S(34), S(30))
            self.hex:SetPos(P + S(38), y) self.hex:SetSize(leftW - S(38) - S(66), S(30))
            self.reset:SetPos(P + leftW - S(58), y + S(2)) self.reset:SetSize(S(58), S(26))
            y = y + S(30) + S(10)
            self.hintX, self.hintY = P, y
            wrapLines(HINT, f, leftW, self.lines)
            y = y + #self.lines * S(16)
            local rx = P * 2 + leftW
            local bh = math.max(S(60), y - P - S(18))
            self.box:SetPos(rx, P) self.box:SetSize(rightW, bh)
            self.hue:SetPos(rx, P + bh + S(6)) self.hue:SetSize(rightW, S(12))
            return math.max(y, P + bh + S(18)) + P
        end
        local inner = w - P * 2
        self.headW = inner
        local cols = (not peek and inner >= S(440)) and 12 or 8
        y = placeSwatches(P, y, inner, cols) + S(10)
        if peek then
            self.hintX, self.hintY = P, y
            wrapLines(HINT_PEEK, f, inner - S(150), self.lines)
            local hh = math.max(#self.lines * S(16), S(26))
            self.back:SetPos(w - P - S(140), y + math.floor((hh - S(26)) * 0.5))
            self.back:SetSize(S(140), S(26))
            return y + hh + P
        end
        self.box:SetPos(P, y) self.box:SetSize(inner, S(96))
        y = y + S(96) + S(6)
        self.hue:SetPos(P, y) self.hue:SetSize(inner, S(12))
        y = y + S(12) + S(10)
        self.hexLabel:SetPos(P, y) self.hexLabel:SetSize(S(34), S(30))
        self.hex:SetPos(P + S(38), y) self.hex:SetSize(inner - S(38) - S(66), S(30))
        self.reset:SetPos(P + inner - S(58), y + S(2)) self.reset:SetSize(S(58), S(26))
        y = y + S(30) + S(10)
        self.hintX, self.hintY = P, y
        wrapLines(HINT, f, inner, self.lines)
        return y + #self.lines * S(16) + P
    end
    return card
end

--------------------------------------------------------------------------
-- The page parts
--------------------------------------------------------------------------

-- The live preview box (toggles and Peek on top when there's room clear
-- of the compass, else in a strip under the picture).
local function previewBox(sp)
    local S = K.S
    local box = vgui.Create("DPanel", sp)
    box:Dock(TOP)
    box:DockMargin(0, 0, S(10), S(10))
    box:SetTall(S(220))
    local V = Menus.hudColView
    local buttons = {}
    local function toggle(label, field)
        local b = K.Button(box, label, function() V[field] = not V[field] end,
            { small = true, selected = function() return V[field] and true or false end })
        surface.SetFont(K.Font(12, 700))
        b:SetWide(surface.GetTextSize(string.upper(label)) + S(24))
        buttons[#buttons + 1] = b
    end
    toggle("Low health", "low")
    toggle("Low ammo", "lowAmmo")
    toggle("Training", "sim")
    local peekLabel = function() return Menus.hudPeek and "Back to the menu" or "Peek at your real HUD" end
    local pk = K.Button(box, peekLabel, function() Menus.HudPeek(not Menus.hudPeek) end,
        { small = true, accent = true, tooltip = "Fade the menu and see your real HUD while you pick" })
    surface.SetFont(K.Font(12, 700))
    pk:SetWide(surface.GetTextSize(string.upper("Peek at your real HUD")) + S(28))
    buttons[#buttons + 1] = pk

    function box:PerformLayout(w, h)
        local picH = math.Clamp(math.floor(w * 290 / 1004), S(150), S(300))
        local total = 0
        for _, b in ipairs(buttons) do total = total + b:GetWide() + S(6) end
        local pu = math.min(w / 1004, picH / 290)
        local poX = (w - 1004 * pu) * 0.5
        -- (on the picture only when the buttons stay right of the compass)
        local over = w - S(12) - total >= poX + 600 * pu
        self.picH = picH
        self.strip = not over
        local want = over and picH or (picH + S(38))
        if h ~= want then
            self:SetTall(want)
            sp:InvalidateLayout()
        end
        local x = w - S(12)
        local y = over and S(10) or (picH + S(6))
        for i = #buttons, 1, -1 do
            local b = buttons[i]
            x = x - b:GetWide()
            b:SetPos(x, y)
            b:SetTall(S(26))
            x = x - S(6)
        end
    end
    function box:Paint(w, h)
        local ph = self.picH or h
        drawPreview(w, ph)
        if self.strip then
            K.SetCol(C.header)
            surface.DrawRect(0, ph, w, h - ph)
        end
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        -- (LIVE PREVIEW chip, top left)
        local f = K.Font(11, 700)
        surface.SetFont(f)
        local tw = surface.GetTextSize("LIVE PREVIEW")
        K.SetCol(C.bg, 200)
        surface.DrawRect(S(12), S(10), tw + S(16), S(22))
        draw.SimpleText("LIVE PREVIEW", f, S(20), S(21), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    function box:OnRemove() if Menus.hudPeek then Menus.HudPeek(false) end end
    return box
end

-- Preset: four buttons, the current one lit, and a note on the right.
local function presetRow(sp)
    local S = K.S
    local row = vgui.Create("DPanel", sp)
    row:Dock(TOP)
    row:DockMargin(0, 0, S(10), S(10))
    row:SetTall(S(34))
    local buttons = {}
    for _, p in ipairs(UI.HUD_PRESETS) do
        local id = p[1]
        local b = K.Button(row, p[2], function() UI.SetHudPreset(id) end,
            { small = true, selected = function() return UI.HudPreset() == id end })
        surface.SetFont(K.Font(12, 700))
        b:SetWide(surface.GetTextSize(string.upper(p[2])) + S(28))
        function b:PaintOver(w, h)
            if UI.HudPreset() == id and pickedN == 0 then
                K.SetCol(C.accent)
                surface.DrawOutlinedRect(0, 0, w, h)
            end
        end
        buttons[#buttons + 1] = b
    end
    function row:PerformLayout(w, h)
        local need = 0
        for _, b in ipairs(buttons) do need = need + b:GetWide() + S(8) end
        -- (no room: the "Preset" label goes)
        self.labelW = (need + S(110) <= w) and S(110) or 0
        local x = self.labelW
        for _, b in ipairs(buttons) do
            b:SetPos(x, math.floor((h - b:GetTall()) * 0.5))
            x = x + b:GetWide() + S(8)
        end
        self.noteX = x + S(4)
    end
    function row:Paint(w, h)
        if (self.labelW or 0) > 0 then
            draw.SimpleText("Preset", K.Font(15, 500), 0, h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local room = w - (self.noteX or w)
        if room > S(60) then
            local f = K.Font(13)
            draw.SimpleText(K.Fit(note, f, room), f, w, h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    return row
end

-- One key row: swatch, name, what it colours, CHANGED; click picks it.
local function keyRow(parent, k)
    local S = K.S
    local id, label, what = k[1], k[2], k[3]
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    function b:Paint(w, h)
        local on = Menus.hudColKey == id
        K.SetCol(on and C.rowHover or C.button)
        surface.DrawRect(0, 0, w, h)
        if not on and self:IsHovered() then
            K.SetCol(C.buttonHover, 110)
            surface.DrawRect(0, 0, w, h)
        end
        K.SetCol(on and C.accent or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local sw = S(26)
        local sx, sy = S(12), math.floor((h - sw) * 0.5)
        local c = UI.HudShown(id)
        surface.SetDrawColor(c.r, c.g, c.b, 255)
        surface.DrawRect(sx, sy, sw, sw)
        K.SetCol(C.edgeLight)
        surface.DrawOutlinedRect(sx, sy, sw, sw)
        local tx, right = sx + sw + S(12), w - S(12)
        if picked[id] then
            local f = K.Font(10, 700)
            surface.SetFont(f)
            local cw = surface.GetTextSize("CHANGED") + S(12)
            K.SetCol(C.accent, 40)
            surface.DrawRect(right - cw, math.floor(h * 0.5) - S(9), cw, S(18))
            draw.SimpleText("CHANGED", f, right - cw * 0.5, h * 0.5, C.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            right = right - cw - S(8)
        end
        local nf, df = K.Font(14, 500), K.Font(12)
        draw.SimpleText(K.Fit(label, nf, right - tx), nf, tx, h * 0.34, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(K.Fit(what, df, right - tx), df, tx, h * 0.68, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        Menus.hudColKey = id
    end
    return b
end

-- The rows and the picker card. Wide page: two columns of rows with the
-- card on their right; narrower: the card under the rows (one column of
-- rows when very narrow).
local function keysArea(sp)
    local S = K.S
    local area = vgui.Create("DPanel", sp)
    area:Dock(TOP)
    area:DockMargin(0, 0, S(10), S(10))
    area:SetTall(S(400))
    area.Paint = nil
    local rows = {}
    for i, k in ipairs(KEYS) do rows[i] = keyRow(area, k) end
    local card = buildPicker(area, "side")
    function area:PerformLayout(w, h)
        local gap, rh = S(6), S(50)
        local mode = (w >= S(940) and "side") or (w >= S(600) and "wide") or "stack"
        local cols = mode == "stack" and 1 or 2
        local rowsW = mode == "side" and (w - S(290) - S(16)) or w
        local colW = math.floor((rowsW - gap * (cols - 1)) / cols)
        for i, r in ipairs(rows) do
            local c, rr = (i - 1) % cols, math.floor((i - 1) / cols)
            r:SetPos(c * (colW + gap), rr * (rh + gap))
            r:SetSize(c == cols - 1 and (rowsW - c * (colW + gap)) or colW, rh)
        end
        local rowsH = math.ceil(#rows / cols) * (rh + gap) - gap
        local total
        if mode == "side" then
            card.mode = "side"
            local cw = S(290)
            local ch = card:Arrange(cw)
            card:SetPos(w - cw, 0)
            card:SetSize(cw, ch)
            total = math.max(rowsH, ch)
        else
            card.mode = mode == "wide" and "wide" or "side"
            local ch = card:Arrange(w)
            card:SetPos(0, rowsH + S(12))
            card:SetSize(w, ch)
            total = rowsH + S(12) + ch
        end
        if h ~= total then
            self:SetTall(total)
            sp:InvalidateLayout()
        end
    end
    return area
end

--------------------------------------------------------------------------
-- Settings rows: the group page above, plus rows that show in search
-- (and give the group its count: the key rows use the key convars).
--------------------------------------------------------------------------

local function register()
    if Menus.SettingGroupTop then
        Menus.SettingGroupTop("HUD colours", function(sp)
            refreshPicked()
            previewBox(sp)
            presetRow(sp)
            keysArea(sp)
        end, { ownRows = true })
    end
    local presets = {}
    for _, p in ipairs(UI.HUD_PRESETS) do presets[#presets + 1] = { p[1], p[2] } end
    Menus.AddSetting("HUD colours", { id = "hudcol.preset", order = 5, group = "HUD colours",
        title = "HUD colour preset", desc = "Default, or colours picked for colour blindness",
        kind = "choice", options = presets, get = UI.HudPreset, set = UI.SetHudPreset })
    for i, k in ipairs(KEYS) do
        local id = k[1]
        -- (search rows: the key's default and preset colours, and a mixer)
        local sw = { k[4] }
        for _, p in ipairs(UI.HUD_PRESETS) do
            local pc = p[3] and p[3][id]
            local dup = false
            for _, s in ipairs(sw) do if pc and same(s, pc) then dup = true end end
            if pc and not dup then sw[#sw + 1] = pc end
        end
        Menus.AddSetting("HUD colours", { id = "hudcol." .. id, order = 10 + i, group = "HUD colours",
            title = "HUD colour: " .. k[2], desc = k[3], kind = "colour", convar = "rhylib_hudcol_" .. id, swatches = sw,
            get = function() return UI.HudShown(id) end,
            set = function(c) pick(id, c) end })
    end
end
register()
