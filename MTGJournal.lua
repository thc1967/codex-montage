local mod = dmhub.GetModLoading()

--- The montage's results, written into the journal once the run ends. A
--- point-in-time record: text and portraits, never read back and never
--- updated, so nothing about a montage's results is kept as data.
MTGJournal = {}

local FOLDER_NAME = "Montage Results"

--- An empty header cell renders absurdly tall, and HTML entities come through
--- literally, so the columns above the portraits carry a zero-width space.
local BLANK_HEADER = "\226\128\139"

--- uiscale is the only size control a RichImage has; maxWidth stays 100%.
local PORTRAIT_SCALE = 0.30

--- A cell's text, with the characters that would break the row taken out.
--- @param str string|nil
--- @return string
local function Cell(str)
    str = tostring(str or "")
    str = string.gsub(str, "[\r\n]+", " ")
    str = string.gsub(str, "|", "/")
    return string.trim(str)
end

--- @param str string
--- @return string
local function Capitalize(str)
    if str == "" then
        return str
    end
    return string.upper(string.sub(str, 1, 1)) .. string.sub(str, 2)
end

--- Characteristic and skill as one phrase; the skill is optional.
--- @param assignment table
--- @return string
local function TestText(assignment)
    local parts = { MTGUtils.CharacteristicName(assignment.attrId) }
    if assignment.skillId ~= nil and assignment.skillId ~= "" then
        parts[#parts + 1] = MTGUtils.SkillName(assignment.skillId)
    end
    return table.concat(parts, ", ")
end

--- @param roll table|nil
--- @return string
local function RollText(roll)
    if roll == nil then
        return ""
    end
    return string.format("%d (tier %d)", roll.total or 0, roll.tier or 0)
end

--- What the test came to. Deliberately computed here rather than shared with
--- the card: a journal keeps the words it was written with, and should not
--- change because the rules module's wording did.
--- @param run MTGRun
--- @param inst table
--- @param ch MTGChallengeDef
--- @return string
local function OutcomeText(run, inst, ch)
    if inst.outcome ~= nil then
        return inst.outcome.label or ""
    end
    local roll = inst.leadRoll
    if roll == nil then
        return ""
    end
    local outcome = MTGRules.GetOrDefault(run.moduleId).RollToOutcome(run, ch, roll)
    return outcome ~= nil and outcome.label or ""
end

--- @param run MTGRun
--- @param inst table
--- @return string
local function AssistText(run, inst)
    local grant = MTGResolver.AssistGrant(run, inst) or "bane"
    return "Assist: " .. Capitalize(string.gsub(grant, "_", " "))
end

--- Every adjudicated row of one round, in the order the board showed them.
--- @param run MTGRun
--- @param round number
--- @return table[]
local function InstancesInRound(run, round)
    local result = {}
    for _, inst in ipairs(run:try_get("instances", {})) do
        if inst.adjudicatedInRound == round then
            result[#result + 1] = inst
        end
    end
    return result
end

--- The document's text and its RichImage annotations, built together because a
--- tag is bound to its image by the annotation key.
--- @param run MTGRun
--- @return string content, table annotations
local function BuildContent(run)
    local annotations = {}
    local tagCount = 0
    local lines = {}

    local function add(str)
        lines[#lines + 1] = str
    end

    --- @param charid string
    --- @return string the tag to drop in a cell, or a blank cell's worth
    local function Portrait(charid)
        local token = dmhub.GetCharacterById(charid)
        if token == nil then
            return BLANK_HEADER
        end
        tagCount = tagCount + 1
        local key = string.format("image:t%d", tagCount)
        annotations[key] = RichImage.new{
            image = token.portrait,
            halign = "left",
            maxWidth = "100%",
            uiscale = PORTRAIT_SCALE,
        }
        return string.format("[[%s]]", key)
    end

    add(string.format("# %s", Cell(run.name)))
    add("")
    add(string.format("*%s*", os.date("%A, %d %B %Y")))
    add("")
    add(string.format("**Montage Type:** %s", Cell(MTGRules.Name(run.moduleId))))
    add(string.format("**Rounds:** %d", run.round or 1))

    local ending = run:try_get("ending")
    if ending ~= nil and ending.degree ~= nil then
        add(string.format("**Result:** %s", Cell(ending.degree.label)))
    end

    for _, meter in ipairs(MTGRules.GetOrDefault(run.moduleId).DescribeProgress(run)) do
        add(string.format("**%s:** %s", Cell(meter.label), tostring(meter.value or 0)))
    end

    if ending ~= nil and (ending.victories or 0) > 0 then
        add(string.format("**Victories:** %d", ending.victories))
    end

    add("")

    --The montage's own description, as authored. It is markdown already, so it
    --goes in whole rather than through Cell.
    local description = string.trim(run:try_get("description", ""))
    if description ~= "" then
        add(description)
        add("")
    end

    for round = 1, run.round or 1 do
        local instances = InstancesInRound(run, round)
        if #instances > 0 then
            add(string.format("## Round %d", round))
            add("")
            add(string.format("|%s| Hero | Challenge | Test | Roll | Outcome |", BLANK_HEADER))
            add("| --- | --- | --- | --- | --- | --- |")

            for _, inst in ipairs(instances) do
                local ch = MTGRun.ChallengeFor(run, inst)
                local name = ch ~= nil and ch.name or ""

                local lead = inst.lead
                if lead ~= nil then
                    local p = MTGRun.Participant(run, lead.charid)
                    add(string.format("|%s| %s | %s | %s | %s | %s |",
                        Portrait(lead.charid),
                        Cell(p ~= nil and p.name or ""),
                        Cell(name),
                        Cell(TestText(lead)),
                        Cell(RollText(inst.leadRoll)),
                        Cell(OutcomeText(run, inst, ch))))
                end

                --The assist is its own row under the lead it helped, set apart
                --by italics rather than by a column of its own.
                local assist = inst.assist
                if assist ~= nil then
                    local p = MTGRun.Participant(run, assist.charid)
                    add(string.format("|%s| *%s* | *%s* | *%s* | *%s* | *%s* |",
                        Portrait(assist.charid),
                        Cell(p ~= nil and p.name or ""),
                        Cell(name),
                        Cell(TestText(assist)),
                        Cell(RollText(inst.assistRoll)),
                        Cell(AssistText(run, inst))))
                end
            end

            add("")
        end
    end

    return table.concat(lines, "\n"), annotations
end

--- @return string|nil the Montage Results folder's id, if it exists yet
local function FindFolder()
    for id, folder in pairs(assets.documentFoldersTable or {}) do
        if folder.description == FOLDER_NAME then
            return id
        end
    end
    return nil
end

--- @param title string
--- @param content string
--- @param annotations table
--- @param folderid string
local function Place(title, content, annotations, folderid)
    local doc = MarkdownDocument.new{
        id = dmhub.GenerateGuid(),
        parentFolder = folderid,
        description = title,
        annotations = annotations,
    }
    doc:SetTextContent(content)
    doc:Upload()
end

--- Write the results of a finished Run into the journal. Call this while the
--- Run is still alive: Discard takes the instances with it.
--- @param run MTGRun
function MTGJournal.WriteResults(run)
    if run == nil then
        return
    end

    --The record belongs to the Director. Only their client is meant to reach
    --this, but the Complete button is merely hidden from players rather than
    --gated, and a stray copy in a player's private tree would be nobody's.
    if not dmhub.isDM then
        return
    end

    --Built now, placed later: the folder may not exist yet, and by the time it
    --does the Run is gone.
    local title = run.name or "Montage"
    local content, annotations = BuildContent(run)

    local folderid = FindFolder()
    if folderid ~= nil then
        Place(title, content, annotations, folderid)
        return
    end

    assets:UploadNewDocumentFolder{
        description = FOLDER_NAME,
        parentFolder = "private",
    }

    --UploadNewDocumentFolder returns nothing and lands asynchronously, so give
    --it a moment and look again. A folder that never arrives must not cost the
    --Director the document: the private root will do.
    dmhub.Schedule(2, function()
        Place(title, content, annotations, FindFolder() or "private")
    end)
end
