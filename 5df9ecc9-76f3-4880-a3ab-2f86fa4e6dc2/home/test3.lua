local gui = require("gui")
local event = require("event")
local image = require("image")

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


local e = gui.createImage(1, 3, image.loadHDG("test.hdg"))
--container:addChild(e)

local f = gui.createInput(3, 6, 30, 3, 0x333333, 0xFFFFFF, 0x555555, 0xFFFFFF, 1, 0x888888, "Placeholder")
container:addChild(f)


local g = gui.createLabel(10, 14, "", 0xFF0000, 50, 20, gui.ALIGN_TOP_LEFT)
container:addChild(g)

local h = gui.createInput(3, 10, 30, 3, 0x333333, 0xFFFFFF, 0x555555, 0xFFFFFF, 1, 0x888888, "Password Field!", "*")
h.onInput = function(input)
    g.text = h.value
    g.draw(g)
end
container:addChild(h)

local k = gui.createInput(3, 18, 30, 3, 0x333333, 0xFFFFFF, 0x555555, 0xFFFFFF, 1, 0x888888, "History")
k.history = true
container:addChild(k)

local l = gui.createProgressIndicator(3, 22, 0x333333, 0xFF0000, 0xFFAA00)
container:addChild(l)



function is_valid_date(str)
    local sub = string.sub
    local num = "0123456789"
    local s

    for i = 1, #str do
        s = sub(str, i, i)
        if i == 1 or i == 2 or i == 4 or i == 5 or i == 7 or i == 8 or i == 9 or i == 10 then
            if tonumber(s) == nil then return false end
        
        elseif s ~= "/" then return false
        end
    end
    return true
end

local j = gui.createInput(3, 14, 30, 3, 0x333333, 0xFFFFFF, 0x555555, 0xFFFFFF, 1, 0x888888, "MM/DD/YYYY")
j.keepPlaceholder = true
j.validate = is_valid_date
container:addChild(j)

h.nextInput = j

local a = gui.createFramedButton(50, 20, 16, 3, "BUTTON with a really long name?", 0x777777,0x777777, 0xAAAAAA, 0xFFFFFF, 1)
a.switchMode = true
container:addChild(  a)

local b = gui.createAdaptiveButton(50, 25, "BUTTON", 0x777777,0xFFFFFF, 0xAAAAAA, 0xFFFFFF, 1)
container:addChild(b)

for i = 1, 9 do
    local c = gui.createLabel(10, 20, "hello world!", 0xFF0000, 50, 20, i)
    container:addChild(c)
end 


local p = gui.createPanel(30, 30, 40, 20, 0xFFFFFF, 1, 2)
p.addChild(gui.createInput(1, 1, 30, 3, 0x333333, 0xFFFFFF, 0x555555, 0xFFFFFF, 1, 0x888888, "MM/DD/YYYY"))
--container:addChild(p)


-- test 
local GUI = gui
local color = require("color")
local colorPickerContainer = GUI.createPanel(55, 8, 65, 25, 0x333333, 1, 1)
colorPickerContainer.overrideBound = true


container:addChild(GUI.createColorPicker(30, 15, 10, 20, "HI", 0x0))

local asd = gui.createTextBox(50, 40, "this is a test\ndoes this text wrap around long lines still or no",0xFFFFFF,  10)
container:addChild(asd)

container:addChild(gui.createSwitch(30, 40, 0x333333, 0xFF0000, 0xFFFFFF))

local bar = gui.createProgressBar(10, 45, 40, 0x333333, 0xFF0000, 0.5, true, 0xFFFFFF, "Hello ")
container:addChild(bar)
bar.setValue(0.2)

container:addChild(gui.createSlider(10, 47, 20, 0x333333, 0xFF0000, 0xFFFFFF, 0xFFFFFF, 10, 50, 30, true, true, 2, "BWBellairs "))

container:draw()



while true do
    doShit(event.pull())
end