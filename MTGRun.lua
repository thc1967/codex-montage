local mod = dmhub.GetModLoading()

--- A character taking part in a Run.
--- @class MTGParticipant
--- @field charid string
--- @field name string
--- @field isHero boolean
--- @field included boolean
MTGParticipant = RegisterGameType("MTGParticipant")

MTGParticipant.name = ""
MTGParticipant.isHero = false
MTGParticipant.included = true

--- @param args nil|table
--- @return MTGParticipant
function MTGParticipant.CreateNew(args)
    return MTGParticipant.new(args or {})
end

--- One live instance of a Montage Definition. A full copy: editing a Run never
--- reaches the Definition it came from.
--- @class MTGRun
--- @field id string
--- @field sourceId string
--- @field name string
--- @field moduleId string
--- @field settings table
--- @field participants MTGParticipant[]
--- @field challenges MTGChallengeDef[]
--- @field round number
--- @field status string
--- @field paused boolean
MTGRun = RegisterGameType("MTGRun")

MTGRun.name = ""
MTGRun.round = 1
MTGRun.status = MTGConstants.statusSetup
MTGRun.paused = false

--- @param args nil|table
--- @return MTGRun
function MTGRun.CreateNew(args)
    args = args or {}
    args.id = args.id or dmhub.GenerateGuid()
    args.settings = args.settings or {}
    args.participants = args.participants or {}
    args.challenges = args.challenges or {}
    args.excludedChallenges = args.excludedChallenges or {}
    args.instances = args.instances or {}
    args.challengeModuleState = args.challengeModuleState or {}
    args.progress = args.progress or {}
    return MTGRun.new(args)
end

mod:RegisterDocumentForCheckpointBackups(MTGConstants.activeRunDoc)

--- @return LuaCodeModDocumentSnapshot
function MTGRun.Doc()
    return mod:GetDocumentSnapshot(MTGConstants.activeRunDoc)
end

--- @return string monitorGame path for the active Run
function MTGRun.DocPath()
    return mod:GetDocumentPath(MTGConstants.activeRunDoc)
end

--- The Run in progress, or nil.
--- @return MTGRun|nil
function MTGRun.Active()
    local doc = MTGRun.Doc()
    if doc == nil or doc.data == nil then
        return nil
    end
    return doc.data.run
end

--- Mutate the active Run inside one document change.
--- @param description string
--- @param fn fun(run: MTGRun)
function MTGRun.Mutate(description, fn)
    local doc = MTGRun.Doc()
    local run = doc.data ~= nil and doc.data.run or nil
    if run == nil then
        return
    end
    doc:BeginChange()
    fn(run)
    doc:CompleteChange(description)
end

--- Characters eligible to be seeded into a Run: the default player party, plus
--- anyone handed to a specific player. Narrower than the combat launcher, which
--- also sweeps in the ally parties, and wider than the map, which only holds
--- whoever happens to be placed right now.
--- @return MTGParticipant[]
function MTGRun.EligibleParticipants()
    local result = {}
    local seen = {}
    local partyId = GetDefaultPartyID()

    local placed = {}
    for _, token in ipairs(dmhub.allTokens) do
        if token ~= nil and token.valid then
            placed[token.charid] = true
        end
    end

    --- @param charid string
    --- @param inDefaultParty boolean
    local function Consider(charid, inDefaultParty)
        if charid == nil or seen[charid] then
            return
        end

        local token = dmhub.GetCharacterById(charid)
        if token == nil or token.properties == nil then
            return
        end

        --playerControlled is also true for party-shared tokens, so it is too
        --wide here; NotShared is the one that means a named owner.
        if not inDefaultParty and token.playerControlledNotShared ~= true then
            return
        end

        seen[charid] = true

        local isHero = false
        pcall(function()
            isHero = token.properties:IsHero()
        end)

        result[#result + 1] = MTGParticipant.CreateNew{
            charid = charid,
            name = token.name or "",
            isHero = isHero,
            --Off the map means not in the scene, so it is offered but not
            --ticked. The Director opts them in.
            included = placed[charid] == true,
        }
    end

    --Named explicitly rather than through unhidden_pairs below, so a hidden
    --player party still seeds.
    for _, charid in ipairs(dmhub.GetCharacterIdsInParty(partyId) or {}) do
        Consider(charid, true)
    end

    for pid, _ in unhidden_pairs(dmhub.GetTable(Party.tableName) or {}) do
        for _, charid in ipairs(dmhub.GetCharacterIdsInParty(pid) or {}) do
            Consider(charid, pid == partyId)
        end
    end

    --Catches anyone assigned to a player but belonging to no party at all.
    for _, token in ipairs(dmhub.allTokens) do
        if token ~= nil and token.valid then
            Consider(token.charid, token.partyId == partyId)
        end
    end

    table.sort(result, function(a, b)
        if a.isHero ~= b.isHero then
            return a.isHero
        end
        return string.lower(a.name) < string.lower(b.name)
    end)

    return result
end

--- Create a Run from a Definition and put it in Setup.
--- @param defid string
--- @return string|nil id of the new Run
function MTGRun.BeginSetup(defid)
    local def = MTGDefinition.GetByID(defid)
    if def == nil then
        return nil
    end

    local run = MTGRun.CreateNew{
        sourceId = defid,
        name = def.name or "Montage",
        description = def:try_get("description", ""),
        moduleId = def.moduleId,
        settings = DeepCopy(def:SettingsFor(def.moduleId)),
        challenges = DeepCopy(def:try_get("challenges", {})),
        participants = MTGRun.EligibleParticipants(),
        status = MTGConstants.statusSetup,
    }

    local doc = MTGRun.Doc()
    doc:BeginChange()
    doc.data.run = run
    doc:CompleteChange("Start montage setup")

    return run.id
