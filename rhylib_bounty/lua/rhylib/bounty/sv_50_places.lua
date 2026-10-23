--[[
    Saving Bounty Offices and wanted posters per map (server). Only the
    ones made permanent with the toolgun's Permanent tool are kept
    (rhylib_core Rhylib.Perma); they come back at map start and after a
    cleanup. Data "bounty_places"/<map> = list of { class, pos, ang }.
]]

local B = Rhylib.Bounty
local Data = Rhylib.Data

B.PLACE_CLASSES = { "rhylib_bounty_office", "rhylib_bounty_poster" }

-- B.SavePlaces(): returns how many were saved.
function B.SavePlaces()
    local rows = {}
    for _, class in ipairs(B.PLACE_CLASSES) do
        for _, e in ipairs(ents.FindByClass(class)) do
            if not Rhylib.Perma or Rhylib.Perma.Is(e) then
                local p, a = e:GetPos(), e:GetAngles()
                rows[#rows + 1] = { class = class, pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r } }
            end
        end
    end
    Data.Set("bounty_places", game.GetMap(), rows)
    return #rows
end

function B.LoadPlaces()
    for _, class in ipairs(B.PLACE_CLASSES) do
        for _, e in ipairs(ents.FindByClass(class)) do e:Remove() end
    end
    local rows = Data.Get("bounty_places", game.GetMap())
    for _, row in ipairs(istable(rows) and rows or {}) do
        if table.HasValue(B.PLACE_CLASSES, row.class) and istable(row.pos) then
            local e = ents.Create(row.class)
            if IsValid(e) then
                e:SetPos(Vector(row.pos[1], row.pos[2], row.pos[3]))
                local a = istable(row.ang) and row.ang or { 0, 0, 0 }
                e:SetAngles(Angle(a[1], a[2], a[3]))
                e:Spawn()
                if Rhylib.Perma then Rhylib.Perma.Mark(e, true) end
            end
        end
    end
end

if Rhylib.Perma and Rhylib.Perma.Register then Rhylib.Perma.Register(B.PLACE_CLASSES, B.SavePlaces) end
Rhylib.Hook.Add("InitPostEntity", "bounty.places", function() timer.Simple(1, B.LoadPlaces) end)
Rhylib.Hook.Add("PostCleanupMap", "bounty.places", B.LoadPlaces)
