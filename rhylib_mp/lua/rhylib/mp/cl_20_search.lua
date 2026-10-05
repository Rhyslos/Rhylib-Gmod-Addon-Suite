--[[
    Search window: the searched player's items (main grid, backpack, back
    slot). "Take" buttons only while they're cuffed. Closes when the server
    says the search ended (out of range, baton put away, ...).
]]

local MP = Rhylib.MP

local CONT_NAMES = { [1] = "Carried", [2] = "Backpack", [3] = "Back slot", [5] = "Cell rack", [6] = "Ammo belt", [7] = "Holster" }
for i = 8, 17 do CONT_NAMES[i] = "Worn gear" end
CONT_NAMES[18] = "Belt pouches"
CONT_NAMES[19] = "Cell pouch"

function MP.OpenSearch(target)
    Rhylib.Net.Start("mp.search")
    net.WriteEntity(target)
    net.SendToServer()
end

local function close()
    if IsValid(MP.searchPanel) then MP.searchPanel:Remove() end
end

Rhylib.Net.Receive("mp.list", function()
    local target = net.ReadEntity()
    local cuffed = net.ReadBool()
    local n = net.ReadUInt(8)
    local Items = Rhylib.Items
    local rows = {}
    for i = 1, n do
        local uid = net.ReadUInt(Items.UID_BITS)
        local def = Items.FromNet(net.ReadUInt(Items.NET_BITS))
        local count = net.ReadUInt(8)
        local fill = net.ReadUInt(7)
        local c = net.ReadUInt(Items.CONT_BITS)
        rows[i] = { uid = uid, def = def, count = count, fill = fill, c = c }
    end
    if not IsValid(target) then close() return end
    MP.ShowSearch(target, cuffed, rows)
end)

function MP.ShowSearch(target, cuffed, rows)
    local K = Rhylib.Menus and Rhylib.Menus.Kit
    if not K then return end
    local s = K.S
    local f = MP.searchPanel
    if not IsValid(f) then
        f = vgui.Create("EditablePanel")
        f:SetSize(s(460), s(560))
        f:Center()
        f:MakePopup()
        f:SetKeyboardInputEnabled(false)
        f:DockPadding(s(14), s(52), s(14), s(14))
        function f:OnRemove()
            Rhylib.Net.Start("mp.search")
            net.WriteEntity(NULL)
            net.SendToServer()
        end
        MP.searchPanel = f
        local closeBtn = K.Button(f, "Close", function() f:Remove() end, { small = true })
        closeBtn:Dock(BOTTOM)
        closeBtn:DockMargin(0, s(10), 0, 0)
        f.scroll = K.Scroll(f)
        f.scroll:Dock(FILL)
        if Rhylib.Menus.RegisterCloser then
            Rhylib.Menus.RegisterCloser("mp.search", function()
                if IsValid(MP.searchPanel) then MP.searchPanel:Remove() return true end
                return false
            end)
        end
    end
    f.target, f.cuffed = target, cuffed
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Search · " .. (IsValid(self.target) and self.target:Nick() or "?"),
            sub = self.cuffed and "Cuffed: you can take items" or "Look only (not cuffed)", ticks = "all", header = s(38) })
    end
    local sp = f.scroll
    sp:Clear()
    if #rows == 0 then
        local l = K.Label(sp, "They carry nothing.", 14, 400, K.C.textDim)
        l:Dock(TOP)
        return
    end
    local lastC
    for _, r in ipairs(rows) do
        local head = CONT_NAMES[r.c] or "Other"
        if head ~= lastC then
            lastC = head
            local h = K.Heading(sp, head)
            h:Dock(TOP)
            h:DockMargin(0, s(4), s(8), s(4))
        end
        local name = r.def and r.def.name or "Unknown item"
        local sub = r.count > 1 and ("x" .. r.count) or ""
        if r.def and r.def.fill and r.def.rounds then sub = math.floor(r.fill / 100 * r.def.rounds + 0.5) .. " / " .. r.def.rounds end
        local row = K.Row(sp, name, sub ~= "" and sub or nil)
        row:Dock(TOP)
        row:DockMargin(0, 0, s(8), s(3))
        row.right:SetWide(s(100))
        if cuffed then
            local uid = r.uid
            local b = K.Button(row.right, "Take", function()
                Rhylib.Net.Start("mp.take")
                net.WriteEntity(target)
                net.WriteUInt(uid, Rhylib.Items.UID_BITS)
                net.SendToServer()
            end, { small = true, accent = true })
            b:Dock(FILL)
        end
    end
end

--------------------------------------------------------------------------
-- Interaction wheel (rhylib_menus)
--------------------------------------------------------------------------

local function wheelOp(op, t)
    Rhylib.Net.Start("mp.wheel")
    net.WriteUInt(op, 2)
    net.WriteEntity(t)
    net.SendToServer()
end

Rhylib.Hook.Add("Rhylib.WheelOptions", "mp.wheel", function(t, me, add)
    if not MP.IsMP(me) then return end
    add("Search", function(x) MP.OpenSearch(x) end, { order = 30, sub = "Look through their gear" })
    if MP.IsCuffed(t) then
        add("Uncuff", function(x) wheelOp(1, x) end, { order = 32 })
        add(MP.EscortedBy(t) == me and "Let go" or "Escort", function(x) wheelOp(2, x) end, { order = 33 })
    elseif not me:HasWeapon("rhylib_handcuffs") then
        add("Cuff", nil, { order = 31, disabled = "No handcuffs" })
    elseif not (MP.IsStunned(t) or (Rhylib.Medical and Rhylib.Medical.IsDown and Rhylib.Medical.IsDown(t))) then
        add("Cuff", nil, { order = 31, disabled = "Stun them first" })
    else
        add("Cuff", function(x)
            wheelOp(0, x)
            local Menus = Rhylib.Menus
            if Menus and Menus.WheelProgress then Menus.WheelProgress("Cuffing " .. x:Nick(), MP.Cfg("cuffTime")) end
        end, { order = 31, sub = "Stay close" })
    end
end)

net.Receive(Rhylib.Net.Name("mp.wheelx"), function()
    local Menus = Rhylib.Menus
    if Menus and Menus.WheelProgressStop then Menus.WheelProgressStop() end
end)
