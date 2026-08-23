local mod = dmhub.GetModLoading()

--- Threats & Opportunities. The heroes always reach the goal; the montage
--- decides at what cost. Nothing accumulates toward a win condition, so the
--- success and failure limits do not exist here.
MTGRules.Register{
    id = MTGConstants.moduleTO,
    name = "Threats & Opportunities",
    inherits = MTGConstants.moduleBaseline,
    description = "Homebrew. Threats left standing cost the party; Opportunities seized reward them.",

    --- Threats before Opportunities within a round, then by name.
    --- @param run MTGRun
    --- @param challenges MTGChallengeDef[]
    --- @return MTGChallengeDef[]
    SortChallenges = function(run, challenges)
        local sorted = {}
        for _, ch in ipairs(challenges) do
            sorted[#sorted + 1] = ch
        end
        table.sort(sorted, function(a, b)
            local ra, rb = a.availableFromRound or 1, b.availableFromRound or 1
            if ra ~= rb then
                return ra < rb
            end
            local ta = a:FieldsFor(MTGConstants.moduleTO).type or "threat"
            local tb = b:FieldsFor(MTGConstants.moduleTO).type or "threat"
            if ta ~= tb then
                return ta < tb
            end
            return string.lower(a.name or "") < string.lower(b.name or "")
        end)
        return sorted
    end,

    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @param run MTGRun
    --- @param inst table
    --- @param ch MTGChallengeDef
    --- @return {icon: string, tooltip: string}
    ChallengeStatus = function(run, inst, ch)
        local isThreat = ch:FieldsFor(MTGConstants.moduleTO).type ~= "opportunity"

        if MTGRun.ChallengeModuleState(run, ch.id).resolved == true then
            return {
                icon = MTGConstants.iconSuccess,
                tone = "success",
                tooltip = cond(isThreat, "Averted", "Seized"),
            }
        end

        return {
            icon = MTGConstants.iconPending,
            tooltip = cond(isThreat, "Still standing", "Not yet secured"),
        }
    end,

    --- Progress is derived from the challenges, never counted.
    --- @return table
    OutcomeLabels = {
        success = "Success",
        success_cost = "Success with a cost",
        failure = "Failure",
        undecided = "Undecided",
    },

    --- No difficulty here: the tier alone decides, and the middle tier is the
    --- table's to settle rather than the app's.
    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @param roll table
    --- @return table {id, label}
    RollToOutcome = function(run, ch, roll)
        local rules = MTGRules.GetOrDefault(run.moduleId)

        local id = "undecided"
        if (roll.naturalRoll or 0) >= 19 or (roll.tier or 1) >= 3 then
            id = "success"
        elseif (roll.tier or 1) <= 1 then
            id = "failure"
        end

        return {
            id = id,
            label = rules.OutcomeLabels[id] or id,
            tone = cond(id == "failure", "danger", cond(id == "undecided", "warning", "success")),
        }
    end,

    --- The middle band is nobody's call but the table's, so the roll stops
    --- here and the person who made it says which way it went.
    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @param outcome table
    --- @return table|nil a prompt descriptor, or nil when the roll decided
    PromptAfterRoll = function(run, ch, outcome)
        if outcome.id ~= "undecided" then
            return nil
        end
        return {
            id = "to_undecided",
            text = "Agree a cost out loud, then say which way this went.",
            options = {
                {
                    id = "failure",
                    label = "Failure",
                    outcome = { id = "failure", label = "Failure", tone = "danger" },
                },
                {
                    id = "success_cost",
                    label = "Success with a cost",
                    outcome = { id = "success_cost", label = "Success with a cost", tone = "success" },
                },
            },
        }
    end,

    --- Progress here is a flag on the Challenge, not a tally.
    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @param inst table
    --- @param sign number 1 to apply, -1 to take it back
    ApplyProgress = function(run, ch, inst, sign)
        local outcome = inst.outcome or {}
        if outcome.tone ~= "success" then
            return
        end
        MTGRun.ChallengeModuleState(run, ch.id).resolved = sign > 0
    end,

    --- A Threat left standing comes straight back, in the same round.
    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @param inst table
    --- @return string a state id
    PostResolutionState = function(run, ch, inst)
        local outcome = inst.outcome or {}
        if outcome.tone ~= "success" or ch.repeatable == true then
            return MTGConstants.stateOpen
        end
        return MTGConstants.stateClosed
    end,

    --- @param run MTGRun
    --- @return boolean, string
    CanEnd = function(run)
        if (run.round or 1) > MTGRun.Setting(run, "roundLimit", 2) then
            return true, "The rounds are spent."
        end
        return false, "Still in play."
    end,

    --- Victories here are a property of the montage's design, not of how the
    --- party did: a party that averts everything earns what one that averts
    --- nothing earns.
    --- @param run MTGRun
    --- @return table
    BuildEnding = function(run)
        local standing, averted, seized = {}, {}, {}
        local threats = 0

        for _, ch in ipairs(MTGRun.ActiveChallenges(run)) do
            local fields = ch:FieldsFor(MTGConstants.moduleTO)
            local resolved = MTGRun.ChallengeModuleState(run, ch.id).resolved == true
            local text = fields.outcome
            if text == nil or text == "" then
                text = ch.name or ""
            else
                text = string.format("%s — %s", ch.name or "", text)
            end

            if fields.type == "opportunity" then
                if resolved then
                    seized[#seized + 1] = text
                end
            else
                threats = threats + 1
                if resolved then
                    averted[#averted + 1] = ch.name or ""
                else
                    standing[#standing + 1] = text
                end
            end
        end

        local heroes = 0
        for _, p in ipairs(MTGRun.ActiveParticipants(run)) do
            if p.isHero == true then
                heroes = heroes + 1
            end
        end

        local victories = 0
        if threats > 0 then
            victories = cond(threats < heroes, 1, 2)
        end

        local sections = {}
        if #standing > 0 then
            sections[#sections + 1] = { title = "What's Coming", entries = standing }
        end
        if #seized > 0 then
            sections[#sections + 1] = { title = "Opportunities Seized", entries = seized }
        end
        if #averted > 0 then
            sections[#sections + 1] = { title = "Threats Averted", entries = averted }
        end

        return {
            sections = sections,
            degree = nil,
            degreeOptions = nil,
            victories = victories,
            victoriesComputed = true,
        }
    end,

    InitProgress = function()
        return {}
    end,

    --- @param run MTGRun
    --- @return table[] meter descriptors
    DescribeProgress = function(run)
        local threats, averted, opportunities, seized = 0, 0, 0, 0

        for _, ch in ipairs(MTGRun.ActiveChallenges(run)) do
            local fields = ch:FieldsFor(MTGConstants.moduleTO)
            local resolved = MTGRun.ChallengeModuleState(run, ch.id).resolved == true
            if fields.type == "opportunity" then
                opportunities = opportunities + 1
                if resolved then seized = seized + 1 end
            else
                threats = threats + 1
                if resolved then averted = averted + 1 end
            end
        end

        return {
            {
                id = "threats",
                label = "Threats Averted",
                value = averted,
                max = threats,
                adjustable = false,
                tone = "success",
                detail = string.format("%d of %d averted, %d still standing",
                    averted, threats, threats - averted),
            },
            {
                id = "opportunities",
                label = "Opportunities Seized",
                value = seized,
                max = opportunities,
                adjustable = false,
                tone = "success",
            },
        }
    end,

    --- @return table[]
    ChallengeFields = function()
        return {
            {
                id = "type",
                text = "Type",
                type = "choice",
                default = "threat",
                options = {
                    { id = "threat", text = "Threat" },
                    { id = "opportunity", text = "Opportunity" },
                },
            },
            {
                id = "outcome",
                text = "Outcome",
                type = "text",
                default = "",
            },
        }
    end,

    --- @return {id: string, text: string, default: number, min: number}[]
    SettingsFields = function()
        return {
            {
                id = "roundLimit",
                text = "Round Limit",
                default = 2,
                min = 1,
            },
        }
    end,
}
