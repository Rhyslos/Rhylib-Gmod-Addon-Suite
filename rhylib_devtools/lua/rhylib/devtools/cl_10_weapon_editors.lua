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
    Hooks: CalcView "weapons.editorcam" (-60) and ShouldDrawLocalPlayer
    while an editor frame with the orbit camera is open.
    Uses the weapon base's shared client helpers (Rhylib.Weapons.BaseClient,
    set by rhylib_base): carrierBone. Needs rhylib_weapons; the windows
    are plain Derma (DFrame).
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

-- rhylib_vm_editor: sliders for the held gun (prop in hand or floating,
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

-- Editor window: typed values with - / + buttons (Enter or leaving the
-- box applies). Returns frame (with .list), label(text), field(...), rows.
local function editorFrame(title, tall, w)
    local f = vgui.Create("DFrame")
    f:SetTitle(title)
    f:SetSize(340, tall)
    f:SetPos(20, ScrH() * 0.5 - tall * 0.5)
    f:MakePopup()   -- (keyboard goes to the window, so number keys don't switch weapons)

    local list = vgui.Create("DScrollPanel", f)
    list:Dock(FILL)
    f.list = list
    local rows = {}

    local function label(text)
        local l = list:Add("DLabel")
        l:SetText(text)
        l:Dock(TOP)
        l:DockMargin(4, 10, 4, 2)
    end

    local function field(text, step, lo, hi, get, set)
        local row = list:Add("DPanel")
        row:SetTall(24)
        row:Dock(TOP)
        row:DockMargin(4, 1, 4, 1)
        row:SetPaintBackground(false)
        local l = vgui.Create("DLabel", row)
        l:SetText(text)
        l:SetWide(90)
        l:Dock(LEFT)
        local plus = vgui.Create("DButton", row)
        plus:SetText("+")
        plus:SetWide(26)
        plus:Dock(RIGHT)
        local minus = vgui.Create("DButton", row)
        minus:SetText("-")
        minus:SetWide(26)
        minus:Dock(RIGHT)
        local e = vgui.Create("DTextEntry", row)
        e:Dock(FILL)
        e:DockMargin(0, 0, 4, 0)
        e:SetNumeric(true)
        local function show() e:SetText(tostring(math.Round(get(), 3))) end
        local function apply(v)
            if not IsValid(w) or not v then return end
            set(math.Clamp(v, lo, hi))
            show()
        end
        e.OnEnter = function() apply(tonumber(e:GetValue())) end
        local base = baseclass.Get("DTextEntry")
        e.OnLoseFocus = function(self)
            apply(tonumber(self:GetValue()))
            if base and base.OnLoseFocus then base.OnLoseFocus(self) end
        end
        minus.DoClick = function() apply(get() - step) end
        plus.DoClick = function() apply(get() + step) end
        -- (held down: keeps stepping, after a short wait)
        local function holdRepeat(btn, d)
            function btn:Think()
                if self:IsDown() then
                    local t = RealTime()
                    if not self.rhylibHeld then
                        self.rhylibHeld = t + 0.35
                    elseif t >= self.rhylibHeld then
                        self.rhylibHeld = t + 0.04
                        apply(get() + d)
                    end
                else
                    self.rhylibHeld = nil
                end
            end
        end
        holdRepeat(minus, -step)
        holdRepeat(plus, step)
        show()
        rows[#rows + 1] = show
    end

    local function copyButton(getText)
        local copy = list:Add("DButton")
        copy:SetText("Copy lines for the weapon file")
        copy:SetTall(28)
        copy:Dock(TOP)
        copy:DockMargin(4, 10, 4, 4)
        copy.DoClick = function()
            if not IsValid(w) then return end
            local text = getText()
            SetClipboardText(text)
            print(text)
            chat.AddText(Color(120, 200, 255), "Copied (also printed in the console).")
        end
    end
    f.copyButton = copyButton

    return f, label, field, rows
end

-- Grenades (rhylib_grenade_base, not Rhylib guns): their first-person
-- prop sits on the viewmodel's grenade bone (PropVMPos / PropVMAng /
-- PropVMScale).
local function grenadeEditor(w)
    w.PropVMPos = Vector(w.PropVMPos:Unpack())
    w.PropVMAng = Angle(w.PropVMAng:Unpack())
    w.PropVMScale = w.PropVMScale or 1
    local f, label, field = editorFrame("First person: " .. w:GetClass(), 360, w)
    editor = f
    local R = 30
    label("Grenade from the viewmodel's grenade bone")
    field("Forward", 0.1, -R, R, function() return w.PropVMPos.x end, function(v) w.PropVMPos.x = v end)
    field("Right", 0.1, -R, R, function() return w.PropVMPos.y end, function(v) w.PropVMPos.y = v end)
    field("Up", 0.1, -R, R, function() return w.PropVMPos.z end, function(v) w.PropVMPos.z = v end)
    field("Pitch", 1, -180, 180, function() return w.PropVMAng.p end, function(v) w.PropVMAng.p = v end)
    field("Yaw", 1, -180, 180, function() return w.PropVMAng.y end, function(v) w.PropVMAng.y = v end)
    field("Roll", 1, -180, 180, function() return w.PropVMAng.r end, function(v) w.PropVMAng.r = v end)
    field("Size", 0.05, 0.1, 3, function() return w.PropVMScale end, function(v) w.PropVMScale = v end)
    f.copyButton(function()
        return string.format("SWEP.PropVMScale = %g\nSWEP.PropVMPos = Vector(%g, %g, %g)\nSWEP.PropVMAng = Angle(%g, %g, %g)",
            w.PropVMScale, w.PropVMPos.x, w.PropVMPos.y, w.PropVMPos.z, w.PropVMAng.p, w.PropVMAng.y, w.PropVMAng.r)
    end)
end

-- Build tools (rhylib_logistics E-tool / repair tool): the tool model on
-- the hand bone (VMOffset / VMAngle / VMScale in first person, WMOffset /
-- WMAngle / WMScale in third person).
local function isBuildTool(w)
    return IsValid(w) and w.ToolModel ~= nil and w.VMOffset ~= nil and w.WMOffset ~= nil and not w.IsRhylib
end
local function toolEditor(w, key, title, extra)
    local P, A, S = key .. "Offset", key .. "Angle", key .. "Scale"
    w[P] = Vector(w[P]:Unpack())
    w[A] = Angle(w[A]:Unpack())
    w[S] = w[S] or 1
    local f, label, field = editorFrame(title .. ": " .. w:GetClass(), extra and 520 or 360, w)
    local R = 30
    label("Tool from the right hand")
    field("Forward", 0.1, -R, R, function() return w[P].x end, function(v) w[P].x = v end)
    field("Right", 0.1, -R, R, function() return w[P].y end, function(v) w[P].y = v end)
    field("Up", 0.1, -R, R, function() return w[P].z end, function(v) w[P].z = v end)
    field("Pitch", 1, -180, 180, function() return w[A].p end, function(v) w[A].p = v end)
    field("Yaw", 1, -180, 180, function() return w[A].y end, function(v) w[A].y = v end)
    field("Roll", 1, -180, 180, function() return w[A].r end, function(v) w[A].r = v end)
    field("Size", 0.05, 0.1, 3, function() return w[S] end, function(v) w[S] = v end)
    f.copyButton(function()
        return string.format("SWEP.%s = %g\nSWEP.%s = Vector(%g, %g, %g)\nSWEP.%s = Angle(%g, %g, %g)",
            S, w[S], P, w[P].x, w[P].y, w[P].z, A, w[A].p, w[A].y, w[A].r)
    end)
    return f, label
end

concommand.Add("rhylib_vm_editor", function()
    if IsValid(editor) then editor:Remove() return end
    local g = LocalPlayer():GetActiveWeapon()
    if isBuildTool(g) then
        editor = toolEditor(g, "VM", "First person")
        return
    end
    if IsValid(g) and not g.IsRhylib and g.PropModel and g.PropVMPos and g.PropVMAng then
        grenadeEditor(g)
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

    local f, label, field, rows = editorFrame("Viewmodel: " .. w:GetClass() .. (px and (" (" .. w:GetFireModeName() .. " hands)") or safe and " (safety pose)" or carrier and " (in hands)" or " (floating)"), 640, w)
    editor = f
    local list = f.list
    f.OnRemove = function() if IsValid(w) then w.rhylibAimPreview = nil end end

    local R = 30
    label(carrier and "Gun on the hands' gun bone" or "Floating gun from the view")
    field("Forward", 0.1, -R, R, function() return t[posKey].x end, function(v) t[posKey].x = v end)
    field("Right", 0.1, -R, R, function() return t[posKey].y end, function(v) t[posKey].y = v end)
    field("Up", 0.1, -R, R, function() return t[posKey].z end, function(v) t[posKey].z = v end)
    field("Pitch", 1, -180, 180, function() return t[angKey].p end, function(v) t[angKey].p = v end)
    field("Yaw", 1, -180, 180, function() return t[angKey].y end, function(v) t[angKey].y = v end)
    field("Roll", 1, -180, 180, function() return t[angKey].r end, function(v) t[angKey].r = v end)
    if carrier then
        field("Size", 0.05, 0.1, 3, function() return t.PropBoneScale or w.PropScale end, function(v) t.PropBoneScale = v end)
        label("Hands and gun on screen")
        field("Right", 0.1, -R, R, function() return t.VMOffset.x end, function(v) t.VMOffset.x = v end)
        field("Forward", 0.1, -R, R, function() return t.VMOffset.y end, function(v) t.VMOffset.y = v end)
        field("Up", 0.1, -R, R, function() return t.VMOffset.z end, function(v) t.VMOffset.z = v end)
        if not safe and not px then
        local align = list:Add("DButton")
        align:SetText("Point the gun straight ahead")
        align:SetTall(24)
        align:Dock(TOP)
        align:DockMargin(4, 4, 4, 0)
        align.DoClick = function()
            if not IsValid(w) then return end
            w.rhylibRealign = true
            timer.Simple(0.3, function()
                if not IsValid(w) or not IsValid(f) then return end
                for _, show in ipairs(rows) do show() end
            end)
        end
        local match = list:Add("DButton")
        match:SetText("Move to the old floating gun position")
        match:SetTall(24)
        match:Dock(TOP)
        match:DockMargin(4, 4, 4, 0)
        match.DoClick = function()
            if not IsValid(w) then return end
            w.rhylibRematch = true   -- worked out again on the next idle frame
            timer.Simple(0.3, function()
                if not IsValid(w) or not IsValid(f) then return end
                for _, show in ipairs(rows) do show() end
            end)
        end
        end
    end
    if w.DualMirror and carrier and not safe then
        w.DualMirrorPos = Vector((w.DualMirrorPos or Vector()):Unpack())
        w.DualMirrorAng = Angle((w.DualMirrorAng or Angle()):Unpack())
        label("Dual pistols (switch to dual to see them)")
        field("Spread", 0.1, -R, R, function() return w.DualSpread or 0 end, function(v) w.DualSpread = v end)
        field("L forward", 0.1, -R, R, function() return w.DualMirrorPos.x end, function(v) w.DualMirrorPos.x = v end)
        field("L right", 0.1, -R, R, function() return w.DualMirrorPos.y end, function(v) w.DualMirrorPos.y = v end)
        field("L up", 0.1, -R, R, function() return w.DualMirrorPos.z end, function(v) w.DualMirrorPos.z = v end)
        field("L pitch", 1, -180, 180, function() return w.DualMirrorAng.p end, function(v) w.DualMirrorAng.p = v end)
        field("L yaw", 1, -180, 180, function() return w.DualMirrorAng.y end, function(v) w.DualMirrorAng.y = v end)
        field("L roll", 1, -180, 180, function() return w.DualMirrorAng.r end, function(v) w.DualMirrorAng.r = v end)
    end
    label("Aiming (tick Preview aim to see it)")
    field("Right", 0.1, -R, R, function() return w.AimPos.x end, function(v) w.AimPos.x = v end)
    field("Forward", 0.1, -R, R, function() return w.AimPos.y end, function(v) w.AimPos.y = v end)
    field("Up", 0.1, -R, R, function() return w.AimPos.z end, function(v) w.AimPos.z = v end)
    label("Viewmodel")
    field("FOV", 1, 30, 110, function() return safe and safe.CarrierFOV or w.ViewModelFOV end, function(v)
        if safe then safe.CarrierFOV = v return end
        w.ViewModelFOV = v
        if carrier then w.CarrierFOV = v end
    end)

    local aim = list:Add("DCheckBoxLabel")
    aim:SetText("Preview aim")
    aim:Dock(TOP)
    aim:DockMargin(4, 10, 4, 0)
    aim.OnChange = function(_, on) if IsValid(w) then w.rhylibAimPreview = on or nil end end

    local copy = list:Add("DButton")
    copy:SetText("Copy lines for the weapon file")
    copy:SetTall(28)
    copy:Dock(TOP)
    copy:DockMargin(4, 10, 4, 4)
    copy.DoClick = function()
        if not IsValid(w) then return end
        local text = editorLines(w, safe, px)
        SetClipboardText(text)
        print(text)
        chat.AddText(Color(120, 200, 255), "Copied (also printed in the console).")
    end
end)

-- Orbit camera for the third-person editors: the view circles your right
-- hand while the editor is open (preset buttons, drag to turn, wheel to
-- zoom). Yaw is from your body's facing: 0 = in front of you.
local orbit = { on = false, yaw = 30, pitch = 10, dist = 45, pan = Vector() }

local function orbitCentre(ply)
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

-- bone: what the camera circles (default the right hand). The camera
-- controls go in a column on the right of the editor (the values stay on
-- the left): presets, a drag area (left drag turns: dragging up always
-- moves the camera up, dragging sideways always goes round the same way;
-- right drag pans; wheel zooms), Reset view, zoom, on / off.
local function addOrbit(f, label, startOff, bone)
    orbit.frame = f
    orbit.on = not startOff
    orbit.bone = bone
    orbit.pan = Vector()
    orbit.baseYaw = nil
    f:SetWide(f:GetWide() + 300)
    local col = vgui.Create("DPanel", f)
    col:Dock(RIGHT)
    col:SetWide(296)
    col:DockMargin(4, 0, 0, 0)
    col:SetPaintBackground(false)
    local head = vgui.Create("DLabel", col)
    head:SetText(bone and "Camera (circles your head)" or "Camera (circles your right hand)")
    head:Dock(TOP)
    head:DockMargin(4, 4, 4, 2)
    local row = vgui.Create("DPanel", col)
    row:SetTall(24)
    row:Dock(TOP)
    row:DockMargin(4, 1, 4, 1)
    row:SetPaintBackground(false)
    local presets = { { "Front", 0, 5 }, { "Back", 180, 5 }, { "Left", 90, 5 }, { "Right", -90, 5 }, { "Top", 0, -85 }, { "Below", 0, 60 } }
    for _, p in ipairs(presets) do
        local b = vgui.Create("DButton", row)
        b:SetText(p[1])
        b:SetWide(46)
        b:Dock(LEFT)
        b:DockMargin(0, 0, 2, 0)
        b.DoClick = function()
            orbit.on = true
            orbit.yaw, orbit.pitch = p[2], p[3]
        end
    end
    local bottom = vgui.Create("DPanel", col)
    bottom:Dock(BOTTOM)
    bottom:SetTall(84)
    bottom:SetPaintBackground(false)
    local reset = vgui.Create("DButton", bottom)
    reset:SetText("Reset view (centre, distance, pan)")
    reset:Dock(TOP)
    reset:DockMargin(4, 2, 4, 2)
    reset.DoClick = function()
        orbit.pan = Vector()
        orbit.dist, orbit.yaw, orbit.pitch = 45, 30, 10
        orbit.baseYaw = nil
        orbit.on = true
    end
    local zoom = vgui.Create("DNumSlider", bottom)
    zoom:Dock(TOP)
    zoom:DockMargin(4, 2, 4, 1)
    zoom:SetText("Zoom (distance)")
    zoom:SetMinMax(15, 200)
    zoom:SetDecimals(0)
    zoom:SetValue(orbit.dist)
    function zoom:OnValueChanged(v)
        orbit.dist = math.Clamp(v, 15, 200)
        orbit.on = true
    end
    function zoom:Think()
        if not self:IsEditing() and math.abs(self:GetValue() - orbit.dist) > 0.5 then self:SetValue(orbit.dist) end
    end
    local off = vgui.Create("DCheckBoxLabel", bottom)
    off:SetText("Orbit camera on")
    off:Dock(TOP)
    off:DockMargin(4, 4, 4, 2)
    off:SetValue(orbit.on)
    function off:OnChange(v) orbit.on = v end
    function off:Think()
        if self:GetChecked() ~= orbit.on then self:SetChecked(orbit.on) end
    end
    local pad = vgui.Create("DPanel", col)
    pad:Dock(FILL)
    pad:DockMargin(4, 4, 4, 4)
    pad:SetCursor("sizeall")
    function pad:Paint(w, h)
        surface.SetDrawColor(20, 24, 30, 220)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(80, 100, 130, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("Left drag: turn · right drag: pan · wheel: zoom", "DermaDefault", w * 0.5, h * 0.46, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("yaw %d · pitch %d · %d units", orbit.yaw, orbit.pitch, orbit.dist), "DermaDefault", w * 0.5, h * 0.54,
            Color(170, 180, 190), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    function pad:OnMousePressed(code)
        if code ~= MOUSE_LEFT and code ~= MOUSE_RIGHT then return end
        self.drag = { gui.MouseX(), gui.MouseY() }
        self.pan = code == MOUSE_RIGHT
        self:MouseCapture(true)
    end
    function pad:OnMouseReleased()
        self.drag = nil
        self:MouseCapture(false)
    end
    function pad:Think()
        if not self.drag then return end
        local x, y = gui.MouseX(), gui.MouseY()
        local dx, dy = x - self.drag[1], y - self.drag[2]
        self.drag = { x, y }
        orbit.on = true
        if self.pan then
            -- (the centre slides with the mouse, in the view's plane)
            local view = Angle(orbit.pitch, (orbit.baseYaw or 0) + orbit.yaw, 0)
            local k = orbit.dist * 0.004
            orbit.pan = orbit.pan + view:Right() * (dx * k) - view:Up() * (dy * k)
        else
            -- (drag up: camera up, from any side; the pitch sign is fixed to
            -- the screen, not to the side you're looking from)
            orbit.yaw = math.NormalizeAngle(orbit.yaw - dx * 0.5)
            orbit.pitch = math.Clamp(orbit.pitch + dy * 0.4, -89, 89)
        end
    end
    function pad:OnMouseWheeled(d)
        orbit.dist = math.Clamp(orbit.dist - d * 5, 15, 200)
        orbit.on = true
        return true
    end
end

-- rhylib_wm_editor: the third-person gun (PropWMPos / PropWMAng /
-- PropScale, from the right hand). Only your own view changes; the
-- orbit camera shows it from any side.
local wmEditor
concommand.Add("rhylib_wm_editor", function()
    if IsValid(wmEditor) then wmEditor:Remove() return end
    -- Any weapon with a third-person prop (guns, grenades), or a build tool.
    local w = LocalPlayer():GetActiveWeapon()
    if isBuildTool(w) then
        local f, label = toolEditor(w, "WM", "Third person", true)
        wmEditor = f
        addOrbit(f, label)
        return
    end
    if not IsValid(w) or not w.PropModel or not w.PropWMPos then print("Hold a Rhy's weapon or grenade first") return end
    w.PropScale = w.PropScale or 1
    w.PropWMPos = Vector(w.PropWMPos:Unpack())
    w.PropWMAng = Angle(w.PropWMAng:Unpack())
    local f, label, field = editorFrame("Third person: " .. w:GetClass(), w.DualPropWMPos and 760 or 560, w)
    wmEditor = f
    local R = 30
    label("Gun from the right hand")
    field("Forward", 0.1, -R, R, function() return w.PropWMPos.x end, function(v) w.PropWMPos.x = v end)
    field("Right", 0.1, -R, R, function() return w.PropWMPos.y end, function(v) w.PropWMPos.y = v end)
    field("Up", 0.1, -R, R, function() return w.PropWMPos.z end, function(v) w.PropWMPos.z = v end)
    field("Pitch", 1, -180, 180, function() return w.PropWMAng.p end, function(v) w.PropWMAng.p = v end)
    field("Yaw", 1, -180, 180, function() return w.PropWMAng.y end, function(v) w.PropWMAng.y = v end)
    field("Roll", 1, -180, 180, function() return w.PropWMAng.r end, function(v) w.PropWMAng.r = v end)
    field("Size", 0.05, 0.1, 3, function() return w.PropScale end, function(v) w.PropScale = v end)
    -- Dual pistols: the second one, from the left hand (switch to dual first to see it).
    local dual = w.DualPropWMPos ~= nil
    if dual then
        w.DualPropWMPos = Vector(w.DualPropWMPos:Unpack())
        w.DualPropWMAng = Angle((w.DualPropWMAng or Angle()):Unpack())
        label("Left pistol from the left hand (dual mode)")
        field("L forward", 0.1, -R, R, function() return w.DualPropWMPos.x end, function(v) w.DualPropWMPos.x = v end)
        field("L right", 0.1, -R, R, function() return w.DualPropWMPos.y end, function(v) w.DualPropWMPos.y = v end)
        field("L up", 0.1, -R, R, function() return w.DualPropWMPos.z end, function(v) w.DualPropWMPos.z = v end)
        field("L pitch", 1, -180, 180, function() return w.DualPropWMAng.p end, function(v) w.DualPropWMAng.p = v end)
        field("L yaw", 1, -180, 180, function() return w.DualPropWMAng.y end, function(v) w.DualPropWMAng.y = v end)
        field("L roll", 1, -180, 180, function() return w.DualPropWMAng.r end, function(v) w.DualPropWMAng.r = v end)
    end
    f.copyButton(function()
        local t = string.format("SWEP.PropScale = %g\nSWEP.PropWMPos = Vector(%g, %g, %g)\nSWEP.PropWMAng = Angle(%g, %g, %g)",
            w.PropScale, w.PropWMPos.x, w.PropWMPos.y, w.PropWMPos.z, w.PropWMAng.p, w.PropWMAng.y, w.PropWMAng.r)
        if dual then
            t = t .. string.format("\nSWEP.DualPropWMPos = Vector(%g, %g, %g)\nSWEP.DualPropWMAng = Angle(%g, %g, %g)",
                w.DualPropWMPos.x, w.DualPropWMPos.y, w.DualPropWMPos.z, w.DualPropWMAng.p, w.DualPropWMAng.y, w.DualPropWMAng.r)
        end
        return t
    end)
    addOrbit(f, label)
end)

-- rhylib_extra_editor: extra props (a riot shield) in first and third
-- person, the carrier's arm moves and the holder's arm turns. Edits only
-- your copy of the weapon; Copy gives the lines for the weapon file.
local extraEditor
local function fmtV(v) return string.format("Vector(%g, %g, %g)", v.x, v.y, v.z) end
local function fmtA(a) return string.format("Angle(%g, %g, %g)", a.p, a.y, a.r) end
concommand.Add("rhylib_extra_editor", function()
    if IsValid(extraEditor) then extraEditor:Remove() return end
    local w = LocalPlayer():GetActiveWeapon()
    if not IsValid(w) or not (w.ExtraProps or w.CarrierBoneMods or w.WorldBoneMods) then
        print("Hold a weapon with extra props (the riot shield) first")
        return
    end
    -- Own copies, so the edits don't change the shared weapon table.
    w.ExtraProps = table.Copy(w.ExtraProps or {})
    w.CarrierBoneMods = w.CarrierBoneMods and table.Copy(w.CarrierBoneMods) or nil
    w.WorldBoneMods = w.WorldBoneMods and table.Copy(w.WorldBoneMods) or nil
    local f, label, field = editorFrame("Extras: " .. w:GetClass(), 700, w)
    extraEditor = f
    addOrbit(f, label, true)   -- (off at first: this editor does first person too)
    local R, B = 60, 120
    local function posAng(t, posKey, angKey, what)
        t[posKey] = Vector((t[posKey] or Vector()):Unpack())
        t[angKey] = Angle((t[angKey] or Angle()):Unpack())
        field(what .. " fwd", 0.1, -B, B, function() return t[posKey].x end, function(v) t[posKey].x = v end)
        field(what .. " right", 0.1, -B, B, function() return t[posKey].y end, function(v) t[posKey].y = v end)
        field(what .. " up", 0.1, -B, B, function() return t[posKey].z end, function(v) t[posKey].z = v end)
        field(what .. " pitch", 1, -180, 180, function() return t[angKey].p end, function(v) t[angKey].p = v end)
        field(what .. " yaw", 1, -180, 180, function() return t[angKey].y end, function(v) t[angKey].y = v end)
        field(what .. " roll", 1, -180, 180, function() return t[angKey].r end, function(v) t[angKey].r = v end)
    end
    for _, e in ipairs(w.ExtraProps) do
        label(e.key .. ": first person (on " .. tostring(e.vmBone) .. ")")
        posAng(e, "vmPos", "vmAng", "")
        field(" size", 0.02, 0.05, 4, function() return e.vmScale or 1 end, function(v) e.vmScale = v end)
        if e.vmPosAim or e.vmAngAim then
            e.vmPosAim = e.vmPosAim or Vector(e.vmPos:Unpack())
            e.vmAngAim = e.vmAngAim or Angle(e.vmAng:Unpack())
            label(e.key .. ": first person while aiming")
            local aim = f.list:Add("DCheckBoxLabel")
            aim:SetText("Preview aim (shows the aiming pose)")
            aim:Dock(TOP)
            aim:DockMargin(4, 2, 4, 2)
            aim.OnChange = function(_, on) if IsValid(w) then w.rhylibAimPreview = on or nil end end
            local oldRemove = f.OnRemove
            f.OnRemove = function(...)
                if IsValid(w) then w.rhylibAimPreview = nil end
                if oldRemove then return oldRemove(...) end
            end
            posAng(e, "vmPosAim", "vmAngAim", "aim")
        end
        label(e.key .. ": third person (on " .. tostring(e.wmBone) .. ")")
        posAng(e, "wmPos", "wmAng", "")
        field(" size", 0.02, 0.05, 4, function() return e.wmScale or 1 end, function(v) e.wmScale = v end)
    end
    for name, m in SortedPairs(w.CarrierBoneMods or {}) do
        label("First person arm: " .. name)
        m.pos = Vector((m.pos or Vector()):Unpack())
        m.ang = Angle((m.ang or Angle()):Unpack())
        field(" x", 0.1, -R, R, function() return m.pos.x end, function(v) m.pos.x = v end)
        field(" y", 0.1, -R, R, function() return m.pos.y end, function(v) m.pos.y = v end)
        field(" z", 0.1, -R, R, function() return m.pos.z end, function(v) m.pos.z = v end)
        field(" pitch", 1, -180, 180, function() return m.ang.p end, function(v) m.ang.p = v end)
        field(" yaw", 1, -180, 180, function() return m.ang.y end, function(v) m.ang.y = v end)
        field(" roll", 1, -180, 180, function() return m.ang.r end, function(v) m.ang.r = v end)
    end
    for name in SortedPairs(w.WorldBoneMods or {}) do
        local mods = w.WorldBoneMods
        label("Third person arm: " .. name)
        mods[name] = Angle(mods[name]:Unpack())
        field(" pitch", 1, -180, 180, function() return mods[name].p end, function(v) mods[name].p = v end)
        field(" yaw", 1, -180, 180, function() return mods[name].y end, function(v) mods[name].y = v end)
        field(" roll", 1, -180, 180, function() return mods[name].r end, function(v) mods[name].r = v end)
    end
    f.copyButton(function()
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
    local f, label, field, rows = editorFrame("Hand to the ear (left arm IK)", 900, me)
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
    local oldRemove = f.OnRemove
    function f:OnRemove()
        if dirty then save() end
        R.earPreview, R.earViaPreview = nil, nil
        -- (your own view keeps the edited values until the saved ones come back)
        timer.Simple(2, function() if not R.earPreview then R.earIKEdit = nil end end)
        if oldRemove then oldRemove(self) end
    end

    -- Load a whole set of values (Reset to default, a snapshot) into the
    -- editor: the same tables stay in use, then every row is shown again.
    local refreshAll
    local function loadInto(src)
        src = istable(src) and src or {}
        for key, d in pairs(DEF) do
            local t = istable(src[key]) and src[key] or d
            ik[key][1], ik[key][2], ik[key][3] = tonumber(t[1]) or d[1], tonumber(t[2]) or d[2], tonumber(t[3]) or d[3]
        end
        ik.fingers = isstring(src.fingers) and src.fingers or ""
        ik.swivel = tonumber(src.swivel) or 0
        ik.shoulder, ik.viaShoulder, ik.viaPos, ik.viaAng = three(src.shoulder), three(src.viaShoulder), three(src.viaPos), three(src.viaAng)
        if refreshAll then refreshAll() end
        changed()
    end
    local function copyOut()
        local function c3(t) return t and { t[1], t[2], t[3] } or nil end
        local out = { fingers = ik.fingers, swivel = ik.swivel, shoulder = c3(ik.shoulder), viaShoulder = c3(ik.viaShoulder), viaPos = c3(ik.viaPos), viaAng = c3(ik.viaAng) }
        for key in pairs(DEF) do out[key] = c3(ik[key]) end
        return out
    end

    -- Reset to default (the shipped earIK) and snapshots (kept in
    -- data/rhylib_ear_ik_snapshots.json on your computer).
    label("Default and snapshots")
    local top = f.list:Add("DPanel")
    top:SetTall(24)
    top:Dock(TOP)
    top:DockMargin(4, 1, 4, 1)
    top:SetPaintBackground(false)
    local resetBtn = vgui.Create("DButton", top)
    resetBtn:SetText("Reset to default")
    resetBtn:Dock(LEFT)
    resetBtn:SetWide(110)
    resetBtn.DoClick = function()
        Derma_Query("Put every value back to the shipped default?", "Reset to default", "Reset", function()
            local def = Rhylib.Config.defs and Rhylib.Config.defs.radio and Rhylib.Config.defs.radio.earIK
            loadInto(def and def.default)
        end, "Cancel")
    end
    local SNAP = "rhylib_ear_ik_snapshots.json"
    local function snaps()
        local t = util.JSONToTable(file.Read(SNAP, "DATA") or "")
        return istable(t) and t or {}
    end
    local snapCombo
    local function fillSnaps()
        snapCombo:Clear()
        for i, sn in ipairs(snaps()) do snapCombo:AddChoice(sn.name or ("Snapshot " .. i), i) end
        snapCombo:SetValue("Snapshots (" .. #snaps() .. ")")
    end
    local saveBtn = vgui.Create("DButton", top)
    saveBtn:SetText("Save snapshot")
    saveBtn:Dock(LEFT)
    saveBtn:SetWide(100)
    saveBtn:DockMargin(4, 0, 0, 0)
    saveBtn.DoClick = function()
        Derma_StringRequest("Save snapshot", "Name for this snapshot", os.date("%H:%M:%S"), function(name)
            local list = snaps()
            list[#list + 1] = { name = string.sub(name ~= "" and name or os.date("%H:%M:%S"), 1, 40), ik = copyOut() }
            file.Write(SNAP, util.TableToJSON(list) or "[]")
            fillSnaps()
        end)
    end
    local row2 = f.list:Add("DPanel")
    row2:SetTall(24)
    row2:Dock(TOP)
    row2:DockMargin(4, 1, 4, 1)
    row2:SetPaintBackground(false)
    local delBtn = vgui.Create("DButton", row2)
    delBtn:SetText("Delete")
    delBtn:Dock(RIGHT)
    delBtn:SetWide(54)
    local loadBtn = vgui.Create("DButton", row2)
    loadBtn:SetText("Load")
    loadBtn:Dock(RIGHT)
    loadBtn:SetWide(50)
    loadBtn:DockMargin(4, 0, 4, 0)
    snapCombo = vgui.Create("DComboBox", row2)
    snapCombo:Dock(FILL)
    fillSnaps()
    local function picked()
        local _, i = snapCombo:GetSelected()
        return i
    end
    loadBtn.DoClick = function()
        local i = picked()
        local sn = i and snaps()[i]
        if sn then loadInto(sn.ik) end
    end
    delBtn.DoClick = function()
        local i = picked()
        if not i then return end
        local list = snaps()
        table.remove(list, i)
        file.Write(SNAP, util.TableToJSON(list) or "[]")
        fillSnaps()
    end
    local ROWS = {
        { "pos", "Wrist position (from the head)", { "X", "Y", "Z" }, 0.5, 30 },
        { "ang", "Hand turn (from the head)", { "Pitch", "Yaw", "Roll" }, 5, 180 },
        { "elbow", "Elbow bends toward (from the head)", { "X", "Y", "Z" }, 1, 60 },
    }
    for _, row in ipairs(ROWS) do
        label(row[2])
        for i, ax in ipairs(row[3]) do
            local key = row[1]
            field(ax, row[4], -row[5], row[5], function() return ik[key][i] end, function(v) ik[key][i] = v changed() end)
        end
    end
    -- Shoulder by hand: lock the upper arm where it is now (in the chest's
    -- axes), then turn it with these rows; unlocked, the elbow point and
    -- swivel above decide it instead.
    label("Shoulder (upper arm from the chest; Lock first)")
    local lockBtn = f.list:Add("DButton")
    lockBtn:SetTall(24)
    lockBtn:Dock(TOP)
    lockBtn:DockMargin(4, 2, 4, 2)
    local function lockText() lockBtn:SetText(ik.shoulder and "Shoulder locked: click to unlock (elbow point decides)" or "Lock the shoulder where it is now") end
    lockText()
    lockBtn.DoClick = function()
        if ik.shoulder then
            ik.shoulder = nil
        else
            local la = R.earUpperLocal or Angle()
            ik.shoulder = { math.Round(la.p), math.Round(la.y), math.Round(la.r) }
        end
        lockText()
        for _, show in ipairs(rows) do show() end
        changed()
    end
    for i, ax in ipairs({ "Pitch", "Yaw", "Roll" }) do
        field("Shoulder " .. ax, 2, -180, 180, function() return ik.shoulder and ik.shoulder[i] or 0 end,
            function(v) if ik.shoulder then ik.shoulder[i] = v changed() end end)
    end
    -- Transition point: where the arm goes first on its way to the ear
    -- (and back), so it doesn't cut through the body. "Show it" holds your
    -- arm there; Lock takes the arm as it is now (from the chest), then the
    -- rows move it. Needs the shoulder locked.
    label("Transition point (the arm passes here first; needs the shoulder locked)")
    local via = f.list:Add("DPanel")
    via:SetTall(24)
    via:Dock(TOP)
    via:DockMargin(4, 2, 4, 2)
    via:SetPaintBackground(false)
    local showBtn = vgui.Create("DButton", via)
    showBtn:Dock(LEFT)
    showBtn:SetWide(150)
    local function showText() showBtn:SetText(R.earViaPreview and "Showing it: click to stop" or "Show the transition point") end
    showText()
    showBtn.DoClick = function() R.earViaPreview = not R.earViaPreview showText() end
    local viaBtn = vgui.Create("DButton", via)
    viaBtn:Dock(FILL)
    viaBtn:DockMargin(4, 0, 0, 0)
    local function viaText() viaBtn:SetText(ik.viaShoulder and "Transition set: click to clear" or "Set the transition point to the arm now") end
    viaText()
    -- (set from the arm as it is now; also done by itself on the first edit
    -- of a Via row, and the shoulder gets locked if it wasn't)
    local function setVia()
        if not ik.shoulder then
            local la = R.earUpperLocal or Angle()
            ik.shoulder = { math.Round(la.p), math.Round(la.y), math.Round(la.r) }
            if lockText then lockText() end
        end
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
    viaBtn.DoClick = function()
        if ik.viaShoulder then
            ik.viaShoulder, ik.viaPos, ik.viaAng = nil, nil, nil
        else
            setVia()
        end
        viaText()
        for _, show in ipairs(rows) do show() end
        changed()
    end
    local function viaEdit(key, i, v)
        if not ik.viaShoulder then
            setVia()
            viaText()
            for _, show in ipairs(rows) do show() end
        end
        ik[key][i] = v
        changed()
    end
    for i, ax in ipairs({ "Pitch", "Yaw", "Roll" }) do
        field("Via shoulder " .. ax, 2, -180, 180, function()
                if ik.viaShoulder then return ik.viaShoulder[i] end
                local la = R.earUpperLocal or Angle()
                return math.Round(({ la.p, la.y, la.r })[i])
            end,
            function(v) viaEdit("viaShoulder", i, v) end)
    end
    for i, ax in ipairs({ "Pitch", "Yaw", "Roll" }) do
        field("Via hand " .. ax, 5, -180, 180, function() return ik.viaAng and ik.viaAng[i] or 0 end,
            function(v)
                if not ik.viaShoulder then setVia() viaText() for _, show in ipairs(rows) do show() end end
                ik.viaAng = ik.viaAng or { 0, 0, 0 }
                ik.viaAng[i] = v
                changed()
            end)
    end
    for i, ax in ipairs({ "X", "Y", "Z" }) do
        field("Via wrist " .. ax, 0.5, -40, 40, function()
                if ik.viaPos then return ik.viaPos[i] end
                local wl = R.earWristLocal or Vector()
                return math.Round(({ wl.x, wl.y, wl.z })[i], 1)
            end,
            function(v) viaEdit("viaPos", i, v) end)
    end
    -- Elbow swivel: turns the elbow round the shoulder-to-wrist line.
    label("Elbow swivel (turns the elbow round the arm's line)")
    field("Degrees", 5, -180, 180, function() return ik.swivel end, function(v) ik.swivel = v changed() end)
    -- Finger pose: any sequence of your model (the fingers as they are in
    -- it), picked from the list or stepped with < >.
    label("Finger pose (from one of your model's animations)")
    local seqs = { "" }
    for _, name in pairs(me:GetSequenceList() or {}) do seqs[#seqs + 1] = name end
    table.sort(seqs)
    local row = f.list:Add("DPanel")
    row:SetTall(24)
    row:Dock(TOP)
    row:DockMargin(4, 1, 4, 1)
    row:SetPaintBackground(false)
    local combo
    local function pick(i)
        i = (i - 1) % #seqs + 1
        ik.fingers = seqs[i]
        combo:SetValue(seqs[i] == "" and "(reference pose)" or seqs[i])
        changed()
    end
    local function index()
        for i, n in ipairs(seqs) do if n == ik.fingers then return i end end
        return 1
    end
    local prev = vgui.Create("DButton", row)
    prev:SetText("<") prev:SetWide(26) prev:Dock(LEFT)
    prev.DoClick = function() pick(index() - 1) end
    local nxt = vgui.Create("DButton", row)
    nxt:SetText(">") nxt:SetWide(26) nxt:Dock(RIGHT)
    nxt.DoClick = function() pick(index() + 1) end
    combo = vgui.Create("DComboBox", row)
    combo:Dock(FILL)
    combo:DockMargin(4, 0, 4, 0)
    for i, n in ipairs(seqs) do combo:AddChoice(n == "" and "(reference pose)" or n, i) end
    combo:SetValue(ik.fingers == "" and "(reference pose)" or ik.fingers)
    refreshAll = function()
        for _, show in ipairs(rows) do show() end
        if lockText then lockText() end
        if viaText then viaText() end
        combo:SetValue(ik.fingers == "" and "(reference pose)" or ik.fingers)
    end
    function combo:OnSelect(_, _, i) pick(i) end
    f.copyButton(function()
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
    label("Transform (click a dot on the model, then drag the gizmo)")
    local trow = f.list:Add("DPanel")
    trow:SetTall(24)
    trow:Dock(TOP)
    trow:DockMargin(4, 1, 4, 1)
    trow:SetPaintBackground(false)
    local function tbtn(text, w, fn, sel)
        local b = vgui.Create("DButton", trow)
        b:Dock(LEFT)
        b:SetWide(w)
        b:DockMargin(0, 0, 3, 0)
        b:SetText(text)
        b.DoClick = fn
        if sel then function b:Think() self:SetText((sel() and "> " or "") .. text) end end
        return b
    end
    tbtn("Move (W)", 70, function() G.mode = "move" end, function() return G.mode == "move" end)
    tbtn("Rotate (E)", 74, function() G.mode = "rotate" end, function() return G.mode == "rotate" end)
    local spaceBtn = tbtn("", 110, function() G.space = G.space == "local" and "world" or "local" end)
    function spaceBtn:Think() self:SetText(G.space == "local" and "Axes: local (Q)" or "Axes: world (Q)") end
    function f:OnKeyCodePressed(k)
        if k == KEY_W then G.mode = "move" elseif k == KEY_E then G.mode = "rotate" elseif k == KEY_Q then G.space = G.space == "local" and "world" or "local" end
    end

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
            if lockText then lockText() end
            if viaText then viaText() end
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
    addOrbit(f, label, false, "ValveBiped.Bip01_Head1")
end)
