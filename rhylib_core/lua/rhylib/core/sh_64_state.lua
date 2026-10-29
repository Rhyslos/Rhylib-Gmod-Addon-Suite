--[[
    Player state questions (shared): one place to ask "is this player
    down?", "can they act?", "may NPCs target them?" instead of reading
    another addon's private fields (ply.rhylibDown, rhylib_simOut...).

        if Rhylib.State.IsDown(ply) then ... end
        if not Rhylib.State.Targetable(ply) then continue end

    Addons answer with providers:
        Rhylib.State.Provide(question, owner, fn(ply) -> bool or nil)
    Same question + owner again = replaced (refresh-safe); fn nil removes it.

    Two kinds of question:
      Vetoes (canAct, targetable): true unless some provider says false.
      Flags  (down, cuffed, cloaked, lying, and any other name): true if
             some provider says true.
    Rhylib.State.Ask(question, ply) -> bool. Answers are cached for the
    current tick (server) / frame (client), so hot code may ask freely.

    Questions used by the suite:
      down        downed, bleeding out (rhylib_medical)
      cuffed      handcuffed or bound (rhylib_mp, rhylib_bounty)
      cloaked     staff cloak (rhylib_admin)
      lying       on the ground in a body (core lying, knock)
      canAct      may use weapons / items / interact (false: down, lying,
                  cuffed, knocked, ...)
      targetable  NPCs and auto-aim may pick them (false: down, knocked,
                  noclip, cloaked, out of a training sim, ...)
    Shortcuts: State.IsDown(ply), State.IsCuffed(ply), State.IsCloaked(ply),
    State.CanAct(ply), State.Targetable(ply).

    Core registers its own providers (lying, knock) and bridge providers
    for down / cuffed / cloaked that read the owning addons' current NW2
    names; each addon replaces its bridge by providing under its own
    module name ("medical", "mp", "admin").
]]

Rhylib.State = Rhylib.State or {}
local State = Rhylib.State

State.providers = State.providers or {}   -- [question] = { { owner, fn }, ... }
local VETO = { canAct = true, targetable = true }

local cache, cacheStamp = {}, -1
local function stamp() return SERVER and engine.TickCount() or FrameNumber() end

-- State.Provide(question, owner, fn): add / replace / remove (fn nil) a provider.
function State.Provide(question, owner, fn)
    local list = State.providers[question] or {}
    State.providers[question] = list
    for i, p in ipairs(list) do
        if p.owner == owner then
            if fn then p.fn = fn else table.remove(list, i) end
            cacheStamp = -1
            return
        end
    end
    if fn then list[#list + 1] = { owner = owner, fn = fn } end
    cacheStamp = -1
end

-- State.Ask(question, ply) -> bool (see the top).
function State.Ask(question, ply)
    if not IsValid(ply) then return false end
    local now = stamp()
    if now ~= cacheStamp then cache, cacheStamp = {}, now end
    local q = cache[question]
    if not q then q = {} cache[question] = q end
    local v = q[ply]
    if v ~= nil then return v end
    local veto = VETO[question]
    v = veto and true or false
    for _, p in ipairs(State.providers[question] or {}) do
        local ok, r = pcall(p.fn, ply)
        if ok then
            if veto and r == false then v = false break end
            if not veto and r == true then v = true break end
        end
    end
    q[ply] = v
    return v
end

function State.IsDown(ply) return State.Ask("down", ply) end
function State.IsCuffed(ply) return State.Ask("cuffed", ply) end
function State.IsCloaked(ply) return State.Ask("cloaked", ply) end
function State.CanAct(ply) return State.Ask("canAct", ply) end
function State.Targetable(ply) return State.Ask("targetable", ply) end

--------------------------------------------------------------------------
-- Core's own answers, and bridges for the addons that haven't moved yet
--------------------------------------------------------------------------

local NW = Rhylib.NW
local L = Rhylib.Lying

State.Provide("lying", "core", function(ply) return L and L.Is and L.Is(ply) or nil end)
State.Provide("canAct", "core", function(ply)
    if L and L.Knocked and L.Knocked(ply) then return false end
end)
State.Provide("targetable", "core", function(ply)
    if not ply:Alive() or ply:GetMoveType() == MOVETYPE_NOCLIP then return false end
    if ply:GetNW2Float(NW.KNOCK_END, 0) ~= 0 then return false end
end)

-- Bridges (replaced when the addon provides under the same owner name).
State.Provide("down", "medical", function(ply)
    if SERVER and ply.rhylibDown then return true end
    return ply:GetNW2Bool(NW.DOWN, false) or nil
end)
State.Provide("cuffed", "mp", function(ply) return ply:GetNW2Bool(NW.CUFFED, false) or nil end)
State.Provide("cloaked", "admin", function(ply) return ply:GetNW2Bool(NW.CLOAK, false) or nil end)
State.Provide("canAct", "medical", function(ply) if State.IsDown(ply) then return false end end)
State.Provide("canAct", "mp", function(ply) if State.IsCuffed(ply) then return false end end)
State.Provide("targetable", "medical", function(ply) if State.IsDown(ply) then return false end end)
State.Provide("targetable", "admin", function(ply) if State.IsCloaked(ply) then return false end end)
State.Provide("targetable", "training", function(ply)
    if ply:GetNW2Bool(NW.SIM_OUT, false) or (SERVER and (ply.rhylibSimImmune or 0) > CurTime()) then return false end
end)
