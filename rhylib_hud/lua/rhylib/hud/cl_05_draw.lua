-- Small drawing helpers shared by the HUD files.

local HUD = Rhylib.HUD
local UI = Rhylib.UI

HUD.Colors = {
    panel = Color(20, 22, 20, 170),
    track = Color(255, 255, 255, 28),
    health = Color(214, 88, 76),
    healthLow = Color(255, 60, 50),
    sim = Color(240, 200, 60),
    simLow = Color(255, 170, 40),
    armor = Color(90, 150, 255),
    fuel = Color(239, 159, 39),
    text = UI.Colors.text,
    dim = UI.Colors.textDim,
    accent = UI.Colors.accent,
    bad = UI.Colors.bad,
}

-- Holding a training gun (rhylib_training): the health readouts show sim
-- health in yellow instead. Returns hp, max, or nil (normal health).
function HUD.SimHealth(ply)
    local T = Rhylib.Training
    if not T then return nil end
    local w = ply:GetActiveWeapon()
    if not (IsValid(w) and w.Training) then return nil end
    return T.Health(ply), math.max(T.Cfg("simHealth"), 1)
end

function HUD.Scale()
    return ScrH() / 1080
end

--------------------------------------------------------------------------
-- House style (shared with the chat and the inventory): a dark plate with
-- a black outline, a faint light line along the top, small corner ticks,
-- and optionally a header band with a caps title and a coloured rule.
--------------------------------------------------------------------------

HUD.Style = {
    bg = Color(14, 16, 15, 232),
    header = Color(22, 25, 23, 250),
    edgeDark = Color(0, 0, 0, 230),
    edgeLight = Color(170, 176, 180, 70),
    tick = Color(170, 176, 180, 150),
    rule = UI.Colors.accent,
}

local cutVerts = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local fc, tc = Color(0, 0, 0), Color(150, 152, 146)
local function setCol(c, alpha)
    fc.r, fc.g, fc.b, fc.a = c.r, c.g, c.b, c.a * alpha / 255
    surface.SetDrawColor(fc)
end

-- Header band height for HUD.Frame titles.
function HUD.HeaderH()
    return math.floor(18 * HUD.Scale())
end

