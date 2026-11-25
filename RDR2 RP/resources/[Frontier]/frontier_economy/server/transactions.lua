local applySql = 'CALL frontier_economy_apply_v1(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'

local function validText(value, maximum)
    return type(value) == 'string' and #value <= maximum and utf8.len(value) ~= nil
end

local function accountId(value, required)
    if value == 0 and not required then
        return true
    end
    return Economy.PositiveInteger(value, Economy.MaxId)
end

function Economy.Apply(actor, kind, debitId, creditId, amount, options)
    if not accountId(debitId, kind ~= 'credit') or not accountId(creditId, kind ~= 'debit') then
        return false, 'invalid_account'
    end
    if debitId == creditId then
        return false, 'same_account'
    end
    if not Economy.PositiveInteger(amount, Economy.MaxMinor) then
        return false, 'invalid_amount'
    end
    if type(options) ~= 'table' then
        return false, 'invalid_options'
    end

    local key = options.key
    if type(key) ~= 'string' or #key > 96 or not key:match('^[A-Za-z0-9_.:%-]+$') then
        return false, 'invalid_key'
    end

    local reason = options.reason
    local reference = options.reference == nil and '' or options.reference
    local metadata = options.metadataJson == nil and '{}' or options.metadataJson
    if not validText(reason, 255) or FrontierLib.Trim(reason) == '' then
        return false, 'invalid_reason'
    end
    if not validText(reference, 128) then
        return false, 'invalid_reference'
    end
    if not validText(metadata, 4096) then
        return false, 'invalid_metadata'
    end

    if actor ~= 'trade:escrow' then
        -- Company accounts are not generic resource wallets. Business and the verified Trade escrow adapter are the only writers.
        if actor ~= 'resource:frontier_business' then
            local checked,company=Economy.Db('scalar',"SELECT COUNT(*) FROM frontier_economy_accounts WHERE id IN (?,?) AND owner_type='business'",{debitId,creditId})
            if not checked then return false,company end
            if tonumber(company)~=0 then return false,'forbidden' end
        end
        local checked, reserved = Economy.Db('scalar', [[
            SELECT COUNT(*) FROM frontier_economy_accounts
            WHERE id IN (?, ?) AND owner_type IN ('trade_hold','trade_npc')
        ]], { debitId, creditId })
        if not checked then return false, reserved end
        if tonumber(reserved) ~= 0 then return false, 'forbidden' end
    end

    local ok, result = Economy.Db('query', applySql, {
        actor, key, kind, debitId, creditId, amount, reason, reference, metadata, 'USD',
    })
    if not ok then
        return false, result
    end
    local receipt = result and type(result[1]) == 'table' and result[1][1]
    if not receipt or type(receipt.code) ~= 'string' then
        FrontierLib.Log('ERROR', Economy.Resource, 'Missing economy operation receipt', { kind = kind })
        return false, 'database_error'
    end
    if receipt.code ~= 'ok' then
        FrontierLib.Log('DEBUG', Economy.Resource, 'Economy operation rejected', {
            actor = actor, kind = kind, code = receipt.code,
        })
        return false, receipt.code
    end
    if type(receipt.operation_id) ~= 'string' then
        FrontierLib.Log('ERROR', Economy.Resource, 'Invalid economy operation ID', { kind = kind })
        return false, 'database_error'
    end
    return true, {
        operationId = receipt.operation_id,
        replayed = tonumber(receipt.replayed) == 1,
    }
end

Economy.Export('CreditAccount', function(resource, id, amount, options)
    return Economy.Apply('resource:' .. resource, 'credit', 0, id, amount, options)
end)

Economy.Export('DebitAccount', function(resource, id, amount, options)
    return Economy.Apply('resource:' .. resource, 'debit', id, 0, amount, options)
end)

Economy.Export('TransferAccounts', function(resource, fromId, toId, amount, options)
    return Economy.Apply('resource:' .. resource, 'transfer', fromId, toId, amount, options)
end)

local function stillAuthorized(guard, sender, recipient)
    return not guard or guard(sender, recipient)
end

function Economy.MoveCharacterFunds(actor, playerSource, fromType, toType, amount, options, guard)
    local ok, accounts = Economy.GetCharacterAccounts(playerSource)
    if not ok then
        return false, accounts
    end
    if not stillAuthorized(guard, accounts.characterId) then
        return false, 'character_changed'
    end
    return Economy.Apply(actor, 'transfer', accounts[fromType].id, accounts[toType].id, amount, options)
end

Economy.Export('Deposit', function(resource, playerSource, amount, options)
    return Economy.MoveCharacterFunds('resource:' .. resource, playerSource, 'cash', 'bank', amount, options)
end)

Economy.Export('Withdraw', function(resource, playerSource, amount, options)
    return Economy.MoveCharacterFunds('resource:' .. resource, playerSource, 'bank', 'cash', amount, options)
end)

