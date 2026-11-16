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

**Design decision, attempt 1 (didn't work)**: gave `SlashCmdList` and
`StaticPopupDialogs` the table form with `other_fields = true` in
`read_globals`. Pushed, re-ran CI: both warnings were still there,
unchanged. The `files["tests/**/*.lua"]` override for
`SendChatMessage`/`DoEmote` *did* work on the same push, and the two
unused-variable warnings were fixed, so only this one mechanism was
wrong, not the general approach.

**Design decision, attempt 2 (confirmed working)**: switched to
dotted-path entries in the top-level `globals` list instead -
`"SlashCmdList.CAMPFIRESTOKERS"`,
`"StaticPopupDialogs.CAMPFIRESTOKERS_RESET_CONFIRM"`,
`"StaticPopupDialogs.CAMPFIRESTOKERS_DELETE_CATEGORY_CONFIRM"` -
declaring each exact field this code actually writes as writable,
rather than trying to open up every field on the table via
`other_fields`. `SlashCmdList`/`StaticPopupDialogs` themselves stay in
`read_globals` (the tables can't be reassigned, only these three
specific keys can be set). More precise than the first attempt would
have been anyway, even once working - matches AGENTS.md's "add only
what you use" principle for `read_globals` more exactly.

Confirms the broader lesson this whole T10 pass has been teaching: this
project's local tooling story has real gaps (no working local
`luacheck`, a Lua version mismatch that was never actually resolved,
just noted and moved past), and CI is the only place several of these
checks - including, now, this `.luacheckrc` syntax itself - have ever
actually run for real. Guessing at Luacheck's config format and
verifying against real CI runs turned out faster and more reliable than
trying to recall the exact documented behavior from memory.

**Resolved (2026-10-01) - first fully green CI run.** Five pushes to
get here (binary naming, tool-installed directories, two rounds of
Luacheck config), but confirmed end to end: syntax check, Luacheck, all
81 unit tests, and `wow-secret-lint` (0 errors, 0 warnings) all pass for
real. This also closes T1's last open checklist item - `wow-secret-lint`
does scan the addon for real in CI, not just locally via `npx`, since
the `path` fix from T1 is confirmed working in the actual CI
environment now, not only in local verification.

## 2026-10-01 — T10 closed: v0.1.0 tagged, packaged, and released

With CI green, tagged and pushed `v0.1.0`. The release workflow
(`BigWigsMods/packager`, also never run for real before this) succeeded
on the first attempt - no further fixes needed here, unlike `ci.yml`.
Downloaded the actual release zip and verified it directly rather than
trusting a green checkmark alone: folder name `CampfireStokers`, correct
module load order, `## Version: v0.1.0` correctly substituted for
`@project-version@` in the TOC, and none of `docs/`, `tests/`,
`.github/`, or `AGENTS.md` included - matching `.pkgmeta`'s `ignore`
list exactly. Public release live at
github.com/ergh99/CampfireStokers/releases/tag/v0.1.0.

This closes T10, and with it every milestone in `docs/tasks.md` except
S1-S4 (the four supporting skills, whose substance was folded into
AGENTS.md/the test harness/CI rather than built as the standalone
artifacts tasks.md describes - a real, acknowledged gap, not an
oversight). The build is complete, released, and publicly downloadable.

## 2026-10-02 — Future-scope research: profession campfire enhancements

Captured the profession-based campfire-enhancement feature (one
campfire feature per profession, used at a campfire to add combat buffs
to the existing hour-long sit buff) as documentation only - see
`definition.md`'s "Future Scope (v2)" section and `tasks.md`'s matching
milestone - with fully silent, one-click auto-craft as the intended
automation level. Before any implementation, ran a round-by-round
in-client research pass against a five-profession test subset (Fishing/
Fish Bowl, Alchemy/Mana Well, Herbalism/Incense Candle, Cooking/Basic
Campfire Kit, First Aid/First Aid Kit) to nail down the real API surface
rather than guessing at implementation time. The full command-by-command
log, including every wrong guess, lives in `docs/research.txt` and is
kept as a working reference, not deleted once "done."

**Tooling note**: chat `print()` output in WoW isn't copyable and long
dumps truncate, which makes it useless for pulling real data back out of
the client. Added a temporary `CampfireStokers_Debug(text)` global
(Launcher.lua, with a matching temporary `.luacheckrc` entry) that
routes arbitrary text through the already-existing `CS.UI.ShowTextPopup`
- the same scrollable, selectable popup the selftest command uses -
instead. Both are explicitly marked temporary and scoped to this
research; removing them is a follow-up once the research concludes.

**First wrong guess, corrected**: initial test commands assumed classic
bare globals (`GetSpellInfo`, `IsSpellKnown`, `GetItemCount`,
`UseItemByName`, `CastSpellByID` for crafting, `GetNumSkillLines`/
`GetSkillLineInfo`). All threw or no-opped. Confirmed instead: this
build's underlying crafting system (no stations, no stats/
specialization layer) is classic-shaped, but its **addon API surface**
is retail-shaped - the modern `C_`-namespaced functions (`C_Spell`,
`C_Item`, `C_TradeSkillUI`) are what's actually present. Lesson for any
future API exploration on this client: don't reach for classic-era
globals by default just because the underlying game system looks
classic; check the namespaced API first.

**Confirmed facts** (see `definition.md` for the consumer-facing
summary; this is the "how we know" version):

- `GetProfessions()`/`GetProfessionInfo()` (bare globals, not
  namespaced) work exactly as retail's do. First Aid isn't tracked
  through them, matching modern retail.
