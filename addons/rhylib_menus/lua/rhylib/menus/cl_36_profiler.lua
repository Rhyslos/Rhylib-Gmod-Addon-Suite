--[[
    Live profiler page (pause menu, Staff group, perm rhylib.profiler).
    Opening it subscribes to the server's once-a-second sample
    (rhylib_core sv_17_profiler.lua); closing it unsubscribes, so the
    profiler only runs while someone watches. Shows the server's tick
    rate and slowest tick, Rhylib hook time per tick (with a 60 s graph),
    memory and counts, then modules, the busiest hook handlers and the
    biggest net messages. Your own FPS is in the corner.

    Client only. Page "profiler" (Staff group, order 70). State in
    Menus.Prof: history (last 60 samples), last, panel.
    Net: sends core.profsub (bool: on/off); receives core.profdata (UInt 16
    length, then that many bytes of compressed JSON, once a second).
    Everything on the page is drawn in one Paint from P.last.
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

local P = Menus.Prof or {}
Menus.Prof = P
P.history = P.history or {}   -- last 60 samples
P.last = P.last or nil

net.Receive(Rhylib.Net.Name("core.profdata"), function()
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

-- A plain table: columns { title, width (0..1 share), align }, rows of strings.
local function drawTable(x, y, w, title, cols, rows, maxRows)
    local S = K.S
    draw.SimpleText(string.upper(title), K.Font(13, 700), x, y, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    y = y + S(20)
    surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 110)
    surface.DrawRect(x, y, w, 1)
    y = y + S(4)
    local cx = x
    for _, c in ipairs(cols) do
        local cw = w * c[2]
        local ax = c[3] == "r" and cx + cw - S(4) or cx
        draw.SimpleText(c[1], K.Font(11, 700), ax, y, C.label, c[3] == "r" and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        cx = cx + cw
    end
    y = y + S(16)
    for i = 1, math.min(#rows, maxRows) do
        local r = rows[i]
        if i % 2 == 0 then
            surface.SetDrawColor(C.rowAlt)
            surface.DrawRect(x, y, w, S(18))
        end
        cx = x
        for j, c in ipairs(cols) do
            local cw = w * c[2]
            local font = K.Font(12, j == 1 and 600 or 400)
            local text = K.Fit(tostring(r[j] or ""), font, cw - S(8))
            local ax = c[3] == "r" and cx + cw - S(4) or cx + S(2)
            draw.SimpleText(text, font, ax, y + S(9), C.text, c[3] == "r" and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            cx = cx + cw
        end
        y = y + S(18)
    end
    if #rows == 0 then
        draw.SimpleText("Nothing recorded yet", K.Font(12), x, y, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        y = y + S(18)
    end
    return y
end

-- Line graph of one field over the history.
local function graph(x, y, w, h, field, col, label, unit)
    local S = K.S
    surface.SetDrawColor(C.row)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(C.edgeDark)
    surface.DrawOutlinedRect(x, y, w, h)
    local hist = P.history
    local peak = 0.001
    for _, d in ipairs(hist) do peak = math.max(peak, tonumber(d[field]) or 0) end
    surface.SetDrawColor(col)
    local px, py
    for i, d in ipairs(hist) do
        local gx = x + (i - 1) / 59 * (w - 1)
        local gy = y + h - 2 - (tonumber(d[field]) or 0) / peak * (h - S(20))
        if px then surface.DrawLine(px, py, gx, gy) end
        px, py = gx, gy
    end
    draw.SimpleText(label .. " (peak " .. string.format("%.2f", peak) .. unit .. ")", K.Font(11, 700), x + S(6), y + S(4), C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end

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
    local fps, fpsAt = 0, 0
    function p:Paint(w, h)
        if RealTime() > fpsAt then
            fps = math.Round(1 / math.max(RealFrameTime(), 0.0001))
            fpsAt = RealTime() + 0.5
        end
        draw.SimpleText("Your FPS " .. fps, K.Font(12), w, 0, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        local d = P.last
        if not d then
            draw.SimpleText("Waiting for the server... (needs the rhylib.profiler permission)", K.Font(14), 0, S(4), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            return
        end
        -- Headline numbers.
        local tickOk = d.ticks >= d.tickRate * 0.95
        local stats = {
            { "Ticks / s", d.ticks .. " of " .. d.tickRate, tickOk and C.good or C.bad },
            { "Slowest tick", d.worst .. " ms", d.worst > 1000 / d.tickRate * 2 and C.warn or C.text },
            { "Rhylib / tick", string.format("%.3f ms", d.perTick), C.text },
            { "Net out", bytes(d.bytes), C.text },
            { "Lua memory", d.mem .. " MB", C.text },
            { "Players", d.humans .. " + " .. d.bots .. " bots" .. ((d.load or 0) > 0 and (" (" .. d.load .. " load)") or ""), C.text },
            { "Entities", tostring(d.ents), C.text },
            { "Droids / bolts", d.droids .. " / " .. d.bolts, C.text },
        }
        local cw = math.floor(w / 4)
        for i, st in ipairs(stats) do
            local cx = ((i - 1) % 4) * cw
            local cy = S(20) + math.floor((i - 1) / 4) * S(48)
            K.Plate(cx, cy, cw - S(8), S(42))
            draw.SimpleText(string.upper(st[1]), K.Font(11, 700), cx + S(10), cy + S(6), C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(st[2], K.Font(17, 700), cx + S(10), cy + S(20), st[3], TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        local y = S(20) + S(48) * 2 + S(6)
        local gw = math.floor(w / 2) - S(6)
        graph(0, y, gw, S(70), "perTick", C.accent, "Rhylib ms per tick", " ms")
        graph(gw + S(12), y, gw, S(70), "ticks", C.good, "Ticks per second", "")
        y = y + S(82)

        local mods = {}
        for _, m in ipairs(d.mods or {}) do
            mods[#mods + 1] = { m[1], string.format("%.2f", m[2]), tostring(m[3]), bytes(m[4]), tostring(m[5]) }
        end
        local hooks = {}
        for _, r in ipairs(d.hooks or {}) do hooks[#hooks + 1] = { r[1], string.format("%.3f", r[2]), tostring(r[3]) } end
        local nets = {}
        for _, r in ipairs(d.net or {}) do nets[#nets + 1] = { r[1], bytes(r[2]), tostring(r[3]) } end

        local half = math.floor(w / 2) - S(8)
        local rowsLeft = math.max(4, math.floor((h - y - S(60)) / S(18)))
        drawTable(0, y, half, "Modules (per second)", {
            { "Module", 0.34 }, { "ms", 0.14, "r" }, { "calls", 0.16, "r" }, { "net out", 0.22, "r" }, { "msgs", 0.14, "r" },
        }, mods, rowsLeft)
        local ry = drawTable(half + S(16), y, half, "Busiest hook handlers", {
            { "Event / handler", 0.62 }, { "ms/s", 0.19, "r" }, { "calls", 0.19, "r" },
        }, hooks, math.max(3, math.floor(rowsLeft / 2) - 2))
        drawTable(half + S(16), ry + S(10), half, "Biggest net messages", {
            { "Message", 0.56 }, { "out", 0.26, "r" }, { "sends", 0.18, "r" },
        }, nets, math.max(3, math.floor(rowsLeft / 2) - 2))
    end
end

Menus.AddPage("profiler", {
    title = "Profiler",
    order = 70,
    group = "staff",
    visible = function()
        local me = LocalPlayer()
        if not IsValid(me) then return false end
        local A = Rhylib.Admin
        if A and A.Has then return A.Has(me, "rhylib.profiler", "superadmin") end
        return me:IsSuperAdmin()
    end,
    build = build,
})
