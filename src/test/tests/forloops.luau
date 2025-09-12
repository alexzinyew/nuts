--!nocheck
--!nolint

CASE "for loop no incr"
local sum = 0
for i = 1, 10 do
    sum += 1
end
printl(sum)
CHECK(sum == 10)
