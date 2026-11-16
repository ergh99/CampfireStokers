# AGENTS.md

Guidance for anyone (human or AI) making changes to Campfire Stokers. See
[docs/definition.md](docs/definition.md) for the full design,
[docs/tasks.md](docs/tasks.md) for the build-order task list this repo is
implementing, and [docs/decision-log.md](docs/decision-log.md) for findings
from in-client verification (T6 onward) and the decisions that followed.

## Lua 5.1 and no-globals rules

- The client runs Lua 5.1. Write code that is valid under `luac5.1 -p`; do
  not use 5.2+ syntax (goto labels are fine, bitwise operators and integer
  division are not).
- Every module file is loaded by the client with `local CS = select(2, ...)`
  (or `local ADDON_NAME, CS = ...` when the addon name is actually used),
  attaching its public surface to the shared `CS` table (e.g. `CS.Tree`).
  The client passes the *same* `CS` table to every file in the TOC's load
  order, so this is the only inter-module namespace: don't invent a second
  one.
- Only the globals declared in `.luacheckrc`'s `globals` list may be defined,
  and each one is there because a specific WoW API convention requires a
  real global of that exact name: `CampfireStokersDB` (the TOC's
  `SavedVariables` table), `CampfireStokers_OnAddonCompartmentClick` (the
  TOC's `AddonCompartmentFunc` handler), and `SLASH_CAMPFIRESTOKERS1` /
  `SLASH_CAMPFIRESTOKERS2` (the client's slash-command registration, which
  only recognizes globals named exactly `SLASH_<key><N>`). Adding any other
  global is a lint failure, not a judgment call; if a new one is genuinely
  required by a WoW API convention, add it to this list with the same kind
  of comment.
- **The WoW client does not validate global names at load time.** Calling a
  misspelled API function is invisible until someone happens to trigger that
  code path in-game. Luacheck is what catches it, at author time, and it can
  only do that for globals it's told about:
  - `read_globals` in `.luacheckrc` lists every WoW API global this addon
    reads (functions, tables, constants). Anything not listed there is
    flagged as an undefined global and fails CI.
  - **Adding a WoW API global**: when a module starts calling a new WoW API
    (e.g. `CreateFrame`, `C_Secrets.ShouldAurasBeSecret`,
    `C_UnitAuras.GetPlayerAuraBySpellID`, `DoEmote`, `SendChatMessage`), add
    its name to `read_globals` in the same commit. Add only what you use;
    don't pre-populate the list with the whole WoW API surface.
  - This list failing to include something never breaks the game (the client
    doesn't consult it) — it only breaks `luacheck .`, which is exactly the
    point: it's the one gate standing in for the compiler error a normal Lua
    project would get for a typo'd identifier.

## Debug flag

`CS.DEBUG` (defined at the top of `Data.lua`) turns on `CS.Debug(...)`
output in chat. Set it to `true` locally while developing, but **before
every commit, set `CS.DEBUG = false`**. It must never be committed as
anything else. Agents: check this as part of preparing any commit, and
reset it yourself if it's `true`. `tests/data_spec.lua` fails if it's not
`false`, so a slip also fails CI. It lives on the shared `CS` table, not as
a real Lua global, per the no-globals rules above.

## Secret-value rules

Since patch 12.0, aura (and related) data can be a *secret value*: unreadable
and untaint-able by addon code whenever addon restrictions are active
(combat, boss encounters, Mythic+, PvP). See [docs/definition.md](docs/definition.md#campfire-detection-and-secret-value-safety)
and the `wow-secret-values` skill for the full checklist. The rules that
matter for every change touching aura data:

1. **Ask before you read.** Call `C_Secrets.ShouldAurasBeSecret()` first. If
   it returns `true`, skip the read entirely and treat the player as not at
   a campfire. This is not an optimization — reads have been observed to
   throw outright while secrecy is active.
2. **Read one aura, by spell ID only.** Use
   `C_UnitAuras.GetPlayerAuraBySpellID` for the player's own campfire aura.
   Never call an aura API by index, slot, or instance ID.
3. **Check readability before touching the result.** `canaccessvalue(result)`
   must be `true` before any field access or branch on that result. Treat an
   unreadable or `nil` result as "no campfire aura."
4. **A `pcall` is not a guard.** Wrapping a read in `pcall` does not undo
   taint and does not substitute for step 1.
5. **Only booleans reach SavedVariables.** Aura data itself is never
   persisted, directly or indirectly — `CampfireStokersDB` may only ever
   store the derived at-fire/not-at-fire boolean and similar plain values.

`wow-secret-lint` runs in strict mode in CI (see below) and fails the build
on violations of rules 2-5 that it can detect statically. Rule 1 (call order)
and rule 4 are checked by the `wow-secret-values` skill and code review,
since they depend on control flow the linter can't fully see.

## TOC gate and two-month recency rule

Before treating any other WoW addon repository as a reference (for code,
patterns, or CI setup), it must pass both checks, in this order:

1. **TOC gate**: its TOC's `## Interface:` line must include `16001` (the
   current Forever build, confirmed in-client with `GetBuildInfo()`) or a
   number starting with `12` (the surrounding retail API generation). A repo
   whose TOC only lists older interface numbers is out of date for this
   project and is rejected here, full stop.
2. **Recency**: it must have shipped a release or commit within the past two
   months of the date you're checking.

The `toc-gate` skill automates this against a candidate repository. Do not
copy code from a reference add-on that fails either check, even if the code
looks otherwise reasonable — Forever's API deviates from retail in ways that
are only caught by testing on the live client (see docs/definition.md's
"Known deviations from retail").

## Test, secret-value lint and release commands

The Lua 5.1 binary name depends entirely on how it got installed, and
varies by environment: CI (`leafo/gh-actions-lua`, which builds from
source) installs plain `lua`/`luac`; Debian/Ubuntu's `apt install lua5.1`
names them `lua5.1`/`luac5.1`; Windows via scoop names them `lua51`/`luac51`.
Confirmed the hard way: `ci.yml` originally assumed the apt names and the
first real CI run failed outright with "command not found" (see
docs/decision-log.md). `ci.yml` is the authoritative, enforced version;
the commands below use the apt-style names as the illustrative default -
substitute whatever `which lua5.1 lua51 lua luac5.1 luac51 luac` finds on
your own machine.

```sh
# Syntax check every Lua file
find . -name '*.lua' -not -path './lua_modules/*' -print0 | xargs -0 -n1 luac5.1 -p

# Static analysis: undefined/misspelled globals, unused locals, etc.
luacheck .

# Pure-Lua unit tests (Send.lua, Tree.lua, migration) against a mocked WoW
# API, run from the repo root
lua5.1 tests/run_tests.lua

# Secret-value violations, in strict mode (elevates SecretReturns-tier
# warnings to build-failing errors)
npx wow-secret-lint . --strict
```

`.vscode/settings.json` points the Lua language server at the `ketho.wow-api`
annotations and disables the standard-library globals (`io`, `os`,
`package`, `require`, etc.) that don't exist in the client's sandbox, so a
typo'd WoW API name gets a red squiggle while editing, not just at CI time.
`tests/.luarc.json` re-enables those for the `tests/` subtree specifically,
since that code runs under a real Lua interpreter with the full standard
library, not inside the client.

All four run in CI on every push (`.github/workflows/ci.yml`). The
`wow-secret-lint` step is pinned to a commit SHA, not a floating tag, so a
new release of the linter can't silently change what CI enforces.

Detection.lua's secret-value guard (`EvaluateState`) and its event
registration (`CreateEventFrame`) are headless-tested too, with
`C_Secrets`/`C_UnitAuras`/`canaccessvalue` and the frame itself passed in as
mocks (see `tests/detection_spec.lua`) rather than assumed missing — only
the real client behavior behind those mocks (does `GetPlayerAuraBySpellID`
actually behave this way, does registering an unknown event actually throw)
is unverified until T6. The same goes for Core.lua's ADDON_LOADED wiring
(`tests/core_spec.lua`, with `CS.UI` stubbed rather than loaded for real)
and Launcher.lua's command routing and selftest checks
(`tests/launcher_spec.lua`, using `tests/support/wow_stub.lua`'s minimal
`CreateFrame`/`SlashCmdList`). What stays manual, in-client only, is
anything that needs a real frame tree - UI.lua's actual panel construction
(`CreatePanel`) and Options.lua's editor (`CreateCanvas`) - since mocking
backdrops, font strings, and button templates well enough to exercise those
for real isn't worth it; UI.lua's auto-open/auto-close timing (a real
C_Timer.NewTimer countdown) falls in the same manual-only bucket for the
same reason. `tests/options_spec.lua`'s `FindDropIndex` drag-reorder math
is the one piece of either module's logic simple and pure enough to be
headless-tested. Tutorial.lua follows the same split: its due/seen state
and step lists are headless-tested (`tests/tutorial_spec.lua`), while the
welcome card, the callout frame and its event wiring are in-client only. WoWUnit is used for that in-client exploratory/self-test
work (see the self-test and
simulate-campfire subcommands added in the "in-client verification"
milestone). If you add a WoWUnit test group, list it in
`## OptionalDeps: WoWUnit` in the TOC, guard its registration on WoWUnit
being loaded, and don't let its presence change any production code path.

Releasing: push an annotated tag matching `v*` (e.g. `v0.1.0`).
`.github/workflows/release.yml` runs the BigWigs packager, which builds a
zip named `CampfireStokers` (per `.pkgmeta`'s `package-as`) with `@project-version@`
in the TOC substituted for the tag, attaches it to a GitHub Release, and
uploads the same zip to CurseForge. Nothing under `docs/`, `tests/`,
`.github/`, or `AGENTS.md` ships in the zip.

- **Release type comes from the tag name**: a tag containing `alpha` or
  `beta` (e.g. `v1.2.0-beta1`) is uploaded to CurseForge as that type;
  anything else is a full release.
- **CurseForge configuration lives in the GitHub repo settings, not in
  code**: the secret `CF_API_KEY` (the CurseForge upload API token) and the
  variable `CF_PROJECT_ID` (the numeric project ID, public). The workflow's
  first step fails the run if either is missing or the ID isn't numeric, so
  a tag can never silently ship to GitHub only.
- **The API token is a secret value**: never commit it, paste it into a
  TOC field, a workflow file, a `/run` command or a chat log, or pass it on
  a command line. It only reaches the workflow as an env var, which
  GitHub masks in logs. If it leaks, revoke it at
  https://wow.curseforge.com/account/api-tokens and replace the secret.
- **Game version**: the packager maps the TOC's `## Interface: 16001` to
  CurseForge game version `1.60.1` (seen in the v1.1.0 release log). The
  packager uploads to CurseForge before GitHub, so if a future Interface
  bump isn't recognized the run fails at the CurseForge upload; check both
  sites for a partial release before re-tagging.

**Resolved item, then fixed upstream**: `wow-secret-lint`'s TOC-based
discovery used to skip this addon (16001 was misread as Classic, not
retail), which is why `ci.yml`'s `path` input used to list the module
files directly instead of `.`. Fixed upstream in v1.8.1
([Booyaka101/wow-secret-lint#14](https://github.com/Booyaka101/wow-secret-lint/issues/14)):
16001 is now correctly recognized as a Forever/retail interface number.
Confirmed locally with v1.9.0 (`npx wow-secret-lint@1.9.0 . --strict
--format json`): `flavour: "forever"`, `filesScanned: 8` (the real
module count), 0 findings - `ci.yml`'s `path` is back to `.`, which is
better than the old explicit list since it now tracks the TOC's file
list automatically; a new module file added to the TOC's load order no
longer needs a separate manual update here.
