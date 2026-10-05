--[[
    Killfeed: replaces the default death notices (top right). Each line is
    a small plate: killer (job colour), weapon, victim (job colour). Lines
    you're in get an accent outline. They stay killfeedTime seconds.

    The game still sends its normal death notice messages; this only
    changes how they're shown (GAMEMODE.AddDeathNotice / DrawDeathNotice).
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

local feed = {}
local COL_NPC = Color(200, 170, 120)
local col = Color(0, 0, 0)  -- reused while drawing

-- Newer GMod passes entities here (players, NPCs) instead of names.
local function niceName(s)
    if not s or s == "" then return "" end
    if not isstring(s) then
        if not IsValid(s) then return "" end
        if s:IsPlayer() then return s:Nick() end
        local n = s.PrintName
        if isstring(n) and n ~= "" then s = n else s = "#" .. s:GetClass() end
    end
    if string.sub(s, 1, 1) == "#" then return language.GetPhrase(string.sub(s, 2)) end
    return s
end

local WORLD = { worldspawn = "World", trigger_hurt = "World", env_fire = "Fire", entityflame = "Fire",
    prop_physics = "Prop", prop_physics_multiplayer = "Prop", func_physbox = "Prop", env_explosion = "Explosion",
    player = "Fists", suicide = "Suicide" }

-- A weapon or entity class as a readable name (cached).
local weaponNames = {}
local function weaponName(class)
    class = class or ""
    local cached = weaponNames[class]
    if cached then return cached end
    local name = WORLD[class]
    if not name then
        local stored = weapons.GetStored(class)
        if stored and stored.PrintName and stored.PrintName ~= "" then name = stored.PrintName end
    end
    if not name then
        local ent = scripted_ents.GetStored(class)
        if ent and ent.t and ent.t.PrintName then name = ent.t.PrintName end
    end
    if not name then
        local phrase = language.GetPhrase(class)
        if phrase ~= class then name = phrase end
    end
    if not name then
        name = string.gsub(string.gsub(class, "^weapon_", ""), "_", " ")
        name = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
    end
    weaponNames[class] = name
    return name
end

local function teamCol(t)
    if not t or t < 0 then return COL_NPC end
    return team.GetColor(t)
end

function Menus.AddKill(attacker, attackerTeam, inflictor, victim, victimTeam)
    attacker, victim = niceName(attacker), niceName(victim)
    if not isstring(inflictor) then inflictor = IsValid(inflictor) and inflictor:GetClass() or "" end
    local me = IsValid(LocalPlayer()) and LocalPlayer():Nick()
    local line = {
        time = RealTime(),
        attacker = attacker ~= victim and attacker or nil,
        aCol = teamCol(attackerTeam),
        weapon = weaponName(inflictor),
        victim = victim,
        vCol = teamCol(victimTeam),
        mine = me ~= nil and (attacker == me or victim == me),
    }
    if line.attacker == "" then line.attacker = nil end
    if not line.attacker then line.weapon = (inflictor == "worldspawn" or inflictor == "trigger_hurt") and "Fell" or (inflictor == "" and "Died" or weaponName(inflictor)) end
    table.insert(feed, 1, line)
    local max = Rhylib.Config.Get("menus", "killfeedMax") or 6
    for i = #feed, max + 1, -1 do feed[i] = nil end
end

local function take()
    local gm = GAMEMODE or GM
    if not gm then return end
    gm.AddDeathNotice = function(self, attacker, attackerTeam, inflictor, victim, victimTeam)
        -- DarkRP's "showdeaths" setting can turn death notices off.
        if self.Config and self.Config.showdeaths == false then return end
        Menus.AddKill(attacker, attackerTeam, inflictor, victim, victimTeam)
    end
    gm.DrawDeathNotice = function() end
end
Rhylib.Hook.Add("Initialize", "menus.killfeed", take)
Rhylib.Hook.Add("InitPostEntity", "menus.killfeed", take)
take()

Rhylib.Hook.Add("HUDPaint", "menus.killfeed", function()
    if #feed == 0 then return end
    local s = K.S
    local life = Rhylib.Config.Get("menus", "killfeedTime") or 6
    local now = RealTime()
    local HUD = Rhylib.HUD
    local visor = HUD and HUD.VisorActive and HUD.VisorActive()
    local x1 = ScrW() - s(24)
    local y = visor and math.floor(ScrH() * 0.075) or s(24)
    local h = s(28)
    local pad = s(10)
    local nameFont, wepFont = K.Font(14, 700), K.Font(12, 500)

    local i = 1
    while i <= #feed do
        local l = feed[i]
        local age = now - l.time
        if age > life then
            table.remove(feed, i)
        else
            local a = 255 * math.Clamp((life - age) / 0.6, 0, 1)
            surface.SetFont(nameFont)
            local vw = surface.GetTextSize(l.victim)
            local aw = l.attacker and surface.GetTextSize(l.attacker) or 0
            surface.SetFont(wepFont)
            local ww = surface.GetTextSize(string.upper(l.weapon))
            local gap = s(12)
            local w = pad * 2 + vw + ww + gap + (l.attacker and aw + gap or 0)
            local x = x1 - w
            K.Plate(x, y, w, h, { alpha = a })
            if l.mine then
                K.SetCol(C.accent, a)
                surface.DrawOutlinedRect(x, y, w, h)
            end
            local tx = x + pad
            local cy = y + h * 0.5
            col.a = a
            if l.attacker then
                col.r, col.g, col.b = l.aCol.r, l.aCol.g, l.aCol.b
                draw.SimpleText(l.attacker, nameFont, tx, cy, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                tx = tx + aw + gap
            end
            col.r, col.g, col.b = C.textDim.r, C.textDim.g, C.textDim.b
            draw.SimpleText(string.upper(l.weapon), wepFont, tx, cy, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            tx = tx + ww + gap
            col.r, col.g, col.b = l.vCol.r, l.vCol.g, l.vCol.b
            draw.SimpleText(l.victim, nameFont, tx, cy, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            y = y + h + s(4)
            i = i + 1
        end
    end
end)
