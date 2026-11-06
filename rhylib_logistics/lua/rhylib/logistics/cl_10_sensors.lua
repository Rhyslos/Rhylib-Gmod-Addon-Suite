--[[
    Sensor array alerts (client; field technicians and officers get them,
    net logi.alert from sv_10_sensors.lua).

    L.alerts = { [beacon entity index] = { count, pos, label, at } }. On
    screen, right of centre: one line per beacon with droids inside
    ("SENSOR · Sensor 3 · 6 droids · 140 m NE"), newest first, a soft beep
    when a beacon first picks some up or the count goes up. On the compass
    (rhylib_radio R.radarExtras): an arrow on the rim toward each one, or
    a red ring at the beacon when it is within the compass. Every player's
    compass also shows each beacon itself as a blue radar mark (a dot with
    two waves; L.beaconEnts, kept by the beacon entity). Alerts are cleared when
    the count drops to 0 (or the beacon is gone / jammed / out of power),
    and all of them on net logi.clear (you stopped being a technician or
    officer).

    The beacon's wheel (rhylib_menus, hook Rhylib.WheelEntityOptions):
    Put in a power cell, Pick up (net logi.beacon).
]]

local L = Rhylib.Logistics
L.alerts = L.alerts or {}
L.beaconEnts = L.beaconEnts or {}   -- [beacon] = true (entities/rhylib_sensor_beacon.lua)

local UNITS_PER_M = 52.49   -- (Source units in a metre)

Rhylib.Net.Receive("logi.alert", function()
    local idx, count, pos, label = net.ReadUInt(13), net.ReadUInt(7), net.ReadVector(), net.ReadString()
    local old = L.alerts[idx]
    if count <= 0 then
        L.alerts[idx] = nil
        return
    end
    L.alerts[idx] = { count = count, pos = pos, label = label, at = old and old.at or CurTime() }
    if not old or count > old.count then surface.PlaySound("buttons/blip1.wav") end
end)

-- (no longer a field technician or officer: every alert goes)
Rhylib.Net.Receive("logi.clear", function() L.alerts = {} end)

local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function compassDir(from, to)
    local d = to - from
    local ang = math.deg(math.atan2(d.x, d.y))   -- (0 = north, +y)
    return DIRS[math.floor(((ang % 360) + 22.5) / 45) % 8 + 1]
end

-- The alert line's plate (theme tokens; the compass marks below keep
-- their own red and blue).
local COL_BG = Rhylib.UI.Col("logi.alertBg", 30, 8, 6, 190)
local COL_TEXT = Rhylib.UI.Col("logi.alertText", 255, 150, 120)
local COL_EDGE = Rhylib.UI.Col("logi.alert", 255, 80, 60)

