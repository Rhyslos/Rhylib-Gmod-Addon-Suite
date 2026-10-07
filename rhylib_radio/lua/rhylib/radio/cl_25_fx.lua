--[[
    Radio sound (2026-10-07, owner: radio should sound like radio, break up
    for the tiniest moment now and then, and have the odd interference).

    GMod gives Lua no way to filter voice audio itself, so the radio feel
    is built around the voice:
      - a squelch click when someone starts and stops talking on your radio
      - tiny drop-outs: the talker's voice is muted for ~0.08 s with a soft
        crackle (Player:SetVoiceVolumeScale, put back right after), every
        few seconds on average, never long enough to lose a word
      - now and then a short burst of interference under the voice
    Only voices you hear over the radio (R.HeardOn), never local voice.

    Comms jammer: keying the radio inside a jammer's range plays a static
    loop instead (others only hear you as local voice; the server routes
    that). The incoming meter goes haywire (cl_20_hud.lua).

    Client convars: rhylib_radio_fx (on/off), rhylib_radio_fx_volume (0-1).
]]

local R = Rhylib.Radio

local fxVar = CreateClientConVar("rhylib_radio_fx", "1", true, false, "Radio voice effects (clicks, tiny drop-outs, interference)")
local volVar = CreateClientConVar("rhylib_radio_fx_volume", "0.6", true, false, "Volume of the radio voice effects (0-1)")

local function vol(mult) return math.Clamp(volVar:GetFloat(), 0, 1) * (mult or 1) end

