--[[
    The health menu (H, convar rhylib_medical_key). Press it while looking
    at someone close to see their body instead of yours.

    Layout: a centred window with a red top edge. Header: HEALTH (yours)
    or HEALTH · <name>, a line under it (job, distance, how much you see),
    a health bar (medics, or your own body) and an armour bar (your own
    body, or a test dummy's) on the right, and a close button. Three columns:
      - left: the body picture, each part white when fine and redder the
        more it's hurt, small tags beside the parts; the hovered part is
        outlined blue, with a tooltip;
      - middle: BODY PARTS, one row per part (damage bar, tag chips, the
        number or "fine"); hovering a row lights the part in the picture
        and the other way round; then the EFFECTS card (a diamond, the
        effect, the time left);
      - right: TREATMENT, a card per kit (count or charge, what it does,
        how to use it), and a hint box at the bottom. Treating is the
        kit's click: this window only shows.

    Hardcore (Med.Hardcore()): parts also show FRACTURE and BURNS (orange
    shade), and the kit cards can be dragged onto a body part (picture or
    row) to treat that part (med.treat: patient, part 3 bits, kit
    Med.TREAT_BITS). A kit's click opens this window (med.open).

    Medics see exact damage, health and effects. Troopers see roughly how
    hurt each part is and whether it bleeds (and their own effects).

    What's shown is worked out ten times a second into reused tables
    (PANEL:Refresh); Paint only draws it.

    Client only. The window is the vgui panel "RhylibInjuries". Opening
    someone else's sends med.view (patient) so the server streams their
    injuries (med.inj); closing sends med.view(NULL). Patients are players
    or test dummies (Med.IsPatient; a dummy's health is read with
    Med.HealthOf). Without rhylib_inventory the kits counted are the kit
    weapons you hold.
    Public: Med.OpenInjuries(target), Med.ToggleInjuries().
    Console: rhylib_injuries (toggle). Client convar rhylib_medical_key
    (default "h"; Settings > Controls). Hidden in the simplified system.
]]

local Med = Rhylib.Medical
local UI = Rhylib.UI

local keyVar = CreateClientConVar("rhylib_medical_key", "h", true, false, "Key that opens the injury menu")

local COL_PAGE = Color(11, 12, 11)
local COL_BG = Color(14, 16, 15, 250)
local COL_SIDE = Color(18, 20, 19)
local COL_CARD = Color(22, 25, 23)
local COL_SEL = Color(27, 37, 48)
local COL_EDGE = Color(0, 0, 0, 255)
local COL_BORDER = Color(42, 45, 41)
local COL_TEXT = Color(228, 227, 220)
local COL_DIM = Color(169, 168, 160)
local COL_SOFT = Color(214, 213, 206)
local COL_LABEL = Color(138, 140, 132)
local COL_BLUE = Color(133, 183, 235)
local COL_RED = Color(226, 75, 74)
local COL_RED_TEXT = Color(240, 149, 149)
local COL_AMBER = Color(239, 159, 39)
local COL_GREY_BAR = Color(201, 200, 192)
local COL_FINE = Color(226, 228, 222)
local COL_HURT = Color(214, 48, 40)
local COL_OUTLINE = Color(0, 0, 0, 220)
local COL_BURN = Color(232, 132, 48)
local COL_DROP = COL_BLUE
local COL_ICON_BG = Color(42, 18, 20)
local COL_HINT_BG = Color(29, 26, 18)
local COL_HINT_EDGE = Color(74, 60, 28)
local COL_HINT_TEXT = Color(232, 207, 154)

local TAGS = {
    { key = "bleed2", text = "HEAVY BLEEDING", col = Color(226, 60, 50) },
    { key = "bleed1", text = "BLEEDING", col = Color(240, 128, 110) },
    { key = "limp", text = "LIMPING", col = Color(239, 199, 89) },
    { key = "frac", text = "FRACTURE", col = Color(239, 199, 89) },
    { key = "burn", text = "BURNS", col = COL_BURN },
}

local function S(n) return math.floor(n * ScrH() / 1080 + 0.5) end
local function font(size, weight) return UI.Font(size, weight) end

-- Body outline in a 200 x 380 box, screen-facing (your right arm on the
-- left of the picture). Convex pieces, clockwise for surface.DrawPoly.
local function octagon(cx, cy, r)
    local pts = {}
    for i = 0, 7 do
        local a = math.rad(i * 45 - 112.5)
        pts[#pts + 1] = { cx + math.cos(a) * r, cy + math.sin(a) * r }
    end
    return pts
end
local SHAPES = {
    head = { octagon(100, 36, 26) },
    torso = { { { 64, 72 }, { 136, 72 }, { 130, 198 }, { 70, 198 } } },
    rarm = { { { 38, 80 }, { 60, 74 }, { 56, 206 }, { 34, 204 } } },
    larm = { { { 140, 74 }, { 162, 80 }, { 166, 204 }, { 144, 206 } } },
    rleg = { { { 70, 202 }, { 98, 202 }, { 94, 372 }, { 64, 372 } } },
    lleg = { { { 102, 202 }, { 130, 202 }, { 136, 372 }, { 106, 372 } } },
}
-- Where each part's tags go (box coordinates) and which side they grow to.
local TAG_AT = {
    head = { 140, 22, 1 }, torso = { 140, 120, 1 }, rarm = { 28, 120, -1 },
    larm = { 172, 160, 1 }, rleg = { 58, 300, -1 }, lleg = { 142, 300, 1 },
}
-- The rows in the middle column, top to bottom.
local ROW_ORDER = { "head", "torso", "rarm", "larm", "rleg", "lleg" }

local function pointIn(poly, x, y)
    -- Convex polygon, clockwise on screen: inside if left of no edge.
    local n = #poly
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        if (b[1] - a[1]) * (y - a[2]) - (b[2] - a[2]) * (x - a[1]) < 0 then return false end
    end
    return true
end

-- Writes the part's picture colour into out (no new Color).
local function partColour(p, rough, out)
    local burn = p.burn or 0
    local f = math.Clamp(math.max(p.dmg, burn * 0.8) / 100, 0, 1)
    -- Troopers only see three shades: fine, hurt, badly hurt.
    if rough then f = f <= 0 and 0 or (f < 0.5 and 0.45 or 1) end
    local base = burn > p.dmg and COL_BURN or COL_HURT   -- (hardcore burns: orange)
    out.r, out.g, out.b, out.a = Lerp(f, COL_FINE.r, base.r), Lerp(f, COL_FINE.g, base.g), Lerp(f, COL_FINE.b, base.b), 255
end

-- Illness by stage (cl_50_illness.lua Med.IllSigns), drawn on the head.
local ILL_TAGS = {
    { key = "ill1", text = "UNWELL", col = Color(170, 200, 120) },
    { key = "ill2", text = "ILL", col = Color(190, 210, 90) },
    { key = "ill3", text = "SEVERELY ILL", col = Color(214, 225, 60) },
}

-- Cuts a reused array down to n entries.
local function cut(t, n)
    for i = #t, n + 1, -1 do t[i] = nil end
end

-- Fills out with the part's tags; returns out.
-- (detail: fractures and burns shown, for medics and your own body)
local function tagsFor(out, p, rough, limping, detail)
    local n = 0
    if rough then
        if p.bleed > 0 then n = n + 1 out[n] = TAGS[2] end
    elseif p.bleed == 2 then n = n + 1 out[n] = TAGS[1]
    elseif p.bleed == 1 then n = n + 1 out[n] = TAGS[2] end
    if p.limp and limping then n = n + 1 out[n] = TAGS[3] end
    if detail then
        if p.frac then n = n + 1 out[n] = TAGS[4] end
        if (p.burn or 0) > 0 then n = n + 1 out[n] = TAGS[5] end
    end
    cut(out, n)
    return out
end

-- How many of an item you carry (rhylib_inventory's client copy), and
-- the charge (0-1) of a first aid kit when there's exactly one (or nil).
local function carried(id)
    local Inv = Rhylib.Inventory
    local n, fill = 0, nil
    if Inv and Inv.byUid then
        for _, inst in pairs(Inv.byUid) do
            if inst.id == id then
                n = n + (inst.count or 1)
                fill = inst.data and inst.data.fill or 1
            end
        end
    elseif LocalPlayer():HasWeapon(id) then
        n = 1
        local w = LocalPlayer():GetWeapon(id)
        fill = IsValid(w) and w.GetCharge and w:GetCharge() or nil
    end
    if n ~= 1 then fill = nil end
    return n, fill
end

-- Word-wrapped lines of text (cached: the texts hardly change).
local wrapCache, wrapCount = {}, 0
local function wrap(text, fnt, maxW)
    local key = text .. "|" .. fnt .. "|" .. maxW
    local c = wrapCache[key]
    if c then return c end
    surface.SetFont(fnt)
    c = {}
    local line = ""
    for word in string.gmatch(text, "%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and surface.GetTextSize(try) > maxW then
            c[#c + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then c[#c + 1] = line end
    wrapCount = wrapCount + 1
    if wrapCount > 200 then wrapCache, wrapCount = {}, 0 end
    wrapCache[key] = c
    return c
end

-- A small filled diamond (reused points).
local diamond = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local function drawDiamond(cx, cy, r, col)
    diamond[1].x, diamond[1].y = cx, cy - r
    diamond[2].x, diamond[2].y = cx + r, cy
    diamond[3].x, diamond[3].y = cx, cy + r
    diamond[4].x, diamond[4].y = cx - r, cy
    draw.NoTexture()
    surface.SetDrawColor(col)
    surface.DrawPoly(diamond)
end

-- A chip's width (cached on the tag for this screen height).
local function chipW(tag)
    if tag.wFor ~= ScrH() then
        surface.SetFont(font(10, 700))
        tag.w = surface.GetTextSize(tag.text) + S(12)
        tag.wFor = ScrH()
    end
    return tag.w
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local PANEL = {}

function PANEL:SetPatient(ply)
    self.patient = ply
    self.refreshAt = nil
end

function PANEL:Patient()
    return IsValid(self.patient) and self.patient or LocalPlayer()
end

function PANEL:Init()
    self:SetSize(math.min(S(1344), ScrW() - S(40)), math.min(S(840), ScrH() - S(40)))
    self:Center()
    self:MakePopup()
    self:SetKeyboardInputEnabled(false)  -- keys keep working; the mouse is free
    self.opened = RealTime()
    self.kitRects = {}
    self.keyReleased = false
    -- Reused per part: picture colour, tags, row text / bar.
    self.partCol, self.tags, self.rowText, self.rowFrac, self.rowBar = {}, {}, {}, {}, {}
    for _, limb in ipairs(ROW_ORDER) do
        self.partCol[limb] = Color(255, 255, 255)
        self.tags[limb] = {}
        self.rowText[limb] = "fine"
        self.rowFrac[limb] = 0
    end
    self.fx, self.fxN = {}, 0
    self.tip, self.tipN = {}, 0
    self.title, self.subline = "HEALTH", ""
end

-- Columns, the body box, the screen polygons and the part rows. Only on a
-- size change.
function PANEL:PerformLayout(w, h)
    local s = S
    self.headH = s(80)
    -- (side columns shrink when the window is narrower than it wants,
    -- e.g. near-square or portrait screens)
    local k = math.min(1, w / s(1344))
    self.leftW, self.rightW = math.floor(s(440) * k), math.floor(s(390) * k)
    local top = self.headH
    self.colTop, self.colBot = top, h
    -- Body: centred in the left column, room under it for the caption.
    local bh = math.max(s(120), math.min(s(520), h - top - s(80), (self.leftW - s(120)) * 380 / 200))
    local bw = bh * 200 / 380
    self.bx, self.by, self.bw, self.bh = math.floor((self.leftW - bw) * 0.5), math.floor(top + (h - top - s(30) - bh) * 0.5), bw, bh
    self.polys = {}
    for limb, pieces in pairs(SHAPES) do
        local list = {}
        for j, poly in ipairs(pieces) do
            local verts = {}
            for i, pt in ipairs(poly) do
                local sx, sy = self:ToScreen(pt[1], pt[2])
                verts[i] = { x = sx, y = sy }
            end
            list[j] = verts
        end
        self.polys[limb] = list
    end
    -- Rows in the middle column.
    local mx = self.leftW + s(20)
    local mw = math.max(s(160), w - self.leftW - self.rightW - s(40))
    self.midX, self.midW = mx, mw
    self.rowRect = {}
    local y = top + s(46)
    for _, limb in ipairs(ROW_ORDER) do
        self.rowRect[limb] = { x = mx, y = y, w = mw, h = s(58) }
        y = y + s(64)
    end
    self.fxY = y + s(4)
    self.close = { x = w - s(24) - s(44), y = s(3) + math.floor((self.headH - s(3) - s(44)) * 0.5), w = s(44), h = s(44) }
    self.refreshAt = nil
end

-- Body box on screen.
function PANEL:BodyRect()
    if not self.bx then self:InvalidateLayout(true) end
    return self.bx, self.by, self.bw, self.bh
end

function PANEL:ToScreen(bx, by)
    local x, y, w, h = self.bx, self.by, self.bw, self.bh
    return x + bx / 200 * w, y + by / 380 * h
end

function PANEL:PartAt(mx, my)
    local x, y, w, h = self:BodyRect()
    local bx, by = (mx - x) / w * 200, (my - y) / h * 380
    for limb, pieces in pairs(SHAPES) do
        for _, poly in ipairs(pieces) do
            if pointIn(poly, bx, by) then return limb end
        end
    end
end

-- The part row under the mouse.
function PANEL:RowAt(mx, my)
    for limb, r in pairs(self.rowRect or {}) do
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then return limb end
    end
end

-- A part in the picture or a row.
function PANEL:LimbAt(mx, my)
    return self:PartAt(mx, my) or self:RowAt(mx, my)
end

local function inRect(r, x, y)
    return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- Adds an effect line (reused entries).
function PANEL:AddFx(text, col, time)
    local n = self.fxN + 1
    self.fxN = n
    local e = self.fx[n]
    if not e then e = {} self.fx[n] = e end
    e.text, e.col, e.time = text, col, time or ""
end

-- Adds a kit card (reused entries).
function PANEL:AddKit(n, id, name)
    local k = self.kitRects[n]
    if not k then k = {} self.kitRects[n] = k end
    k.id, k.name = id, name
    return k
end

-- Works out everything Paint shows (ten times a second).
function PANEL:Refresh()
    local s = S
    local w = self:GetWide()
    local ply = self:Patient()
    local me = ply == LocalPlayer()
    local medic = Med.IsMedic(LocalPlayer())
    local rough = not medic
    local hard = Med.Hardcore()
    self.rough, self.hard, self.me, self.medic = rough, hard, me, medic

    -- Header
    local job = ply:IsPlayer() and team.GetName(ply:Team()) or "Test dummy"
    local parts = job
    if not me then
        parts = parts .. "  ·  " .. math.floor(LocalPlayer():GetPos():Distance(ply:GetPos()) * 0.01905 + 0.5) .. " m away"
    end
    if medic then parts = parts .. "  ·  you see everything as a medic"
    else parts = parts .. (me and "  ·  you see roughly how hurt each part is" or "  ·  you see roughly how hurt they are") end
    self.showHp = medic or me
    -- Armour: your own, or a test dummy's (an NW2 copy); another player's
    -- isn't reliably known on this client.
    self.showAr = self.showHp and (me or ply.IsRhylibDummy == true)
    local barsW = self.showHp and (s(200 + 18) + (self.showAr and s(160 + 18) or 0)) or 0
    local titleW = math.max(s(80), self.close.x - s(24) - barsW - s(24))
    self.title = UI.Kit.Fit(me and "HEALTH" or ("HEALTH  ·  " .. string.upper(ply:Nick())), font(28, 700), titleW)
    self.subline = UI.Kit.Fit(parts, font(13), titleW)
    if self.showHp then
        local hp, max = Med.HealthOf(ply)
        hp = math.max(0, hp)
        self.hpText, self.hpMax, self.hpFrac = tostring(hp), "/ " .. max, math.Clamp(hp / math.max(max, 1), 0, 1)
        local ar = self.showAr and ply.Armor and ply:Armor() or 0
        local amax = ply.GetMaxArmor and ply:GetMaxArmor() or 100
        if amax <= 0 then amax = 100 end
        self.arText, self.arMax, self.arFrac = tostring(math.max(0, ar)), "/ " .. amax, math.Clamp(ar / amax, 0, 1)
    end

    -- Parts
    local t = Med.injOf and Med.injOf[ply]
    local limping = Med.Limping(ply)
    local detail = hard and (medic or me)
    for _, limb in ipairs(ROW_ORDER) do
        local p = t and t[limb] or Med.EMPTY_LIMB
        partColour(p, rough, self.partCol[limb])
        local tags = tagsFor(self.tags[limb], p, rough, limping, detail)
        -- (an illness shows on the head as an affliction; what it is takes a blood test)
        if limb == "head" and (medic or me) and Med.IllSigns then
            local _, stage = Med.IllSigns(ply)
            if stage then tags[#tags + 1] = ILL_TAGS[stage] end
        end
        local burn = p.burn or 0
        if rough then
            local f = math.max(p.dmg, burn * 0.8)
            self.rowText[limb] = f <= 0 and "fine" or (f < 50 and "hurt" or "badly hurt")
            self.rowFrac[limb] = f <= 0 and 0 or (f < 50 and 0.4 or 0.85)
            self.rowBar[limb] = f < 50 and COL_AMBER or COL_RED
        else
            local d = math.ceil(p.dmg)
            self.rowText[limb] = d > 0 and tostring(d) or "fine"
            self.rowFrac[limb] = math.Clamp(d / 100, 0, 1)
            self.rowBar[limb] = d >= 60 and COL_RED or (d >= 25 and COL_AMBER or COL_GREY_BAR)
        end
    end

    -- Effects
    self.fxN = 0
    local fxW = math.max(s(60), self.midW - s(28 + 24 + 90))
    local ff = font(14, 500)
    if t and (medic or me) then
        if Med.BleedLevel(ply) == 2 then self:AddFx("Losing blood fast", TAGS[1].col)
        elseif Med.BleedLevel(ply) == 1 then self:AddFx("Losing blood", TAGS[2].col) end
    end
    if (medic or me) and limping then
        self:AddFx("Limping: can't sprint", TAGS[3].col, math.ceil(Med.LimpLeft(ply)) .. " s")
    end
    if t and (medic or me) then
        -- (hardcore legs)
        if Med.BrokenLeg(ply) then self:AddFx("Broken leg: slow, can't sprint", TAGS[4].col)
        elseif hard and Med.NoSprint(ply) then self:AddFx("Hurt leg: can't sprint", COL_HURT) end
        if not Med.CanAim(ply) then self:AddFx(hard and "Broken or hurt arm: can't aim, shaky" or "Badly hurt arm: can't aim, shaky", COL_HURT)
        elseif Med.SpreadPenalty(ply, 1) > 0.05 then self:AddFx("Aim a little shaky", COL_AMBER) end
        -- (torso only: an illness lowers the cap too, and medics find that with a blood test)
        local cap = Med.StaminaCap(ply) / math.max(Med.IllStaminaMult and Med.IllStaminaMult(ply) or 1, 0.01)
        if cap < 0.99 then self:AddFx(string.format("Hurt torso: stamina capped at %d%%", cap * 100), COL_HURT) end
        -- Illness: you feel it, a medic sees the signs; the cause needs a blood test.
        local sign, stage
        if Med.IllSigns then sign, stage = Med.IllSigns(ply) end
        if sign then
            self:AddFx(me and "You feel unwell" or "Ill, cause unknown: draw blood and analyse it", ILL_TAGS[stage].col)
        end
    end
    if self.fxN == 0 then
        if not medic and not me then
            self:AddFx("A medic can tell you more.", COL_DIM)
        else
            self:AddFx(me and "None. You're in good shape." or "None.", UI.Colors.good)
        end
    end
    for i = 1, self.fxN do
        local e = self.fx[i]
        e.text = UI.Kit.Fit(e.text, ff, fxW)
    end
    cut(self.fx, self.fxN)

    -- Kit cards (same kits in both modes: medics first aid kit and medkit,
    -- troopers medkit)
    local rx = w - self.rightW + s(18)
    local rw = self.rightW - s(36)
    local textW = rw - s(24)
    local fDoes = font(13)
    local nk = 0
    local function card(id, name, does)
        nk = nk + 1
        local k = self:AddKit(nk, id, name)
        local n, fill = carried(id)
        k.count = n
        if hard then
            local allowed = medic or Med.ANYONE[id]
            if id == Med.MEDKIT and Med.Cfg("medkitMedicOnly") and not medic then allowed = false end
            k.usable = allowed and n > 0
            k.have = not allowed and "medics only" or (n > 0 and (n .. " carried") or "none carried")
            k.how = "Drag onto a body part"
        else
            k.usable = n > 0
            k.have = n > 0 and (n .. " carried") or "none carried"
            k.how = me and "Hold it · RMB: treat yourself" or "Hold it · LMB on them"
        end
        if fill and n > 0 and id == Med.FIRST_AID then k.have = k.have .. "  ·  " .. math.ceil(fill * 100) .. "% charge" end
        k.does = wrap(does, fDoes, textW)
    end
    if hard then
        if medic then
            card(Med.FIRST_AID, "First aid kit", "Fixes that part, sets the bone, treats burns, +" .. Med.Cfg("hcFirstAidLimbHealth") .. " health.")
            card(Med.MEDKIT, "Medkit", "Stops its bleeding, sets the bone, eases damage and burns, +" .. Med.Cfg("medkitHealMedic") .. ".")
        else
            card(Med.MEDKIT, "Medkit", "Stops that part's bleeding, +" .. Med.Cfg("medkitHeal") .. " health.")
        end
    else
        if medic then
            card(Med.FIRST_AID, "First aid kit", "Fixes every wound, heals what's missing.")
            card(Med.MEDKIT, "Medkit", "All bleeding, a limp, repairs parts, +" .. Med.Cfg("medkitHealMedic") .. ".")
        else
            card(Med.MEDKIT, "Medkit", "Stops the worst bleeding, +" .. Med.Cfg("medkitHeal") .. " health.")
        end
    end
    cut(self.kitRects, nk)
    local y = self.colTop + s(18) + s(30)
    for i = 1, nk do
        local k = self.kitRects[i]
        k.x, k.y, k.w = rx, y, rw
        k.h = s(12) + s(44) + s(8) + #k.does * s(19) + s(4) + s(14) + s(12)
        y = y + k.h + s(10)
    end

    -- Hint box
    local hint
    if hard then
        hint = (medic and "" or "Broken bones and burns need a medic. ") .. "Parts heal by themselves only with no bleeding, fracture or burns."
    else
        hint = (medic and "" or "A medic can fix limps and hurt limbs. ") .. "Hurt parts heal by themselves once they stop bleeding; a limp wears off."
    end
    self.hint = wrap(hint, font(12), rw - s(24) - s(26))
    self.hintH = s(20) + #self.hint * s(18)

    if self.hover then self:BuildTip(self.hover) end
end

-- The tooltip lines for a part: { text, col } entries, reused.
function PANEL:TipLine(text, col)
    local n = self.tipN + 1
    self.tipN = n
    local e = self.tip[n]
    if not e then e = {} self.tip[n] = e end
    e[1], e[2] = text, col
end

function PANEL:BuildTip(limb)
    self.tipFor = limb
    self.tipN = 0
    local ply = self:Patient()
    local t = Med.injOf and Med.injOf[ply]
    local p = t and t[limb] or Med.EMPTY_LIMB
    local burn = p.burn or 0
    self:TipLine(Med.LIMB_NAMES[limb], COL_TEXT)
    if self.rough then
        local f = math.max(p.dmg, burn * 0.8)
        self:TipLine(f <= 0 and "Looks fine" or (f < 50 and "Hurt" or "Badly hurt"), COL_SOFT)
        if p.bleed > 0 then self:TipLine("Bleeding", TAGS[2].col) end
        if ply == LocalPlayer() and p.frac then self:TipLine("Fractured", TAGS[4].col) end
    else
        self:TipLine("Damage " .. math.ceil(p.dmg) .. "%", COL_SOFT)
        if p.bleed == 2 then self:TipLine("Heavy bleeding", TAGS[1].col) elseif p.bleed == 1 then self:TipLine("Light bleeding", TAGS[2].col) end
        if p.frac then self:TipLine("Fractured", TAGS[4].col) end
        if burn > 0 then self:TipLine("Burns " .. math.ceil(burn) .. "%", COL_BURN) end
    end
    if p.limp and Med.Limping(ply) then
        self:TipLine("Limping: can't sprint  ·  " .. math.ceil(Med.LimpLeft(ply)) .. " s left", TAGS[3].col)
    end
    cut(self.tip, self.tipN)
    -- Box width from the widest line.
    local bw = S(190)
    for i = 1, self.tipN do
        surface.SetFont(font(i == 1 and 14 or 12, i == 1 and 700 or 400))
        bw = math.max(bw, surface.GetTextSize(self.tip[i][1]) + S(26))
    end
    self.tipW = bw
end

-- A health / armour bar with the number on the right.
local function bar(x, y, bw, label, num, max, frac, numCol, fillCol)
    local s = S
    draw.SimpleText(label, font(10, 700), x, y + s(9), COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    surface.SetFont(font(12))
    local mw = surface.GetTextSize(max)
    draw.SimpleText(max, font(12), x + bw, y + s(9), COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(num, font(16, 700), x + bw - mw - s(5), y + s(8), numCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    local by, bh = y + s(22), s(8)
    surface.SetDrawColor(COL_PAGE)
    surface.DrawRect(x, by, bw, bh)
    surface.SetDrawColor(fillCol)
    surface.DrawRect(x + 1, by + 1, math.floor((bw - 2) * frac), bh - 2)
    surface.SetDrawColor(COL_BORDER)
    surface.DrawOutlinedRect(x, by, bw, bh)
end

function PANEL:Paint(w, h)
    local s = S
    if not self.polys then self:InvalidateLayout(true) end
    if not self.refreshAt or RealTime() >= self.refreshAt then
        self.refreshAt = RealTime() + 0.1
        self:Refresh()
    end
    local mx, my = self:CursorPos()
    local hoverPic = self:PartAt(mx, my)
    local hover = hoverPic or self:RowAt(mx, my)
    self.hoverPic = hoverPic
    if hover ~= self.hover then
        self.hover = hover
        if hover then self:BuildTip(hover) end
    end

    -- Frame
    surface.SetDrawColor(COL_BG)
    surface.DrawRect(0, 0, w, h)
    local hh = self.headH
    surface.SetDrawColor(COL_CARD)
    surface.DrawRect(0, 0, w, hh)
    surface.SetDrawColor(COL_RED)
    surface.DrawRect(0, 0, w, s(3))
    surface.SetDrawColor(COL_EDGE)
    surface.DrawRect(0, hh - 1, w, 1)

    -- Header
    local tx = s(24)
    local mid = s(3) + (hh - s(3)) * 0.5
    draw.SimpleText(self.title, font(28, 700), tx, mid - s(9), COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(self.subline, font(13), tx, mid + s(15), COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local c = self.close
    if self.showHp and self.hpText then
        local ax = c.x
        if self.showAr then
            ax = c.x - s(18) - s(160)
            bar(ax, mid - s(16), s(160), "ARMOUR", self.arText, self.arMax, self.arFrac, COL_BLUE, COL_BLUE)
        end
        bar(ax - s(18) - s(200), mid - s(16), s(200), "HEALTH", self.hpText, self.hpMax, self.hpFrac, COL_RED_TEXT, COL_RED)
    end
    local overClose = inRect(c, mx, my)
    surface.SetDrawColor(overClose and COL_SEL or COL_CARD)
    surface.DrawRect(c.x, c.y, c.w, c.h)
    surface.SetDrawColor(overClose and COL_BLUE or COL_BORDER)
    surface.DrawOutlinedRect(c.x, c.y, c.w, c.h)
    local cx, cy, r = c.x + c.w * 0.5, c.y + c.h * 0.5, s(7)
    surface.SetDrawColor(overClose and COL_TEXT or COL_DIM)
    for o = 0, 1 do
        surface.DrawLine(cx - r + o, cy - r, cx + r + o, cy + r)
        surface.DrawLine(cx + r + o, cy - r, cx - r + o, cy + r)
    end

    -- Side columns
    local top = self.colTop
    surface.SetDrawColor(COL_SIDE)
    surface.DrawRect(0, top, self.leftW, h - top)
    surface.DrawRect(w - self.rightW, top, self.rightW, h - top)
    surface.SetDrawColor(COL_EDGE)
    surface.DrawRect(self.leftW - 1, top, 1, h - top)
    surface.DrawRect(w - self.rightW, top, 1, h - top)

    self:PaintBody(hover)
    self:PaintRows(hover)
    self:PaintTreatment(w, h, mx, my)

    surface.SetDrawColor(COL_EDGE)
    surface.DrawOutlinedRect(0, 0, w, h)
end

-- Left: the body picture and its tags.
function PANEL:PaintBody(hover)
    local s = S
    draw.NoTexture()
    for limb, list in pairs(self.polys) do
        local col = self.partCol[limb]
        if self.drag and hover == limb then col = COL_DROP end
        local lit = hover == limb
        for j = 1, #list do
            local verts = list[j]
            surface.SetDrawColor(col)
            surface.DrawPoly(verts)
            surface.SetDrawColor(lit and COL_BLUE or COL_OUTLINE)
            local n = #verts
            for i = 1, n do
                local a, b = verts[i], verts[i % n + 1]
                surface.DrawLine(a.x, a.y, b.x, b.y)
                surface.DrawLine(a.x + 1, a.y, b.x + 1, b.y)
                if lit then surface.DrawLine(a.x, a.y + 1, b.x, b.y + 1) end
            end
        end
        local tags = self.tags[limb]
        if #tags > 0 then
            local at = TAG_AT[limb]
            local tx, ty = self:ToScreen(at[1], at[2])
            for i = 1, #tags do
                draw.SimpleText(tags[i].text, font(11, 700), tx, ty + (i - 1) * s(14), tags[i].col, at[3] > 0 and TEXT_ALIGN_LEFT or TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end
    draw.SimpleText(self.hard and "Seen from the front  ·  drag a kit onto a part" or "Seen from the front  ·  hover a part", font(11), self.leftW * 0.5, self:GetTall() - s(18), COL_LABEL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Middle: BODY PARTS rows and the EFFECTS card.
function PANEL:PaintRows(hover)
    local s = S
    local x0, mw = self.midX, self.midW
    draw.SimpleText("BODY PARTS", font(14, 700), x0, self.colTop + s(26), COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local fName, fChip, fNum = font(15, 700), font(10, 700), font(13, 700)
    for _, limb in ipairs(ROW_ORDER) do
        local r = self.rowRect[limb]
        local lit = hover == limb
        surface.SetDrawColor(lit and COL_SEL or COL_CARD)
        surface.DrawRect(r.x, r.y, r.w, r.h)
        if lit then
            surface.SetDrawColor(COL_BLUE)
            surface.DrawOutlinedRect(r.x, r.y, r.w, r.h)
        end
        local cyy = r.y + r.h * 0.5
        draw.SimpleText(Med.LIMB_NAMES[limb], fName, r.x + s(14), cyy, COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local text = self.rowText[limb]
        draw.SimpleText(text, fNum, r.x + r.w - s(14), cyy, text == "fine" and COL_LABEL or COL_TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        -- Damage bar and chips between the name and the number.
        local bx = r.x + s(14) + s(100)
        local bw = math.max(s(30), r.w - s(14) - s(100) - s(14) - s(90))
        local by = r.y + s(13)
        surface.SetDrawColor(COL_PAGE)
        surface.DrawRect(bx, by, bw, s(6))
        local f = self.rowFrac[limb]
        if f > 0 then
            surface.SetDrawColor(self.rowBar[limb])
            surface.DrawRect(bx, by, math.max(1, math.floor(bw * f)), s(6))
        end
        local tags = self.tags[limb]
        local cx, chy, chh = bx, by + s(13), s(18)
        for i = 1, #tags do
            local tag = tags[i]
            local tw = chipW(tag)
            if cx + tw > bx + bw then break end
            surface.SetDrawColor(tag.col)
            surface.DrawOutlinedRect(cx, chy, tw, chh)
            draw.SimpleText(tag.text, fChip, cx + tw * 0.5, chy + chh * 0.5, tag.col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cx = cx + tw + s(6)
        end
    end
    -- Effects
    local ey = self.fxY
    local eh = s(44) + self.fxN * s(24)
    surface.SetDrawColor(COL_CARD)
    surface.DrawRect(x0, ey, mw, eh)
    draw.SimpleText("EFFECTS", font(14, 700), x0 + s(14), ey + s(20), COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    for i = 1, self.fxN do
        local e = self.fx[i]
        local ly = ey + s(44) + (i - 1) * s(24)
        drawDiamond(x0 + s(18), ly, s(5), e.col)
        draw.SimpleText(e.text, font(14, 500), x0 + s(32), ly, e.col == COL_DIM and COL_DIM or COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if e.time ~= "" then
            draw.SimpleText(e.time, font(12), x0 + mw - s(14), ly, COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
end

-- Right: TREATMENT cards (self.kitRects, also the drag sources in
-- hardcore) and the hint box.
function PANEL:PaintTreatment(w, h, mx, my)
    local s = S
    local rx = w - self.rightW + s(18)
    local rw = self.rightW - s(36)
    draw.SimpleText("TREATMENT", font(14, 700), rx, self.colTop + s(26), COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local hard = self.hard
    for i = 1, #self.kitRects do
        local k = self.kitRects[i]
        local over = hard and not self.drag and k.usable and inRect(k, mx, my)
        local dragging = self.drag and self.drag.id == k.id
        surface.SetDrawColor(over and COL_SEL or COL_CARD)
        surface.DrawRect(k.x, k.y, k.w, k.h)
        surface.SetDrawColor((over or dragging) and COL_BLUE or COL_BORDER)
        surface.DrawOutlinedRect(k.x, k.y, k.w, k.h)
        local on = k.count > 0
        -- Icon square with a cross
        local ix, iy, is = k.x + s(12), k.y + s(12), s(44)
        surface.SetDrawColor(on and COL_ICON_BG or COL_PAGE)
        surface.DrawRect(ix, iy, is, is)
        surface.SetDrawColor(on and COL_RED or COL_BORDER)
        surface.DrawOutlinedRect(ix, iy, is, is)
        local arm, th = s(10), math.max(2, s(3))
        surface.DrawRect(ix + is * 0.5 - th * 0.5, iy + is * 0.5 - arm, th, arm * 2)
        surface.DrawRect(ix + is * 0.5 - arm, iy + is * 0.5 - th * 0.5, arm * 2, th)
        local nx = ix + is + s(12)
        draw.SimpleText(k.name, font(15, 700), nx, iy + s(13), on and COL_TEXT or COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(k.have, font(12), nx, iy + s(32), COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local ly = iy + is + s(8) + s(9)
        for j = 1, #k.does do
            draw.SimpleText(k.does[j], font(13), k.x + s(12), ly, on and COL_SOFT or COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            ly = ly + s(19)
        end
        draw.SimpleText(k.how, font(11), k.x + s(12), k.y + k.h - s(12) - s(7), (not hard or k.usable) and COL_LABEL or COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    -- Hint box at the bottom
    if self.hint then
        local hh = self.hintH
        local hy = h - s(18) - hh
        surface.SetDrawColor(COL_HINT_BG)
        surface.DrawRect(rx, hy, rw, hh)
        surface.SetDrawColor(COL_HINT_EDGE)
        surface.DrawOutlinedRect(rx, hy, rw, hh)
        local icx, icy = rx + s(12) + s(8), hy + s(10) + s(9)
        surface.DrawCircle(icx, icy, s(8), COL_AMBER.r, COL_AMBER.g, COL_AMBER.b, 255)
        surface.SetDrawColor(COL_AMBER)
        surface.DrawRect(icx - 1, icy - s(4), 2, s(5))
        surface.DrawRect(icx - 1, icy + s(3), 2, 2)
        for j = 1, #self.hint do
            draw.SimpleText(self.hint[j], font(12), rx + s(12) + s(26), hy + s(10) + (j - 0.5) * s(18), COL_HINT_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
end

function PANEL:KitAt(mx, my)
    for _, k in ipairs(self.kitRects or {}) do
        if inRect(k, mx, my) then return k end
    end
end

function PANEL:PaintOver(w, h)
    local mx, my = self:CursorPos()
    if self.drag then
        local text = self.drag.name
        surface.SetFont(font(13, 600))
        local tw = surface.GetTextSize(text)
        surface.SetDrawColor(COL_CARD)
        surface.DrawRect(mx + 10, my + 6, tw + S(16), S(26))
        surface.SetDrawColor(COL_DROP)
        surface.DrawOutlinedRect(mx + 10, my + 6, tw + S(16), S(26))
        draw.SimpleText(text, font(13, 600), mx + 10 + S(8), my + 6 + S(13), COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return
    end
    -- Tooltip for the part under the mouse in the picture.
    local limb = self.hoverPic
    if not limb or self.tipFor ~= limb or self.tipN == 0 then return end
    local bw, lh = self.tipW, S(18)
    local bh = self.tipN * lh + S(16)
    local x, y = math.min(mx + 16, w - bw - 4), math.min(my + 16, h - bh - 4)
    surface.SetDrawColor(COL_BG)
    surface.DrawRect(x, y, bw, bh)
    surface.SetDrawColor(COL_BLUE)
    surface.DrawOutlinedRect(x, y, bw, bh)
    for i = 1, self.tipN do
        local l = self.tip[i]
        draw.SimpleText(l[1], font(i == 1 and 14 or 12, i == 1 and 700 or 400), x + S(12), y + S(8) + (i - 0.5) * lh,
            l[2], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

-- Close button; hardcore: drag a kit card onto a body part.
function PANEL:OnMousePressed(code)
    if code ~= MOUSE_LEFT then return end
    local mx, my = self:CursorPos()
    if inRect(self.close, mx, my) then self:Remove() return end
    if not Med.Hardcore() then return end
    local k = self:KitAt(mx, my)
    if k and k.usable then
        self.drag = { id = k.id, name = k.name }
        self:MouseCapture(true)
    end
end

function PANEL:OnMouseReleased(code)
    if code ~= MOUSE_LEFT or not self.drag then return end
    self:MouseCapture(false)
    local row = self.drag
    self.drag = nil
    local limb = self:LimbAt(self:CursorPos())
    local kind = Med.TREAT_KIND[row.id]
    if not limb or not kind or not Med.Hardcore() then return end
    Rhylib.Net.Start("med.treat")
    net.WriteEntity(self:Patient())
    net.WriteUInt(Med.LIMB_INDEX[limb], 3)
    net.WriteUInt(kind, Med.TREAT_BITS)
    net.SendToServer()
end

function PANEL:Think()
    -- The key again (a fresh press) closes it.
    local code = input.GetKeyCode(keyVar:GetString())
    local down = code and code > 0 and input.IsKeyDown(code)
    if not down then
        self.keyReleased = true
    elseif self.keyReleased and not self.keyWasDown then
        self:Remove()
        return
    end
    self.keyWasDown = down
    if not LocalPlayer():Alive() then self:Remove() return end
    -- Someone else's: close when they're gone or you walk away.
    local p = self.patient
    if p ~= nil then
        local r = Rhylib.Config.Get("medical", "viewRange") * 1.5
        if not IsValid(p) or not p:Alive() or LocalPlayer():GetPos():DistToSqr(p:GetPos()) > r * r then self:Remove() end
    end
end

function PANEL:OnRemove()
    if self.patient ~= nil then
        Rhylib.Net.Start("med.view")
        net.WriteEntity(NULL)
        net.SendToServer()
    end
end

vgui.Register("RhylibInjuries", PANEL, "EditablePanel")

-- Who you're looking at, close enough to examine (standing or downed).
local function lookTarget()
    local me = LocalPlayer()
    local r = Rhylib.Config.Get("medical", "viewRange")
    local tr = me:GetEyeTrace()
    local e = tr.Entity
    local L = Rhylib.Lying
    if L and L.Owner and L.Owner(e) then e = L.Owner(e) end   -- a lying player's ragdoll
    if Med.IsPatient(e) and e:Alive() and me:GetPos():DistToSqr(e:GetPos()) <= r * r then return e end
    return Med.FindDowned and Med.FindDowned(me, Med.clientDown) or nil
end

-- Med.OpenInjuries(target): opens the injury menu for target (a player or
-- a test dummy),
-- or your own with nil / yourself. Does nothing while dead, downed or in
-- the simplified system. Client only.
-- Example: Rhylib.Medical.OpenInjuries(LocalPlayer():GetEyeTrace().Entity)
function Med.OpenInjuries(target)
    if IsValid(Med.injuryPanel) then Med.injuryPanel:Remove() end
    local me = LocalPlayer()
    if not me:Alive() or Med.IsDown(me) then return end
    if Med.Simple() then return end   -- (simplified medical system: no injury menu)
    if target == me then target = nil end
    local p = vgui.Create("RhylibInjuries")
    if IsValid(target) then
        p:SetPatient(target)
        Rhylib.Net.Start("med.view")
        net.WriteEntity(target)
        net.SendToServer()
    end
    Med.injuryPanel = p
end

-- Med.ToggleInjuries(): closes the menu, or opens it on whoever you look
-- at within viewRange (else your own). The H key and rhylib_injuries.
function Med.ToggleInjuries()
    if IsValid(Med.injuryPanel) then
        Med.injuryPanel:Remove()
        return
    end
    Med.OpenInjuries(lookTarget())
end
concommand.Add("rhylib_injuries", Med.ToggleInjuries)

-- Open with the key (not while typing or in a menu).
local wasDown = false
Rhylib.Hook.Add("Think", "medical.injurykey", function()
    if IsValid(Med.injuryPanel) then
        if Med.Simple() then Med.injuryPanel:Remove() end   -- (switched to the simplified system)
        wasDown = true
        return
    end
    local code = input.GetKeyCode(keyVar:GetString())
    local down = code and code > 0 and input.IsKeyDown(code)
    if down and not wasDown and not vgui.GetKeyboardFocus() and not gui.IsGameUIVisible() and not gui.IsConsoleVisible() then
        Med.ToggleInjuries()
    end
    wasDown = down
end)

-- Esc closes it (rhylib_menus), and the key is in the settings.
Rhylib.Hook.Add("InitPostEntity", "medical.injurymenu", function()
    local Menus = Rhylib.Menus
    if not Menus then return end
    if Menus.RegisterCloser then
        Menus.RegisterCloser("injuries", function()
            if IsValid(Med.injuryPanel) then
                Med.injuryPanel:Remove()
                return true
            end
            return false
        end)
    end
    if Menus.AddSetting then
        Menus.AddSetting("Medical", { id = "med.key", order = 10, title = "Injury menu key", kind = "key", convar = "rhylib_medical_key",
            showIf = function() return not Med.Simple() end })
    end
end)

-- A kit's click on the server: open the menu (someone's, or your own).
Rhylib.Net.Receive("med.open", function()
    local p = net.ReadEntity()
    Med.OpenInjuries(IsValid(p) and p or nil)
end)
