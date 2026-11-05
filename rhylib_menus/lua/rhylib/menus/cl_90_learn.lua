--[[
    Learn (pause menu > Options > Learn): a built-in wiki of how everything
    on the server works. A search box on top, the topics on the left in
    groups (Menus.LEARN_GROUPS), the open topic on the right.

    Topics register themselves (client):
        Rhylib.Menus.AddLearn("medical", {
            title = "Medical: wounds & revives", group = "fighting", order = 20,
            col = Color(226, 75, 74),          -- the diamond and header strip
            needs = "medical",                 -- module id(s): hidden without them
            visible = function() return true end,    -- optional
            lock = function() return "Needs ..." end, -- optional: listed with a
                                               -- lock, content replaced by the text
            sub = "one line under the title",
            words = "extra search words",
            blocks = { ... },                  -- or build = function(panel, kit) end
        })
    blocks (in order): { "p", text } a paragraph, { "h", text } a sub
    heading, { "steps", { text, ... } } numbered steps, { "keys", { { key,
    text }, ... } } a key table, { "note", text } a highlighted note. Text
    may be a function (read when shown: config values).
    build(panel, kit) fills the whole topic panel (it draws its own title;
    dock a K.Scroll FILL in it); search then only matches title, sub and
    words.

    Menus.OpenLearn(id): opens the pause menu on Learn at that topic (the
    datapad's EOD manual opens the bomb manual this way). Console command
    rhylib_learn [topic id].

    The general topics (basics, fighting, the base) are below, each shown
    only when its addon is installed (the medical one reads whether the
    hardcore medical system is on). Rhy's EOD adds the bomb manual,
    mines and training bombs (rhylib_eod cl_40_manual.lua).
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

Menus.LEARN_GROUPS = {
    { id = "basics", title = "Basics" },
    { id = "fighting", title = "Fighting" },
    { id = "explosives", title = "Explosives" },
    { id = "base", title = "The base" },
    { id = "class", title = "Your class" },
    { id = "staff", title = "Staff" },
}

Menus.learn = Menus.learn or {}
function Menus.AddLearn(id, t)
    t.id = id
    Menus.learn[id] = t
end

local NOTE_BG, NOTE_EDGE, NOTE_TEXT = Color(36, 33, 15), Color(245, 217, 10), Color(240, 231, 180)
local DIAMOND = { {}, {}, {}, {} }   -- (one vertex table, filled per row)
local CLEAR, ROW_TEXT, BADGE_TEXT = Color(0, 0, 0, 0), Color(201, 200, 192), Color(20, 20, 19)

local function txt(v) if isfunction(v) then local ok, r = pcall(v) return ok and tostring(r or "") or "" end return v or "" end

local function shown(t)
    if t.needs then
        local list = istable(t.needs) and t.needs or { t.needs }
        for _, m in ipairs(list) do if not Rhylib.Has(m) then return false end end
    end
    if t.visible then
        local ok, r = pcall(t.visible)
        if not ok or not r then return false end
    end
    return true
end

local function lockOf(t)
    if not t.lock then return nil end
    local ok, r = pcall(t.lock)
    return ok and r or nil
end

-- Lower-case text of a topic, for the search.
local function haystack(t)
    local parts = { t.title or "", txt(t.sub), t.words or "" }
    for _, b in ipairs(t.blocks or {}) do
        if istable(b[2]) then
            for _, x in ipairs(b[2]) do
                if istable(x) then parts[#parts + 1] = txt(x[1]) .. " " .. txt(x[2]) else parts[#parts + 1] = txt(x) end
            end
        else
            parts[#parts + 1] = txt(b[2])
        end
    end
    return string.lower(table.concat(parts, " "))
end

local function topicsIn(group, query)
    local out = {}
    for _, t in pairs(Menus.learn) do
        if t.group == group and shown(t) then
            if query == "" or string.find(haystack(t), query, 1, true) then out[#out + 1] = t end
        end
    end
    table.sort(out, function(a, b)
        local oa, ob = a.order or 50, b.order or 50
        if oa ~= ob then return oa < ob end
        return (a.title or a.id) < (b.title or b.id)
    end)
    return out
end

-- Blocks -> panels in the scroll sp.
local function buildBlocks(sp, t)
    local s = K.S
    local col = t.col or C.accent
    local n = 0
    for _, b in ipairs(t.blocks or {}) do
        local kind, v = b[1], b[2]
        if kind == "p" then
            local l = K.Label(sp, txt(v), 14, 400, C.text)
            l:Dock(TOP)
            l:DockMargin(0, s(2), s(12), s(8))
        elseif kind == "h" then
            local h = K.Heading(sp, txt(v), col)
            h:Dock(TOP)
            h:DockMargin(0, s(10), s(10), s(6))
            n = 0
        elseif kind == "note" then
            local p = vgui.Create("DPanel", sp)
            p:Dock(TOP)
            p:DockMargin(0, s(4), s(10), s(8))
            p:DockPadding(s(14), s(8), s(10), s(8))
            local l = K.Label(p, txt(v), 13, 400, NOTE_TEXT)
            l:Dock(TOP)
            function p:PerformLayout() self:SizeToChildren(false, true) self:SetTall(self:GetTall() + s(8)) end
            function p:Paint(w, h)
                K.SetCol(NOTE_BG)
                surface.DrawRect(0, 0, w, h)
                K.SetCol(NOTE_EDGE)
                surface.DrawRect(0, 0, s(4), h)
            end
        elseif kind == "steps" or kind == "keys" then
            for _, item in ipairs(v or {}) do
                n = n + 1
                local num = n
                local p = vgui.Create("DPanel", sp)
                p:Dock(TOP)
                p:DockMargin(0, 0, s(10), s(3))
                local leftW = kind == "keys" and s(170) or s(42)
                local l = K.Label(p, txt(kind == "keys" and item[2] or item), 14, 400, C.text)
                l.OnSizeChanged = function() if IsValid(p) then p:InvalidateLayout() end end
                function p:PerformLayout(w)
                    l:SetPos(leftW, s(8))
                    l:SetWide(w - leftW - s(10))
                    l:InvalidateLayout(true)
                    l:SizeToContentsY()
                    self:SetTall(math.max(s(36), l:GetTall() + s(16)))
                end
                local key = kind == "keys" and txt(item[1]) or nil
                function p:Paint(w, h)
                    K.SetCol(C.row)
                    surface.DrawRect(0, 0, w, h)
                    if key then
                        draw.SimpleText(key, K.Font(13, 700), s(12), s(18), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    else
                        local r = s(11)
                        draw.RoundedBox(r, s(12), s(18) - r, r * 2, r * 2, col)
                        draw.SimpleText(tostring(num), K.Font(13, 800), s(12) + r, s(18), BADGE_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                end
            end
        end
    end
end

local function showTopic(body, t)
    body:Clear()
    if not t then
        local l = K.Label(body, "Nothing found. Try another word.", 14, 400, C.textDim)
        l:Dock(TOP)
        return
    end
    local s = K.S
    local col = t.col or C.accent
    local lock = lockOf(t)
    -- (a built topic draws its own title)
    if t.build and not lock then
        local holder = vgui.Create("DPanel", body)
        holder:Dock(FILL)
        holder.Paint = nil
        local ok, err = pcall(t.build, holder, K)
        if not ok then Rhylib.Error("menus", "learn %s: %s", t.id, tostring(err)) end
        return
    end
    local head = vgui.Create("DPanel", body)
    head:Dock(TOP)
    head:SetTall(s(lock and 92 or 70))
    head:DockMargin(0, 0, 0, s(8))
    function head:Paint(w, h)
        K.SetCol(C.header)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(col)
        surface.DrawRect(0, 0, w, s(3))
        draw.SimpleText(string.upper(t.title or t.id), K.Font(24, 800), s(14), s(14), C.text)
        local sub = txt(t.sub)
        if sub ~= "" then draw.SimpleText(K.Fit(sub, K.Font(13), w - s(28)), K.Font(13), s(14), s(44), C.textDim) end
        if lock then
            K.Icon("lock", s(14), s(64), s(16), C.warn)
            draw.SimpleText(lock, K.Font(13, 700), s(36), s(72), C.warn, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    if lock then return end
    local sp = K.Scroll(body)
    sp:Dock(FILL)
    buildBlocks(sp, t)
end

Menus.AddPage("learn", {
    title = "Learn",
    order = 110,
    section = "options",
    icon = "learn",
    wide = true,
    sub = "How everything on this server works",
    build = function(page)
        local s = K.S
        local query = ""
        local nav, body

        local top = vgui.Create("DPanel", page)
        top:Dock(TOP)
        top:SetTall(s(34))
        top:DockMargin(0, 0, 0, s(8))
        top.Paint = nil
        local search = K.TextEntry(top, "Search: capacitor, limp, jammer, garrison…")
        search:Dock(LEFT)
        search:SetWide(math.min(s(420), page:GetWide() * 0.5))
        search:SetUpdateOnType(true)

        nav = K.Scroll(page)
        nav:Dock(LEFT)
        nav:SetWide(s(270))
        nav:DockMargin(0, 0, s(14), 0)
        body = vgui.Create("DPanel", page)
        body:Dock(FILL)
        body.Paint = nil

        local function fill()
            nav:Clear()
            local first, current
            for _, g in ipairs(Menus.LEARN_GROUPS) do
                local list = topicsIn(g.id, query)
                if #list > 0 then
                    local hd = vgui.Create("DPanel", nav)
                    hd:Dock(TOP)
                    hd:SetTall(s(28))
                    hd:DockMargin(0, s(6), s(8), 0)
                    function hd:Paint(w, h)
                        draw.SimpleText(string.upper(g.title), K.Font(12, 700), s(10), h - s(8), C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
                    end
                    for _, t in ipairs(list) do
                        first = first or t
                        if t.id == Menus.learnTopic then current = t end
                        local b = vgui.Create("DButton", nav)
                        b:SetText("")
                        b:Dock(TOP)
                        b:SetTall(s(34))
                        b:DockMargin(0, 0, s(8), s(1))
                        local locked = t.lock and lockOf(t)
                        function b:Paint(w, h)
                            local on = Menus.learnTopic == t.id
                            K.SetCol(on and C.rowHover or (self:IsHovered() and C.rowAlt or CLEAR))
                            surface.DrawRect(0, 0, w, h)
                            if on then K.SetCol(C.accent) surface.DrawRect(0, 0, s(3), h) end
                            local d = s(8) * 0.7
                            draw.NoTexture()
                            K.SetCol(t.col or C.accent)
                            local cx, cy = s(18), h * 0.5
                            DIAMOND[1].x, DIAMOND[1].y = cx, cy - d
                            DIAMOND[2].x, DIAMOND[2].y = cx + d, cy
                            DIAMOND[3].x, DIAMOND[3].y = cx, cy + d
                            DIAMOND[4].x, DIAMOND[4].y = cx - d, cy
                            surface.DrawPoly(DIAMOND)
                            draw.SimpleText(K.Fit(t.title or t.id, K.Font(14, on and 700 or 500), w - s(56)), K.Font(14, on and 700 or 500), s(32), cy, on and C.text or ROW_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                            if locked then K.Icon("lock", w - s(24), cy - s(7), s(14), C.textDim) end
                            return true
                        end
                        function b:DoClick()
                            surface.PlaySound("ui/buttonclick.wav")
                            Menus.learnTopic = t.id
                            showTopic(body, t)
                        end
                    end
                end
            end
            local t = current or first
            if t then Menus.learnTopic = t.id end
            showTopic(body, t)
        end
        function search:OnValueChange(v)
            query = string.lower(string.Trim(v or ""))
            fill()
        end
        fill()
    end,
})

-- Menus.OpenLearn(id): the pause menu on Learn, at topic id (if shown).
function Menus.OpenLearn(id)
    if id then Menus.learnTopic = id end
    Menus.lastPage = "learn"
    -- (the pause menu already open: just switch page)
    if IsValid(Menus.pause) then
        Menus.pause:ShowPage("learn")
        return
    end
    if Rhylib.UI and Rhylib.UI.CloseAll then pcall(Rhylib.UI.CloseAll) end
    Menus.OpenPause()   -- (opens on lastPage)
end
concommand.Add("rhylib_learn", function(_, _, args) Menus.OpenLearn(args[1]) end)

--------------------------------------------------------------------------
-- General topics
--------------------------------------------------------------------------

local BLUE, AMBER, RED, GREEN, PURPLE, CYAN = Color(133, 183, 235), Color(239, 159, 39), Color(226, 75, 74), Color(151, 196, 89), Color(164, 110, 224), Color(60, 210, 220)

Menus.AddLearn("start", { title = "Getting started", group = "basics", order = 10, col = BLUE,
    sub = "Your first minutes on the server",
    blocks = {
        { "p", "You are a clone of the Grand Army of the Republic. Everything you need is in this menu (Esc): your trooper, skills, jobs, battalion, radio and settings." },
        { "steps", {
            "Pick a clone number, a nickname and your looks the first time you join.",
            "As a cadet, pass basic training: walk up to a training instructor and press E for the quiz, or press \"Request basic training\" on the Battalion page.",
            "Get your kit from the armoury: E on an armoury or cabinet opens it next to your inventory (G). Drag out what you need.",
            "Join a squad on the Radio page (T) and talk with B.",
            "Spend skill points on the Skills page (M).",
        } },
        { "note", "Press F1 for every key, and Settings to change them." },
    } })

Menus.AddLearn("keys", { title = "Menus & keys", group = "basics", order = 20, col = BLUE, needs = "menus",
    sub = "The keys you use all the time (change them in Settings > Controls)",
    blocks = {
        { "keys", {
            { "Esc", "This menu. Shift + Esc: the game's own menu." },
            { "F1", "Controls: every key on the server." },
            { "F4", "Jobs." },
            { "M", "Skills." },
            { "T", "Radio & squads." },
            { "Tab", "Scoreboard; right-click frees the mouse." },
            { "Hold E on a player", "Interaction wheel: move to an action and let go." },
            { "G", "Inventory." },
            { "V", "Next fire mode; hold for the fire-mode wheel." },
            { "P", "Third person (when the server allows it). N swaps shoulder." },
            { "Middle mouse", "Freelook: look around without turning." },
        } },
    } })

Menus.AddLearn("inventory", { title = "Inventory & weight", group = "basics", order = 30, col = BLUE, needs = "inventory",
    sub = "Carrying, the hotbar and handing gear in", words = "kg carry limit backpack hotbar drop give",
    blocks = {
        { "keys", {
            { "G", "Open / close the inventory. You can walk with it open." },
            { "Drag", "Move an item; onto a matching stack to merge. R turns it, Ctrl takes just one." },
            { "Drop outside", "Off the grids: drop it. Onto an armoury: hand it in." },
            { "Right-click", "Split, equip on the hotbar, wear, give, drop." },
            { "Number keys", "Hotbar slots. Pressing the slot you hold puts the gun away." },
        } },
        { "h", "Weight" },
        { "p", "The bar at the top shows your load against your carry cap. Over the cap you can't sprint; far over it you can't pick up any more. A backpack adds carry cap and room." },
    } })

Menus.AddLearn("weapons", { title = "Weapons & fire modes", group = "fighting", order = 10, col = AMBER, needs = "weapons",
    sub = "Shooting, reloading, modes and the crosshair",
    blocks = {
        { "keys", {
            { "LMB / RMB", "Fire / aim." },
            { "R", "Reload. Hold R for the ammo wheel (only ammo you carry shows)." },
            { "V", "Next fire mode. Hold V for the wheel: skill modes appear once learned." },
            { "Shift + E + R", "Safety on / off." },
        } },
        { "p", "Bolts are slow enough to see: lead moving targets. Low stamina widens your aim; aiming and crouching tighten it." },
        { "note", "Settings > Crosshair changes how the crosshair looks, with a live preview." },
    } })

-- (rhylib_medical's hardcore system on: the medical topic reads it when shown)
local function medHard()
    local Med = Rhylib.Medical
    return Med and Med.Hardcore and Med.Hardcore() or false
end

Menus.AddLearn("medical", { title = "Medical: wounds & revives", group = "fighting", order = 20, col = RED, needs = "medical",
    sub = "Going down, bleeding, limping and getting patched up", words = "downed bleed limp medkit revive kit first aid drag stabilise hardcore fracture broken bone burns",
    blocks = {
        { "p", "At 0 health you go down instead of dying. Someone can stabilise you (E), drag you (hold LMB with empty hands) or revive you with a kit. Hold Jump for 3 s to give up." },
        { "h", "Wounds" },
        { "p", function()
            if medHard() then
                return "Hits bleed easily: light bleeding stops by itself, heavy bleeding goes on until treated. A hard arm or leg hit or a fall can break the bone: a broken leg walks slowly and can't sprint, a broken or badly hurt arm can't aim. Fire and blasts burn, which shakes your aim and heals slowly."
            end
            return "Big hits bleed: light bleeding stops by itself, heavy bleeding goes on until treated. A hard leg hit, a fall or a close blast makes you limp for a while: no sprinting. A hurt arm widens your aim."
        end },
        { "keys", {
            { "H", "Injury menu: your body, or the player you look at." },
            { "Medkit", function()
                if medHard() then return "LMB someone, RMB yourself: opens their injury menu; drag the kit onto one body part. Stops its bleeding; a medic's also sets the bone." end
                return "LMB someone, RMB yourself. Worst problem first, then health. A medic's medkit fixes more."
            end },
            { "First aid kit", function()
                if medHard() then return "Medics: drag onto a part to fix it all (bones, burns); LMB on a downed player revives." end
                return "Medics: fixes everything; LMB on a downed player revives."
            end },
            { "Revive kit", "Medics: LMB on a downed player." },
        } },
        { "note", function()
            if medHard() then return "This server runs hardcore medical: fractures and burns, only medics set bones and treat burns, and you treat one body part at a time in the H menu." end
            return "Some servers run hardcore medical: fractures and burns, only medics set bones, and you treat one body part at a time in the H menu."
        end },
    } })

Menus.AddLearn("radio", { title = "Radio, squads & the compass", group = "fighting", order = 30, col = GREEN, needs = "radio",
    sub = "Talking, pings and the radar", words = "squad channel ping jammer compass radar hide",
    blocks = {
        { "keys", {
            { "T", "Radio page: squads, channels, hails, the compass." },
            { "Hold B", "Talk on the radio slot you picked (K switches it)." },
            { "Hold O", "Ping wheel for your squad." },
        } },
        { "p", "The compass shows your squad in green and other friendlies in blue. Marked enemies show as red marks for whoever got the mark. Inside a comms jammer the radio and compass are cut." },
    } })

Menus.AddLearn("skills", { title = "Skill trees", group = "class", order = 10, col = CYAN, needs = "skills",
    sub = "Points, paths and branches",
    blocks = {
        { "p", "Press M. Click a skill to learn it; right-click a freshly learned one to undo it. Hover a skill to read what it does and what it needs." },
        { "p", "Some skills are a choice between two branches: learning one closes the other. Your job decides which trees you see." },
    } })

Menus.AddLearn("armoury", { title = "Armoury & stock", group = "base", order = 10, col = PURPLE, needs = "armoury",
    sub = "Where kit comes from, and why it runs out", words = "stock resupply out of stock locker issued",
    blocks = {
        { "p", "E on an armoury, ammo cabinet, gear cabinet or specialist rack opens it next to your inventory. Drag out what you need; specialist racks only show what your role may take." },
        { "p", function()
            local L = Rhylib.Logistics
            if L and L.Cfg and L.Cfg("stockOn") then
                return "Every armoury on the map shares one stock per item: the corner of each shelf says how many are left. Hand back what you don't need. When something is out, carry an armoury resupply crate (two of you) to an armoury and set it down."
            end
            return "Armouries never run out on this server."
        end },
        { "p", "Issued gear dropped on the ground disappears after a few minutes. Claim a locker (E) to keep your own things between lives." },
    } })

Menus.AddLearn("building", { title = "Building & supplies", group = "base", order = 20, col = PURPLE, needs = "logistics",
    sub = "The E-tool, holograms, supply crates", words = "etool e-tool field kit repair crate structure snap barrier",
    blocks = {
        { "steps", {
            "Set down building supplies (from the gear cabinet) as a crate near where you want to build.",
            "With the E-tool, hold R for the build menu and pick a structure. E / Q turn it.",
            "RMB places a hologram; it takes its cost from a crate close by.",
            "Hold LMB on the hologram to build it (several builders are faster).",
            "The field kit repairs damaged structures (hold LMB on them).",
        } },
        { "p", "Z removes a structure you placed. Heavy crates need two to carry (E each)." },
    } })

Menus.AddLearn("post", { title = "Command post & call-ins", group = "base", order = 30, col = PURPLE, needs = "logistics",
    sub = "Supplies, sensors, tickets and orders", words = "garrison tickets clone squad call in sensor beacon",
    blocks = {
        { "p", "Press E on a command post: supplies nearby, the armoury stock running low, respawn and garrison tickets. Field technicians and officers also see the sensor arrays." },
        { "h", "Orders (officers)" },
        { "p", "Officers call in a clone squad, an armoury resupply crate, ammo crates or a medical crate. They arrive after a short delay; each has a cooldown for the whole server. A clone squad costs a garrison ticket per clone while tickets are on." },
        { "p", "Sensor kits set down beacons that sense droids nearby, through walls, and alert field technicians and officers." },
    } })
