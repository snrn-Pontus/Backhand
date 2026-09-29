# Backhand

Rear-paddle action panels for **WoW: Forever**, nested in the native gamepad crossbar. Built for the Xbox Elite Series 2; also works with the PlayStation DualSense Edge and any other controller whose extra buttons can be mapped to keys on PC.

Backhand is part of the SNRN addon family. It was called PaddleSlots up to version 0.7.9.

![Backhand panels inside the Forever crossbar](screenshots/ui.png)

Forever's crossbar gives you the d-pad and face buttons on four layers (no trigger, LT, RT, LT + RT). Backhand adds a 2 x 2 group for the P1-P4 paddles to each layer: 16 more actions without taking your thumbs off the sticks. The panels use Blizzard's own crossbar art, expand and highlight exactly like the native bars, and sit next to the bar that uses the same trigger combination.

Built for **World of Warcraft: Forever** only (Interface 16001). It relies on Forever's native crossbar and gamepad API and does nothing on other clients.

## Quick start

1. Map each paddle to a key WoW does not use. Xbox Elite with the Xbox Accessories app: paddle to F9, F10, F11, F12. Steam Input or reWASD (Xbox Elite, DualSense Edge, others): paddle to F13, F14, F15, F16.
2. In game open **Settings > AddOns > Backhand** (or type `/backhand`), click **Assign P1-P4** and press each paddle in turn.
3. Drag spells, items or macros onto the paddle slots. Hold LT, RT or both to fill the other layers.

Panels can be moved in WoW's normal Edit Mode, or with **Unlock panels outside Edit Mode** in the settings. `/backhand reset` puts them back into the crossbar.

## Settings

Open:

**Settings → AddOns → Backhand**

or use:

`/backhand`

Options include:

- Unlock panels outside Edit Mode
- Only show in gamepad mode (panels hide in mouse-and-keyboard mode, stay visible while unlocked or in Edit Mode)
- Paddle inputs (one row per paddle, click to assign by pressing), Assign P1-P4, Setup guide
- HUD scale
- Inactive panel opacity (1.00 = native, no fading)
- Focus highlight and strength
- LT / RT modifier icons (off by default; the native crossbar shows the same prompts)
- Paddle prompts on the focused panel
- Diagnostics

## Paddle inputs

On Windows the Xbox Elite Series 2 does not report its paddles to games, and the DualSense Edge's back buttons arrive as copies of the face buttons. WoW only sees whatever the Xbox Accessories app, Steam Input or reWASD maps a paddle to, so Backhand listens for a configurable input per paddle instead of assuming the native `PADPADDLE1-4` keys.

Backhand never takes over a button the native gamepad UI uses. **Settings -> AddOns -> Backhand -> Paddle inputs** shows one row per paddle whose button reads the current input; click it and press the paddle to assign a new one. Accepted inputs are only ones WoW does not use:

- physical keyboard keys with no WoW binding (F9-F12 on a compact keyboard; also F6-F8, Page Up/Down, Scroll Lock, Pause, or Numpad keys), for the Xbox Accessories app's keyboard key mapping,
- the Share button (unused by the native UI, if Xbox Accessories offers it for your controller),
- keyboard F13-F24, for Steam Input or reWASD sending keys that are not on the keyboard,
- the native paddle keys, for controllers that actually report paddles.

**Assign by pressing** opens a prompt and assigns each paddle to whatever the controller sends when you press it. If that is A, B, X, Y, a stick click, or any other native button, the prompt refuses it, explains that the controller profile is mirroring the paddle, and keeps waiting. Keyboard keys that already have a binding are refused too. **Setup guide** opens an in-game window with the step-by-step instructions for both routes and a live "last input detected" line.

Two routes:

1. **Xbox Accessories keyboard mapping**: map each paddle to a real key WoW leaves unbound (F9-F12 on a compact keyboard; also F6-F8, Page Up/Down, Scroll Lock, Pause, or Numpad keys), then use Assign by pressing. Share also works for one paddle if the app offers it.
2. **Steam Input or reWASD**: install Steam's Xbox Extended Feature Support driver (or use reWASD), map the paddles to F13-F16, leave them unassigned in Xbox Accessories, and select Keyboard F13-F16 in the addon. All four paddles work and the native layout stays intact. If a paddle press flips the UI to mouse-and-keyboard mode, pin the interface style to gamepad in the game's controls settings.

