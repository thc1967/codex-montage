local mod = dmhub.GetModLoading()

--- The list of prepared montages, down the left of the montage form.
MTGLibraryPanel = {}

local ICON_BASELINE = "phosphor/book-open-fill.png"
local ICON_CUSTOM = "phosphor/wrench-bold.png"
local ICON_PLAY = "phosphor/play-fill.png"
local ICON_PAUSE = "phosphor/pause-fill.png"
local ICON_GEAR = "phosphor/gear-six-fill.png"
local ICON_NEW_FOLDER = "phosphor/folder-plus.png"
local ICON_IMPORT = "phosphor/upload-simple-bold.png"
local CARET = "phosphor/caret-down-fill.png"

--- Rows and headers advertise themselves with one class; the theme already
--- paints "drag-target-hover" with an accent border and fill, so a drop
--- target lights up without any styling here.
local DROP_CLASS = "mtgDropTarget"

--- @param moduleId string
--- @return string
local function RulesIcon(moduleId)
    if moduleId == MTGConstants.moduleBaseline then
        return ICON_BASELINE
    end
    return ICON_CUSTOM
end

--- @param def MTGDefinition
--- @param index number
--- @param selectedId string|nil
--- @param onSelect fun(defid: string)
--- @return Panel
local function CreateRow(def, index, selectedId, onSelect, indent)
    local defid = def:GetID()

    --Exactly one Run exists at a time, so a montage is either the one running
    --or it is locked out until that Run finishes.
    local running = MTGRun.ActiveFor(defid)
    local otherRunning = nil
    if running == nil and MTGRun.Active() ~= nil then
        otherRunning = MTGRun.Active()
    end

    local playTooltip = "Run this montage"
    if otherRunning ~= nil then
        playTooltip = string.format("%s is running. Finish or cancel it first.", otherRunning.name or "A montage")
    elseif running ~= nil and running.status == MTGConstants.statusRunning then
        playTooltip = cond(running.paused == true, "Resume this montage", "Pause this montage")
    elseif running ~= nil then
        playTooltip = "Setting up"
    end

    return gui.Panel{
        classes = {
            "row",
            "hoverable",
            cond(index % 2 == 1, "oddRow", "evenRow"),
            cond(defid == selectedId, "selected"),
        },
        width = cond(indent > 0, string.format("100%%-%d", indent), "100%"),
        height = 32,
        flow = "horizontal",
        halign = "right",
        valign = "top",

        draggable = true,
        canDragOnto = function(element, target)
            return target ~= nil and target:HasClass(DROP_CLASS)
        end,

        beginDrag = function(element)
            local controller = element:FindParentWithClass("mtgLibrary")
            if controller ~= nil then
                controller:FireEventTree("setDragging", true)
            end
        end,

        drag = function(element, target)
            local controller = element:FindParentWithClass("mtgLibrary")
            if controller ~= nil then
                controller:FireEventTree("setDragging", false)
            end
            if target ~= nil then
                MTGDefinition.SetFolder(defid, target.data.folderId or "")
            end
        end,

        click = function()
            onSelect(defid)
        end,

        gui.Label{
            classes = { "sizeS" },
            width = "56%",
            height = "auto",
            lmargin = 8,
            halign = "left",
            valign = "center",
            text = def.name or "",
        },

        gui.Panel{
            classes = { "bgFg" },
            width = 20,
            height = 20,
            halign = "left",
            valign = "center",
            bgimage = RulesIcon(def.moduleId),
            hover = gui.Tooltip(MTGRules.Name(def.moduleId)),
        },

        gui.Panel{
            width = "26%",
            height = "100%",
            flow = "horizontal",
            halign = "right",
            valign = "center",

            gui.Button{
                classes = { "sizeXs" },
                icon = cond(running ~= nil and running.paused ~= true, ICON_PAUSE, ICON_PLAY),
                halign = "right",
                valign = "center",
                hmargin = 2,
                interactable = otherRunning == nil,
                hover = gui.Tooltip(playTooltip),
                click = function(element)
                    onSelect(defid)
                    if running == nil then
                        MTGRun.BeginSetup(defid)
                    elseif running.status == MTGConstants.statusRunning then
                        local paused = running.paused ~= true
                        MTGRun.SetPaused(paused)
                        if paused then
                            MTGRun.HideFromPlayers()
                        else
                            MTGRun.PresentToPlayers(element)
                        end
                    end
                end,
            },

            gui.Button{
                classes = { "sizeXs" },
                icon = ICON_GEAR,
                halign = "right",
                valign = "center",
                hmargin = 2,
                hover = gui.Tooltip("More"),
                click = function(element)
                    element.popup = gui.ContextMenu{
                        entries = {
                            {
                                text = "Duplicate",
                                click = function()
                                    element.popup = nil
                                    MTGDefinition.Duplicate(defid)
                                end,
                            },
                            {
                                text = "Delete",
                                click = function()
                                    element.popup = nil
                                    MTGDefinition.Delete(defid)
                                end,
                            },
                        },
                    }
                end,
            },
        },
    }
