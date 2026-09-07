local mod = dmhub.GetModLoading()

--- Asks a Participant's player for a test and harvests the result.
MTGResolver = {}

--- The Director's answer for the request now out, or nil. Client-local by
--- nature: the resultTable belongs to their own summary dialog, and only their
--- client harvests. A reload drops it, which Pump reads as the dialog never
--- having been there and falls back to harvesting on completion.
--- One value, not a table keyed by row: Trigger admits only one roll at a time.
--- @type nil|{actionId: string, resultTable: table}
local g_pending = nil

--- The player-facing roll. Two independent axes meet here: `rollType` picks
--- the dialog, while GetModifiers passes a type from the modifier pipeline's
--- own closed vocabulary. A private id on that second axis silently drops
--- every Tests-scoped modifier, Skilled included.
RollCheck.RegisterCustom{
    id = MTGConstants.rollCheckId,
    rollType = "power_roll_custom",

    Describe = function(check, isplayer)
        return check.info.explanation
    end,

    GetRoll = function(check, creature)
        return "2d10 + " .. creature:AttributeMod(check.info.attrid)
    end,

    GetModifiers = function(check, creature)
        local result = creature:GetModifiersForPowerRoll(
            check:GetRoll(creature),
            MTGConstants.modifierRollType,
            { attribute = check.info.attrid, skills = check.skills })

        --The pipeline cannot know the skill was chosen for this test.
        local skillsTable = GetTableCached("Skills")
        for _, skillid in ipairs(check.skills or {}) do
            local skill = skillsTable[skillid]
            if skill ~= nil and creature:ProficientInSkill(skill) then
                for _, entry in ipairs(result) do
                    if entry.modifier.name == "Skilled" then
                        entry.hint.result = true
                    end
                end
            end
        end

        --The dialog reads .modifier off each entry, so a raw id would raise.
        local grant = check.info.assistGrant
        if grant ~= nil and grant ~= "" then
            local options = { attribute = check.info.attrid, skills = check.skills }
            local m = CharacterModifier.new{
                behavior = "power",
                rollType = MTGConstants.modifierRollType,
                modtype = grant,
                activationCondition = true,
                guid = dmhub.GenerateGuid(),
                name = check.info.assistName or "Assisted",
                description = check.info.assistDescription or "An ally assisted this test.",
                keywords = {},
            }

            local entry = { mod = m }
            local described = m:DescribeModifyPowerRoll(entry, creature,
                MTGConstants.modifierRollType, options)
            if described ~= nil then
                described.hint = described.modifier:HintModifyPowerRolls(entry, creature,
                    MTGConstants.modifierRollType, options)
                if described.hint ~= nil then
                    result[#result + 1] = described
                end
            end
        end

        for _, entry in pairs(check:try_get("modifiers", {})) do
            result[#result + 1] = entry
        end

        return result
    end,

    --The power table reads #tiers, so a table without them raises.
    ShowDialog = function(check, dialogOptions)
        --The frame's blur is what makes it see-through; opacity alone would not.
        dialogOptions.solidDialog = true

        local tiers = check:try_get("options", {}).tiers

        if tiers ~= nil then
            dialogOptions.rollProperties = RollPropertiesPowerTable.new{
                tiers = DeepCopy(tiers),
            }
            dialogOptions.PopulateCustom = ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(
                dialogOptions.rollProperties, dialogOptions.creature)
        end

        return GameHud.instance.rollDialog.data.ShowDialog(dialogOptions)
    end,
}

--- The modtype the assist's roll earned the Lead, or nil when the assist has
--- not rolled. Derived rather than stored, so undoing the assist roll takes
--- the grant with it.
--- @param run MTGRun
--- @param inst table
--- @return string|nil
function MTGResolver.AssistGrant(run, inst)
    if inst.assistRoll == nil then
        return nil
    end
    return MTGRules.GetOrDefault(run.moduleId).AssistGrant(inst.assistRoll.tier or 1)
end

--- Ask this Participant's player to roll.
--- @param run MTGRun
--- @param ch MTGChallengeDef
--- @param assignment table
--- @param grant string|nil a modtype the assist earned this roller
--- @param grantFrom string|nil who earned it
--- @param role string "lead" or "assist"
--- @return string|nil actionId
local function SendRequest(run, ch, assignment, grant, grantFrom, role)
    local attrName = MTGUtils.CharacteristicName(assignment.attrId)
    local skills = {}
    if assignment.skillId ~= nil and assignment.skillId ~= "" then
        skills[1] = assignment.skillId
    end

    local title = ch.name or "Montage test"
    if role == "assist" then
        title = string.format("Assist: %s", title)
    end

    local explanation = string.format("%s (%s)", title, attrName)

    --options.tiers, NOT info, is what the roll dialog reads.
    local rules = MTGRules.GetOrDefault(run.moduleId)

    local tiers = nil
    if role == "assist" then
        --An assist hands the Lead a grant, so AssistGrant is the text, not the outcomes.
        tiers = {}
        for tier = 1, 3 do
            local grantId = rules.AssistGrant(tier)
            tiers[tier] = string.format("The Lead rolls with %s %s",
                cond(grantId == "edge", "an", "a"),
                string.gsub(grantId, "_", " "))
        end
    elseif rules.TierLabels ~= nil then
        tiers = rules.TierLabels(run, ch)
    end

    local check = RollCheck.new{
        type = MTGConstants.rollCheckId,
        id = MTGConstants.rollCheckId,
        text = title,
        explanation = explanation,
        skills = skills,
        modifiers = {},
        options = tiers ~= nil and { tiers = tiers } or nil,
        info = {
            attrid = assignment.attrId,
            explanation = explanation,
            assistGrant = grant,
            assistName = grant ~= nil and string.format("Assisted by %s", grantFrom or "an ally") or nil,
            assistDescription = grant ~= nil and string.format("%s's assist gave you a %s.",
                grantFrom or "An ally", string.gsub(grant, "_", " ")) or nil,
        },
    }

    local actionId = dmhub.SendActionRequest(RollRequest.new{
        title = title,
        checks = { check },
        tokens = { [assignment.charid] = {} },
    })

    --Proceed accepts the roll, so the resultTable is kept and Pump waits on it.
    local hud = actionId ~= nil and GameHud.instance or nil
    if hud then
        local resultTable = {}
        hud:ShowRollSummaryDialog(actionId, resultTable)
        g_pending = { actionId = actionId, resultTable = resultTable }
    else
        g_pending = nil
    end

    return actionId
end

--- Ask for the next roll this row still needs: the Assist goes first, because
--- what it earns rides on the Lead's roll.
--- @param instanceId string
function MTGResolver.Trigger(instanceId)
    local run = MTGRun.Active()
    if run == nil then
        return
    end

    local inst = MTGRun.Instance(run, instanceId)
    if inst == nil or inst.adjudicatedInRound ~= nil or inst.lead == nil then
        return
    end

    --One at a time: a second would displace the shared summary dialog and lose that roll.
    local busy = MTGRun.ResolvingInstance(run)
    if busy ~= nil and busy.id ~= instanceId then
        return
    end

    local ch = MTGRun.ChallengeFor(run, inst)
    if ch == nil then
        return
    end

    local slot = "lead"
    local assignment = inst.lead
    local grant, grantFrom = nil, nil

    if inst.assist ~= nil and inst.assistRoll == nil then
        slot = "assist"
        assignment = inst.assist
    elseif inst.assist ~= nil then
        grant = MTGResolver.AssistGrant(run, inst)
        local p = MTGRun.Participant(run, inst.assist.charid)
        grantFrom = p ~= nil and p.name or nil
    end

    --Must land before the request, or the roll dialog beats the curtain to the screen.
    local startedAt = dmhub.serverTime

    MTGRun.SetResolution(instanceId, {
        phase = slot .. "_roll",
        slot = slot,
        actionFor = assignment.charid,
        startedAt = startedAt,
    })

    local actionId = SendRequest(run, ch, assignment, grant, grantFrom, slot)
    if actionId == nil then
        MTGRun.SetResolution(instanceId, nil)
        return
    end

    --A fresh table: assigning the document's own back over itself drops the new field.
    MTGRun.SetResolution(instanceId, {
        phase = slot .. "_roll",
        slot = slot,
        actionId = actionId,
        actionFor = assignment.charid,
        startedAt = startedAt,
    })
end

--- Take a row out of resolution and drop its request.
--- @param instanceId string
--- @param actionId string|nil
function MTGResolver.Cancel(instanceId, actionId)
    --Dropped first, so the dialog's dying result is not read against a live request.
    g_pending = nil

    if actionId ~= nil then
        dmhub.CancelActionRequest(actionId)
    end
    MTGRun.SetResolution(instanceId, nil)
end

--- Move any finished roll out of its request and onto the Run. Stateless and
--- idempotent: every input is cloud state, so a Director who reloads or who
--- put the montage away picks up wherever the Run says it is.
function MTGResolver.Pump()
    if not dmhub.isDM then
        return
    end

    local run = MTGRun.Active()
    if run == nil or run.status ~= MTGConstants.statusRunning then
        return
    end

    local inst = MTGRun.ResolvingInstance(run)
    if inst == nil then
        return
    end

    local res = inst.resolution

    --In flight, not lost: the nil lookup below would otherwise wipe it.
    if res.actionId == nil then
        return
    end

    --Read first: Proceed has already cancelled the request, which must not read as abandoned.
    local answer = nil
    if g_pending ~= nil and g_pending.actionId == res.actionId then
        answer = g_pending.resultTable
    end

    local req = dmhub.GetPlayerActionRequest(res.actionId)
    local info = req ~= nil and req.info.tokens[res.actionFor] or nil
    local status = info ~= nil and info.status or nil

    --A player dismissing their roll takes the request, and the dialog, down.
    if status == "cancel" then
        MTGResolver.Cancel(inst.id, res.actionId)
        return
    end

    local tokenInfo = nil

    if answer ~= nil then
        --Still on the Director's desk.
        if answer.result == nil then
            return
        end

        g_pending = nil

        --The dialog dropped the request on its way out; nothing left to cancel.
        if answer.result ~= true or answer.action == nil then
            MTGRun.SetResolution(inst.id, nil)
            return
        end

        --Snapshotted before the dialog cancelled the request.
        tokenInfo = answer.action.info.tokens[res.actionFor]
    else
        --No dialog: harvest on completion, and a vanished request was never asked.
        if req == nil then
            MTGRun.SetResolution(inst.id, nil)
            return
        end

        if status ~= "complete" then
            return
        end

        tokenInfo = info
        dmhub.CancelActionRequest(res.actionId)
    end

    if tokenInfo == nil or tokenInfo.status ~= "complete" then
        MTGRun.SetResolution(inst.id, nil)
        return
    end

    --Two edges bump the tier without moving the total.
    local rollInfo = {
        total = tokenInfo.result,
        naturalRoll = tokenInfo.naturalRoll,
        boons = tokenInfo.boons,
        banes = tokenInfo.banes,
    }
    rollInfo.tier = RollUtils.DiceResultToTier(rollInfo)

    local slot = res.slot or "lead"
    MTGRun.RecordRoll(inst.id, slot, rollInfo)

    if slot == "assist" then
        MTGResolver.Trigger(inst.id)
        return
    end

    local ch = MTGRun.ChallengeFor(run, inst)
    if ch == nil then
        return
    end

    local rules = MTGRules.GetOrDefault(run.moduleId)
    local outcome = rules.RollToOutcome(run, ch, rollInfo)

    --A module may refuse, leaving the row waiting on a human.
    if rules.PromptAfterRoll(run, ch, outcome) == nil then
        MTGRun.Adjudicate(inst.id, outcome)
    end
end

--- The question this row is waiting on, or nil when it is not waiting.
--- @param run MTGRun
--- @param inst table
--- @return table|nil
function MTGResolver.PendingPrompt(run, inst)
    if inst.leadRoll == nil or inst.adjudicatedInRound ~= nil then
        return nil
    end

    local ch = MTGRun.ChallengeFor(run, inst)
    if ch == nil then
        return nil
    end

    local rules = MTGRules.GetOrDefault(run.moduleId)
    return rules.PromptAfterRoll(run, ch, rules.RollToOutcome(run, ch, inst.leadRoll))
end

--- The Director's client drives resolution on a tick rather than from the
--- montage panel: hiding the montage to run combat destroys that panel, and
--- the harvest has to survive the trip.
local function Tick()
    if mod.unloaded then
        return
    end
    if dmhub.isDM then
        MTGResolver.Pump()
    end
    dmhub.Schedule(0.5, Tick)
end

dmhub.Schedule(0.5, Tick)
