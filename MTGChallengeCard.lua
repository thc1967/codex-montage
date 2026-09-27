local mod = dmhub.GetModLoading()

--- One attempt row: a Challenge, its Lead and Assist slots, and its status.
MTGChallengeCard = {}

--- What every part of one card reads. `setRow` moves it.
--- @class MTGRowBinding
--- @field run MTGRun|nil
--- @field inst table|nil
--- @field ch MTGChallengeDef|nil
--- @field foldKey string|nil
--- @field open boolean
--- @field foldedTokens Panel|nil
--- @field openTokens Panel|nil

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
        hover = THCWidgets.Tooltip(tooltip),
    }
end

--- One labelled dropdown plus its off-list flag, built once. `setPicker`
--- hands it its options, pick, editability and whether the pick is off the
--- Challenge's list.
--- @param offListTip string
--- @param onChange fun(id: string)
--- @return Panel
local function PickerRow(offListTip, onChange)
    local dropdown = gui.Dropdown{
        width = "98%",
        halign = "left",
        valign = "center",
        options = {},
        idChosen = "",
        interactable = false,
        change = function(element)
            onChange(element.idChosen)
        end,
    }

    local icon = OffListIcon(offListTip)
    icon:SetClass("collapsed", true)

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",
        vmargin = 1,

        --- @param options {id: string, text: string}[]
        --- @param value string
        --- @param editable boolean
        --- @param offList boolean
        setPicker = function(element, options, value, editable, offList)
            if not dmhub.DeepEqual(dropdown.options, options) then
                dropdown.options = options
            end
            if dropdown.idChosen ~= value then
                dropdown.idChosen = value
            end
            if dropdown.interactable ~= editable then
                dropdown.interactable = editable
            end
            dropdown.selfStyle.width = cond(offList, "98%-24", "98%")
            icon:SetClass("collapsed", not offList)
        end,

        dropdown,
        icon,
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

