--[[
    Toolgun (client): what's chosen (client convars), its tab in the spawn
    window and the R key, the HUD line and the aim marker.
]]

local Tool = Rhylib.Tool

local cvEntry = CreateClientConVar("rhylib_tool_entry", "b1", true, false, "Toolgun: chosen entry id")
local cvCount = CreateClientConVar("rhylib_tool_count", "1", true, false, "Toolgun: how many droids at once (1-5)")
local cvName = CreateClientConVar("rhylib_tool_name", "Range", true, false, "Toolgun: name for new training beacons")

local cvMode = CreateClientConVar("rhylib_tool_droidmode", "1", true, false, "Toolgun: mode for placed droids (1 guard, 2 patrol, 3 attack)")
local cvCustom = CreateClientConVar("rhylib_tool_custom", "", true, false, "Toolgun: picked spawn-window thing (kind|name|skin|body|weapon|label)")

-- Spawn-window things picked with "Spawn with Rhy's toolgun": entry id
-- "@custom", the thing itself in rhylib_tool_custom.
Tool.KINDS = { prop = 1, entity = 2, npc = 3, vehicle = 4, weapon = 5 }
local customCache = {}
local function customEntry()
    local raw = cvCustom:GetString()
    if customCache.raw == raw then return customCache.e end
    local p = string.Explode("|", raw)
    local e
    if Tool.KINDS[p[1] or ""] and (p[2] or "") ~= "" then
        e = { id = "@custom", custom = { kind = p[1], name = p[2], skin = tonumber(p[3]) or 0, body = p[4] or "", wep = p[5] or "" },
            name = (p[6] ~= nil and p[6] ~= "") and p[6] or p[2] }
    end
    customCache.raw, customCache.e = raw, e
    return e
end

function Tool.Chosen()
    local id = cvEntry:GetString()
    if id == "@custom" then
        local c = customEntry()
        if c then return c end
    end
    for _, e in ipairs(Tool.Entries()) do
        if e.id == id then return e end
    end
    return Tool.Entries()[1]
end

