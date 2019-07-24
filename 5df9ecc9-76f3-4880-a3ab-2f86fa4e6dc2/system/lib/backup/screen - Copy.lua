-- Double Buffered Magic --
local component = require("component")
local unicode = require("unicode")
local color = require("color")
local format = require("format")

local gpuProxy = component.gpu
if not gpuProxy then
  error("A graphics card is required for screen.lua")
end

-- Buffer which stores all the changes
-- that are to be displayed on the screen
local bufferWidth, bufferHeight
local bufferBackground, bufferForeground, bufferSymbol
local changeBackgrounds, changeForegrounds, changeSymbols

-- Limits for drawing on the buffer, to avoid 
-- checking for excessive changes (Bounds rectangle where changes occured)
local updateBoundX1, updateBoundY1, updateBoundX2, updateBoundY2 = 1, 1, bufferWidth, bufferHeight

-- True "bounding box", anything outside won't be rendered
local drawX1, drawY1, drawX2, drawY2

-- Current fg / bg colors for set and fill
local currentBackground, currentForeground = 0, 0xFFFFFF

-- Optimization for lua / gpu proxying
local GPUfill, GPUset, GPUsetBackground, GPUsetForeground
local GPUgetResolution, GPUsetResolution, GPUgetPaletteColor, GPUcopy, GPUsetResolution, GPUsetPaletteColor
local GPUgetBackground, GPUgetForeground

local rep, sub, len = string.rep, unicode.sub, unicode.len
local floor, ceil, min, max, abs, sqrt, sin, cos = math.floor, math.ceil,
  math.min, math.max, math.abs, math.sqrt, math.sin, math.cos
local concat = table.concat
local unpack = unpack or table.unpack

-- Constants
local fillIfAreaIsGreaterThan = 40

-- Convert x y coords to a buffer index
local function getIndex(x, y)
	return bufferWidth * (y - 1) + x
end

-- Convert index to x y coords
local function getCoords(index)
  local y = floor(index / buffWidth) + 1
  local x = index - (y - 1) * buffWidth
  return x, y
end

-- Check if two characters at the buffers are
-- equal. Equality is checked by symbol, fg and bg
-- unless the character is whitespace, in which case
-- fg is ignored
local function areEqual(sym, changeSymbols, bg, changeBackgrounds, fg, changeForegrounds)
  -- If symbols don't match or backgrounds match always unequal
  if sym ~= changeSymbols or bg ~= changeBackgrounds then return false end
  if sym == " " then return true end
  return fg == changeForegrounds
end

-- Palette index = (-index - 1), this takes the "absolute"
-- value to convert to the proper index if negative
local function absColor(val) 
  if val < 0 then return -val - 1 end
  return val
end 

-- Normalize a color to a 24 bit int (Including)
-- palette indexes
local function normalizeColor(val)
  if val < 0 then return GPUgetPaletteColor(-val - 1) end
  return val
end

--------------------------------------------------------

-- Flush the buffer and re-create each array --
local function flush(w, h)
  if w == nil or h == nil then
    w, h = GPUgetResolution()
  end
  checkMultiArg("number", w, h)

  bufferWidth, bufferHeight = w, h
  updateBoundX1, updateBoundX2, updateBoundY1, updateBoundY2 = w, 1, h, 1
  drawX1, drawY1, drawX2, drawY2 = 1, 1, bufferWidth, bufferHeight

  bufferBackground, bufferForeground, bufferSymbol = {}, {}, {}
  changeBackgrounds, changeForegrounds, changeSymbols = {}, {}, {}

  -- Prefill the buffers to avoid rehashing --
  for i = 1, w * h do
    bufferBackground[i], bufferForeground[i], bufferSymbol[i] = 0, 0, " "
    changeBackgrounds[i], changeForegrounds[i], changeSymbols[i] = 0, 0, " "
  end
end

-- Set a specific character (internal method) --
local function setChar(x, y, fgColor, bgColor, symbol)
  if x < drawX1 or x > drawX2 or y < drawY1 or y > drawY2 then return false end

  -- Don't check arg types in this function as this function is used A LOT
  -- internally and checking args actually slows down a full screen render
  -- by up to 100 ms
  local i = getIndex(x, y)

  -- Replace empty braille with regular space
  if symbol == "⠀" then symbol = " " end

  -- Update draw bounds if needed
  updateBoundX1, updateBoundX2 = min(x, updateBoundX1), max(x, updateBoundX2)
  updateBoundY1, updateBoundY2 = min(x, updateBoundY1), max(x, updateBoundY2)
  changeBackgrounds[i], changeForegrounds[i], changeSymbols[i] = bgColor, fgColor, symbol
end

