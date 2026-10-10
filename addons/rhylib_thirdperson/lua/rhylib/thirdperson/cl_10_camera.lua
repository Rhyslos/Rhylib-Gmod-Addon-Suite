--[[
    Over-the-shoulder third person (client only, nothing is networked).

    P toggles it, N swaps shoulders, holding right mouse pulls the camera in.
    Console: rhylib_thirdperson 0/1, rhylib_thirdperson_side 1/-1,
             rhylib_thirdperson_key, rhylib_thirdperson_swapkey.

    How bolts land on the crosshair:
      The mouse turns the camera (camAng), not the player. Every frame we
      trace from the camera through the crosshair to find the aim point,
      then turn the player's real eye angles toward that point from the
      eyes and send them in the normal user command. The server just sees
      normal eye angles, so bolts, spread and lag compensation work
      exactly like first person. The trace starts level with the player,
      so walls behind your shoulder are ignored.

      If something is between your gun and the aim point (you can see
      past cover but your gun can't), a small marker shows where the bolt
      will actually hit.

    Adds Rhylib.ThirdPerson (TP): Mode, Wanted, Active, Toggle,
    SwapShoulder, and the live camera state (camAng, camPos, aimPoint,
    aimFrac, side, camHeight). Other addons read TP.Wanted() / TP.Active()
    (e.g. the body camera) and turn TP.camAng (rhylib_weapons view recoil).
    Hooks: InputMouseApply "thirdperson.mouse" (10, after the reload
    menu), CreateMove "thirdperson.aim", CalcView "thirdperson.camera" (0;
    the body camera at -50 runs first and returns nothing while this is
    wanted), PreDrawViewModel, HUDPaint, Think (keys). Nothing networked.
]]

Rhylib.ThirdPerson = Rhylib.ThirdPerson or {}
local TP = Rhylib.ThirdPerson

local enabledVar = CreateClientConVar("rhylib_thirdperson", "0", true, false, "Over-the-shoulder third person (0/1)")
local keyVar = CreateClientConVar("rhylib_thirdperson_key", "p", true, false, "Key that toggles third person")
local swapVar = CreateClientConVar("rhylib_thirdperson_swapkey", "n", true, false, "Key that swaps the shoulder")
local sideVar = CreateClientConVar("rhylib_thirdperson_side", "1", true, false, "1 = right shoulder, -1 = left shoulder")
local crouchVar = CreateClientConVar("rhylib_thirdperson_crouchup", "14", true, false, "How far the camera rises while crouching, so it clears the arms")
local crouchMoveVar = CreateClientConVar("rhylib_thirdperson_crouchmove", "0.5", true, false, "While moving crouched, how far the camera rises back toward standing height (0 = crouch height, 1 = standing)")
local allowedVar = GetConVar("rhylib_thirdperson_allowed")

local sensitivity = GetConVar("sensitivity")
local mYaw = GetConVar("m_yaw")
local mPitch = GetConVar("m_pitch")

-- Camera offsets from the eyes: back, sideways (toward the shoulder), up.
local HIP = { back = 62, side = 20, up = 3 }
local AIM = { back = 30, side = 15, up = 1 }
local HULL = Vector(5, 5, 5)
local FAR = 32768
local MIN_AIM_DIST = 40      -- closer than this, just aim where the camera looks

TP.camAng = nil              -- where the camera looks (driven by the mouse)
TP.camPos = nil              -- last camera position
TP.aimPoint = nil            -- world point under the crosshair
TP.aimFrac = 0               -- 0 hip, 1 aiming (smoothed)
TP.side = sideVar:GetFloat() -- smoothed shoulder side
TP.camHeight = nil           -- smoothed camera height above the feet

-- TP.Mode(): the server's mode: "choice", "third" or "first" (config
-- thirdperson mode; the old convar rhylib_thirdperson_allowed 0 = "first").
function TP.Mode()
    if allowedVar and not allowedVar:GetBool() then return "first" end
    local m = Rhylib.Config.Get("thirdperson", "mode")
    if m == "third" or m == "first" then return m end
    return "choice"
end

