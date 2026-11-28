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
        if resource ~= 'frontier_trade' and not ((resource=='frontier_logistics' or resource=='frontier_jobs') and (name=='FundTradeHold' or name=='ReleaseTradeHold' or name=='PayTradeDelivery')) then return false, 'forbidden' end
        return handler(...)
    end)
end

local function tradePayment(owner, account, amount, apply, reference)
    local ok, result = apply()
    if ok or result ~= 'insufficient_funds' or owner:sub(1,4) ~= 'npc_' then return ok, result end
    local verified, npc = Economy.Db('scalar', [[
        SELECT id FROM frontier_economy_accounts
        WHERE id=? AND owner_type='trade_npc' AND owner_id=? AND account_type='bank'
    ]], {account,owner})
    if not verified then return false,npc end
    if tonumber(npc) ~= account then return false,'forbidden' end
    if amount > 10000000 then return false,'invalid_amount' end
    local funded, issue = Economy.Apply('trade:escrow','credit',0,account,amount,
        { key=reference..':npc-topup', reason='NPC-Marktkasse aufgefüllt' })
    if not funded then return false,issue end
    return apply()
end

tradeExport('ProvisionTradeNpc', function(owner)
    if type(owner) ~= 'string' or #owner > 48 or not owner:match('^npc_[a-z0-9_]+$') then
        return false,'invalid_request'
    end
    local ok, issue = Economy.Db('query','CALL frontier_economy_provision_trade_npc(?)',{owner})
    if not ok then return false,issue end
    local loaded,id = Economy.Db('scalar',[[
        SELECT id FROM frontier_economy_accounts
        WHERE owner_type='trade_npc' AND owner_id=? AND account_type='bank' AND currency='USD'
    ]],{owner})
    if not loaded or not id then return false,'database_error' end
    return true,tonumber(id)
end)

tradeExport('FundTradeHold', function(reference, character, bankId, amount)
    if not validReference(reference) or type(character) ~= 'string'
        or not Economy.PositiveInteger(bankId, Economy.MaxId)
        or not Economy.PositiveInteger(amount, Economy.MaxMinor) then return false, 'invalid_request' end
    local checked, bank = Economy.Db('scalar', [[
        SELECT id FROM frontier_economy_accounts
        WHERE id = ? AND owner_type IN ('character','trade_npc','business') AND owner_id = ?
          AND account_type = 'bank' AND currency = 'USD'
    ]], { bankId, character })
    if not checked then return false, bank end
    if tonumber(bank) ~= bankId then return false, 'forbidden' end

    local created, issue = Economy.Db('query', 'CALL frontier_economy_provision_trade_hold(?)', { reference })
    if not created then return false, issue end
    local loaded, hold = holdAccount(reference)
    if not loaded then return false, hold end
    return tradePayment(character,bankId,amount,function()
        return Economy.Apply('trade:escrow','transfer',bankId,tonumber(hold),amount,
            { key=reference..':fund', reason='Handelsbudget reserviert' })
    end,reference)
end)

tradeExport('ReleaseTradeHold', function(reference, character, bankId, amount)
    if not validReference(reference) or type(character) ~= 'string'
        or not Economy.PositiveInteger(bankId, Economy.MaxId)
        or not Economy.PositiveInteger(amount, Economy.MaxMinor) then return false, 'invalid_request' end
    local ok, bank = Economy.Db('scalar', [[
        SELECT id FROM frontier_economy_accounts WHERE id = ? AND owner_type IN ('character','trade_npc','business')
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
        SELECT id FROM frontier_economy_accounts WHERE id = ? AND owner_type IN ('character','trade_npc','business')
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

tradeExport('PayTradeSale', function(reference, buyer, debit, seller, credit, amount)
    if not validReference(reference) or type(buyer) ~= 'string' or type(seller) ~= 'string'
        or buyer == seller or not Economy.PositiveInteger(debit, Economy.MaxId)
        or not Economy.PositiveInteger(credit, Economy.MaxId)
        or not Economy.PositiveInteger(amount, Economy.MaxMinor) then return false, 'invalid_request' end
    local ok, count = Economy.Db('scalar', [[
        SELECT COUNT(*) FROM frontier_economy_accounts
        WHERE owner_type IN ('character','trade_npc','business') AND account_type='bank' AND currency='USD'
          AND ((id=? AND owner_id=?) OR (id=? AND owner_id=?))
    ]], { debit, buyer, credit, seller })
    if not ok then return false, count end
    if tonumber(count) ~= 2 then return false, 'forbidden' end
    return tradePayment(buyer,debit,amount,function()
        return Economy.Apply('trade:escrow','transfer',debit,credit,amount,
            { key=reference..':sale', reason='Marktverkauf bezahlt' })
    end,reference)
end)
