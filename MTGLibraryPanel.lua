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

--- The play button's face for one montage: what it shows and whether it
--- takes a press. Exactly one Run exists at a time, so a montage is either
--- the one running or it is locked out until that Run finishes.
--- @param defid string
--- @return {icon: string, tooltip: string, interactable: boolean}
local function PlayFace(defid)
    local running = MTGRun.ActiveFor(defid)
    local otherRunning = nil
    if running == nil and MTGRun.Active() ~= nil then
        otherRunning = MTGRun.Active()
    end

    local tooltip = "Run this montage"
    if otherRunning ~= nil then
        tooltip = string.format("%s is running. Finish or cancel it first.", otherRunning.name or "A montage")
    elseif running ~= nil and running.status == MTGConstants.statusRunning then
        tooltip = cond(running.paused == true, "Resume this montage", "Pause this montage")
    elseif running ~= nil then
        tooltip = "Setting up"
    end

    return {
        icon = cond(running ~= nil and running.paused ~= true, ICON_PAUSE, ICON_PLAY),
        tooltip = tooltip,
        interactable = otherRunning == nil,
    }
end

--- A montage's row. Built once and handed a montage with `setMontage`;
--- handed nil, it collapses and waits. Stripe and selection are classes the
--- bind toggles.
--- @param onSelect fun(defid: string)
--- @param indent number
--- @return Panel
local function CreateRow(onSelect, indent)
    --- @type {defid: string|nil, name: string|nil, moduleId: string|nil, playIcon: string|nil, playTip: string|nil}
    local bound = {}

    local nameLabel = gui.Label{
        classes = { "sizeS" },
        width = "100% available",
        height = "auto",
        lmargin = 8,
        halign = "left",
        valign = "center",
        text = "",
    }

    local rulesIcon = gui.Panel{
        classes = { "bgFg" },
        width = 20,
        height = 20,
        halign = "left",
        valign = "center",
        bgimage = ICON_BASELINE,
    }

    local playButton = gui.Button{
        classes = { "sizeXs" },
        icon = ICON_PLAY,
        halign = "right",
        valign = "center",
        hmargin = 2,
        click = function(element)
            onSelect(bound.defid)
            --Read live: the button outlives the refresh that dressed it.
            local running = MTGRun.ActiveFor(bound.defid)
            if running == nil then
                MTGRun.BeginSetup(bound.defid)
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
    }

    return gui.Panel{
        classes = { "row", "hoverable" },
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
                MTGDefinition.SetFolder(bound.defid, target.data.folderId or "")
            end
        end,

        click = function()
            onSelect(bound.defid)
        end,

        --- @param item nil|{def: MTGDefinition, index: number, selected: boolean}
        setMontage = function(element, item)
            element:SetClass("collapsed", item == nil)
            if item == nil then
                return
            end

            local def = item.def
            bound.defid = def:GetID()

            element:SetClass("oddRow", item.index % 2 == 1)
            element:SetClass("evenRow", item.index % 2 == 0)
            element:SetClass("selected", item.selected)

            local name = def.name or ""
            if bound.name ~= name then
                bound.name = name
                nameLabel.text = name
            end

            if bound.moduleId ~= def.moduleId then
                bound.moduleId = def.moduleId
                rulesIcon.bgimage = RulesIcon(def.moduleId)
                rulesIcon.tooltip = gui.Tooltip(MTGRules.Name(def.moduleId))
            end

            local face = PlayFace(bound.defid)
            if bound.playIcon ~= face.icon then
                bound.playIcon = face.icon
                playButton:FireEvent("setIcon", face.icon)
            end
            if bound.playTip ~= face.tooltip then
                bound.playTip = face.tooltip
                playButton.tooltip = gui.Tooltip(face.tooltip)
            end
            if playButton.interactable ~= face.interactable then
                playButton.interactable = face.interactable
            end
        end,

        nameLabel,
        rulesIcon,

        gui.Panel{
            width = "auto",
            height = "100%",
            flow = "horizontal",
            halign = "right",
            valign = "center",

            playButton,

            gui.Button{
                classes = { "sizeXs" },
                icon = ICON_GEAR,
                halign = "right",
                valign = "center",
                hmargin = 2,
                hover = gui.Tooltip("More"),
                click = function(element)
                    local defid = bound.defid
                    element.popup = gui.ContextMenu{
                        entries = {
                            {
                                text = "Copy Slug",
                                click = function()
                                    element.popup = nil
                                    dmhub.CopyToClipboard(MTGDefinition.EnsureSlug(defid))
                                end,
                            },
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

--- Collapse is a view preference, so it lives per client rather than in the
--- shared document where it would follow everyone around.
--- @param folderId string
--- @return string
local function FoldPrefKey(folderId)
    return string.format("mtgfolder:%s:%s", dmhub.gameid, folderId)
end

--- A folder: its header, with its name, how many montages it holds and the
--- drop target that files them into it, over the rows of those montages.
--- Built once and handed a folder with `setFolder`; handed nil, it collapses.
--- @param onSelect fun(defid: string)
--- @param onRebuild fun()
--- @return Panel
local function CreateFolderBlock(onSelect, onRebuild)
    --- @type {folderId: string|nil, label: string|nil, count: string|nil}
    local bound = {}

    local rows = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    --No classes key: an empty list wipes ExpandoArrow's own theme classes.
    local arrow = gui.ExpandoArrow{
        bgimage = CARET,
        width = 14,
        height = 14,
        halign = "left",
        valign = "center",
        lmargin = 4,
        click = function(element)
            local nowExpanded = not element:HasClass("expanded")
            element:SetClass("expanded", nowExpanded)
            dmhub.SetPref(FoldPrefKey(bound.folderId), not nowExpanded)
            onRebuild()
        end,
    }

    local nameLabel = gui.Label{
        classes = { "tableLabel", "sizeXs" },
        width = "70%",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 4,
        editable = true,
        characterLimit = 32,
        text = "",
        change = function(element)
            local name = trim(element.text or "")
            if name == "" then
                element.text = bound.label or ""
                return
            end
            MTGDefinition.RenameFolder(bound.folderId, name)
        end,
    }

    local countLabel = gui.Label{
        classes = { "sizeXs", "noBold", "fgMuted" },
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        rmargin = 8,
        text = "",
    }

    local header = gui.Panel{
        classes = { DROP_CLASS },
        width = "100%",
        height = 26,
        flow = "horizontal",
        valign = "top",
        tmargin = 6,
        bgimage = "panels/square.png",
        dragTarget = true,

        data = { folderId = "" },

        rightClick = function(element)
            element.popup = gui.ContextMenu{
                entries = {
                    {
                        text = "Delete Folder",
                        click = function()
                            element.popup = nil
                            MTGDefinition.DeleteFolder(bound.folderId)
                        end,
                    },
                },
            }
        end,

        arrow,
        nameLabel,
        countLabel,
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        --- @param entry nil|{folder: {id: string, name: string}, items: table[], closed: boolean}
        setFolder = function(element, entry)
            element:SetClass("collapsed", entry == nil)
            if entry == nil then
                return
            end

            bound.folderId = entry.folder.id
            header.data.folderId = entry.folder.id

            if bound.label ~= entry.folder.name then
                bound.label = entry.folder.name
                nameLabel.text = entry.folder.name
            end
            local count = tostring(#entry.items)
            if bound.count ~= count then
                bound.count = count
                countLabel.text = count
            end

            arrow:SetClass("expanded", not entry.closed)
            rows:SetClass("collapsed", entry.closed)
            MTGWidgets.BindList(rows, entry.items, function()
                return CreateRow(onSelect, 16)
            end, "setMontage")
        end,

        header,
        rows,
    }
end

--- The list half of the montage form.
--- @param onSelect fun(defid: string|nil)
--- @param onImport fun()
--- @return Panel
function MTGLibraryPanel.Create(onSelect, onImport)
    local m_selected = nil

    local rootRows = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    local folderBlocks = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    local listPanel = gui.Panel{
        classes = { "bordered" },
        pad = 4,
        width = "98%-6",
        height = "98%",
        flow = "vertical",
        valign = "top",
        vscroll = true,

        CreateRootDropRow(),
        rootRows,
        folderBlocks,
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

            --Only visible rows take a stripe; folded ones stay bound for the unfold.
            local index = 0
            local function Items(bucket, visible)
                local items = {}
                for _, def in ipairs(bucket or {}) do
                    if visible then
                        index = index + 1
                    end
                    items[#items + 1] = {
                        def = def,
                        index = index,
                        selected = def:GetID() == m_selected,
                    }
                end
                return items
            end

            MTGWidgets.BindList(rootRows, Items(byFolder[""], true), function()
                return CreateRow(Select, 0)
            end, "setMontage")

            local folders = {}
            for _, folder in ipairs(MTGDefinition.GetFolders()) do
                local closed = dmhub.GetPref(FoldPrefKey(folder.id)) == true
                folders[#folders + 1] = {
                    folder = folder,
                    closed = closed,
                    items = Items(byFolder[folder.id], not closed),
                }
            end
            MTGWidgets.BindList(folderBlocks, folders, function()
                return CreateFolderBlock(Select, Rebuild)
            end, "setFolder")

            emptyLabel:SetClass("collapsed", #defs > 0)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        --A panel monitors one path; rows need the Run's too.
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
