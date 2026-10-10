# rhylib_medical: Downing, injuries, medics and illness

Players go down at 0 HP instead of dying. A downed player lies on the ground with a bleed-out timer; anyone can
stabilise them (pauses the timer) or drag them to cover, and medics revive them with a kit. On top of that every
player has six body parts that take damage, bleed, break and burn, with real effects (no sprinting, no aiming, more
spread, less stamina); the H menu shows them and you treat a part by dragging a kit or field item onto it. Medics get
a med bay (bacta tank, chemistry bench, med sofa) and an illness system that staff start: medics draw blood, read a
test strip, analyse the sample and give the right dose of the right medicine. Server owners can switch the whole
injury/illness side off with one setting (the simplified medical system) and keep only downing and plain healing.
It also ships two test dummies (bot players) for trying weapons and medical tools.

## Requirements

- **Required:** `rhylib_core` (it also provides the lying ragdoll bodies the downed state and the med sofa use).
- **Works better with** (all optional; the addon checks for each):
  - `rhylib_inventory`: kits and field items as inventory items, first aid kit charge, stacks, the chemistry
    bench and the whole illness flow (blood kits, samples, strips, medicines). Without it kits are plain weapons
    and the bench / illness steps say they need it.
  - `rhylib_menus`: the interaction wheel (E on a player), the analyser / test strip / dose windows, the injury
    key in Settings, Esc closing windows. Without it E on a downed player opens a small menu instead.
  - `rhylib_skills`: the medic skills (Combat medic and Chemist paths). Without it no skill applies.
  - `rhylib_armoury` (medic gear and medical crates), `rhylib_hud` (plates in the house style),
    `rhylib_admin` (`!infect`, `!cure`, `!heal`, buddha), `rhylib_datapad` (the medical holotable also makes a
    med bay, stats count revives and heals), `rhylib_weapons` / `rhylib_stamina` (read the injury effects).
