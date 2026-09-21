local mod = dmhub.GetModLoading()

--- Authoring surface for the selected Montage Definition.
MTGEditorPanel = {}

--- Fields per horizontal band of the settings form.
local FIELDS_ACROSS = 3
local FIELD_WIDTH = "30%"

--- Two digits, matching the stepper's input width.
local SETTING_MAX = 99

--- @class MTGStepperOptions
--- @field min number
--- @field max number
--- @field read fun(): number where the number comes from on each refresh
--- @field commit fun(n: number) where a press or an edit sends it
--- @field event nil|string refresh event to answer; defaults to refreshForm

--- A "- [n] +" stepper over a bounded integer, built once.
--- @param opts MTGStepperOptions
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
        text = tostring(opts.min),
        [opts.event or "refreshForm"] = function(element)
            local text = tostring(opts.read())
            if element.text ~= text then
                element.text = text
            end
        end,
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

--- A label-over-control form row.
--- @param labelText string
--- @param width string
--- @param control Panel
--- @param hint string|nil
--- @param labelTrailing nil|Panel a control sitting to the right of the label
--- @return Panel
local function FormRow(labelText, width, control, hint, labelTrailing)
    local label = gui.Label{
        classes = { "formStacked", "sizeS" },
        --A themed formStacked label is 98% wide and would push the control away.
        width = cond(labelTrailing == nil, nil, "auto"),
        text = labelText,
    }

    if labelTrailing ~= nil then
        label = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            children = { label, labelTrailing },
        }
    end

    local children = {
        label,
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

--- What the editor's fixed controls read. `rebuild` moves it.
--- @class MTGEditorBinding
--- @field defid string|nil
--- @field def MTGDefinition|nil

--- @param bound MTGEditorBinding
--- @param moduleId string
--- @param field table a SettingsFields() entry
--- @return Panel
local function SettingField(bound, moduleId, field)
    return FormRow(field.text, FIELD_WIDTH, Stepper{
        min = field.min or 1,
        max = field.max or SETTING_MAX,
        event = "refreshSettings",
        read = function()
            return bound.def:SettingValue(moduleId, field)
        end,
        commit = function(n)
            MTGDefinition.SetSetting(bound.defid, moduleId, field.id, n)
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

--- What one form's controls read. `setChallenge` moves all three at once.
--- @class MTGFormBinding
--- @field ch MTGChallengeDef|nil
--- @field store MTGChallengeStore|nil
--- @field moduleId string|nil

--- An eye that reports one boolean and flips it on press. Built once; its
--- icon and tooltip follow the flag on each refresh.
--- @param read fun(): boolean
--- @param onTip string tooltip while on
--- @param offTip string tooltip while off
--- @param onIcon string
--- @param offIcon string
--- @param press fun(on: boolean)
--- @return Panel
local function EyeButton(read, onTip, offTip, onIcon, offIcon, press)
    local shown = nil
    return gui.Button{
        classes = { "sizeXs" },
        icon = offIcon,
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        lmargin = 6,
        refreshForm = function(element)
            local on = read()
            if shown ~= on then
                shown = on
                element:FireEvent("setIcon", cond(on, onIcon, offIcon))
                element.tooltip = THCWidgets.Tooltip(cond(on, onTip, offTip))
            end
        end,
        click = function()
            press(read())
        end,
    }
end

--- A module-contributed field on one Challenge.
--- @param bound MTGFormBinding
--- @param moduleId string
--- @param field table a ChallengeFields() entry
--- @param hint string|nil
--- @return Panel
local function ChallengeModuleField(bound, moduleId, field, hint)
    if field.type == "choice" then
        local control = gui.Dropdown{
            classes = { "formStacked", "sizeS" },
            options = field.options,
            idChosen = field.default,
            refreshForm = function(element)
                local value = bound.ch:FieldValue(moduleId, field)
                if element.idChosen ~= value then
                    element.idChosen = value
                end
            end,
            change = function(element)
                bound.store.SetModuleField(field.id, element.idChosen)
            end,
        }

        --Difficulty is the only module field worth keeping from the table.
        if field.id == "difficulty" then
            control = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                valign = "center",

                control,

                EyeButton(function()
                    return bound.ch:try_get("difficultyHidden", false) == true
                end,
                    "Difficulty hidden from the table. Press to show it.",
                    "The table can see the difficulty. Press to hide it.",
                    "phosphor/eye-slash-duotone.png", "phosphor/eye-bold.png",
                    function(on)
                        bound.store.SetField("difficultyHidden", not on)
                    end),
            }
        end

        return FormRow(field.text, FIELD_WIDTH, control, hint)
    end

    --Off by default; a landed Outcome shows regardless.
    local labelTrailing = nil
    if moduleId == MTGConstants.moduleTO and field.id == "outcome" then
        labelTrailing = EyeButton(function()
            return bound.ch:try_get("outcomeShown", false) == true
        end,
            "The table can read this Outcome. Press to keep it back.",
            "Kept from the table until it lands. Press to show it always.",
            "phosphor/eye-bold.png", "phosphor/eye-slash-duotone.png",
            function(on)
                bound.store.SetField("outcomeShown", not on)
            end)
    end

    local full = field.fullWidth == true
    return FormRow(field.text, cond(full, "94%", "60%"), gui.Input{
        classes = { "formStacked", "sizeS" },
        text = "",
        characterLimit = 200,
        refreshForm = function(element)
            local text = tostring(bound.ch:FieldValue(moduleId, field) or "")
            if element.text ~= text then
                element.text = text
            end
        end,
        change = function(element)
            bound.store.SetModuleField(field.id, element.text or "")
        end,
    }, nil, labelTrailing)
end

--- The ids a multiselect has ticked. Its value can carry false entries for
--- ids that were unticked, so the set is rebuilt from the true ones before
--- it is compared with what the document holds.
--- @param value table<string, boolean>
--- @return table<string, boolean>
local function TickedSet(value)
    local set = {}
    for id, flag in pairs(value or {}) do
        if flag then
            set[id] = true
        end
    end
    return set
end

--- Allowed characteristics. Ordered: a hero who ties across two of these
--- takes whichever the Director listed first, so selection order is data.
--- @param bound MTGFormBinding
--- @param hint string|nil
--- @return Panel
local function CharacteristicsPicker(bound, hint)
    local options = THCUtils.CharacteristicOptions()

    return FormRow("Allowed Characteristics", "46%",
        gui.Multiselect{
            classes = { "formStacked", "sizeS" },
            dropdown = { hasSearch = false },
            options = options,
            value = {},
            refreshForm = function(element)
                local set = THCUtils.ToSet(bound.ch:try_get("allowedCharacteristics", {}))
                if not dmhub.DeepEqual(TickedSet(element.value), set) then
                    element.value = set
                end
            end,
            change = function(element)
                local existing = {}
                local current = bound.store.Read()
                if current ~= nil then
                    existing = current:try_get("allowedCharacteristics", {})
                end
                bound.store.SetCharacteristics(
                    THCUtils.MergeOrdered(element.value, existing, options))
            end,
        }, hint)
end

--- @param bound MTGFormBinding
--- @return Panel
local function SkillsPicker(bound)
    local options = THCUtils.SkillOptions()

    return FormRow("Allowed Skills", "46%",
        gui.Multiselect{
            classes = { "formStacked", "sizeS" },
            options = options,
            value = {},
            refreshForm = function(element)
                local set = THCUtils.ToSet(bound.ch:try_get("allowedSkills", {}))
                if not dmhub.DeepEqual(TickedSet(element.value), set) then
                    element.value = set
                end
            end,
            change = function(element)
                local list = {}
                for _, option in ipairs(options) do
                    if element.value[option.id] then
                        list[#list + 1] = option.id
                    end
                end
                bound.store.SetSkills(list)
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
--- run-time draft. Built once and pointed at a Challenge with
--- `setChallenge(ch, store, moduleId)`, after which every control patches
--- itself from that binding. Everything it writes goes through the store, so
--- the caller decides whether that lands in a saved montage or a private
--- draft.
--- @param opts nil|{showRequired: boolean}
--- @return Panel
function MTGEditorPanel.ChallengeForm(opts)
    opts = opts or {}

    local required = nil
    if opts.showRequired == true then
        required = "Required."
    end

    --- @type MTGFormBinding
    local bound = {}

    --Only a choice field can be required; free text is the Director's business.
    --A field asking for the full width takes a row of its own beneath the rest.
    local function ModuleFieldsRow(moduleId)
        local moduleFields = {}
        local fullRows = {}
        for _, field in ipairs(MTGRules.GetOrDefault(moduleId).ChallengeFields()) do
            local control = ChallengeModuleField(bound, moduleId, field,
                cond(field.type == "choice", required))
            if field.fullWidth == true then
                fullRows[#fullRows + 1] = control
            else
                moduleFields[#moduleFields + 1] = control
            end
        end

        local rows = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                valign = "top",
                children = moduleFields,
            },
        }
        for _, row in ipairs(fullRows) do
            rows[#rows + 1] = row
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "top",
            children = rows,
        }
    end

    local moduleFieldsSlot = MTGWidgets.Slot{ width = "100%" }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        setChallenge = function(element, ch, store, moduleId)
            bound.ch = ch
            bound.store = store
            bound.moduleId = moduleId
            MTGWidgets.SetSlot(moduleFieldsSlot, moduleId, function()
                return ModuleFieldsRow(moduleId)
            end)
            element:FireEventTree("refreshForm")
        end,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            FormRow("Name", "42%", gui.Input{
                classes = { "formStacked", "sizeS" },
                text = "",
                characterLimit = 80,
                refreshForm = function(element)
                    local name = bound.ch.name or ""
                    if element.text ~= name then
                        element.text = name
                    end
                end,
                change = function(element)
                    local newName = string.trim(element.text or "")
                    if newName == "" then
                        element.text = bound.ch.name or ""
                        return
                    end
                    bound.store.SetField("name", newName)
                end,
            }, required),

            FormRow("From Round", "16%", Stepper{
                min = 1,
                max = MTGConstants.roundMax,
                read = function()
                    return bound.ch.availableFromRound or 1
                end,
                commit = function(n)
                    bound.store.SetField("availableFromRound", n)
                end,
            }, required),

            FormRow("Repeats", "16%", Stepper{
                min = 0,
                max = MTGConstants.repeatMax,
                read = function()
                    return bound.ch:RepeatLimit()
                end,
                commit = function(n)
                    bound.store.SetField("repeatable", n)
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
                text = "",
                characterLimit = 300,
                refreshForm = function(element)
                    local description = bound.ch.description or ""
                    if element.text ~= description then
                        element.text = description
                    end
                end,
                change = function(element)
                    bound.store.SetField("description", element.text or "")
                end,
            }),
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            CharacteristicsPicker(bound, required),
            SkillsPicker(bound),
        },

        moduleFieldsSlot,
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
        hover = THCWidgets.Tooltip("Present this challenge to the table"),
        click = function(element)
            if element:HasClass("disabled") then
                return
            end
            onPresent(draft)
        end,
    }

    --Rebuilding the form would take the caret out of the field being typed.
    local function SyncPresent()
        if presentButton ~= nil and presentButton.valid then
            presentButton:SetClass("disabled", not DraftReady(draft, moduleId))
        end
    end

    --The draft is this card's own; no document write changes it.
    local form = MTGEditorPanel.ChallengeForm{ showRequired = true }
    form:FireEvent("setChallenge", draft, DraftStore(draft, moduleId, SyncPresent), moduleId)

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
                    hover = THCWidgets.Tooltip("Discard this challenge"),
                    click = function()
                        onDiscard()
                    end,
                },
            },
        },

        form,
    }
