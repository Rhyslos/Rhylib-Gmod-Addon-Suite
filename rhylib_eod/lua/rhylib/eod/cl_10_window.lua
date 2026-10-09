--[[
    Defusal window (client). Fully opaque (owner). The server sends the
    bomb's view (eod.state: colours, ends and flags, never the wire kinds);
    the probe's readings come back one by one (eod.read).

    Left: timer, first inspection (hold), the casing, the modules and the
    gas valve. Right: tools (probe, wirecutters, jumper wire), the last
    reading, the board (hover a wire to trace it), and a log.
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local OPAQUE = Color(14, 16, 15, 255)
local BOARD_BG = Color(14, 27, 20, 255)
local PART_BG = Color(22, 38, 29, 255)
local PART_EDGE = Color(96, 128, 108, 255)
local TERM_EDGE = Color(135, 165, 146, 255)
local JUMPER = Color(255, 209, 102)
local BW, BH = 760, 420

E.win = E.win or nil   -- { frame, bomb, v, recv, reads, log, tool, pick, xray, ... }

local function W() local w = E.win return (w and IsValid(w.frame)) and w or nil end

local function act(op, write)
    local w = W()
    if not w or not IsValid(w.bomb) then return end
    Net.Start("eod.act")
    net.WriteEntity(w.bomb)
    net.WriteUInt(op, 4)
    if write then write() end
    net.SendToServer()
end

local function colOf(i) return (E.COLOURS[i] or E.COLOURS[1])[2] end
local function nameOf(i) return (E.COLOURS[i] or E.COLOURS[1])[1] end

local function addLog(text, bad)
    local w = W()
    if not w then
        chat.AddText(Color(255, 170, 60), "[EOD] ", bad and Color(255, 120, 110) or color_white, text)
        return
    end
    table.insert(w.log, 1, { text, bad, CurTime() })
    while #w.log > 8 do table.remove(w.log) end
end

--------------------------------------------------------------------------
-- Board geometry (from the view: parts and wires)
--------------------------------------------------------------------------

local function partBy(v, id)
    for i, p in ipairs(v.parts) do if p.id == id then return p, i end end
end

local function port(p, q, off)
    local pcx, pcy = p.x + p.w / 2, p.y + p.h / 2
    local qcx, qcy = q.x + q.w / 2, q.y + q.h / 2
    if math.abs(qcx - pcx) > 60 then
        local right = qcx > pcx
        return right and p.x + p.w or p.x, pcy + off, right and 1 or -1, 0
    end
    local down = qcy > pcy
    return pcx + off, down and p.y + p.h or p.y, 0, down and 1 or -1
end

local function bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2, n)
    local pts = {}
    for i = 0, n do
        local t = i / n
        local u = 1 - t
        pts[#pts + 1] = {
            u * u * u * x1 + 3 * u * u * t * cx1 + 3 * u * t * t * cx2 + t * t * t * x2,
            u * u * u * y1 + 3 * u * u * t * cy1 + 3 * u * t * t * cy2 + t * t * t * y2,
        }
    end
    return pts
end

local function buildGeo(v)
    local geo = { wires = {} }
    local used = {}
    for i, w in ipairs(v.wires) do
        local a, b = partBy(v, w.a), partBy(v, w.b)
        if a and b then
            local ka = w.a .. (b.x > a.x and "r" or "l")
            local kb = w.b .. (a.x > b.x and "r" or "l")
            used[ka] = (used[ka] or 0) + 1
            used[kb] = (used[kb] or 0) + 1
            local offA = (used[ka] - 1) * 14 - (used[ka] > 1 and 7 or 0)
            local offB = (used[kb] - 1) * 14 - (used[kb] > 1 and 7 or 0)
            local x1, y1, dx1, dy1 = port(a, b, offA)
            local x2, y2, dx2, dy2 = port(b, a, offB)
            local k = math.max(60, math.abs(x2 - x1) * 0.45 + math.abs(y2 - y1) * 0.2)
            local pts = bezier(x1, y1, x1 + dx1 * k, y1 + dy1 * k, x2 + dx2 * k, y2 + dy2 * k, x2, y2, 28)
            geo.wires[i] = { pts = pts, mid = pts[15] }
            if w.sealed then geo.sealed = pts[15] end
        end
    end
    -- fake board mounts
    geo.mounts = {}
    for m = 1, 3 do
        local x, y = BW * 0.25 * m, BH - 60
        geo.mounts[m] = { pts = bezier(x, y - 34, x + 40, y - 20, x - 40, y + 10, x, y + 26, 16), x = x, y = y }
    end
    return geo
end

local function termPos(p, plus)
    return p.x + p.w - (plus and 36 or 14), p.y + p.h - 14
end

--------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------

local quad = { {}, {}, {}, {} }
local function thick(pts, width, col, sc, ox, oy, skipFrom, skipTo)
    surface.SetDrawColor(col)
    draw.NoTexture()
    local hw = width / 2
    for i = 1, #pts - 1 do
        if not (skipFrom and i >= skipFrom and i <= skipTo) then
            local ax, ay = pts[i][1] * sc + ox, pts[i][2] * sc + oy
            local bx, by = pts[i + 1][1] * sc + ox, pts[i + 1][2] * sc + oy
            local dx, dy = bx - ax, by - ay
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0.01 then
                -- (clockwise on screen: surface.DrawPoly skips the other winding)
                local nx, ny = dy / len * hw, -dx / len * hw
                -- (extend a little so the joins close)
                local ex, ey = dx / len * hw * 0.5, dy / len * hw * 0.5
                quad[1].x, quad[1].y = ax + nx - ex, ay + ny - ey
                quad[2].x, quad[2].y = bx + nx + ex, by + ny + ey
                quad[3].x, quad[3].y = bx - nx + ex, by - ny + ey
                quad[4].x, quad[4].y = ax - nx - ex, ay - ny - ey
                surface.DrawPoly(quad)
            end
        end
    end
end

local function circle(x, y, r, col)
    draw.RoundedBox(math.floor(r), x - r, y - r, r * 2, r * 2, col)
end

local function distSeg(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and math.Clamp(((px - ax) * dx + (py - ay) * dy) / l2, 0, 1) or 0
    local cx, cy = ax + dx * t, ay + dy * t
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

local function nearPts(pts, x, y)
    local best = math.huge
    for i = 1, #pts - 1 do
        local d = distSeg(x, y, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2])
        if d < best then best = d end
    end
    return best
end

--------------------------------------------------------------------------
-- Live values (between state messages)
--------------------------------------------------------------------------

local function heatNow(w)
    local v = w.v
    local h = (v.heat or 0)
    local dt = CurTime() - (v.now or CurTime())
    if v.torching then
        h = h + dt * ((E.Cfg("heatTorch") or 26) - (E.Cfg("heatCool") or 9))
    else
        h = h - dt * (E.Cfg("heatCool") or 9)
    end
    return math.Clamp(h, 0, 100)
end

local function sealedNow(w)
    local v = w.v
    local p = v.sealedP or 0
    if v.torching then p = p + (CurTime() - (v.now or CurTime())) / math.max(0.5, E.Cfg("torchTime") or 5) end
    return math.Clamp(p, 0, 1)
end

local function timerText(v)
    local t = v.timer
    if not t then return nil end
    if v.safe or v.done then return "SAFE", Color(80, 220, 120) end
    if t.ends and t.ends > 0 then
        local left = math.max(0, t.ends - CurTime())
        return string.FormattedTime(left, "%02i:%02i"), left < 15 and Color(255, 90, 80) or Color(235, 70, 60)
    end
    if t.stopped then return string.FormattedTime(t.left or 0, "%02i:%02i") .. "  STOPPED", Color(140, 140, 140) end
    return string.FormattedTime(t.left or t.secs or 0, "%02i:%02i") .. "  WAITING", Color(200, 120, 60)
end

--------------------------------------------------------------------------
-- The board panel
--------------------------------------------------------------------------

local function boardPanel(parent, k)
    local s = k.S
    local C = k.C
    local p = vgui.Create("DPanel", parent)
    p:SetCursor("hand")

    function p:Frame(w, h)
        local sc = math.min(w / BW, h / BH)
        return sc, (w - BW * sc) / 2, (h - BH * sc) / 2
    end

    -- What the mouse is over: { kind = "wire"|"term"|"mount", ... }
    function p:Hover()
        local win = W()
        if not win or not win.geo then return nil end
        local v = win.v
        if not v.open then return nil end
        local mx, my = self:CursorPos()
        local sc, ox, oy = self:Frame(self:GetWide(), self:GetTall())
        local bx, by = (mx - ox) / sc, (my - oy) / sc
        if v.fake and not v.fake.removed then
            for m, g in ipairs(win.geo.mounts) do
                if not v.fake.cut[m] and nearPts(g.pts, bx, by) < 9 then return { kind = "mount", m = m } end
            end
            return nil
        end
        if win.tool == "jump" then
            for i, part in ipairs(v.parts) do
                if part.term then
                    for _, plus in ipairs({ true, false }) do
                        local tx, ty = termPos(part, plus)
                        if (bx - tx) ^ 2 + (by - ty) ^ 2 <= 12 * 12 then return { kind = "term", part = i, plus = plus } end
                    end
                end
            end
            return nil
        end
        local best, bestD = nil, 8
        for i, g in pairs(win.geo.wires) do
            local wd = v.wires[i]
            if wd and not (wd.sealed and not v.sealedOpen) then
                local d = nearPts(g.pts, bx, by)
                if d < bestD then best, bestD = i, d end
            end
        end
        return best and { kind = "wire", i = best } or nil
    end

    function p:OnMousePressed(code)
        if code ~= MOUSE_LEFT then return end
        local win = W()
        if not win or win.overlay then return end
        local v = win.v
        if not v.kit then addLog("You need an EOD kit", true) return end
        local h = self:Hover()
        if not h then return end
        if h.kind == "mount" then
            if win.tool ~= "cut" then addLog("Use the wirecutters on the mount wires") return end
            act(12, function() net.WriteUInt(h.m, 2) end)
        elseif h.kind == "wire" then
            if win.tool == "probe" then
                act(4, function() net.WriteUInt(h.i, 5) end)
            elseif win.tool == "cut" then
                act(5, function() net.WriteUInt(h.i, 5) end)
                surface.PlaySound("physics/metal/metal_solid_impact_soft" .. math.random(1, 3) .. ".wav")
            end
        elseif h.kind == "term" then
            if not win.pick then
                win.pick = { part = h.part, plus = h.plus }
            elseif win.pick.part == h.part and win.pick.plus == h.plus then
                win.pick = nil
            else
                local a = win.pick
                win.pick = nil
                if (v.jumpers or 0) <= 0 then addLog("No jumper wires left", true) return end
                act(6, function()
                    net.WriteUInt(a.part, 4)
                    net.WriteBool(a.plus)
                    net.WriteUInt(h.part, 4)
                    net.WriteBool(h.plus)
                end)
            end
        end
    end

    function p:Paint(w, h)
        local win = W()
        if not win then return end
        local v = win.v
        local sc, ox, oy = self:Frame(w, h)
        k.SetCol(BOARD_BG)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local now = CurTime()

        if not v.open then
            -- casing still on
            k.SetCol(Color(40, 46, 52))
            surface.DrawRect(ox + 10 * sc, oy + 10 * sc, (BW - 20) * sc, (BH - 20) * sc)
            k.SetCol(Color(90, 100, 110))
            surface.DrawOutlinedRect(ox + 10 * sc, oy + 10 * sc, (BW - 20) * sc, (BH - 20) * sc, 2)
            draw.SimpleText("CASING CLOSED", k.Font(22, 800), w / 2, h / 2 - s(14), Color(200, 206, 210), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(v.lid and "Lid-switch tab released" or "Inspect first. Release the lid-switch tab (if it has one), then lift the lid.",
                k.Font(13), w / 2, h / 2 + s(14), Color(150, 160, 168), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end

        local hov = (not win.overlay) and self:Hover() or nil
        local geo = win.geo

        -- wires
        for i, g in pairs(geo.wires) do
            local wd = v.wires[i]
            if wd then
                local col = colOf(wd.c)
                local hot = hov and hov.kind == "wire" and hov.i == i
                if wd.arm then thick(g.pts, 10 * sc, Color(60, 64, 70), sc, ox, oy) end
                if wd.cut then
                    thick(g.pts, 6 * sc, Color(col.r * 0.45, col.g * 0.45, col.b * 0.45), sc, ox, oy, 12, 16)
                else
                    if hot then thick(g.pts, 11 * sc, Color(255, 255, 255, 120), sc, ox, oy) end
                    thick(g.pts, (hot and 8 or 6) * sc, col, sc, ox, oy)
                end
                if wd.arm then
                    -- armour bands
                    for j = 3, #g.pts - 2, 4 do
                        local pt = g.pts[j]
                        circle(pt[1] * sc + ox, pt[2] * sc + oy, 4 * sc, Color(120, 126, 132))
                    end
                end
                local r = win.reads[i]
                if r and not wd.cut then
                    draw.SimpleTextOutlined(r, k.Font(11, 700), g.mid[1] * sc + ox, g.mid[2] * sc + oy - 12 * sc, Color(220, 235, 225), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 220))
                end
            end
        end

        -- parts
        for _, part in ipairs(v.parts) do
            local x, y, pw, ph = ox + part.x * sc, oy + part.y * sc, part.w * sc, part.h * sc
            draw.RoundedBox(4, x, y, pw, ph, PART_EDGE)
            draw.RoundedBox(4, x + 1, y + 1, pw - 2, ph - 2, PART_BG)
            draw.SimpleText(part.label, k.Font(14, 700), x + 10 * sc, y + 8 * sc, Color(220, 232, 224))
            if part.sub and part.sub ~= "" then
                draw.SimpleText(part.sub, k.Font(12), x + 10 * sc, y + 26 * sc, Color(140, 165, 150))
            end
            if part.id == "chip" and v.chip then
                -- blink pattern: S 0.25 s, L 0.75 s, gaps 0.35 s, then a pause
                local lit = false
                if v.chip.ok then
                    lit = now % 2 < 1
                elseif v.chip.code then
                    local seq, t = {}, 0
                    for c in string.gmatch(v.chip.code, ".") do seq[#seq + 1] = c == "L" and 0.75 or 0.25 end
                    local cyc = 0
                    for _, d in ipairs(seq) do cyc = cyc + d + 0.35 end
                    cyc = cyc + 1.4
                    local tt = now % cyc
                    for _, d in ipairs(seq) do
                        if tt >= t and tt < t + d then lit = true break end
                        t = t + d + 0.35
                    end
                end
                local col = v.chip.ok and Color(70, 220, 110) or (lit and Color(255, 60, 50) or Color(70, 20, 20))
                circle(x + pw - 20 * sc, y + 20 * sc, 8 * sc, col)
            end
            if part.id == "chg" then
                local yy = y + 46 * sc
                if v.stab and v.stab.dose then
                    draw.SimpleText("STABILISER", k.Font(11, 700), x + 10 * sc, yy, Color(255, 209, 102))
                    draw.SimpleText(string.format("%.2f ml", v.stab.dose), k.Font(16, 800), x + 10 * sc, yy + 14 * sc, Color(255, 209, 102))
                    yy = yy + 40 * sc
                end
                if v.liquid then
                    draw.SimpleText(v.liquid.drained and "LIQUID · drained" or "LIQUID CHARGE", k.Font(11, 700), x + 10 * sc, yy, Color(110, 190, 255))
                end
            end
        end

        -- sealed plate over the detonator line
        if geo.sealed and not v.sealedOpen then
            local cx, cy = geo.sealed[1] * sc + ox, geo.sealed[2] * sc + oy
            draw.RoundedBox(4, cx - 70 * sc, cy - 36 * sc, 140 * sc, 72 * sc, Color(138, 147, 156))
            draw.RoundedBox(4, cx - 69 * sc, cy - 35 * sc, 138 * sc, 70 * sc, Color(58, 64, 72))
            draw.SimpleText("Sealed plate", k.Font(13, 700), cx, cy - 10 * sc, Color(220, 226, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("cut " .. math.floor(sealedNow(win) * 100) .. "%", k.Font(12), cx, cy + 12 * sc, Color(170, 178, 186), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if v.torching and now % 0.2 < 0.1 then circle(cx, cy - 34 * sc, 6 * sc, Color(255, 200, 90)) end
        end

        -- jumpers
        for _, j in ipairs(v.jumps or {}) do
            local pa, pb = v.parts[j.a], v.parts[j.b]
            if pa and pb then
                local x1, y1 = termPos(pa, j.pa)
                local x2, y2 = termPos(pb, j.pb)
                local lift = j.a == j.b and 26 or 40
                thick(bezier(x1, y1, x1, y1 - lift, x2, y2 - lift, x2, y2, 16), 3 * sc, JUMPER, sc, ox, oy)
            end
        end
        -- terminals
        local jumping = win.tool == "jump"
        for i, part in ipairs(v.parts) do
            if part.term then
                for _, plus in ipairs({ true, false }) do
                    local tx, ty = termPos(part, plus)
                    tx, ty = tx * sc + ox, ty * sc + oy
                    local picked = win.pick and win.pick.part == i and win.pick.plus == plus
                    local hot = hov and hov.kind == "term" and hov.part == i and hov.plus == plus
                    circle(tx, ty, 9 * sc, (jumping or hot) and JUMPER or TERM_EDGE)
                    circle(tx, ty, 7.5 * sc, picked and JUMPER or Color(15, 26, 20))
                    draw.SimpleText(plus and "+" or "−", k.Font(12, 800), tx, ty, picked and Color(17, 17, 17) or Color(207, 227, 212), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end
        if win.pick then
            local pa = v.parts[win.pick.part]
            if pa then
                local x1, y1 = termPos(pa, win.pick.plus)
                local mx, my = self:CursorPos()
                surface.SetDrawColor(JUMPER)
                surface.DrawLine(x1 * sc + ox, y1 * sc + oy, mx, my)
            end
        end

        -- fake board cover
        if v.fake and not v.fake.removed then
            local xray = win.xray and now < win.xray.untilT
            draw.RoundedBox(6, ox + 8 * sc, oy + 8 * sc, (BW - 16) * sc, (BH - 16) * sc, xray and Color(43, 49, 56, 115) or Color(43, 49, 56, 255))
            draw.SimpleText("Board cover", k.Font(16, 700), ox + 28 * sc, oy + 30 * sc, Color(207, 214, 220))
            draw.SimpleText(xray and "X-RAY: mount order shown" or ("Three mounts hold it down · X-rays left: " .. (v.fake.xrays or 0)), k.Font(12), ox + 28 * sc, oy + 52 * sc, Color(143, 154, 164))
            for m, g in ipairs(geo.mounts) do
                circle(g.x * sc + ox, (g.y - 34) * sc + oy, 7 * sc, Color(89, 99, 109))
                circle(g.x * sc + ox, (g.y + 26) * sc + oy, 7 * sc, Color(89, 99, 109))
                local col = colOf(v.fake.cols[m])
                local hot = hov and hov.kind == "mount" and hov.m == m
                if v.fake.cut[m] then
                    thick(g.pts, 6 * sc, Color(col.r * 0.45, col.g * 0.45, col.b * 0.45), sc, ox, oy, 7, 9)
                else
                    if hot then thick(g.pts, 11 * sc, Color(255, 255, 255, 120), sc, ox, oy) end
                    thick(g.pts, 6 * sc, col, sc, ox, oy)
                end
                if xray then
                    local n
                    for kk = 1, 3 do if win.xray.order[kk] == m then n = kk end end
                    draw.SimpleText(tostring(n or "?"), k.Font(24, 800), (g.x + 22) * sc + ox, g.y * sc + oy, JUMPER, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end
        end

        -- hovered wire's name
        if hov and hov.kind == "wire" and v.wires[hov.i] then
            local mx, my = self:CursorPos()
            local wd = v.wires[hov.i]
            local txt = nameOf(wd.c) .. " wire" .. (wd.cut and " (cut)" or "") .. (wd.arm and " · armoured" or "")
            draw.SimpleTextOutlined(txt, k.Font(13, 700), mx + s(14), my + s(6), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 230))
        end
    end
    return p
end

--------------------------------------------------------------------------
-- Left column: inspection, casing, modules
--------------------------------------------------------------------------

-- A button you hold: onStart, onDone (after secs), onStop (released early).
local function holdButton(parent, k, text, secs, onStart, onDone, onStop)
    local s = k.S
    local b = k.Button(parent, text, nil, { accent = true })
    b.holdAt = nil
    function b:OnMousePressed(code)
        if code ~= MOUSE_LEFT then return end
        self.holdAt = CurTime()
        self:MouseCapture(true)
        if onStart then onStart() end
    end
    function b:OnMouseReleased(code)
        if code ~= MOUSE_LEFT then return end
        self:MouseCapture(false)
        if self.holdAt then
            self.holdAt = nil
            if onStop then onStop() end
        end
    end
    function b:Think()
        if self.holdAt and secs and CurTime() - self.holdAt >= secs then
            self.holdAt = nil
            self:MouseCapture(false)
            if onDone then onDone() end
        end
    end
    local paint = b.Paint
    function b:Paint(w, h)
        paint(self, w, h)
        if self.holdAt and secs then
            k.SetCol(k.C.good, 120)
            surface.DrawRect(1, h - s(4), (w - 2) * math.Clamp((CurTime() - self.holdAt) / secs, 0, 1), s(3))
        end
        return true
    end
    return b
end

local function section(sp, k, title)
    local h = k.Heading(sp, title)
    h:Dock(TOP)
    h:DockMargin(0, k.S(8), k.S(6), k.S(4))
end

local function text(sp, k, str, col)
    local l = k.Label(sp, str, 13, 400, col or k.C.textDim)
    l:Dock(TOP)
    l:DockMargin(0, 0, k.S(8), k.S(4))
    return l
end

local function btn(sp, k, label, fn, opts)
    local b = k.Button(sp, label, fn, opts)
    b:Dock(TOP)
    b:DockMargin(0, 0, k.S(8), k.S(4))
    return b
end

local function custom(sp, k, tall, paint)
    local p = vgui.Create("DPanel", sp)
    p:Dock(TOP)
    p:DockMargin(0, 0, k.S(8), k.S(6))
    p:SetTall(tall)
    p.Paint = paint
    return p
end

local function layoutKey(v)
    local m = v.mods or {}
    local parts = {
        v.insp and 1 or 0, v.open and 1 or 0, v.lid and 1 or 0, v.safe and 1 or 0, v.done and 1 or 0,
        v.gasSealed and 1 or 0, v.leakEnd and 1 or 0, v.sealedOpen and 1 or 0, v.recover and 1 or 0, v.kit and 1 or 0,
        v.chip and (v.chip.ok and 2 or 1) or 0, v.liquid and (v.liquid.drained and 2 or 1) or 0,
        v.fake and (v.fake.removed and 2 or 1) or 0, v.stab and (v.stab.done and 2 or 1) or 0,
        v.timer and 1 or 0,
    }
    for _, mm in ipairs(E.MODS) do parts[#parts + 1] = m[mm.id] and 1 or 0 end
    return table.concat(parts, ",")
end

local function buildLeft(win, k)
    local sp = win.left
    local scroll = sp:GetVBar():GetScroll()
    sp:Clear()
    local v = win.v
    local s = k.S
    local C = k.C
    local ply = LocalPlayer()

    if v.timer then
        custom(sp, k, s(46), function(_, w, h)
            k.Plate(0, 0, w, h, { bg = Color(8, 8, 8, 255) })
            local txt, col = timerText(W() and W().v or v)
            draw.SimpleText("TIMER", k.Font(12, 700), s(10), h / 2, C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(txt or "", k.Font(24, 800), w - s(10), h / 2, col or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end)
    end

    section(sp, k, "First inspection")
    if not v.insp then
        text(sp, k, "Hold to look the bomb over before touching anything: detonator, anti-jam, motion sensor, lid switch, charge.")
        local need = (E.Cfg("inspectTime") or 2.5)
        local b = holdButton(sp, k, "Hold to inspect", need, function() act(0) end, function() act(1) end)
        b:Dock(TOP)
        b:DockMargin(0, 0, s(8), s(4))
    else
        for _, f in ipairs(v.insp) do
            custom(sp, k, s(24), function(_, w, h)
                k.SetCol(C.row)
                surface.DrawRect(0, 0, w, h)
                draw.SimpleText(f[1], k.Font(13), s(8), h / 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(k.Fit(f[2], k.Font(13, 700), w * 0.62), k.Font(13, 700), w - s(8), h / 2, f[3] and C.warn or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end)
        end
    end

    if not v.kit then
        section(sp, k, "No EOD kit")
        text(sp, k, "You can look, but opening and working on the bomb needs an EOD kit (ammo cabinet).", C.warn)
    end

    if not v.open then
        section(sp, k, "Casing")
        btn(sp, k, v.lid and "Lid-switch tab released" or "Release the lid-switch tab", function() act(2) end, { enabled = v.kit and not v.lid })
        btn(sp, k, "Lift the lid", function() act(3) end, { enabled = v.kit, accent = true })
    end

    local mods = v.mods or {}
    if v.open and (mods.fuse or mods.sealed) then
        section(sp, k, "Board heat")
        custom(sp, k, s(22), function(_, w, h)
            local win2 = W()
            if not win2 then return end
            local heat = heatNow(win2)
            k.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            local col = heat > 75 and C.bad or heat > 45 and C.warn or C.good
            k.SetCol(col)
            surface.DrawRect(1, 1, (w - 2) * heat / 100, h - 2)
            draw.SimpleText(math.floor(heat) .. "°", k.Font(12, 700), w / 2, h / 2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end)
        text(sp, k, "Cuts, jumpers and the torch heat the board. Past 100° it fires; it cools on its own.")
    end

    if v.open and v.tilt and not v.safe then
        section(sp, k, "Tilt switch")
        local lvl = custom(sp, k, s(150), function(_, w, h)
            local win2 = W()
            if not win2 or not win2.v.tilt then return end
            local r = math.min(w, h) / 2 - s(4)
            local cx, cy = w / 2, h / 2
            circle(cx, cy, r, Color(61, 90, 71))
            circle(cx, cy, r - 2, Color(15, 26, 20))
            circle(cx, cy, r * 0.33, Color(61, 90, 71))
            circle(cx, cy, r * 0.33 - 1, Color(15, 26, 20))
            local x, y = E.TiltPos(win2.v.tilt, CurTime())
            local d = math.sqrt(x * x + y * y)
            circle(cx + x * r * 0.8, cy + y * r * 0.8, s(10), d > 0.8 and Color(255, 110, 80) or Color(255, 209, 102))
        end)
        local row = vgui.Create("DPanel", sp)
        row:Dock(TOP)
        row:SetTall(s(30))
        row:DockMargin(0, 0, s(8), s(4))
        row.Paint = nil
        for _, d in ipairs({ { "←", -1, 0 }, { "↑", 0, -1 }, { "↓", 0, 1 }, { "→", 1, 0 } }) do
            local b = k.Button(row, d[1], function() E.Nudge(d[2], d[3]) end, { small = true })
            b:Dock(LEFT)
            b:SetWide(s(72))
            b:DockMargin(0, 0, s(4), 0)
        end
        text(sp, k, "Keep the bubble off the edge (arrow keys work too). Cuts and jumpers jolt it.")
        local _ = lvl
    end

    if v.open and mods.sealed and not v.sealedOpen then
        section(sp, k, "Sealed compartment")
        text(sp, k, "The detonator line runs under a welded plate. Hold the torch to cut it open; it heats the board.")
        local b = holdButton(sp, k, "Hold: torch", nil, function() act(8, function() net.WriteBool(true) end) end, nil,
            function() act(8, function() net.WriteBool(false) end) end)
        b:Dock(TOP)
        b:DockMargin(0, 0, s(8), s(4))
    end

    if v.open and v.chip and not v.chip.ok then
        section(sp, k, "Logic chip")
        text(sp, k, "Count the LED's short and long blinks, set the switches from the manual's table, then Enter.")
        win.chipSw = win.chipSw or { false, false, false, false }
        local row = vgui.Create("DPanel", sp)
        row:Dock(TOP)
        row:SetTall(s(34))
        row:DockMargin(0, 0, s(8), s(4))
        row.Paint = nil
        for i = 1, 4 do
            local b = k.Button(row, function() return (win.chipSw[i] and "1" or "0") end, function() win.chipSw[i] = not win.chipSw[i] end,
                { selected = function() return win.chipSw[i] end })
            b:Dock(LEFT)
            b:SetWide(s(52))
            b:DockMargin(0, 0, s(4), 0)
        end
        local go = k.Button(row, "Enter", function()
            local str = ""
            for i = 1, 4 do str = str .. (win.chipSw[i] and "1" or "0") end
            act(9, function() net.WriteString(str) end)
        end, { accent = true })
        go:Dock(FILL)
    end

    if v.open and v.liquid and not v.liquid.drained then
        section(sp, k, "Liquid charge")
        custom(sp, k, s(34), function(_, w, h)
            local win2 = W()
            if not win2 or not win2.v.liquid then return end
            local l = win2.v.liquid
            k.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            k.SetCol(Color(70, 167, 88, 160))
            surface.DrawRect(w * l.band / 100, 1, w * 14 / 100, h - 2)
            local n = E.LiquidNeedle(l, CurTime())
            k.SetCol(Color(255, 255, 255))
            surface.DrawRect(w * n / 100 - 1, 0, 3, h)
            k.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
        end)
        btn(sp, k, "Open the drain valve", function() act(10) end, { accent = true })
        text(sp, k, "Only with every supply dead, and only while the needle is in the green band.")
    end

    if v.open and v.fake and not v.fake.removed then
        section(sp, k, "Fake board")
        text(sp, k, "A cover hides the real board. X-ray it to see the order, then cut the three mount wires in that order.")
        btn(sp, k, function() return "X-ray (" .. ((W() and W().v.fake and W().v.fake.xrays) or 0) .. " left)" end, function() act(11) end,
            { enabled = function() local w2 = W() return w2 and w2.v.fake and (w2.v.fake.xrays or 0) > 0 end })
    end

    if v.safe and v.gas and not v.gasSealed then
        section(sp, k, "Gas valve")
        custom(sp, k, s(26), function(_, w, h)
            local win2 = W()
            local left = win2 and win2.v.leakEnd and math.max(0, win2.v.leakEnd - CurTime()) or 0
            draw.SimpleText(string.format("Venting: %.1f s to seal it", left), k.Font(14, 700), 0, h / 2, C.bad, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end)
        btn(sp, k, "Seal the valve", function() act(14) end, { danger = true })
    end

    if v.stab and v.safe and not v.stab.done then
        section(sp, k, "Charge stabiliser")
        text(sp, k, "Inject exactly the dose printed on the charge.")
        win.stabQ = win.stabQ or 4
        local row = k.Row(sp, "Dose (ml)")
        row:Dock(TOP)
        row:DockMargin(0, 0, s(8), s(4))
        local sl = k.Slider(row.right, 0.25, 7.75, 2, function() return win.stabQ / 4 end, function(x) win.stabQ = math.Clamp(math.floor(x * 4 + 0.5), 1, 31) end)
        sl:Dock(FILL)
        btn(sp, k, "Inject", function() act(13, function() net.WriteUInt(win.stabQ, 5) end) end, { accent = true })
    end

    if v.done then
        section(sp, k, "Made safe")
        text(sp, k, "This bomb can't go off any more.", C.good)
        if v.recover then
            btn(sp, k, "Recover the charge", function() act(15) end, { accent = true })
        end
    end

    timer.Simple(0, function() if IsValid(sp) then sp:GetVBar():SetScroll(scroll) end end)
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function closeWindow(tell)
    local w = E.win
    E.win = nil
    if w and IsValid(w.frame) then w.frame:Remove() end
    if tell and w and IsValid(w.bomb) then
        Net.Start("eod.close")
        net.WriteEntity(w.bomb)
        net.SendToServer()
    end
end
E.CloseWindow = closeWindow

function E.Nudge(dx, dy)
    local w = W()
    if not w or not w.v.tilt or w.overlay then return end
    w.v.tilt.nx = math.Clamp(w.v.tilt.nx + dx * 0.14, -3, 3)
    w.v.tilt.ny = math.Clamp(w.v.tilt.ny + dy * 0.14, -3, 3)
    act(7, function() net.WriteInt(dx, 3) net.WriteInt(dy, 3) end)
end

local function overlay(win, k, kind, a, b, c)
    if IsValid(win.ov) then win.ov:Remove() end
    win.overlay = kind
    local s = k.S
    local C = k.C
    local f = win.frame
    local ov = vgui.Create("DPanel", f)
    win.ov = ov
    ov:SetSize(f:GetWide(), f:GetTall())
    ov:SetPos(0, 0)
    local bad = kind == "fail"
    function ov:Paint(w, h)
        k.SetCol(Color(0, 0, 0, 255), 215)
        surface.DrawRect(0, 0, w, h)
        local pw, ph = s(560), s(250)
        local x, y = (w - pw) / 2, (h - ph) / 2
        k.Plate(x, y, pw, ph, { title = bad and "Detonation" or "Bomb made safe", ticks = "all", bg = OPAQUE, rule = bad and C.bad or C.good })
        draw.SimpleText(a or "", k.Font(20, 800), x + s(18), y + s(52), bad and C.bad or C.good)
        local yy = y + s(84)
        for _, line in ipairs({ b or "", c and c ~= "" and ("Manual: " .. c) or "" }) do
            if line ~= "" then
                local wrapped = {}
                local cur = ""
                surface.SetFont(k.Font(14))
                for word in string.gmatch(line, "%S+") do
                    local try = cur == "" and word or (cur .. " " .. word)
                    if surface.GetTextSize(try) > pw - s(36) then wrapped[#wrapped + 1] = cur cur = word else cur = try end
                end
                wrapped[#wrapped + 1] = cur
                for _, wl in ipairs(wrapped) do
                    draw.SimpleText(wl, k.Font(14), x + s(18), yy, C.text)
                    yy = yy + s(20)
                end
                yy = yy + s(8)
            end
        end
    end
    local bx = (f:GetWide() + s(560)) / 2 - s(18) - s(120)
    local by = (f:GetTall() + s(250)) / 2 - s(18) - s(34)
    local close = k.Button(ov, "Close", function() closeWindow(true) end, { accent = true })
    close:SetSize(s(120), s(34))
    close:SetPos(bx, by)
    if not bad then
        local back = k.Button(ov, "Back to the bomb", function() win.overlay = nil win.ovDone = true ov:Remove() end)
        back:SetSize(s(170), s(34))
        back:SetPos(bx - s(180), by)
    end
    -- Training bomb: go again (a failed one re-arms by itself in a few seconds).
    if IsValid(win.bomb) and win.bomb.IsTrainingBomb then
        local again = k.Button(ov, bad and "Training: it re-arms in 3 s" or "Same again", function()
            if bad then return end
            if E.TrainAct then E.TrainAct(win.bomb, 1) end
            closeWindow(true)
        end, { enabled = not bad })
        again:SetSize(s(190), s(34))
        again:SetPos(bx - (bad and s(200) or s(380)), by)
    end
end

local function openWindow(bomb)
    local k = K()
    if not k then
        chat.AddText(Color(255, 170, 60), "[EOD] ", color_white, "The defusal window needs rhylib_menus.")
        return nil
    end
    closeWindow(false)
    local s = k.S
    local C = k.C
    local f = vgui.Create("EditablePanel")
    local fw, fh = math.min(ScrW() - s(60), s(1340)), math.min(ScrH() - s(60), s(800))
    f:SetSize(fw, fh)
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(true)
    f:DockPadding(s(12), s(48), s(12), s(12))
    local win = { frame = f, bomb = bomb, reads = {}, log = {}, tool = "probe" }
    E.win = win

    function f:Paint(w, h)
        local cur = W()
        local v = cur and cur.v
        k.Plate(0, 0, w, h, { title = "Bomb" .. (v and (" · " .. v.kind) or ""), ticks = "all", header = s(38), bg = OPAQUE,
            sub = v and (v.kit and "EOD kit ready" or "No EOD kit") or "" })
    end

    local x = k.Button(f, "Close", function() closeWindow(true) end, { small = true })
    x:SetSize(s(90), s(26))
    x:SetPos(fw - s(90) - s(160), s(6))
    if bomb.IsTrainingBomb then
        local ts = k.Button(f, "Training setup", function() if E.TrainingSetup then E.TrainingSetup(bomb) end end, { small = true, accent = true })
        ts:SetSize(s(150), s(26))
        ts:SetPos(fw - s(90) - s(160) - s(160), s(6))
    end

    local left = vgui.Create("DPanel", f)
    left:Dock(LEFT)
    left:SetWide(s(370))
    left:DockMargin(0, 0, s(12), 0)
    left.Paint = nil
    win.left = k.Scroll(left)
    win.left:Dock(FILL)

    local right = vgui.Create("DPanel", f)
    right:Dock(FILL)
    right.Paint = nil

    -- tools
    local tools = vgui.Create("DPanel", right)
    tools:Dock(TOP)
    tools:SetTall(s(34))
    tools:DockMargin(0, 0, 0, s(6))
    tools.Paint = nil
    for _, t in ipairs({ { "probe", "Probe" }, { "cut", "Wirecutters" }, { "jump", "Jumper wire" } }) do
        local b = k.Button(tools, function()
            if t[1] == "jump" then local cw = W() return "Jumper wire (" .. (cw and cw.v and cw.v.jumpers or 0) .. ")" end
            return t[2]
        end, function() win.tool = t[1] win.pick = nil end, { selected = function() return win.tool == t[1] end })
        b:Dock(LEFT)
        b:SetWide(s(170))
        b:DockMargin(0, 0, s(6), 0)
    end
    local note = vgui.Create("DPanel", tools)
    note:Dock(FILL)
    function note:Paint(w, h)
        local t = win.tool == "jump" and (win.pick and "Click the second terminal (the same part's other terminal shorts it)." or "Click a + or − terminal to start a jumper.")
            or "Hover a wire to trace it. The probe reads it, the wirecutters cut it."
        draw.SimpleText(k.Fit(t, k.Font(12), w - s(8)), k.Font(12), s(8), h / 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- last reading
    local read = vgui.Create("DPanel", right)
    read:Dock(TOP)
    read:SetTall(s(30))
    read:DockMargin(0, 0, 0, s(6))
    function read:Paint(w, h)
        k.SetCol(Color(8, 8, 8, 255))
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("PROBE", k.Font(12, 700), s(10), h / 2, C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(win.lastRead or "—", k.Font(15, 700), s(70), h / 2, Color(130, 255, 160), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- log
    local log = vgui.Create("DPanel", right)
    log:Dock(BOTTOM)
    log:SetTall(s(118))
    log:DockMargin(0, s(6), 0, 0)
    function log:Paint(w, h)
        k.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local y = s(6)
        for _, l in ipairs(win.log) do
            draw.SimpleText(k.Fit(l[1], k.Font(13), w - s(16)), k.Font(13), s(8), y, l[2] and C.bad or C.text)
            y = y + s(18)
            if y > h - s(16) then break end
        end
    end

    win.board = boardPanel(right, k)
    win.board:Dock(FILL)

    function f:Think()
        local cur = W()
        if not cur then return end
        local ply = LocalPlayer()
        if cur.overlay ~= "fail" and (not ply:Alive() or not IsValid(cur.bomb)) then closeWindow(false) return end
        -- arrow keys nudge the tilt switch
        local v = cur.v
        if v and v.tilt and v.open and not v.safe and not cur.overlay and CurTime() >= (cur.nudgeAt or 0) then
            local dx = (input.IsKeyDown(KEY_RIGHT) and 1 or 0) - (input.IsKeyDown(KEY_LEFT) and 1 or 0)
            local dy = (input.IsKeyDown(KEY_DOWN) and 1 or 0) - (input.IsKeyDown(KEY_UP) and 1 or 0)
            if dx ~= 0 or dy ~= 0 then
                cur.nudgeAt = CurTime() + 0.12
                E.Nudge(dx, dy)
            end
        end
        if v and v.done and not cur.overlay and not cur.ovDone then overlay(cur, k, "done", "The bomb can't go off any more.", "Good work. Cut wires and jumpers stay as they are.", nil) end
    end
    function f:OnKeyCodePressed(code)
        if code == KEY_ESCAPE then closeWindow(true) end
    end
    return win
end

--------------------------------------------------------------------------
-- Net
--------------------------------------------------------------------------

Net.Receive("eod.state", function()
    local bomb = net.ReadEntity()
    local len = net.ReadUInt(16)
    local raw = net.ReadData(len)
    local js = raw and util.Decompress(raw)
    local v = js and util.JSONToTable(js)
    if not (istable(v) and IsValid(bomb)) then return end
    local win = W()
    if not win or win.bomb ~= bomb then win = openWindow(bomb) end
    if not win then return end
    -- (JSON turns nested arrays into tables with number keys; parts and
    -- wires keep their order)
    win.v = v
    win.recv = CurTime()
    win.geo = buildGeo(v)
    local key = layoutKey(v)
    if key ~= win.layout then
        win.layout = key
        buildLeft(win, K())
    end
end)

Net.Receive("eod.read", function()
    local i = net.ReadUInt(5)
    local txt = net.ReadString()
    local win = W()
    if not win then return end
    win.reads[i] = txt
    local wd = win.v and win.v.wires[i]
    win.lastRead = (wd and (nameOf(wd.c) .. " wire: ") or "") .. txt
    addLog("Probe · " .. win.lastRead)
    surface.PlaySound("buttons/blip1.wav")
end)

Net.Receive("eod.msg", function()
    local t = net.ReadString()
    local bad = net.ReadBool()
    addLog(t, bad)
    if bad then surface.PlaySound("buttons/button10.wav") end
end)

Net.Receive("eod.xray", function()
    local bomb = net.ReadEntity()
    local order = { net.ReadUInt(2), net.ReadUInt(2), net.ReadUInt(2) }
    local secs = net.ReadFloat()
    local win = W()
    if not win or win.bomb ~= bomb then return end
    win.xray = { order = order, untilT = CurTime() + secs }
    surface.PlaySound("buttons/button17.wav")
end)

Net.Receive("eod.close", function()
    local bomb = net.ReadEntity()
    local win = W()
    if win and (win.bomb == bomb or not IsValid(bomb)) and win.overlay ~= "fail" then closeWindow(false) end
end)

Net.Receive("eod.done", function()
    surface.PlaySound("buttons/button3.wav")
end)

Net.Receive("eod.boom", function()
    local idx = net.ReadUInt(13)
    local cause = net.ReadString()
    local pos = net.ReadVector()
    local win = W()
    local c = E.CAUSES[cause] or E.CAUSES.gm
    if win and IsValid(win.frame) and (win.bomb:EntIndex() == idx or not IsValid(win.bomb)) then
        overlay(win, K(), "fail", c[1], c[2], c[3])
    else
        chat.AddText(Color(255, 170, 60), "[EOD] ", Color(255, 120, 110), "A bomb went off: " .. c[1])
    end
    local _ = pos
end)

-- A large bomb anywhere: everyone hears it.
Net.Receive("eod.far", function()
    local pos = net.ReadVector()
    local r = net.ReadFloat()
    local eye = EyePos()
    local d = eye:Distance(pos)
    if d > 2500 then
        local dir = (pos - eye):GetNormalized()
        sound.Play("ambient/explosions/explode_" .. math.random(7, 9) .. ".wav", eye + dir * 400, 100, math.Clamp(90 - d / 400, 50, 90), 1)
        util.ScreenShake(eye, math.Clamp(10 - d / 1500, 1, 8), 40, 2.5, 200)
    end
    local _ = r
end)

-- Gas and virus clouds: smoke that hangs for the cloud's time.
Net.Receive("eod.gas", function()
    local pos = net.ReadVector()
    local r = net.ReadFloat()
    local secs = net.ReadFloat()
    local virus = net.ReadBool()
    local em = ParticleEmitter(pos)
    if not em then return end
    local col = virus and Color(160, 110, 210) or Color(150, 190, 90)
    local untilT = CurTime() + secs
    E.gasN = (E.gasN or 0) + 1
    local id = "Rhylib.EOD.Gas." .. E.gasN
    local done = false
    local function finish()
        if done then return end
        done = true
        timer.Remove(id)
        if IsValid(em) then em:Finish() end
    end
    local function puff(n)
        for _ = 1, n do
            local off = VectorRand()
            off.z = math.abs(off.z) * 0.3
            local p = em:Add("particle/particle_smokegrenade", pos + off * r * math.Rand(0.1, 0.85))
            if p then
                p:SetVelocity(VectorRand() * 12)
                p:SetDieTime(math.Rand(5, 8))
                p:SetStartAlpha(0)
                p:SetEndAlpha(0)
                p:SetStartSize(r * 0.25)
                p:SetEndSize(r * 0.45)
                p:SetColor(col.r, col.g, col.b)
                p:SetRoll(math.Rand(0, 360))
                p:SetAirResistance(40)
                p:SetLighting(false)
                p:SetNextThink(CurTime())
                p:SetThinkFunction(function(pa)
                    local t = pa:GetLifeTime() / pa:GetDieTime()
                    pa:SetStartAlpha(math.sin(t * math.pi) * 120)
                    pa:SetNextThink(CurTime() + 0.05)
                end)
            end
        end
    end
    puff(24)
    timer.Create(id, 0.7, math.ceil(secs / 0.7), function()
        if done then return end
        if CurTime() > untilT then finish() return end
        puff(8)
    end)
    timer.Simple(secs + 1, finish)
end)

-- Aiming at a bomb: what E does.
Rhylib.Hook.Add("HUDPaint", "eod.hint", function()
    local ply = LocalPlayer()
    if W() or not ply:Alive() then return end
    local tr = ply:GetEyeTrace()
    local e = tr.Entity
    if not (IsValid(e) and (e.IsRhylibBomb or e:GetClass() == "rhylib_interference_dev")) or tr.HitPos:DistToSqr(tr.StartPos) > 160 * 160 then return end
    local k = K()
    local font = k and k.Font(15, 700) or "DermaDefaultBold"
    local txt
    if e.IsRhylibBomb then
        local w = ply:GetActiveWeapon()
        local gm = IsValid(w) and w:GetClass() == "rhylib_toolgun"
        txt = (e:GetNW2String("rhylib_eodKind", "Bomb")) .. (e:GetNW2Bool("rhylib_eodSafe", false) and " · safe" or "") .. "  ·  E: " .. (gm and "GM window" or "work on it")
    else
        txt = "Interference device  ·  E: settings"
    end
    draw.SimpleTextOutlined(txt, font, ScrW() / 2, ScrH() * 0.58, Color(255, 209, 102), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
end)

if Rhylib.Menus and Rhylib.Menus.RegisterCloser then
    Rhylib.Menus.RegisterCloser("eod", function() if W() then closeWindow(true) return true end end)
end
Rhylib.Hook.Add("InitPostEntity", "eod.closer", function()
    if Rhylib.Menus and Rhylib.Menus.RegisterCloser then
        Rhylib.Menus.RegisterCloser("eod", function() if W() then closeWindow(true) return true end end)
    end
end)
