local mod = dmhub.GetModLoading()

--- Shared vocabulary for the Montage feature.
MTGConstants = {}

MTGConstants.libraryDoc = "mtgLibrary"
MTGConstants.activeRunDoc = "mtgActive"
MTGConstants.archiveDoc = "mtgArchive"

MTGConstants.dialogId = "mtgmontage"
MTGConstants.panelName = "Montage"

MTGConstants.iconRepeatable = "phosphor/repeat-bold.png"
MTGConstants.iconRoll = "ui-icons/dsdice/djordice-d10.png"
MTGConstants.iconVictory = "drawsteel/HeroicResources/T_UI_ICON_FLAT_HR_VICTORY.png"
MTGConstants.iconPending = "phosphor/question-light.png"
MTGConstants.iconSuccess = "phosphor/check-circle.png"
MTGConstants.iconFailure = "phosphor/warning-circle-bold.png"

--- Seconds the celebration stays reachable, counted from when it goes out.
--- It is a moment, not a surface: past this a reconnecting client no longer
--- rebuilds it.
MTGConstants.celebrationTTL = 30

MTGConstants.rollCheckId = "mtg_test"

--- Power roll type for the modifier pipeline. Must be a stock type: the
--- modifier matcher admits only "all" or an exact match against a closed
--- vocabulary, and a miss drops every Tests-scoped modifier without raising.
MTGConstants.modifierRollType = "test_power_roll"

MTGConstants.moduleBaseline = "baseline"
MTGConstants.moduleTO = "to"

MTGConstants.stateLocked = "locked"
MTGConstants.stateOpen = "open"
MTGConstants.stateStaged = "staged"
MTGConstants.stateResolving = "resolving"
MTGConstants.stateClosed = "closed"

MTGConstants.statusSetup = "setup"
MTGConstants.statusRunning = "running"
MTGConstants.statusEnded = "ended"
