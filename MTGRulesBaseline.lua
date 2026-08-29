local mod = dmhub.GetModLoading()

--- Which outcome each tier lands on, by the Challenge's difficulty. Read by
--- both the roll resolution and the tier text shown in the roll dialog, so the
--- two can never drift apart and tell the player different things.
local g_tiersByDifficulty = {
    easy = { "success_consequence", "success", "success_reward" },
    medium = { "failure", "success_consequence", "success" },
    hard = { "failure_consequence", "failure", "success" },
}

--- The difficulty a Challenge is being run at.
--- @param run MTGRun
--- @param ch MTGChallengeDef
--- @return string difficulty
local function DifficultyOf(run, ch)
    return ch:FieldValue(run.moduleId, {
        id = "difficulty",
        default = "medium",
    })
end

--- Draw Steel montage tests as written. The root module: every other module
--- inherits from this one and overrides only what it changes.
MTGRules.Register{
    id = MTGConstants.moduleBaseline,
    name = "Draw Steel",
    description = "Draw Steel montage tests as written. Successes and failures race toward their limits.",

    --- Board order. Round first, then whatever the module cares about.
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
            return string.lower(a.name or "") < string.lower(b.name or "")
        end)
        return sorted
    end,

    --- What the board shows about a Challenge at a glance.
    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @param run MTGRun
    --- @param inst table
    --- @param ch MTGChallengeDef
    --- @return {icon: string, tooltip: string}
    ChallengeStatus = function(run, inst, ch)
        if inst.adjudicatedInRound == nil then
            return { icon = MTGConstants.iconPending, tooltip = "Not yet attempted" }
        end
        local outcome = inst.outcome or {}
        local failed = outcome.tone == "danger"
        return {
            icon = cond(failed, MTGConstants.iconFailure, MTGConstants.iconSuccess),
            tone = cond(failed, "danger", "success"),
            tooltip = outcome.label or "Resolved",
        }
    end,

    --- What the assist's own tier hands the Lead.
    --- @param assistTier number
    --- @return string a modtype id
    AssistGrant = function(assistTier)
        if assistTier >= 3 then
            return "double_edge"
        end
        if assistTier >= 2 then
            return "edge"
        end
        return "bane"
    end,

    --- Outcome ids, so progress and history never parse prose.
    OutcomeLabels = {
        success_consequence = "Success with a consequence",
        success = "Success",
        success_reward = "Success with a reward",
        failure = "Failure",
        failure_consequence = "Failure with a consequence",
    },

    --- Tier against difficulty. A natural 19 or 20 is a reward whatever the
    --- difficulty was.
    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @param roll table
    --- @return table {id, label}
    RollToOutcome = function(run, ch, roll)
        local rules = MTGRules.GetOrDefault(run.moduleId)

        local id
        if (roll.naturalRoll or 0) >= 19 then
            id = "success_reward"
        else
            local column = g_tiersByDifficulty[DifficultyOf(run, ch)]
                or g_tiersByDifficulty.medium
            id = column[math.max(1, math.min(3, roll.tier or 1))]
        end

        return {
            id = id,
            label = rules.OutcomeLabels[id] or id,
            tone = cond(string.sub(id, 1, 7) == "failure", "danger", "success"),
        }
    end,

    --- What each tier of the roll means, for the roll dialog's power table.
    --- Read from the same map the resolution uses, so what the player is told
    --- before rolling is what the roll then does. The fourth row is the
    --- critical, which outranks difficulty entirely.
    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @return string[] labels tier 1-3, then the critical
    TierLabels = function(run, ch)
        local rules = MTGRules.GetOrDefault(run.moduleId)
        local column = g_tiersByDifficulty[DifficultyOf(run, ch)]
            or g_tiersByDifficulty.medium

        local labels = {}
        for i = 1, 3 do
            labels[i] = rules.OutcomeLabels[column[i]] or column[i]
        end
        labels[4] = rules.OutcomeLabels.success_reward

        return labels
    end,

    --- What the Director hands out when they grant a success without a roll.
    --- @return table {id, label, tone}
    GrantedOutcome = function()
        return { id = "success", label = "Success", tone = "success" }
    end,

    --- Every Baseline roll decides itself.
    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @param outcome table
    --- @return table|nil
    PromptAfterRoll = function(run, ch, outcome)
        return nil
    end,

    --- Move the meters for an outcome that just landed.
    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @param inst table
    --- @param sign number 1 to apply, -1 to take it back
    ApplyProgress = function(run, ch, inst, sign)
        local outcome = inst.outcome or {}
        local progress = run:get_or_add("progress", { successes = 0, failures = 0 })
        local key = cond(outcome.tone == "danger", "failures", "successes")
        progress[key] = math.max(0, (progress[key] or 0) + sign)
    end,

    --- Where the row goes once its outcome is in.
    --- @param run MTGRun
    --- @param ch MTGChallengeDef
    --- @param inst table
    --- @return string a state id
    PostResolutionState = function(run, ch, inst)
        if MTGRun.AttemptsLeft(run, ch) > 0 then
            return MTGConstants.stateOpen
        end
        return MTGConstants.stateClosed
    end,

    --- Whether the montage has reached a natural stopping point. Advisory:
    --- the Director may end it whenever they like.
    --- @param run MTGRun
    --- @return boolean, string
    CanEnd = function(run)
        local progress = run:try_get("progress", {})
        local successes = progress.successes or 0
        local failures = progress.failures or 0

        if successes >= MTGRun.Setting(run, "successLimit", 6) then
            return true, "The successes are in."
        end
        if failures >= MTGRun.Setting(run, "failureLimit", 3) then
            return true, "The failures have piled up."
        end
        if (run.round or 1) > MTGRun.Setting(run, "roundLimit", 2) then
            return true, "The rounds are spent."
        end
        return false, "Still in play."
    end,

    --- The final report. Victories are the Director's to enter: Baseline has
    --- no easy/moderate/hard label for the rulebook's award table to key off.
    --- @param run MTGRun
    --- @return table
    BuildEnding = function(run)
        local progress = run:try_get("progress", {})
        local successes = progress.successes or 0
        local failures = progress.failures or 0
        local successLimit = MTGRun.Setting(run, "successLimit", 6)

        local degreeId = "total_failure"
        if successes >= successLimit then
            degreeId = "total_success"
        elseif successes >= failures + 2 then
            degreeId = "partial_success"
        end

        local options = {
            { id = "total_success", label = "Total success" },
            { id = "partial_success", label = "Partial success" },
            { id = "total_failure", label = "Total failure" },
        }

        local degree = options[3]
        for _, option in ipairs(options) do
            if option.id == degreeId then
                degree = option
            end
        end

        return {
            sections = {
                {
                    title = "Tally",
                    entries = {
                        string.format("Successes: %d of %d", successes, successLimit),
                        string.format("Failures: %d of %d", failures,
                            MTGRun.Setting(run, "failureLimit", 3)),
                        string.format("Rounds played: %d", run.round or 1),
                    },
                },
            },
            degree = degree,
            degreeOptions = options,
            victories = 0,
            victoriesComputed = false,
        }
    end,

    --- @return table starting progress state
    InitProgress = function()
        return { successes = 0, failures = 0 }
    end,

    --- @param run MTGRun
    --- @return table[] meter descriptors
    DescribeProgress = function(run)
        local progress = run:try_get("progress", {})
        return {
            {
                id = "successes",
                label = "Successes",
                labelOne = "Success",
                value = progress.successes or 0,
                max = MTGRun.Setting(run, "successLimit", 6),
                adjustable = true,
                tone = "success",
            },
            {
                id = "failures",
                label = "Failures",
                labelOne = "Failure",
                value = progress.failures or 0,
                max = MTGRun.Setting(run, "failureLimit", 3),
                adjustable = true,
                tone = "danger",
            },
        }
    end,

    --- Whether an authored Challenge has everything it needs to run. The
    --- module's own fields come from ChallengeFields(), so declaring a new one
    --- gets it checked here without an override.
    --- @param ch MTGChallengeDef
    --- @param moduleId string
    --- @return boolean
    IsChallengeComplete = function(ch, moduleId)
        if string.trim(ch.name or "") == "" then
            return false
        end
        if (tonumber(ch.availableFromRound) or 0) < 1 then
            return false
        end
        if string.trim(ch.description or "") == "" then
            return false
        end
        if #ch:try_get("allowedCharacteristics", {}) < 1 then
            return false
        end
        if #ch:try_get("allowedSkills", {}) < 1 then
            return false
        end

        for _, field in ipairs(MTGRules.GetOrDefault(moduleId).ChallengeFields()) do
            local value = ch:FieldValue(moduleId, field)
            if value == nil or string.trim(tostring(value)) == "" then
                return false
            end
        end

        return true
    end,

    --- Fields this module adds to every Challenge.
    --- @return table[]
    ChallengeFields = function()
        return {
            {
                id = "difficulty",
                text = "Difficulty",
                type = "choice",
                default = "medium",
                --The Director may retune this mid-Run, on any test that has not
                --been adjudicated. A module opts a field in deliberately: most
                --describe what a Challenge IS and have no business moving once
                --the montage is on the table.
                liveEditable = true,
                options = {
                    { id = "easy", text = "Easy" },
                    { id = "medium", text = "Medium" },
                    { id = "hard", text = "Hard" },
                },
            },
        }
    end,

    --- @return {id: string, text: string, default: number, min: number}[]
    SettingsFields = function()
        return {
            {
                id = "successLimit",
                text = "Success Limit",
                default = 6,
                min = 1,
            },
            {
                id = "failureLimit",
                text = "Failure Limit",
                default = 3,
                min = 1,
            },
            {
                id = "roundLimit",
                text = "Round Limit",
                default = 2,
                min = 1,
            },
        }
    end,
}
