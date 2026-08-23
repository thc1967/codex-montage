local mod = dmhub.GetModLoading()

--- Authoring surface for the selected Montage Definition.
MTGEditorPanel = {}

--- Reorder arrows. One asset, flipped vertically for the up direction, the
--- way the theme flips pagingArrow horizontally for its right variant.
local CARET = "phosphor/caret-down-fill.png"

--- Fields per horizontal band of the settings form.
local FIELDS_ACROSS = 3
local FIELD_WIDTH = "30%"

--- A label-over-control form row.
--- @param labelText string
--- @param width string
--- @param control Panel
--- @return Panel
--- A "- [n] +" stepper for how many further attempts a Challenge allows.
--- @param defid string
--- @param chid string
--- @param ch MTGChallengeDef
--- @return Panel
local function RepeatStepper(defid, chid, ch)
    local input

    local function Commit(value)
        local n = math.max(0, math.min(MTGConstants.repeatMax, math.floor(value or 0)))
        input.text = tostring(n)
        MTGDefinition.SetChallengeField(defid, chid, "repeatable", n)
    end

    input = gui.Input{
        classes = { "formStacked", "sizeXs" },
        width = "40%",
        height = 22,
        halign = "left",
        valign = "center",
        numeric = true,
        characterLimit = 2,
        textAlignment = "center",
        text = tostring(ch:RepeatLimit()),
        change = function(element)
            Commit(tonumber(element.text) or 0)
        end,
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",

        gui.Button{
            classes = { "sizeXxs" },
            width = 22,
            height = 22,
            text = "-",
            halign = "left",
            valign = "center",
            press = function()
                Commit((tonumber(input.text) or 0) - 1)
            end,
        },

        input,

        gui.Button{
            classes = { "sizeXxs" },
            width = 22,
            height = 22,
            text = "+",
            halign = "left",
            valign = "center",
            press = function()
                Commit((tonumber(input.text) or 0) + 1)
            end,
        },
    }
end

local function FormRow(labelText, width, control)
    return gui.Panel{
        classes = { "formStackedRow" },
        width = width,
        children = {
            gui.Label{
                classes = { "formStacked", "sizeS" },
                text = labelText,
            },
            control,
        },
    }
end

--- @param defid string
--- @param moduleId string
--- @param field table a SettingsFields() entry
--- @param value number
--- @return Panel
local function SettingField(defid, moduleId, field, value)
    return FormRow(field.text, FIELD_WIDTH, gui.Input{
        classes = { "formStacked", "sizeXs" },
        numeric = true,
        characterLimit = 3,
        text = tostring(value),

        change = function(element)
            local current = MTGDefinition.GetByID(defid)
            if current == nil then
                return
            end

            local n = tonumber(element.text) or tonumber((element.text or ""):match("%-?%d+")) or field.default
            n = math.max(field.min or 1, math.floor(n))
            element.text = tostring(n)
            MTGDefinition.SetSetting(defid, moduleId, field.id, n)
        end,
    })
end

--- A module-contributed field on one Challenge.
--- @param defid string
--- @param ch MTGChallengeDef
--- @param moduleId string
--- @param field table a ChallengeFields() entry
--- @return Panel
local function ChallengeModuleField(defid, ch, moduleId, field)
    local chid = ch.id
    local value = ch:FieldValue(moduleId, field)

    if field.type == "choice" then
        return FormRow(field.text, FIELD_WIDTH, gui.Dropdown{
            classes = { "formStacked", "sizeS" },
            options = field.options,
            idChosen = value,
            change = function(element)
                MTGDefinition.SetChallengeModuleField(defid, chid, moduleId, field.id, element.idChosen)
            end,
        })
    end

    return FormRow(field.text, "60%", gui.Input{
        classes = { "formStacked", "sizeS" },
        text = tostring(value or ""),
        characterLimit = 200,
        change = function(element)
            MTGDefinition.SetChallengeModuleField(defid, chid, moduleId, field.id, element.text or "")
        end,
    })
end

