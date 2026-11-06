--[[
    Droids: lightweight NextBot enemies that fire real bolts (rhylib_weapons),
    so hits, hit markers and kill markers work like against players.

      B1 battle droid (rhylib_b1): b1Health health, E-5 blaster with red bolts,
      now and then a grenade at someone who just ducked behind cover.
      B1 variants (rhylib_b1_<variant>): aat, geonosis, marine, security,
      snow fight like a B1 (other model); heavy suppresses like a B2;
      commander has more health and makes droids near it aim better,
      react faster and pause less between bursts. Killing a commander
      rattles the droids near it for a few seconds.
      B2 super battle droid (rhylib_b2): tough and slow, a blaster in each
      arm firing without stopping, tighter the longer it stays on you
      (suppression; no rocket).
      B2 mortar (rhylib_b2_cannon, was "B2 cannon"): mainly a wrist rocket
      lobbed high over cover (purple blast); its blaster only at someone
      close (mortarSelfRange).
      B2 rocket droid (rhylib_b2_rocketdroid): same arm, but its rocket
      flies straight at you and dives into the floor just before you, so
      it works down hallways and indoors (needs sight of you); between
      rockets it suppresses like a B2 at half the rate.
      DSD1 dwarf spider droid (rhylib_spider, entities/rhylib_spider.lua):
      a four-legged walker as tough as a B2 (b2Health, same damage rules),
      slow, turns its body to its target and fires one explosive shell
      (rhylib_spider_shell: looks like a B1 bolt, spiderShellSize times
      as big, at the B1's bolt speed) every spiderShellInterval seconds
      at a target in sight, leading a moving one; backs off from anyone
      closer than spiderShellMin (fires anyway when it can't). Its head
      takes spiderHeadMult (rockets full). Model: spiderModel
      (models/macieg/starwars/spider.mdl, else the HL2 antlion).
      LM-432 crab droid (rhylib_crab, entities/rhylib_crab.lua): the
      spider's walker with two rapid-fire blasters (crabRPM without
      stopping), mostly near misses that walk round the target: it aims
      true at someone standing still in the open (crabStill*), charging
      it or very close (crabCharge*, crabCloseRange), and suppresses
      the spot it last saw someone in cover (crabSuppressTime).
      crabHealth, its armour by where a hit comes from: side plates take
      crabSideMult, front and back crabFrontMult, hits from above
      crabTopMult. Model: crabModel (placeholder HL2 headcrab).
      Spider and crab: a frag grenade going off right under one kills it
      (spiderBelly* / crabBelly*).
      Droideka (rhylib_droideka, entities/rhylib_droideka.lua): rolls
      fast with no shield (droidekaSpeed, droidekaHealth), stops and
      deploys (droidekaDeployTime): a shield bubble that stops bolts and
      blasts from outside, two arm blasters in bursts. Hit from inside
      the bubble x droidekaInsideMult; a frag grenade inside it, a direct
      rocket hit or a rocket blast at the bubble kills it; a droid popper
      drops the shield for
      droidekaShieldDownTime s. Model: droidekaModel.
      Training B1 / B2 (rhylib_b1_training, rhylib_b2_training): like the
      B1 and B2 with orange-yellow bolts that only take sim health
      (rhylib_training).
      BX commando droids (rhylib_bx_commando, entities/rhylib_bx_commando.lua):
      the B1 brain with b1Health x bxHealthMult, faster (bxSpeed,
      bxReaction); in a fight each takes its own angle round the target
      (flanking, surrounding, higher spots first) and now and then leaps
      up onto a roof or ledge (bxLeap*). Captain (rhylib_bx_captain):
      bxCaptainHealth, bxCaptainDamage, a commander that boosts only
      commandos (leads = "bx"). Training commando (rhylib_bx_training):
      training bolts. Models: bxModel, bxCaptainModel, bxTrainingModel.
      Fewer but tougher: B1s take cover when hit a few times
      (or suppressed), blind fire from it, and pull back once when badly
      hurt; B2s don't. Route and cover searches are spread over ticks
      (pathPerTick).
      Spots players in sight within range (checked a few times a second,
      not every tick), turns, fires in its kind's style (B1: fairly fast
      semi; clones: DC-15S full-auto runs with short random breaks and
      target switches, DC-15A slow aimed semi, Z-6 non-stop spray while
      standing; see ENT:StyleFire in rhylib_b1.lua), advances when
      far away, chases to where it last saw you, wanders near where it was
      spawned when idle. Walking needs a navmesh (nav_generate); without
      one droids stand and shoot.

    Spawn menu: NPCs tab, "Rhy's B1 battle droids", "Rhy's B2 super
    battle droids", "Rhy's Spider droids", "Rhy's Crab droids", "Rhy's Droidekas", "Rhy's Commando droids" and "Rhy's Training droids"
    (admins). Droids don't hurt each other. At most maxActive droids exist at once.

    Clone troopers (rhylib_ct_*, spawn menu "Rhy's Clone troopers"):
    friendly NPCs on the same brain that fight droids (sv_30_clones,
    entities/rhylib_clone.lua). Own cap cloneMax.

    This file (shared) holds: the Rhylib.Droids table (D), every config
    key, the model paths, D.KINDS (one row per NPC kind), D.CLASSES (kind
    -> entity class, also builds the spawn menu list), mode and
    aggression names, D.Aggro, D.Gun, the Server settings > Models entries
    and the player/clone no-collide rule. The brain is in
    entities/rhylib_b1.lua; server lists and caps in sv_10_droids, orders
    and markers in sv_20_orders, clones/presets/medics/artillery
    spotting/command wheel in sv_30_clones.

    Adding a kind: a D.KINDS row (below), a D.CLASSES entry, and a
    one-line entity file with ENT.Base = "rhylib_b1" (or "rhylib_clone")
    and ENT.DroidKind = "<kind>". See docs/addons/rhylib_droids.md.
]]

Rhylib.Droids = Rhylib.Droids or {}
local D = Rhylib.Droids
local Config = Rhylib.Config

Config.Register("droids", "maxActive", 100, "Most droids alive at once (more are removed when spawned)")
Config.Register("droids", "b1Health", 260, "B1 battle droid health")
Config.Register("droids", "b1Speed", 170, "B1 run speed")
Config.Register("droids", "b1Range", 3000, "How far a B1 sees and shoots")
Config.Register("droids", "b1Reaction", 0.7, "Seconds before a B1 starts firing at a new target")
Config.Register("droids", "e5Damage", 13, "E-5 damage per bolt")
Config.Register("droids", "e5RPM", 150, "B1 E-5: shots per minute (fairly fast semi)")
Config.Register("droids", "e5Spread", 1.2, "E-5 inaccuracy cone (degrees), more against moving targets")

Config.Register("droids", "b1NadeChance", 0.5, "B1: chance to throw a grenade at a target that just went behind cover")
Config.Register("droids", "b1NadeCooldown", 20, "B1: seconds between one droid's grenades")
Config.Register("droids", "b1NadeFightChance", 0.2, "B1: chance after each burst to throw a grenade at a target it can see (doubled at a group)")
Config.Register("droids", "b1NadeMin", 300, "B1: closest target it throws a grenade at")
Config.Register("droids", "b1NadeMax", 900, "B1: furthest target it throws a grenade at")
Config.Register("droids", "b1NadeDamage", 90, "B1 grenade: damage at the centre")
Config.Register("droids", "b1NadeRadius", 260, "B1 grenade: blast radius")

