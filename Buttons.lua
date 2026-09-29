-- The paddle action buttons: art, cooldowns, usability, range, secure
-- attributes, drag and drop, and tooltips.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local LAYOUT = ns.LAYOUT
local ATLAS = ns.ATLAS
local NATIVE_CVAR_PROMPTS = ns.NATIVE_CVAR_PROMPTS
local PANELS = ns.PANELS
local panelFrames = ns.panelFrames
local buttons = ns.buttons
local focusRouting = ns.focusRouting
local Print = ns.Print
local GetMedia = ns.GetMedia
local GetPaddleTexture = ns.GetPaddleTexture
local SafeCall = ns.SafeCall
local IsSecret = ns.IsSecret
local ApplyCooldown = ns.ApplyCooldown
local LegacyCooldownActive = ns.LegacyCooldownActive
local AtlasExists = ns.AtlasExists
local ApplyArt = ns.ApplyArt
local GetNativeCVarBool = ns.GetNativeCVarBool
local IsEditable = ns.IsEditable
local GetNativeSlot = ns.GetNativeSlot

-- Reading order: P1 and P2 on the top row, P3 and P4 on the bottom row.
local GRID_CELLS = {
    [1] = { col = 0, row = 0 },
    [2] = { col = 1, row = 0 },
    [3] = { col = 0, row = 1 },
    [4] = { col = 1, row = 1 },
}

local function ClearCooldown(button)
    if button.cooldown.Clear then
        button.cooldown:Clear()
    else
        button.cooldown:SetCooldown(0, 0)
    end
end

local function GetFallbackActionDisplay(action)
    if not action then
        return nil, nil
    end

    if action.kind == "spell" then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(action.id)
        if info then
            return info.iconID, info.name
        end
        return nil, "Spell " .. tostring(action.id)
    elseif action.kind == "item" then
        local itemID, _, _, _, icon = C_Item.GetItemInfoInstant(action.id)
        local name = C_Item.GetItemInfo(action.id)
        if not name and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(action.id)
        end
        return icon, name or ("Item " .. tostring(itemID or action.id))
    elseif action.kind == "macro" then
        local name, icon = GetMacroInfo(action.id)
        return icon, name or ("Macro " .. tostring(action.id))
    end

    return nil, nil
end

local function UpdateFallbackCooldown(button)
    local action = button.actionData
    if not action then
        ClearCooldown(button)
        return
    end

    if action.kind == "spell" and C_Spell and C_Spell.GetSpellCooldown then
        local info = SafeCall(C_Spell.GetSpellCooldown, action.id)
        if type(info) == "table" then
            local active = info.isActive
            if not IsSecret(active) and active == nil then
                active = LegacyCooldownActive(info.startTime, info.duration, info.isEnabled)
            end
            ApplyCooldown(button.cooldown, active, info.startTime, info.duration, info.modRate)
        else
            ClearCooldown(button)
        end
    elseif action.kind == "item" and C_Item and C_Item.GetItemCooldown then
        local startTime, duration, enabled = SafeCall(C_Item.GetItemCooldown, action.id)
        ApplyCooldown(button.cooldown, LegacyCooldownActive(startTime, duration, enabled), startTime, duration)
    else
        ClearCooldown(button)
    end
end

local function UpdateNativeCooldown(button)
    local slot = button.actionSlot
    if not slot or not C_ActionBar.HasAction(slot) then
        ClearCooldown(button)
        return
    end

    -- Mirrors ActionButton_ApplyCooldown: the client's isActive flag decides
    -- whether a swipe is shown, and the (possibly secret) timing values are
    -- handed to the Cooldown widget without being inspected.
    local info = C_ActionBar.GetActionCooldown and SafeCall(C_ActionBar.GetActionCooldown, slot) or nil
    if type(info) == "table" then
        local active = info.isActive
        if not IsSecret(active) and active == nil then
            active = LegacyCooldownActive(info.startTime, info.duration, info.isEnabled)
        end
        ApplyCooldown(button.cooldown, active, info.startTime, info.duration, info.modRate)
        return
    end

    local startTime, duration, enable, modRate = SafeCall(GetActionCooldown, slot)
    ApplyCooldown(button.cooldown, LegacyCooldownActive(startTime, duration, enable), startTime, duration, modRate)
end