-- Write changes to the screen
local function update(force)
  -- Force update all bounds
  if force then
    updateBoundX1, updateBoundY1, updateBoundX2, updateBoundY2 = 1, 1, bufferWidth, bufferHeight
  end

  -- If there have been no changes then ignore
  if updateBoundX1 > updateBoundX2 or updateBoundY1 > updateBoundY2 then return end

  -- i = current index
  -- lineChange = index increment when changing to next y value
  -- subgroup = the foreground subgroup of the background dict
  -- searchX = x value of end of repeated length
  -- searchIndex = index of end of repeated length
  -- tempLine = temp table to store line of chars
  -- colorChanges = dict of bg / fg color pixels grouped togther
  -- tempLineSize, subGroupSize = temp varable to keep track of sizes of these tables
  local i = getIndex(updateBoundX1, updateBoundY1)
  local lineChange = bufferWidth - updateBoundX2 + updateBoundX1 - 1
  local subgroup, searchX, searchIndex, tempLineSize, subgroupSize
  local colorChanges, tempLine = {}, {}

  for y = updateBoundY1, updateBoundY2 do
    x = updateBoundX1
    while x <= updateBoundX2 do	
			if changeBackgrounds[i] == nil or changeBackgrounds[i] == -17 or changeForegrounds[i] == -17 then
      -- Ignore transparent characters
      -- If char is same as buffer below don't update it
      -- unless the force parameter is true.
      elseif force or not areEqual(bufferSymbol[i], changeSymbols[i], bufferBackground[i], changeBackgrounds[i], bufferForeground[i], changeForegrounds[i]) then
        ::doChange::
        bufferSymbol[i], bufferBackground[i], bufferForeground[i] = changeSymbols[i], changeBackgrounds[i], changeForegrounds[i]
  
        tempLine = { changeSymbols[i] }
        tempLineSize, searchX, searchIndex = 1, x + 1, i + 1

        while searchX <= updateBoundX2 do
          if changeBackgrounds[i] == changeBackgrounds[searchIndex] and
						(changeSymbols[searchIndex] == " " or
             changeForegrounds[i] == changeForegrounds[searchIndex]) 
          then

            -- Update current "image" buffer
            bufferSymbol[searchIndex], bufferBackground[searchIndex], bufferForeground[searchIndex] = 
              changeSymbols[searchIndex], changeBackgrounds[searchIndex], changeForegrounds[searchIndex]
            tempLine[tempLineSize + 1] = changeSymbols[searchIndex]

            searchX, searchIndex, tempLineSize = searchX + 1, searchIndex + 1, tempLineSize + 1
          else break end
        end

        if colorChanges[changeBackgrounds[i]] == nil then colorChanges[changeBackgrounds[i]] = {} end
        if colorChanges[changeBackgrounds[i]][changeForegrounds[i]] == nil then colorChanges[changeBackgrounds[i]][changeForegrounds[i]] = {} end

        subgroup = colorChanges[changeBackgrounds[i]][changeForegrounds[i]]
        subgroupSize = #subgroup
        subgroup[subgroupSize + 1], subgroup[subgroupSize + 2] = x, y
        subgroup[subgroupSize + 3] = concat(tempLine)

        i = i + searchX - x - 1
        x = searchX - 1
      end

      -- This is required to avoid infinite loops
      -- when buffers are the same
      x = x + 1
      i = i + 1
		end

		i = i + lineChange
  end
  
  -- Draw color groups
  local currentForeground

  for backgroundColor, foregrounds in pairs(colorChanges) do
    GPUsetBackground(absColor(backgroundColor), backgroundColor < 0)

    for foregroundColor, group2 in pairs(foregrounds) do
      if currentForeground ~= foregroundColor then
        GPUsetForeground(absColor(foregroundColor), foregroundColor < 0)
        currentForeground = foregroundColor
      end

      for i = 1, #group2, 3 do
        GPUset(group2[i], group2[i + 1], group2[i + 2])
      end
    end
  end

  -- Reset the drawX drawY bounds to largest / smallest possible
  updateBoundX1, updateBoundX2 = bufferWidth, 1
  updateBoundY1, updateBoundY2 = bufferHeight, 1 
  colorChanges = nil
end

-- Set the drawing bounds. If useCurrent is true it will take the min
-- of the current bound and the updated bound
local function setDrawingBound(x1, y1, x2, y2, useCurrent)
  -- If no arguments are passed reset to full screen
  if x1 == nil then
    drawX1, drawY1, drawX2, drawY2 = 1, 1, bufferWidth, bufferHeight
    return
  end

  checkMultiArg("number", x1, y1, x2, y2)
  x1, y1, x2, y2 = floor(x1), floor(y1), floor(x2), floor(y2)

  if useCurrent then
    -- Take the intersection of rectangles defined by the corners
    -- (drawX1, drawY1), (drawX2, drawY2) and (x1, y1), (x2, y2)
    local x3, y3, x4, y4 = max(drawX1, x1), max(drawY1, y1), min(drawX2, x2), min(drawY2, y2)
    if x3 < x4 and y3 < y4 then
      drawX1, drawY1, drawX2, drawY2 = x3, y3, x4, y4
    end
  else
    -- Overwrite any changes
    drawX1, drawY1, drawX2, drawY2 = max(1, x1), max(1, y1), min(bufferWidth, x2), min(bufferHeight, y2)
  end

  -- Bound checks
  drawX1, drawX2 = max(1, drawX1), min(bufferWidth, drawX2)
  drawY1, drawY2 = max(1, drawY1), min(bufferHeight, drawY2)

  -- Invalid corners (x1, y1) must be top left corner
  if drawX1 >= drawX2 or drawY1 >= drawY2 then
    error("Rectangle defined by corners (" .. drawX1 .. ", " .. drawY1 .. 
      "), (" .. drawX2 .. ", " .. drawY2 .. ") is not valid (First corner must be top left)")
  end
end

local function resetDrawingBound()
  drawX1, drawY1, drawX2, drawY2 = 1, 1, bufferWidth, bufferHeight
end

-- Getter for drawing bounds
local function getDrawingBound()
  return drawX1, drawY1, drawX2, drawY2
end

-- Raw get for buffer values
local function getRaw(x, y)
  local index = getIndex(x, y)
  if changeBackgrounds[index] ~= nil and changeBackgrounds[index] ~= -17 and changeForegrounds[index] ~= -17 then
    return normalizeColor(changeBackgrounds[index]), normalizeColor(changeForegrounds[index]), changeSymbols[index]
  end
  return normalizeColor(bufferBackground[index]), normalizeColor(bufferForeground[index]), bufferSymbol[index]
end

-- Additional functions for the screen

