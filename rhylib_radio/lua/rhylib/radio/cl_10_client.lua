--[[
    Radio (client): what we know, the keys, and requests to the server.

      R.dir    squads and channels (radio.dir): squads[id] = { id, name, open, leader, ro, members = { ply, ... } },
               channels[id] = { id, name, mode, bn, n }
      R.me     own channel slots and call (radio.me)
      R.call   the call we're in: { id, started, label, caller, members, ringing } or nil
      R.rings  hails ringing for us: [id] = { caller, label, at }
      R.mates  last known positions of squad mates out of view (radio.pos)
      R.speaking  players talking right now (start / end voice events)

      R.tx     [entindex] = { kind, id }: what each talker sends on (radio.txev)

    Keys (settings page, Radio): talk on the radio (B), switch the radio
    channel (K), radio page (T), and unbound mute / deafen / power. Keys
    are read in Think with input.IsKeyDown, not binds; voice is switched
    with permissions.EnableVoiceChat (the game asks once per server).

    Client convars (all saved): rhylib_radio_key / _switchkey / _menukey /
    _mutekey / _deafkey / _powerkey (keys), rhylib_radio_col1 / _col2
    (channel colours, R.PALETTE ids), rhylib_radio_role (role index),
    rhylib_radio_slot (1 squad, 2 channel 1, 3 channel 2), rhylib_radio_off
    / _muted / _deaf (states, sent to the server on join and change),
    rhylib_radio_compass (squad compass on the HUD, default off),
    rhylib_radio_hidden (userinfo: hidden on the compass from everyone but
    your squad; R.Hidden / R.ToggleHidden, the Radio page's Hide button),
    rhylib_radio_chmute (channels whose voice you don't hear: bits 1
    squad, 2 channel 1, 4 channel 2; sent with radio.chmute on join and
    change; the Radio page's Mute buttons, R.ChanMuted / R.ToggleChanMute).
    Console command rhylib_radio opens the Radio page.
]]

local R = Rhylib.Radio

-- Fixed colours: local voice, squad, the default channel colours, hail
-- gold, muted/deafened red, radio off, not joined; on the radar everyone
-- outside your squad and your squad leader. squad, red, radarFriend and
-- radarLeader are HUD colour tokens (Settings > HUD colours: keys squad,
-- danger, friend, objective); read them when drawing.
local UI = Rhylib.UI
R.COL = {
    local_ = Color(233, 237, 239),
    squad = UI.HudCol("squad", "radio.squad", 92, 214, 125),
    ch1 = Color(79, 175, 255),
    ch2 = Color(180, 140, 255),
    hail = Color(242, 193, 78),
    red = UI.HudCol("danger", "radio.muted", 229, 82, 75),
    off = Color(43, 48, 54),
    grey = Color(60, 67, 74),
    radarFriend = UI.HudCol("friend", "radio.radarFriend", 79, 175, 255),
    radarLeader = UI.HudCol("objective", "radio.radarLeader", 242, 193, 78),
}
-- Channel colour choices: { id (convar value), label, colour }.
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
-- (userinfo: the server leaves you out of everyone's compass, radio.all)
local hiddenVar = CreateClientConVar("rhylib_radio_hidden", "0", true, true, "Hide yourself on the compass from everyone but your squad (sensor array beacons still show you)")
function R.Hidden() return hiddenVar:GetBool() end
function R.ToggleHidden()
    hiddenVar:SetBool(not hiddenVar:GetBool())
    if R.Changed then R.Changed() end
end
local chMuteVar = cv("rhylib_radio_chmute", "0", "Radio channels you don't hear (bits: 1 squad, 2 channel 1, 4 channel 2)")

-- R.ChanMuted(slot): is that slot's voice muted for you (1 squad, 2
-- channel 1, 3 channel 2; a call is never muted)?
function R.ChanMuted(slot)
    if not slot or slot < 1 or slot > 3 then return false end
    return bit.band(chMuteVar:GetInt(), bit.lshift(1, slot - 1)) ~= 0
end

-- R.SendChanMute(v): sends radio.chmute (the muted slots; default the
-- saved ones) to the server.
function R.SendChanMute(v)
    Rhylib.Net.Start("radio.chmute")
    net.WriteUInt(bit.band(v or chMuteVar:GetInt(), 7), 3)
    net.SendToServer()
end

local function setChanMute(v)
    chMuteVar:SetInt(v)
    R.SendChanMute(v)
    if R.Changed then R.Changed() end
end

-- R.ToggleChanMute(slot): mute / unmute a slot's voice (only for you).
function R.ToggleChanMute(slot)
    setChanMute(bit.bxor(bit.band(chMuteVar:GetInt(), 7), bit.lshift(1, slot - 1)))
end

-- (a channel slot that now holds another channel, or none: its mute goes)
function R.ClearChanMuteFor(oldSlots, newSlots)
    local v = bit.band(chMuteVar:GetInt(), 7)
    local nv = v
    for i = 1, 2 do
        if (oldSlots[i] or 0) ~= (newSlots[i] or 0) then nv = bit.band(nv, bit.bnot(bit.lshift(1, i))) end
    end
    if nv ~= v then setChanMute(nv) end
end
-- R.RadarOn(): is the squad compass on the HUD switched on?
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

-- R.SlotColor(slot): colour of a radio slot: 1 squad, 2 channel 1,
-- 3 channel 2 (the player's palette picks for the channels).
function R.SlotColor(slot)
    if slot == 1 then return R.COL.squad end
    if slot == 2 then return paletteCol(col1Var:GetString(), R.COL.ch1) end
    return paletteCol(col2Var:GetString(), R.COL.ch2)
end

-- R.Note(text): a "[Radio] text" chat line (client version).
function R.Note(text)
    Rhylib.Notify(nil, text, "info", "Radio")
end

-- R.Mine(): your own unpacked radio state. R.Selected(): the slot the
-- radio key talks on (1-3).
function R.Mine() return R.State(LocalPlayer()) end
function R.Selected() return math.Clamp(slotVar:GetInt(), 1, 3) end

-- Does slot exist (squad joined / channel in that slot)?
function R.SlotOn(slot)
    if slot == 1 then return R.SquadOf(LocalPlayer()) ~= 0 end
    return (R.me.slots[slot - 1] or 0) ~= 0
end

-- R.SlotName(slot): the squad's or channel's name for a slot.
function R.SlotName(slot)
    if slot == 1 then
        local sq = R.dir.squads[R.SquadOf(LocalPlayer())]
        return sq and sq.name or "Squad"
    end
    local c = R.dir.channels[R.me.slots[slot - 1] or 0]
    return c and c.name or ("Channel " .. (slot - 1))
end

-- R.InCall(): in a hail call someone has answered (2+ members).
function R.InCall() return R.call ~= nil and #R.call.members >= 2 end

-- R.HeardOn(talker): which of my slots (or the call) a talker's radio
-- reaches me on: 1-3, 4 = call, nil = not on my radio. The last
-- radio.txev for that talker wins over their NW2 state (which arrives
-- late for players out of view). Doesn't check my own off/deaf/jammed.
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

-- R.SpeakerColor(ply): the colour the voice list and meters use for a
-- talker (nil = local voice). For yourself: what you send on. Used by
-- rhylib_chat's voice list stripe.
-- Example: local col = Rhylib.Radio.SpeakerColor(ply) or color_white
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
    if on and R.ChanMuted(on) then return nil end   -- (a muted channel: only local voice)
    if on then return R.SlotColor(on) end
end

--------------------------------------------------------------------------
-- Page refresh (debounced)
--------------------------------------------------------------------------

-- R.Changed(): something on the Radio page changed; rebuild it 0.2 s
-- later if it is open (several changes in a row rebuild once).
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
    local old = R.me and R.me.slots
    R.me = { slots = { net.ReadUInt(R.ID_BITS), net.ReadUInt(R.ID_BITS) }, call = net.ReadUInt(R.ID_BITS) }
    -- (a channel muted in a slot: leaving it or a new channel there unmutes the slot)
    if old and R.ClearChanMuteFor then R.ClearChanMuteFor(old, R.me.slots) end
    -- Selected slot gone: back to the squad.
    if not R.SlotOn(R.Selected()) then RunConsoleCommand("rhylib_radio_slot", "1") end
    R.Changed()
end)

Rhylib.Net.Receive("radio.txev", function()
    local idx, kind, id = net.ReadUInt(8), net.ReadUInt(2), net.ReadUInt(R.ID_BITS)
    R.tx[idx] = { kind = kind, id = id }
end)

Rhylib.Net.Receive("radio.pos", function()
    local now = CurTime()
    for _ = 1, net.ReadUInt(8) do
        local idx = net.ReadUInt(8)
        local x, y, z = net.ReadInt(16), net.ReadInt(16), net.ReadInt(16)
        R.mates[idx] = { pos = Vector(x, y, z), at = now }
    end
end)

-- R.everyone[entindex] = { pos, at }: who the compass may show (radio.all).
R.everyone = R.everyone or {}
Rhylib.Net.Receive("radio.all", function()
    local now = CurTime()
    for _ = 1, net.ReadUInt(8) do
        local idx = net.ReadUInt(8)
        local x, y, z = net.ReadInt(16), net.ReadInt(16), net.ReadInt(16)
        R.everyone[idx] = { pos = Vector(x, y, z), at = now }
    end
end)

-- Hand to the ear: typing in chat (rhylib_chat NW2Bool rhylib_typing) or
-- talking on the radio (a radio tx kind set). The left arm is taken off
-- whatever the animation does and put there by IK (a BuildBonePositions
-- callback on each player, drawn by everyone): the wrist goes to a point
-- fixed to the head bone (config earIK.pos, in the head bone's own axes),
-- the hand takes a fixed turn from the head (earIK.ang), the elbow bends
-- toward earIK.elbow (also head space), turned earIK.swivel degrees
-- round the shoulder-to-wrist line; or, with earIK.shoulder set, the upper
-- arm takes that fixed turn from the chest bone and the forearm aims from
-- the elbow at the wrist point (steady with freelook); the shoulder stays where the
-- animation has it, the upper arm and forearm only swing (no twist), and
-- the fingers take the pose they have in the sequence earIK.fingers ("" =
-- the model's reference pose), so it looks the same with any weapon. Eased in and out (weight). Not while a weapon poses that
-- player's arm (WorldBoneMods: the riot shields). R.earPreview
-- (rhylib_devtools' rhylib_ear_editor) holds your own arm up and uses
-- R.earIKEdit instead of the config.
local B_UPPER, B_FORE, B_HAND, B_HEAD = "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_Head1"

Rhylib.Hook.Add("UpdateAnimation", "radio.ear", function(ply)
    if not IsValid(ply) then return end
    local St = Rhylib.State
    local on = ply:Alive() and not ply:IsPlayingTaunt() and not (St and (St.IsDown(ply) or St.IsCuffed(ply)))
        and (ply:GetNW2Bool("rhylib_typing", false) or R.State(ply).txKind ~= 0)
    if R.earPreview and ply == LocalPlayer() then on = true end
    ply.rhylibEarW = math.Approach(ply.rhylibEarW or 0, on and 1 or 0, FrameTime() * 3)
    if ply.rhylibEarW > 0 and not ply.rhylibEarCb then
        ply.rhylibEarCb = true
        ply:AddCallback("BuildBonePositions", function(ent, n) if R.EarBones then R.EarBones(ent, n) end end)
    end
end)

-- Per model: bone ids, which of the arm bones each other bone hangs under
-- (1 upper arm, 2 forearm, 3 hand), and the fingers' pose relative to the
-- hand in the reference pose.
local earModels = {}
local function earInfo(ent)
    local mdl = ent:GetModel()
    local info = earModels[mdl]
    if info ~= nil then return info end
    local up, fo, ha, he = ent:LookupBone(B_UPPER), ent:LookupBone(B_FORE), ent:LookupBone(B_HAND), ent:LookupBone(B_HEAD)
    local ch = ent:LookupBone("ValveBiped.Bip01_Spine4") or ent:LookupBone("ValveBiped.Bip01_Spine2")
    if not (up and fo and ha and he and ch) then earModels[mdl] = false return false end
    info = { up = up, fo = fo, ha = ha, he = he, ch = ch, under = {} }
    for b = 0, ent:GetBoneCount() - 1 do
        if b ~= up and b ~= fo and b ~= ha then
            local p = ent:GetBoneParent(b)
            while p and p >= 0 do
                if p == ha then info.under[b] = 3 break end
                if p == fo then info.under[b] = 2 break end
                if p == up then info.under[b] = 1 break end
                p = ent:GetBoneParent(p)
            end
        end
    end
    earModels[mdl] = info
    return info
end

-- The fingers relative to the hand in one of the model's sequences
-- (earIK.fingers = its name, "" = the reference pose), from a hidden copy
-- of the model half way through it. Cached per model and sequence.
local fingerCache = {}
local function fingerPose(ent, info, seqName)
    local key = ent:GetModel() .. "|" .. (seqName or "")
    local ref = fingerCache[key]
    if ref ~= nil then return ref end
    ref = {}
    local cm = ClientsideModel(ent:GetModel(), RENDERGROUP_OPAQUE)
    if IsValid(cm) then
        cm:SetNoDraw(true)
        local seq = seqName ~= "" and cm:LookupSequence(seqName) or -1
        if not seq or seq < 0 then seq = cm:LookupSequence("reference") end
        cm:ResetSequence(seq and seq >= 0 and seq or 0)
        cm:SetCycle(seqName ~= "" and 0.5 or 0)
        cm:SetupBones()
        local hm = cm:GetBoneMatrix(info.ha)
        if hm then
            local inv = hm:GetInverseTR()
            for b, k in pairs(info.under) do
                if k == 3 then
                    local m = cm:GetBoneMatrix(b)
                    if m then ref[b] = inv * m end
                end
            end
        end
        cm:Remove()
    end
    fingerCache[key] = ref
    return ref
end

-- Rodrigues: v turned about unit axis k by angle a.
local function turn(v, k, c, sn)
    return v * c + k:Cross(v) * sn + k * (k:Dot(v) * (1 - c))
end
-- The matrix m swung (shortest turn) so its forward goes from dir a to dir
-- b, moved to pos (scale kept).
local function swing(m, a, b, pos)
    local f, u = m:GetForward(), m:GetUp()
    local axis = a:Cross(b)
    local sn = axis:Length()
    local c = a:Dot(b)
    if sn > 1e-5 then
        axis:Mul(1 / sn)
        f, u = turn(f, axis, c, sn), turn(u, axis, c, sn)
    end
    local out = Matrix()
    out:SetAngles(f:AngleEx(u))
    out:SetTranslation(pos)
    out:Scale(m:GetScale())
    return out
end

local function v3(t, d) return Vector(tonumber(t and t[1]) or d[1], tonumber(t and t[2]) or d[2], tonumber(t and t[3]) or d[3]) end

function R.EarBones(ent, n)
    local w = ent.rhylibEarW or 0
    if w <= 0 or ent.rhylibWorldMods then return end
    local info = earInfo(ent)
    if not info then return end
    local cfg = (ent == LocalPlayer() and R.earIKEdit) or R.Cfg("earIK")
    if not istable(cfg) then return end
    local mU, mF, mH, mHead, mC = ent:GetBoneMatrix(info.up), ent:GetBoneMatrix(info.fo), ent:GetBoneMatrix(info.ha), ent:GetBoneMatrix(info.he), ent:GetBoneMatrix(info.ch)
    if not (mU and mF and mH and mHead and mC) then return end
    local S, E0, W0 = mU:GetTranslation(), mF:GetTranslation(), mH:GetTranslation()
    local a, b = S:Distance(E0), E0:Distance(W0)
    if a < 1 or b < 1 then return end
    local hp, ha = mHead:GetTranslation(), mHead:GetAngles()
    local T = LocalToWorld(v3(cfg.pos, { -0.5, -2.5, -6 }), angle_zero, hp, ha)
    local _, handAng = LocalToWorld(vector_origin, Angle(v3(cfg.ang, { -175, -150, 80 }):Unpack()), hp, ha)
    local target0 = Vector(T)   -- (the wrist point as set, for the editor's handles)
    local cp, ca = mC:GetTranslation(), mC:GetAngles()
    local pole = LocalToWorld(v3(cfg.elbow, { 13, 18, 15 }), angle_zero, hp, ha)
    local nU, nF
    local preview = R.earViaPreview and ent == LocalPlayer()
    if preview then w = 0.5 end
    -- The transition point is only used from idle (no weapon, or one held
    -- with the normal / passive hold type: the arm hangs by the body).
    local useVia = false
    if istable(cfg.shoulder) and istable(cfg.viaShoulder) and istable(cfg.viaPos) and w < 1 then
        local wep = ent:GetActiveWeapon()
        local ht = IsValid(wep) and wep.GetHoldType and wep:GetHoldType() or "normal"
        useVia = preview or ht == "normal" or ht == "passive"
    end
    -- (eased: the hand turns from where the animation has it; through the
    -- transition point: to its own turn there first, earIK.viaAng)
    if w < 1 then
        if useVia then
            local _, vh = LocalToWorld(vector_origin, Angle(v3(cfg.viaAng, { 0, 0, 0 }):Unpack()), cp, ca)
            if not istable(cfg.viaAng) then vh = LerpAngle(0.5, mH:GetAngles(), handAng) end
            if w < 0.5 then handAng = LerpAngle(w * 2, mH:GetAngles(), vh) else handAng = LerpAngle((w - 0.5) * 2, vh, handAng) end
        else
            handAng = LerpAngle(w, mH:GetAngles(), handAng)
        end
    end
    if istable(cfg.shoulder) then
        -- Shoulder set by hand (earIK.shoulder, in the chest bone's axes):
        -- the upper arm points that way whatever the head or the animation
        -- does, and the forearm aims from the elbow at the wrist point.
        local _, ua = LocalToWorld(vector_origin, Angle(v3(cfg.shoulder, { 0, 0, 0 }):Unpack()), cp, ca)
        if w < 1 then
            -- On the way: from the animation's arm to the transition point
            -- (earIK.viaShoulder / viaPos, chest axes) over the first half,
            -- then on to the ear, so the hand doesn't cut through the body.
            if useVia then
                local _, va = LocalToWorld(vector_origin, Angle(v3(cfg.viaShoulder, { 0, 0, 0 }):Unpack()), cp, ca)
                local vt = LocalToWorld(v3(cfg.viaPos, { 0, 0, 0 }), angle_zero, cp, ca)
                if w < 0.5 then
                    local k = w * 2
                    ua, T = LerpAngle(k, mU:GetAngles(), va), LerpVector(k, W0, vt)
                else
                    local k = (w - 0.5) * 2
                    ua, T = LerpAngle(k, va, ua), LerpVector(k, vt, T)
                end
            else
                ua, T = LerpAngle(w, mU:GetAngles(), ua), LerpVector(w, W0, T)
            end
        end
        nU = Matrix()
        nU:SetAngles(ua)
        nU:SetTranslation(S)
        nU:Scale(mU:GetScale())
        local E = S + nU:GetForward() * a
        local dirF = (T - E):GetNormalized()
        T = E + dirF * b
        nF = swing(nU, nU:GetForward(), dirF, E)
    else
    if w < 1 then T = LerpVector(w, W0, T) end
    -- Two-bone IK: the elbow on the circle where both bone lengths fit,
    -- on the side of the pole.
    local d = T - S
    local dist = math.Clamp(d:Length(), math.abs(a - b) + 0.1, (a + b) * 0.999)
    local dir = d:GetNormalized()
    T = S + dir * dist
    local cosA = math.Clamp((a * a + dist * dist - b * b) / (2 * a * dist), -1, 1)
    local sinA = math.sqrt(1 - cosA * cosA)
    local pp = pole - S
    local perp = pp - dir * pp:Dot(dir)
    if perp:LengthSqr() < 0.01 then perp = (E0 - S) - dir * (E0 - S):Dot(dir) end
    perp:Normalize()
    -- (swivel: the elbow turned on round the shoulder-to-wrist line)
    local sw = math.rad(tonumber(cfg.swivel) or 0)
    if sw ~= 0 then perp = turn(perp, dir, math.cos(sw), math.sin(sw)) end
    local E = S + dir * (a * cosA) + perp * (a * sinA)
    -- New matrices: the upper arm and forearm swung onto the new lines, the
    -- hand at the wrist with the fixed turn.
    nU = swing(mU, (E0 - S):GetNormalized(), (E - S):GetNormalized(), S)
    nF = swing(mF, (W0 - E0):GetNormalized(), (T - E):GetNormalized(), E)
    end
    -- (for the editor's "lock the shoulder here": the upper arm now, in the chest's axes)
    if ent == LocalPlayer() then
        local _, la = WorldToLocal(vector_origin, nU:GetAngles(), cp, ca)
        R.earUpperLocal = la
        R.earWristLocal = WorldToLocal(T, angle_zero, cp, ca)
        -- (what the editor's transform handles show and drag)
        R.earDbg = { S = Vector(S), E = nF:GetTranslation(), W = Vector(T), target = target0, hand = Angle(handAng),
            upper = nU:GetAngles(), hp = hp, ha = ha, cp = cp, ca = ca }
    end
    local nH = Matrix()
    nH:SetAngles(handAng)
    nH:SetTranslation(T)
    nH:Scale(mH:GetScale())
    local dU, dF, dH = nU * mU:GetInverseTR(), nF * mF:GetInverseTR(), nH * mH:GetInverseTR()
    -- Everything hanging under them follows (fingers: the chosen pose).
    local fingers = fingerPose(ent, info, isstring(cfg.fingers) and cfg.fingers or "")
    for bone, k in pairs(info.under) do
        local m = ent:GetBoneMatrix(bone)
        if m then
            if k == 3 then
                local r = fingers[bone]
                if r then ent:SetBoneMatrix(bone, nH * r) else ent:SetBoneMatrix(bone, dH * m) end
            elseif k == 2 then
                ent:SetBoneMatrix(bone, dF * m)
            else
                ent:SetBoneMatrix(bone, dU * m)
            end
        end
    end
    ent:SetBoneMatrix(info.up, nU)
    ent:SetBoneMatrix(info.fo, nF)
    ent:SetBoneMatrix(info.ha, nH)
end

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

-- R.SendState(): sends radio.state (off, muted, deafened from the
-- convars) to the server.
function R.SendState()
    Rhylib.Net.Start("radio.state")
    net.WriteBool(offVar:GetBool())
    net.WriteBool(mutedVar:GetBool())
    net.WriteBool(deafVar2:GetBool())
    net.SendToServer()
end

-- R.Toggle(what): flips "off", "muted" or "deaf" (anything else = deaf),
-- tells the server and prints a chat note.
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

-- R.SetRole(i): saves and sends your squad role (R.ROLES index).
function R.SetRole(i)
    RunConsoleCommand("rhylib_radio_role", tostring(i))
    Rhylib.Net.Start("radio.role")
    net.WriteUInt(i, 5)
    net.SendToServer()
end

-- R.SquadOp(op, arg): sends radio.squad. arg: the name for CREATE /
-- RENAME, the squad id for JOIN, the player for KICK / LEADER / RO.
-- Example: R.SquadOp(R.SQ.JOIN, 3)
R.SQ = { CREATE = 0, JOIN = 1, LEAVE = 2, LOCK = 3, RENAME = 4, KICK = 5, LEADER = 6, RO = 7 }
function R.SquadOp(op, arg)
    Rhylib.Net.Start("radio.squad")
    net.WriteUInt(op, 3)
    if op == R.SQ.CREATE or op == R.SQ.RENAME then net.WriteString(arg or "")
    elseif op == R.SQ.JOIN then net.WriteUInt(arg, R.ID_BITS)
    elseif op >= R.SQ.KICK then net.WriteEntity(arg) end
    net.SendToServer()
end

-- Channel requests (radio.chan); slot is 1 or 2 (channel 1 / 2).
-- R.ChanCreate(slot, name, mode, pass), R.ChanJoin(slot, id, pass),
-- R.ChanLeave(slot).
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

-- Hail requests (radio.hail): R.HailSquad(squadId) rings its leader and
-- RO, R.HailPlayer(ply) rings one player. R.Answer(callId, yes) answers
-- or declines a ring; R.HangUp() leaves / ends your call.
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

-- On join (2 s after InitPostEntity): send state and role, ask for the
-- directory.
Rhylib.Hook.Add("InitPostEntity", "radio.join", function()
    timer.Simple(2, function()
        R.SendState()
        R.SendChanMute()
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

-- A player gone: their talking state goes too (R.tx is by entindex).
Rhylib.Hook.Add("EntityRemoved", "radio.tx", function(e)
    if e:IsPlayer() then R.tx[e:EntIndex()] = nil end
end)

--------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------

-- Keys do nothing while the game menu or console is up, while typing in
-- chat or in a text box.
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

-- R.txOn: true while we're keying the radio (told the server, voice on).
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

-- R.CycleSlot(): switch the radio key to the next slot you're in.
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

-- R.OpenPage(): opens the pause menu on the Radio page (or closes it if
-- it's already showing). Needs rhylib_menus.
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

-- The page key and the talk key replace whatever game bind sits on the
-- same key (T: spray, B: the suit zoom). The talk key also swallows the
-- release, so a held +bind (zoom) never starts.
Rhylib.Hook.Add("PlayerBindPress", "radio.menukey", function(_, bind, pressed, code)
    if string.find(bind, "messagemode", 1, true) then return end
    -- (the key actually pressed; older builds without it: the bind's first key)
    local b = code and code > 0 and input.GetKeyName(code) or input.LookupBinding(bind, true)
    if not b then return end
    b = string.lower(b)
    local talk = string.lower(talkVar:GetString())
    if talk ~= "" and b == talk then return true end
    local key = string.lower(menuVar:GetString())
    if key == "" or not pressed then return end
    if b == key then return true end
end)

local was = {}
local function pressed(id, var)
    local d = keyDown(var)
    local p = d and not was[id]
    was[id] = d
    return p, d
end

-- Talk key held = keying (one try per press: a refused start isn't
-- retried until the key is let go). The other keys act on press.
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

-- Interaction wheel (rhylib_menus): hail them on the radio.
Rhylib.Hook.Add("Rhylib.WheelOptions", "radio.wheel", function(t, me, add)
    if R.State(me).off then
        add("Hail", nil, { order = 45, disabled = "Your radio is off" })
    else
        add("Hail", function(x) R.HailPlayer(x) end, { order = 45, sub = "Call them on the radio" })
    end
end)
