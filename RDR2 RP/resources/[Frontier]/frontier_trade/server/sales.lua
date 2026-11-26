local core, economy, inventory = exports.frontier_core, exports.frontier_economy, exports.frontier_inventory
local cfg = TradeConfig
local busy = {}

local function db(method, statement, args)
    local ok, result = pcall(MySQL[method].await, statement, args)
    if ok then return result end
    FrontierLib.Log('WARN','frontier_trade','Sale database request failed',{method=method})
end

local function uuid(value)
    return type(value)=='string' and #value==36 and value:match('^[a-f0-9-]+$')
end

local function int(value,limit)
    return value and value>=1 and value<=limit and value==math.floor(value)
end

local function procedure(action,id,offer,actor,bank,quantity)
    local rows=db('query','CALL frontier_trade_sale_v1(?, ?, ?, ?, ?, ?)',
        {action,id,offer or '',actor or '',bank or 0,quantity or 0})
    return rows and rows[1] and rows[1][1] and rows[1][1].code=='ok'
end

local function tell(source,message)
    TriggerClientEvent('chat:addMessage',source,{args={'Frontier Handel',message}})
end

local function command(name,handler)
    RegisterCommand(name,function(source,args)
        if source==0 or busy[source] then return end
        local actor=core:GetPlayerCharacterId(source)
        if not actor then return end
        busy[source]=true
        local ok,message=pcall(handler,source,actor,args)
        busy[source]=nil
        if core:GetPlayerCharacterId(source)==actor then
            tell(source,ok and message or 'Der Markt ist momentan nicht verfügbar.')
        end
    end,false)
end

local function bank(source,actor)
    local ok,accounts=economy:GetCharacterAccounts(source)
    if ok and accounts.characterId==actor and core:GetPlayerCharacterId(source)==actor then return accounts.bank.id end
end


local function farmSaleAllowed(typ,id,item)
 if not TradeConfig.Agricultural[item] then return true end
 return GetResourceState('frontier_business')=='started' and exports.frontier_business:VerifyLicense(typ,id,'agriculture')
end

command('handelsangebot',function(source,actor,args)
    local market,item=args[1],args[2]
    local count,price=tonumber(args[3]),tonumber(args[4])
    if not market or not cfg.Markets[market] or not item or not cfg.Products[item]
        or not int(count,math.min(cfg.MaxQuantity,1000)) or not int(price,math.min(cfg.MaxUnitMinor,10000)) then
        return 'Verwendung: /handelsangebot <Markt> <Ware> <Menge> <Cent je Stück>'
    end
    if not farmSaleAllowed('character',actor,item) then return 'Agriculture license required.' end
    local found,def=inventory:GetTradeItemDefinition(item)
    if not found or not def.transferable then return 'Diese Ware ist nicht handelbar.' end
    local id=db('scalar','SELECT UUID()')
    local account=bank(source,actor)
    if not uuid(id) or not account then return 'Angebot konnte nicht angelegt werden.' end
    local saved=db('update',[[
        INSERT INTO frontier_trade_offers
        (id,seller_id,seller_bank,market_id,item_id,quantity,available,unit_minor,expires_at)
        VALUES (?,?,?,?,?,?,?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL ? HOUR))
    ]],{id,actor,account,market,item,count,count,price,cfg.LifetimeHours})
    return (saved==1 and 'Warenreservierung läuft. Angebots-ID: ' or
        'Angebot nicht bestätigt. Prüfe das Angebot unter dieser ID: ')..id
end)

command('handelskaufen',function(source,actor,args)
    local count=tonumber(args[2])
    if not uuid(args[1]) or not int(count,1000) then return 'Verwendung: /handelskaufen <Angebots-ID> <Menge>' end
    local id=db('scalar','SELECT UUID()')
    local account=bank(source,actor)
    if not uuid(id) or not account then return 'Kauf konnte nicht angelegt werden.' end
    if procedure('buy',id,args[1],actor,account,count) then return 'Kauf in Abwicklung. Kauf-ID: '..id end
    return 'Kauf nicht bestätigt. Prüfe diese Kauf-ID: '..id
end)

command('handelsangebotstorno',function(_,actor,args)
    if not uuid(args[1]) then return 'Verwendung: /handelsangebotstorno <Angebots-ID>' end
    local count=db('update',[[
        UPDATE frontier_trade_offers SET state='return',retry_at=UTC_TIMESTAMP()
        WHERE id=? AND seller_id=? AND state='open' AND active_sale IS NULL
    ]],{args[1],actor})
    return count==1 and 'Die Warenrückgabe wurde vorgemerkt.' or 'Das Angebot kann gerade nicht storniert werden.'
end)

