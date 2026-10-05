--[[
    Toolgun (client): what's chosen (client convars), the R list, the HUD
    line and the aim marker.
]]

local Tool = Rhylib.Tool

local cvEntry = CreateClientConVar("rhylib_tool_entry", "b1", true, false, "Toolgun: chosen entry id")
local cvCount = CreateClientConVar("rhylib_tool_count", "1", true, false, "Toolgun: how many droids at once (1-5)")
local cvName = CreateClientConVar("rhylib_tool_name", "Range", true, false, "Toolgun: name for new training beacons")

function Tool.Chosen()
    local id = cvEntry:GetString()
    for _, e in ipairs(Tool.Entries()) do
        if e.id == id then return e end
    end
    return Tool.Entries()[1]
end

local win

local function openMenu()
    local M = Rhylib.Menus
    local K = M and M.Kit
    if not K then
        chat.AddText(Color(255, 200, 80), "[Toolgun] needs rhylib_menus for its list. rhylib_tool_entry <id> picks one.")
        return
    end
    if IsValid(win) then win:Remove() return end
    local S = K.S
    local f = vgui.Create("EditablePanel")
    win = f
    f:SetSize(S(560), math.min(S(720), ScrH() - S(80)))
    f:Center()
    f:MakePopup()
    if M.prompts then
        M.prompts[f] = true
        f.OnRemove = function(self) M.prompts[self] = nil end
    end
    f:DockPadding(S(12), S(46), S(12), S(12))
    function f:Paint(w, h) K.Plate(0, 0, w, h, { title = "Toolgun", sub = "LMB place · RMB remove · Esc close", ticks = "all", header = S(34) }) end

    -- Bottom: count, beacon name, save, close.
    local bottom = vgui.Create("DPanel", f)
    bottom:Dock(BOTTOM)
    bottom:SetTall(S(112))
    bottom:DockMargin(0, S(8), 0, 0)
    bottom.Paint = nil

    local row1 = vgui.Create("DPanel", bottom)
    row1:Dock(TOP)
    row1:SetTall(S(34))
    row1.Paint = nil
    local lbl = K.Label(row1, "Droids at once", 13, 700, K.C.textDim)
    lbl:Dock(LEFT)
    lbl:SetWide(S(120))
    lbl:SetAutoStretchVertical(false)
    lbl:SetContentAlignment(4)
    for _, n in ipairs({ 1, 3, 5 }) do
        local b = K.Button(row1, tostring(n), function() RunConsoleCommand("rhylib_tool_count", tostring(n)) end,
            { small = true, selected = function() return cvCount:GetInt() == n end })
        b:Dock(LEFT)
        b:SetWide(S(48))
        b:DockMargin(0, S(4), S(6), S(4))
    end

    local row2 = vgui.Create("DPanel", bottom)
    row2:Dock(TOP)
    row2:SetTall(S(34))
    row2:DockMargin(0, S(4), 0, 0)
    row2.Paint = nil
    local lbl2 = K.Label(row2, "Beacon name", 13, 700, K.C.textDim)
    lbl2:Dock(LEFT)
    lbl2:SetWide(S(120))
    lbl2:SetAutoStretchVertical(false)
    lbl2:SetContentAlignment(4)
    local te = K.TextEntry(row2, "e.g. Range, Killhouse A")
    te:Dock(FILL)
    te:SetValue(cvName:GetString())
    te.OnChange = function(self) RunConsoleCommand("rhylib_tool_name", string.sub(self:GetValue(), 1, 32)) end

    local row3 = vgui.Create("DPanel", bottom)
    row3:Dock(TOP)
    row3:SetTall(S(34))
    row3:DockMargin(0, S(6), 0, 0)
    row3.Paint = nil
    local save = K.Button(row3, "Save all placements", function()
        Rhylib.Net.Start("tool.save")
        net.SendToServer()
    end, { tooltip = "Fixtures save by themselves when placed or removed; this saves everything on the map again." })
    save:Dock(LEFT)
    save:SetWide(S(250))
    local close = K.Button(row3, "Close", function() f:Remove() end, { danger = true })
    close:Dock(RIGHT)
    close:SetWide(S(120))

    -- The list, by category.
    local sc = K.Scroll(f)
    sc:Dock(FILL)
    local cats, order = {}, {}
    for _, e in ipairs(Tool.Entries()) do
        if not cats[e.cat] then
            cats[e.cat] = {}
            order[#order + 1] = e.cat
        end
        table.insert(cats[e.cat], e)
    end
    for _, cat in ipairs(order) do
        local h = K.Heading(sc, cat)
        h:Dock(TOP)
        for _, e in ipairs(cats[cat]) do
            local b = K.Button(sc, e.name, function() RunConsoleCommand("rhylib_tool_entry", e.id) end,
                { align = "left", small = true, selected = function() return cvEntry:GetString() == e.id end })
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, S(3))
        end
    end
end

-- R: a tap opens our list; holding it opens a wheel (spawn menu or our
-- list; the Q key no longer opens the spawn menu, rhylib_menus).
local HOLD = 0.25
local rPress

local function reloadCode()
    local key = input.LookupBinding("+reload")
    local c = key and input.GetKeyCode(key)
    return (c and c > 0) and c or KEY_R
end

Rhylib.Hook.Add("Think", "tool.rhold", function()
    if not rPress then return end
    -- (only while the toolgun is out and nothing else has the mouse)
    local w = LocalPlayer():GetActiveWeapon()
    if not (IsValid(w) and w.ToolGun) or vgui.CursorVisible() then
        rPress = nil
        return
    end
    local M = Rhylib.Menus
    local W = M and M.Wheel
    if not input.IsButtonDown(rPress.code) then
        rPress = nil
        openMenu()
        return
    end
    if RealTime() - rPress.at < HOLD then return end
    local code = rPress.code
    rPress = nil
    if not (W and W.OpenList) then return openMenu() end
    W.OpenList("Toolgun", {
        { label = "Spawn menu", sub = "The Q menu", run = function()
            if M.OpenSpawnMenu then M.OpenSpawnMenu() end
        end },
        { label = "Rhylib tools", sub = "Placement list", run = openMenu },
    }, code)
end)

function Tool.Click(wep, which)
    if which == "3" then
        local W = Rhylib.Menus and Rhylib.Menus.Wheel
        if rPress or (W and W.open) then return end
        rPress = { at = RealTime(), code = reloadCode() }
        return
    end
    if which == "2" then
        Rhylib.Net.Start("tool.remove")
        net.SendToServer()
        return
    end
    local e = Tool.Chosen()
    if not e then return end
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
    local text = "Place: " .. e.name
    if e.count and cvCount:GetInt() > 1 then text = text .. " ×" .. cvCount:GetInt() end
    if e.named then text = text .. "  \"" .. cvName:GetString() .. "\"" end
    local y = ScrH() * 0.5 + 40
    draw.SimpleTextOutlined(text, Rhylib.UI.Font(16, 700), ScrW() * 0.5, y, COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    local ent = tr.Entity
    if IsValid(ent) and not ent:IsPlayer() and (ent.IsRhylibDroid or Tool.ByClass(ent:GetClass())) then
        draw.SimpleTextOutlined("RMB: remove " .. (ent.PrintName or ent:GetClass()), Rhylib.UI.Font(14, 700), ScrW() * 0.5, y + 22, COL_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    end
    draw.SimpleTextOutlined("R: list  ·  hold R: spawn menu", Rhylib.UI.Font(13), ScrW() * 0.5, y + 42, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
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
