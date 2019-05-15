local package = {}

-- Paths to where you can load a package, seperated by ;
-- File names are replaced with a ? wildcard
package.path = "/lib/?.lua;/system/lib/?.lua;/usr/lib/?.lua;/home/lib/?.lua;./?.lua;/lib/?/init.lua;/usr/lib/?/init.lua;/home/lib/?/init.lua;./?/init.lua"

local loading = {}
local loaded = {
  ["_G"]        = _G,
  ["bit32"]     = bit32,
  ["coroutine"] = coroutine,
  ["math"]      = math,
  ["os"]        = os,
  ["package"]   = package,
  ["string"]    = string,
  ["table"]     = table
}
package.loaded = loaded

-- Helper to check if a file path is
-- a valid file, returns nil if not,
-- otherwise returns true
local function checkFile(filepath, fs)
  if fs.exists(filepath) then
    local file = fs.open(filepath, "r")
    if file then
      file:close()
      return filepath
    end
  end
  return nil
end

function package.searchpath(name, path, sep, rep)
  checkArg(1, name, "string")
  checkArg(2, path, "string")

  local fs = require("filesystem")
  local errorFiles = {}  -- Files that were failed to be found
  local temppath

  -- This allows for requiring direct files, ie I call
  -- require("/system/test.lua") which loads it even if it
  -- is not a path in package.path
  if name:sub(-4) == ".lua" then
    -- If not an absolute path
    if name:sub(1, 1) ~= "/" and os.getenv then
      temppath = fs.concat(os.getenv("PWD") or "/", name)
    end

    temppath = checkFile(name, fs)
    if temppath ~= nil then return temppath end
    errorFiles[#errorFiles + 1] = "\tNo file '" .. name .. "'"

    -- If an absolute path is not found then don't bother
    -- checking for others
    if name:sub(1, 1) == "/" then return nil, table.concat(errorFiles, "\n") end
  end

  sep = sep or '.'
  rep = rep or '/'
  sep, rep = '%' .. sep, rep
  name = string.gsub(name, sep, rep)

  for subPath in string.gmatch(path, "([^;]+)") do
    -- Get the sub path to iterate, prepending a / if needed
    subPath = string.gsub(subPath, "?", name)
    if subPath:sub(1, 1) ~= "/" and os.getenv then
      subPath = fs.concat(os.getenv("PWD") or "/", subPath)
    end

    temppath = checkFile(subPath, fs)
    if temppath ~= nil then return temppath end

    errorFiles[#errorFiles + 1] = "\tNo file '" .. subPath .. "'"
  end
  return nil, table.concat(errorFiles, "\n")
end

-- Global function require
function require(module)
  checkArg(1, module, "string")

  if loaded[module] ~= nil then
    return loaded[module]
  elseif not loading[module] then
    local library, status, step
    step, library, status = "not found", package.searchpath(module, package.path)

    if library then
      step, library, status = "loadfile failed", loadfile(library)
    end

    if library then
      loading[module] = true
      step, library, status = "load failed", pcall(library, module)
      loading[module] = false
    end

    assert(library, string.format("module '%s' %s:\n%s", module, step, status))
    loaded[module] = status
    return status
  else
    error("already loading: " .. module .. "\n" .. debug.traceback(), 2)
  end
end

function package.delay(lib, file)
  local mt = {
    __index = function(tbl, key)
      dofile(file)
      setmetatable(lib, nil)
      setmetatable(lib.internal or {}, nil)
      return tbl[key]
    end
  }
  if lib.internal then
    setmetatable(lib.internal, mt)
  end
  setmetatable(lib, mt)
end

-------------------------------------------------------------------------------
return package