- **Gamemode:** medics are DarkRP jobs with `medic = true` (other gamemodes can answer the `Rhylib.IsMedic` hook).
- **Content:** sounds `weapons/2misc_non_guns/use_bacta.ogg` and `sw_syringe.ogg` come from the Star Wars shared
  resources pack (silent without it). Default models: bacta tank `models/props/cydi/bactatank1.mdl`, chemistry bench
  `models/fyu/cedi/misc/v4/misc_30.mdl`, med sofa `models/reizer_props/.../med_sofa_01.mdl`, test dummy
  `models/ct_trp/pm_ct_trp.mdl`. The tank, bench and sofa fall back to HL2 props (fridge, table, couch) when their
  model is missing.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_medical.lua` | shared | Loader: `Rhylib.LoadModule("medical")`. |
| `lua/rhylib/medical/sh_00_config.lua` | shared | Most config keys, action ids (`A_*`), item ids, plain medical items and medicines, the simplified-system switch, item stack and item-disabled hooks, state readers (`IsDown`, `TimeLeft`, `Action`, `IsMedic`, `FindDowned` ...). |
| `lua/rhylib/medical/sh_10_move.lua` | shared | Movement while downed / dragging / helping (predicted), giving up, dragging the body, the lying pose. |
| `lua/rhylib/medical/sv_10_downed.lua` | server | Going down at 0 HP, grace time, bleeding out, `Med.Down` / `Revive` / `GiveUp`, dragging, the 0.1 s check loop, `med.note`. |
| `lua/rhylib/medical/sv_20_actions.lua` | server | Every timed action (stabilise, revives, heals, part treatment, blood pack): checks, durations, kits and charge, effects, `med.act`, `med.open`. |
| `lua/rhylib/medical/sh_30_injuries.lua` | shared | Injury config, body parts, effect checks (`NoSprint`, `CanAim`, `SpreadPenalty`, `StaminaCap` ...), leg limiter, the `med.inj` wire format. |
| `lua/rhylib/medical/sv_30_injuries.lua` | server | Damage to body parts, bleeding and recovery timers, the Recovery skill, H menu treatments (`med.treat`), sending injuries, bacta tank healing step. |
| `lua/rhylib/medical/sh_40_medbay.lua` | shared | `Med.InTank`, `Med.OnSofa`, no input while in a tank or on a sofa. |
| `lua/rhylib/medical/sv_40_medbay.lua` | server | Bacta tank, chemistry bench crafting, med sofa, saving placements (`rhylib_medical_save`). |
| `lua/rhylib/medical/sh_50_illness.lua` | shared | Illness kinds, illness config, `IllState`, blood kit / sample / strip items. |
| `lua/rhylib/medical/sv_50_illness.lua` | server | Infections and symptoms, drawing blood, the analyser, test strips, dosing, saving illnesses. |
| `lua/rhylib/medical/cl_10_hud.lua` | client | Downed screen, helper progress, "being treated", markers over downed players, E menu and wheel options. |
| `lua/rhylib/medical/cl_30_injuries.lua` | client | The H injury window (body picture, effects, drag items onto parts). |
| `lua/rhylib/medical/cl_40_medbay.lua` | client | Bench menu, mixing bar, bacta tank screen and tint, floating labels. |
| `lua/rhylib/medical/cl_50_illness.lua` | client | Illness screen effects, analyser window, test strip window, dose window, wheel and item menu options. |
| `lua/weapons/rhylib_med_base.lua` | shared | Base for the kit weapons (click goes to `Med.UseKit`, HUD hint). |
| `lua/weapons/rhylib_medkit.lua` | shared | Medkit. |
| `lua/weapons/rhylib_firstaid.lua` | shared | First aid kit (medics, holds a charge). |
| `lua/weapons/rhylib_revivekit.lua` | shared | Revive kit (medics). |
| `lua/entities/rhylib_bacta_tank.lua` | shared | Bacta tank entity. |
| `lua/entities/rhylib_chem_bench.lua` | shared | Chemistry bench / blood analyser entity. |
| `lua/entities/rhylib_med_sofa.lua` | shared | Med sofa entity. |
| `lua/entities/rhylib_test_dummy.lua` | shared | Test dummy: a bot player held on an invisible marker, with damage numbers. |
| `lua/entities/rhylib_test_dummy_tough.lua` | shared | Test dummy that takes no damage (only shows the numbers). |

## For server owners

### Settings

Config module `"medical"`. Change values in game on the Staff > Server settings page (superadmins), or in a host
config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("medical", "bleedTime", 90)
Rhylib.Config.Set("medical", "simplified", true)
```

Distances are in Source units (about 52 units = 1 m). Skill-related keys only matter with `rhylib_skills`.

**Downing and helping**

| Key | Default | What it does |
|---|---|---|
| `enabled` | `true` | Players go down at 0 HP instead of dying. |
| `bleedTime` | `120` | Seconds a downed player lasts before bleeding out. |
| `downHealth` | `50` | Health while downed; damage while down comes off this (simplified system: a percent of max health). |
| `downGrace` | `2` | Seconds after going down when the body takes no damage. |
| `giveUpTime` | `3` | Seconds of holding Jump to give up. |
| `range` | `90` | How close a helper must be (units). |
| `selfMult` | `2` | Treating yourself takes this many times longer. |
| `dragSpeed` | `100` | Top speed while dragging someone. |
| `dragLeash` | `45` | How far behind the dragger the body trails. |
| `dragWeapons` | `{ rhylib_stowed = true, keys = true }` | Weapon classes that count as empty hands for dragging. |
| `noTarget` | `true` | NPCs ignore downed players. |
| `downSequences` | `{ "death_04", "death_03", "death_02", "death_01", "zombie_slump_idle_02" }` | Lying poses to try; the first the model has wins (last frame is used). |
| `markerRange` | `2500` | Downed markers show within this distance. |
| `bloodPackTime` | `4` | Seconds to hook up a blood pack. |
| `bloodPackAdd` | `60` | Blood pack: seconds added to a downed player's bleed-out. |

**Kits**

