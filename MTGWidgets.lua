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

    --The frame is a separate child, so desaturate the children too.
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


--- The round's free participant tokens: everyone not currently standing on a
--- test still in play. Anyone who already took a test this round is here too,
--- greyed, and can take another. Built once and handed the free participants
--- with `setTray`; a token's portrait, drag and dimming are fixed at
--- construction, so each sits in a slot remade when its state moves.
--- @param onReturn fun(charid: string)
--- @return Panel
function MTGWidgets.Tray(onReturn)
    local tokens = gui.Panel{
        width = "auto",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "center",
    }

    local emptyLabel = gui.Label{
        classes = { "sizeXs", "noBold", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        text = "All Heroes assigned",
    }

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

        --- @param entries {p: MTGParticipant, dimmed: boolean}[]
        setTray = function(element, entries)
            emptyLabel:SetClass("collapsed", #entries > 0)
            THCWidgets.BindList(tokens, entries, function()
                return MTGWidgets.Slot{
                    setToken = function(slot, entry)
                        local state = ""
                        if entry ~= nil then
                            state = entry.p.charid .. "|" .. tostring(entry.dimmed)
                                .. "|" .. tostring(MTGRun.CanManage(entry.p.charid))
                        end
                        MTGWidgets.SetSlot(slot, state, function()
                            return MTGWidgets.ParticipantToken(entry.p, true, nil, entry.dimmed)
                        end)
                    end,
                }
            end, "setToken")
        end,

        tokens,
        emptyLabel,
    }
end

--- One pip of a meter. Its tooltip is fixed at construction, so the slot
--- holding it is remade when the pip is earned or given back.
--- @param pip {earned: boolean, tone: string|nil, label: string, meterId: string, adjustable: boolean}
--- @return Panel
local function Pip(pip)
    local earnedIcon = cond(pip.tone == "danger",
        MTGConstants.iconFailure, MTGConstants.iconSuccess)

    local args = {
        classes = { cond(pip.earned, MTGWidgets.ToneClass(pip.tone), "bgFgMuted") },
        width = 22,
        height = 22,
        halign = "left",
        valign = "center",
        rmargin = 2,
        vmargin = 1,
        bgimage = cond(pip.earned, earnedIcon, MTGConstants.iconPending),
    }

    if pip.adjustable then
        args.hover = gui.Tooltip(cond(pip.earned,
            string.format("Take back one %s", pip.label),
            string.format("Award one %s", pip.label)))
        args.press = function()
            MTGRun.AdjustProgress(pip.meterId, cond(pip.earned, -1, 1))
        end
    end

    return gui.Panel(args)
end

--- A progress meter. Built once and handed a descriptor with `setMeter`;
--- handed nil, it collapses. The module supplies label, value, max and the
--- optional detail line; the shell never composes that text itself.
--- @return Panel
function MTGWidgets.Meter()
    local shown = {}

    local titleLabel = gui.Label{
        classes = { "sizeS" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        text = "",
    }

    local pipRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        halign = "left",
        valign = "top",
        tmargin = 2,
    }

    local detailLabel = gui.Label{
        classes = { "sizeXs", "noBold", "fgMuted" },
        width = "100%",
        height = "auto",
        valign = "top",
        tmargin = 2,
        text = "",
    }

    return gui.Panel{
        width = "46%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        rmargin = 12,

        --- @param meter nil|table a DescribeProgress() entry
        setMeter = function(element, meter)
            element:SetClass("collapsed", meter == nil)
            if meter == nil then
                return
            end

            local max = meter.max or 0
            local value = math.min(meter.value or 0, max)

            local title = string.format("%s (%d/%d)", meter.label or "", meter.value or 0, max)
            if shown.title ~= title then
                shown.title = title
                titleLabel.text = title
            end

            local adjustable = dmhub.isDM and meter.adjustable == true and max > 0
            local pips = {}
            for i = 1, max do
                pips[i] = {
                    earned = i <= value,
                    tone = meter.tone,
                    label = meter.label or "point",
                    meterId = meter.id,
                    adjustable = adjustable,
                }
            end
            THCWidgets.BindList(pipRow, pips, function()
                return MTGWidgets.Slot{
                    setPip = function(slot, pip)
                        local state = ""
                        if pip ~= nil then
                            state = tostring(pip.earned) .. "|" .. tostring(pip.tone)
                                .. "|" .. pip.label .. "|" .. tostring(pip.adjustable)
                        end
                        MTGWidgets.SetSlot(slot, state, function()
                            return Pip(pip)
                        end)
                    end,
                }
            end, "setPip")

            local detail = meter.detail or ""
            if shown.detail ~= detail then
                shown.detail = detail
                detailLabel.text = detail
                detailLabel:SetClass("collapsed", detail == "")
            end
        end,

        titleLabel,
        pipRow,
        detailLabel,
    }
end



--- A kept panel holding one control that is remade only when its state
--- moves: an icon that flips, a token portrait, a block whose shape changes.
--- An empty state empties the slot.
--- @param slot Panel built with a data table
--- @param state string
--- @param build fun(): Panel|nil
--- @return Panel|nil the child now in the slot
function MTGWidgets.SetSlot(slot, state, build)
    if slot.data.slotState ~= state then
        slot.data.slotState = state
        if state == "" then
            slot.data.slotChild = nil
            slot.children = {}
        else
            local child = build()
            slot.data.slotChild = child
            slot.children = { child }
        end
    end
    return slot.data.slotChild
end

--- The slot SetSlot fills. Sized to its content so an empty one takes no
--- room.
--- @param args nil|table extra panel fields
--- @return Panel
function MTGWidgets.Slot(args)
    local panel = {
        width = "auto",
        height = "auto",
        flow = "none",
        halign = "left",
        valign = "center",
        data = {},
    }
    for k, v in pairs(args or {}) do
        panel[k] = v
    end
    return gui.Panel(panel)
end

--- Swap one theme class for another, for a badge whose tone moves.
--- @param element Panel
--- @param from string|nil the class currently on it
--- @param to string
--- @return string the class now on it
function MTGWidgets.SwapClass(element, from, to)
    if from ~= to then
        if from ~= nil then
            element:SetClass(from, false)
        end
        element:SetClass(to, true)
    end
    return to
end

--- What a Threats & Opportunities Challenge is, for its title-bar badge. Nil
--- under any other rules, where a Challenge has no kind.
--- @param ch MTGChallengeDef
--- @param moduleId string
--- @return nil|{icon: string, tone: string, tooltip: string}
function MTGWidgets.ChallengeKind(ch, moduleId)
    if moduleId ~= MTGConstants.moduleTO then
        return nil
    end
    if ch:FieldsFor(moduleId).type == "opportunity" then
        return {
            icon = MTGConstants.iconOpportunity,
            tone = "success",
            tooltip = "Opportunity",
        }
    end
    return {
        icon = MTGConstants.iconThreat,
        tone = "danger",
        tooltip = "Threat",
    }
end

--- The kind badge, built once and collapsed; PatchKindBadge points it at a
--- Challenge.
--- @param size number
--- @param margin number on each side
--- @return Panel
function MTGWidgets.KindBadge(size, margin)
    return gui.Panel{
        classes = { "collapsed" },
        width = size,
        height = size,
        halign = "right",
        valign = "center",
        hmargin = margin,
        bgimage = MTGConstants.iconThreat,
    }
end

--- Points a kind badge at a Challenge: shown only where there is a kind, its
--- glyph, tone and tooltip patched through `shown` so an unchanged one is
--- left alone.
--- @param badge Panel
--- @param shown table the caller's memo of what is on screen
--- @param ch MTGChallengeDef
--- @param moduleId string
function MTGWidgets.PatchKindBadge(badge, shown, ch, moduleId)
    local kind = MTGWidgets.ChallengeKind(ch, moduleId)
    badge:SetClass("collapsed", kind == nil)
    if kind == nil then
        return
    end
    if shown.kindIcon ~= kind.icon then
        shown.kindIcon = kind.icon
        badge.bgimage = kind.icon
        badge.tooltip = gui.Tooltip(kind.tooltip)
    end
    shown.kindTone = MTGWidgets.SwapClass(badge, shown.kindTone, MTGWidgets.ToneClass(kind.tone))
end