end

--- Somewhere to drop a montage that should leave its folder. Collapsed until
--- a drag begins, so it costs nothing and shows nothing the rest of the time.
--- @return Panel
local function CreateRootDropRow()
    return gui.Panel{
        classes = { DROP_CLASS, "bordered", "collapsed" },
        width = "100%",
        height = 22,
        flow = "horizontal",
        valign = "top",
        vmargin = 3,
        bgimage = "panels/square.png",
        dragTarget = true,

        data = { folderId = "" },

        setDragging = function(element, dragging)
            element:SetClass("collapsed", not dragging)
        end,

        gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "center",
            textAlignment = "center",
            text = "(root)",
        },
    }
end

--- A folder's header: its name, how many montages it holds, and the drop
--- target that files them into it.
--- @param folderId string
--- @param label string
--- @param onRebuild fun()
--- @param count number
--- @return Panel
local function CreateFolderHeader(folderId, label, onRebuild, count)
    --Collapse is a view preference, so it lives per client rather than in the
    --shared document where it would follow everyone around.
    local prefKey = string.format("mtgfolder:%s:%s", dmhub.gameid, folderId)
    local closed = dmhub.GetPref(prefKey) == true

    local arrowArgs = {
        bgimage = CARET,
        width = 14,
        height = 14,
        halign = "left",
        valign = "center",
        lmargin = 4,
    }
    if not closed then
        arrowArgs.classes = { "expanded" }
    end
    arrowArgs.click = function(element)
        local nowExpanded = not element:HasClass("expanded")
        element:SetClass("expanded", nowExpanded)
        dmhub.SetPref(prefKey, not nowExpanded)
        onRebuild()
    end

    local children = {
        gui.ExpandoArrow(arrowArgs),
    }

    children[#children + 1] = gui.Label{
        classes = { "tableLabel", "sizeXs" },
        width = "70%",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 4,
        editable = true,
        characterLimit = 32,
        text = label,
        change = function(element)
            local name = trim(element.text or "")
            if name == "" then
                element.text = label
                return
            end
            MTGDefinition.RenameFolder(folderId, name)
        end,
    }

    children[#children + 1] = gui.Label{
        classes = { "sizeXs", "noBold", "fgMuted" },
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        rmargin = 8,
        text = tostring(count),
    }

    return gui.Panel{
        classes = { DROP_CLASS },
        width = "100%",
        height = 26,
        flow = "horizontal",
        valign = "top",
        tmargin = 6,
        bgimage = "panels/square.png",
        dragTarget = true,

        data = { folderId = folderId },

        rightClick = function(element)
            element.popup = gui.ContextMenu{
                entries = {
                    {
                        text = "Delete Folder",
                        click = function()
                            element.popup = nil
                            MTGDefinition.DeleteFolder(folderId)
                        end,
                    },
                },
            }
        end,

        children = children,
    }
end

