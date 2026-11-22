function Frontier.HasPermission(source, permission)
    source = tonumber(source)

    if not FrontierLib.IsValidSource(source) then
        return false
    end

    if type(permission) ~= 'string' or permission == '' then
        return false
    end

    -- RedM may return 1/0 instead of true/false.
    local allowed = IsPlayerAceAllowed(source, permission)

    return allowed == true or allowed == 1
end