--[[
    HUD.Frame(x, y, w, h, opts) draws a plate in the house style.
    opts (all optional):
      alpha   0-255 for the whole frame
      title   caps text in a header band along the top
      rule    colour of the line under the header (default accent)
      cut     px cut off the top-right corner (like the chat)
      cutH    height of the cut, if it isn't square (default cut)
      bg      plate colour (default HUD.Style.bg)
      cutLeft true: cut the top-left corner instead (things on the right)
      ticks   false to leave out the corner ticks
    Returns the y where content below the header starts.
]]
function HUD.Frame(x, y, w, h, opts)
    opts = opts or {}
    local a = opts.alpha or 255
    local S = HUD.Style
    local s = HUD.Scale()
    local cut = opts.cut or 0
    local cutH = opts.cutH or cut
    local x1, y1 = x + w, y + h

    draw.NoTexture()
    setCol(opts.bg or S.bg, a)
    local left = opts.cutLeft
    if cut > 0 then
        local v = cutVerts
        if left then
            v[1].x, v[1].y = x + cut, y
            v[2].x, v[2].y = x1, y
            v[3].x, v[3].y = x1, y1
            v[4].x, v[4].y = x, y1
            v[5].x, v[5].y = x, y + cutH
        else
            v[1].x, v[1].y = x, y
            v[2].x, v[2].y = x1 - cut, y
            v[3].x, v[3].y = x1, y + cutH
            v[4].x, v[4].y = x1, y1
            v[5].x, v[5].y = x, y1
        end
        surface.DrawPoly(v)
    else
        surface.DrawRect(x, y, w, h)
    end

    local top = y
    if opts.title then
        local hh = HUD.HeaderH()
        local hx = left and x + cut or x
        setCol(S.header, a)
        surface.DrawRect(hx, y, w - cut, hh)
        local r = opts.rule or S.rule
        setCol(r, a * 0.7)
        surface.DrawRect(hx, y + hh - 1, w - cut, 1)
        tc.a = a
        draw.SimpleText(string.upper(opts.title), UI.Font(12, 700), x + math.floor(7 * s), y + hh * 0.5, tc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        top = y + hh
    end

    -- Outline and the light line along the top.
    setCol(S.edgeDark, a)
    if cut > 0 and left then
        surface.DrawLine(x + cut, y, x1 - 1, y)
        surface.DrawLine(x1 - 1, y, x1 - 1, y1 - 1)
        surface.DrawLine(x1 - 1, y1 - 1, x, y1 - 1)
        surface.DrawLine(x, y1 - 1, x, y + cutH)
        surface.DrawLine(x, y + cutH, x + cut, y)
    elseif cut > 0 then
        surface.DrawLine(x, y, x1 - cut, y)
        surface.DrawLine(x1 - cut, y, x1 - 1, y + cutH)
        surface.DrawLine(x1 - 1, y + cutH, x1 - 1, y1 - 1)
        surface.DrawLine(x1 - 1, y1 - 1, x, y1 - 1)
        surface.DrawLine(x, y1 - 1, x, y)
    else
        surface.DrawOutlinedRect(x, y, w, h)
    end
    setCol(S.edgeLight, a)
    if left then
        surface.DrawLine(x + cut, y + 1, x1 - 1, y + 1)
    else
        surface.DrawLine(x + 1, y + 1, x1 - cut, y + 1)
    end

    if opts.ticks ~= false then
        local t = math.floor(7 * s)
        setCol(S.tick, a)
        surface.DrawRect(x, y1 - 2, t, 2)
        surface.DrawRect(x, y1 - t, 2, t)
        surface.DrawRect(x1 - t, y1 - 2, t, 2)
        surface.DrawRect(x1 - 2, y1 - t, 2, t)
    end
    return top
end

-- A flat bar: dark track with a filled part. frac is 0..1.
function HUD.Bar(x, y, w, h, frac, col, alpha)
    alpha = alpha or 255
    local track = HUD.Colors.track
    surface.SetDrawColor(track.r, track.g, track.b, track.a * alpha / 255)
    surface.DrawRect(x, y, w, h)
    local fw = math.floor(w * math.Clamp(frac, 0, 1) + 0.5)
    if fw > 0 then
        surface.SetDrawColor(col.r, col.g, col.b, alpha)
        surface.DrawRect(x, y, fw, h)
    end
end

-- One reusable colour for faded draws, so nothing is allocated per frame.
local scratch = Color(0, 0, 0, 0)
local function faded(col, alpha)
    scratch.r, scratch.g, scratch.b, scratch.a = col.r, col.g, col.b, col.a * alpha / 255
    return scratch
end

-- A plain plate in the house style (no title, no ticks).
function HUD.Panel(x, y, w, h, alpha)
    HUD.Frame(x, y, w, h, { alpha = alpha, ticks = false })
end

function HUD.Text(text, size, x, y, col, ax, ay, alpha)
    if alpha and alpha < 255 then col = faded(col, alpha) end
    return draw.SimpleText(text, UI.Font(size), x, y, col, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
end

-- Distance from the screen edges for a HUD box. kind: "ammo", "hotbar"
-- or "status". While the helmet visor is showing, the ammo box sits on
-- the lower-right cheek and the hotbar low in the chin opening.
function HUD.Margins(kind)
    if HUD.VisorActive and HUD.VisorActive() then
        -- (low: the visor parts sit close to the bottom edge, like the stamina strips)
        if kind == "ammo" then return math.floor(ScrW() * 0.005), math.floor(ScrH() * 0.008) end
        if kind == "hotbar" then return 0, math.floor(ScrH() * 0.012) end
    end
    if kind == "hotbar" then return 0, math.floor(10 * HUD.Scale()) end
    local m = math.floor(24 * HUD.Scale())
    return m, m
end

-- True while something should hide the HUD (camera tool, dead, etc.).
function HUD.Hidden()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return true end
    local wep = ply:GetActiveWeapon()
    return IsValid(wep) and wep:GetClass() == "gmod_camera"
end

--[[
    Third-person corner plate: a dark plate in a bottom corner. Both
    plates are always the same fixed size, whatever they hold. The outer
    edge is a little taller than the inner edge, and the inner side
    slants down to the screen bottom.
    side: -1 = bottom left, 1 = bottom right.
    Returns the content box: x, y, w, h.
]]
local plateVerts = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local COL_PLATE = Color(14, 16, 15, 225)
local COL_PLATE_EDGE = Color(0, 0, 0, 220)
local COL_PLATE_HI = Color(170, 176, 180, 90)

HUD.PLATE_W = 300   -- content size at 1080p, same for both plates
HUD.PLATE_H = 100

function HUD.Plate(side)
    local W, H = ScrW(), ScrH()
    local s = HUD.Scale()
    local contentW, contentH = math.floor(HUD.PLATE_W * s), math.floor(HUD.PLATE_H * s)
    local pad = math.floor(14 * s)
    local innerH = contentH + pad * 2
    local drop = math.floor(H * 0.035)   -- outer edge this much taller
    local slant = math.floor(W * 0.03)   -- inner edge leans out this far at the bottom
    local innerX = pad * 2 + contentW

    local function px(x) return side < 0 and x or W - x end
    local ax, ay = px(0), H - innerH - drop
    local bx, by = px(innerX), H - innerH
    local cx, cy = px(innerX + slant), H
    local dx, dy = px(0), H

    -- Winding for surface.DrawPoly: clockwise on screen.
    if side < 0 then
        plateVerts[1].x, plateVerts[1].y = ax, ay
        plateVerts[2].x, plateVerts[2].y = bx, by
        plateVerts[3].x, plateVerts[3].y = cx, cy
        plateVerts[4].x, plateVerts[4].y = dx, dy
    else
        plateVerts[1].x, plateVerts[1].y = bx, by
        plateVerts[2].x, plateVerts[2].y = ax, ay
        plateVerts[3].x, plateVerts[3].y = dx, dy
        plateVerts[4].x, plateVerts[4].y = cx, cy
    end
    draw.NoTexture()
    surface.SetDrawColor(COL_PLATE)
    surface.DrawPoly(plateVerts)

    -- Edges along the top and the slant.
    surface.SetDrawColor(COL_PLATE_EDGE)
    surface.DrawLine(ax, ay, bx, by)
    surface.DrawLine(ax, ay - 1, bx, by - 1)
    surface.DrawLine(bx, by, cx, cy)
    surface.SetDrawColor(COL_PLATE_HI)
    surface.DrawLine(ax, ay + 1, bx, by + 1)

    -- A small tick where the top edge meets the slant, like the chat's corners.
    local t = math.floor(8 * s)
    local dir = side < 0 and -1 or 1
    surface.SetDrawColor(HUD.Style.tick)
    surface.DrawRect(math.min(bx, bx + dir * t), by - 1, t, 2)

    local x = side < 0 and pad or W - pad - contentW
    return x, H - innerH + pad, contentW, contentH
end
