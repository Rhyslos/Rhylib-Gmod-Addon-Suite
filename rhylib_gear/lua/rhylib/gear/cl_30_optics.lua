--[[
    Optics (client): the optics key (rhylib_optics_key) raises your
    macrobinoculars (or, without them, the rangefinder) and lowers them
    again. While up the gun is put away and the view goes through the
    viewer. The rangefinder has its own (from the show's rangefinder
    view, drawRangefinder): an elongated hexagon of pale glass with a slit
    in each side, the window's corners cut along the frame's slants and a
    V notch on its right; left: elevation and zoom, your grid position
    (metres), the target range with three zoom dots; right: a 0-200 m
    range scale with a marker and a N / E / S / W compass with the
    bearing; chevrons above and below and a pitch ladder that follows the
    spotting ring (rhylib_skills K.visorTarget; looking only, not in
    weapon mode). The macrobinoculars and
    handheld binoculars use this one (styled on the macrobinocular view
    from The Clone Wars):

      a wide window with cut corners, a notch in each side, the compass
      bar above it (heading ticks, red marker), the zoom scale on the left
      (the arrow moves with the mouse wheel), range / bearing / elevation
      and zoom boxes in the tab at the bottom, red markings.
      Clear glass with a faint grey tint; the flashlight key toggles night
      vision (green picture, crawling scanlines and TV static, a light
      around you). Solid black outside the window (an active module, like
      a scope); faint scanlines on the clear glass too.
      No crosshair (the weapon base hides its own while optics are up).

    Weapon mode (mode key rhylib_optics_mode_key, default middle mouse):
    the optics stay down (night vision too) but the view is 1x, the gun and
    crosshair come back and you can shoot; in first person the viewer is
    drawn under the normal HUD, in third person only the night vision
    shows. Back to looking: zoomed all the way out (no sudden zoom).

    Handheld binoculars (the rhylib_binoculars weapon, kind 3): the same
    viewer, raised and lowered by clicking with them in hand; the optics key
    only lowers them.

    Zoom: macrobinoculars x2 to x12, the rangefinder half that, handheld
    binoculars x2 to x20 (G.ZOOM_RANGE).

    Holding the helmet gear key (about 0.35 s) with optics up switches
    night vision (the flashlight key still does too); a tap acts when the
    key is let go.
    The helmet gear key (L) steps through it all: off -> binoculars ->
    sun visor -> off (the helmet slot holds one part at a time, so in
    practice binoculars / rangefinder -> off, or visor -> off, or lights
    on / off). With rhylib_inventory the binoculars / rangefinder
    follow your hands (G.AutoMode): a weapon out = weapon mode, gun put
    away = looking. Without it, L steps looking -> weapon mode -> visor.
    Middle mouse is freelook's alone (rhylib_thirdperson).
    In third person worn optics (macrobinoculars, rangefinder) stay in
    weapon mode: you stay in third person, they flip down and night vision
    works, but there's no viewer or zoom (switch to first person for those).

    Sun visor (worn and the helmet on): down, red night vision is always
    on, a grid and scan line under the HUD (masked to rhylib_hud's visor
    opening), and aiming a Rhylib gun (right mouse, not through a scope)
    gives a fixed zoom (config visorZoom).

    Client only. Client convars: rhylib_optics_key (default l),
    rhylib_optics_mode_key (an optional extra key that only switches
    looking <-> weapon mode, and toggles the visor zoom; unbound by
    default); both in Settings > Gear.
    Sends rhylib.gear.optics, rhylib.gear.visor, rhylib.gear.lights.
    Night vision also shows while rhylib_weapons' W.ScopeNV() is on (a
    scope with SWEP.ScopeNightVision, its own flashlight-key toggle).
    Sets for other client code: G.NightVision() (is it on?), G.NVLayer
    (the viewer's night vision picture), G.opticsFov
    (view FOV while looking), G.visorFov (visor zoom factor; the crosshair
    uses it).
]]

-- Plain white for untextured polygons (draw.NoTexture alone can leave
-- another texture bound).
local WHITE_MAT = Material("vgui/white")

local G = Rhylib.Gear
local UI = Rhylib.UI

local keyVar = CreateClientConVar("rhylib_optics_key", "l", true, false, "Helmet gear key: raises or lowers your macrobinoculars / rangefinder, or switches your helmet lights")
local modeVar = CreateClientConVar("rhylib_optics_mode_key", "", true, false, "Optional extra key that switches binoculars / rangefinder between looking and weapon mode (the helmet gear key does it too)")
-- (middle mouse belongs to freelook now: an old saved default moves off it, once)
if cookie.GetString("rhylib_optics_mode_v", "") ~= "2" then
    if string.lower(modeVar:GetString()) == "mouse3" then RunConsoleCommand("rhylib_optics_mode_key", "") end
    cookie.Set("rhylib_optics_mode_v", "2")
end

local zoomOf = {}   -- [kind] = current zoom
local nv = false
local wasDown = false
local smoothFov

local function visorDown()
    local me = LocalPlayer()
    return IsValid(me) and G.VisorDown(me)
