--[[
    Calls on screen (state from sv_30_calls.lua's Global2 vars, so joiners
    get it too):
      Banner   centred near the top for 8 s when a call goes out (or when
               you join while one is up), with a sound and a chat line.
               Drawn after the menus (PostRenderVGUI), so it shows over them.
      Timer    timed calls only: a plate in the top-left corner (the
               visor's left cheek pocket is the radio's), the top line is
               the time left.
               Last minute amber; at 0 a short "time's up" banner.
    Client only. Admin.CurrentCall() gives the call that's up.
    Console: rhylib_call_status prints what this client sees (for testing).
]]

local Admin = Rhylib.Admin
local UI = Rhylib.UI

local GOLD = Color(230, 170, 70)
local TEXT = Color(228, 227, 220)
local DIM = Color(169, 168, 160)
local WARN = Color(239, 159, 39)
local BG = Color(14, 16, 15, 235)
local EDGE = Color(0, 0, 0, 230)
local HI = Color(170, 176, 180, 70)

local BANNER_TIME = 8
local UP_TIME = 4

local seen = -1          -- last rhylib_call_n we looked at
local banner             -- { title, sub, by, at (RealTime), up = true for time's up }
local wasRunning = false

local function S(n) return math.floor(n * ScrH() / 1080 + 0.5) end

-- The current call, or nil. timed: seconds left (nil = untimed).
-- Admin.CurrentCall(): { title, sub, by, ends (CurTime, 0 = untimed),
-- left (seconds, nil = untimed), total (timer length) } or nil. nil also
-- when a timer ran out, or an untimed call is older than callShowFor.
local function current()
    local title = GetGlobal2String("rhylib_call_title", "")
    if title == "" then return nil end
    local ends = GetGlobal2Float("rhylib_call_end", 0)
    local left
    if ends > 0 then
        left = ends - CurTime()
        if left <= 0 then return nil end
    elseif CurTime() - GetGlobal2Float("rhylib_call_at", 0) > (Admin.Cfg("callShowFor") or 900) then
        return nil
    end
    return { title = title, sub = GetGlobal2String("rhylib_call_sub", ""), by = GetGlobal2String("rhylib_call_by", ""),
        ends = ends, left = left, total = ends > 0 and (ends - GetGlobal2Float("rhylib_call_at", 0)) or nil }
end
Admin.CurrentCall = current

local function clock(secs)
    secs = math.max(0, math.ceil(secs))
    local h, m, s = math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- New calls (and the one that's up when you join), and timers running out.
-- A change of rhylib_call_n = a new call or one ended; seen starts at -1,
-- so a call that's up when you join shows its banner once.
timer.Create("rhylib_admin_calls", 0.25, 0, function()
    if not IsValid(LocalPlayer()) then return end
    local n = GetGlobal2Int("rhylib_call_n", 0)
    local c = current()
    if n ~= seen then
        seen = n
        if c then
            banner = { title = c.title, sub = c.sub, by = c.by, at = RealTime() }
            surface.PlaySound(Admin.Cfg("callSound") or "ambient/alarms/warningbell1.wav")
            chat.AddText(GOLD, "[" .. c.title .. "] ", TEXT, c.sub ~= "" and c.sub or "",
                DIM, c.left and ("  (" .. clock(c.left) .. ")") or "")
        else
            banner = nil
        end
        wasRunning = c ~= nil and c.left ~= nil
        return
    end
    local running = c ~= nil and c.left ~= nil
    if wasRunning and not running and GetGlobal2String("rhylib_call_title", "") ~= "" then
        banner = { title = GetGlobal2String("rhylib_call_title", ""), sub = "Time's up", at = RealTime(), up = true }
        surface.PlaySound("buttons/blip1.wav")
    end
    wasRunning = running
end)

--------------------------------------------------------------------------
-- Banner
--------------------------------------------------------------------------

local col = Color(0, 0, 0)
local function rgba(c, a)
    col.r, col.g, col.b, col.a = c.r, c.g, c.b, (c.a or 255) * a
    return col
end

local function drawBanner()
    local b = banner
    local life = b.up and UP_TIME or BANNER_TIME
    local age = RealTime() - b.at
    if age > life then banner = nil return end
    local a = math.Clamp(math.min(age * 4, (life - age) * 1.5), 0, 1)
    local open = math.Clamp(age / 0.3, 0, 1)
    open = 1 - (1 - open) * (1 - open)   -- ease out

    local W, H = ScrW(), ScrH()
    local titleFont = UI.Font(b.up and 30 or 44, 800)
    local subFont, smallFont = UI.Font(19, 500), UI.Font(12, 700)
    surface.SetFont(titleFont)
    local tw = surface.GetTextSize(string.upper(b.title))
    surface.SetFont(subFont)
    local sw = b.sub ~= "" and surface.GetTextSize(b.sub) or 0
    local w = math.min(math.max(tw, sw) + S(120), W - S(40))
    w = math.max(w, math.floor(W * 0.36))
    local h = b.up and S(78) or S(128)
    local cx, y = W * 0.5, math.floor(H * 0.2)
    local x = math.floor(cx - w * 0.5)

    -- Opens from the middle.
    local half = math.floor(w * 0.5 * open)
    render.SetScissorRect(math.floor(cx - half), y - S(4), math.ceil(cx + half), y + h + S(4), true)

    surface.SetDrawColor(rgba(BG, a))
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(rgba(GOLD, a))
    surface.DrawRect(x, y, w, math.max(2, S(3)))
    surface.DrawRect(x, y + h - math.max(1, S(1)), w, math.max(1, S(1)))
    surface.SetDrawColor(rgba(EDGE, a))
    surface.DrawOutlinedRect(x, y, w, h)
    surface.SetDrawColor(rgba(HI, a))
    surface.DrawLine(x + 1, y + S(4), x + w - 1, y + S(4))
    -- Chevrons on both ends.
    local ch = S(10)
    surface.SetDrawColor(rgba(GOLD, a * 0.8))
    for k = 0, 2 do
        local ox = S(18) + k * S(9)
        local my = y + h * 0.5
        surface.DrawLine(x + ox, my - ch, x + ox + ch, my)
        surface.DrawLine(x + ox + ch, my, x + ox, my + ch)
        surface.DrawLine(x + w - ox, my - ch, x + w - ox - ch, my)
        surface.DrawLine(x + w - ox - ch, my, x + w - ox, my + ch)
    end

    if b.up then
        draw.SimpleText(string.upper(b.title), titleFont, cx, y + h * 0.42, rgba(TEXT, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.upper(b.sub), smallFont, cx, y + h * 0.78, rgba(GOLD, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        draw.SimpleText("ALL PERSONNEL", smallFont, cx, y + S(20), rgba(GOLD, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.upper(b.title), titleFont, cx, y + S(54), rgba(TEXT, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if b.sub ~= "" then
            draw.SimpleText(b.sub, subFont, cx, y + S(90), rgba(DIM, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        local c = current()
        if c and c.left then
            draw.SimpleText(clock(c.left), smallFont, x + w - S(12), y + h - S(13), rgba(GOLD, a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        if b.by ~= "" then
            draw.SimpleText(string.upper(b.by), smallFont, x + S(12), y + h - S(13), rgba(DIM, a * 0.8), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    render.SetScissorRect(0, 0, 0, 0, false)
end

--------------------------------------------------------------------------
-- Timer
--------------------------------------------------------------------------

local function fit(text, font, maxW)
    surface.SetFont(font)
    if surface.GetTextSize(text) <= maxW then return text end
    while #text > 1 and surface.GetTextSize(text .. "…") > maxW do
        text = string.sub(text, 1, (utf8.offset(text, -1) or #text) - 1)
    end
    return text .. "…"
end

-- Same look as the HUD's visor tiles (rhylib_hud cl_42_layouts.lua).
local COL_PLATE = Color(28, 32, 31, 236)
local COL_EDGE = Color(0, 0, 0, 215)
local COL_HI2 = Color(200, 206, 210, 50)
local COL_LABEL = Color(165, 168, 160)
local COL_TRACK = Color(255, 255, 255, 30)

local function timeColor(c)
    if c.left > 60 then return TEXT end
    -- Last minute: amber, pulsing.
    local p = 0.6 + 0.4 * math.abs(math.sin(RealTime() * 3))
    col.r, col.g, col.b, col.a = WARN.r, WARN.g, WARN.b, 255 * p
    return col
end

local function lineColor(c)
    if c.left <= 60 then return WARN end
    return GOLD
end


-- A plate in the top-left corner.
local function drawCornerTimer(c)
    -- Top left (the killfeed is top right), under the visor's brow.
    local w, h = S(250), S(62)
    local HUD = Rhylib.HUD
    local visor = HUD and HUD.VisorActive and HUD.VisorActive()
    local x, y = S(24), visor and math.floor(ScrH() * 0.075) or S(24)
    draw.NoTexture()
    surface.SetDrawColor(COL_PLATE)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(COL_EDGE)
    surface.DrawOutlinedRect(x, y, w, h)
    -- Top line: the time left.
    local frac = (c.total and c.total > 0) and math.Clamp(c.left / c.total, 0, 1) or 1
    local lc = lineColor(c)
    surface.SetDrawColor(COL_HI2)
    surface.DrawLine(x + 1, y + 1, x + w - 1, y + 1)
    surface.SetDrawColor(lc)
    surface.DrawRect(x + 1, y + 1, math.floor((w - 2) * frac), 2)
    -- Corner ticks, like the other HUD plates.
    local t = S(7)
    surface.SetDrawColor(170, 176, 180, 150)
    surface.DrawRect(x, y + h - 2, t, 2)
    surface.DrawRect(x, y + h - t, 2, t)
    surface.DrawRect(x + w - t, y + h - 2, t, 2)
    surface.DrawRect(x + w - 2, y + h - t, 2, t)

    local pad = S(12)
    local titleFont, timeFont, subFont = UI.Font(12, 700), UI.Font(26, 500), UI.Font(11, 400)
    local tw = draw.SimpleText(clock(c.left), timeFont, x + w - pad, y + h * 0.56, timeColor(c), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    local room = w - pad * 2 - tw - S(10)
    draw.SimpleText(fit(string.upper(c.title), titleFont, room), titleFont, x + pad, y + S(22), lc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if c.sub ~= "" then
        draw.SimpleText(fit(c.sub, subFont, room), subFont, x + pad, y + S(42), COL_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

Rhylib.Hook.Add("HUDPaint", "admin.calls", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep:GetClass() == "gmod_camera" then return end
    local c = current()
    if not (c and c.left) then return end
    -- (the left cheek pocket is the radio's now: always the top-left plate)
    drawCornerTimer(c)
end)

-- The banner draws over menus too (a call matters even with the menu open).
Rhylib.Hook.Add("PostRenderVGUI", "admin.calls", function()
    if banner then drawBanner() end
end)

-- What this client sees (for checking calls arrive).
concommand.Add("rhylib_call_status", function()
    local c = current()
    print(string.format("[Rhylib] call #%d title=%q sub=%q end=%.1f now=%.1f seen=%d showing=%s banner=%s",
        GetGlobal2Int("rhylib_call_n", 0), GetGlobal2String("rhylib_call_title", ""), GetGlobal2String("rhylib_call_sub", ""),
        GetGlobal2Float("rhylib_call_end", 0), CurTime(), seen, tostring(c ~= nil), tostring(banner ~= nil)))
    print("[Rhylib] watch timer running: " .. tostring(timer.Exists("rhylib_admin_calls")))
end)
