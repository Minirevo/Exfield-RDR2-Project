(()=>{
const planner=document.querySelector('#planner');
const map=document.querySelector('#planner-map');
const pen=map.getContext('2d');
const zone=document.querySelector('#planner-zone');
const status=document.querySelector('#planner-status');
const buy=document.querySelector('#planner-buy');
const quote=document.querySelector('#planner-quote');
const undo=document.querySelector('#planner-undo');
let radius=75,points=[],history=[],drag=-1,pending=false,checked=false;

function plannerSend(name,data={}){
    return fetch('https://'+GetParentResourceName()+'/'+name,{
        method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)
    });
}
function draw(){
    const size=map.width,middle=size/2,scale=middle/radius;
    pen.clearRect(0,0,size,size);
    pen.strokeStyle='#625341';pen.lineWidth=1;
    for(let i=-radius;i<=radius;i+=15){
        const p=middle+i*scale;
        pen.beginPath();pen.moveTo(p,0);pen.lineTo(p,size);pen.moveTo(0,p);pen.lineTo(size,p);pen.stroke();
    }
    pen.fillStyle='#e3ceb0';pen.fillText('N',middle+7,14);
    pen.fillRect(middle-2,middle-2,4,4);
    if(points.length===0)return;
    pen.beginPath();
    points.forEach((p,i)=>{
        const x=middle+p.x*scale,y=middle-p.y*scale;
        if(i===0)pen.moveTo(x,y);else pen.lineTo(x,y);
    });
    if(points.length>=3){pen.closePath();pen.fillStyle='#bb945e55';pen.fill();}
    pen.strokeStyle=checked?'#acdb94':'#f2c883';pen.lineWidth=2;pen.stroke();
    for(const p of points){
        pen.beginPath();pen.arc(middle+p.x*scale,middle-p.y*scale,5,0,Math.PI*2);
        pen.fillStyle='#f2c883';pen.fill();
    }
}
function controls(){
    quote.disabled=pending||points.length<3||!zone.value;
    buy.disabled=pending||!checked;
    undo.disabled=pending||!history.length;
    zone.disabled=pending;
}
function change(){
    checked=false;
    let area=0;
    if(points.length>=3)points.forEach((a,i)=>{const b=points[(i+1)%points.length];area+=a.x*b.y-a.y*b.x;});
    const hint=points.length>=3?' · Vorschau '+Math.abs(area/2).toFixed(1)+' m²':'';
    status.textContent=points.length+' Eckpunkte'+hint+'. Preis und Konflikte prüft der Server.';
    draw();controls();
}
function snapshot(){history.push(points.map(p=>({...p})));if(history.length>64)history.shift();}
function location(event){
    const r=map.getBoundingClientRect();
    const limit=value=>Math.round(Math.max(-radius,Math.min(radius,value))*10)/10;
    return {x:limit((event.clientX-r.left)*2*radius/r.width-radius),
        y:limit(radius-(event.clientY-r.top)*2*radius/r.height)};
}
function vertex(point){
    const range=radius*18/map.getBoundingClientRect().width;
    return points.findIndex(p=>Math.hypot(p.x-point.x,p.y-point.y)<range);
}
map.addEventListener('pointerdown',event=>{
    if(pending||event.button!==0)return;
    const p=location(event),i=vertex(p);
    if(i<0&&points.length>=64)return;
    snapshot();drag=i;
    if(i<0)points.push(p);
    else map.setPointerCapture(event.pointerId);
    change();
});
map.addEventListener('pointermove',event=>{
    if(drag<0||pending)return;
    points[drag]=location(event);change();
});
for(const name of ['pointerup','pointercancel'])map.addEventListener(name,()=>{drag=-1;});
map.addEventListener('contextmenu',event=>{
    event.preventDefault();
    if(pending)return;
    const i=vertex(location(event));
    if(i>=0){snapshot();points.splice(i,1);change();}
});
undo.onclick=()=>{if(!pending&&history.length){points=history.pop();change();}};
zone.onchange=change;
async function request(action){
    if(pending)return;
    pending=true;checked=false;status.textContent='Server prüft …';controls();
    try{
        const result=await (await plannerSend('plannerAction',{action,zone:zone.value,points})).json();
        if(!result.ok)throw Error();
    }catch{pending=false;status.textContent='Verbindung unterbrochen.';controls();}
}
quote.onclick=()=>request('quote');
buy.onclick=()=>request('buy');
async function closePlanner(){
    if(!planner.hidden)await plannerSend('plannerClose');
}
document.querySelector('#planner-close').onclick=closePlanner;
document.addEventListener('keydown',event=>{if(event.key==='Escape')closePlanner();});
window.addEventListener('message',event=>{
    if(event.data.action==='plannerOpen'){
        planner.hidden=false;points=[];history=[];pending=false;radius=event.data.data.radius;drag=-1;
        zone.replaceChildren(...event.data.data.zones.map(name=>new Option(name==='world'?'Spielwelt':name,name)));
        change();
        if(!zone.value)status.textContent='Auf diesem Server ist keine Kaufzone freigegeben.';
    }else if(event.data.action==='plannerClose')planner.hidden=true;
    else if(event.data.action==='plannerResult'&&!planner.hidden){
        const result=event.data.data;
        pending=false;checked=Number.isFinite(result.price);
        status.textContent=checked
            ? new Intl.NumberFormat('de-DE',{maximumFractionDigits:2}).format(result.area)+' m² · '
                +new Intl.NumberFormat('de-DE',{style:'currency',currency:'USD'}).format(result.price/100)
            : result.message;
        draw();controls();
    }
});
})();
