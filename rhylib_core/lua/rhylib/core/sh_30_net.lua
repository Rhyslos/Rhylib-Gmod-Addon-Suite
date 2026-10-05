--[[
    Networking helpers.

    All Rhylib messages are named "rhylib.<name>".

    1) Client-to-server requests, rate limited per player:
        -- server
        Rhylib.Net.Receive("inv.move", function(ply, len) ... end, { rate = 20, burst = 10 })
        -- client
        Rhylib.Net.Start("inv.move") net.WriteUInt(uid, 16) ... net.SendToServer()

    2) Batches: many small events per tick packed into one message
       per recipient. Used for things like blaster shots.
        -- server (create once, when the file loads)
        local shots = Rhylib.Net.CreateBatch("wep.shots", function(item)
            net.WriteUInt(item.shooter, 8)
            net.WriteVector(item.origin)
        end)
        shots:Send(ply, item)        -- one player
        shots:SendTo(players, item)  -- a list of players
        shots:Broadcast(item)        -- everyone
        -- client
        Rhylib.Net.ReceiveBatch("wep.shots", function()
            return { shooter = net.ReadUInt(8), origin = net.ReadVector() }
        end, function(item) ... end)

       Batches are flushed once per server tick; nothing is sent when
       nothing happened. In a message, each item is preceded by a 1 bit
       "another item follows" flag and the list ends with a 0 bit. A
       message is closed and a new one started once it passes about
       60 KB, under the 64 KB net message limit. A writer that errors
       is reported and its queue dropped, so it can't jam the batch.

    Write exact bit sizes (net.WriteUInt with a bit count). Never use
    net.WriteTable for anything sent often.
]]

Rhylib.Net = Rhylib.Net or {}
local Net = Rhylib.Net

local PREFIX = "rhylib."
Net.MSG_SOFT_LIMIT = 60000             -- bytes; start a new message past this

function Net.Name(name)
    return PREFIX .. name
end

function Net.Register(name)
    if SERVER then util.AddNetworkString(PREFIX .. name) end
end

function Net.Start(name)
    net.Start(PREFIX .. name)
end

-- Send the message that is being written (its size is recorded by the
-- net wrappers below).
local function finish(name, sendFn, target)
    sendFn(target)
end

