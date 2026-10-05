--[[
    Mark target on the client: Q asks the server to mark (hook
    Rhylib.MarkKey from rhylib_menus), and marks sent to us (ours or a
    squad mate's) are drawn over the target until they run out or the
    target dies. Through optics, one Q marks several (sv_30_mark).
    A Commander's (Tactical visor) Q marks are locks: red diamonds for
    everyone who sees them (the squad hits locked targets harder); other
    marks, spots and Called shot marks orange.
    Sun visor down: a white ring on the spotted enemy nearest the aim; Q
    locks that one. Your own locks get a red ring (only you see rings).
]]

local K = Rhylib.Skills
local UI = Rhylib.UI

K.clientMarks = K.clientMarks or {}   -- [entity index] = { [marker index] = { untilT, lock } } (like the server's)

local COL = Color(242, 160, 60)
local COL_LOCK = Color(235, 60, 50)
local COL_OUT = Color(0, 0, 0, 170)

Rhylib.Hook.Add("Rhylib.MarkKey", "skills.mark", function()
    local me = LocalPlayer()
    if not (IsValid(me) and me:Alive() and K.Has(me, "mark_target")) then return end
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
    local n = net.ReadUInt(3)
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
    if not (IsValid(me) and me:Alive() and K.Has(me, "tactical_visor")) then return end
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
    if not me:GetNW2Bool("rhylib_visorDown", false) then return end
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
