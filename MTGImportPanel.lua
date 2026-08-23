local mod = dmhub.GetModLoading()

--- Paste a montage in as JSON. Takes over the right pane rather than opening
--- a dialog of its own.
MTGImportPanel = {}

--- @param onDone fun(defid: string|nil) selects what arrived, or clears
--- @return Panel
function MTGImportPanel.Create(onDone)
    local m_moduleId = MTGConstants.moduleBaseline

    local titleLabel = gui.Label{
        classes = { "modalTitle", "sizeL" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        text = "Import a Montage",
    }

    local blurbLabel = gui.Label{
        classes = { "sizeS", "noBold", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 2,
        textWrap = true,
        text = "Paste JSON below, or copy a template to fill in. Anything that "
            .. "cannot be read is skipped and the rest still imports.",
    }

    local resultLabel = gui.Label{
        classes = { "sizeS", "noBold", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 4,
        textWrap = true,
        markdown = true,
        text = "",
    }

    local importButton

    local jsonInput = gui.Input{
        classes = { "formStacked", "sizeS" },
        width = "98%",
        height = "100% available",
        multiline = true,
        textAlignment = "topLeft",
        characterLimit = 60000,
        placeholderText = "Paste montage JSON here",
        text = "",
        edit = function(element)
            importButton:SetClass("hidden", trim(element.text or "") == "")
        end,
        change = function(element)
            importButton:SetClass("hidden", trim(element.text or "") == "")
        end,
    }

    local templateDropdown = gui.Dropdown{
        classes = { "formStacked", "sizeS" },
        width = 160,
        halign = "left",
        valign = "center",
        rmargin = 8,
        options = MTGRules.DropdownOptions(),
        idChosen = m_moduleId,
        change = function(element)
            m_moduleId = element.idChosen
        end,
    }

    local copyButton = gui.Button{
        classes = { "sizeS" },
        width = 150,
        text = "Copy Template",
        halign = "left",
        valign = "center",
        rmargin = 8,
        hover = gui.Tooltip("Put a filled-in template on the clipboard"),
        click = function()
            dmhub.CopyToClipboard(MTGDefinition.BuildImportTemplate(m_moduleId))
            resultLabel:SetClass("collapsed", false)
            resultLabel.text = string.format("Template for **%s** copied to the clipboard.",
                MTGRules.Name(m_moduleId))
        end,
    }

    importButton = gui.Button{
        classes = { "sizeS", "hidden" },
        width = 110,
        text = "Import",
        halign = "right",
        valign = "center",
        click = function()
            local result = MTGDefinition.ImportFromJson(jsonInput.text)

            local lines = {}
            if result.ok then
                lines[#lines + 1] = string.format("Imported **%s**.", result.name or "")
            end
            for _, message in ipairs(result.messages or {}) do
                lines[#lines + 1] = string.format("- %s", message)
            end

            resultLabel:SetClass("collapsed", false)
            resultLabel.text = table.concat(lines, "\n")

            if result.ok then
                jsonInput.text = ""
                importButton:SetClass("hidden", true)
                onDone(result.defid)
            end
        end,
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "100% available",
        flow = "vertical",
        valign = "top",

        --Reset every time this pane is shown: a stale paste from last time is
        --never what the Director means to import.
        reset = function()
            jsonInput.text = ""
            importButton:SetClass("hidden", true)
            resultLabel:SetClass("collapsed", true)
        end,

        titleLabel,
        blurbLabel,
        resultLabel,

        jsonInput,

        gui.Panel{
            width = "100%",
            height = 40,
            flow = "horizontal",
            valign = "bottom",
            tmargin = 8,

            templateDropdown,
            copyButton,

            gui.Button{
                classes = { "sizeS" },
                width = 110,
                text = "Cancel",
                halign = "right",
                valign = "center",
                rmargin = 8,
                click = function()
                    onDone(nil)
                end,
            },

            importButton,
        },
    }

    return resultPanel
end