-- TP.Wanted(): third person wanted right now (mode, else the player's own
-- switch rhylib_thirdperson).
function TP.Wanted()
    local m = TP.Mode()
    if m == "first" then return false end
    return m == "third" or enabledVar:GetBool()
end

-- TP.Active(): third person really in use now: wanted, alive, not in a
-- vehicle or spectating, not looking through binoculars (rhylib_gear).
-- Example: if Rhylib.ThirdPerson and Rhylib.ThirdPerson.Active() then ... end
function TP.Active()
    local ply = LocalPlayer()
    return TP.Wanted() and IsValid(ply) and ply:Alive()
        and not ply:InVehicle() and ply:GetObserverMode() == OBS_MODE_NONE
        and not (ply:GetNW2Int("rhylib_optics", 0) ~= 0 and not ply:GetNW2Bool("rhylib_opticsFire", false))   -- (rhylib_gear: looking through binoculars; weapon mode keeps third person)
end

local function isAiming(ply)
    local wep = ply:GetActiveWeapon()
    return IsValid(wep) and wep.GetAiming and wep:GetAiming() or false
end

--------------------------------------------------------------------------
-- Mouse: turn the camera, not the player
--------------------------------------------------------------------------

-- Runs after the reload menu's handler (priority 10), which takes the
-- mouse while that menu is open.
Rhylib.Hook.Add("InputMouseApply", "thirdperson.mouse", function(cmd, x, y, ang)
    if not TP.Active() then return end
    if not TP.camAng then TP.camAng = Angle(ang.p, ang.y, 0) end

    local scale = sensitivity:GetFloat()
    local wep = LocalPlayer():GetActiveWeapon()
    if IsValid(wep) and wep.AdjustMouseSensitivity then
        scale = scale * (wep:AdjustMouseSensitivity() or 1)
    end

    local a = TP.camAng
    a.p = math.Clamp(a.p + y * scale * mPitch:GetFloat(), -89, 89)
    a.y = math.NormalizeAngle(a.y - x * scale * mYaw:GetFloat())
    return true
end, 10)

--------------------------------------------------------------------------
-- Aim correction
--------------------------------------------------------------------------

local traceResult = {}
local traceData = { mask = MASK_SHOT, output = traceResult }

local function updateAimPoint(ply)
    local eye = ply:EyePos()
    local camPos = TP.camPos or eye
    local dir = TP.camAng:Forward()

    -- Start the trace level with the player, not at the camera.
    local along = math.max((eye - camPos):Dot(dir), 0)
    traceData.start = camPos + dir * along
    traceData.endpos = traceData.start + dir * FAR
    traceData.filter = ply
    util.TraceLine(traceData)
    TP.aimPoint = traceResult.HitPos

    if TP.aimPoint:DistToSqr(eye) < MIN_AIM_DIST * MIN_AIM_DIST then
        return Angle(TP.camAng.p, TP.camAng.y, 0)
    end
    local ang = (TP.aimPoint - eye):Angle()
    ang:Normalize()
    return ang
end

