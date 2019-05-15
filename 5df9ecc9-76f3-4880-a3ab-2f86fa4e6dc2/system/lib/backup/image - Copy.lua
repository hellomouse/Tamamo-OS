-- Require modules --
local component = require("component")
local bit32 = require("bit32")
local unicode = require('unicode')
local compression = require("compression")

local gpu = component.gpu

-- The fixed 240 color palette used by HDG
local preset_palette = {0x000000,0x002400,0x004900,0x006D00,0x009200,0x00B600,0x00D800,0x00FF00,0x000040,0x002440,0x004940,0x006D40,0x009240,0x00B640,0x00D840,0x00FF40,0x000080,0x002480,0x004980,0x006D80,0x009280,0x00B680,0x00D880,0x00FF80,0x0000C0,0x0024C0,0x0049C0,0x006DC0,0x0092C0,0x00B6C0,0x00D8C0,0x00FFC0,0x0000FF,0x0024FF,0x0049FF,0x006DFF,0x0092FF,0x00B6FF,0x00D8FF,0x00FFFF,0x330000,0x332400,0x334900,0x336D00,0x339200,0x33B600,0x33D800,0x33FF00,0x330040,0x332440,0x334940,0x336D40,0x339240,0x33B640,0x33D840,0x33FF40,0x330080,0x332480,0x334980,0x336D80,0x339280,0x33B680,0x33D880,0x33FF80,0x3300C0,0x3324C0,0x3349C0,0x336DC0,0x3392C0,0x33B6C0,0x33D8C0,0x33FFC0,0x3300FF,0x3324FF,0x3349FF,0x336DFF,0x3392FF,0x33B6FF,0x33D8FF,0x33FFFF,0x660000,0x662400,0x664900,0x666D00,0x669200,0x66B600,0x66D800,0x66FF00,0x660040,0x662440,0x664940,0x666D40,0x669240,0x66B640,0x66D840,0x66FF40,0x660080,0x662480,0x664980,0x666D80,0x669280,0x66B680,0x66D880,0x66FF80,0x6600C0,0x6624C0,0x6649C0,0x666DC0,0x6692C0,0x66B6C0,0x66D8C0,0x66FFC0,0x6600FF,0x6624FF,0x6649FF,0x666DFF,0x6692FF,0x66B6FF,0x66D8FF,0x66FFFF,0x990000,0x992400,0x994900,0x996D00,0x999200,0x99B600,0x99D800,0x99FF00,0x990040,0x992440,0x994940,0x996D40,0x999240,0x99B640,0x99D840,0x99FF40,0x990080,0x992480,0x994980,0x996D80,0x999280,0x99B680,0x99D880,0x99FF80,0x9900C0,0x9924C0,0x9949C0,0x996DC0,0x9992C0,0x99B6C0,0x99D8C0,0x99FFC0,0x9900FF,0x9924FF,0x9949FF,0x996DFF,0x9992FF,0x99B6FF,0x99D8FF,0x99FFFF,0xCC0000,0xCC2400,0xCC4900,0xCC6D00,0xCC9200,0xCCB600,0xCCD800,0xCCFF00,0xCC0040,0xCC2440,0xCC4940,0xCC6D40,0xCC9240,0xCCB640,0xCCD840,0xCCFF40,0xCC0080,0xCC2480,0xCC4980,0xCC6D80,0xCC9280,0xCCB680,0xCCD880,0xCCFF80,0xCC00C0,0xCC24C0,0xCC49C0,0xCC6DC0,0xCC92C0,0xCCB6C0,0xCCD8C0,0xCCFFC0,0xCC00FF,0xCC24FF,0xCC49FF,0xCC6DFF,0xCC92FF,0xCCB6FF,0xCCD8FF,0xCCFFFF,0xFF0000,0xFF2400,0xFF4900,0xFF6D00,0xFF9200,0xFFB600,0xFFD800,0xFFFF00,0xFF0040,0xFF2440,0xFF4940,0xFF6D40,0xFF9240,0xFFB640,0xFFD840,0xFFFF40,0xFF0080,0xFF2480,0xFF4980,0xFF6D80,0xFF9280,0xFFB680,0xFFD880,0xFFFF80,0xFF00C0,0xFF24C0,0xFF49C0,0xFF6DC0,0xFF92C0,0xFFB6C0,0xFFD8C0,0xFFFFC0,0xFF00FF,0xFF24FF,0xFF49FF,0xFF6DFF,0xFF92FF,0xFFB6FF,0xFFD8FF,0xFFFFFF}

-- Optimization for lua
local insert = table.insert
local sub = string.sub
local byte = string.byte
local char = string.char
local uchar = unicode.char

local bor = bit32.bor
local bxor = bit32.bxor
local lshift = bit32.lshift

local setBackground = gpu.setBackground
local setForeground = gpu.setForeground
local set = gpu.set
local gw, gh = gpu.maxResolution()

-- Populate index of braille characterss
local braille = {}
for i = 0, 255 do
  braille[i + 1] = uchar(bor(0x2800, i))
end

-- Final API
local api = {}

-- Convert 3 seperate colors, r, g, b to hex int
local function rgb(r, b, g)
  return bor(bor(lshift(r, 16), lshift(b, 8)), g)
end

-- Return the correct hex color value or palette index for a given
-- byte value saved in HDG (1-15 are palettes, others are fixed)
-- Returns { index|color int, is_palette }
local function getcolor(val)
  if val < 15 then
    return {val + 1, true}
  end
  return {preset_palette[val - 14], false}
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

  -- Populate palette
  self.palette = {}
  for i = 1, self.palette_size do
    insert(self.palette, rgb(self:r8(), self:r8(), self:r8()))
  end

  -- Populate fg, bg, sym
  self.fg = {}
  self.bg = {}
  self.sym = {}

  for i = 1, self.w * self.h do insert(self.fg, self:r8()) end
  for i = 1, self.w * self.h do insert(self.bg, self:r8()) end
  for i = 1, self.w * self.h do insert(self.sym, self:r8()) end
end 

function HDGImage:draw(x, y)
  x = x or 1
  y = y or 1

  -- Populate global palette
  for i = 1, self.palette_size do
    gpu.setPaletteColor(i, self.palette[i])
  end

  -- Keep original colors
  local bgi = gpu.getBackground()
  local fgi = gpu.getForeground()

  local bg, fg = nil, nil

  -- TODO use the screen class (TODO: Write screen class)
  for i = 1, self.w * self.h do 
    local x1 = math.floor((i - 1) % self.w) + x
    local y1 = math.floor((i - 1) / self.w) + y

    -- Don't render off screen
    if x1 > gw or y1 > gh then
      goto continue
    end

    local a = getcolor(self.bg[i])
    local b = getcolor(self.fg[i])

    if a[1] ~= bg then
      bg = a[1]
      setBackground(a[1], a[2])
    end
    if b[1] ~= fg then
      fg = b[1]
      setForeground(b[1], b[2])
    end
    set(x1, y1, braille[1 + self.sym[i]])
    ::continue::
  end

  -- Reset to original colors
  setBackground(bgi)
  setForeground(fgi)
end

function HDGImage:reset()     -- Read the index
  self.indx = 1
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
    insert(compressed, b)
  end

  -- LZW decompression algorithim
  return compression.decompress(compressed)
end

-- Loads and returns an uncompressed HDG object that
-- can be displayed to the screen
function api.loadHDG(path)
  local data = io.open(path, "rb")
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