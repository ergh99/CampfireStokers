# Campfire Stokers - Add-on Definition Document

September 29, 2026 · CodePoet

A World of Warcraft: Forever add-on that gives players one-click access to an editable, categorized tree of conversation-starter phrases, surfaced automatically when the player is sitting at an in-game campfire.

## Overview

Campfire Stokers solves a small, specific social friction point: two strangers sit down at a campfire emote circle and neither knows what to say. The add-on adds a lightweight, campfire-aware panel that lets a player click a canned phrase - organized by category in a collapsible tree - and send it on Say or Yell, or as an emote, instantly.

The phrase list ships with a bootstrapped starter set so the add-on is useful immediately on install, but every category and phrase is player-editable: players can rename, add, remove, and reorganize entries to match their own voice and server culture.

## Target Platform and API Version

The add-on targets World of Warcraft: Forever, which runs its own client. Its addon API is based on retail's, including the secret-value system added in 12.0 and extended to auras in 12.1, but it is not identical, so retail code cannot be assumed to work unchanged. Classic-era globals such as UnitAura and GetSpellInfo are absent ([forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit), measured on the live client).

The TOC Interface number is 16001 on the current Forever build, confirmed in-client with GetBuildInfo(). It can change before launch, and it is not a retail number, so the add-on never gates behavior on the build number and detects features directly instead, for example by testing that C_Secrets exists.

Known deviations from retail that affect this add-on:

- Registering an unknown event throws, so non-core events such as ADDON_RESTRICTION_STATE_CHANGED are registered inside a pcall.
- ReloadUI is protected, so the options panel refreshes the phrase tree in place and never calls it.

## Features

1. Campfire panel: a compact, movable frame that appears near the chat window, showing the phrase tree when the campfire aura is detected.
    1. Collapsible category nodes, expanding to their child phrases.
    2. One click on a phrase sends it immediately, no confirmation dialog.
2. Send targets and target names: a Say/Yell toggle in the panel applies to phrases without a slash command, a phrase that starts with / is sent the way the client would read it (/s and /say on Say, /y and /yell on Yell, /e and /emote as an emote, and built-in emote commands such as /salute perform that emote), and a %t in phrase text is replaced with the target's name by the client when sent.
3. Phrase tree editor: an in-game options panel for adding, renaming, reordering by drag and drop, and deleting categories and phrases, hosted in a custom canvas inside Blizzard's Settings interface.
4. Bootstrapped starter content: on first load, the add-on seeds a default tree so the panel is immediately useful, five categories (Icebreakers, Trading, Professions, Info & Advice and Emotes), listed under Default Starter Content.
5. Manual override: an addon compartment entry and a slash command to open the panel on demand, regardless of campfire state, for players who want to use phrases away from a fire.
6. Secret-value-safe detection: campfire state is driven by UNIT_AURA events and read only when the client reports aura data as readable, with no polling.

Out of scope for v1: whispers, chat channels other than Say, Yell and emote, import and export, profiles, and a hover tooltip on the addon compartment entry.

## Data Model: the Phrase Tree

*(Diagram: a root "Phrase Tree" with five categories beneath it, each holding phrases: Icebreakers 3, Trading 1, Professions 1, Info & Advice 2, Emotes 2.)*

Each node is either a category, which holds phrases and sits directly under the root, or a phrase, which holds the text to send. The editor walks this same tree to build its rows, so the data and the UI share one shape. Categories cannot contain other categories.

A node table looks like this in Lua: a table with fields id (a readable string for default nodes, a generated string for player nodes), node type of either category or phrase, name or text, children for categories, and for phrases the text to send, which may begin with a slash command and is limited to 255 characters, the chat message limit and the only validation the editor enforces. SavedVariables stores the whole tree account-wide, plus a schemaVersion field so future updates can migrate the bootstrapped defaults without clobbering a player's edits.

Bootstrapping runs once on first load: if no saved tree exists, the add-on deep-copies a constant DefaultTree table into SavedVariables. Editing never touches DefaultTree, only the player's live copy, so a reset-to-defaults option is always possible.

Target names: a %t in phrase text is replaced by the client with the target's name when the phrase is sent, so the add-on never reads or handles the name itself ([Warcraft Wiki: Chat substitutions](https://warcraft.wiki.gg/wiki/Chat_substitutions)). With nothing targeted the client inserts `<no target>`, so the panel disables any phrase containing %t until a target is selected, re-checking on PLAYER_TARGET_CHANGED.

