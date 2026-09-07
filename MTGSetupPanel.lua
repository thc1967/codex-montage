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

--- @param onChange fun(included: boolean)
--- @return Panel
local function IncludeCheck(onChange)
    return gui.Check{
        classes = { "sizeS" },
        text = "",
        width = 30,
        minWidth = 1,
        value = true,
        halign = "left",
        valign = "center",
        change = function(element)
            onChange(element.value)
        end,
    }
end

--- A participant's row. Built once and handed a participant with
--- `setParticipant`; handed nil, it collapses. The portrait is fixed at
--- construction, so it sits in a slot remade when the participant changes.
--- @return Panel
local function ParticipantRow()
    local bound = {}
    local shown = {}

    local check = IncludeCheck(function(included)
        MTGRun.SetParticipantIncluded(bound.charid, included)
    end)

    local portraitSlot = MTGWidgets.Slot{}

    local nameLabel = gui.Label{
        classes = { "sizeS" },
        width = "auto",
        height = "auto",
        lmargin = 8,
        halign = "left",
        valign = "center",
        text = "",
    }

    return gui.Panel{
        classes = { "row" },
        width = "100%",
        height = 38,
        flow = "horizontal",
        valign = "top",

        --- @param item nil|{p: MTGParticipant, index: number}
        setParticipant = function(element, item)
            element:SetClass("collapsed", item == nil)
            if item == nil then
                return
            end

            local p = item.p
            bound.charid = p.charid
            element:SetClass("oddRow", item.index % 2 == 1)
            element:SetClass("evenRow", item.index % 2 == 0)

            local included = p.included ~= false
            if check.value ~= included then
                check.value = included
            end

            MTGWidgets.SetSlot(portraitSlot, p.charid, function()
                local token = dmhub.GetCharacterById(p.charid)
                if token == nil then
                    return nil
                end
                return gui.CreateTokenImage(token, {
                    width = 32,
                    height = 32,
                    halign = "left",
                    valign = "center",
                })
            end)

            local name = p.name or ""
            if shown.name ~= name then
                shown.name = name
                nameLabel.text = name
            end
        end,

        check,
        portraitSlot,
        nameLabel,
    }
end

--- A challenge's row. Built once and handed a challenge with
--- `setChallenge`; handed nil, it collapses.
--- @return Panel
local function ChallengeRow()
    local bound = {}
    local shown = {}

    local check = IncludeCheck(function(included)
        MTGRun.SetChallengeIncluded(bound.chid, included)
    end)

    local nameLabel = gui.Label{
        classes = { "sizeS" },
        width = "auto",
        height = "auto",
        lmargin = 8,
        halign = "left",
        valign = "center",
        text = "",
    }

    return gui.Panel{
        classes = { "row" },
        width = "100%",
        height = 30,
        flow = "horizontal",
        valign = "top",

        --- @param item nil|{ch: MTGChallengeDef, index: number, included: boolean}
        setChallenge = function(element, item)
            element:SetClass("collapsed", item == nil)
            if item == nil then
                return
            end

            bound.chid = item.ch.id
            element:SetClass("oddRow", item.index % 2 == 1)
            element:SetClass("evenRow", item.index % 2 == 0)

            if check.value ~= item.included then
                check.value = item.included
            end

            local name = item.ch.name or ""
            if shown.name ~= name then
                shown.name = name
                nameLabel.text = name
            end
        end,

        check,
        nameLabel,
    }
end

--- One availability round: its sub-header over the rows of the challenges
--- that open then. Built once and handed a group with `setGroup`.
--- @return Panel
local function RoundGroup()
    local shown = {}

    local header = MTGWidgets.SubHeader("")

    local rows = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        --- @param group nil|{round: number, items: table[]}
        setGroup = function(element, group)
            element:SetClass("collapsed", group == nil)
            if group == nil then
                return
            end

            local text = string.format("From Round %d", group.round)
            if shown.text ~= text then
                shown.text = text
                header.text = text
            end
            MTGWidgets.BindList(rows, group.items, ChallengeRow, "setChallenge")
        end,

        header,
        rows,
    }
end

--- Challenges grouped by availability round, in round order.
--- @param run MTGRun
--- @return {round: number, items: table[]}[] setGroup entries
local function ChallengeGroups(run)
    local byRound = {}
    local rounds = {}

    for _, ch in ipairs(run:try_get("challenges", {})) do
        local round = ch.availableFromRound or 1
        if byRound[round] == nil then
            byRound[round] = {}
            rounds[#rounds + 1] = round
        end
        local group = byRound[round]
        group[#group + 1] = {
            ch = ch,
            index = #group + 1,
            included = MTGRun.IsChallengeIncluded(run, ch.id),
        }
    end

    table.sort(rounds)

    local groups = {}
    for _, round in ipairs(rounds) do
        groups[#groups + 1] = { round = round, items = byRound[round] }
    end
    return groups
end

--- What the settings fields read. `rebuild` moves it.
--- @class MTGSetupBinding
--- @field run MTGRun|nil

--- @param bound MTGSetupBinding
--- @param field table a SettingsFields() entry
--- @return Panel
local function SettingField(bound, field)
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
            text = tostring(field.default),
            refreshSettings = function(element)
                local text = tostring(MTGRun.SettingValue(bound.run, field))
                if element.text ~= text then
                    element.text = text
                end
            end,
            change = function(element)
                local n = tonumber(element.text) or field.default
                n = math.max(field.min or 1, math.floor(n))
                element.text = tostring(n)
                MTGRun.SetSetting(field.id, n)
            end,
        },
    }
end

--- The settings fields of one rules module, in a row.
--- @param bound MTGSetupBinding
--- @param moduleId string
--- @return Panel
local function SettingsRow(bound, moduleId)
    local fields = {}
    for _, field in ipairs(MTGRules.GetOrDefault(moduleId).SettingsFields()) do
        fields[#fields + 1] = SettingField(bound, field)
    end
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        children = fields,
    }
end

--- The Setup half of the montage form. Its Cancel and Start go to the shell's
--- footer, so this hands them out rather than mounting them itself.
--- @return {body: Panel, footer: table[]} the pane and its footer cells
function MTGSetupPanel.Create()
    --- @type MTGSetupBinding
    local bound = {}

    local settingsSlot = MTGWidgets.Slot{ width = "100%" }

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

            bound.run = run
            MTGWidgets.SetSlot(settingsSlot, run.moduleId, function()
                return SettingsRow(bound, run.moduleId)
            end)
            settingsSlot:FireEventTree("refreshSettings")

            local roster = {}
            for i, p in ipairs(run:try_get("participants", {})) do
                roster[i] = { p = p, index = i }
            end
            MTGWidgets.BindList(rosterPanel, roster, ParticipantRow, "setParticipant")

            MTGWidgets.BindList(challengesPanel, ChallengeGroups(run), RoundGroup, "setGroup")
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        settingsSlot,

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
                    classes = { "sizeL" },
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
                    classes = { "sizeL" },
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
