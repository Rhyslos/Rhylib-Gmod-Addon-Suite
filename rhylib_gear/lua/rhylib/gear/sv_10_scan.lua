--[[
    rhylib_gear_scan (admin, or the server console): every DarkRP job
    model's bodygroups (name, options and their names), then which models
    have each bodygroup name. Also lists skin counts and hair materials.
    Then it learns: each item's keyword rules (G.MATCH in sh_00_config.lua)
    run over every job model's groups and options, and the group / option
    names found that the built-in lists lack are saved, merged into the
    items at once (G.SetLearned, both realms: the cabinet, the inventory
    gear slots and wearing use them straight away) and sent to every
    client. The report says what each item matched on which models, what
    tied between items (not learned) and which bodygroups nothing matched.
    Printed to your console and saved to data/rhylib_gear_scan.txt on the
    server.
    rhylib_gear_scan reset: forget the learned names (built-in names only).
    Server only; perm rhylib.gear.admin.
    Saved data: Data "gear" / "learned" = { [item id] = { groups, on, down } },
    loaded when this file loads (server start, map change).
    Nets: rhylib.gear.learned (server -> client: UInt32 length +
    compressed JSON of G.learned; on request and after a scan / reset),
    rhylib.gear.learnreq (client -> server, empty, at InitPostEntity;
    answered once per player, rate 1/s).
    G.Scan() -> the lines (and writes the file); G.MatchOption(group,
    option) -> ids or nil, tied ids. Spawns one prop_dynamic per model for
    a moment, so run it on a quiet server.
]]

local G = Rhylib.Gear

Rhylib.Net.Register("gear.learned")

