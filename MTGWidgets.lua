local mod = dmhub.GetModLoading()

--- Small pieces shared by the montage surfaces.
MTGWidgets = {}

--- Maps a module-supplied tone onto the theme's status classes.
--- @param tone string|nil
--- @return string
function MTGWidgets.ToneClass(tone)
    if tone == "success" then
        return "bgSuccess"
    end
    if tone == "danger" then
        return "bgDanger"
    end
    if tone == "warning" then
        return "bgWarning"
    end
    if tone == "info" then
        return "bgInfo"
    end
    return "bgFg"
end

--- @param text string
--- @return Panel
function MTGWidgets.SubHeader(text)
    return gui.Label{
        classes = { "tableLabel", "sizeXs" },
        width = "100%",
        height = "auto",
        valign = "top",
        tmargin = 8,
        text = text,
    }
end

--- A participant token that can be dragged onto a slot. The drag props have
--- to live on a panel we build: gui.CreateTokenImage makes its own panel and
--- does not forward them, so the image goes inside as a child.
--- @param p MTGParticipant
--- @param draggable boolean
--- @param rightClick fun(element: Panel)|nil
--- @param dimmed nil|boolean the theme's disabled idiom, which is desaturation
--- @return Panel|nil
function MTGWidgets.ParticipantToken(p, draggable, rightClick, dimmed)
    local token = dmhub.GetCharacterById(p.charid)
    if token == nil then
        return nil
    end

    local mine = MTGRun.CanManage(p.charid)

    local image = gui.CreateTokenImage(token, {
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
    })

    --The portrait and its frame are separate child panels, so desaturating
    --only what CreateTokenImage returns leaves them untouched.
    if dimmed == true then
        image.selfStyle.saturation = 0
        for _, child in ipairs(image.children or {}) do
            child.selfStyle.saturation = 0
        end
    end

    return gui.Panel{
        rightClick = cond(mine, rightClick),

        classes = { "mtgToken" },
        width = 40,
        height = 40,
        halign = "left",
        valign = "center",
        hmargin = 2,
        bgimage = true,
        bgcolor = "clear",
        draggable = draggable and mine,

        canDragOnto = function(element, target)
            return target:HasClass("mtgSlot") or target:HasClass("mtgTray")
        end,

        drag = function(element, target)
            if target == nil then
                return
            end
            print("THC:: montage drop " .. tostring(p.name) .. " onto " ..
                cond(target:HasClass("mtgTray"), "tray", "slot"))
            if target:HasClass("mtgTray") then
                target:FireEvent("dropToTray", p.charid)
            else
                target:FireEvent("dropOnSlot", p.charid)
            end
        end,

        hover = gui.Tooltip(p.name or ""),

        data = { charid = p.charid },

        image,
    }
end

--- A hero's card in the closing report: their portrait over what they did.
--- No local styles table: one here would shadow the inherited ThemeEngine
--- cascade for the whole card, and every class below would stop resolving.
--- @param row table a MTGRun.BuildRecap entry
--- @param lines string[]
--- @return Panel
function MTGWidgets.RecapCard(row, lines)
    local token = dmhub.GetCharacterById(row.charid)

    --"image" keeps the portrait true-colour: the {panel} base tints a bare
    --bgimage with @bg.
    local portraitPanel = gui.Panel{
        classes = { "image", "borderInfo" },
        interactable = false,
        flow = "none",
        width = "100%",
        height = "133.333% width",
        halign = "center",
        valign = "top",
        borderWidth = 2,
        cornerRadius = 4,
    }

    if token ~= nil then
        local portrait = token.inspectPortrait
        portraitPanel.bgimage = portrait
        if token.hasSpineAnimation then
            portraitPanel.selfStyle.imageRect = nil
        else
            portraitPanel.selfStyle.imageRect = token:GetPortraitRectForAspect(0.75, portrait)
        end
    end

    local children = {
        portraitPanel,

        gui.Label{
            classes = { "sizeL" },
            interactable = false,
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "top",
            tmargin = 6,
            textAlignment = "center",
            textWrap = true,
            text = row.name or "",
        },
    }

    for _, line in ipairs(lines) do
        children[#children + 1] = gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            interactable = false,
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "top",
            tmargin = 2,
            textAlignment = "center",
            textWrap = true,
            text = line,
        }
    end

    return gui.Panel{
        classes = { "panel", "surfaceRadial", "border" },
        interactable = false,
        flow = "vertical",
        width = 168,
        height = "auto",
        minHeight = 300,
        halign = "left",
        valign = "top",
        margin = 8,
        cornerRadius = 8,
        borderWidth = 1,
        vpad = 10,
        hpad = 8,
        children = children,
    }
