--[[
    Command orders (Officer tier 6, pick one): a short buff the officer
    gives with the command comlink (weapons/rhylib_commlink.lua) to
    themselves and everyone within commandRadius in sight, for
    commandTime seconds, then commandCooldown before the next one.

    State is NW2, set when an order is given:
      target  rhylib_order (Int, index in K.ORDERS), rhylib_orderEnd (Float)
              rhylib_afflMute (Float, Field triage; read by rhylib_medical)
      officer rhylib_orderCd (Float, when the next order is ready)
    A new order replaces the old one and starts the timer again.

        K.Order(ply)        the active order table, or nil
        K.OrderIs(ply, key) is this order active on ply?
        K.OrderOf(ply)      the order this officer can give (from skills)
]]

local K = Rhylib.Skills
local Config = Rhylib.Config

local function reg(key, val, desc) Config.Register("skills", key, val, desc) end
reg("commandRadius", 380, "Command orders: radius (units, like a droid popper)")
reg("commandTime", 6, "Command orders: seconds they last")
reg("commandCooldown", 360, "Command orders: seconds before an officer can give the next one")
reg("windRegen", 4, "Second wind: stamina refill speed multiplier")
reg("triageHeal", 20, "Field triage: health per second")
reg("focusDamage", 1.2, "Focus fire: damage multiplier")
reg("focusRecoil", 0.5, "Focus fire: view kick multiplier")
reg("pressSprint", 1.2, "Press forward: sprint speed multiplier")

local function cfg(k) return Config.Get("skills", k) end

K.ORDERS = {
    { key = "wind", skill = "cmd_wind", name = "Second wind", col = Color(242, 209, 75), text = "No stamina drain, fast refill" },
    { key = "triage", skill = "cmd_triage", name = "Field triage", col = Color(91, 201, 122), text = "Healing, afflictions muted" },
    { key = "hold", skill = "cmd_hold", name = "Hold fast", col = Color(79, 143, 232), text = "Armour refilled, no damage" },
    { key = "focus", skill = "cmd_focus", name = "Focus fire", col = Color(232, 97, 60), text = "+20% damage, half the kick" },
    { key = "open", skill = "cmd_open", name = "Open up", col = Color(167, 123, 232), text = "No ammo used" },
    { key = "press", skill = "cmd_press", name = "Press forward", col = Color(60, 201, 214), text = "No knockback, faster sprint" },
}
K.orderByKey = {}
for i, o in ipairs(K.ORDERS) do
    o.index = i
    K.orderByKey[o.key] = o
end

function K.Order(ply)
    if ply:GetNW2Float("rhylib_orderEnd", 0) <= CurTime() then return nil end
    return K.ORDERS[ply:GetNW2Int("rhylib_order", 0)]
end

function K.OrderIs(ply, key)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    local o = K.Order(ply)
    return o ~= nil and o.key == key
end

-- Seconds left of the active order (0 = none).
function K.OrderLeft(ply)
    return math.max(0, ply:GetNW2Float("rhylib_orderEnd", 0) - CurTime())
end

function K.OrderOf(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return nil end
    local set = K.Set(ply)
    for _, o in ipairs(K.ORDERS) do
        if set[o.skill] then return o end
    end
end

-- Seconds until this officer can give an order again (0 = ready).
function K.OrderCooldown(ply)
    return math.max(0, ply:GetNW2Float("rhylib_orderCd", 0) - CurTime())
end

-- The comlink is carried by anyone with a command order skill
-- (CarrySkill "command", see Inv.MayHold).
K.COMMLINK = "rhylib_commlink"
K.CARRY_NAMES = { command = "a command order" }
function K.CarryOk(ply, skill)
    if skill == "command" then return K.OrderOf(ply) ~= nil end
    return K.Has(ply, skill)
end

-- Press forward: sprint faster. Before every limiter (they only lower it).
Rhylib.Hook.Add("SetupMove", "skills.press", function(ply, mv)
    if not mv:KeyDown(IN_SPEED) or not K.OrderIs(ply, "press") then return end
    local m = cfg("pressSprint")
    mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * m)
    mv:SetMaxSpeed(mv:GetMaxSpeed() * m)
end, -199)
