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


--- Point an engine token image at a different token. Its `token` event
--- retargets portrait and frame, but a tree event skips collapsed panels, so a
--- folded card would keep its old portrait. Each part is fired directly
--- instead, the image itself first: its handler stores the token its parts
--- read.
--- @param image Panel made by gui.CreateTokenImage
--- @param token token
function MTGWidgets.RetargetPortrait(image, token)
    image:FireEvent("token", token)
    for _, child in ipairs(image.children or {}) do
        child:FireEvent("token", token)
    end
end

--- A participant token that can be dragged onto a slot, built once and
--- pointed at a participant with `setParticipant`. Handed nil, it collapses.
---
--- The drag props live on a panel we build, because gui.CreateTokenImage
--- makes its own panel and does not forward them, so the image sits inside as
--- a child. Drag and right-click read the token's current binding when they
--- fire, so a token handed someone new never acts for whoever it showed last.
--- @return Panel
function MTGWidgets.ParticipantToken()
    local image = gui.CreateTokenImage(nil, {
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
    })

    local shown = {}

    --- Who the token stands for, and what a right-click does, read by the
    --- handlers when they fire.
    local m_charid = nil
    local m_onRightClick = nil

    return gui.Panel{
        classes = { "mtgToken", "collapsed" },
        width = 40,
        height = 40,
        halign = "left",
        valign = "center",
        hmargin = 2,
        bgimage = true,
        bgcolor = "clear",
        draggable = false,

        canDragOnto = function(element, target)
            return target:HasClass("mtgSlot") or target:HasClass("mtgTray")
        end,

        drag = function(element, target)
            if target == nil or m_charid == nil then
                return
            end
            if target:HasClass("mtgTray") then
                target:FireEvent("dropToTray", m_charid)
            else
                target:FireEvent("dropOnSlot", m_charid)
            end
        end,

        rightClick = function(element)
            if m_onRightClick ~= nil then
                m_onRightClick(element)
            end
        end,

        --- `dimmed` is the theme's disabled idiom, which is desaturation. The
        --- right-click only answers someone who manages this hero.
        --- @param entry nil|{p: MTGParticipant, draggable: boolean, dimmed: boolean, onRightClick: nil|fun(element: Panel)}
        setParticipant = function(element, entry)
            local token = entry ~= nil and dmhub.GetCharacterById(entry.p.charid) or nil
            element:SetClass("collapsed", token == nil)
            if token == nil then
                m_charid = nil
                m_onRightClick = nil
                return
            end

            local mine = MTGRun.CanManage(entry.p.charid)
            m_charid = entry.p.charid
            m_onRightClick = mine and entry.onRightClick or nil

            local draggable = entry.draggable == true and mine
            if element.draggable ~= draggable then
                element.draggable = draggable
            end

            if shown.charid ~= m_charid then
                shown.charid = m_charid
                MTGWidgets.RetargetPortrait(image, token)
            end

            local name = entry.p.name or ""
            if shown.name ~= name then
                shown.name = name
                element.tooltip = THCWidgets.Tooltip(name)
            end

            --The frame is a separate child, so it is desaturated too.
            local saturation = cond(entry.dimmed == true, 0, 1)
            if shown.saturation ~= saturation then
                shown.saturation = saturation
                image.selfStyle.saturation = saturation
                for _, child in ipairs(image.children or {}) do
                    child.selfStyle.saturation = saturation
                end
            end
        end,

        image,
    }
end


--- The round's free participant tokens: everyone not currently standing on a
--- test still in play. Anyone who already took a test this round is here too,
--- greyed, and can take another. Built once and handed the free participants
--- with `setTray`, which rebinds a pool of tokens rather than remaking them.
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
            local tokenEntries = {}
            for i, entry in ipairs(entries) do
                tokenEntries[i] = {
                    p = entry.p,
                    draggable = true,
                    dimmed = entry.dimmed,
                }
            end
            THCWidgets.BindList(tokens, tokenEntries, MTGWidgets.ParticipantToken, "setParticipant")
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
        args.hover = THCWidgets.Tooltip(cond(pip.earned,
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
        badge.tooltip = THCWidgets.Tooltip(kind.tooltip)
    end
    shown.kindTone = MTGWidgets.SwapClass(badge, shown.kindTone, MTGWidgets.ToneClass(kind.tone))
end
