# First-Run Tutorial: Best Practices

Internal reference, 2026-11-12. Distilled from how current WoW add-ons
handle first-run onboarding, read at the source level, plus Blizzard's
own UI code on the `forever` branch of the client UI mirror. Written for
whoever implements Campfire Stokers' first-run tutorial; the plan that
applies it is [tutorial-plan.md](tutorial-plan.md).

## Sources and the reference gate

Every add-on below was put through AGENTS.md's TOC gate and two-month
recency check (cutoff 2026-09-12) before its code was read as a
reference. Rejected repos are listed so nobody re-checks them.

| Add-on | Interface | Last push | Gate | Onboarding style |
| --- | --- | --- | --- | --- |
| [ClassicUI Forever](https://github.com/fallenguards/classicuiforever) (`Options/Welcome.lua`) | 16001, 1201xx | 2026-11-12 | Pass | One-page welcome note, then a chained follow-up question |
| [OneForAll](https://github.com/smoergi/OneForAll_Forever) (`OneForAll/UI/Welcome.lua`) | 16001 | 2026-11-11 | Pass | Multi-page setup wizard with Skip and "Recommended settings" |
| [CraftBoard](https://github.com/MartinPTielemans/craftboard) (`CraftBoard/Welcome.lua`) | 16001 | 2026-10-27 | Pass | One-page splash: four illustrated steps, one call-to-action |
| [ElvUI](https://github.com/tukui-org/ElvUI) (`General/Install.lua`, `General/Tutorials.lua`) | 16001 and others | 2026-11-12 | Pass | Multi-page installer; separate rotating tips window afterwards |
| [Details!](https://github.com/Tercioo/Details-Damage-Meter) (`frames/window_welcome.lua`) | 16001 (`Details_Camelot.toc`), 120105 | 2026-11-09 | Pass | Multi-page configuration wizard |
| [NDui](https://github.com/siweia/NDui) (`Modules/Chat/Chatbar.lua` and others) | 120105 | 2026-11-12 | Pass | Blizzard `HelpTip` callouts on its own frames |
| [LFGSpamFilter](https://github.com/romdeau23/wow-lfgspamfilter) (`modules/ui/statusButton.lua`) | 120100 | 2026-09-19 | Pass | One Blizzard `HelpTip` on its button, the first time it's visible |
| Blizzard UI, `forever` branch, 1.60.1 (70888), via [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever) | n/a | 2026-11-10 | n/a | `HelpTip`, `HelpPlate` |
| AbstractFramework (enderneko) | 120001 | 2026-03-29 | **Fail: recency** | Custom HelpTip clone. Not used. |
| BetterGearCompare | 1200xx | 2026-09-05 | **Fail: recency** | Not used. |
| AllGasNoBrakes | 20505 | 2026-06-21 | **Fail: TOC** | Not used. |

Web search turned up nothing useful on this topic; the GitHub source above is the evidence.

## The patterns

### 1. Trigger after login, not in `ADDON_LOADED`, and wait a few seconds

All three Forever-native references show their welcome from
`PLAYER_LOGIN`, then defer with `C_Timer.After`: CraftBoard 3 s,
OneForAll 4 s, Details! 1 s. `ADDON_LOADED` fires during the loading
screen, before the rest of the UI (and other add-ons' popups) has
settled, so a window shown there competes with everything else for the
player's attention.

- **Do:** decide "is it due?" at `ADDON_LOADED` (that's when
  SavedVariables are readable), but *show* it from `PLAYER_LOGIN` plus a
  short `C_Timer.After`.
- **Don't:** show anything from `ADDON_LOADED` directly.

### 2. Never pop up in combat

CraftBoard checks `InCombatLockdown()` and, if true, sets a pending flag
and shows the window on `PLAYER_REGEN_ENABLED` instead. A login inside
combat is rare but real (logging back in mid-fight, a reload in a
dungeon). Campfire Stokers' UI.lua already uses this pending-flush
pattern for profession-button updates (`queueCombatFlush` and
`combatFlushFrame`). That helper is local to UI.lua and specific to the
profession block, so follow the same pattern instead of trying to call
it.

### 3. Mark it seen on *show*, not on close

| Add-on | When "seen" is written |
| --- | --- |
| OneForAll | on show |
| CraftBoard | on show, and also when the window fails to build |
| LFGSpamFilter | on show |
| ClassicUI | on hide |
| NDui | on "Got it" acknowledge only |

Writing on show is the majority choice for a full welcome window and the
safer one: if the client crashes, the player `/reload`s, or they log
out with it open, they aren't nagged with the same popup forever.
On-acknowledge (NDui) suits single coach marks, where the player hasn't
really seen it until they click "Got it."

CraftBoard's extra rule is worth copying: if building the window throws,
mark it seen anyway and print one chat line instead. A broken tutorial
must never re-error on every login.

### 4. Version the flag, don't make it a boolean

CraftBoard stores `welcomeVersion` against a constant `VERSION = 2`,
and OneForAll stores `welcomeSeen = "6.0.0"` against a `WELCOME_ID`.
Raising the constant re-shows the tutorial once after an update that
materially changes it, without a migration. A plain `seen = true`
can't do that.

- **Do:** store an integer `tutorialVersion` (plain value, so it
  satisfies AGENTS.md secret-value rule 5) and compare it to a constant.

### 5. Separate fresh installs from upgrades

ClassicUI's `Returning()` check silently marks existing players as
welcomed: anyone who already has saved data when the welcome feature
ships never sees the first-run popup. Showing a "Welcome to X!" window
to someone who has used X for months is the most commonly cited
onboarding annoyance. CraftBoard takes the opposite approach and shows
it once to everyone.

For Campfire Stokers, the fresh-install signal already exists:
`CS.Tree.Bootstrap` takes its `db.tree == nil` branch only on a true
first load. Whether existing players see it is a product decision; see
the plan.

### 6. One popup at a time

- ClassicUI's welcome *stands in* for its "What's New" notice on a fresh
  install (it marks the news as seen), and chains its next prompt from
  the welcome's `OnHide` instead of opening both at once.
- ElvUI's rotating tips window refuses to show until the installer is
  complete (`if not E.private.install_complete then return end`).
- OneForAll's news popup waits a login while the welcome is due.

Rule: the tutorial owns the screen until dismissed, and anything else
this add-on would show automatically (including the campfire panel's
auto-open) has to account for it.

### 7. Always skippable, always replayable

Every reference has at least one of these, and the good ones have all
of them:

- **Close in one action:** Esc works (OneForAll and CraftBoard add their
  frame to `UISpecialFrames`), there's an explicit close/"Later"/"Skip",
  and the frame is draggable and clamped to the screen.
- **Replay:** a slash subcommand (`/cb welcome`, `/ofa setup`,
  ClassicUI's `welcome`) and a button in the add-on's options.
- **Developer reset:** ClassicUI has an unlisted `dev` subcommand that
  clears the flag so the next `/reload` behaves like a fresh install. It
  makes in-client testing take seconds instead of a SavedVariables wipe.

### 8. Short, task-shaped, ending in one obvious action

- CraftBoard: four steps, each an icon, a gold title, and at most three
  lines of grey body text (enforced with `SetMaxLines`), then one primary
  button ("Open Professions") and a secondary "Later."
- OneForAll: a "1 / 7" page counter so the player knows the length up
  front, "Choose myself" vs. "Recommended settings" on page one, and a
  final page that says where every setting lives later.
- The multi-page wizards (ElvUI, Details!, OneForAll) are configuration
  tools for add-ons with dozens of settings. Campfire Stokers has two
  settings (panel style, Say/Yell), so a wizard is out of proportion.

Each step should answer "what do I do?", not "what is this?". Close by
telling the player where the tutorial and settings live
(`/campfire`, the addon compartment, Settings > AddOns).

### 9. Point at the real UI where possible: `HelpTip`

Blizzard's `HelpTip` (the gold callout with an arrow used throughout the
default UI) is present and unmodified on Forever's 1.60.1 build
(`Interface/AddOns/Blizzard_SharedXML/HelpTip.lua`). Add-ons use it on
their own frames: NDui on its chat bar, LFGSpamFilter on its status
button.

- `HelpTip:Show(parent, info, relativeRegion)` with `info.text`,
  `buttonStyle` (`Close`, `Okay`, `GotIt`, `Next`), `targetPoint`,
  `alignment`, offsets, and `onAcknowledgeCallback` / `onHideCallback`.
  `ButtonStyle.Next` plus `onAcknowledgeCallback` is how you chain a
  multi-step tour.
- It returns `false` and shows nothing when `HelpTip:AreHelpTipsEnabled()`
  is false: Kiosk mode, gamepad UI, or the player's **`hideHelptips`
  CVar** (the "Tutorials" toggle in Blizzard's settings). There is no
  per-call override.
- **Project decision (2026-11-12): Campfire Stokers does not follow
  `hideHelptips`.** That setting governs the game client's own tips, not
  add-ons. Because `HelpTip:Show` enforces the setting itself, this add-on
  can't use HelpTip. Its callouts are its own frame, which can borrow
  HelpTip's stock textures for the look but none of its code, and which
  checks no CVars. The points below still describe good callout
  behavior; apply them to that frame.
- **Track acknowledgement in our own SavedVariables, not with
  `info.cvarBitfield`.** Blizzard's bitfields (`closedInfoFrames` and
  others) belong to Blizzard's own tips; both NDui and LFGSpamFilter
  leave `checkCVars` off and store the flag themselves.
- **Only show a tip on a visible anchor.** LFGSpamFilter checks
  `button:IsVisible()` first. Set `autoHideWhenTargetHides = true` so the
  tip doesn't float on screen after its frame closes.
- `systemPriority` lets a higher-priority tip in the same `system`
  replace a lower one. Give all of our tips one `system` string so they
  never stack.

### 10. Don't use `HelpPlate` on Forever

`HelpPlate` (the "?" button that overlays numbered boxes on a frame) is
deliberately disabled on Forever:
`Blizzard_HelpPlate/Camelot/HelpPlateOverrides.lua` makes
`MainHelpPlateButtonMixin:OnShow` hide the button immediately. This is
another entry for definition.md's "Known deviations from retail."

## Risks to verify in-client

- **HelpTip taint (moot for this add-on).** HelpTip frames come from a
  Blizzard-owned frame pool, so calling `HelpTip:Show` from add-on code
  means insecure code initializes a pooled frame that Blizzard code may
  reuse later. NDui and LFGSpamFilter do this and the risk looks low, but
  it's unverified on Forever. It doesn't apply here, since the
  `hideHelptips` decision above rules HelpTip out. It's kept for any
  future add-on that does use HelpTip.
- **Panel visibility at login.** A coach mark needs its anchor on
  screen. The campfire panel isn't shown at login unless the player is
  already at a fire, so a tour anchored to it has to open the panel
  first or wait for it.

## Checklist

- [ ] "Due" is decided from SavedVariables at `ADDON_LOADED`; showing happens after `PLAYER_LOGIN` plus a short delay.
- [ ] Combat-deferred with a `PLAYER_REGEN_ENABLED` pending flag, the same pattern as UI.lua's profession flush.
- [ ] Integer `tutorialVersion` in `CampfireStokersDB`, written when shown, and also on build failure.
- [ ] Fresh install vs. upgrade handled deliberately.
- [ ] Nothing else this add-on shows automatically opens on top of it.
- [ ] Esc, a close button, and an explicit Skip all dismiss it; draggable and clamped.
- [ ] `/campfire tutorial` replays it; a button in Options does too; there's a reset for testing.
- [ ] Short: each step answers "what do I do?" and fits in three lines; the last step says where to find things later.
- [ ] Callouts are this add-on's own frame and ignore `hideHelptips` (project decision). They only anchor to visible frames and hide with their target.
- [ ] Every string is in `CS.Data.L`; every new WoW global is in `.luacheckrc`'s `read_globals`.
- [ ] The decision logic ("is it due, what step next") is headless-tested; frames are checked in-client.
