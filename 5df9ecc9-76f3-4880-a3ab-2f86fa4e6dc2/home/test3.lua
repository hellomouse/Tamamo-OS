local gui = require("gui")
local event = require("event")


local container = gui.createContainer(1, 1, 70, 50)

local function doShit(eventID, ...)
    if eventID then -- can be nil if no event was pulled for some time
        container:eventHandler(eventID, ...) -- call the appropriate event handler with all remaining arguments
    end
end
--  local thread = require("thread")
--  local t = thread.create(function()
--    while true do
--      doShit(event.pull())
--    end
-- end)


local a = gui.createFramedButton(50, 20, 16, 3, "BUTTON", 0x777777,0x777777, 0xAAAAAA, 0xFFFFFF, 1)
a.switchMode = true
container:addChild(  a)

local b = gui.createButton(50, 25, 16, 3, "BUTTON", 0x777777,0xFFFFFF, 0xAAAAAA, 0xFFFFFF, 1)


--container:addChild(b)

for i = 1, 9 do
    local c = gui.createLabel(10, 20, "hello world!", 0xFF0000, 50, 20, i)
    container:addChild(c)
end 


container:draw()

while true do
     doShit(event.pull())
   end