Config.Register("droids", "b2Health", 800, "B2 super battle droid health")
Config.Register("droids", "b2Speed", 115, "B2 walk speed")
Config.Register("droids", "b2Range", 2800, "How far a B2 sees and shoots")
Config.Register("droids", "b2Reaction", 0.9, "Seconds before a B2 starts firing at a new target")
Config.Register("droids", "b2Damage", 14, "B2 wrist blaster damage per bolt")
Config.Register("droids", "aquaModel", "models/wosha/aqua droid/aqua_droid.mdl", "Aqua droid model (a missing one falls back to the B2's)")
Config.Register("droids", "aquaHealth", 520, "Aqua droid health (twice the B1's default)")
Config.Register("droids", "aquaDamage", 40, "Aqua droid blaster damage per bolt")
Config.Register("droids", "aquaRPM", 60, "Aqua droid: shots per minute, fired without stopping (60 = one a second)")
Config.Register("droids", "aquaSpread", 1.2, "Aqua droid inaccuracy cone (degrees)")
Config.Register("droids", "b2RPM", 320, "B2 blasters (both arms): shots per minute, fired without stopping (suppression)")
Config.Register("droids", "b2cRPM", 300, "B2 mortar: blaster shots per minute (only at someone within mortarSelfRange)")
Config.Register("droids", "b2RocketRate", 0.5, "B2 rocket droid: blaster fire rate as a part of the B2's (b2RPM)")
Config.Register("droids", "mortarSelfRange", 700, "B2 mortar: it only uses its blaster on someone closer than this (units); further out only the mortar")
Config.Register("droids", "suppressRamp", 3, "B2 / heavy B1 suppression: seconds on the same target until their aim is fully settled")
Config.Register("droids", "suppressFrom", 1.5, "B2 / heavy B1 suppression: aim cone multiplier when they start on a target")
Config.Register("droids", "suppressTo", 0.6, "B2 / heavy B1 suppression: aim cone multiplier after suppressRamp seconds on the same target")
Config.Register("droids", "b2Spread", 1.8, "B2 inaccuracy cone (degrees), more against moving targets")
Config.Register("droids", "b2RocketDamage", 75, "B2 wrist rocket: damage at the centre")
Config.Register("droids", "b2RocketRadius", 230, "B2 wrist rocket: blast radius")
Config.Register("droids", "b2RocketCooldown", 9, "B2 wrist rocket: seconds between one droid's rockets")
Config.Register("droids", "b2RocketMin", 350, "B2 wrist rocket: closest target it fires at")
Config.Register("droids", "b2RocketMax", 2600, "B2 wrist rocket: furthest target it fires at")
Config.Register("droids", "b2RocketSpread", 70, "B2 wrist rocket: miss distance per 1000 units of range")
Config.Register("droids", "b2DirectSpeed", 1300, "B2 rocket droid: rocket speed (units/s)")
Config.Register("droids", "b2SlowTime", 1, "B2 rocket droid: seconds before the dive over which the rocket slows down")
Config.Register("droids", "b2SlowMult", 0.65, "B2 rocket droid: speed share it slows to by the dive (kept through the curve)")
Config.Register("droids", "b2DiveDist", 220, "B2 rocket droid: how far before its target the rocket starts curving down into the floor")
-- Command wheel (rhylib_skills, D.SquadOrder in sv_30_clones): the two
-- cmd* keys below. Then artillery (genuine artillery
-- to fight against): the mortar squad's mortars fire mostly rockets, at
-- anything any droid sees within artyRange, walking their shots in on a
-- target.
Config.Register("droids", "cmdFollowRadius", 900, "Command wheel Follow me: free clones this close join you")
Config.Register("droids", "cmdMaxFollowers", 8, "Command wheel: most clones following one commander")
Config.Register("droids", "artyRange", 8000, "Mortar squad artillery: how far its mortars fire (any droid spotting a target is enough)")
Config.Register("droids", "artyCooldown", 4.5, "Mortar squad artillery: seconds between one mortar's rockets")
Config.Register("droids", "artySpread", 35, "Mortar squad artillery: miss distance per 1000 units (tightens on repeated shots at one target)")
Config.Register("droids", "artyMaxFlight", 5.5, "Mortar squad artillery: longest rocket flight time (higher arcs at long range)")
Config.Register("droids", "artyBlasterRange", 1500, "Mortar squad artillery: closer than this it also uses its blaster (a lone B2 mortar: mortarSelfRange)")

-- DSD1 dwarf spider droid (rhylib_spider). Health is the B2's (b2Health).
Config.Register("droids", "spiderModel", "models/macieg/starwars/spider.mdl", "DSD1 dwarf spider droid model (a missing one falls back to the HL2 antlion)")
Config.Register("droids", "spiderScale", 0, "Spider droid: model size (0 = sized to spiderHeight)")
Config.Register("droids", "spiderHeight", 64, "Spider droid: body height (units): its hull, its eyes and, with spiderScale 0, the model's size")
Config.Register("droids", "spiderSeqIdle", "", "Spider droid: standing animation (sequence name; empty = found by itself)")
Config.Register("droids", "spiderSeqWalk", "", "Spider droid: walking animation (sequence name; empty = found by itself)")
Config.Register("droids", "spiderSeqRun", "", "Spider droid: running animation (sequence name; empty = found by itself)")
Config.Register("droids", "spiderMuzzleAttach", "", "Spider droid: model attachment the shells leave from (empty or missing = spiderMuzzleFwd / spiderMuzzleUp)")
Config.Register("droids", "spiderMuzzleFwd", 30, "Spider droid: shells leave this far in front of its centre (units)")
Config.Register("droids", "spiderMuzzleUp", 40, "Spider droid: shells leave this high above its feet (units)")
Config.Register("droids", "spiderSpeed", 95, "Spider droid: run speed")
Config.Register("droids", "spiderRange", 2800, "How far a spider droid sees and shoots")
Config.Register("droids", "spiderReaction", 0.9, "Seconds before a spider droid starts firing at a new target")
Config.Register("droids", "spiderTurnRate", 90, "Spider droid: how fast it turns its body (degrees per second)")
Config.Register("droids", "spiderAimCone", 12, "Spider droid: fires only once its body points this close to the target (degrees)")
Config.Register("droids", "spiderShellInterval", 4.6, "Spider droid: seconds between shells")
Config.Register("droids", "spiderShellDamage", 65, "Spider droid shell: blast damage at the centre")
Config.Register("droids", "spiderShellDirect", 60, "Spider droid shell: extra blast damage to what it hits")
Config.Register("droids", "spiderShellRadius", 110, "Spider droid shell: blast radius (units)")
Config.Register("droids", "spiderShellKnock", true, "Spider droid shell: can knock players down (only close to the impact, where the blast does weapons knockMin damage or more)")
Config.Register("droids", "spiderShellSize", 2, "Spider droid shell: size of its look as a multiple of a B1 blaster bolt (it flies at the B1's bolt speed, boltSpeed, times spiderShellSpeedMult)")
Config.Register("droids", "spiderShellSpeedMult", 0.85, "Spider droid shell: its speed as a multiple of the B1's bolt speed (0.85 = 15% slower)")
Config.Register("droids", "spiderShellSpread", 40, "Spider droid shell: miss distance per 1000 units of range")
Config.Register("droids", "spiderShellMin", 350, "Spider droid: closer than this it backs off before firing (cornered: fires anyway)")
Config.Register("droids", "spiderShellMax", 16, "Spider droid shells in flight at once, all spiders together")
Config.Register("droids", "spiderHeadMult", 0.4, "Spider droid: damage taken from hits on its head (rockets always full; a blaster head hit's own weapons headMult is taken out first)")
Config.Register("droids", "spiderHeadFwd", 0.4, "Spider droid: with no head hitbox hit, a hit further forward than this share of its hull's front half counts as its head")
Config.Register("droids", "spiderBellyKill", true, "Spider droid: a frag grenade going off right under it kills it outright")
Config.Register("droids", "spiderBellyRadius", 0.6, "Spider droid: under it = the grenade within this share of its hull half-width from its middle (horizontally)")
Config.Register("droids", "spiderBellyHeight", 0.35, "Spider droid: under it = the grenade no higher than this share of its hull height above its feet")