command('handelskaufabholung',function(_,actor,args)
    if not uuid(args[1]) then return 'Verwendung: /handelskaufabholung <Kauf-ID>' end
    local row=db('single',[[
        SELECT s.id,s.quantity,s.claimed_at,o.item_id
        FROM frontier_trade_sales s JOIN frontier_trade_offers o ON o.id=s.offer_id
        WHERE s.id=? AND s.buyer_id=? AND s.state='complete'
    ]],{args[1],actor})
    if not row then return 'Kauf nicht verfügbar.' end
    if row.claimed_at then return 'Kauf bereits abgeholt.' end
    if not inventory:ClaimTradeDelivery(row.id,actor,row.item_id,tonumber(row.quantity)) then
        return 'Abholung nicht bestätigt. Prüfe Gewicht und freie Plätze.'
    end
    db('update','UPDATE frontier_trade_sales SET claimed_at=UTC_TIMESTAMP() WHERE id=? AND claimed_at IS NULL',{row.id})
    return 'Ware erhalten.'
end)

local function offerState(row,state)
    db('update','UPDATE frontier_trade_offers SET state=?,retry_at=UTC_TIMESTAMP() WHERE id=? AND state=?',
        {state,row.id,row.state})
end

local function saleState(row,state)
    db('update','UPDATE frontier_trade_sales SET state=?,retry_at=UTC_TIMESTAMP() WHERE id=? AND state=?',
        {state,row.id,row.state})
end

local function offerStep(row)
    if row.state=='stock' then
        local ok,reason=inventory:ReserveTradeDelivery(row.id,row.seller_id,row.item_id,tonumber(row.quantity))
        if ok then offerState(row,'open'); return end
        if reason=='insufficient_stock' or reason=='not_found' or reason=='invalid_item'
            or reason=='slots' or reason=='weight' then offerState(row,'rejected'); return end
    elseif inventory:ClaimTradeDelivery(row.id,row.seller_id,row.item_id,tonumber(row.available)) then
        offerState(row,'closed'); return
    end
    db('update','UPDATE frontier_trade_offers SET retry_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 30 SECOND) WHERE id=? AND state=?',
        {row.id,row.state})
end

local function saleStep(row)
    if row.state=='stock' then
        if inventory:MoveTradeSaleStock(row.id,row.offer_id,row.item_id,tonumber(row.quantity),false) then
            saleState(row,'payment'); return
        end
    elseif row.state=='payment' then
        local ok,reason=economy:PayTradeSale(row.id,row.buyer_id,tonumber(row.buyer_bank),row.seller_id,
            tonumber(row.seller_bank),tonumber(row.quantity)*tonumber(row.unit_minor))
        if ok then procedure('complete',row.id); return end
        if reason=='insufficient_funds' or reason=='balance_limit' then saleState(row,'reverse'); return end
    elseif inventory:MoveTradeSaleStock(row.id,row.offer_id,row.item_id,tonumber(row.quantity),true) then
        procedure('reject',row.id); return
    end
    db('update','UPDATE frontier_trade_sales SET retry_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 30 SECOND) WHERE id=? AND state=?',
        {row.id,row.state})
end

local function process(rows,handler)
    for _,row in ipairs(rows or {}) do
        local ok=pcall(handler,row)
        if not ok then FrontierLib.Log('WARN','frontier_trade','Sale job will retry',{id=row.id}) end
    end
end

MySQL.ready(function()
    while true do
        db('update',[[
            UPDATE frontier_trade_offers SET state='return',retry_at=UTC_TIMESTAMP()
            WHERE state='open' AND active_sale IS NULL AND expires_at<=UTC_TIMESTAMP()
            ORDER BY expires_at,id LIMIT ?
        ]],{cfg.Batch})
        process(db('query',[[
            SELECT id,seller_id,item_id,quantity,available,state FROM frontier_trade_offers
            WHERE state IN ('stock','return') AND retry_at<=UTC_TIMESTAMP() ORDER BY retry_at,id LIMIT ?
        ]],{cfg.Batch}),offerStep)
        process(db('query',[[
            SELECT s.id,s.offer_id,s.buyer_id,s.buyer_bank,s.quantity,s.state,o.seller_id,o.seller_bank,o.item_id,o.unit_minor
            FROM frontier_trade_sales s JOIN frontier_trade_offers o ON o.id=s.offer_id
            WHERE s.state IN ('stock','payment','reverse') AND s.retry_at<=UTC_TIMESTAMP()
            ORDER BY s.retry_at,s.id LIMIT ?
        ]],{cfg.Batch}),saleStep)
        Wait(cfg.WorkerIntervalMs)
    end
end)
