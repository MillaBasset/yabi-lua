local bigint = {}

setmetatable(bigint, {
    __call = function(_, ...)
        return bigint.new(...)
    end
})

local mt = {
    __add = function(arg1, arg2)
        return bigint.add(arg1, arg2)
    end,
    __sub = function(arg1, arg2)
        return bigint.subtract(arg1, arg2)
    end,
    __mul = function(arg1, arg2)
        return bigint.multiply(arg1, arg2)
    end,
    __div = function(arg1, arg2)
        return bigint.divide(arg1, arg2)
    end,
    __unm = function(arg)
        return bigint.negate(arg)
    end,
    __eq = function(arg1, arg2)
        return bigint.compare(arg1, arg2) == 0
    end,
    __lt = function(arg1, arg2)
        return bigint.compare(arg1, arg2) < 0
    end,
    __le = function(arg1, arg2)
        return bigint.compare(arg1, arg2) <= 0
    end,
    __tostring = function(arg)
        return bigint.tostring(arg)
    end,
    __index = bigint
}

local exponent = 7
local base = 10 ^ exponent -- do not change this

local unpack = table.unpack or unpack

function bigint.new(arg)
    local res = {digits = {}, negative = false}
    if getmetatable(arg) == mt then
        res.negative = arg.negative
        res.digits = {unpack(arg.digits)}
    elseif type(arg) == "nil" then
        -- do nothing; res is already initialized
    elseif type(arg) == "number" then
        if arg ~= arg or math.abs(arg) == math.huge then
            error("non-finite number supplied to bigint.new", 2)
        elseif math.abs(arg) > 2^53 then
            error("number supplied to bigint.new too large; supply a string instead", 2)
        elseif math.floor(arg) ~= arg then
            error("non-integer supplied to bigint.new", 2)
        end

        res.negative = (arg < 0)
        if arg < 0 then
            arg = -arg
        end
        while arg ~= 0 do
            table.insert(res.digits, arg % base)
            arg = math.floor(arg / base)
        end
    elseif type(arg) == "string" then
        if not arg:match("^%-?%d+$") then
            error(string.format([[cannot parse string "%s" to bigint]], arg), 2)
        end

        -- negative sign
        if arg:sub(1, 1) == "-" then
            arg = arg:sub(2, -1)
            res.negative = true
        end

        local strlen = #arg
        local padlen = exponent - (strlen % exponent)
        local dgtlen = math.floor(0.5 + (strlen + padlen) / exponent) -- in case of funny floating points
        local curdgt = dgtlen
    
        -- cut the string into the 10 ^ exponent chunks we want
        arg = string.rep("0", padlen) .. arg
        for chunk in arg:gmatch("(" .. string.rep("%d", exponent) .. ")") do
            res.digits[curdgt] = tonumber(chunk)
            curdgt = curdgt - 1
        end
    
        -- remove empty leading digits
        while res.digits[dgtlen] == 0 do
            res.digits[dgtlen] = nil
            dgtlen = dgtlen - 1
        end
    
        -- force positive zero
        if dgtlen == 0 then
            res.negative = false
        end
    else
        error("bigint.new expects a nil, number, string, or bigint", 2)
    end
    return setmetatable(res, mt)
end

function bigint.tostring(arg)
    if #arg.digits == 0 then
        return "0"
    end
    local str = arg.negative and "-" or ""
    for i = #arg.digits, 1, -1 do
        str = str .. string.format(
            i ~= #arg.digits and ("%0" .. exponent .. "d") or "%d",
            arg.digits[i]
        )
    end
    return str
end

function bigint.tonumber(arg)
    local res = 0
    for i = 1, #arg.digits do
        res = res + arg.digits[i] * base ^ (i - 1)
    end
    return arg.negative and -res or res
end

function bigint.compare(arg1, arg2)
    if arg2.negative and not arg1.negative then
        return 1
    elseif arg1.negative and not arg2.negative then
        return -1
    else
        return bigint.compare_magnitude(arg1, arg2)
    end
end

-- convenience function for front-end add/subtract
function bigint.compare_magnitude(arg1, arg2)
    if #arg1.digits > #arg2.digits then
        return 1
    elseif #arg2.digits > #arg1.digits then
        return -1
    else
        return bigint.compare_digits(arg1, arg2)
    end
end

-- #arg1.digits must equal #arg2.digits
function bigint.compare_digits(arg1, arg2)
    for i = #arg1.digits, 1, -1 do
        if arg1.digits[i] > arg2.digits[i] then
            return 1
        elseif arg2.digits[i] > arg1.digits[i] then
            return -1
        end
    end
    return 0
end

-- arg1 and arg2 must both be positive
local function add_raw(arg1, arg2)
    local res = {}
    local carry = 0
    local max_digits = #arg2.digits
    if #arg1.digits > #arg2.digits then
        max_digits = #arg1.digits
    end
    for i = 1, max_digits do
        local digit_res = (
            (arg1.digits[i] or 0) +
            (arg2.digits[i] or 0) +
            carry
        )
        if digit_res >= base then
            carry = 1
            digit_res = digit_res - base
        else
            carry = 0
        end
        table.insert(res, digit_res)
    end
    if carry == 1 then
        table.insert(res, 1)
    end
    return res
