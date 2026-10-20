local mod = dmhub.GetModLoading()

--- A character taking part in a Run.
--- @class MTGParticipant
--- @field charid string
--- @field name string
--- @field isHero boolean
--- @field included boolean
--- @field isCompanion boolean a beastheart's companion, not a roster choice
--- @field summonerId string|nil the charid a companion belongs to
MTGParticipant = RegisterGameType("MTGParticipant")

MTGParticipant.name = ""
MTGParticipant.isHero = false
MTGParticipant.included = true

--- Absent on every participant stored before companions were carried, so both
--- default rather than being read with try_get at each site.
MTGParticipant.isCompanion = false
MTGParticipant.summonerId = ""

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
--- @field successLadder table what the Director narrates per outcome, by rung id
--- @field successLadderShown boolean whether the table reads the ladder
--- @field image string the scene the table sees, copied so editing the montage mid-run changes nothing
MTGRun = RegisterGameType("MTGRun")

MTGRun.name = ""
MTGRun.round = 1
MTGRun.status = MTGConstants.statusSetup
MTGRun.paused = false

--- Copied from the Definition when the Run is made, so a Run started before
--- the ladder existed reads as kept back rather than raising.
MTGRun.successLadderShown = false

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

--- A row's roll record: who stands where, what they rolled, the request out.
--- The THCRollFlow shape, in `inst.roll`. A row not yet given one reads as
--- empty without one being written.
--- @param inst table
--- @return table
function MTGRun.Record(inst)
    return inst.roll or THCRollFlow.NewRecord()
end

--- Who stands in a seat, as stored: {charid, attrId?, skillId?}, or nil.
--- @param inst table
--- @param slot string
--- @return table|nil
function MTGRun.Seat(inst, slot)
    return MTGRun.Record(inst).slots[slot]
end

--- The roll a seat has made, or nil.
--- @param inst table
--- @param slot string
--- @return table|nil
function MTGRun.RowRoll(inst, slot)
    return MTGRun.Record(inst).rolls[slot]
end

--- The request out on a row, or nil.
--- @param inst table
--- @return table|nil
function MTGRun.Pending(inst)
    return MTGRun.Record(inst).pending
end

--- Whether a run still keeps rows the old way, waiting for the Director's
--- client to move them onto roll records.
--- @param run MTGRun
--- @return boolean
local function HasLegacy(run)
    for _, inst in ipairs(run:try_get("instances", {})) do
        if inst.lead ~= nil or inst.assist ~= nil or inst.leadRoll ~= nil
            or inst.assistRoll ~= nil or inst.resolution ~= nil then
            return true
        end
    end
    return false
end

