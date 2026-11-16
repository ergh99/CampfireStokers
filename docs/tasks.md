# Implementation Tasks

Implementation tasks for the Campfire Stokers Add-on Definition Document (`definition.md`), in build order. Every task also requires that its unit tests pass where it adds testable code, that luac5.1, Luacheck and wow-secret-lint pass, that it adds no globals beyond the compartment click handler, and that it follows AGENTS.md.

## Supporting skills

These run alongside T1 and T2.

- [ ] **S1, wow-secret-values.** A review checklist built from the current Warcraft Wiki secret-value rules and this design's guard pattern: ask ShouldAurasBeSecret first, check canaccessvalue on results, no by-index aura calls, no pcall as a guard, only booleans saved. Done when it lists each rule with its source and date and flags a sample file that breaks them.
- [ ] **S2, toc-gate.** Takes a repository, applies the TOC rule (the Interface line includes 16001 or a number starting with 12), then the two-month recency check, and reports pass or fail with the evidence. Done when it passes psykzz/wow-template and rejects a repository whose only TOC numbers are older.
- [ ] **S3, wow-lua-tests.** Scaffolds unit tests for pure Lua modules against a mocked WoW API and runs luac5.1 and Luacheck. Done when a sample module gets a passing test locally and in CI.
- [ ] **S4, wow-release.** Documents and automates the .pkgmeta file, the BigWigs packager and the tag flow. Done when a test tag builds a zip whose folder name matches the TOC.

## T1. Scaffold the repository

Depends on: nothing. S3 helps.

- [x] CampfireStokers.toc has Interface 16001 only, Title Campfire Stokers, Notes, Author, Version @project-version@, SavedVariables CampfireStokersDB, IconTexture, and AddonCompartmentFunc naming the global click handler.
- [x] The TOC loads Data.lua, Tree.lua, Send.lua, Detection.lua, UI.lua, Launcher.lua, Options.lua and Core.lua, in that order, and every empty module loads without errors.
- [x] The folder name, the TOC filename and the .pkgmeta package-as value are all CampfireStokers.
- [x] CI runs on each push: luac5.1 syntax, Luacheck with the compartment handler allowed as a global, wow-secret-lint in strict mode pinned to a commit, and the unit tests.
- [x] The first CI run confirms wow-secret-lint actually scans the add-on and does not skip it as non-retail. If it skips, CI points it at the Lua files directly. (Confirmed in real CI 2026-10-01 - see docs/decision-log.md's T10 entries - after fixing several CI-only issues no local verification could have caught: lua/luac binary naming, tool-installed .lua//.luarocks/ directories, and two rounds of Luacheck config for globals this code legitimately writes.)
- [ ] Pushing a v* tag builds a zip through the BigWigs packager. (T10, not yet attempted - needs a GitHub remote.)
- [x] AGENTS.md covers the Lua 5.1 and no-globals rules, the secret-value rules, the TOC gate and two-month recency rule, and the test, lint and release commands.

## T2. Data.lua: DefaultTree and string tables

Depends on: T1.

- [x] DefaultTree holds five categories in this order: Icebreakers, Trading, Professions, Info & Advice, Emotes.
- [x] It holds the nine phrases exactly as listed in the Default Starter Content table.
- [x] Every default category and phrase has a stable, readable string id.
- [x] All player-visible strings, including the default phrase text, come from a string table keyed by id. Only enUS ships.
- [x] A test confirms five categories, nine phrases, unique ids, every text at most 255 characters, and every string id resolving.

## T3. Tree.lua: tree operations and migration

Depends on: T2.

- [x] Bootstrap: when no saved tree exists, DefaultTree is deep-copied into CampfireStokersDB, and DefaultTree itself is never modified.
- [x] Operations: add category, add phrase, rename, edit text, delete, and reorder categories and phrases. Player nodes get generated string ids.
- [x] Categories sit directly under the root, and adding a category inside a category is rejected.
- [x] Phrase text over 255 characters is rejected. That is the only validation.
- [x] Deleting a default node records its id.
- [x] Migration: when schemaVersion is older, it adds any default category or phrase whose id is missing from the saved tree, skips recorded deleted ids, never touches player edits, then bumps schemaVersion.
- [x] Reset to defaults replaces the whole tree with a fresh copy of DefaultTree and clears the deleted-ids record.
- [x] Restore missing defaults re-adds every missing default, clears the deleted-ids record, and leaves other edits alone.
- [x] Unit tests cover each operation and these migration cases: fresh install, older version with missing defaults, a player-deleted default, and a player-edited default.

## T4. Send.lua: slash parsing and sending

Depends on: T3.

- [x] A pure function classifies a phrase and returns the send action, with command matching, including case and spacing, following the client.
- [x] A phrase without a leading / goes out on Say or Yell according to the panel toggle.
- [x] /s and /say send the rest on Say, /y and /yell send it on Yell, and /e and /emote send it as an emote.
- [x] A built-in emote command, found by scanning the client's emote command globals, performs that emote through DoEmote at the current target and ignores any text after the command. (Forever's actual registration convention differs from retail - see AGENTS.md/decision-log.)
- [x] Any other slash command, empty text, or an emote the client reports as restricted is not sent. It is flagged, and a chat message tells the player why.
- [x] Text is limited to 255 characters, %t is left for the client to replace, and a helper reports whether a phrase contains %t.
- [x] Unit tests use mocked emote globals, SendChatMessage and DoEmote.

