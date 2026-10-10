--[[
    Small vector symbols (client) for roles, squad leader, radio operator,
    hails and pings, drawn in a 0-1 box: R = rect, P = convex polygon, C = disc, O = ring,
    L = thick line, A = arc (cx, cy, r, thickness, from, to in degrees,
    0 = right, -90 = up), S = star. A trailing true draws in bg (a cut-out).

        R.DrawIcon(name, x, y, size, col, bg)

    Add your own by putting a list in R.ICONS (cl_40_pings.lua adds the
    ping symbols this way). Polygons are re-wound if needed, since
    surface.DrawPoly only draws clockwise ones.
]]

local R = Rhylib.Radio

R.ICONS = {
    rifle = { { "R", .08, .42, .8, .12 }, { "P", { .08, .42, .3, .42, .24, .72, .1, .72 } }, { "R", .52, .54, .1, .2 } },
    bolt = { { "P", { .58, .06, .24, .56, .52, .56 } }, { "P", { .48, .44, .76, .44, .42, .94 } } },
    spear = { { "R", .08, .44, .56, .12 }, { "P", { .6, .24, .94, .5, .6, .76 } } },
    mag = { { "R", .36, .1, .28, .52 }, { "P", { .36, .62, .64, .62, .58, .9, .3, .9 } }, { "R", .42, .2, .16, .05, true }, { "R", .42, .32, .16, .05, true } },
    ammo = { { "R", .14, .36, .72, .5 }, { "R", .14, .24, .72, .08 }, { "R", .42, .5, .16, .14, true } },
    crosshair = { { "O", .5, .5, .3, .09 }, { "R", .45, .04, .1, .24 }, { "R", .45, .72, .1, .24 }, { "R", .04, .45, .24, .1 }, { "R", .72, .45, .24, .1 } },
    barrels = { { "R", .06, .3, .58, .1 }, { "R", .06, .45, .58, .1 }, { "R", .06, .6, .58, .1 }, { "R", .62, .24, .3, .52 } },
    rocket = { { "R", .14, .4, .54, .2 }, { "P", { .68, .34, .96, .5, .68, .66 } }, { "P", { .04, .26, .26, .4, .14, .4 } }, { "P", { .14, .6, .26, .6, .04, .74 } } },
    door = { { "R", .2, .08, .5, .84 }, { "R", .28, .16, .34, .68, true }, { "C", .54, .52, .05 }, { "S", .84, .2, .14 } },
    grenade = { { "C", .5, .6, .3 }, { "R", .4, .16, .2, .18 }, { "R", .56, .2, .24, .07 } },
    cross = { { "R", .38, .1, .24, .8 }, { "R", .1, .38, .8, .24 } },
    wings = { { "P", { .5, .12, .66, .8, .5, .66, .34, .8 } }, { "L", .06, .66, .38, .4, .1 }, { "L", .94, .66, .62, .4, .1 } },
    star = { { "S", .5, .54, .46 } },
    shield = { { "P", { .16, .1, .84, .1, .84, .5, .5, .92, .16, .5 } }, { "R", .28, .3, .44, .08, true } },
    leader = { { "L", .1, .5, .5, .2, .14 }, { "L", .5, .2, .9, .5, .14 }, { "L", .1, .86, .5, .56, .14 }, { "L", .5, .56, .9, .86, .14 } },
    ro = { { "C", .2, .8, .12 }, { "A", .2, .8, .38, .11, -90, 0 }, { "A", .2, .8, .68, .11, -90, 0 } },
    hail = { { "C", .5, .55, .14 }, { "A", .5, .55, .32, .09, -150, -30 }, { "A", .5, .55, .5, .09, -145, -35 } },
}

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

