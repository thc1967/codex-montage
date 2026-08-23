local mod = dmhub.GetModLoading()

--- The montage form: list on the left, editor on the right.
MTGDialog = {}

--- @return Panel
function MTGDialog.Create()
    local listPanel
    local editorPanel = MTGEditorPanel.Create()
    local setupPanel = MTGSetupPanel.Create()
    local runPanel = MTGRunPanel.Create{ director = true }
    local endingPanel = MTGEndingPanel.Create{ director = true }

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

    listPanel = MTGLibraryPanel.Create(function(defid)
        if editorPanel.valid then
            editorPanel:FireEvent("setDefinition", defid)
        end
    end, function()
        m_importing = true
        importPanel:FireEvent("reset")
        rightPane:FireEvent("rebuild")
    end)

    --4:3, so the montage image renders into it cleanly here and in the
    --player view that mirrors this pane.
    rightPane = gui.Panel{
        width = 800,
        height = 600,
        flow = "vertical",
        valign = "top",

        monitorGame = MTGRun.DocPath(),
        refreshGame = function(element)
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local run = MTGRun.Active()
            local status = run ~= nil and run.status or nil
            importPanel:SetClass("collapsed", not m_importing)
            editorPanel:SetClass("collapsed", run ~= nil or m_importing)
            setupPanel:SetClass("collapsed", status ~= MTGConstants.statusSetup)
            runPanel:SetClass("collapsed", status ~= MTGConstants.statusRunning)
            endingPanel:SetClass("collapsed", status ~= MTGConstants.statusEnded)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        editorPanel,
        importPanel,
        setupPanel,
        runPanel,
        endingPanel,
    }

    local resultPanel
    resultPanel = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        classes = { "dialog" },
        width = 1220,
        height = 620,
        flow = "vertical",
        halign = "center",
        valign = "center",
        pad = 16,

        gui.Label{
            classes = { "modalTitle" },
            width = "auto",
            height = "auto",
            valign = "top",
            halign = "center",
            text = "Montages",
            tmargin = -8,
        },

        gui.Panel{
            width = "100%",
            height = "100%-40",
            flow = "horizontal",
            valign = "top",

            gui.Panel{
                width = 360,
                height = 600,
                flow = "vertical",
                valign = "top",
                rmargin = 12,
                vscroll = true,

                listPanel,
            },

            rightPane,
        },
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    return resultPanel
end

--- What the table sees. The closing report is a full-screen overlay the way
--- the end-of-combat screen is: this panel lands in the hud's documentsPanel,
--- which is already a 100% x 100% layer, so it fills the screen and dims
--- behind itself. The running board stays a windowed 4:3 pane.
--- @param args nil|{report: table|nil}
--- @return Panel|nil
function MTGDialog.CreatePlayerView(args)
    args = args or {}

    if args.report ~= nil then
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

            MTGEndingPanel.CreateCelebration(args.report),
        }

        ThemeEngine.OnThemeChanged(mod, function()
            if resultPanel ~= nil and resultPanel.valid then
                resultPanel.styles = ThemeEngine.GetStyles()
            end
        end)

        return resultPanel
    end

    if dmhub.isDM or MTGRun.Active() == nil then
        return nil
    end

    local resultPanel
    resultPanel = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        classes = { "bordered", "bg", "mtgPlayerView" },
        width = 800,
        height = 600,
        flow = "vertical",
        halign = "center",
        valign = "center",
        pad = 16,
        blurBackground = true,

        --Closing is local to this client: HidePresentedDialog would take the
        --board off everyone's screen and stop the Director's broadcast. The
        --Director's Show Players button is what brings it back.
        gui.Button{
            classes = { "closeButton", "sizeXs" },
            floating = true,
            halign = "right",
            valign = "top",
            hmargin = -12,
            tmargin = -12,
            hover = gui.Tooltip("Close. The Director can show this again."),
            press = function(element)
                element.parent:DestroySelf()
            end,
        },

        MTGRunPanel.Create{ director = false },
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    return resultPanel
end

GameHud.RegisterPresentableDialog{
    id = MTGConstants.dialogId,
    keeplocal = false,
    create = MTGDialog.CreatePlayerView,
}

LaunchablePanel.Register{
    name = MTGConstants.panelName,
    menu = "game",
    icon = "game-icons/bookmarklet.png",
    halign = "center",
    valign = "center",
    hidden = function()
        return not dmhub.isDM
    end,
    content = function()
        return MTGDialog.Create()
    end,
}
