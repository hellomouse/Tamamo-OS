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



local hs = {}
local selections = {
    {1, 2, 1, 5},
    {2, 3, 6, 2}
}
hs[5] = 0xFF0000
local co = gui.createCodeView(0, 0, 150, 50, {
    "line 1",
    "line 2",
    "this is an example of a really long line that forces u to scroll across",
    "-- comment test",
    "for i = 1, 10 do",
        "",
        "",
        "local function drawHighlightedText(line, x, y, syntaxPatterns, colorScheme)",
  "-- Base text (assumed you set base color already)",
  "screen.drawText(x, y, line)",
"",
  "-- Syntax highlighting for each group",
  "local index1, index2, group, pattern",
"",
 "for i = 1, #syntaxPatterns, 2 do",
  "  pattern = syntaxPatterns[i]",
  "  group = syntaxPatterns[i + 1] .. \"\"",
"",
  "  index1, index2 = find(line, pattern, 1)",
  "  screen.setForeground(colorScheme[group] or 1)",
"",
  "  while index1 ~= nil do",
  "    screen.drawText(x + index1 - 1, y, sub(line, index1, index2))",
  "    index1, index2 = find(line, pattern, index1 + 1)",
  "    if thing then",
  "\t\t\t-- Thing",
  "    end",
  "  end",
  "end",
  "test",

      "line 1",
    "line 2",
    "this is an example of a really long line that forces u to scroll across",
    "-- comment test",
    "for i = 1, 10 do",
        "",
        "",
        "local function drawHighlightedText(line, x, y, syntaxPatterns, colorScheme)",
  "-- Base text (assumed you set base color already)",
  "screen.drawText(x, y, line)",
"",
  "-- Syntax highlighting for each group",
  "local index1, index2, group, pattern",
"",
 "for i = 1, #syntaxPatterns, 2 do",
  "  pattern = syntaxPatterns[i]",
  "  group = syntaxPatterns[i + 1] .. \"\"",
"",
  "  index1, index2 = find(line, pattern, 1)",
  "  screen.setForeground(colorScheme[group] or 1)",
"",
  "  while index1 ~= nil do",
  "    screen.drawText(x + index1 - 1, y, sub(line, index1, index2))",
  "    index1, index2 = find(line, pattern, index1 + 1)",
  "    if thing then",
  "\t\t\t-- Thing",
  "    end",
  "  end",
  "end",
  "test",
      "line 1",
    "line 2",
    "this is an example of a really long line that forces u to scroll across",
    "-- comment test",
    "for i = 1, 10 do",
        "",
        "",
        "local function drawHighlightedText(line, x, y, syntaxPatterns, colorScheme)",
  "-- Base text (assumed you set base color already)",
  "screen.drawText(x, y, line)",
"",
  "-- Syntax highlighting for each group",
  "local index1, index2, group, pattern",
"",
 "for i = 1, #syntaxPatterns, 2 do",
  "  pattern = syntaxPatterns[i]",
  "  group = syntaxPatterns[i + 1] .. \"\"",
"",
  "  index1, index2 = find(line, pattern, 1)",
  "  screen.setForeground(colorScheme[group] or 1)",
"",
  "  while index1 ~= nil do",
  "    screen.drawText(x + index1 - 1, y, sub(line, index1, index2))",
  "    index1, index2 = find(line, pattern, index1 + 1)",
  "    if thing then",
  "\t\t\t-- Thing",
  "    end",
  "  end",
  "end",
  "test",
    "-- Syntax highlighting for each group",
  "local index1, index2, group, pattern",
"",
 "for i = 1, #syntaxPatterns, 2 do",
  "  pattern = syntaxPatterns[i]",
  "  group = syntaxPatterns[i + 1] .. \"\"",
"",
  "  index1, index2 = find(line, pattern, 1)",
  "  screen.setForeground(colorScheme[group] or 1)",
"",
  "  while index1 ~= nil do",
  "    screen.drawText(x + index1 - 1, y, sub(line, index1, index2))",
  "    index1, index2 = find(line, pattern, index1 + 1)",
  "    if thing then",
  "\t\t\t-- Thing",
  "    end",
  "  end",
  "end",
  "test",
}, 1, 16, selections, hs, gui.LUA_SYNTAX_PATTERNS,
gui.LUA_SYNTAX_COLOR_SCHEME, true)
container:addChild(co)


container:draw()

if computer then
print(computer.freeMemory() / computer.totalMemory())
end

while true do
    doShit(event.pull())
    os.sleep(0.1)
end