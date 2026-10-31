--[[
    Toolgun Command mode (client): select droids and clones and give them
    orders straight from the toolgun, without the spawn window. Needs
    rhylib_droids (the orders are its droids.cmd net, sv_45_command.lua).

    The command key (rhylib_tool_command_key, default x; Settings >
    Weapons) with the toolgun out switches between placing and Command
    mode. In Command mode:
      LMB             select what you aim at (its whole squad); hold and
                      sweep across the ground to add everything you pass
                      over; LMB on nothing clears. Shift + LMB adds to the
                      selection (or takes a squad out of it).
      RMB             the selection moves there in formation; hold RMB,
                      drag and let go to set the way they face when there.
      RMB on an enemy they hunt it.
      Shift + RMB     adds a patrol route point (up to 12; numbered
                      rings joined in a loop). Shift + RMB on the first
                      point clears the route.
      Ctrl + wheel    the area size for Spread out, Defend 360 and Patrol
                      area (a ring where you aim while Ctrl is held).
      1-5             aggression of the selected squads (1 retreat ... 5
                      charge); 6 back to the global level.
      R (hold)        order wheel, for where you aim when it opens: Hold,
                      Defend 360 (ring all round, cover facing out),
                      Spread out (own spots over the area), Patrol,
                      Patrol area, Patrol route, Roam, Remove, Split up,
                      Make one squad, Next formation, Retreat, Hunt,
                      Assault here (attack that spot; NPCs placed as
                      ASSAULT go there too, a red ring marks it).
    Selected NPCs get an outline (only for you). The HUD lists the
    controls and the selection. The selection is kept while you switch
    weapons; it drops NPCs that die.

    Client only. Client convar rhylib_tool_command_key. Adds Tool.command
    (on/off), Tool.Selection() -> list, Tool.CommandWheel(code) (the R key
    handler in cl_10_tool calls it in Command mode), Tool.DrawCommandHUD().
]]

local Tool = Rhylib.Tool

local cvKey = CreateClientConVar("rhylib_tool_command_key", "x", true, false, "Toolgun: key that switches between placing and Command mode")

Tool.command = Tool.command or false
local sel = {}          -- [npc] = true
local selSide = nil     -- 1 clones, 2 droids
local COL_SEL = Color(255, 220, 90)
local COL = Color(255, 210, 80)
local COL_DIM = Color(220, 220, 220)

local OP = { move = 1, attack = 2, aggro = 3, mode = 4, formation = 5, group = 6, split = 7, remove = 8,
    assault = 9, spread = 10, defend = 11, area = 12, route = 13 }

Tool.cmdRadius = Tool.cmdRadius or 500   -- (units; Ctrl + wheel)
Tool.route = Tool.route or {}            -- patrol route points (Shift + RMB)
local assaultAt = {}                     -- [side] = the assault point this GM set (1 clones, 2 droids)
local COL_ROUTE = Color(120, 230, 140)
local COL_ASSAULT = Color(255, 60, 40)

local function toolOut()
    local me = LocalPlayer()
    local w = IsValid(me) and me:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == "rhylib_toolgun"
end
local function free()
    return not vgui.CursorVisible() and not gui.IsGameUIVisible() and not vgui.GetKeyboardFocus()
        and not (Rhylib.Menus and Rhylib.Menus.Wheel and Rhylib.Menus.Wheel.open)
end
local function npc(e) return IsValid(e) and (e.IsRhylibDroid or e.IsRhylibClone) and e:Health() > 0 end
local function sideOf(e) return e.IsRhylibClone and 1 or 2 end

