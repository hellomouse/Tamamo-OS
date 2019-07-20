-- Double Buffered Magic --
local component = require("component")
local unicode = require("unicode")
local color = require("color")
local format = require("format")

local gpu = component.gpu

-- Buffer which stores all the changes
-- that are to be displayed on the screen
local bufferWidth, bufferHeight
local buffBg, buffFg, buffSym
local changeBg, changeFg, changeSym

-- Limits for drawing on the buffer, to avoid 
-- checking for excessive changes (Bounds rectangle where changes occured)
local updateBoundX1, updateBoundY1, updateBoundX2, updateBoundY2 = 0, 0, bufferWidth, bufferHeight

-- True "bounding box", anything outside won't be rendered
local drawX1, drawY1, drawX2, drawY2

-- Current fg / bg colors for set and fill
local currentBg, currentFg = 0, 0xFFFFFF

-- Optimization for lua / gpu proxying
local gpuProxy, GPUfill, GPUset, GPUsetBackground, GPUsetForeground
local GPUgetResolution, GPUsetResolution, GPUgetPaletteColor, GPUcopy, GPUsetResolution, GPUsetPaletteColor
local GPUgetBackground, GPUgetForeground

local rep = string.rep
local sub = unicode.sub
local floor = math.floor
local len = unicode.len
local min = math.min
local max = math.max
local abs = math.abs
local sqrt = math.sqrt

-- Constants
local fillIfAreaIsGreaterThan = 40
local setToFillRatio = 2 -- Ratio of max set() calls / fill() calls per tick, defined in card

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
local function areEqual(sym, changesym, bg, changebg, fg, changefg)
  -- If symbols don't match or backgrounds match always unequal
  if sym ~= changesym or bg ~= changebg then return false end
  if sym == " " or sym == "⠀" then return true end -- 2nd is unicode 0x2800, not regular space
  return fg == changefg
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

-- Set the drawing bounds. If useCurrent is true it will take the min
-- of the current bound and the updated bound
local function setDrawingBound(x1, y1, x2, y2, useCurrent)
  -- If no arguments are passed reset to full screen
  if x1 == nil then
    drawX1, drawY1, drawX2, drawY2 = 1, 1, bufferWidth, bufferHeight
    return
  end

  checkArg(1, x1, "number")
  checkArg(2, y1, "number")
  checkArg(3, x2, "number")
  checkArg(4, y2, "number")

  if useCurrent then
    -- Take the intersection of rectangles defined by the corners
    -- (drawX1, drawY1), (drawX2, drawY2) and (x1, y1), (x2, y2)
    local x3, y3, x4, y4
    x3 = max(drawX1, x1)
    y3 = max(drawY1, y1)
    x4 = min(drawX2, x2)
    y4 = min(drawY2, y2)

    if x3 < x4 and y3 < y4 then
      drawX1, drawY1, drawX2, drawY2 = x3, y3, x4, y4
    end
  else
    -- Overwrite any changes
    drawX1, drawY1, drawX2, drawY2 = x1, y1, x2, y2
  end

  -- Bound checks
  if drawX1 < 1 then drawX1 = 1 end
  if drawX2 > bufferWidth then drawX2 = bufferWidth end
  if drawY1 < 1 then drawY1 = 1 end
  if drawY2 > bufferHeight then drawY2 = bufferHeight end

  -- Invalid corners (x1, y1) must be top left corner
  if drawX1 >= drawX2 or drawY1 >= drawY2 then
    error("Invalid drawing bounds, the rectangle defined by corners (" .. drawX1 .. ", " .. drawY1 .. 
      "), (" .. drawX2 .. ", " .. drawY2 .. ") is not valid (First corner must be top left)")
  end
end

local function resetDrawingBound()
  drawX1, drawY1, drawX2, drawY2 = 0, 0, bufferWidth, bufferHeight
end

-- Getter for drawing bounds
local function getDrawingBound()
  return drawX1, drawY1, drawX2, drawY2
end