--- Allowed characteristics. Ordered: a hero who ties across two of these
--- takes whichever the Director listed first, so selection order is data.
--- @param defid string
--- @param ch MTGChallengeDef
--- @return Panel
local function CharacteristicsPicker(defid, ch)
    local chid = ch.id
    local options = MTGUtils.CharacteristicOptions()
    local chosen = ch:try_get("allowedCharacteristics", {})

    return FormRow("Allowed Characteristics", "46%",
        gui.Multiselect{
            classes = { "formStacked", "sizeS" },
            dropdown = { hasSearch = false },
            options = options,
            value = MTGUtils.ToSet(chosen),
            change = function(element)
                local current = MTGDefinition.GetByID(defid)
                if current == nil then
                    return
                end
                local existing = {}
                local c = MTGDefinition.FindChallenge(current, chid)
                if c ~= nil then
                    existing = c:try_get("allowedCharacteristics", {})
                end
                MTGDefinition.SetChallengeCharacteristics(defid, chid,
                    MTGUtils.MergeOrdered(element.value, existing, options))
            end,
        })
end

--- @param defid string
--- @param ch MTGChallengeDef
--- @return Panel
local function SkillsPicker(defid, ch)
    local chid = ch.id
    local options = MTGUtils.SkillOptions()
    local chosen = ch:try_get("allowedSkills", {})

    return FormRow("Allowed Skills", "46%",
        gui.Multiselect{
            classes = { "formStacked", "sizeS" },
            options = options,
            value = MTGUtils.ToSet(chosen),
            change = function(element)
                local list = {}
                for _, option in ipairs(options) do
                    if element.value[option.id] then
                        list[#list + 1] = option.id
                    end
                end
                MTGDefinition.SetChallengeSkills(defid, chid, list)
            end,
        })
end

--- One authored Challenge.
--- @param defid string
--- @param def MTGDefinition
--- @param ch MTGChallengeDef
--- @param index number
--- @param count number
--- @return Panel
local function ChallengeCard(defid, def, ch, index, count)
    local chid = ch.id
    local moduleId = def.moduleId

    local moduleFields = {}
    for _, field in ipairs(MTGRules.GetOrDefault(moduleId).ChallengeFields()) do
        moduleFields[#moduleFields + 1] = ChallengeModuleField(defid, ch, moduleId, field)
    end

    return gui.Panel{
        classes = { "bordered" },
        width = "96%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        pad = 8,
        vmargin = 4,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            FormRow("Challenge " .. tostring(index), "42%", gui.Input{
                classes = { "formStacked", "sizeS" },
                text = ch.name or "",
                characterLimit = 80,
                change = function(element)
                    local newName = string.trim(element.text or "")
                    if newName == "" then
                        element.text = ch.name or ""
                        return
                    end
                    MTGDefinition.SetChallengeField(defid, chid, "name", newName)
                end,
            }),

            FormRow("From Round", "16%", gui.Input{
                classes = { "formStacked", "sizeXs" },
                numeric = true,
                characterLimit = 2,
                text = tostring(ch.availableFromRound or 1),
                change = function(element)
                    local n = math.max(1, math.floor(tonumber(element.text) or 1))
                    element.text = tostring(n)
                    MTGDefinition.SetChallengeField(defid, chid, "availableFromRound", n)
                end,
            }),

            FormRow("Repeats", "16%", RepeatStepper(defid, chid, ch)),

            gui.Panel{
                width = "14%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "top",

                gui.Panel{
                    classes = { "bgFg", "hoverable", cond(index <= 1, "hidden") },
                    bgimage = CARET,
                    scale = { x = 1, y = -1 },
                    width = 16,
                    height = 16,
                    halign = "right",
                    valign = "center",
                    hmargin = 2,
                    hover = gui.Tooltip("Move earlier"),
                    press = function()
                        MTGDefinition.MoveChallenge(defid, chid, -1)
                    end,
                },

                gui.Panel{
                    classes = { "bgFg", "hoverable", cond(index >= count, "hidden") },
                    bgimage = CARET,
                    width = 16,
                    height = 16,
                    halign = "right",
                    valign = "center",
                    hmargin = 2,
                    hover = gui.Tooltip("Move later"),
                    press = function()
                        MTGDefinition.MoveChallenge(defid, chid, 1)
                    end,
                },

                gui.Button{
                    classes = { "deleteButton", "sizeXs" },
                    halign = "right",
                    valign = "top",
                    hmargin = 2,
                    requireConfirm = true,
                    hover = gui.Tooltip("Remove this challenge"),
                    click = function()
                        MTGDefinition.RemoveChallenge(defid, chid)
                    end,
                },
            },
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            FormRow("Description", "92%", gui.Input{
                classes = { "formStacked", "sizeS" },
                text = ch.description or "",
                characterLimit = 300,
                change = function(element)
                    MTGDefinition.SetChallengeField(defid, chid, "description", element.text or "")
                end,
            }),
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            CharacteristicsPicker(defid, ch),
            SkillsPicker(defid, ch),
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            children = moduleFields,
        },
    }
end

--- @param defid string
--- @param def MTGDefinition
--- @return Panel[]
local function SettingBands(defid, def)
    local moduleId = def.moduleId
    local fields = MTGRules.GetOrDefault(moduleId).SettingsFields()

    local bands = {}
    local current = nil

    for i, field in ipairs(fields) do
        if current == nil then
            current = {}
        end
        current[#current + 1] = SettingField(defid, moduleId, field, def:SettingValue(moduleId, field))

        if #current == FIELDS_ACROSS or i == #fields then
            bands[#bands + 1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                valign = "top",
                children = current,
            }
            current = nil
        end
    end

    return bands
end

--- The editor half of the montage form. Point it at a montage by firing
--- `setDefinition` with an id, or nil to show the empty state.
--- @return Panel
function MTGEditorPanel.Create()
    local m_defid = nil

    local settingsPanel = gui.Panel{
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

    local noChallengesLabel = gui.Label{
        classes = { "sizeS", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "center",
        vmargin = 12,
        textAlignment = "center",
        text = "No challenges yet. Use the + button to add one.",
    }

    local nameInput = gui.Input{
        classes = { "formStacked", "sizeS" },
        characterLimit = 80,
        change = function(element)
            if m_defid == nil then
                return
            end
            local newName = string.trim(element.text or "")
            local current = MTGDefinition.GetByID(m_defid)
            if current == nil then
                return
            end
            if newName == "" then
                element.text = current.name or ""
                return
            end
            MTGDefinition.Rename(m_defid, newName)
        end,
    }

    local descriptionInput = gui.Input{
        classes = { "formStacked", "sizeS" },
        width = "100%",
        height = 60,
        multiline = true,
        textAlignment = "topLeft",
        characterLimit = 4000,
        placeholderText = "What is happening here? Markdown is welcome.",
        text = "",
        change = function(element)
            if m_defid ~= nil then
                MTGDefinition.SetDescription(m_defid, element.text)
            end
        end,
    }

    local moduleDropdown = gui.Dropdown{
        classes = { "formStacked", "sizeS" },
        options = MTGRules.DropdownOptions(),
        change = function(element)
            if m_defid ~= nil then
                MTGDefinition.SetModule(m_defid, element.idChosen)
            end
        end,
    }

    local addChallengeButton = gui.Button{
        classes = { "addButton", "sizeXs" },
        halign = "left",
        valign = "center",
        hmargin = 8,
        hover = gui.Tooltip("Add a challenge"),
        click = function()
            if m_defid ~= nil then
                MTGDefinition.AddChallenge(m_defid)
            end
        end,
    }

    local formPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            FormRow("Name", "60%", nameInput),
            FormRow("Rules", "30%", moduleDropdown),
        },

        settingsPanel,

        FormRow("Description", "96%", descriptionInput),

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            vmargin = 8,

            gui.Label{
                classes = { "tableLabel" },
                width = "auto",
                height = "auto",
                valign = "center",
                text = "Challenges",
            },

            addChallengeButton,
        },

        challengesPanel,
        noChallengesLabel,
    }

    local emptyLabel = gui.Label{
        classes = { "sizeS", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        text = "Select a montage on the left, or add one.",
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        valign = "top",
        vscroll = true,

        monitorGame = MTGDefinition.DocPath(),
        refreshGame = function(element)
            element:FireEvent("rebuild")
        end,

        setDefinition = function(element, defid)
            m_defid = defid
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local def = m_defid ~= nil and MTGDefinition.GetByID(m_defid) or nil

            formPanel:SetClass("collapsed", def == nil)
            emptyLabel:SetClass("collapsed", def ~= nil)

            if def == nil then
                return
            end

            nameInput.text = def.name or ""
            descriptionInput.text = def:try_get("description", "")
            moduleDropdown.idChosen = def.moduleId
            settingsPanel.children = SettingBands(m_defid, def)

            local challenges = def:try_get("challenges", {})
            local cards = {}
            for i, ch in ipairs(challenges) do
                cards[#cards + 1] = ChallengeCard(m_defid, def, ch, i, #challenges)
            end
            challengesPanel.children = cards
            noChallengesLabel:SetClass("collapsed", #challenges > 0)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        formPanel,
        emptyLabel,
    }

    return resultPanel
end
