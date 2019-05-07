-- Double Buffered Magic --
local component = require("component")
local unicode = require("unicode")

local gpu = component.gpu

-- Buffer which stores all the changes
-- that are to be displayed on the screen
local buffWidth, buffHeight
local buffBg, buffFg, buffSym
local changeBg, changeFg, changeSym

-- Limits for drawing on the buffer, to avoid 
-- checking for excessive changes
local drawX1, drawY1, drawX2, drawY2 = 0, 0, buffWidth, buffHeight

-- Current fg / bg colors for set and fill
local currentBg, currentFg = 0, 0xFFFFFF

-- Optimization for lua
local fill = gpu.fill
local set = gpu.set
local setBackground = gpu.setBackground
local setForeground = gpu.setForeground
local getResolution = gpu.getResolution
local setResolution = gpu.setResolution
local getPaletteColor = gpu.getPaletteColor
local copy = gpu.copy
local setResolution = gpu.setResolution

local rep = string.rep
local sub = unicode.sub
local floor = math.floor

-- Constants
local fillIfAreaIsGreaterThan = 80

-- Convert x y coords to a buffer index
local function getIndex(x, y)
	return buffWidth * (y - 1) + x
end

-- Check if two characters at the buffers are
-- equal. Equality is checked by symbol, fg and bg
-- unless the character is whitespace, in which case
-- fg is ignored
local function areEqual(sym, changesym, bg, changebg, fg, changefg)
  -- If symbols don't match or backgrounds match always unequal
  if sym ~= changesym or bg ~= changebg then return false end
  if sym == " " then return true end
  return fg == changefg
end

-- Palette index = (-index - 1), this takes the "absolute"
-- value to convert to the proper index if negative
local function absColor(val) 
  if val < 0 then
    return -val - 1
  end
  return val
end 

--------------------------------------------------------
local api = {}

function api.flush()
  local w, h = getResolution()
  buffWidth = w
  buffHeight = h

  drawX1, drawX2 = w, 0
  drawY1, drawY2 = h, 0

  buffBg, buffFg, buffSym = {}, {}, {}
  changeBg, changeFg, changeSym = {}, {}, {}

  -- Prefill the buffers to avoid rehashing (-17 is transparent) --
  for i = 1, w * h do
    buffBg[i], buffFg[i], buffSym[i] = -17, -17, " "
    changeBg[i], changeFg[i], changeSym[i] = -17, -17, " "
  end
end

function api.clear(color)
  api.setBackground(color)
  api.fill(0, 0, bufferWidth, bufferHeight, " ")

  drawX1, drawX2 = w, 0
  drawY1, drawY2 = h, 0
end

function api.setChar(x, y, fgColor, bgColor, symbol, isPalette1, isPalette2)
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end
  local i = getIndex(x, y)

  -- Update draw bounds if needed
  if x < drawX1 then drawX1 = x end
  if x > drawX2 then drawX2 = x end
  if y < drawY1 then drawY1 = y end
  if y > drawY2 then drawY2 = y end

  -- We'll represent palette indexes with negative numbers - 1
  -- ie palette index 3 is saved as -4
  if isPalette1 then fgColor = -fgColor - 1 end
  if isPalette2 then bgColor = -bgColor - 1 end

  changeBg[i], changeFg[i], changeSym[i] = bgColor, fgColor, symbol
end

