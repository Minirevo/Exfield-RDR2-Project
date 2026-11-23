(()=>{
const view=document.querySelector('#management');
const list=view.querySelector('#manage-list');
const details=view.querySelector('#manage-details');
const status=view.querySelector('#manage-status');
let data, selection;
const labels={enter:'Zutritt',construct:'Bauen',furnish:'Möbel platzieren',furnish_move:'Möbel bewegen',furnish_remove:'Möbel einlagern',use_facility:'Einrichtungen nutzen'};
const post=(name,body={})=>fetch('https://'+GetParentResourceName()+'/'+name,{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)
});
function el(tag,text){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;return node;}
function button(label,action){
    const node=el('button',label);node.type='button';node.onclick=action;return node;
}
function change(body){
    status.textContent='Anfrage gesendet …';
    post('manageAction',{id:selection,...body}).catch(()=>{status.textContent='Anfrage fehlgeschlagen.';});
}
function render(){
    list.replaceChildren();details.replaceChildren();
    for(const property of data.properties){
        const role=Number(property.owner)===1?'Eigentum':Number(property.tenant)===1?'Miete':'Freigabe';
        list.append(button(property.label+' · '+role,()=>{selection=property.id;render();}));
    }
    if(!list.children.length)list.append(el('p','Keine zugänglichen Immobilien.'));
    const property=data.properties.find(item=>item.id===selection);
    if(!property)return;
    details.append(el('h2',property.label));
    if(Number(property.owner)!==1)return;
    const name=el('input');name.value=property.label;name.maxLength=64;name.setAttribute('aria-label','Grundstücksname');
    details.append(el('h3','Name'),name,button('Speichern',()=>change({action:'rename',name:name.value})));
    const player=el('select'),capability=el('select');
    player.setAttribute('aria-label','Charakter');
    capability.setAttribute('aria-label','Berechtigung');
    for(const p of data.online)player.add(new Option(p.label,p.character));
    for(const [key,label] of Object.entries(labels))capability.add(new Option(label,key));
    details.append(el('h3','Berechtigungen'),player,capability,button('Freigeben',()=>{
        const target=data.online.find(p=>p.character===player.value);
        if(target)change({action:'permission',permission:capability.value,character:target.character,player:target.source,allow:true});
    }));
    for(const grant of property.grants||[]){
        const row=el('p', (data.online.find(p=>p.character===grant.character)?.label||grant.character)
            +' · '+(labels[grant.permission]||grant.permission)+' ');
        row.append(button('Widerrufen',()=>change({action:'permission',permission:grant.permission,character:grant.character,allow:false})));
        details.append(row);
    }
    const price=el('input'), hours=el('input'), deposit=el('input'), furnish=el('input'), furnishLabel=el('label');
    for(const [field, title, initial] of [[price,'Miete in Cent',''],[hours,'Dauer in Stunden','24'],
            [deposit,'Kaution in Cent','0']]){
        field.type='number';field.value=initial;field.placeholder=title;field.setAttribute('aria-label',title);
    }
    furnish.type='checkbox';furnishLabel.append(furnish,' Möblierung für Mieter erlauben');
    details.append(el('h3','Vermietung'),price,hours,deposit,furnishLabel,
        button('Mietangebot speichern',()=>change({action:'offer',price:Number(price.value),
            hours:Number(hours.value),deposit:Number(deposit.value),furnish:furnish.checked})));
    details.append(button('Mietangebot zurückziehen',()=>{
        const confirm=button('Rücknahme bestätigen',()=>{confirm.remove();change({action:'unlist'});});
        details.append(confirm);
    }));
}
function close(){if(!view.hidden)post('manageClose');}
view.querySelector('#manage-close').onclick=close;
document.addEventListener('keydown',event=>{if(event.key==='Escape')close();});
window.addEventListener('message',event=>{
    const msg=event.data;
    if(msg.action==='manageOpen'){data=msg.data;view.hidden=false;render();}
    if(msg.action==='manageResult')status.textContent=msg.data;
    if(msg.action==='manageClose'){view.hidden=true;selection=undefined;status.textContent='';}
});
})();
