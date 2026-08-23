local mod = dmhub.GetModLoading()

--- Registry of rules modules. A module supplies the behaviour that differs
--- between ways of running a montage; anything it does not supply falls
--- through to the module it inherits from.
MTGRules = {}

MTGRules.modules = {}

local g_resolved = {}

--- @param def table id, name, and any behaviour this module overrides. Set
---            `inherits` to the id of the module to fall through to; omit it
---            on the root module.
function MTGRules.Register(def)
    MTGRules.modules[def.id] = def
    g_resolved = {}
end

--- @param id string
--- @return table|nil
function MTGRules.Get(id)
    local def = MTGRules.modules[id]
    if def == nil then
        return nil
    end
    if g_resolved[id] then
        return def
    end

    local parentId = def.inherits
    if parentId ~= nil and parentId ~= def.id then
        local parent = MTGRules.Get(parentId)
        if parent ~= nil then
            setmetatable(def, { __index = parent })
        end
    end

    g_resolved[id] = true
    return def
end

--- @param id string
--- @return table the requested module, or the baseline module
function MTGRules.GetOrDefault(id)
    return MTGRules.Get(id) or MTGRules.Get(MTGConstants.moduleBaseline)
end

--- @return {id: string, text: string}[] every registered module, for a picker
function MTGRules.DropdownOptions()
    local options = {}
    for id, def in pairs(MTGRules.modules) do
        options[#options + 1] = { id = id, text = def.name or id }
    end
    table.sort(options, function(a, b)
        return a.text < b.text
    end)
    return options
end

--- @param moduleId string
--- @return string
function MTGRules.Name(moduleId)
    local def = MTGRules.Get(moduleId)
    return def ~= nil and def.name or moduleId
end
