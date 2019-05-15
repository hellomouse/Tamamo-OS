local api = {}

-- Optimization for lua
local char = string.char
local sub = string.sub
local byte = string.byte
local insert = table.insert
local concat = table.concat

-- Both compression use LZW and accept the file data
function api.compress(uncompressed) -- string
  local d, result, dictSize, w, c = {}, {}, 255, ""
  for i = 0, 255 do d[char(i)] = i end
  for i = 1, #uncompressed do
    c = sub(uncompressed, i, i)
    if d[w .. c] then
      w = w .. c
    else
      insert(result, d[w])
      dictSize = dictSize + 1
      d[w .. c] = dictSize
      w = c
    end
  end
  if w ~= "" then
    insert(result, d[w])
  end
  return result
end
 
function api.decompress(compressed) -- table
  local d, dictSize, entry, w, k = {}, 255, "", "", ""
  for i = 0, 255 do d[i] = char(i) end
  local result = {}
  for i = 1, #compressed do
    k = compressed[i]
    if d[k] then
      entry = d[k]
    elseif k == dictSize then
      entry = w .. sub(w, 1, 1)
    else
      return nil, i
    end
    result[#result + 1] = entry
    d[dictSize] = w .. sub(entry, 1, 1)
    dictSize = dictSize + 1
    w = entry
  end
  if w ~= nil then 
    table.insert(result, w) 
  end
  return concat(result)
end

return api