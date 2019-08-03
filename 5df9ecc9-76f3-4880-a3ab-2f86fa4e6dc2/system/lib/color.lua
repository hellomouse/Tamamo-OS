-- API
local api = {}

-- Optimization for lua
local sqrt = math.sqrt
local floor = math.floor
local byte = string.byte

-- Constants
local r1, r2 =  0          ,  1.0
local g1, g2 = -sqrt(3) / 2, -0.5
local b1, b2 =  sqrt(3) / 2, -0.5

-- The fixed 240 color palette used by OC
-- api.preset_palette = {0x000000,0x002400,0x004900,0x006d00,0x009200,0x00b600,0x00d800,0x00ff00,0x000040,0x002440,0x004940,0x006d40,0x009240,0x00b640,0x00d840,0x00ff40,0x000080,0x002480,0x004980,0x006d80,0x009280,0x00b680,0x00d880,0x00ff80,0x0000c0,0x0024c0,0x0049c0,0x006dc0,0x0092c0,0x00b6c0,0x00d8c0,0x00ffc0,0x0000ff,0x0024ff,0x0049ff,0x006dff,0x0092ff,0x00b6ff,0x00d8ff,0x00ffff,0x330000,0x332400,0x334900,0x336d00,0x339200,0x33b600,0x33d800,0x33ff00,0x330040,0x332440,0x334940,0x336d40,0x339240,0x33b640,0x33d840,0x33ff40,0x330080,0x332480,0x334980,0x336d80,0x339280,0x33b680,0x33d880,0x33ff80,0x3300c0,0x3324c0,0x3349c0,0x336dc0,0x3392c0,0x33b6c0,0x33d8c0,0x33ffc0,0x3300ff,0x3324ff,0x3349ff,0x336dff,0x3392ff,0x33b6ff,0x33d8ff,0x33ffff,0x660000,0x662400,0x664900,0x666d00,0x669200,0x66b600,0x66d800,0x66ff00,0x660040,0x662440,0x664940,0x666d40,0x669240,0x66b640,0x66d840,0x66ff40,0x660080,0x662480,0x664980,0x666d80,0x669280,0x66b680,0x66d880,0x66ff80,0x6600c0,0x6624c0,0x6649c0,0x666dc0,0x6692c0,0x66b6c0,0x66d8c0,0x66ffc0,0x6600ff,0x6624ff,0x6649ff,0x666dff,0x6692ff,0x66b6ff,0x66d8ff,0x66ffff,0x990000,0x992400,0x994900,0x996d00,0x999200,0x99b600,0x99d800,0x99ff00,0x990040,0x992440,0x994940,0x996d40,0x999240,0x99b640,0x99d840,0x99ff40,0x990080,0x992480,0x994980,0x996d80,0x999280,0x99b680,0x99d880,0x99ff80,0x9900c0,0x9924c0,0x9949c0,0x996dc0,0x9992c0,0x99b6c0,0x99d8c0,0x99ffc0,0x9900ff,0x9924ff,0x9949ff,0x996dff,0x9992ff,0x99b6ff,0x99d8ff,0x99ffff,0xcc0000,0xcc2400,0xcc4900,0xcc6d00,0xcc9200,0xccb600,0xccd800,0xccff00,0xcc0040,0xcc2440,0xcc4940,0xcc6d40,0xcc9240,0xccb640,0xccd840,0xccff40,0xcc0080,0xcc2480,0xcc4980,0xcc6d80,0xcc9280,0xccb680,0xccd880,0xccff80,0xcc00c0,0xcc24c0,0xcc49c0,0xcc6dc0,0xcc92c0,0xccb6c0,0xccd8c0,0xccffc0,0xcc00ff,0xcc24ff,0xcc49ff,0xcc6dff,0xcc92ff,0xccb6ff,0xccd8ff,0xccffff,0xff0000,0xff2400,0xff4900,0xff6d00,0xff9200,0xffb600,0xffd800,0xffff00,0xff0040,0xff2440,0xff4940,0xff6d40,0xff9240,0xffb640,0xffd840,0xffff40,0xff0080,0xff2480,0xff4980,0xff6d80,0xff9280,0xffb680,0xffd880,0xffff80,0xff00c0,0xff24c0,0xff49c0,0xff6dc0,0xff92c0,0xffb6c0,0xffd8c0,0xffffc0,0xff00ff,0xff24ff,0xff49ff,0xff6dff,0xff92ff,0xffb6ff,0xffd8ff,0xffffff}
local REDS = {0x00, 0x33, 0x66, 0x99, 0xCC, 0xFF}
local BLUES = {0x00, 0x40, 0x80, 0xC0, 0xFF}
local GREENS = {0x00, 0x24, 0x49, 0x6D, 0x92, 0xB6, 0xD8, 0xFF}

