--[[
    rhylib_gear_scan (admin, or the server console): every DarkRP job
    model's bodygroups (name, options and their names), then which models
    have each bodygroup name. Printed to your console and saved to
    data/rhylib_gear_scan.txt on the server.
]]

local G = Rhylib.Gear

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

-- A model's bodygroups, read from a short-lived entity.
local function groupsOf(model)
    if not util.IsValidModel(model) then return nil end
    local e = ents.Create("prop_dynamic")
    if not IsValid(e) then return nil end
    e:SetModel(model)
    e:Spawn()
    local list = {}
    for _, g in ipairs(e:GetBodyGroups() or {}) do
        local subs = {}
        for i = 0, (g.num or 1) - 1 do subs[#subs + 1] = (g.submodels and g.submodels[i]) or ("#" .. i) end
        list[#list + 1] = { id = g.id, name = g.name, subs = subs }
    end
    e:Remove()
    return list
end

function G.Scan()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local models, order = jobModels()
    local byGroup, groupOrder = {}, {}
    add("Rhylib bodygroup scan, " .. os.date("%Y-%m-%d %H:%M") .. ", " .. #order .. " job models")
    add("")
    for _, m in ipairs(order) do
        add(m)
        add("  jobs: " .. table.concat(models[m], ", "))
        local groups = groupsOf(m)
        if not groups then
            add("  (model missing on the server)")
        else
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
        end
        add("")
    end
    table.sort(groupOrder)
    add("Bodygroup names (how many models have each):")
    for _, k in ipairs(groupOrder) do
        add(string.format("  %s: %d of %d", k, #byGroup[k], #order))
    end
    file.Write("rhylib_gear_scan.txt", table.concat(lines, "\n"))
    return lines
end

concommand.Add("rhylib_gear_scan", function(ply)
    local function run()
        local lines = G.Scan()
        for _, l in ipairs(lines) do
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, l) else print(l) end
        end
        local msg = "Bodygroup scan done (" .. #lines .. " lines): see the console, or data/rhylib_gear_scan.txt on the server."
        if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
    end
    if not IsValid(ply) then return run() end
    Rhylib.Perms.Check(ply, "rhylib.gear.admin", function(ok) if ok then run() end end)
end)
