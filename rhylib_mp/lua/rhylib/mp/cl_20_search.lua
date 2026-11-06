--[[
    Search window: the searched player's items (main grid, backpack, back
    slot). "Take" buttons only while they're cuffed. Closes when the server
    says the search ended (out of range, baton put away, ...).
    Look: the header plate (SEARCH · name) with a chip under it (green
    CUFFED · YOU CAN TAKE ITEMS, or amber LOOK ONLY · NOT CUFFED), then one
    band per place (Carried, Backpack, Worn gear...: diamond, caps name,
    item count) over rows alternating, each with its kind's colour strip
    (the inventory's), the name, the count or rounds right-aligned and
    Take. Nothing carried: a dashed box.
    Client only. Needs the UI kit (Rhylib.UI.Kit, rhylib_core) to draw; without it the
    list arrives but no window opens.

    Also here: the MP options on the rhylib_menus interaction wheel
    (Search, Cuff, Uncuff, Escort / Let go), sent as net mp.wheel.
]]

local MP = Rhylib.MP

local CONT_NAMES = { [1] = "Carried", [2] = "Backpack", [3] = "Back slot", [5] = "Cell rack", [6] = "Ammo belt", [7] = "Holster" }
for i = 8, 17 do CONT_NAMES[i] = "Worn gear" end
CONT_NAMES[18] = "Belt pouches"
CONT_NAMES[19] = "Cell pouch"
CONT_NAMES[20] = "Belt cells"
CONT_NAMES[21] = "Gun belt"

