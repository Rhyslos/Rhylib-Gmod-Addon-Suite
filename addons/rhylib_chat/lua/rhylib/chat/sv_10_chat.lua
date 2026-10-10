--[[
    Chat, server side: checks each message and sends it only to the
    players its channel reaches. One small net message per recipient
    group, nothing per tick.

    Flow: the client sends chat.send -> Chat.CanUse -> hook Rhylib.CanChat
    -> the channel's route below picks the recipients -> chat.msg to them
    -> hook Rhylib.ChatMessage and a console line.

    Hooks fired:
      Rhylib.CanChat(ply, channelId, text, target)
          return false, "reason" to stop a message (rhylib_admin mutes use it).
          target is the PM receiver, or nil.
      Rhylib.ChatMessage(sender, channelId, text, target)
          after a message was sent (e.g. for logs). target only for PMs.
    Messages also go to the server console.

    Permissions: rhylib.chat.admin (admin: see the Admin channel),
    rhylib.chat.event (admin: post in the Event channel).
]]

local Chat = Rhylib.Chat
local Config = Rhylib.Config

-- chat.msg (server -> the recipients): channel index (CHANNEL_BITS, 0 =
-- a system note), sender entity, target entity (PM receiver or NULL), text.
Rhylib.Net.Register("chat.msg")
Rhylib.Perms.Register("rhylib.chat.admin", "admin", "See the admin chat channel")
Rhylib.Perms.Register("rhylib.chat.event", "admin", "Post in the Event chat channel")

local lastAdvert = setmetatable({}, { __mode = "k" })  -- [ply] = CurTime of their last advert

