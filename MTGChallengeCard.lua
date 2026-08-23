local mod = dmhub.GetModLoading()

--- One attempt row: a Challenge, its Lead and Assist slots, and its status.
MTGChallengeCard = {}

--- A Lead or Assist slot: empty and waiting, or holding a participant.
--- @param run MTGRun
--- @param inst table
--- @param slot string "lead" or "assist"
--- @param label string
--- @return Panel
local function Slot(run, inst, slot, label)
    local placed = inst[slot]

    --A rolled slot is spent: the only way back is the Director's undo.
    local inert = inst.adjudicatedInRound ~= nil or inst[slot .. "Roll"] ~= nil

    local classes = { "bordered", "mtgSlot" }
    if inert then
        classes[#classes + 1] = "disabled"
    end

    local removeMenu = nil
    if placed ~= nil and not inert and MTGRun.CanManage(placed.charid) then
        removeMenu = function(element)
            element.popup = gui.ContextMenu{
                entries = {
                    {
                        text = "Remove",
                        click = function()
                            element.popup = nil
                            MTGRun.Unstage(inst.id, slot)
                        end,
                    },
                },
            }
        end
    end

    local children = {}

    if placed ~= nil then
        local p = MTGRun.Participant(run, placed.charid)
        if p ~= nil then
            local token = MTGWidgets.ParticipantToken(p, not inert, removeMenu, inert)
            if token ~= nil then
                children[#children + 1] = token
            end
        end
    end

    local box = gui.Panel{
        classes = classes,
        width = 46,
        height = 46,
        flow = "none",
        halign = "center",
        valign = "top",
        dragTarget = not inert,
        hover = gui.Tooltip(label),

        dropOnSlot = function(element, charid)
            MTGRun.Stage(inst.id, slot, charid)
        end,

        rightClick = removeMenu,

        press = function(element)
            if inert or placed ~= nil then
                return
            end

            local entries = {}
            for _, p in ipairs(MTGRun.StageOptions(run, inst, slot)) do
                local charid = p.charid
                if MTGRun.CanManage(charid) then
                    entries[#entries + 1] = {
                        text = p.name or "",
                        click = function()
                            element.popup = nil
                            MTGRun.Stage(inst.id, slot, charid)
                        end,
                    }
                end
            end

            if #entries == 0 then
                entries[#entries + 1] = {
                    text = "No one available",
                    click = function()
                        element.popup = nil
                    end,
                }
            end

            element.popup = gui.ContextMenu{ entries = entries }
        end,

        children = children,
    }

    return gui.Panel{
        width = 46,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        rmargin = 8,

        box,

        gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            text = label,
        },
    }
end

--- Flags a pick the Challenge does not allow. Off-list is legal, so this
--- informs rather than blocks.
--- @param tooltip string
--- @return Panel
local function OffListIcon(tooltip)
    return gui.Panel{
        classes = { "bgWarning" },
        width = 20,
        height = 20,
        halign = "left",
        valign = "center",
        lmargin = 2,
        bgimage = "phosphor/warning-duotone.png",
        hover = gui.Tooltip(tooltip),
    }
end

--- One labelled dropdown plus its off-list flag.
--- @param options {id: string, text: string}[]
--- @param value string
--- @param editable boolean
--- @param offList string|nil tooltip when the pick is off-list, else nil
--- @param onChange fun(id: string)
--- @return Panel
local function PickerRow(options, value, editable, offList, onChange)
    local children = {
        gui.Dropdown{
            -- classes = { "form" },
            width = cond(offList ~= nil, "98%-24", "98%"),
            -- height = 20,
            halign = "left",
            valign = "center",
            options = options,
            idChosen = value,
            interactable = editable,
            change = function(element)
                onChange(element.idChosen)
            end,
        },
    }

    --Built in a branch, not with cond: Lua evaluates both arguments, so the
    --icon would be constructed and orphaned on every on-list pick.
    if offList ~= nil then
        children[#children + 1] = OffListIcon(offList)
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",
        vmargin = 1,
        children = children,
    }
end

--- "2 edges", "1 bane", or nil when the roll was clean.
--- @param roll table
--- @return string|nil
local function EdgeText(roll)
    local boons = roll.boons or 0
    local banes = roll.banes or 0
    if boons > 0 then
        return string.format("%d edge%s", boons, cond(boons == 1, "", "s"))
    end
    if banes > 0 then
        return string.format("%d bane%s", banes, cond(banes == 1, "", "s"))
    end
    return nil
end

--- What the roll was made of, once it has been made. Replaces the pickers:
--- the choices are spent, so what matters is what they produced.
--- @param run MTGRun
--- @param inst table
--- @param ch MTGChallengeDef
--- @param slot string
--- @param assignment table
--- @param roll table
--- @return Panel[]
local function RollSummary(run, inst, ch, slot, assignment, roll)
    local function Line(text)
        return gui.Label{
            classes = { "sizeXs", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            markdown = true,
            text = text,
        }
    end

    local parts = {
        string.format("Tier %d", roll.tier or 0),
        tostring(roll.total or 0),
        string.format("Natural %d", roll.naturalRoll or 0),
        string.format("%s %s",
            MTGUtils.CharacteristicName(assignment.attrId),
            MTGUtils.SignedModifier(MTGUtils.CharacteristicModifier(assignment.charid, assignment.attrId))),
    }
    if assignment.skillId ~= nil and assignment.skillId ~= "" then
        parts[#parts + 1] = MTGUtils.SkillName(assignment.skillId)
    else
        parts[#parts + 1] = "no skill"
    end
    local edges = EdgeText(roll)
    if edges ~= nil then
        parts[#parts + 1] = edges
    end

    local verdict
    if slot == "assist" then
        local grant = MTGResolver.AssistGrant(run, inst)
        verdict = string.format("Gives a %s", string.gsub(grant or "bane", "_", " "))
    elseif inst.outcome ~= nil then
        verdict = inst.outcome.label
    else
        verdict = MTGRules.GetOrDefault(run.moduleId).RollToOutcome(run, ch, roll).label
    end

    local headline = {
        Line(string.format("**%s**", verdict)),
    }

    if dmhub.isDM then
        headline[#headline + 1] = gui.Button{
            classes = { "sizeXxs" },
            icon = "icons/standard/Icon_App_Undo.png",
            halign = "right",
            valign = "center",
            floating = true,
            hover = gui.Tooltip("Undo this roll"),
            click = function()
                MTGRun.ClearRoll(inst.id, slot)
            end,
        }
    end

    return {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            children = headline,
        },

        Line(table.concat(parts, " · ")),
    }
end

--- The module's question, answerable by whoever rolled and by the Director.
--- @param inst table
--- @param prompt table
--- @param charid string the Lead who rolled
--- @return Panel
local function PromptRow(inst, prompt, charid)
    local children = {
        gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            text = prompt.text or "",
        },
    }

    if MTGRun.CanManage(charid) then
        local buttons = {}
        for _, option in ipairs(prompt.options or {}) do
            local outcome = option.outcome
            buttons[#buttons + 1] = gui.Button{
                classes = { "sizeXxs" },
                width = "48%",
                height = 22,
                halign = "left",
                rmargin = 4,
                text = option.label or "",
                click = function()
                    MTGRun.Adjudicate(inst.id, outcome)
                end,
            }
        end

        children[#children + 1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            tmargin = 2,
            children = buttons,
        }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        children = children,
    }
end

--- The Lead or Assist column: the slot, with its characteristic and skill
--- stacked beside it.
--- @param run MTGRun
--- @param inst table
--- @param ch MTGChallengeDef
--- @param slot string
--- @param label string
--- @return Panel
local function SlotColumn(run, inst, ch, slot, label)
    local placed = inst[slot]
    local locked = inst.adjudicatedInRound ~= nil
    local editable = placed ~= nil and not locked and MTGRun.CanManage(placed.charid)

    local pickers = {}
    local roll = placed ~= nil and inst[slot .. "Roll"] or nil

    if roll ~= nil then
        pickers = RollSummary(run, inst, ch, slot, placed, roll)
        if slot == "lead" then
            local prompt = MTGResolver.PendingPrompt(run, inst)
            if prompt ~= nil then
                pickers[#pickers + 1] = PromptRow(inst, prompt, placed.charid)
            end
        end
    elseif placed ~= nil then
        local allowedAttrs = MTGUtils.ToSet(ch:try_get("allowedCharacteristics", {}))
        local attrOptions = {}
        for _, option in ipairs(MTGUtils.CharacteristicOptions()) do
            local modifier = MTGUtils.CharacteristicModifier(placed.charid, option.id)
            attrOptions[#attrOptions + 1] = {
                id = option.id,
                text = string.format("%s %s", option.text, MTGUtils.SignedModifier(modifier)),
            }
        end

        local attrId = placed.attrId or ""
        pickers[#pickers + 1] = PickerRow(attrOptions, attrId, editable,
            cond(attrId ~= "" and not allowedAttrs[attrId],
                "Not one of this challenge's characteristics"),
            function(id)
                MTGRun.SetAssignmentCharacteristic(inst.id, slot, id)
            end)

        local allowedSkills = MTGUtils.ToSet(ch:try_get("allowedSkills", {}))
        local skillOptions = { { id = "", text = "No skill" } }
        for _, option in ipairs(MTGUtils.SkillOptionsFor(placed.charid)) do
            skillOptions[#skillOptions + 1] = option
        end

        local skillId = placed.skillId or ""
        pickers[#pickers + 1] = PickerRow(skillOptions, skillId, editable,
            cond(skillId ~= "" and not allowedSkills[skillId],
                "Not one of this challenge's skills"),
            function(id)
                MTGRun.SetAssignmentSkill(inst.id, slot, id)
            end)

        if inst.resolution ~= nil and inst.resolution.actionFor == placed.charid then
            pickers[#pickers + 1] = gui.Label{
                classes = { "sizeXs", "noBold", "fgMuted" },
                width = "100%",
                height = "auto",
                halign = "left",
                valign = "top",
                text = "Rolling...",
            }
        end
    end

    return gui.Panel{
        width = "33%",
        height = "auto",
        flow = "horizontal",
        valign = "top",

        Slot(run, inst, slot, label),

        gui.Panel{
            width = "96%-54",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "center",
            children = pickers,
        },
    }
end

--- @param image string
--- @param tooltip string
--- @param tone string|nil
--- @return Panel
local function Badge(image, tooltip, tone)
    return gui.Panel{
        classes = { MTGWidgets.ToneClass(tone) },
        width = 18,
        height = 18,
        halign = "right",
        valign = "center",
        lmargin = 6,
        bgimage = image,
        hover = gui.Tooltip(tooltip),
    }
end

--- The module's own fields, one label/value pair each.
--- @param run MTGRun
--- @param ch MTGChallengeDef
--- @return {label: string, value: string}[]
local function ModuleFields(run, ch)
    local result = {}
    for _, field in ipairs(MTGRules.GetOrDefault(run.moduleId).ChallengeFields()) do
        local value = ch:FieldValue(run.moduleId, field)
        if value ~= nil and value ~= "" then
            local text = tostring(value)
            for _, option in ipairs(field.options or {}) do
                if option.id == value then
                    text = option.text
                end
            end
            result[#result + 1] = { label = field.text, value = text }
        end
    end
    return result
end

--- @param run MTGRun
--- @param inst table
--- @return Panel
function MTGChallengeCard.Create(run, inst)
    local ch = MTGRun.ChallengeFor(run, inst)
    if ch == nil then
        return gui.Panel{ width = 0, height = 0 }
    end

    local adjudicated = inst.adjudicatedInRound ~= nil
    local status = MTGRules.GetOrDefault(run.moduleId).ChallengeStatus(run, inst, ch)

    local badges = {}
    if ch.repeatable == true then
        badges[#badges + 1] = Badge(MTGConstants.iconRepeatable, "Repeatable")
    end

    local resolving = inst.resolution ~= nil
    if dmhub.isDM and not adjudicated and inst.lead ~= nil and inst.leadRoll == nil then
        if resolving then
            badges[#badges + 1] = gui.Button{
                classes = { "sizeXs" },
                icon = MTGConstants.iconRoll,
                width = 22,
                height = 22,
                halign = "right",
                valign = "center",
                lmargin = 6,
                hover = gui.Tooltip("Waiting on the roll. Press to take it back."),
                click = function()
                    MTGResolver.Cancel(inst.id, inst.resolution.actionId)
                end,
            }
        else
            badges[#badges + 1] = gui.Button{
                classes = { "sizeXs" },
                icon = MTGConstants.iconRoll,
                width = 22,
                height = 22,
                halign = "right",
                valign = "center",
                lmargin = 6,
                hover = gui.Tooltip("Ask the Lead's player to roll"),
                click = function()
                    MTGResolver.Trigger(inst.id)
                end,
            }
        end
    end

    badges[#badges + 1] = Badge(status.icon, status.tooltip, status.tone)

    local children = {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            gui.Label{
                classes = { "sizeS", "bold" },
                width = "62%",
                height = "auto",
                halign = "left",
                valign = "center",
                text = ch.name or "",
            },

            gui.Panel{
                width = "34%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                children = badges,
            },
        },
    }

    if ch.description ~= nil and ch.description ~= "" then
        children[#children + 1] = gui.Label{
            classes = { "sizeXs", "noBold" },
            width = "100%",
            height = "auto",
            valign = "top",
            tmargin = 2,
            text = ch.description,
        }
    end

    local function MetaLine(label, value)
        return gui.Label{
            classes = { "sizeS", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            markdown = true,
            text = string.format("**%s:** %s", label, value),
        }
    end

    local metaLines = {}
    for _, field in ipairs(ModuleFields(run, ch)) do
        metaLines[#metaLines + 1] = MetaLine(field.label, field.value)
    end
    metaLines[#metaLines + 1] = MetaLine("Characteristics", MTGUtils.NameList(
        ch:try_get("allowedCharacteristics", {}), MTGUtils.CharacteristicName, "any"))
    metaLines[#metaLines + 1] = MetaLine("Skills", MTGUtils.NameList(
        ch:try_get("allowedSkills", {}), MTGUtils.SkillName, "none"))

    children[#children + 1] = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",
        tmargin = 4,

        gui.Panel{
            width = "34%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            children = metaLines,
        },

        SlotColumn(run, inst, ch, "lead", "Lead"),
        SlotColumn(run, inst, ch, "assist", "Assist"),
    }

    return gui.Panel{
        classes = { "bordered", cond(adjudicated, "disabled") },
        width = "97%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        pad = 8,
        vmargin = 4,
        children = children,
    }
end
