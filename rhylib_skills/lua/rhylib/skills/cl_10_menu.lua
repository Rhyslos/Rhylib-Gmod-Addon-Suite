--[[
    Skills page in the pause menu (rhylib_menus), drawn like a doctrine
    tree: one tab per category, square skill icons in tier rows, and
    straight connector lines that only turn at right angles (down from a
    skill, across, down into the next). Shared skills sit in the middle,
    each specialisation has its own column, end branches sit in framed
    boxes inside it.

    Click a skill to learn it (skills.learn); "Reset skills" clears all
    (skills.reset). Learned = filled accent square, can learn = green
    edge, locked = dim. The panel on the right explains the skill under
    the mouse (or the last one clicked).

    Icons are small vector glyphs drawn here (ICONS / GLYPHS), so there
    are no materials to ship.
]]

local K = Rhylib.Skills

Rhylib.Net.Receive("skills.note", function()
    local bad = net.ReadBool()
    local text = net.ReadString()
    chat.AddText(bad and Color(235, 90, 80) or Color(133, 183, 235), "[Skills] ", Color(225, 225, 225), text)
    surface.PlaySound(bad and "buttons/button10.wav" or "buttons/button14.wav")
end)

local function learn(n)
    Rhylib.Net.Start("skills.learn")
    net.WriteUInt(n.index, 8)
    net.SendToServer()
end

--------------------------------------------------------------------------
-- Glyphs: shapes in a 0-1 box. R = rect, P = convex polygon, C = disc,
-- O = ring, L = thick line, S = star (points), B = burst (rays).
-- A trailing true draws in the background colour (cut-outs).
--------------------------------------------------------------------------

