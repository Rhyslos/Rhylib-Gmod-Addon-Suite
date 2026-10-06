--[[
    Command orders (Officer, pick one: Pistol tier 6, Commander tier 3): a short buff the officer
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
        K.OrderOf(ply)      the order this officer can give (from skills:
                            cmd_x in the Pistol spec, cmd_x_c in the Commander's)
        K.OrderRadius(ply), K.OrderTime(ply), K.OrderCooldownTime(ply)
                            with Command presence / Standing orders /
                            Seasoned command (Commander)
]]

local K = Rhylib.Skills
local Config = Rhylib.Config

local function reg(key, val, desc) Config.Register("skills", key, val, desc) end
reg("commandRadius", 380, "Command orders: radius (units, like a droid popper)")
reg("commandTime", 6, "Command orders: seconds they last")
reg("commandCooldown", 360, "Command orders: seconds before an officer can give the next one")
reg("windRegen", 4, "Second wind: stamina refill speed multiplier")
reg("triageHeal", 8, "Field triage: health per second")
reg("triageRevive", 0.25, "Field triage: downed players in reach get up with this share of their max health")
reg("focusDamage", 1.2, "Focus fire: damage multiplier")
reg("focusRecoil", 0.5, "Focus fire: view kick multiplier")
reg("pressSprint", 1.2, "Press forward: sprint speed multiplier")
reg("presenceMult", 1.5, "Command presence: order radius multiplier")
reg("seasonedCooldown", 240, "Seasoned command: order cooldown (seconds)")
reg("standingTime", 10, "Standing orders: seconds orders last")
reg("reinfCooldown", 900, "Reinforcements (Commander capstone): seconds between calls")
reg("reinfLife", 600, "Reinforcements: seconds the squad stays before pulling out (0 = until killed)")
reg("reinfSquad", { "ct_trooper", "ct_medic", "ct_rifleman", "ct_heavy" }, "Reinforcements: the clone kinds that come (ct_trooper, ct_rifleman, ct_heavy, ct_medic, ct_commander)")

reg("squadSignals", { follow = "/group", regroup = "/come", hold = "/stop", move = "/advance", aggroUp = "/advance", aggroDown = "/group", dismiss = "" },
    "Squad wheel: hand-signal chat command each order runs (for a hand-signal animation addon; \"\" = none)")
reg("squadSignalMode", "hooks", "Squad wheel: how signals reach the animation addon: hooks (PlayerSay hooks only, nothing in chat), gamemode (also the gamemode's chat, e.g. DarkRP chat commands), say (a real chat line)")

local function cfg(k) return Config.Get("skills", k) end

-- Squad wheel options in network order (the index is sent): the clone
-- orders (rhylib_droids D.SquadOrder).
K.SQUAD_OPS = { "follow", "hold", "move", "aggroUp", "aggroDown", "dismiss", "regroup" }

-- Hand-signal chat commands hidden from chat (typed or from the wheel; owner:
-- they showed as plain text). Plus every squadSignals value.
K.SIGNAL_WORDS = { ["/advance"] = true, ["/stop"] = true, ["/group"] = true, ["/come"] = true, ["/yes"] = true, ["/no"] = true }
function K.IsSignalText(text)
    if not isstring(text) then return false end
    local t = string.lower(string.Trim(text))
    if K.SIGNAL_WORDS[t] then return true end
    local map = Config.Get("skills", "squadSignals")
    if istable(map) then
        for _, v in pairs(map) do
            if isstring(v) and v ~= "" and string.lower(v) == t then return true end
        end
    end
    return false
end

K.ORDERS = {
    { key = "wind", skill = "cmd_wind", name = "Second wind", col = Color(242, 209, 75), text = "No stamina drain, fast refill" },
    { key = "triage", skill = "cmd_triage", name = "Field triage", col = Color(91, 201, 122), text = "Downed get up, healing, afflictions muted" },
    { key = "hold", skill = "cmd_hold", name = "Hold fast", col = Color(79, 143, 232), text = "Armour refilled, no damage, hold position" },
    { key = "focus", skill = "cmd_focus", name = "Focus fire", col = Color(232, 97, 60), text = "+20% damage, half the kick" },
    { key = "open", skill = "cmd_open", name = "Open up", col = Color(167, 123, 232), text = "No ammo used" },
    { key = "press", skill = "cmd_press", name = "Press forward", col = Color(214, 48, 58), text = "No knockback, faster sprint" },
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
        if set[o.skill] or set[o.skill .. "_c"] then return o end
    end
end

function K.OrderRadius(ply)
    local r = cfg("commandRadius")
    if K.Has(ply, "cmd_presence") then r = r * cfg("presenceMult") end
    return r
end

function K.OrderTime(ply)
    return K.Has(ply, "standing_orders") and cfg("standingTime") or cfg("commandTime")
end

function K.OrderCooldownTime(ply)
    return K.Has(ply, "seasoned_cmd") and cfg("seasonedCooldown") or cfg("commandCooldown")
end

-- Seconds until this officer can give an order again (0 = ready).
function K.OrderCooldown(ply)
    return math.max(0, ply:GetNW2Float("rhylib_orderCd", 0) - CurTime())
end

-- Seconds until this officer can call reinforcements again (0 = ready).
function K.ReinfCooldown(ply)
    return math.max(0, ply:GetNW2Float("rhylib_reinfCd", 0) - CurTime())
end

-- The comlink is carried by anyone with a command order skill
-- (CarrySkill "command", see Inv.MayHold).
K.COMMLINK = "rhylib_commlink"
K.CARRY_NAMES = { command = "a command order" }
function K.CarryOk(ply, skill)
    if skill == "command" then return K.OrderOf(ply) ~= nil end
    return K.Has(ply, skill)
end

-- Hold fast: hold the position. No sprint (so no jetpack hover either),
-- no jetpack climb in the air, walk speed at most (jumping still works on
-- the ground). After Light kit (-200), before Sidestep (-150) and the
-- jetpack, which read the buttons left here.
Rhylib.Hook.Add("SetupMove", "skills.holdfast", function(ply, mv)
    if not K.OrderIs(ply, "hold") then return end
    local b = mv:GetButtons()
    b = bit.band(b, bit.bnot(IN_SPEED))
    if not ply:OnGround() then b = bit.band(b, bit.bnot(IN_JUMP)) end
    mv:SetButtons(b)
    local walk = ply:GetWalkSpeed()
    mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), walk))
    mv:SetMaxSpeed(math.min(mv:GetMaxSpeed(), walk))
end, -160)

-- Press forward: sprint faster. Before every limiter (they only lower it).
Rhylib.Hook.Add("SetupMove", "skills.press", function(ply, mv)
    if not mv:KeyDown(IN_SPEED) or not K.OrderIs(ply, "press") then return end
    local m = cfg("pressSprint")
    mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * m)
    mv:SetMaxSpeed(mv:GetMaxSpeed() * m)
end, -199)
