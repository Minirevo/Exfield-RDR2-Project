Economy = {
    Resource = GetCurrentResourceName(),
    MaxMinor = 9000000000000,
    MaxId = 9007199254740991,
    DefaultHistoryLimit = 25,
    MaxHistoryLimit = 100,
}

function Economy.Db(method, statement, parameters)
    local ok, result = pcall(MySQL[method].await, statement, parameters)
    if not ok then
        FrontierLib.Log('ERROR', Economy.Resource, 'Economy database request failed', { method = method })
        return false, 'database_error'
    end
    return true, result
end

function Economy.PositiveInteger(value, maximum)
    return type(value) == 'number' and value > 0 and value <= maximum
        and FrontierLib.IsInteger(value)
end

function Economy.Export(name, handler)
    exports(name, function(...)
        local caller = GetInvokingResource()
        if not caller or EconomyConfig.TrustedResources[caller] ~= true then
            return false, 'forbidden'
        end
        return handler(caller, ...)
    end)
end