end

--- One authored Challenge's card. Built once and handed a Challenge with
--- `setChallenge`; handed nil, it collapses and waits for the next one.
--- @param expanded table<string, boolean> this client's fold state, by challenge
--- @return Panel
local function ChallengeCard(expanded)
    --- What the card's own controls read. `setChallenge` moves it.
    --- @class MTGCardBinding
    --- @field defid string|nil
    --- @field ch MTGChallengeDef|nil
    local bound = {}

    local shown = {}

    local form = MTGEditorPanel.ChallengeForm()

    local summaryLabel = gui.Label{
        classes = { "sizeS", "fgMuted" },
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 12,
        text = "",
    }

    local titleLabel = gui.Label{
        classes = { "sizeS", "bold" },
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        text = "",
    }

    local function MoveButton(up)
        return gui.Button{
            classes = { "sizeXs" },
            icon = "phosphor/arrow-fat-down-fill.png",
            rotate = cond(up, 180, 0),
            width = 16,
            height = 16,
            halign = "right",
            valign = "center",
            hmargin = 2,
            hover = THCWidgets.Tooltip(cond(up, "Move up", "Move down")),
            click = function()
                MTGDefinition.MoveChallenge(bound.defid, bound.ch.id, cond(up, -1, 1))
            end,
        }
    end
    local upButton = MoveButton(true)
    local downButton = MoveButton(false)
    local kindBadge = MTGWidgets.KindBadge(16, 2)

    local hiddenEye = gui.Button{
        classes = { "sizeXs" },
        icon = "phosphor/eye-bold.png",
        width = 16,
        height = 16,
        halign = "right",
        valign = "center",
        hmargin = 2,
        click = function()
            MTGDefinition.SetChallengeField(bound.defid, bound.ch.id, "hidden",
                not (bound.ch:try_get("hidden", false) == true))
        end,
    }

    local completeIcon = gui.Panel{
        classes = { "image" },
        bgimage = MTGConstants.iconConfigured,
        width = 16,
        height = 16,
        halign = "right",
        valign = "center",
        hmargin = 2,
        hover = THCWidgets.Tooltip("Ready to run"),
    }

    local deleteButton = gui.Button{
        classes = { "deleteButton", "sizeXs" },
        halign = "right",
        valign = "top",
        hmargin = 2,
        requireConfirm = true,
        hover = THCWidgets.Tooltip("Remove this challenge"),
        click = function()
            MTGDefinition.RemoveChallenge(bound.defid, bound.ch.id)
        end,
    }

    local arrow = gui.ExpandoArrow{
        classes = { "bgFgStrong" },
        width = 12,
        height = 12,
        halign = "left",
        valign = "center",
        rmargin = 4,
        click = function(element)
            local nowOpen = not element:HasClass("expanded")
            element:SetClass("expanded", nowOpen)
            expanded[bound.ch.id] = nowOpen
            form:SetClass("collapsed", not nowOpen)
            summaryLabel:SetClass("collapsed", nowOpen)
        end,
    }

    return gui.Panel{
        classes = { "bordered" },
        width = "96%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        pad = 8,
        vmargin = 4,

        --- @param item nil|{defid: string, moduleId: string, ch: MTGChallengeDef, index: number, total: number}
        setChallenge = function(element, item)
            element:SetClass("collapsed", item == nil)
            if item == nil then
                return
            end

            local ch = item.ch
            local moduleId = item.moduleId
            bound.defid = item.defid
            bound.ch = ch

            local complete = MTGRules.GetOrDefault(moduleId).IsChallengeComplete(ch, moduleId)

            --Remembered on first sight, so typing the last field does not snap it shut.
            local open = expanded[ch.id]
            if open == nil then
                open = not complete
                expanded[ch.id] = open
            end
            arrow:SetClass("expanded", open)
            form:SetClass("collapsed", not open)
            summaryLabel:SetClass("collapsed", open)

            local title = cond(ch:try_get("name", "") ~= "", ch.name, "Challenge " .. tostring(item.index))
            if shown.title ~= title then
                shown.title = title
                titleLabel.text = title
            end
            local summary = SummaryText(ch, moduleId)
            if shown.summary ~= summary then
                shown.summary = summary
                summaryLabel.text = summary
            end

            upButton:SetClass("collapsed", item.index <= 1)
            downButton:SetClass("collapsed", item.index >= item.total)
            completeIcon:SetClass("collapsed", not complete)

            local hidden = ch:try_get("hidden", false) == true
            if shown.hidden ~= hidden then
                shown.hidden = hidden
                hiddenEye:FireEvent("setIcon",
                    cond(hidden, "phosphor/eye-slash-duotone.png", "phosphor/eye-bold.png"))
                hiddenEye.tooltip = THCWidgets.Tooltip(cond(hidden,
                    "Hidden. Press to make it visible.",
                    "Visible. Press to hide it."))
            end

            MTGWidgets.PatchKindBadge(kindBadge, shown, ch, moduleId)

            form:FireEvent("setChallenge", ch, DefinitionStore(item.defid, ch.id, moduleId), moduleId)
        end,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            arrow,
            titleLabel,
            summaryLabel,

            gui.Panel{
                width = "14%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "top",

                upButton,
                downButton,
                kindBadge,
                hiddenEye,
                completeIcon,
                deleteButton,
            },
        },

        form,
    }
