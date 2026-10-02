-- The addon's page in the game's Settings window
local _, ns = ...

local PADDLE_COUNT = ns.PADDLE_COUNT
local Print = ns.Print
local GetPaddleKey = ns.GetPaddleKey
local GetKeyDisplayName = ns.GetKeyDisplayName
local UpdatePanelVisibility = ns.UpdatePanelVisibility
local StartKeyCapture = ns.StartKeyCapture
local ToggleGuideFrame = ns.ToggleGuideFrame
local ApplyAppearance = ns.ApplyAppearance
local SetUnlocked = ns.SetUnlocked
local ResetPosition = ns.ResetPosition
local ShowDiagnosticsFrame = ns.ShowDiagnosticsFrame
local GetProfileSetting = ns.GetProfileSetting
local GetProfileChoiceLabel = ns.GetProfileChoiceLabel
local CycleControllerProfileSetting = ns.CycleControllerProfileSetting

-- Everything lives on one canvas page built from plain widgets. Forever's
-- vertical-layout settings list hangs the client when the Settings window is
-- closed in gamepad mode after that page was shown (canvas pages such as
-- ChattyLittleNpc's do not), and its subcategories crash the gamepad
-- smart-navigation cursor (ScrollUtil.lua IsSelected on a released list button).
local function RegisterSettings()
    if ns.settingsRegistered or not Settings or type(Settings.RegisterCanvasLayoutCategory) ~= "function" then
        return
    end

    ns.settingsRegistered = true

    -- Hidden until the Settings window displays it, so OnShow always fires.
    local panel = CreateFrame("Frame")
    panel.name = "Backhand"
    panel:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(560, 1)
    scrollFrame:SetScrollChild(content)

    -- Each control registers a function that reloads it from BackhandDB.
    local refreshers = {}
    local y = -6
    local sliderCount = 0

    local note = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 6, y)
    note:SetWidth(540)
    note:SetJustifyH("LEFT")
    note:SetText("With a controller, use the mouse on this page. The gamepad cursor cannot enter it without freezing Forever when Settings is closed. Paddle keys, lock/unlock and reset also work through /backhand.")
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
            BackhandDB[key] = self:GetChecked() and true or false
            onChange(BackhandDB[key])
        end)
        AttachTooltip(checkbox, label, tooltip)
        table.insert(refreshers, function()
            checkbox:SetChecked(BackhandDB[key] == true)
        end)
        y = y - 30
    end

    -- OptionsSliderTemplate needs a global name on Classic-derived clients.
    local function AddSlider(key, label, minValue, maxValue, step, tooltip)
        sliderCount = sliderCount + 1
        y = y - 16
        local slider = CreateFrame("Slider", "BackhandSettingsSlider" .. sliderCount, content, "OptionsSliderTemplate")
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
            if math.abs((tonumber(BackhandDB[key]) or 0) - value) > 0.001 then
                BackhandDB[key] = value
                ApplyAppearance()
            end
        end)
        AttachTooltip(slider, label, tooltip)
        table.insert(refreshers, function()
            local value = tonumber(BackhandDB[key]) or minValue
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
        "Normally Backhand unlocks automatically while WoW Edit Mode is open. Enable this to move the four panels independently without opening Edit Mode.",
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

    AddButton(
        "Controller",
        function()
            return GetProfileChoiceLabel(GetProfileSetting())
        end,
        function()
            CycleControllerProfileSetting()
            ns.RefreshSettingsKeyRows()
        end,
        "Which paddle controller you use. Auto detects the Xbox Elite and DualSense Edge from the connected controller. Click to step through Auto, Xbox Elite, DualSense Edge and Generic; pick one manually when Steam Input, reWASD or a Bluetooth driver hides the real controller. Changing it never touches your paddle keys or actions."
    )

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
        "Scales all four Backhand panels. 1.00 matches the size of the native crossbar slots."
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
        "View Diagnostics",
        function()
            ShowDiagnosticsFrame()
        end,
        "Shows native storage, LT/RT detection, and native art status as plain text you can select and copy (Ctrl+C) into a bug report. Same as /backhand diag copy; /backhand diag prints it to chat."
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
    ns.RefreshSettingsKeyRows = function()
        if panel:IsVisible() then
            RefreshControls()
        end
    end

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    ns.settingsCategory = category
end

local function OpenSettings()
    if not ns.settingsRegistered then
        RegisterSettings()
    end

    if ns.settingsCategory and Settings and type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    else
        Print("The native Settings UI is not available yet.")
    end
end

ns.RegisterSettings = RegisterSettings
ns.OpenSettings = OpenSettings
