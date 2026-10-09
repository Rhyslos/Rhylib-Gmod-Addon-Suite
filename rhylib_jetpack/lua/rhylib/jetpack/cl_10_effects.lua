--[[
    Jetpack visuals and sound (client only). Nothing is sent over the
    network: everything is read from the players' predicted network vars.

      - the jetpack model on the back of anyone wearing one
      - thrust flames and a jet sound while thrusting
      - a small fuel bar under your crosshair
]]

local J = Rhylib.Jetpack
local UI = Rhylib.UI

-- Placeholder placement on the back; tune once a real jetpack model is chosen.
J.BackOffset = Vector(-9, 0, 50)      -- back, sideways, up from the player's feet (standing)
J.CrouchDrop = 18                     -- lower by this while crouching
J.BackAngle = Angle(0, 0, 0)
J.Nozzles = { Vector(-2, -5, -12), Vector(-2, 5, -12) }  -- flame points relative to the jetpack

local MODEL = "models/thrusters/jetpack.mdl"
local SOUND = "thrusters/jet02.wav"

local matGlow = Material("sprites/light_glow02_add")
local matBeam = Material("trails/plasma")
local COL_FLAME = Color(255, 170, 80)
local COL_CORE = Color(255, 240, 200)

local backModel

local function placement(ply)
    local yaw = ply:GetRenderAngles().y
    local ang = Angle(0, yaw, 0)
    local off = J.BackOffset
    local up = off.z - (ply:Crouching() and J.CrouchDrop or 0)
    local pos = ply:GetPos() + ang:Forward() * off.x + ang:Right() * off.y + ang:Up() * up
    local a = Angle(ang.p + J.BackAngle.p, ang.y + J.BackAngle.y, ang.r + J.BackAngle.r)
    return pos, a
end

Rhylib.Hook.Add("PostPlayerDraw", "jetpack.draw", function(ply)
    if not ply:GetDTBool(J.DT_HAS) or not ply:Alive() then return end

    -- (the jetpack item's model: Server settings > Models can swap it)
    local def = Rhylib.Items and Rhylib.Items.Get and Rhylib.Items.Get("jetpack")
    local want = def and def.model or MODEL
    if IsValid(backModel) and backModel.rhylibWant ~= want then backModel:Remove() end
    if not IsValid(backModel) then
        backModel = ClientsideModel(want, RENDERGROUP_OPAQUE)
        if IsValid(backModel) then backModel.rhylibWant = want end
        if not IsValid(backModel) then return end
        backModel:SetNoDraw(true)
    end

    local pos, ang = placement(ply)
    backModel:SetPos(pos)
    backModel:SetAngles(ang)
    backModel:SetupBones()
    backModel:DrawModel()

    if not ply:GetDTBool(J.DT_THRUST) then return end
    local flicker = 0.8 + math.sin(CurTime() * 40 + ply:EntIndex()) * 0.2
    for _, n in ipairs(J.Nozzles) do
        local p = pos + ang:Forward() * n.x + ang:Right() * n.y + ang:Up() * n.z
        local tip = p - ang:Up() * (28 * flicker)
        render.SetMaterial(matBeam)
        render.DrawBeam(p, tip, 7 * flicker, 0, 1, COL_FLAME)
        render.SetMaterial(matGlow)
        render.DrawSprite(p, 22 * flicker, 22 * flicker, COL_FLAME)
        render.DrawSprite(p, 9, 9, COL_CORE)
    end
end)

-- One looping sound per thrusting player, started and stopped on change.
-- Checked 10 times a second instead of every frame; nobody hears 0.1 s.
local sounds = {}
Rhylib.Hook.Remove("Think", "jetpack.sound")  -- older versions ran per frame
timer.Create("Rhylib.Jetpack.Sound", 0.1, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        local on = ply:GetDTBool(J.DT_THRUST) and ply:Alive()
        local snd = sounds[ply]
        if on and not snd then
            snd = CreateSound(ply, SOUND)
            snd:PlayEx(0.55, 100)
            sounds[ply] = snd
        elseif not on and snd then
            snd:FadeOut(0.2)
            sounds[ply] = nil
        end
    end
    for ply, snd in pairs(sounds) do
        if not IsValid(ply) then
            snd:Stop()
            sounds[ply] = nil
        end
    end
end)

-- Fuel bar under the crosshair while it isn't full.
Rhylib.Hook.Add("HUDPaint", "jetpack.fuel", function()
    local ply = LocalPlayer()
    if not ply:GetDTBool(J.DT_HAS) or not ply:Alive() then return end
    local fuel = J.Fuel(ply)
    local thrust = ply:GetDTBool(J.DT_THRUST)
    local locked = ply:GetDTBool(J.DT_LOCKED)
    if fuel >= 1 and not thrust then return end

    local s = ScrH() / 1080
    local w, h = math.floor(120 * s), math.max(2, math.floor(5 * s))
    local x, y = math.floor(ScrW() * 0.5 - w * 0.5), math.floor(ScrH() * 0.5 + 70 * s)
    surface.SetDrawColor(0, 0, 0, 150)
    surface.DrawRect(x - 1, y - 1, w + 2, h + 2)
    surface.SetDrawColor(locked and UI.Colors.bad or UI.Colors.warn)
    surface.DrawRect(x, y, math.floor(w * fuel), h)
    if locked then
        draw.SimpleText("Jetpack recharging", UI.Font(14), ScrW() * 0.5, y + h + 4 * s, UI.Colors.bad, TEXT_ALIGN_CENTER)
    end
end)
