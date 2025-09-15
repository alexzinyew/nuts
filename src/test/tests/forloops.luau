--!nocheck
--!nolint

CASE "for loop no incr"
local sum = 0
for i = 1, 3 do
    sum += i
end
cprintl(sum)
CHECK(sum == 1 + 2 + 3)

CASE "for loops scoped"
local upper = 0

for i = 1, 10 do
    local inner = 1
    upper += 1
end

CHECK(inner == nil)
CHECK(upper == 10)

CASE "generic for loop"
local tbl = {1, 2, 3}
local sum = 0

for i, v in tbl do
    sum += v
end

CHECK(sum == 6)
