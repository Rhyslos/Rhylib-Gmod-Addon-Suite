--[[
    Freelook (client only, nothing networked): the freelook key
    (rhylib_freelook_key, default middle mouse) lets you look around
    without turning your body or your aim, at rhylib_freelook_sens (0.5) of
    the normal mouse speed. rhylib_freelook_hold: 0 (the
    default) = click once to start, click again to stop; 1 = only while
    held. When it stops the view goes back. Console: rhylib_freelook_toggle.

      First person: up to freelookYaw (100) degrees left or right of where
      you face, and up and down as far as normal. The arms and gun
      stay pointing where they were (always drawn; they leave the screen
      as you look away) and the crosshair hides.
      Third person: the camera turns all the way round (360), your aim
      and movement stay where your body faces, and your head turns toward
      where you look (only on your own screen).

    While helmet optics are in use (rhylib_gear: binoculars / rangefinder
    up, sun visor down) and the freelook key is the same as the optics
    mode key, the key keeps its optics job (and freelook ends). Not while down / lying (the
    body camera has its own look-around), in a menu or typing.

    Switching between first and third person keeps freelook on and the
    view where it was looking (TP.InitCam / TP.FreelookCarry); it ends on
    your aim either way.

    TP.freeLook (bool), TP.freeOff (first-person offset, Angle), TP.freeAim
    (the aim held while freelooking). Hooks:
    Think "thirdperson.freelook", InputMouseApply "thirdperson.freelook"
    (-60, before the body camera), CalcView "thirdperson.freelook" (-200:
    turns the view angles the later camera hooks and the gamemode use),
    PrePlayerDraw
    "thirdperson.freelook" (head). Third person's own CreateMove holds the
    aim (cl_10_camera.lua).
]]

local TP = Rhylib.ThirdPerson

local keyVar = CreateClientConVar("rhylib_freelook_key", "mouse3", true, false, "Hold to look around without turning (freelook)")
local yawVar = CreateClientConVar("rhylib_freelook_yaw", "100", true, false, "First person freelook: how far left / right you can look (degrees)")
local sensVar = CreateClientConVar("rhylib_freelook_sens", "0.5", true, false, "Freelook mouse speed (1 = the same as normal looking)")
local holdVar = CreateClientConVar("rhylib_freelook_hold", "0", true, false, "Freelook: 0 = click to switch on / off, 1 = only while the key is held")

local sensitivity = GetConVar("sensitivity")
local mYaw = GetConVar("m_yaw")
local mPitch = GetConVar("m_pitch")
local opticsKey = GetConVar("rhylib_optics_mode_key")

TP.freeLook = false
TP.freeOff = Angle(0, 0, 0)

-- TP.FreelookCarry(camAng): third person switched off mid freelook: the
-- first-person look offset carries on from where the camera looked.
function TP.FreelookCarry(camAng)
    local aim = TP.freeAim
    if not aim then return end
    local lim = math.Clamp(yawVar:GetFloat(), 10, 170)
    TP.freeOff.y = math.Clamp(math.NormalizeAngle(camAng.y - aim.y), -lim, lim)
    TP.freeOff.p = math.Clamp(camAng.p - aim.p, -89 - aim.p, 89 - aim.p)
end

-- TP.FreelookSens(): the freelook mouse speed multiplier (rhylib_freelook_sens;
-- the third-person camera uses it too while freelooking).
function TP.FreelookSens()
    return math.Clamp(sensVar:GetFloat(), 0.05, 3)
end

local function keyDown()
    local code = input.GetKeyCode(keyVar:GetString())
    return code and code > 0 and input.IsButtonDown(code)
end

local toggled = false   -- (toggle mode: switched on)
local wasDown = false

-- Helmet optics in use and sharing the key: it's theirs.
local function opticsOwnKey(ply)
    opticsKey = opticsKey or GetConVar("rhylib_optics_mode_key")
    return opticsKey and string.lower(opticsKey:GetString()) == string.lower(keyVar:GetString())
        and (ply:GetNW2Int("rhylib_optics", 0) ~= 0 or ply:GetNW2Bool("rhylib_visorDown", false)) or false
end

-- Can freelook be on at all right now?
local function allowed(ply)
    if not (IsValid(ply) and ply:Alive()) or ply:GetViewEntity() ~= ply then return false end
    local L = Rhylib.Lying
    if L and L.bodyCam then return false end
    return true
end

-- TP.ToggleFreelook(): switch freelook on / off (toggle mode). Console:
-- rhylib_freelook_toggle.
function TP.ToggleFreelook()
    toggled = not toggled
end
concommand.Add("rhylib_freelook_toggle", function() TP.ToggleFreelook() end)

