--[[
    Giving items to other players, and holding items in your hand.

      inv.give  (request) item uid, single, target player: hands it over
                straight into their inventory (what doesn't fit stays
                with you). From the inventory menu, or the hand weapon.
      inv.hold  (request) item uid: hold that hotbar item (def.hand,
                e.g. magazines) with the rhylib_hand weapon.

    The held item's uid is NW2Int "rhylib_handUid" on the player.
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local Config = Rhylib.Config
local I = Inv.Internal

-- Close, alive, in sight, and free to receive.
function Inv.CanGive(ply, target)
    if not (IsValid(target) and target:IsPlayer() and target ~= ply and target:Alive() and ply:Alive()) then return false end
    local r = Config.Get("inventory", "giveRange") or 130
    if ply:GetPos():DistToSqr(target:GetPos()) > r * r then return false end
    if Inv.Locked(ply) or Inv.Locked(target) then return false end
    if ply.rhylibDown or target.rhylibDown then return false end   -- downed (rhylib_medical)
    local tr = util.TraceLine({ start = ply:EyePos(), endpos = target:WorldSpaceCenter(), filter = { ply, target }, mask = MASK_SOLID })
    return not tr.Hit
end

local function label(def, n)
    return (def and def.name or "item") .. (n > 1 and (" x" .. n) or "")
end

-- Returns how many were given.
function Inv.GiveTo(ply, target, uid, single)
    if not Inv.CanGive(ply, target) then return 0 end
    local st = Inv.Get(ply)
    local inst = st.byUid[uid]
    if not inst then return 0 end
    local canLeave, why = Items.CanLeave(st, inst)
    if not canLeave then
        Inv.Note(ply, why)
        return 0
    end
    local def = Items.defs[inst.id]
    if inst.data and inst.data.loadout then
        Inv.Note(ply, "Job gear can't be given away")
        return 0
    end
    if not Inv.MayHold(target, inst.id) then
        Inv.Note(ply, target:Nick() .. " can't carry that (needs a skill)")
        return 0
    end
    local n = (single and inst.count > 1) and 1 or inst.count
    I.captureWeapon(ply, inst)
    local left = Inv.AddItem(target, inst.id, n, table.Copy(inst.data or {}))
    local given = n - left
    if given <= 0 then
        local dupe = Items.Unique(def) and Inv.Has(target, inst.id)
        Inv.Note(ply, target:Nick() .. (dupe and " already has one" or " has no room"))
        return 0
    end
    if given < inst.count then
        inst.count = inst.count - given
        I.update(ply, st, inst)
    else
        I.removeInst(ply, st, uid)
    end
    Inv.Note(ply, "Gave " .. label(def, given) .. " to " .. target:Nick())
    Inv.Note(target, ply:Nick() .. " gave you " .. label(def, given))
    target:EmitSound("items/ammo_pickup.wav", 60)
    hook.Run("Rhylib.ItemGiven", ply, target, inst.id, given)
    return given
end

Rhylib.Net.Receive("inv.give", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    local single = net.ReadBool()
    local target = net.ReadEntity()
    Inv.GiveTo(ply, target, uid, single)
end, { rate = 6, burst = 6 })

-- Hold a hotbar item in your hand.
Rhylib.Net.Receive("inv.hold", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    if not ply:Alive() or Inv.Locked(ply) or ply.rhylibDown then return end
    local inst = Inv.Get(ply).byUid[uid]
    local def = inst and Items.defs[inst.id]
    if not (def and def.hand and inst.hb) then return end
    ply:SetNW2Int("rhylib_handUid", uid)
    if not ply:HasWeapon(Inv.HAND) then
        ply.rhylibGiving = true
        ply:Give(Inv.HAND)
        ply.rhylibGiving = false
    end
    ply:SelectWeapon(Inv.HAND)
end, { rate = 6, burst = 6 })
