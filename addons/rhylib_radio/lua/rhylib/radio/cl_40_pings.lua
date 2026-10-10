--[[
    Squad pings, client side (sh_40_pings.lua has the overview).
    Client convars: rhylib_radio_pingkey (default "o"; any key or mouse
    button) and rhylib_radio_pingchat (chat line too, default 1).

    Hold the ping key (client convar rhylib_radio_pingkey, default O) for
    the wheel; release on a type to send it (release in the middle =
    cancel). Without rhylib_menus a tap sends "Enemy".
    R.pings[from entindex * 16 + kind] = { kind, from, name, pos, ent, at,
    untilT }: one of each kind per player, a new one replaces the old.
    Drawn as markers on screen (pinned to the screen edge with an arrow
    when off screen; fade out over the last 2 s) and as small icons on the
    squad compass (R.DrawPingsOnRadar, called from cl_20_hud's drawCore).
]]

local R = Rhylib.Radio
local UI = Rhylib.UI

local keyVar = CreateClientConVar("rhylib_radio_pingkey", "o", true, false, "Hold for the squad ping wheel")
local chatVar = CreateClientConVar("rhylib_radio_pingchat", "1", true, false, "Squad pings also show a chat line")

-- Ping symbols (0-1 box, see cl_05_icons).
R.ICONS.ping_move = { { "P", { .5, .06, .92, .56, .08, .56 } }, { "R", .36, .56, .28, .36 } }
R.ICONS.ping_hold = { { "P", { .32, .06, .68, .06, .94, .32, .94, .68, .68, .94, .32, .94, .06, .68, .06, .32 } }, { "R", .22, .44, .56, .12, true } }
R.ICONS.ping_danger = { { "P", { .5, .06, .96, .9, .04, .9 } }, { "R", .45, .34, .1, .3, true }, { "R", .45, .7, .1, .1, true } }

R.pings = R.pings or {}

--------------------------------------------------------------------------
-- Sending: the wheel
--------------------------------------------------------------------------

local function send(k)
    Rhylib.Net.Start("radio.ping")
    net.WriteUInt(k, R.PING_BITS)
    net.SendToServer()
end

local function blocked()
    if gui.IsGameUIVisible() or gui.IsConsoleVisible() or vgui.CursorVisible() then return true end
    if Rhylib.Menus and Rhylib.Menus.keyTrapping then return true end   -- (rebinding a key)
    local ply = LocalPlayer()
    if not IsValid(ply) or ply:IsTyping() then return true end
    local f = vgui.GetKeyboardFocus()
    return IsValid(f) and f:GetClassName() == "TextEntry"
end

local function wheelList(me)
    local jammed = R.Jammed(me) and "Comms jammed" or nil
    local list = {}
    for k, p in ipairs(R.PINGS) do
        list[#list + 1] = {
            label = p.label,
            sub = p.self and "On you" or (p.track and "Where you aim (sticks to droids)" or "Where you aim"),
            col = p.col,
            disabled = jammed,
            run = function() send(k) end,
        }
    end
    return list
end

local wasDown, lastSquad = false, 0
Rhylib.Hook.Add("Think", "radio.pingkey", function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    -- left or switched squads: the old squad's pings go
    local sqNow = R.SquadOf(me)
    if sqNow ~= lastSquad then
        lastSquad = sqNow
        R.pings = {}
    end
    local s = keyVar:GetString()
    local code = s ~= "" and input.GetKeyCode(s) or 0
    local down = code and code > 0 and input.IsButtonDown(code) or false   -- (mouse buttons too)
    local pressed = down and not wasDown
    wasDown = down
    if not pressed or blocked() or not me:Alive() then return end
    if R.SquadOf(me) == 0 then
        R.Note("Join a squad to send pings (Radio page)")
        return
    end
    local W = Rhylib.Menus and Rhylib.Menus.Wheel
    if not (W and W.OpenList) then
        send(2)   -- (no wheel: a tap pings "Enemy")
        return
    end
    if W.open then return end
    W.OpenList("Ping", wheelList(me), code)
end)

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

Rhylib.Net.Receive("radio.ping", function()
    local from = net.ReadEntity()
    local k = net.ReadUInt(R.PING_BITS)
    local pos = net.ReadVector()
    local ent = net.ReadEntity()
    local p = R.PINGS[k]
    if not (p and IsValid(from)) then return end
    local now = RealTime()
    R.pings[from:EntIndex() * 16 + k] = {
        kind = k, from = from, name = from:Nick(), pos = p.self and (pos + Vector(0, 0, 90)) or pos, ent = IsValid(ent) and ent or nil,
        at = now, untilT = now + (p.life or 15),
    }
    surface.PlaySound(p.id == "enemy" and "buttons/blip2.wav" or "buttons/blip1.wav")
    if chatVar:GetBool() then
        chat.AddText(R.COL.squad, "[Squad] ", Color(225, 225, 225), from:Nick() .. ": ", p.col, p.chat)
    end
end)

-- Where a ping is now (an entity it follows, else its spot).
local UP_SELF, UP_ENEMY = Vector(0, 0, 90), Vector(0, 0, 40)
local function pingPos(g)
    local p = R.PINGS[g.kind]
    local e = g.ent
    if e == nil then return g.pos end
    if not IsValid(e) then
        -- (the droid is gone: fade; a pinger who left: stays put)
        if p.track then g.untilT = math.min(g.untilT, RealTime() + 1) end
        g.ent = nil
    elseif e:IsPlayer() then
        if not e:Alive() then
            g.ent = nil   -- (died: the ping stays where they fell, never jumps to the respawn)
        else
            local mp = R.MatePos and R.MatePos(e) or (not e:IsDormant() and e:GetPos())
            if mp then g.pos = mp + UP_SELF end
        end
    elseif not e:IsDormant() then
        if e:IsNPC() and e:Health() <= 0 then
            g.untilT = math.min(g.untilT, RealTime() + 1)
            g.ent = nil
        else
            g.pos = e:WorldSpaceCenter() + UP_ENEMY
        end
    end
    -- (a dormant droid: keep its last known spot)
    return g.pos
end

--------------------------------------------------------------------------
-- Markers on screen
--------------------------------------------------------------------------

local PLATE, OUTLINE = Color(10, 13, 15, 200), Color(0, 0, 0, 230)
local tmp = Color(255, 255, 255)
local RBG = Color(10, 13, 15, 220)

local function fadeOf(g, now)
    local a = math.Clamp((g.untilT - now) / 2, 0, 1)
    local pulse = math.Clamp(1 - (now - g.at) / 0.6, 0, 1)
    return a, pulse
end

Rhylib.Hook.Add("HUDPaint", "radio.pings", function()
    if next(R.pings) == nil then return end
    local HUD = Rhylib.HUD
    if HUD and HUD.Hidden and HUD.Hidden() then return end
    local me = LocalPlayer()
    local now = RealTime()
    local W, H = ScrW(), ScrH()
    local s = H / 1080
    local eye = EyePos()
    local font, small = UI.Font(12, 700), UI.Font(11, 500)
    for key, g in pairs(R.pings) do
        local p = R.PINGS[g.kind]
        if now >= g.untilT or not p then
            R.pings[key] = nil
        elseif not (p.self and g.from == me) then
            local pos = pingPos(g)
            local a, pulse = fadeOf(g, now)
            local sc = pos:ToScreen()
            local x, y = sc.x, sc.y
            local margin = 60 * s
            local off = not sc.visible or x < margin or x > W - margin or y < margin or y > H - margin
            if off then
                -- pinned to the screen edge, pointing the way
                local dir = (pos - eye)
                local ang = EyeAngles()
                local fx, rx = dir:Dot(ang:Forward()), dir:Dot(ang:Right())
                local uy = dir:Dot(ang:Up())
                local vx, vy = rx, -uy
                if fx < 0 and math.abs(vx) < 1 and math.abs(vy) < 1 then vx = 1 end
                local len = math.sqrt(vx * vx + vy * vy)
                if len < 0.001 then vx, vy, len = 0, 1, 1 end
                vx, vy = vx / len, vy / len
                local hw, hh = W * 0.5 - margin, H * 0.5 - margin
                local t = math.min(hw / math.max(math.abs(vx), 0.001), hh / math.max(math.abs(vy), 0.001))
                x, y = W * 0.5 + vx * t, H * 0.5 + vy * t
                -- arrow
                local ax, ay = x + vx * 22 * s, y + vy * 22 * s
                local px, py = -vy, vx
                tmp.r, tmp.g, tmp.b, tmp.a = p.col.r, p.col.g, p.col.b, 220 * a
                draw.NoTexture()
                surface.SetDrawColor(tmp)
                surface.DrawPoly({
                    { x = ax + vx * 9 * s, y = ay + vy * 9 * s },
                    { x = ax + px * 7 * s, y = ay + py * 7 * s },
                    { x = ax - px * 7 * s, y = ay - py * 7 * s },
                })
            end
            local size = math.floor((26 + 10 * pulse) * s)
            local hx, hy = math.floor(x - size * 0.5), math.floor(y - size * 0.5)
            draw.NoTexture()
            surface.SetDrawColor(PLATE.r, PLATE.g, PLATE.b, PLATE.a * a)
            surface.DrawRect(hx - 4, hy - 4, size + 8, size + 8)
            tmp.r, tmp.g, tmp.b, tmp.a = p.col.r, p.col.g, p.col.b, 255 * a
            surface.SetDrawColor(tmp)
            surface.DrawOutlinedRect(hx - 4, hy - 4, size + 8, size + 8, math.max(1, math.floor(2 * s)))
            R.DrawIcon(p.icon, hx + 2, hy + 2, size - 4, tmp, Color(PLATE.r, PLATE.g, PLATE.b, 230 * a))
            local m = math.floor(pos:Distance(eye) * 0.01905)
            local ty = hy + size + 6 * s
            OUTLINE.a = 200 * a
            draw.SimpleTextOutlined(p.short .. "  " .. m .. " m", font, x, ty, tmp, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, OUTLINE)
            draw.SimpleTextOutlined(g.name, small, x, ty + 14 * s, Color(220, 225, 228, 200 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, OUTLINE)
        end
    end
end)

--------------------------------------------------------------------------
-- On the squad compass (called from cl_20_hud's drawCore)
--------------------------------------------------------------------------

-- R.DrawPingsOnRadar(cx, cy, r, mp, fx, fy, k): ping icons on a compass
-- (mp = your position, fx/fy = your forward, k = pixels per unit; same
-- maths as the mates in drawCore). Clamped to the rim.
function R.DrawPingsOnRadar(cx, cy, r, mp, fx, fy, k)
    if next(R.pings) == nil then return end
    local now = RealTime()
    local me = LocalPlayer()
    local size = math.max(8, math.floor(r * 0.16))
    for _, g in pairs(R.pings) do
        local p = R.PINGS[g.kind]
        if p and now < g.untilT and not (p.self and g.from == me) then
            local pos = pingPos(g)
            local dx, dy = pos.x - mp.x, pos.y - mp.y
            local fwd = dx * fx + dy * fy
            local right = dx * fy - dy * fx
            local sx, sy = right * k, -fwd * k
            local len = math.sqrt(sx * sx + sy * sy)
            local lim = r - size * 0.6
            if len > lim then sx, sy = sx / len * lim, sy / len * lim end
            local a = fadeOf(g, now)
            tmp.r, tmp.g, tmp.b, tmp.a = p.col.r, p.col.g, p.col.b, 255 * a
            RBG.a = 220 * a
            R.DrawIcon(p.icon, cx + sx - size * 0.5, cy + sy - size * 0.5, size, tmp, RBG)
        end
    end
end

--------------------------------------------------------------------------
-- Settings (rhylib_menus)
--------------------------------------------------------------------------

local function addSettings()
    local M = Rhylib.Menus
    if not (M and M.AddSetting) then return end
    M.AddSetting("Radio", { id = "radio.pingkey", order = 35, title = "Squad ping wheel (hold)", kind = "key", convar = "rhylib_radio_pingkey", short = "Ping" })
    M.AddSetting("Radio", { id = "radio.pingchat", order = 36, title = "Squad pings also show in chat", kind = "toggle", convar = "rhylib_radio_pingchat" })
end
Rhylib.Hook.Add("InitPostEntity", "radio.pingsettings", addSettings)
addSettings()
