--[[
    Radio on the HUD.

    Helmet visor (rhylib_hud): four channel squares between the chat and
    the chin on the left cheek (Local, Squad, Channel 1, Channel 2; the top
    one cut to the armour slope), your mic meter under the stamina strip on
    the left, the incoming meter mirrored on the right. Shapes are worked
    out once per screen size. Third person: the same parts as a small
    plate next to the chat.

    Squares: grey = not joined, dim = joined, bright = talking on it, red =
    radio muted, dark grey = radio off; a small notch marks the radio
    channel the radio key talks on. Meters: real voice levels for incoming
    voices (Player:VoiceVolume), yours too when the game reports it, else a
    level pattern while you talk. Incoming turns solid red when deafened,
    dark grey when the radio is off. Gold on a hail call.

    Also: diamond markers over squad mates, a card while a hail rings, and
    a line while you're on a call.
]]

local R = Rhylib.Radio
local UI = Rhylib.UI

local geo = { key = "" }


-- Visor: how wide the chat may be (up to the compass, or the squares when
-- the compass is off).
function R.CompassChatWidth()
    local HUD = Rhylib.HUD
    if not (HUD and HUD.Margins and HUD.VisorCheekY) then return nil end
    local g = R.VisorGeo and R.VisorGeo()
    if not g then return nil end
    return R.RadarOn() and g.chatW or g.chatWNoCompass
end

