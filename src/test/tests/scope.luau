--!nocheck
--!nolint

CASE "scope check"
local a = 0
b = 1

CHECK(a == 0)
CHECK(b == 1)

a = 1
b = 2

CHECK(a == 1)
CHECK(b == 2)

local c = true

function foo()
    local new = "new"
    a = "modified"

    new_global = "meow"
    b = "mraow"

    local c = false
end
foo()

CHECK(new == nil)
CHECK(a == "modified")
CHECK(b == "mraow")
CHECK(c == true)
CHECK(new_global == "meow")