end
local visorZoom = false   -- (the visor's zoom toggle)
local visorFov = 1        -- (eased zoom factor)

local function sendVisor(on)
    Rhylib.Net.Start("gear.visor")
    net.WriteBool(on)
    net.SendToServer()
end

local function kindUp()
    local me = LocalPlayer()
    return IsValid(me) and me:GetNW2Int("rhylib_optics", 0) or 0
end

-- Up and looking through them (not weapon mode).
local function looking()
    local me = LocalPlayer()
    return IsValid(me) and G.Looking(me)
end

local function range(kind) return G.ZOOM_RANGE[kind] or G.ZOOM_RANGE[1] end

local function zoom(kind)
    kind = kind or kindUp()
    local r = range(kind)
    local z = zoomOf[kind] or r[3]
    return math.Clamp(z, r[1], r[2])
end

-- (third person wanted: worn optics then stay in weapon mode, so the
-- camera stays behind you and the optics just flip down)
local function thirdPerson()
    local TP = Rhylib.ThirdPerson
    return TP and TP.Wanted and TP.Wanted() or false
end

local function send(kind, fire)
    Rhylib.Net.Start("gear.optics")
    net.WriteUInt(kind, 2)
    net.WriteBool(fire == true)
    net.WriteBool(thirdPerson())
    net.SendToServer()
end

-- G.SendOptics(kind, fire): ask the server to raise optics kind (0 = down).
-- Client. (The handheld binoculars weapon uses it.)
G.SendOptics = send

local function free()
    return not vgui.GetKeyboardFocus() and not gui.IsGameUIVisible() and not gui.IsConsoleVisible()
end

local keyDown = G.KeyDown   -- (sh_00_config.lua)

-- Helmet gear key: a tap acts on release (gearTap), holding it with optics
-- up switches night vision. Mode key: looking <-> weapon mode.
-- A tap of the helmet gear key: optics up (binoculars first) or down, the
-- sun visor, or the helmet lights (see the header for the order).
local function gearTap(me)
    -- (order: binoculars -> visor -> off; one helmet part is worn at a time)
    if kindUp() == 3 then
        send(0)   -- (handheld binoculars: just lowered)
    elseif kindUp() ~= 0 and looking() and not G.AutoMode() then
        send(kindUp(), true)   -- (looking -> weapon mode; with the inventory your hands decide)
    elseif kindUp() ~= 0 then
        send(0)
        if G.Active(me, "visor") then sendVisor(true) end
    elseif visorDown() then
        sendVisor(false)
    elseif G.OpticsAllowed(me, 1) then
        send(1)
    elseif G.OpticsAllowed(me, 2) then
        send(2)
    elseif G.Active(me, "visor") then
        sendVisor(true)
    elseif G.Active(me, "light") or (G.Worn(me, "light") == nil and not G.Cfg("lightNeeded") and G.HelmetOn(me)) then
        Rhylib.Net.Start("gear.lights")
        net.SendToServer()
    elseif not G.HelmetOn(me) then
        Rhylib.Notify(nil, "Put your helmet on first", "bad", "Gear")
    else
        Rhylib.Notify(nil, "You need macrobinoculars, a rangefinder, a sun visor or helmet lights worn", "bad", "Gear")
    end
end

-- Holding the helmet gear key this long (with optics up) switches night
-- vision instead of acting as a tap.
local HOLD_NV = 0.35
local pressAt, holdUsed

local modeWasDown = false
local lastTP = false
Rhylib.Hook.Add("Think", "gear.optics.key", function()
    local me = LocalPlayer()
    local down = keyDown(keyVar)
    if down and not wasDown and free() then
        pressAt, holdUsed = RealTime(), false
    end
    if down and pressAt and not holdUsed and RealTime() - pressAt >= HOLD_NV then
        holdUsed = true
        if kindUp() ~= 0 then
            nv = not nv
            surface.PlaySound("items/flashlight1.wav")
        end
    end
    if not down and wasDown and pressAt then
        if not holdUsed then gearTap(me) end
        pressAt = nil
    end
    wasDown = down
    local mdown = keyDown(modeVar)
    local kind = kindUp()
    if mdown and not modeWasDown and kind ~= 0 and free() and not (G.AutoMode() and kind ~= 3) then
        local toFire = looking()
        if not toFire then
            -- Back to looking: all the way out, so nothing jumps at you.
            zoomOf[kind] = range(kind)[1]
            smoothFov = nil
        end
        send(kind, toFire)
        surface.PlaySound("buttons/lightswitch2.wav")
    end
    -- Visor down: the mode key toggles its fixed zoom.
    if mdown and not modeWasDown and kind == 0 and visorDown() and free() then
        visorZoom = not visorZoom
        surface.PlaySound("buttons/lightswitch2.wav")
    end
    modeWasDown = mdown
    -- Switched first / third person with worn optics up: tell the server.
    local tp = thirdPerson()
    if kind ~= 0 and kind ~= 3 and tp ~= lastTP then
        if tp then send(kind, true) elseif G.AutoMode() then send(kind, false) end
    end
    lastTP = tp
    if kind == 0 then
        smoothFov = nil
        if not visorDown() then
            nv = false
            visorZoom = false
        end
    end
end)

-- Mouse wheel zooms (smoothly, a step at a time), the flashlight key toggles night vision.
local ZOOM_STEP = 1.2
Rhylib.Hook.Add("PlayerBindPress", "gear.optics.binds", function(ply, bind, pressed)
    local kind = kindUp()
    if not pressed or kind == 0 then return end   -- (visor: F stays the lights key)
    if looking() and (string.find(bind, "invprev", 1, true) or string.find(bind, "invnext", 1, true)) then
        local r = range(kind)
        local z = zoom(kind) * (string.find(bind, "invprev", 1, true) and ZOOM_STEP or 1 / ZOOM_STEP)
        zoomOf[kind] = math.Clamp(z, r[1], r[2])
        surface.PlaySound("buttons/lightswitch2.wav")
        return true
    elseif string.find(bind, "impulse 100", 1, true) then
        nv = not nv
        surface.PlaySound("items/flashlight1.wav")
        return true
    end
end, -60)

-- First person through the viewer, zoomed (before third person and the body camera).
Rhylib.Hook.Add("CalcView", "gear.optics.view", function(ply, pos, angles, fov)
    if ply ~= LocalPlayer() or not looking() then return end
    local want = fov / zoom()
    smoothFov = smoothFov and Lerp(math.min(1, FrameTime() * 10), smoothFov, want) or fov
    G.opticsFov = smoothFov   -- (Mark target: how wide the view is right now)
    return { origin = ply:EyePos(), angles = ply:EyeAngles(), fov = smoothFov, drawviewer = false }
end, -70)

Rhylib.Hook.Add("AdjustMouseSensitivity", "gear.optics.sens", function()
    if looking() then return 1 / zoom() end
    if visorFov > 1.01 then
        -- (on top of the gun's own aiming sensitivity, which this replaces)
        local wep = LocalPlayer():GetActiveWeapon()
        local w = IsValid(wep) and wep.AdjustMouseSensitivity and wep:AdjustMouseSensitivity() or 1
        return (tonumber(w) or 1) / visorFov
    end
end, -70)

-- Sun visor zoom (fixed, config gear visorZoom), first person only.
Rhylib.Hook.Add("CalcView", "gear.visor.zoom", function(ply, pos, angles, fov, znear, zfar)
    if ply ~= LocalPlayer() then return end
    -- (anything else taking the camera: drop the zoom at once, so the
    -- third person, body and death cameras get their frames)
    local TP = Rhylib.ThirdPerson
    local L, Med = Rhylib.Lying, Rhylib.Medical
    local usable = visorDown() and ply:Alive() and not ply:InVehicle() and ply:GetViewEntity() == ply
        and not (TP and TP.Active and TP.Active())
        and not (Med and Med.IsDown and Med.IsDown(ply))
        and not (L and L.Ragdoll and IsValid(L.Ragdoll(ply)))
    if not usable then
        visorFov = 1
        G.visorFov = 1
        return
    end
    -- (zoomed while aiming a Rhylib gun that has no scope of its own, or
    -- with the optional mode key's toggle)
    local wep = ply:GetActiveWeapon()
    local aiming = IsValid(wep) and wep.GetAiming and wep:GetAiming() and not (wep.Scoped and wep:Scoped())
    local want = (visorZoom or aiming) and math.max(1, G.Cfg("visorZoom")) or 1
    visorFov = Lerp(math.min(1, FrameTime() * 12), visorFov, want)
    if math.abs(visorFov - want) < 0.01 then visorFov = want end
    G.visorFov = visorFov   -- (the crosshair scales its spread by it)
    if visorFov <= 1.001 then return end
    local view = GAMEMODE:CalcView(ply, pos, angles, fov, znear, zfar)
    view.fov = (view.fov or fov) / visorFov
    return view
end, -69)

Rhylib.Hook.Add("PreDrawViewModel", "gear.optics.vm", function()
    if looking() then return true end
end, -110)

-- Night vision (config gear nvMode):
--   1 amplified (default): a wide shadowless light from the eyes (a
--     projected texture) whose strength follows the light already there
--     (auto gain: full in the dark, turned down in lit places), plus a
--     soft green filter that lifts the darks and squeezes the brights.
--   2 fully lit: the world drawn without lighting (render.SetLightingMode).
--   0 the green filter only.
-- 1 and 2 fade into dark green beyond nvRange, so it has a reach.
-- (the sun visor's night vision is always on while it's down: owner, it
-- only lifts the dark, so it's fine in daylight too)
-- (also a Rhy's gun's scope with ScopeNightVision on: rhylib_weapons W.ScopeNV)
local function scopeNV()
    local W = Rhylib.Weapons
    return W and W.ScopeNV and W.ScopeNV() or false
end
-- (a gun's own scope or sight in use: the optics' night vision rests, the
-- scope's own switch decides)
local function gunScoped()
    local me = LocalPlayer()
    local w = IsValid(me) and me:GetActiveWeapon()
    return IsValid(w) and w.Scoped and w:Scoped() or false
end
local function nvOn() return (nv and kindUp() ~= 0 and not gunScoped()) or (kindUp() == 0 and visorDown()) or scopeNV() end
local function nvMode()
    local m = G.Cfg("nvMode")
    return math.Clamp(math.floor(m), 0, 2)
end
G.NightVision = nvOn

-- Auto gain: how much light there already is where you are and where you look.
local gain = 1
local function lum(v) return v and (v.x * 0.3 + v.y * 0.59 + v.z * 0.11) or 0 end
local nextSample = 0
local function updateGain()
    if RealTime() < nextSample then return end
    nextSample = RealTime() + 0.1
    local me = LocalPlayer()
    local eye = me:EyePos()
    local tr = util.TraceLine({ start = eye, endpos = eye + me:GetAimVector() * 1500, filter = me, mask = MASK_OPAQUE })
    local l = math.max(lum(render.GetLightColor(eye)), lum(render.GetLightColor(tr.HitPos + tr.HitNormal * 4)))
    -- (dark ~0.01, a lit room ~0.2+, daylight 1+)
    local want = math.Clamp(1 - l * 4, 0.1, 1)
    gain = Lerp(0.35, gain, want)   -- (eases like a tube adjusting)
end

-- GMod's colour modify: add, then saturation (colour), then + luminance
-- x mul per channel, + brightness, then x contrast (a plain multiplier:
-- below 1 darkens everything). Green night vision keeps part of the real
-- colours (nvColour) with no per-channel mul (a negative mul turned
-- orange markings blue and blue ones red) and gets its green from a
-- multiply tint afterwards (greenTint, nvTint), which keeps every hue
-- where it was. The visor's red one does the same with its own amounts
-- (visorColour, visorTint) and a red multiply (redTint).
-- Both are boosted (less where it's already bright).
local tab = {
    ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 0,
    ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
}
local function filter(mode)
    local lift = G.Cfg("nvLift")
    local boost = math.max(1, G.Cfg("nvBoost"))
    local g = mode == 1 and gain or 1
    if mode == 0 then boost = boost + 0.6 end   -- (filter only: nothing else brightens it)
    -- (the sun visor's night vision is red, the optics' green)
    local red = kindUp() == 0 and visorDown()
    -- (red: colours kept by visorColour, tinted afterwards by redTint())
    tab["$pp_colour_addr"] = 0
    tab["$pp_colour_addg"] = red and 0 or lift * g
    tab["$pp_colour_addb"] = 0
    tab["$pp_colour_colour"] = math.Clamp(G.Cfg(red and "visorColour" or "nvColour"), 0, 1)
    tab["$pp_colour_mulr"] = 0
    tab["$pp_colour_mulg"] = 0
    tab["$pp_colour_mulb"] = 0
    tab["$pp_colour_brightness"] = lift * 0.5 * g
    tab["$pp_colour_contrast"] = 1 + (boost - 1) * g
    return tab
end

-- Mode 1: the amplifier light.
local amp
local function dropAmp()
    if IsValid(amp) then amp:Remove() end
    amp = nil
end
Rhylib.Hook.Add("PreRender", "gear.optics.nvamp", function()
    if not (nvOn() and nvMode() == 1) then
        if amp then dropAmp() end
        return
    end
    updateGain()
    if not IsValid(amp) then
        amp = ProjectedTexture()
        local m = Material("effects/flashlight/soft")
        amp:SetTexture((m and not m:IsError()) and "effects/flashlight/soft" or "effects/flashlight001")
        amp:SetEnableShadows(false)
        amp:SetNearZ(12)
        amp:SetFOV(120)
        amp:SetColor(Color(235, 255, 235))
    end
    local me = LocalPlayer()
    local ang = me:EyeAngles()
    local pos = me:EyePos()
    -- (third person: the light starts a little ahead of you, so it doesn't
    -- light your own helmet and back)
    if me:ShouldDrawLocalPlayer() then pos = pos + ang:Forward() * 40 end
    amp:SetPos(pos)
    amp:SetAngles(ang)
    amp:SetFarZ(math.max(200, G.Cfg("nvLightRange")))
    amp:SetBrightness(G.Cfg("nvGain") * gain)
    amp:Update()
end)

-- Mode 2: fully lit world; put back before the HUD and after the frame.
local lit = false
Rhylib.Hook.Add("PreRender", "gear.optics.nvlit", function()
    if nvOn() and nvMode() == 2 then
        render.SetLightingMode(1)
        lit = true
    end
end)
local function unlit()
    if lit then
        render.SetLightingMode(0)
        lit = false
    end
end
Rhylib.Hook.Add("PreDrawHUD", "gear.optics.nvlit", unlit)
Rhylib.Hook.Add("PostRender", "gear.optics.nvlit", unlit)

-- The reach: linear fog into dark green.
local function nvFog(scale)
    if not (nvOn() and nvMode() > 0) then return end
    -- (off by default: it hid everything past it, and binoculars look far)
    local range = G.Cfg("nvRange")
    if range <= 0 then return end
    scale = scale or 1
    range = math.max(200, range)
    local from = math.Clamp(G.Cfg("nvFadeFrom"), 0, range - 50)
    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogStart(from * scale)
    render.FogEnd(range * scale)
    render.FogMaxDensity(0.92)
    render.FogColor(4, 18, 6)
    return true
end
Rhylib.Hook.Add("SetupWorldFog", "gear.optics.nvfog", function() return nvFog(1) end)
Rhylib.Hook.Add("SetupSkyboxFog", "gear.optics.nvfog", function(scale) return nvFog(scale) end)


-- The visor's red night vision: the grey picture multiplied by red (the
-- screen times the colour), so it reads clearly red like the optics' green.
-- The visor's red: the screen times a pale red (visorTint: how red), so
-- colours keep their hue and only lean red, as the optics' green does.
local function redTint()
    local t = math.Clamp(G.Cfg("visorTint"), 0, 1)
    if t <= 0 then return end
    cam.Start2D()
    render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD)
    draw.NoTexture()
    local o = 255 * (1 - t)
    surface.SetDrawColor(255, o, o * 0.9, 255)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    render.OverrideBlend(false)
    cam.End2D()
end

-- The optics' green: the screen times a pale green (nvTint: how pale), so
-- reds stay red, blues blue, only everything leans green.
local function greenTint()
    local t = math.Clamp(G.Cfg("nvTint"), 0, 1)
    if t <= 0 then return end
    cam.Start2D()
    render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD)
    draw.NoTexture()
    local o = 255 * (1 - t)
    surface.SetDrawColor(o, 255, o, 255)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    render.OverrideBlend(false)
    cam.End2D()
end

Rhylib.Hook.Add("RenderScreenspaceEffects", "gear.optics.nv", function()
    if nvOn() then
        DrawColorModify(filter(nvMode()))
        if kindUp() == 0 and visorDown() then redTint() else greenTint() end
    end
end)

--------------------------------------------------------------------------
-- The viewer
--------------------------------------------------------------------------

local RED = Color(225, 45, 40)
local WHITE = Color(235, 238, 240)
local PANEL_CLEAR = Color(205, 214, 212, 235)
local PANEL_NV = Color(170, 235, 170, 235)
local PANEL_TEXT = Color(18, 26, 22)
local OUTSIDE = Color(0, 0, 0, 255)   -- (solid: an active module, like a scope)

-- Window outline (clockwise on screen), cached per screen size.
local shape
local function buildShape(w, h)
    local cx = w * 0.5
    local hw = math.min(w * 0.43, h * 0.78)
    local L, R = cx - hw, cx + hw
    local T, B = h * 0.21, h * 0.79           -- (centred: the middle is where you aim)
    local r = h * 0.035                       -- rounded corners
    local d = h * 0.022                       -- top middle drops by this (chamfered)
    local tm1, tm2 = cx - hw * 0.33, cx + hw * 0.33
    local tab = h * 0.065                     -- bottom tab height
    local tb1, tb2 = hw * 0.44, hw * 0.37     -- tab half-width at the bottom / top
    local ny = T + (B - T) * 0.5              -- side notches
    local nOut, nIn, nDepth = h * 0.075, h * 0.022, hw * 0.21

    local pts = {}
    local function add(x, y) pts[#pts + 1] = { x = x, y = y } end
    local function arc(ccx, ccy, a0, a1)
        for i = 0, 6 do
            local a = math.rad(a0 + (a1 - a0) * i / 6)
            add(ccx + math.cos(a) * r, ccy + math.sin(a) * r)
        end
    end
    arc(L + r, T + r, 180, 270)                  -- top left
    add(tm1 - d, T) add(tm1, T + d) add(tm2, T + d) add(tm2 + d, T)
    arc(R - r, T + r, 270, 360)                  -- top right
    add(R, ny - nOut * 0.5) add(R - nDepth, ny - nIn * 0.5) add(R - nDepth, ny + nIn * 0.5) add(R, ny + nOut * 0.5)
    arc(R - r, B - r, 0, 90)                     -- bottom right
    add(cx + tb1, B) add(cx + tb2, B - tab) add(cx - tb2, B - tab) add(cx - tb1, B)
    arc(L + r, B - r, 90, 180)                   -- bottom left
    add(L, ny + nOut * 0.5) add(L + nDepth, ny + nIn * 0.5) add(L + nDepth, ny - nIn * 0.5) add(L, ny - nOut * 0.5)

    -- A fan of triangles from the first point, each wound clockwise; drawn
    -- with stencil INVERT they fill the (concave) outline exactly.
    local tris = {}
    for i = 2, #pts - 1 do
        local a, b, c = pts[1], pts[i], pts[i + 1]
        local cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        if math.abs(cross) > 0.01 then
            tris[#tris + 1] = cross > 0 and { a, b, c } or { a, c, b }
        end
    end
    shape = { w = w, h = h, cx = cx, hw = hw, L = L, R = R, T = T, B = B, d = d, tm1 = tm1, tm2 = tm2,
        tab = tab, tb2 = tb2, ny = ny, pts = pts, tris = tris }
    return shape
end

local function S(n, h) return math.floor(n * h / 1080 + 0.5) end

local function tri(x1, y1, x2, y2, x3, y3)
    local cross = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)
    if cross < 0 then x2, y2, x3, y3 = x3, y3, x2, y2 end
    surface.DrawPoly({ { x = x1, y = y1 }, { x = x2, y = y2 }, { x = x3, y = y3 } })
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- Compass bar over the top middle: a tick every 2.5 degrees (long every 10), the heading at the marker.
local function drawCompass(sh, h, heading)
    local x0, x1 = sh.tm1 + sh.d, sh.tm2 - sh.d
    local yBase = sh.T + sh.d - S(6, h)
    local span = 40                              -- degrees across the bar
    local pxPerDeg = (x1 - x0) / span
    surface.SetDrawColor(RED)
    local first = math.ceil((heading - span / 2) / 2.5) * 2.5
    for deg = first, heading + span / 2, 2.5 do
        local x = sh.cx + (deg - heading) * pxPerDeg
        local major = math.abs(deg % 10) < 0.01
        local len = major and S(22, h) or S(13, h)
        surface.DrawRect(math.floor(x - 1), yBase - len, math.max(2, S(3, h)), len)
    end
    -- N, NE, E ... under their ticks (just inside the window).
    local font = UI.Font(S(15, h), 800)
    local first45 = math.ceil((heading - span / 2) / 45) * 45
    for deg = first45, heading + span / 2, 45 do
        local x = sh.cx + (deg - heading) * pxPerDeg
        local name = COMPASS[(math.floor(deg / 45 + 0.5) % 8) + 1]
        draw.SimpleText(name, font, x, yBase + S(16, h), RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    -- End posts and the marker.
    surface.DrawRect(x0 - S(2, h), yBase - S(30, h), S(4, h), S(30, h))
    surface.DrawRect(x1 - S(2, h), yBase - S(30, h), S(4, h), S(30, h))
    local m = S(14, h)
    tri(sh.cx, yBase - S(30, h) - m * 2, sh.cx + m, yBase - S(30, h), sh.cx - m, yBase - S(30, h))
end

-- Zoom scale left of the window: the arrow sits at the current zoom (top = most).
local function drawZoomScale(sh, h, frac, kind)
    local x = sh.L - S(52, h)
    local y0, y1 = sh.T + S(60, h), sh.B - S(90, h)
    local n = 15
    surface.SetDrawColor(WHITE)
    for i = 0, n - 1 do
        local y = y0 + (y1 - y0) * i / (n - 1)
        local long = i == 0 or i == n - 1
        surface.DrawRect(x - (long and S(10, h) or 0), y, long and S(46, h) or S(36, h), S(4, h))
    end
    local r = range(kind)
    local font = UI.Font(S(15, h), 800)
    draw.SimpleText("x" .. r[2], font, x - S(8, h), y0 - S(16, h), WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText("x" .. r[1], font, x - S(8, h), y1 + S(22, h), WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local ay = y1 - (y1 - y0) * frac
    local a = S(14, h)
    tri(x - S(4, h), ay + S(2, h), x - S(4, h) - a * 1.6, ay + S(2, h) - a, x - S(4, h) - a * 1.6, ay + S(2, h) + a)
end

-- Boxes in the bottom tab: elevation / bearing / range, then zoom and mode.
local function drawReadouts(sh, h, metres, heading, elev, z, kind)
    local panel = nv and PANEL_NV or PANEL_CLEAR
    local yTop = sh.B - sh.tab + S(12, h)
    local bh = S(46, h)
    local font = UI.Font(S(22, h), 800)
    local small = UI.Font(S(11, h), 700)
    -- Left box: three cells.
    local lw = sh.tb2 * 1.1
    local lx = sh.cx - sh.tb2 + S(10, h)
    local cells = {
        { string.format("%+03d", elev), "ELV" },
        { string.format("%03d", heading % 360), "BRG" },
        { metres and string.format("%04d", math.min(metres, 9999)) or "----", "RNG M" },
    }
    local cw = lw / #cells
    for i, c in ipairs(cells) do
        local x = lx + (i - 1) * cw
        surface.SetDrawColor(panel.r, panel.g, panel.b, panel.a - (i % 2 == 0 and 25 or 0))
        surface.DrawRect(x, yTop, cw - S(2, h), bh)
        draw.SimpleText(c[1], font, x + cw * 0.5, yTop + bh * 0.42, PANEL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(c[2], small, x + cw * 0.5, yTop + bh - S(7, h), PANEL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    -- Right box: two rows.
    local rx = lx + lw + S(12, h)
    local rw = sh.cx + sh.tb2 - S(10, h) - rx
    local rh = math.floor((bh - S(3, h)) / 2)
    surface.SetDrawColor(panel)
    surface.DrawRect(rx, yTop, rw, rh)
    surface.DrawRect(rx, yTop + rh + S(3, h), rw, rh)
    local mid = UI.Font(S(15, h), 800)
    draw.SimpleText(string.format("ZOOM x%.1f", z), mid, rx + rw * 0.5, yTop + rh * 0.5, PANEL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(nv and "NV ON" or "NV OFF", mid, rx + rw * 0.5, yTop + rh * 1.5 + S(3, h), PANEL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function keyName(var)
    local k = string.lower(var:GetString())
    if k == "" then return "?" end
    if k == "mouse3" then return "MIDDLE MOUSE" end
    return string.upper(k)
end

-- The night vision picture: faint green wash, scanlines crawling down, a
-- thin rolling band, flicker lines and grain, inside x0..x1 / y0..y1.
local function nvLayer(w, h, x0, y0, x1, y1)
    local now = RealTime()
    draw.NoTexture()
    -- Green wash, then scanlines that crawl down the picture.
    -- (faint: a strong wash flattened the picture)
    surface.SetDrawColor(30, 255, 60, 10)
    surface.DrawRect(0, 0, w, h)
    local step = math.max(3, S(4, h))
    local off = math.floor(now * 30) % step
    -- (light: they darkened the whole picture)
    surface.SetDrawColor(0, 35, 0, 34)
    for y = math.floor(y0) + off, y1, step do surface.DrawRect(0, y, w, math.max(1, math.floor(step / 2))) end
    -- TV static: a thin, faint rolling band, flickering lines and grain.
    local band = math.max(2, math.floor(h * 0.012))
    local by = y0 + ((now * 0.18) % 1) * (y1 - y0 + band) - band
    surface.SetDrawColor(170, 255, 170, 10)
    surface.DrawRect(0, by, w, band)
    for _ = 1, 10 do
        local ly = math.random(math.floor(y0), math.floor(y1))
        surface.SetDrawColor(190, 255, 190, math.random(10, 45))
        surface.DrawRect(0, ly, w, math.random(1, 2))
    end
    local gx0, gx1 = math.floor(x0), math.floor(x1)
    local gy0, gy1 = math.floor(y0), math.floor(y1)
    local px = math.max(1, S(2, h))
    for _ = 1, 700 do
        local v = math.random(120, 255)
        surface.SetDrawColor(v * 0.7, v, v * 0.7, math.random(12, 40))
        surface.DrawRect(math.random(gx0, gx1), math.random(gy0, gy1), px, px)
    end
end
-- G.NVLayer(w, h, x0, y0, x1, y1): the viewer's night vision picture
-- (rhylib_weapons' launcher sight draws it too).
G.NVLayer = nvLayer

-- The sun visor's picture (reference: the clones' red helmet
-- view): a square grid over the screen, a red scan line climbing up it,
-- light grain (more with night vision). Drawn under the HUD.
local function visorLayer(w, h)
    local now = RealTime()
    draw.NoTexture()
    -- Grid.
    local step = math.max(20, S(62, h))
    surface.SetDrawColor(255, 200, 200, 11)   -- (softer: 16 was harsh)
    for x = (w % step) * 0.5, w, step do surface.DrawRect(math.floor(x), 0, 1, h) end
    for y = (h % step) * 0.5, h, step do surface.DrawRect(0, math.floor(y), w, 1) end
    -- Scan line, bottom to top in 3.5 s with a soft glow under it, then a
    -- 3.5 s pause off screen (so it doesn't come back too often).
    local SWEEP, PAUSE = 3.5, 3.5
    local t = now % (SWEEP + PAUSE)
    if t < SWEEP then
        local glow = S(36, h)
        local y = h - (t / SWEEP) * (h + glow)
        surface.SetDrawColor(255, 60, 40, 14)
        surface.DrawRect(0, y, w, glow)
        surface.SetDrawColor(255, 70, 50, 26)
        surface.DrawRect(0, y, w, math.floor(glow * 0.3))
        surface.SetDrawColor(255, 90, 60, 140)
        surface.DrawRect(0, y, w, math.max(2, S(2, h)))
    end
    -- Grain.
    local px = math.max(1, S(2, h))
    for _ = 1, 500 do
        local v = math.random(120, 255)
        surface.SetDrawColor(v, v * 0.55, v * 0.5, math.random(8, 30))
        surface.DrawRect(math.random(0, w), math.random(0, h), px, px)
    end
end

--------------------------------------------------------------------------
-- The rangefinder's own viewer (kind 2), from the show's rangefinder view:
-- an elongated hexagon of pale glass with a slit in each side, a window
-- onto the world (its corners cut along the frame's slanted edges, a V
-- notch in its right side), readouts on the left, a range scale and a
-- compass on the right, chevrons above and below and a pitch ladder that
-- follows the spotting ring (rhylib_skills K.visorTarget).
-- Laid out on a 1600 x 900 design, scaled to fit and centred.
--------------------------------------------------------------------------

local RF_GLASS = Color(214, 242, 230, 209)
local RF_BOX = Color(196, 230, 216, 235)
local RF_INK = Color(244, 255, 250, 255)
local RF_DIM = Color(93, 122, 112, 255)
local RF_EDGE = Color(125, 154, 143, 255)
local RF_OUTER = { { 40, 340 }, { 690, 118 }, { 910, 118 }, { 1560, 340 }, { 1560, 560 }, { 910, 785 }, { 690, 785 }, { 40, 560 } }
local RF_BOXRECT = { { 320, 222 }, { 1280, 222 }, { 1280, 380 }, { 1160, 432 }, { 1280, 486 }, { 1280, 688 }, { 320, 688 } }

-- A convex polygon as DrawPoly vertices, wound clockwise on screen.
local function cwPoly(list)
    local area = 0
    for i = 1, #list do
        local a, b = list[i], list[i % #list + 1]
        area = area + (a.x * b.y - b.x * a.y)
    end
    if area >= 0 then return list end
    local out = {}
    for i = #list, 1, -1 do out[#out + 1] = list[i] end
    return out
end

-- The polygon (clockwise on screen) moved in by m.
local function insetPoly(poly, m)
    local n, lines, out = #poly, {}, {}
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local l = math.sqrt(dx * dx + dy * dy)
        lines[i] = { a[1] - dy / l * m, a[2] + dx / l * m, dx, dy }
    end
    for i = 1, n do
        local p, q = lines[(i + n - 2) % n + 1], lines[i]
        local den = p[3] * q[4] - p[4] * q[3]
        local t = ((q[1] - p[1]) * q[4] - (q[2] - p[2]) * q[3]) / den
        out[i] = { p[1] + p[3] * t, p[2] + p[4] * t }
    end
    return out
end

-- subj clipped to the convex polygon cl (both clockwise on screen).
local function clipPoly(subj, cl)
    local out = subj
    for i = 1, #cl do
        local a, b = cl[i], cl[i % #cl + 1]
        local function inside(p) return (b[1] - a[1]) * (p[2] - a[2]) - (b[2] - a[2]) * (p[1] - a[1]) >= 0 end
        local function cut(p, q)
            local den = (p[1] - q[1]) * (a[2] - b[2]) - (p[2] - q[2]) * (a[1] - b[1])
            local t = ((p[1] - a[1]) * (a[2] - b[2]) - (p[2] - a[2]) * (a[1] - b[1])) / den
            return { p[1] + t * (q[1] - p[1]), p[2] + t * (q[2] - p[2]) }
        end
        local inp = out
        out = {}
        for j = 1, #inp do
            local p, q = inp[j], inp[j % #inp + 1]
            if inside(q) then
                if not inside(p) then out[#out + 1] = cut(p, q) end
                out[#out + 1] = q
            elseif inside(p) then
                out[#out + 1] = cut(p, q)
            end
        end
    end
    return out
end

-- A straight band from (x1, y1) to (x2, y2), w thick.
local function bandPoly(x1, y1, x2, y2, w)
    w = math.max(1, w)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return nil end
    -- (square ends, so corners meet without a notch)
    local ex, ey = dx / len * w * 0.5, dy / len * w * 0.5
    x1, y1, x2, y2 = x1 - ex, y1 - ey, x2 + ex, y2 + ey
    local nx, ny = -dy / len * w * 0.5, dx / len * w * 0.5
    return cwPoly({ { x = x1 + nx, y = y1 + ny }, { x = x2 + nx, y = y2 + ny }, { x = x2 - nx, y = y2 - ny }, { x = x1 - nx, y = y1 - ny } })
end

-- Fan triangles from the first point (stencil INVERT fills a concave outline).
local function fanTris(pts)
    local tris = {}
    for i = 2, #pts - 1 do
        local a, b, c = pts[1], pts[i], pts[i + 1]
        local cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        if math.abs(cross) > 0.01 then tris[#tris + 1] = cross > 0 and { a, b, c } or { a, c, b } end
    end
    return tris
end

local rf
local function buildRF(w, h)
    local k = math.min(h / 900, w / 1600)
    local ox, oy = w * 0.5 - 800 * k, h * 0.5 - 450 * k
    local function P(x, y) return { x = ox + x * k, y = oy + y * k } end
    local g = { w = w, h = h, k = k, ox = ox, oy = oy, P = P }
    local function list(t)
        local out = {}
        for i, q in ipairs(t) do out[i] = P(q[1], q[2]) end
        return out
    end
    g.outer = cwPoly(list(RF_OUTER))
    local win = clipPoly(RF_BOXRECT, insetPoly(RF_OUTER, 22))
    g.win = list(win)
    g.winTris = fanTris(g.win)
    -- Outlines: the frame (thin), the window (thick white, thin dark inside).
    g.lines = {}
    local function outline(pts, wd, col)
        for i = 1, #pts do
            local a, b = pts[i], pts[i % #pts + 1]
            local q = bandPoly(a.x, a.y, b.x, b.y, wd * k)
            if q then g.lines[#g.lines + 1] = { q = q, col = col } end
        end
    end
    outline(g.outer, 2, RF_INK)
    outline(g.win, 5, RF_INK)
    outline(list(insetPoly(win, 3)), 1.5, RF_EDGE)
    -- Left boxes (mirror images about the slit).
    g.boxes = {
        cwPoly(list({ { 53, 358 }, { 296, 272 }, { 296, 433 }, { 53, 433 } })),
        cwPoly(list({ { 53, 469 }, { 296, 469 }, { 296, 630 }, { 53, 544 } })),
    }
    for _, b in ipairs(g.boxes) do outline(b, 3, RF_INK) end
    -- Slits: a tapering cut with a round end, both sides.
    g.slits = {}
    for _, side in ipairs({ -1, 1 }) do
        local function X(x) return side < 0 and x or 1600 - x end
        g.slits[#g.slits + 1] = cwPoly({ P(X(30), 437), P(X(112), 443), P(X(112), 458), P(X(30), 464) })
        local cap = {}
        for i = 0, 11 do
            local a = math.rad(i * 30)
            cap[#cap + 1] = P(X(112) + math.cos(a) * 7.5, 450.5 + math.sin(a) * 7.5)
        end
        g.slits[#g.slits + 1] = cwPoly(cap)
    end
    -- Chevrons: thin outline legs pointing at the centre, a filled one inside.
    g.chevLegs = {}
    for _, c in ipairs({ { 772, 126, 800, 214 }, { 828, 126, 800, 214 }, { 772, 777, 800, 689 }, { 828, 777, 800, 689 } }) do
        local a, b = P(c[1], c[2]), P(c[3], c[4])
        g.chevLegs[#g.chevLegs + 1] = bandPoly(a.x, a.y, b.x, b.y, 2 * k)
    end
    g.chevFill = { cwPoly(list({ { 784, 132 }, { 816, 132 }, { 800, 178 } })), cwPoly(list({ { 784, 771 }, { 816, 771 }, { 800, 725 } })) }
    -- Dots by the notch, zoom dots, the compass ring.
    local function disc(cx, cy, r)
        local pts = {}
        for i = 0, 15 do
            local a = math.rad(i * 22.5)
            pts[#pts + 1] = P(cx + math.cos(a) * r, cy + math.sin(a) * r)
        end
        return cwPoly(pts)
    end
    g.notchDots = { disc(1187, 435, 5), disc(1208, 435, 7.5), disc(1234, 434, 11.5) }
    g.zoomDots = { disc(252, 512, 21), disc(252, 555, 13), disc(252, 582, 7) }
    g.compass = P(1414, 440)
    g.ring = {}
    for i = 0, 35 do
        local a0, a1 = math.rad(i * 10), math.rad(i * 10 + 10)
        local function at(a, r) return P(1414 + math.cos(a) * r, 440 + math.sin(a) * r) end
        g.ring[#g.ring + 1] = cwPoly({ at(a0, 46.5), at(a1, 46.5), at(a1, 41.5), at(a0, 41.5) })
    end
    g.compassMark = cwPoly(list({ { 1406, 388 }, { 1422, 388 }, { 1414, 402 } }))
    -- Range scale ticks.
    g.scale = {}
    for i = 0, 8 do
        local a = P(1346, 578 - i * 32.5)
        g.scale[#g.scale + 1] = { x = a.x, y = a.y, w = (i % 4 == 0 and 22 or 12) * k }
    end
    g.winTop, g.winBot = oy + 236 * k, oy + 676 * k
    rf = g
    return g
end

local rfTri = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local function rfFont(px, weight, k)
    return UI.Font(math.max(6, math.floor(px * k * 1080 / ScrH() + 0.5)), weight)
end

local function drawRangefinder(fire)
    local kind = kindUp()
    local me = LocalPlayer()
    local w, h = ScrW(), ScrH()
    local g = (rf and rf.w == w and rf.h == h) and rf or buildRF(w, h)
    local k, P = g.k, g.P

    -- Stencil: 2 = inside the frame, 1 = the window (fan + INVERT).
    draw.NoTexture()
    surface.SetMaterial(WHITE_MAT)   -- (binds plain white for sure)
    render.SetStencilWriteMask(0xFF)
    render.SetStencilTestMask(0xFF)
    render.SetStencilReferenceValue(0)
    render.ClearStencil()
    render.SetStencilEnable(true)
    render.SetStencilWriteMask(2)
    render.SetStencilTestMask(2)
    render.SetStencilReferenceValue(2)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    render.OverrideColorWriteEnable(true, false)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawPoly(g.outer)
    render.SetStencilWriteMask(1)
    render.SetStencilReferenceValue(1)
    render.SetStencilPassOperation(STENCIL_INVERT)
    for _, t in ipairs(g.winTris) do surface.DrawPoly(t) end
    render.OverrideColorWriteEnable(false)
    render.SetStencilPassOperation(STENCIL_KEEP)

    -- Outside the frame: solid black.
    render.SetStencilTestMask(2)
    render.SetStencilReferenceValue(0)
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, w, h)
    -- The frame's glass (inside the frame, not the window).
    render.SetStencilTestMask(3)
    render.SetStencilReferenceValue(2)
    surface.SetDrawColor(RF_GLASS)
    surface.DrawRect(0, 0, w, h)
    -- The window: night vision, or clear glass with faint scanlines.
    render.SetStencilReferenceValue(3)
    if nv then
        local ok, err = pcall(nvLayer, w, h, P(320, 0).x, g.oy + 222 * k, P(1280, 0).x, g.oy + 688 * k)
        if not ok then render.SetStencilEnable(false) ErrorNoHalt(tostring(err) .. "\n") return end
    else
        surface.SetDrawColor(18, 24, 30, 22)
        surface.DrawRect(0, 0, w, h)
        local step = math.max(3, S(4, h))
        local off = math.floor(RealTime() * 30) % step
        surface.SetDrawColor(0, 0, 0, 34)
        for y = math.floor(g.oy + 222 * k) + off, g.oy + 688 * k, step do surface.DrawRect(0, y, w, math.max(1, math.floor(step / 2))) end
    end
    render.SetStencilEnable(false)
    draw.NoTexture()

    -- Slits, boxes, outlines.
    surface.SetDrawColor(RF_BOX)
    for _, q in ipairs(g.boxes) do surface.DrawPoly(q) end
    for _, l in ipairs(g.lines) do
        surface.SetDrawColor(l.col)
        surface.DrawPoly(l.q)
    end
    surface.SetDrawColor(0, 0, 0, 255)     -- (the slits cut through the frame's edge line)
    for _, q in ipairs(g.slits) do surface.DrawPoly(q) end
    surface.SetDrawColor(RF_INK)
    for _, q in ipairs(g.chevLegs) do surface.DrawPoly(q) end
    for _, q in ipairs(g.chevFill) do surface.DrawPoly(q) end
    for _, q in ipairs(g.notchDots) do surface.DrawPoly(q) end

    -- Readings.
    local ang = me:EyeAngles()
    local heading = (90 - ang.y) % 360
    local elev = math.floor(-ang.p + 0.5)
    local tr = util.TraceLine({ start = me:EyePos(), endpos = me:EyePos() + me:GetAimVector() * 32768, filter = me, mask = MASK_SHOT })
    local metres = tr.Hit and not tr.HitSky and math.floor(tr.HitPos:Distance(tr.StartPos) * 0.01905 + 0.5) or nil
    local z = fire and 1 or zoom(kind)
    local r = range(kind)
    local frac = math.Clamp(math.log(math.max(z, r[1]) / r[1]) / math.log(r[2] / r[1]), 0, 1)

    -- Zoom dots (lit by zoom step).
    local lit = z >= 5 and 3 or (z >= 3 and 2 or 1)
    for i, q in ipairs(g.zoomDots) do
        surface.SetDrawColor(RF_INK.r, RF_INK.g, RF_INK.b, i <= lit and 255 or 77)
        surface.DrawPoly(q)
    end

    -- Left readouts.
    local big, mid, small = rfFont(22, 600, k), rfFont(30, 600, k), rfFont(11, 600, k)
    local function at(x, y) local p = P(x, y) return p.x, p.y end
    local tx, ty = at(276, 352)
    draw.SimpleText("ELV · ZOOM", small, tx, ty, RF_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    tx, ty = at(276, 380)
    draw.SimpleText(string.format("%+03d  x%.1f", elev, z), big, tx, ty, RF_INK, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    local pos = me:GetPos() * 0.01905
    tx, ty = at(276, 408)
    draw.SimpleText(string.format("%d. %d. %d", math.floor(pos.x), math.floor(pos.y), math.floor(pos.z)), big, tx, ty, RF_INK, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    tx, ty = at(276, 425)
    draw.SimpleText("GRID", small, tx, ty, RF_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    tx, ty = at(210, 528)
    draw.SimpleText(metres and string.format("%04d", math.min(metres, 9999)) or "----", mid, tx, ty, RF_INK, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    tx, ty = at(210, 552)
    draw.SimpleText("RNG M", small, tx, ty, RF_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

    -- Range scale (0-200 m) and its marker.
    draw.NoTexture()
    surface.SetDrawColor(RF_INK)
    local th = math.max(2, math.floor(3 * k))
    for _, t in ipairs(g.scale) do surface.DrawRect(t.x, t.y, t.w, th) end
    local my = 579 - math.min(metres or 0, 200) / 200 * 260
    local m1, m2, m3 = P(1344, my), P(1322, my - 8), P(1322, my + 8)
    rfTri[1].x, rfTri[1].y, rfTri[2].x, rfTri[2].y, rfTri[3].x, rfTri[3].y = m1.x, m1.y, m3.x, m3.y, m2.x, m2.y
    surface.SetDrawColor(RF_INK.r, RF_INK.g, RF_INK.b, metres and 255 or 90)
    surface.DrawPoly(cwPoly(rfTri))
    local sf = rfFont(15, 600, k)
    tx, ty = at(1340, 312)
    draw.SimpleText("200", sf, tx, ty, RF_INK, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    tx, ty = at(1340, 584)
    draw.SimpleText("0", sf, tx, ty, RF_INK, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

    -- Compass: N / E / S / W turning with you, the mark at the top.
    draw.NoTexture()
    surface.SetDrawColor(RF_INK)
    for _, q in ipairs(g.ring) do surface.DrawPoly(q) end
    surface.DrawPoly(g.compassMark)
    local c = g.compass
    for i = 0, 7 do
        local a = math.rad(i * 45 + 22.5 - heading - 90)
        local q = bandPoly(c.x + math.cos(a) * 35 * k, c.y + math.sin(a) * 35 * k, c.x + math.cos(a) * 40 * k, c.y + math.sin(a) * 40 * k, 2 * k)
        if q then surface.DrawPoly(q) end
    end
    local nf, of = rfFont(15, 700, k), rfFont(12, 600, k)
    for i, l in ipairs({ "N", "E", "S", "W" }) do
        local a = math.rad((i - 1) * 90 - heading - 90)
        draw.SimpleText(l, i == 1 and nf or of, c.x + math.cos(a) * 27 * k, c.y + math.sin(a) * 27 * k,
            i == 1 and RF_INK or ColorAlpha(RF_INK, 205), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    tx, ty = at(1414, 518)
    draw.SimpleText(string.format("%03d", math.floor(heading + 0.5) % 360), big, tx, ty, RF_INK, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    tx, ty = at(1414, 538)
    draw.SimpleText("BRG", small, tx, ty, RF_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

    -- Pitch ladder: a dash every 5 degrees, following the spotting ring
    -- (the screen middle when nothing is ringed). Only while looking: in
    -- weapon mode it would sit over what you shoot at.
    if not fire then
        local lx = w * 0.5
        local K = Rhylib.Skills
        local t = K and K.visorTarget
        if IsValid(t) then
            local sp = t:WorldSpaceCenter():ToScreen()
            if sp.visible then lx = math.Clamp(sp.x, g.ox + 500 * k, g.ox + 1100 * k) end
        end
        draw.NoTexture()
        local lf = rfFont(11, 600, k)
        local base = math.floor(-ang.p / 5) * 5
        for a = math.max(base - 30, -90), math.min(base + 30, 90), 5 do
            local y = h * 0.5 + (-ang.p - a) * 9 * k
            if y >= g.winTop and y <= g.winBot then
                local major = a % 10 == 0
                local hw = (major and 14 or 8) * k
                surface.SetDrawColor(RF_INK.r, RF_INK.g, RF_INK.b, a == 0 and 255 or 190)
                surface.DrawRect(lx - hw, y - 2 * k, hw * 2, math.max(2, math.floor(4 * k)))
                if major then
                    draw.SimpleText((a > 0 and "+" or "") .. a, lf, lx + 22 * k, y, ColorAlpha(RF_INK, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.NoTexture()
                end
            end
        end

    end   -- (not fire: the ladder)

    if not fire then
        local hint = "Wheel: zoom  ·  hold " .. keyName(keyVar) .. ": night vision  ·  "
            .. (G.AutoMode() and "draw a weapon: weapon mode  ·  " .. keyName(keyVar) .. ": lower"
                or keyName(keyVar) .. ": weapon mode")
        draw.SimpleText(hint, UI.Font(S(13, h)), w * 0.5, h - S(36, h), Color(200, 200, 200, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

-- fire: weapon mode (drawn under the normal HUD, 1x).
local function drawViewer(fire)
    local kind = kindUp()
    if kind == 2 then return drawRangefinder(fire) end   -- (its own viewer)
    local me = LocalPlayer()
    local w, h = ScrW(), ScrH()
    local sh = (shape and shape.w == w and shape.h == h) and shape or buildShape(w, h)

    -- The window into the stencil (fan + INVERT = an exact concave fill).
    draw.NoTexture()
    surface.SetMaterial(WHITE_MAT)   -- (binds plain white for sure)
    render.SetStencilWriteMask(0xFF)
    render.SetStencilTestMask(0xFF)
    render.SetStencilReferenceValue(0)
    render.ClearStencil()
    render.SetStencilEnable(true)
    render.SetStencilWriteMask(1)
    render.SetStencilTestMask(1)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_INVERT)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    render.OverrideColorWriteEnable(true, false)
    surface.SetDrawColor(255, 255, 255, 255)
    for _, t in ipairs(sh.tris) do surface.DrawPoly(t) end
    render.OverrideColorWriteEnable(false)

    -- Outside: the viewer's dark body.
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
    surface.SetDrawColor(OUTSIDE)
    surface.DrawRect(0, 0, w, h)

    -- Inside: grey glass, or night vision scanlines.
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    if nv then
        local ok, err = pcall(nvLayer, w, h, sh.L, sh.T, sh.R, sh.B)
        if not ok then render.SetStencilEnable(false) ErrorNoHalt(tostring(err) .. "\n") return end
    else
        -- Glass with faint scanlines crawling down. Dark tint only: light
        -- grey here lifted the blacks, so you saw better in the dark with
        -- the binoculars than without (only night vision should brighten).
        surface.SetDrawColor(18, 24, 30, 22)
        surface.DrawRect(0, 0, w, h)
        local step = math.max(3, S(4, h))
        local off = math.floor(RealTime() * 30) % step
        surface.SetDrawColor(0, 0, 0, 34)
        for y = math.floor(sh.T) + off, sh.B, step do surface.DrawRect(0, y, w, math.max(1, math.floor(step / 2))) end
    end
    render.SetStencilEnable(false)

    -- Edge line around the window.
    surface.SetDrawColor(nv and 120 or 170, nv and 200 or 176, nv and 120 or 180, 60)
    local pts = sh.pts
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        surface.DrawLine(a.x, a.y, b.x, b.y)
    end

    -- Readings.
    local ang = me:EyeAngles()
    local heading = math.floor((90 - ang.y) % 360 + 0.5) % 360
    local elev = math.floor(-ang.p + 0.5)
    local tr = util.TraceLine({ start = me:EyePos(), endpos = me:EyePos() + me:GetAimVector() * 32768, filter = me, mask = MASK_SHOT })
    local metres = tr.Hit and not tr.HitSky and math.floor(tr.HitPos:Distance(tr.StartPos) * 0.01905 + 0.5) or nil
    local z = fire and 1 or zoom(kind)
    local r = range(kind)
    local frac = math.Clamp(math.log(math.max(z, r[1]) / r[1]) / math.log(r[2] / r[1]), 0, 1)

    drawCompass(sh, h, (90 - ang.y) % 360)
    drawZoomScale(sh, h, frac, kind)
    drawReadouts(sh, h, metres, heading, elev, z, kind)

    -- Red markings.
    local mark = UI.Font(S(17, h), 800)
    draw.SimpleText(kind == 1 and "MACROBINOCULARS · GAR ISSUE" or kind == 3 and "BINOCULARS · FIELD ISSUE" or "RANGEFINDER · HELMET MODULE", mark,
        sh.L + S(70, h), sh.T - S(22, h), RED, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText("ELEVATION · BEARING · TARGET RANGE", mark, sh.R - S(70, h), sh.B + S(28, h), RED, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

    if not fire then
        local hint = "Wheel: zoom  ·  hold " .. keyName(keyVar) .. ": night vision  ·  "
            .. (G.AutoMode() and "draw a weapon: weapon mode  ·  " .. keyName(keyVar) .. ": lower"
                or keyName(keyVar) .. ": weapon mode")
        draw.SimpleText(hint, UI.Font(S(13, h)), w * 0.5, h - S(36, h), Color(200, 200, 200, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

-- Looking: on top of everything.
Rhylib.Hook.Add("HUDPaint", "gear.optics.overlay", function()
    if looking() then drawViewer(false) end
end, 200)

-- Weapon mode, first person: the viewer under the HUD; rhylib_hud drops the
-- visor then, so the third-person HUD shows over it.
Rhylib.Hook.Add("HUDPaint", "gear.optics.under", function()
    local me = LocalPlayer()
    if kindUp() == 0 or looking() then return end
    -- (looking through a gun's own scope or sight: only that shows)
    local wep = me:GetActiveWeapon()
    if IsValid(wep) and wep.Scoped and wep:Scoped() then return end
    if not me:ShouldDrawLocalPlayer() then
        drawViewer(true)
    elseif nv then
        -- Third person (weapon mode): no viewer frame, the night vision
        -- picture over the whole screen (it used to be only the colour filter).
        local w, h = ScrW(), ScrH()
        nvLayer(w, h, 0, 0, w, h)
    end
end, -20)

-- The sun visor (down, no binoculars up): its picture under the HUD.
Rhylib.Hook.Add("HUDPaint", "gear.visor.layer", function()
    if kindUp() ~= 0 or not visorDown() then return end
    local me = LocalPlayer()
    if not me:Alive() then return end
    -- Only in the clear opening: the visor shell's (semi-transparent)
    -- brow and cheeks are written into the stencil and skipped.
    local tris = Rhylib.HUD and Rhylib.HUD.VisorShellTris and Rhylib.HUD.VisorShellTris()
    if not tris or #tris == 0 then
        visorLayer(ScrW(), ScrH())
        return
    end
    render.ClearStencil()
    render.SetStencilEnable(true)
    render.SetStencilWriteMask(255)
    render.SetStencilTestMask(255)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_REPLACE)
    render.OverrideColorWriteEnable(true, false)
    draw.NoTexture()
    surface.SetMaterial(WHITE_MAT)   -- (binds plain white for sure)
    surface.SetDrawColor(255, 255, 255, 255)
    for i = 1, #tris do surface.DrawPoly(tris[i]) end
    render.OverrideColorWriteEnable(false, false)
    render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    -- (an error inside must not leave the stencil on for the rest of the HUD)
    local ok, err = pcall(visorLayer, ScrW(), ScrH())
    render.SetStencilEnable(false)
    if not ok then ErrorNoHalt(tostring(err) .. "\n") end
end, -30)

-- Settings and the controls list (rhylib_menus).
Rhylib.Hook.Add("InitPostEntity", "gear.optics.setting", function()
    local Menus = Rhylib.Menus
    if not Menus then return end
    if Menus.AddSetting then
        Menus.AddSetting("Gear", { id = "gear.opticskey", order = 10, title = "Helmet gear: binoculars / rangefinder up or down, helmet lights on or off", kind = "key", convar = "rhylib_optics_key" })
        Menus.AddSetting("Gear", { id = "gear.opticsmode", order = 11, title = "Binoculars / rangefinder: weapon mode (extra key, optional)",
            desc = "The helmet gear key already steps from looking to weapon mode; bind this only if you want a second key for it", kind = "key", convar = "rhylib_optics_mode_key" })
    end
    if Menus.AddControl then
        Menus.AddControl("Gear", "Mouse wheel", "Zoom (binoculars / rangefinder up)")
        Menus.AddControl("Gear", "{impulse 100}", "Night vision (binoculars / rangefinder up; the sun visor has it always on)")
        Menus.AddControl("Gear", "Hold [rhylib_optics_key]", "Night vision on / off (binoculars / rangefinder up)")
        Menus.AddControl("Gear", "[rhylib_optics_key]", "Binoculars / rangefinder up or down (gun out: weapon mode, gun put away: looking)")
        Menus.AddControl("Gear", "Right mouse", "Sun visor down: aim for the 3x zoom")
    end
end)

-- No engine crosshair either (other weapons) while looking through them.
Rhylib.Hook.Add("HUDShouldDraw", "gear.optics.crosshair", function(name)
    if name == "CHudCrosshair" and looking() then return false end
end)
