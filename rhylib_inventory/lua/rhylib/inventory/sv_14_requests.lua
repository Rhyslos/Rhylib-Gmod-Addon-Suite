--[[
    Inventory client requests (server only; split from sv_10_inventory.lua).
    Each reads exactly what cl_10_inventory writes; all rate limited.
    Inv.Locked(ply) (cuffed, stunned, jailed: Rhylib.InventoryLocked) is
    defined here too.
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local I = Inv.Internal
local IsWorn = Items.IsWorn

--------------------------------------------------------------------------
-- Client requests
--------------------------------------------------------------------------

-- Inv.Locked(ply): cuffed, stunned or jailed players (rhylib_mp) can't
-- drop, use or hand over items. Other addons answer the
-- Rhylib.InventoryLocked hook (return true to lock).
-- Example:
--   Rhylib.Hook.Add("Rhylib.InventoryLocked", "myaddon.lock", function(ply)
--       if ply.myFrozen then return true end
--   end)
function Inv.Locked(ply)
    return hook.Run("Rhylib.InventoryLocked", ply) == true
end

-- Client requests. Each reads exactly what cl_10_inventory writes:
--   inv.req      nothing: send me everything
--   inv.move     uid 16, container 5, x 5, y 5, rot 1, single 1
--   inv.hotbar   uid 16, slot 3
--   inv.split / inv.hide / inv.use   uid 16
--   inv.combine  nothing
--   inv.drop     uid 16, single 1
Rhylib.Net.Receive("inv.req", function(ply)
    Inv.SendFull(ply)
end, { rate = 1, burst = 2 })

Rhylib.Net.Receive("inv.move", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    local cid = net.ReadUInt(Items.CONT_BITS)
    local x = net.ReadUInt(Items.POS_BITS)
    local y = net.ReadUInt(Items.POS_BITS)
    local rot = net.ReadBool()
    local single = net.ReadBool()
    Inv.Move(ply, uid, cid, x, y, rot, single)
end, { rate = 20, burst = 10 })

Rhylib.Net.Receive("inv.hotbar", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    Inv.SetHotbar(ply, uid, net.ReadUInt(3))
end, { rate = 10, burst = 10 })

Rhylib.Net.Receive("inv.split", function(ply)
    Inv.Split(ply, net.ReadUInt(Items.UID_BITS))
end, { rate = 5, burst = 5 })

Rhylib.Net.Receive("inv.combine", function(ply)
    Inv.StartCombine(ply)
end, { rate = 2, burst = 2 })

Rhylib.Net.Receive("inv.drop", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    local single = net.ReadBool()
    if Inv.Locked(ply) then return end
    Inv.Drop(ply, uid, single)
end, { rate = 8, burst = 8 })

-- Hide / unhide contraband from searches (rhylib_mp rolls for each hidden
-- item). data.hidden is the hider's SteamID64, so it lapses when the item
-- changes hands.
Rhylib.Net.Receive("inv.hide", function(ply)
    if Inv.Locked(ply) then return end
    local st = Inv.Get(ply)
    local inst = st.byUid[net.ReadUInt(Items.UID_BITS)]
    if not inst or IsWorn(inst.c) then return end
    inst.data = inst.data or {}
    if inst.data.hidden then
        inst.data.hidden = nil
    else
        if not Items.IsContraband(inst.id) then return end
        local sid, n = ply:SteamID64() or "0", 0
        for _, o in pairs(st.byUid) do
            if o.data and o.data.hidden == sid then n = n + 1 end
        end
        if n >= Items.HIDE_MAX then
            Inv.Note(ply, "You can hide " .. Items.HIDE_MAX .. " items at most")
            I.sendSet(ply, st, inst)
            return
        end
        inst.data.hidden = sid
    end
    I.update(ply, st, inst)
end, { rate = 5, burst = 5 })

Rhylib.Net.Receive("inv.use", function(ply)
    if Inv.Locked(ply) then return end
    local inst = Inv.Get(ply).byUid[net.ReadUInt(Items.UID_BITS)]
    local def = inst and Items.defs[inst.id]
    if def and def.weapon and ply:HasWeapon(def.weapon) then
        ply:SelectWeapon(def.weapon)
    end
end, { rate = 5, burst = 5 })