**PlayStation DualSense Edge**: Sony has no PC app for the Edge, and without a profile the back buttons and Fn buttons just repeat face buttons (Steam shows them as Circle and Cross, so the addon refuses them). Steam Input and reWASD do see the back buttons as their own inputs: add WoW as a non-Steam game, enable PlayStation controller support in Steam's controller settings, bind the two back buttons (and, if you like, the two Fn buttons) to F13-F16, and use route 2 above. A PS5 is not needed for this; the Edge's own profiles only matter if you also want them on the console.

The client's own default config for the Elite Series 2 (vendor 1118, product 767) maps raw buttons 16-19 to PADPADDLE1-4, but the controller never sends them on Windows. `/backhand test` shows raw presses; `/backhand learn` is only useful for controllers whose paddles arrive on other raw indices.

## Usage

Drag a spell, item, macro, or supported action-bar action onto any paddle slot. Press P1-P4 to activate the corresponding action in the currently active controller layer.

Paddle actions are saved per character, in `WTF\Account\<account>\<realm>\<character>\SavedVariables\Backhand.lua`. Paddle keys, panel positions and the appearance settings are shared by every character on the account and live in `WTF\Account\<account>\SavedVariables\Backhand.lua`. Updating from 0.7.6 or older copies the old account-wide actions to each character the first time it logs in, so nothing disappears; clear the slots you do not want on that character with `/backhand clear`.

## Slash commands

- `/backhand` (or the old `/paddles`) — open native Backhand settings.
- `/backhand unlock` — move panels outside WoW Edit Mode.
- `/backhand lock` — lock panels outside WoW Edit Mode.
- `/backhand reset` — reset all four panel positions to the nested crossbar layout.
- `/backhand reset <base|lt|rt|both>` — reset one panel.
- `/backhand clear <base|lt|rt|both> <1-4>` — clear one paddle action.
- `/backhand guide` — open the setup guide window.
- `/backhand assign [1-4]` — assign one paddle (or all four in order) by pressing it.
- `/backhand keys [P1 P2 P3 P4 | reset]` — show or set the paddle inputs, e.g. `/backhand keys F13 F14 F15 F16`.
- `/backhand diag` — print gamepad integration diagnostics, including the paddle inputs and which raw buttons carry PADPADDLE1-4.
- `/backhand diag copy` — open the same diagnostics as plain text you can select and copy.
- `/backhand test` — for 30 seconds, print the raw controller button index of anything you press and what the client maps it to. Use it to confirm the paddles reach WoW at all.
- `/backhand learn` — press P1, P2, P3, P4 in order. The addon writes a device config (vendor/product specific) through `C_GamePad.SetConfig` so those raw buttons become PADPADDLE1-4. The client stores it in `WTF/GamePadConfig_AddOns.json`. Learning refuses raw buttons the client already uses (A/B/X/Y, D-pad, ...), because a paddle arriving as one of those means the controller profile mirrors it, and rebinding it would take the button away from the native UI. `/backhand learn force` overrides that check. `/backhand learn cancel` aborts; `/backhand learn clear` deletes the addon's device config again (follow with `/reload`).
- `/backhand help` — print command help.

## Diagnostics

`/backhand diag` reports:

- addon version and client build
- native storage status and slots
- storage scope (per character, and whether the actions were copied from an older account-wide profile)
- LT / RT bindings
- modifier-emulation CVars
- LT / RT mapped button indices and current values
- visual detection method and visual panel
- secure panel
- native style CVars and native art availability
- secure panel-driver mode
- Edit Mode integration state

The most useful lines when validating a Forever build are **Modifier CVars**, **Mapped state**, **Visual panel**, and **Secure panel**.

To attach the report to a bug report, open **View Diagnostics** in the Diagnostics section of the Backhand settings (or run `/backhand diag copy`), click **Select All**, and press Ctrl+C. The text has no chat color codes, so it pastes cleanly into GitHub or Discord.

The full version history is in [CHANGELOG.md](CHANGELOG.md).
