local gui = require("gui")

local button = gui.createButton(20, 20, 16, 3, "BUTTON", 0x777777,0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 1)
button.draw(button)

local button2 = gui.createFramedButton(20, 30, 16, 3, "BUTTON", 0x777777,0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 1)
button2.draw(button2)