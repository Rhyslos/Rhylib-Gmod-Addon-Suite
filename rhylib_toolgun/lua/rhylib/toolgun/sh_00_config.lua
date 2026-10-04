--[[
    Toolgun (rhylib_toolgun weapon, BTX-42 pistol model): the host's spawn
    tool. LMB places the chosen thing where you aim (on the world or on
    props), facing you; RMB removes a Rhylib thing you aim at; R opens the
    list. Fixtures (armouries, cabinets, crates, med bay, jail, computers,
    training beacons) are saved for the map straight away (their own
    *_save command); droids are not saved.

    Permission rhylib.toolgun (admin). Get one with rhylib_toolgun in the
    console, !toolgun in chat, or the spawn menu (Weapons > Rhylib).

    Rhylib.Tool.ENTRIES: { id, name, cat, class, count (several at once),
    named (asks for a name: training beacons), save (console command) }.
    Entries whose class isn't installed are left out. Other addons can add
    rows with hook Rhylib.ToolEntries(list).
]]

Rhylib.Tool = Rhylib.Tool or {}
local Tool = Rhylib.Tool

Tool.MODEL = "models/jajoff/sps/cgiweapons/tc13j/btx42_pistol.mdl"
Tool.RANGE = 6000

local ARMOURY = "rhylib_armoury_save"
local MED = "rhylib_medical_save"
local MP = "rhylib_mp_save"
local PAD = "rhylib_datapad_save"
local TRAIN = "rhylib_training_save"

local ALL = {
    { id = "b1", name = "B1 battle droid", cat = "Droids", class = "rhylib_b1", count = true },
    { id = "b2", name = "B2 super battle droid", cat = "Droids", class = "rhylib_b2", count = true },
    { id = "b1t", name = "B1 training droid", cat = "Training", class = "rhylib_b1_training", count = true },
    { id = "b2t", name = "B2 training droid", cat = "Training", class = "rhylib_b2_training", count = true },
    { id = "beacon", name = "Training respawn beacon", cat = "Training", class = "rhylib_training_beacon", named = true, save = TRAIN },
    { id = "tarmoury", name = "Training armoury", cat = "Training", class = "rhylib_training_armoury", save = ARMOURY },
    { id = "tammo", name = "Training ammo cabinet", cat = "Training", class = "rhylib_training_ammo", save = ARMOURY },
    { id = "armoury", name = "Weapons armoury", cat = "Armoury", class = "rhylib_armoury", save = ARMOURY },
    { id = "ammo", name = "Ammo cabinet", cat = "Armoury", class = "rhylib_ammo_cabinet", save = ARMOURY },
    { id = "gear", name = "Gear cabinet", cat = "Armoury", class = "rhylib_gear_cabinet", save = ARMOURY },
    { id = "specw", name = "Specialist weapons", cat = "Armoury", class = "rhylib_spec_weapons", save = ARMOURY },
    { id = "specg", name = "Specialist gear", cat = "Armoury", class = "rhylib_spec_gear", save = ARMOURY },
    { id = "locker", name = "Personal locker", cat = "Armoury", class = "rhylib_locker", save = ARMOURY },
    { id = "crs", name = "Supply crate (small)", cat = "Armoury", class = "rhylib_crate_small", save = ARMOURY },
    { id = "crm", name = "Supply crate (medium)", cat = "Armoury", class = "rhylib_crate_medium", save = ARMOURY },
    { id = "crl", name = "Supply crate (large)", cat = "Armoury", class = "rhylib_crate_large", save = ARMOURY },
    { id = "medcrate", name = "Medical crate", cat = "Medical", class = "rhylib_med_crate", save = ARMOURY },
    { id = "tank", name = "Bacta tank", cat = "Medical", class = "rhylib_bacta_tank", save = MED },
    { id = "bench", name = "Chemistry bench", cat = "Medical", class = "rhylib_chem_bench", save = MED },
    { id = "sofa", name = "Med sofa", cat = "Medical", class = "rhylib_med_sofa", save = MED },
    { id = "holo", name = "Medical holotable", cat = "Medical", class = "rhylib_med_holotable", save = PAD },
    { id = "computer", name = "Battalion computer", cat = "Base", class = "rhylib_bn_computer", save = PAD },
    { id = "cell", name = "Jail cell", cat = "Base", class = "rhylib_jail_cell", save = MP },
    { id = "terminal", name = "Jail terminal", cat = "Base", class = "rhylib_jail_terminal", save = MP },
    { id = "property", name = "Property locker", cat = "Base", class = "rhylib_property_locker", save = MP },
    { id = "dummy", name = "Test dummy", cat = "Testing", class = "rhylib_test_dummy" },
    { id = "dummyt", name = "Test dummy (tough)", cat = "Testing", class = "rhylib_test_dummy_tough" },
}

-- The installed entries (built once, after entities are registered).
function Tool.Entries()
    if Tool.list then return Tool.list end
    local list = {}
    for _, e in ipairs(ALL) do
        if scripted_ents.GetStored(e.class) then list[#list + 1] = e end
    end
    hook.Run("Rhylib.ToolEntries", list)
    for i, e in ipairs(list) do e.index = i end
    Tool.list = list
    return list
end

function Tool.ById(id)
    for _, e in ipairs(Tool.Entries()) do
        if e.id == id then return e end
    end
end

function Tool.ByClass(class)
    for _, e in ipairs(Tool.Entries()) do
        if e.class == class then return e end
    end
end

Rhylib.Perms.Register("rhylib.toolgun", "admin", "Use the Rhylib toolgun (place droids, armouries, beacons and other fixtures)")