end

--- Throw the Run away. The Definition it came from is untouched.
function MTGRun.Discard()
    local doc = MTGRun.Doc()
    doc:BeginChange()
    doc.data.run = nil
    doc:CompleteChange("Discard montage")
end

--- @param charid string
--- @param included boolean
function MTGRun.SetParticipantIncluded(charid, included)
    local run = MTGRun.Active()
    if run == nil then
        return
    end

    local participant = MTGRun.Participant(run, charid)
    if participant == nil or participant.included == included then
        return
    end

    MTGRun.Mutate("Change montage roster", function(r)
        local p = MTGRun.Participant(r, charid)
        if p ~= nil then
            p.included = included
        end
    end)
end

--- @param run MTGRun
--- @param chid string
--- @return boolean
function MTGRun.IsChallengeIncluded(run, chid)
    return run:try_get("excludedChallenges", {})[chid] ~= true
end

--- Whether the table is being kept from seeing this Challenge. Seeded from the
--- authored Definition when the Run copies it, then the Director's to change
--- for the rest of the Run. Absent reads visible, so a montage authored before
--- hiding existed needs nothing done to it.
--- @param run MTGRun
--- @param chid string
--- @return boolean
function MTGRun.IsChallengeHidden(run, chid)
    for _, ch in ipairs(run:try_get("challenges", {})) do
        if ch.id == chid then
            return ch:try_get("hidden", false) == true
        end
    end
    return false
end

--- Writes to the Run's own copy of the Challenge, so revealing something mid
--- montage never edits the saved montage it came from.
--- @param chid string
--- @param hidden boolean
function MTGRun.SetChallengeHidden(chid, hidden)
    local run = MTGRun.Active()
    if run == nil or MTGRun.IsChallengeHidden(run, chid) == (hidden == true) then
        return
    end

    MTGRun.Mutate(cond(hidden, "Hide challenge", "Reveal challenge"), function(r)
        for _, ch in ipairs(r:try_get("challenges", {})) do
            if ch.id == chid then
                ch.hidden = hidden == true
                return
            end
        end
    end)
end

--- @param run MTGRun
--- @param chid string
--- @return boolean
function MTGRun.IsDifficultyHidden(run, chid)
    for _, ch in ipairs(run:try_get("challenges", {})) do
        if ch.id == chid then
            return ch:try_get("difficultyHidden", false) == true
        end
    end
    return false
end

--- @param chid string
--- @param hidden boolean
function MTGRun.SetDifficultyHidden(chid, hidden)
    local run = MTGRun.Active()
    if run == nil or MTGRun.IsDifficultyHidden(run, chid) == (hidden == true) then
        return
    end

    MTGRun.Mutate(cond(hidden, "Hide difficulty", "Reveal difficulty"), function(r)
        for _, ch in ipairs(r:try_get("challenges", {})) do
            if ch.id == chid then
                ch.difficultyHidden = hidden == true
                return
            end
        end
    end)
end

--- @param chid string
--- @param included boolean
function MTGRun.SetChallengeIncluded(chid, included)
    local run = MTGRun.Active()
    if run == nil or MTGRun.IsChallengeIncluded(run, chid) == (included == true) then
        return
    end

    MTGRun.Mutate("Change montage challenges", function(r)
        if r:try_get("excludedChallenges") == nil then
            r.excludedChallenges = {}
        end
        r.excludedChallenges[chid] = cond(included, nil, true)
    end)
end

--- @param fieldId string
--- @param value number
function MTGRun.SetSetting(fieldId, value)
    local run = MTGRun.Active()
    if run == nil or run:try_get("settings", {})[fieldId] == value then
        return
    end

    MTGRun.Mutate("Change montage setting", function(r)
        r.settings[fieldId] = value
    end)
end

--- A run setting, falling back to the field's declared default.
--- @param run MTGRun
--- @param field table a SettingsFields() entry
--- @return number
function MTGRun.SettingValue(run, field)
    local value = run:try_get("settings", {})[field.id]
    if value == nil then
        return field.default
    end
    return value
end

--- The active Run, but only when it came from this Definition.
--- @param defid string
--- @return MTGRun|nil
function MTGRun.ActiveFor(defid)
    local run = MTGRun.Active()
    if run ~= nil and run.sourceId == defid then
        return run
    end
    return nil
end

