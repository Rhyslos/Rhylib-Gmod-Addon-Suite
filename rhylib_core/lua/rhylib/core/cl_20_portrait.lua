--[[
    Portraits: a head-and-shoulders picture of a player model, used in
    place of Steam avatars (chat, voice).

        Rhylib.UI.DrawPortrait(plyOrModel, x, y, size, alpha)

    Each model is rendered once into a small render target and cached, so
    drawing a portrait is just a textured rectangle. New portraits are
    rendered one per frame at the start of the HUD; until then a plain
    plate is drawn. Up to SLOTS models are kept (least recently used go).
]]

local UI = Rhylib.UI

local SIZE = 128           -- texture size
local SLOTS = 48
local FOV = 22
local DIST = 48            -- camera distance from the head
local BG = Color(26, 29, 27)

local cache = {}           -- [model] = { mat, slot, used }
local slots = {}           -- [i] = model
local queue, queued = {}, {}
local csEnt

local function freeSlot()
    for i = 1, SLOTS do
        if not slots[i] then return i end
    end
    -- Reuse the least recently used one.
    local oldest, at = 1, math.huge
    for i = 1, SLOTS do
        local c = cache[slots[i]]
        if c and c.used < at then oldest, at = i, c.used end
    end
    cache[slots[oldest]] = nil
    return oldest
end

local function headPos(ent)
    ent:SetupBones()
    local b = ent:LookupBone("ValveBiped.Bip01_Head1")
    local pos = b and ent:GetBonePosition(b)
    if not pos or pos == ent:GetPos() then
        local mins, maxs = ent:GetModelBounds()
        pos = ent:GetPos() + Vector(0, 0, maxs.z * 0.88)
    end
    return pos
end

local function render1(model)
    if not IsValid(csEnt) then
        csEnt = ClientsideModel(model, RENDERGROUP_OPAQUE)
        if not IsValid(csEnt) then return end
        csEnt:SetNoDraw(true)
    else
        csEnt:SetModel(model)
    end
    csEnt:SetPos(Vector(0, 0, 0))
    csEnt:SetAngles(Angle(0, 0, 0))
    local seq = csEnt:LookupSequence("idle_all_01")
    if not seq or seq < 0 then seq = csEnt:LookupSequence("idle") end
    if seq and seq >= 0 then csEnt:ResetSequence(seq) csEnt:SetCycle(0) end
    csEnt:InvalidateBoneCache()

    local head = headPos(csEnt) + Vector(0, 0, -2)
    -- Models face +X; look back at the face, slightly from the side.
    local camAng = Angle(4, 195, 0)
    local camPos = head - camAng:Forward() * DIST

    local i = freeSlot()
    local rt = GetRenderTargetEx("rhylib_portrait_" .. i, SIZE, SIZE, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGBA8888)
    render.PushRenderTarget(rt)
    render.Clear(BG.r, BG.g, BG.b, 255, true, true)
    cam.Start3D(camPos, camAng, FOV, 0, 0, SIZE, SIZE)
        render.SuppressEngineLighting(true)
        render.SetLightingOrigin(head)
        render.ResetModelLighting(0.25, 0.25, 0.28)
        render.SetModelLighting(BOX_FRONT, 1, 1, 1)
        render.SetModelLighting(BOX_TOP, 0.8, 0.8, 0.8)
        render.SetModelLighting(BOX_RIGHT, 0.5, 0.5, 0.55)
        render.SetColorModulation(1, 1, 1)
        render.SetBlend(1)
        csEnt:DrawModel()
        render.SuppressEngineLighting(false)
    cam.End3D()
    render.PopRenderTarget()

    local c = cache[model] or {}
    c.mat = c.mat or CreateMaterial("rhylib_portrait_mat_" .. i .. "_" .. util.CRC(model), "UnlitGeneric", {
        ["$basetexture"] = rt:GetName(),
        ["$vertexcolor"] = "1",
        ["$vertexalpha"] = "1",
    })
    c.mat:SetTexture("$basetexture", rt)
    c.slot, c.used = i, RealTime()
    cache[model] = c
    slots[i] = model
end

-- One new portrait per frame.
Rhylib.Hook.Add("HUDPaint", "core.portraits", function()
    local model = table.remove(queue, 1)
    if not model then return end
    queued[model] = nil
    if cache[model] or not util.IsValidModel(model) then return end
    render1(model)
end, -100)

-- Re-render after the game lost its render targets (alt-tab, settings).
Rhylib.Hook.Add("OnScreenSizeChanged", "core.portraits", function()
    cache, slots = {}, {}
end)

-- UI.PortraitMaterial(model): the cached portrait material, or nil (then
-- it's queued, up to 16 waiting). Model paths are lower-cased.
function UI.PortraitMaterial(model)
    if not model or model == "" then return nil end
    model = string.lower(model)
    local c = cache[model]
    if c then
        c.used = RealTime()
        return c.mat
    end
    if not queued[model] and #queue < 16 then
        queued[model] = true
        queue[#queue + 1] = model
    end
end

-- UI.DrawPortrait(who, x, y, size, alpha): who = a player/entity (its
-- model) or a model path. Draws inside a HUDPaint/Paint (2D). alpha 0-255.
-- Example: Rhylib.UI.DrawPortrait(ply, 10, 10, 64)
function UI.DrawPortrait(who, x, y, size, alpha)
    local model = who
    if isentity(who) then model = IsValid(who) and who:GetModel() or nil end
    local mat = UI.PortraitMaterial(model)
    alpha = alpha or 255
    if mat then
        surface.SetMaterial(mat)
        surface.SetDrawColor(255, 255, 255, alpha)
        surface.DrawTexturedRect(x, y, size, size)
    else
        surface.SetDrawColor(BG.r, BG.g, BG.b, alpha)
        surface.DrawRect(x, y, size, size)
    end
    surface.SetDrawColor(0, 0, 0, alpha * 0.9)
    surface.DrawOutlinedRect(x, y, size, size)
end
