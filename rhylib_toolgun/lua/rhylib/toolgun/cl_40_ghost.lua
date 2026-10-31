--[[
    Toolgun placement preview (client): a see-through copy of what LMB
    will place or spawn, standing where it will stand and turned the way
    it will face. Ctrl + mouse wheel turns it (15 degrees a step, held for
    the next ones; Ctrl + R straightens it again). The turn is sent with
    the click (tool.place / tool.spawn, Float yaw offset) and the server
    places the thing at that angle.

    Works for Rhylib entries with a model (NPCs, fixtures, presets: the
    main unit) and for spawn-window things (props, entities, NPCs,
    vehicles, weapons). Several at once (count) show each one in its ring.
    Hidden in Command and physgun mode, and for orders, markers' brushes
    and the Permanent tool. Only you see it (client models; nothing is
    networked).

    Adds Tool.rot (the yaw offset), Tool.GhostModel(entry) -> model path.
]]

local Tool = Rhylib.Tool
local CLASS = "rhylib_toolgun"

Tool.rot = Tool.rot or 0

local ghosts = {}   -- client models, reused
local GHOST_COL = Color(150, 200, 255, 110)

local function listModel(kind, name)
    if kind == "prop" then return name end
    if kind == "npc" then
        local n = list.Get("NPC")[name]
        return n and n.Model or Tool.ClassModel(n and n.Class or name)
    elseif kind == "vehicle" then
        local v = list.Get("Vehicles")[name]
        return v and v.Model
    elseif kind == "weapon" then
        local w = weapons.Get(name)
        return w and w.WorldModel ~= "" and w.WorldModel or nil
    elseif kind == "entity" then
        local t = scripted_ents.GetStored(name)
        return (t and t.t and t.t.Model) or Tool.ClassModel(name)
    end
end

-- Tool.GhostModel(entry) -> the model to preview (or nil).
function Tool.GhostModel(e)
    if not e then return nil end
    if e.custom then return listModel(e.custom.kind, e.custom.name) end
    if e.order or e.follow or e.perma or e.marker then return nil end
    return Tool.EntryModel and Tool.EntryModel(e) or nil
end

local function hideAll(from)
    for i = from or 1, #ghosts do
        local g = ghosts[i]
        if IsValid(g) then g:SetNoDraw(true) end
    end
end

local function ghost(i, model)
    local g = ghosts[i]
    if not IsValid(g) then
        g = ClientsideModel(model, RENDERGROUP_TRANSLUCENT)
        if not IsValid(g) then return nil end
        g:SetRenderMode(RENDERMODE_TRANSCOLOR)
        g:SetColor(GHOST_COL)
        g:DrawShadow(false)
        ghosts[i] = g
    end
    if g:GetModel() ~= model then g:SetModel(model) end
    g:SetNoDraw(false)
    return g
end

local function active()
    local me = LocalPlayer()
    local w = IsValid(me) and me:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == CLASS) then return nil end
    if Tool.command or (Tool.ToolMode and Tool.ToolMode(w) == 1) then return nil end
    return me
end

Rhylib.Hook.Add("Think", "toolgun.ghost", function()
    local me = active()
    if not me then hideAll() return end
    local e = Tool.Chosen and Tool.Chosen()
    local model = Tool.GhostModel(e)
    if not model or model == "" or not (util.IsValidModel(model) or file.Exists(model, "GAME")) then hideAll() return end
    local tr = me:GetEyeTrace()
    if not tr.Hit or tr.HitSky or tr.HitPos:DistToSqr(me:EyePos()) > (Tool.RANGE or 4096) ^ 2 then hideAll() return end
    local yaw = (me:GetPos() - tr.HitPos):Angle().y
    if e.custom then yaw = me:EyeAngles().y + 180 end
    yaw = yaw + Tool.rot
    local count = (e.count and not e.custom) and math.Clamp(GetConVarNumber("rhylib_tool_count"), 1, 5) or 1
    for i = 1, count do
        local pos = tr.HitPos
        if count > 1 then
            -- (the same ring the server places them in)
            local a = (i / count) * math.pi * 2
            local r = 45 + count * 6
            pos = pos + Vector(math.cos(a) * r, math.sin(a) * r, 0)
            local down = util.TraceLine({ start = pos + Vector(0, 0, 40), endpos = pos - Vector(0, 0, 120), mask = MASK_SOLID })
            if down.Hit then pos = down.HitPos end
        end
        local g = ghost(i, model)
        if g then
            g:SetAngles(Angle(0, yaw, 0))
            -- (sits on the surface like the real thing)
            local mins = g:OBBMins()
            g:SetPos(pos + tr.HitNormal * 2 - Vector(0, 0, math.min(mins.z, 0)))
        end
    end
    hideAll(count + 1)
end)

-- Ctrl + wheel turns it; Ctrl + R straightens it.
Rhylib.Hook.Add("PlayerBindPress", "toolgun.ghost", function(ply, bind, pressed)
    if not pressed or not active() then return end
    if not (input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)) then return end
    local up = string.find(bind, "invprev", 1, true)
    local dn = string.find(bind, "invnext", 1, true)
    if up or dn then
        Tool.rot = (Tool.rot + (up and 15 or -15)) % 360
        surface.PlaySound("buttons/lightswitch2.wav")
        return true
    end
    if bind == "+reload" then
        Tool.rot = 0
        surface.PlaySound("buttons/lightswitch2.wav")
        return true
    end
end, -40)

-- (the client models go when the toolgun isn't out for a while)
timer.Create("Rhylib.Tool.Ghost", 10, 0, function()
    if active() then return end
    for i, g in pairs(ghosts) do
        if IsValid(g) then g:Remove() end
        ghosts[i] = nil
    end
end)
