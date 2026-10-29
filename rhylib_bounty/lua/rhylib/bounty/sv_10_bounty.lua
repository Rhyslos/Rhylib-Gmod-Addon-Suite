--[[
    Bounties (server): the board, money, contracts, bodies and proof,
    turning in (proof or a prisoner), expiry and refunds.

    A bounty: { id, kind ("player" | "npc"), tkey (target key: "p" .. sid
    or "n" .. first npc bounty id), sid (players), ent (npcs, this session),
    name, model, reward, mode ("dead" | "alive" | "either"), by (poster
    sid, "" for staff), byName, free (staff, no money held), std
    (standalone), at (os.time posted), ends (os.time) }.

    Data (Rhylib.Data): "bounty"/"open" = list of player bounties (npc ones
    end with the map), "bounty"/"next" = next id, "bounty"/"refund_s<sid>"
    = money owed to an offline poster (paid when they join).

    Messages:
      bounty.listreq  client -> server (empty): send me the board (rate 1/s;
                      clients ask once loaded in)
      bounty.diff     server -> client(s): reset (bool: the whole board
                      follows), then items: more (bool), remove (bool), then
                      id (UInt 24) for a remove, else a row: id UInt 24, npc
                      bool, name, model, reward UInt 32, mode UInt 2 (1 dead,
                      2 alive, 3 either), free, std (bools), by (sid), byName,
                      seconds left UInt 24, tsid, tidx UInt 16 (target entity
                      index, 0 = none); more = false ends it. The snapshot
                      goes to the asking player only; changes (B.sent
                      signatures, flushed 0.5 s after B.Changed, and when
                      someone joins or leaves) go to everyone, one row each.
      bounty.open     server -> client: office entity (open the window)
      bounty.post     client -> server: office, target sid, reward (UInt 32),
                      mode (UInt 2), standalone, free (bools)
      bounty.npc      client -> server: npc entity, reward (UInt 32), name
                      (staff, free, dead only)
      bounty.accept   client -> server: office, bounty id (UInt 32)
      bounty.cancel   client -> server: bounty id (UInt 32)
      bounty.turnin   client -> server: office
      bounty.collect  client -> server: body entity (start collecting proof)
      bounty.collectx server -> client: collecting stopped (reason string)
      bounty.msg      server -> client: ok (bool), text
    Also: the target of a new player bounty is told ("There's a price on
    your head", config notifyTarget / notifyAmount); a bound prisoner is
    freed when no bounty on them is left (weapons/rhylib_binders.lua).
    Hooks fired: Rhylib.BountyPosted(b), Rhylib.BountyClaimed(b, ply, how
    ("proof" | "alive")), Rhylib.BountyClosed(b, why).
]]

local B = Rhylib.Bounty
local Data = Rhylib.Data
local Net = Rhylib.Net

for _, n in ipairs({ "bounty.diff", "bounty.open", "bounty.msg", "bounty.collectx" }) do Net.Register(n) end

B.list = B.list or {}       -- [id] = bounty
B.bodies = B.bodies or {}   -- [ragdoll] = { tkey, name, at, taken }
B.collecting = B.collecting or {}   -- [ply] = { body, ends, pos }

local OFFICE_RANGE = 220

local function sid(ply) return ply:SteamID64() or "" end

-- B.PlayerKey(ply): a player's target key. "p" .. SteamID64 for people;
-- bots share one SteamID64, so they get "pb" .. UserID (test bots).
function B.PlayerKey(ply)
    if ply:IsBot() then return "pb" .. ply:UserID() end
    return "p" .. sid(ply)
end

-- B.TargetPlayer(b): the online player a player bounty is on, or nil.
function B.TargetPlayer(b)
    if b.botId then
        local p = Player(b.botId)
        return IsValid(p) and p or nil
    end
    local p = b.sid and b.sid ~= "" and player.GetBySteamID64(b.sid)
    return IsValid(p) and p or nil
end

-- B.Msg(ply, ok, text): a line in the office window and in chat.
function B.Msg(ply, ok, text)
    if not IsValid(ply) then return end
    Net.Start("bounty.msg")
    net.WriteBool(ok and true or false)
    net.WriteString(text or "")
    net.Send(ply)
end

-- B.NearOffice(ply, office): office is a Bounty Office within reach.
function B.NearOffice(ply, office)
    return IsValid(office) and office:GetClass() == "rhylib_bounty_office" and ply:GetPos():DistToSqr(office:GetPos()) < OFFICE_RANGE * OFFICE_RANGE
end

--------------------------------------------------------------------------
-- Money (DarkRP)
--------------------------------------------------------------------------

local function canPay(ply, n) return ply.canAfford ~= nil and ply:canAfford(n) end
local function give(ply, n) if n > 0 and ply.addMoney then ply:addMoney(math.floor(n)) end end
local function take(ply, n) if n > 0 and ply.addMoney then ply:addMoney(-math.floor(n)) end end
-- DarkRP overwrites the wallet when a joining player's data loads, so money
-- given before then is lost.
local function walletReady(ply) return IsValid(ply) and not ply.DarkRPUnInitialized end
local function money(n) return DarkRP and DarkRP.formatMoney and DarkRP.formatMoney(n) or ("$" .. n) end
B.Money = money

-- Pay a poster back (online now, or when they next join).
local function refund(bySid, n)
    n = math.floor(n)
    if n <= 0 or bySid == "" then return end
    local p = player.GetBySteamID64(bySid)
    if walletReady(p) then
        give(p, n)
        B.Msg(p, true, "Refunded " .. money(n) .. " for a bounty")
        return
    end
    local owed = tonumber(Data.Get("bounty", "refund_s" .. bySid)) or 0
    Data.Set("bounty", "refund_s" .. bySid, owed + n)
end

-- Owed refunds, once DarkRP has loaded the player's wallet (checked every
-- 2 s for up to a minute; the row is only deleted after paying).
Rhylib.Hook.Add("PlayerInitialSpawn", "bounty.refund", function(ply)
    local id = "Rhylib.Bounty.Refund." .. ply:EntIndex()
    timer.Create(id, 2, 30, function()
        if not IsValid(ply) then timer.Remove(id) return end
        if not walletReady(ply) then return end
        timer.Remove(id)
        local owed = tonumber(Data.Get("bounty", "refund_s" .. sid(ply))) or 0
        if owed > 0 then
            give(ply, owed)
            Data.Delete("bounty", "refund_s" .. sid(ply))
            B.Msg(ply, true, "Refunded " .. money(owed) .. " for bounties that ran out while you were away")
        end
    end)
end)