-- Set GPU Proxy for the screen --
function setGPUProxy(gpu)
  -- Define local variables
  gpuProxy = gpu
  GPUfill, GPUset, GPUcopy = gpu.fill, gpu.set, gpu.copy
  GPUsetBackground, GPUsetForeground = gpu.setBackground, gpu.setForeground
  GPUgetBackground, GPUgetForeground = gpu.getBackground, gpu.getForeground
  GPUgetResolution, GPUsetResolution = gpu.getResolution, gpu.setResolution
  GPUgetPaletteColor = gpu.getPaletteColor
  GPUsetPaletteColor = gpu.setPaletteColor

  -- Override GPU API
  gpu.set, gpu.copy, gpu.fill = set, copy, fill
  gpu.setBackground, gpu.setForeground = setBackground, setForeground
  gpu.getBackground, gpu.getForeground = getBackground, getForeground
  gpu.setResolution, gpu.getResolution = setResolution, getResolution

  -- Prefill buffer
  flush()
end

-- Get GPU Proxy for the screen --
function getGPUProxy()
  return gpuProxy
end

-- Bind the gpu proxy to a screen address --
function bind(screenAddress, reset)
  local success, reason = gpuProxy.bind(address, reset)
	if success then
		if reset then setResolution(gpuProxy.maxResolution())
    else setResolution(bufferWidth, bufferHeight) end
  end
  return success, reason
end

-- Flush the buffer and re-create each array --
function flush(w, h)
  if w == nil or h == nil then
    w, h = GPUgetResolution()
  end
  checkArg(1, w, "number")
  checkArg(1, h, "number")

  bufferWidth = w
  bufferHeight = h

  updateBoundX1, updateBoundX2 = w, 0
  updateBoundY1, updateBoundY2 = h, 0

  buffBg, buffFg, buffSym = {}, {}, {}
  changeBg, changeFg, changeSym = {}, {}, {}
  drawX1, drawY1, drawX2, drawY2 = 0, 0, bufferWidth, bufferHeight

  -- Prefill the buffers to avoid rehashing (-17 is transparent) --
  for i = 1, w * h do
    buffBg[i], buffFg[i], buffSym[i] = 0, 0, " "
    -- changeBg[i], changeFg[i], changeSym[i] = -17, -17, " "
  end
end

-- Reset the palette to OpenOS defaults
function resetPalette()
  GPUsetPaletteColor(0, 0x0F0F0F)
  GPUsetPaletteColor(1, 0x1E1E1E)
  GPUsetPaletteColor(2, 0x2D2D2D)
  GPUsetPaletteColor(3, 0x3C3C3C)
  GPUsetPaletteColor(4, 0x4B4B4B)
  GPUsetPaletteColor(5, 0x5A5A5A)
  GPUsetPaletteColor(6, 0x696969)
  GPUsetPaletteColor(7, 0x787878)
  GPUsetPaletteColor(8, 0x878787)
  GPUsetPaletteColor(9, 0x969696)
  GPUsetPaletteColor(10, 0xA5A5A5)
  GPUsetPaletteColor(11, 0xB4B4B4)
  GPUsetPaletteColor(12, 0xC3C3C3)
  GPUsetPaletteColor(13, 0xD2D2D2)
  GPUsetPaletteColor(14, 0xE1E1E1)
  GPUsetPaletteColor(15, 0xF0F0F0)
end

-- Clear the screen by filling with black whitespace chars --
function clear(color)
  if color == nil then color = 0x0 end

  checkArg(1, color, "number")
  setBackground(color)
  fill(0, 0, bufferWidth, bufferHeight, " ")

  updateBoundX1, updateBoundX2 = w, 0
  updateBoundY1, updateBoundY2 = h, 0
end

-- Set a specific character (internal method) --
function setChar(x, y, fgColor, bgColor, symbol, isPalette1, isPalette2)
  if x < drawX1 or x > drawX2 or y < drawY1 or y > drawY2 then return false end
  if len(symbol) ~= 1 then return false end

  -- Don't check arg types in this function as this function is used A LOT
  -- internally and checking args actually slows down a full screen render
  -- by up to 100 ms

  local i = getIndex(x, y)

  -- Update draw bounds if needed
  if x < updateBoundX1 then updateBoundX1 = x end
  if x > updateBoundX2 then updateBoundX2 = x end
  if y < updateBoundY1 then updateBoundY1 = y end
  if y > updateBoundY2 then updateBoundY2 = y end

  -- We'll represent palette indexes with negative numbers - 1
  -- ie palette index 3 is saved as -4
  if isPalette1 then fgColor = -fgColor - 1 end
  if isPalette2 then bgColor = -bgColor - 1 end

  changeBg[i], changeFg[i], changeSym[i] = bgColor, fgColor, symbol
