local mod = dmhub.GetModLoading()

--- Authoring surface for the selected Montage Definition.
MTGEditorPanel = {}

--- Fields per horizontal band of the settings form.
local FIELDS_ACROSS = 3
local FIELD_WIDTH = "30%"

--- A label-over-control form row.
--- @param labelText string
--- @param width string
--- @param control Panel
--- @return Panel
--- A "- [n] +" stepper over a bounded integer.
--- @param opts {value: number, min: number, max: number, commit: fun(n: number)}
--- @return Panel
local function Stepper(opts)
    local input

    local function Commit(value)
        local n = math.max(opts.min, math.min(opts.max, math.floor(value or opts.min)))
        input.text = tostring(n)
        opts.commit(n)
    end

    input = gui.Input{
        classes = { "formStacked", "sizeXs" },
        width = "20%",
        height = 22,
        halign = "left",
        valign = "center",
        numeric = true,
        characterLimit = 2,
        textAlignment = "center",
        text = tostring(opts.value),
        change = function(element)
            Commit(tonumber(element.text) or opts.min)
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
                Commit((tonumber(input.text) or opts.min) - 1)
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
                Commit((tonumber(input.text) or opts.min) + 1)
            end,
        },
    }
end

local function FormRow(labelText, width, control, hint)
    local children = {
        gui.Label{
            classes = { "formStacked", "sizeS" },
            text = labelText,
        },
        control,
    }

    if hint ~= nil then
        children[#children + 1] = gui.Label{
            classes = { "sizeXxs", "fgMuted" },
            italics = true,
            width = "auto",
            height = "auto",
            halign = "left",
            text = hint,
        }
    end

    return gui.Panel{
        classes = { "formStackedRow" },
        width = width,
        children = children,
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

--- Where a challenge form reads and writes. The library editor goes through
--- MTGDefinition; a run-time draft goes to a table nobody else can see.
--- @class MTGChallengeStore
--- @field Read fun(): MTGChallengeDef|nil the live object, for order-preserving merges
--- @field SetField fun(key: string, value: any)
--- @field SetModuleField fun(fieldId: string, value: any)
--- @field SetCharacteristics fun(list: string[])
--- @field SetSkills fun(list: string[])

--- @param defid string
--- @param chid string
--- @param moduleId string
--- @return MTGChallengeStore
local function DefinitionStore(defid, chid, moduleId)
    return {
        Read = function()
            local def = MTGDefinition.GetByID(defid)
            if def == nil then
                return nil
            end
            return (MTGDefinition.FindChallenge(def, chid))
        end,
        SetField = function(key, value)
            MTGDefinition.SetChallengeField(defid, chid, key, value)
        end,
        SetModuleField = function(fieldId, value)
            MTGDefinition.SetChallengeModuleField(defid, chid, moduleId, fieldId, value)
        end,
        SetCharacteristics = function(list)
            MTGDefinition.SetChallengeCharacteristics(defid, chid, list)
        end,
        SetSkills = function(list)
            MTGDefinition.SetChallengeSkills(defid, chid, list)
        end,
    }
end

--- @param draft MTGChallengeDef
--- @param moduleId string
--- @param onChanged fun()
--- @return MTGChallengeStore
local function DraftStore(draft, moduleId, onChanged)
    return {
        Read = function()
            return draft
        end,
        SetField = function(key, value)
            draft[key] = value
            onChanged()
        end,
        SetModuleField = function(fieldId, value)
            draft:FieldsFor(moduleId)[fieldId] = value
            onChanged()
        end,
        SetCharacteristics = function(list)
            draft.allowedCharacteristics = list
            onChanged()
        end,
        SetSkills = function(list)
            draft.allowedSkills = list
            onChanged()
        end,
    }
end

--- A module-contributed field on one Challenge.
--- @param store MTGChallengeStore
--- @param ch MTGChallengeDef
--- @param moduleId string
--- @param field table a ChallengeFields() entry
--- @param hint string|nil
--- @return Panel
local function ChallengeModuleField(store, ch, moduleId, field, hint)
    local value = ch:FieldValue(moduleId, field)

    if field.type == "choice" then
        return FormRow(field.text, FIELD_WIDTH, gui.Dropdown{
            classes = { "formStacked", "sizeS" },
            options = field.options,
            idChosen = value,
            change = function(element)
                store.SetModuleField(field.id, element.idChosen)
            end,
        }, hint)
    end

    return FormRow(field.text, "60%", gui.Input{
        classes = { "formStacked", "sizeS" },
        text = tostring(value or ""),
        characterLimit = 200,
        change = function(element)
            store.SetModuleField(field.id, element.text or "")
        end,
    })
end

--- Allowed characteristics. Ordered: a hero who ties across two of these
--- takes whichever the Director listed first, so selection order is data.
--- @param store MTGChallengeStore
--- @param ch MTGChallengeDef
--- @param hint string|nil
--- @return Panel
local function CharacteristicsPicker(store, ch, hint)
    local options = MTGUtils.CharacteristicOptions()
    local chosen = ch:try_get("allowedCharacteristics", {})

    return FormRow("Allowed Characteristics", "46%",
        gui.Multiselect{
            classes = { "formStacked", "sizeS" },
            dropdown = { hasSearch = false },
            options = options,
            value = MTGUtils.ToSet(chosen),
            change = function(element)
                local existing = {}
                local current = store.Read()
                if current ~= nil then
                    existing = current:try_get("allowedCharacteristics", {})
                end
                store.SetCharacteristics(
                    MTGUtils.MergeOrdered(element.value, existing, options))
            end,
        }, hint)
end

--- @param store MTGChallengeStore
--- @param ch MTGChallengeDef
--- @return Panel
local function SkillsPicker(store, ch)
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
                store.SetSkills(list)
            end,
        })
