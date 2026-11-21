local levels = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
}

local configuredLevel = GetConvar('frontier_log_level', 'INFO'):upper()
local threshold = levels[configuredLevel] or levels.INFO

local function serializeContext(context)
    if context == nil then
        return ''
    end

    local ok, encoded = pcall(json.encode, context)
    return ok and encoded or '<context serialization failed>'
end

function FrontierLib.Log(level, resource, message, context)
    level = type(level) == 'string' and level:upper() or 'INFO'
    if not levels[level] then
        level = 'INFO'
    end

    if levels[level] < threshold then
        return
    end

    resource = type(resource) == 'string' and resource or GetCurrentResourceName()
    message = tostring(message or '')
    local contextText = serializeContext(context)

    if contextText ~= '' then
        print(('[FRONTIER][%s][%s] %s | %s'):format(level, resource, message, contextText))
    else
        print(('[FRONTIER][%s][%s] %s'):format(level, resource, message))
    end
end

function FrontierLib.GetLogLevel()
    return configuredLevel
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        FrontierLib.Log('INFO', resourceName, 'Shared library initialized', {
            version = FrontierLib.VERSION,
            logLevel = configuredLevel,
        })
    end
end)
