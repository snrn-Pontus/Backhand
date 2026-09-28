local ADDON_NAME = ...

local PANEL_COUNT = 4
local PADDLE_COUNT = 4
local MEDIA_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local STORAGE_SCAN_LIMIT = 512
local STORAGE_STOP_AFTER_INVALID = 32
local MIN_NATIVE_STORAGE_POOL = 48

-- Slot metrics mirror Blizzard_GamepadActionBars/ActionBarStyles.lua so the
-- paddle slots match the circle (face button) slots of the native crossbar.
-- Bars that are not focused are "collapsed"; the focused bar is "expanded".
local LAYOUT = {
    BUTTON_SIZE_COLLAPSED = 32,
    BUTTON_SIZE_EXPANDED = 40,
    BUTTON_PRESSED_SIZE_OFFSET = 4,
    SHADOW_DISTANCE_COLLAPSED = 4,
    SHADOW_DISTANCE_EXPANDED = 13,
    GRID_SPACING_COLLAPSED = 46,
    GRID_SPACING_EXPANDED = 56,
    GRID_CENTER_Y = 12,
    PROMPT_ICON_SIZE = 15,
    EMPTY_GLYPH_RATIO = 0.62,
    FOCUS_FADE_DURATION = 0.33,
    FOCUS_SHADOW_MIN_ALPHA = 0.4,
    FOCUS_BACKGROUND_ALPHA = 0.375,
    FOCUS_BACKGROUND_WIDTH = 190,
    FOCUS_BACKGROUND_HEIGHT = 176,
    MODIFIER_ICON_Y = -54,
    PANEL_WIDTH = 136,
    PANEL_HEIGHT = 152,
}

-- Native crossbar art (Blizzard_GamepadActionBars). Every atlas has a fallback
-- so the addon keeps working on builds that rename or remove one of them.
local ATLAS = {
    border = "gamepad-actionbar-circleslot-border-normal",
    borderPressed = "gamepad-actionbar-circleslot-border-pressed",
    borderHover = "gamepad-actionbar-circleslot-border-hover",
    shadow = "gamepad-actionbar-circleslot-dropshadow",
    shadowFocus = "gamepad-actionbar-focus-bg-circ",
    focusBackground = "gamepad-actionbar-focus-bg-section",
    editGlow = "gamepad-actionbar-fx-controls-behind",
    circleMask = "CircleMask",
}

-- Paddle glyphs are the addon's own Media\P1-P4 textures: the native
-- Gamepad_Gen_Paddle atlases are plain "P1" text, the addon draws each paddle's
-- shape in the same button style.

local NATIVE_CVAR_SCALING = "GamepadShowActionBarScaling"
local NATIVE_CVAR_HIGHLIGHT = "GamepadShowActionBarHighlight"
local NATIVE_CVAR_PROMPTS = "GamepadShowActionBarButtonPrompts"

local PANELS = {
    { key = "BASE", label = "BASE", lt = false, rt = false },
    { key = "LT", label = "LT", lt = true, rt = false },
    { key = "RT", label = "RT", lt = false, rt = true },
    { key = "BOTH", label = "LT + RT", lt = true, rt = true },
}

-- Reading order: P1 and P2 on the top row, P3 and P4 on the bottom row.
local GRID_CELLS = {
    [1] = { col = 0, row = 0 },
    [2] = { col = 1, row = 0 },
    [3] = { col = 0, row = 1 },
    [4] = { col = 1, row = 1 },
}

-- Inputs a paddle can be assigned to. On Windows the Elite Series 2 does not
-- report its paddles to games; WoW only sees whatever the Xbox Accessories
-- app (or Steam Input / reWASD) maps a paddle to. Only inputs the native
-- gamepad UI never uses are offered, so a paddle can never steal a button.
local PADDLE_KEY_OPTIONS = {
    { value = "PADPADDLE1", label = "Paddle P1 (native)", note = "Only for controllers that report paddles to WoW. The Elite Series 2 on Windows does not." },
    { value = "PADPADDLE2", label = "Paddle P2 (native)", note = "Only for controllers that report paddles to WoW. The Elite Series 2 on Windows does not." },
    { value = "PADPADDLE3", label = "Paddle P3 (native)", note = "Only for controllers that report paddles to WoW. The Elite Series 2 on Windows does not." },
    { value = "PADPADDLE4", label = "Paddle P4 (native)", note = "Only for controllers that report paddles to WoW. The Elite Series 2 on Windows does not." },
    { value = "PADSOCIAL", label = "Share button", note = "Unused by the native gamepad UI. Map a paddle to Share in Xbox Accessories if the app offers it for your controller." },
    { value = "PAD5", label = "Extra face button 5", note = "Unused by the native gamepad UI. Only some controllers or remapping tools can send it." },
    { value = "PAD6", label = "Extra face button 6", note = "Unused by the native gamepad UI. Only some controllers or remapping tools can send it." },
}
for fkey = 13, 24 do
    PADDLE_KEY_OPTIONS[#PADDLE_KEY_OPTIONS + 1] = {
        value = "F" .. fkey,
        label = "Keyboard F" .. fkey,
        note = "For Steam Input or reWASD sending the paddle as a keyboard key. Nothing in WoW uses F13-F24.",
    }
