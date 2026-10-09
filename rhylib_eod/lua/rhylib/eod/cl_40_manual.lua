--[[
    The bomb manual: a datapad tab (rhylib_datapad) for players with the
    Field technician skill "Bomb manual". Rules, probe readings, the safe
    order, every safeguard and module, the logic chip table and the
    interference device. Built from the shared tables, so it never
    disagrees with the game.
]]

local E = Rhylib.EOD

local function hasManual()
    return E.Skill(LocalPlayer(), "eod_manual")
end

local MODULE_HOW = {
    fuse = "Every cut and jumper heats the board; past 100° it fires. Pause between steps, it cools by itself.",
    stab = "After the detonator line is cut, inject exactly the dose printed on the charge (slider, then Inject).",
    tilt = "Once the lid is off a level bubble drifts. Nudge it back to the middle (buttons or arrow keys). Cuts and jumpers jolt it.",
    sealed = "The detonator line runs under a welded plate. Torch it open in short bursts (it heats the board) before you can probe or cut that line.",
    relay = "Remote bombs only. The antenna, relay and trigger wires are armoured. Put a jumper from the relay to the dummy load: the remote can't reach the detonator any more. Never short the relay or jumper it to the detonator.",
    chip = "An LED blinks a code of short and long flashes. Set the four switches from the table below and press Enter before cutting the logic or detonator line.",
    liquid = "Kill every supply first, then open the drain valve while the needle is in the green band. Drain it before the detonator line.",
    fake = "A cover hides the real board. X-ray it (2 shots) to see the order, then cut the three mount wires in that order.",
}

local READINGS = {
    { "LIVE 9V", "Battery power on it. Cutting a live feed, timer or detonator line fires the bomb." },
    { "LIVE · CAP n%", "The capacitor is still holding charge (it drains about 15 s after the supply is cut, or short it)." },
    { "DEAD", "No power. Safe to cut, unless a safeguard says otherwise." },
    { "SIGNAL · f GHz / JAMMED", "Antenna lead to the receiver; the frequency for a tuned device. JAMMED = your device covers it." },
    { "MON · watching receiver", "Anti-jam monitor. Cut it first, then you may jam the bomb or cut the antenna." },
    { "LOOP 3V", "Collapse sense line. Cut it before any battery supply." },
    { "LOOP 5V", "Tamper loop. Cutting it halves the time left on a running timer." },
    { "LIVE 9V · SENSE", "Self-powered charge: it fires if the bomb loses power. Short the charge cell first (+ to −)." },
    { "LOGIC · pulsing", "Logic chip line: set the chip to safe mode first." },
    { "RELAY / TRIGGER · armoured", "Signal relay: redirect it into the dummy load." },
}

local ORDER = {
    "Walk in slowly (crouch for a sensitive sensor). Hold Inspect before anything else.",
    "Anti-jam? Don't jam it. No anti-jam? Place an interference device: wideband also blinds the motion sensor.",
    "Lid switch? Release the tab, then lift the lid.",
    "Probe every wire before cutting. Decoys read DEAD and do nothing.",
    "Cut MON (anti-jam) and the collapse sense line (LOOP 3V) if there are any.",
    "Self-powered charge? Short the charge cell (jumper its + to its −).",
    "Cut every battery supply (or short the batteries). A running timer stops.",
    "Capacitor? Wait until it reads under 5% or short it, then cut its feed.",
    "Handle the modules (chip, liquid, sealed plate, relay) as below.",
    "The detonator line must read DEAD. Cut it.",
    "Gas or virus charge? Seal the valve straight away. Stabiliser? Inject the dose.",
}

