const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
(async()=>{
    const browser=await chromium.launch({executablePath:process.env.BROWSER_EXECUTABLE||undefined});
    try{
        const page=await browser.newPage(),records=[],errors=[];
        page.on('pageerror',e=>errors.push(e.message));
        await page.addInitScript(()=>{window.GetParentResourceName=()=> 'frontier_property';});
        await page.route('https://nui.local/**',route=>route.fulfill({
            path:path.join(__dirname,'..','html',new URL(route.request().url()).pathname.split('/').pop()),
        }));
        await page.route('https://frontier_property/**',route=>{
            const request=route.request(),headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type'};
            if(request.method()==='OPTIONS')return route.fulfill({status:204,headers});
            records.push(request.postDataJSON());
            return route.fulfill({json:{ok:true},headers});
        });
        await page.goto('https://nui.local/agent.html');
        const post=(action,data)=>page.evaluate(value=>window.postMessage(value,'*'),{action,data});
        await post('manageOpen',{properties:[{id:3,label:'Hof',owner:1,grants:[]},{id:4,label:'Zimmer',tenant:1}],online:[]});
        await page.getByRole('button',{name:'Zimmer · Miete'}).click();
        assert.equal(await page.getByRole('button',{name:'Speichern',exact:true}).count(),0);
        await page.getByRole('button',{name:'Hof · Eigentum'}).click();
        await page.getByRole('textbox',{name:'Grundstücksname'}).fill("Wolf's Rest");
        await Promise.all([page.waitForResponse(r=>r.url().endsWith('/manageAction')),
            page.getByRole('button',{name:'Speichern',exact:true}).click()]);
        assert.deepEqual(records.at(-1),{id:3,action:'rename',name:"Wolf's Rest"});
        await post('manageClose');
        const points=[{x:0,y:0},{x:10,y:0},{x:10,y:10}];
        await post('walkSurvey',{points,radius:75,valid:true,area:50,price:1750});
        await page.getByText('50.0 m²',{exact:false}).waitFor();
        await post('walkSurveyEnd');
        await post('plannerOpen',{walk:true,radius:75,zones:['world'],points});
        await page.locator('#planner-map').click({position:{x:40,y:40}});
        await page.getByText('3 Eckpunkte',{exact:false}).waitFor();
        await post('plannerClose');
        await post('open',{town:'Baukatalog',catalogue:true,plans:[{key:'cabin',label:'Blockhaus',radius:5,
            value:100,available:false,interior:'Ungeprüft'}],owns:[{id:3,label:'Hof'}]});
        await page.getByText('Gesperrt: Ungeprüft').waitFor();
        assert.equal(await page.getByRole('button',{name:'Vorschau am Bauplatz'}).count(),0);
        assert.deepEqual(errors,[]);
        console.log('Property overhaul menu passed');
    }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
