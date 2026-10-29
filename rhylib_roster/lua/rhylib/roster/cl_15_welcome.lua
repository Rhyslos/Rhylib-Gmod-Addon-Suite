--[[
    "Getting started" card (client; needs rhylib_menus' Kit).

    Shown once after a new character is made (roster.created ok), and on
    the first spawn of a player who already has one but never saw it
    (client cookie rhylib_welcome_seen). Lists the keys a new player can't
    find on their own: controls page, inventory, interaction wheel,
    injuries, the pause menu, the armoury and how to get basic training.
    Keys are read from the players' own binds / Rhy's key settings.

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

function R.ShowWelcome()
    local k = K()
    if not k or IsValid(panel) then return end
    cookie.Set("rhylib_welcome_seen", "1")
    local s = k.S
    local list = lines()
    local w, rowH = s(560), s(30)
    local h = s(30) + s(16) + #list * rowH + s(58)
    panel = vgui.Create("EditablePanel")
    panel:SetSize(w, h)
    panel:Center()
    panel:MakePopup()
    panel:SetKeyboardInputEnabled(false)
    function panel:Paint(pw, ph)
        k.Plate(0, 0, pw, ph, { title = "Getting started", sub = "Rhy's Clone Wars RP", ticks = "all" })
        local y = s(30) + s(12)
        for _, l in ipairs(list) do
            if l[1] ~= "" then
                draw.SimpleText(l[1], k.Font(14, 700), s(18), y + rowH * 0.5, k.C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            draw.SimpleText(l[2], k.Font(14), s(118), y + rowH * 0.5, k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            y = y + rowH
        end
    end
    local b = k.Button(panel, "Got it", function() if IsValid(panel) then panel:Remove() end end, { accent = true })
    b:SetSize(s(140), s(34))
    b:SetPos(w - s(140) - s(14), h - s(34) - s(12))
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