local function build(content, k)
    if not (k and IsValid(content)) then return end
    local s = k.S
    local C = k.C
    local sp = k.Scroll(content)
    sp:Dock(FILL)

    local function heading(t)
        local h = k.Heading(sp, t)
        h:Dock(TOP)
        h:DockMargin(0, s(10), s(8), s(4))
    end
    local function para(t, col)
        local l = k.Label(sp, t, 14, 400, col or C.text)
        l:Dock(TOP)
        l:DockMargin(0, 0, s(10), s(6))
    end
    local function pair(a, b, aw)
        local p = vgui.Create("DPanel", sp)
        p:Dock(TOP)
        p:DockMargin(0, 0, s(10), s(3))
        local l = k.Label(p, b, 13, 400, C.textDim)
        l:SetPos(aw or s(220), s(5))
        function p:PerformLayout(w)
            l:SetWide(w - (aw or s(220)) - s(8))
            l:SizeToContentsY()
            self:SetTall(math.max(s(26), l:GetTall() + s(10)))
        end
        function p:Paint(w, h)
            k.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText(a, k.Font(13, 700), s(8), s(13), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    heading("Bomb manual · Field technician")
    para("Every bomb is a small circuit. Learn the rules and any board can be read: the colours change, the rules don't.", C.textDim)

    heading("Before you touch it")
    para("Motion sensors watch about 10 m around the bomb: walk, don't run (crouch-walk for a sensitive one). Hold Inspect first: it tells you the detonator, anti-jam, motion sensor, lid switch and charge. The Trained eye skill also names the battery, the board and the modules.")
    para("Tools come in the EOD kit: probe (reads a wire), wirecutters, jumper wires (join two terminals; a part's own + and − shorts it) and a torch.")

    heading("A safe order")
    for i, t in ipairs(ORDER) do pair(i .. ".", t, s(40)) end

    heading("Probe readings")
    for _, r in ipairs(READINGS) do pair(r[1], r[2]) end

    heading("Safeguards")
    pair("Anti-jam", "Fires if its remote signal is lost: jamming it or cutting the antenna. Cut MON first.")
    pair("Motion sensor", "Fires on fast movement within ~10 m. A wideband interference device blinds it.")
    pair("Lid switch", "Fires if the lid comes off with the tab still in. Release the tab first.")
    pair("Collapse circuit", "Fires if a battery supply is cut or shorted while armed. Cut LOOP 3V first.")
    pair("Capacitor", "Keeps the detonator live ~15 s after the supply is cut. Wait or short it (only once the supply is dead).")
    pair("Timer", "Starts when someone comes close. Cutting the power stops it; the tamper loop halves it.")
    pair("Remote", "A spotter can send the signal any time. Jam it (no anti-jam), cut the antenna, or redirect a relay.")

    heading("Modules")
    for _, m in ipairs(E.MODS) do pair(m.name .. " · rank " .. m.rank, MODULE_HOW[m.id] or "") end

    heading("Logic chip codes")
    para("· short flash   — long flash. Switches left to right.", C.textDim)
    for _, c in ipairs(E.CHIP_CODES) do pair(E.ChipText(c[1]), c[2]) end

    heading("Interference device")
    para("Place it from your inventory (right-click). Wideband blocks every remote signal and blinds motion sensors in its circle, but also jams your own radio and compass there. Tuned blocks one frequency (read it with the probe or the scanner), lasts four times longer and leaves your radio alone; a hopping receiver jumps away from it every ~25 s.")
    for _, r in ipairs({ 3, 5, 8, 10, 15 }) do
        local wide = E.CellLife(r, false, false)
        local tuned = E.CellLife(r, true, false)
        pair(r .. " m", string.format("wideband %s · tuned %s per cell", string.FormattedTime(wide, "%02i:%02i"), string.FormattedTime(tuned, "%02i:%02i")), s(80))
    end

    heading("Mines")
    para("Mines sit half buried and are hard to see: only a few metres off (Trained eye: further), unless someone marked them or a scanner shows them. AP mines need one safety pin, LAP (large) mines two and blast much wider.")
    pair("It clicked", "Freeze. Moving, jumping or stepping off sets it off. Call EOD.")
    pair("Dig", "With an EOD kit: E on the mine, hold Dig until the fuse shows.")
    pair("Pin", "Push the safety pin (Space) while the needle is inside the green zone. A wrong push sets it off. Steady hands widens the zone.")
    pair("Lift", "Once pinned it's safe: whoever stood on it can step off. Hold Lift to take it away.")
    pair("Scanner", "LMB switches the beam on; mines in it are outlined and it beeps faster as you close in. RMB marks the mine nearest your crosshair for everyone (a red flag).")
    pair("Clearing", "Grenades and other blasts set mines off from a distance, and so does shooting one you can see. Mines close together set each other off.")

    heading("Last resort")
    para("A droid popper's EMP has about a 1 in 10 chance to fry a bomb. Don't count on it.")

    heading("Why bombs go off")
    for _, key in ipairs({ "motion", "antijam", "lid", "collapse", "feed", "det", "sensor", "capshort", "jumpdet", "relayshort", "tilt", "heat", "chip", "liquid", "fake", "stab", "leak" }) do
        local c = E.CAUSES[key]
        if c then pair(c[1], c[3]) end
    end
end

-- Datapad hooks (rhylib_datapad's TABS entry "eod" calls these).
local function hook()
    local D = Rhylib.Datapad
    if not D then return end
    D.EodManualBuild = build
    D.HasEodManual = hasManual
end
hook()
Rhylib.Hook.Add("InitPostEntity", "eod.manual", hook)
Rhylib.Hook.Add("Rhylib.ModuleLoaded", "eod.manual", function(id) if id == "datapad" then hook() end end)
