const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
(async()=>{
    const browser=await chromium.launch({executablePath:process.env.BROWSER_EXECUTABLE||undefined});
    try{
        const page=await browser.newPage();
        const commands=[];
        await page.addInitScript(()=>{window.GetParentResourceName=()=> 'frontier_property';});
        await page.route('https://nui.local/**',route=>route.fulfill({
            path:path.join(__dirname,'..','html',new URL(route.request().url()).pathname.split('/').pop()),
        }));
        await page.route('https://frontier_property/**',route=>{
            const request=route.request();
            const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type'};
            if(request.method()==='OPTIONS')return route.fulfill({status:204,headers});
            commands.push(request.postDataJSON());
            return route.fulfill({json:{ok:true},headers});
        });
        await page.goto('https://nui.local/agent.html');
        const post=(action,data)=>page.evaluate(value=>window.postMessage(value,'*'),{action,data});
        await post('plannerOpen',{radius:75,zones:['test']});
        const canvas=page.locator('#planner-map'),box=await canvas.boundingBox();
        for(const [x,y] of [[.35,.35],[.6,.35],[.6,.6],[.35,.6]]){
            await canvas.click({position:{x:box.width*x,y:box.height*y}});
        }
        await page.getByText('4 Eckpunkte',{exact:false}).waitFor();
        await page.getByRole('button',{name:'Rückgängig'}).click();
        await page.getByText('3 Eckpunkte',{exact:false}).waitFor();
        const check=page.getByRole('button',{name:'Fläche und Preis prüfen'});
        await Promise.all([page.waitForResponse(r=>r.url().endsWith('/plannerAction')),check.click()]);
        assert.equal(commands.at(-1).points.length,3);
        assert.equal(commands.at(-1).zone,'test');
        await post('plannerResult',{area:150,price:5000});
        const buy=page.getByRole('button',{name:'Kauf bestätigen'});
        await Promise.all([page.waitForResponse(r=>r.url().endsWith('/plannerAction')),buy.click()]);
        assert.equal(commands.at(-1).action,'buy');
        console.log('Property plot planner NUI passed');
    }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