-- Override GPU Functions
-- All files will now utilize the buffered drawing code
-- instead of native gpu codem which should be abstracted
local function setBackground(color, isPalette)
  checkArg(1, color, "number")
  checkArg(2, isPalette, "boolean", "nil")

  local prev = currentBackground
  if isPalette then currentBackground = -color - 1 else currentBackground = color end
  if prev < 0 then return GPUgetPaletteColor(-prev - 1), -prev - 1 end
  return prev
end

local function setForeground(color, isPalette)
  checkArg(1, color, "number")
  checkArg(2, isPalette, "boolean", "nil")

  local prev = currentForeground
  if isPalette then currentForeground = -color - 1 else currentForeground = color end
  if prev < 0 then return GPUgetPaletteColor(-prev - 1), -prev - 1 end
  return prev
end

local function getBackground()
  return absColor(currentBackground), currentBackground < 0
end

local function getForeground()
  return absColor(currentForeground), currentForeground < 0
end

local function set(x, y, string, vertical)
  checkMultiArg("number", x, y)
  checkArg(3, string, "string")
  x, y = floor(x), floor(y)

  if (not vertical and (y < 1 or y > bufferHeight or x > bufferWidth or x + len(string) < 1)) or
     (vertical and (x < 1 or x > bufferWidth or y > bufferHeight or y + len(string) < 1)) then
    return false
  end

  for delta = 0, len(string) - 1 do
    if vertical then
      setChar(x, y + delta, currentForeground, currentBackground, sub(string, delta + 1, delta + 1))
    else
      setChar(x + delta, y, currentForeground, currentBackground, sub(string, delta + 1, delta + 1))
    end
  end
  return true
end

-- Copy a region by a displacement tx and ty
-- Note that this directly updates to screen, as it is more
-- efficent to directly do the copy call
local function copy(x, y, w, h, tx, ty)
  checkMultiArg("number", x, y, w, h, tx, ty)

  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if x < 1 or y < 1 or x > bufferWidth or y > bufferHeight or w < 1 or h < 1 then return false end
  local canDirectlyCopy, canPartialCopy = true, false
  local bg, fg, sym, i

  -- We can't use gpu copy directly though if it exceeds the current bounds
  if drawX1 ~= 1 or drawY1 ~= 1 or drawX2 ~= bufferWidth or drawY2 ~= bufferHeight then
    if x + tx < drawX1 or x + tx + w - 1 < drawX1 or y + ty < drawY1 or y + ty + h - 1 < drawY1 or
      x + tx > drawX2 or x + tx + w - 1 > drawX2 or y + ty > drawY2 or y + ty + h - 1 > drawY2 then
      canDirectlyCopy = false
    end
  end

  -- Literally just call copy() since it's 1 GPU call
  -- and the buffer's already properly updated
  if canDirectlyCopy then
    update() -- Update current change buffer
    GPUcopy(x, y, w, h, tx, ty)
  
  -- Try to identify any overlapping region we can copy to
  -- to minimize later set() calls
  else
    -- Intersect of draw bounds and the copied rectangle
    -- (Copied portion that can be displayed)
    local ix1, iy1, ix2, iy2 = max(drawX1, x + tx), max(drawY1, y + ty), min(drawX2, x + w + tx), min(drawY2, y + h + ty)

    if ix1 >= ix2 or iy1 >= iy2 then else -- If there is an intersection copy() it over
      update() -- Update current change buffer
      GPUcopy(ix1 - tx, iy1 - ty, ix2 - ix1 + 1, iy2 - iy1 + 1, tx, ty)
      canPartialCopy = true
    end
  end

  -- Update background BG buffer to match reality
  local boundX1, boundX2, xinc, boundY1, boundY2, yinc
  boundX1, boundX2, xinc = x, x + w - 1, 1
  boundY1, boundY2, yinc = y, y + h - 1, 1
  if tx > 0 then
    boundX1, boundX2, xinc = boundX2, boundX1, -1
  end
  if ty > 0 then
    boundY1, boundY2, yinc = boundY2, boundY1, -1
  end
   
  for y1 = boundY1, boundY2, yinc do
    for x1 = boundX1, boundX2, xinc do
      if y1 > bufferHeight or y1 + ty > bufferHeight then goto loopend end
      if x1 < 1 or x1 > bufferWidth or y1 < 1 or
        x1 + tx < 1 or x1 + tx > bufferWidth or y1 + ty < 1 then goto continue end

      bg, fg, sym = getRaw(x1, y1)
      if canDirectlyCopy or canPartialCopy then
        i = getIndex(x1 + tx, y1 + ty)
        bufferBackground[i], bufferForeground[i], bufferSymbol[i] = bg, fg, sym
      else
        currentBackground, currentForeground = bg, fg
        set(x1 + tx, y1 + ty, sym)
      end

      ::continue::
    end
  end
  ::loopend::

  if not canDirectlyCopy and not canPartialCopy then update() end
  return true
end

local function fill(x, y, w, h, symbol)
  checkMultiArg("number", x, y, w, h)
  checkArg(5, symbol, "string")

  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if len(symbol) ~= 1 or x > bufferWidth or y > bufferHeight or w < 1 or h < 1 then return false end

  for x1 = x, x + w - 1 do
    for y1 = y, y + h - 1 do
      set(x1, y1, symbol)
    end
  end
  return true
end

local function setResolution(w, h)
  checkMultiArg("number", w, h)
  
  local success = GPUsetResolution(w, h)
  if sucess then
    flush()
    GPUsetBackground(0)
    GPUfill(0, 0, w, h, " ")
  end
  return success
end

local function getResolution()
  return bufferWidth, bufferHeight
end

local function getWidth()
  return bufferWidth
end

