local core = exports.frontier_core

local messages = {
    account_not_found = 'Das Konto wurde nicht gefunden.',
    character_changed = 'Der Charakter hat während der Anfrage gewechselt.',
    character_unavailable = 'Der Charakter ist noch nicht geladen.',
    database_error = 'Die Wirtschaftsdatenbank ist momentan nicht verfügbar. Bei Wiederholung dieselbe Vorgangskennung verwenden.',
    idempotency_conflict = 'Diese Vorgangskennung wurde bereits für andere Daten verwendet.',
    invalid_amount = 'Der Betrag muss eine positive ganze Zahl in Cent sein.',
    invalid_key = 'Die Vorgangskennung muss aus 1 bis 96 Zeichen bestehen (A–Z, 0–9, Punkt, Unterstrich, Doppelpunkt, Bindestrich).',
    invalid_reason = 'Der Grund fehlt oder ist zu lang (maximal 255 Byte).',
    balance_limit = 'Das Guthaben würde die Kontogrenze überschreiten.',
}

local function reply(playerSource, message)
    if playerSource == 0 then
        print(('[Frontier Wirtschaft] %s'):format(message))
    else
        TriggerClientEvent('chat:addMessage', playerSource, { args = { 'Frontier Wirtschaft', message } })
    end
end

local function reportError(playerSource, code)
    reply(playerSource, messages[code] or 'Der Vorgang konnte nicht abgeschlossen werden.')
end

local function formatMoney(minor)
    return ('%d,%02d $'):format(minor // 100, minor % 100)
end

local function parsePositive(text, maximum)
    if type(text) == 'string' and #text <= 16 and text:match('^[0-9]+$') then
        local value = tonumber(text)
        if Economy.PositiveInteger(value, maximum) then
            return value
        end
    end
end

RegisterCommand(EconomyConfig.BalanceCommand, function(playerSource, args)
    if playerSource == 0 or #args ~= 0 then
        reply(playerSource, ('Im Spiel ohne Parameter verwenden: /%s'):format(EconomyConfig.BalanceCommand))
        return
    end
    local ok, accounts = Economy.GetCharacterAccounts(playerSource)
    if not ok then
        reportError(playerSource, accounts)
        return
    end
    reply(playerSource, ('Bargeld: %s | Bank: %s'):format(
        formatMoney(accounts.cash.balance_minor), formatMoney(accounts.bank.balance_minor)
    ))
end, false)

RegisterCommand(EconomyConfig.AdminCreditCommand, function(playerSource, args)
    if playerSource ~= 0 and not core:HasPermission(playerSource, EconomyConfig.AdminPermission) then
        FrontierLib.Log('WARN', Economy.Resource, 'Unauthorized economy admin command', { source = playerSource })
        reply(playerSource, 'Dir fehlt die Berechtigung für diesen Befehl.')
        return
    end

    local target = parsePositive(args[1], 2147483647)
    local inputType = args[2]
    local amount = parsePositive(args[3], Economy.MaxMinor)
    if not target or (inputType ~= 'bar' and inputType ~= 'bank') or not amount or #args < 5 then
        reply(playerSource, ('Verwendung: /%s <Spieler-ID> <bar|bank> <Cent> <Vorgangskennung> <Grund>'):format(
            EconomyConfig.AdminCreditCommand
        ))
        return
    end

    local adminLicense = playerSource ~= 0 and GetPlayerIdentifierByType(playerSource, 'license')
    local ok, accounts = Economy.GetCharacterAccounts(target)
    if playerSource ~= 0 and (not adminLicense
        or GetPlayerIdentifierByType(playerSource, 'license') ~= adminLicense
        or not core:HasPermission(playerSource, EconomyConfig.AdminPermission)) then
        return
    end
    if not ok then
        reportError(playerSource, accounts)
        return
    end

    local account = accounts[inputType == 'bar' and 'cash' or 'bank']
    local applied, result = Economy.Apply('admin:command', 'credit', 0, account.id, amount, {
        key = args[4],
        reason = table.concat(args, ' ', 5),
        metadataJson = json.encode({ admin = adminLicense or 'server_console' }),
    })
    FrontierLib.Log(applied and 'INFO' or 'WARN', Economy.Resource, 'Economy admin credit attempted', {
        source = playerSource, accountId = account.id, amountMinor = amount,
        operationId = applied and result.operationId or nil,
        replayed = applied and result.replayed or nil,
        error = not applied and result or nil,
    })
    if playerSource ~= 0 and GetPlayerIdentifierByType(playerSource, 'license') ~= adminLicense then
        return
    end
    if not applied then
        reportError(playerSource, result)
        return
    end
    reply(playerSource, ('Gutschrift %s. Vorgang: %s.'):format(
        result.replayed and 'war bereits verbucht' or 'wurde verbucht', result.operationId
    ))
end, false)