-- Native action buttons tint the icon when the action cannot be used
-- (ActionBarActionButtonMixin:UpdateUsable).
local function UpdateUsableTint(button, hasAction)
    local icon = button.visual.icon
    if not hasAction then
        icon:SetVertexColor(1, 1, 1)
        return
    end

    local isUsable, notEnoughMana
    if button.actionSlot then
        if C_ActionBar and type(C_ActionBar.IsUsableAction) == "function" then
            isUsable, notEnoughMana = SafeCall(C_ActionBar.IsUsableAction, button.actionSlot)
        elseif type(IsUsableAction) == "function" then
            isUsable, notEnoughMana = SafeCall(IsUsableAction, button.actionSlot)
        end
    else
        local action = button.actionData
        if action and action.kind == "spell" and C_Spell and type(C_Spell.IsSpellUsable) == "function" then
            isUsable, notEnoughMana = SafeCall(C_Spell.IsSpellUsable, action.id)
        elseif action and action.kind == "item" and C_Item and type(C_Item.IsUsableItem) == "function" then
            isUsable, notEnoughMana = SafeCall(C_Item.IsUsableItem, action.id)
        end
    end

    -- Usability may be secret in combat; a secret answer cannot be tested, so
    -- the icon is left untinted rather than guessed.
    if IsSecret(isUsable) or IsSecret(notEnoughMana) or isUsable == nil then
        isUsable = true
        notEnoughMana = false
    end

    if isUsable then
        icon:SetVertexColor(1, 1, 1)
    elseif notEnoughMana then
        icon:SetVertexColor(0.5, 0.5, 1.0)
    else
        icon:SetVertexColor(0.4, 0.4, 0.4)
    end
end

-- Range feedback is polled with IsActionInRange instead of asking the client
-- to push ACTION_RANGE_CHECK_UPDATE for our slots: on Forever build 69913,
-- C_ActionBar.EnableActionRangeCheck trips a client assert (a hard crash that
-- pcall cannot catch) for gamepad storage slots that are not owned by a
-- native action button. The event handler is kept in case the client sends
-- updates for a slot anyway.
local function SetRangeCheckEnabled(button, enabled)
    enabled = enabled == true and button.actionSlot ~= nil
    if button.rangeCheckEnabled == enabled then
        return
    end

    button.rangeCheckEnabled = enabled
    if not enabled then
        button.visual.rangeIndicator:Hide()
    end
end

local function UpdateRangeIndicator(button, checksRange, inRange)
    local visual = button.visual
    if not checksRange or not button.hasAction then
        visual.rangeIndicator:Hide()
        visual.prompt:SetVertexColor(1, 1, 1)
        return
    end

    visual.rangeIndicator:Show()
    if inRange then
        local color = ACTIONBAR_HOTKEY_FONT_COLOR
        if color and color.GetRGB then
            visual.rangeIndicator:SetTextColor(color:GetRGB())
        else
            visual.rangeIndicator:SetTextColor(0.6, 0.6, 0.6)
        end
        visual.prompt:SetVertexColor(1, 1, 1)
    else
        local color = RED_FONT_COLOR
        if color and color.GetRGB then
            visual.rangeIndicator:SetTextColor(color:GetRGB())
        else
            visual.rangeIndicator:SetTextColor(1, 0.1, 0.1)
        end
        visual.prompt:SetVertexColor(0.55, 0.55, 0.55)
    end
end

local function ShouldShowPrompts()
    return PaddleSlotsDB.showPaddleBadges ~= false and GetNativeCVarBool(NATIVE_CVAR_PROMPTS, true)
end

local function UpdatePromptVisibility(button)
    local panel = panelFrames[button.panelIndex]
    local shown = panel ~= nil and panel.isActive == true and button.hasAction == true and ShouldShowPrompts()
    button.visual.prompt:SetShown(shown and button.visual.prompt.artAvailable)
end

