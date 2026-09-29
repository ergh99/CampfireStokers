local loadModule = require("support.load_module")

require("support.wow_stub").install()

local MODULES = {
    "Data", "Tree", "Send", "Detection", "UI", "Options", "Launcher", "Core",
}

local tests = {}

for _, moduleName in ipairs(MODULES) do
    tests["loads " .. moduleName .. ".lua without error"] = function()
        local CS = {}
        loadModule(moduleName .. ".lua", "CampfireStokers", CS)
    end
end

tests["Launcher.lua defines the addon compartment click handler"] = function()
    loadModule("Launcher.lua", "CampfireStokers", {})
    assert(
        type(CampfireStokers_OnAddonCompartmentClick) == "function",
        "CampfireStokers_OnAddonCompartmentClick should be a global function"
    )
end

return tests