-- Write changes to the screen
function api.update(force)
  -- If there have been no changes then ignore
  if drawX1 > drawX2 or drawY1 > drawY2 then return end

  -- i = current index
  -- lineChange = index increment when changing to next y value
  -- fillw = Width of repeated length of background colors
  -- subgroup = the foregorund subgroup of the background dict
  -- searchX = x value of end of repeated length
  -- searchIndex = index of end of repeated length
  -- currBg = temp var to store bg for current index since change buffer gets reset
  -- charCount = character counter for repeated string optimization
  -- j = temp loop variable
  -- colorChanges = dict of bg / fg color pixels grouped togther
  local i = getIndex(drawX1, drawY1)
  local lineChange = buffWidth - drawX2 + drawX1 - 1
  local fillw, subgroup, searchX, searchIndex, currBg, charcount, j
  local colorChanges = {}

  for y = drawY1, drawY2 do
		x = drawX1
    while x <= drawX2 do
      if changeBg[i] == -17 or changeFg[i] == -17 then
        -- Ignore transparent characters
      -- If char is same as buffer below don't update it
      -- unless the force parameter is true.
      elseif force or not areEqual(buffSym[i], changeSym[i], buffBg[i], changeBg[i], buffFg[i], changeFg[i]) then
        searchX = x + 1
        searchIndex = i + 1
        
        buffSym[i], buffBg[i], buffFg[i] = changeSym[i], changeBg[i], changeFg[i]

        -- Search for repeating chunks of characters of the same
        -- background
        while searchX <= drawX2 do
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
          end

          subgroup[#subgroup + 1] = {x + j - i, y, rep(changeSym[j], charcount)}

          -- Reset the change buffer
          changeBg[j], changeFg[j] = -17, -17
          changeSym[j] = " "

          j = j + charcount
        end

        -- Increment x and i up to searchX - 1
        -- (Since there is a +1 below)
        x = searchX - 1
        i = i + fillw - 1
      end

      -- This is required to avoid infinite loops
      -- when buffers are the same
      x = x + 1
      i = i + 1
    end

    i = i + lineChange
  end

  -- Draw color groups
  local t -- Temp variable
  for bgcolor, group1 in pairs(colorChanges) do
    setBackground(absColor(bgcolor), bgcolor < 0)
    for fgcolor, group2 in pairs(group1) do
      setForeground(absColor(fgcolor), fgcolor < 0)

      for i = 1, #group2 do
        t = group2[i]

        -- If spaces then use fill as it is less energy intensive
        if t[3] == " " then
          fill(t[1], t[2], #t[3], 1, " ")
        else 
          set(t[1], t[2], t[3])
        end
      end
    end
  end

  -- Reset the drawX drawY bounds to largest / smallest possible
  drawX1, drawX2 = buffWidth, 0
  drawY1, drawY2 = buffHeight, 0 
  colorChanges = nil
end


-- Additional functions for the screen




-- Override GPU Functions
-- All files will now utilize the buffered drawing code
-- instead of native gpu codem which should be abstracted
function api.setBackground(color, isPalette)
  local prev = currentBg
  if isPalette then currentBg = -color - 1 else currentBg = color end
  if prev < 0 then
    return getPaletteColor(-prev - 1), -prev - 1
  end
  return prev
end

function api.setForeground(color, isPalette)
  local prev = currentFg
  if isPalette then currentFg = -color - 1 else currentFg = color end
  if prev < 0 then
    return getPaletteColor(-prev - 1), -prev - 1
  end
  return prev
end

function api.getBackground()
  return absColor(currentBg), currentBg < 0
end

function api.getForeground()
  return absColor(currentFg), currentFg < 0
end

function api.set(x, y, string, vertical, dontUpdate)
  local c1, c2 = absColor(currentFg), absColor(currentBg)
  if vertical then
    for y1 = 0, #string - 1 do
      api.setChar(x, y + y1, c1, c2, sub(string, y1 + 1, y1 + 1), currentFg < 0, currentBg < 0)
    end
  else
    for x1 = 0, #string - 1 do
      api.setChar(x + x1, y, c1, c2, sub(string, x1 + 1, x1 + 1), currentFg < 0, currentBg < 0)
    end
  end
  if not dontUpdate then api.update() end
end

function api.copy(x, y, w, h, tx, ty)
  local i
  local orgB, orgF = currentBg, currentFg

  for dx = 0, w - 1 do
    for dy = 0, h - 1 do
      api.setBackground(buffBg[i])
      api.setForeground(buffFg[i])
      api.set(tx + dx, ty + dy, buffSym[i], false, true)
    end
  end

  currentBg = orgB
  currentFg = orgF
  api.update()
end 

function api.fill(x, y, w, h, symbol)
  if #symbol ~= 1 then return false end
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end
  if w < 1 or h < 1 or w > buffWidth or h > buffHeight then return false end

  -- Round x and y values down automagically
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)

  -- Directly fill if area is large enough
  local useGpuFill = fillIfAreaIsGreaterThan <= w * h
  local i

  for x1 = x, x + w - 1 do
    for y1 = y, y + h - 1 do
      if useGpuFill then
        i = getIndex(x1, y1)
        buffBg[i], buffFg[i] = currentBg, currentFg
        buffSym[i] = symbol
      else 
        api.set(x1, y1, symbol, false, true)
      end
    end
  end
  
  if useGpuFill then
    setBackground(currentBg)
    setForeground(currentFg)
    fill(x, y, w, h, symbol)
  else api.update() end

  -- Reset the drawX drawY bounds to largest / smallest possible
  drawX1, drawX2 = buffWidth, 0
  drawY1, drawY2 = buffHeight, 0 

  return true
end

function api.setResolution(w, h)
  local success = setResolution(w, h)
  if sucess then
    api.flush()
    setBackground(0)
    fill(0, 0, w, h, " ")
  end
  return success
end

function api.getResolution()
  return buffWidth, buffHeight
end

function api.getWidth()
  return buffWidth
end

function api.getHeight()
  return buffHeight
end

-- Override GPU API
gpu.set = api.set
gpu.setBackground = api.setBackground
gpu.setForeground = api.setForeground
gpu.getBackground = api.getBackground
gpu.getForeground = api.getForeground
gpu.setResolution = api.setResolution
gpu.getResolution = api.getResolution
gpu.copy = api.copy
gpu.fill = api.fill

-- Prefill buffer
api.flush()

return api