local function UpdateButtonVisual(button)
    local visual = button.visual
    local icon
    local hasAction = false

    if button.actionSlot then
        hasAction = C_ActionBar.HasAction(button.actionSlot)
        if hasAction then
            icon = GetActionTexture(button.actionSlot)
        end
        UpdateNativeCooldown(button)
    else
        icon = GetFallbackActionDisplay(button.actionData)
        hasAction = icon ~= nil
        UpdateFallbackCooldown(button)
    end

    button.hasAction = hasAction

    if icon then
        visual.icon:SetTexture(icon)
        visual.icon:Show()
        visual.emptyGlyph:Hide()
    else
        visual.icon:SetTexture(nil)
        visual.icon:Hide()
        visual.emptyGlyph:SetShown(visual.emptyGlyph.artAvailable)
    end

    UpdateUsableTint(button, hasAction)

    local count
    if button.actionSlot and hasAction then
        if C_ActionBar and type(C_ActionBar.GetActionDisplayCount) == "function" then
            count = SafeCall(C_ActionBar.GetActionDisplayCount, button.actionSlot)
        else
            count = GetActionCount(button.actionSlot)
        end
    elseif button.actionData and button.actionData.kind == "item" and C_Item and type(C_Item.GetItemCount) == "function" then
        count = SafeCall(C_Item.GetItemCount, button.actionData.id)
    end
    if IsSecret(count) then
        -- GetActionDisplayCount already returns display-ready text; the native
        -- buttons pass it straight to SetText, which accepts secret values.
        visual.count:SetText(count)
    else
        if type(count) == "number" and count <= 1 then
            count = nil
        elseif count == "" or count == "0" or count == "1" then
            count = nil
        end
        visual.count:SetText(count and tostring(count) or "")
    end

    SetRangeCheckEnabled(button, hasAction)
    if not hasAction then
        UpdateRangeIndicator(button, false, false)
    end
    UpdatePromptVisibility(button)
end

local function ApplyFallbackSecureAction(button)
    if InCombatLockdown() then
        ns.pendingSecureRefresh = true
        return
    end

    button:SetAttribute("type", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("macrotext", nil)

    local action = button.actionData
    if not action then
        return
    end

    if action.kind == "spell" then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", action.id)
    elseif action.kind == "item" then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. tostring(action.id))
    elseif action.kind == "macro" then
        local _, _, body = GetMacroInfo(action.id)
        if body and body ~= "" then
            button:SetAttribute("type", "macro")
            button:SetAttribute("macrotext", body)
        end
    end
end

local function ConfigureSecureAction(button)
    if InCombatLockdown() then
        ns.pendingSecureRefresh = true
        return
    end

    if button.actionSlot then
        button:SetAttribute("type", "action")
        button:SetAttribute("action", button.actionSlot)
    else
        ApplyFallbackSecureAction(button)
    end
    focusRouting.SyncAttributes(button)
end

local function ConvertCursorToFallbackAction()
    local cursorType, a, b, c = GetCursorInfo()
    if not cursorType then
        return nil
    end

    if cursorType == "spell" then
        local spellID = c or a
        if spellID then
            return { kind = "spell", id = spellID }
        end
    elseif cursorType == "item" and a then
        return { kind = "item", id = a }
    elseif cursorType == "macro" and a then
        return { kind = "macro", id = a }
    elseif cursorType == "action" then
        local actionType, id, subType = GetActionInfo(a)
        if actionType == "spell" and id then
            return { kind = "spell", id = id }
        elseif actionType == "item" and id then
            return { kind = "item", id = id }
        elseif actionType == "macro" and id then
            return { kind = "macro", id = id }
        elseif actionType == "companion" and subType == "MOUNT" and id then
            return { kind = "spell", id = id }
        end
    end

    return nil
end

local function SetFallbackAction(button, action)
    if InCombatLockdown() then
        Print("Actions cannot be changed during combat.")
        return
    end

    PaddleSlotsCharDB.fallbackActions[button.panelIndex][button.paddleIndex] = action
    button.actionData = action
    ConfigureSecureAction(button)
    UpdateButtonVisual(button)
end

local function PutCursorIntoButton(button)
    if InCombatLockdown() then
        Print("Actions cannot be changed during combat.")
        return
    end

    if button.actionSlot then
        local cursorType = GetCursorInfo()
        if not cursorType then
            return
        end

        local ok = pcall(C_ActionBar.PutActionInSlot, button.actionSlot)
        if not ok then
            Print("The client rejected that action for native gamepad storage.")
            return
        end
        UpdateButtonVisual(button)
        return
    end

    local action = ConvertCursorToFallbackAction()
    if not action then
        Print("That cursor payload is not supported by fallback storage.")
        return
    end

    SetFallbackAction(button, action)
    ClearCursor()
end

