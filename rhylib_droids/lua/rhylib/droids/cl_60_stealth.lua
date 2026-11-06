--[[
    Stealth (client): what players and staff see of unaware droids
    (sv_60_stealth.lua sends it; sh_50_stealth.lua has the rules).

    Players (Server setting stealthHud):
      meter  a small plate under the crosshair: an eye and a bar with the
             highest meter any unaware droid has on you. Light while it
             only notices you, amber once it is suspicious, a red flash and
             SPOTTED when one is alerted by seeing you. Fades out at zero.
      arcs   up to three short arcs round the crosshair, each pointing at
             where a droid stood when it last saw you (only droids that
             saw you in the last half second, never ones that only heard
             you) and filling with its meter (same colours).
      none   nothing.
    HUD colours (Settings > HUD colours): the meter's and arcs' amber is
    token droids.stealthWarn (key warn), their red and SPOTTED
    droids.stealthSpotted (key danger). The "?" / "!" over droids and the
    staff cones keep their own colours.
    Over droids, for everyone who can see the droid (a trace to its head,
    never through walls) within about 40 m: an amber "?" while it is
    suspicious or searching, a red "!" just after it is alerted out of
    stealth and while it radios the alarm.
    Staff holding the toolgun: each unaware / suspicious / searching
    droid's view cone on the ground (central cone bright, the corners of
    its eye dim, out to its sight range) and its meter as a bar over it.

    Nets read: droids.seen (Bool spotted, UInt 2 n, n x (UInt 13 droid,
    UInt 8 meter, UInt 2 state)), droids.smeter (UInt 7 n, n x (UInt 13
    droid, UInt 8 meter)).
]]

local D = Rhylib.Droids
local UI = Rhylib.UI

