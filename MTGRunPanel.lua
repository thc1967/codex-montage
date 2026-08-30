local mod = dmhub.GetModLoading()

--- The montage in play.
MTGRunPanel = {}

--- The Director's controls go to the shell's footer, so this hands them out
--- rather than mounting them itself. The player's board has no footer.
--- @param opts nil|{director: boolean}
--- @return {body: Panel, footer: table[]} the board and its footer cells
function MTGRunPanel.Create(opts)
    opts = opts or {}
    local director = opts.director == true

    --Expansion this client chose, by round and by challenge row. Absent means
    --"follow the default": the current round is open, earlier ones folded, and
    --a challenge folds once it has an outcome.
    local m_expanded = {}
    local m_cardExpanded = {}

    --Challenges this board has already drawn. Seeded silently on the first
    --build, so a board opened later sorts normally; anything that turns up
    --after that is something the Director has just presented, and it floats to
    --the top of its round until this client closes the board.
    local m_seenChallenges = nil
    local m_pinned = {}

    --The run-time challenge being authored. Director side only, and held as
    --data rather than as a panel so a document refresh mid-edit cannot strand
    --it in a body that is about to be replaced.
    local m_draft = nil

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

    --Stands where the tray does while the table waits on the Director.
    local finalizingLabel = gui.Label{
        classes = { "sizeL", "noBold", "fgMuted", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "top",
        textAlignment = "center",
        vmargin = 8,
        text = "The Director is finalizing the montage...",
    }

    local boardPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    --- A participant's portrait, crowned when they led the test. The crown
    --- floats over the corner rather than taking a column of its own.
    --- @param p MTGParticipant
    --- @param lead boolean
    --- @return Panel|nil
    local function SummaryToken(p, lead)
        local portrait = MTGWidgets.ParticipantToken(p, false, nil, false)
        if portrait == nil then
            return nil
        end

        if not lead then
            return portrait
        end

        return gui.Panel{
            width = 44,
            height = 40,
            flow = "none",
            halign = "left",
            valign = "center",

            portrait,

            gui.Panel{
                classes = { "bgAccent" },
                floating = true,
                interactable = false,
                width = 16,
                height = 16,
                halign = "right",
                valign = "top",
                bgimage = "phosphor/crown-duotone.png",
            },
        }
    end

    --- One test: everyone who worked it, what it was, and how it came out. The
    --- badge is the module's own, so this reads the same as the board's rows.
    --- @param run MTGRun
    --- @param inst table
    --- @param rules table the run's rules module
    --- @return Panel|nil
    local function SummaryRow(run, inst, rules)
        local ch = MTGRun.ChallengeFor(run, inst)
        if ch == nil then
            return nil
        end

        local tokens = {}
        if inst.lead ~= nil then
            tokens[#tokens + 1] = SummaryToken(inst.lead, true)
        end
        if inst.assist ~= nil then
            tokens[#tokens + 1] = SummaryToken(inst.assist, false)
        end

        local status = rules.ChallengeStatus(run, inst, ch)

        return gui.Panel{
            classes = { "row" },
            width = "100%",
            height = 48,
            flow = "horizontal",
            halign = "left",
            valign = "top",

            gui.Panel{
                width = 96,
                height = "100%",
                flow = "horizontal",
                halign = "left",
                valign = "center",
                lmargin = 8,

                children = tokens,
            },

            gui.Label{
                classes = { "sizeM" },
                width = "100% available",
                height = "auto",
                halign = "left",
                valign = "center",
                lmargin = 8,
                textWrap = true,
                text = ch.name or "",
            },

            gui.Panel{
                classes = { MTGWidgets.ToneClass(status.tone) },
                width = 20,
                height = 20,
                halign = "right",
                valign = "center",
                rmargin = 12,
                bgimage = status.icon,
                hover = gui.Tooltip(status.tooltip or ""),
            },
        }
    end

    --- Every test the table attempted, in the order the board showed them:
    --- round by round, and within a round the module's own sort.
    --- @param run MTGRun
    --- @return Panel[]
    local function SummaryRows(run)
        local rules = MTGRules.GetOrDefault(run.moduleId)
        local rows = {}

        for round = 1, run.round or 1 do
            local byChallenge = {}
            for _, inst in ipairs(MTGRun.InstancesForRound(run, round)) do
                local ch = MTGRun.ChallengeFor(run, inst)
                if ch ~= nil then
                    byChallenge[ch.id] = byChallenge[ch.id] or {}
                    local bucket = byChallenge[ch.id]
                    bucket[#bucket + 1] = inst
                end
            end

            for _, ch in ipairs(rules.SortChallenges(run, MTGRun.ActiveChallenges(run))) do
                for _, inst in ipairs(byChallenge[ch.id] or {}) do
                    --Attempted means resolved: an untouched Challenge has
                    --nothing to report, and a hidden one was never on the
                    --table's board to begin with.
                    if inst.outcome ~= nil
                        and not MTGRun.IsChallengeHidden(run, inst.challengeId) then
                        rows[#rows + 1] = SummaryRow(run, inst, rules)
                    end
                end
            end
        end

        return rows
    end

    --What the table reads once the Director ends the montage: every test they
    --attempted, in board order, with who led and how it came out.
    local summaryPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "100% available",
        flow = "vertical",
        valign = "top",
        vscroll = true,
    }

    --Takes whatever the rows above and the footer below leave, so the
    --description growing costs the board height instead of pushing the footer
    --off the bottom. Swaps with the summary once the montage is over.
    local boardScroll = gui.Panel{
        width = "100%",
        height = "100% available",
        flow = "vertical",
        valign = "top",
        vscroll = true,

        boardPanel,
    }

    --Director-only, and built only for them: the player's board has no footer
    --to mount these in, and a panel nothing parents is a leak the engine
    --complains about at creation.
    local pauseButton = director and gui.Button{
        classes = { "sizeL" },
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
    } or nil

    local advanceButton = director and gui.Button{
        classes = { "sizeL" },
        text = "Next Round",
        width = 100,
        halign = "right",
        valign = "center",
        hmargin = 8,
        click = function()
            MTGRun.AdvanceRound()
        end,
    } or nil

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

            --The table reads the summary once the montage is over; the
            --Director keeps the board, since they are still working on it.
            local reviewing = not director
                and run.status == MTGConstants.statusEnded
            summaryPanel:SetClass("collapsed", not reviewing)
            boardScroll:SetClass("collapsed", reviewing)
            --The tray is for staging heroes, which is over: the notice takes
            --its place rather than leaving a gap.
            trayPanel:SetClass("collapsed", reviewing)
            finalizingLabel:SetClass("collapsed", not reviewing)
            if reviewing then
                summaryPanel.children = SummaryRows(run)
            end

            if pauseButton ~= nil then
                pauseButton.text = cond(run.paused == true, "Resume", "Pause")
            end

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

            --Keyed by challenge rather than by instance: a round advance seeds
            --a batch of new instances, and every one of them would otherwise
            --look like something the Director had just added.
            if m_seenChallenges == nil then
                m_seenChallenges = {}
                for _, ch in ipairs(run:try_get("challenges", {})) do
                    m_seenChallenges[ch.id] = true
                end
            else
                for _, ch in ipairs(run:try_get("challenges", {})) do
                    if not m_seenChallenges[ch.id] then
                        m_seenChallenges[ch.id] = true
                        --One authored for a later round is just another
                        --challenge when its round comes around.
                        if (ch.availableFromRound or 1) == (run.round or 1) then
                            m_pinned[ch.id] = true
                        end
                    end
                end
            end

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

                local floated = {}
                for _, inst in ipairs(ordered) do
                    if m_pinned[inst.challengeId] then
                        floated[#floated + 1] = inst
                    end
                end
                for _, inst in ipairs(ordered) do
                    if not m_pinned[inst.challengeId] then
                        floated[#floated + 1] = inst
                    end
                end
                ordered = floated

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
                if isCurrent and m_draft ~= nil then
                    bodyChildren[#bodyChildren + 1] = MTGEditorPanel.DraftCard(m_draft, run.moduleId,
                        function(draft)
                            m_draft = nil
                            MTGRun.AddChallengeAtRuntime(draft)
                        end,
                        function()
                            m_draft = nil
                            resultPanel:FireEvent("rebuild")
                        end)
                end
                --The reveal IS the card appearing: a hidden Challenge is absent
                --from the players' board rather than shown greyed out.
                for _, inst in ipairs(ordered) do
                    if director or not MTGRun.IsChallengeHidden(run, inst.challengeId) then
                        bodyChildren[#bodyChildren + 1] = MTGChallengeCard.Create(run, inst, m_cardExpanded,
                            director, m_pinned[inst.challengeId] == true)
                    end
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
                local headerChildren = {
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

                if director and isCurrent then
                    headerChildren[#headerChildren + 1] = gui.Button{
                        classes = { "addButton", "sizeXs" },
                        halign = "right",
                        valign = "center",
                        --Clear of the board's scrollbar.
                        rmargin = 20,
                        hover = gui.Tooltip("Add a challenge"),
                        click = function()
                            if m_draft ~= nil then
                                return
                            end
                            m_draft = MTGChallengeDef.CreateNew{
                                name = "",
                                description = "",
                                availableFromRound = run.round or 1,
                                repeatable = 0,
                            }
                            resultPanel:FireEvent("rebuild")
                        end,
                    }
                end

                sections[#sections + 1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    valign = "top",
                    tmargin = 8,
                    children = headerChildren,
                }
                sections[#sections + 1] = body
            end

            boardPanel.children = sections

            trayPanel.children = {
                MTGWidgets.Tray(run, MTGRun.TrayParticipants(run, run.round or 1), function(charid)
                    MTGRun.UnstageParticipant(charid)
                end),
            }
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        descriptionLabel,

        metersPanel,

        trayPanel,
        finalizingLabel,

        boardScroll,
        summaryPanel,
    }

    if not director then
        return { body = resultPanel }
    end

    --Handed to the shell rather than mounted here: pauseButton and
    --advanceButton stay locals so rebuild keeps updating them wherever they
    --end up sitting.
    local leftGroup = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",

        pauseButton,

        gui.Button{
            classes = { "sizeL" },
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
            classes = { "sizeL" },
            width = 100,
            text = "Show Players",
            halign = "left",
            valign = "center",
            hover = gui.Tooltip("Put the board back on the players' screens"),
            click = function(element)
                MTGRun.PresentToPlayers(element)
            end,
        },
    }

    local rightGroup = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",

        advanceButton,

        gui.Button{
            classes = { "sizeL" },
            text = "End",
            halign = "right",
            valign = "center",
            hover = gui.Tooltip("Close the montage and review the result"),
            click = function()
                --The board stays up, curtained, until Complete.
                MTGRun.EndRun()
            end,
        },
    }

    return {
        body = resultPanel,
        footer = {
            { slot = leftGroup, width = MTGConstants.footerCellsRun[1] },
            { slot = rightGroup, width = MTGConstants.footerCellsRun[2] },
        },
    }
end
