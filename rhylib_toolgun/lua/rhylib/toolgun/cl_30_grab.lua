--[[
    Toolgun modes and physgun mode (client).

    Hold E (Use) with the toolgun out, not aiming at something close by
    (so E on doors, bombs and players still works): a wheel (rhylib_menus
    Menus.Wheel) to pick the mode: Place / spawn, Command (Command mode,
    needs rhylib_droids, cl_20_command.lua) or Physgun. The physgun key
    (rhylib_tool_physgun_key, default t) switches physgun mode on and off.
    The mode is NW2Int rhylib_toolMode on the toolgun (server: net
    tool.mode, sv_20_grab.lua); Command mode is Tool.command here.

    Physgun mode (the server moves things, sv_20_grab.lua): LMB hold grab,
    wheel nearer / further (net tool.grabdist), R held rotate (the view
    stops turning here), RMB freeze and let go / unfreeze. The beam is
    drawn from the toolgun's own muzzle (its prop's PropMuzzle) to the held
    point, for everyone who can see it; nothing shows through walls (it's
    drawn in the world).

    Adds Tool.ToolMode(w) -> 0 / 1, Tool.SendMode(n), Tool.DrawPhysHUD().
]]

local Tool = Rhylib.Tool
local CLASS = "rhylib_toolgun"

local cvPhysKey = GetConVar("rhylib_tool_physgun_key")

function Tool.ToolMode(w)
    return IsValid(w) and w:GetClass() == CLASS and w:GetNW2Int("rhylib_toolMode", 0) or 0
end

function Tool.SendMode(n)
    Rhylib.Net.Start("tool.mode")
    net.WriteUInt(n, 2)
    net.SendToServer()
end

local function toolgun()
    local me = LocalPlayer()
    local w = IsValid(me) and me:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == CLASS and w or nil
end

local function physOn()
    return Tool.ToolMode(toolgun()) == 1
end
Tool.PhysOnLocal = physOn

local function holding()
    local me = LocalPlayer()
    return IsValid(me) and IsValid(me:GetNW2Entity("rhylib_grabEnt"))
end

local function setMode(mode, command)
    Tool.command = command and Rhylib.Droids ~= nil or false
    Tool.SendMode(mode)
    surface.PlaySound("buttons/button17.wav")
end

-- The mode wheel (hold E).
local function openWheel(code)
    local M = Rhylib.Menus
    local W = M and M.Wheel
    if not (W and W.OpenList) then return end
    local w = toolgun()
    local phys = Tool.ToolMode(w) == 1
    local cur = phys and "phys" or (Tool.command and "cmd" or "place")
    local list = {
        { label = "Place / spawn", run = function() setMode(0, false) end, sub = cur == "place" and "Now" or "LMB places, RMB removes, R spawn window",
          col = Color(255, 210, 80) },
        { label = "Physgun", run = function() setMode(1, false) end, sub = cur == "phys" and "Now" or "Move, turn and freeze things",
          col = Color(90, 170, 255) },
    }
    if Rhylib.Droids then
        table.insert(list, 2, { label = "Command", run = function() setMode(0, true) end, sub = cur == "cmd" and "Now" or "Select and order droids and clones",
            col = Color(255, 100, 80) })
    end
    W.OpenList("Toolgun mode", list, code)
end

local useAt, useOpened = nil, false
local physWas = false
Rhylib.Hook.Add("Think", "toolgun.modes", function()
    local me = LocalPlayer()
    local w = toolgun()
    if not w then useAt, physWas = nil, false return end
    local free = not vgui.GetKeyboardFocus() and not vgui.CursorVisible() and not gui.IsGameUIVisible() and not me:IsTyping()
    -- Hold E: the mode wheel.
    local bind = input.LookupBinding("+use")
    local code = bind and input.GetKeyCode(bind) or KEY_E
    local down = free and code and code > 0 and input.IsButtonDown(code)
    if down then
        if not useAt then
            useAt, useOpened = RealTime(), false
        elseif not useOpened and RealTime() - useAt > 0.3 then
            useOpened = true
            local M = Rhylib.Menus
            local busy = M and M.Wheel and M.Wheel.open
            local tr = me:GetEyeTrace()
            local near = IsValid(tr.Entity) and tr.HitPos:DistToSqr(me:EyePos()) < 150 * 150
            if not busy and not near and not holding() then openWheel(code) end
        end
    else
        useAt = nil
    end
    -- The physgun key: physgun mode on / off.
    local pk = cvPhysKey and input.GetKeyCode(cvPhysKey:GetString())
    local pd = free and pk and pk > 0 and input.IsButtonDown(pk) or false
    if pd and not physWas then setMode(physOn() and 0 or 1, false) end
    physWas = pd
end)

