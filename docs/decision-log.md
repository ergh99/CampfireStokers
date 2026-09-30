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