-- Every droid and clone the client knows (refreshed twice a second).
local all, allAt = {}, 0
local function npcs()
    local now = RealTime()
    if now > allAt then
        allAt = now + 0.5
        all = {}
        for _, e in ipairs(ents.GetAll()) do
            if e.IsRhylibDroid or e.IsRhylibClone then all[#all + 1] = e end
        end
    end
    return all
end

function Tool.Selection()
    local out = {}
    for e in pairs(sel) do
        if npc(e) then out[#out + 1] = e else sel[e] = nil end
    end
    if #out == 0 then selSide = nil end
    return out
end

-- The NPC under the crosshair: the trace hit, else the one nearest the
-- aim within 2.5 degrees.
local function aimedNpc()
    local me = LocalPlayer()
    local tr = me:GetEyeTrace()
    if npc(tr.Entity) then return tr.Entity end
    local eye, aim = me:EyePos(), me:GetAimVector()
    local best, bestDot = nil, math.cos(math.rad(2.5))
    for _, e in ipairs(npcs()) do
        if npc(e) then
            local d = e:WorldSpaceCenter() - eye
            local len = d:Length()
            if len < 4000 and len > 1 then
                local dot = aim:Dot(d / len)
                if dot > bestDot then best, bestDot = e, dot end
            end
        end
    end
    return best
end

-- Add (or with remove, take out) e and its squad.
local function pick(e, remove)
    if not npc(e) then return 0 end
    if not remove and selSide and sideOf(e) ~= selSide then return 0 end
    local id = e:GetNW2Int("rhylib_squad", 0)
    local n = 0
    local group = { e }
    if id > 0 then
        group = {}
        for _, o in ipairs(npcs()) do
            if npc(o) and o:GetNW2Int("rhylib_squad", 0) == id then group[#group + 1] = o end
        end
    end
    for _, o in ipairs(group) do
        if remove then sel[o] = nil else sel[o] = true end
        n = n + 1
    end
    if not remove then selSide = selSide or sideOf(e) end
    return n
end

local function send(op, write)
    local list = Tool.Selection()
    if #list == 0 then
        Rhylib.Notify(nil, "Select droids or clones first (LMB)", "bad", "Droids")
        return false
    end
    Rhylib.Net.Start("droids.cmd")
    net.WriteUInt(op, 4)
    local n = math.min(#list, 100)
    net.WriteUInt(n, 7)
    for i = 1, n do net.WriteUInt(list[i]:EntIndex(), 13) end
    if write then write() end
    net.SendToServer()
    surface.PlaySound("buttons/button14.wav")
    return true
end

local function isEnemyOf(e, side)
    if not IsValid(e) then return false end
    if side == 1 then return e.IsRhylibDroid == true end
    return e:IsPlayer() or e.IsRhylibClone == true
end

-- Mouse buttons (read here: the attack keys only fire on press).
local lmb, rmb = false, false
local sweep = nil       -- { hitNpc, added }
local rStart = nil      -- { pos, ent }
local keyWas = false

Rhylib.Hook.Add("Think", "toolgun.command", function()
    if not Rhylib.Droids then return end
    local out = toolOut()
    -- The command key switches mode (toolgun out).
    local code = input.GetKeyCode(cvKey:GetString())
    local kd = out and code and code > 0 and input.IsButtonDown(code) or false
    if kd and not keyWas and free() and not LocalPlayer():IsTyping() then
        if not Tool.command and Tool.FullAccess and not Tool.FullAccess(LocalPlayer()) then
            Rhylib.Notify(nil, "Command mode needs full toolgun access", "bad", "Droids")
            keyWas = kd
            return
        end
        Tool.command = not Tool.command
        if Tool.command and Tool.PhysOnLocal and Tool.PhysOnLocal() then Tool.SendMode(0) end   -- (out of physgun mode)
        surface.PlaySound(Tool.command and "buttons/button17.wav" or "buttons/button18.wav")
    end
    keyWas = kd
    if not (out and Tool.command) then
        lmb, rmb, sweep, rStart = false, false, nil, nil
        return
    end
    local me = LocalPlayer()
    local canClick = free()
    local l = canClick and input.IsMouseDown(MOUSE_LEFT)
    local r = canClick and input.IsMouseDown(MOUSE_RIGHT)
    local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)

    -- LMB: select / sweep.
    if l and not lmb then
        local e = aimedNpc()
        if not shift and not (e and sel[e]) then sel, selSide = {}, nil end
        local added = 0
        if e then added = pick(e, shift and sel[e]) end
        sweep = { hit = e ~= nil, added = added, at = 0 }
    elseif l and sweep then
        local now = RealTime()
        if now >= sweep.at then
            sweep.at = now + 0.05
            local tr = me:GetEyeTrace()
            if tr.Hit then
                for _, o in ipairs(npcs()) do
                    if npc(o) and not sel[o] and o:GetPos():DistToSqr(tr.HitPos) < 110 * 110 then
                        sweep.added = sweep.added + pick(o)
                    end
                end
            end
        end
    elseif not l and lmb then
        sweep = nil
    end
    lmb = l

    -- Shift + RMB: a route point (on the first point: clear the route).
    if r and not rmb and shift then
        local tr = me:GetEyeTrace()
        if tr.Hit then
            local rt = Tool.route
            if #rt > 0 and rt[1]:DistToSqr(tr.HitPos) < 60 * 60 then
                Tool.route = {}
                surface.PlaySound("buttons/button18.wav")
            elseif #rt >= 12 then
                Rhylib.Notify(nil, "A route has at most 12 points", "bad", "Droids")
            else
                rt[#rt + 1] = tr.HitPos
                surface.PlaySound("buttons/lightswitch2.wav")
            end
        end
        rStart = nil
    -- RMB: move (drag = facing) or attack.
    elseif r and not rmb then
        local tr = me:GetEyeTrace()
        local e = tr.Entity
        if not IsValid(e) or not isEnemyOf(e, selSide) then e = nil end
        rStart = tr.Hit and { pos = tr.HitPos, ent = e } or nil
    elseif not r and rmb and rStart then
        local s = rStart
        rStart = nil
        if s.ent and IsValid(s.ent) then
            send(OP.attack, function() net.WriteUInt(s.ent:EntIndex(), 13) end)
        else
            local tr = me:GetEyeTrace()
            local d = tr.HitPos - s.pos
            d.z = 0
            local face = tr.Hit and d:LengthSqr() > 64 * 64
            send(OP.move, function()
                net.WriteVector(s.pos)
                net.WriteBool(face)
                net.WriteFloat(face and d:Angle().y or 0)
            end)
        end
    end
    rmb = r
end)

-- 1-5 aggression, 6 global (the hotbar's slot keys, swallowed here);
-- Ctrl + wheel the area size.
Rhylib.Hook.Add("PlayerBindPress", "toolgun.command", function(ply, bind, pressed)
    if not pressed or not Tool.command or not toolOut() or not Rhylib.Droids then return end
    if input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) then
        local up = string.find(bind, "invprev", 1, true)
        local dn = string.find(bind, "invnext", 1, true)
        if up or dn then
            Tool.cmdRadius = math.Clamp(Tool.cmdRadius + (up and 50 or -50), 100, 2500)
            surface.PlaySound("buttons/lightswitch2.wav")
            return true
        end
    end
    local n = tonumber(string.match(bind, "^slot(%d+)$") or "")
    if not n or n > 6 then return end
    local lv = n <= 5 and n or 0
    send(OP.aggro, function() net.WriteUInt(lv, 3) end)
    return true
end, -35)

-- R held: the order wheel (rhylib_menus).
function Tool.CommandWheel(code)
    local M = Rhylib.Menus
    local W = M and M.Wheel
    if not (W and W.OpenList) then
        Rhylib.Notify(nil, "The order wheel needs Rhy's Menus", "bad", "Droids")
        return
    end
    local D = Rhylib.Droids
    local mode = function(i) return function() send(OP.mode, function() net.WriteUInt(i, 3) end) end end
    -- (orders for a place use where you aim as the wheel opens)
    local tr = LocalPlayer():GetEyeTrace()
    local at = tr.Hit and not tr.HitSky and tr.HitPos or nil
    local rad = Tool.cmdRadius
    local m = math.Round(rad * 0.019)
    local function atSpot(op, withR)
        return function()
            if not at then
                Rhylib.Notify(nil, "Aim at the ground for that order", "bad", "Droids")
                return
            end
            local side = selSide
            local ok = send(op, function()
                net.WriteVector(at)
                if withR then net.WriteUInt(rad, 12) end
            end)
            if ok and op == OP.assault and side then assaultAt[side] = at end
        end
    end
    local nr = #Tool.route
    W.OpenList("Orders (" .. #Tool.Selection() .. " selected)", {
        { label = "Hold", run = mode(1), sub = "Guard where they stand", col = Color(110, 170, 255) },
        { label = "Defend 360", run = atSpot(OP.defend, true), sub = m .. " m ring, cover facing out", col = Color(80, 140, 255) },
        { label = "Spread out", run = atSpot(OP.spread, true), sub = "Own spots over " .. m .. " m", col = Color(90, 200, 220) },
        { label = "Patrol", run = mode(2), sub = "Walk around where they are", col = Color(120, 230, 140) },
        { label = "Patrol area", run = atSpot(OP.area, true), sub = "Walk " .. m .. " m round there", col = Color(120, 230, 140) },
        { label = "Patrol route", col = Color(120, 230, 140),
          sub = nr >= 2 and ("Loop the " .. nr .. " points") or nil,
          disabled = nr < 2 and "Shift+RMB: 2+ points" or nil,
          run = function()
              local rt = Tool.route
              local ok = send(OP.route, function()
                  net.WriteUInt(#rt, 4)
                  for _, p in ipairs(rt) do net.WriteVector(p) end
              end)
              if ok then Tool.route = {} end
          end },
        { label = "Roam", run = mode(4), sub = "Wander the map in twos", col = Color(200, 140, 255) },
        { label = "Remove", run = function() send(OP.remove) sel, selSide = {}, nil end, sub = "Delete the selected NPCs", col = Color(255, 70, 60) },
        { label = "Split up", run = function() send(OP.split) end, sub = "Out of their squads" },
        { label = "Make one squad", run = function() send(OP.group) end, sub = "Up to " .. (D.Cfg("squadMax") or 16) .. " together" },
        { label = "Next formation", run = function() send(OP.formation) end, sub = "Box, wedge, line, column..." },
        { label = "Retreat", run = mode(5), sub = "Withdraw from the enemy", col = Color(255, 170, 60) },
        { label = "Hunt", run = mode(3), sub = "Hunt the nearest enemies", col = Color(255, 100, 80) },
        { label = "Assault here", run = atSpot(OP.assault), sub = "Attack that spot (waves)", col = COL_ASSAULT },
    }, code)
end

-- Outlines on the selection.
Rhylib.Hook.Add("PreDrawHalos", "toolgun.command", function()
    if not (Tool.command and toolOut()) then return end
    local list = Tool.Selection()
    if #list > 0 then halo.Add(list, COL_SEL, 2, 2, 1, true, false) end
end)

-- RMB held: where they go and the way they'll face. Also the route, the
-- assault point and (Ctrl held) the area ring.
local RING = Material("effects/select_ring")
local function circle(c, r, col)
    local seg, prev = 40, nil
    for i = 0, seg do
        local a = i / seg * math.pi * 2
        local p = c + Vector(math.cos(a) * r, math.sin(a) * r, 4)
        if prev then render.DrawLine(prev, p, col, true) end
        prev = p
    end
end
Rhylib.Hook.Add("PostDrawTranslucentRenderables", "toolgun.commandmarks", function(depth, sky)
    if depth or sky or not (Tool.command and toolOut()) then return end
    local rt = Tool.route
    render.SetMaterial(RING)
    for i, p in ipairs(rt) do
        render.DrawQuadEasy(p + Vector(0, 0, 3), Vector(0, 0, 1), 40, 40, COL_ROUTE, 0)
        local q = rt[i % #rt + 1]
        if #rt > 1 then render.DrawLine(p + Vector(0, 0, 6), q + Vector(0, 0, 6), COL_ROUTE, true) end
    end
    for side, p in pairs(assaultAt) do
        render.DrawQuadEasy(p + Vector(0, 0, 3), Vector(0, 0, 1), side == 2 and 90 or 70, side == 2 and 90 or 70,
            side == 2 and COL_ASSAULT or Color(90, 160, 255), 0)
    end
    if input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) then
        local tr = LocalPlayer():GetEyeTrace()
        if tr.Hit then circle(tr.HitPos, Tool.cmdRadius, COL) end
    end
end)
Rhylib.Hook.Add("PostDrawTranslucentRenderables", "toolgun.command", function(depth, sky)
    if depth or sky or not (Tool.command and toolOut() and rStart) then return end
    local tr = LocalPlayer():GetEyeTrace()
    local p = rStart.pos + Vector(0, 0, 3)
    render.SetMaterial(RING)
    render.DrawQuadEasy(p, Vector(0, 0, 1), 60, 60, rStart.ent and Color(255, 80, 70) or COL, 0)
    if not rStart.ent and tr.Hit then
        local q = tr.HitPos + Vector(0, 0, 3)
        local d = q - p
        d.z = 0
        if d:LengthSqr() > 64 * 64 then
            render.DrawLine(p, p + d, COL, false)
            local back = -d:GetNormalized() * 24
            local side = Vector(-back.y, back.x, 0) * 0.6
            render.DrawLine(p + d, p + d + back + side, COL, false)
            render.DrawLine(p + d, p + d + back - side, COL, false)
        end
    end
end)

-- HUD (cl_10_tool's DrawHUD calls this in Command mode).
function Tool.DrawCommandHUD()
    local list = Tool.Selection()
    local x, y = ScrW() * 0.5, ScrH() * 0.5 + 40
    local key = string.upper(cvKey:GetString())
    draw.SimpleTextOutlined("COMMAND MODE" .. (selSide and (selSide == 1 and "  ·  clones" or "  ·  droids") or ""), Rhylib.UI.Font(16, 700), x, y, COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    local squads, loose = {}, 0
    for _, e in ipairs(list) do
        local id = e:GetNW2Int("rhylib_squad", 0)
        if id > 0 then squads[id] = true else loose = loose + 1 end
    end
    local ns = table.Count(squads)
    local line = #list == 0 and "Nothing selected" or string.format("%d selected  ·  %d squad%s%s", #list, ns, ns == 1 and "" or "s", loose > 0 and ("  ·  " .. loose .. " loose") or "")
    draw.SimpleTextOutlined(line, Rhylib.UI.Font(14, 600), x, y + 22, COL_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    local f = Rhylib.UI.Font(13)
    draw.SimpleTextOutlined("LMB select (hold: sweep)  ·  Shift+LMB add  ·  RMB move (drag: facing)  ·  RMB enemy: attack", f, x, y + 42, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    draw.SimpleTextOutlined("1-5 aggression  ·  6 global  ·  hold R: orders  ·  " .. key .. ": back to placing", f, x, y + 58, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    draw.SimpleTextOutlined(string.format("Shift+RMB: route point (%d)  ·  Ctrl+wheel: area %d m", #Tool.route, math.Round(Tool.cmdRadius * 0.019)),
        f, x, y + 74, COL_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    -- (route point numbers)
    local nf = Rhylib.UI.Font(14, 800)
    for i, p in ipairs(Tool.route) do
        local sp = (p + Vector(0, 0, 20)):ToScreen()
        if sp.visible then draw.SimpleTextOutlined(tostring(i), nf, sp.x, sp.y, COL_ROUTE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black) end
    end
end

local function addSetting()
    local M = Rhylib.Menus
    if M and M.AddSetting then
        M.AddSetting("Weapons", { id = "toolgun.commandkey", order = 51, title = "Toolgun: Command mode", kind = "key", convar = "rhylib_tool_command_key",
            shareWith = { rhylib_shield_bash_key = true } })   -- (only with the toolgun out; the bash only with a shield)
    end
end
addSetting()
Rhylib.Hook.Add("InitPostEntity", "toolgun.commandsetting", addSetting)
