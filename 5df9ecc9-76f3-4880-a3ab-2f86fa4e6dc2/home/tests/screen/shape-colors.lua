-- Tests background color works properly
local screen = require("screen")
local component = require("component")
local gpu = component.gpu

local paletteBg = math.random(0, 16777215) -- Random color between 0x0 and 0xFFFFFF
local paletteFg = math.random(0, 16777215) -- Random color between 0x0 and 0xFFFFFF
gpu.setPaletteColor(0, paletteBg)
gpu.setPaletteColor(1, paletteFg)

screen.clear()

-- Background colors
screen.setForeground(0xFFFFFF)
screen.drawText(10, 7, "All shapes drawn below should be the same color")
screen.drawText(10, 8, "Braille shapes are offset on the y by 0.5")
screen.drawText(10, 10, "BG: Palette index at 0 is " .. paletteBg)

screen.setForeground(0xFFFFFF)
screen.setBackground(0, true)

screen.set(10, 13, "Set: background color")
screen.fill(10, 14, 15, 1, " ")

screen.drawEllipse(10, 20, 5, 3)
screen.drawEllipseOutline(22, 20, 5, 3)
screen.drawBrailleEllipse(34, 20.5, 5, 3)
screen.drawBrailleEllipseOutline(46, 20.5, 5, 3)

screen.drawLine(10, 25, 12, 30)
screen.drawBrailleLine(22, 25.5, 34, 30.5)

screen.drawRectangle(10, 32, 5, 5)
screen.drawRectangleOutline(22, 32, 5, 5)
screen.drawBrailleRectangle(34, 32.5, 5, 5)
screen.drawThinRectangleOutline(46, 32, 5, 5)
screen.drawBrailleRectangleOutline(58, 32, 5, 5)


screen.setForeground(0xFFFFFF)
screen.setBackground(0)
screen.drawText(80, 7, "All shapes drawn below should be the same color")
screen.drawText(80, 8, "But with a foreground color. Braille should not be affected.")
screen.drawText(80, 10, "FG: Palette index at 1 is " .. paletteFg)

screen.setForeground(1, true)
screen.setBackground(0, true)

screen.set(100 - 20, 13, "Set: foreground color")
screen.fill(100 - 20, 14, 15, 1, "t")

screen.drawEllipse(100 - 20, 20, 5, 3, 1, "t")
screen.drawEllipseOutline(112 - 20, 20, 5, 3, 1, "t")
screen.drawBrailleEllipse(124 - 20, 20.5, 5, 3)
screen.drawBrailleEllipseOutline(136 - 20, 20.5, 5, 3)

screen.drawLine(100 - 20, 25, 102 - 20, 30, 1, "t")
screen.drawBrailleLine(112 - 20, 25.5, 124 - 20, 30.5)

screen.drawRectangle(100 - 20, 32, 5, 5, 1, "t")
screen.drawRectangleOutline(112 - 20, 32, 5, 5, 1, "t")
screen.drawBrailleRectangle(124 - 20, 32.5, 5, 5)
screen.drawThinRectangleOutline(136 - 20, 32, 5, 5)
screen.drawBrailleRectangleOutline(148 - 20, 32, 5, 5)

screen.update(true)