-- Import screen lib
local screen = require("screen")

-- Fill background with black
screen.clear()

-- Draw a row of rectangles with random colors
for i = 1, 10 do
  screen.setBackground(math.random(0x0, 0xFFFFFF))
  screen.drawRectangle(i * 10, 15, 6, 3)
end

-- Draw braille ellipse centered on screen
local w, h = screen.getResolution()

-- screen.setBackground(0xFFDD00)
-- screen.drawBrailleEllipseOutline(w / 2, h / 2, w / 4, w / 8)

-- testing
local floor = math.floor 

for r = 1, 50, 5 do
  screen.setBackground(floor(r / 50 * 0xFFFFFF))
  screen.drawBrailleEllipseOutline(floor(w / 2), floor(h / 2), r, r / 2)
end

-- Draw a white line from bottom left corner to top right
screen.setBackground(0xFFFFFF)
screen.setForeground(0x0)
screen.drawBrailleLine(1, h, w, 1)

-- Draw changed pixels on screen
screen.update(true)