-- MP.OpenSearch(target): asks the server to search target (net mp.search).
-- The server checks everything and answers with mp.list. Client only.
-- Example (from another addon's button): Rhylib.MP.OpenSearch(ply)
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

-- MP.ShowSearch(target, cuffed, rows): opens or refreshes the search window.
-- rows = { uid, def, count, fill, c } as read from mp.list. Closing it
-- sends mp.search with NULL so the server stops refreshing. Client only.
local DIA = { {}, {}, {}, {} }
local GRAD = Material("vgui/gradient-l")

local function kindCol(K, def)
    local Inv = Rhylib.Inventory
    local cc = def and Inv and Inv.CATEGORY_COLORS and (Inv.CATEGORY_COLORS[def.category] or Inv.CATEGORY_COLORS.misc)
    return cc and cc.stripe or K.C.label
end

function MP.ShowSearch(target, cuffed, rows)

    local K = Rhylib.UI and Rhylib.UI.Kit
    if not K then return end
    local C, s = K.C, K.S
    local f = MP.searchPanel
    if not IsValid(f) then
        f = vgui.Create("EditablePanel")
        f:SetSize(s(500), math.min(s(600), ScrH() - s(40)))
        f:Center()
        f:MakePopup()
        f:SetKeyboardInputEnabled(false)
        f:DockPadding(s(14), s(84), s(14), s(14))
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
        local UI = Rhylib.UI
        if UI and UI.RegisterCloser then
            UI.RegisterCloser("mp.search", function()
                if IsValid(MP.searchPanel) then MP.searchPanel:Remove() return true end
                return false
            end)
        end
    end
    f.target, f.cuffed = target, cuffed
    f.count = #rows
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Search · " .. (IsValid(self.target) and self.target:Nick() or "?"),
            sub = self.count == 1 and "1 item" or (self.count .. " items"), ticks = "all", header = s(38),
            rule = self.cuffed and C.good or C.warn })
        -- (state chip)
        local col = self.cuffed and C.good or C.warn
        local text = self.cuffed and "CUFFED · YOU CAN TAKE ITEMS" or "LOOK ONLY · NOT CUFFED"
        local cf = K.Font(11, 700)
        surface.SetFont(cf)
        local cw, ch = surface.GetTextSize(text) + s(16), s(20)
        local cx, cy = s(14), s(50)
        K.SetCol(col, 35)
        surface.DrawRect(cx, cy, cw, ch)
        K.SetCol(col, 150)
        surface.DrawOutlinedRect(cx, cy, cw, ch)
        draw.SimpleText(text, cf, cx + cw * 0.5, cy + ch * 0.5, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    local sp = f.scroll
    sp:Clear()
    if #rows == 0 then
        local p = vgui.Create("DPanel", sp)
        p:Dock(TOP)
        p:SetTall(s(64))
        p:DockMargin(0, s(4), s(8), 0)
        function p:Paint(w, h)
            K.SetCol(C.tick, 140)
            local dash, gap = s(6), s(4)
            for i = 0, w - 1, dash + gap do
                local len = math.min(dash, w - i)
                surface.DrawRect(i, 0, len, 1)
                surface.DrawRect(i, h - 1, len, 1)
            end
            for j = 0, h - 1, dash + gap do
                local len = math.min(dash, h - j)
                surface.DrawRect(0, j, 1, len)
                surface.DrawRect(w - 1, j, 1, len)
            end
            draw.SimpleText("They carry nothing.", K.Font(14), w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end
    -- (items per place, for the band counts)
    local per = {}
    for _, r in ipairs(rows) do
        local head = CONT_NAMES[r.c] or "Other"
        per[head] = (per[head] or 0) + 1
    end
    local lastC
    local n = 0
    for _, r in ipairs(rows) do
        local head = CONT_NAMES[r.c] or "Other"
        if head ~= lastC then
            lastC = head
            n = 0
            local band = vgui.Create("DPanel", sp)
            band:Dock(TOP)
            band:SetTall(s(30))
            band:DockMargin(0, s(6), s(8), s(3))
            local cap = string.upper(head)
            local cnt = per[head] == 1 and "1 item" or (per[head] .. " items")
            function band:Paint(w, h)
                K.SetCol(C.accent, 35)
                surface.SetMaterial(GRAD)
                surface.DrawTexturedRect(0, 0, w * 0.7, h)
                K.SetCol(C.accent)
                surface.DrawRect(0, 0, s(4), h)
                local cx, cy, rr = s(18), h * 0.5, s(5)
                DIA[1].x, DIA[1].y = cx, cy - rr
                DIA[2].x, DIA[2].y = cx + rr, cy
                DIA[3].x, DIA[3].y = cx, cy + rr
                DIA[4].x, DIA[4].y = cx - rr, cy
                draw.NoTexture()
                K.SetCol(C.accent)
                surface.DrawPoly(DIA)
                draw.SimpleText(cap, K.Font(14, 700), s(32), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(cnt, K.Font(12), w - s(10), h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
        n = n + 1
        local alt = n % 2 == 0
        local name = r.def and r.def.name or "Unknown item"
        local sub = r.count > 1 and ("x" .. r.count) or ""
        if r.def and r.def.fill and r.def.rounds then sub = math.floor(r.fill / 100 * r.def.rounds + 0.5) .. " / " .. r.def.rounds end
        local def = r.def
        local row = vgui.Create("DPanel", sp)
        row:Dock(TOP)
        row:SetTall(s(38))
        row:DockMargin(0, 0, s(8), s(2))
        row:DockPadding(0, s(6), s(8), s(6))
        local rightW = cuffed and s(90) or 0
        function row:Paint(w, h)
            K.SetCol(self:IsHovered() and C.rowHover or (alt and C.rowAlt or C.row))
            surface.DrawRect(0, 0, w, h)
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            K.SetCol(kindCol(K, def))
            surface.DrawRect(0, 0, s(3), h)
            local vx = w - s(12) - (rightW > 0 and rightW + s(4) or 0)
            if sub ~= "" then
                draw.SimpleText(sub, K.Font(13, 700), vx, h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
            draw.SimpleText(K.Fit(name, K.Font(14, 600), vx - s(90)), K.Font(14, 600), s(14), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        if cuffed then
            local uid = r.uid
            local b = K.Button(row, "Take", function()
                Rhylib.Net.Start("mp.take")
                net.WriteEntity(target)
                net.WriteUInt(uid, Rhylib.Items.UID_BITS)
                net.SendToServer()
            end, { small = true, accent = true })
            b:Dock(RIGHT)
            b:SetWide(rightW)
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
    if MP.IsCuffed(t) and t:GetNW2Bool("rhylib_bound", false) then
        -- (bound with rhylib_bounty's binders: the hunter's prisoner)
        add("Uncuff", nil, { order = 32, disabled = "A bounty hunter's prisoner" })
    elseif MP.IsCuffed(t) then
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

Rhylib.Net.Receive("mp.wheelx", function()
    local Menus = Rhylib.Menus
    if Menus and Menus.WheelProgressStop then Menus.WheelProgressStop() end
end)
