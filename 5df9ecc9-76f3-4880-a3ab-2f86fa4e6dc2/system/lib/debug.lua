-- TODO remake this thing

local api = {}
local serial=require("serialization")


function api.saveTable(table)
    file=io.open("/system/logs/error.txt","a")
    file:write("\n\n" .. serial.serialize(table))
    file:close()
end

function api.save(thing)
    file=io.open("/system/logs/error.txt","a")
    file:write("\n\n" .. thing)
    file:close()
end

return api