end


-- Write changes to the screen
function update(force)
   -- Force update all bounds
  if force then
    updateBoundX1, updateBoundY1, updateBoundX2, updateBoundY2 = 1, 1, bufferWidth, bufferHeight
  end

  -- If there have been no changes then ignore
  if updateBoundX1 > updateBoundX2 or updateBoundY1 > updateBoundY2 then return end

  -- i = current index
  -- lineChange = index increment when changing to next y value
  -- fillw = Width of repeated length of background colors
  -- subgroup = the foreground subgroup of the background dict
  -- searchX = x value of end of repeated length
  -- searchIndex = index of end of repeated length
  -- currBg = temp var to store bg for current index since change buffer gets reset
  -- charCount = character counter for repeated string optimization
  -- j = temp loop variable
  -- colorChanges = dict of bg / fg color pixels grouped togther
  -- transparentChange = variable to track if any change vector is transparent
  -- noEmptySpaces = variable to track if there are not any empty spaces (no foreground chars)
  local i = getIndex(updateBoundX1, updateBoundY1)
  local lineChange = bufferWidth - updateBoundX2 + updateBoundX1 - 1
  local fillw, subgroup, searchX, searchIndex, currBg, charcount, j
  local colorChanges = {}
  local aFgValue = nil

  for y = updateBoundY1, updateBoundY2 do
		x = updateBoundX1
    while x <= updateBoundX2 do
      if changeBg[i] == nil or changeBg[i] == -17 or changeFg[i] == -17 then
      -- Ignore transparent characters
      -- If char is same as buffer below don't update it
      -- unless the force parameter is true.
      elseif force or not areEqual(buffSym[i], changeSym[i], buffBg[i], changeBg[i], buffFg[i], changeFg[i]) then
        searchX = x + 1
        searchIndex = i + 1
        
        buffSym[i], buffBg[i], buffFg[i] = changeSym[i], changeBg[i], changeFg[i]

        -- Spaces don't need a foreground, assign filler value (black foreground)
        -- First space below is unicode char 0x2800 (not a regular space)
        if buffSym[i] == "⠀"  or buffSym[i] == " " then
          -- All "space" chars don't render a foreground color, so
          -- we set them all equal to 1 foreground to minimize redundant
          -- setForeground() calls
          if aFgValue == nil then aFgValue = buffFg[i] 
          else buffFg[i] = aFgValue end
        end 

        -- Search for repeating chunks of characters of the same
        -- background
        while searchX <= updateBoundX2 do
          if not areEqual(1, 1, changeBg[i], changeBg[searchIndex], 1, 1) then break end

          -- Update current "image" buffer
          buffSym[searchIndex], buffBg[searchIndex], buffFg[searchIndex] = 
            changeSym[searchIndex], changeBg[searchIndex], changeFg[searchIndex]
          searchX = searchX + 1
          searchIndex = searchIndex + 1
        end

        fillw = searchX - x

        -- Create a dictionary by the background, then a sub
        -- dictionary of the foreground colors containing the points
        -- needed to draw. That way we minimize the number of setBackground
        -- and setForeground calls
        if colorChanges[changeBg[i]] == nil then colorChanges[changeBg[i]] = {} end
        currBg = changeBg[i]

        j = i
        while j <= i + fillw - 1 do
          if colorChanges[currBg][changeFg[j]] == nil then
            colorChanges[currBg][changeFg[j]] = {}
          end

          subgroup = colorChanges[currBg][changeFg[j]]
          
          -- Check for repeated strings
          charcount = 1
          for k = j + 1, i + fillw - 1 do
            if not areEqual(buffSym[j], changeSym[k], buffBg[j], changeBg[k], buffFg[j], changeFg[k]) then
              break
            end
            charcount = charcount + 1

            -- Change buffer reset
            changeBg[k], changeFg[k], changeSym[k] = -17, -17, " "
          end
          
          subgroup[#subgroup + 1] = {x + j - i, y, changeSym[j], charcount}

          -- Reset the change buffer
          changeBg[j], changeFg[j], changeSym[j] = -17, -17, " "
          j = j + charcount
        end

        -- Increment x and i up to searchX - 1
        -- (Since there is a +1 below)
        x = searchX - 1
        i = i + fillw - 1
      end

      ::renderoptimizationend::

      -- This is required to avoid infinite loops
      -- when buffers are the same
      x = x + 1
      i = i + 1
    end

    i = i + lineChange
  end

  -- Draw color groups
  local t -- Temp variable
  local setCounter = 0
  local fillCounter = 1

  for bgcolor, group1 in pairs(colorChanges) do
    GPUsetBackground(absColor(bgcolor), bgcolor < 0)

    for fgcolor, group2 in pairs(group1) do
      -- In the event a color is just spaces there is no need to
      -- do a foreground call
      if #group2 == 1 and (group2[1] == "⠀" or group2[1] == " ") then -- Do nothing
      else GPUsetForeground(absColor(fgcolor), fgcolor < 0) end

      for i = 1, #group2 do
        t = group2[i]

        if t[3] == "⠀" or t[3] == " " then -- First is braille 0x2800
          -- If spaces then use fill as it is less energy intensive
          if t[4] > 1 then
            GPUfill(t[1], t[2], t[4], 1, " ")
            fillCounter = fillCounter + 1
            goto continue
          end
        end

        -- Use fill or set depending on setToFillRatio to try to max out
        -- free gpu calls before they are queued to next tick
        if setCounter <= fillCounter * setToFillRatio then
          GPUset(t[1], t[2], rep(t[3], t[4]))
          setCounter = setCounter + 1
        else 
          GPUfill(t[1], t[2], t[4], 1, t[3]) 
          fillCounter = fillCounter + 1
        end

        ::continue::
      end
    end
  end

  -- Reset the drawX drawY bounds to largest / smallest possible
  updateBoundX1, updateBoundX2 = bufferWidth, 0
  updateBoundY1, updateBoundY2 = bufferHeight, 0 
  changeBg, changeFg, changeSym = {}, {}, {}
end

-- Raw get for buffer values
local function getRaw(x, y, dontNormalize)
  local index = getIndex(x, y)

  if changeBg[index] ~= nil and changeBg[index] ~= -17 and changeFg[index] ~= -17 then
    if dontNormalize then return changeBg[index], changeFg[index], changeSym[index] end
    return normalizeColor(changeBg[index]), normalizeColor(changeFg[index]), changeSym[index]
  end

  if dontNormalize then return buffBg[index], buffFg[index], buffSym[index] end
  return normalizeColor(buffBg[index]), normalizeColor(buffFg[index]), buffSym[index]
end

-- Additional functions for the screen

-- Override GPU Functions
-- All files will now utilize the buffered drawing code
-- instead of native gpu codem which should be abstracted
function setBackground(color, isPalette)
  checkArg(1, color, "number")

  local prev = currentBg
  if isPalette then currentBg = -color - 1 else currentBg = color end
  if prev < 0 then
    return GPUgetPaletteColor(-prev - 1), -prev - 1
  end
  return prev
end

function setForeground(color, isPalette)
  checkArg(1, color, "number")

  local prev = currentFg
  if isPalette then currentFg = -color - 1 else currentFg = color end
  if prev < 0 then
    return GPUgetPaletteColor(-prev - 1), -prev - 1
  end
  return prev
end

function getBackground()
  return absColor(currentBg), currentBg < 0
end

function getForeground()
  return absColor(currentFg), currentFg < 0
end

function set(x, y, string, vertical, dontUpdate)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, string, "string")

  local c1, c2 = absColor(currentFg), absColor(currentBg)
  if vertical then
    for y1 = 0, len(string) - 1 do
      setChar(x, y + y1, c1, c2, sub(string, y1 + 1, y1 + 1), currentFg < 0, currentBg < 0)
    end
  else
    for x1 = 0, len(string) - 1 do
      setChar(x + x1, y, c1, c2, sub(string, x1 + 1, x1 + 1), currentFg < 0, currentBg < 0)
    end
  end
  if not dontUpdate then update() end
