local mod = dmhub.GetModLoading()

--- Asks a Participant's player for a test and harvests the result. The
--- conversation itself -- request, summary dialog, reading the answer back --
--- is THCRoll's; what stays here is which roll a row still needs and what the
--- montage does with the result.
MTGResolver = {}

--- The player-facing roll. Only the assist grant is ours; THCRoll supplies the
--- rest of the check.
THCRoll.RegisterCheck{
    id = MTGConstants.rollCheckId,
    modifierRollType = MTGConstants.modifierRollType,

    DecorateModifiers = function(check, creature, options, result)
        local grant = check.info.assistGrant
        if grant == nil or grant == "" then
            return
        end

        local described = THCRoll.DescribeGrant(creature, options, grant,
            check.info.assistName or "Assisted",
            check.info.assistDescription or "An ally assisted this test.",
            MTGConstants.modifierRollType)
        if described ~= nil then
            result[#result + 1] = described
        end
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
    local attrName = THCUtils.CharacteristicName(assignment.attrId)
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

    return THCRoll.Send{
        title = title,
        charid = assignment.charid,
        check = check,
    }
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
    THCRoll.Cancel(actionId)
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

    local status, rollInfo = THCRoll.Harvest(res.actionId, res.actionFor)

    --A player dismissing their roll takes the request, and the dialog, down.
    if status == "cancelled" then
        MTGResolver.Cancel(inst.id, res.actionId)
        return
    end

    if status == "waiting" then
        return
    end

    if status ~= "complete" then
        MTGRun.SetResolution(inst.id, nil)
        return
    end

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