## T5. Detection.lua: campfire detection

Depends on: T4.

- [x] It registers UNIT_AURA for the player only and PLAYER_ENTERING_WORLD, and registers ADDON_RESTRICTION_STATE_CHANGED inside a pcall. It uses no timers, OnUpdate handlers or combat log.
- [x] State is at fire or not at fire, and state changes are announced to the UI.
- [x] Each event runs the same check: if C_Secrets.ShouldAurasBeSecret() is true, skip the read and treat the player as not at a campfire.
- [x] Otherwise it reads only C_UnitAuras.GetPlayerAuraBySpellID with the campfire spell ID, ignores the UNIT_AURA payload, and never uses by-index, by-slot or by-instance-id aura calls.
- [x] The result is used only after canaccessvalue(result) is true, and an unreadable or nil result counts as no campfire aura.
- [x] Only booleans are persisted, never aura data. The campfire spell ID is one constant, confirmed in T6.
- [x] Unit tests use mocked C_Secrets and C_UnitAuras and cover: auras secret, readable and present, readable and nil, canaccessvalue false, and a failed event registration.
- [x] wow-secret-lint reports no findings.

## T6. In-client verification

Depends on: T5. This is the first task that runs in the client.

- [x] A self-test subcommand of the add-on's slash command reports pass, fail or unknown for each of these: the campfire aura's spell ID and whether campsites are enabled, aura reads while secrecy is active, registering an unknown event, ReloadUI protection, %t through SendChatMessage, the hardware-event requirement for Say, Yell and emote sends, the addon compartment, C_Secrets, and the client's emote command globals.
- [x] A second subcommand simulates campfire state (at fire or not at fire) so the panel can be tested without a real campfire.
- [x] Detection is tested with the forced-restriction console variables such as addonCombatRestrictionsForced.
- [x] Results are recorded in the Decision Log, the spell ID constant from T5 is updated, and any failed assumption is raised for a design decision.

## T7. UI.lua: the campfire panel

Depends on: T6.

- [x] The panel is an undecorated frame anchored near the chat window by default, draggable, with its position saved account-wide.
- [x] Categories are collapsible headers and phrases are single-line buttons, with each category's collapsed state saved.
- [x] Clicking a phrase sends it immediately through Send.lua with no confirmation and briefly highlights the button.
- [x] A Say/Yell toggle in the panel is saved and applies to phrases without a slash command.
- [x] The panel auto-opens when state becomes at fire, and it has a close button.
- [x] Auto-open mirrors aura detection directly, with no delay or cooldown. Opening the panel manually is, as always, immediate. (Changed 2026-10-01 from the original rate-limited design - see docs/decision-log.md.)
- [x] Losing the campfire aura (including while auras are restricted, which Detection reports as not-at-fire too) starts a 10-second countdown before an auto-opened panel closes, cancelled if the aura is regained first - the aura can drop and reapply repeatedly while the player sits still, so closing immediately on the first loss would flicker the panel shut and open. (Changed 2026-10-01.)
- [x] Phrases containing %t are disabled until a target is selected, re-checked on PLAYER_TARGET_CHANGED.
- [x] Unsendable phrases are visibly flagged.
- [x] It uses no secure templates, and all strings come from the string table.
- [x] Manual in-client checks pass using the simulate subcommand from T6.

