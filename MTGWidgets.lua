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
--- @param sizeClass nil|string overrides the default size
--- @return Panel
function MTGWidgets.SubHeader(text, sizeClass)
    return gui.Label{
        classes = { "tableLabel", sizeClass or "sizeXs" },
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

--- The round's free participant tokens: everyone not currently standing on a
--- test still in play. Anyone who already took a test this round is here too,
--- greyed, and can take another.
--- @param run MTGRun
--- @param participants MTGParticipant[]
--- @param onReturn fun(charid: string)
--- @return Panel
function MTGWidgets.Tray(run, participants, onReturn)
    local children = {}
    for _, p in ipairs(participants) do
        local token = MTGWidgets.ParticipantToken(p, true, nil,
            MTGRun.HasActedThisRound(run, p.charid))
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

--- A progress meter. The module supplies label, value, max and the optional
--- detail line; the shell never composes that text itself.
--- @param meter table a DescribeProgress() entry
--- @return Panel
function MTGWidgets.Meter(meter)
    local max = meter.max or 0
    local value = math.min(meter.value or 0, max)

    local earnedIcon = cond(meter.tone == "danger",
        MTGConstants.iconFailure, MTGConstants.iconSuccess)

    --The Director awards and takes back by hand on meters the module says may
    --be moved. Which pip was clicked does not matter, only which side of the
    --line it was on: a dim one adds, a lit one removes. That reads as filling
    --the next pip or clearing the last, without the pips having to be told
    --apart from one another.
    local adjustable = dmhub.isDM and meter.adjustable == true and max > 0

    local pips = {}
    for i = 1, max do
        local earned = i <= value

        --Built in one go rather than assigned onto afterwards: hover is fixed
        --at construction and will not take a later write.
        local args = {
            classes = { cond(earned, MTGWidgets.ToneClass(meter.tone), "bgFgMuted") },
            width = 22,
            height = 22,
            halign = "left",
            valign = "center",
            rmargin = 2,
            vmargin = 1,
            bgimage = cond(earned, earnedIcon, MTGConstants.iconPending),
        }

        if adjustable then
            args.hover = gui.Tooltip(cond(earned,
                string.format("Take back one %s", meter.label or "point"),
                string.format("Award one %s", meter.label or "point")))
            args.press = function()
                MTGRun.AdjustProgress(meter.id, cond(earned, -1, 1))
            end
        end

        pips[#pips + 1] = gui.Panel(args)
    end

    --Wraps rather than clips: a Director who sets a big limit gets a second
    --row instead of pips disappearing off the edge.
    local pipRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        halign = "left",
        valign = "top",
        tmargin = 2,
        children = pips,
    }

    local children = {
        gui.Label{
            classes = { "sizeS" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            text = string.format("%s (%d/%d)", meter.label or "", meter.value or 0, max),
        },

        --One pip per point, in the same vocabulary the challenge rows use:
        --unknown until it lands, then a check or an x. These are counts of
        --events, never fractions, so a bar would imply a granularity that
        --does not exist -- and at these magnitudes the pips are countable at
        --a glance without reading the numeral.
        pipRow,
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

--- First of these keys the style actually carries. A style is userdata and
--- reading a key it does not have raises, so each one is probed.
--- @param style any
--- @return number
--- A curtain over whatever hosts it: dims it, swallows clicks, says why.
--- Collapsed until the caller shows it.
--- @param text string
--- @param sizeClass string
--- @param hostLevels nil|number how far up to measure; 1 (the parent) by default
--- @param inset nil|number the host's padding, which it does not expose
--- @return Panel
function MTGWidgets.Overlay(text, sizeClass, hostLevels, inset)
    hostLevels = hostLevels or 1
    inset = inset or 0

    return gui.Panel{
        classes = { "bordered", "collapsed" },
        floating = true,
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",
        flow = "none",
        bgimage = true,
        bgcolor = "#000000c0",

        --Stops the raycast reaching the controls underneath.
        interactable = true,

        --A host sized to its own content gives a percentage nothing to resolve
        --against, and renderedHeight reads 0 until the first layout pass.
        thinkTime = 0.2,
        think = function(element)
            if element:HasClass("collapsed") then
                return
            end

            --A rebuild can leave a stale link up the chain, and reading
            --anything off a panel whose object has gone raises.
            local host = element
            for _ = 1, hostLevels do
                if host == nil or not host.valid then
                    return
                end
                host = host.parent
            end
            if host == nil or not host.valid then
                return
            end

            local w = host.renderedWidth
            local h = host.renderedHeight
            if w ~= nil and w > 0 and h ~= nil and h > 0 then
                --Padding counts as part of the host, so its rendered size
                --includes it while children start inside it. Step back out.
                element.selfStyle.width = w
                element.selfStyle.height = h
                element.x = -inset
                element.y = -inset
            end
        end,

        gui.Label{
            classes = { sizeClass, "bold" },
            width = "90%",
            height = "auto",
            halign = "center",
            valign = "center",
            textAlignment = "center",
            textWrap = true,
            text = text,
        },
    }
end