end
-- Physical keyboard keys that WoW leaves unbound by default. The Xbox
-- Accessories app can map a paddle to a keyboard key you press, so these are
-- the practical choices without extra software. Bound keys are refused.
local PHYSICAL_KEY_OPTIONS = {
    { value = "NUMPAD0", label = "Keyboard Numpad 0" }, { value = "NUMPAD1", label = "Keyboard Numpad 1" },
    { value = "NUMPAD2", label = "Keyboard Numpad 2" }, { value = "NUMPAD3", label = "Keyboard Numpad 3" },
    { value = "NUMPAD4", label = "Keyboard Numpad 4" }, { value = "NUMPAD5", label = "Keyboard Numpad 5" },
    { value = "NUMPAD6", label = "Keyboard Numpad 6" }, { value = "NUMPAD7", label = "Keyboard Numpad 7" },
    { value = "NUMPAD8", label = "Keyboard Numpad 8" }, { value = "NUMPAD9", label = "Keyboard Numpad 9" },
    { value = "NUMPADDECIMAL", label = "Keyboard Numpad ." }, { value = "NUMPADDIVIDE", label = "Keyboard Numpad /" },
    { value = "NUMPADMULTIPLY", label = "Keyboard Numpad *" },
    { value = "SCROLLLOCK", label = "Keyboard Scroll Lock" }, { value = "PAUSE", label = "Keyboard Pause" },
    { value = "F6", label = "Keyboard F6" }, { value = "F7", label = "Keyboard F7" }, { value = "F8", label = "Keyboard F8" },
    { value = "F9", label = "Keyboard F9" }, { value = "F10", label = "Keyboard F10" },
    { value = "F11", label = "Keyboard F11" }, { value = "F12", label = "Keyboard F12" },
    { value = "PAGEUP", label = "Keyboard Page Up" }, { value = "PAGEDOWN", label = "Keyboard Page Down" },
}
for _, option in ipairs(PHYSICAL_KEY_OPTIONS) do
    option.note = "A real key the Xbox Accessories app can map a paddle to. Accepted only while nothing in WoW is bound to it."
    PADDLE_KEY_OPTIONS[#PADDLE_KEY_OPTIONS + 1] = option
end
PADDLE_KEY_OPTIONS[#PADDLE_KEY_OPTIONS + 1] = { value = "NONE", label = "Not assigned", note = "This paddle slot is shown but never triggered." }

-- Controller inputs the native Forever gamepad UI relies on. A paddle that
-- arrives as one of these is being mirrored by the controller profile.
local NATIVE_RESERVED_KEYS = {
    PAD1 = "A button", PAD2 = "B button", PAD3 = "X button", PAD4 = "Y button",
    PADDUP = "D-pad up", PADDDOWN = "D-pad down", PADDLEFT = "D-pad left", PADDRIGHT = "D-pad right",
    PADLSHOULDER = "Left bumper (LB)", PADRSHOULDER = "Right bumper (RB)",
    PADLTRIGGER = "Left trigger (LT)", PADRTRIGGER = "Right trigger (RT)",
    PADLSTICK = "Left stick click", PADRSTICK = "Right stick click",
    PADLSTICKUP = "Left stick up", PADLSTICKDOWN = "Left stick down", PADLSTICKLEFT = "Left stick left", PADLSTICKRIGHT = "Left stick right",
    PADRSTICKUP = "Right stick up", PADRSTICKDOWN = "Right stick down", PADRSTICKLEFT = "Right stick left", PADRSTICKRIGHT = "Right stick right",
    PADBACK = "View button", PADFORWARD = "Menu button", PADSYSTEM = "Xbox button",
}

local CAPTURE_IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true,
}

local CAPTURE_TIMEOUT = 20

local addon = CreateFrame("Frame")
local secureDriver = CreateFrame("Frame", "PaddleSlotsSecureDriver", UIParent, "SecureHandlerStateTemplate")
local panelFrames = {}
local buttons = {}
local editModeActive = false
local pendingSecureRefresh = false
local nativeStorageEnabled = false
local nativeStorageSlots = {}
local nativeStorageStatus = "not initialized"
local ltButtonIndex
local rtButtonIndex
local lastVisualPanel
local statePollElapsed = 0
local rangePollElapsed = 0
local RANGE_POLL_INTERVAL = 0.25
local nativeHookStatus = "not attempted"
local lastBoundPanel = 1
local ltModifier
local rtModifier
local securePanelDriverRegistered = false
local settingsCategory
local settingsRegistered = false
local pendingAppearanceRefresh = false
local editModeCallbacksRegistered = false
local nativeModifierCallbackRegistered = false
local visualDetectionMethod = "not initialized"
local missingAtlases = {}
local inputWatcher
local captureFrame
local captureState
local guideFrame

local INPUT_WATCH_TEST_DURATION = 30
local INPUT_WATCH_LEARN_STEP_TIMEOUT = 30

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd5b15fPaddleSlots:|r " .. tostring(message))
end

local function GetMedia(name)
    return MEDIA_PATH .. name
end

local function GetPaddleTexture(index)
    return GetMedia("P" .. index)
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local ok, a, b, c, d = pcall(func, ...)
    if not ok then
        return nil
    end
    return a, b, c, d
end

-- Forever hands addons "secret" numbers and booleans for some combat data
-- (cooldowns, usability, range). They can be passed straight to widgets such
-- as Cooldown:SetCooldown or FontString:SetText, but comparing them, doing
-- arithmetic on them, or using them as a condition raises a Lua error.
local function IsSecret(value)
    if type(issecretvalue) == "function" then
        return issecretvalue(value) == true
    end
    -- Older clients have no predicate; probe with the operations a secret
    -- value refuses. Nothing here touches the value outside the pcall.
    local ok = pcall(function()
        return value == nil or not value
    end)
    return not ok
end

-- Sets or clears a cooldown the way Blizzard_ActionBar/ActionButton.lua does:
-- "active" is a plain boolean decided by the client, and the timing values are
-- forwarded untouched so they may be secret. SetCooldown is the only thing
-- allowed to look at them, so a rejected call simply clears the swipe.
local function ApplyCooldown(cooldown, active, startTime, duration, modRate)
    if IsSecret(active) then
        active = true
    end
    if active then
        local ok = pcall(cooldown.SetCooldown, cooldown, startTime, duration, modRate)
        if ok then
            return
        end
    end
    if cooldown.Clear then
        cooldown:Clear()
    else
        cooldown:SetCooldown(0, 0)
    end
end

-- Turns a legacy (startTime, duration, enable) triple into the "active" flag
-- used by ApplyCooldown. Secret values cannot be inspected, so they are
-- handed to SetCooldown as-is; a zero duration renders as no cooldown.
local function LegacyCooldownActive(startTime, duration, enable)
    if IsSecret(enable) or IsSecret(duration) or IsSecret(startTime) then
        return true
    end
    if startTime == nil or duration == nil then
        return false
    end
    if enable == false or enable == 0 then
        return false
    end
    return duration > 0
end

local function AtlasExists(name)
    if type(name) ~= "string" or not C_Texture or type(C_Texture.GetAtlasInfo) ~= "function" then
        return false
    end
    return SafeCall(C_Texture.GetAtlasInfo, name) ~= nil
end

-- Applies a native atlas when the client has it, otherwise the bundled TGA.
-- Returns true when the native art is in use. Textures without any usable art
-- are flagged so the layout code never shows them.
local function ApplyArt(texture, atlas, fallbackFile)
    if AtlasExists(atlas) then
        texture:SetAtlas(atlas)
        texture.artAvailable = true
        return true
    end

    if atlas and not missingAtlases[atlas] then
        missingAtlases[atlas] = true
        missingAtlases.count = (missingAtlases.count or 0) + 1
    end

    if fallbackFile then
        texture:SetTexture(fallbackFile)
        texture.artAvailable = true
    else
        texture:SetTexture(nil)
        texture.artAvailable = false
    end
    return false
end

local function GetNativeCVarBool(name, default)
    local value
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        value = SafeCall(C_CVar.GetCVar, name)
    elseif type(GetCVar) == "function" then
        value = SafeCall(GetCVar, name)
    end

    if value == nil then
        return default
    end
    return value == "1" or value == 1 or value == true
end

-- Native crossbar geometry (Blizzard_GamepadActionBars/ActionBarTemplates.xml
-- and MainActionBarFrame.xml). GamepadMainActionBarFrame is 656 x 202 and sits
-- 25 units above the bottom of the screen; its four bars form a cross around
-- its centre: BASE on top (0, 58), LT left (-195, 0), RT right (195, 0) and
-- LT + RT at the bottom (0, -58). Each bar has a d-pad group on the left and a
-- face-button group on the right, whose inner slots are only 18 units apart,
-- so a 2 x 2 paddle grid cannot sit inside that gap. Instead every paddle
-- group is centred on its own bar and nested in the notch above the two inner
-- slots (the top d-pad and top face-button slots leave 80+ units of free width
-- there). LT + RT uses the free box in the middle of the cross, between the
-- BASE and LT + RT bars. All offsets are grid centres relative to the
-- crossbar's centre and are chosen so the expanded (focused) grid still
-- clears the expanded native slots.
local NATIVE_CROSSBAR_FRAME = "GamepadMainActionBarFrame"
local NATIVE_CROSSBAR_CENTER_Y = 25 + (202 / 2)
local DEFAULT_GRID_CENTERS = {
    [1] = { x = 0, y = 58 + 68 },   -- BASE: above the top bar
    [2] = { x = -195, y = 68 },     -- LT: above the left bar
    [3] = { x = 195, y = 68 },      -- RT: above the right bar
    [4] = { x = 0, y = 2 },         -- LT + RT: centre of the cross
}

local function DefaultPanelPosition(panelIndex)
    local center = DEFAULT_GRID_CENTERS[panelIndex] or DEFAULT_GRID_CENTERS[1]
    return {
        point = "CENTER",
        relativeTo = NATIVE_CROSSBAR_FRAME,
        relativePoint = "CENTER",
        x = center.x,
        -- The grid is drawn LAYOUT.GRID_CENTER_Y above the panel's centre.
        y = center.y - LAYOUT.GRID_CENTER_Y,
    }
end

-- Positions used by 0.6 / 0.7: panels flanking the crossbar on both sides.
local function LegacyDefaultPanelPosition(panelIndex)
    local outer = 328 + 16 + (LAYOUT.PANEL_WIDTH / 2)
    local inner = outer + LAYOUT.PANEL_WIDTH + 20
    local offsets = { -inner, -outer, outer, inner }
    return { point = "BOTTOM", relativePoint = "BOTTOM", x = offsets[panelIndex] or 0, y = 40 }
end

local function IsLegacyDefaultPosition(pos, panelIndex)
    local legacy = LegacyDefaultPanelPosition(panelIndex)
    return type(pos) == "table"
        and pos.relativeTo == nil
        and (pos.point or "BOTTOM") == legacy.point
        and (pos.relativePoint or "BOTTOM") == legacy.relativePoint
        and math.abs((tonumber(pos.x) or 0) - legacy.x) < 0.5
        and math.abs((tonumber(pos.y) or 0) - legacy.y) < 0.5
end

-- Resolves a stored position to something SetPoint accepts. Positions are
-- normally relative to the native crossbar so they follow it if it is moved
-- or scaled; when that frame does not exist the same spot is computed
-- relative to the bottom of the screen instead.
local function ResolvePanelAnchor(pos)
    local relativeTo = pos.relativeTo and _G[pos.relativeTo] or nil
    if relativeTo and type(relativeTo.GetObjectType) == "function" then
        return pos.point or "CENTER", relativeTo, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0
    end
    if pos.relativeTo == NATIVE_CROSSBAR_FRAME then
        return pos.point or "CENTER", UIParent, "BOTTOM", pos.x or 0, (pos.y or 0) + NATIVE_CROSSBAR_CENTER_Y
    end
    return pos.point or "BOTTOM", UIParent, pos.relativePoint or "BOTTOM", pos.x or 0, pos.y or 40
end

local function EnsureDatabase()
    PaddleSlotsDB = PaddleSlotsDB or {}
    local previousVersion = tonumber(PaddleSlotsDB.version) or 0
    -- Every build since 0.7.1 writes a version. A profile that has data but no
    -- version is therefore older, so it still needs the 0.7.1 migration.
    if PaddleSlotsDB.version == nil and next(PaddleSlotsDB) ~= nil then
        previousVersion = 7
    end
    PaddleSlotsDB.version = 8
    PaddleSlotsDB.unlocked = PaddleSlotsDB.unlocked == true

    if PaddleSlotsDB.hudScale == nil then
        PaddleSlotsDB.hudScale = 1.0
    end
    if PaddleSlotsDB.inactiveOpacity == nil then
        PaddleSlotsDB.inactiveOpacity = 1.0
    end
    if PaddleSlotsDB.highlightActivePanel == nil then
        PaddleSlotsDB.highlightActivePanel = true
    end
    if PaddleSlotsDB.highlightStrength == nil then
        PaddleSlotsDB.highlightStrength = 1.0
    end
    if PaddleSlotsDB.showPaddleBadges == nil then
        PaddleSlotsDB.showPaddleBadges = true
    end
    if PaddleSlotsDB.showPanelLabels == nil then
        PaddleSlotsDB.showPanelLabels = false
    end
    if PaddleSlotsDB.gamepadOnly == nil then
        PaddleSlotsDB.gamepadOnly = true
    end

    PaddleSlotsDB.paddleKeys = PaddleSlotsDB.paddleKeys or {}
    for paddleIndex = 1, PADDLE_COUNT do
        local key = PaddleSlotsDB.paddleKeys["P" .. paddleIndex]
        if type(key) ~= "string" or key == "" then
            PaddleSlotsDB.paddleKeys["P" .. paddleIndex] = "PADPADDLE" .. paddleIndex
        end
    end

    -- 0.7 adopts the native crossbar look, where unfocused bars are collapsed
    -- rather than dimmed. Existing profiles are moved to that default once.
    if previousVersion > 0 and previousVersion < 7 then
        PaddleSlotsDB.inactiveOpacity = 1.0
    end

    -- 0.7.1 nests the panels in the native crossbar, which already shows the
    -- LT / RT / LT + RT prompts under its own bars, so the addon's copies of
    -- those prompts become opt-in. Panels that still sit at the 0.6 / 0.7
    -- default spots move to the new layout; panels the user moved are kept.
    if previousVersion > 0 and previousVersion < 8 then
        PaddleSlotsDB.showPanelLabels = false
        PaddleSlotsDB.migrateLegacyPanelPositions = true
    end

    PaddleSlotsDB.hudScale = math.max(0.65, math.min(1.50, tonumber(PaddleSlotsDB.hudScale) or 1.0))
    PaddleSlotsDB.inactiveOpacity = math.max(0.10, math.min(1.0, tonumber(PaddleSlotsDB.inactiveOpacity) or 1.0))
    PaddleSlotsDB.highlightStrength = math.max(0.0, math.min(1.0, tonumber(PaddleSlotsDB.highlightStrength) or 1.0))
    PaddleSlotsDB.panelPositions = PaddleSlotsDB.panelPositions or {}

    -- Up to 0.7.6 the actions and reserved native slots lived here, account-wide.
    -- They are now per character (see EnsureCharacterDatabase), but the account
    -- copies are kept so every character can migrate them on its first login.
    PaddleSlotsDB.nativeSlots = PaddleSlotsDB.nativeSlots or {}
    PaddleSlotsDB.fallbackActions = PaddleSlotsDB.fallbackActions or {}
    for panelIndex = 1, PANEL_COUNT do
        PaddleSlotsDB.fallbackActions[panelIndex] = PaddleSlotsDB.fallbackActions[panelIndex] or {}
    end

    -- Migrate the original four-slot layout into the BASE panel if present.
    if PaddleSlotsDB.buttons and not PaddleSlotsDB.migratedLegacyButtons then
        for paddleIndex = 1, PADDLE_COUNT do
            local old = PaddleSlotsDB.buttons[paddleIndex]
            if old and old.action and not PaddleSlotsDB.fallbackActions[1][paddleIndex] then
                PaddleSlotsDB.fallbackActions[1][paddleIndex] = old.action
            end
        end
        PaddleSlotsDB.migratedLegacyButtons = true
    end

    -- v0.5 stored one position for the complete strip. Preserve that placement
    -- while splitting the four panels into independently movable frames.
    if not PaddleSlotsDB.migratedPanelPositions then
        local oldPosition = PaddleSlotsDB.position
        if type(oldPosition) == "table" then
            local legacyWidth = 114
            local legacyGap = 14
            local totalWidth = (legacyWidth * PANEL_COUNT) + (legacyGap * (PANEL_COUNT - 1))
            local firstCenter = -(totalWidth / 2) + (legacyWidth / 2)
            for panelIndex = 1, PANEL_COUNT do
                if not PaddleSlotsDB.panelPositions[panelIndex] then
                    PaddleSlotsDB.panelPositions[panelIndex] = {
                        point = "BOTTOM",
                        relativePoint = "BOTTOM",
                        x = (tonumber(oldPosition.x) or 0) + firstCenter + ((panelIndex - 1) * (legacyWidth + legacyGap)),
                        y = tonumber(oldPosition.y) or 115,
                    }
                end
            end
        end
        PaddleSlotsDB.migratedPanelPositions = true
    end

    for panelIndex = 1, PANEL_COUNT do
        local pos = PaddleSlotsDB.panelPositions[panelIndex]
        if type(pos) ~= "table" or (PaddleSlotsDB.migrateLegacyPanelPositions and IsLegacyDefaultPosition(pos, panelIndex)) then
            pos = DefaultPanelPosition(panelIndex)
            PaddleSlotsDB.panelPositions[panelIndex] = pos
        end
        local default = DefaultPanelPosition(panelIndex)
        pos.point = pos.point or default.point
        pos.relativePoint = pos.relativePoint or default.relativePoint
        pos.x = tonumber(pos.x) or default.x
        pos.y = tonumber(pos.y) or default.y
        if type(pos.relativeTo) ~= "string" then
            pos.relativeTo = nil
        end
    end
    PaddleSlotsDB.migrateLegacyPanelPositions = nil
end

local function CopyTable(source)
    if type(source) ~= "table" then
        return source
    end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = CopyTable(value)
    end
    return copy
end

-- Actions and reserved native slots are per character: a spell that one class
-- knows is nothing another class can cast, and action slot contents differ per
-- character anyway. Before 0.7.7 both lived account-wide in PaddleSlotsDB, so a
-- character that has no per-character table yet takes a copy of those values
-- once. That keeps whatever it saw before the update. Wrong-class spells that
-- came along can be cleared with /paddles clear.
local function EnsureCharacterDatabase()
    PaddleSlotsCharDB = PaddleSlotsCharDB or {}
    local db = PaddleSlotsCharDB

    if db.version == nil then
        if type(PaddleSlotsDB.fallbackActions) == "table" and type(db.fallbackActions) ~= "table" then
            db.fallbackActions = CopyTable(PaddleSlotsDB.fallbackActions)
        end
        if type(PaddleSlotsDB.nativeSlots) == "table" and type(db.nativeSlots) ~= "table" then
            db.nativeSlots = CopyTable(PaddleSlotsDB.nativeSlots)
        end
        local copiedActions = false
        for _, panelActions in pairs(db.fallbackActions or {}) do
            if type(panelActions) == "table" and next(panelActions) ~= nil then
                copiedActions = true
            end
        end
        if copiedActions or next(db.nativeSlots or {}) ~= nil then
            db.migratedFromAccount = true
        end
    end
    db.version = 1

    db.nativeSlots = db.nativeSlots or {}
    db.fallbackActions = db.fallbackActions or {}
    for panelIndex = 1, PANEL_COUNT do
        db.fallbackActions[panelIndex] = db.fallbackActions[panelIndex] or {}
    end
end

local function IsEditable()
    return (PaddleSlotsDB and PaddleSlotsDB.unlocked == true) or editModeActive
end

-- Returns the binding key a paddle listens for, or nil when unassigned.
local function GetPaddleKey(paddleIndex)
    local key = PaddleSlotsDB and PaddleSlotsDB.paddleKeys and PaddleSlotsDB.paddleKeys["P" .. paddleIndex]
    if type(key) ~= "string" then
        return nil
    end
    key = key:upper()
    if key == "" or key == "NONE" or NATIVE_RESERVED_KEYS[key] then
        return nil
    end
    return key
end

local function GetKeyDisplayName(key)
    if not key or key == "" or key:upper() == "NONE" then
        return "Not assigned"
    end
    key = key:upper()
    for _, option in ipairs(PADDLE_KEY_OPTIONS) do
        if option.value == key then
            return option.label
        end
    end
    if NATIVE_RESERVED_KEYS[key] then
        return NATIVE_RESERVED_KEYS[key]
    end
    return "Keyboard " .. key
end

local function GetKeyNote(key)
    key = key and key:upper() or ""
    for _, option in ipairs(PADDLE_KEY_OPTIONS) do
        if option.value == key then
            return option.note
        end
    end
    if NATIVE_RESERVED_KEYS[key] then
        return "Used by the native gamepad UI; paddles cannot take it over."
    end
    return nil
end

-- Returns true when a key may drive a paddle, otherwise false and a reason.
-- Allowed: the native paddle keys, Share, extra face buttons, F13-F24, and
-- keyboard keys that currently have no binding at all.
local function IsPaddleKeyAllowed(key)
    key = key and key:upper() or ""
    if key == "" or key == "NONE" then
        return true
    end
    if NATIVE_RESERVED_KEYS[key] then
        return false, string.format(
            "%s is used by the native gamepad UI, so it cannot drive a paddle. The controller is sending this paddle as %s: in Xbox Accessories map the paddle to a keyboard key WoW does not use (F9-F12 for example) or to Share.",
            NATIVE_RESERVED_KEYS[key], NATIVE_RESERVED_KEYS[key]
        )
    end
    for _, option in ipairs(PADDLE_KEY_OPTIONS) do
        if option.value == key and (key:match("^PAD") or key:match("^F1[3-9]$") or key:match("^F2[0-4]$")) then
            return true
        end
    end
    if key:match("^PAD") then
        return false, key .. " is a controller input the addon does not know; only Share, extra face buttons, and the native paddle keys are allowed."
    end

    -- Look at the regular binding only; the addon's own override bindings
    -- (CLICK PaddleSlotsButton...) must not block reassigning a paddle.
    local action = type(GetBindingAction) == "function" and GetBindingAction(key, false) or nil
    if action and action:match("^CLICK PaddleSlots") then
        action = nil
    end
    if action and action ~= "" then
        local actionName = action
        if type(GetBindingName) == "function" then
            actionName = GetBindingName(action) or action
        end
        return false, string.format(
            "Keyboard key %s is already bound to %s. Map the paddle to an unused key such as F9-F12 instead.",
            key, tostring(actionName)
        )
    end
    return true
end

local function SetPanelPosition(panelIndex)
    local panel = panelFrames[panelIndex]
    if not panel then
        return
    end

    local pos = PaddleSlotsDB.panelPositions[panelIndex] or DefaultPanelPosition(panelIndex)
    panel:ClearAllPoints()
    panel:SetPoint(ResolvePanelAnchor(pos))
end

local function SavePanelPosition(panelIndex)
    local panel = panelFrames[panelIndex]
    if not panel then
        return
    end

    local point, relativeTo, relativePoint, x, y = panel:GetPoint(1)
    if not point then
        return
    end

    -- Dragging re-anchors the panel to UIParent, so only a position that is
    -- still attached to the native crossbar keeps its frame reference.
    local relativeName = relativeTo and relativeTo ~= UIParent and type(relativeTo.GetName) == "function" and relativeTo:GetName() or nil
    PaddleSlotsDB.panelPositions[panelIndex] = {
        point = point,
        relativeTo = relativeName == NATIVE_CROSSBAR_FRAME and relativeName or nil,
        relativePoint = relativePoint or point,
        x = x or 0,
        y = y or 0,
    }
end

local UpdatePanelVisibility -- defined below

local function UpdateEditOverlays()
    local editable = IsEditable()
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel and panel.editOverlay then
            panel.editOverlay:SetShown(editable)
        end
    end
    if UpdatePanelVisibility then
        UpdatePanelVisibility()
    end
end

local function IsGamepadInterfaceActive()
    if C_InputInterfaceStyle and type(C_InputInterfaceStyle.GetCurrentStyle) == "function" then
        local style = SafeCall(C_InputInterfaceStyle.GetCurrentStyle)
        if style ~= nil then
            local gamepad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad or 1
            return style == gamepad
        end
    end
    if type(IsGamePadEnabled) == "function" then
        return SafeCall(IsGamePadEnabled) == true
    end
    return true
end

-- Hides the panels outside gamepad mode unless they are being positioned.
-- The panels parent secure action buttons, so showing or hiding them is a
-- protected action; in combat it waits for PLAYER_REGEN_ENABLED.
UpdatePanelVisibility = function()
    if InCombatLockdown() then
        pendingAppearanceRefresh = true
        return
    end

    local shown = PaddleSlotsDB.gamepadOnly == false or IsGamepadInterfaceActive() or IsEditable()
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel then
            panel:SetShown(shown)
        end
    end
end

local function IsValidNativeStorageSlot(slot)
    if not C_GamepadUI or type(C_GamepadUI.IsValidGamepadActionStorageSlotIndex) ~= "function" then
        return false
    end
    return SafeCall(C_GamepadUI.IsValidGamepadActionStorageSlotIndex, slot) == true
end

local function DiscoverNativeStorageSlots()
    if not C_GamepadUI
        or type(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex) ~= "function"
        or type(C_GamepadUI.IsValidGamepadActionStorageSlotIndex) ~= "function" then
        return nil
    end

    local first = SafeCall(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex)
    if type(first) ~= "number" then
        return nil
    end

    local petStart = SafeCall(C_GamepadUI.GetFirstGamepadPetActionStorageSlotIndex)
    local valid = {}
    local seenValid = false
    local invalidRun = 0

    for slot = first, first + STORAGE_SCAN_LIMIT do
        -- Pet storage is a separate range on Forever (for example pet=11 while
        -- general gamepad storage starts around 181). Only treat it as an upper
        -- boundary when it actually follows the general storage range.
        if type(petStart) == "number" and petStart > first and slot >= petStart then
            break
        end

        if IsValidNativeStorageSlot(slot) then
            valid[#valid + 1] = slot
            seenValid = true
            invalidRun = 0
        elseif seenValid then
            invalidRun = invalidRun + 1
            if invalidRun >= STORAGE_STOP_AFTER_INVALID then
                break
            end
        end
    end

    return valid
end

local function SavedNativeSlotsAreUsable()
    local saved = PaddleSlotsCharDB.nativeSlots
    if type(saved) ~= "table" or #saved ~= PANEL_COUNT * PADDLE_COUNT then
        return false
    end

    local seen = {}
    for _, slot in ipairs(saved) do
        if type(slot) ~= "number" or not IsValidNativeStorageSlot(slot) or seen[slot] then
            return false
        end
        seen[slot] = true
    end

    return true
end

local function HasFallbackActions()
    for panelIndex = 1, PANEL_COUNT do
        local panelActions = PaddleSlotsCharDB.fallbackActions and PaddleSlotsCharDB.fallbackActions[panelIndex]
        if panelActions then
            for paddleIndex = 1, PADDLE_COUNT do
                if panelActions[paddleIndex] then
                    return true
                end
            end
        end
    end
    return false
end

local function InitializeNativeStorage()
    nativeStorageEnabled = false
    nativeStorageSlots = {}
    nativeStorageStatus = "unavailable"

    if SavedNativeSlotsAreUsable() then
        for i, slot in ipairs(PaddleSlotsCharDB.nativeSlots) do
            nativeStorageSlots[i] = slot
        end
        nativeStorageEnabled = true
        nativeStorageStatus = "using previously reserved C_GamepadUI slots"
        return
    end

    -- Do not silently switch an existing SavedVariables profile to native action
    -- slots; doing so would make already assigned fallback actions appear empty.
    -- New/empty profiles can use native storage immediately.
    if HasFallbackActions() then
        nativeStorageStatus = "preserving existing SavedVariables actions"
        return
    end

    local valid = DiscoverNativeStorageSlots()
    if not valid then
        nativeStorageStatus = "C_GamepadUI action storage API unavailable"
        return
    end
    if #valid < MIN_NATIVE_STORAGE_POOL then
        nativeStorageStatus = string.format("native pool too small (%d valid slots)", #valid)
        return
    end

    -- Reserve empty slots from the high end of the dedicated gamepad storage pool.
    -- This deliberately avoids overwriting anything Blizzard/the player already uses.
    local chosen = {}
    for i = #valid, 1, -1 do
        local slot = valid[i]
        if not C_ActionBar.HasAction(slot) then
            table.insert(chosen, 1, slot)
            if #chosen == PANEL_COUNT * PADDLE_COUNT then
                break
            end
        end
    end

    if #chosen ~= PANEL_COUNT * PADDLE_COUNT then
        nativeStorageStatus = string.format("only %d unused native slots found", #chosen)
        return
    end

    PaddleSlotsCharDB.nativeSlots = chosen
    for i, slot in ipairs(chosen) do
        nativeStorageSlots[i] = slot
    end
    nativeStorageEnabled = true
    nativeStorageStatus = "using newly reserved C_GamepadUI slots"
end

local function FlatButtonIndex(panelIndex, paddleIndex)
    return ((panelIndex - 1) * PADDLE_COUNT) + paddleIndex
end

local function GetNativeSlot(panelIndex, paddleIndex)
    return nativeStorageSlots[FlatButtonIndex(panelIndex, paddleIndex)]
end

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
        pendingSecureRefresh = true
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
        pendingSecureRefresh = true
        return
    end

    if button.actionSlot then
        button:SetAttribute("type", "action")
        button:SetAttribute("action", button.actionSlot)
    else
        ApplyFallbackSecureAction(button)
    end
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
    if nativeStorageEnabled then
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

    if nativeStorageEnabled then
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

local function SetModifierIconFocused(panel, focused)
    local icon = panel.modifierIcon
    if not icon then
        return
    end

    if focused then
        if type(icon.SetFocused) == "function" then
            pcall(icon.SetFocused, icon)
        end
    elseif type(icon.SetPressable) == "function" then
        pcall(icon.SetPressable, icon)
    end
end

-- Uses Blizzard's InputIconTextureFrameTemplate so the LT / RT prompts follow
-- the connected controller's glyph style exactly like the native crossbar.
local function CreateModifierIcon(panel, panelInfo)
    if not panelInfo.lt and not panelInfo.rt then
        return nil
    end

    local leftKey = GAMEPAD_TRIGGER_LEFT or "PADLTRIGGER"
    local rightKey = GAMEPAD_TRIGGER_RIGHT or "PADRTRIGGER"
    local frame

    if panelInfo.lt and panelInfo.rt then
        local ok, created = pcall(CreateFrame, "Frame", nil, panel, "InputPromptTwoIconTemplate")
        if ok and created and type(created.SetPromptInputIconKey) == "function" then
            local configured = pcall(function()
                created:SetPromptInputIconKey(1, leftKey)
                created:SetPromptInputIconKey(2, rightKey)
                if type(created.SetUseDropShadow) == "function" then
                    created:SetUseDropShadow(true)
                end
            end)
            if configured then
                frame = created
            else
                created:Hide()
            end
        elseif ok and created then
            created:Hide()
        end
    else
        local ok, created = pcall(CreateFrame, "Frame", nil, panel, "InputIconTextureFrameTemplate")
        if ok and created and type(created.SetInputKey) == "function" then
            local configured = pcall(function()
                created:SetInputKey(panelInfo.lt and leftKey or rightKey)
                if type(created.EnableDropShadow) == "function" then
                    created:EnableDropShadow()
                end
            end)
            if configured then
                frame = created
            else
                created:Hide()
            end
        elseif ok and created then
            created:Hide()
        end
    end

    if not frame then
        -- Text fallback for clients without the gamepad prompt templates.
        frame = CreateFrame("Frame", nil, panel)
        frame:SetSize(48, 16)
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.text:SetPoint("CENTER")
        frame.text:SetText(panelInfo.label)
        frame.SetFocused = function(self)
            self.text:SetTextColor(1, 0.82, 0)
        end
        frame.SetPressable = function(self)
            self.text:SetTextColor(0.62, 0.62, 0.62)
        end
        frame:SetPressable()
    end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", panel, "CENTER", 0, LAYOUT.MODIFIER_ICON_Y)
    return frame
end

local function SetPanelActiveVisual(panelIndex, isActive)
    local panel = panelFrames[panelIndex]
    if not panel then
        return
    end

    local scalingEnabled = GetNativeCVarBool(NATIVE_CVAR_SCALING, true)
    local highlightEnabled = PaddleSlotsDB.highlightActivePanel ~= false and GetNativeCVarBool(NATIVE_CVAR_HIGHLIGHT, true)
    local expanded = isActive and scalingEnabled
    local wasExpanded = panel.expanded == true

    panel.isActive = isActive
    panel.expanded = expanded

    local inactiveOpacity = PaddleSlotsDB.inactiveOpacity or 1.0
    panel:SetAlpha(IsEditable() and 1 or (isActive and 1 or inactiveOpacity))

    panel.focusBackground:SetAlpha(LAYOUT.FOCUS_BACKGROUND_ALPHA * (PaddleSlotsDB.highlightStrength or 1.0))
    panel.focusBackground:SetShown(isActive and highlightEnabled and panel.focusBackground.artAvailable)

    if panel.modifierIcon then
        panel.modifierIcon:SetShown(PaddleSlotsDB.showPanelLabels ~= false)
        SetModifierIconFocused(panel, isActive)
    end

    if expanded and not wasExpanded then
        -- Native focus: the focus shadow starts fully opaque and settles to 0.4.
        panel.focusFadeStart = GetTime()
    elseif not expanded then
        panel.focusFadeStart = nil
    end

    for paddleIndex = 1, PADDLE_COUNT do
        local button = buttons[panelIndex][paddleIndex]
        if button then
            LayoutButtonVisual(button)
            if expanded and not wasExpanded then
                button.visual.shadowFocus:SetAlpha(1)
            end
            UpdatePromptVisibility(button)
        end
    end
end

local function UpdateFocusFades()
    local now = GetTime()
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel and panel.focusFadeStart then
            local progress = (now - panel.focusFadeStart) / LAYOUT.FOCUS_FADE_DURATION
            local alpha
            if progress >= 1 then
                alpha = LAYOUT.FOCUS_SHADOW_MIN_ALPHA
                panel.focusFadeStart = nil
            else
                alpha = 1 - ((1 - LAYOUT.FOCUS_SHADOW_MIN_ALPHA) * progress)
            end

            for paddleIndex = 1, PADDLE_COUNT do
                local button = buttons[panelIndex][paddleIndex]
                if button then
                    button.visual.shadowFocus:SetAlpha(alpha)
                end
            end
        end
    end
end

local function UpdatePanelVisualState(panelIndex, force)
    if not force and lastVisualPanel == panelIndex then
        return
    end

    lastVisualPanel = panelIndex
    for i = 1, PANEL_COUNT do
        SetPanelActiveVisual(i, i == panelIndex)
    end
end

local function CreatePanelFrame(panelIndex)
    local panelInfo = PANELS[panelIndex]
    local panel = CreateFrame("Frame", "PaddleSlotsPanel" .. panelIndex, UIParent)
    panel.panelIndex = panelIndex
    panel.expanded = false
    panel:SetSize(LAYOUT.PANEL_WIDTH, LAYOUT.PANEL_HEIGHT)
    panel:SetFrameStrata("LOW")
    -- The panels nest inside the native crossbar; keep them above its slots so
    -- an expanded paddle grid never disappears behind a native ring.
    panel:SetFrameLevel(40)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    -- Registered before the slots are created so their first layout pass works.
    panelFrames[panelIndex] = panel

    -- Soft highlight the native crossbar draws behind the focused bar.
    panel.focusBackground = panel:CreateTexture(nil, "BACKGROUND", nil, -2)
    panel.focusBackground:SetSize(LAYOUT.FOCUS_BACKGROUND_WIDTH, LAYOUT.FOCUS_BACKGROUND_HEIGHT)
    panel.focusBackground:SetPoint("CENTER", panel, "CENTER", 0, LAYOUT.GRID_CENTER_Y)
    if not ApplyArt(panel.focusBackground, ATLAS.focusBackground, nil) then
        panel.focusBackground:SetColorTexture(0.68, 0.45, 0.08, 0.6)
        panel.focusBackground:SetSize(LAYOUT.PANEL_WIDTH - 20, LAYOUT.PANEL_WIDTH - 20)
        panel.focusBackground.artAvailable = true
    end
    panel.focusBackground:Hide()

    for paddleIndex = 1, PADDLE_COUNT do
        local button = CreateActionButton(panelIndex, paddleIndex, panel)
        local x, y = GetButtonCenter(paddleIndex, true)
        button:SetPoint("CENTER", panel, "CENTER", x, y)
    end

    panel.modifierIcon = CreateModifierIcon(panel, panelInfo)

    panel.editOverlay = CreateFrame("Button", nil, panel)
    panel.editOverlay:SetAllPoints()
    panel.editOverlay:SetFrameLevel(panel:GetFrameLevel() + 50)
    panel.editOverlay:RegisterForDrag("LeftButton", "RightButton")
    panel.editOverlay:Hide()

    panel.editOverlay.fill = panel.editOverlay:CreateTexture(nil, "BACKGROUND")
    if ApplyArt(panel.editOverlay.fill, ATLAS.editGlow, nil) then
        panel.editOverlay.fill:SetSize(LAYOUT.PANEL_WIDTH + 44, LAYOUT.PANEL_WIDTH + 44)
        panel.editOverlay.fill:SetPoint("CENTER", panel, "CENTER", 0, LAYOUT.GRID_CENTER_Y)
        panel.editOverlay.fill:SetAlpha(0.5)
    else
        panel.editOverlay.fill:SetAllPoints()
        panel.editOverlay.fill:SetColorTexture(0.95, 0.72, 0.16, 0.10)
    end

    local function CreateEdge(point1, point2, isHorizontal)
        local edge = panel.editOverlay:CreateTexture(nil, "OVERLAY")
        edge:SetPoint(point1.point, point1.x, point1.y)
        edge:SetPoint(point2.point, point2.x, point2.y)
        if isHorizontal then
            edge:SetHeight(2)
        else
            edge:SetWidth(2)
        end
        edge:SetColorTexture(1.0, 0.82, 0.28, 0.95)
        return edge
    end

    panel.editOverlay.top = CreateEdge({ point = "TOPLEFT", x = -2, y = 2 }, { point = "TOPRIGHT", x = 2, y = 2 }, true)
    panel.editOverlay.bottom = CreateEdge({ point = "BOTTOMLEFT", x = -2, y = -2 }, { point = "BOTTOMRIGHT", x = 2, y = -2 }, true)
    panel.editOverlay.left = CreateEdge({ point = "TOPLEFT", x = -2, y = 2 }, { point = "BOTTOMLEFT", x = -2, y = -2 }, false)
    panel.editOverlay.right = CreateEdge({ point = "TOPRIGHT", x = 2, y = 2 }, { point = "BOTTOMRIGHT", x = 2, y = -2 }, false)

    panel.editOverlay.text = panel.editOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.editOverlay.text:SetPoint("CENTER", panel, "CENTER", 0, LAYOUT.GRID_CENTER_Y)
    panel.editOverlay.text:SetText(panelInfo.label .. "\nDRAG TO MOVE")

    panel.editOverlay:SetScript("OnDragStart", function()
        if not IsEditable() then
            return
        end
        if InCombatLockdown() then
            Print("Paddle panels cannot be moved during combat.")
            return
        end
        panel:StartMoving()
    end)

    panel.editOverlay:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        SavePanelPosition(panelIndex)
    end)

    SetPanelPosition(panelIndex)
    return panel
end

local function CreateUI()
    for panelIndex = 1, PANEL_COUNT do
        buttons[panelIndex] = {}
        CreatePanelFrame(panelIndex)
    end

    UpdatePanelVisualState(1, true)
    UpdateEditOverlays()
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

-- All binding strings a paddle must answer to: the bare key plus every
-- combination of the emulated LT/RT modifiers. While a trigger is held the
-- client resolves "SHIFT-F9" before "F9", and the layer driver already picks
-- the right panel, so every variant points at the same slot.
local function GetPaddleBindingKeys(paddleIndex)
    local key = GetPaddleKey(paddleIndex)
    if not key then
        return {}
    end

    local modifiers = {}
    for _, modifier in ipairs({ ltModifier, rtModifier }) do
        if type(modifier) == "string" then
            local upper = modifier:upper()
            if not tContains(modifiers, upper) then
                modifiers[#modifiers + 1] = upper
            end
        end
    end
    table.sort(modifiers) -- ALT < CTRL < SHIFT, the client's canonical order

    local keys = { key }
    if #modifiers >= 1 then
        for _, modifier in ipairs(modifiers) do
            keys[#keys + 1] = modifier .. "-" .. key
        end
    end
    if #modifiers >= 2 then
        keys[#keys + 1] = table.concat(modifiers, "-") .. "-" .. key
    end
    return keys
end

-- The secure layer driver reads the paddle keys from attributes.
local function WriteSecureKeyAttributes()
    for paddleIndex = 1, PADDLE_COUNT do
        local keys = GetPaddleBindingKeys(paddleIndex)
        secureDriver:SetAttribute("paddleKeyCount" .. paddleIndex, #keys)
        for n = 1, #keys do
            secureDriver:SetAttribute("paddleKey" .. paddleIndex .. "_" .. n, keys[n])
        end
    end
end

local function BindPaddlesToPanel(panelIndex)
    panelIndex = tonumber(panelIndex) or 1
    if panelIndex < 1 or panelIndex > PANEL_COUNT then
        panelIndex = 1
    end

    if InCombatLockdown() then
        pendingSecureRefresh = true
        return
    end

    ClearOverrideBindings(secureDriver)
    for paddleIndex = 1, PADDLE_COUNT do
        local button = buttons[panelIndex][paddleIndex]
        for _, key in ipairs(GetPaddleBindingKeys(paddleIndex)) do
            SetOverrideBindingClick(secureDriver, true, key, button:GetName(), "LeftButton")
        end
    end
    secureDriver:SetAttribute("activePanel", panelIndex)
    lastBoundPanel = panelIndex
end

local function RegisterSecureFrameRefs()
    if InCombatLockdown() then
        pendingSecureRefresh = true
        return
    end

    for panelIndex = 1, PANEL_COUNT do
        for paddleIndex = 1, PADDLE_COUNT do
            secureDriver:SetFrameRef(
                string.format("P%dB%d", panelIndex, paddleIndex),
                buttons[panelIndex][paddleIndex]
            )
        end
    end

    WriteSecureKeyAttributes()
    secureDriver:SetAttribute("activePanel", 1)
end

local SECURE_STATE_BINDINGS = [[
    local panel = tonumber(newstate) or 1
    if panel < 1 or panel > 4 then
        panel = 1
    end

    self:SetAttribute("activePanel", panel)
    self:ClearBindings()
    for i = 1, 4 do
        local ref = self:GetFrameRef("P" .. panel .. "B" .. i)
        local count = tonumber(self:GetAttribute("paddleKeyCount" .. i)) or 0
        if ref then
            for n = 1, count do
                local key = self:GetAttribute("paddleKey" .. i .. "_" .. n)
                if key and key ~= "" then
                    self:SetBindingClick(true, key, ref, "LeftButton")
                end
            end
        end
    end
]]

local function GetGamepadEmulationCVar(name)
    local value
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        value = SafeCall(C_CVar.GetCVar, name)
    elseif type(GetCVar) == "function" then
        value = SafeCall(GetCVar, name)
    end
    return type(value) == "string" and value:upper() or nil
end

local function FindEmulatedModifier(buttonName)
    buttonName = buttonName and buttonName:upper()
    if not buttonName then
        return nil
    end

    local mappings = {
        { cvar = "GamePadEmulateShift", modifier = "shift" },
        { cvar = "GamePadEmulateCtrl", modifier = "ctrl" },
        { cvar = "GamePadEmulateAlt", modifier = "alt" },
    }

    for _, mapping in ipairs(mappings) do
        if GetGamepadEmulationCVar(mapping.cvar) == buttonName then
            return mapping.modifier
        end
    end
    return nil
end

local function SetupSecurePanelDriver()
    if InCombatLockdown() then
        nativeHookStatus = "modifier driver deferred until combat ends"
        pendingSecureRefresh = true
        return false
    end

    if securePanelDriverRegistered then
        pcall(UnregisterStateDriver, secureDriver, "paddlepanel")
        securePanelDriverRegistered = false
    end

    ltModifier = FindEmulatedModifier("PADLTRIGGER")
    rtModifier = FindEmulatedModifier("PADRTRIGGER")

    if not ltModifier or not rtModifier or ltModifier == rtModifier then
        nativeHookStatus = string.format(
            "native modifier mapping incomplete (LT=%s, RT=%s); using mapped-state fallback out of combat",
            tostring(ltModifier),
            tostring(rtModifier)
        )
        return false
    end

    WriteSecureKeyAttributes()
    secureDriver:SetAttribute("_onstate-paddlepanel", SECURE_STATE_BINDINGS)

    local driver = string.format(
        "[mod:%s,mod:%s] 4; [mod:%s] 2; [mod:%s] 3; 1",
        ltModifier,
        rtModifier,
        ltModifier,
        rtModifier
    )

    local ok = pcall(RegisterStateDriver, secureDriver, "paddlepanel", driver)
    if not ok then
        nativeHookStatus = "found LT/RT modifier mappings but failed to register secure state driver"
        return false
    end

    securePanelDriverRegistered = true
    nativeHookStatus = string.format(
        "secure native modifier driver (LT=%s, RT=%s)",
        ltModifier,
        rtModifier
    )
    return true
end

local function TryHookNativeTriggerDriver()
    -- v0.6 no longer wraps Blizzard's PADTRIGGER click frame. Forever binds LT
    -- and RT to the same native click target, so a wrapper cannot tell which
    -- physical trigger caused the click. The controller's modifier-emulation
    -- CVars are a better native signal and can drive a SecureStateDriver safely.
    return SetupSecurePanelDriver()
end

local function CacheGamepadButtonIndices()
    ltButtonIndex = SafeCall(C_GamePad and C_GamePad.ButtonBindingToIndex, "PADLTRIGGER")
    rtButtonIndex = SafeCall(C_GamePad and C_GamePad.ButtonBindingToIndex, "PADRTRIGGER")
end

local function GetMappedButtonArrayIndex(state, index)
    if not state or not state.buttons or type(index) ~= "number" then
        return nil
    end

    -- ButtonBindingToIndex returns the engine button index. Blizzard's Lua
    -- state table has differed between clients/tooling assumptions, so detect
    -- whether the returned buttons table exposes element 0 instead of guessing.
    if state.buttons[0] ~= nil then
        return index
    end
    return index + 1
end

local function GetMappedButtonDown(state, index)
    local arrayIndex = GetMappedButtonArrayIndex(state, index)
    return arrayIndex ~= nil and state.buttons[arrayIndex] == true
end

local function GetMappedState()
    if not C_GamePad or type(C_GamePad.GetDeviceMappedState) ~= "function" then
        return nil
    end

    local activeID = SafeCall(C_GamePad.GetActiveDeviceID)
    local state
    if type(activeID) == "number" then
        state = SafeCall(C_GamePad.GetDeviceMappedState, activeID)
    end
    return state or SafeCall(C_GamePad.GetDeviceMappedState)
end

---------------------------------------------------------------------------
-- Raw input watcher: /paddles test and /paddles learn
---------------------------------------------------------------------------

local function GetRawState(deviceID)
    if not C_GamePad or type(C_GamePad.GetDeviceRawState) ~= "function" or type(deviceID) ~= "number" then
        return nil
    end
    local raw = SafeCall(C_GamePad.GetDeviceRawState, deviceID)
    if type(raw) == "table" and type(raw.rawButtons) == "table" then
        return raw
    end
    return nil
end

-- Finds a device that exposes raw state: the active one first, then any other.
local function FindRawInputDevice()
    local activeID = SafeCall(C_GamePad and C_GamePad.GetActiveDeviceID)
    local raw = GetRawState(activeID)
    if raw then
        return activeID, raw
    end

    local ids = SafeCall(C_GamePad and C_GamePad.GetAllDeviceIDs)
    if type(ids) == "table" then
        for _, id in ipairs(ids) do
            raw = GetRawState(id)
            if raw then
                return id, raw
            end
        end
    end
    return nil, nil
end

-- Raw button tables may be 0- or 1-based like the mapped state table; return a
-- snapshot keyed by the 0-based rawIndex used in GamePadConfig files.
local function SnapshotRawButtons(raw)
    local snapshot = {}
    local base = raw.rawButtons[0] ~= nil and 0 or 1
    local count = tonumber(raw.rawButtonCount) or #raw.rawButtons
    for rawIndex = 0, math.max(count - 1, 0) do
        snapshot[rawIndex] = raw.rawButtons[rawIndex + base] == true
    end
    return snapshot
end

local function GetDeviceConfig(vendorID, productID)
    if not C_GamePad or type(C_GamePad.GetConfig) ~= "function" then
        return nil
    end
    local config = SafeCall(C_GamePad.GetConfig, { vendorID = vendorID, productID = productID })
    if type(config) == "table" then
        return config
    end
    return nil
end

local function DescribeRawButtonMapping(config, rawIndex)
    if config and type(config.rawButtonMappings) == "table" then
        for _, mapping in ipairs(config.rawButtonMappings) do
            if mapping.rawIndex == rawIndex then
                if mapping.button and mapping.button ~= "" and mapping.button ~= "None" then
                    return mapping.button
                elseif mapping.axis then
                    return string.format("axis %s", tostring(mapping.axis))
                end
                return "None"
            end
        end
    end
    return "unmapped"
end

local function GetPaddleRawMappingDiagnostic()
    local deviceID, raw = FindRawInputDevice()
    if not raw then
        return "no raw gamepad state available"
    end

    local config = GetDeviceConfig(raw.vendorID, raw.productID)
    local parts = {}
    for paddle = 1, PADDLE_COUNT do
        local found = "none"
        if config and type(config.rawButtonMappings) == "table" then
            for _, mapping in ipairs(config.rawButtonMappings) do
                if type(mapping.button) == "string" and mapping.button:upper() == ("PADPADDLE" .. paddle) then
                    found = "raw " .. tostring(mapping.rawIndex)
                    break
                end
            end
        end
        parts[#parts + 1] = string.format("P%d=%s", paddle, found)
    end

    return string.format(
        "%s (%d:%d, device %s, %s raw buttons)   %s",
        tostring(raw.name),
        tonumber(raw.vendorID) or 0,
        tonumber(raw.productID) or 0,
        tostring(deviceID),
        tostring(raw.rawButtonCount or #raw.rawButtons),
        table.concat(parts, "  ")
    )
end

local function StopInputWatcher(message)
    if not inputWatcher then
        return
    end
    inputWatcher = nil
    if message then
        Print(message)
    end
end

local function StartInputWatcher(mode)
    local deviceID, raw = FindRawInputDevice()
    if not raw then
        Print("No gamepad raw state is available. Make sure the controller is connected and gamepad input is enabled.")
        return false
    end

    inputWatcher = {
        mode = mode,
        deviceID = deviceID,
        vendorID = raw.vendorID,
        productID = raw.productID,
        deviceName = raw.name,
        config = GetDeviceConfig(raw.vendorID, raw.productID),
        previous = SnapshotRawButtons(raw),
        startedAt = GetTime(),
        stepStartedAt = GetTime(),
        step = 1,
        results = {},
    }

    Print(string.format(
        "%s: %s (vendor %d, product %d) with %s raw buttons.",
        mode == "learn" and "Learning paddles" or "Testing raw input",
        tostring(raw.name),
        tonumber(raw.vendorID) or 0,
        tonumber(raw.productID) or 0,
        tostring(raw.rawButtonCount or #raw.rawButtons)
    ))
    return true
end

-- Writes a device config that maps the learned raw buttons to PADPADDLE1-4.
-- The client stores addon configs in GamePadConfig_AddOns.json, loaded last.
local function ApplyLearnedPaddleMapping(watcher)
    if not C_GamePad or type(C_GamePad.SetConfig) ~= "function" then
        Print("This client does not expose C_GamePad.SetConfig; write the mapping into a GamePadConfig_*.json file instead.")
        return false
    end
    if InCombatLockdown() then
        Print("Gamepad configs cannot be changed during combat. Run /paddles learn again after combat.")
        return false
    end

    local config = GetDeviceConfig(watcher.vendorID, watcher.productID) or {}
    config.configID = config.configID or { vendorID = watcher.vendorID, productID = watcher.productID }
    config.name = config.name or ("PaddleSlots mapping for " .. tostring(watcher.deviceName))
    config.comment = "Paddle buttons learned by PaddleSlots (/paddles learn)"
    config.rawButtonMappings = config.rawButtonMappings or {}
    config.rawAxisMappings = config.rawAxisMappings or {}
    config.axisConfigs = config.axisConfigs or {}
    config.stickConfigs = config.stickConfigs or {}

    local byIndex = {}
    for _, mapping in ipairs(config.rawButtonMappings) do
        byIndex[mapping.rawIndex] = mapping
        -- Release any raw button that previously carried a paddle binding.
        if type(mapping.button) == "string" and mapping.button:upper():match("^PADPADDLE%d$") then
            mapping.button = "None"
        end
    end

    for paddle = 1, PADDLE_COUNT do
        local rawIndex = watcher.results[paddle]
        local mapping = byIndex[rawIndex]
        if not mapping then
            mapping = { rawIndex = rawIndex }
            config.rawButtonMappings[#config.rawButtonMappings + 1] = mapping
            byIndex[rawIndex] = mapping
        end
        mapping.button = "PADPADDLE" .. paddle
        mapping.axis = nil
        mapping.axisValue = nil
        mapping.comment = "PaddleSlots paddle " .. paddle
    end

    local ok, err = pcall(C_GamePad.SetConfig, config)
    if not ok then
        Print("The client rejected the gamepad config: " .. tostring(err))
        return false
    end
    if type(C_GamePad.ApplyConfigs) == "function" then
        pcall(C_GamePad.ApplyConfigs)
    end

    local summary = {}
    for paddle = 1, PADDLE_COUNT do
        summary[#summary + 1] = string.format("P%d=raw %d", paddle, watcher.results[paddle])
    end
    Print("Saved paddle mapping: " .. table.concat(summary, ", ") .. ". Reload the UI if the paddles do not respond immediately.")
    return true
end

local function ClearLearnedPaddleMapping()
    if not C_GamePad or type(C_GamePad.DeleteConfig) ~= "function" then
        Print("This client does not expose C_GamePad.DeleteConfig.")
        return
    end
    if InCombatLockdown() then
        Print("Gamepad configs cannot be changed during combat.")
        return
    end

    local _, raw = FindRawInputDevice()
    if not raw then
        Print("No gamepad raw state is available.")
        return
    end

    local ok, err = pcall(C_GamePad.DeleteConfig, { vendorID = raw.vendorID, productID = raw.productID })
    if not ok then
        Print("Could not remove the device config: " .. tostring(err))
        return
    end
    if type(C_GamePad.ApplyConfigs) == "function" then
        pcall(C_GamePad.ApplyConfigs)
    end
    Print(string.format("Removed the addon gamepad config for %s. The client's default mapping is back in effect.", tostring(raw.name)))
end

local function PrintLearnPrompt(step)
    Print(string.format("Press paddle P%d now (%d seconds). Type /paddles learn cancel to stop.", step, INPUT_WATCH_LEARN_STEP_TIMEOUT))
end

local function UpdateInputWatcher()
    local watcher = inputWatcher
    if not watcher then
        return
    end

    local now = GetTime()
    if watcher.mode == "test" and now - watcher.startedAt > INPUT_WATCH_TEST_DURATION then
        StopInputWatcher("Raw input test finished.")
        return
    end
    if watcher.mode == "learn" and now - watcher.stepStartedAt > INPUT_WATCH_LEARN_STEP_TIMEOUT then
        StopInputWatcher(string.format("No press detected for P%d. Learning cancelled; nothing was changed.", watcher.step))
        return
    end

    local raw = GetRawState(watcher.deviceID)
    if not raw then
        StopInputWatcher("Lost the gamepad raw state. Stopped.")
        return
    end

    local current = SnapshotRawButtons(raw)
    local pressed = {}
    for rawIndex, down in pairs(current) do
        if down and not watcher.previous[rawIndex] then
            pressed[#pressed + 1] = rawIndex
        end
    end
    watcher.previous = current
    if #pressed == 0 then
        return
    end
    table.sort(pressed)

    if watcher.mode == "test" then
        for _, rawIndex in ipairs(pressed) do
            Print(string.format("Raw button %d pressed (client maps it to %s).", rawIndex, DescribeRawButtonMapping(watcher.config, rawIndex)))
        end
        return
    end

    -- Learn mode: one raw button per paddle, in order P1..P4.
    local rawIndex = pressed[1]
    for paddle, assigned in pairs(watcher.results) do
        if assigned == rawIndex then
            Print(string.format("Raw button %d is already P%d. Press a different paddle for P%d.", rawIndex, paddle, watcher.step))
            return
        end
    end

    -- A raw button the client already uses for something else (A/B/X/Y, D-pad,
    -- shoulders...) means the controller profile mirrors the paddle onto that
    -- button. Rebinding it would steal the button from the native UI.
    local currentMapping = DescribeRawButtonMapping(watcher.config, rawIndex)
    local isFree = currentMapping == "None"
        or currentMapping == "unmapped"
        or currentMapping:upper():match("^PADPADDLE%d$") ~= nil
    if not isFree and not watcher.force then
        Print(string.format(
            "Raw button %d is the client's %s button, so the controller is sending this paddle as %s rather than as a paddle. Learning stopped; nothing was changed.",
            rawIndex, currentMapping, currentMapping
        ))
        Print("Unassign the paddles in the Xbox Accessories app (or switch the profile slot off), reconnect over USB, then run /paddles test: the paddles should appear as their own raw buttons. Use /paddles learn force only if you really want to take this button away from the native UI.")
        inputWatcher = nil
        return
    end

    watcher.results[watcher.step] = rawIndex
    Print(string.format("P%d = raw button %d (currently %s).", watcher.step, rawIndex, DescribeRawButtonMapping(watcher.config, rawIndex)))
    watcher.step = watcher.step + 1
    watcher.stepStartedAt = now

    if watcher.step > PADDLE_COUNT then
        local finished = watcher
        inputWatcher = nil
        if ApplyLearnedPaddleMapping(finished) then
            CacheGamepadButtonIndices()
        end
        return
    end

    PrintLearnPrompt(watcher.step)
end

local function StartRawInputTest()
    if inputWatcher then
        StopInputWatcher("Stopped watching raw input.")
        return
    end
    if StartInputWatcher("test") then
        Print(string.format("Press each paddle. Raw button presses are printed for %d seconds; type /paddles test again to stop early.", INPUT_WATCH_TEST_DURATION))
    end
end

local function StartPaddleLearning(force)
    if inputWatcher then
        StopInputWatcher("Stopped the previous watcher.")
    end
    if StartInputWatcher("learn") then
        inputWatcher.force = force == true
        if force then
            Print("Force mode: raw buttons already used by the client will be rebound to the paddles.")
        end
        PrintLearnPrompt(1)
    end
end

-- Asks the client the same question the native crossbar asks
-- (GamepadMode.IsLeftModifierDown / IsRightModifierDown): is the crossbar
-- modifier binding held? Returns nil when neither native signal is available.
local function IsNativeModifierDown(side)
    if type(GamepadMode) == "table" then
        local func = side == "left" and GamepadMode.IsLeftModifierDown or GamepadMode.IsRightModifierDown
        if type(func) == "function" then
            local ok, down = pcall(func)
            if ok then
                return down == true, "GamepadMode"
            end
        end
    end

    if type(GetBindingKey) == "function" and type(IsKeyDown) == "function" then
        local bindingName = side == "left" and "GAMEPADLEFTMOD" or "GAMEPADRIGHTMOD"
        local ok, key1, key2 = pcall(GetBindingKey, bindingName, 1)
        if ok and (key1 or key2) then
            for _, key in ipairs({ key1, key2 }) do
                local downOk, down = pcall(IsKeyDown, key)
                if downOk and down then
                    return true, "modifier bindings"
                end
            end
            return false, "modifier bindings"
        end
    end

    return nil
end

local function GetVisualPanelFromGamepadState()
    local lt, method = IsNativeModifierDown("left")
    local rt = IsNativeModifierDown("right")

    if lt == nil or rt == nil then
        local state = GetMappedState()
        if not state then
            visualDetectionMethod = "secure driver state"
            local securePanel = secureDriver:GetAttribute("activePanel")
            return tonumber(securePanel) or 1
        end

        visualDetectionMethod = "mapped controller state"
        lt = GetMappedButtonDown(state, ltButtonIndex)
        rt = GetMappedButtonDown(state, rtButtonIndex)
    else
        visualDetectionMethod = method
    end

    if lt and rt then
        return 4
    elseif lt then
        return 2
    elseif rt then
        return 3
    end
    return 1
end

---------------------------------------------------------------------------
-- Paddle input assignment, press-to-assign capture, and the setup guide
---------------------------------------------------------------------------

local RefreshGuideFrame -- defined with the guide below
local RefreshSettingsKeyRows -- defined with the settings page below

-- Re-applies the configured paddle keys to the override bindings and the
-- secure layer driver. Deferred until after combat when necessary.
local function ApplyPaddleKeys(announce)
    if not buttons[1] or not buttons[1][1] then
        return
    end

    if InCombatLockdown() then
        pendingSecureRefresh = true
        if announce then
            Print("Paddle input changes will apply after combat.")
        end
        return
    end

    ClearOverrideBindings(secureDriver)
    RegisterSecureFrameRefs()
    if securePanelDriverRegistered then
        SetupSecurePanelDriver()
    end
    BindPaddlesToPanel(GetVisualPanelFromGamepadState())

    local seen = {}
    for paddleIndex = 1, PADDLE_COUNT do
        local key = GetPaddleKey(paddleIndex)
        if key then
            if seen[key] then
                Print(string.format("P%d and P%d both use %s; only one of them will fire.", seen[key], paddleIndex, GetKeyDisplayName(key)))
            else
                seen[key] = paddleIndex
            end
        end
    end

    if RefreshGuideFrame then
        RefreshGuideFrame()
    end
    if RefreshSettingsKeyRows then
        RefreshSettingsKeyRows()
    end
end

-- Pass deferApply when setting several keys, then call ApplyPaddleKeys once.
local function SetPaddleKey(paddleIndex, key, deferApply)
    key = (key and key:upper()) or "NONE"
    local allowed, reason = IsPaddleKeyAllowed(key)
    if not allowed then
        Print(reason)
        return false
    end

    PaddleSlotsDB.paddleKeys["P" .. paddleIndex] = key
    if not deferApply then
        ApplyPaddleKeys(true)
    end
    return true
end

local function StopKeyCapture(message)
    captureState = nil
    if captureFrame then
        captureFrame:Hide()
    end
    if message then
        Print(message)
    end
end

local function UpdateCaptureText()
    if not captureFrame or not captureState then
        return
    end
    captureFrame.title:SetText(string.format("Assign paddle P%d", captureState.paddle))
    captureFrame.text:SetText(string.format(
        "Press the paddle now. Whatever button or key the controller sends will be assigned to P%d.\nCurrently: %s.  Esc or Cancel stops.",
        captureState.paddle,
        GetKeyDisplayName(GetPaddleKey(captureState.paddle))
    ))
end

local function HandleCapturedKey(key)
    local state = captureState
    if not state or type(key) ~= "string" or key == "" then
        return
    end

    key = key:upper()
    local paddle = state.paddle
    local allowed, reason = IsPaddleKeyAllowed(key)
    if not allowed then
        Print(reason)
        if captureFrame then
            captureFrame.text:SetText(string.format("%s\n\nStill waiting for P%d. Esc or Cancel stops.", reason, paddle))
        end
        state.startedAt = GetTime()
        return
    end

    SetPaddleKey(paddle, key)
    Print(string.format("P%d assigned to %s.", paddle, GetKeyDisplayName(key)))

    if state.sequence and paddle < PADDLE_COUNT then
        state.paddle = paddle + 1
        state.startedAt = GetTime()
        UpdateCaptureText()
    else
        StopKeyCapture(nil)
    end
end

local function EnsureCaptureFrame()
    if captureFrame then
        return captureFrame
    end

    local frame = CreateFrame("Frame", "PaddleSlotsCaptureFrame", UIParent, "BackdropTemplate")
    frame:SetSize(480, 170)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(200)
    frame:SetClampedToScreen(true)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -18)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.text:SetPoint("TOP", frame.title, "BOTTOM", 0, -8)
    frame.text:SetWidth(420)
    frame.text:SetJustifyH("CENTER")

    frame.cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.cancel:SetSize(110, 22)
    frame.cancel:SetPoint("BOTTOM", 0, 14)
    frame.cancel:SetText("Cancel")
    frame.cancel:SetScript("OnClick", function()
        StopKeyCapture("Assignment cancelled.")
    end)

    frame:EnableKeyboard(true)
    if frame.EnableGamePadButton then
        frame:EnableGamePadButton(true)
    end
    frame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            StopKeyCapture("Assignment cancelled.")
            return
        end
        if CAPTURE_IGNORED_KEYS[key] then
            return
        end
        HandleCapturedKey(key)
    end)
    -- The frame does not propagate input, so captured presses never reach the
    -- native UI.
    frame:SetScript("OnGamePadButtonDown", function(_, button)
        HandleCapturedKey(button)
    end)
    frame:SetScript("OnUpdate", function()
        if captureState and GetTime() - captureState.startedAt > CAPTURE_TIMEOUT then
            StopKeyCapture("No input detected; assignment cancelled.")
        end
    end)
    frame:SetScript("OnHide", function()
        captureState = nil
    end)
    frame:Hide()

    captureFrame = frame
    return frame
end

-- Starts press-to-assign for one paddle, or for P1..P4 in sequence.
local function StartKeyCapture(paddleIndex, sequence)
    if InCombatLockdown() then
        Print("Paddle inputs cannot be assigned during combat.")
        return
    end

    -- The frame must exist before the capture state is set: creating it ends
    -- with a Hide() whose OnHide handler clears captureState, which used to
    -- leave the very first prompt blank and unresponsive.
    local frame = EnsureCaptureFrame()
    captureState = {
        paddle = paddleIndex or 1,
        sequence = sequence == true,
        startedAt = GetTime(),
    }
    UpdateCaptureText()
    frame:Show()
end

local GUIDE_TEXT = table.concat({
    "On Windows the Xbox Elite Series 2 does not report its paddles to games. WoW only sees whatever the Xbox Accessories app maps a paddle to. PaddleSlots never takes over a button the native gamepad UI uses (A/B/X/Y, D-pad, bumpers, triggers, stick clicks, View, Menu), so each paddle has to arrive as an input WoW does not use.",
    "",
    "|cffffd100Option 1: Xbox Accessories app, keyboard key mapping|r",
    "1. Open Xbox Accessories, select the controller, and edit the profile whose slot is active (the slot LED shows which one).",
    "2. Map each paddle to a keyboard key by pressing a real key that WoW leaves unbound. On a compact keyboard F9, F10, F11, F12 are the natural set; F6-F8, Page Up/Down, Scroll Lock, Pause, and Numpad keys also work when present. Do not use a key you type in chat. Save the profile.",
    "3. Below, click Assign and press each paddle. The addon refuses any key that already has a WoW binding and tells you which one.",
    "4. Share is also free if the app offers it as a paddle target, but that covers only one paddle.",
    "",
    "|cffffd100Option 2: Steam Input or reWASD|r",
    "Same idea, but these tools can send keys that are not on your keyboard (F13-F24), which can never be pressed by accident. Steam: enable the Xbox Extended Feature Support driver under Settings > Controller, add WoW as a non-Steam game, map the paddles in its controller layout, and leave the paddles unassigned in Xbox Accessories.",
    "",
    "|cffffd100PlayStation DualSense Edge|r",
    "Without a profile the Edge's back buttons repeat face buttons, which the addon refuses. Steam Input and reWASD see them as their own inputs: enable PlayStation controller support in Steam, bind the back buttons (and Fn buttons if wanted) to F13-F16 in WoW's controller layout, then assign them here. No PS5 is needed.",
    "",
    "The live line at the bottom shows what WoW receives for any press. If a paddle shows up as A, B, X, Y or another native button, the controller profile is still mirroring it and the addon will refuse it. If a paddle press switches the interface to mouse and keyboard mode, look for an interface style option under Settings > Controls and pin it to gamepad.",
}, "\n")

local function EnsureGuideFrame()
    if guideFrame then
        return guideFrame
    end

    local frame = CreateFrame("Frame", "PaddleSlotsGuideFrame", UIParent, "BackdropTemplate")
    frame:SetSize(640, 700)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -18)
    frame.title:SetText("PaddleSlots setup guide")

    frame.body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.body:SetPoint("TOPLEFT", 24, -48)
    frame.body:SetWidth(592)
    frame.body:SetJustifyH("LEFT")
    frame.body:SetJustifyV("TOP")
    frame.body:SetSpacing(2)
    frame.body:SetText(GUIDE_TEXT)

    frame.rowsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.rowsHeader:SetPoint("TOPLEFT", frame.body, "BOTTOMLEFT", 0, -14)
    frame.rowsHeader:SetText("Current paddle inputs")

    frame.rows = {}
    local previous = frame.rowsHeader
    for paddleIndex = 1, PADDLE_COUNT do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(572, 24)
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -4)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(400)
        row.label:SetJustifyH("LEFT")

        row.assign = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.assign:SetSize(120, 22)
        row.assign:SetPoint("RIGHT", 0, 0)
        row.assign:SetText("Assign P" .. paddleIndex)
        row.assign:SetScript("OnClick", function()
            StartKeyCapture(paddleIndex, false)
        end)

        frame.rows[paddleIndex] = row
        previous = row
    end

    frame.lastInput = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.lastInput:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10)
    frame.lastInput:SetWidth(572)
    frame.lastInput:SetJustifyH("LEFT")
    frame.lastInput:SetText("Last input detected while this window is open: none yet. Press a paddle to see what WoW receives.")

    frame.assignAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.assignAll:SetSize(170, 22)
    frame.assignAll:SetPoint("BOTTOMLEFT", 22, 16)
    frame.assignAll:SetText("Assign all by pressing")
    frame.assignAll:SetScript("OnClick", function()
        StartKeyCapture(1, true)
    end)

    frame.openSettings = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.openSettings:SetSize(120, 22)
    frame.openSettings:SetPoint("LEFT", frame.assignAll, "RIGHT", 8, 0)
    frame.openSettings:SetText("Open settings")
    frame.openSettings:SetScript("OnClick", function()
        if settingsCategory and Settings and type(Settings.OpenToCategory) == "function" then
            Settings.OpenToCategory(settingsCategory:GetID())
        end
    end)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.close:SetSize(100, 22)
    frame.close:SetPoint("BOTTOMRIGHT", -22, 16)
    frame.close:SetText("Close")
    frame.close:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Live readout: report presses without swallowing them. Propagation (for
    -- keys and gamepad buttons alike) is set by SetPropagateKeyboardInput, which
    -- is blocked in combat; ToggleGuideFrame never creates the frame in combat,
    -- and input is only read once propagation is confirmed.
    if frame.SetPropagateKeyboardInput and pcall(frame.SetPropagateKeyboardInput, frame, true) then
        frame:EnableKeyboard(true)
        frame:SetScript("OnKeyDown", function(_, key)
            if not CAPTURE_IGNORED_KEYS[key] then
                frame.lastInput:SetText(string.format("Last input detected: %s (%s)", GetKeyDisplayName(key), key))
            end
        end)
        if frame.EnableGamePadButton then
            frame:EnableGamePadButton(true)
            frame:SetScript("OnGamePadButtonDown", function(_, button)
                frame.lastInput:SetText(string.format("Last input detected: %s (%s)", GetKeyDisplayName(button), button))
            end)
        end
    end

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "PaddleSlotsGuideFrame")
    end

    frame:Hide()
    guideFrame = frame
    return frame
end

RefreshGuideFrame = function()
    if not guideFrame or not guideFrame:IsShown() then
        return
    end
    for paddleIndex = 1, PADDLE_COUNT do
        local key = GetPaddleKey(paddleIndex)
        local note = key and GetKeyNote(key)
        local text = string.format("P%d:  %s", paddleIndex, GetKeyDisplayName(key))
        if key and key:match("^PADPADDLE%d$") then
            text = text .. "  |cffff6060(native paddle key; not reported by the Elite Series 2 on Windows)|r"
        elseif note and not key:match("^F%d+$") and key ~= "PADSOCIAL" then
            text = text .. "  |cffa0a0a0" .. note .. "|r"
        end
        guideFrame.rows[paddleIndex].label:SetText(text)
    end
end

local function ToggleGuideFrame()
    if not guideFrame and InCombatLockdown() then
        Print("The setup guide can be opened after combat.")
        return
    end

    local frame = EnsureGuideFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        RefreshGuideFrame()
    end
end

local function OnNativeModifierStateChanged()
    UpdatePanelVisualState(GetVisualPanelFromGamepadState())
end

local function RegisterNativeModifierCallback()
    if nativeModifierCallbackRegistered
        or type(GamepadMode) ~= "table"
        or type(GamepadMode.RegisterCrossBarModifierStateChanged) ~= "function" then
        return
    end

    local ok = pcall(GamepadMode.RegisterCrossBarModifierStateChanged, OnNativeModifierStateChanged, addon)
    nativeModifierCallbackRegistered = ok == true
end

local function ApplyAppearance()
    if not panelFrames[1] then
        return
    end

    if InCombatLockdown() then
        pendingAppearanceRefresh = true
        return
    end

    local scale = PaddleSlotsDB.hudScale or 1.0
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel then
            panel:SetScale(scale)
        end
    end

    UpdatePanelVisualState(GetVisualPanelFromGamepadState(), true)
    UpdateEditOverlays()
    pendingAppearanceRefresh = false
end

-- Polls IsActionInRange for native-storage slots that hold an action. See
-- SetRangeCheckEnabled for why the client's push-based range checks are not used.
local function PollRangeIndicators()
    if type(IsActionInRange) ~= "function" then
        return
    end
    ForEachButton(function(button)
        if button.rangeCheckEnabled and button.hasAction and button.actionSlot then
            local inRange = SafeCall(IsActionInRange, button.actionSlot)
            if IsSecret(inRange) then
                -- Range is secret for this action right now; hide the dot
                -- rather than compare a value the addon may not read.
                UpdateRangeIndicator(button, false, false)
            else
                UpdateRangeIndicator(button, inRange ~= nil, inRange == true)
            end
        end
    end)
end

local function StartStatePoller()
    addon:SetScript("OnUpdate", function(_, elapsed)
        UpdateFocusFades()

        rangePollElapsed = rangePollElapsed + elapsed
        if rangePollElapsed >= RANGE_POLL_INTERVAL then
            rangePollElapsed = 0
            PollRangeIndicators()
        end

        statePollElapsed = statePollElapsed + elapsed
        if statePollElapsed < 0.035 then
            return
        end
        statePollElapsed = 0

        if inputWatcher then
            UpdateInputWatcher()
        end

        local panelIndex = GetVisualPanelFromGamepadState()
        UpdatePanelVisualState(panelIndex)

        -- If Forever is not exposing LT/RT as emulated secure modifiers, we
        -- can still follow the real controller state outside combat.
        if not securePanelDriverRegistered and not InCombatLockdown() and panelIndex ~= lastBoundPanel then
            BindPaddlesToPanel(panelIndex)
        end
    end)
end

local function SetUnlocked(unlocked)
    PaddleSlotsDB.unlocked = unlocked and true or false
    if InCombatLockdown() then
        pendingAppearanceRefresh = true
        Print("Layout lock changes will apply after combat.")
        return
    end
    UpdateEditOverlays()
    UpdatePanelVisualState(GetVisualPanelFromGamepadState(), true)
    Print(unlocked and "Unlocked. Drag each paddle panel independently." or "Locked. Edit Mode will still unlock the panels while it is open.")
end

local function ResetPosition(panelIndex)
    if InCombatLockdown() then
        Print("Paddle panels cannot be moved during combat.")
        return
    end

    if panelIndex then
        PaddleSlotsDB.panelPositions[panelIndex] = DefaultPanelPosition(panelIndex)
        SetPanelPosition(panelIndex)
        Print(PANELS[panelIndex].label .. " position reset.")
        return
    end

    for i = 1, PANEL_COUNT do
        PaddleSlotsDB.panelPositions[i] = DefaultPanelPosition(i)
        SetPanelPosition(i)
    end
    Print("All paddle panel positions reset.")
end

local function RegisterEditModeIntegration()
    if editModeCallbacksRegistered or not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end

    editModeCallbacksRegistered = true

    EventRegistry:RegisterCallback("EditMode.Enter", function()
        editModeActive = true
        UpdateEditOverlays()
        UpdatePanelVisualState(GetVisualPanelFromGamepadState(), true)
    end, addon)

    -- Dragged panels save on OnDragStop. Re-saving every panel here would turn
    -- a fallback UIParent anchor into a stored position and lose the crossbar
    -- attachment for panels that were never moved.
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        editModeActive = false
        UpdateEditOverlays()
        UpdatePanelVisualState(GetVisualPanelFromGamepadState(), true)
    end, addon)

    -- Reloading the UI while Edit Mode is already open does not emit another
    -- EditMode.Enter event for us, so mirror the manager's current state once.
    if EditModeManagerFrame and type(EditModeManagerFrame.IsEditModeActive) == "function" then
        local ok, active = pcall(EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
        if ok and active then
            editModeActive = true
        end
    end
end

local function ParsePanelArgument(value)
    value = value and value:upper() or ""
    if value == "1" or value == "BASE" or value == "NONE" then
        return 1
    elseif value == "2" or value == "LT" then
        return 2
    elseif value == "3" or value == "RT" then
        return 3
    elseif value == "4" or value == "BOTH" or value == "LTRT" or value == "LT+RT" then
        return 4
    end
    return nil
end

local function ClearSlot(panelArg, paddleArg)
    local panelIndex = ParsePanelArgument(panelArg)
    local paddleIndex = tonumber(paddleArg)
    if not panelIndex or not paddleIndex or paddleIndex ~= math.floor(paddleIndex)
        or paddleIndex < 1 or paddleIndex > PADDLE_COUNT then
        Print("Usage: /paddles clear <base|lt|rt|both> <1-4>")
        return
    end

    ClearButtonAction(buttons[panelIndex][paddleIndex])
    Print(string.format("Cleared %s P%d.", PANELS[panelIndex].label, paddleIndex))
end

local function GetMappedDiagnosticValues()
    local state = GetMappedState()
    if not state then
        return "unavailable"
    end

    local ltLuaIndex = GetMappedButtonArrayIndex(state, ltButtonIndex)
    local rtLuaIndex = GetMappedButtonArrayIndex(state, rtButtonIndex)
    local ltValue = ltLuaIndex ~= nil and state.buttons and state.buttons[ltLuaIndex]
    local rtValue = rtLuaIndex ~= nil and state.buttons and state.buttons[rtLuaIndex]
    local tableBase = state.buttons and state.buttons[0] ~= nil and 0 or 1

    return string.format(
        "tableBase=%d   LT index=%s/lua=%s/value=%s   RT index=%s/lua=%s/value=%s",
        tableBase,
        tostring(ltButtonIndex), tostring(ltLuaIndex), tostring(ltValue),
        tostring(rtButtonIndex), tostring(rtLuaIndex), tostring(rtValue)
    )
end

local function GetModifierDiagnosticValues()
    return string.format(
        "Shift=%s   Ctrl=%s   Alt=%s",
        tostring(GetGamepadEmulationCVar("GamePadEmulateShift")),
        tostring(GetGamepadEmulationCVar("GamePadEmulateCtrl")),
        tostring(GetGamepadEmulationCVar("GamePadEmulateAlt"))
    )
end

local function GetNativeArtDiagnostic()
    local missing = missingAtlases.count or 0
    if missing == 0 then
        return "all native crossbar atlases found"
    end

    local names = {}
    for name, flagged in pairs(missingAtlases) do
        if flagged == true and name ~= "count" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return string.format("%d native atlases missing (using bundled art): %s", missing, table.concat(names, ", "))
end

local function GetNativeStyleDiagnostic()
    return string.format(
        "scaling=%s   highlight=%s   prompts=%s",
        tostring(GetNativeCVarBool(NATIVE_CVAR_SCALING, true)),
        tostring(GetNativeCVarBool(NATIVE_CVAR_HIGHLIGHT, true)),
        tostring(GetNativeCVarBool(NATIVE_CVAR_PROMPTS, true))
    )
end

local function GetDiagnosticLines(separator)
    local firstStorage = SafeCall(C_GamepadUI and C_GamepadUI.GetFirstGamepadActionStorageSlotIndex)
    local stanceStorage = SafeCall(C_GamepadUI and C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance)
    local petStorage = SafeCall(C_GamepadUI and C_GamepadUI.GetFirstGamepadPetActionStorageSlotIndex)
    local ltAction = GetBindingAction("PADLTRIGGER", true)
    local rtAction = GetBindingAction("PADRTRIGGER", true)
    local securePanelIndex = tonumber(secureDriver:GetAttribute("activePanel")) or 1
    local visualPanelIndex = GetVisualPanelFromGamepadState()

    local lines = {
        "Storage mode: " .. (nativeStorageEnabled and "native C_GamepadUI action slots" or "SavedVariables fallback"),
        "Storage detail: " .. nativeStorageStatus,
        "Storage scope: actions and reserved slots are per character" .. (PaddleSlotsCharDB.migratedFromAccount and " (copied from the account-wide profile of 0.7.6 or older)" or ""),
        string.format("Gamepad storage: first=%s%sstance=%s%spet=%s", tostring(firstStorage), separator, tostring(stanceStorage), separator, tostring(petStorage)),
        "Panel driver: " .. nativeHookStatus,
        string.format("LT binding: %s%sRT binding: %s", tostring(ltAction), separator, tostring(rtAction)),
        "Modifier CVars: " .. GetModifierDiagnosticValues(),
        "Mapped state: " .. GetMappedDiagnosticValues(),
        "Paddle raw mapping: " .. GetPaddleRawMappingDiagnostic(),
        string.format("Paddle inputs: P1=%s   P2=%s   P3=%s   P4=%s",
            tostring(GetPaddleKey(1)), tostring(GetPaddleKey(2)), tostring(GetPaddleKey(3)), tostring(GetPaddleKey(4))),
        "Interface style: " .. tostring(C_InputInterfaceStyle and type(C_InputInterfaceStyle.GetCurrentStyle) == "function" and SafeCall(C_InputInterfaceStyle.GetCurrentStyle) or "unknown")
            .. " (CVar InputDeviceInterfaceStyle=" .. tostring(GetGamepadEmulationCVar("InputDeviceInterfaceStyle")) .. ")",
        "Panels shown: " .. tostring(panelFrames[1] and panelFrames[1]:IsShown()) .. " (gamepad interface=" .. tostring(IsGamepadInterfaceActive()) .. ", gamepad only=" .. tostring(PaddleSlotsDB.gamepadOnly ~= false) .. ")",
        "Visual detection: " .. visualDetectionMethod .. (nativeModifierCallbackRegistered and " (+ native crossbar callback)" or ""),
        "Visual panel: " .. PANELS[visualPanelIndex].label,
        "Secure panel: " .. PANELS[securePanelIndex].label,
        "Native style CVars: " .. GetNativeStyleDiagnostic(),
        "Native art: " .. GetNativeArtDiagnostic(),
        "Edit Mode: " .. (editModeActive and "active" or "inactive") .. (editModeCallbacksRegistered and " (listening for EditMode.Enter/Exit)" or " (integration unavailable)"),
    }

    if nativeStorageEnabled then
        local values = {}
        for _, slot in ipairs(nativeStorageSlots) do
            values[#values + 1] = tostring(slot)
        end
        lines[#lines + 1] = "Reserved native slots: " .. table.concat(values, ", ")

        -- Checks the reservation against the slots the native crossbar
        -- addresses (GamepadActionBarBindingUtil): the standard pages, each
        -- with its reserved UI slots removed, plus the active stance bar.
        local constants = Constants and Constants.GamepadActionBarConstants or {}
        local pageSlots = (constants.NUM_PAGEABLE_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT_STANDARD_PAGE or 32)
            - (constants.NUM_RESERVED_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT or 4)
        local pageCount = constants.NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT or 3
        local barSlots = constants.NUM_SLOTS_PER_GAMEPAD_ACTION_BAR or 8
        local ranges = {}
        if type(firstStorage) == "number" then
            ranges[#ranges + 1] = { label = "pages", first = firstStorage, last = firstStorage + pageSlots * pageCount - 1 }
        end
        if type(stanceStorage) == "number" then
            ranges[#ranges + 1] = { label = "active stance", first = stanceStorage, last = stanceStorage + barSlots - 1 }
        end

        local conflicts = {}
        for _, slot in ipairs(nativeStorageSlots) do
            for _, range in ipairs(ranges) do
                if slot >= range.first and slot <= range.last then
                    conflicts[#conflicts + 1] = string.format("%d (%s)", slot, range.label)
                end
            end
        end

        local rangeText = {}
        for _, range in ipairs(ranges) do
            rangeText[#rangeText + 1] = string.format("%s %d-%d", range.label, range.first, range.last)
        end
        local pool = DiscoverNativeStorageSlots()
        if pool and #pool > 0 then
            rangeText[#rangeText + 1] = string.format("valid pool %d-%d", pool[1], pool[#pool])
        end
        if type(stanceStorage) ~= "number" then
            rangeText[#rangeText + 1] = "no stance active"
        end

        lines[#lines + 1] = string.format("Native slot check: %s%s%s",
            #conflicts == 0 and "OK" or ("CONFLICT " .. table.concat(conflicts, ", ")),
            separator,
            table.concat(rangeText, ", "))
    end

    return lines
end

local function PrintDiagnostics()
    Print("Diagnostics:")
    for _, line in ipairs(GetDiagnosticLines(" | ")) do
        Print(line)
    end
end

-- Everything lives on one canvas page built from plain widgets. Forever's
-- vertical-layout settings list hangs the client when the Settings window is
-- closed in gamepad mode after that page was shown (canvas pages such as
-- ChattyLittleNpc's do not), and its subcategories crash the gamepad
-- smart-navigation cursor (ScrollUtil.lua IsSelected on a released list button).
local function RegisterSettings()
    if settingsRegistered or not Settings or type(Settings.RegisterCanvasLayoutCategory) ~= "function" then
        return
    end

    settingsRegistered = true

    -- Hidden until the Settings window displays it, so OnShow always fires.
    local panel = CreateFrame("Frame")
    panel.name = "PaddleSlots"
    panel:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(560, 1)
    scrollFrame:SetScrollChild(content)

    -- Each control registers a function that reloads it from PaddleSlotsDB.
    local refreshers = {}
    local y = -6
    local sliderCount = 0

    local note = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 6, y)
    note:SetWidth(540)
    note:SetJustifyH("LEFT")
    note:SetText("With a controller, use the mouse on this page. The gamepad cursor cannot enter it without freezing Forever when Settings is closed. Paddle keys, lock/unlock and reset also work through /paddles.")
    y = y - 34

    local function AttachTooltip(control, label, tooltip)
        control:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        control:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local function AddSection(label)
        y = y - 12
        local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", 6, y)
        header:SetText(label)
        y = y - 26
    end

    local function AddCheckbox(key, label, tooltip, onChange)
        local checkbox = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", 14, y)
        checkbox.Text:SetText(label)
        checkbox:SetScript("OnClick", function(self)
            PaddleSlotsDB[key] = self:GetChecked() and true or false
            onChange(PaddleSlotsDB[key])
        end)
        AttachTooltip(checkbox, label, tooltip)
        table.insert(refreshers, function()
            checkbox:SetChecked(PaddleSlotsDB[key] == true)
        end)
        y = y - 30
    end

    -- OptionsSliderTemplate needs a global name on Classic-derived clients.
    local function AddSlider(key, label, minValue, maxValue, step, tooltip)
        sliderCount = sliderCount + 1
        y = y - 16
        local slider = CreateFrame("Slider", "PaddleSlotsSettingsSlider" .. sliderCount, content, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", 22, y)
        slider:SetWidth(250)
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        if slider.Low then
            slider.Low:SetText(string.format("%.2f", minValue))
        end
        if slider.High then
            slider.High:SetText(string.format("%.2f", maxValue))
        end

        local function UpdateLabel(value)
            slider.Text:SetText(string.format("%s: %.2f", label, value))
        end

        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / step + 0.5) * step
            UpdateLabel(value)
            -- Refreshing the page calls SetValue too; only real changes apply.
            if math.abs((tonumber(PaddleSlotsDB[key]) or 0) - value) > 0.001 then
                PaddleSlotsDB[key] = value
                ApplyAppearance()
            end
        end)
        AttachTooltip(slider, label, tooltip)
        table.insert(refreshers, function()
            local value = tonumber(PaddleSlotsDB[key]) or minValue
            slider:SetValue(value)
            UpdateLabel(value)
        end)
        y = y - 40
    end

    -- buttonText may be a function so the paddle rows can show the current key.
    local function AddButton(label, buttonText, onClick, tooltip)
        local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOPLEFT", 20, y - 5)
        text:SetText(label)

        local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        button:SetSize(180, 22)
        button:SetPoint("TOPLEFT", 250, y)
        button:SetScript("OnClick", onClick)
        AttachTooltip(button, label, tooltip)
        if type(buttonText) == "function" then
            table.insert(refreshers, function()
                button:SetText(buttonText())
            end)
        else
            button:SetText(buttonText)
        end
        y = y - 28
    end

    AddSection("Layout")

    AddCheckbox(
        "unlocked",
        "Unlock panels outside Edit Mode",
        "Normally PaddleSlots unlocks automatically while WoW Edit Mode is open. Enable this to move the four panels independently without opening Edit Mode.",
        function(value)
            SetUnlocked(value)
        end
    )

    AddButton(
        "Panel positions",
        "Reset All",
        function()
            ResetPosition()
        end,
        "Moves all four paddle panels back to their default spots inside the native crossbar: each panel above the centre of the bar that uses the same trigger combination, LT + RT in the middle of the cross."
    )

    AddCheckbox(
        "gamepadOnly",
        "Only show in gamepad mode",
        "Hides the paddle panels while the interface is in mouse and keyboard mode. They stay visible while unlocked or in Edit Mode.",
        function()
            UpdatePanelVisibility()
        end
    )

    AddSection("Paddle inputs")

    for paddleIndex = 1, PADDLE_COUNT do
        AddButton(
            "Paddle P" .. paddleIndex,
            function()
                return GetKeyDisplayName(GetPaddleKey(paddleIndex))
            end,
            function()
                StartKeyCapture(paddleIndex, false)
            end,
            "Shows the input that triggers this paddle. Click it, then press the paddle to assign a new one."
        )
    end

    AddButton(
        "Assign all four in order",
        "Assign P1-P4",
        function()
            StartKeyCapture(1, true)
        end,
        "Prompts for P1, P2, P3, and P4 one after another."
    )

    AddButton(
        "How to set up the paddles",
        "Setup guide",
        function()
            ToggleGuideFrame()
        end,
        "Step-by-step instructions for the Xbox Accessories app, plus a live readout of what WoW receives when you press a paddle."
    )

    AddSection("Paddle HUD")

    AddSlider(
        "hudScale",
        "HUD scale",
        0.65, 1.50, 0.05,
        "Scales all four PaddleSlots panels. 1.00 matches the size of the native crossbar slots."
    )

    AddSlider(
        "inactiveOpacity",
        "Inactive panel opacity",
        0.10, 1.0, 0.05,
        "Fades the three unfocused panels. The native crossbar does not fade unfocused bars, so 1.00 is the default."
    )

    AddCheckbox(
        "highlightActivePanel",
        "Highlight focused panel",
        "Draws the native crossbar focus highlight behind the BASE, LT, RT, or LT + RT panel that is currently active. Also respects the game's own action bar highlight setting.",
        function()
            ApplyAppearance()
        end
    )

    AddSlider(
        "highlightStrength",
        "Focus highlight strength",
        0.0, 1.0, 0.05,
        "Adjusts the strength of the focus highlight. 1.00 matches the native crossbar."
    )

    AddCheckbox(
        "showPanelLabels",
        "Show LT / RT modifier icons",
        "Adds LT, RT, and LT + RT controller prompts below the paddle panels. Off by default because the native crossbar already shows those prompts next to the default panel positions.",
        function()
            ApplyAppearance()
        end
    )

    AddCheckbox(
        "showPaddleBadges",
        "Show paddle prompts on the focused panel",
        "Shows the small P1-P4 glyph on assigned actions of the focused panel, like the native button prompts. Also respects the game's own action bar button prompt setting.",
        function()
            ApplyAppearance()
        end
    )

    AddSection("Diagnostics")

    AddButton(
        "Gamepad integration",
        "Print Diagnostics",
        function()
            PrintDiagnostics()
        end,
        "Prints native storage, LT/RT detection, and native art status to the chat frame. Same as /paddles diag."
    )

    content:SetHeight(-y + 10)

    local function RefreshControls()
        for _, refresh in ipairs(refreshers) do
            refresh()
        end
    end
    -- Deliberately not announced to the gamepad cursor (SmartNavigation). Once
    -- this page's controls are in its button list, closing Settings with the
    -- controller (B, or A on Close) hangs the client for the rest of the
    -- session. The controls are created at login and only reparented into the
    -- Settings window, so the cursor never picks them up on its own.
    panel:SetScript("OnShow", RefreshControls)

    -- Keeps the page in step with slash commands and press-to-assign while open.
    RefreshSettingsKeyRows = function()
        if panel:IsVisible() then
            RefreshControls()
        end
    end

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    settingsCategory = category
end

local function OpenSettings()
    if not settingsRegistered then
        RegisterSettings()
    end

    if settingsCategory and Settings and type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(settingsCategory:GetID())
    else
        Print("The native Settings UI is not available yet.")
    end
end

local function PrintHelp()
    Print("Commands:")
    Print("/paddles unlock - move panels outside WoW Edit Mode")
    Print("/paddles lock - lock panels outside WoW Edit Mode")
    Print("/paddles reset [base|lt|rt|both] - reset all or one panel position")
    Print("/paddles clear <base|lt|rt|both> <1-4> - clear one paddle action")
    Print("/paddles or /paddles options - open native settings")
    Print("/paddles diag - show native gamepad integration diagnostics")
    Print("/paddles guide - open the setup guide (Xbox Accessories / Steam Input steps, live input readout)")
    Print("/paddles assign [1-4] - assign one paddle, or all four in order, by pressing it")
    Print("/paddles keys [P1 P2 P3 P4 | reset] - show or set the inputs, e.g. /paddles keys F13 F14 F15 F16")
    Print("/paddles test - print which raw controller buttons fire when you press the paddles")
    Print("/paddles learn - press P1-P4 in order to map them to PADPADDLE1-4 in the client's gamepad config")
    Print("/paddles learn clear - remove the addon's device config again")
    Print("/paddles learn force - allow rebinding raw buttons the client already uses (steals them from the native UI)")
end

SLASH_PADDLESLOTS1 = "/paddles"
SLASH_PADDLESLOTS2 = "/pslots"
SlashCmdList.PADDLESLOTS = function(message)
    local args = {}
    for token in message:gmatch("%S+") do
        args[#args + 1] = token
    end

    local command = (args[1] or ""):lower()
    if command == "" or command == "options" or command == "settings" then
        OpenSettings()
    elseif command == "unlock" then
        SetUnlocked(true)
        if Settings and type(Settings.SetValue) == "function" then
            pcall(Settings.SetValue, "PADDLESLOTS_UNLOCKED", true)
        end
    elseif command == "lock" then
        SetUnlocked(false)
        if Settings and type(Settings.SetValue) == "function" then
            pcall(Settings.SetValue, "PADDLESLOTS_UNLOCKED", false)
        end
    elseif command == "reset" then
        local panelIndex = args[2] and ParsePanelArgument(args[2]) or nil
        if args[2] and not panelIndex then
            Print("Usage: /paddles reset [base|lt|rt|both]")
        else
            ResetPosition(panelIndex)
        end
    elseif command == "clear" then
        ClearSlot(args[2], args[3])
    elseif command == "diag" or command == "diagnostics" then
        PrintDiagnostics()
    elseif command == "guide" or command == "setup" then
        ToggleGuideFrame()
    elseif command == "assign" then
        local paddleIndex = tonumber(args[2])
        if paddleIndex and paddleIndex >= 1 and paddleIndex <= PADDLE_COUNT then
            StartKeyCapture(paddleIndex, false)
        else
            StartKeyCapture(1, true)
        end
    elseif command == "keys" then
        local option = (args[2] or ""):lower()
        if option == "" then
            for paddleIndex = 1, PADDLE_COUNT do
                Print(string.format("P%d: %s", paddleIndex, GetKeyDisplayName(GetPaddleKey(paddleIndex))))
            end
        elseif option == "reset" then
            for paddleIndex = 1, PADDLE_COUNT do
                SetPaddleKey(paddleIndex, "PADPADDLE" .. paddleIndex, true)
            end
            ApplyPaddleKeys(true)
            Print("Paddle inputs reset to the native paddle keys.")
        else
            for paddleIndex = 1, PADDLE_COUNT do
                if args[paddleIndex + 1] then
                    SetPaddleKey(paddleIndex, args[paddleIndex + 1], true)
                end
            end
            ApplyPaddleKeys(true)
            for paddleIndex = 1, PADDLE_COUNT do
                Print(string.format("P%d: %s", paddleIndex, GetKeyDisplayName(GetPaddleKey(paddleIndex))))
            end
        end
    elseif command == "test" then
        StartRawInputTest()
    elseif command == "learn" then
        local option = (args[2] or ""):lower()
        if option == "cancel" or option == "stop" then
            StopInputWatcher("Learning cancelled; nothing was changed.")
        elseif option == "clear" or option == "reset" then
            StopInputWatcher(nil)
            ClearLearnedPaddleMapping()
        else
            StartPaddleLearning(option == "force")
        end
    else
        PrintHelp()
    end
end

local NATIVE_STYLE_CVARS = {
    [NATIVE_CVAR_SCALING] = true,
    [NATIVE_CVAR_HIGHLIGHT] = true,
    [NATIVE_CVAR_PROMPTS] = true,
}

local MODIFIER_EMULATION_CVARS = {
    GamePadEmulateShift = true,
    GamePadEmulateCtrl = true,
    GamePadEmulateAlt = true,
}

-- The reserved paddle slots were picked because they were empty, not because
-- the native crossbar can never address them. Stance bars have their own
-- storage blocks and the client only reveals the active one, so check each
-- stance as it becomes active and warn once if it shares slots with a paddle.
local stanceOverlapWarned = {}
local function CheckStanceOverlap()
    if not nativeStorageEnabled or not C_GamepadUI
        or type(C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance) ~= "function" then
        return
    end
    local first = SafeCall(C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance)
    if type(first) ~= "number" or stanceOverlapWarned[first] then
        return
    end
    local constants = Constants and Constants.GamepadActionBarConstants or {}
    local last = first + (constants.NUM_SLOTS_PER_GAMEPAD_ACTION_BAR or 8) - 1
    for _, slot in ipairs(nativeStorageSlots) do
        if slot >= first and slot <= last then
            stanceOverlapWarned[first] = true
            Print(string.format(
                "Warning: this stance bar uses action slots %d-%d, which include paddle slot %d. Actions placed on either may replace each other. Please report this with /paddles diag output.",
                first, last, slot
            ))
            return
        end
    end
end

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")
addon:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
addon:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
addon:RegisterEvent("ACTIONBAR_UPDATE_STATE")
addon:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
addon:RegisterEvent("SPELL_UPDATE_USABLE")
addon:RegisterEvent("ACTION_RANGE_CHECK_UPDATE")
addon:RegisterEvent("UPDATE_MACROS")
addon:RegisterEvent("SPELL_UPDATE_COOLDOWN")
addon:RegisterEvent("BAG_UPDATE_COOLDOWN")
addon:RegisterEvent("BAG_UPDATE_DELAYED")
addon:RegisterEvent("ITEM_DATA_LOAD_RESULT")
addon:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
addon:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
addon:RegisterEvent("GAME_PAD_CONFIGS_CHANGED")
addon:RegisterEvent("CVAR_UPDATE")
addon:RegisterEvent("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED")
addon:RegisterEvent("GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED")

addon:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end

        EnsureDatabase()
        EnsureCharacterDatabase()
        InitializeNativeStorage()
        CreateUI()
        RegisterSecureFrameRefs()
        CacheGamepadButtonIndices()
        BindPaddlesToPanel(GetVisualPanelFromGamepadState())
        SetupSecurePanelDriver()
        RegisterEditModeIntegration()
        RegisterNativeModifierCallback()
        UpdateEditOverlays()
        ApplyAppearance()
        RegisterSettings()
        StartStatePoller()
        return
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if not settingsRegistered then
            RegisterSettings()
        end
        -- Re-anchor to the native crossbar in case it did not exist yet when
        -- the panels were created and they fell back to screen coordinates.
        if not InCombatLockdown() then
            for panelIndex = 1, PANEL_COUNT do
                SetPanelPosition(panelIndex)
            end
        end
        CacheGamepadButtonIndices()
        CheckStanceOverlap()
        RegisterEditModeIntegration()
        RegisterNativeModifierCallback()
        if not InCombatLockdown() then
            BindPaddlesToPanel(GetVisualPanelFromGamepadState())
            C_Timer.After(0.5, function()
                TryHookNativeTriggerDriver()
            end)
        end
        UpdateAllButtonVisuals()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if pendingSecureRefresh then
            pendingSecureRefresh = false
            RefreshButtons()
            RegisterSecureFrameRefs()
            BindPaddlesToPanel(GetVisualPanelFromGamepadState())
        end
        if pendingAppearanceRefresh then
            ApplyAppearance()
        end
        TryHookNativeTriggerDriver()
        return
    end

    if event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        UpdatePanelVisibility()
        return
    end

    if event == "GAME_PAD_ACTIVE_CHANGED" or event == "GAME_PAD_CONFIGS_CHANGED" then
        CacheGamepadButtonIndices()
        UpdatePanelVisibility()
        C_Timer.After(0.2, function()
            if not InCombatLockdown() then
                BindPaddlesToPanel(GetVisualPanelFromGamepadState())
            end
            TryHookNativeTriggerDriver()
        end)
        return
    end

    if event == "CVAR_UPDATE" then
        local cvarName = tostring(arg1 or "")
        if MODIFIER_EMULATION_CVARS[cvarName] then
            TryHookNativeTriggerDriver()
        elseif NATIVE_STYLE_CVARS[cvarName] then
            ApplyAppearance()
        end
        return
    end

    if event == "ACTIONBAR_SLOT_CHANGED" then
        local changedSlot = tonumber(arg1) or 0
        if nativeStorageEnabled and changedSlot > 0 then
            ForEachButton(function(button)
                if button.actionSlot == changedSlot then
                    UpdateButtonVisual(button)
                end
            end)
        elseif nativeStorageEnabled then
            -- Slot 0 means every slot changed.
            UpdateAllButtonVisuals()
        else
            RefreshButtons()
        end
        return
    end

    if event == "ACTION_RANGE_CHECK_UPDATE" then
        local changedSlot = not IsSecret(arg1) and tonumber(arg1) or nil
        if changedSlot then
            local secret = IsSecret(arg2) or IsSecret(arg3)
            ForEachButton(function(button)
                if button.actionSlot == changedSlot then
                    if secret then
                        UpdateRangeIndicator(button, false, false)
                    else
                        UpdateRangeIndicator(button, arg3 == true, arg2 == true)
                    end
                end
            end)
        end
        return
    end

    if event == "GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED" or event == "GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED" then
        RefreshButtons()
        CheckStanceOverlap()
        return
    end

    if event == "UPDATE_MACROS" then
        -- Macro bodies feed the secure attributes of fallback slots.
        RefreshButtons()
        return
    end

    if event == "ACTIONBAR_UPDATE_COOLDOWN"
        or event == "ACTIONBAR_UPDATE_STATE"
        or event == "ACTIONBAR_UPDATE_USABLE"
        or event == "SPELL_UPDATE_USABLE"
        or event == "SPELL_UPDATE_COOLDOWN"
        or event == "BAG_UPDATE_COOLDOWN"
        or event == "BAG_UPDATE_DELAYED"
        or event == "ITEM_DATA_LOAD_RESULT" then
        UpdateAllButtonVisuals()
    end
end)