## T8. Options.lua: the phrase tree editor

Depends on: T7.

- [x] The editor is a custom canvas in Blizzard's Settings interface under AddOns, with no libraries.
- [x] It supports add category, add phrase, delete, and rename and edit text through a popup dialog, and drag-and-drop reordering of phrases and categories, all through Tree.lua.
- [x] Phrase text over 255 characters is rejected with a message, and unsendable phrases are flagged.
- [x] ~~An auto-open delay setting defaults to 5 minutes.~~ Removed 2026-10-01: auto-open no longer has a delay/cooldown to configure - see T7 and docs/decision-log.md.
- [x] Two buttons handle defaults: Reset to defaults asks for a confirmation and replaces the whole tree, and Restore missing defaults re-adds deleted defaults without touching other edits.
- [x] It never calls ReloadUI and refreshes in place.
- [x] Manual in-client checks confirm each change appears in the panel immediately and survives a /reload.

## T9. Launcher.lua and the slash command

Depends on: T8.

- [x] The global click handler named in the TOC toggles the panel.
- [x] The add-on's slash command, /campfire, with /cfs as an alias, toggles the panel when given no arguments and keeps the T6 subcommands.
- [x] There is no minimap button and no hover tooltip.
- [x] Luacheck allows the single global handler.

## T10. Package and release

Depends on: T9.

