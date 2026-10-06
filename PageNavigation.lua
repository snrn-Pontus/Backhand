-- Paddles that page the native action bar instead of firing a Backhand slot.
-- Each paddle has a behavior: its Backhand actions (the default), the previous
-- or next action-bar page, or a jump to one page. Navigation paddles are bound
-- to hidden secure buttons using the built-in "actionbar" action type, so a
-- press pages the bar through the secure click path, in combat as well.
local _, ns = ...

local PADDLE_COUNT = ns.PADDLE_COUNT
local SafeCall = ns.SafeCall

-- Classic-derived clients have six main action-bar pages.
local PAGE_COUNT = tonumber(NUM_ACTIONBAR_PAGES) or 6

-- Every behavior in the order the settings button steps through them.
local BEHAVIORS = {
    { value = "action", label = "Backhand actions", short = "actions" },
    { value = "previous", label = "Previous action-bar page", short = "previous page", glyph = "<", action = "decrement" },
    { value = "next", label = "Next action-bar page", short = "next page", glyph = ">", action = "increment" },
}
for page = 1, PAGE_COUNT do
    BEHAVIORS[#BEHAVIORS + 1] = {
        value = "page" .. page,
        label = "Action-bar page " .. page,
        short = "page " .. page,
        glyph = tostring(page),
        action = page,
    }
end

local behaviorByValue = {}
for _, behavior in ipairs(BEHAVIORS) do
    behaviorByValue[behavior.value] = behavior
end

-- One hidden secure target per navigation behavior. They never change after
-- creation, so binding a paddle to one is the only thing configuration does.
-- Like the slot buttons they act on the press, not again on release.
local targets = {}
for _, behavior in ipairs(BEHAVIORS) do
    if behavior.action then
        -- BackhandPagePrevious, BackhandPageNext, BackhandPage1 and so on.
        local name = "BackhandPage" .. behavior.value:gsub("^page", ""):gsub("^%l", string.upper)
        local target = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        target:SetSize(1, 1)
        target:SetAlpha(0)
        target:EnableMouse(false)
        target:RegisterForClicks("AnyUp", "AnyDown")
        target:SetAttribute("useOnKeyDown", true)
        target:SetAttribute("type", "actionbar")
        target:SetAttribute("action", behavior.action)
        targets[behavior.value] = target
    end
end

local function GetPaddleBehavior(paddleIndex)
    local value = BackhandDB and BackhandDB.paddleBehaviors and BackhandDB.paddleBehaviors["P" .. paddleIndex]
    return behaviorByValue[value] or behaviorByValue.action
end

-- The secure button a navigation paddle clicks, or nil for Backhand actions.
local function GetPaddleNavigationTarget(paddleIndex)
    return targets[GetPaddleBehavior(paddleIndex).value]
end

-- Short text drawn on the slots of a navigation paddle, or nil.
local function GetPaddleBehaviorGlyph(paddleIndex)
    return GetPaddleBehavior(paddleIndex).glyph
end

-- Accepts a behavior value or the friendlier names the slash command takes.
local BEHAVIOR_ALIASES = {
    actions = "action", slot = "action", slots = "action", backhand = "action",
    prev = "previous", back = "previous", ["<"] = "previous",
    forward = "next", [">"] = "next",
}

local function ParseBehavior(text, pageText)
    text = text and text:lower() or ""
    if text == "page" and tonumber(pageText) then
        text = "page" .. tonumber(pageText)
    elseif tonumber(text) then
        text = "page" .. tonumber(text)
    end
    text = BEHAVIOR_ALIASES[text] or text
    return behaviorByValue[text] and text or nil
end

local function SetPaddleBehavior(paddleIndex, value)
    if not behaviorByValue[value] then
        return false
    end
    BackhandDB.paddleBehaviors["P" .. paddleIndex] = value
    -- Rebinds the keys (deferred until after combat) and redraws the slots.
    ns.ApplyPaddleKeys(false)
    ns.UpdateAllButtonVisuals()
    return true
end

-- Steps to the next (or, with reverse, the previous) behavior.
local function CyclePaddleBehavior(paddleIndex, reverse)
    local current = GetPaddleBehavior(paddleIndex).value
    for index, behavior in ipairs(BEHAVIORS) do
        if behavior.value == current then
            local step = reverse and -1 or 1
            SetPaddleBehavior(paddleIndex, BEHAVIORS[(index - 1 + step) % #BEHAVIORS + 1].value)
            return
        end
    end
    SetPaddleBehavior(paddleIndex, "action")
end

local function GetCurrentActionBarPage()
    if C_ActionBar and type(C_ActionBar.GetActionBarPage) == "function" then
        return SafeCall(C_ActionBar.GetActionBarPage)
    end
    return SafeCall(GetActionBarPage)
end

local function GetPageNavigationDiagnostic()
    local parts = {}
    for paddleIndex = 1, PADDLE_COUNT do
        parts[#parts + 1] = string.format("P%d=%s", paddleIndex, GetPaddleBehavior(paddleIndex).short)
    end
    return string.format("%s (native page %s of %d)",
        table.concat(parts, "   "), tostring(GetCurrentActionBarPage()), PAGE_COUNT)
end

ns.PAGE_COUNT = PAGE_COUNT
ns.GetPaddleBehavior = GetPaddleBehavior
ns.GetPaddleNavigationTarget = GetPaddleNavigationTarget
ns.GetPaddleBehaviorGlyph = GetPaddleBehaviorGlyph
ns.ParsePaddleBehavior = ParseBehavior
ns.SetPaddleBehavior = SetPaddleBehavior
ns.CyclePaddleBehavior = CyclePaddleBehavior
ns.GetPageNavigationDiagnostic = GetPageNavigationDiagnostic