local function getHeight()
  return bufferHeight
end

-- Raw method to set current background
-- to adapt to the background of x, y and
-- current foreground to blend
-- Optionally, blendBg can be set to false to
-- not use adapative background
-- Returns the character to use for the fill
local function setAdaptive(x, y, cfg, cbg, alpha, blendBg, blendBgalpha, symbol)
  -- Ignore if x, y not in screen buffer bounds
  if x < 1 or y < 1 or x > bufferWidth or y > bufferHeight then return "" end

  if alpha == 1 and blendBgalpha then
    if cbg ~= nil and cbg ~= false then setBackground(cbg) end
    if cfg ~= nil and cfg ~= false then setForeground(cfg) end
    return symbol
  end

  local bg, fg, sym = getRaw(x, y)

  if blendBg then
    if blendBgalpha then setBackground(color.blend(bg, cbg, 1 - alpha))
    else setBackground(color.getProminentColor(fg, bg, sym)) end
  end
  setForeground(color.blend(cfg, fg, alpha))

  -- If filling with a space it's better if one fills with the background symbol
  -- instead of losing accuracy by overwriting it with a space
  ::symbolcheck::
  if sym == nil then bg, fg, sym = getRaw(x, y) end -- Since the goto skips this line

  if symbol == " " then
    setForeground(color.blend(fg, cbg, 1 - alpha))
    return sym
  elseif symbol == "█" or symbol == "⣿" then  -- Full block doesn't blend with current background
    return symbol
  end
  return symbol -- Otherwise fill with the symbol
end

-- Screen drawing methods --
-- Important note: alpha is equal to alpha value, meaning 1 = visible, 0 = invisible --

-- Since all functions below basically do the same variable checking this
-- function takes care of it. Returns the following:
-- (should func return false), x, y, w, h, alpha, currentForegroundSave, currentBackgroundSave, cfg, cbg
local function processVariables(x, y, w, h, alpha, dontFloor)
  if alpha == 0 then return false end -- No alpha no render

  if not dontFloor then x, y, w, h = floor(x), floor(y), floor(w), floor(h) end
  if alpha == nil then alpha = 1 end

  checkMultiArg("number", x, y, w, h, alpha)

  local currentForegroundSave, currentBackgroundSave = currentForeground, currentBackground
  local cfg, cbg = normalizeColor(currentForeground), normalizeColor(currentBackground)
  return true, x, y, w, h, alpha, currentForegroundSave, currentBackgroundSave, cfg, cbg
end

-- For thin drawing functions often each point in a braille char is
-- checked with some function that returns either 0 or 1
local function brailleHelper(func, x, y, x0, y0, ...)
  return format.getBrailleChar(
    func(x,       y,        x0, y0, unpack({...})),
    func(x + 0.5, y,        x0, y0, unpack({...})),
    func(x,       y + 0.25, x0, y0, unpack({...})),
    func(x + 0.5, y + 0.25, x0, y0, unpack({...})),
    func(x,       y + 0.5,  x0, y0, unpack({...})),
    func(x + 0.5, y + 0.5,  x0, y0, unpack({...})),
    func(x,       y + 0.75, x0, y0, unpack({...})),
    func(x + 0.5, y + 0.75, x0, y0, unpack({...}))
  )
end

local function setSetAdaptive(x, y, cfg, cbg, alpha, blendBg, blendBgAlpha, symbol)
  set(x, y, setAdaptive(x, y, cfg, cbg, alpha, blendBg, blendBgAlpha, symbol))
end

local function rectangleOutlineHelper(x, y, w, h, alpha, tl, tr, bl, br, ht, hb, vl, vr, swapCfg, blendBg)
  local _, x, y, w, h, alpha, currentForegroundSave, currentBackgroundSave, cfg, cbg = processVariables(x, y, w, h, alpha)
  if not _ then return false end

  -- Corners
  if swapCfg then cfg = cbg end  -- All geometry should use background color
  setSetAdaptive(x, y, cfg, cbg, alpha, true, blendBg, tl)
  setSetAdaptive(x + w - 1, y, cfg, cbg, alpha, true, blendBg, tr)
  setSetAdaptive(x, y + h - 1, cfg, cbg, alpha, true, blendBg, bl)
  setSetAdaptive(x + w - 1, y + h - 1, cfg, cbg, alpha, true, blendBg, br)

  -- Top and bottom
  for x1 = x + 1, x + w - 2 do
    setSetAdaptive(x1, y, cfg, cbg, alpha, true, blendBg, ht)
    setSetAdaptive(x1, y + h - 1, cfg, cbg, alpha, true, blendBg, hb)
  end

  -- Sides
  for y1 = y + 1, y + h - 2 do
    setSetAdaptive(x, y1, cfg, cbg, alpha, true, blendBg, vl)
    setSetAdaptive(x + w - 1, y1, cfg, cbg, alpha, true, blendBg, vr)
  end

  -- Reset original bg / fg colors
  currentBackground, currentForeground = currentBackgroundSave, currentForegroundSave
  return true
end

-- Draw a rectangle (border) with current bg color,
-- with optional alpha
local function drawRectangleOutline(x, y, w, h, alpha, symbol)
  checkArg(6, symbol, "string", "nil")
  symbol = symbol or " "
  return rectangleOutlineHelper(x, y, w, h, alpha, symbol, symbol, symbol, symbol, symbol, symbol, symbol, symbol, false, true)
end

