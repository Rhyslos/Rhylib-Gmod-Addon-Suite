--[[
    Radio (client): what we know, the keys, and requests to the server.

      R.dir    squads and channels (radio.dir): squads[id] = { id, name, open, leader, ro, members = { ply, ... } },
               channels[id] = { id, name, mode, bn, n }
      R.me     own channel slots and call (radio.me)
      R.call   the call we're in: { id, started, label, caller, members, ringing } or nil
      R.rings  hails ringing for us: [id] = { caller, label, at }
      R.mates  last known positions of squad mates out of view (radio.pos)
      R.speaking  players talking right now (start / end voice events)

    Keys (settings page, Radio): talk on the radio (B), switch the radio
    channel (K), radio page (T), and unbound mute / deafen / power.
]]

local R = Rhylib.Radio

R.COL = {
    local_ = Color(233, 237, 239),
    squad = Color(92, 214, 125),
    ch1 = Color(79, 175, 255),
    ch2 = Color(180, 140, 255),
    hail = Color(242, 193, 78),
    red = Color(229, 82, 75),
    off = Color(43, 48, 54),
    grey = Color(60, 67, 74),
}
R.PALETTE = {
    { "blue", "Blue", Color(79, 175, 255) },
    { "violet", "Violet", Color(180, 140, 255) },
    { "cyan", "Cyan", Color(70, 215, 215) },
    { "orange", "Orange", Color(240, 150, 60) },
    { "pink", "Pink", Color(240, 110, 170) },
    { "yellow", "Yellow", Color(232, 212, 90) },
}

local function cv(name, def, desc) return CreateClientConVar(name, def, true, false, desc) end
local talkVar = cv("rhylib_radio_key", "b", "Hold to talk on the radio")
local switchVar = cv("rhylib_radio_switchkey", "k", "Switch the radio channel you talk on")
local menuVar = cv("rhylib_radio_menukey", "t", "Open the Radio page")
local muteVar = cv("rhylib_radio_mutekey", "", "Mute your radio")
local deafVar = cv("rhylib_radio_deafkey", "", "Deafen your radio")
local powerVar = cv("rhylib_radio_powerkey", "", "Turn your radio on or off")
local col1Var = cv("rhylib_radio_col1", "blue", "Colour of radio channel 1")
local col2Var = cv("rhylib_radio_col2", "violet", "Colour of radio channel 2")
local roleVar = cv("rhylib_radio_role", "1", "Your squad role")
local slotVar = cv("rhylib_radio_slot", "1", "Radio channel you talk on: 1 squad, 2 channel 1, 3 channel 2")
local offVar = cv("rhylib_radio_off", "0", "Radio off")
local mutedVar = cv("rhylib_radio_muted", "0", "Radio muted")
local deafVar2 = cv("rhylib_radio_deaf", "0", "Radio deafened")
local radarVar = cv("rhylib_radio_compass", "0", "Squad compass on the HUD (takes half the chat's room in the visor)")
function R.RadarOn() return radarVar:GetBool() end

R.dir = R.dir or { squads = {}, channels = {}, sqOf = {}, roleOf = {} }
R.tx = R.tx or {}   -- [entindex] = { kind, id }: who is talking on what (radio.txev)
R.me = R.me or { slots = {}, call = 0 }
R.rings = R.rings or {}
R.mates = R.mates or {}
R.speaking = R.speaking or {}

-- Other players' squad, role and ranks come from the directory: their NW2
-- state is late while they're out of view (the radio is mostly for them).
local sqOfNW, roleOfNW, leaderNW, roNW = R.SquadOf, R.RoleOf, R.IsLeader, R.IsRO
function R.SquadOf(ply)
    if ply == LocalPlayer() then return sqOfNW(ply) end
    return R.dir.sqOf[ply:EntIndex()] or 0
end
function R.RoleOf(ply)
    if ply == LocalPlayer() then return roleOfNW(ply) end
    local r = R.dir.roleOf[ply:EntIndex()]
    return (r and R.ROLES[r]) and r or 1
end
function R.IsLeader(ply)
    if ply == LocalPlayer() then return leaderNW(ply) end
    local sq = R.dir.squads[R.SquadOf(ply)]
    return sq ~= nil and sq.leader == ply
