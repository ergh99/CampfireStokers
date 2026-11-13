# Session Brief: First-Run Tutorial

Written 2026-11-12 to start a fresh working session on this topic. It is
self-contained: the decisions below were made by the project owner and
shouldn't be re-asked. Out of scope: the feature-button recipe gate,
which has its own brief, [feature-recipe-gate-plan.md](feature-recipe-gate-plan.md).

## Start here

1. Read [AGENTS.md](../AGENTS.md) (Lua 5.1, no-globals, secret-value
   rules, test commands) and [tutorial-best-practices.md](tutorial-best-practices.md)
   (the research behind this plan, with sources).
2. Run `git status`. On 2026-11-12 the tree had uncommitted work in UI.lua,
   Options.lua, Professions.lua, Data.lua and docs. Don't assume a clean
   tree, and don't fold unrelated changes into this work.
3. Run the full check suite (AGENTS.md, "Test, secret-value lint and
   release commands") to get a green baseline before changing anything.
4. When approved, add the checklist at the end to [tasks.md](tasks.md)
   as T11.

## Goal

Teach a new player how to make the phrase tree their own, then how to use
it at a campfire. **Managing phrases and categories is the top
priority.** Sending phrases and the campfire feature buttons come second.

## Decisions (project owner, 2026-11-12)

| Question | Decision |
| --- | --- |
| Who sees it | **Everyone, once**, including players upgrading from v0.1.0 who already have saved data. |
| Shape | **A welcome card and a guided tour of the phrase editor**, with callouts on the editor's real controls. A second, shorter tour runs on the campfire panel. |
| When | **Welcome card shortly after login. Panel tour the first time the panel auto-opens at a campfire.** |
| What it teaches | Editing phrases and categories (first), click-to-send and Say/Yell, and the campfire feature buttons. Opening the panel manually isn't a step; the card mentions `/campfire` in one line. |
| Reset / Restore Defaults | **Not in the tour.** They're low priority; a mouseover tooltip is enough. |
| Blizzard's "Tutorials" setting (`hideHelptips` CVar) | **Ignored.** That setting is for the game client's own tips, not add-ons. |

## The player's experience

### 1. Welcome card (first login after install or update)

About 3 seconds after `PLAYER_LOGIN`, a small card appears in the active
panel style (Campfire or Forever):

> **Welcome to Campfire Stokers**
>
> - **Make it yours:** add your own categories and phrases, rename,
>   reorder and delete them.
> - **Click to talk:** at a campfire the panel opens by itself. One click
>   sends a phrase on Say or Yell.
> - **Campfire features:** your professions' campfire items, ready to
>   place, craft or request.
>
> `/campfire tutorial` replays this.
>
> **[Make it yours]**  [Later]

- **Make it yours** opens Settings > AddOns > Campfire Stokers and starts
  the editor tour.
- **Later**, the close button, and Esc all just close the card. The editor
  tour is then offered again at the end of the panel tour.
- If the player is in combat at login, the card waits for
  `PLAYER_REGEN_ENABLED`.

### 2. Editor tour (from "Make it yours")

Callouts on the real editor controls, one at a time, each with **Next**
(the last with **Done**) and a close X that ends the tour:

1. **Add Category** button: "Start your own category here."
2. **First category row**: its Rename / Add Phrase / Delete buttons,
   which are normally hover-only, are pinned visible for this step.
   "Hover any row to rename it, add phrases to it, or delete it."
3. **First phrase row**: Edit / Delete pinned visible. "Edit any phrase.
   Put %t in one to say your target's name."
4. **The `::` drag handle** on that row: "Drag rows to reorder."

Reset to Defaults isn't a tour step. It gets a mouseover tooltip instead
(it has none today): "Replace your whole phrase list with the starter
set, or bring back only the defaults you deleted." Restore Missing
Defaults is a choice in the confirmation popup that button opens, and
that popup's text already explains both.

### 3. Panel tour (first time the panel auto-opens at a campfire)

1. **First phrase button:** "Click a phrase to send it."
2. **Say/Yell toggle:** "Choose where phrases without a / go."
3. **First campfire feature button**, only if any are showing: "Place,
   craft, or ask the fire for materials. Hover one to see what it will
   do." The text points at the tooltip and doesn't promise the button is
   usable, so it stays correct whatever states the recipe-gate work adds
   (such as a grayed not-learned button).
4. **Last step**, if the editor tour hasn't run yet: "Make these yours" with
   a button that opens the editor tour.

The panel tour waits until the welcome card is gone. If the panel closes
partway through (for example, the auto-close countdown runs out), the
tour doesn't count as seen and runs again at the next auto-open.

If the feature step was skipped because no feature buttons were showing,
it shows by itself the first time any character's panel has one.

## Technical design

### New module: Tutorial.lua

Loaded after `Options.lua` and before `Core.lua` in the TOC. It splits
into two halves, matching how the rest of the repo is tested:

- **Pure logic, headless-tested:** `CS.Tutorial.IsDue(db, part)`,
  `CS.Tutorial.MarkSeen(db, part)`, the step lists as data, and
  `CS.Tutorial.NextStep(steps, index, context)`. `context` is a plain
  table (`{ hasFeatureButtons = true, editorSeen = false }`) so step
  skipping is testable without frames.
- **Frames, checked in-client:** the welcome card, the callout frame, and
  the event wiring.

### Saved state

```lua
CampfireStokersDB.tutorial = {
    version = 1,      -- CS.Tutorial.VERSION when the entries below were written
    welcome = true,   -- card shown
    editor = true,    -- editor tour reached Done or was closed with the X
    panel = true,     -- panel tour reached its end or was closed with the X
    features = true,  -- the feature-button step has been shown
}
```

- Only booleans and an integer, per AGENTS.md secret-value rule 5.
- Missing `tutorial`, or `version < CS.Tutorial.VERSION`: every part is
  due. That makes **everyone, once** work for v0.1.0 players with no
  migration, and raising `VERSION` later re-runs it after a significant
  change.
- The **card** is marked seen when shown, and also if building it throws.
  In that case one chat line points to `/campfire tutorial` instead.
- **Tours** are marked seen on Done or on the close X. A close caused by
  the anchor frame hiding doesn't count, so an interrupted tour resumes in
  context later.

### Callouts: our own frame, not Blizzard's `HelpTip`

`HelpTip:Show` checks `HelpTip:AreHelpTipsEnabled()` itself and refuses
to show anything while `hideHelptips` is set, with no override (see the
best-practices doc, section 9). Since this add-on must ignore that
setting, the tours use a small callout frame of our own in Tutorial.lua:

- One reusable frame: text, an arrow texture rotated toward the anchor, a
  Next/Done button, and a close X. Strata above `SettingsPanel`, clamped
  to the screen.
- It hides itself, and reports "target hidden", when its anchor frame
  hides. It uses an `OnHide` hook on the anchor, removed when the step
  ends.
- Visual: borrow HelpTip's stock textures/atlases (no HelpTip code), or
  match the active panel style. Pick in-client (V3). Stock textures only,
  since the add-on embeds no art.
- No CVar checks of any kind. This also avoids the shared-frame-pool
  taint question that using HelpTip would have raised.

### Changes to existing modules

| File | Change |
| --- | --- |
| `CampfireStokers.toc` | Add `Tutorial.lua` between `Options.lua` and `Core.lua`. |
| `Core.lua` | After `Bootstrap`, call `CS.Tutorial.Init()` (registers `PLAYER_LOGIN` and `PLAYER_REGEN_ENABLED`). |
| `Options.lua` | Expose the anchors: Add Category button, the first category row and first phrase row. Add `CS.Options.PinRowActions(rowId, on)` to force a row's hover widgets (`row.hoverWidgets`) visible and stop `OnLeave` hiding them. Add `CS.Options.Open()` (`Settings.OpenToCategory`). Start a pending editor tour from the canvas's `OnShow`, so it works however the editor was opened. Add a tooltip to Reset to Defaults and a "Replay tutorial" button. |
| `UI.lua` | Expose the first phrase button, the Say/Yell toggle, and the first visible feature button. In the auto-open path (`CS.UI.OnCampfireStateChanged`), call `CS.Tutorial.OnPanelAutoOpened()` after the panel is shown. Use the campfire boolean only, never aura data. Build the card from the active style's frame helpers. |
| `Launcher.lua` | `/campfire tutorial` replays the card. `/campfire tutorial reset` clears `CampfireStokersDB.tutorial` so the next `/reload` behaves like a first install. Update the unknown-command hint. |
| `Data.lua` | Every new string goes in `CS.Data.L`, including the Reset tooltip. |
| `.luacheckrc` | Add `UISpecialFrames` (Esc closes the card) and any other WoW global the code actually uses. No `HelpTip` or `GetCVarBool`. |
| `tests/tutorial_spec.lua` | New: `IsDue` for fresh, v0.1.0-upgrade, current and older version; `MarkSeen`; step skipping with and without feature buttons and with the editor tour done or not; tours not marked seen on target-hidden. |
| `tests/launcher_spec.lua` | Routing for `tutorial` and `tutorial reset`. |
| `tests/core_spec.lua` | `CS.Tutorial.Init` called once, stubbed like the UI/Options stubs. |

### One popup at a time

- The card and a tour never show together. The panel tour waits for the
  card's `OnHide`.
- If the player is already at a fire at login, the panel still auto-opens
  as normal (no change to detection or auto-open). The panel tour starts
  once the card closes.
- Nothing in the tutorial blocks sending or the panel's own behavior.

## In-client verification

These are client-behavior questions, so run them with the
`observation-ledger` skill and record the results in decision-log.md.
Keep any proposed `/run` command under 255 characters.

| # | Question | Why it matters |
| --- | --- | --- |
| V1 | Does `Settings.OpenToCategory` open our canvas category out of combat? What happens in combat? | "Make it yours" depends on it. Fallback: a chat line saying where to find it, with the tour still starting from the canvas's `OnShow`. |
| V2 | Does our callout frame draw above `SettingsPanel` and stay clamped at small resolutions and UI scales? | Editor tour visibility. |
| V3 | Which look reads better next to the editor and the panel: HelpTip's stock textures or the active panel style? | Picks the callout's visual. This is an aesthetic choice, not client research, so it doesn't go in the ledger. |
| V4 | Do pinned hover widgets stay visible through the editor tour and hide again correctly afterwards? | Editor tour steps 2-4. |
| V5 | With Blizzard's Tutorials setting off (`/console hideHelptips 1`), do the card and both tours still appear? | Confirms the add-on ignores that setting, as decided. |

Also add to definition.md's Known Deviations: **HelpPlate's "?" button is
disabled on Forever** (`Blizzard_HelpPlate/Camelot/HelpPlateOverrides.lua`
on the `forever` branch of Gethe/wow-ui-source).

## T11 checklist (to move into tasks.md)

- [ ] Tutorial.lua: pure due/seen/step logic plus `Init`, with headless tests.
- [ ] Saved state is `CampfireStokersDB.tutorial`, plain values only, and v0.1.0 saves see it once.
- [ ] Welcome card after `PLAYER_LOGIN` + 3 s, combat-deferred, styled to match the panel, closable with Esc, X and Later, draggable and clamped.
- [ ] "Make it yours" opens the editor and runs the four-step editor tour with hover widgets pinned.
- [ ] Reset to Defaults has a mouseover tooltip.
- [ ] Panel tour on the first auto-open, after the card, skipping the feature step when no feature buttons show. It resumes if cut short.
- [ ] The editor tour is offered at the end of the panel tour if it hasn't run.
- [ ] Callouts are our own frame and ignore `hideHelptips`.
- [ ] `/campfire tutorial`, `/campfire tutorial reset`, and a Replay button in Options.
- [ ] Strings in `CS.Data.L`, globals in `.luacheckrc`, and luac/luacheck/tests/wow-secret-lint all pass.
- [ ] V1-V5 confirmed in-client and recorded in decision-log.md. Definition.md updated (Features, Saved Variables, Known Deviations).

## Open questions for the project owner

None block starting. Each has a default that can be changed during review:

1. **Card wording.** The text above is a draft.
2. **Delay.** 3 s after login, matching CraftBoard.
3. **Tour state across characters.** Everything is account-wide, like the
   rest of `CampfireStokersDB`. The feature step is the one exception: it
   waits for a character with feature buttons.