end

-- arg1 must be greater than arg2, both must be positive
local function subtract_raw(arg1, arg2)
    local res = {}
    local borrow = 0
    for i = 1, #arg1.digits do
        local digit_res = (
            arg1.digits[i] -
            (arg2.digits[i] or 0) -
            borrow
        )
        if digit_res < 0 then
            borrow = 1
            digit_res = digit_res + base
        else
            borrow = 0
        end
        table.insert(res, digit_res)
    end
    -- removes leading zeroes
    -- I don't think any digit but the leading digit can be zero?
    -- but I'll have this here for now
    while res[#res] == 0 do
        res[#res] = nil
    end
    return res
end

function bigint.negate(arg)
    return setmetatable({
        negative = not arg.negative,
        digits = {unpack(arg.digits)}
    }, mt)
end

function bigint.abs(arg)
    return setmetatable({
        negative = false,
        digits = {unpack(arg.digits)}
    }, mt)
end

function bigint.add(arg1, arg2)
    local res = {}
    if arg1.negative == arg2.negative then
        return setmetatable({
            negative = arg1.negative,
            digits = add_raw(arg1, arg2)
        }, mt)
    elseif bigint.compare_magnitude(arg1, arg2) == 0 then
        return bigint.new(0)
    elseif bigint.compare_magnitude(arg1, arg2) > 0 then
        return setmetatable({
            negative = arg1.negative,
            digits = subtract_raw(arg1, arg2)
        }, mt)
    else
        return setmetatable({
            negative = arg2.negative,
            digits = subtract_raw(arg2, arg1)
        }, mt)
    end
end

function bigint.subtract(arg1, arg2)
    return bigint.add(arg1, bigint.negate(arg2))
end

-- arg1 and arg2 must both be positive
local function multiply_raw(arg1, arg2)
    local res = {}
    for i = 1, #arg1.digits do
        for j = 1, #arg2.digits do
            local pos = i + j - 1
            if not res[pos] then
                res[pos] = 0
            end
            local digit_res = arg1.digits[i] * arg2.digits[j]
            res[pos] = res[pos] + digit_res
            if res[pos] >= base then
                local to_add = math.floor(res[pos] / base)
                res[pos] = res[pos] % base
                if res[pos + 1] then
                    res[pos + 1] = res[pos + 1] + to_add
                else
                    res[pos + 1] = to_add
                end
            end
        end
    end

    return res
end

function bigint.multiply(arg1, arg2)
    if (
        bigint.compare(arg1, bigint.new(0)) == 0 or
        bigint.compare(arg2, bigint.new(0)) == 0
    ) then
        return bigint.new(0)
    -- next two conditions handle 1 and -1
    elseif bigint.compare_magnitude(arg1, bigint.new(1)) == 0 then
        return setmetatable({
            negative = arg1.negative ~= arg2.negative,
            digits = {unpack(arg2.digits)}
        }, mt)
    elseif bigint.compare_magnitude(arg2, bigint.new(1)) == 0 then
        return setmetatable({
            negative = arg1.negative ~= arg2.negative,
            digits = {unpack(arg1.digits)}
        }, mt)
    else
        return setmetatable({
            negative = arg1.negative ~= arg2.negative,
            digits = multiply_raw(arg1, arg2)
        }, mt)
    end
end

-- arg1 must be greater than or equal to arg2, both must be positive
local function divide_raw(arg1, arg2)
    local res, dividend = {}, bigint.new(0)

    for i = #arg1.digits, 1, -1 do
        if not (arg1.digits[i] == 0 and #dividend.digits == 0) then
            table.insert(dividend.digits, 1, arg1.digits[i])
        end
        local cur_digit = 0

        while bigint.compare_magnitude(dividend, arg2) >= 0 do
            cur_digit = cur_digit + 1
            dividend = bigint.subtract(dividend, bigint.abs(arg2))
        end

        if not (cur_digit == 0 and #res == 0) then
            table.insert(res, 1, cur_digit)
        end
    end

    return res
end

function bigint.divide(arg1, arg2)
    if bigint.compare(arg2, bigint.new(0)) == 0 then
        error("bigint.divide: attempted to divide by zero", 2)
    elseif bigint.compare_magnitude(arg1, arg2) < 0 then
        return bigint.new(0)
    elseif bigint.compare_magnitude(arg1, arg2) == 0 then
        return bigint.new(arg1.negative == arg2.negative and 1 or -1)
    -- handles divisor of 1 or -1
    elseif bigint.compare_magnitude(arg2, bigint.new(1)) == 0 then
        return setmetatable({
            negative = arg1.negative ~= arg2.negative,
            digits = {unpack(arg1.digits)}
        }, mt)
    else
        return setmetatable({
            negative = arg1.negative ~= arg2.negative,
            digits = divide_raw(arg1, arg2)
        }, mt)
    end
end

return bigint