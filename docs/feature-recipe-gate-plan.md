# Session Brief: Campfire Feature Buttons Gated on Learned Recipes

Written 2026-11-12 to start a fresh working session on this topic. It is
self-contained: the decisions below were made by the project owner and
shouldn't be re-asked. Out of scope: the first-run tutorial, which has its
own brief, [tutorial-plan.md](tutorial-plan.md).

## Start here

1. Read [AGENTS.md](../AGENTS.md) (Lua 5.1, no-globals, secret-value
   rules, test commands), then definition.md's "Future Scope (v2):
   Profession Campfire Enhancements" section, which describes how the
   feature buttons work today.
2. Run `git status`. On 2026-11-12 the tree had uncommitted work in UI.lua,
   Options.lua, Professions.lua, Data.lua and docs. Don't assume a clean
   tree, and don't fold unrelated changes into this work.
3. Run the full check suite (AGENTS.md, "Test, secret-value lint and
   release commands") to get a green baseline.
4. Most of this work starts with in-client probes. Run them with the
   `observation-ledger` skill and keep every proposed `/run` or `/dump`
   under 255 characters. For any craft test, a cast bar starting counts as
   success.
5. When approved, add the checklist at the end to [tasks.md](tasks.md)
   under the Profession Campfire Enhancements milestone.

## Domain facts (project owner, 2026-11-12)

- **Skill 20 doesn't grant a campfire feature recipe.** The recipe still
  has to be learned from a trainer or a quest. Skill 20 is only the
  requirement to learn it.
- **First Aid on Forever is different from retail's** and may have skill
  line ID **129**. This hasn't been confirmed in-client yet.

## Decisions (project owner, 2026-11-12)

| Question | Decision |
| --- | --- |
| Gate | A feature button is fully active only when the character **has learned the feature's recipe**. If that can't be detected, fall back to the profession being at **skill 20 or higher**. |
| Not learned | **Grayed, not hidden.** |

## The problem

`CS.Professions.EvaluateFeature` (Professions.lua) gates each button on
`C_TradeSkillUI.IsRecipeProfessionLearned(recipeSpellId)`. That's true
for any character who has the profession at all. So a character below
skill 20, or at 20+ who hasn't been to the trainer, gets an active Craft
or Request button for a recipe they can't make.

## Target behavior

| Character | Button |
| --- | --- |
| Doesn't have the profession | Hidden (unchanged) |
| Has the profession, hasn't learned the recipe, item in bags | Use (placing doesn't need the recipe; confirmed in-client 2026-11-12) |
| Has the profession, hasn't learned the recipe, no item | **Shown, grayed.** Tooltip status says it isn't learned yet. Clicking does nothing. |
| Has learned the recipe | Use / Craft / Request as today, including the existing cooldown state |

With the skill-20 fallback (only if no recipe-known signal works), "hasn't
learned" becomes "below skill 20". A 20+ character who hasn't learned
the recipe would then show as active, which is a known limitation of the
fallback.

### Grayed must not look like the cooldown state

The panel already uses gray for "on cooldown": the glow turns
poor-quality gray (`#9D9D9D`, `professionGlowColor` in UI.lua) and the
tooltip says "On cooldown". A not-learned button needs to read
differently. Recommendation, to confirm in-client:

- the icon desaturated (`SetDesaturated(true)`), with the same gray glow
  or no glow;
- tooltip status: "Not learned yet - visit your profession trainer" (new
  `feature_status_unlearned` string in `CS.Data.L`, matching the existing
  `feature_status_*` keys);
- no cooldown sweep.

Earlier button-appearance choices were made in-client
(docs/profession-button-appearance-findings.md). Settle this one the same
way, but as a visual choice it doesn't go in the observation ledger.

### Secure-button rules still apply

The buttons are `SecureActionButtonTemplate`-based. Only the "use" action
sets the `type`/`item` attributes; craft and request clear them and run
from `PreClick`. A not-learned button clears `type` like craft/request do,
and `PreClick` treats the new state as a no-op. All attribute and
visibility changes already go through `layoutProfessionBlock`'s combat
deferral (`queueCombatFlush`). Keep it that way.

## Correcting an earlier finding

docs/research.txt, Round 2, dumped `GetRecipeInfo(1229745)` (Fish Bowl)
on a character with Fishing at 20+, got `learned = false`, and concluded
that `learned` "tracks something else." That assumed skill 20 grants the
recipe, which it doesn't. The likelier reading is that the character
simply hadn't learned Fish Bowl from a trainer, so `learned` was reporting
correctly and **is the leading candidate for the gate**.

The same mistaken reading appears in three docs. Correct them once probe
G1 confirms the new reading:

- `docs/research.txt`, Round 2 result A: annotate in place and keep the
  original text.
- `docs/decision-log.md`, around line 600: add a new dated correction
  entry instead of rewriting the old one, since the log is a history.
- `docs/definition.md`, Future Scope, "Confirmed via in-client research":
  replace the "`learned` ... tracks something else" parenthetical and the
  `IsRecipeProfessionLearned` gate description.

## What's already known

- `GetRecipeInfo(id).craftable` is `true` even for a profession the
  character doesn't have. Not usable.
- `IsRecipeProfessionLearned(id)` correctly separates "has the
  profession" from "doesn't". Keep it as the hidden-vs-shown check.
- `GetProfessions()` / `GetProfessionInfo()` work and include skill level,
  but **don't list First Aid**, one of the 11 features.
