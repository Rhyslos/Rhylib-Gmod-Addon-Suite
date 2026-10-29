--[[
    Weapon position editors (client; moved out of the weapon base so live
    servers don't send them to every player). Hold the gun, then:
      rhylib_vm_editor      first person: prop offset / size, VMOffset, AimPos,
                            FOV, the SafePose and ModeProxies blocks, and
                            grenades (PropVMPos / PropVMAng / PropVMScale);
                            Copy prints the lines for the weapon file
      rhylib_wm_editor      third person: PropWMPos / PropWMAng / PropScale
                            (and the left pistol's DualPropWM*), with an
                            orbit camera around the right hand
      rhylib_extra_editor   ExtraProps (both views), CarrierBoneMods,
                            WorldBoneMods
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

concommand.Add("rhylib_vm_editor", function()
    if IsValid(editor) then editor:Remove() return end
    local g = LocalPlayer():GetActiveWeapon()
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
local orbit = { on = false, yaw = 30, pitch = 10, dist = 45 }

local function orbitCentre(ply)
    ply:SetupBones()
    local b = ply:LookupBone("ValveBiped.Bip01_R_Hand")
    local m = b and ply:GetBoneMatrix(b)
    return m and m:GetTranslation() or (ply:GetPos() + Vector(0, 0, 45))
end

Rhylib.Hook.Add("CalcView", "weapons.editorcam", function(ply, pos, angles, fov)
    if not orbit.on then return end
    if not IsValid(orbit.frame) or ply ~= LocalPlayer() or not ply:Alive() then
        orbit.on = false
        return
    end
    local centre = orbitCentre(ply)
    local dir = Angle(orbit.pitch, ply:GetRenderAngles().y + orbit.yaw, 0):Forward()
    local origin = centre + dir * orbit.dist
    return { origin = origin, angles = (centre - origin):Angle(), fov = 60, znear = 1, drawviewer = true }
end, -60)   -- (before the body camera and third person)

-- (no gun sway or first-person bits while orbiting)
Rhylib.Hook.Add("ShouldDrawLocalPlayer", "weapons.editorcam", function()
    if orbit.on and IsValid(orbit.frame) then return true end
end, -60)

local function addOrbit(f, label, startOff)
    orbit.frame = f
    orbit.on = not startOff
    label("Camera (circles your right hand)")
    local list = f.list
    local row = list:Add("DPanel")
    row:SetTall(24)
    row:Dock(TOP)
    row:DockMargin(4, 1, 4, 1)
    row:SetPaintBackground(false)
    local presets = { { "Front", 0, 5 }, { "Back", 180, 5 }, { "Left", 90, 5 }, { "Right", -90, 5 }, { "Top", 0, -85 }, { "Below", 0, 60 } }
    for _, p in ipairs(presets) do
        local b = vgui.Create("DButton", row)
        b:SetText(p[1])
        b:SetWide(50)
        b:Dock(LEFT)
        b:DockMargin(0, 0, 2, 0)
        b.DoClick = function()
            orbit.on = true
            orbit.yaw, orbit.pitch = p[2], p[3]
        end
    end
    local pad = list:Add("DPanel")
    pad:SetTall(90)
    pad:Dock(TOP)
    pad:DockMargin(4, 4, 4, 1)
    pad:SetCursor("sizeall")
    function pad:Paint(w, h)
        surface.SetDrawColor(20, 24, 30, 220)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(80, 100, 130, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("Drag here to turn · wheel to zoom", "DermaDefault", w * 0.5, h * 0.42, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("yaw %d · pitch %d · %d units", orbit.yaw, orbit.pitch, orbit.dist), "DermaDefault", w * 0.5, h * 0.66,
            Color(170, 180, 190), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    function pad:OnMousePressed(code)
        if code ~= MOUSE_LEFT then return end
        self.drag = { gui.MouseX(), gui.MouseY() }
        self:MouseCapture(true)
    end
    function pad:OnMouseReleased()
        self.drag = nil
        self:MouseCapture(false)
    end
    function pad:Think()
        if not self.drag then return end
        local x, y = gui.MouseX(), gui.MouseY()
        orbit.yaw = math.NormalizeAngle(orbit.yaw - (x - self.drag[1]) * 0.5)
        orbit.pitch = math.Clamp(orbit.pitch + (y - self.drag[2]) * 0.4, -89, 89)
        self.drag = { x, y }
        orbit.on = true
    end
    function pad:OnMouseWheeled(d)
        orbit.dist = math.Clamp(orbit.dist - d * 5, 15, 200)
        orbit.on = true
        return true
    end
    -- Zoom: distance from the hand (the wheel on the pad moves it too).
    local zoom = list:Add("DNumSlider")
    zoom:Dock(TOP)
    zoom:DockMargin(4, 4, 4, 1)
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
    local off = list:Add("DCheckBoxLabel")
    off:SetText("Orbit camera on")
    off:Dock(TOP)
    off:DockMargin(4, 4, 4, 2)
    off:SetValue(orbit.on)
    function off:OnChange(v) orbit.on = v end
    function off:Think()
        if self:GetChecked() ~= orbit.on then self:SetChecked(orbit.on) end
    end
end

-- rhylib_wm_editor: the third-person gun (PropWMPos / PropWMAng /
-- PropScale, from the right hand). Only your own view changes; the
-- orbit camera shows it from any side.
local wmEditor
concommand.Add("rhylib_wm_editor", function()
    if IsValid(wmEditor) then wmEditor:Remove() return end
    -- Any weapon with a third-person prop (guns, grenades).
    local w = LocalPlayer():GetActiveWeapon()
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

