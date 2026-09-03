local mod = dmhub.GetModLoading()

--- One authored Challenge inside a Montage Definition.
--- @class MTGChallengeDef
--- @field id string
--- @field name string
--- @field description string
--- @field allowedCharacteristics string[] ordered; ties in the derived characteristic resolve to this order
--- @field allowedSkills string[]
--- @field repeatable number how many times it may be attempted AGAIN
--- @field availableFromRound number
--- @field moduleFields table keyed by rules module id
--- @field hidden boolean authored out of sight, for the Director to reveal
--- @field outcomeShown boolean T&O only; whether the table reads the Outcome before it lands
MTGChallengeDef = RegisterGameType("MTGChallengeDef")

MTGChallengeDef.name = "New Challenge"
MTGChallengeDef.description = ""
MTGChallengeDef.repeatable = 0
MTGChallengeDef.availableFromRound = 1

--- Declared on the type, which is what makes every Challenge authored before
--- this existed read as visible without a migration touching the library.
MTGChallengeDef.hidden = false

--- Keeps the difficulty off the players' card and out of the roll they are
--- asked for. Draw Steel only: T&O has no difficulty to hide.
MTGChallengeDef.difficultyHidden = false

--- Whether the T&O Outcome text is carried on the players' runtime card. Named
--- for what lights the eye rather than for what hides it: the default is off,
--- and an `outcomeHidden` twin would have to default TRUE to mean the same
--- thing, which reads backwards as a type default. A landed Outcome shows
--- regardless - see OutcomeRevealed in MTGChallengeCard.
MTGChallengeDef.outcomeShown = false

--- How many further attempts this Challenge allows. Stored as a count now;
--- a legacy boolean true meant "always", which reads as the cap.
--- @return number
function MTGChallengeDef:RepeatLimit()
    local value = self:try_get("repeatable", 0)
    if value == true then
        return MTGConstants.repeatMax
    end
    if type(value) ~= "number" then
        return 0
    end
    return math.max(0, math.min(MTGConstants.repeatMax, math.floor(value)))
end

--- @param args nil|table
--- @return MTGChallengeDef
function MTGChallengeDef.CreateNew(args)
    args = args or {}
    args.id = args.id or dmhub.GenerateGuid()
    args.allowedCharacteristics = args.allowedCharacteristics or {}
    args.allowedSkills = args.allowedSkills or {}
    args.moduleFields = args.moduleFields or {}
    return MTGChallengeDef.new(args)
end

--- The field bag owned by one rules module, created on first access. Keeping
--- them separate lets a Definition change module without losing the fields the
--- previous one authored.
--- @param moduleId string
--- @return table
function MTGChallengeDef:FieldsFor(moduleId)
    local fields = self:try_get("moduleFields")
    if fields == nil then
        self.moduleFields = {}
        fields = self.moduleFields
    end
    if fields[moduleId] == nil then
        fields[moduleId] = {}
    end
    return fields[moduleId]
end

--- A module field's value, falling back to the field's declared default.
--- @param moduleId string
--- @param field table a ChallengeFields() entry
--- @return any
function MTGChallengeDef:FieldValue(moduleId, field)
    local value = self:FieldsFor(moduleId)[field.id]
    if value == nil then
        return field.default
    end
    return value
end

--- A prepared, reusable montage. A Run copies one wholesale and never writes
--- back to it.
--- @class MTGDefinition
--- @field id string
--- @field name string
--- @field image string
--- @field moduleId string
--- @field moduleSettings table
--- @field challenges MTGChallengeDef[]
MTGDefinition = RegisterGameType("MTGDefinition")

MTGDefinition.name = "New Montage"
MTGDefinition.image = ""
MTGDefinition.description = ""
MTGDefinition.folderId = ""
MTGDefinition.moduleId = MTGConstants.moduleBaseline

--- @param args nil|table
--- @return MTGDefinition
function MTGDefinition.CreateNew(args)
    args = args or {}
    args.id = args.id or dmhub.GenerateGuid()
    args.moduleSettings = args.moduleSettings or {}
    args.challenges = args.challenges or {}
    return MTGDefinition.new(args)
end

--- @return string
function MTGDefinition:GetID()
    return self:try_get("id") or ""
end

--- @return number
function MTGDefinition:ChallengeCount()
    return #self:try_get("challenges", {})
