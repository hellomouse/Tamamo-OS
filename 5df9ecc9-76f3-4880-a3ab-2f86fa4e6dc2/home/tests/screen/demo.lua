-- Import screen lib
local screen = require("screen")

-- Fill background with black
screen.clear()

-- Draw rectangle grid with random colors
for y = 1, 3 do
  for x = 1, 5 do
    screen.setBackground(math.random(0x0, 0xFFFFFF))
    screen.drawRectangle(x * 7, y * 4, 6, 3)
  end
end

-- Draw a white braille ellipse outline
screen.setBackground(0xFFFFFF)
screen.drawBrailleEllipseOutline(24, 9.5, 10, 5)

-- Draw a yellow line
screen.setBackground(0xFFFF00)
screen.drawBrailleLine(7, 15, 41, 4)

-- Draw some white text
screen.setForeground(0xFFFFFF)
screen.drawText(18, 16, "Hello World!")

-- Draw changed pixels on screen
screen.update(true)