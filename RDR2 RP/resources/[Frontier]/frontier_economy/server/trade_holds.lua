local function validReference(value)
    return type(value) == 'string' and #value == 36 and value:match('^[a-f0-9-]+$') ~= nil
end

local function holdAccount(reference)
    return Economy.Db('scalar', [[
        SELECT id FROM frontier_economy_accounts
        WHERE owner_type = 'trade_hold' AND owner_id = ? AND account_type = 'escrow' AND currency = 'USD'
    ]], { reference })
end

local function tradeExport(name, handler)
    Economy.Export(name, function(resource, ...)
        if resource ~= 'frontier_trade' then return false, 'forbidden' end
        return handler(...)
    end)
end

tradeExport('FundTradeHold', function(reference, character, bankId, amount)
    if not validReference(reference) or type(character) ~= 'string'
        or not Economy.PositiveInteger(bankId, Economy.MaxId)
        or not Economy.PositiveInteger(amount, Economy.MaxMinor) then return false, 'invalid_request' end
    local checked, bank = Economy.Db('scalar', [[
        SELECT id FROM frontier_economy_accounts
        WHERE id = ? AND owner_type = 'character' AND owner_id = ?
          AND account_type = 'bank' AND currency = 'USD'
    ]], { bankId, character })
    if not checked then return false, bank end
    if tonumber(bank) ~= bankId then return false, 'forbidden' end

    local created, issue = Economy.Db('query', 'CALL frontier_economy_provision_trade_hold(?)', { reference })
    if not created then return false, issue end
    local loaded, hold = holdAccount(reference)
    if not loaded then return false, hold end
    return Economy.Apply('trade:escrow', 'transfer', bankId, tonumber(hold), amount,
        { key = reference .. ':fund', reason = 'Handelsbudget reserviert' })
end)

tradeExport('ReleaseTradeHold', function(reference, character, bankId, amount)
    if not validReference(reference) or type(character) ~= 'string'
        or not Economy.PositiveInteger(bankId, Economy.MaxId)
        or not Economy.PositiveInteger(amount, Economy.MaxMinor) then return false, 'invalid_request' end
    local ok, bank = Economy.Db('scalar', [[
        SELECT id FROM frontier_economy_accounts WHERE id = ? AND owner_type = 'character'
          AND owner_id = ? AND account_type = 'bank' AND currency = 'USD'
    ]], { bankId, character })
    if not ok then return false, bank end
    if tonumber(bank) ~= bankId then return false, 'forbidden' end
    -- Require the original funding entry from the same buyer and for the same amount.
    local verified, match = Economy.Db('scalar', [[
        SELECT l.account_id FROM frontier_economy_operations o
        JOIN frontier_economy_ledger l ON l.operation_id = o.id
        WHERE o.actor = 'trade:escrow' AND o.request_key = ? AND o.completed = TRUE
          AND l.entry_type = 'debit' AND l.account_id = ? AND l.amount_minor = ?
    ]], { reference .. ':fund', bankId, amount })
    if not verified then return false, match end
    if tonumber(match) ~= bankId then return false, 'forbidden' end
    local loaded, hold = holdAccount(reference)
    if not loaded then return false, hold end
    return Economy.Apply('trade:escrow', 'transfer', tonumber(hold), bankId, amount,
        { key = reference .. ':release', reason = 'Handelsbudget freigegeben' })
end)

local function settle(reference, operation, character, bankId, amount, refund)
    if not validReference(reference) or not validReference(operation) or type(character) ~= 'string'
        or not Economy.PositiveInteger(bankId, Economy.MaxId)
        or not Economy.PositiveInteger(amount, Economy.MaxMinor) then return false, 'invalid_request' end
    local ok, bank = Economy.Db('scalar', [[
        SELECT id FROM frontier_economy_accounts WHERE id = ? AND owner_type = 'character'
          AND owner_id = ? AND account_type = 'bank' AND currency = 'USD'
    ]], { bankId, character })
    if not ok then return false, bank end
    if tonumber(bank) ~= bankId then return false, 'forbidden' end
    if refund then
        local verified, original = Economy.Db('scalar', [[
            SELECT l.account_id FROM frontier_economy_operations o
            JOIN frontier_economy_ledger l ON l.operation_id = o.id
            WHERE o.actor = 'trade:escrow' AND o.request_key = ? AND o.completed = TRUE
              AND l.entry_type = 'debit' AND l.account_id = ?
        ]], { reference .. ':fund', bankId })
        if not verified then return false, original end
        if tonumber(original) ~= bankId then return false, 'forbidden' end
    end
    local loaded, hold = holdAccount(reference)
    if not loaded then return false, hold end
    return Economy.Apply('trade:escrow', 'transfer', tonumber(hold), bankId, amount, {
        key = operation .. (refund and ':remainder' or ':delivery'),
        reason = refund and 'Restbudget freigegeben' or 'Handelslieferung bezahlt',
    })
end

tradeExport('PayTradeDelivery', function(reference, operation, character, bankId, amount)
    return settle(reference, operation, character, bankId, amount, false)
end)
tradeExport('RefundTradeRemainder', function(reference, character, bankId, amount)
    return settle(reference, reference, character, bankId, amount, true)
end)