end
function R.IsRO(ply)
    if ply == LocalPlayer() then return roNW(ply) end
    local sq = R.dir.squads[R.SquadOf(ply)]
    return sq ~= nil and sq.ro == ply
end

local function paletteCol(name, fallback)
    for _, p in ipairs(R.PALETTE) do if p[1] == name then return p[3] end end
    return fallback
end

-- Colour of a radio slot: 1 squad, 2 channel 1, 3 channel 2.
function R.SlotColor(slot)
    if slot == 1 then return R.COL.squad end
    if slot == 2 then return paletteCol(col1Var:GetString(), R.COL.ch1) end
    return paletteCol(col2Var:GetString(), R.COL.ch2)
end

function R.Note(text)
    chat.AddText(R.COL.squad, "[Radio] ", Color(225, 225, 225), text)
end

function R.Mine() return R.State(LocalPlayer()) end
function R.Selected() return math.Clamp(slotVar:GetInt(), 1, 3) end

-- Does slot exist (squad joined / channel in that slot)?
function R.SlotOn(slot)
    if slot == 1 then return R.SquadOf(LocalPlayer()) ~= 0 end
    return (R.me.slots[slot - 1] or 0) ~= 0
end

function R.SlotName(slot)
    if slot == 1 then
        local sq = R.dir.squads[R.SquadOf(LocalPlayer())]
        return sq and sq.name or "Squad"
    end
    local c = R.dir.channels[R.me.slots[slot - 1] or 0]
    return c and c.name or ("Channel " .. (slot - 1))
end

function R.InCall() return R.call ~= nil and #R.call.members >= 2 end

-- Which of my slots (or the call) a talker's radio reaches me on: 1-3, 4 = call, nil.
function R.HeardOn(talker)
    local kind, id
    local ev = R.tx[talker:EntIndex()]
    if ev then
        kind, id = ev.kind, ev.id
    else
        local t = R.State(talker)
        if t.off or t.muted then return nil end
        kind, id = t.txKind, t.txId
    end
    if kind == 0 or id == 0 then return nil end
    if kind == R.TX_SQUAD then
        return id == R.SquadOf(LocalPlayer()) and 1 or nil
    elseif kind == R.TX_CHAN then
        if R.me.slots[1] == id then return 2 end
        if R.me.slots[2] == id then return 3 end
    elseif kind == R.TX_CALL then
        return (R.call and R.call.id == id) and 4 or nil
    end
end

-- The colour the voice list and meters use for a talker (nil = local).
function R.SpeakerColor(ply)
    if ply == LocalPlayer() then
        local t = R.Mine()
        if t.txKind == R.TX_CALL then return R.COL.hail end
        if t.txKind == R.TX_SQUAD then return R.SlotColor(1) end
        if t.txKind == R.TX_CHAN then return R.SlotColor(R.me.slots[1] == t.txId and 2 or 3) end
        return nil
    end
    local mine = R.Mine()
    if mine.off or mine.deaf then return nil end
    local on = R.HeardOn(ply)
    if on == 4 then return R.COL.hail end
    if on then return R.SlotColor(on) end
end

--------------------------------------------------------------------------
-- Page refresh (debounced)
--------------------------------------------------------------------------

function R.Changed()
    if timer.Exists("Rhylib.Radio.Page") then return end
    timer.Create("Rhylib.Radio.Page", 0.2, 1, function()
        local M = Rhylib.Menus
        if M and IsValid(M.pause) and M.pause.pageId == "radio" then M.RefreshPause() end
    end)
end

--------------------------------------------------------------------------
-- Messages in
--------------------------------------------------------------------------

Rhylib.Net.Receive("radio.dir", function()
    local d = { squads = {}, channels = {}, sqOf = {}, roleOf = {} }
    for _ = 1, net.ReadUInt(R.ID_BITS) do
        local sq = { id = net.ReadUInt(R.ID_BITS), name = net.ReadString(), open = net.ReadBool(), leader = net.ReadEntity(), ro = net.ReadEntity(), members = {} }
        for i = 1, net.ReadUInt(8) do
            local idx = net.ReadUInt(8)
            local role = net.ReadUInt(5)
            sq.members[i] = Entity(idx)
            d.sqOf[idx], d.roleOf[idx] = sq.id, role
        end
        d.squads[sq.id] = sq
    end
    for _ = 1, net.ReadUInt(R.ID_BITS) do
        local c = { id = net.ReadUInt(R.ID_BITS), name = net.ReadString(), mode = net.ReadUInt(2), bn = net.ReadString(), n = net.ReadUInt(8) }
        d.channels[c.id] = c
    end
    R.dir = d
    R.Changed()
end)

