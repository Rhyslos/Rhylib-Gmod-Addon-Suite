--[[
    The injury menu (H, convar rhylib_medical_key). Press it while looking
    at someone close to see their body instead of yours. Left: the body,
    each part white when fine and redder the more it's hurt, with small
    tags (bleeding, limping); hover a part for details. Middle: the
    effects. Right: how to treat it with the kits you carry (treating is
    the kit's click, worst problem first: this window only shows).

    Hardcore (Med.Hardcore()): parts also show FRACTURE and BURNS (orange
    shade), and the right column lists your kits: drag one onto a body
    part to treat that part (med.treat: patient, part 3 bits, kit
    Med.TREAT_BITS). A kit's click opens this window (med.open).

    Medics see exact damage, health and effects. Troopers see roughly how
    hurt each part is and whether it bleeds (and their own effects).

    Same look as the other Rhylib windows (dark plates, caps labels).

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

local COL_BG = Color(14, 16, 15, 242)
local COL_HEADER = Color(22, 25, 23, 255)
local COL_EDGE = Color(0, 0, 0, 230)
local COL_LIGHT = Color(170, 176, 180, 70)
local COL_TICK = Color(170, 176, 180, 150)
local COL_LABEL = Color(140, 142, 136)
local COL_FINE = Color(226, 228, 222)
local COL_HURT = Color(214, 48, 40)
local COL_OUTLINE = Color(0, 0, 0, 200)
local COL_BURN = Color(232, 132, 48)
local COL_DROP = Color(133, 183, 235)
local COL_ROW = Color(20, 23, 21)
local COL_ROW_HOVER = Color(32, 40, 48)

local TAGS = {
    { key = "bleed2", text = "HEAVY BLEEDING", col = Color(226, 60, 50) },
    { key = "bleed1", text = "BLEEDING", col = Color(226, 110, 90) },
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

local function pointIn(poly, x, y)
    -- Convex polygon, clockwise on screen: inside if left of no edge.
    local n = #poly
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        if (b[1] - a[1]) * (y - a[2]) - (b[2] - a[2]) * (x - a[1]) < 0 then return false end
    end
    return true
end

local function partColour(p, rough)
    local burn = p.burn or 0
    local f = math.Clamp(math.max(p.dmg, burn * 0.8) / 100, 0, 1)
    -- Troopers only see three shades: fine, hurt, badly hurt.
    if rough then f = f <= 0 and 0 or (f < 0.5 and 0.45 or 1) end
    local base = burn > p.dmg and COL_BURN or COL_HURT   -- (hardcore burns: orange)
    return Color(Lerp(f, COL_FINE.r, base.r), Lerp(f, COL_FINE.g, base.g), Lerp(f, COL_FINE.b, base.b))
end

-- Illness by stage (cl_50_illness.lua Med.IllSigns), drawn on the head.
local ILL_TAGS = {
    { key = "ill1", text = "UNWELL", col = Color(170, 200, 120) },
    { key = "ill2", text = "ILL", col = Color(190, 210, 90) },
    { key = "ill3", text = "SEVERELY ILL", col = Color(214, 225, 60) },
}

-- (detail: fractures and burns shown, for medics and your own body)
local function tagsFor(p, rough, limping, detail)
    local out = {}
    if rough then
        if p.bleed > 0 then out[#out + 1] = TAGS[2] end
    elseif p.bleed == 2 then out[#out + 1] = TAGS[1] elseif p.bleed == 1 then out[#out + 1] = TAGS[2] end
    if p.limp and limping then out[#out + 1] = TAGS[3] end
    if detail then
        if p.frac then out[#out + 1] = TAGS[4] end
        if (p.burn or 0) > 0 then out[#out + 1] = TAGS[5] end
    end
    return out
end

-- How many of an item you carry (rhylib_inventory's client copy).
local function carried(id)
    local Inv = Rhylib.Inventory
    local n = 0
    if Inv and Inv.byUid then
        for _, inst in pairs(Inv.byUid) do
            if inst.id == id then n = n + (inst.count or 1) end
        end
    elseif LocalPlayer():HasWeapon(id) then
        n = 1
    end
    return n
end

-- Hardcore: the kits you can drag onto a part: { id, name, count, usable,
-- sub }. Medics: first aid kit and medkit; troopers: medkit.
local function kitRows(medic)
    local rows = {}
    local function row(id, name)
        local n = carried(id)
        local allowed = medic or Med.ANYONE[id]
        if id == Med.MEDKIT and Med.Cfg("medkitMedicOnly") and not medic then allowed = false end
        local sub = not allowed and "medics only" or (n > 0 and ("x" .. n) or "none carried")
        rows[#rows + 1] = { id = id, name = name, count = n, usable = allowed and n > 0, sub = sub }
    end
    if medic then row(Med.FIRST_AID, "First aid kit") end
    row(Med.MEDKIT, "Medkit")
    return rows
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local PANEL = {}

function PANEL:SetPatient(ply)
    self.patient = ply
end

function PANEL:Patient()
    return IsValid(self.patient) and self.patient or LocalPlayer()
end

function PANEL:Init()
    self:SetSize(S(960), S(560))
    self:Center()
    self:MakePopup()
    self:SetKeyboardInputEnabled(false)  -- keys keep working; the mouse is free
    self.opened = RealTime()
    self.kitRects = {}
    self.keyReleased = false
end

-- Body box on screen.
function PANEL:BodyRect()
    local h = S(440)
    local w = h * 200 / 380
    return S(40), S(70), w, h
end

function PANEL:ToScreen(bx, by)
    local x, y, w, h = self:BodyRect()
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

function PANEL:Paint(w, h)
    local s = S
    -- Frame
    surface.SetDrawColor(COL_BG)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(COL_HEADER)
    surface.DrawRect(0, 0, w, s(40))
    surface.SetDrawColor(UI.Colors.accent.r, UI.Colors.accent.g, UI.Colors.accent.b, 170)
    surface.DrawRect(0, s(40), w, 1)
    surface.SetDrawColor(COL_EDGE)
    surface.DrawOutlinedRect(0, 0, w, h)
    surface.SetDrawColor(COL_LIGHT)
    surface.DrawLine(1, 1, w - 1, 1)
    local ply = self:Patient()
    local me = ply == LocalPlayer()
    local medic = Med.IsMedic(LocalPlayer())
    local rough = not medic
    local hard = Med.Hardcore()
    self.rough = rough
    self.hard = hard
    draw.SimpleText(me and "INJURIES" or ("INJURIES  ·  " .. ply:Nick()), font(17, 700), s(14), s(20), UI.Colors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if medic or me then
        local hp, max = Med.HealthOf(ply)
        draw.SimpleText("Health " .. math.max(0, hp) .. " / " .. max, font(14, 600), w - s(14), s(20), UI.Colors.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local mx, my = self:CursorPos()
    local hover = self:PartAt(mx, my)
    self.hover = hover
    local t = Med.injOf and Med.injOf[ply]

    -- Body
    draw.NoTexture()
    for limb, pieces in pairs(SHAPES) do
        local p = t and t[limb] or Med.EMPTY_LIMB
        local col = partColour(p, rough)
        if self.drag and hover == limb then col = COL_DROP end
        for _, poly in ipairs(pieces) do
            local verts = {}
            for i, pt in ipairs(poly) do
                local sx, sy = self:ToScreen(pt[1], pt[2])
                verts[i] = { x = sx, y = sy }
            end
            surface.SetDrawColor(col)
            surface.DrawPoly(verts)
            surface.SetDrawColor(hover == limb and UI.Colors.accent or COL_OUTLINE)
            for i = 1, #verts do
                local a, b = verts[i], verts[i % #verts + 1]
                surface.DrawLine(a.x, a.y, b.x, b.y)
            end
        end
        -- Tags (an illness shows on the head as an affliction; what it is
        -- takes a blood test)
        local tags = tagsFor(p, rough, Med.Limping(ply), hard and (medic or me))
        if limb == "head" and (medic or me) and Med.IllSigns then
            local _, stage = Med.IllSigns(ply)
            if stage then tags[#tags + 1] = ILL_TAGS[stage] end
        end
        local at = TAG_AT[limb]
        local tx, ty = self:ToScreen(at[1], at[2])
        for i, tag in ipairs(tags) do
            draw.SimpleText(tag.text, font(11, 700), tx, ty + (i - 1) * s(14), tag.col, at[3] > 0 and TEXT_ALIGN_LEFT or TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    -- Effects under the body
    local ex, ey = s(300), s(80)
    draw.SimpleText("EFFECTS", font(12, 700), ex, ey, COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local lines = {}
    if t and (medic or me) then
        if Med.BleedLevel(ply) == 2 then lines[#lines + 1] = { "Losing blood fast", TAGS[1].col }
        elseif Med.BleedLevel(ply) == 1 then lines[#lines + 1] = { "Losing blood", TAGS[2].col } end
    end
    if (medic or me) and Med.Limping(ply) then
        lines[#lines + 1] = { string.format("Limping: can't sprint (%d s)", math.ceil(Med.LimpLeft(ply))), TAGS[3].col }
    end
    if t and (medic or me) then
        -- (hardcore legs)
        if Med.BrokenLeg(ply) then lines[#lines + 1] = { "Broken leg: slow, can't sprint", TAGS[4].col }
        elseif hard and Med.NoSprint(ply) then lines[#lines + 1] = { "Hurt leg: can't sprint", COL_HURT } end
        if not Med.CanAim(ply) then lines[#lines + 1] = { hard and "Broken or hurt arm: can't aim, shaky" or "Badly hurt arm: can't aim, shaky", COL_HURT }
        elseif Med.SpreadPenalty(ply, 1) > 0.05 then lines[#lines + 1] = { "Aim a little shaky", COL_LABEL } end
        -- (torso only: an illness lowers the cap too, and medics find that with a blood test)
        local cap = Med.StaminaCap(ply) / math.max(Med.IllStaminaMult and Med.IllStaminaMult(ply) or 1, 0.01)
        if cap < 0.99 then lines[#lines + 1] = { string.format("Hurt torso: stamina capped at %d%%", cap * 100), COL_HURT } end
        -- Illness: you feel it, a medic sees the signs; the cause needs a blood test.
        local sign, stage
        if Med.IllSigns then sign, stage = Med.IllSigns(ply) end
        if sign then
            lines[#lines + 1] = { me and "You feel unwell" or "Ill, cause unknown: draw blood and analyse it", ILL_TAGS[stage].col }
        end
    end
    if #lines == 0 then
        if not medic and not me then
            lines[1] = { "A medic can tell you more.", UI.Colors.textDim }
        else
            lines[1] = { me and "None. You're in good shape." or "None.", UI.Colors.good }
        end
    end
    for i, l in ipairs(lines) do
        draw.SimpleText(l[1], font(14, 500), ex, ey + s(10) + i * s(22), l[2], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- How to treat it, with what you carry (right column)
    local lx, ly = w - s(310), s(70)
    if hard then
        self:PaintKits(lx, ly, mx, my, medic)
    else
        if self.kitAt ~= nil or (self.kitRects and next(self.kitRects)) then
            self.kitRects, self.kitAt = {}, nil
        end
        draw.SimpleText("TREATMENT", font(12, 700), lx, ly + s(8), COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local help = {}
        local function kit(name, n, text)
            help[#help + 1] = { name .. (n > 0 and ("  ·  " .. n) or "  ·  none carried"), n > 0 and UI.Colors.text or UI.Colors.textDim, true }
            help[#help + 1] = { text, UI.Colors.textDim }
        end
        local who = me and "Hold the kit, right click: yourself." or "Hold the kit, left click on them."
        if medic then
            kit("First aid kit", carried(Med.FIRST_AID), "Fixes every wound, heals what's missing.")
            kit("Medkit", carried(Med.MEDKIT), "All bleeding, a limp, repairs parts, +" .. Med.Cfg("medkitHealMedic") .. ".")
        else
            kit("Medkit", carried(Med.MEDKIT), "Stops the worst bleeding, +" .. Med.Cfg("medkitHeal") .. " health.")
            help[#help + 1] = { "A medic can fix limps and hurt limbs.", UI.Colors.textDim }
        end
        help[#help + 1] = { who, UI.Colors.textDim }
        help[#help + 1] = { "Hurt parts heal by themselves once", UI.Colors.textDim }
        help[#help + 1] = { "they stop bleeding; a limp wears off.", UI.Colors.textDim }
        local yy = ly + s(24)
        for _, l in ipairs(help) do
            yy = yy + s(l[3] and 26 or 20)
            draw.SimpleText(l[1], font(l[3] and 14 or 13, l[3] and 600 or 400), lx, yy, l[2], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    surface.SetDrawColor(COL_EDGE)
    surface.DrawLine(lx - s(16), s(60), lx - s(16), h - s(20))

    -- Corner ticks
    local tk = s(7)
    surface.SetDrawColor(COL_TICK)
    surface.DrawRect(0, h - 2, tk, 2) surface.DrawRect(0, h - tk, 2, tk)
    surface.DrawRect(w - tk, h - 2, tk, 2) surface.DrawRect(w - 2, h - tk, 2, tk)
end

-- Hardcore: the kit rows to drag from (self.kitRects for the mouse), then
-- what each kit does.
function PANEL:PaintKits(lx, ly, mx, my, medic)
    local s = S
    local lw, rh = s(290), s(40)
    draw.SimpleText("KITS  ·  DRAG ONTO A BODY PART", font(12, 700), lx, ly + s(8), COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    -- (the rows and their boxes are worked out a few times a second, not
    -- every frame)
    if not self.kitAt or RealTime() >= self.kitAt then
        self.kitAt = RealTime() + 0.25
        self.kitRects = {}
        local y0 = ly + s(24)
        for _, r in ipairs(kitRows(medic)) do
            self.kitRects[#self.kitRects + 1] = { x = lx, y = y0, w = lw, h = rh, row = r }
            y0 = y0 + rh + s(4)
        end
    end
    local ry = ly + s(24)
    for _, k in ipairs(self.kitRects) do
        local r = k.row
        ry = k.y
        local over = not self.drag and mx >= lx and mx <= lx + lw and my >= ry and my <= ry + rh
        surface.SetDrawColor(over and r.usable and COL_ROW_HOVER or COL_ROW)
        surface.DrawRect(lx, ry, lw, rh)
        surface.SetDrawColor(COL_EDGE)
        surface.DrawOutlinedRect(lx, ry, lw, rh)
        if r.usable then
            surface.SetDrawColor(96, 186, 126)
            surface.DrawRect(lx + 1, ry + 1, s(3), rh - 2)
        end
        draw.SimpleText(r.name, font(14, r.usable and 600 or 400), lx + s(12), ry + rh * 0.5, r.usable and UI.Colors.text or UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(r.sub, font(12), lx + lw - s(10), ry + rh * 0.5, UI.Colors.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        ry = ry + rh + s(4)
    end
    local help
    if medic then
        help = {
            "First aid kit: fixes that part, sets",
            "the bone, treats burns, +" .. Med.Cfg("hcFirstAidLimbHealth") .. " health.",
            "Medkit: stops its bleeding, sets the",
            "bone, eases damage and burns, +" .. Med.Cfg("medkitHealMedic") .. ".",
        }
    else
        help = {
            "Medkit: stops that part's bleeding,",
            "+" .. Med.Cfg("medkitHeal") .. " health.",
            "Broken bones and burns need a medic.",
        }
    end
    help[#help + 1] = "Parts heal by themselves only with no"
    help[#help + 1] = "bleeding, fracture or burns."
    local yy = ry + s(8)
    draw.SimpleText("TREATMENT", font(12, 700), lx, yy, COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    for _, l in ipairs(help) do
        yy = yy + s(20)
        draw.SimpleText(l, font(13), lx, yy, UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

function PANEL:KitAt(mx, my)
    for _, k in ipairs(self.kitRects or {}) do
        if mx >= k.x and mx <= k.x + k.w and my >= k.y and my <= k.y + k.h then return k.row end
    end
end

function PANEL:PaintOver(w, h)
    local mx, my = self:CursorPos()
    if self.drag then
        local text = self.drag.name
        surface.SetFont(font(13, 600))
        local tw = surface.GetTextSize(text)
        surface.SetDrawColor(COL_HEADER)
        surface.DrawRect(mx + 10, my + 6, tw + S(16), S(26))
        surface.SetDrawColor(COL_DROP)
        surface.DrawOutlinedRect(mx + 10, my + 6, tw + S(16), S(26))
        draw.SimpleText(text, font(13, 600), mx + 10 + S(8), my + 6 + S(13), UI.Colors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return
    end
    -- Tooltip for the part under the mouse.
    local limb = self.hover
    if not limb then return end
    local t = Med.injOf and Med.injOf[self:Patient()]
    local p = t and t[limb] or Med.EMPTY_LIMB
    local lines = { Med.LIMB_NAMES[limb] }
    local burn = p.burn or 0
    if self.rough then
        local f = math.max(p.dmg, burn * 0.8)
        lines[#lines + 1] = f <= 0 and "Looks fine" or (f < 50 and "Hurt" or "Badly hurt")
        if p.bleed > 0 then lines[#lines + 1] = "Bleeding" end
        if self:Patient() == LocalPlayer() and p.frac then lines[#lines + 1] = "Fractured" end
    else
        lines[#lines + 1] = "Damage " .. math.ceil(p.dmg) .. "%"
        if p.bleed == 2 then lines[#lines + 1] = "Heavy bleeding" elseif p.bleed == 1 then lines[#lines + 1] = "Light bleeding" end
        if p.frac then lines[#lines + 1] = "Fractured" end
        if burn > 0 then lines[#lines + 1] = "Burns " .. math.ceil(burn) .. "%" end
    end
    if p.limp and Med.Limping(self:Patient()) then lines[#lines + 1] = "Limping" end
    local bw, lh = S(170), S(18)
    local bh = #lines * lh + S(12)
    local x, y = math.min(mx + 14, w - bw - 4), math.min(my + 14, h - bh - 4)
    surface.SetDrawColor(COL_BG)
    surface.DrawRect(x, y, bw, bh)
    surface.SetDrawColor(COL_EDGE)
    surface.DrawOutlinedRect(x, y, bw, bh)
    for i, l in ipairs(lines) do
        draw.SimpleText(l, font(i == 1 and 14 or 12, i == 1 and 700 or 400), x + S(8), y + S(6) + (i - 0.5) * lh,
            i == 1 and UI.Colors.text or UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

-- Hardcore: drag a kit row onto a body part.
function PANEL:OnMousePressed(code)
    if code ~= MOUSE_LEFT or not Med.Hardcore() then return end
    local row = self:KitAt(self:CursorPos())
    if row and row.usable then
        self.drag = row
        self:MouseCapture(true)
    end
end

function PANEL:OnMouseReleased(code)
    if code ~= MOUSE_LEFT or not self.drag then return end
    self:MouseCapture(false)
    local row = self.drag
    self.drag = nil
    local limb = self:PartAt(self:CursorPos())
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
