local mod = dmhub.GetModLoading()

--- Shared vocabulary for the Montage feature.
MTGConstants = {}

-- Identity
MTGConstants.libraryDoc = "mtgLibrary"
MTGConstants.activeRunDoc = "mtgActive"
MTGConstants.archiveDoc = "mtgArchive"
MTGConstants.dialogId = "mtgmontage"
MTGConstants.panelName = "Montage"          -- keys the launchable panel and the presented dialog
MTGConstants.panelTitle = "Montage Tests"   -- what the Director's window says
MTGConstants.playerPanelTitle = "Montage Test"

-- Window
MTGConstants.windowWidth = 1220
MTGConstants.windowHeight = 620
MTGConstants.listWidth = 360
MTGConstants.listRightMargin = 12

-- Player window: narrower, no footer
MTGConstants.playerWindowWidth = 800
MTGConstants.playerWindowHeight = 600

-- Footer cells. The band, its rule and the window's padding are the
-- DialogShell's; only the split inside the band is ours. Whole percentages,
-- as the shell takes them, and the middle cell carries the odd point so three
-- of them sum to 100.
MTGConstants.footerCells = {33, 34, 33}
MTGConstants.footerCellsRun = {50, 50}  -- pause/reset/show, then next/end

-- Run status
MTGConstants.statusSetup = "setup"
MTGConstants.statusRunning = "running"
MTGConstants.statusEnded = "ended"

-- Challenge state
MTGConstants.stateLocked = "locked"
MTGConstants.stateOpen = "open"
MTGConstants.stateStaged = "staged"
MTGConstants.stateResolving = "resolving"
MTGConstants.stateClosed = "closed"

-- Rules modules
MTGConstants.moduleBaseline = "baseline"
MTGConstants.moduleTO = "to"

-- Rolling
MTGConstants.rollCheckId = "mtg_test"

--- Power roll type for the modifier pipeline. Must be a stock type: the
--- modifier matcher admits only "all" or an exact match against a closed
--- vocabulary, and a miss drops every Tests-scoped modifier without raising.
MTGConstants.modifierRollType = "test_power_roll"

-- Limits
MTGConstants.repeatMax = 99                 -- doubles as "unlimited" for legacy repeatable = true
MTGConstants.roundMax = 99                  -- two digits, matching the stepper's input width

--- Seconds the celebration stays reachable, counted from when it goes out.
--- It is a moment, not a surface: past this a reconnecting client no longer
--- rebuilds it.
MTGConstants.celebrationTTL = 30

-- Icons
MTGConstants.iconRepeatable = "phosphor/repeat-bold.png"
MTGConstants.iconRoll = "ui-icons/dsdice/djordice-d10.png"
MTGConstants.iconGrant = "phosphor/check-fat-duotone.png"
MTGConstants.iconVictory = "drawsteel/HeroicResources/T_UI_ICON_FLAT_HR_VICTORY.png"
MTGConstants.iconPending = "phosphor/circle-duotone.png"
MTGConstants.iconSuccess = "phosphor/check-circle.png"
MTGConstants.iconFailure = "phosphor/x-circle.png"
MTGConstants.iconConfigured = "phosphor/check-circle.png"  -- editor: every field present. Distinct in meaning from iconSuccess
MTGConstants.iconPresent = "icons/icon_app/icon_app_34.png"  -- hand a run-time Challenge to the table