local function circle(cx, cy, r, seg)
    local pts = {}
    for i = 0, seg - 1 do
        local a = i / seg * math.pi * 2
        pts[#pts + 1] = { x = cx + math.cos(a) * r, y = cy + math.sin(a) * r }
    end
    return pts
end

local function arc(cx, cy, r, t, a0, a1, seg)
    local ro, ri = r + t * 0.5, r - t * 0.5
    for i = 0, seg - 1 do
        local p = math.rad(a0 + (a1 - a0) * i / seg)
        local q = math.rad(a0 + (a1 - a0) * (i + 1) / seg)
        poly({ { x = cx + math.cos(p) * ro, y = cy + math.sin(p) * ro }, { x = cx + math.cos(q) * ro, y = cy + math.sin(q) * ro },
            { x = cx + math.cos(q) * ri, y = cy + math.sin(q) * ri }, { x = cx + math.cos(p) * ri, y = cy + math.sin(p) * ri } })
    end
end

local function line(x1, y1, x2, y2, t)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0 then return end
    local nx, ny = -dy / len * t * 0.5, dx / len * t * 0.5
    poly({ { x = x1 + nx, y = y1 + ny }, { x = x2 + nx, y = y2 + ny }, { x = x2 - nx, y = y2 - ny }, { x = x1 - nx, y = y1 - ny } })
end

local BG = Color(10, 12, 14)

-- R.DrawIcon(name, x, y, s, col, bg): draws R.ICONS[name] in an s-by-s
-- box at x, y in colour col; cut-out parts use bg (default near black).
-- Unknown names draw nothing.
-- Example: Rhylib.Radio.DrawIcon("hail", 10, 10, 32, Color(242, 193, 78))
function R.DrawIcon(name, x, y, s, col, bg)
    local g = R.ICONS[name]
    if not g then return end
    draw.NoTexture()
    for _, p in ipairs(g) do
        local kind = p[1]
        local cut = p[#p] == true
        surface.SetDrawColor(cut and (bg or BG) or col)
        if kind == "R" then
            surface.DrawRect(math.floor(x + p[2] * s), math.floor(y + p[3] * s), math.max(1, math.floor(p[4] * s + 0.5)), math.max(1, math.floor(p[5] * s + 0.5)))
        elseif kind == "P" then
            local pts = {}
            for i = 1, #p[2], 2 do pts[#pts + 1] = { x = x + p[2][i] * s, y = y + p[2][i + 1] * s } end
            poly(pts)
        elseif kind == "C" then
            poly(circle(x + p[2] * s, y + p[3] * s, p[4] * s, 14))
        elseif kind == "O" then
            arc(x + p[2] * s, y + p[3] * s, p[4] * s, p[5] * s, 0, 360, 16)
        elseif kind == "A" then
            arc(x + p[2] * s, y + p[3] * s, p[4] * s, p[5] * s, p[6], p[7], 6)
        elseif kind == "L" then
            line(x + p[2] * s, y + p[3] * s, x + p[4] * s, y + p[5] * s, p[6] * s)
        elseif kind == "S" then
            local cx, cy, r = x + p[2] * s, y + p[3] * s, p[4] * s
            local core = {}
            for i = 0, 4 do
                local a = (i / 5) * math.pi * 2 - math.pi * 0.5
                local a1, a2 = a - math.pi / 5, a + math.pi / 5
                local l = { x = cx + math.cos(a1) * r * 0.42, y = cy + math.sin(a1) * r * 0.42 }
                local rr = { x = cx + math.cos(a2) * r * 0.42, y = cy + math.sin(a2) * r * 0.42 }
                poly({ l, { x = cx + math.cos(a) * r, y = cy + math.sin(a) * r }, rr })
                core[#core + 1] = l
            end
            poly(core)
        end
    end
end

-- R.DrawTags(ply, x, y, s, col): the symbols shown next to a player's
-- name: leader (gold), RO (blue), then the role (col). Returns the width
-- used.
function R.DrawTags(ply, x, y, s, col)
    local dx = 0
    if R.IsLeader(ply) then
        R.DrawIcon("leader", x, y, s, R.COL.hail)
        dx = dx + s + math.floor(s * 0.25)
    end
    if R.IsRO(ply) then
        R.DrawIcon("ro", x + dx, y, s, R.COL.ch1)
        dx = dx + s + math.floor(s * 0.25)
    end
    local role = R.ROLES[R.RoleOf(ply)]
    R.DrawIcon(role[3], x + dx, y, s, col or color_white)
    return dx + s
end
