--[[
    Class page (pause menu, Character group, under Skills), only listed
    while class mode is on: asks whether you want to play a class, says
    what happens, then lists the classes with their descriptions. The
    Officer card picks a command order first. Staff get a button to switch
    class mode off (switching it on is on the Skills page or
    rhylib_classmode).
    Client only; needs rhylib_menus. Sends skills.classpick (class index
    UInt 4, order index UInt 3, 0 = none), skills.classleave, and
    skills.classmode (bool; the server checks the permission).
]]

local K = Rhylib.Skills

local function send(name, fn)
    Rhylib.Net.Start(name)
    if fn then fn() end
    net.SendToServer()
end

local function build(page)
    local Menus = Rhylib.Menus
    local Kit = Menus.Kit
    local C, S = Kit.C, Kit.S
    local me = LocalPlayer()
    local cur = K.ClassOf(me)
    local left = K.ClassPicksLeft(me)

    -- Rebuild when something changes (a pick, a leave, class mode itself).
    local function sig()
        local c = K.ClassOf(me)
        return tostring(K.ClassMode()) .. (c and c.id or "") .. K.ClassPicksLeft(me)
    end
    local built = sig()
    local sp = Kit.Scroll(page)
    sp:Dock(FILL)
    -- (on the scroll panel, so it goes with this page)
    function sp:Think()
        if sig() == built then return end
        built = sig()
        if not K.ClassMode() then
            if IsValid(Menus.pause) then Menus.pause:ShowPage("skills") end
        else
            Menus.RefreshPause()
        end
    end
    local function add(p, top)
        p:Dock(TOP)
        p:DockMargin(0, top or 0, S(10), 0)
        return p
    end

    add(Kit.Heading(sp, cur and ("Playing a class: " .. cur.name) or "Do you want to play a class?"))
    add(Kit.Label(sp, "Class mode is on. Instead of your own skill tree you can play a ready-made class: you get "
        .. "every skill of that class at once, nothing to unlock. Your own skills are kept safe and come back when you "
        .. "go back to your own tree, or when staff switch class mode off. Job rules still apply (medic classes need "
        .. "a medic job, Shock Trooper the military police).", 14, nil, C.textDim), S(8))
    add(Kit.Label(sp, "You can pick a class once and change your mind once each time class mode is switched on. "
        .. (left > 0 and (left == 1 and "1 change left." or (left .. " picks left.")) or "No changes left."), 14, 600, C.text), S(8))

    -- Back to your own tree / staff switch.
    local bar = add(vgui.Create("DPanel", sp), S(10))
    bar:SetTall(S(34))
    bar.Paint = nil
    if cur then
        local b = Kit.Button(bar, "Back to my own skill tree", function() send("skills.classleave") end)
        b:Dock(LEFT)
        b:SetWide(S(260))
    end
    if me:IsAdmin() then
        local b = Kit.Button(bar, "Staff: switch class mode off", function()
            send("skills.classmode", function() net.WriteBool(false) end)
        end, { danger = true })
        b:Dock(RIGHT)
        b:SetWide(S(260))
    end

    add(Kit.Heading(sp, "Classes"), S(14))
    for _, cls in ipairs(K.CLASSES) do
        local ok, why = K.ClassAllowed(me, cls)
        local playing = cur == cls
        local chosen = 0
        local card = add(vgui.Create("DPanel", sp), S(8))
        card:SetTall(cls.orders and S(124) or S(84))
        card:DockPadding(S(14), S(34), S(14), S(10))
        function card:Paint(w, h)
            Kit.Plate(0, 0, w, h, { bg = playing and C.rowAlt or C.row })
            if playing then
                Kit.SetCol(C.accent)
                surface.DrawRect(0, 0, S(4), h)
            end
            draw.SimpleText(string.upper(cls.name), Kit.Font(16, 700), S(14), S(10), ok and C.text or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            surface.SetFont(Kit.Font(16, 700))
            local tw = surface.GetTextSize(string.upper(cls.name))
            draw.SimpleText(playing and "PLAYING" or (ok and cls.who or why), Kit.Font(12, 600), S(24) + tw, S(13),
                playing and C.accent or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        -- (the order row first, so it spans the card's full width)
        if cls.orders then
            local opts = {}
            for _, o in ipairs(K.ORDERS) do opts[#opts + 1] = { o.index, o.name } end
            local ch = Kit.Choices(card, opts, function() return chosen end, function(v) chosen = v end)
            ch:Dock(BOTTOM)
            ch:SetTall(S(26))
            ch:DockMargin(0, S(6), 0, 0)
        end
        local btn = Kit.Button(card, playing and (cls.orders and "Change order" or "Playing") or "Play this class", function()
            send("skills.classpick", function()
                net.WriteUInt(cls.index, 4)
                net.WriteUInt(chosen, 3)
            end)
        end, { accent = true, enabled = function()
            if not ok or left <= 0 then return false end
            if cls.orders then return chosen > 0 end
            return not playing
        end })
        btn:Dock(RIGHT)
        btn:SetWide(S(170))
        btn:DockMargin(S(10), 0, 0, 0)
        local d = Kit.Label(card, cls.desc .. (cls.orders and ("  Command orders need the rank " .. tostring(K.Cfg("commandRank")) .. ".") or ""), 13, nil, C.label)
        d:SetAutoStretchVertical(false)
        d:Dock(FILL)
        d:SetContentAlignment(7)
    end
end

local function addPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage and Menus.Kit) then return end
    Menus.AddPage("class", {
        title = "Class",
        order = 23,   -- (right under Skills)
        group = "character",
        visible = function() return K.ClassMode() end,
        build = build,
    })
end
addPage()
Rhylib.Hook.Add("InitPostEntity", "skills.classpage", addPage)

-- The page only shows while class mode is on: rebuild an open pause
-- menu's side bar when that changes.
local lastMode
timer.Create("Rhylib.Skills.ClassNav", 0.5, 0, function()
    local on = K.ClassMode()
    if on == lastMode then return end
    lastMode = on
    local Menus = Rhylib.Menus
    if not (Menus and IsValid(Menus.pause)) then return end
    if not on and Menus.pause.pageId == "class" then
        Menus.pause:ShowPage("skills")
    elseif Menus.pause.BuildNav then
        Menus.pause:BuildNav()
    end
end)