--- The list half of the montage form.
--- @param onSelect fun(defid: string|nil)
--- @param onImport fun()
--- @return Panel
function MTGLibraryPanel.Create(onSelect, onImport)
    local m_selected = nil

    local listPanel = gui.Panel{
        classes = { "bordered" },
        pad = 4,
        width = "98%-6",
        height = "98%",
        flow = "vertical",
        valign = "top",
        vscroll = true,
    }

    local emptyLabel = gui.Label{
        classes = { "sizeS", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "center",
        vmargin = 16,
        textAlignment = "center",
        text = "No montages yet.",
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        valign = "top",

        monitorGame = MTGDefinition.DocPath(),
        refreshGame = function(element)
            element:FireEvent("rebuild")
        end,

        --- Select a montage and tell the editor about it.
        select = function(element, defid)
            m_selected = defid
            onSelect(defid)
            element:FireEvent("rebuild")
        end,

        rebuild = function(element)
            local defs = MTGDefinition.GetAll()

            --The selection can vanish under us when a montage is deleted here
            --or on another client.
            if m_selected ~= nil and MTGDefinition.GetByID(m_selected) == nil then
                m_selected = nil
                onSelect(nil)
            end

            local function Select(defid)
                element:FireEvent("select", defid)
            end
            local function Rebuild()
                element:FireEvent("rebuild")
            end

            local byFolder = {}
            for _, def in ipairs(defs) do
                local key = def:try_get("folderId", "")
                byFolder[key] = byFolder[key] or {}
                local bucket = byFolder[key]
                bucket[#bucket + 1] = def
            end

            local children = {}
            local index = 0

            local function AddRows(bucket, indent)
                for _, def in ipairs(bucket or {}) do
                    index = index + 1
                    children[#children + 1] = CreateRow(def, index, m_selected, Select, indent)
                end
            end

            children[#children + 1] = CreateRootDropRow()
            AddRows(byFolder[""], 0)

            for _, folder in ipairs(MTGDefinition.GetFolders()) do
                local bucket = byFolder[folder.id] or {}
                children[#children + 1] =
                    CreateFolderHeader(folder.id, folder.name, Rebuild, #bucket)

                local prefKey = string.format("mtgfolder:%s:%s", dmhub.gameid, folder.id)
                if dmhub.GetPref(prefKey) ~= true then
                    AddRows(bucket, 16)
                end
            end

            listPanel.children = children
            emptyLabel:SetClass("collapsed", #defs > 0)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        --Rows show run state as well as definition state, and a panel can
        --only monitor one path.
        gui.Panel{
            width = 0,
            height = 0,
            monitorGame = MTGRun.DocPath(),
            refreshGame = function(element)
                local controller = element:FindParentWithClass("mtgLibrary")
                if controller ~= nil then
                    controller:FireEvent("rebuild")
                end
            end,
        },

        gui.Panel{
            width = "100%",
            height = "100%-44",
            flow = "vertical",
            valign = "top",
            vscroll = true,

            listPanel,
            emptyLabel,
        },

        gui.Panel{
            width = "100%",
            height = 40,
            flow = "horizontal",
            valign = "bottom",

            gui.Button{
                classes = { "sizeS" },
                icon = ICON_IMPORT,
                width = 26,
                height = 26,
                halign = "right",
                valign = "center",
                hmargin = 4,
                hover = gui.Tooltip("Import a montage"),
                click = function()
                    onImport()
                end,
            },

            gui.Button{
                classes = { "sizeS" },
                icon = ICON_NEW_FOLDER,
                width = 26,
                height = 26,
                halign = "right",
                valign = "center",
                hmargin = 4,
                hover = gui.Tooltip("New folder"),
                click = function()
                    MTGDefinition.CreateFolder()
                end,
            },

            gui.Button{
                classes = { "addButton", "sizeS" },
                halign = "right",
                valign = "center",
                hover = gui.Tooltip("Prepare a new montage"),
                click = function(element)
                    local defid = MTGDefinition.CreateInLibrary()
                    local controller = element:FindParentWithClass("mtgLibrary")
                    if controller ~= nil then
                        controller:FireEvent("select", defid)
                    end
                end,
            },
        },
    }

    resultPanel:SetClass("mtgLibrary", true)

    return resultPanel
end