end

--- The settings bag owned by one rules module, created on first access.
--- Keeping them separate lets a Definition change module and change back
--- without losing what the previous one had.
--- @param moduleId string
--- @return table
function MTGDefinition:SettingsFor(moduleId)
    local settings = self:try_get("moduleSettings")
    if settings == nil then
        self.moduleSettings = {}
        settings = self.moduleSettings
    end
    if settings[moduleId] == nil then
        settings[moduleId] = {}
    end
    return settings[moduleId]
end

--- A module setting, falling back to the field's declared default.
--- @param moduleId string
--- @param field table a SettingsFields() entry
--- @return number
function MTGDefinition:SettingValue(moduleId, field)
    local value = self:SettingsFor(moduleId)[field.id]
    if value == nil then
        return field.default
    end
    return value
end

mod:RegisterDocumentForCheckpointBackups(MTGConstants.libraryDoc)

--- @return LuaCodeModDocumentSnapshot
function MTGDefinition.Doc()
    return mod:GetDocumentSnapshot(MTGConstants.libraryDoc)
end

--- @return string monitorGame path for the library
function MTGDefinition.DocPath()
    return mod:GetDocumentPath(MTGConstants.libraryDoc)
end

--- Mutate the library inside one document change.
--- @param description string
--- @param fn fun(definitions: table<string, MTGDefinition>)
function MTGDefinition.Mutate(description, fn)
    local doc = MTGDefinition.Doc()
    doc:BeginChange()
    if doc.data.definitions == nil then
        doc.data.definitions = {}
    end
    fn(doc.data.definitions)
    doc:CompleteChange(description)
end

--- @return table<string, MTGDefinition>
local function Definitions()
    local doc = MTGDefinition.Doc()
    if doc == nil or doc.data == nil then
        return {}
    end
    return doc.data.definitions or {}
end

