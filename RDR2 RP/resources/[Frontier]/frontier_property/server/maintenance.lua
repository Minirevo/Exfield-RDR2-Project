local _ENV=PropertyRuntime
function tick()
    local now=os.time(); local changed=false; local worked={}
    for src,w in pairs(workers) do
        local s=settlement(w.sid); local b=s and s.buildings[w.bid]
        local valid=b and not b.complete and allowed(s,cid(src),'work') and cid(src)==w.actor and close(src,b)
        if valid then
            local stage=b.stages[b.stage]
            for k,n in pairs(stage.materials) do if (b.delivered[k] or 0)<n then valid=false end end
            if valid then for _,tool in ipairs(stage.tools) do local ok,has=inv:HasItem(src,tool,1); if not ok or not has then valid=false; break end end end
            if valid and cid(src)==w.actor and close(src,b) and not worked[b.id] then
                worked[b.id]=true; b.progress=b.progress+1; changed=true
                if b.progress>=stage.seconds then
                    b.stage=b.stage+1; b.progress=0; b.delivered={}
                    if not b.stages[b.stage] then b.complete=true; workers[src]=nil; notice(src,'Building completed!') else notice(src,'Stage completed.') end
                end
            end
        end
        if not valid then workers[src]=nil; notice(src,'Construction paused: distance, permission, tools or materials.') end
    end
    for _,s in pairs(S.settlements) do if s.status=='active' then
        if now>=s.nextTax then
            local periods=math.floor((now-s.nextTax)/C.TaxPeriod)+1
            if s.debt==0 then s.overdue=s.nextTax end
            s.debt=s.debt+periods*R.tax(s,C); s.nextTax=s.nextTax+periods*C.TaxPeriod; changed=true
        end
        if s.debt>0 and s.overdue and now-s.overdue>=C.TaxGrace and not occupied(s.id) then
            local value=0
            for _,b in pairs(s.buildings) do if b.complete then
                value=value+b.value
                for _,f in pairs(b.furniture) do value=value+C.Furniture[f.item].value end
            end end
            local amount=R.foreclosure(value,s.debt,C); local payments=shares(s,amount)
            if payments then s.status='foreclosing'; queue({kind='foreclose',sid=s.id,payouts=payments}); return end
        end
    end end
    if changed then save() end
end
