-- Third person settings (shared, so clients read the same mode).
-- Server setting (Server settings page, or Config.Set in a host file):
--   "choice" players switch with P (default), "third" everyone is always in
--   third person, "first" first person only.
Rhylib.Config.Register("thirdperson", "mode", "choice", "Third person: choice (players switch with P), third (always third person), first (first person only)")

-- Old switch, still honoured: 0 = first person only.
CreateConVar("rhylib_thirdperson_allowed", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Allow Rhylib over-the-shoulder third person (0/1)")
