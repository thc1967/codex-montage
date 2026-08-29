local mod = dmhub.GetModLoading()

--- Pre-flight for a Run: the limits, who takes part, and which challenges.
MTGSetupPanel = {}

--- @param text string
--- @return Panel
local function SectionHeader(text)
    return gui.Label{
        classes = { "tableLabel" },
        width = "100%",
        height = "auto",
        valign = "top",
        text = text,
    }
end

--- @param value boolean
--- @param onChange fun(included: boolean)
--- @return Panel
local function IncludeCheck(value, onChange)
    return gui.Check{
        classes = { "sizeS" },
        text = "",
        width = 30,
        minWidth = 1,
        value = value,
        halign = "left",
        valign = "center",
        change = function(element)
            onChange(element.value)
        end,
    }
end

--- @param p MTGParticipant
--- @param index number
--- @return Panel
local function ParticipantRow(p, index)
    local charid = p.charid
    local token = dmhub.GetCharacterById(charid)

    local children = {
        IncludeCheck(p.included ~= false, function(included)
            MTGRun.SetParticipantIncluded(charid, included)
        end),
    }

    if token ~= nil then
        children[#children + 1] = gui.CreateTokenImage(token, {
            width = 32,
            height = 32,
            halign = "left",
            valign = "center",
        })
    end

    children[#children + 1] = gui.Label{
        classes = { "sizeS" },
        width = "auto",
        height = "auto",
        lmargin = 8,
        halign = "left",
        valign = "center",
        text = p.name or "",
    }

    return gui.Panel{
        classes = { "row", cond(index % 2 == 1, "oddRow", "evenRow") },
        width = "100%",
        height = 38,
        flow = "horizontal",
        valign = "top",
        children = children,
    }
end

--- @param ch MTGChallengeDef
--- @param index number
--- @param included boolean
--- @return Panel
local function ChallengeRow(ch, index, included)
    local chid = ch.id

    return gui.Panel{
        classes = { "row", cond(index % 2 == 1, "oddRow", "evenRow") },
        width = "100%",
        height = 30,
        flow = "horizontal",
        valign = "top",

        IncludeCheck(included, function(inc)
            MTGRun.SetChallengeIncluded(chid, inc)
        end),

        gui.Label{
            classes = { "sizeS" },
            width = "auto",
            height = "auto",
            lmargin = 8,
            halign = "left",
            valign = "center",
            text = ch.name or "",
        },
    }
end

--- Challenges grouped under a sub-header per availability round.
--- @param run MTGRun
--- @return Panel[]
local function ChallengeRows(run)
    local byRound = {}
    local rounds = {}

    for _, ch in ipairs(run:try_get("challenges", {})) do
        local round = ch.availableFromRound or 1
        if byRound[round] == nil then
            byRound[round] = {}
            rounds[#rounds + 1] = round
        end
        local group = byRound[round]
        group[#group + 1] = ch
    end

    table.sort(rounds)

    local children = {}
    for _, round in ipairs(rounds) do
        children[#children + 1] = MTGWidgets.SubHeader(string.format("From Round %d", round))
        for i, ch in ipairs(byRound[round]) do
            children[#children + 1] = ChallengeRow(ch, i, MTGRun.IsChallengeIncluded(run, ch.id))
        end
    end

    return children
end

--- @param run MTGRun
--- @param field table a SettingsFields() entry
--- @return Panel
local function SettingField(run, field)
    return gui.Panel{
        classes = { "formStackedRow" },
        width = "30%",

        gui.Label{
            classes = { "formStacked", "sizeS" },
            text = field.text,
        },

        gui.Input{
            classes = { "formStacked", "sizeXs" },
            numeric = true,
            characterLimit = 3,
            text = tostring(MTGRun.SettingValue(run, field)),
            change = function(element)
                local n = tonumber(element.text) or field.default
                n = math.max(field.min or 1, math.floor(n))
                element.text = tostring(n)
                MTGRun.SetSetting(field.id, n)
            end,
        },
    }
end

--- The Setup half of the montage form. Its Cancel and Start go to the shell's
--- footer, so this hands them out rather than mounting them itself.
--- @return {body: Panel, footer: table[]} the pane and its footer cells
function MTGSetupPanel.Create()
    local titleLabel = gui.Label{
        classes = { "tableLabel" },
        width = "100%",
        height = "auto",
        valign = "top",
        text = "Setup",
    }

    local settingsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
    }

    local rosterPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    local challengesPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
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
            if run == nil then
                return
            end

            titleLabel.text = string.format("Setup: %s", run.name or "Montage")

            local fields = {}
            for _, field in ipairs(MTGRules.GetOrDefault(run.moduleId).SettingsFields()) do
                fields[#fields + 1] = SettingField(run, field)
            end
            settingsPanel.children = fields

            local rows = {}
            for i, p in ipairs(run:try_get("participants", {})) do
                rows[#rows + 1] = ParticipantRow(p, i)
            end
            rosterPanel.children = rows

            challengesPanel.children = ChallengeRows(run)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        titleLabel,
        settingsPanel,

        --Takes what the title and settings rows leave, so losing the button
        --row to the shell's footer gives the columns that height back.
        gui.Panel{
            width = "100%",
            height = "100% available",
            flow = "horizontal",
            valign = "top",
            tmargin = 8,

            gui.Panel{
                width = "48%",
                height = "100%",
                flow = "vertical",
                valign = "top",
                rmargin = 12,
                vscroll = true,

                SectionHeader("Challenges"),
                challengesPanel,
            },

            gui.Panel{
                width = "48%",
                height = "100%",
                flow = "vertical",
                valign = "top",
                vscroll = true,

                SectionHeader("Participants"),
                rosterPanel,
            },
        },

    }

    return {
        body = resultPanel,
        footer = {
            {
                slot = gui.Button{
                    classes = { "sizeS" },
                    text = "Cancel",
                    halign = "left",
                    valign = "center",
                    click = function()
                        MTGRun.Discard()
                    end,
                },
            },
            {},
            {
                slot = gui.Button{
                    classes = { "sizeS" },
                    text = "Start",
                    halign = "right",
                    valign = "center",
                    click = function(element)
                        MTGRun.Start()
                        MTGRun.PresentToPlayers(element)
                    end,
                },
            },
        },
    }
end