--------------------------------------------------------------------------
-- Storage and the board
--------------------------------------------------------------------------

local function save()
    local rows = {}
    for _, b in pairs(B.list) do
        if b.kind == "player" and not b.botId then   -- (test-bot bounties end with the session)
            rows[#rows + 1] = { id = b.id, kind = b.kind, tkey = b.tkey, sid = b.sid, name = b.name, model = b.model,
                reward = b.reward, mode = b.mode, by = b.by, byName = b.byName, free = b.free, std = b.std, at = b.at, ends = b.ends }
        end
    end
    Data.Set("bounty", "open", rows)
    Data.Set("bounty", "next", B.nextId)
end

local function load()
    B.nextId = tonumber(Data.Get("bounty", "next")) or 1
    local rows = Data.Get("bounty", "open")
    for _, r in ipairs(istable(rows) and rows or {}) do
        if istable(r) and tonumber(r.id) then B.list[tonumber(r.id)] = r end
    end
end
if not B.loaded then
    B.loaded = true
    load()
end

-- The board for the clients: one row per bounty as the client sees it.
local function wireRow(b)
    local tidx = 0
    if b.kind == "npc" and IsValid(b.ent) then tidx = b.ent:EntIndex()
    elseif b.kind == "player" then
        local p = B.TargetPlayer(b)
        if p then tidx = p:EntIndex() end
    end
    return { id = b.id, kind = b.kind, name = tostring(b.name or ""), model = tostring(b.model or ""), reward = math.floor(tonumber(b.reward) or 0),
        mode = b.mode, free = b.free and true or false, std = b.std and true or false, by = tostring(b.by or ""), byName = tostring(b.byName or ""),
        ends = b.ends or 0, tsid = tostring(b.sid or ""), tidx = tidx }
end

-- (everything but the time left: a change in any of these is an update)
local function sig(r)
    return table.concat({ r.kind, r.name, r.model, r.reward, r.mode, tostring(r.free), tostring(r.std), r.by, r.byName, r.ends, r.tsid, r.tidx }, "\1")
end

