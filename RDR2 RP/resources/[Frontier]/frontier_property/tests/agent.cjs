const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');

(async()=>{
    const browser=await chromium.launch({executablePath:process.env.BROWSER_EXECUTABLE||undefined});
    try{
        const page=await browser.newPage();
        const commands=[],errors=[];
        page.on('pageerror',error=>errors.push(error.message));
        await page.addInitScript(()=>{window.GetParentResourceName=()=> 'frontier_property';});
        await page.route('https://nui.local/**',route=>route.fulfill({
            path:path.join(__dirname,'..','html',new URL(route.request().url()).pathname.split('/').pop()),
        }));
        await page.route('https://frontier_property/**',route=>{
            const request=route.request();
            const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type'};
            if(request.method()==='OPTIONS')return route.fulfill({status:204,headers});
            const operation=new URL(request.url()).pathname.slice(1);
            commands.push([operation,request.postDataJSON()]);
            return route.fulfill({json:{ok:true},headers});
        });
        await page.goto('https://nui.local/agent.html');
        const data={town:'Valentine',
            listings:[{label:'Testhaus',kind:'Staatlich',id:3,price:1000,deposit:500,duration:3600,furnish:true,available:true},
                {label:'Belegt',kind:'Privat',price:2000,deposit:100,duration:3600,available:false}],
            sales:[{id:9,label:'Mietobjekt',price:20000,lease:7,buyer:true}],
            owns:[{id:12,label:'Land',share:5000}],recovery:[{id:2,model:'bett'}],
            leases:[{id:3,label:'Testzimmer',enter:true}],plans:[{key:'huette',label:'Hütte',radius:4,value:9000}]};
        await page.evaluate(input=>window.postMessage({action:'open',data:input},'*'),data);
        await page.getByRole('heading',{name:'Testhaus'}).waitFor();
        assert.equal(await page.getByRole('button',{name:'Mieten',exact:true}).count(),1);
        await page.getByRole('button',{name:'Mieten',exact:true}).click();
        await page.getByRole('button',{name:'Abbrechen'}).click();
        assert.equal(commands.length,0);
        await page.getByRole('button',{name:'Mieten',exact:true}).click();
        await page.getByRole('button',{name:'Bestätigen'}).click();
        await page.getByText('Anfrage gesendet.',{exact:false}).waitFor();
        assert.deepEqual(commands.at(-1),['command',{command:'grundmiete buchen 3 1000 500'}]);
        await page.getByRole('button',{name:'Verkäufe',exact:true}).click();
        await page.getByRole('button',{name:'Kaufen und Mietvertrag übernehmen'}).click();
        await Promise.all([page.waitForResponse(r=>r.url()==='https://frontier_property/command'),
            page.getByRole('button',{name:'Bestätigen'}).click()]);
        assert.deepEqual(commands.at(-1),['command',{command:'grundverkauf kaufen 9 20000 miete-ja'}]);
        await page.getByRole('button',{name:'Rückgabelager'}).click();
        await page.getByRole('heading',{name:'bett'}).waitFor();
        await page.getByRole('button',{name:'Meine Mietobjekte'}).click();
        await page.getByRole('heading',{name:'Testzimmer'}).waitFor();
        await page.getByRole('button',{name:'Innenraum betreten'}).click();
        await Promise.all([page.waitForResponse(r=>r.url()==='https://frontier_property/command'),
            page.getByRole('button',{name:'Bestätigen'}).click()]);
        assert.deepEqual(commands.at(-1),['command',{command:'grundzimmer 3'}]);
        await page.getByRole('button',{name:'Baupläne'}).click();
        await Promise.all([page.waitForResponse(r=>r.url()==='https://frontier_property/command'),
            page.getByRole('button',{name:'Vorschau am Bauplatz'}).click()]);
        assert.deepEqual(commands.at(-1),['command',{command:'grundbau vorschau 12 huette'}]);
        assert.deepEqual(errors,[]);
        console.log('Property agent NUI passed');
    }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