Slash parsing: at send time the add-on checks whether the phrase starts with /. If it does, it reads the command the way the client would, with case and spacing following the client's rules: /s or /say sends the rest on Say, /y or /yell sends it on Yell, and /e or /emote sends it as an emote. A phrase whose command matches a built-in emote command, such as /salute, performs that emote through DoEmote, aimed at the current target as the client does by default (the add-on finds the token by scanning the client's emote command globals) and ignores any text after the command. A phrase starting with any other slash command, with empty text, or with an emote the client reports as restricted is not sent; it is flagged in the editor and a chat message tells the player why. A phrase that does not start with / goes out on Say or Yell according to the panel toggle.

## Default Starter Content

The DefaultTree holds five categories and nine phrases, stored exactly as written below.

| Category | Phrase |
| --- | --- |
| Icebreakers | What’s the best thing you looted today? |
| Icebreakers | What has been your favorite place in this zone? |
| Icebreakers | What are you hoping to experience while you’re in this area? |
| Trading | Got anything taking up space you want to trade? |
| Professions | What are you making to skill up your professions? |
| Info & Advice | Looking to group for the next 10 mins to knock out a quest or explore? |
| Info & Advice | What tips should everyone know about this zone? |
| Emotes | /salute |
| Emotes | /e warms their weary bones by the fire. |

## Campfire Detection and Secret-Value Safety

Detection is event-driven and never polls. The add-on registers UNIT_AURA for the player only, plus ADDON_RESTRICTION_STATE_CHANGED and PLAYER_ENTERING_WORLD, and treats each as a cue to re-evaluate campfire state. It uses no timers, no OnUpdate handlers, and no combat log.

