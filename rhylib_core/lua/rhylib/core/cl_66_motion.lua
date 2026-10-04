--[[
    Walking feel without moving the world (client, first person).

    The camera moving on its own (bob, roll, sway) makes many people
    motion sick, so the default effects move things in front of you:

      1. Gun bob (rhylib_gunbob, on, rhylib_gunbob_scale): the gun and hands
         sway and dip with your steps (half the first version: it mixes
         with footstep feel); the view stays put.
      (2. Visor sway was tried and removed: the HUD moving opened gaps at
         the screen edges, and moving only part of it looked wrong.)
      3. Landing dip (rhylib_landdip, on): the gun dips when you land
         from a jump or fall.
      4. Footsteps (on; rhylib_footstepfeel, rhylib_footstepfeel_scale): your own footsteps
         a bit louder and a stronger, smooth gun sway and roll with each
         step (eased in and out, no jolts).
    Off unless turned on:
      5. Camera bob (rhylib_camerabob, rhylib_camerabob_scale): up/down
         only, a small dip on each footstep, only while sprinting; no roll,
         no sideways sway.

    Steps come from the walk cycle while moving on the ground; footstep
    impulses (4, 5) from the walk cycle (a step every half turn); the louder
    footstep sound from PlayerFootstep. Settings > HUD.
]]

local L = Rhylib.Lying

