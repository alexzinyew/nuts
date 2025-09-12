--!nocheck
--!nolint

CASE "local functions"
local function foo() end
local function foo(a, b, c) end
local function foo(a, b) return a + b end

CHECK(foo(3, 5) == 8)
