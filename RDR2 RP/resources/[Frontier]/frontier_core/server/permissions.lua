function Frontier.HasPermission(source, permission)
    source = tonumber(source)

    if not FrontierLib.IsValidSource(source) then
        return false
    end

    if type(permission) ~= 'string' or permission == '' then
        return false
    end

    -- ACE remains the permission source until Frontier has its own staff/group system.
    return IsPlayerAceAllowed(source, permission) == true
end
