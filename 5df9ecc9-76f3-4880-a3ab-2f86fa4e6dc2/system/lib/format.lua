-- Text format api --
local format = {}

-- Requires --
local unicode = require("unicode")
local bit32 = require("bit32")

-- Optimization for lua
local sub = unicode.sub
local len = unicode.len
local uchar = unicode.char
local insert = table.insert
local concat = table.concat
local find = string.find
local bor = bit32.bor

-- Trim the string to the length
function format.trimLength(text, length, suffix)
  if not suffix then suffix = "…" end
  if len(text) > length then return sub(text, 1, length - 1) .. suffix end
  return text
end

-- Wrap text to width
function format.wrap(text, width, returnAsTable)
  checkArg(1, text, "string")
  checkArg(2, width, "number")

  local returned = {}
  local length = len(text)
  local i = 1
  local pos, subchunk

  -- No need to wrap
  if length <= width then
    if returnAsTable then return {text}, 1 end
    return text, 1
  end 

  while i <= length do
    subchunk = sub(text, i, i + width)

    -- Search for the first newline or the first space before i + width + 1
    pos = find(subchunk, "\n") or find(subchunk, " [^ ]*$")

    if pos and pos <= i + width then -- Sub up to the newline / space and continue
      insert(returned, sub(text, i, i + pos - 2))
      i = i + pos
      goto continue
    end

    -- No space was found, sub up to the max allowed - 1 and add a hypen if not end of string
    -- or not in the middle of a word break
    if i + width < length - 1 and sub(text, i + 1, i + 1) ~= " " then 
      insert(returned, sub(text, i, i + width - 1) .. "-")
    else                
      insert(returned, subchunk) 
    end
    i = i + width
    ::continue::
  end

  -- Return as a table
  if returnAsTable then return returned, #returned end

  -- Return the wrapped string and number of new lines
  return concat(returned, "\n"), #returned
end

-- Get braille char from coordinates
-- Note that a, b, ... are not ordered like on the wiki, rather they
-- read directly left -> right top -> bottom
-- Ie:
-- a b
-- c d
-- e f
-- g h
function format.getBrailleChar(a, b, c, d, e, f, g, h)
  return uchar(bor(0x2800, a + 8 * b + 2 * c + 16 * d + 4 * e + 32 * f + 64 * g + 128 * h))
end

return format