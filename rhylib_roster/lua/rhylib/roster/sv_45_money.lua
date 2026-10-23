--[[
    DarkRP money switch (server). Config roster "money" (Server settings,
    off by default): a clone server has nothing to buy, so with it off
      - no paydays (and no "Payday!" notice) and no NPC kill pay
      - the chat commands /give, /dropmoney (/moneydrop) and /cheque
        (/check) are taken out of DarkRP (put back when it's switched on)
      - doors can't be bought (hook playerBuyDoor)
    The HUD (rhylib_hud) and the Profile page (rhylib_menus) hide money too,
    through R.MoneyOn(). Wallets are kept as they are; staff can still use
    !money / !setmoney.
]]

local R = Rhylib.Roster

local MONEY_COMMANDS = R.MONEY_COMMANDS
R.savedMoneyCommands = R.savedMoneyCommands or {}

-- Take the money chat commands out of DarkRP's list, or put them back.
local function applyCommands()
    if not (DarkRP and DarkRP.chatCommands) then return end
    local on = R.MoneyOn()
    local saved = R.savedMoneyCommands
    for _, c in ipairs(MONEY_COMMANDS) do
        if on then
            if saved[c] and not DarkRP.chatCommands[c] then DarkRP.chatCommands[c] = saved[c] end
        elseif DarkRP.chatCommands[c] then
            saved[c] = DarkRP.chatCommands[c]
            DarkRP.chatCommands[c] = nil
        end
    end
end
Rhylib.Hook.Add("InitPostEntity", "roster.money", function() timer.Simple(1, applyCommands) end)
Rhylib.Hook.Add("Rhylib.ConfigChanged", "roster.money", function(m, k)
    if m == "roster" and k == "money" then applyCommands() end
end)
applyCommands()   -- (Lua refresh)

-- No salary and no notice (DarkRP: suppress, message, amount).
Rhylib.Hook.Add("playerGetSalary", "roster.money", function()
    if not R.MoneyOn() then return true, nil, 0 end
end)

Rhylib.Hook.Add("canEarnNPCKillPay", "roster.money", function()
    if not R.MoneyOn() then return false end
end)

Rhylib.Hook.Add("playerBuyDoor", "roster.money", function()
    if not R.MoneyOn() then return false, "Doors can't be bought on this server" end
end)
