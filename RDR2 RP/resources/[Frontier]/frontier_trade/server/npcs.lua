local cfg=TradeConfig
local economy,inventory,core=exports.frontier_economy,exports.frontier_inventory,exports.frontier_core

local function db(method,sql,args)
    local ok,result=pcall(MySQL[method].await,sql,args)
    if ok then return result end
    FrontierLib.Log('WARN','frontier_trade','NPC transaction will retry',{method=method})
end

local function key(owner,epoch,step)
    return db('scalar',"SELECT SUBSTRING(SHA2(CONCAT(?, ':', ?, ':', ?),256),1,36)",{owner,epoch,step})
end

local function procedure(name,action,id,parent,owner,value,last)
    if not id then return false end
    local rows=db('query',name=='sale' and 'CALL frontier_trade_sale_v1(?, ?, ?, ?, ?, ?)'
        or 'CALL frontier_trade_contract_v1(?, ?, ?, ?, ?, ?)',{action,id,parent,owner,value,last or 0})
    if not rows then return nil end
    return rows[1] and rows[1][1] and rows[1][1].code=='ok'
end

local function valid(npc)
    return type(npc)=='table' and cfg.Markets[npc.market] and cfg.Products[npc.item]
        and npc.minimum>=1 and npc.minimum<=npc.target and npc.target<npc.maximum
        and npc.maximum<=1000 and npc.price>=1 and npc.price<=10000
        and npc.consume>=0 and npc.consume<=npc.maximum and npc.produce>=0 and npc.produce<=npc.maximum
        and npc.chance>=0 and npc.chance<=100
end

local function stock(owner,npc,epoch)
    local ok,count=inventory:GetTradeNpcStock(owner,npc.item)
    if not ok then return nil end
    for _,rule in ipairs({ {take=npc.consume,step='consume'}, {give=npc.produce,step='produce'} }) do
        local amount=rule.take or rule.give
        if amount>0 and ((rule.take and count>=amount) or (rule.give and count+amount<=npc.maximum)) then
            local id=key(owner,epoch,rule.step)
            if not id then return nil end
            local done,why=inventory:ChangeTradeNpcStock(owner,npc.item,amount,rule.give~=nil,id)
            if not done and why~='weight' and why~='slots' and why~='quantity' then return nil end
            ok,count=inventory:GetTradeNpcStock(owner,npc.item)
            if not ok then return nil end
        end
    end
    return count
end

local function fulfill(owner,npc,epoch,account,count)
    local contract=db('single',[[
        SELECT c.id,c.active_delivery,r.quantity-r.settled_quantity AS remaining
        FROM frontier_trade_contracts c JOIN frontier_trade_requests r ON r.id=c.request_id
        WHERE c.seller_id=? AND c.state='active' AND c.due_at>UTC_TIMESTAMP() LIMIT 1
    ]],{owner})
    if contract then
        if not contract.active_delivery and count>0 then
            local queued=procedure('contract','deliver',key(owner,epoch,'deliver'),contract.id,owner,
                math.min(count,tonumber(contract.remaining)),0)
            return queued~=nil
        end
        return true
    end
    if count<=npc.minimum then return false end
    local roll=key(owner,epoch,'competition')
    if not roll or tonumber(roll:sub(1,6),16)%100>=npc.chance then return false end
    local row=db('single',[[
        SELECT id,COALESCE(quote_minor,price_minor) AS quote
        FROM frontier_trade_requests
        WHERE market_id=? AND item_id=? AND state='open' AND active_contract IS NULL
          AND buyer_id<>? AND expires_at>UTC_TIMESTAMP() AND quantity-settled_quantity<=?
          AND COALESCE(quote_minor,price_minor)>=?
        ORDER BY quote DESC,expires_at,id LIMIT 1
    ]],{npc.market,npc.item,owner,count-npc.minimum,npc.price})
    if not row then return false end
    local id=key(owner,epoch,'contract')
    local accepted=procedure('contract','accept',id,row.id,owner,account,tonumber(row.quote))
    if not accepted then return accepted end
    -- The next cycle delivers actual stock through the same reservation worker as a player.
    return true
end

