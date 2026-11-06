--[[
    Foliage for stealth (server): where players can hide from unaware
    droids. Three sources, all in one spatial hash (cells of 256 units):

      1. The map's static props: at map start the map file's game lump
         "sprp" (the model list and every prop's position) is read and
         each prop whose model file name has a foliage word
         (stealthFoliage "word=radius", not stealthFoliageSkip) is kept
         with that radius. Versions 4-13 and others: the prop record size
         is worked out from the lump size. Wrapped in pcall; any problem
         is a warning, never an error. Setting stealthFoliageMap.
      2. Concealment areas (entity rhylib_concealment, placed with the
         toolgun, made permanent with the Permanent tool).
      3. Spawned props with a foliage model (stealthFoliageProps).
    2 and 3 move or come and go, so they sit in a second grid, rebuilt
    (checked every 2 s) only when one came, went or moved, and only while
    some droid is unaware. Changing the foliage words reads the map and
    the spawned props again by itself.

    D.Foliage (F):
      F.Inside(pos) -> radius or nil: pos is inside a foliage item
      F.Between(a, b) -> true: the segment a-b passes within 0.8 x radius
                         of an item (cells along it only, capped)
      F.Counts() -> static, spawned, areas
      F.ParseSprp(reader, dictFn, propFn) -> props, err (pure: reader =
         { seek(p), long(), ushort(), float(), str(n), size() };
         dictFn(i, name) -> radius or false for model i (0-based);
         propFn(x, y, z, radius) for each foliage prop)
      F.ModelRadius(model) -> radius or false (cached)
    Console / chat: rhylib_foliage (!foliage, perm rhylib.droids.alarm):
    counts; "rhylib_foliage reload" reads the map again.
]]

local D = Rhylib.Droids
D.Foliage = D.Foliage or {}
local F = D.Foliage

local CELL = 256
local OFF = 256            -- (cell coords shifted to stay positive)
local floor, sqrt = math.floor, math.sqrt

local function key(cx, cy) return (cx + OFF) * 2048 + (cy + OFF) end

-- One grid: arrays of x, y, z, r by id and cell lists of ids.
local function newGrid() return { x = {}, y = {}, z = {}, r = {}, cells = {}, seen = {}, n = 0 } end

local function add(g, x, y, z, r)
    local id = g.n + 1
    g.n = id
    g.x[id], g.y[id], g.z[id], g.r[id] = x, y, z, r
    g.seen[id] = 0
    for cx = floor((x - r) / CELL), floor((x + r) / CELL) do
        for cy = floor((y - r) / CELL), floor((y + r) / CELL) do
            local k = key(cx, cy)
            local l = g.cells[k]
            if not l then l = {} g.cells[k] = l end
            l[#l + 1] = id
        end
    end
end

F.static = F.static or newGrid()
F.dyn = F.dyn or newGrid()
F.stamp = F.stamp or 0

-- Inside: pos within an item's radius (sideways) and not far above or
-- below its base.
local function insideIn(g, pos)
    local l = g.cells[key(floor(pos.x / CELL), floor(pos.y / CELL))]
    if not l then return nil end
    local X, Y, Z, R = g.x, g.y, g.z, g.r
    for i = 1, #l do
        local id = l[i]
        local dx, dy, dz = pos.x - X[id], pos.y - Y[id], pos.z - Z[id]
        local r = R[id]
        if dx * dx + dy * dy <= r * r and dz > -60 and dz < 200 then return r end
    end
    return nil
end

function F.Inside(pos)
    return insideIn(F.static, pos) or insideIn(F.dyn, pos)
end

-- Distance squared from point (px, py, pz) to the segment a-b.
local function segDist2(ax, ay, az, bx, by, bz, px, py, pz)
    local vx, vy, vz = bx - ax, by - ay, bz - az
    local wx, wy, wz = px - ax, py - ay, pz - az
    local len2 = vx * vx + vy * vy + vz * vz
    local t = len2 > 0 and (wx * vx + wy * vy + wz * vz) / len2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local dx, dy, dz = ax + vx * t - px, ay + vy * t - py, az + vz * t - pz
    return dx * dx + dy * dy + dz * dz
end

local MAX_SAMPLES, MAX_ITEMS = 40, 64

-- Walks the cells along a-b (samples every half cell) and checks each
-- item once (stamp). Items the end point b stands in don't count (that
-- is "inside"), nor ones the start a (the droid) stands in (sideways).
local function betweenIn(g, a, b, stamp)
    local ax, ay, az, bx, by, bz = a.x, a.y, a.z, b.x, b.y, b.z
    local dx, dy = bx - ax, by - ay
    local len = sqrt(dx * dx + dy * dy)
    local steps = math.min(math.ceil(len / (CELL * 0.5)) + 1, MAX_SAMPLES)
    local X, Y, Z, R, seen, cells = g.x, g.y, g.z, g.r, g.seen, g.cells
    local lastK, checked = nil, 0
    for s = 0, steps do
        local f = steps > 0 and s / steps or 0
        local k = key(floor((ax + dx * f) / CELL), floor((ay + dy * f) / CELL))
        if k ~= lastK then
            lastK = k
            local l = cells[k]
            if l then
                for i = 1, #l do
                    local id = l[i]
                    if seen[id] ~= stamp then
                        seen[id] = stamp
                        checked = checked + 1
                        if checked > MAX_ITEMS then return false end
                        local r = R[id]
                        local h = r < 48 and r or 48   -- (the middle of the bush, above its base)
                        local px, py, pz = X[id], Y[id], Z[id] + h
                        local ex, ey = bx - px, by - py
                        local sx, sy = ax - px, ay - py
                        -- (not the one b stands in, nor the one a, the droid, stands in)
                        if ex * ex + ey * ey > r * r and sx * sx + sy * sy > r * r then
                            local lim = r * 0.8
                            if segDist2(ax, ay, az, bx, by, bz, px, py, pz) < lim * lim then return true end
                        end
                    end
                end
            end
        end
    end
    return false
end

function F.Between(a, b)
    F.stamp = F.stamp + 1
    if F.stamp > 1e9 then F.stamp = 1 end
    return betweenIn(F.static, a, b, F.stamp) or betweenIn(F.dyn, a, b, F.stamp)
end

--------------------------------------------------------------------------
-- Which models are foliage
--------------------------------------------------------------------------

local words, skips, wordsFor = {}, {}, nil
local function readWords()
    local list, sk = D.Cfg("stealthFoliage"), D.Cfg("stealthFoliageSkip")
    if wordsFor == list then return end
    wordsFor = list
    words, skips = {}, {}
    for _, s in ipairs(istable(list) and list or {}) do
        local w, r = string.match(tostring(s), "^%s*([^=%s]+)%s*=%s*(%d+%.?%d*)%s*$")
        if w then words[#words + 1] = { string.lower(w), math.Clamp(tonumber(r) or 48, 8, 512) } end
    end
    for _, s in ipairs(istable(sk) and sk or {}) do skips[#skips + 1] = string.lower(tostring(s)) end
end

-- F.MatchName(name) -> radius or false (no cache; the BSP parse calls it
-- once per model of the map's list).
function F.MatchName(name)
    readWords()
    local n = string.lower(tostring(name or ""))
    local file = string.match(n, "([^/\\]+)$") or n
    for _, s in ipairs(skips) do
        if s ~= "" and string.find(file, s, 1, true) then return false end
    end
    for _, w in ipairs(words) do
        if string.find(file, w[1], 1, true) then return w[2] end
    end
    return false
end

F.modelR = F.modelR or {}
function F.ModelRadius(model)
    if not isstring(model) or model == "" then return false end
    local r = F.modelR[model]
    if r == nil then
        r = F.MatchName(model)
        F.modelR[model] = r
    end
    return r
end

-- New foliage words: the map's props are read again and spawned props
-- looked at again (a second after the last change).
Rhylib.Hook.Add("Rhylib.ConfigChanged", "droids.foliage", function(m, k)
    if m == "droids" and (k == "stealthFoliage" or k == "stealthFoliageSkip" or k == "stealthFoliageMap" or k == "stealthFoliageProps") then
        wordsFor = nil
        F.modelR = {}
        timer.Create("Rhylib.Droids.FoliageReload", 1, 1, function()
            if F.LoadMap then F.LoadMap() end
            if F.Rescan then F.Rescan() end
        end)
    end
end)

--------------------------------------------------------------------------
-- The map file's static props (game lump "sprp")
--------------------------------------------------------------------------

local HEADER = 8 + 64 * 16 + 4   -- (ident, version, 64 lumps, map revision)
local GAME_LUMP = 35
-- Prop record sizes by version (only used when the lump size doesn't
-- give a sane one).
local KNOWN = { [4] = 56, [5] = 60, [6] = 64, [7] = 68, [8] = 68, [9] = 72, [10] = 76, [11] = 80, [12] = 80, [13] = 76 }

function F.ParseSprp(r, dictFn, propFn)
    local size = r.size()
    if size < HEADER then return nil, "file too small" end
    r.seek(0)
    if r.str(4) ~= "VBSP" then return nil, "not a VBSP map" end
    local bspVer = r.long()
    -- The game lump's entry: { offset, length, version, fourCC }; maps
    -- saved in the L4D2 layout (version 21) store { version, offset, length }.
    r.seek(8 + GAME_LUMP * 16)
    local a, b, c = r.long(), r.long(), r.long()
    local lofs, llen = a, b
    if not (lofs >= HEADER and llen > 4 and lofs + llen <= size) then lofs, llen = b, c end
    if not (lofs >= HEADER and llen > 4 and lofs + llen <= size) then return nil, "no game lump (map version " .. tostring(bspVer) .. ")" end
    r.seek(lofs)
    local count = r.long()
    if count < 0 or count > 256 or 4 + count * 16 > llen then return nil, "bad game lump directory" end
    local sofs, slen, sver, sflags
    for i = 1, count do
        r.seek(lofs + 4 + (i - 1) * 16)
        local id = r.str(4)
        local flags, ver = r.ushort(), r.ushort()
        local fofs, flen = r.long(), r.long()
        if id == "prps" or id == "sprp" then
            sofs, slen, sver, sflags = fofs, flen, ver, flags
            break
        end
    end
    if not sofs then return 0, nil end   -- (no static props at all)
    if sflags % 2 == 1 then return nil, "static props are compressed (version " .. sver .. ")" end
    -- (offsets are from the file start; a few tools wrote them from the lump)
    if not (sofs >= HEADER and slen >= 12 and sofs + slen <= size) and lofs + sofs + slen <= size then sofs = lofs + sofs end
    if not (sofs >= HEADER and slen >= 12 and sofs + slen <= size) then return nil, "bad static prop lump" end
    local stop = sofs + slen
    r.seek(sofs)
    local nDict = r.long()
    if nDict < 0 or 4 + nDict * 128 > slen then return nil, "bad model list" end
    local rad = {}
    local any = false
    for i = 0, nDict - 1 do
        r.seek(sofs + 4 + i * 128)
        local raw = r.str(128)
        local z = string.find(raw, "\0", 1, true)
        local rr = dictFn(i, z and string.sub(raw, 1, z - 1) or raw)
        rad[i] = rr
        if rr then any = true end
    end
    local p = sofs + 4 + nDict * 128
    r.seek(p)
    local nLeaf = r.long()
    if nLeaf < 0 or p + 4 + nLeaf * 2 > stop then return nil, "bad leaf list" end
    p = p + 4 + nLeaf * 2
    r.seek(p)
    local nProps = r.long()
    p = p + 4
    if nProps <= 0 then return 0, nil end
    if not any then return 0, nil end   -- (no foliage models: nothing to read)
    local rec = floor((stop - p) / nProps)
    if rec < 56 or rec > 256 then rec = KNOWN[sver] end
    if not rec or p + rec * nProps > stop then return nil, "bad prop records (version " .. tostring(sver) .. ")" end
    local found = 0
    for i = 0, nProps - 1 do
        local at = p + i * rec
        r.seek(at + 24)   -- (origin 12 bytes, angles 12, then the model index)
        local m = r.ushort()
        local rr = rad[m]
        if rr then
            r.seek(at)
            local x, y, zz = r.float(), r.float(), r.float()
            if x == x and y == y and zz == zz and math.abs(x) < 65536 and math.abs(y) < 65536 and math.abs(zz) < 65536 then
                propFn(x, y, zz, rr)
                found = found + 1
            end
        end
    end
    return found, nil
end

-- A reader over a GMod File.
local function fileReader(f)
    return {
        seek = function(p) f:Seek(p) end,
        long = function() return f:ReadLong() or 0 end,
        ushort = function()
            local v = f:ReadShort() or 0
            if v < 0 then v = v + 65536 end
            return v
        end,
        float = function() return f:ReadFloat() or 0 end,
        str = function(n) return f:Read(n) or "" end,
        size = function() return f:Size() end,
    }
end

-- Reads the map's foliage props into the static grid (replacing it).
function F.LoadMap()
    local g = newGrid()
    F.static = g
    F.mapCount = 0
    if not D.Cfg("stealthFoliageMap") then return 0 end
    local path = "maps/" .. game.GetMap() .. ".bsp"
    local f = file.Open(path, "rb", "GAME")
    if not f then
        Rhylib.Warn("droids", "Foliage: couldn't open %s (no map foliage for stealth)", path)
        return 0
    end
    local ok, n, err = pcall(F.ParseSprp, fileReader(f), function(_, name) return F.MatchName(name) end,
        function(x, y, z, r) add(g, x, y, z, r) end)
    f:Close()
    if not ok then
        Rhylib.Warn("droids", "Foliage: reading %s failed: %s", path, tostring(n))
        F.static = newGrid()
        return 0
    end
    if not n then
        Rhylib.Warn("droids", "Foliage: %s: %s (no map foliage for stealth)", path, tostring(err))
        return 0
    end
    F.mapCount = n
    Rhylib.Print("droids", "Foliage: %d foliage props on %s", n, game.GetMap())
    return n
end

--------------------------------------------------------------------------
-- Concealment areas and spawned foliage props (the second grid)
--------------------------------------------------------------------------

D.conceal = D.conceal or {}       -- [rhylib_concealment] = true
F.props = F.props or {}           -- [prop] = radius

local PROP_CLASSES = { prop_physics = true, prop_physics_multiplayer = true, prop_dynamic = true, prop_dynamic_override = true }

local function rebuild()
    local g = newGrid()
    local nP, nA = 0, 0
    for e, r in pairs(F.props) do
        if IsValid(e) then
            local p = e:GetPos()
            e.rhylibFolX, e.rhylibFolY, e.rhylibFolZ = p.x, p.y, p.z   -- (where it was put in the grid)
            add(g, p.x, p.y, p.z, r)
            nP = nP + 1
        else
            F.props[e] = nil
        end
    end
    for e in pairs(D.conceal) do
        if IsValid(e) then
            local p = e:GetPos()
            e.rhylibFolX, e.rhylibFolY, e.rhylibFolZ = p.x, p.y, p.z
            add(g, p.x, p.y, p.z, math.max(e.GetRadius and e:GetRadius() or 0, 16))
            nA = nA + 1
        else
            D.conceal[e] = nil
        end
    end
    F.dyn = g
    F.propCount, F.areaCount = nP, nA
    F.dirty = false
end
F.Rebuild = rebuild

-- Moved since the last build (more than 16 units)?
local function moved(set)
    for e in pairs(set) do
        if not IsValid(e) then return true end
        local p = e:GetPos()
        local dx, dy, dz = p.x - (e.rhylibFolX or 1e9), p.y - (e.rhylibFolY or 1e9), p.z - (e.rhylibFolZ or 1e9)
        if dx * dx + dy * dy + dz * dz > 256 then return true end
    end
    return false
end

-- Rebuilt (checked every 2 s) only when something came, went or moved,
-- and only while some droid is unaware (nothing reads it otherwise).
timer.Create("Rhylib.Droids.Foliage", 2, 0, function()
    if not (D.stealthy and next(D.stealthy)) then return end
    if F.dirty or moved(F.props) or moved(D.conceal) then rebuild() end
end)

Rhylib.Hook.Add("OnEntityCreated", "droids.foliage", function(e)
    if not (IsValid(e) and PROP_CLASSES[e:GetClass()]) then return end
    -- (the model is set after creation)
    timer.Simple(0, function()
        if not (IsValid(e) and D.Cfg("stealthFoliageProps")) then return end
        local r = F.ModelRadius(e:GetModel())
        if r then
            F.props[e] = r
            F.dirty = true
        end
    end)
end)

Rhylib.Hook.Add("EntityRemoved", "droids.foliage", function(e)
    if F.props[e] then F.props[e] = nil F.dirty = true end
    if D.conceal[e] then D.conceal[e] = nil F.dirty = true end
end)

-- F.Rescan(): every spawned prop looked at again (new foliage words).
function F.Rescan()
    for e in pairs(F.props) do F.props[e] = nil end
    if D.Cfg("stealthFoliageProps") then
        for cls in pairs(PROP_CLASSES) do
            for _, e in ipairs(ents.FindByClass(cls)) do
                local r = F.ModelRadius(e:GetModel())
                if r then F.props[e] = r end
            end
        end
    end
    rebuild()
end

function F.Counts()
    return F.mapCount or 0, F.propCount or 0, F.areaCount or 0
end

Rhylib.Hook.Add("InitPostEntity", "droids.foliage", function()
    timer.Simple(2, function() F.LoadMap() end)
end)
-- (a Lua refresh after map start: read it again if it never was)
if F.mapCount == nil and CurTime() > 10 then timer.Simple(1, function() F.LoadMap() end) end

Rhylib.Command.Add({
    name = "rhylib_foliage", chat = { "foliage" }, perm = "rhylib.droids.alarm", minAccess = "admin", tag = "Droids",
    help = "Stealth foliage: how many map props, spawned props and concealment areas count (reload: read the map again)", args = "[reload]",
    fn = function(ply, args)
        if args[1] == "reload" then F.LoadMap() rebuild() end
        local a, b, c = F.Counts()
        return string.format("Foliage: %d map props, %d spawned props, %d concealment areas", a, b, c)
    end,
})

-- Concealment areas stay where they're made permanent (the Permanent tool).
if Rhylib.Perma and Rhylib.Perma.Placements then
    F.places = Rhylib.Perma.Placements("droids_conceal", {
        classes = { "rhylib_concealment" },
        dataModule = "droids_conceal",
        save = function(e) return { r = e:GetRadius() } end,
        preSpawn = function(e, row) e.ConcealRadius = tonumber(row.r) end,
        freeze = false,
    })
end
