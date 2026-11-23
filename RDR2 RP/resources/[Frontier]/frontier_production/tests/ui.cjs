'use strict';
const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
async function main(){
    const browser=await chromium.launch({executablePath:process.env.BROWSER_EXECUTABLE||undefined});
    try{
        const page=await browser.newPage();
        const actions=[],errors=[];
        page.on('pageerror',error=>errors.push(error.message));
        await page.addInitScript(()=>{window.GetParentResourceName=()=> 'frontier_production';});
        await page.route('https://nui.local/**',route=>route.fulfill({
            path:path.join(process.cwd(),'html',new URL(route.request().url()).pathname.split('/').pop()),
        }));
        const state={employee:'hired',balance:5000,wage:200,wageInterval:3600,maxBatches:10,units:2,capacity:100,
            ingredients:{flour:6,water:2},jobs:[],goods:[{id:'bread',name:'Brot',count:2}],
            recipes:[{id:'bake',name:'Brot backen',description:'Backen',seconds:300,output:'Brot',quantity:2,
                inputs:[{id:'flour',name:'Mehl',count:2},{id:'water',name:'Wasser',count:1}],player:true,npc:true}]};
        const send=(event)=>page.evaluate(value=>window.postMessage(value,'*'),event);
        await page.route('https://frontier_production/**',async route=>{
            const request=route.request();
            const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type',
                'Access-Control-Allow-Methods':'POST, OPTIONS'};
            if(request.method()==='OPTIONS')return route.fulfill({status:204,headers});
            const op=new URL(request.url()).pathname.slice(1);
            const value=request.postDataJSON();
            if(op==='request')actions.push(value);
            await route.fulfill({json:{ok:true},headers});
            if(op==='close')await send({type:'close'});
            if(op==='request')await send({type:'response',ok:true,seq:value.seq,snapshot:state,message:'Gespeichert.'});
        });
        await page.goto('https://nui.local/index.html');
        assert(await page.locator('body').isHidden());
        await send({type:'open',snapshot:state});
        await page.getByText(/Mehl 2/).waitFor();
        await page.selectOption('#mode','npc');
        assert.match(await page.locator('#preview').textContent(),/0,17/);
        await page.getByRole('button',{name:'Auftrag starten',exact:true}).click();
        assert.equal(actions.length,0);
        await page.locator('#confirm').check();
        await page.getByRole('button',{name:'Auftrag starten',exact:true}).click();
        await page.getByText('Gespeichert.').waitFor();
        assert.deepEqual(actions[0].data,{recipe:'bake',batches:1,mode:'npc',confirm:true});
        await page.getByRole('button',{name:'Rezepte',exact:true}).click();
        await page.getByRole('heading',{name:'Rezeptbuch'}).waitFor();
        await page.getByRole('button',{name:'Mitarbeiter',exact:true}).click();
        await page.getByText(/Lohnsatz/).waitFor();
        await page.getByRole('button',{name:'Lager',exact:true}).click();
        await page.getByRole('button',{name:'Abholen',exact:true}).click();
        for(let i=0;i<100&&actions.length<2;i++)await new Promise(resolve=>setTimeout(resolve,20));
        assert.deepEqual(actions[1].data,{item:'bread',quantity:1});

        state.jobs=[{id:'00000000-0000-0000-0000-000000000001',name:'Brot backen',
            output_units:2,mode:'player',status:'In Arbeit',state:'running',remaining:120,duration_seconds:300,wage_minor:0}];
        await send({type:'open',snapshot:state});
        await page.getByRole('button',{name:'Auftrag abbrechen und Zutaten zurückgeben'}).click();
        for(let i=0;i<100&&actions.length<3;i++)await new Promise(resolve=>setTimeout(resolve,20));
        assert.deepEqual(actions[2].data,{job:'00000000-0000-0000-0000-000000000001'});

        await page.keyboard.press('Escape');
        await page.locator('body').waitFor({state:'hidden'});
        assert.deepEqual(errors,[]);
        console.log('Production German tabs, confirmation, wages, collection and Escape passed');
    }finally{await browser.close();}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
