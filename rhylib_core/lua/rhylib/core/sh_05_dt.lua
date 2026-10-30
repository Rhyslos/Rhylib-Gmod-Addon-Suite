--[[
    Player DT slots and shared NW2 names (shared).

    Player DT vars (ply:SetDTFloat(slot, v) ...) are a small fixed set of
    slots per type (Float, Bool, Entity, Int, Vector, Angle, String: 0-31
    for most), shared by every addon. Rhylib.DT keeps one table of who uses
    which, so two addons never pick the same slot by accident.

        local SLOT = Rhylib.DT.Claim("Float", "myaddon.charge")   -- a free slot
        ply:SetDTFloat(SLOT, 0.5)
        Rhylib.DT.Slot("Float", "stamina.value")                   -- 28

    Rhylib.DT.Claim(kind, name, slot):
      - kind: "Float", "Bool", "Entity", "Int", "Vector", "Angle", "String".
      - name: "<module>.<what>". Claiming the same name again returns the
        same slot (Lua refresh safe).
      - slot (optional): the slot you need (existing code with a fixed
        number). Claiming a slot another name holds is an error (Rhylib.Error)
        and returns nil.
      - Without slot it takes the highest free slot from 31 down, so new
        claims stay clear of the low slots other addons (and GMod's own
        player classes) tend to use.
    Rhylib.DT.Slot(kind, name) -> slot or nil. Rhylib.DT.Table() -> the
    whole table { [kind] = { [slot] = name } } (for docs and debugging).

    Seeded with the slots already in use (2026-10-24), so existing code
    keeps its numbers:
      Float  23 jetpack.rate     24 skills.step     25 skills.dodge
             26 stamina.rate     27 grapple.s       28 stamina.value
             29 stamina.from     30 jetpack.fuel    31 jetpack.from
      Bool   27 grapple.mantle   28 stamina.exhausted  29 jetpack.thrust
             30 jetpack.locked   31 jetpack.has
      Entity 31 grapple.rope
    Added since: Float 22 grapple.zipv, Entity 30 grapple.zip (ziplines);
    Int 31 grapple.phook, Float 21 grapple.phookT, 20 grapple.phookLen,
    Vector 31 grapple.phookAt,
    30 grapple.phookHook, 29 grapple.phookLedge (personal grappling hook).

    Rhylib.NW: names of NW2 vars that several addons read, so a rename is
    one change. Rhylib.NW.CLOAK = "rhylib_cloak" etc. (see the table below);
    the owning addon still sets them.
]]

Rhylib.DT = Rhylib.DT or {}
local DT = Rhylib.DT

DT.slots = DT.slots or {}   -- [kind] = { [slot] = name }
DT.names = DT.names or {}   -- [kind] = { [name] = slot }

local SEED = {
    Float = { [23] = "jetpack.rate", [24] = "skills.step", [25] = "skills.dodge", [26] = "stamina.rate",
              [27] = "grapple.s", [28] = "stamina.value", [29] = "stamina.from", [30] = "jetpack.fuel",
              [31] = "jetpack.from", [22] = "grapple.zipv", [21] = "grapple.phookT", [20] = "grapple.phookLen" },
    Bool = { [27] = "grapple.mantle", [28] = "stamina.exhausted", [29] = "jetpack.thrust",
             [30] = "jetpack.locked", [31] = "jetpack.has" },
    Entity = { [31] = "grapple.rope", [30] = "grapple.zip" },
    Int = { [31] = "grapple.phook" },
    Vector = { [31] = "grapple.phookAt", [30] = "grapple.phookHook", [29] = "grapple.phookLedge" },
}

local function kindTables(kind)
    DT.slots[kind] = DT.slots[kind] or {}
    DT.names[kind] = DT.names[kind] or {}
    return DT.slots[kind], DT.names[kind]
end

for kind, list in pairs(SEED) do
    local slots, names = kindTables(kind)
    for slot, name in pairs(list) do
        slots[slot] = name
        names[name] = slot
    end
end

-- DT.Claim(kind, name, slot) -> slot (see the top). Shared: claim the
-- same way on both realms (at file load) so the numbers agree.
function DT.Claim(kind, name, slot)
    local slots, names = kindTables(kind)
    local have = names[name]
    if have and (slot == nil or slot == have) then return have end
    if slot then
        local owner = slots[slot]
        if owner and owner ~= name then
            Rhylib.Error("core", "DT %s slot %d is %s's: %s can't have it (pick another or claim without a slot)", kind, slot, owner, name)
            return nil
        end
        if have then slots[have] = nil end
        slots[slot] = name
        names[name] = slot
        return slot
    end
    for s = 31, 0, -1 do
        if not slots[s] then
            slots[s] = name
            names[name] = s
            return s
        end
    end
    Rhylib.Error("core", "No free DT %s slot for %s", kind, name)
end

-- DT.Slot(kind, name) -> the slot claimed under that name, or nil.
function DT.Slot(kind, name)
    local names = DT.names[kind]
    return names and names[name]
end

-- DT.Table() -> { [kind] = { [slot] = name } }.
function DT.Table() return DT.slots end

--------------------------------------------------------------------------
-- Shared NW2 names
--------------------------------------------------------------------------

Rhylib.NW = Rhylib.NW or {}
local NW = Rhylib.NW
NW.CLOAK = "rhylib_cloak"          -- rhylib_admin: cloaked (Bool)
NW.WEIGHT = "rhylib_weight"        -- rhylib_inventory: carried kg (Float)
NW.CARRY = "rhylib_carry"          -- rhylib_inventory: carry limit kg (Float)
NW.BATTALION = "rhylib_bn"         -- rhylib_roster: battalion name (String)
NW.RANK = "rhylib_rank"            -- rhylib_roster: rank index (Int)
NW.DOWN = "rhylib_down"            -- rhylib_medical: downed (Bool)
NW.DOWN_END = "rhylib_downEnd"     -- rhylib_medical: bleed-out time (Float)
NW.DOWN_LEFT = "rhylib_downLeft"   -- rhylib_medical: paused seconds left (Float)
NW.STAB_BY = "rhylib_stabBy"       -- rhylib_medical: stabilised by (Entity)
NW.DRAG_BY = "rhylib_dragBy"       -- rhylib_medical: dragged by (Entity)
NW.CUFFED = "rhylib_cuffed"        -- rhylib_mp: cuffed (Bool)
NW.STUN_END = "rhylib_stunEnd"     -- rhylib_mp: stunned until (Float)
NW.KNOCK_END = "rhylib_knockEnd"   -- core knock: until (Float, -1 open-ended)
NW.KNOCK_SOFT = "rhylib_knockSoft" -- core knock: soft knock (Bool)
NW.LYING_RAG = "rhylib_lyingRag"   -- core lying: a lying body (Bool, on the ragdoll)
NW.RAG = "rhylib_rag"              -- core lying: the player's ragdoll (Entity)
NW.CORPSE = "rhylib_corpse"        -- core lying: the player's corpse (Entity)
NW.SIM_OUT = "rhylib_simOut"       -- rhylib_training: eliminated (Bool)
NW.SIM = "rhylib_sim"              -- rhylib_training: sim health (Int)
NW.JAM_UNTIL = "rhylib_jamUntil"   -- rhylib_radio: radio jammed until (Float)
NW.PERMA = "rhylib_perma"          -- core: permanent (Bool, on entities)