-- Send G.learned to one player, or everyone (target nil).
local function sendLearned(target)
    local data = util.Compress(util.TableToJSON(G.learned or {}) or "{}") or ""
    Rhylib.Net.Start("gear.learned")
    net.WriteUInt(#data, 32)
    if #data > 0 then net.WriteData(data, #data) end
    if target then net.Send(target) else net.Broadcast() end
end

Rhylib.Net.Receive("gear.learnreq", function(ply)
    if ply.rhylibGearLearnSent then return end
    ply.rhylibGearLearnSent = true
    sendLearned(ply)
end, { rate = 1, burst = 2 })

-- Bodygroups put right again on everyone (after the lists changed).
local function reapplyAll()
    if not G.Apply then return end
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() then G.Apply(ply) end
    end
end

-- Saved names, merged in at load.
G.SetLearned(Rhylib.Data.Get("gear", "learned") or {})

--------------------------------------------------------------------------
-- Keyword rules
--------------------------------------------------------------------------

-- Score of one rule entry in text (a word, or a table of words that all
-- have to be there), or nil.
local function hitEntry(text, e)
    if isstring(e) then return string.find(text, e, 1, true) and #e or nil end
    if not istable(e) then return nil end
    local sum = 0
    for _, w in ipairs(e) do
        if not string.find(text, w, 1, true) then return nil end
        sum = sum + #w
    end
    return sum
end

local function bestHit(text, list)
    local best
    for _, e in ipairs(list or {}) do
        local s = hitEntry(text, e)
        if s and (not best or s > best) then best = s end
    end
    return best
end

-- Groups the scan leaves alone: the helmet itself ("helmet", "parahelmet":
-- a name ending in helmet; the on / off toggle), hair, head and body,
-- unless the name itself has an item's word ("flashlighthelmet"). Groups
-- that only start with it ("helmet attachments") are scanned.
local function reservedGroup(gn)
    if gn == "head" or gn == "body" or gn == "face" then return true end
    if string.sub(gn, -6) == "helmet" or string.find(gn, "hair", 1, true) then
        for _, s in pairs(G.SHOWS) do
            if s.match and bestHit(gn, s.match.words) then return false end
        end
        return true
    end
    return false
end
G.ReservedGroup = reservedGroup

-- G.MatchOption(gn, on) -> { ids } (the best-scoring items) or nil, plus a
-- second list when several items tie (then nothing is learned).
-- Option-name hits beat "group option" hits; +10 when the group name also
-- has one of the item's words.
function G.MatchOption(gn, on)
    if G.IsOffName(on) or reservedGroup(gn) then return nil end
    local optHits, comboHits = {}, {}
    local both = gn .. " " .. on
    for id, s in pairs(G.SHOWS) do
        local m = s.match
        if m and not bestHit(on, m.notWords) and not bestHit(gn, m.notGroups) then
            local bonus = bestHit(gn, m.words) and 10 or 0
            local sc = bestHit(on, m.words)
            if sc and (not m.need or bestHit(on, m.need)) then
                optHits[#optHits + 1] = { id = id, score = 100 + sc + bonus }
            elseif m.groupFallback ~= false then
                local sc2 = bestHit(both, m.words)
                if sc2 and (not m.need or bestHit(both, m.need)) then
                    comboHits[#comboHits + 1] = { id = id, score = sc2 + bonus }
                end
            end
        end
    end
    local hits = #optHits > 0 and optHits or comboHits
    if #hits == 0 then return nil end
    local top = 0
    for _, h in ipairs(hits) do if h.score > top then top = h.score end end
    local ids = {}
    for _, h in ipairs(hits) do if h.score == top then ids[#ids + 1] = h.id end end
    table.sort(ids)
    if #ids > 1 then return nil, ids end
    return ids
end

--------------------------------------------------------------------------
-- Scan
--------------------------------------------------------------------------

-- Every model the jobs use: { model = { job names } }.
local function jobModels()
    local out, order = {}, {}
    for _, job in pairs(RPExtraTeams or {}) do
        local list = istable(job.model) and job.model or { job.model }
        for _, m in ipairs(list) do
            if isstring(m) and m ~= "" then
                m = string.lower(m)
                if not out[m] then
                    out[m] = {}
                    order[#order + 1] = m
                end
                table.insert(out[m], job.name or "?")
            end
        end
    end
    table.sort(order)
    return out, order
end

-- A model's bodygroups, read from a short-lived entity, plus its
-- G.ModelInfo (what players with it use).
local function groupsOf(model)
    if not util.IsValidModel(model) then return nil end
    local e = ents.Create("prop_dynamic")
    if not IsValid(e) then return nil end
    e:SetModel(model)
    e:Spawn()
    local list = { skins = e:SkinCount() or 1, mats = {}, info = G.ModelInfo(e) }
    for _, m in ipairs(e:GetMaterials() or {}) do
        if string.find(string.lower(m), "hair", 1, true) then list.mats[#list.mats + 1] = m end
    end
    for _, g in ipairs(e:GetBodyGroups() or {}) do
        local subs = {}
        for i = 0, (g.num or 1) - 1 do subs[#subs + 1] = (g.submodels and g.submodels[i]) or ("#" .. i) end
        list[#list + 1] = { id = g.id, name = g.name, subs = subs }
    end
    e:Remove()
    return list
end

local function shortModel(m)
    m = string.gsub(m, "^models/", "")
    return (string.gsub(m, "%.mdl$", ""))
end

-- "a, b, c +2 more"
local function listModels(models)
    local out = {}
    for i = 1, math.min(#models, 4) do out[i] = shortModel(models[i]) end
    local s = table.concat(out, ", ")
    if #models > 4 then s = s .. " +" .. (#models - 4) .. " more" end
    return s
end

local function inList(list, n)
    for _, v in ipairs(list or {}) do if v == n then return true end end
    return false
end

-- Learn from the scanned models: { { model, groups (groupsOf) } }.
-- Returns learned, pairs (id -> list of { gn, on, models }), ties,
-- unmatched (list of { model, gn, opts }).
local function learn(scanned)
    local pairsBy, pairKey = {}, {}
    local ties, tieKey = {}, {}
    local unmatched = {}
    local N = G.Norm
    for _, sm in ipairs(scanned) do
        for _, g in ipairs(sm.groups) do
            local gn = N(g.name)
            if #g.subs > 1 and not reservedGroup(gn) then
                local left = {}
                for _, sub in ipairs(g.subs) do
                    local on = N(sub)
                    local ids, tied = G.MatchOption(gn, on)
                    if ids then
                        local id = ids[1]
                        local k = id .. "\n" .. gn .. "\n" .. on
                        local p = pairKey[k]
                        if not p then
                            p = { gn = gn, on = on, models = {} }
                            pairKey[k] = p
                            pairsBy[id] = pairsBy[id] or {}
                            table.insert(pairsBy[id], p)
                        end
                        table.insert(p.models, sm.model)
                    elseif tied then
                        local k = gn .. "\n" .. on
                        local t = tieKey[k]
                        if not t then
                            t = { gn = gn, on = on, ids = tied, models = {} }
                            tieKey[k] = t
                            ties[#ties + 1] = t
                        end
                        table.insert(t.models, sm.model)
                    elseif not G.IsOffName(on) then
                        left[#left + 1] = on
                    end
                end
                if #left > 0 then unmatched[#unmatched + 1] = { model = sm.model, gn = gn, opts = left } end
            end
        end
    end
    -- Names the built-in lists lack. Optics: "down" options are the
    -- flipped-down look (on too when a group has no other option for it);
    -- other items list "down" names last.
    local learned = {}
    for id, list in pairs(pairsBy) do
        local s, b = G.SHOWS[id], G.BUILTIN[id] or {}
        local groups, on, down, onLate = {}, {}, {}, {}
        local byGroup = {}
        for _, p in ipairs(list) do
            byGroup[p.gn] = byGroup[p.gn] or {}
            table.insert(byGroup[p.gn], p.on)
        end
        for gn, opts in pairs(byGroup) do
            if not inList(b.groups, gn) and not inList(groups, gn) then groups[#groups + 1] = gn end
            local hasUp = false
            for _, o in ipairs(opts) do
                if not string.find(o, "down", 1, true) then hasUp = true end
            end
            for _, o in ipairs(opts) do
                local isDown = string.find(o, "down", 1, true) ~= nil
                if s.optics and isDown then
                    if not inList(b.down, o) and not inList(down, o) then down[#down + 1] = o end
                    if not hasUp and not inList(b.on, o) and not inList(onLate, o) then onLate[#onLate + 1] = o end
                elseif isDown then
                    if not inList(b.on, o) and not inList(onLate, o) then onLate[#onLate + 1] = o end
                elseif not inList(b.on, o) and not inList(on, o) then
                    on[#on + 1] = o
                end
            end
        end
        table.sort(groups) table.sort(on) table.sort(down) table.sort(onLate)
        for _, o in ipairs(onLate) do if not inList(on, o) then on[#on + 1] = o end end
        if #groups > 0 or #on > 0 or #down > 0 then
            learned[id] = { groups = groups, on = on, down = #down > 0 and down or nil }
        end
    end
    return learned, pairsBy, ties, unmatched
end

local function itemName(id)
    local s = G.SHOWS[id]
    return (s and s.name) or id
end

function G.Scan()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local models, order = jobModels()
    local byGroup, groupOrder = {}, {}
    local scanned = {}
    add("Rhylib bodygroup scan, " .. os.date("%Y-%m-%d %H:%M") .. ", " .. #order .. " job models")
    add("")
    for _, m in ipairs(order) do
        add(m)
        add("  jobs: " .. table.concat(models[m], ", "))
        local groups = groupsOf(m)
        if not groups then
            add("  (model missing on the server)")
        else
            scanned[#scanned + 1] = { model = m, groups = groups }
            for _, g in ipairs(groups) do
                if #g.subs > 1 then
                    add(string.format("  [%d] %s: %s", g.id, g.name, table.concat(g.subs, " | ")))
                    local key = string.lower(g.name)
                    if not byGroup[key] then
                        byGroup[key] = {}
                        groupOrder[#groupOrder + 1] = key
                    end
                    byGroup[key][#byGroup[key] + 1] = m
                end
            end
            if #groups <= 1 then add("  (no bodygroups)") end
            add("  skins: " .. tostring(groups.skins) .. (#groups.mats > 0 and ("  hair materials: " .. table.concat(groups.mats, ", ")) or ""))
        end
        add("")
    end
    table.sort(groupOrder)
    add("Bodygroup names (how many models have each):")
    for _, k in ipairs(groupOrder) do
        add(string.format("  %s: %d of %d", k, #byGroup[k], #order))
    end
    add("")

    -- Learn, save, use now.
    local learned, pairsBy, ties, unmatched = learn(scanned)
    G.SetLearned(learned)
    if next(learned) then
        Rhylib.Data.Set("gear", "learned", learned)
    else
        Rhylib.Data.Delete("gear", "learned")
    end
    sendLearned(nil)
    reapplyAll()

    add("Gear matching (keyword rules; group: option, models):")
    for _, id in ipairs(G.ORDER) do
        if G.SHOWS[id] and G.SHOWS[id].match then
            local list = pairsBy[id]
            add("  " .. itemName(id) .. " (" .. id .. ")" .. (learned[id] and "  [learned new names]" or ""))
            if not list then
                add("    nothing matched")
            else
                table.sort(list, function(a, b) return a.gn .. a.on < b.gn .. b.on end)
                for _, p in ipairs(list) do
                    add(string.format("    %s: %s  (%d: %s)", p.gn, p.on, #p.models, listModels(p.models)))
                end
            end
        end
    end
    add("")
    if #ties > 0 then
        add("Unsure (several items match equally, not learned):")
        for _, t in ipairs(ties) do
            add(string.format("  %s: %s -> %s  (%d: %s)", t.gn, t.on, table.concat(t.ids, " / "), #t.models, listModels(t.models)))
        end
        add("")
    end
    add("Bodygroups nothing matched (helmet, hair, head and body groups are left alone):")
    if #unmatched == 0 then add("  none") end
    for _, u in ipairs(unmatched) do
        add(string.format("  %s  %s: %s", shortModel(u.model), u.gn, table.concat(u.opts, " | ")))
    end
    add("")
    add("What each model shows now (the gear cabinet offers these):")
    for _, sm in ipairs(scanned) do
        local shows = {}
        for _, id in ipairs(G.ORDER) do
            if G.ITEMS[id] and G.InfoShows(sm.groups.info, id) then shows[#shows + 1] = itemName(id) end
        end
        add("  " .. shortModel(sm.model) .. ": " .. (#shows > 0 and table.concat(shows, ", ") or "nothing"))
    end
    add("")
    add("Learned names are saved and used now. rhylib_gear_scan reset forgets them.")
    file.Write("rhylib_gear_scan.txt", table.concat(lines, "\n"))
    return lines
end

-- G.ResetLearned(): back to the built-in names only (saved, sent).
function G.ResetLearned()
    G.SetLearned({})
    Rhylib.Data.Delete("gear", "learned")
    sendLearned(nil)
    reapplyAll()
end

Rhylib.Command.Add({
    name = "rhylib_gear_scan",
    perm = "rhylib.gear.admin",
    args = "[reset]",
    help = "List every job model's bodygroups and learn which are gear parts (console and data/rhylib_gear_scan.txt); reset forgets the learned names",
    tag = "Gear",
    fn = function(ply, args)
        if args and string.lower(tostring(args[1] or "")) == "reset" then
            G.ResetLearned()
            return "Learned gear bodygroup names forgotten: only the built-in names are used now.", "good"
        end
        local lines = G.Scan()
        for _, l in ipairs(lines) do
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, l) else print(l) end
        end
        local n = table.Count(G.learned or {})
        return "Bodygroup scan done: " .. n .. " gear item(s) learned new names and are in use now. Report in the console and data/rhylib_gear_scan.txt on the server.", "good"
    end,
})
