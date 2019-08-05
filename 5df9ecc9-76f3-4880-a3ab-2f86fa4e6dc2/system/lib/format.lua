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

function format.serialise(tbl_in, pretty, allow_multref, stringify_unknown)
	local tabs = setmetatable({}, { __index = function(tbl, key)
		local value = ("\t"):rep(key)
		tbl[key] = value
		return value
	end })
	local output = {}
	local tracker = {}
	local function impl(tbl, depth)
		if tracker[tbl] then
			if allow_multref then
				table.insert(output, "[see above]")
				return
			else
				error("unable to serialise multiple references to the same subtable", 3)
			end
		end
		local function insert_value(value)
			local value_type = type(value)
			if  value_type ~= "boolean"
			and value_type ~= "string"
			and value_type ~= "number"
			and value_type ~= "table" then
				if stringify_unknown then
					value = ("[%s]"):format(tostring(value))
				else
					error(("unable to serialise value '%s'"):format(tostring(value)), 3)
				end
			end
			if value_type == "string" then
				table.insert(output, ("%q"):format(value))
			elseif value_type == "table" then
				impl(value, depth + 1)
			else
				table.insert(output, tostring(value))
			end
			table.insert(output, pretty and ",\n" or ",")
		end
		tracker[tbl] = true
		if not next(tbl) then
			table.insert(output, "{}")
			return
		end
		table.insert(output, pretty and "{\n" or "{")
		local length = #tbl
		if length == 0 then
			length = nil
		else
			for key, value in ipairs(tbl) do
				if pretty then
					table.insert(output, tabs[depth + 1])
				end
				insert_value(value)
				length = key
			end
		end
		for key, value in pairs(tbl) do
			local key_type = type(key)
			if not (length and key_type == "number" and key <= length) then
				if pretty then
					table.insert(output, tabs[depth + 1])
				end
				if  key_type ~= "boolean"
				and key_type ~= "string"
				and key_type ~= "number" then
					if stringify_unknown then
						key = ("[%s]"):format(tostring(key))
					else
						error(("unable to serialise key '%s'"):format(tostring(key)), 3)
					end
				end
				if key_type == "string" then
					if key:find("^[_%a][_%w]*$") then
						table.insert(output, key)
					else
						table.insert(output, ("[%q]"):format(key))
					end
				else
					table.insert(output, "[")
					table.insert(output, tostring(key))
					table.insert(output, "]")
				end
				table.insert(output, pretty and " = " or "=")
				insert_value(value)
			end
		end
		if pretty then
			table.insert(output, tabs[depth])
		end
		table.insert(output, "}")
	end
	impl(tbl_in, 0)
	return table.concat(output):gsub(",}$", "}") -- Remove trailing comma
end

function format.unserialise(str)
	local func, err = loadstring("return " .. str)
	if not func then
		error("Serialised data corrupt", 2)
	end
	local ok, tbl = pcall(setfenv(func, {}))
	if not ok then
		error("Serialised data corrupt", 2)
	end
	return tbl
end

return format