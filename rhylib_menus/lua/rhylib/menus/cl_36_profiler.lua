--[[
    Live profiler page (pause menu, Staff group, perm rhylib.profiler).
    Opening it subscribes to the server's once-a-second sample
    (rhylib_core sv_17_profiler.lua); closing it unsubscribes, so the
    profiler only runs while someone watches.

    Look: a strip with a LIVE / WAITING chip and your FPS on the right;
    eight stat tiles (caps label, big value, a coloured edge for state:
    green ticks on time, red behind, amber slow tick); two graphs over the
    last 60 s (Rhy's ms per tick, ticks per second) with the peak on their
    header; then tables (a diamond heading, caps column titles, rows
    alternating, numbers right-aligned): modules, the busiest hook
    handlers and the biggest net messages. Waiting for the first sample:
    a dashed box.

    Client only. Page "profiler" (Staff group, order 260). State in
    Menus.Prof: history (last 60 samples), last, panel.
    Net: sends core.profsub (bool: on/off); receives core.profdata (UInt 16
    length, then that many bytes of compressed JSON, once a second).
    Everything on the page is drawn in one Paint from P.last; the texts
    are made once per sample, not every frame.
]]
local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

local P = Menus.Prof or {}
Menus.Prof = P
P.history = P.history or {}   -- last 60 samples
P.last = P.last or nil

Rhylib.Net.Receive("core.profdata", function()
    local n = net.ReadUInt(16)
    local raw = net.ReadData(n)
    local data = util.JSONToTable(util.Decompress(raw or "") or "") or nil
    if not data then return end
    P.last = data
    table.insert(P.history, data)
    while #P.history > 60 do table.remove(P.history, 1) end
end)

local function subscribe(on)
    Rhylib.Net.Start("core.profsub")
    net.WriteBool(on)
    net.SendToServer()
end

local function bytes(b)
    if b >= 1048576 then return string.format("%.2f MB/s", b / 1048576) end
    if b >= 1024 then return string.format("%.1f KB/s", b / 1024) end
    return string.format("%d B/s", b)
end

-- (one vertex table, filled per draw)
local DIA = { {}, {}, {}, {} }
local function diamond(cx, cy, r, col)
    DIA[1].x, DIA[1].y = cx, cy - r
    DIA[2].x, DIA[2].y = cx + r, cy
    DIA[3].x, DIA[3].y = cx, cy + r
    DIA[4].x, DIA[4].y = cx - r, cy
    draw.NoTexture()
    K.SetCol(col)
    surface.DrawPoly(DIA)
end

-- A dashed outline (an empty / waiting box).
local function dashed(x, y, w, h, col, a)
    local d, g = K.S(6), K.S(4)
    K.SetCol(col, a)
    for i = x, x + w - 1, d + g do
        local l = math.min(d, x + w - i)
        surface.DrawRect(i, y, l, 1)
        surface.DrawRect(i, y + h - 1, l, 1)
    end
    for j = y, y + h - 1, d + g do
        local l = math.min(d, y + h - j)
        surface.DrawRect(x, j, 1, l)
        surface.DrawRect(x + w - 1, j, 1, l)
    end
end

-- A chip: small caps text on a pill tinted in col. y is the centre.
-- align "r": x is the right edge. Returns its width.
local function chip(text, x, y, col, align)
    local S = K.S
    local f = K.Font(11, 700)
    surface.SetFont(f)
    local w, h = surface.GetTextSize(text) + S(14), S(18)
    if align == "r" then x = x - w end
    K.SetCol(col, 40)
    surface.DrawRect(x, y - h * 0.5, w, h)
    K.SetCol(col, 150)
    surface.DrawOutlinedRect(x, y - h * 0.5, w, h)
    draw.SimpleText(text, f, x + w * 0.5, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return w
end

-- A table: a diamond heading, caps column titles { TITLE, share, "r" },
-- rows of strings (numbers right-aligned). Returns the y under it.
local function drawTable(x, y, w, title, cols, rows, maxRows)
    local S = K.S
    local rh = S(20)
    diamond(x + S(5), y + S(9), S(5), C.accent)
    draw.SimpleText(title, K.Font(13, 700), x + S(16), y + S(9), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    y = y + S(20)
    K.SetCol(C.accent, 110)
    surface.DrawRect(x, y, w, 1)
    y = y + S(4)
    local top = y
    K.SetCol(C.header)
    surface.DrawRect(x, y, w, rh)
    local cx = x
    for _, c in ipairs(cols) do
        local cw = w * c[2]
        local right = c[3] == "r"
        draw.SimpleText(c[1], K.Font(11, 700), right and (cx + cw - S(8)) or (cx + S(8)), y + rh * 0.5, C.label,
            right and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        cx = cx + cw
    end
    y = y + rh
    local n = math.min(#rows, maxRows)
    for i = 1, n do
        local r = rows[i]
        K.SetCol(i % 2 == 0 and C.rowAlt or C.row)
        surface.DrawRect(x, y, w, rh)
        cx = x
        for j, c in ipairs(cols) do
            local cw = w * c[2]
            local right = c[3] == "r"
            local font = K.Font(12, j == 1 and 600 or 400)
            local text = K.Fit(r[j] or "", font, cw - S(14))
            draw.SimpleText(text, font, right and (cx + cw - S(8)) or (cx + S(8)), y + rh * 0.5, j == 1 and C.text or C.textDim,
                right and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            cx = cx + cw
        end
        y = y + rh
    end
    if n == 0 then
        K.SetCol(C.row)
        surface.DrawRect(x, y, w, rh)
        draw.SimpleText("Nothing recorded yet", K.Font(12), x + S(8), y + rh * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        y = y + rh
    end
    K.SetCol(C.edgeDark)
    surface.DrawOutlinedRect(x, top, w, y - top)
    return y
end

-- A graph of one field over the history, on a small plate: caps label
-- and the peak on its header, faint quarter lines, the line in col.
local function graph(x, y, w, h, field, col, label, unit, peakFmt)
    local S = K.S
    local hh = S(22)
    K.SetCol(C.row)
    surface.DrawRect(x, y, w, h)
    K.SetCol(C.header)
    surface.DrawRect(x, y, w, hh)
    K.SetCol(col)
    surface.DrawRect(x, y + hh - 1, w, 1)
    local hist = P.history
    local peak = 0.001
    for _, d in ipairs(hist) do peak = math.max(peak, tonumber(d[field]) or 0) end
    K.Caps(label, x + S(10), y + hh * 0.5)
    draw.SimpleText("peak " .. string.format(peakFmt, peak) .. unit, K.Font(11, 700), x + w - S(10), y + hh * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    local gy0, gh = y + hh + S(4), h - hh - S(8)
    K.SetCol(C.edgeLight, 60)
    for q = 1, 3 do surface.DrawRect(x + 1, gy0 + math.floor(gh * q / 4), w - 2, 1) end
    K.SetCol(col)
    local px, py
    for i, d in ipairs(hist) do
        local gx = x + S(2) + (i - 1) / 59 * (w - S(4))
        local gy = gy0 + gh - (tonumber(d[field]) or 0) / peak * gh
        if px then surface.DrawLine(px, py, gx, gy) end
        px, py = gx, gy
    end
    if px then surface.DrawRect(px - S(2), py - S(2), S(4), S(4)) end
    K.SetCol(C.edgeDark)
    surface.DrawOutlinedRect(x, y, w, h)
    K.SetCol(C.edgeLight)
    surface.DrawLine(x + 1, y + 1, x + w - 1, y + 1)
end

-- The texts of one sample, made once when it arrives.
local cache = {}
local function prepare(d)
    if cache.d == d then return cache end
    local tickOk = d.ticks >= d.tickRate * 0.95
    local slow = d.worst > 1000 / d.tickRate * 2
    local c = { d = d }
    -- { LABEL, value, value colour, edge colour (nil = plain) }
    c.stats = {
        { "TICKS / S", d.ticks .. " of " .. d.tickRate, tickOk and C.good or C.bad, tickOk and C.good or C.bad },
        { "SLOWEST TICK", d.worst .. " ms", slow and C.warn or C.text, slow and C.warn or nil },
        { "RHY'S / TICK", string.format("%.3f ms", d.perTick), C.text },
        { "NET OUT", bytes(d.bytes), C.text },
        { "LUA MEMORY", d.mem .. " MB", C.text },
        { "PLAYERS", d.humans .. " + " .. d.bots .. " bots" .. ((d.load or 0) > 0 and (" (" .. d.load .. " load)") or ""), C.text },
        { "ENTITIES", tostring(d.ents), C.text },
        { "DROIDS / BOLTS", d.droids .. " / " .. d.bolts, C.text },
    }
    c.mods = {}
    for _, m in ipairs(d.mods or {}) do
        c.mods[#c.mods + 1] = { tostring(m[1]), string.format("%.2f", m[2]), tostring(m[3]), bytes(m[4]), tostring(m[5]) }
    end
    c.hooks = {}
    for _, r in ipairs(d.hooks or {}) do c.hooks[#c.hooks + 1] = { tostring(r[1]), string.format("%.3f", r[2]), tostring(r[3]) } end
    c.nets = {}
    for _, r in ipairs(d.net or {}) do c.nets[#c.nets + 1] = { tostring(r[1]), bytes(r[2]), tostring(r[3]) } end
    cache = c
    return c
end

local COLS_MODS = { { "MODULE", 0.34 }, { "MS", 0.14, "r" }, { "CALLS", 0.16, "r" }, { "NET OUT", 0.22, "r" }, { "MSGS", 0.14, "r" } }
local COLS_HOOKS = { { "EVENT / HANDLER", 0.62 }, { "MS/S", 0.19, "r" }, { "CALLS", 0.19, "r" } }
local COLS_NETS = { { "MESSAGE", 0.56 }, { "OUT", 0.26, "r" }, { "SENDS", 0.18, "r" } }

local function build(page)
    local S = K.S
    P.last, P.history = nil, {}
    subscribe(true)
    local p = vgui.Create("DPanel", page)
    p:Dock(FILL)
    P.panel = p
    -- (closing the page or the menu unsubscribes; not when a rebuilt page took over)
    function p:OnRemove()
        if P.panel == self then
            P.panel = nil
            subscribe(false)
        end
    end
    local fps, fpsAt, fpsText = 0, 0, "0"
    function p:Paint(w, h)
        if RealTime() > fpsAt then
            fps = math.Round(1 / math.max(RealFrameTime(), 0.0001))
            fpsText = tostring(fps)
            fpsAt = RealTime() + 0.5
        end
        local d = P.last
        -- The strip: LIVE / WAITING, your FPS on the right.
        local sy = S(11)
        chip(d and "LIVE · EVERY SECOND" or "WAITING", 0, sy, d and C.good or C.warn)
        draw.SimpleText(fpsText, K.Font(15, 700), w, sy, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        surface.SetFont(K.Font(15, 700))
        K.Caps("Your FPS", w - surface.GetTextSize(fpsText) - S(8), sy, C.label, TEXT_ALIGN_RIGHT)
        if not d then
            local by = S(32)
            K.SetCol(C.row, 120)
            surface.DrawRect(0, by, w, S(80))
            dashed(0, by, w, S(80), C.edgeLight, 200)
            draw.SimpleText("Waiting for the server... (needs the rhylib.profiler permission)", K.Font(14), w * 0.5, by + S(40), C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end
        local c = prepare(d)
        -- Stat tiles, four a row.
        local gap = S(8)
        local tw = math.floor((w - gap * 3) / 4)
        local th = S(54)
        local y0 = S(30)
        for i, st in ipairs(c.stats) do
            local tx = ((i - 1) % 4) * (tw + gap)
            local ty = y0 + math.floor((i - 1) / 4) * (th + gap)
            K.SetCol(C.row)
            surface.DrawRect(tx, ty, tw, th)
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(tx, ty, tw, th)
            K.SetCol(C.edgeLight)
            surface.DrawLine(tx + 1, ty + 1, tx + tw - 1, ty + 1)
            if st[4] then
                K.SetCol(st[4])
                surface.DrawRect(tx + 1, ty + 1, S(3), th - 2)
            end
            K.Caps(st[1], tx + S(12), ty + S(15))
            draw.SimpleText(K.Fit(st[2], K.Font(18, 700), tw - S(20)), K.Font(18, 700), tx + S(12), ty + S(36), st[3], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local y = y0 + (th + gap) * 2 + S(4)
        local gw = math.floor((w - S(12)) / 2)
        local gh = S(86)
        graph(0, y, gw, gh, "perTick", C.accent, "Rhy's ms per tick", " ms", "%.2f")
        graph(gw + S(12), y, w - gw - S(12), gh, "ticks", C.good, "Ticks per second", "", "%.0f")
        y = y + gh + S(14)

        local half = math.floor((w - S(16)) / 2)
        local rowsLeft = math.max(4, math.floor((h - y - S(64)) / S(20)))
        drawTable(0, y, half, "MODULES (PER SECOND)", COLS_MODS, c.mods, rowsLeft)
        local ry = drawTable(half + S(16), y, w - half - S(16), "BUSIEST HOOK HANDLERS", COLS_HOOKS, c.hooks, math.max(3, math.floor(rowsLeft / 2) - 2))
        drawTable(half + S(16), ry + S(12), w - half - S(16), "BIGGEST NET MESSAGES", COLS_NETS, c.nets, math.max(3, math.floor(rowsLeft / 2) - 2))
    end
end

Menus.AddPage("profiler", {
    title = "Profiler",
    order = 260,
    section = "staff",
    icon = "profiler",
    visible = function()
        local me = LocalPlayer()
        if not IsValid(me) then return false end
        local A = Rhylib.Admin
        if A and A.Has then return A.Has(me, "rhylib.profiler", "superadmin") end
        return me:IsSuperAdmin()
    end,
    build = build,
})