local function buy(owner,npc,epoch,account,count)
    if count>=npc.minimum then return true end
    local open=db('scalar',[[
        SELECT COUNT(*) FROM frontier_trade_requests WHERE buyer_id=? AND market_id=? AND item_id=?
          AND state IN ('funding','open','refund')
    ]],{owner,npc.market,npc.item})
    local pending=db('scalar',[[
        SELECT COUNT(*) FROM frontier_trade_sales s JOIN frontier_trade_offers o ON o.id=s.offer_id
        WHERE s.buyer_id=? AND o.market_id=? AND o.item_id=?
          AND s.state IN ('stock','payment','reverse','complete') AND s.claimed_at IS NULL
    ]],{owner,npc.market,npc.item})
    if open==nil or pending==nil then return false end
    if tonumber(open)>0 or tonumber(pending)>0 then return true end
    local quantity=npc.target-count
    local offer=db('single',[[
        SELECT id,available FROM frontier_trade_offers WHERE market_id=? AND item_id=?
          AND state='open' AND active_sale IS NULL AND seller_id<>? AND expires_at>UTC_TIMESTAMP()
          AND unit_minor<=? ORDER BY unit_minor,expires_at,id LIMIT 1
    ]],{npc.market,npc.item,owner,npc.price})
    if offer then
        return procedure('sale','buy',key(owner,epoch,'buy'),offer.id,owner,account,
            math.min(quantity,tonumber(offer.available)))~=nil
    end
    local id=key(owner,epoch,'request')
    if not id then return false end
    return db('update',[[
        INSERT INTO frontier_trade_requests
        (id,buyer_id,bank_id,market_id,item_id,quantity,price_minor,budget_minor,state,expires_at,retry_at)
        VALUES(?,?,?,?,?,?,?,?,'funding',DATE_ADD(UTC_TIMESTAMP(),INTERVAL ? HOUR),UTC_TIMESTAMP())
        ON DUPLICATE KEY UPDATE id=id
    ]],{id,owner,account,npc.market,npc.item,quantity,npc.price,quantity*npc.price,cfg.LifetimeHours})~=nil
end

local function sell(owner,npc,epoch,account,count)
    if count<=npc.target then return true end
    local open=db('scalar',[[
        SELECT COUNT(*) FROM frontier_trade_offers WHERE seller_id=? AND item_id=?
          AND state IN ('stock','open','return')
    ]],{owner,npc.item})
    if open==nil then return false end
    if tonumber(open)>0 then return true end
    local id=key(owner,epoch,'offer')
    if not id then return false end
    return db('update',[[
        INSERT INTO frontier_trade_offers
        (id,seller_id,seller_bank,market_id,item_id,quantity,available,unit_minor,expires_at)
        VALUES(?,?,?,?,?,?,?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL ? HOUR))
        ON DUPLICATE KEY UPDATE id=id
    ]],{id,owner,account,npc.market,npc.item,count-npc.target,count-npc.target,npc.price,cfg.LifetimeHours})~=nil
end

local function claim(owner)
    local sales=db('query',[[
        SELECT s.id,s.quantity,o.item_id FROM frontier_trade_sales s
        JOIN frontier_trade_offers o ON o.id=s.offer_id
        WHERE s.buyer_id=? AND s.state='complete' AND s.claimed_at IS NULL LIMIT 10
    ]],{owner})
    local deliveries=db('query',[[
        SELECT d.id,d.quantity,r.item_id FROM frontier_trade_deliveries d
        JOIN frontier_trade_contracts c ON c.id=d.contract_id JOIN frontier_trade_requests r ON r.id=c.request_id
        WHERE r.buyer_id=? AND d.state='complete' AND d.claimed_at IS NULL LIMIT 10
    ]],{owner})
    if not sales or not deliveries then return false end
    for _,group in ipairs({{rows=sales,tableName='frontier_trade_sales'},
        {rows=deliveries,tableName='frontier_trade_deliveries'}}) do
        for _,row in ipairs(group.rows) do
            if inventory:ClaimTradeDelivery(row.id,owner,row.item_id,tonumber(row.quantity)) then
                db('update','UPDATE '..group.tableName..' SET claimed_at=UTC_TIMESTAMP() WHERE id=? AND claimed_at IS NULL',{row.id})
            end
        end
    end
    return true
