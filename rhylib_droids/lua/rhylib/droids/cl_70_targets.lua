--[[
    Event targets (client): the HUD and the settings window
    (the entity is entities/rhylib_event_target.lua, the server side
    sv_70_targets.lua).

    HUD, for everyone:
      - over a target in sight within etBarRange (one trace per target
        every 0.2 s): its name, EXPLOSIVE · N M and UNDER ATTACK chips,
        a health bar and "hp / max · N m";
      - otherwise an objective-style marker from anywhere (gold diamond,
        name, small health bar, "N% · N m"), slid onto the screen edge
        when off screen or behind; red ring and bar while droids hit it
        (within 5 s of the last hit);
      - "OBJECTIVE LOST · <name> destroyed" plate for 5 s (droids.etlost).
      Colours: HUD colour keys objective (gold) and danger (red).

    D.TargetWindow(st, title, sub, onApply): the settings window
    (st = { name, model, scale, health, explode, radius }): WHAT IT IS
    (name, model: "Pick from spawn menu…" (rhylib_menus pick mode) or
    "What I aim at", size), TOUGHNESS (health), WHEN IT IS DESTROYED
    (explodes, blast radius), a card with the model turning and the
    numbers; Apply / Close / Esc (closer "droids.target"). Used by E on
    a placed one (droids.etedit -> droids.etset) and by the toolgun's
    right-click on its tile (rhylib_toolgun, for the next ones).
]]

local D = Rhylib.Droids
local UI = Rhylib.UI

D.eventTargets = D.eventTargets or {}

local GOLD = UI and UI.HudCol and UI.HudCol("objective", "droids.etGold", 255, 200, 70) or Color(255, 200, 70)
local RED = UI and UI.HudCol and UI.HudCol("danger", "droids.etRed", 220, 70, 50) or Color(220, 70, 50)
local AMBER = Color(230, 140, 40)
local WHITE, SHADOW = Color(235, 238, 240), Color(0, 0, 0, 200)
local BACK = Color(10, 12, 14, 190)
local M_PER_UNIT = 0.01905
local HIT_SHOW = 5

local function font(size, weight)
    return UI and UI.Font and UI.Font(size, weight) or "DermaDefaultBold"
end

local DIA = { {}, {}, {}, {} }
local function diamond(cx, cy, r, col)
    DIA[1].x, DIA[1].y = cx, cy - r
    DIA[2].x, DIA[2].y = cx + r, cy
    DIA[3].x, DIA[3].y = cx, cy + r
    DIA[4].x, DIA[4].y = cx - r, cy
    draw.NoTexture()
    surface.SetDrawColor(col)
    surface.DrawPoly(DIA)
end
local function diamondOut(cx, cy, r, col)
    surface.SetDrawColor(col)
    for i = 0, 1 do
        local rr = r + i
        surface.DrawLine(cx, cy - rr, cx + rr, cy)
        surface.DrawLine(cx + rr, cy, cx, cy + rr)
        surface.DrawLine(cx, cy + rr, cx - rr, cy)
        surface.DrawLine(cx - rr, cy, cx, cy - rr)
    end
end

local function bar(x, y, w, h, frac, col)
    surface.SetDrawColor(BACK)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(0, 0, 0, 220)
    surface.DrawOutlinedRect(x, y, w, h)
    surface.SetDrawColor(col)
    surface.DrawRect(x + 2, y + 2, math.floor((w - 4) * math.Clamp(frac, 0, 1)), h - 4)
end

local function chip(text, x, y, col, f)
    surface.SetFont(f)
    local tw, th = surface.GetTextSize(text)
    local w, h = tw + 10, th + 2
    surface.SetDrawColor(col.r, col.g, col.b, 60)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(col)
    surface.DrawOutlinedRect(x, y, w, h)
    draw.SimpleText(text, f, x + 5, y + 1, Color(math.min(255, col.r + 35), math.min(255, col.g + 50), math.min(255, col.b + 60)))
    return w, h
end

