# Backhand changelog

## Unreleased

- **Panels collapse when a menu has gamepad focus**, like the native crossbar. Opening the game menu, bags, settings or any other controller-navigable window used to leave the selected paddle panel expanded. Backhand now follows the same check the crossbar uses (only the core gameplay bindings are active), so the panel collapses, its focus background, button prompts and LT / RT prompt hide, and it expands again when focus returns. The selected layer and the paddle bindings do not change. `/backhand diag` shows "Native crossbar focused" and "Visual expanded" (#5).

## 0.8.0 — Renamed to SNRN Backhand

- **PaddleSlots is now SNRN Backhand**, part of the SNRN addon family. The addon folder is `Backhand`, and the slash command is `/backhand`. The old `/paddles` still works.
- **Settings and paddle actions start fresh.** WoW keeps saved variables per addon folder, so the new folder cannot read the old PaddleSlots data. After updating, assign the paddle keys again (`/backhand assign`) and drag your actions back onto the slots. Remove the old `PaddleSlots` folder from `Interface\AddOns` if the CurseForge app leaves it behind, otherwise both addons try to use the paddles.
- The code is split into several files. No behaviour changes.

## 0.7.9 — Paddle layers in combat

- **Paddles switch layers in combat again.** On clients where LT and RT are not emulated Shift/Ctrl/Alt (the Forever default), PaddleSlots could only rebind the paddles outside combat, so they stayed on whichever layer was active when combat started. Each paddle now goes through a hidden secure button that checks, at the moment you press it, which native crossbar bar has focus, and fires that panel's action. `/paddles diag` reports this as "paddles follow the native crossbar focus".

## 0.7.8 — Copyable diagnostics

- **Copyable diagnostics.** The **Print Diagnostics** button in the settings is replaced by **View Diagnostics** (also `/paddles diag copy`); `/paddles diag` still prints to chat. It opens the `/paddles diag` report as plain text in a window with **Refresh**, **Select All** and **Close**, so you can press Ctrl+C and paste the whole report into a bug report. The chat output and the window share the same code, so they always match. Both now start with the addon version and client build (#11).

## 0.7.7 — Actions saved per character

- **Paddle actions and reserved native slots are now saved per character** (`SavedVariablesPerCharacter`). They used to be account-wide, so a second character of another class saw, and tried to cast, the first character's spells, and both characters fought over the same reserved action slots. Paddle keys, panel positions and appearance settings stay account-wide (#3).
- **Migration.** The first time each character logs in after the update, it takes a copy of the old account-wide actions and reserved slots, so what that character saw before the update is still there. Slots that hold another class's spells can be cleared with `/paddles clear`. The old account-wide copies are kept until every character has logged in.
- `/paddles diag` has a new "Storage scope" line that says whether this character's actions came from the account-wide migration.

## 0.7.6 — Settings freeze, combat and review fixes

- **Fixes the game freezing when the Settings window closes.** In gamepad mode, opening the PaddleSlots page and then closing Settings (with the controller or the Close button) locked up the client. The page used Blizzard's standard settings list, which triggers this on Forever. It is now a custom page built from plain checkboxes, sliders and buttons. The options are unchanged. The page has to stay out of reach of the gamepad cursor, because the freeze returns (for the rest of the session) as soon as the cursor knows about its controls. With a controller, use the mouse on the page, or `/paddles` for keys, lock/unlock and reset.
- **Panels no longer show or hide in combat.** Switching between controller and mouse/keyboard mid-fight used to trigger a blocked-action error, because the panels hold secure buttons. Visibility changes now wait until combat ends (#1).
- **The setup guide no longer swallows input.** If it was first opened in combat, it kept every gamepad button and key for the rest of the session. It now only opens outside combat, and it reads input only when that input also reaches the game (#5).
- **Upgrades from 0.6 / 0.7.0 migrate** even if those builds never saved a version number. The panels move to the 0.7.1 layout and the trigger prompts turn off, as the 0.7.1 notes promised (#4).
- **Leaving Edit Mode saves only panels you dragged.** Panels you never moved stay attached to the crossbar (#6).
- **Dragging an action off a paddle follows the action bar lock**, like the native bars: with bars locked, hold the pickup modifier (Shift by default). Edit Mode and the addon's unlock option still allow free dragging (#6).
- **Paddle prompts follow the focused panel** even when the game's action bar scaling is off (#6).
- **Stance bar check.** `/paddles diag` has a new "Native slot check" line that compares the reserved paddle slots with the slots the native crossbar uses. The addon also checks each stance or form bar when it becomes active, and warns in chat if that bar shares slots with a paddle (#2).
- `/paddles clear` rejects a fractional paddle number instead of erroring, and `/paddles keys A B C D` applies the bindings once, so a duplicate-key warning prints once (#6).

## 0.7.5 — New paddle icons

- New P1-P4 icons. Each shows its paddle's shape (P1/P2 the top levers, P3/P4 the bottom paddles, left and right) inside the same dark round button the crossbar uses for face buttons. Empty slots and the focused-panel prompts now use them instead of the native atlas, which only shows "P1" text.

## 0.7.4 — DualSense Edge in the docs

- The setup guide, README and addon summary now cover the PlayStation DualSense Edge. On PC its back buttons repeat face buttons until Steam Input or reWASD binds them to F13-F16, which is the same route the Xbox Elite uses. No PS5 is needed.
- The in-game setup guide window is taller to fit the extra section.

## 0.7.3 — Fix 0.7.2 failing to load

0.7.2 did not load at all: the file's main chunk exceeded Lua's limit of 200 local variables ("main function has more than 200 local variables"). The slot layout constants now live in one `LAYOUT` table, which brings the count back to 184. No behaviour change beyond the 0.7.2 fix finally taking effect.

## 0.7.2 — Secret cooldown values

Fixes a Lua error that fired repeatedly in combat on Forever once a paddle slot held an action:

```
PaddleSlots.lua:802: attempt to compare local 'duration' (a secret number value ...)
```

Forever hands addons "secret" numbers for some combat data (cooldowns, usability, range). They can be passed to widgets such as `Cooldown:SetCooldown`, but comparing them raises an error.

- **Cooldowns** now follow `Blizzard_ActionBar/ActionButton.lua`: the client's `isActive` flag decides whether a swipe is drawn and the timing values go to the Cooldown widget untouched. Applies to native storage slots and to fallback spell and item slots.
- **Usable tint, stack count, and range dot** no longer inspect values the addon is not allowed to read. A secret usability answer leaves the icon untinted, a secret count is handed straight to the font string like the native buttons do, and a secret range answer hides the dot.

## 0.7.1 — Panels nested in the crossbar

The default layout now puts each paddle panel inside the native crossbar, next to the bar that uses the same trigger combination, and the panels are anchored to `GamepadMainActionBarFrame` so they follow it if the crossbar is moved or scaled:

- **BASE** sits above the top bar, centred between its d-pad and face-button groups.
- **LT** and **RT** sit above the left and right bars, in the notch between the top d-pad slot and the top face-button slot of each bar.
- **LT + RT** sits in the free box in the middle of the cross, between the BASE bar and the LT + RT bar.

The gap between a native bar's inner d-pad slot and inner face-button slot is only 18 units wide, so a 2 x 2 paddle grid cannot sit inside it; the notch above the centre of each bar is the closest spot with enough room (the offsets are chosen so the expanded, focused grid still clears the expanded native slots). LT + RT is the tight one: its expanded grid overlaps the neighbouring native rings by a few units while both triggers are held.

- **Trigger prompts are off by default.** The crossbar already draws the LT, RT, and LT + RT prompts under its own bars, right next to the new panel spots, so the addon's copies are now the opt-in **Show LT / RT modifier icons** setting.
- Panels that were still at the 0.6 / 0.7 default spots move to the new layout automatically. Panels you moved yourself stay where they are; `/paddles reset` adopts the new layout.
- **Range feedback is polled** with `IsActionInRange` every 0.25 s. The previous push-based approach (`C_ActionBar.EnableActionRangeCheck`) trips a client assert on build 69913 for gamepad storage slots that no native button owns, which crashed the game on startup once a paddle slot held an action.
- **Assign by pressing** works on the first click. Creating the prompt window used to clear the capture state, which left the first prompt blank and unresponsive until it was opened a second time.

## 0.7.0 — Native crossbar look

The four paddle panels are now built from the same art and behaviour as Forever's native gamepad crossbar (`Blizzard_GamepadActionBars`):

- **Slots** use the native circle-slot atlases: `gamepad-actionbar-circleslot-border-normal` / `-pressed` / `-hover`, the circle drop shadow, the `CircleMask` icon mask, and the native circular cooldown swipe.
- **Focus** works like the native bars. The panel for the held trigger combination is *expanded* (40 px slots, `gamepad-actionbar-focus-bg-circ` focus shadow that settles to 40 % opacity, `gamepad-actionbar-focus-bg-section` highlight behind it). The other three panels are *collapsed* (32 px slots with the normal drop shadow). Nothing is dimmed by default any more, exactly like the native bars.
- **Pressed state** shrinks the slot by 4 px and nudges it down, then swaps to the pressed border, matching `ActionBarStyles.lua`. Paddle actions now fire on press (`useOnKeyDown`), like native gamepad buttons.
- **Modifier prompts**: the LT, RT, and LT + RT panels show Blizzard's own `InputIconTextureFrameTemplate` / `InputPromptTwoIconTemplate` trigger glyphs beneath the slots. They follow the connected controller's glyph style and switch to the focused variant when their panel is active.
- **Paddle glyphs**: empty slots show Blizzard's `Gamepad_Gen_Paddle1-4` glyphs (the same art the key-binding UI uses for paddles). Assigned actions on the focused panel get a small paddle prompt in the corner, like the native button prompts.
- **Usable / range feedback**: icons tint blue when out of resources and grey when unusable, and native-storage slots show the native range dot (polled since 0.7.1, see above).
- **Native settings are respected**: the game's `GamepadShowActionBarScaling`, `GamepadShowActionBarHighlight`, and `GamepadShowActionBarButtonPrompts` CVars control scaling, the focus highlight, and the paddle prompts, in addition to the addon's own options.
- **Focus detection** now asks the client the same question the native crossbar asks (`GamepadMode.IsLeftModifierDown` / `IsRightModifierDown`, falling back to the `GAMEPADLEFTMOD` / `GAMEPADRIGHTMOD` bindings) and listens to the native crossbar modifier callback. The mapped-state reader remains as a last resort.

Every native atlas has a bundled fallback, so the addon still renders on builds that rename art. `/paddles diag` reports the detection method and any missing atlases.

The settings now live on a single page. Selecting a settings category that has subcategories makes the client rebuild its category list, which crashes Blizzard's gamepad smart-navigation cursor (`ScrollUtil.lua: attempt to call a nil value` in `IsSelected`). Diagnostics moved to a **Print Diagnostics** button on that page.

Default panel positions in 0.7.0 flanked the native crossbar (BASE and LT on the left, RT and LT + RT on the right); 0.7.1 replaces that layout, see above.

## 0.6.0 — Independent panels, Edit Mode integration, LT/RT fix

### Independent HUD pieces

The four controller layers are now four separate frames:

- **BASE**
- **LT**
- **RT**
- **LT + RT**

Each frame can be positioned independently. Their positions are stored separately in `PaddleSlotsDB.panelPositions`.

### WoW Edit Mode

PaddleSlots listens to Blizzard's native `EditMode.Enter` / `EditMode.Exit` lifecycle. When normal WoW Edit Mode opens, all four PaddleSlots panels become independently draggable and get an edit overlay. Leaving Edit Mode locks them again and stores their positions.

Blizzard does not expose a supported public API for third-party addons to become first-class Edit Mode systems, so PaddleSlots deliberately does **not** call the internal `EditModeManagerFrame:RegisterSystemFrame()` machinery. That avoids tainting Blizzard's Edit Mode while still making the panels movable when you use the normal Edit Mode UI.

You can also enable **Unlock panels outside Edit Mode** in PaddleSlots settings if you want to move them without opening Blizzard Edit Mode.

### LT / RT panel detection

The previous version had two problems:

1. Forever routes both LT and RT through the same native `InputFunctionBindingButton_PADTRIGGER` click target, so wrapping that frame cannot identify which physical trigger caused the click.
2. The old mapped-state reader assumed the same index base for `C_GamePad.ButtonBindingToIndex()` and the Lua `GamePadMappedState.buttons` table. On your client that made LT resolve to the wrong state entry.

0.6.0 removes the shared native-click wrapper and detects the mapped-state table's index base at runtime before reading LT/RT. Visual state now distinguishes:

- no trigger → **BASE**
- LT → **LT**
- RT → **RT**
- LT + RT → **LT + RT**

For combat-safe paddle rebinding, PaddleSlots also detects whether Forever maps LT and RT to distinct native modifier CVars (`GamePadEmulateShift`, `GamePadEmulateCtrl`, or `GamePadEmulateAlt`). When it does, PaddleSlots uses a secure state driver so the paddle bindings can switch layers during combat without replacing Blizzard's trigger bindings.

If the client does not expose both triggers as distinct secure modifiers, the addon still follows the mapped controller state and switches correctly outside combat. `/paddles diag` reports exactly which mode is active.

### Native gamepad action storage

The storage scanner now handles Forever's separate pet-action range correctly. In current builds the pet range can begin below the normal gamepad storage range (for example pet storage near 11 and general gamepad storage around 181); the old scanner incorrectly treated that as an upper boundary and immediately fell back to SavedVariables.

When a safe block of unused native gamepad action-storage slots is available, PaddleSlots uses it for new/empty profiles. If you already have actions stored in the SavedVariables fallback, the addon deliberately keeps that mode so an update never makes existing paddle assignments disappear. Otherwise it falls back whenever the native pool is unavailable or unsafe.