end

-- Copy a region by a displacement tx and ty
-- Note that this directly updates to screen, as it is more
-- efficent to directly do the copy call
function copy(x, y, w, h, tx, ty)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, w, "number")
  checkArg(4, h, "number")
  checkArg(5, tx, "number")
  checkArg(6, ty, "number")

  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if x < 1 or y < 1 or x > bufferWidth or y > bufferHeight then return false end
  if w < 1 or h < 1 or w > bufferWidth or h > bufferHeight then return false end
  local canDirectlyCopy = true
  local canPartialCopy = false
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
      if x1 < 1 or x1 > bufferWidth or y1 < 1 then goto continue end
      if x1 + tx < 1 or x1 + tx > bufferWidth or y1 + ty < 1 then goto continue end

      bg, fg, sym = getRaw(x1, y1)
      if canDirectlyCopy or canPartialCopy then
        i = getIndex(x1 + tx, y1 + ty)
        buffBg[i], buffFg[i], buffSym[i] = bg, fg, sym
      else
        setBackground(bg)
        setForeground(fg)
        set(x1 + tx, y1 + ty, sym, false, true)
      end

      ::continue::
    end
  end
  ::loopend::
end 

function fill(x, y, w, h, symbol, dontUpdate)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, w, "number")
  checkArg(4, h, "number")
  checkArg(5, symbol, "string")

  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  
  if len(symbol) ~= 1 then return false end
  if x < 1 or y < 1 or x > bufferWidth or y > bufferHeight then return false end
  if w < 1 or h < 1 or w > bufferWidth or h > bufferHeight then return false end

  -- Directly fill if area is large enough and we're directly updating
  local useGpuFill = fillIfAreaIsGreaterThan <= w * h and not dontUpdate
  local i

  -- We can't use gpu fill directly though if it exceeds the current bounds
  if x < drawX1 or x + w - 1 < drawX1 or y < drawY1 or y + h - 1 < drawY1 or
     x > drawX2 or x + w - 1 > drawX2 or y > drawY2 or y + h - 1 > drawY2 then
    useGpuFill = false
  end

  for x1 = x, x + w - 1 do
    for y1 = y, y + h - 1 do
      if useGpuFill then
        i = getIndex(x1, y1)
        buffBg[i], buffFg[i], buffSym[i] = currentBg, currentFg, symbol
        changeBg[i], changeFg[i], changeSym[i] = -17, -17, " "
      else 
        set(x1, y1, symbol, false, true)
      end
    end
  end
  
  if useGpuFill then
    GPUsetBackground(currentBg)
    GPUsetForeground(currentFg)
    GPUfill(x, y, w, h, symbol)
  elseif not dontUpdate then update() 
  else -- Do nothing
  end

  return true
