'use strict';
const {chromium,webkit,devices}=require('playwright');
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../dist');
const config=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../vercel.json'),'utf8'));
const api='https://ryzgbajgjctmliwhvezo.supabase.co/functions/v1/customer-push';
const token='a'.repeat(64);
const engineName=process.argv[2];
assert(['chromium','webkit'].includes(engineName),'engine required');
const device=engineName==='chromium'?'Pixel 7':'iPhone 13';
const engine=engineName==='chromium'?chromium:webkit;
const server=http.createServer((req,res)=>{
 const u=new URL(req.url,'http://localhost'),name=u.pathname==='/'?'index.html':u.pathname.slice(1);
 const p=path.resolve(root,name);
 if(!p.startsWith(root+path.sep)||!fs.existsSync(p)||!fs.statSync(p).isFile()){res.writeHead(404).end();return;}
 for(const header of config.headers.find(x=>x.source==='/(.*)').headers)res.setHeader(header.key,header.value);
 res.setHeader('Content-Type',({'.html':'text/html; charset=utf-8','.js':'application/javascript','.css':'text/css','.webmanifest':'application/manifest+json','.png':'image/png'})[path.extname(p)]||'text/plain');
 res.end(fs.readFileSync(p));
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const base='http://127.0.0.1:'+server.address().port;
 let browser;
 try{
 browser=await engine.launch({headless:true});
 const context=await browser.newContext({...devices[device],acceptDownloads:true,serviceWorkers:'block'});
 const page=await context.newPage();let unexpected=[],errors=[],calls=[];
 page.on('pageerror',e=>errors.push(e.message));
 await context.route('**/*',async route=>{
  const url=route.request().url();
  if(url.startsWith(base+'/')||['https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js','https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js'].includes(url))return route.continue();
  if(url!==api){unexpected.push(new URL(url).hostname);return route.abort();}
  const headers={'access-control-allow-origin':'*','access-control-allow-methods':'POST, OPTIONS','access-control-allow-headers':'content-type'};
  if(route.request().method()==='OPTIONS')return route.fulfill({status:204,headers});
  const p=route.request().postDataJSON();calls.push(p.action);
  if(p.token!==token)return route.fulfill({status:400,headers,contentType:'application/json',body:'{"error":"link_unavailable"}'});
  let data={};
  if(p.action==='portal')data={market_name:'مارکێتی تاقیکاری',customer_name:'کڕیاری تاقیکاری',effective_remaining_iqd:75000,totals:[{currency:'IQD',total_debt:100000,paid:25000,remaining:75000}],rows:[],has_more:false};
  else if(p.action==='notifications')data={items:[],notifications:[]};
  else if(p.action==='preferences')data={due_reminders:true,monthly_statements:true,manual_messages:true};
  else if(p.action==='statement')data={market_name:'مارکێتی تاقیکاری',customer_name:'کڕیاری تاقیکاری',from_date:p.from_date,to_date:p.to_date,generated_at:'2026-11-28T12:00:00Z',rows:Array.from({length:40},(_,i)=>({name:'کاڵای تاقیکاری '+(i+1),amount:1000+i,currency:'IQD',date:'2026-11-20'})),row_count:40};
  else return route.fulfill({status:400,headers,contentType:'application/json',body:'{"error":"link_unavailable"}'});
  return route.fulfill({status:200,headers,contentType:'application/json',body:JSON.stringify(data)});
 });
 await page.goto(base+'/');await page.locator('#lockedState').waitFor({state:'visible'});assert.equal(await page.locator('#portalApp').isVisible(),false);assert.equal(calls.length,0);console.log(device+' unauthenticated lock PASS');
 await page.goto(base+'/?token='+token);await page.locator('#portalApp').waitFor({state:'visible'});assert(!page.url().includes('token='));assert((await page.locator('#primaryRemaining').innerText()).includes('75'));console.log(device+' synthetic login and URL scrub PASS');
 for(const [tab,view] of [['transactionsTab','transactionsView'],['receiptsTab','receiptsView'],['notificationsTab','notificationsView'],['accountTab','accountView'],['homeTab','homeView'],['statementTab','statementView']]){
  await page.locator('#'+tab).click();await page.locator('#'+view).waitFor({state:'visible'});
  const sizes=await page.evaluate(()=>({w:document.documentElement.clientWidth,s:document.documentElement.scrollWidth}));assert(sizes.s<=sizes.w+2,view+' overflow '+JSON.stringify(sizes));
 }
 console.log(device+' six tabs and viewport PASS');
 await page.evaluate(()=>{document.getElementById('statementFromDate').value='2026-11-01';document.getElementById('statementToDate').value='2026-11-28';});
 await page.locator('#generatePeriodStatement').click();await page.locator('#periodStatementDocument').waitFor({state:'visible'});assert.equal(await page.locator('#periodStatementRows tr').count(),40);console.log(device+' statement 40 synthetic rows PASS');
 await page.evaluate(()=>{Object.defineProperty(navigator,'share',{value:undefined,configurable:true});Object.defineProperty(navigator,'canShare',{value:undefined,configurable:true});});
 const download=page.waitForEvent('download',{timeout:90000});
 await page.locator('#printPeriodStatement').click();let dl;
 try{dl=await download;}catch(e){throw Error('PDF '+await page.locator('#statementBuilderResult').innerText()+' '+e.message);}
 const file=await dl.path();const pdf=fs.readFileSync(file);
 assert.equal(pdf.subarray(0,5).toString(),'%PDF-');
 const count=[...pdf.toString('latin1').matchAll(/\/Type\s*\/Page\b/g)].length;assert(count>=3);assert(pdf.length>1500);
 console.log(device+' PDF PASS pages='+count+' bytes='+pdf.length);
 assert.equal(errors.length,0,errors.join(';'));assert.equal(unexpected.length,0,unexpected.join(';'));
 await context.close();
 }finally{if(browser)await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