end

local function cycle(owner,npc,epoch)
    if not valid(npc) or not owner:match('^npc_[a-z0-9_]+$') then return end
    local ok,account=economy:ProvisionTradeNpc(owner)
    if not ok or not claim(owner) then return end
    local active=db('scalar',"SELECT COUNT(*) FROM frontier_trade_contracts WHERE seller_id=? AND state='active'",{owner})
    if active==nil then return end
    local count
    if tonumber(active)>0 then
        local known,available=inventory:GetTradeNpcStock(owner,npc.item)
        if known then count=available end
    else
        count=stock(owner,npc,epoch)
    end
    if count==nil then return end
    local committed=fulfill(owner,npc,epoch,account,count)
    if committed==nil or (not committed and (not buy(owner,npc,epoch,account,count)
        or not sell(owner,npc,epoch,account,count))) then return end
    db('update',[[
        INSERT INTO frontier_trade_npc_ticks(owner_id,last_epoch) VALUES(?,?)
        ON DUPLICATE KEY UPDATE last_epoch=GREATEST(last_epoch,VALUES(last_epoch))
    ]],{owner,epoch})
end

MySQL.ready(function()
    while true do
        if cfg.NpcEnabled then
            local now=db('scalar','SELECT UNIX_TIMESTAMP()')
            if now then
                local epoch=math.floor(tonumber(now)/(math.max(1,cfg.NpcTickMinutes)*60))
                local ticks=db('query','SELECT owner_id,last_epoch FROM frontier_trade_npc_ticks')
                if ticks then
                    local due={}
                    for _,row in ipairs(ticks) do due[row.owner_id]=tonumber(row.last_epoch) end
                    for owner,npc in pairs(cfg.NpcMerchants) do
                        if not due[owner] or due[owner]<epoch then
                            local ok=pcall(cycle,owner,npc,epoch)
                            if not ok then FrontierLib.Log('WARN','frontier_trade','NPC cycle failed',{owner=owner}) end
                        end
                    end
                end
            end
        end
        Wait(60000)
    end
end)

-- Adapter boundary for a future property resource. Only a configured, running provider can grant access.
exports('ResolveTradeBusinessSite',function(source,site,action)
    local provider=cfg.PropertyProvider
    if not provider or GetInvokingResource()~=provider or GetResourceState(provider)~='started' then
        return false,'property_provider_unavailable'
    end
    if type(source)~='number' or type(site)~='string' or #site>80
        or (action~='view' and action~='trade') then return false,'invalid_request' end
    local character=core:GetPlayerCharacterId(source)
    if not character then return false,'character_unavailable' end
    local ok,access,result=pcall(function()
        return exports[provider]:GetTradePropertyAccess(character,site,action)
    end)
    if not ok or access~=true or type(result)~='table' or core:GetPlayerCharacterId(source)~=character then
        return false,'forbidden'
    end
    return true,result
end)

RegisterCommand('handelsnpcbestand',function(source,args)
    if source~=0 and not core:HasPermission(source,'frontier.trade.admin') then return end
    local owner=args[1]
    local count=tonumber(args[2])
    local npc=owner and cfg.NpcMerchants[owner]
    local function report(message)
        if source==0 then print('[FRONTIER TRADE] '..message)
        else TriggerClientEvent('chat:addMessage',source,{args={'Frontier Handel',message}}) end
    end
    if not valid(npc) or not count or count<1 or count>npc.maximum or count~=math.floor(count) then
        report('Verwendung: /handelsnpcbestand <NPC-ID> <Menge>');return
    end
    local ok,current=inventory:GetTradeNpcStock(owner,npc.item)
    if not ok or current+count>npc.maximum then report('Die Bestandsgrenze wäre überschritten.');return end
    local id=db('scalar','SELECT UUID()')
    local saved=id and inventory:ChangeTradeNpcStock(owner,npc.item,count,true,id)
    report(saved and 'NPC-Bestand gebucht.' or 'Die Buchung wurde nicht bestätigt.')
end,false)
