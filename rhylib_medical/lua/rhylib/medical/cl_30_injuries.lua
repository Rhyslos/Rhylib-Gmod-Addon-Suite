--[[
    The injury menu (H, convar rhylib_medical_key). Press it while looking
    at someone close to see their body instead of yours. Left: the body,
    each part white when fine and redder the more it's hurt, with small
    tags; hover a part for details. Right: your inventory; drag a kit or a
    field item (splint, burn gel, painkillers) onto a body
    part to treat it.

    Medics see exact damage, fractures, burns, health and effects.
    Troopers see roughly how hurt each part is and whether it bleeds (and
    their own effects), and can only stop bleeding with a medkit.

    Same look as the other Rhylib windows (dark plates, caps labels).
]]

local Med = Rhylib.Medical
local UI = Rhylib.UI

local keyVar = CreateClientConVar("rhylib_medical_key", "h", true, false, "Key that opens the injury menu")

local COL_BG = Color(14, 16, 15, 242)
local COL_HEADER = Color(22, 25, 23, 255)
local COL_EDGE = Color(0, 0, 0, 230)
local COL_LIGHT = Color(170, 176, 180, 70)
local COL_TICK = Color(170, 176, 180, 150)
local COL_ROW = Color(20, 23, 21)
local COL_ROW_HOVER = Color(32, 40, 48)
local COL_LABEL = Color(140, 142, 136)
local COL_FINE = Color(226, 228, 222)
local COL_HURT = Color(214, 48, 40)
local COL_BURN = Color(232, 132, 48)
local COL_OUTLINE = Color(0, 0, 0, 200)
local COL_DROP = Color(133, 183, 235)

