'use strict';
const el=(id)=>document.getElementById(id);
const rows=(value)=>Object.values(value||{});
const dollars=new Intl.NumberFormat('de-DE',{style:'currency',currency:'USD',currencyDisplay:'code'});
const money=(value)=>dollars.format(Number(value)/100);
const duration=(value)=>Math.floor(Number(value)/60)+' Min. '+(Number(value)%60)+' Sek.';
let data,pending,retry;
let sequence=0;
let tab='work';

async function nui(url,body={}) {
    const abort=new AbortController();
    const timer=setTimeout(()=>abort.abort(),5000);
    try {
        const response=await fetch('https://'+GetParentResourceName()+'/'+url,{
            method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:abort.signal,
        });
        if(!response.ok) throw new Error('request');
        return await response.json();
    } finally {clearTimeout(timer);}
}
function status(message) {el('status').textContent=message;}
function line(list,text) {
    const node=document.createElement('article');
    node.textContent=text;
    list.append(node);
    return node;
}
function button(label,callback){
    const node=document.createElement('button');
    node.type='button';node.textContent=label;node.disabled=Boolean(pending||retry);
    node.addEventListener('click',callback);return node;
}
function selectTab(next) {
    tab=next;
    for(const button of document.querySelectorAll('[data-tab]')){
        const active=tab===button.dataset.tab;
        button.setAttribute('aria-pressed',String(active));
        el(button.dataset.tab).hidden=!active;
    }
}
function selected(){return rows(data?.recipes).find(recipe=>recipe.id===el('recipe').value);}
function preview(reset=false){
    const recipe=selected();
    if(!recipe)return;
    const n=Number(el('batches').value);
    const mode=el('mode');
    const npc=mode.querySelector('[value=npc]'),player=mode.querySelector('[value=player]');
    npc.disabled=!recipe.npc||data.employee!=='hired';
    player.disabled=!recipe.player;
    if(mode.selectedOptions[0]?.disabled) mode.value=player.disabled?'npc':'player';
    if(reset) el('confirm').checked=false;
    const needs=rows(recipe.inputs).map(item=>item.name+' '+item.count*n+' (vorhanden: '+(data.ingredients[item.id]||0)+')');
    const wage=mode.value==='npc'?Math.ceil(recipe.seconds*n*data.wage/data.wageInterval):0;
    el('preview').textContent=needs.join(', ')+' | Ertrag: '+recipe.quantity*n+' × '+recipe.output+
        ' | Dauer: '+duration(recipe.seconds*n)+' | Lohn: '+money(wage);
    el('order').querySelector('button').disabled=Boolean(pending||retry||mode.selectedOptions[0]?.disabled);
}
function render(){
    if(!data)return;
    const blocked=Boolean(pending||retry);
    el('order').hidden=!!data.legacy;
    if(data.legacy){el('work').querySelector('h2').textContent='Legacy production — collect or cancel existing jobs';el('hire').hidden=true;}
    const old=el('recipe').value;
    el('recipe').replaceChildren(...rows(data.recipes).map(r=>new Option(r.name,r.id)));
    if(rows(data.recipes).some(r=>r.id===old))el('recipe').value=old;
    el('batches').max=data.maxBatches;
    preview();
    for(const id of ['jobs','goods','recipe-list'])el(id).replaceChildren();
    for(const recipe of rows(data.recipes)){
        line(el('recipe-list'),recipe.name+' · '+recipe.description+' · '+rows(recipe.inputs)
            .map(i=>i.count+' × '+i.name).join(', ')+' → '+recipe.quantity+' × '+recipe.output+
            ' · '+duration(recipe.seconds)+' · '+[recipe.player?'Selbstbetrieb':'',recipe.npc?'NPC-Betrieb':''].filter(Boolean).join(' / '));
    }
    for(const job of rows(data.jobs)){
        const node=line(el('jobs'),job.name+' · '+job.output_units+' Stück · '+(job.mode==='npc'?'NPC':'Selbstbetrieb')+
            ' · '+job.status+' · '+duration(job.remaining)+' verbleibend'+(Number(job.wage_minor)?' · Lohn: '+money(job.wage_minor):''));
        const progress=document.createElement('progress');
        progress.max=Number(job.duration_seconds);
        progress.value=Math.max(0,progress.max-Number(job.remaining));
        progress.setAttribute('aria-label','Produktionsfortschritt');
        node.append(progress);
        if(job.state==='unpaid')node.append(button('Lohn erneut prüfen',()=>submit('resume',{job:job.id})),
            button('Stornieren und Zutaten zurückgeben',()=>submit('cancel',{job:job.id})));
        else if(job.state==='running')node.append(button('Auftrag abbrechen und Zutaten zurückgeben',
            ()=>submit('cancel',{job:job.id})));
        else if(job.state==='return'){
            const note=document.createElement('p');
            note.textContent='Zutaten werden zurückgegeben …';
            node.append(note);
        }
    }
    for(const item of rows(data.goods)){
        const node=line(el('goods'),item.name+' × '+item.count+(item.description?' · '+item.description:''));
        const amount=document.createElement('input');
        amount.type='number';amount.min='1';amount.max=String(item.count);amount.value='1';
        amount.setAttribute('aria-label','Menge '+item.name);
        node.append(amount,button('Abholen',()=>{
            if(amount.reportValidity())submit('collect',{item:item.id,quantity:Number(amount.value)});
        }));
    }
    if(!el('jobs').childElementCount)line(el('jobs'),'Keine Aufträge.');
    if(!el('goods').childElementCount)line(el('goods'),'Das Produktionslager ist leer.');
    el('usage').textContent=data.units+' von '+data.capacity+' Einheiten belegt';
    el('collect').disabled=blocked||!Number(data.units);
    el('employee').textContent=({none:'Kein Mitarbeiter eingestellt.',hired:'Mitarbeiter eingestellt.',unpaid:'Mitarbeiter wartet auf Lohn.'})[data.employee];
    el('wages').textContent='Lohnsatz: '+money(data.wage)+' pro '+duration(data.wageInterval)+' Echtzeit, anteilig pro Auftrag.';
    el('balance').textContent='Verfügbares Bankguthaben: '+money(data.balance);
    el('hire').disabled=blocked||data.employee!=='none';
    el('dismiss').disabled=blocked||data.employee==='none';
    el('refresh').disabled=blocked;
    el('retry').hidden=!retry;
    el('retry').disabled=Boolean(pending);
}
async function send(request){
    if(pending||!data)return;
    pending=request;
    if(!request.quiet)status('Anfrage läuft …');
    render();
    try{
        const ack=await nui('request',request);
        if(!ack.ok&&pending===request){
            pending=null;retry=request;status('Anfrage nicht bestätigt. Bitte erneut versuchen.');render();
        }
    }catch{
        if(pending!==request)return;
        pending=null;retry=request;status('Keine Bestätigung. Wiederhole dieselbe Anfrage.');render();
    }
}
function submit(action,values={}){
    if(!retry&&!pending)send({seq:++sequence,action,data:values});
}
window.addEventListener('message',({data:event})=>{
    if(event?.type==='open'){
        data=event.snapshot;pending=retry=null;document.body.hidden=false;
        status('');selectTab('work');render();el('close').focus();
    }else if(event?.type==='close'){
        data=pending=retry=null;document.body.hidden=true;
    }else if(event?.type==='response'&&pending?.seq===event.seq){
        const request=pending;
        pending=null;retry=event.retry?request:null;
        if(event.snapshot)data=event.snapshot;
        if(event.ok&&request.action==='start')el('confirm').checked=false;
        if(!request.quiet||!event.ok)status(event.message||'');
        render();
    }
});
const close=()=>nui('close').catch(()=>status('Das Fenster konnte nicht geschlossen werden.'));
el('close').addEventListener('click',close);
document.addEventListener('keydown',event=>{
    if(event.key==='Escape'&&!document.body.hidden){event.preventDefault();close();}
});
for(const button of document.querySelectorAll('[data-tab]'))button.addEventListener('click',()=>selectTab(button.dataset.tab));
for(const id of ['recipe','batches','mode'])el(id).addEventListener('input',()=>preview(true));
el('order').addEventListener('submit',event=>{
    event.preventDefault();
    submit('start',{recipe:el('recipe').value,batches:Number(el('batches').value),mode:el('mode').value,confirm:el('confirm').checked});
});
el('refresh').addEventListener('click',()=>submit('refresh'));
el('retry').addEventListener('click',()=>{if(retry)send(retry);});
el('collect').addEventListener('click',()=>submit('collect'));
el('hire').addEventListener('click',()=>submit('hire'));
el('dismiss').addEventListener('click',()=>submit('dismiss'));
setInterval(()=>{
    if(data&&!pending&&!retry&&rows(data.jobs).some(job=>!['complete','cancelled','rejected','unpaid'].includes(job.state))){
        send({seq:++sequence,action:'refresh',data:{},quiet:true});
    }
},8000);
nui('ready').catch(()=>{});
