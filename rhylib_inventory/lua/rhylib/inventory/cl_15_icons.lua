--[[
    Item pictures for the inventory window (client only): every item is
    drawn from its 3D model, rendered once and kept in a 2048x2048 texture
    (more pages if it fills up), so drawing it is one textured quad.

    Which model, first that works:
    1. SWEP.InvIconModel / SWEP.InvIconModels (first installed) or
       def.iconModel: an explicit picture model.
    2. Gear parts that are bodygroups (rhylib_gear G.SHOWS: kama, pauldron,
       visor, backpacks, jetpack...): your current player model with only
       that part on, and the rest of the body hidden (drawn first, nudged
       toward the camera, into the depth buffer only, so only what sticks
       out of the body shows), framed on the part (a quick silhouette pass
       finds where it is). Remade when your model changes.
    3. Guns and grenades: SWEP.PropModel (+PropBodygroups, PropColor tint)
       side on, the longest axis across, muzzle (model +X) on the right
       (SWEP.InvIconFlip turns it round, SWEP.InvIconZoom frames tighter).
    4. The weapon's WorldModel, else def.model: seen from the front left
       and a little above, like a spawn icon.
    5. A cardboard box (the world item's fallback).

    Every picture is framed on where the model really is: it's drawn
    white on a small target first and the lit pixels read back (bounds are
    often the collision hull, far bigger than the mesh: grenades).
    Staff can tune any item's picture in game (inventory right-click
    "Adjust picture", or rhylib_inventory_icon_edit <id>): turn, tilt,
    roll, zoom, move. Saved on the server (sv_25_icons) and sent to every
    player as they load in; every picture is made right after loading in.

    Tiles are opaque, in the item category's body colour; alpha writes are
    locked so models can't punch holes. Made a few per frame from a
    PreRender hook that only exists while something waits; errors can't
    leave the render state broken (pcall).

        Inv.Icons.Fit(def, x, y, w, h, rot) -> dx, dy, dw, dh (or nil)
        Inv.Icons.Draw(def, x, y, w, h, rot, alpha) -> drawn?
        rhylib_inventory_icons: make every picture again.
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items

-- Item body and stripe colours per category (the window uses them too).
Inv.CATEGORY_COLORS = {
    weapon = { body = Color(30, 37, 46), stripe = Color(96, 140, 196) },
    ammo = { body = Color(42, 36, 25), stripe = Color(206, 152, 62) },
    medical = { body = Color(25, 40, 31), stripe = Color(96, 186, 126) },
    gear = { body = Color(38, 35, 30), stripe = Color(168, 146, 112) },
    misc = { body = Color(34, 34, 33), stripe = Color(136, 136, 130) },
    training = { body = Color(44, 40, 20), stripe = Color(236, 200, 60) },   -- (rhylib_training gear)
}

Inv.Icons = Inv.Icons or {}
local Icons = Inv.Icons

local FALLBACK = "models/props_junk/cardboard_box004a.mdl"

-- Camera around a gear part: yaw (0 = in front of the model, + = its
-- left) and pitch (degrees above).
Icons.PART_VIEW = {
    kama = { 20, 5 }, pauldron = { 25, 10 }, binos = { 30, 8 }, rangefinder = { 30, 8 }, light = { 30, 8 }, visor = { 25, 5 },
    holster = { 15, 5 }, forearm = { -40, 5 }, comms = { 35, 10 }, belt = { 15, 5 }, back = { 205, 12 },
}
Icons.ANGLED = { 35, 25 }   -- other items: front left, a little above

--------------------------------------------------------------------------
-- What picture an item gets
--------------------------------------------------------------------------

local function valid(m) return isstring(m) and m ~= "" and util.IsValidModel(m) end

local function autoSpec(def)
    local sw = def.weapon and weapons.Get(def.weapon)
    local w, h = def.w or 1, def.h or 1
    -- 1. explicit
    local pick = def.iconModel or (sw and sw.InvIconModel)
    if valid(pick) then return { model = pick, angled = true, zoom = sw and sw.InvIconZoom, w = w, h = h } end
    if sw and istable(sw.InvIconModels) then
        for _, m in ipairs(sw.InvIconModels) do
            if valid(m) then return { model = m, angled = true, zoom = sw.InvIconZoom, w = w, h = h } end
        end
    end
    -- 2. a part of your player model
    local GG = Rhylib.Gear
    local me = LocalPlayer()
    if GG and GG.SHOWS and GG.SHOWS[def.id] and IsValid(me) and valid(me:GetModel()) and GG.ItemShown(me, def.id) then
        return { part = def.id, model = me:GetModel(), w = w, h = h }
    end
    -- 3. guns and grenades
    if sw and valid(sw.PropModel) then
        return { model = sw.PropModel, bodygroups = sw.PropBodygroups, color = sw.PropColor, flip = sw.InvIconFlip, zoom = sw.InvIconZoom, w = w, h = h }
    end
    -- 4. world model
    if sw and valid(sw.WorldModel) then return { model = sw.WorldModel, angled = true, zoom = sw.InvIconZoom, w = w, h = h } end
    if valid(def.model) then return { model = def.model, angled = true, w = w, h = h } end
    return { model = FALLBACK, angled = true, w = w, h = h }
end

-- Saved per-item settings from the server (sv_25_icons): [id] = { p, y, r
-- (camera, or nil = automatic), z (zoom), ox, oy (move) }.
Icons.TUNE = Icons.TUNE or {}

function Icons.Spec(def)
    local sp = autoSpec(def)
    sp.id = def.id
    sp.tune = Icons.TUNE[def.id]
    return sp
end

--------------------------------------------------------------------------
-- The picture pages
--------------------------------------------------------------------------

local U = 128          -- pixels per cell in a picture
local PAGE = 2048
local GAP = 2
local MAX_PAGES = 4
local SCRATCH = 128    -- silhouette pass for gear parts

local pages = Icons.pages or {}
Icons.pages = pages
local entries, queue, queued = {}, {}, {}
local builtFor   -- (player model the part pictures were made from)

local function page(n)
    local p = pages[n]
    if not p then
        local rt = GetRenderTargetEx("rhylib_inv_icons_" .. n, PAGE, PAGE, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGBA8888)
        local mat = CreateMaterial("rhylib_inv_icons_m" .. n, "UnlitGeneric", { ["$basetexture"] = rt:GetName(), ["$vertexcolor"] = 1, ["$vertexalpha"] = 1 })
        mat:SetTexture("$basetexture", rt)
        p = { rt = rt, mat = mat }
        pages[n] = p
    end
    if not p.ready then
        p.x, p.y, p.rowH, p.ready = 0, 0, 0, true
        render.PushRenderTarget(p.rt)
        render.Clear(0, 0, 0, 255, true, true)
        render.PopRenderTarget()
    end
    return p
end

local scratchRT
local function scratch()
    if not scratchRT then
        scratchRT = GetRenderTargetEx("rhylib_inv_icons_scratch", SCRATCH, SCRATCH, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGBA8888)
    end
    return scratchRT
end

-- Room for a tw x th picture: page and top-left, or nil.
local function reserve(tw, th)
    for n = 1, MAX_PAGES do
        local p = page(n)
        if p.x + tw > PAGE then p.x, p.y, p.rowH = 0, p.y + p.rowH + GAP, 0 end
        if p.y + th <= PAGE then
            local x, y = p.x, p.y
            p.x = p.x + tw + GAP
            p.rowH = math.max(p.rowH, th)
            return p, x, y
        end
    end
end

--------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------

local function lights()
    render.SuppressEngineLighting(true)
    -- even light from every side (whichever face we see), brighter from above
    render.ResetModelLighting(0.75, 0.76, 0.8)
    render.SetModelLighting(BOX_TOP, 1.15, 1.15, 1.15)
    render.SetModelLighting(BOX_BOTTOM, 0.25, 0.25, 0.28)
end

local function boundsOf(ent)
    local mins, maxs = ent:GetModelRenderBounds()
    -- (zero vectors when the model has no view box)
    if not mins or (maxs - mins):LengthSqr() < 1 then mins, maxs = ent:GetModelBounds() end
    return mins, maxs
end

-- Open cameras / pushed targets, so a failed render can be unwound.
local camDepth, rtDepth = 0, 0
local function endCam() cam.End() camDepth = camDepth - 1 end

-- Ranges of the 8 bounds corners along right / up / forward.
local function project(mins, maxs, origin, right, up, fwd)
    local r0, r1, u0, u1, f0, f1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
    for i = 0, 7 do
        local c = Vector(bit.band(i, 1) > 0 and maxs.x or mins.x, bit.band(i, 2) > 0 and maxs.y or mins.y, bit.band(i, 4) > 0 and maxs.z or mins.z) - origin
        local r, u, f = c:Dot(right), c:Dot(up), c:Dot(fwd)
        r0, r1, u0, u1, f0, f1 = math.min(r0, r), math.max(r1, r), math.min(u0, u), math.max(u1, u), math.min(f0, f), math.max(f1, f)
    end
    return r0, r1, u0, u1, f0, f1
end

-- One ortho view: the box r0..r1 x u0..u1 (around origin, in the camera
-- plane) fitted into the viewport with a margin, keeping its aspect.
local function startCam(vx, vy, vw, vh, origin, ang, r0, r1, u0, u1, f0, f1, margin)
    local fwd, right, up = ang:Forward(), ang:Right(), ang:Up()
    local cr, cu = (r0 + r1) * 0.5, (u0 + u1) * 0.5
    local aspect = vw / vh
    local halfW = math.max((r1 - r0) * 0.5, (u1 - u0) * 0.5 * aspect, 0.25) * (margin or 1.08)
    local halfH = halfW / aspect
    local back = -f0 + 32
    cam.Start({ type = "3D", x = vx, y = vy, w = vw, h = vh, angles = ang,
        origin = origin + right * cr + up * cu - fwd * back,
        ortho = { left = -halfW, right = halfW, top = -halfH, bottom = halfH }, znear = 1, zfar = back + f1 + 64 })
    camDepth = camDepth + 1
    render.FogMode(MATERIAL_FOG_NONE)
    return cr, cu, halfW, halfH
end

local function setGroups(ent, groups)
    for id, idx in pairs(groups) do ent:SetBodygroup(id, idx) end
    ent:InvalidateBoneCache()
    ent:SetupBones()
end

local WHITE = Material("models/debug/debugwhite")

-- Where the model really is on screen: drawn white on the scratch target
-- (framed loosely from its bounds, wider again if it touches the edge),
-- the lit pixels read back and turned into camera-plane extents. Bounds
-- are often the collision hull, far bigger than the mesh (grenades), so
-- every picture is framed on this. draw(white) draws the model.
local function silhouette(center, ang, r0, r1, u0, u1, f0, f1, draw)
    local S = SCRATCH
    local cr, cu, halfW, halfH, px0, px1, py0, py1
    for _, margin in ipairs({ 1.35, 2.4 }) do
        render.PushRenderTarget(scratch())
        rtDepth = rtDepth + 1
        render.Clear(0, 0, 0, 255, true, true)
        cr, cu, halfW, halfH = startCam(0, 0, S, S, center, ang, r0, r1, u0, u1, f0, f1, margin)
            lights()
            render.ResetModelLighting(1, 1, 1)
            draw(true)
        endCam()
        render.CapturePixels()
        px0, px1, py0, py1 = S, -1, S, -1
        for py = 0, S - 1, 2 do
            for px = 0, S - 1, 2 do
                local r = render.ReadPixel(px, py)
                if r and r > 100 then
                    if px < px0 then px0 = px end
                    if px > px1 then px1 = px end
                    if py < py0 then py0 = py end
                    if py > py1 then py1 = py end
                end
            end
        end
        render.PopRenderTarget()
        rtDepth = rtDepth - 1
        if px1 < px0 then return nil end
        if px0 > 0 and py0 > 0 and px1 < S - 2 and py1 < S - 2 then break end
    end
    -- pixels back to the camera plane (screen y goes down, up goes up)
    local function rr(px) return cr - halfW + (px / S) * 2 * halfW end
    local function uu(py) return cu + halfH - (py / S) * 2 * halfH end
    return rr(px0 - 2), rr(px1 + 3), uu(py1 + 3), uu(py0 - 2)
end

-- The camera: saved settings (turn / tilt / roll around the model) or the
-- automatic view. Icons.AngleToView turns a camera angle back into those.
local function viewAngle(spec, auto)
    local t = spec.tune
    if t and t.y then
        local ang = (-Angle(-(t.p or 0), t.y, 0):Forward()):Angle()
        if (t.r or 0) ~= 0 then ang:RotateAroundAxis(ang:Forward(), t.r) end
        return ang
    end
    return auto
end

function Icons.AngleToView(ang)
    local d = -ang:Forward()
    local p = math.deg(math.asin(math.Clamp(d.z, -1, 1)))
    local y = math.deg(math.atan2(d.y, d.x))
    local base = (-Angle(-p, y, 0):Forward()):Angle()
    local up = ang:Up()
    local r = math.deg(math.atan2(up:Dot(base:Right()), up:Dot(base:Up())))
    for _, cand in ipairs({ r, -r }) do
        local a = Angle(base.p, base.y, base.r)
        a:RotateAroundAxis(a:Forward(), cand)
        if a:Up():Dot(up) > 0.999 then return p, y, cand end
    end
    return p, y, r
end

-- The silhouette box with the saved zoom and move, ready for startCam
-- (margin 1).
local function finalBox(spec, pr0, pr1, pu0, pu1, tw, th)
    local t = spec.tune or {}
    local z = (t.z or 1) * (tonumber(spec.zoom) or 1)
    local cr, cu = (pr0 + pr1) * 0.5, (pu0 + pu1) * 0.5
    local aspect = tw / th
    local halfW = math.max((pr1 - pr0) * 0.5, (pu1 - pu0) * 0.5 * aspect, 0.25) * 1.06 / z
    local halfH = halfW / aspect
    cr = cr - (t.ox or 0) * 2 * halfW   -- (+ox: the model moves right)
    cu = cu + (t.oy or 0) * 2 * halfH   -- (+oy: the model moves down)
    return cr - halfW, cr + halfW, cu - halfH, cu + halfH
end

-- A gun / item model (spec.model) into the tile.
local function shootModel(ent, spec, tx, ty, tw, th)
    for k, v in pairs(spec.bodygroups or {}) do ent:SetBodygroup(k, v) end
    ent:SetupBones()
    local mins, maxs = boundsOf(ent)
    local center = (mins + maxs) * 0.5
    local auto
    if spec.angled then
        local d = Angle(-Icons.ANGLED[2], Icons.ANGLED[1], 0):Forward()   -- (from the model toward the camera)
        auto = (-d):Angle()
    else
        -- side on: look along the thinnest axis, longest across a wide
        -- picture (down a tall one; up for an upright square one)
        local ext = maxs - mins
        local axes = { { Vector(1, 0, 0), ext.x }, { Vector(0, 1, 0), ext.y }, { Vector(0, 0, 1), ext.z } }
        table.sort(axes, function(a, b) return a[2] > b[2] end)
        local H, V = axes[1][1], axes[2][1]
        if th > tw or (tw == th and axes[1][1].z == 1) then H, V = axes[2][1], axes[1][1] end
        if spec.flip then H = -H end
        auto = V:Cross(H):AngleEx(V)
    end
    spec.autoAng = auto
    local ang = viewAngle(spec, auto)
    local r0, r1, u0, u1, f0, f1 = project(mins, maxs, center, ang:Right(), ang:Up(), ang:Forward())
    local c = spec.color
    local function draw(white)
        if white then
            render.MaterialOverride(WHITE)
            ent:DrawModel()
            render.MaterialOverride()
            return
        end
        if istable(c) and c.r then render.SetColorModulation(c.r / 255, c.g / 255, c.b / 255) end
        render.SetBlend(1)
        ent:DrawModel()
        render.SetColorModulation(1, 1, 1)
    end
    local pr0, pr1, pu0, pu1 = silhouette(center, ang, r0, r1, u0, u1, f0, f1, draw)
    if not pr0 then pr0, pr1, pu0, pu1 = r0, r1, u0, u1 end   -- (nothing lit: the bounds)
    pr0, pr1, pu0, pu1 = finalBox(spec, pr0, pr1, pu0, pu1, tw, th)
    render.ClearDepth()
    startCam(tx, ty, tw, th, center, ang, pr0, pr1, pu0, pu1, f0, f1, 1)
        lights()
        draw(false)
    endCam()
end

-- A gear part on the player model, alone, into the tile.
local function shootPart(ent, spec, tx, ty, tw, th)
    local GG = Rhylib.Gear
    local me = LocalPlayer()
    ent.GetPlayerColor = function() return IsValid(me) and me:GetPlayerColor() or Vector(1, 1, 1) end
    if IsValid(me) then ent:SetSkin(me:GetSkin()) end
    local seq = ent:LookupSequence("idle_all_01")
    if seq and seq > 0 then ent:ResetSequence(seq) ent:SetCycle(0) end
    local info = GG.ModelInfo(ent)
    local sh = GG.SHOWS[spec.part]
    -- base: helmet on, every gear group empty, no hair
    local base = {}
    local helm = info.groups.helmet
    if helm then
        local want
        for name, i in pairs(helm.opts) do
            if string.find(name, "helmet", 1, true) and (not want or i < want) then want = i end
        end
        if want then base[helm.id] = want end
    end
    for gn in pairs(GG.ALL_GROUPS) do
        local g = info.groups[gn]
        if g and g.opts.empty then base[g.id] = g.opts.empty end
    end
    for _, gn in ipairs({ "hair", "fhair" }) do
        local g = info.groups[gn]
        if g and g.opts.empty then base[g.id] = g.opts.empty end
    end
    local with = table.Copy(base)
    local any = false
    for _, gn in ipairs(sh.groups) do
        local g = info.groups[gn]
        local idx = g and GG.Option(g, sh.on)
        if idx then
            with[g.id] = idx
            any = true
            -- (the body pass must not have the part: some other option)
            if base[g.id] == nil or base[g.id] == idx then
                base[g.id] = g.opts.empty or g.opts.blank or g.opts.none or (idx == 0 and 1 or 0)
            end
        end
    end
    if not any then error("part not on this model") end
    local view = Icons.PART_VIEW[sh.slot] or { 20, 5 }
    local auto = (-Angle(-view[2], view[1], 0):Forward()):Angle()
    spec.autoAng = auto
    local ang = viewAngle(spec, auto)
    local fwd, right, up = ang:Forward(), ang:Right(), ang:Up()
    setGroups(ent, with)
    local mins, maxs = boundsOf(ent)
    local center = (mins + maxs) * 0.5
    local r0, r1, u0, u1, f0, f1 = project(mins, maxs, center, right, up, fwd)
    -- the body without the part, nudged toward the camera, depth only:
    -- then only what sticks out of the body passes the depth test
    -- (same mesh and bones, so depth matches closely: a small nudge keeps
    -- flat parts like straps; drawn opaque so see-through visors hide too)
    local NUDGE = 0.2
    local function hiddenBody()
        ent:SetPos(-fwd * NUDGE)
        setGroups(ent, base)
        render.OverrideColorWriteEnable(true, false)
        render.MaterialOverride(WHITE)
        ent:DrawModel()
        render.MaterialOverride()
        render.OverrideColorWriteEnable(false)
        ent:SetPos(vector_origin)
        setGroups(ent, with)
    end
    local function draw(white)
        hiddenBody()
        if white then render.MaterialOverride(WHITE) end
        render.SetBlend(1)
        ent:DrawModel()
        if white then render.MaterialOverride() end
    end
    local pr0, pr1, pu0, pu1 = silhouette(center, ang, r0, r1, u0, u1, f0, f1, draw)
    if not pr0 then error("part not visible") end
    pr0, pr1, pu0, pu1 = finalBox(spec, pr0, pr1, pu0, pu1, tw, th)
    render.ClearDepth()
    startCam(tx, ty, tw, th, center, ang, pr0, pr1, pu0, pu1, f0, f1, 1)
        lights()
        draw(false)
    endCam()
end

-- Render one picture into rt at x, y (tw x th) on the category colour.
-- Errors can't leave the render state broken. Returns ok.
local function renderTile(rt, rtW, rtH, x, y, tw, th, body, sp)
    local lightMode = render.GetLightingMode and render.GetLightingMode() or 0
    if lightMode ~= 0 then render.SetLightingMode(0) end   -- (night vision sets fullbright in PreRender)
    local function attempt()
        render.PushRenderTarget(rt)
        -- the tile's background (a viewport clear: no screen-size clipping)
        render.SetViewPort(x, y, tw, th)
        render.Clear(body.r, body.g, body.b, 255, true, true)
        render.SetViewPort(0, 0, rtW, rtH)
        render.OverrideAlphaWriteEnable(true, false)   -- (alpha stays 255 from the clear)
        local ent = ClientsideModel(sp.model, RENDERGROUP_OPAQUE)
        local ok = IsValid(ent)
        if ok then
            ent:SetNoDraw(true)
            ent:SetPos(vector_origin)
            ent:SetAngles(angle_zero)
            ok = pcall(sp.part and shootPart or shootModel, ent, sp, x, y, tw, th)
            ent:Remove()
        end
        -- (put everything back, whatever happened)
        while camDepth > 0 do endCam() end
        while rtDepth > 0 do render.PopRenderTarget() rtDepth = rtDepth - 1 end
        render.SetBlend(1)
        render.MaterialOverride()
        render.OverrideColorWriteEnable(false)
        render.SetColorModulation(1, 1, 1)
        render.SuppressEngineLighting(false)
        render.OverrideAlphaWriteEnable(false)
        render.PopRenderTarget()
        return ok
    end
    local _, ok = pcall(attempt)
    if lightMode ~= 0 then render.SetLightingMode(lightMode) end
    return ok
end

-- The fallback when a gear part doesn't work on your model: the item's own model.
local function ownModelSpec(def, spec)
    local sw = def.weapon and weapons.Get(def.weapon)
    local m = (sw and valid(sw.WorldModel) and sw.WorldModel) or (valid(def.model) and def.model) or FALLBACK
    return { id = def.id, tune = spec.tune, model = m, angled = true, w = spec.w, h = spec.h }
end
Icons.OwnModelSpec = ownModelSpec

-- Spots of pictures being made again (one changed setting): reused when
-- the size is the same, so tuning doesn't fill the pages.
local reuse = {}

local function build(def)
    local spec = Icons.Spec(def)
    local tw, th = spec.w * U, spec.h * U
    local p, x, y
    local old = reuse[def.id]
    reuse[def.id] = nil
    if old and old.tw == tw and old.th == th and old.page.ready then
        p, x, y = old.page, old.x, old.y
    else
        p, x, y = reserve(tw, th)
    end
    if not p then return false end
    local cat = Inv.CATEGORY_COLORS[def.category] or Inv.CATEGORY_COLORS.misc
    local ok = renderTile(p.rt, PAGE, PAGE, x, y, tw, th, cat.body, spec)
    -- (any wearable part, whichever picture it got: remade if your model
    -- changes, e.g. from cadet to your battalion's model after loading in)
    local GG = Rhylib.Gear
    local me = LocalPlayer()
    if GG and GG.SHOWS and GG.SHOWS[def.id] and IsValid(me) then builtFor = me:GetModel() end
    if not ok and spec.part then ok = renderTile(p.rt, PAGE, PAGE, x, y, tw, th, cat.body, ownModelSpec(def, spec)) end
    if not ok then return false end
    local half = 0.5 / PAGE
    entries[def.id] = { page = p, u0 = x / PAGE + half, v0 = y / PAGE + half, u1 = (x + tw) / PAGE - half, v1 = (y + th) / PAGE - half,
        w = spec.w, h = spec.h, x = x, y = y, tw = tw, th = th }
    return true
end
Icons.RenderTile = renderTile

local function process()
    -- one a frame (each reads its silhouette back from the GPU); ones
    -- already made are skipped for free
    while #queue > 0 do
        local id = table.remove(queue, 1)
        queued[id] = nil
        local def = Items.Get(id)
        if def and not entries[id] then
            local ok, built = pcall(build, def)
            if not (ok and built) then entries[id] = false end   -- (no room / failed: not drawn)
            break
        end
    end
    if #queue == 0 then Rhylib.Hook.Remove("PreRender", "inventory.icons") end
end

local function enqueue(id)
    if queued[id] then return end
    queued[id] = true
    queue[#queue + 1] = id
    -- (early: before anything else changes the lighting in PreRender)
    if #queue == 1 then Rhylib.Hook.Add("PreRender", "inventory.icons", function() process() end, -1000) end
end

-- Where an item's picture goes inside x, y, w, h (centred): dx, dy, dw,
-- dh, entry, turned; nil while it's still being made. rot: the item lies
-- turned (the picture turns with it).
function Icons.Fit(def, x, y, w, h, rot)
    local e = entries[def.id]
    if e == nil then enqueue(def.id) return nil end
    if not e then return nil end
    local tw, th = e.w, e.h
    local turned = rot and tw ~= th
    if turned then tw, th = th, tw end
    local k = math.min(w / tw, h / th)
    local dw, dh = math.floor(tw * k), math.floor(th * k)
    return math.floor(x + (w - dw) * 0.5), math.floor(y + (h - dh) * 0.5), dw, dh, e, turned
end

-- Draw it (same arguments plus alpha). Returns whether it was drawn.
local tmpPoly = { { x = 0, y = 0, u = 0, v = 0 }, { x = 0, y = 0, u = 0, v = 0 }, { x = 0, y = 0, u = 0, v = 0 }, { x = 0, y = 0, u = 0, v = 0 } }
function Icons.Draw(def, x, y, w, h, rot, alpha)
    local dx, dy, dw, dh, e, turned = Icons.Fit(def, x, y, w, h, rot)
    if not dx then return false end
    surface.SetMaterial(e.page.mat)
    surface.SetDrawColor(255, 255, 255, alpha or 255)
    if not turned then
        surface.DrawTexturedRectUV(dx, dy, dw, dh, e.u0, e.v0, e.u1, e.v1)
    else
        -- a quarter turn clockwise: the picture's left edge ends up on top
        local p = tmpPoly
        p[1].x, p[1].y, p[1].u, p[1].v = dx, dy, e.u0, e.v1
        p[2].x, p[2].y, p[2].u, p[2].v = dx + dw, dy, e.u0, e.v0
        p[3].x, p[3].y, p[3].u, p[3].v = dx + dw, dy + dh, e.u1, e.v0
        p[4].x, p[4].y, p[4].u, p[4].v = dx, dy + dh, e.u1, e.v1
        surface.DrawPoly(p)
    end
    draw.NoTexture()   -- (don't leave the picture page bound for later DrawPolys)
    return true
end

-- Make every picture again (lazily, as they're drawn).
function Icons.Reset()
    entries, queue, queued, builtFor, reuse = {}, {}, {}, nil, {}
    for _, p in pairs(pages) do p.ready = false end
    Rhylib.Hook.Remove("PreRender", "inventory.icons")
end
Icons.Reset()

concommand.Add("rhylib_inventory_icons", function() Icons.Reset() print("[Rhylib] Inventory pictures will be made again") end)
-- Render targets can lose their contents when the screen mode changes or
-- the game comes back from alt-tab (device reset): make them again then.
-- Also when your player model changes (the gear part pictures use it).
Rhylib.Hook.Add("OnScreenSizeChanged", "inventory.icons", function() Icons.Reset() end)
local hadFocus = true
timer.Create("Rhylib.Inventory.IconFocus", 1, 0, function()
    local f = system.HasFocus()
    if f and not hadFocus and next(entries) ~= nil then Icons.Reset() end
    hadFocus = f
    local me = LocalPlayer()
    local m = IsValid(me) and me:GetModel() or nil
    if m and builtFor and m ~= builtFor then Icons.Reset() end
end)

--------------------------------------------------------------------------
-- Saved settings (sv_25_icons) and making every picture at load-in
--------------------------------------------------------------------------

-- Queue every item's picture, so the inventory is ready when opened.
function Icons.PrebuildAll()
    if Items.EnsureReady then Items.EnsureReady() end
    for id in pairs(Items.defs) do
        if entries[id] == nil then enqueue(id) end
    end
end

Rhylib.Net.Receive("inv.icontunes", function()
    local full = net.ReadBool()
    local n = net.ReadUInt(12)
    if full then Icons.TUNE = {} end
    for _ = 1, n do
        local id = net.ReadString()
        local t
        if net.ReadBool() then
            t = {}
            if net.ReadBool() then t.p, t.y, t.r = net.ReadFloat(), net.ReadFloat(), net.ReadFloat() end
            t.z, t.ox, t.oy = net.ReadFloat(), net.ReadFloat(), net.ReadFloat()
        end
        Icons.TUNE[id] = t
        if not full then
            -- (made again the next time it's drawn, in the same spot)
            local e = entries[id]
            if e then reuse[id] = { page = e.page, x = e.x, y = e.y, tw = e.tw, th = e.th } end
            entries[id] = nil
        end
    end
    if full then
        Icons.Reset()
        Icons.PrebuildAll()
    end
end)

-- Ask for the saved settings once loaded in; no answer for a while
-- (an old server without them): build anyway.
Rhylib.Hook.Add("InitPostEntity", "inventory.iconprebuild", function()
    timer.Simple(1, function()
        Rhylib.Net.Start("inv.icontunesreq")
        net.SendToServer()
    end)
    timer.Simple(10, function()
        if next(entries) == nil and #queue == 0 then Icons.PrebuildAll() end
    end)
end)

--------------------------------------------------------------------------
-- Picture editor (staff, rhylib.inventory.icons): inventory right-click
-- "Adjust picture", or rhylib_inventory_icon_edit <item id>. Turn, tilt,
-- roll, zoom and move with a live preview; Save sends it to the server,
-- which keeps it and gives it to everyone.
--------------------------------------------------------------------------

local EDIT = 1024
local editRT, editMat
local ed

local function editTarget()
    if not editRT then
        editRT = GetRenderTargetEx("rhylib_inv_icons_edit", EDIT, EDIT, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGBA8888)
        editMat = CreateMaterial("rhylib_inv_icons_editm", "UnlitGeneric", { ["$basetexture"] = editRT:GetName(), ["$vertexcolor"] = 1, ["$vertexalpha"] = 1 })
        editMat:SetTexture("$basetexture", editRT)
    end
    return editRT
end

local function editRender()
    if not (ed and ed.dirty and IsValid(ed.win)) then return end
    ed.dirty = false
    local sp = table.Copy(ed.spec)
    sp.tune = ed.t
    local cat = Inv.CATEGORY_COLORS[ed.def.category] or Inv.CATEGORY_COLORS.misc
    local rt = editTarget()
    local ok = renderTile(rt, EDIT, EDIT, 0, 0, ed.pw, ed.ph, cat.body, sp)
    if not ok and sp.part then
        sp = ownModelSpec(ed.def, sp)
        sp.tune = ed.t
        renderTile(rt, EDIT, EDIT, 0, 0, ed.pw, ed.ph, cat.body, sp)
    end
    -- (the automatic view, for the sliders until they're moved)
    if sp.autoAng and not ed.auto then
        local p, y, r = Icons.AngleToView(sp.autoAng)
        ed.auto = { p = p, y = y, r = r }
    end
end

local function send(id, t)
    Rhylib.Net.Start("inv.icontune")
    net.WriteString(id)
    net.WriteBool(t == nil)
    if t then
        net.WriteBool(t.y ~= nil)
        if t.y ~= nil then
            net.WriteFloat(t.p or 0)
            net.WriteFloat(t.y)
            net.WriteFloat(t.r or 0)
        end
        net.WriteFloat(t.z or 1)
        net.WriteFloat(t.ox or 0)
        net.WriteFloat(t.oy or 0)
    end
    net.SendToServer()
end

function Icons.OpenEditor(id)
    local def = Items.Get(id)
    local M = Rhylib.Menus
    local K = M and M.Kit
    if not (def and K) then print("[Rhylib] No such item, or rhylib_menus is missing: " .. tostring(id)) return end
    if ed and IsValid(ed.win) then
        local old = ed.win
        ed = nil
        old:Remove()
    end
    local spec = Icons.Spec(def)
    local saved = Icons.TUNE[id]
    local t = { z = saved and saved.z or 1, ox = saved and saved.ox or 0, oy = saved and saved.oy or 0 }
    if saved and saved.y then t.p, t.y, t.r = saved.p or 0, saved.y, saved.r or 0 end
    local per = math.floor(math.min(EDIT / spec.w, EDIT * 0.5 / spec.h))
    ed = { def = def, spec = spec, t = t, dirty = true, pw = spec.w * per, ph = spec.h * per }
    Rhylib.Hook.Add("PreRender", "inventory.iconedit", function() editRender() end, -999)

    local S, C = K.S, K.C
    local f = vgui.Create("EditablePanel")
    ed.win = f
    M.prompts[f] = true
    f:SetSize(math.min(S(1100), ScrW() - S(40)), math.min(S(600), ScrH() - S(40)))
    f:Center()
    f:MakePopup()
    f:DockPadding(S(12), S(46), S(12), S(12))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Item picture: " .. (def.name or id), sub = "Saved pictures are kept on the server and everyone gets them", ticks = "all", header = S(34) })
    end
    function f:OnRemove()
        M.prompts[self] = nil
        -- (Remove() is deferred: a newer editor may own the hook by now)
        if ed and ed.win == self then
            ed = nil
            Rhylib.Hook.Remove("PreRender", "inventory.iconedit")
        end
    end

    local side = vgui.Create("DPanel", f)
    side:Dock(RIGHT)
    side:SetWide(S(400))
    side:DockMargin(S(12), 0, 0, 0)
    side.Paint = nil

    -- the preview, as big as fits, and at the size it has in a cell row
    local view = vgui.Create("DPanel", f)
    view:Dock(FILL)
    function view:Paint(w, h)
        surface.SetDrawColor(C.row)
        surface.DrawRect(0, 0, w, h)
        if not editMat then return end
        local k = math.min((w - S(20)) / ed.pw, (h - S(130)) / ed.ph)
        local dw, dh = math.floor(ed.pw * k), math.floor(ed.ph * k)
        local dx, dy = math.floor((w - dw) * 0.5), S(10)
        surface.SetMaterial(editMat)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRectUV(dx, dy, dw, dh, 0, 0, ed.pw / EDIT, ed.ph / EDIT)
        -- (about how big it is in the inventory)
        local cell = S(80)
        local sw, sh = math.floor(spec.w * cell * 0.86), math.floor(spec.h * cell * 0.7)
        local kk = math.min(sw / ed.pw, sh / ed.ph)
        local qw, qh = math.floor(ed.pw * kk), math.floor(ed.ph * kk)
        surface.SetMaterial(editMat)
        surface.DrawTexturedRectUV(math.floor((w - qw) * 0.5), h - qh - S(12), qw, qh, 0, 0, ed.pw / EDIT, ed.ph / EDIT)
        draw.NoTexture()
        surface.SetDrawColor(C.edgeDark)
        surface.DrawOutlinedRect(dx, dy, dw, dh)
        draw.SimpleText("In the inventory:", K.Font(12, 700), S(10), h - qh * 0.5 - S(12), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- sliders: the camera values start as the automatic view until moved
    local function angVal(k)
        if t.y ~= nil then return t[k] or 0 end
        return ed.auto and math.Round(ed.auto[k]) or 0
    end
    local function setAng(k, v)
        if t.y == nil then
            local a = ed.auto or { p = 0, y = 0, r = 0 }
            t.p, t.y, t.r = math.Round(a.p), math.Round(a.y), math.Round(a.r)
        end
        t[k] = v
        ed.dirty = true
    end
    local function row(title, lo, hi, dec, get, set)
        local r = K.Row(side, title)
        r:Dock(TOP)
        r:DockMargin(0, 0, 0, S(4))
        r.right:SetWide(S(250))
        local sl = K.Slider(r.right, lo, hi, dec, get, set)
        sl:Dock(FILL)
    end
    row("Turn", -180, 180, 0, function() return angVal("y") end, function(v) setAng("y", v) end)
    row("Tilt", -90, 90, 0, function() return angVal("p") end, function(v) setAng("p", v) end)
    row("Roll", -180, 180, 0, function() return angVal("r") end, function(v) setAng("r", v) end)
    row("Zoom", 0.25, 4, 2, function() return t.z end, function(v) t.z = v ed.dirty = true end)
    row("Move right", -0.5, 0.5, 2, function() return t.ox end, function(v) t.ox = v ed.dirty = true end)
    row("Move down", -0.5, 0.5, 2, function() return t.oy end, function(v) t.oy = v ed.dirty = true end)

    -- quick turns (a model lying the wrong way round)
    local quick = vgui.Create("DPanel", side)
    quick:Dock(TOP)
    quick:SetTall(S(30))
    quick:DockMargin(0, S(4), 0, S(4))
    quick.Paint = nil
    for i, q in ipairs({ { "Turn 180", "y", 180 }, { "Top / side", "p", 0 }, { "Roll 90", "r", 90 }, { "Roll 180", "r", 180 } }) do
        local b = K.Button(quick, q[1], function()
            local nv
            if q[2] == "p" then
                nv = angVal("p") < 45 and 89 or 0   -- (from above, or level)
            else
                nv = math.NormalizeAngle(angVal(q[2]) + q[3])
            end
            setAng(q[2], nv)
        end, { small = true })
        b:Dock(LEFT)
        b:SetWide(S(95))
        b:DockMargin(0, 0, i < 4 and S(6) or 0, 0)
    end

    local btns = vgui.Create("DPanel", side)
    btns:Dock(BOTTOM)
    btns:SetTall(S(34))
    btns.Paint = nil
    local save = K.Button(btns, "Save for everyone", function() send(id, t) end, { accent = true,
        tooltip = "Kept on the server: every player gets this picture when they load in" })
    save:Dock(RIGHT)
    save:SetWide(S(180))
    local auto = K.Button(btns, "Automatic", function()
        send(id, nil)
        t.p, t.y, t.r, t.z, t.ox, t.oy = nil, nil, nil, 1, 0, 0
        ed.dirty = true
    end, { tooltip = "Forget the saved settings: back to the automatic picture" })
    auto:Dock(RIGHT)
    auto:SetWide(S(110))
    auto:DockMargin(0, 0, S(6), 0)
    local close = K.Button(btns, "Close", function() f:Remove() end)
    close:Dock(LEFT)
    close:SetWide(S(80))
end

concommand.Add("rhylib_inventory_icon_edit", function(_, _, args)
    if not args[1] then print("rhylib_inventory_icon_edit <item id>  (e.g. rhylib_thermal)") return end
    Icons.OpenEditor(args[1])
end)