-- What the server sent.
-- (x, y: where that droid stood when the message came, for the arcs;
-- ok false = it wasn't in view on this client, no arc)
local seen = { n = 0, ent = {}, v = {}, s = {}, x = {}, y = {}, ok = {}, at = 0 }
local spottedAt = -100
local staffM = {}   -- [entindex] = meter 0-1

Rhylib.Net.Receive("droids.seen", function()
    local spotted = net.ReadBool()
    local n = net.ReadUInt(2)
    for i = 1, n do
        seen.ent[i] = net.ReadUInt(13)
        seen.v[i] = net.ReadUInt(8) / 255
        seen.s[i] = net.ReadUInt(2)
        local e = Entity(seen.ent[i])
        local okE = IsValid(e) and not e:IsDormant()
        seen.ok[i] = okE
        if okE then
            local p = e:GetPos()
            seen.x[i], seen.y[i] = p.x, p.y
        end
    end
    seen.n = n
    seen.at = RealTime()
    if spotted then
        spottedAt = RealTime()
        surface.PlaySound("buttons/blip1.wav")
    end
end)

Rhylib.Net.Receive("droids.smeter", function()
    for k in pairs(staffM) do staffM[k] = nil end
    local n = net.ReadUInt(7)
    for _ = 1, n do
        local idx = net.ReadUInt(13)
        staffM[idx] = net.ReadUInt(8) / 255
    end
end)

-- Colours (the house tokens) and cached text colours whose alpha is set
-- before drawing. C_AMBER / C_RED are HUD colour tokens, read when drawing.
local C_PLATE = Color(14, 16, 15)
local C_TRACK = Color(42, 46, 43)
local C_TEXT = Color(228, 227, 220)
local C_AMBER = UI.HudCol("warn", "droids.stealthWarn", 239, 159, 39)
local C_RED = UI.HudCol("danger", "droids.stealthSpotted", 226, 75, 74)
local T_SPOT = Color(226, 75, 74)   -- (SPOTTED: C_RED with its alpha)
local T_RED = Color(226, 75, 74)
local T_AMBER = Color(239, 159, 39)
local T_DIM = Color(138, 140, 132)
local T_BLACK = Color(0, 0, 0)

local function S(n) return math.Round(n * ScrH() / 1080) end

local function setCol(c, a) surface.SetDrawColor(c.r, c.g, c.b, a) end

-- The eye icon: polygons built once per screen size, round its centre.
local eyeFor, eyeOuter, eyePupil = nil, nil, nil
local function buildEye(cx, cy, w, h)
    local key = cx * 100000 + cy
    if eyeFor == key then return end
    eyeFor = key
    eyeOuter, eyePupil = {}, {}
    local seg = 8
    for i = 0, seg do   -- (upper lid, left to right)
        local t = i / seg
        eyeOuter[#eyeOuter + 1] = { x = cx - w / 2 + w * t, y = cy - math.sin(t * math.pi) * h / 2 }
    end
    for i = seg - 1, 1, -1 do   -- (lower lid, right to left)
        local t = i / seg
        eyeOuter[#eyeOuter + 1] = { x = cx - w / 2 + w * t, y = cy + math.sin(t * math.pi) * h / 2 }
    end
    local r = h * 0.3
    for i = 0, 9 do
        local a = i / 10 * math.pi * 2
        eyePupil[i + 1] = { x = cx + math.cos(a) * r, y = cy + math.sin(a) * r }
    end
end
Rhylib.Hook.Add("OnScreenSizeChanged", "droids.stealtheye", function() eyeFor = nil end)

local shownA = 0   -- (the plate fades in and out)

local function stateCol(st, spotted)
    if spotted then return C_RED end
    if st == 2 then return C_AMBER end
    return C_TEXT
end

local function drawMeter(now, spotted)
    local top, st = 0, 1
    for i = 1, seen.n do
        if seen.v[i] > top then top, st = seen.v[i], seen.s[i] end
    end
    local want = (top > 0 or spotted) and 1 or 0
    shownA = shownA + (want - shownA) * math.min(FrameTime() * 8, 1)
    if shownA < 0.02 then return end
    local a = shownA * 255
    local w, h = S(132), S(16)
    local x, y = math.floor(ScrW() * 0.5 - w / 2), math.floor(ScrH() * 0.5 + S(46))
    draw.NoTexture()
    setCol(C_PLATE, a * 0.85)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(0, 0, 0, a)
    surface.DrawOutlinedRect(x, y, w, h)
    -- the eye
    local col = stateCol(st, spotted)
    local ex, ey = x + S(12), y + h / 2
    buildEye(ex, ey, S(15), S(9))
    setCol(col, a)
    surface.DrawPoly(eyeOuter)
    setCol(C_PLATE, a)
    surface.DrawPoly(eyePupil)
    -- the bar
    local bx, bw, bh = x + S(24), w - S(30), S(4)
    local by = y + math.floor((h - bh) / 2)
    setCol(C_TRACK, a)
    surface.DrawRect(bx, by, bw, bh)
    local fill = spotted and 1 or top
    -- (spotted: the bar flashes red)
    local fa = spotted and a * (0.55 + 0.45 * math.abs(math.sin(now * 12))) or a
    setCol(col, fa)
    surface.DrawRect(bx, by, math.floor(bw * fill + 0.5), bh)
    if spotted then
        T_SPOT.r, T_SPOT.g, T_SPOT.b, T_SPOT.a, T_BLACK.a = C_RED.r, C_RED.g, C_RED.b, a, a
        draw.SimpleTextOutlined("SPOTTED", UI.Font(15, 800), ScrW() * 0.5, y - S(3), T_SPOT, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, T_BLACK)
    end
end

-- Arcs round the crosshair toward each droid noticing you.
local ARC_SEG, ARC_SPAN = 9, math.rad(34)
local function drawArcs(now, spotted)
    local cx, cy = ScrW() * 0.5, ScrH() * 0.5
    local R, th = S(66), S(4)
    local segLen = R * ARC_SPAN / ARC_SEG + 1
    local eye, eyaw = EyePos(), EyeAngles().y
    draw.NoTexture()
    for i = 1, seen.n do
        if seen.ok[i] then
            -- (toward where it stood when it last saw you, not where it is now)
            local yaw = math.deg(math.atan2(seen.y[i] - eye.y, seen.x[i] - eye.x))
            local rel = math.rad(-math.NormalizeAngle(yaw - eyaw))   -- (clockwise from straight up)
            local col = stateCol(seen.s[i], false)
            local lit = math.ceil(seen.v[i] * ARC_SEG)
            for j = 0, ARC_SEG - 1 do
                local ang = rel - ARC_SPAN / 2 + ARC_SPAN * (j + 0.5) / ARC_SEG
                local px, py = cx + math.sin(ang) * R, cy - math.cos(ang) * R
                if j < lit then setCol(col, 235) else setCol(C_TRACK, 170) end
                surface.DrawTexturedRectRotated(px, py, segLen, th, -math.deg(ang))
            end
        end
    end
    if spotted then
        local a = 255 * math.Clamp(1.6 - (now - spottedAt), 0, 1)
        T_SPOT.r, T_SPOT.g, T_SPOT.b, T_SPOT.a, T_BLACK.a = C_RED.r, C_RED.g, C_RED.b, a, a
        draw.SimpleTextOutlined("SPOTTED", UI.Font(15, 800), cx, cy + R + S(10), T_SPOT, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, T_BLACK)
    end
end

--------------------------------------------------------------------------
-- Droids near you (the "?" / "!" marks and the staff view)
--------------------------------------------------------------------------

local droids, droidsAt = {}, 0
local marks, marksN, marksAt = {}, 0, 0   -- marks[i] = { ent, kind } (1 "?", 2 "!")
local mtr = {}
local mtrData = { mask = MASK_VISIBLE, output = mtr }
local MARK_R = 2100
local hv = Vector()   -- (reused: a point over a droid's head)

-- Droids tracked as they come and go (one full scan at load / map start
-- only); the list is rebuilt from the set only when it changed.
local droidSet, droidsDirty = {}, true
local function track(e)
    if IsValid(e) and e.IsRhylibDroid then droidSet[e] = true droidsDirty = true end
end
Rhylib.Hook.Add("OnEntityCreated", "droids.stealthtrack", function(e)
    -- (the class table may not be on it yet in this hook)
    timer.Simple(0, function() track(e) end)
end)
Rhylib.Hook.Add("NetworkEntityCreated", "droids.stealthtrack", track)
Rhylib.Hook.Add("EntityRemoved", "droids.stealthtrack", function(e)
    if droidSet[e] then droidSet[e] = nil droidsDirty = true end
end)
-- (droids that existed before this file loaded: once, and after a refresh)
local function scanAll()
    for _, e in ipairs(ents.GetAll()) do track(e) end
end
Rhylib.Hook.Add("InitPostEntity", "droids.stealthtrack", scanAll)
scanAll()

local function refreshDroids(now)
    if now < droidsAt or not droidsDirty then return end
    droidsAt = now + 0.5
    droidsDirty = false
    local n = 0
    for e in pairs(droidSet) do
        if IsValid(e) then
            n = n + 1
            droids[n] = e
        else
            droidSet[e] = nil
        end
    end
    for i = n + 1, #droids do droids[i] = nil end
end

local function refreshMarks(now)
    if now < marksAt then return end
    marksAt = now + 0.25
    local eye = EyePos()
    local ct = CurTime()
    local n = 0
    for _, d in ipairs(droids) do
        if IsValid(d) and not d:IsDormant() and d:Health() > 0 then
            local s = d:GetNW2Int("rhylib_sstate", 0)
            local kind = (s == 4 or ct - d:GetNW2Float("rhylib_salert", -100) < 2) and 2 or (s == 2 or s == 3) and 1 or nil
            if kind and d:GetPos():DistToSqr(eye) < MARK_R * MARK_R then
                mtrData.start, mtrData.filter = eye, LocalPlayer()
                hv:Set(d:GetPos())
                hv.z = hv.z + 66
                mtrData.endpos = hv
                util.TraceLine(mtrData)
                if not mtr.Hit then
                    n = n + 1
                    local m = marks[n]
                    if not m then m = {} marks[n] = m end
                    m.ent, m.kind = d, kind
                end
            end
        end
    end
    marksN = n
end

local function holdingTool()
    local me = LocalPlayer()
    local w = IsValid(me) and me:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == "rhylib_toolgun"
end

Rhylib.Hook.Add("HUDPaint", "droids.stealth", function()
    local now = RealTime()
    local mode = D.Cfg("stealthHud")
    if mode ~= "none" then
        local spotted = now - spottedAt < 1.6
        if mode == "arcs" then drawArcs(now, spotted) else drawMeter(now, spotted) end
    end
    refreshDroids(now)
    refreshMarks(now)
    if marksN > 0 then
        local font = UI.Font(30, 800)
        for i = 1, marksN do
            local m = marks[i]
            local d = m.ent
            if IsValid(d) and not d:IsDormant() then
                hv:Set(d:GetPos())
                hv.z = hv.z + (d:Kind().big and 104 or 90)
                local sp = hv:ToScreen()
                if sp.visible then
                    if m.kind == 2 then
                        -- (radioing: it pulses)
                        local a = d:GetNW2Int("rhylib_sstate", 0) == 4 and (150 + 105 * math.abs(math.sin(now * 6))) or 255
                        T_RED.a, T_BLACK.a = a, a
                        draw.SimpleTextOutlined("!", font, sp.x, sp.y, T_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, T_BLACK)
                    else
                        T_AMBER.a, T_BLACK.a = 255, 255
                        draw.SimpleTextOutlined("?", font, sp.x, sp.y, T_AMBER, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, T_BLACK)
                    end
                end
            end
        end
    end
    -- Staff: each unaware droid's meter over it.
    if holdingTool() and next(staffM) then
        local eye = EyePos()
        local bw, bh = S(48), S(4)
        draw.NoTexture()
        for _, d in ipairs(droids) do
            local v = IsValid(d) and staffM[d:EntIndex()]
            if v and d:GetPos():DistToSqr(eye) < 2500 * 2500 then
                hv:Set(d:GetPos())
                hv.z = hv.z + (d:Kind().big and 112 or 100)
                local sp = hv:ToScreen()
                if sp.visible then
                    local x, y = math.floor(sp.x - bw / 2), math.floor(sp.y)
                    surface.SetDrawColor(0, 0, 0, 220)
                    surface.DrawRect(x - 1, y - 1, bw + 2, bh + 2)
                    setCol(C_TRACK, 255)
                    surface.DrawRect(x, y, bw, bh)
                    setCol(d:GetNW2Int("rhylib_sstate", 0) >= 2 and C_AMBER or C_TEXT, 255)
                    surface.DrawRect(x, y, math.floor(bw * v + 0.5), bh)
                end
            end
        end
    end
end)

-- Staff: view cones on the ground (nearest 20 within 3000 units).
local ca, cb = Vector(), Vector()
local CONE_ARC = 10
local function cosLine(px, py, z, yaw, len)
    local r = math.rad(yaw)
    cb:SetUnpacked(px + math.cos(r) * len, py + math.sin(r) * len, z)
end

local COL_FULL, COL_WIDE = Color(133, 183, 235, 200), Color(133, 183, 235, 70)
local COL_SUSP, COL_SUSPW = Color(239, 159, 39, 220), Color(239, 159, 39, 80)

Rhylib.Hook.Add("PostDrawTranslucentRenderables", "droids.stealthcones", function(depth, sky)
    if depth or sky or not holdingTool() then return end
    local eye = EyePos()
    local hf = D.Cfg("stealthFov") * 0.5
    local hw = D.Cfg("stealthFovWide") * 0.5
    local drawn = 0
    for _, d in ipairs(droids) do
        if drawn >= 20 then break end
        local s = IsValid(d) and d:Health() > 0 and d:GetNW2Int("rhylib_sstate", 0) or 0
        if s >= 1 and s <= 3 then
            local p = d:GetPos()
            if p:DistToSqr(eye) < 3000 * 3000 then
                drawn = drawn + 1
                local R = D.Cfg(d:Kind().range)
                local yaw = d:GetAngles().y
                local z = p.z + 4
                local full, wide = s == 1 and COL_FULL or COL_SUSP, s == 1 and COL_WIDE or COL_SUSPW
                ca:SetUnpacked(p.x, p.y, z)
                -- edges of the central cone and of the whole cone
                for side = -1, 1, 2 do
                    cosLine(p.x, p.y, z, yaw + side * hf, R)
                    render.DrawLine(ca, cb, full, true)
                    cosLine(p.x, p.y, z, yaw + side * hw, R * 0.5)
                    render.DrawLine(ca, cb, wide, true)
                end
                -- the arc at its sight range
                cosLine(p.x, p.y, z, yaw - hf, R)
                for i = 1, CONE_ARC do
                    ca:Set(cb)
                    cosLine(p.x, p.y, z, yaw - hf + 2 * hf * i / CONE_ARC, R)
                    render.DrawLine(ca, cb, full, true)
                end
            end
        end
    end
end)
