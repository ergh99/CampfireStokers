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
