local screen = require("screen")
screen.setBackground(0xFF0000)
screen.fill(10, 10, 100, 20, " ")
screen.setBackground(0x000000)
screen.drawRect(10, 10, 80, 10, 0.5)
-- screen.setBackground(0xFFFFFF)
-- screen.setForeground(0xFFFFFF)
-- screen.drawLine(8, 10, 90, 10)

-- for i = 5, 80 do
--     screen.drawLine(i, 0, i, 20)
-- end

screen.setBackground(0xFF00FF)
screen.fill(1,1,screen.getWidth(),screen.getHeight(), " ", false)

local image = require("image")
local x = image.loadHDG("/system/assets/boot-logo.hdg")
x:draw(1, 10)
--
screen.copy(1, 10, x.w, x.h, 39, 0)
screen.copy(1, 10, x.w, x.h, 0, -14)

screen.setForeground(0xFFFFFF)
screen.update()
screen.drawRectOutline(20, 20, 80, 20, 1)
screen.setBackground(0xFF0000)
screen.drawEllipse(30, 30, 20, 10, 0.5)

screen.update()

screen.drawText(40, 40, "test")
screen.setForeground(0x00FF00)
screen.setBackground(0x00FF00)
screen.drawEllipseOutlineThin(40, 30, 20, 20, 0.5)

--os.sleep(10)
--screen.update()