local GLYPHS = {
    mag = { { "R", .36, .12, .28, .5 }, { "P", { .36, .62, .64, .62, .58, .88, .30, .88 } },
        { "R", .42, .22, .16, .05, true }, { "R", .42, .34, .16, .05, true } },
    run = { { "P", { .12, .2, .3, .2, .52, .5, .34, .5 } }, { "P", { .34, .5, .52, .5, .3, .8, .12, .8 } },
        { "P", { .42, .2, .6, .2, .82, .5, .64, .5 } }, { "P", { .64, .5, .82, .5, .6, .8, .42, .8 } } },
    target = { { "O", .5, .5, .36, .07 }, { "O", .5, .5, .2, .07 }, { "C", .5, .5, .07 } },
    crosshair = { { "O", .5, .5, .28, .06 }, { "R", .47, .08, .06, .24 }, { "R", .47, .68, .06, .24 },
        { "R", .08, .47, .24, .06 }, { "R", .68, .47, .24, .06 }, { "C", .5, .5, .05 } },
    scope = { { "R", .12, .43, .76, .14 }, { "R", .16, .34, .16, .32 }, { "R", .68, .37, .14, .26 }, { "R", .44, .57, .07, .15 } },
    aim = { { "R", .15, .15, .22, .06 }, { "R", .15, .15, .06, .22 }, { "R", .63, .15, .22, .06 }, { "R", .79, .15, .06, .22 },
        { "R", .15, .79, .22, .06 }, { "R", .15, .63, .06, .22 }, { "R", .63, .79, .22, .06 }, { "R", .79, .63, .06, .22 },
        { "C", .5, .5, .08 } },
    bolt = { { "P", { .58, .08, .26, .56, .52, .56 } }, { "P", { .48, .44, .74, .44, .42, .92 } } },
    stack = { { "R", .18, .22, .64, .12 }, { "R", .18, .44, .64, .12 }, { "R", .18, .66, .64, .12 } },
    rounds = { { "R", .2, .36, .14, .46 }, { "P", { .2, .36, .27, .18, .34, .36 } }, { "R", .43, .36, .14, .46 },
        { "P", { .43, .36, .5, .18, .57, .36 } }, { "R", .66, .36, .14, .46 }, { "P", { .66, .36, .73, .18, .8, .36 } } },
    cell = { { "R", .3, .2, .4, .66 }, { "R", .42, .12, .16, .08 }, { "R", .47, .38, .06, .22, true }, { "R", .4, .46, .2, .06, true } },
    grenade = { { "C", .5, .6, .27 }, { "R", .42, .2, .16, .16 }, { "R", .56, .23, .2, .05 } },
    barrels = { { "R", .1, .36, .6, .07 }, { "R", .1, .47, .6, .07 }, { "R", .1, .58, .6, .07 }, { "R", .66, .3, .24, .42 } },
    shield = { { "P", { .2, .16, .8, .16, .8, .5, .5, .88, .2, .5 } }, { "R", .2, .36, .6, .06, true } },
    heart = { { "C", .36, .38, .17 }, { "C", .64, .38, .17 }, { "P", { .2, .46, .8, .46, .5, .84 } } },
    anchor = { { "O", .5, .18, .08, .05 }, { "R", .47, .26, .06, .54 }, { "R", .32, .34, .36, .06 },
        { "R", .2, .74, .6, .06 }, { "R", .2, .58, .06, .2 }, { "R", .74, .58, .06, .2 } },
    belt = { { "R", .08, .5, .84, .14 }, { "R", .14, .28, .08, .2 }, { "R", .3, .28, .08, .2 }, { "R", .46, .28, .08, .2 },
        { "R", .62, .28, .08, .2 }, { "R", .78, .28, .08, .2 } },
    flame = { { "C", .5, .64, .22 }, { "P", { .28, .6, .5, .1, .72, .6 } }, { "C", .5, .7, .09, true } },
    drop = { { "C", .5, .63, .24 }, { "P", { .27, .58, .5, .12, .73, .58 } } },
    feather = { { "P", { .62, .1, .82, .3, .4, .78, .22, .6 } }, { "L", .16, .86, .5, .5, .05 } },
    weight = { { "C", .5, .62, .26 }, { "O", .5, .3, .14, .06 } },
    box = { { "R", .16, .36, .68, .46 }, { "R", .16, .26, .68, .07 }, { "R", .43, .5, .14, .14, true } },
    pistol = { { "R", .16, .3, .62, .15 }, { "P", { .48, .45, .66, .45, .6, .8, .42, .8 } } },
    dual = { { "R", .08, .22, .46, .11 }, { "P", { .32, .33, .45, .33, .41, .58, .28, .58 } },
        { "R", .46, .5, .46, .11 }, { "P", { .7, .61, .83, .61, .79, .86, .66, .86 } } },
    star = { { "S", .5, .52, .38 } },
    burst = { { "B", .5, .5, .4 } },
    up = { { "P", { .5, .14, .86, .48, .7, .48, .5, .3 } }, { "P", { .5, .14, .5, .3, .3, .48, .14, .48 } },
        { "P", { .5, .44, .86, .78, .7, .78, .5, .6 } }, { "P", { .5, .44, .5, .6, .3, .78, .14, .78 } } },
    fuel = { { "R", .28, .22, .44, .62 }, { "R", .4, .13, .2, .09 }, { "R", .34, .42, .32, .05, true }, { "R", .34, .56, .32, .05, true } },
    spring = { { "L", .3, .18, .7, .34, .07 }, { "L", .7, .34, .3, .5, .07 }, { "L", .3, .5, .7, .66, .07 }, { "L", .7, .66, .3, .82, .07 } },
    dodge = { { "P", { .08, .5, .3, .28, .3, .72 } }, { "R", .3, .45, .16, .1 }, { "P", { .92, .5, .7, .72, .7, .28 } }, { "R", .54, .45, .16, .1 } },
    landing = { { "R", .42, .08, .16, .28 }, { "P", { .24, .34, .76, .34, .5, .6 } }, { "R", .1, .7, .8, .07 }, { "R", .22, .82, .56, .06 } },
    down = { { "R", .42, .1, .16, .4 }, { "P", { .2, .48, .8, .48, .5, .82 } }, { "R", .16, .86, .68, .06 } },
    drag = { { "P", { .1, .5, .34, .28, .34, .72 } }, { "R", .34, .45, .34, .1 }, { "R", .72, .24, .09, .52 } },
    cross = { { "R", .4, .14, .2, .72 }, { "R", .14, .4, .72, .2 } },
    clock = { { "O", .5, .5, .33, .07 }, { "R", .47, .28, .06, .25 }, { "R", .47, .47, .2, .06 } },
    pocket = { { "R", .2, .32, .6, .5 }, { "R", .2, .44, .6, .05, true }, { "O", .5, .26, .1, .05 } },
    eye = { { "E", .5, .5, .38, .2 }, { "C", .5, .5, .12, true }, { "C", .5, .5, .06 } },
    syringe = { { "L", .26, .74, .64, .36, .14 }, { "L", .64, .36, .84, .16, .04 }, { "L", .12, .76, .24, .88, .05 } },
    flask = { { "R", .42, .14, .16, .26 }, { "P", { .42, .4, .58, .4, .82, .86, .18, .86 } }, { "R", .36, .12, .28, .05 } },
    bone = { { "R", .3, .44, .4, .12 }, { "C", .28, .42, .09 }, { "C", .28, .58, .09 }, { "C", .72, .42, .09 }, { "C", .72, .58, .09 } },
    crouch = { { "C", .44, .18, .1 }, { "P", { .34, .32, .54, .32, .6, .6, .4, .6 } }, { "R", .4, .56, .36, .1 },
        { "R", .66, .56, .1, .3 }, { "P", { .32, .58, .44, .58, .4, .86, .28, .86 } }, { "R", .12, .86, .76, .05 } },
    riot = { { "R", .24, .1, .52, .8 }, { "R", .32, .22, .36, .08, true }, { "R", .46, .38, .08, .4, true } },
    bash = { { "R", .12, .2, .34, .6 }, { "L", .58, .32, .86, .2, .06 }, { "L", .58, .5, .9, .5, .06 }, { "L", .58, .68, .86, .8, .06 } },
    cuffs = { { "O", .3, .6, .16, .07 }, { "O", .7, .6, .16, .07 }, { "L", .42, .38, .58, .38, .06 } },
    door = { { "R", .22, .1, .46, .8 }, { "R", .28, .16, .34, .74, true }, { "C", .56, .52, .04 }, { "B", .8, .28, .14 } },
    search = { { "O", .42, .42, .24, .07 }, { "L", .6, .6, .86, .86, .1 } },
    charge = { { "R", .1, .4, .46, .2 }, { "P", { .54, .2, .9, .5, .54, .8 } } },
    wall = { { "R", .1, .2, .38, .16 }, { "R", .52, .2, .38, .16 }, { "R", .1, .42, .18, .16 }, { "R", .32, .42, .36, .16 },
        { "R", .72, .42, .18, .16 }, { "R", .1, .64, .38, .16 }, { "R", .52, .64, .38, .16 } },
    phalanx = { { "R", .06, .22, .26, .6 }, { "R", .37, .16, .26, .6 }, { "R", .68, .22, .26, .6 } },
    swap = { { "R", .14, .3, .56, .1 }, { "P", { .7, .18, .9, .35, .7, .52 } },
        { "R", .3, .6, .56, .1 }, { "P", { .3, .82, .1, .65, .3, .48 } } },
}