end

function setResolution(w, h)
  checkArg(1, w, "number")
  checkArg(2, h, "number")
  
  local success = setResolution(w, h)
  if sucess then
    flush()
    GPUsetBackground(0)
    GPUfill(0, 0, w, h, " ")
  end
  return success
end

function getResolution()
  return bufferWidth, bufferHeight
end

function getWidth()
  return bufferWidth
end

function getHeight()
  return bufferHeight
end

-- Raw method to set current background
-- to adapt to the background of x, y and
-- current foreground to blend
-- Optionally, blendBg can be set to false to
-- not use adapative background
-- Returns the character to use for the fill
local function setAdaptive(x, y, cfg, cbg, alpha, blendBg, blendBgalpha, symbol)
  if alpha == 1 and blendBgalpha then
    if cbg ~= nil and cbg ~= false then setBackground(cbg) end
    if cfg ~= nil and cfg ~= false then setForeground(cfg) end
    return symbol
  end

  bg, fg, sym = getRaw(x, y)

  if blendBg then
    if blendBgalpha then setBackground(color.blend(bg, cbg, 1 - alpha))
    else setBackground(color.getProminentColor(fg, bg, sym)) end
  end
  setForeground(color.blend(fg, cfg, alpha))

  -- If filling with a space it's better if one fills with the background symbol
  -- instead of losing accuracy by overwriting it with a space
  ::symbolcheck::
  if sym == nil then bg, fg, sym = getRaw(x, y) end -- Since the goto skips this line

  if symbol == " " or symbol == "⠀" then -- 2nd is unicode 0x2800, not regular space
    setForeground(color.blend(fg, cbg, 1 - alpha))
    return sym
  elseif symbol == "█" or symbol == "⣿" then  -- Full block doesn't blend with current background
    return symbol
  end
  return symbol -- Otherwise fill with the symbol
