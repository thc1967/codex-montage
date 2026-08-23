local mod = dmhub.GetModLoading()

--- Shared helpers over the platform's own data.
MTGUtils = {}

--- Characteristics in the order the game defines them.
--- @return {id: string, text: string}[]
function MTGUtils.CharacteristicOptions()
    local options = {}
    for _, id in ipairs(creature.attributeIds) do
        local info = creature.attributesInfo[id]
        options[#options + 1] = { id = id, text = info ~= nil and info.description or id }
    end
    return options
end

--- @param id string
--- @return string
function MTGUtils.CharacteristicName(id)
    local info = creature.attributesInfo[id]
    return info ~= nil and info.description or tostring(id)
end

--- Every skill, sorted by name. gui.Multiselect keeps this order and searches
--- it, so the sort here is the sort the Director sees.
--- @return {id: string, text: string}[]
function MTGUtils.SkillOptions()
    local options = {}
    for _, skill in ipairs(Skill.SkillsInfo) do
        options[#options + 1] = { id = skill.id, text = skill.name }
    end
    table.sort(options, function(a, b)
        return string.lower(a.text) < string.lower(b.text)
    end)
    return options
end

--- @param id string
--- @return string
function MTGUtils.SkillName(id)
    local skill = Skill.SkillsById ~= nil and Skill.SkillsById[id] or nil
    if skill ~= nil then
        return skill.name
    end
    local skillsTable = dmhub.GetTable(Skill.tableName) or {}
    local entry = skillsTable[id]
    return entry ~= nil and entry.name or tostring(id)
end

--- The skills this creature actually has, sorted by name.
--- @param charid string
--- @return {id: string, text: string}[]
function MTGUtils.SkillOptionsFor(charid)
    local token = dmhub.GetCharacterById(charid)
    if token == nil or token.properties == nil then
        return {}
    end

    local options = {}
    for _, skill in ipairs(Skill.SkillsInfo) do
        if token.properties:ProficientInSkill(skill) then
            options[#options + 1] = { id = skill.id, text = skill.name }
        end
    end
    table.sort(options, function(a, b)
        return string.lower(a.text) < string.lower(b.text)
    end)
    return options
end

--- This creature's modifier for a characteristic, or nil when it has none.
--- @param charid string
--- @param attrId string
--- @return number|nil
function MTGUtils.CharacteristicModifier(charid, attrId)
    local token = dmhub.GetCharacterById(charid)
    if token == nil or token.properties == nil then
        return nil
    end
    local modifier = nil
    pcall(function()
        modifier = token.properties:GetAttribute(attrId):Modifier()
    end)
    return modifier
end

--- @param modifier number|nil
--- @return string
function MTGUtils.SignedModifier(modifier)
    if modifier == nil then
        return ""
    end
    return string.format("%s%d", modifier >= 0 and "+" or "", modifier)
end

--- Turn an ordered array into the set gui.Multiselect expects.
--- @param list string[]
--- @return table<string, boolean>
function MTGUtils.ToSet(list)
    local set = {}
    for _, id in ipairs(list or {}) do
        set[id] = true
    end
    return set
end

--- Fold a multiselect's set back into an ordered array, keeping entries that
--- were already chosen in their existing positions and appending the rest in
--- the order `ordering` lists them.
--- @param set table<string, boolean>
--- @param existing string[]
--- @param ordering {id: string}[]
--- @return string[]
function MTGUtils.MergeOrdered(set, existing, ordering)
    local result = {}
    local seen = {}

    for _, id in ipairs(existing or {}) do
        if set[id] and not seen[id] then
            result[#result + 1] = id
            seen[id] = true
        end
    end

    for _, option in ipairs(ordering or {}) do
        if set[option.id] and not seen[option.id] then
            result[#result + 1] = option.id
            seen[option.id] = true
        end
    end

    return result
end

--- @param ids string[]
--- @param nameFn fun(id: string): string
--- @param emptyText string
--- @return string
function MTGUtils.NameList(ids, nameFn, emptyText)
    if ids == nil or #ids == 0 then
        return emptyText
    end
    local names = {}
    for _, id in ipairs(ids) do
        names[#names + 1] = nameFn(id)
    end
    return table.concat(names, ", ")
end