local function writeRow(r, now)
    net.WriteUInt(r.id, 24)
    net.WriteBool(r.kind == "npc")
    net.WriteString(string.sub(r.name, 1, 64))
    net.WriteString(string.sub(r.model, 1, 160))
    net.WriteUInt(math.Clamp(r.reward, 0, 4294967295), 32)
    net.WriteUInt(B.MODE_INDEX[r.mode] or 1, 2)
    net.WriteBool(r.free)
    net.WriteBool(r.std)
    net.WriteString(string.sub(r.by, 1, 24))
    net.WriteString(string.sub(r.byName, 1, 64))
    net.WriteUInt(math.Clamp(r.ends - now, 0, 16777215), 24)   -- (seconds left; the client counts down)
    net.WriteString(string.sub(r.tsid, 1, 24))
    net.WriteUInt(math.Clamp(r.tidx, 0, 65535), 16)
end

-- B.sent[id] = signature the clients have. Diffs go to everyone, a full
-- snapshot only to a player who asks (on joining).
B.sent = B.sent or {}

-- One bounty.diff: reset bool, then items { more bool, remove bool, id
-- UInt 24 (remove) | row (upsert) }, more = false at the end. Rows are
-- ~100-250 bytes: at most 150 a message (a bigger snapshot is split, the
-- first part has reset = true).
local function sendOps(ops, reset, target)
    local now = os.time()
    local i, first = 1, true
    repeat
        Net.Start("bounty.diff")
        net.WriteBool(reset and first)
        local n = 0
        while i <= #ops and n < 150 do
            local o = ops[i]
            net.WriteBool(true)
            net.WriteBool(o.remove == true)
            if o.remove then net.WriteUInt(o.id, 24) else writeRow(o.row, now) end
            i, n = i + 1, n + 1
        end
        net.WriteBool(false)
        if target then net.Send(target) else net.Broadcast() end
        first = false
    until i > #ops
end

