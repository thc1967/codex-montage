local mod = dmhub.GetModLoading()

--- Moves a row's rolls along. The rolls themselves are THCRollFlow's; what
--- stays here is the montage's reading of them -- the Assist's grant, the
--- Lead's outcome and the module's question -- and the Director's taking of
--- the Lead's roll.
MTGResolver = {}

THCRollFlow.RegisterCheck(MTGConstants.rollCheckId, MTGConstants.modifierRollType)

--- The modtype the Assist's roll earned the Lead, or nil when the Assist has
--- not rolled. Derived rather than stored, so undoing the roll takes it too.
--- @param run MTGRun
--- @param inst table
--- @return string|nil
function MTGResolver.AssistGrant(run, inst)
    local roll = MTGRun.RowRoll(inst, "assist")
    if roll == nil then
        return nil
    end
    return MTGRules.GetOrDefault(run.moduleId).AssistGrant(roll.tier or 1)
end

--- Why this row's next roll cannot go out now, or nil when it can.
--- @param run MTGRun
--- @param inst table
--- @return string|nil
function MTGResolver.RollBlocker(run, inst)
    if MTGRun.Seat(inst, "lead") == nil then
        return "Put a Hero in the Lead slot first"
    end
    --A roll with no characteristic has nothing to add; hold it until one is picked.
    if not MTGRun.HasCharacteristics(run, inst) then
        return "Pick a characteristic first"
    end
    local flow = MTGRun.Flow(run, inst)
    if not flow:CanRoll() then
        return "This row cannot roll now."
    end
    return flow:SendBlocker()
end

--- Send whichever roll this row needs next. Director only.
--- @param instanceId string
function MTGResolver.Roll(instanceId)
    local run = MTGRun.Active()
    local inst = run ~= nil and MTGRun.Instance(run, instanceId) or nil
    if not dmhub.isDM or inst == nil or MTGResolver.RollBlocker(run, inst) ~= nil then
        return
    end
    MTGRun.Flow(run, inst):RollNext()
end

--- Take back the roll out on this row. The step is offered again.
--- @param instanceId string
function MTGResolver.Cancel(instanceId)
    local run = MTGRun.Active()
    local inst = run ~= nil and MTGRun.Instance(run, instanceId) or nil
    if inst ~= nil then
        MTGRun.Flow(run, inst):Abandon()
    end
end

--- Read back any roll that has come in, on any row. Director only; run by
--- THCRollFlow's harvest whether or not the montage is open.
function MTGResolver.Pump()
    if not dmhub.isDM then
        return
    end

    --A legacy field left by an old client would refuse the roll's recording.
    MTGRun.MigrateRun()

    local run = MTGRun.Active()
    if run == nil then
        return
    end
    for _, inst in ipairs(run:try_get("instances", {})) do
        if MTGRun.Pending(inst) ~= nil then
            local ok, err = pcall(function()
                MTGRun.Flow(run, inst):Pump()
            end)
            if not ok then
                printf("MTG:: harvest failed: %s", tostring(err))
            end
        end
    end
end

THCRollFlow.RegisterHarvester("montage", function()
    MTGResolver.Pump()
end)

--- What the Lead's roll comes to: as decided, once decided, and read off the
--- roll by the row's rules before that.
--- @param run MTGRun
--- @param inst table
--- @return table|nil {id, label, tone}
function MTGResolver.Outcome(run, inst)
    if inst.outcome ~= nil then
        return inst.outcome
    end
    local roll = MTGRun.RowRoll(inst, "lead")
    local ch = MTGRun.ChallengeFor(run, inst)
    if roll == nil or ch == nil then
        return nil
    end
    return MTGRules.GetOrDefault(run.moduleId).RollToOutcome(run, ch, roll)
end

--- The question this row is waiting on, or nil when it is not waiting.
--- @param run MTGRun
--- @param inst table
--- @return table|nil
function MTGResolver.PendingPrompt(run, inst)
    if MTGRun.RowRoll(inst, "lead") == nil or inst.adjudicatedInRound ~= nil
        or MTGRun.Pending(inst) ~= nil then
        return nil
    end
    local ch = MTGRun.ChallengeFor(run, inst)
    if ch == nil then
        return nil
    end
    local rules = MTGRules.GetOrDefault(run.moduleId)
    return rules.PromptAfterRoll(run, ch, MTGResolver.Outcome(run, inst))
