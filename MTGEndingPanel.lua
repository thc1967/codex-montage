local mod = dmhub.GetModLoading()

--- Two closing surfaces: the Director's summary, where the result is settled
--- and the Victories handed out, and the celebration the whole table sees.
MTGEndingPanel = {}

--- One line of the report: a section's title or one of its entries. Built
--- once as a slot and handed a line with `setLine`; the label inside is
--- remade only when the line's kind or text moves, which after the ending is
--- written is never.
--- @return Panel
local function ReportLine()
    return MTGWidgets.Slot{
        width = "100%",
        --- @param line nil|{kind: string, text: string}
        setLine = function(slot, line)
            local state = ""
            if line ~= nil then
                state = line.kind .. "|" .. line.text
            end
            MTGWidgets.SetSlot(slot, state, function()
                if line.kind == "header" then
                    return THCWidgets.SubHeader(line.text, "sizeXl")
                end
                return gui.Label{
                    classes = { "sizeM", "noBold" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    valign = "top",
                    markdown = true,
                    text = string.format("- %s", line.text),
                }
            end)
        end,
    }
end

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

    local m_degreeText = nil

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

    local m_ladderProse = nil

    local ladderLine = gui.Label{
        classes = { "sizeM", "noBold", "fgMuted", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 2,
        bmargin = 4,
        markdown = true,
        textWrap = true,
        text = "",
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
        halign = "left",
        valign = "center",
        text = "Write to journal",
        value = true,
        hover = THCWidgets.Tooltip("Leave a record in Private Documents / Montage Results"),
        change = function(element)
            MTGRun.SetEndingWriteJournal(element.value)
        end,
    }

    local victoryCell = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        bmargin = 6,

        trophyIcon,
        victoryLabel,
        victoryInput,
    }

    local endingControls = gui.Panel{
        classes = { cond(not director, "collapsed") },
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        vmargin = 8,

        victoryCell,
        journalCheck,
    }

    local completeButton = gui.Button{
        classes = { "sizeL" },
        width = 100,
        text = "Complete",
        halign = "right",
        valign = "center",
        hover = THCWidgets.Tooltip("Award the Victories, announce the result, clear the montage"),
        click = function()
            --A value typed and never blurred has not reached the Run yet.
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

            local lines = {}
            for _, section in ipairs(ending.sections or {}) do
                lines[#lines + 1] = { kind = "header", text = section.title or "" }
                for _, entry in ipairs(section.entries or {}) do
                    lines[#lines + 1] = { kind = "entry", text = entry }
                end
            end
            THCWidgets.BindList(reportPanel, lines, ReportLine, "setLine")

            local degree = ending.degree
            local options = {}
            for _, option in ipairs(ending.degreeOptions or {}) do
                options[#options + 1] = { id = option.id, text = option.label }
            end

            local picker = #options > 0 and director
            if not dmhub.DeepEqual(degreeDropdown.options, options) then
                degreeDropdown.options = options
            end
            degreeDropdown:SetClass("collapsed", not picker)
            if degree ~= nil and degreeDropdown.idChosen ~= degree.id then
                degreeDropdown.idChosen = degree.id
            end

            --The picker already reads out the result.
            degreeLabel:SetClass("collapsed", degree == nil or picker)
            if degree ~= nil then
                local text = string.format("**Result:** %s", degree.label or "")
                if m_degreeText ~= text then
                    m_degreeText = text
                    degreeLabel.text = text
                end
            end

            local prose = degree ~= nil and MTGRun.LadderText(run, degree.id) or ""
            ladderLine:SetClass("collapsed", prose == "")
            if m_ladderProse ~= prose then
                m_ladderProse = prose
                ladderLine.text = prose
            end

            local victories = tostring(ending.victories or 0)
            if victoryInput.text ~= victories then
                victoryInput.text = victories
            end
            local write = MTGRun.EndingWritesJournal(run)
            if journalCheck.value ~= write then
                journalCheck.value = write
            end
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        degreeLabel,
        degreeDropdown,
        ladderLine,
        endingControls,

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
            {},
            {},
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

    --One line of "3 Successes  |  1 Failure", or nothing when no meter moved.
    local stats = ""
    if #(payload.progress or {}) > 0 then
        local parts = {}
        for _, meter in ipairs(payload.progress) do
            local value = meter.value or 0
            parts[#parts + 1] = string.format("%d %s", value,
                cond(value == 1, meter.labelOne or meter.label or "", meter.label or ""))
        end
        stats = table.concat(parts, "  |  ")
    end

    return THCWidgets.Celebration{
        title = payload.name or "Montage",
        subtitle = ending.degree ~= nil and ending.degree.label or "",
        detail = payload.ladder or "",
        stats = stats,
        victories = ending.victories or 0,
        icon = MTGConstants.iconVictory,
        recap = payload.recap,

        RecapLines = function(row)
            local lines = {}
            if row.led > 0 or row.assisted > 0 then
                lines[#lines + 1] = string.format("Led %d  |  Assisted %d", row.led, row.assisted)
            else
                lines[#lines + 1] = "Stood by"
            end
            if row.bestTier ~= nil then
                lines[#lines + 1] = string.format("Best Tier %d", row.bestTier)
            end
            for _, name in ipairs(row.credits or {}) do
                lines[#lines + 1] = name
            end
            return lines
        end,
    }
end