end

--- What the title bar carries while a Challenge is folded. Only choice fields
--- join in; a free-text one would swamp the row.
--- @param ch MTGChallengeDef
--- @param moduleId string
--- @return string
local function SummaryText(ch, moduleId)
    local parts = {
        "Round " .. tostring(ch.availableFromRound or 1),
        "Repeats " .. tostring(ch:RepeatLimit()),
    }

    for _, field in ipairs(MTGRules.GetOrDefault(moduleId).ChallengeFields()) do
        if field.type == "choice" then
            local value = ch:FieldValue(moduleId, field)
            for _, option in ipairs(field.options or {}) do
                if option.id == value then
                    parts[#parts + 1] = option.text
                end
            end
        end
    end

    return table.concat(parts, ", ")
end

--- The field rows of a Challenge, shared by the library editor and the
--- run-time draft. Everything it writes goes through the store, so the caller
--- decides whether that lands in a saved montage or a private draft.
--- @param ch MTGChallengeDef
--- @param moduleId string
--- @param store MTGChallengeStore
--- @param opts nil|{showRequired: boolean}
--- @return Panel[]
function MTGEditorPanel.ChallengeForm(ch, moduleId, store, opts)
    opts = opts or {}

    local required = nil
    if opts.showRequired == true then
        required = "Required."
    end

    --Only a choice field can be required: a module's free text, like T&O's
    --outcome, is the Director's business.
    local moduleFields = {}
    for _, field in ipairs(MTGRules.GetOrDefault(moduleId).ChallengeFields()) do
        moduleFields[#moduleFields + 1] = ChallengeModuleField(store, ch, moduleId, field,
            cond(field.type == "choice", required))
    end

    return {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            FormRow("Name", "42%", gui.Input{
                classes = { "formStacked", "sizeS" },
                text = ch.name or "",
                characterLimit = 80,
                change = function(element)
                    local newName = string.trim(element.text or "")
                    if newName == "" then
                        element.text = ch.name or ""
                        return
                    end
                    store.SetField("name", newName)
                end,
            }, required),

            FormRow("From Round", "16%", Stepper{
                value = ch.availableFromRound or 1,
                min = 1,
                max = MTGConstants.roundMax,
                commit = function(n)
                    store.SetField("availableFromRound", n)
                end,
            }, required),

            FormRow("Repeats", "16%", Stepper{
                value = ch:RepeatLimit(),
                min = 0,
                max = MTGConstants.repeatMax,
                commit = function(n)
                    store.SetField("repeatable", n)
                end,
            }),
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
                    store.SetField("description", element.text or "")
                end,
            }),
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            CharacteristicsPicker(store, ch, required),
            SkillsPicker(store, ch),
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

--- Whether a run-time draft carries what a Challenge needs to be rollable. A
--- lower bar than IsChallengeComplete: description and skills are the
--- Director's business, but with no characteristic DeriveCharacteristic has
--- nothing to walk and the lead rolls against nothing.
--- @param draft MTGChallengeDef
--- @param moduleId string
--- @return boolean
local function DraftReady(draft, moduleId)
    if string.trim(draft.name or "") == "" then
        return false
    end
    if (tonumber(draft.availableFromRound) or 0) < 1 then
        return false
    end
    if #draft:try_get("allowedCharacteristics", {}) < 1 then
        return false
    end

    for _, field in ipairs(MTGRules.GetOrDefault(moduleId).ChallengeFields()) do
        if field.type == "choice" then
            local value = draft:FieldValue(moduleId, field)
            if value == nil or string.trim(tostring(value)) == "" then
                return false
            end
        end
    end

    return true
end

