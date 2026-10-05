--[[
    Mark target on the client: Q asks the server to mark (hook
    Rhylib.MarkKey from rhylib_menus), and marks sent to us (ours or a
    squad mate's) are drawn over the target until they run out or the
    target dies. Through optics, one Q marks several (sv_30_mark).
]]

local K = Rhylib.Skills
local UI = Rhylib.UI

K.clientMarks = K.clientMarks or {}   -- [entity index] = { by, untilT }

local COL = Color(242, 160, 60)
local COL_OUT = Color(0, 0, 0, 170)

Rhylib.Hook.Add("Rhylib.MarkKey", "skills.mark", function()
    local me = LocalPlayer()
    if not (IsValid(me) and me:Alive() and K.Has(me, "mark_target")) then return end
    local G = Rhylib.Gear
    local optics = G and G.Looking and G.Looking(me) or false
    Rhylib.Net.Start("skills.markreq")
    net.WriteBool(optics)
    net.WriteUInt(math.Clamp(math.floor((optics and G.opticsFov or 0) * 10), 0, 1023), 10)
    net.SendToServer()
end)

Rhylib.Net.Receive("skills.mark", function()
    local by = net.ReadUInt(13)   -- (who marked)
    local replace = net.ReadBool()
    local quiet = net.ReadBool()   -- (sun visor auto spots: no blip every 5 s)
    local secs = net.ReadUInt(6)
    local n = net.ReadUInt(3)
    -- A new Q replaces that player's older marks.
    if replace then
        for t, mk in pairs(K.clientMarks) do
            if mk.by == by then K.clientMarks[t] = nil end
        end
    end
    for _ = 1, n do
        local idx = net.ReadUInt(13)
        local old = K.clientMarks[idx]
        local untilT = CurTime() + secs
        if not replace and old and old.by == by and old.untilT > untilT then untilT = old.untilT end
        K.clientMarks[idx] = { by = by, untilT = untilT }
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
    for idx, mk in pairs(K.clientMarks) do
        local e = Entity(idx)
        if mk.untilT <= now or (IsValid(e) and not alive(e)) then
            K.clientMarks[idx] = nil
        elseif IsValid(e) and not e:IsDormant() then
            local top = e:GetPos() + Vector(0, 0, e:OBBMaxs().z + 14)
            local sp = top:ToScreen()
            if sp.visible then
                local col = COL
                local left = mk.untilT - now
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

-- Sun visor down + Mark target: the marked enemy you look closest at (within
-- 6 degrees of the middle) gets the sectioned ring of the clones' helmet
-- view (four arcs with gaps), sized to it.
local RING_COL = Color(245, 245, 245, 235)
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
local function ring(cx, cy, r, s)
    local thick = math.max(2, math.floor(3 * s))
    for k = 0, 3 do
        local a0 = k * 90 + 15
        for t = -1, thick do
            arc(cx, cy, r + t, a0, a0 + 60, t == -1 and RING_OUT or RING_COL)
        end
    end
end

Rhylib.Hook.Add("HUDPaint", "skills.visorring", function()
    if next(K.clientMarks) == nil then return end
    local me = LocalPlayer()
    if not (IsValid(me) and me:Alive() and me:GetNW2Bool("rhylib_visorDown", false) and K.Has(me, "mark_target")) then return end
    local eye, aim = me:EyePos(), me:GetAimVector()
    local best, bestDot = nil, math.cos(math.rad(6))
    local now = CurTime()
    for idx, mk in pairs(K.clientMarks) do
        local e = Entity(idx)
        if mk.untilT > now and IsValid(e) and not e:IsDormant() and alive(e) then
            local d = e:WorldSpaceCenter() - eye
            local len = d:Length()
            local dot = len > 1 and aim:Dot(d / len) or -1
            if dot > bestDot then best, bestDot = e, dot end
        end
    end
    if not best then return end
    local c = best:WorldSpaceCenter()
    local sp = c:ToScreen()
    if not sp.visible then return end
    -- (about the target's height on screen)
    local top = (c + Vector(0, 0, (best:OBBMaxs().z - best:OBBMins().z) * 0.5)):ToScreen()
    local s = ScrH() / 1080
    local r = math.Clamp(math.abs(sp.y - top.y) * 0.75, 14 * s, 90 * s)
    draw.NoTexture()
    ring(sp.x, sp.y, r, s)
end)
