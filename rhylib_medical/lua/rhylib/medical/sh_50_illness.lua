--[[
    Illness and medicine (shared): game masters infect players (rhylib_admin
    !infect, or the staff part of the interaction wheel); medics find out
    what it is and how bad, and dose the right medicine.

      1. Draw blood: the patient lies on a med sofa; a medic with a blood
         sample kit uses "Draw blood" on the interaction wheel. The labelled
         blood sample goes into the medic's inventory.
      2. Test strip: right-click the sample, "Apply to a test strip". The
         strip develops over stripMin-stripMax s (worse = sooner). control
         channel = the test works; the test channel's colour says the kind: blue viral
         (antiviral), green bacterial (antibiotics), purple poison
         (antidote), test channel dark = nothing. Medics see that someone is ill
         (injury panel), not what it is.
      3. Analyser (the chemistry bench, "Blood analyser" on the wheel or
         at the top of its menu): needs the sample and its developed
         strip. Gives the dose in units with an error band (Chemists:
         narrower band, faster). Samples and strips spoil after sampleLife.
      4. Dose: "Give medicine" on the wheel, pick the medicine and the units.
         Right dose = load / 5 units, within doseTolerance (15%).
         Too little: the load drops by what was given and keeps growing.
         Too much: cured, but hurt (health, blurred sight); over twice
         the right dose downs them. Wrong medicine: nothing but a mild
         side effect.

    Untreated (per kind, loads grow by loadRate per minute up to 100):
      viral       cough, slow drain to 50% health, stamina cap
      bacterial   the same, drains to 25%, a lower stamina cap
      poison      grows fastest; at 100 the patient goes down (load drops
                  back to poisonAfterDown so it can be treated)

    NW2Int rhylib_ill = kind (0-3) + stage (0-3) × 4 (stage from the load,
    for symptoms; the load itself stays on the server). NW2Float
    rhylib_overdose = until when sight is blurred.
]]

local Med = Rhylib.Medical
local Config = Rhylib.Config

Med.ILL_NONE, Med.ILL_VIRAL, Med.ILL_BACTERIAL, Med.ILL_POISON = 0, 1, 2, 3
Med.ILL = {
    [1] = { id = "viral", name = "Viral infection", medicine = "rhylib_antiviral", colour = "Blue", col = Color(90, 150, 255), floor = 0.5, stamina = 0.07 },
    [2] = { id = "bacterial", name = "Bacterial infection", medicine = "rhylib_antibiotics", colour = "Green", col = Color(90, 210, 110), floor = 0.25, stamina = 0.1 },
    [3] = { id = "poison", name = "Poisoning", medicine = "rhylib_antidote", colour = "Purple", col = Color(175, 95, 230), floor = 0, stamina = 0.12 },
}
Med.ILL_BY_ID = { viral = 1, bacterial = 2, poison = 3 }

Med.BLOOD_KIT = "rhylib_blood_kit"
Med.SAMPLE = "rhylib_blood_sample"
Med.STRIP = "rhylib_test_strip"
Med.CASSETTE = "rhylib_test_cassette"   -- (a strip with a sample on it, developing)

Config.Register("medical", "loadRate", { 0.5, 0.75, 1.5 }, "Illness: load gained per minute untreated (viral, bacterial, poison)")
Config.Register("medical", "illDrain", 2, "Illness: health lost per 30 s at the worst stage (less at lower stages)")
Config.Register("medical", "poisonAfterDown", 60, "Poison: load after it has downed the patient")
Config.Register("medical", "drawTime", 3, "Seconds to draw blood (Chemists: 2/3 of it)")
Config.Register("medical", "scanTime", 6, "Seconds an analyser takes per sample (Chemists: half)")
Config.Register("medical", "scanBand", 9, "Analyser error band (± load); Chemists get scanBandChemist")
Config.Register("medical", "scanBandChemist", 4, "Analyser error band for Chemists")
Config.Register("medical", "doseTime", 2, "Seconds to give a dose")
Config.Register("medical", "doseTolerance", 0.15, "How far off the right dose may be and still cure (share of it, at least 1 unit)")
Config.Register("medical", "stripMax", 120, "Test strip: seconds a light infection takes to show (a negative test also needs this long)")
Config.Register("medical", "stripMin", 30, "Test strip: seconds a severe infection takes to show")
Config.Register("medical", "sampleLife", 1800, "Seconds before a blood sample or used strip spoils and is thrown away")

function Med.IllState(ply)
    if Med.Simple() then return 0, 0 end   -- (simplified medical system: no illness)
    local v = ply:GetNW2Int("rhylib_ill", 0)
    return v % 4, math.floor(v / 4)   -- kind, stage
end

function Med.Overdosed(ply)
    return ply:GetNW2Float("rhylib_overdose", 0) > CurTime()
end

-- Stamina cap from illness (multiplied into Med.StaminaCap).
function Med.IllStaminaMult(ply)
    local kind, stage = Med.IllState(ply)
    local k = Med.ILL[kind]
    if not k then return 1 end
    return 1 - stage * k.stamina
end

local function registerItems()
    local Items = Rhylib.Items
    if not (Items and Items.Register) then return end
    Items.Register(Med.BLOOD_KIT, {
        name = "Blood sample kit", desc = "Medics: draw blood from a patient lying on a med sofa (interaction wheel)",
        w = 1, h = 1, stack = 5, weight = 0.1, category = "medical", model = "models/healthvial.mdl",
    })
    Items.Register(Med.SAMPLE, {
        name = "Blood sample", desc = "Put it in an analyser, then test it on a strip (right-click)",
        w = 1, h = 1, stack = 1, weight = 0.05, category = "medical", model = "models/healthvial.mdl", note = true,
    })
    Items.Register(Med.CASSETTE, {
        name = "Test strip (used)", desc = "Right-click: look at the result. Keep it with its blood sample for the analyser",
        w = 1, h = 1, stack = 1, weight = 0.02, category = "medical", model = "models/props_lab/clipboard.mdl", note = true,
    })
    Items.Register(Med.STRIP, {
        name = "Test strip", desc = "Right-click a blood sample to use one. Control lights = the test works; the test channel lights when infected (blue viral · green bacterial · purple poison)",
        w = 1, h = 1, stack = 10, weight = 0.02, category = "medical", model = "models/props_lab/clipboard.mdl",
    })
    -- Medicines are counted in units (a stack is 20).
    for _, m in ipairs(Med.MEDICINES) do
        local def = Items.Get(m[1])
        if def then def.stack = 20 end
    end
end
registerItems()
