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
MTGConstants.iconGrant = "phosphor/check-fat-duotone.png"
MTGConstants.iconVictory = "drawsteel/HeroicResources/T_UI_ICON_FLAT_HR_VICTORY.png"
MTGConstants.iconPending = "phosphor/circle-duotone.png" --"phosphor/circle-duotone.png"
MTGConstants.iconSuccess = "phosphor/check-circle.png"

--- Shown in the editor when a Challenge has every field it needs. Distinct in
--- meaning from iconSuccess even though it shares the asset.
MTGConstants.iconConfigured = "phosphor/check-circle.png"

--- Hand a run-time Challenge to the table. The journal's share control.
MTGConstants.iconPresent = "icons/icon_app/icon_app_34.png"

MTGConstants.iconFailure = "phosphor/x-circle.png"

--- Seconds the celebration stays reachable, counted from when it goes out.
--- It is a moment, not a surface: past this a reconnecting client no longer
--- rebuilds it.
MTGConstants.celebrationTTL = 30

MTGConstants.rollCheckId = "mtg_test"

--- Power roll type for the modifier pipeline. Must be a stock type: the
--- modifier matcher admits only "all" or an exact match against a closed
--- vocabulary, and a miss drops every Tests-scoped modifier without raising.
MTGConstants.modifierRollType = "test_power_roll"

--- The most repeats a Challenge can carry. A montage runs a couple of rounds,
--- so this doubles as "effectively unlimited" for legacy data that stored
--- repeatable as a plain true.
MTGConstants.repeatMax = 99

--- The latest round a Challenge can be held back to. Two digits, matching the
--- stepper's input width.
MTGConstants.roundMax = 99

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