- [x] A v* tag builds the zip through the packager, the zip folder is CampfireStokers, and the TOC Version is substituted. (v0.1.0, 2026-10-01: verified by downloading the actual release zip - correct folder name, correct load order, `## Version: v0.1.0` substituted for `@project-version@`, none of docs/tests/.github/AGENTS.md included.)
- [x] Every T6 check passes, or the failures are recorded and accepted in the Decision Log. (All nine checks resolved - pass, or a recorded/accepted finding - per the T6 decision-log entries.)
- [x] The first build is distributed for player feedback. (Public release at github.com/ergh99/CampfireStokers/releases/tag/v0.1.0 - live and downloadable. Actually gathering player feedback is an ongoing activity beyond this checklist item's scope.)

## T11. First-run tutorial

Depends on: T10. Design: [tutorial-plan.md](tutorial-plan.md). Code
written 2026-11-14; every item, and V1-V5, confirmed in-client by the
project owner and shipped in v1.1.0 (2026-11-15).

- [x] Tutorial.lua: pure due/seen/step logic plus `Init`, with headless tests (`tests/tutorial_spec.lua`).
- [x] Saved state is `CampfireStokersDB.tutorial`, plain values only, and v0.1.0 saves see it once.
- [x] Welcome card after `PLAYER_LOGIN` + 3 s, combat-deferred, styled to match the panel, closable with Esc, X and Maybe later, draggable and clamped.
- [x] "Show me around" opens the real panel and tours it, then its Open Editor step opens the editor and runs the four-step editor tour with hover widgets pinned (revised 2026-11-14, see decision-log.md). Nothing sends the player to chat; mid-fight it waits for combat to end.
- [x] Reset to Defaults has a mouseover tooltip.
- [x] Panel tour on the first auto-open, after the card (no Say/Yell step, removed 2026-11-14), skipping the feature step when no feature buttons show. It resumes if cut short.
- [x] The editor tour is offered at the end of the panel tour if it hasn't run.
- [x] Callouts are our own frame and ignore `hideHelptips`.
- [x] `/campfire tutorial`, `/campfire tutorial reset`, and a Replay button in Options. (Slash routing headless-tested.)
- [x] Strings in `CS.Data.L`, globals in `.luacheckrc`, and luac/luacheck/tests/wow-secret-lint all pass.
- [x] V1-V5 confirmed in-client and recorded in decision-log.md. Definition.md updated (Features, Saved Variables, Known Deviations). (See decision-log.md, "First-run tutorial verified in-client".)

## Future Scope: Profession Campfire Enhancements

**Not scheduled, not started.** Captured 2026-10-02 for later design and
implementation once real in-client data is available - see
[definition.md](definition.md#future-scope-v2-profession-campfire-enhancements)
for the full feature description and the list of open questions this
milestone exists to resolve. Unlike T1-T10, this is not a committed next
step; do not begin implementation work here without first confirming the
open questions below in-client, the same way T6 did for the original
build.

Depends on: T10 (uses the existing campfire panel and detection
infrastructure; adds to them, doesn't replace them).

- [x] In-client discovery: confirmed 2026-10-02 against a five-profession
      test subset (see docs/research.txt and definition.md's "Confirmed
      via in-client research"). Profession detection is the bare
      `GetProfessions()`/`GetProfessionInfo()` globals, retail-shaped. The
      campfire recipe for profession X is identified by `craftable` on
      `C_TradeSkillUI.GetRecipeInfo(recipeSpellID)` - the craft spell ID
      doubles as the recipe ID directly, no separate lookup needed.
- [x] In-client discovery: confirmed 2026-10-02. Silent, one-click crafting
      IS achievable - `C_TradeSkillUI.CraftRecipe(recipeSpellID)` is
      callable from ordinary (non-secure) addon code and was verified live
      to actually craft the item (bag count 0 -> 1, reagents consumed, no
      UI interaction). This risk was mislabeled: crafting turned out to be
      the easy part. The real architectural risk, discovered in the same
      session, is using/placing the crafted item - see the new item below.
      **Superseded 2026-10-05**: `CraftRecipe` does nothing unless the
      real crafting frame is shown on that recipe, and crafting ended up
      as two clicks - see the "Clicking a button" item below and
      `docs/craft-profession-switch-findings.md`.
- [x] In-client discovery: `C_Item.UseItemByName` (the "use/place the
      item" step) cannot be called from ordinary insecure Lua at all -
      confirmed 2026-10-02, it throws citing `SecureActionButtonTemplate`,
      even from inside a plain `Button`'s `OnClick`. Confirmed working
      2026-10-04 via a temporary `SecureButtonTest.lua` smoke test (now
      removed): a `SecureActionButtonTemplate` button toggled between
      `SetAttribute("type","item")`/`SetAttribute("item", itemName)`
      (use) and cleared attributes + ordinary `PreClick` logic
      (craft/request) works correctly with no taint, and caught a real
      bug before it shipped (`RegisterForClicks("AnyUp","AnyDown")`
      double-firing `PreClick` per click - fixed to `"AnyUp"` only).
      **Revised 2026-10-05**: `"AnyUp"` only broke item use with
      `ActionButtonUseKeyDown` on; now both are registered and
      `PreClick` ignores the press - see "Placing a prepared campfire
      feature does nothing" below.
      Implemented in `UI.lua`'s `createProfessionButton`/
      `layoutProfessionBlock`.
- [x] In-client discovery: confirmed 2026-10-02. Reagent item IDs are
      reachable via `GetRecipeSchematic(recipeSpellID,
      false).reagentSlotSchematics[n].reagents[1].itemID`. **Corrected
      during implementation**: `GetCraftableCount(recipeSpellID)`
      looked like the yes/no "can craft right now" gate, but returned
      `0` for two recipes (Blacksmithing, Mining) while the character
      held 46x/62x of the only two reagents required (1 each) - it can
      be `0` for reasons unrelated to materials. The real gate is
      walking the schematic against `C_Item.GetItemCount` directly (the
      same walk already needed to build the missing-materials list);
      `GetCraftableCount` isn't used at all.
- [x] Proximity: resolved 2026-10-02 as a design decision, not an
      in-client discovery - the campfire feature enforces being at a
      campfire itself, but the panel should not rely on that alone. Gate
      each profession button's visibility/enabled state on the same
      `CS.Detection` at-fire boolean (spell `1229739`, the "Welcoming
      Campfire" aura) already driving the rest of this panel - no new
      aura or API needed. **Superseded 2026-10-05**: buttons are no
      longer gated on at-fire - see "Profession button visibility"
      below.
- [x] Confirmed 2026-10-02 (player domain knowledge): each profession has
      (at least) three reward tiers, functionally different per tier, not
      "the same campfire feature, upgraded" - tier 1 is a placeable sit-buff
      augmenter (for anyone at that fire, not just the placer; Engineering
      tier 1 is the one exception, an interactable vendor-spawner, which
      needs no special handling here - the add-on's job ends at
      use/craft/request regardless of what the object does after
      placement); tier 2 is a placeable crafting-proximity station for
      new Forever-only recipes (not a buff at all); tier 3 isn't
      discovered/datamined yet. **Scope decision**: tiers 2/3 are
      strictly additive over tier 1 (a placed tier 2/3 object also counts
      as its tier-1 self, plus niche extras, at higher crafting cost) -
      given that, and the added cost for only niche benefit, this add-on
      supports **tier 1 only**. "One button per profession" stands as
      originally written; tier 2/3 data is kept in docs/research.txt for
      reference, not for implementation.
- [x] Confirmed 2026-10-02 (Wowhead, reagents used to attribute each
      item to its profession rather than guessing from the name - see
      docs/research.txt for the full table): Enchanted Lute/Enchanting,
      Camp Tent/Leatherworking, Reagent Bot/Engineering (this is the
      "spawns a vendor" exception - a reagent-vendor bot, fits exactly),
      Sharpening Wheel/Blacksmithing, Faction Banner (two faction-specific
      item IDs)/Tailoring, Lodestone/Mining (a profession not previously
      in scope at all), and Camp Chair/Skinning (confirmed directly, not
      just inferred from reagents). **Profession coverage is complete**:
      Jewelcrafting and Inscription don't exist in Forever (added in TBC
      and Wrath respectively), so these 11 professions are the full set,
      not a partial list - no further profession discovery needed.
- [x] Profession detection: superseded by a simpler design, confirmed
      2026-10-04 - `GetProfessions()`/`GetProfessionInfo()` are never
      called at all. Since the 11 campfire features are a fixed, known list (not
      open-ended discovery), `C_TradeSkillUI.IsRecipeProfessionLearned(
      recipeSpellId)` gates each one directly and was confirmed live to
      correctly distinguish a known profession (Skinning, `true`) from
      an unknown one (Alchemy, `false`) on the same character -
      `GetRecipeInfo`'s `craftable` field, tried first, turned out to
      return `true` regardless of whether the profession is known at
      all, so it couldn't be used for this. Implemented in
      `Professions.lua`'s `EvaluateFeature`.
- [x] The campfire panel shows one button per campfire feature the
      character could plausibly use (skill >= 20), determined
      dynamically, not from a hardcoded list. Implemented: `UI.lua`'s
      `layoutProfessionBlock` lays out label-less icon buttons (one per
      `CS.Professions.FEATURES` entry) in a wrapped grid, visible only
      when `EvaluateFeature` says so.
- [x] Clicking a button, with no confirmation dialog at any step, matching
      this add-on's existing one-click philosophy: uses the item from bags
      if present; otherwise crafts if materials are present - in two
      clicks (confirmed in-client 2026-10-05, Rounds 14-17 of
      `docs/craft-profession-switch-findings.md`): the first opens the
      real crafting frame on the recipe via `C_TradeSkillUI.OpenRecipe`,
      the second calls `CraftRecipe` and hides the frame. A single-click
      open-craft-hide did nothing once a different profession had been
      opened by hand (Rounds 7, 9); otherwise yells a request for the
      missing materials.
      Confirmed 2026-10-02: message structure is "I can place a/an
      &lt;item link&gt; at the campfire if someone wants to provide
      &lt;list of missing materials&gt;," with the item link and the
      missing-materials list both generated dynamically. Implemented in
      `Professions.lua` (`EvaluateFeature`, `BuildRequestMessage`, `Craft`)
      and wired into `UI.lua`'s secure-button `PreClick` handler.
- [x] Unit tests for whatever pure logic this produces (e.g. a
      Classify-style function deciding use/craft/request from bag-count
      inputs), following this project's established pattern of separating
      pure decision logic from the real API calls around it. Implemented
      in `tests/professions_spec.lua` (`FEATURES`, `ResolveEntry`,
      `EvaluateFeature`, `BuildRequestMessage` via dependency injection,
      `Craft`/`CreateEventFrame` via the same monkey-patch/fake-frame
      patterns `send_spec.lua`/`detection_spec.lua` already use).
- [x] **Profession button visibility.** Observed in-client 2026-10-05
      (Round 17 of `docs/craft-profession-switch-findings.md`):
      interrupting a craft cast by moving the character removes the
      campfire aura; the panel reacts by hiding the profession buttons
      right away, while the panel itself and its other elements stay
      visible until the delayed auto-close timer finishes. Also reported
      the same day (`docs/profession-button-appearance-findings.md`):
      the buttons are only ever shown or hidden as a whole. Today
      `UI.lua`'s `evaluateFeatureSafely` treats every button as hidden
      whenever `CS.Detection.atFire` is false. **Desired** (the user's
      answers, recorded in that ledger): the profession buttons are
      shown whenever the panel is visible - including a panel opened
      manually away from a campfire ("Always") - and when the panel
      auto-opens, the buttons are evaluated first, so the panel never
      appears without them or has them pop in afterwards ("Evaluated
      first").
      **Done 2026-10-05**: `evaluateFeatureSafely` no longer checks
      `atFire`, and `CS.UI.Show` (manual open/toggle) now calls
      `CS.UI.Refresh()` before showing, as the auto-open path in
      `OnCampfireStateChanged` already did. Verified in-client (Round 11
      of `docs/profession-button-appearance-findings.md`) across
      auto-open, aura drop and manual open away from a fire: "button
      visibility was static in each scenario as desired".
- [x] **Yell request message's "a/an" is literal.** Reported in-client
      2026-10-05: the message reads "I can place a/an &lt;item link&gt;
      ..." verbatim. `Professions.lua`'s `BuildRequestMessage` hard-codes
      "a/an". **Desired**: use "a" or "an" as appropriate for the item
      name in the generated message.
      **Done 2026-10-05, confirmed in-client ("confirmed working")**: new pure
      `CS.Professions.IndefiniteArticle(name)` ("an" before a vowel
      letter, "a" otherwise - right for all 11 FEATURES names, of which
      only Incense Candle and Enchanted Lute take "an"), used by
      `BuildRequestMessage` with the item's plain name. Unit tests cover
      both articles and every FEATURES name.
- [x] **Placing a prepared campfire feature does nothing.** Reported
      in-client 2026-10-05: clicking a profession button that should
      place a campfire feature already in the bags (the "use" state) does nothing
      and shows no error. That path is the secure click-through set up
      in `UI.lua`'s `applyProfessionButtonState` (`type` = `"item"`,
      `item` = the item's name).
      **Done 2026-10-05, verified in-client** (Round 3 of
      `docs/profession-use-findings.md`: use, craft and request each
      confirmed working, one action per click): the attributes
      were correct (Round 1), but `ActionButtonUseKeyDown` was `1` and
      the button only registered `"AnyUp"`; registering `"AnyDown"` too
      made the click place the Sharpening Wheel (Round 2). `UI.lua` now
      registers both, and `PreClick` ignores the press so craft/request
      still fire once per click.
- [x] **255-character check counts item links at full raw length.**
      Reported in-client 2026-10-05: the Fishing and First Aid request
      yells were refused for a character with none of the materials.
      `Send.lua`'s `Classify` checks `#text > 255` (raw bytes). Findings
      (`docs/yell-length-findings.md`): the game's limit is 255 visible
      characters with each item link counting as its visible `[Name]`,
      brackets included (Rounds 4-5); raw length up to 619 bytes of links
      was accepted (Rounds 1-2); over the limit `SendChatMessage` raises
      "Chat message limits exceeded" (Rounds 3-5). **Desired**: count
      links by their visible text when applying the 255 limit. Tested on
      SAY only; confirm on YELL after the fix.
      **Done 2026-10-05, confirmed in-client** (Round 6, a real request
      yell: "confirmed working"): new pure
      `CS.Send.VisibleLength(text)` strips `|H...|h`/`|h` link wrappers,
      `|cAARRGGBB` color starts and `|r` resets before counting;
      `Classify` checks that against 255 instead of `#text`. Four new
      unit tests cover the Round 5 boundary (255 passes, 256 fails) and
      a 10-link message far over 255 raw bytes. `Tree.lua`'s phrase
      editor still checks raw `#text`; unchanged, since it wasn't part
      of this report.
- [x] **Profession buttons show the shared campfire feature cooldown.**
      Placing any campfire feature puts every campfire feature's Use on
      one shared cooldown, which the panel didn't show.
      **Done 2026-10-14, confirmed in-client ("confirmed working as
      expected")**: each profession button has a `CooldownFrameTemplate`
      sweep with countdown numbers, set from
      `CS.Professions.GetItemCooldown` on "use" buttons only, updated on
      every Refresh and on `BAG_UPDATE_COOLDOWN`. Four new unit tests,
      including one that fails if a secret cooldown value is compared.