--- A Challenge authored while the montage is running. It reaches the document
--- only on Present, so discarding costs nothing and the table never sees a
--- half-built row.
--- @param draft MTGChallengeDef
--- @param moduleId string
--- @param onPresent fun(draft: MTGChallengeDef)
--- @param onDiscard fun()
--- @return Panel
function MTGEditorPanel.DraftCard(draft, moduleId, onPresent, onDiscard)
    local presentButton

    presentButton = gui.Button{
        classes = { "sizeXs", cond(not DraftReady(draft, moduleId), "disabled") },
        icon = MTGConstants.iconPresent,
        width = 22,
        height = 22,
        halign = "right",
        valign = "center",
        hmargin = 2,
        hover = gui.Tooltip("Present this challenge to the table"),
        click = function(element)
            if element:HasClass("disabled") then
                return
            end
            onPresent(draft)
        end,
    }

    --The form is left standing and only the button is retoned: rebuilding it
    --on every edit would take the caret out of whatever field is being typed.
    local function SyncPresent()
        if presentButton ~= nil and presentButton.valid then
            presentButton:SetClass("disabled", not DraftReady(draft, moduleId))
        end
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

            gui.Label{
                classes = { "sizeS", "bold" },
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                text = "New Challenge",
            },

            gui.Panel{
                width = "20%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "top",

                presentButton,

                gui.Button{
                    classes = { "deleteButton", "sizeXs" },
                    halign = "right",
                    valign = "top",
                    hmargin = 2,
                    hover = gui.Tooltip("Discard this challenge"),
                    click = function()
                        onDiscard()
                    end,
                },
            },
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "top",
            children = MTGEditorPanel.ChallengeForm(draft, moduleId,
                DraftStore(draft, moduleId, SyncPresent), { showRequired = true }),
        },
    }
end

--- One authored Challenge.
--- @param defid string
--- @param def MTGDefinition
--- @param ch MTGChallengeDef
--- @param index number
--- @param expanded table<string, boolean> this client's fold state, by challenge
--- @return Panel
local function ChallengeCard(defid, def, ch, index, expanded)
    local chid = ch.id
    local moduleId = def.moduleId
    local complete = MTGRules.GetOrDefault(moduleId).IsChallengeComplete(ch, moduleId)

    --Decided on first sight and then remembered: a finished challenge folds
    --away, one still missing fields stays open. Recording it means typing the
    --last field does not snap the card shut mid-edit.
    local open = expanded[chid]
    if open == nil then
        open = not complete
        expanded[chid] = open
    end

    local body = gui.Panel{
        classes = { cond(not open, "collapsed") },
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        children = MTGEditorPanel.ChallengeForm(ch, moduleId,
            DefinitionStore(defid, chid, moduleId)),
    }

    local summaryLabel = gui.Label{
        classes = { "sizeS", "fgMuted", cond(open, "collapsed") },
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 12,
        text = SummaryText(ch, moduleId),
    }

    local topRight = {}

    if complete then
        topRight[#topRight + 1] = gui.Panel{
            classes = { "image" },
            bgimage = MTGConstants.iconConfigured,
            width = 16,
            height = 16,
            halign = "right",
            valign = "center",
            hmargin = 2,
            hover = gui.Tooltip("Ready to run"),
        }
    end

    topRight[#topRight + 1] = gui.Button{
        classes = { "deleteButton", "sizeXs" },
        halign = "right",
        valign = "top",
        hmargin = 2,
        requireConfirm = true,
        hover = gui.Tooltip("Remove this challenge"),
        click = function()
            MTGDefinition.RemoveChallenge(defid, chid)
        end,
    }

    local arrowArgs = {
        classes = { "bgFgStrong" },
        width = 12,
        height = 12,
        halign = "left",
        valign = "center",
        rmargin = 4,
    }
    if open then
        arrowArgs.classes[#arrowArgs.classes + 1] = "expanded"
    end
    arrowArgs.click = function(element)
        local nowOpen = not element:HasClass("expanded")
        element:SetClass("expanded", nowOpen)
        expanded[chid] = nowOpen
        body:SetClass("collapsed", not nowOpen)
        summaryLabel:SetClass("collapsed", nowOpen)
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

            gui.ExpandoArrow(arrowArgs),

            gui.Label{
                classes = { "sizeS", "bold" },
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                text = "Challenge " .. tostring(index),
            },

            summaryLabel,

            gui.Panel{
                width = "14%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "top",
                children = topRight,
            },
        },

        body,
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

    --Fold state this client chose, by challenge. Absent means open, so a
    --freshly authored challenge lands with its fields in reach.
    local m_cardExpanded = {}

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
                cards[#cards + 1] = ChallengeCard(m_defid, def, ch, i, m_cardExpanded)
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
