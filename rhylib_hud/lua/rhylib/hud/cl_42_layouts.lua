--[[
    First-person (helmet visor) layouts that draw the hotbar and the ammo
    together, on the right cheek. An admin picks one for the server with
    rhylib_hud_layout (sv_20_layout.lua):

      f4  Ammo strip. A row of hotbar tiles along the bottom, as long as
          the health bars; their tops lean a little with the cheek. Right
          on top of them a line of round ticks with one small row of info
          under it (weapon, mode, spare mags left, shot count right).
      f5  Curve tiles. Slots 1-4 are tiles whose tops follow the cheek;
          slots 2-4 reach down to a strip with the overflow and backpack
          slots. Under them a wide ammo plate, as wide as the tiles.

    The hotbar fades like before; the ammo parts never fade.
    Shapes are drawn as strips of trapezoids with vertical sides, which
    are always convex, so surface.DrawPoly draws them safely.
]]

local HUD = Rhylib.HUD
local UI = Rhylib.UI

local COL_PLATE = Color(28, 32, 31, 236)
local COL_EDGE = Color(0, 0, 0, 215)
local COL_HI = Color(200, 206, 210, 50)
local COL_DIVIDER = Color(170, 176, 180, 60)
local COL_TICK_ON = Color(210, 214, 206)
local COL_TICK_OFF = Color(255, 255, 255, 30)
local COL_LABEL = Color(165, 168, 160)

local function inventory()
    local Inv = Rhylib.Inventory
    return Inv and Inv.HotbarItem and Rhylib.Items and Inv or nil
end

-- True while one of these layouts is drawing the ammo (cl_30_ammo.lua skips).
function HUD.LayoutDrawsAmmo()
    return HUD.VisorActive and HUD.VisorActive() and inventory() ~= nil and HUD.VisorLayout() ~= "console"
end

--------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------

-- The right cheek edge's y at x, cached per pixel column and screen size.
local curveCache, cacheW, cacheH = {}, 0, 0
local function cheekY(x)
    local W, H = ScrW(), ScrH()
    if W ~= cacheW or H ~= cacheH then
        curveCache, cacheW, cacheH = {}, W, H
    end
    local xi = math.floor(x)
    local y = curveCache[xi]
    if not y then
        y = HUD.VisorCheekY and HUD.VisorCheekY(xi, 1) or H * 0.8
        curveCache[xi] = y
    end
    return y
end

