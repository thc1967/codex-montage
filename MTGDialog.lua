local mod = dmhub.GetModLoading()

--- The montage windows. The frame they wear - heading band, working area and
--- footer band - comes from DialogShell; what stays here is which pane the
--- run's status calls for, and when a player's board has outlived the montage
--- it was following.
MTGDialog = RegisterGameType("MTGDialog")

--- How many Montage windows this client has open. A board pushed to a player
--- who already opened it from the Game menu must not toggle it shut.
local m_openWindows = 0

--- @return boolean
function MTGDialog.IsOpen()
    return m_openWindows > 0
end

--- The run line both windows carry in their shell header: what the montage is,
--- whether it is going, and how far in. Shared so the Director's window and the
--- players' say it the same way, in the same place.
--- @return string
local function RunHeaderInfo()
    local run = MTGRun.Active()
    if run == nil then
        return ""
    end

    if run.status == MTGConstants.statusEnded then
        return string.format("%s | Complete", run.name or "Montage")
    end

    if run.status == MTGConstants.statusSetup then
        return string.format("%s | Setup", run.name or "Montage")
    end

    if run.status ~= MTGConstants.statusRunning then
        return ""
    end

    return string.format("%s | %s | Round %d",
        run.name or "Montage",
        cond(run:try_get("paused", false), "Paused", "In play"),
        run.round or 1)
end

--- One cell of a footer. Cells are equal thirds unless a state asks for its
--- own split, so contents land left, centre and right whichever a state fills.
--- @param slot nil|Panel
--- @param pct number cell width as a whole percentage
--- @return Panel
local function FooterCell(slot, pct)
    return gui.Panel{
        width = string.format("%d%%", pct),
        height = "100%",
        flow = "horizontal",
        valign = "center",
        children = slot ~= nil and {slot} or {},
    }
end