Rhylib.Hook.Add("CreateMove", "thirdperson.aim", function(cmd)
    local ply = LocalPlayer()
    if not TP.Active() then
        -- Just switched off: face where the camera was looking.
        if TP.camAng then
            cmd:SetViewAngles(Angle(TP.camAng.p, TP.camAng.y, 0))
            TP.camAng, TP.camPos, TP.aimPoint = nil, nil, nil
        end
        return
    end
    if not TP.camAng then
        local va = cmd:GetViewAngles()
        TP.camAng = Angle(va.p, va.y, 0)
    end

    local aimAng = updateAimPoint(ply)
    local fm, sm = cmd:GetForwardMove(), cmd:GetSideMove()

    -- Noclip (admins flying around): no aim correction at all. The body
    -- looks exactly where the camera looks, so flying always goes straight
    -- where you point. Shots then leave the eyes along the camera line,
    -- a little off the crosshair, which doesn't matter while noclipping.
    if ply:GetMoveType() == MOVETYPE_NOCLIP then
        cmd:SetViewAngles(Angle(TP.camAng.p, TP.camAng.y, 0))
        return
    end

    -- Movement stays relative to the camera, not the corrected aim.
    local flying = ply:WaterLevel() >= 2
    if flying and (fm ~= 0 or sm ~= 0) then
        -- Swimming moves along the full 3D aim (pitch included),
        -- plus up/down along world Z. Find the inputs that, along the aim
        -- directions, add up to the move the camera asked for.
        local camF, camR = TP.camAng:Forward(), TP.camAng:Right()
        local want = camF * fm + camR * sm
        local aimF, aimR = aimAng:Forward(), aimAng:Right()

        local side = want:Dot(aimR)                 -- aim right is level, so this is exact
        local rest = want - aimR * side             -- lies in the plane of aim forward and world up
        local flat = math.sqrt(aimF.x * aimF.x + aimF.y * aimF.y)
        local fwd
        if flat > 0.05 then
            fwd = (rest.x * aimF.x + rest.y * aimF.y) / (flat * flat)
        else
            fwd = rest:Dot(aimF)                    -- looking straight up or down
        end
        local up = rest.z - fwd * aimF.z

        cmd:SetForwardMove(fwd)
        cmd:SetSideMove(side)
        cmd:SetUpMove(cmd:GetUpMove() + up)
    else
        -- Walking only uses the level direction, so turning the inputs by
        -- the yaw difference is exact.
        local d = math.rad(TP.camAng.y - aimAng.y)
        local c, s = math.cos(d), math.sin(d)
        cmd:SetForwardMove(fm * c + sm * s)
        cmd:SetSideMove(-fm * s + sm * c)
    end

    cmd:SetViewAngles(aimAng)
end)

--------------------------------------------------------------------------
-- Camera
--------------------------------------------------------------------------

local hullResult = {}
local hullData = { mins = -HULL, maxs = HULL, mask = MASK_SOLID_BRUSHONLY, output = hullResult }

Rhylib.Hook.Add("CalcView", "thirdperson.camera", function(ply, pos, angles, fov)
    if ply ~= LocalPlayer() or not TP.Active() or not TP.camAng then return end

    local ft = FrameTime()
    TP.aimFrac = math.Approach(TP.aimFrac, isAiming(ply) and 1 or 0, ft * 6)
    TP.side = math.Approach(TP.side, sideVar:GetFloat() >= 0 and 1 or -1, ft * 5)

    local f = TP.aimFrac
    local back = Lerp(f, HIP.back, AIM.back)
    local side = Lerp(f, HIP.side, AIM.side) * TP.side
    local up = Lerp(f, HIP.up, AIM.up)

    -- Camera height above the feet. It follows the engine's own crouch
    -- (the eye height as it moves between standing and crouched), so the
    -- camera goes down exactly as fast as you crouch, with no extra lag.
    -- The crouch raise (so the camera clears the arms) is blended in by
    -- how far down you are, so there's no dip. Moving while crouched, the
    -- crouch-walk animation lifts the arms into view, so the camera sits
    -- part of the way back up (crouchmove).
    local standH = ply:GetViewOffset().z
    local duckH = ply:GetViewOffsetDucked().z
    local eyeH = ply:GetCurrentViewOffset().z
    local frac = standH > duckH and math.Clamp((standH - eyeH) / (standH - duckH), 0, 1) or 0
    local lowH = duckH + crouchVar:GetFloat()
    if frac > 0 and ply:GetVelocity():Length2DSqr() > 400 then
        lowH = Lerp(crouchMoveVar:GetFloat(), lowH, standH)
    end
    local wantH = Lerp(frac, standH, lowH)
    -- Only a light smoothing, to take the edge off the crouch-walk switch.
    TP.camHeight = TP.camHeight and TP.camHeight + (wantH - TP.camHeight) * (1 - math.exp(-ft * 25)) or wantH

    local ang = TP.camAng
    local eye = ply:GetPos() + Vector(0, 0, TP.camHeight)
    local want = eye - ang:Forward() * back + ang:Right() * side + ang:Up() * up

    -- Pull the camera in so it never goes through walls. Start from the
    -- real eyes, which are always in open space (under a low ceiling the
    -- smoothed height can briefly be inside it).
    hullData.start = ply:EyePos()
    hullData.endpos = want
    hullData.filter = ply
    util.TraceHull(hullData)
    TP.camPos = hullResult.HitPos

    return { origin = TP.camPos, angles = Angle(ang.p, ang.y, 0), fov = fov, drawviewer = true }
end)