Rhylib.Hook.Add("HUDPaint", "logistics.sensors", function()
    if not next(L.alerts) then return end
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local UI = Rhylib.UI
    local font = UI and UI.Font and UI.Font(15, 700) or "DermaDefaultBold"
    local s = ScrH() / 1080
    local list = {}
    for _, a in pairs(L.alerts) do list[#list + 1] = a end
    table.sort(list, function(a, b) return a.at > b.at end)
    local x, y = ScrW() * 0.5 + 140 * s, ScrH() * 0.30
    local mp = me:GetPos()
    for i = 1, math.min(#list, 6) do
        local a = list[i]
        local m = math.floor(mp:Distance(a.pos) / UNITS_PER_M)
        local text = string.format("SENSOR  ·  %s  ·  %d droid%s  ·  %d m %s", a.label, a.count, a.count == 1 and "" or "s", m, compassDir(mp, a.pos))
        surface.SetFont(font)
        local tw, th = surface.GetTextSize(text)
        local pad = math.floor(6 * s)
        local pulse = 0.6 + 0.4 * math.abs(math.sin((CurTime() - a.at) * 3))
        draw.RoundedBox(0, x - pad, y - pad * 0.5, tw + pad * 2, th + pad, COL_BG)
        surface.SetDrawColor(Rhylib.UI.Kit.C.edgeDark)
        surface.DrawOutlinedRect(x - pad, y - pad * 0.5, tw + pad * 2, th + pad)
        surface.SetDrawColor(COL_EDGE.r, COL_EDGE.g, COL_EDGE.b, 255 * pulse)
        surface.DrawRect(x - pad, y - pad * 0.5, math.max(2, math.floor(3 * s)), th + pad)
        draw.SimpleText(text, font, x, y, COL_TEXT)
        y = y + th + pad * 1.6
    end
end)

-- The compass (rhylib_radio): an arrow on the rim toward each beacon with
-- droids, or a red ring at it when it is within the compass.
local function addCompass()
    local R = Rhylib.Radio
    if not (R and R.radarExtras) then return end
    R.radarExtras["logistics.sensors"] = function(cx, cy, r, mp, fx, fy, k)
        if not next(L.alerts) then return end
        draw.NoTexture()
        for _, a in pairs(L.alerts) do
            local dx, dy = a.pos.x - mp.x, a.pos.y - mp.y
            -- (screen: forward up; right = the view's right)
            local fwd = dx * fx + dy * fy
            local right = dx * fy - dy * fx
            local px, py = right * k, -fwd * k
            local len = math.sqrt(px * px + py * py)
            local pulse = 0.55 + 0.45 * math.abs(math.sin(CurTime() * 4))
            surface.SetDrawColor(255, 80, 60, 230 * pulse)
            if len < r * 0.92 then
                local rr = math.max(4, math.floor(r * 0.12))
                surface.DrawCircle(cx + px, cy + py, rr, 255, 80, 60, 230 * pulse)
            else
                local ux, uy = px / math.max(len, 1), py / math.max(len, 1)
                local tipx, tipy = cx + ux * (r - 2), cy + uy * (r - 2)
                local bx, by = cx + ux * (r - 12), cy + uy * (r - 12)
                local w = 6
                surface.DrawPoly({ { x = tipx, y = tipy }, { x = bx - uy * w, y = by + ux * w }, { x = bx + uy * w, y = by - ux * w } })
            end
        end
    end
end
-- Every beacon on the compass for everyone: a blue dot with two radar
-- waves over it (dimmer with no power), only when within the compass.
local BLUE = Color(70, 150, 255)
local function radarMark(x, y, s, a)
    surface.SetDrawColor(BLUE.r, BLUE.g, BLUE.b, a)
    surface.DrawRect(x - s * 0.3, y - s * 0.3 + s * 0.35, s * 0.6, s * 0.6)
    for w = 1, 2 do
        local rad = s * 0.45 * w + s * 0.2
        local lx, ly
        for i = 0, 6 do
            local ang = math.rad(-135 + i * 15)   -- (an arc opening upward)
            local px, py = x + math.cos(ang) * rad, y + s * 0.35 + math.sin(ang) * rad
            if lx then surface.DrawLine(lx, ly, px, py) end
            lx, ly = px, py
        end
    end
end

local function addBeacons()
    local R = Rhylib.Radio
    if not (R and R.radarExtras) then return end
    R.radarExtras["logistics.beacons"] = function(cx, cy, r, mp, fx, fy, k)
        if not next(L.beaconEnts) then return end
        draw.NoTexture()
        local s = math.max(6, math.floor(r * 0.11))
        for e in pairs(L.beaconEnts) do
            if IsValid(e) then
                local pos = e:GetPos()
                local px, py, al
                if R.RadarPlace then
                    px, py, al = R.RadarPlace(pos.x - mp.x, pos.y - mp.y, fx, fy, k, r, r * 0.88)
                else
                    local dx, dy = pos.x - mp.x, pos.y - mp.y
                    px, py, al = (dx * fy - dy * fx) * k, -(dx * fx + dy * fy) * k, 1
                    if px * px + py * py >= (r * 0.88) ^ 2 then px = nil end
                end
                if px then
                    radarMark(cx + px, cy + py, s, (e.Powered and e:Powered() and 235 or 110) * al)
                end
            else
                L.beaconEnts[e] = nil
            end
        end
    end
end

addCompass()
addBeacons()
Rhylib.Hook.Add("InitPostEntity", "logistics.beacons", addBeacons)
if Rhylib.After then Rhylib.After("radio", addBeacons) end
Rhylib.Hook.Add("InitPostEntity", "logistics.compass", addCompass)
if Rhylib.After then Rhylib.After("radio", addCompass) end

-- The beacon's wheel (rhylib_menus).
Rhylib.Hook.Add("Rhylib.WheelEntityOptions", "logistics.beacon", function(ent, me, add)
    if not (IsValid(ent) and ent:GetClass() == "rhylib_sensor_beacon") then return end
    local function op(n)
        return function()
            Rhylib.Net.Start("logi.beacon")
            net.WriteEntity(ent)
            net.WriteUInt(n, 2)
            net.SendToServer()
        end
    end
    local left = math.max(0, ent:GetPowerEnd() - CurTime())
    local W = Rhylib.Weapons
    local hasCell = W and me:GetAmmoCount("rhylib_cell") > 0
    add("Put in a power cell", hasCell and op(1) or nil, { sub = left > 0 and string.format("%d:%02d left now", math.floor(left / 60), math.floor(left % 60)) or "No power",
        disabled = not hasCell and "You have no power cell" or nil, order = 20 })
    add("Pick up", op(2), { sub = "Back into your inventory (the cell in it is lost)", order = 60 })
end)

-- (clear alerts for beacons that are gone)
timer.Create("Rhylib.Logistics.AlertSweep", 5, 0, function()
    for idx in pairs(L.alerts) do
        local e = Entity(idx)
        if IsValid(e) and e:GetClass() ~= "rhylib_sensor_beacon" then L.alerts[idx] = nil end
    end
end)