local function send(recipients, ch, sender, text, target)
    -- Radio text doesn't reach anyone inside a comms jammer (rhylib_radio).
    if ch.jammable then
        local kept = {}
        for _, p in ipairs(recipients) do
            if not p.rhylibJammed then kept[#kept + 1] = p end
        end
        recipients = kept
    end
    if #recipients == 0 then return end
    Rhylib.Net.Start("chat.msg")
    net.WriteUInt(ch.index, Chat.CHANNEL_BITS)
    net.WriteEntity(sender)
    net.WriteEntity(target or NULL)
    net.WriteString(text)
    net.Send(recipients)
end

-- Chat.Note(ply, text): a grey system line in one player's chat. Server only.
-- Example: Rhylib.Chat.Note(ply, "You can't do that here")
local function note(ply, text)
    Rhylib.Net.Start("chat.msg")
    net.WriteUInt(0, Chat.CHANNEL_BITS)  -- 0 = a system note to this player only
    net.WriteEntity(NULL)
    net.WriteEntity(NULL)
    net.WriteString(text)
    net.Send(ply)
end
Chat.Note = note

-- route[channel id](ply, ch, text, target): sends the message to whoever
-- the channel reaches. Return false when nothing was sent (or the route
-- sent and logged it itself), so the hook and console line are skipped.
local route = {}

route.public = function(ply, ch, text)
    send(player.GetHumans(), ch, ply, text)
end

route["local"] = function(ply, ch, text)
    local range = Config.Get("chat", "localRange")
    local pos, list = ply:GetPos(), {}
    for _, p in ipairs(player.GetHumans()) do
        if p:GetPos():DistToSqr(pos) <= range * range then list[#list + 1] = p end
    end
    send(list, ch, ply, text)
end

route.advert = function(ply, ch, text)
    local wait = (lastAdvert[ply] or 0) + Config.Get("chat", "advertCooldown") - CurTime()
    if wait > 0 then
        note(ply, string.format("You can advertise again in %d s", math.ceil(wait)))
        return false
    end
    lastAdvert[ply] = CurTime()
    send(player.GetHumans(), ch, ply, text)
end

-- Anyone can send; admins (CAMI permission) and the sender see it.
route.admin = function(ply, ch, text)
    send({ ply }, ch, ply, text)
    for _, p in ipairs(player.GetHumans()) do
        if p ~= ply then
            Rhylib.Perms.Check(p, "rhylib.chat.admin", function(ok)
                if ok and IsValid(p) and IsValid(ply) then send({ p }, ch, ply, text) end
            end)
        end
    end
end

-- Comms: everyone, like public (the tag is the difference).
route.comms = function(ply, ch, text)
    send(player.GetHumans(), ch, ply, text)
end

route.rp = function(ply, ch, text)
    send(player.GetHumans(), ch, ply, text)
end

-- Staff only (permission); everyone sees it.
route.event = function(ply, ch, text)
    Rhylib.Perms.Check(ply, "rhylib.chat.event", function(ok)
        if not IsValid(ply) then return end
        if not ok then
            note(ply, "Only event staff can post events")
            return
        end
        send(player.GetHumans(), ch, ply, text)
        hook.Run("Rhylib.ChatMessage", ply, ch.id, text, nil)
        print(string.format("[Chat][%s] %s: %s", ch.name, ply:Nick(), text))
    end)
    return false  -- sent (and logged) above, after the permission check
end

-- Squad / battalion / command: the members (Chat.CanUse is checked first).
route.squad = function(ply, ch, text)
    local id, list = Chat.SquadOf(ply), {}
    for _, p in ipairs(player.GetHumans()) do
        if Chat.SquadOf(p) == id then list[#list + 1] = p end
    end
    send(list, ch, ply, text)
end

route.battalion = function(ply, ch, text)
    local bn, list = Chat.BattalionOf(ply), {}
    for _, p in ipairs(player.GetHumans()) do
        if Chat.BattalionOf(p) == bn then list[#list + 1] = p end
    end
    send(list, ch, ply, text)
end

route.command = function(ply, ch, text)
    local list = {}
    for _, p in ipairs(player.GetHumans()) do
        if Chat.InCommand(p) then list[#list + 1] = p end
    end
    send(list, ch, ply, text)
end

route.pm = function(ply, ch, text, target)
    if not IsValid(target) or not target:IsPlayer() then
        note(ply, "No player by that name")
        return false
    end
    if target == ply then
        note(ply, "That's you")
        return false
    end
    send({ ply, target }, ch, ply, text, target)
end

-- chat.send (client -> server): channel index (CHANNEL_BITS), target entity
-- (PM receiver, else NULL), text. Rate 2/s, burst 5.
Rhylib.Net.Receive("chat.send", function(ply)
    local ch = Chat.CHANNELS[net.ReadUInt(Chat.CHANNEL_BITS)]
    local target = net.ReadEntity()
    local text = string.Trim(net.ReadString())
    if not ch or text == "" then return end
    if not ch.private then target = nil end  -- only private messages have a target
    local usable, whyNot = Chat.CanUse(ply, ch)
    if not usable then
        note(ply, whyNot)
        return
    end
    -- rhylib_admin (mutes) and others can stop it (target: a PM's receiver).
    local can, why = hook.Run("Rhylib.CanChat", ply, ch.id, text, target)
    if can == false then
        note(ply, why or "You can't chat right now")
        return
    end
    text = string.sub(text, 1, Config.Get("chat", "maxLength"))

    local fn = route[ch.id]
    if not fn or fn(ply, ch, text, target) == false then return end
    hook.Run("Rhylib.ChatMessage", ply, ch.id, text, IsValid(target) and target or nil)
    print(string.format("[Chat][%s] %s%s: %s", ch.name, ply:Nick(), IsValid(target) and (" -> " .. target:Nick()) or "", text))
end, { rate = 2, burst = 5 })

-- Typing indicator (the HUD's icons above heads read this).
-- chat.typing (client -> server): one bool, typing or not. Sets NW2Bool
-- rhylib_typing on the player.
-- (A generous limit, so the final "stopped typing" isn't dropped when the
-- chat is opened and closed quickly; it's also cleared on spawn and death.)
Rhylib.Net.Receive("chat.typing", function(ply)
    ply:SetNW2Bool("rhylib_typing", net.ReadBool())
end, { rate = 6, burst = 10 })

local function notTyping(ply) ply:SetNW2Bool("rhylib_typing", false) end
Rhylib.Hook.Add("PlayerSpawn", "chat.typing", notTyping)
Rhylib.Hook.Add("PlayerDeath", "chat.typing", notTyping)