-- Server traffic for the profiler: every net message (other addons' too),
-- bytes x recipients, by name ("rhylib." dropped). Costs nothing while the
-- profiler is off. Wrapped once (refresh-safe).
if SERVER and not net.rhylibWrapped then
    net.rhylibWrapped = true
    local start = net.Start
    net.Start = function(name, ...)
        Rhylib.Net.cur = name
        return start(name, ...)
    end
    local function label(name)
        if string.sub(name, 1, #PREFIX) == PREFIX then return string.sub(name, #PREFIX + 1) end
        return name
    end
    local function wrap(fname, count)
        local orig = net[fname]
        if not orig then return end
        net[fname] = function(a, ...)
            local P = Rhylib.Profiler
            local cur = Rhylib.Net.cur
            Rhylib.Net.cur = nil
            if cur and P and P.enabled then
                local n = count(a)
                if n > 0 then P.AddNet(label(cur), (net.BytesWritten() or 0) * n) end
            end
            return orig(a, ...)
        end
    end
    -- (bots get no net messages: they don't count)
    local function recipients(t)
        if istable(t) then
            local n = 0
            for i = 1, #t do
                local p = t[i]
                if IsValid(p) and not p:IsBot() then n = n + 1 end
            end
            return n
        end
        if type(t) == "CRecipientFilter" then return t:GetCount() end
        return (IsValid(t) and not t:IsBot()) and 1 or 0
    end
    wrap("Send", recipients)
    wrap("Broadcast", function() return #player.GetHumans() end)
    wrap("SendOmit", function(t) return math.max(0, #player.GetHumans() - recipients(t)) end)
    wrap("SendPVS", function() return 1 end)   -- (unknown: counted once)
    wrap("SendPAS", function() return 1 end)
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

if SERVER then
    local buckets = {}  -- [name][ply] = { tokens, last }

    -- opts.rate: messages per second allowed, opts.burst: max saved up.
    function Net.Receive(name, fn, opts)
        Net.Register(name)
        local rate = opts and opts.rate or 10
        local burst = opts and opts.burst or rate
        buckets[name] = buckets[name] or setmetatable({}, { __mode = "k" })
        local perPly = buckets[name]

        net.Receive(PREFIX .. name, function(len, ply)
            if not IsValid(ply) then return end
            local now = SysTime()
            local b = perPly[ply]
            if not b then
                b = { tokens = burst, last = now }
                perPly[ply] = b
            end
            b.tokens = math.min(burst, b.tokens + (now - b.last) * rate)
            b.last = now
            if b.tokens < 1 then return end  -- over the limit: drop silently
            b.tokens = b.tokens - 1
            fn(ply, len)
        end)
    end
else
    function Net.Receive(name, fn)
        net.Receive(PREFIX .. name, function(len)
            fn(len)
        end)
    end
end

--------------------------------------------------------------------------
-- Batches
--------------------------------------------------------------------------

if SERVER then
    local Batch = {}
    Batch.__index = Batch

    Net.batches = Net.batches or {}

    function Net.CreateBatch(name, writeItem)
        Net.Register(name)
        local b = Net.batches[name]
        if b then
            b.write = writeItem  -- autorefresh: keep queues, swap the writer
            return b
        end
        b = setmetatable({ name = name, write = writeItem, perPly = {}, all = {} }, Batch)
        Net.batches[name] = b
        return b
    end

    function Batch:Send(ply, item)
        local q = self.perPly[ply]
        if not q then
            q = {}
            self.perPly[ply] = q
        end
        q[#q + 1] = item
        self.dirty = true
    end

    function Batch:SendTo(players, item)
        for i = 1, #players do self:Send(players[i], item) end
    end

    function Batch:Broadcast(item)
        self.all[#self.all + 1] = item
        self.dirty = true
    end

    -- Writes items into as many messages as needed (each under the soft
    -- size limit). Also used by modules that send their own batches.
    function Net.SendItems(name, items, write, sendFn, target)
        local total, i = #items, 1
        local limit = Net.MSG_SOFT_LIMIT
        while i <= total do
            net.Start(PREFIX .. name)
            repeat
                net.WriteBool(true)
                write(items[i])
                i = i + 1
            until i > total or net.BytesWritten() > limit
            net.WriteBool(false)
            finish(name, sendFn, target)
        end
    end

    local function sendQueue(batch, queue, sendFn, target)
        local ok, err = pcall(Net.SendItems, batch.name, queue, batch.write, sendFn, target)
        if not ok then
            Rhylib.Error("core", "batch %s: writer failed, %d items dropped: %s", batch.name, #queue, tostring(err))
        end
    end

    local function clear(q)
        for i = #q, 1, -1 do q[i] = nil end
    end

    -- Queue tables are kept and emptied, so a busy tick allocates nothing
    -- here and an idle tick costs one flag check.
    function Batch:Flush()
        if not self.dirty then return end
        self.dirty = false
        for ply, q in pairs(self.perPly) do
            if not IsValid(ply) then
                self.perPly[ply] = nil  -- allowed while iterating with pairs
            elseif #q > 0 then
                sendQueue(self, q, net.Send, ply)
                clear(q)
            end
        end
        if #self.all > 0 then
            sendQueue(self, self.all, net.Broadcast)
            clear(self.all)
        end
    end

    -- Runs last in the tick, after modules have queued their events.
    Rhylib.Hook.Add("Tick", "core.net.flush", function()
        for _, b in pairs(Net.batches) do b:Flush() end
    end, 1000)
else
    function Net.ReceiveBatch(name, readItem, onItem)
        net.Receive(PREFIX .. name, function()
            -- A 1 bit before each item; 0 ends the list. The cap guards
            -- against a broken message looping forever.
            local n = 0
            while n < 4096 and net.ReadBool() do
                n = n + 1
                onItem(readItem())
            end
        end)
    end
end