end

-- Screen drawing methods --
-- Important note: alpha is equal to alpha value, meaning 1 = visible, 0 = invisible --
-- Sorry for bad variable naming --

-- Draw a rectangle (border) with current bg and fg colors,
-- with optional alpha
function drawRectangleOutline(x, y, w, h, alpha)
  if alpha == 0 then return false end -- No alpha no render
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if x < 1 or y < 1 or x > bufferWidth or y > bufferHeight then return false end
  if alpha == nil then alpha = 1 end

  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, w, "number")
  checkArg(4, h, "number")
  checkArg(5, alpha, "number")

  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)

  -- Corners
  setAdaptive(x, y, cfg, cbg, alpha, true, false)
  set(x, y, "┌", false, true)
  setAdaptive(x + w - 1, y, cfg, cbg, alpha, true, false)
  set(x + w - 1, y, "┐", false, true)
  setAdaptive(x, y + h - 1, cfg, cbg, alpha, true, false)
  set(x, y + h - 1, "└", false, true)
  setAdaptive(x + w, y + h - 1, cfg, cbg, alpha, true, false)
  set(x + w - 1, y + h - 1, "┘", false, true)

  -- Top and bottom
  for x1 = x + 1, x + w - 2 do
    setAdaptive(x1, y, cfg, cbg, alpha, true, false)
    set(x1, y, "─", false, true)
    setAdaptive(x1, y + h - 1, cfg, cbg, alpha, true, false)
    set(x1, y + h - 1, "─", false, true)
  end

  -- Sides
  for y1 = y + 1, y + h - 2 do
    setAdaptive(x, y1, cfg, cbg, alpha, true, false)
    set(x, y1, "│", false, true)
    setAdaptive(x + w - 1, y1, cfg, cbg, alpha, true, false)
    set(x + w - 1, y1, "│", false, true)
  end

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

-- Fill a rectangle with the current bg and fg colors,
-- with optional alpha. Because of alpha
-- we have to reimplement fill code
function drawRectangle(x, y, w, h, alpha)
  if alpha == 0 then return false end -- No alpha no render
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if x > bufferWidth or y > bufferHeight then return false end
  if alpha == nil then alpha = 1 end

  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, w, "number")
  checkArg(4, h, "number")
  checkArg(5, alpha, "number")

  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)

  -- Directly fill if area is large enough
  for x1 = x, x + w - 1 do
  for y1 = y, y + h - 1 do
    if x1 < 1 then goto continue end
    if y1 < 1 then goto continue end
    if x1 > bufferWidth then goto continue end
    if y1 > bufferHeight then break end
    
    set(x1, y1, setAdaptive(x1, y1, cfg, cbg, alpha, true, true, " "), false, true)
    ::continue::
  end end

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

-- Draw a string at the location (Straight line, newlines ignore)
-- If alpha is enabled, foreground is blended w/ bg
-- If blendBg is enabled, the background will be selected to try
-- to camouflage itself with the existing buffer
function drawText(x, y, string, alpha, blendBg)
  if alpha == 0 then return false end -- No alpha no render
  x, y = floor(x), floor(y)

  if y < 1 or y > bufferHeight then return end

  -- Save current colors
  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)
  if alpha == nil then alpha = 1 end

  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, string, "string")
  checkArg(4, alpha, "number")

  for dx = 0, len(string) - 1 do
    if x < 1 then goto continue end
    if x > bufferWidth then break end

    set(x + dx, y, setAdaptive(x + dx, y, cfg, cbg, alpha, blendBg, false, sub(string, dx + 1, dx + 1)), false, true)
    ::continue::
  end

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