local function buildVisor(HUD)
    local W, H = ScrW(), ScrH()
    local s = H / 1080
    local _, my = HUD.Margins("ammo")
    local YB = H - my
    local key = W .. "x" .. H
    if geo.key == key then return geo end
    geo = { key = key, s = s, YB = YB }
    local barB = ((HUD.VISOR_BAR_OFFSET or 0.005) + (HUD.VISOR_BAR_THICK or 0.009)) * H + math.floor(7 * s)
    local function armourBottom(x) return HUD.VisorCheekY(x, -1) + barB end

    -- Squares: their right edge lines up with where the voice meter starts
    -- (the end of the armour bars), so the chat gets the room before them.
    local meterStart = math.floor(W * (HUD.VISOR_BAR_TO or 0.3)) + math.floor(14 * s)
    local x1 = meterStart - math.floor(14 * s)
    local x0 = x1 - math.floor(40 * s)
    local h, gap = math.floor(30 * s), math.floor(5 * s)
    local rows = {}
    for i = 1, 3 do
        local b = YB - (i - 1) * (h + gap)
        rows[i] = { b - h, b }
    end
    -- ch2 at the bottom, then ch1, squad; local on top, cut to the slope.
    geo.sq = {
        { { x = x0, y = armourBottom(x0) }, { x = x1, y = armourBottom(x1) }, { x = x1, y = rows[3][1] - gap }, { x = x0, y = rows[3][1] - gap } },
        { { x = x0, y = rows[3][1] }, { x = x1, y = rows[3][1] }, { x = x1, y = rows[3][2] }, { x = x0, y = rows[3][2] } },
        { { x = x0, y = rows[2][1] }, { x = x1, y = rows[2][1] }, { x = x1, y = rows[2][2] }, { x = x0, y = rows[2][2] } },
        { { x = x0, y = rows[1][1] }, { x = x1, y = rows[1][1] }, { x = x1, y = rows[1][2] }, { x = x0, y = rows[1][2] } },
    }
    geo.sqX0, geo.sqX1 = x0, x1

    -- Compass: just as wide as it is tall, right next to the squares; the
    -- chat gets the rest (Chat.Rect asks R.CompassChatWidth()).
    local mx = HUD.Margins("ammo")
    local cx1 = x0 - math.floor(10 * s)
    local r = math.floor((YB - armourBottom(cx1)) * 0.5)
    for _ = 1, 3 do   -- (the cheek is higher further left: settle the size)
        r = math.floor((YB - armourBottom(cx1 - r)) * 0.5)
    end
    r = math.max(r, 0)
    local cx0 = cx1 - 2 * r
    geo.radar = { x = cx1 - r, y = YB - r, r = r }
    geo.chatW = math.max(math.floor(W * 0.08), cx0 - math.floor(10 * s) - mx)          -- (compass on)
    geo.chatWNoCompass = math.max(math.floor(W * 0.08), x0 - math.floor(12 * s) - mx)   -- (compass off)

    -- Meter bars: under the stamina strip (same strip as rhylib_hud's).
    local strip = HUD.VisorStrip(-1, (HUD.VISOR_BAR_TO or 0.3) + 0.006, 0.4, HUD.VISOR_BAR_OFFSET or 0.005, HUD.VISOR_BAR_THICK or 0.009, 28)
    local inner = strip.inner
    local function topAt(x)
        if x < inner[1][1] then return armourBottom(x) end
        for i = 1, #inner - 1 do
            local a, b = inner[i], inner[i + 1]
            local lo, hi = math.min(a[1], b[1]), math.max(a[1], b[1])
            if x >= lo and x <= hi then
                local f = (x - a[1]) / math.max(b[1] - a[1], 0.001)
                return a[2] + (b[2] - a[2]) * f + math.floor(7 * s)
            end
        end
        return YB
    end
    local bw, bg = math.max(3, math.floor(8 * s)), math.max(2, math.floor(4 * s))
    -- Bars from x toward the chin (left-side coordinates; the right cheek
    -- is drawn mirrored).
    local function bars(x)
        local list = {}
        while #list < 40 do
            local top = math.max(topAt(x), topAt(x + bw))
            if YB - top < 10 * s then break end
            list[#list + 1] = { x = x, top = top }
            x = x + bw + bg
        end
        return list
    end
    -- Both meters start at the same distance from their screen edge, where
    -- the armour / health bars end (and clear of the squares on the left),
    -- so they mirror each other and stay under the stamina strip.
    geo.bars = bars(meterStart)
    geo.barsR = bars(meterStart)
    geo.bw = bw
    return geo
end

function R.VisorGeo()
    local HUD = Rhylib.HUD
    if not (HUD and HUD.Margins and HUD.VisorCheekY and HUD.VisorStrip) then return nil end
    return buildVisor(HUD)
end

--------------------------------------------------------------------------
-- Levels
--------------------------------------------------------------------------

local lvlL, lvlR = 0, 0

-- Own meter: level, colour.
local function ownLevel()
    local me = LocalPlayer()
    local talking = R.speaking[me] or R.txOn
    local col = R.COL.local_
    if R.txOn then
        if R.InCall() then col = R.COL.hail else col = R.SlotColor(R.Selected()) end
    end
    -- Real level only (a made-up pattern looked like peaking before you
    -- spoke and after you stopped).
    local target = 0
    if talking then target = math.min(1, (me:VoiceVolume() or 0) * 1.6) end
    lvlL = Lerp(math.min(1, FrameTime() * 14), lvlL, target)
    return lvlL, col
end

-- Incoming: the loudest radio voice we hear. Returns level, colour, mode.
local function inLevel()
    local mine = R.Mine()
    if mine.off then return 0, R.COL.off, "track" end
    if mine.deaf then return 0, R.COL.red, "track" end
    -- Comms jammer: the meter goes haywire.
    if R.Jammed(LocalPlayer()) then return 1, R.COL.red, "jam" end
    local best, col = 0, nil
    for p in pairs(R.speaking) do
        if IsValid(p) and p ~= LocalPlayer() and not p:IsSpeaking() then
            R.speaking[p] = nil   -- (the end event was missed)
        elseif IsValid(p) and p ~= LocalPlayer() then
            local on = R.HeardOn(p)
            if on then
                local v = math.max(p:VoiceVolume() or 0, 0.05)
                if v >= best then best, col = v, (on == 4 and R.COL.hail or R.SlotColor(on)) end
            end
        else
            if not IsValid(p) then R.speaking[p] = nil end
        end
    end
    lvlR = Lerp(math.min(1, FrameTime() * 14), lvlR, math.min(1, best * 1.6))
    return lvlR, col or R.COL.local_, "level"
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local scratch = Color(0, 0, 0)
local function setCol(c, a)
    scratch.r, scratch.g, scratch.b, scratch.a = c.r, c.g, c.b, a or 255
    surface.SetDrawColor(scratch)
end

local quad = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local function rect(x0, y0, x1, y1)
    quad[1].x, quad[1].y = x0, y0
    quad[2].x, quad[2].y = x1, y0
    quad[3].x, quad[3].y = x1, y1
    quad[4].x, quad[4].y = x0, y1
    surface.DrawPoly(quad)
end

local function outline(pts)
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        surface.DrawLine(a.x, a.y, b.x, b.y)
    end
end

-- State of square i (1 local, 2 squad, 3 ch1, 4 ch2): colour, fill alpha, bright.
local function squareState(i)
    local mine = R.Mine()
    if i == 1 then
        local talking = R.speaking[LocalPlayer()] and not R.txOn
        return R.COL.local_, talking and 240 or 70, talking
    end
    local slot = i - 1
    if mine.off then return R.COL.off, 200, false end
    if mine.muted then return R.COL.red, 150, false end
    if not R.SlotOn(slot) then return R.COL.grey, 90, false end
    local col = R.SlotColor(slot)
    local tx = R.txOn and not R.InCall() and R.Selected() == slot
    return col, tx and 240 or 70, tx
end

local LABELS = { "L", "SQ", "1", "2" }
local glowPts = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local DARK, LIGHT = Color(12, 14, 16), Color(235, 235, 235)

local function drawSquares(list, s, noNotch)
    draw.NoTexture()
    surface.SetTexture(0)
    local font = UI.Font(11, 700)
    for i, pts in ipairs(list) do
        local col, a, bright = squareState(i)
        if bright then
            -- A soft glow: the same shape (slope included), grown and faint.
            setCol(col, 45)
            local g = math.floor(3 * s)
            local gp = glowPts
            gp[1].x, gp[1].y = pts[1].x - g, pts[1].y - g
            gp[2].x, gp[2].y = pts[2].x + g, pts[2].y - g
            gp[3].x, gp[3].y = pts[3].x + g, pts[3].y + g
            gp[4].x, gp[4].y = pts[4].x - g, pts[4].y + g
            surface.DrawPoly(gp)
        end
        setCol(col, a)
        surface.DrawPoly(pts)
        setCol(col, 230)
        outline(pts)
        local cx = (pts[1].x + pts[2].x) * 0.5
        local cy = (math.max(pts[1].y, pts[2].y) + pts[3].y) * 0.5
        local tc = bright and DARK or (a >= 150 and LIGHT or col)
        draw.SimpleText(LABELS[i], font, cx, cy, tc, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        -- The radio channel the radio key talks on: a notch on the right.
        if not noNotch and i > 1 and i - 1 == R.Selected() and R.SlotOn(i - 1) and not R.Mine().off then
            local nx, ny = pts[2].x + math.floor(3 * s), cy
            local n = math.floor(4 * s)
            setCol(col, 230)
            surface.DrawPoly({ { x = nx, y = ny - n }, { x = nx + n, y = ny }, { x = nx, y = ny + n } })
        end
    end
end

local function barLevel(i, level, t)
    local f = 0.55 + 0.45 * math.abs(math.sin(t * (5 + i * 1.7) + i * 2.1))
    return math.Clamp(level * f * 1.25, 0.04, 1)
end

-- Jammed meter: random bar heights, re-rolled ~20 times a second, with
-- the odd full spike and a red/white flicker.
local jamH, jamAt, jamFlash = {}, 0, false
local JAM_WHITE = Color(240, 235, 230)
local function jamRoll()
    local now = RealTime()
    if now < jamAt then return end
    jamAt = now + math.Rand(0.03, 0.07)
    jamFlash = math.random() < 0.18
    local spike = math.random() < 0.25
    for i = 1, 64 do
        jamH[i] = (spike and math.random() < 0.3) and 1 or math.Rand(0.04, 0.85)
    end
end
local function jamBar(i) return jamH[(i - 1) % 64 + 1] or 0.5 end
local function jamCol(i, col) return (jamFlash and i % 2 == 0) and JAM_WHITE or col end

local function drawMeter(bars, bw, YB, side, level, col, mode)
    local W = ScrW()
    local t = RealTime()
    draw.NoTexture()
    if mode == "jam" then jamRoll() end
    for i, b in ipairs(bars) do
        local x = side < 0 and b.x or (W - b.x - bw)
        local h = YB - b.top
        if mode == "jam" then
            setCol(color_white, 14)
            rect(x, b.top, x + bw, YB)
            local bh = math.max(2, h * jamBar(i))
            setCol(jamCol(i, col), math.random(150, 240))
            rect(x, YB - bh, x + bw, YB)
        elseif mode == "track" then
            setCol(col, 150)
            rect(x, b.top, x + bw, YB)
        else
            setCol(color_white, 14)
            rect(x, b.top, x + bw, YB)
            local bh = math.max(2, h * barLevel(i, level, t))
            setCol(col, level > 0.02 and 230 or 110)
            rect(x, YB - bh, x + bw, YB)
        end
    end
end

local function drawVisor(HUD)
    local g = buildVisor(HUD)
    drawSquares(g.sq, g.s)
    local l, lc = ownLevel()
    drawMeter(g.bars, g.bw, g.YB, -1, l, lc, "level")
    local r, rc, mode = inLevel()
    drawMeter(g.barsR, g.bw, g.YB, 1, r, rc, mode)
    if R.RadarOn() and g.radar.r > 20 then R.DrawRadar(g.radar.x, g.radar.y, g.radar.r, false) end
end

-- Third person: a panel at the right edge. Hidden while the radio is off.
local plateLabels = { "LOCAL", "SQUAD", "CH 1", "CH 2" }
local function drawPlate()
    if R.Mine().off then return end
    local W, H = ScrW(), ScrH()
    local s = H / 1080
    local pad = math.floor(8 * s)
    local w = math.floor(210 * s)
    local x, y = W - w - math.floor(24 * s), math.floor(H * 0.56)
    local q, gap = math.floor(22 * s), math.floor(5 * s)
    local mh = math.floor(30 * s)
    local radar = R.RadarOn()
    local rr = math.floor((w - pad * 2) * 0.5)
    local h = pad * 3 + q + mh + (radar and (rr * 2 + pad) or 0)
    -- Plate in the house style.
    surface.SetDrawColor(14, 16, 15, 225)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(0, 0, 0, 230)
    surface.DrawOutlinedRect(x, y, w, h)
    surface.SetDrawColor(170, 176, 180, 70)
    surface.DrawLine(x + 1, y + 1, x + w - 1, y + 1)
    -- Squares in a row, the selected channel's name after them.
    local list = {}
    for i = 1, 4 do
        local sx = x + pad + (i - 1) * (q + gap)
        list[i] = { { x = sx, y = y + pad }, { x = sx + q, y = y + pad }, { x = sx + q, y = y + pad + q }, { x = sx, y = y + pad + q } }
    end
    drawSquares(list, s, true)
    local nameX = x + pad + 4 * (q + gap) + math.floor(4 * s)
    local slot = R.Selected()
    local label = R.InCall() and "HAIL" or (R.SlotOn(slot) and string.upper(R.SlotName(slot)) or "NO CHANNEL")
    draw.SimpleText(label, UI.Font(11, 700), nameX, y + pad + q * 0.5, R.InCall() and R.COL.hail or (R.SlotOn(slot) and R.SlotColor(slot) or R.COL.grey),
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    -- Two meters side by side: yours, incoming.
    local my = y + pad * 2 + q
    local half = math.floor((w - pad * 3) * 0.5)
    local bw, bg = math.max(2, math.floor(5 * s)), math.max(1, math.floor(3 * s))
    local nb = math.floor((half + bg) / (bw + bg))
    local function meter(mx, level, col, mode)
        local t = RealTime()
        if mode == "jam" then jamRoll() end
        for i = 1, nb do
            local bx = mx + (i - 1) * (bw + bg)
            if mode == "jam" then
                setCol(color_white, 14)
                rect(bx, my, bx + bw, my + mh)
                local bh = math.max(2, mh * jamBar(i))
                setCol(jamCol(i, col), math.random(150, 240))
                rect(bx, my + mh - bh, bx + bw, my + mh)
            elseif mode == "track" then
                setCol(col, 150)
                rect(bx, my, bx + bw, my + mh)
            else
                setCol(color_white, 14)
                rect(bx, my, bx + bw, my + mh)
                local bh = math.max(2, mh * barLevel(i, level, t))
                setCol(col, level > 0.02 and 230 or 110)
                rect(bx, my + mh - bh, bx + bw, my + mh)
            end
        end
    end
    draw.NoTexture()
    local l, lc = ownLevel()
    meter(x + pad, l, lc, "level")
    local r, rc, mode = inLevel()
    meter(x + pad * 2 + half, r, rc, mode)
    if radar then R.DrawRadar(x + math.floor(w * 0.5), my + mh + pad + rr, rr, false) end
end

--------------------------------------------------------------------------
-- Squad markers
--------------------------------------------------------------------------

local UNITS_TO_M = 0.01905

function R.MatePos(p)
    if not p:IsDormant() then return p:GetPos() end
    local m = R.mates[p:EntIndex()]
    if m and CurTime() - m.at < 3 then return m.pos end
end

--------------------------------------------------------------------------
-- Compass: squad mates around you, you in the middle facing up, 40 m to
-- the rim (the visor's left cheek, the third-person panel, the page).
--------------------------------------------------------------------------

R.RADAR_M = 40
local UNITS_PER_M = 1 / 0.01905
local discs = {}
local function disc(r)
    local d = discs[r]
    if d then return d end
    d = {}
    for i = 0, 31 do
        local a = i / 32 * math.pi * 2
        d[#d + 1] = { math.cos(a) * r, math.sin(a) * r }
    end
    discs[r] = d
    return d
end
local discPts = {}
for i = 1, 32 do discPts[i] = { x = 0, y = 0 } end

-- Jammer status on the compass (owner 2026-10-07): inside a jammer the
-- compass "desyncs" (horizontal slices slide back and forth, pop out and
-- jump, with ghost copies and glitch bars) and a red JAMMED blinks 3
-- times, then stays; leaving it a green UPLINK ACTIVE blinks 3 times.
local BLINKS, BLINK = 3, 0.5
local JAM_RED, UPLINK_GREEN = Color(235, 70, 60), Color(110, 220, 120)
local function blinkOn(t) return (t % BLINK) < BLINK * 0.6 end

local function drawBanner(cx, cy, r, lines, col)
    local font = UI.Font(r >= 60 and 14 or (r >= 42 and 11 or 9), 800)
    surface.SetFont(font)
    local w, h = 0, 0
    for _, l in ipairs(lines) do
        local lw, lh = surface.GetTextSize(l)
        w, h = math.max(w, lw), h + lh
    end
    local pad = 4
    draw.NoTexture()
    surface.SetDrawColor(8, 10, 12, 220)
    surface.DrawRect(cx - w * 0.5 - pad, cy - h * 0.5 - pad * 0.5, w + pad * 2, h + pad)
    surface.SetDrawColor(col.r, col.g, col.b, 200)
    surface.DrawOutlinedRect(cx - w * 0.5 - pad, cy - h * 0.5 - pad * 0.5, w + pad * 2, h + pad)
    local y = cy - h * 0.5
    for _, l in ipairs(lines) do
        local _, lh = surface.GetTextSize(l)
        draw.SimpleText(l, font, cx, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        y = y + lh
    end
end

-- The JAMMED / RECONNECTING / UPLINK ACTIVE banner.
local RECON_AMBER = Color(235, 170, 60)
local function jamBanner(cx, cy, r, jammed)
    local b = R.jamBanner
    if jammed and R.Reconnecting(LocalPlayer()) then
        -- (a slow pulse, not a blink: it stays up until the link is back)
        local a = 0.65 + 0.35 * math.abs(math.sin(RealTime() * 2.5))
        RECON_AMBER.a = math.floor(255 * a)
        drawBanner(cx, cy, r, { "RECONNECTING" }, RECON_AMBER)
        return
    end
    if jammed then
        local t = b and b.jammed and (RealTime() - b.at) or 0
        if t >= BLINKS * BLINK or blinkOn(t) then drawBanner(cx, cy, r, { "JAMMED" }, JAM_RED) end
        return
    end
    if b and not b.jammed then
        local t = RealTime() - b.at
        if t < BLINKS * BLINK then
            if blinkOn(t) then drawBanner(cx, cy, r, { "UPLINK", "ACTIVE" }, UPLINK_GREEN) end
        else
            R.jamBanner = nil
        end
    end
end

-- Desync slices. One shared state: every compass on screen glitches alike.
-- (sizes are fractions of the radius, so compasses of any size share it)
local DS = { bands = {}, bars = {}, rebuildAt = 0, barsAt = 0, last = 0 }
local BAR_COLS = { Color(240, 240, 240), Color(235, 70, 60), Color(90, 200, 220) }

local function rebuildBands()
    local bands, y = {}, -1.02
    while y < 1.02 do
        local h = math.Rand(0.07, 0.3)
        bands[#bands + 1] = { y = y, h = h, off = 0, target = 0, nextAt = 0, gone = false, ghost = false }
        y = y + h
    end
    DS.bands = bands
end

local function updateDesync(k)
    local now = RealTime()
    local dt = math.Clamp(now - DS.last, 0, 0.1)
    DS.last = now
    -- the slicing itself pops to a new pattern now and then
    if now >= DS.rebuildAt then
        rebuildBands()
        DS.rebuildAt = now + math.Rand(0.3, 0.9)
    end
    local maxOff = 0.32
    for _, b in ipairs(DS.bands) do
        if now >= b.nextAt then
            b.nextAt = now + math.Rand(0.05, 0.3)
            local roll = math.random()
            if roll < 0.2 then
                b.target = 0                                   -- slide back in line
            elseif roll < 0.7 then
                b.target = math.Rand(-1, 1) * maxOff           -- slide out
            elseif roll < 0.85 then
                b.target = math.Rand(-1, 1) * maxOff * 1.4     -- jump
                b.off = b.target
            end
            b.gone = math.random() < 0.1 * k                   -- pop out
            b.ghost = not b.gone and math.random() < 0.18 * k  -- doubled
        end
        b.off = Lerp(math.min(1, dt * 18), b.off, b.target)
    end
    if now >= DS.barsAt then
        DS.barsAt = now + math.Rand(0.06, 0.16)
        DS.bars = {}
        for i = 1, math.random(0, math.Round(4 * k)) do
            DS.bars[i] = {
                y = math.Rand(-1, 1), h = math.random(1, 2),
                x = math.Rand(-1.1, 0.4), w = math.Rand(0.4, 1.5),
                col = BAR_COLS[math.random(#BAR_COLS)], a = math.random(60, 150),
            }
        end
    end
end

-- Draws drawCore(x, ...) sliced into the bands. ox/oy = screen offset of
-- the drawing origin (panels), since the scissor rect is in screen pixels.
-- k = strength 0-1 (the fringe outside a jammer, fading while reconnecting).
local function drawDesync(drawCore, cx, cy, r, names, ox, oy, k)
    ox, oy = ox or 0, oy or 0
    updateDesync(k)
    local x1, x2 = math.floor(ox + cx - r * 1.2), math.ceil(ox + cx + r * 1.2)
    for _, b in ipairs(DS.bands) do
        local by, bh = math.floor(cy + b.y * r), math.max(1, math.ceil(b.h * r))
        local off = b.off * r * k
        if b.gone then
            render.SetScissorRect(0, 0, 0, 0, false)
            draw.NoTexture()
            surface.SetDrawColor(6, 8, 10, 150)
            surface.DrawRect(cx - r, by, r * 2, bh)
        else
            render.SetScissorRect(x1, oy + by, x2, oy + by + bh, true)
            drawCore(cx + off, cy, r, names)
            if b.ghost then
                surface.SetAlphaMultiplier(0.35)
                drawCore(cx + off + (off >= 0 and -1 or 1) * r * 0.14, cy, r, names)
                surface.SetAlphaMultiplier(1)
            end
        end
    end
    render.SetScissorRect(0, 0, 0, 0, false)
    draw.NoTexture()
    for _, g in ipairs(DS.bars) do
        surface.SetDrawColor(g.col.r, g.col.g, g.col.b, g.a)
        surface.DrawRect(cx + g.x * r, cy + g.y * r, g.w * r, g.h)
    end
end

local function drawCore(cx, cy, r, names)
    local s = ScrH() / 1080
    draw.NoTexture()
    local d = disc(r)
    for i = 1, 32 do discPts[i].x, discPts[i].y = cx + d[i][1], cy + d[i][2] end
    surface.SetDrawColor(10, 13, 15, 190)
    surface.DrawPoly(discPts)
    -- Rings: the rim and half way.
    local d2 = disc(math.floor(r * 0.5))
    for i = 1, 32 do
        local j = i % 32 + 1
        surface.SetDrawColor(110, 120, 128, 150)
        surface.DrawLine(cx + d[i][1], cy + d[i][2], cx + d[j][1], cy + d[j][2])
        surface.SetDrawColor(80, 90, 98, 90)
        surface.DrawLine(cx + d2[i][1], cy + d2[i][2], cx + d2[j][1], cy + d2[j][2])
    end
    local me = LocalPlayer()
    local yaw = math.rad(me:EyeAngles().y)
    local fx, fy = math.cos(yaw), math.sin(yaw)
    -- North (+y) on the rim.
    local nx, ny = -fx, -fy
    draw.SimpleText("N", UI.Font(11, 700), cx + nx * (r - math.floor(8 * s)), cy + ny * (r - math.floor(8 * s)), Color(200, 206, 210, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.NoTexture()
    -- You.
    local a = math.max(4, math.floor(r * 0.09))
    setCol(R.COL.ch1, 240)
    surface.DrawPoly({ { x = cx, y = cy - a }, { x = cx + a * 0.75, y = cy + a }, { x = cx, y = cy + a * 0.45 }, { x = cx - a * 0.75, y = cy + a } })
    local sq = R.SquadOf(me)
    if sq == 0 then return end
    local mp = me:GetPos()
    local k = r / (R.RADAR_M * UNITS_PER_M)
    local font = UI.Font(11, 600)
    for _, p in ipairs(player.GetAll()) do
        if p ~= me and p:Alive() and R.SquadOf(p) == sq then
            local pos = R.MatePos(p)
            if pos then
                local dx, dy = pos.x - mp.x, pos.y - mp.y
                local fwd = dx * fx + dy * fy
                local right = dx * fy - dy * fx
                local sx, sy = right * k, -fwd * k
                local len = math.sqrt(sx * sx + sy * sy)
                local edge = len > r - 4
                if edge then sx, sy = sx / len * (r - 4), sy / len * (r - 4) end
                local px, py = cx + sx, cy + sy
                local m = math.max(3, math.floor(r * (edge and 0.045 or 0.065)))
                draw.NoTexture()
                setCol(R.IsLeader(p) and R.COL.hail or R.COL.squad, edge and 150 or 240)
                surface.DrawPoly({ { x = px, y = py - m }, { x = px + m, y = py }, { x = px, y = py + m }, { x = px - m, y = py } })
                if names then
                    draw.SimpleText(p:Nick(), font, px + m + 3, py, Color(220, 225, 228, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end
        end
    end
end

-- ox, oy: screen position of the drawing origin when drawn inside a panel.
-- Shown jamming strength, eased so the fringe steps and the reconnect
-- fade look smooth (once per frame, shared by every compass).
local shownK, shownFrame = 0, -1
function R.JamShown()
    local f = FrameNumber()
    if f ~= shownFrame then
        shownFrame = f
        local target = R.JamLevel(LocalPlayer())
        shownK = Lerp(math.min(1, FrameTime() * 4), shownK, target)
        if target >= 1 then shownK = 1 end
        if shownK < 0.005 then shownK = 0 end
    end
    return shownK
end

function R.DrawRadar(cx, cy, r, names, ox, oy)
    local jammed = R.Jammed(LocalPlayer())
    local k = R.JamShown()
    if k > 0.03 then
        drawDesync(drawCore, cx, cy, r, names, ox, oy, k)
    else
        drawCore(cx, cy, r, names)
    end
    jamBanner(cx, cy, r, jammed)
end

local function drawMarkers(s)
    draw.NoTexture()
    local me = LocalPlayer()
    local sq = R.SquadOf(me)
    if sq == 0 then return end
    local eye = me:EyePos()
    local font = UI.Font(12, 600)
    for _, p in ipairs(player.GetAll()) do
        if p ~= me and p:Alive() and R.SquadOf(p) == sq then
            local pos = R.MatePos(p)
            if pos then
                local sc = (pos + Vector(0, 0, 82)):ToScreen()
                if sc.visible then
                    local dist = eye:Distance(pos)
                    local a = dist < 120 and 90 or 220
                    local d = math.floor(6 * s)
                    local col = R.IsLeader(p) and R.COL.hail or R.COL.squad
                    setCol(Color(0, 0, 0), a * 0.6)
                    surface.DrawPoly({ { x = sc.x, y = sc.y - d - 1 }, { x = sc.x + d + 1, y = sc.y }, { x = sc.x, y = sc.y + d + 1 }, { x = sc.x - d - 1, y = sc.y } })
                    setCol(col, a)
                    surface.DrawPoly({ { x = sc.x, y = sc.y - d }, { x = sc.x + d, y = sc.y }, { x = sc.x, y = sc.y + d }, { x = sc.x - d, y = sc.y } })
                    local is = math.floor(14 * s)
                    local tagsW = (R.IsLeader(p) and is * 1.25 or 0) + (R.IsRO(p) and is * 1.25 or 0) + is
                    R.DrawTags(p, sc.x - tagsW * 0.5, sc.y - d - is - math.floor(4 * s), is, Color(230, 233, 235, a))
                    draw.SimpleTextOutlined(p:Nick() .. "  " .. math.floor(dist * UNITS_TO_M) .. " m", font, sc.x, sc.y + d + math.floor(3 * s),
                        Color(225, 230, 232, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, a * 0.6))
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- Hail card and call line
--------------------------------------------------------------------------

local function clock(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function drawHail(s)
    local W, H = ScrW(), ScrH()
    local y = math.floor(H * 0.13)
    local key = string.upper(GetConVarString("rhylib_radio_menukey"))
    for _, r in pairs(R.rings) do
        local w, h = math.floor(380 * s), math.floor(54 * s)
        local x = math.floor((W - w) * 0.5)
        local pulse = 0.6 + 0.4 * math.abs(math.sin(RealTime() * 4))
        surface.SetDrawColor(18, 16, 10, 235)
        surface.DrawRect(x, y, w, h)
        setCol(R.COL.hail, 255 * pulse)
        surface.DrawOutlinedRect(x, y, w, h, math.max(1, math.floor(2 * s)))
        R.DrawIcon("hail", x + math.floor(10 * s), y + math.floor(12 * s), math.floor(30 * s), R.COL.hail)
        local who = IsValid(r.caller) and r.caller:Nick() or "?"
        draw.SimpleText("HAIL  ·  " .. r.label, UI.Font(14, 700), x + math.floor(50 * s), y + math.floor(17 * s), R.COL.hail, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(who .. "  ·  answer on the Radio page (" .. key .. ")", UI.Font(13), x + math.floor(50 * s), y + math.floor(37 * s), Color(220, 222, 224), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        y = y + h + math.floor(6 * s)
    end
    local c = R.call
    if c then
        local live = #c.members >= 2
        local text = live and ("ON HAIL  ·  " .. c.label .. "  ·  " .. clock(CurTime() - (c.started or CurTime())))
            or ("HAILING  ·  " .. (c.ringing > 0 and "ringing" or "waiting"))
        draw.SimpleTextOutlined(text, UI.Font(13, 700), W * 0.5, y + math.floor(8 * s), R.COL.hail, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 160))
    end
end

Rhylib.Hook.Add("HUDPaint", "radio.hud", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep:GetClass() == "gmod_camera" then return end
    local s = ScrH() / 1080
    local HUD = Rhylib.HUD
    if HUD and HUD.VisorActive and HUD.VisorActive() and HUD.VisorStrip and HUD.VisorCheekY then
        drawVisor(HUD)
    else
        drawPlate()
    end
    drawMarkers(s)
    drawHail(s)
end)
