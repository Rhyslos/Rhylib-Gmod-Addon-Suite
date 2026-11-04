--[[
    Command post window (client; net logi.post from sv_20_post.lua). What
    shows depends on who you are (access 1 everyone, 2 field technician,
    3 officer): Respawn tickets and Garrison (stage 2), Logistics (nearby
    supplies), Sensor arrays (technicians and officers), Orders (officers,
    stage 2). Refresh asks again (logi.postreq). Esc or Close shuts it (UI
    closer "logistics.post").
]]

local L = Rhylib.Logistics

local function close()
    if IsValid(L.postPanel) then L.postPanel:Remove() return true end
    return false
end
local UI = Rhylib.UI
if UI and UI.RegisterCloser then UI.RegisterCloser("logistics.post", close) end

local ACCESS_NAMES = { "Trooper", "Field technician", "Officer" }

Rhylib.Net.Receive("logi.post", function()
    local post = net.ReadEntity()
    local access = net.ReadUInt(2)
    local len = net.ReadUInt(32)
    local data = util.JSONToTable(util.Decompress(net.ReadData(len) or "") or "") or {}
    local K = Rhylib.UI and Rhylib.UI.Kit
    if not K then return end
    local s = K.S
    close()
    local f = vgui.Create("EditablePanel")
    L.postPanel = f
    f:SetSize(s(760), s(620))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    f:DockPadding(s(16), s(56), s(16), s(14))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Command post", sub = "You see it as: " .. (ACCESS_NAMES[access] or "Trooper"), ticks = "all", header = s(40) })
    end
    local bar = vgui.Create("DPanel", f)
    bar.Paint = nil
    bar:Dock(BOTTOM)
    bar:SetTall(s(34))
    bar:DockMargin(0, s(8), 0, 0)
    local cb = K.Button(bar, "Close", function() close() end)
    cb:Dock(RIGHT)
    cb:SetWide(s(110))
    local rb = K.Button(bar, "Refresh", function()
        if not IsValid(post) then return end
        Rhylib.Net.Start("logi.postreq")
        net.WriteEntity(post)
        net.SendToServer()
    end, { accent = true })
    rb:Dock(RIGHT)
    rb:SetWide(s(110))
    rb:DockMargin(0, 0, s(8), 0)

    local sc = K.Scroll(f)
    sc:Dock(FILL)
    local function heading(t)
        local h = K.Heading(sc, t)
        h:Dock(TOP)
        h:DockMargin(0, s(6), s(8), s(4))
    end
    local function note(t)
        local l = K.Label(sc, t, 13, 400, K.C.textDim)
        l:Dock(TOP)
        l:DockMargin(0, 0, s(8), s(6))
    end
    local function row(title, desc, right)
        local r = K.Row(sc, title, desc)
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(3))
        if right then
            r.right:SetWide(s(200))
            local l = K.Label(r.right, right, 15, 700)
            l:Dock(FILL)
            l:SetContentAlignment(6)
        end
        return r
    end

    heading("Respawn tickets")
    note("Not set up yet (logistics stage 2).")
    heading("Garrison")
    note("Not set up yet (logistics stage 2).")

    heading("Logistics")
    local sup = data.supplies or {}
    if #sup == 0 then note("No supply crates, cabinets or armouries near this command post.") end
    for _, it in ipairs(sup) do
        row(it.name, it.kind .. " · " .. it.dist .. " m away", (it.left or -1) < 0 and "Unlimited" or (it.left .. " left"))
    end

    if access >= L.ACCESS_TECH then
        heading("Sensor arrays")
        local bs = data.beacons or {}
        if #bs == 0 then note("No sensor beacons out. Anyone with a sensor kit can set one down.") end
        for _, b in ipairs(bs) do
            local power = b.power > 0 and string.format("%d:%02d left", math.floor(b.power / 60), b.power % 60) or "no power"
            local ago = b.ago >= 0 and string.format(" · last alert %d s ago", b.ago) or ""
            row(b.label .. " (" .. b.owner .. ")", b.state .. " · " .. power .. " · " .. b.dist .. " m away" .. ago,
                b.count > 0 and (b.count .. " droid" .. (b.count == 1 and "" or "s")) or "Clear")
        end
    else
        heading("Sensor arrays")
        note("Field technicians and officers see the sensor arrays here.")
    end

    if access >= L.ACCESS_OFFICER then
        heading("Orders")
        note("Calling the garrison and supplies comes with logistics stage 2.")
    end
end)
