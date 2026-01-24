-- "Corobo UTIL"
CUTIL = SMODS.current_mod

-- Load all the util files.
assert(SMODS.load_file("src/helpers.lua"))()
assert(SMODS.load_file("src/game.lua"))()
assert(SMODS.load_file("src/maths.lua"))()
assert(SMODS.load_file("src/events.lua"))()