-- LM-432 crab droid (rhylib_crab).
Config.Register("droids", "crabModel", "models/funky/starwars/crab.mdl", "LM-432 crab droid model (a missing one falls back to the HL2 headcrab)")
Config.Register("droids", "crabScale", 0, "Crab droid: model size (0 = sized to crabHeight)")
Config.Register("droids", "crabHeight", 56, "Crab droid: body height (units): its hull, its eyes and, with crabScale 0, the model's size")
Config.Register("droids", "crabSeqIdle", "", "Crab droid: standing animation (sequence name; empty = found by itself)")
Config.Register("droids", "crabSeqWalk", "", "Crab droid: walking animation (sequence name; empty = found by itself)")
Config.Register("droids", "crabSeqRun", "", "Crab droid: running animation (sequence name; empty = found by itself)")
Config.Register("droids", "crabMuzzleLeft", "", "Crab droid: model attachment the left gun fires from (empty or missing = crabMuzzleFwd / Side / Up)")
Config.Register("droids", "crabMuzzleRight", "", "Crab droid: model attachment the right gun fires from (empty or missing = crabMuzzleFwd / Side / Up)")
Config.Register("droids", "crabMuzzleFwd", 28, "Crab droid: bolts leave this far in front of its centre (units)")
Config.Register("droids", "crabMuzzleSide", 16, "Crab droid: each gun this far left / right of its centre (units)")
Config.Register("droids", "crabMuzzleUp", 34, "Crab droid: bolts leave this high above its feet (units)")
Config.Register("droids", "crabHealth", 900, "Crab droid: health")
Config.Register("droids", "crabSpeed", 120, "Crab droid: run speed")
Config.Register("droids", "crabRange", 2400, "How far a crab droid sees and shoots")
Config.Register("droids", "crabReaction", 0.6, "Seconds before a crab droid starts firing at a new target")
Config.Register("droids", "crabTurnRate", 120, "Crab droid: how fast it turns its body (degrees per second)")
Config.Register("droids", "crabAimCone", 25, "Crab droid: fires only while its body points this close to the target (degrees)")
Config.Register("droids", "crabDamage", 11, "Crab droid: blaster damage per bolt")
Config.Register("droids", "crabRPM", 1560, "Crab droid: shots per minute, both guns together, fired without stopping")
Config.Register("droids", "crabSpread", 2.2, "Crab droid inaccuracy cone (degrees) of bolts aimed at the target, more against moving targets")
-- Crab aim: mostly near misses (a spot off the target's body that walks
-- round it), aimed true by chance (entities/rhylib_crab.lua).
Config.Register("droids", "crabMissMin", 40, "Crab droid near misses: closest they pass the target's body (units)")
Config.Register("droids", "crabMissMax", 90, "Crab droid near misses: furthest they pass the target's body (units)")
Config.Register("droids", "crabMissSpread", 0.35, "Crab droid near misses: aim cone multiplier on crabSpread (small keeps the stream tight)")
Config.Register("droids", "crabMissRepick", 0.9, "Crab droid near misses: seconds between new spots round the target (the stream walks there)")
Config.Register("droids", "crabMissWalk", 240, "Crab droid near misses: how fast the stream circles round the target to the new spot (degrees per second)")
Config.Register("droids", "crabBaseHit", 0.03, "Crab droid: share of bolts aimed true at a target in sight that is moving (strafing, dashing to cover)")
Config.Register("droids", "crabStillSpeed", 70, "Crab droid: a target slower than this (units/s) counts as standing still")
Config.Register("droids", "crabStillTime", 1.5, "Crab droid: seconds a target stands still in sight before it starts aiming true")
Config.Register("droids", "crabStillRamp", 2, "Crab droid: seconds over which the share aimed true at a target standing still rises to crabStillHit")
Config.Register("droids", "crabStillHit", 0.5, "Crab droid: share of bolts aimed true at a target standing still in sight (after crabStillTime + crabStillRamp)")
Config.Register("droids", "crabChargeSpeed", 120, "Crab droid: a target moving toward it at least this fast (units/s) is closing in")
Config.Register("droids", "crabChargeDist", 350, "Crab droid: units a target has to close in during one approach before it aims true (a short dash to cover stays under it)")
Config.Register("droids", "crabChargeGrace", 0.5, "Crab droid: seconds a target can stop closing in before its approach starts over")
Config.Register("droids", "crabChargeRange", 750, "Crab droid: a target closing in is only aimed at true within this range (units)")
Config.Register("droids", "crabCloseRange", 300, "Crab droid: anyone closer than this (units) is aimed at true at crabChargeHit")
Config.Register("droids", "crabChargeHit", 0.75, "Crab droid: share of bolts aimed true at a target charging it or closer than crabCloseRange")
Config.Register("droids", "crabSuppressTime", 4, "Crab droid: seconds after losing sight of a target it keeps firing near misses at the spot it last saw it (0 = stops at once)")
Config.Register("droids", "crabSideMult", 0.35, "Crab droid: damage taken from hits on its left or right side")
Config.Register("droids", "crabFrontMult", 0.7, "Crab droid: damage taken from hits on its front or back")
Config.Register("droids", "crabTopMult", 1.75, "Crab droid: damage taken from hits from above (its weak spot)")
Config.Register("droids", "crabTopAngle", 35, "Crab droid: a hit counts as from above when it comes from at least this steep above its middle (degrees)")
Config.Register("droids", "crabBellyKill", true, "Crab droid: a frag grenade going off right under it kills it outright (its armour never lowers that)")
Config.Register("droids", "crabBellyRadius", 0.6, "Crab droid: under it = the grenade within this share of its hull half-width from its middle (horizontally)")
Config.Register("droids", "crabBellyHeight", 0.35, "Crab droid: under it = the grenade no higher than this share of its hull height above its feet")

-- Droideka (rhylib_droideka).
Config.Register("droids", "droidekaModel", "models/crossline/player/droideka/cl_droideka.mdl", "Droideka model (a missing one falls back to the HL2 floor turret)")
Config.Register("droids", "droidekaScale", 1, "Droideka: model size")
Config.Register("droids", "droidekaHeight", 60, "Droideka: hull height (units), its eyes near the top")
Config.Register("droids", "droidekaSeqRoll", "", "Droideka: rolling animation (sequence name; empty = found by itself; none = drawn as a ball)")
Config.Register("droids", "droidekaSeqDeploy", "", "Droideka: unfolding animation (sequence name; empty = found by itself)")
Config.Register("droids", "droidekaSeqIdle", "", "Droideka: deployed standing animation (sequence name; empty = found by itself)")
Config.Register("droids", "droidekaSeqWalk", "", "Droideka: deployed crawling animation (sequence name; empty = found by itself)")
Config.Register("droids", "droidekaBallModel", "models/hunter/misc/sphere075x075.mdl", "Droideka: ball drawn while rolling when the model has no rolling animation")
Config.Register("droids", "droidekaBallRadius", 20, "Droideka: radius of that ball (units)")
Config.Register("droids", "droidekaMuzzleLeft", "", "Droideka: model attachment the left arm fires from (empty or missing = the model's left hand, else droidekaMuzzleFwd / Side / Up)")
Config.Register("droids", "droidekaMuzzleRight", "", "Droideka: model attachment the right arm fires from (empty or missing = the model's right hand, else droidekaMuzzleFwd / Side / Up)")
Config.Register("droids", "droidekaMuzzleFwd", 20, "Droideka: bolts leave this far in front of its centre (units)")
Config.Register("droids", "droidekaMuzzleSide", 12, "Droideka: each arm this far left / right of its centre (units)")
Config.Register("droids", "droidekaMuzzleUp", 36, "Droideka: bolts leave this high above its feet (units)")
Config.Register("droids", "droidekaHealth", 260, "Droideka: health (the same pool rolled and deployed)")
Config.Register("droids", "droidekaSpeed", 340, "Droideka: rolling speed")
Config.Register("droids", "droidekaWalkSpeed", 35, "Droideka: deployed crawling speed (side steps with the shield up)")
Config.Register("droids", "droidekaRange", 2600, "How far a droideka sees and shoots")
Config.Register("droids", "droidekaReaction", 0.6, "Seconds before a droideka starts firing at a new target")
Config.Register("droids", "droidekaDamage", 12, "Droideka: blaster damage per bolt")
Config.Register("droids", "droidekaRPM", 540, "Droideka: shots per minute within a burst, both arms together")
Config.Register("droids", "droidekaSpread", 1.6, "Droideka: inaccuracy cone (degrees), more against moving targets")
Config.Register("droids", "droidekaPause", 0.5, "Droideka: seconds between bursts")
Config.Register("droids", "droidekaDeployRange", 1300, "Droideka: further than this from its target it rolls closer (to 0.75 x this, 0.45 x at aggression 4-5) before deploying")
Config.Register("droids", "droidekaDeployTime", 1.2, "Droideka: seconds to deploy after it stops (no shield and no firing until then)")
Config.Register("droids", "droidekaRepositionMin", 10, "Droideka: fewest seconds deployed in a fight before it rolls a few metres to a new spot")
Config.Register("droids", "droidekaRepositionMax", 20, "Droideka: most seconds deployed in a fight before it rolls to a new spot (0 = never)")
Config.Register("droids", "droidekaShieldScale", 0.69, "Droideka shield: bubble radius as a multiple of the model bounds' half-diagonal")
Config.Register("droids", "droidekaShieldRadius", 0, "Droideka shield: bubble radius in units (0 = from the model, droidekaShieldScale)")
Config.Register("droids", "droidekaInsideMult", 1.3, "Droideka: damage multiplier on hits from someone inside its shield while it is up")
Config.Register("droids", "droidekaShieldDownTime", 5, "Droideka: seconds a droid popper's EMP keeps its shield down")

