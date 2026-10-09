--[[
    Datapad: notes, battalion logs, medical records and MP tools.

      Datapad      hold the datapad SWEP (config "class", sw_datapad) and
                   left click to open it. Anyone writes notes (logs);
                   medics also write medical records about a patient.
                   Notes stay on the pad until uploaded. Troopers hold
                   noteLimit notes; MPs and medics have no limit.
      Battalion    a computer per battalion (battalion = DarkRP job
      computer     category; an admin sets it on the computer). Upload
                   your logs there and read the battalion's logs.
                   Commanders (job commander = true) and admins delete
                   logs and ban people from uploading.
      Medical      medics upload medical records here and read them all.
      holotable    Medic commanders and admins moderate it.
      MP tools     on the datapad: look up anyone's arrest record and logs,
                   read logs written by MPs, search and jail cuffed
                   prisoners nearby (no terminal needed).

    Data: "dp_pad"/sid (notes on the pad), "dp_log"/battalion and
    "dp_log"/"__medical" ({ next, list }), "dp_ban"/same keys,
    "dp_places"/map (computer placements).
]]

Rhylib.Datapad = Rhylib.Datapad or {}
local D = Rhylib.Datapad
local Config = Rhylib.Config

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
D.KIND_LOG, D.KIND_MED = 0, 1
D.HARD_CAP = 100          -- notes on any pad, even "no limit" ones (keeps messages small)

function D.Cfg(k) return Config.Get("datapad", k) end

local function job(ply)
    return RPExtraTeams and RPExtraTeams[ply:Team()]
end

-- Battalion = the DarkRP job category.
function D.Battalion(ply)
    local j = job(ply)
    return j and j.category or ""
end

function D.IsMP(ply) return Rhylib.MP and Rhylib.MP.IsMP and Rhylib.MP.IsMP(ply) or false end
-- Bomb squad: rhylib_eod answers (Field technician skill or an EOD kit), else a job with eod = true.
function D.IsBombSquad(ply)
    local r = hook.Run("Rhylib.IsBombSquad", ply)
    if r ~= nil then return r end
    local j = RPExtraTeams and RPExtraTeams[ply:Team()]
    return j and j.eod == true or false
end
function D.IsMedic(ply) return Rhylib.Medical and Rhylib.Medical.IsMedic and Rhylib.Medical.IsMedic(ply) or false end

function D.IsCommander(ply)
    local r = hook.Run("Rhylib.IsCommander", ply)
    if r ~= nil then return r end
    local j = job(ply)
    return j and j.commander == true or false
end

function D.Holding(ply)
    local w = ply:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == D.Cfg("class")
end

-- Notes the pad holds, or 0 for no limit.
function D.Limit(ply)
    if D.IsMP(ply) or D.IsMedic(ply) then return 0 end
    return math.Clamp(math.floor(D.Cfg("noteLimit")), 1, D.HARD_CAP)
end

-- Clip to n characters (whole UTF-8 characters), drop control characters
-- except new lines (keepLines).
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

-- The datapad SWEP becomes an inventory item (so armouries can stock it).
Rhylib.Hook.Add("Initialize", "datapad.item", function()
    local s = weapons.GetStored(D.Cfg("class"))
    if s and not s.InvW then
        s.InvW, s.InvH, s.InvWeight, s.InvCategory = 1, 1, 0.3, "gear"
    end
end)

-- Shared look for the computers' floating label.
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
