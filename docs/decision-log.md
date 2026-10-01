# Decision Log

Findings from T6's in-client verification (and later manual checks), and
any design decisions that followed from them. See
[tasks.md](tasks.md#t6-in-client-verification) and
[AGENTS.md](../AGENTS.md).

## 2026-09-30 — T6 in-client verification (first pass, out of combat)

Tested via `/cfs selftest` and manual checks, out of combat only.

- **Campfire aura spell ID**: confirmed `1229739`. `Detection.lua`'s
  `CAMPFIRE_SPELL_ID` placeholder (`0`) updated to this value. The
  `selftest` "campfire aura spell ID" check now reports `pass` with this
  number instead of `unknown`.
- **ReloadUI protection**: manually called `ReloadUI()` from a
  slash-command context (out of combat) and it ran without error — it was
  not blocked. No code change: this add-on already never calls `ReloadUI`
  regardless (`Options.lua` refreshes its editor in place instead), so this
  finding doesn't change anything, it just confirms that choice was already
  the right call rather than an unnecessary precaution. **Open**: not yet
  retested in combat.
- **Hardware-event requirement for Say/Yell/emote sends**: not tested this
  pass. **Open** — needs checking once UI.lua (T7) has real buttons to
  click, per Launcher.lua's self-test message for this check.
- **`%t` through SendChatMessage**: not tested this pass (self-test
  deliberately never auto-sends a real chat message). **Open**.
- **Aura reads while secrecy is active**: not tested this pass (player
  wasn't in a secrecy-forcing state; the check reports `unknown` and
  suggests `/console addonCombatRestrictionsForced 1` or entering
  combat/Mythic+/PvP). **Open**.
- **Everything else** (unknown-event registration, `C_Secrets`, the addon
  compartment, the emote command globals scan): no failures reported.

No failed assumptions to raise for a design decision from this pass.
Remaining opens (hardware-event requirement, `%t` substitution, aura reads
under real secrecy, ReloadUI in combat) carry forward to be checked
alongside T7's manual verification, once there's a panel to click through.

## 2026-09-30 — T6 in-client verification (second pass, in combat)

Same checklist, this time from inside combat, confirming the "aura reads
while secrecy is active" case the first pass couldn't reach.

- **Aura reads while secrecy is active — FAILED against the documented
  assumption**: `C_UnitAuras.GetPlayerAuraBySpellID` did **not** throw while
  `C_Secrets.ShouldAurasBeSecret()` was `true`, contradicting
  forever-addon-kit's finding (cited in `docs/definition.md`). Design
  decision: **no change to Detection.lua**. Its guard order — skip the read
  entirely once `ShouldAurasBeSecret()` is `true` — never depended on the
  read throwing; it was already the conservative choice regardless of this
  specific claim, and it means this code path is never reached in
  production either way.

  What did need fixing: the *selftest check itself* only asked "did the
  read throw," so it reported `fail` the moment a real client didn't throw
  — without ever checking whether `canaccessvalue()` would have caught an
  unsafe result some other way. That's the wrong question; the property
  that actually matters is whether *some* safety net (throwing, or
  `canaccessvalue` flagging the result as unreadable) fires before the
  addon would touch the data. Rewrote the check to test that directly: it's
  `pass` if the read throws, `pass` if it doesn't throw but
  `canaccessvalue(result)` is `false`, and only `fail` if neither happens.
  Added `launcher_spec.lua` tests pinning down all three branches with
  mocked `C_Secrets`/`C_UnitAuras`/`canaccessvalue`, since the gap that
  shipped here — an automated check that only exercised one of two safety
  mechanisms — is exactly the kind of thing a test should have caught
  before a human had to.
- **ReloadUI, hardware-event requirement, `%t` substitution**: still not
  retested in combat / still manual-only. Carry forward.

## 2026-09-30 — T6 in-client verification (third pass, in combat, corrected check)

Re-ran `/cfs selftest` in combat against the fixed check. Result:
**still `fail`**, but now for a more specific and informative reason:
`canaccessvalue(result)` returned `true` (readable), not `false`. Neither
safety net fired — the read didn't throw *and* `canaccessvalue` reports the
result as fully accessible.

**Conclusion: this campfire aura's data does not appear to be
secret-restricted on this build at all**, at least for
`C_UnitAuras.GetPlayerAuraBySpellID` on spell `1229739` during combat. This
is a plausible, low-stakes gap in the secret-value system rather than a
bug: "sitting at a campfire" carries no competitive information, so
Blizzard may simply not bother tainting it, unlike combat-relevant auras
the system exists to protect.

**Design decision: closed, no code change, and no further retesting
needed for this specific finding.** `Detection.lua` never attempts this
read while `ShouldAurasBeSecret()` is `true` — the guard order means this
result is informational, not something the add-on's safety depends on.
Keeping the `ShouldAurasBeSecret`-first guard regardless is still correct:
it costs nothing (a player in a secrecy-restricted state is already
unlikely to be at a campfire) and stays forward-compatible if a future
patch narrows or widens what's secret. The selftest check's message and
its doc comment in `Launcher.lua` are updated to state this conclusion
directly, so a future `fail` here reads as "known and accepted" rather
than an open question — a genuine status change (e.g. this aura becoming
actually restricted in a later patch) would still show up as a change in
which branch fires, just no longer as a surprise.

`ReloadUI` in combat, the hardware-event requirement, and `%t` substitution
remain open, to be checked alongside T7's manual verification.

## 2026-09-30 — T7 manual verification (panel clicks, ReloadUI in combat)

- **Hardware-event requirement for sends — CLOSED, no issue.** Clicking a
  phrase button in the panel sent it as expected. Send.lua's dispatch runs
  from the button's own `OnClick`, which is already a real hardware event,
  so nothing needed to change.
- **ReloadUI in combat — CLOSED, no issue.** `/run ReloadUI()` completed
  without error while in combat, same as the earlier out-of-combat result.
  Still no code change: this add-on never calls `ReloadUI` regardless
  (`Options.lua` refreshes its editor in place).

Only `%t` substitution remains open.

## 2026-09-30 — `%t` substitution verified, closing T6/T7

Tested via a temporarily injected `%t` phrase (`/run
table.insert(CampfireStokersDB.tree[1].children, {...})` + `/reload`, per
instructions given in this session, since Options.lua doesn't exist yet to
add one through the UI):

- With no target selected, the phrase row renders gray/disabled.
- With a target selected, the row renders white/enabled, live, without
  needing a reload (`PLAYER_TARGET_CHANGED` re-check confirmed working).
- Sending it substitutes the target's name correctly.

**Closed, no issues, no code change.** `UI.lua`'s `ContainsTargetToken` +
`applyRowState` gating and the client's own `%t` substitution both work as
designed.

This closes every check from T6's self-test and T7's manual verification
list: all either `pass`, or `fail`-but-understood-and-accepted (the one
aura-secrecy finding above), or confirmed manually with no issues.

## 2026-09-30 — T8 manual verification: StaticPopup's EditBox field renamed

Clicking "Add Category" opened the popup correctly but threw: `Options.lua:283:
attempt to index field 'editBox' (a nil value)` in `OnShow`. The error's
locals dump showed the actual field on this build's dialog frame is
`EditBox` (capital E) — confirmed by the same dump listing `ButtonContainer`,
`CloseButton`, `SubText`, etc., all PascalCase, consistent with
`Blizzard_StaticPopup_Game/GameDialog.xml`'s naming rather than the
classic lowercase `editBox` from older StaticPopup.lua-based dialogs.

**Design decision: fixed, all four `self.editBox`/`parent.editBox`
references in `Options.lua`'s `CAMPFIRESTOKERS_TEXT_INPUT` popup changed to
`self.EditBox`/`parent.EditBox`.** This is exactly the class of deviation
AGENTS.md's TOC-gate section warns about — retail-derived code (including
code written from general WoW addon knowledge, not just copied from a
specific reference repo) can't be assumed to carry field names over
unchanged. A comment was added at the registration site pointing back here.
UI.lua's own popup (`ShowTextPopup`) is unaffected — it builds its EditBox
by hand rather than through a `StaticPopupDialogs` template, so there's no
Blizzard-owned field name involved there.

