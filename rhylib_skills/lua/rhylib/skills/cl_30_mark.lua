--[[
    Mark target on the client: Q asks the server to mark (hook
    Rhylib.MarkKey from rhylib_menus), and marks sent to us (ours or a
    squad mate's) are drawn over the target until they run out or the
    target dies. Through optics, one Q marks several (sv_30_mark).
    Without a marking skill (K.CanMark), the first Q of a session prints a
    quiet chat line saying which skills mark.
    Locks (K.LocksNow: a Commander always, Tactical marks with helmet
    optics in use) are red diamonds for
    everyone who sees them (the squad hits locked targets harder); other
    marks, spots and Called shot marks orange.
    Tactical visor spotting (K.SpotsNow: a Commander always, others with the sun visor down
    or through macrobinoculars / a rangefinder): a white ring on the
    spotted enemy nearest the aim; Q (with a marking skill) locks that one. Your own locks get a red
    ring (only you see rings).
    Marked enemies also show on the compass radar (rhylib_radio
    R.radarExtras["skills.marks"]) for whoever got the marks (the marker
    and their squad): red squares, a commander as two upright bars, a B2
    as a half circle over a line. Not while your comms are jammed.
    Client only. K.visorTarget = the ringed enemy this frame (sent with Q).
    Distances on the diamonds use 0.019 m per unit.
]]

local K = Rhylib.Skills
local UI = Rhylib.UI

K.clientMarks = K.clientMarks or {}   -- [entity index] = { [marker index] = { untilT, lock } } (like the server's)

local COL = Color(242, 160, 60)
local COL_LOCK = Color(235, 60, 50)
local COL_OUT = Color(0, 0, 0, 170)

-- Without the skill, Q says once per session what it's for (it used to do
-- nothing at all).
local toldMark = false
Rhylib.Hook.Add("Rhylib.MarkKey", "skills.mark", function()
    local me = LocalPlayer()
    if not (IsValid(me) and me:Alive()) then return end
    if not K.CanMark(me) then
        if not toldMark then
            toldMark = true
            Rhylib.Notify(nil, "Q marking needs Tactical visor as a Commander, Tactical marks (Pistol officer) or ARC training", "info", "Skills")
        end
        return
    end
    local G = Rhylib.Gear
    local optics = G and G.Looking and G.Looking(me) or false
    Rhylib.Net.Start("skills.markreq")
    net.WriteBool(optics)
    net.WriteUInt(math.Clamp(math.floor((optics and G.opticsFov or 0) * 10), 0, 1023), 10)
    -- (sun visor: lock the ringed enemy)
    local t = not optics and K.visorTarget
    net.WriteBool(IsValid(t))
    if IsValid(t) then net.WriteUInt(t:EntIndex(), 13) end
    net.SendToServer()
end)

Rhylib.Net.Receive("skills.mark", function()
    local by = net.ReadUInt(13)   -- (who marked)
    local replace = net.ReadBool()
    local quiet = net.ReadBool()   -- (sun visor auto spots: no blip every 5 s)
    local lock = net.ReadBool()
    local secs = net.ReadUInt(6)
    local n = net.ReadUInt(4)
    local now = CurTime()
    -- A new Q replaces that player's older locks (spots stay).
    if replace then
        for t, per in pairs(K.clientMarks) do
            local mk = per[by]
            if mk and (mk.lock or mk.q or mk.untilT <= now) then per[by] = nil end
            if next(per) == nil then K.clientMarks[t] = nil end
        end
    end
    local untilT = now + secs
    for _ = 1, n do
        local idx = net.ReadUInt(13)
        local per = K.clientMarks[idx] or {}
        K.clientMarks[idx] = per
        local old = per[by]
        if old and old.untilT <= now then old = nil end
        if lock or replace then
            -- (a Q: a lock, or a plain mark the next Q replaces)
            per[by] = { untilT = untilT, lock = lock or nil, q = (not lock) or nil }
        else
            -- (a shorter spot never cuts a longer mark short, nor unlocks it)
            per[by] = { untilT = math.max(untilT, old and old.untilT or 0), lock = old and old.lock or nil, q = old and old.q or nil }
        end
    end
    if not quiet then surface.PlaySound(by == LocalPlayer():EntIndex() and "buttons/blip1.wav" or "buttons/blip2.wav") end
end)

local function alive(e)
    if not IsValid(e) then return false end
    if e:IsPlayer() then return e:Alive() end
    return e:Health() > 0
end

-- A diamond outline at x, y.
local function diamond(x, y, r, col)
    surface.SetDrawColor(col)
    surface.DrawLine(x, y - r, x + r, y)
    surface.DrawLine(x + r, y, x, y + r)
    surface.DrawLine(x, y + r, x - r, y)
    surface.DrawLine(x - r, y, x, y - r)
end

Rhylib.Hook.Add("HUDPaint", "skills.marks", function()
    if next(K.clientMarks) == nil then return end
    local me = LocalPlayer()
    local now = CurTime()
    local s = ScrH() / 1080
    draw.NoTexture()
    for idx, per in pairs(K.clientMarks) do
        -- (the longest live mark on it, red if anyone's is a lock)
        local untilT, locked = 0, false
        for by, m in pairs(per) do
            if m.untilT <= now then
                per[by] = nil
            else
                if m.untilT > untilT then untilT = m.untilT end
                if m.lock then locked = true end
            end
        end
        local e = Entity(idx)
        if next(per) == nil or (IsValid(e) and not alive(e)) then
            K.clientMarks[idx] = nil
        elseif IsValid(e) and not e:IsDormant() then
            local top = e:GetPos() + Vector(0, 0, e:OBBMaxs().z + 14)
            local sp = top:ToScreen()
            if sp.visible then
                local col = locked and COL_LOCK or COL
                local left = untilT - now
                local a = left < 1 and left or 1
                local r = 9 * s
                diamond(sp.x, sp.y, r + 1, ColorAlpha(COL_OUT, COL_OUT.a * a))
                diamond(sp.x, sp.y, r, ColorAlpha(col, 255 * a))
                diamond(sp.x, sp.y, r - 3 * s, ColorAlpha(col, 160 * a))
                local m = math.Round(top:Distance(me:EyePos()) * 0.019)
                local text = m .. " m"
                draw.SimpleTextOutlined(text, UI.Font(12, 600), sp.x, sp.y + r + 3 * s, ColorAlpha(col, 255 * a),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, ColorAlpha(COL_OUT, COL_OUT.a * a))
            end
        end
    end
end)

-- Rings (only the marker sees them): with the sun visor down and Mark
-- target, a white sectioned ring (the clones' helmet view: four arcs with
-- gaps) on the spotted enemy nearest the aim (within 6 degrees), which Q
-- then locks; a red ring on every enemy you've locked, visor or not.
local RING_COL = Color(245, 245, 245, 235)
local RING_LOCK = Color(235, 60, 50, 240)
local RING_OUT = Color(0, 0, 0, 120)
local function arc(cx, cy, r, a0, a1, col)
    surface.SetDrawColor(col)
    local steps = 10
    local px, py
    for i = 0, steps do
        local a = math.rad(a0 + (a1 - a0) * i / steps)
        local x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        if px then surface.DrawLine(px, py, x, y) end
        px, py = x, y
    end
end
local function ring(cx, cy, r, s, col)
    local thick = math.max(2, math.floor(3 * s))
    for k = 0, 3 do
        local a0 = k * 90 + 15
        for t = -1, thick do
            arc(cx, cy, r + t, a0, a0 + 60, t == -1 and RING_OUT or col)
        end
    end
end

-- A ring sized to the target on screen.
local function ringOn(e, s, col, alpha)
    local c = e:WorldSpaceCenter()
    local sp = c:ToScreen()
    if not sp.visible then return end
    local top = (c + Vector(0, 0, (e:OBBMaxs().z - e:OBBMins().z) * 0.5)):ToScreen()
    local r = math.Clamp(math.abs(sp.y - top.y) * 0.75, 14 * s, 90 * s)
    ring(sp.x, sp.y, r, s, alpha and ColorAlpha(col, col.a * alpha) or col)
end

Rhylib.Hook.Add("HUDPaint", "skills.visorring", function()
    K.visorTarget = nil
    if next(K.clientMarks) == nil then return end
    local me = LocalPlayer()
    if not (IsValid(me) and me:Alive() and K.Has(me, "mark_target")) then return end   -- (Tactical visor)
    local myIdx = me:EntIndex()
    local now = CurTime()
    local s = ScrH() / 1080
    draw.NoTexture()
    -- Your locks.
    for idx, per in pairs(K.clientMarks) do
        local mk = per[myIdx]
        if mk and mk.lock and mk.untilT > now then
            local e = Entity(idx)
            if IsValid(e) and not e:IsDormant() and alive(e) then
                local left = mk.untilT - now
                ringOn(e, s, RING_LOCK, left < 1 and left or 1)
            end
        end
    end
    -- The visor's pick: the nearest spot to the aim that you haven't locked.
    if not K.SpotsNow(me) then return end
    local eye, aim = me:EyePos(), me:GetAimVector()
    local best, bestDot = nil, math.cos(math.rad(6))
    for idx, per in pairs(K.clientMarks) do
        local e = Entity(idx)
        local mine = per[myIdx]
        local live = false
        for _, m in pairs(per) do
            if m.untilT > now then live = true break end
        end
        if live and not (mine and mine.lock and mine.untilT > now) and IsValid(e) and not e:IsDormant() and alive(e) then
            local d = e:WorldSpaceCenter() - eye
            local len = d:Length()
            local dot = len > 1 and aim:Dot(d / len) or -1
            if dot > bestDot then best, bestDot = e, dot end
        end
    end
    if not best then return end
    K.visorTarget = best
    ringOn(best, s, RING_COL)
end)

-- Marked enemies on the compass radar (see the header).
local RADAR_RED = Color(235, 60, 50)
local RADAR_OUT = Color(0, 0, 0, 200)
local DOME_SEG = 10
local function dome(x, y, m, col)
    -- (a half circle sitting on y, flat side down)
    local pts = {}
    for i = 0, DOME_SEG do
        local a = math.pi + i / DOME_SEG * math.pi
        pts[#pts + 1] = { x = x + math.cos(a) * m, y = y + math.sin(a) * m }
    end
    surface.SetDrawColor(col)
    surface.DrawPoly(pts)
end
local function radarIcon(x, y, m, e, col, grow)
    local kind = e.Kind and e:Kind()
    local g = grow or 0
    surface.SetDrawColor(col)
    if kind and kind.commander then
        -- two upright bars (an "=" stood on end)
        local w = math.max(2, math.floor(m * 0.45))
        surface.DrawRect(x - m * 0.75 - g, y - m - g, w + g * 2, m * 2 + g * 2)
        surface.DrawRect(x + m * 0.75 - w - g, y - m - g, w + g * 2, m * 2 + g * 2)
    elseif kind and kind.big then
        dome(x, y + m * 0.25, m + g, col)
        local t = math.max(2, math.floor(m * 0.35))
        surface.SetDrawColor(col)
        surface.DrawRect(x - m - g, y + m * 0.5 - g, m * 2 + g * 2, t + g * 2)
    else
        surface.DrawRect(x - m * 0.8 - g, y - m * 0.8 - g, m * 1.6 + g * 2, m * 1.6 + g * 2)
    end
end
local function radarMarks(cx, cy, r, mp, fx, fy, k)
    if next(K.clientMarks) == nil then return end
    local me = LocalPlayer()
    local R = Rhylib.Radio
    if R and R.Jammed and R.Jammed(me) then return end
    local now = CurTime()
    local m = math.max(3, math.floor(r * 0.045))
    draw.NoTexture()
    for idx, per in pairs(K.clientMarks) do
        local live = false
        for _, mk in pairs(per) do
            if mk.untilT > now then live = true break end
        end
        local e = live and Entity(idx)
        if e and IsValid(e) and not e:IsDormant() and alive(e) then
            local p = e:GetPos()
            local dx, dy = p.x - mp.x, p.y - mp.y
            local fwd = dx * fx + dy * fy
            local right = dx * fy - dy * fx
            local sx, sy = right * k, -fwd * k
            if sx * sx + sy * sy < (r - m) * (r - m) then
                local x, y = cx + sx, cy + sy
                radarIcon(x, y, m, e, RADAR_OUT, 1)
                radarIcon(x, y, m, e, RADAR_RED, 0)
            end
        end
    end
end
local function hookRadar()
    local R = Rhylib.Radio
    if R and R.radarExtras then R.radarExtras["skills.marks"] = radarMarks end
end
hookRadar()
Rhylib.Hook.Add("InitPostEntity", "skills.markradar", hookRadar)