Config.Register("droids", "heavyHealth", 340, "B1 heavy: health")
Config.Register("droids", "heavySpeed", 140, "B1 heavy: run speed")
Config.Register("droids", "heavyRPM", 360, "B1 heavy: shots per minute, fired without stopping (suppression)")
Config.Register("droids", "heavySpread", 2.0, "B1 heavy: inaccuracy cone (degrees)")

Config.Register("droids", "cmdHealth", 480, "B1 commander: health")
Config.Register("droids", "cmdRadius", 800, "B1 commander: droids this close get the boost")
Config.Register("droids", "smokeSuppressors", 3, "Smoke: droids per commander that fire into smoke where they last saw their target (0 = none)")
Config.Register("droids", "smokeSuppressTime", 6, "Smoke: seconds a droid keeps firing into the smoke")
Config.Register("droids", "boltSpeed", 5200, "Droid blaster bolt speed (units/s); clones and players aren't affected")
Config.Register("droids", "cmdSpread", 0.7, "B1 commander boost: aim cone multiplier")
Config.Register("droids", "cmdReaction", 0.6, "B1 commander boost: reaction time multiplier")
Config.Register("droids", "blackoutReaction", 2, "EOD Signal blackout: droids' reaction time multiplier inside the bubble")
Config.Register("droids", "cmdPause", 0.6, "Commander boost: multiplier on the gap between shots and the breaks between runs (fires faster)")
Config.Register("droids", "cmdDeathTime", 6, "B1 commander killed: seconds nearby droids are rattled (0 = off)")
Config.Register("droids", "cmdDeathMult", 1.8, "B1 commander killed: aim cone multiplier while rattled")

-- BX commando droids (entities/rhylib_bx_commando.lua).
Config.Register("droids", "bxModel", "models/bx/npc_droid_cis_bx_h.mdl", "BX commando droid model (a missing one falls back to the B1's)")
Config.Register("droids", "bxCaptainModel", "models/bx_captain/npc_droid_cis_bx_cpt_h.mdl", "BX commando captain model (a missing one falls back to the B1's)")
Config.Register("droids", "bxTrainingModel", "models/bx_training/npc_droid_cis_bx_training_h.mdl", "BX training commando model (a missing one falls back to the B1's)")
Config.Register("droids", "bxSeqIdle", "", "BX commandos: standing animation (sequence name; empty = found by itself)")
Config.Register("droids", "bxSeqWalk", "", "BX commandos: walking animation (sequence name; empty = found by itself)")
Config.Register("droids", "bxSeqRun", "", "BX commandos: running animation (sequence name; empty = found by itself)")
Config.Register("droids", "bxSeqJump", "", "BX commandos: animation played during a leap (sequence name; empty = a jump activity if the model has one)")
Config.Register("droids", "bxHealthMult", 2, "BX commando (and training commando): health as a multiple of b1Health")
Config.Register("droids", "bxCaptainHealth", 800, "BX commando captain: health")
Config.Register("droids", "bxSpeed", 240, "BX commandos: run speed")
Config.Register("droids", "bxRange", 3000, "How far a BX commando sees and shoots")
Config.Register("droids", "bxReaction", 0.45, "Seconds before a BX commando starts firing at a new target")
Config.Register("droids", "bxDamage", 15, "BX commando: E-5 damage per bolt")
Config.Register("droids", "bxCaptainDamage", 20, "BX commando captain: E-5 damage per bolt")
Config.Register("droids", "bxRPM", 170, "BX commandos: shots per minute (semi)")
Config.Register("droids", "bxSpread", 1.0, "BX commandos: inaccuracy cone (degrees), more against moving targets")
Config.Register("droids", "bxFlankMin", 400, "BX commandos flanking: closest they take a spot round the target (units)")
Config.Register("droids", "bxFlankMax", 950, "BX commandos flanking: furthest they take a spot round the target (units)")
Config.Register("droids", "bxFlankRepick", 4, "BX commandos flanking: seconds between picking a new spot round the target")
Config.Register("droids", "bxLeapChance", 0.3, "BX commandos: chance, each time one picks a flanking spot, to look for a roof or ledge to leap up onto instead")
Config.Register("droids", "bxLeapCooldown", 18, "BX commandos: seconds between one commando's leaps")
Config.Register("droids", "bxLeapMinHeight", 90, "BX commando leap: lowest spot above it that counts (units)")
Config.Register("droids", "bxLeapMaxHeight", 320, "BX commando leap: highest spot above it it leaps to (units)")
Config.Register("droids", "bxLeapRange", 650, "BX commando leap: furthest it leaps sideways (units)")

Config.Register("droids", "moveSpread", 0.003, "Extra aim cone (degrees) per unit/s the target moves")
Config.Register("droids", "flashSuppress", 3, "Flash charge: droid aim cone multiplier while dazzled")
Config.Register("droids", "flashTime", 5, "Flash charge: seconds droids stay dazzled")

-- Smarter B1s (fewer but stronger droids): cover when
-- under fire, blind fire from it, pull back once when badly hurt. B2s
-- don't (they walk into fire). Needs a navmesh; without one they fight
-- in the open like before.
Config.Register("droids", "coverHits", 2, "B1: hits within coverWindow that send it to cover (Z-6 suppression and flash charges too)")
Config.Register("droids", "coverWindow", 2.5, "B1: seconds the hits are counted over")
Config.Register("droids", "coverTime", 4, "B1: seconds it stays in cover (blind firing) before fighting again")
Config.Register("droids", "coverCooldown", 8, "B1: seconds after leaving cover before it takes cover again")
Config.Register("droids", "coverRadius", 700, "B1: how far it looks for a cover spot")
Config.Register("droids", "coverWallTries", 6, "Cover: nearby spots tried beside walls and props (one trace each) besides the navmesh's hiding spots")
Config.Register("droids", "coverPeek", true, "Cover: from low cover it fires aimed bursts over it; from full cover clones step out to the side for an aimed burst now and then (droids only blind fire unless droidPeekOut)")
Config.Register("droids", "droidPeekOut", false, "Cover: droids also step out of full cover for aimed bursts (off: they only blind fire from it, clones step out)")
Config.Register("droids", "ctCoverHits", 1, "Clones: hits within coverWindow that send a clone to cover (droids use coverHits)")
Config.Register("droids", "ctBound", 3, "Clones: bounding overwatch at aggression 4 in a squad: half the squad moves while the other half crouches and fires, swapping every this many seconds (0 = off)")
Config.Register("droids", "coverFlankCheck", 1, "Cover: seconds between checks whether the enemy can see it in its spot (flanked: it finds another spot)")
Config.Register("droids", "squadSize", 8, "Squads: most NPCs in one squad when the toolgun places several or a preset squad (bigger groups become several squads)")
Config.Register("droids", "squadMax", 16, "Squads: most NPCs a GM can group into one squad in the toolgun's Command mode")
Config.Register("droids", "squadFormation", "box", "Squads: formation of new squads (box, wedge, line, column, spread); a preset squad placed in box keeps the block it was placed in")
Config.Meta("droids", "squadFormation", { options = { { "box", "Box" }, { "wedge", "Wedge" }, { "line", "Line" }, { "column", "Column" }, { "spread", "Spread" } } })
Config.Register("droids", "squadSpacing", 80, "Squads: units between neighbours in a formation")
Config.Register("droids", "squadGap", 50, "Squads: members keep at least this far from each other (units)")
Config.Register("droids", "squadCatchUp", 1.35, "Squads: speed multiplier for a member behind its slot")
Config.Register("droids", "squadWait", 260, "Squads: the leader slows down while a member is this far behind its slot (units)")
Config.Register("droids", "blindSpread", 4, "B1: aim cone multiplier when blind firing from cover")
Config.Register("droids", "retreatFrac", 0.35, "Health share below which a B1 pulls back once (0 = never)")
-- Peeking (5 B1s and a commander killed you before
-- you got 4 shots off): aim settles in after first sight, and big groups
-- focusing one player aim worse per extra shooter.
Config.Register("droids", "settleTime", 0.8, "Seconds after first seeing a target before a droid aims at its best")
Config.Register("droids", "settleMult", 1.6, "Aim cone multiplier at first sight (eases to 1 over settleTime)")
Config.Register("droids", "crowdFree", 3, "Droids that can fire at one player at full accuracy")
Config.Register("droids", "crowdMult", 0.12, "Extra aim cone per droid above crowdFree firing at the same player")
Config.Register("droids", "crowdMax", 1.4, "Most the crowd rule widens the aim cone (multiplier)")
-- Orders : modes per droid (guard / patrol /
-- attack), admin-only markers (attack here, defend this, fall back here)
-- and one aggression level for every droid that GMs turn up or down live.
Config.Register("droids", "aggression", 3, "Droid aggression 1-5: 1 retreat (withdraw from the enemy: run, turn and fire, run on; last stand when cornered), 2 fall back (to a fallback marker or their post while firing, then back off from anyone close, no pushing), 3 moderate (default), 4 march forward firing (charge when spread out or in tight spaces), 5 running charge. GMs change it live with !droidaggro or the toolgun")
Config.Meta("droids", "aggression", { options = { { 1, "1 · Retreat" }, { 2, "2 · Fall back" }, { 3, "3 · Moderate" }, { 4, "4 · March forward" }, { 5, "5 · Running charge" } } })
-- Retreat : mode "retreat" (toolgun order) and
-- aggression 1. Nowhere in particular, just away from the enemy.
Config.Register("droids", "retreatLeg", 550, "Retreat: how far each run away from the enemy goes before turning to fight")
Config.Register("droids", "retreatStand", 3.5, "Retreat: seconds it turns and fights between runs")
Config.Register("droids", "retreatClose", 350, "Retreat: an enemy this close makes it turn and fight instead of turning its back")
Config.Register("droids", "retreatClear", 15, "Retreat: seconds with no enemy seen or shooting before it stops and holds where it is")
Config.Register("droids", "retreatMax", 1500, "Retreat: with no enemy in sight it stops this far from where the retreat began (stays roughly in the same area)")
Config.Register("droids", "lastStandPause", 0.6, "Last stand (retreating with nowhere to go): pause between bursts multiplier")
Config.Register("droids", "walkMult", 0.5, "Walking (marching) speed as a share of a droid's run speed")
Config.Register("droids", "guardRadius", 700, "Guard mode: how far a droid fights away from its post")
Config.Register("droids", "patrolRadius", 2500, "Patrol mode: how far a patrol goes from where it was placed")
Config.Register("droids", "postRadius", 160, "Spread out / Defend 360 (Command mode): how far an NPC fights away from the spot it was given")
Config.Register("droids", "markerRadius", 2000, "Droids within this range of a new marker follow it (droids placed after it follow it too)")
Config.Register("droids", "brushRadius", 400, "Toolgun order brush: droids within this range of where you aim get the order")
Config.Register("droids", "marchGroup", 2, "Marching (aggression 4) needs this many other droids close by; fewer, or a tight space, means a charge")
Config.Register("droids", "runSpread", 1.4, "Aim cone multiplier while running")
Config.Register("droids", "walkSpread", 1.1, "Aim cone multiplier while walking")
Config.Register("droids", "pathPerTick", 4, "Most route and cover searches all droids start in one tick (spreads the cost)")