--- What the roll was made of, once it has been made: the verdict line and
--- the parts line that replace the pickers, since the choices are spent and
--- what matters is what they produced.
--- @param run MTGRun
--- @param inst table
--- @param ch MTGChallengeDef
--- @param slot string
--- @param assignment table
--- @param roll table
--- @return string verdict
--- @return string parts
local function RollSummaryText(run, inst, ch, slot, assignment, roll)
    local parts = {
        string.format("Tier %d", roll.tier or 0),
        tostring(roll.total or 0),
        string.format("Natural %d", roll.naturalRoll or 0),
        string.format("%s %s",
            THCUtils.CharacteristicName(assignment.attrId),
            THCUtils.SignedModifier(THCUtils.CharacteristicModifier(assignment.charid, assignment.attrId))),
    }
    if assignment.skillId ~= nil and assignment.skillId ~= "" then
        parts[#parts + 1] = THCUtils.SkillName(assignment.skillId)
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
        verdict = string.format("Grants %s", string.gsub(grant or "bane", "_", " "))
    elseif inst.outcome ~= nil then
        verdict = inst.outcome.label
    else
        verdict = MTGRules.GetOrDefault(run.moduleId).RollToOutcome(run, ch, roll).label
    end

    return string.format("**%s**", verdict), table.concat(parts, " | ")
end

--- A muted line of the roll summary.
--- @return Panel
local function SummaryLine()
    return gui.Label{
        classes = { "sizeXs", "fgMuted", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        markdown = true,
        text = "",
    }
end

--- The Lead or Assist column: the box, with its characteristic and skill
--- stacked beside it, or the roll's summary once it has rolled, and the
--- module's prompt under the Lead. Every part is built once. `setColumn`
--- reads the bound row, and the handlers read it again when they fire, so a
--- column handed a new row never acts on the last one.
--- @param bound MTGRowBinding
--- @param slot string
--- @param label string
--- @return Panel
local function SlotColumn(bound, slot, label)
    local shown = {}

    --Whether this slot can change right now, read by the handlers.
    local m_inert = true

    --- Offer to remove whoever stands here, to someone who manages that hero,
    --- while the slot can still change. The menu acts on the row it opened on.
    --- @param element Panel
    local function OfferRemove(element)
        local inst = bound.inst
        local placed = inst ~= nil and inst[slot] or nil
        if placed == nil or m_inert or not MTGRun.CanManage(placed.charid) then
            return
        end

        local instId = inst.id
        element.popup = gui.ContextMenu{
            entries = {
                {
                    text = "Remove",
                    click = function()
                        element.popup = nil
                        MTGRun.Unstage(instId, slot)
                    end,
                },
            },
        }
    end

    local token = MTGWidgets.ParticipantToken()

    --Empty and waiting, or holding a participant.
    local box = gui.Panel{
        classes = { "bordered", "mtgSlot", "disabled" },
        width = 46,
        height = 46,
        flow = "none",
        halign = "center",
        valign = "top",
        dragTarget = false,
        hover = THCWidgets.Tooltip(label),

        dropOnSlot = function(element, charid)
            if bound.inst ~= nil and not m_inert then
                MTGRun.Stage(bound.inst.id, slot, charid)
            end
        end,

        rightClick = OfferRemove,

        --An empty slot offers everyone who could stand in it. The menu acts on
        --the row it opened on.
        press = function(element)
            local inst = bound.inst
            if inst == nil or m_inert or inst[slot] ~= nil then
                return
            end

            --Read live: CanStage looks at rows this card's own data does not.
            local current = MTGRun.Active() or bound.run
            local instId = inst.id
            local entries = {}
            for _, p in ipairs(MTGRun.StageOptions(current, inst, slot)) do
                local charid = p.charid
                if MTGRun.CanManage(charid) then
                    entries[#entries + 1] = {
                        text = p.name or "",
                        click = function()
                            element.popup = nil
                            MTGRun.Stage(instId, slot, charid)
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

        token,
    }

    local attrRow = PickerRow("Not one of this challenge's characteristics", function(id)
        MTGRun.SetAssignmentCharacteristic(bound.inst.id, slot, id)
    end)
    local skillRow = PickerRow("Not one of this challenge's skills", function(id)
        MTGRun.SetAssignmentSkill(bound.inst.id, slot, id)
    end)

    local rollingLabel = gui.Label{
        classes = { "sizeXs", "noBold", "fgMuted", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        text = "Rolling...",
    }

    local verdictLine = SummaryLine()
    local partsLine = SummaryLine()

    local promptText = gui.Label{
        classes = { "sizeXs", "noBold", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        text = "",
    }

    --- One of the prompt's answers, handed its option with `setOption`.
    --- @return Panel
    local function PromptButton()
        local m_outcome = nil
        return gui.Button{
            classes = { "sizeXxs", "collapsed" },
            width = "48%",
            height = 22,
            halign = "left",
            rmargin = 4,
            text = "",

            --- @param option nil|{label: string, outcome: table}
            setOption = function(element, option)
                element:SetClass("collapsed", option == nil)
                m_outcome = option ~= nil and option.outcome or nil
                if option ~= nil then
                    local text = option.label or ""
                    if element.text ~= text then
                        element.text = text
                    end
                end
            end,

            click = function()
                if bound.inst ~= nil and m_outcome ~= nil then
                    MTGRun.Adjudicate(bound.inst.id, m_outcome)
                end
            end,
        }
    end

    local promptButtons = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",
        tmargin = 2,
    }

    --The module's question, answerable by whoever rolled and by the Director.
    local promptRow = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        promptText,
        promptButtons,
    }

    return gui.Panel{
        width = "33%",
        height = "auto",
        flow = "horizontal",
        valign = "top",

        setColumn = function(element)
            local run = bound.run
            local inst = bound.inst
            local ch = bound.ch
            local placed = inst[slot]

            --A roll in flight freezes the slot: its inputs are out with the request.
            local inert = inst.adjudicatedInRound ~= nil or inst[slot .. "Roll"] ~= nil
                or inst.resolution ~= nil
            --Dimmed means spent or already acted this round; both read the same.
            local dimmed = placed ~= nil and (inert or MTGRun.HasActedThisRound(run, placed.charid))
            local canManage = placed ~= nil and MTGRun.CanManage(placed.charid)

            m_inert = inert
            box:SetClass("disabled", inert)
            if box.dragTarget ~= (not inert) then
                box.dragTarget = not inert
            end

            local p = placed ~= nil and MTGRun.Participant(run, placed.charid) or nil
            token:FireEvent("setParticipant", p ~= nil and {
                p = p,
                draggable = not inert,
                dimmed = dimmed,
                onRightClick = OfferRemove,
            } or nil)

            local locked = inst.adjudicatedInRound ~= nil or inst.resolution ~= nil
            local editable = placed ~= nil and not locked and canManage
            local roll = placed ~= nil and inst[slot .. "Roll"] or nil
            local picking = placed ~= nil and roll == nil

            attrRow:SetClass("collapsed", not picking)
            skillRow:SetClass("collapsed", not picking)
            rollingLabel:SetClass("collapsed", not (picking
                and inst.resolution ~= nil and inst.resolution.actionFor == placed.charid))
            verdictLine:SetClass("collapsed", roll == nil)
            partsLine:SetClass("collapsed", roll == nil)

            if picking then
                local allowedAttrs = THCUtils.ToSet(ch:try_get("allowedCharacteristics", {}))
                local attrOptions = {}
                for _, option in ipairs(THCUtils.CharacteristicOptions()) do
                    local modifier = THCUtils.CharacteristicModifier(placed.charid, option.id)
                    attrOptions[#attrOptions + 1] = {
                        id = option.id,
                        text = string.format("%s %s", option.text, THCUtils.SignedModifier(modifier)),
                    }
                end
                local attrId = placed.attrId or ""
                attrRow:FireEvent("setPicker", attrOptions, attrId, editable,
                    attrId ~= "" and not allowedAttrs[attrId])

                local allowedSkills = THCUtils.ToSet(ch:try_get("allowedSkills", {}))
                local skillOptions = THCUtils.SkillOptionsFor(placed.charid, true)
                local skillId = placed.skillId or ""
                skillRow:FireEvent("setPicker", skillOptions, skillId, editable,
                    skillId ~= "" and not allowedSkills[skillId])
            end

            if roll ~= nil then
                local verdict, parts = RollSummaryText(run, inst, ch, slot, placed, roll)
                if shown.verdict ~= verdict then
                    shown.verdict = verdict
                    verdictLine.text = verdict
                end
                if shown.parts ~= parts then
                    shown.parts = parts
                    partsLine.text = parts
                end
            end

            local prompt = nil
            if roll ~= nil and slot == "lead" then
                prompt = MTGResolver.PendingPrompt(run, inst)
            end
            promptRow:SetClass("collapsed", prompt == nil)
            if prompt ~= nil then
                local text = prompt.text or ""
                if promptText.text ~= text then
                    promptText.text = text
                end
                local options = {}
                if MTGRun.CanManage(placed.charid) then
                    options = prompt.options or {}
                end
                promptButtons:SetClass("collapsed", #options == 0)
                THCWidgets.BindList(promptButtons, options, PromptButton, "setOption")
            end
        end,

        gui.Panel{
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
        },

        gui.Panel{
            width = "96%-54",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "center",

            attrRow,
            skillRow,
            rollingLabel,
            verdictLine,
            partsLine,
            promptRow,
        },
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
        --An empty note still wants its input on the Director's card.
        local editableText = dmhub.isDM and field.liveEditable == true and field.type == "text"
        if (value ~= nil and value ~= "") or editableText then
            local text = tostring(value or "")
            for _, option in ipairs(field.options or {}) do
                if option.id == value then
                    text = option.text
                end
            end
            --field and raw ride along so a live card can offer the pick.
            result[#result + 1] = {
                label = field.text,
                value = text,
                field = field,
                raw = value
            }
        end
    end
    return result
end

--- Whether the table may read this Challenge's T&O Outcome. The eye is the
--- Director's standing answer; a Challenge whose Outcome has actually landed
--- overrides it, because by then the party is living with the result.
--- @param run MTGRun
--- @param ch MTGChallengeDef
--- @return boolean
local function OutcomeRevealed(run, ch)
    if MTGRun.IsOutcomeShown(run, ch.id) then
        return true
    end

    --Still attemptable is still undecided, whichever way the last try went.
    if MTGRun.AttemptsLeft(run, ch) > 0 then
        return false
    end

    --Not ChallengeModuleState: it CREATES its table, a write a render must not make.
    local all = run:try_get("challengeModuleState") or {}
    local resolved = (all[ch.id] or {}).resolved == true

    --Same flag, opposite sense: a Threat pays out when left standing.
    if ch:FieldsFor(run.moduleId).type == "opportunity" then
        return resolved
    end
    return not resolved
end

--- The heroes who rolled - or, for the folded strip, whoever is placed - as
--- token entries. Small and in full colour: unlike the slots, which grey a
--- spent token out, this is a summary and wants to be readable.
--- @param run MTGRun
--- @param inst table
--- @param always boolean show whoever is placed, not just whoever has rolled
--- @return {charid: string, slot: string, name: string}[]
local function RollerEntries(run, inst, always)
    local result = {}
    for _, slot in ipairs({ "lead", "assist" }) do
        local placed = inst[slot]
        if placed ~= nil and (always
            or inst[slot .. "Roll"] ~= nil or inst.granted == true) then
            local p = MTGRun.Participant(run, placed.charid)
            result[#result + 1] = {
                charid = placed.charid,
                slot = slot,
                name = p ~= nil and p.name or "",
            }
        end
    end
    return result
end

--- One roller's portrait in the header strip, built once and handed an
--- entry with `setToken`. The engine's token image is retargeted rather than
--- remade when the hero moves. Handed nil, it collapses.
--- @return Panel
local function RollerToken()
    local image = gui.CreateTokenImage(nil, {
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
    })

    local shown = {}

    return gui.Panel{
        classes = { "collapsed" },
        width = 22,
        height = 22,
        halign = "right",
        valign = "center",
        lmargin = 3,

        --- @param entry nil|{charid: string, slot: string, name: string}
        setToken = function(element, entry)
            local token = entry ~= nil and dmhub.GetCharacterById(entry.charid) or nil
            element:SetClass("collapsed", token == nil)
            if token == nil then
                return
            end

            if shown.charid ~= entry.charid then
                shown.charid = entry.charid
                MTGWidgets.RetargetPortrait(image, token)
            end

            local tip = string.format("%s (%s)", entry.name, entry.slot)
            if shown.tip ~= tip then
                shown.tip = tip
                element.tooltip = THCWidgets.Tooltip(tip)
            end
        end,

        image,
    }
end

--- One portrait per entry in a strip, pooled and rebound.
--- @param strip Panel
--- @param entries table[] RollerEntries
local function BindTokens(strip, entries)
    THCWidgets.BindList(strip, entries, RollerToken, "setToken")
end

--- A header badge whose image, tone and tooltip are patched onto it, so it
--- is built with none of them.
--- @return Panel
local function PatchedBadge()
    return gui.Panel{
        classes = { "bgFg" },
        width = 18,
        height = 18,
        halign = "right",
        valign = "center",
        lmargin = 6,
        bgimage = MTGConstants.iconPending,
    }
end

--- A Director's header button with a fixed face. One whose tooltip moves is
--- built with none and has it patched on.
--- @param icon string
--- @param tooltip string|nil
--- @param click fun(element: Panel)
--- @return Panel
local function HeaderButton(icon, tooltip, click)
    local args = {
        classes = { "sizeXs" },
        icon = icon,
        width = 22,
        height = 22,
        halign = "right",
        valign = "center",
        lmargin = 6,
        click = click,
    }
    if tooltip ~= nil then
        args.hover = THCWidgets.Tooltip(tooltip)
    end
    return gui.Button(args)
end

--- The strip of badges on a card's header, built once: the repeat badge, the
--- roller tokens, the Director's cancel, roll, grant, undo and hide controls,
--- and the status. `refreshBadges` patches each from the bound row: presence
--- through "collapsed", tooltips through `.tooltip`, icons through `setIcon`,
--- the status through its image and tone class.
--- @param bound MTGRowBinding
--- @param director boolean
--- @return Panel
local function BadgeBar(bound, director)
    local shown = { statusTone = "bgFg" }

    local repeatBadge = PatchedBadge()
    repeatBadge.bgimage = MTGConstants.iconRepeatable

    --Two strips because the expando toggles classes rather than rebuilding.
    local function TokenStrip()
        return gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            valign = "center",
        }
    end
    bound.foldedTokens = TokenStrip()
    bound.openTokens = TokenStrip()

    local kindBadge = MTGWidgets.KindBadge(18, 6)
    local children = { repeatBadge, bound.foldedTokens, bound.openTokens }

    --The roll button holds its place greyed, so the Director sees it is a step away.
    local cancelButton = nil
    local rollButton = nil
    local grantButton = nil
    local undoButton = nil
    if dmhub.isDM then
        cancelButton = HeaderButton(MTGConstants.iconRoll,
            "Waiting on the roll. Press to take it back.", function()
                local resolution = bound.inst.resolution
                if resolution ~= nil then
                    MTGResolver.Cancel(bound.inst.id, resolution.actionId)
                end
            end)
        rollButton = HeaderButton(MTGConstants.iconRoll, nil, function(element)
            if element:HasClass("disabled") then
                return
            end
            MTGResolver.Trigger(bound.inst.id)
        end)
        grantButton = HeaderButton(MTGConstants.iconGrant,
            "Grant this to the Lead, no roll", function()
                MTGRun.Grant(bound.inst.id)
            end)
        undoButton = HeaderButton("icons/standard/Icon_App_Undo.png",
            "Undo this test", function()
                MTGRun.UndoTest(bound.inst.id)
            end)
        children[#children + 1] = cancelButton
        children[#children + 1] = rollButton
        children[#children + 1] = grantButton
        children[#children + 1] = undoButton
    end

    --Director only: a hidden Challenge is not drawn on the players' board.
    local hiddenEye = nil
    if director then
        hiddenEye = HeaderButton("phosphor/eye-bold.png", nil, function()
            MTGRun.SetChallengeHidden(bound.ch.id,
                not MTGRun.IsChallengeHidden(bound.run, bound.ch.id))
        end)
        children[#children + 1] = hiddenEye
    end

    local statusBadge = PatchedBadge()
    children[#children + 1] = kindBadge
    children[#children + 1] = statusBadge

    return gui.Panel{
        width = "34%",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",

        refreshBadges = function()
            local run = bound.run
            local inst = bound.inst
            local ch = bound.ch
            local adjudicated = inst.adjudicatedInRound ~= nil
            MTGWidgets.PatchKindBadge(kindBadge, shown, ch, run.moduleId)

            local attemptsLeft = MTGRun.AttemptsLeft(run, ch)
            local repeats = not adjudicated and ch:RepeatLimit() > 0 and attemptsLeft > 1
            repeatBadge:SetClass("collapsed", not repeats)
            if repeats then
                local tip = string.format("%d more attempt%s after this one",
                    attemptsLeft - 1, cond(attemptsLeft - 1 == 1, "", "s"))
                if shown.repeatTip ~= tip then
                    shown.repeatTip = tip
                    repeatBadge.tooltip = THCWidgets.Tooltip(tip)
                end
            end

            BindTokens(bound.foldedTokens, RollerEntries(run, inst, true))
            BindTokens(bound.openTokens, RollerEntries(run, inst, false))
            bound.foldedTokens:SetClass("collapsed", bound.open)
            bound.openTokens:SetClass("collapsed", not bound.open)

            if rollButton ~= nil then
                local waiting = not adjudicated and inst.leadRoll == nil
                local resolving = inst.resolution ~= nil
                cancelButton:SetClass("collapsed", not (waiting and resolving))
                rollButton:SetClass("collapsed", not (waiting and not resolving))
                if waiting and not resolving then
                    --One roll at a time: the summary dialog is a single shared panel.
                    local ready = inst.lead ~= nil
                    local busy = MTGRun.ResolvingInstance(run)
                    local blocked = busy ~= nil and busy.id ~= inst.id
                    rollButton:SetClass("disabled", not (ready and not blocked))
                    local tip = cond(blocked,
                        "Another row's roll is out",
                        cond(ready,
                            "Request rolls",
                            "Put a Hero in the Lead slot first"))
                    if shown.rollTip ~= tip then
                        shown.rollTip = tip
                        rollButton.tooltip = THCWidgets.Tooltip(tip)
                    end
                end

                local undoable = MTGRun.HasTestToUndo(run, inst)
                grantButton:SetClass("collapsed", not (not adjudicated
                    and inst.lead ~= nil and inst.resolution == nil and not undoable))
                undoButton:SetClass("collapsed", not undoable)
            end

            if hiddenEye ~= nil then
                local hidden = MTGRun.IsChallengeHidden(run, ch.id)
                if shown.hidden ~= hidden then
                    shown.hidden = hidden
                    hiddenEye:FireEvent("setIcon",
                        cond(hidden, "phosphor/eye-slash-duotone.png", "phosphor/eye-bold.png"))
                    hiddenEye.tooltip = THCWidgets.Tooltip(cond(hidden,
                        "Hidden from the table. Press to reveal it.",
                        "The table can see this. Press to hide it."))
                end
            end

            local status = MTGRules.GetOrDefault(run.moduleId).ChallengeStatus(run, inst, ch)
            if shown.statusIcon ~= status.icon then
                shown.statusIcon = status.icon
                statusBadge.bgimage = status.icon
            end
            shown.statusTone = MTGWidgets.SwapClass(statusBadge, shown.statusTone,
                MTGWidgets.ToneClass(status.tone))
            local tip = status.tooltip or ""
            if shown.statusTip ~= tip then
                shown.statusTip = tip
                statusBadge.tooltip = THCWidgets.Tooltip(tip)
            end
        end,

        children = children,
    }
end

--- What the meta area shows for one state of the row, as data: a column of
--- lines beside the slots, and a band beneath them holding the Outcome and
--- the Director's notes. Each entry names its shape, so one pooled row can
--- present any of them and field order survives. Hidden means absent, not
--- blanked.
--- @param run MTGRun
--- @param inst table
--- @param ch MTGChallengeDef
--- @param director boolean
--- @return table[] column
--- @return table[] band
local function MetaEntries(run, inst, ch, director)
    local adjudicated = inst.adjudicatedInRound ~= nil
    local column = {}
    local band = {}

    for _, entry in ipairs(ModuleFields(run, ch)) do
        local fieldId = entry.field.id
        local isOutcome = fieldId == "outcome"
            and run.moduleId == MTGConstants.moduleTO

        local suppressed = (fieldId == "difficulty"
                and not director
                and MTGRun.IsDifficultyHidden(run, ch.id))
            or (isOutcome and not director and not OutcomeRevealed(run, ch))
            or (entry.field.directorOnly == true and not director)

        if suppressed then
            --nothing on this line
        elseif dmhub.isDM and not adjudicated
            and entry.field.liveEditable == true
            and entry.field.type == "choice"
            and #(entry.field.options or {}) > 0 then
            --The control going away stops a late change looking like a
            --rewritten verdict.
            local line = {
                kind = "choice",
                label = entry.label,
                fieldId = fieldId,
                options = entry.field.options,
                raw = entry.raw,
            }
            if fieldId == "difficulty" then
                local hidden = MTGRun.IsDifficultyHidden(run, ch.id)
                line.eye = "difficulty"
                line.eyeOpen = not hidden
                line.eyeTip = cond(hidden,
                    "Difficulty hidden from the table. Press to show it.",
                    "The table can see the difficulty. Press to hide it.")
            end
            column[#column + 1] = line
        elseif dmhub.isDM and entry.field.liveEditable == true
            and entry.field.type == "text" then
            band[#band + 1] = {
                kind = "note",
                label = entry.label,
                fieldId = fieldId,
                raw = entry.raw,
            }
        elseif isOutcome then
            local line = {
                kind = "line",
                label = entry.label,
                value = entry.value,
            }
            --The eye reports what was authored: once the Outcome has landed the
            --table reads it either way, and the tooltip says so rather than
            --lighting an eye nobody set.
            if director then
                local shown = MTGRun.IsOutcomeShown(run, ch.id)
                line.eye = "outcome"
                line.eyeOpen = shown
                if shown then
                    line.eyeTip = "The table can read this Outcome. Press to keep it back."
                elseif OutcomeRevealed(run, ch) then
                    line.eyeTip = "This Outcome has landed, so the table reads it either way."
                else
                    line.eyeTip = "Kept from the table until it lands. Press to show it now."
                end
            end
            band[#band + 1] = line
        else
            column[#column + 1] = {
                kind = "line",
                label = entry.label,
                value = entry.value,
            }
        end
    end

    column[#column + 1] = {
        kind = "line",
        label = "Characteristics",
        value = THCUtils.NameList(ch:try_get("allowedCharacteristics", {}),
            THCUtils.CharacteristicName, "any"),
    }
    column[#column + 1] = {
        kind = "line",
        label = "Skills",
        value = THCUtils.NameList(ch:try_get("allowedSkills", {}),
            THCUtils.SkillName, "none"),
    }

    return column, band
end

--- One line of the meta area, built once and handed an entry with
--- `setMeta`: a plain line, with the Outcome's eye leading it when it has
--- one; a live choice, with the difficulty's eye after it; or the Director's
--- note, the label over a full-width field. It holds all three and shows the
--- one its entry names. Handed nil, it collapses.
---
--- The note is written on commit, and its field is only refilled when the
--- committed value moves, so neither the echo of the Director's own write nor
--- any other change to the row takes the caret.
--- @param bound MTGRowBinding
--- @return Panel
local function MetaRow(bound)
    local shown = {}

    --The field this row edits, read by the handlers when they fire.
    local m_fieldId = nil

    --- Show an eye's state; open means the table can see it.
    --- @param eye Panel
    --- @param key string this eye's memo slot
    --- @param open boolean
    --- @param tip string
    local function PatchEye(eye, key, open, tip)
        if shown[key .. "Open"] ~= open then
            shown[key .. "Open"] = open
            eye:FireEvent("setIcon",
                cond(open, "phosphor/eye-bold.png", "phosphor/eye-slash-duotone.png"))
        end
        if shown[key .. "Tip"] ~= tip then
            shown[key .. "Tip"] = tip
            eye.tooltip = THCWidgets.Tooltip(tip)
        end
    end

    --- @param label Panel
    --- @param text string
    local function SetText(label, text)
        if label.text ~= text then
            label.text = text
        end
    end

    local outcomeEye = gui.Button{
        classes = { "sizeXs", "collapsed" },
        icon = "phosphor/eye-slash-duotone.png",
        width = 16,
        height = 16,
        halign = "left",
        valign = "top",
        rmargin = 6,
        click = function()
            local run = bound.run
            local ch = bound.ch
            if run ~= nil and ch ~= nil then
                MTGRun.SetOutcomeShown(ch.id, not MTGRun.IsOutcomeShown(run, ch.id))
            end
        end,
    }

    local lineText = gui.Label{
        classes = { "sizeS", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        markdown = true,
        text = "",
    }

    --The eye leads: a trailing one would land past the wrapped value.
    local lineRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",

        outcomeEye,
        lineText,
    }

    local choiceLabel = gui.Label{
        classes = { "sizeS", "fgMuted" },
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        rmargin = 4,
        markdown = true,
        text = "",
    }

    local dropdown = gui.Dropdown{
        width = "50%",
        halign = "left",
        valign = "center",
        options = {},
        idChosen = "",
        change = function(element)
            local ch = bound.ch
            if ch ~= nil and m_fieldId ~= nil then
                MTGRun.SetChallengeField(ch.id, m_fieldId, element.idChosen)
            end
        end,
    }

    local difficultyEye = gui.Button{
        classes = { "sizeXs", "collapsed" },
        icon = "phosphor/eye-bold.png",
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        lmargin = 6,
        click = function()
            local run = bound.run
            local ch = bound.ch
            if run ~= nil and ch ~= nil then
                MTGRun.SetDifficultyHidden(ch.id, not MTGRun.IsDifficultyHidden(run, ch.id))
            end
        end,
    }

    local choiceRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",

        choiceLabel,
        dropdown,
        difficultyEye,
    }

    local noteLabel = gui.Label{
        classes = { "sizeS", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        markdown = true,
        text = "",
    }

    local noteInput = gui.Input{
        classes = { "input", "sizeS" },
        height = MTGConstants.noteInputHeight,
        width = "100%-16",
        halign = "left",
        valign = "top",
        text = "",
        characterLimit = 200,
        change = function(element)
            local ch = bound.ch
            if ch ~= nil and m_fieldId ~= nil then
                MTGRun.SetChallengeField(ch.id, m_fieldId, element.text or "")
            end
        end,
    }

    local noteGroup = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        noteLabel,
        noteInput,
    }

    return gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        --- @param entry nil|table a MetaEntries line
        setMeta = function(element, entry)
            element:SetClass("collapsed", entry == nil)
            if entry == nil then
                m_fieldId = nil
                return
            end

            m_fieldId = entry.fieldId
            lineRow:SetClass("collapsed", entry.kind ~= "line")
            choiceRow:SetClass("collapsed", entry.kind ~= "choice")
            noteGroup:SetClass("collapsed", entry.kind ~= "note")

            if entry.kind == "line" then
                local hasEye = entry.eye == "outcome"
                outcomeEye:SetClass("collapsed", not hasEye)
                local width = cond(hasEye, "100%-22", "100%")
                if shown.lineWidth ~= width then
                    shown.lineWidth = width
                    lineText.selfStyle.width = width
                end
                SetText(lineText, string.format("**%s:** %s", entry.label, entry.value))
                if hasEye then
                    PatchEye(outcomeEye, "outcome", entry.eyeOpen, entry.eyeTip)
                end
            elseif entry.kind == "choice" then
                SetText(choiceLabel, string.format("**%s:**", entry.label))
                if not dmhub.DeepEqual(dropdown.options, entry.options) then
                    dropdown.options = entry.options
                end
                if dropdown.idChosen ~= entry.raw then
                    dropdown.idChosen = entry.raw
                end
                local hasEye = entry.eye == "difficulty"
                difficultyEye:SetClass("collapsed", not hasEye)
                if hasEye then
                    PatchEye(difficultyEye, "difficulty", entry.eyeOpen, entry.eyeTip)
                end
            else
                SetText(noteLabel, string.format("**%s:**", entry.label))
                --Keyed by row and field, so a row handed a different note is
                --refilled even when the text happens to match.
                local key = (bound.ch ~= nil and bound.ch.id or "") .. "/" .. tostring(entry.fieldId)
                local committed = tostring(entry.raw or "")
                if shown.noteKey ~= key or shown.noteText ~= committed then
                    shown.noteKey = key
                    shown.noteText = committed
                    if noteInput.text ~= committed then
                        noteInput.text = committed
                    end
                end
            end
        end,

        lineRow,
        choiceRow,
        noteGroup,
    }
end

--- One attempt row's card. Built once and handed a row with `setRow`;
--- handed nil, or a row whose Challenge is gone, it collapses and waits.
--- Nothing inside it is remade either: every part is built here and rebound,
--- and its lists are pools.
--- @param director boolean
--- @param expanded table<string, boolean> this client's overrides, by instance
--- @return Panel
function MTGChallengeCard.Create(director, expanded)
    --- @type MTGRowBinding
    local bound = { open = false }

    local shown = {}

    local titleLabel = gui.Label{
        classes = { "sizeS", "bold" },
        width = "58%",
        height = "auto",
        halign = "left",
        valign = "center",
        text = "",
    }

    local badgeBar = BadgeBar(bound, director)

    local descriptionLabel = gui.Label{
        classes = { "sizeXs", "noBold", "collapsed" },
        width = "100%",
        height = "auto",
        valign = "top",
        tmargin = 2,
        text = "",
    }

    --The meta column beside the slots and the band beneath them, both pools of
    --meta rows rebound on every refresh.
    local metaColumn = gui.Panel{
        width = "34%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }
    local noteBand = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }

    --- @return Panel
    local function NewMetaRow()
        return MetaRow(bound)
    end

    local leadColumn = SlotColumn(bound, "lead", "Lead")
    local assistColumn = SlotColumn(bound, "assist", "Assist")

    local body = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        descriptionLabel,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            tmargin = 4,

            metaColumn,
            leadColumn,
            assistColumn,
        },

        noteBand,
    }

    --Director side stays live: that is where the roll is taken back.
    local curtain = nil
    if not director then
        curtain = THCWidgets.Overlay("Rolling in progress...", "sizeXl", 1, 8)
    end

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
            bound.open = nowOpen
            expanded[bound.foldKey] = nowOpen
            body:SetClass("collapsed", not nowOpen)
            bound.foldedTokens:SetClass("collapsed", nowOpen)
            bound.openTokens:SetClass("collapsed", not nowOpen)
            if curtain ~= nil then
                curtain:SetClass("collapsed", not (nowOpen and bound.inst.resolution ~= nil))
            end
        end,
    }

    local children = {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            arrow,
            titleLabel,
            badgeBar,
        },

        body,
    }
    if curtain ~= nil then
        children[#children + 1] = curtain
    end

    return gui.Panel{
        classes = { "bordered" },
        width = "97%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        pad = 8,
        vmargin = 4,

        --- @param item nil|{run: MTGRun, inst: table, pinned: boolean}
        setRow = function(element, item)
            local ch = item ~= nil and MTGRun.ChallengeFor(item.run, item.inst) or nil
            element:SetClass("collapsed", ch == nil)
            if ch == nil then
                return
            end

            local run = item.run
            local inst = item.inst
            bound.run = run
            bound.inst = inst
            bound.ch = ch

            local adjudicated = inst.adjudicatedInRound ~= nil
            element:SetClass("disabled", adjudicated)

            --Keyed by phase: settling clears the memo, so a settled row folds away.
            bound.foldKey = inst.id .. cond(adjudicated, "/done", "")
            local open = expanded[bound.foldKey]
            if open == nil then
                open = (director or item.pinned) and not adjudicated
            end
            bound.open = open
            arrow:SetClass("expanded", open)
            body:SetClass("collapsed", not open)

            local title = ch.name or ""
            if shown.title ~= title then
                shown.title = title
                titleLabel.text = title
            end
            local description = ch.description or ""
            if shown.description ~= description then
                shown.description = description
                descriptionLabel.text = description
                descriptionLabel:SetClass("collapsed", description == "")
            end

            badgeBar:FireEvent("refreshBadges")

            local column, band = MetaEntries(run, inst, ch, director)
            THCWidgets.BindList(metaColumn, column, NewMetaRow, "setMeta")
            THCWidgets.BindList(noteBand, band, NewMetaRow, "setMeta")

            leadColumn:FireEvent("setColumn")
            assistColumn:FireEvent("setColumn")

            if curtain ~= nil then
                curtain:SetClass("collapsed", not (open and inst.resolution ~= nil))
            end
        end,

        children = children,
    }
end