--- The roll flow over one row's record. Cheap: make one whenever needed. It
--- reads the row afresh each time, so it never acts on a stale copy.
--- @param run MTGRun
--- @param inst table
--- @return THCRollFlow
function MTGRun.Flow(run, inst)
    local instanceId = inst.id

    --The run being changed, while inside one of this flow's changes, so a
    --hero can be lifted off other rows in the same change.
    local m_run = nil

    --- The run, the row and its Challenge as they stand now.
    --- @return MTGRun|nil, table|nil, MTGChallengeDef|nil
    local function Live()
        local r = MTGRun.Active()
        local i = r ~= nil and MTGRun.Instance(r, instanceId) or nil
        local ch = i ~= nil and MTGRun.ChallengeFor(r, i) or nil
        return r, i, ch
    end

    --- @return boolean
    local function Open()
        local r, i = Live()
        return r ~= nil and i ~= nil and r.status == MTGConstants.statusRunning
            and i.adjudicatedInRound == nil
    end

    local startCh = MTGRun.ChallengeFor(run, inst)
    local anySkill = startCh == nil or #startCh:try_get("allowedSkills", {}) == 0

    return THCRollFlow.CreateNew{
        read = function()
            local _, i = Live()
            return i ~= nil and MTGRun.Record(i) or nil
        end,

        mutate = function(description, fn)
            MTGRun.Mutate(description, function(r)
                if HasLegacy(r) then
                    return
                end
                local i = MTGRun.Instance(r, instanceId)
                if i == nil then
                    return
                end
                local record = i.roll
                local created = record == nil
                if created then
                    record = THCRollFlow.NewRecord()
                end
                m_run = r
                fn(record)
                m_run = nil
                if created then
                    i.roll = record
                end
            end)
        end,

        checkId = MTGConstants.rollCheckId,
        characteristics = function()
            local _, _, ch = Live()
            return ch ~= nil and ch:try_get("allowedCharacteristics", {}) or {}
        end,
        skills = function()
            local _, _, ch = Live()
            return ch ~= nil and ch:try_get("allowedSkills", {}) or {}
        end,
        anySkill = anySkill,

        title = function()
            local _, _, ch = Live()
            return ch ~= nil and ch.name or "Montage test"
        end,

        leadTiers = function()
            local r, _, ch = Live()
            if r == nil or ch == nil then
                return {}
            end
            return MTGRules.GetOrDefault(r.moduleId).TierLabels(r, ch)
        end,

        --An Assist joining after the Lead rolled would earn a grant with no
        --roll, so nobody is placed once the Lead has rolled.
        canStage = function(slot)
            if not Open() then
                return false
            end
            local _, i = Live()
            local record = MTGRun.Record(i)
            return record.pending == nil and record.rolls[slot] == nil
                and record.rolls[THCRollFlow.slotLead] == nil
        end,

        canEdit = function(slot)
            if not Open() then
                return false
            end
            local _, i = Live()
            local record = MTGRun.Record(i)
            return record.pending == nil and record.rolls[slot] == nil
        end,

        canRoll = Open,

        --One roll out across every row.
        sendBlocker = function()
            local r = MTGRun.Active()
            for _, row in ipairs(r ~= nil and r:try_get("instances", {}) or {}) do
                if row.id ~= instanceId and MTGRun.Pending(row) ~= nil then
                    return "Another row's roll is out."
                end
            end
            return nil
        end,

        --A hero who has rolled on another open row, or whose roll is out
        --there, stays put.
        mayPlace = function(charid)
            local r = MTGRun.Active()
            for _, row in ipairs(r ~= nil and r:try_get("instances", {}) or {}) do
                if row.id ~= instanceId and row.adjudicatedInRound == nil then
                    local record = MTGRun.Record(row)
                    for slot, seat in pairs(record.slots) do
                        if seat.charid == charid and (record.rolls[slot] ~= nil
                            or (record.pending ~= nil and record.pending.charid == charid)) then
                            return false
                        end
                    end
                end
            end
            return true
        end,

        --A token is one thing: placing it here lifts it off any other open row.
        release = function(charid)
            if m_run == nil then
                return
            end
            for _, row in ipairs(m_run:try_get("instances", {})) do
                local record = row.roll
                if row.id ~= instanceId and row.adjudicatedInRound == nil
                    and record ~= nil and record.pending == nil then
                    for slot, seat in pairs(record.slots) do
                        if seat.charid == charid and record.rolls[slot] == nil then
                            record.slots[slot] = nil
                        end
                    end
                end
            end
        end,
    }
end

--- What each seat of a row will roll with, or rolled with.
--- @param run MTGRun
--- @param inst table
--- @return {lead: table|nil, assist: table|nil}
function MTGRun.Picks(run, inst)
    return MTGRun.Flow(run, inst):Effective()
end

--- Drop every roll still out, as resetting, ending or clearing the montage
--- does: a request left behind would block every tool's next roll.
--- @param run MTGRun|nil
function MTGRun.AbandonRolls(run)
    if run == nil then
        return
    end
    for _, inst in ipairs(run:try_get("instances", {})) do
        if MTGRun.Pending(inst) ~= nil then
            MTGRun.Flow(run, inst):Abandon()
        end
    end
end