**Open**: only the "Add Category" flow was exercised before this fix.
Re-verify Add Category, Add Phrase, Rename, and Edit Text all work
end-to-end (popup shows pre-filled text where expected, typing and
accepting actually applies the change) now that the EditBox reference is
correct.

## 2026-09-30 — T8 manual verification: empty row list, canvas never hidden

The same screenshot that caught the `EditBox` bug also showed something
easy to miss next to it: the options canvas rendered its top controls
(Add Category, Reset to Defaults, Restore Missing Defaults, the delay
field) correctly, registered under Settings → AddOns correctly, but the
row list below was completely empty — no category rows at all, even
though `CampfireStokersDB.tree` already had the five default categories
by the time the canvas could possibly be shown (`Core.lua` bootstraps it
before calling `CS.Options.CreateCanvas()`).

**Root cause**: `CS.Options.CreateCanvas()` never called `canvas:Hide()`
after creating the frame — unlike `UI.lua`'s `CreatePanel()`, which does.
A freshly created frame starts shown. `CS.Options.Refresh()` only runs
from the canvas's `OnShow` script, which only fires on an actual
hidden-to-shown *transition*; since the canvas's own `:IsShown()` was
already `true` from creation, the Settings system's later `:Show()` call
(when you navigate to the category) was a no-op as far as the frame's own
show state is concerned, so `OnShow` — and therefore `Refresh()` — never
fired.