-- Fill a rectangle with the current bg color,
-- with optional alpha. Because of alpha
-- we have to reimplement fill code
local function drawRectangle(x, y, w, h, alpha, symbol)
  local _, x, y, w, h, alpha, currentForegroundSave, currentBackgroundSave, cfg, cbg = processVariables(x, y, w, h, alpha)
  if not _ then return false end

  checkArg(6, symbol, "string", "nil")
  symbol = symbol or " "

  for x1 = x, x + w - 1 do
    for y1 = y, y + h - 1 do
      if x1 < 1 or y1 < 1 or x1 > bufferWidth then goto continue end
      if y1 > bufferHeight then break end
      
      setSetAdaptive(x1, y1, cfg, cbg, alpha, true, true, symbol)
      ::continue::
    end
  end

  -- Reset original bg / fg colors
  currentBackground, currentForeground = currentBackgroundSave, currentForegroundSave
  return true
end

-- Draw a rectangle (border) with current bg color,
-- with optional alpha
local function drawThinRectangleOutline(x, y, w, h, alpha)
  return rectangleOutlineHelper(x, y, w, h, alpha, "┌", "┐", "└", "┘", "─", "─", "│", "│", true, false)
end

local function drawBrailleRectangleOutline(x, y, w, h, alpha)
  return rectangleOutlineHelper(x, y, w, h, alpha, "⡏", "⢹", "⣇", "⣸", "⠉", "⣀", "⡇", "⢸", true, false)
end

local function subRectangleHelper(x1, y1, x, y, w, h)
  if x1 >= x and x1 < x + w and y1 >= y and y1 < y + h then return 1 end
  return 0
end

-- Fill a rectangle with the current bg color,
-- with optional alpha. Because of alpha
-- we have to reimplement fill code
local function drawBrailleRectangle(x, y, w, h, alpha)
  local _, x, y, w, h, alpha, currentForegroundSave, currentBackgroundSave, cfg, cbg = processVariables(x, y, w, h, alpha, true)
  if not _ then return false end

  local subChar
  cfg = cbg -- Use background color for all drawing

  for x1 = floor(x), floor(x + w) do
    for y1 = floor(y), floor(y + h) do
      if x1 < 1 or y1 < 1 or x1 > bufferWidth then goto continue end
      if y1 > bufferHeight then break end

      subChar = brailleHelper(subRectangleHelper, x1, y1, x, y, w, h)
      setSetAdaptive(x1, y1, cfg, cbg, alpha, true, false, subChar)
      ::continue::
    end
  end

  -- Reset original bg / fg colors
  currentBackground, currentForeground = currentBackgroundSave, currentForegroundSave
  return true
end

-- Draw a string at the location (Straight line, newlines ignore)
-- If alpha is enabled, foreground is blended w/ bg
-- If blendBg is enabled, the background will be selected to try
-- to camouflage itself with the existing buffer
local function drawText(x, y, string, alpha, blendBg)
  if alpha == 0 then return false end -- No alpha no render
  if blendBg == nil then blendBg = true end
  x, y = floor(x), floor(y)

  if y < 1 or y > bufferHeight then return end

  -- Save current colors
  local currentForegroundSave, currentBackgroundSave = currentForeground, currentBackground
  local cfg, cbg = normalizeColor(currentForeground), normalizeColor(currentBackground)
  if alpha == nil then alpha = 1 end

  checkMultiArg("number", x, y)
  checkArg(3, string, "string")
  checkArg(4, alpha, "number")
  checkArg(5, blendBg, "boolean")

  for dx = 0, len(string) - 1 do
    if x < 1 then goto continue end
    if x > bufferWidth then break end

    setSetAdaptive(x + dx, y, cfg, cbg, alpha, blendBg, false, sub(string, dx + 1, dx + 1))
    ::continue::
  end

  -- Reset original bg / fg colors
  currentBackground, currentForeground = currentBackgroundSave, currentForegroundSave
  return true
end

local function ellipseHelper(x, y, a, b, alpha, outlineOnly, symbol)
  local _, x, y, a, b, alpha, currentForegroundSave, currentBackgroundSave, cfg, cbg = processVariables(x, y, a, b, alpha, false)
  if not _ then return false end

  checkArg(6, symbol, "string", "nil")
  symbol = symbol or " "

  if outlineOnly then
    local thetaInc = 1 / max(a + 1, b + 1)
    local dx1, dy1, prevdx1, prevdy1
    local halfpi = 0.5 * math.pi

    for theta = 0, halfpi - thetaInc, thetaInc do
      dx1 = floor(cos(theta) * a)
      dy1 = floor(sin(theta) * b)

      -- Overlapping point
      if dx1 == prevdx1 and dy1 == prevdy1 then goto continue end
      prevdx1, prevdy1 = dx1, dy1

      -- x1, y1 is in first quadrent, use symmetry
      setSetAdaptive(x + dx1, y + dy1, cfg, cbg, alpha, true, true, symbol)
      setSetAdaptive(x - dx1, y + dy1, cfg, cbg, alpha, true, true, symbol)

      -- Avoid overlap on x-sides
      if dy1 ~= 0 then
        setSetAdaptive(x + dx1, y - dy1, cfg, cbg, alpha, true, true, symbol)
        setSetAdaptive(x - dx1, y - dy1, cfg, cbg, alpha, true, true, symbol)
      end
      ::continue::
    end

    -- Fill in caps on top and bottom, since there is overlap and we subtracted thetaInc from loop
    setSetAdaptive(x, y + b, cfg, cbg, alpha, true, true, symbol)
    setSetAdaptive(x, y - b, cfg, cbg, alpha, true, true, symbol)
  else
    local a2, b2 = a * a, b * b -- Store the axis squared
    local computedBound

    for dx = 0, a do
    for dy = 0, b do
      computedBound = dx * dx / a2 + dy * dy / b2
      if computedBound > 1 then goto continue end

      -- First quadrent
      setSetAdaptive(x + dx, y + dy, cfg, cbg, alpha, true, true, symbol)
      -- If dx = 0 and dy = 0 then don't draw any other quadrent to avoid overlap
      if dx == 0 and dy == 0 then -- Do nothing
      -- If dx = 0 then don't draw left side of ellipse to avoid overlap
      elseif dx == 0 then
        setSetAdaptive(x + dx, y - dy, cfg, cbg, alpha, true, true, symbol)
      -- If dy = 0 then don't draw bottom half to avoid overlap
      elseif dy == 0 then
        setSetAdaptive(x - dx, y + dy, cfg, cbg, alpha, true, true, symbol)
      -- Draw all other quadrents
      else
        setSetAdaptive(x - dx, y + dy, cfg, cbg, alpha, true, true, symbol)
        setSetAdaptive(x + dx, y - dy, cfg, cbg, alpha, true, true, symbol)
        setSetAdaptive(x - dx, y - dy, cfg, cbg, alpha, true, true, symbol)
      end
      ::continue::
    end end
  end

  -- Reset original bg / fg colors
  currentBackground, currentForeground = currentBackgroundSave, currentForegroundSave
  return true