-- Clone troopers : friendly NPCs on the droid brain.
-- They fight droids, never hurt players (or get hurt by them), and the
-- Commander's Reinforcements skill calls a squad of them.
Config.Register("droids", "cloneMax", 40, "Most clone NPCs alive at once")
Config.Register("droids", "cloneAggro", 3, "Clone NPC aggression 1-5 (same scale as the droids'; 3 = moderate)")
Config.Meta("droids", "cloneAggro", { options = { { 1, "1 · Retreat" }, { 2, "2 · Fall back" }, { 3, "3 · Moderate" }, { 4, "4 · March forward" }, { 5, "5 · Running charge" } } })
Config.Register("droids", "cloneFollowRadius", 600, "Clones following an officer fight at most this far from them")
Config.Register("droids", "ctModel", "models/hazo/npc/ct_trp/npc_ct_trp_f.mdl", "Clone trooper NPC model (troopers, riflemen, heavies; the _h version works too)")
Config.Register("droids", "ctMedicModel", "models/hazo/npc/ct_medic/npc_ct_medic_f.mdl", "Clone medic NPC model")
Config.Register("droids", "ctCmdModel", "models/hazo/npc/ct_cmd/npc_ct_cmd_f.mdl", "Clone commander NPC model")
Config.Register("droids", "ctHealth", 300, "Clone trooper / rifleman / medic: health")
Config.Register("droids", "ctSpeed", 190, "Clone run speed")
Config.Register("droids", "ctRange", 3000, "How far a clone sees and shoots")
Config.Register("droids", "ctReaction", 0.35, "Seconds before a clone starts firing at a new target")
Config.Register("droids", "ctDamage", 18, "Clone DC-15S damage per bolt")
Config.Register("droids", "ctRPM", 360, "Clone DC-15S: shots per minute in its full-auto runs")
Config.Register("droids", "ctAutoPauseMin", 0.25, "Clone DC-15S: shortest break between full-auto runs (seconds)")
Config.Register("droids", "ctAutoPauseMax", 0.9, "Clone DC-15S: longest break between full-auto runs (seconds)")
Config.Register("droids", "ctSwitchChance", 0.35, "Clone DC-15S: chance after a run to switch to another enemy in sight")
Config.Register("droids", "ctSpread", 0.9, "Clone inaccuracy cone (degrees), more against moving targets")
Config.Register("droids", "ctRifleDamage", 30, "Clone rifleman / commander DC-15A damage per bolt")
Config.Register("droids", "ctRifleRPM", 100, "Clone rifleman / commander DC-15A: shots per minute (slow, aimed semi)")
Config.Register("droids", "ctHeavyHealth", 420, "Clone heavy: health")
Config.Register("droids", "ctHeavySpeed", 160, "Clone heavy: run speed")
Config.Register("droids", "ctHeavyDamage", 14, "Clone heavy Z-6 damage per bolt")
Config.Register("droids", "ctHeavyRPM", 900, "Clone heavy Z-6: shots per minute, sprayed without stopping (holds fire while moving unless assaulting)")
Config.Register("droids", "ctHeavySpread", 1.6, "Clone heavy inaccuracy cone (degrees)")
Config.Register("droids", "ctCmdHealth", 500, "Clone commander: health (boosts clones near it like a B1 commander boosts droids)")
Config.Register("droids", "ctMedicHeal", 2, "Clone medic: health a second for players and clones near it")
Config.Register("droids", "ctMedicRadius", 300, "Clone medic: healing radius")
Config.Register("droids", "ctPopperChance", 0.15, "Clone trooper: chance after each burst to throw a droid popper at a droid in sight (doubled at a group)")
Config.Register("droids", "ctPopperLobChance", 0.4, "Clone trooper: chance to throw a droid popper where a droid just went out of sight")
Config.Register("droids", "ctPopperCooldown", 30, "Clone trooper: seconds between one clone's droid poppers")
Config.Register("droids", "ctDownGuards", 2, "Clones that go and stand guard over a downed player (0 = off)")
Config.Register("droids", "ctMedicRepair", 4, "Clone medic: injury damage healed a second on each body part of players near it (bleeding stops first, then a broken bone is set (hardcore medical) or a limp ends; burns heal too)")
Config.Register("droids", "ctMedicReviveRadius", 1500, "Clone medic: goes to downed or just-dead players this close")
Config.Register("droids", "ctMedicReviveTime", 5, "Clone medic: seconds crouched on the body to get someone up")
Config.Register("droids", "ctMedicReviveHealth", 0.3, "Clone medic: share of max health a revived player gets up with")
-- Roam / patrol groups and calls for help (sv_40_squads), clone doctrine:
-- clones fall back when outnumbered, hold when even, charge when they
-- outnumber the droids, and crouch when there's no cover.
Config.Register("droids", "roamRadius", 4000, "Spread out (roam): how far one leg of a roam goes (roaming has no home: it carries on across the whole map)")
Config.Register("droids", "wanderClones", 2, "Roam and patrol: clones per group")
Config.Register("droids", "wanderDroids", 6, "Roam and patrol: droids per group (roaming droids left over make a group of 4 or 2; one left over goes alone)")
Config.Register("droids", "callRadius", 2000, "Droids: how far a droid's call for help reaches (idle roaming, patrolling and guarding groups answer)")
Config.Register("droids", "callHelpers", 10, "Droids: droids that come when one calls for help (whole groups, so it can be a few more)")
Config.Register("droids", "callCooldown", 12, "Droids: seconds between one droid group's calls for help")
Config.Register("droids", "ctCallRadius", 2000, "Clones: how far a clone's call for help reaches (idle roaming, patrolling and guarding groups answer)")
Config.Register("droids", "ctCallHelpers", 4, "Clones: clones that come when one calls for help (whole groups, so it can be one more)")
Config.Register("droids", "ctCallCooldown", 12, "Clones: seconds between one clone group's calls for help")
Config.Register("droids", "ctOddsFriends", 900, "Clones: friends (clones and players) this close count for the odds")
Config.Register("droids", "ctOddsEnemies", 1500, "Clones: droids this close count for the odds (B2s count double)")
Config.Register("droids", "ctFallBackOdds", 0.8, "Clones fall back when friends are fewer than this share of the enemies")
Config.Register("droids", "ctChargeOdds", 1.25, "Clones charge when friends are more than this many times the enemies (in between they hold the line)")
Config.Register("droids", "ctCrouchTime", 4, "Clones: seconds they crouch when hit with no cover to reach")
Config.Register("droids", "ctCrouchSpread", 0.8, "Clones: aim cone multiplier while crouched")
Config.Register("droids", "ctMedicShield", 0.8, "Clone medic: damage reduction while crouched reviving someone (0.8 = takes 20%)")
Config.Register("droids", "reviveShield", 0.6, "Players got up by a clone medic: damage reduction for reviveShieldTime (ends when they fire; an escape tool)")
Config.Register("droids", "reviveShieldTime", 5, "Players got up by a clone medic: seconds the damage reduction lasts")
Config.Register("droids", "ctDownRadius", 1500, "Clones this close to a downed player can be sent to guard them")

