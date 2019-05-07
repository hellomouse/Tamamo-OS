local screen = require("screen")
screen.setBackground(0xFF0000)
screen.fill(10, 10, 100, 20, " ")
screen.setBackground(0x000000)
screen.drawRect(10, 10, 80, 10, " ", 0.5)

screen.setBackground(0xFFFFFF)
screen.setForeground(0xFFFFFF)
screen.drawLine(8, 10, 90, 10)

for i = 5, 80 do
    screen.drawLine(i, 0, i, 50)
end