Rhylib.Net.Receive("radio.me", function()
    R.me = { slots = { net.ReadUInt(R.ID_BITS), net.ReadUInt(R.ID_BITS) }, call = net.ReadUInt(R.ID_BITS) }
    -- Selected slot gone: back to the squad.
    if not R.SlotOn(R.Selected()) then RunConsoleCommand("rhylib_radio_slot", "1") end
    R.Changed()
end)

Rhylib.Net.Receive("radio.txev", function()
    local idx, kind, id = net.ReadUInt(8), net.ReadUInt(2), net.ReadUInt(R.ID_BITS)
    R.tx[idx] = { kind = kind, id = id }
end)

Rhylib.Net.Receive("radio.note", function()
    R.Note(net.ReadString())
end)

Rhylib.Net.Receive("radio.pos", function()
    local now = CurTime()
    for _ = 1, net.ReadUInt(8) do
        local idx = net.ReadUInt(8)
        local x, y, z = net.ReadInt(16), net.ReadInt(16), net.ReadInt(16)
        R.mates[idx] = { pos = Vector(x, y, z), at = now }
    end
end)

Rhylib.Net.Receive("radio.ring", function()
    local id = net.ReadUInt(R.ID_BITS)
    if net.ReadBool() then
        R.rings[id] = { id = id, caller = net.ReadEntity(), label = net.ReadString(), at = RealTime() }
        R.nextBeep = 0
    else
        R.rings[id] = nil
    end
    R.Changed()
end)

Rhylib.Net.Receive("radio.call", function()
    local id = net.ReadUInt(R.ID_BITS)
    if id == 0 then
        R.call = nil
        R.Changed()
        return
    end
    local c = { id = id, started = net.ReadFloat(), label = net.ReadString(), caller = net.ReadEntity(), ringing = net.ReadUInt(8), members = {} }
    for i = 1, net.ReadUInt(8) do c.members[i] = net.ReadEntity() end
    R.call = c
    R.Changed()
end)

--------------------------------------------------------------------------
-- Requests out
--------------------------------------------------------------------------

function R.SendState()
    Rhylib.Net.Start("radio.state")
    net.WriteBool(offVar:GetBool())
    net.WriteBool(mutedVar:GetBool())
    net.WriteBool(deafVar2:GetBool())
    net.SendToServer()
end

function R.Toggle(what)
    local var = what == "off" and offVar or what == "muted" and mutedVar or deafVar2
    RunConsoleCommand(var:GetName(), var:GetBool() and "0" or "1")
    -- (the convar changes next frame)
    timer.Simple(0, function()
        R.SendState()
        local word = what == "off" and (offVar:GetBool() and "Radio off" or "Radio on")
            or what == "muted" and (mutedVar:GetBool() and "Radio muted" or "Radio unmuted")
            or (deafVar2:GetBool() and "Radio deafened" or "Radio undeafened")
        R.Note(word)
    end)
end

function R.SetRole(i)
    RunConsoleCommand("rhylib_radio_role", tostring(i))
    Rhylib.Net.Start("radio.role")
    net.WriteUInt(i, 5)
    net.SendToServer()
end

R.SQ = { CREATE = 0, JOIN = 1, LEAVE = 2, LOCK = 3, RENAME = 4, KICK = 5, LEADER = 6, RO = 7 }
function R.SquadOp(op, arg)
    Rhylib.Net.Start("radio.squad")
    net.WriteUInt(op, 3)
    if op == R.SQ.CREATE or op == R.SQ.RENAME then net.WriteString(arg or "")
    elseif op == R.SQ.JOIN then net.WriteUInt(arg, R.ID_BITS)
    elseif op >= R.SQ.KICK then net.WriteEntity(arg) end
    net.SendToServer()
