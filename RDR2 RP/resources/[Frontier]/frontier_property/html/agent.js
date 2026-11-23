const main=document.querySelector('main');
const content=document.querySelector('#content');
const notice=document.querySelector('#notice');
let snapshot, section='listings';
const send=(name,body={})=>fetch('https://'+GetParentResourceName()+'/'+name,{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)
});
const number=v=>new Intl.NumberFormat('de-DE',{style:'currency',currency:'USD'}).format(v/100);
const yes=v=>v===true||v===1||v==='1';
function button(text,fn){
    const b=document.createElement('button');b.textContent=text;b.addEventListener('click',fn);return b;
}
function paragraph(text){const p=document.createElement('p');p.textContent=text;return p;}
function confirm(row,text,command){
    row.append(button(text,()=>{
        row.querySelector('.confirm')?.remove();
        const action=document.createElement('div');
        action.className='confirm';
        action.append(paragraph('Möchtest du diesen Vorgang bestätigen?'));
        action.append(button('Bestätigen',async()=>{
            action.remove();
            try{
                const result=await (await send('command',{command})).json();
                notice.textContent=result.ok?'Anfrage gesendet. Die Antwort erscheint im Spielchat.':'Anfrage abgewiesen.';
            }catch{notice.textContent='Die Anfrage konnte nicht gesendet werden.';}
        }),button('Abbrechen',()=>action.remove()));
        row.append(action);
    }));
}
function render(){
    if(!snapshot)return;
    document.querySelector('#town').textContent=snapshot.town;
    for(const b of document.querySelectorAll('nav button')){
        b.hidden=snapshot.catalogue&&b.dataset.section!=='plans';
        b.setAttribute('aria-pressed',b.dataset.section===section);
    }
    content.replaceChildren();
    const rows=snapshot[section]||[];
    if(!snapshot.catalogue&&section==='plans')content.append(button('Bauplan abholen',()=>send('command',{command:'bauplan'})));
    if(!rows.length)content.append(paragraph('Keine Einträge verfügbar.'));
    for(const entry of rows){
        const row=document.createElement('article'),title=document.createElement('h2');
        title.textContent=entry.label||entry.model||entry.key;
        row.append(title);
        if(section==='listings'){
            row.append(paragraph(entry.kind+' · '+number(entry.price)+' · Kaution '+number(entry.deposit)
                +' · '+Math.round(entry.duration/3600)+' Std. · Möblieren '+(entry.furnish?'erlaubt':'nicht erlaubt')));
            if(!entry.available)row.append(paragraph('Belegt oder reserviert'));
            else confirm(row,'Mieten',entry.version?'privatmiete buchen '+entry.id+' '+entry.version
                :'grundmiete buchen '+entry.id+' '+entry.price+' '+entry.deposit);
        }else if(section==='sales'){
            row.append(paragraph(number(entry.price)+(entry.lease?' · Laufender Mietvertrag':' · Ohne laufenden Mietvertrag')));
            if(yes(entry.buyer))confirm(row,entry.lease?'Kaufen und Mietvertrag übernehmen':'Kaufen',
                'grundverkauf kaufen '+entry.id+' '+entry.price+(entry.lease?' miete-ja':''));
            else confirm(row,'Verkauf zustimmen','grundverkauf zustimmen '+entry.id);
        }else if(section==='leases'){
            row.append(paragraph('Aktiver Mietvertrag'));
            if(entry.enter)confirm(row,'Innenraum betreten','grundzimmer '+entry.id);
        }else if(section==='plans'){
            row.append(paragraph('Radius '+entry.radius+' m · Schätzwert '+number(entry.value||0)));
            const select=document.createElement('select');
            for(const property of snapshot.owns||[])select.add(new Option(property.label,property.id));
            if(entry.stages)row.append(paragraph(entry.stages.map(stage=>
                stage.count+' × '+({wood:'Holz',wooden_planks:'Holzbretter',iron_ingot:'Eisenbarren'}[stage.item]||stage.item)
                    +' / '+stage.workSeconds+' s').join(' · ')));
            if(entry.available===false)row.append(paragraph('Gesperrt: '+entry.interior));
            else if(select.options.length){
                row.append(select);
                row.append(button('Vorschau am Bauplatz',async()=>{
                    try{await send('command',{command:'grundbau vorschau '+select.value+' '+entry.key});}
                    catch{notice.textContent='Die Vorschau konnte nicht geöffnet werden.';}
                }));
            }else row.append(paragraph('Kein eigener Bauplatz vorhanden.'));
        }else if(section==='owns')row.append(paragraph('Eigentumsanteil: '+(entry.share/100)+' %'));
        else row.append(paragraph('Lagernummer '+entry.id+' · Im Zielraum auslagern.'));
        content.append(row);
    }
}
document.querySelector('nav').addEventListener('click',event=>{
    const id=event.target.dataset.section;if(id){section=id;render();}
});
document.querySelector('#close').addEventListener('click',()=>send('close'));
document.querySelector('#refresh').addEventListener('click',()=>send('refresh'));
document.addEventListener('keydown',event=>{if(event.key==='Escape'&&!main.hidden)send('close');});
window.addEventListener('message',event=>{
    if(event.data.action==='hint')document.querySelector('#hint').hidden=!event.data.show;
    if(event.data.action==='open'){snapshot=event.data.data;if(snapshot.catalogue)section='plans';main.hidden=false;render();}
    if(event.data.action==='close')main.hidden=true;
});
