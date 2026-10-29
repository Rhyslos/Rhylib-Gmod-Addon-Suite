--[[
    DarkRP money staff commands (shared: the staff menu needs the list; the
    server runs them). They work on any DarkRP server, with or without
    rhylib_roster, whatever roster's money switch says.

      !money [player] <amount>     (!addmoney) give DarkRP money (negative takes)
      !setmoney [player] <amount>  set it

    Permission "money" (Admin rank), as before.
]]

local Admin = Rhylib.Admin

local function name(p) return IsValid(p) and p:Nick() or "Console" end
local function you(caller, t) return caller == t and "themselves" or name(t) end

local H = {}
if SERVER then
    -- DarkRP money (whatever the money switch says).
    local function darkrpMoney(t)
        return t.getDarkRPVar and t.addMoney and (t:getDarkRPVar("money") or 0)
    end
    local function fmt(n) return (DarkRP and DarkRP.formatMoney or tostring)(n) end

    H.money = function(caller, t, a)
        local have = darkrpMoney(t)
        if not have then return nil, "DarkRP money isn't available" end
        local n = math.floor(a.amount)
        if n == 0 then return nil, "Give an amount" end
        if have + n < 0 then n = -have end
        t:addMoney(n)
        return name(caller) .. (n >= 0 and (" gave " .. fmt(n) .. " to ") or (" took " .. fmt(-n) .. " from ")) .. you(caller, t)
    end

    H.setmoney = function(caller, t, a)
        local have = darkrpMoney(t)
        if not have then return nil, "DarkRP money isn't available" end
        local n = math.max(0, math.floor(a.amount))
        t:addMoney(n - have)
        return name(caller) .. " set the money of " .. you(caller, t) .. " to " .. fmt(n)
    end
end

local MONEY = { "player", "Job & money" }
Admin.AddCommand({ id = "money", name = "Give money", cat = "Powers", target = "self", args = { { "amount", "Amount (negative takes)", "number" } }, aliases = { "addmoney" } }, H.money, MONEY)
Admin.AddCommand({ id = "setmoney", name = "Set money", cat = "Powers", perm = "money", target = "self", args = { { "amount", "Amount", "number" } } }, H.setmoney, MONEY)