end

function R.ChanCreate(slot, name, mode, pass)
    Rhylib.Net.Start("radio.chan")
    net.WriteUInt(0, 2)
    net.WriteUInt(slot - 1, 1)
    net.WriteString(name)
    net.WriteUInt(mode, 2)
    net.WriteString(pass or "")
    net.SendToServer()
end

function R.ChanJoin(slot, id, pass)
    Rhylib.Net.Start("radio.chan")
    net.WriteUInt(1, 2)
    net.WriteUInt(slot - 1, 1)
    net.WriteUInt(id, R.ID_BITS)
    net.WriteString(pass or "")
    net.SendToServer()
end

function R.ChanLeave(slot)
    Rhylib.Net.Start("radio.chan")
    net.WriteUInt(2, 2)
    net.WriteUInt(slot - 1, 1)
    net.SendToServer()
end

function R.HailSquad(id)
    Rhylib.Net.Start("radio.hail")
    net.WriteUInt(1, 2)
    net.WriteUInt(id, R.ID_BITS)
    net.SendToServer()
end

function R.HailPlayer(ply)
    Rhylib.Net.Start("radio.hail")
    net.WriteUInt(2, 2)
    net.WriteEntity(ply)
    net.SendToServer()
end

function R.Answer(id, yes)
    Rhylib.Net.Start("radio.answer")
    net.WriteUInt(id, R.ID_BITS)
    net.WriteBool(yes)
    net.SendToServer()
end

function R.HangUp()
    Rhylib.Net.Start("radio.hangup")
    net.SendToServer()
end

-- On join: state, role, directory.
Rhylib.Hook.Add("InitPostEntity", "radio.join", function()
    timer.Simple(2, function()
        R.SendState()
        local r = roleVar:GetInt()
        if R.ROLES[r] then R.SetRole(r) end
        Rhylib.Net.Start("radio.dirreq")
        net.SendToServer()
    end)
end)

