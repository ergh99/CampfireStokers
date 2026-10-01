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
- [ ] The first CI run confirms wow-secret-lint actually scans the add-on and does not skip it as non-retail. If it skips, CI points it at the Lua files directly. (Confirmed locally that the fix works - see AGENTS.md's "Resolved item" - but no CI has actually run yet; this repo is still local-only. Revisit at T10.)
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

- [ ] A v* tag builds the zip through the packager, the zip folder is CampfireStokers, and the TOC Version is substituted.
- [ ] Every T6 check passes, or the failures are recorded and accepted in the Decision Log.
- [ ] The first build is distributed for player feedback.