-- No floating first-person gun in third person.
Rhylib.Hook.Add("PreDrawViewModel", "thirdperson.hidevm", function()
    if TP.Active() then return true end
end)

--------------------------------------------------------------------------
-- HUD: crosshair and the blocked-shot marker
--------------------------------------------------------------------------

local COL_BLOCK = Color(255, 90, 80)
local COL_BLOCK_OUT = Color(0, 0, 0, 160)

Rhylib.Hook.Add("HUDPaint", "thirdperson.hud", function()
    if not TP.Active() or not TP.aimPoint then return end
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()

    -- Rhylib weapons draw their crosshair here in third person.
    if IsValid(wep) and wep.IsRhylib and Rhylib.Weapons and Rhylib.Weapons.Crosshair
        and not (wep.IsLowered and wep:IsLowered()) then
        Rhylib.Weapons.Crosshair.Draw(wep, ScrW() * 0.5, ScrH() * 0.5)
    end

    -- Is the path from the gun to the aim point blocked?
    local eye = ply:EyePos()
    traceData.start = eye
    traceData.endpos = TP.aimPoint
    traceData.filter = ply
    util.TraceLine(traceData)
    if not traceResult.Hit or traceResult.HitPos:DistToSqr(TP.aimPoint) < 24 * 24 then return end

    local scr = traceResult.HitPos:ToScreen()
    if not scr.visible then return end
    local s = ScrH() / 1080
    local r = 6 * s
    for _, col in ipairs({ COL_BLOCK_OUT, COL_BLOCK }) do
        local w = col == COL_BLOCK_OUT and 3 or 1
        surface.SetDrawColor(col)
        for o = -w + 1, w - 1 do
            surface.DrawLine(scr.x - r, scr.y - r + o, scr.x + r, scr.y + r + o)
            surface.DrawLine(scr.x - r, scr.y + r + o, scr.x + r, scr.y - r + o)
        end
    end
end)

--------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------

-- TP.Toggle(): flip rhylib_thirdperson (refused with a chat line in a fixed
-- server mode). Console: rhylib_thirdperson_toggle.
function TP.Toggle()
    local m = TP.Mode()
    if m == "first" then
        chat.AddText(Color(255, 190, 80), "This server is first person only.")
        return
    elseif m == "third" then
        chat.AddText(Color(255, 190, 80), "This server keeps everyone in third person.")
        return
    end
    RunConsoleCommand("rhylib_thirdperson", enabledVar:GetBool() and "0" or "1")
end

-- TP.SwapShoulder(): right <-> left shoulder. Console: rhylib_thirdperson_swap.
function TP.SwapShoulder()
    RunConsoleCommand("rhylib_thirdperson_side", sideVar:GetFloat() >= 0 and "-1" or "1")
end

concommand.Add("rhylib_thirdperson_toggle", TP.Toggle)
concommand.Add("rhylib_thirdperson_swap", TP.SwapShoulder)

local wasDown = {}
local function pressed(var)
    local code = input.GetKeyCode(var:GetString())
    local down = code and code > 0 and input.IsKeyDown(code)
    local edge = down and not wasDown[var]
    wasDown[var] = down
    return edge
end

Rhylib.Hook.Add("Think", "thirdperson.keys", function()
    local toggle, swap = pressed(keyVar), pressed(swapVar)
    if not (toggle or swap) then return end
    if gui.IsGameUIVisible() or gui.IsConsoleVisible() or LocalPlayer():IsTyping() or IsValid(vgui.GetKeyboardFocus()) then return end
    if toggle then TP.Toggle() end
    if swap and TP.Active() then TP.SwapShoulder() end
end)