**Design decision: fixed, added `canvas:Hide()` immediately after
creating the frame**, matching `UI.lua`'s pattern. This is a general
lesson for this codebase, not just an Options.lua quirk: any frame whose
content is built lazily on `OnShow` must start hidden, or that lazy build
silently never happens. Worth keeping in mind for any future frame using
this pattern.

Re-verify: reopening the options canvas now shows all five default
categories with their phrases, matching the campfire panel.

## 2026-09-30 — T8 manual verification: row list still empty after the Hide() fix

A second screenshot, after the `canvas:Hide()` fix was committed, showed
the same empty row list - top controls fine, no rows. Two more issues
found on closer review, both fixed without waiting for confirmation on
whether the running client had actually picked up the previous fix
(`/reload` is required for addon code changes to take effect; that's
unconfirmed for this screenshot), since both are real, independent
robustness gaps regardless:

1. **`CreateCanvas()` relied solely on `OnShow` to populate the row list
   the first time**, unlike `UI.lua`'s `CreatePanel()`, which also calls
   `CS.UI.Refresh()` once eagerly right after building the frame. Relying
   only on `OnShow` firing depends on an assumption about
   `Settings.RegisterCanvasLayoutCategory`'s show/hide behavior that was
   already flagged as unconfirmed for this build. Fixed: added an eager
   `CS.Options.Refresh()` call at the end of `CreateCanvas()`, matching
   `UI.lua`'s proven pattern.
2. **`canvas.rowContainer:SetWidth(canvas.scrollFrame:GetWidth())` ran
   once, at creation time** - before the Settings system has necessarily
   sized `canvas.scrollFrame` - and `SetWidth` freezes a value rather than
   tracking it live. If `scrollFrame` was still unsized (0 width) at that
   moment, `rowContainer` would be permanently pinned to 0 width, which
   would collapse every row (anchored between `rowContainer`'s LEFT and
   RIGHT) to nothing regardless of whether rows were actually being
   created. Fixed: moved this into `CS.Options.Refresh()` itself, so the
   width is re-synced to whatever `scrollFrame`'s current actual width is
   on every refresh (creation, `OnShow`, and every mutation), not just
   once.

