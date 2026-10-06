# Profession button appearance/visibility findings ledger (started 2026-10-05)

Append-only observation ledger, kept per the `observation-ledger` skill:
each round is written as soon as its result is reported, before the next
test is designed. Observed fields are verbatim quotes of the report.

## Reported problem (verbatim, 2026-10-05)

"the docs contain mention of the profession buttons indicating what will
happen when they are pressed (colored border i believe) but this is not
occurring.  the profession buttons are either shown or not shown (which is
not correct, they should be shown whenever the panel is visible and the
panel should not be visible unless the profession buttons are ready) but
they never change appearance in anyway/"

Related earlier report: Round 17 of
`docs/craft-profession-switch-findings.md` (profession buttons hide when
the campfire aura drops while the panel stays up).

## Desired behavior, from the user's answers (2026-10-05)

- Profession buttons shown whenever the panel is visible - answer to
  "does that include a panel opened manually while NOT at a campfire?":
  "Always".
- Meaning of "ready" - answer: "Evaluated first" (when auto-opening,
  evaluate the buttons before showing the panel, so it never appears
  without them or with them popping in later).
- Approach - answer: "Diagnose first".

## Code at ledger start (from the repo, not observed in-client)

- `UI.lua` `createProfessionButton`: `SecureActionButtonTemplate,
  BackdropTemplate`, 64x64, backdrop `edgeFile =
  "Interface/Tooltips/UI-Tooltip-Border"`, `edgeSize = 10`; icon texture
  on the `ARTWORK` layer, inset 2px on every side.
- `applyProfessionButtonState`: `SetBackdropBorderColor` green (use),
  blue (craft), orange (request).
- `evaluateGoodSafely`: every button treated as hidden while
  `CS.Detection.atFire` is false.
- Hypothesis to test (not observed): the icon covers most of the 10px
  border, so the color isn't visible.

## Rounds

### Round 1: is the border color applied but hidden?
Starting state: at the campfire, panel open, Mining button showing, not
  clicked.
Action taken (verbatim): `/run local b=CampfireStokersProfessionButtonmining print("action:", b.pendingAction, "border:", b:GetBackdropBorderColor()) b.icon:SetAlpha(0.3) b:SetBackdropBorderColor(1,0,0)`
Observed result (verbatim):
  - Chat: "action: craft border 0.4... 0.6... 1 1"
  - After: "faded icon, initially red border, changed to bluish gray border without any user interaction, slightly too thin to be useful"
  - Before: "before the command it was normal saturation with a barely visible bluish gray border"
Interpretation (not observed - reasoning only): the printed values match
  the craft color `0.4, 0.6, 1` set by `applyProfessionButtonState`, so
  the color is being applied. The switch back from red without
  interaction fits a panel refresh re-applying the craft color. The
  border that shows is only a thin strip, and the tooltip border art
  tints to a muted bluish gray rather than a clear blue.

### Round 2: thicker solid border, icon inset 4px (one /run)
Action taken (verbatim): `/run local b=CampfireStokersProfessionButtonmining b.icon:SetAlpha(1) b.icon:ClearAllPoints() b.icon:SetPoint("TOPLEFT",4,-4) b.icon:SetPoint("BOTTOMRIGHT",-4,4) b:SetBackdrop({edgeFile="Interface/Buttons/WHITE8X8",edgeSize=4}) b:SetBackdropBorderColor(0.4,0.6,1)`
Observed result (verbatim): "message character overflow"
Interpretation (not observed - reasoning only): the command is about
  266 characters, over the chat box's 255-character limit, so it never
  ran. Not a result about the border; retried as Round 3 split into two
  commands.

### Round 3: thicker solid border, icon inset 4px (two /run commands)
Starting state: at the campfire, panel open, Mining button showing.
Action taken (verbatim):
  1. `/run local i=CampfireStokersProfessionButtonmining.icon i:SetAlpha(1) i:ClearAllPoints() i:SetPoint("TOPLEFT",4,-4) i:SetPoint("BOTTOMRIGHT",-4,4)`
  2. `/run local b=CampfireStokersProfessionButtonmining b:SetBackdrop({edgeFile="Interface/Buttons/WHITE8X8",edgeSize=4}) b:SetBackdropBorderColor(0.4,0.6,1)`
  3. Watch at least 10 seconds.