-- R held while holding something: the mouse turns it, not the view.
Rhylib.Hook.Add("InputMouseApply", "toolgun.grab", function(cmd, x, y, ang)
    if physOn() and holding() and LocalPlayer():KeyDown(IN_RELOAD) then
        -- (the server reads the turn from the command's mouse movement)
        cmd:SetMouseX(math.Round(x))
        cmd:SetMouseY(math.Round(y))
        return true
    end
end, -45)

-- Wheel while holding something: nearer / further (not weapon switching).
Rhylib.Hook.Add("PlayerBindPress", "toolgun.grab", function(ply, bind, pressed)
    if not pressed or not physOn() then return end
    local up = string.find(bind, "invprev", 1, true)
    local dn = string.find(bind, "invnext", 1, true)
    if (up or dn) and holding() then
        Rhylib.Net.Start("tool.grabdist")
        net.WriteInt(up and 1 or -1, 4)
        net.SendToServer()
        return true
    end
end, -38)

-- The beam: from the toolgun's muzzle to the held point.
local BEAM = Material("sprites/physbeama")
local GLOW = Material("sprites/light_glow02_add")   -- (depth tested: nothing through walls)
local BEAM_COL = Color(90, 170, 255)
local function muzzle(ply, w)
    local fp = ply == LocalPlayer() and not ply:ShouldDrawLocalPlayer()
    local m = w.GetPropMuzzle and w:GetPropMuzzle(fp)
    if m then return m end
    local a = ply:EyeAngles()
    return ply:EyePos() + a:Forward() * 20 + a:Right() * 6 - a:Up() * 6
end

Rhylib.Hook.Add("PostDrawTranslucentRenderables", "toolgun.grab", function(depth, sky)
    if depth or sky then return end
    for _, ply in ipairs(player.GetAll()) do
        local ent = ply:GetNW2Entity("rhylib_grabEnt")
        if IsValid(ent) then
            local w = ply:GetActiveWeapon()
            -- (not for a cloaked or hidden holder: it would show where they are)
            local hidden = ply ~= LocalPlayer() and (ply:GetNW2Bool(Rhylib.NW.CLOAK, false) or ply:GetNoDraw())
            if IsValid(w) and w:GetClass() == CLASS and not ply:IsDormant() and not hidden then
                local a = muzzle(ply, w)
                local lp = ply:GetNW2Vector("rhylib_grabLocal")
                local bone = ply:GetNW2Int("rhylib_grabBone", -1)
                local b
                local m = bone >= 0 and ent:GetBoneMatrix(bone)
                if m then
                    b = LocalToWorld(lp, angle_zero, m:GetTranslation(), m:GetAngles())
                else
                    b = ent:LocalToWorld(lp)
                end
                -- (a curve that leaves the gun straight ahead and bends onto the point)
                local ctrl = a + ply:GetAimVector() * a:Distance(b) * 0.5
                local n = 12
                local scroll = CurTime() * 2
                render.SetMaterial(BEAM)
                render.StartBeam(n + 1)
                for i = 0, n do
                    local t = i / n
                    local p = (1 - t) * (1 - t) * a + 2 * (1 - t) * t * ctrl + t * t * b
                    render.AddBeam(p, 6, scroll + t * 3, BEAM_COL)
                end
                render.EndBeam()
                render.SetMaterial(GLOW)
                render.DrawSprite(b, 16, 16, BEAM_COL)
                render.DrawSprite(a, 10, 10, BEAM_COL)
            end
        end
    end
end)

-- HUD in physgun mode (cl_10_tool's DrawHUD calls it).
function Tool.DrawPhysHUD()
    local x, y = ScrW() * 0.5, ScrH() * 0.5 + 40
    local key = cvPhysKey and string.upper(cvPhysKey:GetString()) or "T"
    draw.SimpleTextOutlined("PHYSGUN MODE", Rhylib.UI.Font(16, 700), x, y, BEAM_COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    local f = Rhylib.UI.Font(13)
    draw.SimpleTextOutlined("LMB hold: grab  ·  wheel: nearer / further  ·  R + mouse: turn  ·  RMB: freeze / unfreeze", f, x, y + 22, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    draw.SimpleTextOutlined(key .. " or hold E: other modes  ·  letting go of a permanent thing saves its spot", f, x, y + 38, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
end