**Open**: waiting on a retest to confirm which of the three fixes so far
(canvas:Hide, eager Refresh, live width resync) actually mattered versus
which were defensive-but-unnecessary. All three are safe to keep
regardless of which one was the real cause.

**Resolved (2026-09-30, retest)**: one or more of the three fixes worked -
the row list now renders all five default categories with their phrases,
plus a manually-added test category, confirming Add Category works
end-to-end too.

## 2026-09-30 — Forever's built-in emote registration differs from retail: EMOTE\<id\>\_CMD\<n\>, not SLASH_\<TOKEN\>\<N\>

The same retest screenshot surfaced a real functional bug: the shipped
default `/salute` phrase rendered flagged/unsendable in the options
editor. Diagnosed interactively:

- `/run print(SLASH_SALUTE1)` → `nil`. The classic retail convention
  `Send.lua`'s `FindEmoteToken` was built around doesn't exist for this
  emote on Forever, even though `/salute` itself works fine when typed.
- `/run for k,v in pairs(_G) do if type(v)=="string" and v:lower()=="/salute" then print(k.." = "..v) end end`
  → `EMOTE79_CMD1 = /salute` and `EMOTE79_CMD2 = /salute`. Forever
  registers built-in emotes under `EMOTE<id>_CMD<n>`, keyed by a numeric
  emote id (79) with no name-like token anywhere in the key.
- `/run DoEmote(79)` (the numeric id, as a guess at what changed) → no
  effect, no error. `/run DoEmote("SALUTE")` (the classic uppercase name)
  → performed the emote correctly.

**Conclusion**: `DoEmote` itself is unchanged - it still wants the classic
uppercase token string. What changed is purely how the client exposes the
command→emote mapping as globals. Since that token has always simply been
the command word itself uppercased (`/salute` → `SALUTE`), the fix doesn't
need to extract anything from the registration key (there's nothing
name-like to extract from `EMOTE79_CMD1`) - it derives the token from the
command text directly, using the global scan only to confirm the command
really is a registered emote rather than arbitrary junk.

**Design decision: fixed `CS.Send.FindEmoteToken`** to check both the
`EMOTE%d+_CMD%d+` pattern (confirmed correct for real emotes on this
build) and the classic `SLASH_%u+%d+` pattern (kept as a fallback -
`SLASH_STOPATTACK1` does exist on this build, just not for an actual
emote), deriving the returned token from `command:sub(2):upper()` in
either case rather than from the matched key.

