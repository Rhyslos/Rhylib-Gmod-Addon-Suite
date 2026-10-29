--[[
    Grapple hook, client side:
      - the landing marker that replaces the crosshair in grapple mode
        (turn it off with the grapple.showLanding config)
      - the short line from a climber's belt to the rope
      - zipline mode: the far-end marker (length, both ways / one way
        down, "post" with the Zipline rigger skill) and the riders' hand line
    Realm: client.
]]

local W = Rhylib.Weapons
local G = W.Grapple
local X = W.Crosshair
local UI = Rhylib.UI
local Config = Rhylib.Config

local COL_OK = Color(151, 196, 89)
local COL_BAD = Color(226, 75, 74)
local COL_DIM = Color(244, 244, 240, 160)
local UNITS_TO_M = 0.01905

local tr = {}
local td = { output = tr, mask = MASK_SHOT }

local function ring(x, y, r, col, s)
    surface.DrawCircle(x, y, r, col.r, col.g, col.b, col.a)
    surface.DrawCircle(x, y, r + math.max(1, math.floor(s)), col.r, col.g, col.b, col.a)
end

-- Zipline mode: where the far end would go, the line's length and whether
-- it rides both ways (from the near post's top, like the server does).
-- The server checks the line for obstacles; this marker doesn't.
local gtr = {}
local gtd = { output = gtr, mask = MASK_PLAYERSOLID }
local function drawZipline(ply, start, x, y, s)
    local bad
    local foot
    local g = G.ZipGround(ply)
    if g then foot = Vector(g) else bad = "Stand on solid ground" end
    local b, post
    if not bad then
        if not tr.Hit or tr.HitSky then
            bad = "Out of range"
        elseif G.CanGrip(tr) and tr.HitNormal.z < 0.7 then
            b = tr.HitPos + tr.HitNormal * 3
        elseif G.HasRigger(ply) then
            if tr.HitNormal.z >= 0.7 and G.CanGrip(tr) then
                b, post = tr.HitPos + Vector(0, 0, G.POST_H), true
            else
                gtd.start, gtd.endpos, gtd.filter = tr.HitPos + tr.HitNormal * 4, tr.HitPos - Vector(0, 0, 2000), ply
                util.TraceLine(gtd)
                if gtr.Hit and gtr.HitNormal.z >= 0.7 and G.CanGrip(gtr) then
                    b, post = gtr.HitPos + Vector(0, 0, G.POST_H), true
                else
                    bad = "No ground there"
                end
            end
        else
            bad = G.CanGrip(tr) and "Needs a wall (or Zipline rigger)" or "Can't grip"
        end
    end
    local a = foot and foot + Vector(0, 0, G.POST_H)
    local deg, twoWay
    if b and not bad then
        local len = a:Distance(b)
        deg, twoWay = G.ZipSlope(a, b)
        if len < Config.Get("grapple", "zipMin") then bad = "Too short"
        elseif deg > Config.Get("grapple", "zipMaxAngle") then bad = "Too steep" end
    end
    if bad then
        ring(x, y, 12 * s, COL_BAD, s)
        draw.SimpleText(bad, UI.Font(14), x, y + 18 * s, COL_BAD, TEXT_ALIGN_CENTER)
        return
    end
    local sp = (post and b - Vector(0, 0, G.POST_H) or b):ToScreen()
    if not sp.visible then return end
    ring(sp.x, sp.y, 12 * s, COL_OK, s)
    local m = a:Distance(b) * UNITS_TO_M
    draw.SimpleText(string.format("%.0f m · %s", m, twoWay and "both ways" or "one way down"), UI.Font(14), sp.x, sp.y + 18 * s, COL_OK, TEXT_ALIGN_CENTER)
    if post then draw.SimpleText("post", UI.Font(12), sp.x, sp.y + 34 * s, COL_DIM, TEXT_ALIGN_CENTER) end
end

-- X.DrawGrapple(wep, x, y): called by the crosshair (X.Draw) instead of
-- the arcs while the weapon is in grapple mode; x, y = screen centre.
function X.DrawGrapple(wep, x, y)
    local ply = LocalPlayer()
    local s = ScrH() / 1080

    surface.SetDrawColor(COL_DIM)
    surface.DrawRect(x - 1, y - 1, 2, 2)

    if not Config.Get("grapple", "showLanding") then
        ring(x, y, 10 * s, COL_DIM, s)
        return
    end

    local start = ply:GetShootPos()
    td.start = start
    td.endpos = start + ply:GetAimVector() * G.Range(ply)
    td.filter = ply
    util.TraceLine(td)

    if wep.InZiplineMode and wep:InZiplineMode() then
        return drawZipline(ply, start, x, y, s)
    end

    if G.CanGrip(tr) then
        local sp = tr.HitPos:ToScreen()
        if sp.visible then
            ring(sp.x, sp.y, 12 * s, COL_OK, s)
            local m = tr.HitPos:Distance(start) * UNITS_TO_M
            draw.SimpleText(string.format("%.0f m", m), UI.Font(14), sp.x, sp.y + 18 * s, COL_OK, TEXT_ALIGN_CENTER)
        end
    else
        ring(x, y, 12 * s, COL_BAD, s)
        draw.SimpleText(tr.Hit and "Can't grip" or "Out of range", UI.Font(14), x, y + 18 * s, COL_BAD, TEXT_ALIGN_CENTER)
    end
end

-- Zipline riders: a short line from the hands up to the cable.
local handBone = {}
local COL_CABLE = Color(20, 20, 22)
Rhylib.Hook.Add("PostPlayerDraw", "weapons.zipline", function(ply)
    local z = ply:GetDTEntity(G.DT_ZIP)
    if not IsValid(z) then return end
    local d = z:GetZipData()
    if not d then return end
    local mdl = ply:GetModel() or ""
    local bone = handBone[mdl]
    if bone == nil then
        bone = ply:LookupBone("ValveBiped.Bip01_R_Hand") or false
        handBone[mdl] = bone
    end
    local hand = bone and ply:GetBonePosition(bone) or ply:GetPos() + Vector(0, 0, 64)
    render.SetColorMaterial()
    render.DrawBeam(hand, d.a + d.dir * ply:GetDTFloat(G.DT_S), 1.4, 0, 1, COL_CABLE)
end)

-- Belt line ---------------------------------------------------------------

local COL_ROPE = Color(14, 14, 14)  -- same black as the rope
local pelvisBone = {}

Rhylib.Hook.Add("PostPlayerDraw", "weapons.grapple", function(ply)
    local rope = ply:GetDTEntity(G.DT_ROPE)
    if not IsValid(rope) then return end
    local d = rope:GetRopeData()
    if not d then return end

    local mdl = ply:GetModel() or ""
    local bone = pelvisBone[mdl]
    if bone == nil then
        bone = ply:LookupBone("ValveBiped.Bip01_Pelvis") or false
        pelvisBone[mdl] = bone
    end
    local belt = bone and ply:GetBonePosition(bone) or ply:GetPos() + Vector(0, 0, 38)

    render.SetColorMaterial()
    render.DrawBeam(belt, G.PosAt(d, ply:GetDTFloat(G.DT_S), false), 1.8, 0, 1, COL_ROPE)
end)