end

--- The Lead roll an answer is about, so a re-roll since makes it stale.
--- @param inst table
--- @return nil|{total: number, naturalRoll: number}
local function Stamp(inst)
    local roll = MTGRun.RowRoll(inst, "lead")
    if roll == nil then
        return nil
    end
    return { total = roll.total, naturalRoll = roll.naturalRoll }
end

--- The Director takes the Lead's roll and the row is decided by its rules.
--- A row whose module asks a question is decided by its answer instead.
--- @param instanceId string
function MTGResolver.AcceptRow(instanceId)
    local run = MTGRun.Active()
    local inst = run ~= nil and MTGRun.Instance(run, instanceId) or nil
    if not dmhub.isDM or inst == nil or inst.adjudicatedInRound ~= nil
        or MTGRun.Pending(inst) ~= nil or MTGResolver.PendingPrompt(run, inst) ~= nil then
        return
    end
    local outcome = MTGResolver.Outcome(run, inst)
    if outcome == nil then
        return
    end
    MTGRun.Adjudicate(instanceId, outcome, false, Stamp(inst))
end

--- Answer the module's question about the Lead's roll. Whoever rolled may,
--- and the Director: this is a plain change to the run, not a roll.
--- @param instanceId string
--- @param outcome table
--- @param stamp nil|{total: number, naturalRoll: number} the roll the question was asked of
function MTGResolver.Answer(instanceId, outcome, stamp)
    MTGRun.Adjudicate(instanceId, outcome, false, stamp)
end

--- The roll an answer is being given about, for the prompt's buttons.
--- @param inst table
--- @return nil|{total: number, naturalRoll: number}
function MTGResolver.Stamp(inst)
    return Stamp(inst)
end

--- The Lead's result as a line on the seat: the outcome by the row's rules.
--- Kept from the table while the difficulty is hidden and nothing is decided,
--- since the outcome would give the difficulty away.
--- @param run MTGRun
--- @param inst table
--- @param director boolean
--- @return string|nil markdown
function MTGResolver.LeadVerdict(run, inst, director)
    if MTGRun.RowRoll(inst, "lead") == nil then
        return nil
    end
    local ch = MTGRun.ChallengeFor(run, inst)
    if not director and inst.adjudicatedInRound == nil and ch ~= nil
        and MTGRun.IsDifficultyHidden(run, ch.id) then
        return nil
    end
    local outcome = MTGResolver.Outcome(run, inst)
    if outcome == nil or (outcome.label or "") == "" then
        return nil
    end
    return string.format("**%s**", outcome.label)
end

--- The Director's next step on each seat, beside its Re-roll: the Lead's turn
--- once the Assist is in, then taking the Lead's roll. None while a roll is
--- out, once the row is decided, or while the module waits on its question.
--- @param run MTGRun
--- @param inst table
--- @return {lead: table|nil, assist: table|nil}
function MTGResolver.Steps(run, inst)
    local steps = {}
    if inst.adjudicatedInRound ~= nil or MTGRun.Pending(inst) ~= nil then
        return steps
    end

    local instanceId = inst.id
    if MTGRun.RowRoll(inst, "lead") ~= nil then
        if MTGResolver.PendingPrompt(run, inst) == nil then
            steps.lead = {
                text = "Accept",
                enabled = true,
                tooltip = "Take this roll: the row is decided and can no longer re-roll.",
                run = function()
                    MTGResolver.AcceptRow(instanceId)
                end,
            }
        end
    elseif MTGRun.RowRoll(inst, "assist") ~= nil then
        local blocker = MTGResolver.RollBlocker(run, inst)
        steps.assist = {
            text = "Continue",
            enabled = blocker == nil,
            tooltip = blocker or "Ask the Lead to roll.",
            run = function()
                MTGResolver.Roll(instanceId)
            end,
        }
    end
    return steps
end
