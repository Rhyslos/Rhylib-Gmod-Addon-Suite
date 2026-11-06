--[[
    Staff view (client): what staff with full toolgun access
    (Tool.FullAccess) see while the toolgun is their active weapon (also in
    Command and physgun mode). The server part is sh_30_staffview.lua.

    Night vision: the flashlight key (impulse 100) toggles it while the
    toolgun is out (the flashlight / helmet lights don't switch then).
    The optics' look (rhylib_gear: colours kept, a green multiply tint,
    brightened, a shadowless light from your eyes plus a soft light round
    you, turned down where it's already bright) without static,
    scanlines, grain, rolling band or flicker. Reads gear's night vision
    settings when rhylib_gear is installed, else its defaults. Off while
    optics are up or another night vision is on (rhylib_gear).

    Minimal HUD: hides the normal HUD (hook Rhylib.HUDHide, rhylib_hud)
    and draws three chips top left (STAFF VIEW, NIGHT VISION · <your
    flashlight key> with a
    green edge when on, X-RAY · N m with a blue edge when on), HP / AP
    numbers and a small hotbar bottom left (key + short name, the held
    one light; rhylib_hud's HUD.HotbarEntries, else your weapons by slot).
    The toolgun's own info bar, chat, notices and the kill feed still draw.

    Names: players in sight within 60 m get their name and
    "battalion · N m" over the head.

    X-ray: soft glow outlines (halo, through walls) round everything in
    range of the picked kinds, anywhere on screen, with a small label
    (name or kind · N m; spawned things: "<thing> · <who spawned it>").
    Colours: players white, droids (and other NPCs) red, clones blue,
    spawned things yellow (toolgun / spawn menu: NW2Bool
    rhylib_toolSpawned, NW2String rhylib_spawnedBy, or a CPPI owner),
    bombs and mines amber, objective markers gold. Cloaked players are
    left out. Gathered every 0.25 s: labels for the 80 nearest, outlines
    for the 40 nearest, one halo per group (spawned things and objectives
    share one). The server adds spots to your PVS while X-ray is on
    (net tool.xray: on, range, kinds; sent on a change, on drawing the
    toolgun and every 10 s while on), so things behind walls are sent.
    Without rhylib_hud the default health / armour / ammo boxes are
    hidden instead. HP shows sim health with a training gun.

    Command: rhylib_xray / !xray (server, staff only) flips X-ray.

    Client convars (saved): rhylib_tool_xray 0, rhylib_tool_xray_players 1,
    rhylib_tool_xray_npcs 1, rhylib_tool_xray_spawned 1,
    rhylib_tool_xray_eod 1 (bombs, mines, objectives),
    rhylib_tool_xray_range 80 (metres, 10-200), rhylib_tool_nv 0,
    rhylib_tool_names 1, rhylib_tool_minhud 1.
    Tool.StaffView() -> true while the staff view applies.
]]

local Tool = Rhylib.Tool
local UI = Rhylib.UI

local M = 0.01905          -- metres per unit
local NAME_RANGE = 60 / M  -- names without X-ray
local MAX_SHOWN = 80
local GATHER = 0.25

local cvXray = CreateClientConVar("rhylib_tool_xray", "0", true, false, "Toolgun staff view: X-ray on (0/1)")
local cvPlayers = CreateClientConVar("rhylib_tool_xray_players", "1", true, false, "Toolgun X-ray: players (0/1)")
local cvNpcs = CreateClientConVar("rhylib_tool_xray_npcs", "1", true, false, "Toolgun X-ray: droids, clones and other NPCs (0/1)")
local cvSpawned = CreateClientConVar("rhylib_tool_xray_spawned", "1", true, false, "Toolgun X-ray: things spawned with the toolgun or spawn menu (0/1)")
local cvEod = CreateClientConVar("rhylib_tool_xray_eod", "1", true, false, "Toolgun X-ray: bombs, mines and objective markers (0/1)")
local cvRange = CreateClientConVar("rhylib_tool_xray_range", "80", true, false, "Toolgun X-ray: range in metres (10-200)")
local cvNV = CreateClientConVar("rhylib_tool_nv", "0", true, false, "Toolgun staff view: night vision (F toggles it with the toolgun out)")
local cvNames = CreateClientConVar("rhylib_tool_names", "1", true, false, "Toolgun staff view: names over players in sight within 60 m (0/1)")
local cvMinHud = CreateClientConVar("rhylib_tool_minhud", "1", true, false, "Toolgun staff view: minimal HUD instead of the normal one (0/1)")

-- Theme tokens (cl_11_theme.lua).
local COL_TEXT = UI.Col("toolgun.svText", 228, 227, 220)
local COL_DIM = UI.Col("toolgun.svDim", 201, 211, 204)
local COL_PANEL = UI.Col("toolgun.svPanel", 14, 16, 15, 205)
local COL_EDGE = UI.Col("toolgun.svEdge", 0, 0, 0, 230)
local COL_NV = UI.Col("toolgun.svNv", 92, 214, 125)
local COL_NV_TEXT = UI.Col("toolgun.svNvText", 155, 227, 174)
local COL_XR = UI.Col("toolgun.svXray", 133, 183, 235)
local COL_XR_TEXT = UI.Col("toolgun.svXrayText", 185, 214, 245)
local COL_HP = UI.Col("toolgun.svHp", 255, 138, 128)
local COL_AP = UI.Col("toolgun.svAp", 159, 205, 245)
local COL_SLOT_ON = UI.Col("toolgun.svSlotOn", 228, 227, 220, 230)
local COL_SLOT_ON_TEXT = UI.Col("toolgun.svSlotOnText", 14, 16, 15)
local COL_SLOT = UI.Col("toolgun.svSlot", 0, 0, 0, 115)
local COL_SLOT_EDGE = UI.Col("toolgun.svSlotEdge", 255, 255, 255, 64)
-- X-ray: outline colour and label colour per kind.
local KIND = {
    player = { halo = UI.Col("toolgun.xrPlayer", 255, 255, 255), label = UI.Col("toolgun.xrPlayerText", 255, 255, 255) },
    droid = { halo = UI.Col("toolgun.xrDroid", 255, 90, 78), label = UI.Col("toolgun.xrDroidText", 255, 138, 128) },
    clone = { halo = UI.Col("toolgun.xrClone", 90, 169, 240), label = UI.Col("toolgun.xrCloneText", 159, 205, 245) },
    spawned = { halo = UI.Col("toolgun.xrSpawned", 255, 210, 74), label = UI.Col("toolgun.xrSpawnedText", 255, 210, 74) },
    eod = { halo = UI.Col("toolgun.xrEod", 239, 159, 39), label = UI.Col("toolgun.xrEodText", 255, 179, 92) },
    obj = { halo = UI.Col("toolgun.xrObj", 255, 200, 70), label = UI.Col("toolgun.xrObjText", 255, 210, 122) },
}
-- Halo groups: one halo.Add each (spawned things and objectives share one).
local HALO = {
    player = { col = KIND.player.halo }, droid = { col = KIND.droid.halo }, clone = { col = KIND.clone.halo },
    item = { col = KIND.spawned.halo }, eod = { col = KIND.eod.halo },
}
local HALO_ORDER = { "player", "droid", "clone", "item", "eod" }
for _, g in pairs(HALO) do g.list, g.n = {}, 0 end
local HALO_OF = { player = "player", droid = "droid", clone = "clone", spawned = "item", obj = "item", eod = "eod" }
local MAX_HALO = 40   -- (halo costs per entity: fewer than the labels)
local function clearHalos()
    for _, k in ipairs(HALO_ORDER) do
        local g = HALO[k]
        for i = 1, g.n do g.list[i] = nil end
        g.n = 0
    end
end

--------------------------------------------------------------------------
-- Who and when
--------------------------------------------------------------------------

local staffAt, staffOk = 0, false
local function isStaff(me)
    local now = RealTime()
    if now >= staffAt then
        staffAt = now + 1
        staffOk = Tool.FullAccess and Tool.FullAccess(me) or false
    end
    return staffOk
end

local activeFrame, activeVal = -1, false
-- Tool.StaffView(): staff, alive, toolgun in hand (asked once a frame).
function Tool.StaffView()
    local f = FrameNumber()
    if f == activeFrame then return activeVal end
    activeFrame = f
    local me = LocalPlayer()
    local ok = false
    if IsValid(me) and me:Alive() then
        local w = me:GetActiveWeapon()
        ok = IsValid(w) and w:GetClass() == "rhylib_toolgun" and isStaff(me)
    end
    activeVal = ok
    return ok
end
local active = Tool.StaffView

-- Optics up, or the gear's own night vision (sun visor, binoculars, a scope).
local function opticsBusy(me)
    if me:GetNW2Int("rhylib_optics", 0) ~= 0 then return true end
    local G = Rhylib.Gear
    return G and G.NightVision and G.NightVision() or false
end

--------------------------------------------------------------------------
-- Night vision
--------------------------------------------------------------------------

local NV_LIGHT = 262000   -- (dynamic light index, outside the entity range)

local function nvOn()
    if not (cvNV:GetBool() and active()) then return false end
    return not opticsBusy(LocalPlayer())
end

-- (gear's night vision settings when it's installed)
local NV_DEFAULT = { nvLift = 0.04, nvColour = 0.6, nvTint = 0.3, nvBoost = 1.5, nvGain = 2.5, nvLightRange = 4000 }
local function nvCfg(k)
    local G = Rhylib.Gear
    local v = G and G.Cfg and G.Cfg(k)
    if isnumber(v) then return v end
    return NV_DEFAULT[k]
end

Rhylib.Hook.Add("PlayerBindPress", "toolgun.staffnv", function(ply, bind, pressed)
    if not pressed or not string.find(bind, "impulse 100", 1, true) then return end
    if not active() or opticsBusy(ply) then return end
    RunConsoleCommand("rhylib_tool_nv", cvNV:GetBool() and "0" or "1")
    surface.PlaySound("items/flashlight1.wav")
    return true
end, -50)

-- Auto gain: less boost where it's already lit (as the optics do).
local gain, nextSample = 1, 0
local function lum(v) return v and (v.x * 0.3 + v.y * 0.59 + v.z * 0.11) or 0 end
local trIn, trOut = { mask = MASK_OPAQUE }, {}
trIn.output = trOut
local function updateGain(me)
    if RealTime() < nextSample then return end
    nextSample = RealTime() + 0.1
    local eye = me:EyePos()
    trIn.start, trIn.endpos, trIn.filter = eye, eye + me:GetAimVector() * 1500, me
    util.TraceLine(trIn)
    local l = math.max(lum(render.GetLightColor(eye)), lum(render.GetLightColor(trOut.HitPos + trOut.HitNormal * 4)))
    gain = Lerp(0.35, gain, math.Clamp(1 - l * 4, 0.1, 1))
end

local amp
local function dropAmp()
    if IsValid(amp) then amp:Remove() end
    amp = nil
end

Rhylib.Hook.Add("PreRender", "toolgun.staffnv", function()
    if not nvOn() then
        if amp then dropAmp() end
        return
    end
    local me = LocalPlayer()
    updateGain(me)
    if not IsValid(amp) then
        amp = ProjectedTexture()
        local m = Material("effects/flashlight/soft")
        amp:SetTexture((m and not m:IsError()) and "effects/flashlight/soft" or "effects/flashlight001")
        amp:SetEnableShadows(false)
        amp:SetNearZ(12)
        amp:SetFOV(120)
        amp:SetColor(Color(235, 255, 235))
    end
    local ang, pos = me:EyeAngles(), me:EyePos()
    if me:ShouldDrawLocalPlayer() then pos = pos + ang:Forward() * 40 end
    amp:SetPos(pos)
    amp:SetAngles(ang)
    amp:SetFarZ(math.max(200, nvCfg("nvLightRange")))
    amp:SetBrightness(nvCfg("nvGain") * gain)
    amp:Update()
    -- (a soft light round you, for the sides and behind)
    local d = DynamicLight(NV_LIGHT)
    if d then
        d.pos = me:GetPos() + Vector(0, 0, 40)
        d.r, d.g, d.b = 200, 255, 200
        d.brightness = 0.6 * gain
        d.size = 500
        d.decay = 1000
        d.dietime = CurTime() + 0.2
    end
end)

local cm = {
    ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 0,
    ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
}

Rhylib.Hook.Add("RenderScreenspaceEffects", "toolgun.staffnv", function()
    if not nvOn() then return end
    local lift = nvCfg("nvLift")
    local boost = math.max(1, nvCfg("nvBoost"))
    cm["$pp_colour_addg"] = lift * gain
    cm["$pp_colour_colour"] = math.Clamp(nvCfg("nvColour"), 0, 1)
    cm["$pp_colour_brightness"] = lift * 0.5 * gain
    cm["$pp_colour_contrast"] = 1 + (boost - 1) * gain
    DrawColorModify(cm)
    -- The green: the screen times a pale green, so every hue stays put.
    local t = math.Clamp(nvCfg("nvTint"), 0, 1)
    if t <= 0 then return end
    cam.Start2D()
    render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD)
    draw.NoTexture()
    local o = 255 * (1 - t)
    surface.SetDrawColor(o, 255, o, 255)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    render.OverrideBlend(false)
    cam.End2D()
end)

--------------------------------------------------------------------------
-- Gathering (every 0.25 s): labels and X-ray lists
--------------------------------------------------------------------------

-- labels[i] = { ent, text, sub, kind, dist, h }, reused; nLabels in use.
local labels, nLabels = {}, 0
local cands, nCands = {}, 0      -- (pooled records, sorted by distance)
local pool = {}
local nextGather = 0
local visIn, visOut = { mask = MASK_OPAQUE, filter = {} }, {}
visIn.output = visOut

local function rec(i)
    local r = pool[i]
    if not r then r = {} pool[i] = r end
    return r
end

local function metres(d) return math.floor(d * M + 0.5) .. " m" end

local function shortModel(e)
    local mdl = e:GetModel()
    if not mdl or mdl == "" then return e:GetClass() end
    return string.StripExtension(string.GetFileFromFilename(mdl))
end

local function spawner(e)
    if e.CPPIGetOwner then
        local o = e:CPPIGetOwner()
        if IsValid(o) and o:IsPlayer() then return o:Nick() end
    end
    local by = e:GetNW2String("rhylib_spawnedBy", "")
    if by ~= "" then return by end
end

-- The X-ray kind of a non-player entity, or nil.
local function kindOf(e, c)
    if e.IsRhylibClone then return "clone" end
    if e.IsRhylibDroid then return "droid" end
    if c == "rhylib_objective" then return "obj" end
    if string.sub(c, 1, 14) == "rhylib_eod_bom" or string.sub(c, 1, 14) == "rhylib_eod_min" or string.sub(c, 1, 15) == "rhylib_rep_mine" then return "eod" end
    if e:IsNPC() or e:IsNextBot() then return "droid" end
    if e:GetNW2Bool("rhylib_toolSpawned", false) or e:GetNW2String("rhylib_spawnedBy", "") ~= "" then return "spawned" end
    if e.CPPIGetOwner and IsValid(e:CPPIGetOwner()) then return "spawned" end
end

local WANT = { player = cvPlayers, droid = cvNpcs, clone = cvNpcs, spawned = cvSpawned, eod = cvEod, obj = cvEod }

local function addCand(e, kind, d2, xray)
    nCands = nCands + 1
    local r = rec(nCands)
    r.ent, r.kind, r.d2, r.xray = e, kind, d2, xray
    cands[nCands] = r
end

local function byDist(a, b) return a.d2 < b.d2 end

local function gather(me)
    for i = 1, nCands do cands[i] = nil end
    nCands = 0
    local eye = me:EyePos()
    local xray = cvXray:GetBool()
    local range = math.Clamp(cvRange:GetFloat(), 10, 200) / M
    local range2, name2 = range * range, NAME_RANGE * NAME_RANGE
    local names = cvNames:GetBool()
    local S = Rhylib.State

    -- Players: X-ray within range, names when in sight within 60 m.
    for _, p in ipairs(player.GetAll()) do
        if p ~= me and p:Alive() and not p:IsDormant() and not p:GetNoDraw() and not (S and S.IsCloaked and S.IsCloaked(p)) then
            local d2 = eye:DistToSqr(p:GetPos())
            if xray and cvPlayers:GetBool() and d2 <= range2 then
                addCand(p, "player", d2, true)
            elseif names and d2 <= name2 then
                visIn.start, visIn.endpos = eye, p:EyePos()
                visIn.filter[1], visIn.filter[2] = me, p
                util.TraceLine(visIn)
                if not visOut.Hit then addCand(p, "player", d2, false) end
            end
        end
    end

    if xray then
        for _, e in ipairs(ents.FindInSphere(eye, range)) do
            if IsValid(e) and not e:IsPlayer() and not e:IsWeapon() and not e:IsDormant() and not e:GetNoDraw()
                and not IsValid(e:GetParent()) then
                local kind = kindOf(e, e:GetClass())
                if kind and WANT[kind]:GetBool() then addCand(e, kind, eye:DistToSqr(e:GetPos()), true) end
            end
        end
    end

    table.sort(cands, byDist)
    clearHalos()
    local haloed = 0
    nLabels = math.min(nCands, MAX_SHOWN)
    local BN = Rhylib.NW and Rhylib.NW.BATTALION
    for i = 1, nLabels do
        local r = cands[i]
        local e, kind = r.ent, r.kind
        local d = math.sqrt(r.d2)
        local L = labels[i]
        if not L then L = {} labels[i] = L end
        L.ent, L.kind, L.dist, L.far = e, kind, d, r.xray and range or NAME_RANGE
        L.h = e:OBBMaxs().z + 6
        if kind == "player" then
            L.text = e:Nick()
            local bn = BN and e:GetNW2String(BN, "") or ""
            L.sub = bn ~= "" and (bn .. " · " .. metres(d)) or metres(d)
        elseif kind == "obj" then
            local nm = e.GetBeaconName and e:GetBeaconName() or ""
            L.text = "OBJ " .. string.upper(nm ~= "" and nm or "marker") .. " · " .. metres(d)
            L.sub = nil
        elseif kind == "spawned" then
            local who = spawner(e)
            L.text = (e.PrintName and e.PrintName ~= "" and e.PrintName or shortModel(e)) .. " · " .. (who or metres(d))
            L.sub = nil
        else
            L.text = (e.PrintName and e.PrintName ~= "" and e.PrintName or e:GetClass()) .. " · " .. metres(d)
            L.sub = nil
        end
        if r.xray and haloed < MAX_HALO then
            haloed = haloed + 1
            local g = HALO[HALO_OF[kind]]
            g.n = g.n + 1
            g.list[g.n] = e
        end
    end
    for i = nLabels + 1, #labels do labels[i].ent = nil end
end

-- X-ray state for the server (sh_30_staffview.lua): on, range, kinds.
local function sendXray()
    if not IsValid(LocalPlayer()) then return end
    local bits = (cvPlayers:GetBool() and 1 or 0) + (cvNpcs:GetBool() and 2 or 0) + (cvSpawned:GetBool() and 4 or 0) + (cvEod:GetBool() and 8 or 0)
    Rhylib.Net.Start("tool.xray")
    net.WriteBool(cvXray:GetBool())
    net.WriteUInt(math.Clamp(math.floor(cvRange:GetFloat()), 10, 200), 8)
    net.WriteUInt(bits, 4)
    net.SendToServer()
end
local wasActive, nextResend = false, 0

Rhylib.Hook.Add("Think", "toolgun.staffview", function()
    if not active() then
        if nLabels > 0 then
            nLabels = 0
            clearHalos()
        end
        wasActive = false
        return
    end
    local now = RealTime()
    -- (the server's PVS spots: tell it again on drawing the toolgun and every 10 s)
    if cvXray:GetBool() and (not wasActive or now >= nextResend) then
        nextResend = now + 10
        sendXray()
    end
    wasActive = true
    if now < nextGather then return end
    nextGather = now + GATHER
    gather(LocalPlayer())
end)

-- One halo per colour, from the cached lists (soft: blur 2, one pass, through walls).
Rhylib.Hook.Add("PreDrawHalos", "toolgun.xray", function()
    if not (cvXray:GetBool() and active()) then return end
    for _, k in ipairs(HALO_ORDER) do
        local g = HALO[k]
        if g.n > 0 then halo.Add(g.list, g.col, 2, 2, 1, true, true) end
    end
end)

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

-- Text with a soft shadow; returns its width and height.
local function text(str, font, x, y, col, a, centre)
    surface.SetFont(font)
    local w, h = surface.GetTextSize(str)
    if centre then x = x - w * 0.5 end
    surface.SetTextColor(0, 0, 0, a * 0.8)
    surface.SetTextPos(x + 1, y + 1)
    surface.DrawText(str)
    surface.SetTextColor(col.r, col.g, col.b, a)
    surface.SetTextPos(x, y)
    surface.DrawText(str)
    return w, h
end

local tmp = Vector()
local function drawLabels(s)
    local W, H = ScrW(), ScrH()
    local fName, fSub, fTag = UI.Font(13, 700), UI.Font(11, 500), UI.Font(12, 700)
    for i = 1, nLabels do
        local L = labels[i]
        local e = L.ent
        if IsValid(e) then
            tmp:Set(e:GetPos())
            tmp.z = tmp.z + L.h
            local sp = tmp:ToScreen()
            if sp.visible and sp.x > -50 and sp.x < W + 50 and sp.y > -20 and sp.y < H + 20 then
                local a = 255 * math.Clamp(1 - (L.dist / L.far) * 0.6, 0.4, 1)
                local col = KIND[L.kind].label
                if L.sub then
                    local _, h = text(L.text, fName, sp.x, sp.y - 26 * s, col, a, true)
                    text(L.sub, fSub, sp.x, sp.y - 26 * s + h, COL_DIM, a, true)
                else
                    text(L.text, fTag, sp.x, sp.y - 16 * s, col, a, true)
                end
            end
        end
    end
end

-- Chips top left.
local xrText, xrRange = "X-RAY · 80 m", 80
local nvText, nvKey, nvKeyAt = "NIGHT VISION · F", "F", 0
local function chip(str, font, x, y, s, edge, col)
    surface.SetFont(font)
    local w, h = surface.GetTextSize(str)
    local px, py = math.floor(8 * s), math.floor(4 * s)
    local cw, ch = w + px * 2 + (edge and 2 or 0), h + py * 2
    surface.SetDrawColor(COL_PANEL)
    surface.DrawRect(x, y, cw, ch)
    surface.SetDrawColor(COL_EDGE)
    surface.DrawOutlinedRect(x, y, cw, ch)
    if edge then
        surface.SetDrawColor(edge)
        surface.DrawRect(x, y, math.max(2, math.floor(3 * s)), ch)
    end
    surface.SetTextColor(col.r, col.g, col.b, 255)
    surface.SetTextPos(x + px + (edge and 2 or 0), y + py)
    surface.DrawText(str)
    return cw
end

local function drawChips(s)
    local font = UI.Font(11, 700)
    local x, y, gap = math.floor(20 * s), math.floor(18 * s), math.floor(6 * s)
    x = x + chip("STAFF VIEW", font, x, y, s, nil, COL_TEXT) + gap
    local nv = nvOn()
    if RealTime() >= nvKeyAt then
        nvKeyAt = RealTime() + 2
        local k = input.LookupBinding("impulse 100")
        k = k and string.upper(k) or "F"
        if k ~= nvKey then nvKey, nvText = k, "NIGHT VISION · " .. k end
    end
    x = x + chip(nvText, font, x, y, s, nv and COL_NV or nil, nv and COL_NV_TEXT or COL_DIM) + gap
    local r = math.floor(math.Clamp(cvRange:GetFloat(), 10, 200))
    if r ~= xrRange then xrRange, xrText = r, "X-RAY · " .. r .. " m" end
    local xr = cvXray:GetBool()
    chip(xrText, font, x, y, s, xr and COL_XR or nil, xr and COL_XR_TEXT or COL_DIM)
end

-- Hotbar chips: rebuilt every 0.5 s from rhylib_hud's hotbar (or your
-- weapons by slot without it). chips[i] = { str, wep, overflow, empty }.
local chips, nChips, nextChips = {}, 0, 0
local fallback = {}
local function slotSort(a, b)
    local sa, sb = a:GetSlot(), b:GetSlot()
    if sa ~= sb then return sa < sb end
    return a:GetSlotPos() < b:GetSlotPos()
end
local function shortName(n)
    n = tostring(n or "")
    if #n > 12 then n = string.sub(n, 1, 11) .. "." end
    return n
end
local function buildChips(me)
    local HUD = Rhylib.HUD
    local entries = HUD and HUD.HotbarEntries and HUD.HotbarEntries()
    if not entries then
        for i = #fallback, 1, -1 do fallback[i] = nil end
        for _, w in ipairs(me:GetWeapons()) do
            if IsValid(w) then fallback[#fallback + 1] = w end
        end
        table.sort(fallback, slotSort)
    end
    local n = entries and #entries or #fallback
    for i = 1, n do
        local c = chips[i]
        if not c then c = {} chips[i] = c end
        if entries then
            local e = entries[i]
            c.wep, c.overflow, c.empty = e.wep, e.overflow, e.empty
            c.str = e.empty and tostring(e.key) or (tostring(e.key) .. "  " .. shortName(e.name))
        else
            local w = fallback[i]
            c.wep, c.overflow, c.empty = w, nil, false
            c.str = i .. "  " .. shortName(w:GetPrintName() or w:GetClass())
        end
    end
    for i = n + 1, #chips do chips[i].wep, chips[i].overflow = nil, nil end
    nChips = n
end

local function held(c, act)
    if c.wep ~= nil and c.wep == act then return true end
    if c.overflow then
        for _, w in ipairs(c.overflow) do
            if w == act then return true end
        end
    end
    return false
end

local hpStr, hpVal, apStr, apVal = "100", 100, "0", 0
local function drawBottom(me, s)
    local H = ScrH()
    local x, by = math.floor(20 * s), H - math.floor(20 * s)
    -- HP / AP
    local hp, ap = math.max(me:Health(), 0), math.max(me:Armor(), 0)
    local HUD = Rhylib.HUD
    local sim = HUD and HUD.SimHealth and HUD.SimHealth(me)   -- (training gun: sim health)
    if sim then hp = math.max(math.floor(sim), 0) end
    if hp ~= hpVal then hpVal, hpStr = hp, tostring(hp) end
    if ap ~= apVal then apVal, apStr = ap, tostring(ap) end
    local fB, fN = UI.Font(12, 700), UI.Font(12, 500)
    surface.SetFont(fB)
    local lw, lh = surface.GetTextSize("HP")
    local y1 = by - lh * 2 - math.floor(3 * s)
    text("HP", fB, x, y1, COL_HP, 255)
    local nw1 = text(hpStr, fN, x + lw + math.floor(5 * s), y1, COL_TEXT, 255)
    text("AP", fB, x, y1 + lh + math.floor(3 * s), COL_AP, 255)
    local nw2 = text(apStr, fN, x + lw + math.floor(5 * s), y1 + lh + math.floor(3 * s), COL_TEXT, 255)
    x = x + lw + math.floor(5 * s) + math.max(nw1, nw2) + math.floor(14 * s)

    -- Hotbar
    if RealTime() >= nextChips then
        nextChips = RealTime() + 0.5
        buildChips(me)
    end
    local act = me:GetActiveWeapon()
    local font = UI.Font(12, 600)
    surface.SetFont(font)
    local _, th = surface.GetTextSize("1")
    local px, py = math.floor(8 * s), math.floor(3 * s)
    local ch = th + py * 2
    local cy = by - ch
    for i = 1, nChips do
        local c = chips[i]
        if c.wep == nil or IsValid(c.wep) or c.empty then
            surface.SetFont(font)
            local w = surface.GetTextSize(c.str)
            local cw = w + px * 2
            local on = held(c, act)
            surface.SetDrawColor(on and COL_SLOT_ON or COL_SLOT)
            surface.DrawRect(x, cy, cw, ch)
            surface.SetDrawColor(on and COL_TEXT or COL_SLOT_EDGE)
            surface.DrawOutlinedRect(x, cy, cw, ch)
            local tc = on and COL_SLOT_ON_TEXT or COL_TEXT
            surface.SetTextColor(tc.r, tc.g, tc.b, c.empty and 140 or 255)
            surface.SetTextPos(x + px, cy + py)
            surface.DrawText(c.str)
            x = x + cw + math.floor(4 * s)
        end
    end
end

Rhylib.Hook.Add("HUDPaint", "toolgun.staffview", function()
    if not active() then return end
    local s = ScrH() / 1080
    if nLabels > 0 then drawLabels(s) end
    if cvMinHud:GetBool() then
        drawChips(s)
        drawBottom(LocalPlayer(), s)
    end
end)

-- Without rhylib_hud: the default health / armour / ammo boxes go too.
local DEFAULT_HUD = { CHudHealth = true, CHudBattery = true, CHudAmmo = true, CHudSecondaryAmmo = true }
Rhylib.Hook.Add("HUDShouldDraw", "toolgun.staffview", function(name)
    if DEFAULT_HUD[name] and cvMinHud:GetBool() and active() then return false end
end)

-- rhylib_hud: hide the normal HUD while the minimal one shows.
Rhylib.Hook.Add("Rhylib.HUDHide", "toolgun.staffview", function()
    if cvMinHud:GetBool() and active() then return true end
end)

--------------------------------------------------------------------------
-- X-ray on the server (PVS) and the !xray command
--------------------------------------------------------------------------

local function queueSend()
    if not IsValid(LocalPlayer()) then return end
    timer.Create("rhylib.toolgun.xraysend", 0.3, 1, sendXray)   -- (several changes: one message)
end
cvars.AddChangeCallback("rhylib_tool_xray", queueSend, "rhylib.toolgun.xray")
for _, n in ipairs({ "rhylib_tool_xray_range", "rhylib_tool_xray_players", "rhylib_tool_xray_npcs", "rhylib_tool_xray_spawned", "rhylib_tool_xray_eod" }) do
    cvars.AddChangeCallback(n, queueSend, "rhylib.toolgun.xray")
end
Rhylib.Hook.Add("InitPostEntity", "toolgun.xray", function()
    timer.Simple(5, function()
        if cvXray:GetBool() and IsValid(LocalPlayer()) then sendXray() end
    end)
end)

Rhylib.Net.Receive("tool.xray.flip", function()
    local on = not cvXray:GetBool()
    RunConsoleCommand("rhylib_tool_xray", on and "1" or "0")
    local r = math.floor(math.Clamp(cvRange:GetFloat(), 10, 200))
    Rhylib.Notify(nil, on and ("X-ray on (" .. r .. " m, toolgun out)") or "X-ray off", "info", "Toolgun")
end)