--- Move a run whose rows predate roll records onto them. Director only, and
--- once: it runs while legacy fields remain. A finished roll still sitting in
--- its request is carried across; anything still out is dropped and offered
--- again. A seat that rolled keeps exactly what it rolled with.
function MTGRun.MigrateRun()
    local run = MTGRun.Active()
    if not dmhub.isDM or run == nil or not HasLegacy(run) then
        return
    end

    local harvested = {}
    for _, inst in ipairs(run:try_get("instances", {})) do
        local res = inst.resolution
        if res ~= nil and res.actionId ~= nil then
            local status, rollInfo = THCRoll.Harvest(res.actionId, res.actionFor, true)
            if status == "complete" and rollInfo ~= nil then
                harvested[inst.id] = { slot = res.slot or THCRollFlow.slotLead, roll = rollInfo }
            end
            THCRoll.Cancel(res.actionId)
        end
    end

    --- @param roll table|nil
    --- @return table|nil
    local function CopyRoll(roll)
        if roll == nil then
            return nil
        end
        return {
            total = roll.total,
            naturalRoll = roll.naturalRoll,
            boons = roll.boons,
            banes = roll.banes,
            tier = roll.tier,
        }
    end

    --- @param entry table|nil
    --- @param rolled boolean
    --- @return table|nil
    local function Seat(entry, rolled)
        if entry == nil or entry.charid == nil then
            return nil
        end
        local seat = { charid = entry.charid }
        if rolled then
            seat.attrId = entry.attrId or ""
            seat.skillId = entry.skillId or ""
        else
            if entry.attrOverridden == true then
                seat.attrId = entry.attrId
            end
            if entry.skillId ~= nil and entry.skillId ~= "" then
                seat.skillId = entry.skillId
            end
        end
        return seat
    end

    MTGRun.Mutate("Update montage", function(r)
        for _, inst in ipairs(r:try_get("instances", {})) do
            if inst.lead ~= nil or inst.assist ~= nil or inst.leadRoll ~= nil
                or inst.assistRoll ~= nil or inst.resolution ~= nil then

                --A row already moved keeps its record; an old client writing a
                --legacy field after the move only has it cleared.
                if inst.roll == nil then
                    local record = THCRollFlow.NewRecord()
                    local caught = harvested[inst.id]
                    local settled = inst.adjudicatedInRound ~= nil

                    record.rolls[THCRollFlow.slotLead] = CopyRoll(inst.leadRoll)
                    record.rolls[THCRollFlow.slotAssist] = CopyRoll(inst.assistRoll)
                    if caught ~= nil and record.rolls[caught.slot] == nil then
                        record.rolls[caught.slot] = CopyRoll(caught.roll)
                    end

                    for _, slot in ipairs{ THCRollFlow.slotLead, THCRollFlow.slotAssist } do
                        record.slots[slot] = Seat(inst[slot], settled or record.rolls[slot] ~= nil)
                    end

                    inst.roll = record
                end

                inst.lead = nil
                inst.assist = nil
                inst.leadRoll = nil
                inst.assistRoll = nil
                inst.resolution = nil
            end
        end
    end)

    printf("MTG:: montage moved onto roll records")
end