--- A state's row of controls. The band and the rule above it belong to the
--- DialogShell; this is only what sits inside them.
--- @param cells table[] {slot, width} in order
--- @return Panel
local function BuildFooter(cells)
    local row = {}

    -- A band of its own width says so; anything else takes its share by
    -- position, and an even split once past what the default names.
    cells = cells or {}
    local share = math.floor(100 / math.max(1, #cells))

    for i, cell in ipairs(cells) do
        row[#row + 1] = FooterCell(cell.slot,
            cell.width or MTGConstants.footerCells[i] or share)
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "center",

        children = row,
    }
end

--- The Director's window: library on the left, whichever pane the run's status
--- calls for on the right, and a footer that changes with it.
--- @return Panel
function MTGDialog.Create()
    local listPanel
    local editorPanel = MTGEditorPanel.Create()
    local setup = MTGSetupPanel.Create()
    local run = MTGRunPanel.Create{ director = true }
    local ending = MTGEndingPanel.Create{ director = true }

    --Import takes the pane rather than opening a dialog of its own, so it is
    --a sibling of the editor rather than a layer over it.
    local m_importing = false
    local rightPane
    local importPanel = MTGImportPanel.Create(function(defid)
        m_importing = false
        rightPane:FireEvent("rebuild")
        if defid ~= nil then
            listPanel:FireEvent("select", defid)
        end
    end)

    --What Run acts on. The editor keeps its own copy privately, so the
    --selection is tracked here rather than read back out of it.
    local m_selectedDefid = nil
    local resultPanel

    listPanel = MTGLibraryPanel.Create(function(defid)
        m_selectedDefid = defid
        if editorPanel.valid then
            editorPanel:FireEvent("setDefinition", defid)
        end
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel:FireEventTree("montageChanged")
        end
    end, function()
        m_importing = true
        importPanel:FireEvent("reset")
        rightPane:FireEvent("rebuild")
    end)

    rightPane = gui.Panel{
        width = "100% available",
        height = "100%",
        flow = "vertical",
        valign = "top",

        montageChanged = function(element)
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local active = MTGRun.Active()
            local status = active ~= nil and active.status or nil
            importPanel:SetClass("collapsed", not m_importing)
            editorPanel:SetClass("collapsed", active ~= nil or m_importing)
            setup.body:SetClass("collapsed", status ~= MTGConstants.statusSetup)
            run.body:SetClass("collapsed", status ~= MTGConstants.statusRunning)
            ending.body:SetClass("collapsed", status ~= MTGConstants.statusEnded)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        editorPanel,
        importPanel,
        setup.body,
        run.body,
        ending.body,
    }

    local dlg

    --The launchable host owns this window's lifetime, so closing is a request
    --to the parent rather than a DestroySelf.
    local function Close()
        if dlg ~= nil then
            dlg:Close()
        end
    end

    --Nothing to run until a definition is selected and no other montage holds
    --the table. There is no readiness test beyond that.
    local runButton = gui.Button{
        classes = { "sizeL", "disabled" },
        text = "Run",
        halign = "right",
        valign = "center",
        interactable = false,
        hover = gui.Tooltip("Set this montage up and run it"),
        click = function(element)
            if not element.interactable or m_selectedDefid == nil then
                return
            end
            MTGRun.BeginSetup(m_selectedDefid)
        end,
        montageChanged = function(element)
            local enabled = m_selectedDefid ~= nil and MTGRun.Active() == nil
            element:SetClass("disabled", not enabled)
            element.interactable = enabled
        end,
    }

    local idleFooter = BuildFooter{
        {
            slot = gui.Button{
                classes = { "sizeL" },
                text = "Close",
                halign = "left",
                valign = "center",
                click = Close,
            },
        },
        {},
        { slot = runButton },
    }

    local setupFooter = BuildFooter(setup.footer)
    local runFooter = BuildFooter(run.footer)
    local endFooter = BuildFooter(ending.footer)

    --Every state's row is built once and collapsed, the way the right pane's
    --bodies are, so a swap never rebuilds a live control. That is also why the
    --shell gets one full-width cell rather than having its own refilled.
    local footerPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "none",
        halign = "left",
        valign = "center",

        montageChanged = function()
            local active = MTGRun.Active()
            local status = active ~= nil and active.status or nil
            idleFooter:SetClass("collapsed", active ~= nil)
            setupFooter:SetClass("collapsed", status ~= MTGConstants.statusSetup)
            runFooter:SetClass("collapsed", status ~= MTGConstants.statusRunning)
            endFooter:SetClass("collapsed", status ~= MTGConstants.statusEnded)
        end,

        create = function(element)
            element:FireEvent("montageChanged")
        end,

        idleFooter,
        setupFooter,
        runFooter,
        endFooter,
    }

    dlg = DialogShell.CreateNew{
        classes = { "launchablePanel" },
        title = MTGConstants.panelTitle,
        subtitle = RunHeaderInfo(),
        width = MTGConstants.windowWidth,
        height = MTGConstants.windowHeight,
        footerCells = { 100 },
        close = "host",

        monitor = MTGRun.DocPath(),
        refresh = function(shell)
            shell:Root():FireEventTree("montageChanged")
            shell:SetSubtitle(RunHeaderInfo())
        end,

        onCreate = function(shell)
            m_openWindows = m_openWindows + 1
            shell:Root():FireEventTree("montageChanged")
        end,

        onDestroy = function()
            m_openWindows = math.max(0, m_openWindows - 1)
        end,
    }

    resultPanel = dlg:Root()

    dlg:SetWorkingContent(gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        valign = "top",

        gui.Panel{
            width = MTGConstants.listWidth,
            height = "100%",
            flow = "vertical",
            valign = "top",
            rmargin = MTGConstants.listRightMargin,
            vscroll = true,

            listPanel,
        },

        rightPane,
    })

    dlg:SetFooterContent("left", footerPanel)

    return resultPanel
end

