--[[
    "Getting started" card (client; needs the UI kit, rhylib_core).

    Shown once after a new character is made (roster.created ok), and on
    the first spawn of a player who already has one but never saw it
    (client cookie rhylib_welcome_seen). Lists the keys a new player can't
    find on their own: controls page, inventory, interaction wheel,
    injuries, the pause menu, the armoury and how to get basic training.
    Keys are read from the players' own binds / Rhy's key settings.

    Look: a plate with a short welcome, then one row per line (rows
    alternate) with the key as a key cap in the accent colour (a small
    diamond when there's no key), and Got it.

    R.ShowWelcome() opens it; console command `rhylib_welcome` too.
]]

local R = Rhylib.Roster

local function K() return Rhylib.UI and Rhylib.UI.Kit end

local function key(cvar, fallback)
    local c = GetConVar(cvar)
    local v = c and c:GetString() or ""
    return string.upper(v ~= "" and v or fallback)
end

local function bind(b, fallback)
    return string.upper(input.LookupBinding(b) or fallback)
end

local function lines()
    local out = {
        { bind("gm_showhelp", "F1"), "Controls: every key, and where to change it" },
        { "ESC", "The menu: settings, your battalion, skills, staff tools" },
    }
    if Rhylib.Inventory then out[#out + 1] = { key("rhylib_inventory_key", "g"), "Inventory: drag things around, right-click for more" } end
    if Rhylib.Menus then out[#out + 1] = { "HOLD " .. bind("+use", "E"), "Interaction wheel: hold E on a person or thing for what you can do" } end
    if Rhylib.Medical then out[#out + 1] = { key("rhylib_medical_key", "h"), "Injuries: your body, or the one you look at" } end
    if Rhylib.Armoury then out[#out + 1] = { "", "Your gear comes from the armoury: press E on a weapons armoury or ammo cabinet" } end
    if Rhylib.Datapad then out[#out + 1] = { "", "Your datapad (in your inventory) calls MPs, medics and the bomb squad: left click with it out" } end
    out[#out + 1] = { "", "Cadets need basic training: ask a Sergeant or higher, or use \"Request basic training\" on the Battalion page" }
    return out
end

local panel

-- Esc closes the card (rhylib_menus' Esc handler runs the UI closers).
if Rhylib.UI and Rhylib.UI.RegisterCloser then
    Rhylib.UI.RegisterCloser("welcome", function()
        if not IsValid(panel) then return false end
        panel:Remove()
        return true
    end)
end

function R.ShowWelcome()
    local k = K()
    if not k or IsValid(panel) then return end
    cookie.Set("rhylib_welcome_seen", "1")
    local s = k.S
    local C = k.C
    local D = R.Draw
    local list = lines()
    local headH, rowH, keyW = s(36), s(36), s(118)
    local w = math.min(ScrW() - s(40), s(660))
    -- (long lines wrap onto a second line: worked out once here)
    local textW = w - s(32) - keyW - s(10)
    surface.SetFont(k.Font(14))
    local listH = 0
    for _, l in ipairs(list) do
        l.parts = { l[2] }
        if surface.GetTextSize(l[2]) > textW then
            local first, rest = "", nil
            for word in string.gmatch(l[2], "%S+") do
                if rest then rest = rest .. " " .. word
                else
                    local try = first == "" and word or (first .. " " .. word)
                    if surface.GetTextSize(try) > textW and first ~= "" then rest = word else first = try end
                end
            end
            l.parts = { first, rest }
        end
        l.h = #l.parts > 1 and s(52) or rowH
        listH = listH + l.h
    end
    local h = headH + s(58) + listH + s(66)
    panel = vgui.Create("EditablePanel")
    panel:SetSize(w, h)
    panel:Center()
    panel:MakePopup()
    panel:SetKeyboardInputEnabled(false)
    function panel:Paint(pw, ph)
        k.Plate(0, 0, pw, ph, { title = "Getting started", sub = "Rhy's Clone Wars RP", ticks = "all", header = headH })
        local x, y = s(16), headH + s(14)
        draw.SimpleText("Welcome, trooper", k.Font(20, 800), x, y + s(10), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("The keys you won't find on your own", k.Font(13), x, y + s(32), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        y = headH + s(58)
        local f = k.Font(14)
        for i, l in ipairs(list) do
            local rh = l.h
            k.SetCol(i % 2 == 0 and C.rowAlt or C.row)
            surface.DrawRect(x, y, pw - x * 2, rh)
            local cy = y + rh * 0.5
            if l[1] ~= "" then
                -- (a key cap)
                local kf = k.Font(12, 700)
                surface.SetFont(kf)
                local tw = surface.GetTextSize(l[1])
                local cw, ch = math.min(keyW - s(16), tw + s(16)), s(22)
                k.SetCol(C.header)
                surface.DrawRect(x + s(10), cy - ch * 0.5, cw, ch)
                k.SetCol(C.edgeDark)
                surface.DrawOutlinedRect(x + s(10), cy - ch * 0.5, cw, ch)
                k.SetCol(C.accent)
                surface.DrawRect(x + s(10), cy + ch * 0.5 - 2, cw, 2)
                draw.SimpleText(l[1], kf, x + s(10) + cw * 0.5, cy - 1, C.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            elseif D and D.Diamond then
                D.Diamond(x + s(20), cy, s(4), C.label)
            end
            if l.parts[2] then
                draw.SimpleText(l.parts[1], f, x + keyW, cy - s(9), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(k.Fit(l.parts[2], f, pw - x * 2 - keyW - s(10)), f, x + keyW, cy + s(9), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(k.Fit(l[2], f, pw - x * 2 - keyW - s(10)), f, x + keyW, cy, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            y = y + rh
        end
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(x, headH + s(58), pw - x * 2, listH)
        draw.SimpleText("Open it again any time: rhylib_welcome in the console", k.Font(12), x, ph - s(30), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local b = k.Button(panel, "Got it", function() if IsValid(panel) then panel:Remove() end end, { accent = true })
    b:SetSize(s(150), s(36))
    b:SetPos(w - s(150) - s(16), h - s(36) - s(12))
end

concommand.Add("rhylib_welcome", function() R.ShowWelcome() end)

-- Players who had a character before this card existed: once, a little
-- after their first spawn (after the creator would have opened).
Rhylib.Hook.Add("InitPostEntity", "roster.welcome", function()
    timer.Simple(12, function()
        if cookie.GetString("rhylib_welcome_seen", "") == "1" then return end
        local me = LocalPlayer()
        if IsValid(me) and R.FullName and R.FullName(me) then R.ShowWelcome() end
    end)
end)
