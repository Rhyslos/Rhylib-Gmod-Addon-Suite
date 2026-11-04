--[[
    Basic training quiz (shared: settings, the starter questions).

    A cadet takes it at a training instructor (entities/rhylib_trainer.lua:
    an NPC-looking clone admins place, saved per map; walk up and press E):
    quizCount questions picked at random from the server's list,
    answers shuffled, one at a time (cl_60_quiz.lua). quizPass of them
    right and they pass basic training at once (R.Train, logged), the same
    as a Sergeant passing them. Fewer, and they can try again straight away,
    quizTries times in a row (3); failing them all locks them out for
    quizRetry seconds and calls every instructor online for them (a
    "Cadet needs training" notice plus a chat line). Cadets who'd rather
    have a person press "Request basic training" on the Battalion page. The score is shown, never which answers were
    wrong.

    Staff (permission rhylib.roster.quiz, admin) write the questions on
    the Staff > Training quiz page: each a question, 2-6 answers, one
    right answer. Saved on the server; until staff
    save their own, R.QUIZ_STARTER (sv_60_quiz.lua: server only, so players
    never download the answers) is used. Saved as Data "roster_quiz" "list".

    Settings (module roster): quiz, quizCount, quizPass, quizTries, quizRetry,
    trainerModel.
]]

local R = Rhylib.Roster
local Config = Rhylib.Config

Config.Register("roster", "quiz", true, "Basic training quiz: cadets can pass basic training by passing a quiz (Battalion page); off = only instructors pass them")
Config.Register("roster", "quizCount", 10, "Basic training quiz: questions asked (picked at random; fewer if the list is shorter; at most 30)")
Config.Register("roster", "quizPass", 0.8, "Basic training quiz: share of answers that must be right to pass (0.8 = 8 of 10)")
Config.Register("roster", "quizTries", 3, "Basic training quiz: tries in a row before a cadet is locked out (and instructors are called for them)")
Config.Register("roster", "trainerModel", "models/ct_trp/pm_ct_trp.mdl", "Training instructor NPC: model (a clone model with player animations)")
Config.Register("roster", "quizRetry", 600, "Basic training quiz: seconds a cadet is locked out after failing quizTries times in a row")

Rhylib.Perms.Register("rhylib.roster.quiz", "admin", "Write the basic training quiz questions (Staff > Training quiz)")

R.QUIZ_MAX = 60        -- questions on the list
R.QUIZ_Q_LEN = 300     -- letters in a question
R.QUIZ_A_LEN = 120     -- letters in an answer