local function PickupButtonAction(button)
    if InCombatLockdown() then
        return
    end
    -- Like ActionButton OnDragStart: locked bars only give up actions with the
    -- pickup modifier held. Edit Mode and the addon's unlock count as unlocked.
    if not IsEditable() and GetNativeCVarBool("lockActionBars", false)
        and not (type(IsModifiedClick) == "function" and IsModifiedClick("PICKUPACTION")) then
        return
    end

    if button.actionSlot then
        if C_ActionBar.HasAction(button.actionSlot) then
            PickupAction(button.actionSlot)
            UpdateButtonVisual(button)
        end
        return
    end

    local action = button.actionData
    if not action then
        return
    end

    if action.kind == "spell" then
        if C_Spell and C_Spell.PickupSpell then
            C_Spell.PickupSpell(action.id)
        elseif PickupSpell then
            PickupSpell(action.id)
        end
    elseif action.kind == "item" then
        if C_Item and C_Item.PickupItem then
            C_Item.PickupItem(action.id)
        elseif PickupItem then
            PickupItem(action.id)
        end
    elseif action.kind == "macro" then
        PickupMacro(action.id)
    end
end

local function ClearButtonAction(button)
    if InCombatLockdown() then
        Print("Actions cannot be changed during combat.")
        return
    end

    if button.actionSlot then
        if C_ActionBar.HasAction(button.actionSlot) then
            PickupAction(button.actionSlot)
            ClearCursor()
        end
        UpdateButtonVisual(button)
    else
        SetFallbackAction(button, nil)
    end
end

local function ShowTooltip(button)
    button.visual.highlight:SetShown(button.visual.highlight.artAvailable)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

    if button.actionSlot and C_ActionBar.HasAction(button.actionSlot) then
        if GameTooltip.SetAction then
            GameTooltip:SetAction(button.actionSlot)
            return
        end
    elseif button.actionData then
        local action = button.actionData
        if action.kind == "spell" then
            GameTooltip:SetHyperlink("spell:" .. tostring(action.id))
            return
        elseif action.kind == "item" then
            GameTooltip:SetHyperlink("item:" .. tostring(action.id))
            return
        elseif action.kind == "macro" then
            local name, _, body = GetMacroInfo(action.id)
            GameTooltip:AddLine(name or "Macro")
            if body and body ~= "" then
                GameTooltip:AddLine(body, 1, 1, 1, true)
            end
            GameTooltip:Show()
            return
        end
    end

    local panel = PANELS[button.panelIndex]
    GameTooltip:AddLine(panel.label .. " · Paddle P" .. button.paddleIndex)
    GameTooltip:AddLine("Drop an action here.", 1, 1, 1, true)
    if ns.nativeStorageEnabled then
        GameTooltip:AddLine("Native gamepad action storage", 0.55, 0.8, 1.0, true)
    end
    GameTooltip:Show()
end

local function HideTooltip(button)
    button.visual.highlight:Hide()
    GameTooltip:Hide()
end

local function GetButtonCenter(paddleIndex, expanded)
    local spacing = expanded and LAYOUT.GRID_SPACING_EXPANDED or LAYOUT.GRID_SPACING_COLLAPSED
    local cell = GRID_CELLS[paddleIndex]
    return (cell.col - 0.5) * spacing, LAYOUT.GRID_CENTER_Y + (0.5 - cell.row) * spacing
end

-- Positions and sizes the non-secure art of a slot. The secure click target
-- itself never moves, so this is safe to call during combat.
local function LayoutButtonVisual(button)
    local panel = panelFrames[button.panelIndex]
    local visual = button.visual
    if not panel or not visual then
        return
    end

    local expanded = panel.expanded == true
    local size = expanded and LAYOUT.BUTTON_SIZE_EXPANDED or LAYOUT.BUTTON_SIZE_COLLAPSED
    local x, y = GetButtonCenter(button.paddleIndex, expanded)
    if button.pushed then
        size = size - LAYOUT.BUTTON_PRESSED_SIZE_OFFSET
        y = y - (LAYOUT.BUTTON_PRESSED_SIZE_OFFSET * 0.5)
    end

    visual:SetSize(size, size)
    visual:ClearAllPoints()
    visual:SetPoint("CENTER", panel, "CENTER", x, y)
    visual.emptyGlyph:SetSize(size * LAYOUT.EMPTY_GLYPH_RATIO, size * LAYOUT.EMPTY_GLYPH_RATIO)

    local shadowDistance = expanded and LAYOUT.SHADOW_DISTANCE_EXPANDED or LAYOUT.SHADOW_DISTANCE_COLLAPSED
    for _, shadow in ipairs({ visual.shadow, visual.shadowFocus }) do
        shadow:ClearAllPoints()
        shadow:SetPoint("TOPLEFT", -shadowDistance, shadowDistance)
        shadow:SetPoint("BOTTOMRIGHT", shadowDistance, -shadowDistance)
    end
    visual.shadow:SetShown(not expanded and visual.shadow.artAvailable)
    visual.shadowFocus:SetShown(expanded and visual.shadowFocus.artAvailable)

    local showPressed = button.pushed and visual.borderPressed.artAvailable
    visual.borderPressed:SetShown(showPressed)
    visual.border:SetShown(not showPressed)
