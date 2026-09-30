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
