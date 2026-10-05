--[[
    Toolgun (client): what's chosen (client convars), its tab in the spawn
    window and the R key, the HUD line and the aim marker.
]]

local Tool = Rhylib.Tool

local cvEntry = CreateClientConVar("rhylib_tool_entry", "b1", true, false, "Toolgun: chosen entry id")
local cvCount = CreateClientConVar("rhylib_tool_count", "1", true, false, "Toolgun: how many droids at once (1-5)")
local cvName = CreateClientConVar("rhylib_tool_name", "Range", true, false, "Toolgun: name for new training beacons")

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

    local inner = vgui.Create("DPanel", body)
    inner:Dock(FILL)
    inner.Paint = nil
    local tab = SP.CatalogueTab(function()
        local items = {}
        local ents = list.Get("SpawnableEntities") or {}
        for _, e in ipairs(Tool.Entries()) do
            local sp = ents[e.class] or {}
            items[#items + 1] = {
                cat = e.cat, name = e.name, extra = e.class, tip = e.class .. "\nClick: pick it for the toolgun (LMB places)",
                mat = SP.IconMat({ sp.IconOverride, "entities/" .. e.class .. ".png" }),
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
        Rhylib.Net.Start("tool.remove")
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
    net.SendToServer()
end

local COL = Color(255, 210, 80)
local COL_RED = Color(255, 90, 80)

function Tool.DrawHUD(wep)
    local e = Tool.Chosen()
    if not e then return end
    local ply = LocalPlayer()
    local tr = ply:GetEyeTrace()
    local text = (e.custom and "Spawn: " or "Place: ") .. e.name
    if e.count and cvCount:GetInt() > 1 then text = text .. " ×" .. cvCount:GetInt() end
    if e.named then text = text .. "  \"" .. cvName:GetString() .. "\"" end
    local y = ScrH() * 0.5 + 40
    draw.SimpleTextOutlined(text, Rhylib.UI.Font(16, 700), ScrW() * 0.5, y, COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    local ent = tr.Entity
    if IsValid(ent) and not ent:IsPlayer() and (ent.IsRhylibDroid or Tool.ByClass(ent:GetClass()) or ent:GetNW2Bool("rhylib_toolSpawned")) then
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
end)

-- Console: rhylib_toolgun (the server checks the permission).
concommand.Add("rhylib_toolgun", function()
    Rhylib.Net.Start("tool.give")
    net.SendToServer()
end)