--- Folders are a Director's filing cabinet and nothing else: no montage
--- behaves differently for being in one, and nothing outside this panel reads
--- them. Single level, sorted by name, and a folder holding montages cannot
--- be deleted.
--- @return {id: string, name: string}[] sorted by name
function MTGDefinition.GetFolders()
    local doc = MTGDefinition.Doc()
    local folders = doc ~= nil and doc.data ~= nil and doc.data.folders or {}

    local result = {}
    for id, folder in pairs(folders) do
        result[#result + 1] = { id = id, name = folder.name or "" }
    end
    table.sort(result, function(a, b)
        local an, bn = string.lower(a.name), string.lower(b.name)
        if an == bn then
            return a.id < b.id
        end
        return an < bn
    end)
    return result
end

--- @param description string
--- @param fn fun(folders: table)
local function MutateFolders(description, fn)
    local doc = MTGDefinition.Doc()
    doc:BeginChange()
    if doc.data.folders == nil then
        doc.data.folders = {}
    end
    fn(doc.data.folders)
    doc:CompleteChange(description)
end

--- @return string id of the new folder
function MTGDefinition.CreateFolder()
    local id = dmhub.GenerateGuid()
    MutateFolders("New montage folder", function(folders)
        folders[id] = { id = id, name = "New Folder" }
    end)
    return id
end

--- @param id string
--- @param name string
function MTGDefinition.RenameFolder(id, name)
    MutateFolders("Rename montage folder", function(folders)
        local folder = folders[id]
        if folder ~= nil and folder.name ~= name then
            folder.name = name
        end
    end)
end

--- Montages in a folder are the reason to keep it, so an occupied folder
--- stays. Emptying it is the Director's decision, not a side effect.
--- @param id string
--- @return boolean whether it went
function MTGDefinition.DeleteFolder(id)
    for _, def in ipairs(MTGDefinition.GetAll()) do
        if def:try_get("folderId", "") == id then
            return false
        end
    end

    MutateFolders("Delete montage folder", function(folders)
        folders[id] = nil
    end)
    return true
end

--- @param defid string
--- @param folderId string empty for the root
function MTGDefinition.SetFolder(defid, folderId)
    MTGDefinition.Mutate("Move montage", function(defs)
        local def = defs[defid]
        if def ~= nil then
            def.folderId = folderId or ""
        end
    end)
end

--- @return MTGDefinition[] sorted by name, then id
function MTGDefinition.GetAll()
    local result = {}
    for id, def in pairs(Definitions()) do
        def.id = id
        result[#result + 1] = def
    end
    table.sort(result, function(a, b)
        local an, bn = string.lower(a.name or ""), string.lower(b.name or "")
        if an == bn then
            return a:GetID() < b:GetID()
        end
        return an < bn
    end)
    return result
end

--- @param id string
--- @return MTGDefinition|nil
function MTGDefinition.GetByID(id)
    if id == nil or id == "" then
        return nil
    end
    return Definitions()[id]
end

--- @param name nil|string
--- @return string id
function MTGDefinition.CreateInLibrary(name)
    local def = MTGDefinition.CreateNew{
        name = name or "New Montage",
        moduleId = MTGConstants.moduleBaseline,
    }
    MTGDefinition.Mutate("Create montage", function(defs)
        defs[def:GetID()] = def
    end)
    return def:GetID()
end

--- @param id string
--- @return string|nil id of the copy
function MTGDefinition.Duplicate(id)
    local source = MTGDefinition.GetByID(id)
    if source == nil then
        return nil
    end
    local copy = DeepCopy(source)
    copy.id = dmhub.GenerateGuid()
    copy.name = string.format("%s (copy)", source.name or "Montage")
    MTGDefinition.Mutate("Duplicate montage", function(defs)
        defs[copy.id] = copy
    end)
    return copy.id
end

--- @param id string
--- @param description string markdown shown to the table while the Run plays
function MTGDefinition.SetDescription(id, description)
    MTGDefinition.Mutate("Describe montage", function(defs)
        local def = defs[id]
        if def ~= nil and def.description ~= description then
            def.description = description
        end
    end)
end

--- @param id string
--- @param name string
function MTGDefinition.Rename(id, name)
    MTGDefinition.Mutate("Rename montage", function(defs)
        local def = defs[id]
        if def ~= nil and def.name ~= name then
            def.name = name
        end
    end)
end

--- @param id string
function MTGDefinition.Delete(id)
    MTGDefinition.Mutate("Delete montage", function(defs)
        defs[id] = nil
    end)
end

--- @param def MTGDefinition
--- @param challengeId string
--- @return MTGChallengeDef|nil challenge
--- @return number|nil index
function MTGDefinition.FindChallenge(def, challengeId)
    for i, ch in ipairs(def:try_get("challenges", {})) do
        if ch.id == challengeId then
            return ch, i
        end
    end
    return nil, nil
end

--- Run fn against one challenge inside a single document change.
--- @param defid string
--- @param challengeId string
--- @param description string
--- @param fn fun(challenge: MTGChallengeDef, def: MTGDefinition)
local function MutateChallenge(defid, challengeId, description, fn)
    MTGDefinition.Mutate(description, function(defs)
        local def = defs[defid]
        if def == nil then
            return
        end
        local ch = MTGDefinition.FindChallenge(def, challengeId)
        if ch ~= nil then
            fn(ch, def)
        end
    end)
end

--- Move one Challenge up or down the authored order.
--- Order IS the array: no field to add, so nothing authored before this can be
--- missing it. Crossing a group boundary adopts the neighbour's grouping rather
--- than refusing the move -- dragging something into Round 2 is taken to mean
--- it belongs to Round 2.
--- @param defid string
--- @param challengeId string
--- @param delta number -1 for up, 1 for down
function MTGDefinition.MoveChallenge(defid, challengeId, delta)
    local step = cond((delta or 0) < 0, -1, 1)

    MTGDefinition.Mutate("Reorder challenge", function(defs)
        local def = defs[defid]
        if def == nil then
            return
        end

        local challenges = def:try_get("challenges")
        if challenges == nil then
            return
        end

        local from = nil
        for i, ch in ipairs(challenges) do
            if ch.id == challengeId then
                from = i
                break
            end
        end

        local to = from ~= nil and from + step or nil
        if from == nil or to == nil or to < 1 or to > #challenges then
            return
        end

        local moving = challenges[from]
        local neighbour = challenges[to]

        --Adopted before the swap, while the neighbour still names the group
        --being moved into.
        moving.availableFromRound = neighbour.availableFromRound or 1
        if def.moduleId == MTGConstants.moduleTO then
            local theirs = neighbour:FieldsFor(MTGConstants.moduleTO).type
            if theirs ~= nil then
                moving:FieldsFor(MTGConstants.moduleTO).type = theirs
            end
        end

        table.remove(challenges, from)
        table.insert(challenges, to, moving)
    end)
end

--- @param defid string
--- @return string|nil id of the new challenge
function MTGDefinition.AddChallenge(defid)
    local ch = MTGChallengeDef.CreateNew{}
    MTGDefinition.Mutate("Add challenge", function(defs)
        local def = defs[defid]
        if def == nil then
            return
        end
        if def:try_get("challenges") == nil then
            def.challenges = {}
        end
        def.challenges[#def.challenges + 1] = ch
    end)
    return ch.id
end

--- Put an already-built Challenge onto a Definition. AddChallenge makes a
--- blank one; this takes a Challenge that was authored somewhere else, which
--- is how a run-time addition earns its place in the saved montage.
--- @param defid string
--- @param ch MTGChallengeDef
function MTGDefinition.AppendChallenge(defid, ch)
    MTGDefinition.Mutate("Add challenge", function(defs)
        local def = defs[defid]
        if def == nil then
            return
        end
        if def:try_get("challenges") == nil then
            def.challenges = {}
        end
        def.challenges[#def.challenges + 1] = ch
    end)
end

--- @param defid string
--- @param challengeId string
function MTGDefinition.RemoveChallenge(defid, challengeId)
    MTGDefinition.Mutate("Remove challenge", function(defs)
        local def = defs[defid]
        if def == nil then
            return
        end
        local _, index = MTGDefinition.FindChallenge(def, challengeId)
        if index ~= nil then
            table.remove(def.challenges, index)
        end
    end)
end

--- @param defid string
--- @param challengeId string
--- @param key string
--- @param value any
function MTGDefinition.SetChallengeField(defid, challengeId, key, value)
    MutateChallenge(defid, challengeId, "Edit challenge", function(ch)
        ch[key] = value
    end)
end

--- @param defid string
--- @param challengeId string
--- @param list string[]
function MTGDefinition.SetChallengeCharacteristics(defid, challengeId, list)
    MutateChallenge(defid, challengeId, "Edit challenge characteristics", function(ch)
        ch.allowedCharacteristics = list
    end)
end

--- @param defid string
--- @param challengeId string
--- @param list string[]
function MTGDefinition.SetChallengeSkills(defid, challengeId, list)
    MutateChallenge(defid, challengeId, "Edit challenge skills", function(ch)
        ch.allowedSkills = list
    end)
end

--- @param defid string
--- @param challengeId string
--- @param moduleId string
--- @param fieldId string
--- @param value any
function MTGDefinition.SetChallengeModuleField(defid, challengeId, moduleId, fieldId, value)
    MutateChallenge(defid, challengeId, "Edit challenge", function(ch)
        ch:FieldsFor(moduleId)[fieldId] = value
    end)
end

--- @param id string
--- @param moduleId string
function MTGDefinition.SetModule(id, moduleId)
    MTGDefinition.Mutate("Change montage rules", function(defs)
        local def = defs[id]
        if def ~= nil then
            def.moduleId = moduleId
        end
    end)
end

--- @param id string
--- @param moduleId string
--- @param fieldId string
--- @param value number
function MTGDefinition.SetSetting(id, moduleId, fieldId, value)
    MTGDefinition.Mutate("Change montage setting", function(defs)
        local def = defs[id]
        if def ~= nil then
            def:SettingsFor(moduleId)[fieldId] = value
        end
    end)
end

--==============================================================================
-- Import
--
-- A montage arrives as JSON: dmhub.FromJson is the only parser Lua can reach.
-- The template is GENERATED from the rules module's own SettingsFields() and
-- ChallengeFields(), so it cannot drift from what the importer accepts and a
-- new module needs no separate registration to be importable.
--==============================================================================

--- @param value any
--- @return string a quoted JSON string
local function JsonString(value)
    local text = tostring(value)
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, '"', '\\"')
    text = string.gsub(text, "\n", "\\n")
    return '"' .. text .. '"'
end

--- @param field table a ChallengeFields()/SettingsFields() entry
--- @return string a JSON scalar
local function FieldExample(field)
    if field.options ~= nil and #field.options > 0 then
        local id = field.options[1].id
        for _, option in ipairs(field.options) do
            if option.id == field.default then
                id = option.id
            end
        end
        return JsonString(id)
    end
    if type(field.default) == "number" then
        return tostring(field.default)
    end
    return JsonString(field.default or "")
end

--- @param field table
--- @return string|nil the legal values, when the field has a closed set
local function FieldNote(field)
    if field.options == nil or #field.options == 0 then
        return nil
    end
    local ids = {}
    for _, option in ipairs(field.options) do
        ids[#ids + 1] = option.id
    end
    return string.format("%s: %s", field.id, table.concat(ids, " | "))
end

--- The JSON a Director can paste, filled in for one rules module.
--- @param moduleId string
--- @return string
function MTGDefinition.BuildImportTemplate(moduleId)
    local rules = MTGRules.GetOrDefault(moduleId)
    local out = {}
    local function Add(line)
        out[#out + 1] = line
    end

    local moduleIds = {}
    for _, option in ipairs(MTGRules.DropdownOptions()) do
        moduleIds[#moduleIds + 1] = option.id
    end

    local notes = {
        "Paste one montage. Keys starting with _ are ignored.",
        string.format("rules: %s", table.concat(moduleIds, " | ")),
        "characteristics and skills: display names or ids. Unknown entries are skipped.",
    }
    for _, field in ipairs(rules.ChallengeFields()) do
        local note = FieldNote(field)
        if note ~= nil then
            notes[#notes + 1] = note
        end
    end

    Add("{")
    Add('  "_readme": [')
    for i, note in ipairs(notes) do
        Add(string.format("    %s%s", JsonString(note), cond(i < #notes, ",", "")))
    end
    Add("  ],")
    Add(string.format('  "name": %s,', JsonString("New Montage")))
    Add(string.format('  "description": %s,', JsonString("")))
    Add(string.format('  "rules": %s,', JsonString(moduleId)))

    Add('  "settings": {')
    local settings = rules.SettingsFields()
    for i, field in ipairs(settings) do
        Add(string.format("    %s: %s%s", JsonString(field.id), FieldExample(field),
            cond(i < #settings, ",", "")))
    end
    Add("  },")

    Add('  "challenges": [')
    Add("    {")
    Add(string.format('      "name": %s,', JsonString("First Challenge")))
    Add(string.format('      "description": %s,', JsonString("")))
    Add('      "availableFromRound": 1,')
    Add('      "repeatable": 0,')
    Add(string.format('      "characteristics": [%s],', JsonString("Might")))
    Add('      "skills": [],')
    local chFields = rules.ChallengeFields()
    for i, field in ipairs(chFields) do
        Add(string.format("      %s: %s%s", JsonString(field.id), FieldExample(field),
            cond(i < #chFields, ",", "")))
    end
    Add("    }")
    Add("  ]")
    Add("}")

    return table.concat(out, "\n")
end

--- "Foo" -> "Foo (2)", "Foo (2)" -> "Foo (3)", the way a file system would.
--- @param name string
--- @return string
local function UniqueName(name)
    local taken = {}
    for _, def in ipairs(MTGDefinition.GetAll()) do
        taken[string.lower(def.name or "")] = true
    end

    if not taken[string.lower(name)] then
        return name
    end

    local base, n = string.match(name, "^(.-)%s*%((%d+)%)$")
    if base == nil then
        base, n = name, 1
    end

    local counter = tonumber(n) or 1
    while true do
        counter = counter + 1
        local candidate = string.format("%s (%d)", base, counter)
        if not taken[string.lower(candidate)] then
            return candidate
        end
    end
end

--- Resolve a list of names-or-ids against the platform's own vocabulary.
--- @param values any what the JSON supplied
--- @param options {id: string, text: string}[]
--- @param label string for the skip message
--- @param messages string[]
--- @return string[]
local function ResolveIds(values, options, label, messages)
    local result = {}
    if type(values) ~= "table" then
        return result
    end

    local byId, byName = {}, {}
    for _, option in ipairs(options) do
        byId[string.lower(option.id)] = option.id
        byName[string.lower(option.text)] = option.id
    end

    for _, value in ipairs(values) do
        local key = string.lower(tostring(value))
        local id = byId[key] or byName[key]
        if id ~= nil then
            result[#result + 1] = id
        else
            messages[#messages + 1] = string.format("Skipped unknown %s \"%s\".", label, tostring(value))
        end
    end
    return result
end

--- Build one challenge from its JSON, or nil when it has nothing usable.
--- @param entry table
--- @param rules table
--- @param moduleId string
--- @param messages string[]
--- @return MTGChallengeDef|nil
local function ImportChallenge(entry, rules, moduleId, messages)
    if type(entry) ~= "table" or type(entry.name) ~= "string" or entry.name == "" then
        messages[#messages + 1] = "Skipped a challenge with no name."
        return nil
    end

    local ch = MTGChallengeDef.CreateNew{
        name = entry.name,
        description = cond(type(entry.description) == "string", entry.description, ""),
        availableFromRound = math.max(1, math.floor(tonumber(entry.availableFromRound) or 1)),
        repeatable = cond(entry.repeatable == true, MTGConstants.repeatMax,
            math.max(0, math.min(MTGConstants.repeatMax,
                math.floor(tonumber(entry.repeatable) or 0)))),
    }

    ch.allowedCharacteristics = ResolveIds(entry.characteristics,
        MTGUtils.CharacteristicOptions(), "characteristic", messages)
    ch.allowedSkills = ResolveIds(entry.skills, MTGUtils.SkillOptions(), "skill", messages)

    for _, field in ipairs(rules.ChallengeFields()) do
        local value = entry[field.id]
        if value ~= nil then
            local accepted = true
            if field.options ~= nil and #field.options > 0 then
                accepted = false
                for _, option in ipairs(field.options) do
                    if string.lower(option.id) == string.lower(tostring(value)) then
                        value = option.id
                        accepted = true
                    end
                end
            end

            if accepted then
                ch:FieldsFor(moduleId)[field.id] = value
            else
                messages[#messages + 1] = string.format(
                    "%s: ignored %s \"%s\".", entry.name, field.id, tostring(value))
            end
        end
    end

    return ch
end

--- Turn pasted JSON into a montage at the root of the library. Nothing that
--- fails stops anything else: a bad challenge costs that challenge, and the
--- montage still lands.
--- @param text string
--- @return {ok: boolean, defid: string|nil, name: string|nil, messages: string[]}
function MTGDefinition.ImportFromJson(text)
    local messages = {}

    if type(text) ~= "string" or trim(text) == "" then
        return { ok = false, messages = { "Nothing to import." } }
    end

    --FromJson reports success even for malformed input, so the shape is what
    --gets checked rather than the flag it hands back.
    local parsed = dmhub.FromJson(text)
    local data = type(parsed) == "table" and parsed.result or nil
    if type(data) ~= "table" then
        return { ok = false, messages = { "That is not valid JSON." } }
    end

    if type(data.name) ~= "string" or trim(data.name) == "" then
        return { ok = false, messages = { "No montage name found. Is this the right JSON?" } }
    end

    local moduleId = cond(type(data.rules) == "string", data.rules, MTGConstants.moduleBaseline)
    if MTGRules.Get(moduleId) == nil then
        return { ok = false, messages = {
            string.format("Unknown rules module \"%s\".", tostring(data.rules)),
        } }
    end
    local rules = MTGRules.GetOrDefault(moduleId)

    local name = UniqueName(trim(data.name))
    if name ~= trim(data.name) then
        messages[#messages + 1] = string.format("Renamed to \"%s\": that name was taken.", name)
    end

    local def = MTGDefinition.CreateNew{
        name = name,
        description = cond(type(data.description) == "string", data.description, ""),
        moduleId = moduleId,
    }

    if type(data.settings) == "table" then
        for _, field in ipairs(rules.SettingsFields()) do
            local value = tonumber(data.settings[field.id])
            if value ~= nil then
                def:SettingsFor(moduleId)[field.id] = value
            end
        end
    end

    local challenges = {}
    if type(data.challenges) == "table" then
        for _, entry in ipairs(data.challenges) do
            local ch = ImportChallenge(entry, rules, moduleId, messages)
            if ch ~= nil then
                challenges[#challenges + 1] = ch
            end
        end
    end
    def.challenges = challenges

    if #challenges == 0 then
        messages[#messages + 1] = "No challenges imported."
    end

    MTGDefinition.Mutate("Import montage", function(defs)
        defs[def:GetID()] = def
    end)

    return { ok = true, defid = def:GetID(), name = name, messages = messages }
end

