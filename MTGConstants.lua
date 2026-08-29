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
MTGConstants.windowPad = 16
MTGConstants.listWidth = 360
MTGConstants.listRightMargin = 12

-- Player window: narrower, no footer
MTGConstants.playerWindowWidth = 800
MTGConstants.playerWindowHeight = 600

-- Header: fixed band, divider floats under the heading so type prints over it
MTGConstants.headerHeight = 40
MTGConstants.headerDividerHeight = 12       -- weight of the rule, not spacing
MTGConstants.headerDividerTopMargin = 22    -- where the rule crosses the band
MTGConstants.headerTitleWidth = "25%"
MTGConstants.headerTitleBottomMargin = -6   -- closes the line box's slack under the baseline
MTGConstants.headerInfoWidth = "67%"
MTGConstants.headerInfoRightMargin = 0      -- the launchable host owns the close control

-- Footer: fixed band, divider on top, controls in cells
MTGConstants.footerHeight = 60
MTGConstants.footerDividerMargin = 12
MTGConstants.footerCellWidth = "33.3%"
MTGConstants.footerCellsRun = {"50%", "50%"}  -- pause/reset/show, then next/end

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