end

local function drawEllipseOutline(x, y, a, b, alpha, symbol)
  return ellipseHelper(x, y, a, b, alpha, true, symbol)
end

local function drawEllipse(x, y, a, b, alpha, symbol)
  ellipseHelper(x, y, a, b, alpha, false, symbol)
end

-- Sub ellipse pixel helper function
-- Returns 0 if outside ellipse else 1
-- x1, y1 is current point
-- x, y is ellipse center
-- a2, b2 is the axii squared
local function subEllipseHelper(x1, y1, x, y, a2, b2, onEllipse) -- a2 = a^2, b2 = b^2
  -- If we're just doing an outline check distance = 1 (on ellipse)
  if onEllipse then
    -- For the given y1 value we'd expect a point at x1 = x - (sqrt(a2) sqrt(b2 - y^2 + 2 y y1 - y1^2))/sqrt(b2)
    local expectedX = x - (sqrt(a2) * sqrt(b2 - y * y + 2 * y * y1 - y1 * y1)) / sqrt(b2)
    expectedX = floor(expectedX * 2) / 2 -- Round to nearest 0.5

    if x1 == expectedX then return 1 end
    if x + x - x1 == expectedX then return 1 end -- Since quadratic there are 2 x1s that satisfy

    -- Since there could be multiple x values for a given y, we also need to check
    -- expected y, which is y1 = y - (sqrt(b2) sqrt(a2 - x^2 + 2 x x1 - x1^2))/sqrt(a2)
    local expectedY = y - (sqrt(b2) * sqrt(a2 - x * x + 2 * x * x1 - x1 * x1)) / sqrt(a2)

    expectedY = floor(expectedY * 4) / 4 -- Round to nearest 0.25
    if y1 == expectedY then return 1 end
    if y + y - y1 == expectedY then return 1 end -- Since quadratic there are 2 y1s that satisfy

    return 0
  end

  local dis = (x1 - x) * (x1 - x) / a2 + (y1 - y) * (y1 - y) / b2
  if dis > 1 then return 0 end
  return 1
end

local function subEllipseTemplate(x, y, a, b, alpha, justOutline)
  local _, x, y, a, b, alpha, currentForegroundSave, currentBackgroundSave, cfg, cbg = processVariables(x, y, a, b, alpha, true)
  if not _ then return false end

  local a2, b2 = a * a, b * b -- Store the axis squared
  local a2minus1, b2minus1 = (a - 1) * (a - 1), (b - 1) * (b - 1)
  local interiorDistance, subChar, charToDraw

  -- Directly fill if area is large enough
  for x1 = floor(x - a), floor(x + a) do
  for y1 = floor(y - b), floor(y + b) do
    if y1 > bufferHeight then break end
    if x1 < 1 or y1 < 1 or x1 > bufferWidth then goto continue end

    -- More efficent to do additional comparison for interior, to skip
    -- 8 subEllipseHelper calls for a full braille character
    interiorDistance = (x1 - x) * (x1 - x) / a2minus1 + (y1 - y) * (y1 - y) / b2minus1
    if interiorDistance <= 1 then
      if justOutline then subChar = " "
      else subChar = "⣿" end
    else
      -- Iterate "subpixels"
      subChar = brailleHelper(subEllipseHelper, x1, y1, x, y, a2, b2, justOutline)
    end
    if subChar == "⠀" or subChar == " " then goto continue end -- Skip empty braille or space
    
    -- Same as drawText but without the checks
    currentForegroundSave, currentBackgroundSave = currentForeground, currentBackground
    cfg, cbg = normalizeColor(currentForeground), normalizeColor(currentBackground)

    if subChar == "⣿" then
      -- Filler in the middle of the ellipse, we can fill with a space
      -- and use default set adaptive behaviour

      subChar = " "
      currentBackground = currentForeground
      setSetAdaptive(x1, y1, cfg, cbg, alpha, true, true, subChar)
    else
      -- Side bars should have the background equal to the blended value
      -- However since braille is filled with foreground we swap bg and fg
      -- and set the bg to whatever the current bg is at that value

      charToDraw = setAdaptive(x1, y1, cfg, cbg, alpha, true, true, subChar)

      -- Just outline ellipse stuff needs proper color blending
      if justOutline then
        currentForeground = color.blend(currentBackgroundSave, getRaw(x1, y1), alpha)
      else currentForeground = currentBackground end

      currentBackground = getRaw(x1, y1)
      set(x1, y1, charToDraw)
    end
    
    currentBackground, currentForeground = currentBackgroundSave, currentForegroundSave
    ::continue::
  end end
  return true
