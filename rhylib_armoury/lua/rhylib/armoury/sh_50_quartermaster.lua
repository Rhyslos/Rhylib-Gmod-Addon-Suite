--[[
    Quartermaster (shared: settings, constants, the name clip).

    An NPC-looking clone staff place (toolgun Base, or the spawn menu
    "Rhy's Armoury & storage"; entities/rhylib_quartermaster.lua). Walk up,
    press E: a window (cl_50_quartermaster.lua) with what you carry now and
    three loadout slots per player. "Save current kit here" stores what you
    carry (item, container, x, y, turn, count, hotbar key; worn gear and the
    backpack with its contents too); "Apply this loadout" hands your whole
    kit back to the armoury stock and issues the saved one from it, fresh
    and full, in one go (sv_50_quartermaster.lua does all of it; the client
    only asks).

    What he takes in: only what the armoury depots on this server issue
    (weapons armoury, ammo cabinet, gear cabinet, specialist racks; never
    training items), and only items without data of their own (A.QM.STD_DATA
    lists the standard data keys; anything else, e.g. a blood sample's note,
    is the item's own data). Carrying anything else blocks applying (saving
    still works and leaves those out). Job gear (data.loadout) stays where it
    is, is never saved and never blocks.

    Applying takes qmIssueTime seconds at the counter (a handout the
    player can stop; walking away, going down or being cuffed stops it).
    With qmEditor on, a loadout can also be built in the editor from the
    whole armoury list (cl_55_quartermaster_editor.lua) and saved; the server
    checks every row.

    Settings (module "armoury", section "Quartermaster"): qmCooldown,
    qmRange, qmModel, qmNameMax, qmIssueTime, qmEditor.
]]

local A = Rhylib.Armoury
A.QM = A.QM or {}
local Q = A.QM
local Config = Rhylib.Config

local S = { section = "Quartermaster" }
Config.Register("armoury", "qmCooldown", 15, "Quartermaster: seconds between two loadout swaps for one player", S)
Config.Meta("armoury", "qmCooldown", { min = 0, max = 255, step = 1, unit = "s" })
Config.Register("armoury", "qmRange", 160, "Quartermaster: how close you must stand to use him (units)", S)
Config.Meta("armoury", "qmRange", { min = 60, max = 400, step = 10, unit = "units" })
Config.Register("armoury", "qmModel", "models/ct_trp/pm_ct_trp.mdl", "Quartermaster NPC: model (a clone model with player animations)", S)
Config.Register("armoury", "qmNameMax", 24, "Quartermaster: longest loadout name (letters)", S)
Config.Meta("armoury", "qmNameMax", { min = 4, max = 40, step = 1 })
Config.Register("armoury", "qmIssueTime", 6, "Quartermaster: seconds a loadout takes to hand out at the counter (0 = at once)", S)
Config.Meta("armoury", "qmIssueTime", { min = 0, max = 30, step = 1, unit = "s" })
Config.Register("armoury", "qmEditor", false, "Lets players build loadouts from the full armoury list without collecting the items first",
    { section = "Quartermaster", name = "Loadout editor at the quartermaster" })

-- (the Server settings page lists the armoury sections in this order)
local d = Config.modules and Config.modules.armoury
if d and istable(d.order) and not table.HasValue(d.order, "Quartermaster") then d.order[#d.order + 1] = "Quartermaster" end

Q.SLOTS = 3
Q.CLASS = "rhylib_quartermaster"

-- Net armoury.qmact (client -> server) ops, UInt 3.
Q.OP_CHECK, Q.OP_APPLY, Q.OP_SAVE, Q.OP_RENAME, Q.OP_CLEAR, Q.OP_CLOSE = 0, 1, 2, 3, 4, 5
Q.OP_STOP, Q.OP_EDITOR = 6, 7          -- stop a handout; the editor (then UInt 1: 0 open, 1 save)
Q.MAX_ROWS = 120                        -- saved rows per slot (editor saves too)

-- Editor catalogue tabs (UInt 3 on the wire).
Q.TABS = { "Weapons", "Ammo", "Grenades", "Equipment", "Medical", "Specialist" }
Q.NO_LIMIT = 2047                       -- stock UInt 11: endless
-- Apply options, UInt 2: 0 nothing was in the way, 1 apply without the
-- problem items, 2 apply and save the loadout without them.
Q.APPLY_PLAIN, Q.APPLY_WITHOUT, Q.APPLY_AND_SAVE = 0, 1, 2

-- Why he won't take an item in (UInt 2 on the wire).
Q.BLOCK_FOREIGN, Q.BLOCK_DATA = 1, 2
Q.BLOCK_TEXT = { [1] = "not from an armoury", [2] = "carries its own data" }

-- Why an item of a loadout can't be issued (UInt 3 on the wire).
Q.WHY_RULE, Q.WHY_STOCK, Q.WHY_HEAVY, Q.WHY_ROOM, Q.WHY_GONE = 1, 2, 3, 4, 5

-- Carry list row kinds (UInt 2): 0 issuable, 1 job gear, 2 blocked.
Q.KIND_ISSUABLE, Q.KIND_JOB, Q.KIND_BLOCKED = 0, 1, 2

-- Item data keys that aren't an item's own data: the inventory's marks
-- (fill, issued, stock, loadout, hidden) and the weapons' saved state
-- (rhylib_base GetInventoryData: clip, mag, cell, mode, mv, safe, charge,
-- magIssued, cellIssued; the old over toggle; the grenade launcher's tr).
-- An item with any other key set (a note, a sample's reading...) carries
-- data of its own.
Q.STD_DATA = {
    fill = true, issued = true, stock = true, loadout = true, hidden = true,
    clip = true, mag = true, cell = true, mode = true, mv = true, safe = true, charge = true, over = true,
    magIssued = true, cellIssued = true, tr = true,
}

-- Q.OwnData(data) -> true when the item carries data of its own.
function Q.OwnData(data)
    if not istable(data) then return false end
    for k, v in pairs(data) do
        if not Q.STD_DATA[k] and v ~= nil and v ~= false and v ~= "" then return true end
    end
    return false
end

-- Q.CleanName(s) -> a plain one-line loadout name, at most qmNameMax letters.
function Q.CleanName(s)
    s = tostring(s or "")
    s = string.gsub(s, "%c", "")
    s = string.Trim(s)
    local n = math.max(1, math.floor(Config.Get("armoury", "qmNameMax")))
    local len = utf8.len(s)
    if not len then
        s = string.sub(s, 1, n)
    elseif len > n then
        s = string.sub(s, 1, utf8.offset(s, n + 1) - 1)
    end
    return s
end

function Q.DefaultName(slot) return "Loadout " .. slot end
