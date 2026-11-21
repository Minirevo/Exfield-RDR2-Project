FrontierLib = FrontierLib or {}

FrontierLib.VERSION = '0.1.0'

function FrontierLib.IsInteger(value)
    return type(value) == 'number' and value == math.floor(value)
end

function FrontierLib.IsPositiveNumber(value)
    return type(value) == 'number' and value > 0 and value < math.huge
end

function FrontierLib.IsValidSource(source)
    return FrontierLib.IsInteger(source) and source > 0
end

function FrontierLib.Trim(value)
    if type(value) ~= 'string' then
        return ''
    end

    return value:match('^%s*(.-)%s*$') or ''
end

function FrontierLib.Clamp(value, minimum, maximum)
    if type(value) ~= 'number' then
        return minimum
    end

    return math.max(minimum, math.min(maximum, value))
end