- `C_TradeSkillUI.GetProfessionInfoByRecipeID` is in Forever's
  146-function `C_TradeSkillUI` list (research.txt Round 2) and has never
  been called. On retail it, and `GetProfessionInfoBySkillLineID`, return
  a profession's `skillLevel`.
- Profession data isn't reliable at `ADDON_LOADED` (decision-log.md,
  2026-10-05, WarmItemCache). The gate runs when the panel is built or
  refreshed, which is later, but probe G5 checks the timing anyway.
- IDs (research.txt and the `FEATURES` table in Professions.lua): Fish
  Bowl recipe `1229745`. First Aid Kit item `279968`, recipe `1230117`.

## In-client probes

**Setup:** for at least one profession, a character at skill 20+ who has
**not** learned that profession's campfire feature recipe and can reach
the trainer that teaches it. Also a character with the profession below
20, and one with First Aid.

| # | Probe | Decides |
| --- | --- | --- |
| G1 | On the 20+ character: `/dump C_TradeSkillUI.GetRecipeInfo(1229745).learned`. Expect `false`. Learn Fish Bowl from the trainer and dump again. Expect `true`. Do the pair once with and once without the profession window opened this session. | Whether `learned` is the recipe-known signal, and whether it needs the window opened first. This is the main test. |
| G2 | The same before/after pair with `/dump IsPlayerSpell and IsPlayerSpell(1229745)` | A second recipe-known signal, in case `learned` needs the window opened first. |
| G3 | First Aid, the same before/after pair if a First Aid character can learn the kit: `/dump C_TradeSkillUI.GetRecipeInfo(1230117).learned` | Whether the recipe-known rule works for Forever's First Aid. If it does, no skill lookup is needed at all. |
| G4 | Fallback only, if G1-G3 don't give a clean answer: `/dump C_TradeSkillUI.GetProfessionInfoBySkillLineID(129)`, then `/dump C_TradeSkillUI.GetProfessionInfoByRecipeID(1230117)`, and the second again with `1229745` | Whether `skillLevel` is readable for the fallback, and whether 129 is First Aid's skill line. |
| G5 | Repeat whichever probe won, within the first seconds after login and after a `/reload`. | Whether the gate needs a re-check event when profession data arrives late. |

**Decision rule:** if G1 (or G2) flips from `false` to `true` across the
trainer visit, and G3 does the same for First Aid, use the recipe-known
signal for all 11 features and drop the skill-20 fallback. Otherwise use
the fallback with whichever G4 call returns `skillLevel`, with 129 for
First Aid if confirmed. If First Aid can't be read by any of these, ask
the project owner before shipping, rather than leaving it on the current
gate.

## Code change

- **Professions.lua.** `EvaluateFeature` gains an injected
  `isFeatureKnown(recipeSpellId)` option, defaulting to the winning
  probe. `IsRecipeProfessionLearned` stays as the hidden/shown check.
  `isFeatureKnown` decides between the new result
  `{ visible = true, action = "unlearned", recipeSpellId, icon, entry }`
  and the existing use/craft/request results. If the fallback is used,
  the threshold is a named constant (`FEATURE_SKILL_REQUIRED = 20`), and
  First Aid's skill line, if it's needed, is a named constant beside
  `FEATURES` rather than a magic number.
- **UI.lua.** The `unlearned` state in `featureState`,
  `professionGlowColor`, the tooltip, and `applyProfessionButtonState`
  (clears `type`, desaturates the icon, no cooldown), and `PreClick`
  ignores it. Every other state un-desaturates the icon.
- **Data.lua.** `feature_status_unlearned`.
- **Re-evaluation.** If G5 shows profession data arriving late, re-run
  the panel's profession refresh on the event that signals it (likely
  `SKILL_LINES_CHANGED` or `TRADE_SKILL_LIST_UPDATE`; confirm in-client).
  Also re-run it when a recipe is learned, so the button turns active
  without a `/reload`. Register any new event inside a `pcall`, since
  Forever throws on unknown events (definition.md, Known Deviations).
- **Tests (`tests/professions_spec.lua`).** No profession: hidden. Has
  profession, recipe not learned (including at skill 20+), no item:
  `unlearned`. Recipe not learned but item in bags: `use`. Learned:
  use/craft/request as before. Unreadable data: `unlearned`, not
  active. First Aid goes through the same path.

### Item in bags, recipe not learned (decided 2026-11-12)

Campfire feature items can be held without knowing the recipe. The
project owner confirmed in-client that **placing the item doesn't need
the recipe**. So the order of checks is:

1. No profession: hidden.
2. Item in bags: **Use**, whether or not the recipe is learned.
3. Recipe learned: Craft or Request as today.
4. Otherwise: grayed `unlearned`.

## Open questions for the project owner

1. **Grayed look.** The recommendation above (desaturated icon, gray or
   no glow, "Not learned yet" tooltip) is a default to confirm in-client.

## Checklist (to move into tasks.md)

- [ ] Probes G1-G5 run and recorded in decision-log.md.
- [ ] Buttons are hidden without the profession, grayed ("unlearned") with the profession but without the recipe, and active once learned. Skill 20+ is used only if no recipe-known signal works. First Aid included.
- [ ] The unlearned look is distinct from the cooldown gray, does nothing when clicked, and uses no secure attributes. All changes go through the existing combat deferral.
- [ ] A button turns active after the recipe is learned without a `/reload`.
- [ ] Unit tests for each case; luac, luacheck, tests and wow-secret-lint pass.
- [ ] The "`learned` tracks something else" finding is corrected: research.txt annotated, a correction entry in decision-log.md, and definition.md's Future Scope section updated.
