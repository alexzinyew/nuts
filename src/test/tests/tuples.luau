--!nocheck
--!nolint

CASE "tuple unpacking function return"

function foo()
    return 1, 2, 3
end

local a, b, c = foo()
CHECK(a == 1)
CHECK(b == 2)
CHECK(c == 3)

CASE "unpacking more than size"
local a,b,c,d = foo()
CHECK(a == 1)
CHECK(b == 2)
CHECK(c == 3)
CHECK(d == nil)

CASE "tuple returning only first expr"
local t,a,b,c = foo(), foo()
CHECK(a == 1)
CHECK(b == 2)
CHECK(c == 3)
CHECK(t == 1)

local t, a, b = (foo())
CHECK(t == 1)
CHECK(a == nil)
CHECK(b == nil)

CASE "tuple unpacking in not an assignment"
CHECK(foo() == 1)

CASE "returning tuple calls"
function bar()
    return foo()
end

local d, e, f, g = bar()
CHECK(d == 1)
CHECK(e == 2)
CHECK(f == 3)

CASE "returning joint tuple calls"
function baz()
    return bar(), foo()
end

local h, i, j, k = baz()
CHECK(h == 1)
CHECK(i == 1)
CHECK(j == 2)
CHECK(k == 3)
