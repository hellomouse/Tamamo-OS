-- Test lines drawing in different directions
-- to check consistency of different lines
local screen = require("screen")
screen.setBackground(0xFF0000)

screen.drawLine(10, 10, 15, 20)
screen.drawLine(10, 10, 10, 20)
screen.drawLine(10, 10, 5, 20)

screen.drawLine(10, 10, 20, 5)
screen.drawLine(10, 10, 20, 10)
screen.drawLine(10, 10, 20, 15)

screen.drawLine(40, 10, 30, 5)
screen.drawLine(40, 10, 30, 10)
screen.drawLine(40, 10, 30, 15)

screen.drawLine(50, 20, 55, 10)
screen.drawLine(50, 20, 50, 10)
screen.drawLine(50, 20, 45, 10)

local dy = 20
screen.drawBrailleLine(10, 10 + dy, 15, 20 + dy)
screen.drawBrailleLine(10, 10 + dy, 10, 20 + dy)
screen.drawBrailleLine(10, 10 + dy, 5, 20 + dy)

screen.drawBrailleLine(10, 10 + dy, 20, 5 + dy)
screen.drawBrailleLine(10, 10 + dy, 20, 10 + dy)
screen.drawBrailleLine(10, 10 + dy, 20, 15 + dy)

screen.drawBrailleLine(40, 10 + dy, 30, 5 + dy)
screen.drawBrailleLine(40, 10 + dy, 30, 10 + dy)
screen.drawBrailleLine(40, 10 + dy, 30, 15 + dy)

screen.drawBrailleLine(50, 20 + dy, 55, 10 + dy)
screen.drawBrailleLine(50, 20 + dy, 50, 10 + dy)
screen.drawBrailleLine(50, 20 + dy, 45, 10 + dy)

screen.update()