-- Should freelook be on this frame?
local function wanted(ply)
    if not allowed(ply) then
        toggled = false
        return false
    end
    -- (helmet optics coming into use end freelook: the key is theirs now)
    if opticsOwnKey(ply) then
        toggled = false
        wasDown = keyDown()
        return false
    end
    local menus = gui.IsGameUIVisible() or vgui.CursorVisible() or ply:IsTyping()
    local down = keyDown() and not menus
    if holdVar:GetBool() then
        toggled = false
        wasDown = down
        return down
    end
    if down and not wasDown then toggled = not toggled end
    wasDown = down
    return toggled
end

Rhylib.Hook.Add("Think", "thirdperson.freelook", function()
    local ply = LocalPlayer()
    local want = wanted(ply)
    if want and not TP.freeLook then
        TP.freeLook = true
        TP.freeOff:Zero()
        TP.freeAim = ply:EyeAngles()   -- (held in both views; switching views keeps freelook)
        if TP.Active() and TP.camAng then
            TP.freeSaveCam = Angle(TP.camAng.p, TP.camAng.y, 0)
        end
    elseif not want and TP.freeLook then
        TP.freeLook = false
        -- Third person: the camera goes back where it was.
        if TP.freeSaveCam and TP.camAng then TP.camAng = TP.freeSaveCam end
        TP.freeSaveCam, TP.freeAim = nil, nil
    end
    -- First person: ease back to straight ahead after letting go.
    if not TP.freeLook and (TP.freeOff.p ~= 0 or TP.freeOff.y ~= 0) then
        local k = math.min(1, FrameTime() * 14)
        TP.freeOff.p = math.abs(TP.freeOff.p) < 0.5 and 0 or TP.freeOff.p * (1 - k)
        TP.freeOff.y = math.abs(TP.freeOff.y) < 0.5 and 0 or TP.freeOff.y * (1 - k)
    end
end)

-- First person: the mouse turns the look offset, not the player.
Rhylib.Hook.Add("InputMouseApply", "thirdperson.freelook", function(cmd, x, y, ang)
    if not TP.freeLook or TP.Active() then return end
    local scale = sensitivity:GetFloat() * TP.FreelookSens()
    local lim = math.Clamp(yawVar:GetFloat(), 10, 170)
    local o = TP.freeOff
    o.y = math.Clamp(o.y - x * scale * mYaw:GetFloat(), -lim, lim)
    -- (pitch: as far as normal looking allows from your current aim)
    local p = ang.p
    o.p = math.Clamp(o.p + y * scale * mPitch:GetFloat(), -89 - p, 89 - p)
    return true
end, -60)

-- First person: turn the view (the later camera hooks and the gamemode
-- build on these angles).
Rhylib.Hook.Add("CalcView", "thirdperson.freelook", function(ply, pos, angles)
    if ply ~= LocalPlayer() or TP.Active() then return end
    local o = TP.freeOff
    if o.p == 0 and o.y == 0 then return end
    angles.p = math.Clamp(angles.p + o.p, -89, 89)
    angles.y = angles.y + o.y
end, -200)


-- Third person: your head turns toward where the camera looks (your own
-- screen only).
Rhylib.Hook.Add("PrePlayerDraw", "thirdperson.freelook", function(ply)
    if ply ~= LocalPlayer() or not TP.freeLook or not TP.Active() or not TP.camAng then return end
    local eye = ply:EyeAngles()
    local dy = math.Clamp(math.NormalizeAngle(TP.camAng.y - eye.y), -75, 75)
    local dp = math.Clamp(TP.camAng.p - eye.p, -60, 60)
    ply:SetPoseParameter("head_yaw", dy)
    ply:SetPoseParameter("head_pitch", dp)
    ply:InvalidateBoneCache()
end)

-- Settings (rhylib_menus).
Rhylib.Hook.Add("InitPostEntity", "thirdperson.freelook.setting", function()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddSetting) then return end
    Menus.AddSetting("Third person", { id = "tp.freelookhold", order = 59, title = "Freelook",
        tab = "Camera & motion", kind = "choice", convar = "rhylib_freelook_hold",
        options = { { "0", "Click on / off" }, { "1", "Hold the key" } } })
    Menus.AddSetting("Third person", { id = "tp.freelookkey", order = 60, title = "Freelook key",
        desc = "Middle mouse by default; while helmet optics are in use it keeps its optics job",
        kind = "key", convar = "rhylib_freelook_key", shareWith = { rhylib_optics_mode_key = true } })
    Menus.AddSetting("Third person", { id = "tp.freelookyaw", order = 61, title = "First person freelook range",
        desc = "How far left / right you can look while holding freelook (degrees)", tab = "Camera & motion",
        kind = "slider", convar = "rhylib_freelook_yaw", min = 30, max = 170 })
    Menus.AddSetting("Third person", { id = "tp.freelooksens", order = 62, title = "Freelook mouse speed",
        desc = "1 = the same as normal looking", tab = "Camera & motion",
        kind = "slider", convar = "rhylib_freelook_sens", min = 0.05, max = 2, decimals = 2 })
end)
