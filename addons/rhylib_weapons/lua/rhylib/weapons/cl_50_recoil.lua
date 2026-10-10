--[[
    View recoil: each shot really turns your aim (up, and a little sideways),
    so the crosshair always shows where the next shot goes. Pull down to
    control it. When you stop firing, part of the climb settles back, minus
    whatever you already pulled down yourself.

    Client only: the shooter's view angles change, and the server simply
    receives them in the normal user command. Per gun: SWEP.Recoil =
      { up = degrees per shot, side = random sideways, bias = -1..1 (left/right
        lean), recover = share of the climb that settles back, aimMult }
    Third person turns the camera (TP.camAng) instead; its aim correction
    then follows the camera.
    Config weapons recoilMult scales every gun; rhylib_skills
    K.RecoilMult scales per player.
]]

local W = Rhylib.Weapons
W.Recoil = W.Recoil or {}
local R = W.Recoil

local APPLY_TIME = 0.05      -- a kick lands over about this long (smooth, not a snap)
local RECOVER_DELAY = 0.12   -- settle back once you've stopped firing this long
local RECOVER_TIME = 0.22

local pendP, pendY = 0, 0    -- kick still to apply (pitch: negative = up)
local back = 0               -- climb that will settle back (degrees, positive)
local lastShot = 0
local lastPitch              -- pitch after our last change, to see your own mouse pull

-- R.Kick(wep): adds one shot's kick (client). Called by rhylib_base
-- FireShot on the first prediction (singleplayer: SWEP:RhylibRecoilKick).
function R.Kick(wep)
    local cfg = wep.Recoil
    if not cfg then return end
    local m = (wep.GetAiming and wep:GetAiming()) and (cfg.aimMult or 0.65) or 1
    m = m * (Rhylib.Config.Get("weapons", "recoilMult") or 1)
    local K = Rhylib.Skills
    if K and K.RecoilMult then m = m * K.RecoilMult(wep:GetOwner(), wep) end   -- (Steady barrels)
    local up = (cfg.up or 0.5) * m * math.Rand(0.85, 1.15)
    local side = (cfg.side or 0.2) * m
    pendP = pendP - up
    pendY = pendY + math.Rand(-side, side) + side * (cfg.bias or 0)
    back = math.min(back + up * (cfg.recover or 0.6), 15)
    lastShot = CurTime()
end

local function tpActive()
    local TP = Rhylib.ThirdPerson
    return TP and TP.Active and TP.Active() and TP.camAng and TP
end

-- Before the third-person aim correction (which reads the camera angle).
Rhylib.Hook.Add("CreateMove", "weapons.recoil", function(cmd)
    if pendP == 0 and pendY == 0 and back == 0 then
        lastPitch = nil
        return
    end
    local ply = LocalPlayer()
    if not ply:Alive() then
        pendP, pendY, back, lastPitch = 0, 0, 0, nil
        return
    end
    local TP = tpActive()
    local ang = TP and TP.camAng or cmd:GetViewAngles()

    -- Your own pull-down counts toward the settle-back.
    if lastPitch then
        local pulled = ang.p - lastPitch
        if pulled > 0 then back = math.max(0, back - pulled) end
    end

    local ft = FrameTime()
    local f = math.min(1, ft / APPLY_TIME)
    local dp, dy = pendP * f, pendY * f
    pendP, pendY = pendP - dp, pendY - dy
    if math.abs(pendP) < 0.001 then pendP = 0 end
    if math.abs(pendY) < 0.001 then pendY = 0 end

    if CurTime() - lastShot > RECOVER_DELAY and back > 0 then
        local r = back * math.min(1, ft / RECOVER_TIME)
        if back < 0.01 then r = back end
        back = back - r
        dp = dp + r
    end

    ang.p = math.Clamp(ang.p + dp, -89, 89)
    ang.y = math.NormalizeAngle(ang.y + dy)
    if not TP then cmd:SetViewAngles(ang) end
    lastPitch = ang.p
end, -20)
