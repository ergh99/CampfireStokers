# Craft Profession-Switch Investigation (unresolved)

Status: **open, unresolved**. Written 2026-10-05 to bootstrap a fresh
session after this one accumulated too many false starts. Read this
in full before proposing any new test - most obvious hypotheses below
are already disproven with real in-client evidence.

## Problem statement

`C_TradeSkillUI.CraftRecipe(recipeSpellId)` only produces a visible
effect (cast bar + character animation) when the correct profession is
already "active" on the client. There is a persistent, client-side
"which profession is active" state, separate from which panel is
currently visually shown, that this project has not found any reliable
way to set programmatically. The profession campfire-goods feature's
"craft" action (`Professions.lua`'s `Craft` function) depends on being
able to do this silently/automatically - that is currently unverified
to work except in the one lucky case where the target profession
happens to already be active.

## Confirmed facts, in order of discovery

1. `CraftRecipe` never throws, with any arguments, from any context
   (`/run`, or from within a real secure button's `PreClick`). It
   either visibly starts a cast, or does nothing at all - there is no
   error signal to distinguish success from failure.
2. A bare `CraftRecipe(id)` call does **nothing visible** (no cast bar,
   no animation) when the real Blizzard crafting frame (`ProfessionsFrame`)
   is not open. Confirmed by direct visual observation, not by checking
   bag counts afterward - an instant bag-count check cannot distinguish
   "nothing happened" from "a multi-second cast just started," and a
   null visual result (no cast bar/animation) is the standard this
   investigation uses; it does not need a follow-up verification command.
3. `CraftRecipe` **does** work (real cast bar + animation) when
   `ProfessionsFrame` is open and showing the matching profession/recipe -
   this was the original, independently-discovered trigger for this
   whole investigation (manually opening the real profession panel
   before clicking this add-on's craft button made it work).
4. `C_TradeSkillUI.OpenTradeSkill(recipeSpellId)` produces **no visible
   effect at all** - does not open any frame, does not change anything
   observable.
5. `C_TradeSkillUI.OpenRecipe(recipeSpellId)` **does** visibly open the
   real frame (global name `ProfessionsFrame`, confirmed via
   `ProfessionsFrame:IsShown()` returning `true`), with the specific
   recipe highlighted/selected - confirmed multiple times, including
   with the selection held visible for 2+ seconds.
6. Hiding `ProfessionsFrame` immediately after calling `CraftRecipe`
   (same synchronous tick, no delay) does **not** interrupt an
   already-started cast - the cast bar/animation plays through to
   completion regardless of the frame's visibility at that point.
   Confirmed via: `/run C_TradeSkillUI.OpenRecipe(1230161)
   C_TradeSkillUI.CraftRecipe(1230161) ProfessionsFrame:Hide()`
   producing a real cast + animation.
7. `CastSpellByName(professionName)` (e.g. `"Blacksmithing"`) **does**
   visibly open that profession's real panel when called from `/run` -
   it does not throw and does not require a secure/hardware-event
   context (unlike `C_Item.UseItemByName`, confirmed earlier in this
   project to require `SecureActionButtonTemplate`).
8. There is a persistent "active profession" state, independent of
   which panel is currently visible, that determines whether
   `CraftRecipe` actually does anything. The only thing confirmed to
   reliably set it is genuine, direct player interaction with the real
   UI (manually opening a profession's panel themselves). Confirmed:
   after manually closing a non-Mining profession's panel, later
   manually re-opening "the profession UI" generically (not casting a
   specific profession) still showed that same non-Mining profession
   selected - i.e. the player's own manual action correctly persists.
9. No combination of `OpenTradeSkill`, `OpenRecipe`, or `CastSpellByName`
   has been shown to reliably switch this active-profession state away
   from whatever a profession was last genuinely/manually viewed, when
   targeting a **different** profession than that one. This has failed
   consistently across every variation tried:
   - Called from `/run` or from a real secure button's `PreClick`
     (a genuine hardware-click context) - no difference observed.
   - With no delay, a 1-frame delay (`C_Timer.After(0, ...)`), or a
     2-second delay between the "open/switch" call and `CraftRecipe`.
   - With `CraftRecipe` called as `CraftRecipe(id)` or explicitly as
     `CraftRecipe(id, 1)` (explicit `numCasts`).
   - Even in a **self-match** case: Blacksmithing's panel manually
     opened and closed, then the identical script (byte-for-byte the
     same as the one confirmed working for Mining) targeting
     Blacksmithing's **own** recipe (1230171) - still produced no cast.
     This directly contradicts the simpler "just needs the target to
     match what was last displayed" theory; something else is also
     required, not yet isolated.
10. One confirmed success case does not fit the "closed first, then
    click" pattern used in most later tests: when a profession's panel
    was **still shown** (not closed first) at the moment of clicking,
    and the script's target matched that shown profession, a single
    click (`OpenRecipe` -> `CraftRecipe` -> `Hide`, no delay) closed the
    panel **and** started a craft, immediately, no second click needed.
    This is the most recent reliably-reproduced success. Whether "panel
    still open at click time" vs "closed first" is actually the
    relevant variable, or just incidental to that specific test, is
    **not resolved** - the user explicitly disputed this reading before
    this document was written ("the last success was without the panel
    open"), so do not assume it without retesting carefully and
    confirming exactly what was open/closed at each step.

## Hypotheses tested and disproven - do not retest these

- "Needs a delay for the profession-switch to commit" - disproven.
  Tried 0 frames, 1 frame, and 2 seconds, all failed, including with
  the correct recipe visually confirmed selected for the entire 2-second
  window.
- "Needs `CraftRecipe`'s full/explicit argument list" - disproven.
  Explicit `numCasts = 1` made no difference.
- "It's about which recipe/profession specifically (Mining/Lodestone
  vs. Blacksmithing/Sharpening Wheel)" - disproven by the Blacksmithing
  self-match failure (fact 9 above).
- "Must run from a genuine secure/hardware-click context, not `/run`" -
  not sufficient on its own. A real secure button's `PreClick` showed
  the identical failure pattern `/run` did.
- My own earlier claim that "`OpenRecipe` always correctly shows the
  panel with the right recipe selected regardless of prior state" -
  **wrong**, corrected mid-session. In the mismatch case, `OpenRecipe`
  for a new target just closes whatever profession's panel was already
  shown, rather than opening/selecting the new target.

## Confounding variable raised but not yet tested

This project's own real `Professions.lua` module (not test code) was
already fully built and loaded throughout every test in this
investigation. `CS.Professions.CreateEventFrame` refreshes the real
campfire panel on every `BAG_UPDATE_DELAYED`, and that refresh calls
`EvaluateGood` for all 11 known campfire goods - which calls
`C_TradeSkillUI.GetRecipeInfo` and `GetRecipeSchematic` for every one of
them, repeatedly, in the background, independent of whatever manual
test is being performed, whenever the campfire panel is open (i.e.
whenever the player is at a campfire). Also, `WarmItemCache` does the
same for every recipe once at `ADDON_LOADED`.

**Not yet tested**: whether this background querying has any side
effect on the "active profession" state being investigated. The
proposed next step, not yet completed: retest the Blacksmithing
self-match scenario (fact 9) while **not standing at a campfire**, so
`CS.Detection.atFire` is false and the real panel's profession block -
and therefore this background querying - is not running at all.

## Also not yet tested

- Whether the **player's own genuine click** on the real "Create"
  button succeeds in the mismatch case, after this add-on's script
  opens the correct recipe via `OpenRecipe` (visually confirmed
  correct) but a different profession was genuinely active before. The
  user directed this to be *assumed* true rather than tested, reasoning
  that doubting the game client's own UI is not productive - but it has
  not actually been empirically confirmed in this specific mismatch
  scenario within this session.
- What Blizzard's own "Create" button actually calls internally - is it
  really a bare `CraftRecipe(id)`, or does it pass additional context
  (e.g. a captured reagent selection, a profession/skill-line id) that
  this add-on has never replicated?
- Whether a dedicated "set active profession" function exists elsewhere
  in `C_TradeSkillUI`'s ~146 functions that hasn't been tried. (The
  function *names* were enumerated early in the broader profession
  research - see `docs/research.txt` - but not every one has been
  tested for this specific purpose.)

## Current code state (as of this document)

- `CraftSwitchTest.lua` - temporary, in the TOC (loads first, before
  `Data.lua`). Secure test button at screen center, +240y, labeled "CS
  Craft Switch Test". Slash command `/cscraftswitch <recipeSpellId>`
  changes its target (default 1230161, Mining's Lodestone). Current
  `PreClick` body: `OpenRecipe(id)` -> `CraftRecipe(id)` -> `Hide()`,
  fully synchronous, no delay, no extra arguments - this is the
  "confirmed success" form from fact 10, not yet re-confirmed since the
  self-match failure in fact 9. Remove this file and its
  `CampfireStokers.toc` entry once this investigation concludes, per
  its own header comment - it is temporary, not shipped.
- `.luacheckrc` - `ProfessionsFrame` is a permanent `read_globals` entry
  now (used by the real `Professions.lua` too, not just the test).
  `SLASH_CAMPFIRESTOKERSCRAFTSWITCHTEST1`/
  `SlashCmdList.CAMPFIRESTOKERSCRAFTSWITCHTEST` are temporary `globals`
  entries for this test file, marked as such in a comment - remove them
  alongside the file. `CastSpellByName` was added then removed when the
  test moved away from using it. `luacheck .` is currently clean (0
  warnings/errors).
- `Professions.lua`'s real `CS.Professions.Craft(recipeSpellId, options)`
  (around line 230) implements `OpenRecipe` -> `CraftRecipe` -> hide
  `ProfessionsFrame`, with DI options for all three steps, matching
  fact 10's form. **This has not been confirmed reliable** given
  everything above - it may only work when the target profession
  happens to already be active, same as the test button.
- `docs/decision-log.md`'s 2026-10-05 entry "CraftRecipe actually
  requires the real crafting frame" documents the **earlier, now
  incomplete** understanding (OpenRecipe + CraftRecipe + Hide believed
  sufficient). That entry should be corrected or superseded once this
  investigation concludes - do not treat it as settled.
- `definition.md`/`tasks.md` were updated to retract "crafting is not
  the hard part" and describe the open+craft+hide mechanism - also
  written before this session's later findings complicated the picture
  further. May need another correction pass once resolved.

## Suggested next step

Run the confounding-variable test (not at a campfire) first, since
it's cheap and directly actionable. If that doesn't change the outcome,
the player's-own-click test (listed under "also not yet tested") is
the next most informative, since it would cleanly separate "our script
can't do this" from "nothing can do this short of the player's own
click."