-- Function to get the palette at index i, replaces the array
-- to save RAM
function api.getPresetPalette(i)
  i = i - 1
  return api.toHexFromRGB(REDS[floor(i / 40) % 6 + 1], GREENS[i % 8 + 1], BLUES[floor(i / 8) % 5 + 1])
end

-- Convert r, g, b values to 24 bit int --
function api.toHexFromRGB(r, g, b)
  r, g, b = floor(r), floor(g), floor(b)
  return r * 65536 + g * 256 + b
end

function api.toRGBFromHex(hex)
  local r, g
  r = hex / 65536
  r = r - r % 1
  g = (hex - r * 65536) / 256
  g = g - g % 1
  return r, g, hex - r * 65536 - g * 256
end

function api.blend(base, color, amount)
  amount = amount or 1
  if amount >= 1 then return base end
  if amount <= 0 then return color end

  local r1, g1, b1, r2, g2, b2
  r1, g1, b1 = api.toRGBFromHex(base)
  r2, g2, b2 = api.toRGBFromHex(color)

  local inverted = 1 - amount
				
  local r, g, b =
    r2 * inverted + r1 * amount,
    g2 * inverted + g1 * amount,
    b2 * inverted + b1 * amount

  return api.toHexFromRGB(r - r % 1, g - g % 1, b - b % 1)
end

function api.prettyPrintHex(hex)
  local r, g, b = api.toRGBFromHex(hex)
  return "(" .. r .. ", " .. g .. ", " .. b .. ")"
end

function api.getProminentColor(fg, bg, symbol)
  local val = byte(symbol)
  
  -- Unicode block characters (Common ones)
  if symbol == "█" or symbol == "⣿" then
    return fg
  elseif symbol == " " then
    return bg
  elseif symbol == "" then return fg

  -- Braille characters are determined by area occupied
  elseif val >= 0x2800 and val <= 255 + 0x2800 then
    local bits = 0
    while val > 0 do
      bits = bits + val % 2
      val = (val - val % 2) / 2
    end

    if bits >= 4 then return fg end
    return bg
  end
  
  return bg -- Educated guess
end

-- Ty MineOS for this transition function
function api.transition(color1, color2, position)
  if position > 1 then position = 1 end
  if position < 0 then position = 0 end

  local r1 = color1 / 65536
  r1 = r1 - r1 % 1

  local g1 = (color1 - r1 * 65536) / 256
  g1 = g1 - g1 % 1

  local b1 = color1 - r1 * 65536 - g1 * 256
  local r2 = color2 / 65536
  r2 = r2 - r2 % 1

  local g2 = (color2 - r2 * 65536) / 256
  g2 = g2 - g2 % 1

  local r, g, b =
    r1 + (r2 - r1) * position,
    g1 + (g2 - g1) * position,
    b1 + (color2 - r2 * 65536 - g2 * 256 - b1) * position
  return
    (r - r % 1) * 65536 +
    (g - g % 1) * 256 +
    (b - b % 1)
end

-- See https://gist.github.com/raingloom/3cb614b4e02e9ad52c383dcaa326a25a
function api.HSVToHex(h, s, v)
  local r, g, b

  local i = floor(h * 6);
  local f = h * 6 - i;
  local p = v * (1 - s);
  local q = v * (1 - f * s);
  local t = v * (1 - (1 - f) * s);

  i = i % 6

  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  elseif i == 5 then r, g, b = v, p, q
  end

  return api.toHexFromRGB(r * 255, g * 255, b * 255)
end

return api