--- Characters eligible to be seeded into a Run, on the map. Heroes first, then
--- by name, with each beastheart companion tucked in directly behind the hero
--- it belongs to -- the tray reads this order, and a companion beside its owner
--- is how the Director thinks of the pair.
---
--- Companions are carried but are not a roster choice: they follow their hero,
--- so the Setup screen leaves them out and only the tray shows them.
--- @return MTGParticipant[]
function MTGRun.EligibleParticipants()
    local roster = THCUtils.PartyRoster{ placedOnly = true, includeCompanions = true }

    local owned = {}
    local result = {}

    for _, entry in ipairs(roster) do
        local participant = MTGParticipant.CreateNew{
            charid = entry.charid,
            name = entry.name,
            isHero = entry.isHero,
            isCompanion = entry.isCompanion,
            summonerId = entry.summonerId or "",
            --Everyone eligible is on the map, so everyone starts ticked.
            included = true,
        }

        if entry.isCompanion then
            local owner = entry.summonerId or ""
            owned[owner] = owned[owner] or {}
            table.insert(owned[owner], participant)
        else
            result[#result + 1] = participant
        end
    end

    table.sort(result, function(a, b)
        if a.isHero ~= b.isHero then
            return a.isHero
        end
        return string.lower(a.name) < string.lower(b.name)
    end)

    --Spliced after the sort, so a companion cannot be pulled away from its hero
    --by its own name. A companion whose owner did not make the roster is
    --dropped with it: it is only ever here on that hero's account.
    local ordered = {}
    for _, participant in ipairs(result) do
        ordered[#ordered + 1] = participant
        for _, companion in ipairs(owned[participant.charid] or {}) do
            ordered[#ordered + 1] = companion
        end
    end

    return ordered
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

        successLadder = DeepCopy(def:try_get("successLadder", {})),
        successLadderShown = def:try_get("successLadderShown", false) == true,
        image = def:try_get("image", ""),
    }

    local doc = MTGRun.Doc()
    doc:BeginChange()
    doc.data.run = run
    doc:CompleteChange("Start montage setup")

    --The table gets the scene over everything while the Director sets up; the
    --Director is left looking at the map, since "players" excludes them.
    THCUtils.ShowScene(run.image, true, false)

    return run.id
end

--- Throw the Run away. The Definition it came from is untouched.
function MTGRun.Discard()
    MTGRun.AbandonRolls(MTGRun.Active())

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

--- Whether the Director has opened this Challenge's T&O Outcome to the table.
--- Says nothing about a landed Outcome, which shows either way.
--- @param run MTGRun
--- @param chid string
--- @return boolean
function MTGRun.IsOutcomeShown(run, chid)
    for _, ch in ipairs(run:try_get("challenges", {})) do
        if ch.id == chid then
            return ch:try_get("outcomeShown", false) == true
        end
    end
    return false
end

--- @param chid string
--- @param shown boolean
function MTGRun.SetOutcomeShown(chid, shown)
    local run = MTGRun.Active()
    if run == nil or MTGRun.IsOutcomeShown(run, chid) == (shown == true) then
        return
    end

    MTGRun.Mutate(cond(shown, "Show outcome", "Hide outcome"), function(r)
        for _, ch in ipairs(r:try_get("challenges", {})) do
            if ch.id == chid then
                ch.outcomeShown = shown == true
                return
            end
        end
    end)
end

--- Open the Success Ladder to the table, or take it back. Writes to the Run's
--- own copy, so a reveal mid montage never edits the saved montage it came
--- from and dies with the Run.
--- @param shown boolean
function MTGRun.SetLadderShown(shown)
    local run = MTGRun.Active()
    if run == nil or run:try_get("successLadderShown", false) == (shown == true) then
        return
    end

    MTGRun.Mutate(cond(shown, "Show success ladder", "Hide success ladder"), function(r)
        r.successLadderShown = shown == true
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
    local included = {}
    for _, p in ipairs(run:try_get("participants", {})) do
        if p.included ~= false and not p.isCompanion then
            included[p.charid] = true
        end
    end

    local result = {}
    for _, p in ipairs(run:try_get("participants", {})) do
        --A companion is never ticked or unticked in its own right; it is in
        --play exactly when the hero it belongs to is.
        local active = p.included ~= false
        if p.isCompanion then
            active = included[p.summonerId] == true
        end

        if active then
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

    --Play begins, so the scene drops behind the interface and the Director
    --joins the table in seeing it. After the mutate: one document at a time.
    local run = MTGRun.Active()
    if run ~= nil then
        THCUtils.ShowScene(run:try_get("image", ""), "all", true)
    end
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
    MTGRun.AbandonRolls(MTGRun.Active())

    MTGRun.Mutate("Reset montage", function(run)
        run.round = 1
        run.paused = false
        run.status = MTGConstants.statusSetup
        run.progress = MTGRules.GetOrDefault(run.moduleId).InitProgress(run)
        run.challengeModuleState = {}
        run.ending = nil

        --The rows ARE the record of play; clearing them clears all of it.
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

--- What the Director narrates when the montage lands on one rung.
--- @param run MTGRun
--- @param key string a MTGConstants.ladderRungs id
--- @return string
function MTGRun.LadderText(run, key)
    return run:try_get("successLadder", {})[key] or ""
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
        roll = THCRollFlow.NewRecord(),
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

--- Put a Challenge authored mid-run onto the board. It goes on the Run only,
--- never the saved montage, so the journal still records it.
--- @param ch MTGChallengeDef
function MTGRun.AddChallengeAtRuntime(ch)
    MTGRun.Mutate("Add challenge", function(run)
        if run:try_get("challenges") == nil then
            run.challenges = {}
        end
        run.challenges[#run.challenges + 1] = ch

        --SeedRound has already run for this round, so this row is made here.
        local round = run.round or 1
        if (ch.availableFromRound or 1) == round then
            if run:try_get("instances") == nil then
                run.instances = {}
            end
            run.instances[#run.instances + 1] = NewInstance(ch.id, round)
        end
    end)
end

--- Whether a player may suggest a Challenge now: the book rules, in play, and
--- not paused.
--- @param run MTGRun|nil
--- @return boolean
function MTGRun.CanSuggest(run)
    return run ~= nil
        and run.moduleId == MTGConstants.moduleBaseline
        and run.status == MTGConstants.statusRunning
        and run.paused ~= true
end

--- What a player's suggestion is called to start with: the first hero in the
--- roster they control, else their own name.
--- @param run MTGRun
--- @return string
function MTGRun.SuggestionName(run)
    local who = nil
    for _, p in ipairs(MTGRun.ActiveParticipants(run)) do
        if p.isHero and MTGRun.CanManage(p.charid) then
            who = p.name
            break
        end
    end
    if who == nil or who == "" then
        who = dmhub.GetDisplayName(dmhub.userid) or "Player"
    end
    return string.format("Suggestion: %s", who)
end

--- Put a player's suggested Challenge on the board for everyone. It goes on
--- the Run only, never the saved montage, so the journal still records it.
--- First in the list, which is what makes the newest suggestion lead.
--- @param ch MTGChallengeDef
function MTGRun.SuggestChallenge(ch)
    if not MTGRun.CanSuggest(MTGRun.Active()) then
        return
    end

    MTGRun.Mutate("Suggest challenge", function(run)
        if not MTGRun.CanSuggest(run) then
            return
        end

        local round = run.round or 1
        ch.availableFromRound = round
        ch.repeatable = 0
        ch.suggested = true
        ch:FieldsFor(MTGConstants.moduleBaseline).difficulty = "medium"

        if run:try_get("challenges") == nil then
            run.challenges = {}
        end
        table.insert(run.challenges, 1, ch)

        if run:try_get("instances") == nil then
            run.instances = {}
        end
        run.instances[#run.instances + 1] = NewInstance(ch.id, round)
    end)
end

--- Whether every hero standing on a row has a characteristic to roll. A
--- Challenge with none allowed derives nothing, so someone has to pick one.
--- @param run MTGRun
--- @param inst table
--- @return boolean
function MTGRun.HasCharacteristics(run, inst)
    for _, assignment in pairs(MTGRun.Picks(run, inst)) do
        if (assignment.attrId or "") == "" then
            return false
        end
    end
    return true
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
    local placed = {}
    for _, inst in ipairs(run:try_get("instances", {})) do
        if inst.adjudicatedInRound == nil then
            for _, seat in pairs(MTGRun.Record(inst).slots) do
                placed[seat.charid] = true
            end
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
            for _, seat in pairs(MTGRun.Record(inst).slots) do
                if seat.charid == charid then
                    return true
                end
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

    --Not FieldsFor: it CREATES the bag, mutating the document outside a change.
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
            --The credit list, not the attendance sheet.
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
                local a = MTGRun.Seat(inst, slot)
                local row = a ~= nil and byChar[a.charid] or nil
                if row ~= nil then
                    if slot == "lead" then
                        row.led = row.led + 1
                        local roll = MTGRun.RowRoll(inst, "lead")
                        if roll ~= nil and (row.bestTier == nil or (roll.tier or 0) > row.bestTier) then
                            row.bestTier = roll.tier or 0
                        end

                        --Tone, not the outcome id, so a module may name its outcomes freely.
                        local outcome = inst.outcome or {}
                        if outcome.tone ~= nil and outcome.tone ~= "danger" then
                            Credit(row, a.charid, ch)
                        end
                    else
                        row.assisted = row.assisted + 1

                        --Asked of AssistGrant, not a tier number, so retuning follows.
                        local assistRoll = MTGRun.RowRoll(inst, "assist")
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

    MTGRun.AbandonRolls(run)

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
    --The module's meters, so no branch here between Draw Steel and T&O.
    local progress = {}
    for _, meter in ipairs(MTGRules.GetOrDefault(run.moduleId).DescribeProgress(run)) do
        --labelOne travels too: "1 Opportunities Seized" is not a sentence.
        progress[#progress + 1] = {
            label = meter.label or "",
            labelOne = meter.labelOne or meter.label or "",
            value = meter.value or 0,
        }
    end

    --Travels whatever the eye said: a landed result reads either way.
    local ending = run:try_get("ending", {})
    local degree = ending.degree
    local ladder = ""
    if degree ~= nil then
        ladder = MTGRun.LadderText(run, degree.id)
    end

    return {
        name = run.name or "Montage",
        ending = DeepCopy(ending),
        progress = progress,
        ladder = ladder,
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
    --Without a ttl every later reload would rebuild the celebration.
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

    --After the announce, before Discard takes the instances the journal needs.
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

--- The row with a roll out, or nil. One at a time across the board.
--- @param run MTGRun
--- @return table|nil
function MTGRun.ResolvingInstance(run)
    for _, inst in ipairs(run:try_get("instances", {})) do
        if MTGRun.Pending(inst) ~= nil then
            return inst
        end
    end
    return nil
end

--- Whether a prompt's answer still belongs to the Lead roll it was asked
--- about: a re-roll since then makes it stale.
--- @param inst table
--- @param expectRoll nil|{total: number, naturalRoll: number}
--- @return boolean
local function RollStill(inst, expectRoll)
    if expectRoll == nil then
        return true
    end
    local roll = MTGRun.RowRoll(inst, "lead")
    return roll ~= nil and roll.total == expectRoll.total and roll.naturalRoll == expectRoll.naturalRoll
end

--- Write a finished test into the Run: the outcome sticks, progress moves,
--- the skills are spent, and the row freezes as its own record. A reopening
--- module gets a fresh row in the same round to try again on. Refused while a
--- roll is out on the row, or when the Lead roll it was decided on has since
--- been re-rolled.
--- @param instanceId string
--- @param outcome table {id, label, tone}
--- @param alsoGrant nil|boolean
--- @param expectRoll nil|{total: number, naturalRoll: number} the Lead roll this decides
function MTGRun.Adjudicate(instanceId, outcome, alsoGrant, expectRoll)
    local active = MTGRun.Active()
    if active == nil then
        return
    end

    local staged = MTGRun.Instance(active, instanceId)
    if staged == nil or staged.adjudicatedInRound ~= nil or MTGRun.Pending(staged) ~= nil
        or not RollStill(staged, expectRoll) or MTGRun.ChallengeFor(active, staged) == nil then
        return
    end

    MTGRun.Mutate("Resolve montage test", function(run)
        local inst = MTGRun.Instance(run, instanceId)
        if inst == nil or inst.adjudicatedInRound ~= nil or MTGRun.Pending(inst) ~= nil
            or not RollStill(inst, expectRoll) then
            return
        end

        local ch = MTGRun.ChallengeFor(run, inst)
        if ch == nil then
            return
        end

        --Folded in: two commits would mean two rebuilds on every screen.
        if alsoGrant then
            inst.granted = true
        end

        local rules = MTGRules.GetOrDefault(run.moduleId)
        inst.outcome = outcome
        inst.adjudicatedInRound = run.round or 1

        rules.ApplyProgress(run, ch, inst, 1)

        --Only a skill someone chose, or a seat rolled with, is spent.
        for _, a in pairs(MTGRun.Record(inst).slots) do
            if a.skillId ~= nil and a.skillId ~= "" then
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
                roll = THCRollFlow.NewRecord(),
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

    for _, a in pairs(MTGRun.Record(inst).slots) do
        if a.skillId ~= nil and a.skillId ~= "" then
            local p = MTGRun.Participant(run, a.charid)
            if p ~= nil then
                p:get_or_add("skillsUsed", {})[a.skillId] = nil
            end
        end
    end

    if inst.reopenedAs ~= nil then
        local instances = run:get_or_add("instances", {})
        for i, other in ipairs(instances) do
            if other.id == inst.reopenedAs and next(MTGRun.Record(other).slots) == nil then
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
--- in Adjudicate only fires on a seat with a chosen skill, so a grant taken
--- with no skill chosen costs nobody anything.
--- @param instanceId string
function MTGRun.Grant(instanceId)
    local run = MTGRun.Active()
    if run == nil then
        return
    end

    local inst = MTGRun.Instance(run, instanceId)
    if inst == nil or inst.adjudicatedInRound ~= nil or MTGRun.Seat(inst, "lead") == nil
        or MTGRun.Pending(inst) ~= nil then
        return
    end

    MTGRun.Adjudicate(instanceId,
        MTGRules.GetOrDefault(run.moduleId).GrantedOutcome(), true)
end

--- Unwind a whole test -- granted or rolled, both seats -- back to the state
--- the row was in before anyone was asked for anything. The heroes and their
--- picks stay put; only what the test produced goes. A roll still out is
--- dropped first.
--- @param instanceId string
function MTGRun.UndoTest(instanceId)
    local run = MTGRun.Active()
    local inst = run ~= nil and MTGRun.Instance(run, instanceId) or nil
    if inst == nil then
        return
    end

    if MTGRun.Pending(inst) ~= nil then
        MTGRun.Flow(run, inst):Abandon()
    end

    MTGRun.Mutate("Undo montage test", function(r)
        local i = MTGRun.Instance(r, instanceId)
        if i == nil then
            return
        end
        Unadjudicate(r, i)
        i.granted = nil
        local record = i.roll
        if record ~= nil then
            record.rolls = {}
            record.previous = {}
            record.rerolled = {}
            record.pending = nil
        end
    end)
end

--- @param run MTGRun
--- @param inst table
--- @return boolean whether this row has anything to take back
function MTGRun.HasTestToUndo(run, inst)
    return inst.adjudicatedInRound ~= nil
        or inst.granted == true
        or next(MTGRun.Record(inst).rolls) ~= nil
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

--- Who an empty seat on this row offers: everyone the row may take. Placing
--- one lifts them off any other open row where they have not rolled.
--- @param run MTGRun
--- @param inst table
--- @return {charid: string, name: string}[]
function MTGRun.StageOptions(run, inst)
    local flow = MTGRun.Flow(run, inst)
    local result = {}
    for _, p in ipairs(MTGRun.ActiveParticipants(run)) do
        if flow.host.mayPlace(p.charid) then
            result[#result + 1] = { charid = p.charid, name = p.name }
        end
    end
    return result
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

--- Hand a participant back to the tray from whatever open seat holds them.
--- @param charid string
function MTGRun.UnstageParticipant(charid)
    local run = MTGRun.Active()
    if run == nil then
        return
    end
    for _, inst in ipairs(run:try_get("instances", {})) do
        if inst.adjudicatedInRound == nil then
            MTGRun.Flow(run, inst):Return(charid)
        end
    end
end