- `C_TradeSkillUI.GetRecipeInfo(recipeSpellID)` - the craft spell ID
  doubles as the recipe ID directly, no separate lookup needed - returns
  `craftable` (true/false: can this character craft this at all) and
  `learned` (which reads `false` even on a character with the profession
  well past skill 20; tracks something else, not used here). `craftable`
  is the correct signal for "does this button exist," confirmed by
  testing against a real `GetRecipeInfo` dump rather than assuming a
  field name.
- `C_TradeSkillUI.GetCraftableCount(recipeSpellID)` does real
  reagent-ratio math: returned 14 against a character holding 14 of one
  reagent and 17 of another (the scarcer of the two, at the recipe's 1:1
  ratio). This is the craft-vs-yell yes/no gate - no manual reagent-count
  comparison needed for that part.
- Reagent item IDs, for building the dynamic missing-materials list, are
  reachable via `GetRecipeSchematic(recipeSpellID,
  false).reagentSlotSchematics[n].reagents[1].itemID` - found by walking
  the schematic's shape one level at a time (dumping keys generically
  rather than guessing field names), since the first attempt to request
  the full schematic as a single `/run` command failed only because the
  *typed command* exceeded the chat input's character limit, not because
  of anything about the data itself.
- `C_TradeSkillUI.CraftRecipe(recipeSpellID)` (signature confirmed via
  warcraft.wiki.gg, matching the already-known
  `C_TradeSkillUI.CraftRecipe` documentation) is callable from ordinary,
  non-secure addon code - verified live, with real reagents on hand, by
  checking bag count before (0) and after (1) the call. No tradeskill UI,
  no cast-time interaction, no further click needed. **Crafting is not
  the hard part of this feature.**
- **The actual hard part, discovered by contrast**: `C_Item.UseItemByName`
  (using/placing the campfire feature) cannot be called from ordinary
  insecure Lua at all, including from inside a plain `Button`'s
  `OnClick` - confirmed live, it throws an error citing
  `SecureActionButtonTemplate` directly. This requires building that
  one button as a `SecureActionButtonTemplate` with secure attributes
  set ahead of time (`SetAttribute("type", "item")`, `SetAttribute(
  "item", <name or itemLink>)`), the same mechanism action bars use,
  with the client's own protected code performing the use when the
  button is physically clicked. Still one click from the player's
  perspective; just not implementable as a plain Button + OnClick like
  the rest of this add-on's UI. This flips `definition.md`'s original
  risk framing, which called silent crafting "the biggest open risk" -
  that part turned out to be straightforward, and using/placing the
  result is the part that actually needs a different implementation
  approach.

**Proximity, resolved as a design decision rather than an in-client
discovery**: the campfire feature enforces being at a campfire through its
own use-validation, but the panel shouldn't rely on that alone - the
profession buttons should gate on the same signal already driving the
rest of this panel, `CS.Detection`'s at-fire boolean (spell `1229739`).
That spell's real in-game name is the "Welcoming Campfire" aura -
previously only ever referred to generically as "the campfire aura"
throughout this project's docs, confirmed here for the first time. No
new aura or API needed for this; it's a reuse of existing
infrastructure.

**Tiers, corrected via the player's own domain knowledge (not an
in-client test) - the Wowhead "multi-tier" hunch from the previous entry
was right that tiers exist, but wrong about what they are.** Initial
assumption was "the same good, upgraded" (e.g. Basic/Journeyman/Expert of
one item). Actual structure, confirmed against 7 newly-looked-up Wowhead
spell/item IDs (Cookie's Feast/Cooking, Fermenter/Alchemy, Anvil/
Blacksmithing, Tanning Rack/Leatherworking, Spinning Wheel/Tailoring,
Repair Bot/Engineering, Arcane Salvager/Enchanting - all "Create Item"
spells with a 10-second cast and real reagent costs, same shape as the
tier-1 recipes already confirmed):

- Tier 1 (the five already tested) is a placeable object that augments
  the sit-at-campfire buff for *anyone* benefiting from that fire, not
  just the player who placed it - this matches `definition.md`'s
  original capture, which already said "for everyone who benefits from
  that fire"; that part was right from the start. Exception:
  Engineering's tier-1 object isn't a passive buff-augmenter - it's
  interactable and spawns a vendor.
- Tier 2 is not a buff-booster at all - it's a placeable crafting-station
  object that satisfies a proximity requirement for new Forever-specific
  crafting recipes, the same way classic recipes require a real anvil or
  forge nearby.
- Tier 3 is in scope but not yet discovered/datamined by anyone.

Design implication: the use/craft/request click flow is likely
tier-agnostic (place if owned, craft if not, yell if materials are
missing) regardless of what the placed object does afterward - that part
doesn't need per-tier branching. What does change is the framing: "one
button per profession" becomes "one button per profession-tier good the
character can plausibly use," not a strict 1:1 mapping.

**Scope narrowed back down, same day**: the player clarified two things
that simplify the above considerably. First, Engineering's tier-1
vendor-spawning exception needs no special handling at all - this
add-on's job ends at use/craft/request, and it's unconcerned with
whatever the placed object does afterward, vendor or otherwise. Second,
and more significant: tiers 2 and 3 are strictly additive over tier 1 (a
placed tier 2/3 object also counts as its tier-1 self for the shared
buff, plus niche extra effects), and cost more to craft for only that
niche benefit. Given that, the add-on will support **tier 1 only** -
tiers 2/3 are out of scope, not a future expansion to design around.
This reverts the "one button per profession-tier good" framing from
earlier in this same entry back to the original "one button per
profession" - the tier-2 spell/item IDs gathered this session stay in
`docs/research.txt` as reference, not as something to implement against.