Observed result (verbatim):
  - Border: "a border was added after the second command.  it is a visually clear light blue.  it has hard corners and no styling however, so while functional, it isn't visually appealing"
  - After refresh: "it didn't not appear to revert or change appearance after refreshing"
  - Icon: "the icon does still appear without distortion"
  - Errors: "no error text"
Interpretation (not observed - reasoning only): "didn't not appear to
  revert" is read as "did not appear to revert" - consistent with a
  refresh only re-applying the same blue via SetBackdropBorderColor.
  Ask if that reading is wrong.

### Round 4: backdrop removed, Interface/Common/WhiteIconFrame overlay tinted blue
Starting state: at the campfire, panel open, Mining button showing.
Action taken (verbatim):
  1. `/run local b=CampfireStokersProfessionButtonmining b:SetBackdrop(nil) b.icon:ClearAllPoints() b.icon:SetAllPoints()`
  2. `/run local b=CampfireStokersProfessionButtonmining local t=b:CreateTexture(nil,"OVERLAY") t:SetAllPoints(b.icon) t:SetTexture("Interface/Common/WhiteIconFrame") t:SetVertexColor(0.4,0.6,1)`
  3. Watch at least 10 seconds.
Observed result (verbatim):
  - Look: "it reads sufficiently clearly and is more appealing but it would be better if it could be thicker"
  - After refresh: "refresh didn't seem to change anything or produce error text"
Interpretation (not observed - reasoning only): calling
  SetBackdropBorderColor on refresh with no backdrop set produced no
  visible error.

### Round 5: second WhiteIconFrame overlay inset inward to thicken the frame
Starting state: continuing from Round 4 (backdrop removed, one
  WhiteIconFrame overlay tinted blue).
Action taken (verbatim): `/run local b=CampfireStokersProfessionButtonmining local t=b:CreateTexture(nil,"OVERLAY") t:SetTexture("Interface/Common/WhiteIconFrame") t:SetVertexColor(0.4,0.6,1) t:SetPoint("TOPLEFT",3,-3) t:SetPoint("BOTTOMRIGHT",-3,3)`,
  then the same with 2 and then 1 in place of 3 (user's own follow-up
  tries; whether a `/reload` happened between tries was not reported, so
  later tries may have stacked on earlier overlays).
Observed result (verbatim): "seam was visible, tried 2, seam still visible, tried 1 seam is barely visible but enough to create dissonance."

### Round 6: tooltip border at edgeSize 16, icon inset 5px
Starting state: `/reload`; at the campfire, panel open, Mining button
  showing.
Action taken (verbatim):
  1. `/run local i=CampfireStokersProfessionButtonmining.icon i:ClearAllPoints() i:SetPoint("TOPLEFT",5,-5) i:SetPoint("BOTTOMRIGHT",-5,5)`
  2. `/run local b=CampfireStokersProfessionButtonmining b:SetBackdrop({edgeFile="Interface/Tooltips/UI-Tooltip-Border",edgeSize=16}) b:SetBackdropBorderColor(0.4,0.6,1)`
  3. Watch at least 10 seconds.
Observed result (verbatim):
  - Look: "not thick enough, less visually clear than R4"
  - After refresh: "no other changes or error"

### Round 7: Interface/Buttons/UI-ActionButton-Border glow, ADD blend, tinted blue, 110x110
Starting state: `/reload`; at the campfire, panel open, Mining button
  showing.
Action taken (verbatim):
  1. `/run local b=CampfireStokersProfessionButtonmining b:SetBackdrop(nil) b.icon:ClearAllPoints() b.icon:SetAllPoints()`
  2. `/run local b=CampfireStokersProfessionButtonmining local g=b:CreateTexture(nil,"OVERLAY") g:SetTexture("Interface/Buttons/UI-ActionButton-Border") g:SetBlendMode("ADD") g:SetVertexColor(0.4,0.6,1) g:SetSize(110,110) g:SetPoint("CENTER")`
  3. Watch at least 10 seconds.