--------------------------------------------------------------------------
-- Who is talking (before the chat's voice list, which stops the event)
--------------------------------------------------------------------------

Rhylib.Hook.Add("PlayerStartVoice", "radio.speaking", function(ply)
    if IsValid(ply) then R.speaking[ply] = true end
end, -100)

Rhylib.Hook.Add("PlayerEndVoice", "radio.speaking", function(ply)
    R.speaking[ply] = nil
end, -100)

--------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------

local function blocked()
    if gui.IsGameUIVisible() or gui.IsConsoleVisible() then return true end
    local ply = LocalPlayer()
    if not IsValid(ply) or ply:IsTyping() then return true end
    local f = vgui.GetKeyboardFocus()
    return IsValid(f) and f:GetClassName() == "TextEntry"
end

local function keyDown(var)
    local s = var:GetString()
    if s == "" then return false end
    local code = input.GetKeyCode(s)
    return code and code > 0 and input.IsKeyDown(code) or false
end

R.txOn = false
local function startTx()
    local t = R.Mine()
    if t.off then R.Note("Your radio is off") return end
    if t.muted then R.Note("Your radio is muted") return end
    local slot = R.Selected()
    if not R.InCall() and not R.SlotOn(slot) then
        R.Note(slot == 1 and "You're not in a squad (Radio page: " .. string.upper(menuVar:GetString()) .. ")" or "No channel in that slot")
        return
    end
    Rhylib.Net.Start("radio.tx")
    net.WriteBool(true)
    net.WriteUInt(slot, 2)
    net.SendToServer()
    -- (+voicerecord can't be run from Lua; this asks the player once per server)
    if permissions and permissions.EnableVoiceChat then permissions.EnableVoiceChat(true) end
    R.txOn = true
end

local function stopTx()
    if not R.txOn then return end
    R.txOn = false
    if permissions and permissions.EnableVoiceChat then permissions.EnableVoiceChat(false) end
    -- Key up twice, in case one is dropped (a stuck radio would send your
    -- local voice to the channel).
    local function off()
        if R.txOn then return end
        Rhylib.Net.Start("radio.txoff")
        net.SendToServer()
    end
    off()
    timer.Simple(0.3, off)
end

function R.CycleSlot()
    local cur = R.Selected()
    for i = 1, 3 do
        local s = (cur + i - 1) % 3 + 1
        if R.SlotOn(s) then
            RunConsoleCommand("rhylib_radio_slot", tostring(s))
            R.Note("Talking on " .. R.SlotName(s))
            surface.PlaySound("buttons/lightswitch2.wav")
            return
        end
    end
    R.Note("Join a squad or a channel first")
end

function R.OpenPage()
    local M = Rhylib.Menus
    if not (M and M.OpenPause) then return end
    if IsValid(M.pause) then
        if M.pause.pageId == "radio" then M.ClosePause() else M.pause:ShowPage("radio") end
        return
    end
    M.lastPage = "radio"
    M.OpenPause()
end
concommand.Add("rhylib_radio", R.OpenPage)

-- The page key replaces whatever game bind sits on the same key (T: spray).
Rhylib.Hook.Add("PlayerBindPress", "radio.menukey", function(_, bind, pressed)
    local key = string.lower(menuVar:GetString())
    if key == "" or not pressed then return end
    local b = input.LookupBinding(bind, true)
    if b and string.lower(b) == key and not string.find(bind, "messagemode", 1, true) then return true end
end)

local was = {}
local function pressed(id, var)
    local d = keyDown(var)
    local p = d and not was[id]
    was[id] = d
    return p, d
end

Rhylib.Hook.Add("Think", "radio.keys", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local isBlocked = blocked()
    local _, talk = pressed("talk", talkVar)
    if talk and not isBlocked and ply:Alive() then
        if not R.txOn and not R.txTried then
            R.txTried = true
            startTx()
        end
    else
        R.txTried = nil
        stopTx()
    end
    local sw = pressed("switch", switchVar)
    local mu = pressed("mute", muteVar)
    local de = pressed("deaf", deafVar)
    local po = pressed("power", powerVar)
    local me = pressed("menu", menuVar)
    if isBlocked then return end
    if sw then R.CycleSlot() end
    if mu then R.Toggle("muted") end
    if de then R.Toggle("deaf") end
    if po then R.Toggle("off") end
    if me then R.OpenPage() end
end)

-- Hails ringing: a two-tone beep every 1.5 s.
Rhylib.Hook.Add("Think", "radio.ring", function()
    if next(R.rings) == nil then return end
    local now = RealTime()
    if now < (R.nextBeep or 0) then return end
    R.nextBeep = now + 1.5
    surface.PlaySound("buttons/blip1.wav")
    timer.Simple(0.16, function() surface.PlaySound("buttons/blip2.wav") end)
end)

--------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------

local function addSettings()
    local M = Rhylib.Menus
    if not (M and M.AddSetting) then return end
    local colours = {}
    for _, p in ipairs(R.PALETTE) do colours[#colours + 1] = { p[1], p[2] } end
    M.AddSetting("Radio", { id = "radio.key", order = 10, title = "Talk on the radio (hold)", kind = "key", convar = "rhylib_radio_key" })
    M.AddSetting("Radio", { id = "radio.switch", order = 20, title = "Switch radio channel", kind = "key", convar = "rhylib_radio_switchkey" })
    M.AddSetting("Radio", { id = "radio.menu", order = 30, title = "Radio page", kind = "key", convar = "rhylib_radio_menukey" })
    M.AddSetting("Radio", { id = "radio.mute", order = 40, title = "Mute radio", kind = "key", convar = "rhylib_radio_mutekey" })
    M.AddSetting("Radio", { id = "radio.deaf", order = 50, title = "Deafen radio", kind = "key", convar = "rhylib_radio_deafkey" })
    M.AddSetting("Radio", { id = "radio.power", order = 60, title = "Radio on / off", kind = "key", convar = "rhylib_radio_powerkey" })
    M.AddSetting("Radio", { id = "radio.col1", order = 70, title = "Channel 1 colour", kind = "choice", convar = "rhylib_radio_col1", options = colours })
    M.AddSetting("Radio", { id = "radio.col2", order = 80, title = "Channel 2 colour", kind = "choice", convar = "rhylib_radio_col2", options = colours })
end
Rhylib.Hook.Add("InitPostEntity", "radio.settings", addSettings)
addSettings()
