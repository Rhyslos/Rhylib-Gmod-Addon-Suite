--[[
    The Gear tab of the Bounty Office (server): buying hunter gear with
    DarkRP money. Stock: config bounty "shop" ({ item id, price }); items
    that aren't installed are skipped. Bounty hunters only while hunterOnly
    is on. The money is taken only if the item fitted in the inventory.

    Message: bounty.buy  client -> server: office, index into the shop
    list (UInt 8). Rate 4/s.
]]

local B = Rhylib.Bounty
local Net = Rhylib.Net

Net.Receive("bounty.buy", function(ply)
    local office = net.ReadEntity()
    local row = (B.Cfg("shop") or {})[net.ReadUInt(8)]
    if not B.NearOffice(ply, office) then return B.Msg(ply, false, "Go to a Bounty Office") end
    if not istable(row) then return end
    local id, price = row[1], math.max(0, math.floor(tonumber(row[2]) or 0))
    local I, Items = Rhylib.Inventory, Rhylib.Items
    if not (I and I.AddItem and Items and Items.Get(id)) then return B.Msg(ply, false, "That isn't available") end
    if not B.MayHunt(ply) then return B.Msg(ply, false, "Only bounty hunters buy here") end
    if I.MayHold and not I.MayHold(ply, id) then return B.Msg(ply, false, "You can't carry that") end
    if not (ply.canAfford and ply:canAfford(price)) then return B.Msg(ply, false, "You can't afford " .. B.Money(price)) end
    if I.AddItem(ply, id, 1) > 0 then return B.Msg(ply, false, "No room for it (or you carry as many as you can)") end
    if price > 0 then ply:addMoney(-price) end
    B.Msg(ply, true, "Bought " .. (Items.Get(id).name or id) .. " for " .. B.Money(price))
end, { rate = 4, burst = 4 })