local function cv(name, def, desc) return CreateClientConVar(name, def, true, false, desc) end
local cvGun = cv("rhylib_gunbob", "1", "Gun and hands sway with your steps")
local cvGunScale = cv("rhylib_gunbob_scale", "1", "Gun sway strength (0-2)")
local cvLand = cv("rhylib_landdip", "1", "Gun dips when you land")
-- (new names: footstep feel is on by default now, saved "off" from before shouldn't stick)
local cvSteps = cv("rhylib_footstepfeel", "1", "Louder own footsteps and a stronger, smooth gun sway with each step")
local cvStepsScale = cv("rhylib_footstepfeel_scale", "1", "Footstep effect strength (0-2)")
local cvCam = cv("rhylib_camerabob", "0", "Camera dips a little on each step while sprinting (up/down only)")
local cvCamScale = cv("rhylib_camerabob_scale", "1", "Camera bob strength (0-2)")

local M = {}
L.motion = M

-- Walk cycle: phase advances with speed on the ground; amt eases to 0-1.5.
M.phase, M.amt = 0, 0
-- Springs (value, velocity) for the landing dip and camera step dip.
local land = { 0, 0 }
local camDip = { 0, 0 }
local wasGround, lastZVel = true, 0

-- (substeps of at most 1/60 s: stable at any frame rate)
local function spring(s, ft, stiff, damp)
    local n = math.max(1, math.ceil(ft * 60))
    local h = ft / n
    for _ = 1, n do
        s[2] = s[2] + (-s[1] * stiff - s[2] * damp) * h
        s[1] = s[1] + s[2] * h
    end
end

local function firstPerson(ply)
    return IsValid(ply) and ply:Alive() and not ply:ShouldDrawLocalPlayer() and not L.BodyCamOn() and not L.ThirdPersonOn()
end

-- Update once a frame.
Rhylib.Hook.Add("Think", "core.motion", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local ft = math.min(FrameTime(), 0.1)
    local onGround = ply:OnGround() and ply:GetMoveType() == MOVETYPE_WALK
    local speed = ply:GetVelocity():Length2D()
    local want = onGround and math.Clamp(speed / 220, 0, 1.5) or 0
    M.amt = M.amt + (want - M.amt) * (1 - math.exp(-ft * 8))
    if M.amt > 0.01 then
        M.phase = M.phase + ft * (5 + speed / 60)
        -- A step every half turn of the cycle (doesn't rely on footstep sounds).
        local step = math.floor(M.phase / math.pi)
        if step ~= M.step then
            M.step = step
            if onGround and speed > 60 then
                if cvCam:GetBool() and ply:KeyDown(IN_SPEED) and speed > 150 then
                    camDip[2] = camDip[2] - 23 * math.Clamp(cvCamScale:GetFloat(), 0, 2)
                end
            end
        end
    end

    -- Landing: a dip by how hard you came down.
    if onGround and not wasGround and lastZVel < -120 and cvLand:GetBool() then
        land[2] = land[2] - math.Clamp(-lastZVel / 500, 0.3, 1.5) * 40
    end
    wasGround = onGround
    lastZVel = ply:GetVelocity().z

    -- Footstep feel: a smooth extra sway that eases in and out with walking.
    local want4 = cvSteps:GetBool() and math.Clamp(cvStepsScale:GetFloat(), 0, 2) * M.amt or 0
    M.steps = (M.steps or 0) + (want4 - (M.steps or 0)) * (1 - math.exp(-ft * 4))

    spring(land, ft, 140, 14)
    spring(camDip, ft, 160, 16)
end)

-- Footstep feel (4): your own footstep sounds a bit louder (once per step,
-- even if prediction calls this more than once).
local lastStepSound = 0
Rhylib.Hook.Add("PlayerFootstep", "core.motion", function(ply, pos, foot, snd, volume)
    if ply ~= LocalPlayer() or not cvSteps:GetBool() then return end
    local now = RealTime()
    if now - lastStepSound < 0.12 then return end
    lastStepSound = now
    local k = math.Clamp(cvStepsScale:GetFloat(), 0, 2)
    if k > 0 then ply:EmitSound(snd, 0, math.random(92, 100), math.min(volume * 0.6 * k, 1), CHAN_STATIC) end
end)

-- 1, 3, 4: the gun. Built on the gamemode's (and weapon's) own placement.
Rhylib.Hook.Add("CalcViewModelView", "core.motion", function(wep, vm, oldPos, oldAng, pos, ang)
    local ply = LocalPlayer()
    if not firstPerson(ply) then return end
    -- (half the first version's sway: it mixes with footstep feel now)
    local gun = cvGun:GetBool() and M.amt * 0.5 * math.Clamp(cvGunScale:GetFloat(), 0, 2) or 0
    local st = M.steps or 0
    if gun < 0.01 and st < 0.01 and math.abs(land[1]) < 0.01 then return end
    local p, a = GAMEMODE:CalcViewModelView(wep, vm, oldPos, oldAng, pos, ang)
    p, a = p or pos, a or ang
    local s = math.sin(M.phase)
    local right, up = a:Right(), a:Up()
    -- Sway left/right once per two steps, dip on each step, a touch of turn.
    -- Footstep feel: the same curves, bigger, plus a soft roll with each
    -- step (continuous, so no jolts).
    local s2 = s * s
    local side = s * (0.45 * gun + 0.6 * st)
    local dip = -math.abs(s) * 0.55 * gun - s2 * 0.6 * st + land[1] * 0.9
    p = p + right * side + up * dip
    a = Angle(a.p + math.abs(s) * 0.5 * gun + s2 * 0.8 * st - land[1] * 1.2, a.y + s * 0.4 * gun, a.r + s * 2 * st)
    return p, a
end, -50)

-- 5: camera bob, only when turned on: a dip from footsteps while sprinting.
Rhylib.Hook.Add("CalcView", "core.motion", function(ply, pos, angles, fov, znear, zfar)
    if ply ~= LocalPlayer() or not cvCam:GetBool() or not firstPerson(ply) then return end
    if math.abs(camDip[1]) < 0.01 then return end
    local view = (GAMEMODE.CalcView and GAMEMODE:CalcView(ply, pos, angles, fov, znear, zfar)) or { origin = pos, angles = angles, fov = fov }
    view.origin = (view.origin or pos) + Vector(0, 0, camDip[1])
    return view
end, -40)

-- In the settings menu (rhylib_menus).
Rhylib.Hook.Add("InitPostEntity", "core.motion.setting", function()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddSetting) then return end
    local function add(id, order, title, desc, kind, convar, extra)
        local t = { id = id, order = order, title = title, desc = desc, kind = kind, convar = convar }
        for k, v in pairs(extra or {}) do t[k] = v end
        Menus.AddSetting("HUD", t)
    end
    add("core.gunbob", 71, "Gun sway", "The gun and hands sway with your steps (the view stays still)", "toggle", "rhylib_gunbob")
    add("core.gunbobscale", 72, "Gun sway strength", "1 = normal", "slider", "rhylib_gunbob_scale", { min = 0, max = 2, decimals = 1 })
    add("core.landdip", 73, "Landing dip", "The gun dips when you land", "toggle", "rhylib_landdip")
    add("core.steps", 74, "Footstep feel", "Louder own footsteps and a stronger, smooth gun sway with each step", "toggle", "rhylib_footstepfeel")
    add("core.stepsscale", 75, "Footstep feel strength", "1 = normal", "slider", "rhylib_footstepfeel_scale", { min = 0, max = 2, decimals = 1 })
    add("core.camerabob", 76, "Camera bob", "A small up/down dip on each step while sprinting (can cause motion sickness)", "toggle", "rhylib_camerabob")
    add("core.camerabobscale", 77, "Camera bob strength", "1 = normal", "slider", "rhylib_camerabob_scale", { min = 0, max = 2, decimals = 1 })
end)