function Economy.TransferCharacters(actor, fromSource, toSource, amount, options, guard)
    local senderOk, sender = Economy.GetCharacterAccounts(fromSource)
    if not senderOk then
        return false, sender
    end
    local receiverOk, receiver = Economy.GetCharacterAccounts(toSource)
    if not receiverOk then
        return false, receiver
    end
    if not Economy.IsCurrentCharacter(fromSource, sender.characterId)
        or not Economy.IsCurrentCharacter(toSource, receiver.characterId)
        or not stillAuthorized(guard, sender.characterId, receiver.characterId) then
        return false, 'character_changed'
    end
    return Economy.Apply(actor, 'transfer', sender.bank.id, receiver.bank.id, amount, options)
end

Economy.Export('TransferCharacters', function(resource, fromSource, toSource, amount, options)
    return Economy.TransferCharacters('resource:' .. resource, fromSource, toSource, amount, options)
end)

local function history(accountId, limit)
    if not Economy.PositiveInteger(accountId, Economy.MaxId) then
        return false, 'invalid_account'
    end
    if limit == nil then
        limit = Economy.DefaultHistoryLimit
    end
    if not Economy.PositiveInteger(limit, Economy.MaxHistoryLimit) then
        return false, 'invalid_limit'
    end
    local ok, rows = Economy.Db('query', [[
        SELECT CAST(l.id AS CHAR) AS id, l.account_id, l.entry_type, l.amount_minor, l.currency,
               l.balance_before, l.balance_after, l.related_account_id,
               CAST(l.operation_id AS CHAR) AS operation_id,
               DATE_FORMAT(l.created_at, '%Y-%m-%dT%H:%i:%s.%fZ') AS created_at,
               o.kind, o.actor, o.request_key, o.reason, o.reference_text, o.metadata_json
        FROM frontier_economy_ledger l
        JOIN frontier_economy_operations o ON o.id = l.operation_id
        WHERE l.account_id = ?
        ORDER BY l.id DESC
        LIMIT ?
    ]], { accountId, limit })
    if not ok then
        return false, rows
    end
    for _, row in ipairs(rows) do
        row.account_id = tonumber(row.account_id)
        row.related_account_id = tonumber(row.related_account_id)
        row.amount_minor = tonumber(row.amount_minor)
        row.balance_before = tonumber(row.balance_before)
        row.balance_after = tonumber(row.balance_after)
    end
    return true, rows
end

Economy.Export('GetAccountTransactions', function(_, id, limit)
    return history(id, limit)
end)
function Economy.GetCharacterTransactions(playerSource, accountType, limit)
    if accountType ~= 'cash' and accountType ~= 'bank' then
        return false, 'invalid_account'
    end
    local ok, accounts = Economy.GetCharacterAccounts(playerSource)
    if not ok then
        return false, accounts
    end
    local read, result = history(accounts[accountType].id, limit)
    if not Economy.IsCurrentCharacter(playerSource, accounts.characterId) then
        return false, 'character_changed'
    end
    return read, result
end

Economy.Export('GetCharacterTransactions', function(_, playerSource, accountType, limit)
    return Economy.GetCharacterTransactions(playerSource, accountType, limit)
end)

-- Multi-shareholder payouts and terminal wage decisions share a single atomic ledger operation.
Economy.Export('TransferBusinessBatch',function(resource,job,from,payments,reserve,skip)
    if resource~='frontier_business' then return false,'forbidden' end
    if type(job)~='string' or #job~=32 or not job:match('^[a-f0-9]+$')
        or not Economy.PositiveInteger(from,Economy.MaxId) or type(payments)~='table'
        or type(reserve)~='number' or reserve%1~=0 or reserve<0 or reserve>Economy.MaxMinor
        or type(skip)~='boolean' then return false,'invalid_request' end
    local list,seen,total={},{},0
    for _,p in ipairs(payments) do
        if type(p)~='table' or not Economy.PositiveInteger(p.to,Economy.MaxId) or p.to==from or seen[p.to]
            or not Economy.PositiveInteger(p.amount,Economy.MaxMinor) or total>Economy.MaxMinor-p.amount then return false,'invalid_request' end
        seen[p.to]=true;total=total+p.amount;list[#list+1]={p.to,p.amount}
    end
    if #list<1 or #list>10000 then return false,'invalid_request' end
    table.sort(list,function(a,b) return a[1]<b[1] end)
    local ok,result=Economy.Db('query','CALL frontier_economy_business_batch_v1(?,?,?,?,?)',
        {'business:'..job..':batch',from,reserve,json.encode(list),skip and 1 or 0})
    if not ok then return false,result end
    local row=result and type(result[1])=='table' and result[1][1]
    if not row or type(row.code)~='string' then return false,'database_error' end
    if row.code~='ok' then return false,row.code end
    return true,{operationId=row.operation_id,replayed=tonumber(row.replayed)==1}
end)
