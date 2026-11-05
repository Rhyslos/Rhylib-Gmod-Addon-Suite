--[[
    Command post window (client; net logi.post from sv_20_post.lua). What
    shows depends on who you are (access 1 everyone, 2 field technician,
    3 officer): Respawn tickets (rhylib_spawns' shared pool), Garrison
    tickets, Logistics (nearby supplies and the armoury stock running
    low), Sensor arrays (technicians and officers), Orders (officers: the
    call-ins, each a button with its cooldown; net logi.call: Entity post,
    UInt 3 call index). Refresh asks again (logi.postreq). Esc or Close
    shuts it (UI closer "logistics.post").
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
    local SP = Rhylib.Spawns
    if SP and SP.TicketsOn and SP.TicketsOn() then
        row("Shared pool", "each respawn after a death uses one", SP.Tickets() .. " left")
    elseif SP and SP.TicketsOn then
        note("Not in use: respawning as normal (staff switch them on for events: !tickets on).")
    else
        note("Not available (needs Rhy's Spawn Points).")
    end
    heading("Garrison")
    if L.GarrisonOn() then
        local gr = row("Garrison tickets", "officers spend one per clone they call in", "")
        local gl = gr.right:GetChildren()[1]
        function gr:Think() if IsValid(gl) then gl:SetText(L.Garrison() .. " left") end end
    else
        note("Not in use: clone squads can be called in freely (staff switch them on for events: !garrison on).")
    end

    heading("Logistics")
    local sup = data.supplies or {}
    if #sup == 0 then note("No supply crates, cabinets or armouries near this command post.") end
    for _, it in ipairs(sup) do
        local left = it.left or -1
        row(it.name, it.kind .. " · " .. it.dist .. " m away", left == -2 and "Armoury stock" or (left < 0 and "Unlimited" or (left .. " left")))
    end
    if data.stock then
        heading("Armoury stock")
        if #data.stock == 0 then note("Every armoury item is above 60%. All armouries on the map share one stock.") end
        for _, it in ipairs(data.stock) do
            row(it.name, it.left == 0 and "out: comes back with a resupply crate" or "shared by every armoury", it.left .. " / " .. it.max)
        end
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
        note("Called in things arrive here after " .. math.Round(L.Cfg("callDelay")) .. " s. A clone squad falls in on you.")
        local DESC = {
            squad = function()
                local n = istable(L.Cfg("callSquad")) and #L.Cfg("callSquad") or 0
                return n .. " clones" .. (L.GarrisonOn() and (" · " .. n .. " garrison tickets") or "")
            end,
            supply = function() return "carry it to an armoury: puts back " .. math.Round(L.Cfg("resupplyAmount") * 100) .. "% of the stock" end,
            ammo = function() return "ammo crates by the post" end,
            medical = function() return "a medical crate by the post" end,
        }
        for _, c in ipairs(L.CALLS) do
            local r = K.Row(sc, c.title, DESC[c.id] and DESC[c.id]() or "")
            r:Dock(TOP)
            r:DockMargin(0, 0, s(8), s(3))
            r.right:SetWide(s(200))
            local b = K.Button(r.right, "Call in", function()
                if not IsValid(post) or L.CallReady(c.id) > 0 then return end
                Rhylib.Net.Start("logi.call")
                net.WriteEntity(post)
                net.WriteUInt(c.index, 3)
                net.SendToServer()
            end, { accent = true, enabled = function() return L.CallReady(c.id) <= 0 end })
            b.label = function()
                local cd = math.ceil(L.CallReady(c.id))
                return cd > 0 and string.format("Ready in %d:%02d", math.floor(cd / 60), cd % 60) or "Call in"
            end
            b:Dock(FILL)
            b:DockMargin(0, s(3), 0, s(3))
        end
    end
end)
