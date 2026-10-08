--[[
    Saved item picture settings (2026-10-08, owner: tune each picture in
    game and keep it). Staff with rhylib.inventory.icons adjust an item's
    picture in the picture editor (cl_15_icons); the server keeps every
    item's settings in Data "inventory" "icontune" and sends the whole
    table to each player once they've loaded in (they ask), and changes to everyone.

    Per item id: { p, y, r (camera pitch / turn / roll, or nil = the
    automatic view), z (zoom), ox, oy (move, fractions of the picture) }.
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items

Rhylib.Perms.Register("rhylib.inventory.icons", "admin", "Adjust inventory item pictures for everyone")
Rhylib.Net.Register("inv.icontunes")

Inv.iconTune = Rhylib.Data.Get("inventory", "icontune")
if not istable(Inv.iconTune) then Inv.iconTune = {} end

local function writeOne(id, t)
    net.WriteString(id)
    net.WriteBool(t ~= nil)
    if not t then return end
    net.WriteBool(t.y ~= nil)
    if t.y ~= nil then
        net.WriteFloat(t.p or 0)
        net.WriteFloat(t.y or 0)
        net.WriteFloat(t.r or 0)
    end
    net.WriteFloat(t.z or 1)
    net.WriteFloat(t.ox or 0)
    net.WriteFloat(t.oy or 0)
end

-- All of them to one player (or a list of players).
function Inv.SendIconTunes(target)
    Rhylib.Net.Start("inv.icontunes")
    net.WriteBool(true)   -- (full table: replaces what the client has)
    net.WriteUInt(table.Count(Inv.iconTune), 12)
    for id, t in pairs(Inv.iconTune) do writeOne(id, t) end
    net.Send(target)
end

-- Each client asks once it has loaded in (InitPostEntity), so the table
-- can't arrive before it can be read; once per connection.
Rhylib.Net.Receive("inv.icontunesreq", function(ply)
    if ply.rhylibIconTunesSent then return end
    ply.rhylibIconTunesSent = true
    Inv.SendIconTunes(ply)
end, { rate = 1, burst = 2 })

local function finite(v) return v == v and math.abs(v) < 1e6 end

-- An editor saved (or reset) one item.
Rhylib.Net.Receive("inv.icontune", function(ply)
    local id = net.ReadString()
    local reset = net.ReadBool()
    local t
    if not reset then
        t = {}
        local p, y, r
        local cam = net.ReadBool()
        if cam then p, y, r = net.ReadFloat(), net.ReadFloat(), net.ReadFloat() end
        local z, ox, oy = net.ReadFloat(), net.ReadFloat(), net.ReadFloat()
        -- (NaN / inf would break the saved table)
        for _, v in ipairs({ p or 0, y or 0, r or 0, z, ox, oy }) do
            if not finite(v) then return end
        end
        if cam then
            t.p = math.Clamp(p, -90, 90)
            t.y = math.NormalizeAngle(y)
            t.r = math.NormalizeAngle(r)
        end
        t.z = math.Clamp(z, 0.25, 4)
        t.ox = math.Clamp(ox, -0.5, 0.5)
        t.oy = math.Clamp(oy, -0.5, 0.5)
    end
    if not Items.defs[id] then return end
    Rhylib.Perms.Check(ply, "rhylib.inventory.icons", function(ok)
        if not ok or not IsValid(ply) then return end
        Inv.iconTune[id] = t
        Rhylib.Data.Set("inventory", "icontune", Inv.iconTune)
        Rhylib.Net.Start("inv.icontunes")
        net.WriteBool(false)   -- (one change)
        net.WriteUInt(1, 12)
        writeOne(id, t)
        net.Broadcast()
        ply:ChatPrint((reset and "Picture back to automatic: " or "Picture saved for everyone: ") .. (Items.defs[id].name or id))
    end)
end, { rate = 4, burst = 8 })