end

local function SetButtonPushed(button, pushed)
    pushed = pushed == true
    if button.pushed == pushed then
        return
    end
    button.pushed = pushed
    LayoutButtonVisual(button)
end

local function CreateActionButton(panelIndex, paddleIndex, panel)
    local name = string.format("PaddleSlotsButton%d_%d", panelIndex, paddleIndex)
    local button = CreateFrame("Button", name, panel, "SecureActionButtonTemplate")
    button.panelIndex = panelIndex
    button.paddleIndex = paddleIndex
    button.pushed = false
    button.hasAction = false
    button:SetSize(LAYOUT.BUTTON_SIZE_EXPANDED, LAYOUT.BUTTON_SIZE_EXPANDED)
    button:SetFrameLevel(panel:GetFrameLevel() + 10)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:RegisterForDrag("LeftButton")
    -- Native gamepad action buttons trigger on press rather than on release.
    button:SetAttribute("useOnKeyDown", true)

    -- The secure button is only the click target. All art lives on a plain
    -- frame so it can be resized and re-anchored while in combat.
    local visual = CreateFrame("Frame", nil, panel)
    visual:SetFrameLevel(panel:GetFrameLevel() + 5)
    visual:SetSize(LAYOUT.BUTTON_SIZE_COLLAPSED, LAYOUT.BUTTON_SIZE_COLLAPSED)
    button.visual = visual

    visual.shadow = visual:CreateTexture(nil, "BACKGROUND", nil, -1)
    ApplyArt(visual.shadow, ATLAS.shadow, nil)
    visual.shadow:Hide()

    visual.shadowFocus = visual:CreateTexture(nil, "BACKGROUND", nil, -1)
    ApplyArt(visual.shadowFocus, ATLAS.shadowFocus, nil)
    visual.shadowFocus:Hide()

    visual.slotArt = visual:CreateTexture(nil, "BACKGROUND", nil, 0)
    visual.slotArt:SetAllPoints()
    visual.slotArt:SetTexture(GetMedia("SlotBase"))

    visual.icon = visual:CreateTexture(nil, "BACKGROUND", nil, 1)
    visual.icon:SetAllPoints()
    visual.icon:Hide()

    if visual.CreateMaskTexture and visual.icon.AddMaskTexture then
        visual.iconMask = visual:CreateMaskTexture()
        visual.iconMask:SetPoint("TOPLEFT", 3, -3)
        visual.iconMask:SetPoint("BOTTOMRIGHT", -3, 3)
        if AtlasExists(ATLAS.circleMask) then
            visual.iconMask:SetAtlas(ATLAS.circleMask)
        else
            visual.iconMask:SetTexture(GetMedia("CircleMask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        visual.icon:AddMaskTexture(visual.iconMask)
    end

    -- Empty slots show the paddle glyph the way native slots show their face button.
    visual.emptyGlyph = visual:CreateTexture(nil, "ARTWORK", nil, 0)
    visual.emptyGlyph:SetPoint("CENTER")
    visual.emptyGlyph:SetTexture(GetPaddleTexture(paddleIndex))
    visual.emptyGlyph.artAvailable = true
    visual.emptyGlyph:SetAlpha(0.9)

    visual.cooldown = CreateFrame("Cooldown", nil, visual, "CooldownFrameTemplate")
    visual.cooldown:SetPoint("TOPLEFT", 3, -3)
    visual.cooldown:SetPoint("BOTTOMRIGHT", -3, 3)
    if visual.cooldown.SetSwipeTexture then
        visual.cooldown:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        visual.cooldown:SetSwipeColor(0, 0, 0, 0.64)
    end
    if visual.cooldown.SetDrawBling then
        visual.cooldown:SetDrawBling(false)
    end
    if visual.cooldown.SetDrawEdge then
        visual.cooldown:SetDrawEdge(false)
    end

    visual.border = visual:CreateTexture(nil, "ARTWORK", nil, 1)
    visual.border:SetAllPoints()
    ApplyArt(visual.border, ATLAS.border, GetMedia("SlotRing"))

    visual.borderPressed = visual:CreateTexture(nil, "ARTWORK", nil, 1)
    visual.borderPressed:SetAllPoints()
    ApplyArt(visual.borderPressed, ATLAS.borderPressed, GetMedia("PressedOverlay"))
    visual.borderPressed:Hide()

    visual.highlight = visual:CreateTexture(nil, "OVERLAY", nil, 0)
    visual.highlight:SetAllPoints()
    ApplyArt(visual.highlight, ATLAS.borderHover, GetMedia("SlotHighlight"))
    visual.highlight:Hide()

    -- Button prompt shown on the focused bar, like the native ButtonIcon.
    visual.prompt = visual:CreateTexture(nil, "OVERLAY", nil, 2)
    visual.prompt:SetSize(LAYOUT.PROMPT_ICON_SIZE, LAYOUT.PROMPT_ICON_SIZE)
    visual.prompt:SetPoint("TOPRIGHT", -1, -1)
    visual.prompt:SetTexture(GetPaddleTexture(paddleIndex))
    visual.prompt.artAvailable = true
    visual.prompt:Hide()

    visual.count = visual:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    visual.count:SetPoint("BOTTOMRIGHT", -5, 5)
    visual.count:SetJustifyH("RIGHT")

    visual.rangeIndicator = visual:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    visual.rangeIndicator:SetPoint("CENTER", 10, 10)
    visual.rangeIndicator:SetText(RANGE_INDICATOR or "●")
    visual.rangeIndicator:Hide()

    -- Aliases used by the shared cooldown helpers.
    button.icon = visual.icon
    button.cooldown = visual.cooldown
    button.count = visual.count

    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function(self)
        HideTooltip(self)
        SetButtonPushed(self, false)
    end)
    button:SetScript("PostClick", function(self, _, down)
        SetButtonPushed(self, down == true)
    end)
    button:SetScript("OnHide", function(self)
        SetButtonPushed(self, false)
    end)
    button:SetScript("OnReceiveDrag", PutCursorIntoButton)
    button:SetScript("OnDragStart", PickupButtonAction)

    if ns.nativeStorageEnabled then
        button.actionSlot = GetNativeSlot(panelIndex, paddleIndex)
    else
        button.actionData = PaddleSlotsCharDB.fallbackActions[panelIndex][paddleIndex]
    end

    buttons[panelIndex][paddleIndex] = button
    ConfigureSecureAction(button)
    LayoutButtonVisual(button)
    UpdateButtonVisual(button)
    return button
end

local function ForEachButton(func)
    for panelIndex = 1, PANEL_COUNT do
        for paddleIndex = 1, PADDLE_COUNT do
            local button = buttons[panelIndex] and buttons[panelIndex][paddleIndex]
            if button then
                func(button, panelIndex, paddleIndex)
            end
        end
    end
end

-- Visual-only refresh; safe to run in combat and on high-frequency events.
local function UpdateAllButtonVisuals()
    ForEachButton(UpdateButtonVisual)
end

-- Full refresh including secure attributes. Deferred while in combat.
local function RefreshButtons()
    ForEachButton(function(button, panelIndex, paddleIndex)
        if not button.actionSlot then
            button.actionData = PaddleSlotsCharDB.fallbackActions[panelIndex][paddleIndex]
        end
        ConfigureSecureAction(button)
        UpdateButtonVisual(button)
    end)
end

ns.UpdateRangeIndicator = UpdateRangeIndicator
ns.UpdatePromptVisibility = UpdatePromptVisibility
ns.UpdateButtonVisual = UpdateButtonVisual
ns.ClearButtonAction = ClearButtonAction
ns.GetButtonCenter = GetButtonCenter
ns.LayoutButtonVisual = LayoutButtonVisual
ns.SetButtonPushed = SetButtonPushed
ns.CreateActionButton = CreateActionButton
ns.ForEachButton = ForEachButton
ns.UpdateAllButtonVisuals = UpdateAllButtonVisuals
ns.RefreshButtons = RefreshButtons
