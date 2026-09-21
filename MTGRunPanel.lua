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

    --Absent means "follow the default", so nil and false differ.
    local m_expanded = {}
    local m_cardExpanded = {}

    --Seeded silently on the first build so an existing board does not float everything.
    local m_seenChallenges = nil
    local m_pinned = {}

    --Held as data, not a panel: a refresh mid-edit would strand the panel.
    local m_draft = nil

    local m_description = nil

    --The fold is this client's own, and every open starts unfolded.
    local m_descriptionOpen = true

    local descriptionLabel = gui.Label{
        classes = { "sizeS", "noBold" },
        width = "100%-40",
        height = "auto",
        halign = "left",
        valign = "top",
        markdown = true,
        textWrap = true,
        text = "",
    }

    --A well of fixed height, so the description costs the board a known
    --amount whether it runs to one line or forty.
    local descriptionWell = gui.Panel{
        width = "100%-20",
        height = MTGConstants.descriptionLineHeight * MTGConstants.descriptionLinesOpen,
        flow = "vertical",
        halign = "left",
        valign = "top",
        vscroll = true,

        descriptionLabel,
    }

    local descriptionArrow = gui.ExpandoArrow{
        classes = { "bgFg", "expanded" },
        width = 10,
        height = 10,
        halign = "left",
        valign = "top",
        lmargin = -4,
        rmargin = 4,
        tmargin = 4,
        click = function(element)
            m_descriptionOpen = not element:HasClass("expanded")
            element:SetClass("expanded", m_descriptionOpen)
            descriptionWell.selfStyle.height = MTGConstants.descriptionLineHeight
                * cond(m_descriptionOpen, MTGConstants.descriptionLinesOpen, 1)
        end,
    }

    local descriptionPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tmargin = 4,

        descriptionArrow,
        descriptionWell,
    }

    local metersPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        vmargin = 8,
    }

    --The fold is this client's own; the document carries none of it.
    local m_ladderOpen = false
    local m_ladderText = {}

    --The eye cannot be read back off the button.
    local m_ladderEyeShown = nil

    local ladderLines = {}
    local ladderRungs = {}
    for _, rung in ipairs(MTGConstants.ladderRungs) do
        local line = gui.Label{
            classes = { "sizeS", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            tmargin = 2,
            markdown = true,
            textWrap = true,
            text = "",
        }
        ladderLines[rung.id] = line
        ladderRungs[#ladderRungs + 1] = line
    end

    local ladderBody = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        children = ladderRungs,
    }

    local ladderArrow = gui.ExpandoArrow{
        classes = { "bgFg" },
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        click = function(element)
            m_ladderOpen = not element:HasClass("expanded")
            element:SetClass("expanded", m_ladderOpen)
            ladderBody:SetClass("collapsed", not m_ladderOpen)
        end,
    }

    --Built bare: hover cannot be re-assigned, so the tooltip is patched.
    local ladderEye = director and gui.Button{
        classes = { "sizeXs" },
        icon = "phosphor/eye-slash-duotone.png",
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        lmargin = 6,
        click = function()
            local run = MTGRun.Active()
            if run ~= nil then
                MTGRun.SetLadderShown(run:try_get("successLadderShown", false) ~= true)
            end
        end,
    } or nil

    local ladderPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        vmargin = 4,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            ladderArrow,

            gui.Label{
                classes = { "tableLabel", "sizeXs" },
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                lmargin = 4,
                text = "Success Ladder",
            },

            ladderEye,
        },

        ladderBody,
    }

    --Pinned above the board so it never scrolls out from under a drag.
    local tray = MTGWidgets.Tray(function(charid)
        MTGRun.UnstageParticipant(charid)
    end)

    local trayPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        tray,
    }

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

    --- One test: everyone who worked it, what it was, and how it came out.
    --- Built once and handed a test with `setSummary`; handed nil, it
    --- collapses. The badge is the module's own, so this reads the same as
    --- the board's rows.
    --- @return Panel
    local function SummaryRow()
        local shown = { tone = "bgFg" }

        local tokens = gui.Panel{
            width = 96,
            height = "100%",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            lmargin = 8,
        }

        local nameLabel = gui.Label{
            classes = { "sizeM" },
            width = "100% available",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 8,
            textWrap = true,
            text = "",
        }

        local badge = gui.Panel{
            classes = { "bgFg" },
            width = 20,
            height = 20,
            halign = "right",
            valign = "center",
            rmargin = 12,
            bgimage = MTGConstants.iconPending,
        }

        return gui.Panel{
            classes = { "row" },
            width = "100%",
            height = 48,
            flow = "horizontal",
            halign = "left",
            valign = "top",

            --- @param item nil|{run: MTGRun, inst: table, ch: MTGChallengeDef, rules: table}
            setSummary = function(element, item)
                element:SetClass("collapsed", item == nil)
                if item == nil then
                    return
                end

                local entries = {}
                if item.inst.lead ~= nil then
                    entries[#entries + 1] = { p = item.inst.lead, lead = true }
                end
                if item.inst.assist ~= nil then
                    entries[#entries + 1] = { p = item.inst.assist, lead = false }
                end
                THCWidgets.BindList(tokens, entries, function()
                    return MTGWidgets.Slot{
                        setToken = function(slot, entry)
                            local state = ""
                            if entry ~= nil then
                                state = entry.p.charid .. "|" .. tostring(entry.lead)
                            end
                            MTGWidgets.SetSlot(slot, state, function()
                                return SummaryToken(entry.p, entry.lead)
                            end)
                        end,
                    }
                end, "setToken")

                local name = item.ch.name or ""
                if shown.name ~= name then
                    shown.name = name
                    nameLabel.text = name
                end

                local status = item.rules.ChallengeStatus(item.run, item.inst, item.ch)
                if shown.icon ~= status.icon then
                    shown.icon = status.icon
                    badge.bgimage = status.icon
                end
                shown.tone = MTGWidgets.SwapClass(badge, shown.tone, MTGWidgets.ToneClass(status.tone))
                local tip = status.tooltip or ""
                if shown.tip ~= tip then
                    shown.tip = tip
                    badge.tooltip = THCWidgets.Tooltip(tip)
                end
            end,

            tokens,
            nameLabel,
            badge,
        }
    end

    --- Every test the table attempted, in the order the board showed them:
    --- round by round, and within a round the module's own sort.
    --- @param run MTGRun
    --- @return table[] setSummary items
    local function SummaryItems(run)
        local rules = MTGRules.GetOrDefault(run.moduleId)
        local items = {}

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
                    --Attempted means resolved; a hidden one was never on the table's board.
                    if inst.outcome ~= nil
                        and not MTGRun.IsChallengeHidden(run, inst.challengeId) then
                        items[#items + 1] = { run = run, inst = inst, ch = ch, rules = rules }
                    end
                end
            end
        end

        return items
    end

    local summaryPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "100% available",
        flow = "vertical",
        valign = "top",
        vscroll = true,
    }

    --The description growing costs board height, not the footer.
    local boardScroll = gui.Panel{
        width = "100%",
        height = "100% available",
        flow = "vertical",
        valign = "top",
        vscroll = true,

        boardPanel,
    }

    --Built only for the Director: an unparented panel is a leak the engine warns about.
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

    --- One round's header over the body its cards go in. Built once for its
    --- position, which is its round, and handed the round's rows with
    --- `setRound`; handed nil, it collapses and waits for the round.
    --- @param round number
    --- @return Panel
    local function BuildSection(round)
        local cards = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "top",
        }

        local draftSlot = MTGWidgets.Slot{ width = "100%" }

        local body = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "top",

            draftSlot,
            cards,
        }

        --No classes key: an empty list wipes ExpandoArrow's own theme classes.
        local arrow = gui.ExpandoArrow{
            width = 16,
            height = 16,
            halign = "left",
            valign = "center",
            click = function(element)
                local nowExpanded = not element:HasClass("expanded")
                element:SetClass("expanded", nowExpanded)
                m_expanded[round] = nowExpanded
                body:SetClass("collapsed", not nowExpanded)
            end,
        }

        local headerChildren = {
            arrow,

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

        local addButton = nil
        if director then
            addButton = gui.Button{
                classes = { "addButton", "sizeXs" },
                halign = "right",
                valign = "center",
                --Clear of the board's scrollbar.
                rmargin = 20,
                hover = THCWidgets.Tooltip("Add a challenge"),
                click = function()
                    if m_draft ~= nil then
                        return
                    end
                    m_draft = MTGChallengeDef.CreateNew{
                        name = "",
                        description = "",
                        availableFromRound = round,
                        repeatable = 0,
                    }
                    resultPanel:FireEvent("rebuild")
                end,
            }
            headerChildren[#headerChildren + 1] = addButton
        end

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "top",

            --- @param entry nil|{run: MTGRun, isCurrent: boolean, items: table[]}
            setRound = function(element, entry)
                element:SetClass("collapsed", entry == nil)
                if entry == nil then
                    return
                end

                local run = entry.run

                local expanded = m_expanded[round]
                if expanded == nil then
                    expanded = entry.isCurrent
                end
                arrow:SetClass("expanded", expanded)
                body:SetClass("collapsed", not expanded)

                if addButton ~= nil then
                    addButton:SetClass("collapsed", not entry.isCurrent)
                end

                local draft = entry.isCurrent and m_draft or nil
                MTGWidgets.SetSlot(draftSlot, cond(draft ~= nil, "draft", ""), function()
                    return MTGEditorPanel.DraftCard(draft, run.moduleId,
                        function(d)
                            m_draft = nil
                            MTGRun.AddChallengeAtRuntime(d)
                        end,
                        function()
                            m_draft = nil
                            resultPanel:FireEvent("rebuild")
                        end)
                end)

                THCWidgets.BindList(cards, entry.items, function()
                    return MTGChallengeCard.Create(director, m_cardExpanded)
                end, "setRow")
            end,

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                valign = "top",
                tmargin = 8,
                children = headerChildren,
            },

            body,
        }
    end

    --"available" measures the parent's CONTENT area, so it fits a padded host too.
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

            --The Director keeps the board after the end; they are still working on it.
            local reviewing = not director
                and run.status == MTGConstants.statusEnded
            summaryPanel:SetClass("collapsed", not reviewing)
            boardScroll:SetClass("collapsed", reviewing)
            trayPanel:SetClass("collapsed", reviewing)
            finalizingLabel:SetClass("collapsed", not reviewing)
            if reviewing then
                THCWidgets.BindList(summaryPanel, SummaryItems(run), SummaryRow, "setSummary")
            end

            if pauseButton ~= nil then
                pauseButton.text = cond(run.paused == true, "Resume", "Pause")
            end

            local description = run:try_get("description", "")
            if m_description ~= description then
                m_description = description
                descriptionLabel.text = description
                descriptionPanel:SetClass("collapsed", description == "")
            end

            THCWidgets.BindList(metersPanel, MTGRun.Meters(), MTGWidgets.Meter, "setMeter")

            --Re-asserted, not reset: a document write must not snap an opened ladder shut.
            local showLadder = run.moduleId == MTGConstants.moduleBaseline
                and (director or run:try_get("successLadderShown", false) == true)
            ladderPanel:SetClass("collapsed", not showLadder)
            ladderBody:SetClass("collapsed", not m_ladderOpen)
            if showLadder then
                for _, rung in ipairs(MTGConstants.ladderRungs) do
                    local prose = MTGRun.LadderText(run, rung.id)
                    local line = ladderLines[rung.id]

                    --An unwritten rung is worth seeing on the Director's board, not the table's.
                    line:SetClass("collapsed", prose == "" and not director)

                    local text = string.format("**%s:** %s", rung.text,
                        cond(prose == "", "Not set.", prose))
                    if m_ladderText[rung.id] ~= text then
                        m_ladderText[rung.id] = text
                        line.text = text
                    end
                end

                if ladderEye ~= nil then
                    local shown = run:try_get("successLadderShown", false) == true
                    if m_ladderEyeShown ~= shown then
                        m_ladderEyeShown = shown
                        ladderEye:FireEvent("setIcon", cond(shown,
                            "phosphor/eye-bold.png", "phosphor/eye-slash-duotone.png"))
                        ladderEye.tooltip = THCWidgets.Tooltip(cond(shown,
                            "The table can read the ladder. Press to keep it back.",
                            "Kept from the table. Press to show it."))
                    end
                end
            end

            local rules = MTGRules.GetOrDefault(run.moduleId)

            --Keyed by challenge: a round advance seeds instances that would all look new.
            if m_seenChallenges == nil then
                m_seenChallenges = {}
                for _, ch in ipairs(run:try_get("challenges", {})) do
                    m_seenChallenges[ch.id] = true
                end
            else
                for _, ch in ipairs(run:try_get("challenges", {})) do
                    if not m_seenChallenges[ch.id] then
                        m_seenChallenges[ch.id] = true
                        --One authored for a later round is not a mid-run addition.
                        if (ch.availableFromRound or 1) == (run.round or 1) then
                            m_pinned[ch.id] = true
                        end
                    end
                end
            end

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

                --A hidden Challenge is absent from the players' board, not greyed.
                local items = {}
                for _, inst in ipairs(ordered) do
                    if director or not MTGRun.IsChallengeHidden(run, inst.challengeId) then
                        items[#items + 1] = {
                            run = run,
                            inst = inst,
                            pinned = m_pinned[inst.challengeId] == true,
                        }
                    end
                end

                sections[round] = {
                    run = run,
                    isCurrent = round == (run.round or 1),
                    items = items,
                }
            end

            THCWidgets.BindList(boardPanel, sections, BuildSection, "setRound")

            local free = MTGRun.TrayParticipants(run, run.round or 1)
            local tokens = {}
            for _, p in ipairs(free) do
                tokens[#tokens + 1] = {
                    p = p,
                    dimmed = MTGRun.HasActedThisRound(run, p.charid),
                }
            end
            tray:FireEvent("setTray", tokens)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        descriptionPanel,

        metersPanel,

        ladderPanel,

        trayPanel,
        finalizingLabel,

        boardScroll,
        summaryPanel,
    }

    if not director then
        return { body = resultPanel }
    end

    --They stay locals so rebuild updates them wherever the shell mounts them.
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
            hover = THCWidgets.Tooltip("Throw away every roll and go back to setup"),
            click = function()
                MTGRun.HideFromPlayers()
                MTGRun.Reset()
            end,
        },

        --Re-presenting automatically would race whatever evicted the board.
        gui.Button{
            classes = { "sizeL" },
            width = 100,
            text = "Show Players",
            halign = "left",
            valign = "center",
            hover = THCWidgets.Tooltip("Put the board back on the players' screens"),
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
            hover = THCWidgets.Tooltip("Close the montage and review the result"),
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