--- What the table sees: the running board, or a line of text when there is
--- nothing to watch. No footer.
--- @return Panel
function MTGDialog.CreatePlayerView()
    --Name, play state and round, which the board used to carry itself.
    --Nothing actionable in either: a player who opens the window while the
    --montage is paused, or with none running, can only read it and close it.
    local function Notice(message)
        return gui.Panel{
            classes = { "collapsed" },
            width = "100%",
            height = "100% available",
            flow = "vertical",
            halign = "center",
            valign = "center",

            gui.Label{
                classes = { "sizeL", "noBold", "fgMuted" },
                width = "80%",
                height = "auto",
                halign = "center",
                valign = "center",
                textAlignment = "center",
                textWrap = true,
                text = message,
            },
        }
    end

    --- A board worth showing: running, and not paused.
    --- @param run nil|MTGRun
    --- @return boolean
    local function IsLive(run)
        return run ~= nil and not run:try_get("paused", false)
    end

    local board = MTGRunPanel.Create{ director = false }
    local pausedBody = Notice("This montage is paused.")
    local idleBody = Notice("No montage is running.")

    --Seeded from the state this window was built on, so one opened while the
    --montage is paused stays put instead of closing on its first ping.
    local sawLive = IsLive(MTGRun.Active())

    --- Pause, Reset and Complete all end up here: a window that was showing a
    --- live board and no longer has one takes itself off the table.
    --- @param shell DialogShell
    local function Apply(shell)
        local run = MTGRun.Active()
        local live = IsLive(run)

        shell:SetSubtitle(RunHeaderInfo())

        if sawLive and not live then
            sawLive = false
            shell:Close()
            return
        end

        sawLive = live
        board.body:SetClass("collapsed", not live)
        pausedBody:SetClass("collapsed", live or run == nil)
        idleBody:SetClass("collapsed", run ~= nil)
    end

    --mtgPlayerView is a marker, not a look: the celebration's Close button
    --finds its host by it. The band and rule come from the shell.
    local dlg = DialogShell.CreateNew{
        classes = { "mtgPlayerView", "launchablePanel" },
        title = MTGConstants.playerPanelTitle,
        subtitle = RunHeaderInfo(),
        width = MTGConstants.playerWindowWidth,
        height = MTGConstants.playerWindowHeight,
        footerCells = false,
        close = "host",

        monitor = MTGRun.DocPath(),
        refresh = function(shell)
            shell:Root():FireEventTree("montageChanged")
            Apply(shell)
        end,

        onCreate = function(shell)
            m_openWindows = m_openWindows + 1
            Apply(shell)
        end,

        onDestroy = function()
            m_openWindows = math.max(0, m_openWindows - 1)
        end,
    }

    local resultPanel = dlg:Root()

    dlg:SetWorkingContent{
        board.body,
        pausedBody,
        idleBody,
    }

    return resultPanel
end

--- The closing report, which is a full-screen layer rather than a window: it
--- lands in the hud's documentsPanel, already a 100% x 100% layer, so it fills
--- the screen and dims behind itself.
--- @param report table
--- @return Panel
local function CreateCelebrationOverlay(report)
    local resultPanel
    resultPanel = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        classes = { "mtgPlayerView" },
        floating = true,
        flow = "none",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        --A parent with interactable=false blocks raycasts for its whole
        --subtree, so the buttons below need this on.
        interactable = true,

        --Not a DialogShell - no heading band, no footer, just a dimmed layer -
        --so the theme subscription is held and dropped by hand here.
        data = {
            themeSub = nil,
        },

        create = function(element)
            element.data.themeSub = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.GetStyles()
                end
            end)
        end,

        destroy = function(element)
            if element.data.themeSub ~= nil then
                element.data.themeSub:Deregister()
                element.data.themeSub = nil
            end
        end,

        gui.Panel{
            interactable = false,
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#000000d0",
        },

        MTGEndingPanel.CreateCelebration(report),
    }

    return resultPanel
end

--- The Director presenting to the table, arriving on a player's client. The
--- board itself is the Game menu's window rather than one built here, so a
--- board pushed to a player is the same window in the same host they would
--- have opened themselves.
---
--- Returning nothing leaves the presentation machinery with nothing to tear
--- down, which is what lets the window decide for itself when to go.
--- @param args nil|{report: table|nil}
--- @return Panel|nil
function MTGDialog.RaiseForPlayer(args)
    args = args or {}

    if args.report ~= nil then
        return CreateCelebrationOverlay(args.report)
    end

    if dmhub.isDM then
        return nil
    end

    --LaunchPanelByName toggles, so a player who already has it open would have
    --it shut in their face. Asking first is per-client.
    if not MTGDialog.IsOpen() then
        LaunchablePanel.LaunchPanelByName(MTGConstants.panelName)
    end

    return nil
end

GameHud.RegisterPresentableDialog{
    id = MTGConstants.dialogId,
    keeplocal = false,
    create = MTGDialog.RaiseForPlayer,
}

LaunchablePanel.Register{
    name = MTGConstants.panelName,
    menu = "game",
    icon = "game-icons/bookmarklet.png",
    halign = "center",
    valign = "center",
    content = function()
        if dmhub.isDM then
            return MTGDialog.Create()
        end
        return MTGDialog.CreatePlayerView()
    end,
}
