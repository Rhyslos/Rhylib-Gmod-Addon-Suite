--[[
    Datapad: notes, battalion computers, the battalion board and unit
    admin, quick response calls and MP tools. (Shared: loads first.)

      Datapad      hold the datapad SWEP (config "class", sw_datapad) and
                   left click to open it. Anyone writes notes (logs);
                   medics also write medical records about a patient.
                   Notes stay on the pad until uploaded. Troopers hold
                   noteLimit notes; MPs and medics have no limit.
                   Sync downloads the battalion computer (board, orders,
                   logs, LOA, stats, own file, mission) to the pad.
      Battalion    a computer per battalion (battalion = DarkRP job
      computer     category; an admin sets it on the computer). Upload
                   your logs there and read the battalion's logs, board,
                   orders, missions, leave, personnel files, stats and
                   applications. Commanders (job commander = true) and
                   admins delete logs and ban people from uploading.
      Medical      medics upload medical records here and read them all.
      holotable    Medic commanders and admins moderate it.
      MP tools     on the datapad: look up anyone's arrest record and logs,
                   read logs written by MPs, search and jail cuffed
                   prisoners nearby (no terminal needed).
      Calls        Quick response tab: call MPs, a medic, the bomb squad,
                   reinforcements or resupply (config "calls").

    This file: config keys, models, shared helpers (D.Battalion, D.IsMP,
    D.Limit, D.Clip...), the datapad's inventory size and the computers'
    floating label. Server files: sv_10 pad + MP tools, sv_20 computers,
    sv_30 search + board, sv_40 stats, sv_50 sync, sv_60 orders/leave/
    applications/sessions, sv_70 personnel, sv_80 calls, sv_90 missions.
    Client files: cl_10 datapad window, cl_20 computer window, cl_30 calls.

    Data: "dp_pad"/sid (notes on the pad), "dp_log"/battalion and
    "dp_log"/"__medical" ({ next, list }), "dp_ban"/same keys,
    "dp_places"/map (computer placements). The other modules are listed
    in the file that owns them.
]]

Rhylib.Datapad = Rhylib.Datapad or {}
local D = Rhylib.Datapad
local Config = Rhylib.Config

-- (class: the inventory size is given to that SWEP at Initialize, so a new
-- class needs a map change. logCap/medCap: the computer sends at most 255
-- entries. arrestRange is also the datapad's search reach for rhylib_mp.)
Config.Register("datapad", "class", "sw_datapad", "Datapad weapon class (left click with it out opens the datapad)")
Config.Register("datapad", "noteLimit", 5, "Notes a trooper's datapad holds before they must upload (MPs and medics: no limit)")
Config.Register("datapad", "titleMax", 48, "Longest note title (characters)")
Config.Register("datapad", "bodyMax", 1500, "Longest note text (characters)")
Config.Register("datapad", "logCap", 250, "Logs kept per battalion computer, max 255 (oldest are dropped)")
Config.Register("datapad", "medCap", 250, "Medical records kept on the medical holotable, max 255")
Config.Register("datapad", "arrestRange", 250, "MPs can jail cuffed players this close with the datapad")
Config.Register("datapad", "useRange", 160, "How close you must stay to a computer to use it")
Config.Register("datapad", "strikeDays", 30, "Days a strike stays active")

-- Quick response calls (datapad). to: "mp", "medic", "battalion" (the
-- caller's), "eod" (bomb squad: hook Rhylib.IsBombSquad, or a job with
-- eod = true), "all". accept = true: they see where you are only after
-- answering. items = true: pick from supplyItems. At most 7 kinds.
-- A call's kind on the wire is its place in this list (3 bits), so keep
-- the order the same on server and clients. short: card/chat name;
-- inbound: "<inbound> inbound: names" for the caller; id picks the card
-- colour (mp, medic, reinf, supply, eod; others use the menu accent).
Config.Register("datapad", "calls", {
    { id = "mp", name = "Call military police", short = "MP", to = "mp", accept = false, inbound = "MP" },
    { id = "medic", name = "Call a medic", short = "Medic", to = "medic", accept = false, inbound = "Medic" },
    { id = "reinf", name = "Request reinforcements", short = "Reinforcements", to = "all", accept = true, inbound = "Reinforcements" },
    { id = "supply", name = "Request resupply", short = "Resupply", to = "all", accept = true, inbound = "Resupply", items = true },
    { id = "eod", name = "Call the bomb squad", short = "Bomb squad", to = "eod", accept = false, inbound = "Bomb squad" },
}, "Quick response calls: { id, name, short, to = mp|medic|battalion|eod|all, accept, inbound, items }")
Config.Register("datapad", "supplyItems", {
    "Medical crate", "Light ammo", "Medium ammo", "Heavy ammo", "Rockets", "Grenades", "Power cells",
}, "What a resupply request can ask for (at most 16)")
Config.Register("datapad", "callLife", 300, "Seconds a call stays open")
Config.Register("datapad", "callCooldown", 20, "Seconds between two calls of the same kind from one player")
Config.Register("datapad", "strikeWarn", 3, "Active strikes at which the battalion's officers are told")

-- Models of the two terminals (ENT.ModelKey picks one). Hosts swap them in
-- Server settings > Models (core sh_25_models writes the setting back here).
D.MODELS = {
    battalion = "models/ace/sw/rh/cgi_holotable_bottom.mdl",
    medical = "models/reizer_props/srsp/sci_fi/command_table_02/command_table_02.mdl",
}
-- Server settings > Models.
Rhylib.Hook.Add("Rhylib.ModelCatalogue", "datapad.models", function(add)
    add("datapad.battalion", "Battalion computer", "Terminals", function() return D.MODELS end, "battalion")
    add("datapad.medical", "Medical holotable", "Terminals", function() return D.MODELS end, "medical")
end)
D.MED_KEY = "__medical"   -- the medical holotable's key in Data
D.KIND_LOG, D.KIND_MED = 0, 1   -- note kinds (1 bit on the wire): log -> battalion computer, medical record -> holotable
D.HARD_CAP = 100          -- notes on any pad, even "no limit" ones (keeps messages small)

-- D.Cfg(key): a datapad config value (override > host file > default).
-- Example: Rhylib.Datapad.Cfg("noteLimit")   -- 5
function D.Cfg(k) return Config.Get("datapad", k) end

local function job(ply)
    return RPExtraTeams and RPExtraTeams[ply:Team()]
end

-- D.Battalion(ply): the player's battalion = their DarkRP job category,
-- or "" (no DarkRP / no category). Every computer, book and stat is keyed by it.
-- Example: if Rhylib.Datapad.Battalion(ply) == "212th" then ... end
function D.Battalion(ply)
    local j = job(ply)
    return j and j.category or ""
end

-- D.IsMP(ply): true if rhylib_mp says they are an MP (false without rhylib_mp).
function D.IsMP(ply) return Rhylib.MP and Rhylib.MP.IsMP and Rhylib.MP.IsMP(ply) or false end
-- D.IsBombSquad(ply): who the "eod" quick response call reaches.
-- Asks hook Rhylib.IsBombSquad(ply) first (rhylib_eod answers: Field
-- technician skill or an EOD kit; true/false wins, nil falls through),
-- else a DarkRP job with eod = true. (rhylib_eod adds its hook server side only.)
function D.IsBombSquad(ply)
    local r = hook.Run("Rhylib.IsBombSquad", ply)
    if r ~= nil then return r end
    local j = RPExtraTeams and RPExtraTeams[ply:Team()]
    return j and j.eod == true or false
end
-- D.IsMedic(ply): true if rhylib_medical says they are a medic (false without it).
function D.IsMedic(ply) return Rhylib.Medical and Rhylib.Medical.IsMedic and Rhylib.Medical.IsMedic(ply) or false end

-- D.IsCommander(ply): may moderate their own battalion's computer (and post
-- on its board without rhylib_roster). Hook Rhylib.IsCommander(ply) wins if
-- it returns true/false, else the DarkRP job's commander = true.
function D.IsCommander(ply)
    local r = hook.Run("Rhylib.IsCommander", ply)
    if r ~= nil then return r end
    local j = job(ply)
    return j and j.commander == true or false
