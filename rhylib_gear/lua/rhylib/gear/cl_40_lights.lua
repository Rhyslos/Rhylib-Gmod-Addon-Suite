--[[
    Helmet lights (client): every player with NW2Bool rhylib_lights on
    gets two hard beams from the sides of the helmet, each turned outwards,
    overlapping a little in the middle (lightGap), the overlap dimmed in
    each beam's own texture (buildBeams). The server switches them on the
    helmet gear key (default L) or the flashlight key (sv_20_gear.lua). Only your own beams cast shadows.
    Client only. Real beams (two ProjectedTextures each) for you and the
    nearest lightMaxPlayers others; everyone lit in range gets the lamp
    glow sprites. Render targets rhylib_helmetlight_1 / _2 hold the beam
    textures (if making them fails, the plain texture is used).
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

-- Each beam's own texture (2026-10-09n, owner: less light where the two
-- overlap): the flashlight texture copied into a render target with the
-- inner band (the part that overlaps the other beam, from lightGap and
-- lightFov) darkened to lightOverlapDim, so the middle isn't twice as
-- bright. Rebuilt when those settings change. lightOverlapFlip mirrors it
-- in case the darkening lands on the outer side.
local beamTex = { key = nil }
local function buildBeams()
    local fov, gap = cfg("lightFov", 26), cfg("lightGap", -4.7)
    local dim, flip = cfg("lightOverlapDim", 0.6), cfg("lightOverlapFlip", false)
    local key = table.concat({ tex(), fov, gap, dim, tostring(flip) }, "|")
    if beamTex.key == key and beamTex[1] then return end
    local frac = math.Clamp(-2 * gap / fov, 0, 0.9)   -- (share of each beam's width that overlaps)
    local base = CreateMaterial("rhylib_helmetlight_src", "UnlitGeneric", { ["$basetexture"] = tex(), ["$vertexcolor"] = 1 })
    base:SetTexture("$basetexture", tex())
    for i, side in ipairs({ -1, 1 }) do
        local rt = GetRenderTargetEx("rhylib_helmetlight_" .. i, 256, 256, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE,
            bit.bor(4, 8), 0, IMAGE_FORMAT_RGB888)
        render.PushRenderTarget(rt)
        beamTex.pushed = true
        render.Clear(0, 0, 0, 255)
        cam.Start2D()
        beamTex.cam = true
        surface.SetMaterial(base)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(0, 0, 256, 256)
        draw.NoTexture()
        -- inner side: the left beam's right edge, the right beam's left edge
        local innerRight = (side == -1)
        if flip then innerRight = not innerRight end
        local band = math.floor(256 * frac)
        for x = 0, band - 1 do
            -- (soft start over the first 40% of the band, then flat)
            local t = math.min(1, (x + 1) / math.max(1, band * 0.4))
            local a = math.floor(255 * (1 - dim) * t)
            surface.SetDrawColor(0, 0, 0, a)
            local col = innerRight and (256 - band + x) or (band - 1 - x)   -- (x = 0 where the band starts, toward the beam's middle)
            surface.DrawRect(col, 0, 1, 256)
        end
        cam.End2D()
        beamTex.cam = false
        render.PopRenderTarget()
        beamTex.pushed = false
        beamTex[i] = rt
    end
    beamTex.key = key
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
    a:RotateAroundAxis(ang:Up(), -side * (fov * 0.5 + cfg("lightGap", -4.7)))
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
        pt:SetTexture(beamTex[i] or tex())
        pt:SetColor(COLOUR)
        pt:SetNearZ(10)
        pt:SetEnableShadows(ply == LocalPlayer())
        l[i] = pt
    end
    lamps[ply] = l
    return l
end

local function lit(ply)
    return IsValid(ply) and ply:Alive() and ply:GetNW2Bool("rhylib_lights", false) and not ply:IsDormant() and not ply:GetNW2Bool("rhylib_cloak")
end

-- Who gets real beams is worked out 4 times a second: you always, plus
-- the nearest lightMaxPlayers others in range. Every lit player in range
-- gets the lamp glow (glowing).
local keep, glowing, nextPick = {}, {}, 0
local function pick(me)
    local eye = EyePos()
    local range2 = (cfg("lightRange", 2000) * 2.5) ^ 2
    local list = {}
    glowing = {}
    for _, p in ipairs(player.GetAll()) do
        if lit(p) then
            local d = p == me and -1 or p:GetPos():DistToSqr(eye)
            if d < range2 then
                glowing[p] = true
                list[#list + 1] = { p, d }
            end
        end
    end
    -- (a player who already has beams counts as 20% closer, so two players
    -- at about the same distance don't swap beams back and forth)
    for _, e in ipairs(list) do
        if lamps[e[1]] and e[2] > 0 then e[2] = e[2] * 0.64 end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    keep = {}
    local others = cfg("lightMaxPlayers", 2)
    for _, e in ipairs(list) do
        if e[1] == me then
            keep[me] = true
        elseif others > 0 then
            keep[e[1]] = true
            others = others - 1
        end
    end
end

Rhylib.Hook.Add("Think", "gear.lights", function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    if RealTime() >= nextPick then
        nextPick = RealTime() + 0.25
        pick(me)
    end
    for ply in pairs(lamps) do
        if not (keep[ply] and lit(ply)) then remove(ply) end
    end
    local range = cfg("lightRange", 2000)
    local fov, bright = cfg("lightFov", 26), cfg("lightBrightness", 3.5)
    beamTex.want = next(keep) ~= nil   -- (built in PreRender, which can draw into render targets)
    local retex = beamTex.key ~= beamTex.applied
    if retex then beamTex.applied = beamTex.key end
    for ply in pairs(keep) do
        if lit(ply) then
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
                    if retex then pt:SetTexture(beamTex[i] or tex()) end
                    pt:Update()
                end
            end
        end
    end
end)

Rhylib.Hook.Add("PreRender", "gear.lights.tex", function()
    if not beamTex.want or beamTex.failed then return end
    local ok, err = pcall(buildBeams)
    if not ok then
        -- (unwind what was left open, then use the plain texture for good)
        if beamTex.cam then cam.End2D() beamTex.cam = false end
        if beamTex.pushed then render.PopRenderTarget() beamTex.pushed = false end
        beamTex[1], beamTex[2], beamTex.key, beamTex.failed = nil, nil, "failed", true
        print("[Rhylib] Helmet light textures failed, using the plain one: " .. tostring(err))
    end
end)

-- A glow on each lamp (not your own in first person).
Rhylib.Hook.Add("PostDrawTranslucentRenderables", "gear.lights.glow", function(depth, sky)
    if depth or sky or not next(glowing) then return end
    local me = LocalPlayer()
    local eye = EyePos()
    render.SetMaterial(GLOW)
    for ply in pairs(glowing) do
        if lit(ply) and not (ply == me and not me:ShouldDrawLocalPlayer()) then
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
