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

Re-run `/cfs selftest` in combat against the corrected check to confirm the
new verdict (expected: `pass`, via the `canaccessvalue` path) once you get
a chance.
