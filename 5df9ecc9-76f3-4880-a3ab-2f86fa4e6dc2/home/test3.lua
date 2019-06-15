local gui = require("gui")
local event = require("event")
local image = require("image")

local container = gui.createContainer(1, 1, 140, 50, true, true)


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
--local colorPickerContainer = GUI.createPanel(55, 8, 65, 25, 0x333333, 1, 1)
--colorPickerContainer.overrideBound = true


--container:addChild(GUI.createColorPicker(30, 15, 10, 20, "HI", 0x0))

local asd = gui.createTextBox(50, 40, "this is a test\ndoes this text wrap around long lines still or no",0xFFFFFF,  10)
container:addChild(asd)

container:addChild(gui.createSwitch(30, 40, 0x333333, 0xFF0000, 0xFFFFFF))

local bar = gui.createProgressBar(10, 45, 40, 0x333333, 0xFF0000, 0.5, true, 0xFFFFFF, "Hello ")
container:addChild(bar)
bar.setValue(0.2)

container:addChild(gui.createSlider(10, 47, 20, 0x333333, 0xFF0000, 0xFFFFFF, 0xFFFFFF, 10, 50, 30, true, true, 2, "BWBellairs "))

container:addChild(gui.createCheckbox(90, 30, "test", 0x333333, 0xFF0000, 0xFFFFFF))

container:addChild(gui.createScrollBar(90, 10, 10, true, 0x333333, 0xFF0000))
container:addChild(gui.createScrollBar(90, 10, 20, false, 0x333333, 0xFF0000))


local scrollt = gui.createPanel(90, 1, 25, 20, 0x111111, 1, 1, true, true, true, 30, 100)
scrollt.addChild(gui.createTextBox(1, 1, " Our Soviet Union conquers The whole world from Europe to the Neva to the east Above the ground everywhere will sing: The capital, vodka, the Soviet bear! Our Soviet Union conquers The whole world from Europe to the Neva to the east Above the ground everywhere will sing: The capital, vodka, the Soviet bear! To all those around us, it's not worth your while If we were to turn you to ashes. We thank you profoundly, and bow to you deeply, From the mightiest nation in all the world. To all those around us, it's not worth your while If we were to turn you to ashes. We thank you profoundly, and bow to you deeply, From the mightiest nation in all the world. Ааааа, аААаа! Our Soviet Union conquers The whole world from Europe to the Neva to the east Above the ground everywhere will sing: The capital, vodka, the Soviet bear!", 0xFFFFFF, 30))
container:addChild(scrollt)

container:draw()

if computer then
print(computer.freeMemory() / computer.totalMemory())
end

while true do
    doShit(event.pull())
end