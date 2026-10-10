--[[
    Grapple hook, client side:
      - the landing marker that replaces the crosshair in grapple mode
        (turn it off with the grapple.showLanding config)
      - the short line from a climber's belt to the rope
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
    td.endpos = start + ply:GetAimVector() * Config.Get("grapple", "range")
    td.filter = ply
    util.TraceLine(td)

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