**Yell message wording, confirmed**: "I can place a/an &lt;item link&gt;
at the campfire if someone wants to provide &lt;list of missing
materials&gt;," with the item link and the missing-materials list both
generated dynamically from the reagent/bag-count logic already resolved
above.

**Remaining tier-1 professions, mostly filled in via Wowhead** (item
attributed to profession by its crafting reagents, not guessed from the
item's name - learned to do this the hard way after the tier-2 naming
surprise earlier in this same research line): Enchanted Lute (Strange
Dust, a classic enchanting-only material) → Enchanting; Camp Tent (Light
Leather, Ruined Leather Scraps) → Leatherworking; Reagent Bot (copper
bolts/bar/ore/tube, weak flux) → Engineering - this is confirmed to be
the "spawns a vendor" exception noted earlier, and a robotic reagent
vendor fits that exactly; Sharpening Wheel (Rough Stone, Copper Bar) →
Blacksmithing; Faction Banner, two faction-specific item IDs (Linen
Cloth, Coarse Thread) → Tailoring; Lodestone (Rough Stone, Copper Bar) →
Mining, a profession not previously in this feature's scope at all. See
`docs/research.txt` for the full table.

One item resisted clean attribution: Camp Chair's reagents (Light
Leather, Ruined Leather Scraps, Simple Wood) overlap Camp Tent's leather
reagents while adding wood, so it doesn't isolate to one profession the
way every other item did. Best guess is Skinning (a secondary gathering
profession not otherwise covered, and "camp furniture from hides" fits
its flavor), but this is marked uncertain rather than asserted as fact.

**Both remaining open items closed, same day**: Camp Chair is confirmed
Skinning's tier-1 campfire feature directly (not just the reagent-based guess).
Inscription and Jewelcrafting were never actually missing data - they
don't exist in Forever at all, having been added in The Burning Crusade
and Wrath of the Lich King respectively. The 11 professions with
confirmed tier-1 data are the complete set.

**This closes the research line.** Every open question raised across
this whole pass - the API surface, the craftable/craftable-count/
schematic calls, the secure-button requirement for item use, the
proximity design, the yell message wording, and full profession coverage
- is now resolved. `definition.md`'s Future Scope section and
`docs/tasks.md`'s matching milestone are both fully specified; what
remains is implementation, not further discovery. Removed the temporary
debug hook (`CampfireStokers_Debug` in Launcher.lua, plus its
`.luacheckrc` entry) the same day, per its own code comment - nothing
left in this research line needs it. Verified clean afterward: syntax
check, all 81 tests, and (newly) a real local `luacheck .` run, 0
warnings/errors - this closes the "no working local luacheck" gap T10's
entries noted earlier; CI is no longer the only place this check runs
for real.

## 2026-10-04 — wow-secret-lint's TOC-discovery bug fixed upstream