local function pick(v)
    if istable(v) then return v[math.random(#v)] end
    return v
end

local function play(snd, mult, pitch)
    snd = pick(snd)
    if not isstring(snd) or snd == "" then return end
    local v = vol(mult)
    if v <= 0 then return end
    sound.Play(snd, LocalPlayer():GetPos(), 60, pitch or 100, v)
end

-- (exponential gap with a floor, so it feels random but never bunches up)
local function nextGap(avg)
    if not avg or avg <= 0 then return math.huge end
    return math.max(avg * 0.3, -math.log(1 - math.random() * 0.999) * avg)
end

-- [player] = { dropAt, restoreAt, scale } (kept across a Lua refresh so
-- a voice muted mid drop-out still gets its volume back)
R._fxOn = R._fxOn or {}
local radioOn = R._fxOn
local noiseAt = 0

local function heardOverRadio(p)
    if not IsValid(p) or p == LocalPlayer() then return false end
    local mine = R.Mine()
    if mine.off or mine.deaf or R.Jammed(LocalPlayer()) then return false end
    return R.HeardOn(p) ~= nil
end

local function restore(p, st)
    if st.restoreAt and IsValid(p) then p:SetVoiceVolumeScale(st.scale or 1) end
    st.restoreAt = nil
end

local function restoreAll()
    for p, st in pairs(radioOn) do restore(p, st) end
end

-- Near a jammer (its fringe, not jammed yet): 0-1. More drop-outs and
-- interference, and static under the voice (below), the closer you get.
local function fringe()
    local me = LocalPlayer()
    if not IsValid(me) or R.Jammed(me) then return 0 end
    return R.JamLevel(me)
end
local function dropGap() return nextGap((R.Cfg("fxDropEvery") or 7) * (1 - 0.8 * fringe())) end
local function noiseGap() return nextGap((R.Cfg("fxNoiseEvery") or 20) * (1 - 0.85 * fringe())) end

local function begin(p)
    radioOn[p] = { dropAt = RealTime() + dropGap() }
    play(R.Cfg("fxSquelchOn"), 0.35, 110)
    if noiseAt < RealTime() then noiseAt = RealTime() + noiseGap() end
end

Rhylib.Hook.Add("PlayerStartVoice", "radio.fx", function(p)
    if not fxVar:GetBool() or not heardOverRadio(p) then return end
    begin(p)
end, -110)

-- (a talker leaving mid drop-out: put their volume back while still valid)
Rhylib.Hook.Add("EntityRemoved", "radio.fx", function(e)
    local st = radioOn[e]
    if st then restore(e, st) radioOn[e] = nil end
end)

Rhylib.Hook.Add("PlayerEndVoice", "radio.fx", function(p)
    local st = radioOn[p]
    if not st then return end
    restore(p, st)
    radioOn[p] = nil
    if fxVar:GetBool() then play(R.Cfg("fxSquelchOff"), 0.3, 105) end
end, -110)

local nextScan = 0
timer.Create("Rhylib.Radio.Fx", 0.02, 0, function()
    local now = RealTime()
    -- Voices that went on the radio after they started (the key event
    -- arrived late, or they were talking locally first).
    if now >= nextScan and fxVar:GetBool() then
        nextScan = now + 0.1
        for p in pairs(R.speaking) do
            if not radioOn[p] and IsValid(p) and p:IsSpeaking() and heardOverRadio(p) then begin(p) end
        end
    end
    R._fxAny = false
    if next(radioOn) == nil then return end
    local any = false
    for p, st in pairs(radioOn) do
        if not IsValid(p) or not p:IsSpeaking() then
            if IsValid(p) then restore(p, st) end
            radioOn[p] = nil
        elseif not fxVar:GetBool() or not heardOverRadio(p) then
            restore(p, st)
        else
            any = true
            if st.restoreAt and now >= st.restoreAt then
                restore(p, st)
                st.dropAt = now + dropGap()
            elseif not st.restoreAt and now >= st.dropAt then
                -- A tiny drop-out: the voice dips out for a moment.
                local cur = p:GetVoiceVolumeScale() or 1
                if cur > 0 then st.scale = cur end
                p:SetVoiceVolumeScale(0)
                st.restoreAt = now + math.Clamp(R.Cfg("fxDropLen") or 0.08, 0.02, 0.25) * (1 + fringe())
                play(R.Cfg("fxCrackle"), 0.12, math.random(130, 170))
            end
        end
    end
    -- Interference now and then while someone talks on the radio.
    R._fxAny = any
    if any and now >= noiseAt then
        noiseAt = now + noiseGap()
        play(R.Cfg("fxNoise"), 0.25, math.random(95, 110))
    end
end)

--------------------------------------------------------------------------
-- Comms jammer: static when you key the radio while jammed
--------------------------------------------------------------------------

local static, noted, staticOffAt = nil, 0, 0
local wasJammed, wasRecon = false, false

local function stopStatic()
    if static then static:Stop() static = nil end
end

-- One static loop: full while you key the radio jammed (or reconnecting),
-- and near a jammer under radio voices and your own talking, louder the
-- closer you get.
local function staticTo(v)
    if v <= 0 then
        if static and RealTime() > staticOffAt then stopStatic()
        elseif static then static:ChangeVolume(0, 0.25) end
        return
    end
    staticOffAt = RealTime() + 0.5
    if not static then
        local snd = R.Cfg("jamStatic")
        if not (isstring(snd) and snd ~= "") then return end
        static = CreateSound(LocalPlayer(), snd)
        if not static then return end
        static:PlayEx(0.01, 100)
    end
    static:ChangeVolume(math.Clamp(v, 0.01, 1), 0.2)
end

timer.Create("Rhylib.Radio.JamFx", 0.1, 0, function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local jammed = R.Jammed(me)
    local recon = R.Reconnecting(me) ~= nil
    if recon ~= wasRecon then
        wasRecon = recon
        if recon then R.Note("Out of jammer range: reconnecting...") end
    end
    if jammed ~= wasJammed then
        wasJammed = jammed
        -- (the compass shows JAMMED / UPLINK ACTIVE from this, cl_20_hud)
        R.jamBanner = { jammed = jammed, at = RealTime() }
        if jammed then R.Note("Comms jammed: the radio only gives static here, people near you still hear you.")
        else chat.AddText(Color(110, 220, 120), "Republic uplink active") end
    end
    if jammed and R.txOn then
        if not static and RealTime() > noted then
            noted = RealTime() + 10
            surface.PlaySound("buttons/button10.wav")
        end
        staticTo(math.max(0.05, vol(0.8)))
    else
        local f = fringe()
        if f > 0.05 and (R._fxAny or R.txOn) then
            staticTo(vol(0.7) * f)
        else
            staticTo(0)
        end
    end
end)

Rhylib.Hook.Add("ShutDown", "radio.fx", function()
    stopStatic()
    restoreAll()
end)

-- Settings > Audio (rhylib_menus).
local function addSettings()
    local M = Rhylib.Menus
    if not (M and M.AddSetting) then return end
    M.AddSetting("Radio", { id = "radio.fx", order = 90, title = "Radio voice effects (clicks, drop-outs, interference)", kind = "toggle", convar = "rhylib_radio_fx", tab = "Audio" })
    M.AddSetting("Radio", { id = "radio.fxvol", order = 95, title = "Radio effects volume", kind = "slider", convar = "rhylib_radio_fx_volume", min = 0, max = 1, decimals = 2, tab = "Audio" })
end
Rhylib.Hook.Add("InitPostEntity", "radio.fxsettings", addSettings)
addSettings()
