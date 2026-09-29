-- Headless test runner for the pure-Lua modules (Send.lua, Tree.lua,
-- migration). Run from the repo root: lua5.1 tests/run_tests.lua
-- See AGENTS.md, "Test, lint and release commands".
package.path = "tests/?.lua;" .. package.path

local SPEC_FILES = {
    "core_smoke_spec",
    "data_spec",
    "tree_spec",
    "send_spec",
}

local total, failed = 0, 0

for _, specName in ipairs(SPEC_FILES) do
    local spec = require(specName)
    for testName, testFn in pairs(spec) do
        total = total + 1
        local ok, err = pcall(testFn)
        if ok then
            print(string.format("  ok    %s: %s", specName, testName))
        else
            failed = failed + 1
            print(string.format("  FAIL  %s: %s\n        %s", specName, testName, tostring(err)))
        end
    end
end

print(string.format("\n%d run, %d failed", total, failed))

os.exit(failed == 0 and 0 or 1)
