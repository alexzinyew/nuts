--!nocheck
--!nolint

CASE "assigning a slot"
local a = {}
a.b = "works"

CHECK(a.b == "works")

CASE "assigning a slot with a tuple"
local a = {}
function foo()
	return 1, 2, 3
end

a.a, a.b, a.c = foo()

CHECK(a.a == 1)
CHECK(a.b == 2)
CHECK(a.c == 3)
