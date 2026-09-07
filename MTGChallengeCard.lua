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

--- A Lead or Assist box: empty and waiting, or holding a participant. Its
--- drag state and token are fixed at construction, so the slot holding it
--- is remade when they move.
--- @param bound MTGRowBinding
--- @param slot string "lead" or "assist"
--- @param label string
--- @param inert boolean
--- @param dimmed boolean
--- @return Panel
local function SlotBox(bound, slot, label, inert, dimmed)
    local run = bound.run
    local inst = bound.inst
    local placed = inst[slot]

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
                            MTGRun.Unstage(bound.inst.id, slot)
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
            local token = MTGWidgets.ParticipantToken(p, not inert, removeMenu, dimmed)
            if token ~= nil then
                children[#children + 1] = token
            end
        end
    end

    return gui.Panel{
        classes = classes,
        width = 46,
        height = 46,
        flow = "none",
        halign = "center",
        valign = "top",
        dragTarget = not inert,
        hover = gui.Tooltip(label),

        dropOnSlot = function(element, charid)
            MTGRun.Stage(bound.inst.id, slot, charid)
        end,

        rightClick = removeMenu,

        press = function(element)
            if inert or placed ~= nil then
                return
            end

            --Read live: CanStage looks at rows this card's own data does not.
            local current = MTGRun.Active() or bound.run
            local entries = {}
            for _, p in ipairs(MTGRun.StageOptions(current, bound.inst, slot)) do
                local charid = p.charid
                if MTGRun.CanManage(charid) then
                    entries[#entries + 1] = {
                        text = p.name or "",
                        click = function()
                            element.popup = nil
                            MTGRun.Stage(bound.inst.id, slot, charid)
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
        verdict = string.format("Grants %s", string.gsub(grant or "bane", "_", " "))
    elseif inst.outcome ~= nil then
        verdict = inst.outcome.label
    else
        verdict = MTGRules.GetOrDefault(run.moduleId).RollToOutcome(run, ch, roll).label
    end

    return string.format("**%s**", verdict), table.concat(parts, " | ")
end

--- The module's question, answerable by whoever rolled and by the Director.
--- Sits in a slot remade when the prompt appears, so what it captures is
--- current for its life.
--- @param bound MTGRowBinding
--- @param prompt table
--- @param charid string the Lead who rolled
--- @return Panel
local function PromptRow(bound, prompt, charid)
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
                    MTGRun.Adjudicate(bound.inst.id, outcome)
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
--- stacked beside it, or the roll's summary once it has rolled. Built once;
--- `setColumn` reads the bound row.
--- @param bound MTGRowBinding
--- @param slot string
--- @param label string
--- @return Panel
local function SlotColumn(bound, slot, label)
    local shown = {}

    local boxSlot = MTGWidgets.Slot{ halign = "center", valign = "top" }

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

    local promptSlot = MTGWidgets.Slot{ width = "100%" }

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
            local boxState = table.concat({
                inst.id,
                placed ~= nil and placed.charid or "",
                tostring(inert),
                tostring(dimmed),
                tostring(canManage),
            }, "|")
            MTGWidgets.SetSlot(boxSlot, boxState, function()
                return SlotBox(bound, slot, label, inert, dimmed)
            end)

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
                attrRow:FireEvent("setPicker", attrOptions, attrId, editable,
                    attrId ~= "" and not allowedAttrs[attrId])

                local allowedSkills = MTGUtils.ToSet(ch:try_get("allowedSkills", {}))
                local skillOptions = { { id = "", text = "No skill" } }
                for _, option in ipairs(MTGUtils.SkillOptionsFor(placed.charid)) do
                    skillOptions[#skillOptions + 1] = option
                end
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
            local promptState = ""
            if prompt ~= nil then
                promptState = table.concat({
                    inst.id,
                    tostring(prompt.id),
                    placed.charid,
                    tostring(MTGRun.CanManage(placed.charid)),
                }, "|")
            end
            MTGWidgets.SetSlot(promptSlot, promptState, function()
                return PromptRow(bound, prompt, placed.charid)
            end)
        end,

        gui.Panel{
            width = 46,
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            rmargin = 8,

            boxSlot,

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
            promptSlot,
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
        if value ~= nil and value ~= "" then
            local text = tostring(value)
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

--- The Director's live switch for the Outcome line on the players' card. The
--- eye reports what was authored: once the Outcome has landed the table reads
--- it either way, and the tooltip says so rather than lighting an eye nobody
--- set.
--- @param run MTGRun
--- @param ch MTGChallengeDef
--- @return Panel
local function OutcomeEye(run, ch)
    local shown = MTGRun.IsOutcomeShown(run, ch.id)
    local landed = not shown and OutcomeRevealed(run, ch)

    local tip = "Kept from the table until it lands. Press to show it now."
    if landed then
        tip = "This Outcome has landed, so the table reads it either way."
    elseif shown then
        tip = "The table can read this Outcome. Press to keep it back."
    end

    return gui.Button{
        classes = { "sizeXs" },
        icon = cond(shown, "phosphor/eye-bold.png", "phosphor/eye-slash-duotone.png"),
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        rmargin = 6,
        hover = gui.Tooltip(tip),
        click = function()
            MTGRun.SetOutcomeShown(ch.id, not shown)
        end,
    }
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

--- One token per entry in a strip, each in a slot remade only when its hero
--- or its slot moves: a portrait is a new panel per hero.
--- @param strip Panel
--- @param entries table[] RollerEntries
local function BindTokens(strip, entries)
    MTGWidgets.BindList(strip, entries, function()
        return MTGWidgets.Slot{
            setToken = function(slot, entry)
                local state = ""
                if entry ~= nil then
                    state = entry.charid .. "|" .. entry.slot
                end
                MTGWidgets.SetSlot(slot, state, function()
                    local token = dmhub.GetCharacterById(entry.charid)
                    if token == nil then
                        return nil
                    end
                    return gui.CreateTokenImage(token, {
                        width = 22,
                        height = 22,
                        halign = "right",
                        valign = "center",
                        lmargin = 3,
                        hover = gui.Tooltip(string.format("%s (%s)", entry.name, entry.slot)),
                    })
                end)
            end,
        }
    end, "setToken")
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
        args.hover = gui.Tooltip(tooltip)
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

            local attemptsLeft = MTGRun.AttemptsLeft(run, ch)
            local repeats = not adjudicated and ch:RepeatLimit() > 0 and attemptsLeft > 1
            repeatBadge:SetClass("collapsed", not repeats)
            if repeats then
                local tip = string.format("%d more attempt%s after this one",
                    attemptsLeft - 1, cond(attemptsLeft - 1 == 1, "", "s"))
                if shown.repeatTip ~= tip then
                    shown.repeatTip = tip
                    repeatBadge.tooltip = gui.Tooltip(tip)
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
                        rollButton.tooltip = gui.Tooltip(tip)
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
                    hiddenEye.tooltip = gui.Tooltip(cond(hidden,
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
                statusBadge.tooltip = gui.Tooltip(tip)
            end
        end,

        children = children,
    }
end

--- Everything the meta lines show or hide, as one string.
--- @param run MTGRun
--- @param inst table
--- @param ch MTGChallengeDef
--- @return string
local function MetaState(run, inst, ch)
    local parts = { inst.id, ch.id, tostring(inst.adjudicatedInRound ~= nil) }
    for _, entry in ipairs(ModuleFields(run, ch)) do
        parts[#parts + 1] = string.format("%s=%s=%s=%s", entry.label, entry.value,
            tostring(entry.raw), tostring(entry.field.liveEditable == true))
    end
    parts[#parts + 1] = tostring(MTGRun.IsDifficultyHidden(run, ch.id))
    parts[#parts + 1] = tostring(MTGRun.IsOutcomeShown(run, ch.id))
    --OutcomeRevealed reads the T&O type field, which only T&O has.
    parts[#parts + 1] = tostring(run.moduleId == MTGConstants.moduleTO and OutcomeRevealed(run, ch))
    parts[#parts + 1] = MTGUtils.NameList(
        ch:try_get("allowedCharacteristics", {}), MTGUtils.CharacteristicName, "any")
    parts[#parts + 1] = MTGUtils.NameList(
        ch:try_get("allowedSkills", {}), MTGUtils.SkillName, "none")
    return table.concat(parts, "|")
end

--- The module's fields, the characteristics and the skills, one line each,
--- built for one state of the row. Remade as a whole when MetaState moves.
--- @param bound MTGRowBinding
--- @param director boolean
--- @return Panel
local function MetaLines(bound, director)
    local run = bound.run
    local inst = bound.inst
    local ch = bound.ch
    local adjudicated = inst.adjudicatedInRound ~= nil

    --- @param trailing nil|Panel a control sitting against the label
    local function MetaLine(label, value, trailing)
        local text = gui.Label{
            classes = { "sizeS", "fgMuted" },
            width = cond(trailing == nil, "100%", "100%-22"),
            height = "auto",
            halign = "left",
            valign = "top",
            markdown = true,
            text = string.format("**%s:** %s", label, value),
        }

        if trailing == nil then
            return text
        end

        --The control leads: a trailing one would land past the wrapped value.
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            trailing,
            text,
        }
    end

    --The control going away stops a late change looking like a rewritten verdict.
    local function MetaChoice(entry)
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            gui.Label{
                classes = { "sizeS", "fgMuted" },
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                rmargin = 4,
                markdown = true,
                text = string.format("**%s:**", entry.label),
            },

            gui.Dropdown{
                width = "50%",
                halign = "left",
                valign = "center",
                options = entry.field.options,
                idChosen = entry.raw,
                change = function(element)
                    MTGRun.SetChallengeField(bound.ch.id, entry.field.id, element.idChosen)
                end,
            },

            entry.field.id == "difficulty" and gui.Button{
                classes = { "sizeXs" },
                icon = cond(MTGRun.IsDifficultyHidden(run, ch.id),
                    "phosphor/eye-slash-duotone.png", "phosphor/eye-bold.png"),
                width = 16,
                height = 16,
                halign = "left",
                valign = "center",
                lmargin = 6,
                hover = gui.Tooltip(cond(MTGRun.IsDifficultyHidden(run, ch.id),
                    "Difficulty hidden from the table. Press to show it.",
                    "The table can see the difficulty. Press to hide it.")),
                click = function()
                    MTGRun.SetDifficultyHidden(bound.ch.id,
                        not MTGRun.IsDifficultyHidden(run, ch.id))
                end,
            } or nil,
        }
    end

    local metaLines = {}
    for _, entry in ipairs(ModuleFields(run, ch)) do
        local isOutcome = entry.field.id == "outcome"
            and run.moduleId == MTGConstants.moduleTO

        --Hidden means absent, not blanked.
        local suppressed = (entry.field.id == "difficulty"
                and not director
                and MTGRun.IsDifficultyHidden(run, ch.id))
            or (isOutcome and not director and not OutcomeRevealed(run, ch))

        if suppressed then
            --nothing on this line
        elseif dmhub.isDM and not adjudicated
            and entry.field.liveEditable == true
            and entry.field.type == "choice"
            and #(entry.field.options or {}) > 0 then
            metaLines[#metaLines + 1] = MetaChoice(entry)
        elseif isOutcome and director then
            metaLines[#metaLines + 1] = MetaLine(entry.label, entry.value,
                OutcomeEye(run, ch))
        else
            metaLines[#metaLines + 1] = MetaLine(entry.label, entry.value)
        end
    end
    metaLines[#metaLines + 1] = MetaLine("Characteristics", MTGUtils.NameList(
        ch:try_get("allowedCharacteristics", {}), MTGUtils.CharacteristicName, "any"))
    metaLines[#metaLines + 1] = MetaLine("Skills", MTGUtils.NameList(
        ch:try_get("allowedSkills", {}), MTGUtils.SkillName, "none"))

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        children = metaLines,
    }
end

--- One attempt row's card. Built once and handed a row with `setRow`;
--- handed nil, or a row whose Challenge is gone, it collapses and waits.
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

    local metaSlot = MTGWidgets.Slot{ width = "34%", height = "auto", valign = "top" }
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

            metaSlot,
            leadColumn,
            assistColumn,
        },
    }

    --Director side stays live: that is where the roll is taken back.
    local curtain = nil
    if not director then
        curtain = MTGWidgets.Overlay("Rolling in progress...", "sizeXl", 1, 8)
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

            MTGWidgets.SetSlot(metaSlot, MetaState(run, inst, ch), function()
                return MetaLines(bound, director)
            end)

            leadColumn:FireEvent("setColumn")
            assistColumn:FireEvent("setColumn")

            if curtain ~= nil then
                curtain:SetClass("collapsed", not (open and inst.resolution ~= nil))
            end
        end,

        children = children,
    }
end
