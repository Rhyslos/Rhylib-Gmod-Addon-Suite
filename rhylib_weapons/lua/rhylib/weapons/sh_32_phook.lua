--[[
    Personal grappling hook (SWEP rhylib_grapple_personal): a short hook
    that only lifts its user up. Shared and predicted, like rope climbing.

    Fire (LMB, from the ground): the hook grips where you look, within
    phookRange (15 m), if that's somewhere a grapple hook can grip
    (Grapple.CanGrip) and at least phookMinRise above your feet:
      - a wall: you hang just below the hook, facing the wall;
      - a ceiling or overhang: you hang straight under it;
      - the top of something (a roof, a ledge): you hang at its edge on
        the side you came from (the edge is found like a rope's).
    Then you're reeled straight there at phookSpeed and hang. While hanging:
      W      over the top, if there's room to stand up there (a ledge)
      Jump   let go (a small push off the wall)
      E / S  let go
    Switching weapons (the next movement tick sees it, on both realms),
    getting downed or knocked, and taking grapple hitsToFall hits also let
    go (sv_30_grapple.lua).

    Why it can't be a bungee: the reel sets your speed directly each tick
    (no spring, nothing stored), letting go keeps no upward or sideways
    speed (you drop), it only fires from the ground (no chaining in the
    air), and after letting go it waits phookCooldown seconds (and, as
    always, fires only from the ground). Reeling longer than the distance needs
    (something in the way) lets go.

    Player state (core DT seeds): Int grapple.phook (0 off, 1 reeling,
    2 hanging, 3 climbing over), Vector grapple.phookAt (where your feet
    go), grapple.phookHook (the hook, drawn), grapple.phookLedge (where you
    stand after climbing over; zero = none), Float grapple.phookT (when the
    reel must be done by).

    Realm: shared (client draws the line). Config module "grapple"
    (phook* keys). Public: G.PhookOn(ply), G.PhookRelease(ply, mv, push),
    G.PhookAim(ply) -> foot target, hook, ledge or nil + why.
]]

local W = Rhylib.Weapons
local G = W.Grapple
local Config = Rhylib.Config
local DT = Rhylib.DT

G.DT_PH = DT and DT.Claim("Int", "grapple.phook", 31) or 31
G.DT_PH_AT = DT and DT.Claim("Vector", "grapple.phookAt", 31) or 31
G.DT_PH_HOOK = DT and DT.Claim("Vector", "grapple.phookHook", 30) or 30
G.DT_PH_LEDGE = DT and DT.Claim("Vector", "grapple.phookLedge", 29) or 29
G.DT_PH_T = DT and DT.Claim("Float", "grapple.phookT", 21) or 21
G.PH_CLASS = "rhylib_grapple_personal"

Config.Register("grapple", "phookRange", 787, "Personal grappling hook: reach (units, 787 = 15 m)")
Config.Register("grapple", "phookSpeed", 420, "Personal grappling hook: how fast it reels you up (units/s)")
Config.Register("grapple", "phookMinRise", 48, "Personal grappling hook: how far above your feet the hang point must be (it only lifts)")
Config.Register("grapple", "phookCooldown", 2, "Personal grappling hook: seconds after letting go before it fires again")

local UP = Vector(0, 0, 1)
local ZERO = Vector(0, 0, 0)
local HANG = 66          -- feet this far under the hook while hanging
local OFF_WALL = 20      -- body this far out from the wall
local HULL_MIN, HULL_MAX = Vector(-16, -16, 0), Vector(16, 16, 72)
local gravityVar = GetConVar("sv_gravity")

local function cfg(k) return Config.Get("grapple", k) end

-- Traces skip the player and zipline far-end boxes (server-only: the
-- client can't see them, and predicted traces must agree).
local skipFor
local function skip(e) return e ~= skipFor and e:GetClass() ~= "rhylib_zipline_end" end
local tr = {}
local td = { output = tr, mask = MASK_PLAYERSOLID, filter = skip }
local function trace(a, b, ply)
    td.start, td.endpos, skipFor = a, b, ply
    util.TraceLine(td)
    return tr
end
local htr = {}
local htd = { output = htr, mask = MASK_PLAYERSOLID, mins = HULL_MIN, maxs = HULL_MAX, filter = skip }
local function roomToStand(pos, ply)
    htd.start, htd.endpos, skipFor = pos + UP * 2, pos + UP * 2, ply
    util.TraceHull(htd)
    return not htr.StartSolid and not htr.Hit
end
local function flat(v)
    local f = Vector(v.x, v.y, 0)
    if f:LengthSqr() < 0.0001 then return nil end
    f:Normalize()
    return f
end

-- G.PhookOn(ply): 0 off, 1 reeling, 2 hanging, 3 climbing over.
function G.PhookOn(ply)
    return ply:GetDTInt(G.DT_PH)
end

-- G.PhookAim(ply): where a shot now would take ply. Returns at (feet),
-- hook, ledge (or nil) - or nil and a message.
function G.PhookAim(ply)
    local eye = ply:GetShootPos()
    local t = trace(eye, eye + ply:GetAimVector() * cfg("phookRange"), ply)
    if not t.Hit or t.HitSky then return nil, nil, nil, "Out of reach" end
    if not G.CanGrip(t) then return nil, nil, nil, "The hook can't grip that" end
    local h, n = Vector(t.HitPos), Vector(t.HitNormal)
    local at, ledge
    if n.z >= 0.7 then
        -- On top of something: hang at its edge on the near side.
        local back = flat(ply:GetPos() - h)
        if not back then return nil, nil, nil, "No edge to hang from" end
        local edge
        for step = 8, 256, 8 do
            local q = h + back * step + UP * 4
            if trace(q - back * 8, q, ply).Hit then break end
            if not trace(q, q - UP * 24, ply).Hit then edge = h + back * (step - 8) break end
        end
        if not edge then return nil, nil, nil, "No edge to hang from" end
        at = edge + back * OFF_WALL - UP * HANG
        h = edge + UP * 2
        if roomToStand(edge - back * 24, ply) then ledge = edge - back * 24 end
    elseif n.z <= -0.7 then
        at = h - UP * (HANG + 6)
    else
        local wn = flat(n)
        if not wn then return nil, nil, nil, "The hook can't grip that" end
        at = h + wn * OFF_WALL - UP * HANG
        -- A ledge just above the hook to climb onto?
        local over = h - wn * 24 + UP * 80
        local down = trace(over, over - UP * 100, ply)
        if down.Hit and not down.StartSolid and down.HitNormal.z > 0.7 and down.HitPos.z >= h.z - 8 then
            local stand = Vector(down.HitPos)
            if roomToStand(stand, ply) then ledge = stand + UP * 2 end
        end
    end
    if at.z - ply:GetPos().z < cfg("phookMinRise") then return nil, nil, nil, "Aim higher: it only lifts you up" end
    return at, h, ledge
end

-- G.PhookStart(ply): fire (predicted, from the SWEP). true if it gripped.
function G.PhookStart(ply)
    if G.PhookOn(ply) ~= 0 then return false end
    if G.Attached(ply) or G.ZipOn(ply) then return false, "Not while on a rope or zipline" end
    if not ply:OnGround() then return false, "Only from the ground" end
    local at, hook, ledge, why = G.PhookAim(ply)
    if not at then return false, why end
    ply:SetDTVector(G.DT_PH_AT, at)
    ply:SetDTVector(G.DT_PH_HOOK, hook)
    ply:SetDTVector(G.DT_PH_LEDGE, ledge or ZERO)
    ply:SetDTFloat(G.DT_PH_T, CurTime() + ply:GetPos():Distance(at) / cfg("phookSpeed") + 1)
    ply:SetDTInt(G.DT_PH, 1)
    return true
end

-- G.PhookRelease(ply, mv, push): let go. You keep no upward or sideways
-- speed (only falling, plus push if given).
function G.PhookRelease(ply, mv, push)
    if ply:GetDTInt(G.DT_PH) == 0 then return end
    ply:SetDTInt(G.DT_PH, 0)
    if SERVER then ply.rhylibLineHits = nil end
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep:GetClass() == G.PH_CLASS then
        wep:SetNextPrimaryFire(CurTime() + cfg("phookCooldown"))
    end
    if mv then
        local v = mv:GetVelocity()
        local out = Vector(0, 0, math.min(v.z, 0))
        if push then out = out + push end
        mv:SetVelocity(out)
    elseif SERVER then
        -- (outside movement: knocked off, downed) just drop
        ply:SetLocalVelocity(Vector(0, 0, math.min(ply:GetVelocity().z, 0)))
    end
end

Rhylib.Hook.Add("SetupMove", "weapons.phook", function(ply, mv)
    local st = ply:GetDTInt(G.DT_PH)
    if st == 0 then return end
    local wep = ply:GetActiveWeapon()
    if not ply:Alive() or ply:GetMoveType() ~= MOVETYPE_WALK or ply:InVehicle()
        or not (IsValid(wep) and wep:GetClass() == G.PH_CLASS) then
        G.PhookRelease(ply, mv)
        return
    end
    local at, hook = ply:GetDTVector(G.DT_PH_AT), ply:GetDTVector(G.DT_PH_HOOK)
    local wall = flat(hook - at) or ZERO   -- (toward the wall)
    if mv:KeyPressed(IN_JUMP) then
        G.PhookRelease(ply, mv, -wall * 100)
        return
    end
    if mv:KeyPressed(IN_USE) or (st == 2 and mv:GetForwardSpeed() < 0) then
        G.PhookRelease(ply, mv)
        return
    end

    local dt = FrameTime()
    local origin = mv:GetOrigin()
    local vel
    if st == 3 then
        -- Over the top: straight up past the edge, then onto the ledge.
        local ledge = ply:GetDTVector(G.DT_PH_LEDGE)
        if origin.z < ledge.z + 2 then
            vel = Vector(0, 0, 260)
        else
            local to = ledge - origin
            to.z = 0
            local dist = to:Length()
            if dist < 6 then
                G.PhookRelease(ply, mv)
                return
            end
            vel = to * (math.min(dist / dt, 220) / dist)
        end
        if CurTime() > ply:GetDTFloat(G.DT_PH_T) then   -- (stuck going over: let go)
            G.PhookRelease(ply, mv)
            return
        end
    else
        local to = at - origin
        local dist = to:Length()
        if st == 1 then
            if dist < 8 then
                ply:SetDTInt(G.DT_PH, 2)
                st = 2
            elseif CurTime() > ply:GetDTFloat(G.DT_PH_T) then
                G.PhookRelease(ply, mv)   -- (something was in the way)
                return
            end
        end
        if st == 2 and mv:GetForwardSpeed() > 0 and ply:GetDTVector(G.DT_PH_LEDGE) ~= ZERO then
            ply:SetDTInt(G.DT_PH, 3)
            ply:SetDTFloat(G.DT_PH_T, CurTime() + 2)
        end
        -- Straight at the hang point at a fixed speed: nothing stored, no bounce.
        local speed = st == 1 and cfg("phookSpeed") or 200
        vel = dist > 0.5 and to * (math.min(dist / dt, speed) / dist) or Vector(0, 0, 0)
    end
    local g = gravityVar:GetFloat() * (ply:GetGravity() ~= 0 and ply:GetGravity() or 1)
    vel.z = vel.z + g * dt   -- cancel this tick's gravity
    mv:SetVelocity(vel)
    mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(bit.bor(IN_JUMP, IN_SPEED, IN_DUCK))))
end, -5)

