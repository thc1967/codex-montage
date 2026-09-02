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

        --Skilled is offered rather than applied: the pipeline cannot know the
        --skill was chosen for this test, so proficiency is confirmed here.
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

        --The grant crosses the wire as a plain id and becomes a modifier here,
        --where the Lead's creature is in hand. Appending it raw would raise:
        --the dialog reads `.modifier` off each entry, so it goes through the
        --same wrapper sequence the engine uses.
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

    --Tiers ride on options, which is where the request dialog looks for them
    --too. Built only when they are actually there: the power table reads
    --#rollProperties.tiers, so handing it a table without them raises rather
    --than degrading -- which is what a request sent by an older client, or by
    --a rules module with no TierLabels, would otherwise do.
    ShowDialog = function(check, dialogOptions)
        --A montage roll is read, not admired: the tier table and the modifiers
        --have to be legible over whatever the map is showing. The frame's blur
        --is what makes it see-through, so opacity alone would not do it.
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

    --The roll dialog reads its power table off options.tiers -- NOT info, which
    --nothing looks at. Each module says what its own tiers mean, so Baseline
    --answers with the outcomes for this Challenge's difficulty and T&O with its
    --own three, and the player reads the real stakes before rolling.
    local rules = MTGRules.GetOrDefault(run.moduleId)

    local tiers = nil
    if role == "assist" then
        --An assist never resolves the Challenge. It hands the Lead a grant and
        --the tier picks which one, so the outcomes the module publishes are the
        --wrong text entirely here. Read straight off AssistGrant, which is what
        --the resolution then calls, and shared by every module through it.
        --Three rows only: a critical buys nothing past the top tier.
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

    --The Director gets the game's own roll summary over the board, which is
    --what brings Re-roll and Take Roll to a montage test. Its Proceed is what
    --accepts the roll, so the resultTable is kept rather than discarded: Pump
    --waits on it instead of on the roll completing.
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

    --One roll out at a time. Pump only ever services ResolvingInstance, which
    --is the FIRST row holding a resolution, so a second request already sat
    --unharvested until the first cleared; and the summary dialog is one shared
    --panel, so a second would displace the first's and report itself
    --cancelled, losing that roll. The card greys the other dice to match.
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

    --Players key their curtain off inst.resolution, so it has to land before
    --the request goes out or the roll dialog beats it to the screen.
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

    --A fresh table, never the one the first write handed to the document:
    --assigning that one back over itself does not carry the new field.
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
    --Dropped before the request goes, so the dialog's dying `result = false`
    --is never read back against a request that no longer exists.
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

    --Set but not yet stamped: in flight, not lost. The nil lookup below would
    --otherwise read as "cleared out from under us" and wipe it.
    if res.actionId == nil then
        return
    end

    --Held before the request is read. Proceed cancels the request on its way
    --out, so by the time this pump next runs the request is ALREADY GONE - and
    --a missing request must not be read as an abandoned roll while an answer
    --is waiting. That ordering is the whole reason this sits up here.
    local answer = nil
    if g_pending ~= nil and g_pending.actionId == res.actionId then
        answer = g_pending.resultTable
    end

    local req = dmhub.GetPlayerActionRequest(res.actionId)
    local info = req ~= nil and req.info.tokens[res.actionFor] or nil
    local status = info ~= nil and info.status or nil

    --A player who dismissed their own roll takes the request down with them,
    --which closes the summary dialog too.
    if status == "cancel" then
        MTGResolver.Cancel(inst.id, res.actionId)
        return
    end

    --Where the numbers come from, and whether it is time to take them. With a
    --summary dialog up, the Director's Proceed is what accepts the roll: a
    --completed roll sits there unrecorded so Re-roll and Take Roll still have
    --a live request to act on, and so a roll about to be thrown away has not
    --already moved the Run.
    local tokenInfo = nil

    if answer ~= nil then
        --Still on the Director's desk.
        if answer.result == nil then
            return
        end

        g_pending = nil

        --Cancelled while incomplete, or the dialog was dismissed. It dropped
        --the request on its way out, so there is nothing left to cancel.
        if answer.result ~= true or answer.action == nil then
            MTGRun.SetResolution(inst.id, nil)
            return
        end

        --Snapshotted before the dialog cancelled the request, which is what
        --makes this safe to read now.
        tokenInfo = answer.action.info.tokens[res.actionFor]
    else
        --No dialog: a reload took it, or there was no hud to show one. Harvest
        --on completion, as this pump always did, and treat a request cleared
        --out from under us as never having been asked.
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

    --Tier comes from the numbers the request carries, not from the total
    --alone: two edges bump the tier without moving it.
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

    --A module may refuse to call it, in which case the row waits on a human
    --rather than resolving.
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