Observed result (verbatim): "this style is a definite improvement and if the blue can be deepened/darkened it would probably be an easy choice"
  Screenshot supplied with the report: `docs/images/profession-buttons-round7.png`.
Interpretation (not observed - reasoning only): my reading of the
  screenshot - four buttons in a row; the first three keep the original
  thin tooltip border (orange-ish on the first two, green on the third);
  the fourth (Mining) shows the blue glow hugging its edge with no
  visible spill onto the neighbor. Spill, size and refresh behavior
  were not separately reported.

### Round 8: deepening the glow's blue - saturated ADD vs BLEND mode
Starting state: `/reload`; at the campfire, panel open, Mining button
  showing; Round 7 setup re-run, with the glow saved as `b.g`.
Action taken (verbatim):
  1. `/run local b=CampfireStokersProfessionButtonmining b:SetBackdrop(nil) b.icon:ClearAllPoints() b.icon:SetAllPoints()`
  2. `/run local b=CampfireStokersProfessionButtonmining local g=b:CreateTexture(nil,"OVERLAY") b.g=g g:SetTexture("Interface/Buttons/UI-ActionButton-Border") g:SetBlendMode("ADD") g:SetVertexColor(0.4,0.6,1) g:SetSize(110,110) g:SetPoint("CENTER")`
  3. A: `/run CampfireStokersProfessionButtonmining.g:SetVertexColor(0.1,0.3,1)`
  4. B: `/run CampfireStokersProfessionButtonmining.g:SetBlendMode("BLEND")`
  5. C (optional): `/run CampfireStokersProfessionButtonmining.g:SetVertexColor(0.05,0.15,0.7)`
Observed result (verbatim): "BLEND did not work at all and obscured the icon.  option A's ADD looks much better"
  Screenshot supplied with the report: `docs/images/profession-buttons-round8.png`
  (which step it shows was not stated). Whether C was run: not reported.
User clarification after Round 8 (verbatim): "the screenshot is the ADD command, both BLEND commands obscured the icon"

### Round 9: use (green) and request (orange) colors in the ADD glow style
Starting state: Mining button with the Round 8 glow (`b.g`).
Action taken (verbatim):
  1. `/run local g=CampfireStokersProfessionButtonmining.g g:SetBlendMode("ADD") g:SetVertexColor(0.1,0.9,0.1)`
  2. `/run CampfireStokersProfessionButtonmining.g:SetVertexColor(1,0.45,0)`
  3. (optional) `/run CampfireStokersProfessionButtonmining.g:SetVertexColor(0.1,0.3,1)`
Observed result (verbatim): "these options are great.  if the orange can be redder (to signify a relationship to yell messages which are red) that would be ideal"

### Round 10: redder request color
Starting state: Mining button with the Round 8 glow (`b.g`).
Action taken (verbatim):
  1. `/run local g=CampfireStokersProfessionButtonmining.g g:SetBlendMode("ADD") g:SetVertexColor(1,0.2,0)`
  2. `/run CampfireStokersProfessionButtonmining.g:SetVertexColor(1,0.25,0.25)`
  3. `/run CampfireStokersProfessionButtonmining.g:SetVertexColor(1,0.05,0.05)`
Observed result (verbatim): "use option 1"

### Round 11: visibility with the code changes (no atFire gate; refresh before manual show)
Starting state: `/reload` with the updated `UI.lua` (glow style from
  Rounds 7-10, `evaluateGoodSafely` no longer checks `atFire`,
  `CS.UI.Show` refreshes before showing).
Action taken (verbatim): 1. go to a campfire and `/sit` (auto-open);
  2. stand up/move until the aura drops; 3. walk away and open the panel
  manually.
Observed result (verbatim): "button visibility was static in each scenario as desired"
  Glow colors in the shipped code (asked in step 3): not separately reported.

## Chosen appearance (decision, from Rounds 7-10)

`Interface/Buttons/UI-ActionButton-Border`, ADD blend, 110x110 centered
on the 64x64 button, no backdrop, icon filling the button. Colors:
craft `0.1, 0.3, 1` (Round 8 option A), use `0.1, 0.9, 0.1` (Round 9),
request `1, 0.2, 0` (Round 10 option 1).