-- The "Rhylib" tab of the spawn window (rhylib_menus cl_85_spawn.lua):
-- our placements as tiles by category, plus count, beacon name and save.
local function buildTab(body)
    local M = Rhylib.Menus
    local K, SP = M.Kit, M.Spawn
    local S = K.S

    local bottom = vgui.Create("DPanel", body)
    bottom:Dock(BOTTOM)
    bottom:SetTall(S(40))
    bottom:DockMargin(0, S(8), 0, 0)
    function bottom:Paint(w, h)
        surface.SetDrawColor(K.C.row)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(K.C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    bottom:DockPadding(S(8), S(4), S(8), S(4))
    local lbl = K.Label(bottom, "Droids at once", 13, 700, K.C.textDim)
    lbl:Dock(LEFT)
    lbl:SetWide(S(110))
    lbl:SetAutoStretchVertical(false)
    lbl:SetContentAlignment(4)
    for _, n in ipairs({ 1, 3, 5 }) do
        local b = K.Button(bottom, tostring(n), function() RunConsoleCommand("rhylib_tool_count", tostring(n)) end,
            { small = true, selected = function() return cvCount:GetInt() == n end })
        b:Dock(LEFT)
        b:SetWide(S(42))
        b:DockMargin(0, S(2), S(6), S(2))
    end
    local lbl2 = K.Label(bottom, "Beacon name", 13, 700, K.C.textDim)
    lbl2:Dock(LEFT)
    lbl2:SetWide(S(110))
    lbl2:DockMargin(S(18), 0, 0, 0)
    lbl2:SetAutoStretchVertical(false)
    lbl2:SetContentAlignment(4)
    local te = K.TextEntry(bottom, "e.g. Range, Killhouse A")
    te:Dock(LEFT)
    te:SetWide(S(240))
    te:SetValue(cvName:GetString())
    te.OnChange = function(self) RunConsoleCommand("rhylib_tool_name", string.sub(self:GetValue(), 1, 32)) end
    local save = K.Button(bottom, "Save all placements", function()
        Rhylib.Net.Start("tool.save")
        net.SendToServer()
    end, { tooltip = "Fixtures save by themselves when placed or removed; this saves everything on the map again." })
    save:Dock(RIGHT)
    save:SetWide(S(220))

    -- (only with rhylib_droids: its buttons send droid messages)
    if Rhylib.Droids then
        -- Second row: the mode placed droids get, and the live aggression.
        local row2 = vgui.Create("DPanel", body)
        row2:Dock(BOTTOM)
        row2:SetTall(S(40))
        row2:DockMargin(0, S(8), 0, 0)
        row2.Paint = bottom.Paint
        row2:DockPadding(S(8), S(4), S(8), S(4))
        local lm = K.Label(row2, "New droids", 13, 700, K.C.textDim)
        lm:Dock(LEFT)
        lm:SetWide(S(110))
        lm:SetAutoStretchVertical(false)
        lm:SetContentAlignment(4)
        for i, m in ipairs({ "Guard", "Patrol", "Attack" }) do
            local b = K.Button(row2, m, function() RunConsoleCommand("rhylib_tool_droidmode", tostring(i)) end,
                { small = true, selected = function() return cvMode:GetInt() == i end,
                  tooltip = "Mode of the droids you place (markers you placed earlier still win)" })
            b:Dock(LEFT)
            b:SetWide(S(72))
            b:DockMargin(0, S(2), S(6), S(2))
        end
        local la = K.Label(row2, "Aggression", 13, 700, K.C.textDim)
        la:Dock(LEFT)
        la:SetWide(S(100))
        la:DockMargin(S(18), 0, 0, 0)
        la:SetAutoStretchVertical(false)
        la:SetContentAlignment(4)
        local AGGRO = { "Fall back", "Retreat", "Moderate", "March", "Charge" }
        for i = 1, 5 do
            local b = K.Button(row2, i .. " " .. AGGRO[i], function()
                Rhylib.Net.Start("droids.aggro")
                net.WriteUInt(i, 3)
                net.SendToServer()
            end, { small = true, selected = function() return GetGlobal2Int("rhylib_droidAggro", 3) == i end,
                   tooltip = "Every droid at once, live: 1 falls back while firing ... 5 charges" })
            b:Dock(LEFT)
            b:SetWide(S(96))
            b:DockMargin(0, S(2), S(6), S(2))
        end
    end

    local inner = vgui.Create("DPanel", body)
    inner:Dock(FILL)
    inner.Paint = nil
    local tab = SP.CatalogueTab(function()
        local items = {}
        local ents = list.Get("SpawnableEntities") or {}
        for _, e in ipairs(Tool.Entries()) do
            local sp = e.class and ents[e.class] or {}
            items[#items + 1] = {
                cat = e.cat, name = e.name, extra = e.class or e.id,
                tip = e.order and "Click: pick it; LMB sets the mode of every NPC of that side near where you aim"
                    or e.follow and "LMB: pick a clone (or all near the spot); RMB: they follow you, or the player you aim at"
                    or e.preset and "LMB: places the whole squad in a grid facing you (front row where you aim, commander and B2s at the back)"
                    or (e.class .. "\nClick: pick it for the toolgun (LMB places)"),
                mat = SP.IconMat({ sp.IconOverride, "entities/" .. (e.class or e.id) .. ".png" }),
                model = Tool.EntryModel(e),   -- (3D tile picture and hover preview)
                selected = function() return cvEntry:GetString() == e.id end,
                run = function()
                    RunConsoleCommand("rhylib_tool_entry", e.id)
                    -- (back to the toolgun if something else is out)
                    local me = LocalPlayer()
                    local w = me:GetActiveWeapon()
                    local tg = me:GetWeapon("rhylib_toolgun")
                    if IsValid(tg) and w ~= tg then input.SelectWeapon(tg) end
                end,
            }
        end
        return items
    end, Tool.CAT_ORDER)
    tab.build(inner)
    body.search = inner.search
end

-- Right-click "Spawn with Rhy's toolgun" in the spawn window.
local function pickForTool(spec)
    local clean = function(v) return (string.gsub(tostring(v or ""), "|", "/")) end
    -- (an NPC's weapon is picked per spawn, in Tool.Click)
    local wep = spec.wep or ""
    RunConsoleCommand("rhylib_tool_custom", table.concat({ clean(spec.kind), clean(spec.name), tostring(tonumber(spec.skin) or 0),
        clean(spec.body), clean(wep), string.sub(clean(spec.label or spec.name), 1, 48) }, "|"))
    RunConsoleCommand("rhylib_tool_entry", "@custom")
    local me = LocalPlayer()
    local tg = me:GetWeapon("rhylib_toolgun")
    if IsValid(tg) then
        if me:GetActiveWeapon() ~= tg then input.SelectWeapon(tg) end
        chat.AddText(Color(255, 210, 80), "[Toolgun] ", color_white, "LMB spawns " .. (spec.label or spec.name) .. " where you aim.")
    else
        chat.AddText(Color(255, 210, 80), "[Toolgun] ", color_white, "Picked " .. (spec.label or spec.name) .. ". Get the toolgun with !toolgun to spawn it.")
    end
end

local function addTab()
    local M = Rhylib.Menus
    if not (M and M.Spawn and M.Spawn.AddTab) then return end
    M.Spawn.PickForTool = pickForTool
    M.Spawn.AddTab("rhylib", {
        title = "Rhylib", order = 0,
        build = buildTab,
        search = function(body, q) if body.search then body.search(q) end end,
    })
end
addTab()
Rhylib.Hook.Add("InitPostEntity", "toolgun.spawntab", addTab)

-- R with the toolgun out: a tap opens the spawn window (and leaves it
-- open), holding R keeps it open only while held, a second tap closes it,
-- and two quick taps open the old Q menu instead.
local HOLD = 0.3
local DOUBLE = 0.35
local rPress, lastOpen = nil, 0

local function reloadCode()
    local key = input.LookupBinding("+reload")
    local c = key and input.GetKeyCode(key)
    return (c and c > 0) and c or KEY_R
end

local function onR(code)
    local M = Rhylib.Menus
    local SP = M and M.Spawn
    if not SP then
        chat.AddText(Color(255, 200, 80), "[Toolgun] needs rhylib_menus for the spawn window. rhylib_tool_entry <id> picks one.")
        return
    end
    local now = RealTime()
    if M.SpawnMenuOpen and M.SpawnMenuOpen() then
        M.CloseSpawnMenu()
        return
    end
    if SP.IsOpen() then
        SP.Close()
        rPress = nil
        if now - lastOpen < DOUBLE and M.OpenSpawnMenu then M.OpenSpawnMenu() end
        lastOpen = 0
        return
    end
    SP.Open()
    lastOpen = now
    rPress = { at = now, code = code or reloadCode() }
end

Rhylib.Hook.Add("PlayerBindPress", "toolgun.r", function(ply, bind, pressed, code)
    if not pressed or bind ~= "+reload" then return end
    -- (R turns items in the open inventory)
    local Inv = Rhylib.Inventory
    if Inv and IsValid(Inv.panel) then return end
    local w = ply:GetActiveWeapon()
    local SP = Rhylib.Menus and Rhylib.Menus.Spawn
    -- (also while the window is open with another tool out)
    if not ((IsValid(w) and w.ToolGun) or (SP and SP.IsOpen())) then return end
    onR(code)
    return true
end, -30)

-- Held past HOLD: letting go closes it again (like holding Q).
Rhylib.Hook.Add("Think", "toolgun.rhold", function()
    if not rPress then return end
    if input.IsButtonDown(rPress.code) then return end
    local held = RealTime() - rPress.at
    rPress = nil
    if held >= HOLD then
        local SP = Rhylib.Menus and Rhylib.Menus.Spawn
        if SP then SP.Close() end
        lastOpen = 0
    end
end)

function Tool.Click(wep, which)
    if which == "3" then return end   -- (R is read from the key, above)
    if which == "2" then
        local f = Tool.Chosen()
        Rhylib.Net.Start(f and f.follow and "tool.follow" or "tool.remove")
        net.SendToServer()
        return
    end
    local e = Tool.Chosen()
    if not e then return end
    if e.custom then
        local c = e.custom
        local wep = c.wep
        if c.kind == "npc" and wep == "" then
            local SP = Rhylib.Menus and Rhylib.Menus.Spawn
            wep = (SP and SP.NpcWeapon) and SP.NpcWeapon((list.Get("NPC") or {})[c.name]) or ""
        end
        Rhylib.Net.Start("tool.spawn")
        net.WriteUInt(Tool.KINDS[c.kind], 3)
        net.WriteString(c.name)
        net.WriteUInt(math.Clamp(c.skin, 0, 63), 6)
        net.WriteString(c.body)
        net.WriteString(wep)
        net.SendToServer()
        return
    end
    Rhylib.Net.Start("tool.place")
    net.WriteString(e.id)
    net.WriteUInt(math.Clamp(cvCount:GetInt(), 1, 5), 3)
    net.WriteString(e.named and cvName:GetString() or "")
    net.WriteUInt(math.Clamp(cvMode:GetInt(), 1, 3), 2)
    net.SendToServer()
end

local COL = Color(255, 210, 80)
local COL_RED = Color(255, 90, 80)

function Tool.DrawHUD(wep)
    local e = Tool.Chosen()
    if not e then return end
    local ply = LocalPlayer()
    local tr = ply:GetEyeTrace()
    local text = e.order and e.name or ((e.custom and "Spawn: " or "Place: ") .. e.name)
    if e.count and cvCount:GetInt() > 1 then text = text .. " ×" .. cvCount:GetInt() end
    if e.count and not e.custom then text = text .. "  ·  " .. ({ "Guard", "Patrol", "Attack" })[math.Clamp(cvMode:GetInt(), 1, 3)] end
    local D = Rhylib.Droids
    if D and D.AGGRO_NAMES then
        local a = D.Aggro()
        draw.SimpleTextOutlined("Droid aggression " .. a .. ": " .. D.AGGRO_NAMES[a], Rhylib.UI.Font(13), ScrW() * 0.5, ScrH() * 0.5 + 102, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    end
    if e.named then text = text .. "  \"" .. cvName:GetString() .. "\"" end
    local y = ScrH() * 0.5 + 40
    draw.SimpleTextOutlined(text, Rhylib.UI.Font(16, 700), ScrW() * 0.5, y, COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    local ent = tr.Entity
    if IsValid(ent) and not ent:IsPlayer() and (ent.IsRhylibDroid or ent.IsRhylibClone or Tool.ByClass(ent:GetClass()) or ent:GetNW2Bool("rhylib_toolSpawned")) then
        draw.SimpleTextOutlined("RMB: remove " .. (ent.PrintName or ent:GetClass()), Rhylib.UI.Font(14, 700), ScrW() * 0.5, y + 22, COL_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    end
    draw.SimpleTextOutlined("R: spawn window  ·  hold R: peek  ·  R twice: old Q menu", Rhylib.UI.Font(13), ScrW() * 0.5, y + 42, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
end

-- Where it will go: a ring on the aimed surface.
local RING = Material("effects/select_ring")
Rhylib.Hook.Add("PostDrawTranslucentRenderables", "toolgun.aim", function(depth, sky)
    if depth or sky then return end
    local ply = LocalPlayer()
    local w = IsValid(ply) and ply:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == "rhylib_toolgun") then return end
    local tr = ply:GetEyeTrace()
    if not tr.Hit or tr.HitSky then return end
    render.SetMaterial(RING)
    render.DrawQuadEasy(tr.HitPos + tr.HitNormal * 1.5, tr.HitNormal, 40, 40, COL, 0)
    -- An order brush: the area it reaches.
    local e = Tool.Chosen()
    local D = Rhylib.Droids
    if e and (e.order or e.follow) and D then
        local r = D.Cfg("brushRadius") or 400
        render.DrawQuadEasy(tr.HitPos + tr.HitNormal * 2, tr.HitNormal, r * 2, r * 2, ColorAlpha(COL, 90), 0)
    end
end)

-- With the toolgun out: each droid's mode over its head (staff only see
-- this, since only they hold the toolgun).
local MODE_COL = { guard = Color(110, 170, 255), patrol = Color(120, 230, 140), attack = Color(255, 100, 80), follow = Color(240, 220, 120), roam = Color(200, 140, 255) }
local PICKED = Color(255, 255, 120)
local droidList, droidListAt = {}, 0
Rhylib.Hook.Add("HUDPaint", "toolgun.droidmodes", function()
    local ply = LocalPlayer()
    local w = IsValid(ply) and ply:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == "rhylib_toolgun") then return end
    local now = RealTime()
    if now > droidListAt then
        droidListAt = now + 0.5
        droidList = {}
        for _, e in ipairs(ents.GetAll()) do
            if e.IsRhylibDroid or e.IsRhylibClone then droidList[#droidList + 1] = e end
        end
    end
    local eye = EyePos()
    local font = Rhylib.UI.Font(13, 700)
    for _, d in ipairs(droidList) do
        if IsValid(d) and d:GetPos():DistToSqr(eye) < 2000 * 2000 then
            local mode = d:GetNW2String("rhylib_dmode", "guard")
            local sp = (d:GetPos() + Vector(0, 0, 90)):ToScreen()
            if sp.visible then
                draw.SimpleTextOutlined(string.upper(mode), font, sp.x, sp.y, MODE_COL[mode] or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
                -- (picked with the follow tool)
                if d:GetNW2Entity("rhylib_pickBy") == ply then
                    draw.SimpleTextOutlined("PICKED", font, sp.x, sp.y - 14, PICKED, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
                end
            end
        end
    end
end)

-- Console: rhylib_toolgun (the server checks the permission).
concommand.Add("rhylib_toolgun", function()
    Rhylib.Net.Start("tool.give")
    net.SendToServer()
end)