-- Hanging pose: the jump pose (legs off the ground).
Rhylib.Hook.Add("CalcMainActivity", "weapons.phook", function(ply)
    if ply:GetDTInt(G.DT_PH) ~= 0 then return ACT_MP_JUMP, -1 end
end)

if CLIENT then
    -- The line from the hand to the hook (everyone hooked, in sight).
    local COL = Color(20, 20, 22)
    local COL_HOOK = Color(58, 60, 62)
    local HOOK_MINS, HOOK_MAXS = Vector(-2, -2, -2), Vector(2, 2, 2)
    local ANG0 = Angle(0, 0, 0)
    local handBone = {}
    Rhylib.Hook.Add("PostDrawTranslucentRenderables", "weapons.phook", function(depth, sky)
        if depth or sky then return end
        local me = LocalPlayer()
        local first = not me:ShouldDrawLocalPlayer()
        for _, p in ipairs(player.GetAll()) do
            if p:GetDTInt(G.DT_PH) ~= 0 and not p:IsDormant() then
                local hook = p:GetDTVector(G.DT_PH_HOOK)
                local hand
                if p == me and first then
                    hand = me:GetShootPos() - UP * 14 + me:EyeAngles():Right() * 8
                else
                    local mdl = p:GetModel() or ""
                    local b = handBone[mdl]
                    if b == nil then
                        b = p:LookupBone("ValveBiped.Bip01_R_Hand") or false
                        handBone[mdl] = b
                    end
                    hand = b and p:GetBonePosition(b) or p:GetPos() + UP * 60
                end
                render.SetColorMaterial()
                render.DrawBeam(hand, hook, 1.2, 0, 1, COL)
                render.DrawBox(hook, ANG0, HOOK_MINS, HOOK_MAXS, COL_HOOK)
            end
        end
    end)
end
