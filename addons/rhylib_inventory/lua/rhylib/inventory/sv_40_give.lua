--[[
    Giving items to other players, and holding items in your hand (server only).

      inv.give  (request) item uid, single, target player: hands it over
                straight into their inventory (what doesn't fit stays
                with you). From the inventory menu, or the hand weapon.
      inv.hold  (request) item uid: hold that hotbar item (def.hand,
                e.g. magazines) with the rhylib_hand weapon.

    The held item's uid is NW2Int "rhylib_handUid" on the player.
    Fires hook Rhylib.ItemGiven(giver, target, id, count) after a give.
    Range: config inventory giveRange (130 units).
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local Config = Rhylib.Config
local I = Inv.Internal

-- Inv.CanGive(ply, target): close (giveRange), both alive, in sight,
-- neither locked nor downed. Returns true/false.
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

-- Inv.GiveTo(ply, target, uid, single): hands ply's item uid straight
-- into target's inventory (single: just one off a stack). What doesn't
-- fit stays with ply; job gear and items target may not carry are
-- refused. Both get a note. Returns how many were given.
-- Example: Rhylib.Inventory.GiveTo(medic, patient, kit.uid, true)
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
        local dupe = Inv.AtLimit(target, inst.id)
        Inv.Note(ply, target:Nick() .. (dupe and (" already carries " .. (Inv.Limit(target, inst.id) > 1 and Inv.Limit(target, inst.id) or "one")) or " has no room"))
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

-- inv.give: uid 16, single 1, target entity.
Rhylib.Net.Receive("inv.give", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    local single = net.ReadBool()
    local target = net.ReadEntity()
    Inv.GiveTo(ply, target, uid, single)
end, { rate = 6, burst = 6 })

-- Hold a hotbar item in your hand. inv.hold: uid 16. Only items with
-- def.hand that sit on the hotbar.
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