-- In sight (cached 0.2 s per target).
local seen = setmetatable({}, { __mode = "k" })
local trOut = {}
local trIn = { mask = MASK_VISIBLE_AND_NPCS, output = trOut }
local function inSight(me, e, eye)
    local c = seen[e]
    local now = RealTime()
    if c and now < c.at then return c.v end
    trIn.start = eye
    trIn.endpos = e:WorldSpaceCenter()
    trIn.filter = me
    util.TraceLine(trIn)
    local v = not trOut.Hit or trOut.Entity == e
    seen[e] = { v = v, at = now + 0.2 }
    return v
end

local lost   -- { name, at }

Rhylib.Hook.Add("HUDPaint", "droids.eventTargets", function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local w, h = ScrW(), ScrH()
    local s = h / 1080
    local now = CurTime()

    if lost and RealTime() - lost.at < 5 then
        local K = UI and UI.Kit
        local a = math.Clamp((5 - (RealTime() - lost.at)) * 2, 0, 1)
        local f1, f2 = font(math.floor(12 * s), 700), font(math.floor(18 * s), 700)
        local text = (lost.name ~= "" and lost.name or "Target") .. " destroyed"
        surface.SetFont(f2)
        local tw = surface.GetTextSize(text)
        local pw, ph = math.floor(tw + 170 * s), math.floor(40 * s)
        local px, py = math.floor(w * 0.5 - pw * 0.5), math.floor(52 * s)
        surface.SetAlphaMultiplier(a)
        if K and K.Plate then K.Plate(px, py, pw, ph, { alpha = 235 }) else
            surface.SetDrawColor(29, 32, 35, 235)
            surface.DrawRect(px, py, pw, ph)
        end
        surface.SetDrawColor(RED)
        surface.DrawRect(px + 10 * s, py + 7 * s, 3 * s, ph - 14 * s)
        draw.SimpleText("OBJECTIVE LOST", f1, px + 22 * s, py + ph * 0.5, Color(154, 163, 168), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(text, f2, px + pw - 14 * s, py + ph * 0.5, Color(255, 140, 120), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        surface.SetAlphaMultiplier(1)
    end

    if not next(D.eventTargets) then return end
    local eye = me:EyePos()
    local fwd = me:EyeAngles():Forward()
    local margin = 40 * s
    local barRange = D.Cfg and D.Cfg("etBarRange") or 3150
    local fName, fSmall, fChip = font(math.floor(17 * s), 700), font(math.floor(14 * s), 600), font(math.floor(12 * s), 700)
    for e in pairs(D.eventTargets) do
        if not IsValid(e) then
            D.eventTargets[e] = nil
        elseif e.GetHPMax and e:GetHPMax() > 0 then
            local hp, max = e:GetHP(), e:GetHPMax()
            local frac = hp / max
            local hit = now - e:GetHitAt() < HIT_SHOW and e:GetHitAt() > 0
            local top = e:WorldSpaceCenter() + Vector(0, 0, e:OBBMaxs().z - e:OBBCenter().z + 14)
            local dist = eye:Distance(top)
            local metres = math.floor(dist * M_PER_UNIT + 0.5)
            local name = string.upper(e:GetTargetName())
            local sp = top:ToScreen()
            local ahead = (top - eye):Dot(fwd) > 0
            local onScreen = ahead and sp.visible and sp.x > margin and sp.x < w - margin and sp.y > margin and sp.y < h - margin
            if onScreen and dist < barRange and inSight(me, e, eye) then
                -- Over it: name, chips, bar, numbers.
                local bw = math.floor(200 * s)
                local x, y = math.floor(sp.x), math.floor(sp.y)
                local by = y - math.floor(26 * s)
                bar(x - bw * 0.5, by, bw, math.floor(12 * s), frac, hit and RED or GOLD)
                draw.SimpleTextOutlined(hp .. " / " .. max .. " · " .. metres .. " m", fSmall, x, by + 14 * s, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, SHADOW)
                -- chips row
                local chips = {}
                if e:GetExplosive() then chips[#chips + 1] = { "EXPLOSIVE · " .. math.floor(e:GetRadius() * M_PER_UNIT + 0.5) .. " M", AMBER } end
                if hit then chips[#chips + 1] = { "UNDER ATTACK", RED } end
                local cy = by - math.floor(22 * s)
                if #chips > 0 then
                    surface.SetFont(fChip)
                    local total = 0
                    for _, c in ipairs(chips) do total = total + surface.GetTextSize(c[1]) + 10 end
                    total = total + (#chips - 1) * 6
                    local cx = x - total * 0.5
                    for _, c in ipairs(chips) do
                        local cw = chip(c[1], cx, cy, c[2], fChip)
                        cx = cx + cw + 6
                    end
                    cy = cy - math.floor(24 * s)
                end
                surface.SetFont(fName)
                local nw = surface.GetTextSize(name)
                local m = math.floor(5 * s)
                diamond(x - nw * 0.5 - m - 4 * s, cy + 10 * s, m, GOLD)
                draw.SimpleTextOutlined(name, fName, x + m, cy + 10 * s, GOLD, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, SHADOW)
            else
                -- Marker from anywhere (objective style), on the edge when off screen.
                local x, y = sp.x, sp.y
                if not ahead then x, y = w - x, h - y end
                if not onScreen then
                    local dx, dy = x - w * 0.5, y - h * 0.5
                    if dx == 0 and dy == 0 then dy = 1 end
                    local k = math.min((w * 0.5 - margin) / math.max(math.abs(dx), 1), (h * 0.5 - margin) / math.max(math.abs(dy), 1))
                    x, y = w * 0.5 + dx * k, h * 0.5 + dy * k
                end
                local m = math.floor(9 * s)
                diamond(x, y, m + 2, Color(0, 0, 0, 160))
                diamond(x, y, m, GOLD)
                if hit then diamondOut(x, y, m + math.floor(5 * s), RED) end
                draw.SimpleTextOutlined(name, font(math.floor(15 * s), 700), x, y - m - 6 * s, GOLD, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, SHADOW)
                local bw = math.floor(54 * s)
                bar(x - bw * 0.5, y + m + 6 * s, bw, math.max(4, math.floor(7 * s)), frac, hit and RED or GOLD)
                draw.SimpleTextOutlined(math.floor(frac * 100 + 0.5) .. "% · " .. metres .. " m", fSmall, x, y + m + 15 * s, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, SHADOW)
            end
        end
    end
end)

Rhylib.Net.Receive("droids.etlost", function()
    lost = { name = net.ReadString(), at = RealTime() }
    surface.PlaySound("buttons/button10.wav")
end)

--------------------------------------------------------------------------
-- Settings window
--------------------------------------------------------------------------

local GRAD = Material("vgui/gradient-l")
local panel

local function closePanel()
    if IsValid(panel) then panel:Remove() panel = nil return true end
    return false
end
if UI and UI.RegisterCloser then UI.RegisterCloser("droids.target", closePanel) end

local function metres(u) return math.floor(u * M_PER_UNIT + 0.5) end

function D.TargetWindow(st, title, sub, onApply)
    local K = UI and UI.Kit
    if not K then return end
    local s = K.S
    local C = K.C
    closePanel()
    st.name = st.name or "Target"
    st.model = st.model or "models/props_junk/wood_crate002a.mdl"
    st.scale = math.Clamp(tonumber(st.scale) or 1, 0.5, 3)
    st.health = math.Clamp(math.floor(tonumber(st.health) or 800), 1, 100000)
    st.radius = math.Clamp(math.floor(tonumber(st.radius) or 300), 16, 2000)

    local f = vgui.Create("EditablePanel")
    panel = f
    f:SetSize(math.min(ScrW() - s(40), s(980)), math.min(ScrH() - s(40), s(560)))
    f:Center()
    f:MakePopup()
    f:DockPadding(s(14), s(52), s(14), s(14))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = title or "Event target", sub = sub or "Something on the map droids go after", ticks = "all", header = s(38) })
    end

    local bar = vgui.Create("DPanel", f)
    bar.Paint = nil
    bar:Dock(BOTTOM)
    bar:SetTall(s(34))
    bar:DockMargin(0, s(10), 0, 0)

    -- Card (right): the model turning and the numbers.
    local card = vgui.Create("DPanel", f)
    card:Dock(RIGHT)
    card:SetWide(s(250))
    card:DockMargin(s(12), 0, 0, 0)
    card:DockPadding(s(16), s(40), s(16), s(16))
    function card:Paint(w, h)
        K.SetCol(C.header)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        K.SetCol(C.accent)
        surface.DrawRect(0, 0, s(3), h)
        K.Ticks(0, 0, w, h)
        local x = s(16)
        K.Caps("Each one you place", x, s(22))
        local y = s(40) + s(130) + s(18)
        draw.SimpleText(K.Fit(st.name ~= "" and st.name or "Target", K.Font(20, 700), w - x * 2), K.Font(20, 700), x, y, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        y = y + s(22)
        K.SetCol(C.edgeLight)
        surface.DrawRect(x, y, w - x * 2, 1)
        y = y + s(20)
        local rows = {
            { "Health", tostring(st.health), C.text },
            { "Size", string.format("%.1f×", st.scale), C.text },
            { "Destroyed", st.explode and ("Explodes · " .. metres(st.radius) .. " m") or "Breaks apart", st.explode and AMBER or C.text },
        }
        for _, r in ipairs(rows) do
            K.Caps(r[1], x, y)
            draw.SimpleText(r[2], K.Font(15, 700), w - x, y, r[3], TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            y = y + s(26)
        end
    end
    local mdl = vgui.Create("DModelPanel", card)
    mdl:Dock(TOP)
    mdl:SetTall(s(130))
    mdl.shown = nil
    function mdl:Think()
        if self.shown == st.model then return end
        self.shown = st.model
        self:SetModel(st.model)
        local ent = self:GetEntity()
        if IsValid(ent) then
            local mn, mx = ent:GetRenderBounds()
            local size = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z, 1)
            local mid = (mn + mx) * 0.5
            self:SetFOV(40)
            self:SetCamPos(mid + Vector(size * 1.3, size * 1.3, size * 0.7))
            self:SetLookAt(mid)
        end
    end
    local paintMdl = mdl.Paint
    function mdl:Paint(w, h)
        surface.SetDrawColor(18, 20, 22, 255)
        surface.DrawRect(0, 0, w, h)
        paintMdl(self, w, h)
    end

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL)
    body.Paint = nil

    local function band(text)
        local caps = string.upper(text)
        local p = vgui.Create("DPanel", body)
        p:Dock(TOP)
        p:SetTall(s(30))
        p:DockMargin(0, 0, 0, s(4))
        function p:Paint(w, h)
            K.SetCol(C.accent, 30)
            surface.SetMaterial(GRAD)
            surface.DrawTexturedRect(0, 0, w * 0.7, h)
            K.SetCol(C.accent)
            surface.DrawRect(0, 0, s(3), h)
            draw.SimpleText(caps, K.Font(13, 700), s(16), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    local n = 0
    local function row(t, desc, descFn)
        n = n + 1
        local alt = n % 2 == 0
        local r = vgui.Create("DPanel", body)
        r:Dock(TOP)
        r:SetTall((desc or descFn) and s(48) or s(38))
        r:DockMargin(0, 0, 0, s(2))
        r:DockPadding(s(12), s(7), s(10), s(7))
        function r:Paint(w, h)
            K.SetCol(self:IsHovered() and C.rowHover or (alt and C.rowAlt or C.row))
            surface.DrawRect(0, 0, w, h)
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            local d = descFn and descFn() or desc
            draw.SimpleText(t, K.Font(14, 500), s(12), d and h * 0.36 or h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if d then draw.SimpleText(K.Fit(d, K.Font(12), w - self.right:GetWide() - s(30)), K.Font(12), s(12), h * 0.70, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        end
        r.right = vgui.Create("DPanel", r)
        r.right:Dock(RIGHT)
        r.right.Paint = nil
        return r
    end
    local function gap()
        local g = vgui.Create("DPanel", body)
        g:Dock(TOP)
        g:SetTall(s(8))
        g.Paint = nil
    end

    band("What it is")
    local r = row("Name")
    r.right:SetWide(s(260))
    local te = K.TextEntry(r.right, "Target")
    te:Dock(FILL)
    te:SetText(st.name)
    te.OnChange = function(self) st.name = string.sub(self:GetValue(), 1, 32) end

    r = row("Model", nil, function() return st.model end)
    r.right:SetWide(s(330))
    local aim = K.Button(r.right, "What I aim at", function()
        local tr = LocalPlayer():GetEyeTrace()
        local e = tr.Entity
        local m = IsValid(e) and not e:IsPlayer() and e:GetModel()
        if isstring(m) and string.EndsWith(string.lower(m), ".mdl") then
            st.model = m
        else
            surface.PlaySound("buttons/button10.wav")
        end
    end, { small = true })
    aim:Dock(RIGHT)
    aim:SetWide(s(120))
    local pick = K.Button(r.right, "Pick from spawn menu…", function()
        local SPW = Rhylib.Menus and Rhylib.Menus.Spawn
        if not (SPW and SPW.PickModel) then surface.PlaySound("buttons/button10.wav") return end
        f:SetVisible(false)
        SPW.PickModel(function(path) st.model = path end, "the event target")
        -- (back from pick mode, picked or cancelled: show the window again;
        -- a hidden panel doesn't Think, so a timer watches)
        timer.Create("droids.etPick", 0.2, 0, function()
            if not IsValid(f) then timer.Remove("droids.etPick") return end
            if not SPW.pick then
                timer.Remove("droids.etPick")
                f:SetVisible(true)
                f:MakePopup()
            end
        end)
    end, { small = true })
    pick:Dock(RIGHT)
    pick:SetWide(s(196))
    pick:DockMargin(0, 0, s(6), 0)

    local function slider(t, desc, lo, hi, dec, get, set)
        local rr = row(t, desc)
        rr.right:SetWide(s(260))
        K.Slider(rr.right, lo, hi, dec, get, set):Dock(FILL)
    end
    slider("Size", nil, 0.5, 3, 1, function() return st.scale end, function(v) st.scale = math.Round(v, 1) end)

    gap()
    band("Toughness")
    slider("Health", "Only droids can hurt it", 50, 10000, 0, function() return st.health end, function(v) st.health = math.Round(v) end)

    gap()
    band("When it is destroyed")
    r = row("Explodes", "Off: it breaks apart with smoke and sparks")
    r.right:SetWide(s(70))
    K.Toggle(r.right, function() return st.explode end, function(v) st.explode = v end):Dock(RIGHT)
    slider("Blast radius (m)", "Hurts everyone inside it", 1, 30, 0, function() return metres(st.radius) end, function(v) st.radius = math.Clamp(math.floor(v / M_PER_UNIT + 0.5), 16, 2000) end)

    local close = K.Button(bar, "Close", function() closePanel() end)
    close:Dock(RIGHT)
    close:SetWide(s(120))
    local apply = K.Button(bar, "Apply", function()
        st.name = string.Trim(st.name or "")
        onApply(st)
        closePanel()
    end, { accent = true })
    apply:Dock(RIGHT)
    apply:SetWide(s(140))
    apply:DockMargin(0, 0, s(8), 0)
end

-- E on a placed one with the toolgun out.
local function readCfg()
    return { name = net.ReadString(), model = net.ReadString(), scale = net.ReadFloat(), health = net.ReadUInt(17),
        explode = net.ReadBool(), radius = net.ReadUInt(11) }
end
D.ReadTargetCfg = readCfg

Rhylib.Net.Receive("droids.etedit", function()
    local ent = net.ReadEntity()
    local st = readCfg()
    if not IsValid(ent) then return end
    D.TargetWindow(st, "Event target", "This one · Apply also brings it back to full health", function(v)
        if not IsValid(ent) then return end
        Rhylib.Net.Start("droids.etset")
        net.WriteEntity(ent)
        net.WriteString(v.name or "")
        net.WriteString(v.model or "")
        net.WriteFloat(v.scale or 1)
        net.WriteUInt(math.Clamp(v.health or 800, 1, 100000), 17)
        net.WriteBool(v.explode and true or false)
        net.WriteUInt(math.Clamp(v.radius or 300, 16, 2000), 11)
        net.SendToServer()
    end)
end)
