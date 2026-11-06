--[[
    Defusal window (client). Fully opaque (owner). The server sends the
    bomb's view (eod.state: colours, ends and flags, never the wire kinds);
    the probe's readings come back one by one (eod.read).

    Left: timer, first inspection (hold), the casing, the modules and the
    gas valve (the tutorial bomb: its checklist first). Right: tools
    (probe, wirecutters, jumper wire), the last reading, the training hint
    (training bombs: the next step of view.steps, client convar
    rhylib_eod_hints, Settings > Interface), the board (hover a wire to
    trace it), and a log.

    The board: wires are routed in straight runs with rounded bends out of
    the side of a part facing the other end (buildGeo: kept clear of other
    parts and a lane apart from each other, cached while the board stays
    the same), drawn with a dark edge, their colour and a sheen, a plug
    where they meet a part, copper ends where cut.

    Every action is a net eod.act (bomb, op 4 bits, arguments; see
    sv_10_bomb). The client never decides anything: it shows the last
    view and runs live values (timer, heat, tilt bubble, needles) on from
    the view's numbers until the next eod.state.
    The left column is rebuilt only when layoutKey changes (which steps
    and modules are showing), so open sliders and switches keep their
    state between updates. A new module adds its section to buildLeft
    and its flags to layoutKey.

    Also here: the fail / done overlay (eod.boom, eod.done), gas cloud
    smoke (eod.gas), the far rumble of a large bomb (eod.far), and the
    "E: work on it" hint when aiming at a bomb or device.
    Needs Rhy's Core's UI kit (Rhylib.UI.Kit) for the window.
]]

-- Colours used while drawing (made once, not every frame). The bomb itself
-- (board, parts, wires, the tilt level, gas) keeps literal colours; the
-- window's own colours are theme tokens (Rhylib.UI.Col), read when drawing.
local Col = Rhylib.UI.Col
local COL_0_0_0_220 = Color(0, 0, 0, 220)
local COL_TIP_EDGE = Col("eod.tipEdge", 0, 0, 0, 230)
local COL_TIP_TEXT = Col("eod.tipText", 255, 255, 255)
local COL_OVERLAY = Col("eod.overlayDim", 0, 0, 0, 255)
local COL_110_190_255 = Color(110, 190, 255)
local COL_120_126_132 = Color(120, 126, 132)
local COL_PROBE_TEXT = Col("eod.probeText", 130, 255, 160)
local COL_138_147_156 = Color(138, 147, 156)
local COL_TIMER_IDLE = Col("eod.timerIdle", 140, 140, 140)
local COL_140_165_150 = Color(140, 165, 150)
local COL_143_154_164 = Color(143, 154, 164)
local COL_150_160_168 = Color(150, 160, 168)
local COL_150_190_90 = Color(150, 190, 90)
local COL_15_26_20 = Color(15, 26, 20)
local COL_160_110_210 = Color(160, 110, 210)
local COL_170_178_186 = Color(170, 178, 186)
local COL_17_17_17 = Color(17, 17, 17)
local COL_TIMER_WAIT = Col("eod.timerWait", 200, 120, 60)
local COL_200_206_210 = Color(200, 206, 210)
local COL_207_214_220 = Color(207, 214, 220)
local COL_207_227_212 = Color(207, 227, 212)
local COL_220_226_230 = Color(220, 226, 230)
local COL_220_232_224 = Color(220, 232, 224)
local COL_220_235_225 = Color(220, 235, 225)
local COL_TIMER_RUN = Col("eod.timerRun", 235, 70, 60)
local COL_255_110_80 = Color(255, 110, 80)
local COL_255_120_110 = Color(255, 120, 110)
local COL_255_170_60 = Color(255, 170, 60)
local COL_255_200_90 = Color(255, 200, 90)
local COL_255_209_102 = Color(255, 209, 102)
local COL_LIQUID_NEEDLE = Col("eod.liquidNeedle", 255, 255, 255)
local COL_255_255_255_120 = Color(255, 255, 255, 120)
local COL_255_60_50 = Color(255, 60, 50)
local COL_TIMER_LOW = Col("eod.timerLow", 255, 90, 80)
local COL_40_46_52 = Color(40, 46, 52)
local COL_43_49_56_115 = Color(43, 49, 56, 115)
local COL_43_49_56_255 = Color(43, 49, 56, 255)
local COL_58_64_72 = Color(58, 64, 72)
local COL_60_64_70 = Color(60, 64, 70)
local COL_61_90_71 = Color(61, 90, 71)
local COL_LIQUID_BAND = Col("eod.liquidBand", 70, 167, 88, 160)
local COL_70_20_20 = Color(70, 20, 20)
local COL_70_220_110 = Color(70, 220, 110)
local COL_TIMER_SAFE = Col("eod.timerSafe", 80, 220, 120)
local COL_89_99_109 = Color(89, 99, 109)
local COL_DISPLAY = Col("eod.displayBg", 8, 8, 8, 255)
local COL_ON_HINT = Col("eod.onHint", 17, 17, 17)
local COL_AIM_HINT = Col("eod.aimHint", 255, 209, 102)
local COL_AIM_EDGE = Col("eod.aimHintEdge", 0, 0, 0, 220)
local COL_90_100_110 = Color(90, 100, 110)

local E = Rhylib.EOD
local Net = Rhylib.Net

