--[[
    Stamina bar (client; needs rhylib_stamina, reads Rhylib.Stamina.Frac
    and Exhausted; draws nothing without it). It shrinks toward the middle from
    both ends as stamina runs down, blinks gently at 20% or less, turns
    red while you're exhausted, and fades out after 2 seconds at full.

      Third person: a thin bar on top of the hotbar, as wide as it.
      Helmet visor: two mirrored strips along the cheek edges, from the
                    armour/health bars down to the bottom of the screen,
                    as thick as those bars, always shown.
                    Together they're one bar whose middle is the chin, so
                    each half shrinks toward the chin.

    The visor strips use HUD.VisorStrip (cl_60_visor.lua); the radio's
    own voice meter sits under them (rhylib_radio cl_20_hud.lua).
]]

local HUD = Rhylib.HUD

local COL_TRACK = Color(255, 255, 255, 22)
local COL_FILL = Color(210, 214, 206)
local COL_LOW = Color(239, 159, 39)
local COL_EXHAUSTED = Color(226, 75, 74)

local fullSince = 0

-- Visor strips: from just past the armour/health bars to near the chin.
local STRIP_GAP = 0.006     -- after the last armour/health bar (share of the width)
local STRIP_END = 0.4       -- the curve's end: the bottom of the screen
local STRIP_STEPS = 28

local partQuad = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local revQuad = { {}, {}, {}, {} }
local function partQuadRev(q)
    revQuad[1], revQuad[2], revQuad[3], revQuad[4] = q[1], q[4], q[3], q[2]
    return revQuad
end

local function drawVisor(frac, col, a, alpha)
    local from = (HUD.VISOR_BAR_TO or 0.3) + STRIP_GAP
    local off = HUD.VISOR_BAR_OFFSET or 0.005
    -- (a texture left bound by an earlier draw made the strip dark grey;
    -- clear it the same way the radio squares do)
    draw.NoTexture()
    surface.SetTexture(0)
    for _, side in ipairs({ -1, 1 }) do
        local strip = HUD.VisorStrip(side, from, STRIP_END, off, HUD.VISOR_BAR_THICK or 0.009, STRIP_STEPS)
        -- Track, then the filled part at the chin end.
        surface.SetDrawColor(COL_TRACK.r, COL_TRACK.g, COL_TRACK.b, COL_TRACK.a * alpha / 255)
        for _, q in ipairs(strip.quads) do surface.DrawPoly(q) end
        -- Whole pieces, then the part-filled piece cut where the fill ends,
        -- so it shrinks smoothly instead of a piece at a time.
        local filled = math.Clamp(frac, 0, 1) * STRIP_STEPS
        local n = math.floor(filled)
        draw.NoTexture()
        surface.SetTexture(0)
        surface.SetDrawColor(col.r, col.g, col.b, a)
        for i = STRIP_STEPS - n + 1, STRIP_STEPS do surface.DrawPoly(strip.quads[i]) end
        local part = filled - n
        if part > 0.01 and n < STRIP_STEPS then
            local k = STRIP_STEPS - n            -- the piece from point k to k + 1
            local o0, o1 = strip.outer[k], strip.outer[k + 1]
            local i0, i1 = strip.inner[k], strip.inner[k + 1]
            local u = 1 - part
            local q = partQuad
            q[1].x, q[1].y = o0[1] + (o1[1] - o0[1]) * u, o0[2] + (o1[2] - o0[2]) * u
            q[2].x, q[2].y = o1[1], o1[2]
            q[3].x, q[3].y = i1[1], i1[2]
            q[4].x, q[4].y = i0[1] + (i1[1] - i0[1]) * u, i0[2] + (i1[2] - i0[2]) * u
            -- Keep the winding clockwise on screen.
            local area = 0
            for j = 1, 4 do
                local p, nx = q[j], q[j % 4 + 1]
                area = area + (p.x * nx.y - nx.x * p.y)
            end
            if area < 0 then
                surface.DrawPoly(partQuadRev(q))
            else
                surface.DrawPoly(q)
            end
        end
        -- End ticks across the strip.
        local tick = HUD.Style and HUD.Style.tick
        if tick then
            surface.SetDrawColor(tick.r, tick.g, tick.b, tick.a * alpha / 255)
            for _, i in ipairs({ 1, #strip.outer }) do
                surface.DrawLine(strip.outer[i][1], strip.outer[i][2], strip.inner[i][1], strip.inner[i][2])
            end
        end
    end
end

Rhylib.Hook.Add("HUDPaint", "hud.stamina", function()
    local S = Rhylib.Stamina
    if not S or HUD.Hidden() then return end
    local ply = LocalPlayer()
    local frac = S.Frac(ply)
    local now = RealTime()

    -- Fade out after 2 s at full, fade straight back in when used.
    -- (In the helmet visor it always stays, like the armour and health.)
    local visor = HUD.VisorActive and HUD.VisorActive() and HUD.VisorStrip
    local alpha = 255
    if visor then
        fullSince = 0
    elseif frac >= 1 then
        if fullSince == 0 then fullSince = now end
        alpha = math.Clamp(255 - (now - fullSince - 2) * 510, 0, 255)
    else
        fullSince = 0
    end
    if alpha <= 0 then return end

    local exhausted = S.Exhausted(ply)
    local low = frac <= 0.2
    local col = exhausted and COL_EXHAUSTED or (low and COL_LOW or COL_FILL)
    local a = alpha
    if low then a = a * (0.65 + 0.35 * math.cos(now * 7)) end  -- gentle blink

    if visor then
        drawVisor(frac, col, a, alpha)
        return
    end

    local s = HUD.Scale()
    -- The hotbar draws after us (priority 0 vs -9), so HotbarRect is from
    -- the last frame; accept it if it is at most one frame old.
    local r = HUD.HotbarRect
    local w, x, y
    local barH = math.max(2, math.floor(6 * s))
    local gap = math.floor(6 * s)
    if r and r.w > 0 and FrameNumber() - r.frame <= 1 then
        w, x, y = r.w, r.x, r.y - gap - barH
    else
        -- No hotbar (no weapons): same place, a fixed width.
        w = math.floor(ScrW() * 0.25)
        x = math.floor((ScrW() - w) * 0.5)
        local _, my = HUD.Margins("hotbar")
        y = ScrH() - my - math.floor(76 * s) - gap - barH
    end

    surface.SetDrawColor(COL_TRACK.r, COL_TRACK.g, COL_TRACK.b, COL_TRACK.a * alpha / 255)
    surface.DrawRect(x, y, w, barH)

    local fw = math.floor(w * frac + 0.5)
    if fw > 0 then
        surface.SetDrawColor(col.r, col.g, col.b, a)
        surface.DrawRect(x + math.floor((w - fw) * 0.5), y, fw, barH)
    end

    -- End ticks, in the HUD's style.
    local tick = HUD.Style and HUD.Style.tick
    if tick then
        surface.SetDrawColor(tick.r, tick.g, tick.b, tick.a * alpha / 255)
        surface.DrawRect(x - 2, y - 2, 2, barH + 4)
        surface.DrawRect(x + w, y - 2, 2, barH + 4)
    end
end, -9)   -- (right after the visor shell, like the armour bars)