end

-- D.Holding(ply): is the datapad weapon (config "class") in their hands?
-- Every dp.* datapad message checks this on the server.
function D.Holding(ply)
    local w = ply:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == D.Cfg("class")
end

-- D.Limit(ply): notes the pad holds, or 0 for no limit (MPs, medics).
-- "No limit" still stops at D.HARD_CAP.
function D.Limit(ply)
    if D.IsMP(ply) or D.IsMedic(ply) then return 0 end
    return math.Clamp(math.floor(D.Cfg("noteLimit")), 1, D.HARD_CAP)
end

-- D.Clip(s, n, keepLines): clip to n characters (whole UTF-8 characters),
-- drop control characters except new lines (keepLines), trim spaces.
-- Used on every text a client sends. Returns the clean string.
-- Example: D.Clip(net.ReadString(), D.Cfg("titleMax"))
function D.Clip(s, n, keepLines)
    s = tostring(s or "")
    s = string.gsub(s, "%c", function(c) return (keepLines and c == "\n") and c or "" end)
    s = string.Trim(s)
    local len = utf8.len(s)
    if not len then
        s = string.sub(s, 1, n)  -- not valid UTF-8: cut by bytes
    elseif len > n then
        s = string.sub(s, 1, utf8.offset(s, n + 1) - 1)
    end
    return s
end

-- The datapad SWEP becomes an inventory item (so armouries can stock it):
-- 1x1, 0.3 kg, category gear. Skipped if the SWEP already sets InvW.
Rhylib.Hook.Add("Initialize", "datapad.item", function()
    local s = weapons.GetStored(D.Cfg("class"))
    if s and not s.InvW then
        s.InvW, s.InvH, s.InvWeight, s.InvCategory = 1, 1, 0.3, "gear"
    end
end)

-- Shared look for the computers' floating label.
-- D.DrawLabel(ent, title, sub) (client): a plate over the entity, facing the
-- player, drawn only within 250 units. Called from the entities' Draw.
if CLIENT then
    local COL_TITLE = Color(228, 227, 220)
    local COL_SUB = Color(169, 168, 160)
    local COL_BG = Color(20, 22, 20, 190)
    function D.DrawLabel(ent, title, sub)
        local ply = LocalPlayer()
        if ply:GetPos():DistToSqr(ent:GetPos()) > 250 * 250 then return end
        local pos = ent:LocalToWorld(Vector(0, 0, ent:OBBMaxs().z + 12))
        local ang = Angle(0, ply:EyeAngles().y - 90, 90)
        local UI = Rhylib.UI
        cam.Start3D2D(pos, ang, 0.08)
            surface.SetFont(UI.Font(30))
            local w = math.max(surface.GetTextSize(title), (surface.GetTextSize(sub))) + 40
            draw.RoundedBox(8, -w * 0.5, -34, w, 74, COL_BG)
            draw.SimpleText(title, UI.Font(30), 0, -16, COL_TITLE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(sub, UI.Font(22), 0, 18, COL_SUB, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        cam.End3D2D()
    end
end