local function K() return Rhylib.UI and Rhylib.UI.Kit end
local OPAQUE = Col("eod.windowBg", 14, 16, 15, 255)
local BOARD_BG = Color(14, 27, 20, 255)
local PART_BG = Color(22, 38, 29, 255)
local PART_EDGE = Color(96, 128, 108, 255)
local TERM_EDGE = Color(135, 165, 146, 255)
local JUMPER = Color(255, 209, 102)
local BW, BH = 760, 420

E.win = E.win or nil   -- { frame, bomb, v, recv, reads, log, tool, pick, xray, ... }

-- The open window, or nil.
local function W() local w = E.win return (w and IsValid(w.frame)) and w or nil end

-- Training hints (training bombs: the next step of the safe order at the
-- top of the board, the wire or part it's about outlined). The tutorial
-- bomb always shows them, with its checklist in the left column.
local cvHints = CreateClientConVar("rhylib_eod_hints", "1", true, false, "Training bombs: show a hint for the next step (1) or not (0)")
local function hintOf(v)
    if not (v and v.steps) or v.done then return nil end
    if not v.tutorial and not cvHints:GetBool() then return nil end
    for n, st in ipairs(v.steps) do
        if not st.done then return { n = n, of = #v.steps, t = st.t, why = st.why, wire = st.wire, part = st.part } end
    end
end
local function addHintSetting()
    local M = Rhylib.Menus
    if not (M and M.AddSetting) then return end
    M.AddSetting("Bombs & mines", { id = "eod.hints", order = 90, tab = "Interface", title = "Training bomb hints",
        desc = "Training bombs show the next step at the top of the defusal window and outline the wire it's about (the tutorial bomb always does)",
        kind = "toggle", convar = "rhylib_eod_hints" })
end
addHintSetting()
Rhylib.Hook.Add("InitPostEntity", "eod.hintsetting", addHintSetting)

-- Send net eod.act for the open window's bomb; write() adds the arguments.
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
    if not w then   -- (no window open: a normal notice)
        Rhylib.Notify(nil, text, bad and "bad" or "info", "EOD")
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

-- Wire routing (board units). Every wire leaves a part from its left or
-- right side (the side facing the other part; parts in the same column
-- use the side facing the middle of the board, a loop out and back),
-- runs in straight lines with rounded bends, and keeps out of other
-- parts. Wires on one side are spread over it in the order of where
-- they go, so they don't cross at the part; parallel runs keep a lane
-- apart (occupied lists), so nothing twists or overlaps.
local MARGIN, LANE = 5, 9

local function sideOf(p, q)
    local qcx = q.x + q.w / 2
    if qcx > p.x + p.w then return 1 end
    if qcx < p.x then return -1 end
    return (p.x + p.w / 2) < BW / 2 and 1 or -1
end

local function clearH(parts, y, xa, xb, skipA, skipB)
    local x1, x2 = math.min(xa, xb), math.max(xa, xb)
    for _, p in ipairs(parts) do
        if p ~= skipA and p ~= skipB and y > p.y - MARGIN and y < p.y + p.h + MARGIN and x2 > p.x - MARGIN and x1 < p.x + p.w + MARGIN then return false end
    end
    return true
end
local function clearV(parts, x, ya, yb, skipA, skipB)
    local y1, y2 = math.min(ya, yb), math.max(ya, yb)
    for _, p in ipairs(parts) do
        if p ~= skipA and p ~= skipB and x > p.x - MARGIN and x < p.x + p.w + MARGIN and y2 > p.y - MARGIN and y1 < p.y + p.h + MARGIN then return false end
    end
    return true
end
-- A run at c from a to b (vertical: x = c) not too close to one already laid.
local function freeRun(list, c, a, b)
    local lo, hi = math.min(a, b), math.max(a, b)
    for _, r in ipairs(list) do
        if math.abs(r[1] - c) < LANE and hi > r[2] - 2 and lo < r[3] + 2 then return false end
    end
    return true
end
local function takeRun(list, c, a, b) list[#list + 1] = { c, math.min(a, b), math.max(a, b) } end

-- Corners -> points with rounded bends (radius up to 10).
local function rounded(corners)
    local pts = { { corners[1][1], corners[1][2] } }
    for i = 2, #corners - 1 do
        local a, b, c = corners[i - 1], corners[i], corners[i + 1]
        local l1 = math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
        local l2 = math.abs(c[1] - b[1]) + math.abs(c[2] - b[2])
        local r = math.min(10, l1 / 2, l2 / 2)
        if r < 1 then
            pts[#pts + 1] = { b[1], b[2] }
        else
            local d1x, d1y = (b[1] - a[1]) / l1, (b[2] - a[2]) / l1
            local d2x, d2y = (c[1] - b[1]) / l2, (c[2] - b[2]) / l2
            local sx, sy = b[1] - d1x * r, b[2] - d1y * r
            local ex, ey = b[1] + d2x * r, b[2] + d2y * r
            for k2 = 0, 4 do
                local t = k2 / 4
                local u = 1 - t
                -- (a quadratic through the corner: close to a quarter circle)
                pts[#pts + 1] = { u * u * sx + 2 * u * t * b[1] + t * t * ex, u * u * sy + 2 * u * t * b[2] + t * t * ey }
            end
        end
    end
    pts[#pts + 1] = { corners[#corners][1], corners[#corners][2] }
    return pts
end

-- Length along pts; the point at distance d; the points from d1 to d2.
local function lengthOf(pts)
    local L = 0
    for i = 1, #pts - 1 do L = L + math.sqrt((pts[i + 1][1] - pts[i][1]) ^ 2 + (pts[i + 1][2] - pts[i][2]) ^ 2) end
    return L
end
local function slice(pts, d1, d2)
    local out, acc = {}, 0
    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        local l = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
        if l > 0 then
            local s0, s1 = acc, acc + l
            if s1 >= d1 and s0 <= d2 then
                local t0 = math.max(0, (d1 - s0) / l)
                local t1 = math.min(1, (d2 - s0) / l)
                if #out == 0 then out[1] = { a[1] + (b[1] - a[1]) * t0, a[2] + (b[2] - a[2]) * t0 } end
                out[#out + 1] = { a[1] + (b[1] - a[1]) * t1, a[2] + (b[2] - a[2]) * t1 }
            end
        end
        acc = acc + l
    end
    return out
end

-- Candidate lane positions from a toward b (step 5), the middle first
-- when between, else outward from the edge.
local function lanes(from, to)
    local out = {}
    if to > from then
        local mid = (from + to) / 2
        for d = 0, (to - from) / 2, 5 do
            out[#out + 1] = mid - d
            if d > 0 then out[#out + 1] = mid + d end
        end
    else
        for d = 0, 140, 5 do out[#out + 1] = from + d end
    end
    return out
end

local function route(parts, A, B, p1, p2, vRuns, hRuns)
    local x1, y1, d1 = p1[1], p1[2], p1[3]
    local x2, y2, d2 = p2[1], p2[2], p2[3]
    local function okLane(lx)
        return (lx - x1) * d1 >= 12 and (lx - x2) * d2 >= 12 and lx > 4 and lx < BW - 4
    end
    -- the lanes to try: between the two sides, or outward past both (a loop)
    local cand
    if d1 ~= d2 then
        local a, b = math.min(x1, x2) + 12, math.max(x1, x2) - 12
        cand = lanes(a, b)
    else
        local edge = d1 > 0 and math.max(x1, x2) + 14 or math.min(x1, x2) - 14
        cand = {}
        for d = 0, 140, 5 do cand[#cand + 1] = edge + d * d1 end
    end
    -- 1) one lane: out, along, in
    for _, lx in ipairs(cand) do
        if okLane(lx) and freeRun(vRuns, lx, y1, y2) and clearH(parts, y1, x1, lx, A, B) and clearV(parts, lx, y1, y2, A, B) and clearH(parts, y2, lx, x2, A, B)
            and freeRun(hRuns, y1, x1, lx) and freeRun(hRuns, y2, lx, x2) then
            takeRun(vRuns, lx, y1, y2)
            takeRun(hRuns, y1, x1, lx)
            takeRun(hRuns, y2, lx, x2)
            return { { x1, y1 }, { lx, y1 }, { lx, y2 }, { x2, y2 } }
        end
    end
    -- 2) two lanes and a band across, for wires that would cut through a column
    local l1s, l2s = {}, {}
    for d = 0, 80, 5 do l1s[#l1s + 1] = x1 + (14 + d) * d1 end
    for d = 0, 80, 5 do l2s[#l2s + 1] = x2 + (14 + d) * d2 end
    for dy = 0, 150, 6 do
        for _, by in ipairs({ (y1 + y2) / 2 - dy, (y1 + y2) / 2 + dy }) do
            if by > 8 and by < BH - 8 then
                for _, l1 in ipairs(l1s) do
                    if l1 > 4 and l1 < BW - 4 and clearH(parts, y1, x1, l1, A, B) and clearV(parts, l1, y1, by, A, B) and freeRun(vRuns, l1, y1, by) then
                        for _, l2 in ipairs(l2s) do
                            if l2 > 4 and l2 < BW - 4 and clearH(parts, by, l1, l2, A, B) and freeRun(hRuns, by, l1, l2)
                                and clearV(parts, l2, by, y2, A, B) and clearH(parts, y2, l2, x2, A, B) and freeRun(vRuns, l2, by, y2) then
                                takeRun(vRuns, l1, y1, by)
                                takeRun(vRuns, l2, by, y2)
                                takeRun(hRuns, by, l1, l2)
                                return { { x1, y1 }, { l1, y1 }, { l1, by }, { l2, by }, { l2, y2 }, { x2, y2 } }
                            end
                        end
                    end
                end
            end
        end
    end
    -- 3) nothing clear: one lane in the middle anyway
    local lx = d1 ~= d2 and (x1 + x2) / 2 or ((d1 > 0 and math.max(x1, x2) or math.min(x1, x2)) + 16 * d1)
    return { { x1, y1 }, { lx, y1 }, { lx, y2 }, { x2, y2 } }
end

-- Wire geometry for the view: per wire the points (rounded), its length,
-- the middle point (readings, the sealed plate), the two halves of a cut
-- wire, its ports (plugs) and the armour band points. Also the fake
-- board's mount wires. Cached while the board's parts and wires stay the
-- same (only cut flags and readings change between state messages).
local function geoKey(v)
    local t = {}
    for _, p in ipairs(v.parts) do t[#t + 1] = p.id .. ":" .. p.x .. ":" .. p.y end
    for _, w in ipairs(v.wires) do t[#t + 1] = w.a .. ">" .. w.b end
    return table.concat(t, ",")
end

local function buildGeo(v, old)
    local key = geoKey(v)
    if old and old.key == key then return old end
    local geo = { wires = {}, key = key }
    local byId = {}
    for _, p in ipairs(v.parts) do byId[p.id] = p end
    -- ports: per part side, the wires leaving it, in the order of where they go
    local sides = {}
    local ends = {}
    for i, w in ipairs(v.wires) do
        local a, b = byId[w.a], byId[w.b]
        if a and b then
            local da, db = sideOf(a, b), sideOf(b, a)
            ends[i] = { a = a, b = b, da = da, db = db }
            for _, e in ipairs({ { a, da, b }, { b, db, a } }) do
                local k = e[1].id .. (e[2] > 0 and "r" or "l")
                sides[k] = sides[k] or { part = e[1], dir = e[2], list = {} }
                table.insert(sides[k].list, { wire = i, other = e[3], isA = e[1] == a })
            end
        end
    end
    local port = {}
    for _, sd in pairs(sides) do
        local p = sd.part
        table.sort(sd.list, function(m, n)
            local my, ny = m.other.y + m.other.h / 2, n.other.y + n.other.h / 2
            if my ~= ny then return my < ny end
            return m.wire < n.wire
        end)
        -- (room on the side: under the label, above the terminals on the right)
        local top = p.y + math.min(22, p.h * 0.3)
        local bottom = p.y + p.h - ((sd.dir > 0 and p.term) and 26 or 10)
        if bottom - top < 8 then top, bottom = p.y + p.h * 0.3, p.y + p.h * 0.7 end
        local n = #sd.list
        local step = math.min(12, (bottom - top) / math.max(1, n))
        local y0 = (top + bottom) / 2 - step * (n - 1) / 2
        for j, e in ipairs(sd.list) do
            local x = sd.dir > 0 and p.x + p.w or p.x
            port[e.wire] = port[e.wire] or {}
            port[e.wire][e.isA and "a" or "b"] = { x, y0 + (j - 1) * step, sd.dir }
        end
    end
    -- route, shortest first (they get the straightest lanes)
    local order = {}
    for i in pairs(ends) do order[#order + 1] = i end
    table.sort(order, function(m, n)
        local pm, pn = port[m], port[n]
        local lm = math.abs(pm.a[1] - pm.b[1]) + math.abs(pm.a[2] - pm.b[2])
        local ln = math.abs(pn.a[1] - pn.b[1]) + math.abs(pn.a[2] - pn.b[2])
        if lm ~= ln then return lm < ln end
        return m < n
    end)
    local vRuns, hRuns = {}, {}
    for _, i in ipairs(order) do
        local e, pp = ends[i], port[i]
        local pts = rounded(route(v.parts, e.a, e.b, pp.a, pp.b, vRuns, hRuns))
        local L = lengthOf(pts)
        local mid = slice(pts, L / 2, L / 2)[1] or pts[1]
        local bands = {}
        for d = 14, L - 14, 22 do bands[#bands + 1] = slice(pts, d, d)[1] end
        local cutA, cutB = slice(pts, 0, L / 2 - 9), slice(pts, L / 2 + 9, L)
        geo.wires[i] = { pts = pts, mid = mid, len = L, cutA = cutA, cutB = cutB, halves = { cutA, cutB },
            cutEnds = { cutA[#cutA], cutB[1] }, ports = { pp.a, pp.b }, bands = bands }
        if v.wires[i].sealed then geo.sealed = mid end
    end
    -- fake board mounts
    geo.mounts = {}
    for m = 1, 3 do
        local x, y = BW * 0.25 * m, BH - 60
        geo.mounts[m] = { pts = bezier(x, y - 34, x + 40, y - 20, x - 40, y + 10, x, y + 26, 16), x = x, y = y }
    end
    return geo
end

-- A part's + (left) and − (right) terminal, bottom right corner.
local function termPos(p, plus)
    return p.x + p.w - (plus and 36 or 14), p.y + p.h - 14
end

--------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------

-- A thick line along pts (board units) as one quad per segment, scaled
-- by sc and offset by ox / oy. skipFrom..skipTo leaves a gap (a cut wire).
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

-- A thin highlight along pts, offset sideways by off (board units): the
-- sheen on a wire's insulation.
local function sheen(pts, width, col, sc, ox, oy, off)
    surface.SetDrawColor(col)
    draw.NoTexture()
    local hw = width / 2
    for i = 1, #pts - 1 do
        local ax, ay = pts[i][1] * sc + ox, pts[i][2] * sc + oy
        local bx, by = pts[i + 1][1] * sc + ox, pts[i + 1][2] * sc + oy
        local dx, dy = bx - ax, by - ay
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.01 then
            local px, py = -dy / len * off * sc, dx / len * off * sc
            -- (the highlight sits on the upper / left side of the wire)
            if py > 0 or (py == 0 and px > 0) then px, py = -px, -py end
            local nx, ny = dy / len * hw, -dx / len * hw
            quad[1].x, quad[1].y = ax + px + nx, ay + py + ny
            quad[2].x, quad[2].y = bx + px + nx, by + py + ny
            quad[3].x, quad[3].y = bx + px - nx, by + py - ny
            quad[4].x, quad[4].y = ax + px - nx, ay + py - ny
            surface.DrawPoly(quad)
        end
    end
end

-- Darker / lighter copies of the wire colours (made once, not per frame).
local shade = {}
local function shadeOf(col, f)
    local key = col.r * 65536 + col.g * 256 + col.b + f * 16777216
    local c = shade[key]
    if not c then
        if f > 1 then
            c = Color(col.r + (255 - col.r) * (f - 1), col.g + (255 - col.g) * (f - 1), col.b + (255 - col.b) * (f - 1), 150)
        else
            c = Color(col.r * f, col.g * f, col.b * f)
        end
        shade[key] = c
    end
    return c
end

-- A coloured strip on top of each part, by what it is.
local PART_STRIP = {
    bat = Color(229, 72, 77), batB = Color(229, 72, 77), cell = Color(229, 72, 77), det = Color(229, 72, 77),
    cap = Color(239, 159, 39), aj = Color(239, 159, 39), tmr = Color(133, 183, 235),
    rx = Color(164, 110, 224), ant = Color(164, 110, 224), col = Color(164, 110, 224),
    chip = Color(60, 210, 220), relay = Color(140, 146, 152), load = Color(140, 146, 152), chg = Color(170, 176, 180),
}
local WIRE_EDGE = Color(4, 8, 6, 255)
local COPPER = Color(214, 142, 68)
local PLUG, PLUG_EDGE = Color(43, 47, 51), Color(10, 12, 13)
local HINT = Col("eod.hint", 245, 217, 10)
local HINT_SOFT = Col("eod.hintSoft", 245, 217, 10, 70)
local TUT_NOW_BG, HINT_BG, HINT_TEXT = Col("eod.stepNowBg", 36, 33, 15), Col("eod.hintBg", 36, 33, 15, 255), Col("eod.hintText", 240, 231, 180)

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

-- These run the view's numbers on from v.now (the server's CurTime when
-- it was sent) with the same config, so the bars move smoothly.
local function heatNow(w)
    local v = w.v
    local h = (v.heat or 0)
    local dt = CurTime() - (v.now or CurTime())
    if v.torching then
        h = h + dt * ((E.Cfg("heatTorch")) - (E.Cfg("heatCool")))
    else
        h = h - dt * (E.Cfg("heatCool"))
    end
    return math.Clamp(h, 0, 100)
end

local function sealedNow(w)
    local v = w.v
    local p = v.sealedP or 0
    if v.torching then p = p + (CurTime() - (v.now or CurTime())) / math.max(0.5, E.Cfg("torchTime")) end
    return math.Clamp(p, 0, 1)
end

local function timerText(v)
    local t = v.timer
    if not t then return nil end
    if v.safe or v.done then return "SAFE", COL_TIMER_SAFE end
    if v.tutorial and not (t.ends and t.ends > 0) then return "NO COUNTDOWN", COL_TIMER_IDLE end
    if t.ends and t.ends > 0 then
        local left = math.max(0, t.ends - CurTime())
        return string.FormattedTime(left, "%02i:%02i"), left < 15 and COL_TIMER_LOW or COL_TIMER_RUN
    end
    if t.stopped then return string.FormattedTime(t.left or 0, "%02i:%02i") .. "  STOPPED", COL_TIMER_IDLE end
    return string.FormattedTime(t.left or t.secs or 0, "%02i:%02i") .. "  WAITING", COL_TIMER_WAIT
end

--------------------------------------------------------------------------
-- The board panel
--------------------------------------------------------------------------

-- The board: drawn in board units (760 x 420) scaled to fit. Clicks go
-- by tool: probe (op 4) / cutters (op 5) on the nearest wire within 8
-- units, the jumper picks two terminals (op 6), and while the fake board
-- cover is on only its mount wires can be cut (op 12).
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
        if not v.kit then addLog("You need a " .. E.KitName(), true) return end
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
            k.SetCol(COL_40_46_52)
            surface.DrawRect(ox + 10 * sc, oy + 10 * sc, (BW - 20) * sc, (BH - 20) * sc)
            k.SetCol(COL_90_100_110)
            surface.DrawOutlinedRect(ox + 10 * sc, oy + 10 * sc, (BW - 20) * sc, (BH - 20) * sc, 2)
            draw.SimpleText("CASING CLOSED", k.Font(22, 800), w / 2, h / 2 - s(14), COL_200_206_210, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(v.lid and "Lid-switch tab released" or "Inspect first. Release the lid-switch tab (if it has one), then lift the lid.",
                k.Font(13), w / 2, h / 2 + s(14), COL_150_160_168, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end

        local hov = (not win.overlay) and self:Hover() or nil
        local geo = win.geo

        -- wires: armour under, a dark edge, the colour, a sheen on top;
        -- a cut wire shows a gap with copper ends
        local hintWire = win.hint and win.hint.wire
        for i, g in pairs(geo.wires) do
            local wd = v.wires[i]
            if wd then
                local col = colOf(wd.c)
                local hot = hov and hov.kind == "wire" and hov.i == i
                if hintWire == i and not wd.cut then thick(g.pts, 18 * sc, HINT_SOFT, sc, ox, oy) end
                if wd.arm then thick(g.pts, 13 * sc, COL_60_64_70, sc, ox, oy) end
                if wd.cut then
                    local dark = shadeOf(col, 0.5)
                    for _, half in ipairs(g.halves) do
                        if #half > 1 then
                            thick(half, 9 * sc, WIRE_EDGE, sc, ox, oy)
                            thick(half, 6 * sc, dark, sc, ox, oy)
                        end
                    end
                    -- (copper strands at the cut)
                    for _, e in ipairs(g.cutEnds) do circle(e[1] * sc + ox, e[2] * sc + oy, 2.6 * sc, COPPER) end
                else
                    if hot then thick(g.pts, 15 * sc, COL_255_255_255_120, sc, ox, oy) end
                    thick(g.pts, 10 * sc, WIRE_EDGE, sc, ox, oy)
                    thick(g.pts, 7 * sc, col, sc, ox, oy)
                    sheen(g.pts, 1.6 * sc, shadeOf(col, 1.6), sc, ox, oy, 1.6)
                end
                if wd.arm then
                    -- armour bands
                    for _, pt in ipairs(g.bands or {}) do
                        circle(pt[1] * sc + ox, pt[2] * sc + oy, 5 * sc, COL_120_126_132)
                    end
                end
            end
        end
        -- plugs where the wires meet the parts
        for _, g in pairs(geo.wires) do
            for _, pp in ipairs(g.ports or {}) do
                local px, py = (pp[1] + pp[3] * 4) * sc + ox, pp[2] * sc + oy
                draw.RoundedBox(2, px - 6 * sc, py - 7 * sc, 12 * sc, 14 * sc, PLUG_EDGE)
                draw.RoundedBox(2, px - 5 * sc, py - 6 * sc, 10 * sc, 12 * sc, PLUG)
            end
        end
        -- readings on the wires
        for i, g in pairs(geo.wires) do
            local wd = v.wires[i]
            local r = wd and win.reads[i]
            if r and not wd.cut then
                draw.SimpleTextOutlined(r, k.Font(11, 700), g.mid[1] * sc + ox, g.mid[2] * sc + oy - 10 * sc, COL_220_235_225, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, COL_0_0_0_220)
            end
        end

        -- parts
        for _, part in ipairs(v.parts) do
            local x, y, pw, ph = ox + part.x * sc, oy + part.y * sc, part.w * sc, part.h * sc
            local hinted = win.hint and win.hint.part == part.id
            draw.RoundedBox(4, x, y, pw, ph, hinted and HINT or PART_EDGE)
            draw.RoundedBox(4, x + (hinted and 2 or 1), y + (hinted and 2 or 1), pw - (hinted and 4 or 2), ph - (hinted and 4 or 2), PART_BG)
            local strip = PART_STRIP[part.id]
            if strip then
                surface.SetDrawColor(strip)
                surface.DrawRect(x + 3, y + 3, pw - 6, math.max(2, 4 * sc))
            end
            draw.SimpleText(part.label, k.Font(14, 700), x + 10 * sc, y + 8 * sc, COL_220_232_224)
            if part.sub and part.sub ~= "" then
                draw.SimpleText(part.sub, k.Font(12), x + 10 * sc, y + 26 * sc, COL_140_165_150)
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
                local col = v.chip.ok and COL_70_220_110 or (lit and COL_255_60_50 or COL_70_20_20)
                circle(x + pw - 20 * sc, y + 20 * sc, 8 * sc, col)
            end
            if part.id == "chg" then
                local yy = y + 46 * sc
                if v.stab and v.stab.dose then
                    draw.SimpleText("STABILISER", k.Font(11, 700), x + 10 * sc, yy, COL_255_209_102)
                    draw.SimpleText(string.format("%.2f ml", v.stab.dose), k.Font(16, 800), x + 10 * sc, yy + 14 * sc, COL_255_209_102)
                    yy = yy + 40 * sc
                end
                if v.liquid then
                    draw.SimpleText(v.liquid.drained and "LIQUID · drained" or "LIQUID CHARGE", k.Font(11, 700), x + 10 * sc, yy, COL_110_190_255)
                end
            end
        end

        -- sealed plate over the detonator line
        if geo.sealed and not v.sealedOpen then
            local cx, cy = geo.sealed[1] * sc + ox, geo.sealed[2] * sc + oy
            draw.RoundedBox(4, cx - 70 * sc, cy - 36 * sc, 140 * sc, 72 * sc, COL_138_147_156)
            draw.RoundedBox(4, cx - 69 * sc, cy - 35 * sc, 138 * sc, 70 * sc, COL_58_64_72)
            draw.SimpleText("Sealed plate", k.Font(13, 700), cx, cy - 10 * sc, COL_220_226_230, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("cut " .. math.floor(sealedNow(win) * 100) .. "%", k.Font(12), cx, cy + 12 * sc, COL_170_178_186, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if v.torching and now % 0.2 < 0.1 then circle(cx, cy - 34 * sc, 6 * sc, COL_255_200_90) end
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
                    circle(tx, ty, 7.5 * sc, picked and JUMPER or COL_15_26_20)
                    draw.SimpleText(plus and "+" or "−", k.Font(12, 800), tx, ty, picked and COL_17_17_17 or COL_207_227_212, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
            draw.RoundedBox(6, ox + 8 * sc, oy + 8 * sc, (BW - 16) * sc, (BH - 16) * sc, xray and COL_43_49_56_115 or COL_43_49_56_255)
            draw.SimpleText("Board cover", k.Font(16, 700), ox + 28 * sc, oy + 30 * sc, COL_207_214_220)
            draw.SimpleText(xray and "X-RAY: mount order shown" or ("Three mounts hold it down · X-rays left: " .. (v.fake.xrays or 0)), k.Font(12), ox + 28 * sc, oy + 52 * sc, COL_143_154_164)
            for m, g in ipairs(geo.mounts) do
                circle(g.x * sc + ox, (g.y - 34) * sc + oy, 7 * sc, COL_89_99_109)
                circle(g.x * sc + ox, (g.y + 26) * sc + oy, 7 * sc, COL_89_99_109)
                local col = colOf(v.fake.cols[m])
                local hot = hov and hov.kind == "mount" and hov.m == m
                if v.fake.cut[m] then
                    thick(g.pts, 6 * sc, shadeOf(col, 0.45), sc, ox, oy, 7, 9)
                else
                    if hot then thick(g.pts, 11 * sc, COL_255_255_255_120, sc, ox, oy) end
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
            draw.SimpleTextOutlined(txt, k.Font(13, 700), mx + s(14), my + s(6), COL_TIP_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, COL_TIP_EDGE)
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

-- A string of everything that changes what the left column shows.
local function layoutKey(v)
    local m = v.mods or {}
    local parts = {
        v.insp and 1 or 0, v.open and 1 or 0, v.lid and 1 or 0, v.safe and 1 or 0, v.done and 1 or 0,
        v.gasSealed and 1 or 0, v.leakEnd and 1 or 0, v.sealedOpen and 1 or 0, v.recover and 1 or 0, v.kit and 1 or 0,
        v.chip and (v.chip.ok and 2 or 1) or 0, v.liquid and (v.liquid.drained and 2 or 1) or 0,
        v.fake and (v.fake.removed and 2 or 1) or 0, v.stab and (v.stab.done and 2 or 1) or 0,
        v.timer and 1 or 0,
    }
    -- (the tutorial checklist: rebuilt as steps get done)
    if v.tutorial and v.steps then
        local n = 0
        for _, st in ipairs(v.steps) do if st.done then n = n + 1 end end
        parts[#parts + 1] = "t" .. n
    end
    for _, mm in ipairs(E.MODS) do parts[#parts + 1] = m[mm.id] and 1 or 0 end
    return table.concat(parts, ",")
end

-- The left column, top to bottom: timer, first inspection, kit warning,
-- casing, then one section per module that needs the player (heat, tilt,
-- sealed, chip, liquid, fake), the gas valve, the stabiliser, and
-- "Made safe" (with Recover the charge for Render safe). Keeps the
-- scroll position across rebuilds.
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
            k.Plate(0, 0, w, h, { bg = COL_DISPLAY })
            local txt, col = timerText(W() and W().v or v)
            draw.SimpleText("TIMER", k.Font(12, 700), s(10), h / 2, C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(txt or "", k.Font(24, 800), w - s(10), h / 2, col or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end)
    end

    if v.tutorial and v.steps then
        section(sp, k, "Your first bomb")
        local now
        for n, st in ipairs(v.steps) do
            local state = st.done and "done" or (not now and "now" or "next")
            if state == "now" then now = n end
            local row = vgui.Create("DPanel", sp)
            row:Dock(TOP)
            row:DockMargin(0, 0, s(8), s(3))
            local why = state == "now" and k.Label(row, st.why or "", 13, 400, C.text) or nil
            function row:PerformLayout(w)
                local h = s(32)
                if why then
                    why:SetPos(s(38), s(28))
                    why:SetWide(w - s(46))
                    why:InvalidateLayout(true)
                    why:SizeToContentsY()
                    h = s(34) + why:GetTall()
                end
                self:SetTall(h)
            end
            function row:Paint(w, h)
                local cur = state == "now"
                k.SetCol(cur and TUT_NOW_BG or C.row)
                surface.DrawRect(0, 0, w, h)
                if cur then k.SetCol(HINT) surface.DrawRect(0, 0, s(3), h) end
                local r = s(10)
                local cx, cy = s(18), s(16)
                if state == "done" then
                    draw.RoundedBox(r, cx - r, cy - r, r * 2, r * 2, C.good)
                    -- (a tick, drawn: not every font has the glyph)
                    surface.SetDrawColor(COL_ON_HINT)
                    for o = -1, 1 do
                        surface.DrawLine(cx - r * 0.45, cy + o, cx - r * 0.1, cy + r * 0.35 + o)
                        surface.DrawLine(cx - r * 0.1, cy + r * 0.35 + o, cx + r * 0.5, cy - r * 0.35 + o)
                    end
                elseif cur then
                    draw.RoundedBox(r, cx - r, cy - r, r * 2, r * 2, HINT)
                    draw.SimpleText(tostring(n), k.Font(12, 800), cx, cy, COL_ON_HINT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    k.SetCol(C.edgeLight)
                    surface.DrawOutlinedRect(cx - r, cy - r, r * 2, r * 2, 1)
                    draw.SimpleText(tostring(n), k.Font(12, 700), cx, cy, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                draw.SimpleText(k.Fit(st.t or "", k.Font(14, 700), w - s(46)), k.Font(14, 700), s(38), cy,
                    state == "done" and C.good or (cur and HINT or C.textDim), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end

    section(sp, k, "First inspection")
    if not v.insp then
        text(sp, k, "Hold to look the bomb over before touching anything: detonator, anti-jam, motion sensor, lid switch, charge.")
        local need = (E.Cfg("inspectTime"))
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
        local kn = E.KitName()
        section(sp, k, "No " .. kn)
        text(sp, k, "You can look, but opening and working on the bomb needs a " .. kn .. (kn == "field kit" and " (gear cabinet)." or " (ammo cabinet)."), C.warn)
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
            circle(cx, cy, r, COL_61_90_71)
            circle(cx, cy, r - 2, COL_15_26_20)
            circle(cx, cy, r * 0.33, COL_61_90_71)
            circle(cx, cy, r * 0.33 - 1, COL_15_26_20)
            local x, y = E.TiltPos(win2.v.tilt, CurTime())
            local d = math.sqrt(x * x + y * y)
            circle(cx + x * r * 0.8, cy + y * r * 0.8, s(10), d > 0.8 and COL_255_110_80 or COL_255_209_102)
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
            k.SetCol(COL_LIQUID_BAND)
            surface.DrawRect(w * l.band / 100, 1, w * 14 / 100, h - 2)
            local n = E.LiquidNeedle(l, CurTime())
            k.SetCol(COL_LIQUID_NEEDLE)
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
        btn(sp, k, "Seal the valve", function() act(14) end, { danger = true, enabled = v.kit })
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

-- E.CloseWindow(tell): close the defusal window; tell = also send
-- eod.close so the server drops us from the viewers.
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

-- E.Nudge(dx, dy): nudge the tilt bubble (-1..1 each). Moves the local
-- copy at once (same 0.14 step and ±3 cap as the server) and sends op 7.
function E.Nudge(dx, dy)
    local w = W()
    if not w or not w.v.tilt or w.overlay then return end
    w.v.tilt.nx = math.Clamp(w.v.tilt.nx + dx * 0.14, -3, 3)
    w.v.tilt.ny = math.Clamp(w.v.tilt.ny + dy * 0.14, -3, 3)
    act(7, function() net.WriteInt(dx, 3) net.WriteInt(dy, 3) end)
end

-- The panel over the window: kind "fail" (a = title, b = what happened,
-- c = manual line) or "done". Training bombs get "Same again".
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
        k.SetCol(COL_OVERLAY, 215)
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

-- Opened by the first eod.state for a bomb (the server decides who may open it).
local function openWindow(bomb)
    local k = K()
    if not k then
        Rhylib.Notify(nil, "The defusal window needs Rhy's Core's UI kit", "bad", "EOD")
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
            sub = v and (v.kit and (E.KitName() .. " ready") or ("No " .. E.KitName())) or "" })
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
        k.SetCol(COL_DISPLAY)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("PROBE", k.Font(12, 700), s(10), h / 2, C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(win.lastRead or "—", k.Font(15, 700), s(70), h / 2, COL_PROBE_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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

    -- training hint (the next step), above the board
    local hint = vgui.Create("DPanel", right)
    hint:Dock(TOP)
    hint:SetTall(0)
    hint:DockMargin(0, 0, 0, 0)
    local hide = k.Button(hint, "Hide hints", function() RunConsoleCommand("rhylib_eod_hints", "0") end, { small = true })
    hide:Dock(RIGHT)
    hide:SetWide(s(110))
    hide:DockMargin(0, s(9), s(8), s(9))
    function hint:Think()
        local cur = W()
        -- (worked out again only when the view or the setting changed)
        if cur and (cur.hintV ~= cur.v or cur.hintCv ~= cvHints:GetBool()) then
            cur.hintV, cur.hintCv = cur.v, cvHints:GetBool()
            cur.hint = hintOf(cur.v)
        end
        local h = cur and cur.hint
        local want = h and s(52) or 0
        if self:GetTall() ~= want then
            self:SetTall(want)
            self:DockMargin(0, 0, 0, want > 0 and s(6) or 0)
            right:InvalidateLayout()
        end
        hide:SetVisible(h ~= nil and not (cur.v and cur.v.tutorial))
    end
    function hint:Paint(w, h)
        local cur = W()
        local ht = cur and cur.hint
        if not ht or h < 2 then return end
        k.SetCol(HINT_BG)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(HINT)
        surface.DrawRect(0, 0, s(4), h)
        local right0 = (hide:IsVisible() and s(130) or s(10))
        draw.SimpleText("HINT · STEP " .. ht.n .. " OF " .. ht.of .. " · " .. string.upper(ht.t or ""), k.Font(12, 800), s(14), s(15), HINT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(k.Fit(ht.why or "", k.Font(13), w - s(14) - right0), k.Font(13), s(14), s(36), HINT_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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

-- eod.state: bomb, length (16 bits), compressed JSON view. Opens the
-- window on the first one.
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
    win.geo = buildGeo(v, win.geo)
    win.hint = hintOf(v)
    local key = layoutKey(v)
    if key ~= win.layout then
        win.layout = key
        buildLeft(win, K())
    end
end)

-- eod.read: wire index (5 bits), probe reading. Shown on the wire and in the log.
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

-- eod.msg: text, bad (bool). Into the log (chat when no window is open).
Net.Receive("eod.msg", function()
    local t = net.ReadString()
    local bad = net.ReadBool()
    addLog(t, bad)
    if bad then surface.PlaySound("buttons/button10.wav") end
end)

-- eod.xray: bomb, mount order (3 × 2 bits), seconds to show it.
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

-- eod.boom: bomb index (13 bits; the entity may be gone), cause key, position.
-- The window shows the fail overlay; anyone else nearby gets a chat line.
Net.Receive("eod.boom", function()
    local idx = net.ReadUInt(13)
    local cause = net.ReadString()
    local pos = net.ReadVector()
    local win = W()
    local c = E.CAUSES[cause] or E.CAUSES.gm
    if win and IsValid(win.frame) and (win.bomb:EntIndex() == idx or not IsValid(win.bomb)) then
        overlay(win, K(), "fail", c[1], c[2], c[3])
    else
        Rhylib.Notify(nil, "A bomb went off: " .. c[1], "bad", "EOD")
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
    local col = virus and COL_160_110_210 or COL_150_190_90
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
    draw.SimpleTextOutlined(txt, font, ScrW() / 2, ScrH() * 0.58, COL_AIM_HINT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, COL_AIM_EDGE)
end)

-- Menu closer (Rhylib.UI.CloseAll: Esc / pause and other menus opening
-- close this window).
Rhylib.UI.RegisterCloser("eod", function() if W() then closeWindow(true) return true end end)