-- D.Cfg(key): shortcut for Rhylib.Config.Get("droids", key). Shared.
-- Example: local hp = Rhylib.Droids.Cfg("b1Health")
D.Cfg = Config.For and Config.For("droids") or function(k) return Config.Get("droids", k) end

D.B1_MODEL = "models/aussiwozzi/cgi/b1droids/b1_battledroid.mdl"   -- (same pack as the variants, B2s and training droids)
D.E5_MODEL = "models/jajoff/sps/cgiweapons/tc13j/e5.mdl"
D.E5_SOUND = "weapons/1misc_guns/wpn_btldroid_laser_shoot_01.ogg"
D.B2_SOUND = "weapons/1misc_guns/wpn_b2_btldroid_hvy_laser_shoot_01.ogg"

D.B2_MODEL = "models/aussiwozzi/cgi/b1droids/b2_battledroid.mdl"
D.B1T_MODEL = "models/aussiwozzi/cgi/b1droids/b1_battledroid_training.mdl"
D.B2T_MODEL = "models/aussiwozzi/cgi/b1droids/b2_battledroid_training.mdl"

--[[
    Droid kinds (ENT.DroidKind). Numbers are config keys. training: yellow
    bolts and blasts that only take sim health (rhylib_training), no kill
    credit. Training droids take normal damage (and training bolts).

    Fields of a row (all read by entities/rhylib_b1.lua):
      name        shown in the spawn menu and toolgun
      model       model path (a missing model falls back to the B1's;
                  clones to D.CLONE_FALLBACK)
      modelCfg    config key holding the model instead (clones)
      health, speed, range, reaction, damage, rpm, spread
                  config KEY names (strings), read when used, so a
                  Server settings change applies to new shots/spawns
      burst       { min, max } shots per burst (full-auto runs, cover bursts)
      style       how it fires in a fight (ENT:StyleFire): auto, semi,
                  spray, suppress or mortar (shell: the spider's own,
                  entities/rhylib_spider.lua); rateKey: config key of a fire
                  rate multiplier
      color       bolt colour index (rhylib_weapons BoltColor: 1 blue,
                  2 red, 8 training)
      gun         gun model drawn in the right hand (none: no prop, e.g. B2)
      sound, pitch  fire sound and pitch % (default D.E5_SOUND, 100)
      nades       throws B1 grenades     poppers  throws droid poppers (clones)
      cover       takes cover when hit   big      bigger hull and eye (B2s)
      dual        fires from both hands  rockets  B2 wrist rockets (mortar)
      direct      rockets fly level and dive (rocket droid; needs rockets)
      category    spawn menu category (none: by the kind's name)
      fallback    model when the row's model isn't installed (none: the B1's)
      labelZ      height of the stealth "?" / "!" over it (none: by big)
      commander   boosts its side within cmdRadius
      leads       (commanders) a field name: boosts only kinds with that
                  field set (bx_captain: "bx")
      healthMult  config key multiplying health (bx: bxHealthMult)
      bx          a BX commando (entities/rhylib_bx_commando.lua)
      medic       heals, treats and revives (clones)
      training    sim-only bolts and blasts, no kill credit
      side        "republic" = a clone (no side = droid)
]]
D.KINDS = {
    b1 = { name = "B1 battle droid", model = D.B1_MODEL, health = "b1Health", speed = "b1Speed", range = "b1Range", reaction = "b1Reaction",
        damage = "e5Damage", rpm = "e5RPM", spread = "e5Spread", burst = { 2, 3 }, color = 2, gun = D.E5_MODEL, nades = true, cover = true, style = "semi" },
    b2 = { name = "B2 super battle droid", model = D.B2_MODEL, health = "b2Health", speed = "b2Speed", range = "b2Range", reaction = "b2Reaction",
        damage = "b2Damage", rpm = "b2RPM", spread = "b2Spread", burst = { 5, 8 }, color = 2, big = true, dual = true, sound = D.B2_SOUND, style = "suppress" },
}

-- B1 variants: a B1 with another model, and a few changes.
-- variant(base, name, model, changes): a copy of D.KINDS[base] with a new
-- name and model (nil model keeps the base's) and the fields in changes.
local B1V = "models/aussiwozzi/cgi/b1droids/b1_battledroid_"
local function variant(base, name, model, changes)
    local k = table.Copy(D.KINDS[base])
    k.name, k.model = name, model
    for key, v in pairs(changes or {}) do k[key] = v end
    return k
end
D.KINDS.b1_aat = variant("b1", "B1 AAT crew droid", B1V .. "aat.mdl")
D.KINDS.b1_geonosis = variant("b1", "B1 Geonosis droid", B1V .. "geonosis.mdl")
D.KINDS.b1_marine = variant("b1", "B1 marine droid", B1V .. "marine.mdl")
D.KINDS.b1_security = variant("b1", "B1 security droid", B1V .. "security.mdl")
D.KINDS.b1_snow = variant("b1", "B1 snow droid", B1V .. "snow.mdl")
D.KINDS.b1_heavy = variant("b1", "B1 heavy droid", B1V .. "heavy.mdl",
    { health = "heavyHealth", speed = "heavySpeed", rpm = "heavyRPM", spread = "heavySpread", burst = { 6, 10 }, nades = false, style = "suppress" })
D.KINDS.b1_commander = variant("b1", "B1 commander droid", B1V .. "commander.mdl", { health = "cmdHealth", commander = true })
D.KINDS.b2_cannon = variant("b2", "B2 mortar droid", "models/aussiwozzi/cgi/b1droids/b2_battledroid_cannon.mdl",
    { rpm = "b2cRPM", burst = { 2, 4 }, dual = false, rockets = true, style = "mortar" })
-- (a level rocket that dives down just before you)
D.KINDS.b2_rocket = variant("b2", "B2 rocket droid", "models/aussiwozzi/cgi/b1droids/b2_battledroid_cannon.mdl",
    { rpm = "b2RPM", rateKey = "b2RocketRate", burst = { 2, 4 }, dual = false, rockets = true, direct = true, style = "suppress" })
-- (a B2 with one heavy shot a second and twice a B1's health)
D.KINDS.aqua = variant("b2", "Aqua droid", D.B2_MODEL,
    { modelCfg = "aquaModel", fallback = D.B2_MODEL, health = "aquaHealth", damage = "aquaDamage", rpm = "aquaRPM", spread = "aquaSpread", burst = { 1, 1 }, dual = false })

-- DSD1 dwarf spider droid: a B2's toughness (big, b2Health), its own
-- entity (rhylib_spider: shells, movement, animation). rpm / spread are
-- never used (it fires no bolts).
D.SPIDER_FALLBACK = "models/antlion.mdl"
D.KINDS.spider = { name = "DSD1 dwarf spider droid", modelCfg = "spiderModel", fallback = D.SPIDER_FALLBACK, health = "b2Health", speed = "spiderSpeed",
    range = "spiderRange", reaction = "spiderReaction", damage = "spiderShellDamage", rpm = "b2RPM", spread = "b2Spread", burst = { 1, 1 }, color = 2,
    big = true, style = "shell", category = "Rhy's Spider droids", labelZ = 84 }

-- LM-432 crab droid: its own entity (rhylib_crab: the spider's walker,
-- two guns, its own aim and firing, armour by hit direction).
D.CRAB_FALLBACK = "models/headcrabclassic.mdl"
D.KINDS.crab = { name = "LM-432 crab droid", modelCfg = "crabModel", fallback = D.CRAB_FALLBACK, health = "crabHealth", speed = "crabSpeed",
    range = "crabRange", reaction = "crabReaction", damage = "crabDamage", rpm = "crabRPM", spread = "crabSpread", burst = { 1, 1 }, color = 2,
    big = true, sound = D.B2_SOUND, style = "suppress", category = "Rhy's Crab droids", labelZ = 76 }

-- Droideka: its own entity (rhylib_droideka: rolled / deployed, shield
-- bubble, two arm blasters in bursts of `burst` shots).
D.DROIDEKA_FALLBACK = "models/combine_turrets/floor_turret.mdl"
D.KINDS.droideka = { name = "Droideka", modelCfg = "droidekaModel", fallback = D.DROIDEKA_FALLBACK, health = "droidekaHealth", speed = "droidekaSpeed",
    range = "droidekaRange", reaction = "droidekaReaction", damage = "droidekaDamage", rpm = "droidekaRPM", spread = "droidekaSpread", burst = { 6, 10 }, color = 2,
    big = true, sound = D.B2_SOUND, pitch = 115, style = "suppress", category = "Rhy's Droidekas", labelZ = 80 }

-- Training droids: yellow bolts (color 8), no kill credit.
D.KINDS.b1t = variant("b1", "B1 training droid", D.B1T_MODEL, { training = true, color = 8 })
D.KINDS.b2t = variant("b2", "B2 training droid", D.B2T_MODEL, { training = true, color = 8 })

-- BX commando droids: models from config, the B1's as the fallback.
D.KINDS.bx = { name = "BX commando droid", modelCfg = "bxModel", fallback = D.B1_MODEL, health = "b1Health", healthMult = "bxHealthMult", speed = "bxSpeed",
    range = "bxRange", reaction = "bxReaction", damage = "bxDamage", rpm = "bxRPM", spread = "bxSpread", burst = { 2, 3 }, color = 2, gun = D.E5_MODEL,
    nades = true, cover = true, style = "semi", bx = true, category = "Rhy's Commando droids" }
D.KINDS.bx_captain = variant("bx", "BX commando captain", nil, { modelCfg = "bxCaptainModel", health = "bxCaptainHealth", healthMult = false,
    damage = "bxCaptainDamage", commander = true, leads = "bx" })
D.KINDS.bx_training = variant("bx", "BX training commando", nil, { modelCfg = "bxTrainingModel", training = true, color = 8, category = "Rhy's Training droids" })

-- Clone troopers (side "republic"): rhylib_clone and its one-line
-- subclasses. Models come from config (modelCfg); fallback = HL2's
-- Combine soldier (it has rifle animations), never a droid model.
local DC15S, DC15A, Z6 = "models/jajoff/sps/cgiweapons/tc13j/dc15s.mdl", "models/jajoff/sps/cgiweapons/tc13j/dc15a.mdl", "models/jajoff/sps/cgiweapons/tc13j/z6.mdl"
D.CLONE_FALLBACK = "models/combine_soldier.mdl"
D.KINDS.ct_trooper = { name = "Clone trooper", side = "republic", modelCfg = "ctModel", health = "ctHealth", speed = "ctSpeed", range = "ctRange", reaction = "ctReaction",
    damage = "ctDamage", rpm = "ctRPM", spread = "ctSpread", burst = { 3, 8 }, color = 1, gun = DC15S, poppers = true, cover = true, style = "auto",
    sound = "weapons/dc15a/dc15a_fire.ogg", pitch = 112 }
D.KINDS.ct_rifleman = variant("ct_trooper", "Clone rifleman", nil, { damage = "ctRifleDamage", rpm = "ctRifleRPM", burst = { 2, 3 }, gun = DC15A, poppers = false, style = "semi",
    sound = "weapons/dc15a/dc15a_fire.ogg", pitch = 100 })
D.KINDS.ct_heavy = variant("ct_trooper", "Clone heavy", nil, { health = "ctHeavyHealth", speed = "ctHeavySpeed", damage = "ctHeavyDamage", rpm = "ctHeavyRPM",
    spread = "ctHeavySpread", burst = { 6, 10 }, gun = Z6, poppers = false, cover = false, style = "spray", sound = "weapons/airboat/airboat_gun_energy2.wav", pitch = 100 })
D.KINDS.ct_medic = variant("ct_trooper", "Clone medic", nil, { modelCfg = "ctMedicModel", poppers = false, medic = true })
D.KINDS.ct_commander = variant("ct_trooper", "Clone commander", nil, { modelCfg = "ctCmdModel", health = "ctCmdHealth", damage = "ctRifleDamage", rpm = "ctRifleRPM",
    burst = { 2, 3 }, gun = DC15A, poppers = false, commander = true, style = "semi", sound = "weapons/dc15a/dc15a_fire.ogg", pitch = 100 })

-- Server settings > Models: each kind's model and gun (clone bodies are
-- config settings: ctModel, ctMedicModel, ctCmdModel).
Rhylib.Hook.Add("Rhylib.ModelCatalogue", "droids.models", function(add)
    local keys = {}
    for k in pairs(D.KINDS) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local kind = D.KINDS[k]
        local get = function() return D.KINDS[k] end
        local group = kind.side == "republic" and "NPCs: Clones" or "NPCs: Droids"
        if not kind.modelCfg then add("droid." .. k, kind.name, group, get, "model") end
        if kind.gun then add("droid." .. k .. ".gun", kind.name .. " · gun", group, get, "gun") end
    end
end)

-- D.KindModel(kindRow) -> model path: the config model for kinds with
-- modelCfg (clones), else the row's model. Takes the row, not the name.
-- Example: local mdl = D.KindModel(D.KINDS.ct_medic)
function D.KindModel(k)
    if k.modelCfg then
        local m = D.Cfg(k.modelCfg)
        if isstring(m) and m ~= "" then return m end
    end
    return k.model
end

-- D.CLASSES: kind name -> entity class. Every entry is added to the
-- spawn menu's NPC list at the bottom of this file, and presets and
-- D.SpawnClone create NPCs through it. New kinds need one.
D.CLASSES = { b1 = 
"rhylib_b1", b2 = "rhylib_b2", b1t = "rhylib_b1_training", b2t = "rhylib_b2_training", b2_cannon = "rhylib_b2_cannon", b2_rocket = "rhylib_b2_rocketdroid",
    ct_trooper = "rhylib_ct_trooper", ct_rifleman = "rhylib_ct_rifleman", ct_heavy = "rhylib_ct_heavy", ct_medic = "rhylib_ct_medic", ct_commander = "rhylib_ct_commander",
    spider = "rhylib_spider", crab = "rhylib_crab" }
for _, v in ipairs({ "aat", "commander", "geonosis", "heavy", "marine", "security", "snow" }) do
    D.CLASSES["b1_" .. v] = "rhylib_b1_" .. v
end
D.CLASSES.droideka = "rhylib_droideka"
D.CLASSES.aqua = "rhylib_aqua_droid"
D.CLASSES.bx, D.CLASSES.bx_captain, D.CLASSES.bx_training = "rhylib_bx_commando", "rhylib_bx_captain", "rhylib_bx_training"

D.MODES = { "guard", "patrol", "attack", "roam" }   -- (index 1-4 on the wire, toolgun "New droids")
D.MODE_NAMES = { guard = "Guard", patrol = "Patrol", attack = "Attack", follow = "Follow", roam = "Spread out", retreat = "Retreat", laststand = "Last stand" }
-- (retreat = leave the front entirely, fall back = relocate)
D.AGGRO_NAMES = { "Retreat", "Fall back", "Moderate", "March", "Charge" }
-- A commander's own clones (command wheel): 3 = by the odds (their doctrine).
D.SQUAD_AGGRO_NAMES = { "Retreat", "Fall back to me", "By the odds", "March", "Charge" }

-- D.Aggro() -> 1-5: the droids' aggression. Server: the live level set by
-- D.SetAggro, else config "aggression". Client: Global2Int
-- rhylib_droidAggro. Clones use ENT:Aggro() instead.
function D.Aggro()
    local v
    if SERVER then v = D.aggroLive or D.Cfg("aggression") else v = GetGlobal2Int("rhylib_droidAggro", 3) end
    return math.Clamp(math.Round(tonumber(v) or 3), 1, 5)
end

-- A droid's blaster as rhylib_weapons sees it (BoltColor 11 = the droids'
-- thick red, 8 = training, 1 = clones' blue). Droid bolts fly at droids
-- boltSpeed; clones' at 6500.
-- D.Gun(kindName) -> the cached "weapon" table passed to Bolts.Fire
-- { BoltSpeed, BoltColor, Training, Damage }. Damage is re-read from
-- config on every call.
D.guns = D.guns or {}
function D.Gun(kind)
    local k = D.KINDS[kind] or D.KINDS.b1
    local g = D.guns[kind]
    if not g then
        -- (droids' red bolts: their own thicker look, BoltColor 11)
        g = { BoltSpeed = 6500, BoltColor = k.color == 2 and 11 or k.color, Training = k.training }
        D.guns[kind] = g
    end
    g.Damage = D.Cfg(k.damage)
    -- Droids (not clones): their own, slower bolt speed (droids boltSpeed).
    if k.color ~= 1 then g.BoltSpeed = D.Cfg("boltSpeed") end
    return g
end
function D.E5() return D.Gun("b1") end   -- (older callers)

-- Spawn menu (NPCs tab): one entry per D.CLASSES row, admin only.
for kind, class in pairs(D.CLASSES) do

    list.Set("NPC", class, {
        Name = D.KINDS[kind].name,
        Class = class,
        -- (split up so they're easier to find)
        Category = D.KINDS[kind].category or D.KINDS[kind].side == "republic" and "Rhy's Clone troopers" or D.KINDS[kind].training and "Rhy's Training droids"
            or (string.sub(kind, 1, 2) == "b2" and "Rhy's B2 super battle droids" or "Rhy's B1 battle droids"),
        AdminOnly = true,
    })
    if CLIENT then language.Add(class, D.KINDS[kind].name) end
end

-- Players and clone NPCs don't collide: friendlies never
-- block a doorway or a way out. Bolts still pass by their own rule.
Rhylib.Hook.Add("ShouldCollide", "droids.clones", function(a, b)
    if (a.IsRhylibClone and b:IsPlayer()) or (b.IsRhylibClone and a:IsPlayer()) then return false end
end)

-- Droid and clone spawners (entities/rhylib_droid_spawner.lua, rhylib_clone_spawner.lua): what a new one starts with
-- (admins change each one with E on it).
Config.Register("droids", "spawnerPreset", "droid_small", "Droid spawner: preset squad a new spawner sends (droid_small, droid_medium, droid_large, droid_b2, droid_mortar, droid_spider, droid_crab, droid_commando, droid_droideka, droid_aqua, droid_company, droid_division)")
Config.Meta("droids", "spawnerPreset", { options = { { "droid_small", "Small squad" }, { "droid_medium", "Medium squad" }, { "droid_large", "Large squad" }, { "droid_b2", "B2s" }, { "droid_mortar", "Mortars" }, { "droid_spider", "Spider squad" }, { "droid_crab", "Crab squad" }, { "droid_commando", "Commando squad (7)" }, { "droid_droideka", "Droideka pair" }, { "droid_aqua", "Aqua droid squad (10)" }, { "droid_company", "Droid company (33)" }, { "droid_division", "Droid division (66)" } } })
Config.Register("droids", "cloneSpawnerPreset", "clone_squad", "Clone spawner: preset squad a new clone spawner sends (clone_squad, clone_company)")
Config.Meta("droids", "cloneSpawnerPreset", { options = { { "clone_squad", "Clone squad (8)" }, { "clone_company", "Clone company (22)" } } })

-- Event targets (entities/rhylib_event_target.lua): what a new one starts
-- with (the toolgun's own settings window overrides these per placement).
Config.Register("droids", "etName", "Target", "Event target: name a new one gets")
Config.Register("droids", "etModel", "models/props_junk/wood_crate002a.mdl", "Event target: model a new one gets (any prop model)")
Config.Register("droids", "etScale", 1, "Event target: size of a new one (0.5-3)")
Config.Register("droids", "etHealth", 800, "Event target: health of a new one")
Config.Register("droids", "etExplode", false, "Event target: a new one blows up when destroyed")
Config.Register("droids", "etRadius", 300, "Event target: blast radius of a new one (units; 52 = 1 m)")
Config.Register("droids", "etBlastDamage", 120, "Event target: blast damage at its middle when one blows up (less further out; hurts everyone in the radius)")
Config.Register("droids", "etPriority", 1.25, "Event target: droids pick one as if it were this many times further away than it is (1 = as eagerly as a trooper)")
Config.Register("droids", "etMax", 30, "Event targets on the map at once")
Config.Register("droids", "etBarRange", 3150, "Event target: the health bar over it shows within this distance while in sight (units)")
Config.Register("droids", "spawnerTotal", 60, "Droid / clone spawner: NPCs a new spawner sends in all before it is empty")
Config.Register("droids", "spawnerCap", 20, "Droid / clone spawner: most of one spawner's NPCs alive at once")
Config.Register("droids", "spawnerInterval", 30, "Droid / clone spawner: seconds between squads")
Config.Register("droids", "spawnerMode", "patrol", "Droid / clone spawner: what its squads do (patrol, roam, attack, guard)")
Config.Meta("droids", "spawnerMode", { options = { { "patrol", "Patrol" }, { "roam", "Roam" }, { "attack", "Attack" }, { "guard", "Guard" } } })
Config.Register("droids", "spawnerHealth", 2000, "Droid / clone spawner: damage it takes before it breaks (a clone spawner only from droids)")
Config.Register("droids", "spawnerModel", "models/props_combine/combine_dispenser.mdl", "Droid / clone spawner: model (a placeholder until a droid factory model is picked; the clone spawner is tinted blue)")

--------------------------------------------------------------------------
-- Server settings page: this module's name, side-bar category and
-- sections (Config.Describe + Config.Sections: patterns over the keys, the
-- first match wins; core applies them to every key of the module).
--------------------------------------------------------------------------

local PAGE_SECTIONS = {
    { "General", { "^boltSpeed$", "^maxActive$", "^aggression$", "^pathPerTick$", "^walkMult$", "^runSpread$", "^walkSpread$", "^moveSpread$", "^marchGroup$" } },
    { "Squads", { "^squad" } },
    { "Droid & clone spawners", { "^spawner", "^cloneSpawner" } },
    { "Event targets", { "^et[A-Z]" } },
    { "Roam, patrol & calls for help", { "^roamRadius$", "^patrolRadius$", "^wander", "^call", "^ctCall" } },
    { "Orders & areas", { "^guardRadius$", "^markerRadius$", "^brushRadius$" } },
    { "B1 grenades", { "^b1Nade" } },
    { "B1 battle droids", { "^b1", "^e5" } },
    { "B2 rockets & mortars", { "^b2Rocket", "^b2Direct", "^b2Slow", "^b2Dive", "^arty", "^mortar", "^b2cRPM$" } },
    { "B2 super battle droids", { "^b2" } },
    { "Spider droids", { "^spider" } },
    { "Crab droids", { "^crab" } },
    { "Droidekas", { "^droideka" } },
    { "Commando droids", { "^bx" } },
    { "Heavy & commander droids", { "^suppress", "^heavy", "^cmdHealth$", "^cmdRadius$", "^cmdSpread$", "^cmdReaction$", "^cmdPause$", "^cmdDeath", "^smoke" } },
    { "Cover & accuracy", { "^cover", "^blindSpread$", "^retreatFrac$", "^flash", "^settle", "^crowd" } },
    { "Retreat", { "^retreat", "^lastStand" } },
    { "Clone medics", { "^ctMedic", "^ctDown", "^reviveShield" } },
    { "Clone tactics", { "^ctOdds", "^ctFallBackOdds$", "^ctChargeOdds$", "^ctCrouch", "^ctPopper" } },
    { "Clone troopers", { "^clone", "^ct", "^cmdFollowRadius$", "^cmdMaxFollowers$" } },
    { "Stealth", { "^stealth" } },   -- (sh_50_stealth.lua)
}

Config.Describe("droids", { name = "Droids & clones", category = "NPCs" })
Config.Sections("droids", PAGE_SECTIONS)   -- (core: applies to keys registered before and after)
