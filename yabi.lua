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
            error(string.format([[Cannot parse string "%s" to bigint]], arg), 2)
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
        error("bigint.new expects a number, string, or bigint", 2)
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
            i ~= #arg.digits and "%07d" or "%d",
            arg.digits[i]
        )
    end
    return str
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

return bigint