end

--- The settings form for one rules module: its fields in bands of
--- FIELDS_ACROSS, each reading the bound montage on `refreshSettings`.
--- @param bound MTGEditorBinding
--- @param moduleId string
--- @return Panel
local function SettingsForm(bound, moduleId)
    local fields = MTGRules.GetOrDefault(moduleId).SettingsFields()

    local bands = {}
    local current = nil

    for i, field in ipairs(fields) do
        if current == nil then
            current = {}
        end
        current[#current + 1] = SettingField(bound, moduleId, field)

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

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        children = bands,
    }
end

--- The editor half of the montage form. Point it at a montage by firing
--- `setDefinition` with an id, or nil to show the empty state.
--- @return Panel
function MTGEditorPanel.Create()
    local m_defid = nil

    local m_cardExpanded = {}

    --The eye cannot be read back off the button.
    local m_ladderShown = nil

    --- @type MTGEditorBinding
    local bound = {}

    local settingsSlot = MTGWidgets.Slot{ width = "100%" }

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

    --One body: the notice has its own collapsed class and the two must not fight.
    local challengesBody = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        challengesPanel,
        noChallengesLabel,
    }

    --Never written to the document: this Director's fold, not the montage's.
    local challengesArrow = gui.ExpandoArrow{
        classes = { "bgFg", "expanded" },
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        rmargin = 4,
        click = function(element)
            local nowExpanded = not element:HasClass("expanded")
            element:SetClass("expanded", nowExpanded)
            challengesBody:SetClass("collapsed", not nowExpanded)
        end,
    }

    local ladderInputs = {}
    local ladderRows = {}
    for _, rung in ipairs(MTGConstants.ladderRungs) do
        local key = rung.id
        local input = gui.Input{
            classes = { "formStacked", "sizeS" },
            width = "100%",
            height = 60,
            multiline = true,
            textAlignment = "topLeft",
            characterLimit = 1000,
            text = "",
            change = function(element)
                if m_defid ~= nil then
                    MTGDefinition.SetLadderText(m_defid, key, element.text or "")
                end
            end,
        }
        ladderInputs[key] = input
        ladderRows[#ladderRows + 1] = FormRow(rung.text, "96%", input)
    end

    local ladderBody = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        children = ladderRows,
    }

    local ladderArrow = gui.ExpandoArrow{
        classes = { "bgFg", "expanded" },
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        rmargin = 4,
        click = function(element)
            local nowExpanded = not element:HasClass("expanded")
            element:SetClass("expanded", nowExpanded)
            ladderBody:SetClass("collapsed", not nowExpanded)
        end,
    }

    --Built bare: hover cannot be re-assigned, so the tooltip is patched.
    local ladderEye = gui.Button{
        classes = { "sizeXs" },
        icon = "phosphor/eye-slash-duotone.png",
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        lmargin = 6,
        click = function()
            local def = m_defid ~= nil and MTGDefinition.GetByID(m_defid) or nil
            if def ~= nil then
                MTGDefinition.SetLadderShown(m_defid,
                    def:try_get("successLadderShown", false) ~= true)
            end
        end,
    }

    local ladderSection = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            vmargin = 8,

            ladderArrow,

            gui.Label{
                classes = { "tableLabel" },
                width = "auto",
                height = "auto",
                valign = "center",
                text = "Success Ladder",
            },

            ladderEye,
        },

        ladderBody,
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

    local scenePicker = THCWidgets.ScenePicker{
        height = MTGConstants.sceneImageHeight,
        halign = "center",
        change = function(value)
            if m_defid ~= nil then
                MTGDefinition.SetImage(m_defid, value)
            end
        end,
    }

    local sceneCell = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "center",

        scenePicker,

        gui.Label{
            classes = { "sizeXxs", "fg" },
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            text = "Backdrop",
        },
    }

    local addChallengeButton = gui.Button{
        classes = { "addButton", "sizeXs" },
        halign = "left",
        valign = "center",
        hmargin = 8,
        hover = THCWidgets.Tooltip("Add a challenge"),
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

            gui.Panel{
                width = "70%",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "top",

                FormRow("Name", "86%", nameInput),
                FormRow("Rules", "43%", moduleDropdown),
            },

            sceneCell,
        },

        settingsSlot,

        FormRow("Description", "96%", descriptionInput),

        ladderSection,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            vmargin = 8,

            challengesArrow,

            gui.Label{
                classes = { "tableLabel" },
                width = "auto",
                height = "auto",
                valign = "center",
                text = "Challenges",
            },

            addChallengeButton,
        },

        challengesBody,
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

        monitorAssets = true,
        refreshAssets = function(element)
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

            bound.defid = m_defid
            bound.def = def

            --An equal write still moves the caret, and the echo carries our own value.
            local name = def.name or ""
            if nameInput.text ~= name then
                nameInput.text = name
            end
            local description = def:try_get("description", "")
            if descriptionInput.text ~= description then
                descriptionInput.text = description
            end
            if moduleDropdown.idChosen ~= def.moduleId then
                moduleDropdown.idChosen = def.moduleId
            end
            local image = def:try_get("image", "")
            if scenePicker.value ~= image then
                scenePicker.value = image
            end

            local ladder = def.moduleId == MTGConstants.moduleBaseline
            ladderSection:SetClass("collapsed", not ladder)
            if ladder then
                for _, rung in ipairs(MTGConstants.ladderRungs) do
                    local input = ladderInputs[rung.id]
                    local text = MTGDefinition.LadderText(def, rung.id)
                    if input.text ~= text then
                        input.text = text
                    end
                end

                local shown = def:try_get("successLadderShown", false) == true
                if m_ladderShown ~= shown then
                    m_ladderShown = shown
                    ladderEye:FireEvent("setIcon", cond(shown,
                        "phosphor/eye-bold.png", "phosphor/eye-slash-duotone.png"))
                    ladderEye.tooltip = THCWidgets.Tooltip(cond(shown,
                        "The table can read the ladder. Press to keep it back.",
                        "Kept from the table. Press to show it."))
                end
            end

            MTGWidgets.SetSlot(settingsSlot, m_defid .. "/" .. def.moduleId, function()
                return SettingsForm(bound, def.moduleId)
            end)
            settingsSlot:FireEventTree("refreshSettings")

            local challenges = def:try_get("challenges", {})
            local items = {}
            for i, ch in ipairs(challenges) do
                items[i] = {
                    defid = m_defid,
                    moduleId = def.moduleId,
                    ch = ch,
                    index = i,
                    total = #challenges,
                }
            end
            THCWidgets.BindList(challengesPanel, items, function()
                return ChallengeCard(m_cardExpanded)
            end, "setChallenge")

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
