--[[
    Weapon position editors (client; moved out of the weapon base so live
    servers don't send them to every player). Hold the gun, then:
      rhylib_vm_editor      first person: prop offset / size, VMOffset, AimPos,
                            FOV, the SafePose and ModeProxies blocks, and
                            grenades (PropVMPos / PropVMAng / PropVMScale),
                            the logistics build tools (VMOffset / VMAngle /
                            VMScale; WMOffset / WMAngle / WMScale in the
                            third-person editor);
                            Copy prints the lines for the weapon file
      rhylib_wm_editor      third person: PropWMPos / PropWMAng / PropScale
                            (and the left pistol's DualPropWM*), with an
                            orbit camera around the right hand
      rhylib_extra_editor   ExtraProps (both views), CarrierBoneMods,
                            WorldBoneMods
      rhylib_ear_editor     the hand-to-the-ear arm IK (rhylib_radio
                            config earIK), with the orbit camera
      rhylib_vm_info        what the held gun's viewmodel uses now
      rhylib_vm_aim r f u   AimPos;  rhylib_vm_fov n   ViewModelFOV
      rhylib_vm_tune ...    PropVMPos / PropVMAng by numbers
      rhylib_vm_bones       the current viewmodel's bone list
    The windows are Rhylib.Devtools.UI windows (cl_15_ui.lua, the same
    look as the pose editor): tabs on the left, the page in the middle,
    the orbit camera on the right where the editor has one, Copy on its
    own tab. Tabs:
      first person (gun)    Gun, Hands (carrier guns), Dual pistols,
                            Aim & FOV, Copy
      grenade / build tool  Prop (or Tool), Copy
      third person          Gun (or Tool), Left pistol (dual), Copy
      extras                First person, Third person (showing it turns
                            the orbit camera on, First person off), Copy
      ear                   Hand, Shoulder, Transition, Fingers,
                            Transform, Snapshots, Copy
    Hooks: CalcView "weapons.editorcam" (-60) and ShouldDrawLocalPlayer
    while an editor window with the orbit camera is open (the camera is
    Rhylib.Devtools.orbit, also used by the pose editor); the ear editor's
    gizmo: HUDPaint / GUIMousePressed / GUIMouseReleased / Think
    "devtools.eargizmo".
    Uses the weapon base's shared client helpers (Rhylib.Weapons.BaseClient,
    set by rhylib_base): carrierBone. Needs rhylib_weapons.
]]

-- The weapon base registers after autorun, so look the helper up when used.
local function carrierBone(w, vm)
    local env = Rhylib.Weapons and Rhylib.Weapons.BaseClient
    return env and env.carrierBone and env.carrierBone(w, vm) or nil
end

concommand.Add("rhylib_vm_bones", function()
    local vm = LocalPlayer():GetViewModel()
    if not IsValid(vm) then return end
    print("Bones of " .. tostring(vm:GetModel()))
    for i = 0, (vm:GetBoneCount() or 0) - 1 do print(i, vm:GetBoneName(i)) end
end)

-- Console helpers ----------------------------------------------------

local function held()
    local w = LocalPlayer():GetActiveWeapon()
    if not IsValid(w) or not w.IsRhylib or not w.PropModel then print("Hold a Rhy's prop weapon first") return nil end
    return w, LocalPlayer():GetViewModel()
end

concommand.Add("rhylib_vm_info", function()
    local w, vm = held()
    if not w or not IsValid(vm) then return end
    print("Viewmodel: " .. tostring(vm:GetModel()) .. (w:UsesCarrier() and "  (carrier)" or ""))
    local cb = w:UsesCarrier() and carrierBone(w, vm)
    print("Bones (index: name):")
    for i = 0, (vm:GetBoneCount() or 0) - 1 do
        print(string.format("  %d: %s%s", i, vm:GetBoneName(i) or "?", cb == i and "   [gun bone: hidden, prop on it]" or ""))
    end
end)

-- rhylib_vm_aim right forward up: the aim-down-sights offset (SWEP.AimPos)
concommand.Add("rhylib_vm_aim", function(_, _, args)
    local w = LocalPlayer():GetActiveWeapon()
    if not IsValid(w) or not w.AimPos then print("Hold a Rhy's weapon first") return end
    local x, y, z = tonumber(args[1]) or 0, tonumber(args[2]) or 0, tonumber(args[3]) or 0
    w.AimPos = Vector(x, y, z)
    print(string.format("SWEP.AimPos = Vector(%g, %g, %g)", x, y, z))
end)

-- rhylib_vm_fov n: the viewmodel FOV (SWEP.ViewModelFOV)
concommand.Add("rhylib_vm_fov", function(_, _, args)
    local w = LocalPlayer():GetActiveWeapon()
    if not IsValid(w) then return end
    w.ViewModelFOV = tonumber(args[1]) or w.ViewModelFOV
    print("SWEP.ViewModelFOV = " .. tostring(w.ViewModelFOV))
end)

-- Live tuning of the floating gun: rhylib_vm_tune x y z pitch yaw roll
-- (forward, right, up from the view; prints the lines for the weapon file).
concommand.Add("rhylib_vm_tune", function(_, _, args)
    local w = held()
    if not w then return end
    local n = {}
    for i = 1, 6 do n[i] = tonumber(args[i]) or 0 end
    w.PropVMPos, w.PropVMAng = Vector(n[1], n[2], n[3]), Angle(n[4], n[5], n[6])
    print(string.format("SWEP.PropVMPos = Vector(%g, %g, %g)\nSWEP.PropVMAng = Angle(%g, %g, %g)", n[1], n[2], n[3], n[4], n[5], n[6]))
end)

-- rhylib_vm_editor: rows for the held gun (prop in hand or floating,
-- aim offset, viewmodel FOV). Changes last until the weapon is removed;
-- Copy puts the lines for the weapon file on the clipboard.
local editor

local function editorLines(w, safe, px)
    local out = {}
    if px and not safe then
        local mode = w:GetFireModeName()
        out[1] = "-- in SWEP.ModeProxies (the " .. mode .. " block):"
        out[2] = string.format("        PropBonePos = Vector(%g, %g, %g),", px.PropBonePos:Unpack())
        out[3] = string.format("        PropBoneAng = Angle(%g, %g, %g),", px.PropBoneAng:Unpack())
        out[4] = string.format("        PropBoneScale = %g,", px.PropBoneScale or w.PropScale)
        out[5] = string.format("        VMOffset = Vector(%g, %g, %g),", (px.VMOffset or Vector()):Unpack())
        out[6] = string.format("-- and for the gun: SWEP.AimPos = Vector(%g, %g, %g)", w.AimPos.x, w.AimPos.y, w.AimPos.z)
        return table.concat(out, "\n")
    end
    if safe then
        out[1] = "SWEP.SafePose = {"
        out[2] = string.format("    PropBonePos = Vector(%g, %g, %g),", safe.PropBonePos:Unpack())
        out[3] = string.format("    PropBoneAng = Angle(%g, %g, %g),", safe.PropBoneAng:Unpack())
        out[4] = string.format("    PropBoneScale = %g,", safe.PropBoneScale)
        out[5] = string.format("    VMOffset = Vector(%g, %g, %g),", safe.VMOffset:Unpack())
        out[6] = string.format("    CarrierFOV = %g,", safe.CarrierFOV)
        out[7] = "}"
        return table.concat(out, "\n")
    end
    if w.rhylibModeCarrier then
        out[#out + 1] = "-- (fire mode \"" .. w.rhylibModeCarrier .. "\": these go in SWEP.ModeCarriers." .. w.rhylibModeCarrier .. ")"
    end
    local function v(name, x) out[#out + 1] = string.format("SWEP.%s = Vector(%g, %g, %g)", name, x.x, x.y, x.z) end
    local function a(name, x) out[#out + 1] = string.format("SWEP.%s = Angle(%g, %g, %g)", name, x.p, x.y, x.r) end
    if w:UsesCarrier() then
        v("PropBonePos", w.PropBonePos)
        a("PropBoneAng", w.PropBoneAng)
        out[#out + 1] = string.format("SWEP.PropBoneScale = %g", w.PropBoneScale or w.PropScale)
        v("VMOffset", w.VMOffset)
    else
        v("PropVMPos", w.PropVMPos)
        a("PropVMAng", w.PropVMAng)
    end
    v("AimPos", w.AimPos)
    if w.DualMirror and w.DualMirrorPos then
        out[#out + 1] = string.format("SWEP.DualSpread = %g", w.DualSpread or 0)
        v("DualMirrorPos", w.DualMirrorPos)
        a("DualMirrorAng", w.DualMirrorAng or Angle())
    end
    out[#out + 1] = w:UsesCarrier() and ("SWEP.CarrierFOV = " .. tostring(w.CarrierFOV)) or ("SWEP.ViewModelFOV = " .. tostring(w.ViewModelFOV))
    return table.concat(out, "\n")
end

-- Window helpers (Rhylib.Devtools.UI, cl_15_ui.lua) ------------------

-- The kit is looked up when an editor opens (cl_15 loads after this file).
local function kitUI()
    local DU = Rhylib.Devtools and Rhylib.Devtools.UI
    if not (DU and DU.Window) then print("Needs Rhy's Core with the UI kit") return nil end
    return DU
end

-- fn runs when the window closes (before the window's own OnRemove).
local function onClose(f, fn)
    local old = f.OnRemove
    function f:OnRemove(...)
        fn()
        if old then return old(self, ...) end
    end
end

-- A number row for w's values: - / + (hold to repeat) or type and Enter;
-- does nothing (and shows 0) once w is gone.
local function num(pg, w, label, step, lo, hi, get, set)
    return pg:Number(label, step, lo, hi,
        function() if not IsValid(w) then return 0 end return tonumber(get()) or 0 end,
        function(v) if IsValid(w) then set(v) end end)
end

-- Three rows for the parts of a Vector (x y z) or an Angle (p y r);
-- obj() gives the Vector / Angle (looked up each time).
local VEC, ANG = { "x", "y", "z" }, { "p", "y", "r" }
local POS, TURN = { "Forward", "Right", "Up" }, { "Pitch", "Yaw", "Roll" }
local function rows3(pg, w, labels, parts, step, range, obj)
    for i = 1, 3 do
        local c = parts[i]
        num(pg, w, labels[i], step, -range, range, function() return obj()[c] end, function(v) obj()[c] = v end)
    end
end

local function copyText(w, getText)
    if not IsValid(w) then return end
    local text = getText()
    SetClipboardText(text)
    print(text)
    chat.AddText(Color(120, 200, 255), "Copied (also printed in the console).")
end

-- The Copy tab: the lines as they are now, and the button.
local function copyTab(f, w, getText, head, button)
    f:AddTab("Copy", function(pg)
        pg:Heading(head or "Lines for the weapon file")
        pg:Note(function() return IsValid(w) and getText() or "" end)
        pg:Buttons({ { button or "Copy lines for the weapon file", function() copyText(w, getText) end, { accent = true } } })
        pg:Note("Also printed in the console.")
    end)
end

-- Grenades (rhylib_grenade_base, not Rhylib guns): their first-person
-- prop sits on the viewmodel's grenade bone (PropVMPos / PropVMAng /
-- PropVMScale).
local function grenadeEditor(w, DU)
    w.PropVMPos = Vector(w.PropVMPos:Unpack())
    w.PropVMAng = Angle(w.PropVMAng:Unpack())
    w.PropVMScale = w.PropVMScale or 1
    local f = DU.Window("First person · " .. w:GetClass())
    editor = f
    local R = 30
    f:AddTab("Prop", function(pg)
        pg:Heading("Grenade from the viewmodel's grenade bone")
        rows3(pg, w, POS, VEC, 0.1, R, function() return w.PropVMPos end)
        rows3(pg, w, TURN, ANG, 1, 180, function() return w.PropVMAng end)
        num(pg, w, "Size", 0.05, 0.1, 3, function() return w.PropVMScale end, function(v) w.PropVMScale = v end)
    end)
    copyTab(f, w, function()
        return string.format("SWEP.PropVMScale = %g\nSWEP.PropVMPos = Vector(%g, %g, %g)\nSWEP.PropVMAng = Angle(%g, %g, %g)",
            w.PropVMScale, w.PropVMPos.x, w.PropVMPos.y, w.PropVMPos.z, w.PropVMAng.p, w.PropVMAng.y, w.PropVMAng.r)
    end)
    f:Show("Prop")
end

-- Build tools (rhylib_logistics E-tool / repair tool): the tool model on
-- the hand bone (VMOffset / VMAngle / VMScale in first person, WMOffset /
-- WMAngle / WMScale in third person, with the orbit camera).
local function isBuildTool(w)
    return IsValid(w) and w.ToolModel ~= nil and w.VMOffset ~= nil and w.WMOffset ~= nil and not w.IsRhylib
end
local function toolEditor(w, key, title, DU, camera)
    local P, A, Sc = key .. "Offset", key .. "Angle", key .. "Scale"
    w[P] = Vector(w[P]:Unpack())
    w[A] = Angle(w[A]:Unpack())
    w[Sc] = w[Sc] or 1
    local f = DU.Window(title .. " · " .. w:GetClass(), { camera = camera })
    local R = 30
    f:AddTab("Tool", function(pg)
        pg:Heading("Tool from the right hand")
        rows3(pg, w, POS, VEC, 0.1, R, function() return w[P] end)
        rows3(pg, w, TURN, ANG, 1, 180, function() return w[A] end)
        num(pg, w, "Size", 0.05, 0.1, 3, function() return w[Sc] end, function(v) w[Sc] = v end)
    end)
    copyTab(f, w, function()
        return string.format("SWEP.%s = %g\nSWEP.%s = Vector(%g, %g, %g)\nSWEP.%s = Angle(%g, %g, %g)",
            Sc, w[Sc], P, w[P].x, w[P].y, w[P].z, A, w[A].p, w[A].y, w[A].r)
    end)
    f:Show("Tool")
    return f
end

concommand.Add("rhylib_vm_editor", function()
    if IsValid(editor) then editor:Remove() return end
    local DU = kitUI()
    if not DU then return end
    local g = LocalPlayer():GetActiveWeapon()
    if isBuildTool(g) then
        editor = toolEditor(g, "VM", "First person", DU)
        return
    end
    if IsValid(g) and not g.IsRhylib and g.PropModel and g.PropVMPos and g.PropVMAng then
        grenadeEditor(g, DU)
        return
    end
    local w = held()
    if not w then return end
    local carrier = w:UsesCarrier()
    local posKey, angKey = carrier and "PropBonePos" or "PropVMPos", carrier and "PropBoneAng" or "PropVMAng"
    -- Own copies, so the edits don't change the shared weapon table.
    w[posKey] = Vector(w[posKey]:Unpack())
    local hadAng = w.PropBoneAng ~= nil and w.PropBoneAng ~= false
    if carrier and not hadAng then w.rhylibRealign = true end
    w[angKey] = Angle((w[angKey] or Angle(0, 0, 0)):Unpack())
    w.AimPos = Vector(w.AimPos:Unpack())
    if carrier and w.VMOffset == nil then w.rhylibRematch = true end
    w.VMOffset = Vector((w.VMOffset or Vector(0, 0, 0)):Unpack())
    -- Opened while lowered (safety or sprint): edit the safety pose.
    local safe
    if carrier and hadAng and w:IsLowered() then
        local sp = w.SafePose or {}
        safe = {
            PropBonePos = Vector((sp.PropBonePos or w.PropBonePos):Unpack()),
            PropBoneAng = Angle((sp.PropBoneAng or w.PropBoneAng):Unpack()),
            PropBoneScale = sp.PropBoneScale or w.PropBoneScale or w.PropScale,
            VMOffset = Vector((sp.VMOffset or w.VMOffset):Unpack()),
            CarrierFOV = sp.CarrierFOV or w.CarrierFOV,
        }
        w.SafePose = safe
    end
    local t = safe or w
    -- A fire mode drawn on another viewmodel (ModeProxies): edit that one.
    local px
    if carrier and not safe and w.ActiveProxy and w:ActiveProxy() then
        w.ModeProxies = table.Copy(w.ModeProxies)
        px = w:ActiveProxy()
        px.PropBonePos = Vector((px.PropBonePos or Vector()):Unpack())
        px.PropBoneAng = Angle((px.PropBoneAng or Angle()):Unpack())
        px.PropBoneScale = px.PropBoneScale or w.PropScale
        px.VMOffset = Vector((px.VMOffset or Vector()):Unpack())
        t = px
    end
    local dual = w.DualMirror and carrier and not safe
    if dual then
        w.DualMirrorPos = Vector((w.DualMirrorPos or Vector()):Unpack())
        w.DualMirrorAng = Angle((w.DualMirrorAng or Angle()):Unpack())
    end

    local f = DU.Window("Viewmodel · " .. w:GetClass())
    editor = f
    onClose(f, function() if IsValid(w) then w.rhylibAimPreview = nil end end)
    local editing = px and ("the " .. w:GetFireModeName() .. " hands (SWEP.ModeProxies)") or safe and "the safety pose (opened while lowered)"
        or carrier and "the gun in the hands" or "the floating gun"

    local R = 30
    f:AddTab("Gun", function(pg)
        pg:Heading(carrier and "Gun on the hands' gun bone" or "Floating gun from the view")
        pg:Note("Editing " .. editing .. ".")
        rows3(pg, w, POS, VEC, 0.1, R, function() return t[posKey] end)
        rows3(pg, w, TURN, ANG, 1, 180, function() return t[angKey] end)
        if carrier then
            num(pg, w, "Size", 0.05, 0.1, 3, function() return t.PropBoneScale or w.PropScale end, function(v) t.PropBoneScale = v end)
        end
    end)
    if carrier then
        f:AddTab("Hands", function(pg)
            pg:Heading("Hands and gun on screen")
            rows3(pg, w, { "Right", "Forward", "Up" }, VEC, 0.1, R, function() return t.VMOffset end)
            if not safe and not px then
                pg:Space(6)
                pg:Buttons({
                    { "Point the gun straight ahead", function() if IsValid(w) then w.rhylibRealign = true end end },
                    -- (worked out again on the next idle frame)
                    { "Move to the old floating gun position", function() if IsValid(w) then w.rhylibRematch = true end end },
                })
            end
        end)
    end
    if dual then
        f:AddTab("Dual pistols", function(pg)
            pg:Heading("Dual pistols")
            pg:Note("Switch to dual to see them.")
            num(pg, w, "Spread", 0.1, -R, R, function() return w.DualSpread or 0 end, function(v) w.DualSpread = v end)
            pg:Heading("Left pistol")
            rows3(pg, w, POS, VEC, 0.1, R, function() return w.DualMirrorPos end)
            rows3(pg, w, TURN, ANG, 1, 180, function() return w.DualMirrorAng end)
        end)
    end
    f:AddTab("Aim & FOV", function(pg)
        pg:Heading("Aiming")
        pg:Toggle("Preview aim", function() return IsValid(w) and w.rhylibAimPreview and true or false end,
            function(on) if IsValid(w) then w.rhylibAimPreview = on or nil end end)
        rows3(pg, w, { "Right", "Forward", "Up" }, VEC, 0.1, R, function() return w.AimPos end)
        pg:Heading("Viewmodel")
        num(pg, w, "FOV", 1, 30, 110, function() return safe and safe.CarrierFOV or w.ViewModelFOV end, function(v)
            if safe then safe.CarrierFOV = v return end
            w.ViewModelFOV = v
            if carrier then w.CarrierFOV = v end
        end)
    end)
    copyTab(f, w, function() return editorLines(w, safe, px) end)
    f:Show("Gun")
end)

-- Orbit camera for the third-person editors: the view circles your right
-- hand while the editor is open (the camera column of the window: presets,
-- drag to turn, wheel to zoom). Yaw is from your body's facing: 0 = in
-- front of you.
local orbit = { on = false, yaw = 30, pitch = 10, dist = 45, pan = Vector() }

local function orbitCentre(ply)
    -- (orbit.ent: circle another model instead, e.g. the pose editor's stand-in)
    if IsValid(orbit.ent) then ply = orbit.ent end
    ply:SetupBones()
    local b = ply:LookupBone(orbit.bone or "ValveBiped.Bip01_R_Hand")
    local m = b and ply:GetBoneMatrix(b)
    return m and m:GetTranslation() or (ply:GetPos() + Vector(0, 0, 45))
end

Rhylib.Hook.Add("CalcView", "weapons.editorcam", function(ply, pos, angles, fov)
    if not orbit.on then return end
    if not IsValid(orbit.frame) or ply ~= LocalPlayer() or not ply:Alive() then
        orbit.on = false
        return
    end
    -- (yaw from your facing when the camera came on, so turning doesn't
    -- swing it; pan = right-drag offset of the centre)
    orbit.baseYaw = orbit.baseYaw or ply:GetRenderAngles().y
    local centre = orbitCentre(ply) + orbit.pan
    local dir = Angle(orbit.pitch, orbit.baseYaw + orbit.yaw, 0):Forward()
    local origin = centre + dir * orbit.dist
    orbit.viewAng = (centre - origin):Angle()
    orbit.viewPos = origin
    return { origin = origin, angles = orbit.viewAng, fov = 60, znear = 1, drawviewer = true }
end, -60)   -- (before the body camera and third person)

-- (no gun sway or first-person bits while orbiting)
Rhylib.Hook.Add("ShouldDrawLocalPlayer", "weapons.editorcam", function()
    if orbit.on and IsValid(orbit.frame) then return true end
end, -60)

-- rhylib_wm_editor: the third-person gun (PropWMPos / PropWMAng /
-- PropScale, from the right hand). Only your own view changes; the
-- orbit camera shows it from any side.
local wmEditor
local HAND_CAM = { head = "Camera (circles your right hand)" }
concommand.Add("rhylib_wm_editor", function()
    if IsValid(wmEditor) then wmEditor:Remove() return end
    local DU = kitUI()
    if not DU then return end
    -- Any weapon with a third-person prop (guns, grenades), or a build tool.
    local w = LocalPlayer():GetActiveWeapon()
    if isBuildTool(w) then
        wmEditor = toolEditor(w, "WM", "Third person", DU, HAND_CAM)
        return
    end
    if not IsValid(w) or not w.PropModel or not w.PropWMPos then print("Hold a Rhy's weapon or grenade first") return end
    w.PropScale = w.PropScale or 1
    w.PropWMPos = Vector(w.PropWMPos:Unpack())
    w.PropWMAng = Angle(w.PropWMAng:Unpack())
    -- Dual pistols: the second one, from the left hand (switch to dual first to see it).
    local dual = w.DualPropWMPos ~= nil
    if dual then
        w.DualPropWMPos = Vector(w.DualPropWMPos:Unpack())
        w.DualPropWMAng = Angle((w.DualPropWMAng or Angle()):Unpack())
    end
    local f = DU.Window("Third person · " .. w:GetClass(), { camera = HAND_CAM })
    wmEditor = f
    local R = 30
    f:AddTab("Gun", function(pg)
        pg:Heading("Gun from the right hand")
        rows3(pg, w, POS, VEC, 0.1, R, function() return w.PropWMPos end)
        rows3(pg, w, TURN, ANG, 1, 180, function() return w.PropWMAng end)
        num(pg, w, "Size", 0.05, 0.1, 3, function() return w.PropScale end, function(v) w.PropScale = v end)
    end)
    if dual then
        f:AddTab("Left pistol", function(pg)
            pg:Heading("Left pistol from the left hand")
            pg:Note("Dual mode: switch to dual first to see it.")
            rows3(pg, w, POS, VEC, 0.1, R, function() return w.DualPropWMPos end)
            rows3(pg, w, TURN, ANG, 1, 180, function() return w.DualPropWMAng end)
        end)
    end
    copyTab(f, w, function()
        local t = string.format("SWEP.PropScale = %g\nSWEP.PropWMPos = Vector(%g, %g, %g)\nSWEP.PropWMAng = Angle(%g, %g, %g)",
            w.PropScale, w.PropWMPos.x, w.PropWMPos.y, w.PropWMPos.z, w.PropWMAng.p, w.PropWMAng.y, w.PropWMAng.r)
        if dual then
            t = t .. string.format("\nSWEP.DualPropWMPos = Vector(%g, %g, %g)\nSWEP.DualPropWMAng = Angle(%g, %g, %g)",
                w.DualPropWMPos.x, w.DualPropWMPos.y, w.DualPropWMPos.z, w.DualPropWMAng.p, w.DualPropWMAng.y, w.DualPropWMAng.r)
        end
        return t
    end)
    f:Show("Gun")
end)

-- rhylib_extra_editor: extra props (a riot shield) in first and third
-- person, the carrier's arm moves and the holder's arm turns. Edits only
-- your copy of the weapon; Copy gives the lines for the weapon file.
local extraEditor
local function fmtV(v) return string.format("Vector(%g, %g, %g)", v.x, v.y, v.z) end
local function fmtA(a) return string.format("Angle(%g, %g, %g)", a.p, a.y, a.r) end
concommand.Add("rhylib_extra_editor", function()
    if IsValid(extraEditor) then extraEditor:Remove() return end
    local DU = kitUI()
    if not DU then return end
    local w = LocalPlayer():GetActiveWeapon()
    if not IsValid(w) or not (w.ExtraProps or w.CarrierBoneMods or w.WorldBoneMods) then
        print("Hold a weapon with extra props (the riot shield) first")
        return
    end
    -- Own copies, so the edits don't change the shared weapon table.
    w.ExtraProps = table.Copy(w.ExtraProps or {})
    w.CarrierBoneMods = w.CarrierBoneMods and table.Copy(w.CarrierBoneMods) or nil
    w.WorldBoneMods = w.WorldBoneMods and table.Copy(w.WorldBoneMods) or nil
    local anyAim = false
    for _, e in ipairs(w.ExtraProps) do
        e.vmPos = Vector((e.vmPos or Vector()):Unpack())
        e.vmAng = Angle((e.vmAng or Angle()):Unpack())
        e.wmPos = Vector((e.wmPos or Vector()):Unpack())
        e.wmAng = Angle((e.wmAng or Angle()):Unpack())
        if e.vmPosAim or e.vmAngAim then
            e.vmPosAim = Vector((e.vmPosAim or e.vmPos):Unpack())
            e.vmAngAim = Angle((e.vmAngAim or e.vmAng):Unpack())
            anyAim = true
        end
    end
    for _, m in pairs(w.CarrierBoneMods or {}) do
        m.pos = Vector((m.pos or Vector()):Unpack())
        m.ang = Angle((m.ang or Angle()):Unpack())
    end
    local mods = w.WorldBoneMods
    for name in pairs(mods or {}) do mods[name] = Angle(mods[name]:Unpack()) end

    -- (the camera starts off: this editor does first person too)
    local f = DU.Window("Extras · " .. w:GetClass(), { camera = { head = "Camera (circles your right hand)", off = true } })
    extraEditor = f
    if anyAim then onClose(f, function() if IsValid(w) then w.rhylibAimPreview = nil end end) end
    local R, B = 60, 120
    local first, third = #w.ExtraProps > 0 or w.CarrierBoneMods ~= nil, #w.ExtraProps > 0 or mods ~= nil
    if first then
        f:AddTab("First person", function(pg)
            for _, e in ipairs(w.ExtraProps) do
                pg:Heading(e.key)
                pg:Note("First person, on " .. tostring(e.vmBone))
                rows3(pg, w, POS, VEC, 0.1, B, function() return e.vmPos end)
                rows3(pg, w, TURN, ANG, 1, 180, function() return e.vmAng end)
                num(pg, w, "Size", 0.02, 0.05, 4, function() return e.vmScale or 1 end, function(v) e.vmScale = v end)
                if e.vmPosAim then
                    pg:Heading(e.key .. " while aiming")
                    pg:Toggle("Preview aim (shows the aiming pose)", function() return IsValid(w) and w.rhylibAimPreview and true or false end,
                        function(on) if IsValid(w) then w.rhylibAimPreview = on or nil end end)
                    rows3(pg, w, POS, VEC, 0.1, B, function() return e.vmPosAim end)
                    rows3(pg, w, TURN, ANG, 1, 180, function() return e.vmAngAim end)
                end
            end
            for name, m in SortedPairs(w.CarrierBoneMods or {}) do
                pg:Heading("Arm move")
                pg:Note(name)
                rows3(pg, w, { "X", "Y", "Z" }, VEC, 0.1, R, function() return m.pos end)
                rows3(pg, w, TURN, ANG, 1, 180, function() return m.ang end)
            end
        end)
    end
    if third then
        f:AddTab("Third person", function(pg)
            for _, e in ipairs(w.ExtraProps) do
                pg:Heading(e.key)
                pg:Note("Third person, on " .. tostring(e.wmBone))
                rows3(pg, w, POS, VEC, 0.1, B, function() return e.wmPos end)
                rows3(pg, w, TURN, ANG, 1, 180, function() return e.wmAng end)
                num(pg, w, "Size", 0.02, 0.05, 4, function() return e.wmScale or 1 end, function(v) e.wmScale = v end)
            end
            for name in SortedPairs(mods or {}) do
                pg:Heading("Arm turn")
                pg:Note(name)
                rows3(pg, w, TURN, ANG, 1, 180, function() return mods[name] end)
            end
        end)
    end
    copyTab(f, w, function()
        local out = {}
        for _, e in ipairs(w.ExtraProps) do
            out[#out + 1] = string.format('%s = { vmPos = %s, vmAng = %s, vmScale = %g, wmPos = %s, wmAng = %s, wmScale = %g },',
                e.key, fmtV(e.vmPos), fmtA(e.vmAng), e.vmScale or 1, fmtV(e.wmPos), fmtA(e.wmAng), e.wmScale or 1)
            if e.vmPosAim then
                out[#out + 1] = string.format('    (aiming) vmPosAim = %s, vmAngAim = %s,', fmtV(e.vmPosAim), fmtA(e.vmAngAim))
            end
        end
        if w.CarrierBoneMods then
            out[#out + 1] = "SWEP.CarrierBoneMods = {"
            for name, m in SortedPairs(w.CarrierBoneMods) do
                out[#out + 1] = string.format('    ["%s"] = { pos = %s, ang = %s },', name, fmtV(m.pos), fmtA(m.ang))
            end
            out[#out + 1] = "}"
        end
        if w.WorldBoneMods then
            out[#out + 1] = "SWEP.WorldBoneMods = {"
            for name, a in SortedPairs(w.WorldBoneMods) do
                out[#out + 1] = string.format('    ["%s"] = %s,', name, fmtA(a))
            end
            out[#out + 1] = "}"
        end
        return table.concat(out, "\n")
    end)
    -- (the third-person tab brings the orbit camera on, first person off)
    f.onShow = function(name)
        if name == "Third person" then orbit.on = true elseif name == "First person" then orbit.on = false end
    end
    f:Show(first and "First person" or third and "Third person" or "Copy")
end)


-- rhylib_ear_editor: the hand-to-the-ear IK (rhylib_radio config earIK:
-- where the wrist goes, the hand's turn and where the elbow bends to, all
-- fixed to the head bone). While it's open your own arm is held up
-- (R.earPreview) and the orbit camera circles your head. Every change is
-- saved half a second later as the Server settings value radio earIK
-- (Rhylib.Settings.Set: needs the settings permission; everyone sees it,
-- it stays after closing); Copy gives the Lua line for the default.
local earEditor
concommand.Add("rhylib_ear_editor", function()
    if IsValid(earEditor) then earEditor:Remove() return end
    local R = Rhylib.Radio
    if not (R and R.EarBones and R.Cfg) then print("Needs Rhy's Radio & Squads") return end
    local DU = kitUI()
    if not DU then return end
    local K = Rhylib.UI.Kit
    -- (your last edits are also kept in data/rhylib_ear_ik.json on your
    -- computer, so a refused or lost save never throws them away)
    local cur = R.Cfg("earIK") or {}
    local localCopy = util.JSONToTable(file.Read("rhylib_ear_ik.json", "DATA") or "")
    if istable(localCopy) then cur = localCopy end
    local DEF = { pos = { -0.5, -2.5, -6 }, ang = { -175, -150, 80 }, elbow = { 13, 18, 15 } }
    local ik = {}
    for key, d in pairs(DEF) do
        local a = istable(cur[key]) and cur[key] or {}
        ik[key] = { tonumber(a[1]) or d[1], tonumber(a[2]) or d[2], tonumber(a[3]) or d[3] }
    end
    ik.fingers = isstring(cur.fingers) and cur.fingers or "run_all_01"
    ik.swivel = tonumber(cur.swivel) or 155
    local function three(t) return istable(t) and { tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0 } or nil end
    ik.shoulder, ik.viaShoulder, ik.viaPos, ik.viaAng = three(cur.shoulder), three(cur.viaShoulder), three(cur.viaPos), three(cur.viaAng)
    R.earIKEdit, R.earPreview = ik, true
    local me = LocalPlayer()
    local f = DU.Window("Hand to the ear (left arm IK)", { camera = { bone = "ValveBiped.Bip01_Head1", head = "Camera (circles your head)" } })
    earEditor = f
    local function save()
        timer.Remove("Rhylib.EarEditorSave")
        local function c3(t) return t and { t[1], t[2], t[3] } or nil end
        local out = { fingers = ik.fingers, swivel = ik.swivel, shoulder = c3(ik.shoulder), viaShoulder = c3(ik.viaShoulder), viaPos = c3(ik.viaPos), viaAng = c3(ik.viaAng) }
        for key, a in pairs(ik) do if istable(a) then out[key] = { a[1], a[2], a[3] } end end
        file.Write("rhylib_ear_ik.json", util.TableToJSON(out) or "")
        local S = Rhylib.Settings
        if S and S.Set then S.Set("radio", "earIK", out) end
    end
    local dirty = false
    local function changed()
        dirty = true
        timer.Create("Rhylib.EarEditorSave", 0.5, 1, function() dirty = false save() end)
    end
    onClose(f, function()
        if dirty then save() end
        R.earPreview, R.earViaPreview = nil, nil
        -- (your own view keeps the edited values until the saved ones come back)
        timer.Simple(2, function() if not R.earPreview then R.earIKEdit = nil end end)
    end)

    -- Load a whole set of values (Reset to default, a snapshot) into the
    -- editor: the same tables stay in use (the rows show them by themselves).
    local function loadInto(src)
        src = istable(src) and src or {}
        for key, d in pairs(DEF) do
            local t = istable(src[key]) and src[key] or d
            ik[key][1], ik[key][2], ik[key][3] = tonumber(t[1]) or d[1], tonumber(t[2]) or d[2], tonumber(t[3]) or d[3]
        end
        ik.fingers = isstring(src.fingers) and src.fingers or ""
        ik.swivel = tonumber(src.swivel) or 0
        ik.shoulder, ik.viaShoulder, ik.viaPos, ik.viaAng = three(src.shoulder), three(src.viaShoulder), three(src.viaPos), three(src.viaAng)
        changed()
    end
    -- (the rows refresh themselves; kept for the gizmo below)
    local function refreshAll() end
    local function copyOut()
        local function c3(t) return t and { t[1], t[2], t[3] } or nil end
        local out = { fingers = ik.fingers, swivel = ik.swivel, shoulder = c3(ik.shoulder), viaShoulder = c3(ik.viaShoulder), viaPos = c3(ik.viaPos), viaAng = c3(ik.viaAng) }
        for key in pairs(DEF) do out[key] = c3(ik[key]) end
        return out
    end
    local function lockNow()
        local la = R.earUpperLocal or Angle()
        ik.shoulder = { math.Round(la.p), math.Round(la.y), math.Round(la.r) }
    end
    -- Transition point from the arm as it is now; also done by itself on
    -- the first edit of a Via row, and the shoulder gets locked if it wasn't.
    local function setVia()
        if not ik.shoulder then lockNow() end
        local la, wl = R.earUpperLocal or Angle(), R.earWristLocal or Vector()
        ik.viaShoulder = { math.Round(la.p), math.Round(la.y), math.Round(la.r) }
        ik.viaPos = { math.Round(wl.x, 1), math.Round(wl.y, 1), math.Round(wl.z, 1) }
        local d = R.earDbg
        if d then
            local _, ha = WorldToLocal(vector_origin, d.hand, d.cp, d.ca)
            ik.viaAng = { math.Round(ha.p), math.Round(ha.y), math.Round(ha.r) }
        else
            ik.viaAng = ik.viaAng or { 0, 0, 0 }
        end
    end
    local function viaEdit(key, i, v)
        if not ik.viaShoulder then setVia() end
        ik[key][i] = v
        changed()
    end

    local ROWS = {
        { "pos", "Wrist position", "From the head.", { "X", "Y", "Z" }, 0.5, 30 },
        { "ang", "Hand turn", "From the head.", { "Pitch", "Yaw", "Roll" }, 5, 180 },
        { "elbow", "Elbow bends toward", "From the head.", { "X", "Y", "Z" }, 1, 60 },
    }
    f:AddTab("Hand", function(pg)
        for _, row in ipairs(ROWS) do
            pg:Heading(row[2])
            pg:Note(row[3])
            for i, ax in ipairs(row[4]) do
                local key = row[1]
                num(pg, me, ax, row[5], -row[6], row[6], function() return ik[key][i] end, function(v) ik[key][i] = v changed() end)
            end
        end
        -- Elbow swivel: turns the elbow round the shoulder-to-wrist line.
        pg:Heading("Elbow swivel")
        pg:Note("Turns the elbow round the arm's line (the hand stays put).")
        num(pg, me, "Degrees", 5, -180, 180, function() return ik.swivel end, function(v) ik.swivel = v changed() end)
    end)

    -- Shoulder by hand: lock the upper arm where it is now (in the chest's
    -- axes), then turn it with these rows; unlocked, the elbow point and
    -- swivel decide it instead.
    f:AddTab("Shoulder", function(pg)
        pg:Heading("Shoulder")
        pg:Note("The upper arm from the chest. Lock it first; unlocked, the elbow point and swivel decide it.")
        pg:Toggle("Shoulder locked (off: the elbow point decides)", function() return ik.shoulder ~= nil end, function()
            if ik.shoulder then ik.shoulder = nil else lockNow() end
            changed()
        end)
        for i, ax in ipairs(TURN) do
            num(pg, me, "Shoulder " .. ax, 2, -180, 180, function() return ik.shoulder and ik.shoulder[i] or 0 end,
                function(v) if ik.shoulder then ik.shoulder[i] = v changed() end end)
        end
    end)

    -- Transition point: where the arm goes first on its way to the ear
    -- (and back), so it doesn't cut through the body. "Show it" holds your
    -- arm there; setting it takes the arm as it is now (from the chest),
    -- then the rows move it. Needs the shoulder locked.
    f:AddTab("Transition", function(pg)
        pg:Heading("Transition point")
        pg:Note("The arm passes here first on its way to the ear and back. Needs the shoulder locked (setting it locks it).")
        pg:Toggle("Show the transition point (holds your arm there)", function() return R.earViaPreview and true or false end,
            function() R.earViaPreview = not R.earViaPreview end)
        pg:Toggle("Transition point set (on: from the arm now)", function() return ik.viaShoulder ~= nil end, function()
            if ik.viaShoulder then
                ik.viaShoulder, ik.viaPos, ik.viaAng = nil, nil, nil
            else
                setVia()
            end
            changed()
        end)
        pg:Heading("Via shoulder")
        for i, ax in ipairs(TURN) do
            num(pg, me, ax, 2, -180, 180, function()
                    if ik.viaShoulder then return ik.viaShoulder[i] end
                    local la = R.earUpperLocal or Angle()
                    return math.Round(({ la.p, la.y, la.r })[i])
                end,
                function(v) viaEdit("viaShoulder", i, v) end)
        end
        pg:Heading("Via hand")
        for i, ax in ipairs(TURN) do
            num(pg, me, ax, 5, -180, 180, function() return ik.viaAng and ik.viaAng[i] or 0 end,
                function(v)
                    if not ik.viaShoulder then setVia() end
                    ik.viaAng = ik.viaAng or { 0, 0, 0 }
                    ik.viaAng[i] = v
                    changed()
                end)
        end
        pg:Heading("Via wrist")
        pg:Note("Chest axes.")
        for i, ax in ipairs({ "X", "Y", "Z" }) do
            num(pg, me, ax, 0.5, -40, 40, function()
                    if ik.viaPos then return ik.viaPos[i] end
                    local wl = R.earWristLocal or Vector()
                    return math.Round(({ wl.x, wl.y, wl.z })[i], 1)
                end,
                function(v) viaEdit("viaPos", i, v) end)
        end
    end)

    -- Finger pose: any sequence of your model (the fingers as they are in
    -- it), picked from the list or stepped with < >.
    local seqs = { "" }
    for _, name in pairs(me:GetSequenceList() or {}) do seqs[#seqs + 1] = name end
    table.sort(seqs)
    local seqOpts = {}
    for i, n in ipairs(seqs) do seqOpts[i] = { n, n == "" and "(reference pose)" or n } end
    local function pick(i)
        i = (i - 1) % #seqs + 1
        ik.fingers = seqs[i]
        changed()
    end
    local function index()
        for i, n in ipairs(seqs) do if n == ik.fingers then return i end end
        return 1
    end
    f:AddTab("Fingers", function(pg)
        pg:Heading("Finger pose")
        pg:Note("The left hand's fingers as they are in one of your model's animations.")
        pg:Choice("Animation", seqOpts, function() return ik.fingers end, function(v) ik.fingers = v changed() end)
        pg:Buttons({ { "<  Previous", function() pick(index() - 1) end }, { "Next  >", function() pick(index() + 1) end } }, { wrap = true })
    end)

    -- Transform mode (in the 3D view, outside the window): the arm's bones
    -- and its handles are drawn over the model; click a dot to pick it,
    -- then drag the gizmo: Move = three arrows (drag one to slide along it,
    -- the middle square to slide in the view's plane), Rotate = three rings.
    -- W / E switch the tool, Q switches local / world axes (with the window
    -- focused), or use the buttons. Handles: Hand (move = wrist point,
    -- rotate = hand turn, head axes), Shoulder (rotate; with "Show the
    -- transition point" on it turns the transition shoulder), Transition
    -- (move; only while the transition point shows).
    local G = { mode = "move", space = "local", sel = nil, drag = nil }
    f:AddTab("Transform", function(pg)
        pg:Heading("Transform")
        pg:Note("Click a dot on the model (in the 3D view, not the window), then drag the gizmo. Click empty space to deselect.")
        pg:Buttons({
            { "Move (W)", function() G.mode = "move" end, { selected = function() return G.mode == "move" end } },
            { "Rotate (E)", function() G.mode = "rotate" end, { selected = function() return G.mode == "rotate" end } },
            { function() return G.space == "local" and "Axes: local (Q)" or "Axes: world (Q)" end, function() G.space = G.space == "local" and "world" or "local" end },
        })
        pg:Note("Hand: move = the wrist point, rotate = the hand's turn. Shoulder: rotate (locks the shoulder). With the transition point shown: Hand (transition) and the transition shoulder.")
    end)
    f.onKey = function(k)
        if k == KEY_W then G.mode = "move" elseif k == KEY_E then G.mode = "rotate" elseif k == KEY_Q then G.space = G.space == "local" and "world" or "local" end
    end

    -- Reset to default (the shipped earIK) and snapshots (kept in
    -- data/rhylib_ear_ik_snapshots.json on your computer).
    local SNAP = "rhylib_ear_ik_snapshots.json"
    local function snaps()
        local t = util.JSONToTable(file.Read(SNAP, "DATA") or "")
        return istable(t) and t or {}
    end
    local snapList, snapPick = snaps(), nil
    local function reloadSnaps()
        snapList = snaps()
        if snapPick and not snapList[snapPick] then snapPick = nil end
    end
    f:AddTab("Snapshots", function(pg)
        pg:Heading("Default")
        pg:Buttons({ { "Reset to default", function()
            K.Confirm("Reset to default", "Put every value back to the shipped default?", "Reset", function()
                local def = Rhylib.Config.defs and Rhylib.Config.defs.radio and Rhylib.Config.defs.radio.earIK
                loadInto(def and def.default)
            end, { danger = true })
        end, { danger = true } } })
        pg:Heading("Snapshots")
        pg:Note("Kept in data/rhylib_ear_ik_snapshots.json on your computer.")
        pg:Buttons({ { "Save snapshot", function()
            K.Prompt("Save snapshot", "Name for this snapshot", os.date("%H:%M:%S"), function(name)
                local list = snaps()
                list[#list + 1] = { name = string.sub(name ~= "" and name or os.date("%H:%M:%S"), 1, 40), ik = copyOut() }
                file.Write(SNAP, util.TableToJSON(list) or "[]")
                reloadSnaps()
            end)
        end, { accent = true } } })
        pg:List({ { "Snapshot", 1 } }, function()
            local out = {}
            for i, sn in ipairs(snapList) do out[i] = { i, { sn.name or ("Snapshot " .. i) } } end
            return out
        end, function() return snapPick end, function(i) snapPick = i end, K.S(180))
        pg:Buttons({
            { "Load", function()
                local sn = snapPick and snaps()[snapPick]
                if sn then loadInto(sn.ik) end
            end, { enabled = function() return snapPick ~= nil end } },
            { "Delete", function()
                if not snapPick then return end
                local list = snaps()
                table.remove(list, snapPick)
                file.Write(SNAP, util.TableToJSON(list) or "[]")
                snapPick = nil
                reloadSnaps()
            end, { danger = true, enabled = function() return snapPick ~= nil end } },
        }, { wrap = true })
    end)

    copyTab(f, me, function()
        local parts = {}
        for _, row2 in ipairs(ROWS) do
            local a = ik[row2[1]]
            parts[#parts + 1] = string.format("%s = { %g, %g, %g }", row2[1], a[1], a[2], a[3])
        end
        parts[#parts + 1] = string.format("swivel = %g", ik.swivel)
        if ik.shoulder then parts[#parts + 1] = string.format("shoulder = { %g, %g, %g }", ik.shoulder[1], ik.shoulder[2], ik.shoulder[3]) end
        if ik.viaShoulder then parts[#parts + 1] = string.format("viaShoulder = { %g, %g, %g }", ik.viaShoulder[1], ik.viaShoulder[2], ik.viaShoulder[3]) end
        if ik.viaPos then parts[#parts + 1] = string.format("viaPos = { %g, %g, %g }", ik.viaPos[1], ik.viaPos[2], ik.viaPos[3]) end
        if ik.viaAng then parts[#parts + 1] = string.format("viaAng = { %g, %g, %g }", ik.viaAng[1], ik.viaAng[2], ik.viaAng[3]) end
        parts[#parts + 1] = string.format("fingers = %q", ik.fingers)
        return "Rhylib.Config.Set(\"radio\", \"earIK\", { " .. table.concat(parts, ", ") .. " })"
    end, "The Lua line for the default", "Copy the line")

    local AXCOL = { Color(235, 70, 70), Color(80, 220, 90), Color(80, 140, 255) }
    local function handles()
        local d = R.earDbg
        if not d then return {} end
        local out = { { id = "shoulder", name = R.earViaPreview and "Shoulder (transition)" or "Shoulder", pos = d.S, rotAng = d.upper } }
        if not R.earViaPreview then
            out[#out + 1] = { id = "hand", name = "Hand", pos = d.target, moveAng = d.ha, rotAng = d.hand }
        elseif ik.viaPos then
            -- (the transition point: move its wrist point, turn its hand)
            out[#out + 1] = { id = "via", name = "Hand (transition)", pos = LocalToWorld(Vector(ik.viaPos[1], ik.viaPos[2], ik.viaPos[3]), angle_zero, d.cp, d.ca), moveAng = d.ca, rotAng = d.hand }
        end
        return out
    end
    local function selected()
        for _, h in ipairs(handles()) do if h.id == G.sel then return h end end
    end
    local function toolOf(h)
        if not h then return nil end
        if G.mode == "move" and h.moveAng then return "move" end
        if h.rotAng then return "rotate" end
        return "move"
    end
    local function axes(h, tool)
        if G.space == "world" then return { Vector(1, 0, 0), Vector(0, 1, 0), Vector(0, 0, 1) } end
        local a = tool == "move" and h.moveAng or h.rotAng
        return { a:Forward(), a:Right(), a:Up() }
    end
    local function scr(v) local t = v:ToScreen() return t.x, t.y end
    local function segDist(px, py, ax, ay, bx, by)
        local vx, vy = bx - ax, by - ay
        local l2 = vx * vx + vy * vy
        local t = l2 > 0 and math.Clamp(((px - ax) * vx + (py - ay) * vy) / l2, 0, 1) or 0
        local cx, cy = ax + vx * t, ay + vy * t
        return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
    end
    local function ringPts(p, axis, r)
        local u = axis:Cross(math.abs(axis.z) < 0.9 and Vector(0, 0, 1) or Vector(1, 0, 0)):GetNormalized()
        local v = axis:Cross(u)
        local pts = {}
        for i = 0, 32 do
            local a = i / 32 * math.pi * 2
            pts[#pts + 1] = p + u * (math.cos(a) * r) + v * (math.sin(a) * r)
        end
        return pts
    end
    local function gizmoLen() return math.max(3, orbit.dist * 0.18) end

    Rhylib.Hook.Add("HUDPaint", "devtools.eargizmo", function()
        if not IsValid(earEditor) or not R.earDbg then return end
        local d = R.earDbg
        -- the bones: shoulder - elbow - wrist, the wrist point, the head
        surface.SetDrawColor(255, 255, 255, 160)
        local sx, sy = scr(d.S)
        local ex, ey = scr(d.E)
        local wx, wy = scr(d.W)
        local tx, ty = scr(d.target)
        surface.DrawLine(sx, sy, ex, ey)
        surface.DrawLine(ex, ey, wx, wy)
        surface.SetDrawColor(255, 255, 255, 70)
        surface.DrawLine(wx, wy, tx, ty)
        for _, h in ipairs(handles()) do
            local x, y = scr(h.pos)
            local on = h.id == G.sel
            draw.RoundedBox(4, x - 6, y - 6, 12, 12, on and Color(255, 210, 60) or Color(230, 235, 240, 220))
            draw.SimpleTextOutlined(h.name, "DermaDefault", x + 9, y - 9, on and Color(255, 210, 60) or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, color_black)
        end
        local h = selected()
        if not h then return end
        local tool = toolOf(h)
        local ax = axes(h, tool)
        local L = gizmoLen()
        local px, py = scr(h.pos)
        for i = 1, 3 do
            local c = AXCOL[i]
            if G.drag and G.drag.axis == i then c = Color(255, 230, 80) end
            surface.SetDrawColor(c)
            if tool == "move" then
                local qx, qy = scr(h.pos + ax[i] * L)
                surface.DrawLine(px, py, qx, qy)
                surface.DrawLine(px + 1, py, qx + 1, qy)
                draw.RoundedBox(2, qx - 3, qy - 3, 6, 6, c)
            else
                local pts = ringPts(h.pos, ax[i], L)
                for k = 1, #pts - 1 do
                    local ax1, ay1 = scr(pts[k])
                    local bx1, by1 = scr(pts[k + 1])
                    surface.DrawLine(ax1, ay1, bx1, by1)
                end
            end
        end
        if tool == "move" then
            surface.SetDrawColor(255, 255, 255, G.drag and G.drag.plane and 255 or 150)
            surface.DrawOutlinedRect(px - 5, py - 5, 10, 10)
        end
    end)

    -- Writing a dragged handle back into the values.
    local function r1(x) return math.Round(x, 1) end
    local function applyMove(h, delta)
        local d = R.earDbg
        if h.id == "hand" then
            local lp = WorldToLocal(d.target + delta, angle_zero, d.hp, d.ha)
            ik.pos[1], ik.pos[2], ik.pos[3] = r1(lp.x), r1(lp.y), r1(lp.z)
        elseif h.id == "via" then
            local lp = WorldToLocal(h.pos + delta, angle_zero, d.cp, d.ca)
            ik.viaPos[1], ik.viaPos[2], ik.viaPos[3] = r1(lp.x), r1(lp.y), r1(lp.z)
        end
    end
    local function applyRotate(h, axis, deg)
        local d = R.earDbg
        local a = Angle(h.rotAng)
        a:RotateAroundAxis(axis, deg)
        if h.id == "hand" then
            local _, la = WorldToLocal(vector_origin, a, d.hp, d.ha)
            ik.ang[1], ik.ang[2], ik.ang[3] = r1(la.p), r1(la.y), r1(la.r)
        elseif h.id == "via" then
            local _, la = WorldToLocal(vector_origin, a, d.cp, d.ca)
            ik.viaAng = ik.viaAng or { 0, 0, 0 }
            ik.viaAng[1], ik.viaAng[2], ik.viaAng[3] = r1(la.p), r1(la.y), r1(la.r)
        elseif h.id == "shoulder" then
            local _, la = WorldToLocal(vector_origin, a, d.cp, d.ca)
            local key = R.earViaPreview and "viaShoulder" or "shoulder"
            if not ik[key] then
                if key == "viaShoulder" then setVia() else ik.shoulder = { 0, 0, 0 } end
            end
            ik[key][1], ik[key][2], ik[key][3] = r1(la.p), r1(la.y), r1(la.r)
        end
    end

    Rhylib.Hook.Add("GUIMousePressed", "devtools.eargizmo", function(code)
        if not IsValid(earEditor) or code ~= MOUSE_LEFT or not R.earDbg then return end
        local mx, my = gui.MouseX(), gui.MouseY()
        local h = selected()
        if h then
            local tool = toolOf(h)
            local ax = axes(h, tool)
            local L = gizmoLen()
            local px, py = scr(h.pos)
            if tool == "move" and math.abs(mx - px) <= 7 and math.abs(my - py) <= 7 then
                G.drag = { plane = true, h = h.id, x = mx, y = my }
                return
            end
            for i = 1, 3 do
                local hit
                if tool == "move" then
                    local qx, qy = scr(h.pos + ax[i] * L)
                    hit = segDist(mx, my, px, py, qx, qy) <= 7
                else
                    local pts = ringPts(h.pos, ax[i], L)
                    for k = 1, #pts - 1 do
                        local ax1, ay1 = scr(pts[k])
                        local bx1, by1 = scr(pts[k + 1])
                        if segDist(mx, my, ax1, ay1, bx1, by1) <= 7 then hit = true break end
                    end
                end
                if hit then
                    G.drag = { axis = i, h = h.id, x = mx, y = my, tool = tool }
                    return
                end
            end
        end
        for _, hh in ipairs(handles()) do
            local x, y = scr(hh.pos)
            if math.abs(mx - x) <= 9 and math.abs(my - y) <= 9 then
                G.sel = hh.id
                return
            end
        end
        G.sel = nil
    end)
    Rhylib.Hook.Add("GUIMouseReleased", "devtools.eargizmo", function(code)
        if code == MOUSE_LEFT then G.drag = nil end
    end)
    Rhylib.Hook.Add("Think", "devtools.eargizmo", function()
        if not IsValid(earEditor) then
            if G.drag then G.drag = nil end
            return
        end
        local dr = G.drag
        if not dr or not R.earDbg then return end
        if not input.IsMouseDown(MOUSE_LEFT) then G.drag = nil return end
        local h = selected()
        if not h or h.id ~= dr.h then G.drag = nil return end
        local mx, my = gui.MouseX(), gui.MouseY()
        local dx, dy = mx - dr.x, my - dr.y
        if dx == 0 and dy == 0 then return end
        local tool = dr.tool or "move"
        if dr.plane then
            local va = orbit.viewAng or EyeAngles()
            local k = orbit.dist * 0.0025
            applyMove(h, va:Right() * (dx * k) - va:Up() * (dy * k))
        elseif tool == "move" then
            local ax = axes(h, "move")[dr.axis]
            local L = gizmoLen()
            local px, py = scr(h.pos)
            local qx, qy = scr(h.pos + ax * L)
            local sx, sy = qx - px, qy - py
            local l2 = sx * sx + sy * sy
            if l2 > 1 then applyMove(h, ax * ((dx * sx + dy * sy) / l2 * L)) end
        else
            local ax = axes(h, "rotate")[dr.axis]
            local px, py = scr(h.pos)
            local a1 = math.atan2(dr.y - py, dr.x - px)
            local a2 = math.atan2(my - py, mx - px)
            local dA = math.deg(a2 - a1)
            dA = (dA + 180) % 360 - 180
            local toCam = (orbit.viewPos or EyePos()) - h.pos
            local facing = ax:Dot(toCam) > 0
            applyRotate(h, ax, facing and -dA or dA)
        end
        dr.x, dr.y = mx, my
        refreshAll()
        changed()
    end)
    f:Show("Hand")
end)

-- (the orbit camera, for the window kit's camera column: cl_15_ui.lua)
Rhylib.Devtools = Rhylib.Devtools or {}
Rhylib.Devtools.orbit = orbit
