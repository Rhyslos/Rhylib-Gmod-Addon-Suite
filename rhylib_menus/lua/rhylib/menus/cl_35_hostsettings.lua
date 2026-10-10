--[[
    Server settings page (pause menu, Staff group, superadmins).

    Left: Model overrides, Changed settings, then the modules grouped by
    category (Combat, Soldiers, Units & roles, NPCs, Server & interface,
    Other), each category folding open. Right: the chosen module, split
    into sections (chips on top: All or one section). Search looks through
    everything.

    Model settings (config module "models" from rhylib_core's model
    registry, and every setting whose default is a .mdl path) get a model
    row: picture, the path now, a box for a new path, Pick (the spawn
    window in pick mode), Apply, Reset. The server refuses paths it
    doesn't have; things already in the world keep the old model until a
    map change (the row and the page say so).

    Changes go through Rhylib.Settings (rhylib_core cl_15_settings.lua);
    the server checks the permission and the value, saves it and sends it
    to everyone. Reset = back to the host file's value or the default.

    Client only. One page: "serversettings" (Staff group, order 60), shown
    to holders of rhylib.settings (superadmin by default).
    Each catalogue entry from Rhylib.Settings.list has these fields:
      m module, k key, d default, b base (host file value or default),
      o override set in game (nil = none), s description, x meta
      ({ name, group } for model settings), p true = a model change that
      needs a map change.
    To give a new module its own place: add it to a category in
    CATEGORIES, a name in NAMES and, if it has many keys, SECTIONS.
    Modules in no category go under "Other".
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

-- Kept across rebuilds of the page.
local view = { kind = "models" }        -- { kind = "module", id } / "models" / "changed"
local section = {}                      -- [view key] = section title (nil = all)
local searchText = ""
local folded = {}                       -- [category id] = true when closed

--------------------------------------------------------------------------
-- How the page is organised
--------------------------------------------------------------------------

local CATEGORIES = {
    { id = "combat", title = "Combat", mods = { "weapons", "guns", "armor", "grapple", "eod" } },
    { id = "soldiers", title = "Soldiers", mods = { "stamina", "inventory", "gear", "jetpack", "medical", "skills" } },
    { id = "units", title = "Units & roles", mods = { "roster", "mp", "datapad", "radio", "chat", "training", "spawns" } },
    { id = "npcs", title = "NPCs", mods = { "droids" } },
    { id = "server", title = "Server & interface", mods = { "core", "hud", "menus", "thirdperson", "armoury", "toolgun", "admin" } },
}

local NAMES = {
    weapons = "Weapons", guns = "Gun stats", armor = "Armour", grapple = "Grapple hook", eod = "Bombs & mines (EOD)",
    stamina = "Stamina & weight", inventory = "Inventory", gear = "Wearable gear", jetpack = "Jetpack", medical = "Medical",
    skills = "Skills", roster = "Roster & ranks", mp = "Military police", datapad = "Datapad", radio = "Radio & squads",
    chat = "Chat", training = "Training", spawns = "Spawn points", droids = "Droids & clones", core = "Core", hud = "HUD",
    menus = "Menus", thirdperson = "Third person", armoury = "Armoury", toolgun = "Toolgun", admin = "Admin",
    models = "Model overrides",
}

-- Sections per module: { title, { Lua patterns matched against the key } };
-- the first section that matches wins. Model settings always go to
-- "Models"; anything unmatched to "Other".
local SECTIONS = {
    droids = {
        { "General", { "^maxActive$", "^aggression$", "^pathPerTick$", "^walkMult$", "^runSpread$", "^walkSpread$", "^moveSpread$", "^marchGroup$" } },
        { "Orders & areas", { "^guardRadius$", "^patrolRadius$", "^markerRadius$", "^brushRadius$", "^roamRadius$" } },
        { "B1 grenades", { "^b1Nade" } },
        { "B1 battle droids", { "^b1", "^e5" } },
        { "B2 rockets & mortars", { "^b2Rocket", "^b2Direct", "^b2Slow", "^b2Dive", "^arty" } },
        { "B2 super battle droids", { "^b2" } },
        { "Heavy & commander droids", { "^heavy", "^cmdHealth$", "^cmdRadius$", "^cmdSpread$", "^cmdReaction$", "^cmdPause$", "^cmdDeath" } },
        { "Cover & accuracy", { "^cover", "^blindSpread$", "^retreatFrac$", "^flash", "^settle", "^crowd" } },
        { "Retreat", { "^retreat", "^lastStand" } },
        { "Clone medics", { "^ctMedic", "^ctDown", "^reviveShield" } },
        { "Clone tactics", { "^ctCall", "^ctOdds", "^ctFallBackOdds$", "^ctChargeOdds$", "^ctCrouch", "^ctPopper" } },
        { "Clone troopers", { "^clone", "^ct", "^cmdFollowRadius$", "^cmdMaxFollowers$" } },
    },
    medical = {
        { "General", { "^enabled$", "^range$", "^selfMult$", "^noTarget$", "^markerRange$", "^viewRange$" } },
        { "Simplified system", { "^simpl" } },
        { "Downed & bleeding out", { "^bleedTime$", "^downHealth$", "^downGrace$", "^giveUpTime$", "^downSequences$" } },
        { "Revives", { "^reviveKit", "^firstAidRevive", "^handRevive", "^bloodPack" } },
        { "Kits & field items", { "^firstAid", "^medkit", "^splint", "^burnGel", "^pillTime$", "^painkiller" } },
        { "Dragging", { "^drag" } },
        { "Medic skills", { "^steadyMult$", "^quickReviveMult$", "^deepPockets$", "^efficientCare$", "^triageFlash$", "^regen" } },
        { "Injuries", { "^injuries$", "Bleed", "^fracture", "^fallFracture", "^recover$", "^burnRecover$", "^legNoSprint", "^armNoAim", "^armSpread$", "^burnSpread$", "^torso" } },
        { "Med bay, bacta tank & sofa", { "^medBay", "^tank", "^sofa" } },
        { "Chemistry bench", { "^bench", "^craftTime$", "^chemRecipes$" } },
        { "Illness", { "^loadRate$", "^illDrain$", "^poisonAfterDown$", "^drawTime$", "^scan", "^dose", "^strip", "^sampleLife$" } },
    },
    skills = {
        { "Points & rules", { "^freePoints$", "^startPoints$", "^commandRank$", "^onePath$", "^undoWindow$" } },
        { "Trooper", { "^quickHands", "^runGun", "^pointBlank", "^lightKit", "^momentum", "^extMag", "^effCells", "^loadBearer", "^cellRack$", "^gunRunner", "^steadySpread$", "^steadyRecoil$", "^rapidFire", "^overcharge", "^sustain" } },
        { "Marksman", { "^stanceSpread$", "^steadyAimSpread$", "^headhunter", "^boltDrills", "^longGun", "^carbine", "^calledShot", "^priority", "^rhythm", "^firstShot" } },
        { "Heavy", { "^reinforcedHealth$", "^planted", "^ammoBelt$", "^shotgun", "^juggernaut", "^suppress" } },
        { "Officer: pistol", { "^pistolSpread$", "^steadyGrip", "^dualRate$", "^crit", "^lightRounds", "^quickDraw", "^speedLoader", "^sidearm", "^sidestep", "^lightMagBonus$" } },
        { "Officer: marks & commander", { "^mark", "^visorSpot", "^squadSkillRange$", "^logiReload$", "^line", "^rifleDrill", "^vet" } },
        { "Command orders", { "^command", "^windRegen$", "^triage", "^focus", "^pressSprint$", "^presenceMult$", "^seasoned", "^standingTime$" } },
        { "Reinforcements & squad wheel", { "^reinf", "^squadSignal" } },
        { "Airborne", { "^rush", "^grenade", "^airborne", "^fallMult$", "^tankMult$", "^springJump$", "^hover", "^afterburner", "^combatDrop", "^blastMult$", "^airMult$", "^slam" } },
        { "Medic", { "^underFire" } },
        { "Shock Trooper", { "^holdLine", "^bash", "^searchMult$" } },
    },
    weapons = {
        { "Bolts & damage", { "^lagCompMax$", "^boltSpeedMult$", "^shotRange$", "^boltRange$", "^boltLife$", "^headMult$", "^limbMult$" } },
        { "Accuracy & recoil", { "^recoilMult$", "^crouchSpread$", "^firstShotMult$" } },
        { "Ammo & reloading", { "^reloadHoldTime$", "^maxMags$", "^maxCells$", "^lowCell" } },
        { "Explosion knockdown", { "^knock" } },
        { "Shields", { "^shield", "^cgShield", "^phalanx" } },
        { "Grenades & charges", { "^he", "^emp", "^breach", "^flash" } },
    },
    radio = {
        { "Radio", { "^localRange$", "^maxChannels$", "^hailTime$", "^squadNames$" } },
        { "Radio effects", { "^fx" } },
        { "Comms jammers", { "^jam" } },
        { "Squad pings", { "^ping" } },
    },
    gear = {
        { "Kit & unlocks", { "^kit$", "^unlocks$" } },
        { "Armour parts", { "^kama", "^pauldron", "^bareHeadshot" } },
        { "Helmet lights", { "^light" } },
        { "Sun visor", { "^visor" } },
        { "Night vision", { "^nv" } },
    },
    eod = {
        { "Explosions", { "^small", "^large", "^gas" } },
        { "Defusal rules", { "^sensorRange$", "^timerWake$", "^capDrain$", "^jumpers$", "^xray", "^inspectTime$", "^reach$", "^heat", "^torchTime$", "^leakTime$", "^hopEvery$", "^popperChance$" } },
        { "Interference device", { "^device" } },
        { "Mines", { "^ap", "^lap", "^mine" } },
    },
    mp = {
        { "Stun & baton", { "^stun", "^baton" } },
        { "Cuffs & escort", { "^cuff", "^escort" } },
        { "Searching", { "^search" } },
        { "Jail", { "^process", "^maxSentence$", "^jail", "^terminal", "^poses$" } },
        { "Property locker", { "^property" } },
    },
    inventory = {
        { "Size & weight", { "^width$", "^height$", "^baseCarry$", "^backpackWeightMult$", "^beltCells$" } },
        { "Dropped items", { "^worldItem", "^issuedDropLife$" } },
        { "Rules", { "^contraband$", "^giveRange$", "^autoHotbar$", "^combine", "^saveInterval$" } },
    },
    stamina = {
        { "Stamina", { "^max$", "^sprintDrain$", "^jumpCost$", "^regen", "^exhausted", "^lowAim" } },
        { "Carry weight", { "^maxPenalty", "^penaltyCurve$", "^heavy", "^overload" } },
    },
    jetpack = {
        { "Fuel", { "^fuel", "^recharge", "^unlockAt$", "^loadFuelMult$", "^hoverFuel$" } },
        { "Flight", { "." } },
    },
    datapad = {
        { "Notes & logs", { "^noteLimit$", "^titleMax$", "^bodyMax$", "^logCap$", "^medCap$" } },
        { "Quick response calls", { "^calls$", "^supplyItems$", "^call" } },
        { "Unit & personnel", { "^strike", "^arrestRange$", "^useRange$", "^class$" } },
    },
    armoury = {
        { "Stock", { "^weapons$", "^trainingWeapons$", "^gearStock$", "^medCrate$", "^roles$" } },
        { "Storage sizes", { "^locker", "^crate" } },
        { "Training deposit", { "^deposit" } },
    },
}

local function prettyKey(k)
    local s = string.gsub(k, "(%l)(%u)", "%1 %2")
    s = string.gsub(s, "(%a)(%d)", "%1 %2")
    s = string.gsub(s, "_", " ")
    return string.upper(string.sub(s, 1, 1)) .. string.lower(string.sub(s, 2))
end

local function prettyModule(m)
    return NAMES[m] or (string.upper(string.sub(m, 1, 1)) .. string.sub(m, 2))
end

local function isModelEntry(e)
    if e.m == "models" then return true end
    local d = e.d
    return isstring(d) and string.lower(string.sub(d, -4)) == ".mdl"
end

-- Gun stats keys are "<class>_<stat>": one section per gun.
local function gunSection(k)
    local class = string.match(k, "^(.-)_[^_]+$")
    if not class then return "Other" end
    local w = weapons.GetStored(class)
    return (w and w.PrintName) or class
end

local function sectionOf(e)
    if e.m == "models" then return (e.x and e.x.group) or "Other" end
    if isModelEntry(e) then return "Models" end
    if e.m == "guns" then return gunSection(e.k) end
    local list = SECTIONS[e.m]
    if not list then return "General" end
    for _, s in ipairs(list) do
        for _, pat in ipairs(s[2]) do
            if string.find(e.k, pat) then return s[1] end
        end
    end
    return "Other"
end

-- A value as short text for the "Default ... · host file ..." line.
local function show(v)
    if v == nil then return "none" end
    if isbool(v) then return v and "on" or "off" end
    if isnumber(v) then return tostring(math.Round(v, 4)) end
    if isstring(v) then return v == "" and "(empty)" or ('"' .. v .. '"') end
    if isvector(v) or isangle(v) then return string.format("%g %g %g", v[1], v[2], v[3]) end
    if istable(v) then
        local j = util.TableToJSON(v) or "?"
        if #j > 60 then j = string.sub(j, 1, 57) .. "..." end
        return j
    end
    return tostring(v)
end

-- The value in use: the in-game override, else the host file / default.
local function current(e)
    if e.o ~= nil then return e.o end
    return e.b
end

local function titleOf(e)
    if e.x and e.x.name then return e.x.name end
    return prettyKey(e.k)
end

-- (asked every frame by the rows: remembered for a few seconds)
local gameHas = {}
local function onYourGame(m)
    if not (isstring(m) and m ~= "") then return false end
    local c = gameHas[m]
    local now = RealTime()
    if c and c.t > now then return c.v end
    local v = util.IsValidModel(m) or file.Exists(m, "GAME")
    gameHas[m] = { v = v, t = now + 5 }
    return v
end

--------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------

-- The control for one plain entry, in holder. Returns a refresh function.
-- The type of the default decides the control: bool = toggle; number,
-- string, table (JSON), Vector / Angle ("x y z") = a text box applied on
-- Enter (red outline and a buzz when it can't be read).
local function control(holder, e)
    local S = Rhylib.Settings
    local d = e.d
    if isbool(d) then
        local t = K.Toggle(holder, function() return current(e) == true end, function(v) S.Set(e.m, e.k, v) end)
        t:Dock(RIGHT)
        return function() end
    end
    if d == nil then return function() end end

    local entry = K.TextEntry(holder, istable(d) and "JSON" or ((isvector(d) or isangle(d)) and "x y z" or ""))
    entry:Dock(FILL)
    local function text()
        local v = current(e)
        if istable(v) then return util.TableToJSON(v) or "" end
        if isnumber(v) then return tostring(math.Round(v, 6)) end
        if isvector(v) or isangle(v) then return string.format("%g %g %g", v[1], v[2], v[3]) end
        return tostring(v == nil and "" or v)
    end
    entry:SetText(text())
    entry.bad = false
    local paint = entry.Paint
    function entry:Paint(w, h)
        paint(self, w, h)
        if self.bad then
            surface.SetDrawColor(C.bad)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
    end
    function entry:OnChange() self.bad = false end
    function entry:OnEnter()
        local raw = self:GetValue()
        local v
        if isnumber(d) then
            v = tonumber(raw)
            if v and (v ~= v or v == math.huge or v == -math.huge) then v = nil end
        elseif isstring(d) then
            v = raw
        elseif istable(d) then
            v = util.JSONToTable(raw)
        elseif isvector(d) or isangle(d) then
            local a, b, c = string.match(raw, "^%s*(%S+)[%s,]+(%S+)[%s,]+(%S+)%s*$")
            a, b, c = tonumber(a), tonumber(b), tonumber(c)
            if a and b and c then v = isvector(d) and Vector(a, b, c) or Angle(a, b, c) end
        end
        if v == nil then
            self.bad = true
            surface.PlaySound("buttons/button10.wav")
            return
        end
        self.bad = false
        S.Set(e.m, e.k, v)
    end
    return function()
        if not entry:HasFocus() then
            entry:SetText(text())
            entry.bad = false
        end
    end
end

local function rowFrame(parent, e, tall)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:DockMargin(0, 0, K.S(10), K.S(4))
    row.minTall = tall
    function row:PaintFrame(w, h)
        surface.SetDrawColor(e.o ~= nil and C.rowAlt or C.row)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        if e.o ~= nil then
            surface.SetDrawColor(C.accent)
            surface.DrawRect(0, 0, K.S(3), h)
        end
    end
    return row
end

-- A plain setting row: title + raw key, description, default / host file
-- line on the left; control and Reset on the right. Grows with its text.
local function makeRow(parent, e, refreshers, showModule)
    local row = rowFrame(parent, e, K.S(70))
    row:DockPadding(K.S(12), K.S(28), K.S(12), K.S(8))
    local title = prettyKey(e.k)
    local tag = showModule and (prettyModule(e.m) .. " · " .. e.k) or e.k
    function row:Paint(w, h)
        self:PaintFrame(w, h)
        draw.SimpleText(title, K.Font(14, 600), K.S(12), K.S(8), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        surface.SetFont(K.Font(14, 600))
        local tw = surface.GetTextSize(title)
        draw.SimpleText(tag, K.Font(11), K.S(20) + tw, K.S(10), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    row.right = vgui.Create("DPanel", row)
    row.right:Dock(RIGHT)
    row.right:SetWide(K.S(300))
    row.right:DockMargin(K.S(12), 0, 0, 0)
    row.right.Paint = nil
    local holder = vgui.Create("DPanel", row.right)
    holder:Dock(TOP)
    holder:SetTall(K.S(30))
    holder.Paint = nil
    local reset = K.Button(holder, "Reset", function() Rhylib.Settings.Set(e.m, e.k, nil) end,
        { small = true, danger = true, enabled = function() return e.o ~= nil end,
          tooltip = "Back to the host file's value, or the default" })
    reset:Dock(RIGHT)
    reset:SetWide(K.S(70))
    reset:DockMargin(K.S(8), 0, 0, 0)
    local refresh = control(holder, e)

    local left = vgui.Create("DPanel", row)
    left:Dock(FILL)
    left.Paint = nil
    local desc = K.Label(left, e.s ~= "" and e.s or "(no description)", 13, nil, C.label)
    desc:Dock(TOP)
    local vals = vgui.Create("DPanel", left)
    vals:Dock(TOP)
    vals:SetTall(K.S(18))
    vals:DockMargin(0, K.S(4), 0, 0)
    function vals:Paint(w, h)
        local s = "Default " .. show(e.d)
        if e.b ~= e.d and not (istable(e.b) and istable(e.d)) then s = s .. "   ·   host file " .. show(e.b) end
        if e.o ~= nil then s = s .. "   ·   changed here" end
        draw.SimpleText(K.Fit(s, K.Font(12), w), K.Font(12), 0, h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    function row:Think()
        local want = math.max(K.S(28) + desc:GetTall() + K.S(4) + vals:GetTall() + K.S(8), self.minTall)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    refreshers[e.m .. "\0" .. e.k] = refresh
    return row
end

-- Model pictures are made a couple a frame, only once a row is seen
-- (each one renders a spawn icon the first time).
local picQueue = {}
local function queuePic(p) picQueue[#picQueue + 1] = p end
Rhylib.Hook.Add("Think", "menus.hostsettings.pics", function()
    if #picQueue == 0 then return end
    for _ = 1, 2 do
        local p = table.remove(picQueue, 1)
        if not p then break end
        if IsValid(p) and p.wantModel then p:Build() end
    end
end)

local function modelPicture(parent)
    local pic = vgui.Create("DPanel", parent)
    pic.Paint = function(self, w, h)
        surface.SetDrawColor(C.header)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(self.preview and C.warn or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        if not self.queued and self.wantModel and self.failedFor ~= self.wantModel
            and not (IsValid(self.mi) and self.builtFor == self.wantModel) then
            self.queued = true
            queuePic(self)
        end
        if not IsValid(self.mi) then
            draw.SimpleText(self.wantModel and "..." or "?", K.Font(13), w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    function pic:PaintOver(w, h)
        if self.preview then
            draw.SimpleText("PREVIEW", K.Font(9, 700), w * 0.5, h - K.S(2), C.warn, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
        end
    end
    function pic:Build()
        self.queued = false
        local m = self.wantModel
        if m == self.builtFor and IsValid(self.mi) then return end
        if IsValid(self.mi) then self.mi:Remove() end
        if not onYourGame(m) then
            self.failedFor = m   -- (not queued again until the wanted model changes)
            return
        end
        util.PrecacheModel(m)
        local mi = vgui.Create("ModelImage", self)
        mi:SetMouseInputEnabled(false)
        mi:SetModel(m)
        local pad = K.S(3)
        mi:SetPos(pad, pad)
        mi:SetSize(self:GetWide() - pad * 2, self:GetTall() - pad * 2)
        self.mi = mi
        self.builtFor = m
    end
    function pic:SetWant(m, preview)
        self.preview = preview
        if m == self.wantModel then return end
        self.wantModel = m
        self.failedFor = nil
        self.queued = false
        if IsValid(self.mi) and self.builtFor ~= m then self.mi:Remove() end
    end
    -- (hover: the spawn window's big turning preview, if it's there)
    function pic:OnCursorEntered()
        local SP = Menus.Spawn
        if SP and SP.Preview and onYourGame(self.wantModel) then
            SP.Preview(self, { model = self.wantModel, title = string.GetFileFromFilename(self.wantModel), sub = self.wantModel })
        end
    end
    pic:SetMouseInputEnabled(true)
    return pic
end

-- A model setting row: picture, title, "Now:" / "Ships with" lines, and a
-- path box with Pick / Apply / Reset and a status line. The picture shows
-- the typed path (marked PREVIEW) while it is a real model on your game.
local function makeModelRow(parent, e, refreshers, showModule)
    local S = Rhylib.Settings
    local row = rowFrame(parent, e, K.S(124))
    local pad = K.S(10)
    local picSize = K.S(84)
    row:DockPadding(pad + picSize + K.S(12), K.S(30), K.S(12), K.S(8))
    local title = titleOf(e)
    local tag
    if e.m == "models" then
        tag = showModule and ("Model · " .. ((e.x and e.x.group) or "")) or ""
    else
        tag = (showModule and (prettyModule(e.m) .. " · ") or "") .. e.k
    end

    local pic = modelPicture(row)
    pic:SetPos(pad, pad)
    pic:SetSize(picSize, picSize)

    function row:Paint(w, h)
        self:PaintFrame(w, h)
        local x = pad + picSize + K.S(12)
        draw.SimpleText(title, K.Font(14, 600), x, K.S(8), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        surface.SetFont(K.Font(14, 600))
        local tw = surface.GetTextSize(title)
        draw.SimpleText(tag, K.Font(11), x + tw + K.S(8), K.S(10), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    row.right = vgui.Create("DPanel", row)
    row.right:Dock(RIGHT)
    row.right:SetWide(K.S(380))
    row.right:DockMargin(K.S(12), 0, 0, 0)
    row.right.Paint = nil
    local holder = vgui.Create("DPanel", row.right)
    holder:Dock(TOP)
    holder:SetTall(K.S(30))
    holder.Paint = nil
    local entry = K.TextEntry(holder, "models/folder/name.mdl")
    local status = vgui.Create("DPanel", row.right)
    status:Dock(TOP)
    status:SetTall(K.S(20))
    status:DockMargin(0, K.S(4), 0, 0)
    local btns = vgui.Create("DPanel", row.right)
    btns:Dock(TOP)
    btns:SetTall(K.S(26))
    btns:DockMargin(0, K.S(2), 0, 0)
    btns.Paint = nil

    local function typed() return string.Trim((string.gsub(entry:GetValue() or "", "\\", "/"))) end
    local function apply()
        local v = typed()
        if v == "" or v == current(e) then return end
        if not string.match(string.lower(v), "%.mdl$") then
            entry.bad = true
            surface.PlaySound("buttons/button10.wav")
            return
        end
        entry.bad = false
        S.Set(e.m, e.k, v)
    end
    local reset = K.Button(btns, "Reset", function() S.Set(e.m, e.k, nil) end,
        { small = true, danger = true, enabled = function() return e.o ~= nil end, tooltip = "Back to the model it ships with (or the host file's)" })
    reset:Dock(RIGHT)
    reset:SetWide(K.S(70))
    local applyB = K.Button(btns, "Apply", apply,
        { small = true, accent = true, enabled = function() local v = typed() return v ~= "" and v ~= current(e) end })
    applyB:Dock(RIGHT)
    applyB:SetWide(K.S(70))
    applyB:DockMargin(0, 0, K.S(6), 0)
    local pick = K.Button(btns, "Pick from the spawn menu", function()
        local SP = Menus.Spawn
        if not (SP and SP.PickModel) then return end
        SP.PickModel(function(m)
            if IsValid(entry) then
                entry:SetText((string.gsub(m, "\\", "/")))
                entry.bad = false
            end
        end, title)
    end, { small = true, enabled = function() return Menus.Spawn and Menus.Spawn.PickModel ~= nil end,
        tooltip = "Opens the spawn window: click any model (props, addons, entities) to put its path here, then Apply" })
    pick:Dock(FILL)
    pick:DockMargin(0, 0, K.S(6), 0)

    entry:Dock(FILL)
    entry:SetText(tostring(current(e) or ""))
    entry.bad = false
    local paint = entry.Paint
    function entry:Paint(w, h)
        paint(self, w, h)
        if self.bad then
            surface.SetDrawColor(C.bad)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
    end
    function entry:OnChange() self.bad = false end
    function entry:OnEnter() apply() end

    -- What the box says about the typed path.
    function status:Paint(w, h)
        local v = typed()
        local txt, col
        if v ~= "" and v ~= current(e) then
            if onYourGame(v) then txt, col = "Not applied yet: press Apply (or Enter)", C.warn
            else txt, col = "Not found on your game: check the path, and that its addon is installed", C.bad end
        elseif e.p then
            txt, col = "Changed: things already in the world keep the old model until a map change", C.warn
        elseif not onYourGame(current(e)) then
            txt, col = "This model isn't on your game (its addon may be missing)", C.bad
        end
        if txt then draw.SimpleText(K.Fit(txt, K.Font(11), w), K.Font(11), 0, h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    end

    local left = vgui.Create("DPanel", row)
    left:Dock(FILL)
    left.Paint = nil
    local descText = (e.m ~= "models" and e.s ~= "") and e.s or nil
    local desc = descText and K.Label(left, descText, 13, nil, C.label)
    if desc then desc:Dock(TOP) end
    local vals = vgui.Create("DPanel", left)
    vals:Dock(TOP)
    vals:SetTall(K.S(36))
    vals:DockMargin(0, K.S(2), 0, 0)
    function vals:Paint(w, h)
        local cur = tostring(current(e) or "")
        draw.SimpleText(K.Fit("Now: " .. cur, K.Font(12), w), K.Font(12), 0, K.S(9), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local s = "Ships with " .. tostring(e.d)
        if e.b ~= e.d then s = s .. "   ·   host file " .. tostring(e.b) end
        draw.SimpleText(K.Fit(s, K.Font(11), w), K.Font(11), 0, K.S(27), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    function row:Think()
        local want = K.S(30) + (desc and (desc:GetTall() + K.S(2)) or 0) + vals:GetTall() + K.S(12)
        want = math.max(want, self.minTall)
        if self:GetTall() ~= want then self:SetTall(want) end
        -- picture: the typed path while it's a real model, else the current one
        local v = typed()
        if v ~= "" and v ~= current(e) and onYourGame(v) then pic:SetWant(v, true) else pic:SetWant(current(e), false) end
    end
    refreshers[e.m .. "\0" .. e.k] = function()
        if not entry:HasFocus() then
            entry:SetText(tostring(current(e) or ""))
            entry.bad = false
        end
    end
    return row
end

local function addRow(parent, e, refreshers, showModule)
    if isModelEntry(e) then return makeModelRow(parent, e, refreshers, showModule) end
    return makeRow(parent, e, refreshers, showModule)
end

local function matches(e, q)
    if q == "" then return true end
    q = string.lower(q)
    local function has(s) return s and string.find(string.lower(s), q, 1, true) end
    return has(e.k) or has(prettyKey(e.k)) or has(e.s) or has(e.m) or has(prettyModule(e.m))
        or has(e.x and e.x.name) or has(e.x and e.x.group) or (isModelEntry(e) and has(tostring(current(e))))
end

--------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------

local function viewKey(v) return v.kind .. ":" .. tostring(v.id or "") end

-- The page: search bar on top, side bar (views and modules) on the left,
-- a header (title, map-change bar, section chips) and the rows on the right.
local function build(page)
    local S = Rhylib.Settings
    if not S then
        K.Label(page, "The settings service isn't loaded (rhylib_core is too old).", 14, nil, C.bad):Dock(TOP)
        return
    end

    local top = vgui.Create("DPanel", page)
    top:Dock(TOP)
    top:SetTall(K.S(30))
    top:DockMargin(0, 0, 0, K.S(6))
    top.Paint = nil
    local search = K.TextEntry(top, "Search all settings and models...")
    search:Dock(LEFT)
    search:SetWide(K.S(320))
    search:SetText(searchText)
    search:SetUpdateOnType(true)
    local note = K.Label(top, "Enter applies a value. Most changes apply at once; models and a few others after a map change. "
        .. "Changes are saved and win over the host config files.", 12, nil, C.textDim)
    note:Dock(FILL)
    note:DockMargin(K.S(12), 0, 0, 0)
    note:SetAutoStretchVertical(false)
    note:SetContentAlignment(4)

    local side = K.Scroll(page)
    side:Dock(LEFT)
    side:SetWide(K.S(220))
    side:DockMargin(0, 0, K.S(10), 0)
    local right = vgui.Create("DPanel", page)
    right:Dock(FILL)
    right.Paint = nil
    local head = vgui.Create("DPanel", right)
    head:Dock(TOP)
    head:SetTall(K.S(10))
    head:DockMargin(0, 0, K.S(10), K.S(6))
    head.Paint = nil
    local body = K.Scroll(right)
    body:Dock(FILL)

    local refreshers = {}
    local fill

    local function entriesOf(pred)
        local out = {}
        for _, e in ipairs(S.list or {}) do
            if pred(e) then out[#out + 1] = e end
        end
        return out
    end
    local function modules()
        local seen = {}
        for _, e in ipairs(S.list or {}) do
            if e.m ~= "models" then seen[e.m] = true end
        end
        return seen
    end
    local function countChanged(pred)
        local n = 0
        for _, e in ipairs(S.list or {}) do
            if e.o ~= nil and pred(e) then n = n + 1 end
        end
        return n
    end
    local function pendingCount()
        local n = 0
        for _, e in ipairs(S.list or {}) do
            if e.p then n = n + 1 end
        end
        return n
    end

    local function choose(v)
        view = v
        search:SetText("")
        searchText = ""
        fill()
    end

    local function sideButton(label, v, indent)
        local b = K.Button(side, label, function() choose(v) end,
            { align = "left", small = true, selected = function() return searchText == "" and viewKey(view) == viewKey(v) end })
        b:Dock(TOP)
        b:DockMargin(indent and K.S(12) or 0, 0, K.S(8), K.S(3))
        return b
    end

    local function buildSide()
        side:Clear()
        local has = modules()
        local b = sideButton(function()
            local n = countChanged(function(e) return isModelEntry(e) end)
            return "Model overrides" .. (n > 0 and ("  (" .. n .. ")") or "")
        end, { kind = "models" })
        b.opts.accent = true
        sideButton(function()
            local n = countChanged(function(e) return true end)
            return "Changed settings" .. ("  (" .. n .. ")")
        end, { kind = "changed" })

        local placed = {}
        local cats = {}
        for _, c in ipairs(CATEGORIES) do
            local mods = {}
            for _, m in ipairs(c.mods) do
                if has[m] then mods[#mods + 1] = m placed[m] = true end
            end
            if #mods > 0 then cats[#cats + 1] = { id = c.id, title = c.title, mods = mods } end
        end
        local other = {}
        for m in pairs(has) do if not placed[m] then other[#other + 1] = m end end
        table.sort(other)
        if #other > 0 then cats[#cats + 1] = { id = "other", title = "Other", mods = other } end

        for _, c in ipairs(cats) do
            local h = vgui.Create("DButton", side)
            h:SetText("")
            h:Dock(TOP)
            h:SetTall(K.S(24))
            h:DockMargin(0, K.S(8), K.S(8), K.S(3))
            function h:Paint(w, hh)
                local n = countChanged(function(e) for _, m in ipairs(c.mods) do if e.m == m then return true end end return false end)
                draw.SimpleText((folded[c.id] and "+ " or "- ") .. string.upper(c.title), K.Font(12, 700), 0, hh * 0.5,
                    self:IsHovered() and C.text or C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if n > 0 then draw.SimpleText(tostring(n), K.Font(11, 700), w, hh * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
                surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 60)
                surface.DrawRect(0, hh - 1, w, 1)
                return true
            end
            function h:DoClick()
                folded[c.id] = not folded[c.id]
                buildSide()
            end
            if not folded[c.id] then
                for _, m in ipairs(c.mods) do
                    sideButton(function()
                        local n = countChanged(function(e) return e.m == m end)
                        return prettyModule(m) .. (n > 0 and ("  (" .. n .. ")") or "")
                    end, { kind = "module", id = m }, true)
                end
            end
        end
    end

    -- Header: title, a pending-map-change bar, and the section chips.
    local function buildHead(title, sub, sections, key)
        head:Clear()
        local h = K.S(30)
        local t = vgui.Create("DPanel", head)
        t:Dock(TOP)
        t:SetTall(K.S(30))
        function t:Paint(w, hh)
            draw.SimpleText(string.upper(title), K.Font(18, 800), 0, hh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if sub then
                surface.SetFont(K.Font(18, 800))
                local tw = surface.GetTextSize(string.upper(title))
                draw.SimpleText(K.Fit(sub, K.Font(12), w - tw - K.S(16)), K.Font(12), tw + K.S(12), hh * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
        local pend = pendingCount()
        if pend > 0 then
            local bar = vgui.Create("DPanel", head)
            bar:Dock(TOP)
            bar:SetTall(K.S(30))
            bar:DockMargin(0, K.S(4), 0, 0)
            h = h + K.S(34)
            function bar:Paint(w, hh)
                surface.SetDrawColor(C.warn.r, C.warn.g, C.warn.b, 30)
                surface.DrawRect(0, 0, w, hh)
                surface.SetDrawColor(C.warn)
                surface.DrawRect(0, 0, K.S(3), hh)
                draw.SimpleText(pendingCount() .. " model change" .. (pendingCount() == 1 and "" or "s")
                    .. " this map: new spawns use them now, things already placed after a map change",
                    K.Font(12, 600), K.S(12), hh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local A = Rhylib.Admin
            if A and A.Run and A.Has and A.Has(LocalPlayer(), "map") then
                local armed = 0
                local rb = K.Button(bar, function()
                    return CurTime() < armed and "Click again: restart" or "Restart map"
                end, function()
                    if CurTime() < armed then
                        A.Run("restartmap", {})
                        armed = 0
                    else
                        armed = CurTime() + 3
                    end
                end, { small = true, danger = true, tooltip = "Reloads this map after a 10 s countdown (everyone is told)" })
                rb:Dock(RIGHT)
                rb:SetWide(K.S(150))
                rb:DockMargin(0, K.S(2), K.S(2), K.S(2))
            end
        end
        local baseH = h
        if sections and #sections > 1 then
            local chips = vgui.Create("DPanel", head)
            chips:Dock(TOP)
            chips:DockMargin(0, K.S(6), 0, 0)
            chips.Paint = nil
            local list = { false }
            for _, s in ipairs(sections) do list[#list + 1] = s end
            local btns = {}
            for _, s in ipairs(list) do
                local label = s or "All"
                local b = K.Button(chips, label, function()
                    section[key] = s or nil
                    fill()
                end, { small = true, selected = function() return (section[key] or false) == s end })
                b.chipLabel = label
                btns[#btns + 1] = b
            end
            function chips:PerformLayout(w)
                local x, y, bh, gap = 0, 0, K.S(26), K.S(4)
                for _, b in ipairs(btns) do
                    surface.SetFont(K.Font(12, 700))
                    local bw = surface.GetTextSize(string.upper(b.chipLabel)) + K.S(28)
                    if x > 0 and x + bw > w then x, y = 0, y + bh + gap end
                    b:SetPos(x, y)
                    b:SetSize(bw, bh)
                    x = x + bw + gap
                end
                local want = y + bh
                if self:GetTall() ~= want then
                    self:SetTall(want)
                    head:SetTall(baseH + K.S(6) + want)
                end
            end
            chips:SetTall(K.S(26))
            h = baseH + K.S(32)
        end
        head:SetTall(h)
    end

    local function heading(text, col)
        local hd = K.Heading(body, text, col)
        hd:Dock(TOP)
        hd:DockMargin(0, K.S(8), K.S(10), K.S(6))
    end
    local function empty(text)
        K.Label(body, text, 14, nil, C.textDim):Dock(TOP)
    end

    -- Entries split into sections in a stable order (the module's own
    -- order, then Other, then Models).
    local function grouped(list, orderFor)
        local by, order = {}, {}
        for _, e in ipairs(list) do
            local s = sectionOf(e)
            if not by[s] then by[s] = {} order[#order + 1] = s end
            table.insert(by[s], e)
        end
        if orderFor then
            local rank = {}
            for i, s in ipairs(orderFor) do rank[s] = i end
            table.sort(order, function(a, b)
                local ra = rank[a] or (a == "Models" and 10000 or (a == "Other" and 9999 or 5000))
                local rb = rank[b] or (b == "Models" and 10000 or (b == "Other" and 9999 or 5000))
                if ra ~= rb then return ra < rb end
                return a < b
            end)
        else
            table.sort(order)
        end
        return by, order
    end

    local MAX_ROWS = 250

    fill = function()
        body:Clear()
        refreshers = {}
        if not S.list then
            buildHead("Loading", nil)
            empty("Loading settings...")
            return
        end
        if #S.list == 0 then
            buildHead("Server settings", nil)
            empty("Nothing to show: you may not have the rhylib.settings permission.")
            return
        end

        local q = searchText
        if q ~= "" then
            local list = entriesOf(function(e) return matches(e, q) end)
            buildHead("Search", #list .. " match" .. (#list == 1 and "" or "es") .. " for \"" .. q .. "\"")
            local lastM
            for i, e in ipairs(list) do
                if i > MAX_ROWS then empty("More matches: narrow the search.") break end
                if e.m ~= lastM then
                    lastM = e.m
                    heading(prettyModule(e.m))
                end
                addRow(body, e, refreshers, false)
            end
            if #list == 0 then empty("Nothing matches.") end
            return
        end

        local key = viewKey(view)
        if view.kind == "models" then
            -- Every model: the registry's ("models") and model settings of
            -- every module, by group.
            local list = entriesOf(isModelEntry)
            local by, order = {}, {}
            for _, e in ipairs(list) do
                local g = e.m == "models" and ((e.x and e.x.group) or "Other") or ("Settings: " .. prettyModule(e.m))
                if not by[g] then by[g] = {} order[#order + 1] = g end
                table.insert(by[g], e)
            end
            table.sort(order)
            for _, g in ipairs(order) do
                table.sort(by[g], function(a, b) return titleOf(a) < titleOf(b) end)
            end
            buildHead("Model overrides", "Swap any model the suite uses for one you have installed. Hover a picture to turn it.", order, key)
            local only = section[key]
            if only and not by[only] then only = nil section[key] = nil end
            local n = 0
            for _, g in ipairs(order) do
                if not only or only == g then
                    if n + #by[g] > MAX_ROWS and n > 0 then
                        empty("More models below: pick a group above to see them.")
                        break
                    end
                    heading(g)
                    for _, e in ipairs(by[g]) do
                        n = n + 1
                        addRow(body, e, refreshers, false)
                    end
                end
            end
            if #list == 0 then empty("No models found yet: the list fills in once the map has loaded.") end
            return
        end

        if view.kind == "changed" then
            local list = entriesOf(function(e) return e.o ~= nil end)
            buildHead("Changed settings", #list .. " changed here (Reset puts one back)")
            local lastM
            for _, e in ipairs(list) do
                if e.m ~= lastM then
                    lastM = e.m
                    heading(prettyModule(e.m))
                end
                addRow(body, e, refreshers, false)
            end
            if #list == 0 then empty("Nothing has been changed from the server settings page yet.") end
            return
        end

        -- A module.
        local m = view.id
        local list = entriesOf(function(e) return e.m == m end)
        if #list == 0 then
            view = { kind = "models" }
            return fill()
        end
        local wanted
        if SECTIONS[m] then
            wanted = {}
            for _, s in ipairs(SECTIONS[m]) do wanted[#wanted + 1] = s[1] end
        end
        local by, order = grouped(list, wanted)
        local n = 0
        for _ in pairs(by) do n = n + 1 end
        buildHead(prettyModule(m), #list .. " setting" .. (#list == 1 and "" or "s"), order, key)
        local only = section[key]
        if only and not by[only] then only = nil section[key] = nil end
        for _, s in ipairs(order) do
            if not only or only == s then
                if n > 1 then heading(s) end
                for _, e in ipairs(by[s]) do addRow(body, e, refreshers, false) end
            end
        end
    end

    function search:OnValueChange(v)
        if v == searchText then return end
        searchText = v
        fill()
    end

    -- (only while this page is open: the panels own the callbacks)
    S.onList = function()
        if not IsValid(body) then return end
        buildSide()
        fill()
    end
    S.onChanged = function(m, k)
        if not IsValid(body) then return end
        -- (the map-change bar, the Changed list and the counts follow a change)
        local modelChange = false
        for _, e in ipairs(S.list or {}) do
            if e.m == m and e.k == k then modelChange = isModelEntry(e) break end
        end
        if modelChange or view.kind == "changed" then
            timer.Create("Rhylib.Menus.SettingsRefill", 0.1, 1, function()
                if not (IsValid(body) and searchText == "") then return end
                local y = body:GetVBar():GetScroll()
                fill()
                timer.Simple(0, function() if IsValid(body) then body:GetVBar():SetScroll(y) end end)
            end)
        end
        local r = refreshers[m .. "\0" .. k]
        if r then r() end
    end

    if S.list then buildSide() end
    fill()
    S.Request()   -- (always fresh: base values may differ from last time)
end

Menus.AddPage("serversettings", {
    title = "Server settings",
    order = 60,
    group = "staff",
    visible = function()
        local me = LocalPlayer()
        if not IsValid(me) then return false end
        local A = Rhylib.Admin
        if A and A.Has then return A.Has(me, "rhylib.settings", "superadmin") end
        return me:IsSuperAdmin()
    end,
    build = build,
})
