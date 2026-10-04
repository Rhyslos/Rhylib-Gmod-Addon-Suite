--[[
    Character creator: shown on first join (roster.need), can't be closed
    until a character is saved. Clone number + nickname, with a live
    preview of the name: CC-1234 Nickname, and looks (hair, facial hair)
    with a preview (cl_15_look.lua).
]]

local R = Rhylib.Roster
local panel

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end

local function open()
    local k = K()
    if not k then return end
    if IsValid(panel) then panel:Remove() end
    local s = k.S
    -- A full-screen backdrop (dims the game) holding the window.
    panel = vgui.Create("EditablePanel")
    panel:SetSize(ScrW(), ScrH())
    panel:SetPos(0, 0)
    panel:MakePopup()
    panel.err = ""
    function panel:Paint(w, h)
        surface.SetDrawColor(0, 0, 0, 200)
        surface.DrawRect(0, 0, w, h)
    end
    local frame = vgui.Create("EditablePanel", panel)
    frame:SetSize(s(780), s(600))
    frame:Center()
    frame:DockPadding(s(18), s(52), s(18), s(18))
    function frame:Paint(w, h)
        k.Plate(0, 0, w, h, { title = "New recruit", sub = "Create your clone", ticks = "all", header = s(38) })
    end

    local look = { hair = "hair_reg", fhair = "", hcol = 0, skin = 0 }
    local lookPrev = R.LookPreview and R.LookPreview(frame, function() return look end)
    if IsValid(lookPrev) then
        lookPrev:Dock(RIGHT)
        lookPrev:SetWide(s(230))
        lookPrev:DockMargin(s(12), 0, 0, 0)
    end

    local intro = k.Label(frame, "Pick your clone number and a nickname. You start as a cadet; basic training makes you a clone trooper, and a battalion gives you a rank.", 13, 400, k.C.textDim)
    intro:Dock(TOP)
    intro:DockMargin(0, 0, 0, s(12))

    local numRow = k.Row(frame, "Clone number", "4 digits, e.g. 0411 or 2187")
    numRow:Dock(TOP)
    numRow:DockMargin(0, 0, 0, s(6))
    numRow.right:SetWide(s(140))
    local num = k.TextEntry(numRow.right, "1234")
    num:Dock(FILL)
    num:SetNumeric(true)

    local nickRow = k.Row(frame, "Nickname", "What your squad calls you")
    nickRow:Dock(TOP)
    nickRow:DockMargin(0, 0, 0, s(12))
    nickRow.right:SetWide(s(220))
    local nick = k.TextEntry(nickRow.right, "Nickname")
    nick:Dock(FILL)

    if R.LookControls then R.LookControls(frame, look) end

    -- Preview and problems.
    local preview = vgui.Create("DPanel", frame)
    preview:Dock(TOP)
    preview:SetTall(s(70))
    local function state()
        local n = num:GetText() or ""
        local nk = R.CleanNick(nick:GetText())
        local okN, whyN = R.ValidNumber(n)
        local okK, whyK = R.ValidNick(nk)
        return n, nk, okN and okK, (not okN and n ~= "" and whyN) or (not okK and nk ~= "" and whyK) or nil
    end
    function preview:Paint(w, h)
        local n, nk, ok, why = state()
        k.SetCol(k.C.row)
        surface.DrawRect(0, 0, w, h)
        local name = "CC-" .. (n ~= "" and n or "????") .. " " .. (nk ~= "" and nk or "Nickname")
        draw.SimpleText(name, k.Font(22, 700), w * 0.5, h * 0.4, ok and k.C.text or k.C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local msg = panel.err ~= "" and panel.err or why or (ok and "Looks good" or "")
        draw.SimpleText(msg, k.Font(12), w * 0.5, h * 0.78, (panel.err ~= "" or why) and k.C.bad or k.C.good, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Keep the number to 4 digits.
    function num:OnChange()
        local t = string.gsub(self:GetText() or "", "%D", "")
        if #t > 4 then t = string.sub(t, 1, 4) end
        if t ~= self:GetText() then
            self:SetText(t)
            self:SetCaretPos(#t)
        end
        panel.err = ""
    end
    function nick:OnChange() panel.err = "" end

    local save = k.Button(frame, "Enlist", function()
        local n, nk, ok = state()
        if not ok then return end
        Rhylib.Net.Start("roster.create")
        net.WriteString(n)
        net.WriteString(nk)
        if R.WriteLook then
            R.WriteLook(look)
        else
            net.WriteString(look.hair)
            net.WriteString(look.fhair)
            net.WriteUInt(0, 4)
            net.WriteUInt(0, 4)
        end
        net.SendToServer()
    end, { accent = true, enabled = function() local _, _, ok = state() return ok end })
    save:Dock(BOTTOM)
    save:SetTall(s(38))
    num:RequestFocus()
end

-- Esc doesn't close it (it can't be skipped).
local function registerCloser()
    local Menus = Rhylib.Menus
    if Menus and Menus.RegisterCloser then
        Menus.RegisterCloser("roster.creator", function() return IsValid(panel) end)
    end
end
registerCloser()

-- Once loaded: register, and ask the server whether we still need a character
-- (and keep asking now and then while we have none and no window is open).
Rhylib.Hook.Add("InitPostEntity", "roster.creator", function()
    registerCloser()
    timer.Create("Rhylib.Roster.Hello", 6, 0, function()
        local ply = LocalPlayer()
        if not IsValid(ply) or ply:GetNW2Bool("rhylib_char", false) then return end
        if IsValid(panel) then return end
        Rhylib.Net.Start("roster.hello")
        net.SendToServer()
    end)
end)

Rhylib.Net.Receive("roster.need", function()
    -- Wait for the UI kit if the game is still loading (the hello timer retries).
    timer.Simple(0.5, function()
        if not IsValid(panel) then open() end
    end)
end)

Rhylib.Net.Receive("roster.created", function()
    local ok, msg = net.ReadBool(), net.ReadString()
    if not IsValid(panel) then return end
    if ok then
        panel:Remove()
    else
        panel.err = msg
    end
end)