function drawLine(x1, y1, x2, y2, alpha)
  if alpha == 0 then return false end -- No alpha no render
  if alpha == nil then alpha = 1 end
  x1, x2, y1, y2 = floor(x1), floor(x2), floor(y1), floor(y2)

  checkArg(1, x1, "number")
  checkArg(2, y1, "number")
  checkArg(3, x2, "number")
  checkArg(4, y2, "number")

  if x2 < x1 then 
    x1, x2 = x2, x1
    y1, y2 = y2, y1
  end

  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)
  local currentFgSave, currentBgSave = currentFg, currentBg

  -- Special case for vertical lines
  if x1 == x2 then
    drawRectangle(x1, y1, 1, y2 - y1, alpha)
    return true
  end

  local gradient = (y2 - y1) / (x2 - x1)
  
  if gradient > 0.5 then
    local x -- Store x coordinate to set
    for y = 0, y2 - y1 - 1 do
      x = floor(y / gradient + x1)
      if y > bufferHeight or y < 1 or
         x + x1 > bufferWidth or x < 1 then goto continue end
      set(x, y + y1, setAdaptive(x, y + y1, cfg, cbg, alpha, true, true, " "), false, true)
      ::continue::
    end
  else
    local y -- Store y coordinate to set
    for x = 0, x2 - x1 - 1 do
      y = floor(gradient * x + y1)
      if y > bufferHeight or y < 1 or
        x + x1 > bufferWidth or x < 1 then goto continue end
      set(x + x1, y, setAdaptive(x + x1, y, cfg, cbg, alpha, true, true, " "), false, true)
      ::continue::
    end
  end

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

function drawEllipseOutline()
  -- TODO
end

function drawEllipse(x, y, a, b, alpha)
  if alpha == 0 then return false end -- No alpha no render
  x, y, a, b = floor(x), floor(y), floor(a), floor(b)

  if x < 1 or y < 1 or x > bufferWidth or y > bufferHeight then return false end
  if alpha == nil then alpha = 1 end

  local a2, b2 = a * a, b * b -- Store the axis squared
  local computedBound
  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)

  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, a, "number")
  checkArg(4, b, "number")
  checkArg(5, alpha, "number")

  -- Directly fill if area is large enough
  for x1 = x - a, x + a - 1 do
  for y1 = y - b, y + b - 1 do
    if x1 > bufferWidth then goto continue end
    if y1 > bufferHeight then break end
    if x1 < 1 then goto continue end
    if y1 < 1 then goto continue end

    -- Check if inside ellipse
    computedBound = (x1 - x) * (x1 - x) / a2 + (y1 - y) * (y1 - y) / b2
    if computedBound > 1 then goto continue end

    set(x1, y1, setAdaptive(x1, y1, cfg, cbg, alpha, true, true, " "), false, true)
    ::continue::
  end end

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

-- Sub ellipse pixel helper function
-- Returns 0 if outside ellipse else 1
function subEllipseHelper(x1, y1, x, y, a2, b2, onEllipse) -- a2 = a^2, b2 = b^2
  local dis = (x1 - x) * (x1 - x) / a2 + (y1 - y) * (y1 - y) / b2

  -- If we're just doing an outline check distance = 1 (on ellipse)
  if onEllipse then
    -- 0.014 is estimate, larger = thicker but less breaks
    if abs(sqrt(dis) - 1) <= 0.014 then return 1 end
    return 0
  end

  if dis > 1 then return 0 end
  return 1
end