end

--- The round's free participant tokens. One token per participant per round:
--- it is here, or in a Lead slot, or in an Assist slot.
--- @param participants MTGParticipant[]
--- @param onReturn fun(charid: string)
--- @return Panel
function MTGWidgets.Tray(participants, onReturn)
    local children = {}
    for _, p in ipairs(participants) do
        local token = MTGWidgets.ParticipantToken(p, true)
        if token ~= nil then
            children[#children + 1] = token
        end
    end

    if #children == 0 then
        children[#children + 1] = gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "center",
            textAlignment = "center",
            text = "All Heroes assigned",
        }
    end

    return gui.Panel{
        classes = { "bordered", "mtgTray" },
        width = "98%",
        height = 52,
        flow = "horizontal",
        halign = "left",
        valign = "top",
        pad = 4,
        vmargin = 4,
        dragTarget = true,

        dropToTray = function(element, charid)
            onReturn(charid)
        end,

        children = children,
    }
end

--- Border companion to ToneClass, so an empty bar still reads as its colour.
--- @param tone string|nil
--- @return string
function MTGWidgets.ToneBorderClass(tone)
    if tone == "success" then
        return "borderSuccess"
    end
    if tone == "danger" then
        return "borderDanger"
    end
    if tone == "warning" then
        return "borderWarning"
    end
    if tone == "info" then
        return "borderInfo"
    end
    return nil
end

--- A progress meter. The module supplies label, value, max and the optional
--- detail line; the shell never composes that text itself.
--- @param meter table a DescribeProgress() entry
--- @return Panel
function MTGWidgets.Meter(meter)
    local max = meter.max or 0
    local value = math.min(meter.value or 0, max)
    local fill = "0%"
    if max > 0 then
        fill = string.format("%d%%", math.floor((value / max) * 100))
    end

    local trackClasses = {}
    local borderClass = MTGWidgets.ToneBorderClass(meter.tone)
    if borderClass ~= nil then
        trackClasses[#trackClasses + 1] = borderClass
    end

    local children = {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",

            gui.Label{
                classes = { "sizeS" },
                width = "70%",
                height = "auto",
                halign = "left",
                valign = "center",
                text = meter.label or "",
            },

            gui.Label{
                classes = { "sizeS", "number" },
                width = "28%",
                height = "auto",
                halign = "right",
                valign = "center",
                textAlignment = "right",
                text = string.format("%d / %d", meter.value or 0, max),
            },
        },

        --The border is what carries the tone while the bar is still empty.
        gui.Panel{
            classes = trackClasses,
            width = "100%",
            height = 20,
            valign = "top",
            tmargin = 2,
            flow = "none",
            bgimage = true,
            bgcolor = "clear",
            borderWidth = 1,
            cornerRadius = 0,

            gui.Panel{
                classes = { MTGWidgets.ToneClass(meter.tone) },
                width = fill,
                height = "100%",
                halign = "left",
                valign = "center",
                cornerRadius = 0,
            },
        },
    }

    if meter.detail ~= nil and meter.detail ~= "" then
        children[#children + 1] = gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            valign = "top",
            tmargin = 2,
            text = meter.detail,
        }
    end

    return gui.Panel{
        width = "46%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        rmargin = 12,
        children = children,
    }
end
