--!nocheck
--!nolint

CASE "for loop no increment"
local sum = 0
for i = 1, 3 do
	sum += i
end

CHECK(sum == 1 + 2 + 3)

CASE "for loop with increment"
local sum = 0
for i = 5, 1, -1 do
	sum += i
end

CHECK(sum == 1 + 2 + 3 + 4 + 5)

CASE "for loops scoped"
local upper = 0

for i = 1, 10 do
	local inner = 1
	upper += 1
end

CHECK(inner == nil)
CHECK(upper == 10)

CASE "generalized table loop"
local mixed_table = { 1, 2, 3, a = 4, b = 5 }
local sum = 0

for i, v in mixed_table do
	sum += v
end

CHECK(sum == 1 + 2 + 3 + 4 + 5)

CASE "pairs table loop"
local sum = 0

for i, v in pairs(mixed_table) do
	sum += v
end

CHECK(sum == 1 + 2 + 3 + 4 + 5)

CASE "next table loop"
local sum = 0

for i, v in next, mixed_table do
	sum += v
end

CHECK(sum == 1 + 2 + 3 + 4 + 5)

CASE "ipairs array loop"
local sum = 0

for i, v in ipairs(mixed_table) do
	sum += v
end

CHECK(sum == 1 + 2 + 3)

CASE "ipairs table with holes"
local holey_table = { [1] = 1, [3] = 3 }

local iterations = 0
local sum = 0

for i, v in ipairs(holey_table) do
	iterations += 1
	sum += v
end

CHECK(iterations == 1)
CHECK(sum == 1)

CASE "iterating with custom iterator"
local function iterator(a, i)
	i = i or 0
	i += 1
	if a[i] then
		return i, a[i]
	else
		return nil
	end
end

local sum = 0

for i, v in iterator, mixed_table do
	sum += v
end

CHECK(sum == 1 + 2 + 3)

CASE "iterating with custom iterator with start-point"
local sum = 0

for i, v in iterator, mixed_table, 1 do
	sum += v
end

CHECK(sum == 2 + 3)