function subEllipseTemplate(x, y, a, b, alpha, justOutline)
  if alpha == 0 then return false end -- No alpha no render
  x, y, a, b = floor(x), floor(y), floor(a), floor(b)

  if x < 1 or y < 1 or x > bufferWidth or y > bufferHeight then return false end
  if alpha == nil then alpha = 1 end

  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, a, "number")
  checkArg(4, b, "number")
  checkArg(5, alpha, "number")

  local a2, b2 = a * a, b * b -- Store the axis squared
  local subChar, charToDraw

  -- Temp vars
  local currentFgSave, currentBgSave
  local cfg, cbg

  -- Directly fill if area is large enough
  for x1 = x - a, x + a - 1 do
  for y1 = y - b, y + b - 1 do
    if x1 > bufferWidth then goto continue end
    if y1 > bufferHeight then break end
    if x1 < 1 then goto continue end
    if y1 < 1 then goto continue end

    -- Iterate "subpixels"
    subChar = format.getBrailleChar(
      subEllipseHelper(x1, y1, x, y, a2, b2, justOutline),
      subEllipseHelper(x1 + 0.5, y1, x, y, a2, b2, justOutline),
      subEllipseHelper(x1, y1 + 0.25, x, y, a2, b2, justOutline),
      subEllipseHelper(x1 + 0.5, y1 + 0.25, x, y, a2, b2, justOutline),
      subEllipseHelper(x1, y1 + 0.5, x, y, a2, b2, justOutline),
      subEllipseHelper(x1 + 0.5, y1 + 0.5, x, y, a2, b2, justOutline),
      subEllipseHelper(x1, y1 + 0.75, x, y, a2, b2, justOutline),
      subEllipseHelper(x1 + 0.5, y1 + 0.75, x, y, a2, b2, justOutline)
    )
    if subChar == "⠀" then goto continue end -- Skip empty braille
    
    -- Same as drawText but without the checks
    currentFgSave, currentBgSave = currentFg, currentBg
    cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)

    if subChar == "⣿" then
      -- Filler in the middle of the ellipse, we can fill with a space
      -- and use default set adaptive behaviour

      subChar = " "
      currentBg = currentFg
      set(x1, y1, setAdaptive(x1, y1, cfg, cbg, alpha, true, true, subChar), false, true)
    else
      -- Side bars should have the background equal to the blended value
      -- However since braille is filled with foreground we swap bg and fg
      -- and set the bg to whatever the current bg is at that value

      charToDraw = setAdaptive(x1, y1, cfg, cbg, alpha, true, true, subChar)
      currentFg = currentBg
      currentBg = getRaw(x1, y1)
      set(x1, y1, charToDraw, false, true)
    end
    
    currentBg = currentBgSave
    currentFg = currentFgSave
    ::continue::
  end end
  return true
end

function drawEllipseThin(x, y, a, b, alpha)
  return subEllipseTemplate(x, y, a, b, alpha, false)
end

function drawEllipseOutlineThin(x, y, a, b, alpha)
  return subEllipseTemplate(x, y, a, b, alpha, true)
end

function drawBeizerCurve(points, alpha)
  -- TODO
end

-- Draw a line (Using braille characters)
-- from 1 point to another, optionally with alpha
-- Optional line character, which will override ALL line characters
function drawLineThin(x1, y1, x2, y2, alpha, lineChar)
  if alpha == 0 then return false end -- No alpha no render
  x1, y1, x2, y2 = floor(x1), floor(y1), floor(x2), floor(y2)
  if alpha == nil then alpha = 1 end

  -- Save current colors
  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)

  checkArg(1, x1, "number")
  checkArg(2, y1, "number")
  checkArg(3, x2, "number")
  checkArg(4, y2, "number")
  checkArg(5, alpha, "number")

  -- Horz line
  if y1 == y2 then
    lineChar = lineChar or "▔"
    for x = x1, x2 do
      if x < 1 then goto continue end
      if x > bufferWidth then break end

      setAdaptive(x, y1, cfg, false, alpha, true, false)
      set(x, y1, lineChar, false, true)
      ::continue::
    end
    return true
  end

  -- Vertical line
  if x1 == x2 then
    lineChar = lineChar or "▏"
    for y = y1, y2 do
      if y < 1 then goto continue end
      if y > bufferHeight then break end

      setAdaptive(x1, y, cfg, false, alpha, true, false)
      set(x1, y, lineChar, false, true)
      ::continue::
    end
    return true
  end

  -- TODO LINE

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

-- Set gpu proxy
setGPUProxy(gpu)

return {
  setGPUProxy = setGPUProxy,
  getGPUProxy = getGPUProxy,
  bind = bind,
  flush = flush,
  clear = clear,
  setChar = setChar,
  update = update,
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
  drawText = drawText,
  drawLine = drawLine,
  drawEllipseOutline = drawEllipseOutline,
  drawEllipse = drawEllipse,
  drawLineThin = drawLineThin,
  setDrawingBound = setDrawingBound,
  getDrawingBound = getDrawingBound,
  resetDrawingBound = resetDrawingBound,
  resetPalette = resetPalette,
  drawEllipseThin = drawEllipseThin,
  drawEllipseOutlineThin = drawEllipseOutlineThin,
  drawBeizerCurve = drawBeizerCurve,
  getRaw = getRaw,
  getIndex = getIndex,
  getCoords = getCoords
}
