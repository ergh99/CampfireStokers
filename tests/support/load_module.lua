-- Loads one addon Lua file the way the WoW client does: as a chunk called
-- with (addonName, sharedTable), instead of a plain require/dofile. Every
-- module under test should be loaded through this so it sees the same
-- vararg contract it gets in-game.
local function loadModule(path, addonName, sharedTable)
    local chunk, err = loadfile(path)
    if not chunk then
        error(err, 0)
    end
    return chunk(addonName, sharedTable)
end

return loadModule
