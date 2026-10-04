--[[
    Controls help (Settings > Controls): warnings when two Rhylib keys
    share a key (or one takes an important game key), the rebindable keys
    (cl_20_settings.lua), then every fixed control of the installed addons.

    F1 (gm_showhelp) and the console command rhylib_controls open it.

    Other addons add fixed controls with
        Rhylib.Menus.AddControl(section, keys, text, need)
    keys may name game binds in braces: "{+use} + {+reload}" shows the
    player's own keys. need() returns false to hide the row.
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

Menus.controls = Menus.controls or {}
Menus.controlOrder = Menus.controlOrder or {}

function Menus.AddControl(section, keys, text, need)
    local list = Menus.controls[section]
    if not list then
        list = {}
        Menus.controls[section] = list
        Menus.controlOrder[#Menus.controlOrder + 1] = section
    end
    for _, c in ipairs(list) do
        if c.keys == keys and c.text == text then return end
    end
    list[#list + 1] = { keys = keys, text = text, need = need }
end

-- "{+use} + {+reload}" -> "E + R" with the player's own binds.
local function keyText(keys)
    return (string.gsub(keys, "{([^}]+)}", function(bind)
        local k = input.LookupBinding(bind)
        return k and string.upper(k) or ("[" .. bind .. "]")
    end))
end

-- Game binds worth warning about when a Rhylib key takes the same key.
local GAME = {
    ["+forward"] = "Move forward", ["+back"] = "Move back", ["+moveleft"] = "Move left", ["+moveright"] = "Move right",
    ["+jump"] = "Jump", ["+duck"] = "Crouch", ["+speed"] = "Sprint", ["+walk"] = "Walk", ["+use"] = "Use",
    ["+reload"] = "Reload", ["+attack"] = "Fire", ["+attack2"] = "Aim", ["+voicerecord"] = "Voice chat",
    ["messagemode"] = "Chat", ["messagemode2"] = "Team chat", ["+showscores"] = "Scoreboard",
}

-- Every key setting whose addon is installed: { title, convar, key }.
local function keyRows()
    local out = {}
    for _, section in ipairs(Menus.sectionOrder) do
        for _, st in ipairs(Menus.settings[section]) do
            if st.kind == "key" and st.convar and ConVarExists(st.convar) then
                local cv = GetConVar(st.convar)
                out[#out + 1] = { title = st.title, convar = st.convar, key = string.lower(cv and cv:GetString() or "") }
            end
        end
    end
    return out
end

-- Fills Menus.keyConflicts[convar] = true and returns warning lines.
local function conflicts()
    local byKey, lines = {}, {}
    Menus.keyConflicts = {}
    for _, row in ipairs(keyRows()) do
        if row.key ~= "" then
            byKey[row.key] = byKey[row.key] or {}
            table.insert(byKey[row.key], row)
        end
    end
    for key, rows in SortedPairs(byKey) do
        if #rows > 1 then
            local names = {}
            for _, r in ipairs(rows) do
                names[#names + 1] = r.title
                Menus.keyConflicts[r.convar] = true
            end
            lines[#lines + 1] = string.upper(key) .. " is used by " .. table.concat(names, " and ")
        end
        local code = input.GetKeyCode(key)
        local bind = code and code > 0 and input.LookupKeyBinding(code)
        local game = bind and GAME[bind]
        if game then
            for _, r in ipairs(rows) do
                Menus.keyConflicts[r.convar] = true
                lines[#lines + 1] = string.upper(key) .. " is your " .. game .. " key and " .. r.title
            end
        end
    end
    return lines
end

function Menus.ControlsTop(sp)
    local lines = conflicts()
    local box = vgui.Create("DPanel", sp)
    box:Dock(TOP)
    box:DockMargin(0, 0, K.S(10), K.S(6))
    local n = math.max(#lines, 1)
    box:SetTall(K.S(36) + n * K.S(20))
    function box:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(#lines > 0 and C.bad or C.accent)
        surface.DrawRect(0, 0, K.S(3), h)
        draw.SimpleText(#lines > 0 and "KEY CLASHES" or "NO KEY CLASHES", K.Font(13, 700), K.S(14), K.S(16), #lines > 0 and C.bad or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if #lines == 0 then
            draw.SimpleText("Every Rhylib key has a key of its own. F1 opens this page.", K.Font(13), K.S(14), K.S(38), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        for i, l in ipairs(lines) do
            draw.SimpleText(l, K.Font(13), K.S(14), K.S(18) + i * K.S(20), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
end

function Menus.ControlsBottom(sp)
    for _, section in ipairs(Menus.controlOrder) do
        local rows = {}
        for _, c in ipairs(Menus.controls[section]) do
            if not c.need or c.need() then rows[#rows + 1] = c end
        end
        if #rows > 0 then
            local h = K.Heading(sp, section)
            h:Dock(TOP)
            h:DockMargin(0, K.S(6), K.S(10), K.S(6))
            for _, c in ipairs(rows) do
                local row = K.Row(sp, c.text)
                row:Dock(TOP)
                row:DockMargin(0, 0, K.S(10), K.S(4))
                row.right:SetWide(K.S(360))
                local keys = keyText(c.keys)
                function row.right:Paint(w, hh)
                    draw.SimpleText(keys, K.Font(13, 700), w, hh * 0.5, C.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
        end
    end
end

-- Open the pause menu on Settings > Controls.
function Menus.OpenControls()
    Menus.settingsTab = "Controls"
    Menus.lastPage = "settings"
    if IsValid(Menus.pause) then
        Menus.pause:ShowPage("settings")
    else
        Menus.OpenPause()
    end
end
concommand.Add("rhylib_controls", Menus.OpenControls)

Rhylib.Hook.Add("PlayerBindPress", "menus.controls", function(ply, bind, pressed)
    if pressed and bind == "gm_showhelp" then
        Menus.OpenControls()
        return true
    end
end)

--------------------------------------------------------------------------
-- Fixed controls of the suite (shown only when that addon is installed)
--------------------------------------------------------------------------

local function has(name) return function() return Rhylib[name] ~= nil end end
local A = Menus.AddControl

A("Menus", "ESC", "Rhylib menu (Shift + Esc: the game's own menu)")
A("Menus", "F1", "This controls page")
A("Menus", "F4", "Jobs, shop and character")
A("Menus", "{+showscores}", "Scoreboard (right-click frees the mouse)")

A("Interaction", "hold {+use} on a player", "Interaction wheel: move the mouse to an action, let go to do it (middle cancels)", function() return Menus.Wheel ~= nil end)

A("Movement", "{+speed}", "Sprint (uses stamina; jumping too)", has("Stamina"))
A("Movement", "{+jump}", "Jetpack: thrust up", has("Jetpack"))
A("Movement", "{+speed} in the air", "Jetpack: hover", has("Jetpack"))
A("Movement", "{+speed} + side/back + {+jump}", "Sidestep dash (Officer skill), or {+walk} + any direction", has("Skills"))
A("Movement", "{+use} / {+jump}", "Grapple rope: grab or let go / jump off", function() return Rhylib.Weapons and Rhylib.Weapons.Grapple ~= nil end)

A("Weapons", "{+attack} / {+attack2}", "Fire / aim", has("Weapons"))
A("Weapons", "tap {+reload}", "Reload the best magazine", has("Weapons"))
A("Weapons", "hold {+reload}", "Magazine wheel: pick which magazine to load", has("Weapons"))
A("Weapons", "{+use} + {+reload}", "Next fire mode (grenades: timed, impact, breach)", has("Weapons"))
A("Weapons", "{+speed} + {+use} + {+reload}", "Safety on or off", has("Weapons"))
A("Weapons", "{+attack} / {+attack2}", "Grenades: throw / lob", has("Weapons"))

A("Medical", "hold {+attack}, empty hands", "Drag a downed player", has("Medical"))
A("Medical", "hold {+jump} while downed", "Give up", has("Medical"))
A("Medical", "move, {+jump} or {+use}", "Cancel a treatment you're doing", has("Medical"))
A("Medical", "{+attack} / {+attack2}", "Medical kits: on someone else / on yourself", has("Medical"))
A("Medical", "{+use} / {+jump}", "Get out of the bacta tank or off the med sofa", has("Medical"))

A("Military police", "{+attack} / {+attack2}", "Stun baton: stun / search", has("MP"))
A("Military police", "hold {+attack} / {+attack2} / {+reload}", "Handcuffs: cuff / uncuff / escort", has("MP"))

A("Inventory", "Ctrl + drag", "Take one off a stack", has("Inventory"))
A("Inventory", "{+reload} while dragging", "Rotate the item", has("Inventory"))
A("Inventory", "right-click", "Item options; in a storage: quick take", has("Inventory"))
A("Inventory", "drag out of the window", "Drop it", has("Inventory"))
A("Inventory", "{+attack} / {+attack2}", "Holding magazines etc.: give one to who you look at / drop one", has("Inventory"))
A("Inventory", "{+attack} / {+attack2}", "Ammo pack: resupply who you look at / yourself", has("Weapons"))

A("Datapad", "{+attack}", "Open the datapad (while holding it)", has("Datapad"))