**Also fixed the selftest check that should have caught this and
didn't**: the original "the client's emote command globals" check
re-implemented its own independent `_G` scan for the classic
`SLASH_%u+%d+` pattern, found `SLASH_STOPATTACK1` (a real global, just
not an emote's), and reported `pass` - while the actual `FindEmoteToken`
function it was supposed to be validating found nothing for `/salute`.
Checking a *different* thing than what the production code depends on is
exactly how this shipped unnoticed. The check now calls
`CS.Send.FindEmoteToken("/salute")` directly against our own shipped
default phrase, so it can't drift out of sync with the real implementation
again. `tests/launcher_spec.lua` needed a matching fix: its test harness
never loaded the real `Send.lua` module, so this check was silently
erroring (caught by the selftest's own `pcall`) in every headless test run
without anyone noticing - `loadLauncher()` now loads the genuine `Send.lua`
instead of leaving `CS.Send` unset, and two tests pin the check's verdict
to mocked `EMOTE<id>_CMD<n>` globals being present or absent.

Re-verify: `/salute` should now render normally (not flagged) in both the
options editor and the campfire panel, and actually clicking it in the
campfire panel should perform the emote.

**Resolved (2026-09-30, retest)**: confirmed - `/salute` works as expected
in the campfire panel.

## T8 status: remaining manual checks

Confirmed so far: the canvas renders and registers correctly, all five
default categories and their phrases render, Add Category works, the
unsendable-phrase flag works (correctly un-flags `/salute` now that
detection is fixed).

**Still open, not yet exercised**: drag-and-drop reordering (categories
and phrases), the 255-character rejection message on Add Phrase/Edit
Text, Reset to Defaults and Restore Missing Defaults actually applying,
and confirming a change made in the editor survives `/reload`.

**Resolved (2026-09-30, retest) — T8 fully closed.** All four confirmed
working as expected: drag-and-drop reordering for both categories and
phrases, the 255-character limit rejection and its message, Reset to
Defaults and Restore Missing Defaults, and persistence across `/reload`.
No further findings; every T8 checklist item from tasks.md is done and
verified in-client.

## 2026-09-30/10-01 — Post-T8 UX pass

Screenshots after T8 closed showed the UI was functionally complete but
not usable: an unreviewable single-line 255-character text field that
discarded typed text on validation failure, destructive Delete buttons
with no confirmation sitting flush against safe ones, category/phrase
rows visually indistinguishable from each other, an unlabeled
undraggable-looking campfire panel, an ambiguous single-label Say/Yell
toggle, and disabled phrases with no explanation. Grounded in Nielsen's
heuristics, Fitts's Law, and Gestalt grouping; fixed across several
rounds, each verified against the previous round's screenshots/reports:

- Replaced the StaticPopup text-input with a custom multi-line,
  reviewable popup (`CS.UI.PromptForText`) with a live character
  counter and an inline error that preserves typed text on failure.
- Category deletion now confirms (cascades to every phrase in it);
  phrase deletion gets a widened gap before Delete instead.
- Category rows use Blizzard's standard disclosure icons in a larger,
  gold-tinted font instead of a "+"/"-" text prefix.
- Campfire panel gained a title bar and a real two-state Say/Yell
  control instead of one button with a mutating label.
- Disabled/flagged phrases show a tooltip explaining why.
- Found and fixed two bugs during review before they ever shipped: a
  missing LEFT anchor on phrase row text (would have rendered with an
  undefined left edge), and a stale OnMouseUp handler surviving row
  pool reuse across category/phrase row types.
- **Second feedback round** caught: tooltips never fired at all
  (`:SetEnabled(false)` stops a Button from receiving OnEnter/OnLeave in
  WoW entirely - removed reliance on it, gating clickability via OnClick
  alone instead); the campfire panel's drag handle was pure decoration
  (individual rows were never actually draggable there, only the whole
  panel is - removed it); hover-reveal flickered rapidly on the buttons
  themselves (moving onto a shown button makes it the topmost frame,
  firing the row's OnLeave even though the cursor never left - fixed by
  hooking the same hover check onto the buttons' own OnEnter/OnLeave);
  tooltip anchored to the frame rather than the cursor (switched to
  ANCHOR_CURSOR_RIGHT); text too small and buttons disproportionately
  large on a high-resolution (3440x1440) display, close button
  overlapping the panel's border, and default phrases still wrapping -
  bumped font sizes a step in both windows, widened the campfire panel
  (260->460 across two passes), and inset the close button to clear the
  border.

**Resolved (2026-10-01) — confirmed clean.** All four follow-up items
(floating/tooltip alignment, panel and text proportions, hover flicker,
panel width vs. text) verified fixed with no further findings. This
closes the post-T8 UX pass.

## 2026-10-01 — Auto-open delay removed; auto-close is now a 10s grace period

Design change requested directly (not an in-client finding): the
campfire aura can drop and reapply repeatedly while the player sits at
the fire without moving. Under the original edge-triggered design, each
brief drop would immediately hide an auto-opened panel, then it would
pop back open moments later when the aura reapplied - a flickering,
unpleasant experience for a very realistic scenario, not an edge case.

**Design decision**: removed the auto-open rate limit entirely
(`CS.UI.ShouldAutoOpen`, `lastAutoOpenTime`, `CampfireStokersDB.autoOpenDelay`,
and its Options.lua field are all gone) - auto-open now mirrors aura
detection directly with no delay or cooldown, which is what "remove the
need for any behavior around auto-open other than aura detection" meant
in practice. In exchange, auto-*close* is no longer immediate: losing
the aura starts a 10-second countdown (`C_Timer.NewTimer`, cancelled via
`:Cancel()`) rather than hiding the panel outright; regaining the aura
before the countdown elapses cancels it. Only a panel this add-on
auto-opened is ever subject to this - a manually opened one still stays
up regardless, unchanged from before.

This also removes `tests/ui_spec.lua` (its only coverage was
`ShouldAutoOpen`, which no longer exists) - the new logic is a straight
line of frame/timer calls with no isolable pure decision left to test
headlessly, so this now falls under AGENTS.md's manual-only bucket like
the rest of `CreatePanel`.

`docs/definition.md` and `docs/tasks.md` updated to describe the new
behavior rather than the original rate-limited design, since this is a
deliberate specification change, not a deviation to merely document.
Also used this pass to check off every `docs/tasks.md` item from T1-T9
that's actually done and verified - none had ever been marked, despite
the whole build being complete through T9. S1-S4 (the four supporting
skills) stay unchecked: their substance was folded directly into
AGENTS.md, the test harness, and the CI/release workflows rather than
built as the standalone reusable artifacts tasks.md describes, which is
a real gap worth being honest about rather than checking off. T10
(package and release) remains the only incomplete milestone, still
blocked on pushing to a real GitHub remote.

**Resolved (2026-10-01)**: confirmed working in-client - auto-open fires
immediately with no delay, and stepping away briefly (under 10s) leaves
the panel open while stepping away longer closes it after the full
countdown. The two T7 checklist items are now checked in tasks.md.

## 2026-10-01 — Options.lua polish: collapse icon spacing, title size, Reset placement

Three rounds of follow-up feedback after the post-T8 UX pass, all
confirmed fixed with no further findings:

- Collapse icon buttons felt crowded against the row edge and label
  text once they replaced the old "+"/"-" prefix. Sized up (14->16),
  given more inset from the row edge (2->6) and more gap before the
  label (4->6); phrase indent bumped to match (14->28), since phrase
  text was actually starting less indented than its own category's
  label once the icon took up space.
- Campfire panel title bumped from GameFontNormal to GameFontNormalLarge.
- Reset to Defaults moved from the options canvas's top button row
  (competing with Add Category) to the bottom, as a low-priority,
  rarely-used destructive action. Restore Missing Defaults folded into
  the Reset confirmation dialog as its third button (Confirm / Restore
  Missing Defaults / Cancel) rather than staying a separate top-level
  button, since it's effectively a gentler subtype of the same action.

**Resolved (2026-10-01)**: all confirmed working, including the one
flagged uncertainty - the dialog's third button uses the classic
StaticPopup `button3`/`OnAlt` convention, which worked as expected
despite this build's dialog system having already deviated from the
classic one once before (the `EditBox` field capitalization). Worth
noting for future API-surface guesses in this dialog system: some parts
of the classic contract carried over unchanged, others didn't - no
blanket assumption either way holds.

## 2026-10-01 — T10: first push, first real CI run fails on luac5.1/lua5.1 naming

Pushed to a new public GitHub repo (github.com/ergh99/CampfireStokers)
for the first time this session. The first real CI run - something
local verification could never fully substitute for, since this
machine's own Lua install uses yet another naming scheme - failed
immediately at the syntax-check step: `luac5.1: command not found`
(exit 127).

**Root cause**: `leafo/gh-actions-lua@v10` builds Lua from source and
installs the result as plain `lua`/`luac`, with no version suffix at
all - not the `lua5.1`/`luac5.1` names Debian/Ubuntu's `apt install
lua5.1` uses, which `ci.yml` had assumed without ever actually running
in CI to check. (For reference, this is now the *third* different
naming convention seen across this project: apt's `lua5.1`/`luac5.1`,
Windows scoop's `lua51`/`luac51`, and gh-actions-lua's plain
`lua`/`luac` - there's no universal name to assume anywhere.)

**Design decision: fixed `ci.yml` to use `lua`/`luac`**, matching what
this specific action actually produces, confirmed locally against this
machine's own `lua`/`luac` shims before pushing again. AGENTS.md's
documented commands updated with a note explaining the naming varies by
environment entirely, rather than asserting one name as correct.

**Second failure, same push cycle**: fixing the binary name got further
but hit two more issues from the same root cause - `leafo/gh-actions-lua`
and `luarocks` both install *into the repo working copy* in CI (`.lua/`
and `.luarocks/` respectively), something no local run could surface
since neither tool is installed that way on this machine. `find . -name
'*.lua'` doesn't distinguish files from directories, so it matched the
`.lua/` directory itself ("cannot read ./.lua: Is a directory"), and
separately matched a real `.lua` file *inside* `.luarocks/` -
`luacheck/vendor/sha1/lua53_ops.lua`, part of luacheck's own vendored
dependencies, written in Lua 5.3 syntax (not ours to fix, and not
something that should ever have been scanned as our code).

**Design decision: added `-type f` plus explicit excludes for `.lua/`
and `.luarocks/`** to `ci.yml`'s find command, and added the same
exclusions (`exclude_files`) to `.luacheckrc` so `luacheck .` doesn't
hit the same problem on its own pass right after. Verified locally that
the corrected find command lists exactly the 19 real Lua files in this
repo, nothing else.

**Third failure, same cycle: the real `luacheck` tool had never actually
run before.** Local verification of `.luacheckrc` has been syntax-only
all along - `luarocks install luacheck` never completed successfully on
this machine (a Lua-version mismatch hit early on and was never
resolved; see the T1 scaffolding notes). This CI run is the first time
the actual tool evaluated this config, and it found three genuine,
previously-invisible issues, 0 errors / 7 warnings:

1. `Launcher.lua`/`Options.lua` writing new keys into `SlashCmdList` and
   `StaticPopupDialogs` (`SlashCmdList.CAMPFIRESTOKERS = handler`, two
   `StaticPopupDialogs[...] = {...}` entries) - legitimate, standard WoW
   addon patterns, but Luacheck's `read_globals` means read-only
   *fields* too, not just the global itself, by default.
2. `tests/send_spec.lua` reassigning `SendChatMessage`/`DoEmote` directly
   to mock them - exactly what a test mock needs to do, but indistinguishable
   from a real "read-only global reassigned" problem without a
   path-scoped exception.
3. Two ordinary unused-variable warnings in `tests/core_spec.lua` (an
   unused `...` in a mock function, an unused `CS` local) - unrelated to
   the WoW-API-globals pattern above, just plain cleanup.

**Design decision**: gave `SlashCmdList` and `StaticPopupDialogs` the
table form with `other_fields = true` (fields are writable, the global
itself still isn't - we never want `SlashCmdList = somethingElse`, only
new keys written into the existing table), added a `files["tests/**/*.lua"]`
override making `SendChatMessage`/`DoEmote` fully read-write *only*
under `tests/`, and fixed the two unused-variable warnings directly.
Confirms the broader lesson this whole T10 pass has been teaching: this
project's local tooling story has real gaps (no working local
`luacheck`, a Lua version mismatch that was never actually resolved,
just noted and moved past), and CI is the only place several of these
checks have ever actually run for real.
