local screen = require("screen")
-- screen.setBackground(0xFF0000)
-- screen.fill(10, 10, 100, 20, " ")

screen.setBackground(0x00FFFFF)

screen.drawLineThin(10, 10, 50, 20, 0.25)
screen.drawLineThin(10, 10, 20, 40, 0.5)
screen.drawLineThin(10, 10, 10, 40, 0.75)
screen.drawLineThin(10, 10, 50, 10, 1, "t")

screen.drawLineThin(50.5, 10, 58, 50, 1)

screen.setBackground(0xFF0000)
screen.drawLineThin(52, 10, 58, 50, 1)
screen.drawLine(100, 10, 101, 50)



--os.sleep(10)
--screen.update()