local TAGS = {
    { key = "bleed2", text = "HEAVY BLEEDING", col = Color(226, 60, 50) },
    { key = "bleed1", text = "BLEEDING", col = Color(226, 110, 90) },
    { key = "frac", text = "FRACTURE", col = Color(239, 199, 89) },
    { key = "burn", text = "BURNS", col = COL_BURN },
    { key = "splint", text = "SPLINTED", col = Color(200, 190, 150) },
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
    local f = math.Clamp(math.max(p.dmg, p.burn * 0.8) / 100, 0, 1)
    -- Troopers only see three shades: fine, hurt, badly hurt.
    if rough then f = f <= 0 and 0 or (f < 0.5 and 0.45 or 1) end
    local base = COL_HURT
    if p.burn > p.dmg then base = COL_BURN end
    return Color(Lerp(f, COL_FINE.r, base.r), Lerp(f, COL_FINE.g, base.g), Lerp(f, COL_FINE.b, base.b))
end

local function tagsFor(p, rough)
    local out = {}
    if rough then
        if p.bleed > 0 then out[#out + 1] = TAGS[2] end
        return out
    end
    if p.bleed == 2 then out[#out + 1] = TAGS[1] elseif p.bleed == 1 then out[#out + 1] = TAGS[2] end
    if p.frac then out[#out + 1] = p.splint and TAGS[5] or TAGS[3] end
    if p.burn > 0 then out[#out + 1] = TAGS[4] end
    return out
end

-- Which treatment an inventory item is (Med.TREAT_ITEMS), or nil.
local function treatKind(inst)
    if not inst then return nil end
    local k = Med.TREAT_KIND[inst.id]
    if not k then return nil end
    if not Med.ANYONE[inst.id] and not Med.IsMedic(LocalPlayer()) then return nil end
    return k
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
    self:SetSize(S(940), S(600))
    self:Center()
    self:MakePopup()
    self:SetKeyboardInputEnabled(false)  -- keys keep working; the mouse is free
    self.opened = RealTime()
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

-- Inventory list on the right, medical items first.
function PANEL:Items()
    local Inv = Rhylib.Inventory
    local list = {}
    if not Inv or not Inv.byUid then return list end
    for _, inst in pairs(Inv.byUid) do list[#list + 1] = inst end
    table.sort(list, function(a, b)
        local ka, kb = treatKind(a) and 0 or 1, treatKind(b) and 0 or 1
        if ka ~= kb then return ka < kb end
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end

function PANEL:ListRect()
    local w = self:GetWide()
    return w - S(320), S(70), S(300), self:GetTall() - S(90)
end

function PANEL:RowAt(mx, my)
    local x, y, w = self:ListRect()
    local rh = S(40)
    if mx < x or mx > x + w or my < y + S(24) then return nil end
    local i = math.floor((my - y - S(24)) / (rh + S(4))) + 1
    return self.rows and self.rows[i]
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
    self.rough = rough
    draw.SimpleText(me and "INJURIES" or ("INJURIES  ·  " .. ply:Nick()), font(17, 700), s(14), s(20), UI.Colors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if medic or me then
        draw.SimpleText("Health " .. math.max(0, ply:Health()) .. " / " .. ply:GetMaxHealth(), font(14, 600), w - s(14), s(20), UI.Colors.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
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
        -- Tags
        local tags = tagsFor(p, rough)
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
        if Med.Painkilled(ply) then
            lines[#lines + 1] = { string.format("Painkillers: %d s", ply:GetNW2Float("rhylib_painkill", 0) - CurTime()), UI.Colors.good }
        end
        if Med.BrokenLeg(ply) then lines[#lines + 1] = { "Broken leg: limping, can't sprint", TAGS[3].col }
        elseif Med.NoSprint(ply) then lines[#lines + 1] = { "Hurt leg: can't sprint", COL_HURT } end
        if not Med.CanAim(ply) then lines[#lines + 1] = { "Hurt arm: can't aim, shaky", COL_HURT }
        elseif Med.SpreadPenalty(ply, 1) > 0.05 then lines[#lines + 1] = { "Aim a little shaky", COL_LABEL } end
        -- (torso only: an illness lowers the cap too, and medics find that with a blood test)
        local cap = Med.StaminaCap(ply) / math.max(Med.IllStaminaMult and Med.IllStaminaMult(ply) or 1, 0.01)
        if cap < 0.99 then lines[#lines + 1] = { string.format("Hurt torso: stamina capped at %d%%", cap * 100), COL_HURT } end
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

    -- How to treat
    local hy = h - s(130)
    draw.SimpleText("TREATMENT", font(12, 700), ex, hy, COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local help = { { "Drag an item from the right onto a body part.", UI.Colors.textDim } }
    if medic then
        local bay = Med.InMedBay(ply) or Med.Skill(LocalPlayer(), "field_surgeon")
        help[2] = { "First aid kit: fixes the part, uses charge.", UI.Colors.textDim }
        help[3] = bay and { "Med bay: sets bones and heals burns too.", UI.Colors.good }
            or { "Away from the med bay: splints, half burns.", COL_BURN }
        help[4] = { "Medkit: bleeding, health, damage, burns.", UI.Colors.textDim }
    else
        help[2] = { "Medkit: stops bleeding, some health.", UI.Colors.textDim }
        help[3] = { "Splint: holds a bone until the med bay.", UI.Colors.textDim }
        help[4] = { "Burn gel and painkillers: drag on too.", UI.Colors.textDim }
    end
    for i, l in ipairs(help) do
        draw.SimpleText(l[1], font(13), ex, hy + s(2) + i * s(20), l[2], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Inventory
    local lx, ly, lw = self:ListRect()
    draw.SimpleText("INVENTORY", font(12, 700), lx, ly + s(8), COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    self.rows = self:Items()
    local rh = s(40)
    local hoverRow = not self.drag and self:RowAt(mx, my)
    for i, inst in ipairs(self.rows) do
        local ry = ly + s(24) + (i - 1) * (rh + s(4))
        if ry + rh > h - s(10) then break end
        local def = Rhylib.Items and Rhylib.Items.Get(inst.id)
        local usable = treatKind(inst) ~= nil
        surface.SetDrawColor(hoverRow == inst and usable and COL_ROW_HOVER or COL_ROW)
        surface.DrawRect(lx, ry, lw, rh)
        surface.SetDrawColor(COL_EDGE)
        surface.DrawOutlinedRect(lx, ry, lw, rh)
        if usable then
            surface.SetDrawColor(96, 186, 126)
            surface.DrawRect(lx + 1, ry + 1, s(3), rh - 2)
        end
        local name = def and def.name or tostring(inst.id)
        local sub = inst.count and inst.count > 1 and ("x" .. inst.count) or ""
        if def and def.fill and def.rounds then
            sub = math.floor((inst.data and inst.data.fill or 1) * def.rounds + 0.5) .. " / " .. def.rounds .. " " .. (def.unit or "")
        elseif def and def.fill then
            sub = math.ceil((inst.data and inst.data.fill or 1) * 100) .. "% charge"
        end
        if inst.id == Med.FIRST_AID and not usable then sub = "medics only" end
        if def and def.desc and not usable then sub = def.usable and (inst.count and inst.count > 1 and ("x" .. inst.count) or "") or "no effect yet" end
        draw.SimpleText(name, font(14, usable and 600 or 400), lx + s(12), ry + rh * 0.5, usable and UI.Colors.text or UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(sub, font(12), lx + lw - s(10), ry + rh * 0.5, UI.Colors.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    if #self.rows == 0 then
        draw.SimpleText("Nothing carried", font(13), lx, ly + s(40), UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Corner ticks
    local tk = s(7)
    surface.SetDrawColor(COL_TICK)
    surface.DrawRect(0, h - 2, tk, 2) surface.DrawRect(0, h - tk, 2, tk)
    surface.DrawRect(w - tk, h - 2, tk, 2) surface.DrawRect(w - 2, h - tk, 2, tk)
end

function PANEL:PaintOver(w, h)
    local mx, my = self:CursorPos()
    if self.drag then
        local def = Rhylib.Items and Rhylib.Items.Get(self.drag.id)
        local text = def and def.name or "Item"
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
    if self.rough then
        local f = math.max(p.dmg, p.burn * 0.8)
        lines[#lines + 1] = f <= 0 and "Looks fine" or (f < 50 and "Hurt" or "Badly hurt")
        if p.bleed > 0 then lines[#lines + 1] = "Bleeding" end
    else
        lines[#lines + 1] = "Damage " .. math.ceil(p.dmg) .. "%"
        if p.bleed == 2 then lines[#lines + 1] = "Heavy bleeding" elseif p.bleed == 1 then lines[#lines + 1] = "Light bleeding" end
        if p.frac then lines[#lines + 1] = p.splint and "Fracture, splinted" or "Fractured" end
        if p.burn > 0 then lines[#lines + 1] = "Burns " .. math.ceil(p.burn) .. "%" end
    end
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

function PANEL:OnMousePressed(code)
    if code ~= MOUSE_LEFT then return end
    local inst = self:RowAt(self:CursorPos())
    if inst and treatKind(inst) then
        self.drag = inst
        self:MouseCapture(true)
    end
end

function PANEL:OnMouseReleased(code)
    if code ~= MOUSE_LEFT or not self.drag then return end
    self:MouseCapture(false)
    local inst = self.drag
    self.drag = nil
    local limb = self:PartAt(self:CursorPos())
    if not limb then return end
    Rhylib.Net.Start("med.treat")
    net.WriteEntity(self:Patient())
    net.WriteUInt(Med.LIMB_INDEX[limb], 3)
    net.WriteUInt(treatKind(inst), 3)
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
    if IsValid(e) and e:IsPlayer() and e:Alive() and me:GetPos():DistToSqr(e:GetPos()) <= r * r then return e end
    return Med.FindDowned and Med.FindDowned(me) or nil
end

-- Open the injury menu for patient (a player), or your own (nil).
function Med.OpenInjuries(target)
    if IsValid(Med.injuryPanel) then Med.injuryPanel:Remove() end
    local me = LocalPlayer()
    if not me:Alive() or Med.IsDown(me) then return end
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
    if IsValid(Med.injuryPanel) then wasDown = true return end
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
        Menus.AddSetting("Medical", { id = "med.key", order = 10, title = "Injury menu key", kind = "key", convar = "rhylib_medical_key" })
    end
end)

-- A kit's click on the server: open the menu (someone's, or your own).
Rhylib.Net.Receive("med.open", function()
    local p = net.ReadEntity()
    Med.OpenInjuries(IsValid(p) and p or nil)
end)