local tcol = Color(0, 0, 0)
local function txt(text, size, weight, x, y, col, ax, a)
    tcol.r, tcol.g, tcol.b, tcol.a = col.r, col.g, col.b, (col.a or 255) * a / 255
    return draw.SimpleText(text, UI.Font(size, weight), x, y, tcol, ax or TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

local function setCol(col, a)
    surface.SetDrawColor(col.r, col.g, col.b, (col.a or 255) * a / 255)
end

local function fit(text, size, weight, maxW)
    surface.SetFont(UI.Font(size, weight))
    if surface.GetTextSize(text) <= maxW then return text end
    while #text > 1 and surface.GetTextSize(text .. "…") > maxW do text = string.sub(text, 1, -2) end
    return text .. "…"
end

local quad = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
-- A trapezoid with vertical sides: top from (x0, t0) to (x1, t1), flat bottom at yb.
local function trap(x0, t0, x1, t1, yb)
    quad[1].x, quad[1].y = x0, t0
    quad[2].x, quad[2].y = x1, t1
    quad[3].x, quad[3].y = x1, yb
    quad[4].x, quad[4].y = x0, yb
    surface.DrawPoly(quad)
end

--[[
    A tile: flat bottom at yb, top following topf(x) in `steps` pieces.
    opts: active, empty, alpha.
]]
local function tile(x0, x1, topf, yb, steps, active, empty, a)
    local C = HUD.Colors
    draw.NoTexture()
    local fa = empty and a * 0.4 or a
    local px, pt = x0, topf(x0)
    setCol(COL_PLATE, fa)
    for i = 1, steps do
        local nx = x0 + (x1 - x0) * i / steps
        local nt = topf(nx)
        trap(px, pt, nx, nt, yb)
        px, pt = nx, nt
    end
    if active then
        setCol(C.accent, a * 0.16)
        px, pt = x0, topf(x0)
        for i = 1, steps do
            local nx = x0 + (x1 - x0) * i / steps
            local nt = topf(nx)
            trap(px, pt, nx, nt, yb)
            px, pt = nx, nt
        end
    end
    -- Outline, then the top line (accent when active, else a faint light line).
    setCol(COL_EDGE, empty and a * 0.6 or a)
    surface.DrawLine(x0, topf(x0), x0, yb)
    surface.DrawLine(x1 - 1, topf(x1), x1 - 1, yb)
    surface.DrawLine(x0, yb - 1, x1, yb - 1)
    px, pt = x0, topf(x0)
    for i = 1, steps do
        local nx = x0 + (x1 - x0) * i / steps
        local nt = topf(nx)
        surface.DrawLine(px, pt, nx, nt)
        if active then
            setCol(C.accent, a)
            surface.DrawLine(px, pt + 1, nx, nt + 1)
            surface.DrawLine(px, pt + 2, nx, nt + 2)
        else
            setCol(COL_HI, a)
            surface.DrawLine(px + 1, pt + 1, nx - 1, nt + 1)
        end
        setCol(COL_EDGE, empty and a * 0.6 or a)
        px, pt = nx, nt
    end
end

-- A flat plate in the same look (no cut).
local function plate(x, y, w, h, a)
    draw.NoTexture()
    setCol(COL_PLATE, a)
    surface.DrawRect(x, y, w, h)
    setCol(COL_EDGE, a)
    surface.DrawOutlinedRect(x, y, w, h)
    setCol(COL_HI, a)
    surface.DrawLine(x + 1, y + 1, x + w - 1, y + 1)
end

-- Spare magazine pips, filled; at most `max`, then "+n".
local function pips(x, y, n, w, h, gap, a, max)
    max = max or 6
    setCol(COL_TICK_ON, a)
    for i = 1, math.min(n, max) do
        surface.DrawRect(x + (i - 1) * (w + gap), y, w, h)
    end
    local used = math.min(n, max) * (w + gap)
    if n > max then
        used = used + txt("+" .. (n - max), 11, 700, x + used + 1, y + h * 0.5, COL_TICK_ON, nil, a) + gap
    end
    return used
end

-- How many round ticks to draw, and how many are lit.
local function tickCounts(ai)
    if ai.unarmed or ai.noAmmo or not ai.maxClip or ai.maxClip <= 0 then return 30, 0 end
    if ai.maxClip <= 60 then return ai.maxClip, ai.clip end
    return 60, math.ceil(ai.clip / ai.maxClip * 60)
end

local function clipColour(ai)
    local C = HUD.Colors
    if not ai.clip then return C.dim end
    if ai.clip == 0 then return C.bad end
    if ai.maxClip and ai.maxClip > 0 and ai.clip / ai.maxClip <= 0.2 then return C.fuel end
    return C.text
end

local function tickColour(ai)
    local C = HUD.Colors
    if ai.maxClip and ai.maxClip > 0 and ai.clip and ai.clip / ai.maxClip <= 0.2 then return C.fuel end
    return COL_TICK_ON
end

-- The hotbar entries in display order: slots 1-4, then the backpack
-- slots and the overflow slot (each item carries its group).
local items = {}
local function collect(entries)
    for k = 1, #items do items[k] = nil end
    for i = 1, 4 do
        if entries[i] then items[#items + 1] = { e = entries[i], group = "main" } end
    end
    for i = 5, 6 do
        local e = entries[i]
        if e and not e.overflow then items[#items + 1] = { e = e, group = "pack" } end
    end
    local last = entries[#entries]
    if last and last.overflow then items[#items + 1] = { e = last, group = "over" } end
    return items
end

local function isActive(e, active)
    if e.wep ~= nil and e.wep == active then return true end
    if e.overflow then
        for _, w in ipairs(e.overflow) do
            if w == active then return true end
        end
    end
    return false
end

local function overflowExtra(e)
    return e.overflow and #e.overflow > 1 and ("+" .. (#e.overflow - 1)) or e.sub
end

--------------------------------------------------------------------------
-- F4: ammo strip on an even hotbar row
--------------------------------------------------------------------------

local function drawF4(entries, active, alpha, s, ai)
    local C = HUD.Colors
    local W, H = ScrW(), ScrH()
    local X0 = math.floor(W * (1 - (HUD.VISOR_BAR_TO or 0.3)))
    local X1 = math.floor(W * (1 - (HUD.VISOR_BAR_FROM or 0.005)))
    local _, my = HUD.Margins("ammo")
    local YB = H - my
    -- Tile tops: one level line, as low as the left end needs.
    local level = math.floor(YB - (50 * s + 0.12 * (YB - cheekY(X0))))
    local function top() return level end

    -- Hotbar tiles.
    local list = collect(entries)
    local n = #list
    local groups = 0
    local prev
    for _, it in ipairs(list) do
        if it.group ~= prev then groups = groups + 1 end
        prev = it.group
    end
    local gap, ggap = math.floor(5 * s), math.floor(12 * s)
    local tw = (X1 - X0 - (n - groups) * gap - (groups - 1) * ggap) / n
    local x = X0
    prev = nil
    local r = HUD.HotbarRect
    r.x, r.y, r.w, r.h, r.frame = X0, math.floor(top(X0)), X1 - X0, YB - math.floor(top(X0)), FrameNumber()
    for _, it in ipairs(list) do
        if prev and it.group ~= prev then x = x + ggap - gap end
        local e = it.e
        local act = isActive(e, active)
        local a = act and math.min(255, alpha * 2) or alpha
        local x0, x1 = math.floor(x), math.floor(x + tw)
        tile(x0, x1, top, YB, 1, act, e.empty, a)
        local pad = math.floor(7 * s)
        if it.group ~= prev and it.group ~= "main" then
            txt(it.group == "pack" and "BACKPACK" or "OTHER", 9, 700, x0 + pad, YB - math.floor(53 * s), COL_LABEL, nil, a * 0.8)
        end
        local kw = txt(tostring(e.key), 13, 700, x0 + pad, YB - math.floor(36 * s), act and C.accent or C.dim, nil, a)
        local extra = overflowExtra(e)
        if extra then txt(extra, 10, 400, x1 - math.floor(6 * s), YB - math.floor(36 * s), C.dim, TEXT_ALIGN_RIGHT, a) end
        if e.empty then
            txt("Empty", 12, 400, x0 + pad, YB - math.floor(16 * s), C.dim, nil, a * 0.5)
        else
            local wgt = act and 500 or 400
            txt(fit(e.name, 12, wgt, x1 - x0 - pad - 4 * s), 12, wgt, x0 + pad, YB - math.floor(16 * s), act and C.text or C.dim, nil, a)
        end
        prev = it.group
        x = x + tw + gap
    end

    -- Round ticks right on top of the tiles, in a straight line as long
    -- as the health bars.
    local N, lit = tickCounts(ai)
    local tg = math.max(1, math.floor(2 * s))
    local tkw = (X1 - X0 - (N - 1) * tg) / N
    local th = math.max(3, math.floor(7 * s))
    local on = tickColour(ai)
    draw.NoTexture()
    for i = 1, N do
        local tx = X0 + (i - 1) * (tkw + tg)
        local yb = top(tx + tkw * 0.5) - math.floor(6 * s)
        setCol(i <= lit and on or COL_TICK_OFF, 255)
        surface.DrawRect(math.floor(tx), math.floor(yb - th), math.max(1, math.floor(tx + tkw) - math.floor(tx)), th)
    end

    -- Power cell (cell weapons): a level bar above the ticks, coloured like
    -- the third-person cell bar.
    local above = math.floor(6 * s) + th
    if ai.cell then
        local ch = math.max(3, math.floor(5 * s))
        local cyb = level - above - math.floor(5 * s)
        local lowCell = ai.cell < Rhylib.Config.Get("weapons", "lowCellThreshold")
        HUD.Bar(X0, cyb - ch, X1 - X0, ch, ai.cell, lowCell and C.bad or C.armor)
        above = above + math.floor(5 * s) + ch
    end

    -- One row of info above the bars.
    local function rowY() return level - above - math.floor(13 * s) end
    local lx = X0
    local w1 = txt(string.upper(ai.name or ""), 14, 700, lx, rowY(lx + 30 * s), C.dim, nil, 255)
    lx = lx + w1 + math.floor(12 * s)
    if ai.mode then
        local w2 = txt(ai.mode, 14, 700, lx, rowY(lx + 15 * s), ai.safe and C.fuel or C.accent, nil, 255)
        lx = lx + w2 + math.floor(14 * s)
    end
    if ai.magShort then
        local ph = math.floor(14 * s)
        local py = math.floor(rowY(lx) - ph * 0.5)
        lx = lx + pips(lx, py, ai.spare or 0, math.max(4, math.floor(7 * s)), ph, math.max(2, math.floor(3 * s)), 255)
        local w3 = txt(string.upper(ai.magShort), 13, 700, lx + math.floor(5 * s), rowY(lx), (ai.spare or 0) > 0 and C.dim or C.bad, nil, 255)
        lx = lx + math.floor(5 * s) + w3 + math.floor(14 * s)
    end
    if ai.others then
        lx = lx + txt(ai.others, 13, 400, lx, rowY(lx), C.dim, nil, 255) + math.floor(14 * s)
    end
    if ai.cell then
        local low = ai.cell < Rhylib.Config.Get("weapons", "lowCellThreshold")
        txt(string.format("CELL %d%%  %d spare", math.ceil(ai.cell * 100), ai.cells or 0), 13, 700, lx, rowY(lx), low and C.bad or C.dim, nil, 255)
    end

    -- Shot count at the right end, on the same row.
    local ry = rowY(X1 - 30 * s) - math.floor(1 * s)
    if ai.unarmed or ai.noAmmo then
        txt(ai.unarmed and "UNARMED" or "—", 15, 700, X1, ry, C.dim, TEXT_ALIGN_RIGHT, 255)
    else
        local mw = txt("/ " .. (ai.maxClip or 0), 14, 400, X1, ry + math.floor(2 * s), C.dim, TEXT_ALIGN_RIGHT, 255)
        txt(tostring(ai.clip or 0), 22, 500, X1 - mw - math.floor(5 * s), ry, clipColour(ai), TEXT_ALIGN_RIGHT, 255)
    end
end

--------------------------------------------------------------------------
-- F5: curve tiles over a wide ammo plate
--------------------------------------------------------------------------

local function drawF5(entries, active, alpha, s, ai)
    local C = HUD.Colors
    local W, H = ScrW(), ScrH()
    local _, my = HUD.Margins("ammo")
    local YB = H - my
    local off, th = math.floor(26 * s), math.floor(40 * s)
    -- Exactly as wide as the health bars: from where they end toward the
    -- chin to where they start at the screen side.
    local left = math.floor(W * (1 - (HUD.VISOR_BAR_TO or 0.3)))
    local right = math.floor(W * (1 - (HUD.VISOR_BAR_FROM or 0.005)))
    local gap = math.floor(8 * s)
    local tw = math.floor((right - left - gap * 3) / 4)
    local xs = {}
    for i = 1, 4 do xs[i] = left + (i - 1) * (tw + gap) end
    xs[5] = right   -- end of the row

    -- Natural tile bottoms (40 px below the top-left corner).
    local nat = {}
    for i = 1, 4 do nat[i] = cheekY(xs[i]) + off + th end

    local list = collect(entries)
    local strip = {}
    for _, it in ipairs(list) do
        if it.group ~= "main" then
            -- Overflow first, then the backpack, like the layout mockup.
            if it.group == "over" then table.insert(strip, 1, it) else strip[#strip + 1] = it end
        end
    end
    local hasStrip = #strip > 0
    local ph = math.floor(26 * s)
    local low = math.max(nat[2], nat[3], nat[4])
    -- The strip's bottom lines up with slot 1's bottom.
    local stripY = math.floor(math.max(low + 7 * s, nat[1] - ph))
    local ammoTop = math.floor(math.max(hasStrip and (stripY + ph) or low, nat[1]) + 8 * s)
    local reach = hasStrip and (stripY - math.floor(6 * s)) or (ammoTop - math.floor(8 * s))

    local r = HUD.HotbarRect
    r.x, r.y, r.w, r.h, r.frame = left, math.floor(cheekY(right) + off), right - left, ammoTop - math.floor(cheekY(right) + off), FrameNumber()

    -- Slots 1-4.
    local function top(x) return cheekY(x) + off end
    for i = 1, 4 do
        local it = list[i]
        if it and it.group == "main" then
            local e = it.e
            local act = isActive(e, active)
            local a = act and math.min(255, alpha * 2) or alpha
            local x0, x1 = xs[i], i == 4 and right or xs[i] + tw
            -- Slot 1 reaches down level with the strip's bottom line.
            local bot = reach
            if i == 1 then bot = math.floor(math.max(nat[1], hasStrip and (stripY + ph) or reach)) end
            -- The top follows the cheek.
            tile(x0, x1, top, bot, 4, act, e.empty, a)
            local pad = math.floor(8 * s)
            txt(tostring(e.key), 12, 700, x1 - math.floor(7 * s), bot - math.floor(28 * s), act and C.accent or C.dim, TEXT_ALIGN_RIGHT, a)
            if e.empty then
                txt("Empty", 12, 400, x0 + pad, bot - math.floor(13 * s), C.dim, nil, a * 0.5)
            else
                local subW = 0
                if e.sub then subW = txt(e.sub, 11, 400, x1 - math.floor(7 * s), bot - math.floor(13 * s), C.dim, TEXT_ALIGN_RIGHT, a) + math.floor(6 * s) end
                local wgt = act and 500 or 400
                txt(fit(e.name, 14, wgt, x1 - x0 - pad - subW - 7 * s), 14, wgt, x0 + pad, bot - math.floor(13 * s), act and C.text or C.dim, nil, a)
            end
        end
    end

    -- The strip under slots 2-4: overflow and backpack slots.
    if hasStrip then
        local sx0, sx1 = xs[2], right
        plate(sx0, stripY, sx1 - sx0, ph, alpha * 0.85)
        local cw = (sx1 - sx0) / #strip
        local cy = stripY + ph * 0.5
        for k, it in ipairs(strip) do
            local e = it.e
            local bx = math.floor(sx0 + (k - 1) * cw)
            local bw = math.floor(sx0 + k * cw) - bx
            if k > 1 then
                setCol(COL_DIVIDER, alpha)
                surface.DrawRect(bx, stripY + math.floor(5 * s), 1, ph - math.floor(10 * s))
            end
            local act = isActive(e, active)
            local a = act and math.min(255, alpha * 2) or alpha
            if act then
                setCol(C.accent, a)
                surface.DrawRect(bx + 2, stripY + ph - 3, bw - 4, 2)
            end
            local kw = txt(tostring(e.key), 11, 700, bx + math.floor(8 * s), cy, act and C.accent or C.dim, nil, a)
            local nx = bx + math.floor(8 * s) + kw + math.floor(6 * s)
            local right = bx + bw - math.floor(6 * s)
            local first = k == 1 or strip[k - 1].group ~= it.group
            if first then
                right = right - txt(it.group == "pack" and "PACK" or "OTHER", 8, 700, right, cy, COL_LABEL, TEXT_ALIGN_RIGHT, a * 0.7) - math.floor(6 * s)
            end
            local extra = overflowExtra(e)
            if extra and e.overflow then
                right = right - txt(extra, 11, 400, right, cy, C.dim, TEXT_ALIGN_RIGHT, a) - math.floor(4 * s)
            end
            if e.empty then
                txt("Empty", 12, 400, nx, cy, C.dim, nil, a * 0.5)
            elseif right - nx > 8 * s then
                txt(fit(e.name, 12, 400, right - nx), 12, 400, nx, cy, act and C.text or C.dim, nil, a)
            end
        end
    end

    -- The ammo plate, as wide as the tiles.
    local ax0, ax1 = left, right
    local ah = YB - ammoTop
    plate(ax0, ammoTop, ax1 - ax0, ah, 255)
    local pad = math.floor(12 * s)
    local ty = ammoTop + math.floor(15 * s)
    local nw = txt(ai.name or "", 15, 500, ax0 + pad, ty, C.dim, nil, 255)
    local lx = ax0 + pad + nw + math.floor(10 * s)
    if ai.mode then
        lx = lx + txt(ai.mode, 14, 700, lx, ty, ai.safe and C.fuel or C.accent, nil, 255) + math.floor(14 * s)
    end
    if ai.cell then
        local lowCell = ai.cell < Rhylib.Config.Get("weapons", "lowCellThreshold")
        txt(string.format("CELL %d%%  %d spare", math.ceil(ai.cell * 100), ai.cells or 0), 13, 700, lx, ty, lowCell and C.bad or C.dim, nil, 255)
    end

    local my2 = ammoTop + math.floor(38 * s)
    if ai.magShort then
        local px = ax0 + pad
        px = px + pips(px, my2 - math.floor(10 * s), ai.spare or 0, math.max(4, math.floor(10 * s)), math.floor(20 * s), math.max(2, math.floor(4 * s)), 255)
        local label = string.upper(ai.magShort)
        if (ai.magRounds or 2) > 1 then label = label .. ((ai.spare or 0) == 1 and " MAG" or " MAGS") elseif (ai.spare or 0) ~= 1 then label = label .. "S" end
        px = px + math.floor(6 * s) + txt(label, 13, 700, px + math.floor(6 * s), my2, (ai.spare or 0) > 0 and C.dim or C.bad, nil, 255)
        if ai.others then txt(ai.others, 13, 400, px + math.floor(12 * s), my2, C.dim, nil, 255) end
    elseif ai.spare then
        txt(ai.spare .. " spare", 13, 400, ax0 + pad, my2, C.dim, nil, 255)
    end

    local cy = ammoTop + math.floor(30 * s)
    if ai.unarmed or ai.noAmmo then
        txt(ai.unarmed and "UNARMED" or "—", 24, 500, ax1 - pad, cy, C.dim, TEXT_ALIGN_RIGHT, 255)
    else
        local mw = txt("/ " .. (ai.maxClip or 0), 15, 400, ax1 - pad, cy + math.floor(5 * s), C.dim, TEXT_ALIGN_RIGHT, 255)
        txt(tostring(ai.clip or 0), 34, 500, ax1 - pad - mw - math.floor(6 * s), cy, clipColour(ai), TEXT_ALIGN_RIGHT, 255)
    end

    -- Round ticks along the bottom.
    local N, lit = tickCounts(ai)
    local tg = math.max(1, math.floor(2 * s))
    local span = ax1 - ax0 - pad * 2
    local tkw = (span - (N - 1) * tg) / N
    local th2 = math.max(3, math.floor(7 * s))
    local tyb = YB - math.floor(9 * s) - th2
    local on = tickColour(ai)

    -- Power cell (cell weapons): a bar right above the ticks, coloured like
    -- the third-person cell bar.
    if ai.cell then
        local ch = math.max(3, math.floor(5 * s))
        local lowCell = ai.cell < Rhylib.Config.Get("weapons", "lowCellThreshold")
        HUD.Bar(ax0 + pad, tyb - math.floor(5 * s) - ch, span, ch, ai.cell, lowCell and C.bad or C.armor)
    end
    for i = 1, N do
        local tx = ax0 + pad + (i - 1) * (tkw + tg)
        setCol(i <= lit and on or COL_TICK_OFF, 255)
        surface.DrawRect(math.floor(tx), tyb, math.max(1, math.floor(tx + tkw) - math.floor(tx)), th2)
    end
end

-- Called by cl_40_hotbar.lua in the visor (with the inventory).
function HUD.DrawVisorLayout(name, entries, active, alpha, s)
    local ply = LocalPlayer()
    local ai = HUD.AmmoInfo(ply, ply:GetActiveWeapon())
    if name == "f5" then
        drawF5(entries, active, alpha, s, ai)
    else
        drawF4(entries, active, alpha, s, ai)
    end
end
