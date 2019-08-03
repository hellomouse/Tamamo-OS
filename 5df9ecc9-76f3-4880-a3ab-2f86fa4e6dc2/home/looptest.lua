local a = {}
local x = os.clock()

for i = 1, 5000000 do
    a[#a + 1] = 1
end

print(os.clock() - x)

a = nil
for i = 1, 10 do os.sleep(0.05) end -- Clear garbage

a = {}
x = os.clock()
local n = 1

for i = 1, 5000000 do
    a[n] = 1
    n = n + 1
end

print(os.clock() - x)