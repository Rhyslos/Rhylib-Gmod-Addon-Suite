--[[
    Turns the jetpack on for players wearing one in the Back slot.
    Only runs when an inventory changes or a player spawns. Server.

    Listens to Rhylib.InventoryChanged (rhylib_inventory) and PlayerSpawn
    (next tick: full tank, unlocked). Perm rhylib.jetpack.give (admin) for
    the console command rhylib_jetpack_give.
]]

local J = Rhylib.Jetpack

-- J.Set(ply, has): turn the jetpack on/off for a player (DTBool 31). On =
-- full tank, unlocked. Normally set by J.Refresh from the inventory.
-- Example (a jetpack without rhylib_inventory): Rhylib.Jetpack.Set(ply, true)
function J.Set(ply, has)
    if ply:GetDTBool(J.DT_HAS) == has then return end
    ply:SetDTBool(J.DT_HAS, has)
    ply:SetDTBool(J.DT_THRUST, false)
    if has then
        J.SetLine(ply, 1, 0, 0)
        ply:SetDTBool(J.DT_LOCKED, false)
    end
end

local function wearing(ply)
    local Inv, Items = Rhylib.Inventory, Rhylib.Items
    if not (Inv and Inv.Get and Items and Items.SLOT_BACK) then return false end
    for _, inst in pairs(Inv.Get(ply).cont[Items.SLOT_BACK].items) do
        if inst.id == "jetpack" then return true end
    end
    return false
end

-- J.Refresh(ply): on if a "jetpack" item is in the Back slot, else off.
-- Does nothing without rhylib_inventory (so J.Set from other code stays).
function J.Refresh(ply)
    if Rhylib.Inventory and Rhylib.Inventory.Get then
        J.Set(ply, wearing(ply))
    end
end

Rhylib.Hook.Add("Rhylib.InventoryChanged", "jetpack.equip", function(ply)
    J.Refresh(ply)
end)

Rhylib.Hook.Add("PlayerSpawn", "jetpack.spawn", function(ply)
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        J.Refresh(ply)
        J.SetLine(ply, 1, 0, 0)
        ply:SetDTBool(J.DT_LOCKED, false)
    end)
end)

-- Admin test command, also works without the inventory addon: with it,
-- gives a jetpack item (worn if the Back slot is free, else in the
-- inventory or on the ground); without it, toggles the jetpack on/off.
Rhylib.Perms.Register("rhylib.jetpack.give", "admin", "Give yourself a jetpack with rhylib_jetpack_give")
concommand.Add("rhylib_jetpack_give", function(ply)
    if not IsValid(ply) then return end
    Rhylib.Perms.Check(ply, "rhylib.jetpack.give", function(ok)
        if not ok or not IsValid(ply) then return end
        if Rhylib.Inventory and Rhylib.Inventory.AddItem then
            Rhylib.Inventory.AddOrDrop(ply, "jetpack", 1, {})
        else
            J.Set(ply, not J.Has(ply))
        end
    end)
end)