-- B.SendList(ply): the whole board to one player.
function B.SendList(ply)
    if not IsValid(ply) then return end
    local ops = {}
    for _, b in pairs(B.list) do ops[#ops + 1] = { row = wireRow(b) } end
    sendOps(ops, true, ply)
end

-- What changed since the last flush, to everyone.
local function flush()
    local ops, seen = {}, {}
    for id, b in pairs(B.list) do
        seen[id] = true
        local r = wireRow(b)
        local s = sig(r)
        if B.sent[id] ~= s then
            B.sent[id] = s
            ops[#ops + 1] = { row = r }
        end
    end
    for id in pairs(B.sent) do
        if not seen[id] then
            B.sent[id] = nil
            ops[#ops + 1] = { remove = true, id = id }
        end
    end
    if #ops > 0 then sendOps(ops, false, nil) end
end
B.FlushBoard = flush

function B.Changed()
    save()
    timer.Create("Rhylib.Bounty.Send", 0.5, 1, flush)
end

Net.Receive("bounty.listreq", function(ply) B.SendList(ply) end, { rate = 1, burst = 3 })
-- A target joining or leaving changes their tidx: flush sends that
-- bounty's row only (nothing else changed).
Rhylib.Hook.Add("PlayerInitialSpawn", "bounty.board", function() timer.Create("Rhylib.Bounty.Send", 2, 1, flush) end)
Rhylib.Hook.Add("PlayerDisconnected", "bounty.board", function() timer.Create("Rhylib.Bounty.Send", 1, 1, flush) end)

-- B.Close(b, why): take a bounty off the board.
function B.Close(b, why)
    if not B.list[b.id] then return end
    B.list[b.id] = nil
    hook.Run("Rhylib.BountyClosed", b, why)
    B.Changed()
end

-- B.Add(b): put a bounty on the board (fills id, at, ends). Returns it.
function B.Add(b)
    b.id = B.nextId
    B.nextId = B.nextId + 1
    b.at = os.time()
    b.ends = b.at + math.max(60, tonumber(B.Cfg("life")) or 7200)
    B.list[b.id] = b
    hook.Run("Rhylib.BountyPosted", b)
    B.Changed()
    return b
end

-- B.OnTarget(tkey): open bounties on a target key.
function B.OnTarget(tkey)
    local out = {}
    for _, b in pairs(B.list) do if b.tkey == tkey then out[#out + 1] = b end end
    return out
end

-- Expiry: refund the poster minus the fee.
timer.Create("Rhylib.Bounty.Expire", 30, 0, function()
    local now = os.time()
    for _, b in pairs(B.list) do
        if now >= b.ends then
            if not b.free then refund(b.by, b.reward * (1 - (tonumber(B.Cfg("fee")) or 0))) end
            B.Close(b, "expired")
        elseif b.kind == "npc" and not IsValid(b.ent) and not b.dead then
            B.Close(b, "gone")   -- (removed without dying)
        end
    end
end)

--------------------------------------------------------------------------
-- Contracts and proof (inventory items)
--------------------------------------------------------------------------

local function Inv() return Rhylib.Inventory end

local function modeLabel(m)
    for _, o in ipairs(B.MODES) do if o[1] == m then return o[2] end end
    return m
end

-- Config notifyTarget: the target hears about a bounty posted on them (not
-- NPC or test-bot bounties). A tick later, so a standalone bounty that
-- failed (no room for the contract) and closed again says nothing.
-- notifyAmount false leaves the reward out.
Rhylib.Hook.Add("Rhylib.BountyPosted", "bounty.notify", function(b)
    if b.kind ~= "player" or b.botId or not B.Cfg("notifyTarget") then return end
    timer.Simple(0, function()
        if not B.list[b.id] then return end
        local p = B.TargetPlayer(b)
        if not p then return end
        local text = "There's a price on your head (" .. string.lower(modeLabel(b.mode)) .. ")"
        if B.Cfg("notifyAmount") then text = text .. ": " .. money(b.reward) end
        B.Msg(p, false, text)
    end)
end)

-- The items of an id a player carries: list of instances.
local function carried(ply, id)
    local out = {}
    local I = Inv()
    if not (I and I.Get) then return out end
    for _, inst in pairs(I.Get(ply).byUid) do
        if inst.id == id then out[#out + 1] = inst end
    end
    return out
end
B.Carried = carried

local function contractData(b)
    return { bid = b.id, tkey = b.tkey, name = b.name, std = b.std or nil,
        note = "#" .. b.id .. " Wanted: " .. b.name .. " · " .. modeLabel(b.mode) .. " · " .. money(b.reward) .. (b.std and " · standalone" or "") }
end

-- B.HasContract(ply, bid): the instance of a contract for that bounty, or nil.
function B.HasContract(ply, bid)
    for _, inst in ipairs(carried(ply, B.CONTRACT)) do
        if istable(inst.data) and inst.data.bid == bid then return inst end
    end
end

-- B.ContractTargets(ply): set of target keys of the contracts a player carries.
function B.ContractTargets(ply)
    local out = {}
    for _, inst in ipairs(carried(ply, B.CONTRACT)) do
        if istable(inst.data) and inst.data.tkey and B.list[inst.data.bid] then out[inst.data.tkey] = true end
    end
    return out
end

-- B.TargetKey(ent): the target key of a player or npc ("p" .. sid / the
-- npc's bounty key), or nil.
function B.TargetKey(ent)
    if not IsValid(ent) then return nil end
    if ent:IsPlayer() then return B.PlayerKey(ent) end
    return ent.rhylibBountyKey
end

--------------------------------------------------------------------------
-- Posting, accepting, cancelling
--------------------------------------------------------------------------

local function isGM(ply, cb)
    Rhylib.Perms.Check(ply, "rhylib.bounty.gm", function(ok) if IsValid(ply) then cb(ok) end end)
end

local function postedBy(ply)
    local n, s = 0, sid(ply)
    for _, b in pairs(B.list) do if b.by == s then n = n + 1 end end
    return n
end

Net.Receive("bounty.post", function(ply)
    local office = net.ReadEntity()
    local tsid = string.sub(net.ReadString(), 1, 24)
    local reward = net.ReadUInt(32)
    local mode = B.MODES[net.ReadUInt(2)]
    local std, free = net.ReadBool(), net.ReadBool()
    if not B.NearOffice(ply, office) then return B.Msg(ply, false, "Go to a Bounty Office") end
    if not mode then return B.Msg(ply, false, "Pick dead, alive or either") end
    local target = player.GetBySteamID64(tsid)
    if not IsValid(target) then return B.Msg(ply, false, "That player isn't on the server") end
    isGM(ply, function(gm)
        if not IsValid(target) then return B.Msg(ply, false, "That player left") end
        if free and not gm then return B.Msg(ply, false, "Only staff post free bounties") end
        if target == ply and not (gm and free) then return B.Msg(ply, false, "You can't put a bounty on yourself") end
        if not free then
            local lo, hi = tonumber(B.Cfg("postMin")) or 0, tonumber(B.Cfg("postMax")) or 1e6
            if reward < lo or reward > hi then return B.Msg(ply, false, "Rewards are " .. money(lo) .. " to " .. money(hi)) end
            if postedBy(ply) >= (tonumber(B.Cfg("maxPerPoster")) or 3) then return B.Msg(ply, false, "You already have the most bounties out you're allowed") end
            if not canPay(ply, reward) then return B.Msg(ply, false, "You can't afford " .. money(reward)) end
        else
            reward = math.Clamp(reward, 1, 10000000)
        end
        local b = {
            kind = "player", tkey = B.PlayerKey(target), sid = target:IsBot() and "" or tsid, botId = target:IsBot() and target:UserID() or nil,
            name = target:Nick(), model = target:GetModel(),
            reward = reward, mode = mode[1], by = free and "" or sid(ply), byName = free and "Bounty office" or ply:Nick(),
            free = free or nil, std = std or nil,
        }
        if not free then take(ply, reward) end
        B.Add(b)
        if std then
            local I = Inv()
            local left = I and I.AddItem and I.AddItem(ply, B.CONTRACT, 1, contractData(b)) or 1
            if left > 0 then
                if not free then give(ply, reward) end
                B.Close(b, "cancelled")
                return B.Msg(ply, false, "No room for the contract in your inventory")
            end
        end
        B.Msg(ply, true, "Bounty posted on " .. b.name .. ": " .. money(reward) .. (std and ". The contract is in your inventory: give it to a hunter." or "."))
    end)
end, { rate = 2, burst = 3 })

Net.Receive("bounty.npc", function(ply)
    local ent = net.ReadEntity()
    local reward = net.ReadUInt(32)
    local name = string.Trim(string.sub(net.ReadString(), 1, 40))
    if not (IsValid(ent) and (ent:IsNPC() or ent:IsNextBot())) then return B.Msg(ply, false, "That isn't an NPC") end
    if ply:GetPos():DistToSqr(ent:GetPos()) > 3000 * 3000 then return B.Msg(ply, false, "Too far away") end
    isGM(ply, function(gm)
        if not gm then return B.Msg(ply, false, "Staff only") end
        if not IsValid(ent) then return end
        local b = { kind = "npc", ent = ent, name = name ~= "" and name or (ent.PrintName or ent:GetClass()), model = ent:GetModel(),
            reward = math.Clamp(reward, 1, 10000000), mode = "dead", by = "", byName = "Bounty office", free = true }
        B.Add(b)
        if not ent.rhylibBountyKey then ent.rhylibBountyKey = "n" .. b.id end
        b.tkey = ent.rhylibBountyKey
        if ent.SetShouldServerRagdoll then ent:SetShouldServerRagdoll(true) end
        B.Changed()
        B.Msg(ply, true, "Bounty on " .. b.name .. ": " .. money(b.reward))
    end)
end, { rate = 2, burst = 3 })

Net.Receive("bounty.accept", function(ply)
    local office = net.ReadEntity()
    local b = B.list[net.ReadUInt(32)]
    if not B.NearOffice(ply, office) then return B.Msg(ply, false, "Go to a Bounty Office") end
    if not b then return B.Msg(ply, false, "That bounty is gone") end
    if b.std then return B.Msg(ply, false, "A standalone contract: only the poster can hand it out") end
    if not B.MayHunt(ply) then return B.Msg(ply, false, "Only bounty hunters take contracts") end
    if b.tkey == B.TargetKey(ply) then return B.Msg(ply, false, "That one's on you") end
    if b.by ~= "" and b.by == sid(ply) then return B.Msg(ply, false, "You posted that one") end
    if B.HasContract(ply, b.id) then return B.Msg(ply, false, "You already have that contract") end
    local held = 0   -- (only contracts whose bounty is still open count)
    for _, inst in ipairs(carried(ply, B.CONTRACT)) do
        if istable(inst.data) and B.list[inst.data.bid] then held = held + 1 end
    end
    local limit = B.ContractLimit(ply)
    if held >= limit then return B.Msg(ply, false, "You can hold " .. limit .. " contract" .. (limit == 1 and "" or "s") .. " at once") end
    local I = Inv()
    if not (I and I.AddItem) or I.AddItem(ply, B.CONTRACT, 1, contractData(b)) > 0 then
        return B.Msg(ply, false, "No room for the contract")
    end
    B.Msg(ply, true, "Contract taken: " .. b.name .. " (" .. modeLabel(b.mode) .. ", " .. money(b.reward) .. ")")
end, { rate = 3, burst = 4 })

Net.Receive("bounty.cancel", function(ply)
    local b = B.list[net.ReadUInt(32)]
    if not b then return end
    isGM(ply, function(gm)
        if not (gm or (b.by ~= "" and b.by == sid(ply))) then return B.Msg(ply, false, "Not your bounty") end
        if not B.list[b.id] then return end
        if not b.free then
            local keep = (b.by == sid(ply)) and (tonumber(B.Cfg("fee")) or 0) or 0   -- (staff cancel: full refund)
            refund(b.by, b.reward * (1 - keep))
        end
        B.Close(b, "cancelled")
        B.Msg(ply, true, "Bounty on " .. b.name .. " cancelled")
    end)
end, { rate = 2, burst = 3 })

--------------------------------------------------------------------------
-- Bodies and proof
--------------------------------------------------------------------------

-- Is anyone paying for this target dead?
local function wantedDead(tkey)
    for _, b in pairs(B.list) do
        if b.tkey == tkey and b.mode ~= "alive" then return true end
    end
    return false
end

-- The pose of an entity now (bone matrices), to build a body from.
local function capture(ent)
    local c = { model = ent:GetModel(), skin = ent:GetSkin(), pos = ent:GetPos(), ang = ent:GetAngles(), mats = {}, groups = {},
        col = ent.GetPlayerColor and ent:GetPlayerColor() or nil, vel = ent:GetVelocity() }
    for _, bg in ipairs(ent:GetBodyGroups() or {}) do c.groups[bg.id] = ent:GetBodygroup(bg.id) end
    if ent.SetupBones then ent:SetupBones() end   -- (client only; the server's bones are current anyway)
    for i = 0, ent:GetBoneCount() - 1 do
        local m = ent:GetBoneMatrix(i)
        if m then c.mats[i] = m end
    end
    return c
end

local function build(c)
    if not (c.model and util.IsValidModel(c.model)) then return nil end
    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then return nil end
    rag:SetModel(c.model)
    rag:SetPos(c.pos)
    rag:SetAngles(c.ang)
    rag:SetSkin(c.skin or 0)
    for id, v in pairs(c.groups) do rag:SetBodygroup(id, v) end
    rag:Spawn()
    rag:Activate()
    rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        local m = c.mats[rag:TranslatePhysBoneToBone(i)]
        if IsValid(phys) and m then
            phys:SetPos(m:GetTranslation())
            phys:SetAngles(m:GetAngles())
            phys:SetVelocity(c.vel or vector_origin)
            phys:Wake()
        end
    end
    if c.col then rag:SetNW2Vector("rhylib_bountyCol", c.col) end   -- (player colour; cl_20_wheel.lua)
    rag.rhylibBountyOwned = true
    return rag
end

-- B.MarkBody(rag, tkey, name): a ragdoll proof can be collected from.
function B.MarkBody(rag, tkey, name)
    if not IsValid(rag) then return end
    B.bodies[rag] = { tkey = tkey, name = name, at = os.time() }
    rag:SetNW2Bool("rhylib_bountyBody", true)
    rag:SetNW2String("rhylib_bountyName", name or "")
    local life = tonumber(B.Cfg("bodyLife")) or 150
    timer.Simple(life, function()
        if not IsValid(rag) then return end
        B.bodies[rag] = nil
        rag:SetNW2Bool("rhylib_bountyBody", false)
        local L = Rhylib.Lying
        local held = false
        for _, r in pairs(L and L.corpse or {}) do if r == rag then held = true end end
        if not held then rag:Remove() end
    end)
end

-- A wanted player died: their body (the lying corpse, or one made here).
Rhylib.Hook.Add("PlayerDeath", "bounty.body", function(ply)
    local tkey = B.PlayerKey(ply)
    if not wantedDead(tkey) then return end
    local cap = capture(ply)
    timer.Simple(0.05, function()
        if not IsValid(ply) or not wantedDead(tkey) then return end
        local rag = ply:GetNW2Entity(Rhylib.NW.CORPSE)
        if not IsValid(rag) then
            rag = build(cap)
            if not IsValid(rag) then return end
            ply:SetNW2Bool("rhylib_ragCorpse", true)   -- (rhylib_core hides the engine's own ragdoll)
            ply:SetNW2Entity(Rhylib.NW.CORPSE, rag)
        end
        B.MarkBody(rag, tkey, ply:Nick())
    end)
end)

-- Leaving doesn't take the body either (rhylib_core removes its corpse
-- on disconnect).
Rhylib.Hook.Add("PlayerDisconnected", "bounty.body", function(ply)
    local L = Rhylib.Lying
    if L and L.corpse and IsValid(L.corpse[ply]) and B.bodies[L.corpse[ply]] then L.corpse[ply] = nil end
end, -200)

Rhylib.Hook.Add("EntityRemoved", "bounty.body", function(ent)
    if B.bodies[ent] then B.bodies[ent] = nil end
end)

-- Respawning doesn't take the body with it (rhylib_core removes its
-- corpse at -100): it stays for bodyLife.
Rhylib.Hook.Add("PlayerSpawn", "bounty.body", function(ply)
    local L = Rhylib.Lying
    if L and L.corpse and IsValid(L.corpse[ply]) and B.bodies[L.corpse[ply]] then L.corpse[ply] = nil end
end, -200)

-- NPC targets: the engine's server ragdoll (SetShouldServerRagdoll at
-- posting), else one made from the pose at death. B.npcBodies[tkey] =
-- the body made for that NPC's death (one either way).
B.npcBodies = B.npcBodies or {}
Rhylib.Hook.Add("CreateEntityRagdoll", "bounty.body", function(owner, rag)
    if not (IsValid(owner) and owner.rhylibBountyKey and wantedDead(owner.rhylibBountyKey)) then return end
    local key = owner.rhylibBountyKey
    local old = B.npcBodies[key]
    if IsValid(old) and old.rhylibBountyOwned then old:Remove() end   -- (a fallback made first)
    B.npcBodies[key] = rag
    B.MarkBody(rag, key, owner.rhylibBountyName or owner.PrintName or owner:GetClass())
end)

Rhylib.Hook.Add("OnNPCKilled", "bounty.body", function(npc)
    local tkey = IsValid(npc) and npc.rhylibBountyKey
    if not tkey then return end
    for _, b in pairs(B.list) do if b.tkey == tkey then b.dead = true end end
    if not wantedDead(tkey) then return end
    local name
    for _, b in pairs(B.list) do if b.tkey == tkey then name = b.name end end
    npc.rhylibBountyName = name
    local cap = capture(npc)
    B.npcBodies[tkey] = nil
    timer.Simple(0, function()
        if IsValid(B.npcBodies[tkey]) then return end   -- (the engine made a server ragdoll)
        local rag = build(cap)
        if not IsValid(rag) then return end
        B.npcBodies[tkey] = rag
        B.MarkBody(rag, tkey, name)
    end)
end)

-- Collecting proof (the wheel's "Collect proof"): timed, stay close.
Net.Receive("bounty.collect", function(ply)
    local rag = net.ReadEntity()
    local body = IsValid(rag) and B.bodies[rag]
    if not body or body.taken then
        Net.Start("bounty.collectx") net.WriteString(body and "Someone already took the proof" or "Nothing to collect here") net.Send(ply)
        return
    end
    if body.tkey == B.PlayerKey(ply) then
        Net.Start("bounty.collectx") net.WriteString("That's your own body") net.Send(ply)
        return
    end
    if not ply:Alive() or ply:GetPos():DistToSqr(rag:GetPos()) > 130 * 130 then
        Net.Start("bounty.collectx") net.WriteString("Too far from the body") net.Send(ply)
        return
    end
    local t = tonumber(B.Cfg("collectTime")) or 5
    if B.Has(ply, "bh_kit") then t = t * B.Mult("fieldKit") end
    if B.Has(ply, "bh_finisher") then t = t * B.Mult("finisherCollect") end
    B.collecting[ply] = { body = rag, ends = CurTime() + t, pos = ply:GetPos() }
end, { rate = 3, burst = 3 })

local function stopCollect(ply, why)
    B.collecting[ply] = nil
    if IsValid(ply) then
        Net.Start("bounty.collectx")
        net.WriteString(why or "")
        net.Send(ply)
    end
end

timer.Create("Rhylib.Bounty.Collect", 0.1, 0, function()
    for ply, c in pairs(B.collecting) do
        if not IsValid(ply) then
            B.collecting[ply] = nil
        else
            local body = IsValid(c.body) and B.bodies[c.body]
            if not body or body.taken then stopCollect(ply, "The proof is gone")
            elseif not ply:Alive() or ply:GetPos():DistToSqr(c.pos) > 40 * 40 then stopCollect(ply, "Stopped: you moved")
            elseif CurTime() >= c.ends then
                local I = Inv()
                local left = I and I.AddItem and I.AddItem(ply, B.PROOF, 1, { tkey = body.tkey, name = body.name, at = body.at,
                    note = "Proof: " .. tostring(body.name) .. " · " .. os.date("%H:%M", body.at) }) or 1
                if left > 0 then
                    stopCollect(ply, "No room for the proof")
                else
                    body.taken = true
                    c.body:SetNW2Bool("rhylib_bountyTaken", true)
                    stopCollect(ply, "")
                    B.Msg(ply, true, "Proof collected: " .. tostring(body.name) .. ". Turn it in at a Bounty Office.")
                end
            end
        end
    end
end)

--------------------------------------------------------------------------
-- Turning in
--------------------------------------------------------------------------

local function pay(ply, b, mult, how)
    local n = math.floor(b.reward * (mult or 1))
    give(ply, n)
    hook.Run("Rhylib.BountyClaimed", b, ply, how)
    B.Close(b, "claimed")
    return n
end

-- B.TurnIn(ply): everything the player can claim (proof items, an
-- escorted prisoner). Returns total paid, lines.
function B.TurnIn(ply)
    local I = Inv()
    local total, lines = 0, {}
    -- Proof: every open dead/either bounty on that target posted before the death.
    local own = B.PlayerKey(ply)
    for _, proof in ipairs(carried(ply, B.PROOF)) do
        local d = proof.data or {}
        local got = 0
        for _, b in pairs(B.list) do
            -- (nobody claims the bounty on themselves)
            if b.tkey ~= own and b.tkey == d.tkey and b.mode ~= "alive" and (b.at or 0) <= (tonumber(d.at) or 0) and not (b.by ~= "" and b.by == sid(ply)) then
                local contract = b.std and B.HasContract(ply, b.id)
                if not b.std or contract then
                    got = got + pay(ply, b, 1, "proof")
                    if contract then I.Remove(ply, contract.uid, 1) end
                end
            end
        end
        if got > 0 then
            I.Remove(ply, proof.uid, 1)
            total = total + got
            lines[#lines + 1] = tostring(d.name) .. ": " .. money(got)
        end
    end
    -- A prisoner you escort.
    -- Only hunters turn prisoners in (not MPs or bystanders escorting one).
    local MP = Rhylib.MP
    if MP and MP.cuffed and B.MayHunt(ply) then
        for p in pairs(MP.cuffed) do
            if IsValid(p) and MP.EscortedBy(p) == ply then
                local got = 0
                for _, b in pairs(B.list) do
                    if b.tkey == B.PlayerKey(p) and b.mode ~= "dead" and not (b.by ~= "" and b.by == sid(ply)) then
                        local contract = b.std and B.HasContract(ply, b.id)
                        if not b.std or contract then
                            -- Bonuses only on office (staff) bounties: a player's
                            -- bounty pays exactly what the poster put up.
                            local m = 1
                            if b.free then
                                if b.mode == "either" then m = m * (tonumber(B.Cfg("aliveBonus")) or 1) end
                                if B.Has(ply, "bh_bring") then m = m * B.Mult("bring") end
                            end
                            got = got + pay(ply, b, m, "alive")
                            if contract then I.Remove(ply, contract.uid, 1) end
                        end
                    end
                end
                if got > 0 then
                    total = total + got
                    lines[#lines + 1] = p:Nick() .. " (alive): " .. money(got)
                    MP.SetEscort(p, nil)
                    MP.Uncuff(p, ply)
                    p.rhylibBound = nil
                    p:Spawn()
                    Rhylib.Notify(p, ply:Nick() .. " handed you in. You're free to go.", "info", "Bounty")
                end
            end
        end
    end
    return total, lines
end

Net.Receive("bounty.turnin", function(ply)
    local office = net.ReadEntity()
    if not B.NearOffice(ply, office) then return B.Msg(ply, false, "Go to a Bounty Office") end
    if not Inv() then return end
    local total, lines = B.TurnIn(ply)
    if total <= 0 then return B.Msg(ply, false, "Nothing to claim: no proof or prisoner with an open bounty (standalone bounties need their contract)") end
    B.Msg(ply, true, "Paid " .. money(total) .. ": " .. table.concat(lines, ", "))
end, { rate = 2, burst = 3 })

--------------------------------------------------------------------------
-- The office
--------------------------------------------------------------------------

-- B.Open(ply, office): open the office window (ENT:Use).
function B.Open(ply, office)
    B.SendList(ply)
    Net.Start("bounty.open")
    net.WriteEntity(office)
    net.Send(ply)
end
