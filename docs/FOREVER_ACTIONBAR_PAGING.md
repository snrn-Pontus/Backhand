# WoW: Forever action-bar paging from Backhand paddles

This note captures the research behind [issue #16](https://github.com/snrn-Pontus/Backhand/issues/16): using controller back paddles to move between WoW: Forever's native action-bar pages without requiring the default `LB + RB + Left/Right` chord.

## Summary

This is feasible, and Backhand already has most of the infrastructure required.

The recommended implementation is **not** to emulate the native controller chord and **not** to call `C_ActionBar.SetActionBarPage()` from an ordinary paddle click handler. Instead, create hidden `SecureActionButtonTemplate` buttons with the built-in `actionbar` action type and route selected paddle bindings to those buttons.

For example:

```lua
local previous = CreateFrame(
    "Button",
    "BackhandActionBarPrevious",
    UIParent,
    "SecureActionButtonTemplate"
)
previous:RegisterForClicks("AnyUp", "AnyDown")
previous:SetAttribute("useOnKeyDown", true)
previous:SetAttribute("type", "actionbar")
previous:SetAttribute("action", "decrement")

local next = CreateFrame(
    "Button",
    "BackhandActionBarNext",
    UIParent,
    "SecureActionButtonTemplate"
)
next:RegisterForClicks("AnyUp", "AnyDown")
next:SetAttribute("useOnKeyDown", true)
next:SetAttribute("type", "actionbar")
next:SetAttribute("action", "increment")
```

Those frames should be created and configured out of combat, then used as secure binding targets.

## Forever API support

The current API documentation lists these action-bar APIs for WoW: Forever:

```lua
C_ActionBar.GetActionBarPage()
C_ActionBar.SetActionBarPage(pageIndex)
```

`C_ActionBar.SetActionBarPage` is documented for Forever 1.60.1:

- https://warcraft.wiki.gg/wiki/API_C_ActionBar.SetActionBarPage

This establishes that Forever has the native page concept Backhand needs to control.

For implementation, however, direct calls to `SetActionBarPage()` are unnecessary. The secure button system already exposes action-bar paging declaratively.

## Secure action support

`SecureActionButtonTemplate` supports an action type named `actionbar`. Its `action` attribute can be:

- a numeric page
- `"increment"`
- `"decrement"`
- a two-page toggle string

Reference:

- https://warcraft.wiki.gg/wiki/Secure_action_button
- Blizzard UI source mirror: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua

The important consequence is that a hardware press can execute page navigation through WoW's secure click path. Backhand therefore does not need an insecure `OnClick` function that tries to mutate the native action-bar page during combat.

Live validation on Forever is still required, but this is the same secure-action mechanism intended for protected button execution rather than an addon-side workaround.

## Why this fits Backhand

Backhand already routes physical paddle inputs to clickable secure frames.

`Layers.lua` currently:

1. resolves each configured paddle key and its LT/RT-modified variants;
2. binds those keys with `SetOverrideBindingClick` when out of combat;
3. mirrors the same bindings inside the `SecureHandlerStateTemplate` state driver so LT/RT layer changes remain combat-safe;
4. defers secure binding changes until combat ends when necessary.

Relevant files:

- [`Layers.lua`](../Layers.lua)
- [`Core.lua`](../Core.lua)
- [`Buttons.lua`](../Buttons.lua)
- [`FocusRouting.lua`](../FocusRouting.lua)

The native action buttons already use:

```lua
button:RegisterForClicks("AnyUp", "AnyDown")
button:SetAttribute("useOnKeyDown", true)
```

Page-navigation buttons should match that press behavior. The manual test still needs to verify that one physical press produces exactly one page change and does not page again on release.

## Recommended Backhand design

### Persist a paddle behavior

Keep physical key assignment separate from what the paddle does.

A simple first schema is:

```lua
BackhandDB.paddleActions = {
    P1 = "action",
    P2 = "action",
    P3 = "action",
    P4 = "action",
}
```

Supported values for the first implementation:

- `action`
- `actionbar-prev`
- `actionbar-next`

All existing users should migrate/default to `action`. Do not silently turn P3/P4 into page buttons.

### Create dedicated secure targets

A small `PageNavigation.lua` module is preferable to embedding more special cases in `Layers.lua`.

It can create and export two hidden secure buttons:

- previous page: `type = "actionbar"`, `action = "decrement"`
- next page: `type = "actionbar"`, `action = "increment"`

`Backhand.toc` should load the module before `Layers.lua` so the secure targets exist before bindings are registered.

### Route bindings by behavior

The binding code should resolve a target for each physical paddle:

```text
paddle behavior       secure target
-------------------   ------------------------------------
action                existing panel button / focus router
actionbar-prev        BackhandActionBarPrevious
actionbar-next        BackhandActionBarNext
```

The existing key-variant logic should remain unchanged. It already handles the base paddle key plus emulated LT/RT modifier combinations.

For the first version, page navigation should be a property of the **physical paddle**, so a paddle configured for paging continues to page while LT, RT, or LT+RT is held. This keeps the secure state driver simple and makes the behavior predictable.

If using a paging paddle only on selected Backhand layers becomes desirable, that should be implemented as a separate per-layer behavior model rather than sneaking another condition into the binding code.

## Settings UX

Each paddle should expose two independent concepts:

1. **Input** — which keyboard/gamepad key the controller sends.
2. **Behavior** — what Backhand does with that input.

Suggested behavior choices:

- Action slot
- Previous action-bar page
- Next action-bar page

The setup guide should continue to focus on detecting/assigning the physical paddle input. Behavior belongs in normal addon settings.

## Diagnostics

Diagnostics should report both values, for example:

```text
P3: F15 -> previous action-bar page
P4: F16 -> next action-bar page
```

This matters because a correct hardware mapping with an unexpected behavior assignment otherwise looks exactly like a broken binding.

## Expected interaction with native Forever controls

Backhand should not remove or replace Forever's own page-navigation binding. The existing `LB + RB + Left/Right` path should remain available.

A paging paddle is simply another secure input path to the same native action-bar paging behavior.

Backhand should also avoid hard-coding assumptions such as "there are exactly N usable pages". Using `increment` / `decrement` delegates valid-page behavior to the native action-bar implementation.

## Combat and secure-state rules

The implementation should preserve Backhand's existing rule:

- secure frames/attributes/bindings are prepared or changed outside combat;
- if configuration changes during combat, set `ns.pendingSecureRefresh` and apply after combat;
- the actual paddle press can execute the preconfigured secure action during combat.

Do not add a normal Lua `OnClick` handler that calls `C_ActionBar.SetActionBarPage()` for the paging action. That needlessly bypasses the secure action mechanism and makes combat behavior more fragile.

## Manual validation required

This research establishes a supported implementation path, but the following must still be tested in the Forever client:

- previous and next page out of combat;
- previous and next page in combat;
- wrap-around / valid-page behavior;
- one page transition per press with `useOnKeyDown = true`;
- bare paddle, LT, RT, and LT+RT binding variants;
- native `LB + RB + Left/Right` remains functional;
- forms/stances/other gameplay states that alter native action-bar behavior;
- existing Backhand action paddles remain unaffected;
- configuration changes made during combat apply correctly after combat.

## Conclusion

Direct paddle paging is a good fit for Backhand's current architecture. The clean path is to bind selected paddles to hidden secure `actionbar` buttons using `increment` and `decrement`, while retaining the current secure driver and combat-deferred configuration model.

Implementation is tracked in [issue #16](https://github.com/snrn-Pontus/Backhand/issues/16).
