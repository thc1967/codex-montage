local mod = dmhub.GetModLoading()

--- The montage windows and the shell they wear: a fixed heading band with the
--- rule painted under the type, a working area taking what is left, and on the
--- Director's window a footer whose controls follow the run's status.
MTGDialog = {}

--- How many Montage windows this client has open. A board pushed to a player
--- who already opened it from the Game menu must not toggle it shut.
local m_openWindows = 0

--- @return boolean
function MTGDialog.IsOpen()
    return m_openWindows > 0
end

--- The window's heading band. The rule is drawn first and floating so the
--- title paints over it rather than sitting above it.
--- @param args table reads title, headerInfo
--- @return Panel
local function BuildHeader(args)
    return gui.Panel{
        width = "100%",
        height = MTGConstants.headerHeight,
        flow = "vertical",
        halign = "left",
        valign = "top",

        gui.Panel{
            floating = true,
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            tmargin = MTGConstants.headerDividerTopMargin,

            gui.MCDMDivider{
                width = "100%",
                layout = "line",
                height = MTGConstants.headerDividerHeight,
            },
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            gui.Label{
                classes = { "sizeXxl", "bold" },
                width = MTGConstants.headerTitleWidth,
                height = "auto",
                halign = "left",
                valign = "bottom",
                bmargin = MTGConstants.headerTitleBottomMargin,
                text = args.title,
            },

            gui.Label{
                classes = { "sizeS", "noBold", "fgMuted" },
                width = MTGConstants.headerInfoWidth,
                height = "auto",
                halign = "right",
                rmargin = MTGConstants.headerInfoRightMargin,
                valign = "bottom",
                textAlignment = "right",
                markdown = true,
                textWrap = true,
                text = args.headerInfo ~= nil and args.headerInfo() or "",
                montageChanged = function(element)
                    element.text = args.headerInfo ~= nil and args.headerInfo() or ""
                end,
            },
        },
    }
end

--- One cell of a footer. Cells are equal thirds unless a state asks for its
--- own split, so contents land left, centre and right whichever a state fills.
--- @param slot nil|Panel
--- @param width nil|string overrides the even third
--- @return Panel
local function FooterCell(slot, width)
    return gui.Panel{
        width = width or MTGConstants.footerCellWidth,
        height = "100%",
        flow = "horizontal",
        valign = "center",
        children = slot ~= nil and {slot} or {},
    }
end

--- The band under the working area, and the rule above it.
--- @param cells table[] {slot, width} in order
--- @return Panel
local function BuildFooter(cells)
    local row = {}
    for _, cell in ipairs(cells or {}) do
        row[#row + 1] = FooterCell(cell.slot, cell.width)
    end

    return gui.Panel{
        width = "100%",
        height = MTGConstants.footerHeight,
        flow = "vertical",
        halign = "left",
        valign = "bottom",

        gui.MCDMDivider{
            width = "100%",
            layout = "line",
            vmargin = MTGConstants.footerDividerMargin,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",

            children = row,
        },
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

    --The launchable host owns this window's lifetime, so closing is a request
    --to the parent rather than a DestroySelf.
    local function Close()
        if resultPanel ~= nil and resultPanel.valid and resultPanel.parent ~= nil then
            resultPanel.parent:FireEvent("close")
        end
    end

    --Nothing to run until a definition is selected and no other montage holds
    --the table. There is no readiness test beyond that.
    local runButton = gui.Button{
        classes = { "sizeS", "disabled" },
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
                classes = { "sizeS" },
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

    --Every state's band is built once and collapsed, the way the right pane's
    --bodies are, so a swap never rebuilds a live control.
    local footerPanel = gui.Panel{
        width = "100%",
        height = MTGConstants.footerHeight,
        flow = "none",
        halign = "left",
        valign = "bottom",

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

    resultPanel = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        classes = { "dialog" },
        width = MTGConstants.windowWidth,
        height = MTGConstants.windowHeight,
        flow = "vertical",
        halign = "center",
        valign = "center",
        pad = MTGConstants.windowPad,

        monitorGame = MTGRun.DocPath(),
        refreshGame = function(element)
            element:FireEventTree("montageChanged")
        end,

        create = function()
            m_openWindows = m_openWindows + 1
        end,

        destroy = function()
            m_openWindows = math.max(0, m_openWindows - 1)
        end,

        --Only once the montage is over: while it runs, the board carries its
        --own title row and the two would say the same thing twice.
        BuildHeader{
            title = MTGConstants.panelTitle,
            headerInfo = function()
                local active = MTGRun.Active()
                if active == nil or active.status ~= MTGConstants.statusEnded then
                    return ""
                end
                return string.format("%s - Complete", active.name or "Montage")
            end,
        },

        gui.Panel{
            width = "100%",
            height = "100% available",
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
        },

        footerPanel,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    return resultPanel
end

--- What the table sees: the running board, or a line of text when there is
--- nothing to watch. No footer.
--- @return Panel
function MTGDialog.CreatePlayerView()
    --Name, play state and round, which the board used to carry itself.
    local function HeaderInfo()
        local run = MTGRun.Active()
        if run == nil then
            return ""
        end

        local state = "Running"
        if run:try_get("paused", false) then
            state = "Paused"
        end

        return string.format("%s - %s - Round %d",
            run.name or "Montage", state, run.round or 1)
    end

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

    local resultPanel
    resultPanel = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        classes = { "mtgPlayerView" },
        width = MTGConstants.playerWindowWidth,
        height = MTGConstants.playerWindowHeight,
        flow = "vertical",
        halign = "center",
        valign = "center",
        pad = MTGConstants.windowPad,

        --Seeded from the state this window was built on, so one opened while
        --the montage is paused stays put instead of closing on its first ping.
        data = {
            sawLive = IsLive(MTGRun.Active()),
        },

        monitorGame = MTGRun.DocPath(),
        refreshGame = function(element)
            element:FireEventTree("montageChanged")
        end,

        montageChanged = function(element)
            local run = MTGRun.Active()
            local live = IsLive(run)

            --Pause, Reset and Complete all end up here: a window that was
            --showing a live board and no longer has one takes itself off the
            --table. The host owns the lifetime, so this asks rather than
            --destroys.
            if element.data.sawLive and not live then
                element.data.sawLive = false
                if element.parent ~= nil then
                    element.parent:FireEvent("close")
                end
                return
            end

            element.data.sawLive = live
            board.body:SetClass("collapsed", not live)
            pausedBody:SetClass("collapsed", live or run == nil)
            idleBody:SetClass("collapsed", run ~= nil)
        end,

        create = function(element)
            m_openWindows = m_openWindows + 1
            element:FireEvent("montageChanged")
        end,

        destroy = function()
            m_openWindows = math.max(0, m_openWindows - 1)
        end,

        BuildHeader{
            title = MTGConstants.playerPanelTitle,
            headerInfo = HeaderInfo,
        },

        board.body,
        pausedBody,
        idleBody,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

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

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

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