end

local function drawBrailleEllipse(x, y, a, b, alpha)
  return subEllipseTemplate(x, y, a, b, alpha, false)
end

local function drawBrailleEllipseOutline(x, y, a, b, alpha)
  return subEllipseTemplate(x, y, a, b, alpha, true)
end

local function lineHelper(x1, y1, x2, y2, alpha, vertLineFunc, horzLineFunc, gtHalfLineFunc, ltHalfLineFunc)
  if alpha == 0 then return false end -- No alpha no render
  if alpha == nil then alpha = 1 end

  checkMultiArg("number", x1, y1, x2, y2, alpha)

  if x2 < x1 then -- Swap coordinates if needed
    x1, x2, y1, y2 = x2, x1, y2, y1
  end

  local cfg, cbg = normalizeColor(currentForeground), normalizeColor(currentBackground)
  local currentForegroundSave, currentBackgroundSave = currentForeground, currentBackground

  -- Vertical lines
  if x1 == x2 then
    if y1 > y2 then y1, y2 = y2, y1 end -- Swap if not in right order
    for y = y1, y2 - 1 do
      if y > bufferHeight or y < 1 then goto continue end
      vertLineFunc(x1, y, cfg, cbg, alpha, x1, y1, 0, currentBackgroundSave, currentForegroundSave)
      ::continue::
    end
    -- Reset original bg / fg colors
    currentBackground, currentForeground = currentBackgroundSave, currentForegroundSave
    return true
  end

  -- Horziontal lines
  if y1 == y2 then
    for x = x1, x2 - 1 do
      if x < 1 then goto continue end
      if x > bufferWidth then break end
      horzLineFunc(x, y1, cfg, cbg, alpha, x1, y1, 0, currentBackgroundSave, currentForegroundSave)
      ::continue::
    end
    -- Reset original bg / fg colors
    currentBackground, currentForeground = currentBackgroundSave, currentForegroundSave
    return true
  end

  local gradient = (y2 - y1) / (x2 - x1)
  
  if abs(gradient) > 0.5 then
    if y1 > y2 then x1, x2, y1, y2 = x2, x1, y2, y1 end -- Swap if not in right order
    local x -- Store x coordinate to set
    for y = 0, ceil(y2 - y1 - 1) do
      x = floor(y / gradient + x1)
      if y + y1 < 1 or y + y1 > bufferHeight or x > bufferWidth or x < 1 then goto continue end
      gtHalfLineFunc(x, y + y1, cfg, cbg, alpha, x1, y1, gradient, currentBackgroundSave, currentForegroundSave)
      ::continue::
    end
  else
    local y -- Store y coordinate to set
    for x = 0, ceil(x2 - x1 - 1) do
      y = floor(gradient * x + y1)
      if y < 1 or y > bufferHeight or x + x1 > bufferWidth or x + x1 < 1 then goto continue end
      ltHalfLineFunc(x + x1, y, cfg, cbg, alpha, x1, y1, gradient, currentBackgroundSave, currentForegroundSave)
      ::continue::
    end
  end

  -- Reset original bg / fg colors
  currentBackground, currentForeground = currentBackgroundSave, currentForegroundSave
  return true
end

local function drawLine(x1, y1, x2, y2, alpha, lineChar)
  x1, x2, y1, y2 = floor(x1), floor(x2), floor(y1), floor(y2)
  lineChar = lineChar or " "
  checkArg(6, lineChar, "string", "nil")

  local function genericLineFunc(x, y, cfg, cbg, alpha)
    setSetAdaptive(x, y, cfg, cbg, alpha, true, true, lineChar)
  end
  return lineHelper(x1, y1, x2, y2, alpha, genericLineFunc, genericLineFunc, genericLineFunc, genericLineFunc)
end

-- Returns 1 if x, y is on the line, else 0
-- Note this differs from other functions, as
-- x1, y1 is lefmost point of the line, and x, y
-- is the current point
local function subLineHelper(x, y, x1, y1, gradient)
  if abs(gradient) > 0.5 then
    local expectedX = (y - y1) / gradient + x1
    expectedX = floor(expectedX * 2) / 2
    if expectedX == x then return 1 end
    return 0
  else
    local expectedY = (x - x1) * gradient + y1
    expectedY = floor(expectedY * 4) / 4
    if expectedY == y then return 1 end
    return 0
  end
end

-- More helper functions for sub line to reduce code copy-paste
-- Performance is slightly impacted but it's not noticable
-- plus it saves a kilobyte of storage / ram to load this module
local function genericSubLineFunc(x, y, cfg, cbg, alpha, char, currentBackgroundSave, currentForegroundSave)
  currentForeground = color.blend(currentBackgroundSave, getRaw(x, y), alpha)
  currentBackground = getRaw(x, y)

  set(x, y, char)
  ::continue::
end

local function subLineSlopeHelperFunc(x, y, cfg, cbg, alpha, x1, y1, gradient, currentBackgroundSave, currentForegroundSave, useDx)
  local x2, y2 = x, y
  local charToDraw, subChar

  for delta = -1, 1 do -- Margin of error to fix gaps on steep lines
    if useDx then x2 = x + delta
    else y2 = y + delta end
    subChar = brailleHelper(subLineHelper, x2, y2, x1, y1, gradient)
    if subChar ~= "⠀" then
      charToDraw = setAdaptive(x2, y2, cfg, cbg, alpha, true, true, subChar)
      currentForeground = color.blend(currentBackgroundSave, getRaw(x2, y2), alpha)
      currentBackground = getRaw(x2, y2)
      set(x2, y2, charToDraw)
    end
  end