| Key | Default | What it does |
|---|---|---|
| `reviveKitTime` | `5` | Seconds to revive with a revive kit. |
| `reviveKitHealth` | `1` | Health after a revive kit, as a share of max health. |
| `firstAidReviveTime` | `15` | Seconds to revive with a first aid kit. |
| `firstAidReviveHealth` | `30` | Health after a first aid revive (taken from the kit's charge). |
| `firstAidCharge` | `500` | Health a full first aid kit can heal before it's used up. |
| `firstAidMinCost` | `10` | Charge a first aid treatment always costs. |
| `firstAidHealTime` | `5` | Seconds to heal someone standing with a first aid kit. |
| `firstAidLimbTime` | `4` | Seconds to treat one body part with a first aid kit. |
| `firstAidLimbHealth` | `50` | Health a first aid kit gives when treating a body part. |
| `medkitHealTime` | `3` | Seconds for a medkit heal. |
| `medkitLimbTime` | `3` | Seconds for a medkit on one body part. |
| `medkitHeal` | `25` | Health a medkit gives (trooper). |
| `medkitHealMedic` | `50` | Health a medkit gives in a medic's hands. |
| `medkitLimbRepair` | `40` | Damage and burns a medic's medkit removes from a body part. |
| `medkitStack` | `3` | Medkits per stack for troopers. |
| `medkitStackMedic` | `5` | Medkits per stack for medics (at most 10). |
| `medkitMedicOnly` | `false` | Only medics can use medkits. |
| `splintTime` | `4` | Seconds to splint a fracture. |
| `burnGelTime` | `3` | Seconds to apply burn gel. |
| `burnGel` | `60` | Burns that burn gel removes. |
| `pillTime` | `1.5` | Seconds to give painkillers. |
| `painkillerTime` | `60` | Painkillers: seconds that hurt limbs and burns don't slow you. |

**Simplified medical system**

| Key | Default | What it does |
|---|---|---|
| `simplified` | `false` | No injuries, bleeding, illness, field items, H menu or chemistry; health reads as 0-100% of the job's max health. Downing, stabilising, dragging, reviving, the tank and sofa stay. Live: switching it on clears everyone's injuries and illnesses. |
| `simpleMedkit` | `0.3` | Share of max health a medkit heals. |
| `simpleFirstAidRevive` | `0.3` | Health after a first aid kit revive, as a share of max health. |
| `simpleFirstAidCharge` | `false` | First aid kits still spend their charge (off = never run out). |

In the simplified system a revive kit revives to full health, a first aid kit heals to full, hands-on revive reads
`handReviveHealth` as a percent, the bacta tank's `tankHeal` is a percent per second, and Recovery's `regenHealth`
is a percent.

**Injuries**

| Key | Default | What it does |
|---|---|---|
| `injuries` | `true` | Hits cause body part injuries. |
| `lightBleedAt` | `12` | A hit this strong (or more) starts light bleeding. |
| `heavyBleedAt` | `35` | A hit this strong (or more) starts heavy bleeding (a part at 80+ damage also bleeds heavily). |
| `lightBleed` | `0.4` | Health lost per second from each lightly bleeding part. |
| `heavyBleed` | `1.5` | Health lost per second from each heavily bleeding part. |
| `lightBleedStops` | `60` | Seconds before light bleeding stops by itself (heavy doesn't). |
| `fractureAt` | `30` | An arm or leg hit this strong (or more) breaks the bone. |
| `fallFractureAt` | `20` | Fall damage this high (or more) breaks a leg. |
| `recover` | `0.25` | Damage a part recovers per second by itself (only with no bleeding, fracture or burns). |
| `burnRecover` | `0.05` | Burns a part recovers per second by itself. |
| `legNoSprintAt` | `40` | Leg damage from which you can't sprint. |
| `fractureWalkMult` | `0.7` | Walk speed with a broken leg. |
| `armNoAimAt` | `40` | Arm damage from which you can't aim down sights. |
| `armSpread` | `0.8` | Extra spread at a fully hurt (or broken) arm, as a share of the weapon's resting cone. |
| `burnSpread` | `0.25` | Extra spread at full burns, as a share of the resting cone. |
| `torsoStaminaHit` | `0.8` | Stamina lost per point of torso damage taken. |
| `torsoStaminaCap` | `0.5` | Share of max stamina lost at a fully hurt torso. |
| `viewRange` | `120` | How close you must be to open someone's injury menu. |

**Medic skills** (rhylib_skills)

| Key | Default | What it does |
|---|---|---|
| `dragSpeedSkill` | `180` | Field drag: top speed while dragging. |
| `handReviveTime` | `25` | Hands-on revive: seconds. |
| `handReviveHealth` | `15` | Hands-on revive: health they get up with. |
| `steadyMult` | `0.85` | Steady hands: treatment time multiplier (not revives). |
| `quickReviveMult` | `0.8` | Quick revive: revive time multiplier. |
| `deepPockets` | `2` | Deep pockets: extra medkits per stack. |
| `efficientCare` | `0.67` | Efficient care: first aid charge used multiplier. |
| `triageFlash` | `30` | Triage: markers flash under this many seconds left. |
| `regenEvery` | `6` | Recovery: seconds between heals. |
| `regenHealth` | `4` | Recovery: health per heal. |
| `regenAffliction` | `4` | Recovery: damage and burns each body part loses per heal (bleeding also eases one step). |
| `tankSpecialist` | `300` | Bacta specialist: tanks within this range of you heal twice as fast. |

**Med bay**

| Key | Default | What it does |
|---|---|---|
| `medBayRange` | `400` | A med bay is this close to one of the `medBayClasses` entities. |
| `medBayClasses` | `{ "rhylib_bacta_tank", "rhylib_med_holotable" }` | Entities that make a med bay around them (the holotable is rhylib_datapad's). |
| `tankModel` | `"models/props/cydi/bactatank1.mdl"` | Bacta tank model (missing = a fridge). |
| `tankOffset` | `Vector(0, 0, 2)` | Where the occupant stands, from the bottom centre of the model. |
| `tankHeal` | `5` | Bacta tank: health per second. |
| `tankRepair` | `8` | Bacta tank: body part damage and burns healed per second. |
| `tankSetBones` | `8` | Bacta tank: seconds inside before fractures are set. |
| `sofaModel` | `"models/reizer_props/alysseum_project/medicine_obj/med_sofa_01/med_sofa_01.mdl"` | Med sofa model. |
| `sofaHeight` | `22` | Height of the lying surface above the model's bottom (only if the trace onto the model misses). |
| `sofaFlip` | `true` | Lay the head toward the other end. |
| `sofaDrop` | `1.5` | Gap between the body's lowest point and the surface (units). |
| `sofaSettle` | `1.5` | Seconds the arms, legs and head settle before the body freezes. |
| `sofaDamping` | `6` | How heavily the arms, legs and head are slowed while settling. |
| `benchModel` | `"models/fyu/cedi/misc/v4/misc_30.mdl"` | Chemistry bench model (missing = a table). |
| `craftTime` | `3` | Chemistry bench: seconds per batch. |
| `chemRecipes` | 10 recipes (below) | `{ item, medical supplies it takes, how many it makes (default 1) }`. At most 31 (5-bit index). |

Default recipes: burn gel 1, painkillers 1, splint 1, blood pack 2, medkit 2, blood sample kit 1 (makes 2),
test strip 1 (makes 3), antiviral 2 (makes 10), antibiotics 2 (makes 10), antidote 2 (makes 10).

**Illness**

| Key | Default | What it does |
|---|---|---|
| `loadRate` | `{ 0.5, 0.75, 1.5 }` | Load gained per minute untreated (viral, bacterial, poison). |
| `illDrain` | `2` | Health lost per 30 s at the worst stage (less at lower stages). |
| `poisonAfterDown` | `60` | Poison: load after it has downed the patient. |
| `drawTime` | `3` | Seconds to draw blood (Chemists: 2/3 of it). |
| `scanTime` | `6` | Seconds the analyser takes per sample (Chemists: half). |
| `scanBand` | `9` | Analyser error band (± load); Chemists get `scanBandChemist`. |
| `scanBandChemist` | `4` | Analyser error band for Chemists. |
| `doseTime` | `2` | Seconds to give a dose. |
| `doseTolerance` | `0.15` | How far off the right dose may be and still cure (share of it, at least 1 unit). |
| `stripMax` | `120` | Seconds a light infection's strip takes to show (a negative test also takes this long). |
| `stripMin` | `30` | Seconds a severe infection's strip takes to show. |
| `sampleLife` | `1800` | Seconds before a blood sample or used strip spoils. |

The model keys (`tankModel`, `sofaModel`, `benchModel`) are read when an entity spawns, so tanks, benches and sofas
already placed keep their old model until the map changes.

### Commands and permissions

| Command | Who | What it does |
|---|---|---|
| `rhylib_medical_save` (console) | permission `rhylib.medical.admin` (default admin), or the server console | Saves every permanent bacta tank, chemistry bench and med sofa on this map. |
| `rhylib_dummy_move still\|walk\|run` | admins, server console | All test dummies stand still, or walk / run back and forth. |
| `rhylib_injuries` (client console) | anyone | Opens or closes the injury menu (same as the H key). |
| `kill` (console) while downed | anyone | Gives up (dies, credited to whoever downed you). |
| `!infect <player> <viral\|bacterial\|poison> [load 1-100]`, `!cure`, `!heal` | staff (rhylib_admin) | Start or end an illness (`!heal` cures too). Also on the interaction wheel for staff. |

Players can't change job or enter vehicles while downed. Leaving the server while downed gives the kill to whoever
downed them.

### Placing things / saving

- Admins spawn the **Bacta tank**, **Chemistry bench**, **Med sofa**, **Test dummy** and **Test dummy (tough)** from
  the spawn menu category "Rhylib: Medical" (or the toolgun's Medical entries).
- Tanks, benches and sofas stay across map changes only when they are **permanent**: make them permanent with the
  toolgun's Permanent tool (Staff tools), or run `rhylib_medical_save`. They are saved per map in
  `Rhylib.Data` module `med_places` and come back 1 s after the map loads and after a map cleanup. `!cleanup`
  removes the ones that aren't permanent.
- A med bay is the area within `medBayRange` of a bacta tank or a medical holotable (rhylib_datapad). Only there (or
  with the Field surgeon skill) does a first aid kit fully set bones and heal burns.
- Test dummies are bot players: they need a multiplayer game with a free player slot and are not saved.

## For players (short)

| Key | What it does |
|---|---|
| (at 0 HP) | You go down. Wait for help, or hold **Jump** for 3 s to give up. |
| **E** on a downed player | Stabilise (anyone, pauses their timer) / revive with a kit (medics) / blood pack. Hold E on a standing player for the interaction wheel (Injuries, draw blood, give medicine). |
| Hold **left mouse** with empty hands on a downed player | Drag them; let go to drop. **Right mouse** while dragging: revive as you walk (Combat medic skill, needs a revive kit). |
| **H** | Injury menu: your body, or the player you look at. Drag a kit or field item from the right onto a body part. |
| Medkit / first aid kit: **LMB** someone, **RMB** yourself | Opens their / your injury menu (simplified system: heals straight away). First aid kit LMB on a downed player revives. |
| Revive kit: **LMB** on a downed player | Revive (medics). |
| Move keys, **Jump** or **E** during a treatment | Stops it. |
| **E** on a bacta tank / med sofa | Climb in / lie down; **Jump** or **E** gets out. |
| **E** on a chemistry bench | Blood analyser (medics) and crafting (Chemists). |
| Right-click a blood sample / used strip | Put it on a test strip, look at the result, throw it away. |

## For developers

The global table is `Rhylib.Medical` (`Med` below). Server state lives in `Med.down`, `Med.acts`, `Med.inj`,
`Med.ill`, `Med.crafting`; shared state is NW2 vars on the player:

| NW2 | On | Meaning |
|---|---|---|
| `rhylib_down` (Bool), `rhylib_downEnd`, `rhylib_downLeft` (Float), `rhylib_downYaw` (Float) | downed player | Downed; when the timer runs out; seconds left while paused; body yaw. |
| `rhylib_stabBy`, `rhylib_dragBy` (Entity) | downed player | Who holds the bleed-out pause; who drags them. |
| `rhylib_medAct` (Int), `rhylib_medT` (Entity), `rhylib_medS`, `rhylib_medE` (Float), `rhylib_medDrag` (Bool) | helper | Action `A_*`, target, start, end, reviving while dragging. |
| `rhylib_dragging` (Entity) | helper | The body being dragged. |
| `rhylib_healBy` (Entity) | patient | Who is treating them ("You are being treated"). |
| `rhylib_painkill` (Float) | player | Painkillers work until this time. |
| `rhylib_tank`, `rhylib_sofa` (Entity) | player | The tank they are in / sofa they lie on. |
| `rhylib_craftS`, `rhylib_craftE` (Float), `rhylib_craftN` (String) | Chemist | Mixing start, end, item name. |
| `rhylib_ill` (Int) | player | Illness kind + stage × 4 (the load stays on the server). |
| `rhylib_overdose` (Float) | player | Blurred sight until this time. |

`rhylib_afflMute` (Float, set by rhylib_skills' Field triage order) is read here: afflictions do nothing until then.

### Public functions

Shared:

- `Med.Cfg(key)` → value. A "medical" config value. `Med.Cfg("bleedTime")`
- `Med.Simple()` → bool. Simplified medical system on.
- `Med.IsDown(ply)` → bool. `if Rhylib.Medical.IsDown(ply) then return end`
- `Med.TimeLeft(ply)` → seconds of bleed-out left.
- `Med.StabilisedBy(ply)`, `Med.DraggedBy(ply)`, `Med.Dragging(ply)` → player or nil.
- `Med.Action(ply)` → `0`, or `kind, target, start, end` of the helper's action.
- `Med.IsMedic(ply)` → bool (DarkRP job `medic = true`, or the `Rhylib.IsMedic` hook).
- `Med.Skill(ply, id)` → bool. A medic skill that counts (needs rhylib_skills and a medic job).
- `Med.HealthPct(ply)` → 0-100. `Med.HoldingHands(ply)` → bool. `Med.BodyPos(ply)` → Vector.
- `Med.FindDowned(ply, list)` → the downed player ply aims at, or nil. `Med.FindStanding(ply)` → player or nil.
- `Med.InMedBay(ply)` → bool. `Med.InTank(ply)`, `Med.OnSofa(ply)` → entity or nil.
- `Med.Injuries(ply)` → `{ [limb] = { dmg, bleed, frac, splint, burn } }` or nil (client: only yours and the
  patient you view). `Med.Part(ply, limb)` → one part (never nil). Limbs: `Med.LIMBS`.
- `Med.NoSprint(ply)`, `Med.BrokenLeg(ply)`, `Med.CanAim(ply)` → bool; `Med.SpreadPenalty(ply, baseCone)` →
  degrees; `Med.StaminaCap(ply)` → 0-1; `Med.BleedLevel(ply)` → 0/1/2; `Med.Painkilled(ply)`, `Med.Muted(ply)` →
  bool.
- `Med.IllState(ply)` → kind, stage. `Med.IllStaminaMult(ply)` → 0-1. `Med.Overdosed(ply)` → bool.

Server:

- `Med.Down(ply, attacker, inflictor)`: down a living player. `Rhylib.Medical.Down(ply, ply, ply)` downs them "by
  themselves" (no frag for anyone else if they die).
- `Med.Revive(ply, health, by)`: get a downed player up. `Rhylib.Medical.Revive(ply, 30, medic)`
- `Med.GiveUp(ply)`: a downed player dies next tick.
- `Med.StartDrag(ply, target)`, `Med.StopDrag(ply)`.
- `Med.Start(helper, kind, target, opts)` → bool: start a timed action (checks everything, notes why not).
  `Rhylib.Medical.Start(ply, Rhylib.Medical.A_STAB, target)`
- `Med.Cancel(helper)`: stop helper's action.
- `Med.UseKit(ply, class, self)`: what a kit click does. `Med.DragRevive(ply, target)`.
- `Med.Has(ply, id)` → bool, `Med.Consume(ply, id)` → bool, `Med.KitCharge(ply)` → health,
  `Med.SpendCharge(ply, amount)`.
- `Med.Note(ply, text)`: short message under the crosshair. `Med.OpenMenuFor(ply, patient)`: open an injury menu.
- `Med.CanSee(helper, target)`, `Med.InRange(helper, target, slack)` → bool.
- `Med.MarkInjuries(ply)`: call after changing `Med.inj[ply]`. `Med.ClearInjuries(ply)`: heal every part.
- `Med.BleedRate(ply)` → health per second. `Med.CanFracture(ply, limb)` → bool.
- `Med.TreatPart(helper, patient, limb, kit)`: the effect of a part treatment.
- `Med.TankEnter / TankExit / TankUse`, `Med.TankTick(ply, dt, mult)`, `Med.BenchUse(bench, ply)`,
  `Med.SofaUse(sofa, ply)`, `Med.SofaUp(ply, quiet)`.
- `Med.Infect(ply, kind, load)` → bool, `Med.Cure(ply)`, `Med.Illness(ply)` → `{ kind, load }` or nil,
  `Med.ApplyDose(t, medId, units)` → `"cured"`, `"too little"`, `"too much"` or `"no effect"`.
- `Med.FindCassette(ply, key)`, `Med.SpoilSamples()`, `Med.AnalyserUse(ent, ply)`.

Client:

- `Med.OpenInjuries(target)` / `Med.ToggleInjuries()`: the injury window.
- `Med.ShowNote(text)`: a note under the crosshair.
- `Med.OpenAnalyser(bench)`, `Med.LooksIll(ply)` → bool, `Med.IllSigns(ply)` → text, stage.
- `Med.DrawEntLabel(ent, title, sub)`: floating label (call from `ENT:Draw`).

### Hooks

Fired by this addon:

| Hook | When | Return value |
|---|---|---|
| `Rhylib.PlayerDowned(ply, attacker)` | A player went down. | Ignored. |
| `Rhylib.PlayerRevived(ply, by)` | A downed player got up (`by` may be nil). | Ignored. |
| `Rhylib.PlayerHealed(patient, helper)` | A heal or part treatment finished. | Ignored. |
| `Rhylib.IsMedic(ply)` | Every medic check (shared). | true / false decides; nil = DarkRP job flag. |
| `Rhylib.CanFracture(ply, limb)` | A bone would break. | false = it doesn't. |
| `Rhylib.FractureChance(ply, limb)` | A bone would break. | 0-1 chance it does (rhylib_gear's kama). |
| `Rhylib.BlastPartMult(ply, limb)` | Blast damage spread over the body. | Multiplier for that part. |

Answered by this addon: `Rhylib.ItemStack(def, ply)` (medkit stack size), `Rhylib.ItemDisabled(id)` (hardcore
items in the simplified system), `Rhylib.ConfigChanged` (switching `simplified` on), and on the client
`Rhylib.WheelOptions`, `Rhylib.WheelEntityOptions` (the bench) and `Rhylib.ItemMenu` (samples and strips).

### Network messages

All names get the `rhylib.` prefix on the wire.

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `med.note` | server → player | string | Note under the crosshair. |
| `med.act` | client → server | kind 4 bits, target entity index 8 bits | Start an action on a downed player (E menu / wheel). |
| `med.open` | server → player | entity (NULL = own) | Open the injury menu (a kit click). |
| `med.inj` | server → owner + viewers | patient entity, 6 × (dmg 7, bleed 2, frac 1, splint 1, burn 7) | Injury state, on change, at most once a tick. |
| `med.view` | client → server | entity (NULL = closed) | Start / stop viewing someone's injuries. |
| `med.treat` | client → server | patient entity, part 3 bits, kind 3 bits | Treat a part with an item. |
| `chem.open` | server → player | bench entity, bool may craft | Bench menu. |
| `chem.use` | client → server | bench entity | Crafting from the wheel. |
| `chem.make` | client → server | bench entity, recipe index 5 bits | Mix one batch. |
| `ill.draw` | client → server | patient entity | Draw blood. |
| `ill.scan` | client → server | bench entity, sample uid | Analyse a sample. |
| `ill.strip` | client → server | sample uid | Put a sample on a test strip. |
| `ill.look` | client → server | used strip uid | Show its result again. |
| `ill.discard` | client → server | uid | Throw away a sample or used strip. |
| `ill.dose` | client → server | patient entity, medicine 2 bits, units 6 bits | Give medicine. |
| `ill.open` | server → player | entity | Open the analyser window. |
| `ill.cass` | server → player | uid, name, elapsed 16, develop time 10, kind 2, load 7 | Used strip window. |
| `ill.beep` | server → player | bool ready, name | Strip started / result ready. |
| `ill.stop` | server → player | uid (0 = draw or dose) | A timed illness step was cancelled. |
| `dummy.dmg` | server → players within 1500 | entity, damage 12 bits, head bool | Damage number over a test dummy. |

Uids use `Rhylib.Items.UID_BITS` (16 without rhylib_inventory).

### Saved data

| `Rhylib.Data` module / key | What's stored |
|---|---|
| `med_places` / `<map name>` | List of `{ class, pos = {x, y, z}, ang = {p, y, r} }` for permanent tanks, benches and sofas. |
| `med_ill` / `<SteamID64>` | `{ k = kind, l = load }`: an illness kept across leaving (never for bots). |

### Examples

React to downs and revives from your own addon:

```lua
Rhylib.Hook.Add("Rhylib.PlayerDowned", "myaddon.downed", function(ply, attacker)
    if IsValid(attacker) and attacker:IsPlayer() then
        print(attacker:Nick() .. " downed " .. ply:Nick())
    end
end)

Rhylib.Hook.Add("Rhylib.PlayerRevived", "myaddon.revived", function(ply, by)
    if IsValid(by) then by:ChatPrint("You got " .. ply:Nick() .. " back up") end
end)
```

Make a job count as a medic in a gamemode without DarkRP job flags:

```lua
hook.Add("Rhylib.IsMedic", "myaddon.medic", function(ply)
    if ply:Team() == TEAM_DOCTOR then return true end
end)
```

Stop bones breaking for players wearing your armour (shared or server):

```lua
Rhylib.Hook.Add("Rhylib.CanFracture", "myaddon.armour", function(ply, limb)
    if ply:GetNWBool("myaddon_heavyArmour") then return false end
end)
```

Heal and patch someone from a script (server), skipping the timed action:

```lua
local Med = Rhylib.Medical
if Med.IsDown(ply) then
    Med.Revive(ply, ply:GetMaxHealth(), nil)
end
Med.ClearInjuries(ply)
if Med.Cure then Med.Cure(ply) end
```

Add a recipe from a host config file (the whole list is replaced, so copy the defaults you want to keep):

```lua
Rhylib.Config.Set("medical", "chemRecipes", {
    { "rhylib_medkit", 2 }, { "rhylib_splint", 1 },
    { "rhylib_antidote", 2, 10 },
    { "my_stim_item", 3 },          -- an item your addon registers
})
```

## Notes and gotchas

- Downing works by cutting lethal damage to leave 1 HP (EntityTakeDamage priority 150, after armour at 100) and then
  downing in PostEntityTakeDamage. Damage another hook blocks never downs anyone. Bleed-out and giving up use
  `DMG_DIRECT` so they pass the grace time and blocks.
- While downed the player is hidden under a server ragdoll (rhylib_core Lying); hits on the ragdoll count as hits on
  the player. Armour is skipped while down.
- Injury state is only sent to the injured player and to players with their H menu open, so on a client
  `Med.Injuries` of anyone else is nil (reads as unhurt).
- The effect checks round damage up the same way the wire does, so server and client agree in predicted movement.
- `Med.Skill` only counts while the player is in a medic job, even if the skill is learned.
- Only one revive or treatment per patient at a time; stabilising can run alongside. A cancelled treatment adds the
  bleeding it held off, so starting and stopping a treatment can't stop bleeding.
- The 0.1 s check loop and the 1 s injury timer do nothing when nobody is down / injured, so they cost nothing on a
  quiet server.
- Medicines are 20 per stack (set in `sh_50_illness.lua`, over the 5 in `sh_00_config.lua`).
- The illness load never leaves the server; clients only see kind and stage. The 30 s illness timer and the
  symptoms stop in the simplified system, but saved illnesses of offline players are kept.
- Changing `tankModel`, `sofaModel` or `benchModel` needs a map change (or respawning the entities) for ones already
  placed.
