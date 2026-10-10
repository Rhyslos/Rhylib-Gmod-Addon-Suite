--[[
    Battalion computer (server): log search, and the battalion board.

    Search (logs and medical records):
      dp.tfind   entity, text, days (10 bits, 0 = any time) -> dp.tfound:
                 matching ids (count 8, ids 20). Matches when the title,
                 text, author or patient contain the text.

    Battalion info: one living text per battalion (Data "dp_info"/bn =
    { txt, by, t }), edited over time by those who can post; sent with
    the board and in the datapad download.

    Board (battalion computers only): posts in sections Session (3) and
    AAR (4, after-action reports, with an outcome: 1 success, 2 partial,
    3 failure, and the session they report on). Info (1) and Plans (2) are
    old sections: their posts stay readable, no new ones. Managers (SGT+)
    may write AARs and edit or delete their own. A session has a time
    (os.time, shown in each player's own time zone); past sessions are
    listed as an archive. Posts can be pinned. At most 120 posts (oldest
    dropped).
    Who may post: admins and the battalion's commander, or anyone the
    Rhylib.CanPostBoard(ply, battalion) hook allows (rhylib_roster: rank
    boardRank, LT, and up).
      dp.bopen   entity -> dp.board: entity, canPost, canAAR, posts (count 8;
                 id 16, section 3, title, author, time 32, session time 32,
                 pinned, outcome 2, session id 16, mine), then the info
      dp.bget    entity, id (16) -> dp.bbody (D.SendPost: text, sign-ups, check-ins)
      dp.bsave   entity, id (16, 0 = new), section (3), title, text,
                 session time (32), outcome (2), session id (16)
      dp.bdel    entity, id (16)
      dp.bpin    entity, id (16)
      dp.binfo   entity, text: save the battalion info

    Data "dp_board"/battalion = { next, list } (post: { id, sec, ti, b, at,
    oc, ses, a, s, t, pin, rv, ci }; rv/ci: see sv_60_unit).
]]

local D = Rhylib.Datapad

Rhylib.Net.Register("dp.tfound")
Rhylib.Net.Register("dp.board")
Rhylib.Net.Register("dp.bbody")

D.SEC_INFO, D.SEC_PLANS, D.SEC_SESSION, D.SEC_AAR = 1, 2, 3, 4   -- board sections (3 bits on the wire)
local BOARD_CAP = 120

--------------------------------------------------------------------------
-- Search
--------------------------------------------------------------------------

D.TermRecv("dp.tfind", {
    read = function() return { q = string.lower(D.Clip(net.ReadString(), 64)), days = net.ReadUInt(10) } end,
    run = function(ply, ent, a, arg)
        local key = D.TermKey(ent)
        if not a.view or key == "" then return end
        local since = arg.days > 0 and (os.time() - arg.days * 86400) or 0
        local q = arg.q
        local out = {}
        for _, e in ipairs(D.Book(key).list) do
            if (e.t or 0) >= since and (q == "" or string.find(string.lower((e.ti or "") .. "\n" .. (e.b or "") .. "\n" .. (e.a or "") .. "\n" .. (e.pn or "")), q, 1, true)) then
                out[#out + 1] = e.id
                if #out >= 255 then break end
            end
        end
        Rhylib.Net.Start("dp.tfound")
        net.WriteUInt(#out, 8)
        for _, id in ipairs(out) do net.WriteUInt(id, 20) end
        net.Send(ply)
    end,
}, { rate = 3, burst = 4 })

--------------------------------------------------------------------------
-- Board
--------------------------------------------------------------------------

-- D.Board(bn): the battalion's board { next, list (newest first) }.
function D.Board(bn)
    local b = D.Load("dp_board", bn, nil)
    if not b.list then b.next, b.list = 1, {} end
    return b
end

-- D.CanPost(ply, bn, admin): full posting rights on bn's board (sessions,
-- pins, any post, the battalion info). admin = the computer's a.admin.
-- Order: admin, then hook Rhylib.CanPostBoard(ply, bn) (true/false wins),
-- else a member with D.IsCommander.
function D.CanPost(ply, bn, admin)
    if admin then return true end
    local r = hook.Run("Rhylib.CanPostBoard", ply, bn)
    if r ~= nil then return r end
    return D.Battalion(ply) == bn and D.IsCommander(ply)
end

-- AARs: managers too.
local function canAAR(ply, bn, admin)
    return D.CanPost(ply, bn, admin) or (D.IsUnitManager and D.IsUnitManager(ply, bn, admin) and D.Battalion(ply) == bn) or false
end

-- May ply edit or delete this post?
local function canChange(ply, bn, admin, p)
    if D.CanPost(ply, bn, admin) then return true end
    return p.sec == D.SEC_AAR and p.s == ply:SteamID64() and canAAR(ply, bn, admin)
end

-- D.WriteInfo(bn): write the battalion info into the current net message:
-- text, edited by, time 32 ("" bn = empty).
function D.WriteInfo(bn)
    local i = bn ~= "" and D.Load("dp_info", bn, {}) or {}
    net.WriteString(i.txt or "")
    net.WriteString(i.by or "")
    net.WriteUInt(i.t or 0, 32)
end

local function sendBoard(ply, ent, a)
    local bn = ent:GetBattalion()
    local list = bn ~= "" and a.view and D.Board(bn).list or {}
    local me = ply:SteamID64()
    Rhylib.Net.Start("dp.board")
    net.WriteEntity(ent)
    net.WriteBool(bn ~= "" and D.CanPost(ply, bn, a.admin))
    net.WriteBool(bn ~= "" and canAAR(ply, bn, a.admin))
    local n = math.min(#list, 255)
    net.WriteUInt(n, 8)
    for i = 1, n do
        local p = list[i]
        net.WriteUInt(p.id, 16)
        net.WriteUInt(p.sec or 1, 3)
        net.WriteString(p.ti or "")
        net.WriteString(p.a or "?")
        net.WriteUInt(p.t or 0, 32)
        net.WriteUInt(p.at or 0, 32)
        net.WriteBool(p.pin or false)
        net.WriteUInt(p.oc or 0, 2)
        net.WriteUInt(p.ses or 0, 16)
        net.WriteBool(p.s ~= nil and p.s == me)
    end
    D.WriteInfo(a.view and bn or "")
    net.Send(ply)
end

local function boardTerm(ent) return not D.IsMedTerm(ent) and ent:GetBattalion() ~= "" end

local function findPost(board, id)
    for i, p in ipairs(board.list) do
        if p.id == id then return p, i end
    end
end

D.TermRecv("dp.bopen", {
    run = function(ply, ent, a)
        if boardTerm(ent) then sendBoard(ply, ent, a) end
    end,
}, { rate = 3, burst = 4 })

-- D.SendPost(ply, p): send dp.bbody, a post's text plus sign-ups and
-- check-ins for sessions: id 16, text, count 8 x (name, choice 2 bits 1-3),
-- my choice (2), count 8 x checked-in name, me checked in (bool).
function D.SendPost(ply, p)
    local me = "s" .. (ply:SteamID64() or "")
    Rhylib.Net.Start("dp.bbody")
    net.WriteUInt(p.id, 16)
    net.WriteString(p.b or "")
    local rv = {}
    for k, v in pairs(p.rv or {}) do
        if istable(v) then rv[#rv + 1] = v end
    end
    table.sort(rv, function(x, y) return (x.s or 0) < (y.s or 0) end)
    local n = math.min(#rv, 255)
    net.WriteUInt(n, 8)
    for i = 1, n do
        net.WriteString(rv[i].n or "?")
        net.WriteUInt(rv[i].s or 1, 2)
    end
    local mine = p.rv and p.rv[me]
    net.WriteUInt(istable(mine) and mine.s or 0, 2)
    local ci = {}
    for _, name in pairs(p.ci or {}) do ci[#ci + 1] = tostring(name) end
    table.sort(ci)
    n = math.min(#ci, 255)
    net.WriteUInt(n, 8)
    for i = 1, n do net.WriteString(ci[i]) end
    net.WriteBool(p.ci and p.ci[me] ~= nil or false)
    net.Send(ply)
end

D.TermRecv("dp.bget", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not boardTerm(ent) or not a.view then return end
        local p = findPost(D.Board(ent:GetBattalion()), id)
        if not p then return end
        D.SendPost(ply, p)
    end,
})

D.TermRecv("dp.bsave", {
    read = function()
        return {
            id = net.ReadUInt(16), sec = net.ReadUInt(3),
            ti = D.Clip(net.ReadString(), D.Cfg("titleMax")),
            b = D.Clip(net.ReadString(), D.Cfg("bodyMax") * 2, true),
            at = net.ReadUInt(32),
            oc = net.ReadUInt(2), ses = net.ReadUInt(16),
        }
    end,
    run = function(ply, ent, a, arg)
        if not boardTerm(ent) then return end
        local bn = ent:GetBattalion()
        if arg.sec < D.SEC_INFO or arg.sec > D.SEC_AAR then return end
        local full = D.CanPost(ply, bn, a.admin)
        -- Without full rights: AARs only.
        if not full and not (arg.sec == D.SEC_AAR and canAAR(ply, bn, a.admin)) then return end
        if arg.id == 0 and arg.sec < D.SEC_SESSION then return end   -- (old sections: no new posts)
        if arg.ti == "" then arg.ti = "Untitled" end
        local at = arg.sec == D.SEC_SESSION and arg.at or 0
        local aar = arg.sec == D.SEC_AAR
        local oc = aar and arg.oc or 0
        local ses = aar and arg.ses or 0
        if arg.sec ~= D.SEC_AAR then arg.b = D.Clip(arg.b, D.Cfg("bodyMax"), true) end   -- (AARs may be twice bodyMax)
        local board = D.Board(bn)
        if arg.id == 0 then
            table.insert(board.list, 1, {
                id = board.next, sec = arg.sec, ti = arg.ti, b = arg.b, at = at, oc = oc, ses = ses,
                a = ply:Nick(), s = ply:SteamID64(), t = os.time(),
            })
            board.next = board.next % 65535 + 1
            while #board.list > BOARD_CAP do table.remove(board.list) end
        else
            local p = findPost(board, arg.id)
            if not p or not canChange(ply, bn, a.admin, p) then return end
            p.sec, p.ti, p.b, p.at, p.oc, p.ses = arg.sec, arg.ti, arg.b, at, oc, ses
        end
        D.Store("dp_board", bn, board)
        sendBoard(ply, ent, a)
    end,
}, { rate = 2, burst = 3 })

D.TermRecv("dp.bdel", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not boardTerm(ent) then return end
        local bn = ent:GetBattalion()
        local board = D.Board(bn)
        local p, i = findPost(board, id)
        if not i or not canChange(ply, bn, a.admin, p) then return end
        table.remove(board.list, i)
        D.Store("dp_board", bn, board)
        sendBoard(ply, ent, a)
    end,
})

D.TermRecv("dp.bpin", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not boardTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not D.CanPost(ply, bn, a.admin) then return end
        local board = D.Board(bn)
        local p = findPost(board, id)
        if not p then return end
        p.pin = not p.pin or nil
        D.Store("dp_board", bn, board)
        sendBoard(ply, ent, a)
    end,
})

D.TermRecv("dp.binfo", {
    read = function() return D.Clip(net.ReadString(), 4000, true) end,
    run = function(ply, ent, a, txt)
        if not boardTerm(ent) or not a.view then return end
        local bn = ent:GetBattalion()
        if not D.CanPost(ply, bn, a.admin) then return end
        D.Store("dp_info", bn, { txt = txt, by = ply:Nick(), t = os.time() })
        D.Touch(bn)
        sendBoard(ply, ent, a)
    end,
}, { rate = 2, burst = 3 })