-- Icon per skill (a node's own `icon` wins).
local ICONS = {
    quick_hands = "mag", run_gun = "run", point_blank = "target", full_auto = "rounds", ext_mags = "mag",
    droid_popper = "grenade", light_kit = "feather", rapid_fire = "bolt", momentum = "star",
    gun_runner = "barrels", steady_barrels = "aim", eff_cells = "cell", load_bearer = "weight", ammo_pack = "box",
    pistol_prof = "pistol", carbine_sidearm = "pistol", steady_grip = "pistol", dual_dc17 = "dual", crits = "star",
    hard_landings = "down", extended_tanks = "fuel", afterburner = "flame",
    combat_drop = "landing", blast_hardened = "shield", aerial_stability = "anchor", death_from_above = "burst",
    field_drag = "drag", hands_on = "heart", steady_hands = "clock", quick_revive = "cross", under_fire = "shield",
    deep_pockets = "pocket", triage = "eye", chem_bench = "flask", field_surgeon = "bone",
    batch_brewing = "stack", bacta_specialist = "drop",
    riot_shield = "riot", shield_bash = "bash", escort_drills = "cuffs", breaching = "door",
    thorough_search = "search", shock_assault = "charge", hold_line = "wall", flash_charge = "burst", phalanx = "phalanx",
    mark_target = "target", quick_draw = "bolt", speed_loader = "mag",
    light_rounds = "rounds", adapt_1 = "swap", dp23_prof = "rounds", battle_rush = "burst", grenadier = "grenade", hover = "up",
    carbine_disc = "aim", called_shot = "eye", priority_target = "star", precision_rhythm = "stack",
    cmd_wind = "run", cmd_triage = "cross", cmd_hold = "shield", cmd_focus = "aim", cmd_open = "box", cmd_press = "charge",
}

local function iconOf(n) return n.icon or ICONS[n.id] or "star" end

-- Drawing helpers. DrawPoly wants clockwise points on screen.
local function poly(pts)
    local area = 0
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        area = area + (a.x * b.y - b.x * a.y)
    end
    if area < 0 then
        local r = {}
        for i = #pts, 1, -1 do r[#r + 1] = pts[i] end
        pts = r
    end
    surface.DrawPoly(pts)
end

local function circlePts(cx, cy, rx, ry, seg)
    local pts = {}
    for i = 0, seg - 1 do
        local a = i / seg * math.pi * 2
        pts[#pts + 1] = { x = cx + math.cos(a) * rx, y = cy + math.sin(a) * ry }
    end
    return pts
end

local function thickLine(x1, y1, x2, y2, t)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0 then return end
    local nx, ny = -dy / len * t * 0.5, dx / len * t * 0.5
    poly({ { x = x1 + nx, y = y1 + ny }, { x = x2 + nx, y = y2 + ny }, { x = x2 - nx, y = y2 - ny }, { x = x1 - nx, y = y1 - ny } })
end

local function drawGlyph(name, x, y, s, col, bg)
    local g = GLYPHS[name] or GLYPHS.star
    draw.NoTexture()
    for _, p in ipairs(g) do
        local kind = p[1]
        local cut = p[#p] == true
        surface.SetDrawColor(cut and bg or col)
        if kind == "R" then
            surface.DrawRect(math.floor(x + p[2] * s), math.floor(y + p[3] * s), math.max(1, math.floor(p[4] * s + 0.5)), math.max(1, math.floor(p[5] * s + 0.5)))
        elseif kind == "P" then
            local pts = {}
            for i = 1, #p[2], 2 do pts[#pts + 1] = { x = x + p[2][i] * s, y = y + p[2][i + 1] * s } end
            poly(pts)
        elseif kind == "C" then
            poly(circlePts(x + p[2] * s, y + p[3] * s, p[4] * s, p[4] * s, 16))
        elseif kind == "E" then
            poly(circlePts(x + p[2] * s, y + p[3] * s, p[4] * s, p[5] * s, 18))
        elseif kind == "O" then
            local cx, cy, r, t = x + p[2] * s, y + p[3] * s, p[4] * s, p[5] * s
            local seg = 18
            for i = 0, seg - 1 do
                local a1, a2 = i / seg * math.pi * 2, (i + 1) / seg * math.pi * 2
                local ro, ri = r + t * 0.5, r - t * 0.5
                poly({ { x = cx + math.cos(a1) * ro, y = cy + math.sin(a1) * ro }, { x = cx + math.cos(a2) * ro, y = cy + math.sin(a2) * ro },
                    { x = cx + math.cos(a2) * ri, y = cy + math.sin(a2) * ri }, { x = cx + math.cos(a1) * ri, y = cy + math.sin(a1) * ri } })
            end
        elseif kind == "L" then
            thickLine(x + p[2] * s, y + p[3] * s, x + p[4] * s, y + p[5] * s, p[6] * s)
        elseif kind == "S" or kind == "B" then
            local cx, cy, r = x + p[2] * s, y + p[3] * s, p[4] * s
            local n, inner = kind == "S" and 5 or 8, kind == "S" and 0.42 or 0.45
            local core = {}
            for i = 0, n - 1 do
                local a = (i / n) * math.pi * 2 - math.pi * 0.5
                local a1, a2 = a - math.pi / n, a + math.pi / n
                local tip = { x = cx + math.cos(a) * r, y = cy + math.sin(a) * r }
                local l = { x = cx + math.cos(a1) * r * inner, y = cy + math.sin(a1) * r * inner }
                local rr = { x = cx + math.cos(a2) * r * inner, y = cy + math.sin(a2) * r * inner }
                poly({ l, tip, rr })
                core[#core + 1] = l
            end
            poly(core)
        end
    end
end
K.DrawGlyph = drawGlyph

-- Word wrap into at most maxLines lines (the last one cut to fit).
local function wrap(text, font, maxW, maxLines)
    surface.SetFont(font)
    local lines, cur = {}, ""
    for word in string.gmatch(text, "%S+") do
        local try = cur == "" and word or (cur .. " " .. word)
        if surface.GetTextSize(try) <= maxW or cur == "" then
            cur = try
        else
            lines[#lines + 1] = cur
            cur = word
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    if maxLines and #lines > maxLines then
        local keep = {}
        for i = 1, maxLines do keep[i] = lines[i] end
        keep[maxLines] = keep[maxLines] .. " " .. table.concat(lines, " ", maxLines + 1)
        lines = keep
    end
    local Kit = Rhylib.Menus and Rhylib.Menus.Kit
    for i, l in ipairs(lines) do
        if surface.GetTextSize(l) > maxW and Kit and Kit.Fit then lines[i] = Kit.Fit(l, font, maxW) end
    end
    return lines
end

--------------------------------------------------------------------------
-- Layout: columns per spec / branch, rows per tier
--------------------------------------------------------------------------

local function columns(cat)
    local specs = cat.specs or {}
    local cols = { shared = { 0, 1 }, spec = {}, branch = {} }
    local n = #specs
    for i, s in ipairs(specs) do
        local a, b = (i - 1) / math.max(n, 1), i / math.max(n, 1)
        cols.spec[s.id] = { a, b }
        local br = s.branches or {}
        for j, x in ipairs(br) do
            cols.branch[x.id] = { a + (b - a) * (j - 1) / #br, a + (b - a) * j / #br }
        end
    end
    return cols
end

local function reqsOf(n)
    local out, seen = {}, {}
    local function add(r)
        if not seen[r] then seen[r] = true out[#out + 1] = r end
    end
    for _, r in ipairs(n.needs or {}) do add(r) end
    for _, g in ipairs(n.needsGroups or {}) do
        for _, r in ipairs(g) do add(r) end
    end
    return out
end

local function stateOf(me, set, n)
    if set[n.id] then return "learned" end
    local ok, why = K.CanLearn(me, set, n.id)
    return ok and "open" or "locked", why
end

--------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------

local function build(page)
    local Menus = Rhylib.Menus
    local Kit = Menus.Kit
    local C, S = Kit.C, Kit.S
    local me = LocalPlayer()

    local cur = K.CATEGORIES[1].id
    for c in pairs(K.Commitments(K.Set(me))) do cur = c end
    local hovered, picked

    -- Tabs.
    local bar = vgui.Create("DPanel", page)
    bar:Dock(TOP)
    bar:SetTall(S(30))
    bar:DockMargin(0, 0, 0, S(10))
    bar.Paint = nil

    -- Right: the details panel, points and reset.
    local side = vgui.Create("DPanel", page)
    side:Dock(RIGHT)
    side:SetWide(S(300))
    side:DockMargin(S(10), 0, 0, 0)
    local reset = Kit.Button(side, "Reset skills", function()
        Rhylib.Net.Start("skills.reset")
        net.SendToServer()
    end, { small = true, danger = true })
    reset:Dock(BOTTOM)
    reset:DockMargin(S(10), 0, S(10), S(10))

    local tree = vgui.Create("DPanel", page)
    tree:Dock(FILL)

    function side:Paint(w, h)
        local hp = vgui.GetHoveredPanel()
        -- (kept while the mouse is over this panel, so long text can be read)
        if IsValid(hp) and hp.node then
            hovered = hp.node
        elseif not (IsValid(hp) and (hp == self or hp:GetParent() == self)) then
            hovered = nil
        end
        Kit.Plate(0, 0, w, h, { bg = C.row })
        local pad = S(14)
        local set = K.Set(me)
        -- Points, above the reset button.
        local spent = K.Spent(set)
        local pts = K.Cfg("freePoints") and ("Spent " .. spent .. " points  ·  free while testing")
            or ("Points: " .. (K.Points(me) - spent) .. " left of " .. K.Points(me))
        draw.SimpleText(pts, Kit.Font(12, 600), w * 0.5, h - S(52), C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        Kit.SetCol(C.edgeLight)
        surface.DrawRect(pad, h - S(68), w - pad * 2, 1)

        local n = hovered or picked
        local y = pad
        if not n then
            local cat = K.catById[cur]
            draw.SimpleText(string.upper(cat.name), Kit.Font(18, 700), pad, y, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            y = y + S(28)
            for _, l in ipairs(wrap(cat.desc or "", Kit.Font(13), w - pad * 2, 3)) do
                draw.SimpleText(l, Kit.Font(13), pad, y, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                y = y + S(18)
            end
            y = y + S(14)
            local rules = {
                "Hover a skill to read it, click to learn it.",
                "One path at a time, one specialisation per path, one end branch.",
                "Lines show what each skill needs first.",
            }
            if cat.medicOnly then table.insert(rules, 1, "Medic jobs only.") end
            if cat.mpOnly then table.insert(rules, 1, "Military police jobs only.") end
            if cat.id == K.ADAPT_CAT then
                rules[#rules + 1] = "Adaptable: learn one skill of tier 4 or lower from another tree; job rules still apply."
                rules[#rules + 1] = "Command orders: pick one. Needs the rank " .. tostring(K.Cfg("commandRank")) .. "; issued with the command comlink."
            end
            for _, r in ipairs(rules) do
                Kit.SetCol(C.accent)
                surface.DrawRect(pad, y + S(6), S(4), S(4))
                for _, l in ipairs(wrap(r, Kit.Font(12), w - pad * 2 - S(10), 3)) do
                    draw.SimpleText(l, Kit.Font(12), pad + S(10), y, C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    y = y + S(16)
                end
                y = y + S(6)
            end
            return
        end

        -- A skill: icon, name, where it sits, state, text, requirements.
        local state, why = stateOf(me, set, n)
        local box = S(64)
        Kit.SetCol(state == "learned" and C.buttonDown or C.button)
        surface.DrawRect(pad, y, box, box)
        Kit.SetCol(state == "learned" and C.accent or (state == "open" and C.good or C.edgeDark))
        surface.DrawOutlinedRect(pad, y, box, box, 2)
        drawGlyph(iconOf(n), pad + box * 0.16, y + box * 0.16, box * 0.68,
            state == "locked" and C.textDim or (state == "learned" and C.accent or C.text), state == "learned" and C.buttonDown or C.button)
        local tx = pad + box + S(12)
        local nameLines = wrap(n.name, Kit.Font(17, 700), w - tx - pad, 2)
        local ny = y + S(2)
        for _, l in ipairs(nameLines) do
            draw.SimpleText(l, Kit.Font(17, 700), tx, ny, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            ny = ny + S(21)
        end
        local where = n.spec and K.specById[n.spec] and K.specById[n.spec].name or "Shared"
        if set[n.id] and K.Borrowed(set, n.id) then where = "Borrowed (Adaptable)" end
        if n.branch then
            for _, s in ipairs(K.catById[n.cat].specs or {}) do
                for _, b in ipairs(s.branches or {}) do
                    if b.id == n.branch then where = where .. " · " .. b.name end
                end
            end
        end
        draw.SimpleText(where .. "  ·  " .. n.cost .. " pt" .. (n.cost == 1 and "" or "s"), Kit.Font(12), tx, ny + S(2), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        y = y + box + S(14)

        local stateText = state == "learned" and "Learned" or (state == "open" and "Click to learn" or why or "Locked")
        draw.SimpleText(stateText, Kit.Font(13, 700), pad, y, state == "learned" and C.accent or (state == "open" and C.good or C.warn), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        y = y + S(26)
        for _, l in ipairs(wrap(n.desc or "", Kit.Font(14), w - pad * 2, 8)) do
            draw.SimpleText(l, Kit.Font(14), pad, y, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            y = y + S(20)
        end
        local reqs = reqsOf(n)
        if #reqs > 0 then
            y = y + S(12)
            Kit.Caps(n.needsGroups and (n.needsLabel or "Needs one of these pairs") or "Needs", pad, y + S(6))
            y = y + S(18)
            if n.needsGroups then
                for _, g in ipairs(n.needsGroups) do
                    local names, all = {}, true
                    for _, r in ipairs(g) do
                        names[#names + 1] = K.byId[r] and K.byId[r].name or r
                        if not set[r] then all = false end
                    end
                    local l = Kit.Fit(table.concat(names, " + "), Kit.Font(13), w - pad * 2 - S(14))
                    Kit.SetCol(all and C.good or C.edgeLight)
                    surface.DrawRect(pad, y + S(6), S(6), S(6))
                    draw.SimpleText(l, Kit.Font(13), pad + S(14), y, all and C.text or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    y = y + S(19)
                end
            else
                for _, r in ipairs(reqs) do
                    local has = set[r]
                    Kit.SetCol(has and C.good or C.edgeLight)
                    surface.DrawRect(pad, y + S(6), S(6), S(6))
                    draw.SimpleText(K.byId[r] and K.byId[r].name or r, Kit.Font(13), pad + S(14), y, has and C.text or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    y = y + S(19)
                end
            end
        end
    end

    local function fill()
        tree:Clear()
        hovered, picked = nil, nil
        local cat = K.catById[cur]
        local cols = columns(cat)
        local nodes, maxTier = {}, 1
        for _, n in ipairs(K.NODES) do
            if n.cat == cur then
                nodes[#nodes + 1] = n
                maxTier = math.max(maxTier, n.tier)
            end
        end
        tree.byNode = {}
        local L = {}   -- layout, filled in PerformLayout

        -- Which tiers each branch spans (for its frame).
        local branchTiers = {}
        for _, n in ipairs(nodes) do
            if n.branch then
                local t = branchTiers[n.branch] or { lo = n.tier, hi = n.tier }
                t.lo, t.hi = math.min(t.lo, n.tier), math.max(t.hi, n.tier)
                branchTiers[n.branch] = t
            end
        end

        function tree:Paint(w, h)
            Kit.Plate(0, 0, w, h, { bg = C.row })
            draw.SimpleText(string.upper(cat.name), Kit.Font(16, 700), S(14), S(16), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(cat.desc or "", Kit.Font(12), S(14), S(34), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if not L.rowH then return end
            local set = K.Set(me)
            local inner, x0 = L.inner, L.x0

            -- Specialisation headers and dividers.
            for i, s in ipairs(cat.specs or {}) do
                local c = cols.spec[s.id]
                local sx = x0 + inner * c[1]
                if i > 1 then
                    Kit.SetCol(C.edgeLight, 120)
                    surface.DrawRect(math.floor(sx), L.headY - S(8), 1, h - L.headY - S(4))
                end
                local cx = x0 + inner * (c[1] + c[2]) * 0.5
                draw.SimpleText(string.upper(s.name), Kit.Font(13, 700), cx, L.headY, C.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(s.desc or "", Kit.Font(11), cx, L.headY + S(15), C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            -- End branch frames (title at the bottom, clear of the lines).
            for _, s in ipairs(cat.specs or {}) do
                for _, br in ipairs(s.branches or {}) do
                    local t, c = branchTiers[br.id], cols.branch[br.id]
                    if t and c then
                        local bx = math.floor(x0 + inner * c[1] + S(6))
                        local bw = math.floor(inner * (c[2] - c[1]) - S(12))
                        local by = math.floor(L.rowY(t.lo) - S(8))
                        local bh = math.floor(L.rowY(t.hi) + L.sq + L.labelH + S(26) - by)
                        Kit.SetCol(C.bg, 120)
                        surface.DrawRect(bx, by, bw, bh)
                        Kit.SetCol(C.warn, 90)
                        surface.DrawOutlinedRect(bx, by, bw, bh)
                        draw.SimpleText(string.upper(br.name), Kit.Font(11, 700), bx + S(8), by + bh - S(10), C.warn, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    end
                end
            end

            -- Connectors: down from under the parent's name, across, down
            -- into the child. Dim first, the learned path on top.
            local th = math.max(2, S(2))
            for pass = 1, 2 do
                for _, n in ipairs(nodes) do
                    local cpos = L.pos[n.id]
                    if cpos then
                        for _, r in ipairs(reqsOf(n)) do
                            local ppos = L.pos[r]
                            if ppos then
                                local lit = set[r] and set[n.id]
                                if (pass == 2) == (lit and true or false) then
                                    Kit.SetCol(lit and C.accent or C.edgeLight, lit and 255 or 150)
                                    local px, py = ppos.cx, ppos.y + L.sq + L.labelH + S(2)
                                    local cx, cy = cpos.cx, cpos.y
                                    -- Each child in a row gets its own bus height, so
                                    -- crossing links stay readable.
                                    local busY = math.floor(cy - L.busGap + (cpos.busOff or 0))
                                    local half = math.floor(th * 0.5)
                                    surface.DrawRect(math.floor(px) - half, math.floor(py), th, math.max(1, busY - math.floor(py)))
                                    local a, b = math.min(px, cx), math.max(px, cx)
                                    surface.DrawRect(math.floor(a) - half, busY - half, math.floor(b - a) + th, th)
                                    surface.DrawRect(math.floor(cx) - half, busY, th, math.max(1, math.floor(cy) - busY))
                                end
                            end
                        end
                    end
                end
            end
        end

        for _, n in ipairs(nodes) do
            local b = vgui.Create("DButton", tree)
            b:SetText("")
            b.node = n
            tree.byNode[n.id] = b
            function b:Paint(w, h)
                local set = K.Set(me)
                local state = stateOf(me, set, n)
                local sq = L.sq or w
                local ox = math.floor((w - sq) * 0.5)
                local hov = self:IsHovered()
                local bg = state == "learned" and C.buttonDown or (hov and C.buttonHover or C.button)
                Kit.SetCol(bg)
                surface.DrawRect(ox, 0, sq, sq)
                local edge = state == "learned" and C.accent or (state == "open" and C.good or C.edgeDark)
                Kit.SetCol(edge, state == "locked" and 220 or 255)
                surface.DrawOutlinedRect(ox, 0, sq, sq, state == "locked" and 1 or 2)
                if hov and state ~= "learned" then
                    Kit.SetCol(C.accent, 160)
                    surface.DrawOutlinedRect(ox + 3, 3, sq - 6, sq - 6, 1)
                end
                -- Capstones: brackets outside the bottom corners.
                if n.cost >= 5 then
                    local t = math.max(4, math.floor(sq * 0.22))
                    Kit.SetCol(edge)
                    surface.DrawRect(ox - 4, sq - t, 2, t + 2) surface.DrawRect(ox - 4, sq, t, 2)
                    surface.DrawRect(ox + sq + 2, sq - t, 2, t + 2) surface.DrawRect(ox + sq - t + 4, sq, t, 2)
                end
                local gc = state == "locked" and C.textDim or (state == "learned" and C.accent or C.text)
                drawGlyph(iconOf(n), ox + sq * 0.18, sq * 0.18, sq * 0.64, gc, bg)
                -- Cost, bottom right (not once learned).
                if state ~= "learned" then
                    local f = Kit.Font(11, 700)
                    surface.SetFont(f)
                    local tw = surface.GetTextSize(tostring(n.cost))
                    local bw2, bh2 = tw + S(8), S(14)
                    Kit.SetCol(C.bg)
                    surface.DrawRect(ox + sq - bw2, sq - bh2, bw2, bh2)
                    Kit.SetCol(edge, 200)
                    surface.DrawOutlinedRect(ox + sq - bw2, sq - bh2, bw2, bh2)
                    draw.SimpleText(tostring(n.cost), f, ox + sq - bw2 * 0.5, sq - bh2 * 0.5, state == "locked" and C.textDim or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                -- Name under the square, up to two lines.
                local f = Kit.Font(12, 600)
                local lines = self.lines
                if not lines or self.linesW ~= w then
                    lines = wrap(n.name, f, w - S(4), 2)
                    self.lines, self.linesW = lines, w
                end
                for i, l in ipairs(lines) do
                    draw.SimpleText(l, f, w * 0.5, sq + S(4) + (i - 1) * S(14), state == "locked" and C.textDim or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                end
                return true
            end
            function b:DoClick()
                picked = n
                local set = K.Set(me)
                if set[n.id] then return end
                local ok, why = K.CanLearn(me, set, n.id)
                if not ok then
                    surface.PlaySound("buttons/button10.wav")
                    chat.AddText(Color(235, 90, 80), "[Skills] ", Color(225, 225, 225), why)
                    return
                end
                learn(n)
            end
        end

        -- Place the nodes: tier rows; nodes sharing a tier and a column
        -- spread evenly across it.
        function tree:PerformLayout(w, h)
            local x0 = S(14)
            local inner = w - S(28)
            local hasSpecs = #(cat.specs or {}) > 0
            local headY = S(62)
            local top = hasSpecs and headY + S(34) or S(64)
            local avail = h - top - S(14)
            local rowH = math.min(S(122), math.floor(avail / maxTier))
            local labelH = S(30)
            local sq = math.max(S(30), math.min(S(56), rowH - labelH - S(34)))
            L.x0, L.inner, L.headY, L.rowH, L.sq, L.labelH = x0, inner, headY, rowH, sq, labelH
            L.busGap = math.max(S(14), math.floor((rowH - sq - labelH) * 0.45))
            L.rowY = function(t) return top + (t - 1) * rowH end
            L.pos = {}
            local groups = {}
            for _, n in ipairs(nodes) do
                local col = n.branch and cols.branch[n.branch] or (n.spec and cols.spec[n.spec]) or cols.shared
                local key = n.tier .. "|" .. col[1] .. "|" .. col[2]
                groups[key] = groups[key] or { col = col, list = {} }
                table.insert(groups[key].list, n)
            end
            for _, g in pairs(groups) do
                local gx0, gx1 = x0 + inner * g.col[1], x0 + inner * g.col[2]
                local cnt = #g.list
                -- Keep siblings fairly close (not at the far edges of wide columns).
                local span = math.min(gx1 - gx0, cnt * S(150))
                local sx = gx0 + (gx1 - gx0 - span) * 0.5
                local cellW = span / cnt
                for i, n in ipairs(g.list) do
                    local cx = math.floor(sx + cellW * (i - 0.5))
                    local y = math.floor(top + (n.tier - 1) * rowH)
                    local bw = math.floor(math.min(cellW - S(6), S(130)))
                    local b = self.byNode[n.id]
                    b:SetPos(cx - math.floor(bw * 0.5), y)
                    b:SetSize(bw, sq + labelH)
                    L.pos[n.id] = { cx = cx, y = y, busOff = math.floor((i - (cnt + 1) * 0.5) * S(6)) }
                end
            end
        end
        tree:InvalidateLayout(true)
    end

    for _, c in ipairs(K.CATEGORIES) do
        local b = Kit.Button(bar, c.name, function()
            cur = c.id
            fill()
        end, { small = true, selected = function() return cur == c.id end })
        b:Dock(LEFT)
        b:SetWide(S(118))
        b:DockMargin(0, 0, S(6), 0)
    end
    fill()
end

local function addPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage and Menus.Kit) then return end
    Menus.AddPage("skills", {
        title = "Skills",
        order = 22,
        group = "character",
        build = build,
    })
end
addPage()
Rhylib.Hook.Add("InitPostEntity", "skills.page", addPage)
