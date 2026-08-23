local mod = dmhub.GetModLoading()

--- The montage in play.
MTGRunPanel = {}

--- @param opts nil|{director: boolean}
--- @return Panel
function MTGRunPanel.Create(opts)
    opts = opts or {}
    local director = opts.director == true

    --Expansion this client chose, by round and by challenge row. Absent means
    --"follow the default": the current round is open, earlier ones folded, and
    --a challenge folds once it has an outcome.
    local m_expanded = {}
    local m_cardExpanded = {}

    local titleLabel = gui.Label{
        classes = { "tableLabel" },
        width = "70%",
        height = "auto",
        halign = "left",
        valign = "center",
        text = "Running",
    }

    local statusLabel = gui.Label{
        classes = { "sizeXs", "noBold", "fgMuted" },
        width = "28%",
        height = "auto",
        halign = "right",
        valign = "center",
        textAlignment = "right",
        text = "",
    }

    local descriptionLabel = gui.Label{
        classes = { "sizeS", "noBold", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 4,
        markdown = true,
        textWrap = true,
        text = "",
    }

    local metersPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        vmargin = 8,
    }

    --Only the current round ever has a tray, so one pinned above the board
    --serves every round and never scrolls out from under a drag.
    local trayPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    local boardPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    local pauseButton = gui.Button{
        classes = { "sizeS" },
        text = "Pause",
        halign = "left",
        valign = "center",
        click = function(element)
            local run = MTGRun.Active()
            if run == nil then
                return
            end
            local paused = run.paused ~= true
            MTGRun.SetPaused(paused)
            if paused then
                MTGRun.HideFromPlayers()
            else
                MTGRun.PresentToPlayers(element)
            end
        end,
    }

    local advanceButton = gui.Button{
        classes = { "sizeS" },
        text = "Next Round",
        width = 100,
        halign = "right",
        valign = "center",
        hmargin = 8,
        click = function()
            MTGRun.AdvanceRound()
        end,
    }

    local resultPanel
    --"available" is measured against the parent's CONTENT area, so this fits
    --whether the host pads (the player's window) or not (the Director's pane).
    resultPanel = gui.Panel{
        width = "100%",
        height = "100% available",
        flow = "vertical",
        valign = "top",

        monitorGame = MTGRun.DocPath(),
        refreshGame = function(element)
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local run = MTGRun.Active()
            if run == nil then
                return
            end

            titleLabel.text = run.name or "Montage"
            statusLabel.text = string.format("%s  |  Round %d",
                cond(run.paused == true, "PAUSED", "In play"), run.round or 1)
            pauseButton.text = cond(run.paused == true, "Resume", "Pause")

            local description = run:try_get("description", "")
            descriptionLabel.text = description
            descriptionLabel:SetClass("collapsed", description == "")

            local meters = {}
            for _, meter in ipairs(MTGRun.Meters()) do
                meters[#meters + 1] = MTGWidgets.Meter(meter)
            end
            metersPanel.children = meters

            local rules = MTGRules.GetOrDefault(run.moduleId)
            local sections = {}

            for round = 1, run.round or 1 do
                local instances = MTGRun.InstancesForRound(run, round)

                local ordered = {}
                local byChallenge = {}
                for _, inst in ipairs(instances) do
                    local ch = MTGRun.ChallengeFor(run, inst)
                    if ch ~= nil then
                        byChallenge[ch.id] = byChallenge[ch.id] or {}
                        local bucket = byChallenge[ch.id]
                        bucket[#bucket + 1] = inst
                    end
                end
                for _, ch in ipairs(rules.SortChallenges(run, MTGRun.ActiveChallenges(run))) do
                    for _, inst in ipairs(byChallenge[ch.id] or {}) do
                        ordered[#ordered + 1] = inst
                    end
                end

                local isCurrent = round == (run.round or 1)
                local expanded = m_expanded[round]
                if expanded == nil then
                    expanded = isCurrent
                end

                local body = gui.Panel{
                    classes = { cond(not expanded, "collapsed") },
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    valign = "top",
                }

                local bodyChildren = {}
                for _, inst in ipairs(ordered) do
                    bodyChildren[#bodyChildren + 1] = MTGChallengeCard.Create(run, inst, m_cardExpanded)
                end
                body.children = bodyChildren

                --gui.CombineFields returns the new table wholesale when either
                --side is empty, so an empty classes list wipes the arrow's own
                --theme classes and it renders invisible.
                local arrowArgs = {
                    width = 16,
                    height = 16,
                    halign = "left",
                    valign = "center",
                }
                if expanded then
                    arrowArgs.classes = { "expanded" }
                end

                local thisRound = round
                arrowArgs.click = function(element)
                    local nowExpanded = not element:HasClass("expanded")
                    element:SetClass("expanded", nowExpanded)
                    m_expanded[thisRound] = nowExpanded
                    body:SetClass("collapsed", not nowExpanded)
                end
                sections[#sections + 1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    valign = "top",
                    tmargin = 8,

                    gui.ExpandoArrow(arrowArgs),

                    gui.Label{
                        classes = { "tableLabel", "sizeXs" },
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        valign = "center",
                        lmargin = 4,
                        text = string.format("Round %d", round),
                    },
                }
                sections[#sections + 1] = body
            end

            boardPanel.children = sections

            trayPanel.children = {
                MTGWidgets.Tray(MTGRun.TrayParticipants(run, run.round or 1), function(charid)
                    MTGRun.UnstageParticipant(charid)
                end),
            }
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            titleLabel,
            statusLabel,
        },

        descriptionLabel,

        metersPanel,

        trayPanel,

        --Takes whatever the rows above and the footer below leave, so the
        --description growing costs the board height instead of pushing the
        --footer off the bottom.
        gui.Panel{
            width = "100%",
            height = "100% available",
            flow = "vertical",
            valign = "top",
            vscroll = true,

            boardPanel,
        },

        gui.Panel{
            classes = { cond(not director, "collapsed") },
            width = "100%",
            height = 40,
            flow = "horizontal",
            valign = "bottom",

            pauseButton,

            gui.Button{
                classes = { "sizeS" },
                text = "Reset",
                halign = "left",
                valign = "center",
                hmargin = 8,
                hover = gui.Tooltip("Throw away every roll and go back to setup"),
                click = function()
                    MTGRun.HideFromPlayers()
                    MTGRun.Reset()
                end,
            },

            --Anything else presented to the table evicts this board from the
            --players' screens, and re-presenting on our own would race the
            --thing that evicted it.
            gui.Button{
                classes = { "sizeS" },
                -- styles = { width = 80, priority = 50 },
                width = 100,
                text = "Show Players",
                halign = "left",
                valign = "center",
                hover = gui.Tooltip("Put the board back on the players' screens"),
                click = function(element)
                    MTGRun.PresentToPlayers(element)
                end,
            },

            advanceButton,

            gui.Button{
                classes = { "sizeS" },
                text = "End",
                halign = "right",
                valign = "center",
                hover = gui.Tooltip("Close the montage and review the result"),
                click = function()
                    MTGRun.HideFromPlayers()
                    MTGRun.EndRun()
                end,
            },
        },
    }

    return resultPanel
end