end
local function subLineGtHalf(x, y, cfg, cbg, alpha, x1, y1, gradient, currentBackgroundSave, currentForegroundSave)
  subLineSlopeHelperFunc(x, y, cfg, cbg, alpha, x1, y1, gradient, currentBackgroundSave, currentForegroundSave, true)
end
local function subLineLtHalf(x, y, cfg, cbg, alpha, x1, y1, gradient, currentBackgroundSave, currentForegroundSave)
  subLineSlopeHelperFunc(x, y, cfg, cbg, alpha, x1, y1, gradient, currentBackgroundSave, currentForegroundSave)
end

-- Draw a line (Using braille characters)
-- from 1 point to another, optionally with alpha
local function drawBrailleLine(x1, y1, x2, y2, alpha)
  x1, y1, x2, y2 = floor(2 * x1) / 2, floor(4 * y1) / 4, floor(2 * x2) / 2, floor(4 * y2) / 4
  local charToDraw

  if y1 == y2 then
    charToDraw = "⠉"
    if y1 - floor(y1) ~= 0 then charToDraw = "⠒" end
  elseif x1 == x2 then
    charToDraw = "⡇"
    if x1 - floor(x1) ~= 0 then charToDraw = "⢸" end
  end

  local function horzVertFunc(x, y, cfg, cbg, alpha, _1, _2, _3, currentBackgroundSave, currentForegroundSave)
    genericSubLineFunc(x, y, cfg, cbg, alpha, charToDraw, currentBackgroundSave, currentForegroundSave)
  end
  return lineHelper(x1, y1, x2, y2, alpha, horzVertFunc, horzVertFunc, subLineGtHalf, subLineLtHalf)
end

-----------------------------------------------------------
-- Buffer functions
local function getCurrentBuffer()
	return bufferBackground, bufferForeground, bufferSymbol
end

local function getChangeBuffer()
	return changeBackgrounds, changeForegrounds, changeSymbols
end

local function rawGet(index)
  checkArg(1, index, "number")
  return bufferBackground[index], bufferForeground[index], bufferSymbol[index]
end

local function rawSet(index, background, foreground, symbol)
  checkMultiArg("number", index, background, foreground)
  checkArg(4, symbol, "string")
  changeBackgrounds[index], changeForegrounds[index], changeSymbols[index] = background, foreground, symbol
end

-- Clear the screen by filling with colored whitespace chars --
local function clear(color, alpha)
  checkArg(1, color, "number", "nil")
  checkArg(2, alpha, "number", "nil")

  setBackground(color or 0x0)
  drawRectangle(1, 1, bufferWidth, bufferHeight, alpha, " ")

  updateBoundX1, updateBoundX2 = 1, bufferWidth
  updateBoundY1, updateBoundY2 = 1, bufferHeight
end

-- Set GPU Proxy for the screen --
local function setGPUProxy(gpu)
  -- Define local variables
  gpuProxy = gpu
  GPUfill, GPUset, GPUcopy = gpu.fill, gpu.set, gpu.copy
  GPUsetBackground, GPUsetForeground = gpu.setBackground, gpu.setForeground
  GPUgetBackground, GPUgetForeground = gpu.getBackground, gpu.getForeground
  GPUgetResolution, GPUsetResolution = gpu.getResolution, gpu.setResolution
  GPUgetPaletteColor = gpu.getPaletteColor
  GPUsetPaletteColor = gpu.setPaletteColor

  -- Prefill buffer
  flush()
end

-- Get GPU Proxy for the screen --
local function getGPUProxy()
  return gpuProxy
end

-- Bind the gpu proxy to a screen address --
local function bind(screenAddress, reset)
  local success, reason = gpuProxy.bind(address, reset)
	if success then
		if reset then setResolution(gpuProxy.maxResolution())
    else setResolution(bufferWidth, bufferHeight) end
  end
  return success, reason
end

-- Reset the palette to OpenOS defaults
local function resetPalette()
  local n -- Temp variable
  for i = 0, 15 do
    n = 16 * i + (15 - i)
    GPUsetPaletteColor(i, n + 256 * n + 65536 * n)
  end
end

-- Set gpu proxy
setGPUProxy(gpuProxy)

return {
  setGPUProxy = setGPUProxy,
  getGPUProxy = getGPUProxy,
  bind = bind,
  flush = flush,
  clear = clear,
  setChar = setChar,

  update = update,
  getRaw = getRaw,
  getIndex = getIndex,
  getCoords = getCoords,
  getCurrentBuffer = getCurrentBuffer,
  getChangeBuffer = getChangeBuffer,
  setDrawingBound = setDrawingBound,
  getDrawingBound = getDrawingBound,
  resetDrawingBound = resetDrawingBound,
  resetPalette = resetPalette,

  rawGet = rawGet,
  rawSet = rawSet,

  setBackground = setBackground,
  setForeground = setForeground,
  getBackground = getBackground,
  getForeground = getForeground,
  set = set,
  copy = copy,
  fill = fill,
  setResolution = setResolution,
  getResolution = getResolution,
  getWidth = getWidth,
  getHeight = getHeight,

  drawRectangleOutline = drawRectangleOutline,
  drawRectangle = drawRectangle,
  drawThinRectangleOutline = drawThinRectangleOutline,
  drawBrailleRectangle = drawBrailleRectangle,
  drawBrailleRectangleOutline = drawBrailleRectangleOutline,
  drawText = drawText,
  drawLine = drawLine,
  drawEllipseOutline = drawEllipseOutline,
  drawEllipse = drawEllipse,
  drawBrailleLine = drawBrailleLine,
  drawBrailleEllipse = drawBrailleEllipse,
  drawBrailleEllipseOutline = drawBrailleEllipseOutline
}
