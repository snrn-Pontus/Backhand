-- Default panel positions and the SavedVariables (account-wide and per
-- character), including migrations from older versions.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local LAYOUT = ns.LAYOUT

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

ns.NATIVE_CROSSBAR_FRAME = NATIVE_CROSSBAR_FRAME
ns.DefaultPanelPosition = DefaultPanelPosition
ns.ResolvePanelAnchor = ResolvePanelAnchor
ns.EnsureDatabase = EnsureDatabase
ns.EnsureCharacterDatabase = EnsureCharacterDatabase
