--[[
    Per-map placements (server): the one saver every addon's fixtures use
    (armouries, med bay, jail cells, computers, spawn points, beacons,
    jammers, bounty offices...). Only permanent things are saved
    (Rhylib.Perma.Is: the toolgun's Permanent entry).

        local PL = Rhylib.Perma.Placements("mp", {
            classes = { "rhylib_jail_cell", "rhylib_jail_terminal" },
            dataModule = "mp_places",          -- default "<module>_places"
            save = function(e) return { bn = e:GetBattalion() } end,  -- extra fields (optional)
            preSpawn = function(e, row) e.MarkerKind = row.kind end,   -- before Spawn (optional)
            load = function(e, row) e:SetBattalion(row.bn or "") end, -- after Spawn (optional)
            command = "rhylib_mp_save",        -- optional console command
            perm = "rhylib.mp.admin",          -- who may run it (console always)
            freeze = true,                     -- default true: physics frozen
        })
        PL:Save()  -> saved, notPermanent      PL:Load()  -> spawned

    Rows: Data <dataModule>/<map> = list of
        { class, pos = { x, y, z }, ang = { p, y, r }, <extra fields> }
    The extra fields from save(e) sit in the row itself, which is the shape
    the addons' own savers already wrote (armoury: owner, ownerName,
    locked; datapad: bn; radio: on), so their saved data loads unchanged.
    Older shapes are read too: `yaw` instead of `ang` (spawns, training),
    no `class` (training beacons: opts.defaultClass). opts.readRow(row) ->
    class, pos (Vector), ang (Angle), or nil to skip, handles anything else.
    load(e, row) gets the whole row.

    Loading: 1 s after InitPostEntity and after every map cleanup. It
    removes the copies it loaded before (and anything permanent of those
    classes) first, spawns each row (each under pcall), marks it permanent
    (Perma.Mark), sets e.rhylibPlacement and freezes it. Nothing saved for
    the map = the map is left alone. Registered with Rhylib.Perma.Register,
    so the Permanent tool and "Re-save permanent things" call PL:Save().
    opts.filter(e) -> false skips an entity when saving. opts.onLoaded(list)
    runs after a load with the spawned entities.
    The command prints "Saved N ... (M placed but not permanent: ...)".
]]

local P = Rhylib.Perma
local Data = Rhylib.Data

local Placements = {}
Placements.__index = Placements
P.placements = P.placements or {}   -- [module] = placement object

local function v3(t) return Vector(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end

-- The default row reader: { class, pos, ang } or { pos, yaw } shapes.
local function readRow(self, row)
    if not istable(row) or not istable(row.pos) then return nil end
    local class = isstring(row.class) and row.class or self.opts.defaultClass
    if not class or not self.isClass[class] then return nil end
    local ang
    if istable(row.ang) then ang = Angle(tonumber(row.ang[1]) or 0, tonumber(row.ang[2]) or 0, tonumber(row.ang[3]) or 0)
    else ang = Angle(0, tonumber(row.yaw) or 0, 0) end
    return class, v3(row.pos), ang
end

-- PL:Save() -> saved, notPermanent. Writes the permanent ones of the classes.
function Placements:Save()
    local rows, skipped = {}, 0
    for _, class in ipairs(self.opts.classes) do
        for _, e in ipairs(ents.FindByClass(class)) do
            if not (self.opts.filter and self.opts.filter(e) == false) then
                if P.Is(e) then
                    local p, a = e:GetPos(), e:GetAngles()
                    local row = { class = class, pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r } }
                    if self.opts.save then
                        local ok, extra = pcall(self.opts.save, e)
                        if ok and istable(extra) then
                            for k, v in pairs(extra) do
                                if row[k] == nil then row[k] = v end
                            end
                        elseif not ok then
                            Rhylib.Warn("core", "%s placement save: %s", self.module, tostring(extra))
                        end
                    end
                    rows[#rows + 1] = row
                else
                    skipped = skipped + 1
                end
            end
        end
    end
    Data.Set(self.dataModule, game.GetMap(), rows)
    return #rows, skipped
end

-- PL:Load() -> number spawned (see the top).
function Placements:Load()
    local rows = Data.Get(self.dataModule, game.GetMap())
    if not istable(rows) then return 0 end
    for _, class in ipairs(self.opts.classes) do
        for _, e in ipairs(ents.FindByClass(class)) do
            if e.rhylibPlacement or P.Is(e) then e:Remove() end
        end
    end
    local list = {}
    for _, row in ipairs(rows) do
        local ok, err = pcall(function()
            local class, pos, ang
            if self.opts.readRow then class, pos, ang = self.opts.readRow(row)
            else class, pos, ang = readRow(self, row) end
            if not class then return end
            local e = ents.Create(class)
            if not IsValid(e) then return end
            e:SetPos(pos)
            e:SetAngles(ang)
            if self.opts.preSpawn then self.opts.preSpawn(e, row) end
            e:Spawn()
            e:Activate()
            if self.opts.load then self.opts.load(e, row) end
            e.rhylibPlacement = true
            P.Mark(e, true)
            if self.opts.freeze ~= false and P.FreezeAll then P.FreezeAll(e) end
            list[#list + 1] = e
        end)
        if not ok then Rhylib.Warn("core", "%s placement didn't load: %s", self.module, tostring(err)) end
    end
    if self.opts.onLoaded then pcall(self.opts.onLoaded, list) end
    if #list > 0 then Rhylib.Print("core", "Placed %d %s things on %s", #list, self.module, game.GetMap()) end
    return #list
end

-- Rhylib.Perma.Placements(module, opts) -> placement object (see the top).
-- Calling again with the same module replaces the options (refresh-safe).
function P.Placements(module, opts)
    assert(istable(opts) and istable(opts.classes), "Perma.Placements needs opts.classes")
    local self = P.placements[module] or setmetatable({}, Placements)
    self.module = module
    self.opts = opts
    self.dataModule = opts.dataModule or (module .. "_places")
    self.isClass = {}
    for _, c in ipairs(opts.classes) do self.isClass[c] = true end
    P.placements[module] = self

    P.Register(opts.classes, function() return (self:Save()) end)

    local id = "core.placements." .. module
    Rhylib.Hook.Add("InitPostEntity", id, function() timer.Simple(1, function() self:Load() end) end)
    Rhylib.Hook.Add("PostCleanupMap", id, function() self:Load() end)

    if opts.command then
        concommand.Add(opts.command, function(ply)
            local function run()
                local n, skipped = self:Save()
                local msg = "Saved " .. n .. " " .. module .. " placements for " .. game.GetMap()
                    .. (skipped > 0 and (" (" .. skipped .. " placed but not permanent: make them permanent with the toolgun's Permanent tool)") or "")
                if Rhylib.Notify then Rhylib.Notify(IsValid(ply) and ply or nil, msg, "good") else print(msg) end
            end
            if not IsValid(ply) or not opts.perm then return run() end
            Rhylib.Perms.Check(ply, opts.perm, function(ok)
                if not IsValid(ply) then return end
                if ok then run() elseif Rhylib.Notify then Rhylib.Notify(ply, "You don't have permission for " .. opts.command, "bad") end
            end)
        end)
    end
    return self
end
