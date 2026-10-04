--[[
    Helmet lights (client): every player with NW2Bool rhylib_lights on
    gets two hard beams from the sides of the helmet, each turned outwards
    so two circles land side by side with a dark gap between them (and
    above and below the middle). The server switches them on the
    helmet gear key (default L) or the flashlight key (sv_20_gear.lua). Only your own beams cast shadows.
]]

local G = Rhylib.Gear

local TEXTURE = "effects/flashlight/hard"
local FALLBACK = "effects/flashlight001"
local GLOW = Material("sprites/light_glow02_add")
local COLOUR = Color(255, 248, 232)

local lamps = {}   -- [ply] = { pt, pt }

local texture
local function tex()
    if not texture then
        local m = Material(TEXTURE)
        texture = (m and not m:IsError()) and TEXTURE or FALLBACK
    end
    return texture
end

local function cfg(k, d)
    local v = G.Cfg and G.Cfg(k)
    return v == nil and d or v
end

-- Where the lamps sit and which way they point.
local function lampOrigin(ply)
    local ang = ply:EyeAngles()
    if ply == LocalPlayer() and not ply:ShouldDrawLocalPlayer() then
        return EyePos(), EyeAngles()
    end
    local att = ply:LookupAttachment("eyes")
    local a = att and att > 0 and ply:GetAttachment(att)
    if a then return a.Pos, ang end
    local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
    if bone then
        local pos = ply:GetBonePosition(bone)
        if pos then return pos + ang:Up() * 2, ang end
    end
    return ply:EyePos(), ang
end

-- side -1 = left, 1 = right: position and angles of that lamp's beam.
local function lampPose(pos, ang, side)
    local fov = cfg("lightFov", 26)
    local p = pos + ang:Right() * (4.5 * side) + ang:Forward() * -3 + ang:Up() * 1   -- (owner: 5 back, inside the helmet)
    local a = Angle(ang.p, ang.y, 0)
    a:RotateAroundAxis(ang:Up(), -side * (fov * 0.5 + cfg("lightGap", -2)))
    return p, a
end

local function remove(ply)
    local l = lamps[ply]
    if not l then return end
    for _, pt in ipairs(l) do if IsValid(pt) then pt:Remove() end end
    lamps[ply] = nil
end

local function make(ply)
    local l = {}
    for i = 1, 2 do
        local pt = ProjectedTexture()
        pt:SetTexture(tex())
        pt:SetColor(COLOUR)
        pt:SetNearZ(10)
        pt:SetEnableShadows(ply == LocalPlayer())
        l[i] = pt
    end
    lamps[ply] = l
    return l
end

local function lit(ply)
    return IsValid(ply) and ply:Alive() and ply:GetNW2Bool("rhylib_lights", false) and not ply:IsDormant()
end

Rhylib.Hook.Add("Think", "gear.lights", function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    -- The nearest lit players.
    local eye = EyePos()
    local list = {}
    for _, p in ipairs(player.GetAll()) do
        if lit(p) then list[#list + 1] = { p, p == me and -1 or p:GetPos():DistToSqr(eye) } end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    local keep = {}
    local range = cfg("lightRange", 2000)
    for i = 1, math.min(#list, cfg("lightMaxPlayers", 4)) do
        if list[i][2] < (range * 2.5) ^ 2 then keep[list[i][1]] = true end
    end
    for ply in pairs(lamps) do
        if not keep[ply] then remove(ply) end
    end
    local fov, bright = cfg("lightFov", 26), cfg("lightBrightness", 3.5)
    for ply in pairs(keep) do
        local l = lamps[ply] or make(ply)
        local pos, ang = lampOrigin(ply)
        for i, side in ipairs({ -1, 1 }) do
            local pt = l[i]
            if IsValid(pt) then
                local p, a = lampPose(pos, ang, side)
                pt:SetPos(p)
                pt:SetAngles(a)
                pt:SetFOV(fov)
                pt:SetFarZ(range)
                pt:SetBrightness(bright)
                pt:Update()
            end
        end
    end
end)

-- A glow on each lamp (not your own in first person).
Rhylib.Hook.Add("PostDrawTranslucentRenderables", "gear.lights.glow", function(depth, sky)
    if depth or sky or not next(lamps) then return end
    local me = LocalPlayer()
    local eye = EyePos()
    render.SetMaterial(GLOW)
    for ply in pairs(lamps) do
        if IsValid(ply) and not (ply == me and not me:ShouldDrawLocalPlayer()) then
            local pos, ang = lampOrigin(ply)
            for _, side in ipairs({ -1, 1 }) do
                local p, a = lampPose(pos, ang, side)
                p = p + ang:Forward() * 5   -- (the beam starts inside the helmet; the glow sits on its front)
                -- (brighter when it points at you)
                local face = math.max(0, a:Forward():Dot((eye - p):GetNormalized()))
                local size = 6 + 18 * face
                render.DrawSprite(p, size, size, Color(255, 248, 232, 120 + 135 * face))
            end
        end
    end
end)

Rhylib.Hook.Add("EntityRemoved", "gear.lights", function(ent)
    if lamps[ent] then remove(ent) end
end)

Rhylib.Hook.Add("InitPostEntity", "gear.lights.control", function()
    local Menus = Rhylib.Menus
    if Menus and Menus.AddControl then
        Menus.AddControl("Gear", "{impulse 100}", "Helmet lights on / off (also the helmet gear key)")
    end
end)
