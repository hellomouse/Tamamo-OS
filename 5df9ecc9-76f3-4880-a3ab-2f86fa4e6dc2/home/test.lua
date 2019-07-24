local screen = require("screen")
local log = require("component").ocemu.log

local times = 160 * 50
local s = os.clock()
local x = {1}
local y

for i = 1, times do
    y = x[1]
end
log(os.clock() - s)

s = os.clock()
for i = 1, times do
    y = 1
end
log(os.clock() - s)

