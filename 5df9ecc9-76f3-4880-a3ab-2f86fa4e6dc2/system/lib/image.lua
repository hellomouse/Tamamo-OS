-- Require modules --
local component = require("component")
local bit32 = require("bit32")
local unicode = require('unicode')
local compression = require("compression")
local screen = require("screen")
local color = require("color")

-- Color API --
local getPresetPalette = color.getPresetPalette
local rgb = color.toHexFromRGB

-- Optimization for lua
local sub = string.sub
local byte = string.byte
local char = string.char
local uchar = unicode.char

local bor = bit32.bor
local bxor = bit32.bxor
local lshift = bit32.lshift

local setChar = screen.setChar
local setPaletteColor = component.gpu.setPaletteColor

-- Populate index of braille characters
-- (Feature removed to save RAM)
-- local braille = {}
-- for i = 0, 255 do braille[i + 1] = uchar(bor(0x2800, i)) end

-- Final API
local api = {}

-- Return the correct hex color value or palette index for a given
-- byte value saved in HDG (0-15 are palettes, others are fixed)
-- Returns { index|color int, is_palette }
local function getcolor(val, palette_size)
  if val < palette_size then
    return {val, true}
  end
  return {getPresetPalette(val - 14), false} -- {preset_palette[val - 14], false}
end

-- HDG Image class
HDGImage = {}
HDGImage.__index = HDGImage

function HDGImage:create(string)
  local img = {}              -- New object
  setmetatable(img, HDGImage) -- make HDGImage handle lookup

  img.data = string           -- Raw image data
  img.indx = 1                -- Current index of the byte lookup
  return img
end

function HDGImage:r8()        -- Read the next byte
  local returned = byte(sub(self.data, self.indx, self.indx))
  self.indx = self.indx + 1
  return returned
end

function HDGImage:prepare()   -- Analyze the raw image data into data arrays
  self.indx = 4  -- Skip header

  -- Basic information
  self.version = self:r8()
  self.w = self:r8()
  self.h = self:r8()
  self.palette_size = self:r8()

  -- Alias
  self.width = self.w
  self.height = self.h

  -- Populate palette
  self.palette = {}
  for i = 1, self.palette_size do
    self.palette[#self.palette + 1] = rgb(self:r8(), self:r8(), self:r8())
  end

  -- Populate fg, bg, sym
  self.fg = {}
  self.bg = {}
  self.sym = {}

  for i = 1, self.w * self.h do self.fg[#self.fg + 1] = self:r8() end
  for i = 1, self.w * self.h do self.bg[#self.bg + 1] = self:r8() end
  for i = 1, self.w * self.h do self.sym[#self.sym + 1] = self:r8() end
end 

function HDGImage:draw(x, y)
  -- Verify not unloaded
  if self.palette == nil and self.bg == nil then
    error("Attempting to draw an unloaded image object!")
  end

  x, y = x or 1, y or 1
  x, y = math.floor(x), math.floor(y)

  -- Populate global palette
  for i = 1, self.palette_size do
    setPaletteColor(i - 1, self.palette[i])
  end

  -- Keep original colors
  local bgi = screen.getBackground()
  local fgi = screen.getForeground()
  local gw, gh = screen.getResolution()

  for i = 1, self.w * self.h do 
    local x1 = math.floor((i - 1) % self.w) + x
    local y1 = math.floor((i - 1) / self.w) + y

    -- Don't render off screen
    if x1 > gw or y1 > gh then
      goto continue
    end

    local a = getcolor(self.bg[i], self.palette_size)
    local b = getcolor(self.fg[i], self.palette_size)

    setChar(x1, y1, b[1], a[1], uchar(bor(0x2800, self.sym[i])), b[2], a[2]) -- braille[1 + self.sym[i]]
    ::continue::
  end

  screen.update()

  -- Reset to original colors
  screen.setBackground(bgi)
  screen.setForeground(fgi)
end

function HDGImage:unload()
  self.data = nil
  self.palette = nil
  self.fg = nil
  self.bg = nil
  self.sym = nil
  screen.resetPalette()
end

-- Helper function, decompresses a string
-- into an array of bytes (Based on LZW and
-- the HDG file format's coding scheme)
local function decompress(compressedstr) -- string
  -- Preseed the dictionary
  local d, dictSize, entry, w, k = {}, 255, "", "", ""
  for i = 0, 255 do d[i] = char(i) end

  -- The table of integers that will make up our compressed data
  local compressed = {}

  -- Currently the data is stored as a string, and not bytes, and values
  -- greater than 127 are stored into 2 bytes. This unpacks this coding
  -- scheme so we get a nice table of numbers
  local i = 1
  while i < #compressedstr do
    local b = byte(sub(compressedstr, i, i))
    if b == nil then b = 0 end

    -- If the value >= 128 then read the next byte, and take the last 7 bits
    -- of this byte and concat with the last 7 bits of the next byte.
    --
    -- Ie, if this byte was 10000011 and the next byte was 01001001 then
    -- this would output 111001001 (bin)
    -- We also increment i as we won't need to read the next byte
    if b >= 128 then
      local left = bxor(b, 128)
      local right = byte(sub(compressedstr, i + 1, i + 1))
      b = left * 128 + right
      i = i + 1
    end

    i = i + 1
    compressed[#compressed + 1] = b
  end
  
  -- LZW decompression algorithim
  return compression.decompress(compressed)
end

-- Loads and returns an uncompressed HDG object that
-- can be displayed to the screen
function api.loadHDG(path)
  local data = io.open(path, "rb")
  if path == nil then error("Image path is nil") end
  if not data then error(path .. " could not be loaded") end

  local header = data:read(3)

  -- Verify header
  if header ~= "HDG" then
    error("File header must be HDG")
  end

  local restOfData = decompress(data:read("*a"))
  local returned = HDGImage:create(header .. restOfData)
  returned:prepare()
  return returned
end

return api