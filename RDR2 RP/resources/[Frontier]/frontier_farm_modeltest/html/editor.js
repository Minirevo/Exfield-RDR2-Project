
(()=>{'use strict';
const $=id=>document.getElementById('b-'+id), panel=document.getElementById('builder'),lab=document.getElementById('modelLab');
let state=null,busy=false;
const presets=[['p_fence_cattle01x','fence','slope'],['p_chickenfence01x','fence','slope'],['p_fence02x','fence','slope'],['p_fence01dx','corner','ground'],['p_watertrough03x','water','ground'],['p_watertroughsml01x','water','ground'],['p_troughtable01x','feed','ground'],['p_haybalestack03x','feed','ground'],['p_haybale03x','decoration','ground'],['p_chicken_coop01x','shelter','fixed'],['p_chicken_coop_post01x','shelter','fixed'],['p_chickencoopcart01x','shelter','fixed'],['p_well02x','decoration','ground']];
for(const p of presets){const o=document.createElement('option');o.value=p[0];o.textContent=p[0];$('preset').append(o)}
$('model').value=presets[0][0];$('preset').onchange=()=>$('model').value=$('preset').value;
async function act(action,data={}){
 if(busy)return;busy=true;
 try{const r=await fetch('https://'+GetParentResourceName()+'/farmBuildAction',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,...data})});const v=await r.json();$('status').textContent=v.message||''}
 catch(e){$('status').textContent='Request failed: '+e.message}finally{busy=false}
}
function render(){
 if(!state)return;
 $('name').value=state.name;
 const list=Array.isArray(state.parts)?state.parts:[];
 $('list').replaceChildren();
 list.forEach((p,i)=>{const o=document.createElement('option');o.value=i+1;o.textContent=(i+1)+'. '+p.role+' · '+p.model+' ('+p.x.toFixed(2)+', '+p.y.toFixed(2)+')';$('list').append(o)});
 $('list').value=state.selected||'';
 const p=list[(state.selected||0)-1];$('edit').hidden=!p;
 if(p)for(const k of ['x','y','z','heading','terrain','role'])$(k).value=p[k];
}
function update(){
 const p=state?.parts?.[(state.selected||0)-1];if(!p)return;
 act('update',{part:{model:p.model,x:Number($('x').value),y:Number($('y').value),z:Number($('z').value),heading:Number($('heading').value),terrain:$('terrain').value,role:$('role').value}})
}
$('apply').onclick=update;
document.querySelectorAll('#builder [data-axis]').forEach(b=>b.onclick=()=>{if(busy)return;const k=b.dataset.axis;$(k).value=(Number($(k).value)+Number(b.dataset.dir)*(k==='heading'?1:Number($('step').value))).toFixed(3);update()});
$('add').onclick=()=>{const model=$('model').value.trim();const p=presets.find(v=>v[0]===model);act('add',{part:{model,x:0,y:0,z:0,heading:0,role:p?.[1]||'decoration',terrain:p?.[2]||'ground'}})};
$('list').onchange=()=>act('select',{index:Number($('list').value)});
for(const k of ['hide','duplicate','delete','relocate'])$(k).onclick=()=>act(k);
for(const k of ['new','clear'])$(k).onclick=()=>{if(confirm('Remove current assembly? Export first if needed.'))act(k)};
$('nameSave').onclick=()=>act('name',{name:$('name').value.trim()});
function exportData(){return {version:1,name:state.name,parts:Array.isArray(state.parts)?state.parts:[]}}
$('export').onclick=()=>{if(state){$('data').value=JSON.stringify(exportData(),null,2);$('data').focus();$('data').select()}};
$('lua').onclick=()=>{if(!state)return;const d=exportData();$('data').value='return {\n  name = '+JSON.stringify(d.name)+',\n  parts = {\n'+d.parts.map(p=>'    {model='+JSON.stringify(p.model)+', x='+p.x+', y='+p.y+', z='+p.z+', heading='+p.heading+', terrain='+JSON.stringify(p.terrain)+', role='+JSON.stringify(p.role)+'},').join('\n')+'\n  }\n}';$('data').focus();$('data').select()};
$('import').onclick=()=>{if(confirm('Replace assembly with imported JSON?'))act('import',{data:$('data').value})};
window.addEventListener('message',e=>{const d=e.data;if(d.type==='buildOpen'){document.body.hidden=false;lab.hidden=true;panel.hidden=false}else if(d.type==='buildHide'){panel.hidden=true;lab.hidden=false;document.body.hidden=true}else if(d.type==='buildState'){state=d.state;render();$('status').textContent=d.message||'Ready'}else if(d.type==='open'){panel.hidden=true;lab.hidden=false}});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!panel.hidden)act('hide')});
})();
