local _ENV=PropertyRuntime
function buildingStages(e,i)
    if e.farm=='field' then return {{label='Prepare soil',materials={},tools={'farm_hoe'},seconds=e.seconds}} end
    local a,b={},{}
    for k,n in pairs(e.materials) do local first=math.max(1,math.floor(n*0.4)); a[k]=first; if n>first then b[k]=n-first end end
    local stages={{label='Foundation',materials=a,tools={'property_hammer'},seconds=math.max(10,math.floor(e.seconds*0.4))},
        {label='Structure',materials=b,tools={'property_hammer','property_saw'},seconds=math.max(10,math.floor(e.seconds*0.6))}}
    if i then stages[#stages+1]={label='Interior',materials=i.materials,tools={'property_hammer','property_saw'},seconds=i.seconds} end
    return stages
end
function buildingInfo(b)
    return {id=b.id,exterior=b.exterior,interior=b.interior,x=b.x,y=b.y,z=b.z,heading=b.heading,radius=b.radius,
        stage=b.stage,stages=b.stages,delivered=b.delivered,progress=b.progress,complete=b.complete,capacity=C.Exteriors[b.exterior].slots,furniture=b.furniture,locked=b.locked}
end
