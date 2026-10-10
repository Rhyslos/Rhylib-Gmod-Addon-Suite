--[[
    First-person camera on the body (client).

    Body camera: in first person, while your body is a ragdoll (downed,
    stunned, knocked down, out of a simulation) or after you die, the
    camera sits in the ragdoll's eyes and turns with its head, so a blast
    that spins you spins the view. Lying alive you can look a little
    around (lookYaw / lookPitch from where the head faces); dead, not at
    all. Your own body isn't drawn meanwhile (you'd see the inside of the
    helmet). Getting up hands the view back facing where the head was.

    Builds on the gamemode's own view (GAMEMODE:CalcView), so weapon zoom
    and FOV still apply. Third person (rhylib_thirdperson) is left alone
    while it's on. Walking motion is in cl_66_motion.lua.

    Client convar: rhylib_bodycam (1). With rhylib_menus: Settings,
    Camera & motion tab.

    Hooks: CalcView "core.bodycam" at -50 (before third person's), so a
    CalcView of another addon that runs first and returns a view skips it;
    L.BodyCamOn() then turns false the next frame, and the mouse and gun
    come back. InputMouseApply -50, PreDrawViewModel -100.
]]

local L = Rhylib.Lying

local cvBody = CreateClientConVar("rhylib_bodycam", "1", true, false, "First person: the camera follows your body's head while lying or dead")

local LOOK_YAW, LOOK_PITCH = 70, 45   -- (lying alive: how far you can look from the head)

L.bodyCam = false     -- true while the camera is on the body (others read it)
local look = Angle(0, 0, 0)
local smPos, smAng
local blendStart = 0
local lastHeadYaw
local camDead = false   -- (on a corpse: respawning keeps the spawn's facing)

-- L.ThirdPersonOn(): true while rhylib_thirdperson wants third person
-- (its server mode or the player's switch; the old convars without it).
function L.ThirdPersonOn()
    local TP = Rhylib.ThirdPerson
    if TP and TP.Wanted then return TP.Wanted() end
    local tp = GetConVar("rhylib_thirdperson")
    local allowed = GetConVar("rhylib_thirdperson_allowed")
    return tp and tp:GetBool() and (not allowed or allowed:GetBool())
end

-- The body the camera should sit in, or nil.
local function bodyOf(ply)
    if ply:Alive() then
        local r = L.Ragdoll(ply)
        if r then return r, false end
        return nil
    end
    local c = ply:GetNW2Entity("rhylib_corpse")
    if IsValid(c) then return c, true end
    local r = ply:GetRagdollEntity()
    if IsValid(r) then return r, true end
end

-- Where the eyes are on a ragdoll: the "eyes" attachment, else the head bone.
local function eyesOf(rag)
    rag:SetupBones()   -- (your own body isn't drawn, so its bones aren't set up by drawing)
    local id = rag:LookupAttachment("eyes")
    if id and id > 0 then
        local a = rag:GetAttachment(id)
        if a then return a.Pos, a.Ang end
    end
    local b = rag:LookupBone("ValveBiped.Bip01_Head1")
    local m = b and rag:GetBoneMatrix(b)
    if m then
        -- (the head bone points up the neck: turn it to face forward)
        local ang = m:GetAngles()
        ang:RotateAroundAxis(ang:Forward(), -90)
        ang:RotateAroundAxis(ang:Up(), -90)
        return m:GetTranslation() + ang:Forward() * 3, ang
    end
end

-- The camera only counts as on if our CalcView ran this frame or the last
-- (another addon's CalcView can skip ours; then mouse and gun come back).
L.bodyCamFrame = L.bodyCamFrame or -10
-- L.BodyCamOn(): true while the view is in the body (others hide things then).
function L.BodyCamOn()
    return L.bodyCam and L.bodyCamFrame >= FrameNumber() - 1
end

local function cvNum(name, def)
    local c = GetConVar(name)
    return c and c:GetFloat() or def
end

-- Mouse while on the body: a little look-around when alive, none when dead.
Rhylib.Hook.Add("InputMouseApply", "core.bodycam", function(cmd, x, y)
    if not L.BodyCamOn() then return end
    local ply = LocalPlayer()
    if ply:Alive() then
        local sens = cvNum("sensitivity", 3)
        look.y = math.Clamp(look.y - x * sens * cvNum("m_yaw", 0.022), -LOOK_YAW, LOOK_YAW)
        look.p = math.Clamp(look.p + y * sens * cvNum("m_pitch", 0.022), -LOOK_PITCH, LOOK_PITCH)
    end
    return true   -- (the real aim doesn't move)
end, -50)

Rhylib.Hook.Add("CalcView", "core.bodycam", function(ply, pos, angles, fov, znear, zfar)
    if ply ~= LocalPlayer() or L.ThirdPersonOn() then
        L.bodyCam = false
        return
    end
    local now, ft = CurTime(), FrameTime()

    local rag, dead
    if cvBody:GetBool() and ply:GetViewEntity() == ply then rag, dead = bodyOf(ply) end
    local ePos, eAng
    if IsValid(rag) then ePos, eAng = eyesOf(rag) end
    if ePos then
        if not L.bodyCam then
            L.bodyCam = true
            look:Zero()
            smPos, smAng = nil, nil
            blendStart = now
        end
        if dead then look:Zero() end
        camDead = dead
        L.bodyCamFrame = FrameNumber()
        -- Light smoothing (ragdoll updates come in steps over the network).
        local k = 1 - math.exp(-ft * 30)
        smPos = smPos and LerpVector(k, smPos, ePos) or Vector(ePos)
        smAng = smAng and LerpAngle(k, smAng, eAng) or Angle(eAng.p, eAng.y, eAng.r)
        lastHeadYaw = smAng.y
        local ang = Angle(smAng.p, smAng.y, smAng.r)
        ang:RotateAroundAxis(ang:Up(), look.y)
        ang:RotateAroundAxis(ang:Right(), -look.p)
        -- Ease in from the old view over a moment.
        local f = math.Clamp((now - blendStart) / 0.15, 0, 1)
        local view = (GAMEMODE.CalcView and GAMEMODE:CalcView(ply, pos, angles, fov, znear, zfar)) or {}
        view.origin = LerpVector(f, pos, smPos)
        view.angles = LerpAngle(f, angles, ang)
        view.znear = 1
        view.drawviewer = false
        return view
    end
    if L.bodyCam then
        -- Up again: face where the head was looking.
        L.bodyCam = false
        if ply:Alive() and not camDead and lastHeadYaw then ply:SetEyeAngles(Angle(0, lastHeadYaw + look.y, 0)) end
    end
end, -50)

-- No floating gun or hands while the camera is in the body.
Rhylib.Hook.Add("PreDrawViewModel", "core.bodycam", function()
    if L.BodyCamOn() then return true end
end, -100)

-- Your own death ragdoll isn't drawn while the camera is in it.
Rhylib.Hook.Add("CreateClientsideRagdoll", "core.bodycam", function(ent, rag)
    if ent ~= LocalPlayer() then return end
    rag.RenderOverride = function(self, flags)
        if L.BodyCamOn() then return end
        self:DrawModel(flags)
    end
end)

-- In the settings menu (rhylib_menus).
Rhylib.Hook.Add("InitPostEntity", "core.bodycam.setting", function()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddSetting) then return end
    Menus.AddSetting("HUD", { id = "core.bodycam", order = 70, title = "Body camera",
        desc = "First person: the view follows your body's head while you're down or dead", kind = "toggle", convar = "rhylib_bodycam" })
end)