T1's workaround (pointing `ci.yml`'s `path` at the module files
directly, since TOC-based discovery misread this addon's 16001
Interface line as Classic and skipped it entirely) is no longer needed.
Fixed upstream in v1.8.1
([Booyaka101/wow-secret-lint#14](https://github.com/Booyaka101/wow-secret-lint/issues/14),
filed off this project's own finding) - 16001 is now correctly
recognized as Forever/retail. v1.9.0 additionally narrows the
removed-symbol list for Forever-only targets based on a real scan of
the client, cutting false positives (`GetWeaponEnchantInfo`,
`getglobal`, `setglobal`, and others) - doesn't change anything for us
directly (this addon never called those), but the discovery fix does.

Confirmed locally: `npx wow-secret-lint@1.9.0 . --strict --format json`
reports `flavour: "forever"`, `filesScanned: 8` (the real module count),
0 findings - using plain `path: .`, no explicit file list.
`.github/workflows/ci.yml` updated to pin v1.9.0 by commit SHA and use
`path: "."` instead of the old explicit module list - an improvement,
not just a simplification, since `.` now tracks the TOC's file list
automatically (a new module no longer needs a separate manual `path`
update, closing that sharp edge from T1).

## 2026-10-04 — Campfire features implemented

Built the feature against the fully-resolved plan (see the research
entries above). New `Professions.lua`, loaded between `Detection.lua`
and `UI.lua`: `FEATURES` (11 entries, Tailoring's Faction Banner carrying
faction-variant ids), `ResolveEntry`, `EvaluateFeature` (pure, DI-based,
mirroring `Detection.EvaluateState`/`Send.Classify`), `BuildRequestMessage`,
`Craft`, and `CreateEventFrame`. `UI.lua` gained 11 fixed
`SecureActionButtonTemplate` buttons (not pooled, unlike phrase rows -
each permanently bound to one profession's item), laid out as a
label-less icon grid (`layoutProfessionBlock`) with a colored border per
state (use/craft/request) and a tooltip carrying the item name and
reason, combat-lockdown-deferred the same way real action-bar addons
handle it. `Core.lua` gained one line wiring `CS.Professions.CreateEventFrame()`.
`Data.lua` gained the 11 item-name strings plus two tooltip-suffix
strings. `docs/definition.md`'s stale "Profession coverage" paragraph
(which still named Cooking among the 11, the exact inconsistency flagged
during planning) is fixed, with the Cooking-exclusion rationale and the
future-scope note (a separate standalone UI/keybind for placing the
*initial* campfire) written down. `docs/tasks.md`'s remaining unchecked
implementation items in this milestone are now checked off, including
retiring the never-built "profession detection via GetProfessions"
item in favor of the simpler, already-confirmed `IsRecipeProfessionLearned`
per-recipe gate.

New `tests/professions_spec.lua` (15 tests) follows the project's
established DI-fake pattern for the pure functions and the
monkey-patch/fake-frame pattern for the two impure ones; `core_spec.lua`
gained a `CS.Professions.CreateEventFrame` call-count assertion, same
shape as the existing UI/Options stubs. Verified clean: syntax, `luacheck .`
(0 warnings across 21 files), all 96 tests (81 existing + 15 new), and
`wow-secret-lint@1.9.0 . --strict` (`filesScanned: 9`, 0 findings - the
new module was picked up automatically, confirming the CI fix from
earlier today works end to end for a real new file, not just
retroactively).

**Still manual-only, not yet done**: the actual in-client pass this
project's testing philosophy always reserves for real frame-tree code -
does the panel actually show the right buttons for a real character's
real professions, do the icons/borders/tooltips look right, does
clicking really use/craft/yell correctly end to end. The secure-button
*mechanic* itself was already smoke-tested in isolation during planning
(see the 2026-10-04 entries above); what's unverified now is the real
feature built on top of it, not the mechanism.

## 2026-10-05 — First real in-client pass surfaces four bugs, three fixed

The manual pass flagged above happened, and found real problems - worth
recording in detail since one of them (`GetCraftableCount`) reverses a
signal this feature's design had relied on since the original research
pass.

1. **Sizing/padding.** Icons were too small and the block had no real
   margin (padding literally hardcoded to `4` on one side only).
   `PROFESSION_ICON_SIZE` doubled 32 -> 64, and three new constants
   (`PROFESSION_BLOCK_SIDE_PADDING`/`TOP_GAP`/`BOTTOM_GAP`, all 8px) give
   the block proper breathing room on every side.
2. **Profession buttons could vanish permanently.** `layoutProfessionBlock`
   had no error handling around each entry's `EvaluateFeature` call. Under
   rapid aura drop/reapply (the campfire aura is known to flap while the
   player sits still, see the auto-close grace-period work earlier in
   this log), a single entry throwing would abort the whole loop
   mid-iteration, leaving every button after the failure point stuck in
   whatever Show/Hide state it had - and since nothing retried, they
   stayed hidden indefinitely. Fixed: each entry's evaluation is now
   `pcall`-wrapped (`evaluateFeatureSafely`); a thrown error is reported to
   chat (not silently swallowed) and treated as "not visible" for just
   that one entry, not the whole block.
3. **Request message showed plain text, not a link, for the main
   item - and missing reagents showed as a raw `"item <id>"` fallback.**
   Both trace to the same root cause: `C_Item.GetItemInfo` and
   `C_Item.GetItemNameByID` both depend on the client's async item-data
   cache and return nil/incomplete data until an item has been "seen."
   `GetItemNameByID` was wrongly assumed to be a lighter, always-synchronous
   lookup - it isn't, confirmed live (an uncached reagent produced
   exactly the `"item <id>"` fallback). Fixed by consolidating onto one
   API: `BuildRequestMessage` now uses `C_Item.GetItemInfo` for both the
   main item (its 2nd return, the link) and every missing reagent's name
   (1st return), so there's one cache behavior to account for, not two.
   Added `CS.Professions.WarmItemCache()`, called once at `ADDON_LOADED`,
   that proactively touches every campfire feature's item id *and* every learned
   campfire recipe's reagent item ids, to start that fetch early instead of at
   first use. This narrows the race substantially but can't fully close
   it for an item referenced in the first moments after login.
4. **`GetCraftableCount` returned `0` while materials were abundant -
   and `missing` correctly came back empty, which is what actually
   exposed the bug.** Diagnostic: `GetRecipeSchematic` confirmed both
   Blacksmithing's and Mining's recipes need exactly 1 of two reagents
   (Rough Stone, Copper Bar); the character held 46 and 62 respectively.
   `GetCraftableCount` nonetheless returned `0` for both - it can be
   zero for reasons that have nothing to do with missing materials (a
   cooldown or similar, not yet identified). **This retracts
   `GetCraftableCount` as a signal entirely** - the original research
   pass treated it as confirmed reliable (real reagent-ratio math, 14
   against 14/17 reagents), which was true for that one test case but
   didn't generalize. `EvaluateFeature` no longer calls it at all: the
   schematic-vs-bag-count walk (already needed to build the
   missing-materials list) is now the *only* signal for craft-vs-request
   - if that walk finds nothing missing, the action is "craft," full
   stop, regardless of what `GetCraftableCount` would have said.
   `definition.md` and `tasks.md` corrected to match; `docs/research.txt`
   is left as-is (a historical log of what was tested, not a live spec).

## 2026-10-05 — Second in-client pass: two more fixes

5. **Location was wrong in a different way than the sizing fix
   addressed.** The profession block sat between the Say/Yell toggle
   and the phrase tree it actually controls - confusing, since
   campfire feature requests always yell regardless of that toggle, so having
   them visually sandwiched inside the Say/Yell-to-phrases relationship
   implied a connection that doesn't exist. Fixed by moving the block
   above Say/Yell instead: Title -> profession block (if any) -> Say/Yell
   -> phrase tree. This required making Say/Yell's position dynamic
   (previously fixed via a static `SetPoint` in `CreatePanel`, now
   repositioned every `Refresh()` based on the profession block's
   current height, same pattern the phrase tree already used). New
   constants `TITLE_AREA_HEIGHT`/`SAY_YELL_HEIGHT`/`SAY_YELL_BOTTOM_GAP`
   replace the old fixed `TOP_CONTROLS_HEIGHT`.
6. **Broadcasting a raw item id in a public yell is not acceptable**,
   confirmed as a real production concern, not a cosmetic one - unlike
   the main item (whose `entry.itemName` is a string this add-on
   already controls and trusts as a fallback), a missing reagent's name
   comes only from the API, with no safe fallback string of our own.
   `BuildRequestMessage` now returns `nil` - not a message containing
   `"item <id>"` - if any missing reagent's name can't be resolved;
   the `PreClick` handler checks for `nil` and reports locally
   (`CS.Data.L.feature_request_not_ready`) instead of ever sending.

Verified clean after all six fixes: syntax, `luacheck .` (0 warnings),
all 102 tests, and `wow-secret-lint@1.9.0` (`filesScanned: 9`,
0 findings).

**Resolved, same day**: `GetCraftableCount` returns `0` unless the
TradeSkillUI panel is actually open to the corresponding profession -
it's UI-state-dependent, not a pure data query. This retroactively
confirms dropping it was correct, not just a workaround: this add-on
never opens the tradeskill panel at all (the entire point of "fully
silent" crafting), so `GetCraftableCount` could never have returned a
meaningful value here regardless of materials. Worth remembering if a
future feature ever wants a direct "will this craft succeed" check -
it would need the panel open first, which defeats the silent-crafting
premise this feature depends on.

The in-client pass otherwise continues - item-link/tooltip/sizing fixes
above are unverified live until re-tested.

## 2026-10-05 — Second campfire aura: permanent tutorial campfires

A real gap in the base detection logic, not specific to the profession
feature: the permanent, non-despawning campfires that are part of the
starting-zone campfire tutorials apply a different aura
(`1289723`) than the regular "Welcoming Campfire" aura (`1229739`)
`Detection.lua` has always checked. Since `EvaluateState` only ever
checked one spell ID, sitting at one of these tutorial campfires would
never have registered as "at a campfire" at all - this add-on's entire
premise (the panel opens because you're at a fire) would have silently
failed for every player at one of these specific campfires.

Fixed: `CS.Detection.CAMPFIRE_SPELL_IDS` is now a list (both ids), and
`EvaluateState` loops over it - the player counts as at-fire if *either*
aura is present. The existing secret-value discipline is preserved
exactly: `ShouldAurasBeSecret` is still asked once, up front, covering
both reads (it's a blanket restriction on reading auras at all this
frame, not a per-aura one); each id is still read one at a time, by
spell ID only, never by index/slot/instance id; `canAccessValue` still
gates every read before anything touches the result. The one behavioral
change: an unreadable or nil result for one id no longer short-circuits
the whole evaluation to `false` - it just means "try the next id," since
an unreadable result for the *first* aura says nothing about whether
the *second* one is present. Only after every id comes back
absent/unreadable does the player count as not at a campfire.

`Launcher.lua`'s "campfire aura spell IDs" self-test now reports both
constants. `docs/definition.md`'s Campfire Detection section and the
profession feature's proximity note are updated to describe checking
two auras, not one. `tests/detection_spec.lua` gained three new tests
(the real default list order, the tutorial aura alone being sufficient,
and an unreadable first id not blocking a readable second one);
`tests/launcher_spec.lua`'s `Detection` stub gained the second constant
so the renamed self-test's `string.format` call doesn't error on a
missing field. Verified clean: syntax, `luacheck .` (0 warnings), all
105 tests (up from 102), and `wow-secret-lint@1.9.0` (0 errors/0
warnings).

## 2026-10-05 — CraftRecipe actually requires the real crafting frame

**Partly superseded** by "Crafting is two clicks" below: the
single-click `OpenRecipe` -> `CraftRecipe` -> hide sequence this entry
calls fully confirmed did nothing once a different profession had been
opened by hand.

Third in-client pass surfaced a reagent-link gap and a genuinely
significant correction to how crafting works.

**Reagent links.** The missing-materials list was built from
`C_Item.GetItemInfo`'s name-only return, never its link - an earlier
design choice, not a caching bug (an earlier round had misdiagnosed
this exact report as the *main* item's link being broken; it wasn't -
the main item's link worked the whole time, confirmed by testing the
wrong item ids). Fixed: each missing reagent now prefers its link over
its plain name too, falling back to name only if no link is available,
still refusing to send anything (`nil`) if neither resolves - the
"never leak a raw item id" rule from the previous round still holds.

**`CraftRecipe` requires the real crafting frame to be open -
confirmed definitively, not inferred.** The investigation, in order:

1. Replaying the exact call sequence from the original successful
   research pass (`GetRecipeInfo` -> `GetCraftableCount` ->
   `GetRecipeSchematic` -> `CraftRecipe`) against Mining, panel closed,
   produced `ok=true, err=nil` but zero actual effect - confirmed by
   direct visual observation (no cast bar, no animation), the
   sufficient signal per this pass's own methodology correction: either
   a cast visibly begins or it doesn't, and checking bag counts
   afterward adds nothing a null visual result hasn't already told you
   (an unnecessary verification step this pass specifically called out
   and that's now the standing approach for this kind of check).
2. `C_TradeSkillUI.OpenTradeSkill(recipeSpellId)` produces no visible
   effect of its own - ruled out as an invisible "prime the state"
   shortcut, since calling it before `CraftRecipe` still produced
   nothing.
3. `C_TradeSkillUI.OpenRecipe(recipeSpellId)` **does** visibly open the
   real crafting frame (`ProfessionsFrame`, confirmed via
   `:IsShown()`), with the recipe pre-selected. With the frame open
   this way, `CraftRecipe` then produces a real cast bar and animation.
4. Hiding `ProfessionsFrame` immediately after calling `CraftRecipe` -
   same synchronous sequence, no delay - does **not** interrupt the
   cast; the bar and animation still play through to completion. This
   matches ordinary WoW spell-cast behavior (a cast is tied to the
   player's casting state, not any UI frame's visibility), not a
   Forever-specific quirk.

**Conclusion**: `C_TradeSkillUI.CraftRecipe` alone was never sufficient
- the original research pass's "bag count 0 -> 1" success almost
certainly happened with the frame already open from earlier manual
testing in that same session, without that being noted at the time.
The real, now-fully-confirmed mechanism is `OpenRecipe` ->
`CraftRecipe` -> hide the frame, all synchronous, in `Professions.lua`'s
`Craft` function. This isn't truly silent (the frame technically opens
and closes, even if imperceptibly fast), but it is still fully
automatic and one-click from the player's perspective, which is what
the plan's scope decision called for. `definition.md` and `tasks.md`
corrected to retract "crafting is not the hard part" / "fully silently,
with no crafting-UI interaction," which were both accurate to what the
original research found but didn't hold up under real testing.

`Craft` gained DI parameters (`openRecipe`/`craftRecipe`/`hideFrame`)
matching this codebase's existing pattern, rather than a bare global
call, so the sequence is directly unit-testable. `ProfessionsFrame`
added to `.luacheckrc`'s `read_globals`. Verified clean: syntax,
`luacheck .` (0 warnings), all 107 tests (up from 105), and
`wow-secret-lint@1.9.0` (0 errors/0 warnings).

## 2026-10-05 — Crafting is two clicks

A 17-round in-client investigation, recorded verbatim as each result
came in, in `docs/craft-profession-switch-findings.md` (round numbers
below refer to that ledger). It started from zero: the earlier
`docs/craft-profession-switch-investigation.md` write-up was rebuilt
from memory, contained claims that turned out wrong, and was used only
as a list of API names to probe.

What the ledger shows:

- `CraftRecipe` alone, with no crafting frame open, does nothing
  (Round 2). From a keypress with `ProfessionsFrame` shown on the recipe,
  it crafts (Round 3).
- Deferred with `C_Timer.After(0, ...)`, it does nothing, even with the
  frame opened by hand on the recipe (Rounds 11, 12). It has to run
  inside the click or keypress itself.
- `OpenRecipe` -> `CraftRecipe` -> hide in one input crafted when Mining
  (the recipe's own profession) was the last panel opened by hand
  (Round 6), and did nothing after Blacksmithing had been opened by hand
  (Rounds 7, 9), even though `OpenRecipe` alone still opened Mining on
  the right recipe in that state (Round 8).
- `OpenRecipe` on one input, then `CraftRecipe` -> hide on a later input,
  with the frame left shown in between, crafted in that Blacksmithing
  state (Rounds 10, 14), from the real secure test button (Round 15),
  at the campfire with the add-on's panel open (Round 16), and from the
  add-on's own campfire feature button (Round 17). Hiding the frame
  between the two inputs broke it (Round 13).

**Decision** (player's choice, with the frame visible between clicks as
the known trade-off): `CS.Professions.Craft` is now two clicks. The first
calls `OpenRecipe` and returns `"opened"`. The second crafts, hides the
frame and returns `"crafted"`, but only if `Craft` itself opened that
same recipe on the previous click and `ProfessionsFrame` is still shown;
otherwise the click opens the recipe again. That last guard covers a
frame the player opened on another profession, a case the ledger never
tested crafting into. `UI.lua`'s `PreClick` needed no change.
`tests/professions_spec.lua`'s two old `Craft` tests were replaced by six
covering open, craft, reopen-after-close, other-recipe and start-over.

Removed: the temporary `CraftSwitchTest.lua`, its TOC entry and its two
temporary `.luacheckrc` globals.

**Found during Round 17, not fixed**: moving to interrupt a craft cast
removed the campfire aura, and the panel hid the profession buttons right
away while the rest of the panel stayed up until the auto-close timer
finished. The player wants the profession buttons to stay visible until
the panel closes; logged as an open item in `docs/tasks.md`.

Verified clean: syntax, `luacheck .` (0 warnings), all 110 tests, and
`wow-secret-lint@1.9.0 --strict` (0 errors/0 warnings).

## 2026-10-05 — Profession buttons: state glow, and shown whenever the panel is

Two in-client reports, worked through round by round in
`docs/profession-button-appearance-findings.md`.

**Appearance.** The per-state border colors were being applied (Round 1
printed the craft color `0.4, 0.6, 1` from the button), but the 10px
tooltip border was almost entirely covered by the icon. A solid border
read clearly but looked plain (Round 3); Blizzard's tinted item-quality
frame looked better but too thin (Round 4), and stacking two copies left
a visible seam (Round 5); a 16px tooltip border was less clear (Round 6).
The classic action-button glow (`Interface/Buttons/UI-ActionButton-Border`,
ADD blend, 110x110 on the 64px button) was "a definite improvement"
(Round 7); BLEND mode covered the icon (Round 8). Colors chosen by the
player: craft `0.1, 0.3, 1`, use `0.1, 0.9, 0.1`, request `1, 0.2, 0`
(red-orange, to tie it to the red of yell messages) (Rounds 8-10).
`UI.lua`'s profession buttons dropped `BackdropTemplate`; the icon fills
the button and a `glow` texture is tinted per state.

**Visibility.** The buttons were hidden whenever `CS.Detection.atFire`
was false, so they vanished during the auto-close grace period after the
aura dropped (Round 17 of the crafting ledger) and never showed on a
manual open away from a fire; and a manual open never refreshed, showing
whatever the last refresh laid out. The player's decision: the buttons
show whenever the panel is visible, and are evaluated before it is
shown. `evaluateFeatureSafely` no longer checks `atFire`, and `CS.UI.Show`
refreshes before showing. Verified in-client across auto-open, aura drop
and manual open (Round 11). `docs/definition.md`'s proximity note
records the change.

Verified clean: syntax, `luacheck .` (0 warnings), all 110 tests, and
`wow-secret-lint@1.9.0 --strict` (0 errors/0 warnings).

## 2026-10-05 — Yell request message picks "a" or "an"

Reported in-client: the request yell read "I can place a/an <item>"
literally. New pure `CS.Professions.IndefiniteArticle(name)` returns
"an" before a vowel letter and "a" otherwise, and `BuildRequestMessage`
uses it with the item's plain name. Letter-based rather than
sound-based, which is right for all 11 campfire features (only Incense Candle and
Enchanted Lute take "an"). Three new unit tests; the three existing
message tests now expect "a" for Fish Bowl. Confirmed in-client by the
player: "confirmed working". Verified clean: syntax, `luacheck .`
(0 warnings), all 113 tests, and `wow-secret-lint@1.9.0 --strict`
(0 errors/0 warnings).

## 2026-10-05 — Use-state click needed the press registered too

Reported in-client: clicking a profession button in the use state did
nothing and showed no error. Worked through in
`docs/profession-use-findings.md`. The secure attributes were correct
(`type` = `item`, `item` = `Sharpening Wheel`, matching the client's own
item name), but `ActionButtonUseKeyDown` was `1` and the button only
registered `"AnyUp"` (Round 1). Also registering `"AnyDown"` on that one
button made the click start the placement cast (Round 2). This reverses
the 2026-10-04 change to `"AnyUp"` only, which had been made because
registering both fired `PreClick` twice per click.

`UI.lua` now registers both, and `PreClick` returns early on the press,
so craft and request still run once per click on the release (where
craft was verified in the crafting ledger's Rounds 15-17). Verified
in-client: use, craft (two clicks) and request each worked once per
click (Round 3). The player noted that placing a campfire feature starts a
one-hour cooldown, and that only the Basic Campfire Kit uses a ground
target; the other campfire features cast and appear at the character's feet.

Found during Round 3, not fixed here: the Fishing and First Aid request
yells were refused by the 255-character check, apparently because item
links are counted at their full raw length - investigated in
`docs/yell-length-findings.md`.

## 2026-10-05 — 255 limit counts links by visible text

Found during the use-click verification: the Fishing and First Aid
request yells were refused by `Send.Classify`'s 255 check for a
character with none of the materials. Investigated in
`docs/yell-length-findings.md`: the client's limit is 255 visible
characters with an item link counting as its bracketed name (244 plain
+ `[Fish Bowl]` sent, 245 + the link raised "Chat message limits
exceeded", Round 5), while 317 and 619 raw bytes of links sent intact
(Rounds 1-2). Plain text over 255 raises that error from
`SendChatMessage` (Round 3).

New pure `CS.Send.VisibleLength(text)` strips link wrappers, color
starts and resets before counting, and `Classify` checks it instead of
`#text`. Four new unit tests cover the boundary and a long all-link
message. Confirmed in-client with a real request yell (Round 6).
`Tree.lua`'s phrase-editor check still uses raw `#text`, unchanged.
Verified clean: syntax, `luacheck .` (0 warnings), all 117 tests, and
`wow-secret-lint@1.9.0 --strict` (0 errors/0 warnings).

## 2026-10-09 — Text popups made fully opaque

Reported in-client: the options rows showed through the phrase prompt.
Both text popups used only the `UI-DialogBox-Background` backdrop, which
is partly transparent, and a backdrop tint can't raise its alpha. A
solid black layer inside the border (`addOpaqueUnderlay` in `UI.lua`)
now sits under the backdrop of the phrase prompt and the selftest/export
popup. Tried in-client first: the black layer made the prompt fully
opaque, and redrawing the dialog texture on top of it changed nothing
visible, so the result is effectively flat black. Confirmed after a
reload; the player called it fine for now.

## 2026-10-09 — Campfire panel look and feel

Requested directly: an improved look for the campfire panel, starting
from a palette sketch (`docs/CAMPFIRE_ADDON_CONTEXT.md`, untracked, whose
member-list/chat assumptions were ignored). Worked through in-client
round by round from screenshots:

- Warm palette: ember-orange title and category headers, parchment
  phrase text, leather dividers below the title and the profession
  block. Title icon and text centered as one unit; profession icons
  centered per row; close button centered in the title row.
- Background: a backdrop's background color multiplies its texture, so
  it can lower opacity but never raise it - the cause of the see-through
  panel. Now an opaque solid layer plus
  `UI-Achievement-Parchment-Horizontal` darkened by vertex color. Every
  earlier textured background used a retail path assumed to exist and
  never visibly rendered; a temporary in-client preview grid
  (`/campfire textures`, since removed) confirmed which files actually
  render before one was chosen.
- Border: the achievement frame's wood (`UI-Achievement-WoodBorder`, a
  standard backdrop edge file per Blizzard's own
  `BACKDROP_ACHIEVEMENTS_0_64`), on its own frame 22 units outside the
  panel so it surrounds rather than covers the content. Its built-in
  gray metal rim is trimmed by a clipping frame (feature-tested
  `SetClipsChildren`); the rim's leftover diagonal at each corner is
  covered by a small dark cap (corner caps not yet confirmed in-client).
- Rows: the old click feedback called `LockHighlight()` on rows with no
  highlight texture, so it never showed. Rows now get an ember hover
  wash and click flash using the quest-title highlight split into two
  halves with `SetGradient` fades, soft on all four sides. Fire/glow
  textures were trialed live on real rows and rejected: none fit the
  row shape.
- Title icon glow flickers (random alpha steps via a re-armed
  AnimationGroup, running only while shown) instead of pulsing.

## 2026-10-14 — Campfire feature cooldown and canonical names

Placing any campfire feature puts every campfire feature's Use on one
shared cooldown. Each profession button now carries a
`CooldownFrameTemplate` sweep with countdown numbers forced on.
`CS.Professions.GetItemCooldown` reads the item's own cooldown (the
shared cooldown means no grouping is needed), trying
`C_Item.GetItemCooldown` and falling back to
`C_Container.GetItemCooldown`, and treats a value `canaccessvalue`
rejects as no cooldown. Only "use" buttons show it: crafting and
requesting still work during the cooldown. `BAG_UPDATE_COOLDOWN`
registration is pcall-guarded since registering an unknown event throws
on this build. Confirmed in-client by the player: "confirmed working as
expected."

Naming: the game calls the placeable items **campfire features** and
the profession recipes that make them **campfire recipes**. Code and
living docs now use those names instead of the earlier "campfire
goods"/"profession goods": `CS.Professions.GOODS` became `FEATURES`,
`EvaluateGood` became `EvaluateFeature`, and the `pg_` locale keys
became `feature_`. Verbatim findings ledgers and quotes of earlier
wording in this log are left as recorded.

## 2026-10-14 — Panel style option and default position

The options panel gains a panel style dropdown (Blizzard_Menu's
`WowStyle1DropdownTemplate`, pcall-wrapped since it isn't confirmed on
Forever). Two styles:

- **Campfire**: the warm look from the entry above.
- **Forever** (the default): built on Blizzard's `PortraitFrameTemplate`,
  the template behind the Auction House and profession windows, for its
  border, title bar, rock background, round portrait and close button,
  with gold category headers on a dark bar and white phrase text. The
  template is built under `pcall`; if it fails, the panel falls back to
  the Campfire look.

Switching applies immediately. Colors moved from one fixed palette to a
per-style table (`LOOKS` in UI.lua). A saved `panelStyle` of `"default"`,
this style's id before it was renamed Forever, is converted to
`"forever"`.

The panel's default position moved from above the chat window to the
right half of the screen: crafting a campfire recipe from the panel
opens the profession window anchored to the left, which covered the
panel at its old spot. `DEFAULT_CHAT_FRAME` is no longer read.

In-client confirmation of the dropdown and portrait template on Forever
wasn't recorded at the time.

## 2026-11-14 — First-run tutorial: opening the editor, and the welcome card

**Finding (in-client, first look at T11).** Clicking the welcome
card's "Make it yours" didn't open the editor; the fallback chat line
printed instead. Cause, confirmed from Forever's UI source (Gethe/wow-ui-source,
`forever` branch): `Settings.OpenToCategory` calls
`C_SettingsUtil.OpenSettingsPanel`, whose documented argument is a
**number** category ID (`SettingsUtilDocumentation.lua`), and each
category's ID is a counter assigned at creation (`Blizzard_Category.lua`).
Options.lua had overwritten our category's `ID` with the string
`"CampfireStokers"` back in T8, so the call threw. Fix: the override is
gone and `CS.Options.Open` passes `category:GetID()`. Re-confirming the
editor now opens is V1.

**Decision (project owner).** The welcome card described things the
player hadn't seen yet ("the panel", "campfire features") with no
visuals, and on failure sent the player off to find the editor
themselves. Replaced with "show, don't tell":

- The card is a short greeting with **Show me** and **Later**.
- **Show me** opens the real panel right away, at a fire or not, and
  runs the panel tour on it. That tour always ends by offering the
  editor, and **Open Editor** goes straight into the editor tour in
  Settings. This reverses the plan's "opening the panel manually isn't
  a step" decision.
- **Later** keeps the original behavior: the panel tour runs at the
  first campfire auto-open.
- No step sends the player to chat. Clicked mid-fight, Show me and Open
  Editor say so in place and run when combat ends. If Settings still
  can't open, the callout itself says where the editor is.

## 2026-11-15 — First-run tutorial verified in-client

The project owner tested the tutorial in-game before releasing v1.1.0
and confirmed every T11 item and all five checks from
[tutorial-plan.md](tutorial-plan.md)'s "In-client verification":

| # | Question | Result |
| --- | --- | --- |
| V1 | Does `Settings.OpenToCategory` open our editor? | Confirmed, with the numeric-ID fix from the entry above. |
| V2 | Does the callout draw above `SettingsPanel` and stay on screen? | Confirmed (`FULLSCREEN_DIALOG` strata, clamped). |
| V3 | Callout look | Accepted as shipped: tooltip backdrop with a gold border and the default UI's yellow tutorial arrow (`UI-MicroStream-Yellow`). |
| V4 | Do pinned hover widgets stay visible through the editor tour and hide afterwards? | Confirmed. |
| V5 | Do the card and tours still appear with `hideHelptips` set? | Confirmed. |

Also changed after the first in-client look, before release: the card's
text was rewritten in a guide's voice ("Show me around" / "Maybe
later"), the panel tour's Say/Yell step was removed, and the editor
offer now stresses full control over every phrase and category.
