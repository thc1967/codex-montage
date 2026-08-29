local mod = dmhub.GetModLoading()

--- Two closing surfaces: the Director's summary, where the result is settled
--- and the Victories handed out, and the celebration the whole table sees.
MTGEndingPanel = {}

--- The Director's summary. Lives in the montage dialog and reads the live Run,
--- so the result can still be changed and the Victories awarded. Nothing has
--- gone out to the table yet. The Victories, the journal check and Complete go
--- to the shell's footer, so this hands them out rather than mounting them.
--- @param opts nil|{director: boolean}
--- @return {body: Panel, footer: table[]} the summary and its footer cells
function MTGEndingPanel.Create(opts)
    opts = opts or {}
    local director = opts.director == true

    local reportPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    local degreeLabel = gui.Label{
        classes = { "sizeL" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        markdown = true,
        text = "",
    }

    local degreeDropdown = gui.Dropdown{
        classes = { "form", "collapsed" },
        width = 180,
        halign = "left",
        valign = "center",
        options = {},
        change = function(element)
            for _, option in ipairs(element.options or {}) do
                if option.id == element.idChosen then
                    MTGRun.SetEndingDegree({ id = option.id, label = option.text })
                end
            end
        end,
    }

    local trophyIcon = gui.Panel{
        classes = { "image" },
        width = 28,
        height = 28,
        halign = "left",
        valign = "center",
        rmargin = 6,
        bgimage = MTGConstants.iconVictory,
    }

    local victoryLabel = gui.Label{
        classes = { "sizeL" },
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        rmargin = 8,
        text = "Victories",
    }

    local victoryInput = gui.Input{
        classes = { "formStacked", "sizeS" },
        width = 60,
        height = 22,
        halign = "left",
        valign = "center",
        rmargin = 8,
        text = "0",
        change = function(element)
            MTGRun.SetEndingVictories(tonumber(element.text) or 0)
        end,
    }

    local journalCheck = gui.Check{
        classes = { "sizeS" },
        width = 180,
        height = 22,
        halign = "center",
        valign = "center",
        text = "Write to journal",
        value = true,
        hover = gui.Tooltip("Leave a record in Private Documents / Montage Results"),
        change = function(element)
            MTGRun.SetEndingWriteJournal(element.value)
        end,
    }

    --The three cells the shell's footer takes. victoryInput and journalCheck
    --stay locals so Complete can still read them from here.
    local victoryCell = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",

        trophyIcon,
        victoryLabel,
        victoryInput,
    }

    local completeButton = gui.Button{
        classes = { "sizeS" },
        width = 100,
        text = "Complete",
        halign = "right",
        valign = "center",
        hover = gui.Tooltip("Award the Victories, announce the result, clear the montage"),
        click = function()
            --Commit the field first: a value typed and never blurred has
            --not reached the Run yet.
            MTGRun.SetEndingVictories(tonumber(victoryInput.text) or 0)
            MTGRun.CompleteRun()
        end,
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        valign = "top",

        monitorGame = MTGRun.DocPath(),
        refreshGame = function(element)
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local run = MTGRun.Active()
            local ending = run ~= nil and run:try_get("ending") or nil
            if ending == nil then
                return
            end

            local sections = {}
            for _, section in ipairs(ending.sections or {}) do
                sections[#sections + 1] = MTGWidgets.SubHeader(section.title or "", "sizeXl")
                for _, entry in ipairs(section.entries or {}) do
                    sections[#sections + 1] = gui.Label{
                        classes = { "sizeM", "noBold" },
                        width = "100%",
                        height = "auto",
                        halign = "left",
                        valign = "top",
                        markdown = true,
                        text = string.format("- %s", entry),
                    }
                end
            end
            reportPanel.children = sections

            --Only Baseline offers a reading the Director can overrule.
            local degree = ending.degree
            local options = {}
            for _, option in ipairs(ending.degreeOptions or {}) do
                options[#options + 1] = { id = option.id, text = option.label }
            end

            local picker = #options > 0 and director
            degreeDropdown.options = options
            degreeDropdown:SetClass("collapsed", not picker)
            if degree ~= nil then
                degreeDropdown.idChosen = degree.id
            end

            --The picker already reads out the result; a label beside it would
            --just say the same thing twice.
            degreeLabel:SetClass("collapsed", degree == nil or picker)
            if degree ~= nil then
                degreeLabel.text = string.format("**Result:** %s", degree.label or "")
            end

            victoryInput.text = tostring(ending.victories or 0)
            journalCheck.value = MTGRun.EndingWritesJournal(run)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        degreeLabel,
        degreeDropdown,

        --Takes what the heading and the degree picker leave, so losing the
        --victory row to the shell's footer gives the report that height back.
        gui.Panel{
            width = "100%",
            height = "100% available",
            flow = "vertical",
            valign = "top",
            vscroll = true,

            reportPanel,
        },
    }

    return {
        body = resultPanel,
        footer = {
            { slot = cond(director, victoryCell) },
            { slot = cond(director, journalCheck) },
            { slot = cond(director, completeButton) },
        },
    }
end

--- The celebration the whole table sees once the Director is done: the award
--- and the heroes, nothing else. Renders entirely from the payload, so the Run
--- can be cleared the moment this goes out.
--- @param payload table
--- @return Panel
function MTGEndingPanel.CreateCelebration(payload)
    local ending = payload.ending or {}
    local victories = ending.victories or 0

    local children = {
        gui.Label{
            classes = { "modalTitle", "sizeXxl" },
            interactable = false,
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            text = payload.name or "Montage",
        },
    }

    if ending.degree ~= nil then
        children[#children + 1] = gui.Label{
            classes = { "sizeXl", "fgMuted" },
            interactable = false,
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            text = ending.degree.label or "",
        }
    end

    --The tally the degree was judged on, small and under it: the degree says
    --how it went, this says what it was scored from.
    if #(payload.progress or {}) > 0 then
        local parts = {}
        for _, meter in ipairs(payload.progress) do
            local value = meter.value or 0
            parts[#parts + 1] = string.format("%d %s", value,
                cond(value == 1, meter.labelOne or meter.label or "", meter.label or ""))
        end

        children[#children + 1] = gui.Label{
            classes = { "sizeS", "fgMuted" },
            interactable = false,
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "top",
            tmargin = 2,
            textAlignment = "center",
            text = table.concat(parts, "  |  "),
        }
    end

    children[#children + 1] = gui.Panel{
        interactable = false,
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "center",
        valign = "top",
        vmargin = 12,

        gui.Panel{
            classes = { "image" },
            interactable = false,
            width = 48,
            height = 48,
            halign = "left",
            valign = "center",
            rmargin = 10,
            bgimage = MTGConstants.iconVictory,
        },

        gui.Label{
            classes = { "sizeXxl" },
            interactable = false,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            text = string.format("%d %s", victories,
                cond(victories == 1, "Victory", "Victories")),
        },
    }

    local cards = {}
    for _, row in ipairs(payload.recap or {}) do
        local lines = {}
        if row.led > 0 or row.assisted > 0 then
            lines[#lines + 1] = string.format("Led %d  |  Assisted %d", row.led, row.assisted)
        else
            lines[#lines + 1] = "Stood by"
        end
        if row.bestTier ~= nil then
            lines[#lines + 1] = string.format("Best Tier %d", row.bestTier)
        end
        --Every Challenge they moved, not just the one their best roll landed
        --on: an assist that handed over an edge counts as much here as a lead.
        for _, name in ipairs(row.credits or {}) do
            lines[#lines + 1] = name
        end
        cards[#cards + 1] = MTGWidgets.RecapCard(row, lines)
    end

    children[#children + 1] = gui.Panel{
        interactable = false,
        width = "auto",
        maxWidth = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        halign = "center",
        valign = "top",
        children = cards,
    }

    children[#children + 1] = gui.Button{
        classes = { "sizeM" },
        width = 140,
        height = 36,
        text = "Close",
        halign = "center",
        valign = "top",
        vmargin = 16,
        click = function(element)
            local view = element:FindParentWithClass("mtgPlayerView")
            if view ~= nil then
                view:DestroySelf()
            end
        end,
    }

    return gui.Panel{
        width = "80%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "center",
        children = children,
    }
end
