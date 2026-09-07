local mod = dmhub.GetModLoading()

--- Shared vocabulary for the Montage feature.
MTGConstants = {}

MTGConstants.libraryDoc = "mtgLibrary"
MTGConstants.activeRunDoc = "mtgActive"
MTGConstants.archiveDoc = "mtgArchive"
MTGConstants.dialogId = "mtgmontage"
MTGConstants.panelName = "Montage"          -- keys the launchable panel and the presented dialog
MTGConstants.panelTitle = "Montage Tests"
MTGConstants.playerPanelTitle = "Montage Test"

MTGConstants.windowWidth = 1220
MTGConstants.windowHeight = 620
MTGConstants.listWidth = 360
MTGConstants.listRightMargin = 12

MTGConstants.playerWindowWidth = 800
MTGConstants.playerWindowHeight = 600

-- Whole percentages: the shell takes no decimals.
MTGConstants.footerCells = {33, 34, 33}
MTGConstants.footerCellsRun = {50, 50}

MTGConstants.statusSetup = "setup"
MTGConstants.statusRunning = "running"
MTGConstants.statusEnded = "ended"

MTGConstants.stateLocked = "locked"
MTGConstants.stateOpen = "open"
MTGConstants.stateStaged = "staged"
MTGConstants.stateResolving = "resolving"
MTGConstants.stateClosed = "closed"

MTGConstants.moduleBaseline = "baseline"
MTGConstants.moduleTO = "to"

--- The Success Ladder's rungs, best first: what the Director narrates when the
--- montage lands on each outcome. Draw Steel only - T&O settles on Threats and
--- Opportunities and has no ladder. The ids are the Baseline module's own
--- ending degrees, so the two never need translating between.
MTGConstants.ladderRungs = {
    { id = "total_success", text = "Total Success" },
    { id = "partial_success", text = "Partial Success" },
    { id = "total_failure", text = "Failure" },
}

MTGConstants.rollCheckId = "mtg_test"

--- Power roll type for the modifier pipeline. Must be a stock type: the
--- modifier matcher admits only "all" or an exact match against a closed
--- vocabulary, and a miss drops every Tests-scoped modifier without raising.
MTGConstants.modifierRollType = "test_power_roll"

MTGConstants.repeatMax = 99                 -- also "unlimited" for a legacy repeatable = true
MTGConstants.roundMax = 99                  -- two digits, matching the stepper's input width

--- Seconds the celebration stays reachable, counted from when it goes out.
--- It is a moment, not a surface: past this a reconnecting client no longer
--- rebuilds it.
MTGConstants.celebrationTTL = 30

MTGConstants.iconRepeatable = "phosphor/repeat-bold.png"
MTGConstants.iconRoll = "ui-icons/dsdice/djordice-d10.png"
MTGConstants.iconGrant = "phosphor/check-fat-duotone.png"
MTGConstants.iconVictory = "drawsteel/HeroicResources/T_UI_ICON_FLAT_HR_VICTORY.png"
MTGConstants.iconPending = "phosphor/circle-duotone.png"
MTGConstants.iconSuccess = "phosphor/check-circle.png"
MTGConstants.iconFailure = "phosphor/x-circle.png"
MTGConstants.iconConfigured = "phosphor/check-circle.png"  -- same asset as iconSuccess, different meaning
MTGConstants.iconPresent = "icons/icon_app/icon_app_34.png"