Since 12.0, aura data is secret whenever addon restrictions are active, which covers combat, boss encounters, Mythic+ runs, and PvP matches ([Warcraft Wiki: It's Secret](https://warcraft.wiki.gg/wiki/Secret_Values)). Addon code is always tainted, so it cannot compare or branch on a secret value, and a pcall does not undo the taint. The rule is to ask the client first, then read:

1. Ask whether aura reads are allowed. If C_Secrets.ShouldAurasBeSecret() returns true, skip the read and treat the player as not at a campfire.
2. Read one aura only: C_UnitAuras.GetPlayerAuraBySpellID with the campfire spell ID. Community references treat this player-only lookup as safe for tainted callers ([RGX-Framework: Auras](https://github.com/RGXMods/RGX-Framework/wiki/Auras/94d9b6f03c333f1f4770e67ee60ba6162710d556), updated Aug 14, 2026), but a measurement on the Forever beta found every aura read throwing while secrecy was active ([forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit)). Step 1 is therefore mandatory, not an optimization.
3. Check the result before using it. canaccessvalue(result) must be true before the add-on tests fields or branches on it. An unreadable or nil result counts as no campfire aura.

UNIT_AURA payloads serve only as a trigger. Aura instance IDs are never secret, but the aura contents can be, so the handler ignores the payload and does the guarded lookup instead. Because the guard tests restriction state rather than combat alone, the same code stays correct in encounters and PvP with no separate InCombatLockdown check.

While auras are restricted, the player counts as not at a campfire, so auto-open is suspended and an auto-opened panel is hidden. The slash command and the addon compartment entry keep working, since sending a phrase does not depend on aura data. Only booleans are written to SavedVariables, never aura data, because saved variables cannot hold secret values. To test without a real fight, set the forced-restriction console variables such as addonCombatRestrictionsForced, which simulate secrecy on demand.

## Project Structure

A reference add-on must pass two checks, in this order. First, its TOC Interface line must include 16001 or a number starting with 12, because a line holding only older numbers means the add-on is out of date. Second, it must have shipped a release or commit within the past two months. [psykzz/wow-template](https://github.com/psykzz/wow-template) (Interface 16001, README current as of September 2026) is the reference for layout and release workflow, and [psykzz/wow-quickbuyout](https://github.com/psykzz/wow-quickbuyout/releases) (Interface 16001, 50504, 120100; v0.0.3 on September 28, 2026) is the reference for a small one-click add-on.

Top-level layout: CampfireStokers.toc at the root; Core.lua for initialization and event registration; Data.lua holding the DefaultTree bootstrap constant; Tree.lua holding tree operations such as add, rename, delete, reorder and reset; Send.lua holding slash parsing, %t handling and sending; Detection.lua holding the UNIT_AURA handler and the secret-value guards described above; UI.lua for the campfire panel; Launcher.lua for the addon compartment click handler, which the TOC names and which must therefore be a global function; and Options.lua hosting the tree editor in Blizzard's Settings interface. The add-on embeds no libraries.

Localization: every player-visible string, including the default phrase text, is read from a string table keyed by id. Only English ships in v1, and the table structure lets other locales be added without code changes.

Repository housekeeping follows wow-template: a .pkgmeta file for the BigWigs packager, GitHub Actions running Lua 5.1 syntax, Luacheck and wow-secret-lint checks on each push, and a tag-triggered release, so pushing a v* tag builds and publishes the zip.

Testing: Send.lua, Tree.lua and migration are plain Lua and get unit tests that run outside the client against a mocked WoW API, alongside luac5.1 syntax checks, Luacheck, and wow-secret-lint in strict mode, which fails the build on secret-value violations such as by-index aura calls. Detection, UI, Options and Launcher are checked manually in the client. Two in-client commands support those checks: a self-test that reports each client assumption, and one that simulates campfire state so the panel can be tested without a real campfire.

The repository includes an AGENTS.md guidance file with four parts: Lua 5.1 and no-globals rules, the secret-value rules, the TOC gate and two-month recency rule for reference add-ons, and the test, secret-value lint and release commands. Four supporting skills are built for the repo: wow-secret-values, a review checklist for the secret-value rules; toc-gate, which applies the TOC and recency rule to candidate references; wow-lua-tests, a mocked-API test harness; and wow-release, the packager and tag flow.

## The TOC File

The Interface line is 16001 for the current Forever build, confirmed in-client by printing the fourth return value of GetBuildInfo(), and updated if the number changes. Use the client's own number rather than a value copied from a retail add-on.

A representative TOC: an Interface line with the confirmed number, Title Campfire Stokers, Notes describing the one-click phrase panel, Author, Version, IconTexture, the AddonCompartmentFunc field naming a global click handler in Launcher.lua, and SavedVariables CampfireStokersDB for the account-wide phrase tree. The load order lists Data.lua, Tree.lua, Send.lua, Detection.lua, UI.lua, Launcher.lua, Options.lua, and Core.lua last, matching the dependency direction of the modules.

## UI and UX

The campfire panel is a small, undecorated frame anchored near the chat window by default, draggable and position-remembered account-wide. It opens automatically on campfire detection and can be dismissed with a close button or by standing up from the fire, and reopened anytime through an addon compartment entry or the slash command /campfire, or its alias /cfs.

Auto-open has no delay or cooldown: it mirrors campfire detection directly, opening every time the player is detected at a fire. Opening the panel manually is, as always, immediate either way. Auto-close is not immediate, though: the campfire aura can drop and reapply repeatedly while the player sits at the fire without moving, so losing it starts a 10-second countdown in memory (never saved) rather than closing the panel outright; regaining the aura before the countdown elapses cancels it. Only a panel this add-on auto-opened is ever auto-closed - one opened manually stays up regardless of the aura.

The panel shows the phrase tree as a collapsible outline, categories as expandable headers and phrases as single-line buttons beneath them. Clicking a phrase sends it immediately, using the panel's Say/Yell toggle unless the phrase starts with a slash command and briefly highlights the button as feedback.

The options panel, opened through the standard Blizzard Settings interface under AddOns, hosts the phrase tree editor: add category, add phrase, rename and delete controls, where rename and edit open a popup dialog, drag-and-drop reordering, and an auto-open delay setting (5 minutes by default). Two buttons handle defaults: Reset to defaults replaces the whole tree with the bootstrapped starter tree after a confirmation, and Restore missing defaults re-adds any default category or phrase the player has deleted, clearing the deleted-ids record, without touching other edits.

## Saved Variables and Persistence

CampfireStokersDB is declared account-wide in the TOC's SavedVariables line, so a player's customized phrase tree follows them across characters and realms. It stores the phrase tree itself, the schemaVersion for future migrations, the ids of any default nodes the player has deleted, per-category collapsed or expanded state, the panel's last screen position, and the Say or Yell toggle state.

Every category and phrase in DefaultTree carries a stable id. Migrations are additive: on load, if schemaVersion is older than the add-on's current version, a migration function walks DefaultTree and adds any default category or phrase whose id is missing from the saved tree, without touching existing player edits, then bumps schemaVersion. The ids of default nodes the player has deleted are recorded, and migrations never restore them.

## Future Scope (v2): Profession Campfire Enhancements

Not scheduled, not started, captured here for later design/implementation
once real in-client data is available. See
[tasks.md](tasks.md#future-scope-profession-campfire-enhancements) for the
milestone shell.

**Context**: WoW Forever adds a new class of crafted consumables, one per
profession (both primary and secondary professions), unlocked at skill
level 20. Using one of these at a campfire creates an object that enhances
the campfire's existing sit-for-a-minute, hour-long buff with additional
effects - specifically combat buffs - for everyone who benefits from that
fire.

**Feature**: the campfire panel gains one button per profession-crafted
good the player's current character could plausibly use, determined
dynamically from which professions the character actually knows and at
what skill level - not a hardcoded list, since Forever's specific
item/recipe data for this isn't available yet. Clicking a profession's
button attempts, in order, with no confirmation dialog at any step
(matching this add-on's existing one-click philosophy):

1. **Use.** If the consumable is already in the player's bags, use/place
   it immediately.
2. **Craft.** If not, attempt to craft it - fully silently, with no
   crafting-UI interaction - assuming the required materials are present.
3. **Request.** If materials are also missing, yell a message offering to
   craft and place the good in exchange for the missing materials, with
   the specific missing items and quantities generated dynamically into
   the message text.

**Confirmed via in-client research (2026-10-02)**, against a test subset
of five professions (Fishing/Fish Bowl, Alchemy/Mana Well,
Herbalism/Incense Candle, Cooking/Basic Campfire Kit, First Aid/First Aid
Kit); the full command-by-command log lives in `docs/research.txt`:

- The client's crafting-related addon API surface is retail-shaped (the
  modern `C_`-namespaced functions), not classic, even though the
  underlying crafting system itself has no stations or stats/specialization
  layer. Legacy bare globals (`GetSpellInfo`, `IsSpellKnown`, `GetItemCount`,
  `UseItemByName`, `CastSpellByID` for crafting, `GetNumSkillLines`) are all
  absent/erroring; use `C_Spell`, `C_Item`, `C_TradeSkillUI` instead.
- Profession detection: the bare globals `GetProfessions()`/
  `GetProfessionInfo()` work as retail's do. First Aid is not tracked
  through them (matches modern retail, which also dropped it from
  `GetProfessions()`).
- "Is this good craftable by this character" is `craftable` on
  `C_TradeSkillUI.GetRecipeInfo(recipeSpellID)` - the craft spell ID
  doubles as the recipe ID directly. (Not `learned`, which reads `false`
  even on a character with the profession well past skill 20 - it tracks
  something else, unused here.)
- "Does this character have the reagents on hand right now" is
  `C_TradeSkillUI.GetCraftableCount(recipeSpellID)` - confirmed to do real
  reagent-ratio math (returned 14 against 14 of one reagent and 17 of
  another, i.e. the scarcer at a 1:1 ratio). This is the yes/no gate for
  the craft-vs-yell fork; no manual reagent-count comparison needed for
  that part.
- Reagent item IDs (for building the dynamic missing-materials list) are
  reachable via
  `C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, false).reagentSlotSchematics[n].reagents[1].itemID`.
- `C_TradeSkillUI.CraftRecipe(recipeSpellID)` is callable from ordinary
  (non-secure) addon code and was confirmed, live, to actually craft the
  item (bag count 0 -> 1, reagents consumed) with no further UI
  interaction. Crafting is **not** the hard part.
- **Corrected risk, was previously mislabeled as crafting**: using/placing
  the crafted good is the step that's actually hard. `C_Item.UseItemByName`
  cannot be called from ordinary insecure Lua at all (confirmed: it throws
  citing `SecureActionButtonTemplate`), including from inside a plain
  `Button`'s `OnClick`. It requires a `SecureActionButtonTemplate`-based
  button with secure attributes set ahead of time
  (`SetAttribute("type", "item")`, `SetAttribute("item", <name or
  itemLink>)`) - the same mechanism action bars use - with the client's own
  protected code performing the use when the button is physically clicked.
  This is still a one-click action from the player's perspective; it just
  means the "use" button in the panel can't be a plain `Button` +
  `OnClick` calling our Lua like the rest of this add-on's UI. Whenever
  which item is current changes, the fix is to update that button's
  secure attributes, not to call a function.

- Proximity: the crafted good's own use-validation enforces being at a
  campfire itself, but the panel should not rely on that alone - it
  should gate each profession button's visibility/enabled state on the
  same signal already driving the rest of this panel
  (`CS.Detection`'s at-fire boolean, spell ID `1229739`, the "Welcoming
  Campfire" aura - see [Campfire Detection](#campfire-detection-and-secret-value-safety)).
  No new aura or API needed; this is a reuse of existing infrastructure,
  not a new discovery.

**Confirmed (2026-10-02, via the player's own domain knowledge - not yet
in-client-tested): each profession has (at least) three reward tiers,
functionally different, not "the same good, upgraded":**

- **Tier 1** (skill 20, the set this capture originally tested): a
  placeable object that augments the sit-at-campfire buff for *anyone*
  who benefits from that fire, not just the player who placed it -
  matching this doc's original "for everyone who benefits from that
  fire" framing above. Engineering's tier-1 object is the one exception
  that isn't a passive buff-augmenter - it's interactable and spawns a
  vendor instead - but this needs no special handling from the add-on:
  the add-on's job ends at use/craft/request, same as any other tier-1
  good, and it's unconcerned with whatever happens after placement.
- **Tier 2 and tier 3** are strictly additive over tier 1: a placed tier
  2/3 object also counts as its tier-1 self for the shared buff, plus
  niche extra effects, at a higher crafting cost. Tier 2's real
  spell/item IDs were confirmed for 7 professions during this research
  pass (Cookie's Feast/Cooking, Fermenter/Alchemy, Anvil/Blacksmithing,
  Tanning Rack/Leatherworking, Spinning Wheel/Tailoring, Repair
  Bot/Engineering, Arcane Salvager/Enchanting - kept in
  `docs/research.txt` for reference), and tier 3 isn't datamined yet.
- **Scope decision**: given tiers 2/3 are strictly additive and more
  expensive to craft for only niche benefit, this add-on supports tier 1
  only. Tiers 2/3 are not part of this feature's scope - "one button per
  profession" stands as originally written, one tier-1 good per
  profession, not one per profession-tier.

**Confirmed (2026-10-02)**: the yell request message follows the
structure "I can place a/an &lt;item link&gt; at the campfire if someone
wants to provide &lt;list of missing materials&gt;," with the item link
and the missing-materials list both generated dynamically (the latter
from the reagent/bag-count comparison already resolved above).

**Profession coverage, complete**: Jewelcrafting and Inscription were
added in The Burning Crusade and Wrath of the Lich King respectively, so
neither exists in Forever - the 11 professions with confirmed tier-1
data (Fishing, Alchemy, Herbalism, Cooking, First Aid, Enchanting,
Leatherworking, Engineering, Blacksmithing, Tailoring, Mining, plus
Skinning/Camp Chair, confirmed) are the complete set, not a partial list
awaiting two more. See `docs/research.txt` for the full table.

No open questions remain from this research pass - the feature is fully
specified down to real item/spell IDs, the API calls needed for each
step, the secure-button requirement for item use, the proximity design,
and the yell message wording. What's left is implementation (see
tasks.md's checklist), not further discovery.

## Milestones

1. Scaffold the repository: the TOC, empty modules, the .pkgmeta file, and the lint and release workflow, including wow-secret-lint confirmed to scan a TOC that lists only 16001.
2. Data.lua: the DefaultTree and the string tables.
3. Tree.lua: tree operations and migration, with unit tests.
4. Send.lua: slash parsing and %t handling, with unit tests.
5. Detection.lua: event-driven detection and its secret-value guards.
6. In-client verification: a self-test command that reports each client assumption (the campfire aura's spell ID, aura reads under secrecy, unknown-event registration, ReloadUI, %t through SendChatMessage, the hardware-event requirement, the addon compartment, C_Secrets, and the client's emote command globals), and a command that simulates campfire state. Test detection with the forced-restriction console variables.
7. UI.lua: the campfire panel, auto-open/auto-close, and the %t disabling.
8. Options.lua: the phrase tree editor with drag and drop, the popup dialog, and the two defaults buttons.
9. Launcher.lua: the addon compartment click handler declared in the TOC.
10. Package a first build through the tag-triggered release flow and distribute it for player feedback.

## Sources

- [Warcraft Wiki: It's Secret](https://warcraft.wiki.gg/wiki/Secret_Values), last edited September 23, 2026
- [forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit), a day-one snapshot from September 17, 2026 measured on the live client; its saved-variables finding is out of date and is not used here
- [RGX-Framework: Auras](https://github.com/RGXMods/RGX-Framework/wiki/Auras/94d9b6f03c333f1f4770e67ee60ba6162710d556), edited August 14, 2026; the framework's retail TOC is Interface 120100 and its latest release is v2.7.4
- [wow-secret-lint](https://github.com/Booyaka101/wow-secret-lint), API snapshot of patch 12.1.5 (build 69594), with a corpus pass dated September 7, 2026
- [psykzz/wow-template](https://github.com/psykzz/wow-template), TOC Interface 16001, README current as of September 2026
- [psykzz/wow-quickbuyout releases](https://github.com/psykzz/wow-quickbuyout/releases), TOC Interface 16001, 50504, 120100; v0.0.3 on September 28, 2026