--- Participants actually taking part. Excluded ones stay on the Run so Setup
--- can be revisited and Reset can rebuild from the same choices.
--- @param run MTGRun
--- @return MTGParticipant[]
function MTGRun.ActiveParticipants(run)
    local result = {}
    for _, p in ipairs(run:try_get("participants", {})) do
        if p.included ~= false then
            result[#result + 1] = p
        end
    end
    return result
end

--- Challenges actually in play.
--- @param run MTGRun
--- @return MTGChallengeDef[]
function MTGRun.ActiveChallenges(run)
    local result = {}
    for _, ch in ipairs(run:try_get("challenges", {})) do
        if MTGRun.IsChallengeIncluded(run, ch.id) then
            result[#result + 1] = ch
        end
    end
    return result
end



--- Leave Setup and start play.
function MTGRun.Start()
    MTGRun.Mutate("Start montage", function(run)
        run.status = MTGConstants.statusRunning
        run.paused = false
        run.round = 1
        run.progress = MTGRules.GetOrDefault(run.moduleId).InitProgress(run)
        run.challengeModuleState = {}
        run.instances = {}
        MTGRun.SeedRound(run, 1)
    end)
end

--- @param paused boolean
function MTGRun.SetPaused(paused)
    local run = MTGRun.Active()
    if run == nil or (run:try_get("paused", false) == true) == (paused == true) then
        return
    end

    MTGRun.Mutate(cond(paused, "Pause montage", "Resume montage"), function(r)
        r.paused = paused
    end)
end

--- Put play back to the beginning. The roster, the excluded challenges and the
--- limits are Setup choices and survive; only what happened in play is cleared.
function MTGRun.Reset()
    MTGRun.Mutate("Reset montage", function(run)
        run.round = 1
        run.paused = false
        run.status = MTGConstants.statusSetup
        run.progress = MTGRules.GetOrDefault(run.moduleId).InitProgress(run)
        run.challengeModuleState = {}
        run.ending = nil

        --The rows ARE the record of play: every roll, outcome and staged
        --Participant lives on them, so clearing them clears all of it. Start
        --seeds a fresh set.
        run.instances = {}

        for _, p in ipairs(run:try_get("participants", {})) do
            p.skillsUsed = {}
        end
    end)
end

--- A run setting by id, falling back to a caller-supplied default.
--- @param run MTGRun
--- @param id string
--- @param default number
--- @return number
function MTGRun.Setting(run, id, default)
    local value = run:try_get("settings", {})[id]
    if value == nil then
        return default
    end
    return value
end

--- The rules module's per-challenge state, created on first access.
--- @param run MTGRun
--- @param chid string
--- @return table
function MTGRun.ChallengeModuleState(run, chid)
    local all = run:try_get("challengeModuleState")
    if all == nil then
        run.challengeModuleState = {}
        all = run.challengeModuleState
    end
    if all[chid] == nil then
        all[chid] = {}
    end
    return all[chid]
end

--- @return table[] meter descriptors for the active Run
function MTGRun.Meters()
    local run = MTGRun.Active()
    if run == nil then
        return {}
    end
    return MTGRules.GetOrDefault(run.moduleId).DescribeProgress(run)
end

--- Move one progress meter by hand.
--- Moves the same counter adjudication moves rather than keeping a parallel
--- manual tally: CanEnd and the ending both read that counter straight, so a
--- second number would have to be added back in at every one of those sites to
--- mean anything, and could disagree with this one.
---
--- The module's descriptor is the authority on whether a meter may be moved and
--- how far, so it is re-read here rather than trusted from the click: a meter
--- whose value is derived has nothing to write to.
--- @param meterId string
--- @param delta number
function MTGRun.AdjustProgress(meterId, delta)
    MTGRun.Mutate("Adjust montage progress", function(run)
        local meter = nil
        for _, m in ipairs(MTGRules.GetOrDefault(run.moduleId).DescribeProgress(run)) do
            if m.id == meterId then
                meter = m
                break
            end
        end

        if meter == nil or meter.adjustable ~= true then
            return
        end

        local progress = run:get_or_add("progress", {})
        local value = progress[meterId] or 0
        progress[meterId] = math.max(0, math.min(meter.max or 0, value + delta))
    end)
end

--- One attempt-in-progress on a Challenge. Rows never migrate between rounds;
--- `adjudicatedInRound` is what decides where a row is shown.
--- @param challengeId string
--- @param round number
--- @return table
local function NewInstance(challengeId, round)
    return {
        id = dmhub.GenerateGuid(),
        challengeId = challengeId,
        createdInRound = round,
        adjudicatedInRound = nil,
    }
end

--- Add a row for every included Challenge that becomes available this round.
--- @param run MTGRun
--- @param round number
function MTGRun.SeedRound(run, round)
    if run:try_get("instances") == nil then
        run.instances = {}
    end
    for _, ch in ipairs(MTGRun.ActiveChallenges(run)) do
        if (ch.availableFromRound or 1) == round then
            run.instances[#run.instances + 1] = NewInstance(ch.id, round)
        end
    end
end

--- Put a Challenge authored mid-run onto the board, and keep it: presenting it
--- to the table is what earns it a place in the saved montage as well.
--- @param ch MTGChallengeDef
function MTGRun.AddChallengeAtRuntime(ch)
    local defid = nil

    MTGRun.Mutate("Add challenge", function(run)
        defid = run.sourceId
        if run:try_get("challenges") == nil then
            run.challenges = {}
        end
        run.challenges[#run.challenges + 1] = ch

        --SeedRound fires only on exact round equality and has already run for
        --the round in play, so a row for this one has to be made here. A
        --future round is left to SeedRound.
        local round = run.round or 1
        if (ch.availableFromRound or 1) == round then
            if run:try_get("instances") == nil then
                run.instances = {}
            end
            run.instances[#run.instances + 1] = NewInstance(ch.id, round)
        end
    end)

    --A copy, so the run and the montage are not sharing one table across two
    --documents. The montage may since have been deleted; AppendChallenge
    --shrugs that off.
    if defid ~= nil then
        MTGDefinition.AppendChallenge(defid, DeepCopy(ch))
    end
end

--- @param run MTGRun
--- @param instanceId string
--- @return table|nil
function MTGRun.Instance(run, instanceId)
    for _, inst in ipairs(run:try_get("instances", {})) do
        if inst.id == instanceId then
            return inst
        end
    end
    return nil
end

--- @param run MTGRun
--- @param inst table
--- @return MTGChallengeDef|nil
function MTGRun.ChallengeFor(run, inst)
    for _, ch in ipairs(run:try_get("challenges", {})) do
        if ch.id == inst.challengeId then
            return ch
        end
    end
    return nil
end

--- Rows shown under a round. A past round shows what it adjudicated; the
--- current round also carries every row still open, however old.
--- @param run MTGRun
--- @param round number
--- @return table[]
function MTGRun.InstancesForRound(run, round)
    local current = run.round or 1
    local result = {}
    for _, inst in ipairs(run:try_get("instances", {})) do
        local adjudicated = inst.adjudicatedInRound
        if adjudicated == round then
            result[#result + 1] = inst
        elseif adjudicated == nil and round == current then
            result[#result + 1] = inst
        end
    end
    return result
end

--- Participants with their round token still free: not placed on an open row,
--- and not stuck in one this round adjudicated. Derived, so a round advance
--- hands everyone back without touching data.
--- @param run MTGRun
--- @param round number
--- @return MTGParticipant[]
function MTGRun.TrayParticipants(run, round)
    --A token is one thing and can only be in one place, so it is out of the
    --tray while it occupies a slot on a test still in play. A finished test
    --releases it: it comes back and can take another, marked as having acted.
    local placed = {}
    for _, inst in ipairs(run:try_get("instances", {})) do
        if inst.adjudicatedInRound == nil then
            if inst.lead ~= nil then placed[inst.lead.charid] = true end
            if inst.assist ~= nil then placed[inst.assist.charid] = true end
        end
    end

    local result = {}
    for _, p in ipairs(MTGRun.ActiveParticipants(run)) do
        if not placed[p.charid] then
            result[#result + 1] = p
        end
    end
    return result
end

--- How many times this Challenge has been carried through to an outcome.
--- Counted from the rows rather than tallied, so an undo hands the attempt
--- straight back.
--- @param run MTGRun
--- @param chid string
--- @return number
function MTGRun.AttemptsMade(run, chid)
    local count = 0
    for _, inst in ipairs(run:try_get("instances", {})) do
        if inst.challengeId == chid and inst.adjudicatedInRound ~= nil then
            count = count + 1
        end
    end
    return count
end

--- Attempts still available, the first one included.
--- @param run MTGRun
--- @param ch MTGChallengeDef
--- @return number
function MTGRun.AttemptsLeft(run, ch)
    return math.max(0, (ch:RepeatLimit() + 1) - MTGRun.AttemptsMade(run, ch.id))
end

--- Has this Participant already taken a test that resolved this round? Purely
--- a readout: it never blocks them from taking another.
--- @param run MTGRun
--- @param charid string
--- @return boolean
function MTGRun.HasActedThisRound(run, charid)
    local round = run.round or 1
    for _, inst in ipairs(run:try_get("instances", {})) do
        if inst.adjudicatedInRound == round then
            if (inst.lead ~= nil and inst.lead.charid == charid)
                or (inst.assist ~= nil and inst.assist.charid == charid) then
                return true
            end
        end
    end
    return false
end

--- Turn the round and open whatever becomes available.
function MTGRun.AdvanceRound()
    MTGRun.Mutate("Advance montage round", function(run)
        run.round = (run.round or 1) + 1
        MTGRun.SeedRound(run, run.round)
    end)
end

--- Can this participant take this slot on this row?
--- @param run MTGRun
--- @param inst table
--- @param slot string "lead" or "assist"
--- @param charid string
--- @return boolean
function MTGRun.CanStage(run, inst, slot, charid)
    if inst == nil or inst.adjudicatedInRound ~= nil then
        return false
    end
    if inst[slot] ~= nil then
        return false
    end
    --Nothing can join a row whose Lead has already rolled: an Assist arriving
    --then would earn a grant with no roll left to apply it to.
    if inst[slot .. "Roll"] ~= nil or inst.leadRoll ~= nil then
        return false
    end
    --Lead and Assist are two Participants, so the other slot rules them out.
    local other = cond(slot == "lead", "assist", "lead")
    if inst[other] ~= nil and inst[other].charid == charid then
        return false
    end

    --Stage lifts them off any row it can, but a slot they have already rolled
    --in cannot be emptied without discarding the roll. Staging them anyway
    --leaves them on two rows, and the second one holds them out of the tray.
    for _, row in ipairs(run:try_get("instances", {})) do
        if row.id ~= inst.id and row.adjudicatedInRound == nil then
            if (row.lead ~= nil and row.lead.charid == charid and row.leadRoll ~= nil)
                or (row.assist ~= nil and row.assist.charid == charid
                    and row.assistRoll ~= nil) then
                return false
            end
        end
    end

    return true
end

--- The Challenge's allowed characteristic this participant scores highest in.
--- Ties go to the order the Director listed them, so the walk is over the
--- allowed list rather than over the characteristics.
--- @param ch MTGChallengeDef
--- @param charid string
--- @return string
function MTGRun.DeriveCharacteristic(ch, charid)
    local best = ""
    local bestModifier = nil
    for _, attrId in ipairs(ch:try_get("allowedCharacteristics", {})) do
        local modifier = MTGUtils.CharacteristicModifier(charid, attrId)
        if modifier ~= nil and (bestModifier == nil or modifier > bestModifier) then
            best = attrId
            bestModifier = modifier
        end
    end
    return best
end

--- Retune one of the rules module's Challenge fields mid-Run.
--- Writes to the Run's own copy of the Challenge, so the prepped montage in the
--- library is untouched and the change dies with the Run. Point-forward by
--- construction: an adjudicated instance keeps the outcome it was handed, and a
--- repeat of this Challenge picks the new value up on its next test.
--- @param challengeId string
--- @param fieldId string
--- @param value any
function MTGRun.SetChallengeField(challengeId, fieldId, value)
    local run = MTGRun.Active()
    if run == nil then
        return
    end

    --Read through try_get rather than FieldsFor: FieldsFor CREATES the bag it
    --cannot find, which would mutate the document outside a change.
    local target = nil
    for _, ch in ipairs(run:try_get("challenges", {})) do
        if ch.id == challengeId then
            target = ch
            break
        end
    end
    if target == nil then
        return
    end

    local bags = target:try_get("moduleFields")
    local bag = bags ~= nil and bags[run.moduleId] or nil
    if bag ~= nil and bag[fieldId] == value then
        return
    end

    MTGRun.Mutate("Retune challenge", function(r)
        for _, ch in ipairs(r:try_get("challenges", {})) do
            if ch.id == challengeId then
                ch:FieldsFor(r.moduleId)[fieldId] = value
                return
            end
        end
    end)
end

--- Record a human's characteristic pick. attrOverridden stops the derivation
--- from stomping it when the Challenge's allowed list is edited later.
--- @param instanceId string
--- @param slot string
--- @param attrId string
function MTGRun.SetAssignmentCharacteristic(instanceId, slot, attrId)
    local run = MTGRun.Active()
    if run == nil then
        return
    end

    local inst = MTGRun.Instance(run, instanceId)
    if inst == nil or inst.adjudicatedInRound ~= nil or inst[slot] == nil then
        return
    end
    if inst[slot].attrId == attrId and inst[slot].attrOverridden == true then
        return
    end

    MTGRun.Mutate("Choose characteristic", function(r)
        local i = MTGRun.Instance(r, instanceId)
        if i == nil or i[slot] == nil then
            return
        end
        i[slot].attrId = attrId
        i[slot].attrOverridden = true
    end)
end

--- @param instanceId string
--- @param slot string
--- @param skillId string "" for no skill, which is a valid choice
function MTGRun.SetAssignmentSkill(instanceId, slot, skillId)
    local run = MTGRun.Active()
    if run == nil then
        return
    end

    local inst = MTGRun.Instance(run, instanceId)
    if inst == nil or inst.adjudicatedInRound ~= nil or inst[slot] == nil then
        return
    end
    if inst[slot].skillId == skillId then
        return
    end

    MTGRun.Mutate("Choose skill", function(r)
        local i = MTGRun.Instance(r, instanceId)
        if i ~= nil and i[slot] ~= nil then
            i[slot].skillId = skillId
        end
    end)
end

--- What each Participant actually did, read back off the resolved rows. An
--- assist decides a test and then leaves no trace in the outcome, so this is
--- the only place that work is ever credited.
--- @param run MTGRun
--- @return table[]
function MTGRun.BuildRecap(run)
    local rows = {}
    local byChar = {}

    for _, p in ipairs(MTGRun.ActiveParticipants(run)) do
        local row = {
            charid = p.charid,
            name = p.name or "",
            led = 0,
            assisted = 0,
            --Challenges this hero actually moved: led to something other than a
            --failure, or assisted well enough to hand the Lead an edge. A lead
            --that failed and an assist that only earned a bane are left off --
            --this is the credit list, not the attendance sheet.
            credits = {},
            bestTier = nil,
        }
        byChar[p.charid] = row
        rows[#rows + 1] = row
    end

    local rules = MTGRules.GetOrDefault(run.moduleId)
    local seenCredit = {}

    local function Credit(row, charid, ch)
        local name = ch ~= nil and ch.name or nil
        if name == nil or name == "" then
            return
        end
        local key = charid .. "/" .. name
        if seenCredit[key] then
            return
        end
        seenCredit[key] = true
        row.credits[#row.credits + 1] = name
    end

    for _, inst in ipairs(run:try_get("instances", {})) do
        if inst.adjudicatedInRound ~= nil then
            local ch = MTGRun.ChallengeFor(run, inst)

            for _, slot in ipairs({ "lead", "assist" }) do
                local a = inst[slot]
                local row = a ~= nil and byChar[a.charid] or nil
                if row ~= nil then
                    if slot == "lead" then
                        row.led = row.led + 1
                        local roll = inst.leadRoll
                        if roll ~= nil and (row.bestTier == nil or (roll.tier or 0) > row.bestTier) then
                            row.bestTier = roll.tier or 0
                        end

                        --Tone rather than the outcome id, so a module can name
                        --its outcomes whatever it likes and still be read here.
                        local outcome = inst.outcome or {}
                        if outcome.tone ~= nil and outcome.tone ~= "danger" then
                            Credit(row, a.charid, ch)
                        end
                    else
                        row.assisted = row.assisted + 1

                        --"Edge or better" asked of AssistGrant rather than of a
                        --tier number, so it follows if the assist tiers are ever
                        --retuned.
                        local assistRoll = inst.assistRoll
                        if assistRoll ~= nil then
                            local grantId = rules.AssistGrant(assistRoll.tier or 1)
                            if grantId ~= nil and grantId ~= "bane" then
                                Credit(row, a.charid, ch)
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.led ~= b.led then
            return a.led > b.led
        end
        if a.assisted ~= b.assisted then
            return a.assisted > b.assisted
        end
        return string.lower(a.name) < string.lower(b.name)
    end)

    return rows
end

--- Close the montage and freeze its report. The Run stays until the Director
--- puts it away, so the table can sit with the result.
function MTGRun.EndRun()
    local run = MTGRun.Active()
    if run == nil or run.status == MTGConstants.statusEnded then
        return
    end

    MTGRun.Mutate("End montage", function(r)
        r.ending = MTGRules.GetOrDefault(r.moduleId).BuildEnding(r)
        r.status = MTGConstants.statusEnded
    end)
end

--- Everything the closing report needs, detached from the Run. The Run is
--- cleared the moment the report goes out, so the report cannot read it.
--- @param run MTGRun
--- @return table
function MTGRun.BuildReportPayload(run)
    --Taken from the module's own meters rather than reading progress directly,
    --so a Draw Steel montage closes on Successes and Failures while T&O closes
    --on Threats and Opportunities, with no branch here.
    local progress = {}
    for _, meter in ipairs(MTGRules.GetOrDefault(run.moduleId).DescribeProgress(run)) do
        --Both forms travel: the meter's own label reads as a scale next to a
        --ratio, but the closing line counts, and "1 Opportunities Seized" is
        --not a sentence. The module knows its own singular.
        progress[#progress + 1] = {
            label = meter.label or "",
            labelOne = meter.labelOne or meter.label or "",
            value = meter.value or 0,
        }
    end

    return {
        name = run.name or "Montage",
        ending = DeepCopy(run:try_get("ending", {})),
        progress = progress,
        recap = MTGRun.BuildRecap(run),
    }
end

--- Throw the montage's name across every screen with the sword reveal the
--- initiative banner uses, so the report arrives as an event.
--- @param payload table
function MTGRun.AnnounceEnding(payload)
    local ending = payload ~= nil and payload.ending or nil
    local subtitle = nil
    if ending ~= nil then
        if ending.degree ~= nil then
            subtitle = ending.degree.label
        elseif (ending.victories or 0) > 0 then
            subtitle = string.format("%d %s", ending.victories,
                cond(ending.victories == 1, "Victory", "Victories"))
        end
    end

    DramaticBanner.Show{
        text = payload ~= nil and payload.name or "Montage",
        subtitle = subtitle,
    }
end

--- Send the celebration to every client, the Director included. It travels as
--- a payload rather than a pointer at the Run, so clearing the Run in the same
--- breath cannot empty it out from under the table. No host element is taken:
--- this fires on a timer, by which point any panel that asked for it is gone.
--- @param payload table
function MTGRun.PresentReport(payload)
    --A local dismiss destroys the panel but leaves the presentdialog document
    --standing, so without a ttl every later reload rebuilds the celebration.
    --The board carries no ttl: that one has to last the session.
    GameHud.PresentDialogToUsers(GameHud.instance.parentPanel,
        MTGConstants.dialogId, { report = payload, ttl = MTGConstants.celebrationTTL })
end

--- The Director is done. Announce the result with the sword banner, clear the
--- montage, and let the celebration land as the banner draws off.
function MTGRun.CompleteRun()
    if MTGRun.Active() == nil then
        return
    end

    --Award before the snapshot, so the celebration carries who got what.
    MTGRun.AwardVictories()

    local run = MTGRun.Active()
    if run == nil then
        return
    end

    local payload = MTGRun.BuildReportPayload(run)

    MTGRun.HideFromPlayers()
    MTGRun.AnnounceEnding(payload)

    --After the table has been told, so building the document cannot delay the
    --ending reaching the players; still before Discard, which takes the
    --instances the journal is made of.
    if MTGRun.EndingWritesJournal(run) then
        MTGJournal.WriteResults(run)
    end

    MTGRun.Discard()
    LaunchablePanel.LaunchPanelByName(MTGConstants.panelName, "hide")

    dmhub.Schedule(DramaticBanner.holdTime, function()
        MTGRun.PresentReport(payload)
    end)
end

--- @param degree table {id, label}
function MTGRun.SetEndingDegree(degree)
    local run = MTGRun.Active()
    local ending = run ~= nil and run:try_get("ending") or nil
    if ending == nil then
        return
    end

    local current = ending.degree
    if current ~= nil and degree ~= nil and current.id == degree.id then
        return
    end

    MTGRun.Mutate("Set degree of success", function(r)
        local e = r:try_get("ending")
        if e ~= nil then
            e.degree = degree
        end
    end)
end

--- @param victories number
function MTGRun.SetEndingVictories(victories)
    local run = MTGRun.Active()
    local ending = run ~= nil and run:try_get("ending") or nil
    if ending == nil then
        return
    end

    local value = math.max(0, math.floor(victories or 0))
    if ending.victories == value then
        return
    end

    MTGRun.Mutate("Set Victory award", function(r)
        local e = r:try_get("ending")
        if e ~= nil then
            e.victories = value
        end
    end)
end

--- Whether completing this Run should leave a journal document behind. Kept on
--- the Run rather than in the panel so the choice survives the rebuilds that
--- happen while the ending screen is up.
--- @param write boolean
function MTGRun.SetEndingWriteJournal(write)
    local run = MTGRun.Active()
    local ending = run ~= nil and run:try_get("ending") or nil
    if ending == nil or ending.writeJournal == (write == true) then
        return
    end

    MTGRun.Mutate("Change montage journal", function(r)
        local e = r:try_get("ending")
        if e ~= nil then
            e.writeJournal = write == true
        end
    end)
end

--- Absent means yes: a montage that ends leaves a record unless the Director
--- says otherwise.
--- @param run MTGRun
--- @return boolean
function MTGRun.EndingWritesJournal(run)
    local ending = run ~= nil and run:try_get("ending") or nil
    return ending == nil or ending.writeJournal ~= false
end

--- Hand the Victories out, once. SetVictories is an absolute write, so
--- without the flag a second press would award them all over again.
function MTGRun.AwardVictories()
    local run = MTGRun.Active()
    local ending = run ~= nil and run:try_get("ending") or nil
    if ending == nil or ending.awarded == true then
        return
    end

    local amount = ending.victories or 0
    local awardedTo = {}

    for _, p in ipairs(MTGRun.ActiveParticipants(run)) do
        if p.isHero == true then
            local token = dmhub.GetCharacterById(p.charid)
            if token ~= nil then
                awardedTo[#awardedTo + 1] = p.name or ""
                token:ModifyProperties{
                    description = "Award Victories",
                    combine = true,
                    execute = function()
                        token.properties:SetVictories(token.properties:GetVictories() + amount)
                    end,
                }
            end
        end
    end

    local active = MTGRun.Active()
    if active == nil or active:try_get("ending") == nil then
        return
    end

    MTGRun.Mutate("Award Victories", function(r)
        local e = r:try_get("ending")
        if e ~= nil then
            e.awarded = true
            e.awardedTo = awardedTo
        end
    end)
end

--- The instance with a roll in flight, or nil.
--- @param run MTGRun
--- @return table|nil
function MTGRun.ResolvingInstance(run)
    for _, inst in ipairs(run:try_get("instances", {})) do
        if inst.resolution ~= nil then
            return inst
        end
    end
    return nil
end

--- @param instanceId string
--- @param resolution table|nil nil takes the row out of resolution
function MTGRun.SetResolution(instanceId, resolution)
    local run = MTGRun.Active()
    if run == nil then
        return
    end

    local inst = MTGRun.Instance(run, instanceId)
    --Clearing something already clear is the common case: Cancel and the Pump's
    --lost-request path both fire it defensively.
    if inst == nil or (inst.resolution == nil and resolution == nil) then
        return
    end

    MTGRun.Mutate("Montage roll", function(r)
        local i = MTGRun.Instance(r, instanceId)
        if i ~= nil then
            i.resolution = resolution
        end
    end)
end

--- @param instanceId string
--- @param slot string
--- @param roll table {total, naturalRoll, boons, banes, tier}
function MTGRun.RecordRoll(instanceId, slot, roll)
    local run = MTGRun.Active()
    if run == nil or MTGRun.Instance(run, instanceId) == nil then
        return
    end

    MTGRun.Mutate("Record montage roll", function(r)
        local i = MTGRun.Instance(r, instanceId)
        if i == nil then
            return
        end
        i[slot .. "Roll"] = roll
        i.resolution = nil
    end)
end

--- Write a finished test into the Run: the outcome sticks, progress moves,
--- the skills are spent, and the row freezes as its own record. A reopening
--- module gets a fresh row in the same round to try again on.
--- @param instanceId string
--- @param outcome table {id, label, tone}
function MTGRun.Adjudicate(instanceId, outcome, alsoGrant)
    local active = MTGRun.Active()
    if active == nil then
        return
    end

    local staged = MTGRun.Instance(active, instanceId)
    if staged == nil or staged.adjudicatedInRound ~= nil
        or MTGRun.ChallengeFor(active, staged) == nil then
        return
    end

    MTGRun.Mutate("Resolve montage test", function(run)
        local inst = MTGRun.Instance(run, instanceId)
        if inst == nil or inst.adjudicatedInRound ~= nil then
            return
        end

        local ch = MTGRun.ChallengeFor(run, inst)
        if ch == nil then
            return
        end

        --Folded in rather than left to a second change: a grant is one action
        --to the Director, and two commits mean two rebuilds on every screen.
        if alsoGrant then
            inst.granted = true
        end

        local rules = MTGRules.GetOrDefault(run.moduleId)
        inst.outcome = outcome
        inst.adjudicatedInRound = run.round or 1

        rules.ApplyProgress(run, ch, inst, 1)

        for _, slot in ipairs({ "lead", "assist" }) do
            local a = inst[slot]
            if a ~= nil and a.skillId ~= nil and a.skillId ~= "" then
                local p = MTGRun.Participant(run, a.charid)
                if p ~= nil then
                    p:get_or_add("skillsUsed", {})[a.skillId] = true
                end
            end
        end

        if rules.PostResolutionState(run, ch, inst) == MTGConstants.stateOpen then
            local instances = run:get_or_add("instances", {})
            local copy = {
                id = dmhub.GenerateGuid(),
                challengeId = ch.id,
                createdInRound = run.round or 1,
            }
            instances[#instances + 1] = copy
            inst.reopenedAs = copy.id
        end
    end)
end

--- Put a resolved test back the way it was, including the row its reopening
--- spawned, provided nobody has touched that one yet.
--- @param run MTGRun
--- @param inst table
local function Unadjudicate(run, inst)
    if inst == nil or inst.adjudicatedInRound == nil then
        return
    end

    local ch = MTGRun.ChallengeFor(run, inst)
    if ch ~= nil then
        MTGRules.GetOrDefault(run.moduleId).ApplyProgress(run, ch, inst, -1)
    end

    for _, slot in ipairs({ "lead", "assist" }) do
        local a = inst[slot]
        if a ~= nil and a.skillId ~= nil and a.skillId ~= "" then
            local p = MTGRun.Participant(run, a.charid)
            if p ~= nil then
                p:get_or_add("skillsUsed", {})[a.skillId] = nil
            end
        end
    end

    if inst.reopenedAs ~= nil then
        local instances = run:get_or_add("instances", {})
        for i, other in ipairs(instances) do
            if other.id == inst.reopenedAs and other.lead == nil and other.assist == nil then
                table.remove(instances, i)
                break
            end
        end
        inst.reopenedAs = nil
    end

    inst.outcome = nil
    inst.adjudicatedInRound = nil
end

--- Hand a Challenge to the Lead without a roll. The skills-spent bookkeeping
--- in Adjudicate only fires on a slot that actually chose a skill, so a grant
--- taken with no skill selected costs nobody anything.
--- @param instanceId string
function MTGRun.Grant(instanceId)
    local run = MTGRun.Active()
    if run == nil then
        return
    end

    local inst = MTGRun.Instance(run, instanceId)
    if inst == nil or inst.adjudicatedInRound ~= nil or inst.lead == nil then
        return
    end

    MTGRun.Adjudicate(instanceId,
        MTGRules.GetOrDefault(run.moduleId).GrantedOutcome(), true)
end

--- Unwind a whole test -- granted or rolled, both slots -- back to the state
--- the row was in before anyone was asked for anything. The staged heroes and
--- their picks stay put; only what the test produced goes.
--- @param instanceId string
function MTGRun.UndoTest(instanceId)
    local run = MTGRun.Active()
    if run == nil or MTGRun.Instance(run, instanceId) == nil then
        return
    end

    MTGRun.Mutate("Undo montage test", function(r)
        local i = MTGRun.Instance(r, instanceId)
        if i == nil then
            return
        end
        Unadjudicate(r, i)
        i.granted = nil
        i.leadRoll = nil
        i.assistRoll = nil
    end)
end

--- @param run MTGRun
--- @param inst table
--- @return boolean whether this row has anything to take back
function MTGRun.HasTestToUndo(run, inst)
    return inst.adjudicatedInRound ~= nil
        or inst.granted == true
        or inst.leadRoll ~= nil
        or inst.assistRoll ~= nil
end

--- May this client move this participant's token? The Director may move
--- anyone: canControl is true for the GM.
--- @param charid string
--- @return boolean
function MTGRun.CanManage(charid)
    local token = dmhub.GetCharacterById(charid)
    return token ~= nil and token.canControl == true
end

--- Put the run board on every client's screen. The host element is the
--- presenting panel: GameHud fires the event on its own parent panel and
--- keeps this only while the dialog is registered keeplocal.
--- @param hostPanel Panel
function MTGRun.PresentToPlayers(hostPanel)
    GameHud.PresentDialogToUsers(hostPanel, MTGConstants.dialogId, {})
end

--- Take the board off the players' screens. The Run itself is untouched: it
--- lives in this module's own document, not in the presentation.
function MTGRun.HideFromPlayers()
    GameHud.HidePresentedDialog()
end

--- Who this slot will accept. Free participants, plus anyone standing in
--- another open slot: placing them there lifts them out of it.
--- @param run MTGRun
--- @param inst table
--- @param slot string "lead" or "assist"
--- @return MTGParticipant[]
function MTGRun.StageOptions(run, inst, slot)
    local result = {}
    for _, p in ipairs(MTGRun.ActiveParticipants(run)) do
        if MTGRun.CanStage(run, inst, slot, p.charid) then
            result[#result + 1] = p
        end
    end
    return result
end

--- Place a participant, lifting them off wherever they were. Their token is
--- one thing: it is in the tray, or in a Lead slot, or in an Assist slot.
--- @param instanceId string
--- @param slot string
--- @param charid string
function MTGRun.Stage(instanceId, slot, charid)
    local active = MTGRun.Active()
    if active == nil
        or not MTGRun.CanStage(active, MTGRun.Instance(active, instanceId), slot, charid) then
        return
    end

    MTGRun.Mutate("Place participant", function(run)
        local inst = MTGRun.Instance(run, instanceId)
        if not MTGRun.CanStage(run, inst, slot, charid) then
            return
        end

        for _, other in ipairs(run:try_get("instances", {})) do
            if other.adjudicatedInRound == nil then
                if other.lead ~= nil and other.lead.charid == charid and other.leadRoll == nil then
                    other.lead = nil
                end
                if other.assist ~= nil and other.assist.charid == charid and other.assistRoll == nil then
                    other.assist = nil
                end
            end
        end

        local ch = MTGRun.ChallengeFor(run, inst)
        inst[slot] = {
            charid = charid,
            skillId = "",
            attrId = ch ~= nil and MTGRun.DeriveCharacteristic(ch, charid) or "",
            attrOverridden = false,
        }
    end)
end

--- Take a participant out of a slot and hand their token back to the tray.
--- @param instanceId string
--- @param slot string
function MTGRun.Unstage(instanceId, slot)
    local run = MTGRun.Active()
    if run == nil then
        return
    end

    local inst = MTGRun.Instance(run, instanceId)
    if inst == nil or inst.adjudicatedInRound ~= nil or inst[slot .. "Roll"] ~= nil
        or inst[slot] == nil then
        return
    end

    MTGRun.Mutate("Remove participant", function(r)
        local i = MTGRun.Instance(r, instanceId)
        if i ~= nil then
            i[slot] = nil
            --A Lead leaving does not evict the Assist; the row simply waits.
        end
    end)
end

--- @param run MTGRun
--- @param charid string
--- @return MTGParticipant|nil
function MTGRun.Participant(run, charid)
    for _, p in ipairs(run:try_get("participants", {})) do
        if p.charid == charid then
            return p
        end
    end
    return nil
end

--- Lift a participant out of whatever open slot holds them.
--- @param charid string
function MTGRun.UnstageParticipant(charid)
    MTGRun.Mutate("Remove participant", function(run)
        for _, inst in ipairs(run:try_get("instances", {})) do
            if inst.adjudicatedInRound == nil then
                if inst.lead ~= nil and inst.lead.charid == charid and inst.leadRoll == nil then
                    inst.lead = nil
                end
                if inst.assist ~= nil and inst.assist.charid == charid and inst.assistRoll == nil then
                    inst.assist = nil
                end
            end
        end
    end)
end
