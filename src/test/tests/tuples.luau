function foo()
    return 1, 2, 3
end

local a, b, c = foo()
assert(a == 1)
assert(b == 2)
assert(c == 3)

assert(foo() == 1)

function bar()
    return foo()
end

local d, e, f = bar()
assert(d == 1)
assert(e == 2)
assert(f == 3)
